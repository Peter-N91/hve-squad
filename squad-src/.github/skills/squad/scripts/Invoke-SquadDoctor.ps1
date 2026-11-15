#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Checks Squad locally and applies only confirmed, allowlisted repairs.
.DESCRIPTION
    AI cost: none. Default is read-only. Host inventory is supplied as a JSON
    array; files on disk are not proof of dispatchability. Exit 0: healthy or
    fully repaired; 2: unresolved findings; 1: execution failure.
    Rates repairs use the existing seeder under the shared handoff lock, with a
    content-addressed backup. No network, installation, or arbitrary commands.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$SquadRoot = '.copilot-tracking/squad',
    [string]$InventoryPath,
    [ValidateSet('all', 'security', 'rai', 'privacy', 'accessibility', 'project-planning', 'design-thinking', 'coding-standards')]
    [string]$Scope = 'all',
    [ValidateSet('rates')]
    [string[]]$Repair = @(),
    [switch]$Confirmed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$findings = [Collections.Generic.List[object]]::new()
$repairs = [Collections.Generic.List[object]]::new()
$receipt = [ordered]@{
    schemaVersion = 1; status = 'error'; repoRoot = $RepoRoot
    squadRoot = $SquadRoot; scope = $Scope; findings = $findings; repairs = $repairs
}

function Add-DoctorFinding {
    param([string]$Id, [string]$Status, [string]$Path, [string]$Detail, [string]$RepairId = '')
    $findings.Add([ordered]@{ id = $Id; status = $Status; path = $Path; detail = $Detail; repairId = $RepairId })
}

function Invoke-DoctorRateRepair {
    param([string]$Root)
    $target = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $Root 'consumption-rates.md') -AllowMissing
    $arguments = @('-SquadRoot', $Root)
    $check = Invoke-SquadLocalScript -Name 'Initialize-SquadConsumptionRates.ps1' -Arguments ($arguments + '-Check')
    if ($check.exitCode -eq 0) {
        Add-DoctorFinding 'rates' 'pass' $target $check.stdout
        return
    }
    if ('rates' -notin $Repair) {
        Add-DoctorFinding 'rates' 'fail' $target ($check.stdout + $check.stderr) 'rates'
        return
    }

    $lockKey = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant()))).Substring(0, 16)
    $lockPath = Join-Path ([IO.Path]::GetTempPath()) "hve-squad-handoff-$lockKey.lock"
    $lock = $null
    try {
        try {
            $lock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        catch [IO.IOException] {
            Add-DoctorFinding 'rates' 'fail' $target "Writer lock unavailable; stop writers and retry: $($_.Exception.Message)" 'rates'
            return
        }
        $target = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $target -AllowMissing
        $check = Invoke-SquadLocalScript -Name 'Initialize-SquadConsumptionRates.ps1' -Arguments ($arguments + '-Check')
        if ($check.exitCode -eq 0) {
            Add-DoctorFinding 'rates' 'pass' $target 'Already repaired by another writer.'
            return
        }
        $backup = ''
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
            $backup = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $Root "consumption-rates.doctor-$hash.bak") -AllowMissing
            if (Test-Path -LiteralPath $backup) {
                if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) {
                    throw "Doctor backup collision: $backup"
                }
            }
            else { [IO.File]::Copy($target, $backup, $false) }
        }
        $result = Invoke-SquadLocalScript -Name 'Initialize-SquadConsumptionRates.ps1' -Arguments $arguments
        $repairReceipt = [ordered]@{
            id = 'rates'; path = $target; backup = $backup; status = 'failed'
            detail = ($result.stdout + $result.stderr)
        }
        $repairs.Add($repairReceipt)
        if ($result.exitCode -ne 0) {
            Add-DoctorFinding 'rates' 'fail' $target $repairReceipt.detail 'rates'
            return
        }
        $verify = Invoke-SquadLocalScript -Name 'Initialize-SquadConsumptionRates.ps1' -Arguments ($arguments + '-Check')
        if ($verify.exitCode -ne 0) {
            Add-DoctorFinding 'rates' 'fail' $target ($verify.stdout + $verify.stderr) 'rates'
            return
        }
        $repairReceipt.status = 'repaired'
        Add-DoctorFinding 'rates' 'pass' $target $verify.stdout
    }
    finally { if ($lock) { $lock.Dispose() } }
}

