#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Appends a validated Council, Intake Readiness, or Discovery Verdict.
.DESCRIPTION
    AI cost: none. This script validates the closed verdict payload, derives the
    deterministic council synthesis and gate fields, acquires the same per-root
    lock as Write-SquadHandoff.ps1, appends one schema-complete decisions.md
    entry atomically, reads it back, and returns its Decision Ref.

    Dispatch history, consumption, and state advancement remain the responsibility
    of Write-SquadHandoff.ps1. Run that writer first for the verdict turn, then run
    this script synchronously at the same squad root. A federation member uses this
    exact script with its members/<name> root; a federation meta-root is refused.

    Exit codes: 0 written and verified; 1 invalid/replayed payload, nothing written;
    2 unsupported root or secret-like content requiring the cold Scribe path,
    nothing written; 3 write/read-back failure with restore attempted; 8 lock timeout.
.PARAMETER SquadRoot
    A single-squad root or federation member root.
.PARAMETER PayloadPath
    Path to the verdict JSON payload.
.PARAMETER PayloadJson
    Verdict JSON supplied directly. Use exactly one of PayloadPath or PayloadJson.
.PARAMETER LockTimeoutSeconds
    Longest wait for another state writer at this root.
.PARAMETER Quiet
    Emit only the compact JSON receipt on stdout.
