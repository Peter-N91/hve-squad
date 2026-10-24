#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Resolves selected work endpoints and orders explicit dependencies into safe waves.
.DESCRIPTION
    AI cost: none. Input is a routing decision, not executable instructions:
    { squadRoot, units: [{ id, role | squad, pattern?, owner?, agent?, selectionCue?,
      execution?, dependsOn?: [], parallel?: bool, readOnly?: bool,
      writePaths?: [], allowedOutputs?: [] }], council?: bool, planPath?: string,
      admissionApproved?: bool, agentTypes?: [] }.
    agentTypes is the exact host-advertised custom-agent enum. When supplied,
    native type IDs are resolved by installed filename/name, never guessed from a
    display label or replaced with a built-in agent.
    No model is launched and no state is written. The result never grants approval
    or cost admission. Native dispatch, semantic gates and exact input forwarding
    remain with the coordinator. Dependencies always override parallel eligibility.
    Unproven write independence serializes; declared overlapping parallel writes,
    invalid endpoints, unknown dependencies and cycles fail before a wave is returned.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputPath,
    [string]$RepoRoot = (Get-Location).ProviderPath,
    [ValidateRange(0, 2147483647)][int]$MaxConcurrent = 0
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force

try {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $inputData = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -AsHashtable
    if ($inputData -isnot [Collections.IDictionary]) { throw 'Expected an object.' }
    foreach ($key in @('squadRoot', 'units')) {
        if (-not $inputData.Contains($key)) { throw "Missing dispatch-plan field: $key" }
    }
    foreach ($key in $inputData.Keys) {
        if ($key -notin @('squadRoot', 'units', 'council', 'planPath', 'admissionApproved', 'agentTypes')) { throw "Unsupported dispatch-plan field: $key" }
    }
    if ($inputData.units -isnot [array] -or $inputData.units.Count -eq 0) { throw 'units must be a nonempty array.' }
    foreach ($key in @('council', 'admissionApproved')) {
        if ($inputData.Contains($key) -and $inputData[$key] -isnot [bool]) { throw "$key must be boolean." }
    }
    $agentTypes = @()
    if ($inputData.Contains('agentTypes')) {
        if ($inputData.agentTypes -isnot [array] -or @($inputData.agentTypes | Where-Object { $_ -isnot [string] }).Count) { throw 'agentTypes must be the host string array.' }
        $agentTypes = @($inputData.agentTypes)
    }
    $root = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $inputData.squadRoot
    $federation = Test-Path -LiteralPath (Join-Path $root 'federation.md')
    $council = $inputData.Contains('council') -and $inputData.council
    $planPath = if ($inputData.Contains('planPath')) { Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $inputData.planPath } else { '' }
    $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json -AsHashtable
    $agents = Get-SquadAgentIndex $RepoRoot
    $roster = @()
    $registry = @()
    if ($federation) {
        $tables = @(Read-SquadTables (Join-Path $root 'federation.md') | Where-Object { 'Sub-squad' -in $_.Header -and 'Location' -in $_.Header })
        if ($tables.Count -ne 1) { throw 'Missing federation registry.' }
        $registry = $tables[0].Rows
    }
    else { $roster = @(Get-SquadRoster $root) }
    $routingPath = Join-Path $root $(if ($federation) { 'meta-routing.md' } else { 'routing.md' })
    $routingTables = @(Read-SquadTables $routingPath | Where-Object { 'Parallel-Eligible' -in $_.Header })
    if ($routingTables.Count -ne 1) { throw 'Missing or ambiguous routing table.' }
    $routing = $routingTables[0].Rows
    $teamText = if ($federation) { '' } else { [IO.File]::ReadAllText((Join-Path $root 'team.md')) }
    $modeMatch = [regex]::Match($teamText, '(?m)^Model routing:[ \t]*`?(?<mode>off|ranked|economy|manual)`?[ \t]*\r?$')
    $modelRouting = if ($modeMatch.Success) { $modeMatch.Groups['mode'].Value } else { 'off' }
    if (-not $MaxConcurrent) {
        $cap = 0
        $MaxConcurrent = if ([int]::TryParse($env:COPILOT_SUBAGENT_MAX_CONCURRENT, [ref]$cap) -and $cap -gt 0) { $cap } else { 4 }
    }
    if ($state.Contains('currentRun') -and $state.currentRun.Contains('costPreflight') -and
        $state.currentRun.costPreflight.decision -eq 'approved-over-ceiling') { $MaxConcurrent = 1 }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $nodes = [Collections.Generic.List[object]]::new()
    foreach ($unit in $inputData.units) {
        if ($unit -isnot [Collections.IDictionary]) { throw 'Each unit must be an object.' }
        foreach ($key in $unit.Keys) {
            if ($key -notin @('id', 'role', 'squad', 'pattern', 'owner', 'agent', 'selectionCue', 'execution', 'dependsOn', 'parallel', 'readOnly', 'writePaths', 'allowedOutputs')) { throw "Unsupported dispatch unit field: $key" }
        }
        if (-not $unit.Contains('id') -or $unit.id -isnot [string] -or $unit.id -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or -not $seen.Add($unit.id)) {
            throw 'Each unit needs a unique lower-kebab-case id.'
        }
        foreach ($key in @('parallel', 'readOnly')) {
            if ($unit.Contains($key) -and $unit[$key] -isnot [bool]) { throw "$($unit.id).$key must be boolean." }
        }
        foreach ($key in @('dependsOn', 'writePaths', 'allowedOutputs')) {
            if ($unit.Contains($key) -and $unit[$key] -isnot [array]) { throw "$($unit.id).$key must be an array." }
        }
        $depends = @(if ($unit.Contains('dependsOn')) { $unit.dependsOn })
        if (@($depends | Where-Object { $_ -isnot [string] }).Count -or @($depends | Select-Object -Unique).Count -ne $depends.Count) { throw 'Dependencies must be distinct string IDs.' }
        $paths = @(
            if ($unit.Contains('writePaths')) {
                foreach ($path in $unit.writePaths) { Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $path -AllowMissing }
            }
        )
        $wantsParallel = $unit.Contains('parallel') -and $unit.parallel
        $readOnly = $unit.Contains('readOnly') -and $unit.readOnly
        $endpoint = [ordered]@{}
        if ($federation) {
            if (-not $unit.Contains('squad') -or $unit.Contains('role')) { throw 'A federation unit selects squad, not role.' }
            $rows = @($registry | Where-Object { $_['Sub-squad'] -ceq $unit.squad })
            if ($rows.Count -ne 1) { throw "Unknown or ambiguous sub-squad: $($unit.squad)" }
            $name = $unit.squad
            if ($name -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or $rows[0].Kind -ne 'in-repo' -or
                ($rows[0].Location -replace '\\', '/').TrimEnd('/') -cne "members/$name") { throw 'Unsupported federation location.' }
            $memberRoot = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $root 'members' $name)
            foreach ($file in @('team.md', 'routing.md', 'state.json')) {
                if (-not (Test-Path -LiteralPath (Join-Path $memberRoot $file) -PathType Leaf)) { throw "Sub-squad '$name' is not built." }
            }
            $matchingRoutes = @($routing | Where-Object { $_['Sub-squad'] -ceq $name })
            $eligible = @($matchingRoutes | Where-Object { $_['Parallel-Eligible'] -eq 'yes' }).Count -gt 0
            $endpoint = [ordered]@{ squad = $name; squadRoot = $memberRoot; protocol = 'scoped-single-squad'; inputsReadOnly = $true }
        }
        else {
            if (-not $unit.Contains('role') -or $unit.Contains('squad')) { throw 'A squad unit selects role, not squad.' }
            $owner = if ($unit.Contains('owner')) { [string]$unit.owner } else { '' }
            $execution = if ($unit.Contains('execution')) { [string]$unit.execution } else { '' }
            $matchingRoutes = @($routing | Where-Object { $unit.role -cin @($_['Role(s)'] -split ',\s*' | ForEach-Object { $_ -replace ' \(optional\)$', '' }) })
            if ($unit.Contains('pattern')) {
                $matchingRoutes = @($matchingRoutes | Where-Object { $_['Pattern / Keyword'] -ceq $unit.pattern })
                if ($matchingRoutes.Count -ne 1) { throw 'The selected routing pattern does not uniquely map to this role.' }
            }
            $eligible = $council -or @($matchingRoutes | Where-Object { $_['Parallel-Eligible'] -eq 'yes' }).Count -gt 0 -or [bool]$planPath
            $selection = Resolve-SquadConnectorExecution -TeamPath (Join-Path $root 'team.md') -Role $unit.role -Owner $owner -Execution $execution `
                -Unattended:($state.mode -ne 'interactive') -CouncilDispatch:$council -ParallelEligible:$eligible `
                -AllowedOutputs @(if ($unit.Contains('allowedOutputs')) { $unit.allowedOutputs }) `
                -AdmissionApproved:($inputData.Contains('admissionApproved') -and $inputData.admissionApproved)
            if ($selection.Status -ne 'ok') { throw "Endpoint resolution $($selection.Status): $($selection.Reason). Follow references/connector-role-modes.md; do not substitute." }
            $rows = @($roster | Where-Object { $_.Role -ceq $unit.role -and (-not $owner -or $_['Member Name'] -ceq $owner) })
            $selectedRows = @($rows | Where-Object { $_['Member Name'] -ceq $selection.MemberName -and $_['Agent Name (Primary)'] -ceq $selection.Agent })
            if ($selectedRows.Count -eq 1) { $row = $selectedRows[0] }
            elseif ($rows.Count -eq 1) { $row = $rows[0] }
            else { throw 'Selected roster member is ambiguous; supply owner.' }
            $agent = $selection.Agent
            if ($unit.Contains('agent') -and $unit.agent -cne $agent) {
                $alternates = @($row['Alternate Agents'] -split ',\s*')
                if ($selection.Choice -ne 'original' -or $unit.agent -cnotin $alternates -or
                    -not $unit.Contains('selectionCue') -or [string]::IsNullOrWhiteSpace($unit.selectionCue) -or
                    $row['Selection Cue'].IndexOf($unit.selectionCue, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw 'An Alternate requires its actual roster Selection Cue; connector endpoints cannot be substituted.' }
                $agent = $unit.agent
            }
            $selectedAgents = @($agent)
            if ($selection.Choice -eq 'both') { $selectedAgents += 'Squad Connector' }
            foreach ($name in $selectedAgents) {
                if (-not $agents.ContainsKey($name) -or -not $agents[$name].dispatchable) { throw "Selected agent '$name' is not installed and dispatchable." }
            }
            $nativeTypes = [ordered]@{}
            if ($inputData.Contains('agentTypes')) {
                foreach ($name in $selectedAgents) {
                    $stem = [IO.Path]::GetFileName($agents[$name].path) -replace '\.agent\.md$', ''
                    $available = @($agentTypes | Where-Object {
                            $_ -notin @('task', 'explore', 'general-purpose', 'research', 'rubber-duck', 'code-review', 'security-review') -and
                            ($_ -ceq $name -or ($_ -split ':')[-1] -ceq $stem)
                        } | Select-Object -Unique)
                    if ($available.Count -ne 1) { throw "No unique host-advertised native type for '$name'; enable or disambiguate it before dispatch." }
                    $nativeTypes[$name] = $available[0]
                }
            }
            $tiers = @($matchingRoutes | ForEach-Object { $_['Autonomy Tier'] })
            $tier = if ('escalate' -in $tiers -or -not $tiers.Count) { 'escalate' } elseif ($council -or 'confirm' -in $tiers) { 'confirm' } else { 'auto' }
            $model = if ($modelRouting -ne 'off' -and $unit.role -ne 'scribe' -and $row.ContainsKey('Model')) { $row.Model } else { '' }
            if ($model -in @('-', [string][char]0x2014)) { $model = '' }
            $endpoint = [ordered]@{
                role = $unit.role; memberName = $selection.MemberName; agent = $agent
                execution = $selection.Choice; connectorSelection = $selection
                squadRoot = $root; deliverableRoot = $row['Deliverable Root']
                model = $model; modelRouting = $modelRouting; autonomyTier = $tier
                nativeAgentTypes = $nativeTypes
            }
        }
        $parallel = $wantsParallel -and $eligible -and ($readOnly -or $paths.Count -gt 0) -and ($federation -or $tier -ne 'escalate')
        $reason = if (-not $wantsParallel) { 'sequential-request' } elseif (-not $eligible) { 'routing-not-parallel-eligible' }
        elseif (-not $federation -and $tier -eq 'escalate') { 'escalation-cannot-batch' }
        elseif (-not $readOnly -and -not $paths.Count) { 'write-independence-unproven' } else { 'explicit-independent-work' }
        $nodes.Add([pscustomobject]@{ id = $unit.id; dependsOn = $depends; parallel = $parallel; parallelReason = $reason; writePaths = $paths; endpoint = $endpoint })
    }
    foreach ($node in $nodes) {
        foreach ($dependency in $node.dependsOn) {
            if (-not $seen.Contains($dependency) -or $dependency -ceq $node.id) { throw "Invalid dependency '$dependency' for '$($node.id)'." }
        }
    }
    $completed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $waves = [Collections.Generic.List[object]]::new()
    while ($completed.Count -lt $nodes.Count) {
        $ready = @($nodes | Where-Object { -not $completed.Contains($_.id) -and @($_.dependsOn | Where-Object { -not $completed.Contains($_) }).Count -eq 0 })
        if (-not $ready.Count) { throw 'Dispatch dependencies contain a cycle.' }
        $batch = if (-not $ready[0].parallel) { @($ready[0]) } else { @($ready | Where-Object parallel | Select-Object -First $MaxConcurrent) }
        for ($i = 0; $i -lt $batch.Count; $i++) {
            for ($j = $i + 1; $j -lt $batch.Count; $j++) {
                foreach ($left in $batch[$i].writePaths) {
                    foreach ($right in $batch[$j].writePaths) {
                        $relative = [IO.Path]::GetRelativePath($left, $right)
                        $reverse = [IO.Path]::GetRelativePath($right, $left)
                        if (($relative -eq '.' -or $relative -notmatch '^\.\.(?:[\\/]|$)') -or
                            ($reverse -eq '.' -or $reverse -notmatch '^\.\.(?:[\\/]|$)')) { throw "Parallel write sets overlap: $($batch[$i].id), $($batch[$j].id)." }
                    }
                }
            }
        }
        $waves.Add([ordered]@{ order = $waves.Count + 1; units = @($batch | ForEach-Object id); barrier = 'artifact-before-dependent-dispatch; history-consumption-state-before-completion' })
        foreach ($node in $batch) { $null = $completed.Add($node.id) }
    }
    [ordered]@{ status = 'ok'; kind = $(if ($federation) { 'federation' } else { 'squad' }); gates = 'not-evaluated'; admission = 'not-granted'; waves = $waves.ToArray(); units = $nodes.ToArray(); stateWritten = $false } | ConvertTo-Json -Depth 20 -Compress
}
catch {
    [Console]::Error.WriteLine("New-SquadDispatchPlan: $($_.Exception.Message)")
    exit 1
}
