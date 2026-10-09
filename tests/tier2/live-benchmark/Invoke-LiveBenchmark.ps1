#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Drives the live benchmark matrix (levels x arms x repeats) and appends one scored row per run. Spends credits.
.DESCRIPTION
    Arms are built from the two source directories passed in, never from branch names:
      A  -BaselineSrc,  default routing (no routing token)
      B  -CandidateSrc, default routing; must match A (default-mode regression check)
      C  -BaselineSrc,  prompt ends with routing=ranked
      D  -CandidateSrc, prompt ends with routing=ranked; must match C
      E  -CandidateSrc, prompt ends with routing=economy; compared with A
      F  -CandidateSrc, prompt ends with routing=economy delivery=background; optional, compared with E
    Arm order is counterbalanced: each level gets a seeded random arm order that rotates
    one place per repeat, so over as many repeats as there are arms every arm runs once
    in every position, cancelling time-of-day and cache-warmth drift by position.
    The schedule is deterministic for a seed, so rerunning the same command resumes an
    interrupted matrix: run ids already in results.csv are skipped, and a run directory
    left by an interrupted run is moved aside, not deleted.

    Each run is a separate pwsh process (Invoke-LiveBenchmarkRun.ps1) so environment
    changes never leak between runs; scoring (Measure-LiveBenchmarkRun) is offline.
    After the matrix: Invoke-BlindJudge.ps1, then New-BenchmarkReport.ps1.
.PARAMETER Repeats
    Repeats per level and arm. Defaults to 8; lower values are indicative only.
.PARAMETER BaselineSrc
    Repository root of the baseline (apm.yml and squad-src/) for arms A and C.
.PARAMETER CandidateSrc
    Repository root of the candidate for arms B, D and E. Required when any is selected.
.PARAMETER Install
    Install each source once with APM (hve-core included) and copy that tree into every
    run, as a consumer would have it. Without it, runs get a squad-src overlay only and
    roles that load hve-core skills cannot run.
.PARAMETER Plan
    Print the schedule and exit without running anything.
.PARAMETER SkipJudge
    Skip blind judging and generate a report that clearly marks quality rows as not judged.
.EXAMPLE
    ./Invoke-LiveBenchmark.ps1 -BaselineSrc C:/wt/main -CandidateSrc C:/wt/int -Install -Repeats 10 -ResultRoot $env:TEMP/hve-live-benchmark
.EXAMPLE
    ./Invoke-LiveBenchmark.ps1 -BaselineSrc C:/wt/main -Levels easy -Arms A -Repeats 1 -ResultRoot $env:TEMP/lb-pilot
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaselineSrc,
    [string]$CandidateSrc,
    [ValidateSet('easy', 'medium', 'hard')][string[]]$Levels = @('easy', 'medium', 'hard'),
    [ValidateSet('A', 'B', 'C', 'D', 'E', 'F')][string[]]$Arms = @('A', 'B', 'C', 'D', 'E'),
    [ValidateRange(1, 50)][int]$Repeats = 8,
    [int]$Seed = 137,
    [string]$ResultRoot = (Join-Path ([IO.Path]::GetTempPath()) 'hve-live-benchmark'),
    [string]$Model = 'claude-sonnet-5.5',
    [string]$CliPath = (Join-Path $env:APPDATA 'npm/copilot.ps1'),
    [string]$JudgeScript = (Join-Path $PSScriptRoot 'Invoke-BlindJudge.ps1'),
    [switch]$Install,
    [switch]$SkipJudge,
    [switch]$Plan
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'LiveBenchmark.psm1') -Force
Write-BenchmarkRepeatWarning -Repeats $Repeats

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$ResultRoot = [IO.Path]::GetFullPath($ResultRoot)
if ($ResultRoot.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "ResultRoot must be outside the repository: $ResultRoot" }
$needsCandidate = @($Arms | Where-Object { (Get-ArmSource -Arm $_) -eq 'candidate' }).Count -gt 0
if ($needsCandidate -and -not $CandidateSrc) { throw 'Arms B, D, E and F need -CandidateSrc.' }
$roots = @{ baseline = (Resolve-Path -LiteralPath $BaselineSrc).Path }
if ($CandidateSrc) { $roots.candidate = (Resolve-Path -LiteralPath $CandidateSrc).Path }
foreach ($root in $roots.Values) { if (-not (Test-Path -LiteralPath (Join-Path $root 'squad-src/.github/agents'))) { throw "Not a repository root with squad-src: $root" } }
$sources = @{}
foreach ($arm in $Arms) { $sources[$arm] = Join-Path $roots[(Get-ArmSource -Arm $arm)] 'squad-src' }

