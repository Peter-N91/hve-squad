#Requires -Version 7.5
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Dimensions = @('businessClarity', 'scopeFidelity', 'acceptanceCriteria', 'traceability', 'risksAndDecisions')
$script:Resources = @('credits', 'requests', 'inputTokens', 'outputTokens', 'toolCalls', 'failedTools', 'measuredProcessWallSeconds', 'cacheReadTokens', 'cacheWriteTokens', 'eventElapsedMs')
$script:Efficiency = @('credits', 'requests', 'inputTokens', 'outputTokens', 'toolCalls', 'measuredProcessWallSeconds')
$script:ProtocolPaths = [ordered]@{
    scenarioHash = 'tests/tier2/live-benchmark/efficiency-scenario.json'
    parserHash = 'tests/tier2/live-benchmark/EfficiencyBenchmark.psm1'
    exerciseHash = 'tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1'
    preparationHash = 'tests/lib/SquadInstall.psm1'
    graderHash = 'tests/tier2/live-benchmark/Test-EfficiencyTask.ps1'
    verifierHash = 'scripts/Test-SquadScribeOutput.ps1'
}
$script:ProtocolLabels = @('schema', 'rubric', 'hostProfile', 'model', 'cliVersion', 'powershell', 'recoveryPolicy', 'evaluationPolicy')
$script:ProtocolDigests = @('installHash', 'roleModelPolicyHash', 'disabledMcpServersHash') + @($script:ProtocolPaths.Keys)
$script:FunctionalNames = @('empty-list', 'add-unicode', 'unique-increasing-id', 'persistent-ordered-list', 'done-idempotent', 'status-filter', 'missing-title', 'blank-title', 'unknown-id', 'invalid-action', 'invalid-filter', 'corrupt-store-preserved', 'id-boundary-preserves-store')
$script:CommonChecks = @('team.md', 'routing.md', 'state.json', 'decisions.md', 'consumption.md', 'consumption-rates.md', 'dispatchEvidence', 'stateVerifier')
$script:StageChecks = @{
    init = $script:CommonChecks + @('scribeHistory')
    requirements = $script:CommonChecks + @('scribeHistory', 'brd.md', 'prd.md', 'BRD Builder', 'PRD Builder', 'BRD Quality Reviewer', 'PRD Quality Reviewer', 'tester', 'reviewOutcome')
    build = $script:CommonChecks + @('researcher', 'lead', 'developer', 'tester', 'reviewOutcome')
}

function Stop-BenchmarkData {
    param([string]$Reason, [string]$Status = 'invalid-record')
    throw [IO.InvalidDataException]::new("$Status`:$Reason")
}

