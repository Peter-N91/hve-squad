# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Pure, offline classification and safeguard logic for the U5 live pipelining
# benchmark (routing-performance plan, Amendment 1 "Benchmark Protocol", Amendment 2
# §11, Amendment 3 §5 Unit U5 / P04-T04, P04-T06). Nothing in this module invokes a
# model, reads a live squad root, or touches the network -- every function is a
# deterministic transform over numbers the caller already measured, which is what
# lets PipeliningClassification.Tests.ps1 assert the classification and void rules
# without spending a single live Copilot request.
#
# The two caveat sentences below are drafted here, verbatim, per the Challenger
# errata (CH-N7, CH-N9): the plan required them in the report *body*, not only in a
# disposition table, and Get-BenchmarkClassification is the single place that emits
# the report body's caveat list, so this is where they are pinned.

#Requires -Version 7.4

Set-StrictMode -Version Latest

# CH-N7: the ambient session/tool timeout is the only bound on a single run's
# duration; this benchmark enforces no additional per-run timeout of its own.
$script:AmbientTimeoutCaveat = 'Ambient session/tool timeout is the only bound on a single run''s duration; this benchmark enforces no separate per-run timeout, so a run that stalls is caught by the host''s own ambient timeout (or the harness-level cost precheck between runs), not by a benchmark-specific clock.'

# CH-N9: any classification resting on N=2 per arm carries low statistical power.
$script:LowPowerCaveat = 'Low statistical power (N=2): this classification rests on the N=2 deterministic fallback for at least one arm, not the N=3 target. A spread computed from two points carries no distributional information, so a gain/no-gain call at N=2 is materially less reliable than at N=3 and any keep-or-revert decision built on it should weight that accordingly.'

function Get-Median {
    <#
    .SYNOPSIS
        Returns the median of a numeric array (average of the two middle values when
        the count is even).
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)]
        [double[]]$Value
    )

    if ($Value.Count -eq 0) { throw 'Get-Median: cannot take the median of an empty array.' }

    $sorted = @($Value | Sort-Object)
    $middle = [int]([math]::Floor($sorted.Count / 2))

    if ($sorted.Count % 2 -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}

function Get-Spread {
    <#
    .SYNOPSIS
        Returns max(Value) - min(Value). Throws on an empty array; a spread needs at
        least one point, and a meaningful one needs at least two.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)]
        [double[]]$Value
    )

    if ($Value.Count -eq 0) { throw 'Get-Spread: cannot take the spread of an empty array.' }
    return ([double]($Value | Measure-Object -Maximum).Maximum) - ([double]($Value | Measure-Object -Minimum).Minimum)
}

