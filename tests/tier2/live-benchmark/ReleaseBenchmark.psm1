#Requires -Version 7.5
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BenchmarkResults.psm1')
Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1')

$script:ProtocolFiles = @(
    'tests/tier2/live-benchmark/efficiency-scenario.json',
    'tests/tier2/live-benchmark/EfficiencyBenchmark.psm1',
    'tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1',
    'tests/lib/SquadInstall.psm1',
    'tests/tier2/live-benchmark/Test-EfficiencyTask.ps1',
    'scripts/Test-SquadScribeOutput.ps1',
    'scripts/Build-SquadPlugin.ps1'
)
$script:PolicyPath = 'benchmarks/efficiency/collection-policy.json'
$script:FailureCategories = @(
    'collection-policy-shape', 'collection-policy-number', 'collection-policy-budget', 'collection-policy-runtime',
    'collection-commit', 'collection-controller-head', 'collection-version', 'collection-dependency-inputs',
    'collection-observation', 'collection-run-identity', 'collection-operational-stop', 'collection-reservation-exceeded',
    'collection-workflow-identity', 'collection-cli-version', 'collection-environment-incompatible',
    'collection-deadline', 'collection-campaign-exceeded', 'collection-child-failed', 'collection-child-without-evidence'
) + @($script:ProtocolFiles | ForEach-Object { "collection-protocol:$_" })

function Write-CollectionJson([string]$Path, $Value) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)))
    [IO.File]::WriteAllText($Path, (ConvertTo-BenchmarkCanonicalJson $Value), [Text.UTF8Encoding]::new($false))
}

function Get-CollectionPolicy {
    param([string]$Repository, [string]$Controller)
    $Bytes = Get-BenchmarkGitFile $Repository $Controller $script:PolicyPath
    $Policy = ConvertFrom-BenchmarkJson $Bytes
    if (($Policy.Keys | Sort-Object) -join ',' -cne 'campaignCredits,campaignTimeoutMinutes,cliVersion,model,perTrialCredits,schemaVersion' -or
        $Policy.schemaVersion -cne 'benchmark-collection-policy-v1') { throw 'collection-policy-shape' }
    foreach ($Name in @('perTrialCredits', 'campaignCredits', 'campaignTimeoutMinutes')) {
        $Value = $Policy[$Name]
        if ($Value -isnot [ValueType] -or $Value -is [bool] -or -not [double]::IsFinite([double]$Value) -or $Value -le 0) { throw 'collection-policy-number' }
    }
    if ($Policy.perTrialCredits -lt 60 -or $Policy.campaignCredits -lt 6 * [decimal]$Policy.perTrialCredits -or
        $Policy.campaignTimeoutMinutes -gt 330 -or $Policy.campaignTimeoutMinutes -lt 1) { throw 'collection-policy-budget' }
    if ($Policy.model -cnotmatch '^[a-z0-9][a-z0-9.-]{0,95}$' -or $Policy.cliVersion -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$') { throw 'collection-policy-runtime' }
    @{ policy = $Policy; sha256 = Get-BenchmarkDigest $Bytes }
}

function Get-CollectionManifestText([byte[]]$Bytes) {
    $Text = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes).Replace("`r`n", "`n")
    $Text = [regex]::Replace($Text, '(?m)^version: [^\n]+$', 'version: RELEASE-METADATA')
    [regex]::Replace($Text, '(?m)^(\s*- Peter-N91/hve-squad/squad-src/[A-Za-z0-9._/-]+)(?:#[A-Za-z0-9._/-]+)?$', '$1')
}