function Get-BenchmarkDigest {
    param([byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function ConvertTo-BenchmarkCanonicalJson {
    param([Parameter(Mandatory)]$Value)
    function Convert-Node($Node) {
        if ($Node -is [Collections.IDictionary]) {
            $Result = [ordered]@{}
            foreach ($Key in @($Node.Keys | Sort-Object -CaseSensitive)) { $Result[$Key] = Convert-Node $Node[$Key] }
            return $Result
        }
        if ($Node -is [array]) { return ,@($Node | ForEach-Object { Convert-Node $_ }) }
        return $Node
    }
    (Convert-Node $Value | ConvertTo-Json -Depth 32 -Compress) + "`n"
}

function ConvertFrom-BenchmarkJson {
    param([byte[]]$Bytes, [int]$MaximumBytes = 262144)
    if ($Bytes.Length -eq 0 -or $Bytes.Length -gt $MaximumBytes) { Stop-BenchmarkData 'json-size' }
    try {
        $Text = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
        $Document = [Text.Json.JsonDocument]::Parse($Text, [Text.Json.JsonDocumentOptions]@{ MaxDepth = 32 })
        try {
            function Assert-JsonKeys($Node) {
                if ($Node.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
                    $Seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                    foreach ($Property in $Node.EnumerateObject()) {
                        if (-not $Seen.Add($Property.Name)) { Stop-BenchmarkData 'duplicate-json-key' }
                        Assert-JsonKeys $Property.Value
                    }
                }
                elseif ($Node.ValueKind -eq [Text.Json.JsonValueKind]::Array) { foreach ($Child in $Node.EnumerateArray()) { Assert-JsonKeys $Child } }
            }
            Assert-JsonKeys $Document.RootElement
        }
        finally { $Document.Dispose() }
        $Result = ConvertFrom-Json -InputObject $Text -AsHashtable -Depth 32 -DateKind String
        if ($Result -isnot [Collections.IDictionary]) { Stop-BenchmarkData 'json-root-object' }
        $Result
    }
    catch [IO.InvalidDataException] { throw }
    catch { Stop-BenchmarkData 'json-syntax' }
}

function Assert-BenchmarkKeys {
    param($Value, [string[]]$Keys)
    if ($Value -isnot [Collections.IDictionary] -or $Value.Count -ne $Keys.Count) { Stop-BenchmarkData 'object-shape' }
    foreach ($Key in $Keys) { if (-not $Value.Contains($Key)) { Stop-BenchmarkData 'object-key' } }
}

function Assert-BenchmarkNumber {
    param($Value, [switch]$Integer, [decimal]$Maximum = 1000000000000000)
    if ($null -eq $Value -or $Value -isnot [ValueType] -or $Value -is [bool] -or [double]::IsNaN([double]$Value) -or [double]::IsInfinity([double]$Value) -or $Value -lt 0 -or $Value -gt $Maximum -or ($Integer -and [decimal]$Value -ne [decimal]::Truncate([decimal]$Value))) {
        Stop-BenchmarkData 'numeric-field'
    }
}

function Assert-BenchmarkHash {
    param($Value, [int]$Length = 64)
    if ($Value -isnot [string] -or $Value -cnotmatch "^[0-9a-f]{$Length}$") { Stop-BenchmarkData 'digest-field' }
}

function Assert-BenchmarkBooleans {
    param($Value, [string[]]$Keys)
    Assert-BenchmarkKeys $Value $Keys
    foreach ($Key in $Keys) { if ($Value[$Key] -isnot [bool]) { Stop-BenchmarkData 'boolean-field' } }
}

function Invoke-BenchmarkGit {
    param([string]$Repository, [string[]]$Arguments, [int]$MaximumBytes = 8388608, [switch]$AllowFailure)
    $Info = [Diagnostics.ProcessStartInfo]::new('git')
    $Info.WorkingDirectory = [IO.Path]::GetFullPath($Repository)
    $Info.UseShellExecute = $false; $Info.RedirectStandardOutput = $true; $Info.RedirectStandardError = $true
    foreach ($Argument in (@('--no-pager', '-c', 'core.hooksPath=/dev/null') + $Arguments)) { $Info.ArgumentList.Add($Argument) }
    $Process = [Diagnostics.Process]::new(); $Process.StartInfo = $Info
    $Buffer = [byte[]]::new(8192); $Output = [IO.MemoryStream]::new()
    try {
        [void]$Process.Start()
        $ErrorRead = $Process.StandardError.ReadToEndAsync()
        while (($Count = $Process.StandardOutput.BaseStream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
            if ($Output.Length + $Count -gt $MaximumBytes) { $Process.Kill($true); Stop-BenchmarkData 'git-object-size' }
            $Output.Write($Buffer, 0, $Count)
        }
        $Process.WaitForExit(); [void]$ErrorRead.GetAwaiter().GetResult()
        if ($Process.ExitCode -ne 0) {
            if ($AllowFailure) { return $null }
            Stop-BenchmarkData 'git-operation' 'operational-error'
        }
        return ,$Output.ToArray()
    }
    finally { $Output.Dispose(); $Process.Dispose() }
}

function Resolve-BenchmarkCommit {
    param([string]$Repository, [string]$Ref)
    if ([string]::IsNullOrWhiteSpace($Ref) -or $Ref.Length -gt 256 -or $Ref -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$' -or $Ref.Contains('..')) { Stop-BenchmarkData 'unsafe-ref' }
    $Bytes = Invoke-BenchmarkGit $Repository @('rev-parse', '--verify', '--end-of-options', "$Ref^{commit}")
    $Oid = [Text.Encoding]::UTF8.GetString($Bytes).Trim()
    Assert-BenchmarkHash $Oid 40
    $Oid
}

function Get-BenchmarkGitFile {
    param([string]$Repository, [string]$Commit, [string]$Path, [int]$MaximumBytes = 262144, [switch]$Optional)
    Assert-BenchmarkHash $Commit 40
    if ($Path -notmatch '^[A-Za-z0-9._/-]+$' -or $Path.Contains('..') -or $Path.StartsWith('/')) { Stop-BenchmarkData 'unsafe-git-path' }
    $Entry = [Text.Encoding]::UTF8.GetString((Invoke-BenchmarkGit $Repository @('ls-tree', $Commit, '--', $Path))).TrimEnd("`n")
    if (-not $Entry) {
        if ($Optional) { return $null }
        Stop-BenchmarkData 'missing-git-file'
    }
    if ($Entry -notmatch '^100(644|755) blob ([0-9a-f]{40})\t' -or $Entry.Contains("`n")) { Stop-BenchmarkData 'nonregular-git-file' }
    Invoke-BenchmarkGit $Repository @('cat-file', 'blob', $Matches[2]) $MaximumBytes
}

function Get-BenchmarkSourceHash {
    param([string]$Repository, [string]$Commit)
    $Listing = [Text.Encoding]::UTF8.GetString((Invoke-BenchmarkGit $Repository @('ls-tree', '-r', '-z', $Commit, '--', 'squad-src')))
    $Entries = @(foreach ($Line in $Listing.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) {
        if ($Line -notmatch '^100(644|755) blob ([0-9a-f]{40})\t(squad-src/[A-Za-z0-9._/-]+)$') { Stop-BenchmarkData 'unsupported-source-tree' }
        $Oid = $Matches[2]; $Path = $Matches[3].Substring('squad-src/'.Length)
        $Digest = Get-BenchmarkDigest (Invoke-BenchmarkGit $Repository @('cat-file', 'blob', $Oid))
        $Path + ':' + $Digest.ToUpperInvariant()
    })
    if ($Entries.Count -eq 0) { Stop-BenchmarkData 'empty-source-tree' }
    Get-BenchmarkDigest ([Text.Encoding]::UTF8.GetBytes((($Entries | Sort-Object) -join "`n")))
}

function Get-BenchmarkProtocol {
    param([string]$Repository, [string]$Revision, [Collections.IDictionary]$Compatibility)
    $Protocol = [ordered]@{}
    foreach ($Key in @('schema', 'rubric', 'hostProfile', 'model', 'powershell', 'recoveryPolicy', 'evaluationPolicy', 'maxCredits', 'continuations')) { $Protocol[$Key] = $Compatibility[$Key] }
    if ($Compatibility.cli -notmatch '^GitHub Copilot CLI ([0-9A-Za-z.+-]+)(?:\. |$)') { Stop-BenchmarkData 'cli-version' }
    $Protocol.cliVersion = $Matches[1]
    $Protocol.installHash = ([string]$Compatibility.installHash).ToLowerInvariant()
    foreach ($Key in @('roleModelPolicy', 'disabledMcpServers')) { $Protocol[$Key + 'Hash'] = Get-BenchmarkDigest ([Text.Encoding]::UTF8.GetBytes([string]$Compatibility[$Key])) }
    foreach ($Key in $script:ProtocolPaths.Keys) {
        $Hash = Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Revision $script:ProtocolPaths[$Key] 8388608)
        if ($Key -ne 'verifierHash' -and $Hash -cne ([string]$Compatibility[$Key]).ToLowerInvariant()) { Stop-BenchmarkData 'measured-protocol-mismatch' }
        $Protocol[$Key] = $Hash
    }
    $Protocol
}

function Get-BenchmarkRawMetrics {
    param([Collections.IDictionary]$Metrics, [decimal]$WallSeconds)
    if ($Metrics.complete -cne $true -or $Metrics.credits.complete -cne $true) { Stop-BenchmarkData 'incomplete-metering' }
    foreach ($Field in @('inputTokens', 'outputTokens')) {
        if ($null -eq $Metrics.totals[$Field] -or $Metrics.counts.usage -le 0 -or $Metrics.coverage[$Field] -ne $Metrics.counts.usage) { Stop-BenchmarkData 'token-coverage' }
    }
    $Result = [ordered]@{
        credits = $Metrics.credits.used; requests = $Metrics.modelRequests
        inputTokens = $Metrics.totals.inputTokens; outputTokens = $Metrics.totals.outputTokens
        toolCalls = $Metrics.toolCalls; failedTools = $Metrics.counts.failures
        measuredProcessWallSeconds = $WallSeconds
        cacheReadTokens = $null; cacheWriteTokens = $null; eventElapsedMs = $Metrics.elapsedMs
    }
    foreach ($Field in @('cacheReadTokens', 'cacheWriteTokens')) {
        if ($Metrics.coverage[$Field] -eq $Metrics.counts.usage) { $Result[$Field] = $Metrics.totals[$Field] }
    }
    $Result
}

function Assert-BenchmarkSeries {
    param([Collections.IDictionary]$Record)
    Assert-BenchmarkKeys $Record @('schemaVersion', 'seriesId', 'measuredRevision', 'sourceHash', 'protocol', 'provenance', 'trials')
    if ($Record.schemaVersion -cne 'benchmark-series-v1' -or $Record.seriesId -cnotmatch '^[a-z0-9][a-z0-9-]{0,95}$') { Stop-BenchmarkData 'series-identity' }
    Assert-BenchmarkHash $Record.measuredRevision 40
    Assert-BenchmarkHash $Record.sourceHash
    Assert-BenchmarkKeys $Record.protocol ($script:ProtocolLabels + $script:ProtocolDigests + @('maxCredits', 'continuations'))
    foreach ($Key in $script:ProtocolLabels) { if ($Record.protocol[$Key] -isnot [string] -or $Record.protocol[$Key] -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.+-]{0,95}$') { Stop-BenchmarkData 'protocol-label' } }
    foreach ($Key in $script:ProtocolDigests) { Assert-BenchmarkHash $Record.protocol[$Key] }
    Assert-BenchmarkNumber $Record.protocol.maxCredits
    Assert-BenchmarkNumber $Record.protocol.continuations -Integer
    if ($Record.protocol.evaluationPolicy -cne 'baseline-observation-v1') { Stop-BenchmarkData 'evaluation-policy' }
    Assert-BenchmarkKeys $Record.provenance @('collector', 'verifierHashBasis', 'hostAttestation', 'rawSeriesHash')
    if ($Record.provenance.collector -cne 'benchmark-export-v1' -or $Record.provenance.verifierHashBasis -cne 'measured-git-revision' -or $Record.provenance.hostAttestation -cne 'unavailable') { Stop-BenchmarkData 'provenance-label' }
    Assert-BenchmarkHash $Record.provenance.rawSeriesHash
    if ($Record.trials -isnot [array] -or $Record.trials.Count -ne 3) { Stop-BenchmarkData 'trial-count' }
    $Ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($Trial in $Record.trials) {
        Assert-BenchmarkKeys $Trial @('runId', 'slot', 'started', 'workflow', 'judge', 'quality', 'criticalHighFindings', 'documents', 'evidence', 'outcomes', 'processes', 'reviewerDispatch')
        $Guid = [guid]::Empty
        if ($Trial.runId -isnot [string] -or -not [guid]::TryParseExact($Trial.runId, 'D', [ref]$Guid) -or -not $Ids.Add($Trial.runId)) { Stop-BenchmarkData 'trial-id' }
        Assert-BenchmarkNumber $Trial.slot -Integer -Maximum 3
        if ($Trial.slot -lt 1 -or $Trial.started -cnotmatch '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,7})?Z$') { Stop-BenchmarkData 'trial-time-slot' }
        foreach ($Part in @('workflow', 'judge')) {
            Assert-BenchmarkKeys $Trial[$Part] $script:Resources
            foreach ($Key in $script:Resources) {
                if ($Key -in @('cacheReadTokens', 'cacheWriteTokens', 'eventElapsedMs') -and $null -eq $Trial[$Part][$Key]) { continue }
                Assert-BenchmarkNumber $Trial[$Part][$Key] -Integer:($Key -notin @('credits', 'measuredProcessWallSeconds', 'eventElapsedMs'))
            }
        }
        if ($Trial.judge.toolCalls -ne 0) { Stop-BenchmarkData 'judge-tool-use' }
        Assert-BenchmarkKeys $Trial.quality $script:Dimensions
        foreach ($Dimension in $script:Dimensions) { Assert-BenchmarkNumber $Trial.quality[$Dimension] -Integer -Maximum 20 }
        Assert-BenchmarkNumber $Trial.criticalHighFindings -Integer
        Assert-BenchmarkKeys $Trial.documents @('brd', 'prd', 'closingReview')
        foreach ($Hash in $Trial.documents.Values) { Assert-BenchmarkHash $Hash }
        Assert-BenchmarkKeys $Trial.evidence @('runHash', 'workflowEventsHash', 'judgeEventsHash')
        foreach ($Hash in $Trial.evidence.Values) { Assert-BenchmarkHash $Hash }
        $OutcomeKeys = @('functional', 'workflow', 'completed') + @($script:FunctionalNames | ForEach-Object { "functional/$_" }) + @($script:StageChecks.build | ForEach-Object { "workflow/$_" })
        foreach ($Stage in @('init', 'requirements', 'build')) { $OutcomeKeys += "stage/$Stage"; $OutcomeKeys += @($script:StageChecks[$Stage] | ForEach-Object { "$Stage/$_" }) }
        Assert-BenchmarkBooleans $Trial.outcomes $OutcomeKeys
        if ($Trial.outcomes.functional -ne (@($script:FunctionalNames | Where-Object { -not $Trial.outcomes["functional/$_"] }).Count -eq 0)) { Stop-BenchmarkData 'functional-consistency' }
        if ($Trial.outcomes.workflow -ne (@($script:StageChecks.build | Where-Object { -not $Trial.outcomes["workflow/$_"] }).Count -eq 0)) { Stop-BenchmarkData 'workflow-consistency' }
        $ExpectedCompletion = $Trial.outcomes.functional -and $Trial.outcomes.workflow
        Assert-BenchmarkKeys $Trial.processes @('init', 'requirements', 'build', 'judge')
        foreach ($Stage in @('init', 'requirements', 'build', 'judge')) {
            Assert-BenchmarkKeys $Trial.processes[$Stage] @('exitCode', 'stopCause')
            $Code = $Trial.processes[$Stage].exitCode
            if ($null -eq $Code -or $Code -isnot [ValueType] -or $Code -is [bool] -or $Code -lt -2147483648 -or $Code -gt 2147483647 -or [decimal]$Code -ne [decimal]::Truncate([decimal]$Code) -or $Trial.processes[$Stage].stopCause -cnotin @('none', 'timeout', 'request-limit', 'credit-limit', 'unexpected-question', 'stdin-timeout', 'unknown')) { Stop-BenchmarkData 'process-field' }
            if ($Stage -ne 'judge') {
                $ChecksPassed = @($script:StageChecks[$Stage] | Where-Object { -not $Trial.outcomes["$Stage/$_"] }).Count -eq 0
                if ($Trial.outcomes["stage/$Stage"] -ne ($ChecksPassed -and $Code -eq 0 -and $Trial.processes[$Stage].stopCause -eq 'none')) { Stop-BenchmarkData 'stage-consistency' }
                $ExpectedCompletion = $ExpectedCompletion -and $Trial.outcomes["stage/$Stage"]
            }
        }
        if ($Trial.processes.judge.exitCode -ne 0 -or $Trial.processes.judge.stopCause -cne 'none' -or $Trial.outcomes.completed -ne $ExpectedCompletion) { Stop-BenchmarkData 'completion-consistency' }
        Assert-BenchmarkBooleans $Trial.reviewerDispatch @('brd', 'prd')
    }
    if ((@($Record.trials.slot | Sort-Object) -join ',') -ne '1,2,3') { Stop-BenchmarkData 'trial-slots' }
}

function Assert-BenchmarkSnapshot {
    param([string]$Repository, [string]$Commit, [Collections.IDictionary]$Record)
    Assert-BenchmarkSeries $Record
    $Ancestor = Invoke-BenchmarkGit $Repository @('merge-base', '--is-ancestor', $Record.measuredRevision, $Commit) -AllowFailure
    if ($null -eq $Ancestor) { Stop-BenchmarkData 'measured-revision-not-ancestor' 'stale-record' }
    if ((Get-BenchmarkSourceHash $Repository $Commit) -cne $Record.sourceHash -or (Get-BenchmarkSourceHash $Repository $Record.measuredRevision) -cne $Record.sourceHash) { Stop-BenchmarkData 'source-fingerprint' 'stale-record' }
    foreach ($Key in $script:ProtocolPaths.Keys) {
        foreach ($Ref in @($Commit, $Record.measuredRevision) | Select-Object -Unique) {
            if ((Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Ref $script:ProtocolPaths[$Key] 8388608)) -cne $Record.protocol[$Key]) { Stop-BenchmarkData "protocol-$Key" 'stale-record' }
        }
    }
}

function Export-BenchmarkSeries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$ControlPath, [Parameter(Mandatory)][string[]]$TrialDirectories, [Parameter(Mandatory)][string]$SeriesId, [switch]$SelectCurrent)
    if ($SeriesId -cnotmatch '^[a-z0-9][a-z0-9-]{0,95}$' -or $TrialDirectories.Count -ne 3) { Stop-BenchmarkData 'export-selection' }
    $Raw = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ControlPath))
    $Controls = ConvertFrom-BenchmarkJson $Raw 33554432
    if ($Controls.schemaVersion -cne 'efficiency-control-v1' -or $Controls.runs.Count -ne 3) { Stop-BenchmarkData 'control-series-schema' }
    Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1') -Force
    $Trials = @(); $Protocol = $null; $Revision = $null; $SourceHash = $null
    foreach ($Directory in $TrialDirectories) {
        $RunBytes = [IO.File]::ReadAllBytes((Join-Path $Directory 'out/run.json'))
        $Run = ConvertFrom-BenchmarkJson $RunBytes 16777216
        $Saved = @($Controls.runs | Where-Object { $_.metadata.runId -ceq $Run.metadata.runId })
        if ($Saved.Count -ne 1 -or (ConvertTo-BenchmarkCanonicalJson $Saved[0]) -cne (ConvertTo-BenchmarkCanonicalJson $Run)) { Stop-BenchmarkData 'raw-control-conflict' }
        if (-not (Test-EfficiencyObservation $Run) -or -not $Run.judge.valid -or -not (Test-EfficiencyJudge $Run.judge.response $Run.judge.documentHashes)) { Stop-BenchmarkData 'raw-observation-or-judge' }
        $CurrentProtocol = Get-BenchmarkProtocol $Repository $Run.metadata.revision $Run.metadata.compatibility
        if ($null -eq $Protocol) { $Protocol = $CurrentProtocol; $Revision = $Run.metadata.revision; $SourceHash = $Run.metadata.sourceHash }
        if ((ConvertTo-BenchmarkCanonicalJson $CurrentProtocol) -cne (ConvertTo-BenchmarkCanonicalJson $Protocol) -or $Run.metadata.revision -cne $Revision -or $Run.metadata.sourceHash -cne $SourceHash) { Stop-BenchmarkData 'mixed-series' }
        $Workspace = [IO.Path]::GetFullPath((Join-Path $Directory 'workspace'))
        $Documents = [ordered]@{}
        foreach ($Name in @('brd', 'prd', 'closingReview')) {
            $Relative = if ($Name -eq 'closingReview') { $Run.workflow.reviewPath } else { "docs/requirements/$Name.md" }
            $Hash = Get-BenchmarkDigest ([byte[]]@())
            if ($Relative) {
                $Path = [IO.Path]::GetFullPath((Join-Path $Workspace $Relative))
                if (-not $Path.StartsWith($Workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::Ordinal)) { Stop-BenchmarkData 'document-path' }
                if (Test-Path -LiteralPath $Path -PathType Leaf) {
                    $Item = Get-Item -LiteralPath $Path
                    if ($Item.LinkType -or $Item.Length -gt 100000 -or $Item.ResolveLinkTarget($true)) { Stop-BenchmarkData 'document-file' }
                    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
                }
                elseif ($Name -ne 'closingReview') { Stop-BenchmarkData 'missing-document' }
            }
            if ($Hash -cne ([string]$Run.judge.documentHashes[$Name]).ToLowerInvariant()) { Stop-BenchmarkData 'document-digest' }
            $Documents[$Name] = $Hash
        }
        $Outcomes = [ordered]@{ functional = $Run.acceptance.passed; workflow = $Run.workflow.passed; completed = $Run.completed }
        foreach ($Check in $Run.acceptance.checks) {
            if ($Check.name -cnotin $script:FunctionalNames -or $Outcomes.Contains("functional/$($Check.name)")) { Stop-BenchmarkData 'functional-probe' }
            $Outcomes["functional/$($Check.name)"] = $Check.passed
        }
        foreach ($Key in $Run.workflow.checks.Keys) { $Outcomes["workflow/$Key"] = $Run.workflow.checks[$Key] }
        $Processes = [ordered]@{}; [decimal]$Wall = 0
        if ($Run.stages.Count -ne 3) { Stop-BenchmarkData 'stage-count' }
        foreach ($Stage in $Run.stages) {
            if ($Stage.name -cnotin @('init', 'requirements', 'build') -or $Processes.Contains($Stage.name)) { Stop-BenchmarkData 'stage-name' }
            Assert-BenchmarkNumber $Stage.process.seconds
            $Wall += [decimal]$Stage.process.seconds
            $Outcomes["stage/$($Stage.name)"] = $Stage.passed
            foreach ($Key in $Stage.readiness.checks.Keys) { $Outcomes["$($Stage.name)/$Key"] = $Stage.readiness.checks[$Key] }
            $Processes[$Stage.name] = @{ exitCode = $Stage.process.exitCode; stopCause = $Stage.process.stopCause }
        }
        Assert-BenchmarkNumber $Run.judge.process.seconds
        $Processes.judge = @{ exitCode = $Run.judge.process.exitCode; stopCause = $Run.judge.process.stopCause }
        $Trials += [ordered]@{
            runId = $Run.metadata.runId; slot = $Run.metadata.pair; started = $Run.metadata.started
            workflow = Get-BenchmarkRawMetrics $Run.metrics $Wall
            judge = Get-BenchmarkRawMetrics $Run.judge.metrics ([decimal]$Run.judge.process.seconds)
            quality = $Run.judge.response.scores; criticalHighFindings = $Run.judge.response.criticalHighFindings
            documents = $Documents
            evidence = @{ runHash = Get-BenchmarkDigest $RunBytes; workflowEventsHash = ([string]$Run.metrics.evidence.sha256).ToLowerInvariant(); judgeEventsHash = ([string]$Run.judge.metrics.evidence.sha256).ToLowerInvariant() }
            outcomes = $Outcomes; processes = $Processes
            reviewerDispatch = @{ brd = ($Run.metrics.dispatches['BRD Quality Reviewer'] -gt 0); prd = ($Run.metrics.dispatches['PRD Quality Reviewer'] -gt 0) }
        }
    }
    $Record = [ordered]@{
        schemaVersion = 'benchmark-series-v1'; seriesId = $SeriesId; measuredRevision = $Revision; sourceHash = $SourceHash
        protocol = $Protocol
        provenance = @{ collector = 'benchmark-export-v1'; verifierHashBasis = 'measured-git-revision'; hostAttestation = 'unavailable'; rawSeriesHash = Get-BenchmarkDigest $Raw }
        trials = @($Trials | Sort-Object slot)
    }
    $Head = Resolve-BenchmarkCommit $Repository 'HEAD'
    Assert-BenchmarkSnapshot $Repository $Head $Record
    $Bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-BenchmarkCanonicalJson $Record))
    if ($Bytes.Length -gt 262144) { Stop-BenchmarkData 'record-size' }
    $Root = Join-Path $Repository 'benchmarks/efficiency'
    [void][IO.Directory]::CreateDirectory((Join-Path $Root 'records'))
    $Path = Join-Path $Root "records/$SeriesId.json"
    $File = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $File.Write($Bytes) } finally { $File.Dispose() }
    if ($SelectCurrent) {
        $Pointer = @{ schemaVersion = 'benchmark-pointer-v1'; recordPath = "records/$SeriesId.json"; sha256 = Get-BenchmarkDigest $Bytes }
        Write-BenchmarkFile (Join-Path $Root 'current.json') (ConvertTo-BenchmarkCanonicalJson $Pointer)
    }
    $Record
}

