#Requires -Modules Pester
#Requires -Version 7.5
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Tests release collection policy, accounting and publication gates.
# AI cost: none; collection is mocked and observations come from local fixtures.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'ReleaseBenchmark.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'BenchmarkResults.psm1') -Force
    $SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $Prototype = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $SourceRoot 'benchmarks/efficiency/records/run-20261021-123337-96e88690-v2.json')))
    $ProtocolFiles = @(
        'tests/tier2/live-benchmark/efficiency-scenario.json', 'tests/tier2/live-benchmark/EfficiencyBenchmark.psm1',
        'tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1', 'tests/lib/SquadInstall.psm1',
        'tests/tier2/live-benchmark/Test-EfficiencyTask.ps1', 'scripts/Test-SquadScribeOutput.ps1', 'scripts/Build-SquadPlugin.ps1'
    )
    function Copy-Value($Value) { ConvertFrom-BenchmarkJson ([Text.Encoding]::UTF8.GetBytes((ConvertTo-BenchmarkCanonicalJson $Value))) }
    function Write-Json($Path, $Value) {
        [void][IO.Directory]::CreateDirectory((Split-Path $Path))
        [IO.File]::WriteAllText($Path, (ConvertTo-BenchmarkCanonicalJson $Value))
    }
    function Invoke-FixtureGit($Repo, [string[]]$GitArgs) {
        $Text = @(& git -c core.hooksPath=/dev/null -C $Repo @GitArgs 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Fixture git: $($Text -join ' ')" }
        $Text -join "`n"
    }
    function Commit($Repo) {
        $null = Invoke-FixtureGit $Repo @('add', '.')
        $null = Invoke-FixtureGit $Repo @('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture')
        Invoke-FixtureGit $Repo @('rev-parse', 'HEAD')
    }
    function Save-Selection($F) {
        $Path = Join-Path $F.repo 'benchmarks/efficiency/records/reference.json'
        Write-Json $Path $F.record
        Write-Json (Join-Path $F.repo 'benchmarks/efficiency/current.json') @{
            schemaVersion = 'benchmark-pointer-v1'; recordPath = 'records/reference.json'
            sha256 = Get-BenchmarkDigest ([IO.File]::ReadAllBytes($Path))
        }
    }
    function New-Fixture {
        $Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Repo = Join-Path $Root 'repo'
        [void][IO.Directory]::CreateDirectory($Repo)
        $null = Invoke-FixtureGit $Repo @('init', '-q', '-b', 'hotfix')
        foreach ($Path in $ProtocolFiles + @('apm.yml', 'benchmarks/efficiency/policy.json', 'benchmarks/efficiency/collection-policy.json')) {
            $To = Join-Path $Repo $Path
            [void][IO.Directory]::CreateDirectory((Split-Path $To))
            Copy-Item -LiteralPath (Join-Path $SourceRoot $Path) -Destination $To
        }
        [void][IO.Directory]::CreateDirectory((Join-Path $Repo 'squad-src'))
        Set-Content (Join-Path $Repo 'squad-src/fixture.md') 'reference'
        $Revision = Commit $Repo
        $Record = Copy-Value $Prototype
        $Record.seriesId = 'reference'; $Record.measuredRevision = $Revision
        $Record.sourceHash = Get-BenchmarkSourceHash $Repo $Revision
        $Compatibility = Copy-Value $Record.protocol
        $Compatibility.Remove('cliVersion'); $Compatibility.Remove('roleModelPolicyHash'); $Compatibility.Remove('disabledMcpServersHash')
        $Compatibility.cli = "GitHub Copilot CLI 1.0.101-0. Run 'copilot update' to check for updates."
        $Compatibility.roleModelPolicy = ''; $Compatibility.disabledMcpServers = ''
        $Compatibility.maxCredits = 1000
        $Compatibility.powershell = $PSVersionTable.PSVersion.ToString()
        $HashFields = @('scenarioHash', 'parserHash', 'exerciseHash', 'preparationHash', 'graderHash', 'verifierHash', 'converterHash')
        for ($I = 0; $I -lt 7; $I++) { $Compatibility[$HashFields[$I]] = (Get-FileHash (Join-Path $Repo $ProtocolFiles[$I])).Hash }
        $Record.protocol = Get-BenchmarkProtocol $Repo $Revision $Compatibility
        $F = @{ root = $Root; repo = $Repo; reference = $Revision; record = $Record; compatibility = $Compatibility }
        Save-Selection $F
        Set-Content (Join-Path $Repo 'squad-src/fixture.md') 'candidate'
        $F.controller = Commit $Repo
        $F.candidate = $F.controller
        $F.output = Join-Path $Root 'public'; $F.private = Join-Path $Root 'private'
        $F.cli = Join-Path $Root 'cli.ps1'
        Set-Content $F.cli "'GitHub Copilot CLI 1.0.101-0. Run update to check for updates.'"
        $F
    }
    function New-RawRun($F, $Arm, $Pair, $TrialPath) {
        $Trial = $F.record.trials[$Pair - 1]
        $Hashes = @{}
        foreach ($Name in @('brd', 'prd', 'closingReview')) {
            $Path = Join-Path $TrialPath ("workspace/" + $(if ($Name -eq 'closingReview') { 'review.md' } else { "docs/requirements/$Name.md" }))
            [void][IO.Directory]::CreateDirectory((Split-Path $Path))
            Set-Content $Path 'PRIVATE SENTINEL document'
            $Hashes[$Name] = (Get-FileHash $Path).Hash
        }
        $Metrics = @{
            complete = $true; credits = @{ complete = $true; used = 100 }; modelRequests = 10; toolCalls = 10
            totals = @{ inputTokens = 100; outputTokens = 100; cacheReadTokens = 0; cacheWriteTokens = 0 }
            coverage = @{ inputTokens = 1; outputTokens = 1; cacheReadTokens = 1; cacheWriteTokens = 1 }
            counts = @{ usage = 1; failures = 0 }; elapsedMs = 1000
            evidence = @{ sha256 = ('a' * 64) }; dispatches = @{ 'BRD Quality Reviewer' = 1; 'PRD Quality Reviewer' = 1 }
        }
        $JudgeMetrics = Copy-Value $Metrics; $JudgeMetrics.toolCalls = 0
        $Stages = @(foreach ($Name in @('init', 'requirements', 'build')) {
                $Checks = @{}
                foreach ($Key in $Trial.outcomes.Keys | Where-Object { $_.StartsWith("$Name/") }) { $Checks[$Key.Substring($Name.Length + 1)] = $true }
                @{ name = $Name; passed = $true; process = @{ exitCode = 0; stopCause = 'none'; seconds = 1 }; readiness = @{ checks = $Checks }; attempts = @() }
            })
        $WorkflowChecks = @{}
        foreach ($Key in $Trial.outcomes.Keys | Where-Object { $_.StartsWith('workflow/') }) { $WorkflowChecks[$Key.Substring(9)] = $true }
        $Evidence = @{}; foreach ($Dimension in $Trial.quality.Keys) { $Evidence[$Dimension] = 'PRIVATE SENTINEL explanation' }
        $Revision = if ($Arm -eq 'baseline') { $F.reference } else { $F.candidate }
        @{
            metadata = @{ runId = [guid]::NewGuid().ToString(); arm = $Arm; pair = $Pair; revision = $Revision
                sourceHash = Get-BenchmarkSourceHash $F.repo $Revision; compatibility = $(if ($Arm -eq 'candidate' -and $F.ContainsKey('candidateCompatibility')) { $F.candidateCompatibility } else { $F.compatibility }); started = '2026-10-21T00:00:00Z' }
            collection = @{ recorded = $true; policy = 'baseline-observation-v1' }
            metrics = $Metrics; stages = $Stages; completed = $true
            acceptance = @{ passed = $true; checks = @($Trial.outcomes.Keys | Where-Object { $_.StartsWith('functional/') } | ForEach-Object { @{ name = $_.Substring(11); passed = $true } }) }
            workflow = @{ passed = $true; checks = $WorkflowChecks; reviewPath = 'review.md' }
            judge = @{ valid = $true; documentHashes = $Hashes; response = @{ scores = @{ businessClarity = 20; scopeFidelity = 20; acceptanceCriteria = 20; traceability = 20; risksAndDecisions = 20 }; evidence = $Evidence; criticalHighFindings = 0; documentHashes = $Hashes }
                metrics = $JudgeMetrics; process = @{ exitCode = 0; stopCause = 'none'; seconds = 1 } }
        }
    }
    function Invoke-Campaign($F, [DateTimeOffset]$Started = [DateTimeOffset]::UtcNow, [bool]$Refresh = $true) {
        $F.refresh = $Refresh
        Invoke-ReleaseBenchmark -Repository $F.repo -Controller $F.controller -Candidate $F.candidate -EffectiveVersion '0.19.0' `
            -InstallRoot $F.root -CliPath $F.cli -PrivateRoot $F.private -OutputDirectory $F.output `
            -RunId 123 -RunAttempt 2 -RepositorySlug 'owner/repo' -Started $Started -RefreshReference:$Refresh
    }
    function Publication-Args($F) {
        @{
            Repository = $F.repo; OutputDirectory = $F.output; Controller = $F.controller; Candidate = $F.candidate
            EffectiveVersion = '0.19.0'; RunId = '123'; RunAttempt = '2'; RepositorySlug = 'owner/repo'
            ManifestDigest = (Get-FileHash (Join-Path $F.output 'identity.json')).Hash.ToLowerInvariant()
            ExpectedRefresh = $F.refresh
        }
    }
}

