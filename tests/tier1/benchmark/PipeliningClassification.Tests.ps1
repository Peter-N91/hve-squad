#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Offline, self-contained Pester coverage for the U5 live pipelining benchmark's pure
# classification and safeguard logic (PipeliningClassification.psm1). No live squad
# root, no model dispatch, no network call -- every case here is arithmetic over
# caller-supplied numbers, which is exactly why it belongs in the -SelfCheck
# container alongside Assertions.Tests.ps1, ModelRouting.Tests.ps1, and
# LedgerCalculator.Tests.ps1 (see Invoke-Tier1Tests.ps1): CI covers the
# classification and void rules without paying for a single benchmark arm.
#
# See .copilot-tracking/squad/members/routing-performance/plans/2026-09-28-scribe-pipelining-plan-amendment-1.md
# ("Benchmark Protocol": Classification Rule, Void Runs, Data sufficiency safeguard)
# and .../plans/2026-09-28-scribe-pipelining-plan-amendment-2.md §11 for the rules
# this file pins.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'PipeliningClassification.psm1') -Force
}

Describe 'Get-Median / Get-Spread' {
    It 'returns the middle value for an odd-length array' {
        Get-Median -Value @(3.0, 1.0, 2.0) | Should -Be 2.0
    }

    It 'averages the two middle values for an even-length array' {
        Get-Median -Value @(10.0, 20.0, 30.0, 40.0) | Should -Be 25.0
    }

    It 'computes max-min as the spread' {
        Get-Spread -Value @(10.0, 40.0, 25.0) | Should -Be 30.0
    }
}

Describe 'Get-BenchmarkClassification: classification rule (Amendment 1)' {
    It 'classifies gain when median_delta exceeds the larger spread' {
        # BEFORE: 100, 105, 110 (spread 10, median 105). AFTER: 60, 63, 66 (spread 6, median 63).
        # median_delta = 42 > larger_spread (10) -> gain.
        $result = Get-BenchmarkClassification -BeforeElapsedSeconds @(100.0, 105.0, 110.0) `
            -AfterElapsedSeconds @(60.0, 63.0, 66.0) -AfterOverlapCount @(2, 2, 2)

        $result.classification | Should -Be 'gain'
        $result.medianDeltaSecond | Should -Be 42.0
        $result.largerSpread | Should -Be 10.0
        $result.afterVoidCount | Should -Be 0
        $result.caveats | Should -Contain 'Ambient session/tool timeout is the only bound on a single run''s duration; this benchmark enforces no separate per-run timeout, so a run that stalls is caught by the host''s own ambient timeout (or the harness-level cost precheck between runs), not by a benchmark-specific clock.'
    }

    It 'classifies inconclusive when 0 < median_delta <= larger_spread' {
        # BEFORE: 100, 120, 140 (spread 40, median 120). AFTER: 95, 100, 105 (spread 10, median 100).
        # median_delta = 20, larger_spread = 40 -> 0 < 20 <= 40 -> inconclusive.
        $result = Get-BenchmarkClassification -BeforeElapsedSeconds @(100.0, 120.0, 140.0) `
            -AfterElapsedSeconds @(95.0, 100.0, 105.0) -AfterOverlapCount @(1, 2, 2)

        $result.classification | Should -Be 'inconclusive'
        $result.medianDeltaSecond | Should -Be 20.0
    }

    It 'classifies no-gain when median_delta is zero or negative' {
        $result = Get-BenchmarkClassification -BeforeElapsedSeconds @(100.0, 100.0, 100.0) `
            -AfterElapsedSeconds @(110.0, 112.0, 108.0) -AfterOverlapCount @(2, 2, 2)

        $result.classification | Should -Be 'no-gain'
        $result.medianDeltaSecond | Should -BeLessOrEqual 0
    }

    It 'reports Δ% relative to the BEFORE median' {
        $result = Get-BenchmarkClassification -BeforeElapsedSeconds @(100.0, 100.0, 100.0) `
            -AfterElapsedSeconds @(50.0, 50.0, 50.0) -AfterOverlapCount @(2, 2, 2)

        $result.medianDeltaPct | Should -Be 50.0
    }
}

