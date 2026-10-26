#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'BenchmarkScore.psm1') -Force

    # One run's result file, as the benchmark engine writes it.
    function New-RunResult {
        param(
            [int[]]$Dimensions = @(18, 17, 16, 17, 15),
            [string[]]$PassedStages = @('init', 'requirements', 'build'),
            [bool]$Functional = $true,
            [bool]$WorkflowPassed = $true,
            [bool]$JudgeValid = $true,
            [int]$Findings = 1,
            [double]$Seconds = 360,
            [bool]$CreditsComplete = $true,
            [string]$Model = 'test-model',
            [string]$Cli = '1.0.0'
        )
        $names = 'businessClarity', 'scopeFidelity', 'acceptanceCriteria', 'traceability', 'risksAndDecisions'
        $scores = [ordered]@{}
        for ($i = 0; $i -lt 5; $i++) { $scores[$names[$i]] = $Dimensions[$i] }
        $stages = foreach ($name in 'init', 'requirements', 'build') {
            $passed = $name -in $PassedStages
            @{ name = $name; passed = $passed; process = @{ exitCode = 0; seconds = ($Seconds - 60) / 3 }; readiness = @{ passed = $passed; checks = @{ 'state-recorded' = $passed; 'review-written' = $true } } }
        }
        @{
            metadata = @{ sourceHash = 'abc123'; compatibility = @{ model = $Model; cli = $Cli; powershell = '7.6.0' } }
            stages = @($stages)
            metrics = @{ credits = @{ used = 200.5; complete = $CreditsComplete } }
            acceptance = @{ passed = $Functional; checks = @(@{ name = 'add-works'; passed = $Functional }, @{ name = 'list-works'; passed = $true }) }
            workflow = @{ passed = $WorkflowPassed; checks = @{ reviewed = $WorkflowPassed } }
            judge = @{ valid = $JudgeValid; response = @{ scores = $scores; criticalHighFindings = $Findings }; metrics = @{ credits = @{ used = 50.25; complete = $true } }; process = @{ seconds = 60 } }
        }
    }

    # A saved score file. A $null run spec is a run that produced no result.
    function New-ScoreFile {
        param([string]$Name, [object[]]$Runs = @(@{}, @{}, @{}), [string]$Commit = '0123456789abcdef0123456789abcdef01234567', [bool]$Uncommitted = $false)
        $summaries = for ($i = 0; $i -lt $Runs.Count; $i++) {
            $spec = $Runs[$i]
            if ($null -eq $spec) { ConvertTo-BenchmarkRunSummary -Run ($i + 1) -Result $null -Note 'no result' }
            else { $result = New-RunResult @spec; ConvertTo-BenchmarkRunSummary -Run ($i + 1) -Result $result }
        }
        $first = $Runs | Where-Object { $null -ne $_ } | Select-Object -First 1
        $spec = if ($first) { $first } else { @{} }
        $identity = Get-BenchmarkRunIdentity -Result (New-RunResult @spec)
        $score = ConvertTo-BenchmarkScore -Trial @($summaries) -Requested $Runs.Count -Commit $Commit -UncommittedChanges $Uncommitted -Identity $identity -MeasuredAt ([datetime]'2026-10-25T12:00:00Z')
        $null = Write-BenchmarkScore -Score $score -Directory (Join-Path $TestDrive $Name)
        Join-Path $TestDrive "$Name/score.json"
    }

    function Compare-ScoreFile {
        param([string]$Base, [string]$Head, [switch]$Unchanged, [switch]$SquadSourceChanged)
        $baseScore = if ($Base) { Read-BenchmarkScore -Path $Base }
        $headScore = if ($Head) { Read-BenchmarkScore -Path $Head }
        Compare-BenchmarkScore -Base $baseScore -Head $headScore -Unchanged:$Unchanged -SquadSourceChanged:$SquadSourceChanged -BaseProblem $(if (-not $Base) { 'missing' }) -HeadProblem $(if (-not $Head) { 'missing' })
    }
}

