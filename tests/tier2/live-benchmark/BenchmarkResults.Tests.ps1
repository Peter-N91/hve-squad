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
    $FrozenPaths = @('tests/tier2/live-benchmark/efficiency-scenario.json', 'tests/tier2/live-benchmark/EfficiencyBenchmark.psm1', 'tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1', 'tests/lib/SquadInstall.psm1', 'tests/tier2/live-benchmark/Test-EfficiencyTask.ps1', 'scripts/Test-SquadScribeOutput.ps1', 'scripts/Build-SquadPlugin.ps1')

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
        $Record.schemaVersion = 'benchmark-series-v2'
        $Record.provenance.collector = 'benchmark-export-v2'
        $Record.provenance.verifierHashBasis = 'executing-file-verified-against-measured-git'
        $Record.seriesId = 'fixture-baseline'
        $Record.measuredRevision = $Revision
        $Record.sourceHash = Get-BenchmarkSourceHash $Repo $Revision
        $Compatibility = Copy-Value $Prototype.protocol
        $Compatibility.cli = 'GitHub Copilot CLI 1.0.101-0.'
        $Compatibility.roleModelPolicy = ''; $Compatibility.disabledMcpServers = ''
        $ProtocolFields = @('scenarioHash', 'parserHash', 'exerciseHash', 'preparationHash', 'graderHash', 'verifierHash', 'converterHash')
        for ($Index = 0; $Index -lt $FrozenPaths.Count; $Index++) {
            $Compatibility[$ProtocolFields[$Index]] = (Get-FileHash -LiteralPath (Join-Path $Repo $FrozenPaths[$Index])).Hash.ToLowerInvariant()
        }
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
                metadata = @{ runId = $Trial.runId; arm = 'baseline'; pair = $Trial.slot; revision = $Fixture.revision; sourceHash = $Fixture.record.sourceHash; compatibility = $Fixture.compatibility; started = $Trial.started; sessionId = 'PRIVATE SESSION' }
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
    It 'historically permits only the five disclosed environment differences without normalizing records' {
        $Fixture = New-TestRepository; $Candidate = New-TestCandidate $Fixture.record
        $Changes = @{ installHash = ('b' * 64); powershell = '99.0.0'; cliVersion = '9.9.9'; maxCredits = 600; roleModelPolicyHash = ('c' * 64) }
        foreach ($Key in $Changes.Keys) { $Candidate.protocol[$Key] = $Changes[$Key] }
        $Before = ConvertTo-BenchmarkCanonicalJson $Fixture.record
        $After = ConvertTo-BenchmarkCanonicalJson $Candidate
        { Compare-BenchmarkSeries $Fixture.record $Candidate $Policy } | Should -Throw '*compatibility-*'
        { Compare-BenchmarkSeries $Fixture.record $Candidate $Policy -DeploymentComparison } | Should -Throw '*compatibility-*'
        $Comparison = Compare-BenchmarkSeries $Fixture.record $Candidate $Policy -HistoricalReference
        $Comparison.exitCode | Should -Be 0
        $Comparison.protocolDifferences.Count | Should -Be 5
        foreach ($Key in $Changes.Keys) {
            $Comparison.protocolDifferences[$Key].old | Should -BeExactly $Fixture.record.protocol[$Key]
            $Comparison.protocolDifferences[$Key].new | Should -BeExactly $Changes[$Key]
        }
        $Report = Compare-BranchBenchmark $Fixture.repository main
        foreach ($Key in $Comparison.Keys) { $Report[$Key] = $Comparison[$Key] }
        $Output = Join-Path $TestDrive 'historical-report'
        Write-BenchmarkReport $Report $Output
        $Json = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $Output 'report.json')))
        $Json.comparisonWarning | Should -Match 'Approximate historical'
        $Markdown = [IO.File]::ReadAllText((Join-Path $Output 'report.md'))
        foreach ($Key in $Changes.Keys) {
            $Markdown | Should -Match ([regex]::Escape([string]$Changes[$Key]))
            $Markdown | Should -Match ([regex]::Escape([string]$Fixture.record.protocol[$Key]))
        }
        (ConvertTo-BenchmarkCanonicalJson $Fixture.record) | Should -BeExactly $Before
        (ConvertTo-BenchmarkCanonicalJson $Candidate) | Should -BeExactly $After
        $SameProtocol = New-TestCandidate $Fixture.record
        (Compare-BenchmarkSeries $Fixture.record $SameProtocol $Policy -HistoricalReference).comparisonWarning | Should -Match 'Approximate historical'
        $InstallOnly = New-TestCandidate $Fixture.record; $InstallOnly.protocol.installHash = 'b' * 64
        (Compare-BenchmarkSeries $Fixture.record $InstallOnly $Policy -DeploymentComparison).exitCode | Should -Be 0
    }
    It 'historically rejects every non-allowlisted protocol difference with unchanged regression reducers' {
        $Fixture = New-TestRepository
        foreach ($Key in $Fixture.record.protocol.Keys | Where-Object { $_ -cnotin @('installHash', 'powershell', 'cliVersion', 'maxCredits', 'roleModelPolicyHash') }) {
            $Candidate = New-TestCandidate $Fixture.record
            $Candidate.protocol[$Key] = if ($Candidate.protocol[$Key] -is [ValueType]) { $Candidate.protocol[$Key] + 1 }
                elseif ($Key.EndsWith('Hash')) { '0' * 64 } else { 'different-protocol' }
            { Compare-BenchmarkSeries $Fixture.record $Candidate $Policy -HistoricalReference } | Should -Throw
        }
    }
    It 'exports only validated numeric evidence and never overwrites a series' {
        $Fixture = New-TestRepository; $Raw = New-TestRawEvidence $Fixture
        $Record = Export-BenchmarkSeries -Repository $Fixture.repository -ControlPath $Raw.control -TrialDirectories $Raw.directories -SeriesId safe-series -SelectCurrent
        $Record.trials[0].workflow.requests | Should -Be 1
        $Record.trials[0].workflow.measuredProcessWallSeconds | Should -Be 6
        $Text = ConvertTo-BenchmarkCanonicalJson $Record
        $Text | Should -Not -Match 'PRIVATE|sessionId|reviewPath|evidence.*EXPLANATION'
        { Export-BenchmarkSeries -Repository $Fixture.repository -ControlPath $Raw.control -TrialDirectories $Raw.directories -SeriesId safe-series } | Should -Throw
        $Original = @($Raw.runs | ForEach-Object { Copy-Value $_ })
        for ($Index = 0; $Index -lt 3; $Index++) {
            $Raw.runs[$Index].metadata.arm = 'candidate'
            $Raw.runs[$Index].metadata.runId = [guid]::NewGuid().ToString()
            Write-TestJson (Join-Path $Raw.directories[$Index] 'out/run.json') $Raw.runs[$Index]
        }
        Write-TestJson $Raw.control @{ runs = @($Original) + @($Raw.runs) }
        $Candidate = Export-BenchmarkSeries -Repository $Fixture.repository -ControlPath $Raw.control -TrialDirectories $Raw.directories -SeriesId native-candidate
        $Candidate.trials.Count | Should -Be 3
        $Candidate.trials.runId | Should -Be $Raw.runs.metadata.runId
        $Raw.runs[1].metadata.arm = 'baseline'
        Write-TestJson $Raw.control @{ runs = @($Original) + @($Raw.runs) }
        { Export-BenchmarkSeries -Repository $Fixture.repository -ControlPath $Raw.control -TrialDirectories $Raw.directories -SeriesId mixed-candidate } | Should -Throw '*native-series-slots*'
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
        $Bad = Copy-Value $Fixture.record; $Bad.trials[0].runId = 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA'
        { Assert-BenchmarkSeries $Bad } | Should -Throw '*trial-id*'
        $Bad = Copy-Value $Fixture.record; $Bad.trials[0].runId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        $Bad.trials[1].runId = $Bad.trials[0].runId.ToUpperInvariant()
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
    It 'rejects converter-only drift with inherited evidence and unchanged squad source' {
        $Fixture = New-TestRepository; $Base = Save-TestSelection $Fixture $Fixture.record
        [IO.File]::AppendAllText((Join-Path $Fixture.repository 'scripts/Build-SquadPlugin.ps1'), "`n# converter drift")
        $Head = Save-TestCommit $Fixture.repository
        (Get-BenchmarkSourceHash $Fixture.repository $Head) | Should -Be $Fixture.record.sourceHash
        $Report = Compare-BranchBenchmark $Fixture.repository $Base $Head
        $Report.status | Should -Be 'stale-record'
        $Report.reasons | Should -Contain 'protocol-converterHash'
    }
    It 'requires measured digests for both the executing verifier and selected converter during export' -ForEach @(
        @{ Digest = 'verifierHash' }, @{ Digest = 'converterHash' }
    ) {
        $Fixture = New-TestRepository; $Raw = New-TestRawEvidence $Fixture
        foreach ($Run in $Raw.runs) { $Run.metadata.compatibility[$Digest] = '0' * 64 }
        foreach ($Index in 0..2) { Write-TestJson (Join-Path $Raw.directories[$Index] 'out/run.json') $Raw.runs[$Index] }
        Write-TestJson $Raw.control @{ schemaVersion = 'efficiency-control-v1'; runs = $Raw.runs }
        { Export-BenchmarkSeries -Repository $Fixture.repository -ControlPath $Raw.control -TrialDirectories $Raw.directories -SeriesId bad-execution } |
            Should -Throw '*measured-protocol-mismatch*'
    }
    It 'reads legacy records historically but explicitly refuses them as current snapshot evidence' {
        $Fixture = New-TestRepository
        $Legacy = Copy-Value $Fixture.record
        $Legacy.schemaVersion = 'benchmark-series-v1'
        $Legacy.provenance.collector = 'benchmark-export-v1'
        $Legacy.provenance.verifierHashBasis = 'measured-git-revision'
        [void]$Legacy.protocol.Remove('converterHash')
        { Assert-BenchmarkHistoricalSeries $Fixture.repository $Legacy } | Should -Not -Throw
        $Head = Save-TestSelection $Fixture $Legacy
        $Report = Compare-BranchBenchmark $Fixture.repository $Head $Head
        $Report.status | Should -Be 'stale-record'
        $Report.reasons | Should -Contain 'unbound-execution-protocol'
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
        $Fixture = New-TestRepository
        $Fixture.record.trials[0].runId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        $Candidate = New-TestCandidate $Fixture.record
        $Candidate.trials[1].runId = $Fixture.record.trials[1].runId
        { Compare-BenchmarkSeries $Fixture.record $Candidate $Policy } | Should -Throw '*overlapping-independent-evidence*'
        { Compare-BenchmarkSeries $Fixture.record $Candidate $Policy -HistoricalReference } | Should -Throw '*overlapping-independent-evidence*'
        $Candidate = New-TestCandidate $Fixture.record; $Candidate.protocol.model = 'different-model'
        { Compare-BenchmarkSeries $Fixture.record $Candidate $Policy } | Should -Throw '*incompatible:compatibility-model*'
        $Candidate = New-TestCandidate $Fixture.record
        $Candidate.trials[0].runId = $Fixture.record.trials[0].runId.ToUpperInvariant()
        { Compare-BenchmarkSeries $Fixture.record $Candidate $Policy } | Should -Throw '*trial-id*'
        $Base = Save-TestSelection $Fixture $Fixture.record
        $Head = Save-TestSelection $Fixture $Candidate
        $Result = Compare-BranchBenchmark $Fixture.repository $Base $Head
        $Result.status | Should -Be 'invalid-record'
        $Result.exitCode | Should -Be 2
        $Result.reasons | Should -Contain 'trial-id'
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
        (Compare-BenchmarkSeries $Fixture.record $Candidate $Policy -HistoricalReference).status | Should -Be 'no-regression'
        foreach ($Trial in $Candidate.trials) { $Trial.workflow.credits = 115 }
        (Compare-BenchmarkSeries $Fixture.record $Candidate $Policy -HistoricalReference).status | Should -Be 'no-regression'
        foreach ($Trial in $Candidate.trials) { $Trial.workflow.credits = 116 }
        (Compare-BenchmarkSeries $Fixture.record $Candidate $Policy).status | Should -Be 'regression'
        (Compare-BenchmarkSeries $Fixture.record $Candidate $Policy -HistoricalReference).status | Should -Be 'regression'
    }
    It 'separates a 10 percent improvement screen from quality and reliability gates' {
        $Fixture = New-TestRepository; $Candidate = New-TestCandidate $Fixture.record
        foreach ($Trial in $Candidate.trials) { $Trial.workflow.requests = 50; $Trial.judge.requests = 50; $Trial.quality.businessClarity = 19 }
        $Result = Compare-BenchmarkSeries $Fixture.record $Candidate $Policy
        $Result.improvementScreen | Should -BeTrue
        $Result.reasons | Should -Contain 'quality-businessClarity'
        $Result.status | Should -Be 'regression'
        $HistoricalResult = Compare-BenchmarkSeries $Fixture.record $Candidate $Policy -HistoricalReference
        $HistoricalResult.improvementScreen | Should -BeTrue
        $HistoricalResult.reasons | Should -Contain 'quality-businessClarity'
        $HistoricalResult.status | Should -Be 'regression'
        $Candidate.trials[0].outcomes['init/stateVerifier'] = $false
        $Candidate.trials[0].outcomes['stage/init'] = $false; $Candidate.trials[0].outcomes.completed = $false
        (Compare-BenchmarkSeries $Fixture.record $Candidate $Policy).reasons | Should -Contain 'outcome-init/stateVerifier'
        (Compare-BenchmarkSeries $Fixture.record $Candidate $Policy -HistoricalReference).reasons | Should -Contain 'outcome-init/stateVerifier'
    }
    It 'counts an outlying failure and critical findings with sums not medians' {
        $Fixture = New-TestRepository; $Candidate = New-TestCandidate $Fixture.record
        $Candidate.trials[0].workflow.failedTools = 1; $Candidate.trials[0].criticalHighFindings = 1
        $Result = Compare-BenchmarkSeries $Fixture.record $Candidate $Policy
        $Result.headStatistics.resources.total.failedTools.median | Should -Be 0
        $Result.reasons | Should -Contain 'failed-tools-sum'
        $Result.reasons | Should -Contain 'critical-high-sum'
        $HistoricalResult = Compare-BenchmarkSeries $Fixture.record $Candidate $Policy -HistoricalReference
        $HistoricalResult.headStatistics.resources.total.failedTools.median | Should -Be 0
        $HistoricalResult.reasons | Should -Contain 'failed-tools-sum'
        $HistoricalResult.reasons | Should -Contain 'critical-high-sum'
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
        foreach ($Trial in $Candidate.trials) {
            $Trial.workflow.measuredProcessWallSeconds = 80
            $Trial.workflow.credits = 105
            $Trial.workflow.inputTokens = 1234567
            $Trial.quality.businessClarity = 19
        }
        $Candidate.trials[2].workflow.measuredProcessWallSeconds = 240
        $Comparison = Compare-BenchmarkSeries $Fixture.record $Candidate $Policy
        $Report = @{ status = 'regression'; exitCode = 3; baseCommit = $Fixture.revision; headCommit = $Fixture.revision; mergeBase = $Fixture.revision; policyHash = ('a' * 64); baseRecord = $null; headRecord = $null; reasons = @($Comparison.reasons) + @('<script>|bad'); deltas = $Comparison.deltas; improvementScreen = $false; baseStatistics = $Comparison.baseStatistics; headStatistics = $Comparison.headStatistics }
        $Output = Join-Path $TestDrive 'render'
        Write-BenchmarkReport $Report $Output
        $Markdown = [IO.File]::ReadAllText((Join-Path $Output 'report.md'))
        $Markdown | Should -Match '&lt;script&gt;&#124;bad'
        $Markdown | Should -Match 'Measured benchmark time per trial.*3 min 20 s.*3 min 0 s.*10.00% faster'
        $Markdown | Should -Match 'Consumption per trial.*200.00.*205.00.*2.50% higher'
        $Markdown | Should -Match 'Input tokens per trial.*1,234,667'
        $Markdown | Should -Match 'Initialization: State verification passed in fewer trials'
        $Markdown | Should -Match 'Business clarity scored lower'
        $Markdown.IndexOf('## Performance and consumption') | Should -BeLessThan $Markdown.IndexOf('<summary>All measurements, samples and checks</summary>')
        $Markdown | Should -Match '<summary>Provenance, compatibility and machine status</summary>'
        $Json = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $Output 'report.json')))
        (ConvertTo-BenchmarkCanonicalJson $Json) | Should -BeExactly (ConvertTo-BenchmarkCanonicalJson $Report)
        $Svg = [IO.File]::ReadAllText((Join-Path $Output 'badge.svg'))
        ([xml]$Svg).svg.GetAttribute('aria-label') | Should -Match 'doc quality 99/100.*functional 3/3.*workflow 2/3'
        ([xml]$Svg).svg.GetAttribute('aria-label') | Should -Match 'avg benchmark time 3 min 53.3 s'
        $Markdown | Should -Match 'Observed total consumption per accepted workflow: Baseline: 200.00; Candidate: 307.50'
        $Markdown | Should -Match 'not delivered software quality'
        $Markdown | Should -Match 'Pure agent latency and whole-wizard duration are not measured'
        $Svg | Should -Match '#b45309'
        (Get-Item (Join-Path $Output 'report.json')).Length | Should -BeGreaterThan 0
        $Report.status = 'incompatible'; $Report.exitCode = 2
        Write-BenchmarkReport $Report $Output
        $Unavailable = [IO.File]::ReadAllText((Join-Path $Output 'badge.svg'))
        $Unavailable | Should -Match '#6b7280.*benchmark unavailable'
        $Unavailable | Should -Not -Match 'avg benchmark time'
    }
    It 'summarizes recorded observations without implying a baseline comparison' {
        $Fixture = New-TestRepository
        $Fixture.record.trials[0].outcomes['functional/id-boundary-preserves-store'] = $false
        $Fixture.record.trials[0].outcomes.functional = $false
        foreach ($Trial in $Fixture.record.trials) {
            $Trial.outcomes['requirements/BRD Quality Reviewer'] = $false
            $Trial.outcomes['stage/requirements'] = $false
            $Trial.outcomes.completed = $false
        }
        $Output = Join-Path $TestDrive 'recorded-summary'
        Write-BenchmarkSeriesReport $Fixture.record $Output
        $Markdown = [IO.File]::ReadAllText((Join-Path $Output 'report.md'))
        $Summary = ($Markdown -split '<details>', 2)[0]
        $Summary | Should -Match 'Recorded observations; no comparison yet'
        $Summary | Should -Match '\| Measure \| Recorded result \|'
        $Summary | Should -Not -Match '\| Baseline \||\| Candidate \||n/a|10% resource-improvement screen'
        $Summary | Should -Match 'Functional acceptance.*2 of 3 trials'
        $Summary | Should -Match 'ID boundary preserves stored data.*2 of 3'
        $Summary | Should -Match 'Full workflow acceptance.*0 of 3 trials'
        $Summary | Should -Match 'BRD reviewer deliverable acceptance.*0 of 3'
        $Summary | Should -Match 'Unavailable \(0 accepted workflows\)'
        $Markdown | Should -Not -Match '&quot;cliVersion'
        $Markdown | Should -Match '\| cliVersion \|'
    }
    It 'reduces stage-plus-judge samples before taking the combined median' {
        $Fixture = New-TestRepository
        $StageSeconds = @(1, 2, 100); $JudgeSeconds = @(100, 2, 1)
        for ($Index = 0; $Index -lt 3; $Index++) {
            $Fixture.record.trials[$Index].workflow.measuredProcessWallSeconds = $StageSeconds[$Index]
            $Fixture.record.trials[$Index].judge.measuredProcessWallSeconds = $JudgeSeconds[$Index]
        }
        $Output = Join-Path $TestDrive 'timing-boundaries'
        Write-BenchmarkSeriesReport $Fixture.record $Output
        $Report = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $Output 'report.json')))
        $Report.headStatistics.resources.total.measuredProcessWallSeconds.median | Should -Be 101
        $Report.headStatistics.resources.workflow.measuredProcessWallSeconds.median | Should -Be 2
        $Report.headStatistics.resources.judge.measuredProcessWallSeconds.median | Should -Be 2
        $Markdown = [IO.File]::ReadAllText((Join-Path $Output 'report.md'))
        $Markdown | Should -Match 'Workflow-stage wall time \(includes harness checks\).*2 s'
        $Markdown | Should -Match 'Independent-judge time.*2 s'
        $Markdown | Should -Match 'Measured benchmark time per trial.*1 min 41 s'
        ([xml][IO.File]::ReadAllText((Join-Path $Output 'badge.svg'))).svg.GetAttribute('aria-label') | Should -Match 'avg benchmark time 1 min 8.7 s'
    }
    It 'always emits reports before a nonzero CLI verdict and rejects unsafe refs' {
        $Fixture = New-TestRepository; $Base = Save-TestSelection $Fixture $Fixture.record
        $Output = Join-Path $TestDrive 'missing-report'
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Compare-BranchBenchmark.ps1') -Repository $Fixture.repository -BaseRef $Fixture.revision -HeadRef $Base -OutputDirectory $Output
        $LASTEXITCODE | Should -Be 2
        [IO.File]::ReadAllText((Join-Path $Output 'report.md')) | Should -Match 'Comparison unavailable.*[\s\S]*No comparable measurements are available'
        [IO.File]::ReadAllText((Join-Path $Output 'report.md')) | Should -Match 'The baseline branch has no selected benchmark record'
        (ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $Output 'report.json')))).status | Should -Be 'missing-baseline'
        (Get-Item (Join-Path $Output 'badge.svg')).Length | Should -BeGreaterThan 0
        { Resolve-BenchmarkCommit $Fixture.repository '--help' } | Should -Throw '*unsafe-ref*'
    }
    It 'keeps the report workflow read-only with verified base execution and bootstrap failure' {
        $Workflow = [IO.File]::ReadAllText((Join-Path $SourceRoot '.github/workflows/tier2-benchmark.yml'))
        $Workflow | Should -Match 'contents: read'
        $Workflow | Should -Not -Match 'pull_request_target|contents: write'
        $Workflow | Should -Match 'ref: \$\{\{ steps.refs.outputs.controller \}\}'
        $Workflow | Should -Match 'COPILOT_GITHUB_TOKEN: \$\{\{ secrets.COPILOT_GITHUB_TOKEN \}\}'
        $Workflow | Should -Match 'persist-credentials: false'
        $Workflow | Should -Match 'base-comparison-tooling-unavailable'
        $Workflow | Should -Match 'FETCH_HEAD'
        $Workflow | Should -Match 'if: always\(\)'
        $Workflow | Should -Not -Match 'pull_request|(?m)^  (push|schedule):'
        $Workflow | Should -Not -Match '(?m)^  release:'
        $Workflow | Should -Match 'workflow_dispatch:'
        $Workflow | Should -Match 'workflow_call:'
        $Release = [IO.File]::ReadAllText((Join-Path $SourceRoot '.github/workflows/release.yml'))
        $Release | Should -Match 'needs: \[candidate, benchmark\]'
        $Release | Should -Match 'uses: ./\.github/workflows/tier2-benchmark.yml'
        $Readme = [IO.File]::ReadAllText((Join-Path $SourceRoot 'README.md'))
        $Readme | Should -Match '\]\(benchmarks/efficiency/badge.svg\)\]\(benchmarks/efficiency/report.md\)'
    }
}

