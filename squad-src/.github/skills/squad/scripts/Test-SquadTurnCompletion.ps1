#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Verifies current-turn dispatch proof in one read-only call.
.DESCRIPTION
    AI cost: none. A single/member proof reuses the ordinary writer payload
    (runId, historyRecords, stateAdvance.activeRoles). Each record may additionally
    specify role, turn, findingsOnly and decisionRef for documented consultative
    stages. ExpectedTurn is the actual writer receipt's turn, never inferred from
    an old history file. Artifact existence, roster roots, exact history entries,
    consumption, active agents, admission links and the ledger are read from disk.
    A federation proof has subSquads [{name, proofPath, turn, decisionRefs: []}],
    each pointing to an inner proof; both levels are checked.
    A ledger-only warning is disclosed, never relabelled PASS. Missing dispatch
    proof or malformed accounting fails closed. No files are written.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SquadRoot,
    [Parameter(Mandatory)][string]$ProofPath,
    [Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$ExpectedTurn,
    [string]$RepoRoot = (Get-Location).ProviderPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force

function Get-Entry {
    param([string]$Text)
    [regex]::Matches($Text, '(?ms)^### (?<heading>[^\r\n]+)\r?\n(?<body>.*?)(?=^### |\z)')
}

function Get-EntryField {
    param([string]$Text, [string]$Name)
    $match = [regex]::Match($Text, '(?m)^\* ' + [regex]::Escape($Name) + ':[ \t]*(?<value>[^\r\n]*)')
    if ($match.Success) { $match.Groups['value'].Value.Trim().Trim('`') } else { '' }
}

function Get-Decision {
    param([string]$Root, [string]$Reference)
    Get-SquadDecision -RepoRoot $RepoRoot -SquadRoot $Root -Reference $Reference
}

function Get-RecordActiveSet {
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Record,
        [Parameter(Mandatory)][object[]]$Roster
    )
    $identities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $null = $identities.Add([string]$Record.agent)
    $member = if ($Record.Contains('memberName')) { [string]$Record.memberName } else { '' }
    $role = if ($Record.Contains('role')) { [string]$Record.role } else { '' }
    $rows = @(
        $Roster | Where-Object {
            $agents = @([string]$_['Agent Name (Primary)']) + @(
                ([string]$_['Alternate Agents'] -split ',\s*') | Where-Object { $_ -and $_ -notin @('-', [string][char]0x2014) }
            )
            $agents -ccontains [string]$Record.agent -and
            (-not $member -or [string]$_['Member Name'] -ceq $member) -and
            (-not $role -or [string]$_.Role -ceq $role)
        }
    )
    if ($rows.Count -eq 1) { $null = $identities.Add([string]$rows[0].Role) }
    @($identities)
}

