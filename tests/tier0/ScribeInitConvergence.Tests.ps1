#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# 0.18.1 hotfix: pins the Init and ledger-repair contract that stops the Scribe
# looping on a fresh squad. GATE-38..GATE-41 in tests/squad-behavior-contract.md are
# this file's contract IDs.
#
# Observed on 0.18.0: the Init Scribe composed generic agent names (the cast catalog
# left the auto-applied roster instructions in 0.18.0 and the Init payload carried
# role ids only), and the Init contract told the Scribe both to leave history/ empty
# and, through the floor, to record its own orchestration block there, with no
# ledgerCommand on the Init payload. The coordinator's next -Check then failed, and
# every corrective Scribe pass appended another block the hand-written ledger missed.
#
# GATE-38..40 are static text pins; GATE-41 runs the shipped Measure-SquadLedger.ps1
# against a seeded fixture to prove the scripted path converges in one pass.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:Model = Get-SquadPackageModel -PackageRoot $PackageRoot

    function Get-SquadReferenceBody {
        param([Parameter(Mandatory)][string]$Name)
        Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot "references/$Name") -Raw
    }

    $script:Coordinator = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-coordinator.agent.md')[0].Body
    $script:Scribe = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-scribe.agent.md')[0].Body
    $script:InitCold = Get-SquadReferenceBody -Name 'scribe-cold-init-and-seeding.md'
    $script:PayloadTemplate = Get-SquadReferenceBody -Name 'scribe-payload-template.md'
    $script:ScribeProcedure = Get-SquadReferenceBody -Name 'scribe-procedure.md'
    $script:OperatingProcedure = Get-SquadReferenceBody -Name 'operating-procedure.md'
    $script:LedgerScript = Join-Path $script:Model.SquadSkillRoot 'scripts/Measure-SquadLedger.ps1'
}

Describe 'GATE-38 Init copies roster rows from the payload and never derives an agent name' {
    It 'the payload template carries a roster field for initialization and roster refresh' {
        $script:PayloadTemplate | Should -Match '(?m)^roster: <initialization/roster refresh only'
    }

    It 'the Init cold file requires verbatim rows and a failure note when they are missing' {
        $script:InitCold | Should -Match ([regex]::Escape('**Copy the roster rows from the payload; never derive them.**'))
        $script:InitCold | Should -Match 'When `roster` is absent, or a row lacks its `Agent Name \(Primary\)`, write nothing and return a failure note'
    }

    It 'the Scribe charter binds verbatim row copying at Step 3' {
        $script:Scribe | Should -Match 'Copy each `team.md` row verbatim from the payload `roster`; never derive an agent name\.'
    }

    It 'the coordinator fills roster with the resolved catalog rows' {
        $script:Coordinator | Should -Match 'Init payload: `roster` rows plus `ledgerCommand`'
        $script:OperatingProcedure | Should -Match ([regex]::Escape('**The Init payload carries the roster rows, not just role ids.**'))
    }
}

Describe 'GATE-39 Init records its orchestration block and runs ledgerCommand last' {
    It 'no Init text still demands an empty history/ directory' {
        foreach ($body in @($script:InitCold, $script:Scribe, $script:Coordinator, $script:OperatingProcedure, $script:ScribeProcedure)) {
            $body | Should -Not -Match 'Seed `history/` as an empty directory'
            $body | Should -Not -Match 'Create no file inside `history/`'
            $body | Should -Not -Match 'an empty `history/`'
            $body | Should -Not -Match 'seeding `history/` empty'
        }
    }

    It 'the Init cold file names history/Squad Scribe.md and ledgerCommand as the last write' {
        $script:InitCold | Should -Match ([regex]::Escape('**The one file Init does write in `history/` is `history/Squad Scribe.md`**'))
        $script:InitCold | Should -Match 'run the payload''s `ledgerCommand` as the last write'
    }

    It 'the payload template requires ledgerCommand on initialization and roster refresh' {
        $script:PayloadTemplate | Should -Match 'on initialization and roster refresh too'
    }

    It 'the Scribe reads the consumption.md ledger template on initialization' {
        $initRow = @($script:ScribeProcedure -split '\r?\n' | Where-Object { $_ -match '^\| initialization or roster refresh \(3\)' })
        $initRow.Count | Should -Be 1
        $initRow[0] | Should -Match '\[consumption\.md\]\(consumption\.md\)'
    }
}