function Get-ReleaseBenchmarkPreflight {
    [CmdletBinding()]
    param([string]$Repository, [string]$Controller, [string]$Candidate, [string]$EffectiveVersion)
    foreach ($Sha in @($Controller, $Candidate)) { if ($Sha -cnotmatch '^[0-9a-f]{40}$') { throw 'collection-commit' } }
    if ((Resolve-BenchmarkCommit $Repository 'HEAD') -cne $Controller) { throw 'collection-controller-head' }
    if ($EffectiveVersion -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:[-+][0-9A-Za-z.-]+)?$') { throw 'collection-version' }
    $Config = Get-CollectionPolicy $Repository $Controller
    $Selection = Get-BenchmarkSelection $Repository $Controller -Historical
    $ComparisonPolicy = ConvertFrom-BenchmarkJson (Get-BenchmarkGitFile $Repository $Controller 'benchmarks/efficiency/policy.json')
    $null = Compare-BenchmarkSeries $Selection.record $Selection.record $ComparisonPolicy
    $Reference = $Selection.record.measuredRevision
    Assert-BenchmarkHistory $Repository $Controller $Candidate -AllowNewControllerRecords
    $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    foreach ($Path in $script:ProtocolFiles) {
        try {
            $Executing = Get-BenchmarkDigest ([IO.File]::ReadAllBytes((Join-Path $Root $Path)))
            foreach ($Ref in @($Controller, $Reference, $Candidate)) {
                if ((Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Ref $Path 8388608)) -cne $Executing) { throw "collection-protocol:$Path" }
            }
        }
        catch { throw "collection-protocol:$Path" }
    }
    @{
        controller = $Controller; candidate = $Candidate; reference = $Reference
        historicalRecordDigest = $Selection.sha256; collectionPolicyHash = $Config.sha256
        policy = $Config.policy; effectiveVersion = $EffectiveVersion; tag = "v$EffectiveVersion"
        referenceManifestHash = Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Reference 'apm.yml')
        candidateManifestHash = Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Candidate 'apm.yml')
    }
}

function New-CollectionReport([string]$Candidate) {
    [ordered]@{
        schemaVersion = 'benchmark-report-v1'; status = 'operational-error'; exitCode = 1
        baseCommit = $null; headCommit = $Candidate; mergeBase = $null; baseRecord = $null; headRecord = $null
        policyHash = $null; reasons = @('collection-not-complete'); improvementScreen = $false; deltas = @{}
        baseStatistics = $null; headStatistics = $null
        provenance = 'operator-reviewed-evidence-not-attestation'
    }
}

function Assert-CollectionRun {
    param($Run, [string]$Arm, [int]$Pair, [string]$Revision, $Compatibility, [decimal]$Reservation)
    if (-not (Test-EfficiencyObservation $Run) -or -not $Run.judge -or -not $Run.judge.valid -or
        -not (Test-EfficiencyJudge $Run.judge.response $Run.judge.documentHashes) -or $Run.stages.Count -ne 3) { throw 'collection-observation' }
    if ($Run.metadata.arm -cne $Arm -or $Run.metadata.pair -ne $Pair -or $Run.metadata.revision -cne $Revision -or
        (ConvertTo-BenchmarkCanonicalJson $Run.metadata.compatibility) -cne (ConvertTo-BenchmarkCanonicalJson $Compatibility)) { throw 'collection-run-identity' }
    $Processes = @($Run.stages | ForEach-Object {
        $_.process
        # Recovered context overflow is native recovery, not a campaign retry.
        foreach ($Attempt in $_.attempts) {
            if ($Attempt.process.stopCause -notin @('none', 'context-overflow')) { throw 'collection-operational-stop' }
        }
    }) + @($Run.judge.process)
    foreach ($Process in $Processes) {
        if ($Process.stopCause -cne 'none' -or $Process.exitCode -ne 0) { throw 'collection-operational-stop' }
    }
    [decimal]$Used = 0
    foreach ($Metrics in @($Run.metrics, $Run.judge.metrics)) {
        # The native workflow metrics are cumulative; never add stage snapshots.
        $Validated = Get-BenchmarkRawMetrics $Metrics 0
        $Used += [decimal]$Validated.credits
    }
    if ($Used -gt $Reservation) { throw 'collection-reservation-exceeded' }
    $Used
}