Describe 'ConvertTo-BenchmarkRunSummary' {
    It 'derives quality, outcomes, time and credits from a run result' {
        $summary = ConvertTo-BenchmarkRunSummary -Run 1 -Result (New-RunResult)
        $summary.scored | Should -BeTrue
        $summary.quality | Should -Be 83
        $summary.dimensions.traceability | Should -Be 17
        $summary.functional | Should -BeTrue
        $summary.workflow | Should -BeTrue
        $summary.criticalHighFindings | Should -Be 1
        $summary.seconds | Should -Be 360
        $summary.credits | Should -Be 250.75
        $summary.failedChecks | Should -BeNullOrEmpty
    }

    It 'requires every stage and the final workflow checks for the workflow outcome' {
        $summary = ConvertTo-BenchmarkRunSummary -Run 1 -Result (New-RunResult -PassedStages @('init', 'requirements'))
        $summary.workflow | Should -BeFalse
        $summary.functional | Should -BeTrue
        $summary.failedChecks | Should -Contain 'build/state-recorded'
        (ConvertTo-BenchmarkRunSummary -Run 1 -Result (New-RunResult -WorkflowPassed $false)).workflow | Should -BeFalse
    }

    It 'lists failed functional probes' {
        (ConvertTo-BenchmarkRunSummary -Run 1 -Result (New-RunResult -Functional $false)).failedChecks | Should -Contain 'functional/add-works'
    }

    It 'does not score a run without a valid judge result' {
        $summary = ConvertTo-BenchmarkRunSummary -Run 2 -Result (New-RunResult -JudgeValid $false)
        $summary.scored | Should -BeFalse
        $summary.quality | Should -BeNullOrEmpty
        $summary.note | Should -Be 'the judge result is missing or invalid'
    }

    It 'does not score a run with an out-of-range dimension' {
        (ConvertTo-BenchmarkRunSummary -Run 1 -Result (New-RunResult -Dimensions @(18, 17, 16, 17, 25))).scored | Should -BeFalse
    }

    It 'leaves credits unknown when metering was incomplete' {
        (ConvertTo-BenchmarkRunSummary -Run 1 -Result (New-RunResult -CreditsComplete $false)).credits | Should -BeNullOrEmpty
    }

    It 'treats a missing result as a failed run and sanitizes its note' {
        $summary = ConvertTo-BenchmarkRunSummary -Run 3 -Result $null -Note "crashed: <b>x</b> @user `` ::set-output`nnext"
        $summary.scored | Should -BeFalse
        $summary.note | Should -Not -Match '[<>@`:\r\n]'
    }
}

Describe 'ConvertTo-BenchmarkScore' {
    It 'takes medians over scored runs and counts outcomes over the requested runs' {
        $runs = @(
            (ConvertTo-BenchmarkRunSummary -Run 1 -Result (New-RunResult -Dimensions @(18, 17, 16, 17, 15) -Seconds 300)),
            (ConvertTo-BenchmarkRunSummary -Run 2 -Result (New-RunResult -Dimensions @(10, 10, 10, 10, 10) -Seconds 600 -Functional $false)),
            (ConvertTo-BenchmarkRunSummary -Run 3 -Result $null -Note 'crashed')
        )
        $score = ConvertTo-BenchmarkScore -Trial $runs -Requested 3 -Commit 'abc1234'
        $score.runs.scored | Should -Be 2
        $score.runs.failed | Should -Be 1
        $score.summary.quality | Should -Be 66.5
        $score.summary.dimensions.businessClarity | Should -Be 14
        $score.summary.functional | Should -Be 1
        $score.summary.workflow | Should -Be 2
        $score.summary.criticalHighFindings | Should -Be 2
        $score.summary.averageSeconds | Should -Be 450
    }

    It 'takes the middle run when three runs are scored' {
        $runs = foreach ($dimension in 10, 18, 14) { ConvertTo-BenchmarkRunSummary -Run 1 -Result (New-RunResult -Dimensions @($dimension, $dimension, $dimension, $dimension, $dimension)) }
        (ConvertTo-BenchmarkScore -Trial @($runs) -Requested 3 -Commit 'abc1234').summary.quality | Should -Be 70
    }

    It 'leaves the averages unknown when a scored run lacks the data' {
        $runs = @((ConvertTo-BenchmarkRunSummary -Run 1 -Result (New-RunResult -CreditsComplete $false)))
        $score = ConvertTo-BenchmarkScore -Trial $runs -Requested 1 -Commit 'abc1234'
        $score.summary.averageCredits | Should -BeNullOrEmpty
        $score.summary.averageSeconds | Should -Be 360
    }

    It 'needs one summary per requested run' {
        { ConvertTo-BenchmarkScore -Trial @((ConvertTo-BenchmarkRunSummary -Run 1 -Result $null)) -Requested 2 -Commit 'abc1234' } | Should -Throw
    }

    It 'records no quality when no run was scored' {
        $score = ConvertTo-BenchmarkScore -Trial @((ConvertTo-BenchmarkRunSummary -Run 1 -Result $null)) -Requested 1 -Commit 'abc1234'
        $score.summary.quality | Should -BeNullOrEmpty
        Get-BenchmarkBadgeText $score | Should -Be 'benchmark unavailable'
        Get-BenchmarkBadgeSvg $score | Should -Match '#6b7280'
    }
}

