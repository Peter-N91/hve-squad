#Requires -Version 7.5
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Imports explicitly selected private observations as immutable, sanitized Git evidence.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ControlPath,
    [Parameter(Mandatory)][string[]]$TrialDirectories,
    [Parameter(Mandatory)][string]$SeriesId,
    [string]$Repository = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
    [switch]$SelectCurrent
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BenchmarkResults.psm1') -Force
$Record = Export-BenchmarkSeries -Repository $Repository -ControlPath $ControlPath -TrialDirectories $TrialDirectories -SeriesId $SeriesId -SelectCurrent:$SelectCurrent
if ($SelectCurrent) { Write-BenchmarkSeriesReport $Record (Join-Path $Repository 'benchmarks/efficiency') }
Write-Output "Recorded $($Record.seriesId); source $($Record.sourceHash). No comparison or quality approval claimed."
