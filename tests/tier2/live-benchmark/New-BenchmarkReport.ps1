#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Turns the live benchmark results (and judge scores, when present) into a Markdown report. Offline.
.DESCRIPTION
    Reports sample statistics only: median with [min, max], and per-repeat paired
    differences against arm B. With three repeats per cell no significance test is
    meaningful, so none is computed or claimed.
.PARAMETER ResultsCsv
    results.csv, or results-judged.csv from Invoke-BlindJudge.ps1.
.PARAMETER OutFile
    Where to write the Markdown. Printed to the pipeline when omitted.
.EXAMPLE
    ./New-BenchmarkReport.ps1 -ResultsCsv $env:TEMP/hve-live-benchmark/results-judged.csv -OutFile $env:TEMP/hve-live-benchmark/report.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResultsCsv,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'LiveBenchmark.psm1') -Force

$rows = @(Import-Csv -LiteralPath $ResultsCsv)
if ($rows.Count -eq 0) { throw "No rows in $ResultsCsv" }
$levels = @('easy', 'medium', 'hard') | Where-Object { $rows.level -contains $_ }
$arms = @('B', 'R', 'E') | Where-Object { $rows.arm -contains $_ }
$hasJudge = [bool]$rows[0].PSObject.Properties['judgeMean']

