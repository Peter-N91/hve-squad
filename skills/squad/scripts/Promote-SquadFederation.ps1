#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Promotes a hash-bound plain squad into a one-member federation transactionally.
.DESCRIPTION
    AI cost: none. The coordinator first runs `Get-SquadPromotionPlan.ps1`, presents
    its candidate directories, and obtains confirmation. This helper then verifies the
    exact plan SHA-256 and requires an explicit relocate/keep partition covering every
    candidate.

    The complete final federation is built and checked in a sibling stage. The helper
    copies and verifies every source before any source path is removed, takes the same
    per-root writer lock as ordinary handoffs, revalidates the sealed plan, and swaps
    the staged tree into place. A pre-commit failure writes nothing. A publish failure
    restores the original squad and relocated directories when owned paths are still
    unchanged.

    Exit 0 returns a verified JSON receipt. Exit 1 rejects input or a stale plan; 3 is
    a write/restore failure; 4 means another writer already promoted the root; 5 is a
    member-name collision; 8 is a writer-lock timeout.
.PARAMETER PlanPath
    JSON plan created by `Get-SquadPromotionPlan.ps1`.
.PARAMETER ExpectedPlanSha256
    Exact SHA-256 returned by the planning helper.
.PARAMETER RelocateDirectory
    Candidate directory names confirmed for relocation.
.PARAMETER KeepDirectory
    Candidate directory names explicitly confirmed to remain at the tracking root.
.PARAMETER Confirmed
    Required after human confirmation, or after Watch Mode authorization auto-approves
    the same bounded operation.
.PARAMETER SessionModel
    Optional coordinator session model to persist for subsequent member dispatches.
    Promotion itself is script-only and does not add estimated model consumption.
