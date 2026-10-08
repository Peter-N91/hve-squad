# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Offline checks for the live benchmark harness. No model is called; Python and pytest
# are required because the scorer and the task validation run real test suites.

#Requires -Version 7.4

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'LiveBenchmark.psm1') -Force

    function New-SyntheticRun {
        param([string]$Root, [switch]$Delivered, [string]$Verdict = 'Pass-With-Findings', [string]$OwnTests)
        $workspace = Join-Path $Root 'workspace'
        $out = Join-Path $Root 'out'
        $fixture = New-InventoryFixture -Destination $workspace
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        $task = Get-BenchmarkTask -Level medium
        if ($Delivered) {
            Copy-Item -LiteralPath $task.Reference -Destination (Join-Path $workspace 'src/ledger.py') -Force
            Set-Content -LiteralPath (Join-Path $workspace 'tests/test_ledger.py') -Encoding utf8NoBOM -Value @'
from src.ledger import Ledger, OutOfStock
import pytest


def test_release_returns_stock():
    ledger = Ledger({"a": 2})
    ledger.reserve("o1", "a", 2)
    ledger.release("a", 2)
    assert ledger.available("a") == 2


def test_reserve_rejects_more_than_remaining():
    ledger = Ledger({"a": 3})
    ledger.reserve("o1", "a", 2)
    with pytest.raises(OutOfStock):
        ledger.reserve("o2", "a", 2)
'@
            if ($OwnTests) { Set-Content -LiteralPath (Join-Path $workspace 'tests/test_ledger.py') -Encoding utf8NoBOM -Value $OwnTests }
            New-Item -ItemType Directory -Path (Join-Path $workspace 'docs') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $workspace 'docs/CONCURRENCY.md') -Value '# Concurrency`n`nTwo callers interleave and race; a lock fixes it at the cost of contention.' -Encoding utf8NoBOM
            New-Item -ItemType Directory -Path (Join-Path $workspace '.copilot-tracking/reviews') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $workspace '.copilot-tracking/reviews/r.md') -Value "# Review`n`n**Verdict:** $Verdict`n`nOne nit; no failures." -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $workspace '.copilot-tracking/squad/team.md') -Encoding utf8NoBOM -Value @'
# Squad Team

Model routing: economy

| Role | Primary | Alternate Agents | Selection Cue | Model Tier | Model | Deliverable Root | Member Name |
| ---- | ------- | ---------------- | ------------- | ---------- | ----- | ---------------- | ----------- |
| developer | Squad Implementor | — | — | default | `gpt-5.4-mini` | `.copilot-tracking/changes/` | — |
| tester | Squad Reviewer | — | — | fast | claude-haiku-4.5 | `.copilot-tracking/reviews/` | — |
| scribe | Squad Scribe | — | — | fast | — | `.copilot-tracking/squad/` | — |
'@
        }
        @{ runId = 'medium-E-r1'; level = 'medium'; arm = 'E'; repeat = 1; position = 2; requestedModel = 'claude-sonnet-5'; cliVersion = 'test'; srcTreeHash = 'ABC'; baselineCommit = $fixture.Commit } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'metadata.json')
        @{ exitCode = 0; seconds = 300 } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'result.json')
        $metric = { param($nano, $in, $outTok, $cache) @{ totalNanoAiu = $nano; usage = @{ inputTokens = $in; outputTokens = $outTok; cacheReadTokens = $cache; cacheWriteTokens = 0 } } }
        @{
            totalNanoAiu = 50e9
            modelMetrics = @{ 'claude-sonnet-5' = (& $metric 40e9 1000000 20000 900000); 'gpt-5.4-mini' = (& $metric 6e9 100000 3000 90000); 'claude-sonnet-4.6' = (& $metric 4e9 50000 1000 40000) }
            agentMetrics = @{
                main     = @{ totalNanoAiu = 40e9; modelMetrics = @{ 'claude-sonnet-5' = (& $metric 40e9 1000000 20000 900000) } }
                'a-impl' = @{ agentName = 'Squad Implementor'; totalNanoAiu = 6e9; modelMetrics = @{ 'gpt-5.4-mini' = (& $metric 6e9 100000 3000 90000) } }
                'a-rev'  = @{ agentName = 'Squad Reviewer'; totalNanoAiu = 4e9; modelMetrics = @{ 'claude-sonnet-4.6' = (& $metric 4e9 50000 1000 40000) } }
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out 'usage.json')
        $events = @(
            @{ type = 'session.info'; timestamp = '2026-10-05T10:00:00Z'; data = @{} }
            @{ type = 'tool.execution_start'; timestamp = '2026-10-05T10:00:05Z'; data = @{ toolCallId = 'c0'; toolName = 'powershell'; arguments = @{ command = 'pwsh -File .agents/skills/squad/scripts/Get-SquadDispatchBrief.ps1' } } }
            @{ type = 'tool.execution_start'; timestamp = '2026-10-05T10:01:00Z'; data = @{ toolCallId = 'c1'; toolName = 'task'; arguments = @{ agent_type = 'Squad Implementor'; model = 'gpt-5.4-mini' } } }
            @{ type = 'tool.execution_start'; timestamp = '2026-10-05T10:02:00Z'; data = @{ toolCallId = 'c2'; toolName = 'task'; arguments = @{ agent_type = 'general-purpose' } } }
            @{ type = 'tool.execution_start'; timestamp = '2026-10-05T10:03:00Z'; data = @{ toolCallId = 'c3'; toolName = 'task'; arguments = @{ agent_type = 'Squad Reviewer'; model = 'claude-haiku-4.5' } } }
            @{ type = 'tool.execution_complete'; timestamp = '2026-10-05T10:04:00Z'; data = @{ toolCallId = 'c3' } }
            @{ type = 'tool.execution_start'; timestamp = '2026-10-05T10:04:10Z'; data = @{ toolCallId = 'c4'; toolName = 'powershell'; arguments = @{ command = 'pwsh -File Write-SquadHandoff.ps1 -PayloadPath x' } } }
            @{ type = 'tool.execution_start'; timestamp = '2026-10-05T10:04:20Z'; data = @{ toolCallId = 'c5'; toolName = 'task'; parentToolCallId = 'c1'; arguments = @{ agent_type = 'Squad Scribe' } } }
        )
        if (-not $Delivered) { $events = @($events | Where-Object { -not ($_.data.ContainsKey('arguments') -and $_.data.arguments['agent_type'] -in 'Squad Implementor', 'general-purpose') }) }
        Set-Content -LiteralPath (Join-Path $out 'events.jsonl') -Value ($events | ForEach-Object { $_ | ConvertTo-Json -Depth 6 -Compress })
        $Root
    }
}

