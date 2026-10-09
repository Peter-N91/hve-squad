#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Blind-judges every run's deliverable, one judge session per difficulty level. The judge step spends credits.
.DESCRIPTION
    For each level: anonymises each run's out/deliverable.diff (arm labels, run ids, paths,
    model ids and routing tokens redacted; squad tracking and install trees were already
    excluded when the diff was taken), shuffles the samples with a seeded RNG, and writes
    them to a judge directory OUTSIDE -ResultRoot. The key (sample id -> run id) stays in
    -ResultRoot/judge/keys, which the judge cannot read: the CLI only grants file access to
    its working directory unless told otherwise, and the judge gets read-only tools
    (view, glob, grep) and no shell.

    The judge replies with one JSON object (see judge-rubric.md). Its scores are
    de-anonymised through the key and written to -ResultRoot/judge-scores.csv and merged
    into -ResultRoot/results-judged.csv for New-BenchmarkReport.ps1.

    -PrepareOnly does everything except the judge call, so the anonymisation can be
    inspected before spending anything. -MergeOnly re-merges previously saved judge
    replies without calling the CLI again.
.PARAMETER JudgeModel
    Fixed judge model for every level. Defaults to claude-opus-5.5.
.EXAMPLE
    ./Invoke-BlindJudge.ps1 -ResultRoot $env:TEMP/hve-live-benchmark -PrepareOnly
.EXAMPLE
    ./Invoke-BlindJudge.ps1 -ResultRoot $env:TEMP/hve-live-benchmark
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResultRoot,
    [ValidateSet('easy', 'medium', 'hard')][string[]]$Levels = @('easy', 'medium', 'hard'),
    [int]$Seed = 137,
    [string]$JudgeModel = 'claude-opus-5.5',
    [string]$JudgeRoot = (Join-Path ([IO.Path]::GetTempPath()) "hve-live-benchmark-judge-$(Get-Date -Format 'yyyyMMdd-HHmmss')"),
    [string]$CliPath = (Join-Path $env:APPDATA 'npm/copilot.ps1'),
    [switch]$PrepareOnly,
    [switch]$MergeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'LiveBenchmark.psm1') -Force

$ResultRoot = (Resolve-Path -LiteralPath $ResultRoot).Path
$rows = @(Import-Csv -LiteralPath (Join-Path $ResultRoot 'results.csv'))
$keyRoot = Join-Path $ResultRoot 'judge/keys'
$replyRoot = Join-Path $ResultRoot 'judge/replies'
New-Item -ItemType Directory -Path $keyRoot, $replyRoot -Force | Out-Null
$merged = [System.Collections.Generic.List[object]]::new()

foreach ($level in $Levels) {
    $runs = @($rows | Where-Object level -EQ $level | ForEach-Object {
            [pscustomobject]@{ RunId = $_.runId; TrialRoot = $_.trial; DiffPath = Join-Path $_.trial 'out/deliverable.diff' }
        })
    if ($runs.Count -eq 0) { continue }
    $keyPath = Join-Path $keyRoot "$level.json"
    $replyPath = Join-Path $replyRoot "$level.txt"

    if (-not $MergeOnly) {
        $judgeDir = Join-Path $JudgeRoot $level
        $key = Export-JudgeSample -Runs $runs -SampleDirectory (Join-Path $judgeDir 'samples') -KeyPath $keyPath -Seed $Seed
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'judge-rubric.md') -Destination (Join-Path $judgeDir 'rubric.md')
        Set-Content -LiteralPath (Join-Path $judgeDir 'task.md') -Value "# Task`n`n$((Get-BenchmarkTask -Level $level).Prompt)" -Encoding utf8NoBOM
        Write-Host "$level : $($runs.Count) samples in $judgeDir"
        if ($PrepareOnly) { continue }

        $prompt = 'Follow rubric.md exactly. Read task.md, then every file in samples/. Score every sample and reply with the single JSON object rubric.md specifies, with no other text.'
        $judgeArgs = @('-p', $prompt, '--model', $JudgeModel, '--allow-all-tools', '--no-ask-user', '--disable-builtin-mcps',
            '--available-tools', 'view', 'glob', 'grep', '--output-format', 'json',
            '--secret-env-vars', 'GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'COPILOT_GITHUB_TOKEN')
        $eventsPath = Join-Path $replyRoot "$level.events.jsonl"
        Push-Location $judgeDir
        try { & $CliPath @judgeArgs 1> $eventsPath 2> (Join-Path $replyRoot "$level.stderr.txt") }
        finally { Pop-Location }
        $messages = @(Get-Content -LiteralPath $eventsPath | ForEach-Object { try { $_ | ConvertFrom-Json -Depth 32 } catch { Write-Debug 'non-JSON line' } } |
                Where-Object { $_ -and $_.type -eq 'assistant.message' -and $_.data.content })
        if ($messages.Count -eq 0) { Write-Warning "$level judge produced no assistant message; see $eventsPath"; continue }
        Set-Content -LiteralPath $replyPath -Value $messages[-1].data.content -Encoding utf8NoBOM
    }
    else {
        $key = Get-Content -LiteralPath $keyPath -Raw | ConvertFrom-Json
    }

    if (-not (Test-Path -LiteralPath $replyPath)) { Write-Warning "No judge reply for $level at $replyPath"; continue }
    $samples = Read-JudgeScore -Text (Get-Content -LiteralPath $replyPath -Raw)
    foreach ($score in Merge-JudgeScore -Samples $samples -Key $key) { $merged.Add($score) }
}

if ($PrepareOnly) { return }
$merged | Export-Csv -LiteralPath (Join-Path $ResultRoot 'judge-scores.csv') -NoTypeInformation -Encoding utf8NoBOM
$byRun = @{}
foreach ($s in $merged) { $byRun[$s.runId] = $s }
$rows | ForEach-Object {
    $s = $byRun[$_.runId]
    foreach ($name in 'judgeCorrectness', 'judgeTests', 'judgeDesign', 'judgeDocs', 'judgeMean') {
        $value = if ($s) { Format-Number $s.$name } else { '' }
        $_ | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
    }
    $_
} | Export-Csv -LiteralPath (Join-Path $ResultRoot 'results-judged.csv') -NoTypeInformation -Encoding utf8NoBOM
Write-Host "Judged $($merged.Count) of $($rows.Count) runs -> $(Join-Path $ResultRoot 'results-judged.csv')"
