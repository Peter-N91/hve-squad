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

    # A file copied out of a line-numbered read view keeps the viewer's gutter, which reads
    # as correct content to a human and parses as nothing at all to every later turn.
    It 'writes no file carrying a read tool line-number gutter' {
        $script:Model.NumberedFiles -join ', ' | Should -BeNullOrEmpty -Because 'line numbers belong to the viewer, not the file'
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

# The Deliverable Root cell is the only place an operator can steer where output lands.
# A role that falls back to the path convention in its own agent definition makes every
# cell in that column a lie, and the operator's customization silently does nothing.
Describe 'SQ-12 The Deliverable Root is binding' -Skip:(-not $ExpectDispatches) {
    # 'Deliverable: N/A - inline verdict, no review artifact written' declares no path, so
    # the existence check below has nothing to reject and the stage reports complete
    # having produced nothing a later gate can read.
    It 'every dispatch entry names an artifact' {
        $script:Model.ArtifactlessEntries -join '; ' | Should -BeNullOrEmpty -Because 'a stage that wrote no file did not run'
    }

    It 'every declared deliverable exists on disk' {
        $missing = @($script:Model.Deliverables | Where-Object { -not $_.Resolved } | ForEach-Object { "$($_.Source) -> $($_.Path)" })
        $missing -join '; ' | Should -BeNullOrEmpty -Because 'a Deliverable path is verified by listing it, never asserted'
    }

    It 'every declared deliverable sits under its role Deliverable Root' {
        $strayed = @($script:Model.Deliverables | Where-Object { -not $_.UnderRoot } | ForEach-Object { "$($_.Source) -> $($_.Path) not under $($_.Root)" })
        $strayed -join '; ' | Should -BeNullOrEmpty -Because 'the roster root overrides the path convention in the agent own definition'
    }

    # The documented failure is a stage whose artifact is on disk while the coordinator
    # never handed the dispatch over, so it has no history entry, no ledger row, and no
    # activeRoles membership - state and ledger agree with each other and with nothing else.
    It 'no artifact under a Deliverable Root is left unclaimed' {
        $orphans = @($script:Model.OrphanArtifacts | ForEach-Object { Split-Path $_ -Leaf })
        $orphans -join '; ' | Should -BeNullOrEmpty -Because 'an unclaimed artifact is a dispatch nobody recorded'
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

Describe 'CON Per-dispatch blocks resolve to a rate row' -Skip:(-not $ExpectDispatches) {
    # The block carries no rate and no cost, so the whole of its pricing contribution is
    # priced_as: a value that matches no row leaves the ledger unable to price the role.
    It '<Source> priced_as names a row in consumption-rates.md' -ForEach @($model.Blocks | ForEach-Object { @{ Source = $_.Source; Fields = $_.Fields } }) {
        $priced = if ($Fields['priced_as']) { $Fields['priced_as'] } else { $Fields['model'] }
        $script:Model.Rates.Keys | Should -Contain $priced -Because 'only consumption-rates.md holds token rates'
    }

    It '<Source> model_source and basis are documented values' -ForEach @($model.Blocks | ForEach-Object { @{ Source = $_.Source; Fields = $_.Fields } }) {
        $script:Model.ModelSources | Should -Contain $Fields['model_source']
        $script:Model.Bases | Should -Contain $Fields['basis'] -Because 'basis is exactly one value, never a combined one'
    }

    It '<Source> model_tier is the tier of the priced_as row' -ForEach @($model.Blocks | ForEach-Object { @{ Source = $_.Source; Fields = $_.Fields } }) {
        $priced = if ($Fields['priced_as']) { $Fields['priced_as'] } else { $Fields['model'] }
        $tier = $script:Model.Rates[$priced]['tier']
        if (-not $tier) { Set-ItResult -Skipped -Because 'the rate table declares no Tier column' }

        $Fields['model_tier'] | Should -Be $tier
    }

    # A copied block reproduces perfectly from its own fields, so every other check
    # passes and the figure is still fiction.
    It 'no two dispatches are sized from the same numbers' {
        $duplicated = @($script:Model.Blocks |
                Group-Object -Property { @(
                        $_.Fields['internal_turns'], $_.Fields['input_tokens'], $_.Fields['cached_tokens']
                        $_.Fields['cache_write_tokens'], $_.Fields['output_tokens']
                    ) -join '/' } |
                Where-Object { $_.Count -gt 1 } |
                ForEach-Object { $_.Name })

        $duplicated -join '; ' | Should -BeNullOrEmpty -Because 'identical token counts describe one dispatch recorded twice'
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
        foreach ($column in @(
                @{ Index = 1; Field = 'internal_turns' }
                @{ Index = 2; Field = 'input_tokens' }
                @{ Index = 3; Field = 'cached_tokens' }
                @{ Index = 4; Field = 'cache_write_tokens' }
                @{ Index = 5; Field = 'output_tokens' }
            )) {
            $expected = ($script:Model.OrchestrationBlocks | ForEach-Object { $_.Fields[$column.Field] } | Measure-Object -Sum).Sum
            ConvertTo-LedgerNumber $row[$column.Index] | Should -Be $expected -Because "the $($column.Field) column is the sum of the orchestration blocks"
        }
    }

    # The documented failure is a Scribe that rewrites from the turn's payload alone,
    # deleting earlier roles from the ledger while leaving their history intact.
    It 'the run total equals the sum of every recorded block' {
        $total = @($script:Model.UsageAndCost | Where-Object { $_[0] -match 'Total' })
        $total.Count | Should -Be 1 -Because 'the ledger carries a run-total row'

        foreach ($column in @(
                @{ Index = 1; Field = 'internal_turns' }
                @{ Index = 2; Field = 'input_tokens' }
                @{ Index = 3; Field = 'cached_tokens' }
                @{ Index = 4; Field = 'cache_write_tokens' }
                @{ Index = 5; Field = 'output_tokens' }
            )) {
            $expected = ($script:Model.Blocks | ForEach-Object { $_.Fields[$column.Field] } | Measure-Object -Sum).Sum
            ConvertTo-LedgerNumber $total[0][$column.Index] | Should -Be $expected -Because 'a ledger rewritten from one turn silently drops every earlier role'
        }
    }

    # Cost exists in exactly one place now, so this is the only check that recomputes it.
    It 'every row cost derives from its own tokens and its priced_as rates' {
        $priced = @{}
        foreach ($row in $script:Model.Attribution) { $priced[$row[0]] = $row[5] }

        foreach ($row in @($script:Model.UsageAndCost | Where-Object { $_[0] -notmatch 'Total' })) {
            $key = $priced[$row[0]]
            $script:Model.Rates.Keys | Should -Contain $key -Because "the Attribution row for '$($row[0])' must name a rate row"

            $rates = $script:Model.Rates[$key]
            $raw = (
                (ConvertTo-LedgerNumber $row[2]) * $rates['input'] +
                (ConvertTo-LedgerNumber $row[3]) * $rates['cached'] +
                (ConvertTo-LedgerNumber $row[4]) * $rates['cache_write'] +
                (ConvertTo-LedgerNumber $row[5]) * $rates['output']
            ) / 1e6

            $expected = [math]::Round($raw * $script:Model.Calibration, (Get-LedgerDecimal $row[6]))
            [math]::Abs((ConvertTo-LedgerNumber $row[6]) - $expected) | Should -BeLessThan $script:Tolerance -Because "expected $expected for '$($row[0])' from the documented derivation"
            [math]::Abs((ConvertTo-LedgerNumber $row[7]) - ((ConvertTo-LedgerNumber $row[6]) / 0.01)) | Should -BeLessThan 0.01
        }
    }

    # A cost computed silently and written as one number is indistinguishable from a guess,
    # so the four products are written into the file where a reader can check them. Zero rows
    # are left to the assertion that rejects them outright rather than reported twice.
    It 'the ledger shows its arithmetic for every priced row' {
        $derivation = [regex]::Match($script:Model.Ledger, '(?ms)^###\s+Derivation\s*$(?<body>.*?)(?=^#{2,3}\s|\z)')
        $derivation.Success | Should -BeTrue -Because 'a Derivation block under Usage & Cost is what makes the cost rule checkable'

        $shown = $derivation.Groups['body'].Value
        $unshown = @(
            foreach ($row in @($script:Model.UsageAndCost | Where-Object { $_[0] -notmatch 'Total' })) {
                if ((ConvertTo-LedgerNumber $row[6]) -eq 0) { continue }
                if ($shown -notmatch ('(?m)^\s*' + [regex]::Escape($row[0]) + '\s')) { $row[0] }
            }
        )

        $unshown -join '; ' | Should -BeNullOrEmpty -Because 'a priced row with no derivation line asserts a cost nobody can reproduce'
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

    # The total row is computed, never carried. The documented failure drops the one short
    # row belonging to a role dispatched on an earlier turn - which is also the row least
    # likely to be missed by eye, and the cost column alone does not surface it.
    It 'the <Column> total equals the sum of the rows above it' -ForEach @(
        @{ Column = 'Turns'; Index = 1 }
        @{ Column = 'In Tokens'; Index = 2 }
        @{ Column = 'Cached'; Index = 3 }
        @{ Column = 'Cache Wr'; Index = 4 }
        @{ Column = 'Out Tokens'; Index = 5 }
    ) {
        $rows = @($script:Model.UsageAndCost | Where-Object { $_[0] -notmatch 'Total' })
        $total = @($script:Model.UsageAndCost | Where-Object { $_[0] -match 'Total' })[0]

        $expected = ($rows | ForEach-Object { ConvertTo-LedgerNumber $_[$Index] } | Measure-Object -Sum).Sum
        ConvertTo-LedgerNumber $total[$Index] | Should -Be $expected -Because 'a total summed over the rows you happened to be looking at disagrees with the table above it'
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