.EXAMPLE
    ./Promote-SquadFederation.ps1 -RepoRoot . -PlanPath $plan -ExpectedPlanSha256 $sha `
      -RelocateDirectory plans,research -KeepDirectory pr -Confirmed
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][string]$ExpectedPlanSha256,
    [string]$RepoRoot = (Get-Location).ProviderPath,
    [string[]]$RelocateDirectory = @(),
    [string[]]$KeepDirectory = @(),
    [switch]$Confirmed,
    [AllowEmptyString()][string]$SessionModel = '',
    [ValidateRange(1, 3600)][int]$LockTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SquadPromotion.psm1') -Force

$lock = $null
$stageContainer = $null
$stageRoot = $null
$backupContainer = $null
$backupRoot = $null
$published = $false
$committed = $false
$sourceMoved = $false
$movedCandidates = [Collections.Generic.List[string]]::new()
$finalSnapshot = $null
$exactSessionJournalPresent = $false
$journalAdvance = $null
$exitCode = 1
$stopwatch = [Diagnostics.Stopwatch]::StartNew()

function Assert-FieldSet {
    param($Object, [string[]]$Required, [string[]]$Optional = @())
    if ($Object -isnot [Collections.IDictionary]) { throw 'Expected a JSON object.' }
    foreach ($field in $Required) {
        if (-not $Object.Contains($field)) { throw "Missing field: $field" }
    }
    foreach ($field in $Object.Keys) {
        if ($field -notin ($Required + $Optional)) { throw "Unsupported field: $field" }
    }
}

function Get-CandidateMap {
    param([Parameter(Mandatory)]$Candidates)
    if ($Candidates -isnot [array]) { throw 'Promotion plan candidates must be an array.' }
    $map = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in $Candidates) {
        Assert-FieldSet $candidate @('name', 'path', 'digest', 'files', 'directories', 'bytes', 'requiredToRelocate', 'reasons')
        Assert-SquadPromotionText $candidate.name
        if ($candidate.name -match '[/\\]' -or $candidate.path -cne ".copilot-tracking/$($candidate.name)" -or
            $candidate.requiredToRelocate -isnot [bool] -or -not $map.TryAdd($candidate.name, $candidate)) {
            throw 'Invalid or duplicate promotion candidate.'
        }
    }
    $map
}

function Assert-LivePlan {
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$CandidateMap,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$TrackingRoot,
        [string[]]$ExcludedDirectory = @()
    )
    if (Test-Path -LiteralPath (Join-Path $SourceRoot 'federation.md')) {
        $script:exitCode = 4
        throw 'Another writer already promoted this squad; re-detect federation state.'
    }
    if (Test-Path -LiteralPath (Join-Path $SourceRoot 'members' $Plan.name)) {
        $script:exitCode = 5
        throw "Federation member '$($Plan.name)' already exists."
    }
    Assert-SquadPromotionSnapshot -Expected $Plan.source -Actual (Get-SquadPromotionTreeSnapshot $SourceRoot) -Label 'plain squad'
    $current = @(
        Get-ChildItem -LiteralPath $TrackingRoot -Directory -Force |
            Where-Object { $_.Name -cne 'squad' -and $_.Name -notin $ExcludedDirectory } |
            Sort-Object Name
    )
    if ($current.Count -ne $CandidateMap.Count) { throw 'Promotion candidate directories changed after confirmation.' }
    foreach ($directory in $current) {
        if (-not $CandidateMap.ContainsKey($directory.Name)) { throw "New or renamed promotion candidate detected: $($directory.Name)" }
        Assert-SquadPromotionSnapshot -Expected $CandidateMap[$directory.Name] -Actual (Get-SquadPromotionTreeSnapshot $directory.FullName) -Label "candidate '$($directory.Name)'"
    }
}

function Write-GeneratedRoot {
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$MemberRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Relocated,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Kept,
        [Parameter(Mandatory)][string]$Timestamp
    )
    $name = [string]$Plan.name
    $arrow = [char]0x2192
    $federation = @"
---
description: "Squad federation registry: the named sub-squads in this repository and the profile each was seeded from"
---

# Squad Federation

## Sub-Squads

| Sub-squad | Profile | Kind    | Location          | Owner | Description |
|-----------|---------|---------|-------------------|-------|-------------|
| $name | $($Plan.profile) | in-repo | members/$name/ | $($Plan.owner) | $($Plan.description) |
"@
    Write-SquadPromotionText -Path (Join-Path $Root 'federation.md') -Text ($federation.TrimStart() + "`n")

    $routeRows = @($Plan.routePatterns | ForEach-Object { "| $_ | $name | yes |" })
    $routing = @"
---
description: "Squad federation meta-routing: request patterns mapped to the sub-squad that handles them"
---

# Squad Federation Meta-Routing

| Pattern / Domain | Sub-squad | Parallel-Eligible |
|------------------|-----------|-------------------|
$($routeRows -join "`n")
"@
    Write-SquadPromotionText -Path (Join-Path $Root 'meta-routing.md') -Text ($routing.TrimStart() + "`n")

    $mappingLines = [Collections.Generic.List[string]]::new()
    $mappingLines.Add("* Prefix mapping: ``.copilot-tracking/squad/`` $arrow ``.copilot-tracking/squad/members/$name/``")
    foreach ($directory in $Relocated) {
        $mappingLines.Add("* Prefix mapping: ``.copilot-tracking/$directory/`` $arrow ``.copilot-tracking/squad/members/$name/$directory/``")
    }
    foreach ($directory in $Kept) {
        $mappingLines.Add("* Kept at tracking root by confirmed choice: ``.copilot-tracking/$directory/``")
    }
    if ($null -ne $Plan.watch) {
        $mappingLines.Add("* Watch provenance: source=$($Plan.watch.source); ref=$($Plan.watch.ref); eventId=$($Plan.watch.eventId); actor=$($Plan.watch.actor); auto-approved after trigger authorization.")
    }
    $decisions = @"
---
description: "Append-only log of squad federation routing decisions and their rationale"
---

# Squad Federation Decisions

Entries are appended below in chronological order.

## $Timestamp Promote single squad as $name

