#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Prints only the active canonical gate/mode sections instead of the whole manual.
.DESCRIPTION
    AI cost: none. Names select shipped sections, never commands or arbitrary paths.
    Multiple comma-separated names are returned in request order. Missing sections
    fail closed; no abbreviated policy or success-shaped fallback is generated.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Name)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force

try {
    $sections = [ordered]@{
        discovery = '## Discovery Gate Procedure'
        intake = '## Intake Gate Procedure'
        council = '## Council Procedure'
        implementation = '## Implementation Gate Procedure'
        'cost-preflight' = '## Cost Preflight Procedure'
        autonomous = '## Autonomous Procedure'
        autopilot = '## Autopilot Procedure'
    }
    $output = [Collections.Generic.List[string]]::new()
    foreach ($key in ($Name -split ',' | ForEach-Object Trim | Select-Object -Unique)) {
        if ($key -eq 'progress') {
            $output.Add((Get-SquadReferenceSection -Path (Join-Path $PSScriptRoot '..' 'references' 'operating-procedure.md') -Heading '### Progress Presentation'))
            continue
        }
        if (-not $sections.Contains($key)) { throw "Unknown procedure '$key'. Valid names: progress, $($sections.Keys -join ', ')." }
        $output.Add((Get-SquadReferenceSection -Path (Join-Path $PSScriptRoot '..' 'references' 'gates-and-modes.md') -Heading $sections[$key]))
    }
    $output -join "`n`n"
}
catch {
    [Console]::Error.WriteLine("Get-SquadProcedure: $($_.Exception.Message)")
    exit 1
}