function Write-BenchmarkFile {
    param([string]$Path, [string]$Text)
    $Full = [IO.Path]::GetFullPath($Path)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Full))
    $Temporary = $Full + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($Temporary, $Text, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($Temporary, $Full, $true)
    }
    finally { if ([IO.File]::Exists($Temporary)) { [IO.File]::Delete($Temporary) } }
}

function Get-BenchmarkSelection {
    param([string]$Repository, [string]$Commit, [string]$MissingStatus)
    $Bytes = Get-BenchmarkGitFile $Repository $Commit 'benchmarks/efficiency/current.json' -Optional
    if ($null -eq $Bytes) { Stop-BenchmarkData 'no-selected-record' $MissingStatus }
    $Pointer = ConvertFrom-BenchmarkJson $Bytes
    Assert-BenchmarkKeys $Pointer @('schemaVersion', 'recordPath', 'sha256')
    if ($Pointer.schemaVersion -cne 'benchmark-pointer-v1' -or $Pointer.recordPath -cnotmatch '^records/([a-z0-9][a-z0-9-]{0,95})\.json$') { Stop-BenchmarkData 'pointer-path' }
    $SeriesId = $Matches[1]
    Assert-BenchmarkHash $Pointer.sha256
    $RecordBytes = Get-BenchmarkGitFile $Repository $Commit ("benchmarks/efficiency/" + $Pointer.recordPath)
    if ((Get-BenchmarkDigest $RecordBytes) -cne $Pointer.sha256) { Stop-BenchmarkData 'pointer-digest' }
    $Record = ConvertFrom-BenchmarkJson $RecordBytes
    Assert-BenchmarkSeries $Record
    if ($Record.seriesId -cne $SeriesId) { Stop-BenchmarkData 'pointer-series' }
    Assert-BenchmarkSnapshot $Repository $Commit $Record
    @{ record = $Record; sha256 = $Pointer.sha256 }
}

