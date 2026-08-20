#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

param(
    [Parameter(Mandatory)]
    [string]$SquadRoot,

    # A squad that has only been initialized has no dispatches yet, so the turn and
    # consumption cases have nothing to assert on.
    [bool]$ExpectDispatches = $true
)

BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot 'SquadState.psm1') -Force
    $model = Get-SquadStateModel -SquadRoot $SquadRoot
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadState.psm1') -Force
    $script:Model = Get-SquadStateModel -SquadRoot $SquadRoot

    # Display rounding in the ledger is expected; drift is not. Each figure is compared
    # against the sum rounded to the precision that figure was printed at, rather than
    # against a tolerance wide enough to hide a dropped role.
    $script:Tolerance = 0.001
}

Describe 'SQ-01 Init seeds the eager state files' {
    It 'the squad root exists' {
        $script:Model.Exists | Should -BeTrue
    }

    It 'seeds <Name>' -ForEach $model.EagerFiles {
        $Present | Should -BeTrue -Because 'Init seeds this file eagerly'
    }

    It 'creates the history directory' {
        $script:Model.HasHistoryDir | Should -BeTrue
    }
}

Describe 'SQ-03 state.json carries the documented shape' {
    It 'parses' {
        $script:Model.State | Should -Not -BeNullOrEmpty -Because 'unparseable state is indistinguishable from no state'
    }

    It 'declares <_>' -ForEach @('schemaVersion', 'updated', 'turn', 'mode', 'activeRoles', 'openEscalations', 'currentRun', 'notify') {
        $script:Model.State.Keys | Should -Contain $_
    }

    It 'currentRun declares <_>' -ForEach @('sessionModel', 'modelOverrides', 'estCostUsd', 'estCreditsTotal') {
        $script:Model.State['currentRun'].Keys | Should -Contain $_
    }

    It 'notify declares <_>' -ForEach @('approvalChannel', 'enabled', 'email', 'github') {
        $script:Model.State['notify'].Keys | Should -Contain $_
    }

    # An invented key is not harmless: this file is read by machine, so a run that parks
    # per-turn data here produces a file that looks informative and answers nothing.
    It 'declares no key outside the documented set' {
        $documented = @('schemaVersion', 'updated', 'turn', 'mode', 'activeRoles', 'openEscalations', 'currentRun', 'notify', 'trigger')
        $extra = @($script:Model.State.Keys | Where-Object { $_ -notin $documented })
        $extra -join ', ' | Should -BeNullOrEmpty -Because 'the state.json key set is closed apart from the optional Watch Mode trigger'
    }

    It 'currentRun declares no key outside the documented set' {
        $documented = @('sessionModel', 'modelOverrides', 'estCostUsd', 'estCreditsTotal')
        $extra = @($script:Model.State['currentRun'].Keys | Where-Object { $_ -notin $documented })
        $extra -join ', ' | Should -BeNullOrEmpty -Because 'currentRun is a running total, not a scratchpad for per-turn figures'
    }

    It 'mode is a documented value' {
        $script:Model.Modes | Should -Contain $script:Model.State['mode']
    }

    It 'approvalChannel is a documented value' {
        $script:Model.ApprovalChannels | Should -Contain $script:Model.State['notify']['approvalChannel']
    }
}

Describe 'SQ-05 The roster carries its documented columns' {
    It 'has a Members section' {
        $script:Model.Team | Should -Match '(?m)^##\s+Members\s*$'
    }

    It 'declares column <_>' -ForEach @('Role', 'Member Name', 'Agent Name \(Primary\)', 'Alternate Agents', 'Selection Cue', 'Invocation', 'Model Tier', 'Deliverable Root') {
        $script:Model.Team | Should -Match $_
    }
}

Describe 'SQ-07 The routing table carries its documented columns' {
    It 'declares column <_>' -ForEach @('Pattern / Keyword', 'Role\(s\)', 'Autonomy Tier', 'Parallel-Eligible') {
        $script:Model.Routing | Should -Match $_
    }

    It 'every autonomy tier is a documented value' {
        $rows = @($script:Model.Routing -split '\r?\n' | Where-Object { $_ -match '^\s*\|' -and $_ -notmatch '^\s*\|[\s\-:|]+\|\s*$' })
        $tiers = @(
            foreach ($row in $rows) {
                $cells = @(($row.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim() })
                if ($cells.Count -ge 3 -and $cells[2] -notmatch '^(Autonomy Tier|-+)$') { $cells[2] }
            }
        )
        $tiers | Should -Not -BeNullOrEmpty
        foreach ($tier in $tiers) {
            $tier | Should -BeIn @('auto', 'confirm', 'escalate', 'auto-validated')
        }
    }
}