function Get-Value { param($Row, [string]$Name) if ($Row.PSObject.Properties[$Name]) { ConvertFrom-InvariantNumber ([string]$Row.$Name) } }
function Get-Values { param($Set, [string]$Name) @($Set | ForEach-Object { Get-Value $_ $Name } | Where-Object { $null -ne $_ }) }
function Get-Sum { param($Values) $total = 0.0; foreach ($v in @($Values)) { if ($null -ne $v) { $total += $v } }; $total }
function Format-Stat {
    param([double[]]$Values, [int]$Digits = 1)
    if ($null -eq $Values -or $Values.Count -eq 0) { return 'n/a' }
    $med = Format-Number (Get-Median $Values) $Digits
    if ($Values.Count -eq 1) { return $med }
    '{0} [{1}, {2}]' -f $med, (Format-Number ($Values | Measure-Object -Minimum).Minimum $Digits), (Format-Number ($Values | Measure-Object -Maximum).Maximum $Digits)
}
function Format-Count { param($Set, [scriptblock]$Test) '{0}/{1}' -f @($Set | Where-Object $Test).Count, @($Set).Count }
function Format-Tally { param([string[]]$Values) (@($Values | Group-Object | Sort-Object Name | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ') }
function Format-Signed { param($Value, [int]$Digits = 1) if ($null -eq $Value) { 'n/a' } else { $s = Format-Number $Value $Digits; if ($Value -gt 0) { "+$s" } else { $s } } }

$lines = [System.Collections.Generic.List[string]]::new()
$add = { param([string]$Line = '') $lines.Add($Line) }

& $add '# Squad Live Benchmark Report'
& $add
& $add ("Generated {0:yyyy-MM-dd HH:mm} from ``{1}``: {2} scored runs, levels {3}, arms {4}." -f (Get-Date), (Split-Path -Leaf $ResultsCsv), $rows.Count, ($levels -join ', '), ($arms -join ', '))
& $add
& $add 'Arms: **B** baseline source with default routing; **R** candidate source with `routing=ranked`; **E** candidate source with `routing=economy`. Credits are `totalNanoAiu / 1e9` from the CLI usage file (runtime credits, not reconciled billing). Cells show median [min, max].'
& $add
& $add '| Arm | Session models | CLI versions | Source tree hashes |'
& $add '| --- | --- | --- | --- |'
foreach ($arm in $arms) {
    $set = @($rows | Where-Object arm -EQ $arm)
    $hashes = @($set.srcTreeHash | Sort-Object -Unique | ForEach-Object { if ($_) { $_.Substring(0, [Math]::Min(12, $_.Length)) } })
    & $add ("| {0} | {1} | {2} | {3} |" -f $arm, (@($set.model | Sort-Object -Unique) -join ', '), (@($set.cliVersion | Sort-Object -Unique) -join ', '), ($hashes -join ', '))
}

& $add
& $add '## Speed and Cost'
& $add
& $add '| Level | Arm | n | Seconds | Credits | Coordinator cr | Owner cr | Input tokens (k) | Output tokens (k) | Cache-read tokens (k) |'
& $add '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'
foreach ($level in $levels) {
    foreach ($arm in $arms) {
        $set = @($rows | Where-Object { $_.level -eq $level -and $_.arm -eq $arm })
        if ($set.Count -eq 0) { continue }
        $k = { param($name) @(Get-Values $set $name | ForEach-Object { $_ / 1000 }) }
        & $add ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f $level, $arm, $set.Count,
            (Format-Stat (Get-Values $set 'seconds') 0), (Format-Stat (Get-Values $set 'credits')), (Format-Stat (Get-Values $set 'coordCr')),
            (Format-Stat (Get-Values $set 'ownerCr')), (Format-Stat (& $k 'inputTokens') 0), (Format-Stat (& $k 'outputTokens') 0), (Format-Stat (& $k 'cacheReadTokens') 0))
    }
}

& $add
& $add '## Paired Differences vs B'
& $add
& $add 'Each row pairs an arm with the B run of the same level and repeat. Negative is faster or cheaper than B.'
& $add
& $add '| Level | Repeat | Arm | Δ seconds | Δ credits | Δ coordinator cr | Δ owner cr | Δ hidden passed |'
& $add '| --- | --- | --- | --- | --- | --- | --- | --- |'
$paired = [System.Collections.Generic.List[object]]::new()
foreach ($level in $levels) {
    foreach ($repeat in @($rows | Where-Object level -EQ $level | ForEach-Object { [int]$_.repeat } | Sort-Object -Unique)) {
        $base = @($rows | Where-Object { $_.level -eq $level -and [int]$_.repeat -eq $repeat -and $_.arm -eq 'B' } | Select-Object -First 1)
        if ($base.Count -eq 0) { continue }
        foreach ($arm in $arms | Where-Object { $_ -ne 'B' }) {
            $other = @($rows | Where-Object { $_.level -eq $level -and [int]$_.repeat -eq $repeat -and $_.arm -eq $arm } | Select-Object -First 1)
            if ($other.Count -eq 0) { continue }
            $delta = [ordered]@{ level = $level; arm = $arm }
            foreach ($name in 'seconds', 'credits', 'coordCr', 'ownerCr', 'hiddenPassed') {
                $a = Get-Value $other[0] $name; $b = Get-Value $base[0] $name
                $delta[$name] = if ($null -ne $a -and $null -ne $b) { $a - $b } else { $null }
            }
            $paired.Add([pscustomobject]$delta)
            & $add ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |" -f $level, $repeat, $arm, (Format-Signed $delta.seconds 0), (Format-Signed $delta.credits),
                (Format-Signed $delta.coordCr), (Format-Signed $delta.ownerCr), (Format-Signed $delta.hiddenPassed 0))
        }
    }
}
if ($paired.Count) {
    & $add
    & $add '| Level | Arm | Pairs | Median Δ seconds | Pairs faster | Median Δ credits | Pairs cheaper |'
    & $add '| --- | --- | --- | --- | --- | --- | --- |'
    foreach ($group in $paired | Group-Object level, arm) {
        $set = @($group.Group)
        $sec = @($set.seconds | Where-Object { $null -ne $_ }); $cr = @($set.credits | Where-Object { $null -ne $_ })
        & $add ("| {0} | {1} | {2} | {3} | {4}/{2} | {5} | {6}/{2} |" -f $set[0].level, $set[0].arm, $set.Count,
            (Format-Signed (Get-Median $sec) 0), @($sec | Where-Object { $_ -lt 0 }).Count, (Format-Signed (Get-Median $cr)), @($cr | Where-Object { $_ -lt 0 }).Count)
    }
}

& $add
& $add '## Quality'
& $add
& $add '| Level | Arm | Outcomes | Hidden tests passed | All hidden pass | Own tests pass | Own tests pass on reference | Mutants killed by own tests | Doc check | Review verdicts | Ledger -Check | Judge mean |'
& $add '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'
$hasOutcome = [bool]$rows[0].PSObject.Properties['outcome']
foreach ($level in $levels) {
    foreach ($arm in $arms) {
        $set = @($rows | Where-Object { $_.level -eq $level -and $_.arm -eq $arm })
        if ($set.Count -eq 0) { continue }
        $hidden = '{0}/{1}' -f (Get-Sum (Get-Values $set 'hiddenPassed')), (Get-Sum (Get-Values $set 'hiddenTotal'))
        $mutants = '{0}/{1}' -f (Get-Sum (Get-Values $set 'mutantsKilled')), (Get-Sum (Get-Values $set 'mutantsTotal'))
        $doc = if (@($set | Where-Object docCheck -NE 'n/a').Count) { Format-Count $set { $_.docCheck -eq 'pass' } } else { 'n/a' }
        $judge = if ($hasJudge) { Format-Stat (Get-Values $set 'judgeMean') } else { 'not judged' }
        $outcomes = if ($hasOutcome) { Format-Tally $set.outcome } else { 'n/a' }
        & $add ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} |" -f $level, $arm, $outcomes, $hidden,
            (Format-Count $set { $_.hiddenAllPass -eq 'True' }), (Format-Count $set { $_.ownTestsPass -eq 'True' }), (Format-Count $set { $_.testsOnReference -eq 'True' }),
            $mutants, $doc, (Format-Tally $set.reviewVerdict), (Format-Tally $set.ledgerCheck), $judge)
    }
}
if ($hasJudge) {
    & $add
    & $add '| Level | Arm | Judge correctness | Judge tests | Judge design | Judge docs |'
    & $add '| --- | --- | --- | --- | --- | --- |'
    foreach ($level in $levels) {
        foreach ($arm in $arms) {
            $set = @($rows | Where-Object { $_.level -eq $level -and $_.arm -eq $arm })
            if ($set.Count -eq 0) { continue }
            & $add ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $level, $arm, (Format-Stat (Get-Values $set 'judgeCorrectness')), (Format-Stat (Get-Values $set 'judgeTests')),
                (Format-Stat (Get-Values $set 'judgeDesign')), (Format-Stat (Get-Values $set 'judgeDocs')))
        }
    }
}