function Get-BenchmarkMedian {
    param([decimal[]]$Values)
    $Sorted = @($Values | Sort-Object)
    if ($Sorted.Count -ne 3) { Stop-BenchmarkData 'median-samples' }
    $Sorted[1]
}

function Get-BenchmarkStatistics {
    param([Collections.IDictionary]$Record)
    Assert-BenchmarkSeries $Record
    $Result = [ordered]@{ resources = [ordered]@{}; quality = [ordered]@{}; outcomes = [ordered]@{}; reviewerDispatch = [ordered]@{}; criticalHighFindings = 0 }
    foreach ($Part in @('workflow', 'judge', 'total')) {
        $Result.resources[$Part] = [ordered]@{}
        foreach ($Field in $script:Resources) {
            $Values = @(foreach ($Trial in $Record.trials) {
                if ($Part -eq 'total') {
                    if ($null -eq $Trial.workflow[$Field] -or $null -eq $Trial.judge[$Field]) { $null }
                    else { [decimal]$Trial.workflow[$Field] + [decimal]$Trial.judge[$Field] }
                }
                else { $Trial[$Part][$Field] }
            })
            $Result.resources[$Part][$Field] = if (@($Values | Where-Object { $null -eq $_ }).Count -gt 0) { $null } else {
                [decimal]$Sum = 0
                foreach ($Value in $Values) { $Sum += [decimal]$Value }
                @{ samples = $Values; median = Get-BenchmarkMedian $Values; min = ($Values | Measure-Object -Minimum).Minimum; max = ($Values | Measure-Object -Maximum).Maximum; sum = $Sum }
            }
        }
    }
    foreach ($Field in ($script:Dimensions + @('total'))) {
        $Values = @(foreach ($Trial in $Record.trials) { if ($Field -eq 'total') { ($Trial.quality.Values | Measure-Object -Sum).Sum } else { $Trial.quality[$Field] } })
        $Result.quality[$Field] = @{ samples = $Values; median = Get-BenchmarkMedian $Values; min = ($Values | Measure-Object -Minimum).Minimum; max = ($Values | Measure-Object -Maximum).Maximum }
    }
    foreach ($Key in $Record.trials[0].outcomes.Keys) { $Result.outcomes[$Key] = @($Record.trials | Where-Object { $_.outcomes[$Key] }).Count }
    foreach ($Role in @('brd', 'prd')) { $Result.reviewerDispatch[$Role] = @($Record.trials | Where-Object { $_.reviewerDispatch[$Role] }).Count }
    $Result.criticalHighFindings = ($Record.trials | ForEach-Object { $_.criticalHighFindings } | Measure-Object -Sum).Sum
    $Result
}

