#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1') -Force
    function New-TestEvent {
        param([string]$Type, [hashtable]$Data, [int]$Second = 0, [string]$Id = ([guid]::NewGuid().ToString()))
        @{ id = $Id; type = $Type; timestamp = "2026-10-18T00:00:$($Second.ToString('00'))Z"; data = $Data } | ConvertTo-Json -Depth 15 -Compress
    }
    function New-TestUsage {
        param([string]$Id = 'usage-1')
        New-TestEvent 'session.usage_record' @{ usage = @{ inputTokens = 100; outputTokens = 10; toolTokenCount = 20; availableToolCount = 3; requestBodyBytes = 400; accounting = @{ sourceSessionId = 'child'; usageId = $Id } } }
    }
    function New-TestRuns {
        foreach ($Arm in @('baseline', 'candidate')) {
            foreach ($Pair in 1..3) {
                $Scores = @{ businessClarity = 20; scopeFidelity = 20; acceptanceCriteria = 20; traceability = 20; risksAndDecisions = 20 }
                $Evidence = @{}; foreach ($Name in $Scores.Keys) { $Evidence[$Name] = 'Specific evidence in frozen document.' }
                $Hashes = @{ brd = 'brd-hash'; prd = 'prd-hash' }
                @{
                    schemaVersion = 'squad-efficiency-v1'
                    metadata = @{ runId = "$Arm-$Pair"; pair = $Pair; arm = $Arm; revision = "$Arm-revision"; sourceHash = "$Arm-tree"; compatibility = @{ fixture = 'frozen'; model = 'same'; cli = 'same' } }
                    completed = $true; acceptance = @{ passed = $true }; workflow = @{ passed = $true }
                    stages = @(@{ name = 'init'; passed = $true; process = @{} }, @{ name = 'requirements'; passed = $true; process = @{} }, @{ name = 'build'; passed = $true; process = @{} })
                    metrics = @{ complete = $true; modelRequests = $(if ($Arm -eq 'baseline') { 100 } else { 80 }); toolCalls = $(if ($Arm -eq 'baseline') { 100 } else { 80 }); totals = @{ inputTokens = $(if ($Arm -eq 'baseline') { 10000 } else { 8000 }); outputTokens = 1000 }; counts = @{ failures = 0 } }
                    judge = @{ valid = $true; documentHashes = $Hashes; response = @{ scores = $Scores; evidence = $Evidence; documentHashes = $Hashes; criticalHighFindings = 0 }; metrics = @{ complete = $true; modelRequests = 5; toolCalls = 0; totals = @{ inputTokens = 100; outputTokens = 100 }; counts = @{ failures = 0 } } }
                }
            }
        }
    }
}

