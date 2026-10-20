#Requires -Modules Pester
#Requires -Version 7.5
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'BenchmarkResults.psm1') -Force
    $SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $TemplatePath = Join-Path $SourceRoot 'benchmarks/efficiency/records/run-20261019-222802-3624af24.json'
    $Prototype = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes($TemplatePath))
    $Policy = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $SourceRoot 'benchmarks/efficiency/policy.json')))
    $FrozenPaths = @('tests/tier2/live-benchmark/efficiency-scenario.json', 'tests/tier2/live-benchmark/EfficiencyBenchmark.psm1', 'tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1', 'tests/lib/SquadInstall.psm1', 'tests/tier2/live-benchmark/Test-EfficiencyTask.ps1', 'scripts/Test-SquadScribeOutput.ps1')

    function Copy-Value($Value) { ConvertFrom-BenchmarkJson ([Text.Encoding]::UTF8.GetBytes((ConvertTo-BenchmarkCanonicalJson $Value))) }
    function Invoke-TestGit([string]$Repo, [string[]]$GitArguments) {
        $Result = @(& git -C $Repo @GitArguments 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Fixture Git failure: $($Result -join ' ')" }
        $Result -join "`n"
    }
    function Write-TestJson([string]$Path, $Value) {
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
        [IO.File]::WriteAllText($Path, (ConvertTo-BenchmarkCanonicalJson $Value), [Text.UTF8Encoding]::new($false))
    }
    function Save-TestCommit([string]$Repo) {
        [void](Invoke-TestGit $Repo @('add', '.'))
        [void](Invoke-TestGit $Repo @('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'fixture'))
        Invoke-TestGit $Repo @('rev-parse', 'HEAD')
    }
    function New-TestRepository {
        $Repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($Repo)
        [void](Invoke-TestGit $Repo @('init', '--quiet', '-b', 'main'))
        foreach ($Path in $FrozenPaths) {
            $Destination = Join-Path $Repo $Path
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination))
            [IO.File]::Copy((Join-Path $SourceRoot $Path), $Destination)
        }
        [void][IO.Directory]::CreateDirectory((Join-Path $Repo 'squad-src'))
        [IO.File]::WriteAllText((Join-Path $Repo 'squad-src/charter.md'), 'original')
        $Revision = Save-TestCommit $Repo
        $Record = Copy-Value $Prototype
        $Record.seriesId = 'fixture-baseline'
        $Record.measuredRevision = $Revision
        $Record.sourceHash = Get-BenchmarkSourceHash $Repo $Revision
        $Compatibility = Copy-Value $Prototype.protocol
        $Compatibility.cli = 'GitHub Copilot CLI 1.0.101-0.'
        $Compatibility.roleModelPolicy = ''; $Compatibility.disabledMcpServers = ''
        $Record.protocol = Get-BenchmarkProtocol $Repo $Revision $Compatibility
        foreach ($Trial in $Record.trials) {
            $Trial.runId = [guid]::NewGuid().ToString()
            foreach ($Part in @('workflow', 'judge')) {
                foreach ($Field in $Trial[$Part].Keys | ForEach-Object { $_ }) { $Trial[$Part][$Field] = 100 }
                $Trial[$Part].failedTools = 0; $Trial[$Part].toolCalls = if ($Part -eq 'judge') { 0 } else { 100 }
            }
            foreach ($Field in $Trial.quality.Keys | ForEach-Object { $_ }) { $Trial.quality[$Field] = 20 }
            foreach ($Field in $Trial.outcomes.Keys | ForEach-Object { $_ }) { $Trial.outcomes[$Field] = $true }
            foreach ($Stage in $Trial.processes.Keys) { $Trial.processes[$Stage].exitCode = 0; $Trial.processes[$Stage].stopCause = 'none' }
            $Trial.criticalHighFindings = 0
        }
        @{ repository = $Repo; revision = $Revision; record = $Record; compatibility = $Compatibility }
    }
    function Save-TestSelection($Fixture, $Record) {
        $Root = Join-Path $Fixture.repository 'benchmarks/efficiency'
        $Path = Join-Path $Root "records/$($Record.seriesId).json"
        Write-TestJson $Path $Record
        Write-TestJson (Join-Path $Root 'current.json') @{ schemaVersion = 'benchmark-pointer-v1'; recordPath = "records/$($Record.seriesId).json"; sha256 = Get-BenchmarkDigest ([IO.File]::ReadAllBytes($Path)) }
        Write-TestJson (Join-Path $Root 'policy.json') $Policy
        Save-TestCommit $Fixture.repository
    }
    function New-TestCandidate($Record) {
        $Candidate = Copy-Value $Record
        $Candidate.seriesId = 'fixture-candidate'
        foreach ($Trial in $Candidate.trials) { $Trial.runId = [guid]::NewGuid().ToString() }
        $Candidate
    }
    function New-TestRawEvidence($Fixture) {
        $Runs = @(); $Directories = @()
        foreach ($Trial in $Fixture.record.trials) {
            $Directory = Join-Path $TestDrive ("raw-" + [guid]::NewGuid().ToString('N'))
            $Directories += $Directory
            $Hashes = @{}
            foreach ($Name in @('brd', 'prd', 'closingReview')) {
                $Relative = if ($Name -eq 'closingReview') { 'review.md' } else { "docs/requirements/$Name.md" }
                $Path = Join-Path $Directory "workspace/$Relative"
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
                [IO.File]::WriteAllText($Path, "$Name document")
                $Hashes[$Name] = (Get-FileHash $Path).Hash
            }
            $Metrics = @{
                complete = $true; credits = @{ complete = $true; used = 100 }; modelRequests = 1; toolCalls = 100
                totals = @{ inputTokens = 100; outputTokens = 100; cacheReadTokens = 100; cacheWriteTokens = 100 }
                coverage = @{ inputTokens = 1; outputTokens = 1; cacheReadTokens = 1; cacheWriteTokens = 1 }
                counts = @{ usage = 1; failures = 0 }; elapsedMs = 999
                evidence = @{ sha256 = ('a' * 64) }
                dispatches = @{ 'BRD Quality Reviewer' = 1; 'PRD Quality Reviewer' = 1 }
            }
            $JudgeMetrics = Copy-Value $Metrics; $JudgeMetrics.toolCalls = 0
            $Checks = @($Trial.outcomes.Keys | Where-Object { $_.StartsWith('functional/') } | ForEach-Object { @{ name = $_.Substring(11); passed = $true } })
            $WorkflowChecks = @{}
            foreach ($Key in $Trial.outcomes.Keys | Where-Object { $_.StartsWith('workflow/') }) { $WorkflowChecks[$Key.Substring(9)] = $true }
            $Stages = @(foreach ($Stage in @('init', 'requirements', 'build')) {
                $StageChecks = @{}
                foreach ($Key in $Trial.outcomes.Keys | Where-Object { $_.StartsWith("$Stage/") }) { $StageChecks[$Key.Substring($Stage.Length + 1)] = $true }
                @{ name = $Stage; passed = $true; process = @{ exitCode = 0; stopCause = 'none'; seconds = 2 }; readiness = @{ passed = $true; checks = $StageChecks }; metrics = $Metrics }
            })
            $Evidence = @{}; foreach ($Dimension in $Trial.quality.Keys) { $Evidence[$Dimension] = 'PRIVATE JUDGE EXPLANATION' }
            $Run = @{
                schemaVersion = 'squad-efficiency-v1'
                metadata = @{ runId = $Trial.runId; pair = $Trial.slot; revision = $Fixture.revision; sourceHash = $Fixture.record.sourceHash; compatibility = $Fixture.compatibility; started = $Trial.started; sessionId = 'PRIVATE SESSION' }
                collection = @{ recorded = $true; policy = 'baseline-observation-v1' }
                metrics = $Metrics; stages = $Stages; completed = $true
                acceptance = @{ passed = $true; checks = $Checks }
                workflow = @{ passed = $true; checks = $WorkflowChecks; reviewPath = 'review.md' }
                judge = @{ valid = $true; documentHashes = $Hashes; response = @{ scores = $Trial.quality; evidence = $Evidence; criticalHighFindings = 0; documentHashes = $Hashes }; metrics = $JudgeMetrics; process = @{ exitCode = 0; stopCause = 'none'; seconds = 3 } }
            }
            $Runs += $Run
            Write-TestJson (Join-Path $Directory 'out/run.json') $Run
        }
        $ControlPath = Join-Path $TestDrive ('controls-' + [guid]::NewGuid().ToString('N') + '.json')
        Write-TestJson $ControlPath @{ schemaVersion = 'efficiency-control-v1'; runs = $Runs }
        @{ control = $ControlPath; directories = $Directories; runs = $Runs }
    }
}

