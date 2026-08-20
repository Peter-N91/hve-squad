#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Scores Tier 1 run observations against the golden baselines and reports the drift.
.DESCRIPTION
    Consumes the observation.json files a Tier 1 live run produced and compares each to
    tests/tier2/baselines/<scenario>.baseline.json across the four questions in the
    behavior contract: same roles, same deliverable types at the same roots, same gates
    with the same verdicts, and - only when a judge is asked for - a materially
    equivalent answer.

    Advisory by default. A scenario with no baseline is reported as unbaselined rather
    than failed, because the first run of a new scenario has nothing to drift from.
.PARAMETER ObservationRoot
    Tier 1 results directory, or any directory containing observation.json files.
.PARAMETER BaselineRoot
    Directory holding <scenario>.baseline.json.
.PARAMETER Threshold
    Minimum overall score a scenario must reach when -Blocking is set.
.PARAMETER Blocking
    Exit non-zero when a scored scenario falls below -Threshold. Leave off until the
    noise floor across repeat runs is known.
.PARAMETER UpdateBaseline
    Write the candidate observations to -BaselineRoot instead of scoring them. Use only
    on a release known to be good; a baseline captured from a broken run makes every
    later comparison agree with the break.
.PARAMETER JudgeAnswer
    Score the prose dimension with a model. Costs Copilot requests.
.PARAMETER SummaryPath
    Markdown summary destination. Defaults to GITHUB_STEP_SUMMARY when set.
.EXAMPLE
    ./Compare-SquadRun.ps1 -ObservationRoot ../tier1/results
.EXAMPLE
    ./Compare-SquadRun.ps1 -ObservationRoot ../tier1/results -UpdateBaseline
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ObservationRoot,

    [string]$BaselineRoot = (Join-Path $PSScriptRoot 'baselines'),

    [double]$Threshold = 0.85,

    [switch]$Blocking,

    [switch]$UpdateBaseline,

    [switch]$JudgeAnswer,

    [string]$Model = 'claude-sonnet-5',

    [string]$ResultPath,

    [string]$SummaryPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'SquadCompare.psm1') -Force

$ObservationRoot = (Resolve-Path -LiteralPath $ObservationRoot).Path
New-Item -ItemType Directory -Path $BaselineRoot -Force | Out-Null

if (-not $ResultPath) { $ResultPath = Join-Path $ObservationRoot 'tier2-score.json' }
if (-not $SummaryPath -and $env:GITHUB_STEP_SUMMARY) { $SummaryPath = $env:GITHUB_STEP_SUMMARY }

# Latest attempt wins: a scenario that passed on retry is the run that counts, and the
# failed attempt's tree is kept beside it for triage either way.
$observations = @(
    Get-ChildItem -LiteralPath $ObservationRoot -Filter 'observation.json' -Recurse -File |
        ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } |
        Group-Object -Property scenario |
        ForEach-Object { $_.Group | Sort-Object { $_.metadata.attempt } | Select-Object -Last 1 }
)

if ($observations.Count -eq 0) {
    throw "No observation.json found under $ObservationRoot. Run Tier 1 first."
}

if ($UpdateBaseline) {
    foreach ($observation in $observations) {
        $path = Join-Path $BaselineRoot "$($observation.scenario).baseline.json"
        $observation | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
        Write-Host "Captured baseline for '$($observation.scenario)' -> $path" -ForegroundColor Green
    }
    return
}

$scores = @()
$unbaselined = @()

foreach ($observation in $observations) {
    $baselinePath = Join-Path $BaselineRoot "$($observation.scenario).baseline.json"
    if (-not (Test-Path -LiteralPath $baselinePath)) {
        $unbaselined += $observation.scenario
        Write-Host "No baseline for '$($observation.scenario)'; skipping." -ForegroundColor Yellow
        continue
    }

    $baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json

    $answerScore = -1.0
    $answerNote = 'not judged'
    if ($JudgeAnswer) {
        $judged = Get-AnswerScore -Baseline $baseline.answer -Candidate $observation.answer -Model $Model
        $answerScore = $judged.Score
        $answerNote = $judged.Note
    }

    $scores += Compare-SquadObservation -Baseline $baseline -Candidate $observation `
        -AnswerScore $answerScore -AnswerNote $answerNote
}

$report = [pscustomobject]@{
    schemaVersion = 1
    threshold     = $Threshold
    blocking      = [bool]$Blocking
    judged        = [bool]$JudgeAnswer
    unbaselined   = $unbaselined
    scenarios     = $scores
}

$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ResultPath -Encoding utf8NoBOM

$lines = @(
    '## Tier 2 semantic comparison'
    ''
    $(if ($Blocking) { "Blocking at **$Threshold**." } else { 'Advisory - no score below fails this run.' })
    ''
    '| Scenario | Overall | Routing | Deliverables | Gates | Answer |'
    '|---|---|---|---|---|---|'
)

foreach ($score in $scores) {
    $answer = if ($null -eq $score.dimensions.answer.score) { 'n/a' } else { $score.dimensions.answer.score }
    $lines += '| {0} | {1} | {2} | {3} | {4} | {5} |' -f @(
        $score.scenario
        $(if ($score.overall -lt $Threshold) { "**$($score.overall)**" } else { $score.overall })
        $score.dimensions.routing.score
        $score.dimensions.deliverables.score
        $score.dimensions.gates.score
        $answer
    )
}

$drift = @(
    foreach ($score in $scores) {
        foreach ($name in @('routing', 'deliverables', 'gates')) {
            $dimension = $score.dimensions.$name
            foreach ($item in $dimension.missing) { "- ``$($score.scenario)`` $name **missing**: $item" }
            foreach ($item in $dimension.added) { "- ``$($score.scenario)`` $name **added**: $item" }
        }
    }
)

if ($drift) { $lines += @('', '### Differences', '') + $drift }
if ($unbaselined) { $lines += @('', "Unbaselined (no golden capture yet): $($unbaselined -join ', ')") }

$summary = $lines -join "`n"
Write-Host $summary

if ($SummaryPath) { Add-Content -LiteralPath $SummaryPath -Value $summary }

if ($Blocking) {
    $below = @($scores | Where-Object { $_.overall -lt $Threshold })
    if ($below) {
        Write-Error "Tier 2: $($below.Count) scenario(s) below $Threshold." -ErrorAction Continue
        exit 1
    }
}