Describe 'Badge, report and files' {
    BeforeAll {
        $dimensions = @(@(18, 17, 16, 17, 15), @(18, 16, 14, 18, 17), @(17, 17, 15, 17, 16))
        $seconds = 1159.972, 1271.579, 1134.002
        $runs = for ($i = 0; $i -lt 3; $i++) {
            ConvertTo-BenchmarkRunSummary -Run ($i + 1) -Result (New-RunResult -Dimensions $dimensions[$i] -Seconds $seconds[$i] -PassedStages @('init'))
        }
        $script:Score = ConvertTo-BenchmarkScore -Trial @($runs) -Requested 3 -Commit '0123456789abcdef0123456789abcdef01234567' -Identity (Get-BenchmarkRunIdentity -Result (New-RunResult))
    }

    It 'summarizes the score in the badge text' {
        Get-BenchmarkBadgeText $script:Score | Should -Be 'doc quality 83/100 | functional 3/3 | workflow 0/3 | avg benchmark time 19 min 48.5 s'
    }

    It 'renders a well-formed SVG that is amber unless every run passed and green when all did' {
        $svg = Get-BenchmarkBadgeSvg $script:Score
        ([xml]$svg).svg.title | Should -Be (Get-BenchmarkBadgeText $script:Score)
        $svg | Should -Match 'fill="#b45309"'
        $good = ConvertTo-BenchmarkScore -Trial @((ConvertTo-BenchmarkRunSummary -Run 1 -Result (New-RunResult))) -Requested 1 -Commit 'abc1234'
        Get-BenchmarkBadgeSvg $good | Should -Match 'fill="#16723b"'
    }

    It 'writes score.json, badge.svg and report.md that read back' {
        $directory = Join-Path $TestDrive 'out'
        $paths = Write-BenchmarkScore -Score $script:Score -Directory $directory
        ($paths | ForEach-Object { Split-Path $_ -Leaf }) | Should -Be @('score.json', 'badge.svg', 'report.md')
        foreach ($path in $paths) {
            $bytes = [IO.File]::ReadAllBytes($path)
            $bytes[0] | Should -Not -Be 0xEF
            [Text.Encoding]::UTF8.GetString($bytes) | Should -Not -Match "`r"
        }
        $read = Read-BenchmarkScore -Path (Join-Path $directory 'score.json')
        $read.summary.quality | Should -Be 83
        $read.runs.requested | Should -Be 3
        $read.measuredAt | Should -Match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
        (Get-Content (Join-Path $directory 'report.md') -Raw) | Should -Match 'Document quality \(median, out of 100\) \| 83 \|'
    }
}

