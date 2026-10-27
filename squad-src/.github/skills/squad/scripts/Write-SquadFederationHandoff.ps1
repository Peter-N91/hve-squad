#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Persists an ordinary federation turn from verified inner proofs and a prior snapshot.
.DESCRIPTION
    AI cost: none. Payload: runId, snapshotPath, routeKind (ordinary or
    targeted-autopilot), decision {title,rationale}, subSquads
    [{name,proofPath,turn,decisionRefs:[],request,outcome}]; optional sessionModel,
    modelOverrides, openEscalationsRaised/Resolved, handoffs
    [{producer,consumer,paths:[]}], orchestration (a ten-field coordinator block).
    The snapshot is written before child dispatch by Get-SquadDispatchBrief
    -AsJson -SnapshotPath, outside squad state. Previous root overhead is carried
    exactly once; member totals are summed after proof verification. Existing file
    bytes are appended intact, and unrelated state survives. State advances last.
    Init, expansion, promotion, aggregate autopilot and verdicts remain cold.
    Exit 0 returns a verified JSON receipt; 1 rejects input; 2 needs the documented
    cold path; 3 reports a write failure with owned-file rollback; 8 is a lock timeout.
    Never overlap this writer, cold Scribe or Cost Preflight at the federation root.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PayloadPath,
    [string]$SquadRoot = '.copilot-tracking/squad',
    [string]$RepoRoot = (Get-Location).ProviderPath,
    [ValidateRange(1, 3600)][int]$LockTimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force
$lock = $null
$scratch = $null
$originals = [ordered]@{}
$owned = @{}
$exitCode = 1

function Assert-Fields {
    param($Object, [string[]]$Required, [string[]]$Optional = @())
    if ($Object -isnot [Collections.IDictionary]) { throw 'Expected a JSON object.' }
    foreach ($key in $Required) { if (-not $Object.Contains($key)) { throw "Missing field: $key" } }
    foreach ($key in $Object.Keys) { if ($key -notin ($Required + $Optional)) { throw "Unsupported field: $key" } }
}

function Assert-Line {
    param($Value)
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value) -or $Value -match '[\r\n\x00-\x1f]') { throw 'Expected a nonempty single-line value.' }
    if ($Value -match '(?i)\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|(?:password|client_secret|api[_-]?key)\s*[:=]\s*\S+)') { throw 'Secret-like text refused.' }
}

function Get-Hash {
    param([byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Add-EntryBytes {
    param([string]$Path, [string]$Header, [string]$Entry)
    $before = if (Test-Path -LiteralPath $Path) { ,([IO.File]::ReadAllBytes($Path)) } else { ,([byte[]]::new(0)) }
    $newline = if ([Text.Encoding]::UTF8.GetString($before).Contains("`r`n")) { "`r`n" } else { "`n" }
    $tail = if ($before.Length) { $(if ($before[-1] -ne 10) { $newline }) + $newline + ($Entry -replace "`r?`n", $newline) + $newline }
    else { ($Header + "`n`n" + $Entry + "`n") -replace "`r?`n", $newline }
    $stream = [IO.MemoryStream]::new()
    try {
        $stream.Write($before)
        $stream.Write([Text.UTF8Encoding]::new($false).GetBytes($tail))
        return ,$stream.ToArray()
    }
    finally { $stream.Dispose() }
}

function Write-Atomic {
    param([string]$Path, [byte[]]$Bytes)
    if (-not $originals.Contains($Path)) {
        if (Test-Path -LiteralPath $Path) { $originals.Add($Path, [IO.File]::ReadAllBytes($Path)) }
        else { $originals.Add($Path, $null) }
    }
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        [IO.File]::Move($temporary, $Path, $true)
        $owned[$Path] = Get-Hash $Bytes
        if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $owned[$Path]) { throw 'Write read-back mismatch.' }
    }
    finally { if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) } }
}

