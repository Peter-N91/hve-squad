#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Mutation controls: each case breaks exactly one rule and requires the contract to
# catch it. This is the evidence that the contract is worth running - a suite that
# cannot fail reports success on a broken tree, which is worse than no suite.
#
# Each mutation runs the contract in a child process, because Pester does not nest.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadFixture.psm1') -Force

    $script:Runner = Join-Path $PSScriptRoot 'Invoke-Tier1Tests.ps1'
    $script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) "hve-squad-tier1-$([guid]::NewGuid().ToString('N').Substring(0, 8))"

    function New-Fixture {
        param([string]$Name)

        $path = Join-Path $script:Scratch $Name
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        New-SquadStateFixture -Path $path
    }

    function Test-Contract {
        param([string]$Root, [switch]$InitOnly)

        $arguments = @('-NoProfile', '-File', $script:Runner, '-SquadRoot', $Root, '-Output', 'None')
        if ($InitOnly) { $arguments += '-InitOnly' }

        & pwsh @arguments *>$null
        [pscustomobject]@{ Passed = $LASTEXITCODE -eq 0 }
    }

    function Edit-Fixture {
        param([string]$Path, [string]$Pattern, [string]$Replacement)

        $content = Get-Content -LiteralPath $Path -Raw
        $updated = $content -replace $Pattern, $Replacement
        if ($updated -eq $content) { throw "Mutation did not change $Path - the pattern '$Pattern' no longer matches the fixture." }
        Set-Content -LiteralPath $Path -Value $updated -Encoding utf8NoBOM -NoNewline

        # A plain function collects surplus positional arguments into $args rather than
        # failing, so an unparenthesised '-Replacement a + b' silently binds only 'a'.
        if ($args.Count -gt 0) { throw "Edit-Fixture received $($args.Count) unbound argument(s); parenthesise the concatenated replacement." }
    }
}