function Invoke-ReleaseBenchmark {
    [CmdletBinding()]
    param(
        [string]$Repository, [string]$Controller, [string]$Candidate, [string]$EffectiveVersion,
        [string]$InstallRoot, [string]$CliPath, [string]$PrivateRoot, [string]$OutputDirectory,
        [string]$RunId, [string]$RunAttempt, [string]$RepositorySlug,
        [DateTimeOffset]$Started = [DateTimeOffset]::UtcNow
    )
    $SafeCandidate = if ($Candidate -cmatch '^[0-9a-f]{40}$') { $Candidate } else { $null }
    $SafeVersion = if ($EffectiveVersion -cmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:[-+][0-9A-Za-z.-]+)?$') { $EffectiveVersion } else { $null }
    $Report = New-CollectionReport $SafeCandidate
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    Write-BenchmarkReport $Report $OutputDirectory
    $Slots = @(); $Runs = @(); [decimal]$Used = 0; $Reason = 'collection-preflight-failed'
    $Manifest = [ordered]@{
        schemaVersion = 'benchmark-release-identity-v1'
        runId = $(if ($RunId -cmatch '^[0-9]+$') { $RunId } else { $null })
        runAttempt = $(if ($RunAttempt -cmatch '^[0-9]+$') { $RunAttempt } else { $null })
        repository = $(if ($RepositorySlug -cmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { $RepositorySlug } else { $null })
        controller = $(if ($Controller -cmatch '^[0-9a-f]{40}$') { $Controller } else { $null })
        candidate = $SafeCandidate; reference = $null; effectiveVersion = $SafeVersion
        tag = $(if ($SafeVersion) { "v$SafeVersion" } else { $null })
        collectionPolicyHash = $null; comparisonPolicyHash = $null; historicalRecordDigest = $null
        baseRecordDigest = $null; headRecordDigest = $null; reportDigest = $null; verdict = 1; finalTagCommit = $null
        slots = @(); creditsUsed = 0
        comparisonScope = 'fresh-paired-deployments'
        referenceManifestHash = $null; candidateManifestHash = $null
    }
    Write-CollectionJson (Join-Path $OutputDirectory 'identity.json') $Manifest
    try {
        if ($RunId -cnotmatch '^[0-9]+$' -or $RunAttempt -cnotmatch '^[0-9]+$' -or $RepositorySlug -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'collection-workflow-identity' }
        $Context = Get-ReleaseBenchmarkPreflight $Repository $Controller $Candidate $EffectiveVersion
        foreach ($Name in @('reference', 'collectionPolicyHash', 'historicalRecordDigest', 'referenceManifestHash', 'candidateManifestHash')) { $Manifest[$Name] = $Context[$Name] }
        $Policy = $Context.policy
        $Deadline = $Started.AddMinutes([double]$Policy.campaignTimeoutMinutes)
        $ComparisonBytes = Get-BenchmarkGitFile $Repository $Controller 'benchmarks/efficiency/policy.json'
        $ComparisonPolicy = ConvertFrom-BenchmarkJson $ComparisonBytes
        $Report.policyHash = Get-BenchmarkDigest $ComparisonBytes
        $Report.baseCommit = $Context.reference
        $Manifest.comparisonPolicyHash = $Report.policyHash
        if ((@(& $CliPath --version) -join ' ').Trim() -cnotmatch ('^GitHub Copilot CLI ' + [regex]::Escape($Policy.cliVersion) + '(?:\. |$)')) { throw 'collection-cli-version' }
        [void][IO.Directory]::CreateDirectory($PrivateRoot)
        $Roots = @{}
        foreach ($Arm in @('baseline', 'candidate')) {
            $Roots[$Arm] = Join-Path $PrivateRoot $Arm
            $Revision = if ($Arm -ceq 'baseline') { $Context.reference } else { $Candidate }
            $null = Invoke-BenchmarkGit $Repository @('worktree', 'add', '--detach', $Roots[$Arm], $Revision)
        }
        $Expected = @{}
        foreach ($Arm in @('baseline', 'candidate')) {
            $Expected[$Arm] = Get-EfficiencyCompatibility -SourceRoot $Roots[$Arm] -InstallRoot (Join-Path $InstallRoot $Arm) -CliPath $CliPath -Model $Policy.model -MaxCredits $Policy.perTrialCredits -ObservationOnly
        }
        foreach ($Key in $Expected.baseline.Keys) {
            if ($Key -ceq 'installHash') { continue }
            if ((ConvertTo-BenchmarkCanonicalJson $Expected.baseline[$Key]) -cne (ConvertTo-BenchmarkCanonicalJson $Expected.candidate[$Key])) { throw 'collection-environment-incompatible' }
        }
        $Reason = 'collection-execution-failed'
        foreach ($Pair in 1..3) {
            foreach ($Arm in @('baseline', 'candidate')) {
                $Remaining = [Math]::Floor(($Deadline - [DateTimeOffset]::UtcNow).TotalSeconds)
                if ($Remaining -lt 1) { throw 'collection-deadline' }
                if ($Used + [decimal]$Policy.perTrialCredits -gt [decimal]$Policy.campaignCredits) { throw 'collection-campaign-exceeded' }
                $TrialPath = Join-Path $PrivateRoot "trials/$Arm-$Pair"
                [void][IO.Directory]::CreateDirectory((Split-Path $TrialPath))
                $Slot = @{ arm = $Arm; pair = $Pair; status = 'launched'; credits = $null }
                $Slots += $Slot
                $Manifest.slots = $Slots
                Write-CollectionJson (Join-Path $OutputDirectory 'identity.json') $Manifest
                $Arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'), '-Mode', 'Run',
                    '-TrialRoot', $TrialPath, '-SourceRoot', $Roots[$Arm], '-InstallRoot', (Join-Path $InstallRoot $Arm),
                    '-Arm', $Arm, '-Pair', [string]$Pair, '-Model', $Policy.model, '-CliPath', $CliPath,
                    '-MaxCredits', ([double]$Policy.perTrialCredits).ToString('R', [Globalization.CultureInfo]::InvariantCulture),
                    '-Live', '-IsolatedEnvironment', '-ObservationOnly')
                $Process = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments $Arguments -WorkingDirectory $PrivateRoot -OutputPath (Join-Path $PrivateRoot "$Arm-$Pair-launch.jsonl") -TimeoutSeconds ([int]$Remaining)
                if ($Process.stopCause -cne 'none') { throw 'collection-deadline' }
                if ($Process.exitCode -notin @(0, 2)) { throw 'collection-child-failed' }
                $RunPath = Join-Path $TrialPath 'out/run.json'
                if (-not (Test-Path -LiteralPath $RunPath -PathType Leaf)) { throw 'collection-child-without-evidence' }
                $Run = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes($RunPath)) 16777216
                $Revision = if ($Arm -ceq 'baseline') { $Context.reference } else { $Candidate }
                $Credits = Assert-CollectionRun $Run $Arm $Pair $Revision $Expected[$Arm] $Policy.perTrialCredits
                $Used += $Credits
                if ($Used -gt [decimal]$Policy.campaignCredits) { throw 'collection-campaign-exceeded' }
                $Slot.status = 'recorded'; $Slot.credits = $Credits
                $Manifest.creditsUsed = $Used
                $Runs += $Run
                Write-CollectionJson (Join-Path $OutputDirectory 'identity.json') $Manifest
            }
        }
        $Reason = 'collection-export-failed'
        $RawPath = Join-Path $PrivateRoot 'series-evidence.json'
        Write-CollectionJson $RawPath @{ runs = $Runs }
        foreach ($Arm in @('baseline', 'candidate')) {
            $Id = "release-$RunId-$RunAttempt-$Arm"
            $Directories = @(1..3 | ForEach-Object { Join-Path $PrivateRoot "trials/$Arm-$_" })
            $Record = Export-BenchmarkSeries -Repository $Roots[$Arm] -ControlPath $RawPath -TrialDirectories $Directories -SeriesId $Id
            $Name = if ($Arm -ceq 'baseline') { 'base' } else { 'head' }
            $Bytes = [IO.File]::ReadAllBytes((Join-Path $Roots[$Arm] "benchmarks/efficiency/records/$Id.json"))
            [IO.File]::WriteAllBytes((Join-Path $OutputDirectory "$Name-record.json"), $Bytes)
            $Manifest[$Name + 'RecordDigest'] = Get-BenchmarkDigest $Bytes
            $Report[$Name + 'Record'] = @{ seriesId = $Id; sha256 = Get-BenchmarkDigest $Bytes; sourceHash = $Record.sourceHash; measuredRevision = $Record.measuredRevision; protocol = $Record.protocol }
            if ($Name -ceq 'base') { $Base = $Record } else { $Head = $Record }
        }
        $Reason = 'collection-comparison-failed'
        $Comparison = Compare-BenchmarkSeries $Base $Head $ComparisonPolicy -DeploymentComparison
        foreach ($Key in $Comparison.Keys) { $Report[$Key] = $Comparison[$Key] }
        $Report['comparisonScope'] = 'fresh-paired-deployments'
    }
    catch {
        $Report.status = 'operational-error'; $Report.exitCode = 1
        $Category = $_.Exception.Message
        $Report.reasons = @($(if ($Category -cin $script:FailureCategories) { $Category } else { $Reason }))
        if ($Slots.Count -and $Slots[-1].status -ceq 'launched') { $Slots[-1].status = 'failed' }
    }
    finally {
        Write-BenchmarkReport $Report $OutputDirectory
        'Fresh paired deployment comparison: each arm uses its own frozen package dependencies. Installation differences are measured treatment, not evidence of source-only causality; all other protocol fields must agree.' |
            Add-Content -LiteralPath (Join-Path $OutputDirectory 'report.md')
        $Manifest.reportDigest = Get-BenchmarkDigest ([IO.File]::ReadAllBytes((Join-Path $OutputDirectory 'report.json')))
        $Manifest.verdict = $Report.exitCode
        Write-CollectionJson (Join-Path $OutputDirectory 'identity.json') $Manifest
    }
    $Report
}