#>
[CmdletBinding(DefaultParameterSetName = 'Path')]
param(
    [Parameter(Mandatory)]
    [string]$SquadRoot,

    [Parameter(Mandatory, ParameterSetName = 'Path')]
    [string]$PayloadPath,

    [Parameter(Mandatory, ParameterSetName = 'Json')]
    [string]$PayloadJson,

    [ValidateRange(1, 3600)]
    [int]$LockTimeoutSeconds = 120,

    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture

$ControlPattern = '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u0085\u2028\u2029]'
$SecretPattern = '(?i)\b(password|passwd|pwd|secret|client[_-]?secret|api[_-]?key|access[_-]?key|access[_-]?token|auth[_-]?token|refresh[_-]?token|token|bearer|connection[_-]?string|accountkey|sharedaccesskey|sharedaccesssignature|private[_-]?key)\s*[=:]|\bauthorization\s*:|\bbearer\s+[A-Za-z0-9._~+/=-]{16,}|\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]+|\b(?:AKIA|ASIA)[0-9A-Z]{16}\b|\bxox[abprs]-[A-Za-z0-9-]{8,}|\bsig=|\bsv=\d{4}-|-----BEGIN [A-Z ]*PRIVATE KEY|\bgh[pousr]_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}|\bsk-[A-Za-z0-9]{20,}|DefaultEndpointsProtocol=|AccountKey='
$Problems = [Collections.Generic.List[string]]::new()
$NeedsScribe = [Collections.Generic.List[string]]::new()

function Stop-Verdict {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Terminates the script with a deterministic exit code and performs no mutation.')]
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("Write-SquadVerdict: $Message")
    exit $Code
}

function Get-CanonicalPath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $root = [IO.Path]::GetPathRoot($full)
    $current = $root
    foreach ($part in @($full.Substring($root.Length) -split '[\\/]' | Where-Object { $_ })) {
        $candidate = Join-Path $current $part
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { $current = $candidate; continue }
        $current = $item.FullName
        $target = $null
        try { $target = $item.ResolveLinkTarget($true) } catch { Write-Verbose "link resolution failed: $($_.Exception.Message)" }
        if ($null -ne $target) { $current = Get-CanonicalPath $target.FullName }
    }
    $current.TrimEnd('\', '/')
}

function Get-Kind {
    param($Node)
    if ($null -eq $Node) { return 'Null' }
    $Node.GetValueKind().ToString()
}

function Get-NodeString {
    param($Node)
    if ((Get-Kind $Node) -ne 'String') { return $null }
    $Node.GetValue[string]()
}

function Get-NodeInt {
    param($Node)
    if ((Get-Kind $Node) -ne 'Number') { return $null }
    $value = 0L
    if (-not [long]::TryParse($Node.ToJsonString(), [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) { return $null }
    $value
}

function Test-ObjectKeys {
    param($Node, [string[]]$Required, [string[]]$Optional = @(), [string]$Where)
    if ((Get-Kind $Node) -ne 'Object') { $Problems.Add("$Where must be a JSON object."); return $false }
    $present = @($Node | ForEach-Object { $_.Key })
    foreach ($key in $Required) {
        if ($key -notin $present) { $Problems.Add("$Where is missing '$key'.") }
    }
    foreach ($key in $present) {
        if ($key -notin ($Required + $Optional)) { $Problems.Add("$Where has unknown key '$key'; the key set is closed.") }
    }
    $true
}

function Get-LineField {
    param(
        $Node,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Where,
        [switch]$Optional,
        [switch]$AllowEmpty
    )
    $value = $Node[$Key]
    if ($null -eq $value) {
        if (-not $Optional) { $Problems.Add("$Where.$Key is required.") }
        return $null
    }
    $text = Get-NodeString $value
    if ($null -eq $text) { $Problems.Add("$Where.$Key must be a string."); return $null }
    $text = $text.Trim()
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($text)) { $Problems.Add("$Where.$Key must be a non-empty string."); return $null }
    if ($text -match '[\r\n]' -or $text -match $ControlPattern) { $Problems.Add("$Where.$Key must be a single line without control characters."); return $null }
    if ($text -match $SecretPattern) { $NeedsScribe.Add("$Where.$Key looks like it carries a secret.") }
    $text
}

function Get-LineArray {
    param(
        $Node,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Where,
        [switch]$Optional
    )
    $value = $Node[$Key]
    if ($null -eq $value) {
        if (-not $Optional) { $Problems.Add("$Where.$Key is required.") }
        return @()
    }
    if ((Get-Kind $value) -ne 'Array') { $Problems.Add("$Where.$Key must be an array of strings."); return @() }
    $items = [Collections.Generic.List[string]]::new()
    $index = 0
    foreach ($item in $value) {
        $text = Get-NodeString $item
        if ([string]::IsNullOrWhiteSpace($text) -or $text -match '[\r\n]' -or $text -match $ControlPattern) {
            $Problems.Add("$Where.$Key[$index] must be a non-empty single-line string.")
        }
        else {
            $text = $text.Trim()
            if ($text -match $SecretPattern) { $NeedsScribe.Add("$Where.$Key[$index] looks like it carries a secret.") }
            $items.Add($text)
        }
        $index++
    }
    @($items)
}

function Test-Unique {
    param([string[]]$Items, [string]$Where, [switch]$IgnoreCase)
    $comparer = if ($IgnoreCase) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
    $seen = [Collections.Generic.HashSet[string]]::new($comparer)
    foreach ($item in $Items) {
        if (-not $seen.Add($item)) { $Problems.Add("$Where contains duplicate '$item'.") }
    }
}

function ConvertTo-MarkdownCell {
    param([AllowEmptyString()][string]$Value)
    $Value.Replace('\', '\\').Replace('|', '\|')
}

function Join-CellItems {
    param([string[]]$Items)
    if ($Items.Count -eq 0) { return 'none' }
    ConvertTo-MarkdownCell ($Items -join '; ')
}

function Add-Bullets {
    param([Collections.Generic.List[string]]$Lines, [string[]]$Items)
    foreach ($item in $Items) { $Lines.Add("* $item") }
}

function Add-Attributed {
    param(
        [Collections.Generic.List[string]]$Target,
        [Collections.Generic.HashSet[string]]$Seen,
        [string]$Role,
        [string[]]$Items
    )
    foreach ($item in $Items) {
        $value = "($Role) $item"
        if ($Seen.Add($value)) { $Target.Add($value) }
    }
}

function Get-DecisionPath {
    param([string]$Root)
    $normalized = $Root.Replace('\', '/').TrimEnd('/')
    $marker = '/.copilot-tracking/'
    $index = $normalized.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase)
    if ($index -ge 0) { return $normalized.Substring($index + 1) + '/decisions.md' }
    'decisions.md'
}

function Get-HeadingAnchor {
    param([string]$Heading)
    (($Heading.ToLowerInvariant() -replace '[^\p{L}\p{Nd}_ -]', '') -replace ' +', '-')
}

function Write-AtomicText {
    param([string]$Path, [string]$Content, [bool]$Bom)
    $temporary = Join-Path (Split-Path -Parent $Path) (".$([IO.Path]::GetFileName($Path)).$([guid]::NewGuid().ToString('N')).tmp")
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Content)
        if ($Bom) { $bytes = [byte[]](@(0xEF, 0xBB, 0xBF) + $bytes) }
        [IO.File]::WriteAllBytes($temporary, $bytes)
        [IO.File]::Move($temporary, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Path') {
    $PayloadPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($PayloadPath)
    if (-not (Test-Path -LiteralPath $PayloadPath -PathType Leaf)) { Stop-Verdict 1 "missing $PayloadPath." }
    $PayloadJson = [IO.File]::ReadAllText($PayloadPath)
}
try { $payload = [Text.Json.Nodes.JsonNode]::Parse($PayloadJson) }
catch { Stop-Verdict 1 "payload is not valid JSON: $($_.Exception.Message)" }
if ((Get-Kind $payload) -ne 'Object') { Stop-Verdict 1 'payload must be a JSON object.' }

$SquadRoot = Get-CanonicalPath ($PSCmdlet.GetUnresolvedProviderPathFromPSPath($SquadRoot))
if (-not (Test-Path -LiteralPath $SquadRoot -PathType Container)) { Stop-Verdict 2 "missing squad root $SquadRoot." }
$decisionsPath = Join-Path $SquadRoot 'decisions.md'
foreach ($required in @('team.md', 'state.json', 'decisions.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SquadRoot $required) -PathType Leaf)) {
        Stop-Verdict 2 "missing $required under $SquadRoot; initialize or repair the squad before recording a verdict."
    }
}
if (Test-Path -LiteralPath (Join-Path $SquadRoot 'federation.md') -PathType Leaf) {
    Stop-Verdict 2 'federation meta-roots do not hold Council, Intake, or Discovery Verdicts; target the selected members/<name> squad root.'
}
if ((Get-Item -LiteralPath $decisionsPath).IsReadOnly) { Stop-Verdict 3 "$decisionsPath is read-only." }

$lockKey = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($SquadRoot.ToLowerInvariant()))).Substring(0, 16)
$lockPath = Join-Path ([IO.Path]::GetTempPath()) "hve-squad-handoff-$lockKey.lock"
$deadline = [DateTime]::UtcNow.AddSeconds($LockTimeoutSeconds)
$script:VerdictLock = $null
while ($null -eq $script:VerdictLock) {
    try { $script:VerdictLock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch [IO.IOException] {
        if ([DateTime]::UtcNow -gt $deadline) { Stop-Verdict 8 "another state writer has held $SquadRoot for more than $LockTimeoutSeconds s; nothing was written." }
        Start-Sleep -Milliseconds 200
    }
}

$kind = Get-LineField -Node $payload -Key 'kind' -Where 'payload'
$topicId = Get-LineField -Node $payload -Key 'topicId' -Where 'payload'
$topic = Get-LineField -Node $payload -Key 'topic' -Where 'payload'
if ($kind -notin @('council', 'intake', 'discovery')) { $Problems.Add("payload.kind must be council, intake, or discovery.") }
if ($topicId -and $topicId -cnotmatch '^[a-z0-9][a-z0-9-]*$') { $Problems.Add('payload.topicId must be lower-kebab-case.') }

$timestampNode = $payload['timestamp']
$timestamp = [DateTimeOffset]::UtcNow.ToString('o')
if ($null -ne $timestampNode) {
    $timestampText = Get-LineField -Node $payload -Key 'timestamp' -Where 'payload'
    $parsedTimestamp = [DateTimeOffset]::MinValue
    if ($timestampText -and -not [DateTimeOffset]::TryParse($timestampText, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsedTimestamp)) {
        $Problems.Add('payload.timestamp must be ISO 8601.')
    }
    elseif ($timestampText) { $timestamp = $parsedTimestamp.ToUniversalTime().ToString('o') }
}

$lines = [Collections.Generic.List[string]]::new()
$label = ''
$heading = ''

switch ($kind) {
    'council' {
        $null = Test-ObjectKeys -Node $payload -Required @('kind', 'topicId', 'topic', 'proposalRef', 'membersDispatched', 'membersNotProposed', 'findings') -Optional @('timestamp') -Where 'payload'
        $proposalRef = Get-LineField -Node $payload -Key 'proposalRef' -Where 'payload'
        $members = @(Get-LineArray -Node $payload -Key 'membersDispatched' -Where 'payload')
        Test-Unique -Items $members -Where 'payload.membersDispatched'
        foreach ($role in $members) {
            if ($role -cnotmatch '^[a-z][a-z0-9-]*$') { $Problems.Add("Council member '$role' must be a lower-kebab-case role id.") }
        }

        $omitted = [Collections.Generic.List[object]]::new()
        if ((Get-Kind $payload['membersNotProposed']) -ne 'Array') { $Problems.Add('payload.membersNotProposed must be an array.') }
        else {
            $index = 0
            foreach ($item in $payload['membersNotProposed']) {
                $where = "payload.membersNotProposed[$index]"
                if (Test-ObjectKeys -Node $item -Required @('role', 'reason') -Where $where) {
                    $role = Get-LineField -Node $item -Key 'role' -Where $where
                    $reason = Get-LineField -Node $item -Key 'reason' -Where $where
                    if ($role -and $role -cnotmatch '^[a-z][a-z0-9-]*$') { $Problems.Add("$where.role must be lower-kebab-case.") }
                    if ($role -and $reason) { $omitted.Add([pscustomobject]@{ Role = $role; Reason = $reason }) }
                }
                $index++
            }
        }
        Test-Unique -Items @($omitted | ForEach-Object Role) -Where 'payload.membersNotProposed roles'
        foreach ($role in @($omitted | ForEach-Object Role)) {
            if ($role -cin $members) { $Problems.Add("Council role '$role' cannot be both dispatched and not proposed.") }
        }

        $findings = [Collections.Generic.List[object]]::new()
        if ((Get-Kind $payload['findings']) -ne 'Array') { $Problems.Add('payload.findings must be a non-empty array.') }
        else {
            $index = 0
            foreach ($item in $payload['findings']) {
                $where = "payload.findings[$index]"
                if (Test-ObjectKeys -Node $item -Required @('role', 'verdict', 'risk', 'blockingIssues', 'conditions', 'suggestedFollowUps') -Where $where) {
                    $role = Get-LineField -Node $item -Key 'role' -Where $where
                    $findingVerdict = Get-LineField -Node $item -Key 'verdict' -Where $where
                    $risk = Get-LineField -Node $item -Key 'risk' -Where $where
                    if ($risk -match '^Risk:\s*(Low|Medium|High)$') { $risk = $Matches[1] }
                    $blocking = @(Get-LineArray -Node $item -Key 'blockingIssues' -Where $where)
                    $conditions = @(Get-LineArray -Node $item -Key 'conditions' -Where $where)
                    $followUps = @(Get-LineArray -Node $item -Key 'suggestedFollowUps' -Where $where)
                    if ($findingVerdict -notin @('Approve', 'Conditional', 'Concern', 'Block')) { $Problems.Add("$where.verdict is invalid.") }
                    if ($risk -notin @('Low', 'Medium', 'High')) { $Problems.Add("$where.risk must be Low, Medium, or High.") }
                    if ($role) {
                        $findings.Add([pscustomobject]@{
                                Role = $role; Verdict = $findingVerdict; Risk = $risk
                                Blocking = @($blocking); Conditions = @($conditions); FollowUps = @($followUps)
                            })
                    }
                }
                $index++
            }
        }
        if ($findings.Count -eq 0) { $Problems.Add('payload.findings must contain at least one council finding.') }
        Test-Unique -Items @($findings | ForEach-Object Role) -Where 'payload.findings roles'
        if (($members -join "`n") -cne ((@($findings | ForEach-Object Role)) -join "`n")) {
            $Problems.Add('payload.membersDispatched must match payload.findings roles in the same order.')
        }

        $blockingAll = [Collections.Generic.List[string]]::new()
        $conditionsAll = [Collections.Generic.List[string]]::new()
        $followUpsAll = [Collections.Generic.List[string]]::new()
        $blockingSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $conditionsSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $followUpsSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($finding in $findings) {
            Add-Attributed -Target $blockingAll -Seen $blockingSeen -Role $finding.Role -Items @($finding.Blocking)
            Add-Attributed -Target $conditionsAll -Seen $conditionsSeen -Role $finding.Role -Items @($finding.Conditions)
            Add-Attributed -Target $followUpsAll -Seen $followUpsSeen -Role $finding.Role -Items @($finding.FollowUps)
        }
        $stop = @($findings | Where-Object { $_.Verdict -eq 'Block' -or $_.Risk -eq 'High' -or @($_.Blocking).Count -gt 0 }).Count -gt 0
        $conditional = @($findings | Where-Object { $_.Verdict -eq 'Conditional' -or @($_.Conditions).Count -gt 0 }).Count -gt 0
        $label = if ($stop) { 'Stop' } elseif ($conditional) { 'Go-With-Conditions' } else { 'Go' }
        $heading = "Council Verdict $timestamp $topicId"
        $lines.Add("## $heading"); $lines.Add('')
        $lines.Add("* Topic: $topic")
        $lines.Add("* Proposal Ref: $proposalRef")
        $lines.Add("* Council Members Dispatched: $($members -join ', ')")
        $omittedText = if ($omitted.Count) { @($omitted | ForEach-Object { "$($_.Role) — $($_.Reason)" }) -join '; ' } else { 'none' }
        $lines.Add("* Council Members Not Proposed: $omittedText")
        $lines.Add("* Verdict: $label")
        $lines.Add(''); $lines.Add('### Findings by Role'); $lines.Add('')
        $lines.Add('| Role | Verdict | Risk | Blocking Issues | Conditions | Suggested Follow-ups |')
        $lines.Add('|------|---------|------|-----------------|------------|----------------------|')
        foreach ($finding in $findings) {
            $lines.Add("| $(ConvertTo-MarkdownCell $finding.Role) | $(ConvertTo-MarkdownCell $finding.Verdict) | Risk: $($finding.Risk) | $(Join-CellItems @($finding.Blocking)) | $(Join-CellItems @($finding.Conditions)) | $(Join-CellItems @($finding.FollowUps)) |")
        }
        $lines.Add(''); $lines.Add('### Synthesis'); $lines.Add('')
        $lines.Add("* Blocking Issues: $(if ($blockingAll.Count) { $blockingAll -join '; ' } else { 'none' })")
        $lines.Add("* Conditions: $(if ($conditionsAll.Count) { $conditionsAll -join '; ' } else { 'none' })")
        $lines.Add("* Suggested Follow-ups: $(if ($followUpsAll.Count) { $followUpsAll -join '; ' } else { 'none' })")
        $lines.Add(''); $lines.Add('### Implementation Gate'); $lines.Add('')
        $lines.Add("* Permits Implementation Dispatch: $(if ($label -eq 'Stop') { 'no (Stop)' } else { "yes ($label)" })")
        $lines.Add("* Conditions Outstanding: $($conditionsAll.Count)")
    }
    'intake' {
        $null = Test-ObjectKeys -Node $payload -Required @('kind', 'topicId', 'topic', 'inputsReviewed', 'validatorDispatched', 'verdict', 'remediationCycles', 'findings', 'clarifyingQuestions', 'recordedAssumptions') -Optional @('timestamp') -Where 'payload'
        $inputs = @(Get-LineArray -Node $payload -Key 'inputsReviewed' -Where 'payload')
        if ($inputs.Count -eq 0) { $Problems.Add('payload.inputsReviewed must contain at least one input.') }
        Test-Unique -Items $inputs -Where 'payload.inputsReviewed'
        $validator = Get-LineField -Node $payload -Key 'validatorDispatched' -Where 'payload'
        $label = Get-LineField -Node $payload -Key 'verdict' -Where 'payload'
        if ($label -notin @('Ready', 'Ready-With-Gaps', 'Not-Ready')) { $Problems.Add('payload.verdict must be Ready, Ready-With-Gaps, or Not-Ready.') }
        $cycles = Get-NodeInt $payload['remediationCycles']
        if ($null -eq $cycles -or $cycles -lt 0 -or $cycles -gt 2) { $Problems.Add('payload.remediationCycles must be 0, 1, or 2.') }
        $questions = @(Get-LineArray -Node $payload -Key 'clarifyingQuestions' -Where 'payload')
        $assumptions = @(Get-LineArray -Node $payload -Key 'recordedAssumptions' -Where 'payload')

        $dimensions = @('Completeness', 'Clarity', 'Testability', 'Consistency', 'Scope Boundaries')
        $byDimension = @{}
        if ((Get-Kind $payload['findings']) -ne 'Array') { $Problems.Add('payload.findings must be an array.') }
        else {
            $index = 0
            foreach ($item in $payload['findings']) {
                $where = "payload.findings[$index]"
                if (Test-ObjectKeys -Node $item -Required @('dimension', 'result', 'blockingGaps', 'nonBlockingGaps') -Where $where) {
                    $dimension = Get-LineField -Node $item -Key 'dimension' -Where $where
                    $result = Get-LineField -Node $item -Key 'result' -Where $where
                    $blocking = @(Get-LineArray -Node $item -Key 'blockingGaps' -Where $where)
                    $nonBlocking = @(Get-LineArray -Node $item -Key 'nonBlockingGaps' -Where $where)
                    if ($dimension -notin $dimensions) { $Problems.Add("$where.dimension is invalid.") }
                    elseif ($byDimension.ContainsKey($dimension)) { $Problems.Add("payload.findings repeats '$dimension'.") }
                    else { $byDimension[$dimension] = [pscustomobject]@{ Result = $result; Blocking = @($blocking); NonBlocking = @($nonBlocking) } }
                    if ($result -notin @('pass', 'fail')) { $Problems.Add("$where.result must be pass or fail.") }
                }
                $index++
            }
        }
        foreach ($dimension in $dimensions) {
            if (-not $byDimension.ContainsKey($dimension)) { $Problems.Add("payload.findings is missing '$dimension'.") }
        }
        $blockingCount = 0
        $nonBlockingCount = 0
        foreach ($finding in $byDimension.Values) {
            $blockingCount += @($finding.Blocking).Count
            $nonBlockingCount += @($finding.NonBlocking).Count
        }
        if ($label -eq 'Not-Ready' -and $blockingCount -eq 0) { $Problems.Add('Not-Ready requires at least one blocking gap.') }
        if ($label -ne 'Not-Ready' -and $blockingCount -gt 0) { $Problems.Add("$label cannot carry blocking gaps.") }
        if ($label -eq 'Ready-With-Gaps' -and $nonBlockingCount -eq 0) { $Problems.Add('Ready-With-Gaps requires at least one non-blocking gap.') }
        if ($label -eq 'Ready' -and $nonBlockingCount -gt 0) { $Problems.Add('Ready cannot carry non-blocking gaps; use Ready-With-Gaps.') }
        if ($label -eq 'Ready' -and $questions.Count -gt 0) { $Problems.Add('Ready must have no clarifying questions.') }

        $heading = "Intake Readiness Verdict $timestamp $topicId"
        $lines.Add("## $heading"); $lines.Add('')
        $lines.Add("* Topic: $topic")
        $lines.Add("* Inputs Reviewed: $($inputs -join ', ')")
        $lines.Add("* Validator Dispatched: $validator")
        $lines.Add("* Verdict: $label")
        $lines.Add("* Remediation Cycles: $cycles")
        $lines.Add(''); $lines.Add('### Findings'); $lines.Add('')
        $lines.Add('| Dimension | Result | Blocking Gaps | Non-Blocking Gaps |')
        $lines.Add('|-----------|--------|---------------|-------------------|')
        foreach ($dimension in $dimensions) {
            $finding = $byDimension[$dimension]
            $lines.Add("| $dimension | $($finding.Result) | $(Join-CellItems @($finding.Blocking)) | $(Join-CellItems @($finding.NonBlocking)) |")
        }
        $lines.Add(''); $lines.Add('### Clarifying Questions'); $lines.Add('')
        Add-Bullets -Lines $lines -Items $questions
        $lines.Add(''); $lines.Add('### Recorded Assumptions'); $lines.Add('')
        Add-Bullets -Lines $lines -Items $assumptions
        $lines.Add(''); $lines.Add('### Intake Gate'); $lines.Add('')
        $lines.Add("* Permits Downstream Dispatch: $(if ($label -eq 'Not-Ready') { 'no (Not-Ready)' } else { "yes ($label)" })")
        $lines.Add("* Blocking Gaps Outstanding: $blockingCount")
    }
    'discovery' {
        $null = Test-ObjectKeys -Node $payload -Required @('kind', 'topicId', 'topic', 'optIn', 'depth', 'rolesDispatched', 'brief', 'handoff', 'framing', 'options', 'objections', 'riskiestAssumption', 'openQuestions') -Optional @('timestamp') -Where 'payload'
        $optIn = Get-LineField -Node $payload -Key 'optIn' -Where 'payload'
        $depth = Get-LineField -Node $payload -Key 'depth' -Where 'payload'
        if ($optIn -notin @('offer-accepted', 'explicit-input', 'offer-declined')) { $Problems.Add('payload.optIn is invalid.') }
        if ($depth -notin @('quick', 'standard', 'deep', 'skip')) { $Problems.Add('payload.depth is invalid.') }
        $roles = @(Get-LineArray -Node $payload -Key 'rolesDispatched' -Where 'payload')
        Test-Unique -Items $roles -Where 'payload.rolesDispatched'
        $brief = Get-LineField -Node $payload -Key 'brief' -Where 'payload'
        $handoff = Get-LineField -Node $payload -Key 'handoff' -Where 'payload'
        $problem = $null
        $success = $null
        if (Test-ObjectKeys -Node $payload['framing'] -Required @('problem', 'successMeasure') -Where 'payload.framing') {
            $problem = Get-LineField -Node $payload['framing'] -Key 'problem' -Where 'payload.framing' -AllowEmpty
            $success = Get-LineField -Node $payload['framing'] -Key 'successMeasure' -Where 'payload.framing' -AllowEmpty
        }
        $options = [Collections.Generic.List[object]]::new()
        if ((Get-Kind $payload['options']) -ne 'Array') { $Problems.Add('payload.options must be an array.') }
        else {
            $index = 0
            foreach ($item in $payload['options']) {
                $where = "payload.options[$index]"
                if (Test-ObjectKeys -Node $item -Required @('option', 'outcome', 'reason') -Where $where) {
                    $option = Get-LineField -Node $item -Key 'option' -Where $where
                    $outcome = Get-LineField -Node $item -Key 'outcome' -Where $where
                    $reason = Get-LineField -Node $item -Key 'reason' -Where $where
                    if ($outcome -notin @('chosen', 'discarded')) { $Problems.Add("$where.outcome must be chosen or discarded.") }
                    if ($option -and $reason) { $options.Add([pscustomobject]@{ Option = $option; Outcome = $outcome; Reason = $reason }) }
                }
                $index++
            }
        }
        $objections = @(Get-LineArray -Node $payload -Key 'objections' -Where 'payload')
        $riskiest = Get-LineField -Node $payload -Key 'riskiestAssumption' -Where 'payload' -AllowEmpty
        $questions = @(Get-LineArray -Node $payload -Key 'openQuestions' -Where 'payload')
        $abandoned = $handoff -eq 'abandoned'
        if ($depth -eq 'skip') {
            if ($roles.Count -gt 0 -or $brief -ne 'none' -or $problem -or $success -or $options.Count -gt 0 -or $objections.Count -gt 0 -or $riskiest -or $questions.Count -gt 0) {
                $Problems.Add('Depth skip requires no roles, Brief none, and empty body sections.')
            }
            if ($optIn -notin @('offer-declined', 'explicit-input')) { $Problems.Add('Depth skip requires optIn offer-declined or explicit-input.') }
        }
        elseif (-not $abandoned) {
            if ($roles.Count -eq 0) { $Problems.Add('A non-skip Discovery Verdict requires at least one dispatched role.') }
            if ($brief -eq 'none') { $Problems.Add('A non-skip Discovery Verdict requires a brief path.') }
            if (-not $problem -or -not $success) { $Problems.Add('A non-skip Discovery Verdict requires both framing fields.') }
            if ($options.Count -eq 0 -or @($options | Where-Object Outcome -eq 'chosen').Count -eq 0) { $Problems.Add('A non-skip Discovery Verdict requires at least one option and one chosen direction.') }
        }
        if ($depth -ne 'deep' -and ($objections.Count -gt 0 -or $riskiest)) { $Problems.Add('Objections and riskiestAssumption are populated only for depth deep.') }

        $label = $depth
        $heading = "Discovery Verdict $timestamp $topicId"
        $lines.Add("## $heading"); $lines.Add('')
        $lines.Add("* Topic: $topic")
        $lines.Add("* Opt-In: $optIn")
        $lines.Add("* Depth: $depth")
        $lines.Add("* Roles Dispatched: $(if ($roles.Count) { $roles -join ', ' } else { 'none' })")
        $lines.Add("* Brief: $brief")
        $lines.Add("* Handoff: $handoff")
        $lines.Add(''); $lines.Add('### Framing'); $lines.Add('')
        $lines.Add("* Problem: $problem")
        $lines.Add("* Success Measure: $success")
        $lines.Add(''); $lines.Add('### Options Considered'); $lines.Add('')
        $lines.Add('| Option | Outcome | Reason |')
        $lines.Add('|--------|---------|--------|')
        foreach ($option in $options) {
            $lines.Add("| $(ConvertTo-MarkdownCell $option.Option) | $($option.Outcome) | $(ConvertTo-MarkdownCell $option.Reason) |")
        }
        $lines.Add(''); $lines.Add('### Objections'); $lines.Add('')
        Add-Bullets -Lines $lines -Items $objections
        $lines.Add(''); $lines.Add('### Riskiest Assumption'); $lines.Add('')
        if ($riskiest) { $lines.Add("* $riskiest") }
        $lines.Add(''); $lines.Add('### Open Questions'); $lines.Add('')
        Add-Bullets -Lines $lines -Items $questions
        $lines.Add(''); $lines.Add('### Discovery Gate')
    }
}

if ($Problems.Count -gt 0) { Stop-Verdict 1 ("invalid payload: " + ($Problems -join ' ')) }
if ($NeedsScribe.Count -gt 0) { Stop-Verdict 2 (($NeedsScribe | Select-Object -Unique) -join ' ') }

$payloadTime = [DateTimeOffset]::Parse($timestamp, [Globalization.CultureInfo]::InvariantCulture)
$originalBytes = [IO.File]::ReadAllBytes($decisionsPath)
$hasBom = $originalBytes.Length -ge 3 -and $originalBytes[0] -eq 0xEF -and $originalBytes[1] -eq 0xBB -and $originalBytes[2] -eq 0xBF
$existing = [Text.UTF8Encoding]::new($false).GetString($originalBytes).TrimStart([char]0xFEFF)
$lastTimestamp = [DateTimeOffset]::MinValue
foreach ($match in [regex]::Matches($existing, '(?m)^## [^\r\n]*?(?<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))')) {
    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($match.Groups['timestamp'].Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsed) -and $parsed -gt $lastTimestamp) {
        $lastTimestamp = $parsed
    }
}
if ($lastTimestamp -ne [DateTimeOffset]::MinValue -and $payloadTime -lt $lastTimestamp) {
    Stop-Verdict 1 "payload.timestamp $timestamp precedes the latest decisions.md verdict/decision timestamp $($lastTimestamp.ToString('o')); entries stay chronological."
}
if ([regex]::IsMatch($existing, '(?m)^## ' + [regex]::Escape($heading) + '[ \t]*\r?$')) {
    Stop-Verdict 1 "decisions.md already holds '## $heading'; a replayed payload writes nothing."
}

$newline = if ($existing.Contains("`r`n")) { "`r`n" } else { "`n" }
$entry = ($lines -join "`n").Replace("`n", $newline)
$separator = if (-not $existing) { '' } elseif ($existing.EndsWith("$newline$newline")) { '' } elseif ($existing.EndsWith($newline)) { $newline } else { "$newline$newline" }
$newText = $existing + $separator + $entry + $newline
if ([Convert]::ToBase64String($originalBytes) -cne [Convert]::ToBase64String([IO.File]::ReadAllBytes($decisionsPath))) {
    Stop-Verdict 3 'collision: decisions.md changed while the verdict was being prepared; nothing was written.'
}
try {
    Write-AtomicText -Path $decisionsPath -Content $newText -Bom $hasBom
    $after = [Text.UTF8Encoding]::new($false).GetString([IO.File]::ReadAllBytes($decisionsPath)).TrimStart([char]0xFEFF)
    if (-not [regex]::IsMatch($after, '(?m)^## ' + [regex]::Escape($heading) + '[ \t]*\r?$')) {
        throw 'verdict heading read-back failed.'
    }
}
catch {
    $detail = $_.Exception.Message
    try { [IO.File]::WriteAllBytes($decisionsPath, $originalBytes); $detail += ' decisions.md restored.' }
    catch { $detail += " decisions.md could not be restored: $($_.Exception.Message)" }
    Stop-Verdict 3 "write failed: $detail"
}

$decisionPath = Get-DecisionPath $SquadRoot
$decisionRef = "$decisionPath#$(Get-HeadingAnchor $heading)"
$receipt = [ordered]@{
    status = 'written'
    kind = $kind
    label = $label
    topicId = $topicId
    path = $decisionPath
    decisionRef = $decisionRef
    timestamp = $timestamp
}
if (-not $Quiet) { Write-Output "WROTE $decisionPath (+1 $kind verdict)" }
$receipt | ConvertTo-Json -Compress
exit 0