Describe 'Read-BenchmarkScore' {
    BeforeAll {
        function Read-Edited {
            param([scriptblock]$Edit)
            $json = Get-Content (New-ScoreFile -Name ('edit-' + [guid]::NewGuid().ToString('N'))) -Raw | ConvertFrom-Json -AsHashtable
            & $Edit $json
            $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
            $json | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path
            Read-BenchmarkScore -Path $path
        }
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'another schema'; Edit = { param($j) $j.schema = 'other' } }
        @{ Name = 'more than three runs'; Edit = { param($j) $j.runs.requested = 4 } }
        @{ Name = 'more scored than requested runs'; Edit = { param($j) $j.runs.scored = 4 } }
        @{ Name = 'a quality above 100'; Edit = { param($j) $j.summary.quality = 101 } }
        @{ Name = 'a text quality'; Edit = { param($j) $j.summary.quality = '83' } }
        @{ Name = 'a missing dimension'; Edit = { param($j) $j.summary.dimensions.Remove('traceability') } }
        @{ Name = 'a fractional run count'; Edit = { param($j) $j.summary.functional = 1.5 } }
    ) {
        { Read-Edited $Edit } | Should -Throw
    }

    It 'rejects files that are not a score' {
        $path = Join-Path $TestDrive 'garbage.json'
        Set-Content -LiteralPath $path -Value '{ not json'
        { Read-BenchmarkScore -Path $path } | Should -Throw
    }

    It 'keeps only sanitized text from the file' {
        $read = Read-Edited {
            param($j)
            $j.environment.model = "x<img src=y onerror=z>`n@octocat ``cmd`` ::error::boom"
            $j.source.commit = 'not-a-sha'
            $j.trials[0].note = '<script>'
        }
        $read.environment.model | Should -Not -Match '[<>@`:\r\n]'
        $read.source.commit | Should -Be 'unknown'
        $read.Keys | Should -Not -Contain 'trials'
    }
}

Describe 'Compare-BenchmarkScore' {
    BeforeAll {
        $script:Base = New-ScoreFile -Name 'base'
    }

    It 'warns about nothing for an identical score' {
        $result = Compare-ScoreFile -Base $script:Base -Head $script:Base -Unchanged
        $result.Warnings | Should -BeNullOrEmpty
        $result.Notes | Should -Contain 'This pull request does not change the benchmark score.'
        $result.Markdown | Should -Match '^<!-- squad-benchmark-score -->'
    }

    It 'shows the change and does not warn when the score improves' {
        $head = New-ScoreFile -Name 'better' -Runs @(@{ Dimensions = @(19, 18, 18, 19, 18) }, @{ Dimensions = @(19, 18, 18, 19, 18) }, @{ Dimensions = @(19, 18, 18, 19, 18) })
        $result = Compare-ScoreFile -Base $script:Base -Head $head
        $result.Warnings | Should -BeNullOrEmpty
        $result.Markdown | Should -Match '\| Document quality \(median, out of 100\) \| 83 \| 92 \| \+9 \|'
    }

    It 'warns about <Name> without failing' -ForEach @(
        @{ Name = 'lower quality'; Runs = @(@{ Dimensions = @(10, 10, 10, 10, 10) }, @{ Dimensions = @(10, 10, 10, 10, 10) }, @{ Dimensions = @(10, 10, 10, 10, 10) }); Expected = 'Document quality is lower' }
        @{ Name = 'a lower dimension'; Runs = @(@{ Dimensions = @(18, 17, 16, 17, 14) }, @{ Dimensions = @(18, 17, 16, 17, 14) }, @{ Dimensions = @(18, 17, 16, 17, 14) }); Expected = 'Risks and decisions' }
        @{ Name = 'a lower functional pass rate'; Runs = @(@{ Functional = $false }, @{}, @{}); Expected = 'functional pass rate is lower' }
        @{ Name = 'a lower workflow pass rate'; Runs = @(@{ WorkflowPassed = $false }, @{}, @{}); Expected = 'workflow pass rate is lower' }
        @{ Name = 'more findings per run'; Runs = @(@{ Findings = 3 }, @{ Findings = 3 }, @{ Findings = 3 }); Expected = 'critical/high findings per run' }
        @{ Name = 'a failed run'; Runs = @(@{}, @{}, $null); Expected = '1 of 3 benchmark runs did not produce a score' }
    ) {
        $head = New-ScoreFile -Name ('head-' + [guid]::NewGuid().ToString('N')) -Runs $Runs
        $result = Compare-ScoreFile -Base $script:Base -Head $head
        ($result.Warnings -join "`n") | Should -Match $Expected
        $result.Markdown | Should -Match ':warning:'
    }

    It 'shows just the current score when there is no base score' {
        $result = Compare-ScoreFile -Head $script:Base
        $result.Warnings | Should -BeNullOrEmpty
        ($result.Notes -join "`n") | Should -Match 'no benchmark score yet'
        $result.Markdown | Should -Match '\| Document quality \(median, out of 100\) \| 83 \|'
    }

    It 'warns when the pull request has no readable score but the base does' {
        $result = Compare-ScoreFile -Base $script:Base
        ($result.Warnings -join "`n") | Should -Match 'no readable benchmark score'
    }

    It 'reports an empty state when neither side has a score' {
        $result = Compare-ScoreFile
        $result.Warnings | Should -BeNullOrEmpty
        $result.Markdown | Should -Match 'No benchmark score has been recorded yet'
    }

    It 'compares on a best-effort basis when run counts, model or CLI differ' {
        $head = New-ScoreFile -Name 'other' -Runs @(@{ Model = 'other-model'; Cli = '2.0.0' })
        $result = Compare-ScoreFile -Base $script:Base -Head $head
        $text = $result.Notes -join "`n"
        $text | Should -Match 'base score used 3 run'
        $text | Should -Match 'model differs'
        $text | Should -Match 'CLI version differs'
        $result.Markdown | Should -Match '\| Functional \(runs passing\) \| 3/3 \| 1/1 \| 0 \|'
    }

    It 'does not warn when the base score has no scored runs to compare with' {
        $result = Compare-ScoreFile -Base (New-ScoreFile -Name 'empty-base' -Runs @($null, $null)) -Head $script:Base
        $result.Warnings | Should -BeNullOrEmpty
        ($result.Notes -join "`n") | Should -Match 'no scored runs'
    }

    It 'warns when none of the pull request runs produced a score' {
        $result = Compare-ScoreFile -Base $script:Base -Head (New-ScoreFile -Name 'empty-head' -Runs @($null, $null))
        ($result.Warnings -join "`n") | Should -Match 'None of the benchmark runs produced a score'
    }

    It 'suggests a refresh when squad-src changed but the score did not' {
        $result = Compare-ScoreFile -Base $script:Base -Head $script:Base -Unchanged -SquadSourceChanged
        ($result.Notes -join "`n") | Should -Match 'Invoke-Benchmark\.ps1'
        $result.Warnings | Should -BeNullOrEmpty
    }

    It 'notes a score measured with uncommitted changes' {
        $head = New-ScoreFile -Name 'dirty' -Uncommitted $true
        (Compare-ScoreFile -Base $script:Base -Head $head).Notes -join "`n" | Should -Match 'uncommitted changes'
    }
}