Describe 'SQ-10 Dispatch history is the proof a stage ran' -Skip:(-not $ExpectDispatches) {
    It 'at least one agent history file exists' {
        $script:Model.HistoryFiles.Count | Should -BeGreaterThan 0 -Because 'no history entry means no stage happened'
    }

    It '<Name> carries its agent heading' -ForEach @($model.HistoryFiles | ForEach-Object { @{ Name = $_.Name; File = $_.FullName } }) {
        Get-Content -LiteralPath $File -Raw | Should -Match '(?m)^#\s+History:'
    }

    # The file name is how a later turn matches an entry back to its roster row, so a
    # slugified or role-id name reads as a missing entry and the rewrite drops the agent.
    It '<Name> is named for a roster agent' -ForEach @($model.HistoryFiles |
            Where-Object { $_.BaseName -notmatch '^(autonomous-loop|autopilot-run)-' } |
            ForEach-Object { @{ Name = $_.Name; Agent = $_.BaseName } }) {
        $script:Model.RosterAgents | Should -Contain $Agent -Because 'the roster is what makes a history file name resolvable'
    }

    # SQ-14: the Scribe writes the history append and its block together, so a file with
    # entries but no block is an incomplete dispatch record.
    It '<Name> carries a consumption block' -ForEach @($model.HistoryFiles | ForEach-Object { @{ Name = $_.Name } }) {
        $blocks = @($script:Model.Blocks | Where-Object { $_.Source -eq $Name })
        $blocks.Count | Should -BeGreaterThan 0 -Because 'a history entry without its consumption block is an incomplete dispatch record'
    }
}

# A history file is the proof a dispatch happened, so seeding one for every roster member
# at Init destroys the signal every later turn and the ledger rewrite read it for.
Describe 'SQ-09 Init leaves history empty' -Skip:$ExpectDispatches {
    It 'creates no history file before the first dispatch' {
        $script:Model.HistoryNames -join ', ' | Should -BeNullOrEmpty -Because 'a history file that predates its dispatch is indistinguishable from one that recorded it'
    }
}

Describe 'SQ-11 Consumption blocks carry the contractual shape' -Skip:(-not $ExpectDispatches) {
    It '<Source> block parses as JSON' -ForEach @($model.Blocks | ForEach-Object { @{ Source = $_.Source; ParseError = $_.ParseError } }) {
        $ParseError | Should -BeNullOrEmpty -Because 'the ledger rewrite reparses these blocks and can only re-derive what it can parse'
    }

    It '<Source> block uses the contractual field order' -ForEach @($model.Blocks | ForEach-Object { @{ Source = $_.Source; Order = $_.Order } }) {
        ($Order -join ',') | Should -Be ($script:Model.ConsumptionFields -join ',')
    }

    # SQ-13: '~8,400 (estimated)' is unparseable and drops that dispatch out of every
    # later aggregate, so the shape is asserted rather than only the value.
    It '<Source> block uses bare numbers' -ForEach @($model.Blocks | ForEach-Object { @{ Source = $_.Source; NonNumeric = $_.NonNumeric } }) {
        $NonNumeric | Should -BeNullOrEmpty -Because 'a thousands separator, a tilde, or a unit makes the field unparseable'
    }
}

Describe 'CON Per-dispatch arithmetic is derivable' -Skip:(-not $ExpectDispatches) {
    It '<Source> est_cost_usd matches tokens times rates' -ForEach @($model.Blocks | ForEach-Object { @{ Source = $_.Source; Fields = $_.Fields } }) {
        $raw = (
            $Fields['input_tokens'] * $Fields['input_rate'] +
            $Fields['cached_tokens'] * $Fields['cached_rate'] +
            $Fields['cache_write_tokens'] * $Fields['cache_write_rate'] +
            $Fields['output_tokens'] * $Fields['output_rate']
        ) / 1e6

        $expected = $raw * $script:Model.Calibration
        [math]::Abs($Fields['est_cost_usd'] - $expected) | Should -BeLessThan $script:Tolerance -Because "expected $expected from the documented derivation"
    }

    It '<Source> est_credits is est_cost_usd over 0.01' -ForEach @($model.Blocks | ForEach-Object { @{ Source = $_.Source; Fields = $_.Fields } }) {
        [math]::Abs($Fields['est_credits'] - ($Fields['est_cost_usd'] / 0.01)) | Should -BeLessThan 0.01
    }

    It '<Source> rates match consumption-rates.md' -ForEach @($model.Blocks | ForEach-Object { @{ Source = $_.Source; Fields = $_.Fields } }) {
        $priced = if ($Fields['priced_as']) { $Fields['priced_as'] } else { $Fields['model'] }
        $script:Model.Rates.Keys | Should -Contain $priced -Because 'only consumption-rates.md holds token rates'

        $row = $script:Model.Rates[$priced]
        $Fields['input_rate'] | Should -Be $row['input']
        $Fields['cached_rate'] | Should -Be $row['cached']
        $Fields['cache_write_rate'] | Should -Be $row['cache_write']
        $Fields['output_rate'] | Should -Be $row['output']
    }

    It '<Source> model_source and basis are documented values' -ForEach @($model.Blocks | ForEach-Object { @{ Source = $_.Source; Fields = $_.Fields } }) {
        $script:Model.ModelSources | Should -Contain $Fields['model_source']
        $script:Model.Bases | Should -Contain $Fields['basis'] -Because 'basis is exactly one value, never a combined one'
    }
}

