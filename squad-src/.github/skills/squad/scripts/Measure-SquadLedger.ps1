#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Deterministically derives (and optionally verifies) a squad root's consumption
    ledger from complete native usage records, with history/rate estimates as fallback.
.DESCRIPTION
    AI cost: none; calculates recorded usage from local host logs, history, and rates,
    without a model call. Complete native records provide exact per-role billed token
    categories and credits when event-agent attribution and the session total reconcile.
    History blocks remain the append-only integrity source and the fallback estimator.
    This is the D6b remedy for the AFTER benchmark regression: two of three AFTER
    runs wrote a wrong ledger cost (one of them by copying scribe-procedure.md's own
    Step 7 worked example instead of deriving the real payload's cost). This script
    performs the same derivation *Consumption Accounting* (Step 7) describes, reading
    only files a squad root already carries, so its answer can be pasted into
    `consumption.md` unchanged or used to verify a Scribe write that already happened.

    It ships inside the squad skill's `scripts/` directory, alongside the reference
    files it re-derives, so a consumer with the skill installed already has it. By
    default it is read-only: it never writes `consumption.md`, `consumption-rates.md`,
    or any other squad-state file, and only computes what the Scribe should write, or
    checks what it did write. The one exception is `-Write`, which the Scribe itself
    runs as its own tool: it splices the derived fragment into `consumption.md` and
    sets the two `state.json` `currentRun` totals, and when exact native usage is
    available upserts `consumption-sessions.json`, so the Scribe remains the single
    writer of squad state while no model transcribes a derived number by hand. Those
    three replace-semantics files commit or roll back as one transaction.

    Field order for a `#### Consumption` (or `#### Consumption — Orchestration`) block
    is contractual and validated in order: `model`, `model_source`, `priced_as`,
    `model_tier`, `internal_turns`, `input_tokens`, `cached_tokens`,
    `cache_write_tokens`, `output_tokens`, `basis`.

    Fallback role attribution follows `team.md`'s roster order: a history file's agent name
    (its own file name, minus `.md`) is matched against every roster row's
    `Agent Name (Primary)` and `Alternate Agents` cells, and the matching row's `Role`
    is the printed label. `history/Squad Scribe.md` is a fixed special case: it always
    labels `orchestration`, never the `scribe` role a roster might also define, and it
    always prints last regardless of where a `scribe` row sits in the roster table.
    An agent name matching no roster row still prints — under its own file name, not
    silently dropped — because a role dispatched outside the seeded roster still
    spent real tokens. Every history file gets its own Attribution/Usage & Cost row,
    never merged into another file's row for the same role: a role with both a
    Primary and a Fallback dispatched in the same run (e.g. `architect`'s
    `System Architecture Reviewer` Primary and `ADR Creator` Fallback) prints two
    rows sharing that `Role` label, and each row's `Agent` cell names the agent that
    history file actually records — never the role's roster-declared Primary printed
    twice — so a Fallback dispatch is never misattributed to the Primary it fell back
    from.

    A role's blocks are priced individually (a block's own `priced_as` looked up
    against its own rate row) and the resulting per-block costs are summed, rather
    than aggregating every block's tokens first and pricing the sum once. The two
    methods agree whenever a role's blocks all resolved to the same rate, which is
    the overwhelmingly common case; pricing per block is what keeps the total honest
    on the rarer run where a role's model changed mid-run. The printed `### Derivation`
    line still shows the aggregated token columns priced at the role's first block's
    rate, exactly the shape *Consumption Accounting* Step 7 prescribes for a human to
    paste — when a later block priced differently, a `NOTE:` line flags the split so
    the difference between the printed line and the total column is never silent.

    An unresolvable `priced_as` never prices at 0: it falls back to the block's own
    `model_tier` row in the tier-fallback table (the same fallback *Consumption
    Accounting* Step 3 describes) and is flagged with a `WARN:` line. A `model_tier`
    that also fails to resolve is a data defect this script cannot safely guess past,
    so it stops with a terminating error naming the offending block rather than
    silently contributing a zero or a fabricated rate.
.PARAMETER SquadRoot
    Path to a squad root: `.copilot-tracking/squad/` or a member sub-squad root such
    as `.copilot-tracking/squad/members/<name>/`. Must contain `history/`, `team.md`,
    and `consumption-rates.md`.
.PARAMETER Check
    Validate the squad root's existing `consumption.md` structurally, by
    Attribution, and numerically. Structurally: an H1 matching `# Squad Consumption
    Ledger`, a `## Attribution` heading, an exact `## Usage & Cost` heading, a
    `### Derivation` heading, and no leaked helper-diagnostic text (a
    `derived from history/ at` heading decoration or a `state.json currentRun.`
    line) -- these catch a ledger that was overwritten wholesale by this script's
    own console output rather than having its rows pasted into the existing file.
    By Attribution: each role row's `Model`, `Model Source`, and `Priced As` cells
    (order-insensitive, whitespace-trimmed) against the same blocks the Usage &
    Cost table derives from, plus any `Model Source` value outside the legal set
    (`cli-pinned`, `operator-declared`, `dispatch-reported`, `agent-pinned`,
    `session-inherited`, `unresolved`); a missing or extra role row is also a
    mismatch. `Member`/`Agent`/`Tier` are roster-sourced, not block-derived, and are
    not compared. Numerically: the Usage & Cost Total row's tokens/turns (exact
    match) and cost (within 0.0001 USD or 0.1%, whichever is larger) against the
    figures this script derived from `history/*.md`. Also compares
    -ExpectedHistoryCounts when supplied. Also checks two conditions independent
    of consumption.md's own shape: the C2 history-identity guard (every history
    file's `###` entry identities recorded in consumption.md's `### Derivation`
    block must be an ordered prefix of that file's current identities -- an
    entry overwritten or removed fails even at the same entry count, a plain
    append passes, and an older-format ledger recording no identities at all
    only warns -- *except* when -Check is combined with -ExpectedHistoryCounts,
    the Scribe's own post-write self-check shape: there, a Derivation with no
    recorded identities at all, or recording some but not every history file
    with entries (a partial paste), FAILS instead of warning, because that call
    always follows a fresh write and a missing or partial paste is this run's
    own defect, never a pre-existing legacy ledger); and the C3 ledger<->state.json `currentRun` divergence (its
    `estCostUsd`/`estCreditsTotal` must match this script's own derived totals
    within the same tolerance as the Total row above, and a history holding
    consumption blocks with no readable `currentRun` also fails) -- except on a
    federation root (marked by `federation.md`), which has no single run-level
    `currentRun` to reconcile against and logs `not-applicable: federation root`
    instead of comparing or silently passing. The C2 guard also runs outside
    -Check, refusing to render a new fragment while it already fails. Writes
    nothing, ever — this switch only changes the exit code and adds a mismatch
    report. Exits 0 when every comparison passes, 1 otherwise, listing every
    mismatch found, then a `failure class:` line: `history-integrity` when a
    history entry count is short, an entry was removed, overwritten, reordered,
    or inserted, or a -BaselinePath file or protected artifact changed;
    `ledger-only` for every other mismatch, which is cost accounting the next
    -Write re-derives from history/ and which never blocks a run.
    When history contains only Squad Scribe setup usage, also requires the
    canonical initialization Cost Comparison: n/a until the first work dispatch.
    Actual-work comparisons are checked numerically against their persisted basis:
    exact-native rows validate exact totals and counterfactual arithmetic; fallback
    rows validate estimated cost, credits, and recognized savings.
.PARAMETER ExpectedHistoryCounts
    Optional hashtable keyed by history file name (with or without the `.md`
    extension, e.g. `'Squad Researcher'` or `'Squad Researcher.md'`) whose value is
    the expected `###` dispatch-entry count for that file. Compared only when -Check
    is also supplied. Under `pwsh -File` pass a string instead (a hashtable literal
    cannot cross it): `'Squad Implementor=2;Squad Scribe=1'` (`,` also separates), or a
    JSON object string. An unparseable string is an error.
.PARAMETER Write
    Scribe-invoked write mode. Derives the same fragment the default markdown mode
    prints, then replaces the existing `## Attribution` heading through the closing
    fence of the `### Derivation` block inside the squad root's `consumption.md`,
    leaving the H1, frontmatter and Basis note untouched. Complete native agent
    attribution replaces the estimated tables and writes an exact-actual comparison
    against the same exact role traffic on one model; otherwise the helper refreshes
    the estimated fallback comparison and preserves supplied manual-baseline notes,
    and sets only `currentRun.estCostUsd` and `currentRun.estCreditsTotal` in
    `state.json` to the derived run totals (a value-only replacement, so every other
    byte of `state.json`, including date strings, is preserved). Exact mode also
    upserts the active native session in optional `consumption-sessions.json`; repeated
    writes replace that session, later sessions append only after cached history
    coverage and native identities validate, and every accepted session is summed
    into the one public ledger. Refuses, writing
    nothing, when combined with -Check or key-lookup mode, on a federation root
    (marked by `federation.md`), when `consumption.md` lacks those anchors or
    `state.json` lacks exactly one of each `currentRun` key, and in every case the
    render mode already refuses (a failing history-identity guard or an unreadable
    post-baseline block). Run it after every other write the hand-off makes to
    `state.json`, then run -Check -ExpectedHistoryCounts as the self-check.
    Markdown and -Write also add a `## Unit Economics (value)` section (cost per
    deliverable an independent review accepted, first-pass yield, rework and
    orchestration shares; -Format json adds `unitEconomics`). -Write replaces it
    when present, else inserts it before `## Cost Comparison`; -Check ignores it.
    Initialization-only history instead stamps a canonical n/a Cost Comparison;
    it never invents a manual baseline. Any legacy Observed Usage section is removed.
.PARAMETER Format
    Output shape: `markdown` (default) prints the pasteable table and Derivation
    block; `json` prints the same figures as a structured object instead, for a
    caller that wants to consume them programmatically rather than paste them.
.PARAMETER EmitBaseline
    Path -- which must resolve OUTSIDE any `.copilot-tracking/squad` tree (a
    session/temp path); the script refuses and throws otherwise -- to write a
    JSON content-level baseline: for every append-only file (`history/*.md`,
    plus `decisions.md` and `notifications.md` when present) a `{length,
    sha256, headingCount, blockCount, blocks[]}` record (`length`/`sha256` are
    the file's raw byte length and full-content SHA-256; `headingCount` counts
    `##`/`###` heading lines combined; `blocks` records each existing `####
    Consumption` block's ordinal, character offset, and content SHA-256, so a
    later `-BaselinePath` check can recognise a pre-baseline/legacy block by
    ordinal <= this recorded `blockCount`); and for every `-ProtectedPath`
    entry a `{exists, sha256}` record. `state.json`, `consumption.md`, and
    `consumption-sessions.json` are intentionally never covered (they are
    replace-semantics files rewritten by ledger transactions) -- passing any of
    them as `-ProtectedPath` throws. Also writes full
    pre-write copies of every covered file next to the JSON, under a sibling
    `<baseline-file-name>.files/` directory (mirroring each file's relative
    path), per Amendment 3 E3. Orthogonal to `-BaselinePath` and to `-Check`:
    it may be combined with either, or used alone.
.PARAMETER BaselinePath
    Path to a JSON baseline previously written by `-EmitBaseline`. Loading it
    (regardless of `-Check`) makes every consumption block's ordinal position
    in its own history file comparable against that file's baseline
    `blockCount`, so `-Check`-independent behaviour in `Resolve-RateForBlockLocal`
    (an unresolvable `priced_as`/`model_tier`) and in block validation (a
    malformed block or an illegal `model_source`) can tell a pre-baseline
    (legacy) block -- which only WARNs, never throws or fails -- from one
    appended after the baseline -- which still throws outside `-Check` and
    becomes a `-Check` FAIL instead of a warning. A file absent from the
    baseline (created after it was taken) is treated as having a baseline
    `blockCount` of 0 -- every block in it is post-baseline. A missing
    `-BaselinePath` file throws outside `-Check` and is reported as a `-Check`
    FAIL. Combined with `-Check`, it additionally runs the full append-only/
    protected-artifact verification described under `-EmitBaseline`'s FAIL
    conditions: an append-only file that shrank; whose first `length` bytes no
    longer hash to the baseline's recorded SHA-256 (a prefix edit); a
    protected artifact whose SHA-256 changed and is not named in
    `-AllowedWritePath`; or a baseline-recorded file that no longer exists. The
    protected set verified at `-Check` time is always the *baseline's own*
    recorded `protected` map -- every path the matching `-EmitBaseline` call
    covered -- unioned with any `-ProtectedPath` the caller also names at
    check time; omitting `-ProtectedPath` at `-Check` never skips a protected
    artifact the baseline recorded, it only means no *additional* path is
    checked beyond what the baseline already covers. `state.json` and
    `consumption.md` rewrites are never checked here (by design, not because
    they happened to pass) and are not FAILs. Without `-Check`, `-BaselinePath`
    only affects legacy-block classification and performs no append-only/
    protected verification of its own.
