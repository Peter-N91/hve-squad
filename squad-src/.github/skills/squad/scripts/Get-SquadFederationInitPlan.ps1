#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Prepares one confirmed, read-only payload for federation initialization.
.DESCRIPTION
    AI cost: none. The coordinator supplies confirmed federation choices: shared
    naming and notification policy plus one or more named sub-squads, each with its
    profile/pack choices and explicit meta-routes. This helper validates every member
    through the same `New-SquadInitPayload` path used by single-squad Init and writes
    one transport JSON outside squad state.

    No squad state is written. On a fresh repository the payload seals the absent or
    empty root. On an existing federation it seals the root files, member state totals,
    and registered member-directory set so `Initialize-SquadFederation.ps1` can add
    the confirmed members with the same compare-and-swap protection.
.PARAMETER ChoicesPath
    Confirmed JSON choices.
.PARAMETER PayloadPath
    New transport JSON outside `.copilot-tracking/squad/`.
.EXAMPLE
    ./Get-SquadFederationInitPlan.ps1 -RepoRoot . -ChoicesPath choices.json `
      -PayloadPath $env:TEMP/federation-init.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ChoicesPath,
    [Parameter(Mandatory)][string]$PayloadPath,
    [string]$RepoRoot = (Get-Location).ProviderPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force

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

function Assert-Line {
    param($Value, [switch]$AllowEmpty)
    if ($Value -isnot [string] -or $Value -match '[\r\n|\x00-\x1f]' -or
        (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value))) {
        throw 'Expected a single-line value without table delimiters or control characters.'
    }
}

function Get-RootBaseline {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [ordered]@{ kind = 'absent'; directories = @() } }
    $root = Get-Item -LiteralPath $Path -Force
    if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Fresh federation root must be absent or an unlinked empty directory tree.'
    }
    $directories = [Collections.Generic.List[string]]::new()
    foreach ($item in Get-ChildItem -LiteralPath $Path -Recurse -Force | Sort-Object FullName) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked empty-root path refused: $($item.FullName)" }
        if (-not $item.PSIsContainer) { throw 'Fresh federation Init refuses an existing file or partial squad tree.' }
        $directories.Add(([IO.Path]::GetRelativePath($Path, $item.FullName) -replace '\\', '/'))
    }
    [ordered]@{ kind = 'empty'; directories = $directories.ToArray() }
}

try {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $choices = Get-Content -LiteralPath $ChoicesPath -Raw | ConvertFrom-Json -AsHashtable
    Assert-FieldSet $choices @('confirmed', 'runId', 'naming', 'notify', 'subSquads') @('sessionModel', 'modelOverrides', 'orchestration')
    if ($choices.confirmed -isnot [bool] -or -not $choices.confirmed) { throw 'Federation Init requires explicit confirmation.' }
    Assert-Line $choices.runId
    if ($choices.naming -notin @('skip', 'aliases', 'custom', 'mixed')) { throw 'Invalid federation naming policy.' }
    if ($choices.notify -isnot [Collections.IDictionary]) { throw 'Federation Init requires the confirmed notify object.' }
    Assert-FieldSet $choices.notify @('approvalChannel', 'enabled') @('email', 'github')
    if ($choices.notify.enabled -isnot [bool] -or $choices.notify.approvalChannel -notin @('in-chat', 'github-issue', 'webhook')) {
        throw 'Invalid federation notification configuration.'
    }
    if ($choices.notify.Contains('email')) { Assert-Line $choices.notify.email -AllowEmpty }
    if ($choices.notify.Contains('github')) {
        Assert-FieldSet $choices.notify.github @('handle', 'repo')
        foreach ($value in $choices.notify.github.Values) { Assert-Line $value -AllowEmpty }
    }
    if ($choices.notify.enabled -and $choices.notify.approvalChannel -eq 'github-issue' -and
        (-not $choices.notify.Contains('github') -or -not $choices.notify.github.handle -or -not $choices.notify.github.repo)) {
        throw 'Enabled github-issue notifications require handle and repo.'
    }
    if ($choices.subSquads -isnot [array] -or $choices.subSquads.Count -lt 1 -or $choices.subSquads.Count -gt 16) {
        throw 'Federation Init requires between 1 and 16 confirmed sub-squads.'
    }
    if ($choices.Contains('sessionModel')) { Assert-Line $choices.sessionModel -AllowEmpty }
    if ($choices.Contains('modelOverrides') -and $choices.modelOverrides -isnot [Collections.IDictionary]) {
        throw 'modelOverrides must be an object.'
    }
    if ($choices.Contains('modelOverrides')) {
        foreach ($value in $choices.modelOverrides.Values) { Assert-Line $value }
    }

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $routeSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $root = [IO.Path]::GetFullPath((Join-Path $RepoRoot '.copilot-tracking' 'squad'))
    $hasTeam = Test-Path -LiteralPath (Join-Path $root 'team.md') -PathType Leaf
    $hasFederation = Test-Path -LiteralPath (Join-Path $root 'federation.md') -PathType Leaf
    if ($hasTeam -and -not $hasFederation) { throw 'A plain squad already exists; use promotion.' }

    $operation = if ($hasFederation) { 'expand' } else { 'fresh' }
    $existingState = $null
    if ($operation -eq 'expand') {
        foreach ($required in @('meta-routing.md', 'decisions.md', 'state.json')) {
            if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) {
                throw "Existing federation is missing required root file: $required"
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $root 'history') -PathType Container)) {
            throw 'Existing federation is missing its root history directory.'
        }
        $snapshot = Get-SquadFederationSnapshot -SquadRoot $root -RepoRoot $RepoRoot
        $registered = @($snapshot.members.Keys)
        $memberRoot = Join-Path $root 'members'
        $memberDirectories = @(
            if (Test-Path -LiteralPath $memberRoot -PathType Container) {
                Get-ChildItem -LiteralPath $memberRoot -Directory -Force | Sort-Object Name | ForEach-Object {
                    if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                        throw "Linked federation member directory refused: $($_.FullName)"
                    }
                    $_.Name
                }
            }
        )
        if ($memberDirectories.Count -ne $registered.Count -or
            @($memberDirectories | Where-Object { $_ -notin $registered }).Count) {
            throw 'Existing federation registry and member directories do not match.'
        }
        foreach ($name in $registered) { $null = $seen.Add($name) }

        $routingTables = @(Read-SquadTables (Join-Path $root 'meta-routing.md') |
                Where-Object { 'Pattern / Domain' -in $_.Header -and 'Sub-squad' -in $_.Header -and 'Parallel-Eligible' -in $_.Header })
        if ($routingTables.Count -ne 1) { throw 'Existing federation has no unique meta-routing table.' }
        foreach ($route in $routingTables[0].Rows) {
            Assert-Line $route['Pattern / Domain']
            if (-not $snapshot.members.Contains($route['Sub-squad']) -or
                $route['Parallel-Eligible'] -notin @('yes', 'no') -or
                -not $routeSeen.Add($route['Pattern / Domain'])) {
                throw 'Existing federation contains an invalid or duplicate meta-route.'
            }
        }
        $existingState = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json -AsHashtable
        if ($existingState.schemaVersion -notin @('1.2', '1.3') -or
            $existingState.subSquads -isnot [array] -or
            $existingState.subSquads.Count -ne $registered.Count -or
            @($existingState.subSquads | Where-Object { $_ -notin $registered }).Count) {
            throw 'Existing federation state does not match its registry.'
        }
        $baseline = [ordered]@{
            kind = 'federation'
            snapshot = $snapshot
            memberDirectories = $memberDirectories
        }
    }
    else {
        $baseline = Get-RootBaseline $root
    }

    $effectiveSessionModel = if ($choices.Contains('sessionModel')) {
        $choices.sessionModel
    }
    elseif ($existingState) {
        [string]$existingState.currentRun.sessionModel
    }
    else {
        ''
    }
    $effectiveModelOverrides = if ($choices.Contains('modelOverrides')) {
        $choices.modelOverrides
    }
    elseif ($existingState) {
        $existingState.currentRun.modelOverrides
    }
    else {
        @{}
    }
    Assert-Line $effectiveSessionModel -AllowEmpty
    if ($effectiveModelOverrides -isnot [Collections.IDictionary]) { throw 'Effective modelOverrides must be an object.' }
    foreach ($value in $effectiveModelOverrides.Values) { Assert-Line $value }
    $members = @(
        foreach ($member in $choices.subSquads) {
            Assert-FieldSet $member @('name', 'profile', 'description', 'routes') @(
                'owner', 'packs', 'roles', 'excludeRoles', 'names', 'naming', 'notify',
                'modelRouting', 'models', 'mode', 'sessionModel', 'modelOverrides', 'usage'
            )
            Assert-Line $member.name
            Assert-Line $member.profile
            Assert-Line $member.description
            if ($member.name -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or -not $seen.Add($member.name)) {
                throw "Invalid or duplicate federation member name: $($member.name)"
            }
            if ($operation -eq 'expand' -and
                (Test-Path -LiteralPath (Join-Path $root 'history' "$($member.name).md"))) {
                throw "Federation history for '$($member.name)' already exists."
            }
            $owner = if ($member.Contains('owner')) { $member.owner } else { '' }
            Assert-Line $owner -AllowEmpty
            if ($member.routes -isnot [array] -or -not $member.routes.Count) {
                throw "Federation member '$($member.name)' requires at least one confirmed meta-route."
            }
            $routes = @(
                foreach ($route in $member.routes) {
                    Assert-FieldSet $route @('pattern', 'parallelEligible')
                    Assert-Line $route.pattern
                    if ($route.parallelEligible -isnot [bool]) { throw 'parallelEligible must be boolean.' }
                    if (-not $routeSeen.Add($route.pattern)) { throw "Duplicate federation meta-route: $($route.pattern)" }
                    [ordered]@{ pattern = $route.pattern; parallelEligible = $route.parallelEligible }
                }
            )
            $initChoices = [ordered]@{
                confirmed = $true
                squadRoot = ".copilot-tracking/squad/members/$($member.name)"
                runId = $choices.runId
                profile = $member.profile
                naming = $(if ($member.Contains('naming')) { $member.naming } else { $choices.naming })
                notify = $(if ($member.Contains('notify')) { $member.notify } else { $choices.notify })
            }
            foreach ($field in @('packs', 'roles', 'excludeRoles', 'names', 'modelRouting', 'models', 'mode', 'usage')) {
                if ($member.Contains($field)) { $initChoices[$field] = $member[$field] }
            }
            foreach ($field in @('sessionModel', 'modelOverrides')) {
                if ($member.Contains($field)) { $initChoices[$field] = $member[$field] }
                elseif ($field -eq 'sessionModel' -and $effectiveSessionModel) { $initChoices[$field] = $effectiveSessionModel }
                elseif ($field -eq 'modelOverrides' -and $effectiveModelOverrides.Count) { $initChoices[$field] = $effectiveModelOverrides }
            }
            $initPayload = New-SquadInitPayload -Choices $initChoices -RepoRoot $RepoRoot
            [ordered]@{
                name = $member.name
                profile = $initPayload.provenance
                owner = $owner
                description = $member.description
                routes = $routes
                initPayload = $initPayload
            }
        }
    )
    $payload = [ordered]@{
        schemaVersion = 2
        operation = $operation
        runId = $choices.runId
        rootBaseline = $baseline
        notify = $choices.notify
        sessionModel = $effectiveSessionModel
        modelOverrides = $effectiveModelOverrides
        members = $members
        generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    }
    if ($choices.Contains('orchestration')) { $payload.orchestration = $choices.orchestration }
    $destination = Write-SquadTransportJson -Path ([IO.Path]::GetFullPath($PayloadPath)) -SquadRoot $root -Value $payload
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    [ordered]@{
        status = 'prepared'
        operation = $operation
        payloadPath = $destination
        payloadSha256 = $hash
        members = @($members | ForEach-Object {
                [ordered]@{
                    name = $_.name
                    profile = $_.profile
                    roles = @($_.initPayload.roster | ForEach-Object Role)
                    primaries = @($_.initPayload.roster | ForEach-Object { $_['Agent Name (Primary)'] })
                }
            })
        stateWritten = $false
    } | ConvertTo-Json -Depth 10 -Compress
    exit 0
}
catch {
    [Console]::Error.WriteLine("Get-SquadFederationInitPlan: $($_.Exception.Message)")
    exit 1
}
