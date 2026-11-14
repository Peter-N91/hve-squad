#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
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
    It 'uses final cumulative activity rather than adding repeated stage snapshots' {
        $result = New-RunResult
        $result.metrics.activity = @{ scribeDispatches = 1; scribeModelRequests = 7; scribeSeconds = 68.818; scribeCredits = 1.39; coordinatorModelRequests = 59; authorModelRequests = 34 }
        foreach ($stage in $result.stages) { $stage.metrics = $result.metrics }
        $summary = ConvertTo-BenchmarkRunSummary -Run 1 -Result $result
        $summary.activity.scribeModelRequests | Should -Be 7
        $summary.activity.coordinatorModelRequests | Should -Be 59
    }
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
    It 'averages activity only when every scored run has that metric' {
        $first = New-RunResult
        $first.metrics.activity = @{ scribeDispatches = 1; scribeModelRequests = 7; scribeSeconds = 69; scribeCredits = 1.39; coordinatorModelRequests = 59; authorModelRequests = 34 }
        $second = New-RunResult
        $second.metrics.activity = @{ scribeDispatches = 3; scribeModelRequests = 9; scribeSeconds = $null; scribeCredits = 2.39; coordinatorModelRequests = 61; authorModelRequests = 36 }
        $runs = @((ConvertTo-BenchmarkRunSummary -Run 1 -Result $first), (ConvertTo-BenchmarkRunSummary -Run 2 -Result $second), (ConvertTo-BenchmarkRunSummary -Run 3 -Result $null))
        $score = ConvertTo-BenchmarkScore -Trial $runs -Requested 3 -Commit 'abc1234'
        $score.summary.activity.scribeDispatches | Should -Be 2
        $score.summary.activity.scribeModelRequests | Should -Be 8
        $score.summary.activity.scribeSeconds | Should -BeNullOrEmpty
        [math]::Abs($score.summary.activity.scribeCredits - 1.89) | Should -BeLessThan 1e-9
        $score.summary.activity.authorModelRequests | Should -Be 35
        $runs[1].activity = $null
        $incomplete = ConvertTo-BenchmarkScore -Trial $runs -Requested 3 -Commit 'abc1234'
        $incomplete.summary.activity.scribeModelRequests | Should -BeNullOrEmpty
    }
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
    It 'persists per-trial activity and compares the report with a previous local score' {
        $result = New-RunResult
        $result.metrics.activity = @{ scribeDispatches = 1; scribeModelRequests = 7; scribeSeconds = 68.818; scribeCredits = 1.39; coordinatorModelRequests = 59; authorModelRequests = 34 }
        $score = ConvertTo-BenchmarkScore -Trial @((ConvertTo-BenchmarkRunSummary -Run 1 -Result $result)) -Requested 1 -Commit 'abc1234'
        $directory = Join-Path $TestDrive 'activity-output'
        [void](Write-BenchmarkScore -Score $score -Directory $directory)
        $raw = Get-Content (Join-Path $directory 'score.json') -Raw | ConvertFrom-Json -AsHashtable
        $raw.trials[0].activity.scribeModelRequests | Should -Be 7
        $read = Read-BenchmarkScore -Path (Join-Path $directory 'score.json')
        $read.summary.activity.scribeCredits | Should -Be 1.39
        Get-Content (Join-Path $directory 'report.md') -Raw | Should -Match '\| Scribe dispatches \| unavailable \| 1 \|'
        $earlier = Read-BenchmarkScore (New-ScoreFile -Name 'earlier-activity')
        $earlier.summary.activity = @{ scribeDispatches = 11; scribeSeconds = 796.06; scribeCredits = 21.02 }
        [void](Write-BenchmarkScore -Score $score -Directory $directory -EarlierScore $earlier)
        $report = Get-Content (Join-Path $directory 'report.md') -Raw
        $report | Should -Match '\| Scribe dispatches \| 11 \| 1 \|'
        $report | Should -Match '\| Scribe credits \| 21.02 \| 1.39 \|'
        $report | Should -Match '\| Time inside Scribe dispatches \| 13 min 16.1 s \| 1 min 8.8 s \|'
        $report | Should -Match 'Earlier run: 2026-10-25 12:00 UTC'
    }
    BeforeAll {
        $dimensions = @(@(18, 17, 16, 17, 15), @(18, 16, 14, 18, 17), @(17, 17, 15, 17, 16))
        $seconds = 1159.972, 1271.579, 1134.002
        $runs = for ($i = 0; $i -lt 3; $i++) {
            ConvertTo-BenchmarkRunSummary -Run ($i + 1) -Result (New-RunResult -Dimensions $dimensions[$i] -Seconds $seconds[$i] -PassedStages @('init'))
        }
        $script:Score = ConvertTo-BenchmarkScore -Trial @($runs) -Requested 3 -Commit '0123456789abcdef0123456789abcdef01234567' -Identity (Get-BenchmarkRunIdentity -Result (New-RunResult))
    }

    It 'summarizes the score in the badge text' {
        Get-BenchmarkBadgeText $script:Score | Should -Be 'doc quality 83/100 | functional 3/3 | workflow 0/3 | avg scored-run time 19 min 48.5 s (3/3 scored)'
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
        @{ Name = 'non-object activity'; Edit = { param($j) $j.summary.activity = 'invalid' } }
        @{ Name = 'negative activity'; Edit = { param($j) $j.summary.activity = @{ scribeModelRequests = -1 } } }
        @{ Name = 'text activity'; Edit = { param($j) $j.summary.activity = @{ scribeCredits = '1.39' } } }
        @{ Name = 'boolean activity'; Edit = { param($j) $j.summary.activity = @{ scribeDispatches = $true } } }
        @{ Name = 'non-array failed checks'; Edit = { param($j) $j.trials[0].failedChecks = 'functional/add-works' } }
        @{ Name = 'non-text failed checks'; Edit = { param($j) $j.trials[0].failedChecks = @(@{ injected = '<script>' }) } }
    ) {
        { Read-Edited $Edit } | Should -Throw
    }

    It 'rejects files that are not a score' {
        $path = Join-Path $TestDrive 'garbage.json'
        Set-Content -LiteralPath $path -Value '{ not json'
        { Read-BenchmarkScore -Path $path } | Should -Throw
    }
    It 'accepts historic scores without activity without fabricating zeroes' {
        $read = Read-Edited { param($j) $j.summary.Remove('activity') }
        $read.summary.activity | Should -BeNullOrEmpty
        (Compare-BenchmarkScore -Head $read).Markdown | Should -Match '\| Scribe credits \| unavailable \| unavailable \|'
    }

    It 'keeps only sanitized text from the file' {
        $read = Read-Edited {
            param($j)
            $j.environment.model = "x<img src=y onerror=z>`n@octocat ``cmd`` ::error::boom"
            $j.source.commit = 'not-a-sha'
            $j.trials[0].note = '<script>'
            $j.trials[0].arbitrary = '<script>'
            $j.trials[0].failedChecks = @('functional/<script>', "review/`n::error::")
        }
        $read.environment.model | Should -Not -Match '[<>@`:\r\n]'
        $read.source.commit | Should -Be 'unknown'
        $read.trials[0].note | Should -Not -Match '[<>@`:\r\n]'
        $read.trials[0].Keys | Should -Not -Contain 'arbitrary'
        $read.trials[0].failedChecks | Should -Be @('functional/script', 'review/error')
    }
}