function Test-DoctorRoot {
    param([string]$Root)
    $Root = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $Root -AllowMissing
    $team = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $Root 'team.md') -AllowMissing
    $federation = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $Root 'federation.md') -AllowMissing
    $isFederation = Test-Path -LiteralPath $federation -PathType Leaf
    if (-not $isFederation -and -not (Test-Path -LiteralPath $team -PathType Leaf)) {
        if (-not (Test-Path -LiteralPath $Root) -or @(Get-ChildItem -LiteralPath $Root -Force).Count -eq 0) {
            Add-DoctorFinding 'state' 'pass' $Root 'No squad state; Init remains a separate user choice.'
        }
        else { Add-DoctorFinding 'state' 'fail' $Root 'Partial root without team.md or federation.md; explicit recovery required.' }
        return
    }
    $required = if ($isFederation) { @('meta-routing.md', 'state.json', 'decisions.md', 'consumption.md') }
    else { @('routing.md', 'state.json', 'decisions.md', 'consumption.md', 'history') }
    $complete = $true
    foreach ($name in $required) {
        $path = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $Root $name) -AllowMissing
        $type = if ($name -eq 'history') { 'Container' } else { 'Leaf' }
        if (-not (Test-Path -LiteralPath $path -PathType $type)) {
            Add-DoctorFinding 'state-file' 'fail' $path 'Required state missing; use the existing Init/Scribe recovery, not fabricated state.'
            $complete = $false
        }
    }
    Invoke-DoctorRateRepair $Root
    if ($complete) {
        $brief = Invoke-SquadLocalScript -Name 'Get-SquadDispatchBrief.ps1' -Arguments @(
            '-RepoRoot', $RepoRoot, '-SquadRoot', $Root, '-AsJson', '-CheckLedger')
        if ($brief.exitCode -ne 0) {
            Add-DoctorFinding 'dispatch-brief' 'fail' $Root ($brief.stdout + $brief.stderr)
        }
        else {
            $data = ConvertFrom-Json -InputObject $brief.stdout -AsHashtable
            $blocked = $data.status -ne 'ok' -or
            ($data.ContainsKey('ledgerCheck') -and $data.ledgerCheck.status -ne 'PASS')
            Add-DoctorFinding 'dispatch-brief' $(if ($blocked) { 'fail' } else { 'pass' }) $Root $brief.stdout
        }
    }
    if ($isFederation) {
        $tables = @(Read-SquadTables $federation | Where-Object { 'Sub-squad' -in $_.Header -and 'Location' -in $_.Header })
        if ($tables.Count -ne 1) { throw 'Federation registry is missing or ambiguous.' }
        foreach ($row in $tables[0].Rows) {
            $location = $row['Location'].Trim('`').TrimEnd('/', '\')
            if ($location -notmatch '^members[/\\][a-z0-9]+(?:-[a-z0-9]+)*$') {
                throw "Unsafe federation member location: $location"
            }
            $member = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $Root $location)
            $memberTeam = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $member 'team.md') -AllowMissing
            if (-not (Test-Path -LiteralPath $memberTeam -PathType Leaf)) {
                Add-DoctorFinding 'member-state' 'fail' $member 'Registered member has no team.md.'
                continue
            }
            if (Test-Path -LiteralPath (Join-Path $member 'federation.md')) { throw 'Nested federation is not a squad member.' }
            Test-DoctorRoot $member
        }
    }
}

try {
    if ($Repair.Count -gt 0 -and -not $Confirmed) { throw 'Repair requires explicit -Confirmed approval; check mode writes nothing.' }
    Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force -DisableNameChecking
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $SquadRoot = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $SquadRoot -AllowMissing
    $receipt.repoRoot = $RepoRoot
    $receipt.squadRoot = $SquadRoot
    foreach ($name in @('Get-SquadDispatchBrief.ps1', 'Initialize-SquadConsumptionRates.ps1', 'Measure-SquadLedger.ps1',
            'New-SquadDispatchPlan.ps1', 'Write-SquadHandoff.ps1', 'Test-SquadTurnCompletion.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name) -PathType Leaf)) {
            throw "Installed runtime file missing: $name. Update/reinstall this distribution and start a fresh session."
        }
    }
    Add-DoctorFinding 'runtime' 'pass' $PSScriptRoot 'Required runtime scripts are present.'
    $inventory = $null
    if ($InventoryPath) {
        $inventoryFile = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $InventoryPath
        $inventory = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($inventoryFile)) -NoEnumerate
        if ($inventory -isnot [array] -or @($inventory | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count) {
            throw 'Inventory must be a JSON array of nonempty, exact host agent IDs or names.'
        }
    }
    $domains = [ordered]@{
        security = @('Security Planner', 'SSSC Planner', 'Skill Assessor', 'Supply Chain Skill Assessor', 'Finding Deep Verifier', 'Report Generator', 'CVE Analyzer')
        rai = @('RAI Planner', 'RAI Skill Assessor')
        privacy = @('Privacy Planner')
        accessibility = @('Accessibility Framework Assessor', 'Accessibility Surface Inventory')
        'project-planning' = @('PRD Builder', 'BRD Builder', 'Functional Planner', 'System Architecture Reviewer', 'ADR Creator', 'Meeting Analyst', 'UX UI Designer')
        'design-thinking' = @('DT Coach', 'DT Learning Tutor')
        'coding-standards' = @('Code Review Functional', 'Code Review Standards', 'Code Review Security', 'Code Review Accessibility')
    }
    foreach ($domain in $domains.Keys) {
        if ($Scope -ne 'all' -and $Scope -ne $domain) { continue }
        if ($null -eq $inventory) {
            Add-DoctorFinding "domain:$domain" 'unverified' '' 'Host dispatchable-agent inventory unavailable.'
            continue
        }
        $resolved = @($inventory | Where-Object {
                $id = ($_ -split ':')[-1]
                foreach ($name in $domains[$domain]) {
                    if ($_ -ceq $name -or $id -ceq ($name.ToLowerInvariant() -replace ' ', '-')) { return $true }
                }
                return $false
            } | Sort-Object -Unique)
        if ($resolved.Count) { Add-DoctorFinding "domain:$domain" 'pass' '' ($resolved -join ', ') }
        else { Add-DoctorFinding "domain:$domain" 'fail' '' 'Missing host agent: update/reinstall hve-squad in this client, then start a fresh session; APM consumers rerun their pinned install. Do not install a second HVE Core plugin.' }
    }
    Test-DoctorRoot $SquadRoot
    $unresolved = @($findings | Where-Object { $_.status -ne 'pass' })
    $receipt.status = if ($unresolved.Count) { 'attention' } elseif ($repairs.Count) { 'repaired' } else { 'healthy' }
    $receipt | ConvertTo-Json -Depth 12 -Compress
    if ($unresolved.Count) { exit 2 }
    exit 0
}
catch {
    Add-DoctorFinding 'execution' 'fail' $SquadRoot $_.Exception.Message
    $receipt | ConvertTo-Json -Depth 12 -Compress
    exit 1
}