Describe 'Efficiency event analysis' -Tag 'Unit' {
    It 'deduplicates accounting records without double-counting child usage' {
        $Path = Join-Path $TestDrive 'usage.jsonl'
        @(New-TestUsage; New-TestUsage) | Set-Content $Path
        $Result = Measure-EfficiencyEvents $Path
        $Result.modelRequests | Should -Be 1
        $Result.totals.inputTokens | Should -Be 100
        $Result.counts.duplicateUsage | Should -Be 1
        $Result.sources.child.records | Should -Be 1
        $Result.totals.cacheReadTokens | Should -BeNullOrEmpty
    }
    It 'merges overlapping and nested hook intervals rather than summing them as blocking' {
        $Path = Join-Path $TestDrive 'hooks.jsonl'
        @(
            New-TestEvent 'hook.start' @{ hookInvocationId = 'one'; hookType = 'postToolUse' } 0
            New-TestEvent 'hook.start' @{ hookInvocationId = 'two'; hookType = 'postToolUse' } 2
            New-TestEvent 'hook.end' @{ hookInvocationId = 'one'; success = $true } 5
            New-TestEvent 'hook.end' @{ hookInvocationId = 'two'; success = $true } 7
        ) | Set-Content $Path
        $Result = Measure-EfficiencyEvents $Path
        $Result.hooks.sumMs | Should -Be 10000
        $Result.hooks.unionMs | Should -Be 7000
        $Result.hooks.overlapMs | Should -Be 3000
        $Result.hooks.blockingMs | Should -BeNullOrEmpty
        $Result.hooks.criticalPathMs | Should -BeNullOrEmpty
    }
    It 'does not count re-emitted hook or tool identifiers twice' {
        $Path = Join-Path $TestDrive 'duplicates.jsonl'
        @(
            New-TestEvent 'tool.execution_start' @{ toolCallId = 'one'; toolName = 'view' }
            New-TestEvent 'tool.execution_start' @{ toolCallId = 'one'; toolName = 'view' }
            New-TestEvent 'tool.execution_complete' @{ toolCallId = 'one'; success = $false }
            New-TestEvent 'tool.execution_complete' @{ toolCallId = 'one'; success = $false }
        ) | Set-Content $Path
        $Result = Measure-EfficiencyEvents $Path
        $Result.toolCalls | Should -Be 1
        $Result.counts.failures | Should -Be 1
        $Result.repairs | Should -BeNullOrEmpty
    }
    It 'marks malformed and unmatched evidence incomplete' {
        $Path = Join-Path $TestDrive 'incomplete.jsonl'
        @((New-TestEvent 'tool.execution_start' @{ toolCallId = 'one'; toolName = 'view' }); '{"partial":') | Set-Content $Path
        $Result = Measure-EfficiencyEvents $Path
        $Result.complete | Should -BeFalse
        $Result.completeness.malformed | Should -Be 1
        $Result.completeness.unmatchedTools | Should -Be 1
        $Result.modelRequests | Should -BeNullOrEmpty
    }
    It 'does not serialize prompt or tool arguments into metrics' {
        $Path = Join-Path $TestDrive 'privacy.jsonl'
        New-TestEvent 'tool.execution_start' @{ toolCallId = 'one'; toolName = 'view'; arguments = @{ path = 'SECRET-PATH' } } | Set-Content $Path
        Measure-EfficiencyEvents $Path | ConvertTo-Json -Depth 30 | Should -Not -Match 'SECRET-PATH'
    }
    It 'preserves missing field coverage rather than treating it as zero' {
        $Path = Join-Path $TestDrive 'coverage.jsonl'
        @((New-TestUsage); (New-TestEvent 'session.usage_record' @{ usage = @{ outputTokens = 5; accounting = @{ sourceSessionId = 'child'; usageId = 'two' } } })) | Set-Content $Path
        $Result = Measure-EfficiencyEvents $Path
        $Result.modelRequests | Should -Be 2
        $Result.totals.inputTokens | Should -BeNullOrEmpty
        $Result.coverage.inputTokens | Should -Be 1
        $Result.totals.outputTokens | Should -Be 15
    }
    It 'creates an immutable snapshot and refuses an existing destination' {
        $Source = Join-Path $TestDrive 'source.jsonl'; $Destination = Join-Path $TestDrive 'snapshot.jsonl'
        New-TestUsage | Set-Content $Source
        $Evidence = Copy-EfficiencySnapshot $Source $Destination
        Add-Content $Source 'later'
        (Get-FileHash $Destination).Hash.ToLowerInvariant() | Should -Be $Evidence.sha256
        { Copy-EfficiencySnapshot $Source $Destination } | Should -Throw
    }
}

Describe 'Efficiency process boundary' -Tag 'Unit' {
    It 'sets repository-hook opt-in only for the child process' {
        $Previous = [Environment]::GetEnvironmentVariable('GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS', 'Process')
        $Output = Join-Path $TestDrive 'child-environment.txt'
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', '[Console]::Write($env:GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS)') -WorkingDirectory $TestDrive -OutputPath $Output -TimeoutSeconds 10 -EnvironmentVariables @{ GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS = 'true' }
        $Result.exitCode | Should -Be 0
        Get-Content $Output -Raw | Should -Be 'true'
        [Environment]::GetEnvironmentVariable('GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS', 'Process') | Should -Be $Previous
    }
    It 'preserves named readiness failures when a stage exits zero' {
        $Trial = {
            param($Arm, $Pair, $Credits)
            $Run = @(New-TestRuns)[0]; $Run.completed = $false; $Run.judge = $null
            $Run.stages = @(@{ name = 'requirements'; passed = $false; process = @{ exitCode = 0; stopCause = 'none' }; readiness = @{ passed = $false; checks = @{ 'PRD Quality Reviewer' = $false; 'brd.md' = $true } } })
            $Run
        }
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial $Trial -PerRunCredits 10 -SeriesCredits 30
        $Result.report.slots[0].failedStages[0].failedChecks | Should -Contain 'PRD Quality Reviewer'
        $Result.report.slots[0].failedStages[0].failedChecks | Should -Not -Contain 'brd.md'
        $Result.report.trials[0].stages[0].readiness.passed | Should -BeFalse
        @($Result.report.slots | Where-Object status -EQ 'not-run').Count | Should -Be 2
    }
    It 'transfers large input through stdin instead of the Windows command line' {
        $Output = Join-Path $TestDrive 'stdin.txt'
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', '$value=[Console]::In.ReadToEnd(); [Console]::Write($value.Length)') -WorkingDirectory $TestDrive -OutputPath $Output -TimeoutSeconds 10 -InputText ('x' * 40000)
        $Result.exitCode | Should -Be 0
        Get-Content $Output -Raw | Should -Be '40000'
    }
    It 'preserves quoted arguments and captures streams without invoking a model' {
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', 'Write-Output "a b"') -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'stdout.txt') -TimeoutSeconds 10
        $Result.exitCode | Should -Be 0
        $Result.stopCause | Should -Be 'none'
        (Get-Content (Join-Path $TestDrive 'stdout.txt') -Raw).Trim() | Should -Be 'a b'
    }
    It 'times out a runaway subprocess' {
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', 'while ($true) {}') -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'timeout.txt') -TimeoutSeconds 1
        $Result.stopCause | Should -Be 'timeout'
    }
    It 'returns a failed independent grade when the implementation is missing' {
        $Output = & (Join-Path $PSScriptRoot 'Test-EfficiencyTask.ps1') -Workspace $TestDrive | ConvertFrom-Json
        $Output.passed | Should -BeFalse
    }
}

