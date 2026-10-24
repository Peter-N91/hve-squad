#Requires -Modules Pester
#Requires -Version 7.5
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Tests study schemas and aggregation against saved and mutated observations.
# AI cost: none; no new workflow or judge session is collected.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'BenchmarkResults.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'BenchmarkStudy.psm1') -Force
    $SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $Prototype = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes((Join-Path $SourceRoot 'benchmarks/efficiency/records/run-20261019-222802-3624af24.json')))
    $ProtocolPaths = [ordered]@{
        scenarioHash = 'tests/tier2/live-benchmark/efficiency-scenario.json'
        parserHash = 'tests/tier2/live-benchmark/EfficiencyBenchmark.psm1'
        exerciseHash = 'tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1'
        preparationHash = 'tests/lib/SquadInstall.psm1'
        graderHash = 'tests/tier2/live-benchmark/Test-EfficiencyTask.ps1'
        verifierHash = 'scripts/Test-SquadScribeOutput.ps1'
        converterHash = 'scripts/Build-SquadPlugin.ps1'
    }
    function Copy-StudyValue($Value) {
        ConvertFrom-BenchmarkJson ([Text.Encoding]::UTF8.GetBytes((ConvertTo-BenchmarkCanonicalJson $Value)))
    }
    function Invoke-StudyGit([string]$Repository, [string[]]$GitArguments) {
        $Result = @(& git -C $Repository @GitArguments 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Synthetic fixture Git failure: $($Result -join ' ')" }
        $Result -join "`n"
    }
    function Save-StudyCommit($Fixture) {
        [void](Invoke-StudyGit $Fixture.repository @('add', '.'))
        [void](Invoke-StudyGit $Fixture.repository @('-c', 'user.name=Synthetic', '-c', 'user.email=synthetic@example.invalid', 'commit', '--quiet', '-m', 'synthetic fixture'))
        Invoke-StudyGit $Fixture.repository @('rev-parse', 'HEAD')
    }
    function Write-StudyJson([string]$Path, $Value) {
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
        [IO.File]::WriteAllText($Path, (ConvertTo-BenchmarkCanonicalJson $Value), [Text.UTF8Encoding]::new($false))
    }
    function Get-StudyFingerprint($Record) {
        Get-BenchmarkDigest ([Text.Encoding]::UTF8.GetBytes((ConvertTo-BenchmarkCanonicalJson $Record.protocol)))
    }
    function Save-StudyBatch($Fixture, [int]$Index = 0) {
        $Batch = $Fixture.manifest.batches[$Index]
        $Path = Join-Path $Fixture.repository $Batch.recordPath
        Write-StudyJson $Path $Fixture.records[$Index]
        $Batch.recordSha256 = Get-BenchmarkDigest ([IO.File]::ReadAllBytes($Path))
    }
    function Add-StudyBatch($Fixture, [string]$Arm, [string]$Stratum = 'development', $Record = $null) {
        $Index = $Fixture.records.Count
        if ($null -eq $Record) { $Record = Copy-StudyValue $Fixture.records[0] }
        $Record.seriesId = "batch-$Index"
        foreach ($Trial in $Record.trials) { $Trial.runId = [guid]::NewGuid().ToString() }
        $Fixture.records += $Record
        $BatchId = "batch-$Index"
        $Fixture.manifest.batches += @{
            batchId = $BatchId; stratumId = $Stratum; arm = $Arm
            recordPath = "benchmarks/efficiency/records/$BatchId.json"; recordSha256 = '0' * 64
        }
        foreach ($Trial in $Record.trials) {
            $Fixture.manifest.slots += @{
                slotId = "slot-$Index-$($Trial.slot)"; stratumId = $Stratum; arm = $Arm
                state = 'recorded'; batchId = $BatchId; runId = $Trial.runId
            }
        }
        Save-StudyBatch $Fixture $Index
    }
    function New-StudyFixture {
        $Repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($Repository)
        [void](Invoke-StudyGit $Repository @('init', '--quiet', '-b', 'main'))
        foreach ($Path in $ProtocolPaths.Values) {
            $Destination = Join-Path $Repository $Path
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination))
            [IO.File]::Copy((Join-Path $SourceRoot $Path), $Destination)
        }
        [void][IO.Directory]::CreateDirectory((Join-Path $Repository 'squad-src'))
        [IO.File]::WriteAllText((Join-Path $Repository 'squad-src/charter.md'), 'synthetic original')
        $Fixture = @{ repository = $Repository; records = @(); manifestPath = Join-Path $Repository 'study.json' }
        $Revision = Save-StudyCommit $Fixture
        $Record = Copy-StudyValue $Prototype
        $Record.schemaVersion = 'benchmark-series-v2'
        $Record.provenance.collector = 'benchmark-export-v2'
        $Record.provenance.verifierHashBasis = 'executing-file-verified-against-measured-git'
        $Record.measuredRevision = $Revision
        $Record.sourceHash = Get-BenchmarkSourceHash $Repository $Revision
        foreach ($Key in $ProtocolPaths.Keys) {
            $Record.protocol[$Key] = Get-BenchmarkDigest ([IO.File]::ReadAllBytes((Join-Path $Repository $ProtocolPaths[$Key])))
        }
        foreach ($Trial in $Record.trials) {
            foreach ($Part in @('workflow', 'judge')) {
                foreach ($Field in @($Trial[$Part].Keys)) { $Trial[$Part][$Field] = 1 }
                $Trial[$Part].failedTools = 0
                $Trial[$Part].toolCalls = if ($Part -ceq 'judge') { 0 } else { 1 }
            }
            foreach ($Field in @($Trial.quality.Keys)) { $Trial.quality[$Field] = 20 }
            foreach ($Field in @($Trial.outcomes.Keys)) { $Trial.outcomes[$Field] = $true }
            foreach ($Stage in $Trial.processes.Keys) { $Trial.processes[$Stage].exitCode = 0; $Trial.processes[$Stage].stopCause = 'none' }
            foreach ($Document in @($Trial.documents.Keys)) { $Trial.documents[$Document] = 'a' * 64 }
            $Trial.criticalHighFindings = 0
        }
        $Fixture.manifest = @{
            schemaVersion = 'benchmark-study-v1'; studyId = 'synthetic-study'
            strata = @(@{ stratumId = 'development'; taskId = 'synthetic-task'; taskRole = 'development'; design = 'descriptive'; protocolFingerprint = Get-StudyFingerprint $Record })
            batches = @(); slots = @()
        }
        Add-StudyBatch -Fixture $Fixture -Arm 'a' -Stratum 'development' -Record $Record
        $Fixture
    }
    function Invoke-Study($Fixture, [string]$AnnotationPath) {
        Write-StudyJson $Fixture.manifestPath $Fixture.manifest
        Get-BenchmarkStudyAnalysis -Repository $Fixture.repository -ManifestPath $Fixture.manifestPath -AnnotationPath $AnnotationPath
    }
    function New-StudyAnnotations($Fixture) {
        $Record = $Fixture.records[0]; $Trial = $Record.trials[0]
        @{
            schemaVersion = 'benchmark-human-annotations-v1'
            annotations = @(
                @{
                    annotationId = 'synthetic-annotation'
                    binding = @{
                        recordSha256 = $Fixture.manifest.batches[0].recordSha256; measuredRevision = $Record.measuredRevision
                        sourceHash = $Record.sourceHash; runId = $Trial.runId; documents = Copy-StudyValue $Trial.documents
                        rubric = $Record.protocol.rubric; judgeImplementationHash = $Record.protocol.parserHash
                        recordedModel = $Record.protocol.model; recordedModelHash = $null
                    }
                    attestation = @{ annotatorId = 'synthetic-rater'; attestationRef = 'synthetic-ref'; status = 'externally-attested-human' }
                    ratings = Copy-StudyValue $Trial.quality
                }
            )
        }
    }
    function Invoke-AnnotatedStudy($Fixture, $Envelope) {
        $Path = Join-Path $Fixture.repository 'synthetic-annotations.json'
        Write-StudyJson $Path $Envelope
        Invoke-Study $Fixture $Path
    }
}