function Assert-BenchmarkPolicy {
    param($Policy)
    Assert-BenchmarkKeys $Policy @('schemaVersion', 'efficiencyTolerancePercent', 'minimumImprovementPercent', 'qualityReducer', 'failureReducer', 'reliabilityReducer', 'criticalHighReducer')
    if ($Policy.schemaVersion -cne 'benchmark-policy-v1' -or $Policy.efficiencyTolerancePercent -ne 5 -or $Policy.minimumImprovementPercent -ne 10 -or $Policy.qualityReducer -cne 'median-no-decrease' -or $Policy.failureReducer -cne 'sum-no-increase' -or $Policy.reliabilityReducer -cne 'per-check-count-no-decrease' -or $Policy.criticalHighReducer -cne 'sum-no-increase') { Stop-BenchmarkData 'unsupported-policy' }
}

function Compare-BenchmarkSeries {
    param([Collections.IDictionary]$Base, [Collections.IDictionary]$Head, [Collections.IDictionary]$Policy)
    Assert-BenchmarkPolicy $Policy; Assert-BenchmarkSeries $Base; Assert-BenchmarkSeries $Head
    foreach ($Key in $Base.protocol.Keys) { if ($Base.protocol[$Key] -cne $Head.protocol[$Key]) { Stop-BenchmarkData "compatibility-$Key" 'incompatible' } }
    $Before = Get-BenchmarkStatistics $Base; $After = Get-BenchmarkStatistics $Head
    $Reasons = [Collections.Generic.List[string]]::new(); $Deltas = [ordered]@{}
    foreach ($Field in $script:Efficiency) {
        [decimal]$B = $Before.resources.total[$Field].median; [decimal]$H = $After.resources.total[$Field].median
        $Deltas[$Field] = @{ absolute = $H - $B; percent = if ($B -eq 0) { if ($H -eq 0) { 0 } else { $null } } else { 100 * ($H - $B) / $B } }
        if ($H -gt $B * (1 + [decimal]$Policy.efficiencyTolerancePercent / 100)) { $Reasons.Add("efficiency-$Field") }
    }
    foreach ($Field in ($script:Dimensions + @('total'))) { if ($After.quality[$Field].median -lt $Before.quality[$Field].median) { $Reasons.Add("quality-$Field") } }
    if ($After.resources.total.failedTools.sum -gt $Before.resources.total.failedTools.sum) { $Reasons.Add('failed-tools-sum') }
    if ($After.criticalHighFindings -gt $Before.criticalHighFindings) { $Reasons.Add('critical-high-sum') }
    foreach ($Key in $Before.outcomes.Keys) { if ($After.outcomes[$Key] -lt $Before.outcomes[$Key]) { $Reasons.Add("outcome-$Key") } }
    $Same = (ConvertTo-BenchmarkCanonicalJson $Base) -ceq (ConvertTo-BenchmarkCanonicalJson $Head)
    if (-not $Same -and ($Base.seriesId -ceq $Head.seriesId -or @($Base.trials.runId | Where-Object { $_ -cin $Head.trials.runId }).Count -gt 0)) { Stop-BenchmarkData 'overlapping-independent-evidence' }
    $Improved = -not $Same -and @('requests', 'inputTokens').Where({ $null -ne $Deltas[$_].percent -and $Deltas[$_].percent -le -$Policy.minimumImprovementPercent }).Count -gt 0
    @{
        status = if ($Same) { 'unchanged' } elseif ($Reasons.Count) { 'regression' } else { 'no-regression' }
        exitCode = if ($Reasons.Count) { 3 } else { 0 }
        reasons = @($Reasons); improvementScreen = $Improved; deltas = $Deltas; baseStatistics = $Before; headStatistics = $After
    }
}