* Turn: 1
* Rationale: Adopt the existing single squad without rebuilding its roster, history, or deliverables.
* Profile: $($Plan.profile)
$($mappingLines -join "`n")
"@
    Write-SquadPromotionText -Path (Join-Path $Root 'decisions.md') -Text ($decisions.TrimStart() + "`n")

    $decisionTitle = "$Timestamp Promote single squad as $name"
    $decisionAnchor = ($decisionTitle.ToLowerInvariant() -replace '[^\p{L}\p{Nd}_ -]', '') -replace ' ', '-'
    $history = @"
---
description: "Append-only federation sub-squad history"
---

# History: $name

### $Timestamp Promotion

* Turn: 1
* Request: Promote the existing single squad into a federation.
* Outcome: Adopted as ``members/$name/`` through the verified promotion transaction.
* Decision Refs: decisions.md#$decisionAnchor
"@
    Write-SquadPromotionText -Path (Join-Path $Root 'history' "$name.md") -Text ($history.TrimStart() + "`n")

    $stateSection = Get-SquadReferenceSection -Path (Join-Path $PSScriptRoot '..' 'references' 'federation-templates.md') -Heading '### state.json (federation root)'
    $stateMatch = [regex]::Match($stateSection, '(?s)```json\s*\n(?<json>.*?)\n```')
    if (-not $stateMatch.Success) { throw 'Missing canonical federation state seed.' }
    $state = $stateMatch.Groups['json'].Value | ConvertFrom-Json -AsHashtable
    $memberState = Get-Content -LiteralPath (Join-Path $MemberRoot 'state.json') -Raw | ConvertFrom-Json -AsHashtable
    $state.updated = $Timestamp
    $state.turn = 1
    $state.mode = 'interactive'
    $state.subSquads = @($name)
    $state.activeSubSquads = @($name)
    $state.currentRun.sessionModel = $memberState.currentRun.sessionModel
    $state.currentRun.modelOverrides = $memberState.currentRun.modelOverrides
    $state.currentRun.estCostUsd = $memberState.currentRun.estCostUsd
    $state.currentRun.estCreditsTotal = $memberState.currentRun.estCreditsTotal
    $state.notify = $Plan.member.notify
    Write-SquadPromotionText -Path (Join-Path $Root 'state.json') -Text (($state | ConvertTo-Json -Depth 30) + "`n")

    $rates = Invoke-SquadLocalScript -Name 'Initialize-SquadConsumptionRates.ps1' -Arguments @('-SquadRoot', $Root)
    if ($rates.exitCode -ne 0) { throw "Federation rate seeding failed: $($rates.stderr.Trim())" }
}

function Restore-PromotionSource {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$TrackingRoot
    )
    $failures = [Collections.Generic.List[string]]::new()
    try {
        if ($script:published -and (Test-Path -LiteralPath $SourceRoot) -and $script:finalSnapshot) {
            $current = Get-SquadPromotionTreeSnapshot $SourceRoot
            if ($current.digest -cne $script:finalSnapshot.digest) {
                $failures.Add('published federation changed before rollback')
            }
            else {
                if (Test-Path -LiteralPath $script:stageRoot) { $failures.Add('stage root collision during rollback') }
                else {
                    [IO.Directory]::Move($SourceRoot, $script:stageRoot)
                    $script:published = $false
                }
            }
        }
    }
    catch { $failures.Add("published root: $($_.Exception.Message)") }
    try {
        if ($script:sourceMoved -and (Test-Path -LiteralPath $script:backupRoot) -and -not (Test-Path -LiteralPath $SourceRoot)) {
            [IO.Directory]::Move($script:backupRoot, $SourceRoot)
            $script:sourceMoved = $false
        }
    }
    catch { $failures.Add("plain squad: $($_.Exception.Message)") }
    foreach ($name in @($script:movedCandidates.ToArray()) | Sort-Object -Descending) {
        try {
            $backup = Join-Path $script:backupContainer 'deliverables' $name
            $destination = Join-Path $TrackingRoot $name
            if (Test-Path -LiteralPath $backup) {
                if (Test-Path -LiteralPath $destination) { $failures.Add("candidate collision: $name") }
                else { [IO.Directory]::Move($backup, $destination) }
            }
        }
        catch { $failures.Add("candidate $name`: $($_.Exception.Message)") }
    }
    $failures.ToArray()
}