Describe 'Efficiency stage readiness' -Tag 'Unit' {
    BeforeEach {
        $script:StageWorkspace = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:StageSquad = Join-Path $script:StageWorkspace '.copilot-tracking/squad'
        New-Item -ItemType Directory -Path (Join-Path $script:StageSquad 'history'), (Join-Path $script:StageWorkspace 'docs/requirements/reviews') -Force | Out-Null
        foreach ($Name in @('team.md', 'routing.md', 'state.json', 'decisions.md', 'consumption.md', 'consumption-rates.md')) {
            Set-Content (Join-Path $script:StageSquad $Name) 'synthetic fixture; external state verification is mocked'
        }
        Set-Content (Join-Path $script:StageSquad 'history/Squad Scribe.md') '# History: Squad Scribe'
        $script:StageMetrics = @{ dispatches = @{ 'Squad Scribe' = 1 } }
        foreach ($Agent in @('BRD Builder', 'PRD Builder', 'BRD Quality Reviewer', 'PRD Quality Reviewer')) {
            $script:StageMetrics.dispatches[$Agent] = 1
            $Relative = "docs/requirements/reviews/$Agent.md"
            Set-Content (Join-Path $script:StageWorkspace $Relative) 'synthetic authored artifact'
            Set-Content (Join-Path $script:StageSquad "history/$Agent.md") "# History: $Agent`n* Deliverable: $Relative"
        }
        foreach ($Name in @('brd.md', 'prd.md')) { Set-Content (Join-Path $script:StageWorkspace "docs/requirements/$Name") 'synthetic published requirements' }
        Mock Invoke-EfficiencyProcess -ModuleName EfficiencyBenchmark { [pscustomobject]@{ exitCode = 0; stopCause = 'none' } }
    }
    It 'accepts initialized state without demanding implementation roles' {
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage init).passed | Should -BeTrue
    }
    It 'accepts requirements with both author and reviewer evidence' {
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeTrue
    }
    It 'rejects a missing reviewer artifact despite existing dispatch and history' {
        Remove-Item (Join-Path $script:StageWorkspace 'docs/requirements/reviews/PRD Quality Reviewer.md')
        $Result = Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements
        $Result.passed | Should -BeFalse
        $Result.checks['PRD Quality Reviewer'] | Should -BeFalse
    }
    It 'rejects reviewer artifacts with no dispatch history' {
        Remove-Item (Join-Path $script:StageSquad 'history/BRD Quality Reviewer.md')
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeFalse
    }
    It 'requires published <Document> before advancing requirements' -ForEach @(@{ Document = 'brd.md' }, @{ Document = 'prd.md' }) {
        Remove-Item (Join-Path $script:StageWorkspace "docs/requirements/$Document")
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeFalse
    }
    It 'does not accept a history deliverable outside the workspace' {
        Set-Content (Join-Path $TestDrive 'outside.md') 'outside evidence'
        Set-Content (Join-Path $script:StageSquad 'history/BRD Quality Reviewer.md') "# History: BRD Quality Reviewer`n* Deliverable: ../outside.md"
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeFalse
    }
    It 'rejects empty initialization state even if the external verifier passes' {
        Set-Content (Join-Path $script:StageSquad 'team.md') '' -NoNewline
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage init).passed | Should -BeFalse
    }
    It 'requires observed reviewer dispatches rather than only files' {
        $script:StageMetrics.dispatches.Remove('PRD Quality Reviewer')
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeFalse
    }
    It 'retains build as the default and requires implementation evidence' {
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics).passed | Should -BeFalse
    }
}