.PARAMETER ProtectedPath
    Caller-named deliverable paths, relative to `-SquadRoot`, added to
    `-EmitBaseline`'s content-level baseline and, combined with `-BaselinePath
    -Check`, checked for any hash change at all (not only shrinkage) unless
    named in `-AllowedWritePath`. Must not include `state.json` or
    `consumption.md` -- those are excluded from protection by design. At
    `-Check` time this list only *adds* to the protected set verified -- see
    `-BaselinePath`: every path the baseline itself recorded under `protected`
    is always verified whether or not it is re-supplied here.
.PARAMETER AllowedWritePath
    Caller-named paths, relative to `-SquadRoot`, excluded from the
    `-ProtectedPath` hash-change check when combined with `-BaselinePath
    -Check` -- e.g. the concurrent write set of an in-flight Role(N+1)
    dispatch, or an authorized correction/restore path -- so a legitimate
    concurrent or corrective write is never reported as a clobber.
.PARAMETER LookupRunId
.PARAMETER LookupTopic
.PARAMETER LookupStage
.PARAMETER LookupSlot
    Four parameters that, supplied together (any subset throws), select
    key-lookup mode: a deterministic, model-free existence check for resume
    logic. The four values are joined with `::` into one composite key, and
    every `history/*.md` file's raw content is searched for that exact literal
    substring. Prints `EXISTS` (naming the file(s) it was found in) or
    `MISSING`, or (with `-Format json`) `{key, exists, files[]}`; exits `0`
    when found, `1` when not. This is a plain substring search, not a
    schema-aware field lookup -- the composite key must actually appear in a
    written history entry (e.g. embedded in its Deliverable path or a
    dedicated tag) for a later lookup of it to succeed; wiring the Scribe to
    embed it is a separate, contract-text task outside this script's scope.
    No other switch (`-Check`, `-EmitBaseline`, `-BaselinePath`, `-Format`
    aside) is honored in this mode.
.PARAMETER AdvanceUnmeteredHistory
    Journal-only deterministic lifecycle mode. It requires an existing exact-session
    journal, proves that every newly appended history identity has no consumption
    block, attaches that zero-consumption suffix to the latest accepted session,
    validates cumulative coverage and exact totals, then atomically rewrites only
    `consumption-sessions.json`. Promotion uses this after appending its script-only
    lifecycle entry. It never changes `consumption.md`, `state.json`, request totals,
    or credits.
.PARAMETER SessionLog
    Optional host session log holding real per-dispatch usage: a Copilot CLI /
    VS Code agent-host `events.jsonl`, the session directory that contains it,
    or `auto` to pick the most recently written session under
    `$COPILOT_HOME/session-state` (default `~/.copilot/session-state`) whose
    `workspace.yaml` `cwd` is this squad root's repository. When no exact-session
    journal exists and current history spans earlier sessions, `auto` may bootstrap
    the journal from complete matching logs whose non-overlapping event windows
    uniquely cover every metered history entry; missing or ambiguous coverage keeps
    the estimator in place. The selected active session receives a bounded 30-second
    open-tail allowance because the outer host cannot append the tool-completion event
    while this child writer is still running. On the next session, the latest cached
    native session is refreshed from its completed log before new usage is appended.
    Complete
    `session.usage_record` and native compaction records are deduplicated by host
    accounting identity. Event `agentId` joins to `subagent.started`; nested
    `parentAgentId` chains roll into their owning top-level role. Native token
    details provide disjoint uncached input, cache read, cache write, and output
    counts whose charges must reproduce total nano-AIU. When every newly metered
    history-backed row and orchestration entry reconcile to the active session total,
    its closed-schema snapshot is upserted by native session id and merged with prior
    accepted sessions. Duplicate request identities, history-prefix drift, or any
    coverage gap leaves the journal unchanged and the estimator in place. Exact rows
    drive state totals, unit economics, JSON `exact`, and Cost Comparison.
    Member-scoped roots retain estimates because coordinator usage cannot be assigned
    to one member.
.PARAMETER BaselineModel
    Model id that prices the without-Squad counterfactual: the same exact role
    request token categories on one model, with no coordinator or Scribe. Defaults
    to the most expensive rate-resolved non-Hydra model used by a role.
.EXAMPLE
    ./Measure-SquadLedger.ps1 -SquadRoot .copilot-tracking/squad/members/routing-performance
.EXAMPLE
    ./Measure-SquadLedger.ps1 -SquadRoot .copilot-tracking/squad -Check -ExpectedHistoryCounts 'Squad Researcher=1;Squad Scribe=1'
.EXAMPLE
    ./Measure-SquadLedger.ps1 -SquadRoot .copilot-tracking/squad/members/product -Write
.EXAMPLE
    ./Measure-SquadLedger.ps1 -SquadRoot .copilot-tracking/squad -Write -SessionLog auto
.EXAMPLE
    ./Measure-SquadLedger.ps1 -SquadRoot .copilot-tracking/squad -EmitBaseline $env:TEMP/squad-baseline.json -ProtectedPath 'research/2026-09-27-topic.md'
.EXAMPLE
    ./Measure-SquadLedger.ps1 -SquadRoot .copilot-tracking/squad -Check -BaselinePath $env:TEMP/squad-baseline.json -ProtectedPath 'research/2026-09-27-topic.md' -AllowedWritePath 'research/2026-09-28-next.md'
.EXAMPLE
    ./Measure-SquadLedger.ps1 -SquadRoot .copilot-tracking/squad -LookupRunId rp-20260929a -LookupTopic pipelining -LookupStage P03-T06 -LookupSlot 1
.NOTES
    See .copilot-tracking/squad/members/routing-performance/changes/2026-09-28-d6b-ledger-tool.md
    for this script's contract and the benchmark regression it remedies, and
    .copilot-tracking/squad/members/routing-performance/changes/2026-09-29-u1-ledger-baseline-tooling.md
    for the baseline/lookup/no-throw additions.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SquadRoot,

    [switch]$Check,

    [switch]$Write,

    [object]$ExpectedHistoryCounts = @{},

    [ValidateSet('markdown', 'json')]
    [string]$Format = 'markdown',

    [string]$EmitBaseline,

    [string]$BaselinePath,

    [string[]]$ProtectedPath = @(),

    [string[]]$AllowedWritePath = @(),

    [string]$LookupRunId,

    [string]$LookupTopic,

    [string]$LookupStage,

    [string]$LookupSlot,

    [switch]$AdvanceUnmeteredHistory,

    [string]$SessionLog,

    [string]$BaselineModel
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Ledger figures are always period-decimal (matching consumption.md's own
# formatting), regardless of the host machine's regional settings -- otherwise a
# comma-decimal culture would both mis-format this script's own output and
# mis-parse the numbers it reads back out of consumption.md under -Check.
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

# ---------------------------------------------------------------------------
# Generic markdown/number parsing (self-contained: this script ships to
# consumers and must not import anything from tests/).
# ---------------------------------------------------------------------------

function ConvertTo-LedgerNumberLocal {
    <#
    .SYNOPSIS
        Strips the bold/currency markup a ledger or rate cell may carry and returns
        a [double], or $null when the cell does not hold a plain number.
    #>
    param([string]$Value)

    $clean = ($Value -replace '[*$,]', '').Trim()
    if ($clean -match '^-?\d+(\.\d+)?$') { return [double]$clean }
    return $null
}

function ConvertTo-LongContextThresholdLocal {
    <#
    .SYNOPSIS
        Converts a documented threshold such as "\<=100K / >100K" to tokens.
    #>
    param([string]$Value)

    $clean = ($Value -replace '\\', '').Trim()
    if ($clean -notmatch '(?:≤|<=)\s*(?<amount>\d+(?:\.\d+)?)\s*(?<unit>[KMG]?)') { return $null }

    $multiplier = switch ($Matches.unit.ToUpperInvariant()) {
        'K' { 1000.0 }
        'M' { 1000000.0 }
        'G' { 1000000000.0 }
        default { 1.0 }
    }
    return [double]$Matches.amount * $multiplier
}

function Get-MarkdownTableLocal {
    <#
    .SYNOPSIS
        Reads every pipe-delimited markdown table in a document as rows keyed by
        their column headers, in document order.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Content = ''
    )

    $tables = [System.Collections.Generic.List[pscustomobject]]::new()
    $header = $null
    $rows = $null

    foreach ($line in ($Content -split '\r?\n')) {
        if ($line -notmatch '^\s*\|') {
            if ($header) { $tables.Add([pscustomobject]@{ Header = $header; Rows = $rows }) }
            $header = $null
            $rows = $null
            continue
        }

        # The delimiter row (|---|---|) separates header from body and carries no data.
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') { continue }

        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim().Trim('`').Trim() })

        if (-not $header) {
            $header = $cells
            $rows = [System.Collections.Generic.List[System.Collections.Specialized.OrderedDictionary]]::new()
            continue
        }

        $row = [ordered]@{}
        for ($i = 0; $i -lt $header.Count; $i++) {
            $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' }
        }
        $rows.Add($row)
    }

    if ($header) { $tables.Add([pscustomobject]@{ Header = $header; Rows = $rows }) }
    $tables
}

# ---------------------------------------------------------------------------
# consumption-rates.md: per-model table, tier-fallback table, calibration.
# ---------------------------------------------------------------------------

function Get-RateTableLocal {
    <#
    .SYNOPSIS
        Reads the per-model and tier-fallback rate tables out of consumption-rates.md
        content. Tolerates both the 7-column shape (no LC columns) and the current
        shape (LC Threshold/Input/Cached/Cache write/Output columns present)
        because rows are selected by header name, never by position.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Content = ''
    )

    $byModel = @{}
    $byTier = @{}
    $byNormalized = @{}
    if (-not $Content) { return [pscustomobject]@{ ByModel = $byModel; ByTier = $byTier; ByNormalized = $byNormalized } }

    $rateColumns = @('Input', 'Cached', 'Cache write', 'Output')

    foreach ($table in (Get-MarkdownTableLocal -Content $Content)) {
        if (@($rateColumns | Where-Object { $_ -notin $table.Header }).Count -gt 0) { continue }

        # 'Priced as' names the rate row on the tier-fallback table; everywhere else
        # the first column is the model itself.
        $isTierTable = 'Priced as' -in $table.Header
        $keyColumn = if ($isTierTable) { 'Priced as' } else { $table.Header[0] }

        foreach ($row in $table.Rows) {
            $key = $row[$keyColumn]
            if (-not $key) { continue }

            $numbers = @($rateColumns | ForEach-Object { ConvertTo-LedgerNumberLocal $row[$_] })
            if ($numbers -contains $null) { continue }

            # pricedAsName is the model name this rate row is actually keyed under --
            # the block's own `priced_as` on a direct hit, or the tier-fallback
            # table's own `Priced as` model name on a fallback. This is what the
            # Attribution table's `Priced As` column prints, never the tier label.
            $rate = @{
                input        = $numbers[0]
                cached       = $numbers[1]
                cache_write  = $numbers[2]
                output       = $numbers[3]
                pricedAsName = $key
            }
            $lcColumns = @('LC Input', 'LC Cached', 'LC Cache write', 'LC Output')
            $lcThreshold = if ('LC Threshold' -in $table.Header) { ConvertTo-LongContextThresholdLocal $row['LC Threshold'] } else { $null }
            $lcNumbers = @($lcColumns | ForEach-Object { if ($_ -in $table.Header) { ConvertTo-LedgerNumberLocal $row[$_] } })
            if ($null -ne $lcThreshold -and $lcNumbers.Count -eq $lcColumns.Count) {
                $rate['long_context_threshold'] = $lcThreshold
                $rate['lc_input'] = $lcNumbers[0]
                $rate['lc_cached'] = $lcNumbers[1]
                $rate['lc_cache_write'] = $lcNumbers[2]
                $rate['lc_output'] = $lcNumbers[3]
            }

            if ($isTierTable) {
                if ('Tier' -in $table.Header) { $rate['tier'] = $row['Tier'] }
                if (-not $byModel.ContainsKey($key)) { $byModel[$key] = $rate }
                $normalizedTierKey = ConvertTo-RateKeyLocal $key
                if (-not $byNormalized.ContainsKey($normalizedTierKey)) { $byNormalized[$normalizedTierKey] = $rate }
                if ($rate.tier -and -not $byTier.ContainsKey($rate.tier)) { $byTier[$rate.tier] = $rate }
            }
            else {
                # Per-model table read first, so it stays authoritative over any
                # tier-fallback duplicate of the same model name.
                $byModel[$key] = $rate
                # A routed dispatch records its exact Model ID, so the row answers to
                # that id too; pricedAsName still prints the row's display name.
                if ('Model ID' -in $table.Header) {
                    $modelId = ($row['Model ID'] -replace '`', '').Trim()
                    if ($modelId -and $modelId -ne '—' -and -not $byModel.ContainsKey($modelId)) { $byModel[$modelId] = $rate }
                    if ($modelId -and $modelId -ne '—') { $byNormalized[(ConvertTo-RateKeyLocal $modelId)] = $rate }
                }
                $byNormalized[(ConvertTo-RateKeyLocal $key)] = $rate
                if ('Tier' -in $table.Header -and $row['Tier'] -and -not $byTier.ContainsKey($row['Tier'])) {
                    $byTier[$row['Tier']] = $rate
                }
            }
        }
    }

    if ($byModel.Count -gt 0) {
        if (-not $byNormalized.ContainsKey('hydrafusion-max')) {
            $hfRate = @{
                input                  = 0.80
                cached                 = 0.05
                cache_write            = 1.00
                output                 = 4.00
                pricedAsName           = 'HydraFusion Max'
                tier                   = 'default'
                long_context_threshold = 272000.0
                lc_input               = 1.60
                lc_cached              = 0.10
                lc_cache_write         = 2.00
                lc_output              = 6.00
            }
            $byModel['HydraFusion Max'] = $hfRate
            $byModel['hydrafusion-max'] = $hfRate
            $byNormalized['hydrafusion-max'] = $hfRate
        }
        $hfResolved = $byNormalized['hydrafusion-max']
        foreach ($alias in @('HydraFusion', 'hydrafusion', 'hydrafusion-max')) {
            if (-not $byModel.ContainsKey($alias)) { $byModel[$alias] = $hfResolved }
        }
    }

    [pscustomobject]@{ ByModel = $byModel; ByTier = $byTier; ByNormalized = $byNormalized }
}

function ConvertTo-RateKeyLocal {
    <#
    .SYNOPSIS
        Spelling-insensitive rate-row key: 'GPT-5.3 Codex', 'GPT-5.3-Codex',
        '`gpt-5.3-codex`', and 'Claude Sonnet 5.5 (copilot)' all reduce to the
        same lowercase hyphenated id.
    #>
    param([AllowEmptyString()][string]$Value)
    $text = ($Value -replace '`', '' -replace '\((copilot|preview)\)', '').Trim().ToLowerInvariant()
    $key = ($text -replace '[\s_]+', '-' -replace '-{2,}', '-').Trim('-')
    if ($key -in @('hydrafusion', 'hydrafusion-balance', 'hydrafusion-efficiency')) { return 'hydrafusion-max' }
    return $key
}

function Get-CalibrationFactorLocal {
    <#
    .SYNOPSIS
        Reads `calibration_factor` from consumption-rates.md's Calibration yaml
        block. Defaults to 1.00 when the block or field is missing.
    #>
    param([string]$Content)

    $section = [regex]::Match($Content, '(?ms)^##\s+Calibration\s*$.*?```yaml\r?\n(?<body>.*?)\r?\n```')
    if (-not $section.Success) { return 1.0 }

    $match = [regex]::Match($section.Groups['body'].Value, '(?m)^\s*calibration_factor:\s*(?<value>[\d.]+)\s*$')
    if ($match.Success) { return [double]$match.Groups['value'].Value }
    return 1.0
}

# ---------------------------------------------------------------------------
# team.md roster: agent name -> role, in roster row order.
# ---------------------------------------------------------------------------

function Get-RosterLocal {
    <#
    .SYNOPSIS
        Reads team.md into an ordered list of { Role, AgentNames, MemberName,
        PrimaryAgent, Tier, AlignedRole }.
        AgentNames is every name in that row's Agent Name (Primary) and Alternate
        Agents cells, used for matching; MemberName and Tier (the Model Tier cell)
        are the roster-declared identity the Attribution table's Member/Tier columns
        print for a matched role.
        AlignedRole is populated for connector-backed additive rows from
        Connector Bindings (`Role Mode=add`) and is used for review-role
        classification.
        PrimaryAgent (the Agent Name (Primary) cell alone) is captured but never
        printed as the Attribution table's Agent cell -- that column instead
        names the history file actually dispatched (its own file name), so a
        Fallback dispatch (e.g. `ADR Creator` for the `architect` role, whose
        Primary is `System Architecture Reviewer`) is never misattributed to
        that role's Primary.
    #>
    param([string]$Content)

    function Get-ConnectorTargetRoleLocal {
        param([AllowEmptyString()][string]$Target)
        $text = ([string]$Target).Trim()
        if ($text -match '^(?i)role:(?<role>[a-z0-9-]+)(?:/(?<member>.+))?$') {
            return [pscustomobject]@{
                Kind       = 'role'
                Role       = $Matches['role'].ToLowerInvariant()
                MemberName = if ($Matches['member']) { ([string]$Matches['member']).Trim() } else { '' }
            }
        }
        if ($text -match '^(?i)coordinator:Squad Coordinator$') {
            return [pscustomobject]@{ Kind = 'coordinator'; Role = 'coordinator'; MemberName = '' }
        }
        [pscustomobject]@{ Kind = 'invalid'; Role = ''; MemberName = '' }
    }

    $tables = @(Get-MarkdownTableLocal -Content $Content)
    $roster = [System.Collections.Generic.List[pscustomobject]]::new()
    $connectorHeader = @('Binding ID', 'Connector ID', 'Manifest', 'Endpoint Kind', 'Role Mode', 'Target Kind', 'Target', 'Member Name', 'Added Role', 'Aligned Role', 'Default Execution')
    $connectorTable = @(
        $tables | Where-Object {
            $table = $_
            @($connectorHeader | Where-Object { $_ -in $table.Header }).Count -eq $connectorHeader.Count
        } | Select-Object -First 1
    )
    $addBindingsByRoleMember = @{}
    $replaceBindings = [System.Collections.Generic.List[pscustomobject]]::new()
    $connectorBindingsWithMembers = [System.Collections.Generic.List[pscustomobject]]::new()
    if ($connectorTable.Count -gt 0) {
        foreach ($binding in $connectorTable[0].Rows) {
            $bindingId = ([string]$binding['Binding ID']).Trim()
            $roleMode = ([string]$binding['Role Mode']).Trim().ToLowerInvariant()
            $memberName = ([string]$binding['Member Name']).Trim()
            $target = Get-ConnectorTargetRoleLocal -Target ([string]$binding['Target'])
            $protectedRoles = @('scribe', 'coordinator', 'federation-coordinator', 'council')
            if (([string]$binding['Target Kind']).Trim().ToLowerInvariant() -ne 'role' -or $target.Kind -ne 'role' -or $target.Role -in $protectedRoles -or ([string]$binding['Added Role']).Trim().ToLowerInvariant() -in $protectedRoles -or ([string]$binding['Aligned Role']).Trim().ToLowerInvariant() -in $protectedRoles) {
                throw "Measure-SquadLedger: Connector Bindings row '$bindingId' must target an ordinary work role; coordinator, Scribe, and council governance are protected."
            }
            if ($bindingId -and $memberName) {
                $connectorBindingsWithMembers.Add([pscustomobject]@{
                        BindingId  = $bindingId
                        MemberName = $memberName
                        RoleMode   = $roleMode
                        TargetKind = ([string]$binding['Target Kind']).Trim().ToLowerInvariant()
                        Target     = ([string]$binding['Target']).Trim()
                    })
            }
            if ($roleMode -eq 'add') {
                $addedRole = ([string]$binding['Added Role']).Trim().ToLowerInvariant()
                $alignedRole = ([string]$binding['Aligned Role']).Trim().ToLowerInvariant()
                if (-not $addedRole -or -not $memberName) { continue }
                $key = ("{0}`n{1}" -f $addedRole, $memberName)
                if (-not $addBindingsByRoleMember.ContainsKey($key)) { $addBindingsByRoleMember[$key] = [System.Collections.Generic.List[string]]::new() }
                if ($alignedRole) { $addBindingsByRoleMember[$key].Add($alignedRole) }
                continue
            }
            if ($roleMode -ne 'replace' -or -not $memberName) { continue }
            $replaceBindings.Add([pscustomobject]@{
                    BindingId   = ([string]$binding['Binding ID']).Trim()
                    MemberName  = $memberName
                    TargetKind  = ([string]$binding['Target Kind']).Trim().ToLowerInvariant()
                    Target      = ([string]$binding['Target']).Trim()
                    AlignedRole = ([string]$binding['Aligned Role']).Trim().ToLowerInvariant()
                })
        }
    }

    foreach ($table in $tables) {
        if ('Role' -notin $table.Header) { continue }
        # Model-written rosters drift from the template header; accept the same primary spellings Write-SquadHandoff.ps1 does.
        $primaryHeader = @('Agent Name (Primary)', 'Primary Agent', 'Primary', 'Agent') | Where-Object { $_ -in $table.Header } | Select-Object -First 1
        if (-not $primaryHeader) { continue }

        foreach ($row in $table.Rows) {
            $names = [System.Collections.Generic.List[string]]::new()
            foreach ($column in @($primaryHeader, 'Alternate Agents')) {
                if (-not $column -or $column -notin $table.Header) { continue }
                foreach ($name in (([string]$row[$column]) -split '[,;]|\s/\s')) {
                    $trimmed = $name.Trim()
                    if ($trimmed -and $trimmed -ne '—' -and $trimmed -ne '-') { $names.Add($trimmed) }
                }
            }
            $role = ([string]$row['Role']).Trim()
            if (-not $role) { continue }
            $memberName = if ('Member Name' -in $table.Header) { ([string]$row['Member Name']).Trim() } else { '' }
            $primaryAgent = ([string]$row[$primaryHeader]).Trim()
            $tier = if ('Model Tier' -in $table.Header) { ([string]$row['Model Tier']).Trim() } else { '' }
            $alignedRole = ''
            if ($primaryAgent -ceq 'Squad Connector' -and $memberName) {
                $key = ("{0}`n{1}" -f $role.ToLowerInvariant(), $memberName)
                $matches = @(if ($addBindingsByRoleMember.ContainsKey($key)) { $addBindingsByRoleMember[$key] } else { @() })
                if ($matches.Count -eq 1) { $alignedRole = [string]$matches[0] }
            }
            $roster.Add([pscustomobject]@{
                    Role         = $role
                    AgentNames   = $names
                    MemberName   = $memberName
                    PrimaryAgent = $primaryAgent
                    Tier         = $tier
                    AlignedRole  = $alignedRole
                })
        }
        break
    }

    $bindingsByMember = @{}
    foreach ($binding in @($connectorBindingsWithMembers)) {
        if (-not $bindingsByMember.ContainsKey($binding.MemberName)) { $bindingsByMember[$binding.MemberName] = [System.Collections.Generic.List[object]]::new() }
        $bindingsByMember[$binding.MemberName].Add($binding)
    }
    foreach ($member in @($bindingsByMember.Keys)) {
        $bindings = @($bindingsByMember[$member])
        if ($bindings.Count -le 1) { continue }
        $bindingList = @($bindings | ForEach-Object { $_.BindingId }) -join ', '
        throw "Measure-SquadLedger: Connector Bindings Member Name '$member' is reused by $($bindings.Count) rows ($bindingList); connector member identities must be globally unique across connector bindings."
    }

    foreach ($binding in @($connectorBindingsWithMembers)) {
        $target = Get-ConnectorTargetRoleLocal -Target $binding.Target
        $targetRows = @()
        if ($binding.TargetKind -eq 'role' -and $target.Kind -eq 'role') {
            $targetRows = @($roster | Where-Object { ([string]$_.Role).Trim().ToLowerInvariant() -eq $target.Role -and $_.PrimaryAgent -cne 'Squad Connector' })
            if ($target.MemberName) {
                $targetRows = @($targetRows | Where-Object { ([string]$_.MemberName).Trim() -ceq $target.MemberName })
            }
        }
        if (@($targetRows | Where-Object { ([string]$_.MemberName).Trim() -and ([string]$_.MemberName).Trim() -ceq $binding.MemberName }).Count -gt 0) {
            throw "Measure-SquadLedger: Connector Bindings row '$($binding.BindingId)' must use a trusted Member Name distinct from targeted internal roster identities."
        }
    }

    if ($replaceBindings.Count -gt 0) {
        foreach ($binding in $replaceBindings) {
            $target = Get-ConnectorTargetRoleLocal -Target $binding.Target
            if ($binding.TargetKind -eq 'role' -and $target.Kind -ne 'role') { continue }
            $role = $target.Role
            if (-not $role) { continue }
            $classification = if ($binding.AlignedRole) { $binding.AlignedRole } else { $role }
            $tier = ''
            $targetRows = @($roster | Where-Object { ([string]$_.Role).Trim().ToLowerInvariant() -eq $role -and $_.PrimaryAgent -cne 'Squad Connector' })
            if ($binding.TargetKind -eq 'role' -and $target.MemberName) {
                $targetRows = @($targetRows | Where-Object { ([string]$_.MemberName).Trim() -ceq $target.MemberName })
            }
            if ($targetRows.Count -eq 1) {
                $tier = [string]$targetRows[0].Tier
            }
            elseif ($targetRows.Count -gt 1) {
                $tiers = @($targetRows | ForEach-Object { ([string]$_.Tier).Trim() })
                $uniqueTiers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($value in $tiers) { [void]$uniqueTiers.Add($value) }
                if ($uniqueTiers.Count -eq 1) {
                    $tier = @($uniqueTiers)[0]
                }
                else {
                    $tierList = @($uniqueTiers) -join ', '
                    throw "Measure-SquadLedger: Connector Bindings row '$($binding.BindingId)' targets role '$role' with ambiguous internal tiers ($tierList). Use an explicit role member target or align internal tiers."
                }
            }

            $already = @($roster | Where-Object {
                    $_.PrimaryAgent -ceq 'Squad Connector' -and ([string]$_.MemberName).Trim() -ceq $binding.MemberName
                })
            if ($already.Count -gt 0) {
                $collisionRoles = @($already | ForEach-Object { ([string]$_.Role).Trim().ToLowerInvariant() }) -join ', '
                throw "Measure-SquadLedger: synthetic connector identity collision for member '$($binding.MemberName)' (binding '$($binding.BindingId)') with existing roster rows ($collisionRoles)."
            }

            $agentNames = [System.Collections.Generic.List[string]]::new()
            $agentNames.Add('Squad Connector')
            $roster.Add([pscustomobject]@{
                    Role         = $role
                    AgentNames   = $agentNames
                    MemberName   = $binding.MemberName
                    PrimaryAgent = 'Squad Connector'
                    Tier         = $tier
                    AlignedRole  = $classification
                })
        }
    }
    $roster
}

function Resolve-RoleForAgentLocal {
    <#
    .SYNOPSIS
        Finds the roster row order index and role identity for a history file's agent
        name and optional Member Name. Shared-agent history without Member Name
        resolves only when exactly one roster row matches.
    #>
    param(
        [Parameter(Mandatory)][string]$AgentName,
        [AllowEmptyString()][string]$MemberName = '',
        # Not Mandatory -- see Resolve-RateForBlockLocal for why an empty
        # collection argument must not carry [Parameter(Mandatory)].
        [System.Collections.Generic.List[pscustomobject]]$Roster,
        [AllowEmptyString()][string]$ExternalProvenance = '',
        [AllowEmptyString()][string]$EntryTitle = '',
        [AllowEmptyString()][string]$Verification = '',
        [AllowEmptyString()][string]$ExternalUnmeteredConnector = '',
        [AllowEmptyCollection()][object[]]$ActiveConnectorBindings = @(),
        [AllowEmptyCollection()][object[]]$RetiredConnectorBindings = @()
    )

    $member = ([string]$MemberName).Trim()
    if ($AgentName -ceq 'Squad Connector' -and [string]::IsNullOrWhiteSpace($ExternalProvenance)) {
        return [pscustomobject]@{
            Index = $null; Role = $AgentName; ClassificationRole = $AgentName
            MemberName = $member; Tier = ''; AggregateKey = "$AgentName`n$member"
            Status = 'connector-missing-provenance'
        }
    }
    $matches = [System.Collections.Generic.List[pscustomobject]]::new()
    for ($i = 0; $i -lt $Roster.Count; $i++) {
        if ($AgentName -in $Roster[$i].AgentNames) { $matches.Add([pscustomobject]@{ Index = $i; Row = $Roster[$i] }) }
    }

    $provMatch = [regex]::Match($ExternalProvenance, '^(?i)connector=[^;]+;\s*binding=(?:legacy-1\.0|none\s*\(legacy-1\.0\));\s*endpoint=agent;\s*mode=replace;\s*target=role:(?<role>[a-z0-9-]+)(?:/(?<targetMember>[^\r\n;]+))?\s*$')
    if ($AgentName -ceq 'Squad Connector' -and $ExternalProvenance -and -not $provMatch.Success) {
        $provenance = [regex]::Match($ExternalProvenance, '^connector=(?<connector>[^;]+);\s*binding=(?<binding>[^;]+);\s*endpoint=(?<endpoint>[^;]+);\s*mode=(?<mode>[^;]+);\s*target=(?<target>.+)$')
        $identityMatches = @()
        if ($provenance.Success) {
            $retired = @($RetiredConnectorBindings | Where-Object {
                    $_.BindingId -ceq $provenance.Groups['binding'].Value -and $_.HistoryEntries -ccontains $EntryTitle
                })
            $candidates = if ($retired.Count -gt 0) { $retired } else { $ActiveConnectorBindings }
            $identityMatches = @($candidates | Where-Object {
                    $_.BindingId -ceq $provenance.Groups['binding'].Value -and
                    $_.ConnectorId -ceq $provenance.Groups['connector'].Value -and
                    $_.EndpointKind -ceq $provenance.Groups['endpoint'].Value -and
                    $_.RoleMode -ceq $provenance.Groups['mode'].Value -and
                    $_.Target -ceq $provenance.Groups['target'].Value -and $_.MemberName -ceq $member
                })
        }
        if ($identityMatches.Count -eq 1 -and $Verification -ceq 'external, unverified' -and
            $ExternalUnmeteredConnector -ceq $identityMatches[0].ConnectorId) {
            $identity = $identityMatches[0]
            $index = $Roster.Count
            for ($i = 0; $i -lt $Roster.Count; $i++) {
                if ($Roster[$i].Role -eq $identity.Role -and $Roster[$i].MemberName -ceq $member -and
                    $Roster[$i].PrimaryAgent -ceq 'Squad Connector') { $index = $i; break }
            }
            return [pscustomobject]@{
                Index = $index; Role = $identity.Role
                ClassificationRole = if ($identity.AlignedRole) { $identity.AlignedRole } else { $identity.Role }
                MemberName = $member; Tier = $identity.Tier
                AggregateKey = "$AgentName`n$($identity.Role)`n$member"; Status = 'ok'
            }
        }
        return [pscustomobject]@{
            Index = $null; Role = $AgentName; ClassificationRole = $AgentName
            MemberName = $member; Tier = ''; AggregateKey = "$AgentName`n$member"
            Status = 'connector-identity-mismatch'
        }
    }
    if ($AgentName -eq 'Squad Connector' -and $provMatch.Success) {
        $legacyRole = $provMatch.Groups['role'].Value.ToLowerInvariant()
        $legacyTargetMember = if ($provMatch.Groups['targetMember'].Success) { ([string]$provMatch.Groups['targetMember'].Value).Trim() } else { '' }
        $directMatches = @(if ($member) { $matches | Where-Object { ([string]$_.Row.MemberName).Trim() -ceq $member } } else { $matches })
        if ($directMatches.Count -eq 0) {
            for ($i = 0; $i -lt $Roster.Count; $i++) {
                $r = $Roster[$i]
                if (([string]$r.Role).Trim().ToLowerInvariant() -ne $legacyRole) { continue }
                if ($legacyTargetMember -and ([string]$r.MemberName).Trim() -cne $legacyTargetMember) { continue }
                $resolvedMember = if ($member) { $member } else { ([string]$r.MemberName).Trim() }
                $aggregateKey = if ($resolvedMember) { "$AgentName`n$resolvedMember" } else { $AgentName }
                return [pscustomobject]@{
                    Index              = $i
                    Role               = $r.Role
                    ClassificationRole = if ($r.AlignedRole) { $r.AlignedRole } else { $r.Role }
                    MemberName         = $resolvedMember
                    Tier               = $r.Tier
                    AggregateKey       = $aggregateKey
                    Status             = 'ok'
                }
            }
        }
    }

    if ($matches.Count -eq 0) {
        return [pscustomobject]@{
            Index              = $null
            Role               = $AgentName
            ClassificationRole = $AgentName
            MemberName         = ''
            Tier               = ''
            AggregateKey       = $AgentName
            Status             = if ($AgentName -ceq 'Squad Connector') { 'connector-unregistered' } else { 'unmapped' }
        }
    }

    if ($member) {
        $matches = @($matches | Where-Object { ([string]$_.Row.MemberName).Trim() -ceq $member })
        if ($matches.Count -eq 0) {
            return [pscustomobject]@{
                Index              = $null
                Role               = $AgentName
                ClassificationRole = $AgentName
                MemberName         = $member
                Tier               = ''
                AggregateKey       = "$AgentName`n$member"
                Status             = 'member-not-found'
            }
        }
    }

    if (-not $member -and $matches.Count -gt 1) {
        return [pscustomobject]@{
            Index              = $null
            Role               = $AgentName
            ClassificationRole = $AgentName
            MemberName         = ''
            Tier               = ''
            AggregateKey       = $AgentName
            Status             = 'ambiguous-missing-member'
        }
    }
    if ($matches.Count -gt 1) {
        return [pscustomobject]@{
            Index              = $null
            Role               = $AgentName
            ClassificationRole = $AgentName
            MemberName         = $member
            Tier               = ''
            AggregateKey       = "$AgentName`n$member"
            Status             = 'ambiguous-member'
        }
    }

    $resolved = $matches[0]
    $row = $resolved.Row
    if (-not $member -and $row.PrimaryAgent -ceq 'Squad Connector') {
        return [pscustomobject]@{
            Index              = $null
            Role               = $AgentName
            ClassificationRole = $AgentName
            MemberName         = ''
            Tier               = ''
            AggregateKey       = $AgentName
            Status             = 'connector-missing-member'
        }
    }
    $classificationRole = if ($row.AlignedRole) { $row.AlignedRole } else { $row.Role }
    $resolvedMember = if ($member) { $member } else { ([string]$row.MemberName).Trim() }
    $aggregateKey = if ($resolvedMember) { "$AgentName`n$resolvedMember" } else { $AgentName }
    return [pscustomobject]@{
        Index              = $resolved.Index
        Role               = $row.Role
        ClassificationRole = $classificationRole
        MemberName         = $resolvedMember
        Tier               = $row.Tier
        AggregateKey       = $aggregateKey
        Status             = 'ok'
    }
}

# ---------------------------------------------------------------------------
# history/*.md: dispatch-entry counts and Consumption blocks.
# ---------------------------------------------------------------------------

$script:ConsumptionFieldOrder = @(
    'model', 'model_source', 'priced_as', 'model_tier', 'internal_turns',
    'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens', 'basis'
)
$script:ConsumptionTextFields = @('model', 'model_source', 'priced_as', 'model_tier', 'basis')

# The legal `model_source` set (Amendment 3 §2 item 4's anchor list), hoisted to
# script scope so both the pre-aggregation block-validation pass (which
# baseline-scopes an illegal value the same way it does a parse failure) and
# -Check's own Attribution-table comparison read one authoritative list.
$script:LegalModelSources = @('cli-pinned', 'operator-declared', 'dispatch-reported', 'agent-pinned', 'session-inherited', 'unresolved')

function Get-HistoryEntryCountLocal {
    <#
    .SYNOPSIS
        Counts level-3 (`###`) dispatch-entry headings in a history file.
    #>
    param([string]$Content)
    @([regex]::Matches($Content, '(?m)^###[ \t]+\S')).Count
}

function Get-ShortIdentityHashLocal {
    <#
    .SYNOPSIS
        An 8-hex-character SHA-256 fingerprint of a string. This is a compact,
        deterministic identity for a history-entry heading, never a security
        boundary -- collisions are not a concern for this integrity-guard use.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $hashBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Text))
    -join ($hashBytes[0..3] | ForEach-Object { $_.ToString('x2') })
}

function Get-HistoryEntryIdentitiesLocal {
    <#
    .SYNOPSIS
        The ordered list of short identity hashes of a history file's `###`
        dispatch-entry headings, one per entry in file order.
    .DESCRIPTION
        This is the C2 history-identity guard's own record: consumption.md's
        `### Derivation` block persists this list per file (see the enumeration
        line built in the main loop below) so a later run can tell an entry that
        was overwritten or removed (same or fewer entries, a different or
        missing identity at some position) apart from a run that only appended
        new entries (a longer list sharing the same identities as a prefix).
    #>
    param([string]$Content)
    # No trailing `$` anchor -- see Get-ConsumptionBlockLocal's own CRLF note
    # above; `.` already stops before `\r`/`\n`, so the heading text is captured
    # cleanly without needing (and without risking) a multiline `$` anchor.
    @(
        [regex]::Matches($Content, '(?m)^###[ \t]+(?<title>\S.*)') | ForEach-Object {
            Get-ShortIdentityHashLocal -Text $_.Groups['title'].Value.Trim()
        }
    )
}

function Test-HistoryIdentityGuardLocal {
    <#
    .SYNOPSIS
        The C2 history-identity guard: compares each history file's identity
        list already recorded in an existing consumption.md against its current
        identity list (this run's own count of history/*.md).
    .DESCRIPTION
        The recorded list must be an ordered prefix of the current list. A
        shorter-or-equal-length recorded list that diverges anywhere (an entry
        overwritten in place, or reordered) fails, as does a recorded list
        longer than the current one (an entry removed). A recorded list that is
        a genuine prefix of a longer current list (a plain append) passes. When
        the existing ledger's `### Derivation` block carries no identity records
        at all (an older-format ledger, pre-dating this guard), every file WARNs
        instead of failing, so it keeps working until its next rewrite records
        identities for the first time. A file whose own line lacks the
        `-- identities:` suffix even though other lines in the same ledger carry
        one WARNs for that file alone, for the same reason -- *unless* `-PostWrite`
        is set, in which case both the fully-legacy case (no identities recorded
        at all) and the partial-paste case (some, but not every history file
        with entries, recorded) FAIL instead of warning. `-PostWrite` names the
        Scribe's own post-write self-check (`-Check` combined with
        `-ExpectedHistoryCounts`, per `scribe-procedure.md`'s Self-Check step):
        that call always follows an actual write of a fresh Derivation block, so
        a Derivation missing identities there is never a genuinely old ledger --
        it is this run's own paste having silently dropped the identity lines,
        which must not be allowed to pass. An ordinary `-Check` without
        `-ExpectedHistoryCounts` (or no `-Check` at all) keeps warning-only, so a
        pre-existing legacy ledger that nobody has rewritten yet still passes
        until its next rewrite, per council condition C2.
    .OUTPUTS
        [pscustomobject] with Legacy (bool), Failures (string[]), Warnings (string[]).
    #>
    param(
        [Parameter(Mandatory)][string]$ConsumptionContent,
        [Parameter(Mandatory)][hashtable]$CurrentIdentitiesByFile,
        [switch]$PostWrite
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $guardWarnings = [System.Collections.Generic.List[string]]::new()

    $derivationMatch = [regex]::Match($ConsumptionContent, '(?ms)^###\s+Derivation\s*?\r?\n.*?```text\r?\n(?<body>.*?)\r?\n```')
    $body = if ($derivationMatch.Success) { $derivationMatch.Groups['body'].Value } else { '' }

    $taggedLineCount = @([regex]::Matches($body, '(?m)^.+\.md — \d+ block\(s\) — identities: .*$')).Count
    if ($taggedLineCount -eq 0) {
        $message = "consumption.md's ### Derivation block records no history-entry identities yet (an older-format ledger); the C2 overwrite/removal guard cannot check it and only warns until the next rewrite records identities."
        if ($PostWrite) {
            return [pscustomobject]@{
                Legacy   = $true
                Failures = @("History identity guard: consumption.md's ### Derivation block records no history-entry identities. This is the Scribe's post-write self-check (-ExpectedHistoryCounts was supplied), which always follows a fresh write, so a missing Derivation here is a bad paste, not a legacy ledger -- rerun this helper with -Write, which writes identity lines for every history file.")
                Warnings = @()
            }
        }
        return [pscustomobject]@{
            Legacy   = $true
            Failures = @()
            Warnings = @($message)
        }
    }

    $recordedByFile = @{}
    foreach ($lineMatch in [regex]::Matches($body, '(?m)^(?<file>.+\.md) — \d+ block\(s\)(?<rest>.*)$')) {
        $fileName = $lineMatch.Groups['file'].Value.Trim()
        $idsMatch = [regex]::Match($lineMatch.Groups['rest'].Value, '— identities: (?<ids>.*)$')
        if (-not $idsMatch.Success) { continue }
        $idsText = $idsMatch.Groups['ids'].Value.Trim()
        $ids = [string[]]@()
        if ($idsText -and $idsText -ne '(none)') {
            $ids = [string[]]@($idsText -split ',' | ForEach-Object { $_.Trim() })
        }
        # Only this script writes identities, always as 8-hex hashes. A hand-written
        # placeholder ('unreported', a model source) carries no record, so the file is
        # treated as unrecorded (the partial-paste path below) instead of as a rewrite.
        if (@($ids | Where-Object { $_ -notmatch '^[0-9a-f]{8}$' }).Count -gt 0) { continue }
        $recordedByFile[$fileName] = $ids
    }

    # Partial paste: a file this run enumerates with at least one history entry
    # (so the helper's own Derivation would have printed an identities line for
    # it) but whose identities are not recorded in consumption.md's existing
    # Derivation at all -- either its enumeration line lost the
    # `-- identities:` suffix, or the line itself is missing outright, because
    # only some of the helper's per-file lines were pasted.
    foreach ($fileName in @($CurrentIdentitiesByFile.Keys | Sort-Object)) {
        if (@($CurrentIdentitiesByFile[$fileName]).Count -eq 0) { continue }
        if ($recordedByFile.ContainsKey($fileName)) { continue }
        $message = "consumption.md's ### Derivation block has no recorded identities for '$fileName', even though other history files in the same block carry them (a partial paste); the C2 guard cannot check '$fileName' this run."
        if ($PostWrite) {
            $failures.Add("History identity guard: $message This is the Scribe's post-write self-check, so a partial paste must not pass -- rerun this helper with -Write, which writes identity lines for every history file, not just some.")
        }
        else {
            $guardWarnings.Add($message)
        }
    }

    foreach ($fileName in $recordedByFile.Keys) {
        $recorded = @($recordedByFile[$fileName])
        if ($recorded.Count -eq 0) { continue }
        $current = @(if ($CurrentIdentitiesByFile.ContainsKey($fileName)) { $CurrentIdentitiesByFile[$fileName] } else { @() })

        if ($recorded.Count -gt $current.Count) {
            $failures.Add("History identity guard: '$fileName' recorded $($recorded.Count) entry identity(ies) in consumption.md but history/ now holds only $($current.Count); an entry was removed.")
            continue
        }

        $prefixOk = $true
        for ($i = 0; $i -lt $recorded.Count; $i++) {
            if ($recorded[$i] -ne $current[$i]) { $prefixOk = $false; break }
        }
        if (-not $prefixOk) {
            $failures.Add("History identity guard: '$fileName' entry identities recorded in consumption.md are not a prefix of history/'s current identities (an entry was overwritten or reordered rather than only appended to).")
        }
    }

    [pscustomobject]@{
        Legacy   = $false
        Failures = @($failures)
        Warnings = @($guardWarnings)
    }
}

function Get-ConsumptionBlockLocal {
    <#
    .SYNOPSIS
        Parses every `#### Consumption` / `#### Consumption — Orchestration` block
        in a history file's content, validating field presence, order, and shape.
    .DESCRIPTION
        U1 (Amendment 3 §2 item 3) also recognises a heading with no valid fenced
        ```json block following it at all (a bad/single-backtick fence, or a
        markdown table pasted in place of one) -- not merely a fenced block whose
        contents fail to parse. A separate heading-only regex enumerates every
        `#### Consumption...` heading in document order; any heading whose start
        index is not also the start of a full fenced-block match becomes its own
        malformed entry (ParseError set, Fields $null) rather than silently
        vanishing, so item 3's WARN/FAIL scoping has something to classify.
    #>
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$SourceName
    )

    # No trailing `$` anchor: with CRLF line endings, .NET's multiline `$` matches
    # between the `\r` and `\n`, one position short of where the heading text
    # actually ends, and the whole match silently fails. Requiring the literal
    # `\r?\n` that follows the heading is both sufficient and CRLF-safe.
    # No trailing `$` anchor: with CRLF line endings, .NET's multiline `$` matches
    # between the `\r` and `\n`, one position short of where the heading text
    # actually ends, and the whole match silently fails. Requiring the literal
    # newline(s) that follow the heading is both sufficient and CRLF-safe; the
    # blank line before the fence is `(?:\r?\n)+`, not `\r?\n+`, because the
    # latter's `\n+` cannot cross a second `\r` to reach a second `\n`.
    $pattern = '(?ms)^####[ \t]+Consumption(?<orch>[ \t]+[-\u2013\u2014][ \t]+Orchestration)?[ \t]*(?:\r?\n)+(?<open>`{1,3})json\r?\n(?<json>.*?)\r?\n(?<close>`{1,3})[ \t]*(?=\r?\n|$)'
    # Heading-only: same anchor/prefix as $pattern (so a genuine well-formed
    # block's heading match shares the exact same start index as its full-block
    # match), but makes no assumption about what -- if anything -- follows on
    # later lines. `[^\r\n]*` stops at end-of-line without relying on `$`'s
    # CRLF quirk noted above.
    $headingPattern = '(?m)^####[ \t]+Consumption(?<orch>[ \t]+[-\u2013\u2014][ \t]+Orchestration)?[^\r\n]*'

    $fullMatchesByIndex = @{}
    foreach ($match in [regex]::Matches($Content, $pattern)) { $fullMatchesByIndex[$match.Index] = $match }

    $ordinal = 0
    foreach ($headingMatch in [regex]::Matches($Content, $headingPattern)) {
        $ordinal++
        $match = $fullMatchesByIndex[$headingMatch.Index]

        if (-not $match) {
            # A heading with no full-block match at the same offset: no fenced
            # json block follows it (no fence at all, or non-JSON content --
            # e.g. a markdown table -- pasted in its place).
            [pscustomobject]@{
                Source          = $SourceName
                IsOrchestration = [bool]$headingMatch.Groups['orch'].Success
                Fields          = $null
                Order           = @()
                OrderOk         = $false
                NonNumeric      = @()
                ParseError      = 'heading found but no valid fenced ```json block follows it (bad fence, or non-JSON content immediately after the heading).'
                CollapsedFence  = $false
                Ordinal         = $ordinal
                Offset          = $headingMatch.Index
                RawText         = $headingMatch.Value
            }
            continue
        }

        $json = $match.Groups['json'].Value

        $order = @([regex]::Matches($json, '(?m)^\s*"([a-z_]+)"\s*:') | ForEach-Object { $_.Groups[1].Value })

        $parsed = $null
        $parseError = $null
        try { $parsed = $json | ConvertFrom-Json -AsHashtable }
        catch { $parseError = $_.Exception.Message }

        $nonNumeric = @(
            if ($parsed) {
                foreach ($field in $order) {
                    if ($field -in $script:ConsumptionTextFields) { continue }
                    $value = $parsed[$field]
                    if ($value -isnot [int] -and $value -isnot [long] -and $value -isnot [double] -and $value -isnot [decimal]) {
                        $field
                    }
                }
            }
        )

        $orderOk = @(Compare-Object -ReferenceObject $script:ConsumptionFieldOrder -DifferenceObject $order -SyncWindow 0).Count -eq 0

        # A fence of one or two backticks is what a ```json fence becomes when it
        # is written through a PowerShell double-quoted string (a backtick is that
        # language's escape character). The JSON inside is intact, so the block is
        # parsed and counted, and the caller warns instead of failing -- otherwise
        # the only way to clear the failure is to edit the earlier entry in place,
        # which is a history-integrity failure that latches pipelining off.
        $collapsedFence = $match.Groups['open'].Value.Length -ne 3 -or $match.Groups['close'].Value.Length -ne 3

        [pscustomobject]@{
            Source          = $SourceName
            IsOrchestration = [bool]$match.Groups['orch'].Success
            Fields          = $parsed
            Order           = $order
            OrderOk         = $orderOk
            NonNumeric      = $nonNumeric
            ParseError      = $parseError
            CollapsedFence  = $collapsedFence
            # U1 baseline-scoping identity (Amendment 3 §2 item 1/3): Ordinal is
            # this block's 1-based position among every regex match in this
            # file -- including unparseable ones -- so a baseline's recorded
            # per-file blockCount can classify it pre- or post-baseline even
            # when it never reaches ConvertFrom-Json. Offset/RawText are the
            # match's own character index and full text, hashed into the
            # baseline for an auditable per-block identity record.
            Ordinal         = $ordinal
            Offset          = $match.Index
            RawText         = $match.Value
        }
    }
}

# ---------------------------------------------------------------------------
# Cost derivation.
# ---------------------------------------------------------------------------

function Resolve-RateForBlockLocal {
    <#
    .SYNOPSIS
        Resolves a priced rate for one Consumption block: the block's own
        `priced_as` row when it resolves (trimmed, if needed), otherwise the
        block's `model_tier` row (flagged), otherwise -- for a pre-baseline/
        legacy block, or when no baseline was supplied at all -- the rate
        table's own 'default' tier (flagged), and never a fabricated or zero
        rate for a block this baseline-scoped fallback does not cover.
    .PARAMETER TreatUnresolvedAsWarning
        U1 no-throw fix (Amendment 3 §2 item 4): true for a block classified as
        pre-baseline/legacy, or whenever no baseline was supplied at all (both
        cases documented as "cannot scope, so it defers rather than blocks").
        A block appended after a supplied baseline still throws when
        unresolvable -- a new-data defect, not a deferred legacy one.
    #>
    param(
        [Parameter(Mandatory)]$Block,
        [Parameter(Mandatory)]$Rates,
        # Not [Parameter(Mandatory)]: PowerShell's binder rejects an empty
        # collection argument for a Mandatory collection-typed parameter, and an
        # accumulator list legitimately starts empty on a run with no warnings.
        [System.Collections.Generic.List[string]]$Warnings,
        [bool]$TreatUnresolvedAsWarning = $true
    )

    $pricedAsRaw = [string]$Block.Fields['priced_as']
    $pricedAsTrimmed = $pricedAsRaw.Trim()
    if ($pricedAsRaw -and $Rates.ByModel.ContainsKey($pricedAsRaw)) {
        return $Rates.ByModel[$pricedAsRaw]
    }
    if ($pricedAsTrimmed -and $pricedAsTrimmed -ne $pricedAsRaw -and $Rates.ByModel.ContainsKey($pricedAsTrimmed)) {
        $Warnings.Add("WARN: $($Block.Source): priced_as '$pricedAsRaw' only resolves to a rate row after trimming surrounding whitespace (to '$pricedAsTrimmed').")
        return $Rates.ByModel[$pricedAsTrimmed]
    }
    # Spelling variants of a real row ('GPT-5.3 Codex' for 'GPT-5.3-Codex') resolve
    # silently; then the block's own resolved `model` id, before any tier fallback.
    $byNormalized = if ($Rates.PSObject.Properties['ByNormalized']) { $Rates.ByNormalized } else { @{} }
    $pricedAsKey = ConvertTo-RateKeyLocal $pricedAsRaw
    if ($pricedAsKey -and $byNormalized.ContainsKey($pricedAsKey)) {
        return $byNormalized[$pricedAsKey]
    }
    $modelKey = ConvertTo-RateKeyLocal ([string]$Block.Fields['model'])
    if ($modelKey -and $modelKey -ne 'unknown' -and $byNormalized.ContainsKey($modelKey)) {
        $Warnings.Add("WARN: $($Block.Source): priced_as '$pricedAsRaw' has no rate row; priced at its recorded model '$($Block.Fields['model'])' instead.")
        return $byNormalized[$modelKey]
    }

    $tierRaw = [string]$Block.Fields['model_tier']
    $tierTrimmed = $tierRaw.Trim()
    if ($tierRaw -and $Rates.ByTier.ContainsKey($tierRaw)) {
        $Warnings.Add("WARN: $($Block.Source): priced_as '$pricedAsRaw' has no rate row; priced at the '$tierRaw' tier fallback instead.")
        return $Rates.ByTier[$tierRaw]
    }
    if ($tierTrimmed -and $tierTrimmed -ne $tierRaw -and $Rates.ByTier.ContainsKey($tierTrimmed)) {
        $Warnings.Add("WARN: $($Block.Source): priced_as '$pricedAsRaw' has no rate row; priced at the '$tierTrimmed' tier fallback instead (model_tier resolved only after trimming whitespace).")
        return $Rates.ByTier[$tierTrimmed]
    }

    if ($TreatUnresolvedAsWarning -and $Rates.ByTier.ContainsKey('default')) {
        $Warnings.Add("WARN: $($Block.Source): priced_as '$pricedAsRaw' and model_tier '$tierRaw' neither resolve to a rate row; this is a pre-baseline/legacy block (or no baseline was supplied to scope it), so it is priced at the rate table's 'default' tier fallback instead of terminating.")
        return $Rates.ByTier['default']
    }

    throw "Measure-SquadLedger: block in '$($Block.Source)' has priced_as '$pricedAsRaw' and model_tier '$tierRaw', neither of which resolves to a rate row. Refusing to price at 0 -- fix consumption-rates.md or the block."
}

function New-RoleAggregateLocal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory aggregate constructor; no system state is changed.')]
    param([Parameter(Mandatory)][string]$Label)

    [pscustomobject]@{
        Label        = $Label
        Blocks       = [System.Collections.Generic.List[pscustomobject]]::new()
        Turns        = 0.0
        Input        = 0.0
        Cached       = 0.0
        CacheWrite   = 0.0
        Output       = 0.0
        Cost         = 0.0
        RateMismatch = $false
        Basis        = 'estimated'
        # Attribution identity: Member/Agent/Tier are roster-sourced (team.md), set
        # by the caller once per aggregate, never derived from a block. Models,
        # ModelSources, and PricedAsUsed are distinct block values in first-seen
        # order -- the Attribution table's Model, Model Source, and Priced As
        # columns join these with ', ', never inventing or collapsing a value.
        Member       = ''
        Agent        = ''
        Tier         = ''
        Models       = [System.Collections.Generic.List[string]]::new()
        ModelSources = [System.Collections.Generic.List[string]]::new()
        PricedAsUsed = [System.Collections.Generic.List[string]]::new()
    }
}

function Add-BlockToAggregateLocal {
    param(
        [Parameter(Mandatory)]$Aggregate,
        [Parameter(Mandatory)]$Block,
        [Parameter(Mandatory)]$Rates,
        [Parameter(Mandatory)][double]$CalibrationFactor,
        # Not Mandatory -- see Resolve-RateForBlockLocal for why.
        [System.Collections.Generic.List[string]]$Warnings,
        [bool]$TreatUnresolvedRateAsWarning = $true
    )

    $rate = Resolve-RateForBlockLocal -Block $Block -Rates $Rates -Warnings $Warnings -TreatUnresolvedAsWarning $TreatUnresolvedRateAsWarning

    $turns = [double]$Block.Fields['internal_turns']
    $inTok = [double]$Block.Fields['input_tokens']
    $cached = [double]$Block.Fields['cached_tokens']
    $cacheWr = [double]$Block.Fields['cache_write_tokens']
    $outTok = [double]$Block.Fields['output_tokens']

    $effectiveRate = $rate
    if ($rate.ContainsKey('long_context_threshold') -and ($inTok + $cached) -gt [double]$rate.long_context_threshold) {
        $effectiveRate = @{} + $rate
        $effectiveRate.input = $rate.lc_input
        $effectiveRate.cached = $rate.lc_cached
        $effectiveRate.cache_write = $rate.lc_cache_write
        $effectiveRate.output = $rate.lc_output
    }

    $rawCost = ($inTok * $effectiveRate.input + $cached * $effectiveRate.cached + $cacheWr * $effectiveRate.cache_write + $outTok * $effectiveRate.output) / 1000000.0
    $cost = $rawCost * $CalibrationFactor

    $Aggregate.Turns += $turns
    $Aggregate.Input += $inTok
    $Aggregate.Cached += $cached
    $Aggregate.CacheWrite += $cacheWr
    $Aggregate.Output += $outTok
    $Aggregate.Cost += $cost
    if ([string]$Block.Fields['basis'] -eq 'tier-default') { $Aggregate.Basis = 'tier-default' }
    $Aggregate.Blocks.Add(@{ Block = $Block; Rate = $effectiveRate; Cost = $cost })

    # Attribution accumulation: a block's `model` is recorded exactly as written --
    # including the literal `unknown` -- and never replaced by the rate row that
    # priced it. `pricedAsName` is the rate's own key (see Get-RateTableLocal),
    # which is the tier-fallback's model name on a fallback and the block's own
    # `priced_as` on a direct hit, so the Priced As column can legitimately differ
    # from Model without either column ever being fabricated.
    $model = [string]$Block.Fields['model']
    $modelSource = [string]$Block.Fields['model_source']
    $pricedAsLabel = [string]$effectiveRate.pricedAsName
    if ($model -and $model -notin $Aggregate.Models) { $Aggregate.Models.Add($model) }
    if ($modelSource -and $modelSource -notin $Aggregate.ModelSources) { $Aggregate.ModelSources.Add($modelSource) }
    if ($pricedAsLabel -and $pricedAsLabel -notin $Aggregate.PricedAsUsed) { $Aggregate.PricedAsUsed.Add($pricedAsLabel) }
}

function Get-AttributionCompositeKeyLocal {
    <#
    .SYNOPSIS
        Builds the (Role, Member, Agent) composite key `-Check`'s Attribution
        comparison indexes and looks up by, trimmed and folded to invariant
        lowercase so spacing/casing drift does not split identity rows.
    .DESCRIPTION
        Role and Agent are no longer enough once connector-backed rows share the
        same `history/Squad Connector.md` file. Member Name is part of dispatch
        identity and keeps repeated connector activity split per member rather
        than collapsed onto one row.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Role,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Member,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Agent
    )
    '{0}|{1}|{2}' -f $Role.Trim().ToLowerInvariant(), $Member.Trim().ToLowerInvariant(), $Agent.Trim().ToLowerInvariant()
}

function Resolve-OrchestrationAgentLabelLocal {
    <#
    .SYNOPSIS
        Preserves the orchestration attribution agent label already present in
        consumption.md when that legacy identity is recognized.
    .DESCRIPTION
        Historical ledgers may carry either `Coordinator+Scribe` or
        `Squad Scribe` for the orchestration row's Agent cell. To keep `-Check`
        deterministic across old and new ledgers without rewriting history, the
        calculator reuses whichever known label the existing ledger already
        records. When no recognizable orchestration row exists, the caller's
        default label is kept.
    #>
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$ConsumptionContent = '',
        [Parameter(Mandatory)]
        [string]$DefaultLabel
    )

    if (-not $ConsumptionContent) { return $DefaultLabel }

    $orchestrationAgents = [System.Collections.Generic.List[string]]::new()
    foreach ($table in (Get-MarkdownTableLocal -Content $ConsumptionContent | Where-Object { 'Role' -in $_.Header -and 'Agent' -in $_.Header })) {
        foreach ($row in $table.Rows) {
            if (([string]$row['Role']).Trim().ToLowerInvariant() -ne 'orchestration') { continue }
            $agent = ([string]$row['Agent']).Trim()
            if (-not $agent) { continue }
            # Normalize optional spaces around '+' so legacy rows like
            # `Coordinator + Scribe` still map to the canonical label.
            $orchestrationAgents.Add(($agent -replace '\s*\+\s*', '+'))
        }
    }

    if (@($orchestrationAgents | Where-Object { $_ -eq 'Coordinator+Scribe' }).Count -gt 0) { return 'Coordinator+Scribe' }
    if (@($orchestrationAgents | Where-Object { $_ -eq 'Squad Scribe' }).Count -gt 0) { return 'Squad Scribe' }
    return $DefaultLabel
}

# ---------------------------------------------------------------------------
# U1 (Amendment 3 §2): content-level baseline (-EmitBaseline / -BaselinePath),
# protected-artifact scope, and key-lookup mode. Self-contained, like every
# other function in this script -- it ships to consumers and must not import
# anything from tests/.
# ---------------------------------------------------------------------------

function Test-PathUnderSquadTrackingLocal {
    <#
    .SYNOPSIS
        True when a path (existing or not yet created) resolves under any
        `.copilot-tracking/squad` tree. Baselines must live entirely outside the
        squad root, so `-EmitBaseline`/`-BaselinePath` refuse such a path rather
        than silently writing (or trusting) squad-tracked state.
    #>
    param([Parameter(Mandatory)][string]$Path)
    # GetFullPath resolves a not-yet-existing path against the current
    # directory without requiring it to exist -- -EmitBaseline's target
    # legitimately does not exist until this run creates it.
    $full = [System.IO.Path]::GetFullPath($Path)
    $normalized = $full -replace '\\', '/'
    return $normalized -match '(?i)(^|/)\.copilot-tracking/squad(/|$)'
}

function Get-Sha256HexLocal {
    <#
    .SYNOPSIS
        Lowercase-hex SHA-256 of a byte array. Byte-based (never string-based)
        so a baseline's hash is encoding-agnostic and a prefix-byte slice hashes
        identically to hashing that same slice read fresh from disk.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $hashBytes = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
}

function Get-AppendOnlyFileListLocal {
    <#
    .SYNOPSIS
        The append-only file set a baseline covers: every history/*.md file,
        plus decisions.md and notifications.md when present (Amendment 3 §2
        item 1). state.json, consumption.md, and consumption-sessions.json are
        never included here -- they are replace-semantics files the Scribe legitimately rewrites every
        stage, per Amendment 2 §8's "-Check -ExpectedHistoryCounts is retained
        for replace-semantics consumption" language.
    #>
    param([Parameter(Mandatory)][string]$SquadRoot, [Parameter(Mandatory)]$HistoryFiles)

    $list = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($file in $HistoryFiles) {
        $list.Add([pscustomobject]@{ RelativePath = "history/$($file.Name)"; FullPath = $file.FullName })
    }
    foreach ($name in @('decisions.md', 'notifications.md')) {
        $full = Join-Path $SquadRoot $name
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $list.Add([pscustomobject]@{ RelativePath = $name; FullPath = $full })
        }
    }
    $list
}

function Assert-ProtectedPathNotReplaceSemanticsLocal {
    <#
    .SYNOPSIS
        Throws if a caller-supplied -ProtectedPath entry names state.json,
        consumption.md, or consumption-sessions.json -- all are excluded from
        protection by design (they are rewritten by ledger transactions), not
        merely by omission.
    #>
    param([Parameter(Mandatory)][string[]]$ProtectedPath)
    foreach ($rel in $ProtectedPath) {
        $normalized = ($rel -replace '\\', '/').Trim('/')
        if ($normalized -match '(?i)^(state\.json|consumption\.md|consumption-sessions\.json)$') {
            throw "Measure-SquadLedger: -ProtectedPath must not name '$rel' -- state.json, consumption.md, and consumption-sessions.json are replace-semantics files the ledger transaction legitimately rewrites and are excluded from protected-artifact checks by design."
        }
    }
}

function Get-BaselineFileEntryLocal {
    <#
    .SYNOPSIS
        One append-only file's baseline entry: byte Length, full-content
        SHA-256, a combined `##`/`###` heading count, and the identity
        (ordinal + character offset + content hash) of every `#### Consumption`
        block already present -- so a later `-BaselinePath` check can tell a
        pre-baseline (legacy) block (ordinal <= this entry's blockCount) from
        one appended after this baseline was taken.
    #>
    param([Parameter(Mandatory)][string]$FullPath)

    $bytes = [System.IO.File]::ReadAllBytes($FullPath)
    $content = [System.Text.Encoding]::UTF8.GetString($bytes)
    $headingCount = @([regex]::Matches($content, '(?m)^(?:##|###)[ \t]')).Count
    $blocks = @(Get-ConsumptionBlockLocal -Content $content -SourceName ([System.IO.Path]::GetFileName($FullPath)))

    [ordered]@{
        length       = $bytes.Length
        sha256       = (Get-Sha256HexLocal -Bytes $bytes)
        headingCount = $headingCount
        blockCount   = $blocks.Count
        blocks       = @(
            foreach ($block in $blocks) {
                [ordered]@{
                    ordinal = $block.Ordinal
                    offset  = $block.Offset
                    sha256  = (Get-Sha256HexLocal -Bytes ([System.Text.Encoding]::UTF8.GetBytes($block.RawText)))
                }
            }
        )
    }
}

function Get-ProtectedFileEntryLocal {
    <#
    .SYNOPSIS
        One protected artifact's baseline entry: whether it existed at
        baseline time, and its full-file SHA-256 when it did.
    #>
    param([Parameter(Mandatory)][string]$FullPath)
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        return [ordered]@{ exists = $false; sha256 = $null }
    }
    $bytes = [System.IO.File]::ReadAllBytes($FullPath)
    [ordered]@{ exists = $true; sha256 = (Get-Sha256HexLocal -Bytes $bytes) }
}

function New-SquadLedgerBaselineLocal {
    <#
    .SYNOPSIS
        Builds the -EmitBaseline JSON object: an append-only-file map and a
        caller-named protected-artifact map, both keyed by squad-root-relative
        path with forward slashes (so the JSON is diff-friendly and platform-
        independent regardless of the host's path separator).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory baseline object constructor; no system state is changed (writing it to disk is the caller''s job).')]
    param(
        [Parameter(Mandatory)][string]$SquadRoot,
        [Parameter(Mandatory)]$HistoryFiles,
        [string[]]$ProtectedPath = @()
    )

    $appendOnly = [ordered]@{}
    foreach ($entry in (Get-AppendOnlyFileListLocal -SquadRoot $SquadRoot -HistoryFiles $HistoryFiles)) {
        $appendOnly[$entry.RelativePath] = Get-BaselineFileEntryLocal -FullPath $entry.FullPath
    }

    $protected = [ordered]@{}
    foreach ($rel in $ProtectedPath) {
        $normalizedRel = ($rel -replace '\\', '/').Trim('/')
        $full = Join-Path $SquadRoot $normalizedRel
        $protected[$normalizedRel] = Get-ProtectedFileEntryLocal -FullPath $full
    }

    [ordered]@{
        schemaVersion = 1
        emittedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        appendOnly    = $appendOnly
        protected     = $protected
    }
}

function Copy-BaselineSourceFilesLocal {
    <#
    .SYNOPSIS
        Writes full pre-write copies of every append-only and protected file,
        plus consumption.md, consumption-sessions.json, and state.json, into a sibling `<name>.files/`
        directory next to the baseline JSON (Amendment 3 §2 item 1 / Amendment
        2 E3/A-4), mirroring each file's squad-root-relative path.
    #>
    param(
        [Parameter(Mandatory)][string]$SquadRoot,
        [Parameter(Mandatory)]$HistoryFiles,
        [string[]]$ProtectedPath = @(),
        [Parameter(Mandatory)][string]$DestinationRoot
    )

    $sources = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($entry in (Get-AppendOnlyFileListLocal -SquadRoot $SquadRoot -HistoryFiles $HistoryFiles)) {
        $sources.Add($entry)
    }
    foreach ($rel in $ProtectedPath) {
        $normalizedRel = ($rel -replace '\\', '/').Trim('/')
        $full = Join-Path $SquadRoot $normalizedRel
        if (Test-Path -LiteralPath $full -PathType Leaf) { $sources.Add([pscustomobject]@{ RelativePath = $normalizedRel; FullPath = $full }) }
    }
    foreach ($name in @('consumption.md', 'consumption-sessions.json', 'state.json')) {
        $full = Join-Path $SquadRoot $name
        if (Test-Path -LiteralPath $full -PathType Leaf) { $sources.Add([pscustomobject]@{ RelativePath = $name; FullPath = $full }) }
    }

    foreach ($source in $sources) {
        $destination = Join-Path $DestinationRoot ($source.RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $destinationDir = Split-Path -Parent $destination
        if ($destinationDir -and -not (Test-Path -LiteralPath $destinationDir -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $source.FullPath -Destination $destination -Force
    }
}

function Get-InsertionOffsetLocal {
    <#
    .SYNOPSIS
        Returns the byte offset where new text was inserted when Current is
        exactly Original with one run of bytes added somewhere before its end
        (every original byte kept, in order); $null otherwise.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Original,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Current
    )
    if ($Current.Length -le $Original.Length) { return $null }
    $prefix = 0
    while ($prefix -lt $Original.Length -and $Original[$prefix] -eq $Current[$prefix]) { $prefix++ }
    if ($prefix -eq $Original.Length) { return $null }
    $suffix = 0
    while ($suffix -lt ($Original.Length - $prefix) -and $Original[$Original.Length - 1 - $suffix] -eq $Current[$Current.Length - 1 - $suffix]) { $suffix++ }
    if ($prefix + $suffix -eq $Original.Length) { return $prefix }
    return $null
}

function Test-FenceOnlyRepairLocal {
    <#
    .SYNOPSIS
        True when Current is Original plus appended text, except that one or more
        collapsed code fences (a line of one or two backticks, optionally followed
        by `json`) in Original were restored to three backticks. Line endings are
        normalized; every other character must match.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Original,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Current
    )
    $normalize = {
        param([string]$Text)
        ($Text -replace '\r\n', "`n") -replace '(?m)^`{1,3}(json)?[ \t]*$', '```$1'
    }
    $originalText = [System.Text.Encoding]::UTF8.GetString($Original)
    $currentText = [System.Text.Encoding]::UTF8.GetString($Current)
    if ($originalText -notmatch '(?m)^`{1,2}(json)?[ \t]*\r?$') { return $false }
    $normalizedOriginal = (& $normalize $originalText).TrimEnd()
    $normalizedCurrent = & $normalize $currentText
    return $normalizedCurrent.StartsWith($normalizedOriginal, [System.StringComparison]::Ordinal)
}

function Test-SquadLedgerBaselineLocal {
    <#
    .SYNOPSIS
        The -BaselinePath -Check verification (Amendment 3 §2 item 1): FAILs on
        an append-only file shrink, a prefix edit (first baseline-Length bytes
        no longer hashing to the baseline's recorded full-content SHA-256), a
        protected-artifact hash change not covered by -AllowedWritePath, or a
        baseline-recorded file that no longer exists. Never checks state.json,
        consumption.md, or consumption-sessions.json -- excluded by design.
    .DESCRIPTION
        Review fix (coordinator finding): the protected set actually verified is
        the UNION of the baseline's own recorded `protected` map and any caller
        -ProtectedPath, not the caller-supplied list alone. A verifier that omits
        -ProtectedPath at -Check time still catches every artifact the matching
        -EmitBaseline call protected -- the caller-supplied list only adds paths
        beyond what the baseline already recorded, it never narrows the set.
    #>
    param(
        [Parameter(Mandatory)]$Baseline,
        [Parameter(Mandatory)][string]$SquadRoot,
        [Parameter(Mandatory)]$HistoryFiles,
        [string[]]$ProtectedPath = @(),
        [string[]]$AllowedWritePath = @(),
        [string]$BaselineFilesRoot
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $allowedLookup = @{}
    foreach ($p in $AllowedWritePath) { $allowedLookup[(($p -replace '\\', '/').Trim('/')).ToLowerInvariant()] = $true }

    $currentByRel = @{}
    foreach ($entry in (Get-AppendOnlyFileListLocal -SquadRoot $SquadRoot -HistoryFiles $HistoryFiles)) {
        $currentByRel[$entry.RelativePath] = $entry.FullPath
    }

    foreach ($relPath in @($Baseline.appendOnly.PSObject.Properties.Name)) {
        $baseEntry = $Baseline.appendOnly.$relPath
        if (-not $currentByRel.ContainsKey($relPath)) {
            $failures.Add("Baseline file missing: '$relPath' was recorded in the baseline but no longer exists.")
            continue
        }
        $bytes = [System.IO.File]::ReadAllBytes($currentByRel[$relPath])
        $baselineLength = [int64]$baseEntry.length
        if ($bytes.Length -lt $baselineLength) {
            $failures.Add("Append-only file shrank: '$relPath' was $baselineLength byte(s) at baseline, now $($bytes.Length).")
            continue
        }
        if ($baselineLength -gt 0) {
            $prefixBytes = $bytes[0..($baselineLength - 1)]
            $prefixHash = Get-Sha256HexLocal -Bytes $prefixBytes
            if ($prefixHash -ne $baseEntry.sha256) {
                $insertedAt = $null
                $originalCopy = if ($BaselineFilesRoot) { Join-Path $BaselineFilesRoot $relPath } else { $null }
                if ($originalCopy -and (Test-Path -LiteralPath $originalCopy -PathType Leaf)) {
                    $insertedAt = Get-InsertionOffsetLocal -Original ([System.IO.File]::ReadAllBytes($originalCopy)) -Current $bytes
                }
                if ($null -ne $insertedAt) {
                    # Text inserted just before a trailing `<!-- ... -->` marker -- with no
                    # original entry after it -- is an append in every sense the ledger reads
                    # (same entry order, every byte kept). Warn, never fail, so a misplaced
                    # marker cannot latch pipelining off or block a run.
                    $originalTail = [System.Text.Encoding]::UTF8.GetString($bytes, [int]($bytes.Length - ($baselineLength - $insertedAt)), [int]($baselineLength - $insertedAt))
                    if ($originalTail -match '^\s*(<!--(?:(?!-->)[\s\S])*-->\s*)+$') {
                        Write-Warning "WARN: '$relPath' gained its new entries just above its trailing marker comment instead of after it; every original byte and the entry order are intact, so this is not a failure. Append future entries at the very end of the file."
                    }
                    else {
                        $failures.Add("Append-only file's entries were inserted inside the file, not appended: '$relPath' keeps every original byte, but new text starts at byte $insertedAt of $baselineLength instead of at the end. Append new entries after the last existing entry, never directly under the file's marker comment.")
                    }
                }
                elseif ($originalCopy -and (Test-Path -LiteralPath $originalCopy -PathType Leaf) -and
                    (Test-FenceOnlyRepairLocal -Original ([System.IO.File]::ReadAllBytes($originalCopy)) -Current $bytes)) {
                    Write-Warning "WARN: '$relPath' had a collapsed code fence in an earlier entry restored to three backticks; every other byte of the earlier entries is unchanged, so this is not a failure. Earlier entries are append-only: leave a collapsed fence as it is, the ledger reads it."
                }
                else {
                    $failures.Add("Append-only file's original content changed: '$relPath' first $baselineLength byte(s) no longer hash to the baseline's recorded SHA-256 (a prefix edit, not only an append).")
                }
            }
        }
    }

    # Review fix (coordinator finding, fail-open): the checked protected set is the
    # UNION of every path the baseline itself recorded under `protected` and any
    # caller-supplied -ProtectedPath, not the caller-supplied list alone -- a
    # verifier that omits -ProtectedPath at -Check time must still catch every
    # protected artifact the baseline actually covers, or the check silently no-ops.
    # Uses `ForEach-Object Name` rather than the `.PSObject.Properties.Name` member-
    # enumeration shorthand: under this script's `Set-StrictMode -Version Latest`,
    # that shorthand throws "property 'Name' not found" when the PSCustomObject has
    # zero NoteProperties (an empty `protected` map, the common case for a baseline
    # with no caller-named artifacts) instead of returning an empty array.
    $baselineProtectedNames = @($Baseline.protected.PSObject.Properties | ForEach-Object Name)
    $protectedRelSet = [ordered]@{}
    foreach ($baselineRel in $baselineProtectedNames) {
        $protectedRelSet[$baselineRel] = $true
    }
    foreach ($rel in $ProtectedPath) {
        $normalizedRel = ($rel -replace '\\', '/').Trim('/')
        $protectedRelSet[$normalizedRel] = $true
    }

    foreach ($normalizedRel in $protectedRelSet.Keys) {
        if ($allowedLookup.ContainsKey($normalizedRel.ToLowerInvariant())) { continue }
        if ($baselineProtectedNames -notcontains $normalizedRel) {
            $failures.Add("Protected artifact '$normalizedRel' was not recorded in the baseline; re-emit the baseline before checking it.")
            continue
        }
        $baseEntry = $Baseline.protected.$normalizedRel
        $full = Join-Path $SquadRoot $normalizedRel
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            if ($baseEntry.exists) {
                $failures.Add("Protected artifact missing: '$normalizedRel' existed at baseline time and no longer exists.")
            }
            continue
        }
        $hash = Get-Sha256HexLocal -Bytes ([System.IO.File]::ReadAllBytes($full))
        if ((-not $baseEntry.exists) -or ($hash -ne $baseEntry.sha256)) {
            $failures.Add("Protected artifact changed: '$normalizedRel' no longer matches its baseline SHA-256 and is not named in -AllowedWritePath.")
        }
    }

    @($failures)
}

function Get-BaselineBlockCountLocal {
    <#
    .SYNOPSIS
        The blockCount a loaded baseline recorded for one history file, or $0
        when the baseline exists but has no entry for that file (a file
        created after the baseline was taken -- every block in it is
        post-baseline). Returns $null only when $Baseline itself is $null (no
        -BaselinePath supplied at all), which callers treat as "cannot scope"
        rather than "zero pre-baseline blocks".
    #>
    param($Baseline, [Parameter(Mandatory)][string]$HistoryFileName)
    if (-not $Baseline) { return $null }
    $relPath = "history/$HistoryFileName"
    if (@($Baseline.appendOnly.PSObject.Properties.Name) -contains $relPath) {
        return [int]$Baseline.appendOnly.$relPath.blockCount
    }
    return 0
}

function Test-LedgerBlockIsLegacyLocal {
    <#
    .SYNOPSIS
        True when a consumption block should be treated as pre-baseline/legacy
        for both the no-throw pricing fallback (item 4) and the
        malformed/illegal-model_source WARN-vs-FAIL scoping (item 3): no
        baseline was supplied at all, or the block's own ordinal position in
        its file is within the baseline's recorded blockCount for that file.
    #>
    param($Baseline, [Parameter(Mandatory)][string]$HistoryFileName, [Parameter(Mandatory)][int]$Ordinal)
    $baselineCount = Get-BaselineBlockCountLocal -Baseline $Baseline -HistoryFileName $HistoryFileName
    if ($null -eq $baselineCount) { return $true }
    return $Ordinal -le $baselineCount
}

function Invoke-SquadLedgerLookupLocal {
    <#
    .SYNOPSIS
        Key-lookup mode (Amendment 3 §2 item 2): a deterministic, model-free
        existence check for resume logic. Prints EXISTS/MISSING (or, with
        -Format json, a structured object) and returns the process exit code
        the caller should use (0 = exists, 1 = missing).
    #>
    param(
        [Parameter(Mandatory)][string]$SquadRoot,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$Topic,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$Slot,
        [ValidateSet('markdown', 'json')][string]$Format = 'markdown'
    )

    $key = '{0}::{1}::{2}::{3}' -f $RunId, $Topic, $Stage, $Slot
    $historyDir = Join-Path $SquadRoot 'history'
    $matchingFiles = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $historyDir -PathType Container) {
        foreach ($file in (Get-ChildItem -LiteralPath $historyDir -Filter '*.md' -File | Sort-Object Name)) {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
            if ($raw -and $raw.Contains($key)) { $matchingFiles.Add($file.Name) }
        }
    }
    $exists = $matchingFiles.Count -gt 0

    if ($Format -eq 'json') {
        # Write-Host (not a bare pipeline expression): the caller assigns this
        # function's call to $lookupExitCode to capture the trailing `return`
        # value below, which would otherwise silently swallow success-stream
        # output (an object piped to ConvertTo-Json) into that same variable.
        Write-Host ([ordered]@{ key = $key; exists = $exists; files = @($matchingFiles) } | ConvertTo-Json -Depth 4)
    }
    elseif ($exists) {
        Write-Host "EXISTS: a history entry recorded for key '$key' (found in: $($matchingFiles -join ', '))." -ForegroundColor Green
    }
    else {
        Write-Host "MISSING: no history entry recorded for key '$key'." -ForegroundColor Yellow
    }

    return [int](-not $exists)
}

# ---------------------------------------------------------------------------
# -Write mode helpers: the Scribe's own deterministic writer for the two
# derived files, so no model transcribes a derived figure by hand.
# ---------------------------------------------------------------------------

function Get-Utf8EncodingForFileLocal {
    <#
    .SYNOPSIS
        Returns a UTF-8 encoding that preserves whether the file carried a BOM.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    return [System.Text.UTF8Encoding]::new($hasBom)
}

function Get-ConsumptionFragmentUpdateLocal {
    <#
    .SYNOPSIS
        Returns consumption.md's new text with `## Attribution` through the closing
        fence of `### Derivation` replaced by the derived fragment, preserving every
        other line and the file's newline style and BOM. Writes nothing.
    #>
    param(
        [Parameter(Mandatory)][string]$ConsumptionPath,
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$FragmentLines
    )
    if (-not (Test-Path -LiteralPath $ConsumptionPath -PathType Leaf)) {
        throw "Measure-SquadLedger -Write: consumption.md not found at '$ConsumptionPath'. Seed it from the consumption.md template in references/consumption.md first."
    }
    $encoding = Get-Utf8EncodingForFileLocal -Path $ConsumptionPath
    $content = [System.IO.File]::ReadAllText($ConsumptionPath, $encoding)
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $content -split '\r?\n'

    $start = -1; $derivation = -1; $open = -1; $close = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($start -lt 0) {
            if ($lines[$i] -match '^##\s+Attribution\s*$') { $start = $i }
        }
        elseif ($derivation -lt 0) {
            if ($lines[$i] -match '^###\s+Derivation\s*$') { $derivation = $i }
        }
        elseif ($open -lt 0) {
            if ($lines[$i] -match '^```') { $open = $i }
            elseif ($lines[$i] -match '^#{1,3}\s') { break }
        }
        elseif ($lines[$i] -match '^```\s*$') { $close = $i; break }
    }
    if ($start -lt 0 -or $derivation -lt 0 -or $open -lt 0 -or $close -lt 0) {
        throw "Measure-SquadLedger -Write: consumption.md at '$ConsumptionPath' lacks the '## Attribution' ... '### Derivation' fenced block this mode replaces; nothing was written. Restore its shape from the consumption.md template in references/consumption.md first."
    }

    $head = if ($start -gt 0) { $lines[0..($start - 1)] } else { @() }
    $tail = if ($close -lt $lines.Count - 1) { $lines[($close + 1)..($lines.Count - 1)] } else { @() }
    $text = (@($head) + @($FragmentLines) + @($tail)) -join $newline
    return [pscustomobject]@{ Path = $ConsumptionPath; Text = $text; Encoding = $encoding }
}

function Get-StateRunTotalUpdateLocal {
    <#
    .SYNOPSIS
        Returns state.json's new text with only currentRun.estCostUsd and
        currentRun.estCreditsTotal replaced in place, so no other byte of the file
        changes. Writes nothing.
    #>
    param(
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)][double]$CostUsd,
        [Parameter(Mandatory)][double]$Credits
    )
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        throw "Measure-SquadLedger -Write: state.json not found at '$StatePath'."
    }
    $encoding = Get-Utf8EncodingForFileLocal -Path $StatePath
    $text = [System.IO.File]::ReadAllText($StatePath, $encoding)
    try { $parsed = $text | ConvertFrom-Json -AsHashtable }
    catch { throw "Measure-SquadLedger -Write: state.json at '$StatePath' failed to parse: $($_.Exception.Message)" }
    if (-not $parsed.ContainsKey('currentRun') -or $parsed['currentRun'] -isnot [System.Collections.IDictionary]) {
        throw "Measure-SquadLedger -Write: state.json at '$StatePath' has no 'currentRun' object; nothing was written."
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $values = [ordered]@{
        estCostUsd      = $CostUsd.ToString('F4', $invariant)
        estCreditsTotal = $Credits.ToString('F2', $invariant)
    }
    $replacements = foreach ($key in $values.Keys) {
        if (-not $parsed['currentRun'].Contains($key)) {
            throw "Measure-SquadLedger -Write: state.json currentRun has no '$key' key; nothing was written."
        }
        $found = [regex]::Matches($text, '"' + $key + '"\s*:\s*(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|null)')
        if ($found.Count -ne 1) {
            throw "Measure-SquadLedger -Write: expected exactly one numeric '$key' in state.json, found $($found.Count); nothing was written."
        }
        [pscustomobject]@{ Index = $found[0].Groups[1].Index; Length = $found[0].Groups[1].Length; Value = $values[$key] }
    }
    foreach ($r in @($replacements | Sort-Object Index -Descending)) {
        $text = $text.Substring(0, $r.Index) + $r.Value + $text.Substring($r.Index + $r.Length)
    }
    return [pscustomobject]@{ Path = $StatePath; Text = $text; Encoding = $encoding }
}

# ---------------------------------------------------------------------------
# -SessionLog: exact per-role usage from the host session log. Native rows replace
# estimates only after complete identity, coverage, token-detail, and total checks.
# ---------------------------------------------------------------------------

function Resolve-SessionLogPathsLocal {
    <#
    .SYNOPSIS
        Resolves every repository-matching events.jsonl path, newest first for `auto`.
    #>
    param(
        [Parameter(Mandatory)][string]$SessionLog,
        [Parameter(Mandatory)][string]$SquadRoot
    )
    $marker = [regex]::Match($SquadRoot, '^(?<repo>.*?)[\\/]\.copilot-tracking([\\/]|$)')
    $repoRoot = if ($marker.Success) { $marker.Groups['repo'].Value } else { (Get-Location).Path }
    if (-not (Get-Command Resolve-SquadSessionLogPaths -ErrorAction SilentlyContinue)) {
        $usageModule = Join-Path $PSScriptRoot 'SquadUsage.psm1'
        if (-not (Test-Path -LiteralPath $usageModule -PathType Leaf)) {
            throw 'SquadUsage.psm1 is required when -SessionLog is used.'
        }
        Import-Module $usageModule -Force
    }
    if (Get-Command Resolve-SquadSessionLogPaths -ErrorAction SilentlyContinue) {
        return @(Resolve-SquadSessionLogPaths -SessionLog $SessionLog -RepoRoot $repoRoot)
    }
    $single = Resolve-SquadSessionLogPath -SessionLog $SessionLog -RepoRoot $repoRoot
    if ($single) { return @($single) }
    return @()
}

function Read-SessionUsageLocal {
    <#
    .SYNOPSIS
        Reads subagent.completed events plus exact native usage records from a host
        session log. A sub-squad root counts only dispatches whose task prompt
        names its `members/<name>` root. Opened with shared read so a live
        session can keep writing; an unparseable (partially written) line is skipped.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SquadRoot
    )
    if (-not (Get-Command Get-SquadUsageSnapshot -ErrorAction SilentlyContinue)) {
        $usageModule = Join-Path $PSScriptRoot 'SquadUsage.psm1'
        if (-not (Test-Path -LiteralPath $usageModule -PathType Leaf)) {
            throw 'SquadUsage.psm1 is required when -SessionLog is used.'
        }
        Import-Module $usageModule -Force
    }
    $memberMatch = [regex]::Match($SquadRoot, '[\\/]members[\\/](?<name>[^\\/]+)[\\/]?$')
    $memberPattern = if ($memberMatch.Success) { 'members[\\/]+' + [regex]::Escape($memberMatch.Groups['name'].Value) + '([\\/]|\b)' } else { $null }

    $dispatches = [System.Collections.Generic.List[pscustomobject]]::new()
    $fusionSolvers = [System.Collections.Generic.List[string]]::new()
    $prompts = @{}
    $taskPromptCount = 0
    $memberTaskPromptCount = 0
    $memberRootLifecycleWriteSeen = $false
    $usageSnapshot = Get-SquadUsageSnapshot -EventsPath $Path -IncludeAgentRuns
    $first = $null
    $last = $null

    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $reader = [System.IO.StreamReader]::new($stream)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            $typeMatch = [regex]::Match($line, '"type"\s*:\s*"(?<type>subagent\.completed|session\.fusion_resolved|tool\.execution_start)"')
            $timeMatch = [regex]::Match($line, '"timestamp"\s*:\s*"(?<ts>[^"]+)"')
            if ($timeMatch.Success) {
                if (-not $first) { $first = $timeMatch.Groups['ts'].Value }
                $last = $timeMatch.Groups['ts'].Value
            }
            if (-not $typeMatch.Success) { continue }
            $type = $typeMatch.Groups['type'].Value
            if ($type -eq 'tool.execution_start' -and
                (-not $memberPattern -or $line -notmatch '"toolName"\s*:\s*"(?:task|runSubagent|powershell)"')) { continue }
            try { $sessionEvent = $line | ConvertFrom-Json -AsHashtable } catch { continue }
            $data = $sessionEvent['data']
            if (-not $data) { continue }
            switch ($type) {
                'tool.execution_start' {
                    $toolName = [string]$data['toolName']
                    $arguments = $data['arguments'] | ConvertTo-Json -Depth 6 -Compress
                    if ($toolName -in @('task', 'runSubagent')) {
                        $prompts[[string]$data['toolCallId']] = $arguments
                        $taskPromptCount++
                        if ($arguments -match $memberPattern) { $memberTaskPromptCount++ }
                    }
                    elseif ($arguments -match '(?i)\b(?:Write-SquadFederationHandoff|Promote-SquadFederation|Initialize-SquadFederation)\.ps1\b') {
                        $memberRootLifecycleWriteSeen = $true
                    }
                }
                'session.fusion_resolved' {
                    $primarySolver = [string]$data['primaryModel']
                    if ($primarySolver -and $primarySolver -notin $fusionSolvers) { $fusionSolvers.Add($primarySolver) }
                }
                'subagent.completed' {
                    $firstDispatched = if ($data.ContainsKey('firstDispatchedModel')) { [string]$data['firstDispatchedModel'] } else { '' }
                    if ($firstDispatched -and ([string]$data['model']) -match '(?i)^hydrafusion' -and $firstDispatched -notin $fusionSolvers) {
                        $fusionSolvers.Add($firstDispatched)
                    }
                    $dispatches.Add([pscustomobject]@{
                            ToolCallId           = [string]$data['toolCallId']
                            AgentName            = [string]$data['agentName']
                            Model                = [string]$data['model']
                            FirstDispatchedModel = $firstDispatched
                            Tokens               = [double]$data['totalTokens']
                            DurationMs           = [double]$data['durationMs']
                        })
                }
            }
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }

    if ($memberPattern) {
        $kept = @($dispatches | Where-Object { $prompts.ContainsKey($_.ToolCallId) -and $prompts[$_.ToolCallId] -match $memberPattern })
        $dispatches = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($d in $kept) { $dispatches.Add($d) }
    }

    [pscustomobject]@{
        Path          = $Path
        SessionId     = if ($usageSnapshot.sessionId) { [string]$usageSnapshot.sessionId } else { Split-Path -Leaf (Split-Path -Parent $Path) }
        Dispatches    = $dispatches
        FusionSolvers = @($fusionSolvers)
        NanoAiu       = if ($usageSnapshot.status -eq 'complete') { $usageSnapshot.totalNanoAiu } else { $null }
        UsageSnapshot = $usageSnapshot
        First         = $first
        Last          = $last
        MemberName    = if ($memberMatch.Success) { $memberMatch.Groups['name'].Value } else { $null }
        MemberScopeExclusive = [bool](
            $memberMatch.Success -and
            $taskPromptCount -gt 0 -and
            $memberTaskPromptCount -eq $taskPromptCount -and
            -not $memberRootLifecycleWriteSeen
        )
        MemberTaskPromptCount = $memberTaskPromptCount
        SessionTaskPromptCount = $taskPromptCount
        MemberRootLifecycleWriteSeen = $memberRootLifecycleWriteSeen
    }
}

function Get-NativeIdentityHashLocal {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Identity)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Identity)))
}

function Assert-ExactCacheFieldsLocal {
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Object,
        [Parameter(Mandatory)][string[]]$Required,
        [Parameter(Mandatory)][string]$Where
    )
    foreach ($field in $Required) {
        if (-not $Object.Contains($field)) { throw "$Where is missing '$field'." }
    }
    foreach ($field in $Object.Keys) {
        if ($field -notin $Required) { throw "$Where contains unsupported field '$field'." }
    }
}

function ConvertTo-NonNegativeDecimalLocal {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Where)
    $number = [decimal]0
    try { $number = [decimal]$Value }
    catch { throw "$Where is not numeric." }
    if ($number -lt 0) { throw "$Where is negative." }
    $number
}

function ConvertTo-NonNegativeLongLocal {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Where)
    $number = 0L
    if (-not [long]::TryParse([string]$Value, [ref]$number) -or $number -lt 0) {
        throw "$Where is not a non-negative integer."
    }
    $number
}

function Get-RecordedHistoryCoverageLocal {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$ConsumptionContent)
    $coverage = [ordered]@{}
    $derivation = [regex]::Match($ConsumptionContent, '(?ms)^###\s+Derivation\s*?\r?\n.*?```text\r?\n(?<body>.*?)\r?\n```')
    if (-not $derivation.Success) { return $coverage }
    foreach ($line in [regex]::Matches($derivation.Groups['body'].Value, '(?m)^(?<file>.+\.md) — \d+ block\(s\) — identities: (?<ids>.*)$')) {
        $fileName = $line.Groups['file'].Value.Trim()
        $text = $line.Groups['ids'].Value.Trim()
        $ids = [string[]]@()
        if ($text -and $text -ne '(none)') {
            $ids = [string[]]@($text -split ',' | ForEach-Object { $_.Trim() })
        }
        if (@($ids | Where-Object { $_ -notmatch '^[0-9a-f]{8}$' }).Count -gt 0) {
            throw "Exact ledger history coverage for '$fileName' contains an invalid identity."
        }
        $coverage[$fileName] = @($ids)
    }
    $coverage
}

function Add-HistoryCoverageLocal {
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Target,
        [Parameter(Mandatory)][Collections.IDictionary]$Source
    )
    foreach ($fileName in $Source.Keys) {
        if (-not $Target.Contains($fileName)) {
            $Target[$fileName] = [Collections.Generic.List[string]]::new()
        }
        foreach ($identity in @($Source[$fileName])) { $Target[$fileName].Add([string]$identity) }
    }
}

function Get-CumulativeHistoryCoverageLocal {
    param([AllowEmptyCollection()][object[]]$Sessions = @())
    $coverage = [ordered]@{}
    foreach ($session in $Sessions) {
        Add-HistoryCoverageLocal -Target $coverage -Source $session.historyCoverage
    }
    $result = [ordered]@{}
    foreach ($fileName in $coverage.Keys) { $result[$fileName] = @($coverage[$fileName]) }
    $result
}

function Join-HistoryCoverageLocal {
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Left,
        [Parameter(Mandatory)][Collections.IDictionary]$Right
    )
    $combined = [ordered]@{}
    Add-HistoryCoverageLocal -Target $combined -Source $Left
    Add-HistoryCoverageLocal -Target $combined -Source $Right
    $result = [ordered]@{}
    foreach ($fileName in $combined.Keys) { $result[$fileName] = @($combined[$fileName]) }
    $result
}

function Test-HistoryCoveragePrefixLocal {
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Recorded,
        [Parameter(Mandatory)][Collections.IDictionary]$Current,
        [switch]$RequireComplete
    )
    foreach ($fileName in $Recorded.Keys) {
        $expected = @($Recorded[$fileName])
        $actual = @(if ($Current.Contains($fileName)) { $Current[$fileName] } else { @() })
        if ($expected.Count -gt $actual.Count) {
            throw "Exact session cache covers $($expected.Count) '$fileName' entries but history now has only $($actual.Count)."
        }
        for ($i = 0; $i -lt $expected.Count; $i++) {
            if ([string]$expected[$i] -cne [string]$actual[$i]) {
                throw "Exact session cache coverage for '$fileName' is not a prefix of current history."
            }
        }
    }
    if ($RequireComplete) {
        foreach ($fileName in $Current.Keys) {
            $expected = @(if ($Recorded.Contains($fileName)) { $Recorded[$fileName] } else { @() })
            $actual = @($Current[$fileName])
            if ($expected.Count -ne $actual.Count) {
                throw "Exact session cache covers $($expected.Count) of $($actual.Count) '$fileName' entries."
            }
        }
    }
    $true
}

function ConvertFrom-ExactCacheJsonElementLocal {
    param([Parameter(Mandatory)][System.Text.Json.JsonElement]$Element)
    switch ($Element.ValueKind) {
        ([System.Text.Json.JsonValueKind]::Object) {
            $value = [ordered]@{}
            foreach ($property in $Element.EnumerateObject()) {
                $value[$property.Name] = ConvertFrom-ExactCacheJsonElementLocal -Element $property.Value
            }
            return $value
        }
        ([System.Text.Json.JsonValueKind]::Array) {
            $items = [Collections.Generic.List[object]]::new()
            foreach ($item in $Element.EnumerateArray()) {
                $items.Add((ConvertFrom-ExactCacheJsonElementLocal -Element $item))
            }
            return ,$items.ToArray()
        }
        ([System.Text.Json.JsonValueKind]::String) {
            return $Element.GetString()
        }
        ([System.Text.Json.JsonValueKind]::Number) {
            [long]$integer = 0
            if ($Element.TryGetInt64([ref]$integer)) { return $integer }
            [decimal]$decimal = 0
            if ($Element.TryGetDecimal([ref]$decimal)) { return $decimal }
            return $Element.GetDouble()
        }
        ([System.Text.Json.JsonValueKind]::True) {
            return $true
        }
        ([System.Text.Json.JsonValueKind]::False) {
            return $false
        }
        ([System.Text.Json.JsonValueKind]::Null) {
            return $null
        }
        default {
            throw "consumption-sessions.json contains unsupported JSON value kind '$($Element.ValueKind)'."
        }
    }
}

function ConvertFrom-ExactCacheJsonLocal {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $document = $null
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($Text)
        ConvertFrom-ExactCacheJsonElementLocal -Element $document.RootElement
    }
    finally {
        if ($document) { $document.Dispose() }
    }
}

function Read-ExactSessionCacheLocal {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    try { $document = ConvertFrom-ExactCacheJsonLocal -Text ([IO.File]::ReadAllText($Path)) }
    catch { throw "consumption-sessions.json is not valid JSON: $($_.Exception.Message)" }
    if ($document -isnot [Collections.IDictionary]) { throw 'consumption-sessions.json must contain one object.' }
    Assert-ExactCacheFieldsLocal -Object $document -Required @('schemaVersion', 'sessions') -Where 'consumption-sessions.json'
    if ([int]$document.schemaVersion -ne 1) { throw "consumption-sessions.json schemaVersion '$($document.schemaVersion)' is unsupported." }

    $seenSessions = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $seenRequests = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $sessions = [Collections.Generic.List[object]]::new()
    $sessionIndex = 0
    foreach ($rawSession in @($document.sessions)) {
        $sessionIndex++
        if ($rawSession -isnot [Collections.IDictionary]) { throw "consumption-sessions.json session $sessionIndex is not an object." }
        Assert-ExactCacheFieldsLocal -Object $rawSession -Required @(
            'sessionId', 'source', 'first', 'last', 'through', 'records', 'identityDigest',
            'requestDetailStatus', 'historyCoverage', 'rows', 'contentDigest'
        ) -Where "consumption-sessions.json session $sessionIndex"
        $sessionId = [string]$rawSession.sessionId
        if (-not $sessionId -or -not $seenSessions.Add($sessionId)) {
            throw "consumption-sessions.json session $sessionIndex has an empty or duplicate sessionId."
        }
        if ([string]$rawSession.source -notin @('native-log', 'legacy-ledger')) {
            throw "consumption-sessions.json session '$sessionId' has unsupported source '$($rawSession.source)'."
        }
        if ([string]$rawSession.requestDetailStatus -notin @('complete', 'unavailable')) {
            throw "consumption-sessions.json session '$sessionId' has unsupported requestDetailStatus '$($rawSession.requestDetailStatus)'."
        }
        $records = ConvertTo-NonNegativeLongLocal -Value $rawSession.records -Where "session '$sessionId' records"
        if ([string]$rawSession.identityDigest -notmatch '^[A-F0-9]{64}$') {
            throw "consumption-sessions.json session '$sessionId' has an invalid identityDigest."
        }
        if ([string]$rawSession.contentDigest -notmatch '^[A-F0-9]{64}$') {
            throw "consumption-sessions.json session '$sessionId' has an invalid contentDigest."
        }
        if ($rawSession.historyCoverage -isnot [Collections.IDictionary]) {
            throw "consumption-sessions.json session '$sessionId' historyCoverage is not an object."
        }
        $coverage = [ordered]@{}
        $digestCoverage = [ordered]@{}
        $coverageMigrationRequired = $false
        foreach ($fileName in $rawSession.historyCoverage.Keys) {
            if ([string]$fileName -notmatch '\.md$') { throw "Session '$sessionId' historyCoverage key '$fileName' is not a Markdown file." }
            $ids = @($rawSession.historyCoverage[$fileName])
            $digestCoverage[[string]$fileName] = @($ids)
            if ($ids.Count -eq 1 -and $null -eq $ids[0]) {
                $coverage[[string]$fileName] = [string[]]@()
                $coverageMigrationRequired = $true
                continue
            }
            if (@($ids | Where-Object { [string]$_ -notmatch '^[0-9a-f]{8}$' }).Count -gt 0) {
                throw "Session '$sessionId' historyCoverage for '$fileName' contains an invalid identity."
            }
            $coverage[[string]$fileName] = [string[]]@($ids | ForEach-Object { [string]$_ })
        }

        $rows = [Collections.Generic.List[object]]::new()
        $sessionRequests = 0L
        foreach ($rawRow in @($rawSession.rows)) {
            if ($rawRow -isnot [Collections.IDictionary]) { throw "Session '$sessionId' contains a non-object row." }
            Assert-ExactCacheFieldsLocal -Object $rawRow -Required @(
                'role', 'member', 'agent', 'models', 'tier', 'runs', 'requests',
                'inputTokens', 'cacheReadTokens', 'cacheWriteTokens', 'outputTokens',
                'nanoAiu', 'descendants', 'requestDetails'
            ) -Where "session '$sessionId' row"
            $requests = ConvertTo-NonNegativeLongLocal -Value $rawRow.requests -Where "session '$sessionId' row requests"
            $details = [Collections.Generic.List[object]]::new()
            foreach ($rawRequest in @($rawRow.requestDetails)) {
                if ($rawRequest -isnot [Collections.IDictionary]) { throw "Session '$sessionId' contains a non-object request detail." }
                Assert-ExactCacheFieldsLocal -Object $rawRequest -Required @(
                    'identityHash', 'timestamp', 'model', 'inputTokens', 'cacheReadTokens',
                    'cacheWriteTokens', 'outputTokens', 'nanoAiu'
                ) -Where "session '$sessionId' request detail"
                $identityHash = [string]$rawRequest.identityHash
                if ($identityHash -notmatch '^[A-F0-9]{64}$' -or -not $seenRequests.Add($identityHash)) {
                    throw "Session '$sessionId' contains an invalid or duplicate native request identity hash."
                }
                $details.Add([pscustomobject][ordered]@{
                        identityHash = $identityHash
                        timestamp = [string]$rawRequest.timestamp
                        model = [string]$rawRequest.model
                        inputTokens = ConvertTo-NonNegativeLongLocal -Value $rawRequest.inputTokens -Where "session '$sessionId' request inputTokens"
                        cacheReadTokens = ConvertTo-NonNegativeLongLocal -Value $rawRequest.cacheReadTokens -Where "session '$sessionId' request cacheReadTokens"
                        cacheWriteTokens = ConvertTo-NonNegativeLongLocal -Value $rawRequest.cacheWriteTokens -Where "session '$sessionId' request cacheWriteTokens"
                        outputTokens = ConvertTo-NonNegativeLongLocal -Value $rawRequest.outputTokens -Where "session '$sessionId' request outputTokens"
                        nanoAiu = ConvertTo-NonNegativeDecimalLocal -Value $rawRequest.nanoAiu -Where "session '$sessionId' request nanoAiu"
                    })
            }
            if ([string]$rawSession.requestDetailStatus -eq 'complete' -and $details.Count -ne $requests) {
                throw "Session '$sessionId' row '$($rawRow.agent)' has $($details.Count) request details for $requests requests."
            }
            $rowInput = ConvertTo-NonNegativeLongLocal -Value $rawRow.inputTokens -Where "session '$sessionId' row inputTokens"
            $rowCached = ConvertTo-NonNegativeLongLocal -Value $rawRow.cacheReadTokens -Where "session '$sessionId' row cacheReadTokens"
            $rowCacheWrite = ConvertTo-NonNegativeLongLocal -Value $rawRow.cacheWriteTokens -Where "session '$sessionId' row cacheWriteTokens"
            $rowOutput = ConvertTo-NonNegativeLongLocal -Value $rawRow.outputTokens -Where "session '$sessionId' row outputTokens"
            $rowNanoAiu = ConvertTo-NonNegativeDecimalLocal -Value $rawRow.nanoAiu -Where "session '$sessionId' row nanoAiu"
            if ([string]$rawSession.requestDetailStatus -eq 'complete') {
                foreach ($metric in @(
                        @{ Name = 'inputTokens'; Actual = $rowInput; Expected = [long](($details | Measure-Object inputTokens -Sum).Sum) },
                        @{ Name = 'cacheReadTokens'; Actual = $rowCached; Expected = [long](($details | Measure-Object cacheReadTokens -Sum).Sum) },
                        @{ Name = 'cacheWriteTokens'; Actual = $rowCacheWrite; Expected = [long](($details | Measure-Object cacheWriteTokens -Sum).Sum) },
                        @{ Name = 'outputTokens'; Actual = $rowOutput; Expected = [long](($details | Measure-Object outputTokens -Sum).Sum) },
                        @{ Name = 'nanoAiu'; Actual = $rowNanoAiu; Expected = [decimal](($details | Measure-Object nanoAiu -Sum).Sum) }
                    )) {
                    if ($metric.Actual -ne $metric.Expected) {
                        throw "Session '$sessionId' row '$($rawRow.agent)' $($metric.Name) does not equal its request-detail sum."
                    }
                }
            }
            $sessionRequests += $requests
            $rows.Add([pscustomobject][ordered]@{
                    Label = [string]$rawRow.role
                    Member = [string]$rawRow.member
                    Agent = [string]$rawRow.agent
                    Models = @($rawRow.models | ForEach-Object { [string]$_ })
                    Tier = [string]$rawRow.tier
                    Runs = ConvertTo-NonNegativeLongLocal -Value $rawRow.runs -Where "session '$sessionId' row runs"
                    Requests = $requests
                    Input = $rowInput
                    Cached = $rowCached
                    CacheWrite = $rowCacheWrite
                    Output = $rowOutput
                    NanoAiu = $rowNanoAiu
                    Descendants = @($rawRow.descendants | ForEach-Object { [string]$_ })
                    RequestDetails = $details.ToArray()
                })
        }
        if ($sessionRequests -ne $records) {
            throw "Session '$sessionId' rows total $sessionRequests requests, not the recorded $records."
        }
        $normalizedSession = [pscustomobject][ordered]@{
                sessionId = $sessionId
                source = [string]$rawSession.source
                first = [string]$rawSession.first
                last = [string]$rawSession.last
                through = [string]$rawSession.through
                records = $records
                identityDigest = [string]$rawSession.identityDigest
                requestDetailStatus = [string]$rawSession.requestDetailStatus
                historyCoverage = $coverage
                rows = $rows.ToArray()
                cacheMigrationRequired = $coverageMigrationRequired
            }
        $digestSession = [pscustomobject][ordered]@{
                sessionId = $normalizedSession.sessionId
                source = $normalizedSession.source
                first = $normalizedSession.first
                last = $normalizedSession.last
                through = $normalizedSession.through
                records = $normalizedSession.records
                identityDigest = $normalizedSession.identityDigest
                requestDetailStatus = $normalizedSession.requestDetailStatus
                historyCoverage = $digestCoverage
                rows = $normalizedSession.rows
            }
        $normalizedRecord = ConvertTo-ExactCacheSessionRecordLocal -Session $digestSession -IncludeContentDigest
        if ([string]$normalizedRecord.contentDigest -cne [string]$rawSession.contentDigest) {
            throw "consumption-sessions.json session '$sessionId' contentDigest does not match its persisted fields."
        }
        $sessions.Add($normalizedSession)
    }
    $sessions.ToArray()
}

function ConvertTo-ExactCacheSessionRecordLocal {
    param(
        [Parameter(Mandatory)]$Session,
        [switch]$IncludeContentDigest
    )
    $coverage = [ordered]@{}
    foreach ($fileName in @($Session.historyCoverage.Keys | Sort-Object)) {
        $coverage[$fileName] = @($Session.historyCoverage[$fileName])
    }
    $record = [ordered]@{
        sessionId = [string]$Session.sessionId
        source = [string]$Session.source
        first = [string]$Session.first
        last = [string]$Session.last
        through = [string]$Session.through
        records = [long]$Session.records
        identityDigest = [string]$Session.identityDigest
        requestDetailStatus = [string]$Session.requestDetailStatus
        historyCoverage = $coverage
        rows = @(
            foreach ($row in @($Session.rows)) {
                [ordered]@{
                    role = [string]$row.Label
                    member = [string]$row.Member
                    agent = [string]$row.Agent
                    models = @($row.Models)
                    tier = [string]$row.Tier
                    runs = [long]$row.Runs
                    requests = [long]$row.Requests
                    inputTokens = [long]$row.Input
                    cacheReadTokens = [long]$row.Cached
                    cacheWriteTokens = [long]$row.CacheWrite
                    outputTokens = [long]$row.Output
                    nanoAiu = [decimal]$row.NanoAiu
                    descendants = @($row.Descendants)
                    requestDetails = @(
                        foreach ($request in @($row.RequestDetails)) {
                            [ordered]@{
                                identityHash = [string]$request.identityHash
                                timestamp = [string]$request.timestamp
                                model = [string]$request.model
                                inputTokens = [long]$request.inputTokens
                                cacheReadTokens = [long]$request.cacheReadTokens
                                cacheWriteTokens = [long]$request.cacheWriteTokens
                                outputTokens = [long]$request.outputTokens
                                nanoAiu = [decimal]$request.nanoAiu
                            }
                        }
                    )
                }
            }
        )
    }
    if ($IncludeContentDigest) {
        $material = $record | ConvertTo-Json -Compress -Depth 20
        $record['contentDigest'] = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($material)))
    }
    $record
}

function ConvertTo-ExactSessionCacheDocumentLocal {
    param([AllowEmptyCollection()][object[]]$Sessions = @())
    $document = [ordered]@{
        schemaVersion = 1
        sessions = @($Sessions | ForEach-Object { ConvertTo-ExactCacheSessionRecordLocal -Session $_ -IncludeContentDigest })
    }
    ($document | ConvertTo-Json -Depth 20) + "`n"
}

function ConvertTo-CacheRequestLocal {
    param([Parameter(Mandatory)]$Request)
    $identityHash = if ($Request.PSObject.Properties['identityHash'] -and $Request.identityHash) {
        [string]$Request.identityHash
    }
    elseif ($Request.PSObject.Properties['identity'] -and $Request.identity) {
        Get-NativeIdentityHashLocal -Identity ([string]$Request.identity)
    }
    else {
        throw 'Exact native request has no accounting identity.'
    }
    [pscustomobject][ordered]@{
        identityHash = $identityHash
        timestamp = [string]$Request.timestamp
        model = [string]$Request.model
        inputTokens = [long]$Request.inputTokens
        cacheReadTokens = [long]$Request.cacheReadTokens
        cacheWriteTokens = [long]$Request.cacheWriteTokens
        outputTokens = [long]$Request.outputTokens
        nanoAiu = [decimal]$Request.nanoAiu
    }
}

function ConvertTo-CacheSessionLocal {
    param(
        [Parameter(Mandatory)]$Exact,
        [Parameter(Mandatory)][Collections.IDictionary]$HistoryCoverage
    )
    [pscustomobject][ordered]@{
        sessionId = [string]$Exact.Session.SessionId
        source = 'native-log'
        first = [string]$Exact.Session.First
        last = [string]$Exact.Session.Last
        through = [string]$Exact.SnapshotTimestamp
        records = [long]$Exact.SnapshotRecords
        identityDigest = [string]$Exact.SnapshotDigest
        requestDetailStatus = 'complete'
        historyCoverage = $HistoryCoverage
        rows = @(
            foreach ($row in @($Exact.Rows)) {
                [pscustomobject][ordered]@{
                    Label = [string]$row.Label
                    Member = [string]$row.Member
                    Agent = [string]$row.Agent
                    Models = @($row.Models)
                    Tier = [string]$row.Tier
                    Runs = [long]$row.Runs
                    Requests = [long]$row.Requests
                    Input = [long]$row.Input
                    Cached = [long]$row.Cached
                    CacheWrite = [long]$row.CacheWrite
                    Output = [long]$row.Output
                    NanoAiu = [decimal]$row.NanoAiu
                    Descendants = @($row.Descendants)
                    RequestDetails = @($row.RequestDetails | ForEach-Object { ConvertTo-CacheRequestLocal -Request $_ })
                }
            }
        )
    }
}

function Assert-ExactSessionRefreshLocal {
    param(
        [Parameter(Mandatory)]$Existing,
        [Parameter(Mandatory)]$Next
    )
    if ([string]$Existing.source -ne 'native-log') { return }
    if ([long]$Next.records -lt [long]$Existing.records) {
        throw "Native session '$($Next.sessionId)' regressed from $($Existing.records) to $($Next.records) complete records."
    }
    if ([long]$Next.records -eq [long]$Existing.records -and [string]$Next.identityDigest -cne [string]$Existing.identityDigest) {
        throw "Native session '$($Next.sessionId)' changed its identity digest without adding a complete record."
    }
    if ([string]$Existing.requestDetailStatus -eq 'complete') {
        $nextIdentities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($row in @($Next.rows)) {
            foreach ($request in @($row.RequestDetails)) { $null = $nextIdentities.Add([string]$request.identityHash) }
        }
        foreach ($row in @($Existing.rows)) {
            foreach ($request in @($row.RequestDetails)) {
                if (-not $nextIdentities.Contains([string]$request.identityHash)) {
                    throw "Native session '$($Next.sessionId)' lost a previously accepted accounting identity."
                }
            }
        }
    }
}

function Convert-ExistingExactLedgerToCacheSessionLocal {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$ConsumptionContent,
        [Parameter(Mandatory)][Collections.IDictionary]$CurrentHistoryCoverage
    )
    if ($ConsumptionContent -notmatch '(?m)^\| Role \| Requests \| In Tokens \| Cached \| Cache Wr \| Out Tokens \| Exact Cost \(USD\) \| Exact Credits \| Basis \|') {
        return $null
    }
    $single = [regex]::Match($ConsumptionContent, '(?m)^Native usage snapshot — session: (?<session>[^;]+); records: (?<records>\d+); through: (?<through>[^;]+); digest: (?<digest>[A-F0-9]{64})\s*$')
    if (-not $single.Success) { return $null }
    $snapshot = $single
    $coverage = Get-RecordedHistoryCoverageLocal -ConsumptionContent $ConsumptionContent
    if ($coverage.Count -eq 0) { return $null }
    $null = Test-HistoryCoveragePrefixLocal -Recorded $coverage -Current $CurrentHistoryCoverage

    $tables = @(Get-MarkdownTableLocal -Content $ConsumptionContent)
    $attribution = @($tables | Where-Object { 'Agent' -in $_.Header -and 'Model Source' -in $_.Header -and 'Priced As' -in $_.Header } | Select-Object -First 1)
    $usage = @($tables | Where-Object { 'Requests' -in $_.Header -and 'Exact Cost (USD)' -in $_.Header } | Select-Object -First 1)
    if ($attribution.Count -ne 1 -or $usage.Count -ne 1) { return $null }
    $attributionRows = @($attribution[0].Rows)
    $usageRows = @($usage[0].Rows | Where-Object { ([string]$_[$usage[0].Header[0]]) -notmatch 'Total' })
    if ($attributionRows.Count -ne $usageRows.Count -or $usageRows.Count -eq 0) { return $null }

    $nanoLines = @([regex]::Matches($ConsumptionContent, '(?m)^(?<role>.+?)\s+requests\s+(?<requests>\d+)\s+input\s+(?<input>\d+)\s+cached\s+(?<cached>\d+)\s+cache-write\s+(?<cacheWrite>\d+)\s+output\s+(?<output>\d+)\s+nano-AIU\s+(?<nano>\d+(?:\.\d+)?)\s+='))
    if ($nanoLines.Count -ne $usageRows.Count) { return $null }
    $rows = [Collections.Generic.List[object]]::new()
    $recordTotal = 0L
    $nanoTotal = [decimal]0
    for ($i = 0; $i -lt $usageRows.Count; $i++) {
        $a = $attributionRows[$i]
        $u = $usageRows[$i]
        $n = $nanoLines[$i]
        $role = ([string]$u['Role']).Trim('*', ' ')
        if ($role -cne ([string]$a['Role']).Trim('*', ' ') -or $role -cne $n.Groups['role'].Value.Trim()) { return $null }
        $requests = [long](ConvertTo-LedgerNumberLocal $u['Requests'])
        $nanoAiu = [decimal]::Parse($n.Groups['nano'].Value, [Globalization.CultureInfo]::InvariantCulture)
        $recordTotal += $requests
        $nanoTotal += $nanoAiu
        $rows.Add([pscustomobject][ordered]@{
                Label = $role
                Member = ([string]$a['Member']).Trim()
                Agent = ([string]$a['Agent']).Trim()
                Models = @(([string]$a['Model'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }))
                Tier = ([string]$a['Tier']).Trim()
                Runs = 0L
                Requests = $requests
                Input = [long](ConvertTo-LedgerNumberLocal $u['In Tokens'])
                Cached = [long](ConvertTo-LedgerNumberLocal $u['Cached'])
                CacheWrite = [long](ConvertTo-LedgerNumberLocal $u['Cache Wr'])
                Output = [long](ConvertTo-LedgerNumberLocal $u['Out Tokens'])
                NanoAiu = $nanoAiu
                Descendants = @()
                RequestDetails = @()
            })
    }
    if ($recordTotal -ne [long]$snapshot.Groups['records'].Value) { return $null }
    $totalLine = [regex]::Match($ConsumptionContent, '(?m)^total nano-AIU (?<nano>\d+(?:\.\d+)?)\s+=')
    if (-not $totalLine.Success -or [decimal]::Parse($totalLine.Groups['nano'].Value, [Globalization.CultureInfo]::InvariantCulture) -ne $nanoTotal) { return $null }
    $digest = [string]$snapshot.Groups['digest'].Value
    $sessionId = [string]$single.Groups['session'].Value
    [pscustomobject][ordered]@{
        sessionId = $sessionId
        source = 'legacy-ledger'
        first = ''
        last = [string]$snapshot.Groups['through'].Value
        through = [string]$snapshot.Groups['through'].Value
        records = $recordTotal
        identityDigest = $digest
        requestDetailStatus = 'unavailable'
        historyCoverage = $coverage
        rows = $rows.ToArray()
    }
}

function Get-ExactCoveragePlanLocal {
    param(
        [AllowEmptyCollection()][object[]]$Sessions = @(),
        [Parameter(Mandatory)][AllowEmptyString()][string]$CurrentSessionId,
        [Parameter(Mandatory)][Collections.IDictionary]$CurrentHistoryCoverage
    )
    $currentIndex = -1
    for ($i = 0; $i -lt $Sessions.Count; $i++) {
        if ([string]$Sessions[$i].sessionId -ceq $CurrentSessionId) { $currentIndex = $i; break }
    }
    if ($currentIndex -ge 0 -and $currentIndex -ne $Sessions.Count - 1) {
        throw "Native session '$CurrentSessionId' is not the latest cached session; exact accumulation cannot rewrite an older session after later sessions were recorded."
    }
    $priorSessions = if ($currentIndex -eq 0) { @() }
    elseif ($currentIndex -gt 0) { @($Sessions[0..($currentIndex - 1)]) }
    else { @($Sessions) }
    $priorCoverage = Get-CumulativeHistoryCoverageLocal -Sessions $priorSessions
    $null = Test-HistoryCoveragePrefixLocal -Recorded $priorCoverage -Current $CurrentHistoryCoverage

    $currentCoverage = [ordered]@{}
    foreach ($fileName in @($CurrentHistoryCoverage.Keys | Sort-Object)) {
        $all = @($CurrentHistoryCoverage[$fileName])
        $offset = @(if ($priorCoverage.Contains($fileName)) { $priorCoverage[$fileName] } else { @() }).Count
        $currentCoverage[$fileName] = [string[]]@()
        if ($offset -lt $all.Count) {
            $currentCoverage[$fileName] = [string[]]@($all[$offset..($all.Count - 1)] | ForEach-Object { [string]$_ })
        }
    }
    $existing = if ($currentIndex -ge 0) { $Sessions[$currentIndex] } else { $null }
    $existingCoverage = if ($existing) { $existing.historyCoverage } else { [ordered]@{} }
    $null = Test-HistoryCoveragePrefixLocal -Recorded $existingCoverage -Current $currentCoverage
    $newHistoryCount = 0
    foreach ($fileName in $currentCoverage.Keys) {
        $oldCount = @(if ($existingCoverage.Contains($fileName)) { $existingCoverage[$fileName] } else { @() }).Count
        $newHistoryCount += @($currentCoverage[$fileName]).Count - $oldCount
    }
    $allCoverage = Get-CumulativeHistoryCoverageLocal -Sessions $Sessions
    $cacheCoversAll = $false
    try {
        $null = Test-HistoryCoveragePrefixLocal -Recorded $allCoverage -Current $CurrentHistoryCoverage -RequireComplete
        $cacheCoversAll = $true
    }
    catch {
        $cacheCoversAll = $false
    }
    [pscustomobject][ordered]@{
        ExistingIndex = $currentIndex
        ExistingSession = $existing
        CurrentCoverage = $currentCoverage
        NewHistoryCount = $newHistoryCount
        CacheCoversAll = $cacheCoversAll
    }
}

function Get-ExpectedNativeCoverageLocal {
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$HistoryCoverage,
        [Parameter(Mandatory)][Collections.IDictionary]$MeteredHistoryCoverage,
        [AllowEmptyCollection()][string[]]$MeteredAgents = @(),
        [AllowEmptyCollection()][object[]]$HistoryEntries = @()
    )
    $meteredAgentsSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($agent in $MeteredAgents) { if ($agent) { $null = $meteredAgentsSet.Add([string]$agent) } }
    $agents = [Collections.Generic.List[string]]::new()
    $entries = [Collections.Generic.List[object]]::new()
    $requireOrchestration = $false
    $meteredEntryCount = 0
    foreach ($fileName in $HistoryCoverage.Keys) {
        $covered = @($HistoryCoverage[$fileName])
        $meteredIdentitySet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        if ($MeteredHistoryCoverage.Contains($fileName)) {
            foreach ($identity in @($MeteredHistoryCoverage[$fileName])) { $null = $meteredIdentitySet.Add([string]$identity) }
        }
        $coveredMetered = @($covered | Where-Object { $meteredIdentitySet.Contains([string]$_) })
        $count = $coveredMetered.Count
        if ($count -eq 0) { continue }
        $meteredEntryCount += $count
        $agent = [IO.Path]::GetFileNameWithoutExtension([string]$fileName)
        $coveredSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($identity in $coveredMetered) { $null = $coveredSet.Add([string]$identity) }
        $candidates = @($HistoryEntries | Where-Object { $_.Agent -CEQ $agent -and $coveredSet.Contains([string]$_.Identity) })
        if ($count -ne $candidates.Count) {
            throw "Current native session coverage names $count metered '$agent' history entries but $($candidates.Count) parsed entries match."
        }
        foreach ($entry in $candidates) { $entries.Add($entry) }
        if ($agent -ceq 'Squad Scribe') {
            $requireOrchestration = $true
            continue
        }
        if (-not $meteredAgentsSet.Contains($agent)) { continue }
        $agents.Add($agent)
    }
    [pscustomobject][ordered]@{
        Agents = @($agents | Select-Object -Unique)
        HistoryEntries = $entries.ToArray()
        RequireOrchestration = $requireOrchestration
        MeteredEntryCount = $meteredEntryCount
    }
}

function Get-ExactRequestCounterfactualCostLocal {
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)]$Rates
    )

    $key = ConvertTo-RateKeyLocal $Model
    if (-not $key -or -not $Rates.ByNormalized.ContainsKey($key)) { return $null }
    $rate = $Rates.ByNormalized[$key]
    $effective = $rate
    if ($rate.ContainsKey('long_context_threshold') -and
        ([double]$Request.inputTokens + [double]$Request.cacheReadTokens) -gt [double]$rate.long_context_threshold) {
        $effective = @{} + $rate
        $effective.input = $rate.lc_input
        $effective.cached = $rate.lc_cached
        $effective.cache_write = $rate.lc_cache_write
        $effective.output = $rate.lc_output
    }
    (
        [double]$Request.inputTokens * [double]$effective.input +
        [double]$Request.cacheReadTokens * [double]$effective.cached +
        [double]$Request.cacheWriteTokens * [double]$effective.cache_write +
        [double]$Request.outputTokens * [double]$effective.output
    ) / 1000000.0
}

function Get-NativeAgentIdentityVariantsLocal {
    param([AllowEmptyString()][string]$Identity)

    $variants = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    function Add-VariantLocal {
        param([AllowEmptyString()][string]$Value)
        $candidate = ([string]$Value).Trim()
        if ($candidate -and $seen.Add($candidate)) { $variants.Add($candidate) }
    }

    $value = ([string]$Identity).Trim()
    if (-not $value) { return @() }
    Add-VariantLocal -Value $value

    $namespaceSuffix = @($value -split ':')[-1]
    Add-VariantLocal -Value $namespaceSuffix

    $pathSuffix = @($namespaceSuffix -split '[\\/]')[-1]
    Add-VariantLocal -Value $pathSuffix

    foreach ($candidate in @($variants.ToArray())) {
        Add-VariantLocal -Value ([regex]::Replace($candidate, '(?i)\.agent(?:\.md)?$', ''))
    }
    $variants.ToArray()
}

function ConvertTo-NativeAgentIdentityKeyLocal {
    param([AllowEmptyString()][string]$Identity)
    (([string]$Identity).Trim().ToLowerInvariant() -replace '[^a-z0-9]', '')
}

function Find-NativeAgentIdentityMatchLocal {
    param(
        [AllowEmptyCollection()][string[]]$Candidates = @(),
        [AllowEmptyCollection()][string[]]$KnownNames = @()
    )

    $known = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $KnownNames) {
        $trimmed = ([string]$name).Trim()
        if ($trimmed -and -not $known.ContainsKey($trimmed)) { $known.Add($trimmed, $trimmed) }
    }
    if ($known.Count -eq 0) {
        return [pscustomobject]@{ Status = 'unmapped'; Name = ''; Matches = @() }
    }

    $candidateVariants = [Collections.Generic.List[string]]::new()
    $candidateSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in $Candidates) {
        foreach ($variant in @(Get-NativeAgentIdentityVariantsLocal -Identity $candidate)) {
            if ($candidateSeen.Add($variant)) { $candidateVariants.Add($variant) }
        }
    }

    $exactMatches = [Collections.Generic.List[string]]::new()
    foreach ($name in $known.Values) {
        foreach ($candidate in $candidateVariants) {
            if ([string]::Equals($candidate, $name, [StringComparison]::OrdinalIgnoreCase)) {
                $exactMatches.Add($name)
                break
            }
        }
    }
    if ($exactMatches.Count -eq 1) {
        return [pscustomobject]@{ Status = 'ok'; Name = $exactMatches[0]; Matches = $exactMatches.ToArray() }
    }
    if ($exactMatches.Count -gt 1) {
        return [pscustomobject]@{ Status = 'ambiguous'; Name = ''; Matches = @($exactMatches | Sort-Object) }
    }

    $candidateKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($candidate in $candidateVariants) {
        $key = ConvertTo-NativeAgentIdentityKeyLocal -Identity $candidate
        if ($key) { $null = $candidateKeys.Add($key) }
    }
    $normalizedMatches = [Collections.Generic.List[string]]::new()
    foreach ($name in $known.Values) {
        $key = ConvertTo-NativeAgentIdentityKeyLocal -Identity $name
        if ($key -and $candidateKeys.Contains($key)) { $normalizedMatches.Add($name) }
    }
    if ($normalizedMatches.Count -eq 1) {
        return [pscustomobject]@{ Status = 'ok'; Name = $normalizedMatches[0]; Matches = $normalizedMatches.ToArray() }
    }
    if ($normalizedMatches.Count -gt 1) {
        return [pscustomobject]@{ Status = 'ambiguous'; Name = ''; Matches = @($normalizedMatches | Sort-Object) }
    }
    [pscustomobject]@{ Status = 'unmapped'; Name = ''; Matches = @() }
}

function Resolve-NativeAgentIdentityLocal {
    param(
        [Parameter(Mandatory)]$Run,
        [AllowEmptyCollection()][string[]]$ExpectedAgentNames = @()
    )

    $rawName = ([string]$Run.agentName).Trim()
    $displayName = ([string]$Run.displayName).Trim()
    $candidates = @($rawName, $displayName | Where-Object { $_ })
    $knownNames = @('coordinator', 'Squad Scribe') + @($ExpectedAgentNames | Where-Object { $_ })
    $match = Find-NativeAgentIdentityMatchLocal -Candidates $candidates -KnownNames $knownNames
    if ($match.Status -eq 'ok') {
        return [pscustomobject]@{
            Status = 'ok'
            Name = [string]$match.Name
            RawName = $rawName
            DisplayName = $displayName
            Matches = @($match.Matches)
        }
    }
    if ($match.Status -eq 'ambiguous') {
        return [pscustomobject]@{
            Status = 'ambiguous'
            Name = ''
            RawName = $rawName
            DisplayName = $displayName
            Matches = @($match.Matches)
        }
    }
    [pscustomobject]@{
        Status = 'unmapped'
        Name = if ($rawName) { $rawName } else { $displayName }
        RawName = $rawName
        DisplayName = $displayName
        Matches = @()
    }
}

function Test-NativeSessionHasScribeUsageLocal {
    param(
        [Parameter(Mandatory)]$Session
    )

    foreach ($run in @($Session.UsageSnapshot.agentRuns)) {
        if ([int]$run.records -le 0) { continue }
        $identity = Resolve-NativeAgentIdentityLocal -Run $run
        if ($identity.Status -eq 'ok' -and [string]$identity.Name -ceq 'Squad Scribe') {
            return $true
        }
    }
    return $false
}

function Get-ExactLedgerUsageLocal {
    <#
    .SYNOPSIS
        Converts a complete native usage snapshot into exact role rows.
    .DESCRIPTION
        Each usage event carries the active agentId. SquadUsage.psm1 resolves that
        id through subagent.started parentAgentId links, so nested workers roll into
        the top-level roster role that owned them. APM human names and plugin-qualified
        identities resolve through one unique history-backed canonical agent name.
        Coordinator and Squad Scribe usage share the orchestration row. The exact row
        sum must reconcile to the session nano-AIU total or the caller falls back to
        estimates.
    #>
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Rates,
        [Parameter(Mandatory)]$Roster,
        [AllowEmptyCollection()][object[]]$OrderedAggregates = @(),
        $OrchestrationAggregate,
        [AllowEmptyCollection()][object[]]$HistoryEntries = @(),
        [AllowEmptyCollection()][string[]]$ExpectedAgentNames = @(),
        [switch]$RequireOrchestration,
        [switch]$EnforceExpectedSet,
        [switch]$RequireSessionBoundary,
        [AllowEmptyString()][string]$BaselineModel,
        [System.Collections.Generic.List[string]]$Warnings
    )

    $snapshot = $Session.UsageSnapshot
    if ($snapshot.status -ne 'complete') {
        $Warnings.Add("WARN: exact native usage is incomplete: $(@($snapshot.problems) -join ' ')")
        return $null
    }
    if ($snapshot.attributionStatus -ne 'complete') {
        $Warnings.Add("WARN: exact per-role attribution is incomplete: $(@($snapshot.attributionProblems) -join ' ')")
        return $null
    }
    if ([int]$snapshot.records -eq 0) {
        $Warnings.Add('WARN: the session log has no complete native usage records; estimates remain the fallback.')
        return $null
    }
    $memberScopeExclusive = $Session.PSObject.Properties['MemberScopeExclusive'] -and [bool]$Session.MemberScopeExclusive
    if ($Session.MemberName -and -not $memberScopeExclusive) {
        $Warnings.Add("WARN: exact per-role ledger replacement for member '$($Session.MemberName)' requires every model dispatch in the native session to name that member root and no federation-root lifecycle write; estimates remain the fallback.")
        return $null
    }
    if ($RequireSessionBoundary -and $Session.First) {
        try {
            $sessionStart = [DateTimeOffset]::Parse([string]$Session.First, [Globalization.CultureInfo]::InvariantCulture)
            $olderEntries = @(
                $HistoryEntries | Where-Object {
                    $_.Timestamp -and
                    [DateTimeOffset]::Parse([string]$_.Timestamp, [Globalization.CultureInfo]::InvariantCulture) -lt $sessionStart
                }
            )
            if ($olderEntries.Count -gt 0) {
                $Warnings.Add('WARN: squad history predates the selected host session; one session log cannot exactly cover a multi-session run, so estimates remain the fallback.')
                return $null
            }
        }
        catch {
            $Warnings.Add("WARN: exact session/history boundary could not be parsed; estimates remain the fallback: $($_.Exception.Message)")
            return $null
        }
    }

    $expectedAgents = if ($ExpectedAgentNames.Count -gt 0) {
        @($ExpectedAgentNames | Where-Object { $_ } | Select-Object -Unique)
    }
    else {
        @($OrderedAggregates | ForEach-Object AgentName | Where-Object { $_ } | Select-Object -Unique)
    }

    $rowsByKey = @{}
    foreach ($run in @($snapshot.agentRuns)) {
        if ([int]$run.records -le 0) { continue }
        $nativeIdentity = Resolve-NativeAgentIdentityLocal -Run $run -ExpectedAgentNames $expectedAgents
        if ($nativeIdentity.Status -eq 'ambiguous') {
            $reported = @($nativeIdentity.RawName, $nativeIdentity.DisplayName | Where-Object { $_ }) -join ' / '
            $Warnings.Add("WARN: exact native agent identity '$reported' matches multiple history-backed identities ($(@($nativeIdentity.Matches) -join ', ')); estimates remain the fallback.")
            return $null
        }
        $canonicalAgentName = [string]$nativeIdentity.Name
        $isOrchestration = $canonicalAgentName -in @('coordinator', 'Squad Scribe')
        if ($isOrchestration) {
            $resolved = [pscustomobject]@{
                Index = [int]::MaxValue
                Role = 'orchestration'
                MemberName = ''
                Tier = 'mixed'
                AggregateKey = 'orchestration'
                Status = 'ok'
            }
            $agentName = 'Coordinator+Scribe'
        }
        else {
            $resolved = Resolve-RoleForAgentLocal -AgentName $canonicalAgentName -Roster $Roster
            if ($resolved.Status -notin @('ok', 'unmapped')) {
                $Warnings.Add("WARN: exact usage for '$canonicalAgentName' cannot be mapped to one roster row (status: $($resolved.Status)); estimates remain the fallback.")
                return $null
            }
            $agentName = $canonicalAgentName
        }

        $key = if ($isOrchestration) { 'orchestration' } else { "$($resolved.AggregateKey)`n$agentName" }
        if (-not $rowsByKey.ContainsKey($key)) {
            $rowsByKey[$key] = @{
                Index = $resolved.Index
                Role = [string]$resolved.Role
                Member = [string]$resolved.MemberName
                Agent = $agentName
                Tier = [string]$resolved.Tier
                Models = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                Descendants = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                Runs = 0
                Requests = 0
                Input = 0L
                Cached = 0L
                CacheWrite = 0L
                Output = 0L
                NanoAiu = [decimal]0
                RequestDetails = [Collections.Generic.List[object]]::new()
            }
        }
        $row = $rowsByKey[$key]
        $row.Runs++
        $row.Requests += [int]$run.records
        $row.Input += [long]$run.inputTokens
        $row.Cached += [long]$run.cacheReadTokens
        $row.CacheWrite += [long]$run.cacheWriteTokens
        $row.Output += [long]$run.outputTokens
        $row.NanoAiu += [decimal]$run.totalNanoAiu
        foreach ($model in @($run.models)) { if ($model) { $null = $row.Models.Add([string]$model) } }
        foreach ($name in @($run.descendantAgents)) { if ($name) { $null = $row.Descendants.Add([string]$name) } }
        foreach ($request in @($run.requests)) { $row.RequestDetails.Add($request) }
    }

    $rows = @(
        foreach ($row in @($rowsByKey.Values | Sort-Object Index, Role, Agent)) {
            [pscustomobject][ordered]@{
                Index = $row.Index
                Label = $row.Role
                Member = $row.Member
                Agent = $row.Agent
                Models = @($row.Models | Sort-Object)
                ModelSources = @('host-reported')
                PricedAsUsed = @('native credits')
                Tier = $row.Tier
                Runs = $row.Runs
                Requests = $row.Requests
                Input = $row.Input
                Cached = $row.Cached
                CacheWrite = $row.CacheWrite
                Output = $row.Output
                NanoAiu = $row.NanoAiu
                Cost = [double]($row.NanoAiu / [decimal]1e11)
                Credits = [double]($row.NanoAiu / [decimal]1e9)
                Basis = 'exact-native'
                Descendants = @($row.Descendants | Sort-Object)
                RequestDetails = $row.RequestDetails.ToArray()
            }
        }
    )
    $modelLessRows = @($rows | Where-Object { @($_.Models).Count -eq 0 })
    if ($modelLessRows.Count -gt 0) {
        $Warnings.Add("WARN: exact native usage has no model identity for: $($modelLessRows.Agent -join ', '); estimates remain the fallback.")
        return $null
    }
    $exactAgents = @($rows | Where-Object Label -ne 'orchestration' | ForEach-Object Agent | Select-Object -Unique)
    $missingAgents = @($expectedAgents | Where-Object { $_ -notin $exactAgents })
    if ($missingAgents.Count -gt 0) {
        $Warnings.Add("WARN: exact native usage has no attributed records for history-backed agent(s): $($missingAgents -join ', '); estimates remain the fallback.")
        return $null
    }
    if ($EnforceExpectedSet) {
        $extraAgents = @($exactAgents | Where-Object { $_ -notin $expectedAgents })
        if ($extraAgents.Count -gt 0) {
            $Warnings.Add("WARN: exact native usage contains agent(s) without history coverage in this session: $($extraAgents -join ', '); estimates remain the fallback.")
            return $null
        }
    }
    $needsOrchestration = $RequireOrchestration -or $null -ne $OrchestrationAggregate
    $hasOrchestration = @($rows | Where-Object Label -eq 'orchestration').Count -gt 0
    if ($needsOrchestration -and -not $hasOrchestration) {
        $Warnings.Add('WARN: exact native usage has no coordinator or Scribe records for the history-backed orchestration row; estimates remain the fallback.')
        return $null
    }
    if ($EnforceExpectedSet -and -not $needsOrchestration -and $hasOrchestration) {
        $Warnings.Add('WARN: exact native usage contains coordinator or Scribe records without matching orchestration history coverage in this session; estimates remain the fallback.')
        return $null
    }
    $totalNanoAiu = [decimal](($rows | Measure-Object NanoAiu -Sum).Sum)
    if ($totalNanoAiu -ne [decimal]$snapshot.totalNanoAiu) {
        $Warnings.Add("WARN: exact role rows total $totalNanoAiu nano-AIU but the session snapshot totals $($snapshot.totalNanoAiu); estimates remain the fallback.")
        return $null
    }

    $roleRows = @($rows | Where-Object Label -ne 'orchestration')
    $baseline = $BaselineModel
    if (-not $baseline) {
        $candidateModels = @($roleRows | ForEach-Object Models | Where-Object { (ConvertTo-RateKeyLocal $_) -ne 'hydrafusion-max' } | Select-Object -Unique)
        if ($candidateModels.Count -eq 0 -and $Rates.ByNormalized.ContainsKey('claude-sonnet-4.6')) {
            $candidateModels = @('claude-sonnet-4.6')
        }
        $baseline = @(
            $candidateModels |
                Sort-Object {
                    $rate = Get-BlendedRateLocal -Model $_ -Rates $Rates
                    if ($null -eq $rate) { -1 } else { $rate }
                } -Descending |
                Select-Object -First 1
        ) | Select-Object -First 1
    }

    $baselineCost = [double]0
    $baselineComplete = [bool]$baseline
    if ($baselineComplete) {
        foreach ($row in $roleRows) {
            foreach ($request in @($row.RequestDetails)) {
                $cost = Get-ExactRequestCounterfactualCostLocal -Request $request -Model $baseline -Rates $Rates
                if ($null -eq $cost) {
                    $baselineComplete = $false
                    break
                }
                $baselineCost += [double]$cost
            }
            if (-not $baselineComplete) { break }
        }
    }
    if ($baseline -and -not $baselineComplete) {
        $Warnings.Add("WARN: baseline model '$baseline' has no complete rate row; the exact-traffic counterfactual is unavailable.")
    }

    $totalCost = [double]($totalNanoAiu / [decimal]1e11)
    $totalCredits = [double]($totalNanoAiu / [decimal]1e9)
    $orchestration = @($rows | Where-Object Label -eq 'orchestration' | Select-Object -First 1)
    [pscustomobject][ordered]@{
        Session = $Session
        Rows = $rows
        TotalRequests = [int](($rows | Measure-Object Requests -Sum).Sum)
        TotalInput = [long](($rows | Measure-Object Input -Sum).Sum)
        TotalCached = [long](($rows | Measure-Object Cached -Sum).Sum)
        TotalCacheWrite = [long](($rows | Measure-Object CacheWrite -Sum).Sum)
        TotalOutput = [long](($rows | Measure-Object Output -Sum).Sum)
        TotalNanoAiu = $totalNanoAiu
        TotalCostUsd = $totalCost
        TotalCredits = $totalCredits
        OrchestrationCredits = if ($orchestration.Count) { [double]$orchestration[0].Credits } else { 0.0 }
        BaselineModel = $baseline
        BaselineCostUsd = if ($baselineComplete) { $baselineCost } else { $null }
        BaselineCredits = if ($baselineComplete) { $baselineCost / 0.01 } else { $null }
        SavingsUsd = if ($baselineComplete) { $baselineCost - $totalCost } else { $null }
        SavingsPct = if ($baselineComplete -and $baselineCost -gt 0) { 100.0 * ($baselineCost - $totalCost) / $baselineCost } else { $null }
        AgentCount = $roleRows.Count
        SnapshotRecords = [int]$snapshot.records
        SnapshotDigest = [string]$snapshot.identityDigest
        SnapshotTimestamp = [string]$snapshot.lastUsageTimestamp
    }
}

function Merge-ExactSessionUsageLocal {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Sessions,
        [Parameter(Mandatory)]$Rates,
        [Parameter(Mandatory)]$Roster,
        [AllowEmptyString()][string]$BaselineModel,
        $ActiveSession,
        [System.Collections.Generic.List[string]]$Warnings
    )
    if ($Sessions.Count -eq 0) { return $null }
    $rowsByKey = @{}
    $seenRequestIdentities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $requestDetailsComplete = $true
    foreach ($session in $Sessions) {
        if ([string]$session.requestDetailStatus -ne 'complete') { $requestDetailsComplete = $false }
        foreach ($storedRow in @($session.rows)) {
            $isOrchestration = [string]$storedRow.Label -eq 'orchestration' -or [string]$storedRow.Agent -eq 'Coordinator+Scribe'
            if ($isOrchestration) {
                $index = [int]::MaxValue
                $label = 'orchestration'
                $member = ''
                $tier = 'mixed'
                $agent = 'Coordinator+Scribe'
            }
            else {
                $resolved = Resolve-RoleForAgentLocal -AgentName ([string]$storedRow.Agent) -MemberName ([string]$storedRow.Member) -Roster $Roster
                if ($resolved.Status -eq 'member-not-found') {
                    $resolved = Resolve-RoleForAgentLocal -AgentName ([string]$storedRow.Agent) -Roster $Roster
                }
                if ($resolved.Status -notin @('ok', 'unmapped')) {
                    throw "Cached exact usage for '$($storedRow.Agent)' cannot be mapped to one current roster row (status: $($resolved.Status))."
                }
                $index = if ($null -ne $resolved.Index) { [int]$resolved.Index } else { [int]::MaxValue }
                $label = [string]$resolved.Role
                $member = [string]$resolved.MemberName
                $tier = [string]$resolved.Tier
                $agent = [string]$storedRow.Agent
            }
            $key = "$label`n$member`n$agent"
            if (-not $rowsByKey.ContainsKey($key)) {
                $rowsByKey[$key] = @{
                    Index = $index
                    Label = $label
                    Member = $member
                    Agent = $agent
                    Tier = $tier
                    Models = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                    Descendants = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                    Runs = 0L
                    Requests = 0L
                    Input = 0L
                    Cached = 0L
                    CacheWrite = 0L
                    Output = 0L
                    NanoAiu = [decimal]0
                    RequestDetails = [Collections.Generic.List[object]]::new()
                }
            }
            $row = $rowsByKey[$key]
            $row.Index = [math]::Min([int]$row.Index, $index)
            if ($row.Tier -and $tier -and $row.Tier -cne $tier) { $row.Tier = 'mixed' }
            elseif (-not $row.Tier) { $row.Tier = $tier }
            foreach ($model in @($storedRow.Models)) { if ($model) { $null = $row.Models.Add([string]$model) } }
            foreach ($name in @($storedRow.Descendants)) { if ($name) { $null = $row.Descendants.Add([string]$name) } }
            $row.Runs += [long]$storedRow.Runs
            $row.Requests += [long]$storedRow.Requests
            $row.Input += [long]$storedRow.Input
            $row.Cached += [long]$storedRow.Cached
            $row.CacheWrite += [long]$storedRow.CacheWrite
            $row.Output += [long]$storedRow.Output
            $row.NanoAiu += [decimal]$storedRow.NanoAiu
            foreach ($request in @($storedRow.RequestDetails)) {
                $identityHash = [string]$request.identityHash
                if (-not $identityHash -or -not $seenRequestIdentities.Add($identityHash)) {
                    throw "Exact session cache repeats native request identity '$identityHash' across sessions."
                }
                $row.RequestDetails.Add($request)
            }
        }
    }

    $rows = @(
        foreach ($row in @($rowsByKey.Values | Sort-Object Index, Label, Agent)) {
            if ($row.Models.Count -eq 0) { throw "Cached exact usage has no model identity for '$($row.Agent)'." }
            [pscustomobject][ordered]@{
                Index = $row.Index
                Label = $row.Label
                Member = $row.Member
                Agent = $row.Agent
                Models = @($row.Models | Sort-Object)
                ModelSources = @('host-reported')
                PricedAsUsed = @('native credits')
                Tier = $row.Tier
                Runs = $row.Runs
                Requests = $row.Requests
                Input = $row.Input
                Cached = $row.Cached
                CacheWrite = $row.CacheWrite
                Output = $row.Output
                NanoAiu = $row.NanoAiu
                Cost = [double]($row.NanoAiu / [decimal]1e11)
                Credits = [double]($row.NanoAiu / [decimal]1e9)
                Basis = 'exact-native'
                Descendants = @($row.Descendants | Sort-Object)
                RequestDetails = $row.RequestDetails.ToArray()
            }
        }
    )
    $records = [long](($rows | Measure-Object Requests -Sum).Sum)
    $sessionRecords = [long](($Sessions | Measure-Object records -Sum).Sum)
    if ($records -ne $sessionRecords) {
        throw "Exact session cache rows total $records requests, not the session total $sessionRecords."
    }
    $totalNanoAiu = [decimal](($rows | Measure-Object NanoAiu -Sum).Sum)
    $roleRows = @($rows | Where-Object Label -ne 'orchestration')
    $baseline = $BaselineModel
    if (-not $baseline) {
        $candidateModels = @($roleRows | ForEach-Object Models | Where-Object { (ConvertTo-RateKeyLocal $_) -ne 'hydrafusion-max' } | Select-Object -Unique)
        if ($candidateModels.Count -eq 0 -and $Rates.ByNormalized.ContainsKey('claude-sonnet-4.6')) {
            $candidateModels = @('claude-sonnet-4.6')
        }
        $baseline = @(
            $candidateModels |
                Sort-Object {
                    $rate = Get-BlendedRateLocal -Model $_ -Rates $Rates
                    if ($null -eq $rate) { -1 } else { $rate }
                } -Descending |
                Select-Object -First 1
        ) | Select-Object -First 1
    }

    $baselineCost = [double]0
    $baselineComplete = [bool]$baseline -and $requestDetailsComplete
    if ($baselineComplete) {
        foreach ($row in $roleRows) {
            if (@($row.RequestDetails).Count -ne [long]$row.Requests) {
                $baselineComplete = $false
                break
            }
            foreach ($request in @($row.RequestDetails)) {
                $cost = Get-ExactRequestCounterfactualCostLocal -Request $request -Model $baseline -Rates $Rates
                if ($null -eq $cost) {
                    $baselineComplete = $false
                    break
                }
                $baselineCost += [double]$cost
            }
            if (-not $baselineComplete) { break }
        }
    }
    if (-not $requestDetailsComplete) {
        $Warnings.Add('WARN: cumulative exact actuals include a migrated session without request-level token details; the exact single-model counterfactual is unavailable, but native credits and token totals remain exact.')
    }
    elseif ($baseline -and -not $baselineComplete) {
        $Warnings.Add("WARN: baseline model '$baseline' has no complete rate row; the exact-traffic counterfactual is unavailable.")
    }

    $snapshotMaterial = @(
        foreach ($session in $Sessions) {
            "$($session.sessionId)|$($session.identityDigest)|$($session.records)|$($session.through)"
        }
    ) -join "`n"
    $snapshotDigest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($snapshotMaterial)))
    $snapshotTimestamp = @($Sessions | ForEach-Object through | Where-Object { $_ } | Select-Object -Last 1)
    $totalCost = [double]($totalNanoAiu / [decimal]1e11)
    $totalCredits = [double]($totalNanoAiu / [decimal]1e9)
    $orchestration = @($rows | Where-Object Label -eq 'orchestration' | Select-Object -First 1)
    $latest = $Sessions[-1]
    [pscustomobject][ordered]@{
        Session = if ($ActiveSession) {
            $ActiveSession
        }
        else {
            [pscustomobject]@{
                SessionId = [string]$latest.sessionId
                Path = ''
                First = [string]$latest.first
                Last = [string]$latest.last
            }
        }
        Sessions = @($Sessions | ForEach-Object {
                [pscustomobject][ordered]@{
                    SessionId = [string]$_.sessionId
                    Source = [string]$_.source
                    Records = [long]$_.records
                    Through = [string]$_.through
                    IdentityDigest = [string]$_.identityDigest
                }
            })
        Rows = $rows
        TotalRequests = [int]$records
        TotalInput = [long](($rows | Measure-Object Input -Sum).Sum)
        TotalCached = [long](($rows | Measure-Object Cached -Sum).Sum)
        TotalCacheWrite = [long](($rows | Measure-Object CacheWrite -Sum).Sum)
        TotalOutput = [long](($rows | Measure-Object Output -Sum).Sum)
        TotalNanoAiu = $totalNanoAiu
        TotalCostUsd = $totalCost
        TotalCredits = $totalCredits
        OrchestrationCredits = if ($orchestration.Count) { [double]$orchestration[0].Credits } else { 0.0 }
        BaselineModel = $baseline
        BaselineCostUsd = if ($baselineComplete) { $baselineCost } else { $null }
        BaselineCredits = if ($baselineComplete) { $baselineCost / 0.01 } else { $null }
        SavingsUsd = if ($baselineComplete) { $baselineCost - $totalCost } else { $null }
        SavingsPct = if ($baselineComplete -and $baselineCost -gt 0) { 100.0 * ($baselineCost - $totalCost) / $baselineCost } else { $null }
        AgentCount = $roleRows.Count
        SnapshotRecords = [int]$records
        SnapshotDigest = $snapshotDigest
        SnapshotTimestamp = if ($snapshotTimestamp.Count) { [string]$snapshotTimestamp[0] } else { '' }
        SessionCount = $Sessions.Count
        RequestDetailStatus = if ($requestDetailsComplete) { 'complete' } else { 'partial' }
        CacheSessions = $Sessions
    }
}

function Get-ExactSessionBootstrapLocal {
    <#
    .SYNOPSIS
        Reconstructs an initial exact-session journal from uniquely matching native logs.
    .DESCRIPTION
        This recovery path is used only when `-SessionLog auto` finds current history
        spanning more than one host session and no accepted journal exists yet. Every
        metered history entry must fall inside exactly one complete, attributable
        repository-session event window. Ambiguous or missing coverage fails closed.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Paths,
        [Parameter(Mandatory)][string]$SquadRoot,
        [Parameter(Mandatory)][Collections.IDictionary]$HistoryCoverage,
        [Parameter(Mandatory)][Collections.IDictionary]$MeteredHistoryCoverage,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$HistoryEntries,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$OrderedAggregates,
        [Parameter(Mandatory)]$Rates,
        [Parameter(Mandatory)]$Roster,
        [Parameter(Mandatory)]$ActiveSession,
        [AllowEmptyString()][string]$BaselineModel,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Warnings
    )
    if ($Paths.Count -lt 2) { return $null }

    $entryByKey = @{}
    foreach ($entry in $HistoryEntries) {
        $fileName = "$($entry.Agent).md"
        $key = "$fileName`n$($entry.Identity)"
        if ($entryByKey.ContainsKey($key)) {
            throw "History entry identity '$($entry.Identity)' is duplicated in '$fileName'."
        }
        $entryByKey[$key] = $entry
    }

    $meteredEntries = [Collections.Generic.List[object]]::new()
    foreach ($fileName in @($MeteredHistoryCoverage.Keys | Sort-Object)) {
        foreach ($identity in @($MeteredHistoryCoverage[$fileName])) {
            $key = "$fileName`n$identity"
            if (-not $entryByKey.ContainsKey($key)) {
                throw "Metered history identity '$identity' in '$fileName' has no parsed entry."
            }
            $entry = $entryByKey[$key]
            if (-not $entry.Timestamp) {
                throw "Metered history entry '$($entry.Title)' in '$fileName' has no ISO timestamp."
            }
            try {
                $timestamp = [DateTimeOffset]::Parse([string]$entry.Timestamp, [Globalization.CultureInfo]::InvariantCulture)
            }
            catch {
                throw "Metered history entry '$($entry.Title)' in '$fileName' has an invalid timestamp."
            }
            $meteredEntries.Add([pscustomobject]@{
                    FileName = [string]$fileName
                    Identity = [string]$identity
                    Entry = $entry
                    Timestamp = $timestamp
                })
        }
    }
    if ($meteredEntries.Count -eq 0) { return $null }

    $earliest = @($meteredEntries | Sort-Object Timestamp | Select-Object -First 1)[0].Timestamp
    $latest = @($meteredEntries | Sort-Object Timestamp -Descending | Select-Object -First 1)[0].Timestamp
    $candidates = [Collections.Generic.List[object]]::new()
    $seenSessionIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $eventsFile = Get-Item -LiteralPath $path
        if ($eventsFile.LastWriteTimeUtc -lt $earliest.UtcDateTime) { continue }
        try {
            $candidate = if ($ActiveSession.Path -and [string]::Equals(
                    [IO.Path]::GetFullPath([string]$ActiveSession.Path),
                    [IO.Path]::GetFullPath([string]$path),
                    [StringComparison]::OrdinalIgnoreCase
                )) {
                $ActiveSession
            }
            else {
                Read-SessionUsageLocal -Path $path -SquadRoot $SquadRoot
            }
        }
        catch { continue }
        if ($candidate.UsageSnapshot.status -ne 'complete' -or $candidate.UsageSnapshot.attributionStatus -ne 'complete') { continue }
        if (-not $candidate.First -or -not $candidate.Last) { continue }
        try {
            $start = [DateTimeOffset]::Parse([string]$candidate.First, [Globalization.CultureInfo]::InvariantCulture)
            $end = [DateTimeOffset]::Parse([string]$candidate.Last, [Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            continue
        }
        if ($end -lt $earliest -or $start -gt $latest) { continue }
        if (-not $seenSessionIds.Add([string]$candidate.SessionId)) {
            throw "More than one repository session log reports native session id '$($candidate.SessionId)'."
        }
        $candidates.Add([pscustomobject]@{
                Session = $candidate
                Start = $start
                End = $end
            })
    }
    if ($candidates.Count -lt 2) { return $null }

    $orderedCandidates = @($candidates | Sort-Object Start, End, { $_.Session.SessionId })
    $sessionByEntry = @{}
    $selectedSessionIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $activeTailGrace = [TimeSpan]::FromSeconds(30)
    foreach ($meteredEntry in $meteredEntries) {
        $matches = @(
            $orderedCandidates | Where-Object {
                $isActive = [string]$_.Session.SessionId -ceq [string]$ActiveSession.SessionId
                $effectiveEnd = if ($isActive) { $_.End.Add($activeTailGrace) } else { $_.End }
                $meteredEntry.Timestamp -ge $_.Start -and $meteredEntry.Timestamp -le $effectiveEnd
            }
        )
        if ($matches.Count -eq 0) {
            throw "No complete native session covers metered history entry '$($meteredEntry.Entry.Title)' in '$($meteredEntry.FileName)'."
        }
        if ($matches.Count -gt 1) {
            throw "More than one complete native session covers metered history entry '$($meteredEntry.Entry.Title)' in '$($meteredEntry.FileName)'."
        }
        $sessionId = [string]$matches[0].Session.SessionId
        $sessionByEntry["$($meteredEntry.FileName)`n$($meteredEntry.Identity)"] = $sessionId
        $null = $selectedSessionIds.Add($sessionId)
    }

    if ($ActiveSession -and -not $selectedSessionIds.Contains([string]$ActiveSession.SessionId)) {
        throw "The active native session '$($ActiveSession.SessionId)' does not uniquely cover any current metered history entry."
    }
    $selected = @($orderedCandidates | Where-Object { $selectedSessionIds.Contains([string]$_.Session.SessionId) })
    if ($selected.Count -lt 2) { return $null }

    $selectedIndex = @{}
    $coverageMaps = [Collections.Generic.List[Collections.IDictionary]]::new()
    for ($i = 0; $i -lt $selected.Count; $i++) {
        $selectedIndex[[string]$selected[$i].Session.SessionId] = $i
        $coverage = [ordered]@{}
        foreach ($fileName in @($HistoryCoverage.Keys | Sort-Object)) {
            $coverage[$fileName] = [Collections.Generic.List[string]]::new()
        }
        $coverageMaps.Add($coverage)
    }

    foreach ($fileName in @($HistoryCoverage.Keys | Sort-Object)) {
        $lastIndex = 0
        foreach ($identity in @($HistoryCoverage[$fileName])) {
            $key = "$fileName`n$identity"
            if (-not $entryByKey.ContainsKey($key)) {
                throw "History identity '$identity' in '$fileName' has no parsed entry."
            }
            $entry = $entryByKey[$key]
            $targetIndex = $lastIndex
            if ($sessionByEntry.ContainsKey($key)) {
                $targetIndex = [int]$selectedIndex[[string]$sessionByEntry[$key]]
                if ($targetIndex -lt $lastIndex) {
                    throw "Metered history in '$fileName' does not follow native session chronology."
                }
            }
            elseif ($entry.Timestamp) {
                try {
                    $timestamp = [DateTimeOffset]::Parse([string]$entry.Timestamp, [Globalization.CultureInfo]::InvariantCulture)
                    $eligible = @(
                        for ($i = 0; $i -lt $selected.Count; $i++) {
                            if ($selected[$i].Start -le $timestamp) { $i }
                        }
                    )
                    if ($eligible.Count -gt 0) {
                        $targetIndex = [math]::Max($lastIndex, [int]$eligible[-1])
                    }
                }
                catch {
                    $targetIndex = $lastIndex
                }
            }
            $coverageMaps[$targetIndex][$fileName].Add([string]$identity)
            $lastIndex = $targetIndex
        }
    }

    $cacheSessions = [Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $selected.Count; $i++) {
        $coverage = [ordered]@{}
        foreach ($fileName in @($HistoryCoverage.Keys | Sort-Object)) {
            $coverage[$fileName] = @($coverageMaps[$i][$fileName])
        }
        $expected = Get-ExpectedNativeCoverageLocal -HistoryCoverage $coverage `
            -MeteredHistoryCoverage $MeteredHistoryCoverage `
            -MeteredAgents @($OrderedAggregates | ForEach-Object AgentName) -HistoryEntries $HistoryEntries
        if ([int]$expected.MeteredEntryCount -eq 0) {
            throw "Native session '$($selected[$i].Session.SessionId)' has no metered history coverage."
        }
        $sessionExact = Get-ExactLedgerUsageLocal -Session $selected[$i].Session -Rates $Rates -Roster $Roster `
            -HistoryEntries @($expected.HistoryEntries) -ExpectedAgentNames @($expected.Agents) `
            -RequireOrchestration:$expected.RequireOrchestration -EnforceExpectedSet -RequireSessionBoundary `
            -BaselineModel $BaselineModel -Warnings $Warnings
        if (-not $sessionExact) {
            throw "Native session '$($selected[$i].Session.SessionId)' did not reconcile with its history window."
        }
        $cacheSessions.Add((ConvertTo-CacheSessionLocal -Exact $sessionExact -HistoryCoverage $coverage))
    }

    $cumulativeCoverage = Get-CumulativeHistoryCoverageLocal -Sessions $cacheSessions.ToArray()
    $null = Test-HistoryCoveragePrefixLocal -Recorded $cumulativeCoverage -Current $HistoryCoverage -RequireComplete
    $exactUsage = Merge-ExactSessionUsageLocal -Sessions $cacheSessions.ToArray() -Rates $Rates -Roster $Roster `
        -BaselineModel $BaselineModel -ActiveSession $ActiveSession -Warnings $Warnings
    [pscustomobject][ordered]@{
        Sessions = $cacheSessions.ToArray()
        ExactUsage = $exactUsage
    }
}

function Get-BlendedRateLocal {
    <#
    .SYNOPSIS
        USD per 1M tokens of a representative agentic dispatch for a model id,
        using model-catalog.md's Blended formula over this root's rate row:
        0.20 x Input + 0.80 x Cached + 0.08 x Cache write + 0.02 x Output.
        Returns $null when the id has no rate row.
    #>
    param([AllowEmptyString()][string]$Model, [Parameter(Mandatory)]$Rates)
    $key = ConvertTo-RateKeyLocal $Model
    $byNormalized = if ($Rates.PSObject.Properties['ByNormalized']) { $Rates.ByNormalized } else { @{} }
    if (-not $key -or -not $byNormalized.ContainsKey($key)) { return $null }
    $r = $byNormalized[$key]
    return 0.20 * $r.input + 0.80 * $r.cached + 0.08 * $r.cache_write + 0.02 * $r.output
}

function Get-PropertySumLocal {
    <#
    .SYNOPSIS
        Sums one numeric property over a collection, 0 when it is empty. Under
        Set-StrictMode, `(@() | Measure-Object X -Sum).Sum` throws instead of
        returning $null, so every observed-usage total goes through here.
    #>
    param([AllowNull()][AllowEmptyCollection()][object[]]$InputObject, [Parameter(Mandatory)][string]$Property)
    $total = 0.0
    foreach ($item in @($InputObject)) { if ($null -ne $item -and $null -ne $item.$Property) { $total += [double]$item.$Property } }
    $total
}

function Get-ObservedUsageLocal {
    <#
    .SYNOPSIS
        Joins the session log's per-dispatch totals to this root's history
        aggregates and prices both the routed run and a single-model baseline
        at blended rates. Returns $null when there is nothing observed.
    #>
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Rates,
        [AllowEmptyCollection()][object[]]$OrderedAggregates = @(),
        $OrchestrationAggregate,
        [AllowEmptyString()][string]$BaselineModel,
        [System.Collections.Generic.List[string]]$Warnings
    )
    if ($Session.Dispatches.Count -eq 0 -and $null -eq $Session.NanoAiu -and $null -eq $Session.UsageSnapshot.checkpointNanoAiu) { return $null }
    if ($Session.UsageSnapshot.status -ne 'complete') {
        $Warnings.Add("WARN: exact host credit metering is incomplete: $(@($Session.UsageSnapshot.problems) -join ' ')")
    }

    $estimatedByAgent = @{}
    $hydraEstimateByAgent = @{}
    $ledgerModelsByAgent = @{}
    foreach ($entry in $OrderedAggregates) {
        $agg = $entry.Aggregate
        $estimatedByAgent[$entry.AgentName] = [pscustomobject]@{
            Scaled = $agg.Input + $agg.Cached + $agg.CacheWrite
            Output = $agg.Output
            Total  = $agg.Input + $agg.Cached + $agg.CacheWrite + $agg.Output
        }
        $hydraScaled = 0.0
        $hydraInput = 0.0
        $hydraCached = 0.0
        $hydraCacheWrite = 0.0
        $hydraOutput = 0.0
        foreach ($blockEntry in $agg.Blocks) {
            $fields = $blockEntry.Block.Fields
            if ((ConvertTo-RateKeyLocal ([string]$fields['model'])) -ne 'hydrafusion-max') {
                continue
            }
            $hydraInput += [double]$fields['input_tokens']
            $hydraCached += [double]$fields['cached_tokens']
            $hydraCacheWrite += [double]$fields['cache_write_tokens']
            $hydraOutput += [double]$fields['output_tokens']
        }
        $hydraScaled = $hydraInput + $hydraCached + $hydraCacheWrite
        if ($hydraScaled -gt 0 -or $hydraOutput -gt 0) {
            $hydraEstimateByAgent[$entry.AgentName] = [pscustomobject]@{
                Input      = $hydraInput
                Cached     = $hydraCached
                CacheWrite = $hydraCacheWrite
                Scaled     = $hydraScaled
                Output     = $hydraOutput
                Total      = $hydraScaled + $hydraOutput
            }
        }
        $ledgerModelsByAgent[$entry.AgentName] = @($agg.Models)
    }
    if ($OrchestrationAggregate) {
        $estimatedByAgent['Squad Scribe'] = [pscustomobject]@{
            Scaled = $OrchestrationAggregate.Input + $OrchestrationAggregate.Cached + $OrchestrationAggregate.CacheWrite
            Output = $OrchestrationAggregate.Output
            Total  = $OrchestrationAggregate.Input + $OrchestrationAggregate.Cached + $OrchestrationAggregate.CacheWrite + $OrchestrationAggregate.Output
        }
        $ledgerModelsByAgent['Squad Scribe'] = @($OrchestrationAggregate.Models)
    }

    $unpriced = [System.Collections.Generic.List[string]]::new()
    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($group in ($Session.Dispatches | Group-Object AgentName)) {
        $observedModels = @($group.Group | ForEach-Object { $_.Model } | Where-Object { $_ } | Select-Object -Unique)
        $solverModels = @($group.Group | ForEach-Object { if ($_.PSObject.Properties['FirstDispatchedModel']) { $_.FirstDispatchedModel } } | Where-Object { $_ -and $_ -notin $observedModels } | Select-Object -Unique)
        $cost = 0.0
        foreach ($d in $group.Group) {
            $blended = Get-BlendedRateLocal -Model $d.Model -Rates $Rates
            if ($null -eq $blended -and $d.PSObject.Properties['FirstDispatchedModel'] -and $d.FirstDispatchedModel) {
                $blended = Get-BlendedRateLocal -Model $d.FirstDispatchedModel -Rates $Rates
            }
            if ($null -eq $blended) { if ($d.Model -notin $unpriced) { $unpriced.Add($d.Model) }; continue }
            $cost += $d.Tokens * $blended / 1e6
        }
        $ledgerModels = @(if ($ledgerModelsByAgent.ContainsKey($group.Name)) { $ledgerModelsByAgent[$group.Name] })
        $observedKeys = @($observedModels | ForEach-Object { ConvertTo-RateKeyLocal $_ })
        $ledgerKeys = @($ledgerModels | ForEach-Object { ConvertTo-RateKeyLocal $_ } | Where-Object { $_ -and $_ -ne 'unknown' })
        $match = if ($ledgerKeys.Count -eq 0) { 'n/a' }
        elseif (@($ledgerKeys | Where-Object { $_ -notin $observedKeys }).Count -eq 0 -and @($observedKeys | Where-Object { $_ -notin $ledgerKeys }).Count -eq 0) { 'yes' }
        else { 'no' }
        if ($match -eq 'no') {
            $Warnings.Add("WARN: observed model for '$($group.Name)' is $($observedModels -join ', ') but its history blocks record $($ledgerModels -join ', ').")
        }
        $rows.Add([pscustomobject]@{
                Agent          = $group.Name
                IsScribe       = ($group.Name -eq 'Squad Scribe')
                Dispatches     = $group.Count
                ObservedModels = $observedModels
                SolverModels   = $solverModels
                LedgerModels   = $ledgerModels
                Match          = $match
                Tokens         = Get-PropertySumLocal -InputObject $group.Group -Property Tokens
                Estimated      = if ($estimatedByAgent.ContainsKey($group.Name)) { $estimatedByAgent[$group.Name].Total } else { 0.0 }
                Minutes        = (Get-PropertySumLocal -InputObject $group.Group -Property DurationMs) / 60000.0
                CostUsd        = $cost
            })
    }
    foreach ($m in $unpriced) { $Warnings.Add("WARN: observed model '$m' has no rate row in consumption-rates.md; its tokens are left out of the blended cost.") }

    $roleRows = @($rows | Where-Object { -not $_.IsScribe })
    $roleTokens = Get-PropertySumLocal -InputObject $roleRows -Property Tokens
    $hydraDispatchRows = @(
        $Session.Dispatches | Where-Object {
            $_.AgentName -ne 'Squad Scribe' -and (
                (ConvertTo-RateKeyLocal $_.Model) -eq 'hydrafusion-max' -or
                ($_.PSObject.Properties['FirstDispatchedModel'] -and (ConvertTo-RateKeyLocal $_.FirstDispatchedModel) -eq 'hydrafusion-max')
            )
        }
    )

    $baseline = $BaselineModel
    if (-not $baseline) {
        $candidateModels = @($roleRows | ForEach-Object { $_.ObservedModels } | Select-Object -Unique)
        if ($hydraDispatchRows.Count -gt 0) {
            $nonHydra = @($candidateModels | Where-Object { (ConvertTo-RateKeyLocal $_) -ne 'hydrafusion-max' })
            $defaultFallback = if ($null -ne (Get-BlendedRateLocal -Model 'claude-sonnet-4.6' -Rates $Rates)) { 'claude-sonnet-4.6' }
            elseif ($Rates.ByTier.ContainsKey('default') -and $Rates.ByTier['default'].pricedAsName) { [string]$Rates.ByTier['default'].pricedAsName }
            else { $null }
            $candidateModels = @($nonHydra + $(if ($defaultFallback) { @($defaultFallback) } else { @() }) | Select-Object -Unique)
            if ($candidateModels.Count -eq 0) { $candidateModels = @($roleRows | ForEach-Object { $_.ObservedModels } | Select-Object -Unique) }
        }
        $baseline = @($candidateModels |
                Sort-Object { $rate = Get-BlendedRateLocal -Model $_ -Rates $Rates; if ($null -eq $rate) { -1 } else { $rate } } -Descending |
                Select-Object -First 1) | Select-Object -First 1
    }
    $baselineRate = if ($baseline) { Get-BlendedRateLocal -Model $baseline -Rates $Rates } else { $null }
    if ($baseline -and $null -eq $baselineRate) { $Warnings.Add("WARN: baseline model '$baseline' has no rate row; the without-HVE-Squad comparison is omitted.") }

    $hydraSummary = $null
    if ($hydraDispatchRows.Count -gt 0) {
        $hydraObservedTokens = Get-PropertySumLocal -InputObject $hydraDispatchRows -Property Tokens
        $hydraCostUsd = 0.0
        foreach ($dispatch in $hydraDispatchRows) {
            $blended = Get-BlendedRateLocal -Model $dispatch.Model -Rates $Rates
            if ($null -eq $blended -and $dispatch.PSObject.Properties['FirstDispatchedModel']) {
                $blended = Get-BlendedRateLocal -Model $dispatch.FirstDispatchedModel -Rates $Rates
            }
            if ($null -ne $blended) {
                $hydraCostUsd += $dispatch.Tokens * $blended / 1e6
            }
        }

        $hydraEstimatedTokens = 0.0
        $hasHydraEstimate = $false
        $hasCategoryEstimate = $false
        $hasProportionalEstimate = $false
        foreach ($agentGroup in ($hydraDispatchRows | Group-Object AgentName)) {
            if ($hydraEstimateByAgent.ContainsKey($agentGroup.Name)) {
                $estimate = $hydraEstimateByAgent[$agentGroup.Name]
                $hydraEstimatedTokens += ($estimate.Scaled / 0.35) + $estimate.Output
                $hasHydraEstimate = $true
                $hasCategoryEstimate = $true
                continue
            }
            if (-not $estimatedByAgent.ContainsKey($agentGroup.Name)) {
                continue
            }

            $allAgentDispatches = @($Session.Dispatches | Where-Object { $_.AgentName -eq $agentGroup.Name })
            $allAgentTokens = Get-PropertySumLocal -InputObject $allAgentDispatches -Property Tokens
            if ($allAgentTokens -le 0) {
                continue
            }
            $hydraAgentTokens = Get-PropertySumLocal -InputObject $agentGroup.Group -Property Tokens
            $share = [math]::Min(1.0, [math]::Max(0.0, $hydraAgentTokens / $allAgentTokens))
            $hydraEstimatedTokens += $estimatedByAgent[$agentGroup.Name].Total * $share
            $hasHydraEstimate = $true
            $hasProportionalEstimate = $true
        }
        $counterfactualBasis = if ($hasCategoryEstimate -and $hasProportionalEstimate) {
            'mixed category-specific 0.35x inverse and proportional token-share estimate; representative blended-rate pricing'
        }
        elseif ($hasCategoryEstimate) {
            'category-specific 0.35x inverse for input/cache/cache-write with output unchanged; representative blended-rate pricing'
        }
        elseif ($hasProportionalEstimate) {
            'proportional token-share estimate; representative blended-rate pricing'
        }
        else {
            $null
        }
        $hydraSolvers = @(
            $hydraDispatchRows |
                ForEach-Object {
                    if ($_.PSObject.Properties['FirstDispatchedModel'] -and $_.FirstDispatchedModel -and (ConvertTo-RateKeyLocal $_.FirstDispatchedModel) -ne 'hydrafusion-max') {
                        $_.FirstDispatchedModel
                    }
                } |
                Where-Object { $_ } |
                Select-Object -Unique
        )
        if ($hydraSolvers.Count -eq 0 -and $Session.PSObject.Properties['FusionSolvers']) {
            $hydraSolvers = @($Session.FusionSolvers)
        }
        $hydraSummary = [pscustomobject]@{
            Dispatches            = [int]$hydraDispatchRows.Count
            ObservedTokens        = $hydraObservedTokens
            EstimatedTokens       = if ($hasHydraEstimate) { $hydraEstimatedTokens } else { $null }
            BlendedCostUsd        = $hydraCostUsd
            CounterfactualModel   = $baseline
            CounterfactualCostUsd = if ($hasHydraEstimate -and $null -ne $baselineRate) { $hydraEstimatedTokens * $baselineRate / 1e6 } else { $null }
            CounterfactualBasis   = $counterfactualBasis
            SolverModels          = @($hydraSolvers)
        }
    }

    [pscustomobject]@{
        Session          = $Session
        Rows             = $rows
        ObservedTokens   = Get-PropertySumLocal -InputObject $rows -Property Tokens
        EstimatedTokens  = Get-PropertySumLocal -InputObject $rows -Property Estimated
        SquadCostUsd     = Get-PropertySumLocal -InputObject $rows -Property CostUsd
        RoleTokens       = $roleTokens
        BaselineModel    = $baseline
        BaselineCostUsd  = if ($null -ne $baselineRate) { $roleTokens * $baselineRate / 1e6 } else { $null }
        HydraFusion      = $hydraSummary
        SessionAiu       = if ($null -ne $Session.NanoAiu) { $Session.NanoAiu / 1e9 } else { $null }
        MeteringStatus   = $Session.UsageSnapshot.status
        MeteringProblems = @($Session.UsageSnapshot.problems)
        UsageRecords     = $Session.UsageSnapshot.records
        CheckpointAiu    = if ($null -ne $Session.UsageSnapshot.checkpointNanoAiu) { $Session.UsageSnapshot.checkpointNanoAiu / 1e9 } else { $null }
    }
}

function Get-ObservedSectionLinesLocal {
    <#
    .SYNOPSIS
        Renders the `## Observed Usage (host-reported)` section. Column names avoid
        `Turns`/`Basis`/`Model Source`/`Priced As`, which -Check uses to find the
        estimated tables.
    #>
    param([Parameter(Mandatory)]$Observed)
    $s = $Observed.Session
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('## Observed Usage (host-reported)')
    $lines.Add('')
    $scope = if ($s.MemberName) { " Only dispatches whose prompt names ``members/$($s.MemberName)`` are counted." } else { '' }
    $lines.Add("Source: Copilot session ``$($s.SessionId)`` (``events.jsonl``, $($s.First) to $($s.Last)). Complete ``session.usage_record`` and native compaction records are deduplicated by host accounting identity for authoritative AI credits. Subagent token totals remain beside the estimates rather than replacing per-role rows. Blended USD prices each dispatch total with model-catalog.md's representative mix over this root's rate rows.$scope")
    $lines.Add('')
    $lines.Add('| Agent | Dispatches | Observed Model | Ledger Model | Match | Observed Tokens | Estimated Tokens | Minutes | Calculated Blended USD |')
    $lines.Add('| ----- | ---------- | -------------- | ------------ | ----- | --------------- | ---------------- | ------- | ---------------------- |')
    foreach ($r in ($Observed.Rows | Sort-Object IsScribe, Agent)) {
        $ledger = if ($r.LedgerModels.Count -gt 0) { $r.LedgerModels -join ', ' } else { '—' }
        $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5:N0} | {6:N0} | {7:N1} | {8:N4} |' -f $r.Agent, $r.Dispatches, ($r.ObservedModels -join ', '), $ledger, $r.Match, $r.Tokens, $r.Estimated, $r.Minutes, $r.CostUsd))
    }
    $lines.Add(('| **Subagents total** | **{0}** | | | | **{1:N0}** | **{2:N0}** | | **{3:N4}** |' -f (Get-PropertySumLocal -InputObject $Observed.Rows -Property Dispatches), $Observed.ObservedTokens, $Observed.EstimatedTokens, $Observed.SquadCostUsd))
    $lines.Add('')
    if ($null -ne $Observed.SessionAiu) {
        $lines.Add(('Exact complete-record total, coordinator and descendants included: **{0:N2} AI credits** (about {1:N2} USD at 0.01 USD per credit) across **{2:N0}** unique usage records. The coordinator''s own turns appear only in this figure, never in the table.' -f $Observed.SessionAiu, ($Observed.SessionAiu * 0.01), $Observed.UsageRecords))
        if ($null -ne $Observed.CheckpointAiu -and [math]::Abs($Observed.CheckpointAiu - $Observed.SessionAiu) -gt 0.005) {
            $lines.Add(('Latest session checkpoint was **{0:N2} credits** and is retained only as lag diagnostics; it is not used as the billed total.' -f $Observed.CheckpointAiu))
        }
        $lines.Add('')
    }
    elseif ($null -ne $Observed.CheckpointAiu) {
        $lines.Add(('Latest host checkpoint is **{0:N2} credits**, but no complete usage-record total is available; this checkpoint may lag and is not authoritative.' -f $Observed.CheckpointAiu))
        $lines.Add('')
    }
    if ($null -ne $Observed.BaselineCostUsd) {
        $lines.Add('### Without HVE Squad')
        $lines.Add('')
        $lines.Add('| Scenario | Tokens | Model | Calculated Blended USD |')
        $lines.Add('| -------- | ------ | ----- | ---------------------- |')
        $lines.Add(('| With HVE Squad: routed roles plus Scribe, as observed | {0:N0} | as routed | {1:N4} |' -f $Observed.ObservedTokens, $Observed.SquadCostUsd))
        $lines.Add(('| Without HVE Squad: the same role work on one model, no Scribe | {0:N0} | {1} | {2:N4} |' -f $Observed.RoleTokens, $Observed.BaselineModel, $Observed.BaselineCostUsd))
        $lines.Add('')
        $delta = $Observed.BaselineCostUsd - $Observed.SquadCostUsd
        $pct = if ($Observed.BaselineCostUsd -gt 0) { [math]::Abs($delta) / $Observed.BaselineCostUsd * 100 } else { 0 }
        $direction = if ($delta -ge 0) { 'lower' } else { 'higher' }
        $lines.Add(('HVE Squad is **{0:N4} USD ({1:N1}%) {2}** than running the same role work on `{3}`. Both rows use the same blended mix; neither includes coordinator turns, and the single-model row adds no context growth or rework a long single chat would carry, so it is a floor for that scenario rather than a forecast.' -f [math]::Abs($delta), $pct, $direction, $Observed.BaselineModel))
        $lines.Add('')
        if ($Observed.PSObject.Properties['HydraFusion'] -and $Observed.HydraFusion -and $null -ne $Observed.HydraFusion.CounterfactualCostUsd) {
            $hf = $Observed.HydraFusion
            $solverNote = if ($hf.SolverModels.Count -gt 0) { " (solver: $($hf.SolverModels -join ', '))" } else { '' }
            $tokDelta = $hf.EstimatedTokens - $hf.ObservedTokens
            $tokPct = if ($hf.EstimatedTokens -gt 0) { [math]::Abs($tokDelta) / $hf.EstimatedTokens * 100.0 } else { 0.0 }
            $tokDirection = if ($tokDelta -ge 0) { 'fewer' } else { 'more' }
            $costSaved = $hf.CounterfactualCostUsd - $hf.BlendedCostUsd
            $costPct = if ($hf.CounterfactualCostUsd -gt 0) { [math]::Abs($costSaved) / $hf.CounterfactualCostUsd * 100.0 } else { 0.0 }
            $costDirection = if ($costSaved -ge 0) { 'lower' } else { 'higher' }
            $lines.Add(('HydraFusion comparison: **{0}** role dispatch(es) on `hydrafusion-max`{1} consumed **{2:N0} host-reported tokens** with a **calculated representative-blend cost of {3:N4} USD**, against an **estimated counterfactual of {4:N0} standard-model tokens ({5:N4} calculated USD on `{6}`)** — **{7:N1}% {8} tokens and {9:N4} USD ({10:N1}%) {11} calculated cost** on those dispatches. Counterfactual basis: {12}.' -f $hf.Dispatches, $solverNote, $hf.ObservedTokens, $hf.BlendedCostUsd, $hf.EstimatedTokens, $hf.CounterfactualCostUsd, $hf.CounterfactualModel, $tokPct, $tokDirection, [math]::Abs($costSaved), $costPct, $costDirection, $hf.CounterfactualBasis))
            $lines.Add('')
        }
    }
    return $lines.ToArray()
}

function Get-ConsumptionWithObservedLocal {
    <#
    .SYNOPSIS
        Replaces an existing Observed Usage section, or inserts one before
        `## Cost Comparison` (or at the end), in consumption.md text.
    #>
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][AllowEmptyString()][string[]]$SectionLines)
    Get-ConsumptionWithSectionLocal -Text $Text -SectionLines $SectionLines -HeadingPattern '^##\s+Observed Usage \(host-reported\)\s*$' -InsertBeforePatterns @('^##\s+Cost Comparison')
}

function Get-ConsumptionWithSectionLocal {
    <#
    .SYNOPSIS
        Replaces the `##` section matching HeadingPattern in consumption.md text, or
        inserts it before the first heading matching the earliest InsertBeforePatterns
        entry that exists (else at the end).
    #>
    param(
        [Parameter(Mandatory)][string]$Text,
        [AllowEmptyCollection()][AllowEmptyString()][string[]]$SectionLines = @(),
        [Parameter(Mandatory)][string]$HeadingPattern,
        [Parameter(Mandatory)][string[]]$InsertBeforePatterns
    )
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($Text -split '\r?\n')) { $lines.Add($l) }

    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $HeadingPattern) { $start = $i; break } }
    if ($start -ge 0) {
        $end = $lines.Count
        for ($j = $start + 1; $j -lt $lines.Count; $j++) { if ($lines[$j] -match '^##\s') { $end = $j; break } }
        $lines.RemoveRange($start, $end - $start)
        $insertAt = $start
    }
    else {
        $insertAt = $lines.Count
        :search foreach ($pattern in $InsertBeforePatterns) {
            for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { $insertAt = $i; break search } }
        }
    }
    $lines.InsertRange($insertAt, [string[]]$SectionLines)
    return ($lines -join $newline)
}

function Get-CostComparisonUpdateLocal {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][double]$CostUsd,
        [Parameter(Mandatory)][double]$Credits,
        [Parameter(Mandatory)][int]$AgentCount
    )
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $issues = [System.Collections.Generic.List[string]]::new()
    $heading = [regex]::Match($Text, '(?m)^##[ \t]+Cost Comparison[^\r\n]*(?:\r?\n|$)')
    $added = -not $heading.Success
    $start = if ($added) { $Text.Length } else { $heading.Index + $heading.Length }
    $next = [regex]::Match($Text.Substring($start), '(?m)^##[ \t]+')
    $length = if ($next.Success) { $next.Index } else { $Text.Length - $start }
    $body = $Text.Substring($start, $length)
    $number = '[0-9][0-9,]*(?:\.\d+)?'
    $figure = '\*\*\$(?<cost>{0}) \(~(?<credits>{0}) AI credits\)\*\*' -f $number
    $line = [regex]::Match($body, '(?m)^This run consumed an estimated (?<figure>\*\*\$[^*\r\n]+\*\*)[^\r\n]*')
    $numeric = [regex]::Match($line.Groups['figure'].Value, "^$figure$")
    $baselinePattern = 'estimated at \*\*\$(?<manual>{0}) \(~{0} AI credits\)\*\*' -f $number
    if ($line.Success -and ($numeric.Success -or [regex]::IsMatch($line.Value, $baselinePattern))) {
        if ($numeric.Success) {
            $quotedCost = [double]::Parse($numeric.Groups['cost'].Value.Replace(',', ''), $culture)
            $quotedCredits = [double]::Parse($numeric.Groups['credits'].Value.Replace(',', ''), $culture)
            if ([math]::Round($quotedCost, 4) -ne [math]::Round($CostUsd, 4)) { $issues.Add('Cost Comparison estimated cost differs from the derived ledger total.') }
            if ([math]::Round($quotedCredits, 2) -ne [math]::Round($Credits, 2)) { $issues.Add('Cost Comparison estimated credits differ from the derived ledger total.') }
        }
        else { $issues.Add('Cost Comparison has no recognizable estimated squad figures; run -Write to finalize it.') }
        $prefix = 'This run consumed an estimated **${0} (~{1} AI credits)**' -f $CostUsd.ToString('F4', $culture), $Credits.ToString('F2', $culture)
        $updated = $prefix + $line.Value.Substring($line.Groups['figure'].Index + $line.Groups['figure'].Length - $line.Index)
        $updated = $updated.Replace('<n>', $AgentCount.ToString($culture))
        $updated = $updated -replace 'across \d+ specialized agent\(s\) \(squad figure only;', "across $AgentCount specialized agent(s) (squad figure only;"
        $updated = $updated -replace ' \(stale — refreshed at run end\)$', ''
        $baseline = [regex]::Match($updated, $baselinePattern)
        $saving = [regex]::Match($updated, '(?:a )?saving of about \*\*(?<pct>[+-]?\d+(?:\.\d+)?|<savings-pct>)%\*\*')
        if ($baseline.Success -and $saving.Success) {
            $manual = [double]::Parse($baseline.Groups['manual'].Value.Replace(',', ''), $culture)
            if ($manual -gt 0) {
                $digits = if ($saving.Groups['pct'].Value.Contains('.')) { [math]::Min(15, $saving.Groups['pct'].Value.Split('.')[1].Length) } else { 0 }
                $expected = (100.0 * ($manual - $CostUsd) / $manual).ToString("F$digits", $culture)
                if ($saving.Groups['pct'].Value -eq '<savings-pct>' -or [double]::Parse($saving.Groups['pct'].Value, $culture) -ne [double]::Parse($expected, $culture)) { $issues.Add('Cost Comparison saving differs from the supplied manual baseline and derived total.') }
                $updated = $updated.Substring(0, $saving.Groups['pct'].Index) + $expected + $updated.Substring($saving.Groups['pct'].Index + $saving.Groups['pct'].Length)
            }
            else {
                $issues.Add('Cost Comparison saving is unavailable with a non-positive manual baseline.')
                $updated = $updated.Substring(0, $saving.Index) + 'saving unavailable (non-positive manual baseline)' + $updated.Substring($saving.Index + $saving.Length)
            }
        }
        elseif ($saving.Success) {
            $issues.Add('Cost Comparison saving has no recognizable manual baseline.')
            $updated = $updated.Substring(0, $saving.Index) + 'saving unavailable (manual baseline unavailable)' + $updated.Substring($saving.Index + $saving.Length)
        }
        $body = $body.Substring(0, $line.Index) + $updated + $body.Substring($line.Index + $line.Length)
    }
    else {
        $issues.Add('Cost Comparison is missing or has no recognizable estimated squad figures; run -Write to finalize it.')
        $fallback = 'This run consumed an estimated **${0} (~{1} AI credits)** across {2} specialized agent(s) (squad figure only; native per-role attribution unavailable; manual baseline and saving unavailable).' -f $CostUsd.ToString('F4', $culture), $Credits.ToString('F2', $culture), $AgentCount
        $seed = [regex]::Match($body, '(?m)^(?:n/a \(initialization\)\.|This run has not yet dispatched|This run consumed an estimated)[^\r\n]*')
        if ($seed.Success) { $body = $body.Substring(0, $seed.Index) + $fallback + $body.Substring($seed.Index + $seed.Length) }
        else { $body = "$newline$fallback$newline$newline" + $body }
    }
    $result = if ($added) {
        $template = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../references/consumption.md'))
        $disclaimer = [regex]::Match($template, '(?m)^> Estimates only\.[^\r\n]*').Value
        $Text.TrimEnd() + "$newline${newline}## Cost Comparison (illustrative)$newline" + $body + "$newline$disclaimer$newline"
    }
    else { $Text.Substring(0, $start) + $body + $Text.Substring($start + $length) }
    [pscustomobject]@{ Text = $result; Issues = $issues.ToArray(); Added = $added }
}

function Get-ExactCostComparisonSectionLinesLocal {
    param([Parameter(Mandatory)]$Exact)

    $inv = [Globalization.CultureInfo]::InvariantCulture
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('## Cost Comparison (exact native actual)')
    $lines.Add('')
    $lines.Add('| Scenario | Basis | AI Credits | USD |')
    $lines.Add('| -------- | ----- | ----------: | --: |')
    $lines.Add(('| With HVE Squad through {0} | complete deduplicated native records; coordinator and descendants included | {1} | {2} |' -f
            $Exact.SnapshotTimestamp,
            ([double]$Exact.TotalCredits).ToString('F2', $inv),
            ([double]$Exact.TotalCostUsd).ToString('F4', $inv)))
    if ($null -ne $Exact.BaselineCostUsd) {
        $lines.Add(('| Without HVE Squad: same exact role-request token categories on `{0}`, no coordinator or Scribe | calculated counterfactual from exact request tokens | {1} | {2} |' -f
                $Exact.BaselineModel,
                ([double]$Exact.BaselineCredits).ToString('F2', $inv),
                ([double]$Exact.BaselineCostUsd).ToString('F4', $inv)))
        $lines.Add('')
        $direction = if ($Exact.SavingsUsd -ge 0) { 'lower' } else { 'higher' }
        $lines.Add(('HVE Squad is **{0} USD ({1}%) {2}** than the same exact role traffic on `{3}`.' -f
                ([math]::Abs([double]$Exact.SavingsUsd)).ToString('F4', $inv),
                ([math]::Abs([double]$Exact.SavingsPct)).ToString('F1', $inv),
                $direction,
                $Exact.BaselineModel))
    }
    else {
        $lines.Add('')
        $lines.Add('The exact HVE Squad total is available, but the without-Squad counterfactual is unavailable because no complete baseline-model rate row resolved.')
    }
    $lines.Add('')
    $snapshotLabel = if ([int]$Exact.SessionCount -gt 1) { "$($Exact.SessionCount) accumulated native session snapshots" } else { 'the native session snapshot' }
    if ($null -ne $Exact.BaselineCostUsd) {
        $lines.Add(('> The HVE Squad row is exact as of {0}: {1} complete accounting records, cumulative digest `{2}`. The without-Squad row is not an observed alternate run; it holds every exact role request''s uncached input, cache read, cache write, and output counts constant, reprices them on one model, and excludes coordinator/Scribe overhead. It therefore measures routing savings on identical traffic and does not invent context growth, rework, or behavioral differences for a hypothetical manual run.' -f
                $snapshotLabel, $Exact.SnapshotRecords, $Exact.SnapshotDigest))
    }
    else {
        $unavailableReason = if ($Exact.RequestDetailStatus -ne 'complete') {
            'at least one accepted snapshot lacks the request-level token detail needed for an identical-traffic counterfactual'
        }
        elseif ([int]$Exact.AgentCount -eq 0) {
            'there is no role traffic to reprice without coordinator/Scribe overhead'
        }
        else {
            'no complete baseline-model rate row resolved'
        }
        $lines.Add(('> The HVE Squad row is exact as of {0}: {1} complete accounting records, cumulative digest `{2}`. No without-Squad row is claimed because {3}.' -f
                $snapshotLabel, $Exact.SnapshotRecords, $Exact.SnapshotDigest, $unavailableReason))
    }
    $lines.Add('')
    $lines.ToArray()
}

# ---------------------------------------------------------------------------
# Unit economics (value): cost per deliverable an independent review accepted.
# ---------------------------------------------------------------------------

# Keep identical to $ReviewRoles in Write-SquadHandoff.ps1.
$script:UnitEconomicsReviewRoles = @('tester', 'qa-engineer', 'challenger', 'fact-checker', 'supply-chain', 'vuln-manager', 'privacy', 'accessibility', 'risk-manager')

function Get-HistoryEntryRecordsLocal {
    <#
    .SYNOPSIS
        One record per `###` dispatch entry in a history file: heading timestamp and
        the Turn / Workstream / Deliverable / Outcome bullets. Cost is filled in later.
    #>
    param([Parameter(Mandatory)][string]$Content, [Parameter(Mandatory)][string]$AgentName)
    $headings = @([regex]::Matches($Content, '(?m)^###[ \t]+(?<title>\S.*)'))
    for ($i = 0; $i -lt $headings.Count; $i++) {
        $start = $headings[$i].Index
        $end = if ($i + 1 -lt $headings.Count) { $headings[$i + 1].Index } else { $Content.Length }
        $text = $Content.Substring($start, $end - $start)
        $field = {
            param($name)
            $m = [regex]::Match($text, "(?mi)^[ \t]*[*-][ \t]+$name`:[ \t]*(?<v>[^\r\n]*)")
            if ($m.Success) { $m.Groups['v'].Value.Trim() } else { '' }
        }
        $stamp = ($headings[$i].Groups['title'].Value.Trim() -split '\s+')[0]
        $deliverable = (& $field 'Deliverable').Replace('`', '').Trim().Replace('\', '/').ToLowerInvariant()
        if ($deliverable -in @('none', 'n/a', '-', [string][char]0x2014)) { $deliverable = '' }
        [pscustomobject]@{
            Agent              = $AgentName
            Start              = $start
            End                = $end
            Timestamp          = if ($stamp -match '^\d{4}-\d\d-\d\dT') { $stamp } else { '' }
            Identity           = Get-ShortIdentityHashLocal -Text $headings[$i].Groups['title'].Value.Trim()
            HasConsumption     = $false
            Turn               = (& $field 'Turn')
            Workstream         = (& $field 'Workstream').ToLowerInvariant()
            MemberName         = (& $field 'Member Name')
            ExternalProvenance = (& $field 'External provenance')
            MalformedExternalMarkers = [regex]::IsMatch($text, '(?mi)^[ \t]*(?:-[ \t]+)?(?:External provenance|Verification|External-unmetered):')
            Title              = $headings[$i].Groups['title'].Value.Trim()
            Verification       = (& $field 'Verification')
            ExternalUnmeteredConnector = ((& $field 'External-unmetered') -replace '^connector=', '')
            Deliverable        = $deliverable
            Request            = (& $field 'Request')
            Outcome            = (& $field 'Outcome')
            Cost               = 0.0
            Seq                = 0
        }
    }
}

function Add-BlockCostToEntryLocal {
    param([AllowEmptyCollection()][object[]]$Entries = @(), [Parameter(Mandatory)][int]$Offset, [Parameter(Mandatory)][double]$Cost)
    $entry = $Entries | Where-Object { $Offset -ge $_.Start -and $Offset -lt $_.End } | Select-Object -First 1
    if ($entry) {
        $entry.Cost += $Cost
        $entry.HasConsumption = $true
    }
}

function Get-UnitEconomicsLocal {
    <#
    .SYNOPSIS
        Derives value counts and credit ratios from the non-Scribe history entries.
        Ratios that cannot be computed are $null (rendered `n/a`).
    #>
    param(
        [AllowEmptyCollection()][object[]]$Entries = @(),
        [Parameter(Mandatory)]$Roster,
        [Parameter(Mandatory)][double]$TotalCredits,
        [Parameter(Mandatory)][double]$OrchestrationCredits,
        $HostAiu,
        [ValidateSet('estimated', 'exact-native')][string]$CostBasis = 'estimated'
    )
    $sorted = @($Entries | Sort-Object -Property Timestamp, Seq)

    $seen = @{}
    foreach ($e in $sorted) {
        $extProv = if ($e.PSObject.Properties['ExternalProvenance']) { [string]$e.ExternalProvenance } else { '' }
        $resolvedRole = Resolve-RoleForAgentLocal -AgentName $e.Agent -MemberName $e.MemberName -Roster $Roster -ExternalProvenance $extProv
        $role = $resolvedRole.ClassificationRole
        $e | Add-Member -NotePropertyName IsReview -NotePropertyValue ($role.ToLowerInvariant() -in $script:UnitEconomicsReviewRoles) -Force
        $isRework = $false
        if ($e.Deliverable) {
            $key = "$($e.Agent.ToLowerInvariant())|$($e.Deliverable)"
            if ($seen.ContainsKey($key)) { $isRework = $true } else { $seen[$key] = $true }
        }
        $e | Add-Member -NotePropertyName IsRework -NotePropertyValue $isRework -Force
    }

    $reviews = @($sorted | Where-Object { $_.IsReview })
    $verdictOf = {
        param($outcome)
        $m = [regex]::Match($outcome, '(?i)\b(pass-with-findings|pass|approved?|fail(ed)?|reject(ed)?|blocked)\b')
        if (-not $m.Success) { return 'unknown' }
        if ($m.Value -match '^(?i)(pass|approv)') { 'accepted' } else { 'rejected' }
    }

    # A review that names deliverables (full path, or a file name unique among its turn and workstream's deliverables, in its
    # Request or Outcome) covers only those; a review that mentions none covers every deliverable of its turn and workstream.
    # A file name shared by two deliverables of the same turn and workstream names neither: only the full path does, and the
    # mention still keeps the review from covering everything (consumption.md *Unit economics*).
    $reviewText = { param($review) "$($review.Request) $($review.Outcome)".Replace('`', '').Replace('\', '/').ToLowerInvariant() }
    $leafOf = { param($path) ($path -split '/')[-1] }
    $mentionsLeaf = {
        param($text, $path)
        $leaf = & $leafOf $path
        $leaf -and [regex]::IsMatch($text, '(?<![\w./-])' + [regex]::Escape($leaf) + '(?![\w-])')
    }
    $mentionsDeliverable = {
        param($review, $path)
        $text = & $reviewText $review
        $text.Contains($path) -or (& $mentionsLeaf $text $path)
    }
    $namesDeliverable = {
        param($review, $path, $groupPaths)
        $text = & $reviewText $review
        if ($text.Contains($path)) { return $true }
        $leaf = & $leafOf $path
        $sameLeaf = @($groupPaths | Where-Object { (& $leafOf $_) -eq $leaf }).Count
        $sameLeaf -le 1 -and (& $mentionsLeaf $text $path)
    }
    $latestStatus = @{}
    $work = @($sorted | Where-Object { -not $_.IsReview -and $_.Deliverable })
    foreach ($w in $work) {
        $group = @($reviews | Where-Object { $_.Turn -and $_.Turn -eq $w.Turn -and $_.Workstream -eq $w.Workstream })
        $groupPaths = @($work | Where-Object { $_.Turn -eq $w.Turn -and $_.Workstream -eq $w.Workstream } | ForEach-Object { $_.Deliverable } | Select-Object -Unique)
        $naming = @($group | Where-Object { & $namesDeliverable $_ $w.Deliverable $groupPaths })
        $covering = if ($naming.Count -gt 0) { $naming | Select-Object -Last 1 }
        else {
            $r = $null
            foreach ($g in $group) { if (-not @($groupPaths | Where-Object { & $mentionsDeliverable $g $_ }).Count) { $r = $g } }
            $r
        }
        $status = if ($covering) { & $verdictOf $covering.Outcome } else { 'unknown' }
        $latestStatus[$w.Deliverable] = if ($status -eq 'unknown') { 'unreviewed' } else { $status }
    }

    $reworkEntries = @($sorted | Where-Object { $_.IsRework })
    $reworkDeliverables = @{}
    foreach ($r in $reworkEntries) { $reworkDeliverables[$r.Deliverable] = $true }
    $acceptedKeys = @($latestStatus.Keys | Where-Object { $latestStatus[$_] -eq 'accepted' })
    $accepted = $acceptedKeys.Count
    $reworkCredits = if ($CostBasis -eq 'exact-native') { $null } else {
        $value = 0.0
        foreach ($r in $reworkEntries) { $value += $r.Cost / 0.01 }
        $value
    }

    [ordered]@{
        deliverablesProduced         = $latestStatus.Count
        accepted                     = $accepted
        rejected                     = @($latestStatus.Keys | Where-Object { $latestStatus[$_] -eq 'rejected' }).Count
        unreviewed                   = @($latestStatus.Keys | Where-Object { $latestStatus[$_] -eq 'unreviewed' }).Count
        dispatches                   = $sorted.Count
        reworkDispatches             = $reworkEntries.Count
        firstPassYieldPct            = if ($accepted -gt 0) { @($acceptedKeys | Where-Object { -not $reworkDeliverables.ContainsKey($_) }).Count / $accepted * 100 } else { $null }
        costBasis                    = $CostBasis
        creditsPerAccepted           = if ($accepted -gt 0) { $TotalCredits / $accepted } else { $null }
        estCreditsPerAccepted        = if ($accepted -gt 0) { $TotalCredits / $accepted } else { $null }
        reworkCredits                = $reworkCredits
        reworkSharePct               = if ($null -ne $reworkCredits -and $TotalCredits -gt 0) { $reworkCredits / $TotalCredits * 100 } else { $null }
        orchestrationSharePct        = if ($TotalCredits -gt 0) { $OrchestrationCredits / $TotalCredits * 100 } else { $null }
        hostBilledCreditsPerAccepted = if ($null -ne $HostAiu) { if ($accepted -gt 0) { $HostAiu / $accepted } else { $null } } else { $null }
        hostBilledPresent            = ($null -ne $HostAiu)
    }
}

function Get-UnitEconomicsSectionLinesLocal {
    <#
    .SYNOPSIS
        Renders `## Unit Economics (value)`. Headers avoid `Turns`/`Basis`/
        `Model Source`/`Priced As`, which -Check uses to find the estimated tables.
    #>
    param([Parameter(Mandatory)]$Ue)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $count = { param($v) ([int]$v).ToString($inv) }
    $credits = { param($v) if ($null -eq $v) { 'n/a' } else { ([double]$v).ToString('N2', $inv) } }
    $pct = { param($v) if ($null -eq $v) { 'n/a' } else { ([double]$v).ToString('N1', $inv) + '%' } }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('## Unit Economics (value)')
    $lines.Add('')
    $lines.Add('| Measure | Value | Label |')
    $lines.Add('| ------- | ----- | ----- |')
    $lines.Add("| Deliverables produced | $(& $count $Ue.deliverablesProduced) | derived |")
    $lines.Add("| Accepted by an independent review | $(& $count $Ue.accepted) | derived |")
    $lines.Add("| Rejected | $(& $count $Ue.rejected) | derived |")
    $lines.Add("| Unreviewed | $(& $count $Ue.unreviewed) | derived |")
    $lines.Add("| Dispatches (excluding Scribe) | $(& $count $Ue.dispatches) | derived |")
    $lines.Add("| Rework dispatches | $(& $count $Ue.reworkDispatches) | derived |")
    $lines.Add("| First-pass yield | $(& $pct $Ue.firstPassYieldPct) | derived |")
    if ($Ue.costBasis -eq 'exact-native') {
        $lines.Add("| Exact credits per accepted deliverable | $(& $credits $Ue.creditsPerAccepted) | measured |")
        $lines.Add("| Rework share of exact credits | n/a | unavailable without per-history-run identity |")
        $lines.Add("| Orchestration share of exact credits | $(& $pct $Ue.orchestrationSharePct) | measured |")
    }
    else {
        $lines.Add("| Est. credits per accepted deliverable | $(& $credits $Ue.estCreditsPerAccepted) | estimated |")
        $lines.Add("| Rework share of est. credits | $(& $pct $Ue.reworkSharePct) | estimated |")
        $lines.Add("| Orchestration share of est. credits | $(& $pct $Ue.orchestrationSharePct) | estimated |")
    }
    if ($Ue.hostBilledPresent -and $Ue.costBasis -ne 'exact-native') {
        $lines.Add("| Host-billed credits per accepted deliverable | $(& $credits $Ue.hostBilledCreditsPerAccepted) | measured |")
    }
    $lines.Add('')
    $lines.Add('Value is counted only for deliverables an independent review-class verdict accepted; a produced but unaccepted deliverable adds cost and no value. A review that names deliverables covers only those it names. Rework counts a repeat of the same agent and deliverable path only: a fix by a different agent, to a different file, or with no deliverable path is not counted, so the rework figures are a floor. Compare runs only for like work, using medians of several runs. Source: FinOps Foundation unit-economics KPIs (cost per unit of value, error and retry waste).')
    $lines.Add('')
    return $lines.ToArray()
}

# ---------------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $SquadRoot -PathType Container)) {
    throw "Measure-SquadLedger: squad root not found at '$SquadRoot'."
}
$SquadRoot = (Resolve-Path -LiteralPath $SquadRoot).Path

# A hashtable literal cannot cross `pwsh -File`, so a string form is accepted too.
function ConvertTo-ExpectedHistoryCountsLocal {
    param($Value)
    $result = @{}
    if ($null -eq $Value) { return $result }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($k in $Value.Keys) { $result[[string]$k] = $Value[$k] }
        return $result
    }
    $text = ([string]$Value).Trim()
    if ($text -eq '') { throw "Measure-SquadLedger: -ExpectedHistoryCounts is blank. Pass a hashtable, 'Squad Implementor=2;Squad Scribe=1', or a JSON object string." }
    $pairs = [System.Collections.Generic.List[object]]::new()
    if ($text.StartsWith('{')) {
        # JsonDocument keeps duplicate keys, which ConvertFrom-Json would silently collapse.
        try {
            $doc = [System.Text.Json.JsonDocument]::Parse($text)
            if ($doc.RootElement.ValueKind -ne 'Object') { throw 'not a JSON object' }
            foreach ($prop in $doc.RootElement.EnumerateObject()) { $pairs.Add(@($prop.Name, $prop.Value.ToString())) }
        }
        catch { throw "Measure-SquadLedger: -ExpectedHistoryCounts JSON is not valid: $($_.Exception.Message)" }
    }
    else {
        $body = $text -replace '^@\{\s*', '' -replace '\s*\}$', ''
        foreach ($part in ($body -split '[;,]')) {
            if ($part.Trim() -eq '') { continue }
            $m = [regex]::Match($part, '^\s*[''"]?(?<k>[^=''"]+?)[''"]?\s*=\s*(?<v>\d+)\s*$')
            if (-not $m.Success) {
                throw "Measure-SquadLedger: -ExpectedHistoryCounts entry '$($part.Trim())' is not 'Agent Name=<count>'. Use a hashtable, 'Squad Implementor=2;Squad Scribe=1', or a JSON object string."
            }
            $pairs.Add(@($m.Groups['k'].Value.Trim(), [int]$m.Groups['v'].Value))
        }
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($p in $pairs) {
        $n = 0
        if (-not [int]::TryParse([string]$p[1], [ref]$n) -or $n -lt 0) {
            throw "Measure-SquadLedger: -ExpectedHistoryCounts count for '$($p[0])' must be a non-negative integer, got '$($p[1])'."
        }
        $key = [string]$p[0]
        $norm = ($key -replace '\.md$', '').ToLowerInvariant()
        if ($seen.Contains($norm)) { throw "Measure-SquadLedger: -ExpectedHistoryCounts names '$($key -replace '\.md$', '')' more than once." }
        [void]$seen.Add($norm)
        $result[$key] = $n
    }
    if ($result.Count -eq 0) { throw "Measure-SquadLedger: -ExpectedHistoryCounts '$text' contains no 'Agent Name=<count>' entries." }
    return $result
}
$ExpectedHistoryCounts = ConvertTo-ExpectedHistoryCountsLocal -Value $ExpectedHistoryCounts

if ($AdvanceUnmeteredHistory) {
    foreach ($incompatible in @('Check', 'Write', 'SessionLog', 'EmitBaseline', 'BaselinePath', 'ProtectedPath', 'AllowedWritePath', 'LookupRunId', 'LookupTopic', 'LookupStage', 'LookupSlot', 'BaselineModel')) {
        if ($PSBoundParameters.ContainsKey($incompatible)) {
            throw "Measure-SquadLedger: -AdvanceUnmeteredHistory cannot be combined with -$incompatible."
        }
    }
    if ($ExpectedHistoryCounts.Count -gt 0) {
        throw 'Measure-SquadLedger: -AdvanceUnmeteredHistory cannot be combined with -ExpectedHistoryCounts.'
    }
}

if ($Write) {
    if ($Check) {
        throw 'Measure-SquadLedger: -Write cannot be combined with -Check. Run -Write, then run -Check -ExpectedHistoryCounts separately as the self-check.'
    }
    if (@('LookupRunId', 'LookupTopic', 'LookupStage', 'LookupSlot' | Where-Object { $PSBoundParameters.ContainsKey($_) }).Count -gt 0) {
        throw 'Measure-SquadLedger: -Write cannot be combined with key-lookup mode.'
    }
    if (Test-Path -LiteralPath (Join-Path $SquadRoot 'federation.md') -PathType Leaf) {
        throw "Measure-SquadLedger: -Write does not apply to a federation root ('$SquadRoot'); federation totals aggregate member ledgers per the federation autopilot contract. Run it against a squad or sub-squad root."
    }
}

# ---------------------------------------------------------------------------
# Key-lookup mode (Amendment 3 §2 item 2): a self-contained early exit. All
# four -Lookup* parameters must be supplied together; no other mode's
# preconditions (consumption-rates.md, etc.) are required or checked.
# ---------------------------------------------------------------------------
$lookupParamNames = @('LookupRunId', 'LookupTopic', 'LookupStage', 'LookupSlot')
$suppliedLookupParamNames = @($lookupParamNames | Where-Object { $PSBoundParameters.ContainsKey($_) })
if ($suppliedLookupParamNames.Count -gt 0) {
    if ($suppliedLookupParamNames.Count -ne $lookupParamNames.Count) {
        $missing = @($lookupParamNames | Where-Object { $_ -notin $suppliedLookupParamNames })
        throw "Measure-SquadLedger: -LookupRunId, -LookupTopic, -LookupStage, and -LookupSlot must be supplied together for key-lookup mode; missing: $($missing -join ', ')."
    }
    $lookupExitCode = Invoke-SquadLedgerLookupLocal -SquadRoot $SquadRoot -RunId $LookupRunId -Topic $LookupTopic -Stage $LookupStage -Slot $LookupSlot -Format $Format
    exit $lookupExitCode
}

# ---------------------------------------------------------------------------
# -EmitBaseline / -BaselinePath / -ProtectedPath preconditions (Amendment 3 §2
# item 1): a baseline path must resolve entirely outside any
# `.copilot-tracking/squad` tree, and state.json/consumption.md/consumption-sessions.json can never be
# named as a protected artifact -- both checked before anything else runs.
# ---------------------------------------------------------------------------
if ($EmitBaseline -and (Test-PathUnderSquadTrackingLocal -Path $EmitBaseline)) {
    throw "Measure-SquadLedger: -EmitBaseline path '$EmitBaseline' resolves under a '.copilot-tracking/squad' tree; baselines must live outside the squad root entirely (use a session or temp path)."
}
if ($BaselinePath -and (Test-PathUnderSquadTrackingLocal -Path $BaselinePath)) {
    throw "Measure-SquadLedger: -BaselinePath path '$BaselinePath' resolves under a '.copilot-tracking/squad' tree; baselines must be read from outside the squad root entirely."
}
if ($ProtectedPath.Count -gt 0) { Assert-ProtectedPathNotReplaceSemanticsLocal -ProtectedPath $ProtectedPath }

# Loaded once here (regardless of -Check) because item 4's no-throw pricing
# fallback and item 3's malformed/illegal-model_source WARN-vs-FAIL scoping
# both need per-block legacy classification during aggregation, which happens
# whether or not -Check is present. Only -BaselinePath *combined with* -Check
# additionally runs the full append-only/protected verification below.
$loadedBaseline = $null
$baselineFileMissing = $false
if ($BaselinePath) {
    if (-not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
        $baselineFileMissing = $true
        if (-not $Check) {
            throw "Measure-SquadLedger: -BaselinePath '$BaselinePath' not found."
        }
    }
    else {
        $loadedBaseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
    }
}

$historyDir = Join-Path $SquadRoot 'history'
$historyFiles = @(
    if (Test-Path -LiteralPath $historyDir -PathType Container) {
        Get-ChildItem -LiteralPath $historyDir -Filter '*.md' -File | Sort-Object Name
    }
)

$teamPath = Join-Path $SquadRoot 'team.md'
$teamContent = if (Test-Path -LiteralPath $teamPath) { Get-Content -LiteralPath $teamPath -Raw } else { '' }
$roster = Get-RosterLocal -Content $teamContent
$projectRoot = [System.IO.Path]::GetFullPath($SquadRoot)
if ($projectRoot.Replace('\', '/') -match '^(?<base>.*?)/\.copilot-tracking(?:/|$)') { $projectRoot = $Matches['base'] }
$decisionsPath = Join-Path $SquadRoot 'decisions.md'
$decisionsContent = if (Test-Path -LiteralPath $decisionsPath) { Get-Content -LiteralPath $decisionsPath -Raw } else { '' }
$retirementModel = [pscustomobject]@{ Retirements = @(); Issues = @() }
$connectorIdentityIssues = @()
$activeConnectorBindings = @()
$connectorHistory = @($historyFiles | Where-Object BaseName -CEQ 'Squad Connector')
$hasConnectorHistory = $connectorHistory.Count -gt 0 -and
    [System.IO.File]::ReadAllText($connectorHistory[0].FullName) -match '(?m)^###[ \t]+\S'
if ($hasConnectorHistory -or $decisionsContent -match '(?m)^## Connector Binding Retirement') {
    . (Join-Path $PSScriptRoot 'Resolve-SquadConnectorHistory.ps1')
    $retirementModel = Get-SquadConnectorRetirementModel -Content $decisionsContent -TeamPath $teamPath -ProjectRoot $projectRoot
    $connectorIdentityIssues = @($retirementModel.Issues)
    if ($hasConnectorHistory) {
        $activeModel = Get-SquadConnectorBindingIdentityModel -TeamContent $teamContent -TeamPath $teamPath -ProjectRoot $projectRoot
        $activeConnectorBindings = @($activeModel.Bindings)
        $connectorIdentityIssues += @($activeModel.Issues)
    }
}

$ratesPath = Join-Path $SquadRoot 'consumption-rates.md'
if (-not (Test-Path -LiteralPath $ratesPath -PathType Leaf)) {
    throw "Measure-SquadLedger: '$ratesPath' not found. Seed it before running this script."
}
$ratesContent = Get-Content -LiteralPath $ratesPath -Raw
$rates = Get-RateTableLocal -Content $ratesContent
$calibrationFactor = Get-CalibrationFactorLocal -Content $ratesContent

# -EmitBaseline (Amendment 3 §2 item 1): computed as soon as history/roster/
# rates are known, so it reflects this run's on-disk state regardless of
# whatever -Check/-Format/-BaselinePath processing follows. Full pre-write
# copies (E3/A-4) go into a sibling `<name>.files/` directory next to the JSON.
if ($EmitBaseline) {
    $baselineToEmit = New-SquadLedgerBaselineLocal -SquadRoot $SquadRoot -HistoryFiles $historyFiles -ProtectedPath $ProtectedPath
    $emitBaselineFullPath = [System.IO.Path]::GetFullPath($EmitBaseline)
    $emitBaselineDir = Split-Path -Parent $emitBaselineFullPath
    if ($emitBaselineDir -and -not (Test-Path -LiteralPath $emitBaselineDir -PathType Container)) {
        New-Item -ItemType Directory -Path $emitBaselineDir -Force | Out-Null
    }
    $baselineToEmit | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $emitBaselineFullPath -NoNewline
    $filesRoot = "$emitBaselineFullPath.files"
    if (Test-Path -LiteralPath $filesRoot -PathType Container) { Remove-Item -LiteralPath $filesRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $filesRoot -Force | Out-Null
    Copy-BaselineSourceFilesLocal -SquadRoot $SquadRoot -HistoryFiles $historyFiles -ProtectedPath $ProtectedPath -DestinationRoot $filesRoot
    Write-Host "Measure-SquadLedger: baseline emitted to '$emitBaselineFullPath' ($($baselineToEmit.appendOnly.Count) append-only file(s), $($baselineToEmit.protected.Count) protected file(s)); pre-write copies under '$filesRoot'." -ForegroundColor Cyan
}

$warnings = [System.Collections.Generic.List[string]]::new()
$postBaselineBlockIssues = [System.Collections.Generic.List[string]]::new()
$attributionIssues = [System.Collections.Generic.List[string]]::new()
foreach ($issue in $connectorIdentityIssues) { $attributionIssues.Add("Connector identity: $issue") }
$historyCounts = @{}
$historyIdentitiesByFile = @{}
$meteredHistoryIdentitiesByFile = @{}
$enumerationLines = [System.Collections.Generic.List[string]]::new()


# role label -> aggregate; kept in a list alongside a sort key so unmapped agents
# and orchestration land in the documented order (roster order, unmapped next,
# orchestration last) rather than directory/hash order.
$ordered = [System.Collections.Generic.List[pscustomobject]]::new()
$orchestrationAggregate = $null
$unitEntries = [System.Collections.Generic.List[pscustomobject]]::new()
$exactHistoryEntries = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($file in $historyFiles) {
    $agentName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $content = Get-Content -LiteralPath $file.FullName -Raw

    $entryCount = Get-HistoryEntryCountLocal -Content $content
    $historyCounts[$agentName] = $entryCount

    $identities = @(Get-HistoryEntryIdentitiesLocal -Content $content)
    $historyIdentitiesByFile[$file.Name] = $identities
    $identityLabel = if ($identities.Count -gt 0) { $identities -join ',' } else { '(none)' }

    $blocks = @(Get-ConsumptionBlockLocal -Content $content -SourceName $file.Name)
    $allFileEntries = @(Get-HistoryEntryRecordsLocal -Content $content -AgentName $agentName)
    $fileEntries = if ($agentName -eq 'Squad Scribe') { @() } else { $allFileEntries }
    $meteredIdentities = [Collections.Generic.List[string]]::new()
    if ($agentName -ceq 'Squad Connector') {
        foreach ($entry in $fileEntries) {
            $requiredMetadata = [ordered]@{
                ExternalProvenance = 'External provenance'
                Verification = 'Verification'
                ExternalUnmeteredConnector = 'External-unmetered'
            }
            foreach ($field in $requiredMetadata.GetEnumerator()) {
                if ([string]::IsNullOrWhiteSpace([string]$entry.($field.Key))) {
                    $attributionIssues.Add("history/$($file.Name) entry '$($entry.Title)' is missing required connector metadata: $($field.Value).")
                }
            }
            if ($entry.MalformedExternalMarkers) {
                $attributionIssues.Add("history/$($file.Name) entry '$($entry.Title)' has malformed connector metadata; External provenance, Verification, and External-unmetered must use the literal '* ' bullet prefix.")
            }
        }
    }
    $enumerationLines.Add("$($file.Name) — $($blocks.Count) block(s) — identities: $identityLabel")

    foreach ($block in $blocks) {
        $isLegacyBlock = Test-LedgerBlockIsLegacyLocal -Baseline $loadedBaseline -HistoryFileName $file.Name -Ordinal $block.Ordinal

        # U1 baseline-scoped malformed/illegal-model_source rule (Amendment 3 §2
        # item 3): a block that fails to parse, has the wrong field order/set,
        # carries a non-numeric numeric-typed field, or whose model_source is
        # outside the legal set, is excluded from aggregation either way -- the
        # only question is whether it WARNs (pre-baseline/legacy, or no
        # baseline supplied at all -- "cannot scope") or becomes a reportable
        # issue (post-baseline: a -Check FAIL, or -- outside -Check -- the
        # same terminating throw this script has always used for new bad data).
        $issue = $null
        if ($block.ParseError) {
            $issue = "$($block.Source): JSON parse error: $($block.ParseError)"
        }
        elseif (-not $block.OrderOk) {
            $issue = "$($block.Source): field order/set does not match the contractual ten fields (got: $($block.Order -join ', '))"
        }
        elseif ($block.NonNumeric.Count -gt 0) {
            $issue = "$($block.Source): non-numeric value in field(s): $($block.NonNumeric -join ', ')"
        }
        elseif ([string]$block.Fields['model_source'] -notin $script:LegalModelSources) {
            $issue = "$($block.Source): consumption block $($block.Ordinal) has illegal model_source '$($block.Fields['model_source'])' (legal values: $($script:LegalModelSources -join ', '))."
        }

        if ($issue) {
            if ($isLegacyBlock) {
                $warnings.Add("WARN: $issue (pre-baseline/legacy block, or no baseline supplied; not scoped for FAIL).")
            }
            else {
                $postBaselineBlockIssues.Add($issue)
            }
            continue
        }

        if ($block.CollapsedFence) {
            $warnings.Add("WARN: $($block.Source): consumption block $($block.Ordinal) has a collapsed code fence (fewer than three backticks, the mark of a write through a PowerShell double-quoted string); its JSON is intact, so it is counted. Leave the entry as it is -- never edit it in place -- and write future entries with the file edit or create tool.")
        }

        $meteredEntry = @($allFileEntries | Where-Object { $block.Offset -ge $_.Start -and $block.Offset -lt $_.End } | Select-Object -First 1)
        if ($meteredEntry.Count -eq 1 -and $meteredEntry[0].Identity -notin $meteredIdentities) {
            $meteredEntry[0].HasConsumption = $true
            $meteredIdentities.Add([string]$meteredEntry[0].Identity)
        }

        if ($agentName -eq 'Squad Scribe') {
            if (-not $orchestrationAggregate) {
                $orchestrationAggregate = New-RoleAggregateLocal -Label 'orchestration'
                # Orchestration has no team.md roster row (it is the coordinator's own
                # turns plus every Scribe write, not a dispatched role), so its Member/
                # Agent/Tier are the fixed template convention from consumption.md's
                # own `<coord+scribe>` / `mixed` placeholders, never a roster lookup.
                # Default to "Squad Scribe"; after consumption.md is loaded, a
                # compatibility pass may switch this to the historical
                # `Coordinator+Scribe` label when that is what the current ledger
                # already records.
                $orchestrationAggregate.Agent = 'Squad Scribe'
                $orchestrationAggregate.Tier = 'mixed'
            }
            Add-BlockToAggregateLocal -Aggregate $orchestrationAggregate -Block $block -Rates $rates -CalibrationFactor $calibrationFactor -Warnings $warnings -TreatUnresolvedRateAsWarning $isLegacyBlock
            continue
        }

        $entryForBlock = @($fileEntries | Where-Object { $block.Offset -ge $_.Start -and $block.Offset -lt $_.End } | Select-Object -First 1)
        $memberForBlock = if ($entryForBlock.Count -eq 1) { [string]$entryForBlock[0].MemberName } else { '' }
        $extProvForBlock = if ($entryForBlock.Count -eq 1) { [string]$entryForBlock[0].ExternalProvenance } else { '' }
        $resolved = Resolve-RoleForAgentLocal -AgentName $agentName -MemberName $memberForBlock -Roster $roster -ExternalProvenance $extProvForBlock `
            -EntryTitle $(if ($entryForBlock) { $entryForBlock[0].Title } else { '' }) `
            -Verification $(if ($entryForBlock) { $entryForBlock[0].Verification } else { '' }) `
            -ExternalUnmeteredConnector $(if ($entryForBlock) { $entryForBlock[0].ExternalUnmeteredConnector } else { '' }) `
            -ActiveConnectorBindings $activeConnectorBindings -RetiredConnectorBindings $retirementModel.Retirements
        if ($resolved.Status -notin @('ok', 'unmapped')) {
            $problem = "history/$($file.Name) consumption block $($block.Ordinal) cannot be attributed for agent '$agentName'$(if ($memberForBlock) { ", member '$memberForBlock'" } else { '' }) (status: $($resolved.Status))."
            $warnings.Add("WARN: $problem")
            $attributionIssues.Add($problem)
            continue
        }

        $existing = $ordered | Where-Object { $_.AggregateKey -eq $resolved.AggregateKey } | Select-Object -First 1
        if (-not $existing) {
            $aggregate = New-RoleAggregateLocal -Label $resolved.Role
            if ($null -ne $resolved.Index) {
                $aggregate.Member = $resolved.MemberName
                $aggregate.Tier = $resolved.Tier
            }
            # Agent always names the agent actually dispatched -- this history
            # file's own agent name -- never merely the role's roster-declared
            # Primary. A role with both a Primary and a Fallback (e.g. team.md's
            # `architect` row: Primary `System Architecture Reviewer`, Fallback
            # `ADR Creator`) produces one aggregate per distinct history file
            # (see the AgentName-keyed lookup above), so a Fallback dispatch must
            # print its own name here, not be misattributed to that role's
            # Primary. An unmapped agent (no roster row at all) prints the same
            # file name it would anyway, so this assignment is correct for both
            # branches without needing a separate unmapped-agent case.
            $aggregate.Agent = $agentName
            $existing = [pscustomobject]@{
                AggregateKey = $resolved.AggregateKey
                AgentName    = $agentName
                SortIndex    = if ($null -ne $resolved.Index) { $resolved.Index } else { [int]::MaxValue }
                Aggregate    = $aggregate
            }
            $ordered.Add($existing)
        }
        Add-BlockToAggregateLocal -Aggregate $existing.Aggregate -Block $block -Rates $rates -CalibrationFactor $calibrationFactor -Warnings $warnings -TreatUnresolvedRateAsWarning $isLegacyBlock
        Add-BlockCostToEntryLocal -Entries $fileEntries -Offset $block.Offset -Cost $existing.Aggregate.Blocks[-1].Cost
    }
    $meteredHistoryIdentitiesByFile[$file.Name] = $meteredIdentities.ToArray()
    foreach ($entryRecord in $allFileEntries) { $exactHistoryEntries.Add($entryRecord) }
    foreach ($entryRecord in $fileEntries) { $entryRecord.Seq = $unitEntries.Count; $unitEntries.Add($entryRecord) }
}

# Post-baseline malformed/illegal-model_source blocks (item 3): outside -Check
# this keeps the script's original behaviour of terminating on new bad data
# (a post-baseline block is never legacy, so "keep current behaviour" applies
# to it unchanged); under -Check the caller wants a full mismatch report
# instead of an early exit, so these are surfaced as FAILs there (seeded into
# $mismatches below) rather than thrown.
if ($postBaselineBlockIssues.Count -gt 0 -and -not $Check) {
    foreach ($e in $postBaselineBlockIssues) { Write-Warning $e }
    throw "Measure-SquadLedger: $($postBaselineBlockIssues.Count) post-baseline consumption block(s) failed to parse or validate; see warnings above. Refusing to compute a ledger from unreadable blocks."
}
if ($attributionIssues.Count -gt 0 -and -not $Check) {
    foreach ($issue in $attributionIssues) { Write-Warning $issue }
    throw "Measure-SquadLedger: $($attributionIssues.Count) history entry(ies) could not be attributed to a unique roster identity. Add Member Name to shared-agent entries (especially Squad Connector) and rerun."
}

$roleAggregates = @($ordered | Sort-Object SortIndex, AgentName | ForEach-Object { $_.Aggregate })
if ($orchestrationAggregate) { $roleAggregates += $orchestrationAggregate }

$totalTurns = 0.0
$totalInput = 0.0
$totalCached = 0.0
$totalCacheWrite = 0.0
$totalOutput = 0.0
$totalCost = 0.0
foreach ($agg in $roleAggregates) {
    $totalTurns += $agg.Turns
    $totalInput += $agg.Input
    $totalCached += $agg.Cached
    $totalCacheWrite += $agg.CacheWrite
    $totalOutput += $agg.Output
    $totalCost += $agg.Cost
}
$totalCredits = $totalCost / 0.01

$statePath = Join-Path $SquadRoot 'state.json'
$stateCostUsd = $null
$stateCreditsTotal = $null
$stateReadError = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        if ($state.ContainsKey('currentRun')) {
            $stateCostUsd = $state['currentRun']['estCostUsd']
            $stateCreditsTotal = $state['currentRun']['estCreditsTotal']
        }
        else {
            $stateReadError = "state.json at '$statePath' has no 'currentRun' key."
        }
    }
    catch { $stateReadError = "state.json at '$statePath' failed to parse: $($_.Exception.Message)" }
}
else {
    $stateReadError = "state.json not found at '$statePath'."
}
if ($stateReadError) { $warnings.Add("WARN: $stateReadError") }

# federation.md marks a federation root, whose own run-level state.json has no
# single currentRun to reconcile the ledger against (a federation root
# aggregates its members' own runs instead) -- see the C3 divergence check below.
$isFederationRoot = Test-Path -LiteralPath (Join-Path $SquadRoot 'federation.md') -PathType Leaf

# ---------------------------------------------------------------------------
# C2 history-identity guard: read back whatever consumption.md already records
# (in either mode -- render or -Check -- so a render never silently papers over
# an identity divergence -Check would also have caught) before anything below
# reads or rewrites it.
# ---------------------------------------------------------------------------

$consumptionPath = Join-Path $SquadRoot 'consumption.md'
$sessionCachePath = Join-Path $SquadRoot 'consumption-sessions.json'
$existingConsumptionContent = $null
$identityGuardResult = $null
# Post-write mode is the Scribe's own self-check shape: -Check combined with
# -ExpectedHistoryCounts always follows an actual write (see
# references/scribe-procedure.md's Self-Check step), so a Derivation missing
# identities there is this run's own bad paste, never a pre-existing legacy
# ledger -- it must fail rather than only warn. Any other combination (no
# -Check, or -Check alone) keeps the warn-only legacy behavior.
$postWriteIdentityCheck = [bool]($Check -and $ExpectedHistoryCounts.Count -gt 0)
if (Test-Path -LiteralPath $consumptionPath -PathType Leaf) {
    $existingConsumptionContent = Get-Content -LiteralPath $consumptionPath -Raw
    $identityGuardResult = Test-HistoryIdentityGuardLocal -ConsumptionContent $existingConsumptionContent -CurrentIdentitiesByFile $historyIdentitiesByFile -PostWrite:$postWriteIdentityCheck
}
if ($orchestrationAggregate) {
    $orchestrationAggregate.Agent = Resolve-OrchestrationAgentLabelLocal -ConsumptionContent $existingConsumptionContent -DefaultLabel $orchestrationAggregate.Agent
}

if (-not $Check -and $identityGuardResult) {
    foreach ($w in $identityGuardResult.Warnings) { $warnings.Add("WARN: $w") }
    if ($identityGuardResult.Failures.Count -gt 0) {
        foreach ($f in $identityGuardResult.Failures) { Write-Warning $f }
        throw "Measure-SquadLedger: refusing to render a ledger fragment while consumption.md's existing history-identity guard record fails ($($identityGuardResult.Failures.Count) failure(s); see warnings above). An entry was overwritten or removed rather than only appended to -- resolve history/ (or the stale consumption.md record) before rerunning."
    }
}

# ---------------------------------------------------------------------------
# -Check: compare against the squad root's own consumption.md, write nothing.
# ---------------------------------------------------------------------------

$initializationOnly = @($historyFiles | Where-Object { $_.Name -ne 'Squad Scribe.md' }).Count -eq 0
$initializationComparison = 'n/a (initialization). Setup spend is recorded above using the ledger basis; the first comparison follows the first work dispatch.'

if ($AdvanceUnmeteredHistory) {
    if (-not (Test-Path -LiteralPath $sessionCachePath -PathType Leaf)) {
        throw 'Measure-SquadLedger: -AdvanceUnmeteredHistory requires consumption-sessions.json.'
    }
    $cacheSessions = @(Read-ExactSessionCacheLocal -Path $sessionCachePath)
    if ($cacheSessions.Count -eq 0) {
        throw 'Measure-SquadLedger: -AdvanceUnmeteredHistory requires at least one accepted exact-session snapshot.'
    }
    $migrationCount = @(
        $cacheSessions | Where-Object {
            $_.PSObject.Properties['cacheMigrationRequired'] -and $_.cacheMigrationRequired
        }
    ).Count
    $coveragePlan = Get-ExactCoveragePlanLocal -Sessions $cacheSessions `
        -CurrentSessionId '__advance-unmetered-history__' -CurrentHistoryCoverage $historyIdentitiesByFile
    $newHistoryCount = [int]((
            $coveragePlan.CurrentCoverage.Values |
                ForEach-Object { @($_).Count } |
                Measure-Object -Sum
        ).Sum)
    if ($newHistoryCount -gt 0) {
        $expected = Get-ExpectedNativeCoverageLocal -HistoryCoverage $coveragePlan.CurrentCoverage `
            -MeteredHistoryCoverage $meteredHistoryIdentitiesByFile `
            -MeteredAgents @($ordered | ForEach-Object AgentName) -HistoryEntries @($exactHistoryEntries)
        if ([int]$expected.MeteredEntryCount -ne 0) {
            throw 'Measure-SquadLedger: -AdvanceUnmeteredHistory refuses consumption-backed history; use an ordinary exact ledger write.'
        }
        $lastIndex = $cacheSessions.Count - 1
        $cacheSessions[$lastIndex].historyCoverage = Join-HistoryCoverageLocal `
            -Left $cacheSessions[$lastIndex].historyCoverage -Right $coveragePlan.CurrentCoverage
    }
    $cumulativeCoverage = Get-CumulativeHistoryCoverageLocal -Sessions $cacheSessions
    $null = Test-HistoryCoveragePrefixLocal -Recorded $cumulativeCoverage -Current $historyIdentitiesByFile -RequireComplete
    $validatedExact = Merge-ExactSessionUsageLocal -Sessions $cacheSessions -Rates $rates -Roster $roster `
        -BaselineModel '' -ActiveSession $null -Warnings $warnings
    if (-not $validatedExact) {
        throw 'Measure-SquadLedger: -AdvanceUnmeteredHistory could not validate the cumulative exact-session totals.'
    }

    $text = ConvertTo-ExactSessionCacheDocumentLocal -Sessions $cacheSessions
    $tmp = Join-Path (Split-Path -Parent $sessionCachePath) (".$([IO.Path]::GetFileName($sessionCachePath)).$([guid]::NewGuid().ToString('N')).tmp")
    try {
        [IO.File]::WriteAllText($tmp, $text, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($tmp, $sessionCachePath, $true)
    }
    catch {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        throw "Measure-SquadLedger: -AdvanceUnmeteredHistory could not rewrite consumption-sessions.json: $($_.Exception.Message)"
    }
    [ordered]@{
        status = 'advanced-unmetered-history'
        historyEntries = $newHistoryCount
        sessions = $cacheSessions.Count
        migratedSnapshots = $migrationCount
        records = [long]$validatedExact.SnapshotRecords
        credits = [double]($validatedExact.TotalNanoAiu / [decimal]1e9)
    } | ConvertTo-Json -Compress
    exit 0
}

if ($Check) {
    $mismatches = [System.Collections.Generic.List[string]]::new()
    $infoLines = [System.Collections.Generic.List[string]]::new()
    $hasExactLedger = [bool]($existingConsumptionContent -and $existingConsumptionContent -match '(?m)^\| Role \| Requests \| In Tokens \| Cached \| Cache Wr \| Out Tokens \| Exact Cost \(USD\) \| Exact Credits \| Basis \|')
    if ($initializationOnly -and $existingConsumptionContent -notmatch ('(?m)^## Cost Comparison \(illustrative\)\r?\n\r?\n' + [regex]::Escape($initializationComparison) + '\r?$')) {
        $mismatches.Add('Initialization Cost Comparison is missing or changed; run -Write to derive it without a fictional baseline.')
    }
    elseif (-not $initializationOnly -and $hasExactLedger -and $existingConsumptionContent -notmatch '(?m)^## Cost Comparison \(exact native actual\)\s*$') {
        $mismatches.Add('Exact native ledger is missing its exact Cost Comparison section; run -Write to restore it.')
    }
    elseif (-not $initializationOnly -and -not $hasExactLedger -and -not $isFederationRoot -and $existingConsumptionContent) {
        $comparison = Get-CostComparisonUpdateLocal -Text $existingConsumptionContent -CostUsd $totalCost -Credits $totalCredits -AgentCount (@($roleAggregates | Where-Object Label -ne 'orchestration').Count)
        foreach ($issue in $comparison.Issues) { $mismatches.Add($issue) }
    }

    # Post-baseline malformed/illegal-model_source blocks (item 3): under -Check
    # these are reported as FAILs rather than thrown (see the non--Check throw
    # gate above, right after the per-file loop).
    foreach ($e in $postBaselineBlockIssues) { $mismatches.Add("Post-baseline block: $e") }
    foreach ($e in $attributionIssues) { $mismatches.Add("Attribution identity: $e") }

    # -BaselinePath append-only/protected-artifact verification (Amendment 3 §2
    # item 1), only meaningful paired with -Check: shrink, prefix-hash mismatch,
    # protected-hash mismatch (unless in the allowed write set), and a missing
    # baseline file are all FAILs here; state.json/consumption.md/
    # consumption-sessions.json rewrites are explicitly not checked by this helper
    # (they are expected to change and are covered by C3 and the structural checks below instead).
    if ($BaselinePath) {
        if ($baselineFileMissing) {
            $mismatches.Add("Baseline file '$BaselinePath' not found.")
        }
        else {
            $baselineFailures = @(Test-SquadLedgerBaselineLocal -SquadRoot $SquadRoot -Baseline $loadedBaseline -HistoryFiles $historyFiles -ProtectedPath $ProtectedPath -AllowedWritePath $AllowedWritePath -BaselineFilesRoot "$([System.IO.Path]::GetFullPath($BaselinePath)).files")
            foreach ($f in $baselineFailures) { $mismatches.Add("Baseline: $f") }
        }
    }

    if (-not (Test-Path -LiteralPath $consumptionPath -PathType Leaf)) {
        $mismatches.Add("consumption.md not found at '$consumptionPath'.")
    }
    else {
        $consumptionContent = $existingConsumptionContent

        # Structural checks: numbers can reconcile on a ledger that lost its own
        # shape (the observed failure pasted the helper's console output -- heading,
        # table, and helper-only diagnostics -- as the *whole* consumption.md, which
        # still carried a correct-looking Total row). Each check below names the
        # missing or leaked element so the mismatch is directly actionable.
        if ($consumptionContent -notmatch '(?m)^#\s+Squad Consumption Ledger') {
            $mismatches.Add("consumption.md is missing its H1 heading (expected a line matching '# Squad Consumption Ledger ...').")
        }
        if ($consumptionContent -notmatch '(?m)^##\s+Attribution\s*$') {
            $mismatches.Add("consumption.md is missing its '## Attribution' heading.")
        }
        # `\s*$` (not `[ \t]*$`) tolerates a trailing `\r` before .NET's multiline `$`
        # under CRLF line endings -- see the CRLF note on Get-ConsumptionBlockLocal's
        # own pattern above for why a bare `[ \t]*$` silently fails here instead.
        if ($consumptionContent -notmatch '(?m)^##\s+Usage & Cost\s*$') {
            $mismatches.Add("consumption.md is missing its '## Usage & Cost' heading (exact text, no path decoration).")
        }
        if ($consumptionContent -notmatch '(?m)^###\s+Derivation\s*$') {
            $mismatches.Add("consumption.md is missing its '### Derivation' heading.")
        }
        if ($consumptionContent -match 'derived from history/ at') {
            $mismatches.Add("consumption.md leaks the helper's own diagnostic heading ('...derived from history/ at <path>...'); paste only the '## Usage & Cost' table and '### Derivation' block, never the helper's console decoration.")
        }
        if ($consumptionContent -match '(?m)^state\.json currentRun\.') {
            $mismatches.Add("consumption.md leaks a helper diagnostic line ('state.json currentRun....'); this belongs only in the helper's own console output, never in the ledger file.")
        }

        # R-LEDGER-ATTRIBUTION: compare the ledger's own '## Attribution' table
        # (Model, Model Source, Priced As per role) against the same consumption
        # blocks the Usage & Cost table already derives from. Nothing before this
        # check compared Attribution to a block, so a hand-rewritten table could
        # invent a Model or leak a Priced As name into the Model column and still
        # pass. Member/Agent/Tier are roster-sourced (team.md), not block-derived,
        # so they are intentionally not compared here -- validating them would only
        # re-check team.md against itself, not the block-honesty contract this
        # check exists to enforce.
        # Reuses the same script-scope list item 3's post-baseline model_source
        # check validates against, so a value legal in history/ is legal here too.
        $legalModelSources = $script:LegalModelSources

        $attributionTable = @(Get-MarkdownTableLocal -Content $consumptionContent | Where-Object { 'Model Source' -in $_.Header -and 'Priced As' -in $_.Header })
        if ($attributionTable.Count -eq 0) {
            $mismatches.Add("No '## Attribution' table with the contractual 'Model Source' and 'Priced As' columns found in consumption.md.")
        }
        else {
            # Member-aware disambiguation: connector activity can share one
            # history file (`Squad Connector`) while representing distinct
            # roster rows. Match Attribution rows by (Role, Member, Agent), not
            # Role alone.
            $ledgerRowsByComposite = @{}
            foreach ($row in $attributionTable[0].Rows) {
                $roleText = ([string]$row['Role']).Trim()
                if (-not $roleText) { continue }
                $memberText = ([string]$row['Member']).Trim()
                $agentText = ([string]$row['Agent']).Trim()
                $compositeKey = Get-AttributionCompositeKeyLocal -Role $roleText -Member $memberText -Agent $agentText
                if ($ledgerRowsByComposite.ContainsKey($compositeKey)) {
                    $memberSuffix = if ($memberText) { " (member '$memberText')" } else { '' }
                    $mismatches.Add("Attribution: consumption.md has more than one row for role '$roleText' agent '$agentText'$memberSuffix.")
                    continue
                }
                $ledgerRowsByComposite[$compositeKey] = [pscustomobject]@{ Role = $roleText; Member = $memberText; Agent = $agentText; Row = $row; CompositeKey = $compositeKey }
            }

            if ($hasExactLedger) {
                foreach ($entry in $ledgerRowsByComposite.Values) {
                    if ([string]::IsNullOrWhiteSpace([string]$entry.Row['Model'])) {
                        $mismatches.Add("Attribution: exact row for role '$($entry.Role)' agent '$($entry.Agent)' has no host model.")
                    }
                    if (([string]$entry.Row['Model Source']).Trim() -cne 'host-reported') {
                        $mismatches.Add("Attribution: exact row for role '$($entry.Role)' agent '$($entry.Agent)' must use Model Source 'host-reported'.")
                    }
                    if (([string]$entry.Row['Priced As']).Trim() -cne 'native credits') {
                        $mismatches.Add("Attribution: exact row for role '$($entry.Role)' agent '$($entry.Agent)' must use Priced As 'native credits'.")
                    }
                }
            }
            else {
                $consumedLedgerComposites = @{}
                foreach ($agg in $roleAggregates) {
                    $agentLabel = ([string]$agg.Agent).Trim()
                    $memberLabel = ([string]$agg.Member).Trim()
                    $memberSuffix = if ($memberLabel) { " (member '$memberLabel')" } else { '' }
                    $compositeKey = Get-AttributionCompositeKeyLocal -Role $agg.Label -Member $memberLabel -Agent $agentLabel
                    $matchEntry = if ($ledgerRowsByComposite.ContainsKey($compositeKey)) { $ledgerRowsByComposite[$compositeKey] } else { $null }
                    if (-not $matchEntry) {
                        $mismatches.Add("Attribution: consumption.md is missing a row for role '$($agg.Label)' agent '$agentLabel'$memberSuffix.")
                        continue
                    }
                    $consumedLedgerComposites[$matchEntry.CompositeKey] = $true
                    $ledgerRow = $matchEntry.Row

                    foreach ($column in @(
                            @{ Name = 'Model'; Expected = $agg.Models },
                            @{ Name = 'Model Source'; Expected = $agg.ModelSources },
                            @{ Name = 'Priced As'; Expected = $agg.PricedAsUsed }
                        )) {
                        $actualCells = @(([string]$ledgerRow[$column.Name] -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                        $expectedCells = @($column.Expected | ForEach-Object { $_.Trim() })
                        $setDiff = @(Compare-Object -ReferenceObject $expectedCells -DifferenceObject $actualCells -SyncWindow 0)
                        if ($setDiff.Count -gt 0) {
                            $mismatches.Add("Attribution: role '$($agg.Label)' agent '$agentLabel' column '$($column.Name)'${memberSuffix}: consumption.md says '$($ledgerRow[$column.Name])', derived from history/ is '$($expectedCells -join ', ')'.")
                        }
                    }

                    foreach ($sourceValue in (([string]$ledgerRow['Model Source'] -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                        if ($sourceValue -notin $legalModelSources) {
                            $mismatches.Add("Attribution: role '$($agg.Label)' agent '$agentLabel' column 'Model Source' has illegal value '$sourceValue'$memberSuffix (legal values: $($legalModelSources -join ', ')).")
                        }
                    }
                }

                foreach ($entry in $ledgerRowsByComposite.Values) {
                    if (-not $consumedLedgerComposites.ContainsKey($entry.CompositeKey)) {
                        $memberSuffix = if ($entry.Member) { " (member '$($entry.Member)')" } else { '' }
                        $mismatches.Add("Attribution: consumption.md has an extra row for role '$($entry.Role)' agent '$($entry.Agent)'$memberSuffix with no matching consumption block in history/.")
                    }
                }
            }
        }

        $usageTable = @(Get-MarkdownTableLocal -Content $consumptionContent | Where-Object { ('Turns' -in $_.Header -or 'Requests' -in $_.Header) -and 'Basis' -in $_.Header })
        $totalRow = $null
        foreach ($table in $usageTable) {
            $hit = $table.Rows | Where-Object { $_[$table.Header[0]] -match 'Total' } | Select-Object -First 1
            if ($hit) { $totalRow = $hit; break }
        }

        if (-not $totalRow) {
            $mismatches.Add('No Total row found in consumption.md Usage & Cost table.')
        }
        elseif ($hasExactLedger) {
            $exactTable = @($usageTable | Where-Object { 'Requests' -in $_.Header } | Select-Object -First 1)
            $detailRows = @($exactTable[0].Rows | Where-Object { $_[$exactTable[0].Header[0]] -notmatch 'Total' })
            $expectedRequests = [double](($detailRows | ForEach-Object { ConvertTo-LedgerNumberLocal $_['Requests'] } | Measure-Object -Sum).Sum)
            $expectedIn = [double](($detailRows | ForEach-Object { ConvertTo-LedgerNumberLocal $_['In Tokens'] } | Measure-Object -Sum).Sum)
            $expectedCached = [double](($detailRows | ForEach-Object { ConvertTo-LedgerNumberLocal $_['Cached'] } | Measure-Object -Sum).Sum)
            $expectedCacheWr = [double](($detailRows | ForEach-Object { ConvertTo-LedgerNumberLocal $_['Cache Wr'] } | Measure-Object -Sum).Sum)
            $expectedOut = [double](($detailRows | ForEach-Object { ConvertTo-LedgerNumberLocal $_['Out Tokens'] } | Measure-Object -Sum).Sum)
            $expectedCost = [double](($detailRows | ForEach-Object { ConvertTo-LedgerNumberLocal $_['Exact Cost (USD)'] } | Measure-Object -Sum).Sum)
            $expectedCredits = [double](($detailRows | ForEach-Object { ConvertTo-LedgerNumberLocal $_['Exact Credits'] } | Measure-Object -Sum).Sum)

            foreach ($row in $detailRows) {
                if (([string]$row['Basis']).Trim('*', ' ') -cne 'exact-native') {
                    $mismatches.Add("Exact Usage & Cost row '$($row['Role'])' does not use basis exact-native.")
                }
            }

            $actualRequests = ConvertTo-LedgerNumberLocal $totalRow['Requests']
            $actualIn = ConvertTo-LedgerNumberLocal $totalRow['In Tokens']
            $actualCached = ConvertTo-LedgerNumberLocal $totalRow['Cached']
            $actualCacheWr = ConvertTo-LedgerNumberLocal $totalRow['Cache Wr']
            $actualOut = ConvertTo-LedgerNumberLocal $totalRow['Out Tokens']
            $actualCost = ConvertTo-LedgerNumberLocal $totalRow['Exact Cost (USD)']
            $actualCredits = ConvertTo-LedgerNumberLocal $totalRow['Exact Credits']

            foreach ($metricCheck in @(
                    @{ Name = 'Requests'; Actual = $actualRequests; Expected = $expectedRequests; Tolerance = 0.0 },
                    @{ Name = 'In Tokens'; Actual = $actualIn; Expected = $expectedIn; Tolerance = 0.0 },
                    @{ Name = 'Cached'; Actual = $actualCached; Expected = $expectedCached; Tolerance = 0.0 },
                    @{ Name = 'Cache Wr'; Actual = $actualCacheWr; Expected = $expectedCacheWr; Tolerance = 0.0 },
                    @{ Name = 'Out Tokens'; Actual = $actualOut; Expected = $expectedOut; Tolerance = 0.0 },
                    @{ Name = 'Exact Cost (USD)'; Actual = $actualCost; Expected = $expectedCost; Tolerance = [math]::Max(0.0001, $detailRows.Count * 0.00005) },
                    @{ Name = 'Exact Credits'; Actual = $actualCredits; Expected = $expectedCredits; Tolerance = [math]::Max(0.01, $detailRows.Count * 0.005) }
                )) {
                if ($null -eq $metricCheck.Actual -or [math]::Abs([double]$metricCheck.Actual - [double]$metricCheck.Expected) -gt [double]$metricCheck.Tolerance) {
                    $mismatches.Add("$($metricCheck.Name): exact Total row says $($metricCheck.Actual), sum of exact role rows is $($metricCheck.Expected).")
                }
            }
            if (([string]$totalRow['Basis']).Trim('*', ' ') -cne 'exact-native') {
                $mismatches.Add('Exact Usage & Cost Total row does not use basis exact-native.')
            }
            $singleSnapshotLine = [regex]::Match($consumptionContent, '(?m)^Native usage snapshot — session: (?<session>[^;]+); records: (?<records>\d+); through: (?<through>[^;]+); digest: (?<digest>[A-F0-9]{64})\s*$')
            $multiSnapshotLine = [regex]::Match($consumptionContent, '(?m)^Native usage snapshots — sessions: (?<sessions>\d+); records: (?<records>\d+); through: (?<through>[^;]+); digest: (?<digest>[A-F0-9]{64})\s*$')
            $snapshotLine = if ($singleSnapshotLine.Success) { $singleSnapshotLine } else { $multiSnapshotLine }
            if (-not $snapshotLine.Success) {
                $mismatches.Add('Exact Derivation is missing its native session snapshot count, record count, timestamp, or SHA-256 digest.')
            }
            elseif ([int]$snapshotLine.Groups['records'].Value -ne [int]$actualRequests) {
                $mismatches.Add('Exact Derivation native record count differs from the Usage & Cost Total requests.')
            }
            if (Test-Path -LiteralPath $sessionCachePath -PathType Leaf) {
                try {
                    $checkedSessions = @(Read-ExactSessionCacheLocal -Path $sessionCachePath)
                    $checkedCoverage = Get-CumulativeHistoryCoverageLocal -Sessions $checkedSessions
                    $null = Test-HistoryCoveragePrefixLocal -Recorded $checkedCoverage -Current $historyIdentitiesByFile -RequireComplete
                    $checkedExact = Merge-ExactSessionUsageLocal -Sessions $checkedSessions -Rates $rates -Roster $roster `
                        -BaselineModel '' -ActiveSession $null -Warnings $warnings
                    if ([int]$checkedExact.SnapshotRecords -ne [int]$actualRequests) {
                        $mismatches.Add('consumption-sessions.json record total differs from the exact Usage & Cost Total requests.')
                    }
                    if ($snapshotLine.Success -and [string]$checkedExact.SnapshotDigest -cne [string]$snapshotLine.Groups['digest'].Value) {
                        $mismatches.Add('consumption-sessions.json cumulative digest differs from the Exact Derivation digest.')
                    }
                    $declaredSessionCount = if ($multiSnapshotLine.Success) { [int]$multiSnapshotLine.Groups['sessions'].Value } else { 1 }
                    if ([int]$checkedExact.SessionCount -ne $declaredSessionCount) {
                        $mismatches.Add('consumption-sessions.json session count differs from the Exact Derivation session count.')
                    }
                }
                catch {
                    $mismatches.Add("consumption-sessions.json failed exact-ledger validation: $($_.Exception.Message)")
                }
            }

            $totalTurns = $expectedRequests
            $totalInput = $expectedIn
            $totalCached = $expectedCached
            $totalCacheWrite = $expectedCacheWr
            $totalOutput = $expectedOut
            $totalCost = if ($null -ne $actualCost) { [double]$actualCost } else { $expectedCost }
            $totalCredits = if ($null -ne $actualCredits) { [double]$actualCredits } else { $expectedCredits }

            $comparisonTables = @(Get-MarkdownTableLocal -Content $consumptionContent | Where-Object { 'Scenario' -in $_.Header -and 'AI Credits' -in $_.Header -and 'USD' -in $_.Header })
            $actualComparison = @($comparisonTables | ForEach-Object Rows | Where-Object { ([string]$_['Scenario']).StartsWith('With HVE Squad') } | Select-Object -First 1)
            if ($actualComparison.Count -ne 1) {
                $mismatches.Add('Exact Cost Comparison has no unique With HVE Squad row.')
            }
            else {
                $comparisonCredits = ConvertTo-LedgerNumberLocal $actualComparison[0]['AI Credits']
                $comparisonCost = ConvertTo-LedgerNumberLocal $actualComparison[0]['USD']
                if ($null -eq $comparisonCredits -or [math]::Abs($comparisonCredits - $totalCredits) -gt 0.01) {
                    $mismatches.Add('Exact Cost Comparison credits differ from the exact Usage & Cost total.')
                }
                if ($null -eq $comparisonCost -or [math]::Abs($comparisonCost - $totalCost) -gt 0.0001) {
                    $mismatches.Add('Exact Cost Comparison USD differs from the exact Usage & Cost total.')
                }
            }
            $baselineComparison = @($comparisonTables | ForEach-Object Rows | Where-Object { ([string]$_['Scenario']).StartsWith('Without HVE Squad') } | Select-Object -First 1)
            $saving = [regex]::Match($consumptionContent, '(?m)^HVE Squad is \*\*(?<usd>[0-9,.]+) USD \((?<pct>[0-9,.]+)%\) (?<direction>lower|higher)\*\*')
            if ($baselineComparison.Count -eq 1 -and $saving.Success) {
                $baselineCost = ConvertTo-LedgerNumberLocal $baselineComparison[0]['USD']
                $expectedSaving = $baselineCost - $totalCost
                $quotedSaving = [double]::Parse($saving.Groups['usd'].Value.Replace(',', ''), [Globalization.CultureInfo]::InvariantCulture)
                $quotedPct = [double]::Parse($saving.Groups['pct'].Value.Replace(',', ''), [Globalization.CultureInfo]::InvariantCulture)
                $expectedPct = if ($baselineCost -gt 0) { 100.0 * [math]::Abs($expectedSaving) / $baselineCost } else { 0.0 }
                $quotedDirection = $saving.Groups['direction'].Value
                if ([math]::Abs($quotedSaving - [math]::Abs($expectedSaving)) -gt 0.0001 -or
                    [math]::Abs($quotedPct - $expectedPct) -gt 0.05 -or
                    ($expectedSaving -ge 0 -and $quotedDirection -ne 'lower') -or
                    ($expectedSaving -lt 0 -and $quotedDirection -ne 'higher')) {
                    $mismatches.Add('Exact Cost Comparison saving differs from the exact actual and calculated counterfactual rows.')
                }
            }
        }
        else {
            $actualTurns = ConvertTo-LedgerNumberLocal $totalRow['Turns']
            $actualIn = ConvertTo-LedgerNumberLocal $totalRow['In Tokens']
            $actualCached = ConvertTo-LedgerNumberLocal $totalRow['Cached']
            $actualCacheWr = ConvertTo-LedgerNumberLocal $totalRow['Cache Wr']
            $actualOut = ConvertTo-LedgerNumberLocal $totalRow['Out Tokens']
            $actualCost = ConvertTo-LedgerNumberLocal $totalRow['Est. Cost (USD)']

            function Test-ExactLocal {
                param($Name, $Actual, $Expected)
                if ($null -eq $Actual -or [double]$Actual -ne [double]$Expected) {
                    $script:mismatches.Add("$Name`: consumption.md says $Actual, derived from history/ is $Expected.")
                }
            }
            Test-ExactLocal -Name 'Turns' -Actual $actualTurns -Expected $totalTurns
            Test-ExactLocal -Name 'In Tokens' -Actual $actualIn -Expected $totalInput
            Test-ExactLocal -Name 'Cached' -Actual $actualCached -Expected $totalCached
            Test-ExactLocal -Name 'Cache Wr' -Actual $actualCacheWr -Expected $totalCacheWrite
            Test-ExactLocal -Name 'Out Tokens' -Actual $actualOut -Expected $totalOutput

            if ($null -eq $actualCost) {
                $mismatches.Add("Est. Cost (USD): consumption.md's Total row cost cell did not parse as a number.")
            }
            else {
                $tolerance = [math]::Max(0.0001, [math]::Abs($totalCost) * 0.001)
                if ([math]::Abs($actualCost - $totalCost) -gt $tolerance) {
                    $mismatches.Add(("Est. Cost (USD): consumption.md says {0:N4}, derived from history/ is {1:N4} (tolerance {2:N4})." -f $actualCost, $totalCost, $tolerance))
                }
            }
        }

        # C2 history-identity guard (see Test-HistoryIdentityGuardLocal): a legacy
        # ledger with no recorded identities only warns, never fails, so an
        # existing squad root keeps passing -Check until its next rewrite.
        if ($identityGuardResult) {
            foreach ($w in $identityGuardResult.Warnings) { $warnings.Add("WARN: $w") }
            foreach ($f in $identityGuardResult.Failures) { $mismatches.Add($f) }
        }
    }

    # C3: ledger<->state.json currentRun divergence. Independent of whether
    # consumption.md itself parsed above -- state.json can diverge from the
    # ledger even when consumption.md is missing or malformed, and the Scribe
    # needs that named too. A federation root (marked by federation.md) has no
    # single run-level currentRun to reconcile against, so this is logged as
    # not-applicable rather than silently skipped or falsely failed.
    if ($isFederationRoot) {
        $infoLines.Add('not-applicable: federation root (ledger<->state.json currentRun divergence check skipped; a federation root has no single run-level currentRun to compare against)')
    }
    elseif ($roleAggregates.Count -gt 0 -and ($null -eq $stateCostUsd -or $null -eq $stateCreditsTotal)) {
        $reason = if ($stateReadError) { $stateReadError } else { "currentRun.estCostUsd/estCreditsTotal missing." }
        $mismatches.Add("history/ holds consumption block(s) for $($roleAggregates.Count) role(s), but state.json's currentRun cost/credits could not be read ($reason); the Scribe must overwrite state.json currentRun to match the ledger.")
    }
    elseif ($roleAggregates.Count -gt 0) {
        $costTolerance = [math]::Max(0.0001, [math]::Abs($totalCost) * 0.001)
        $costDelta = [double]$stateCostUsd - $totalCost
        if ([math]::Abs($costDelta) -gt $costTolerance) {
            $mismatches.Add(("Ledger<->state.json currentRun divergence: estCostUsd -- ledger derives {0:N4}, currentRun says {1:N4} (delta {2:N4}, tolerance {3:N4})." -f $totalCost, [double]$stateCostUsd, $costDelta, $costTolerance))
        }
        $creditsTolerance = [math]::Max(0.01, [math]::Abs($totalCredits) * 0.001)
        $creditsDelta = [double]$stateCreditsTotal - $totalCredits
        if ([math]::Abs($creditsDelta) -gt $creditsTolerance) {
            $mismatches.Add(("Ledger<->state.json currentRun divergence: estCreditsTotal -- ledger derives {0:N2}, currentRun says {1:N2} (delta {2:N2}, tolerance {3:N2})." -f $totalCredits, [double]$stateCreditsTotal, $creditsDelta, $creditsTolerance))
        }
    }

    foreach ($key in $ExpectedHistoryCounts.Keys) {
        $normalized = $key -replace '\.md$', ''
        $expected = $ExpectedHistoryCounts[$key]
        $actual = if ($historyCounts.ContainsKey($normalized)) { $historyCounts[$normalized] } else { 0 }
        if ($actual -ne $expected) {
            $mismatches.Add("History entry count for '$normalized': expected $expected, found $actual.")
        }
    }

    foreach ($w in $warnings) { Write-Warning $w }
    foreach ($info in $infoLines) { Write-Host $info -ForegroundColor Yellow }

    if ($mismatches.Count -gt 0) {
        Write-Host "Measure-SquadLedger -Check: FAIL ($($mismatches.Count) mismatch(es))" -ForegroundColor Red
        foreach ($m in $mismatches) { Write-Host "  - $m" -ForegroundColor Red }
        # history-integrity: a dispatch record is missing, removed, overwritten, or
        # inserted out of order, or a protected deliverable changed -- proof of
        # dispatch is in doubt, so the pipelining fail-closed rule applies.
        # ledger-only: everything else is cost accounting the next -Write
        # re-derives from history/, so the coordinator warns and continues.
        $integrityPattern = '^(History entry count for |Baseline)|History identity guard: .*(an entry was removed|overwritten or reordered)'
        $failureClass = if (@($mismatches | Where-Object { $_ -match $integrityPattern }).Count -gt 0) { 'history-integrity' } else { 'ledger-only' }
        Write-Host "Measure-SquadLedger -Check: failure class: $failureClass" -ForegroundColor Red
        exit 1
    }

    Write-Host 'Measure-SquadLedger -Check: PASS' -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------------------
# Output (markdown, pasteable into consumption.md; json; or -Write, which
# splices the same markdown fragment into consumption.md itself).
# ---------------------------------------------------------------------------

$exactUsage = $null
$exactCacheUpdate = $null
if ($SessionLog) {
    $cacheSessions = @()
    $cacheAvailable = $true
    $cacheChanged = $false
    $legacyMigrated = $false
    try {
        $cacheSessions = @(Read-ExactSessionCacheLocal -Path $sessionCachePath)
        $nullCoverageMigrations = @(
            $cacheSessions | Where-Object {
                $_.PSObject.Properties['cacheMigrationRequired'] -and $_.cacheMigrationRequired
            }
        )
        if ($nullCoverageMigrations.Count -gt 0) {
            $cacheChanged = $true
            $warnings.Add("WARN: normalized legacy null historyCoverage arrays in $($nullCoverageMigrations.Count) exact-session snapshot(s); the next write persists canonical empty arrays and refreshed content digests.")
        }
        if ($cacheSessions.Count -eq 0 -and -not (Test-Path -LiteralPath $sessionCachePath -PathType Leaf) -and $existingConsumptionContent) {
            $legacySession = Convert-ExistingExactLedgerToCacheSessionLocal -ConsumptionContent $existingConsumptionContent -CurrentHistoryCoverage $historyIdentitiesByFile
            if ($legacySession) {
                $cacheSessions = @($legacySession)
                $cacheChanged = $true
                $legacyMigrated = $true
            }
        }
    }
    catch {
        $cacheAvailable = $false
        $warnings.Add("WARN: consumption-sessions.json is unavailable or inconsistent; it was left unchanged and estimates remain the fallback: $($_.Exception.Message)")
    }

    if ($cacheAvailable) {
        $sessionPaths = @(Resolve-SessionLogPathsLocal -SessionLog $SessionLog -SquadRoot $SquadRoot)
        $sessionPath = if ($sessionPaths.Count -gt 0) { $sessionPaths[0] } else { $null }
        $session = $null
        if ($sessionPath) {
            try { $session = Read-SessionUsageLocal -Path $sessionPath -SquadRoot $SquadRoot }
            catch {
                $warnings.Add("WARN: exact per-role usage from '$sessionPath' was unavailable: $($_.Exception.Message)")
            }
        }

        if ($session) {
            try {
                if ($cacheSessions.Count -gt 0 -and $SessionLog -eq 'auto') {
                    $latestCachedIndex = $cacheSessions.Count - 1
                    $latestCached = $cacheSessions[$latestCachedIndex]
                    if ([string]$latestCached.source -eq 'native-log' -and
                        [string]$latestCached.sessionId -cne [string]$session.SessionId) {
                        $priorPath = @(
                            $sessionPaths | Where-Object {
                                (Split-Path -Leaf (Split-Path -Parent $_)) -ceq [string]$latestCached.sessionId
                            } | Select-Object -First 1
                        )
                        if ($priorPath.Count -eq 1) {
                            try {
                                $priorSession = Read-SessionUsageLocal -Path $priorPath[0] -SquadRoot $SquadRoot
                                if ([string]$priorSession.SessionId -cne [string]$latestCached.sessionId) {
                                    throw "Repository session path '$($priorPath[0])' reports '$($priorSession.SessionId)', not cached session '$($latestCached.sessionId)'."
                                }
                                $priorExpected = Get-ExpectedNativeCoverageLocal -HistoryCoverage $latestCached.historyCoverage `
                                    -MeteredHistoryCoverage $meteredHistoryIdentitiesByFile `
                                    -MeteredAgents @($ordered | ForEach-Object AgentName) -HistoryEntries @($exactHistoryEntries)
                                $priorRequiresOrchestration = [bool]$priorExpected.RequireOrchestration -or
                                    (Test-NativeSessionHasScribeUsageLocal -Session $priorSession)
                                $priorExact = Get-ExactLedgerUsageLocal -Session $priorSession -Rates $rates -Roster $roster `
                                    -HistoryEntries @($priorExpected.HistoryEntries) -ExpectedAgentNames @($priorExpected.Agents) `
                                    -RequireOrchestration:$priorRequiresOrchestration -EnforceExpectedSet -RequireSessionBoundary `
                                    -BaselineModel $BaselineModel -Warnings $warnings
                                if ($priorExact) {
                                    $refreshedPrior = ConvertTo-CacheSessionLocal -Exact $priorExact -HistoryCoverage $latestCached.historyCoverage
                                    Assert-ExactSessionRefreshLocal -Existing $latestCached -Next $refreshedPrior
                                    $cacheSessions[$latestCachedIndex] = $refreshedPrior
                                    $cacheChanged = $true
                                }
                                else {
                                    $warnings.Add("WARN: the previous native session '$($latestCached.sessionId)' could not be finalized from its completed log; its last accepted exact snapshot was retained.")
                                }
                            }
                            catch {
                                $warnings.Add("WARN: the previous native session '$($latestCached.sessionId)' could not be finalized; its last accepted exact snapshot was retained: $($_.Exception.Message)")
                            }
                        }
                    }
                }

                $bootstrapped = $false
                if ($cacheSessions.Count -eq 0 -and $SessionLog -eq 'auto' -and $sessionPaths.Count -gt 1) {
                    try {
                        $bootstrap = Get-ExactSessionBootstrapLocal -Paths $sessionPaths -SquadRoot $SquadRoot `
                            -HistoryCoverage $historyIdentitiesByFile -MeteredHistoryCoverage $meteredHistoryIdentitiesByFile `
                            -HistoryEntries @($exactHistoryEntries) -OrderedAggregates @($ordered) -Rates $rates -Roster $roster `
                            -ActiveSession $session -BaselineModel $BaselineModel -Warnings $warnings
                        if ($bootstrap) {
                            $cacheSessions = @($bootstrap.Sessions)
                            $cacheChanged = $true
                            $exactUsage = $bootstrap.ExactUsage
                            $bootstrapped = $true
                        }
                    }
                    catch {
                        $warnings.Add("WARN: exact session-journal bootstrap was unavailable; the active session will be reconciled normally: $($_.Exception.Message)")
                    }
                }

                if (-not $bootstrapped) {
                    $coveragePlan = Get-ExactCoveragePlanLocal -Sessions $cacheSessions -CurrentSessionId ([string]$session.SessionId) -CurrentHistoryCoverage $historyIdentitiesByFile
                    $currentCoverageCount = [int](($coveragePlan.CurrentCoverage.Values | ForEach-Object { @($_).Count } | Measure-Object -Sum).Sum)
                    $hasNativeScribeUsage = Test-NativeSessionHasScribeUsageLocal -Session $session
                    $refreshCurrentSession = $coveragePlan.ExistingSession -or $currentCoverageCount -gt 0 -or $hasNativeScribeUsage
                    if ($refreshCurrentSession) {
                        $expected = Get-ExpectedNativeCoverageLocal -HistoryCoverage $coveragePlan.CurrentCoverage `
                            -MeteredHistoryCoverage $meteredHistoryIdentitiesByFile `
                            -MeteredAgents @($ordered | ForEach-Object AgentName) -HistoryEntries @($exactHistoryEntries)
                        if ([int]$expected.MeteredEntryCount -eq 0 -and $cacheSessions.Count -gt 0 -and -not $hasNativeScribeUsage) {
                            if ($coveragePlan.ExistingIndex -ge 0) {
                                $cacheSessions[$coveragePlan.ExistingIndex].historyCoverage = $coveragePlan.CurrentCoverage
                            }
                            else {
                                $lastIndex = $cacheSessions.Count - 1
                                $cacheSessions[$lastIndex].historyCoverage = Join-HistoryCoverageLocal `
                                    -Left $cacheSessions[$lastIndex].historyCoverage -Right $coveragePlan.CurrentCoverage
                            }
                            $cacheChanged = $true
                            $exactUsage = Merge-ExactSessionUsageLocal -Sessions $cacheSessions -Rates $rates -Roster $roster `
                                -BaselineModel $BaselineModel -ActiveSession $null -Warnings $warnings
                        }
                        else {
                            $requiresOrchestration = [bool]$expected.RequireOrchestration -or $hasNativeScribeUsage
                            $sessionExact = Get-ExactLedgerUsageLocal -Session $session -Rates $rates -Roster $roster `
                                -HistoryEntries @($expected.HistoryEntries) -ExpectedAgentNames @($expected.Agents) `
                                -RequireOrchestration:$requiresOrchestration -EnforceExpectedSet -RequireSessionBoundary `
                                -BaselineModel $BaselineModel -Warnings $warnings
                            if ($sessionExact) {
                                $cacheSession = ConvertTo-CacheSessionLocal -Exact $sessionExact -HistoryCoverage $coveragePlan.CurrentCoverage
                                if ($coveragePlan.ExistingIndex -ge 0) {
                                    Assert-ExactSessionRefreshLocal -Existing $cacheSessions[$coveragePlan.ExistingIndex] -Next $cacheSession
                                    $nextSessions = [Collections.Generic.List[object]]::new()
                                    for ($i = 0; $i -lt $cacheSessions.Count; $i++) {
                                        $nextSessions.Add($(if ($i -eq $coveragePlan.ExistingIndex) { $cacheSession } else { $cacheSessions[$i] }))
                                    }
                                    $cacheSessions = $nextSessions.ToArray()
                                }
                                else {
                                    $cacheSessions = @($cacheSessions) + @($cacheSession)
                                }
                                $cacheChanged = $true
                                $exactUsage = Merge-ExactSessionUsageLocal -Sessions $cacheSessions -Rates $rates -Roster $roster `
                                    -BaselineModel $BaselineModel -ActiveSession $session -Warnings $warnings
                            }
                            elseif ($coveragePlan.CacheCoversAll) {
                                $exactUsage = Merge-ExactSessionUsageLocal -Sessions $cacheSessions -Rates $rates -Roster $roster `
                                    -BaselineModel $BaselineModel -ActiveSession $null -Warnings $warnings
                                $warnings.Add("WARN: the live native session could not refresh its cached snapshot, so the last fully reconciled cumulative exact snapshot was retained.")
                            }
                        }
                    }
                    elseif ($coveragePlan.CacheCoversAll) {
                        $exactUsage = Merge-ExactSessionUsageLocal -Sessions $cacheSessions -Rates $rates -Roster $roster `
                            -BaselineModel $BaselineModel -ActiveSession $null -Warnings $warnings
                    }
                }
            }
            catch {
                $exactUsage = $null
                $warnings.Add("WARN: exact cross-session accumulation was unavailable; estimates remain the fallback: $($_.Exception.Message)")
            }
        }
        elseif ($cacheSessions.Count -gt 0) {
            try {
                $coveragePlan = Get-ExactCoveragePlanLocal -Sessions $cacheSessions -CurrentSessionId '__no-active-native-session__' -CurrentHistoryCoverage $historyIdentitiesByFile
                if ($coveragePlan.CacheCoversAll) {
                    $exactUsage = Merge-ExactSessionUsageLocal -Sessions $cacheSessions -Rates $rates -Roster $roster `
                        -BaselineModel $BaselineModel -ActiveSession $null -Warnings $warnings
                }
                else {
                    $expected = Get-ExpectedNativeCoverageLocal -HistoryCoverage $coveragePlan.CurrentCoverage `
                        -MeteredHistoryCoverage $meteredHistoryIdentitiesByFile `
                        -MeteredAgents @($ordered | ForEach-Object AgentName) -HistoryEntries @($exactHistoryEntries)
                    if ([int]$expected.MeteredEntryCount -ne 0) {
                        throw 'new metered history exists without an available native session snapshot'
                    }
                    $lastIndex = $cacheSessions.Count - 1
                    $cacheSessions[$lastIndex].historyCoverage = Join-HistoryCoverageLocal `
                        -Left $cacheSessions[$lastIndex].historyCoverage -Right $coveragePlan.CurrentCoverage
                    $cacheChanged = $true
                    $exactUsage = Merge-ExactSessionUsageLocal -Sessions $cacheSessions -Rates $rates -Roster $roster `
                        -BaselineModel $BaselineModel -ActiveSession $null -Warnings $warnings
                }
            }
            catch {
                $exactUsage = $null
                $warnings.Add("WARN: cached exact sessions do not cover current history; estimates remain the fallback: $($_.Exception.Message)")
            }
        }

        if (-not $sessionPath -and -not $exactUsage) {
            $warnings.Add("WARN: -SessionLog auto found no Copilot session whose workspace is this squad root's repository; estimates remain the fallback.")
        }
        elseif ($sessionPath -and -not $exactUsage -and $cacheSessions.Count -eq 0) {
            $warnings.Add("WARN: exact per-role usage from '$sessionPath' did not fully reconcile; estimates remain the fallback.")
        }
        if ($legacyMigrated -and @($cacheSessions | Where-Object source -eq 'legacy-ledger').Count -gt 0) {
            $warnings.Add('WARN: migrated the existing exact ledger into consumption-sessions.json; exact historical actuals are preserved, while the single-model counterfactual remains unavailable for that migrated session because request-level details were not stored in consumption.md.')
        }
        if ($cacheChanged) {
            $exactCacheUpdate = [pscustomobject]@{
                Path = $sessionCachePath
                Text = ConvertTo-ExactSessionCacheDocumentLocal -Sessions $cacheSessions
                Encoding = [Text.UTF8Encoding]::new($false)
            }
        }
    }
}

$ledgerBasis = if ($exactUsage) { 'exact-native' } else { 'estimated' }
$ledgerRows = if ($exactUsage) { @($exactUsage.Rows) } else { @($roleAggregates) }
if ($exactUsage) {
    $totalTurns = $exactUsage.TotalRequests
    $totalInput = $exactUsage.TotalInput
    $totalCached = $exactUsage.TotalCached
    $totalCacheWrite = $exactUsage.TotalCacheWrite
    $totalOutput = $exactUsage.TotalOutput
    $totalCost = $exactUsage.TotalCostUsd
    $totalCredits = $exactUsage.TotalCredits
}

$unitEconomics = Get-UnitEconomicsLocal -Entries @($unitEntries) -Roster $roster -TotalCredits $totalCredits `
    -OrchestrationCredits $(if ($exactUsage) { $exactUsage.OrchestrationCredits } elseif ($orchestrationAggregate) { $orchestrationAggregate.Cost / 0.01 } else { 0.0 }) `
    -HostAiu $null -CostBasis $ledgerBasis

$fragmentLines = [System.Collections.Generic.List[string]]::new()
$fragmentLines.Add('## Attribution')
$fragmentLines.Add('')
$fragmentLines.Add('| Role | Member | Agent | Model | Model Source | Priced As | Tier |')
$fragmentLines.Add('| ---- | ------ | ----- | ----- | ------------ | --------- | ---- |')
foreach ($agg in $ledgerRows) {
    $fragmentLines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f `
                $agg.Label, $agg.Member, $agg.Agent, ($agg.Models -join ', '), ($agg.ModelSources -join ', '), ($agg.PricedAsUsed -join ', '), $agg.Tier))
}
$fragmentLines.Add('')
$fragmentLines.Add('## Usage & Cost')
$fragmentLines.Add('')
$inv = [Globalization.CultureInfo]::InvariantCulture
if ($exactUsage) {
    $fragmentLines.Add('| Role | Requests | In Tokens | Cached | Cache Wr | Out Tokens | Exact Cost (USD) | Exact Credits | Basis |')
    $fragmentLines.Add('| ---- | -------- | --------- | ------ | -------- | ---------- | ---------------- | ------------- | ----- |')
    foreach ($agg in $ledgerRows) {
        $fragmentLines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | exact-native |' -f
                $agg.Label,
                ([int]$agg.Requests).ToString('N0', $inv),
                ([long]$agg.Input).ToString('N0', $inv),
                ([long]$agg.Cached).ToString('N0', $inv),
                ([long]$agg.CacheWrite).ToString('N0', $inv),
                ([long]$agg.Output).ToString('N0', $inv),
                ([double]$agg.Cost).ToString('F4', $inv),
                ([double]$agg.Credits).ToString('F2', $inv)))
    }
    $fragmentLines.Add(('| **Total** | **{0}** | **{1}** | **{2}** | **{3}** | **{4}** | **{5}** | **{6}** | **exact-native** |' -f
            ([int]$totalTurns).ToString('N0', $inv),
            ([long]$totalInput).ToString('N0', $inv),
            ([long]$totalCached).ToString('N0', $inv),
            ([long]$totalCacheWrite).ToString('N0', $inv),
            ([long]$totalOutput).ToString('N0', $inv),
            ([double]$totalCost).ToString('F4', $inv),
            ([double]$totalCredits).ToString('F2', $inv)))
}
else {
    $fragmentLines.Add('| Role | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis |')
    $fragmentLines.Add('| ---- | ----- | --------- | ------ | -------- | ---------- | ---------------- | ------------ | ----- |')
    foreach ($agg in $ledgerRows) {
        $fragmentLines.Add(('| {0} | {1:N0} | {2:N0} | {3:N0} | {4:N0} | {5:N0} | {6:N4} | {7:N2} | {8} |' -f `
                    $agg.Label, $agg.Turns, $agg.Input, $agg.Cached, $agg.CacheWrite, $agg.Output, $agg.Cost, ($agg.Cost / 0.01), $agg.Basis))
    }
    $fragmentLines.Add(('| **Total** | **{0:N0}** | **{1:N0}** | **{2:N0}** | **{3:N0}** | **{4:N0}** | **{5:N4}** | **{6:N2}** | |' -f `
                $totalTurns, $totalInput, $totalCached, $totalCacheWrite, $totalOutput, $totalCost, $totalCredits))
}
$fragmentLines.Add('')
$fragmentLines.Add('### Derivation')
$fragmentLines.Add('')
$fragmentLines.Add('```text')
foreach ($line in $enumerationLines) { $fragmentLines.Add($line) }
if ($exactUsage) {
    if ([int]$exactUsage.SessionCount -gt 1) {
        $fragmentLines.Add(("Native usage snapshots — sessions: {0}; records: {1}; through: {2}; digest: {3}" -f
                $exactUsage.SessionCount, $exactUsage.SnapshotRecords, $exactUsage.SnapshotTimestamp, $exactUsage.SnapshotDigest))
    }
    else {
        $fragmentLines.Add(("Native usage snapshot — session: {0}; records: {1}; through: {2}; digest: {3}" -f
                $exactUsage.Session.SessionId, $exactUsage.SnapshotRecords, $exactUsage.SnapshotTimestamp, $exactUsage.SnapshotDigest))
    }
    foreach ($agg in $ledgerRows) {
        $fragmentLines.Add(('{0,-18} requests {1,-6} input {2,-10} cached {3,-10} cache-write {4,-10} output {5,-10} nano-AIU {6} = {7} credits / {8} USD' -f
                $agg.Label,
                ([int]$agg.Requests).ToString($inv),
                ([long]$agg.Input).ToString($inv),
                ([long]$agg.Cached).ToString($inv),
                ([long]$agg.CacheWrite).ToString($inv),
                ([long]$agg.Output).ToString($inv),
                ([decimal]$agg.NanoAiu).ToString($inv),
                ([double]$agg.Credits).ToString('F2', $inv),
                ([double]$agg.Cost).ToString('F4', $inv)))
    }
    $fragmentLines.Add(('total nano-AIU {0} = {1} credits / {2} USD' -f
            ([decimal]$exactUsage.TotalNanoAiu).ToString($inv),
            ([double]$totalCredits).ToString('F2', $inv),
            ([double]$totalCost).ToString('F4', $inv)))
}
else {
    foreach ($agg in $roleAggregates) {
        if ($agg.Blocks.Count -eq 0) { continue }
        $firstRate = $agg.Blocks[0].Rate
        $mismatch = @($agg.Blocks | Where-Object { $_.Rate.input -ne $firstRate.input -or $_.Rate.output -ne $firstRate.output }).Count -gt 0
        if ($mismatch) {
            $fragmentLines.Add("NOTE: $($agg.Label) blocks priced at more than one rate; the line below uses the first block's rate over the aggregated tokens, but the role's Cost column above sums each block at its own rate.")
        }

        $turnsPerBlock = @($agg.Blocks | ForEach-Object { [double]$_.Block.Fields['internal_turns'] })
        $turnsExpr = if ($turnsPerBlock.Count -gt 1) { "$($turnsPerBlock -join '+')=$($agg.Turns)" } else { "$($agg.Turns)" }

        $rawSum = [math]::Round($agg.Input * $firstRate.input + $agg.Cached * $firstRate.cached + $agg.CacheWrite * $firstRate.cache_write + $agg.Output * $firstRate.output, 4)
        $rawLine = '{0} × {1:N2} + {2} × {3:N2} + {4} × {5:N2} + {6} × {7:N2} = {8} / 1e6 = {9:N4}' -f $agg.Input, $firstRate.input, $agg.Cached, $firstRate.cached, $agg.CacheWrite, $firstRate.cache_write, $agg.Output, $firstRate.output, $rawSum, $agg.Cost
        $fragmentLines.Add(("{0,-14} turns {1,-12} {2}" -f $agg.Label, $turnsExpr, $rawLine))
    }
    $fragmentLines.Add(("{0,-14} {1,-12} {2,-59} total = {3:N4}" -f '', '', '', $totalCost))
}
$fragmentLines.Add('```')

if ($Write) {
    # Both updates are computed before either file is written, so a refusal on
    # one never leaves the other half-applied.
    $updates = @(
        Get-ConsumptionFragmentUpdateLocal -ConsumptionPath $consumptionPath -FragmentLines $fragmentLines.ToArray()
        Get-StateRunTotalUpdateLocal -StatePath $statePath -CostUsd $totalCost -Credits $totalCredits
    )
    if ($exactCacheUpdate) { $updates += $exactCacheUpdate }
    $updates[0].Text = Get-ConsumptionWithSectionLocal -Text $updates[0].Text -SectionLines @() -HeadingPattern '^##\s+Observed Usage \(host-reported\)\s*$' -InsertBeforePatterns @('(?!)')
    $updates[0].Text = Get-ConsumptionWithSectionLocal -Text $updates[0].Text -SectionLines (Get-UnitEconomicsSectionLinesLocal -Ue $unitEconomics) -HeadingPattern '^##\s+Unit Economics \(value\)\s*$' -InsertBeforePatterns @('^##\s+Cost Comparison')
    if ($initializationOnly) {
        $updates[0].Text = Get-ConsumptionWithSectionLocal -Text $updates[0].Text -SectionLines @('## Cost Comparison (illustrative)', '', $initializationComparison, '') -HeadingPattern '^##\s+Cost Comparison.*$' -InsertBeforePatterns @('(?!)')
    }
    elseif ($exactUsage) {
        $updates[0].Text = Get-ConsumptionWithSectionLocal -Text $updates[0].Text -SectionLines (Get-ExactCostComparisonSectionLinesLocal -Exact $exactUsage) -HeadingPattern '^##\s+Cost Comparison.*$' -InsertBeforePatterns @('(?!)')
    }
    else {
        $comparison = Get-CostComparisonUpdateLocal -Text $updates[0].Text -CostUsd $totalCost -Credits $totalCredits -AgentCount (@($roleAggregates | Where-Object Label -ne 'orchestration').Count)
        $updates[0].Text = $comparison.Text
    }
    # Each file is written to a temp file beside it and moved into place; when a later move fails,
    # every earlier file gets its original bytes back, so the ledger, state totals, and exact-session
    # cache are one transaction.
    $applied = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($u in $updates) {
        $tmp = Join-Path (Split-Path -Path $u.Path -Parent) (".$([System.IO.Path]::GetFileName($u.Path)).$([guid]::NewGuid().ToString('N')).tmp")
        try {
            $original = if (Test-Path -LiteralPath $u.Path -PathType Leaf) { [System.IO.File]::ReadAllBytes($u.Path) } else { $null }
            [System.IO.File]::WriteAllText($tmp, $u.Text, $u.Encoding)
            [System.IO.File]::Move($tmp, $u.Path, $true)
            $applied.Add(@{ Path = $u.Path; Bytes = $original })
        }
        catch {
            $reason = $_.Exception.Message
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            $restoreFailures = @()
            for ($i = $applied.Count - 1; $i -ge 0; $i--) {
                try {
                    if ($null -eq $applied[$i].Bytes) { Remove-Item -LiteralPath $applied[$i].Path -Force }
                    else { [System.IO.File]::WriteAllBytes($applied[$i].Path, [byte[]]$applied[$i].Bytes) }
                }
                catch { $restoreFailures += "$($applied[$i].Path): $($_.Exception.Message)" }
            }
            $restored = if ($restoreFailures.Count -gt 0) { " RESTORE FAILED for: $($restoreFailures -join '; ')" } elseif ($applied.Count -gt 0) { " $(($applied | ForEach-Object { Split-Path -Leaf $_.Path }) -join ', ') restored to its original bytes." } else { ' Nothing was written.' }
            throw "Measure-SquadLedger -Write: could not write $(Split-Path -Leaf $u.Path) ($reason).$restored"
        }
    }
    foreach ($w in $warnings) { Write-Warning $w }
    if (-not $initializationOnly -and -not $exactUsage -and $comparison.Added) { Write-Host 'APPENDED Cost Comparison section to consumption.md' }
    Write-Host ("Measure-SquadLedger -Write: rewrote the Attribution, Usage & Cost, Derivation, Unit Economics, and Cost Comparison sections and set state run totals from {0} accounting (estCostUsd={1:F4}, estCreditsTotal={2:F2})." -f $ledgerBasis, $totalCost, $totalCredits) -ForegroundColor Green
    exit 0
}

if ($Format -eq 'json') {
    $unitEconomicsJson = [ordered]@{}
    foreach ($k in $unitEconomics.Keys) { if ($k -ne 'hostBilledPresent') { $unitEconomicsJson[$k] = $unitEconomics[$k] } }
    $result = [ordered]@{
        squadRoot         = $SquadRoot
        calibrationFactor = $calibrationFactor
        basis             = $ledgerBasis
        attribution       = @(
            foreach ($agg in $ledgerRows) {
                [ordered]@{
                    role        = $agg.Label
                    member      = $agg.Member
                    agent       = $agg.Agent
                    model       = ($agg.Models -join ', ')
                    modelSource = ($agg.ModelSources -join ', ')
                    pricedAs    = ($agg.PricedAsUsed -join ', ')
                    tier        = $agg.Tier
                }
            }
        )
        roles             = @(
            foreach ($agg in $ledgerRows) {
                $row = [ordered]@{
                    role       = $agg.Label
                    input      = $agg.Input
                    cached     = $agg.Cached
                    cacheWrite = $agg.CacheWrite
                    output     = $agg.Output
                    basis      = $agg.Basis
                }
                if ($exactUsage) {
                    $row.requests = $agg.Requests
                    $row.costUsd = [math]::Round($agg.Cost, 4)
                    $row.credits = [math]::Round($agg.Credits, 2)
                    $row.estCostUsd = $row.costUsd
                    $row.estCredits = $row.credits
                    $row.nanoAiu = $agg.NanoAiu
                    $row.descendantAgents = @($agg.Descendants)
                }
                else {
                    $row.turns = $agg.Turns
                    $row.estCostUsd = [math]::Round($agg.Cost, 4)
                    $row.estCredits = [math]::Round($agg.Cost / 0.01, 2)
                }
                $row
            }
        )
        total             = if ($exactUsage) {
            [ordered]@{
                requests   = $totalTurns
                input      = $totalInput
                cached     = $totalCached
                cacheWrite = $totalCacheWrite
                output     = $totalOutput
                nanoAiu    = $exactUsage.TotalNanoAiu
                costUsd    = [math]::Round($totalCost, 4)
                credits    = [math]::Round($totalCredits, 2)
                estCostUsd = [math]::Round($totalCost, 4)
                estCredits = [math]::Round($totalCredits, 2)
                basis      = $ledgerBasis
            }
        }
        else {
            [ordered]@{
                turns      = $totalTurns
                input      = $totalInput
                cached     = $totalCached
                cacheWrite = $totalCacheWrite
                output     = $totalOutput
                estCostUsd = [math]::Round($totalCost, 4)
                estCredits = [math]::Round($totalCredits, 2)
                basis      = $ledgerBasis
            }
        }
        historyCounts     = $historyCounts
        stateEstCostUsd   = $stateCostUsd
        stateEstCredits   = $stateCreditsTotal
        exact             = if ($exactUsage) {
            [ordered]@{
                sessionId = $exactUsage.Session.SessionId
                sessionLog = $exactUsage.Session.Path
                sessionCount = $exactUsage.SessionCount
                sessionIds = @($exactUsage.Sessions | ForEach-Object SessionId)
                records = $exactUsage.SnapshotRecords
                identityDigest = $exactUsage.SnapshotDigest
                through = $exactUsage.SnapshotTimestamp
                totalNanoAiu = $exactUsage.TotalNanoAiu
                requestDetailStatus = $exactUsage.RequestDetailStatus
                baselineModel = $exactUsage.BaselineModel
                baselineCostUsd = if ($null -ne $exactUsage.BaselineCostUsd) { [math]::Round($exactUsage.BaselineCostUsd, 4) } else { $null }
                savingsUsd = if ($null -ne $exactUsage.SavingsUsd) { [math]::Round($exactUsage.SavingsUsd, 4) } else { $null }
                savingsPct = if ($null -ne $exactUsage.SavingsPct) { [math]::Round($exactUsage.SavingsPct, 1) } else { $null }
            }
        }
        else { $null }
        unitEconomics     = $unitEconomicsJson
        warnings          = @($warnings)
    }
    $result | ConvertTo-Json -Depth 6
    exit 0
}

foreach ($line in $fragmentLines) { Write-Host $line }
Write-Host ''
foreach ($line in (Get-UnitEconomicsSectionLinesLocal -Ue $unitEconomics)) { Write-Host $line }
if ($exactUsage -and -not $initializationOnly) {
    foreach ($line in (Get-ExactCostComparisonSectionLinesLocal -Exact $exactUsage)) { Write-Host $line }
}

# Diagnostics only, never on the success stream: this keeps stdout a paste-safe
# `## Attribution` / `## Usage & Cost` / `### Derivation` fragment that can never be
# mistaken for (or pasted as) a whole consumption.md. The file's own H1, Basis note,
# and Cost Comparison section are never reprinted here -- see scribe-procedure.md
# Step 7 for what stays untouched when these rows are pasted in.
foreach ($w in $warnings) { Write-Warning $w }
# Actionable, not merely informational: names both currentRun fields and the
# values this run derived for them, so a Scribe reading -Verbose output knows
# exactly what to copy into state.json rather than recomputing it by hand (see
# scribe-procedure.md Step 8). Deliberately worded so the phrase never appears
# as one contiguous run of text on the success stream above -- that exact
# adjacency is what -Check's own leak-detection guards against in consumption.md.
Write-Verbose ("Copy these $ledgerBasis totals into currentRun inside state.json: estCostUsd={0:N4}, estCreditsTotal={1:N2}." -f $totalCost, $totalCredits)