try {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $SquadRoot = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $SquadRoot
    $proof = Get-Content -LiteralPath $ProofPath -Raw | ConvertFrom-Json -AsHashtable
    if ($proof -isnot [Collections.IDictionary]) { throw 'Proof must be a JSON object.' }
    if ($proof.Contains('squadRoot') -and
        (Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $proof.squadRoot) -ne $SquadRoot) { throw 'Proof belongs to a different squad root.' }
    if ($proof.Contains('turn') -and $proof.turn -ne $ExpectedTurn) { throw 'Proof turn does not match the expected writer turn.' }
    $stateText = [IO.File]::ReadAllText((Join-Path $SquadRoot 'state.json'))
    $state = $stateText | ConvertFrom-Json -AsHashtable
    $updated = [Text.Json.Nodes.JsonNode]::Parse($stateText)['updated'].ToString()
    if ($state.turn -ne $ExpectedTurn -or -not $state.updated) { throw 'state.json did not advance to the expected turn.' }
    if ($proof.Contains('expectedUpdatedBefore') -and
        [DateTimeOffset]::Parse($updated, [Globalization.CultureInfo]::InvariantCulture) -le [DateTimeOffset]::Parse($proof.expectedUpdatedBefore, [Globalization.CultureInfo]::InvariantCulture)) { throw 'state.json updated did not advance.' }
    $verified = [Collections.Generic.List[object]]::new()
    $warnings = [Collections.Generic.List[string]]::new()

    if (Test-Path -LiteralPath (Join-Path $SquadRoot 'federation.md')) {
        if (-not $proof.Contains('subSquads') -or $proof.subSquads -isnot [array] -or -not $proof.subSquads.Count) {
            throw 'Federation completion requires inner proof for every selected sub-squad.'
        }
        $tables = @(Read-SquadTables (Join-Path $SquadRoot 'federation.md') | Where-Object { 'Sub-squad' -in $_.Header -and 'Location' -in $_.Header })
        if ($tables.Count -ne 1) { throw 'Missing federation registry.' }
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($member in $proof.subSquads) {
            if ($member -isnot [Collections.IDictionary] -or -not $member.Contains('name') -or
                -not $member.Contains('proofPath') -or -not $member.Contains('turn') -or
                $member.name -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or -not $names.Add($member.name)) { throw 'Invalid or duplicate selected sub-squad proof.' }
            $rows = @($tables[0].Rows | Where-Object { $_['Sub-squad'] -ceq $member.name })
            if ($rows.Count -ne 1 -or $rows[0].Kind -ne 'in-repo' -or
                ($rows[0].Location -replace '\\', '/').TrimEnd('/') -cne "members/$($member.name)") { throw 'Selected sub-squad is not registered at its own root.' }
            $memberRoot = Join-Path $SquadRoot 'members' $member.name
            $result = Invoke-SquadLocalScript -Name 'Test-SquadTurnCompletion.ps1' -Arguments @(
                '-RepoRoot', $RepoRoot, '-SquadRoot', $memberRoot, '-ProofPath', $member.proofPath, '-ExpectedTurn', [string]$member.turn)
            if ($result.exitCode -ne 0) { throw "Inner proof failed for '$($member.name)': $($result.stderr.Trim())" }
            $inner = $result.stdout | ConvertFrom-Json -AsHashtable
            if ($inner.status -ne 'ok' -or $inner.verified -ne $true -or $inner.dispatchEntries -lt 1) { throw 'An inner summary or empty run is not dispatch proof.' }
            $historyPath = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $SquadRoot 'history' "$($member.name).md")
            $entries = @(Get-Entry ([IO.File]::ReadAllText($historyPath)) | Where-Object { (Get-EntryField $_.Groups['body'].Value 'Turn') -eq [string]$ExpectedTurn })
            if ($entries.Count -ne 1) { throw "Missing federation history for '$($member.name)' on turn $ExpectedTurn." }
            if (-not $member.Contains('decisionRefs') -or $member.decisionRefs -isnot [array] -or -not $member.decisionRefs.Count) { throw 'Federation history needs explicit inner decision references.' }
            foreach ($reference in $member.decisionRefs) {
                $null = Get-Decision -Root $memberRoot -Reference $reference
                if (-not $entries[0].Groups['body'].Value.Contains($reference)) { throw "Federation history omitted inner decision '$reference'." }
            }
            foreach ($warning in $inner.warnings) { $warnings.Add("$($member.name): $warning") }
            $verified.Add([ordered]@{ squad = $member.name; turn = $member.turn; history = $historyPath; dispatchEntries = $inner.dispatchEntries })
        }
        $active = @($state.activeSubSquads)
        if ($active.Count -ne $names.Count -or @($active | Where-Object { -not $names.Contains($_) }).Count) { throw 'Federation activeSubSquads does not match actual selected runs.' }
        [ordered]@{ status = 'ok'; verified = $true; kind = 'federation'; squadRoot = $SquadRoot; turn = $ExpectedTurn; subSquads = $verified.ToArray(); warnings = $warnings.ToArray() } | ConvertTo-Json -Depth 8 -Compress
        exit 0
    }

    if (-not $proof.Contains('runId') -or -not $proof.Contains('historyRecords') -or $proof.historyRecords -isnot [array] -or
        -not $proof.Contains('stateAdvance') -or -not $proof.stateAdvance.Contains('activeRoles') -or $proof.stateAdvance.activeRoles -isnot [array]) {
        throw 'Use the actual handoff payload: runId, historyRecords, stateAdvance.activeRoles.'
    }
    $activeExpected = @($proof.stateAdvance.activeRoles)
    $activeActual = @($state.activeRoles)
    if ($activeActual.Count -ne $activeExpected.Count -or @($activeActual | Where-Object { $_ -cnotin $activeExpected }).Count) { throw 'state.json activeRoles does not match the handoff.' }
    $roster = @(Get-SquadRoster $SquadRoot)
    $recordedActiveIdentities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $allHistory = @(
        Get-ChildItem -LiteralPath (Join-Path $SquadRoot 'history') -File -Filter '*.md' |
            ForEach-Object { [IO.File]::ReadAllText($_.FullName) }
    ) -join "`n"
    $consumptionKeys = @('model', 'model_source', 'priced_as', 'model_tier', 'internal_turns', 'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens', 'basis')
    $matchedEntries = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in $proof.historyRecords) {
        if ($record -isnot [Collections.IDictionary] -or -not $record.Contains('agent') -or
            $record.agent -isnot [string] -or $record.agent -match '[/\\<>:\r\n\x00]' -or
            [string]::IsNullOrWhiteSpace($record.agent) -or $record.agent -ceq 'Squad Scribe') { throw 'A real dispatched agent identity is required.' }
        $turn = if ($record.Contains('turn')) { $record.turn } else { $ExpectedTurn }
        if ($turn -isnot [int] -and $turn -isnot [long] -or $turn -lt 1 -or $turn -gt $ExpectedTurn) { throw 'Invalid dispatch turn.' }
        $activeIdentities = @(Get-RecordActiveSet -Record $record -Roster $roster)
        if ($turn -eq $ExpectedTurn) {
            foreach ($identity in $activeIdentities) { $null = $recordedActiveIdentities.Add($identity) }
            if (@($activeActual | Where-Object { $_ -cin $activeIdentities }).Count -eq 0) {
                throw "Current dispatch '$($record.agent)' is missing from activeRoles."
            }
        }
        $historyPath = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $SquadRoot 'history' "$($record.agent).md")
        $text = [IO.File]::ReadAllText($historyPath)
        if ($text -cnotmatch ('(?m)^# History: ' + [regex]::Escape($record.agent) + '\r?$')) { throw 'History header does not match the dispatched identity.' }
        $candidates = @(
            Get-Entry $text | Where-Object {
                $body = $_.Groups['body'].Value
                (Get-EntryField $body 'Turn') -eq [string]$turn -and
                (-not $record.Contains('memberName') -or (Get-EntryField $body 'Member Name') -ceq $record.memberName) -and
                (-not $record.Contains('request') -or (Get-EntryField $body 'Request') -ceq $record.request)
            }
        )
        $findingsOnly = $record.Contains('findingsOnly') -and $record.findingsOnly -is [bool] -and $record.findingsOnly
        if ($findingsOnly) {
            $consultative = @('cost-manager', 'deployer', 'fact-checker', 'asbuilt-author', 'azure-diagnose', 'aws-diagnose')
            $stage = if ($proof.Contains('stage')) { $proof.stage } else { '' }
            if (-not $record.Contains('role') -or
                ($record.role -notin $consultative -and $stage -ne 'council' -and
                -not ($stage -eq 'discovery' -and $record.role -in @('designer', 'challenger', 'experimenter')))) { throw 'This role/stage requires a domain artifact.' }
            if (-not $record.Contains('decisionRef')) { throw 'Findings-only proof requires its durable decision reference.' }
            $null = Get-Decision -Root $SquadRoot -Reference $record.decisionRef
            $candidates = @($candidates | Where-Object { $_.Groups['body'].Value.Contains($record.decisionRef) })
            $artifact = $record.decisionRef
        }
        else {
            if (-not $record.Contains('deliverable') -or $record.deliverable -isnot [string] -or -not $record.deliverable) { throw 'Dispatch proof requires an exact deliverable file.' }
            $pathText = ($record.deliverable -replace '\s+\([^)]*\)\s*$', '').Trim().Trim('`')
            $artifact = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $pathText -AllowMissing
            if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
                $artifact = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $SquadRoot $pathText)
            }
            if (-not (Test-Path -LiteralPath $artifact -PathType Leaf) -or (Get-Item -LiteralPath $artifact).Length -eq 0) { throw 'Domain artifact is missing or empty.' }
            $artifactRelative = [IO.Path]::GetRelativePath($RepoRoot, $artifact) -replace '\\', '/'
            $roleRows = @($roster | Where-Object {
                    ($_.ContainsKey('Agent Name (Primary)') -and ($_['Agent Name (Primary)'] -ceq $record.agent -or $record.agent -cin @($_['Alternate Agents'] -split ',\s*'))) -and
                    (-not $record.Contains('role') -or $_.Role -ceq $record.role)
                })
            if ($roleRows.Count -eq 1) {
                $declared = $roleRows[0]['Deliverable Root']
                if ($declared -and $declared -notin @('-', [string][char]0x2014, '(squad state)')) {
                    $underRoot = $false
                    foreach ($alternative in ($declared -split '\s+or\s+')) {
                        $prefix = ($alternative -replace ' \((?:ADO|Jira)\)$', '').Trim('`') -replace '\\', '/'
                        if ([IO.Path]::IsPathRooted($prefix)) {
                            $prefix = [IO.Path]::GetRelativePath($RepoRoot, (Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $prefix -AllowMissing)) -replace '\\', '/'
                        }
                        $pattern = [regex]::Escape($prefix.TrimEnd('/')) -replace '<[^>]+>', '[^/]+'
                        if ($artifactRelative -match ('^' + $pattern + '/')) { $underRoot = $true }
                    }
                    if (-not $underRoot) { throw 'Artifact is outside its current roster Deliverable Root.' }
                }
            }
            $candidates = @($candidates | Where-Object {
                    $line = Get-EntryField $_.Groups['body'].Value 'Deliverable'
                    $stored = [regex]::Match($line, '^`?(?<path>[^`]+?)(?:`(?: \([^)]*\))?|$)').Groups['path'].Value.Trim()
                    ($stored -replace '\\', '/') -ceq ($pathText -replace '\\', '/')
                })
        }
        if ($candidates.Count -ne 1) { throw "No unique matching dispatch entry for '$($record.agent)' on turn $turn." }
        $entry = $candidates[0]
        if (-not $matchedEntries.Add($historyPath + ':' + $entry.Index)) { throw 'The same history entry cannot prove two dispatches.' }
        $blocks = @([regex]::Matches($entry.Groups['body'].Value, '(?ms)^#### Consumption\r?\n\s*\r?\n```json\r?\n(?<json>.*?)\r?\n```[ \t]*(?:\r?\n|$)'))
        if ($blocks.Count -ne 1) { throw 'The dispatch needs exactly one literal consumption block.' }
        $block = $blocks[0].Groups['json'].Value | ConvertFrom-Json -AsHashtable
        if (@($block.Keys).Count -ne 10 -or (@($block.Keys) -join ',') -cne ($consumptionKeys -join ',')) { throw 'Consumption field set/order is invalid.' }
        foreach ($key in @('internal_turns', 'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens')) {
            if ($block[$key] -isnot [long] -and $block[$key] -isnot [int] -or $block[$key] -lt 0) { throw 'Consumption numbers must be nonnegative integers.' }
        }
        $body = $entry.Groups['body'].Value
        $reference = Get-EntryField $body 'Cost Preflight Ref'
        if (-not $reference) { $reference = Get-EntryField $body 'Cost Preflight Decision Ref' }
        $slot = Get-EntryField $body 'Cost Preflight Slot'
        $preflight = if ($state.currentRun.Contains('costPreflight')) { $state.currentRun.costPreflight } else { $null }
        if ($reference -or $slot -or ($preflight -and $preflight.decision -ne 'not-requested')) {
            if (-not $reference -or -not $slot) { throw 'Ceiling-admitted dispatch is missing its reference or slot.' }
            $decision = Get-Decision -Root $SquadRoot -Reference $reference
            $heading = $decision.Groups['heading'].Value
            if ($heading -notmatch ('^Cost Preflight \S+ ' + [regex]::Escape($proof.runId) + ' \S+$')) { throw 'Admission reference belongs to another run.' }
            $decisionBody = $decision.Groups['body'].Value
            if ((Get-EntryField $decisionBody 'Decision') -notin @('within-ceiling', 'approved-over-ceiling')) { throw 'Dispatch references a non-admitting decision.' }
            $permitted = @((Get-EntryField $decisionBody 'Permitted Next Dispatch Set') -split ',\s*' | ForEach-Object { $_.Trim('`') })
            if ($slot -cnotin $permitted) { throw 'Dispatch consumed an unpermitted slot.' }
            $occurrences = @(Get-Entry $allHistory | Where-Object {
                    (Get-EntryField $_.Groups['body'].Value 'Cost Preflight Slot') -ceq $slot -and
                    $_.Groups['body'].Value.Contains($reference)
                })
            if ($occurrences.Count -ne 1) { throw 'Admission slot was recorded more than once.' }
        }
        $verified.Add([ordered]@{ agent = $record.agent; turn = $turn; artifact = $artifact; history = $historyPath; heading = $entry.Groups['heading'].Value })
    }
    foreach ($activeRole in $activeExpected) {
        if (-not $recordedActiveIdentities.Contains([string]$activeRole)) { throw 'activeRoles claims an unrecorded dispatch.' }
    }
    $ledger = Invoke-SquadLocalScript -Name 'Measure-SquadLedger.ps1' -Arguments @('-SquadRoot', $SquadRoot, '-Check')
    $ledgerText = ($ledger.stdout + $ledger.stderr) -replace '\x1b\[[0-9;]*[A-Za-z]', ''
    $ledgerStatus = 'PASS'
    if ($ledger.exitCode -ne 0) {
        if ($ledgerText -notmatch 'failure class: ledger-only') { throw "Ledger/history verification failed: $($ledgerText.Trim())" }
        $ledgerStatus = 'ledger-only'
        $warnings.Add($ledgerText.Trim())
    }
    elseif ($ledgerText -notmatch 'Measure-SquadLedger -Check: PASS') { throw 'Ledger returned no PASS status.' }
    $consumption = [IO.File]::ReadAllText((Join-Path $SquadRoot 'consumption.md'))
    if ($consumption -notmatch ('(?m)^# Squad Consumption Ledger \(Run: ' + [regex]::Escape($proof.runId) + '\)')) { throw 'Ledger belongs to a different run.' }
    [ordered]@{ status = 'ok'; verified = $true; kind = 'squad'; squadRoot = $SquadRoot; turn = $ExpectedTurn; updated = $state.updated; dispatchEntries = $verified.Count; records = $verified.ToArray(); ledgerCheck = $ledgerStatus; warnings = $warnings.ToArray() } | ConvertTo-Json -Depth 8 -Compress
}
catch {
    [Console]::Error.WriteLine("Test-SquadTurnCompletion: $($_.Exception.Message)")
    exit 1
}