Describe 'Efficiency quality and comparison gates' -Tag 'Unit' {
    It 'requires three pairs and includes independently metered judge work' {
        $Report = Compare-EfficiencyRuns @(New-TestRuns)
        $Report.eligible | Should -BeTrue
        $Report.metrics.modelRequests.baseline | Should -Be 105
        $Report.metrics.modelRequests.candidate | Should -Be 85
        $Report.pairs.Count | Should -Be 3
    }
    It 'rejects missing observations rather than interpreting them as zero' {
        $Runs = @(New-TestRuns); $Runs[3].metrics.totals.inputTokens = $null
        { Compare-EfficiencyRuns $Runs } | Should -Throw
    }
    It 'rejects incompatible runs and duplicate pair identities' {
        $Runs = @(New-TestRuns); $Runs[3].metadata.compatibility.cli = 'different'
        { Compare-EfficiencyRuns $Runs } | Should -Throw '*Incompatible*'
        $Runs = @(New-TestRuns); $Runs[3].metadata.pair = 2
        { Compare-EfficiencyRuns $Runs } | Should -Throw '*Duplicate*'
    }
    It 'does not trust a saved completed flag when independent checks fail' {
        $Runs = @(New-TestRuns); $Runs[3].workflow.passed = $false
        (Compare-EfficiencyRuns $Runs).eligible | Should -BeFalse
    }
    It 'refuses offline promotion when a required stage is missing despite a saved success flag' {
        $Runs = @(New-TestRuns); $Runs[3].stages[2].passed = $false
        (Compare-EfficiencyRuns $Runs).eligible | Should -BeFalse
        { Save-EfficiencyBaseline -Runs $Runs -Path (Join-Path $TestDrive 'missing-stage.json') } | Should -Throw '*not eligible*'
    }
    It 'rejects a faster candidate whose quality declines' {
        $Runs = @(New-TestRuns)
        foreach ($Run in $Runs | Where-Object { $_.metadata.arm -eq 'candidate' }) { $Run.judge.response.scores.businessClarity = 19 }
        $Report = Compare-EfficiencyRuns $Runs
        $Report.eligible | Should -BeFalse
        $Report.reasons -join ',' | Should -Match 'Quality'
    }
    It 'rejects excessive secondary metric regression' {
        $Runs = @(New-TestRuns)
        foreach ($Run in $Runs | Where-Object { $_.metadata.arm -eq 'candidate' }) { $Run.metrics.totals.outputTokens = 2000 }
        (Compare-EfficiencyRuns $Runs).eligible | Should -BeFalse
    }
    It 'requires matching judge document hashes and evidence for every dimension' {
        $Run = @(New-TestRuns)[0]
        $Run.judge.response.documentHashes = @{ brd = 'wrong'; prd = 'wrong' }
        Test-EfficiencyJudge $Run.judge.response $Run.judge.documentHashes | Should -BeFalse
        { Compare-EfficiencyRuns @(New-TestRuns | ForEach-Object { $_.judge.response.evidence.businessClarity = ''; $_ }) } | Should -Throw
    }
    It 'rejects extra score fields rather than inflating the frozen quality total' {
        $Run = @(New-TestRuns)[0]
        $Run.judge.response.scores['bonus'] = 1000
        Test-EfficiencyJudge $Run.judge.response $Run.judge.documentHashes | Should -BeFalse
    }
    It 'preserves the initial report and refuses failed promotion' {
        $Path = Join-Path $TestDrive 'accepted.json'
        Save-EfficiencyBaseline -Runs @(New-TestRuns) -Path $Path | Out-Null
        $Initial = (Get-FileHash ($Path + '.initial.json')).Hash
        Save-EfficiencyBaseline -Runs @(New-TestRuns) -Path $Path | Out-Null
        (Get-FileHash ($Path + '.initial.json')).Hash | Should -Be $Initial
        $Before = (Get-FileHash $Path).Hash
        $Runs = @(New-TestRuns); $Runs[3].acceptance.passed = $false
        { Save-EfficiencyBaseline $Runs $Path } | Should -Throw
        (Get-FileHash $Path).Hash | Should -Be $Before
    }
    It 'refuses a live launch without explicit opt-in and isolation' {
        $Output = Join-Path $TestDrive 'blocked-launch.txt'
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'), '-Mode', 'Run') -WorkingDirectory $TestDrive -OutputPath $Output -TimeoutSeconds 10
        $Result.exitCode | Should -Be 1
        Get-Content ($Output + '.stderr') -Raw | Should -Match 'requires -Live'
    }
    It 'returns exit two and preserves reports for an incomplete Analyze command' {
        $Events = Join-Path $TestDrive 'analyze-events.jsonl'
        New-TestEvent 'tool.execution_start' @{ toolCallId = 'unfinished'; toolName = 'view' } | Set-Content $Events
        $Destination = Join-Path $TestDrive 'analysis'
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'), '-Mode', 'Analyze', '-EventsPath', $Events, '-OutputPath', $Destination) -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'analysis-stdout.txt') -TimeoutSeconds 10
        $Result.exitCode | Should -Be 2
        (Get-Content (Join-Path $Destination 'metrics.json') -Raw | ConvertFrom-Json).complete | Should -BeFalse
        Test-Path (Join-Path $Destination 'events.jsonl') | Should -BeTrue
    }
    It 'actually launches an Establish child and retains its failed preflight stderr' {
        $Source = Join-Path $TestDrive 'launch-source'
        $Install = Join-Path $TestDrive 'launch-install'
        $Trial = Join-Path $TestDrive 'launch-series'
        New-Item -ItemType Directory -Path (Join-Path $Source 'squad-src/.github/agents'), (Join-Path $Install '.github/agents') -Force | Out-Null
        foreach ($Name in @('squad-coordinator.agent.md', 'brd-builder.agent.md', 'prd-builder.agent.md')) { Set-Content -LiteralPath (Join-Path $Install ".github/agents/$Name") -Value 'offline fixture' }
        $Cli = Join-Path $TestDrive 'no-model-cli.ps1'
        @'
if ($args -contains 'mcp') { '{"mcpServers":{}}' }
elseif ($args -contains '--help') { 'OFFLINE PREFLIGHT SENTINEL: no live invocation is supported' }
elseif ($args -contains '--version') { 'offline-cli-1.0' }
else { throw 'A model-backed invocation is forbidden in this test.' }
exit 0
'@ | Set-Content -LiteralPath $Cli -Encoding utf8NoBOM
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'), '-Mode', 'Establish', '-SourceRoot', $Source, '-InstallRoot', $Install, '-CliPath', $Cli, '-TrialRoot', $Trial, '-MaxCredits', '1', '-MaxSeriesCredits', '3', '-Live', '-IsolatedEnvironment') -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'establish-command.txt') -TimeoutSeconds 30 -InputText ''
        $Result.exitCode | Should -Be 2
        $LaunchError = Join-Path $Trial 'out/baseline-1-launch.jsonl.stderr'
        Test-Path -LiteralPath $LaunchError | Should -BeTrue
        Get-Content -LiteralPath $LaunchError -Raw | Should -Match 'does not support --session-id'
        $Report = Get-Content -LiteralPath (Join-Path $Trial 'out/report.json') -Raw | ConvertFrom-Json
        $Report.outcome | Should -Be incomplete
        $Report.slots[0].status | Should -Be failed
        $Report.slots[0].reason | Should -Be 'child-exited-without-run-evidence'
        $Report.slots[0].childExitCode | Should -Be 1
        $Report.slots[0].evidence | Should -Contain 'out/baseline-1-launch.jsonl.stderr'
        Get-Content -LiteralPath (Join-Path $Trial 'out/report.md') -Raw | Should -Match 'Failure Diagnostics'
        Get-Content -LiteralPath (Join-Path $Trial 'out/report.json') -Raw | Should -Not -Match 'OFFLINE PREFLIGHT SENTINEL|does not support --session-id'
        $Report.slots[1].status | Should -Be 'not-run'
    }
    It 'stops after zero-exit initialization with missing readiness evidence' {
        $Install = Join-Path $TestDrive 'incomplete-install'; $Trial = Join-Path $TestDrive 'incomplete-run'
        New-Item -ItemType Directory -Path (Join-Path $Install '.github/agents') -Force | Out-Null
        foreach ($Name in @('squad-coordinator.agent.md', 'brd-builder.agent.md', 'prd-builder.agent.md')) { Set-Content (Join-Path $Install ".github/agents/$Name") 'offline fixture' }
        $Cli = Join-Path $TestDrive 'incomplete-cli.ps1'
        @'
if ($args -contains 'mcp') { '{"mcpServers":{}}'; exit 0 }
if ($args -contains '--version') { 'offline-incomplete-cli'; exit 0 }
if ($args -contains '--help') { '--session-id --max-ai-credits --no-ask-user --max-autopilot-continues --usage-output-file --no-remote --no-remote-export --add-dir'; exit 0 }
Add-Content 'stage-launches.txt' 'one invocation'
$Session = $args[[array]::IndexOf($args, '--session-id') + 1]
$SessionRoot = Join-Path $HOME ".copilot/session-state/$Session"
New-Item -ItemType Directory -Path $SessionRoot -Force | Out-Null
@{ type = 'session.usage_record'; data = @{ usage = @{ inputTokens = 10; outputTokens = 1; accounting = @{ sourceSessionId = $Session; usageId = 'fake-usage' } } } } | ConvertTo-Json -Depth 8 -Compress | Set-Content (Join-Path $SessionRoot 'events.jsonl')
exit 0
'@ | Set-Content $Cli -Encoding utf8NoBOM
        $Source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'), '-Mode', 'Run', '-SourceRoot', $Source, '-InstallRoot', $Install, '-CliPath', $Cli, '-TrialRoot', $Trial, '-MaxCredits', '1', '-Live', '-IsolatedEnvironment') -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'incomplete-command.txt') -TimeoutSeconds 60 -InputText ''
        $Run = Get-Content (Join-Path $Trial 'out/run.json') -Raw | ConvertFrom-Json
        try {
            $Result.exitCode | Should -Be 2
            @($Run.stages).Count | Should -Be 1
            $Run.stages[0].process.exitCode | Should -Be 0
            $Run.stages[0].readiness.passed | Should -BeFalse
            $Run.stages[0].passed | Should -BeFalse
            @(Get-Content (Join-Path $Trial 'workspace/stage-launches.txt')).Count | Should -Be 1
            $Run.judge | Should -BeNullOrEmpty
        }
        finally { Remove-Item (Join-Path $HOME ".copilot/session-state/$($Run.metadata.sessionId)") -Recurse -Force }
    }
    It 'passes the full init prompt and options as valid argv elements to the CLI process' {
        $Install = Join-Path $TestDrive 'argv-install'; $Trial = Join-Path $TestDrive 'argv-run'
        New-Item -ItemType Directory -Path (Join-Path $Install '.github/agents') -Force | Out-Null
        foreach ($Name in @('squad-coordinator.agent.md', 'brd-builder.agent.md', 'prd-builder.agent.md')) { Set-Content -LiteralPath (Join-Path $Install ".github/agents/$Name") -Value 'offline fixture' }
        $Cli = Join-Path $TestDrive 'argv-only-cli.ps1'
        @'
if ($args -contains 'mcp') { '{"mcpServers":{}}'; exit 0 }
if ($args -contains '--version') { 'offline-argv-cli'; exit 0 }
if ($args -contains '--help') { '--session-id --max-ai-credits --no-ask-user --max-autopilot-continues --usage-output-file --no-remote --no-remote-export --add-dir'; exit 0 }
@{ arguments = @($args); repoHooks = $env:GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS } | ConvertTo-Json -Depth 6 -Compress
exit 37
'@ | Set-Content -LiteralPath $Cli -Encoding utf8NoBOM
        $Source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'), '-Mode', 'Run', '-SourceRoot', $Source, '-InstallRoot', $Install, '-CliPath', $Cli, '-TrialRoot', $Trial, '-MaxCredits', '1', '-Live', '-IsolatedEnvironment') -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'argv-command.txt') -TimeoutSeconds 60 -InputText ''
        $Result.exitCode | Should -Be 2
        $Captured = Get-Content -LiteralPath (Join-Path $Trial 'out/init-stdout.jsonl') -Raw | ConvertFrom-Json
        $Captured.arguments[0] | Should -Be '-p'
        $Captured.arguments[1] | Should -Match '^This is a synthetic, preauthorized exercise.*Initialization only; no substantive business deliverables yet\.$'
        $Captured.arguments[2] | Should -Be '--agent'
        $Captured.arguments | Should -Contain '--secret-env-vars=GH_TOKEN,GITHUB_TOKEN,COPILOT_GITHUB_TOKEN'
        $Captured.arguments | Should -Not -Contain 'GITHUB_TOKEN'
        $Captured.arguments | Should -Not -Contain '--trust-folder'
        $Captured.arguments | Should -Contain '--session-id'
        $Captured.arguments | Should -Contain '--allow-all-tools'
        $DirectoryIndex = [array]::IndexOf($Captured.arguments, '--add-dir')
        $DirectoryIndex | Should -BeGreaterThan 0
        $Captured.arguments[$DirectoryIndex + 1] | Should -Be (Join-Path $Trial 'workspace')
        $Captured.arguments | Should -Not -Contain '--allow-all-paths'
        $Captured.arguments | Should -Not -Contain '--allow-all-urls'
        $Captured.arguments | Should -Contain 'shell(git push)'
        $Captured.arguments[1] | Should -Match 'split large reference reads into explicit ranges'
        $Captured.arguments[1] | Should -Match 'one complete Scribe handoff per completed dispatch'
        $Captured.repoHooks | Should -Be 'true'
        $Run = Get-Content -LiteralPath (Join-Path $Trial 'out/run.json') -Raw | ConvertFrom-Json
        $Run.stages[0].process.exitCode | Should -Be 37
        $Run.completed | Should -BeFalse
    }
}