Describe 'GATE-40 Init verification and ledger repair are bounded' {
    It 'the coordinator repairs a failed Init once, then stops and asks the user' {
        $script:Coordinator | Should -Match 'verify once, repair once, then stop\*\*'
        $script:OperatingProcedure | Should -Match ([regex]::Escape('**Verify Init once, repair once, then stop.**'))
        $script:OperatingProcedure | Should -Match 'never dispatch a third Scribe pass'
    }

    It 'Ledger Reconciliation repairs once with ledgerCommand, then stops' {
        $script:OperatingProcedure | Should -Match ([regex]::Escape('**Repair once, then stop.**'))
        $script:OperatingProcedure | Should -Match 'never re-dispatch the Scribe for the same mismatch'
    }
}

Describe 'GATE-41 The scripted ledger converges after Init and after one corrective hand-off' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive '.copilot-tracking/squad'
        New-Item -ItemType Directory -Path (Split-Path $script:Root) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'fixtures', 'scribe-benchmark', 'seed') -Destination $script:Root -Recurse
        $script:ScribeHistory = Join-Path $script:Root 'history/Squad Scribe.md'

        function Format-OrchestrationEntry {
            param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][int]$Turn)
            $fence = '```'
            @(
                ''
                "### 2026-10-07T09:0${Turn}:00Z $Title"
                ''
                "* Turn: $Turn"
                "* Request: $Title."
                '* Deliverable: `state.json`'
                "* Outcome: $Title recorded."
                ''
                '#### Consumption — Orchestration'
                ''
                "${fence}json"
                '{'
                '  "model": "Claude Haiku 4.5",'
                '  "model_source": "agent-pinned",'
                '  "priced_as": "Claude Haiku 4.5",'
                '  "model_tier": "fast",'
                '  "internal_turns": 4,'
                '  "input_tokens": 3000,'
                '  "cached_tokens": 12000,'
                '  "cache_write_tokens": 1250,'
                '  "output_tokens": 3200,'
                '  "basis": "estimated"'
                '}'
                $fence
                ''
            ) -join "`n"
        }

        function Invoke-Ledger {
            param([Parameter(Mandatory)][ValidateSet('Write', 'Check')][string]$Mode)
            $output = & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root "-$Mode" 2>&1
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
        }

        $header = "---`ndescription: `"Append-only dispatch history for a single squad agent`"`n---`n`n# History: Squad Scribe`n"
        Set-Content -LiteralPath $script:ScribeHistory -Value ($header + (Format-OrchestrationEntry -Title 'Initialization state seed' -Turn 1)) -NoNewline -Encoding utf8
    }

    It 'fails -Check when the Init block is on disk but the ledger was left at its seed (the 0.18.0 trap)' {
        (Invoke-Ledger -Mode Check).ExitCode | Should -Not -Be 0
    }

    It 'passes -Check once the Init hand-off runs ledgerCommand last' {
        (Invoke-Ledger -Mode Write).ExitCode | Should -Be 0
        $check = Invoke-Ledger -Mode Check
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }

    It 'converges in one corrective pass when that pass appends its own block before -Write' {
        Add-Content -LiteralPath $script:ScribeHistory -Value (Format-OrchestrationEntry -Title 'Roster refresh' -Turn 2) -NoNewline -Encoding utf8
        (Invoke-Ledger -Mode Write).ExitCode | Should -Be 0
        $check = Invoke-Ledger -Mode Check
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }

    It 'is one block behind when a pass appends its block without -Write' {
        Add-Content -LiteralPath $script:ScribeHistory -Value (Format-OrchestrationEntry -Title 'Hand-written repair' -Turn 3) -NoNewline -Encoding utf8
        (Invoke-Ledger -Mode Check).ExitCode | Should -Not -Be 0 -Because 'a hand-written ledger never folds the block its own hand-off appends'
    }
}
