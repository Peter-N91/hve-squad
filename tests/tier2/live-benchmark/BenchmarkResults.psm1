#Requires -Version 7.5
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Validates and sanitizes saved observations, compares immutable revisions and writes reports.
# AI cost: none; operates on existing evidence and Git objects, never launches model collection.

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
    converterHash = 'scripts/Build-SquadPlugin.ps1'
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
        if ($Hash -cne ([string]$Compatibility[$Key]).ToLowerInvariant()) { Stop-BenchmarkData 'measured-protocol-mismatch' }
        $Protocol[$Key] = $Hash
    }
    $Protocol
}

function Assert-BenchmarkRecordedIdentity {
    <# .SYNOPSIS
    Checks retained source/protocol provenance offline; never fetches or repairs evidence.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][Collections.IDictionary]$Run)
    $null = Get-BenchmarkProtocol $Repository $Run.metadata.revision $Run.metadata.compatibility
    if ((Get-BenchmarkSourceHash $Repository $Run.metadata.revision) -cne $Run.metadata.sourceHash.ToLowerInvariant()) {
        Stop-BenchmarkData 'measured-source-mismatch'
    }
}

function Get-BenchmarkExecutionIdentity {
    <# .SYNOPSIS
    Binds freshly measured executing bytes to Git before spending; unrelated dirt is allowed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][Collections.IDictionary]$Compatibility,
        [Parameter(Mandatory)][string]$SourceHash,
        [AllowNull()][Collections.IDictionary]$ExpectedIdentity
    )
    $Repository = (Resolve-Path -LiteralPath $Repository).Path
    $Revision = Resolve-BenchmarkCommit $Repository 'HEAD'
    $Identity = [ordered]@{ repository = $Repository; revision = $Revision; sourceHash = $SourceHash.ToLowerInvariant(); compatibility = $Compatibility }
    if ($ExpectedIdentity -and (ConvertTo-BenchmarkCanonicalJson $Identity) -cne (ConvertTo-BenchmarkCanonicalJson $ExpectedIdentity)) {
        $Failure = [IO.InvalidDataException]::new('invalid-record:execution-identity-drift. Stop collection; freeze the admitted source/protocol before any further paid work.')
        $Failure.Data['observedIdentity'] = $Identity
        throw $Failure
    }
    try {
        Assert-BenchmarkRecordedIdentity -Repository $Repository -Run @{ metadata = $Identity }
    }
    catch {
        throw [IO.InvalidDataException]::new("Provenance preflight failed: $($_.Exception.Message). Commit the intended measured source/protocol and use a frozen checkout before paid collection; do not relabel retained evidence.", $_.Exception)
    }
    $Identity
}

