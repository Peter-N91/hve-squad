#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Benchmarks the squad in this checkout and saves the score in benchmarks/efficiency/.
.DESCRIPTION
    Runs the cold-start benchmark -Runs times against this checkout's squad-src/ and
    writes score.json, badge.svg and report.md into benchmarks/efficiency/. Commit those
    files with your branch. The score is not compared with any other branch.

    This SPENDS Copilot credits: about 300 credits and 20 minutes per run. Use -WhatIf
    to see what would run without spending anything.

    The benchmark runs an autonomous Copilot agent with tool filters, not an OS sandbox.
    Run it on a throwaway machine, container or VM.
.PARAMETER Runs
    How many times to run the benchmark, from 1 to 3 (default 3). One run is a quick check.
.EXAMPLE
    pwsh -NoProfile -File ./tests/tier2/live-benchmark/Invoke-Benchmark.ps1 -Runs 1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateRange(1, 3)][int]$Runs = 3
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$OutputDirectory = Join-Path $RepoRoot 'benchmarks/efficiency'
$CreditCeilingPerRun = 1000

function Get-GitOutput {
    param([string[]]$Arguments)
    $output = & git -C $RepoRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $output" }
    @($output | Where-Object { $_ })
}

if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'squad-src/.github/agents') -PathType Container)) {
    throw 'Run this from a checkout of the squad repository: squad-src/ was not found.'
}
foreach ($Tool in 'git', 'apm', 'copilot') {
    if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
        throw "'$Tool' was not found on PATH. The prerequisites are listed in benchmarks/efficiency/README.md."
    }
}

$Commit = [string]@(Get-GitOutput @('rev-parse', 'HEAD'))[0]
$Branch = @(Get-GitOutput @('branch', '--show-current')) -join ''
if (-not $Branch) { $Branch = 'detached HEAD' }
$Uncommitted = @(Get-GitOutput @('status', '--porcelain', '--', 'squad-src')).Count -gt 0

Write-Host @"
Benchmarking '$Branch' at $($Commit.Substring(0, 7))$(if ($Uncommitted) { ', including uncommitted changes in squad-src/' }).
  Runs:          $Runs
  Expected cost: about $($Runs * 300) Copilot credits and $($Runs * 20) minutes$(if ($Runs -gt 1) { ' (about 300 credits and 20 minutes per run)' })
  Stops a run:   at $CreditCeilingPerRun credits
  Saves to:      benchmarks/efficiency/ (score.json, badge.svg, report.md)

WARNING: this runs an autonomous Copilot agent with tool filters, not an OS sandbox.
Use a throwaway machine, container or VM.
"@
if (-not $PSCmdlet.ShouldProcess("$Runs benchmark run(s) of $Branch", 'Spend Copilot credits')) { return }

Import-Module (Join-Path $RepoRoot 'tests/lib/SquadInstall.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'BenchmarkScore.psm1') -Force

$Work = Join-Path ([IO.Path]::GetTempPath()) ('sbench-{0:yyMMdd-HHmmss}-{1}' -f [datetime]::Now, $PID)
$Trials = Join-Path $Work 'trials'
[void][IO.Directory]::CreateDirectory($Trials)
Write-Host "Evidence and logs are kept in $Work (safe to delete afterwards)."

Write-Host 'Installing the squad from this checkout...'
$Install = Install-SquadPackage -Destination (Join-Path $Work 'install') -SourceRoot $RepoRoot

$Engine = Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'
$Scenario = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'efficiency-scenario.json') -Raw | ConvertFrom-Json -AsHashtable
$TimeoutSeconds = [int]$Scenario.observationTimeoutMinutes * 60 + 120
$Ceiling = $CreditCeilingPerRun.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$Summaries = [Collections.Generic.List[object]]::new()
$Identity = @{}

for ($Run = 1; $Run -le $Runs; $Run++) {
    Write-Host "Run $Run of $Runs started at $(Get-Date -Format 'HH:mm'). It takes about 20 minutes..."
    $TrialPath = Join-Path $Trials "run-$Run"
    $Log = Join-Path $Work "run-$Run.log"
    $Result = $null
    $Note = ''
    try {
        $Arguments = @('-NoProfile', '-File', $Engine, '-Mode', 'Run', '-TrialRoot', $TrialPath, '-SourceRoot', $RepoRoot, '-InstallRoot', $Install.Root, '-Arm', 'baseline', '-Pair', [string]$Run, '-MaxCredits', $Ceiling, '-Live', '-IsolatedEnvironment', '-ObservationOnly')
        $Process = Invoke-EfficiencyProcess -FilePath (Get-Process -Id $PID).Path -Arguments $Arguments -WorkingDirectory $Trials -OutputPath $Log -TimeoutSeconds $TimeoutSeconds -EnvironmentVariables @{ COPILOT_AUTO_UPDATE = 'false' }
        $RunJson = Join-Path $TrialPath 'out/run.json'
        if (Test-Path -LiteralPath $RunJson -PathType Leaf) { $Result = Get-Content -LiteralPath $RunJson -Raw | ConvertFrom-Json -AsHashtable }
        else { $Note = "the run produced no result (exit code $($Process.exitCode), stop cause $($Process.stopCause))" }
    }
    catch {
        $Note = "the run could not be completed: $($_.Exception.Message)"
    }

    $Summary = ConvertTo-BenchmarkRunSummary -Run $Run -Result $Result -Note $Note
    $Summaries.Add($Summary)
    if ($Summary['scored']) {
        if (-not $Identity.Count -and $null -ne $Result) { $Identity = Get-BenchmarkRunIdentity -Result $Result }
        Write-Host "Run $Run scored: quality $($Summary['quality'])/100, functional $(if ($Summary['functional']) { 'passed' } else { 'failed' }), workflow $(if ($Summary['workflow']) { 'passed' } else { 'failed' })."
    }
    else {
        Write-Host "Run $Run did not produce a score: $($Summary['note'])"
        if (Test-Path -LiteralPath "$Log.stderr") { Get-Content -LiteralPath "$Log.stderr" -Tail 8 | ForEach-Object { Write-Host "  $_" } }
    }
}

$Scored = @($Summaries | Where-Object { $_['scored'] }).Count
if ($Scored -eq 0) {
    Write-Host "No run produced a score, so benchmarks/efficiency/ was left unchanged. Logs and evidence: $Work"
    exit 1
}
$Score = ConvertTo-BenchmarkScore -Trial $Summaries.ToArray() -Requested $Runs -Commit $Commit -UncommittedChanges $Uncommitted -Identity $Identity -Scenario ([string]$Scenario.name)
[void](Write-BenchmarkScore -Score $Score -Directory $OutputDirectory)
Write-Host ''
Write-Host (Get-BenchmarkBadgeText $Score)
if ($Scored -lt $Runs) { Write-Warning "$($Runs - $Scored) of $Runs runs did not produce a score; they are recorded as failed." }
Write-Host 'Saved score.json, badge.svg and report.md in benchmarks/efficiency/. Commit them with your branch.'
