#Requires -Version 7.5
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Validates release collection policy, collects trials and checks publication evidence.
# AI cost: Invoke-ReleaseBenchmark launches 3 paid candidate trials, or 6 with reference
# refresh, including each trial's judge. Importing and preflight/report validation call no model.

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
    param([string]$Repository, [string]$Controller, [switch]$RefreshReference)
    $Bytes = Get-BenchmarkGitFile $Repository $Controller $script:PolicyPath
    $Policy = ConvertFrom-BenchmarkJson $Bytes
    if (($Policy.Keys | Sort-Object) -join ',' -cne 'campaignCredits,campaignTimeoutMinutes,cliVersion,model,perTrialCredits,schemaVersion' -or
        $Policy.schemaVersion -cne 'benchmark-collection-policy-v1') { throw 'collection-policy-shape' }
    foreach ($Name in @('perTrialCredits', 'campaignCredits', 'campaignTimeoutMinutes')) {
        $Value = $Policy[$Name]
        if ($Value -isnot [ValueType] -or $Value -is [bool] -or -not [double]::IsFinite([double]$Value) -or $Value -le 0) { throw 'collection-policy-number' }
    }
    $Count = if ($RefreshReference) { 6 } else { 3 }
    if ($Policy.perTrialCredits -lt 60 -or $Policy.campaignCredits -lt $Count * [decimal]$Policy.perTrialCredits -or
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
    param([string]$Repository, [string]$Controller, [string]$Candidate, [string]$EffectiveVersion, [switch]$RefreshReference)
    foreach ($Sha in @($Controller, $Candidate)) { if ($Sha -cnotmatch '^[0-9a-f]{40}$') { throw 'collection-commit' } }
    if ((Resolve-BenchmarkCommit $Repository 'HEAD') -cne $Controller) { throw 'collection-controller-head' }
    if ($EffectiveVersion -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:[-+][0-9A-Za-z.-]+)?$') { throw 'collection-version' }
    $Config = Get-CollectionPolicy $Repository $Controller -RefreshReference:$RefreshReference
    $Selection = Get-BenchmarkSelection $Repository $Controller -Historical
    $ComparisonPolicy = ConvertFrom-BenchmarkJson (Get-BenchmarkGitFile $Repository $Controller 'benchmarks/efficiency/policy.json')
    $null = Compare-BenchmarkSeries $Selection.record $Selection.record $ComparisonPolicy
    $Reference = if ($RefreshReference) { $Controller } else { $Selection.record.measuredRevision }
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
        historicalRecordBytes = $Selection.bytes; refreshReference = [bool]$RefreshReference
        arms = $(if ($RefreshReference) { @('baseline', 'candidate') } else { @('candidate') })
        reservedCredits = $(if ($RefreshReference) { 6 } else { 3 }) * [decimal]$Config.policy.perTrialCredits
        policy = $Config.policy; effectiveVersion = $EffectiveVersion; tag = "v$EffectiveVersion"
        referenceManifestHash = Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Reference 'apm.yml')
        candidateManifestHash = Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Candidate 'apm.yml')
    }
}

