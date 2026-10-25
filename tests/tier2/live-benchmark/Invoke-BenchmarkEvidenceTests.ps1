#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the offline self-checks for the benchmark score, its pull request comparer and the squad installer.
.DESCRIPTION
    Invokes no model and needs no Python, credentials or network access.
    Separate from the live-harness runner because it needs no Python. Also invoked by the
    Tier 2 comparator CI self-check.
#>
[CmdletBinding()]
param(
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module Pester -RequiredVersion 5.7.1

$config = New-PesterConfiguration
$config.Run.Container = New-PesterContainer -Path @(
    (Join-Path $PSScriptRoot '../../lib/SquadInstall.Tests.ps1'),
    (Join-Path $PSScriptRoot 'BenchmarkScore.Tests.ps1')
)
$config.Run.PassThru = $true
$config.Output.Verbosity = $Output

$result = Invoke-Pester -Configuration $config
if ($result.FailedCount -gt 0 -or $result.TotalCount -eq 0 -or $result.Result -ne 'Passed') { exit 1 }
