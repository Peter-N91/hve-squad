#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Writes an ordinary squad hand-off (history, decision, orchestration, state advance)
    deterministically from a JSON payload, then verifies the ledger.
.DESCRIPTION
    A hand-off that only transcribes a payload into append-only entries, a state advance,
    and a derived ledger needs no model. This script performs exactly that write, with the
    same formats `references/entry-schemas.md` defines. The Squad Scribe runs it as its
    deterministic write path for an ordinary payload, so the Scribe remains the only writer
    of squad state; a payload this script refuses (initialization, memory, verdicts, summaries,
    promotion, expansion, notifications, a ceiling-admitted history write) is composed by the
    Scribe itself. The coordinator never runs it. It is synchronous; run it once at a time
    per squad root.

    Order of operations:
      1. Validate the payload (closed field sets, legal values, roster agent names, model
         attribution against the agent pin and the rate table, deliverables are files inside
         the repository modified since the last hand-off, no secret-like text anywhere, no
         heading-forging text) and the squad root (single-squad schema 1.4, no federation
         root, no cost ceiling here or at the federation root above a sub-squad, `turn` equals
         state turn + 1, timestamp not before the last entry, no duplicate entry heading).
         A rejection writes nothing.
      2. Run `Initialize-SquadConsumptionRates.ps1 -Check`; when the rate table lacks a
         template row, reseed it (never `-DropMalformedRows`). A malformed operator row
         refuses with exit 4 and nothing written.
      3. Append each history entry with its consumption block, the Squad Scribe
         orchestration entry, and the optional decision entry; advance `state.json`.
      4. Run `Measure-SquadLedger.ps1 -Write` (child process: it calls `exit`), refresh the
         ledger heading run id, then run `Measure-SquadLedger.ps1 -Check
         -ExpectedHistoryCounts` with counts taken before step 3. The script exits 0 only
         when that check passes. An existing Cost Comparison keeps its manual-baseline figures;
         this script rewrites its squad cost and credits to the new total and recomputes the saving
         percentage from the stated baseline (a baseline below the cost marks the paragraph
         `stale — refreshed at run end` for the Scribe). The seed placeholder is replaced by a
         squad-figure line the Scribe completes.
    Appended files keep their existing bytes (BOM, line endings); entries are only appended.
    Every file is replaced through a temp file and move. On any failure after step 2 begins,
    every changed file is restored to its original bytes (a file the script created is
    removed) and the script exits 3.

    Payload (JSON object; every object is a closed key set). Only `runId`, `historyRecords`
    (each with agent, request, deliverable, outcome) and `stateAdvance.activeRoles` are
    required; everything marked "derived" is filled in when omitted and strictly validated
    when supplied:
      runId, handoff (optional, only `script`: the economy marker the coordinator sends),
      route (optional, requires decision),
      turn (derived: state turn + 1), timestamp (derived: the current UTC time),
      mode (derived: the state.json mode),
      since (optional ISO time: the dispatch start; a parallel wave passes it),
      decision {title, rationale, adrNoted} (optional),
      historyRecords [ {agent, title?, request, deliverable, outcome, memberName?,
        selectionCue? (required for an Alternate agent), passedModel? (required with
        cli-pinned and must equal model), costPreflightRef?/costPreflightSlot? (refused:
        a ceiling slot needs the Scribe), consumption? {ten fields}, routingIdentity?{
        requestedModel, effectiveModel, observedModel, routeRationale}} ] (may be empty),
      orchestration? {request?, outcome?, passedModel?, consumption? {ten fields}},
      stateAdvance {activeRoles[], openEscalationsRaised[]?, openEscalationsResolved[]?,
        sessionModel?, modelOverrides?}.

    Derived consumption (a record's `consumption`, or `orchestration.consumption`, omitted
    entirely; a supplied block is never altered): the five token fields are the estimator
    floors of the role's assignment class (model-routing.md Assignment Classes; the
    orchestration share is the `bookkeeping` class) from the Dispatch-size estimator table in
    consumption-rates.md (the shipped template when that file lacks it), computed as that
    section defines; `model` is `passedModel` (`cli-pinned`), else the agent's frontmatter pin
    (`agent-pinned`), else the session model (`session-inherited`; `unknown` and
    `unresolved` when none is recorded); the orchestration share is always the session model;
    `model_tier` and `priced_as` come from that model's rate row (the `default` tier and the
    tier fallback row when it has none); `basis` is `estimated`. A figure the estimator cannot
    produce refuses to the Scribe (exit 2) rather than guessing. Supply `consumption` whenever
    the dispatch reported its own size signals.

    Review-saw-final-files check (always on, no flag): when a record's agent fills a review-class
    role (tester, qa-engineer, challenger, fact-checker, supply-chain, vuln-manager, privacy,
    accessibility, risk-manager), every other record's deliverable must not be modified more than
    2 s after the latest review deliverable; otherwise exit 1 and nothing is written. Editing the
    payload does not clear it: re-dispatch the review on the final files, then rerun.

    Snapshot mode (`-SnapshotPath`/`-Path`, then `-VerifySnapshotPath`) is optional and records and later
    re-checks SHA-256 hashes of an owner write set (files and directories), so the owners can be
    confirmed finished and a closing review left the files unchanged. Directories
    are re-enumerated on verify, so a new or removed file counts as a change. `-WaitStable
    <seconds>` returns only after the whole write set has been unchanged for that long
    (bounded by `-MaxWaitSeconds`, exit 6 on timeout). Paths must stay inside `-RepoRoot`.

    Pass the payload in-process as a single-quoted here-string, so `$` and backticks survive:
    `$p = @'` newline JSON newline `'@` then `& <script> -SquadRoot <root> -PayloadJson $p`.
    Never pass JSON through a double-quoted string or a `pwsh -File` argument.
    Snapshot mode from a `pwsh -File` host takes `-Path 'a,b'` (comma-joined, split here); a
    PowerShell host calls it in-process: `& <script> -SnapshotPath s.json -Path 'a','b'`. A
    listed path that does not exist exits 1.

    Exit codes: 0 written and verified (or snapshot unchanged); 1 validation or usage
    error, nothing written (correct the one field named and rerun once); 2 the Scribe composes
    this hand-off itself (unsupported payload or state: cost ceiling here or at the federation
    root, ceiling slot fields, federation root, legacy schema, agent not on the roster,
    secret-like text, unseeded ledger, a consumption.md with some but not all ledger headings,
    an omitted block the estimator cannot derive), nothing
    written; 3 write or ledger failure, files restored (or unreadable input, nothing
    changed); 4 rate table refused (malformed operator row), operator decision needed,
    nothing written; 5 snapshot differs; 6 write set not stable before the timeout;
    7 refused: `team.md` does not record `Model routing: economy` (every mode, nothing
    written; the Scribe composes the hand-off by hand, as in v0.18.1); 8 another hand-off
    holds this squad root's lock past -LockTimeoutSeconds, nothing written.

    Ledger check (v0.18.1 failure classes): after the writes, `Measure-SquadLedger -Check`
    runs. PASS, or a `ledger-only` failure (cost accounting the next -Write re-derives),
    keeps the writes and exits 0; a ledger-only failure prints `WARN ledger-only:` with the
    first mismatch lines. A `history-integrity` failure, a missing `failure class:` line, or
    a crash rolls the writes back and exits 3.

    Warnings (never refusals): `WARN economy consent not recorded` when decisions.md has no
    `## Economy Mode Accepted` entry; a history record whose routeRationale does not start
    with `Route: ` is prefixed with `Route: bounded` (payload route `bounded`) or
    `Route: economy`, with a WARN; a record without routingIdentity gets a WARN.

    Economy only (references/economy-mode.md): every parameter set reads `team.md` under
    -SquadRoot first and refuses with exit 7 unless it records `Model routing: economy`.

    Concurrency: a hand-off holds an exclusive per-root lock (an OS file handle in the temp
    directory, released when the process exits, so a crashed holder never leaves a stale
    lock) from validation to the ledger check. The lock is keyed by the canonical squad root
    (8.3 short names expanded, junctions and symbolic links resolved), so one folder reached
    by two spellings shares one lock. Everything that depends on state (turn, the freshness
    bound, rate seeding) is read after the lock is held. When another hand-off landed while
    this one waited, the freshness bound stays the state.json `updated` read before the wait,
    so a valid second payload lands as the next turn; a deliverable that the other hand-off
    already credited and that has not changed since exits 1 (a deliverable is credited once). A rollback restores a file only while its
    bytes are still the ones this run wrote; a file another writer changed is left as it is
    and named in the exit-3 message.

.PARAMETER SquadRoot
    A single-squad root: `.copilot-tracking/squad/` or `.copilot-tracking/squad/members/<name>/`.
    Required in every mode, because the economy check reads its `team.md`.
.PARAMETER PayloadPath
    Path to a JSON payload file, instead of -PayloadJson.
.PARAMETER PayloadJson
    The payload as a JSON string.
.PARAMETER SessionLog
    Passed to `Measure-SquadLedger.ps1 -Write`; defaults to `auto`.
.PARAMETER LockTimeoutSeconds
    Longest wait for another hand-off on the same root to finish; exit 8 when exceeded (default 120).
.PARAMETER SnapshotPath
    Snapshot mode: file to write the hash snapshot to.
.PARAMETER Path
    Snapshot mode: files or directories (relative to -RepoRoot) to hash.
.PARAMETER WaitStable
    Snapshot mode: wait until the hashed write set has been unchanged for this many seconds
    before recording.
.PARAMETER MaxWaitSeconds
    Snapshot mode: longest total wait for -WaitStable; exit 6 when exceeded (default 600).
.PARAMETER RepoRoot
    Snapshot mode: repository root; defaults to the current directory.
.PARAMETER VerifySnapshotPath
    Verify mode: a snapshot previously written with -SnapshotPath.
.EXAMPLE
    $p = @'
    { "runId": "r1", "turn": 2, "...": "..." }
    '@
    & ./Write-SquadHandoff.ps1 -SquadRoot .copilot-tracking/squad -PayloadJson $p
.EXAMPLE
    ./Write-SquadHandoff.ps1 -SquadRoot .copilot-tracking/squad -PayloadPath $env:TEMP/handoff.json
.EXAMPLE
    ./Write-SquadHandoff.ps1 -SquadRoot .copilot-tracking/squad -SnapshotPath $env:TEMP/deliverables.json -Path src/app.py, .copilot-tracking/changes/x.md
.EXAMPLE
    ./Write-SquadHandoff.ps1 -SquadRoot .copilot-tracking/squad -VerifySnapshotPath $env:TEMP/deliverables.json
