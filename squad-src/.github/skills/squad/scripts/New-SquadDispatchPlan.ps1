#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Resolves selected work endpoints, model routes, exact spend, and safe dependency waves.
.DESCRIPTION
    AI cost: none. Input is a routing decision, not executable instructions:
    { squadRoot, units: [{ id, role | squad, pattern?, owner?, agent?, selectionCue?,
      execution?, dependsOn?: [], parallel?: bool, readOnly?: bool,
      writePaths?: [], allowedOutputs?: [] }], council?: bool, planPath?: string,
      admissionApproved?: bool, agentTypes?: [], availableModels?: [],
      sessionModel?: string, asOf?: date, requestedModelRouting?: ranked|economy|manual,
      manualModels?: {role:model}, economyConsent?: {user,tradeAccepted,neverWeakened,timestamp?},
      cost?: {runId, roundId, ceilingUsd, sessionLog?|usageOutputPath?,
      baselineNanoAiu?, pendingUsd?, reserveMultiplier?, timestamp?} }.
    agentTypes is the exact host-advertised custom-agent enum. When supplied,
    native type IDs are resolved by installed filename/name, never guessed from a
    display label or replaced with a built-in agent.
    No model is launched and no state is written. Ranked, economy, and manual routing
    are resolved only for the actual role units in this input. Changed Model cells are
    returned as a compare-and-swap routing refresh for Set-SquadModelRouting.ps1.
    When cost is supplied, complete native usage records are authoritative consumed
    spend and only the actual next wave plus one coordinator lookup is reserved.
    The returned Cost Preflight object must be persisted before dispatch.
    Native dispatch, semantic gates and exact input forwarding remain with the
    coordinator. Dependencies always override parallel eligibility.
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
Import-Module (Join-Path $PSScriptRoot 'SquadUsage.psm1') -Force

