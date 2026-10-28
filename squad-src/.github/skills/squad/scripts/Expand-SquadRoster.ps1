#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Applies one sealed additive roster expansion without a Scribe or ledger rewrite.
.DESCRIPTION
    AI cost: none. Requires the exact SHA-256 of a plan produced by
    Get-SquadRosterExpansionPlan.ps1 and explicit confirmation. Under the same
    per-root writer lock as ordinary handoffs, the transaction revalidates every
    sealed file and history digest, writes only team.md, routing.md, and an appended
    decisions.md entry, then checks the ledger read-only.

    consumption.md, optional consumption-sessions.json, state.json, consumption-rates.md, notifications.md, and history/
    must remain byte-identical. A stale plan, lock timeout, failed ledger check, or
    write/read-back failure restores owned files and returns nonzero.
.PARAMETER PlanPath
    Plan JSON produced by Get-SquadRosterExpansionPlan.ps1.
.PARAMETER ExpectedPlanSha256
    Exact SHA-256 returned by the planning helper.
.PARAMETER Confirmed
    Required after the user confirms the proposed packs and roles.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][string]$ExpectedPlanSha256,
    [string]$RepoRoot = (Get-Location).ProviderPath,
    [switch]$Confirmed,
    [ValidateRange(1, 3600)][int]$LockTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SquadPromotion.psm1') -Force

$locks = [Collections.Generic.List[IO.FileStream]]::new()
$exitCode = 1
$wrote = $false
$originals = [ordered]@{}
$planned = [ordered]@{}
$root = $null
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

function Get-Hash {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Get-FileSnapshot {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked squad-state file refused: $Path" }
    $bytes = [IO.File]::ReadAllBytes($Path)
    [ordered]@{
        bytes = $bytes.Length
        sha256 = Get-Hash $bytes
    }
}

function Get-Baseline {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$RelativeRoot
    )
    $files = [ordered]@{}
    foreach ($name in @(
            'team.md', 'routing.md', 'decisions.md', 'notifications.md',
            'state.json', 'consumption.md', 'consumption-rates.md'
        )) {
        $path = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required squad state: $name" }
        $files[$name] = Get-FileSnapshot $path
    }
    $sessionCache = Join-Path $Root 'consumption-sessions.json'
    if (Test-Path -LiteralPath $sessionCache -PathType Leaf) {
        $files['consumption-sessions.json'] = Get-FileSnapshot $sessionCache
    }
    $history = Join-Path $Root 'history'
    if (-not (Test-Path -LiteralPath $history -PathType Container)) { throw 'Missing required squad state: history' }
    $baseline = [ordered]@{
        files = $files
        history = Get-SquadPromotionTreeSnapshot $history
    }
    if ($RelativeRoot -match '^\.copilot-tracking/squad/members/(?<name>[a-z0-9][a-z0-9-]*)$') {
        $memberName = $Matches.name
        $registryPath = Join-Path (Join-Path $Repository '.copilot-tracking' 'squad') 'federation.md'
        if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
            throw "Member '$memberName' is no longer registered."
        }
        $registry = @(Read-SquadTables $registryPath |
                Where-Object { 'Sub-squad' -in $_.Header -and 'Location' -in $_.Header })
        if ($registry.Count -ne 1) { throw 'Federation registry is missing or ambiguous.' }
        $rows = @($registry[0].Rows | Where-Object {
                $_['Sub-squad'] -ceq $memberName -and
                (($_.Location -replace '\\', '/').TrimEnd('/')) -ceq "members/$memberName"
            })
        if ($rows.Count -ne 1) { throw "Member '$memberName' is no longer registered at its selected root." }
        $baseline['federation'] = [ordered]@{
            member = $memberName
            registry = Get-FileSnapshot $registryPath
        }
    }
    $baseline
}