Describe 'Fixture and schedule' {
    It 'defaults the matrix to the supported repeat floor and warns below it' {
        Get-MinimumBenchmarkRepeats | Should -Be 8
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Invoke-LiveBenchmark.ps1'), [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
        $paramAst = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ParameterAst] -and $node.Name.VariablePath.UserPath -eq 'Repeats' }, $true) | Select-Object -First 1
        $paramAst.DefaultValue.Extent.Text | Should -Be '8'
        @(& { Write-BenchmarkRepeatWarning -Repeats 8 } 3>&1) | Should -BeNullOrEmpty
        $warning = @(& { Write-BenchmarkRepeatWarning -Repeats 7 } 3>&1)
        $warning[0].Message | Should -Match 'below 8 repeats.*indicative only'
    }

    It 'keeps the single-run helper defaults and arm validation aligned with the matrix' {
        $path = Join-Path $PSScriptRoot 'Invoke-LiveBenchmarkRun.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
        $model = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ParameterAst] -and $node.Name.VariablePath.UserPath -eq 'Model' }, $true) | Select-Object -First 1
        $model.DefaultValue.Extent.Text | Should -Be "'claude-sonnet-5.5'"
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should -Match "\[ValidateSet\('A', 'B', 'C', 'D', 'E'\)\]\[string\]\`$Arm"
        $text | Should -Match 'A through E'
        $text | Should -Not -Match 'claude-sonnet-5[^.]'
    }

    It 'selects configured non-builtin MCP servers for isolated benchmark runs' {
        $config = '{"mcpServers":{"builtin":{"source":"builtin"},"workspace":{"source":"workspace"},"plugin":{"source":"plugin"}}}' | ConvertFrom-Json
        @(Get-NonBuiltinMcpServerNames -Configuration $config) | Should -Be @('plugin', 'workspace')
    }

    It 'parses the child-process MCP server argument without flattening names' {
        @(ConvertFrom-McpServerArgument -Names 'calendar,canvas-authoring,mail') | Should -Be @('calendar', 'canvas-authoring', 'mail')
    }

    It 'materialises a clean git repository with one baseline commit and no remote' {
        $fixture = New-InventoryFixture -Destination (Join-Path $TestDrive 'fx')
        git -C $fixture.Root status --porcelain | Should -BeNullOrEmpty
        @(git -C $fixture.Root rev-list --all).Count | Should -Be 1
        git -C $fixture.Root remote | Should -BeNullOrEmpty
        Test-Path (Join-Path $fixture.Root '.copilot-tracking/squad/team.md') | Should -BeTrue
        Test-Path (Join-Path $fixture.Root 'src/ledger.py') | Should -BeTrue
    }

    It 'refuses to overwrite an existing destination' {
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'exists')
        { New-InventoryFixture -Destination $dir.FullName } | Should -Throw '*already exists*'
    }

    It 'seeds a consumption ledger the squad ledger check accepts, so no run starts with a reconciliation' {
        $fixture = New-InventoryFixture -Destination (Join-Path $TestDrive 'ledger')
        $measure = Join-Path $PSScriptRoot '../../../squad-src/.github/skills/squad/scripts/Measure-SquadLedger.ps1'
        pwsh -NoProfile -File $measure -SquadRoot (Join-Path $fixture.Root '.copilot-tracking/squad') -Check *> $null
        $LASTEXITCODE | Should -Be 0
    }

    It 'keeps every fixture and task file free of double-encoded UTF-8, so roster cells parse as written' {
        $files = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'fixtures'), (Join-Path $PSScriptRoot 'tasks') -Recurse -File
        foreach ($file in $files) {
            [IO.File]::ReadAllText($file.FullName) | Should -Not -Match '[\u00C3\u00C2\u00D4][\u0080-\u00FF]' -Because "$($file.Name) must hold real characters, not a codepage round trip"
        }
    }

    It 'gives every arm the same prompt apart from the routing token' {
        foreach ($level in Get-LiveBenchmarkLevel) {
            $a = Get-ArmPrompt -Level $level -Arm A
            $a | Should -Not -Match 'routing='
            $a | Should -Not -Match 'README' -Because 'a referenced input file fires the intake gate, whose role the fixture roster lacks'
            Get-ArmPrompt -Level $level -Arm B | Should -BeExactly $a
            Get-ArmPrompt -Level $level -Arm C | Should -BeExactly "$a routing=ranked"
            Get-ArmPrompt -Level $level -Arm D | Should -BeExactly "$a routing=ranked"
            Get-ArmPrompt -Level $level -Arm E | Should -BeExactly "$a routing=economy"
        }
    }

    It 'pairs arms so each comparison changes exactly one factor' {
        @('A', 'C') | ForEach-Object { Get-ArmSource -Arm $_ } | Should -Be @('baseline', 'baseline')
        @('B', 'D', 'E') | ForEach-Object { Get-ArmSource -Arm $_ } | Should -Be @('candidate', 'candidate', 'candidate')
        (Get-ArmRouting -Arm A) | Should -Be (Get-ArmRouting -Arm B)
        (Get-ArmRouting -Arm C) | Should -Be (Get-ArmRouting -Arm D)
    }

    It 'schedules every arm once per repeat and level, in every position once per level, deterministically for a seed' {
        $a = @(Get-BenchmarkSchedule -Repeats 5 -Seed 137)
        $a.Count | Should -Be 75
        foreach ($group in $a | Group-Object Repeat, Level) { ($group.Group.Arm | Sort-Object) -join '' | Should -Be 'ABCDE' }
        foreach ($group in $a | Group-Object Level, Arm) { ($group.Group.Position | Sort-Object) -join '' | Should -Be '12345' }
        (@(Get-BenchmarkSchedule -Repeats 5 -Seed 137).RunId -join ',') | Should -Be ($a.RunId -join ',')
        (@(Get-BenchmarkSchedule -Repeats 5 -Seed 138).RunId -join ',') | Should -Not -Be ($a.RunId -join ',')
        @($a.RunId | Sort-Object -Unique).Count | Should -Be 75
    }

    It 'gives a reproducible bootstrap interval that brackets the median' {
        $values = [double[]](1..9)
        $ci = Get-BootstrapMedianInterval -Values $values
        $ci.Low | Should -BeLessOrEqual 5
        $ci.High | Should -BeGreaterOrEqual 5
        (Get-BootstrapMedianInterval -Values $values | ConvertTo-Json) | Should -Be ($ci | ConvertTo-Json)
        Get-BootstrapMedianInterval -Values @(4.0) | Should -BeNullOrEmpty
    }
}