Describe 'Independent functional acceptance contract' -Tag 'Unit' {
    It 'passes all probes on a conformant reference CLI' {
        $Workspace = Join-Path $TestDrive 'reference'; New-Item -ItemType Directory -Path (Join-Path $Workspace 'src') -Force | Out-Null
        @'
param([ValidateSet('add','list','done')][string]$Action,[string]$Store,[string]$Title,[int]$Id,[ValidateSet('all','open','done')][string]$Status='all')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
try {
    $Tasks=@()
    if (Test-Path -LiteralPath $Store) { $Tasks=@(Get-Content -LiteralPath $Store -Raw | ConvertFrom-Json -AsHashtable) }
    if ($Action -eq 'add') {
        if ([string]::IsNullOrWhiteSpace($Title)) {throw 'title'}
        $Maximum=0; foreach ($Task in $Tasks) {if ($Task.id -gt $Maximum) {$Maximum=$Task.id}}
        $Result=@{id=$Maximum+1;title=$Title;status='open'}; $Tasks+=,$Result
    } elseif ($Action -eq 'done') {
        $Found=@($Tasks | Where-Object id -EQ $Id); if ($Found.Count -ne 1) {throw 'id'}
        $Found[0].status='done'; $Result=$Found[0]
    } elseif ($Action -eq 'list') {
        $Selected=@($Tasks | Where-Object {$Status -eq 'all' -or $_.status -eq $Status} | Sort-Object id)
        ConvertTo-Json -InputObject $Selected -Depth 8 -Compress; exit 0
    } else {throw 'action'}
    ConvertTo-Json -InputObject $Tasks -Depth 8 | Set-Content -LiteralPath $Store -Encoding utf8NoBOM
    $Result | ConvertTo-Json -Compress
} catch {exit 1}
'@ | Set-Content -LiteralPath (Join-Path $Workspace 'src/task.ps1') -Encoding utf8NoBOM
        $Result = & (Join-Path $PSScriptRoot 'Test-EfficiencyTask.ps1') -Workspace $Workspace | ConvertFrom-Json
        $Result.checks.Count | Should -Be 12
        $Result.passed | Should -BeTrue -Because (@($Result.checks | Where-Object { -not $_.passed } | ForEach-Object name) -join ', ')
    }
}

