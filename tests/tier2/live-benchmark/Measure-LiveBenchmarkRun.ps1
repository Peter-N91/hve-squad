#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Scores one finished live benchmark run and prints its results row. Offline.
.PARAMETER TrialRoot
    The run directory Invoke-LiveBenchmarkRun.ps1 wrote.
.PARAMETER Csv
    Optional results file to append the row to.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TrialRoot,
    [string]$Csv
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'LiveBenchmark.psm1') -Force

$row = Measure-LiveBenchmarkRun -TrialRoot (Resolve-Path -LiteralPath $TrialRoot).Path
if ($Csv) { $row | Export-Csv -LiteralPath $Csv -Append -NoTypeInformation -Encoding utf8NoBOM }
$row