try {
    if (-not $Confirmed) { throw 'Promotion requires explicit confirmation.' }
    if ($ExpectedPlanSha256 -cnotmatch '^[A-Fa-f0-9]{64}$') { throw 'ExpectedPlanSha256 must be a SHA-256 digest.' }
    if ($SessionModel) { Assert-SquadPromotionText $SessionModel }
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $planFile = (Resolve-Path -LiteralPath $PlanPath).ProviderPath
    if ([IO.Path]::GetExtension($planFile) -cne '.json') { throw 'PlanPath must name a JSON file.' }
    $cursor = $planFile
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Linked promotion plan path refused: $cursor" }
        $cursor = Split-Path -Parent $cursor
    }
    if ((Get-FileHash -LiteralPath $planFile -Algorithm SHA256).Hash -cne $ExpectedPlanSha256.ToUpperInvariant()) {
        throw 'Promotion plan hash mismatch; prepare and confirm a fresh plan.'
    }
    $plan = Get-Content -LiteralPath $planFile -Raw | ConvertFrom-Json -AsHashtable
    Assert-FieldSet $plan @('schemaVersion', 'squadRoot', 'name', 'profile', 'owner', 'description', 'routePatterns', 'source', 'candidates', 'member', 'watch', 'generatedAt')
    if ($plan.schemaVersion -ne 1 -or $plan.squadRoot -cne '.copilot-tracking/squad' -or
        $plan.name -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
        throw 'Unsupported promotion plan.'
    }
    if ($plan.generatedAt -is [DateTime]) { $plan.generatedAt = $plan.generatedAt.ToString('o') }
    foreach ($value in @($plan.name, $plan.profile, $plan.owner, $plan.description, $plan.generatedAt) + @($plan.routePatterns)) {
        Assert-SquadPromotionText $value -AllowEmpty
    }
    if ($plan.routePatterns -isnot [array] -or -not $plan.routePatterns.Count) { throw 'Promotion plan requires at least one route pattern.' }
    Assert-FieldSet $plan.member @('turn', 'sessionModel', 'notify', 'memberNames')
    if ($plan.member.turn -isnot [ValueType] -or $plan.member.turn -is [bool] -or $plan.member.turn -lt 0) { throw 'Invalid planned member turn.' }
    Assert-SquadPromotionText ([string]$plan.member.sessionModel) -AllowEmpty
    Assert-FieldSet $plan.member.notify @('approvalChannel', 'enabled') @('email', 'github')
    if ($plan.member.notify.enabled -isnot [bool] -or $plan.member.notify.approvalChannel -notin @('in-chat', 'github-issue', 'webhook')) {
        throw 'Invalid planned notification configuration.'
    }
    if ($null -ne $plan.watch) {
        Assert-FieldSet $plan.watch @('source', 'ref', 'eventId', 'actor')
        foreach ($value in $plan.watch.Values) { Assert-SquadPromotionText $value }
    }
    $candidateMap = Get-CandidateMap $plan.candidates

    $selected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $kept = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $RelocateDirectory) {
        Assert-SquadPromotionText $name
        if (-not $candidateMap.ContainsKey($name) -or -not $selected.Add($name)) { throw "Unknown or duplicate relocated directory: $name" }
    }
    foreach ($name in $KeepDirectory) {
        Assert-SquadPromotionText $name
        if (-not $candidateMap.ContainsKey($name) -or $selected.Contains($name) -or -not $kept.Add($name)) { throw "Unknown, duplicate, or conflicting kept directory: $name" }
    }
    if ($selected.Count + $kept.Count -ne $candidateMap.Count) {
        throw 'RelocateDirectory and KeepDirectory must explicitly partition every planned candidate.'
    }
    foreach ($candidate in $candidateMap.Values) {
        if ($candidate.requiredToRelocate -and -not $selected.Contains($candidate.name)) {
            throw "Candidate '$($candidate.name)' is referenced by $($candidate.reasons -join ' and ') and must relocate."
        }
    }
    $relocated = [string[]]@($candidateMap.Values | Where-Object { $selected.Contains($_.name) } | ForEach-Object name)
    $keptNames = [string[]]@($candidateMap.Values | Where-Object { $kept.Contains($_.name) } | ForEach-Object name)
    [Array]::Sort($relocated, [StringComparer]::Ordinal)
    [Array]::Sort($keptNames, [StringComparer]::Ordinal)

    $sourceRoot = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $plan.squadRoot
    $trackingRoot = Split-Path -Parent $sourceRoot
    Assert-LivePlan -Plan $plan -CandidateMap $candidateMap -SourceRoot $sourceRoot -TrackingRoot $trackingRoot
    $sourceSessionJournal = Join-Path $sourceRoot 'consumption-sessions.json'
    if ((Test-Path -LiteralPath $sourceSessionJournal) -and -not (Test-Path -LiteralPath $sourceSessionJournal -PathType Leaf)) {
        throw 'Plain squad consumption-sessions.json must be a file when present.'
    }
    $exactSessionJournalPresent = Test-Path -LiteralPath $sourceSessionJournal -PathType Leaf

    $transactionId = [guid]::NewGuid().ToString('N')
    $stageContainer = Join-Path $trackingRoot ".squad-promotion-$transactionId"
    $stageRoot = Join-Path $stageContainer 'squad'
    $stageMember = Join-Path $stageRoot 'members' $plan.name
    $backupContainer = Join-Path $trackingRoot ".squad-promotion-backup-$transactionId"
    $backupRoot = Join-Path $backupContainer 'squad'
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $stageMember))

    Copy-SquadPromotionTree -Source $sourceRoot -Destination $stageMember -ExpectedSnapshot $plan.source
    if ((Test-Path -LiteralPath (Join-Path $stageMember 'consumption-sessions.json') -PathType Leaf) -ne $exactSessionJournalPresent) {
        throw 'Staged member did not preserve the exact-session journal state.'
    }
    foreach ($name in $relocated) {
        $destination = Join-Path $stageMember $name
        if (Test-Path -LiteralPath $destination) { throw "Relocated directory '$name' collides with existing squad state." }
        Copy-SquadPromotionTree -Source (Join-Path $trackingRoot $name) -Destination $destination -ExpectedSnapshot $candidateMap[$name]
    }

    $teamPath = Join-Path $stageMember 'team.md'
    $team = ConvertTo-SquadPromotionTeam -Path $teamPath -Name $plan.name
    [IO.File]::WriteAllText($teamPath, $team.text, $team.encoding)
    foreach ($relative in Get-SquadPromotionDeliverableDirectory -Roots $team.roots -Name $plan.name) {
        $null = [IO.Directory]::CreateDirectory((Join-Path $stageMember $relative))
    }

    $memberStatePath = Join-Path $stageMember 'state.json'
    $memberState = Get-Content -LiteralPath $memberStatePath -Raw | ConvertFrom-Json -AsHashtable
    if ($memberState.turn -ne $plan.member.turn) { throw 'Member turn changed while the promotion was staged.' }
    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    $memberState.updated = $timestamp
    $memberState.turn = [int]$memberState.turn + 1
    $memberState.activeRoles = @()
    if ($SessionModel) { $memberState.currentRun.sessionModel = $SessionModel }
    Write-SquadPromotionText -Path $memberStatePath -Text (($memberState | ConvertTo-Json -Depth 30) + "`n")

    $entry = "### $timestamp Federation promotion`n`n* Turn: $($memberState.turn)`n* Request: Promote the existing single squad into a federation.`n* Deliverable: federation state`n* Outcome: Deterministic coordinator transaction; no model or Scribe dispatch and no added consumption."
    $historyPath = Join-Path $stageMember 'history' 'Squad Scribe.md'
    [IO.File]::WriteAllBytes($historyPath, (Add-SquadPromotionEntry -Path $historyPath -Header "---`ndescription: `"Append-only dispatch history for a single squad agent`"`n---`n`n# History: Squad Scribe" -Entry $entry))

    if ($exactSessionJournalPresent) {
        $journalAdvance = Invoke-SquadLocalScript -Name 'Measure-SquadLedger.ps1' `
            -Arguments @('-SquadRoot', $stageMember, '-AdvanceUnmeteredHistory') -TimeoutSeconds 180
        if ($journalAdvance.exitCode -ne 0) {
            throw "Promotion exact-session journal advance failed: $($journalAdvance.stderr.Trim()) $($journalAdvance.stdout.Trim())"
        }
    }
    $ledgerCheck = Invoke-SquadLocalScript -Name 'Measure-SquadLedger.ps1' -Arguments @('-SquadRoot', $stageMember, '-Check') -TimeoutSeconds 180
    if ($ledgerCheck.exitCode -ne 0 -or $ledgerCheck.stdout -notmatch 'Measure-SquadLedger -Check: PASS') {
        throw "Promotion ledger check failed: $($ledgerCheck.stderr.Trim()) $($ledgerCheck.stdout.Trim())"
    }

    Write-GeneratedRoot -Plan $plan -Root $stageRoot -MemberRoot $stageMember -Relocated $relocated -Kept $keptNames -Timestamp $timestamp
    $null = Get-SquadFederationSnapshot -SquadRoot $stageRoot -RepoRoot $RepoRoot
    $finalSnapshot = Get-SquadPromotionTreeSnapshot $stageRoot

    $key = (Get-SquadPromotionHash ([Text.UTF8Encoding]::new($false).GetBytes($sourceRoot.ToLowerInvariant()))).Substring(0, 16)
    $lockPath = Join-Path ([IO.Path]::GetTempPath()) "hve-squad-handoff-$key.lock"
    $deadline = [DateTime]::UtcNow.AddSeconds($LockTimeoutSeconds)
    while (-not $lock) {
        try { $lock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) { $exitCode = 8; throw 'Promotion writer lock timed out; nothing was written.' }
            Start-Sleep -Milliseconds 200
        }
    }
    Assert-LivePlan -Plan $plan -CandidateMap $candidateMap -SourceRoot $sourceRoot -TrackingRoot $trackingRoot -ExcludedDirectory @((Split-Path $stageContainer -Leaf), (Split-Path $backupContainer -Leaf))

    $exitCode = 3
    $null = [IO.Directory]::CreateDirectory((Join-Path $backupContainer 'deliverables'))
    foreach ($name in $relocated) {
        [IO.Directory]::Move((Join-Path $trackingRoot $name), (Join-Path $backupContainer 'deliverables' $name))
        $movedCandidates.Add($name)
    }
    [IO.Directory]::Move($sourceRoot, $backupRoot)
    $sourceMoved = $true
    [IO.Directory]::Move($stageRoot, $sourceRoot)
    $published = $true

    Assert-SquadPromotionSnapshot -Expected $finalSnapshot -Actual (Get-SquadPromotionTreeSnapshot $sourceRoot) -Label 'published federation'
    $federationSnapshot = Get-SquadFederationSnapshot -SquadRoot $sourceRoot -RepoRoot $RepoRoot
    if ($federationSnapshot.members.Count -ne 1 -or -not $federationSnapshot.members.Contains($plan.name)) {
        throw 'Published federation member verification failed.'
    }
    if ((Test-Path -LiteralPath (Join-Path $sourceRoot 'members' $plan.name 'consumption-sessions.json') -PathType Leaf) -ne $exactSessionJournalPresent) {
        throw 'Published member did not preserve the exact-session journal state.'
    }
    foreach ($name in $relocated) {
        if (Test-Path -LiteralPath (Join-Path $trackingRoot $name)) { throw "Relocated source still exists: $name" }
        if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'members' $plan.name $name) -PathType Container)) {
            throw "Relocated destination is missing: $name"
        }
    }
    foreach ($name in $keptNames) {
        Assert-SquadPromotionSnapshot -Expected $candidateMap[$name] -Actual (Get-SquadPromotionTreeSnapshot (Join-Path $trackingRoot $name)) -Label "kept candidate '$name'"
    }
    if (Test-Path -LiteralPath (Join-Path $trackingRoot '.copilot-tracking')) { throw 'Promotion created a nested .copilot-tracking directory.' }

    $publishedState = Get-Content -LiteralPath (Join-Path $sourceRoot 'state.json') -Raw | ConvertFrom-Json -AsHashtable
    $memberState = Get-Content -LiteralPath (Join-Path $sourceRoot 'members' $plan.name 'state.json') -Raw | ConvertFrom-Json -AsHashtable
    $committed = $true
    $cleanupWarnings = [Collections.Generic.List[string]]::new()
    foreach ($path in @($stageContainer, $backupContainer)) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        try {
            [IO.Directory]::Delete($path, $true)
            if ($path -ceq $stageContainer) { $stageContainer = $null }
            if ($path -ceq $backupContainer) { $backupContainer = $null }
        }
        catch { $cleanupWarnings.Add("Transaction cleanup required at '$path': $($_.Exception.Message)") }
    }
    $stopwatch.Stop()
    $warnings = [Collections.Generic.List[string]]::new()
    foreach ($text in @($ledgerCheck.stderr.Trim())) {
        if ($text) { $warnings.Add($text) }
    }
    if ($journalAdvance -and $journalAdvance.stderr.Trim()) {
        $warnings.Add($journalAdvance.stderr.Trim())
    }
    foreach ($text in $cleanupWarnings) { $warnings.Add($text) }
    [ordered]@{
        status = $(if ($cleanupWarnings.Count) { 'promoted-cleanup-required' } else { 'promoted' })
        verified = $cleanupWarnings.Count -eq 0
        name = $plan.name
        memberRoot = ".copilot-tracking/squad/members/$($plan.name)"
        relocatedDirectories = $relocated
        keptDirectories = $keptNames
        memberTurn = $memberState.turn
        federationTurn = $publishedState.turn
        costUsd = $memberState.currentRun.estCostUsd
        credits = $memberState.currentRun.estCreditsTotal
        exactSessionJournal = $(if ($exactSessionJournalPresent) { 'preserved' } else { 'absent' })
        elapsedMs = $stopwatch.ElapsedMilliseconds
        warnings = $warnings.ToArray()
        cleanupRequired = $cleanupWarnings.Count -gt 0
    } | ConvertTo-Json -Depth 8 -Compress
    $exitCode = $(if ($cleanupWarnings.Count) { 3 } else { 0 })
}
catch {
    $restoreFailures = @()
    if (-not $committed -and ($backupContainer -or $sourceMoved -or $published)) {
        $restoreFailures = @(Restore-PromotionSource -SourceRoot $sourceRoot -TrackingRoot $trackingRoot)
    }
    [Console]::Error.WriteLine("Promote-SquadFederation: $($_.Exception.Message)")
    if ($restoreFailures.Count) {
        [Console]::Error.WriteLine("RESTORE FAILED; inspect transaction paths: $($restoreFailures -join '; ')")
        $exitCode = 3
    }
}
finally {
    if ($lock) { $lock.Dispose() }
    if (-not $published) {
        foreach ($path in @($stageContainer, $backupContainer)) {
            if ($path -and (Test-Path -LiteralPath $path)) {
                try { [IO.Directory]::Delete($path, $true) } catch { [Console]::Error.WriteLine("Promotion cleanup failed for '$path': $($_.Exception.Message)") }
            }
        }
    }
    $stopwatch.Stop()
}
exit $exitCode