& $add
& $add '## Model Assignment'
& $add
& $add '`Model cell` is the `team.md` Model column (present only under ranked, economy, or manual routing). `Passed` is the model the coordinator passed on the `task` dispatch. `Match` compares the cell with the model the agent actually ran on.'
& $add
& $add '| Level | Arm | Role | Agent | Runs | Models used | Model cell | Passed | Match | Credits |'
& $add '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'
foreach ($level in $levels) {
    foreach ($arm in $arms) {
        $agents = @($rows | Where-Object { $_.level -eq $level -and $_.arm -eq $arm } | ForEach-Object {
                if ($_.agentsJson) { @($_.agentsJson | ConvertFrom-Json) }
            })
        foreach ($group in $agents | Group-Object role, agent | Sort-Object { $_.Group[0].role -ne 'coordinator' }, Name) {
            $set = @($group.Group)
            $blank = { param($v) @($v | Where-Object { $_ }) }
            & $add ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f $level, $arm, $set[0].role, $set[0].agent, $set.Count,
                (Format-Tally $set.modelsUsed), (Format-Tally (& $blank $set.modelCell)), (Format-Tally (& $blank $set.passedModel)), (Format-Tally $set.match),
                (Format-Stat @($set.credits | ForEach-Object { [double]$_ })))
        }
    }
}

& $add
& $add '## Process Signals'
& $add
& $add '| Level | Arm | Routing recorded | Model cells match | Top-level dispatches | Scribe dispatches | Generic-agent dispatches | Brief ran | Coordinator ran hand-off script | Hand-off seconds |'
& $add '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'
foreach ($level in $levels) {
    foreach ($arm in $arms) {
        $set = @($rows | Where-Object { $_.level -eq $level -and $_.arm -eq $arm })
        if ($set.Count -eq 0) { continue }
        & $add ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f $level, $arm, (Format-Tally $set.routingMode), (Format-Tally $set.modelMatch),
            (Format-Stat (Get-Values $set 'dispatches') 0), (Format-Stat (Get-Values $set 'scribeDispatches') 0), (Get-Sum (Get-Values $set 'genericDispatches')),
            (Format-Count $set { $_.briefRan -eq 'True' }), (Format-Stat (Get-Values $set 'coordScriptRuns') 0), (Format-Stat (Get-Values $set 'handoffSeconds') 0))
    }
}

$perCell = @($rows | Group-Object level, arm | ForEach-Object Count)
& $add
& $add '## Limitations'
& $add
& $add ("* **Sample size.** {0} to {1} runs per level and arm. Medians, ranges, and paired differences describe these runs only; no p-values or confidence intervals are claimed, and a difference smaller than the within-arm range is not evidence of an effect." -f ($perCell | Measure-Object -Minimum).Minimum, ($perCell | Measure-Object -Maximum).Maximum)
& $add '* **Warm cache and shared quota.** Runs execute back to back on one account, so prompt-cache warmth and service load vary with position; counterbalanced arm order spreads this across arms but does not remove it.'
& $add '* **Single fixture, single language.** Every level is a change to one small Python inventory ledger. Results may not transfer to larger repositories, other languages, or tasks that need research or planning.'
& $add '* **Source overlay.** Each arm overlays its squad-src onto a fresh fixture without a full APM install or hve-core, and every arm starts from the same seeded team.md and consumption-rates.md.'
& $add '* **Runtime credits.** Credits come from the CLI usage file and are not reconciled against billing.'
& $add '* **Quality proxies.** Hidden tests and mutants check the specified behaviour only. The blind judge is one model, one session per level, grading anonymised diffs; redaction removes arm labels, run ids, paths, model ids and routing tokens, but writing style could still leak.'

$text = $lines -join "`n"
if ($OutFile) { Set-Content -LiteralPath $OutFile -Value $text -Encoding utf8NoBOM; Write-Host "Report: $OutFile" } else { $text }