function Assert-ReleaseBenchmarkPublication {
    [CmdletBinding()]
    param(
        [string]$Repository, [string]$OutputDirectory, [string]$Controller, [string]$Candidate,
        [string]$EffectiveVersion, [string]$RunId, [string]$RunAttempt, [string]$RepositorySlug,
        [string]$ManifestDigest, [switch]$BindFinalCommit
    )
    $IdentityPath = Join-Path $OutputDirectory 'identity.json'
    $Bytes = [IO.File]::ReadAllBytes($IdentityPath)
    if ((Get-BenchmarkDigest $Bytes) -cne $ManifestDigest) { throw 'publication-manifest-digest' }
    $Identity = ConvertFrom-BenchmarkJson $Bytes
    if ($Identity.schemaVersion -cne 'benchmark-release-identity-v1' -or $Identity.verdict -ne 0 -or $null -ne $Identity.finalTagCommit) { throw 'publication-verdict' }
    foreach ($Expected in @{
        controller = $Controller; candidate = $Candidate; effectiveVersion = $EffectiveVersion; tag = "v$EffectiveVersion"
        runId = $RunId; runAttempt = $RunAttempt; repository = $RepositorySlug
    }.GetEnumerator()) {
        if ($Identity[$Expected.Key] -cne $Expected.Value) { throw 'publication-identity' }
    }
    $Selection = Get-BenchmarkSelection $Repository $Controller -Historical
    if ($Identity.reference -cne $Selection.record.measuredRevision -or $Identity.historicalRecordDigest -cne $Selection.sha256) { throw 'publication-reference' }
    if ($Identity.comparisonScope -cne 'fresh-paired-deployments' -or
        $Identity.referenceManifestHash -cne (Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Identity.reference 'apm.yml')) -or
        $Identity.candidateManifestHash -cne (Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Candidate 'apm.yml'))) { throw 'publication-dependency-inputs' }
    $Config = Get-CollectionPolicy $Repository $Controller
    if ($Config.sha256 -cne $Identity.collectionPolicyHash) { throw 'publication-policy' }
    $PolicyBytes = Get-BenchmarkGitFile $Repository $Controller 'benchmarks/efficiency/policy.json'
    if ((Get-BenchmarkDigest $PolicyBytes) -cne $Identity.comparisonPolicyHash) { throw 'publication-policy' }
    $Records = @{}
    foreach ($Name in @('base', 'head')) {
        $RecordBytes = [IO.File]::ReadAllBytes((Join-Path $OutputDirectory "$Name-record.json"))
        if ((Get-BenchmarkDigest $RecordBytes) -cne $Identity[$Name + 'RecordDigest']) { throw 'publication-record-digest' }
        $Record = ConvertFrom-BenchmarkJson $RecordBytes
        Assert-BenchmarkHistoricalSeries $Repository $Record
        $Revision = if ($Name -ceq 'base') { $Identity.reference } else { $Candidate }
        if ($Record.schemaVersion -cne 'benchmark-series-v2' -or $Record.measuredRevision -cne $Revision -or
            $Record.protocol.model -cne $Config.policy.model -or $Record.protocol.cliVersion -cne $Config.policy.cliVersion -or
            $Record.protocol.maxCredits -ne $Config.policy.perTrialCredits) { throw 'publication-record-identity' }
        $Records[$Name] = $Record
    }
    $Comparison = Compare-BenchmarkSeries $Records.base $Records.head (ConvertFrom-BenchmarkJson $PolicyBytes) -DeploymentComparison
    if ($Identity.slots.Count -ne 6) { throw 'publication-slots' }
    [decimal]$Used = 0
    foreach ($Arm in @('baseline', 'candidate')) {
        $Name = if ($Arm -ceq 'baseline') { 'base' } else { 'head' }
        foreach ($Pair in 1..3) {
            $Slots = @($Identity.slots | Where-Object { $_.arm -ceq $Arm -and $_.pair -eq $Pair })
            $Trial = @($Records[$Name].trials | Where-Object slot -EQ $Pair)[0]
            [decimal]$Credits = [decimal]$Trial.workflow.credits + [decimal]$Trial.judge.credits
            if ($Slots.Count -ne 1 -or $Slots[0].status -cne 'recorded' -or $Slots[0].credits -ne $Credits -or
                $Credits -gt [decimal]$Config.policy.perTrialCredits) { throw 'publication-accounting' }
            $Used += $Credits
        }
    }
    if ($Used -ne $Identity.creditsUsed -or $Used -gt [decimal]$Config.policy.campaignCredits) { throw 'publication-accounting' }
    $ReportBytes = [IO.File]::ReadAllBytes((Join-Path $OutputDirectory 'report.json'))
    if ((Get-BenchmarkDigest $ReportBytes) -cne $Identity.reportDigest) { throw 'publication-report-digest' }
    $Report = ConvertFrom-BenchmarkJson $ReportBytes
    if ($Report.schemaVersion -cne 'benchmark-report-v1' -or $Report.exitCode -ne 0 -or
        $Report.baseCommit -cne $Identity.reference -or $Report.headCommit -cne $Candidate -or $Report.policyHash -cne $Identity.comparisonPolicyHash -or
        $Report.comparisonScope -cne 'fresh-paired-deployments') { throw 'publication-report-identity' }
    foreach ($Key in $Comparison.Keys) {
        if ((ConvertTo-BenchmarkCanonicalJson $Report[$Key]) -cne (ConvertTo-BenchmarkCanonicalJson $Comparison[$Key])) { throw 'publication-comparison' }
    }
    foreach ($Name in @('base', 'head')) {
        if ($Report[$Name + 'Record'].sha256 -cne $Identity[$Name + 'RecordDigest'] -or
            $Report[$Name + 'Record'].measuredRevision -cne $Records[$Name].measuredRevision) { throw 'publication-report-record' }
    }
    if ($Comparison.exitCode -ne 0) { throw 'publication-regression' }
    Assert-BenchmarkHistory $Repository $Controller $Candidate -AllowNewControllerRecords
    $Final = Resolve-BenchmarkCommit $Repository 'HEAD'
    if ($null -eq (Invoke-BenchmarkGit $Repository @('merge-base', '--is-ancestor', $Candidate, $Final) -AllowFailure)) { throw 'publication-ancestry' }
    $Changed = [Text.Encoding]::UTF8.GetString((Invoke-BenchmarkGit $Repository @('diff', '--name-only', $Candidate, $Final))).Trim()
    if ($Changed -and $Changed -cne 'apm.yml') { throw 'publication-product-changed' }
    $Before = Get-BenchmarkGitFile $Repository $Candidate 'apm.yml'
    $After = Get-BenchmarkGitFile $Repository $Final 'apm.yml'
    if ((Get-CollectionManifestText $Before) -cne (Get-CollectionManifestText $After)) { throw 'publication-dependencies-changed' }
    if ($BindFinalCommit) {
        $Text = [Text.Encoding]::UTF8.GetString($After)
        if ([regex]::Matches($Text, '(?m)^version: ' + [regex]::Escape($EffectiveVersion) + '\r?$').Count -ne 1) { throw 'publication-version' }
        foreach ($Line in $Text.Split("`n") | Where-Object { $_ -cmatch '^\s*- Peter-N91/hve-squad/squad-src/' }) {
            if ($Line.TrimEnd("`r") -cnotmatch ('#' + [regex]::Escape($Identity.tag) + '$')) { throw 'publication-self-pin' }
        }
        $Identity.finalTagCommit = $Final
        Write-CollectionJson $IdentityPath $Identity
    }
    $Identity
}

Export-ModuleMember -Function Get-CollectionPolicy, Get-ReleaseBenchmarkPreflight, Invoke-ReleaseBenchmark, Assert-ReleaseBenchmarkPublication
