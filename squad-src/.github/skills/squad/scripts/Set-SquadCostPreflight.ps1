#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Performs the squad's one coordinator-owned state write, the Cost Preflight transaction,
    deterministically, so the coordinator needs no file-editing tool.
.DESCRIPTION
    The transaction defined by `references/gates-and-modes.md` (Cost Preflight Procedure,
    step 3): append the Cost Preflight decision entry to `decisions.md`, compare-and-swap
    only `currentRun.costPreflight` in `state.json`, apply the exact legacy schema bump
    when the state predates the object (single squad `1.3` to `1.4`, federation root `1.2`
    to `1.3`), and read both files back. The script computes nothing: the coordinator
    supplies the finished object and decision text from the procedure.

    Validation runs before any write and a rejection leaves both files untouched:
    the object must carry exactly the closed `costPreflight` key set with valid types and
    enum values; the decision text must be a `## Cost Preflight <timestamp> <run-id>
    <round-id>` entry whose ids and `Decision:` line match the object; and `state.json`
    `updated` must equal -ExpectedUpdated (the value the coordinator read). `updated` is
    not changed by this transaction. Every other `state.json` value is preserved;
    the file is re-serialized with two-space indentation and values are not altered.

    A decision of `not-requested` appends nothing to `decisions.md` (the entry shape has
    no `not-requested` form) and -DecisionText must be omitted. When `state.json` already
    holds that exact object at the current schema version, nothing is written.

    Both files are replaced through a temp file and move. `decisions.md` is written first
    so admission evidence never trails the state that cites it; if the `state.json` write
    then fails, `decisions.md` is restored to its original bytes. Read-back verifies the
    appended entry occurs exactly once and the parsed state equals the intended state.

    Exit codes: 0 written or already current; 1 validation or usage error (no write);
    2 `updated` collision (no write); 3 write or read-back failure (original content
    restored where possible). On any non-zero exit the coordinator dispatches nothing.
.PARAMETER SquadRoot
    A squad root: `.copilot-tracking/squad/` or `.copilot-tracking/squad/members/<name>/`
    (or the federation root). Both `state.json` and `decisions.md` must exist.
.PARAMETER ExpectedUpdated
    The `updated` value the coordinator read from `state.json` before building the round.
.PARAMETER PreflightJson
    The complete `currentRun.costPreflight` object as a JSON string.
.PARAMETER PreflightPath
    Path to a file holding that JSON object, instead of -PreflightJson.
.PARAMETER DecisionText
    The Cost Preflight decision entry (markdown) to append to `decisions.md`. Required for
    every decision except `not-requested`.
.PARAMETER DecisionPath
    Path to a file holding that entry, instead of -DecisionText.
.EXAMPLE
    ./Set-SquadCostPreflight.ps1 -SquadRoot .copilot-tracking/squad -ExpectedUpdated '2026-10-03T19:00:00Z' -PreflightJson $json -DecisionText $entry
.EXAMPLE
    ./Set-SquadCostPreflight.ps1 -SquadRoot .copilot-tracking/squad -ExpectedUpdated '2026-10-03T19:00:00Z' -PreflightJson $notRequestedJson
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SquadRoot,

    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$ExpectedUpdated,

    [string]$PreflightJson,

    [string]$PreflightPath,

    [string]$DecisionText,

    [string]$DecisionPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

$PreflightKeys = @(
    'runId', 'roundId', 'ceilingUsd', 'evaluatedSpendUsd', 'remainingUsd', 'plannedDispatches',
    'projectedCostUsd', 'reserveMultiplier', 'admissionCostUsd', 'confidence', 'basis', 'decision', 'reason'
)
$StringKeys = @('runId', 'roundId', 'confidence', 'basis', 'decision', 'reason')
$NumberKeys = @('evaluatedSpendUsd', 'plannedDispatches', 'projectedCostUsd', 'reserveMultiplier', 'admissionCostUsd')
$Decisions = @('not-requested', 'within-ceiling', 'over-ceiling', 'approved-over-ceiling', 'cannot-confirm')
$Confidences = @('not-applicable', 'low', 'medium')
$Bases = @('not-requested', 'estimated', 'calibrated')