Describe 'Automatic release collection and publication' {
    BeforeEach {
        $script:F = New-Fixture
        $script:Launches = [Collections.Generic.List[string]]::new()
        $script:MutateRun = $null
        $script:ChildMode = 'normal'
        Mock Get-EfficiencyCompatibility -ModuleName ReleaseBenchmark {
            param($SourceRoot)
            if ($SourceRoot.EndsWith('candidate') -and $script:F.ContainsKey('candidateCompatibility')) { $script:F.candidateCompatibility }
            else { $script:F.compatibility }
        }
        Mock Invoke-EfficiencyProcess -ModuleName ReleaseBenchmark {
            param($Arguments, $OutputPath)
            $Arm = $Arguments[[array]::IndexOf($Arguments, '-Arm') + 1]
            $Pair = [int]$Arguments[[array]::IndexOf($Arguments, '-Pair') + 1]
            $TrialPath = $Arguments[[array]::IndexOf($Arguments, '-TrialRoot') + 1]
            $script:Launches.Add("$Arm-$Pair")
            [IO.File]::WriteAllText($OutputPath, 'PRIVATE SENTINEL raw log')
            if ($script:ChildMode -eq 'throw') { throw 'collection-private:PRIVATE-SENTINEL' }
            if ($script:ChildMode -ne 'missing') {
                $Run = New-RawRun $script:F $Arm $Pair $TrialPath
                if ($script:MutateRun) { & $script:MutateRun $Run $TrialPath }
                Write-Json (Join-Path $TrialPath 'out/run.json') $Run
            }
            [pscustomobject]@{ exitCode = $(if ($script:ChildMode -eq 'exit') { 1 } else { 0 }); stopCause = $(if ($script:ChildMode -eq 'timeout') { 'timeout' } else { 'none' }) }
        }
    }

    It 'accepts configurable lower ceilings and rejects invalid numeric, reservation and runtime policy values' {
        $Path = Join-Path $F.repo 'benchmarks/efficiency/collection-policy.json'
        $Policy = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes($Path))
        $Policy.perTrialCredits = 60; $Policy.campaignCredits = 360
        Write-Json $Path $Policy; $Sha = Commit $F.repo
        (Get-CollectionPolicy $F.repo $Sha).policy.perTrialCredits | Should -Be 60
        (Get-CollectionPolicy $F.repo $Sha -RefreshReference).policy.campaignCredits | Should -Be 360
        $Policy.campaignCredits = 180
        Write-Json $Path $Policy; $Sha = Commit $F.repo
        (Get-CollectionPolicy $F.repo $Sha).policy.campaignCredits | Should -Be 180
        { Get-CollectionPolicy $F.repo $Sha -RefreshReference } | Should -Throw '*collection-policy-budget*'
        $Policy.perTrialCredits = 1000; $Policy.campaignCredits = 3000
        Write-Json $Path $Policy; $Sha = Commit $F.repo
        (Get-CollectionPolicy $F.repo $Sha).policy.campaignCredits | Should -Be 3000
        { Get-CollectionPolicy $F.repo $Sha -RefreshReference } | Should -Throw '*collection-policy-budget*'
        $F.controller = $Sha; $F.candidate = $Sha
        (Invoke-Campaign $F).exitCode | Should -Be 1
        $Launches.Count | Should -Be 0
        $Policy.perTrialCredits = 60; $Policy.campaignCredits = 180
        foreach ($Change in @(@{ perTrialCredits = 59 }, @{ campaignCredits = 179 }, @{ campaignTimeoutMinutes = 331 }, @{ model = 'floating model' }, @{ cliVersion = 'latest' }, @{ perTrialCredits = '1000' })) {
            $Bad = Copy-Value $Policy
            foreach ($Key in $Change.Keys) { $Bad[$Key] = $Change[$Key] }
            Write-Json $Path $Bad; $Sha = Commit $F.repo
            { Get-CollectionPolicy $F.repo $Sha } | Should -Throw '*collection-policy*'
        }
        foreach ($Value in @([double]::NaN, [double]::PositiveInfinity, -1, $true)) {
            # JSON itself cannot represent NaN/Infinity as numeric values.
            $Bad = Copy-Value $Policy; $Bad.perTrialCredits = $Value
            Write-Json $Path $Bad; $Sha = Commit $F.repo
            { Get-CollectionPolicy $F.repo $Sha } | Should -Throw
        }
    }

    It 'freezes a validated historical reference despite changed controller source and no candidate record' {
        $Context = Get-ReleaseBenchmarkPreflight $F.repo $F.controller $F.candidate '0.19.0'
        $Context.reference | Should -Be $F.reference
        $Context.reference | Should -Not -Be $F.controller
        $Context.effectiveVersion | Should -Be '0.19.0'
        (Get-ReleaseBenchmarkPreflight $F.repo $F.controller $F.reference '0.19.0').reference | Should -Be $F.reference
        $CandidateRecord = Copy-Value $F.record; $CandidateRecord.seriesId = 'candidate-selection'
        $Path = Join-Path $F.repo 'benchmarks/efficiency/records/candidate-selection.json'
        Write-Json $Path $CandidateRecord
        Write-Json (Join-Path $F.repo 'benchmarks/efficiency/current.json') @{
            schemaVersion = 'benchmark-pointer-v1'; recordPath = 'records/candidate-selection.json'
            sha256 = (Get-FileHash $Path).Hash.ToLowerInvariant()
        }
        $F.candidate = Commit $F.repo
        $null = Invoke-FixtureGit $F.repo @('checkout', '--detach', $F.controller)
        $Context = Get-ReleaseBenchmarkPreflight $F.repo $F.controller $F.candidate '0.19.0'
        $Context.historicalRecordDigest | Should -Be (Get-BenchmarkDigest (Get-BenchmarkGitFile $F.repo $F.controller 'benchmarks/efficiency/records/reference.json'))
        $Launches.Count | Should -Be 0
    }

    It 'rejects corrupt pointers, v1, altered historical protocol and non-ancestor references before spending' {
        foreach ($Kind in @('digest', 'path', 'v1', 'protocol', 'history', 'source', 'series')) {
            $F = New-Fixture
            if ($Kind -eq 'digest' -or $Kind -eq 'path') {
                $Path = Join-Path $F.repo 'benchmarks/efficiency/current.json'
                $Pointer = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes($Path))
                if ($Kind -eq 'digest') { $Pointer.sha256 = '0' * 64 } else { $Pointer.recordPath = '../unsafe.json' }
                Write-Json $Path $Pointer
            } else {
                if ($Kind -eq 'v1') {
                    $F.record.schemaVersion = 'benchmark-series-v1'; $F.record.protocol.Remove('converterHash')
                    $F.record.provenance.collector = 'benchmark-export-v1'; $F.record.provenance.verifierHashBasis = 'measured-git-revision'
                }
                if ($Kind -eq 'protocol') { $F.record.protocol.parserHash = '0' * 64 }
                if ($Kind -eq 'source') { $F.record.sourceHash = '0' * 64 }
                if ($Kind -eq 'series') { $F.record.seriesId = 'wrong-selection' }
                if ($Kind -eq 'history') {
                    $null = Invoke-FixtureGit $F.repo @('checkout', '--orphan', 'untrusted')
                    $Unrelated = Commit $F.repo
                    $null = Invoke-FixtureGit $F.repo @('checkout', 'hotfix')
                    $F.record.measuredRevision = $Unrelated
                    $F.record.sourceHash = Get-BenchmarkSourceHash $F.repo $Unrelated
                }
                Save-Selection $F
            }
            $F.controller = Commit $F.repo; $F.candidate = $F.controller
            { Get-ReleaseBenchmarkPreflight $F.repo $F.controller $F.candidate '0.19.0' } | Should -Throw
        }
        $Launches.Count | Should -Be 0
    }

    It 'rejects modifications and deletions of immutable controller history without requiring new selected records' {
        foreach ($Delete in @($false, $true)) {
            $F = New-Fixture
            $Path = Join-Path $F.repo 'benchmarks/efficiency/records/reference.json'
            if ($Delete) { Remove-Item $Path } else { Add-Content $Path ' ' }
            $F.candidate = Commit $F.repo
            $null = Invoke-FixtureGit $F.repo @('checkout', '--detach', $F.controller)
            { Get-ReleaseBenchmarkPreflight $F.repo $F.controller $F.candidate '0.19.0' } | Should -Throw '*historical-record-modified*'
        }
        $Launches.Count | Should -Be 0
    }

    It 'checks every executing protocol path against both measured revisions before spending' {
        foreach ($Context in @('candidate', 'controller', 'reference')) {
            foreach ($Path in $ProtocolFiles) {
                $F = New-Fixture
                Add-Content (Join-Path $F.repo $Path) 'changed protocol'
                $BadRevision = Commit $F.repo
                if ($Context -eq 'candidate') {
                    $F.candidate = $BadRevision
                    $null = Invoke-FixtureGit $F.repo @('checkout', '--detach', $F.controller)
                } elseif ($Context -eq 'controller') {
                    $F.controller = $BadRevision; $F.candidate = $BadRevision
                } else {
                    $F.record.measuredRevision = $BadRevision
                    $F.record.sourceHash = Get-BenchmarkSourceHash $F.repo $BadRevision
                    $HashFields = @('scenarioHash', 'parserHash', 'exerciseHash', 'preparationHash', 'graderHash', 'verifierHash', 'converterHash')
                    $F.record.protocol[$HashFields[[array]::IndexOf($ProtocolFiles, $Path)]] = (Get-FileHash (Join-Path $F.repo $Path)).Hash.ToLowerInvariant()
                    Save-Selection $F
                    Copy-Item (Join-Path $SourceRoot $Path) (Join-Path $F.repo $Path) -Force
                    $F.controller = Commit $F.repo; $F.candidate = $F.controller
                }
                { Get-ReleaseBenchmarkPreflight $F.repo $F.controller $F.candidate '0.19.0' } | Should -Throw "*collection-protocol:$Path*"
            }
        }
        $Launches.Count | Should -Be 0
    }

    It 'measures source-bound dependency changes with real install identities while default comparisons remain strict' {
        $Path = Join-Path $F.repo 'apm.yml'
        $Text = [IO.File]::ReadAllText($Path) -replace '(?m)^version: .+$', 'version: 0.19.0'
        $Text = $Text -replace '(?m)(Peter-N91/hve-squad/squad-src/[^\r\n#]+)$', '$1#v0.19.0'
        [IO.File]::WriteAllText($Path, $Text)
        $F.candidate = Commit $F.repo
        $null = Invoke-FixtureGit $F.repo @('checkout', '--detach', $F.controller)
        (Get-ReleaseBenchmarkPreflight $F.repo $F.controller $F.candidate '0.19.0').reference | Should -Be $F.reference
        $null = Invoke-FixtureGit $F.repo @('checkout', '--detach', $F.candidate)
        [IO.File]::WriteAllText($Path, ($Text -replace '#[0-9a-f]{40}', ('#' + ('a' * 40))))
        $F.candidate = Commit $F.repo
        $null = Invoke-FixtureGit $F.repo @('checkout', '--detach', $F.controller)
        $Context = Get-ReleaseBenchmarkPreflight $F.repo $F.controller $F.candidate '0.19.0'
        $Context.referenceManifestHash | Should -Not -Be $Context.candidateManifestHash
        $F.candidateCompatibility = Copy-Value $F.compatibility
        $F.candidateCompatibility.installHash = 'b' * 64
        $Report = Invoke-Campaign $F
        $Report.exitCode | Should -Be 0
        $Base = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $F.output 'base-record.json')))
        $Head = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $F.output 'head-record.json')))
        $Policy = ConvertFrom-BenchmarkJson (Get-BenchmarkGitFile $F.repo $F.controller 'benchmarks/efficiency/policy.json')
        $Base.protocol.installHash | Should -Not -Be $Head.protocol.installHash
        { Compare-BenchmarkSeries $Base $Head $Policy } | Should -Throw '*compatibility-installHash*'
        $null = Invoke-FixtureGit $F.repo @('checkout', '--detach', $F.candidate)
        $PublicationParams = Publication-Args $F
        (Assert-ReleaseBenchmarkPublication @PublicationParams).comparisonScope | Should -Be 'fresh-paired-deployments'
        $Launches.Count | Should -Be 6
    }

    It 'collects original six slots once, exports distinct HEAD-correct arms and validates exact publication handoff' {
        $Report = Invoke-Campaign $F
        $Report.exitCode | Should -Be 0
        ($Launches -join ',') | Should -Be 'baseline-1,candidate-1,baseline-2,candidate-2,baseline-3,candidate-3'
        $Report.baseRecord.measuredRevision | Should -Be $F.reference
        $Report.headRecord.measuredRevision | Should -Be $F.candidate
        $Report.baseRecord.sourceHash | Should -Not -Be $Report.headRecord.sourceHash
        $PublicationParams = Publication-Args $F
        $Identity = Assert-ReleaseBenchmarkPublication @PublicationParams
        $Identity.creditsUsed | Should -Be 1200
        $Identity.creditsKnown | Should -Be 1200
        $Identity.accountingComplete | Should -BeTrue
        @($Identity.slots | Where-Object { -not $_.accountingComplete }).Count | Should -Be 0
        foreach ($Arm in @('baseline', 'candidate')) {
            (Invoke-FixtureGit (Join-Path $F.private $Arm) @('rev-parse', 'HEAD')) | Should -Be $(if ($Arm -eq 'baseline') { $F.reference } else { $F.candidate })
        }
    }

    It 'defaults to exactly three original candidate slots and the selected immutable historical bytes' {
        $Pointer = (Get-FileHash (Join-Path $F.repo 'benchmarks/efficiency/current.json')).Hash
        $RecordPath = Join-Path $F.repo 'benchmarks/efficiency/records/reference.json'
        $Historical = [IO.File]::ReadAllBytes($RecordPath)
        $Report = Invoke-Campaign $F -Refresh $false
        $Report.exitCode | Should -Be 0
        ($Launches -join ',') | Should -Be 'candidate-1,candidate-2,candidate-3'
        Test-Path (Join-Path $F.private 'baseline') | Should -BeFalse
        Should -Invoke Get-EfficiencyCompatibility -ModuleName ReleaseBenchmark -Times 1 -Exactly -ParameterFilter { $SourceRoot.EndsWith('candidate') }
        Should -Invoke Get-EfficiencyCompatibility -ModuleName ReleaseBenchmark -Times 0 -Exactly -ParameterFilter { $SourceRoot.EndsWith('baseline') }
        (Get-FileHash (Join-Path $F.output 'base-record.json')).Hash | Should -Be (Get-BenchmarkDigest $Historical)
        (Get-FileHash $RecordPath).Hash | Should -Be (Get-BenchmarkDigest $Historical)
        (Get-FileHash (Join-Path $F.repo 'benchmarks/efficiency/current.json')).Hash | Should -Be $Pointer
        $Raw = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $F.private 'series-evidence.json'))) 33554432
        $Raw.schemaVersion | Should -Be 'efficiency-control-v1'
        $Raw.runs.Count | Should -Be 3
        foreach ($Run in $Raw.runs) {
            $Original = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $F.private "trials/candidate-$($Run.metadata.pair)/out/run.json"))) 16777216
            (ConvertTo-BenchmarkCanonicalJson $Run) | Should -BeExactly (ConvertTo-BenchmarkCanonicalJson $Original)
        }
        (Invoke-FixtureGit (Join-Path $F.private 'candidate') @('rev-parse', 'HEAD')) | Should -Be $F.candidate
        $PublicationParams = Publication-Args $F
        $Identity = Assert-ReleaseBenchmarkPublication @PublicationParams
        $Identity.creditsUsed | Should -Be 600
        $Identity.headRecordDigest | Should -Be $Report.headRecord.sha256
        $Report.headRecord.seriesId | Should -Be 'release-123-2-candidate'
        $Identity.comparisonScope | Should -Be 'historical-reference'
        $Identity.comparisonWarning | Should -Match 'Approximate historical'
        $Directories = @(1..3 | ForEach-Object { Join-Path $F.private "trials/candidate-$_" })
        foreach ($Kind in @('duplicate', 'mixed')) {
            $Bad = Copy-Value $Raw
            if ($Kind -eq 'duplicate') { $Bad.runs[1] = $Bad.runs[0] } else { $Bad.runs[0].metadata.arm = 'baseline' }
            Write-Json (Join-Path $F.private 'bad-control.json') $Bad
            { Export-BenchmarkSeries -Repository (Join-Path $F.private 'candidate') -ControlPath (Join-Path $F.private 'bad-control.json') -TrialDirectories $Directories -SeriesId bad-control } | Should -Throw
        }
    }

    It 'keeps older historical usage outside today reservation while enforcing current candidate policy' {
        $PolicyPath = Join-Path $F.repo 'benchmarks/efficiency/collection-policy.json'
        $Policy = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes($PolicyPath))
        $Policy.perTrialCredits = 60; $Policy.campaignCredits = 180
        Write-Json $PolicyPath $Policy
        $F.compatibility.maxCredits = 60
        $F.controller = Commit $F.repo; $F.candidate = $F.controller
        (Get-ReleaseBenchmarkPreflight $F.repo $F.controller $F.candidate '0.19.0').reservedCredits | Should -Be 180
        $script:MutateRun = { param($Run) $Run.metrics.credits.used = 20; $Run.judge.metrics.credits.used = 20 }
        (Invoke-Campaign $F -Refresh $false).exitCode | Should -Be 0
        $PublicationParams = Publication-Args $F
        (Assert-ReleaseBenchmarkPublication @PublicationParams).creditsUsed | Should -Be 120
        foreach ($Trial in $F.record.trials) {
            ($Trial.workflow.credits + $Trial.judge.credits) | Should -BeGreaterThan 60
        }
        $Path = Join-Path $F.output 'head-record.json'
        $Original = [IO.File]::ReadAllBytes($Path)
        $IdentityPath = Join-Path $F.output 'identity.json'
        $IdentityBytes = [IO.File]::ReadAllBytes($IdentityPath)
        foreach ($Kind in @('credits', 'cliVersion', 'model', 'maxCredits', 'powershell')) {
            $Head = ConvertFrom-BenchmarkJson $Original
            if ($Kind -eq 'credits') { $Head.trials[0].workflow.credits = 61 }
            elseif ($Kind -eq 'maxCredits') { $Head.protocol.maxCredits = 1000 }
            elseif ($Kind -eq 'model') { $Head.protocol.model = 'other-model' }
            elseif ($Kind -eq 'powershell') { $Head.protocol.powershell = '99.0.0' }
            else { $Head.protocol.cliVersion = '9.9.9' }
            Write-Json $Path $Head
            $Identity = ConvertFrom-BenchmarkJson $IdentityBytes
            $Identity.headRecordDigest = (Get-FileHash $Path).Hash.ToLowerInvariant()
            Write-Json $IdentityPath $Identity
            $PublicationParams = Publication-Args $F
            $ExpectedFailure = if ($Kind -eq 'credits') { '*publication-accounting*' } else { '*publication-record-identity*' }
            { Assert-ReleaseBenchmarkPublication @PublicationParams } | Should -Throw $ExpectedFailure
        }
    }

    It 'rejects a wrong export HEAD without rewriting either measured source or the original raw runs' {
        (Invoke-Campaign $F).exitCode | Should -Be 0
        $RawPath = Join-Path $F.private 'series-evidence.json'
        $Before = (Get-FileHash $RawPath).Hash
        $Directories = @(1..3 | ForEach-Object { Join-Path $F.private "trials/baseline-$_" })
        { Export-BenchmarkSeries -Repository (Join-Path $F.private 'candidate') -ControlPath $RawPath -TrialDirectories $Directories -SeriesId wrong-head } |
            Should -Throw '*source-fingerprint*'
        (Get-FileHash $RawPath).Hash | Should -Be $Before
        (Invoke-FixtureGit (Join-Path $F.private 'baseline') @('rev-parse', 'HEAD')) | Should -Be $F.reference
        (Invoke-FixtureGit (Join-Path $F.private 'candidate') @('rev-parse', 'HEAD')) | Should -Be $F.candidate
    }

    It 'blocks a changed actual CLI or incompatible shared runtime before launching a paid child' {
        Set-Content $F.cli "'GitHub Copilot CLI 9.9.9. Run update to check for updates.'"
        (Invoke-Campaign $F).reasons | Should -Contain 'collection-cli-version'
        $Launches.Count | Should -Be 0
        $script:F = New-Fixture
        Mock Get-EfficiencyCompatibility -ModuleName ReleaseBenchmark {
            param($SourceRoot)
            $Value = Copy-Value $script:F.compatibility
            if ($SourceRoot.EndsWith('candidate')) { $Value.powershell = '99.0.0' }
            $Value
        }
        (Invoke-Campaign $F).reasons | Should -Contain 'collection-environment-incompatible'
        $Launches.Count | Should -Be 0
    }

    It 'preserves product-only failures and does not turn the native improvement screen into a release gate' {
        $script:MutateRun = {
            param($Run)
            $Run.acceptance.checks[0].passed = $false; $Run.acceptance.passed = $false; $Run.completed = $false
        }
        $Report = Invoke-Campaign $F
        $Report.status | Should -Be 'no-regression'
        $Report.improvementScreen | Should -BeFalse
        $Report.headStatistics.outcomes.functional | Should -Be 0
        $Raw = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $F.private 'series-evidence.json'))) 33554432
        @($Raw.runs | Where-Object completed).Count | Should -Be 0
        $Launches.Count | Should -Be 6
    }

    It 'renders an actual regression as exit three in JSON, Markdown and SVG and blocks publication' {
        $script:MutateRun = { param($Run) if ($Run.metadata.arm -eq 'candidate') { $Run.metrics.modelRequests = 50 } }
        $Report = Invoke-Campaign $F
        $Report.exitCode | Should -Be 3
        (Get-Content (Join-Path $F.output 'report.json') -Raw) | Should -Match '"status":"regression"'
        (Get-Content (Join-Path $F.output 'report.md') -Raw) | Should -Match 'Regression detected'
        (Get-Content (Join-Path $F.output 'badge.svg') -Raw) | Should -Match '#b45309'
        $PublicationParams = Publication-Args $F
        { Assert-ReleaseBenchmarkPublication @PublicationParams } | Should -Throw '*publication-verdict*'
    }

    It 'stops before a second launch on budget, infrastructure, incomplete accounting or combined workflow plus judge overrun' {
        foreach ($Refresh in @($true, $false)) {
            foreach ($Kind in @('credit-limit', 'request-limit', 'timeout', 'meter', 'judge', 'overrun', 'negative', 'nonnumeric', 'missing-judge', 'invalid-number')) {
                $script:F = New-Fixture
                $script:MutateRun = {
                    param($Run)
                    if ($Kind -eq 'meter') { $Run.metrics.credits.complete = $false }
                    elseif ($Kind -eq 'judge') { $Run.judge.metrics.credits.complete = $false }
                    elseif ($Kind -eq 'overrun') { $Run.metrics.credits.used = 950; $Run.judge.metrics.credits.used = 100 }
                    elseif ($Kind -eq 'negative') { $Run.metrics.credits.used = -1 }
                    elseif ($Kind -eq 'nonnumeric') { $Run.metrics.credits.used = 'PRIVATE SENTINEL' }
                    elseif ($Kind -eq 'missing-judge') { $Run.judge = $null }
                    elseif ($Kind -eq 'invalid-number') { $Run.metrics.credits.used = [double]::PositiveInfinity }
                    else { $Run.stages[0].process.stopCause = $Kind }
                }
                $Launches.Clear()
                (Invoke-Campaign $F -Refresh $Refresh).exitCode | Should -Be 1
                $Launches.Count | Should -Be 1
                (Get-Content (Join-Path $F.output 'identity.json') -Raw) | Should -Not -Match 'PRIVATE SENTINEL'
                $Identity = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $F.output 'identity.json')))
                $Identity.slots[0].status | Should -Be 'failed'
                if ($Kind -in @('meter', 'judge', 'negative', 'nonnumeric', 'missing-judge', 'invalid-number')) {
                    $Identity.accountingComplete | Should -BeFalse
                    $Identity.creditsUsed | Should -BeNullOrEmpty
                    $Identity.creditsKnown | Should -Be 100
                    $Identity.slots[0].credits | Should -BeNullOrEmpty
                    (Get-Content (Join-Path $F.output 'report.md') -Raw) | Should -Match 'lower bound; total unknown'
                } else {
                    $Expected = if ($Kind -eq 'overrun') { 1050 } else { 200 }
                    $Identity.accountingComplete | Should -BeTrue
                    $Identity.creditsUsed | Should -Be $Expected
                    $Identity.creditsKnown | Should -Be $Expected
                    $Identity.slots[0].credits | Should -Be $Expected
                }
            }
        }
    }

    It 'stops child-without-evidence, nonzero infrastructure exit and controlled deadline without inventing records' {
        foreach ($Refresh in @($true, $false)) {
            foreach ($Mode in @('missing', 'exit', 'timeout', 'throw')) {
                $script:F = New-Fixture; $script:ChildMode = $Mode; $Launches.Clear()
                (Invoke-Campaign $F -Refresh $Refresh).exitCode | Should -Be 1
                $Launches.Count | Should -Be 1
                $Identity = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $F.output 'identity.json')))
                if ($Mode -eq 'exit') {
                    $Identity.accountingComplete | Should -BeTrue
                    $Identity.creditsUsed | Should -Be 200
                } else {
                    $Identity.accountingComplete | Should -BeFalse
                    $Identity.creditsUsed | Should -BeNullOrEmpty
                    $Identity.creditsKnown | Should -Be $(if ($Mode -eq 'timeout') { 200 } else { 0 })
                }
                Test-Path (Join-Path $F.output 'head-record.json') | Should -BeFalse
                foreach ($File in Get-ChildItem $F.output -File) { (Get-Content $File.FullName -Raw) | Should -Not -Match 'PRIVATE.SENTINEL' }
            }
        }
        $script:F = New-Fixture; $Launches.Clear(); $script:ChildMode = 'normal'
        $script:MutateRun = { param($Run) if ($Run.metadata.arm -eq 'candidate') { $Run.judge.metrics.credits.complete = $false } }
        (Invoke-Campaign $F).exitCode | Should -Be 1
        $Launches.Count | Should -Be 2
        $Identity = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $F.output 'identity.json')))
        $Identity.creditsKnown | Should -Be 300
        $Identity.creditsUsed | Should -BeNullOrEmpty
        $Identity.accountingComplete | Should -BeFalse
    }

    It 'initializes safe non-passing reports before a deadline and launches no child after expiration' {
        $Report = Invoke-Campaign $F ([DateTimeOffset]::UtcNow.AddMinutes(-331))
        $Report.reasons | Should -Contain 'collection-deadline'
        $Launches.Count | Should -Be 0
        foreach ($File in @('report.json', 'report.md', 'badge.svg', 'identity.json')) { Test-Path (Join-Path $F.output $File) | Should -BeTrue }
        $script:F = New-Fixture
        $Report = Invoke-ReleaseBenchmark -Repository $F.repo -Controller $F.controller -Candidate 'PRIVATE SENTINEL' `
            -EffectiveVersion 'PRIVATE SENTINEL' -RunId 'PRIVATE SENTINEL' -RunAttempt 2 -RepositorySlug 'PRIVATE SENTINEL' `
            -InstallRoot $F.root -CliPath $F.cli -PrivateRoot $F.private -OutputDirectory $F.output
        $Report.exitCode | Should -Be 1
        foreach ($File in Get-ChildItem $F.output -File) { (Get-Content $File.FullName -Raw) | Should -Not -Match 'PRIVATE SENTINEL' }
    }

    It 'retains a sanitized failure envelope on export rejection and never stages raw diagnostics or documents' {
        $script:MutateRun = { param($Run, $Path) Add-Content (Join-Path $Path 'workspace/docs/requirements/brd.md') 'tampered PRIVATE SENTINEL' }
        $Report = Invoke-Campaign $F
        $Report.exitCode | Should -Be 1
        $Report.reasons | Should -Contain 'collection-export-failed'
        $Launches.Count | Should -Be 6
        foreach ($File in Get-ChildItem $F.output -File) { (Get-Content $File.FullName -Raw) | Should -Not -Match 'PRIVATE SENTINEL' }
    }

    It 'rejects wrong campaign, controller, candidate, version, reference and record digests at publication' {
        (Invoke-Campaign $F).exitCode | Should -Be 0
        foreach ($Key in @('RunId', 'RunAttempt', 'Controller', 'Candidate', 'EffectiveVersion', 'RepositorySlug', 'ManifestDigest')) {
            $PublicationParams = Publication-Args $F; $PublicationParams[$Key] = 'wrong'
            { Assert-ReleaseBenchmarkPublication @PublicationParams } | Should -Throw '*publication-*'
        }
        $Path = Join-Path $F.output 'identity.json'
        $Original = [IO.File]::ReadAllBytes($Path)
        foreach ($Key in @('reference', 'historicalRecordDigest', 'collectionPolicyHash', 'comparisonPolicyHash', 'baseRecordDigest', 'headRecordDigest', 'reportDigest', 'creditsKnown', 'creditsUsed', 'accountingComplete')) {
            $Identity = ConvertFrom-BenchmarkJson $Original; $Identity[$Key] = '0' * 64; Write-Json $Path $Identity
            $PublicationParams = Publication-Args $F
            { Assert-ReleaseBenchmarkPublication @PublicationParams } | Should -Throw '*publication-*'
        }
        $Identity = ConvertFrom-BenchmarkJson $Original; $Identity.slots[0].accountingComplete = $false; Write-Json $Path $Identity
        $PublicationParams = Publication-Args $F
        { Assert-ReleaseBenchmarkPublication @PublicationParams } | Should -Throw '*publication-accounting*'
        foreach ($Refresh in @($false, $true)) {
            $script:F = New-Fixture
            (Invoke-Campaign $F -Refresh $Refresh).exitCode | Should -Be 0
            $IdentityPath = Join-Path $F.output 'identity.json'
            $ReportPath = Join-Path $F.output 'report.json'
            $OriginalIdentity = [IO.File]::ReadAllBytes($IdentityPath)
            $OriginalReport = [IO.File]::ReadAllBytes($ReportPath)
            $HeadPath = Join-Path $F.output 'head-record.json'
            $BasePath = Join-Path $F.output 'base-record.json'
            $OriginalHead = [IO.File]::ReadAllBytes($HeadPath)
            $OriginalBase = [IO.File]::ReadAllBytes($BasePath)
            $PublicationParams = Publication-Args $F
            $PublicationParams.ExpectedRefresh = -not $Refresh
            { Assert-ReleaseBenchmarkPublication @PublicationParams } | Should -Throw '*publication-mode*'
            $Kinds = @('mode', 'scope', 'missing-scope', 'old-candidate', 'old-baseline', 'missing-slot', 'duplicate-slot', 'wrong-arm', 'differences', 'warning')
            if (-not $Refresh) { $Kinds += 'base-bytes' }
            foreach ($Kind in $Kinds) {
                [IO.File]::WriteAllBytes($HeadPath, $OriginalHead)
                [IO.File]::WriteAllBytes($BasePath, $OriginalBase)
                $Identity = ConvertFrom-BenchmarkJson $OriginalIdentity
                $Report = ConvertFrom-BenchmarkJson $OriginalReport
                switch ($Kind) {
                    'mode' { $Identity.refreshReference = -not $Refresh }
                    'scope' { $Identity.comparisonScope = 'unknown'; $Report.comparisonScope = 'unknown' }
                    'missing-scope' { $Identity.Remove('comparisonScope'); $Report.Remove('comparisonScope') }
                    'old-candidate' {
                        $Head = ConvertFrom-BenchmarkJson $OriginalHead; $Head.seriesId = 'release-122-2-candidate'
                        Write-Json $HeadPath $Head
                        $Report.headRecord.seriesId = $Head.seriesId
                    }
                    'old-baseline' {
                        $Base = ConvertFrom-BenchmarkJson $OriginalBase; $Base.seriesId = 'release-122-2-baseline'
                        Write-Json $BasePath $Base
                        $Report.baseRecord.seriesId = $Base.seriesId
                    }
                    'base-bytes' { Add-Content -LiteralPath $BasePath ' ' }
                    'missing-slot' { $Identity.slots = @($Identity.slots | Select-Object -Skip 1) }
                    'duplicate-slot' { $Identity.slots[1] = $Identity.slots[0] }
                    'wrong-arm' { $Identity.slots[0].arm = 'unknown' }
                    'differences' {
                        $Identity.protocolDifferences = @{ powershell = @{ old = 'invented'; new = 'invented' } }
                        $Report.protocolDifferences = $Identity.protocolDifferences
                    }
                    'warning' { $Identity.comparisonWarning = ''; $Report.comparisonWarning = '' }
                }
                foreach ($Name in @('base', 'head')) {
                    $Digest = (Get-FileHash (Join-Path $F.output "$Name-record.json")).Hash.ToLowerInvariant()
                    $Identity[$Name + 'RecordDigest'] = $Digest
                    $Report[$Name + 'Record'].sha256 = $Digest
                }
                Write-Json $ReportPath $Report
                $Identity.reportDigest = (Get-FileHash $ReportPath).Hash.ToLowerInvariant()
                Write-Json $IdentityPath $Identity
                $PublicationParams = Publication-Args $F
                { Assert-ReleaseBenchmarkPublication @PublicationParams } | Should -Throw -Because "resealed $Kind must fail (refresh=$Refresh)"
            }
        }
    }

    It 'binds a hotfix version override and exact self-pin-only final tag, rejecting product or dependency mutations' {
        (Invoke-Campaign $F).exitCode | Should -Be 0
        $PublicationParams = Publication-Args $F
        $Path = Join-Path $F.repo 'apm.yml'
        $Before = [IO.File]::ReadAllText($Path)
        [IO.File]::WriteAllText($Path, (($Before -replace '(?m)^version: .+$', 'version: 0.19.0') -replace '(?m)(Peter-N91/hve-squad/squad-src/[^\r\n#]+)$', '$1#v0.19.0'))
        $Final = Commit $F.repo
        (Assert-ReleaseBenchmarkPublication @PublicationParams -BindFinalCommit).finalTagCommit | Should -Be $Final
        $Identity = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $F.output 'identity.json')))
        $Identity.finalTagCommit = $null; Write-Json (Join-Path $F.output 'identity.json') $Identity
        $PublicationParams = Publication-Args $F
        Add-Content (Join-Path $F.repo 'squad-src/fixture.md') 'wrong product'
        $null = Commit $F.repo
        { Assert-ReleaseBenchmarkPublication @PublicationParams -BindFinalCommit } | Should -Throw '*publication-product-changed*'
        $null = Invoke-FixtureGit $F.repo @('reset', '--hard', $Final)
        Add-Content $Path 'dependencies-changed: true'
        $null = Commit $F.repo
        { Assert-ReleaseBenchmarkPublication @PublicationParams -BindFinalCommit } | Should -Throw '*publication-dependencies-changed*'
    }

    It 'isolates credentials, forbids PR or ordinary-push paid triggers, allowlists artifacts and keeps Release Prep requesting the stored gate' {
        $Workflow = Get-Content (Join-Path $SourceRoot '.github/workflows/tier2-benchmark.yml') -Raw
        $Workflow | Should -Not -Match '(?m)^  (pull_request|push|pull_request_target):'
        ([regex]::Matches($Workflow, 'COPILOT_GITHUB_TOKEN: \$\{\{ secrets.COPILOT_GITHUB_TOKEN \}\}')).Count | Should -Be 1
        $Workflow | Should -Match 'timeout-minutes: 360'
        $Workflow | Should -Match 'cancel-in-progress: false'
        $Workflow | Should -Match '\-\-no-auto-update'
        $Workflow | Should -Not -Match 'path:.*private|recorded-observation'
        $Workflow | Should -Match "COLLECTION_REQUIRED: 'true'"
        ([regex]::Matches($Workflow, '(?ms)refresh_reference:\r?\n\s+description:[^\r\n]+\r?\n\s+required: false\r?\n\s+default: false\r?\n\s+type: boolean')).Count | Should -Be 2
        $Workflow | Should -Match 'foreach \(\$arm in \$context.arms\)'
        $Workflow | Should -Not -Match "foreach \(\`$arm in @\('baseline', 'candidate'\)\)"
        ([regex]::Matches($Workflow, '-RefreshReference:\(\$env:REFRESH_REFERENCE -ceq ''true''\)')).Count | Should -Be 3
        (Get-Content (Join-Path $SourceRoot '.github/workflows/release-prep.yml') -Raw) | Should -Match '-f run_benchmark=true'
    }
}