function Compare-BranchBenchmark {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$BaseRef, [string]$HeadRef = 'HEAD')
    $Report = [ordered]@{
        schemaVersion = 'benchmark-report-v1'; status = 'operational-error'; exitCode = 1
        baseCommit = $null; headCommit = $null; mergeBase = $null; baseRecord = $null; headRecord = $null
        policyHash = $null; reasons = @(); improvementScreen = $false; deltas = @{}
        baseStatistics = $null; headStatistics = $null
        provenance = 'operator-reviewed-evidence-not-attestation'
    }
    try {
        $Report.baseCommit = Resolve-BenchmarkCommit $Repository $BaseRef
        $Report.headCommit = Resolve-BenchmarkCommit $Repository $HeadRef
        $Merge = Invoke-BenchmarkGit $Repository @('merge-base', $Report.baseCommit, $Report.headCommit) -AllowFailure
        if ($null -ne $Merge) { $Report.mergeBase = [Text.Encoding]::UTF8.GetString($Merge).Trim() }
        $Base = Get-BenchmarkSelection $Repository $Report.baseCommit 'missing-baseline'
        $Report.baseRecord = @{ seriesId = $Base.record.seriesId; sha256 = $Base.sha256; sourceHash = $Base.record.sourceHash; measuredRevision = $Base.record.measuredRevision; protocol = $Base.record.protocol }
        $Report.baseStatistics = Get-BenchmarkStatistics $Base.record
        $Head = Get-BenchmarkSelection $Repository $Report.headCommit 'missing-candidate'
        $Report.headRecord = @{ seriesId = $Head.record.seriesId; sha256 = $Head.sha256; sourceHash = $Head.record.sourceHash; measuredRevision = $Head.record.measuredRevision; protocol = $Head.record.protocol }
        $Report.headStatistics = Get-BenchmarkStatistics $Head.record
        $PolicyBytes = Get-BenchmarkGitFile $Repository $Report.baseCommit 'benchmarks/efficiency/policy.json'
        $Policy = ConvertFrom-BenchmarkJson $PolicyBytes
        $Report.policyHash = Get-BenchmarkDigest $PolicyBytes
        $OldRecords = [Text.Encoding]::UTF8.GetString((Invoke-BenchmarkGit $Repository @('ls-tree', '-r', '-z', $Report.baseCommit, '--', 'benchmarks/efficiency/records')))
        foreach ($Entry in $OldRecords.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) {
            if ($Entry -notmatch '^100644 blob ([0-9a-f]{40})\t(benchmarks/efficiency/records/[a-z0-9-]+\.json)$') { Stop-BenchmarkData 'historical-record-path' }
            $OldHash = $Matches[1]; $Path = $Matches[2]
            $NewEntry = [Text.Encoding]::UTF8.GetString((Invoke-BenchmarkGit $Repository @('ls-tree', $Report.headCommit, '--', $Path))).TrimEnd("`n")
            if ($NewEntry -cne "100644 blob $OldHash`t$Path") { Stop-BenchmarkData 'historical-record-modified' }
        }
        $Comparison = Compare-BenchmarkSeries $Base.record $Head.record $Policy
        foreach ($Key in $Comparison.Keys) { $Report[$Key] = $Comparison[$Key] }
    }
    catch {
        if ($_.Exception.Message -cmatch '^(missing-baseline|missing-candidate|invalid-record|stale-record|incompatible|operational-error):([A-Za-z0-9/-]+)$') {
            $Report.status = $Matches[1]; $Report.reasons = @($Matches[2]); $Report.exitCode = if ($Report.status -eq 'operational-error') { 1 } else { 2 }
        }
        else { $Report.status = 'operational-error'; $Report.exitCode = 1; $Report.reasons = @('unexpected-operation-failure') }
    }
    $Report
}