#>
[CmdletBinding(DefaultParameterSetName = 'Handoff')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Handoff')]
    [Parameter(Mandatory, ParameterSetName = 'Snapshot')]
    [Parameter(Mandatory, ParameterSetName = 'Verify')]
    [string]$SquadRoot,

    [Parameter(ParameterSetName = 'Handoff')]
    [string]$PayloadPath,

    [Parameter(ParameterSetName = 'Handoff')]
    [string]$PayloadJson,

    [Parameter(ParameterSetName = 'Handoff')]
    [string]$SessionLog = 'auto',

    [Parameter(ParameterSetName = 'Handoff')]
    [ValidateRange(1, 3600)]
    [int]$LockTimeoutSeconds = 120,

    [Parameter(Mandatory, ParameterSetName = 'Snapshot')]
    [string]$SnapshotPath,

    [Parameter(Mandatory, ParameterSetName = 'Snapshot')]
    [string[]]$Path,

    [Parameter(ParameterSetName = 'Snapshot')]
    [string]$RepoRoot,

    [Parameter(ParameterSetName = 'Snapshot')]
    [ValidateRange(0, 3600)]
    [int]$WaitStable,

    [Parameter(ParameterSetName = 'Snapshot')]
    [ValidateRange(1, 3600)]
    [int]$MaxWaitSeconds = 600,

    [Parameter(Mandatory, ParameterSetName = 'Verify')]
    [string]$VerifySnapshotPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

function Stop-Handoff {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("Write-SquadHandoff: $Message")
    exit $Code
}

function Get-FileSha256 {
    param([string]$FullPath)
    try { return (Get-FileHash -LiteralPath $FullPath -Algorithm SHA256).Hash.ToLowerInvariant() }
    catch { return '<unreadable>' }
}

$SquadRoot = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($SquadRoot)
$routingTeam = Join-Path $SquadRoot 'team.md'
$routingMode = 'off'
if (Test-Path -LiteralPath $routingTeam -PathType Leaf) {
    $routingMatch = [regex]::Match([System.IO.File]::ReadAllText($routingTeam), '(?m)^Model routing:\s*`?(?<mode>off|ranked|economy|manual)`?\s*$')
    if ($routingMatch.Success) { $routingMode = $routingMatch.Groups['mode'].Value }
}
if ($routingMode -ne 'economy') {
    Stop-Handoff 7 "refused: $routingTeam records Model routing: $routingMode, not economy. The script hand-off is economy-only; the Squad Scribe composes this hand-off itself."
}

function ConvertTo-NormalPath {
    # GetFullPath expands 8.3 short names; an existing path is then read back in its long form.
    param([string]$Text)
    $full = [System.IO.Path]::GetFullPath($Text)
    if (Test-Path -LiteralPath $full) { try { $full = (Get-Item -LiteralPath $full -Force).FullName } catch { Write-Verbose "long-path lookup failed: $($_.Exception.Message)" } }
    return $full
}

function Get-CanonicalPath {
    # One folder maps to one string: 8.3 short names are expanded and junctions or symbolic links
    # on any component are resolved to their final target.
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $root = [System.IO.Path]::GetPathRoot($full)
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
    return $current.TrimEnd('\', '/')
}

function Resolve-UnderRoot {
    param([string]$Root, [string]$Relative)
    $normalRoot = ConvertTo-NormalPath $Root
    $full = ConvertTo-NormalPath (Join-Path $normalRoot $Relative)
    $trimmed = $normalRoot.TrimEnd('\', '/')
    $prefix = $trimmed + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -and $full.TrimEnd('\', '/') -ne $trimmed) {
        Stop-Handoff 1 "path '$Relative' resolves outside '$Root'."
    }
    return $full
}

function Get-SnapshotMap {
    param([string]$Root, [string[]]$Relatives, [switch]$RequireExisting)
    $Root = ConvertTo-NormalPath $Root
    $map = [ordered]@{}
    foreach ($rel in $Relatives) {
        $full = Resolve-UnderRoot -Root $Root -Relative $rel
        if ($RequireExisting -and -not (Test-Path -LiteralPath $full)) { Stop-Handoff 1 "write-set path '$rel' does not exist; list a typo-free file or its parent directory (a deleted file is covered by its directory)." }
        if (Test-Path -LiteralPath $full -PathType Container) {
            foreach ($file in (Get-ChildItem -LiteralPath $full -Recurse -File | Sort-Object FullName)) {
                $key = [System.IO.Path]::GetRelativePath($Root, $file.FullName) -replace '\\', '/'
                $map[$key] = Get-FileSha256 $file.FullName
            }
        }
        else {
            $key = [System.IO.Path]::GetRelativePath($Root, $full) -replace '\\', '/'
            $map[$key] = if (Test-Path -LiteralPath $full -PathType Leaf) { Get-FileSha256 $full } else { $null }
        }
    }
    return $map
}

# --- Snapshot and verify modes ------------------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'Snapshot') {
    $root = if ($PSBoundParameters.ContainsKey('RepoRoot')) { $PSCmdlet.GetUnresolvedProviderPathFromPSPath($RepoRoot) } else { (Get-Location).ProviderPath }
    # A bash host can only pass one string, so each element may be a comma-joined list.
    $Path = @($Path | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($Path.Count -eq 0) { Stop-Handoff 1 '-Path names no file or directory.' }
    $root = ConvertTo-NormalPath $root
    $map = Get-SnapshotMap -Root $root -Relatives $Path -RequireExisting
    if ($PSBoundParameters.ContainsKey('WaitStable')) {
        $deadline = [DateTime]::UtcNow.AddSeconds($MaxWaitSeconds)
        $signature = ($map.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
        $stableSince = [DateTime]::UtcNow
        while (([DateTime]::UtcNow - $stableSince).TotalSeconds -lt $WaitStable) {
            if ([DateTime]::UtcNow -gt $deadline) { Stop-Handoff 6 "the write set was still changing after $MaxWaitSeconds s; an owner has not finished." }
            Start-Sleep -Milliseconds 250
            $map = Get-SnapshotMap -Root $root -Relatives $Path
            $current = ($map.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
            if ($current -ne $signature) { $signature = $current; $stableSince = [DateTime]::UtcNow }
        }
    }
    $target = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($SnapshotPath)
    $targetDir = Split-Path -Parent $target
    if ($targetDir -and -not (Test-Path -LiteralPath $targetDir -PathType Container)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    $snapshot = [ordered]@{ repoRoot = $root; paths = @($Path); files = $map }
    [System.IO.File]::WriteAllText($target, ($snapshot | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
    Write-Output "SNAPSHOT recorded $($map.Count) existing file(s) to $target"
    exit 0
}
if ($PSCmdlet.ParameterSetName -eq 'Verify') {
    $source = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($VerifySnapshotPath)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { Stop-Handoff 1 "missing snapshot $source." }
    $snapshot = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json -AsHashtable
    $root = [string]$snapshot['repoRoot']
    $recorded = $snapshot['files']
    $paths = if ($snapshot.ContainsKey('paths')) { @($snapshot['paths']) } else { @($recorded.Keys) }
    $now = Get-SnapshotMap -Root $root -Relatives $paths
    $changes = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $recorded.Keys) {
        if (-not $now.Contains($key) -or $null -eq $now[$key]) { if ($null -ne $recorded[$key]) { $changes.Add("$key was removed since the snapshot.") } }
        elseif ($now[$key] -ne $recorded[$key]) { $changes.Add("$key changed since the snapshot.") }
    }
    foreach ($key in $now.Keys) {
        if (-not $recorded.ContainsKey($key) -and $null -ne $now[$key]) { $changes.Add("$key is new since the snapshot.") }
    }
    if ($changes.Count -gt 0) {
        [Console]::Error.WriteLine("SNAPSHOT: CHANGED`n  - " + ($changes -join "`n  - "))
        exit 5
    }
    Write-Output "SNAPSHOT: UNCHANGED ($($recorded.Count) file(s))"
    exit 0
}

# --- Hand-off mode ---------------------------------------------------------------------------
$ConsumptionOrder = @('model', 'model_source', 'priced_as', 'model_tier', 'internal_turns', 'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens', 'basis')
$ConsumptionNumberKeys = @('internal_turns', 'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens')
$ModelSources = @('dispatch-reported', 'agent-pinned', 'operator-declared', 'session-inherited', 'cli-pinned', 'unresolved')
$ModelTiers = @('fast', 'default', 'extended')
$Bases = @('estimated', 'tier-default')
$Modes = @('interactive', 'autonomous', 'autopilot')
$RoutingKeys = @('requestedModel', 'effectiveModel', 'observedModel', 'routeRationale')
$ScribeAgent = 'Squad Scribe'
$Fence = '```'
# The Scribe never writes a secret, token, credential, or connection string (scribe-procedure.md
# treat-as-data-and-redaction); the script refuses to the Scribe rather than redacting.
$SecretPattern = '(?i)\b(password|passwd|pwd|secret|client[_-]?secret|api[_-]?key|access[_-]?key|access[_-]?token|auth[_-]?token|refresh[_-]?token|token|bearer|connection[_-]?string|accountkey|sharedaccesskey|sharedaccesssignature|private[_-]?key)\s*[=:]|\bauthorization\s*:|\bbearer\s+[A-Za-z0-9._~+/=-]{16,}|\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]+|\b(?:AKIA|ASIA)[0-9A-Z]{16}\b|\bxox[abprs]-[A-Za-z0-9-]{8,}|\bsig=|\bsv=\d{4}-|-----BEGIN [A-Z ]*PRIVATE KEY|\bgh[pousr]_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}|\bsk-[A-Za-z0-9]{20,}|DefaultEndpointsProtocol=|AccountKey='
$ControlPattern = '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u0085\u2028\u2029]'

$JsonOptions = [System.Text.Json.JsonSerializerOptions]::new()
$JsonOptions.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
$JsonOptions.WriteIndented = $true

$problems = [System.Collections.Generic.List[string]]::new()
$needsScribe = [System.Collections.Generic.List[string]]::new()

function Get-Kind {
    param($Node)
    if ($null -eq $Node) { return 'Null' }
    return $Node.GetValueKind().ToString()
}

function Get-NodeString {
    param($Node)
    if ((Get-Kind $Node) -ne 'String') { return $null }
    return $Node.GetValue[string]()
}

function Get-NodeInt {
    param($Node)
    if ((Get-Kind $Node) -ne 'Number') { return $null }
    $value = 0L
    if (-not [long]::TryParse($Node.ToJsonString(), [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value)) { return $null }
    return $value
}

function Test-ObjectKeys {
    param($Node, [string[]]$Required, [string[]]$Optional, [string]$Where)
    if ((Get-Kind $Node) -ne 'Object') { $problems.Add("$Where must be a JSON object."); return $false }
    $present = @($Node | ForEach-Object { $_.Key })
    foreach ($key in $Required) { if ($key -notin $present) { $problems.Add("$Where is missing '$key'.") } }
    foreach ($key in $present) { if ($key -notin ($Required + $Optional)) { $problems.Add("$Where has unknown key '$key'; the key set is closed.") } }
    return $true
}

function Get-TextField {
    # A required (or present optional) single-line string field; $null and a problem when invalid.
    param($Node, [string]$Key, [string]$Where, [switch]$Optional, [switch]$MultiLine)
    $value = $Node[$Key]
    if ($null -eq $value) {
        if (-not $Optional) { $problems.Add("$Where.$Key is required.") }
        return $null
    }
    $text = Get-NodeString $value
    if ($null -eq $text -or [string]::IsNullOrWhiteSpace($text)) { $problems.Add("$Where.$Key must be a non-empty string."); return $null }
    $text = $text.Trim()
    if ($text -match $ControlPattern) { $problems.Add("$Where.$Key contains control characters."); return $null }
    if ($MultiLine) {
        $text = ($text -replace "`r`n", "`n" -replace "`r", "`n")
        $fenceChar = $null
        $fenceLength = 0
        foreach ($line in ($text -split "`n")) {
            if ($line -match '^\s*#') { $problems.Add("$Where.$Key must not contain a line starting with '#'; headings are structural."); return $null }
            if ($line -match '^\s{0,3}(=+|-+|\*{3,}|_{3,})\s*$') { $problems.Add("$Where.$Key must not contain a setext underline or thematic break line; it would forge a heading."); return $null }
            if ($line -match '^\s{0,3}<') { $problems.Add("$Where.$Key must not contain a line starting with '<'; an HTML block would hide later entries."); return $null }
            $fenceMatch = [regex]::Match($line, '^\s{0,3}(?<f>`{3,}|~{3,})(?<rest>.*)$')
            if ($fenceMatch.Success) {
                $marker = $fenceMatch.Groups['f'].Value
                if ($null -eq $fenceChar) { $fenceChar = $marker[0]; $fenceLength = $marker.Length }
                elseif ($marker[0] -eq $fenceChar -and $marker.Length -ge $fenceLength -and [string]::IsNullOrWhiteSpace($fenceMatch.Groups['rest'].Value)) { $fenceChar = $null; $fenceLength = 0 }
            }
        }
        if ($null -ne $fenceChar) { $problems.Add("$Where.$Key has an unclosed code fence (a closing fence must use the same character and at least the same length), which would swallow later entries."); return $null }
    }
    elseif ($text -match '[\r\n]') { $problems.Add("$Where.$Key must be a single line."); return $null }
    if ($text -match $SecretPattern) { $needsScribe.Add("$Where.$Key looks like it carries a secret; the Scribe redacts before writing.") }
    return $text
}

function Test-Consumption {
    # Returns an ordered map in contractual field order, or $null with problems recorded.
    param($Node, [string]$Where)
    if (-not (Test-ObjectKeys -Node $Node -Required @($ConsumptionOrder | Where-Object { $_ -ne 'priced_as' }) -Optional @('priced_as') -Where $Where)) { return $null }
    $before = $problems.Count
    $map = [ordered]@{}
    # priced_as is always derivable from the model, so a supplied value is only checked against the derivation.
    $suppliedPricedAs = if ($null -ne $Node['priced_as']) { (Get-NodeString $Node['priced_as']).Trim().Trim('`').Trim() } else { $null }
    foreach ($key in $ConsumptionOrder) {
        if ($key -eq 'priced_as') { $map[$key] = ''; continue }
        if ($key -in $ConsumptionNumberKeys) {
            $n = Get-NodeInt $Node[$key]
            if ($null -eq $n) { $problems.Add("$Where.$key must be a bare non-negative integer."); continue }
            $map[$key] = $n
        }
        else {
            $s = Get-NodeString $Node[$key]
            if ([string]::IsNullOrWhiteSpace($s)) { $problems.Add("$Where.$key must be a non-empty string."); continue }
            $map[$key] = $s.Trim().Trim('`').Trim()
        }
    }
    if ($problems.Count -gt $before) { return $null }
    if ($map['model_source'] -notin $ModelSources) { $problems.Add("$Where.model_source '$($map['model_source'])' is not one of: $($ModelSources -join ', ').") }
    if ($map['model_tier'] -notin $ModelTiers) { $problems.Add("$Where.model_tier must be one of: $($ModelTiers -join ', ').") }
    if ($map['basis'] -notin $Bases) { $problems.Add("$Where.basis must be exactly one of: $($Bases -join ', ').") }
    if ($problems.Count -eq $before) {
        $derived = Get-DerivedPricedAs -Model $map['model'] -Tier $map['model_tier']
        if ($derived) {
            $map['priced_as'] = $derived
            if ($suppliedPricedAs -and $suppliedPricedAs -ne $derived) {
                $warning = "WARN $Where.priced_as '$suppliedPricedAs' replaced by '$derived', the rate row model '$($map['model'])' prices at"
                if (-not $handoffWarnings.Contains($warning)) { $handoffWarnings.Add($warning) }
            }
        }
        elseif ($suppliedPricedAs -and $suppliedPricedAs -notmatch '(?i)orchestration') { $map['priced_as'] = $suppliedPricedAs }
        else { $problems.Add("$Where.priced_as cannot be derived: model '$($map['model'])' has no rate row and no tier fallback row exists for '$($map['model_tier'])'.") }
    }
    if ($map['priced_as'] -match '(?i)orchestration') { $problems.Add("$Where.priced_as must be a rate-row name, never an orchestration label.") }
    if ($map['model'] -match $SecretPattern -or $map['priced_as'] -match $SecretPattern) { $needsScribe.Add("$Where carries secret-like text.") }
    if ($problems.Count -gt $before) { return $null }
    return $map
}

function ConvertTo-ConsumptionBlock {
    param($Map, [bool]$Orchestration)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($(if ($Orchestration) { '#### Consumption — Orchestration' } else { '#### Consumption' }))
    $lines.Add('')
    $lines.Add("${Fence}json")
    $lines.Add('{')
    for ($i = 0; $i -lt $ConsumptionOrder.Count; $i++) {
        $key = $ConsumptionOrder[$i]
        $rendered = if ($key -in $ConsumptionNumberKeys) { [string]$Map[$key] } else { [System.Text.Json.JsonSerializer]::Serialize([string]$Map[$key], $JsonOptions) }
        $comma = if ($i -lt ($ConsumptionOrder.Count - 1)) { ',' } else { '' }
        $lines.Add("  `"$key`": $rendered$comma")
    }
    $lines.Add('}')
    $lines.Add($Fence)
    return $lines
}

function Write-FileAtomic {
    param([string]$FullPath, [byte[]]$Bytes)
    $tmp = Join-Path (Split-Path -Path $FullPath -Parent) (".$([System.IO.Path]::GetFileName($FullPath)).$([guid]::NewGuid().ToString('N')).tmp")
    try {
        [System.IO.File]::WriteAllBytes($tmp, $Bytes)
        [System.IO.File]::Move($tmp, $FullPath, $true)
        $script:OwnedHash[$FullPath] = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes))
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Update-OwnedHash {
    # A child script this run started wrote the file; its bytes are this run's to restore.
    param([string[]]$FullPath)
    foreach ($p in $FullPath) {
        if (Test-Path -LiteralPath $p -PathType Leaf) { $script:OwnedHash[$p] = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($p))) }
    }
}

function Invoke-ChildScript {
    param([string]$ScriptPath, [string[]]$Arguments)
    $output = & $PwshPath -NoProfile -File $ScriptPath @Arguments 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (($output | ForEach-Object { "$_" }) -join "`n").Trim() }
}

function Test-NodeStrings {
    # Every string in the payload (values and object keys) is scanned: secrets go to the Scribe, control characters are refused.
    param($Node, [string]$Where)
    switch (Get-Kind $Node) {
        'Object' {
            foreach ($pair in $Node) {
                if ($pair.Key -match $SecretPattern) { $needsScribe.Add("$Where key '$($pair.Key)' looks like it carries a secret.") }
                if ($pair.Key -match $ControlPattern) { $problems.Add("$Where key contains control characters.") }
                Test-NodeStrings -Node $pair.Value -Where "$Where.$($pair.Key)"
            }
        }
        'Array' { $i = 0; foreach ($item in $Node) { Test-NodeStrings -Node $item -Where "$Where[$i]"; $i++ } }
        'String' {
            $text = Get-NodeString $Node
            if ($text -match $SecretPattern) { $needsScribe.Add("$Where looks like it carries a secret; the Scribe redacts before writing.") }
            if ($text -match $ControlPattern) { $problems.Add("$Where contains control characters.") }
        }
    }
}

function ConvertFrom-ModelPin {
    # 'Claude Haiku 4.5 (copilot)' and 'claude-haiku-4.5' both -> 'claude-haiku-4.5'; only a trailing vendor suffix is dropped, so '(fast mode)' stays part of the name.
    param([string]$Text)
    return (($Text.Trim().Trim('"', "'") -replace '\s*\((?:copilot|github|anthropic|openai)\)\s*$', '').Trim() -replace '\s+', '-').ToLowerInvariant()
}

function Find-AgentPin {
    # Returns @{ Found; Models[] } from the agent's frontmatter under the repository agent folders.
    param([string]$AgentName)
    # Repository folders first (the flattened .github/agents layout included), then the installed plugin's agents/ beside this skill.
    $bases = @()
    if ($RepoBase) { $bases += @('.github/agents', '.agents/agents', '.claude/agents') | ForEach-Object { Join-Path $RepoBase $_ } }
    $bases += @((Join-Path $PSScriptRoot '../../../agents'), (Join-Path $PSScriptRoot '../../agents'), (Join-Path $PSScriptRoot '../agents'))
    foreach ($base in $bases) {
        if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $base -Recurse -File -Filter '*.md')) {
            $lines = @([System.IO.File]::ReadLines($file.FullName) | Select-Object -First 40)
            if ($lines.Count -lt 2 -or $lines[0].Trim() -ne '---') { continue }
            $name = $null
            $modelText = $null
            for ($i = 1; $i -lt $lines.Count -and $lines[$i].Trim() -ne '---'; $i++) {
                if ($lines[$i] -match '^name:\s*(.+?)\s*$') { $name = $Matches[1].Trim('"', "'") }
                elseif ($lines[$i] -match '^model:\s*(.+?)\s*$') { $modelText = $Matches[1] }
            }
            if ($name -ceq $AgentName) {
                $models = @()
                if ($modelText) { $models = @($modelText.Trim('[', ']').Split(',') | ForEach-Object { ConvertFrom-ModelPin $_ } | Where-Object { $_ }) }
                return @{ Found = $true; Models = $models }
            }
        }
    }
    return @{ Found = $false; Models = @() }
}

function Get-RateRows {
    # Name (first column) and Model ID (second column, when present) of the per-model rate table (headed 'Model (as routed)').
    param([string]$FullPath)
    $rows = [System.Collections.Generic.List[hashtable]]::new()
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) { return $rows }
    $inTable = $false
    $tierColumn = -1
    $cacheWriteColumn = -1
    foreach ($line in [System.IO.File]::ReadAllLines($FullPath)) {
        if (-not $inTable) {
            if ($line -match '^\|\s*Model \(as routed\)') {
                $inTable = $true
                $headerCells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
                $tierColumn = [array]::IndexOf($headerCells, 'Tier')
                $cacheWriteColumn = [array]::IndexOf($headerCells, 'Cache write')
            }
            continue
        }
        if ($line -notmatch '^\|') { break }
        $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        $cell = $cells[0]
        if ($cell -and $cell -notmatch '^[-: ]+$' -and $cell -ne '(additional)') {
            $rowId = if ($cells.Count -gt 1) { $cells[1].Trim('`') } else { '' }
            $rowTier = if ($tierColumn -ge 0 -and $cells.Count -gt $tierColumn) { $cells[$tierColumn] } else { '' }
            $cacheWrite = 0.0
            if ($cacheWriteColumn -ge 0 -and $cells.Count -gt $cacheWriteColumn) { [void][double]::TryParse($cells[$cacheWriteColumn], [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$cacheWrite) }
            $rows.Add(@{ Name = $cell; Id = $(if ($rowId -match '^[\w.-]+$') { $rowId } else { '' }); Tier = $rowTier; CacheWrite = $cacheWrite })
        }
    }
    return $rows
}

function Get-TierFallbackRow {
    # The 'Priced as' row name the Tier fallback rates table assigns to a tier, or $null.
    param([string]$FullPath, [string]$Tier)
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) { return $null }
    $inSection = $false
    foreach ($line in [System.IO.File]::ReadAllLines($FullPath)) {
        if ($line -match '^##\s+Tier fallback rates') { $inSection = $true; continue }
        if (-not $inSection) { continue }
        if ($line -match '^##\s') { break }
        if ($line -notmatch '^\|') { continue }
        $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -gt 1 -and $cells[0] -ieq $Tier) { return $cells[1] }
    }
    return $null
}

function Get-DerivedPricedAs {
    # The model's own rate row (display name), else the tier fallback row; $null when neither exists.
    param([string]$Model, [string]$Tier)
    $modelKey = ConvertFrom-ModelPin $Model
    $ownRow = @($RateRows | Where-Object { (ConvertFrom-ModelPin $_.Name) -eq $modelKey -or ($_.Id -and (ConvertFrom-ModelPin $_.Id) -eq $modelKey) }) | Select-Object -First 1
    if ($ownRow) { return $ownRow.Name }
    foreach ($rateFile in $RateFiles) { $fallback = Get-TierFallbackRow -FullPath $rateFile -Tier $Tier; if ($fallback) { return $fallback } }
    return $null
}

function Test-Attribution {
    # model_source evidence, priced_as rate row; called with a validated consumption map.
    param($Map, [string]$Where, [string]$PinAgent, [string]$PassedModel)
    if ($Map['priced_as'] -notin $RateNames) { $problems.Add("$Where.priced_as '$($Map['priced_as'])' is not a rate row in consumption-rates.md or the template.") }
    else {
        # The model's own rate row prices it; only a model with no row falls back to its tier's row.
        $modelKey = ConvertFrom-ModelPin $Map['model']
        $ownRow = @($RateRows | Where-Object { (ConvertFrom-ModelPin $_.Name) -eq $modelKey -or ($_.Id -and (ConvertFrom-ModelPin $_.Id) -eq $modelKey) }) | Select-Object -First 1
        if ($ownRow) {
            if ($Map['priced_as'] -ne $ownRow.Name) { $problems.Add("$Where.priced_as '$($Map['priced_as'])' must be the model's own rate row '$($ownRow.Name)' for model '$($Map['model'])'.") }
        }
        else {
            $fallback = $null
            foreach ($rateFile in $RateFiles) { $fallback = Get-TierFallbackRow -FullPath $rateFile -Tier $Map['model_tier']; if ($fallback) { break } }
            if ($fallback -and $Map['priced_as'] -ne $fallback) { $problems.Add("$Where.model '$($Map['model'])' has no rate row, so priced_as must be the $($Map['model_tier']) tier fallback '$fallback', not '$($Map['priced_as'])'.") }
        }
    }
    # A passedModel that repeats the recorded model is redundant, not evidence of a passed override.
    if ($Map['model_source'] -ne 'cli-pinned' -and $PassedModel -and (ConvertFrom-ModelPin $PassedModel) -ne (ConvertFrom-ModelPin $Map['model'])) { $problems.Add("$Where passedModel '$PassedModel' differs from model '$($Map['model'])'; a passed override is model_source cli-pinned.") }
    switch ($Map['model_source']) {
        'cli-pinned' {
            if (-not $PassedModel) { $problems.Add("$Where.model_source cli-pinned needs the dispatch's passedModel recorded in the payload.") }
            elseif ((ConvertFrom-ModelPin $PassedModel) -ne (ConvertFrom-ModelPin $Map['model'])) { $problems.Add("$Where.model '$($Map['model'])' must equal the passedModel '$PassedModel' for cli-pinned.") }
        }
        'agent-pinned' {
            $pin = Find-AgentPin $PinAgent
            if (-not $pin.Found) { $needsScribe.Add("$Where.model_source agent-pinned cannot be checked: no agent file named '$PinAgent' under the repository or installed plugin agent folders."); return }
            if ($pin.Models.Count -eq 0) { $problems.Add("$Where.model_source agent-pinned but '$PinAgent' declares no model: pin in its frontmatter."); return }
            if ((ConvertFrom-ModelPin $Map['model']) -notin $pin.Models) { $problems.Add("$Where.model '$($Map['model'])' does not equal the frontmatter pin of '$PinAgent' ($($pin.Models -join ', ')).") }
        }
    }
}

function Find-OwnRateRow {
    param([string]$Model)
    $modelKey = ConvertFrom-ModelPin $Model
    return @($RateRows | Where-Object { (ConvertFrom-ModelPin $_.Name) -eq $modelKey -or ($_.Id -and (ConvertFrom-ModelPin $_.Id) -eq $modelKey) }) | Select-Object -First 1
}

function Get-EstimatorFloors {
    # The class's row of the Dispatch-size estimator table (the squad's consumption-rates.md, else the shipped template); $null when unreadable.
    param([string]$Class)
    $label = switch ($Class) { 'research' { 'Research' } 'planning' { 'Plan' } 'review' { 'Review' } 'intake' { 'Review' } 'council' { 'Council' } 'bookkeeping' { 'Scribe' } default { 'Implement' } }
    foreach ($rateFile in $RateFiles) {
        if (-not (Test-Path -LiteralPath $rateFile -PathType Leaf)) { continue }
        $inTable = $false
        foreach ($line in [System.IO.File]::ReadAllLines($rateFile)) {
            if (-not $inTable) { if ($line -match '^\|\s*Dispatch class\s*\|') { $inTable = $true }; continue }
            if ($line -notmatch '^\|') { break }
            $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
            if ($cells.Count -lt 5 -or $cells[0] -notlike "$label*") { continue }
            $numbers = @($cells[1..4] | ForEach-Object { $parsed = 0.0; if ([double]::TryParse(($_ -replace ',', ''), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { $parsed } else { $null } })
            if (@($numbers | Where-Object { $null -eq $_ }).Count -gt 0) { continue }
            return @{ Turns = $numbers[0]; Base = $numbers[1]; Growth = $numbers[2]; Output = $numbers[3] }
        }
    }
    return $null
}

function Get-DerivedConsumption {
    # Fills an omitted consumption block from the role class's estimator floors, the model attribution ladder, and the rate row;
    # $null with the reason recorded for the Scribe when a figure cannot be produced.
    param([string]$Agent, [string]$PassedModel, [string]$Where, [string]$SessionModel, [switch]$Orchestration)
    $class = 'bookkeeping'
    if (-not $Orchestration) {
        $role = if ($agentRoles.ContainsKey($Agent)) { $agentRoles[$Agent] } else { '' }
        $class = if ($role -and $RoleClassMap.ContainsKey($role)) { $RoleClassMap[$role] } else { 'implementation' }
    }
    $floors = Get-EstimatorFloors $class
    if ($null -eq $floors) { $needsScribe.Add("$Where was omitted and the $class dispatch-size estimator row cannot be read from consumption-rates.md or its template; the Scribe composes the block."); return $null }
    if ($Orchestration) {
        if ($SessionModel) { $model = $SessionModel; $source = 'session-inherited' } else { $model = 'unknown'; $source = 'unresolved' }
    }
    elseif ($PassedModel) { $model = $PassedModel; $source = 'cli-pinned' }
    else {
        $pin = Find-AgentPin $Agent
        if (-not $pin.Found) { $needsScribe.Add("$Where was omitted and no agent file named '$Agent' was found to read its model pin; the Scribe composes the block."); return $null }
        if ($pin.Models.Count -gt 0) { $model = $pin.Models[0]; $source = 'agent-pinned' }
        elseif ($SessionModel) { $model = $SessionModel; $source = 'session-inherited' }
        else { $model = 'unknown'; $source = 'unresolved' }
    }
    $own = if ($model -ne 'unknown') { Find-OwnRateRow $model } else { $null }
    $tier = if ($own -and $own.Tier -in $ModelTiers) { $own.Tier } else { 'default' }
    $priced = Get-DerivedPricedAs -Model $model -Tier $tier
    if (-not $priced) { $needsScribe.Add("$Where was omitted and model '$model' has no rate row and no '$tier' tier fallback row; the Scribe composes the block."); return $null }
    $pricedRow = @($RateRows | Where-Object { $_.Name -eq $priced }) | Select-Object -First 1
    $writesCache = ($pricedRow -and $pricedRow.CacheWrite -gt 0)
    $average = $floors.Base + $floors.Growth * ($floors.Turns - 1) / 2.0
    $gross = $floors.Turns * $average
    return [ordered]@{
        model              = $model
        model_source       = $source
        priced_as          = $priced
        model_tier         = $tier
        internal_turns     = [long]$floors.Turns
        input_tokens       = [long][Math]::Round($gross * 0.20)
        cached_tokens      = [long][Math]::Round($gross * 0.80)
        cache_write_tokens = $(if ($writesCache) { [long][Math]::Round($floors.Base + $floors.Growth * ($floors.Turns - 1)) } else { 0L })
        output_tokens      = [long][Math]::Round($floors.Turns * $floors.Output)
        basis              = 'estimated'
    }
}

# A stamp later than now + 120 s cannot be real (typically local time labelled Z); it is never an ordering floor.
$handoffWarnings = [System.Collections.Generic.List[string]]::new()
$futureLimit = [DateTimeOffset]::UtcNow.AddSeconds(120)
function Test-FutureStamp {
    param([string]$Value, [DateTimeOffset]$Time, [string]$Where)
    if ($Time -le $futureLimit) { return $false }
    $warning = "WARN future timestamp $Value in $Where ignored as an ordering floor (likely local time labelled UTC)"
    if (-not $handoffWarnings.Contains($warning)) { $handoffWarnings.Add($warning) }
    return $true
}

function Get-LastEntryTimestamp {
    param([string]$Text, [string]$HeadingPrefix, [string]$Where = '')
    if ($null -eq $Text) { return $null }
    $found = [regex]::Matches($Text, '(?m)^' + $HeadingPrefix + '[ \t]+(\d{4}-\d{2}-\d{2}T\S+)')
    for ($i = $found.Count - 1; $i -ge 0; $i--) {
        $parsed = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse($found[$i].Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            if (Test-FutureStamp $found[$i].Groups[1].Value $parsed $Where) { continue }
            return $parsed
        }
    }
    return $null
}

$PwshPath = (Get-Process -Id $PID).Path

# --- Inputs ------------------------------------------------------------------------------------
if ($PSBoundParameters.ContainsKey('PayloadJson') -eq $PSBoundParameters.ContainsKey('PayloadPath')) {
    Stop-Handoff 1 'supply exactly one of -PayloadJson or -PayloadPath.'
}
if ($PSBoundParameters.ContainsKey('PayloadPath')) {
    $PayloadPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($PayloadPath)
    if (-not (Test-Path -LiteralPath $PayloadPath -PathType Leaf)) { Stop-Handoff 1 "missing $PayloadPath." }
    $PayloadJson = [System.IO.File]::ReadAllText($PayloadPath)
}
try { $payload = [System.Text.Json.Nodes.JsonNode]::Parse($PayloadJson) }
catch { Stop-Handoff 1 "payload is not valid JSON (duplicate keys are rejected): $($_.Exception.Message)" }

$scriptsRoot = $PSScriptRoot
$statePath = Join-Path $SquadRoot 'state.json'
$decisionsPath = Join-Path $SquadRoot 'decisions.md'
$consumptionPath = Join-Path $SquadRoot 'consumption.md'
$ratesPath = Join-Path $SquadRoot 'consumption-rates.md'
$teamPath = Join-Path $SquadRoot 'team.md'
$historyDir = Join-Path $SquadRoot 'history'

foreach ($required in @($statePath, $decisionsPath, $consumptionPath, $teamPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { Stop-Handoff 2 "missing $required; an uninitialized or unseeded squad root needs the Squad Scribe." }
}

# The state this hand-off was dispatched against, read before waiting on the lock: a hand-off that lands
# while this one waits moves state.json updated past this turn's deliverables.
$preWaitUpdated = $null
try {
    $preWaitNode = [System.Text.Json.Nodes.JsonNode]::Parse([System.IO.File]::ReadAllText($statePath))
    if ((Get-Kind $preWaitNode) -eq 'Object') { $preWaitUpdated = Get-NodeString $preWaitNode['updated'] }
}
catch { Write-Verbose "state.json pre-wait read failed; the state validation below reports it: $($_.Exception.Message)" }

# One hand-off per root at a time; the handle is released by the OS if this process dies. The key is the
# canonical root, so a short (8.3) name, a junction, or a symbolic link to the same folder shares the lock. The root itself
# is canonical from here on, so the repository above .copilot-tracking is found however the root was spelled.
$SquadRoot = Get-CanonicalPath $SquadRoot
$statePath = Join-Path $SquadRoot 'state.json'
$decisionsPath = Join-Path $SquadRoot 'decisions.md'
$consumptionPath = Join-Path $SquadRoot 'consumption.md'
$ratesPath = Join-Path $SquadRoot 'consumption-rates.md'
$teamPath = Join-Path $SquadRoot 'team.md'
$historyDir = Join-Path $SquadRoot 'history'
$lockKey = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($SquadRoot.ToLowerInvariant()))).Substring(0, 16)
$lockPath = Join-Path ([System.IO.Path]::GetTempPath()) "hve-squad-handoff-$lockKey.lock"
$lockDeadline = [DateTime]::UtcNow.AddSeconds($LockTimeoutSeconds)
$script:HandoffLock = $null
while ($null -eq $script:HandoffLock) {
    try { $script:HandoffLock = [System.IO.FileStream]::new($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) }
    catch [System.IO.IOException] {
        if ([DateTime]::UtcNow -gt $lockDeadline) { Stop-Handoff 8 "another hand-off has held $SquadRoot for more than $LockTimeoutSeconds s; nothing was written. Rerun once it finishes." }
        Start-Sleep -Milliseconds 200
    }
}
if (Test-Path -LiteralPath (Join-Path $SquadRoot 'federation.md') -PathType Leaf) {
    Stop-Handoff 2 'federation roots need the Squad Scribe.'
}

# economy-mode.md Consent: a missing acceptance is reported, never refused (refusing would only push the Scribe to the manual path).
$consentText = try { [System.IO.File]::ReadAllText($decisionsPath) } catch { '' }
if ($consentText -notmatch '(?m)^## Economy Mode Accepted\b') {
    $handoffWarnings.Add('WARN economy consent not recorded: decisions.md has no ## Economy Mode Accepted entry (economy-mode.md Consent); the hand-off continues. The coordinator states the trade and records it before the next dispatch.')
}

# The repository root sits above .copilot-tracking; without it, agent pins cannot be checked and deliverables stay inside the squad root.
$RepoBase = $null
$trackingMatch = [regex]::Match(($SquadRoot -replace '\\', '/'), '^(?<repo>.*?)/\.copilot-tracking/')
if ($trackingMatch.Success) { $RepoBase = ConvertTo-NormalPath $trackingMatch.Groups['repo'].Value }

# A sub-squad root sits under the federation root, whose aggregate ceiling this script cannot admit against.
$rootTrim = $SquadRoot.TrimEnd('\', '/')
$membersDir = Split-Path -Parent $rootTrim
if ($membersDir -and (Split-Path -Leaf $membersDir) -eq 'members') {
    $federationState = Join-Path (Split-Path -Parent $membersDir) 'state.json'
    if (Test-Path -LiteralPath $federationState -PathType Leaf) {
        try { $fedNode = [System.Text.Json.Nodes.JsonNode]::Parse([System.IO.File]::ReadAllText($federationState)) }
        catch { Stop-Handoff 2 "the federation root state.json is unreadable ($($_.Exception.Message)); the Squad Scribe handles a sub-squad hand-off." }
        $fedPreflight = $null
        if ($null -ne $fedNode -and $null -ne $fedNode['currentRun']) { $fedPreflight = $fedNode['currentRun']['costPreflight'] }
        if ($null -eq $fedPreflight -or $null -ne $fedPreflight['ceilingUsd'] -or (Get-NodeString $fedPreflight['decision']) -ne 'not-requested') {
            Stop-Handoff 2 'the federation root carries an active cost ceiling (or none can be read); a sub-squad hand-off under it needs the Squad Scribe.'
        }
    }
}

$RateNames = [System.Collections.Generic.List[string]]::new()
$RateRows = [System.Collections.Generic.List[hashtable]]::new()
$RateFiles = @($ratesPath, (Join-Path $scriptsRoot '../references/consumption-rates-template.md'))
foreach ($rateFile in $RateFiles) { foreach ($rateRow in (Get-RateRows $rateFile)) { $RateNames.Add($rateRow.Name); $RateRows.Add($rateRow) } }
if ($RateNames.Count -eq 0) { Stop-Handoff 2 'no rate table can be read (consumption-rates.md or the template); the Squad Scribe seeds it.' }
# Assignment classes (model-routing.md) pick an omitted block's estimator row; an unlisted role is ranked as implementation.
$RoleClassMap = @{}
$routingDoc = Join-Path $scriptsRoot '../references/model-routing.md'
if (Test-Path -LiteralPath $routingDoc -PathType Leaf) {
    $classSection = [regex]::Match([System.IO.File]::ReadAllText($routingDoc), '(?ms)^## Assignment Classes\s*\r?\n(?<body>.*?)(?=^## )').Groups['body'].Value
    foreach ($classLine in ($classSection -split '\r?\n')) {
        $classRow = [regex]::Match($classLine, '^\|\s*`(?<class>[a-z]+)`\s*\|(?<roles>.*)\|\s*$')
        if (-not $classRow.Success) { continue }
        foreach ($roleMatch in [regex]::Matches($classRow.Groups['roles'].Value, '`([a-z][a-z0-9-]*)`')) {
            if (-not $RoleClassMap.ContainsKey($roleMatch.Groups[1].Value)) { $RoleClassMap[$roleMatch.Groups[1].Value] = $classRow.Groups['class'].Value }
        }
    }
}

# Omitted turn, mode, and session model are read from state.json here; the full state validation (and its exit codes) runs below.
$preState = @{ Turn = $null; Mode = $null; SessionModel = $null }
try {
    $preNode = [System.Text.Json.Nodes.JsonNode]::Parse([System.IO.File]::ReadAllText($statePath))
    if ((Get-Kind $preNode) -eq 'Object') {
        $preState.Turn = Get-NodeInt $preNode['turn']
        $preState.Mode = Get-NodeString $preNode['mode']
        if ((Get-Kind $preNode['currentRun']) -eq 'Object') { $preState.SessionModel = Get-NodeString $preNode['currentRun']['sessionModel'] }
    }
}
catch { Write-Verbose "state.json pre-read failed; the state validation below reports it: $($_.Exception.Message)" }

# --- Payload validation ------------------------------------------------------------------------
Test-NodeStrings -Node $payload -Where 'payload'
$null = Test-ObjectKeys -Node $payload -Required @('runId', 'historyRecords', 'stateAdvance') -Optional @('handoff', 'turn', 'mode', 'timestamp', 'route', 'decision', 'since', 'orchestration') -Where 'payload'
if ($problems.Count -gt 0) { Stop-Handoff 1 ("invalid payload: " + ($problems -join ' ')) }
if ($null -ne $payload['handoff'] -and (Get-NodeString $payload['handoff']) -ne 'script') { $problems.Add("payload.handoff must be 'script' (economy-mode.md) when present.") }

$runId = Get-NodeString $payload['runId']
if ($null -eq $runId -or $runId -notmatch '^[A-Za-z0-9._:-]+$') { $problems.Add("payload.runId must match [A-Za-z0-9._:-]+.") }
$turn = $null
if ($null -ne $payload['turn']) {
    $turn = Get-NodeInt $payload['turn']
    if ($null -eq $turn -or $turn -lt 1) { $problems.Add('payload.turn must be a positive integer.') }
}
elseif ($null -ne $preState.Turn) { $turn = $preState.Turn + 1 }
else { $problems.Add('payload.turn was omitted and state.json turn cannot be read.') }
$mode = if ($null -ne $payload['mode']) { Get-NodeString $payload['mode'] } else { $preState.Mode }
if ($mode -notin $Modes) { $problems.Add("payload.mode must be one of: $($Modes -join ', ')$(if ($null -eq $payload['mode']) { '; it was omitted and state.json carries no legal mode' }).") }
$timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
if ($null -ne $payload['timestamp']) {
    $timestamp = Get-NodeString $payload['timestamp']
    if ($null -eq $timestamp -or $timestamp -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$') { $problems.Add('payload.timestamp must be ISO 8601, e.g. 2026-10-04T12:00:00Z.') }
}
$since = $null
if ($null -ne $payload['since']) {
    $since = Get-NodeString $payload['since']
    if ($null -eq $since -or $since -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$') { $problems.Add('payload.since must be ISO 8601 (when this turn''s dispatch began).'); $since = $null }
}
$route = $null
if ($null -ne $payload['route']) {
    $route = Get-TextField -Node $payload -Key 'route' -Where 'payload'
    if ($null -eq $payload['decision']) { $problems.Add('payload.route is recorded in the decision entry; supply decision too.') }
}

$decision = $null
if ($null -ne $payload['decision']) {
    $d = $payload['decision']
    if (Test-ObjectKeys -Node $d -Required @('title', 'rationale', 'adrNoted') -Optional @() -Where 'decision') {
        $decisionTitle = Get-TextField -Node $d -Key 'title' -Where 'decision'
        $decisionRationale = Get-TextField -Node $d -Key 'rationale' -Where 'decision' -MultiLine
        $adr = $d['adrNoted']
        if ((Get-Kind $adr) -notin @('True', 'False')) { $problems.Add('decision.adrNoted must be true or false.') }
        elseif ($null -ne $decisionTitle -and $null -ne $decisionRationale) {
            $decision = @{ Title = $decisionTitle; Rationale = $decisionRationale; Adr = ((Get-Kind $adr) -eq 'True') }
        }
    }
}

# Roster agents (Primary and Alternates) bound the history file names; a slug or role id is refused.
$rosterAgents = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$primaryAgents = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$agentRoles = @{}
$ReviewRoles = @('tester', 'qa-engineer', 'challenger', 'fact-checker', 'supply-chain', 'vuln-manager', 'privacy', 'accessibility', 'risk-manager')
$memberNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$rosterLines = [System.IO.File]::ReadAllLines($teamPath)
$primaryHeaders = 'Agent Name (Primary)', 'Primary Agent', 'Primary', 'Agent'
# The roster is the one table with a Role column and a primary-agent header (the template's exact header wins over a drifted
# spelling); it ends at the first non-table line, so another table earlier or later never admits an agent.
$rosterTables = [System.Collections.Generic.List[hashtable]]::new()
$tableLines = $null
foreach ($line in ($rosterLines + @(''))) {
    if ($line -match '^\s*\|') {
        if ($null -eq $tableLines) { $tableLines = [System.Collections.Generic.List[string]]::new() }
        $tableLines.Add($line)
        continue
    }
    if ($null -eq $tableLines) { continue }
    $headerCells = @($tableLines[0].Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim().Trim('`').Trim() })
    $column = -1
    foreach ($header in $primaryHeaders) { $column = [array]::IndexOf($headerCells, $header); if ($column -ge 0) { break } }
    if ('Role' -in $headerCells -and $column -ge 0) { $rosterTables.Add(@{ Header = $headerCells; Column = $column; Lines = $tableLines }) }
    $tableLines = $null
}
$rosterTable = @($rosterTables | Where-Object { 'Agent Name (Primary)' -in $_.Header }) + @($rosterTables) | Select-Object -First 1
if ($rosterTable) {
    $primaryColumn = $rosterTable.Column
    $alternateColumn = [array]::IndexOf($rosterTable.Header, 'Alternate Agents')
    $memberColumn = [array]::IndexOf($rosterTable.Header, 'Member Name')
    $roleColumn = [array]::IndexOf($rosterTable.Header, 'Role')
    foreach ($line in ($rosterTable.Lines | Select-Object -Skip 1)) {
        $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -le $primaryColumn -or $cells[$primaryColumn] -match '^[-: ]*$') { continue }
        [void]$rosterAgents.Add($cells[$primaryColumn].Trim('`'))
        [void]$primaryAgents.Add($cells[$primaryColumn].Trim('`'))
        $rowRole = if ($cells.Count -gt $roleColumn) { $cells[$roleColumn].Trim('`').ToLowerInvariant() } else { '' }
        $agentRoles[$cells[$primaryColumn].Trim('`')] = $rowRole
        if ($memberColumn -ge 0 -and $cells.Count -gt $memberColumn -and $cells[$memberColumn]) { [void]$memberNames.Add($cells[$memberColumn]) }
        if ($alternateColumn -ge 0 -and $cells.Count -gt $alternateColumn) {
            foreach ($alternate in ($cells[$alternateColumn] -split '[,;]|\s/\s')) {
                $name = $alternate.Trim().Trim('`')
                if ($name -and $name -ne '—' -and $name -ne '-') { [void]$rosterAgents.Add($name); if (-not $agentRoles.ContainsKey($name)) { $agentRoles[$name] = $rowRole } }
            }
        }
    }
}
$derivationSession = $preState.SessionModel
if ((Get-Kind $payload['stateAdvance']) -eq 'Object' -and (Get-Kind $payload['stateAdvance']['sessionModel']) -eq 'String') { $derivationSession = Get-NodeString $payload['stateAdvance']['sessionModel'] }
$records = [System.Collections.Generic.List[hashtable]]::new()
$recordNodes = $payload['historyRecords']
if ((Get-Kind $recordNodes) -ne 'Array') { $problems.Add('payload.historyRecords must be an array (empty when no dispatch was recorded).') }
else {
    $index = 0
    foreach ($node in $recordNodes) {
        $where = "historyRecords[$index]"
        $index++
        if (-not (Test-ObjectKeys -Node $node -Required @('agent', 'request', 'deliverable', 'outcome') -Optional @('consumption', 'title', 'memberName', 'selectionCue', 'passedModel', 'costPreflightRef', 'costPreflightSlot', 'routingIdentity') -Where $where)) { continue }
        $agent = Get-TextField -Node $node -Key 'agent' -Where $where
        $request = Get-TextField -Node $node -Key 'request' -Where $where
        $deliverable = Get-TextField -Node $node -Key 'deliverable' -Where $where
        $outcome = Get-TextField -Node $node -Key 'outcome' -Where $where
        $title = Get-TextField -Node $node -Key 'title' -Where $where -Optional
        $memberName = Get-TextField -Node $node -Key 'memberName' -Where $where -Optional
        $selectionCue = Get-TextField -Node $node -Key 'selectionCue' -Where $where -Optional
        $passedModel = Get-TextField -Node $node -Key 'passedModel' -Where $where -Optional
        $ref = Get-TextField -Node $node -Key 'costPreflightRef' -Where $where -Optional
        $slot = Get-TextField -Node $node -Key 'costPreflightSlot' -Where $where -Optional
        $consumption = $null
        if ($null -ne $node['consumption']) { $consumption = Test-Consumption -Node $node['consumption'] -Where "$where.consumption" }
        if ($consumption -and $consumption['model_source'] -eq 'cli-pinned' -and -not $passedModel) {
            $passedModel = $consumption['model']
            $handoffWarnings.Add("WARN $where.passedModel omitted; recorded as the cli-pinned model '$passedModel'")
        }
        $routing = $null
        if ($null -ne $node['routingIdentity']) {
            if (Test-ObjectKeys -Node $node['routingIdentity'] -Required $RoutingKeys -Optional @() -Where "$where.routingIdentity") {
                $routing = [ordered]@{}
                foreach ($key in $RoutingKeys) { $routing[$key] = Get-TextField -Node $node['routingIdentity'] -Key $key -Where "$where.routingIdentity" }
            }
        }
        if ($null -ne $ref -or $null -ne $slot) { $needsScribe.Add("$where carries a Cost Preflight ref or slot; slot admission and the replay check need the Scribe.") }
        if ($null -eq $agent -or $null -eq $request -or $null -eq $deliverable -or $null -eq $outcome -or ($null -ne $node['consumption'] -and $null -eq $consumption)) { continue }
        if ($agent -eq $ScribeAgent) { $problems.Add("$where.agent must not be '$ScribeAgent'; its orchestration entry is written from payload.orchestration."); continue }
        if ($agent -match '[\\/:*?"<>|=;,]' -or $agent -match '^\.') { $problems.Add("$where.agent '$agent' is not a valid history file name."); continue }
        if (-not $rosterAgents.Contains($agent)) { $needsScribe.Add("$where.agent '$agent' is not an Agent Name (Primary) or Alternate in team.md (history file names are the frontmatter name verbatim).") ; continue }
        if (-not $primaryAgents.Contains($agent) -and -not $selectionCue) { $problems.Add("$where.agent '$agent' is an Alternate; selectionCue must name the cue that selected it.") }
        if ($primaryAgents.Contains($agent) -and $selectionCue) { $problems.Add("$where.selectionCue is only for an Alternate; '$agent' is the Primary.") }
        if ($memberName -and -not $memberNames.Contains($memberName)) { $problems.Add("$where.memberName '$memberName' is not a Member Name in team.md.") }
        if ($null -eq $node['consumption']) {
            $consumption = Get-DerivedConsumption -Agent $agent -PassedModel $passedModel -Where "$where.consumption" -SessionModel $derivationSession
            if ($null -eq $consumption) { continue }
        }
        Test-Attribution -Map $consumption -Where "$where.consumption" -PinAgent $agent -PassedModel $passedModel
        $deliverablePath = ($deliverable -replace '\s+\([^)]*\)\s*$', '').Trim().Trim('`')
        $deliverableSize = if ($deliverable -match '\s+\(([^)]*)\)\s*$') { $Matches[1] } else { $null }
        if ($deliverablePath -match '^(?i)(n/?a|none|inline.*|no artifact.*)$') { $problems.Add("$where.deliverable names no artifact; a stage that wrote no file did not run."); continue }
        $records.Add(@{ Agent = $agent; Title = $(if ($title) { $title } else { $request.Substring(0, [Math]::Min(80, $request.Length)) }); Request = $request; DeliverablePath = $deliverablePath; DeliverableSize = $deliverableSize; Outcome = $outcome; MemberName = $memberName; SelectionCue = $selectionCue; Ref = $ref; Slot = $slot; Consumption = $consumption; Routing = $routing })
    }
}

# economy-mode.md Route Markers: every economy history entry starts its Route rationale with Route: economy or Route: bounded.
foreach ($record in $records) {
    if ($null -eq $record.Routing) {
        $handoffWarnings.Add("WARN $($record.Agent): no routingIdentity; under economy every history entry carries Route: economy (or Route: bounded) in its Route rationale bullet (economy-mode.md Route Markers).")
        continue
    }
    $rationale = $record.Routing['routeRationale']
    if ($null -ne $rationale -and $rationale -notmatch '^Route: ') {
        $marker = if ($route -eq 'bounded') { 'Route: bounded' } else { 'Route: economy' }
        $record.Routing['routeRationale'] = "$marker; $rationale"
        $handoffWarnings.Add("WARN $($record.Agent): routeRationale did not start with a Route marker; recorded as '$marker; ...' (economy-mode.md Route Markers).")
    }
}

$orchestration = $null
$orchNode = $payload['orchestration']
$orchValid = $true
if ($null -ne $orchNode) { $orchValid = Test-ObjectKeys -Node $orchNode -Required @() -Optional @('consumption', 'request', 'outcome', 'passedModel') -Where 'orchestration' }
if ($orchValid) {
    $orchSupplied = ($null -ne $orchNode -and $null -ne $orchNode['consumption'])
    $orchConsumption = $null
    if ($orchSupplied) { $orchConsumption = Test-Consumption -Node $orchNode['consumption'] -Where 'orchestration.consumption' }
    $orchRequest = $null; $orchOutcome = $null; $orchPassed = $null
    if ($null -ne $orchNode) {
        $orchRequest = Get-TextField -Node $orchNode -Key 'request' -Where 'orchestration' -Optional
        $orchOutcome = Get-TextField -Node $orchNode -Key 'outcome' -Where 'orchestration' -Optional
        $orchPassed = Get-TextField -Node $orchNode -Key 'passedModel' -Where 'orchestration' -Optional
    }
    if (-not $orchSupplied) { $orchConsumption = Get-DerivedConsumption -Agent $ScribeAgent -PassedModel $null -Where 'orchestration.consumption' -SessionModel $derivationSession -Orchestration }
    if ($null -ne $orchConsumption) {
        # The orchestration entry is the coordinator's own turns, priced at the session model; the coordinator declares no model: pin.
        if ($orchConsumption['model_source'] -eq 'agent-pinned') { $problems.Add('orchestration.consumption.model_source must not be agent-pinned; the coordinator declares no model: pin. Price its turns at the session model with session-inherited.') }
        else { Test-Attribution -Map $orchConsumption -Where 'orchestration.consumption' -PinAgent $ScribeAgent -PassedModel $orchPassed }
        $orchestration = @{ Consumption = $orchConsumption; Request = $orchRequest; Outcome = $orchOutcome }
    }
}
$stateAdvance = $null
$sa = $payload['stateAdvance']
if (Test-ObjectKeys -Node $sa -Required @('activeRoles') -Optional @('openEscalationsRaised', 'openEscalationsResolved', 'sessionModel', 'modelOverrides') -Where 'stateAdvance') {
    $lists = @{}
    foreach ($key in @('activeRoles', 'openEscalationsRaised', 'openEscalationsResolved')) {
        $lists[$key] = @()
        if ($null -eq $sa[$key]) { continue }
        if ((Get-Kind $sa[$key]) -ne 'Array') { $problems.Add("stateAdvance.$key must be an array of strings."); continue }
        $items = @($sa[$key] | ForEach-Object { Get-NodeString $_ })
        if (@($items | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { $problems.Add("stateAdvance.$key must hold non-empty strings."); continue }
        $lists[$key] = @($items | ForEach-Object { $_.Trim() })
    }
    $sessionModel = $null
    if ($null -ne $sa['sessionModel']) { $sessionModel = Get-TextField -Node $sa -Key 'sessionModel' -Where 'stateAdvance' }
    $overrides = $null
    if ($null -ne $sa['modelOverrides']) {
        if ((Get-Kind $sa['modelOverrides']) -ne 'Object') { $problems.Add('stateAdvance.modelOverrides must be an object of strings.') }
        elseif (@($sa['modelOverrides'] | Where-Object { $null -eq (Get-NodeString $_.Value) }).Count -gt 0) { $problems.Add('stateAdvance.modelOverrides values must be strings.') }
        else { $overrides = $sa['modelOverrides'] }
    }
    $stateAdvance = @{ ActiveRoles = $lists['activeRoles']; Raised = $lists['openEscalationsRaised']; Resolved = $lists['openEscalationsResolved']; SessionModel = $sessionModel; Overrides = $overrides }
}

if ($problems.Count -gt 0) { Stop-Handoff 1 ("invalid payload: " + ($problems -join ' ')) }
if ($needsScribe.Count -gt 0) { Stop-Handoff 2 ("needs the Squad Scribe: " + ($needsScribe -join ' ')) }

# --- State validation ----------------------------------------------------------------------------
try { $stateBytes = [System.IO.File]::ReadAllBytes($statePath) }
catch { Stop-Handoff 3 "cannot read state.json ($($_.Exception.Message)); nothing was changed." }
$stateHasBom = ($stateBytes.Length -ge 3 -and $stateBytes[0] -eq 0xEF -and $stateBytes[1] -eq 0xBB -and $stateBytes[2] -eq 0xBF)
$stateText = [System.Text.UTF8Encoding]::new($false).GetString($stateBytes).TrimStart([char]0xFEFF)
try { $state = [System.Text.Json.Nodes.JsonNode]::Parse($stateText) }
catch { Stop-Handoff 1 "state.json is not valid JSON: $($_.Exception.Message)" }
if ((Get-Kind $state) -ne 'Object') { Stop-Handoff 1 'state.json is not an object.' }
foreach ($key in @('schemaVersion', 'updated', 'turn', 'mode', 'activeRoles', 'openEscalations', 'currentRun', 'notify')) {
    if ($null -eq $state[$key]) { Stop-Handoff 2 "state.json lacks '$key'; the Squad Scribe repairs state." }
}
if ($null -ne $state['subSquads']) { Stop-Handoff 2 'federation state needs the Squad Scribe.' }
$schemaVersion = Get-NodeString $state['schemaVersion']
if ($schemaVersion -notin '1.3', '1.4') { Stop-Handoff 2 "state.json schemaVersion '$schemaVersion' needs the Squad Scribe to upgrade it to 1.4." }
$run = $state['currentRun']
if ((Get-Kind $run) -ne 'Object') { Stop-Handoff 2 "state.json currentRun is not an object; the Squad Scribe repairs state." }
# entry-schemas.md: state without costPreflight reads as an unset ceiling; add the exact default and bump only 1.3 to 1.4.
if ($null -ne $run['costPreflight'] -and (Get-Kind $run['costPreflight']) -ne 'Object') { Stop-Handoff 2 'state.json currentRun.costPreflight is not an object; the Squad Scribe repairs state.' }
if ($null -eq $run['costPreflight']) {
    $run['costPreflight'] = [System.Text.Json.Nodes.JsonNode]::Parse('{"runId":"","roundId":"","ceilingUsd":null,"evaluatedSpendUsd":0,"remainingUsd":null,"plannedDispatches":0,"projectedCostUsd":0,"reserveMultiplier":3.0,"admissionCostUsd":0,"confidence":"not-applicable","basis":"not-requested","decision":"not-requested","reason":"No cost ceiling configured."}')
    if ($schemaVersion -eq '1.3') { $state['schemaVersion'] = '1.4' }
}
elseif ($schemaVersion -ne '1.4') { Stop-Handoff 2 "state.json schemaVersion '$schemaVersion' needs the Squad Scribe to upgrade it to 1.4." }
foreach ($key in @('sessionModel', 'modelOverrides', 'estCostUsd', 'estCreditsTotal', 'costPreflight')) {
    if ($null -eq $run[$key]) { Stop-Handoff 2 "state.json currentRun lacks '$key'; the Squad Scribe repairs state." }
}
$preflight = $run['costPreflight']
if ($null -ne $preflight['ceilingUsd'] -or (Get-NodeString $preflight['decision']) -ne 'not-requested') {
    Stop-Handoff 2 'a cost ceiling is configured; a ceiling-admitted hand-off (slot and replay checks) needs the Squad Scribe.'
}
$stateTurn = Get-NodeInt $state['turn']
if ($null -eq $stateTurn -or $turn -ne ($stateTurn + 1)) { Stop-Handoff 1 "payload.turn $turn must equal state.json turn + 1 ($stateTurn + 1); a replayed or stale payload writes nothing." }
if ($stateAdvance.Resolved.Count -gt 0 -and @($state['openEscalations'] | Where-Object { $null -eq (Get-NodeString $_) }).Count -gt 0) {
    Stop-Handoff 2 'openEscalations holds non-string entries; resolving them needs the Squad Scribe.'
}

# session-inherited orchestration is priced at the coordinator's session model: this payload's, else the state's.
if ($orchestration.Consumption['model_source'] -eq 'session-inherited') {
    $effectiveSession = if ($stateAdvance.SessionModel) { $stateAdvance.SessionModel } else { Get-NodeString $run['sessionModel'] }
    if ($effectiveSession -and (ConvertFrom-ModelPin $orchestration.Consumption['model']) -ne (ConvertFrom-ModelPin $effectiveSession)) {
        $problems.Add("orchestration.consumption.model '$($orchestration.Consumption['model'])' must equal the coordinator's session model '$effectiveSession' for session-inherited.")
    }
}
if ($problems.Count -gt 0) { Stop-Handoff 1 ("invalid payload: " + ($problems -join ' ')) }

# The timestamp must not precede the last hand-off.
$payloadTime = [DateTimeOffset]::Parse($timestamp, [System.Globalization.CultureInfo]::InvariantCulture)
$lastHandoff = [DateTimeOffset]::MinValue
$stateUpdated = Get-NodeString $state['updated']
if ($payloadTime -gt $futureLimit -or ($since -and [DateTimeOffset]::Parse($since, [System.Globalization.CultureInfo]::InvariantCulture) -gt $futureLimit)) {
    Stop-Handoff 1 'timestamp is in the future; stamp with the current UTC time (payload.timestamp and since may not be more than 120 s ahead of now).'
}
if ($stateUpdated -and [DateTimeOffset]::TryParse($stateUpdated, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$lastHandoff) -and (Test-FutureStamp $stateUpdated $lastHandoff 'state.json')) { $lastHandoff = [DateTimeOffset]::MinValue }
if ($lastHandoff -gt [DateTimeOffset]::MinValue) {
    if ($payloadTime -lt $lastHandoff) { Stop-Handoff 1 "payload.timestamp $timestamp precedes state.json updated $stateUpdated; entries stay in chronological order." }
}

# A deliverable is a file inside the repository (or the squad root when it sits outside .copilot-tracking) that this turn modified:
# newer than `since` (the dispatch start, which a parallel wave passes) or, by default, the previous hand-off.
# When another hand-off landed while this one waited on the lock, this turn still began at the state.json
# updated read before the wait: its deliverables predate the other hand-off and are not stale.
$turnFloor = $lastHandoff
$landedWhileWaiting = $false
$preWaitTime = [DateTimeOffset]::MinValue
if ($preWaitUpdated -and [DateTimeOffset]::TryParse($preWaitUpdated, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$preWaitTime) -and $preWaitTime -lt $lastHandoff -and $preWaitTime -le $futureLimit) {
    $turnFloor = $preWaitTime
    $landedWhileWaiting = $true
}
$freshAfter = if ($since) { [DateTimeOffset]::Parse($since, [System.Globalization.CultureInfo]::InvariantCulture) } else { $turnFloor }
if ($since) {
    # since is bounded to this turn: not before the previous hand-off (state.json updated as this hand-off found it), not after this one.
    if ($freshAfter -lt $turnFloor) { $problems.Add("payload.since $since precedes state.json updated $(if ($landedWhileWaiting) { $preWaitUpdated } else { $stateUpdated }); since must fall within this turn.") }
    if ($freshAfter -gt $payloadTime) { $problems.Add("payload.since $since is after payload.timestamp $timestamp.") }
}
# A deliverable is credited once: the hand-off that landed while this one waited may already have recorded it.
$creditedWhileWaiting = @()
if ($landedWhileWaiting) {
    foreach ($historyFile in @(Get-ChildItem -LiteralPath $historyDir -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
        $historyText = [System.Text.UTF8Encoding]::new($false).GetString([System.IO.File]::ReadAllBytes($historyFile.FullName))
        foreach ($chunk in ([regex]::Split($historyText, '(?m)^(?=###[ \t]+\d{4}-)') | Where-Object { $_ -match '^###[ \t]+\d{4}-' })) {
            $entryTime = [DateTimeOffset]::MinValue
            if (-not [DateTimeOffset]::TryParse([regex]::Match($chunk, '^###[ \t]+(\S+)').Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$entryTime)) { continue }
            if ($entryTime -le $turnFloor) { continue }
            foreach ($deliverableLineMatch in [regex]::Matches($chunk, '(?m)^\* Deliverable:(.*)$')) {
                foreach ($pathMatch in [regex]::Matches($deliverableLineMatch.Groups[1].Value, '`([^`]+)`')) {
                    $creditedWhileWaiting += , @{ Path = (($pathMatch.Groups[1].Value -replace '\\', '/').Trim() -replace '^\./', '').ToLowerInvariant(); Time = $entryTime; File = $historyFile.Name }
                }
            }
        }
    }
}
$deliverableBase = if ($RepoBase) { $RepoBase } else { ConvertTo-NormalPath $SquadRoot }
foreach ($record in $records) {
    $resolved = $null
    foreach ($base in @($RepoBase, $SquadRoot) | Where-Object { $_ }) {
        $candidate = ConvertTo-NormalPath ([System.IO.Path]::Combine($base, $record.DeliverablePath))
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $resolved = $candidate; break }
    }
    if (-not $resolved) { $problems.Add("deliverable '$($record.DeliverablePath)' for $($record.Agent) is not an existing file; a stage without its artifact did not run."); continue }
    $inside = $resolved.StartsWith($deliverableBase.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $inside) { $problems.Add("deliverable '$($record.DeliverablePath)' for $($record.Agent) resolves outside the repository."); continue }
    if ($freshAfter -gt [DateTimeOffset]::MinValue -and [DateTimeOffset]::new([System.IO.File]::GetLastWriteTimeUtc($resolved), [TimeSpan]::Zero) -lt $freshAfter) {
        $problems.Add("deliverable '$($record.DeliverablePath)' for $($record.Agent) was last modified before this turn began ($freshAfter); a stage that wrote nothing this turn did not run. In a parallel wave pass payload.since.")
    }
    # An entry stamped before its own artifact existed claims a dispatch that had not finished.
    $modified = [DateTimeOffset]::new([System.IO.File]::GetLastWriteTimeUtc($resolved), [TimeSpan]::Zero)
    $record.Modified = $modified
    $record.ResolvedPath = $resolved
    $waitKey = (($record.DeliverablePath -replace '\\', '/').Trim() -replace '^\./', '').ToLowerInvariant()
    foreach ($earlier in @($creditedWhileWaiting | Where-Object { $_.Path -eq $waitKey -and $_.Time.AddSeconds(5) -ge $modified })) {
        $problems.Add("deliverable '$($record.DeliverablePath)' for $($record.Agent) was already credited in history/$($earlier.File) at $($earlier.Time.ToString('o')) by the hand-off that landed while this one waited for the lock, and has not changed since; a deliverable is credited once. Drop the record, or re-dispatch the stage that rewrites it.")
        break
    }
    if ($payloadTime -lt $modified.AddSeconds(-5)) { $problems.Add("payload.timestamp $timestamp precedes the last write of deliverable '$($record.DeliverablePath)' for $($record.Agent) ($($modified.ToString('o'))); stamp the hand-off at or after its artifacts.") }
}
if ($problems.Count -gt 0) { Stop-Handoff 1 ("invalid payload: " + ($problems -join ' ')) }

# Review-saw-final-files: no owner deliverable may change after the closing review's own deliverable.
$reviewRecords = @($records | Where-Object { $agentRoles[$_.Agent] -in $ReviewRoles -and $_.Modified })
if ($reviewRecords.Count -gt 0) {
    $reviewTime = ($reviewRecords | ForEach-Object { $_.Modified } | Sort-Object | Select-Object -Last 1)
    foreach ($record in @($records | Where-Object { $agentRoles[$_.Agent] -notin $ReviewRoles -and $_.Modified })) {
        if ($record.Modified -gt $reviewTime.AddSeconds(2)) {
            Stop-Handoff 1 "owner deliverable $($record.DeliverablePath) changed after the closing review; re-dispatch the review on the final files before the hand-off. Editing the payload does not clear this; re-dispatch the review, then rerun."
        }
    }
}

# --- Plan the writes ----------------------------------------------------------------------------
$originals = [System.Collections.Generic.List[hashtable]]::new()
$written = [System.Collections.Generic.List[string]]::new()
$script:OwnedHash = @{}
function Register-Original {
    param([string]$FullPath)
    if ($originals.Where({ $_.Path -eq $FullPath }).Count -gt 0) { return }
    $bytes = if (Test-Path -LiteralPath $FullPath -PathType Leaf) { [System.IO.File]::ReadAllBytes($FullPath) } else { $null }
    $originals.Add(@{ Path = $FullPath; Bytes = $bytes })
}
function Restore-Originals {
    # Restores only files whose bytes differ from the original and still equal what this run last wrote;
    # $script:RestoredCount counts restores, $script:ForeignChanges names files another writer changed.
    $failed = @()
    $script:RestoredCount = 0
    $script:ForeignChanges = [System.Collections.Generic.List[string]]::new()
    $reversed = @($originals)
    [array]::Reverse($reversed)
    foreach ($entry in $reversed) {
        try {
            $exists = Test-Path -LiteralPath $entry.Path
            if ($exists -and (Test-Path -LiteralPath $entry.Path -PathType Leaf) -and $script:OwnedHash.ContainsKey($entry.Path)) {
                $current = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($entry.Path)))
                if ($current -ne $script:OwnedHash[$entry.Path]) { $script:ForeignChanges.Add($entry.Path); continue }
            }
            if ($null -eq $entry.Bytes) {
                if ($exists) { Remove-Item -LiteralPath $entry.Path -Force -Recurse; $script:RestoredCount++ }
                continue
            }
            if ($exists -and [System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes($entry.Path), [byte[]]$entry.Bytes)) { continue }
            Write-FileAtomic -FullPath $entry.Path -Bytes $entry.Bytes
            $script:RestoredCount++
        }
        catch { $failed += "$($entry.Path): $($_.Exception.Message)" }
    }
    return $failed
}
function Stop-WithRollback {
    param([int]$Code, [string]$Message)
    $failed = @(Restore-Originals)
    $suffix = if ($failed.Count -gt 0) { " RESTORE FAILED for: $($failed -join '; ')" }
    elseif ($script:RestoredCount -gt 0) { " $($script:RestoredCount) changed file(s) restored to their original bytes." }
    else { ' No file had been changed.' }
    if ($script:ForeignChanges.Count -gt 0) { $suffix += " Left as found, changed by another writer since this run wrote them: $($script:ForeignChanges -join '; ')." }
    Stop-Handoff $Code "$Message$suffix"
}

function Get-FileText {
    param([string]$FullPath)
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) { return $null }
    return [System.Text.UTF8Encoding]::new($false).GetString([System.IO.File]::ReadAllBytes($FullPath)).TrimStart([char]0xFEFF)
}

function Get-NewlineOf {
    param([string]$Text)
    if ($null -ne $Text -and $Text.Contains("`r`n")) { return "`r`n" }
    return "`n"
}

function Get-EntryCount {
    param([string]$Text)
    if ($null -eq $Text) { return 0 }
    return @([regex]::Matches($Text, '(?m)^###[ \t]+\S')).Count
}

function Get-HistoryHeader {
    param([string]$Agent)
    return @(
        '---',
        'description: "Append-only dispatch history for a single squad agent"',
        '---',
        '',
        "# History: $Agent",
        '',
        'Each entry records a request this agent handled, the findings or outcome it returned, and the turn it was dispatched on. Entries are appended in chronological order and never edited.',
        '',
        '<!-- Append each new dispatch entry at the end of this file, after the last entry. -->'
    )
}

function Add-ToTextFile {
    # Appends $EntryLines to a file (creating it from $HeaderLines when absent); returns the entry count added.
    param([string]$FullPath, [string[]]$EntryLines, [string[]]$HeaderLines)
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    if (Test-Path -LiteralPath $FullPath -PathType Leaf) {
        # Append only: the original bytes (BOM, line endings, trailing content) stay exactly as they were.
        $original = [System.IO.File]::ReadAllBytes($FullPath)
        $newline = Get-NewlineOf ($utf8.GetString($original))
        $addition = ''
        if ($original.Length -gt 0 -and $original[$original.Length - 1] -ne 10) { $addition = $newline }
        $addition += $newline + ($EntryLines -join $newline) + $newline
        $stream = [System.IO.MemoryStream]::new()
        $stream.Write($original, 0, $original.Length)
        $tail = $utf8.GetBytes($addition)
        $stream.Write($tail, 0, $tail.Length)
        Write-FileAtomic -FullPath $FullPath -Bytes $stream.ToArray()
        return
    }
    $body = ($HeaderLines -join "`n") + "`n" + "`n" + ($EntryLines -join "`n") + "`n"
    Write-FileAtomic -FullPath $FullPath -Bytes ($utf8.GetBytes($body))
}

$expectedCounts = [ordered]@{}
# consumption.md is derived from history. A file with none of the ledger headings Measure-SquadLedger recognizes is reseeded;
# a partial or hand-maintained ledger is the Scribe's to repair, never overwritten here.
$ledgerMarkers = @('(?m)^##\s+Attribution\s*$', '(?m)^##\s+Usage & Cost\s*$', '(?m)^###\s+Derivation\s*$')
$ledgerBefore = Get-FileText $consumptionPath
$markersPresent = @($ledgerMarkers | Where-Object { $ledgerBefore -match $_ }).Count
if ($markersPresent -gt 0 -and $markersPresent -lt $ledgerMarkers.Count) { Stop-Handoff 2 'consumption.md has some but not all of its ledger headings (Attribution, Usage & Cost, Derivation); the Squad Scribe repairs it. Nothing was written.' }
$reseedLedger = ($markersPresent -eq 0)
$entryPlans = [System.Collections.Generic.List[hashtable]]::new()
foreach ($record in $records) {
    $heading = "$timestamp $($record.Title)"
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("### $heading"); $lines.Add('')
    $lines.Add("* Turn: $turn")
    $lines.Add("* Request: $($record.Request)")
    $deliverableLine = '`' + $record.DeliverablePath + '`'
    if ($record.DeliverableSize) { $deliverableLine += " ($($record.DeliverableSize))" }
    $lines.Add("* Deliverable: $deliverableLine")
    $lines.Add("* Outcome: $($record.Outcome)")
    if ($record.MemberName) { $lines.Add("* Member Name: $($record.MemberName)") }
    if ($record.SelectionCue) { $lines.Add("* Selection Cue: $($record.SelectionCue)") }
    if ($record.Ref) { $lines.Add('* Cost Preflight Ref: `' + $record.Ref + '`'); $lines.Add("* Cost Preflight Slot: $($record.Slot)") }
    $lines.Add('')
    foreach ($l in (ConvertTo-ConsumptionBlock -Map $record.Consumption -Orchestration $false)) { $lines.Add($l) }
    if ($record.Routing) {
        $lines.Add('')
        $lines.Add("* **Requested model** — $($record.Routing['requestedModel'])")
        $lines.Add("* **Effective model** — $($record.Routing['effectiveModel'])")
        $lines.Add("* **Observed model** — $($record.Routing['observedModel'])")
        $lines.Add("* **Route rationale** — $($record.Routing['routeRationale'])")
    }
    $entryPlans.Add(@{ Agent = $record.Agent; Heading = $heading; Lines = $lines })
}

$decisionHeading = $null
$decisionLines = $null
if ($decision) {
    $decisionHeading = "$timestamp $($decision.Title)"
    $decisionLines = [System.Collections.Generic.List[string]]::new()
    $decisionLines.Add("## $decisionHeading"); $decisionLines.Add('')
    $decisionLines.Add("* Turn: $turn")
    if ($route) { $decisionLines.Add("* Route: $route") }
    if ($decision.Rationale.Contains("`n")) {
        $decisionLines.Add('* Rationale:'); $decisionLines.Add('')
        foreach ($l in ($decision.Rationale -split "`n")) { $decisionLines.Add($l) }
    }
    else { $decisionLines.Add("* Rationale: $($decision.Rationale)") }
    if ($decision.Adr) { $decisionLines.Add(''); $decisionLines.Add('* ADR: architecturally significant; the coordinator captures it via the `adr-author` skill and references it here.') }
}

$deliverableList = [System.Collections.Generic.List[string]]::new()
if ($decision) { $deliverableList.Add('`decisions.md`') }
$deliverableList.Add('`state.json`'); $deliverableList.Add('`consumption.md`')
foreach ($agent in @($entryPlans | ForEach-Object { $_.Agent } | Select-Object -Unique)) { $deliverableList.Add('`history/' + $agent + '.md`') }
$orchHeading = "$timestamp Coordinator hand-off, turn $turn"
$orchLines = [System.Collections.Generic.List[string]]::new()
$orchLines.Add("### $orchHeading"); $orchLines.Add('')
$orchLines.Add("* Turn: $turn")
$orchLines.Add("* Request: $(if ($orchestration.Request) { $orchestration.Request } else { 'Coordinator hand-off recorded by the Squad Scribe through scripts/Write-SquadHandoff.ps1.' })")
$orchLines.Add("* Deliverable: $($deliverableList -join ', ')")
$orchLines.Add("* Outcome: $(if ($orchestration.Outcome) { $orchestration.Outcome } else { "Recorded $($entryPlans.Count) dispatch entr$(if ($entryPlans.Count -eq 1) { 'y' } else { 'ies' }) and advanced state." })")
$orchLines.Add('')
foreach ($l in (ConvertTo-ConsumptionBlock -Map $orchestration.Consumption -Orchestration $true)) { $orchLines.Add($l) }

# Replay guard and pre-write counts.
$historyTargets = [ordered]@{}
foreach ($plan in $entryPlans) { if (-not $historyTargets.Contains($plan.Agent)) { $historyTargets[$plan.Agent] = [System.Collections.Generic.List[hashtable]]::new() }; $historyTargets[$plan.Agent].Add($plan) }
if (-not $historyTargets.Contains($ScribeAgent)) { $historyTargets[$ScribeAgent] = [System.Collections.Generic.List[hashtable]]::new() }
$historyTargets[$ScribeAgent].Add(@{ Agent = $ScribeAgent; Heading = $orchHeading; Lines = $orchLines })
foreach ($agent in $historyTargets.Keys) {
    try { $existing = Get-FileText (Join-Path $historyDir "$agent.md") }
    catch { Stop-Handoff 3 "cannot read history/$agent.md ($($_.Exception.Message)); nothing was changed." }
    $expectedCounts[$agent] = (Get-EntryCount $existing) + $historyTargets[$agent].Count
    $lastEntry = Get-LastEntryTimestamp -Text $existing -HeadingPrefix '###' -Where "history/$agent.md"
    if ($null -ne $lastEntry -and $payloadTime -lt $lastEntry) { Stop-Handoff 1 "payload.timestamp $timestamp precedes the last entry in history/$agent.md ($lastEntry); entries stay in chronological order." }
    foreach ($plan in $historyTargets[$agent]) {
        if ($null -ne $existing -and [regex]::IsMatch($existing, '(?m)^###[ \t]+' + [regex]::Escape($plan.Heading) + '[ \t]*\r?$')) {
            Stop-Handoff 1 "history/$agent.md already holds '### $($plan.Heading)'; a replayed payload writes nothing."
        }
    }
}
if ($decisionHeading) {
    try { $existingDecisions = Get-FileText $decisionsPath }
    catch { Stop-Handoff 3 "cannot read decisions.md ($($_.Exception.Message)); nothing was changed." }
    $lastDecision = Get-LastEntryTimestamp -Text $existingDecisions -HeadingPrefix '##' -Where 'decisions.md'
    if ($null -ne $lastDecision -and $payloadTime -lt $lastDecision) { Stop-Handoff 1 "payload.timestamp $timestamp precedes the last entry in decisions.md ($lastDecision); entries stay in chronological order." }
    if ([regex]::IsMatch($existingDecisions, '(?m)^## ' + [regex]::Escape($decisionHeading) + '[ \t]*\r?$')) { Stop-Handoff 1 "decisions.md already holds '## $decisionHeading'; a replayed payload writes nothing." }
}

# --- Rate table (before any append so a refusal writes nothing) -----------------------------------
$ratesScript = Join-Path $scriptsRoot 'Initialize-SquadConsumptionRates.ps1'
$ledgerScript = Join-Path $scriptsRoot 'Measure-SquadLedger.ps1'
foreach ($dependency in @($ratesScript, $ledgerScript)) { if (-not (Test-Path -LiteralPath $dependency -PathType Leaf)) { Stop-Handoff 1 "missing sibling script $dependency." } }

Register-Original $ratesPath
$ratesCheck = Invoke-ChildScript -ScriptPath $ratesScript -Arguments @('-SquadRoot', $SquadRoot, '-Check', '-Mode', 'economy')
if ($ratesCheck.ExitCode -ne 0) {
    $seed = Invoke-ChildScript -ScriptPath $ratesScript -Arguments @('-SquadRoot', $SquadRoot, '-Mode', 'economy')
    Update-OwnedHash $ratesPath
    if ($seed.ExitCode -ne 0) {
        $failed = @(Restore-Originals)
        Stop-Handoff 4 "the rate table needs an operator decision (never -DropMalformedRows from here): $($seed.Text)$(if ($failed.Count -gt 0) { " RESTORE FAILED: $($failed -join '; ')" })"
    }
    $written.Add('WROTE consumption-rates.md (reseeded from the template)')
}

# --- Writes -----------------------------------------------------------------------------------------
$ledgerWarnings = ''
try {
    if (-not (Test-Path -LiteralPath $historyDir -PathType Container)) { Register-Original $historyDir; New-Item -ItemType Directory -Path $historyDir -Force | Out-Null }
    foreach ($agent in $historyTargets.Keys) {
        $file = Join-Path $historyDir "$agent.md"
        Register-Original $file
        foreach ($plan in $historyTargets[$agent]) { Add-ToTextFile -FullPath $file -EntryLines $plan.Lines -HeaderLines (Get-HistoryHeader $agent) }
        $written.Add("WROTE history/$agent.md (+$($historyTargets[$agent].Count) entr$(if ($historyTargets[$agent].Count -eq 1) { 'y' } else { 'ies' }))")
    }
    if ($decisionLines) {
        Register-Original $decisionsPath
        Add-ToTextFile -FullPath $decisionsPath -EntryLines $decisionLines -HeaderLines @()
        $written.Add('WROTE decisions.md (+1 decision)')
    }

    Register-Original $statePath
    $expectedState = $state.DeepClone()
    $expectedState['updated'] = [System.Text.Json.Nodes.JsonValue]::Create($timestamp)
    $expectedState['turn'] = [System.Text.Json.Nodes.JsonValue]::Create([long]$turn)
    $expectedState['mode'] = [System.Text.Json.Nodes.JsonValue]::Create($mode)
    $roles = [System.Text.Json.Nodes.JsonArray]::new()
    foreach ($role in $stateAdvance.ActiveRoles) { $roles.Add([System.Text.Json.Nodes.JsonValue]::Create($role)) }
    $expectedState['activeRoles'] = $roles
    $open = [System.Text.Json.Nodes.JsonArray]::new()
    foreach ($item in $state['openEscalations']) {
        $text = Get-NodeString $item
        if ($null -ne $text -and $text -in $stateAdvance.Resolved) { continue }
        $open.Add($item.DeepClone())
    }
    foreach ($item in $stateAdvance.Raised) { if (@($open | Where-Object { (Get-NodeString $_) -eq $item }).Count -eq 0) { $open.Add([System.Text.Json.Nodes.JsonValue]::Create($item)) } }
    $expectedState['openEscalations'] = $open
    if ($stateAdvance.SessionModel) { $expectedState['currentRun']['sessionModel'] = [System.Text.Json.Nodes.JsonValue]::Create($stateAdvance.SessionModel) }
    if ($null -ne $stateAdvance.Overrides) { $expectedState['currentRun']['modelOverrides'] = [System.Text.Json.Nodes.JsonNode]::Parse($stateAdvance.Overrides.ToJsonString()) }
    $serializer = [System.Text.Json.JsonSerializerOptions]::new()
    $serializer.WriteIndented = $true
    $serializer.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
    $stateNewline = Get-NewlineOf $stateText
    $newState = ($expectedState.ToJsonString($serializer) -replace "`r`n", "`n").Replace("`n", $stateNewline)
    if ($stateText.EndsWith("`n")) { $newState += $stateNewline }
    $stateOut = [System.Text.UTF8Encoding]::new($false).GetBytes($newState)
    if ($stateHasBom) { $stateOut = [byte[]](@(0xEF, 0xBB, 0xBF) + $stateOut) }
    Write-FileAtomic -FullPath $statePath -Bytes $stateOut
    $written.Add('WROTE state.json (turn, updated, mode, activeRoles, openEscalations)')

    Register-Original $consumptionPath
    # consumption.md is derived from history; a file with none of the ledger's headings was classified above and is re-seeded from the template.
    if ($reseedLedger) {
        $templateText = [System.IO.File]::ReadAllText((Join-Path $scriptsRoot '../references/consumption.md'))
        $seed = [regex]::Match($templateText, '(?s)````markdown\r?\n(.*?)\r?\n````').Groups[1].Value
        if (-not $seed) { throw 'consumption.md lacks the ledger sections and the consumption.md template block could not be read.' }
        $seed = $seed.Replace('<run-id>', $runId) -replace "`r`n", "`n"
        Write-FileAtomic -FullPath $consumptionPath -Bytes ([System.Text.UTF8Encoding]::new($false).GetBytes($seed + "`n"))
        $written.Add('RESEEDED consumption.md from the references/consumption.md template (it lacked the ledger sections)')
    }
    $ledger = Invoke-ChildScript -ScriptPath $ledgerScript -Arguments @('-SquadRoot', $SquadRoot, '-Write', '-SessionLog', $SessionLog)
    Update-OwnedHash $consumptionPath, $statePath
    if ($ledger.ExitCode -ne 0) { throw "Measure-SquadLedger -Write failed: $($ledger.Text)" }
    $written.Add("WROTE consumption.md ($(($ledger.Text -split "`n" | Select-Object -Last 1).Trim()))")

    # The ledger helper leaves the heading run id and the Cost Comparison section as written. The seed placeholder and this script's own
    # squad-figure line are replaced; a full comparison keeps its manual baseline and gets its squad figures and saving recomputed.
    $afterState = [System.Text.Json.Nodes.JsonNode]::Parse((Get-FileText $statePath))
    $cost = [double]::Parse($afterState['currentRun']['estCostUsd'].ToJsonString(), [System.Globalization.CultureInfo]::InvariantCulture)
    $credits = [double]::Parse($afterState['currentRun']['estCreditsTotal'].ToJsonString(), [System.Globalization.CultureInfo]::InvariantCulture)
    $agentCount = @(Get-ChildItem -LiteralPath $historyDir -Filter '*.md' -File | Where-Object { $_.BaseName -ne $ScribeAgent -and $_.Name -notmatch '^(autonomous-loop|autopilot-run)-' }).Count
    $ledgerBytes = [System.IO.File]::ReadAllBytes($consumptionPath)
    $ledgerHasBom = ($ledgerBytes.Length -ge 3 -and $ledgerBytes[0] -eq 0xEF -and $ledgerBytes[1] -eq 0xBB -and $ledgerBytes[2] -eq 0xBF)
    $ledgerText = Get-FileText $consumptionPath
    $ledgerText = [regex]::Replace($ledgerText, '(?m)^# Squad Consumption Ledger \(Run: [^)\r\n]*\)', "# Squad Consumption Ledger (Run: $runId)")
    $comparison = 'This run consumed an estimated **${0} (~{1} AI credits)** across {2} specialized agent(s) (squad figure only; the host-reported comparison is in Observed Usage when a session log exists).' -f $cost.ToString('F4', [System.Globalization.CultureInfo]::InvariantCulture), $credits.ToString('F2', [System.Globalization.CultureInfo]::InvariantCulture), $agentCount
    $comparisonPattern = '(?m)^(?:This run has not yet dispatched|This run consumed an estimated \*\*\$<squad-cost>|This run consumed an estimated [^\r\n]*\(squad figure only;)[^\r\n]*'
    $comparisonRefreshed = [regex]::IsMatch($ledgerText, $comparisonPattern)
    if ($comparisonRefreshed) { $ledgerText = [regex]::Replace($ledgerText, $comparisonPattern, { param($m) $comparison }) }
    else {
        # A full comparison keeps its manual baseline; its squad figures and the saving percentage are recomputed from the new total.
        $invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
        $figure = '\*\*\$[0-9][0-9,]*(?:\.\d+)? \(~[0-9][0-9,]*(?:\.\d+)? AI credits\)\*\*'
        $fullMatch = [regex]::Match($ledgerText, "(?m)^This run consumed an estimated $figure[^\r\n]*")
        if ($fullMatch.Success -and $ledgerText -notmatch '(?m)^#{2,3}\s+Observed Usage') {
            $squadFigure = '**${0} (~{1} AI credits)**' -f $cost.ToString('F4', $invariantCulture), $credits.ToString('F2', $invariantCulture)
            $line = [regex]::Replace($fullMatch.Value, "^This run consumed an estimated $figure", { param($m) "This run consumed an estimated $squadFigure" })
            $line = $line -replace ' \(stale — refreshed at run end\)$', ''
            $baseline = [regex]::Match($line, 'estimated at \*\*\$(?<m>[0-9][0-9,]*(?:\.\d+)?) \(~[0-9][0-9,]*(?:\.\d+)? AI credits\)\*\*(?<mid>[^*]*?)about \*\*(?<p>\d+(?:\.\d+)?)%\*\*')
            if ($baseline.Success) {
                $manual = [double]::Parse($baseline.Groups['m'].Value.Replace(',', ''), $invariantCulture)
                if ($manual -gt 0 -and $manual -ge $cost) {
                    $decimals = if ($baseline.Groups['p'].Value.Contains('.')) { $baseline.Groups['p'].Value.Split('.')[1].Length } else { 0 }
                    $saving = (100.0 * ($manual - $cost) / $manual).ToString("F$decimals", $invariantCulture)
                    $line = $line.Substring(0, $baseline.Groups['p'].Index) + $saving + $line.Substring($baseline.Groups['p'].Index + $baseline.Groups['p'].Length)
                }
                else { $line += ' (stale — refreshed at run end)' }
            }
            $ledgerText = $ledgerText.Substring(0, $fullMatch.Index) + $line + $ledgerText.Substring($fullMatch.Index + $fullMatch.Length)
            $comparisonRefreshed = $true
        }
        elseif ($fullMatch.Success) { $comparisonRefreshed = $true }
    }
    if (-not $comparisonRefreshed) {
        # No Cost Comparison section at all: append the template's section with this script's own squad-figure line.
        $templateForComparison = [System.IO.File]::ReadAllText((Join-Path $scriptsRoot '../references/consumption.md'))
        $estimatesNote = [regex]::Match($templateForComparison, '(?m)^> Estimates only\.[^\r\n]*').Value
        $nl = Get-NewlineOf $ledgerText
        $section = "## Cost Comparison (illustrative)$nl$nl$comparison$nl"
        if ($estimatesNote) { $section += "$nl$estimatesNote$nl" }
        $ledgerText = $ledgerText.TrimEnd() + "$nl$nl" + $section
        $comparisonRefreshed = $true
        $written.Add('APPENDED Cost Comparison section to consumption.md')
    }
    $ledgerOut = [System.Text.UTF8Encoding]::new($false).GetBytes($ledgerText)
    if ($ledgerHasBom) { $ledgerOut = [byte[]](@(0xEF, 0xBB, 0xBF) + $ledgerOut) }
    Write-FileAtomic -FullPath $consumptionPath -Bytes $ledgerOut

    $countsArgument = (@($expectedCounts.Keys | ForEach-Object { "$_=$($expectedCounts[$_])" })) -join ';'
    $check = Invoke-ChildScript -ScriptPath $ledgerScript -Arguments @('-SquadRoot', $SquadRoot, '-Check', '-ExpectedHistoryCounts', $countsArgument)
    $ledgerOnly = $null
    if ($check.ExitCode -ne 0) {
        # v0.18.1: only a history-integrity failure stops; a ledger-only mismatch is cost accounting the next -Write re-derives.
        $failureClass = [regex]::Match($check.Text, '(?m)Measure-SquadLedger -Check: failure class: (?<class>[a-z-]+)').Groups['class'].Value
        if ($failureClass -ne 'ledger-only') { throw "Measure-SquadLedger -Check failed (failure class: $(if ($failureClass) { $failureClass } else { 'none reported' })): $($check.Text)" }
        $firstMismatches = @($check.Text -split "`n" | Where-Object { $_ -match '^\s+- ' } | Select-Object -First 3 | ForEach-Object { ($_ -replace '^\s+- ', '').Trim() })
        $ledgerOnly = "WARN ledger-only: $($firstMismatches -join ' | ') (writes kept; the next Measure-SquadLedger -Write re-derives consumption.md from history)"
    }

    # A comparison that still quotes a squad total other than the ledger's own is self-refuting; the hand-off does not stand.
    $finalLedger = Get-FileText $consumptionPath
    $quoted = [regex]::Match($finalLedger, '(?m)^This run consumed an estimated \*\*\$(?<n>[0-9][0-9,]*(?:\.\d+)?) \(~')
    if ($quoted.Success -and $finalLedger -notmatch '(?m)^#{2,3}\s+Observed Usage') {
        $quotedCost = [double]::Parse($quoted.Groups['n'].Value.Replace(',', ''), [System.Globalization.CultureInfo]::InvariantCulture)
        if ([math]::Abs($quotedCost - [math]::Round($cost, 4)) -gt 0.00005) { throw "the Cost Comparison quotes `$$($quoted.Groups['n'].Value) but the ledger total is `$$($cost.ToString('F4', [System.Globalization.CultureInfo]::InvariantCulture)) (self-refuting)." }
    }
}
catch {
    Stop-WithRollback 3 "write failed: $($_.Exception.Message)"
}

$written | ForEach-Object { Write-Output $_ }
$handoffWarnings | ForEach-Object { Write-Output $_ }
if ($ledgerOnly) {
    Write-Output $ledgerOnly
    exit 0
}
$checkLine = @($check.Text -split "`n" | Where-Object { $_ -match 'Measure-SquadLedger -Check: PASS' } | Select-Object -Last 1)
Write-Output $(if ($checkLine.Count -gt 0) { $checkLine[0].Trim() } else { 'Measure-SquadLedger -Check: PASS' })
exit 0