Describe 'Pre-release benchmark gate' {
    BeforeAll {
        $Release = [IO.File]::ReadAllText((Join-Path $SourceRoot '.github/workflows/release.yml'))
        $Expression = [regex]::Match($Release, '(?s)  release:\s+name: Create Release.*?if: >\r?\n(?<condition>.*?)    permissions:').Groups['condition'].Value.Trim()
        $Expression = $Expression.Replace('always()', '$true').Replace('!cancelled()', '$true').
            Replace('needs.candidate.result', '$Candidate').Replace('needs.benchmark.result', '$Benchmark').
            Replace('github.event_name', '$Event').Replace('inputs.run_benchmark', '$Enabled').
            Replace('==', '-eq').Replace('&&', '-and').Replace('||', '-or').Replace('false', '$false')
        $Gate = [scriptblock]::Create($Expression)
        $InputBlock = [regex]::Match($Release, '(?ms)^      run_benchmark:\r?\n(?<body>.*?)(?=^ {0,6}\S|\z)').Groups['body'].Value
        $Default = [regex]::Match($InputBlock, '(?m)^        default: (true|false)\s*$')
        if (-not $Default.Success -or $InputBlock -notmatch '(?m)^        type: boolean\s*$') {
            throw 'run_benchmark must declare an explicit boolean default.'
        }
        $ConfiguredDefault = $Default.Groups[1].Value -ceq 'true'
        $BenchmarkCondition = [regex]::Match($Release, '(?ms)^  benchmark:\r?\n.*?^    if: ([^\r\n]+)').Groups[1].Value
        if (-not $BenchmarkCondition) { throw 'Missing benchmark admission condition.' }
        $TagExists = $false
        $Admission = [scriptblock]::Create($BenchmarkCondition.Replace("needs.candidate.outputs.tag_exists == 'false'", '(-not $TagExists)').Replace('github.event_name', '$Event').
            Replace('inputs.run_benchmark', '$Enabled').Replace('!=', '-ne').Replace('||', '-or').Replace('&&', '-and').Replace('false', '$false'))
    }
    It 'permits publication only for a passed gate or an explicitly skipped manual gate: <Event>/<Benchmark>/<Enabled>' -ForEach @(
        @{ Event='push'; Candidate='success'; Benchmark='success'; Enabled=$false; Expected=$true }
        @{ Event='push'; Candidate='success'; Benchmark='failure'; Enabled=$false; Expected=$false }
        @{ Event='push'; Candidate='success'; Benchmark='skipped'; Enabled=$false; Expected=$false }
        @{ Event='workflow_dispatch'; Candidate='success'; Benchmark='success'; Enabled=$true; Expected=$true }
        @{ Event='workflow_dispatch'; Candidate='success'; Benchmark='failure'; Enabled=$true; Expected=$false }
        @{ Event='workflow_dispatch'; Candidate='success'; Benchmark='cancelled'; Enabled=$true; Expected=$false }
        @{ Event='workflow_dispatch'; Candidate='success'; Benchmark='skipped'; Enabled=$true; Expected=$false }
        @{ Event='workflow_dispatch'; Candidate='success'; Benchmark='skipped'; Enabled=$false; Expected=$true }
        @{ Event='workflow_dispatch'; Candidate='failure'; Benchmark='skipped'; Enabled=$false; Expected=$false }
    ) {
        (& $Gate) | Should -Be $Expected
    }
    It 'honors manual selection and keeps automatic releases gated regardless of the configured default' {
        foreach ($Event in @('push', 'workflow_dispatch')) {
            foreach ($Enabled in @($false, $true)) {
                (& $Admission) | Should -Be ($Event -eq 'push' -or $Enabled)
            }
        }
        $Event = 'workflow_dispatch'; $Enabled = $ConfiguredDefault
        (& $Admission) | Should -Be $ConfiguredDefault
        $Candidate = 'success'
        $Benchmark = if ($ConfiguredDefault) { 'success' } else { 'skipped' }
        (& $Gate) | Should -BeTrue
        $Event = 'push'; $Benchmark = 'skipped'
        (& $Gate) | Should -BeFalse
        $TagExists = $true
        (& $Admission) | Should -BeFalse
    }
    It 'freezes the same candidate before writes and lets Release Prep inherit the Release default' {
        $Release | Should -Match 'candidate_sha: \$\{\{ needs.candidate.outputs.sha \}\}'
        $Release | Should -Match 'ref: \$\{\{ needs.candidate.outputs.sha \}\}'
        $Release | Should -Match 'Benchmark gate explicitly disabled'
        $Release | Should -Not -Match 'benchmark_tag|Benchmark published release'
        $Prep = [IO.File]::ReadAllText((Join-Path $SourceRoot '.github/workflows/release-prep.yml'))
        $Prep | Should -Not -Match '(?m)^      run_benchmark:'
        $Dispatch = [regex]::Match($Prep, '(?m)^\s+gh workflow run release\.yml .+$').Value
        $Dispatch | Should -Match ([regex]::Escape('-f ref="$REF"'))
        $Dispatch | Should -Match '-f run_benchmark=true'
        $Dispatch | Should -Not -Match 'refresh_reference=true'
    }
}