function Write-BenchmarkReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Report, [Parameter(Mandatory)][string]$OutputDirectory)
    function Format-Number($Value) { if ($null -eq $Value) { return 'n/a' }; ([decimal]$Value).ToString('0.#########', [Globalization.CultureInfo]::InvariantCulture) }
    function Escape-Display($Value) { if ($null -eq $Value) { return 'n/a' }; [Net.WebUtility]::HtmlEncode([string]$Value).Replace('|', '&#124;').Replace("`r", '').Replace("`n", ' ').Trim() }
    $Lines = [Collections.Generic.List[string]]::new()
    $Lines.Add('# Efficiency benchmark')
    $Lines.Add('')
    $Lines.Add("**Status: $(Escape-Display $Report.status)** (exit $($Report.exitCode)). Observations, not quality approval.")
    $Lines.Add('')
    $Lines.Add('Independent three-sample series; no pairing or statistical-significance claim. Process wall time excludes offline setup and report generation.')
    $Lines.Add('Integrity and reviewed workflow/controller provenance are not authenticated model-execution attestation.')
    foreach ($Key in @('baseCommit', 'headCommit', 'mergeBase', 'policyHash')) { $Lines.Add("- $Key`: $(Escape-Display $Report[$Key])") }
    foreach ($Arm in @('base', 'head')) {
        $Record = $Report[$Arm + 'Record']
        if ($Record) { foreach ($Key in @('seriesId', 'sha256', 'sourceHash', 'measuredRevision')) { $Lines.Add("- $Arm $Key`: $(Escape-Display $Record[$Key])") }; $Lines.Add("- $Arm protocol: $(Escape-Display (ConvertTo-BenchmarkCanonicalJson $Record.protocol))") }
    }
    if ($Report.status -eq 'unchanged') { $Lines.Add('Same validated evidence; no independent candidate measurement or improvement claim.') }
    if ($Report.reasons.Count) { $Lines.Add(''); $Lines.Add('Reasons: ' + (($Report.reasons | ForEach-Object { Escape-Display $_ }) -join ', ')) }
    $Lines.Add(''); $Lines.Add("10% request/input-token improvement screen: $($Report.improvementScreen). This is separate from non-regression and strict promotion.")
    $After = $Report.headStatistics
    if ($Report.Contains('deltas') -and $Report.deltas.Count) {
        $Lines.Add(''); $Lines.Add('## Combined-resource screening deltas'); $Lines.Add('')
        $Lines.Add('| Metric | Median absolute change | Change % (positive is worse) |')
        $Lines.Add('|---|---|---|')
        foreach ($Field in $script:Efficiency) {
            $Delta = $Report.deltas[$Field]
            $Lines.Add("| $Field | $(Format-Number $Delta.absolute) | $(Format-Number $Delta.percent) |")
        }
    }
    foreach ($Part in @('workflow', 'judge', 'total')) {
        $Lines.Add(''); $Lines.Add("## $Part resources"); $Lines.Add('')
        $Lines.Add('| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |')
        $Lines.Add('|---|---|---|')
        foreach ($Field in $script:Resources) {
            $Cells = @(foreach ($Arm in @('base', 'head')) {
                $Stats = $Report[$Arm + 'Statistics']
                $Metric = if ($Stats) { $Stats.resources[$Part][$Field] } else { $null }
                if ($null -eq $Metric) { 'n/a (unavailable)' } else {
                    "$(Format-Number $Metric.median) [$(Format-Number $Metric.min), $(Format-Number $Metric.max)]; $((@($Metric.samples | ForEach-Object { Format-Number $_ })) -join ', '); $(Format-Number $Metric.sum)"
                }
            })
            $Lines.Add("| $Field | $($Cells[0]) | $($Cells[1]) |")
        }
    }
    $Lines.Add(''); $Lines.Add('## Quality and reliability'); $Lines.Add('')
    $Lines.Add('| Metric | Base | Head |'); $Lines.Add('|---|---|---|')
    foreach ($Field in ($script:Dimensions + @('total'))) {
        $Cells = @(foreach ($Arm in @('base', 'head')) {
            $Stats = $Report[$Arm + 'Statistics']
            if ($Stats) { $Metric = $Stats.quality[$Field]; "$(Format-Number $Metric.median) [$(Format-Number $Metric.min), $(Format-Number $Metric.max)]; $((@($Metric.samples | ForEach-Object { Format-Number $_ })) -join ', ')" } else { 'n/a' }
        })
        $Lines.Add("| quality/$Field | $($Cells[0]) | $($Cells[1]) |")
    }
    $Keys = if ($After) { $After.outcomes.Keys } elseif ($Report.baseStatistics) { $Report.baseStatistics.outcomes.Keys } else { @() }
    foreach ($Key in (@('criticalHighFindings') + @($Keys | Sort-Object))) {
        $Cells = @(foreach ($Arm in @('base', 'head')) {
            $Stats = $Report[$Arm + 'Statistics']
            if ($null -eq $Stats) { 'n/a' }
            elseif ($Key -eq 'criticalHighFindings') { Format-Number $Stats.criticalHighFindings }
            else { "$($Stats.outcomes[$Key])/3" }
        })
        $Lines.Add("| $(Escape-Display $Key) | $($Cells[0]) | $($Cells[1]) |")
    }
    foreach ($Role in @('brd', 'prd')) {
        $Cells = @(foreach ($Arm in @('base', 'head')) {
            $Stats = $Report[$Arm + 'Statistics']
            if ($null -eq $Stats) { 'n/a' } else { "$($Stats.reviewerDispatch[$Role])/3" }
        })
        $Lines.Add("| observed $Role reviewer dispatch (not file-deliverable acceptance) | $($Cells[0]) | $($Cells[1]) |")
    }
    $Title = 'benchmark unavailable'; $Color = '#6b7280'
    if ($After -and $Report.status -in @('recorded-observation', 'unchanged', 'no-regression', 'regression')) {
        $Title = "quality $(Format-Number $After.quality.total.median)/100 | functional $($After.outcomes.functional)/3 | workflow $($After.outcomes.completed)/3"
        $Color = if ($After.outcomes.completed -lt 3 -or $Report.status -eq 'regression') { '#b45309' } else { '#16723b' }
    }
    $EscapedTitle = [Security.SecurityElement]::Escape($Title)
    $Svg = "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"550`" height=`"28`" viewBox=`"0 0 550 28`" role=`"img`" aria-label=`"$EscapedTitle`"><title>$EscapedTitle</title><rect width=`"550`" height=`"28`" rx=`"4`" fill=`"$Color`"/><text x=`"275`" y=`"18`" text-anchor=`"middle`" fill=`"#fff`" font-family=`"Verdana,Arial,sans-serif`" font-size=`"12`">$EscapedTitle</text></svg>`n"
    Write-BenchmarkFile (Join-Path $OutputDirectory 'report.json') (ConvertTo-BenchmarkCanonicalJson $Report)
    Write-BenchmarkFile (Join-Path $OutputDirectory 'report.md') (($Lines -join "`n") + "`n")
    Write-BenchmarkFile (Join-Path $OutputDirectory 'badge.svg') $Svg
}

