#Requires -Version 7.5
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Compares immutable branch snapshots offline and always writes reports before verdict exit.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaseRef,
    [string]$HeadRef = 'HEAD',
    [string]$Repository = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
    [string]$OutputDirectory = (Join-Path (Get-Location) 'benchmark-report')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BenchmarkResults.psm1') -Force
$Report = Compare-BranchBenchmark -Repository $Repository -BaseRef $BaseRef -HeadRef $HeadRef
Write-BenchmarkReport -Report $Report -OutputDirectory $OutputDirectory
Write-Output "Benchmark: $($Report.status) (exit $($Report.exitCode))."
exit $Report.exitCode