function New-CollectionReport([string]$Candidate, [bool]$RefreshReference) {
    [ordered]@{
        schemaVersion = 'benchmark-report-v1'; status = 'operational-error'; exitCode = 1
        baseCommit = $null; headCommit = $Candidate; mergeBase = $null; baseRecord = $null; headRecord = $null
        policyHash = $null; reasons = @('collection-not-complete'); improvementScreen = $false; deltas = @{}
        baseStatistics = $null; headStatistics = $null
        provenance = 'operator-reviewed-evidence-not-attestation'
        comparisonScope = $(if ($RefreshReference) { 'fresh-paired-deployments' } else { 'historical-reference' })
        protocolDifferences = @{}
        comparisonWarning = $(if ($RefreshReference) {
                'Fresh paired deployment comparison: installation differences are measured treatment, not evidence of source-only causality.'
            } else {
                'Approximate historical comparison: the stored parent was measured in an older environment. All original metrics and protocol values are retained; this is not source-only causality or equal-environment evidence.'
            })
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

function Get-CollectionAccounting {
    param([Collections.IDictionary]$Run)
    [decimal]$Known = 0
    $Complete = $true
    $Judge = $Run['judge']
    $JudgeMetrics = if ($Judge -is [Collections.IDictionary]) { $Judge['metrics'] } else { $null }
    foreach ($Metrics in @($Run['metrics'], $JudgeMetrics)) {
        $Credits = if ($Metrics -is [Collections.IDictionary]) { $Metrics['credits'] } else { $null }
        if ($Credits -isnot [Collections.IDictionary] -or $Credits['complete'] -cne $true) {
            $Complete = $false
            continue
        }
        $Value = $Credits['used']
        if ($Value -isnot [ValueType] -or $Value -is [bool] -or
            -not [double]::IsFinite([double]$Value) -or $Value -lt 0 -or $Value -ge [decimal]::MaxValue -or
            $Value -ge ([decimal]::MaxValue - $Known)) {
            $Complete = $false
            continue
        }
        # Workflow meters are cumulative; count the final snapshot and judge once.
        $Known += [decimal]$Value
    }
    @{ known = $Known; complete = $Complete }
}

function Invoke-ReleaseBenchmark {
    [CmdletBinding()]
    param(
        [string]$Repository, [string]$Controller, [string]$Candidate, [string]$EffectiveVersion,
        [string]$InstallRoot, [string]$CliPath, [string]$PrivateRoot, [string]$OutputDirectory,
        [string]$RunId, [string]$RunAttempt, [string]$RepositorySlug,
        [DateTimeOffset]$Started = [DateTimeOffset]::UtcNow, [switch]$RefreshReference
    )
    $SafeCandidate = if ($Candidate -cmatch '^[0-9a-f]{40}$') { $Candidate } else { $null }
    $SafeVersion = if ($EffectiveVersion -cmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:[-+][0-9A-Za-z.-]+)?$') { $EffectiveVersion } else { $null }
    $Report = New-CollectionReport $SafeCandidate ([bool]$RefreshReference)
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
        slots = @(); creditsUsed = 0; creditsKnown = 0; accountingComplete = $true
        refreshReference = [bool]$RefreshReference
        comparisonScope = $Report.comparisonScope
        protocolDifferences = @{}; comparisonWarning = $Report.comparisonWarning
        referenceManifestHash = $null; candidateManifestHash = $null
    }
    Write-CollectionJson (Join-Path $OutputDirectory 'identity.json') $Manifest
    try {
        if ($RunId -cnotmatch '^[0-9]+$' -or $RunAttempt -cnotmatch '^[0-9]+$' -or $RepositorySlug -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'collection-workflow-identity' }
        $Context = Get-ReleaseBenchmarkPreflight $Repository $Controller $Candidate $EffectiveVersion -RefreshReference:$RefreshReference
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
        foreach ($Arm in $Context.arms) {
            $Roots[$Arm] = Join-Path $PrivateRoot $Arm
            $Revision = if ($Arm -ceq 'baseline') { $Context.reference } else { $Candidate }
            $null = Invoke-BenchmarkGit $Repository @('worktree', 'add', '--detach', $Roots[$Arm], $Revision)
        }
        $Expected = @{}
        foreach ($Arm in $Context.arms) {
            $Expected[$Arm] = Get-EfficiencyCompatibility -SourceRoot $Roots[$Arm] -InstallRoot (Join-Path $InstallRoot $Arm) -CliPath $CliPath -Model $Policy.model -MaxCredits $Policy.perTrialCredits -ObservationOnly
        }
        if ($RefreshReference) {
            foreach ($Key in $Expected.baseline.Keys) {
                if ($Key -ceq 'installHash') { continue }
                if ((ConvertTo-BenchmarkCanonicalJson $Expected.baseline[$Key]) -cne (ConvertTo-BenchmarkCanonicalJson $Expected.candidate[$Key])) { throw 'collection-environment-incompatible' }
            }
        } else {
            $Base = ConvertFrom-BenchmarkJson $Context.historicalRecordBytes
            $CandidateProtocol = Get-BenchmarkProtocol $Roots.candidate $Candidate $Expected.candidate
            $Differences = Get-BenchmarkProtocolDifferences $Base.protocol $CandidateProtocol -HistoricalReference
            $Report.protocolDifferences = $Differences; $Manifest.protocolDifferences = $Differences
            [IO.File]::WriteAllBytes((Join-Path $OutputDirectory 'base-record.json'), $Context.historicalRecordBytes)
            $Manifest.baseRecordDigest = $Context.historicalRecordDigest
            $Report.baseRecord = @{ seriesId = $Base.seriesId; sha256 = $Context.historicalRecordDigest; sourceHash = $Base.sourceHash; measuredRevision = $Base.measuredRevision; protocol = $Base.protocol }
        }
        $Reason = 'collection-execution-failed'
        foreach ($Pair in 1..3) {
            foreach ($Arm in $Context.arms) {
                $Remaining = [Math]::Floor(($Deadline - [DateTimeOffset]::UtcNow).TotalSeconds)
                if ($Remaining -lt 1) { throw 'collection-deadline' }
                if ($Used + [decimal]$Policy.perTrialCredits -gt [decimal]$Policy.campaignCredits) { throw 'collection-campaign-exceeded' }
                $TrialPath = Join-Path $PrivateRoot "trials/$Arm-$Pair"
                [void][IO.Directory]::CreateDirectory((Split-Path $TrialPath))
                $Slot = @{ arm = $Arm; pair = $Pair; status = 'launched'; credits = $null; creditsKnown = 0; accountingComplete = $false }
                $Slots += $Slot
                $Manifest.slots = $Slots
                $Manifest.creditsUsed = $null
                $Manifest.accountingComplete = $false
                Write-CollectionJson (Join-Path $OutputDirectory 'identity.json') $Manifest
                $Arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'), '-Mode', 'Run',
                    '-TrialRoot', $TrialPath, '-SourceRoot', $Roots[$Arm], '-InstallRoot', (Join-Path $InstallRoot $Arm),
                    '-Arm', $Arm, '-Pair', [string]$Pair, '-Model', $Policy.model, '-CliPath', $CliPath,
                    '-MaxCredits', ([double]$Policy.perTrialCredits).ToString('R', [Globalization.CultureInfo]::InvariantCulture),
                    '-Live', '-IsolatedEnvironment', '-ObservationOnly')
                $Process = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments $Arguments -WorkingDirectory $PrivateRoot -OutputPath (Join-Path $PrivateRoot "$Arm-$Pair-launch.jsonl") -TimeoutSeconds ([int]$Remaining)
                $RunPath = Join-Path $TrialPath 'out/run.json'
                $Run = $null
                if (Test-Path -LiteralPath $RunPath -PathType Leaf) {
                    $Run = ConvertFrom-BenchmarkJson ([IO.File]::ReadAllBytes($RunPath)) 16777216
                    $Accounting = Get-CollectionAccounting $Run
                    $Slot.creditsKnown = $Accounting.known
                    $Slot.accountingComplete = $Accounting.complete -and $Process.stopCause -ceq 'none'
                    if ($Slot.accountingComplete) { $Slot.credits = $Accounting.known }
                    $Manifest.creditsKnown += $Accounting.known
                    $Manifest.accountingComplete = $Slot.accountingComplete
                    if ($Manifest.accountingComplete) { $Manifest.creditsUsed = $Manifest.creditsKnown }
                }
                if ($Process.stopCause -cne 'none') { throw 'collection-deadline' }
                if ($Process.exitCode -notin @(0, 2)) { throw 'collection-child-failed' }
                if ($null -eq $Run) { throw 'collection-child-without-evidence' }
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
        $RawEvidence = @{ runs = $Runs }
        if (-not $RefreshReference) { $RawEvidence.schemaVersion = 'efficiency-control-v1' }
        Write-CollectionJson $RawPath $RawEvidence
        foreach ($Arm in $Context.arms) {
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
        $Comparison = Compare-BenchmarkSeries $Base $Head $ComparisonPolicy -DeploymentComparison:$RefreshReference -HistoricalReference:(-not $RefreshReference)
        foreach ($Key in $Comparison.Keys) { $Report[$Key] = $Comparison[$Key] }
        foreach ($Key in @('comparisonScope', 'protocolDifferences', 'comparisonWarning')) { $Manifest[$Key] = $Comparison[$Key] }
    }
    catch {
        $Report.status = 'operational-error'; $Report.exitCode = 1
        $Category = $_.Exception.Message
        $Report.reasons = @($(if ($Category -cin $script:FailureCategories) { $Category } else { $Reason }))
        if ($Slots.Count -and $Slots[-1].status -ceq 'launched') { $Slots[-1].status = 'failed' }
    }
    finally {
        Write-BenchmarkReport $Report $OutputDirectory
        $Spending = if ($Manifest.accountingComplete) { "Credits used: $($Manifest.creditsUsed) (complete accounting)." }
        else { "Known credits used: $($Manifest.creditsKnown) (lower bound; total unknown because accounting is incomplete)." }
        $Spending | Add-Content -LiteralPath (Join-Path $OutputDirectory 'report.md')
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
        [string]$ManifestDigest, [switch]$BindFinalCommit, [switch]$ExpectedRefresh
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
    $Scope = if ($ExpectedRefresh) { 'fresh-paired-deployments' } else { 'historical-reference' }
    if ($Identity.refreshReference -isnot [bool] -or $Identity.refreshReference -ne [bool]$ExpectedRefresh -or $Identity.comparisonScope -cne $Scope) { throw 'publication-mode' }
    $Selection = Get-BenchmarkSelection $Repository $Controller -Historical
    $ExpectedReference = if ($ExpectedRefresh) { $Controller } else { $Selection.record.measuredRevision }
    if ($Identity.reference -cne $ExpectedReference -or $Identity.historicalRecordDigest -cne $Selection.sha256) { throw 'publication-reference' }
    if (
        $Identity.referenceManifestHash -cne (Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Identity.reference 'apm.yml')) -or
        $Identity.candidateManifestHash -cne (Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Candidate 'apm.yml'))) { throw 'publication-dependency-inputs' }
    $Config = Get-CollectionPolicy $Repository $Controller -RefreshReference:$ExpectedRefresh
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
        if ($Record.schemaVersion -cne 'benchmark-series-v2' -or $Record.measuredRevision -cne $Revision) { throw 'publication-record-identity' }
        if ($Name -ceq 'base' -and -not $ExpectedRefresh) {
            if ((Get-BenchmarkDigest $RecordBytes) -cne $Selection.sha256) { throw 'publication-historical-bytes' }
        } else {
            $Arm = if ($Name -ceq 'base') { 'baseline' } else { 'candidate' }
            if ($Record.seriesId -cne "release-$RunId-$RunAttempt-$Arm" -or
                $Record.protocol.model -cne $Config.policy.model -or $Record.protocol.cliVersion -cne $Config.policy.cliVersion -or
                $Record.protocol.maxCredits -ne $Config.policy.perTrialCredits -or
                $Record.protocol.powershell -cne $PSVersionTable.PSVersion.ToString()) { throw 'publication-record-identity' }
        }
        $Records[$Name] = $Record
    }
    $Comparison = Compare-BenchmarkSeries $Records.base $Records.head (ConvertFrom-BenchmarkJson $PolicyBytes) -DeploymentComparison:$ExpectedRefresh -HistoricalReference:(-not $ExpectedRefresh)
    foreach ($Key in @('comparisonScope', 'protocolDifferences', 'comparisonWarning')) {
        if ((ConvertTo-BenchmarkCanonicalJson $Identity[$Key]) -cne (ConvertTo-BenchmarkCanonicalJson $Comparison[$Key])) { throw 'publication-mode' }
    }
    $Arms = @(if ($ExpectedRefresh) { 'baseline'; 'candidate' } else { 'candidate' })
    if ($Identity.slots.Count -ne 3 * $Arms.Count) { throw 'publication-slots' }
    if ($Identity.accountingComplete -cne $true -or $null -eq $Identity.creditsUsed -or
        $Identity.creditsKnown -ne $Identity.creditsUsed) { throw 'publication-accounting' }
    [decimal]$Used = 0
    foreach ($Arm in $Arms) {
        $Name = if ($Arm -ceq 'baseline') { 'base' } else { 'head' }
        foreach ($Pair in 1..3) {
            $Slots = @($Identity.slots | Where-Object { $_.arm -ceq $Arm -and $_.pair -eq $Pair })
            $Trial = @($Records[$Name].trials | Where-Object slot -EQ $Pair)[0]
            [decimal]$Credits = [decimal]$Trial.workflow.credits + [decimal]$Trial.judge.credits
            if ($Slots.Count -ne 1 -or $Slots[0].status -cne 'recorded' -or $Slots[0].credits -ne $Credits -or
                $Slots[0].accountingComplete -cne $true -or $Slots[0].creditsKnown -ne $Credits -or
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
        $Report.comparisonScope -cne $Scope) { throw 'publication-report-identity' }
    # Apply the report reader's numeric representation to recomputed statistics,
    # not to either original record or its protocol.
    $PersistedComparison = ConvertFrom-BenchmarkJson ([Text.Encoding]::UTF8.GetBytes((ConvertTo-BenchmarkCanonicalJson $Comparison)))
    foreach ($Key in $PersistedComparison.Keys) {
        if ((ConvertTo-BenchmarkCanonicalJson $Report[$Key]) -cne (ConvertTo-BenchmarkCanonicalJson $PersistedComparison[$Key])) { throw 'publication-comparison' }
    }
    foreach ($Name in @('base', 'head')) {
        $ExpectedRecord = @{
            sha256 = $Identity[$Name + 'RecordDigest']; seriesId = $Records[$Name].seriesId
            sourceHash = $Records[$Name].sourceHash; measuredRevision = $Records[$Name].measuredRevision; protocol = $Records[$Name].protocol
        }
        if ((ConvertTo-BenchmarkCanonicalJson $Report[$Name + 'Record']) -cne (ConvertTo-BenchmarkCanonicalJson $ExpectedRecord)) { throw 'publication-report-record' }
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