try {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $SquadRoot = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $SquadRoot
    $payload = Get-Content -LiteralPath $PayloadPath -Raw | ConvertFrom-Json -AsHashtable
    Assert-Fields $payload @('runId', 'snapshotPath', 'routeKind', 'decision', 'subSquads') @('sessionModel', 'modelOverrides', 'openEscalationsRaised', 'openEscalationsResolved', 'handoffs', 'orchestration')
    Assert-Line $payload.runId
    if ($payload.routeKind -notin @('ordinary', 'targeted-autopilot')) {
        $exitCode = 2
        throw 'Aggregate autopilot and cold lifecycle operations require the cold Scribe procedure.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $SquadRoot 'federation.md')) -or
        -not (Test-Path -LiteralPath (Join-Path $SquadRoot 'history') -PathType Container) -or
        -not (Test-Path -LiteralPath (Join-Path $SquadRoot 'consumption-rates.md'))) {
        $exitCode = 2
        throw 'An uninitialized/legacy federation needs cold seeding before an ordinary scripted handoff.'
    }
    $key = (Get-Hash ([Text.Encoding]::UTF8.GetBytes($SquadRoot.ToLowerInvariant()))).Substring(0, 16)
    $lockPath = Join-Path ([IO.Path]::GetTempPath()) "hve-squad-handoff-$key.lock"
    $deadline = [DateTime]::UtcNow.AddSeconds($LockTimeoutSeconds)
    while (-not $lock) {
        try { $lock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) { $exitCode = 8; throw 'Federation writer lock timed out; nothing was written.' }
            Start-Sleep -Milliseconds 200
        }
    }
    $snapshot = Get-Content -LiteralPath $payload.snapshotPath -Raw | ConvertFrom-Json -AsHashtable
    Assert-Fields $snapshot @('schemaVersion', 'squadRoot', 'files', 'members')
    if ($snapshot.schemaVersion -ne 1 -or $snapshot.squadRoot -cne $SquadRoot) { throw 'Snapshot belongs to a different root or version.' }
    $current = Get-SquadFederationSnapshot -SquadRoot $SquadRoot -RepoRoot $RepoRoot
    if ($snapshot.files.Count -ne $current.files.Count -or @($current.files.Keys | Where-Object { -not $snapshot.files.Contains($_) -or $snapshot.files[$_] -cne $current.files[$_] }).Count) {
        throw 'Federation state/history changed since the pre-dispatch snapshot; nothing was written.'
    }
    if ($snapshot.members.Count -ne $current.members.Count -or @($current.members.Keys | Where-Object { -not $snapshot.members.Contains($_) }).Count) { throw 'Federation membership changed.' }
    $statePath = Join-Path $SquadRoot 'state.json'
    $stateText = [IO.File]::ReadAllText($statePath)
    $state = $stateText | ConvertFrom-Json -AsHashtable
    $stateNode = [Text.Json.Nodes.JsonNode]::Parse($stateText)
    if ($state.schemaVersion -notin @('1.2', '1.3') -or $state.turn -isnot [ValueType] -or $state.turn -is [bool]) { $exitCode = 2; throw 'Unsupported federation state.' }
    $turn = [int]$state.turn + 1
    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    $previousUpdated = $stateNode['updated'].ToString()
    if ($previousUpdated -and [DateTimeOffset]::Parse($previousUpdated, [Globalization.CultureInfo]::InvariantCulture) -ge [DateTimeOffset]::Parse($timestamp, [Globalization.CultureInfo]::InvariantCulture)) { throw 'Federation timestamp must advance.' }
    Assert-Fields $payload.decision @('title', 'rationale')
    Assert-Line $payload.decision.title
    Assert-Line $payload.decision.rationale
    if ($payload.subSquads -isnot [array] -or -not $payload.subSquads.Count -or
        ($payload.routeKind -eq 'targeted-autopilot' -and $payload.subSquads.Count -ne 1)) { throw 'Select actual completed sub-squads; targeted autopilot selects exactly one.' }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $innerResults = [ordered]@{}
    $warnings = [Collections.Generic.List[string]]::new()
    foreach ($member in $payload.subSquads) {
        Assert-Fields $member @('name', 'proofPath', 'turn', 'decisionRefs', 'request', 'outcome')
        Assert-Line $member.name
        Assert-Line $member.request
        Assert-Line $member.outcome
        if (-not $current.members.Contains($member.name) -or -not $names.Add($member.name)) { throw 'Unknown or duplicate selected sub-squad.' }
        if ($member.decisionRefs -isnot [array] -or -not $member.decisionRefs.Count) { throw 'Inner decision references are required.' }
        $memberRoot = Join-Path $SquadRoot 'members' $member.name
        foreach ($reference in $member.decisionRefs) { $null = Get-SquadDecision -RepoRoot $RepoRoot -SquadRoot $memberRoot -Reference $reference }
        $proof = Invoke-SquadLocalScript -Name 'Test-SquadTurnCompletion.ps1' -Arguments @(
            '-RepoRoot', $RepoRoot, '-SquadRoot', $memberRoot, '-ProofPath', $member.proofPath, '-ExpectedTurn', [string]$member.turn)
        if ($proof.exitCode -ne 0) { throw "Inner completion failed for '$($member.name)': $($proof.stderr.Trim())" }
        $result = $proof.stdout | ConvertFrom-Json -AsHashtable
        if ($result.status -ne 'ok' -or $result.verified -ne $true -or $result.dispatchEntries -lt 1) { throw 'Empty inner runs or summaries are not completion proof.' }
        foreach ($warning in $result.warnings) { $warnings.Add("$($member.name): $warning") }
        $innerResults[$member.name] = $result
    }
    foreach ($name in $current.members.Keys) {
        foreach ($field in @('costUsd', 'credits')) {
            $value = $snapshot.members[$name][$field]
            if ($value -isnot [ValueType] -or $value -is [bool] -or -not [double]::IsFinite([double]$value) -or $value -lt 0) { throw 'Invalid snapshot member total.' }
        }
        if (-not $names.Contains($name) -and $snapshot.members[$name].stateHash -cne $current.members[$name].stateHash) { throw 'An unselected sub-squad changed during this turn.' }
    }
    $oldMemberUsd = [double](@($snapshot.members.Values | ForEach-Object costUsd) | Measure-Object -Sum).Sum
    $oldMemberCredits = [double](@($snapshot.members.Values | ForEach-Object credits) | Measure-Object -Sum).Sum
    $overheadUsd = [double]$state.currentRun.estCostUsd - $oldMemberUsd
    $overheadCredits = [double]$state.currentRun.estCreditsTotal - $oldMemberCredits
    if (-not [double]::IsFinite($overheadUsd) -or -not [double]::IsFinite($overheadCredits) -or $overheadUsd -lt -0.00005 -or $overheadCredits -lt -0.005) {
        $exitCode = 2
        throw 'Prior federation totals do not cover baseline member totals; cold reconciliation is required.'
    }
    $sessionModel = if ($payload.Contains('sessionModel')) { $payload.sessionModel } else { [string]$state.currentRun.sessionModel }
    if ($sessionModel -isnot [string] -or $sessionModel -match '[\r\n\x00]') { throw 'Invalid sessionModel.' }
    $block = if ($payload.Contains('orchestration')) { $payload.orchestration }
    else { New-SquadOrchestrationConsumption -RatesPath (Join-Path $SquadRoot 'consumption-rates.md') -SessionModel $sessionModel }
    $keys = @('model', 'model_source', 'priced_as', 'model_tier', 'internal_turns', 'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens', 'basis')
    Assert-Fields $block $keys
    foreach ($field in $keys) {
        if ($field -in @('internal_turns', 'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens')) {
            if ($block[$field] -isnot [int] -and $block[$field] -isnot [long] -or $block[$field] -lt 0) { throw 'Invalid orchestration token number.' }
        }
        else { Assert-Line $block[$field] }
    }
    if ($block.model_source -notin @('dispatch-reported', 'session-inherited', 'operator-declared', 'cli-pinned', 'unresolved') -or
        $block.model_tier -notin @('fast', 'default', 'extended') -or
        $block.model -in @('auto', 'fast', 'default', 'extended') -or
        (($block.model -eq 'unknown') -ne ($block.model_source -eq 'unresolved')) -or
        $block.basis -ne $(if ($block.model -eq 'unknown') { 'tier-default' } else { 'estimated' }) -or
        ($block.model_source -eq 'session-inherited' -and $block.model -cne $sessionModel)) { throw 'Invalid coordinator orchestration attribution.' }
    $expectedPricing = New-SquadOrchestrationConsumption -RatesPath (Join-Path $SquadRoot 'consumption-rates.md') -SessionModel $block.model -FallbackTier $block.model_tier
    if ($block.priced_as -cne $expectedPricing.priced_as -or $block.model_tier -cne $expectedPricing.model_tier) { throw 'Coordinator consumption does not match its canonical model/tier rate row.' }
    $orderedBlock = [ordered]@{}
    foreach ($field in $keys) { $orderedBlock[$field] = $block[$field] }
    $orchestrationEntry = "### $timestamp Federation coordinator, turn $turn`n`n* Turn: $turn`n* Request: Federation routing`n* Deliverable: federation state`n* Outcome: Coordinator overhead; no Scribe dispatch.`n`n#### Consumption $([char]0x2014) Orchestration`n`n``````json`n$($orderedBlock | ConvertTo-Json)`n``````"
    if (-not $payload.Contains('orchestration')) { $warnings.Add('Federation coordinator usage uses the documented orchestration estimator floor, not measured or billed telemetry.') }
    $scratch = Join-Path ([IO.Path]::GetTempPath()) "hve-squad-federation-price-$([guid]::NewGuid().ToString('N'))"
    $null = [IO.Directory]::CreateDirectory((Join-Path $scratch 'history'))
    [IO.File]::WriteAllText((Join-Path $scratch 'history' 'Squad Scribe.md'), "# History: Squad Scribe`n`n$orchestrationEntry`n")
    [IO.File]::Copy((Join-Path $SquadRoot 'members' $payload.subSquads[0].name 'team.md'), (Join-Path $scratch 'team.md'))
    [IO.File]::Copy((Join-Path $SquadRoot 'consumption-rates.md'), (Join-Path $scratch 'consumption-rates.md'))
    [IO.File]::Copy($statePath, (Join-Path $scratch 'state.json'))
    $price = Invoke-SquadLocalScript -Name 'Measure-SquadLedger.ps1' -Arguments @('-SquadRoot', $scratch, '-Format', 'json')
    if ($price.exitCode -ne 0) { throw "Orchestration pricing failed: $($price.stderr.Trim())" }
    $priced = $price.stdout | ConvertFrom-Json -AsHashtable
    if ($priced.total.turns -ne $block.internal_turns -or @($priced.attribution).Count -ne 1 -or $priced.attribution[0].role -ne 'orchestration') {
        throw "Orchestration accounting did not validate: expected $($block.internal_turns) turns, priced $($priced.total.turns); $($priced.warnings -join '; ')."
    }
    foreach ($warning in $priced.warnings) { $warnings.Add($warning) }
    $newMemberUsd = [double](@($current.members.Values | ForEach-Object costUsd) | Measure-Object -Sum).Sum
    $newMemberCredits = [double](@($current.members.Values | ForEach-Object credits) | Measure-Object -Sum).Sum
    $next = $stateNode.DeepClone()
    $next['schemaVersion'] = '1.3'
    $next['updated'] = $timestamp
    $next['turn'] = $turn
    $next['mode'] = $(if ($payload.routeKind -eq 'targeted-autopilot') { 'autopilot' } else { 'interactive' })
    $next['activeSubSquads'] = [Text.Json.Nodes.JsonNode]::Parse((ConvertTo-Json -InputObject @($payload.subSquads | ForEach-Object name) -Compress))
    $next['currentRun']['sessionModel'] = $sessionModel
    $next['currentRun']['estCostUsd'] = [Math]::Round($newMemberUsd + [Math]::Max(0.0, $overheadUsd) + [double]$priced.total.estCostUsd, 4)
    $next['currentRun']['estCreditsTotal'] = [Math]::Round($newMemberCredits + [Math]::Max(0.0, $overheadCredits) + [double]$priced.total.estCredits, 2)
    $seedSection = Get-SquadReferenceSection -Path (Join-Path $PSScriptRoot '..' 'references' 'federation-templates.md') -Heading '### state.json (federation root)'
    $seedJson = [regex]::Match($seedSection, '(?s)```json\s*\n(?<json>.*?)\n```')
    if (-not $seedJson.Success) { throw 'Missing canonical federation preflight seed.' }
    $seed = [Text.Json.Nodes.JsonNode]::Parse($seedJson.Groups['json'].Value)
    $next['currentRun']['costPreflight'] = $seed['currentRun']['costPreflight'].DeepClone()
    if ($payload.Contains('modelOverrides')) {
        Assert-Fields $payload.modelOverrides @() @($payload.modelOverrides.Keys)
        foreach ($value in $payload.modelOverrides.Values) { Assert-Line $value }
        $next['currentRun']['modelOverrides'] = [Text.Json.Nodes.JsonNode]::Parse(($payload.modelOverrides | ConvertTo-Json -Compress))
    }
    $escalations = @($state.openEscalations)
    foreach ($field in @('openEscalationsRaised', 'openEscalationsResolved')) {
        if ($payload.Contains($field)) {
            if ($payload[$field] -isnot [array]) { throw "$field must be an array." }
            foreach ($value in $payload[$field]) { Assert-Line $value }
        }
    }
    if ($payload.Contains('openEscalationsResolved')) { $escalations = @($escalations | Where-Object { $_ -cnotin $payload.openEscalationsResolved }) }
    if ($payload.Contains('openEscalationsRaised')) { $escalations = @($escalations + $payload.openEscalationsRaised | Select-Object -Unique) }
    $next['openEscalations'] = [Text.Json.Nodes.JsonNode]::Parse((ConvertTo-Json -InputObject @($escalations) -Compress))
    $decisionEntry = "## $timestamp $($payload.decision.title)`n`n* Turn: $turn`n* Rationale: $($payload.decision.rationale)"
    foreach ($member in $payload.subSquads) { $decisionEntry += "`n* Sub-squad: $($member.name); Decision Refs: $($member.decisionRefs -join ', ')" }
    if ($payload.Contains('handoffs')) {
        if ($payload.handoffs -isnot [array]) { throw 'handoffs must be an array.' }
        foreach ($handoff in $payload.handoffs) {
            Assert-Fields $handoff @('producer', 'consumer', 'paths')
            if (-not $current.members.Contains($handoff.producer) -or -not $names.Contains($handoff.consumer) -or
                $handoff.paths -isnot [array] -or -not $handoff.paths.Count) { throw 'Invalid producer/consumer handoff.' }
            foreach ($path in $handoff.paths) {
                $resolved = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $path
                if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw 'A handoff input must be an existing file.' }
                $relative = [IO.Path]::GetRelativePath($RepoRoot, $resolved) -replace '\\', '/'
                $producerPrefix = ([IO.Path]::GetRelativePath($RepoRoot, (Join-Path $SquadRoot 'members' $handoff.producer)) -replace '\\', '/') + '/'
                if (-not $relative.StartsWith($producerPrefix, [StringComparison]::Ordinal) -and $relative -notmatch '^(?:docs|outputs)/') { throw 'A handoff input leaves its producer root.' }
            }
            $decisionEntry += "`n* Handoff: $($handoff.producer) -> $($handoff.consumer); read-only inputs: $($handoff.paths -join ', ')"
        }
    }
    $plans = [ordered]@{}
    foreach ($member in $payload.subSquads) {
        $path = Join-Path $SquadRoot 'history' "$($member.name).md"
        $header = "---`ndescription: Append-only federation sub-squad history`n---`n`n# History: $($member.name)"
        $entry = "### $timestamp $($member.name)`n`n* Turn: $turn`n* Request: $($member.request)`n* Outcome: $($member.outcome)`n* Decision Refs: $($member.decisionRefs -join ', ')"
        $plans[$path] = Add-EntryBytes -Path $path -Header $header -Entry $entry
    }
    $orchestrationPath = Join-Path $SquadRoot 'history' 'Squad Scribe.md'
    $plans[$orchestrationPath] = Add-EntryBytes -Path $orchestrationPath -Header "---`ndescription: Append-only orchestration history`n---`n`n# History: Squad Scribe" -Entry $orchestrationEntry
    $decisionsPath = Join-Path $SquadRoot 'decisions.md'
    $plans[$decisionsPath] = Add-EntryBytes -Path $decisionsPath -Header '' -Entry $decisionEntry
    $plans[$statePath] = [Text.UTF8Encoding]::new($false).GetBytes($next.ToJsonString([Text.Json.JsonSerializerOptions]@{ WriteIndented = $true }))
    $finalSnapshot = Get-SquadFederationSnapshot -SquadRoot $SquadRoot -RepoRoot $RepoRoot
    if (($current | ConvertTo-Json -Depth 15 -Compress) -cne ($finalSnapshot | ConvertTo-Json -Depth 15 -Compress)) { throw 'Federation or member state changed during validation; nothing was written.' }
    $exitCode = 3
    foreach ($path in $plans.Keys) { Write-Atomic -Path $path -Bytes $plans[$path] }
    [ordered]@{
        status = 'written'; verified = $true; turn = $turn; squadRoot = $SquadRoot
        activeSubSquads = @($payload.subSquads | ForEach-Object name)
        innerDispatchEntries = @($innerResults.Values | ForEach-Object dispatchEntries)
        estCostUsd = [double]$next['currentRun']['estCostUsd'].ToString()
        estCreditsTotal = [double]$next['currentRun']['estCreditsTotal'].ToString()
        warnings = $warnings.ToArray()
    } | ConvertTo-Json -Depth 8 -Compress
    $exitCode = 0
}
catch {
    $restoreFailures = [Collections.Generic.List[string]]::new()
    foreach ($path in $originals.Keys) {
        try {
            if (-not $owned.ContainsKey($path)) {
                if ($null -eq $originals[$path] -and -not (Test-Path -LiteralPath $path)) { continue }
                if ($null -ne $originals[$path] -and (Test-Path -LiteralPath $path) -and
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ceq (Get-Hash $originals[$path])) { continue }
                $restoreFailures.Add($path)
                continue
            }
            if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $owned[$path]) {
                $restoreFailures.Add($path)
                continue
            }
            if ($null -eq $originals[$path]) { [IO.File]::Delete($path) }
            else { [IO.File]::WriteAllBytes($path, $originals[$path]) }
        }
        catch [IO.IOException] { $restoreFailures.Add($path) }
        catch [UnauthorizedAccessException] { $restoreFailures.Add($path) }
    }
    [Console]::Error.WriteLine("Write-SquadFederationHandoff: $($_.Exception.Message)")
    if ($restoreFailures.Count) { [Console]::Error.WriteLine("RESTORE FAILED; external changes preserved: $($restoreFailures -join ', ')") }
}
finally {
    if ($lock) { $lock.Dispose() }
    if ($scratch -and (Test-Path -LiteralPath $scratch)) { [IO.Directory]::Delete($scratch, $true) }
}
exit $exitCode
