#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Drives the live benchmark matrix (levels x arms x repeats) and appends one scored row per run. Spends credits.
.DESCRIPTION
    Arms are built from the two source directories passed in, never from branch names:
      B  -BaselineSrc,  default routing (no routing token)
      R  -CandidateSrc, prompt ends with routing=ranked
      E  -CandidateSrc, prompt ends with routing=economy
    Arm order is counterbalanced: each level gets a seeded random arm order that rotates
    one place per repeat, so over three repeats every arm runs once in every position,
    cancelling time-of-day and cache-warmth drift by position.
    The schedule is deterministic for a seed, so rerunning the same command resumes an
    interrupted matrix: run ids already in results.csv are skipped, and a run directory
    left by an interrupted run is moved aside, not deleted.

    Each run is a separate pwsh process (Invoke-LiveBenchmarkRun.ps1) so environment
    changes never leak between runs; scoring (Measure-LiveBenchmarkRun) is offline.
    After the matrix: Invoke-BlindJudge.ps1, then New-BenchmarkReport.ps1.
.PARAMETER BaselineSrc
    squad-src directory for arm B.
.PARAMETER CandidateSrc
    squad-src directory for arms R and E. Required when either is selected.
.PARAMETER Plan
    Print the schedule and exit without running anything.
.EXAMPLE
    ./Invoke-LiveBenchmark.ps1 -BaselineSrc C:/wt/main/squad-src -CandidateSrc C:/wt/int/squad-src -ResultRoot $env:TEMP/hve-live-benchmark
.EXAMPLE
    ./Invoke-LiveBenchmark.ps1 -BaselineSrc C:/wt/main/squad-src -Levels easy -Arms B -Repeats 1 -ResultRoot $env:TEMP/lb-pilot
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaselineSrc,
    [string]$CandidateSrc,
    [ValidateSet('easy', 'medium', 'hard')][string[]]$Levels = @('easy', 'medium', 'hard'),
    [ValidateSet('B', 'R', 'E')][string[]]$Arms = @('B', 'R', 'E'),
    [ValidateRange(1, 50)][int]$Repeats = 3,
    [int]$Seed = 137,
    [string]$ResultRoot = (Join-Path ([IO.Path]::GetTempPath()) 'hve-live-benchmark'),
    [string]$Model = 'claude-sonnet-5',
    [string]$CliPath = (Join-Path $env:APPDATA 'npm/copilot.ps1'),
    [switch]$Plan
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'LiveBenchmark.psm1') -Force

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$ResultRoot = [IO.Path]::GetFullPath($ResultRoot)
if ($ResultRoot.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "ResultRoot must be outside the repository: $ResultRoot" }
if (($Arms -contains 'R' -or $Arms -contains 'E') -and -not $CandidateSrc) { throw 'Arms R and E need -CandidateSrc.' }
$sources = @{ B = (Resolve-Path -LiteralPath $BaselineSrc).Path }
if ($CandidateSrc) { $sources.R = (Resolve-Path -LiteralPath $CandidateSrc).Path; $sources.E = $sources.R }

$schedule = @(Get-BenchmarkSchedule -Levels $Levels -Arms $Arms -Repeats $Repeats -Seed $Seed)
if ($Plan) { return $schedule | Format-Table Index, Repeat, Level, Position, Arm, RunId -AutoSize }

New-Item -ItemType Directory -Path (Join-Path $ResultRoot 'runs') -Force | Out-Null
$csv = Join-Path $ResultRoot 'results.csv'
[ordered]@{ seed = $Seed; levels = $Levels; arms = $Arms; repeats = $Repeats; model = $Model; sources = $sources; schedule = $schedule } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $ResultRoot "matrix-$(Get-Date -Format 'yyyyMMdd-HHmmss').json") -Encoding utf8NoBOM
$done = if (Test-Path -LiteralPath $csv) { @(Import-Csv -LiteralPath $csv | ForEach-Object runId) } else { @() }

foreach ($run in $schedule) {
    if ($done -contains $run.RunId) { Write-Host "skip $($run.RunId) (already scored)"; continue }
    $trial = Join-Path $ResultRoot "runs/$($run.RunId)"
    if (Test-Path -LiteralPath $trial) { Move-Item -LiteralPath $trial -Destination "$trial.incomplete-$(Get-Date -Format 'yyyyMMddHHmmss')" }
    Write-Host ("[{0}/{1}] {2} start {3:HH:mm:ss}" -f $run.Index, $schedule.Count, $run.RunId, (Get-Date))
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Invoke-LiveBenchmarkRun.ps1') -Src $sources[$run.Arm] -Level $run.Level -Arm $run.Arm `
        -TrialRoot $trial -RunId $run.RunId -Repeat $run.Repeat -Position $run.Position -Model $Model -CliPath $CliPath | Out-Host
    if (-not (Test-Path -LiteralPath (Join-Path $trial 'out/result.json'))) { Write-Warning "$($run.RunId) wrote no result.json; not scored."; continue }
    $row = Measure-LiveBenchmarkRun -TrialRoot $trial
    $row | Export-Csv -LiteralPath $csv -Append -NoTypeInformation -Encoding utf8NoBOM
    $row | Select-Object runId, seconds, credits, coordCr, ownerCr, hiddenPassed, hiddenTotal, mutantsKilled, docCheck, reviewVerdict, ledgerCheck, modelMatch | Format-List | Out-Host
}
Write-Host "Results: $csv"
