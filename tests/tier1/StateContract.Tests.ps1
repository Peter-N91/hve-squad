#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# False positive: Pester evaluates BeforeDiscovery in the discovery scope and the It
# blocks that consume $model through -ForEach in the run scope. PSScriptAnalyzer
# resolves neither, so it reports the assignment as unused.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'model',
    Justification = 'Consumed by It -ForEach at discovery scope; PSScriptAnalyzer cannot resolve Pester scoping.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SquadRoot',
    Justification = 'Read inside BeforeDiscovery and BeforeAll, which PSScriptAnalyzer treats as unrelated scopes.')]
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

    # Every ledger figure is an estimate with no per-dispatch telemetry behind it, so the
    # arithmetic checks compare orders of magnitude rather than digits. The corruption
    # worth failing a run over is a factor-of-ten slip from dividing by 1e6 twice; a few
    # percent of drift on a number that was estimated in the first place is not. Structure
    # is still strict, because a missing row loses a role rather than mis-stating one.
    $script:LedgerBand = 3.0

    function Test-LedgerFigure {
        param([double]$Actual, [double]$Expected)

        if ([math]::Abs($Expected) -lt $script:Tolerance) { return [math]::Abs($Actual) -lt $script:Tolerance }
        if ([math]::Abs($Actual) -lt $script:Tolerance) { return $false }

        $ratio = $Actual / $Expected
        return ($ratio -le $script:LedgerBand -and $ratio -ge (1 / $script:LedgerBand))
    }
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

    # A promotion that created its destinations from inside the tracking directory rather
    # than the project root leaves .copilot-tracking/.copilot-tracking/ behind it.
    It 'writes no tracking directory inside the tracking directory' {
        $script:Model.NestedTracking -join ', ' | Should -BeNullOrEmpty -Because 'a state path is written from the project root, so it can never contain .copilot-tracking twice'
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
    # The floor requires the Scribe to record its own orchestration block on every turn it
    # writes state, Init included, so its file is the one history file Init legitimately
    # produces. What this rejects is an agent file seeded before that agent ran.
    It 'creates no agent history file before the first dispatch' {
        $premature = @($script:Model.HistoryNames | Where-Object { $_ -ne 'Squad Scribe' })
        $premature -join ', ' | Should -BeNullOrEmpty -Because 'a history file that predates its dispatch is indistinguishable from one that recorded it'
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

Describe 'CON Per-dispatch blocks resolve to a rate row' -Tag 'Consumption' -Skip:(-not $ExpectDispatches) {
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

Describe 'CON The ledger is re-derivable from history' -Tag 'Consumption' -Skip:(-not $ExpectDispatches) {
    It 'splits into Attribution and Usage & Cost, never one wide table' {
        $script:Model.Ledger | Should -Match '(?m)^##\s+Attribution\s*$'
        $script:Model.Ledger | Should -Match '(?m)^##\s+Usage & Cost\s*$'
    }

    It 'carries an orchestration row in both tables' {
        @($script:Model.Attribution | Where-Object { (Get-LedgerRoleKey $_[0]) -eq 'orchestration' }).Count | Should -BeGreaterThan 0
        @($script:Model.UsageAndCost | Where-Object { (Get-LedgerRoleKey $_[0]) -eq 'orchestration' }).Count | Should -BeGreaterThan 0
    }

    It 'records orchestration overhead in history' {
        $script:Model.OrchestrationBlocks.Count | Should -BeGreaterThan 0 -Because 'without it the ledger omits the cost of running the squad itself'
    }

    # A role that ran and has no row is a stage missing from every figure derived from the
    # ledger. That is a loss, not a mis-statement, so it stays exact while the arithmetic
    # around it does not. Blocks are keyed by agent and rows by role, so the check counts
    # rather than joins.
    It 'carries a row for every role that was dispatched' {
        $dispatched = @($script:Model.DispatchBlocks | ForEach-Object { $_.Source } | Sort-Object -Unique).Count
        $rows = @($script:Model.UsageAndCost |
                Where-Object { $_[0] -notmatch 'Total' } |
                Where-Object { (Get-LedgerRoleKey $_[0]) -ne 'orchestration' } |
                ForEach-Object { Get-LedgerRoleKey $_[0] } |
                Sort-Object -Unique).Count

        $rows | Should -BeGreaterOrEqual $dispatched -Because 'a dispatched role with no row is absent from every total the ledger feeds'
    }

    It 'the orchestration row is within an order of magnitude of its blocks' {
        $rows = @($script:Model.UsageAndCost | Where-Object { (Get-LedgerRoleKey $_[0]) -eq 'orchestration' })
        $findings = @()

        foreach ($column in @(
                @{ Name = 'Turns'; Index = 1; Field = 'internal_turns' }
                @{ Name = 'In Tokens'; Index = 2; Field = 'input_tokens' }
                @{ Name = 'Cached'; Index = 3; Field = 'cached_tokens' }
                @{ Name = 'Cache Wr'; Index = 4; Field = 'cache_write_tokens' }
                @{ Name = 'Out Tokens'; Index = 5; Field = 'output_tokens' }
            )) {
            $expected = ($script:Model.OrchestrationBlocks | ForEach-Object { $_.Fields[$column.Field] } | Measure-Object -Sum).Sum
            $actual = ($rows | ForEach-Object { ConvertTo-LedgerNumber $_[$column.Index] } | Measure-Object -Sum).Sum
            if (-not (Test-LedgerFigure -Actual $actual -Expected $expected)) {
                $findings += "$($column.Name) says $actual against blocks summing to $expected"
            }
        }

        $findings -join '; ' | Should -BeNullOrEmpty -Because 'the orchestration row is derived from the orchestration blocks'
    }

    # The documented failure is a Scribe that rewrites from the turn's payload alone,
    # deleting earlier roles from the ledger while leaving their history intact.
    It 'the run total is within an order of magnitude of every recorded block' {
        $total = @($script:Model.UsageAndCost | Where-Object { $_[0] -match 'Total' })
        $total.Count | Should -Be 1 -Because 'the ledger carries a run-total row'

        $findings = @()
        foreach ($column in @(
                @{ Name = 'Turns'; Index = 1; Field = 'internal_turns' }
                @{ Name = 'In Tokens'; Index = 2; Field = 'input_tokens' }
                @{ Name = 'Cached'; Index = 3; Field = 'cached_tokens' }
                @{ Name = 'Cache Wr'; Index = 4; Field = 'cache_write_tokens' }
                @{ Name = 'Out Tokens'; Index = 5; Field = 'output_tokens' }
            )) {
            $expected = ($script:Model.Blocks | ForEach-Object { $_.Fields[$column.Field] } | Measure-Object -Sum).Sum
            $actual = ConvertTo-LedgerNumber $total[0][$column.Index]
            if (-not (Test-LedgerFigure -Actual $actual -Expected $expected)) {
                $findings += "$($column.Name) says $actual against blocks summing to $expected"
            }
        }

        $findings -join '; ' | Should -BeNullOrEmpty -Because 'a ledger rewritten from one turn silently drops every earlier role'
    }

    # Cost exists in exactly one place now, so this is the only check that recomputes it.
    # Every row is collected before asserting: a Should inside the loop aborts on the first
    # bad row, which is how a ledger overstating eight rows reported one.
    It 'no row cost is out by an order of magnitude' {
        $priced = @{}
        foreach ($row in $script:Model.Attribution) { $priced[(Get-LedgerRoleKey $row[0])] = $row[5] }

        $findings = @()

        foreach ($row in @($script:Model.UsageAndCost | Where-Object { $_[0] -notmatch 'Total' })) {
            $key = $priced[(Get-LedgerRoleKey $row[0])]
            if (-not $key -or -not $script:Model.Rates.ContainsKey($key)) {
                $findings += "$($row[0]) joins no Attribution row naming a rate row"
                continue
            }

            $rates = $script:Model.Rates[$key]
            $raw = (
                (ConvertTo-LedgerNumber $row[2]) * $rates['input'] +
                (ConvertTo-LedgerNumber $row[3]) * $rates['cached'] +
                (ConvertTo-LedgerNumber $row[4]) * $rates['cache_write'] +
                (ConvertTo-LedgerNumber $row[5]) * $rates['output']
            ) / 1e6

            $expected = $raw * $script:Model.Calibration
            $actual = ConvertTo-LedgerNumber $row[6]
            if (-not (Test-LedgerFigure -Actual $actual -Expected $expected)) {
                $findings += "$($row[0]) says $actual, derives to $([math]::Round($expected, 4))"
            }
            elseif (-not (Test-LedgerFigure -Actual (ConvertTo-LedgerNumber $row[7]) -Expected ($actual / 0.01))) {
                $findings += "$($row[0]) credits do not follow from its cost"
            }
        }

        $findings -join '; ' | Should -BeNullOrEmpty -Because 'a factor-of-ten slip survives every other check because the row is otherwise well formed'
    }

    # A cost computed silently and written as one number is indistinguishable from a guess,
    # so the products are written into the file where a reader can check them. The check is
    # on the working being present, not on how each line is labelled.
    It 'the ledger shows its arithmetic' {
        $derivation = [regex]::Match($script:Model.Ledger, '(?ms)^###\s+Derivation\s*$(?<body>.*?)(?=^#{2,3}\s|\z)')
        $derivation.Success | Should -BeTrue -Because 'a Derivation block under Usage & Cost is what makes a ledger figure checkable by eye'

        $priced = @($script:Model.UsageAndCost |
                Where-Object { $_[0] -notmatch 'Total' } |
                Where-Object { (ConvertTo-LedgerNumber $_[6]) -ne 0 })
        $lines = @($derivation.Groups['body'].Value -split '\r?\n' | Where-Object { $_ -match '\d\s*[x×]\s*\d' })

        $lines.Count | Should -BeGreaterOrEqual $priced.Count -Because 'every priced row shows the products behind its cost'
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

    # The sharper form of the check above: an invented row carries a plausible cost, so
    # the zero test cannot see it. The row set is a function of history/, and a run that
    # priced eleven roles over a history directory holding two files recorded nine
    # dispatches that never happened.
    It 'every ledger row has a history file behind it' {
        $unbacked = @(
            foreach ($row in $script:Model.UsageAndCost) {
                $role = Get-LedgerRoleKey $row[0]
                if (-not $role -or $role -match 'Total' -or $role -eq 'orchestration') { continue }

                $agents = @($script:Model.RoleAgents[$role])
                if (-not $agents) { $agents = @($role) }
                if (@($agents | Where-Object { $_ -in $script:Model.HistoryNames })) { continue }

                $role
            }
        )

        $unbacked -join ', ' | Should -BeNullOrEmpty -Because 'the ledger is derived from history/, so a row whose agent left no file prices a dispatch that did not happen'
    }

    It 'state.json run totals track the ledger total' {
        $total = @($script:Model.UsageAndCost | Where-Object { $_[0] -match 'Total' })[0]
        $ledger = ConvertTo-LedgerNumber $total[6]
        Test-LedgerFigure -Actual $script:Model.State['currentRun']['estCostUsd'] -Expected $ledger |
            Should -BeTrue -Because "state.json reports $($script:Model.State['currentRun']['estCostUsd']) against a ledger total of $ledger"
    }

    # The total row is computed, never carried. The documented failure drops the one short
    # row belonging to a role dispatched on an earlier turn - which is also the row least
    # likely to be missed by eye, and the cost column alone does not surface it.
    It 'the <Column> total tracks the rows above it' -ForEach @(
        @{ Column = 'Turns'; Index = 1 }
        @{ Column = 'In Tokens'; Index = 2 }
        @{ Column = 'Cached'; Index = 3 }
        @{ Column = 'Cache Wr'; Index = 4 }
        @{ Column = 'Out Tokens'; Index = 5 }
    ) {
        $rows = @($script:Model.UsageAndCost | Where-Object { $_[0] -notmatch 'Total' })
        $total = @($script:Model.UsageAndCost | Where-Object { $_[0] -match 'Total' })[0]

        $expected = ($rows | ForEach-Object { ConvertTo-LedgerNumber $_[$Index] } | Measure-Object -Sum).Sum
        $actual = ConvertTo-LedgerNumber $total[$Index]
        Test-LedgerFigure -Actual $actual -Expected $expected |
            Should -BeTrue -Because "the $Column total says $actual against rows summing to $expected"
    }

    # The comparison is the figure an operator actually reads, so it is the one part of the
    # ledger required to be complete rather than merely close.
    It 'states what the run cost, what the manual baseline would cost, and the saving' {
        $comparison = [regex]::Match($script:Model.Ledger, '(?ms)^##\s+Cost Comparison.*?(?=^##\s|\z)')
        $comparison.Success | Should -BeTrue -Because 'the ledger carries a Cost Comparison section'

        $text = $comparison.Value
        @($text | Select-String -Pattern '\$\s*[\d,]+\.?\d*' -AllMatches).Matches.Count |
            Should -BeGreaterOrEqual 2 -Because 'the comparison names both the squad cost and the manual baseline it is measured against'
        $text | Should -Match '\d+\s*%' -Because 'a comparison with no percentage leaves the reader to do the division'
    }
}

Describe 'CON The rates file passes its shape check' -Tag 'Consumption' {
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

    # The spec's promise is about the ledger: until observations reach 1 the factor stays
    # 1.00 and the ledger says so. The rates file's own shape is the check above this one.
    It 'an unreconciled run stays at 1.00 and says it is uncalibrated' -Skip:($model.Observations -gt 0) {
        $script:Model.Calibration | Should -Be 1.0
        if ($script:Model.Ledger) {
            $script:Model.Ledger | Should -Match '(?i)uncalibrated|never reconciled|no reconciled runs|\(0 reconciled run'
        }
    }
}
