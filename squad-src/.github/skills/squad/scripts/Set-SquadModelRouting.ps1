#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Applies the deterministic active routing transition or Model-cell refresh.
.DESCRIPTION
    Reads a dispatch-plan result, verifies the exact team.md SHA-256 and recorded mode,
    adds or changes the active routing line and Model column when requested, replaces
    only selected rows' Model cells, appends deterministic decision evidence, and reads
    both files back. The transaction writes no state.json field and launches no model.
.PARAMETER PlanPath
    JSON output from New-SquadDispatchPlan.ps1.
.PARAMETER RepoRoot
    Repository boundary. Defaults to the current directory.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [string]$RepoRoot = (Get-Location).ProviderPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force

function Stop-RoutingRefresh {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Terminates the script with a deterministic exit code and performs no mutation.')]
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("Set-SquadModelRouting: $Message")
    exit $Code
}

function Write-AtomicText {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    $temporary = Join-Path (Split-Path -Parent $Path) (".$([IO.Path]::GetFileName($Path)).$([guid]::NewGuid().ToString('N')).tmp")
    try {
        [IO.File]::WriteAllText($temporary, $Content, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function ConvertFrom-TableLine {
    param([Parameter(Mandatory)][string]$Line)
    @($Line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
}

try {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $PlanPath = (Resolve-Path -LiteralPath $PlanPath).ProviderPath
    $plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json -AsHashtable -Depth 40 -DateKind String
    if ($plan -isnot [Collections.IDictionary] -or $plan.status -ne 'ok' -or $plan.kind -ne 'squad') {
        throw 'PlanPath must contain a successful single-squad dispatch plan.'
    }
    $refresh = $plan.routingRefresh
    if ($refresh -isnot [Collections.IDictionary]) { throw 'Dispatch plan has no routingRefresh object.' }
    if ($refresh.required -isnot [bool]) { throw 'routingRefresh.required must be boolean.' }
    if (-not $refresh.required) {
        [ordered]@{ status = 'unchanged'; mode = $refresh.mode; changes = 0; stateWritten = $false } | ConvertTo-Json -Compress
        exit 0
    }
    if ($refresh.mode -notin @('ranked', 'economy', 'manual')) { throw 'Routing refresh requires ranked, economy, or manual mode.' }
    if ($refresh.recordedMode -notin @('off', 'ranked', 'economy', 'manual')) { throw 'routingRefresh.recordedMode is invalid.' }
    $changes = @($refresh.changes)
    if ($changes.Count -eq 0 -and $refresh.recordedMode -ceq $refresh.mode) { throw 'A required routing refresh has no changes.' }
    $consent = $refresh.economyConsent
    if ($refresh.recordedMode -cne $refresh.mode -and $refresh.mode -eq 'economy') {
        if ($consent -isnot [Collections.IDictionary]) { throw 'Switching into economy requires economyConsent.' }
    }
    elseif ($null -ne $consent) { throw 'economyConsent is allowed only while switching into economy.' }

    $root = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path ([string]$plan.units[0].endpoint.squadRoot)
    $teamPath = Join-Path $root 'team.md'
    $decisionsPath = Join-Path $root 'decisions.md'
    foreach ($path in @($teamPath, $decisionsPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing $path." }
        if ((Get-Item -LiteralPath $path).IsReadOnly) { throw "$path is read-only." }
    }

    $teamBytes = [IO.File]::ReadAllBytes($teamPath)
    $teamHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($teamBytes))
    if ($teamHash -cne [string]$refresh.expectedTeamHash) {
        Stop-RoutingRefresh 2 "collision: team.md hash is $teamHash, expected $($refresh.expectedTeamHash). Nothing written."
    }
    $teamText = [Text.UTF8Encoding]::new($false).GetString($teamBytes).TrimStart([char]0xFEFF)
    $mode = [regex]::Match($teamText, '(?m)^Model routing:\s*`?(?<mode>off|ranked|economy|manual)`?\s*$')
    $currentMode = if ($mode.Success) { $mode.Groups['mode'].Value } else { 'off' }
    if ($currentMode -cne $refresh.recordedMode) {
        throw "team.md routing mode '$currentMode' does not match the plan's recorded mode '$($refresh.recordedMode)'."
    }

    $newline = if ($teamText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $hadFinalNewline = $teamText.EndsWith("`n")
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in ($teamText -replace "`r`n", "`n" -split "`n")) { $lines.Add($line) }
    if ($currentMode -eq 'off') {
        $headings = @(0..($lines.Count - 1) | Where-Object { $lines[$_] -match '^# [^#]' })
        if ($headings.Count -ne 1) { throw 'Expected exactly one team.md H1.' }
        $lines.Insert($headings[0] + 1, "Model routing: $($refresh.mode)")
    }
    else {
        $modeLines = @(0..($lines.Count - 1) | Where-Object { $lines[$_] -match '^Model routing:' })
        if ($modeLines.Count -ne 1) { throw 'Expected exactly one Model routing line.' }
        $lines[$modeLines[0]] = "Model routing: $($refresh.mode)"
    }

    $tables = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -notmatch '^\s*\|') { continue }
        $header = @(ConvertFrom-TableLine $lines[$index] | ForEach-Object { $_.Trim('`') })
        if ('Role' -notin $header -or 'Model Tier' -notin $header -or 'Deliverable Root' -notin $header) { continue }
        $tables.Add([pscustomobject]@{ index = $index; header = $header })
    }
    if ($tables.Count -ne 1) { throw 'Expected exactly one roster table.' }
    $table = $tables[0]
    $hasModel = 'Model' -in $table.header
    if ($currentMode -ne 'off' -and -not $hasModel) { throw 'Active routing requires an existing Model column.' }
    if (-not $hasModel) {
        $insertAt = [array]::IndexOf($table.header, 'Deliverable Root')
        for ($index = $table.index; $index -lt $lines.Count -and $lines[$index] -match '^\s*\|'; $index++) {
            $cells = [Collections.Generic.List[string]]::new()
            foreach ($cell in (ConvertFrom-TableLine $lines[$index])) { $cells.Add($cell) }
            if ($cells.Count -ne $table.header.Count) { throw "Roster row $($index + 1) does not match its header width." }
            $cells.Insert($insertAt, $(if ($index -eq $table.index) { 'Model' } elseif ($index -eq $table.index + 1) { '-----' } else { '' }))
            $lines[$index] = '| ' + ($cells -join ' | ') + ' |'
        }
        $table.header = @($table.header[0..($insertAt - 1)] + 'Model' + $table.header[$insertAt..($table.header.Count - 1)])
    }
    $roleIndex = [array]::IndexOf($table.header, 'Role')
    $memberIndex = [array]::IndexOf($table.header, 'Member Name')
    $modelIndex = [array]::IndexOf($table.header, 'Model')
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $changeByIdentity = @{}
    foreach ($change in $changes) {
        if ($change -isnot [Collections.IDictionary]) { throw 'Every routing change must be an object.' }
        foreach ($key in @('role', 'memberName', 'from', 'to', 'rationale')) {
            if (-not $change.Contains($key) -or $change[$key] -isnot [string]) { throw "Routing change is missing string '$key'." }
        }
        $identity = [string]$change.role + "`n" + [string]$change.memberName
        if ($change.role -cnotmatch '^[a-z][a-z0-9-]*$' -or -not $seen.Add($identity)) { throw 'Routing changes need unique role/member identities.' }
        if ($change.to -cnotmatch '^[a-z0-9][a-z0-9.-]*$') { throw "Invalid target model '$($change.to)'." }
        $plannedUnits = @($plan.units | Where-Object {
                $_.endpoint.role -ceq $change.role -and
                $_.endpoint.memberName -ceq $change.memberName -and
                $_.endpoint.model -ceq $change.to -and
                $_.endpoint.persistedModel -ceq $change.from -and
                $_.endpoint.modelRouting -ceq $refresh.mode
            })
        if ($plannedUnits.Count -eq 0) { throw "Routing change '$($change.role)/$($change.memberName)' is not backed by a selected plan unit." }
        $changeByIdentity[$identity] = $change
    }

    $matched = @{}
    for ($index = $table.index + 2; $index -lt $lines.Count -and $lines[$index] -match '^\s*\|'; $index++) {
        $cells = @(ConvertFrom-TableLine $lines[$index])
        if ($cells.Count -ne $table.header.Count) { throw "Roster row $($index + 1) does not match its header width." }
        $role = $cells[$roleIndex].Trim('`')
        $memberName = if ($memberIndex -ge 0) { $cells[$memberIndex].Trim('`') } else { '' }
        $identity = $role + "`n" + $memberName
        if (-not $changeByIdentity.ContainsKey($identity)) {
            if ($refresh.recordedMode -cne $refresh.mode -and $refresh.mode -eq 'manual') {
                $cells[$modelIndex] = ''
                $lines[$index] = '| ' + ($cells -join ' | ') + ' |'
            }
            continue
        }
        if ($matched.ContainsKey($identity)) { throw "Roster identity '$role/$memberName' is ambiguous." }
        $change = $changeByIdentity[$identity]
        $current = $cells[$modelIndex].Trim().Trim('`')
        if ($current -in @('-', [string][char]0x2014)) { $current = '' }
        if ($current -cne [string]$change.from) {
            throw "Roster role '$role' changed from '$($change.from)' to '$current' after planning."
        }
        $cells[$modelIndex] = "``$($change.to)``"
        $lines[$index] = '| ' + ($cells -join ' | ') + ' |'
        $matched[$identity] = $true
    }
    $missing = @($changeByIdentity.Keys | Where-Object { -not $matched.ContainsKey($_) })
    if ($missing.Count) { throw 'One or more routing refresh role/member identities were not found in team.md.' }

    $newTeam = ($lines -join "`n").Replace("`n", $newline)
    if (-not $hadFinalNewline) { $newTeam = $newTeam.TrimEnd("`r", "`n") }
    $decisionsText = [IO.File]::ReadAllText($decisionsPath)
    $decisionNewline = if ($decisionsText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    $entry = [Collections.Generic.List[string]]::new()
    $entry.Add("## Model Routing Refresh $timestamp")
    $entry.Add('')
    $entry.Add("* Previous mode: $($refresh.recordedMode)")
    $entry.Add("* Mode: $($refresh.mode)")
    $entry.Add('* Source: deterministic dispatch plan over the actual selected role units and host model inputs')
    foreach ($change in $changes) {
        $from = if ($change.from) { $change.from } else { '(empty)' }
        $member = if ($change.memberName) { " / $($change.memberName)" } else { '' }
        $entry.Add(('* {0}{1}: {2} -> {3}' -f $change.role, $member, $from, $change.to))
    }
    $entryText = ($entry -join $decisionNewline)
    $decisionEntries = [Collections.Generic.List[string]]::new()
    if ($null -ne $consent) {
        foreach ($key in @('user', 'tradeAccepted', 'neverWeakened', 'timestamp')) {
            if (-not $consent.Contains($key) -or $consent[$key] -isnot [string] -or
                [string]::IsNullOrWhiteSpace($consent[$key]) -or $consent[$key] -match '[\r\n]') {
                throw "economyConsent.$key is required."
            }
        }
        foreach ($key in $consent.Keys) {
            if ($key -notin @('user', 'tradeAccepted', 'neverWeakened', 'timestamp')) { throw "Unsupported economyConsent field: $key" }
        }
        $consentTimestamp = [DateTimeOffset]::Parse([string]$consent.timestamp, [Globalization.CultureInfo]::InvariantCulture).ToUniversalTime().ToString('o')
        $decisionEntries.Add((@(
                    "## Economy Mode Accepted $consentTimestamp"
                    ''
                    "* User: $($consent.user)"
                    "* Previous mode: $($refresh.recordedMode)"
                    "* Trade accepted: $($consent.tradeAccepted)"
                    "* Never weakened: $($consent.neverWeakened)"
                ) -join $decisionNewline))
    }
    $decisionEntries.Add($entryText)
    $separator = if (-not $decisionsText) { '' } elseif ($decisionsText.EndsWith("`n")) { $decisionNewline } else { "$decisionNewline$decisionNewline" }
    $newDecisions = $decisionsText + $separator + ($decisionEntries -join "$decisionNewline$decisionNewline") + $decisionNewline

    if ([Convert]::ToBase64String($teamBytes) -cne [Convert]::ToBase64String([IO.File]::ReadAllBytes($teamPath))) {
        Stop-RoutingRefresh 2 'collision: team.md changed while the refresh was being prepared. Nothing written.'
    }
    $decisionsBytes = [IO.File]::ReadAllBytes($decisionsPath)
    $decisionsWritten = $false
    try {
        Write-AtomicText -Path $decisionsPath -Content $newDecisions
        $decisionsWritten = $true
        Write-AtomicText -Path $teamPath -Content $newTeam
    }
    catch {
        $detail = $_.Exception.Message
        if ($decisionsWritten) {
            try { [IO.File]::WriteAllBytes($decisionsPath, $decisionsBytes); $detail += ' decisions.md restored.' }
            catch { $detail += " decisions.md could not be restored: $($_.Exception.Message)" }
        }
        Stop-RoutingRefresh 3 "write failed: $detail"
    }

    $afterHash = (Get-FileHash -LiteralPath $teamPath -Algorithm SHA256).Hash
    $after = [IO.File]::ReadAllText($teamPath)
    if ($after -notmatch ('(?m)^Model routing:\s*' + [regex]::Escape([string]$refresh.mode) + '\s*$')) {
        Stop-RoutingRefresh 3 'routing mode read-back failed.'
    }
    foreach ($change in $changes) {
        if ($after -notmatch ('(?m)^\|[^\r\n]*\|\s*`?' + [regex]::Escape([string]$change.to) + '`?\s*\|')) {
            Stop-RoutingRefresh 3 "read-back failed for role '$($change.role)'."
        }
    }
    if (-not [IO.File]::ReadAllText($decisionsPath).Contains($entryText)) {
        Stop-RoutingRefresh 3 'decision read-back failed.'
    }

    [ordered]@{
        status = 'written'
        mode = $refresh.mode
        changes = $changes.Count
        previousTeamHash = $teamHash
        teamHash = $afterHash
        decision = "decisions.md#model-routing-refresh-$($timestamp.ToLowerInvariant() -replace '[^a-z0-9 _-]', '' -replace ' ', '-')"
        stateWritten = $false
    } | ConvertTo-Json -Compress
}
catch {
    Stop-RoutingRefresh 1 $_.Exception.Message
}