Describe 'Get-BenchmarkClassification: AFTER-only void rule (Amendment 2 R10)' {
    It 'excludes a single void AFTER run (0 overlaps) from the median/spread and still classifies' {
        # One AFTER run (index 1) is void; the remaining two AFTER runs still classify.
        $result = Get-BenchmarkClassification -BeforeElapsedSeconds @(100.0, 105.0, 110.0) `
            -AfterElapsedSeconds @(60.0, 999.0, 66.0) -AfterOverlapCount @(2, 0, 2)

        $result.afterVoidCount | Should -Be 1
        $result.afterValidCount | Should -Be 2
        $result.classification | Should -Not -Be $null
        # The voided 999.0 run must not appear in the surviving median/spread.
        $result.medianAfter | Should -Be 63.0
    }

    It 'forces inconclusive when more than 1 AFTER run is void, regardless of the surviving numbers' {
        $result = Get-BenchmarkClassification -BeforeElapsedSeconds @(100.0, 105.0, 110.0) `
            -AfterElapsedSeconds @(1.0, 1.0, 1.0) -AfterOverlapCount @(0, 0, 2)

        $result.classification | Should -Be 'inconclusive'
        $result.reason | Should -Match 'void'
        $result.afterVoidCount | Should -Be 2
    }

    It 'never voids a BEFORE run even though BEFORE overlap counts are not supplied (BEFORE has no overlap concept)' {
        # BEFORE is the sequential baseline: it is expected to show 0 overlaps and is
        # never voided by that fact. The function accepts no BEFORE overlap parameter
        # at all, which is itself the AFTER-only enforcement.
        $result = Get-BenchmarkClassification -BeforeElapsedSeconds @(10.0, 20.0, 30.0) `
            -AfterElapsedSeconds @(5.0, 6.0, 7.0) -AfterOverlapCount @(2, 2, 2)

        $result.beforeValidCount | Should -Be 3
    }
}

Describe 'Get-BenchmarkClassification: data-sufficiency safeguard' {
    It 'forces inconclusive when BEFORE has fewer than 2 valid runs' {
        $result = Get-BenchmarkClassification -BeforeElapsedSeconds @(100.0) `
            -AfterElapsedSeconds @(50.0, 51.0) -AfterOverlapCount @(2, 2)

        $result.classification | Should -Be 'inconclusive'
        $result.reason | Should -Match 'Data-sufficiency safeguard'
    }

    It 'forces inconclusive when AFTER has fewer than 2 valid runs after voiding' {
        $result = Get-BenchmarkClassification -BeforeElapsedSeconds @(100.0, 105.0) `
            -AfterElapsedSeconds @(50.0, 999.0) -AfterOverlapCount @(2, 0)

        $result.classification | Should -Be 'inconclusive'
        $result.afterValidCount | Should -Be 1
    }

    It 'flags low statistical power (CH-N9 caveat) when the N=2 fallback is in play' {
        $result = Get-BenchmarkClassification -BeforeElapsedSeconds @(100.0, 50.0) `
            -AfterElapsedSeconds @(60.0, 30.0) -AfterOverlapCount @(2, 2)

        $result.lowPower | Should -BeTrue
        ($result.caveats -join ' ') | Should -Match 'Low statistical power \(N=2\)'
    }

    It 'does not flag low statistical power at the N=3 target' {
        $result = Get-BenchmarkClassification -BeforeElapsedSeconds @(100.0, 105.0, 110.0) `
            -AfterElapsedSeconds @(60.0, 63.0, 66.0) -AfterOverlapCount @(2, 2, 2)

        $result.lowPower | Should -BeFalse
        ($result.caveats -join ' ') | Should -Not -Match 'Low statistical power'
    }
}

Describe 'Test-CostPrecheck: harness-level 150 USD limit (Amendment 2 §11)' {
    It 'does not abort while running total plus next estimate stays under the ceiling' {
        $precheck = Test-CostPrecheck -RunningTotalUsd 40.0 -NextRunEstimateUsd 20.0 -CeilingUsd 150.0
        $precheck.ShouldAbort | Should -BeFalse
    }

    It 'aborts once running total plus next estimate reaches the ceiling' {
        $precheck = Test-CostPrecheck -RunningTotalUsd 130.0 -NextRunEstimateUsd 20.0 -CeilingUsd 150.0
        $precheck.ShouldAbort | Should -BeTrue
        $precheck.ProjectedUsd | Should -Be 150.0
    }

    It 'defaults the ceiling to 150 USD' {
        $precheck = Test-CostPrecheck -RunningTotalUsd 149.0 -NextRunEstimateUsd 5.0
        $precheck.CeilingUsd | Should -Be 150.0
        $precheck.ShouldAbort | Should -BeTrue
    }
}

Describe 'Get-NDowngradeDecision: N=3 target, N=2 deterministic fallback (Cost C)' {
    It 'stays at N=3 when the 3rd-run precheck has headroom' {
        $decision = Get-NDowngradeDecision -RunningTotalUsdAfterTwoRuns 40.0 -ThirdRunEstimateUsd 20.0 -CeilingUsd 150.0
        $decision.DowngradeToN2 | Should -BeFalse
        $decision.TargetN | Should -Be 3
    }

    It 'downgrades to N=2 when the 3rd-run precheck would abort' {
        $decision = Get-NDowngradeDecision -RunningTotalUsdAfterTwoRuns 135.0 -ThirdRunEstimateUsd 20.0 -CeilingUsd 150.0
        $decision.DowngradeToN2 | Should -BeTrue
        $decision.TargetN | Should -Be 2
    }
}

Describe 'Test-PowerCeilingCheck: power/ceiling pre-check after each arm''s first run' {
    It 'does not ask the human when the detectability ceiling exceeds the provisional spread' {
        $check = Test-PowerCeilingCheck -BoundaryCount 2 -ScribeRoundTripSeconds 30.0 -RoleRoundTripSeconds 40.0 `
            -FirstBeforeElapsedSeconds 200.0 -FirstAfterElapsedSeconds 190.0

        # ceiling = 2 * min(30, 40) = 60; observed spread = |200-190| = 10; 60 > 10 -> continue.
        $check.CeilingSeconds | Should -Be 60.0
        $check.ShouldStopAndAskHuman | Should -BeFalse
    }

    It 'asks the human when the detectability ceiling does not exceed the provisional spread' {
        $check = Test-PowerCeilingCheck -BoundaryCount 2 -ScribeRoundTripSeconds 5.0 -RoleRoundTripSeconds 8.0 `
            -FirstBeforeElapsedSeconds 200.0 -FirstAfterElapsedSeconds 100.0

        # ceiling = 2 * min(5, 8) = 10; observed spread = |200-100| = 100; 10 <= 100 -> stop and ask.
        $check.CeilingSeconds | Should -Be 10.0
        $check.ShouldStopAndAskHuman | Should -BeTrue
    }
}