Describe 'Task validity: <_>' -ForEach @('easy', 'medium', 'hard') {
    BeforeAll {
        $level = $_
        $result = Test-BenchmarkTask -Level $level -WorkRoot $TestDrive
        $minimum = @{ easy = @(5, 2); medium = @(10, 2); hard = @(8, 3) }[$level]
    }

    It 'passes every hidden test on the reference' {
        $result.ReferenceClean | Should -BeTrue
        $result.ReferencePassed | Should -BeGreaterOrEqual $minimum[0]
    }

    It 'kills every planted mutant' {
        $result.Mutants.Count | Should -BeGreaterOrEqual $minimum[1]
        @($result.Mutants | Where-Object { -not $_.Killed } | ForEach-Object Name) | Should -BeNullOrEmpty
    }

    It 'fails on the fixture baseline' {
        $result.BaselineFailed | Should -BeGreaterThan 0
    }
}

Describe 'Scorer on synthetic workspaces' {
    BeforeAll {
        $good = Measure-LiveBenchmarkRun -TrialRoot (New-SyntheticRun -Root (Join-Path $TestDrive 'good') -Delivered)
        $bad = Measure-LiveBenchmarkRun -TrialRoot (New-SyntheticRun -Root (Join-Path $TestDrive 'bad'))
        $failed = Measure-LiveBenchmarkRun -TrialRoot (New-SyntheticRun -Root (Join-Path $TestDrive 'failed') -Delivered -Verdict 'Fail')
        $coupled = Measure-LiveBenchmarkRun -TrialRoot (New-SyntheticRun -Root (Join-Path $TestDrive 'coupled') -Delivered -OwnTests @'
from src.ledger import Ledger


def test_reads_private_state():
    ledger = Ledger({"a": 2})
    assert ledger._private_counter == 0
'@)
    }

    It 'counts a run as completed only when hidden tests pass and the review passes' {
        $good.completed | Should -BeTrue
        $bad.completed | Should -BeFalse
        $failed.hiddenAllPass | Should -BeTrue
        $failed.reviewVerdict | Should -Be 'Fail'
        $failed.completed | Should -BeFalse
    }

    It 'reports mutants as skipped, not zero, when the own tests fail on the reference' {
        $coupled.testsOnReference | Should -BeFalse
        $coupled.mutantsKilled | Should -Be 'skipped'
    }

    It 'reads credits and tokens with invariant formatting' {
        $good.credits | Should -Be '50'
        $good.coordCr | Should -Be '40'
        $good.ownerCr | Should -Be '6'
        $good.reviewCr | Should -Be '4'
        $good.inputTokens | Should -Be 1150000
        $good.cacheReadTokens | Should -Be 1030000
        $good.coordOutputTokens | Should -Be 20000
    }

    It 'counts dispatches, generic agents, the brief, and the hand-off tail' {
        $good.dispatches | Should -Be 3
        $good.dispatchesAll | Should -Be 4
        $good.scribeDispatches | Should -Be 1
        $good.genericDispatches | Should -Be 1
        $good.briefRan | Should -BeTrue
        $good.coordScriptRuns | Should -Be 1
        $good.handoffSeconds | Should -Be 60
    }

    It 'records routing mode and compares Model cells with the models used' {
        $good.routingMode | Should -Be 'economy'
        $good.modelCells | Should -Be 'developer=gpt-5.4-mini;tester=claude-haiku-4.5'
        $good.modelMatch | Should -Be '1/2'
        $agents = $good.agentsJson | ConvertFrom-Json
        ($agents | Where-Object agent -EQ 'Squad Implementor').match | Should -Be 'yes'
        ($agents | Where-Object agent -EQ 'Squad Implementor').passedModel | Should -Be 'gpt-5.4-mini'
        ($agents | Where-Object agent -EQ 'Squad Reviewer').match | Should -Be 'no'
        ($agents | Where-Object agent -EQ 'coordinator').role | Should -Be 'coordinator'
        $bad.routingMode | Should -Be 'off'
        $bad.modelMatch | Should -Be 'n/a'
    }

    It 'grades a correct delivery as passing every quality check' {
        $good.hiddenAllPass | Should -BeTrue
        $good.hiddenPassed | Should -Be $good.hiddenTotal
        $good.ownTestsPass | Should -BeTrue
        $good.testsOnReference | Should -BeTrue
        $good.mutantsKilled | Should -Be 2
        $good.docCheck | Should -Be 'pass'
        $good.reviewVerdict | Should -Be 'Pass-With-Findings'
        $good.ledgerCheck | Should -Be 'n/a'
    }

    It 'grades an untouched baseline as failing' {
        $bad.hiddenAllPass | Should -BeFalse
        $bad.hiddenPassed | Should -BeLessThan $bad.hiddenTotal
        $bad.mutantsKilled | Should -BeIn @(0, 'skipped')
        $bad.docCheck | Should -Be 'missing'
        $bad.reviewVerdict | Should -Be 'none'
    }

    It 'scores a run with no owner dispatch and no change as halted' {
        $good.outcome | Should -Be 'dispatched'
        $good.stopCause | Should -Be 'none'
        $good.ownerDispatches | Should -Be 1
        $bad.outcome | Should -Be 'halted'
        $bad.stopCause | Should -Be 'unknown'
        $bad.ownerDispatches | Should -Be 0
    }

    It 'diffs only the deliverable, not squad tracking files' {
        $diff = Get-Content -LiteralPath (Join-Path $TestDrive 'good/out/deliverable.diff') -Raw
        $diff | Should -Match 'src/ledger\.py'
        $diff | Should -Match 'docs/CONCURRENCY\.md'
        $diff | Should -Not -Match '\.copilot-tracking'
        git -C (Join-Path $TestDrive 'good/workspace') diff --cached --name-only | Should -BeNullOrEmpty
    }
}

Describe 'Review verdict parsing' {
    It 'reads <Text> as <Expected>' -ForEach @(
        @{ Text = "## Verdict`n`n**Pass**"; Expected = 'Pass' }
        @{ Text = 'Verdict: FAIL - two blockers'; Expected = 'Fail' }
        @{ Text = '| Verdict | Pass-With-Findings |'; Expected = 'Pass-With-Findings' }
        @{ Text = 'Overall the change passed review.'; Expected = 'Pass' }
    ) {
        $ws = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $ws '.copilot-tracking/reviews') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $ws '.copilot-tracking/reviews/r.md') -Value $Text
        Get-ReviewVerdict -Workspace $ws | Should -Be $Expected
    }
}