function Write-BenchmarkSeriesReport {
    param([Collections.IDictionary]$Record, [string]$OutputDirectory)
    $Stats = Get-BenchmarkStatistics $Record
    $Report = @{
        schemaVersion = 'benchmark-report-v1'; status = 'recorded-observation'; exitCode = 0
        baseCommit = $null; headCommit = $Record.measuredRevision; mergeBase = $null; baseRecord = $null
        headRecord = @{ seriesId = $Record.seriesId; sha256 = Get-BenchmarkDigest ([Text.Encoding]::UTF8.GetBytes((ConvertTo-BenchmarkCanonicalJson $Record))); sourceHash = $Record.sourceHash; measuredRevision = $Record.measuredRevision; protocol = $Record.protocol }
        policyHash = $null; reasons = @('no-comparison-claimed'); improvementScreen = $false; deltas = @{}
        baseStatistics = $null; headStatistics = $Stats; provenance = 'operator-reviewed-evidence-not-attestation'
    }
    Write-BenchmarkReport $Report $OutputDirectory
}

Export-ModuleMember -Function Export-BenchmarkSeries, Compare-BranchBenchmark, Write-BenchmarkReport, Write-BenchmarkSeriesReport, Assert-BenchmarkSeries, Compare-BenchmarkSeries, ConvertTo-BenchmarkCanonicalJson, ConvertFrom-BenchmarkJson, Get-BenchmarkDigest, Get-BenchmarkSourceHash, Get-BenchmarkProtocol, Get-BenchmarkRawMetrics, Resolve-BenchmarkCommit