function Get-BenchmarkClassification {
    <#
    .SYNOPSIS
        Applies the fixed-in-advance classification rule (Amendment 1 "Classification
        Rule", Amendment 2 §11) to a set of BEFORE/AFTER elapsed-time observations.
    .DESCRIPTION
        Void rule is AFTER-only (Amendment 2 R10): a BEFORE run is never voided by its
        own overlap count (BEFORE is expected to show 0 pipelining overlaps -- that is
        the sequential baseline, not a defect). An AFTER run whose independently
        measured overlapped-boundary count is 0 is void and excluded from the
        median/spread computation. More than one void AFTER run out of N forces
        `inconclusive` regardless of the surviving numbers (Amendment 2 R10 / §11).

        Data-sufficiency safeguard: fewer than 2 valid (non-void) runs in *either* arm
        after voiding also forces `inconclusive` (Amendment 1 "Data sufficiency
        safeguard").

        Classification (Amendment 1 "Classification Rule", exact threshold):
          gain:         median_delta > larger_spread
          inconclusive: 0 < median_delta <= larger_spread
          no-gain:      median_delta <= 0
        where median_delta = median(BEFORE) - median(AFTER) (positive means AFTER is
        faster) and larger_spread = max(spread(BEFORE valid), spread(AFTER valid)).

        The CH-N7 ambient-timeout caveat is always present in the returned Caveats
        list. The CH-N9 low-statistical-power caveat is added only when either arm's
        valid-run count is exactly 2 (the N=2 deterministic fallback), per Amendment 3
        Unit U5's exit evidence.
    .PARAMETER BeforeElapsedSeconds
        Elapsed wall-clock seconds for every BEFORE-arm run attempted (void-exempt).
    .PARAMETER AfterElapsedSeconds
        Elapsed wall-clock seconds for every AFTER-arm run attempted, in the same
        order as -AfterOverlapCount.
    .PARAMETER AfterOverlapCount
        Independently measured overlapped-boundary count (0, 1, or 2 for this
        scenario's two pipelinable boundaries) for each AFTER run, same order/length
        as -AfterElapsedSeconds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double[]]$BeforeElapsedSeconds,

        [Parameter(Mandatory)]
        [double[]]$AfterElapsedSeconds,

        [Parameter(Mandatory)]
        [int[]]$AfterOverlapCount
    )

    if ($AfterElapsedSeconds.Count -ne $AfterOverlapCount.Count) {
        throw 'Get-BenchmarkClassification: -AfterElapsedSeconds and -AfterOverlapCount must be the same length (one overlap count per AFTER run).'
    }

    $afterVoidMask = @($AfterOverlapCount | ForEach-Object { $_ -eq 0 })
    $afterVoidCount = @($afterVoidMask | Where-Object { $_ }).Count

    $afterValid = [System.Collections.Generic.List[double]]::new()
    for ($i = 0; $i -lt $AfterElapsedSeconds.Count; $i++) {
        if (-not $afterVoidMask[$i]) { $afterValid.Add($AfterElapsedSeconds[$i]) }
    }
    $beforeValid = @($BeforeElapsedSeconds)

    $caveats = [System.Collections.Generic.List[string]]::new()
    $caveats.Add($script:AmbientTimeoutCaveat)

    $result = [ordered]@{
        beforeValidCount  = $beforeValid.Count
        afterValidCount   = $afterValid.Count
        afterVoidCount    = $afterVoidCount
        afterTotalRuns    = $AfterElapsedSeconds.Count
        spreadBefore      = $null
        spreadAfter       = $null
        largerSpread      = $null
        medianBefore      = $null
        medianAfter       = $null
        medianDeltaSecond = $null
        medianDeltaPct    = $null
        classification    = $null
        reason            = $null
        lowPower          = $false
        caveats           = $caveats
    }

    if ($afterVoidCount -gt 1) {
        $result.classification = 'inconclusive'
        $result.reason = "$afterVoidCount of $($AfterElapsedSeconds.Count) AFTER runs were void (0 independently-observed overlaps); more than 1 void AFTER run forces inconclusive regardless of the surviving numbers."
        return [pscustomobject]$result
    }

    if ($beforeValid.Count -lt 2 -or $afterValid.Count -lt 2) {
        $result.classification = 'inconclusive'
        $result.reason = "Data-sufficiency safeguard: BEFORE has $($beforeValid.Count) valid run(s), AFTER has $($afterValid.Count) valid run(s) (after voiding); fewer than 2 valid runs in either arm cannot be classified."
        if ($beforeValid.Count -eq 2 -or $afterValid.Count -eq 2) {
            $result.lowPower = $true
            $caveats.Add($script:LowPowerCaveat)
        }
        return [pscustomobject]$result
    }

    $spreadBefore = Get-Spread -Value $beforeValid
    $spreadAfter = Get-Spread -Value @($afterValid)
    $largerSpread = [math]::Max($spreadBefore, $spreadAfter)

    $medianBefore = Get-Median -Value $beforeValid
    $medianAfter = Get-Median -Value @($afterValid)
    $medianDelta = $medianBefore - $medianAfter
    $medianDeltaPct = if ($medianBefore -ne 0) { ($medianDelta / $medianBefore) * 100.0 } else { $null }

    $result.spreadBefore = $spreadBefore
    $result.spreadAfter = $spreadAfter
    $result.largerSpread = $largerSpread
    $result.medianBefore = $medianBefore
    $result.medianAfter = $medianAfter
    $result.medianDeltaSecond = $medianDelta
    $result.medianDeltaPct = $medianDeltaPct

    if ($medianDelta -gt $largerSpread) {
        $result.classification = 'gain'
        $result.reason = "median_delta ($([math]::Round($medianDelta, 2))s) > larger_spread ($([math]::Round($largerSpread, 2))s)."
    }
    elseif ($medianDelta -gt 0) {
        $result.classification = 'inconclusive'
        $result.reason = "0 < median_delta ($([math]::Round($medianDelta, 2))s) <= larger_spread ($([math]::Round($largerSpread, 2))s): a possible improvement indistinguishable from within-arm noise at this N."
    }
    else {
        $result.classification = 'no-gain'
        $result.reason = "median_delta ($([math]::Round($medianDelta, 2))s) <= 0: AFTER is not faster than BEFORE."
    }

    if ($beforeValid.Count -eq 2 -or $afterValid.Count -eq 2) {
        $result.lowPower = $true
        $caveats.Add($script:LowPowerCaveat)
    }

    [pscustomobject]$result
}

function Test-CostPrecheck {
    <#
    .SYNOPSIS
        Harness-level cost precheck (Amendment 2 §11 "Harness precheck"): running sum
        plus the next run's estimate reaching the ceiling aborts remaining runs. This
        is the 150 USD *harness* limit named by the human, never a squad Cost
        Preflight ceiling (a squad ceiling would itself latch pipelining off for the
        AFTER arm, per the Enablement Predicate -- see the run's human decision).
    .PARAMETER RunningTotalUsd
        Sum of actual (or, absent actual figures, estimated) cost for every run
        completed so far, across both arms.
    .PARAMETER NextRunEstimateUsd
        Estimated cost of the run about to start.
    .PARAMETER CeilingUsd
        Harness spend ceiling. Defaults to 150 (the human-settled limit).
    .OUTPUTS
        [pscustomobject] with ShouldAbort (bool) and Reason (string).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double]$RunningTotalUsd,

        [Parameter(Mandatory)]
        [double]$NextRunEstimateUsd,

        [double]$CeilingUsd = 150.0
    )

    $projected = $RunningTotalUsd + $NextRunEstimateUsd
    $abort = $projected -ge $CeilingUsd

    [pscustomobject]@{
        ShouldAbort     = $abort
        ProjectedUsd    = $projected
        RunningTotalUsd = $RunningTotalUsd
        NextEstimateUsd = $NextRunEstimateUsd
        CeilingUsd      = $CeilingUsd
        Reason          = if ($abort) {
            "Running total `$$([math]::Round($RunningTotalUsd, 2)) + next-run estimate `$$([math]::Round($NextRunEstimateUsd, 2)) = `$$([math]::Round($projected, 2)), which reaches the `$$([math]::Round($CeilingUsd, 2)) harness limit. Aborting remaining runs."
        }
        else {
            "Running total `$$([math]::Round($RunningTotalUsd, 2)) + next-run estimate `$$([math]::Round($NextRunEstimateUsd, 2)) = `$$([math]::Round($projected, 2)), under the `$$([math]::Round($CeilingUsd, 2)) harness limit."
        }
    }
}