Describe 'Stop-cause classification' {
    BeforeEach {
        $runRoot = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $runRoot 'out'), (Join-Path $runRoot 'workspace/.copilot-tracking/squad') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $runRoot 'out/stderr.txt') -Value '' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $runRoot 'out/events.jsonl') -Value '' -Encoding utf8NoBOM
        @{ openEscalations = @() } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runRoot 'workspace/.copilot-tracking/squad/state.json') -Encoding utf8NoBOM
    }

    It 'returns intake-escalation from squad state' {
        @{ openEscalations = @(@{ type = 'intake'; reason = 'needs user input' }) } | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath (Join-Path $runRoot 'workspace/.copilot-tracking/squad/state.json') -Encoding utf8NoBOM
        Get-StopCause -TrialRoot $runRoot -ExitCode 0 -Outcome halted | Should -Be 'intake-escalation'
    }

    It 'returns handoff-failure with the handoff exit code' {
        $events = @(
            @{ type = 'tool.execution_start'; data = @{ toolCallId = 'h1'; arguments = @{ command = 'pwsh -File Write-SquadHandoff.ps1' } } }
            @{ type = 'tool.execution_complete'; data = @{ toolCallId = 'h1'; exitCode = 3 } }
        )
        Set-Content -LiteralPath (Join-Path $runRoot 'out/events.jsonl') -Value ($events | ForEach-Object { $_ | ConvertTo-Json -Depth 6 -Compress }) -Encoding utf8NoBOM
        Get-StopCause -TrialRoot $runRoot -ExitCode 0 -Outcome halted | Should -Be 'handoff-failure (exit 3)'
    }

    It 'returns ledger-crash for Measure-SquadLedger exceptions' {
        Set-Content -LiteralPath (Join-Path $runRoot 'out/stderr.txt') -Value 'Measure-SquadLedger.ps1 RuntimeException: null ledger entry' -Encoding utf8NoBOM
        Get-StopCause -TrialRoot $runRoot -ExitCode 0 -Outcome halted | Should -Be 'ledger-crash'
    }

    It 'returns rate-limit for throttle messages' {
        Set-Content -LiteralPath (Join-Path $runRoot 'out/stderr.txt') -Value 'GitHub API throttle exceeded (HTTP 403). Retry later.' -Encoding utf8NoBOM
        Get-StopCause -TrialRoot $runRoot -ExitCode 0 -Outcome halted | Should -Be 'rate-limit'
    }

    It 'returns cli-error for an otherwise unclassified non-zero exit' {
        Get-StopCause -TrialRoot $runRoot -ExitCode 2 -Outcome dispatched | Should -Be 'cli-error'
    }

    It 'returns none for a normal dispatched run' {
        Get-StopCause -TrialRoot $runRoot -ExitCode 0 -Outcome dispatched | Should -Be 'none'
    }

    It 'returns unknown for a halted run with no signal' {
        Get-StopCause -TrialRoot $runRoot -ExitCode 0 -Outcome halted | Should -Be 'unknown'
    }
}