function Assert-Baseline {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$RelativeRoot,
        [string[]]$IgnoreFiles = @()
    )
    $actual = Get-Baseline -Root $Root -Repository $Repository -RelativeRoot $RelativeRoot
    foreach ($name in $Expected.files.Keys) {
        if ($name -in $IgnoreFiles) { continue }
        foreach ($field in @('bytes', 'sha256')) {
            if ($Expected.files[$name][$field] -cne $actual.files[$name][$field]) {
                $script:exitCode = 2
                throw "Roster expansion collision: $name changed after confirmation."
            }
        }
    }
    foreach ($field in @('digest', 'files', 'directories', 'bytes')) {
        if ($Expected.history[$field] -cne $actual.history[$field]) {
            $script:exitCode = 2
            throw 'Roster expansion collision: history changed after confirmation.'
        }
    }
    if ($Expected.Contains('federation')) {
        foreach ($field in @('bytes', 'sha256')) {
            if ($Expected.federation.registry[$field] -cne $actual.federation.registry[$field]) {
                $script:exitCode = 2
                throw 'Roster expansion collision: federation registry changed after confirmation.'
            }
        }
    }
}

function Write-AtomicFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$Bytes)
    if (Test-Path -LiteralPath $Path) {
        $probe = $null
        try {
            $probe = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        finally {
            if ($probe) { $probe.Dispose() }
        }
    }
    $temporary = Join-Path (Split-Path -Parent $Path) (".$([IO.Path]::GetFileName($Path)).$([guid]::NewGuid().ToString('N')).tmp")
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        [IO.File]::Move($temporary, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Enter-WriterLock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][DateTime]$Deadline
    )
    $key = (Get-Hash ([Text.UTF8Encoding]::new($false).GetBytes($Path.ToLowerInvariant()))).Substring(0, 16)
    $lockPath = Join-Path ([IO.Path]::GetTempPath()) "hve-squad-handoff-$key.lock"
    while ($true) {
        try {
            return [IO.FileStream]::new(
                $lockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        }
        catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $Deadline) {
                $script:exitCode = 8
                throw 'Roster expansion writer lock timed out; nothing was written.'
            }
            Start-Sleep -Milliseconds 200
        }
    }
}

function Restore-Output {
    $failures = [Collections.Generic.List[string]]::new()
    foreach ($name in @('routing.md', 'team.md', 'decisions.md')) {
        if (-not $script:originals.Contains($name)) { continue }
        $path = Join-Path $script:root $name
        try {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $current = [IO.File]::ReadAllBytes($path)
                if ((Get-Hash $current) -ceq (Get-Hash $script:originals[$name])) { continue }
                if (-not $script:planned.Contains($name) -or
                    (Get-Hash $current) -cne (Get-Hash $script:planned[$name])) {
                    $null = $failures.Add("$name changed after this transaction wrote it")
                    continue
                }
            }
            Write-AtomicFile -Path $path -Bytes $script:originals[$name]
        }
        catch { $null = $failures.Add("${name}: $($_.Exception.Message)") }
    }
    if ($failures.Count) { throw "Roster expansion rollback incomplete: $($failures -join '; ')" }
}

