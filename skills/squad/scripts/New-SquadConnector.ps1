#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Safely scaffolds a contract 1.1 Squad Connector.
.DESCRIPTION
    Renders a closed-schema manifest, mailbox guidance, example envelopes, a
    removable file-drop runner, and an end-to-end runbook. A rerun is a no-op
    only for byte-identical files and refuses every customized-file conflict
    before writing.
.EXAMPLE
    ./New-SquadConnector.ps1 -WorkspaceRoot . -ConnectorId org-research `
        -EndpointKind agent -Capabilities 'Repository research' `
        -Roles researcher -Contact integrations@example.invalid
.EXAMPLE
    ./New-SquadConnector.ps1 -WorkspaceRoot . -EditableTemplate
#>

[CmdletBinding(DefaultParameterSetName = 'Configured')]
param(
    [Parameter(Mandatory)]
    [string]$WorkspaceRoot,

    [Parameter(Mandatory, ParameterSetName = 'Configured')]
    [string]$ConnectorId,

    [Parameter(ParameterSetName = 'Configured')]
    [ValidateSet('agent', 'orchestrator')]
    [string]$EndpointKind = 'agent',

    [Parameter(Mandatory, ParameterSetName = 'Configured')]
    [string[]]$Capabilities,

    [Parameter(Mandatory, ParameterSetName = 'Configured')]
    [string[]]$Roles,

    [Parameter(Mandatory, ParameterSetName = 'Configured')]
    [string]$Contact,

    [Parameter(ParameterSetName = 'Configured')]
    [string]$Version = '0.1.0',

    [Parameter(ParameterSetName = 'Configured')]
    [ValidateRange(1, 2147483647)]
    [int]$DeadlineMinutes = 60,

    [Parameter(ParameterSetName = 'Configured')]
    [ValidateRange(0, 2147483647)]
    [int]$RetryCap = 2,

    [Parameter(Mandatory, ParameterSetName = 'Template')]
    [switch]$EditableTemplate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'SquadBuilder.Common.ps1')
. (Join-Path $PSScriptRoot 'Resolve-SquadConnectorDispatch.ps1')

$arguments = @{
    EditableTemplate = $EditableTemplate
}
if (-not $EditableTemplate) {
    $arguments += @{
        ConnectorId = $ConnectorId
        EndpointKind = $EndpointKind
        Capabilities = $Capabilities
        Roles = $Roles
        Contact = $Contact
        Version = $Version
        DeadlineMinutes = $DeadlineMinutes
        RetryCap = $RetryCap
    }
}
$plan = @(Get-SquadConnectorScaffoldPlan @arguments)

if (-not $EditableTemplate) {
    $manifestEntry = $plan | Where-Object Path -eq "connectors/$ConnectorId.json"
    $manifest = $manifestEntry.Content | ConvertFrom-Json -Depth 16
    $shape = Test-SquadConnectorManifestShape -Manifest $manifest
    $issues = @($shape.Issues) + @(Test-SquadBuilderManifestValues -Manifest $manifest -Raw $manifestEntry.Content)
    if ($issues.Count -gt 0) {
        throw "Generated manifest failed validation: $($issues -join ', ')."
    }
}

$files = @(Write-SquadBuilderPlan -WorkspaceRoot $WorkspaceRoot -Plan $plan)
[ordered]@{
    status       = 'ok'
    mode         = if ($EditableTemplate) { 'editable-template' } else { 'configured' }
    connectorId  = if ($EditableTemplate) { 'REPLACE_CONNECTOR_ID' } else { $ConnectorId }
    files        = $files
    placeholders = if ($EditableTemplate) {
        @('REPLACE_CONNECTOR_ID', 'REPLACE_CAPABILITY', 'REPLACE_ROLE', 'REPLACE_CONTACT')
    }
    else {
        @()
    }
} | ConvertTo-Json -Depth 8