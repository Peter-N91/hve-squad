#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Seals a read-only, hash-bound plan for promoting one plain squad into a federation.
.DESCRIPTION
    AI cost: none. The helper inventories the complete single-squad state tree and
    every immediate directory under `.copilot-tracking/` except `squad/`. It records
    compact tree digests, identifies directories required by roster roots or
    append-only history, and writes a new JSON plan outside squad state. It writes no
    squad or federation state.

    The coordinator presents the returned candidate list and obtains confirmation.
    `Promote-SquadFederation.ps1` later requires the exact plan SHA-256 plus an explicit
    relocate/keep partition that covers every candidate.
.PARAMETER Name
    Unique lower-kebab-case name for the adopted member.
.PARAMETER PlanPath
    New JSON transport path outside `.copilot-tracking/squad/`.
.PARAMETER Owner
    Optional federation registry owner label.
.PARAMETER Description
    Optional one-line registry description. Defaults from the inferred profile.
.PARAMETER RoutePattern
    Optional one-line meta-routing patterns. A sole-member fallback is generated when
    omitted.
.PARAMETER WatchSource
    Optional Watch Mode provenance. Supply all four Watch fields or none.
.EXAMPLE
    ./Get-SquadPromotionPlan.ps1 -RepoRoot . -Name product -PlanPath $env:TEMP/promotion.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$PlanPath,
    [string]$RepoRoot = (Get-Location).ProviderPath,
    [string]$SquadRoot = '.copilot-tracking/squad',
    [AllowEmptyString()][string]$Owner = '',
    [AllowEmptyString()][string]$Description = '',
    [string[]]$RoutePattern = @(),
    [string]$WatchSource,
    [string]$WatchRef,
    [string]$WatchEventId,
    [string]$WatchActor
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SquadPromotion.psm1') -Force

