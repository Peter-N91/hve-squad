#Requires -Version 7.5
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BenchmarkResults.psm1')
$script:StudyDimensions = @('businessClarity', 'scopeFidelity', 'acceptanceCriteria', 'traceability', 'risksAndDecisions')
$script:StudyResources = @('credits', 'requests', 'inputTokens', 'outputTokens', 'toolCalls', 'failedTools', 'measuredProcessWallSeconds', 'cacheReadTokens', 'cacheWriteTokens', 'eventElapsedMs')

function Stop-BenchmarkStudy {
    param([string]$Reason)
    throw [IO.InvalidDataException]::new("invalid-record:study-$Reason")
}

function Assert-StudyKeys {
    param($Value, [string[]]$Keys)
    if ($Value -isnot [Collections.IDictionary] -or $Value.Count -ne $Keys.Count) { Stop-BenchmarkStudy 'object-shape' }
    foreach ($Key in $Keys) { if (-not $Value.Contains($Key)) { Stop-BenchmarkStudy 'object-key' } }
}

function Assert-StudyId {
    param($Value)
    if ($Value -isnot [string] -or $Value -cnotmatch '^[a-z0-9][a-z0-9_-]{0,95}$') { Stop-BenchmarkStudy 'opaque-id' }
}

function Assert-StudyHash {
    param($Value)
    if ($Value -isnot [string] -or $Value -cnotmatch '^[0-9a-f]{64}$') { Stop-BenchmarkStudy 'digest' }
}