function Get-NDowngradeDecision {
    <#
    .SYNOPSIS
        Decides whether the design downgrades from the N=3 target to the N=2
        deterministic fallback (Amendment 1 "Cost Estimate and N-Sizing", Cost C /
        Residual "P04-T02 precheck + N=2 trigger").
    .DESCRIPTION
        N=2 triggers automatically when the running sum after 2 runs of an arm, plus
        the next (3rd) run's estimate, would reach the harness ceiling -- this is the
        "largest honest design the per-run evidence actually supports", not a
        re-design after the fact.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double]$RunningTotalUsdAfterTwoRuns,

        [Parameter(Mandatory)]
        [double]$ThirdRunEstimateUsd,

        [double]$CeilingUsd = 150.0
    )

    $precheck = Test-CostPrecheck -RunningTotalUsd $RunningTotalUsdAfterTwoRuns -NextRunEstimateUsd $ThirdRunEstimateUsd -CeilingUsd $CeilingUsd

    [pscustomobject]@{
        DowngradeToN2 = $precheck.ShouldAbort
        TargetN       = if ($precheck.ShouldAbort) { 2 } else { 3 }
        Reason        = if ($precheck.ShouldAbort) {
            "3rd-run precheck would abort ($($precheck.Reason)); downgrading to the N=2 deterministic fallback rather than exceeding the harness limit."
        }
        else {
            '3rd-run precheck has headroom; continuing to the N=3 target.'
        }
    }
}