AfterAll {
    if ($script:Scratch -and (Test-Path -LiteralPath $script:Scratch)) {
        Remove-Item -LiteralPath $script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'The contract passes on a schema-correct tree' {
    It 'passes unmutated' {
        $root = New-Fixture 'baseline'
        (Test-Contract $root).Passed | Should -BeTrue -Because 'a contract that cannot pass on a correct tree only reports noise'
    }

    It 'passes an initialized tree that has not dispatched yet' {
        $root = New-Fixture 'init-only'
        Get-ChildItem -LiteralPath (Join-Path $root 'history') -Filter '*.md' -File | Remove-Item -Force
        (Test-Contract -Root $root -InitOnly).Passed | Should -BeTrue -Because 'Init seeds the history directory and nothing inside it'
    }
}

Describe 'The contract catches a broken tree' {
    It 'catches a missing eager state file' {
        $root = New-Fixture 'missing-ledger'
        Remove-Item -LiteralPath (Join-Path $root 'consumption.md') -Force
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches a history entry with no consumption block' {
        $root = New-Fixture 'no-block'
        $path = Join-Path $root 'history/Squad Researcher.md'
        Set-Content -LiteralPath $path -Encoding utf8NoBOM -Value "# History: Squad Researcher`n`n## 2026-08-19T10:00:03Z Investigate`n`n* Turn: 1`n"
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a history append and its block are inseparable'
    }

    It 'catches a reordered consumption block' {
        $root = New-Fixture 'reordered'
        $path = Join-Path $root 'history/Squad Researcher.md'
        Edit-Fixture -Path $path `
            -Pattern '(?s)"model_source": "dispatch-reported",\s*\r?\n\s*"priced_as": "",' `
            -Replacement ('"priced_as": "",' + "`n  " + '"model_source": "dispatch-reported",')
        (Test-Contract $root).Passed | Should -BeFalse -Because 'the ledger rewrite reads these blocks positionally'
    }

    It 'catches a token count that is not a bare number' {
        $root = New-Fixture 'not-bare'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Researcher.md') `
            -Pattern '"input_tokens": 10000' -Replacement '"input_tokens": "~10,000 (estimated)"'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'an unparseable field drops that dispatch out of every later aggregate'
    }

    It 'catches a cost that does not follow from its tokens and rates' {
        $root = New-Fixture 'bad-arithmetic'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Researcher.md') `
            -Pattern '"est_cost_usd": 0.06525' -Replacement '"est_cost_usd": 0.5'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches a rate that drifts from consumption-rates.md' {
        $root = New-Fixture 'rate-drift'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Researcher.md') `
            -Pattern '"input_rate": 3.0' -Replacement '"input_rate": 9.0'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'only consumption-rates.md holds token rates'
    }

    It 'catches missing orchestration overhead' {
        $root = New-Fixture 'no-orchestration'
        Remove-Item -LiteralPath (Join-Path $root 'history/Squad Scribe.md') -Force
        (Test-Contract $root).Passed | Should -BeFalse -Because 'without it the ledger omits the cost of running the squad itself'
    }

    It 'catches a run total that dropped an earlier role' {
        $root = New-Fixture 'dropped-role'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '\*\*\$0\.09\*\*' -Replacement '**$0.03**'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'this is exactly the payload-only rewrite the Scribe procedure warns about'
    }

    It 'catches an orchestration row that skipped a recorded block' {
        $root = New-Fixture 'partial-orchestration'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '\| 0\.0270 +\| 2\.70' -Replacement '| 0.0100          | 1.00'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'the row is the sum of every orchestration block, not the latest one'
    }

    It 'catches a history file named by role id instead of agent name' {
        $root = New-Fixture 'slugified-history'
        Move-Item -LiteralPath (Join-Path $root 'history/Squad Researcher.md') `
            -Destination (Join-Path $root 'history/researcher.md')
        (Test-Contract $root).Passed | Should -BeFalse -Because 'the filename is how a later turn matches an entry back to its roster row'
    }

    It 'catches a rate table the contract cannot read' {
        $root = New-Fixture 'unreadable-rates'
        Edit-Fixture -Path (Join-Path $root 'consumption-rates.md') `
            -Pattern '\| Cache write \|' -Replacement '| Cache-write |'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a table that does not parse makes every rate assertion vacuous'
    }

    It 'catches history files seeded before the first dispatch' {
        $root = New-Fixture 'init-with-history'
        (Test-Contract -Root $root -InitOnly).Passed | Should -BeFalse -Because 'a history file that predates its dispatch is indistinguishable from one that recorded it'
    }

    It 'catches a roster that lists alternates without their cue' {
        $root = New-Fixture 'no-selection-cue'
        Edit-Fixture -Path (Join-Path $root 'team.md') `
            -Pattern '\| Selection Cue\s+' -Replacement '| Alternate Cue '
        (Test-Contract $root).Passed | Should -BeFalse -Because 'knowing an alternate exists is not knowing when it applies'
    }

    It 'catches a ledger row for a role that was never dispatched' {
        $root = New-Fixture 'idle-role-row'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '(?m)^\| orchestration \| 1 ' `
            -Replacement "| lead          | 0     | 0         | 0      | 0        | 0          | 0.0000          | 0.00         | estimated |`n| orchestration | 1 "
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a zero row makes a stale ledger look populated'
    }

    It 'catches per-turn figures parked in state.json' {
        $root = New-Fixture 'state-scratchpad'
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"estCreditsTotal": 9.225' `
            -Replacement ('"estCreditsTotal": 9.225,' + "`n    " + '"turn1_consumption": { "tokens": "moderate" }')
        (Test-Contract $root).Passed | Should -BeFalse -Because 'currentRun is a running total, not a scratchpad'
    }

    It 'catches an undocumented autonomy mode' {
        $root = New-Fixture 'bad-mode'
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"mode": "interactive"' -Replacement '"mode": "turbo"'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches state.json totals that disagree with the ledger' {
        $root = New-Fixture 'state-drift'
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"estCostUsd": 0.09225' -Replacement '"estCostUsd": 0'
        (Test-Contract $root).Passed | Should -BeFalse
    }
}