try {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    if ($Name -cnotmatch '^[a-z0-9][a-z0-9-]*$') { throw 'Promotion member name must be lower-kebab-case.' }
    foreach ($value in @($Name, $Owner, $Description) + @($RoutePattern)) {
        Assert-SquadPromotionText $value -AllowEmpty
    }
    $watchValues = @($WatchSource, $WatchRef, $WatchEventId, $WatchActor)
    $watchCount = @($watchValues | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    if ($watchCount -notin @(0, 4)) { throw 'Supply all Watch Mode provenance fields or none.' }
    foreach ($value in $watchValues) {
        if ($watchCount) { Assert-SquadPromotionText $value }
    }

    $root = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $SquadRoot
    $relativeRoot = [IO.Path]::GetRelativePath($RepoRoot, $root) -replace '\\', '/'
    if ($relativeRoot -cne '.copilot-tracking/squad') { throw 'Promotion applies only to the top-level plain squad root.' }
    foreach ($required in @('team.md', 'routing.md', 'decisions.md', 'notifications.md', 'state.json', 'consumption.md', 'consumption-rates.md', 'history')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $required))) { throw "Plain squad is missing required state: $required" }
    }
    if (Test-Path -LiteralPath (Join-Path $root 'federation.md')) { throw 'This repository is already a federation.' }
    if (Test-Path -LiteralPath (Join-Path $root 'members' $Name)) { throw "Federation member '$Name' already exists." }
    if (Test-Path -LiteralPath (Join-Path $root 'members')) { throw 'A plain squad cannot be promoted while a top-level members directory already exists.' }

    $source = Get-SquadPromotionTreeSnapshot $root
    $roster = @(Get-SquadRoster $root)
    $inferredProfile = Get-SquadPromotionProfile -DecisionsPath (Join-Path $root 'decisions.md') -Roster $roster -InitData (Get-SquadInitData -RepoRoot $RepoRoot)
    Assert-SquadPromotionText $inferredProfile
    if (-not $Description) { $Description = "Promoted $inferredProfile squad" }
    if (-not $RoutePattern.Count) { $RoutePattern = @("all requests while $Name is the sole registered sub-squad") }
    foreach ($value in @($Description) + @($RoutePattern)) { Assert-SquadPromotionText $value }

    $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json -AsHashtable
    if ($state -isnot [Collections.IDictionary] -or $state.turn -isnot [ValueType] -or $state.turn -is [bool] -or
        $state.currentRun -isnot [Collections.IDictionary] -or $state.notify -isnot [Collections.IDictionary]) {
        throw 'Plain squad state.json is not promotion-compatible.'
    }
    $requiredDirectories = Get-SquadPromotionRequiredDirectoryMap -TeamPath (Join-Path $root 'team.md') -HistoryRoot (Join-Path $root 'history')
    $trackingRoot = Split-Path -Parent $root
    $candidateNames = [string[]]@(Get-ChildItem -LiteralPath $trackingRoot -Directory -Force | Where-Object Name -cne 'squad' | ForEach-Object Name)
    [Array]::Sort($candidateNames, [StringComparer]::Ordinal)
    $candidates = @(
        foreach ($candidateName in $candidateNames) {
            $directory = Get-Item -LiteralPath (Join-Path $trackingRoot $candidateName) -Force
            if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Linked promotion candidate refused: $($directory.FullName)"
            }
            if ($directory.Name -in @('.', '..') -or $directory.Name -match '[/\\|\r\n\t\x00]') {
                throw "Unsafe promotion candidate name: $($directory.Name)"
            }
            if ($directory.Name -like '.squad-promotion-*') {
                throw "Stale promotion transaction directory requires cleanup before planning: $($directory.Name)"
            }
            $snapshot = Get-SquadPromotionTreeSnapshot $directory.FullName
            [ordered]@{
                name = $directory.Name
                path = ".copilot-tracking/$($directory.Name)"
                digest = $snapshot.digest
                files = $snapshot.files
                directories = $snapshot.directories
                bytes = $snapshot.bytes
                requiredToRelocate = $requiredDirectories.ContainsKey($directory.Name)
                reasons = @($(if ($requiredDirectories.ContainsKey($directory.Name)) { $requiredDirectories[$directory.Name].ToArray() }))
            }
        }
    )
    Assert-SquadPromotionSnapshot -Expected $source -Actual (Get-SquadPromotionTreeSnapshot $root) -Label 'plain squad'

    $plan = [ordered]@{
        schemaVersion = 1
        squadRoot = $relativeRoot
        name = $Name
        profile = $inferredProfile
        owner = $Owner
        description = $Description
        routePatterns = @($RoutePattern)
        source = $source
        candidates = $candidates
        member = [ordered]@{
            turn = [int]$state.turn
            sessionModel = [string]$state.currentRun.sessionModel
            notify = $state.notify
            memberNames = @($roster | Where-Object { $_['Member Name'] } | ForEach-Object { $_['Member Name'] })
        }
        watch = $(if ($watchCount) {
                [ordered]@{ source = $WatchSource; ref = $WatchRef; eventId = $WatchEventId; actor = $WatchActor }
            }
            else { $null })
        generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    }
    $destination = Write-SquadTransportJson -Path ([IO.Path]::GetFullPath($PlanPath)) -SquadRoot $root -Value $plan
    $sha = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    [ordered]@{
        status = 'planned'
        planPath = $destination
        planSha256 = $sha
        name = $Name
        profile = $inferredProfile
        memberNames = $plan.member.memberNames
        candidates = @($candidates | ForEach-Object {
                [ordered]@{
                    name = $_.name
                    files = $_.files
                    bytes = $_.bytes
                    requiredToRelocate = $_.requiredToRelocate
                    reasons = $_.reasons
                }
            })
        notify = $plan.member.notify
        confirmationRequired = -not [bool]$watchCount
        stateWritten = $false
    } | ConvertTo-Json -Depth 8 -Compress
    exit 0
}
catch {
    [Console]::Error.WriteLine("Get-SquadPromotionPlan: $($_.Exception.Message)")
    exit 1
}