function Test-PowerCeilingCheck {
    <#
    .SYNOPSIS
        Power/ceiling pre-check run after each arm's first run (Amendment 2 §11).
    .DESCRIPTION
        Interpretation used by this benchmark (documented as a design decision in the
        change record, since the source protocol names the inputs but not the exact
        two-point formula): the detectability ceiling is
        `boundaries * min(scribeRoundTripSeconds, roleRoundTripSeconds)` -- the largest
        time pipelining could plausibly ever save in this scenario. The "observed
        spread" compared against it, this early (only one run per arm exists), is the
        provisional two-point |BEFORE run 1 - AFTER run 1| difference -- the only
        spread-like figure available before a second run in either arm exists. If the
        ceiling cannot exceed even this provisional figure, further spend is unlikely
        to produce a trustworthy signal, so the benchmark stops and asks the human
        before running additional (paid) runs.
    .PARAMETER BoundaryCount
        Number of pipelinable boundaries in the scenario (2, per the fixed design).
    .PARAMETER ScribeRoundTripSeconds
        Observed (or estimated) Scribe hand-off round-trip duration.
    .PARAMETER RoleRoundTripSeconds
        Observed (or estimated) role-dispatch round-trip duration.
    .PARAMETER FirstBeforeElapsedSeconds
        Elapsed seconds of the BEFORE arm's first run.
    .PARAMETER FirstAfterElapsedSeconds
        Elapsed seconds of the AFTER arm's first run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$BoundaryCount,

        [Parameter(Mandatory)]
        [double]$ScribeRoundTripSeconds,

        [Parameter(Mandatory)]
        [double]$RoleRoundTripSeconds,

        [Parameter(Mandatory)]
        [double]$FirstBeforeElapsedSeconds,

        [Parameter(Mandatory)]
        [double]$FirstAfterElapsedSeconds
    )

    $ceilingSeconds = $BoundaryCount * [math]::Min($ScribeRoundTripSeconds, $RoleRoundTripSeconds)
    $observedSpread = [math]::Abs($FirstBeforeElapsedSeconds - $FirstAfterElapsedSeconds)
    $shouldStop = $ceilingSeconds -le $observedSpread

    [pscustomobject]@{
        CeilingSeconds        = $ceilingSeconds
        ObservedSpreadSeconds = $observedSpread
        ShouldStopAndAskHuman = $shouldStop
        Reason                = if ($shouldStop) {
            "Detectability ceiling ($([math]::Round($ceilingSeconds, 2))s = $BoundaryCount x min(scribe, role) round-trip) does not exceed the provisional first-run spread ($([math]::Round($observedSpread, 2))s); the maximum plausible saving cannot be distinguished from the noise already observed at N=1. Stopping before further spend; a human should confirm whether to continue, redesign, or accept an inconclusive result."
        }
        else {
            "Detectability ceiling ($([math]::Round($ceilingSeconds, 2))s) exceeds the provisional first-run spread ($([math]::Round($observedSpread, 2))s); continuing is not yet known to be futile."
        }
    }
}

Export-ModuleMember -Function Get-Median, Get-Spread, Get-BenchmarkClassification, Test-CostPrecheck, Get-NDowngradeDecision, Test-PowerCeilingCheck