Describe 'Release benchmark event identities' {
    BeforeAll {
        $WorkflowText = [IO.File]::ReadAllText((Join-Path $SourceRoot '.github/workflows/tier2-recorded-benchmark.yml'))
        function Get-WorkflowRun([string]$Name, [string]$Text = $WorkflowText) {
            $Step = [regex]::Match($Text, '(?ms)^      - name: ' + [regex]::Escape($Name) + '\r?\n(.*?)(?=^      - name:|\z)').Groups[1].Value
            $Body = [regex]::Match($Step, '(?ms)^        run: \|\r?\n(.*)').Groups[1].Value
            if (-not $Body) { throw "Missing workflow script: $Name" }
            [scriptblock]::Create(($Body -replace '(?m)^          ', ''))
        }
        $ResolveRelease = Get-WorkflowRun 'Validate immutable event identities'
        $MissingBaseline = Get-WorkflowRun 'Compare or report missing baseline tooling'
        $Bootstrap = Get-WorkflowRun 'Apply temporary release baseline bootstrap' ([IO.File]::ReadAllText((Join-Path $SourceRoot '.github/workflows/tier2-benchmark.yml')))
    }
    BeforeEach {
        $SavedEnvironment = @{}
        foreach ($Name in @('GITHUB_REPOSITORY', 'GITHUB_API_URL', 'GITHUB_OUTPUT', 'GITHUB_EVENT_PATH', 'GITHUB_EVENT_NAME', 'GH_TOKEN', 'RELEASE_TAG', 'CANDIDATE_SHA', 'SELECTED_BRANCH', 'RUNNER_TEMP', 'BASE_SHA', 'HEAD_SHA', 'VERDICT', 'GITHUB_STEP_SUMMARY', 'COLLECTION_REQUIRED')) {
            $SavedEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name)
        }
        $env:GITHUB_REPOSITORY = 'fixture/benchmark'
        $env:GITHUB_API_URL = 'https://api.github.invalid'
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'release-outputs'
        $env:GITHUB_EVENT_PATH = Join-Path $TestDrive 'release-event.json'
        $env:GH_TOKEN = 'fixture-only'
        $env:GITHUB_EVENT_NAME = 'workflow_call'
        $env:RELEASE_TAG = 'v2'
        $env:CANDIDATE_SHA = ''
        $env:COLLECTION_REQUIRED = ''
        $env:SELECTED_BRANCH = 'feature/test'
        [IO.File]::WriteAllText($env:GITHUB_OUTPUT, '')
        $CurrentRelease = @{ id = 20; tag_name = 'v2'; draft = $false; prerelease = $false; published_at = '2026-10-20T00:00:00Z' }
        $PriorRelease = @{ id = 10; tag_name = 'v1'; draft = $false; prerelease = $false; published_at = '2026-10-18T00:00:00Z' }
        $script:ReleaseApi = @{
            'releases/tags/v2' = $CurrentRelease
            'git/ref/tags/v2' = @{ object = @{ type = 'tag'; sha = ('c' * 40) } }
            "git/tags/$('c' * 40)" = @{ object = @{ type = 'commit'; sha = ('2' * 40) } }
            'releases?per_page=100&page=1' = @(
                $CurrentRelease, $PriorRelease
                @{ id = 15; tag_name = 'unrelated-hotfix'; draft = $false; prerelease = $false; published_at = '2026-10-19T00:00:00Z' }
                @{ id = 19; tag_name = 'rolling-preview'; draft = $false; prerelease = $true; published_at = '2026-10-19T00:00:00Z' }
                @{ id = 18; tag_name = 'draft'; draft = $true; prerelease = $false; published_at = '2026-10-19T00:00:00Z' }
                @{ id = 30; tag_name = 'future-release'; draft = $false; prerelease = $false; published_at = '2026-10-21T00:00:00Z' }
            )
            'git/ref/tags/unrelated-hotfix' = @{ object = @{ type = 'commit'; sha = ('9' * 40) } }
            'git/ref/tags/v1' = @{ object = @{ type = 'commit'; sha = ('1' * 40) } }
            "compare/$('9' * 40)...$('2' * 40)" = @{ status = 'diverged' }
            "compare/$('1' * 40)...$('2' * 40)" = @{ status = 'ahead' }
        }
        $script:ReleaseCalls = [Collections.Generic.List[string]]::new()
        Mock Invoke-RestMethod {
            param($Uri)
            $Prefix = 'https://api.github.invalid/repos/fixture/benchmark/'
            if ([string]$Uri -ceq $Prefix.TrimEnd('/')) {
                $script:ReleaseCalls.Add('')
                return $script:ReleaseApi['']
            }
            if (-not ([string]$Uri).StartsWith($Prefix, [StringComparison]::Ordinal)) { throw 'Unexpected API host.' }
            $Path = ([string]$Uri).Substring($Prefix.Length)
            $script:ReleaseCalls.Add($Path)
            if (-not $script:ReleaseApi.ContainsKey($Path)) { throw "Unexpected API request: $Path" }
            if ($script:ReleaseApi[$Path] -is [array]) {
                Write-Output -NoEnumerate $script:ReleaseApi[$Path]
            } else {
                $script:ReleaseApi[$Path]
            }
        }
    }
    AfterEach {
        foreach ($Name in $SavedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($Name, $SavedEnvironment[$Name])
        }
    }
    It 'peels annotated tags and selects an earlier stable ancestor rather than a newer unrelated hotfix' {
        & $ResolveRelease
        $Output = [IO.File]::ReadAllText($env:GITHUB_OUTPUT)
        $Output | Should -Match "(?m)^base=$('1' * 40)\r?$"
        $Output | Should -Match "(?m)^head=$('2' * 40)\r?$"
        $script:ReleaseCalls | Should -Contain "git/tags/$('c' * 40)"
        $script:ReleaseCalls | Should -Not -Contain 'git/ref/tags/rolling-preview'
        $script:ReleaseCalls | Should -Not -Contain 'git/ref/tags/draft'
        $script:ReleaseCalls | Should -Not -Contain 'git/ref/tags/future-release'
    }
    It 'selects a stable ancestor for an unpublished immutable candidate without looking up its release' {
        $env:RELEASE_TAG = ''
        $env:CANDIDATE_SHA = '2' * 40
        $script:ReleaseApi['releases?per_page=100&page=1'] = @($PriorRelease)
        & $ResolveRelease
        [IO.File]::ReadAllText($env:GITHUB_OUTPUT) | Should -Match "(?m)^base=$('1' * 40)\r?$"
        [IO.File]::ReadAllText($env:GITHUB_OUTPUT) | Should -Match "(?m)^head=$('2' * 40)\r?$"
        $script:ReleaseCalls | Should -Not -Contain 'releases/tags/v2'
        $env:CANDIDATE_SHA = '--help'
        { & $ResolveRelease } | Should -Throw '*immutable candidate SHA required*'
    }
    It 'resolves pull request identity from the event for same-repository and fork heads' {
        $env:GITHUB_EVENT_NAME = 'pull_request'
        $env:RELEASE_TAG = ''
        foreach ($HeadRepo in @('fixture/benchmark', 'contributor/benchmark-fork')) {
            [IO.File]::WriteAllText($env:GITHUB_OUTPUT, '')
            Write-TestJson $env:GITHUB_EVENT_PATH @{ pull_request = @{
                base = @{ ref = 'main'; sha = ('a' * 40); repo = @{ full_name = 'fixture/benchmark' } }
                head = @{ sha = ('b' * 40); repo = @{ full_name = $HeadRepo } } } }
            & $ResolveRelease
            $Output = [IO.File]::ReadAllText($env:GITHUB_OUTPUT)
            $Output | Should -Match "(?m)^base=$('a' * 40)\r?$"
            $Output | Should -Match "(?m)^head=$('b' * 40)\r?$"
            $Output | Should -Match '(?m)^base_repository=fixture/benchmark\r?$'
            $Output | Should -Match "(?m)^head_repository=$([regex]::Escape($HeadRepo))\r?$"
        }
        $script:ReleaseCalls.Count | Should -Be 0
    }
    It 'rejects pull request events with a foreign base, non-main target, or unsafe identities' {
        $env:GITHUB_EVENT_NAME = 'pull_request'
        foreach ($Case in @(
            @{ Ref = 'main'; Base = 'other/benchmark'; Head = 'fixture/benchmark'; Sha = ('b' * 40); Error = '*must target main*' }
            @{ Ref = 'release'; Base = 'fixture/benchmark'; Head = 'fixture/benchmark'; Sha = ('b' * 40); Error = '*must target main*' }
            @{ Ref = 'main'; Base = 'fixture/benchmark'; Head = '--upload-pack=x'; Sha = ('b' * 40); Error = '*head repository identity*' }
            @{ Ref = 'main'; Base = 'fixture/benchmark'; Head = 'fixture/benchmark'; Sha = 'HEAD'; Error = '*Full commit SHA required*' }
        )) {
            Write-TestJson $env:GITHUB_EVENT_PATH @{ pull_request = @{
                base = @{ ref = $Case.Ref; sha = ('a' * 40); repo = @{ full_name = $Case.Base } }
                head = @{ sha = $Case.Sha; repo = @{ full_name = $Case.Head } } } }
            { & $ResolveRelease } | Should -Throw $Case.Error
        }
    }
    It 'has exactly one pull request trigger, deduplicated per PR, and is not also called by the experimental paid Release' {
        $Triggers = [regex]::Matches($WorkflowText, '(?m)^  (pull_request|pull_request_target|push|schedule):').Value
        $Triggers | Should -Be @('  pull_request:')
        $WorkflowText | Should -Match '(?ms)^  pull_request:\r?\n    branches:\r?\n      - main\r?\n'
        $WorkflowText | Should -Match "format\('pr-\{0\}', github\.event\.pull_request\.number\)"
        $WorkflowText | Should -Match 'cancel-in-progress: true'
        $WorkflowText | Should -Match 'persist-credentials: false'
        $WorkflowText | Should -Not -Match 'COPILOT_GITHUB_TOKEN|secrets\.'
        $Callers = Get-ChildItem (Join-Path $SourceRoot '.github/workflows') -Filter *.yml |
            Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'tier2-recorded-benchmark\.yml' -and $_.Name -ne 'tier2-recorded-benchmark.yml' }
        @($Callers).Count | Should -Be 0
    }
    It 'keeps manual full-SHA comparisons independent of release API lookups and rejects unsafe refs' {
        $env:RELEASE_TAG = ''
        Write-TestJson $env:GITHUB_EVENT_PATH @{ inputs = @{ base_sha = ('a' * 40); head_sha = ('b' * 40) } }
        & $ResolveRelease
        [IO.File]::ReadAllText($env:GITHUB_OUTPUT) | Should -Match "(?m)^base=$('a' * 40)\r?$"
        $script:ReleaseCalls.Count | Should -Be 0
        Write-TestJson $env:GITHUB_EVENT_PATH @{ inputs = @{ base_sha = '--help'; head_sha = ('b' * 40) } }
        { & $ResolveRelease } | Should -Throw '*Full commit SHA required*'
    }
    It 'defaults to the latest selected branch and its cross-repository PR parent' {
        $env:RELEASE_TAG = ''
        Write-TestJson $env:GITHUB_EVENT_PATH @{ inputs = @{ base_sha = ''; head_sha = '' } }
        $script:ReleaseApi['branches/feature%2Ftest'] = @{ commit = @{ sha = 'a' * 40 } }
        $script:ReleaseApi[''] = @{ fork = $false; default_branch = 'main' }
        $script:ReleaseApi['pulls?state=open&head=fixture%3Afeature%2Ftest&per_page=100'] = @(
            @{ base = @{ ref = 'integration/parent'; repo = @{ full_name = 'upstream/project' } } }
        )
        Mock Invoke-RestMethod {
            param($Uri)
            $text = [string]$Uri
            if ($text -eq 'https://api.github.invalid/repos/upstream/project/branches/integration%2Fparent') {
                return @{ commit = @{ sha = 'b' * 40 } }
            }
            if ($text -ceq 'https://api.github.invalid/repos/fixture/benchmark') { return $script:ReleaseApi[''] }
            $path = $text.Substring('https://api.github.invalid/repos/fixture/benchmark/'.Length)
            if (-not $script:ReleaseApi.ContainsKey($path)) { throw "Unexpected API request: $path" }
            Write-Output -NoEnumerate $script:ReleaseApi[$path]
        }
        & $ResolveRelease
        $output = [IO.File]::ReadAllText($env:GITHUB_OUTPUT)
        $output | Should -Match "(?m)^head=$('a' * 40)\r?$"
        $output | Should -Match "(?m)^base=$('b' * 40)\r?$"
        $output | Should -Match '(?m)^base_repository=upstream/project\r?$'
    }
    It 'uses the default branch only without a PR and preserves individual overrides' {
        $env:RELEASE_TAG = ''
        $script:ReleaseApi[''] = @{ fork = $false; default_branch = 'main' }
        $script:ReleaseApi['pulls?state=open&head=fixture%3Afeature%2Ftest&per_page=100'] = @()
        $script:ReleaseApi['branches/main'] = @{ commit = @{ sha = 'b' * 40 } }
        $script:ReleaseApi['branches/feature%2Ftest'] = @{ commit = @{ sha = 'a' * 40 } }
        Write-TestJson $env:GITHUB_EVENT_PATH @{ inputs = @{ base_sha = ''; head_sha = 'c' * 40 } }
        & $ResolveRelease
        [IO.File]::ReadAllText($env:GITHUB_OUTPUT) | Should -Match "(?m)^head=$('c' * 40)\r?$"
        [IO.File]::ReadAllText($env:GITHUB_OUTPUT) | Should -Match "(?m)^base=$('b' * 40)\r?$"
        [IO.File]::WriteAllText($env:GITHUB_OUTPUT, '')
        Write-TestJson $env:GITHUB_EVENT_PATH @{ inputs = @{ base_sha = 'd' * 40; head_sha = '' } }
        & $ResolveRelease
        [IO.File]::ReadAllText($env:GITHUB_OUTPUT) | Should -Match "(?m)^base=$('d' * 40)\r?$"
        [IO.File]::ReadAllText($env:GITHUB_OUTPUT) | Should -Match "(?m)^head=$('a' * 40)\r?$"
    }
    It 'discovers fork PRs upstream and rejects ambiguous or self-parent defaults' {
        $env:RELEASE_TAG = ''
        Write-TestJson $env:GITHUB_EVENT_PATH @{ inputs = @{ base_sha = ''; head_sha = 'a' * 40 } }
        $script:ReleaseApi[''] = @{ fork = $true; parent = @{ full_name = 'upstream/project' }; default_branch = 'main' }
        $script:ReleaseApi['pulls?state=open&head=fixture%3Afeature%2Ftest&per_page=100'] = @()
        Mock Invoke-RestMethod {
            param($Uri)
            $text = [string]$Uri
            if ($text.StartsWith('https://api.github.invalid/repos/upstream/project/pulls?')) {
                Write-Output -NoEnumerate @(@{ base = @{ ref = 'main'; repo = @{ full_name = 'upstream/project' } } })
                return
            }
            if ($text -eq 'https://api.github.invalid/repos/upstream/project/branches/main') {
                return @{ commit = @{ sha = 'b' * 40 } }
            }
            if ($text -ceq 'https://api.github.invalid/repos/fixture/benchmark') { return $script:ReleaseApi[''] }
            $path = $text.Substring('https://api.github.invalid/repos/fixture/benchmark/'.Length)
            Write-Output -NoEnumerate $script:ReleaseApi[$path]
        }
        & $ResolveRelease
        [IO.File]::ReadAllText($env:GITHUB_OUTPUT) | Should -Match '(?m)^base_repository=upstream/project\r?$'
        $script:ReleaseApi['pulls?state=open&head=fixture%3Afeature%2Ftest&per_page=100'] = @(@{}, @{})
        { & $ResolveRelease } | Should -Throw '*Multiple open PR parents*'
        $script:ReleaseApi['pulls?state=open&head=fixture%3Afeature%2Ftest&per_page=100'] = @()
        $script:ReleaseApi[''] = @{ fork = $false; default_branch = 'feature/test' }
        { & $ResolveRelease } | Should -Throw '*no distinct parent*'
    }
    It 'emits missing-baseline exit 2 for a first release without running candidate helpers' {
        $script:ReleaseApi['releases?per_page=100&page=1'] = @($CurrentRelease)
        & $ResolveRelease
        [IO.File]::ReadAllText($env:GITHUB_OUTPUT) | Should -Match '(?m)^base=\r?$'
        $env:RUNNER_TEMP = Join-Path $TestDrive 'release-no-baseline'
        $env:BASE_SHA = ''
        $env:HEAD_SHA = '2' * 40
        Mock pwsh { throw 'Candidate helper must not run.' }
        New-Item -ItemType Directory -Path $env:RUNNER_TEMP -Force | Out-Null
        Push-Location $env:RUNNER_TEMP
        try { & $MissingBaseline } finally { Pop-Location }
        $Result = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $env:RUNNER_TEMP '.benchmark-recorded-public/report.json')))
        $Result.status | Should -Be 'missing-baseline'
        $Result.exitCode | Should -Be 2
        $Result.reasons | Should -Contain 'previous-stable-release-unavailable'
        Should -Invoke pwsh -Times 0
    }
    It 'limits legacy bootstrap to missing release tooling through 0.18.1 and never waives fresh collection' -ForEach @(
        @{ Version = '0.18.1'; Status = 'missing-baseline'; Reason = 'base-comparison-tooling-unavailable'; InputVerdict = '2'; ReleaseCandidate = $true; CollectionRequired = $true; Expected = '2' }
        @{ Version = '0.18.0'; Status = 'missing-baseline'; Reason = 'base-comparison-tooling-unavailable'; InputVerdict = '2'; ReleaseCandidate = $true; Expected = '0' }
        @{ Version = '0.18.1'; Status = 'missing-baseline'; Reason = 'previous-stable-release-unavailable'; InputVerdict = '2'; ReleaseCandidate = $true; Expected = '0' }
        @{ Version = '0.18.2'; Status = 'missing-baseline'; Reason = 'base-comparison-tooling-unavailable'; InputVerdict = '2'; ReleaseCandidate = $true; Expected = '2' }
        @{ Version = '0.19.0'; Status = 'missing-baseline'; Reason = 'base-comparison-tooling-unavailable'; InputVerdict = '2'; ReleaseCandidate = $true; Expected = '2' }
        @{ Version = '0.18.1'; Status = 'stale-record'; Reason = 'unbound-execution-protocol'; InputVerdict = '2'; ReleaseCandidate = $true; Expected = '2' }
        @{ Version = '0.18.1'; Status = 'incompatible'; Reason = 'protocol'; InputVerdict = '2'; ReleaseCandidate = $true; Expected = '2' }
        @{ Version = '0.18.1'; Status = 'missing-candidate'; Reason = 'selection'; InputVerdict = '2'; ReleaseCandidate = $true; Expected = '2' }
        @{ Version = '0.18.1'; Status = 'regression'; Reason = 'quality'; InputVerdict = '3'; ReleaseCandidate = $true; Expected = '3' }
        @{ Version = '0.18.1'; Status = 'operational-error'; Reason = 'failure'; InputVerdict = '1'; ReleaseCandidate = $true; Expected = '1' }
        @{ Version = '0.18.1'; Status = 'missing-baseline'; Reason = 'base-comparison-tooling-unavailable'; InputVerdict = '2'; ReleaseCandidate = $false; Expected = '2' }
    ) {
        param([bool]$CollectionRequired = $false)
        $env:RUNNER_TEMP = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $directory = Join-Path $env:RUNNER_TEMP 'efficiency-report'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $path = Join-Path $directory 'report.json'
        Write-TestJson $path @{ status = $Status; reasons = @($Reason); exitCode = [int]$InputVerdict }
        $original = [IO.File]::ReadAllText($path)
        $env:VERDICT = $InputVerdict
        $env:COLLECTION_REQUIRED = if ($CollectionRequired) { 'true' } else { '' }
        $env:CANDIDATE_SHA = if ($ReleaseCandidate) { 'a' * 40 } else { '' }
        $env:GITHUB_STEP_SUMMARY = Join-Path $env:RUNNER_TEMP 'summary'
        Mock git { $global:LASTEXITCODE = 0; "version: $Version" }
        & $Bootstrap
        [IO.File]::ReadAllText($env:GITHUB_OUTPUT) | Should -Match "(?m)^verdict=$Expected\r?$"
        [IO.File]::ReadAllText($path) | Should -BeExactly $original
    }
    It 'paginates published releases instead of silently missing an older baseline' {
        $script:ReleaseApi['releases?per_page=100&page=1'] = @(1..100 | ForEach-Object {
            @{ id = (100 + $_); tag_name = "preview-$_"; draft = $false; prerelease = $true; published_at = '2026-10-19T00:00:00Z' }
        })
        $script:ReleaseApi['releases?per_page=100&page=2'] = @($PriorRelease)
        & $ResolveRelease
        [IO.File]::ReadAllText($env:GITHUB_OUTPUT) | Should -Match "(?m)^base=$('1' * 40)\r?$"
        $script:ReleaseCalls | Should -Contain 'releases?per_page=100&page=2'
    }
    It 'rejects nonstable releases, malformed object identities and cyclic annotated tags' {
        $CurrentRelease.prerelease = $true
        { & $ResolveRelease } | Should -Throw '*published stable release is required*'
        $CurrentRelease.prerelease = $false
        $script:ReleaseApi['git/ref/tags/v2'].object.sha = '--help'
        { & $ResolveRelease } | Should -Throw '*Invalid release object identity*'
        $script:ReleaseApi['git/ref/tags/v2'].object.sha = 'c' * 40
        $script:ReleaseApi["git/tags/$('c' * 40)"].object = @{ type = 'tag'; sha = ('c' * 40) }
        { & $ResolveRelease } | Should -Throw '*Invalid release tag chain*'
    }
}