Describe 'Offline benchmark study evidence' {
    It 'reduces every same-arm batch before reduction and keeps roles and planned arms separate' {
        $Fixture = New-StudyFixture
        $Fixture.manifest.strata[0].design = 'aa'
        Add-StudyBatch $Fixture 'a'
        Add-StudyBatch $Fixture 'b'
        $Samples = @(1, 2, 101, 11, 21, 31)
        for ($Index = 0; $Index -lt 6; $Index++) {
            $Trial = $Fixture.records[[int][Math]::Floor($Index / 3)].trials[$Index % 3]
            $Trial.workflow.measuredProcessWallSeconds = $Samples[$Index] - 1
            $Trial.judge.measuredProcessWallSeconds = 1
            $Trial.workflow.credits = $Samples[$Index] - 1; $Trial.judge.credits = 1
        }
        $Fixture.records[0].trials[0].judge.cacheReadTokens = $null
        Save-StudyBatch $Fixture 0; Save-StudyBatch $Fixture 1
        $Fixture.manifest.strata += @{ stratumId = 'heldout'; taskId = 'other-task'; taskRole = 'held-out'; design = 'descriptive'; protocolFingerprint = Get-StudyFingerprint $Fixture.records[0] }
        Add-StudyBatch -Fixture $Fixture -Arm 'a' -Stratum 'heldout'
        $Fixture.manifest.slots += @{ slotId = 'future'; stratumId = 'development'; arm = 'future'; state = 'planned' }
        $Result = Invoke-Study $Fixture
        $Result.strata.Count | Should -Be 2
        $Development = $Result.strata | Where-Object taskRole -CEQ 'development'
        $Arm = $Development.arms | Where-Object arm -CEQ 'a'
        $Arm.counts.recorded | Should -Be 6
        $Arm.resources.total.measuredProcessWallSeconds.sum | Should -Be 167
        $Arm.resources.total.measuredProcessWallSeconds.median | Should -Be 16
        $Arm.resources.total.measuredProcessWallSeconds.mean | Should -Be ([decimal]167 / 6)
        $Arm.resources.total.cacheReadTokens.sum | Should -BeNullOrEmpty
        $Arm.resources.total.cacheReadTokens.mean | Should -BeNullOrEmpty
        $Arm.resources.total.cacheReadTokens.median | Should -BeNullOrEmpty
        $Arm.resources.total.cacheReadTokens.sampleCount | Should -Be 6
        $Arm.resources.total.cacheReadTokens.missingCount | Should -Be 1
        $Arm.resources.total.cacheReadTokens.reason | Should -Be 'missing-component-metric'
        $Arm.recordedConsumptionPerAcceptedWorkflow.credits.numerator | Should -Be 167
        $Arm.recordedConsumptionPerAcceptedWorkflow.credits.denominator | Should -Be 6
        $Arm.recordedConsumptionPerAcceptedWorkflow.credits.value | Should -Be ([decimal]167 / 6)
        $Arm.recordedWorkflowAcceptance.denominator | Should -Be 6
        ($Development.arms | Where-Object arm -CEQ 'b').counts.recorded | Should -Be 3
        ($Result.strata | Where-Object taskRole -CEQ 'held-out').arms[0].counts.recorded | Should -Be 3
        $Future = $Development.arms | Where-Object arm -CEQ 'future'
        $Future.resources.total.credits.mean | Should -BeNullOrEmpty
        $Future.documentQuality.total.median | Should -BeNullOrEmpty
        $Future.portableEvidenceCoverage.value | Should -BeNullOrEmpty
        $Future.portableEvidenceCoverage.reason | Should -Be 'no-attempted-slots'
        $Result.ContainsKey('resources') | Should -BeFalse
        $Result.calibration.calibrationState | Should -Be 'unassessed'
    }
    It 'accepts historical evidence without bypassing the current snapshot boundary' {
        $Fixture = New-StudyFixture
        $Root = Join-Path $Fixture.repository 'benchmarks/efficiency'
        Write-StudyJson (Join-Path $Root 'current.json') @{ schemaVersion = 'benchmark-pointer-v1'; recordPath = 'records/batch-0.json'; sha256 = $Fixture.manifest.batches[0].recordSha256 }
        [IO.File]::Copy((Join-Path $SourceRoot 'benchmarks/efficiency/policy.json'), (Join-Path $Root 'policy.json'))
        $Base = Save-StudyCommit $Fixture
        [IO.File]::AppendAllText((Join-Path $Fixture.repository $ProtocolPaths.graderHash), "`n# synthetic protocol change")
        $Head = Save-StudyCommit $Fixture
        (Invoke-Study $Fixture).state | Should -Be 'recorded-evidence-present'
        (Compare-BranchBenchmark $Fixture.repository $Base $Head).status | Should -Be 'stale-record'
    }
    It 'compares exact file bytes rather than canonical JSON digests' {
        $Fixture = New-StudyFixture
        $Path = Join-Path $Fixture.repository $Fixture.manifest.batches[0].recordPath
        [IO.File]::AppendAllText($Path, ' ')
        { Invoke-Study $Fixture } | Should -Throw '*study-record-digest*'
        $Fixture.manifest.batches[0].recordSha256 = Get-BenchmarkDigest ([IO.File]::ReadAllBytes($Path))
        (Invoke-Study $Fixture).state | Should -Be 'recorded-evidence-present'
    }
    It 'rejects a record source hash inconsistent with its measured commit' {
        $Fixture = New-StudyFixture
        $Fixture.records[0].sourceHash = '0' * 64; Save-StudyBatch $Fixture
        { Invoke-Study $Fixture } | Should -Throw '*historical-source-fingerprint*'
    }
    It 'rejects a record protocol hash inconsistent with its measured commit' {
        $Fixture = New-StudyFixture
        $Fixture.records[0].protocol.parserHash = '0' * 64; Save-StudyBatch $Fixture
        { Invoke-Study $Fixture } | Should -Throw '*historical-protocol-parserHash*'
    }
    It 'rejects UUID reuse across independently declared arms' {
        $Fixture = New-StudyFixture; Add-StudyBatch $Fixture 'b'
        $Fixture.records[1].trials[0].runId = $Fixture.records[0].trials[0].runId
        Save-StudyBatch $Fixture 1
        { Invoke-Study $Fixture } | Should -Throw '*study-uuid-reuse*'
    }
    It 'requires complete unique batch and trial rosters with exact slot bindings' {
        $Fixture = New-StudyFixture; $Original = Copy-StudyValue $Fixture.manifest
        $Fixture.manifest.slots = @($Fixture.manifest.slots | Select-Object -Skip 1)
        { Invoke-Study $Fixture } | Should -Throw '*study-incomplete-roster*'
        $Fixture.manifest = Copy-StudyValue $Original
        $Fixture.manifest.batches += Copy-StudyValue $Fixture.manifest.batches[0]
        { Invoke-Study $Fixture } | Should -Throw '*study-batch*'
        $Fixture.manifest = Copy-StudyValue $Original
        $Fixture.manifest.slots[1].runId = $Fixture.manifest.slots[0].runId
        { Invoke-Study $Fixture } | Should -Throw '*study-trial-roster*'
        $Fixture.manifest = Copy-StudyValue $Original
        $Fixture.manifest.slots[0].runId = [guid]::NewGuid().ToString()
        { Invoke-Study $Fixture } | Should -Throw '*study-trial-roster*'
        $Fixture.manifest = Copy-StudyValue $Original
        $Fixture.manifest.slots[0].arm = 'other'
        { Invoke-Study $Fixture } | Should -Throw '*study-slot-binding*'
        $Fixture.manifest = Copy-StudyValue $Original
        $Fixture.manifest.slots[0].batchId = 'nonexistent'
        { Invoke-Study $Fixture } | Should -Throw '*study-trial-roster*'
    }
    It 'requires shared A/A sources and stable A/B sources with two recorded arms' {
        $Fixture = New-StudyFixture; $Fixture.manifest.strata[0].design = 'aa'
        { Invoke-Study $Fixture } | Should -Throw '*study-design-recorded-arms*'
        [IO.File]::WriteAllText((Join-Path $Fixture.repository 'squad-src/charter.md'), 'synthetic changed')
        $Changed = Copy-StudyValue $Fixture.records[0]
        $Changed.measuredRevision = Save-StudyCommit $Fixture
        $Changed.sourceHash = Get-BenchmarkSourceHash $Fixture.repository $Changed.measuredRevision
        Add-StudyBatch -Fixture $Fixture -Arm 'b' -Stratum 'development' -Record $Changed
        { Invoke-Study $Fixture } | Should -Throw '*study-aa-source*'
        $Fixture.manifest.strata[0].design = 'ab'
        (Invoke-Study $Fixture).strata[0].design | Should -Be 'ab'
        Add-StudyBatch -Fixture $Fixture -Arm 'a' -Stratum 'development' -Record (Copy-StudyValue $Changed)
        { Invoke-Study $Fixture } | Should -Throw '*study-ab-source*'
    }
    It 'rejects mixed protocol fingerprints within a stratum but permits separate strata' {
        $Fixture = New-StudyFixture; Add-StudyBatch $Fixture 'b'
        $Fixture.records[1].protocol.model = 'synthetic-other-model'; Save-StudyBatch $Fixture 1
        { Invoke-Study $Fixture } | Should -Throw '*study-protocol-fingerprint*'
        $Fixture.manifest.strata += @{ stratumId = 'other'; taskId = 'synthetic-task'; taskRole = 'development'; design = 'descriptive'; protocolFingerprint = Get-StudyFingerprint $Fixture.records[1] }
        $Fixture.manifest.batches[1].stratumId = 'other'
        foreach ($Slot in $Fixture.manifest.slots | Where-Object batchId -EQ 'batch-1') { $Slot.stratumId = 'other' }
        (Invoke-Study $Fixture).strata.Count | Should -Be 2
    }
    It 'rejects absolute record paths after a valid in-root positive control' {
        $Fixture = New-StudyFixture
        (Invoke-Study $Fixture).state | Should -Be 'recorded-evidence-present'
        $Fixture.manifest.batches[0].recordPath = Join-Path $Fixture.repository $Fixture.manifest.batches[0].recordPath
        { Invoke-Study $Fixture } | Should -Throw '*study-record-path*'
    }
    It 'rejects traversal record paths after a valid in-root positive control' {
        $Fixture = New-StudyFixture
        (Invoke-Study $Fixture).state | Should -Be 'recorded-evidence-present'
        $Fixture.manifest.batches[0].recordPath = 'benchmarks/efficiency/records/../records/batch-0.json'
        { Invoke-Study $Fixture } | Should -Throw '*study-record-path*'
    }
    It 'rejects a real leaf symlink to an out-of-root record' {
        $Fixture = New-StudyFixture
        (Invoke-Study $Fixture).state | Should -Be 'recorded-evidence-present'
        $Path = Join-Path $Fixture.repository $Fixture.manifest.batches[0].recordPath
        $Outside = Join-Path $TestDrive 'outside-record.json'
        [IO.File]::Move($Path, $Outside)
        [void](New-Item -ItemType SymbolicLink -Path $Path -Target $Outside)
        (Get-Item -LiteralPath $Path).LinkType | Should -Be 'SymbolicLink'
        { Invoke-Study $Fixture } | Should -Throw '*study-symlink*'
    }
    It 'rejects real ancestor symlinks including a symlinked allowed root' {
        $Fixture = New-StudyFixture
        (Invoke-Study $Fixture).state | Should -Be 'recorded-evidence-present'
        $Root = Join-Path $Fixture.repository 'benchmarks/efficiency/records'
        $Outside = Join-Path $TestDrive 'outside-records'
        [IO.Directory]::Move($Root, $Outside)
        [void](New-Item -ItemType SymbolicLink -Path $Root -Target $Outside)
        { Invoke-Study $Fixture } | Should -Throw '*study-symlink*'
        [IO.File]::Delete($Root)
        [void][IO.Directory]::CreateDirectory($Root)
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $Root 'nested') -Target $Outside)
        $Fixture.manifest.batches[0].recordPath = 'benchmarks/efficiency/records/nested/batch-0.json'
        { Invoke-Study $Fixture } | Should -Throw '*study-symlink*'
    }
    It 'keeps aborted attempts unknown and validates explicit no-recorded plans' {
        $Fixture = New-StudyFixture; $Original = Copy-StudyValue $Fixture.manifest
        $Fixture.manifest.slots += @{ slotId = 'interrupted'; stratumId = 'development'; arm = 'a'; state = 'aborted'; reason = 'Synthetic interruption' }
        $Fixture.manifest.slots += @{ slotId = 'future'; stratumId = 'development'; arm = 'a'; state = 'planned' }
        $Arm = (Invoke-Study $Fixture).strata[0].arms[0]
        $Arm.counts.aborted | Should -Be 1; $Arm.counts.planned | Should -Be 1
        $Arm.portableEvidenceCoverage.value | Should -Be 0.75
        $Arm.portableEvidenceCoverage.denominator | Should -Be 4
        $Arm.recordedWorkflowAcceptance.value | Should -Be 1
        $Arm.attemptedRunReliability.value | Should -BeNullOrEmpty
        $Arm.completeAttemptConsumption.resources | Should -BeNullOrEmpty
        $Arm.attemptedRunReliability.reason | Should -Be 'interrupted-outcomes-and-resources-unknown'
        $Fixture.manifest.batches = @()
        $Fixture.manifest.slots = @($Fixture.manifest.slots | Where-Object state -NE 'recorded')
        $Fixture.manifest.strata[0].design = 'aa'
        $Result = Invoke-Study $Fixture; $Arm = $Result.strata[0].arms[0]
        $Result.state | Should -Be 'no-recorded-evidence'
        $Arm.counts.recorded | Should -Be 0
        $Arm.resources.total.credits.sum | Should -BeNullOrEmpty
        $Arm.resources.total.credits.reason | Should -Be 'no-recorded-observations'
        $Arm.documentQuality.total.mean | Should -BeNullOrEmpty
        $Arm.recordedConsumptionPerAcceptedWorkflow.credits.value | Should -BeNullOrEmpty
        $Arm.recordedConsumptionPerAcceptedWorkflow.credits.reason | Should -Be 'no-recorded-observations'
        $Arm.recordedWorkflowAcceptance.value | Should -BeNullOrEmpty
        $Arm.portableEvidenceCoverage.value | Should -Be 0
        $Result.calibration.coverage.value | Should -BeNullOrEmpty
        $Fixture.manifest.slots = @($Fixture.manifest.slots | Where-Object state -EQ 'planned')
        $Arm = (Invoke-Study $Fixture).strata[0].arms[0]
        $Arm.portableEvidenceCoverage.reason | Should -Be 'no-attempted-slots'
        foreach ($Mutation in @('schema', 'enum', 'id', 'shape', 'duplicate', 'abort')) {
            $Fixture.manifest = Copy-StudyValue $Original
            switch ($Mutation) {
                'schema' { $Fixture.manifest.schemaVersion = 'future' }
                'enum' { $Fixture.manifest.strata[0].taskRole = 'expert' }
                'id' { $Fixture.manifest.studyId = 'person@example.invalid' }
                'shape' { $Fixture.manifest.slots[0].metrics = @{} }
                'duplicate' { $Fixture.manifest.slots[1].slotId = $Fixture.manifest.slots[0].slotId }
                'abort' { $Fixture.manifest.slots = @(@{ slotId = 'x'; stratumId = 'development'; arm = 'a'; state = 'aborted'; reason = '' }) }
            }
            { Invoke-Study $Fixture } | Should -Throw
        }
    }
    It 'leaves zero-success consumption ratios unavailable without losing functional counts' {
        $Fixture = New-StudyFixture
        foreach ($Trial in $Fixture.records[0].trials) {
            $Trial.outcomes.completed = $false
            $Trial.processes.build.exitCode = 1; $Trial.outcomes['stage/build'] = $false
        }
        Save-StudyBatch $Fixture
        $Arm = (Invoke-Study $Fixture).strata[0].arms[0]
        $Arm.counts.functionalPassed | Should -Be 3; $Arm.counts.accepted | Should -Be 0
        $Arm.recordedWorkflowAcceptance.value | Should -Be 0
        $Arm.recordedConsumptionPerAcceptedWorkflow.credits.value | Should -BeNullOrEmpty
        $Arm.recordedConsumptionPerAcceptedWorkflow.credits.denominator | Should -Be 0
        $Arm.recordedConsumptionPerAcceptedWorkflow.credits.numerator | Should -Be 6
        $Arm.recordedConsumptionPerAcceptedWorkflow.credits.reason | Should -Be 'no-accepted-workflows'
    }
    It 'requires all document, source, rubric, implementation and model bindings' {
        $Fixture = New-StudyFixture; $Original = New-StudyAnnotations $Fixture
        foreach ($Key in @('recordSha256', 'measuredRevision', 'sourceHash', 'runId', 'rubric', 'judgeImplementationHash', 'recordedModel', 'recordedModelHash', 'brd', 'prd', 'closingReview')) {
            $Envelope = Copy-StudyValue $Original
            if ($Key -in @('brd', 'prd', 'closingReview')) { $Envelope.annotations[0].binding.documents[$Key] = '0' * 64 }
            else { $Envelope.annotations[0].binding[$Key] = 'invented' }
            { Invoke-AnnotatedStudy $Fixture $Envelope } | Should -Throw '*study-annotation-*'
        }
    }
    It 'rejects invalid dimensions, ranges, identities, attestations and duplicate ratings' {
        $Fixture = New-StudyFixture; $Original = New-StudyAnnotations $Fixture
        foreach ($Mutation in @('missing', 'unknown', 'range', 'fraction', 'boolean', 'status', 'personal', 'opaque', 'duplicate-id', 'duplicate-pair')) {
            $Envelope = Copy-StudyValue $Original
            switch ($Mutation) {
                'missing' { $Envelope.annotations[0].ratings.Remove('businessClarity') }
                'unknown' { $Envelope.annotations[0].ratings.extra = 1 }
                'range' { $Envelope.annotations[0].ratings.businessClarity = 21 }
                'fraction' { $Envelope.annotations[0].ratings.businessClarity = 1.5 }
                'boolean' { $Envelope.annotations[0].ratings.businessClarity = $true }
                'status' { $Envelope.annotations[0].attestation.status = 'expert-approved' }
                'personal' { $Envelope.annotations[0].attestation.name = 'Not accepted' }
                'opaque' { $Envelope.annotations[0].attestation.annotatorId = 'person@example.invalid' }
                'duplicate-id' { $Envelope.annotations += Copy-StudyValue $Envelope.annotations[0] }
                'duplicate-pair' {
                    $Envelope.annotations += Copy-StudyValue $Envelope.annotations[0]
                    $Envelope.annotations[1].annotationId = 'other'
                }
            }
            { Invoke-AnnotatedStudy $Fixture $Envelope } | Should -Throw '*study-*'
        }
    }
    It 'describes external rating pairs without authenticating humans or claiming calibration' {
        $Fixture = New-StudyFixture; $Envelope = New-StudyAnnotations $Fixture
        $Envelope.annotations[0].ratings.businessClarity = 17
        $Envelope.annotations += Copy-StudyValue $Envelope.annotations[0]
        $Envelope.annotations[1].annotationId = 'second'; $Envelope.annotations[1].attestation.annotatorId = 'another-rater'
        $Envelope.annotations[1].ratings.businessClarity = 19
        $Result = Invoke-AnnotatedStudy $Fixture $Envelope
        $Result.calibration.calibrationState | Should -Be 'external-ratings-present'
        $Result.calibration.attestationStatus | Should -Be 'externally-supplied-unauthenticated'
        $Result.calibration.expertApproval | Should -Be 'not-established'
        $Result.calibration.annotationCount | Should -Be 2
        $Result.calibration.ratedTrialCount | Should -Be 1
        $Result.calibration.coverage.denominator | Should -Be 3
        $Result.calibration.groups[0].dimensions.businessClarity.ratingPairCount | Should -Be 2
        $Result.calibration.groups[0].dimensions.businessClarity.disagreementCount | Should -Be 2
        $Result.calibration.groups[0].dimensions.businessClarity.meanAbsoluteDifference | Should -Be 2
        $Result.calibration.groups[0].dimensions.scopeFidelity.meanAbsoluteDifference | Should -Be 0
        $Result.calibration.bindings[0].recordedModelHash | Should -BeNullOrEmpty
        $Fixture.manifest.strata += @{ stratumId = 'heldout'; taskId = 'other-task'; taskRole = 'held-out'; design = 'descriptive'; protocolFingerprint = Get-StudyFingerprint $Fixture.records[0] }
        Add-StudyBatch -Fixture $Fixture -Arm 'a' -Stratum 'heldout'
        $Result = Invoke-AnnotatedStudy $Fixture $Envelope
        $Result.calibration.groups.Count | Should -Be 2
        ($Result.calibration.groups | Where-Object stratumId -CEQ 'heldout').dimensions.businessClarity.meanAbsoluteDifference | Should -BeNullOrEmpty
        $Text = ConvertTo-BenchmarkCanonicalJson $Result
        $Text | Should -Not -Match 'synthetic-rater|another-rater|synthetic-ref|annotatorId|attestationRef'
        $Result.strata[0].arms[0].counts.recorded | Should -Be 3
    }
}
