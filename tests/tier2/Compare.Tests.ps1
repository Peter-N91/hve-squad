#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Self-check for the Tier 2 comparator, on the same principle as the Tier 1 mutation
# controls: a comparator that reports parity on a drifted run is worse than no
# comparator, because it converts an unmeasured risk into a false assurance.
#
# Each case takes a known-good pair and breaks exactly one thing, then requires the
# score for that dimension - and only that dimension - to move.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadCompare.psm1') -Force

    $script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) "hve-squad-tier2-$([guid]::NewGuid().ToString('N').Substring(0, 8))"

    function New-Observation {
        param([string]$Scenario = 'single-turn')

        [pscustomobject]@{
            schemaVersion = 1
            scenario      = $Scenario
            capturedUtc   = (Get-Date).ToUniversalTime().ToString('o')
            metadata      = @{ attempt = 1; model = 'test-model' }
            squadRoots    = @('.copilot-tracking/squad')
            roles         = @('architect', 'researcher', 'scribe')
            agents        = @('squad-researcher', 'squad-scribe', 'system-architecture-reviewer')
            deliverables  = @(
                [pscustomobject]@{ Path = '.copilot-tracking/research/2026-08-19-ledger.md'; Root = '.copilot-tracking/research/'; Extension = '.md' }
                [pscustomobject]@{ Path = 'docs/design/ledger.md'; Root = 'docs/design/'; Extension = '.md' }
            )
            deliverableRoots = @('.copilot-tracking/research/', 'docs/design/')
            gates         = @(
                [pscustomobject]@{ Gate = 'Council Verdict'; Verdict = 'Go' }
                [pscustomobject]@{ Gate = 'Intake Readiness Verdict'; Verdict = 'Ready' }
            )
            consumption   = @{ estCostUsd = 0.09; estCredits = 9.0 }
            answer        = 'Reserved stock can be double-allocated; add optimistic concurrency and a persistence layer.'
        }
    }

    function Save-Observation {
        param($Observation, [string]$Directory, [string]$Name = 'observation.json')

        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        $path = Join-Path $Directory $Name
        $Observation | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
        $path
    }

    function Invoke-Comparer {
        param([string[]]$Arguments)

        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Compare-SquadRun.ps1') @Arguments *>$null
        $LASTEXITCODE
    }
}