Describe 'Compare-Benchmark.ps1' {
    BeforeAll {
        $script:Script = Join-Path $PSScriptRoot 'Compare-Benchmark.ps1'
        function Invoke-Comparer {
            param([string]$Path, [hashtable]$Parameters)
            $comment = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.md')
            $command = @('-NoProfile', '-File', $Path, '-CommentPath', $comment)
            foreach ($key in $Parameters.Keys) { $command += @("-$key", $Parameters[$key]) }
            $output = & pwsh @command 2>&1 | Out-String
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output; Comment = if (Test-Path $comment) { Get-Content $comment -Raw } }
        }
    }

    It 'exits 0 and annotates a lower score' {
        $head = New-ScoreFile -Name 'cli-lower' -Runs @(@{ Dimensions = @(5, 5, 5, 5, 5) }, @{ Dimensions = @(5, 5, 5, 5, 5) }, @{ Dimensions = @(5, 5, 5, 5, 5) })
        $result = Invoke-Comparer $script:Script @{ BasePath = (New-ScoreFile -Name 'cli-base'); HeadPath = $head }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match '::warning title=Benchmark score::'
        $result.Comment | Should -Match '^<!-- squad-benchmark-score -->'
    }

    It 'exits 0 when the scores are missing or malformed' {
        $garbage = Join-Path $TestDrive 'garbage.json'
        Set-Content -LiteralPath $garbage -Value '{ not json'
        foreach ($parameters in @(@{}, @{ BasePath = $garbage; HeadPath = $garbage }, @{ BasePath = (Join-Path $TestDrive 'nope.json'); HeadPath = $garbage })) {
            $result = Invoke-Comparer $script:Script $parameters
            $result.ExitCode | Should -Be 0
            $result.Comment | Should -Match 'squad-benchmark-score'
        }
    }

    It 'exits 0 with an unavailable comment when the module cannot load' {
        $lonely = Join-Path $TestDrive 'lonely'
        $null = New-Item -ItemType Directory -Path $lonely
        Copy-Item $script:Script $lonely
        $result = Invoke-Comparer (Join-Path $lonely 'Compare-Benchmark.ps1') @{}
        $result.ExitCode | Should -Be 0
        $result.Comment | Should -Match 'comparison is unavailable'
    }
}