try {
    if (-not $Confirmed) { throw 'Roster expansion requires -Confirmed.' }
    if ($ExpectedPlanSha256 -cnotmatch '^[A-Fa-f0-9]{64}$') { throw 'ExpectedPlanSha256 must be a SHA-256 hex value.' }
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $PlanPath = (Resolve-Path -LiteralPath $PlanPath).ProviderPath
    if ((Get-Item -LiteralPath $PlanPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Linked roster expansion plan refused.'
    }
    $stateBoundary = [IO.Path]::GetFullPath((Join-Path $RepoRoot '.copilot-tracking' 'squad'))
    $planRelative = [IO.Path]::GetRelativePath($stateBoundary, $PlanPath)
    if ($planRelative -ne '..' -and $planRelative -notmatch '^\.\.[\\/]' -and
        -not [IO.Path]::IsPathRooted($planRelative)) {
        throw 'Roster expansion plan must be outside squad state.'
    }
    $planHash = (Get-FileHash -LiteralPath $PlanPath -Algorithm SHA256).Hash
    if ($planHash -cne $ExpectedPlanSha256.ToUpperInvariant()) { throw 'Roster expansion plan hash does not match the confirmed plan.' }

    $plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json -AsHashtable -Depth 50 -DateKind String
    Assert-FieldSet $plan @(
        'schemaVersion', 'squadRoot', 'scope', 'runId', 'generatedAt', 'modelRouting',
        'packs', 'requestedRoles', 'alreadyPresentRoles', 'addedRoles', 'provenance',
        'baseline', 'outputs', 'routingRowsAdded'
    )
    if ($plan.schemaVersion -ne 1 -or $plan.scope -notin @('plain-squad', 'federation-member') -or
        $plan.modelRouting -notin @('off', 'ranked', 'economy', 'manual') -or
        $plan.addedRoles -isnot [array] -or -not $plan.addedRoles.Count -or
        $plan.packs -isnot [array] -or $plan.routingRowsAdded -isnot [ValueType] -or
        $plan.routingRowsAdded -is [bool] -or $plan.routingRowsAdded -lt 0) {
        throw 'Roster expansion plan metadata is invalid.'
    }
    Assert-FieldSet $plan.provenance @('before', 'after')
    Assert-FieldSet $plan.baseline @('files', 'history') @('federation')
    Assert-FieldSet $plan.outputs @('team', 'routing', 'decisions')
    foreach ($name in @('team', 'routing', 'decisions')) {
        Assert-FieldSet $plan.outputs[$name] @('bytes', 'sha256', 'contentBase64')
        $bytes = [Convert]::FromBase64String([string]$plan.outputs[$name].contentBase64)
        if ($bytes.Length -ne [int64]$plan.outputs[$name].bytes -or
            (Get-Hash $bytes) -cne [string]$plan.outputs[$name].sha256) {
            throw "Roster expansion output '$name' does not match its sealed digest."
        }
        $plannedName = switch ($name) {
            'team' { 'team.md' }
            'routing' { 'routing.md' }
            'decisions' { 'decisions.md' }
        }
        $planned[$plannedName] = $bytes
    }

    $root = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path ([string]$plan.squadRoot)
    $relativeRoot = [IO.Path]::GetRelativePath($RepoRoot, $root) -replace '\\', '/'
    if ($relativeRoot -cne [string]$plan.squadRoot -or
        $relativeRoot -notmatch '^\.copilot-tracking/squad(?:/members/[a-z0-9][a-z0-9-]*)?$') {
        throw 'Roster expansion plan is not bound to this repository root.'
    }
    if (($plan.scope -eq 'plain-squad') -ne ($relativeRoot -ceq '.copilot-tracking/squad')) {
        throw 'Roster expansion plan scope does not match SquadRoot.'
    }
    if (Test-Path -LiteralPath (Join-Path $root 'federation.md') -PathType Leaf) {
        throw 'Roster expansion cannot apply to a federation root.'
    }

    foreach ($name in @(
            'team.md', 'routing.md', 'decisions.md', 'notifications.md',
            'state.json', 'consumption.md', 'consumption-rates.md'
        )) {
        if (-not $plan.baseline.files.Contains($name)) { throw "Roster expansion baseline is missing $name." }
        Assert-FieldSet $plan.baseline.files[$name] @('bytes', 'sha256')
    }
    Assert-FieldSet $plan.baseline.history @('digest', 'files', 'directories', 'bytes')
    if ($plan.scope -eq 'federation-member') {
        if (-not $plan.baseline.Contains('federation')) { throw 'Federation-member plan is missing its registry baseline.' }
        Assert-FieldSet $plan.baseline.federation @('member', 'registry')
        Assert-FieldSet $plan.baseline.federation.registry @('bytes', 'sha256')
    }
    elseif ($plan.baseline.Contains('federation')) { throw 'Plain-squad plan cannot carry a federation baseline.' }

    Assert-Baseline -Expected $plan.baseline -Root $root -Repository $RepoRoot -RelativeRoot $relativeRoot
    $deadline = [DateTime]::UtcNow.AddSeconds($LockTimeoutSeconds)
    $lockRoots = [Collections.Generic.List[string]]::new()
    if ($plan.scope -eq 'federation-member') {
        $null = $lockRoots.Add([IO.Path]::GetFullPath((Join-Path $RepoRoot '.copilot-tracking' 'squad')))
    }
    $null = $lockRoots.Add($root)
    foreach ($lockRoot in $lockRoots) {
        $null = $locks.Add((Enter-WriterLock -Path $lockRoot -Deadline $deadline))
    }
    Assert-Baseline -Expected $plan.baseline -Root $root -Repository $RepoRoot -RelativeRoot $relativeRoot

    foreach ($name in @('team.md', 'routing.md', 'decisions.md')) {
        $originals[$name] = [IO.File]::ReadAllBytes((Join-Path $root $name))
    }
    try {
        Write-AtomicFile -Path (Join-Path $root 'decisions.md') -Bytes $planned['decisions.md']
        $wrote = $true
        Write-AtomicFile -Path (Join-Path $root 'team.md') -Bytes $planned['team.md']
        Write-AtomicFile -Path (Join-Path $root 'routing.md') -Bytes $planned['routing.md']

        foreach ($name in @('team.md', 'routing.md', 'decisions.md')) {
            $actual = [IO.File]::ReadAllBytes((Join-Path $root $name))
            if ((Get-Hash $actual) -cne (Get-Hash $planned[$name])) {
                throw "Roster expansion read-back failed for $name."
            }
        }
        $writtenRoster = @(Get-SquadRoster $root)
        foreach ($role in $plan.addedRoles) {
            if (@($writtenRoster | Where-Object { $_.Role -ceq $role }).Count -ne 1) {
                throw "Roster expansion read-back did not contain exactly one '$role' row."
            }
        }
        $writtenRouting = @(Read-SquadTables (Join-Path $root 'routing.md') |
                Where-Object {
                    'Pattern / Keyword' -in $_.Header -and 'Role(s)' -in $_.Header -and
                    'Autonomy Tier' -in $_.Header -and 'Parallel-Eligible' -in $_.Header
                })
        if ($writtenRouting.Count -ne 1) { throw 'Roster expansion routing read-back is missing or ambiguous.' }
        Assert-Baseline -Expected $plan.baseline -Root $root -Repository $RepoRoot -RelativeRoot $relativeRoot `
            -IgnoreFiles @('team.md', 'routing.md', 'decisions.md')

        $ledger = Invoke-SquadLocalScript -Name 'Measure-SquadLedger.ps1' -Arguments @('-SquadRoot', $root, '-Check')
        $ledgerText = ((@($ledger.stdout, $ledger.stderr) | Where-Object { $_ }) -join "`n").Trim()
        if ($ledger.exitCode -ne 0 -or $ledgerText -notmatch 'Measure-SquadLedger -Check: PASS') {
            throw "Read-only ledger check failed after roster expansion: $ledgerText"
        }
    }
    catch {
        $detail = $_.Exception.Message
        $exitCode = 3
        if ($wrote) {
            try {
                Restore-Output
                $detail += ' Original roster files restored.'
            }
            catch { $detail += " $($_.Exception.Message)" }
        }
        throw $detail
    }

    $stopwatch.Stop()
    [ordered]@{
        status = 'expanded'
        scope = $plan.scope
        squadRoot = $relativeRoot
        runId = $plan.runId
        packs = $plan.packs
        addedRoles = $plan.addedRoles
        routingRowsAdded = [int]$plan.routingRowsAdded
        modelRouting = $plan.modelRouting
        ledgerCheck = 'PASS'
        accountingPreserved = $true
        statePreserved = $true
        historyPreserved = $true
        elapsedMs = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
    } | ConvertTo-Json -Depth 10 -Compress
    exit 0
}
catch {
    [Console]::Error.WriteLine("Expand-SquadRoster: $($_.Exception.Message)")
    exit $exitCode
}
finally {
    for ($index = $locks.Count - 1; $index -ge 0; $index--) { $locks[$index].Dispose() }
}