Describe 'Portable benchmark history and reporting' {
    It 'exports only validated numeric evidence and never overwrites a series' {
        $Fixture = New-TestRepository; $Raw = New-TestRawEvidence $Fixture
        $Record = Export-BenchmarkSeries -Repository $Fixture.repository -ControlPath $Raw.control -TrialDirectories $Raw.directories -SeriesId safe-series -SelectCurrent
        $Record.trials[0].workflow.requests | Should -Be 1
        $Record.trials[0].workflow.measuredProcessWallSeconds | Should -Be 6
        $Text = ConvertTo-BenchmarkCanonicalJson $Record
        $Text | Should -Not -Match 'PRIVATE|sessionId|reviewPath|evidence.*EXPLANATION'
        { Export-BenchmarkSeries -Repository $Fixture.repository -ControlPath $Raw.control -TrialDirectories $Raw.directories -SeriesId safe-series } | Should -Throw
    }
    It 'rejects original document changes and conflicting saved raw controls' {
        $Fixture = New-TestRepository; $Raw = New-TestRawEvidence $Fixture
        [IO.File]::WriteAllText((Join-Path $Raw.directories[0] 'workspace/review.md'), 'tampered')
        { Export-BenchmarkSeries -Repository $Fixture.repository -ControlPath $Raw.control -TrialDirectories $Raw.directories -SeriesId bad-series } | Should -Throw '*document-digest*'
        $Raw.runs[0].metrics.modelRequests = 2
        Write-TestJson $Raw.control @{ schemaVersion = 'efficiency-control-v1'; runs = $Raw.runs }
        { Export-BenchmarkSeries -Repository $Fixture.repository -ControlPath $Raw.control -TrialDirectories $Raw.directories -SeriesId bad-series } | Should -Throw '*raw-control-conflict*'
    }
    It 'rejects missing token coverage even when general telemetry says complete' {
        $Fixture = New-TestRepository; $Raw = New-TestRawEvidence $Fixture
        $Metrics = $Raw.runs[0].metrics
        $Metrics.totals.inputTokens = $null
        { Get-BenchmarkRawMetrics $Metrics 6 } | Should -Throw '*token-coverage*'
        $Metrics.totals.inputTokens = 100; $Metrics.coverage.inputTokens = 0
        { Get-BenchmarkRawMetrics $Metrics 6 } | Should -Throw '*token-coverage*'
    }
    It 'rejects unknown keys, invalid numbers, duplicate samples and oversized or duplicate-key JSON' {
        $Fixture = New-TestRepository
        $Bad = Copy-Value $Fixture.record; $Bad.secret = 'hidden'
        { Assert-BenchmarkSeries $Bad } | Should -Throw
        $Bad = Copy-Value $Fixture.record; $Bad.trials[0].workflow.requests = -1
        { Assert-BenchmarkSeries $Bad } | Should -Throw
        $Bad = Copy-Value $Fixture.record; $Bad.trials[1].runId = $Bad.trials[0].runId
        { Assert-BenchmarkSeries $Bad } | Should -Throw '*trial-id*'
        { ConvertFrom-BenchmarkJson ([Text.Encoding]::UTF8.GetBytes('{"a":1,"a":2}')) } | Should -Throw '*duplicate-json-key*'
        { ConvertFrom-BenchmarkJson ([byte[]]::new(262145)) } | Should -Throw '*json-size*'
    }
    It 'reports missing main explicitly and reads a stacked parent instead' {
        $Fixture = New-TestRepository
        $Base = Save-TestSelection $Fixture $Fixture.record
        (Compare-BranchBenchmark $Fixture.repository $Fixture.revision $Base).status | Should -Be 'missing-baseline'
        [void](Invoke-TestGit $Fixture.repository @('branch', 'integration', $Base))
        (Compare-BranchBenchmark $Fixture.repository 'integration' $Base).status | Should -Be 'unchanged'
    }
    It 'preserves immutable SHA comparisons when branch names move' {
        $Fixture = New-TestRepository; $Base = Save-TestSelection $Fixture $Fixture.record
        [void](Invoke-TestGit $Fixture.repository @('branch', 'parent', $Base))
        [IO.File]::WriteAllText((Join-Path $Fixture.repository 'squad-src/charter.md'), 'changed')
        $Moved = Save-TestCommit $Fixture.repository
        [void](Invoke-TestGit $Fixture.repository @('branch', '-f', 'parent', $Moved))
        (Compare-BranchBenchmark $Fixture.repository $Base $Base).status | Should -Be 'unchanged'
        (Compare-BranchBenchmark $Fixture.repository 'parent' $Moved).status | Should -Be 'stale-record'
    }
    It 'allows result-only commits but rejects changed source with inherited evidence' {
        $Fixture = New-TestRepository; $Base = Save-TestSelection $Fixture $Fixture.record
        [IO.File]::WriteAllText((Join-Path $Fixture.repository 'notes.txt'), 'metadata')
        $Head = Save-TestCommit $Fixture.repository
        (Compare-BranchBenchmark $Fixture.repository $Base $Head).status | Should -Be 'unchanged'
        [IO.File]::WriteAllText((Join-Path $Fixture.repository 'squad-src/charter.md'), 'changed')
        $Head = Save-TestCommit $Fixture.repository
        (Compare-BranchBenchmark $Fixture.repository $Base $Head).status | Should -Be 'stale-record'
    }
    It 'rejects protocol drift and measured revisions outside snapshot ancestry' {
        $Fixture = New-TestRepository; $Base = Save-TestSelection $Fixture $Fixture.record
        [IO.File]::AppendAllText((Join-Path $Fixture.repository $FrozenPaths[0]), 'drift')
        $Head = Save-TestCommit $Fixture.repository
        (Compare-BranchBenchmark $Fixture.repository $Base $Head).status | Should -Be 'stale-record'
        $Bad = Copy-Value $Fixture.record; $Bad.measuredRevision = ('1' * 40)
        $Head = Save-TestSelection $Fixture $Bad
        (Compare-BranchBenchmark $Fixture.repository $Base $Head).status | Should -Be 'stale-record'
    }
    It 'rejects historical edits even when a head pointer has a matching new hash' {
        $Fixture = New-TestRepository; $Base = Save-TestSelection $Fixture $Fixture.record
        $Modified = Copy-Value $Fixture.record; $Modified.trials[0].workflow.credits = 50
        $Head = Save-TestSelection $Fixture $Modified
        $Result = Compare-BranchBenchmark $Fixture.repository $Base $Head
        $Result.status | Should -Be 'invalid-record'
        $Result.reasons | Should -Contain 'historical-record-modified'
    }
    It 'rejects pointer traversal and source symlinks without executing candidate content' {
        $Fixture = New-TestRepository; $Base = Save-TestSelection $Fixture $Fixture.record
        $PointerPath = Join-Path $Fixture.repository 'benchmarks/efficiency/current.json'
        $Pointer = @{ schemaVersion = 'benchmark-pointer-v1'; recordPath = '../escape.json'; sha256 = ('a' * 64) }
        Write-TestJson $PointerPath $Pointer
        $Head = Save-TestCommit $Fixture.repository
        (Compare-BranchBenchmark $Fixture.repository $Base $Head).status | Should -Be 'invalid-record'
        if (-not $IsWindows) {
            [void](New-Item -ItemType SymbolicLink -Path (Join-Path $Fixture.repository 'squad-src/unsafe') -Target '/etc/passwd')
            $Head = Save-TestCommit $Fixture.repository
            { Get-BenchmarkSourceHash $Fixture.repository $Head } | Should -Throw '*unsupported-source-tree*'
        }
    }
    It 'rejects overlapping independently claimed series and reports protocol differences' {
        $Fixture = New-TestRepository; $Candidate = New-TestCandidate $Fixture.record
        $Candidate.trials[1].runId = $Fixture.record.trials[1].runId
        { Compare-BenchmarkSeries $Fixture.record $Candidate $Policy } | Should -Throw '*overlapping-independent-evidence*'
        $Candidate = New-TestCandidate $Fixture.record; $Candidate.protocol.model = 'different-model'
        { Compare-BenchmarkSeries $Fixture.record $Candidate $Policy } | Should -Throw '*incompatible:compatibility-model*'
    }
    It 'uses combined medians and base policy without requiring improvement' {
        $Fixture = New-TestRepository; $Base = Save-TestSelection $Fixture $Fixture.record
        $Candidate = New-TestCandidate $Fixture.record
        foreach ($Trial in $Candidate.trials) { $Trial.workflow.credits = 105; $Trial.judge.credits = 95 }
        $Head = Save-TestSelection $Fixture $Candidate
        Write-TestJson (Join-Path $Fixture.repository 'benchmarks/efficiency/policy.json') @{ arbitrary = 'head policy is not authoritative' }
        $Head = Save-TestCommit $Fixture.repository
        $Result = Compare-BranchBenchmark $Fixture.repository $Base $Head
        $Result.status | Should -Be 'no-regression'
        $Result.improvementScreen | Should -BeFalse
        foreach ($Trial in $Candidate.trials) { $Trial.workflow.credits = 116 }
        (Compare-BenchmarkSeries $Fixture.record $Candidate $Policy).status | Should -Be 'regression'
    }
    It 'separates a 10 percent improvement screen from quality and reliability gates' {
        $Fixture = New-TestRepository; $Candidate = New-TestCandidate $Fixture.record
        foreach ($Trial in $Candidate.trials) { $Trial.workflow.requests = 50; $Trial.judge.requests = 50; $Trial.quality.businessClarity = 19 }
        $Result = Compare-BenchmarkSeries $Fixture.record $Candidate $Policy
        $Result.improvementScreen | Should -BeTrue
        $Result.reasons | Should -Contain 'quality-businessClarity'
        $Result.status | Should -Be 'regression'
        $Candidate.trials[0].outcomes['init/stateVerifier'] = $false
        $Candidate.trials[0].outcomes['stage/init'] = $false; $Candidate.trials[0].outcomes.completed = $false
        (Compare-BenchmarkSeries $Fixture.record $Candidate $Policy).reasons | Should -Contain 'outcome-init/stateVerifier'
    }
    It 'counts an outlying failure and critical findings with sums not medians' {
        $Fixture = New-TestRepository; $Candidate = New-TestCandidate $Fixture.record
        $Candidate.trials[0].workflow.failedTools = 1; $Candidate.trials[0].criticalHighFindings = 1
        $Result = Compare-BenchmarkSeries $Fixture.record $Candidate $Policy
        $Result.headStatistics.resources.total.failedTools.median | Should -Be 0
        $Result.reasons | Should -Contain 'failed-tools-sum'
        $Result.reasons | Should -Contain 'critical-high-sum'
    }
    It 'does not divide by zero and leaves missing optional metrics unknown' {
        $Fixture = New-TestRepository; $Candidate = New-TestCandidate $Fixture.record
        foreach ($Trial in $Fixture.record.trials) { $Trial.workflow.credits = 0; $Trial.judge.credits = 0 }
        foreach ($Trial in $Candidate.trials) { $Trial.workflow.cacheReadTokens = $null }
        $Result = Compare-BenchmarkSeries $Fixture.record $Candidate $Policy
        $Result.status | Should -Be 'regression'
        $Result.deltas.credits.percent | Should -BeNullOrEmpty
        $Result.headStatistics.resources.total.cacheReadTokens | Should -BeNullOrEmpty
    }
    It 'writes safe report and amber SVG with acceptance counts rather than a green composite' {
        $Fixture = New-TestRepository; $Candidate = New-TestCandidate $Fixture.record
        $Candidate.trials[0].outcomes['init/stateVerifier'] = $false; $Candidate.trials[0].outcomes['stage/init'] = $false; $Candidate.trials[0].outcomes.completed = $false
        $Comparison = Compare-BenchmarkSeries $Fixture.record $Candidate $Policy
        $Report = @{ status = 'regression'; exitCode = 3; baseCommit = $Fixture.revision; headCommit = $Fixture.revision; mergeBase = $Fixture.revision; policyHash = ('a' * 64); baseRecord = $null; headRecord = $null; reasons = @('<script>|bad'); improvementScreen = $false; baseStatistics = $Comparison.baseStatistics; headStatistics = $Comparison.headStatistics }
        $Output = Join-Path $TestDrive 'render'
        Write-BenchmarkReport $Report $Output
        $Markdown = [IO.File]::ReadAllText((Join-Path $Output 'report.md'))
        $Markdown | Should -Match '&lt;script&gt;&#124;bad'
        $Svg = [IO.File]::ReadAllText((Join-Path $Output 'badge.svg'))
        ([xml]$Svg).svg.GetAttribute('aria-label') | Should -Match 'quality 100/100.*functional 3/3.*workflow 2/3'
        $Svg | Should -Match '#b45309'
        (Get-Item (Join-Path $Output 'report.json')).Length | Should -BeGreaterThan 0
        $Report.status = 'incompatible'; $Report.exitCode = 2
        Write-BenchmarkReport $Report $Output
        [IO.File]::ReadAllText((Join-Path $Output 'badge.svg')) | Should -Match '#6b7280.*benchmark unavailable'
    }
    It 'always emits reports before a nonzero CLI verdict and rejects unsafe refs' {
        $Fixture = New-TestRepository; $Base = Save-TestSelection $Fixture $Fixture.record
        $Output = Join-Path $TestDrive 'missing-report'
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Compare-BranchBenchmark.ps1') -Repository $Fixture.repository -BaseRef $Fixture.revision -HeadRef $Base -OutputDirectory $Output
        $LASTEXITCODE | Should -Be 2
        (ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $Output 'report.json')))).status | Should -Be 'missing-baseline'
        (Get-Item (Join-Path $Output 'badge.svg')).Length | Should -BeGreaterThan 0
        { Resolve-BenchmarkCommit $Fixture.repository '--help' } | Should -Throw '*unsafe-ref*'
    }
    It 'keeps the report workflow read-only with verified base execution and bootstrap failure' {
        $Workflow = [IO.File]::ReadAllText((Join-Path $SourceRoot '.github/workflows/efficiency-comparison.yml'))
        $Workflow | Should -Match 'contents: read'
        $Workflow | Should -Not -Match 'pull_request_target|secrets\.|contents: write|COPILOT_'
        $Workflow | Should -Match 'ref: \$\{\{ steps.refs.outputs.base \}\}'
        $Workflow | Should -Match 'persist-credentials: false'
        $Workflow | Should -Match 'base-comparison-tooling-unavailable'
        $Workflow | Should -Match 'FETCH_HEAD'
        $Workflow | Should -Match 'if: always\(\)'
        $Readme = [IO.File]::ReadAllText((Join-Path $SourceRoot 'README.md'))
        $Readme | Should -Match '\]\(benchmarks/efficiency/badge.svg\)\]\(benchmarks/efficiency/report.md\)'
    }
}
