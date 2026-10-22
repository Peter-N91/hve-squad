#Requires -Version 7.5
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Imports explicitly selected private observations as immutable, sanitized Git evidence.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, ParameterSetName = 'Complete')][string]$ControlPath,
    [Parameter(Mandatory)][string[]]$TrialDirectories,
    [Parameter(Mandatory)][string]$SeriesId,
    [string]$Repository = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
    [Parameter(ParameterSetName = 'Complete')][switch]$SelectCurrent,
    [Parameter(Mandatory, ParameterSetName = 'Observation')][switch]$ObservationOnly,
    [Parameter(ParameterSetName = 'Observation')][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BenchmarkResults.psm1') -Force
if ($ObservationOnly) {
    $Options = @{ Repository = $Repository; TrialDirectories = $TrialDirectories; CampaignId = $SeriesId }
    if ($OutputDirectory) { $Options.OutputDirectory = $OutputDirectory }
    $Record = Export-BenchmarkCampaign @Options
    Write-Output "Recorded campaign $($Record.campaignId); source $($Record.sourceHash). Comparison unavailable (exit 2); current.json unchanged. Review and commit the campaign, pointer, campaign report and badge."
    return
}
$Record = Export-BenchmarkSeries -Repository $Repository -ControlPath $ControlPath -TrialDirectories $TrialDirectories -SeriesId $SeriesId -SelectCurrent:$SelectCurrent
if ($SelectCurrent) { Write-BenchmarkSeriesReport $Record (Join-Path $Repository 'benchmarks/efficiency') }
Write-Output "Recorded $($Record.seriesId); source $($Record.sourceHash). No comparison or quality approval claimed."