Describe 'Blind judge anonymisation' {
    BeforeAll {
        $runs = foreach ($i in 1..4) {
            $arm = @('A', 'D', 'E', 'A')[$i - 1]
            $id = "medium-$arm-r$i"
            $trial = "C:\Users\someone\AppData\Local\Temp\hve-live-benchmark\runs\$id"
            $path = Join-Path $TestDrive "$id.diff"
            Set-Content -LiteralPath $path -Value "+# marker-$i`n+ran on claude-sonnet-5 with routing=economy for arm $arm`n+see $trial\workspace\src\ledger.py ($id)`n+Model routing: ranked"
            [pscustomobject]@{ RunId = $id; TrialRoot = $trial; DiffPath = $path; Marker = $i }
        }
        $samples = Join-Path $TestDrive 'judge/medium/samples'
        $keyPath = Join-Path $TestDrive 'keys/medium.json'
        $key = Export-JudgeSample -Runs $runs -SampleDirectory $samples -KeyPath $keyPath -Seed 7
    }

    It 'strips arm, run, path, model and routing identifiers from every sample' {
        $files = @(Get-ChildItem -LiteralPath $samples -File)
        $files.Count | Should -Be 4
        foreach ($file in $files) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $text | Should -Not -Match 'claude-sonnet-5|routing=economy|Model routing: ranked|medium-[A-E]-r\d|hve-live-benchmark|AppData|arm [A-E]\b'
            $text | Should -Match 'marker-\d'
        }
    }

    It 'keeps the key outside the sample directory and refuses otherwise' {
        Test-Path $keyPath | Should -BeTrue
        { Export-JudgeSample -Runs $runs -SampleDirectory $samples -KeyPath (Join-Path $samples 'key.json') } | Should -Throw '*outside*'
    }

    It 'shuffles deterministically for a seed' {
        $again = Export-JudgeSample -Runs $runs -SampleDirectory (Join-Path $TestDrive 'again') -KeyPath (Join-Path $TestDrive 'keys/again.json') -Seed 7
        ($again | ConvertTo-Json) | Should -Be ($key | ConvertTo-Json)
        $order = @($key.PSObject.Properties.Value)
        ($order -join ',') | Should -Not -Be ($runs.RunId -join ',')
    }

    It 'de-anonymises judge scores back onto the right runs' {
        $scores = foreach ($file in Get-ChildItem -LiteralPath $samples -File) {
            $marker = [int]([regex]::Match((Get-Content -LiteralPath $file.FullName -Raw), 'marker-(\d)').Groups[1].Value)
            @{ id = $file.BaseName; correctness = @{ score = $marker; reason = 'r' }; tests = @{ score = 5; reason = 'r' }; design = @{ score = 5; reason = 'r' }; docs = $null }
        }
        $reply = "Here you go:`n``````json`n$(@{ samples = @($scores) } | ConvertTo-Json -Depth 5 -Compress)`n``````"
        $merged = @(Merge-JudgeScore -Samples (Read-JudgeScore -Text $reply) -Key $key)
        $merged.Count | Should -Be 4
        foreach ($run in $runs) {
            $row = $merged | Where-Object runId -EQ $run.RunId
            $row.judgeCorrectness | Should -Be $run.Marker
            $row.judgeDocs | Should -BeNullOrEmpty
            $row.judgeMean | Should -Be ([math]::Round(($run.Marker + 10) / 3, 2))
        }
    }

    It 'rejects a judge reply that names an unknown sample' {
        $samplesBad = Read-JudgeScore -Text '{"samples":[{"id":"S99","correctness":{"score":1,"reason":"x"}}]}'
        { Merge-JudgeScore -Samples $samplesBad -Key $key } | Should -Throw '*unknown sample*'
    }
}