Describe 'Invoke-Benchmark.ps1' {
    It 'rejects -Runs <_>' -ForEach @(0, 4) {
        $output = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Invoke-Benchmark.ps1') -Runs $_ -WhatIf 2>&1 | Out-String
        $LASTEXITCODE | Should -Not -Be 0
        $output | Should -Match 'Runs'
    }

    Context 'with a stand-in benchmark engine' -Skip:(-not $IsLinux) {
        BeforeAll {
            $script:Repo = Join-Path $TestDrive 'repo'
            $live = Join-Path $script:Repo 'tests/tier2/live-benchmark'
            $null = New-Item -ItemType Directory -Path $live, (Join-Path $script:Repo 'tests/lib'), (Join-Path $script:Repo 'squad-src/.github/agents'), (Join-Path $TestDrive 'bin'), (Join-Path $TestDrive 'tmp')
            foreach ($name in 'Invoke-Benchmark.ps1', 'BenchmarkScore.psm1', 'EfficiencyBenchmark.psm1', 'LiveBenchmark.psm1', 'efficiency-scenario.json') { Copy-Item (Join-Path $PSScriptRoot $name) $live }
            Copy-Item (Join-Path $PSScriptRoot '../../lib/SquadInstall.psm1') (Join-Path $script:Repo 'tests/lib')
            Set-Content (Join-Path $script:Repo 'apm.yml') 'name: test'
            Set-Content (Join-Path $script:Repo 'squad-src/.github/agents/squad-test.md') '# test'
            New-RunResult | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $live 'fake-run.json')
            Set-Content (Join-Path $live 'Invoke-EfficiencyExercise.ps1') @'
param($Mode, $TrialRoot, $SourceRoot, $InstallRoot, $Arm, $Pair, $MaxCredits, [switch]$Live, [switch]$IsolatedEnvironment, [switch]$ObservationOnly)
if ($env:FAKE_ENGINE_FAIL_PAIR -eq $Pair) { [Console]::Error.WriteLine('stand-in engine failure'); exit 1 }
New-Item -ItemType Directory -Path (Join-Path $TrialRoot 'out') -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'fake-run.json') (Join-Path $TrialRoot 'out/run.json')
'@
            foreach ($tool in 'apm', 'copilot') {
                $path = Join-Path $TestDrive "bin/$tool"
                Set-Content $path "#!/bin/sh`nexit 0"
                [IO.File]::SetUnixFileMode($path, [IO.UnixFileMode]'UserRead, UserWrite, UserExecute')
            }
            git -C $script:Repo init -q
            git -C $script:Repo add -A
            git -C $script:Repo -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false commit -q -m 'fixture'
            $script:Runner = Join-Path $live 'Invoke-Benchmark.ps1'
            $script:SavedPath = $env:PATH
            $env:PATH = "$(Join-Path $TestDrive 'bin')$([IO.Path]::PathSeparator)$env:PATH"
            $env:TMPDIR = Join-Path $TestDrive 'tmp'
        }
        AfterAll {
            $env:PATH = $script:SavedPath
            $env:TMPDIR = $null
            $env:FAKE_ENGINE_FAIL_PAIR = $null
        }

        It 'saves the score of the runs that finished and records the others as failed' {
            $env:FAKE_ENGINE_FAIL_PAIR = '2'
            $output = & pwsh -NoProfile -File $script:Runner -Runs 2 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            $directory = Join-Path $script:Repo 'benchmarks/efficiency'
            foreach ($name in 'score.json', 'badge.svg', 'report.md') { Join-Path $directory $name | Should -Exist }
            $score = Read-BenchmarkScore -Path (Join-Path $directory 'score.json')
            $score.runs.requested | Should -Be 2
            $score.runs.scored | Should -Be 1
            $score.runs.failed | Should -Be 1
            $output | Should -Match 'Run 2 did not produce a score'
            $output | Should -Match 'stand-in engine failure'
        }

        It 'leaves the saved score alone when no run produced one' {
            $path = Join-Path $script:Repo 'benchmarks/efficiency/score.json'
            Set-Content $path 'previous score'
            $env:FAKE_ENGINE_FAIL_PAIR = '1'
            $null = & pwsh -NoProfile -File $script:Runner -Runs 1 2>&1
            $LASTEXITCODE | Should -Be 1
            (Get-Content $path -Raw).Trim() | Should -Be 'previous score'
        }
    }
}