try {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $inputData = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -AsHashtable
    if ($inputData -isnot [Collections.IDictionary]) { throw 'Expected an object.' }
    foreach ($key in @('squadRoot', 'units')) {
        if (-not $inputData.Contains($key)) { throw "Missing dispatch-plan field: $key" }
    }
    foreach ($key in $inputData.Keys) {
        if ($key -notin @('squadRoot', 'units', 'council', 'planPath', 'admissionApproved', 'agentTypes', 'availableModels', 'sessionModel', 'asOf', 'requestedModelRouting', 'manualModels', 'economyConsent', 'cost')) { throw "Unsupported dispatch-plan field: $key" }
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
    $availableModels = @()
    if ($inputData.Contains('availableModels')) {
        if ($inputData.availableModels -isnot [array] -or @($inputData.availableModels | Where-Object { $_ -isnot [string] }).Count) { throw 'availableModels must be the host string array.' }
        $availableModels = @($inputData.availableModels)
    }
    $sessionModel = if ($inputData.Contains('sessionModel')) { [string]$inputData.sessionModel } else { '' }
    $asOf = if ($inputData.Contains('asOf')) {
        $parsed = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$inputData.asOf, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsed)) { throw 'asOf must be a date.' }
        $parsed
    }
    else { Get-Date }
    $requestedModelRouting = if ($inputData.Contains('requestedModelRouting')) { [string]$inputData.requestedModelRouting } else { '' }
    if ($requestedModelRouting -and $requestedModelRouting -notin @('ranked', 'economy', 'manual')) {
        throw 'requestedModelRouting must be ranked, economy, or manual.'
    }
    $manualModels = if ($inputData.Contains('manualModels')) { $inputData.manualModels } else { [ordered]@{} }
    if ($manualModels -isnot [Collections.IDictionary]) { throw 'manualModels must be a role-to-model object.' }
    $economyConsent = if ($inputData.Contains('economyConsent')) { $inputData.economyConsent } else { $null }
    if ($null -ne $economyConsent -and $economyConsent -isnot [Collections.IDictionary]) { throw 'economyConsent must be an object.' }
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
    $recordedModelRouting = if ($modeMatch.Success) { $modeMatch.Groups['mode'].Value } else { 'off' }
    $modelRouting = if ($requestedModelRouting) { $requestedModelRouting } else { $recordedModelRouting }
    $routingModeChanged = $modelRouting -cne $recordedModelRouting
    if ($manualModels.Count -gt 0 -and $modelRouting -ne 'manual') { throw 'manualModels requires Model routing: manual.' }
    if ($null -ne $economyConsent -and (-not $routingModeChanged -or $modelRouting -ne 'economy')) {
        throw 'economyConsent is allowed only while switching into economy.'
    }
    if ($routingModeChanged -and $modelRouting -eq 'economy') {
        if ($null -eq $economyConsent) { throw 'Switching into economy requires economyConsent.' }
        foreach ($key in @('user', 'tradeAccepted', 'neverWeakened')) {
            if (-not $economyConsent.Contains($key) -or $economyConsent[$key] -isnot [string] -or
                [string]::IsNullOrWhiteSpace($economyConsent[$key]) -or $economyConsent[$key] -match '[\r\n]') {
                throw "economyConsent.$key must be a nonempty single-line string."
            }
        }
        foreach ($key in $economyConsent.Keys) {
            if ($key -notin @('user', 'tradeAccepted', 'neverWeakened', 'timestamp')) { throw "Unsupported economyConsent field: $key" }
        }
        $consentTimestamp = if ($economyConsent.Contains('timestamp')) {
            [DateTimeOffset]::Parse([string]$economyConsent.timestamp, [Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
        }
        else { [DateTimeOffset]::UtcNow }
        $economyConsent = [ordered]@{
            user = [string]$economyConsent.user
            tradeAccepted = [string]$economyConsent.tradeAccepted
            neverWeakened = [string]$economyConsent.neverWeakened
            timestamp = $consentTimestamp.ToString('o')
        }
    }
    $roleClasses = if ($federation) { @{} } else { Get-SquadRoleClassMap }
    $routeReport = $null
    $routeByIdentity = @{}
    $routingChanges = [Collections.Generic.List[object]]::new()
    $routingChangeRoles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $teamHash = if ($federation) { '' } else { (Get-FileHash -LiteralPath (Join-Path $root 'team.md') -Algorithm SHA256).Hash }
    if (-not $federation -and $modelRouting -ne 'off') {
        if ($availableModels.Count -eq 0 -and -not $sessionModel) {
            throw 'Active model routing requires the host availableModels enum or the literal sessionModel.'
        }
        $sessionModelKey = ($sessionModel.Trim().ToLowerInvariant() -replace '\s*\((?:copilot|github|anthropic|openai)\)\s*$', '' -replace '[\s_]+', '-')
        if ($availableModels.Count -eq 0 -and $sessionModelKey -in @('', 'auto', 'unknown', 'fast', 'default', 'extended')) {
            throw "Active model routing requires the host availableModels enum. sessionModel '$sessionModel' is routing metadata, not an availability inventory; pass the task tool's advertised model enum, or a concrete priced session model only on a host that advertises no model list."
        }
        $selectedRoles = @($inputData.units | ForEach-Object {
                if ($_ -is [Collections.IDictionary] -and $_.Contains('role')) { [string]$_.role }
            } | Where-Object { $_ } | Select-Object -Unique)
        foreach ($role in $manualModels.Keys) {
            if ($role -cnotin $selectedRoles) { throw "manualModels names an unselected role: $role" }
        }
        $routeArguments = @{
            SquadRoot = $root
            AvailableModels = $availableModels
            SessionModel = $sessionModel
            Mode = $modelRouting
            Role = $selectedRoles
            AsOf = $asOf
            Format = 'json'
        }
        if ($manualModels.Count -gt 0) { $routeArguments.ManualModels = $manualModels }
        $routeReport = & (Join-Path $PSScriptRoot 'Resolve-SquadModelRoute.ps1') @routeArguments | ConvertFrom-Json -AsHashtable -Depth 30
        if (-not $routeReport.Contains('availabilityResolved') -or -not [bool]$routeReport.availabilityResolved) {
            throw "Active model routing could not prove host availability ($($routeReport.availability)). Pass the host availableModels enum; do not substitute the catalog or sessionModel '$sessionModel'."
        }
        if ($null -ne $economyConsent) {
            $routeReport.warnings = @($routeReport.warnings | Where-Object { $_ -notlike 'economy consent*' })
        }
        foreach ($route in @($routeReport.roles)) {
            $routeKey = [string]$route.role + "`n" + [string]$route.memberName
            if ($routeByIdentity.ContainsKey($routeKey)) { throw "Model routing returned a duplicate roster identity for '$($route.role)'." }
            $routeByIdentity[$routeKey] = $route
        }
    }
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
            $persistedModel = if ($modelRouting -ne 'off' -and $row.ContainsKey('Model')) { [string]$row.Model } else { '' }
            if ($persistedModel -in @('-', [string][char]0x2014)) { $persistedModel = '' }
            $routeKey = [string]$unit.role + "`n" + [string]$selection.MemberName
            $route = if ($routeByIdentity.ContainsKey($routeKey)) { $routeByIdentity[$routeKey] } else { $null }
            $assignmentClass = if ($null -ne $route) { [string]$route.class }
            elseif ($roleClasses.ContainsKey([string]$unit.role)) { [string]$roleClasses[[string]$unit.role] }
            else { 'implementation' }
            $model = ''
            $routeRationale = ''
            $cellStatus = ''
            if ($modelRouting -ne 'off' -and $unit.role -ne 'scribe') {
                if ($null -eq $route) { throw "No model route was returned for role '$($unit.role)'." }
                $model = [string]$route.resolved
                $cellStatus = [string]$route.cellStatus
                $routeRationale = [string]$route.rationale
                if (-not $model) {
                    $candidates = @($route.candidates | ForEach-Object { $_.id }) -join ', '
                    throw "Role '$($unit.role)' has no admissible $modelRouting model. Cell status: $cellStatus. Candidates: $candidates"
                }
                if ($persistedModel -cne $model -and $routingChangeRoles.Add($routeKey)) {
                    $routingChanges.Add([ordered]@{
                            role = [string]$unit.role
                            memberName = [string]$selection.MemberName
                            from = $persistedModel
                            to = $model
                            rationale = $routeRationale
                        })
                }
            }
            $pin = [string]$agents[$agent].model
            $pricingModel = if ($model) { $model } elseif ($pin) { $pin } else { $sessionModel }
            $endpoint = [ordered]@{
                role = $unit.role; memberName = $selection.MemberName; agent = $agent
                execution = $selection.Choice; connectorSelection = $selection
                squadRoot = $root; deliverableRoot = $row['Deliverable Root']
                model = $model; persistedModel = $persistedModel; pricingModel = $pricingModel
                modelRouting = $modelRouting; modelCellStatus = $cellStatus
                modelRationale = $routeRationale; assignmentClass = $assignmentClass
                autonomyTier = $tier
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

    $routingRefresh = [ordered]@{
        required = $routingModeChanged -or $routingChanges.Count -gt 0
        recordedMode = $recordedModelRouting
        mode = $modelRouting
        expectedTeamHash = $teamHash
        changes = $routingChanges.ToArray()
        economyConsent = $economyConsent
    }

    $preflight = $null
    $decisionText = ''
    $usageSnapshot = $null
    $reservations = [Collections.Generic.List[object]]::new()
    $admittedUnits = @()
    $admission = 'not-requested'
    $statePreflight = if ($state.Contains('currentRun') -and $state.currentRun.Contains('costPreflight')) { $state.currentRun.costPreflight } else { $null }
    $activeCeiling = $null -ne $statePreflight -and ($null -ne $statePreflight.ceilingUsd -or $statePreflight.decision -ne 'not-requested')
    if (-not $inputData.Contains('cost') -and $activeCeiling) {
        throw 'An active ceiling requires the actual cost input; dispatch planning cannot bypass Cost Preflight.'
    }
    if ($inputData.Contains('cost')) {
        if ($federation) { throw 'Exact Cost Preflight must be calculated inside each selected member before federation dispatch.' }
        $cost = $inputData.cost
        if ($cost -isnot [Collections.IDictionary]) { throw 'cost must be an object.' }
        foreach ($key in @('runId', 'roundId', 'ceilingUsd')) {
            if (-not $cost.Contains($key)) { throw "Missing cost field: $key" }
        }
        foreach ($key in $cost.Keys) {
            if ($key -notin @('runId', 'roundId', 'ceilingUsd', 'sessionLog', 'usageOutputPath', 'baselineNanoAiu', 'pendingUsd', 'reserveMultiplier', 'timestamp')) {
                throw "Unsupported cost field: $key"
            }
        }
        $runId = [string]$cost.runId
        $roundId = [string]$cost.roundId
        if ($runId -cnotmatch '^[A-Za-z0-9._:-]+$' -or $roundId -cnotmatch '^[A-Za-z0-9._:-]+$') {
            throw 'cost runId and roundId must match [A-Za-z0-9._:-]+.'
        }
        $ceilingUsd = [decimal]0
        try { $ceilingUsd = [decimal]$cost.ceilingUsd } catch { throw 'cost.ceilingUsd must be numeric.' }
        if ($ceilingUsd -le 0) { throw 'cost.ceilingUsd must be positive.' }
        $baselineNanoAiu = $null
        if ($cost.Contains('baselineNanoAiu')) {
            $baselineNanoAiu = [decimal]$cost.baselineNanoAiu
        }
        else {
            $decisionsPath = Join-Path $root 'decisions.md'
            if (Test-Path -LiteralPath $decisionsPath -PathType Leaf) {
                $priorDecisions = [IO.File]::ReadAllText($decisionsPath)
                $sections = [regex]::Matches($priorDecisions, '(?ms)^## Cost Preflight \S+ (?<run>[^\s]+) [^\r\n]+\r?\n(?<body>.*?)(?=^## |\z)')
                foreach ($section in $sections) {
                    if ($section.Groups['run'].Value -cne $runId) { continue }
                    $match = [regex]::Match($section.Groups['body'].Value, '(?m)^\* Usage Baseline Nano-AIU:\s*(?<value>\d+(?:\.\d+)?)\s*$')
                    if ($match.Success) { $baselineNanoAiu = [decimal]$match.Groups['value'].Value }
                }
            }
        }
        if ($null -eq $baselineNanoAiu) {
            throw 'The first Cost Preflight round for a run requires cost.baselineNanoAiu; later rounds recover it from decisions.md.'
        }
        $pendingUsd = if ($cost.Contains('pendingUsd')) { [decimal]$cost.pendingUsd } else { [decimal]0 }
        $reserveMultiplier = if ($cost.Contains('reserveMultiplier')) { [decimal]$cost.reserveMultiplier } else { [decimal]3 }
        if ($baselineNanoAiu -lt 0 -or $pendingUsd -lt 0) { throw 'cost baselineNanoAiu and pendingUsd must be nonnegative.' }
        if ($reserveMultiplier -ne [decimal]3) { throw 'cost.reserveMultiplier must be 3.0.' }
        if ($cost.Contains('sessionLog') -and $cost.Contains('usageOutputPath')) { throw 'Supply only one of cost.sessionLog or cost.usageOutputPath.' }

        $meteringProblems = [Collections.Generic.List[string]]::new()
        try {
            if ($cost.Contains('usageOutputPath')) {
                $usageSnapshot = Get-SquadUsageSnapshot -UsagePath ([string]$cost.usageOutputPath) -BaselineNanoAiu $baselineNanoAiu
            }
            else {
                $requestedLog = if ($cost.Contains('sessionLog')) { [string]$cost.sessionLog } else { 'auto' }
                $eventsPath = Resolve-SquadSessionLogPath -SessionLog $requestedLog -RepoRoot $RepoRoot
                if (-not $eventsPath) { throw 'No Copilot session log matches this repository.' }
                $usageSnapshot = Get-SquadUsageSnapshot -EventsPath $eventsPath -BaselineNanoAiu $baselineNanoAiu
            }
        }
        catch {
            $meteringProblems.Add($_.Exception.Message)
        }
        if ($usageSnapshot -and $usageSnapshot.status -ne 'complete') {
            foreach ($problem in @($usageSnapshot.problems)) { $meteringProblems.Add($problem) }
        }

        $nextWaveIds = @($waves[0].units)
        $reservationProblems = [Collections.Generic.List[string]]::new()
        $ratesPath = Join-Path $root 'consumption-rates.md'
        foreach ($node in @($nodes | Where-Object { $_.id -cin $nextWaveIds })) {
            try {
                $reservation = Get-SquadDispatchReservation -RatesPath $ratesPath -Model ([string]$node.endpoint.pricingModel) -AssignmentClass ([string]$node.endpoint.assignmentClass)
                $reservations.Add([ordered]@{
                        slot = $node.id
                        role = $node.endpoint.role
                        agent = $node.endpoint.agent
                        model = $reservation.model
                        dispatchClass = $reservation.dispatchClass
                        projectedCostUsd = [math]::Round([double]$reservation.projectedCostUsd, 6)
                    })
            }
            catch {
                $reservationProblems.Add("$($node.id): $($_.Exception.Message)")
            }
        }
        try {
            $coordinatorReservation = Get-SquadDispatchReservation -RatesPath $ratesPath -Model $sessionModel -AssignmentClass coordinator
            $reservations.Add([ordered]@{
                    slot = 'coordinator'
                    role = 'coordinator'
                    agent = 'Squad Coordinator'
                    model = $coordinatorReservation.model
                    dispatchClass = $coordinatorReservation.dispatchClass
                    projectedCostUsd = [math]::Round([double]$coordinatorReservation.projectedCostUsd, 6)
                })
        }
        catch {
            $reservationProblems.Add("coordinator: $($_.Exception.Message)")
        }

        $actualUsedUsd = if ($usageSnapshot) { [decimal]$usageSnapshot.usd } else { [decimal]0 }
        $evaluatedSpendUsd = $actualUsedUsd + $pendingUsd
        $remainingUsd = if ($ceilingUsd -gt $evaluatedSpendUsd) { $ceilingUsd - $evaluatedSpendUsd } else { [decimal]0 }
        $projectedCostUsd = [decimal]0
        foreach ($reservation in $reservations) { $projectedCostUsd += [decimal]$reservation.projectedCostUsd }
        $admissionCostUsd = $projectedCostUsd * $reserveMultiplier
        $confidence = if ($meteringProblems.Count -eq 0 -and $reservationProblems.Count -eq 0) { 'medium' } else { 'low' }
        $basis = 'host-exact+estimated-reservation'
        $reason = ''
        if ($meteringProblems.Count -gt 0) {
            $decision = 'cannot-confirm'
            $reason = 'Exact host metering is incomplete: ' + ($meteringProblems -join ' ')
        }
        elseif ($reservationProblems.Count -gt 0) {
            $decision = 'cannot-confirm'
            $reason = 'The next-wave reservation is incomplete: ' + ($reservationProblems -join ' ')
        }
        elseif ($evaluatedSpendUsd -ge $ceilingUsd) {
            $decision = 'over-ceiling'
            $reason = 'Exact consumed usage plus in-flight reservations has reached the ceiling.'
        }
        elseif ($admissionCostUsd -gt $remainingUsd) {
            $decision = 'over-ceiling'
            $reason = 'The conservative reservation for the actual next wave exceeds the exact remaining ceiling.'
        }
        else {
            $decision = 'within-ceiling'
            $reason = 'Exact consumed usage and the reserved actual next wave fit within the ceiling.'
            $admittedUnits = $nextWaveIds
        }
        $admission = $decision
        $round = {
            param([decimal]$value)
            [math]::Round([double]$value, 4)
        }
        $preflight = [ordered]@{
            runId = $runId
            roundId = $roundId
            ceilingUsd = & $round $ceilingUsd
            evaluatedSpendUsd = & $round $evaluatedSpendUsd
            remainingUsd = & $round $remainingUsd
            plannedDispatches = $nextWaveIds.Count
            projectedCostUsd = & $round $projectedCostUsd
            reserveMultiplier = [double]$reserveMultiplier
            admissionCostUsd = & $round $admissionCostUsd
            confidence = $confidence
            basis = $basis
            decision = $decision
            reason = $reason
        }
        $timestamp = if ($cost.Contains('timestamp')) {
            [DateTimeOffset]::Parse([string]$cost.timestamp, [Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
        }
        else { [DateTimeOffset]::UtcNow }
        $permitted = if ($admittedUnits.Count) { ($admittedUnits | ForEach-Object { "``$_``" }) -join ', ' } else { 'none' }
        $records = if ($usageSnapshot) { $usageSnapshot.records } else { 0 }
        $meteringStatus = if ($usageSnapshot) { $usageSnapshot.status } else { 'unavailable' }
        $decisionText = @(
            "## Cost Preflight $($timestamp.ToString('o')) $runId $roundId"
            ''
            "* Ceiling USD: $((& $round $ceilingUsd).ToString('F4', [Globalization.CultureInfo]::InvariantCulture))"
            "* Exact Used USD: $((& $round $actualUsedUsd).ToString('F4', [Globalization.CultureInfo]::InvariantCulture))"
            "* Usage Baseline Nano-AIU: $($baselineNanoAiu.ToString([Globalization.CultureInfo]::InvariantCulture))"
            "* Observed Total Nano-AIU: $(if ($usageSnapshot) { $usageSnapshot.totalNanoAiu.ToString([Globalization.CultureInfo]::InvariantCulture) } else { 'unavailable' })"
            "* Pending Reservation USD: $((& $round $pendingUsd).ToString('F4', [Globalization.CultureInfo]::InvariantCulture))"
            "* Remaining USD: $((& $round $remainingUsd).ToString('F4', [Globalization.CultureInfo]::InvariantCulture))"
            "* Planned Dispatches: $($nextWaveIds.Count)"
            "* Projected Cost USD: $((& $round $projectedCostUsd).ToString('F4', [Globalization.CultureInfo]::InvariantCulture))"
            "* Reserve Multiplier: $($reserveMultiplier.ToString('F1', [Globalization.CultureInfo]::InvariantCulture))"
            "* Admission Cost USD: $((& $round $admissionCostUsd).ToString('F4', [Globalization.CultureInfo]::InvariantCulture))"
            "* Metering: $meteringStatus ($records complete unique record(s))"
            "* Permitted Next Dispatch Set: $permitted"
            "* Decision: $decision"
            "* Reason: $reason"
        ) -join "`n"
    }

    [ordered]@{
        status = 'ok'
        kind = $(if ($federation) { 'federation' } else { 'squad' })
        gates = 'not-evaluated'
        admission = $admission
        admissionPersisted = $false
        admittedUnits = @($admittedUnits)
        waves = $waves.ToArray()
        units = $nodes.ToArray()
        recordedModelRouting = $recordedModelRouting
        modelRouting = $modelRouting
        modelPolicy = $(if ($routeReport) { $routeReport.scoringPolicy } else { 'off' })
        modelSnapshot = $(if ($routeReport) { $routeReport.snapshotIdentity } else { 'not-evaluated' })
        modelAvailability = $(if ($routeReport) { $routeReport.availability } else { 'not-evaluated' })
        modelWarnings = @(if ($routeReport) { $routeReport.warnings })
        routingRefresh = $routingRefresh
        costPreflight = $preflight
        costDecisionText = $decisionText
        usage = $usageSnapshot
        reservations = $reservations.ToArray()
        stateWritten = $false
    } | ConvertTo-Json -Depth 30 -Compress
}
catch {
    [Console]::Error.WriteLine("New-SquadDispatchPlan: $($_.Exception.Message)")
    exit 1
}