function Read-StudyFile {
    param([string]$Path)
    try {
        $FullPath = [IO.Path]::GetFullPath($Path)
        $Item = Get-Item -LiteralPath $FullPath -Force
        if ($Item -isnot [IO.FileInfo]) { Stop-BenchmarkStudy 'regular-file' }
        # Inspect the entire path, including the allowed root and its ancestors.
        $Ancestor = $Item
        while ($null -ne $Ancestor) {
            if (($Ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Stop-BenchmarkStudy 'symlink' }
            $Ancestor = if ($Ancestor -is [IO.FileInfo]) { $Ancestor.Directory } else { $Ancestor.Parent }
        }
        if ($Item.Length -eq 0 -or $Item.Length -gt 262144) { Stop-BenchmarkStudy 'file-size' }
        ,([IO.File]::ReadAllBytes($FullPath))
    }
    catch [IO.InvalidDataException] { throw }
    catch { Stop-BenchmarkStudy 'file-access' }
}

function Get-StudyReduction {
    param([AllowEmptyCollection()][object[]]$Values)
    $Missing = @($Values | Where-Object { $null -eq $_ }).Count
    $Result = [ordered]@{
        sampleCount = $Values.Count; missingCount = $Missing
        sum = $null; mean = $null; median = $null; reason = $null
    }
    if ($Values.Count -eq 0) { $Result.reason = 'no-recorded-observations'; return $Result }
    if ($Missing) { $Result.reason = 'missing-component-metric'; return $Result }
    [decimal]$Sum = 0
    foreach ($Value in $Values) { $Sum += [decimal]$Value }
    $Sorted = @($Values | Sort-Object { [decimal]$_ })
    $Middle = [int][Math]::Floor($Values.Count / 2)
    $Result.sum = $Sum
    $Result.mean = $Sum / $Values.Count
    $Result.median = if ($Values.Count % 2) { [decimal]$Sorted[$Middle] } else { ([decimal]$Sorted[$Middle - 1] + [decimal]$Sorted[$Middle]) / 2 }
    $Result
}

function Get-StudyRatio {
    param($Numerator, [int]$Denominator, [string]$ZeroReason, [string]$Label, [string]$UnavailableReason)
    $Reason = if ($Denominator -eq 0) { $ZeroReason } elseif ($null -eq $Numerator) { $UnavailableReason } else { $null }
    @{
        numerator = $Numerator; denominator = $Denominator; label = $Label; reason = $Reason
        value = if ($null -eq $Reason) { [decimal]$Numerator / $Denominator } else { $null }
    }
}

function Get-StudyArmAnalysis {
    param([object[]]$Slots, [object[]]$Trials, [object[]]$Batches, [string]$Arm)
    $Recorded = $Trials.Count
    $Planned = @($Slots | Where-Object { $_.state -ceq 'planned' }).Count
    $Aborted = @($Slots | Where-Object { $_.state -ceq 'aborted' }).Count
    $Accepted = @($Trials | Where-Object { $_.outcomes.completed }).Count
    $Functional = @($Trials | Where-Object { $_.outcomes.functional }).Count
    $Resources = [ordered]@{}
    foreach ($Part in @('workflow', 'judge', 'total')) {
        $Resources[$Part] = [ordered]@{}
        foreach ($Field in $script:StudyResources) {
            $Values = @(
                foreach ($Trial in $Trials) {
                    if ($Part -ceq 'total') {
                        if ($null -eq $Trial.workflow[$Field] -or $null -eq $Trial.judge[$Field]) { $null }
                        else { [decimal]$Trial.workflow[$Field] + [decimal]$Trial.judge[$Field] }
                    }
                    else { $Trial[$Part][$Field] }
                }
            )
            $Resources[$Part][$Field] = Get-StudyReduction $Values
        }
    }
    $Quality = [ordered]@{}
    foreach ($Dimension in ($script:StudyDimensions + @('total'))) {
        $Values = @(
            foreach ($Trial in $Trials) {
                if ($Dimension -ceq 'total') { ($Trial.quality.Values | Measure-Object -Sum).Sum }
                else { $Trial.quality[$Dimension] }
            }
        )
        $Quality[$Dimension] = Get-StudyReduction $Values
    }
    $Consumption = [ordered]@{}
    foreach ($Field in $script:StudyResources) {
        $ZeroReason = if ($Recorded) { 'no-accepted-workflows' } else { 'no-recorded-observations' }
        $Consumption[$Field] = Get-StudyRatio -Numerator $Resources.total[$Field].sum -Denominator $Accepted -ZeroReason $ZeroReason -Label 'conditional-on-exported-evidence' -UnavailableReason $Resources.total[$Field].reason
    }
    $Bindings = @(
        foreach ($Batch in $Batches) {
            @{
                batchId = $Batch.batch.batchId; recordSha256 = $Batch.batch.recordSha256
                measuredRevision = $Batch.record.measuredRevision; sourceHash = $Batch.record.sourceHash
                protocolFingerprint = $Batch.fingerprint
            }
        }
    )
    $AttemptReason = if ($Aborted) { 'interrupted-outcomes-and-resources-unknown' } elseif (-not $Recorded) { 'no-attempted-slots' } else { $null }
    @{
        arm = $Arm; state = if ($Recorded) { 'recorded-evidence-present' } else { 'no-recorded-evidence' }
        counts = @{ recorded = $Recorded; planned = $Planned; aborted = $Aborted; declared = $Slots.Count; accepted = $Accepted; functionalPassed = $Functional }
        bindings = $Bindings
        resources = $Resources; documentQuality = $Quality
        portableEvidenceCoverage = Get-StudyRatio -Numerator $Recorded -Denominator ($Recorded + $Aborted) -ZeroReason 'no-attempted-slots' -Label 'operator-declared-attempt-ledger'
        recordedWorkflowAcceptance = Get-StudyRatio -Numerator $Accepted -Denominator $Recorded -ZeroReason 'no-recorded-observations' -Label 'conditional-on-exported-evidence'
        recordedConsumptionPerAcceptedWorkflow = $Consumption
        attemptedRunReliability = @{
            value = if ($null -eq $AttemptReason) { [decimal]$Accepted / $Recorded } else { $null }
            reason = $AttemptReason; label = 'operator-declared-attempt-ledger'
        }
        completeAttemptConsumption = @{
            resources = if ($null -eq $AttemptReason) { $Resources.total } else { $null }
            reason = $AttemptReason
        }
    }
}

function Get-StudyAnnotations {
    param([string]$AnnotationPath, $TrialIndex)
    $Result = @{
        calibrationState = 'unassessed'; annotationCount = 0; ratedTrialCount = 0
        recordedTrialCount = $TrialIndex.Count; groups = @(); bindings = @()
        attestationStatus = 'unavailable'; expertApproval = 'not-established'
    }
    $Groups = [ordered]@{}
    foreach ($Entry in $TrialIndex.Values) {
        $GroupKey = $Entry.batch.stratumId + ':' + $Entry.batch.arm
        if (-not $Groups.Contains($GroupKey)) {
            $Differences = @{}
            foreach ($Dimension in $script:StudyDimensions) { $Differences[$Dimension] = [Collections.Generic.List[decimal]]::new() }
            $Groups[$GroupKey] = @{
                stratumId = $Entry.batch.stratumId; arm = $Entry.batch.arm
                differences = $Differences
            }
        }
    }
    if ($AnnotationPath) {
        $Envelope = ConvertFrom-BenchmarkJson (Read-StudyFile $AnnotationPath)
        Assert-StudyKeys $Envelope @('schemaVersion', 'annotations')
        if ($Envelope.schemaVersion -cne 'benchmark-human-annotations-v1' -or $Envelope.annotations -isnot [array]) { Stop-BenchmarkStudy 'annotation-schema' }
        $AnnotationIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $Pairs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $Rated = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($Annotation in $Envelope.annotations) {
            Assert-StudyKeys $Annotation @('annotationId', 'binding', 'attestation', 'ratings')
            Assert-StudyId $Annotation.annotationId
            if (-not $AnnotationIds.Add($Annotation.annotationId)) { Stop-BenchmarkStudy 'annotation-id' }
            Assert-StudyKeys $Annotation.binding @('recordSha256', 'measuredRevision', 'sourceHash', 'runId', 'documents', 'rubric', 'judgeImplementationHash', 'recordedModel', 'recordedModelHash')
            $Binding = $Annotation.binding
            if ($Binding.runId -isnot [string] -or -not $TrialIndex.ContainsKey($Binding.runId)) { Stop-BenchmarkStudy 'annotation-run' }
            $Entry = $TrialIndex[$Binding.runId]
            $Group = $Groups[$Entry.batch.stratumId + ':' + $Entry.batch.arm]
            $Expected = @{
                recordSha256 = $Entry.batch.recordSha256; measuredRevision = $Entry.record.measuredRevision
                sourceHash = $Entry.record.sourceHash; runId = $Entry.trial.runId; documents = $Entry.trial.documents
                rubric = $Entry.record.protocol.rubric; judgeImplementationHash = $Entry.record.protocol.parserHash
                recordedModel = $Entry.record.protocol.model; recordedModelHash = $null
            }
            if ((ConvertTo-BenchmarkCanonicalJson $Binding) -cne (ConvertTo-BenchmarkCanonicalJson $Expected)) { Stop-BenchmarkStudy 'annotation-binding' }
            Assert-StudyKeys $Annotation.attestation @('annotatorId', 'attestationRef', 'status')
            Assert-StudyId $Annotation.attestation.annotatorId
            Assert-StudyId $Annotation.attestation.attestationRef
            if ($Annotation.attestation.status -cne 'externally-attested-human') { Stop-BenchmarkStudy 'annotation-attestation' }
            if (-not $Pairs.Add($Annotation.attestation.annotatorId + ':' + $Binding.runId)) { Stop-BenchmarkStudy 'annotation-pair' }
            Assert-StudyKeys $Annotation.ratings $script:StudyDimensions
            foreach ($Dimension in $script:StudyDimensions) {
                $Rating = $Annotation.ratings[$Dimension]
                if ($null -eq $Rating -or $Rating -isnot [ValueType] -or $Rating -is [bool] -or [double]::IsNaN([double]$Rating) -or [double]::IsInfinity([double]$Rating) -or $Rating -lt 0 -or $Rating -gt 20 -or [decimal]$Rating -ne [decimal]::Truncate([decimal]$Rating)) { Stop-BenchmarkStudy 'annotation-rating' }
                $Group.differences[$Dimension].Add([Math]::Abs([decimal]$Rating - [decimal]$Entry.trial.quality[$Dimension]))
            }
            [void]$Rated.Add($Binding.runId)
            $Result.bindings += $Expected
        }
        $Result.annotationCount = $Envelope.annotations.Count
        $Result.ratedTrialCount = $Rated.Count
        if ($Result.annotationCount) { $Result.calibrationState = 'external-ratings-present'; $Result.attestationStatus = 'externally-supplied-unauthenticated' }
    }
    foreach ($Key in @($Groups.Keys | Sort-Object -CaseSensitive)) {
        $Group = $Groups[$Key]
        $Dimensions = [ordered]@{}
        foreach ($Dimension in $script:StudyDimensions) {
            $Reduction = Get-StudyReduction @($Group.differences[$Dimension])
            $Dimensions[$Dimension] = @{
                ratingPairCount = $Reduction.sampleCount
                disagreementCount = @($Group.differences[$Dimension] | Where-Object { $_ -ne 0 }).Count
                meanAbsoluteDifference = $Reduction.mean
                reason = if ($Reduction.sampleCount) { $null } else { 'no-external-ratings' }
            }
        }
        $Result.groups += @{ stratumId = $Group.stratumId; arm = $Group.arm; dimensions = $Dimensions }
    }
    $Result.coverage = Get-StudyRatio -Numerator $Result.ratedTrialCount -Denominator $TrialIndex.Count -ZeroReason 'no-recorded-observations' -Label 'rated-recorded-trials'
    $Result
}

function Get-BenchmarkStudyAnalysis {
    <#
    .SYNOPSIS
    Describes a bounded, operator-declared offline study using historical v1 evidence.
    .DESCRIPTION
    Reads local manifests and optional external rating bindings without executing their
    contents. Metrics remain separated by stratum and arm; execution and human
    expertise are not authenticated. Returns an object suitable for ConvertTo-Json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$ManifestPath,
        [string]$AnnotationPath
    )
    $Repository = [IO.Path]::GetFullPath($Repository)
    $Manifest = ConvertFrom-BenchmarkJson (Read-StudyFile $ManifestPath)
    Assert-StudyKeys $Manifest @('schemaVersion', 'studyId', 'strata', 'batches', 'slots')
    if ($Manifest.schemaVersion -cne 'benchmark-study-v1') { Stop-BenchmarkStudy 'schema' }
    Assert-StudyId $Manifest.studyId
    foreach ($Collection in @('strata', 'batches', 'slots')) {
        if ($Manifest[$Collection] -isnot [array]) { Stop-BenchmarkStudy 'array' }
    }
    if ($Manifest.strata.Count -eq 0 -or $Manifest.slots.Count -eq 0) { Stop-BenchmarkStudy 'empty-plan' }
    $Strata = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($Stratum in $Manifest.strata) {
        Assert-StudyKeys $Stratum @('stratumId', 'taskId', 'taskRole', 'design', 'protocolFingerprint')
        Assert-StudyId $Stratum.stratumId; Assert-StudyId $Stratum.taskId
        Assert-StudyHash $Stratum.protocolFingerprint
        if ($Stratum.taskRole -cnotin @('development', 'held-out') -or $Stratum.design -cnotin @('descriptive', 'aa', 'ab') -or $Strata.ContainsKey($Stratum.stratumId)) { Stop-BenchmarkStudy 'stratum' }
        $Strata.Add($Stratum.stratumId, $Stratum)
    }
    $Batches = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $TrialIndex = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $Paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($Batch in $Manifest.batches) {
        Assert-StudyKeys $Batch @('batchId', 'stratumId', 'arm', 'recordPath', 'recordSha256')
        foreach ($Key in @('batchId', 'stratumId', 'arm')) { Assert-StudyId $Batch[$Key] }
        Assert-StudyHash $Batch.recordSha256
        if (-not $Strata.ContainsKey($Batch.stratumId) -or $Batches.ContainsKey($Batch.batchId)) { Stop-BenchmarkStudy 'batch' }
        if ($Batch.recordPath -isnot [string] -or $Batch.recordPath.Length -gt 512 -or $Batch.recordPath -cnotmatch '^benchmarks/efficiency/records/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.json$' -or -not $Paths.Add($Batch.recordPath)) { Stop-BenchmarkStudy 'record-path' }
        $Bytes = Read-StudyFile (Join-Path $Repository $Batch.recordPath)
        if ((Get-BenchmarkDigest $Bytes) -cne $Batch.recordSha256) { Stop-BenchmarkStudy 'record-digest' }
        $Record = ConvertFrom-BenchmarkJson $Bytes
        Assert-BenchmarkHistoricalSeries -Repository $Repository -Record $Record
        $Fingerprint = Get-BenchmarkDigest ([Text.Encoding]::UTF8.GetBytes((ConvertTo-BenchmarkCanonicalJson $Record.protocol)))
        if ($Fingerprint -cne $Strata[$Batch.stratumId].protocolFingerprint) { Stop-BenchmarkStudy 'protocol-fingerprint' }
        $Entry = @{ batch = $Batch; record = $Record; fingerprint = $Fingerprint }
        $Batches.Add($Batch.batchId, $Entry)
        foreach ($Trial in $Record.trials) {
            if ($TrialIndex.ContainsKey($Trial.runId)) { Stop-BenchmarkStudy 'uuid-reuse' }
            $TrialIndex.Add($Trial.runId, @{ batch = $Batch; record = $Record; trial = $Trial })
        }
    }
    $SlotIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $RecordedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($Slot in $Manifest.slots) {
        if ($Slot -isnot [Collections.IDictionary] -or -not $Slot.Contains('state') -or $Slot.state -isnot [string]) { Stop-BenchmarkStudy 'slot-shape' }
        $Keys = @('slotId', 'stratumId', 'arm', 'state')
        switch -CaseSensitive ($Slot.state) {
            'recorded' { $Keys += @('batchId', 'runId') }
            'planned' { }
            'aborted' { $Keys += 'reason' }
            default { Stop-BenchmarkStudy 'slot-state' }
        }
        Assert-StudyKeys $Slot $Keys
        foreach ($Key in @('slotId', 'stratumId', 'arm')) { Assert-StudyId $Slot[$Key] }
        if (-not $Strata.ContainsKey($Slot.stratumId) -or -not $SlotIds.Add($Slot.slotId)) { Stop-BenchmarkStudy 'slot-id' }
        if ($Slot.state -ceq 'aborted' -and ($Slot.reason -isnot [string] -or [string]::IsNullOrWhiteSpace($Slot.reason) -or $Slot.reason.Length -gt 256 -or $Slot.reason -match '[\x00-\x1f]')) { Stop-BenchmarkStudy 'abort-reason' }
        if ($Slot.state -ceq 'recorded') {
            Assert-StudyId $Slot.batchId
            if ($Slot.runId -isnot [string] -or -not $TrialIndex.ContainsKey($Slot.runId) -or -not $Batches.ContainsKey($Slot.batchId) -or -not $RecordedIds.Add($Slot.runId)) { Stop-BenchmarkStudy 'trial-roster' }
            $Batch = $TrialIndex[$Slot.runId].batch
            if ($Batch.batchId -cne $Slot.batchId -or $Batch.stratumId -cne $Slot.stratumId -or $Batch.arm -cne $Slot.arm) { Stop-BenchmarkStudy 'slot-binding' }
        }
    }
    if ($RecordedIds.Count -ne $TrialIndex.Count) { Stop-BenchmarkStudy 'incomplete-roster' }
    $OutputStrata = @(
        foreach ($Stratum in $Manifest.strata) {
            $Slots = @($Manifest.slots | Where-Object { $_.stratumId -ceq $Stratum.stratumId })
            if (-not $Slots.Count) { Stop-BenchmarkStudy 'empty-stratum' }
            $Included = @($Batches.Values | Where-Object { $_.batch.stratumId -ceq $Stratum.stratumId } | Sort-Object { $_.batch.batchId } -CaseSensitive)
            $RecordedArms = @($Included | ForEach-Object { $_.batch.arm } | Sort-Object -Unique -CaseSensitive)
            if ($Included.Count -and $Stratum.design -cin @('aa', 'ab') -and $RecordedArms.Count -lt 2) { Stop-BenchmarkStudy 'design-recorded-arms' }
            if ($Stratum.design -ceq 'aa' -and @($Included | ForEach-Object { $_.record.sourceHash } | Sort-Object -Unique -CaseSensitive).Count -gt 1) { Stop-BenchmarkStudy 'aa-source' }
            $Arms = @(
                foreach ($Arm in @($Slots.arm | Sort-Object -Unique -CaseSensitive)) {
                    $ArmBatches = @($Included | Where-Object { $_.batch.arm -ceq $Arm })
                    if ($Stratum.design -ceq 'ab' -and @($ArmBatches | ForEach-Object { $_.record.sourceHash } | Sort-Object -Unique -CaseSensitive).Count -gt 1) { Stop-BenchmarkStudy 'ab-source' }
                    $Trials = @($ArmBatches | ForEach-Object { $_.record.trials } | Sort-Object runId -CaseSensitive)
                    Get-StudyArmAnalysis -Slots @($Slots | Where-Object { $_.arm -ceq $Arm }) -Trials $Trials -Batches $ArmBatches -Arm $Arm
                }
            )
            @{
                stratumId = $Stratum.stratumId; taskId = $Stratum.taskId; taskRole = $Stratum.taskRole
                design = $Stratum.design; protocolFingerprint = $Stratum.protocolFingerprint
                metadataBasis = 'manifest-declared'; arms = $Arms
            }
        }
    )
    @{
        schemaVersion = 'benchmark-study-analysis-v1'; studyId = $Manifest.studyId
        state = if ($RecordedIds.Count) { 'recorded-evidence-present' } else { 'no-recorded-evidence' }
        executionAttestation = 'unavailable'; strata = $OutputStrata
        calibration = Get-StudyAnnotations $AnnotationPath $TrialIndex
        limitations = @(
            'Historical consistency does not authenticate execution or annotators.'
            'The operator-declared ledger cannot prove omitted attempts or independent/randomized execution.'
            'Per-stratum and per-arm descriptions are not significance, causality, expert calibration, or release approval.'
            'Interrupted outcomes and resources remain unknown; recorded-only ratios are not expected retry costs.'
        )
    }
}

Export-ModuleMember -Function Get-BenchmarkStudyAnalysis
