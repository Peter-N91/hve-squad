#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Creates or adapts an external agent or orchestrator for Squad Connector.
.DESCRIPTION
    Create mode renders consumer-owned agent/worker charters, a skill, connector
    artifacts, and runbooks. Adapt mode leaves the named implementation
    untouched and renders only integration artifacts and mapping guidance.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$WorkspaceRoot,

    [Parameter(Mandatory)]
    [ValidateSet('Create', 'Adapt')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [string]$ConnectorId,

    [Parameter(Mandatory)]
    [ValidateSet('agent', 'orchestrator')]
    [string]$EndpointKind,

    [Parameter(Mandatory)]
    [string[]]$Capabilities,

    [Parameter(Mandatory)]
    [string[]]$Roles,

    [Parameter(Mandatory)]
    [string[]]$Responsibilities,

    [string[]]$SkillRequirements = @(),

    [Parameter(Mandatory)]
    [string]$Contact,

    [string]$EndpointName,

    [string]$ExistingPath,

    [string]$Version = '0.1.0',

    [ValidateRange(1, 2147483647)]
    [int]$DeadlineMinutes = 60,

    [ValidateRange(0, 2147483647)]
    [int]$RetryCap = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'SquadBuilder.Common.ps1')
. (Join-Path $PSScriptRoot 'Resolve-SquadConnectorDispatch.ps1')

$plan = @(Get-SquadExternalEndpointScaffoldPlan `
        -Mode $Mode `
        -ConnectorId $ConnectorId `
        -EndpointKind $EndpointKind `
        -Capabilities $Capabilities `
        -Roles $Roles `
        -Responsibilities $Responsibilities `
        -SkillRequirements $SkillRequirements `
        -Contact $Contact `
        -EndpointName $EndpointName `
        -ExistingPath $ExistingPath `
        -Version $Version `
        -DeadlineMinutes $DeadlineMinutes `
        -RetryCap $RetryCap `
        -WorkspaceRoot $WorkspaceRoot)

$manifestEntry = $plan | Where-Object Path -eq "connectors/$ConnectorId.json"
$manifest = $manifestEntry.Content | ConvertFrom-Json -Depth 16
$shape = Test-SquadConnectorManifestShape -Manifest $manifest
$issues = @($shape.Issues) + @(Test-SquadBuilderManifestValues -Manifest $manifest -Raw $manifestEntry.Content)
if ($issues.Count -gt 0) {
    throw "Generated manifest failed validation: $($issues -join ', ')."
}

$files = @(Write-SquadBuilderPlan -WorkspaceRoot $WorkspaceRoot -Plan $plan)
[ordered]@{
    status       = 'ok'
    mode         = $Mode.ToLowerInvariant()
    endpointKind = $EndpointKind
    connectorId  = $ConnectorId
    files        = $files
    placeholders = if ($Mode -eq 'Create' -and $SkillRequirements.Count -eq 0) {
        @('TODO: describe this requirement before production use.')
    }
    else {
        @()
    }
} | ConvertTo-Json -Depth 8