AfterAll {
    if ($script:Scratch -and (Test-Path -LiteralPath $script:Scratch)) {
        Remove-Item -LiteralPath $script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'An unchanged run scores parity' {
    It 'scores 1.0 across every measured dimension' {
        $result = Compare-SquadObservation -Baseline (New-Observation) -Candidate (New-Observation)

        $result.overall | Should -Be 1.0
        $result.dimensions.routing.score | Should -Be 1.0
        $result.dimensions.deliverables.score | Should -Be 1.0
        $result.dimensions.gates.score | Should -Be 1.0
    }

    It 'does not deflate the total when the answer is not judged' {
        $result = Compare-SquadObservation -Baseline (New-Observation) -Candidate (New-Observation)

        $result.dimensions.answer.score | Should -BeNullOrEmpty
        $result.overall | Should -Be 1.0 -Because 'a skipped dimension carries no weight rather than a zero'
    }
}

Describe 'The comparator catches routing drift' {
    It 'catches a role that stopped being dispatched' {
        $candidate = New-Observation
        $candidate.roles = @('researcher', 'scribe')

        $result = Compare-SquadObservation -Baseline (New-Observation) -Candidate $candidate
        $result.dimensions.routing.score | Should -BeLessThan 1.0
        $result.dimensions.routing.missing | Should -Contain 'architect'
    }

    It 'catches a role that was never dispatched before' {
        $candidate = New-Observation
        $candidate.roles = @('architect', 'researcher', 'scribe', 'security')

        $result = Compare-SquadObservation -Baseline (New-Observation) -Candidate $candidate
        $result.dimensions.routing.added | Should -Contain 'security'
    }
}

Describe 'The comparator catches deliverable drift' {
    It 'catches a deliverable that moved to a different root' {
        $candidate = New-Observation
        $candidate.deliverables[1].Root = 'docs/'

        $result = Compare-SquadObservation -Baseline (New-Observation) -Candidate $candidate
        $result.dimensions.deliverables.score | Should -BeLessThan 1.0
    }

    It 'catches a deliverable that stopped being produced' {
        $candidate = New-Observation
        $candidate.deliverables = @($candidate.deliverables[0])

        $result = Compare-SquadObservation -Baseline (New-Observation) -Candidate $candidate
        $result.dimensions.deliverables.score | Should -BeLessThan 1.0
    }

    It 'ignores a renamed file at the same root and type' {
        $candidate = New-Observation
        $candidate.deliverables[0].Path = '.copilot-tracking/research/2026-08-19-concurrency.md'

        $result = Compare-SquadObservation -Baseline (New-Observation) -Candidate $candidate
        $result.dimensions.deliverables.score | Should -Be 1.0 -Because 'the topic slug is the model''s to choose; the root is the roster''s promise'
    }
}

Describe 'The comparator catches gate drift' {
    It 'catches a verdict that flipped' {
        $candidate = New-Observation
        $candidate.gates[0].Verdict = 'Stop'

        $result = Compare-SquadObservation -Baseline (New-Observation) -Candidate $candidate
        $result.dimensions.gates.score | Should -BeLessThan 1.0
    }

    It 'catches a gate that stopped firing' {
        $candidate = New-Observation
        $candidate.gates = @($candidate.gates[0])

        $result = Compare-SquadObservation -Baseline (New-Observation) -Candidate $candidate
        $result.dimensions.gates.missing | Should -Not -BeNullOrEmpty
    }
}

Describe 'The judged answer dimension' {
    It 'lowers the overall score when the answer diverges' {
        $judged = Compare-SquadObservation -Baseline (New-Observation) -Candidate (New-Observation) -AnswerScore 0.0 -AnswerNote 'different conclusion'
        $unjudged = Compare-SquadObservation -Baseline (New-Observation) -Candidate (New-Observation)

        $judged.overall | Should -BeLessThan $unjudged.overall
    }
}

Describe 'The driver script' {
    It 'reports an unbaselined scenario without failing' {
        $root = Join-Path $script:Scratch 'unbaselined'
        Save-Observation -Observation (New-Observation) -Directory (Join-Path $root 'single-turn/attempt-1') | Out-Null

        $exit = Invoke-Comparer @('-ObservationRoot', $root, '-BaselineRoot', (Join-Path $root 'baselines'))
        $exit | Should -Be 0 -Because 'the first run of a new scenario has nothing to drift from'
    }

    It 'captures and then re-scores a baseline as parity' {
        $root = Join-Path $script:Scratch 'roundtrip'
        $baselines = Join-Path $root 'baselines'
        Save-Observation -Observation (New-Observation) -Directory (Join-Path $root 'single-turn/attempt-1') | Out-Null

        Invoke-Comparer @('-ObservationRoot', $root, '-BaselineRoot', $baselines, '-UpdateBaseline') | Out-Null
        Test-Path -LiteralPath (Join-Path $baselines 'single-turn.baseline.json') | Should -BeTrue

        $exit = Invoke-Comparer @('-ObservationRoot', $root, '-BaselineRoot', $baselines, '-Blocking', '-Threshold', '1.0')
        $exit | Should -Be 0
    }

    It 'fails a blocking run when the candidate drifted' {
        $root = Join-Path $script:Scratch 'drifted'
        $baselines = Join-Path $root 'baselines'
        Save-Observation -Observation (New-Observation) -Directory (Join-Path $root 'single-turn/attempt-1') | Out-Null
        Invoke-Comparer @('-ObservationRoot', $root, '-BaselineRoot', $baselines, '-UpdateBaseline') | Out-Null

        $drifted = New-Observation
        $drifted.roles = @('scribe')
        $drifted.gates = @()
        Save-Observation -Observation $drifted -Directory (Join-Path $root 'single-turn/attempt-1') | Out-Null

        $exit = Invoke-Comparer @('-ObservationRoot', $root, '-BaselineRoot', $baselines, '-Blocking', '-Threshold', '0.85')
        $exit | Should -Be 1
    }

    It 'scores the latest attempt when a scenario was retried' {
        $root = Join-Path $script:Scratch 'retried'
        $baselines = Join-Path $root 'baselines'

        $first = New-Observation
        $first.metadata = @{ attempt = 1 }
        $first.roles = @('scribe')
        Save-Observation -Observation $first -Directory (Join-Path $root 'single-turn/attempt-1') | Out-Null

        $second = New-Observation
        $second.metadata = @{ attempt = 2 }
        Save-Observation -Observation $second -Directory (Join-Path $root 'single-turn/attempt-2') | Out-Null

        Save-Observation -Observation (New-Observation) -Directory $baselines -Name 'single-turn.baseline.json' | Out-Null

        $exit = Invoke-Comparer @('-ObservationRoot', $root, '-BaselineRoot', $baselines, '-Blocking', '-Threshold', '1.0')
        $exit | Should -Be 0 -Because 'a scenario that passed on retry is the run that counts'
    }
}