function Get-BenchmarkSourceStatus {
    <# .SYNOPSIS
    Identifies source/protocol differences and the complete working input identity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repository,
        [string]$ProtocolRepository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    )
    $Revision = Resolve-BenchmarkCommit $Repository 'HEAD'
    $Source = Join-Path $Repository 'squad-src'
    $Listing = [Text.Encoding]::UTF8.GetString((Invoke-BenchmarkGit $Repository @('ls-tree', '-r', '--name-only', $Revision, '--', 'squad-src')))
    $Paths = @($Listing.Split("`n", [StringSplitOptions]::RemoveEmptyEntries))
    if (-not $Paths.Count) { Stop-BenchmarkData 'empty-source-tree' }
    if (Test-Path -LiteralPath $Source -PathType Container) {
        $Paths += @(Get-ChildItem -LiteralPath $Source -File -Recurse -Force |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
            ForEach-Object { 'squad-src/' + [IO.Path]::GetRelativePath($Source, $_.FullName).Replace('\', '/') })
    }
    $Issues = [Collections.Generic.List[object]]::new()
    $WorkingSource = [ordered]@{}; $WorkingProtocol = [ordered]@{}
    foreach ($Path in $Paths | Sort-Object -Unique) {
        $Committed = Get-BenchmarkGitFile $Repository $Revision $Path 8388608 -Optional
        $WorkingPath = Join-Path $Repository $Path
        $WorkingHash = if (Test-Path -LiteralPath $WorkingPath -PathType Leaf) { (Get-FileHash -LiteralPath $WorkingPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
        if ($WorkingHash) { $WorkingSource[$Path] = $WorkingHash }
        if ($null -eq $Committed -or (Get-BenchmarkDigest $Committed) -cne $WorkingHash) {
            $Regular = -not (Test-Path -LiteralPath $WorkingPath) -or -not ((Get-Item -LiteralPath $WorkingPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
            $Issues.Add([pscustomobject]@{ kind = 'source'; path = $Path; canCommit = $Regular; detail = "source: $Path" })
        }
    }
    foreach ($Key in $script:ProtocolPaths.Keys) {
        $Path = $script:ProtocolPaths[$Key]
        $Root = if ($Key -eq 'converterHash') { $Repository } else { $ProtocolRepository }
        $WorkingPath = Join-Path $Root $Path
        $Committed = Get-BenchmarkGitFile $Repository $Revision $Path 8388608 -Optional
        $WorkingHash = if (Test-Path -LiteralPath $WorkingPath -PathType Leaf) { (Get-FileHash -LiteralPath $WorkingPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
        $WorkingProtocol[$Key] = $WorkingHash
        if ($null -eq $Committed -or (Get-BenchmarkDigest $Committed) -cne $WorkingHash) {
            $LocalPath = Join-Path $Repository $Path
            $CanCommit = $WorkingHash -and (Test-Path -LiteralPath $LocalPath -PathType Leaf) -and
                -not ((Get-Item -LiteralPath $LocalPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -and
                (Get-FileHash -LiteralPath $LocalPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $WorkingHash
            $Issues.Add([pscustomobject]@{ kind = 'protocol'; path = $Path; canCommit = [bool]$CanCommit; detail = "protocol: $Path (executing checkout: $Root)" })
        }
    }
    @{
        revision = $Revision; issues = $Issues.ToArray()
        workingIdentity = Get-BenchmarkDigest ([Text.Encoding]::UTF8.GetBytes((ConvertTo-BenchmarkCanonicalJson @{ source = $WorkingSource; protocol = $WorkingProtocol })))
    }
}

function Assert-BenchmarkSourceReady {
    <# .SYNOPSIS
    Requires committed measured bytes and the exact executing protocol before collection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repository,
        [string]$ProtocolRepository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    )
    $Status = Get-BenchmarkSourceStatus -Repository $Repository -ProtocolRepository $ProtocolRepository
    if ($Status.issues.Count) {
        throw "Formal source check failed for $Repository at $($Status.revision):`n$($Status.issues.detail -join "`n")`nUse Repair (option 7) to review and optionally commit only these measured changes, then check/rebuild setup. Incompatible executing protocols require matching revisions, not dependency rebuilds. Existing evidence is unchanged."
    }
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
    if ($Record.schemaVersion -cnotin @('benchmark-series-v1', 'benchmark-series-v2') -or $Record.seriesId -cnotmatch '^[a-z0-9][a-z0-9-]{0,95}$') { Stop-BenchmarkData 'series-identity' }
    Assert-BenchmarkHash $Record.measuredRevision 40
    Assert-BenchmarkHash $Record.sourceHash
    # V1 remains readable for historical description, but cannot bind a current snapshot.
    $Digests = @($script:ProtocolDigests | Where-Object { $Record.schemaVersion -ceq 'benchmark-series-v2' -or $_ -cne 'converterHash' })
    Assert-BenchmarkKeys $Record.protocol ($script:ProtocolLabels + $Digests + @('maxCredits', 'continuations'))
    foreach ($Key in $script:ProtocolLabels) { if ($Record.protocol[$Key] -isnot [string] -or $Record.protocol[$Key] -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.+-]{0,95}$') { Stop-BenchmarkData 'protocol-label' } }
    foreach ($Key in $Digests) { Assert-BenchmarkHash $Record.protocol[$Key] }
    Assert-BenchmarkNumber $Record.protocol.maxCredits
    Assert-BenchmarkNumber $Record.protocol.continuations -Integer
    if ($Record.protocol.evaluationPolicy -cne 'baseline-observation-v1') { Stop-BenchmarkData 'evaluation-policy' }
    Assert-BenchmarkKeys $Record.provenance @('collector', 'verifierHashBasis', 'hostAttestation', 'rawSeriesHash')
    $Collector = if ($Record.schemaVersion -ceq 'benchmark-series-v2') { 'benchmark-export-v2' } else { 'benchmark-export-v1' }
    $VerifierBasis = if ($Record.schemaVersion -ceq 'benchmark-series-v2') { 'executing-file-verified-against-measured-git' } else { 'measured-git-revision' }
    if ($Record.provenance.collector -cne $Collector -or $Record.provenance.verifierHashBasis -cne $VerifierBasis -or $Record.provenance.hostAttestation -cne 'unavailable') { Stop-BenchmarkData 'provenance-label' }
    Assert-BenchmarkHash $Record.provenance.rawSeriesHash
    if ($Record.trials -isnot [array] -or $Record.trials.Count -ne 3) { Stop-BenchmarkData 'trial-count' }
    $Ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($Trial in $Record.trials) {
        Assert-BenchmarkKeys $Trial @('runId', 'slot', 'started', 'workflow', 'judge', 'quality', 'criticalHighFindings', 'documents', 'evidence', 'outcomes', 'processes', 'reviewerDispatch')
        $Guid = [guid]::Empty
        if ($Trial.runId -isnot [string] -or -not [guid]::TryParseExact($Trial.runId, 'D', [ref]$Guid) -or $Trial.runId -cne $Guid.ToString('D') -or -not $Ids.Add($Trial.runId)) { Stop-BenchmarkData 'trial-id' }
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

function Assert-BenchmarkHistoricalSeries {
    param([string]$Repository, [Collections.IDictionary]$Record)
    Assert-BenchmarkSeries $Record
    $Revision = Resolve-BenchmarkCommit $Repository $Record.measuredRevision
    if ((Get-BenchmarkSourceHash $Repository $Revision) -cne $Record.sourceHash) { Stop-BenchmarkData 'historical-source-fingerprint' }
    foreach ($Key in $script:ProtocolPaths.Keys) {
        if ($Record.schemaVersion -ceq 'benchmark-series-v1' -and $Key -ceq 'converterHash') { continue }
        if ((Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Revision $script:ProtocolPaths[$Key] 8388608)) -cne $Record.protocol[$Key]) {
            Stop-BenchmarkData "historical-protocol-$Key"
        }
    }
}

function Assert-BenchmarkSnapshot {
    param([string]$Repository, [string]$Commit, [Collections.IDictionary]$Record)
    Assert-BenchmarkSeries $Record
    if ($Record.schemaVersion -cne 'benchmark-series-v2') { Stop-BenchmarkData 'unbound-execution-protocol' 'stale-record' }
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
    if ($Controls.Contains('schemaVersion')) {
        if ($Controls.schemaVersion -cne 'efficiency-control-v1' -or $Controls.runs.Count -ne 3) { Stop-BenchmarkData 'control-series-schema' }
    }
    else {
        Assert-BenchmarkKeys $Controls @('runs')
        if ($Controls.runs.Count -ne 6) { Stop-BenchmarkData 'native-series-count' }
        $NativeIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($Arm in @('baseline', 'candidate')) {
            $Group = @($Controls.runs | Where-Object { $_.metadata.arm -ceq $Arm })
            if ($Group.Count -ne 3 -or (@($Group.metadata.pair | Sort-Object) -join ',') -ne '1,2,3') { Stop-BenchmarkData 'native-series-slots' }
            foreach ($Run in $Group) { if (-not $NativeIds.Add([string]$Run.metadata.runId)) { Stop-BenchmarkData 'native-series-duplicate' } }
        }
    }
    Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1') -Force
    $Trials = @(); $Protocol = $null; $Revision = $null; $SourceHash = $null; $SelectedArm = $null
    foreach ($Directory in $TrialDirectories) {
        $RunBytes = [IO.File]::ReadAllBytes((Join-Path $Directory 'out/run.json'))
        $Run = ConvertFrom-BenchmarkJson $RunBytes 16777216
        if ($Run.metadata.arm -cnotin @('baseline', 'candidate')) { Stop-BenchmarkData 'raw-arm' }
        if ($null -eq $SelectedArm) { $SelectedArm = $Run.metadata.arm }
        if ($SelectedArm -cne $Run.metadata.arm) { Stop-BenchmarkData 'mixed-selected-arms' }
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
        schemaVersion = 'benchmark-series-v2'; seriesId = $SeriesId; measuredRevision = $Revision; sourceHash = $SourceHash
        protocol = $Protocol
        provenance = @{ collector = 'benchmark-export-v2'; verifierHashBasis = 'executing-file-verified-against-measured-git'; hostAttestation = 'unavailable'; rawSeriesHash = Get-BenchmarkDigest $Raw }
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
        $CampaignPointer = Join-Path $Root 'latest-campaign.json'
        if (Test-Path -LiteralPath $CampaignPointer -PathType Leaf) { Remove-Item -LiteralPath $CampaignPointer }
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
    param([string]$Repository, [string]$Commit, [string]$MissingStatus = 'missing-baseline', [switch]$Historical, [switch]$Descriptive)
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
    if ($Historical -or $Descriptive) {
        if ($Historical -and $Record.schemaVersion -cne 'benchmark-series-v2') { Stop-BenchmarkData 'unbound-execution-protocol' }
        Assert-BenchmarkHistoricalSeries $Repository $Record
        $Ancestor = Invoke-BenchmarkGit $Repository @('merge-base', '--is-ancestor', $Record.measuredRevision, $Commit) -AllowFailure
        if ($null -eq $Ancestor) { Stop-BenchmarkData 'measured-revision-not-ancestor' }
    }
    else { Assert-BenchmarkSnapshot $Repository $Commit $Record }
    @{ record = $Record; sha256 = $Pointer.sha256; bytes = $RecordBytes }
}

function Assert-BenchmarkHistory {
    param([string]$Repository, [string]$Controller, [string]$Candidate, [switch]$AllowNewControllerRecords)
    $Common = if ($AllowNewControllerRecords) {
        [Text.Encoding]::UTF8.GetString((Invoke-BenchmarkGit $Repository @('merge-base', $Controller, $Candidate))).Trim()
    } else { $null }
    $OldRecords = [Text.Encoding]::UTF8.GetString((Invoke-BenchmarkGit $Repository @('ls-tree', '-r', '-z', $Controller, '--', 'benchmarks/efficiency/records', 'benchmarks/efficiency/campaigns')))
    foreach ($Entry in $OldRecords.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) {
        if ($Entry -notmatch '^100644 blob ([0-9a-f]{40})\t(benchmarks/efficiency/(?:records|campaigns)/[a-z0-9-]+\.json)$') { Stop-BenchmarkData 'historical-record-path' }
        $OldHash = $Matches[1]; $Path = $Matches[2]
        $NewEntry = [Text.Encoding]::UTF8.GetString((Invoke-BenchmarkGit $Repository @('ls-tree', $Candidate, '--', $Path))).TrimEnd("`n")
        if ($AllowNewControllerRecords -and -not $NewEntry) {
            $CommonEntry = Invoke-BenchmarkGit $Repository @('ls-tree', $Common, '--', $Path)
            if ($CommonEntry.Length -eq 0) { continue }
        }
        if ($NewEntry -cne "100644 blob $OldHash`t$Path") { Stop-BenchmarkData 'historical-record-modified' }
    }
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

function Get-BenchmarkProtocolDifferences {
    param($Base, $Head, [switch]$DeploymentComparison, [switch]$HistoricalReference)
    if ($DeploymentComparison -and $HistoricalReference) { Stop-BenchmarkData 'conflicting-comparison-mode' }
    if ((($Base.Keys | Sort-Object) -join ',') -cne (($Head.Keys | Sort-Object) -join ',')) { Stop-BenchmarkData 'compatibility-fields' 'incompatible' }
    $Differences = [ordered]@{}
    foreach ($Key in $Base.Keys) {
        if ($Base[$Key] -ceq $Head[$Key]) { continue }
        if (($DeploymentComparison -and $Key -ceq 'installHash') -or
            ($HistoricalReference -and $Key -cin @('installHash', 'powershell', 'cliVersion', 'maxCredits', 'roleModelPolicyHash'))) {
            $Differences[$Key] = @{ old = $Base[$Key]; new = $Head[$Key] }
        } else { Stop-BenchmarkData "compatibility-$Key" 'incompatible' }
    }
    $Differences
}

function Compare-BenchmarkSeries {
    param([Collections.IDictionary]$Base, [Collections.IDictionary]$Head, [Collections.IDictionary]$Policy, [switch]$DeploymentComparison, [switch]$HistoricalReference)
    Assert-BenchmarkPolicy $Policy; Assert-BenchmarkSeries $Base; Assert-BenchmarkSeries $Head
    if ($HistoricalReference -and ($Base.schemaVersion -cne 'benchmark-series-v2' -or $Head.schemaVersion -cne 'benchmark-series-v2')) { Stop-BenchmarkData 'unbound-execution-protocol' 'incompatible' }
    $Differences = Get-BenchmarkProtocolDifferences $Base.protocol $Head.protocol -DeploymentComparison:$DeploymentComparison -HistoricalReference:$HistoricalReference
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
    $Result = @{
        status = if ($Same) { 'unchanged' } elseif ($Reasons.Count) { 'regression' } else { 'no-regression' }
        exitCode = if ($Reasons.Count) { 3 } else { 0 }
        reasons = @($Reasons); improvementScreen = $Improved; deltas = $Deltas; baseStatistics = $Before; headStatistics = $After
    }
    if ($HistoricalReference -or $DeploymentComparison) {
        $Result.comparisonScope = if ($HistoricalReference) { 'historical-reference' } else { 'fresh-paired-deployments' }
        $Result.protocolDifferences = $Differences
        $Result.comparisonWarning = if ($HistoricalReference) {
            'Approximate historical comparison: the stored parent was measured in an older environment. All original metrics and protocol values are retained; this is not source-only causality or equal-environment evidence.'
        } else { 'Fresh paired deployment comparison: installation differences are measured treatment, not evidence of source-only causality.' }
    }
    $Result
}

function Compare-BranchBenchmark {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$BaseRef, [string]$HeadRef = 'HEAD')
    $Report = [ordered]@{
        schemaVersion = 'benchmark-report-v1'; status = 'operational-error'; exitCode = 1
        baseCommit = $null; headCommit = $null; mergeBase = $null; baseRecord = $null; headRecord = $null
        policyHash = $null; reasons = @(); improvementScreen = $false; deltas = @{}
        baseStatistics = $null; headStatistics = $null
        headCampaign = $null; availability = [ordered]@{}
        provenance = 'operator-reviewed-evidence-not-attestation'
    }
    $Selections = @{}
    foreach ($Arm in @('base', 'head')) {
        $Failure = $null; $Selection = $null; $DisplayFailure = $null
        try {
            $Commit = Resolve-BenchmarkCommit $Repository $(if ($Arm -eq 'base') { $BaseRef } else { $HeadRef })
            $Report[$Arm + 'Commit'] = $Commit
            $Selection = Get-BenchmarkSelection $Repository $Commit $(if ($Arm -eq 'base') { 'missing-baseline' } else { 'missing-candidate' })
        }
        catch {
            $Failure = Get-BenchmarkFailure $_.Exception.Message
            if ($Failure.status -ceq 'stale-record') {
                try { $Selection = Get-BenchmarkSelection $Repository $Commit -Descriptive }
                catch { $DisplayFailure = Get-BenchmarkFailure $_.Exception.Message }
            }
        }
        $Report.availability[$Arm] = @{
            status = $(if ($Failure) { $Failure.status } else { 'validated-current' })
            reason = $(if ($Failure) { $Failure.reason } else { $null })
            display = $(if ($null -eq $Selection) { 'unavailable' } elseif ($Failure) { 'validated-historical-observation-not-current' } else { 'validated-current-observation' })
            displayFailure = $(if ($DisplayFailure) { $DisplayFailure.reason } else { $null })
        }
        if ($Selection) {
            $Report[$Arm + 'Record'] = @{ schemaVersion = $Selection.record.schemaVersion; seriesId = $Selection.record.seriesId; sha256 = $Selection.sha256; sourceHash = $Selection.record.sourceHash; measuredRevision = $Selection.record.measuredRevision; protocol = $Selection.record.protocol }
            $Report[$Arm + 'Statistics'] = Get-BenchmarkStatistics $Selection.record
            if (-not $Failure) { $Selections[$Arm] = $Selection }
        }
    }
    try {
        if ($Report.baseCommit -and $Report.headCommit) {
            $Merge = Invoke-BenchmarkGit $Repository @('merge-base', $Report.baseCommit, $Report.headCommit) -AllowFailure
            if ($null -ne $Merge) { $Report.mergeBase = [Text.Encoding]::UTF8.GetString($Merge).Trim() }
        }
        if ($Report.headCommit) {
            try { $Report.headCampaign = Get-BenchmarkCampaignSelection $Repository $Report.headCommit }
            catch {
                $CampaignFailure = Get-BenchmarkFailure $_.Exception.Message
                $Report.availability.campaign = $CampaignFailure
                if ($CampaignFailure.status -ceq 'stale-record') {
                    try { $Report.headCampaign = Get-BenchmarkCampaignSelection $Repository $Report.headCommit -Descriptive }
                    catch { $Report.availability.campaign.displayFailure = (Get-BenchmarkFailure $_.Exception.Message).reason }
                }
                throw
            }
        }
        foreach ($Arm in @('base', 'head')) {
            if (-not $Selections.ContainsKey($Arm)) { Stop-BenchmarkData $Report.availability[$Arm].reason $Report.availability[$Arm].status }
        }
        Assert-BenchmarkHistory $Repository $Report.baseCommit $Report.headCommit
        if ($Report.headCampaign) { Stop-BenchmarkData 'observational-campaign-not-comparable' 'not-evaluable' }
        $Base = $Selections.base; $Head = $Selections.head
        $PolicyBytes = Get-BenchmarkGitFile $Repository $Report.baseCommit 'benchmarks/efficiency/policy.json'
        $Policy = ConvertFrom-BenchmarkJson $PolicyBytes
        $Report.policyHash = Get-BenchmarkDigest $PolicyBytes
        $Comparison = Compare-BenchmarkSeries $Base.record $Head.record $Policy
        foreach ($Key in $Comparison.Keys) { $Report[$Key] = $Comparison[$Key] }
    }
    catch {
        $Failure = Get-BenchmarkFailure $_.Exception.Message
        $Report.status = $Failure.status; $Report.reasons = @($Failure.reason); $Report.exitCode = $Failure.exitCode
        if ($Report.headCampaign -and $Report.reasons -cnotcontains 'observational-campaign-not-comparable') { $Report.reasons += 'observational-campaign-not-comparable' }
    }
    $Report
}

function Get-BenchmarkFailure {
    param([string]$Message)
    if ($Message -cmatch '^(missing-baseline|missing-candidate|invalid-record|stale-record|incompatible|not-evaluable|operational-error):([A-Za-z0-9/-]+)$') {
        return @{ status = $Matches[1]; reason = $Matches[2]; exitCode = $(if ($Matches[1] -ceq 'operational-error') { 1 } else { 2 }) }
    }
    @{ status = 'operational-error'; reason = 'unexpected-operation-failure'; exitCode = 1 }
}

function Write-BenchmarkReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Report, [Parameter(Mandatory)][string]$OutputDirectory)
    if ($Report.status -cnotin @('recorded-observation', 'unchanged', 'no-regression', 'regression')) {
        Write-BenchmarkUnavailableReport $Report $OutputDirectory
        return
    }
    function Format-Number($Value) { if ($null -eq $Value) { return 'n/a' }; ([decimal]$Value).ToString('0.#########', [Globalization.CultureInfo]::InvariantCulture) }
    function Escape-Display($Value) { if ($null -eq $Value) { return 'n/a' }; [Net.WebUtility]::HtmlEncode([string]$Value).Replace('|', '&#124;').Replace("`r", '').Replace("`n", ' ').Trim() }
    function Format-ReadableNumber($Value, [int]$Places = 0) {
        if ($null -eq $Value) { return 'Not available' }
        ([decimal]$Value).ToString("N$Places", [Globalization.CultureInfo]::InvariantCulture)
    }
    function Format-Duration($Seconds) {
        if ($null -eq $Seconds) { return 'Not available' }
        $Rounded = [decimal]::Round([decimal]$Seconds, 1)
        $Minutes = [decimal]::Floor($Rounded / 60)
        "$(Format-ReadableNumber $Minutes) min $(Format-Number ($Rounded - 60 * $Minutes)) s"
    }
    function Format-CheckName([string]$Key) {
        $Names = @{
            completed = 'Full workflow acceptance'; functional = 'All functional checks'; workflow = 'Final workflow readiness'
            init = 'Initialization'; requirements = 'Requirements'; build = 'Build'; stage = 'Stage readiness'
            stateVerifier = 'State verification'; reviewOutcome = 'Review outcome'; dispatchEvidence = 'Dispatch evidence'
            scribeHistory = 'Scribe history'; 'id-boundary-preserves-store' = 'ID boundary preserves stored data'
            'BRD Quality Reviewer' = 'BRD reviewer deliverable acceptance'; 'PRD Quality Reviewer' = 'PRD reviewer deliverable acceptance'
        }
        (@($Key.Split('/') | ForEach-Object { if ($Names.ContainsKey($_)) { $Names[$_] } else { $_.Replace('-', ' ') } })) -join ': '
    }
    function Format-Change($Delta, [string]$Field) {
        if ($null -eq $Delta) { return 'Not compared' }
        if ($Delta.absolute -eq 0) { return 'No change' }
        if ($null -eq $Delta.percent) { return 'New usage (baseline was zero)' }
        $Amount = if ([decimal]::Abs($Delta.percent) -lt 0.01) { '<0.01' } else { Format-ReadableNumber ([decimal]::Abs($Delta.percent)) 2 }
        $Direction = if ($Field -eq 'measuredProcessWallSeconds') {
            if ($Delta.absolute -gt 0) { 'slower' } else { 'faster' }
        } elseif ($Field -eq 'credits') {
            if ($Delta.absolute -gt 0) { 'higher' } else { 'lower' }
        } else { if ($Delta.absolute -gt 0) { 'more' } else { 'fewer' } }
        "$(Escape-Display $Amount)% $Direction"
    }
    function Format-Reason([string]$Reason) {
        switch -CaseSensitive ($Reason) {
            'no-comparison-claimed' { return 'No baseline comparison was requested.' }
            'no-selected-record' {
                $Side = if ($Report.status -eq 'missing-baseline') { 'baseline' } else { 'candidate' }
                return "The $Side branch has no selected benchmark record. Record and commit its benchmark before comparing."
            }
            'failed-tools-sum' { return 'The total number of failed tool calls increased.' }
            'critical-high-sum' { return 'The total number of critical/high findings increased.' }
        }
        if ($Reason.StartsWith('quality-')) {
            $Dimension = $Reason.Substring(8)
            $Name = switch -CaseSensitive ($Dimension) {
                'businessClarity' { 'Business clarity' }; 'scopeFidelity' { 'Scope fidelity' }
                'acceptanceCriteria' { 'Acceptance criteria' }; 'traceability' { 'Traceability' }
                'risksAndDecisions' { 'Risks and decisions' }; 'total' { 'Overall quality' }
                default { $Dimension }
            }
            return "$(Escape-Display $Name) scored lower."
        }
        if ($Reason.StartsWith('outcome-')) { return "$(Escape-Display (Format-CheckName $Reason.Substring(8))) passed in fewer trials." }
        if ($Reason.StartsWith('efficiency-')) {
            $Field = $Reason.Substring(11)
            $Name = if ($ResourceNames.ContainsKey($Field)) { $ResourceNames[$Field] } else { $Field }
            return "$(Escape-Display $Name) exceeded the allowed increase."
        }
        Escape-Display $Reason
    }
    $ResourceNames = @{
        measuredProcessWallSeconds = 'Measured benchmark time per trial'; credits = 'Consumption per trial'
        requests = 'Model requests per trial'; inputTokens = 'Input tokens per trial'
        outputTokens = 'Output tokens per trial'; toolCalls = 'Tool calls per trial'
    }
    $Before = $Report.baseStatistics; $After = $Report.headStatistics
    $Arms = @(if ($Before) { 'base' }; if ($After) { 'head' })
    $CanCompare = $Before -and $After -and $Report.status -in @('unchanged', 'no-regression', 'regression')
    $Columns = @($Arms | ForEach-Object { if ($Arms.Count -eq 1 -and $Report.status -eq 'recorded-observation') { 'Recorded result' } elseif ($_ -eq 'base') { 'Baseline' } else { 'Candidate' } })
    $SummaryColumns = @('Measure') + $Columns
    if ($CanCompare) { $SummaryColumns += 'Change' }
    $Header = '| ' + ($SummaryColumns -join ' | ') + ' |'
    $Separator = '| ' + ((@($SummaryColumns | ForEach-Object { '---' })) -join ' | ') + ' |'
    $Lines = [Collections.Generic.List[string]]::new()
    $Lines.Add('# Efficiency benchmark')
    $Lines.Add('')
    $Verdict = switch -CaseSensitive ($Report.status) {
        'recorded-observation' { '**Recorded observations; no comparison yet.** These results are not quality approval.' }
        'unchanged' { '**No measurement change.** Both snapshots select the same validated evidence; no new trial or improvement is claimed.' }
        'no-regression' { '**No measured regression.** The candidate meets the comparison policy; this does not mean all product checks passed.' }
        'regression' { '**Regression detected.** The candidate fails one or more comparison checks; resource savings do not override quality or reliability failures.' }
        default { '**Comparison unavailable.** Missing, invalid or incompatible evidence must not be treated as a passing result.' }
    }
    $Lines.Add($Verdict)
    $Lines.Add('')
    if ($Report.Contains('comparisonWarning')) {
        $Lines.Add("**$(Escape-Display $Report.comparisonWarning)**")
        $Lines.Add('')
        $Lines.Add("Comparison scope: $(Escape-Display $Report.comparisonScope)")
        foreach ($Key in $Report.protocolDifferences.Keys | Sort-Object) {
            $Difference = $Report.protocolDifferences[$Key]
            $Lines.Add("* $(Escape-Display $Key): old ``$(Escape-Display $Difference.old)``; new ``$(Escape-Display $Difference.new)``.")
        }
        $Lines.Add('')
    }
    $Lines.Add('Each series contains three trials. Per-trial figures below are **medians**; explicitly labelled totals cover all three trials. These are independent screening observations, not proof of statistical significance or causality.')
    if ($Arms.Count) {
        $Lines.Add(''); $Lines.Add('## Performance and consumption'); $Lines.Add('')
        $Lines.Add($Header); $Lines.Add($Separator)
        foreach ($Field in @('measuredProcessWallSeconds', 'credits', 'requests', 'inputTokens', 'outputTokens', 'toolCalls')) {
            $Cells = @($ResourceNames[$Field]) + @(foreach ($Arm in $Arms) {
                $Value = $Report[$Arm + 'Statistics'].resources.total[$Field].median
                if ($Field -eq 'measuredProcessWallSeconds') { Format-Duration $Value }
                elseif ($Field -eq 'credits') { Format-ReadableNumber $Value 2 }
                else { Format-ReadableNumber $Value }
            })
            if ($CanCompare) { $Cells += Format-Change $(if ($Report.Contains('deltas')) { $Report.deltas[$Field] } else { $null }) $Field }
            $Lines.Add('| ' + ($Cells -join ' | ') + ' |')
        }
        $Totals = @(foreach ($Index in 0..($Arms.Count - 1)) { $(if ($Arms.Count -gt 1) { "$($Columns[$Index]): " }) + "**$(Format-ReadableNumber $Report[$Arms[$Index] + 'Statistics'].resources.total.credits.sum 2)**" })
        $Lines.Add(''); $Lines.Add('Total consumption across all three trials: ' + ($Totals -join '; ') + '.')
        $Lines.Add('Consumption is measured in credits, not currency. Measured benchmark time combines workflow-stage wall time and the independent judge. Stage clocks include some harness checks, not just agent subprocess execution; preparation, report generation and some independent evaluation are excluded. Pure agent latency and whole-wizard duration are not measured. Every sample and the complete numeric data are retained in `report.json`; detailed tables appear below.')
        $Lines.Add(''); $Lines.Add('| Timing boundary (median per trial) | ' + ($Columns -join ' | ') + ' |')
        $Lines.Add('| --- | ' + ((@($Columns | ForEach-Object { '---' })) -join ' | ') + ' |')
        foreach ($Part in @('workflow', 'judge')) {
            $Label = if ($Part -eq 'workflow') { 'Workflow-stage wall time (includes harness checks)' } else { 'Independent-judge time' }
            $Cells = @(foreach ($Arm in $Arms) { Format-Duration $Report[$Arm + 'Statistics'].resources[$Part].measuredProcessWallSeconds.median })
            $Lines.Add("| $Label | " + ($Cells -join ' | ') + ' |')
        }
        $Lines.Add('Combined medians are reduced from per-trial stage-plus-judge sums, not added component medians.')
        $Lines.Add(''); $Lines.Add('## Document quality and acceptance'); $Lines.Add('')
        $Lines.Add('| Measure | ' + ($Columns -join ' | ') + ' |'); $Lines.Add('| --- | ' + ((@($Columns | ForEach-Object { '---' })) -join ' | ') + ' |')
        foreach ($Field in @('quality', 'functional', 'completed', 'failedTools', 'criticalHighFindings')) {
            $Label = switch ($Field) { 'quality' { 'Document quality (median /100)' }; 'functional' { 'Functional acceptance' }; 'completed' { 'Full workflow acceptance' }; 'failedTools' { 'Failed tool calls (total)' }; 'criticalHighFindings' { 'Critical/high findings (total)' } }
            $Cells = @(foreach ($Arm in $Arms) {
                $Stats = $Report[$Arm + 'Statistics']
                switch ($Field) {
                    'quality' { "$(Format-ReadableNumber $Stats.quality.total.median)/100" }
                    'functional' { "$($Stats.outcomes.functional) of 3 trials" }
                    'completed' { "$($Stats.outcomes.completed) of 3 trials" }
                    'failedTools' { Format-ReadableNumber $Stats.resources.total.failedTools.sum }
                    'criticalHighFindings' { Format-ReadableNumber $Stats.criticalHighFindings }
                }
            })
            $Lines.Add("| $Label | " + ($Cells -join ' | ') + ' |')
        }
        $Lines.Add(''); $Lines.Add('Functional acceptance requires every functional probe to pass. **Full workflow acceptance** also requires every stage and the final workflow checks to pass. A successful process exit or final build alone is not full acceptance.')
        $Cells = @(foreach ($Arm in $Arms) {
            $Stats = $Report[$Arm + 'Statistics']
            if ($Stats.outcomes.completed -eq 0) { 'Unavailable (0 accepted workflows)' }
            elseif ($null -eq $Stats.resources.total.credits) { 'Unavailable (missing consumption)' }
            else { Format-ReadableNumber ([decimal]$Stats.resources.total.credits.sum / $Stats.outcomes.completed) 2 }
        })
        $Lines.Add(''); $Lines.Add('Observed total consumption per accepted workflow: ' + ((@(for ($Index = 0; $Index -lt $Arms.Count; $Index++) { "$($Columns[$Index]): $($Cells[$Index])" })) -join '; ') + '.')
        $Lines.Add('This descriptive ratio includes consumption from every recorded attempt, not just successful ones; it is not expected retry cost. Document quality scores assess BRD/PRD content, not delivered software quality. Expert calibration and statistical significance have not been established.')
    } else { $Lines.Add(''); $Lines.Add('No comparable measurements are available. See the diagnostic reasons and provenance below.') }
    if ($Report.reasons.Count) {
        $Lines.Add(''); $Lines.Add('## Comparison findings'); $Lines.Add('')
        foreach ($Reason in $Report.reasons) { $Lines.Add('- ' + (Format-Reason $Reason)) }
    }
    if ($CanCompare -and $Report.status -ne 'unchanged') {
        $Screen = if ($Report.improvementScreen) { '**Met.**' } else { '**Not met.**' }
        $Lines.Add(''); $Lines.Add("10% resource-improvement screen: $Screen This requires at least 10% fewer median model requests or input tokens. It is separate from non-regression, product acceptance and strict baseline promotion.")
    }
    $Keys = if ($After) { $After.outcomes.Keys } elseif ($Before) { $Before.outcomes.Keys } else { @() }
    $Attention = @($Keys | Sort-Object | Where-Object {
        $Key = $_
        @($Arms | Where-Object { $Report[$_ + 'Statistics'].outcomes[$Key] -lt 3 }).Count -gt 0
    })
    if ($Attention.Count) {
        $Lines.Add(''); $Lines.Add('## Checks needing attention'); $Lines.Add('')
        $Lines.Add('Only checks that did not pass in all three trials are shown here. The complete check list, including passing checks, is available in the details below.')
        $Lines.Add(''); $Lines.Add('| Check | ' + ($Columns -join ' | ') + ' |'); $Lines.Add('| --- | ' + ((@($Columns | ForEach-Object { '---' })) -join ' | ') + ' |')
        foreach ($Key in $Attention) {
            $Cells = @($Arms | ForEach-Object { "$($Report[$_ + 'Statistics'].outcomes[$Key]) of 3" })
            $Lines.Add("| $(Escape-Display (Format-CheckName $Key)) | " + ($Cells -join ' | ') + ' |')
        }
        $Lines.Add(''); $Lines.Add('Reviewer dispatch and reviewer file-deliverable acceptance are different checks. A reviewer may have been dispatched even when its required deliverable check fails.')
    }
    $Lines.Add(''); $Lines.Add('<details>'); $Lines.Add('<summary>All measurements, samples and checks</summary>'); $Lines.Add('')
    $Lines.Add('Resource tables use exact values: median [minimum, maximum]; individual samples; series total. Time is in seconds unless explicitly labelled as an event interval in milliseconds; event intervals are diagnostic, not end-to-end timing.')
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
    $Lines.Add(''); $Lines.Add('</details>')
    $Lines.Add(''); $Lines.Add('<details>'); $Lines.Add('<summary>Provenance, compatibility and machine status</summary>'); $Lines.Add('')
    $Lines.Add("Machine status: **$(Escape-Display $Report.status)**; exit code **$($Report.exitCode)**.")
    $Lines.Add('Integrity hashes and a reviewed workflow/controller do not authenticate model execution.')
    $Lines.Add(''); $Lines.Add('| Reference | Value |'); $Lines.Add('|---|---|')
    foreach ($Key in @('baseCommit', 'headCommit', 'mergeBase', 'policyHash')) { $Lines.Add("| $Key | $(Escape-Display $Report[$Key]) |") }
    foreach ($Arm in @('base', 'head')) {
        $Record = $Report[$Arm + 'Record']
        if ($Record) {
            $Label = if ($Arm -eq 'base') { 'Baseline' } else { 'Recorded / candidate' }
            foreach ($Key in @('seriesId', 'sha256', 'sourceHash', 'measuredRevision')) { $Lines.Add("| $Label $Key | $(Escape-Display $Record[$Key]) |") }
        }
    }
    foreach ($Arm in @('base', 'head')) {
        $Record = $Report[$Arm + 'Record']
        if ($Record) {
            $Label = if ($Arm -eq 'base') { 'Baseline' } else { 'Recorded / candidate' }
            $Lines.Add(''); $Lines.Add("### $Label protocol"); $Lines.Add('')
            $Lines.Add('| Field | Value |'); $Lines.Add('|---|---|')
            foreach ($Key in @($Record.protocol.Keys | Sort-Object)) { $Lines.Add("| $(Escape-Display $Key) | $(Escape-Display $Record.protocol[$Key]) |") }
        }
    }
    if ($Report.reasons.Count) { $Lines.Add(''); $Lines.Add('Machine reasons: ' + (($Report.reasons | ForEach-Object { Escape-Display $_ }) -join ', ')) }
    $Lines.Add(''); $Lines.Add('</details>')
    $Title = 'benchmark unavailable'; $Color = '#6b7280'
    if ($After -and $Report.status -in @('recorded-observation', 'unchanged', 'no-regression', 'regression')) {
        $AverageSeconds = [decimal]$After.resources.total.measuredProcessWallSeconds.sum / $After.resources.total.measuredProcessWallSeconds.samples.Count
        $Title = "doc quality $(Format-Number $After.quality.total.median)/100 | functional $($After.outcomes.functional)/3 | workflow $($After.outcomes.completed)/3 | avg benchmark time $(Format-Duration $AverageSeconds)"
        $Color = if ($After.outcomes.completed -lt 3 -or $Report.status -eq 'regression') { '#b45309' } else { '#16723b' }
    }
    $EscapedTitle = [Security.SecurityElement]::Escape($Title)
    $Svg = "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"720`" height=`"28`" viewBox=`"0 0 720 28`" role=`"img`" aria-label=`"$EscapedTitle`"><title>$EscapedTitle</title><rect width=`"720`" height=`"28`" rx=`"4`" fill=`"$Color`"/><text x=`"360`" y=`"18`" text-anchor=`"middle`" fill=`"#fff`" font-family=`"Verdana,Arial,sans-serif`" font-size=`"12`">$EscapedTitle</text></svg>`n"
    Write-BenchmarkFile (Join-Path $OutputDirectory 'report.json') (ConvertTo-BenchmarkCanonicalJson $Report)
    Write-BenchmarkFile (Join-Path $OutputDirectory 'report.md') (($Lines -join "`n") + "`n")
    Write-BenchmarkFile (Join-Path $OutputDirectory 'badge.svg') $Svg
}

function Write-BenchmarkUnavailableReport {
    param([Collections.IDictionary]$Report, [string]$OutputDirectory)
    function Escape-Unavailable($Value) { [Net.WebUtility]::HtmlEncode([string]$Value).Replace('|', '&#124;').Replace("`r", '').Replace("`n", ' ') }
    function Format-UnavailableNumber($Value) { if ($null -eq $Value) { 'unavailable' } else { ([decimal]$Value).ToString('0.#######', [Globalization.CultureInfo]::InvariantCulture) } }
    $Lines = @('# Efficiency benchmark', '', '**Comparison unavailable.** No comparable measurements are available for a strict verdict.',
        '', 'The independently validated observations below are descriptive only. They are not a 1:1 comparison: no deltas, ratios, regression certification or improvement claim is available.',
        '', "Machine status: **$(Escape-Unavailable $Report.status)**; exit code **$($Report.exitCode)**.",
        "Reasons: $(($Report.reasons | ForEach-Object { Escape-Unavailable $_ }) -join ', ').")
    if ($Report.status -ceq 'missing-baseline' -and $Report.reasons -contains 'no-selected-record') { $Lines += 'The baseline branch has no selected benchmark record.' }
    foreach ($Arm in @('base', 'head')) {
        $Label = if ($Arm -ceq 'base') { 'Parent observations' } else { 'Head observations' }
        $Lines += @('', "## $Label", '', "Snapshot: ``$(Escape-Unavailable $Report[$Arm + 'Commit'])``.")
        if ($Report.Contains('availability')) {
            $State = $Report.availability[$Arm]
            $Lines += "Evidence status: $(Escape-Unavailable $State.status); $(Escape-Unavailable $State.reason); $(Escape-Unavailable $State.display)."
            if ($State.Contains('displayFailure') -and $State.displayFailure) { $Lines += "Historical display unavailable: $(Escape-Unavailable $State.displayFailure)." }
        }
        $Stats = $Report[$Arm + 'Statistics']; $Record = $Report[$Arm + 'Record']
        if ($null -eq $Stats) { $Lines += 'No validated numeric observations are available for this side.'; continue }
        if ($Record) {
            foreach ($Key in @('seriesId', 'measuredRevision', 'sourceHash', 'sha256')) { $Lines += "* $Key`: ``$(Escape-Unavailable $Record[$Key])``" }
            if ($Record.Contains('schemaVersion')) { $Lines += "* schemaVersion: ``$(Escape-Unavailable $Record.schemaVersion)``" }
        }
        $Lines += @('', '| Observed measure | Value |', '|---|---:|',
            "| Document quality median /100 | $(Format-UnavailableNumber $Stats.quality.total.median) |",
            "| Functional acceptance | $($Stats.outcomes.functional)/3 |",
            "| Full workflow acceptance | $($Stats.outcomes.completed)/3 |",
            "| Total credits (three trials) | $(Format-UnavailableNumber $Stats.resources.total.credits.sum) |")
        foreach ($Field in $script:Efficiency) {
            $Metric = $Stats.resources.total[$Field]
            $Lines += "| $Field median | $(Format-UnavailableNumber $(if ($Metric) { $Metric.median } else { $null })) |"
        }
        if ($Record) {
            $Lines += @('', '### Measured protocol', '', '| Field | Value |', '|---|---|')
            foreach ($Key in $Record.protocol.Keys | Sort-Object) { $Lines += "| $(Escape-Unavailable $Key) | $(Escape-Unavailable $Record.protocol[$Key]) |" }
        }
    }
    if ($Report.Contains('headCampaign') -and $Report.headCampaign) {
        Write-BenchmarkCampaignReport $Report.headCampaign $OutputDirectory
        $CampaignText = [IO.File]::ReadAllText((Join-Path $OutputDirectory 'campaign-report.md'))
        $Lines += @('', '## Latest head campaign (not a complete comparison series)', '', ($CampaignText -replace '^# Latest benchmark campaign', '### Recorded campaign'))
        if ($Report.Contains('availability') -and $Report.availability.Contains('campaign')) {
            $Lines += "Campaign is historical only: $(Escape-Unavailable $Report.availability.campaign.reason). It is not current-source evidence."
        }
    }
    $Lines += @('', 'Hashes establish integrity, not authenticated model execution. Historical observations describe their measured revision, not the current source. Unsupported schemas and invalid pointers are never guessed or displayed as trustworthy numbers.')
    Write-BenchmarkFile (Join-Path $OutputDirectory 'report.json') (ConvertTo-BenchmarkCanonicalJson $Report)
    Write-BenchmarkFile (Join-Path $OutputDirectory 'report.md') (($Lines -join "`n") + "`n")
    Write-BenchmarkFile (Join-Path $OutputDirectory 'badge.svg') "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"260`" height=`"28`" role=`"img`" aria-label=`"benchmark unavailable`"><title>benchmark unavailable</title><rect width=`"260`" height=`"28`" rx=`"4`" fill=`"#6b7280`"/><text x=`"130`" y=`"18`" text-anchor=`"middle`" fill=`"white`" font-family=`"Verdana,Arial,sans-serif`" font-size=`"12`">benchmark unavailable</text></svg>`n"
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

function Assert-BenchmarkCampaign {
    param([Collections.IDictionary]$Record)
    Assert-BenchmarkKeys $Record @('schemaVersion', 'campaignId', 'measuredRevision', 'sourceHash', 'protocol', 'provenance', 'trials')
    if ($Record.schemaVersion -cne 'benchmark-campaign-v1' -or $Record.campaignId -cnotmatch '^[a-z0-9][a-z0-9-]{0,95}$') { Stop-BenchmarkData 'campaign-identity' }
    Assert-BenchmarkHash $Record.measuredRevision 40
    Assert-BenchmarkHash $Record.sourceHash
    Assert-BenchmarkKeys $Record.protocol ($script:ProtocolLabels + $script:ProtocolDigests + @('maxCredits', 'continuations'))
    foreach ($Key in $script:ProtocolLabels) { if ($Record.protocol[$Key] -isnot [string] -or $Record.protocol[$Key] -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.+-]{0,95}$') { Stop-BenchmarkData 'protocol-label' } }
    foreach ($Key in $script:ProtocolDigests) { Assert-BenchmarkHash $Record.protocol[$Key] }
    Assert-BenchmarkNumber $Record.protocol.maxCredits
    Assert-BenchmarkNumber $Record.protocol.continuations -Integer
    if ($Record.protocol.evaluationPolicy -cne 'baseline-observation-v1') { Stop-BenchmarkData 'evaluation-policy' }
    Assert-BenchmarkKeys $Record.provenance @('collector', 'hostAttestation')
    if ($Record.provenance.collector -cne 'benchmark-campaign-export-v1' -or $Record.provenance.hostAttestation -cne 'unavailable') { Stop-BenchmarkData 'campaign-provenance' }
    if ($Record.trials -isnot [array] -or $Record.trials.Count -lt 1 -or $Record.trials.Count -gt 3) { Stop-BenchmarkData 'campaign-trials' }
    $Ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $Slots = [Collections.Generic.HashSet[int]]::new()
    foreach ($Trial in $Record.trials) {
        Assert-BenchmarkKeys $Trial @('runId', 'slot', 'started', 'workflow', 'judge', 'quality', 'criticalHighFindings', 'documents', 'evidence', 'outcomes', 'accounting', 'unavailable')
        $Guid = [guid]::Empty
        if ($Trial.runId -isnot [string] -or -not [guid]::TryParseExact($Trial.runId, 'D', [ref]$Guid) -or $Trial.runId -cne $Guid.ToString('D') -or -not $Ids.Add($Trial.runId)) { Stop-BenchmarkData 'trial-id' }
        Assert-BenchmarkNumber $Trial.slot -Integer -Maximum 3
        if ($Trial.slot -lt 1 -or -not $Slots.Add($Trial.slot) -or $Trial.started -cnotmatch '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,7})?Z$') { Stop-BenchmarkData 'trial-time-slot' }
        foreach ($Part in @('workflow', 'judge')) {
            if ($Part -ceq 'judge' -and $null -eq $Trial.judge) { continue }
            Assert-BenchmarkKeys $Trial[$Part] $script:Resources
            foreach ($Key in $script:Resources) {
                if ($Key -in @('cacheReadTokens', 'cacheWriteTokens', 'eventElapsedMs') -and $null -eq $Trial[$Part][$Key]) { continue }
                Assert-BenchmarkNumber $Trial[$Part][$Key] -Integer:($Key -notin @('credits', 'measuredProcessWallSeconds', 'eventElapsedMs'))
            }
        }
        if ($null -ne $Trial.judge -and $Trial.judge.toolCalls -ne 0) { Stop-BenchmarkData 'judge-tool-use' }
        if ($null -ne $Trial.quality) {
            Assert-BenchmarkKeys $Trial.quality $script:Dimensions
            foreach ($Dimension in $script:Dimensions) { Assert-BenchmarkNumber $Trial.quality[$Dimension] -Integer -Maximum 20 }
            Assert-BenchmarkNumber $Trial.criticalHighFindings -Integer
            if ($null -eq $Trial.judge) { Stop-BenchmarkData 'campaign-grade-without-judge' }
        } elseif ($null -ne $Trial.criticalHighFindings) { Stop-BenchmarkData 'campaign-findings-without-grade' }
        Assert-BenchmarkKeys $Trial.documents @('brd', 'prd', 'closingReview')
        foreach ($Hash in $Trial.documents.Values) { if ($null -ne $Hash) { Assert-BenchmarkHash $Hash } }
        if ($null -ne $Trial.quality -and ($null -eq $Trial.documents.brd -or $null -eq $Trial.documents.prd)) { Stop-BenchmarkData 'campaign-grade-without-documents' }
        Assert-BenchmarkKeys $Trial.evidence @('runHash', 'workflowEventsHash', 'judgeEventsHash')
        Assert-BenchmarkHash $Trial.evidence.runHash
        Assert-BenchmarkHash $Trial.evidence.workflowEventsHash
        if ($null -ne $Trial.evidence.judgeEventsHash) { Assert-BenchmarkHash $Trial.evidence.judgeEventsHash }
        if (($null -eq $Trial.judge) -ne ($null -eq $Trial.evidence.judgeEventsHash)) { Stop-BenchmarkData 'campaign-judge-evidence' }
        Assert-BenchmarkKeys $Trial.outcomes @('functional', 'workflow', 'completed', 'stages')
        foreach ($Key in @('functional', 'workflow', 'completed')) { if ($Trial.outcomes[$Key] -isnot [bool]) { Stop-BenchmarkData 'boolean-field' } }
        Assert-BenchmarkBooleans $Trial.outcomes.stages @('init', 'requirements', 'build')
        if ($Trial.outcomes.completed -ne ($Trial.outcomes.functional -and $Trial.outcomes.workflow -and @($Trial.outcomes.stages.Values | Where-Object { -not $_ }).Count -eq 0)) { Stop-BenchmarkData 'completion-consistency' }
        Assert-BenchmarkKeys $Trial.accounting @('knownCredits', 'complete', 'totalCredits')
        Assert-BenchmarkNumber $Trial.accounting.knownCredits
        $Known = [decimal]$Trial.workflow.credits
        if ($null -ne $Trial.judge) { $Known += [decimal]$Trial.judge.credits }
        if ($Trial.accounting.complete -isnot [bool] -or $Trial.accounting.complete -ne ($null -ne $Trial.judge) -or $Trial.accounting.knownCredits -ne $Known) { Stop-BenchmarkData 'campaign-accounting' }
        if ($Trial.accounting.complete) {
            Assert-BenchmarkNumber $Trial.accounting.totalCredits
            if ($Trial.accounting.totalCredits -ne $Known) { Stop-BenchmarkData 'campaign-accounting' }
        } elseif ($null -ne $Trial.accounting.totalCredits) { Stop-BenchmarkData 'campaign-unknown-total' }
        $Expected = @()
        if ($null -eq $Trial.judge) { $Expected += 'judge-unavailable' }
        if ($null -eq $Trial.quality) { $Expected += 'quality-unavailable' }
        foreach ($Name in @('brd', 'prd')) { if ($null -eq $Trial.documents[$Name]) { $Expected += "missing-$Name" } }
        if ($Trial.unavailable -isnot [array] -or ($Trial.unavailable -join ',') -cne ($Expected -join ',')) { Stop-BenchmarkData 'campaign-availability' }
    }
}

function Assert-BenchmarkCampaignBinding {
    param([string]$Repository, [string]$Commit, [Collections.IDictionary]$Record)
    Assert-BenchmarkCampaign $Record
    if ($null -eq (Invoke-BenchmarkGit $Repository @('merge-base', '--is-ancestor', $Record.measuredRevision, $Commit) -AllowFailure)) { Stop-BenchmarkData 'measured-revision-not-ancestor' 'stale-record' }
    foreach ($Ref in @($Commit, $Record.measuredRevision) | Select-Object -Unique) {
        if ((Get-BenchmarkSourceHash $Repository $Ref) -cne $Record.sourceHash) { Stop-BenchmarkData 'source-fingerprint' 'stale-record' }
        foreach ($Key in $script:ProtocolPaths.Keys) {
            if ((Get-BenchmarkDigest (Get-BenchmarkGitFile $Repository $Ref $script:ProtocolPaths[$Key] 8388608)) -cne $Record.protocol[$Key]) { Stop-BenchmarkData "protocol-$Key" 'stale-record' }
        }
    }
}

function Export-BenchmarkCampaign {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string[]]$TrialDirectories, [Parameter(Mandatory)][string]$CampaignId, [string]$OutputDirectory = (Join-Path $Repository 'benchmarks/efficiency'))
    if ($CampaignId -cnotmatch '^[a-z0-9][a-z0-9-]{0,95}$' -or $TrialDirectories.Count -lt 1 -or $TrialDirectories.Count -gt 3) { Stop-BenchmarkData 'campaign-selection' }
    Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1')
    function Get-CampaignFileHash([string]$Path) {
        $Item = Get-Item -LiteralPath $Path -Force
        if ($Item -isnot [IO.FileInfo]) { Stop-BenchmarkData 'campaign-file' }
        $Ancestor = $Item
        while ($null -ne $Ancestor) {
            if ($Ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { Stop-BenchmarkData 'campaign-symlink' }
            $Ancestor = if ($Ancestor -is [IO.FileInfo]) { $Ancestor.Directory } else { $Ancestor.Parent }
        }
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $Trials = @(); $Protocol = $null; $Revision = $null; $SourceHash = $null; $Arm = $null
    foreach ($Directory in $TrialDirectories) {
        $RunPath = Join-Path $Directory 'out/run.json'
        $RunHash = Get-CampaignFileHash $RunPath
        $RunBytes = [IO.File]::ReadAllBytes($RunPath)
        if ((Get-BenchmarkDigest $RunBytes) -cne $RunHash) { Stop-BenchmarkData 'campaign-run-changed' }
        $Run = ConvertFrom-BenchmarkJson $RunBytes 16777216
        if (-not (Test-EfficiencyObservation $Run)) { Stop-BenchmarkData 'raw-observation' }
        if ($Run.metadata.arm -cnotin @('baseline', 'candidate')) { Stop-BenchmarkData 'raw-arm' }
        $CurrentProtocol = Get-BenchmarkProtocol $Repository $Run.metadata.revision $Run.metadata.compatibility
        if ($null -eq $Protocol) { $Protocol = $CurrentProtocol; $Revision = $Run.metadata.revision; $SourceHash = $Run.metadata.sourceHash; $Arm = $Run.metadata.arm }
        if ((ConvertTo-BenchmarkCanonicalJson $CurrentProtocol) -cne (ConvertTo-BenchmarkCanonicalJson $Protocol) -or $Run.metadata.revision -cne $Revision -or $Run.metadata.sourceHash -cne $SourceHash -or $Run.metadata.arm -cne $Arm) { Stop-BenchmarkData 'mixed-series' }
        if (($Run.stages.name | Sort-Object) -join ',' -cne 'build,init,requirements') { Stop-BenchmarkData 'stage-count' }
        [decimal]$Wall = 0; $Stages = [ordered]@{}
        foreach ($Stage in $Run.stages) { Assert-BenchmarkNumber $Stage.process.seconds; $Wall += [decimal]$Stage.process.seconds; $Stages[$Stage.name] = $Stage.passed }
        $Workflow = Get-BenchmarkRawMetrics $Run.metrics $Wall
        $WorkflowHash = ([string]$Run.metrics.evidence.sha256).ToLowerInvariant()
        if ((Get-CampaignFileHash (Join-Path $Directory "out/$($Run.stages[-1].name)-events.jsonl")) -cne $WorkflowHash) { Stop-BenchmarkData 'workflow-events-digest' }
        $Judge = $null; $JudgeHash = $null; $Quality = $null; $Findings = $null
        if ($Run.judge.Contains('process')) {
            Assert-BenchmarkNumber $Run.judge.process.seconds
            $Judge = Get-BenchmarkRawMetrics $Run.judge.metrics ([decimal]$Run.judge.process.seconds)
            $JudgeHash = ([string]$Run.judge.metrics.evidence.sha256).ToLowerInvariant()
            if ((Get-CampaignFileHash (Join-Path $Directory 'out/judge-events.jsonl')) -cne $JudgeHash) { Stop-BenchmarkData 'judge-events-digest' }
        }
        $Workspace = [IO.Path]::GetFullPath((Join-Path $Directory 'workspace'))
        $Documents = [ordered]@{}
        foreach ($Name in @('brd', 'prd', 'closingReview')) {
            $Relative = if ($Name -ceq 'closingReview') { $Run.workflow['reviewPath'] } else { "docs/requirements/$Name.md" }
            $Hash = $null
            if ($Relative) {
                $Path = [IO.Path]::GetFullPath((Join-Path $Workspace $Relative))
                if (-not $Path.StartsWith($Workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::Ordinal)) { Stop-BenchmarkData 'document-path' }
                if (Test-Path -LiteralPath $Path -PathType Leaf) {
                    if ((Get-Item -LiteralPath $Path).Length -gt 100000) { Stop-BenchmarkData 'document-file' }
                    $Hash = Get-CampaignFileHash $Path
                }
            }
            $Documents[$Name] = $Hash
            if ($Run.judge.valid) {
                $ExpectedHash = if ($null -eq $Hash) { Get-BenchmarkDigest ([byte[]]@()) } else { $Hash }
                if ($ExpectedHash -cne ([string]$Run.judge.documentHashes[$Name]).ToLowerInvariant()) { Stop-BenchmarkData 'document-digest' }
            }
        }
        if ($Run.judge.valid) {
            if (-not (Test-EfficiencyJudge $Run.judge.response $Run.judge.documentHashes)) { Stop-BenchmarkData 'raw-judge' }
            $Quality = $Run.judge.response.scores; $Findings = $Run.judge.response.criticalHighFindings
        }
        $Unavailable = @()
        if ($null -eq $Judge) { $Unavailable += 'judge-unavailable' }
        if ($null -eq $Quality) { $Unavailable += 'quality-unavailable' }
        foreach ($Name in @('brd', 'prd')) { if ($null -eq $Documents[$Name]) { $Unavailable += "missing-$Name" } }
        $Known = [decimal]$Workflow.credits
        if ($null -ne $Judge) { $Known += [decimal]$Judge.credits }
        $Trials += [ordered]@{
            runId = $Run.metadata.runId; slot = $Run.metadata.pair; started = $Run.metadata.started
            workflow = $Workflow; judge = $Judge; quality = $Quality; criticalHighFindings = $Findings
            documents = $Documents; evidence = @{ runHash = $RunHash; workflowEventsHash = $WorkflowHash; judgeEventsHash = $JudgeHash }
            outcomes = @{ functional = $Run.acceptance.passed; workflow = $Run.workflow.passed; completed = $Run.completed; stages = $Stages }
            accounting = @{ knownCredits = $Known; complete = ($null -ne $Judge); totalCredits = $(if ($null -ne $Judge) { $Known } else { $null }) }
            unavailable = $Unavailable
        }
    }
    $Record = [ordered]@{
        schemaVersion = 'benchmark-campaign-v1'; campaignId = $CampaignId; measuredRevision = $Revision; sourceHash = $SourceHash
        protocol = $Protocol; provenance = @{ collector = 'benchmark-campaign-export-v1'; hostAttestation = 'unavailable' }
        trials = @($Trials | Sort-Object slot)
    }
    Assert-BenchmarkCampaignBinding $Repository (Resolve-BenchmarkCommit $Repository 'HEAD') $Record
    $Bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-BenchmarkCanonicalJson $Record))
    if ($Bytes.Length -gt 262144) { Stop-BenchmarkData 'record-size' }
    [void][IO.Directory]::CreateDirectory((Join-Path $OutputDirectory 'campaigns'))
    $File = [IO.File]::Open((Join-Path $OutputDirectory "campaigns/$CampaignId.json"), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $File.Write($Bytes) } finally { $File.Dispose() }
    Write-BenchmarkFile (Join-Path $OutputDirectory 'latest-campaign.json') (ConvertTo-BenchmarkCanonicalJson @{
        schemaVersion = 'benchmark-campaign-pointer-v1'; campaignPath = "campaigns/$CampaignId.json"; sha256 = Get-BenchmarkDigest $Bytes
    })
    Write-BenchmarkCampaignReport $Record $OutputDirectory
    $Record
}

function Get-BenchmarkCampaignSelection {
    param([string]$Repository, [string]$Commit, [switch]$Descriptive)
    $Bytes = Get-BenchmarkGitFile $Repository $Commit 'benchmarks/efficiency/latest-campaign.json' -Optional
    if ($null -eq $Bytes) { return $null }
    $Pointer = ConvertFrom-BenchmarkJson $Bytes
    Assert-BenchmarkKeys $Pointer @('schemaVersion', 'campaignPath', 'sha256')
    if ($Pointer.schemaVersion -cne 'benchmark-campaign-pointer-v1' -or $Pointer.campaignPath -cnotmatch '^campaigns/([a-z0-9][a-z0-9-]{0,95})\.json$') { Stop-BenchmarkData 'campaign-pointer' }
    $Id = $Matches[1]
    Assert-BenchmarkHash $Pointer.sha256
    $RecordBytes = Get-BenchmarkGitFile $Repository $Commit ("benchmarks/efficiency/" + $Pointer.campaignPath)
    if ((Get-BenchmarkDigest $RecordBytes) -cne $Pointer.sha256) { Stop-BenchmarkData 'campaign-pointer-digest' }
    $Record = ConvertFrom-BenchmarkJson $RecordBytes
    Assert-BenchmarkCampaignBinding $Repository $(if ($Descriptive) { $Record.measuredRevision } else { $Commit }) $Record
    if ($Descriptive -and $null -eq (Invoke-BenchmarkGit $Repository @('merge-base', '--is-ancestor', $Record.measuredRevision, $Commit) -AllowFailure)) { Stop-BenchmarkData 'measured-revision-not-ancestor' 'stale-record' }
    if ($Record.campaignId -cne $Id) { Stop-BenchmarkData 'campaign-pointer-id' }
    $Record
}

function Write-BenchmarkCampaignReport {
    param([Collections.IDictionary]$Record, [string]$OutputDirectory)
    Assert-BenchmarkCampaign $Record
    function Format-CampaignNumber($Value) { if ($null -eq $Value) { 'unavailable' } else { ([decimal]$Value).ToString('0.#######', [Globalization.CultureInfo]::InvariantCulture) } }
    [decimal]$Known = 0; [decimal]$CompleteSubtotal = 0
    foreach ($Trial in $Record.trials) {
        $Known += [decimal]$Trial.accounting.knownCredits
        if ($Trial.accounting.complete) { $CompleteSubtotal += [decimal]$Trial.accounting.totalCredits }
    }
    $Complete = $Record.trials.Count -eq 3 -and @($Record.trials | Where-Object { -not $_.accounting.complete }).Count -eq 0
    $Report = [ordered]@{
        schemaVersion = 'benchmark-campaign-report-v1'; status = 'not-evaluable'; exitCode = 2
        reason = 'observational-campaign-not-comparable'; campaign = $Record
        summary = @{
            declaredSlots = 3; recordedSlots = $Record.trials.Count
            knownCredits = $Known; accountingComplete = $Complete
            totalCredits = $(if ($Complete) { $Known } else { $null })
            completeTrialCreditsSubtotal = $CompleteSubtotal
            qualitySamples = @($Record.trials | Where-Object { $null -ne $_.quality }).Count
            qualityMedian = $(if ($Record.trials.Count -eq 3 -and @($Record.trials | Where-Object { $null -eq $_.quality }).Count -eq 0) {
                Get-BenchmarkMedian @($Record.trials | ForEach-Object { ($_.quality.Values | Measure-Object -Sum).Sum })
            } else { $null })
        }
    }
    $Lines = @('# Latest benchmark campaign', '', '**Not evaluable for comparison (exit 2).** Observations are not an approved baseline.',
        '', "Measured revision: ``$($Record.measuredRevision)``.", "Source SHA-256: ``$($Record.sourceHash)``.",
        '', '| Trial | Quality /100 | Workflow credits | Judge credits | Known credits | Complete total credits | Full workflow | Unavailable |',
        '|---:|---:|---:|---:|---:|---:|---|---|')
    foreach ($Trial in $Record.trials) {
        $Score = if ($null -eq $Trial.quality) { $null } else { ($Trial.quality.Values | Measure-Object -Sum).Sum }
        $JudgeCredits = if ($null -eq $Trial.judge) { $null } else { $Trial.judge.credits }
        $Lines += "| $($Trial.slot) | $(Format-CampaignNumber $Score) | $(Format-CampaignNumber $Trial.workflow.credits) | $(Format-CampaignNumber $JudgeCredits) | $(Format-CampaignNumber $Trial.accounting.knownCredits) | $(Format-CampaignNumber $Trial.accounting.totalCredits) | $($Trial.outcomes.completed) | $($Trial.unavailable -join ', ') |"
    }
    $Lines += @('', "Known consumption: **$(Format-CampaignNumber $Known) credits**. Complete-trial subtotal: **$(Format-CampaignNumber $CompleteSubtotal)**.",
        "Whole three-trial consumption: **$(Format-CampaignNumber $Report.summary.totalCredits)**. Three-trial quality median: **$(Format-CampaignNumber $Report.summary.qualityMedian)**.",
        '', 'Known consumption counts each final cumulative workflow meter and each available independent judge once; it never sums stage snapshots. Missing judge evidence is unknown, not zero. Complete-trial subtotal excludes slots with incomplete accounting, not failed workflows.',
        '', 'This separate campaign archive cannot be selected by current.json, used in complete-series reducers or promoted. The strict complete-series schema is unchanged. The comparator exposes this campaign and returns non-evaluable; no regression, improvement or compatible-baseline claim is made.',
        '', 'Raw run/event/document SHA-256 bindings and exact measured protocol are retained in campaign JSON. Private prompts, documents, judge explanations and session identifiers are excluded. Hashes establish integrity, not authenticated execution.')
    $Lines += @('', '## Measured protocol', '', '| Field | Value |', '|---|---|')
    foreach ($Key in $Record.protocol.Keys | Sort-Object) { $Lines += "| $Key | $($Record.protocol[$Key]) |" }
    Write-BenchmarkFile (Join-Path $OutputDirectory 'campaign-report.json') (ConvertTo-BenchmarkCanonicalJson $Report)
    Write-BenchmarkFile (Join-Path $OutputDirectory 'campaign-report.md') (($Lines -join "`n") + "`n")
    $Badge = if ($Complete -and $null -ne $Report.summary.qualityMedian) { 'benchmark unavailable: observational campaign' } else { 'benchmark unavailable: incomplete observational campaign' }
    Write-BenchmarkFile (Join-Path $OutputDirectory 'campaign-badge.svg') "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"600`" height=`"28`" role=`"img`" aria-label=`"$Badge`"><title>$Badge</title><rect width=`"600`" height=`"28`" rx=`"4`" fill=`"#6b7280`"/><text x=`"300`" y=`"18`" text-anchor=`"middle`" fill=`"white`" font-family=`"Verdana,Arial,sans-serif`" font-size=`"12`">$Badge</text></svg>`n"
}

Export-ModuleMember -Function Export-BenchmarkCampaign, Assert-BenchmarkCampaign, Get-BenchmarkCampaignSelection, Write-BenchmarkCampaignReport, Export-BenchmarkSeries, Compare-BranchBenchmark, Write-BenchmarkReport, Write-BenchmarkSeriesReport, Assert-BenchmarkSeries, Assert-BenchmarkHistoricalSeries, Compare-BenchmarkSeries, ConvertTo-BenchmarkCanonicalJson, ConvertFrom-BenchmarkJson, Get-BenchmarkDigest, Get-BenchmarkSourceHash, Get-BenchmarkProtocol, Get-BenchmarkRawMetrics, Resolve-BenchmarkCommit, Get-BenchmarkSelection, Assert-BenchmarkHistory, Get-BenchmarkGitFile, Invoke-BenchmarkGit, Get-BenchmarkProtocolDifferences, Assert-BenchmarkRecordedIdentity, Get-BenchmarkExecutionIdentity, Get-BenchmarkSourceStatus, Assert-BenchmarkSourceReady