Describe 'CON The ledger is re-derivable from history' -Skip:(-not $ExpectDispatches) {
    It 'splits into Attribution and Usage & Cost, never one wide table' {
        $script:Model.Ledger | Should -Match '(?m)^##\s+Attribution\s*$'
        $script:Model.Ledger | Should -Match '(?m)^##\s+Usage & Cost\s*$'
    }

    It 'carries an orchestration row in both tables' {
        @($script:Model.Attribution | Where-Object { $_[0] -eq 'orchestration' }).Count | Should -Be 1
        @($script:Model.UsageAndCost | Where-Object { $_[0] -eq 'orchestration' }).Count | Should -Be 1
    }

    It 'records orchestration overhead in history' {
        $script:Model.OrchestrationBlocks.Count | Should -BeGreaterThan 0 -Because 'without it the ledger omits the cost of running the squad itself'
    }

    It 'the orchestration row equals the sum of every orchestration block' {
        $row = @($script:Model.UsageAndCost | Where-Object { $_[0] -eq 'orchestration' })[0]
        $expected = ($script:Model.OrchestrationBlocks | ForEach-Object { $_.Fields['est_cost_usd'] } | Measure-Object -Sum).Sum
        [math]::Abs((ConvertTo-LedgerNumber $row[6]) - [math]::Round($expected, (Get-LedgerDecimal $row[6]))) | Should -BeLessThan $script:Tolerance
    }

    # The documented failure is a Scribe that rewrites from the turn's payload alone,
    # deleting earlier roles from the ledger while leaving their history intact.
    It 'the run total equals the sum of every recorded block' {
        $total = @($script:Model.UsageAndCost | Where-Object { $_[0] -match 'Total' })
        $total.Count | Should -Be 1 -Because 'the ledger carries a run-total row'

        $expected = ($script:Model.Blocks | ForEach-Object { $_.Fields['est_cost_usd'] } | Measure-Object -Sum).Sum
        [math]::Abs((ConvertTo-LedgerNumber $total[0][6]) - [math]::Round($expected, (Get-LedgerDecimal $total[0][6]))) | Should -BeLessThan $script:Tolerance -Because 'a ledger rewritten from one turn silently drops every earlier role'
    }

    It 'the ledger is not left at its seed while history shows dispatches' {
        $total = @($script:Model.UsageAndCost | Where-Object { $_[0] -match 'Total' })[0]
        (ConvertTo-LedgerNumber $total[6]) | Should -BeGreaterThan 0
    }

    # A roster seeded as zero rows makes a ledger that never advanced look populated, and
    # buries the one real row among eleven that only restate the roster.
    It 'carries no row for a role that was never dispatched' {
        $idle = @($script:Model.UsageAndCost |
                Where-Object { $_[0] -notmatch 'Total' } |
                Where-Object { (ConvertTo-LedgerNumber $_[6]) -eq 0 } |
                ForEach-Object { $_[0] })

        $idle -join ', ' | Should -BeNullOrEmpty -Because 'a role with no consumption block has no row, not a zero row'
    }

    It 'state.json run totals match the ledger total' {
        $total = @($script:Model.UsageAndCost | Where-Object { $_[0] -match 'Total' })[0]
        $ledger = ConvertTo-LedgerNumber $total[6]
        [math]::Abs([math]::Round($script:Model.State['currentRun']['estCostUsd'], (Get-LedgerDecimal $total[6])) - $ledger) | Should -BeLessThan $script:Tolerance
    }
}

Describe 'CON The rates file passes its shape check' {
    It 'declares column <_>' -ForEach @('Input', 'Cached', 'Cache write', 'Output') {
        $script:Model.RatesContent | Should -Match $_
    }

    # A rate table the contract cannot read reports every block's rates as unknown, which
    # reads as a squad failure when it is the reader that is broken.
    It 'the per-model rate table is machine-readable' {
        $script:Model.Rates.Keys.Count | Should -BeGreaterThan 0 -Because 'every rate assertion is vacuous against a table that did not parse'
    }

    It 'carries the tier fallback table' {
        $script:Model.RatesContent | Should -Match 'Tier fallback'
    }

    It 'carries the estimator and the calibration block' {
        $script:Model.RatesContent | Should -Match 'estimator'
        $script:Model.RatesContent | Should -Match 'calibration_factor'
    }

    It 'the calibration factor is within its clamp' {
        $script:Model.Calibration | Should -BeGreaterOrEqual 0.25
        $script:Model.Calibration | Should -BeLessOrEqual 10.0
    }

    It 'an unreconciled run stays at 1.00 and says it is uncalibrated' -Skip:($model.Observations -gt 0) {
        $script:Model.Calibration | Should -Be 1.0
        $script:Model.RatesContent | Should -Match '(?i)uncalibrated'
    }
}