Describe 'Unattended series lifecycle' -Tag 'Unit' {
    BeforeEach {
        $script:SeriesCalls = [Collections.Generic.List[string]]::new()
        $script:Trial = {
            param($Arm, $Pair, $Credits)
            $script:SeriesCalls.Add("$Arm-$Pair")
            @(New-TestRuns | Where-Object { $_.metadata.arm -eq $Arm -and $_.metadata.pair -eq $Pair })[0]
        }
    }
    It 'establishes exactly three controls with no invented improvement or prior score' {
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial $script:Trial -PerRunCredits 10 -SeriesCredits 30
        $Result.exitCode | Should -Be 0
        $Result.report.message | Should -Be 'baseline established; no previous comparison available'
        $Result.report.previousComparisonAvailable | Should -BeFalse
        $Result.report.efficiency | Should -BeNullOrEmpty
        $Result.controls.runs.Count | Should -Be 3
        $script:SeriesCalls.Count | Should -Be 3
    }
    It 'executes all six paired slots and automatically compares without promotion' {
        $Result = Invoke-EfficiencySeries -Kind Series -RunTrial $script:Trial -PerRunCredits 10 -SeriesCredits 60
        $Result.exitCode | Should -Be 0
        $script:SeriesCalls -join ',' | Should -Be 'baseline-1,candidate-1,candidate-2,baseline-2,baseline-3,candidate-3'
        $Result.report.outcome | Should -Be 'passed'
        $Result.report.acceptedBaselineChanged | Should -BeFalse
        $Result.report.pairwiseDeltas.Count | Should -Be 3
    }
    It 'reuses exactly three compatible saved controls' {
        $Controls = @{ schemaVersion = 'efficiency-control-v1'; runs = @(New-TestRuns | Where-Object { $_.metadata.arm -eq 'baseline' }) }
        $Result = Invoke-EfficiencySeries -Kind Series -RunTrial $script:Trial -PerRunCredits 10 -SeriesCredits 30 -BaselineEvidence $Controls -ExpectedCompatibility $Controls.runs[0].metadata.compatibility
        $Result.exitCode | Should -Be 0
        $script:SeriesCalls -join ',' | Should -Be 'candidate-1,candidate-2,candidate-3'
        $Result.report.reusedControlRuns | Should -Be 3
    }
    It 'rejects incompatible saved controls before launching anything' {
        $Controls = @{ schemaVersion = 'efficiency-control-v1'; runs = @(New-TestRuns | Where-Object { $_.metadata.arm -eq 'baseline' }) }
        { Invoke-EfficiencySeries -Kind Series -RunTrial $script:Trial -PerRunCredits 10 -SeriesCredits 30 -BaselineEvidence $Controls -ExpectedCompatibility @{ cli = 'different' } } | Should -Throw '*compatibility*'
        $script:SeriesCalls.Count | Should -Be 0
    }
    It 'rejects incorrectly paired saved controls before launching anything' {
        $Controls = @{ schemaVersion = 'efficiency-control-v1'; runs = @(New-TestRuns | Where-Object { $_.metadata.arm -eq 'baseline' }) }
        $Controls.runs[2].metadata.pair = 1
        { Invoke-EfficiencySeries -Kind Series -RunTrial $script:Trial -PerRunCredits 10 -SeriesCredits 30 -BaselineEvidence $Controls -ExpectedCompatibility $Controls.runs[0].metadata.compatibility } | Should -Throw '*paired*'
        $script:SeriesCalls.Count | Should -Be 0
    }
    It 'does not establish a control series whose source changes between trials' {
        $Trial = { param($Arm, $Pair, $Credits) $Run = @(New-TestRuns | Where-Object { $_.metadata.arm -eq $Arm -and $_.metadata.pair -eq $Pair })[0]; $Run.metadata.sourceHash = "changed-$Pair"; $Run }
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial $Trial -PerRunCredits 10 -SeriesCredits 30
        $Result.exitCode | Should -Be 2
        $Result.controls | Should -BeNullOrEmpty
    }
    It 'rejects insufficient series spending bounds before launching anything' {
        { Invoke-EfficiencySeries -Kind Series -RunTrial $script:Trial -PerRunCredits 10 -SeriesCredits 59 } | Should -Throw '*ceiling*'
        $script:SeriesCalls.Count | Should -Be 0
    }
    It 'preserves a failed trial and all unstarted slots without retries' {
        $Trial = { param($Arm, $Pair, $Credits) $script:SeriesCalls.Add("$Arm-$Pair"); $Run = @(New-TestRuns)[0]; $Run.acceptance.passed = $false; $Run }
        $Result = Invoke-EfficiencySeries -Kind Series -RunTrial $Trial -PerRunCredits 10 -SeriesCredits 60
        $Result.exitCode | Should -Be 2
        $Result.report.slots.Count | Should -Be 6
        @($Result.report.slots | Where-Object status -EQ 'not-run').Count | Should -Be 5
        $Result.report.trials.Count | Should -Be 1
        $script:SeriesCalls.Count | Should -Be 1
    }
    It 'reports missing trial evidence as incomplete rather than passing an empty series' {
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial { throw 'missing' } -PerRunCredits 10 -SeriesCredits 30
        $Result.exitCode | Should -Be 2
        $Result.report.outcome | Should -Be 'incomplete'
        $Result.controls | Should -BeNullOrEmpty
    }
    It 'reports missing judge or telemetry as failed checks without losing the failure category' {
        $Trial = { param($Arm, $Pair, $Credits) $Run = @(New-TestRuns)[0]; $Run.completed = $false; $Run.judge = $null; $Run.metrics = $null; $Run }
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial $Trial -PerRunCredits 10 -SeriesCredits 30
        $Result.report.slots[0].reason | Should -Be 'run-failed-independent-checks'
        $Result.report.slots[0].checks.judge | Should -BeFalse
        $Result.report.slots[0].checks.telemetry | Should -BeFalse
        $Result.exitCode | Should -Be 2
    }
    It 'reports an immediate init process failure without calling it a document-quality failure' {
        $Trial = { param($Arm, $Pair, $Credits) $Run = @(New-TestRuns)[0]; $Run.completed = $false; $Run.stages = @(@{ name = 'init'; passed = $false; process = @{ exitCode = 1; stopCause = 'none' } }); $Run.judge = $null; $Run.metrics = $null; $Run }
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial $Trial -PerRunCredits 10 -SeriesCredits 30
        $Result.report.slots[0].failedStages[0].name | Should -Be init
        $Result.report.slots[0].failedStages[0].exitCode | Should -Be 1
        $Result.report.slots[0].failedStages[0].stopCause | Should -Be none
        $Result.report.quality.scores.Count | Should -Be 0
        $Result.exitCode | Should -Be 2
    }
    It 'does not leak arbitrary callback exception text into portable reports' {
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial { throw 'PRIVATE-TOKEN-OR-PROMPT-CONTENT' } -PerRunCredits 10 -SeriesCredits 30
        $Result.report | ConvertTo-Json -Depth 30 | Should -Not -Match 'PRIVATE-TOKEN-OR-PROMPT-CONTENT'
        $Result.report.slots[0].reason | Should -Be 'trial-error-or-missing-evidence'
    }
}