Describe 'invoke-benchmark.sh' -Skip:(-not ($IsLinux -and (Get-Command bash -ErrorAction SilentlyContinue))) {
    BeforeAll {
        $script:Bash = (Get-Command bash).Source
        $script:Launcher = Join-Path $PSScriptRoot 'invoke-benchmark.sh'
        $script:NoPwsh = Join-Path $TestDrive 'no-pwsh'
        $script:FakeBin = Join-Path $TestDrive 'fake-bin'
        $null = New-Item -ItemType Directory -Path $script:NoPwsh, $script:FakeBin

        # Stand-in pwsh: the version check (-Command) exits $CHECK_EXIT; any other call records its arguments.
        $fake = Join-Path $script:FakeBin 'pwsh'
        @'
#!/bin/sh
for argument in "$@"; do
  if [ "$argument" = '-Command' ]; then exit "$CHECK_EXIT"; fi
done
printf '%s\n' "$@" > "$ARG_LOG"
exit "$RUNNER_EXIT"
'@.Replace("`r", '') | Set-Content -LiteralPath $fake -NoNewline
        [IO.File]::SetUnixFileMode($fake, [IO.UnixFileMode]'UserRead, UserWrite, UserExecute')

        function Invoke-Launcher {
            param([string]$Path, [string[]]$Arguments = @(), [int]$CheckExit = 0, [int]$RunnerExit = 0)
            $log = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.log')
            $saved = $env:PATH
            try {
                $env:PATH = $Path
                $env:CHECK_EXIT = $CheckExit
                $env:RUNNER_EXIT = $RunnerExit
                $env:ARG_LOG = $log
                $output = & $script:Bash $script:Launcher @Arguments 2>&1 | Out-String
                [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output; Arguments = @(if (Test-Path $log) { Get-Content $log }) }
            }
            finally {
                $env:PATH = $saved
                $env:CHECK_EXIT = $null
                $env:RUNNER_EXIT = $null
                $env:ARG_LOG = $null
            }
        }
        $script:WithFake = @($script:FakeBin, '/usr/bin', '/bin') -join [IO.Path]::PathSeparator
    }

    It 'is valid bash' {
        & $script:Bash -n $script:Launcher
        $LASTEXITCODE | Should -Be 0
    }

    It 'stops with install instructions and runs nothing when pwsh is missing' {
        $result = Invoke-Launcher -Path $script:NoPwsh -Arguments @('-WhatIf')
        $result.ExitCode | Should -Be 127
        $result.Output | Should -Match 'was not found on PATH'
        $result.Output | Should -Match 'Nothing has been installed'
        $result.Output | Should -Match 'packages\.microsoft\.com/config/ubuntu'
    }

    It 'stops with install instructions and runs nothing when pwsh is older than 7.4 or cannot run' {
        $result = Invoke-Launcher -Path $script:WithFake -CheckExit 1
        $result.ExitCode | Should -Be 2
        $result.Output | Should -Match 'older than 7\.4 or could not run'
        $result.Arguments.Count | Should -Be 0
    }

    It 'passes its arguments to Invoke-Benchmark.ps1 unchanged and returns its exit status' {
        $result = Invoke-Launcher -Path $script:WithFake -Arguments @('-Runs', '2', '-WhatIf', 'a b') -RunnerExit 7
        $result.ExitCode | Should -Be 7 -Because $result.Output
        $result.Arguments.Count | Should -Be 8
        ($result.Arguments[0..2] -join ' ') | Should -Be '-NoLogo -NoProfile -File'
        $result.Arguments[3] | Should -Be (Join-Path $PSScriptRoot 'Invoke-Benchmark.ps1')
        ($result.Arguments[4..7] -join '|') | Should -Be '-Runs|2|-WhatIf|a b'
    }

    It 'starts the real Invoke-Benchmark.ps1 with the installed pwsh' {
        $result = Invoke-Launcher -Path $env:PATH -Arguments @('-Runs', '4', '-WhatIf')
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "parameter 'Runs'"
    }
}
