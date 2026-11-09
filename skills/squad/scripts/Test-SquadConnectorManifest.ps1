#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Validates a generated or consumer-authored Squad Connector manifest.
.DESCRIPTION
    Reuses the shipped connector contract validator, then applies builder
    invariants for lower-kebab-case ids, matching mailbox paths, non-empty
    capabilities/roles, and unresolved editable-template placeholders.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'SquadBuilder.Common.ps1')
. (Join-Path $PSScriptRoot 'Resolve-SquadConnectorDispatch.ps1')

$issues = [Collections.Generic.List[string]]::new()
$raw = ''
$manifest = $null
try {
    $resolved = (Resolve-Path -LiteralPath $ManifestPath).Path
    $raw = Get-Content -LiteralPath $resolved -Raw
    $manifest = $raw | ConvertFrom-Json -Depth 16
}
catch {
    $issues.Add("invalid-json-or-path:$($_.Exception.Message)")
}

if ($null -ne $manifest) {
    $shape = Test-SquadConnectorManifestShape -Manifest $manifest
    foreach ($issue in @($shape.Issues)) { $issues.Add($issue) }
    if ($manifest.PSObject.Properties.Name -contains 'connectorId' -and
        $manifest.PSObject.Properties.Name -contains 'dropPath' -and
        $manifest.PSObject.Properties.Name -contains 'capabilities' -and
        $manifest.PSObject.Properties.Name -contains 'roles') {
        foreach ($issue in @(Test-SquadBuilderManifestValues -Manifest $manifest -Raw $raw)) {
            $issues.Add($issue)
        }
    }
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'ok' } else { 'error' }
    path   = $ManifestPath
    issues = $issues.ToArray()
}
$result | ConvertTo-Json -Depth 8
if ($issues.Count -gt 0) { exit 1 }