Describe 'Judge and report workflow' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $agents = @([ordered]@{ role = 'coordinator'; agent = 'coordinator'; modelsUsed = 'claude-sonnet-5.5'; modelCell = ''; passedModel = ''; match = 'n/a'; credits = 5 })
        [pscustomobject][ordered]@{
            runId = 'easy-A-r1'; level = 'easy'; arm = 'A'; repeat = 1; seconds = 100; outcome = 'dispatched'; stopCause = 'none'; credits = '10'
            coordCr = '5'; ownerCr = '3'; inputTokens = 1000; outputTokens = 100; cacheReadTokens = 50
            hiddenPassed = 5; hiddenTotal = 5; hiddenAllPass = 'True'; completed = 'True'; ownTestsPass = 'True'; testsOnReference = 'True'
            mutantsKilled = 2; mutantsTotal = 2; docCheck = 'n/a'; reviewVerdict = 'Pass'; ledgerCheck = 'PASS'
            dispatches = 1; scribeDispatches = 0; genericDispatches = 0; briefRan = 'True'; coordScriptRuns = 0; handoffSeconds = 10
            routingMode = 'off'; modelMatch = 'n/a'; model = 'claude-sonnet-5.5'; cliVersion = '1.0.0'; srcTreeHash = 'HASH'; agentsJson = (ConvertTo-Json -InputObject $agents -Compress)
        } | Export-Csv -LiteralPath (Join-Path $root 'results.csv') -NoTypeInformation

        $stub = Join-Path $TestDrive 'stub-judge.ps1'
        Set-Content -LiteralPath $stub -Encoding utf8NoBOM -Value @'