$schedule = @(Get-BenchmarkSchedule -Levels $Levels -Arms $Arms -Repeats $Repeats -Seed $Seed)
if ($Plan) { return $schedule | Format-Table Index, Repeat, Level, Position, Arm, RunId -AutoSize }

$disabledMcpServers = @(Get-ConfiguredMcpServerNames -CliPath $CliPath)
New-Item -ItemType Directory -Path (Join-Path $ResultRoot 'runs') -Force | Out-Null
$installs = @{}
if ($Install) {
    Import-Module (Join-Path $repoRoot 'tests/lib/SquadInstall.psm1') -Force
    foreach ($kind in $roots.Keys) {
        # Keyed by the squad-src tree hash, so a resumed matrix reuses an install of the same source.
        $dir = Join-Path $ResultRoot "installs/$kind-$((Get-SourceTreeHash -Path (Join-Path $roots[$kind] 'squad-src')).Substring(0, 12))"
        if (-not (Test-Path -LiteralPath (Join-Path $dir '.agents'))) {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            Install-SquadPackage -Destination $dir -SourceRoot $roots[$kind] | Out-Null
        }
        $installs[$kind] = $dir
    }
}
$csv = Join-Path $ResultRoot 'results.csv'
[ordered]@{ seed = $Seed; levels = $Levels; arms = $Arms; repeats = $Repeats; model = $Model; sources = $sources; installed = [bool]$Install; schedule = $schedule; disabledMcpServers = $disabledMcpServers } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $ResultRoot "matrix-$(Get-Date -Format 'yyyyMMdd-HHmmss').json") -Encoding utf8NoBOM
$done = if (Test-Path -LiteralPath $csv) { @(Import-Csv -LiteralPath $csv | ForEach-Object runId) } else { @() }

foreach ($run in $schedule) {
    if ($done -contains $run.RunId) { Write-Host "skip $($run.RunId) (already scored)"; continue }
    $trial = Join-Path $ResultRoot "runs/$($run.RunId)"
    if (Test-Path -LiteralPath $trial) { Move-Item -LiteralPath $trial -Destination "$trial.incomplete-$(Get-Date -Format 'yyyyMMddHHmmss')" }
    Write-Host ("[{0}/{1}] {2} start {3:HH:mm:ss}" -f $run.Index, $schedule.Count, $run.RunId, (Get-Date))
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Invoke-LiveBenchmarkRun.ps1') -Src $sources[$run.Arm] -Level $run.Level -Arm $run.Arm `
        -TrialRoot $trial -RunId $run.RunId -Repeat $run.Repeat -Position $run.Position -Model $Model -CliPath $CliPath `
        -DisabledMcpServers ($disabledMcpServers -join ',') -InstallRoot $(if ($Install) { $installs[(Get-ArmSource -Arm $run.Arm)] } else { '' }) | Out-Host
    if (-not (Test-Path -LiteralPath (Join-Path $trial 'out/result.json'))) { Write-Warning "$($run.RunId) wrote no result.json; not scored."; continue }
    $row = Measure-LiveBenchmarkRun -TrialRoot $trial
    $row | Export-Csv -LiteralPath $csv -Append -NoTypeInformation -Encoding utf8NoBOM -Force
    $row | Select-Object runId, seconds, credits, coordCr, ownerCr, hiddenPassed, hiddenTotal, mutantsKilled, docCheck, reviewVerdict, ledgerCheck, modelMatch | Format-List | Out-Host
}
Write-Host "Results: $csv"
$report = Invoke-BenchmarkJudgeAndReport -ResultRoot $ResultRoot -Levels $Levels -Seed $Seed -SkipJudge:$SkipJudge -JudgeScript $JudgeScript
Write-Host "Report: $($report.ReportPath)"