function Stop-Preflight {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("Set-SquadCostPreflight: $Message")
    exit $Code
}

function ConvertTo-Lf {
    param([AllowEmptyString()][string]$Text)
    return ($Text -replace "`r`n", "`n" -replace "`r", "`n")
}

function Get-JsonNumber {
    param($Node)
    $result = 0.0
    if ($null -eq $Node -or $Node.GetValueKind() -ne [System.Text.Json.JsonValueKind]::Number) { return $null }
    if (-not [double]::TryParse($Node.ToJsonString(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$result)) { return $null }
    return $result
}

function Get-JsonString {
    param($Node)
    if ($null -eq $Node -or $Node.GetValueKind() -ne [System.Text.Json.JsonValueKind]::String) { return $null }
    return $Node.GetValue[string]()
}

function Test-PreflightObject {
    <#
    .SYNOPSIS
        Returns the list of problems with a candidate costPreflight object (empty when valid).
    #>
    param($Node)

    $problems = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Node -or $Node.GetValueKind() -ne [System.Text.Json.JsonValueKind]::Object) {
        $problems.Add('costPreflight must be a JSON object.')
        return $problems
    }

    $present = @($Node | ForEach-Object { $_.Key })
    foreach ($key in $PreflightKeys) { if ($key -notin $present) { $problems.Add("missing key '$key'.") } }
    foreach ($key in $present) { if ($key -notin $PreflightKeys) { $problems.Add("unknown key '$key'; the key set is closed.") } }
    if ($problems.Count -gt 0) { return $problems }

    foreach ($key in $StringKeys) {
        if ($null -eq (Get-JsonString $Node[$key])) { $problems.Add("'$key' must be a string.") }
    }
    foreach ($key in $NumberKeys) {
        $n = Get-JsonNumber $Node[$key]
        if ($null -eq $n -or [double]::IsNaN($n) -or [double]::IsInfinity($n)) { $problems.Add("'$key' must be a finite number.") }
        elseif ($n -lt 0) { $problems.Add("'$key' must not be negative.") }
    }
    if ((Get-JsonNumber $Node['reserveMultiplier']) -ne 3.0) { $problems.Add("'reserveMultiplier' must be 3.0.") }
    foreach ($key in @('ceilingUsd', 'remainingUsd')) {
        $value = $Node[$key]
        if ($null -ne $value -and $null -eq (Get-JsonNumber $value)) { $problems.Add("'$key' must be a number or null.") }
    }
    if ($problems.Count -gt 0) { return $problems }

    $decision = Get-JsonString $Node['decision']
    if ($decision -notin $Decisions) { $problems.Add("decision '$decision' is not one of: $($Decisions -join ', ').") }
    if ((Get-JsonString $Node['confidence']) -notin $Confidences) { $problems.Add("confidence must be one of: $($Confidences -join ', ').") }
    if ((Get-JsonString $Node['basis']) -notin $Bases) { $problems.Add("basis must be one of: $($Bases -join ', ').") }

    $ceiling = Get-JsonNumber $Node['ceilingUsd']
    if ($decision -eq 'not-requested') {
        if ($null -ne $ceiling) { $problems.Add('not-requested requires ceilingUsd null.') }
        if ((Get-JsonString $Node['confidence']) -ne 'not-applicable') { $problems.Add("not-requested requires confidence 'not-applicable'.") }
        if ((Get-JsonString $Node['basis']) -ne 'not-requested') { $problems.Add("not-requested requires basis 'not-requested'.") }
    }
    elseif ($decision -in $Decisions) {
        if ($null -eq $ceiling -or $ceiling -le 0) { $problems.Add("$decision requires a finite positive ceilingUsd.") }
        if ((Get-JsonString $Node['confidence']) -notin @('low', 'medium')) { $problems.Add("$decision requires confidence 'low' or 'medium'.") }
        if ((Get-JsonString $Node['basis']) -eq 'not-requested') { $problems.Add("$decision requires basis 'estimated' or 'calibrated'.") }
        if ((Get-JsonString $Node['runId']).Length -eq 0 -or (Get-JsonString $Node['roundId']).Length -eq 0) { $problems.Add("$decision requires non-empty runId and roundId.") }
    }
    return $problems
}