param([string]$ResultRoot, [string[]]$Levels, [int]$Seed)
Set-Content -LiteralPath (Join-Path $ResultRoot 'judge-called.txt') -Value "$($Levels -join ',')|$Seed" -Encoding utf8NoBOM
$rows = @(Import-Csv -LiteralPath (Join-Path $ResultRoot 'results.csv'))
foreach ($row in $rows) {
    foreach ($name in 'judgeCorrectness', 'judgeTests', 'judgeDesign', 'judgeDocs', 'judgeMean') {
        $row | Add-Member -NotePropertyName $name -NotePropertyValue '9' -Force
    }
}
$rows | Export-Csv -LiteralPath (Join-Path $ResultRoot 'results-judged.csv') -NoTypeInformation -Encoding utf8NoBOM
'@
    }

    It 'runs the judge by default and reports merged scores' {
        $result = Invoke-BenchmarkJudgeAndReport -ResultRoot $root -Levels @('easy') -Seed 17 -JudgeScript $stub
        Get-Content -LiteralPath (Join-Path $root 'judge-called.txt') -Raw | Should -Match 'easy\|17'
        Split-Path -Leaf $result.ReportCsv | Should -Be 'results-judged.csv'
        $report = Get-Content -LiteralPath $result.ReportPath -Raw
        $report | Should -Match '\| easy \| A \| dispatched x1 .* \| 9 \|'
    }

    It 'skips the judge on request and marks the report as not judged' {
        $result = Invoke-BenchmarkJudgeAndReport -ResultRoot $root -Levels @('easy') -Seed 17 -JudgeScript $stub -SkipJudge
        Test-Path -LiteralPath (Join-Path $root 'judge-called.txt') | Should -BeFalse
        Split-Path -Leaf $result.ReportCsv | Should -Be 'results.csv'
        $report = Get-Content -LiteralPath $result.ReportPath -Raw
        $report | Should -Match 'Not blind judged'
        $report | Should -Match '\*\*not judged\*\*'
    }
}