Describe 'Compare-BenchmarkScore' {
    It 'shows unavailable historic activity alongside current measurements without adding warnings' {
        $base = Read-BenchmarkScore (New-ScoreFile -Name 'activity-base')
        $head = Read-BenchmarkScore (New-ScoreFile -Name 'activity-head')
        $head.summary.activity = @{ scribeDispatches = 1; scribeModelRequests = 7; scribeSeconds = 68.818; scribeCredits = 1.39; coordinatorModelRequests = 59; authorModelRequests = 34 }
        $comparison = Compare-BenchmarkScore -Base $base -Head $head
        $comparison.Markdown | Should -Match '\| Scribe dispatches \| unavailable \| 1 \|'
        $comparison.Markdown | Should -Match '\| Coordinator model requests \| unavailable \| 59 \|'
        $comparison.Warnings | Should -BeNullOrEmpty
        $base.summary.activity = @{ scribeDispatches = 11; authorModelRequests = 6 }
        (Compare-BenchmarkScore -Base $base -Head $head).Markdown | Should -Match '\| Scribe dispatches \| 11 \| 1 \|'
        (Compare-BenchmarkScore -Head $head).Markdown | Should -Match '\| BRD/PRD author model requests \| unavailable \| 34 \|'
    }
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
        @{ Name = 'more findings per run'; Runs = @(@{ Findings = 3 }, @{ Findings = 3 }, @{ Findings = 3 }); Expected = 'JUDGE-ONLY critical/high findings per scored run' }
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

Describe 'Honest source coverage and comparison provenance' -Tag 'Unit' {
    BeforeAll {
        function New-CompatibleRun {
            $result = New-RunResult
            $result.metadata.compatibility = @{
                schema = 'efficiency-v1'; rubric = 'rubric-v1'; hostProfile = 'native-cli-references'
                scenarioHash = 'a' * 64; parserHash = 'b' * 64; exerciseHash = 'c' * 64
                preparationHash = 'd' * 64; graderHash = 'e' * 64; verifierHash = 'f' * 64
                converterHash = '1' * 64; installHash = '2' * 64
                model = 'test-model'; cli = '1.0.0'; powershell = '7.6.0'
                roleModelPolicy = 'coordinator.agent.md:model: customer-controlled'
                disabledMcpServers = ''; maxCredits = 120; continuations = 1
                recoveryPolicy = 'bounded-v1'; evaluationPolicy = 'strict-v1'
                privateMetadata = '<secret>must-not-survive'
            }
            $result.metadata.sourceHash = '3' * 64
            $result
        }

        function Invoke-ScoreRoundTrip {
            param($Score)
            $directory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $expectedChecks = @{}
            foreach ($trial in $Score['trials']) {
                $expectedChecks[[string]$trial['run']] = ConvertTo-Json -InputObject $trial['failedChecks'] -Compress
            }
            [void](Write-BenchmarkScore -Score $Score -Directory $directory)
            $stored = Get-Content -LiteralPath (Join-Path $directory 'score.json') -Raw | ConvertFrom-Json -AsHashtable
            $read = Read-BenchmarkScore (Join-Path $directory 'score.json')
            [void](Write-BenchmarkScore -Score $read -Directory $directory)
            $again = Read-BenchmarkScore (Join-Path $directory 'score.json')
            foreach ($roundTrip in @($stored, $read, $again)) {
                foreach ($trial in $roundTrip['trials']) {
                    (ConvertTo-Json -InputObject $trial['failedChecks'] -Compress) | Should -BeExactly $expectedChecks[[string]$trial['run']]
                }
            }
            ($again | ConvertTo-Json -Depth 10 -Compress) | Should -BeExactly ($read | ConvertTo-Json -Depth 10 -Compress)
            $again
        }
    }

    It 'keeps judge-zero separate from a failed requirements review with <Name>' -ForEach @(
        @{ Name = 'unknown severity'; Counts = $null; Path = '.squad/reviews/requirements.md'; Expected = $null }
        @{ Name = 'typed overlapping findings'; Counts = @{ critical = 0; high = 2 }; Path = '.squad/reviews/requirements.md'; Expected = 2 }
        @{ Name = 'typed zero findings'; Counts = @{ critical = 0; high = 0 }; Path = '.squad/reviews/requirements.md'; Expected = 0 }
        @{ Name = 'a spaced reviewer filename'; Counts = @{ critical = 0; high = 2 }; Path = '.squad\reviews\Squad Reviewer.md'; Expected = 2 }
        @{ Name = 'spaced path segments'; Counts = @{ critical = 0; high = 2 }; Path = '.squad/review notes/Squad Reviewer.md'; Expected = 2 }
        @{ Name = 'a partial severity pair'; Counts = @{ high = 2 }; Path = '.squad/reviews/requirements.md'; Expected = $null }
        @{ Name = 'unparseable findings'; Counts = 'High: 2'; Path = '.squad/reviews/requirements.md'; Expected = $null }
        @{ Name = 'negative findings'; Counts = @{ critical = -1; high = 2 }; Path = '.squad/reviews/requirements.md'; Expected = $null }
        @{ Name = 'fractional findings'; Counts = @{ critical = 0; high = 1.5 }; Path = '.squad/reviews/requirements.md'; Expected = $null }
        @{ Name = 'boolean findings'; Counts = @{ critical = $false; high = 2 }; Path = '.squad/reviews/requirements.md'; Expected = $null }
        @{ Name = 'text findings'; Counts = @{ critical = 0; high = '2' }; Path = '.squad/reviews/requirements.md'; Expected = $null }
        @{ Name = 'traversal'; Counts = @{ critical = 0; high = 2 }; Path = '..\private.md'; Expected = $null }
        @{ Name = 'an absolute path'; Counts = @{ critical = 0; high = 2 }; Path = 'C:\private.md'; Expected = $null }
        @{ Name = 'a markup path'; Counts = @{ critical = 0; high = 2 }; Path = '[review](https://example.test)'; Expected = $null }
        @{ Name = 'spaced traversal'; Counts = @{ critical = 0; high = 2 }; Path = '.squad/.. /private.md'; Expected = $null }
        @{ Name = 'a rooted path'; Counts = @{ critical = 0; high = 2 }; Path = '/private.md'; Expected = $null }
        @{ Name = 'a network path'; Counts = @{ critical = 0; high = 2 }; Path = '\\server\private.md'; Expected = $null }
        @{ Name = 'a control character'; Counts = @{ critical = 0; high = 2 }; Path = ".squad/reviews/line`nbreak.md"; Expected = $null }
        @{ Name = 'backtick delimiters'; Counts = @{ critical = 0; high = 2 }; Path = '.squad/reviews/`review`.md'; Expected = $null }
        @{ Name = 'bracket delimiters'; Counts = @{ critical = 0; high = 2 }; Path = '.squad/reviews/[review].md'; Expected = $null }
        @{ Name = 'an alternate data stream'; Counts = @{ critical = 0; high = 2 }; Path = '.squad/reviews/review:stream.md'; Expected = $null }
    ) {
        $result = New-RunResult -Findings 0 -PassedStages @('init', 'build')
        $result.stages[1].readiness.checks.reviewOutcome = $false
        $result.stages[1].readiness.reviewPath = $Path
        $result.stages[1].readiness.findingCounts = $Counts
        $result.stages[2].readiness.checks.reviewOutcome = $true
        $result.stages[2].readiness.reviewPath = '.squad/reviews/build.md'
        $result.stages[2].readiness.findingCounts = @{ critical = 0; high = 2 }
        $trial = ConvertTo-BenchmarkRunSummary -Run 1 -Result $result
        $trial.sourceReviews.requirements.outcome | Should -Be 'failed'
        if ($null -eq $Expected) { $trial.sourceReviews.requirements.criticalHighFindings | Should -BeNullOrEmpty }
        else { $trial.sourceReviews.requirements.criticalHighFindings | Should -Be $Expected }
        if ($Name -in 'traversal', 'an absolute path', 'a markup path', 'spaced traversal', 'a rooted path',
            'a network path', 'a control character', 'backtick delimiters', 'bracket delimiters', 'an alternate data stream') {
            $trial.sourceReviews.requirements.reviewPath | Should -BeNullOrEmpty
        }
        $trial.sourceReviews.build.criticalHighFindings | Should -Be 2
        $trial.failedChecks | Should -Contain 'requirements/reviewOutcome'
        $score = Invoke-ScoreRoundTrip (ConvertTo-BenchmarkScore -Trial @($trial) -Requested 1 -Commit 'abc1234')
        $score.schema | Should -Be 'benchmark-score-v1'
        $score.summary.quality | Should -Be 83
        $score.summary.criticalHighFindings | Should -Be 0
        $score.summary.workflow | Should -Be 0
        $score.trials[0].sourceReviews.requirements.outcome | Should -Be 'failed'
        $score.trials[0].failedChecks | Should -HaveCount 2
        $score.trials[0].failedChecks | Should -Contain 'requirements/state-recorded'
        $score.trials[0].failedChecks | Should -Contain 'requirements/reviewOutcome'
        $report = Get-BenchmarkReportMarkdown $score
        $comparison = Compare-BenchmarkScore -Base $score -Head $score
        foreach ($text in $report, $comparison.Markdown) {
            $text | Should -Match 'JUDGE-ONLY critical/high findings \| 0'
            $text | Should -Match '\| 1 \| requirements \| failed \|'
            $text | Should -Match 'unavailable severity coverage is not zero'
            $text | Should -Not -Match 'https:|C:\\private|\.\./private'
        }
        if ($null -eq $Expected) { $report | Should -Match '\| 1 \| requirements \| failed \| [^\r\n]*\| unavailable \|' }
        else {
            $expectedPath = $Path.Replace('\', '/')
            $score.trials[0].sourceReviews.requirements.reviewPath | Should -BeExactly $expectedPath
            foreach ($text in $report, $comparison.Markdown) { $text | Should -Match ([regex]::Escape("``$expectedPath``")) }
        }
        $score.trials[0].sourceReviews.build.criticalHighFindings = 1.5
        { Write-BenchmarkScore -Score $score -Directory (Join-Path $TestDrive 'invalid-severity') } | Should -Throw
    }

    It 'retains a slower unscored trial in all-requested costs with <Name>' -ForEach @(
        @{ Name = 'complete credits'; Complete = $true; ExpectedCreditsCovered = 2; TotalCredits = 1001.0 }
        @{ Name = 'incomplete unscored credits'; Complete = $false; ExpectedCreditsCovered = 1; TotalCredits = 250.75 }
    ) {
        $first = New-RunResult -Seconds 300
        $second = New-RunResult -Seconds 900 -JudgeValid $false -CreditsComplete $Complete
        $second.metrics.credits.used = 700
        $trials = @(
            (ConvertTo-BenchmarkRunSummary -Run 1 -Result $first)
            (ConvertTo-BenchmarkRunSummary -Run 2 -Result $second)
            (ConvertTo-BenchmarkRunSummary -Run 3 -Result $null)
        )
        $score = Invoke-ScoreRoundTrip (ConvertTo-BenchmarkScore -Trial $trials -Requested 3 -Commit 'abc1234')
        $score.runs.scored | Should -Be 1
        $score.summary.averageSeconds | Should -Be 300
        $score.summary.averageCredits | Should -Be 250.75
        $score.summary.allRequested.totalSeconds | Should -Be 1200
        $score.summary.allRequested.averageSeconds | Should -Be 600
        $score.summary.allRequested.secondsCovered | Should -Be 2
        $score.summary.allRequested.creditsCovered | Should -Be $ExpectedCreditsCovered
        $score.summary.allRequested.totalCredits | Should -Be $TotalCredits
        $score.trials[1].quality | Should -BeNullOrEmpty
        $score.trials[1].note | Should -Be 'the judge result is missing or invalid'
        Get-BenchmarkBadgeText $score | Should -Match 'avg scored-run time 5 min 0 s \(1/3 scored\)'
        foreach ($text in (Get-BenchmarkReportMarkdown $score), (Compare-BenchmarkScore -Head $score).Markdown) {
            $text | Should -Match 'Average time per scored run \| 5 min 0 s'
            $text | Should -Match 'All-requested time \(total observed\) \| 20 min 0 s; 2/3 requested runs covered'
            $text | Should -Match 'All-requested time \(average observed\) \| 10 min 0 s; 2/3 requested runs covered'
        }
        $empty = ConvertTo-BenchmarkScore -Trial @($trials[2]) -Requested 1 -Commit 'abc1234'
        $empty.summary.allRequested.secondsCovered | Should -Be 0
        $empty.summary.allRequested.totalSeconds | Should -BeNullOrEmpty
        $empty.summary.allRequested.averageCredits | Should -BeNullOrEmpty
        $score.summary.allRequested.secondsCovered = 0
        { Write-BenchmarkScore -Score $score -Directory (Join-Path $TestDrive 'invalid-coverage') } | Should -Throw
    }

    It 'flags <Name> identities without leaking raw metadata or truncating equality' -ForEach @(
        @{ Name = 'complete matching'; Key = ''; Expected = 'compatible' }
        @{ Name = 'legacy unavailable'; Key = 'legacy'; Expected = 'unknown' }
        @{ Name = 'legacy trials with unavailable review coverage'; Key = 'legacy-trials'; Expected = 'unknown' }
        @{ Name = 'missing scenario'; Key = 'scenario-missing'; Expected = 'unknown' }
        @{ Name = 'different scenario'; Key = 'scenario'; Expected = 'incompatible' }
        @{ Name = 'different rubric'; Key = 'rubric'; Expected = 'incompatible' }
        @{ Name = 'different scenario payload'; Key = 'scenarioHash'; Expected = 'incompatible' }
        @{ Name = 'different parser'; Key = 'parserHash'; Expected = 'incompatible' }
        @{ Name = 'different exercise'; Key = 'exerciseHash'; Expected = 'incompatible' }
        @{ Name = 'different preparation'; Key = 'preparationHash'; Expected = 'incompatible' }
        @{ Name = 'different grader'; Key = 'graderHash'; Expected = 'incompatible' }
        @{ Name = 'different verifier'; Key = 'verifierHash'; Expected = 'incompatible' }
        @{ Name = 'different converter'; Key = 'converterHash'; Expected = 'incompatible' }
        @{ Name = 'different installation'; Key = 'installHash'; Expected = 'incompatible' }
        @{ Name = 'different role policy beyond display length'; Key = 'roleModelPolicy'; Expected = 'incompatible' }
        @{ Name = 'different PowerShell'; Key = 'powershell'; Expected = 'incompatible' }
        @{ Name = 'missing runtime'; Key = 'runtime-missing'; Expected = 'unknown' }
        @{ Name = 'oversized runtime'; Key = 'runtime-oversized'; Expected = 'unknown' }
        @{ Name = 'invalid fingerprint'; Key = 'fingerprint'; Expected = 'unknown' }
    ) {
        $before = New-CompatibleRun
        $after = New-CompatibleRun
        $before.metadata.compatibility.roleModelPolicy = ('x' * 100) + '<private-before>'
        $after.metadata.compatibility.roleModelPolicy = $before.metadata.compatibility.roleModelPolicy
        if ($Key -eq 'runtime-missing') { [void]$after.metadata.compatibility.Remove('powershell') }
        elseif ($Key -eq 'runtime-oversized') { $after.metadata.compatibility.powershell = 'x' * 16385 }
        elseif ($Key -notin '', 'legacy', 'legacy-trials', 'scenario', 'scenario-missing', 'fingerprint') { $after.metadata.compatibility[$Key] += '<private-after>' }
        $trial = ConvertTo-BenchmarkRunSummary -Run 1 -Result $before
        $base = ConvertTo-BenchmarkScore -Trial @($trial) -Requested 1 -Commit 'abc1234' -Identity (Get-BenchmarkRunIdentity $before)
        $head = ConvertTo-BenchmarkScore -Trial @($trial) -Requested 1 -Commit 'def5678' -Identity (Get-BenchmarkRunIdentity $after)
        if ($Key -in 'legacy', 'legacy-trials') {
            [void]$base.Remove('compatibility'); [void]$base.Remove('scenario')
            [void]$base.summary.Remove('allRequested')
            if ($Key -eq 'legacy') { [void]$base.Remove('trials') }
            else { [void]$base.trials[0].Remove('sourceReviews') }
        }
        elseif ($Key -eq 'scenario') { $head.scenario = 'another-scenario' }
        elseif ($Key -eq 'scenario-missing') { $head.scenario = ('x' * 80) + '<unsafe>' }
        elseif ($Key -eq 'fingerprint') { $head.compatibility.powershell = '<private-invalid>' }
        $base = Invoke-ScoreRoundTrip $base
        $head = Invoke-ScoreRoundTrip $head
        $comparison = Compare-BenchmarkScore -Base $base -Head $head
        $comparison.Comparability | Should -Be $Expected
        $comparison.Markdown | Should -Match "Comparison identity: $Expected"
        $report = Get-BenchmarkReportMarkdown -Score $head -EarlierScore $base
        $report | Should -Match "Comparison identity: $Expected"
        $comparison.Markdown | Should -Match 'not an identity of the current checkout'
        $serialized = @($base, $head, $comparison.Markdown, $report) | ConvertTo-Json -Depth 12
        $serialized | Should -Not -Match 'private-before|private-after|private-invalid|must-not-survive|privateMetadata|<unsafe>'
        $head.source.squadSourceHash | Should -Be ('3' * 64)
        if ($Key -in 'powershell', 'runtime-missing', 'runtime-oversized') { $head.environment.powershell | Should -BeNullOrEmpty }
        else { $head.environment.powershell | Should -Be '7.6.0' }
        if ($Key -in 'legacy', 'legacy-trials') {
            $base.summary.allRequested | Should -BeNullOrEmpty
            $base.summary.quality | Should -Be 83
            $comparison.Markdown | Should -Match 'coverage unavailable'
            if ($Key -eq 'legacy') { $comparison.Markdown | Should -Match '\| unavailable \| requirements/build \| unavailable' }
            else { $comparison.Markdown | Should -Match '\| 1 \| requirements \| unavailable \| unavailable \| unavailable \|' }
        }
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
param($Mode, $TrialRoot, $SourceRoot, $InstallRoot, $Arm, $Pair, $MaxCredits, $ProgressPath, [switch]$Live, [switch]$IsolatedEnvironment, [switch]$ObservationOnly)
Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1') -Force
Write-EfficiencyProgress -Step 1 -Label 'Preparing workspace' -Path $ProgressPath
if ($env:FAKE_ENGINE_FAIL_PAIR -eq $Pair) { [Console]::Error.WriteLine('stand-in engine failure'); exit 1 }
New-Item -ItemType Directory -Path (Join-Path $TrialRoot 'out') -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'fake-run.json') (Join-Path $TrialRoot 'out/run.json')
Write-EfficiencyProgress -Step 7 -Label 'Saving run evidence' -Status finished -Path $ProgressPath
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
            $output | Should -Match '\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d[+-]\d\d:\d\d\] Installation finished; 2 runs'
            $output | Should -Match 'Run 1 of 2 started; 7 planned steps, 1 later runs'
            $output | Should -Match 'Step 1/7: Preparing workspace - started; 6 steps remaining'
            $output | Should -Match 'Step 7/7: Saving run evidence - finished; 0 steps remaining'
            $output | Should -Match 'Saved score.json.*0 steps remaining'
        }

        It 'leaves the saved score alone when no run produced one' {
            $path = Join-Path $script:Repo 'benchmarks/efficiency/score.json'
            Set-Content $path 'previous score'
            $env:FAKE_ENGINE_FAIL_PAIR = '1'
            $null = & pwsh -NoProfile -File $script:Runner -Runs 1 2>&1
            $LASTEXITCODE | Should -Be 1
            (Get-Content $path -Raw).Trim() | Should -Be 'previous score'
        }
        It 'automatically compares the replaced local score and tolerates unreadable earlier evidence' {
            $directory = Join-Path $script:Repo 'benchmarks/efficiency'
            $path = Join-Path $directory 'score.json'
            Copy-Item (New-ScoreFile -Name 'previous-local') $path -Force
            $previous = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
            $previous.summary.activity = @{ scribeDispatches = 11 }
            $previous | ConvertTo-Json -Depth 8 | Set-Content $path
            $live = Split-Path $script:Runner
            $run = New-RunResult
            $run.metrics.activity = @{ scribeDispatches = 1; scribeModelRequests = 7 }
            $run | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $live 'fake-run.json')
            $env:FAKE_ENGINE_FAIL_PAIR = $null
            $null = & pwsh -NoProfile -File $script:Runner -Runs 1 2>&1
            $LASTEXITCODE | Should -Be 0
            Get-Content (Join-Path $directory 'report.md') -Raw | Should -Match '\| Scribe dispatches \| 11 \| 1 \|'

            Set-Content $path '{bad-json'
            $output = & pwsh -NoProfile -File $script:Runner -Runs 1 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 0
            $output | Should -Match 'Earlier score could not be read'
            Get-Content (Join-Path $directory 'report.md') -Raw | Should -Match '\| Scribe dispatches \| unavailable \| 1 \|'
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