Describe 'Runtime limits and closing review evidence' -Tag 'Unit' {
    It 'stops a subprocess when the observed request budget is exhausted' {
        $Events = Join-Path $TestDrive 'budget-events.jsonl'
        $Encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(((New-TestUsage) + "`n")))
        $Command = "[IO.File]::WriteAllText('$Events',[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$Encoded'))); while (`$true) {}"
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', $Command) -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'budget-stdout.txt') -EventsPath $Events -MaxRequests 1 -TimeoutSeconds 10
        $Result.stopCause | Should -Be 'request-limit'
    }
    It 'requires a passing outcome in the actual closing review artifact' {
        Mock Invoke-EfficiencyProcess -ModuleName EfficiencyBenchmark { @{ exitCode = 0; stopCause = 'none' } }
        $Root = Join-Path $TestDrive 'workflow'; $Squad = Join-Path $Root '.copilot-tracking/squad'
        New-Item -ItemType Directory -Path (Join-Path $Squad 'history'), (Join-Path $Root 'artifacts') -Force | Out-Null
        foreach ($Name in @('routing.md', 'state.json', 'decisions.md', 'consumption.md', 'consumption-rates.md')) { Set-Content (Join-Path $Squad $Name) 'fixture' }
        $Rows = @(); $Dispatches = @{}
        foreach ($Role in @('researcher', 'lead', 'developer', 'tester')) {
            $Agent = "Test $Role"; $Dispatches[$Agent] = 1
            $Rows += "| $Role | member | $Agent | none |"
            Set-Content (Join-Path $Root "artifacts/$Role.md") 'Verdict: Pass'
            Set-Content (Join-Path $Squad "history/$Agent.md") "# History: $Agent`n* Deliverable: artifacts/$Role.md"
        }
        Set-Content (Join-Path $Squad 'team.md') $Rows
        (Test-EfficiencyWorkflow $Root @{ dispatches = $Dispatches }).passed | Should -BeTrue
        Set-Content (Join-Path $Root 'artifacts/tester.md') 'Verdict: Fail'
        (Test-EfficiencyWorkflow $Root @{ dispatches = $Dispatches }).passed | Should -BeFalse
    }
}