Describe 'Report generation' {
    BeforeAll {
        $rows = foreach ($level in 'easy', 'hard') {
            foreach ($repeat in 1..3) {
                foreach ($arm in 'A', 'B', 'C', 'D', 'E') {
                    $seconds = @{ A = 300; B = 300; C = 280; D = 250; E = 200 }[$arm] + $repeat
                    $credits = @{ A = 80; B = 80; C = 75; D = 70; E = 60 }[$arm] + $repeat / 10
                    $cell = if ($arm -in 'A', 'B') { '' } else { 'gpt-5.4-mini' }
                    $verdict = if ($level -eq 'hard' -and $arm -eq 'E' -and $repeat -eq 3) { 'Fail' } else { 'Pass' }
                    $skipped = $level -eq 'easy' -and $arm -eq 'D' -and $repeat -eq 1
                    $agents = @(
                        [ordered]@{ role = 'coordinator'; agent = 'coordinator'; modelsUsed = 'claude-sonnet-5'; modelCell = ''; passedModel = ''; match = 'n/a'; credits = 50 }
                        [ordered]@{ role = 'developer'; agent = 'Squad Implementor'; modelsUsed = 'gpt-5.4-mini'; modelCell = $cell; passedModel = 'gpt-5.4-mini'; match = $(if ($cell) { 'yes' } else { 'n/a' }); credits = 6 }
                    )
                    [pscustomobject][ordered]@{
                        runId = "$level-$arm-r$repeat"; level = $level; arm = $arm; repeat = $repeat; seconds = $seconds; outcome = 'dispatched'; stopCause = 'none'; credits = Format-Number $credits
                        coordCr = '50.5'; ownerCr = '6'; inputTokens = 1000000; outputTokens = 20000; cacheReadTokens = 900000
                        hiddenPassed = 11; hiddenTotal = 11; hiddenAllPass = 'True'; completed = $(if ($verdict -eq 'Pass') { 'True' } else { 'False' }); ownTestsPass = 'True'; testsOnReference = $(if ($skipped) { 'False' } else { 'True' })
                        mutantsKilled = $(if ($skipped) { 'skipped' } else { 2 }); mutantsTotal = 2; docCheck = $(if ($level -eq 'easy') { 'n/a' } else { 'pass' }); reviewVerdict = $verdict; ledgerCheck = 'PASS'
                        dispatches = 3; scribeDispatches = 1; genericDispatches = 0; briefRan = 'True'; coordScriptRuns = 0; handoffSeconds = 40
                        routingMode = $(@{ A = 'off'; B = 'off'; C = 'ranked'; D = 'ranked'; E = 'economy' }[$arm]); modelMatch = $(if ($cell) { '1/1' } else { 'n/a' })
                        model = 'claude-sonnet-5'; cliVersion = '1.0.92-3'; srcTreeHash = "HASH$arm"; agentsJson = (ConvertTo-Json -InputObject $agents -Compress)
                        judgeCorrectness = '8'; judgeTests = '7'; judgeDesign = '8'; judgeDocs = ''; judgeMean = '7.67'
                    }
                }
            }
        }
        $csv = Join-Path $TestDrive 'results.csv'
        $rows | Export-Csv -LiteralPath $csv -NoTypeInformation
        $out = Join-Path $TestDrive 'report.md'
        & (Join-Path $PSScriptRoot 'New-BenchmarkReport.ps1') -ResultsCsv $csv -OutFile $out | Out-Null
        $report = Get-Content -LiteralPath $out -Raw
    }

    It 'reports per level and arm medians with ranges' {
        $report | Should -Match '\| easy \| A \| 3 \| 302 \[301, 303\] \| 80\.2 \[80\.1, 80\.3\] \|'
        $report | Should -Match '\| hard \| E \| 3 \| 202 \[201, 203\] \| 60\.2 \[60\.1, 60\.3\] \|'
    }

    It 'reports all-run and completed medians side by side, counting a failed review as not completed' {
        $report | Should -Match '## Summary by Arm'
        $report | Should -Match '\| A \| 6 \| 6 \| 80\.2 \('
        $report | Should -Match '\| E \| 6 \| 5 \| '
    }

    It 'reports paired differences against each arm''s control per repeat and their medians' {
        $report | Should -Match '\| easy \| 1 \| E \| A \| -100 \| -20 \|'
        $report | Should -Match '\| easy \| 1 \| D \| C \| -30 \| -5 \|'
        $report | Should -Match '\| hard \| E \| A \| 3 \| -100 \| 3/3 \| -20 \| 3/3 \|'
        $report | Should -Not -Match '\| C \| A \|'
    }

    It 'reports quality, judge scores, and model assignment per role' {
        $report | Should -Match '\| easy \| D \| dispatched x3 \| none x3 \| 3/3 \| 33/33 \| 3/3 \| 3/3 \| 2/3 \| 4/4 \(1 skipped\) \| n/a \| Pass x3 \| PASS x3 \| 7\.7 \[7\.7, 7\.7\] \|'
        $report | Should -Match '\| hard \| E \| dispatched x3 \| none x3 \| 2/3 \| 33/33 \| 3/3 \|'
        $report | Should -Match '\| hard \| E \| developer \| Squad Implementor \| 3 \| gpt-5\.4-mini x3 \| gpt-5\.4-mini x3 \| gpt-5\.4-mini x3 \| yes x3 \|'
        $report | Should -Match '\| easy \| A \| off x3 \| n/a x3 \| 3 \[3, 3\] \| 1 \[1, 1\] \| 0 \| 3/3 \| 0 \[0, 0\] \| 40 \[40, 40\] \|'
    }

    It 'states limitations and claims no significance test' {
        $report | Should -Match '## Limitations'
        $report | Should -Match 'Sample size'
        $report | Should -Match 'Warm cache'
        $report | Should -Match 'Single fixture, single language'
        $report | Should -Not -Match '(?i)p\s*[<=]\s*0?\.\d|significant(ly)? (faster|cheaper|better)'
    }
}