function Write-FileAtomic {
    param([string]$Path, [string]$Content)
    $tmp = Join-Path (Split-Path -Path $Path -Parent) (".$([System.IO.Path]::GetFileName($Path)).$([guid]::NewGuid().ToString('N')).tmp")
    try {
        [System.IO.File]::WriteAllText($tmp, $Content, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Move($tmp, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

$SquadRoot = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($SquadRoot)
$statePath = Join-Path $SquadRoot 'state.json'
$decisionsPath = Join-Path $SquadRoot 'decisions.md'

# --- Inputs ---------------------------------------------------------------------------
if ($PSBoundParameters.ContainsKey('PreflightJson') -eq $PSBoundParameters.ContainsKey('PreflightPath')) {
    Stop-Preflight 1 'supply exactly one of -PreflightJson or -PreflightPath.'
}
if ($PSBoundParameters.ContainsKey('DecisionText') -and $PSBoundParameters.ContainsKey('DecisionPath')) {
    Stop-Preflight 1 'supply at most one of -DecisionText or -DecisionPath.'
}
foreach ($path in @($statePath, $decisionsPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-Preflight 1 "missing $path." }
}

if ($PSBoundParameters.ContainsKey('PreflightPath')) {
    $PreflightPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($PreflightPath)
    if (-not (Test-Path -LiteralPath $PreflightPath -PathType Leaf)) { Stop-Preflight 1 "missing $PreflightPath." }
    $PreflightJson = [System.IO.File]::ReadAllText($PreflightPath)
}
if ($PSBoundParameters.ContainsKey('DecisionPath')) {
    $DecisionPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DecisionPath)
    if (-not (Test-Path -LiteralPath $DecisionPath -PathType Leaf)) { Stop-Preflight 1 "missing $DecisionPath." }
    $DecisionText = [System.IO.File]::ReadAllText($DecisionPath)
}
$hasDecisionText = -not [string]::IsNullOrWhiteSpace($DecisionText)

try { $newPreflight = [System.Text.Json.Nodes.JsonNode]::Parse($PreflightJson) }
catch { Stop-Preflight 1 "costPreflight is not valid JSON: $($_.Exception.Message)" }

$problems = @(Test-PreflightObject $newPreflight)
if ($problems.Count -gt 0) { Stop-Preflight 1 "invalid costPreflight object: $($problems -join ' ')" }

$decision = Get-JsonString $newPreflight['decision']
$runId = Get-JsonString $newPreflight['runId']
$roundId = Get-JsonString $newPreflight['roundId']

$entryText = $null
if ($decision -eq 'not-requested') {
    if ($hasDecisionText) { Stop-Preflight 1 'a not-requested decision appends no decisions.md entry; omit -DecisionText.' }
}
else {
    if (-not $hasDecisionText) { Stop-Preflight 1 "decision '$decision' requires -DecisionText." }
    $entryText = (ConvertTo-Lf $DecisionText).Trim("`n")
    $heading = ($entryText -split "`n")[0]
    $headingPattern = '^## Cost Preflight \S+ ' + [regex]::Escape($runId) + ' ' + [regex]::Escape($roundId) + '$'
    if ($heading -notmatch $headingPattern) { Stop-Preflight 1 "decision heading must be '## Cost Preflight <timestamp> $runId $roundId'; got '$heading'." }
    if ($entryText -notmatch ('(?m)^\* Decision: ' + [regex]::Escape($decision) + '\s*$')) { Stop-Preflight 1 "decision text must carry '* Decision: $decision'." }
    if (([regex]::Matches($entryText, '(?m)^## ')).Count -ne 1) { Stop-Preflight 1 'decision text must hold exactly one ## heading.' }
    if (([regex]::Matches($entryText, '(?m)^\* Decision:')).Count -ne 1) { Stop-Preflight 1 'decision text must hold exactly one * Decision: line.' }
    $headingLine = '(?m)^' + [regex]::Escape($heading) + '\r?$'
}

# --- Read and validate current state ----------------------------------------------------
$stateBytes = [System.IO.File]::ReadAllBytes($statePath)
$stateText = [System.Text.UTF8Encoding]::new($false).GetString($stateBytes).TrimStart([char]0xFEFF)
$decisionsText = [System.IO.File]::ReadAllText($decisionsPath)

try { $root = [System.Text.Json.Nodes.JsonNode]::Parse($stateText) }
catch { Stop-Preflight 1 "state.json is not valid JSON: $($_.Exception.Message)" }
if ($root.GetValueKind() -ne [System.Text.Json.JsonValueKind]::Object -or -not $root.AsObject().ContainsKey('updated') -or -not $root.AsObject().ContainsKey('schemaVersion')) {
    Stop-Preflight 1 'state.json lacks the squad status shape (schemaVersion, updated).'
}

$currentUpdated = Get-JsonString $root['updated']
if ($null -eq $currentUpdated) { Stop-Preflight 1 "state.json 'updated' is not a string." }
if (-not [string]::Equals($currentUpdated, $ExpectedUpdated, [System.StringComparison]::Ordinal)) {
    Stop-Preflight 2 "collision: state.json updated is '$currentUpdated', expected '$ExpectedUpdated'. Nothing written."
}

$isFederation = $root.AsObject().ContainsKey('subSquads')
$schema = Get-JsonString $root['schemaVersion']
$currentSchema = if ($isFederation) { '1.3' } else { '1.4' }
$legacySchema = if ($isFederation) { '1.2' } else { '1.3' }
$run = $root['currentRun']
if ($null -eq $run -or $run.GetValueKind() -ne [System.Text.Json.JsonValueKind]::Object) {
    Stop-Preflight 1 "state.json has no currentRun object; the Scribe seeds it. Nothing written."
}
$hasPreflight = $run.AsObject().ContainsKey('costPreflight')

$bump = $false
if ($schema -eq $currentSchema) {
    # entry-schemas.md: a current-schema state without the object reads as not-requested, so the write simply adds it.
}
elseif ($schema -eq $legacySchema) {
    if ($hasPreflight) { Stop-Preflight 1 "state.json schema $schema already carries currentRun.costPreflight. Nothing written." }
    $bump = $true
}
else {
    Stop-Preflight 1 "unsupported state.json schemaVersion '$schema'. Nothing written."
}

if ($null -ne $entryText -and [regex]::IsMatch($decisionsText, $headingLine)) {
    Stop-Preflight 1 "decisions.md already holds '$heading'; the entry is appended exactly once. Nothing written."
}

# --- Compute the intended files -----------------------------------------------------------
$expected = $root.DeepClone()
$expected['currentRun']['costPreflight'] = [System.Text.Json.Nodes.JsonNode]::Parse($newPreflight.ToJsonString())
if ($bump) { $expected['schemaVersion'] = [System.Text.Json.Nodes.JsonValue]::Create($currentSchema) }

if (-not $bump -and $hasPreflight -and [System.Text.Json.Nodes.JsonNode]::DeepEquals($root['currentRun']['costPreflight'], $newPreflight) -and $null -eq $entryText) {
    Write-Output "UNCHANGED state.json already holds this costPreflight object"
    exit 0
}

$serializer = [System.Text.Json.JsonSerializerOptions]::new()
$serializer.WriteIndented = $true
$serializer.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
$stateNewline = if ($stateText.Contains("`r`n")) { "`r`n" } else { "`n" }
$newState = (ConvertTo-Lf $expected.ToJsonString($serializer)).Replace("`n", $stateNewline)
if ($stateText.EndsWith("`n")) { $newState += $stateNewline }

$newDecisions = $null
if ($null -ne $entryText) {
    $decisionsNewline = if ($decisionsText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $separator = if ($decisionsText.Length -eq 0) { '' } elseif ($decisionsText.EndsWith("`n")) { $decisionsNewline } else { "$decisionsNewline$decisionsNewline" }
    $newDecisions = $decisionsText + $separator + $entryText.Replace("`n", $decisionsNewline) + $decisionsNewline
}

# --- Write ---------------------------------------------------------------------------------
foreach ($path in @($statePath, $decisionsPath)) {
    if ((Get-Item -LiteralPath $path).IsReadOnly) { Stop-Preflight 3 "$path is read-only. Nothing written." }
}

$recheck = [System.IO.File]::ReadAllBytes($statePath)
if ([System.Convert]::ToBase64String($stateBytes) -cne [System.Convert]::ToBase64String($recheck)) {
    Stop-Preflight 2 'collision: state.json changed while the transaction was being prepared. Nothing written.'
}

$decisionsWritten = $false
try {
    if ($null -ne $newDecisions) {
        Write-FileAtomic -Path $decisionsPath -Content $newDecisions
        $decisionsWritten = $true
    }
    Write-FileAtomic -Path $statePath -Content $newState
}
catch {
    $detail = $_.Exception.Message
    if ($decisionsWritten) {
        try { Write-FileAtomic -Path $decisionsPath -Content $decisionsText; $detail += ' decisions.md restored.' }
        catch { $detail += " decisions.md could NOT be restored: $($_.Exception.Message)" }
    }
    Stop-Preflight 3 "write failed: $detail"
}

# --- Read back -------------------------------------------------------------------------------
$readbackFailures = [System.Collections.Generic.List[string]]::new()
try {
    $after = [System.Text.Json.Nodes.JsonNode]::Parse([System.IO.File]::ReadAllText($statePath))
    if (-not [System.Text.Json.Nodes.JsonNode]::DeepEquals($after, $expected)) { $readbackFailures.Add('state.json does not equal the intended state.') }
    if (-not [System.Text.Json.Nodes.JsonNode]::DeepEquals($after['currentRun']['costPreflight'], $newPreflight)) { $readbackFailures.Add('state.json costPreflight does not equal the supplied object.') }
    $originalRest = $root.DeepClone()
    $afterRest = $after.DeepClone()
    foreach ($n in @($originalRest, $afterRest)) {
        $n['schemaVersion'] = [System.Text.Json.Nodes.JsonValue]::Create('x')
        $null = $n['currentRun'].AsObject().Remove('costPreflight')
    }
    if (-not [System.Text.Json.Nodes.JsonNode]::DeepEquals($originalRest, $afterRest)) { $readbackFailures.Add('state.json changed a value outside costPreflight and schemaVersion.') }

    $decisionsAfter = [System.IO.File]::ReadAllText($decisionsPath)
    if ($null -ne $entryText) {
        if (([regex]::Matches($decisionsAfter, $headingLine)).Count -ne 1) { $readbackFailures.Add('decisions.md does not hold the entry exactly once.') }
        if (-not (ConvertTo-Lf $decisionsAfter).Contains($entryText)) { $readbackFailures.Add('decisions.md entry does not match the supplied text.') }
        if (-not $decisionsAfter.StartsWith($decisionsText, [System.StringComparison]::Ordinal)) { $readbackFailures.Add('decisions.md prior content changed.') }
    }
    elseif ($decisionsAfter -cne $decisionsText) { $readbackFailures.Add('decisions.md changed without an entry.') }
}
catch { $readbackFailures.Add("read-back threw: $($_.Exception.Message)") }

if ($readbackFailures.Count -gt 0) { Stop-Preflight 3 "read-back failed: $($readbackFailures -join ' ')" }

$anchor = if ($null -ne $entryText) {
    'decisions.md#' + (([regex]::Replace($heading.Substring(3).ToLowerInvariant(), '[^a-z0-9 _-]', '')) -replace ' ', '-')
}
else { 'none' }
Write-Output "WRITTEN decision=$decision runId=$runId roundId=$roundId schemaVersion=$(Get-JsonString $after['schemaVersion']) decisionRef=$anchor"
exit 0
