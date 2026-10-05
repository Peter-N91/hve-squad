#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Deterministically derives (and optionally verifies) a squad root's consumption
    ledger from history/*.md and consumption-rates.md, so the Scribe never hand-
    arithmetics a total again.
.DESCRIPTION
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
    sets the two `state.json` `currentRun` totals, so the Scribe remains the single
    writer of squad state while no model transcribes a derived number by hand.

    Field order for a `#### Consumption` (or `#### Consumption — Orchestration`) block
    is contractual and validated in order: `model`, `model_source`, `priced_as`,
    `model_tier`, `internal_turns`, `input_tokens`, `cached_tokens`,
    `cache_write_tokens`, `output_tokens`, `basis`.

    Role attribution follows `team.md`'s roster order: a history file's agent name
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
    mismatch found.
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
    leaving the H1, frontmatter, Basis note, and Cost Comparison section untouched,
    and sets only `currentRun.estCostUsd` and `currentRun.estCreditsTotal` in
    `state.json` to the derived run totals (a value-only replacement, so every other
    byte of `state.json`, including date strings, is preserved). Refuses, writing
    nothing, when combined with -Check or key-lookup mode, on a federation root
    (marked by `federation.md`), when `consumption.md` lacks those anchors or
    `state.json` lacks exactly one of each `currentRun` key, and in every case the
    render mode already refuses (a failing history-identity guard or an unreadable
    post-baseline block). Run it after every other write the hand-off makes to
    `state.json`, then run -Check -ExpectedHistoryCounts as the self-check.
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
    entry a `{exists, sha256}` record. `state.json` and `consumption.md` are
    intentionally never covered (they are replace-semantics files rewritten
    every stage) -- passing either as `-ProtectedPath` throws. Also writes full
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
.PARAMETER SessionLog
    Optional host session log holding real per-dispatch usage: a Copilot CLI /
    VS Code agent-host `events.jsonl`, the session directory that contains it,
    or `auto` to pick the most recently written session under
    `$COPILOT_HOME/session-state` (default `~/.copilot/session-state`) whose
    `workspace.yaml` `cwd` is this squad root's repository. Each
    `subagent.completed` event gives the dispatch's real model and total
    tokens; the last `session.usage_checkpoint` gives the session's billed AI
    units. The estimates are kept unchanged: markdown and -Write add an
    `## Observed Usage (host-reported)` section beside them (inserted before
    `## Cost Comparison`, or replaced when already present), -Format json adds
    an `observed` object, and -Check ignores the section. A sub-squad root under
    `members/<name>/` counts only dispatches whose prompt names that root. When
    `auto` finds no session, a warning is printed and nothing observed is added.
.PARAMETER BaselineModel
    Model id that prices the "without HVE Squad" comparison in the observed
    section: the same role work run on this one model, with no Scribe. Defaults
    to the most expensive model, by blended rate, that any role dispatch
    actually ran on.
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
        shape (LC Threshold/Input/Cached/Cache write/Output columns present but
        unused here) because rows are selected by header name, never by position.
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
    return ($text -replace '[\s_]+', '-' -replace '-{2,}', '-').Trim('-')
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
        PrimaryAgent, Tier } — AgentNames is every name in that row's Agent Name
        (Primary) and Alternate Agents cells, used for matching; MemberName and
        Tier (the Model Tier cell) are the roster-declared identity the
        Attribution table's Member/Tier columns print for a matched role.
        PrimaryAgent (the Agent Name (Primary) cell alone) is captured but never
        printed as the Attribution table's Agent cell -- that column instead
        names the history file actually dispatched (its own file name), so a
        Fallback dispatch (e.g. `ADR Creator` for the `architect` role, whose
        Primary is `System Architecture Reviewer`) is never misattributed to
        that role's Primary.
    #>
    param([string]$Content)

    $roster = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($table in (Get-MarkdownTableLocal -Content $Content)) {
        if ('Role' -notin $table.Header) { continue }
        # Model-written rosters drift from the template header; accept the same primary spellings Write-SquadHandoff.ps1 does.
        $primaryHeader = @('Agent Name (Primary)', 'Primary Agent', 'Primary', 'Agent') | Where-Object { $_ -in $table.Header } | Select-Object -First 1

        foreach ($row in $table.Rows) {
            $names = [System.Collections.Generic.List[string]]::new()
            foreach ($column in @($primaryHeader, 'Alternate Agents')) {
                if (-not $column -or $column -notin $table.Header) { continue }
                foreach ($name in ($row[$column] -split ',')) {
                    $trimmed = $name.Trim()
                    if ($trimmed -and $trimmed -ne '—' -and $trimmed -ne '-') { $names.Add($trimmed) }
                }
            }
            if (-not $row['Role']) { continue }
            $memberName = if ('Member Name' -in $table.Header) { $row['Member Name'] } else { '' }
            $primaryAgent = if ($primaryHeader) { $row[$primaryHeader] } else { '' }
            $tier = if ('Model Tier' -in $table.Header) { $row['Model Tier'] } else { '' }
            $roster.Add([pscustomobject]@{
                    Role         = $row['Role']
                    AgentNames   = $names
                    MemberName   = $memberName
                    PrimaryAgent = $primaryAgent
                    Tier         = $tier
                })
        }
    }
    $roster
}

function Resolve-RoleForAgentLocal {
    <#
    .SYNOPSIS
        Finds the roster row order index and Role label for a history file's agent
        name. Returns $null Index (sorted last, before orchestration) when unmapped.
    #>
    param(
        [Parameter(Mandatory)][string]$AgentName,
        # Not Mandatory -- see Resolve-RateForBlockLocal for why an empty
        # collection argument must not carry [Parameter(Mandatory)].
        [System.Collections.Generic.List[pscustomobject]]$Roster
    )

    for ($i = 0; $i -lt $Roster.Count; $i++) {
        if ($AgentName -in $Roster[$i].AgentNames) {
            return [pscustomobject]@{ Index = $i; Role = $Roster[$i].Role }
        }
    }
    return [pscustomobject]@{ Index = $null; Role = $AgentName }
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
        $ids = if (-not $idsText -or $idsText -eq '(none)') { @() } else { @($idsText -split ',' | ForEach-Object { $_.Trim() }) }
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
    $pattern = '(?ms)^####[ \t]+Consumption(?<orch>[ \t]+[-\u2013\u2014][ \t]+Orchestration)?[ \t]*(?:\r?\n)+```json\r?\n(?<json>.*?)\r?\n```'
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
            # A heading with no full-block match at the same offset: no valid
            # fenced ```json block follows it (bad/single-backtick fence, or
            # non-JSON content -- e.g. a markdown table -- pasted in its place).
            [pscustomobject]@{
                Source          = $SourceName
                IsOrchestration = [bool]$headingMatch.Groups['orch'].Success
                Fields          = $null
                Order           = @()
                OrderOk         = $false
                NonNumeric      = @()
                ParseError      = 'heading found but no valid fenced ```json block follows it (bad fence, or non-JSON content immediately after the heading).'
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

        [pscustomobject]@{
            Source          = $SourceName
            IsOrchestration = [bool]$match.Groups['orch'].Success
            Fields          = $parsed
            Order           = $order
            OrderOk         = $orderOk
            NonNumeric      = $nonNumeric
            ParseError      = $parseError
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

    $rawCost = ($inTok * $rate.input + $cached * $rate.cached + $cacheWr * $rate.cache_write + $outTok * $rate.output) / 1000000.0
    $cost = $rawCost * $CalibrationFactor

    $Aggregate.Turns += $turns
    $Aggregate.Input += $inTok
    $Aggregate.Cached += $cached
    $Aggregate.CacheWrite += $cacheWr
    $Aggregate.Output += $outTok
    $Aggregate.Cost += $cost
    if ([string]$Block.Fields['basis'] -eq 'tier-default') { $Aggregate.Basis = 'tier-default' }
    $Aggregate.Blocks.Add(@{ Block = $Block; Rate = $rate })

    # Attribution accumulation: a block's `model` is recorded exactly as written --
    # including the literal `unknown` -- and never replaced by the rate row that
    # priced it. `pricedAsName` is the rate's own key (see Get-RateTableLocal),
    # which is the tier-fallback's model name on a fallback and the block's own
    # `priced_as` on a direct hit, so the Priced As column can legitimately differ
    # from Model without either column ever being fabricated.
    $model = [string]$Block.Fields['model']
    $modelSource = [string]$Block.Fields['model_source']
    $pricedAsLabel = [string]$rate.pricedAsName
    if ($model -and $model -notin $Aggregate.Models) { $Aggregate.Models.Add($model) }
    if ($modelSource -and $modelSource -notin $Aggregate.ModelSources) { $Aggregate.ModelSources.Add($modelSource) }
    if ($pricedAsLabel -and $pricedAsLabel -notin $Aggregate.PricedAsUsed) { $Aggregate.PricedAsUsed.Add($pricedAsLabel) }
}

function Get-AttributionCompositeKeyLocal {
    <#
    .SYNOPSIS
        Builds the (Role, Agent) composite key `-Check`'s Attribution comparison
        indexes and looks up by, trimmed and folded to invariant lowercase so a
        merely differently-cased or differently-spaced Agent name is still the
        same row.
    .DESCRIPTION
        R-LEDGER-ATTRIBUTION follow-up: a role with both a Primary and a Fallback
        agent dispatched in the same run (e.g. team.md's own `architect` row)
        produces two distinct $roleAggregates entries -- and two ledger rows --
        that share the same Role but carry different Agent cells (see the
        Agent-assignment comment in the main loop below). Indexing the lookup by
        Role alone collapses those two rows onto each other (last-write-wins):
        both aggregates would then be compared against whichever row survived,
        producing a false mismatch when the survivor's own cells legitimately
        differ from the other aggregate's, or a false pass when a corrupted cell
        happened to coincide with the survivor. Keying by this composite instead
        means each history-file's own row is looked up, and compared, only
        against its own aggregate.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Role, [Parameter(Mandatory)][AllowEmptyString()][string]$Agent)
    '{0}|{1}' -f $Role.Trim().ToLowerInvariant(), $Agent.Trim().ToLowerInvariant()
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
        item 1). state.json and consumption.md are never included here -- they
        are replace-semantics files the Scribe legitimately rewrites every
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
        Throws if a caller-supplied -ProtectedPath entry names state.json or
        consumption.md -- both are excluded from protection by design (they are
        rewritten every stage), not merely by omission.
    #>
    param([Parameter(Mandatory)][string[]]$ProtectedPath)
    foreach ($rel in $ProtectedPath) {
        $normalized = ($rel -replace '\\', '/').Trim('/')
        if ($normalized -match '(?i)^(state\.json|consumption\.md)$') {
            throw "Measure-SquadLedger: -ProtectedPath must not name '$rel' -- state.json and consumption.md are replace-semantics files the Scribe legitimately rewrites every stage and are excluded from protected-artifact checks by design."
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
        plus consumption.md and state.json, into a sibling `<name>.files/`
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
    foreach ($name in @('consumption.md', 'state.json')) {
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

function Test-SquadLedgerBaselineLocal {
    <#
    .SYNOPSIS
        The -BaselinePath -Check verification (Amendment 3 §2 item 1): FAILs on
        an append-only file shrink, a prefix edit (first baseline-Length bytes
        no longer hashing to the baseline's recorded full-content SHA-256), a
        protected-artifact hash change not covered by -AllowedWritePath, or a
        baseline-recorded file that no longer exists. Never checks state.json
        or consumption.md -- excluded by design.
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
                    $failures.Add("Append-only file's entries were inserted inside the file, not appended: '$relPath' keeps every original byte, but new text starts at byte $insertedAt of $baselineLength instead of at the end. Append new entries after the last existing entry, never directly under the file's marker comment.")
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
# -SessionLog: real per-dispatch usage from the host's session log, reported
# beside the estimates (never replacing them).
# ---------------------------------------------------------------------------

function Resolve-SessionLogPathLocal {
    <#
    .SYNOPSIS
        Resolves -SessionLog to an events.jsonl path, or $null when `auto` finds
        no session whose workspace cwd is this squad root's repository.
    #>
    param(
        [Parameter(Mandatory)][string]$SessionLog,
        [Parameter(Mandatory)][string]$SquadRoot
    )
    if ($SessionLog -ne 'auto') {
        $candidate = if (Test-Path -LiteralPath $SessionLog -PathType Container) { Join-Path $SessionLog 'events.jsonl' } else { $SessionLog }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Measure-SquadLedger: -SessionLog '$SessionLog' does not resolve to an events.jsonl file."
        }
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    $marker = [regex]::Match($SquadRoot, '^(?<repo>.*?)[\\/]\.copilot-tracking([\\/]|$)')
    $repoRoot = if ($marker.Success) { $marker.Groups['repo'].Value } else { (Get-Location).Path }
    $repoRoot = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/')

    $copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' }
    $stateDir = Join-Path $copilotHome 'session-state'
    if (-not (Test-Path -LiteralPath $stateDir -PathType Container)) { return $null }

    # Local helper: does this session dir's workspace.yaml name the repo root as its cwd?
    $testCwd = {
        param([string]$dir)
        $workspace = Join-Path $dir 'workspace.yaml'
        if (-not (Test-Path -LiteralPath $workspace -PathType Leaf)) { return $false }
        $cwdMatch = [regex]::Match([System.IO.File]::ReadAllText($workspace), '(?m)^cwd:\s*(?<cwd>.+?)\s*$')
        if (-not $cwdMatch.Success) { return $false }
        try { $cwd = [System.IO.Path]::GetFullPath($cwdMatch.Groups['cwd'].Value.Trim('"', "'")).TrimEnd('\', '/') } catch { return $false }
        return [string]::Equals($cwd, $repoRoot, [System.StringComparison]::OrdinalIgnoreCase)
    }

    # The CLI exports the running session's id to its shell tool. Trust it only when it is a GUID naming a
    # direct child of session-state whose cwd is this repo; an inherited or foreign id falls through to the scan.
    $sessionId = $env:COPILOT_AGENT_SESSION_ID
    if ($sessionId -and $sessionId -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
        $ownDir = [System.IO.Path]::GetFullPath((Join-Path $stateDir $sessionId))
        $stateFull = [System.IO.Path]::GetFullPath($stateDir).TrimEnd('\', '/')
        $own = Join-Path $ownDir 'events.jsonl'
        if ([string]::Equals([System.IO.Path]::GetDirectoryName($ownDir), $stateFull, [System.StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $own -PathType Leaf) -and (& $testCwd $ownDir)) { return $own }
    }

    # Newest events.jsonl first, so the first cwd match is the most recently written one and
    # older sessions' workspace.yaml are never read (a machine can hold thousands).
    $candidates = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($dirPath in [System.IO.Directory]::EnumerateDirectories($stateDir)) {
        $info = [System.IO.FileInfo]::new([System.IO.Path]::Combine($dirPath, 'events.jsonl'))
        if ($info.Exists) { $candidates.Add($info) }
    }
    $candidates.Sort([System.Comparison[System.IO.FileInfo]] { param($a, $b) $b.LastWriteTimeUtc.CompareTo($a.LastWriteTimeUtc) })
    foreach ($item in $candidates) {
        if (& $testCwd $item.DirectoryName) { return $item.FullName }
    }
    return $null
}

function Read-SessionUsageLocal {
    <#
    .SYNOPSIS
        Reads subagent.completed and session.usage_checkpoint events from a host
        session log. A sub-squad root counts only dispatches whose task prompt
        names its `members/<name>` root. Opened with shared read so a live
        session can keep writing; an unparseable (partially written) line is skipped.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SquadRoot
    )
    $memberMatch = [regex]::Match($SquadRoot, '[\\/]members[\\/](?<name>[^\\/]+)[\\/]?$')
    $memberPattern = if ($memberMatch.Success) { 'members[\\/]+' + [regex]::Escape($memberMatch.Groups['name'].Value) + '([\\/]|\b)' } else { $null }

    $dispatches = [System.Collections.Generic.List[pscustomobject]]::new()
    $prompts = @{}
    $nanoAiu = $null
    $first = $null
    $last = $null

    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $reader = [System.IO.StreamReader]::new($stream)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            $typeMatch = [regex]::Match($line, '"type"\s*:\s*"(?<type>subagent\.completed|session\.usage_checkpoint|tool\.execution_start)"')
            $timeMatch = [regex]::Match($line, '"timestamp"\s*:\s*"(?<ts>[^"]+)"')
            if ($timeMatch.Success) {
                if (-not $first) { $first = $timeMatch.Groups['ts'].Value }
                $last = $timeMatch.Groups['ts'].Value
            }
            if (-not $typeMatch.Success) { continue }
            $type = $typeMatch.Groups['type'].Value
            if ($type -eq 'tool.execution_start' -and (-not $memberPattern -or $line -notmatch '"toolName"\s*:\s*"task"')) { continue }
            try { $sessionEvent = $line | ConvertFrom-Json -AsHashtable } catch { continue }
            $data = $sessionEvent['data']
            if (-not $data) { continue }
            switch ($type) {
                'tool.execution_start' {
                    $prompts[[string]$data['toolCallId']] = ($data['arguments'] | ConvertTo-Json -Depth 6 -Compress)
                }
                'session.usage_checkpoint' {
                    if ($null -ne $data['totalNanoAiu']) { $nanoAiu = [double]$data['totalNanoAiu'] }
                }
                'subagent.completed' {
                    $dispatches.Add([pscustomobject]@{
                            ToolCallId = [string]$data['toolCallId']
                            AgentName  = [string]$data['agentName']
                            Model      = [string]$data['model']
                            Tokens     = [double]$data['totalTokens']
                            DurationMs = [double]$data['durationMs']
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
        Path       = $Path
        SessionId  = Split-Path -Leaf (Split-Path -Parent $Path)
        Dispatches = $dispatches
        NanoAiu    = $nanoAiu
        First      = $first
        Last       = $last
        MemberName = if ($memberMatch.Success) { $memberMatch.Groups['name'].Value } else { $null }
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
    if ($Session.Dispatches.Count -eq 0 -and $null -eq $Session.NanoAiu) { return $null }

    $estimatedByAgent = @{}
    $ledgerModelsByAgent = @{}
    foreach ($entry in $OrderedAggregates) {
        $agg = $entry.Aggregate
        $estimatedByAgent[$entry.AgentName] = $agg.Input + $agg.Cached + $agg.CacheWrite + $agg.Output
        $ledgerModelsByAgent[$entry.AgentName] = @($agg.Models)
    }
    if ($OrchestrationAggregate) {
        $estimatedByAgent['Squad Scribe'] = $OrchestrationAggregate.Input + $OrchestrationAggregate.Cached + $OrchestrationAggregate.CacheWrite + $OrchestrationAggregate.Output
        $ledgerModelsByAgent['Squad Scribe'] = @($OrchestrationAggregate.Models)
    }

    $unpriced = [System.Collections.Generic.List[string]]::new()
    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($group in ($Session.Dispatches | Group-Object AgentName)) {
        $observedModels = @($group.Group | ForEach-Object { $_.Model } | Where-Object { $_ } | Select-Object -Unique)
        $cost = 0.0
        foreach ($d in $group.Group) {
            $blended = Get-BlendedRateLocal -Model $d.Model -Rates $Rates
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
                LedgerModels   = $ledgerModels
                Match          = $match
                Tokens         = ($group.Group | Measure-Object Tokens -Sum).Sum
                Estimated      = if ($estimatedByAgent.ContainsKey($group.Name)) { $estimatedByAgent[$group.Name] } else { 0.0 }
                Minutes        = ($group.Group | Measure-Object DurationMs -Sum).Sum / 60000.0
                CostUsd        = $cost
            })
    }
    foreach ($m in $unpriced) { $Warnings.Add("WARN: observed model '$m' has no rate row in consumption-rates.md; its tokens are left out of the blended cost.") }

    $roleRows = @($rows | Where-Object { -not $_.IsScribe })
    $roleTokens = ($roleRows | Measure-Object Tokens -Sum).Sum
    if ($null -eq $roleTokens) { $roleTokens = 0.0 }

    $baseline = $BaselineModel
    if (-not $baseline) {
        $baseline = @($roleRows | ForEach-Object { $_.ObservedModels } | Select-Object -Unique |
                Sort-Object { $rate = Get-BlendedRateLocal -Model $_ -Rates $Rates; if ($null -eq $rate) { -1 } else { $rate } } -Descending |
                Select-Object -First 1)[0]
    }
    $baselineRate = if ($baseline) { Get-BlendedRateLocal -Model $baseline -Rates $Rates } else { $null }
    if ($baseline -and $null -eq $baselineRate) { $Warnings.Add("WARN: baseline model '$baseline' has no rate row; the without-HVE-Squad comparison is omitted.") }

    [pscustomobject]@{
        Session          = $Session
        Rows             = $rows
        ObservedTokens   = ($rows | Measure-Object Tokens -Sum).Sum
        EstimatedTokens  = ($rows | Measure-Object Estimated -Sum).Sum
        SquadCostUsd     = ($rows | Measure-Object CostUsd -Sum).Sum
        RoleTokens       = $roleTokens
        BaselineModel    = $baseline
        BaselineCostUsd  = if ($null -ne $baselineRate) { $roleTokens * $baselineRate / 1e6 } else { $null }
        SessionAiu       = if ($null -ne $Session.NanoAiu) { $Session.NanoAiu / 1e9 } else { $null }
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
    $lines.Add("Source: Copilot session ``$($s.SessionId)`` (``events.jsonl``, $($s.First) to $($s.Last)). The host reports one real token total per dispatch, not split into input, cached, and output, so these figures sit beside the estimates above rather than replacing them. Blended USD prices each total with model-catalog.md's blended mix (0.20 input, 0.80 cached, 0.08 cache write, 0.02 output) over this root's rate rows.$scope")
    $lines.Add('')
    $lines.Add('| Agent | Dispatches | Observed Model | Ledger Model | Match | Observed Tokens | Estimated Tokens | Minutes | Blended USD |')
    $lines.Add('| ----- | ---------- | -------------- | ------------ | ----- | --------------- | ---------------- | ------- | ----------- |')
    foreach ($r in ($Observed.Rows | Sort-Object IsScribe, Agent)) {
        $ledger = if ($r.LedgerModels.Count -gt 0) { $r.LedgerModels -join ', ' } else { '—' }
        $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5:N0} | {6:N0} | {7:N1} | {8:N4} |' -f $r.Agent, $r.Dispatches, ($r.ObservedModels -join ', '), $ledger, $r.Match, $r.Tokens, $r.Estimated, $r.Minutes, $r.CostUsd))
    }
    $lines.Add(('| **Subagents total** | **{0}** | | | | **{1:N0}** | **{2:N0}** | | **{3:N4}** |' -f ($Observed.Rows | Measure-Object Dispatches -Sum).Sum, $Observed.ObservedTokens, $Observed.EstimatedTokens, $Observed.SquadCostUsd))
    $lines.Add('')
    if ($null -ne $Observed.SessionAiu) {
        $lines.Add(('Session total billed by the host, coordinator included: **{0:N2} AI units** (about {1:N2} USD at 0.01 USD per unit, the same convention as 1 AI credit). The coordinator''s own turns appear only in this figure, never in the table.' -f $Observed.SessionAiu, ($Observed.SessionAiu * 0.01)))
        $lines.Add('')
    }
    if ($null -ne $Observed.BaselineCostUsd) {
        $lines.Add('### Without HVE Squad')
        $lines.Add('')
        $lines.Add('| Scenario | Tokens | Model | Blended USD |')
        $lines.Add('| -------- | ------ | ----- | ----------- |')
        $lines.Add(('| With HVE Squad: routed roles plus Scribe, as observed | {0:N0} | as routed | {1:N4} |' -f $Observed.ObservedTokens, $Observed.SquadCostUsd))
        $lines.Add(('| Without HVE Squad: the same role work on one model, no Scribe | {0:N0} | {1} | {2:N4} |' -f $Observed.RoleTokens, $Observed.BaselineModel, $Observed.BaselineCostUsd))
        $lines.Add('')
        $delta = $Observed.BaselineCostUsd - $Observed.SquadCostUsd
        $pct = if ($Observed.BaselineCostUsd -gt 0) { [math]::Abs($delta) / $Observed.BaselineCostUsd * 100 } else { 0 }
        $direction = if ($delta -ge 0) { 'lower' } else { 'higher' }
        $lines.Add(('HVE Squad is **{0:N4} USD ({1:N1}%) {2}** than running the same role work on `{3}`. Both rows use the same blended mix; neither includes coordinator turns, and the single-model row adds no context growth or rework a long single chat would carry, so it is a floor for that scenario rather than a forecast.' -f [math]::Abs($delta), $pct, $direction, $Observed.BaselineModel))
        $lines.Add('')
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
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($Text -split '\r?\n')) { $lines.Add($l) }

    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^##\s+Observed Usage \(host-reported\)\s*$') { $start = $i; break } }
    if ($start -ge 0) {
        $end = $lines.Count
        for ($j = $start + 1; $j -lt $lines.Count; $j++) { if ($lines[$j] -match '^##\s') { $end = $j; break } }
        $lines.RemoveRange($start, $end - $start)
        $insertAt = $start
    }
    else {
        $insertAt = $lines.Count
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^##\s+Cost Comparison') { $insertAt = $i; break } }
    }
    $lines.InsertRange($insertAt, [string[]]$SectionLines)
    return ($lines -join $newline)
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
# `.copilot-tracking/squad` tree, and state.json/consumption.md can never be
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
$roster = Get-RosterLocal -Content $(if (Test-Path -LiteralPath $teamPath) { Get-Content -LiteralPath $teamPath -Raw } else { '' })

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
$historyCounts = @{}
$historyIdentitiesByFile = @{}
$enumerationLines = [System.Collections.Generic.List[string]]::new()


# role label -> aggregate; kept in a list alongside a sort key so unmapped agents
# and orchestration land in the documented order (roster order, unmapped next,
# orchestration last) rather than directory/hash order.
$ordered = [System.Collections.Generic.List[pscustomobject]]::new()
$orchestrationAggregate = $null

foreach ($file in $historyFiles) {
    $agentName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $content = Get-Content -LiteralPath $file.FullName -Raw

    $entryCount = Get-HistoryEntryCountLocal -Content $content
    $historyCounts[$agentName] = $entryCount

    $identities = @(Get-HistoryEntryIdentitiesLocal -Content $content)
    $historyIdentitiesByFile[$file.Name] = $identities
    $identityLabel = if ($identities.Count -gt 0) { $identities -join ',' } else { '(none)' }

    $blocks = @(Get-ConsumptionBlockLocal -Content $content -SourceName $file.Name)
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

        if ($agentName -eq 'Squad Scribe') {
            if (-not $orchestrationAggregate) {
                $orchestrationAggregate = New-RoleAggregateLocal -Label 'orchestration'
                # Orchestration has no team.md roster row (it is the coordinator's own
                # turns plus every Scribe write, not a dispatched role), so its Member/
                # Agent/Tier are the fixed template convention from consumption.md's
                # own `<coord+scribe>` / `mixed` placeholders, never a roster lookup.
                $orchestrationAggregate.Agent = 'Coordinator+Scribe'
                $orchestrationAggregate.Tier = 'mixed'
            }
            Add-BlockToAggregateLocal -Aggregate $orchestrationAggregate -Block $block -Rates $rates -CalibrationFactor $calibrationFactor -Warnings $warnings -TreatUnresolvedRateAsWarning $isLegacyBlock
            continue
        }

        $resolved = Resolve-RoleForAgentLocal -AgentName $agentName -Roster $roster
        $existing = $ordered | Where-Object { $_.AgentName -eq $agentName } | Select-Object -First 1
        if (-not $existing) {
            $aggregate = New-RoleAggregateLocal -Label $resolved.Role
            if ($null -ne $resolved.Index) {
                $rosterRow = $roster[$resolved.Index]
                $aggregate.Member = $rosterRow.MemberName
                $aggregate.Tier = $rosterRow.Tier
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
                AgentName = $agentName
                SortIndex = if ($null -ne $resolved.Index) { $resolved.Index } else { [int]::MaxValue }
                Aggregate = $aggregate
            }
            $ordered.Add($existing)
        }
        Add-BlockToAggregateLocal -Aggregate $existing.Aggregate -Block $block -Rates $rates -CalibrationFactor $calibrationFactor -Warnings $warnings -TreatUnresolvedRateAsWarning $isLegacyBlock
    }
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

if ($Check) {
    $mismatches = [System.Collections.Generic.List[string]]::new()
    $infoLines = [System.Collections.Generic.List[string]]::new()

    # Post-baseline malformed/illegal-model_source blocks (item 3): under -Check
    # these are reported as FAILs rather than thrown (see the non--Check throw
    # gate above, right after the per-file loop).
    foreach ($e in $postBaselineBlockIssues) { $mismatches.Add("Post-baseline block: $e") }

    # -BaselinePath append-only/protected-artifact verification (Amendment 3 §2
    # item 1), only meaningful paired with -Check: shrink, prefix-hash mismatch,
    # protected-hash mismatch (unless in the allowed write set), and a missing
    # baseline file are all FAILs here; state.json/consumption.md rewrites are
    # explicitly not checked by this helper (they are expected to change and are
    # covered by C3 and the structural checks below instead).
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
            # R-LEDGER-ATTRIBUTION follow-up: a role dispatched through both a
            # Primary and a Fallback agent in the same run (e.g. team.md's own
            # `architect` row) produces more than one $roleAggregates entry --
            # and more than one ledger row -- sharing the same Role but carrying
            # different Agent cells (see the Agent-assignment comment in the main
            # loop above). Only when a Role actually has more than one row or
            # more than one aggregate does Agent become load-bearing for *which*
            # row an aggregate is compared against -- keyed by the composite
            # (Role, Agent), trimmed and case-insensitive (see
            # Get-AttributionCompositeKeyLocal above), so each history file's own
            # row is compared only to its own aggregate. In the ordinary
            # one-row-per-role case, matching stays Role-only, unchanged, since
            # Member/Agent/Tier remain intentionally excluded from *value*
            # comparison (see the design-decision comment above) -- disambiguation
            # is the only reason Agent participates in the lookup at all.
            $ledgerRowsByRole = @{}
            $seenLedgerComposites = @{}
            foreach ($row in $attributionTable[0].Rows) {
                $roleText = ([string]$row['Role']).Trim()
                if (-not $roleText) { continue }
                $agentText = ([string]$row['Agent']).Trim()
                $roleKeyLower = $roleText.ToLowerInvariant()
                $compositeKey = Get-AttributionCompositeKeyLocal -Role $roleText -Agent $agentText
                if ($seenLedgerComposites.ContainsKey($compositeKey)) {
                    $mismatches.Add("Attribution: consumption.md has more than one row for role '$roleText' agent '$agentText'.")
                    continue
                }
                $seenLedgerComposites[$compositeKey] = $true
                if (-not $ledgerRowsByRole.ContainsKey($roleKeyLower)) {
                    $ledgerRowsByRole[$roleKeyLower] = [System.Collections.Generic.List[pscustomobject]]::new()
                }
                $ledgerRowsByRole[$roleKeyLower].Add([pscustomobject]@{ Role = $roleText; Agent = $agentText; Row = $row; CompositeKey = $compositeKey })
            }

            $aggregatesByRole = @{}
            foreach ($agg in $roleAggregates) {
                $roleKeyLower = $agg.Label.Trim().ToLowerInvariant()
                if (-not $aggregatesByRole.ContainsKey($roleKeyLower)) {
                    $aggregatesByRole[$roleKeyLower] = [System.Collections.Generic.List[pscustomobject]]::new()
                }
                $aggregatesByRole[$roleKeyLower].Add($agg)
            }

            $consumedLedgerComposites = @{}
            foreach ($agg in $roleAggregates) {
                $roleKeyLower = $agg.Label.Trim().ToLowerInvariant()
                $agentLabel = ([string]$agg.Agent).Trim()
                $candidates = @(if ($ledgerRowsByRole.ContainsKey($roleKeyLower)) { $ledgerRowsByRole[$roleKeyLower] })
                # Disambiguation by Agent is only required when a collision
                # actually exists on either side -- more than one aggregate for
                # this Role, or more than one ledger row for it.
                $needsDisambiguation = ($aggregatesByRole[$roleKeyLower].Count -gt 1) -or ($candidates.Count -gt 1)

                $matchEntry = $null
                if ($needsDisambiguation) {
                    $agentLabelLower = $agentLabel.ToLowerInvariant()
                    $matchEntry = $candidates | Where-Object { $_.Agent.Trim().ToLowerInvariant() -eq $agentLabelLower } | Select-Object -First 1
                }
                elseif ($candidates.Count -eq 1) {
                    $matchEntry = $candidates[0]
                }

                if (-not $matchEntry) {
                    $mismatches.Add("Attribution: consumption.md is missing a row for role '$($agg.Label)' agent '$agentLabel'.")
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
                        $mismatches.Add("Attribution: role '$($agg.Label)' agent '$agentLabel' column '$($column.Name)': consumption.md says '$($ledgerRow[$column.Name])', derived from history/ is '$($expectedCells -join ', ')'.")
                    }
                }

                foreach ($sourceValue in (([string]$ledgerRow['Model Source'] -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                    if ($sourceValue -notin $legalModelSources) {
                        $mismatches.Add("Attribution: role '$($agg.Label)' agent '$agentLabel' column 'Model Source' has illegal value '$sourceValue' (legal values: $($legalModelSources -join ', ')).")
                    }
                }
            }

            foreach ($roleKeyLower in $ledgerRowsByRole.Keys) {
                foreach ($entry in $ledgerRowsByRole[$roleKeyLower]) {
                    if (-not $consumedLedgerComposites.ContainsKey($entry.CompositeKey)) {
                        $mismatches.Add("Attribution: consumption.md has an extra row for role '$($entry.Role)' agent '$($entry.Agent)' with no matching consumption block in history/.")
                    }
                }
            }
        }

        $usageTable = @(Get-MarkdownTableLocal -Content $consumptionContent | Where-Object { 'Turns' -in $_.Header -and 'Basis' -in $_.Header })
        $totalRow = $null
        foreach ($table in $usageTable) {
            $hit = $table.Rows | Where-Object { $_[$table.Header[0]] -match 'Total' } | Select-Object -First 1
            if ($hit) { $totalRow = $hit; break }
        }

        if (-not $totalRow) {
            $mismatches.Add('No Total row found in consumption.md Usage & Cost table.')
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
        exit 1
    }

    Write-Host 'Measure-SquadLedger -Check: PASS' -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------------------
# Output (markdown, pasteable into consumption.md; json; or -Write, which
# splices the same markdown fragment into consumption.md itself).
# ---------------------------------------------------------------------------

$observed = $null
if ($SessionLog) {
    $sessionPath = Resolve-SessionLogPathLocal -SessionLog $SessionLog -SquadRoot $SquadRoot
    if ($sessionPath) {
        $session = Read-SessionUsageLocal -Path $sessionPath -SquadRoot $SquadRoot
        $observed = Get-ObservedUsageLocal -Session $session -Rates $rates -OrderedAggregates @($ordered) -OrchestrationAggregate $orchestrationAggregate -BaselineModel $BaselineModel -Warnings $warnings
    }
    else {
        $warnings.Add("WARN: -SessionLog auto found no Copilot session whose workspace is this squad root's repository; no observed usage was added.")
    }
}

$fragmentLines = [System.Collections.Generic.List[string]]::new()
$fragmentLines.Add('## Attribution')
$fragmentLines.Add('')
$fragmentLines.Add('| Role | Member | Agent | Model | Model Source | Priced As | Tier |')
$fragmentLines.Add('| ---- | ------ | ----- | ----- | ------------ | --------- | ---- |')
foreach ($agg in $roleAggregates) {
    $fragmentLines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f `
                $agg.Label, $agg.Member, $agg.Agent, ($agg.Models -join ', '), ($agg.ModelSources -join ', '), ($agg.PricedAsUsed -join ', '), $agg.Tier))
}
$fragmentLines.Add('')
$fragmentLines.Add('## Usage & Cost')
$fragmentLines.Add('')
$fragmentLines.Add('| Role | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis |')
$fragmentLines.Add('| ---- | ----- | --------- | ------ | -------- | ---------- | ---------------- | ------------ | ----- |')
foreach ($agg in $roleAggregates) {
    $fragmentLines.Add(('| {0} | {1:N0} | {2:N0} | {3:N0} | {4:N0} | {5:N0} | {6:N4} | {7:N2} | {8} |' -f `
                $agg.Label, $agg.Turns, $agg.Input, $agg.Cached, $agg.CacheWrite, $agg.Output, $agg.Cost, ($agg.Cost / 0.01), $agg.Basis))
}
$fragmentLines.Add(('| **Total** | **{0:N0}** | **{1:N0}** | **{2:N0}** | **{3:N0}** | **{4:N0}** | **{5:N4}** | **{6:N2}** | |' -f `
            $totalTurns, $totalInput, $totalCached, $totalCacheWrite, $totalOutput, $totalCost, $totalCredits))
if ($observed -and $null -ne $observed.SessionAiu -and $observed.SessionAiu -gt 0) {
    $billedUsd = $observed.SessionAiu * 0.01
    $fragmentLines.Add('')
    $fragmentLines.Add(('> **Billed by the host for this session so far: {0:N2} AI units, about {1:N2} USD.** The estimate above is {2:N2}x that figure. Estimates come from dispatch-size guesses; the billed figure is the host''s own count, coordinator included. See *Observed Usage (host-reported)* below.' -f $observed.SessionAiu, $billedUsd, ($totalCost / $billedUsd)))
}
$fragmentLines.Add('')
$fragmentLines.Add('### Derivation')
$fragmentLines.Add('')
$fragmentLines.Add('```text')
foreach ($line in $enumerationLines) { $fragmentLines.Add($line) }
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
$fragmentLines.Add('```')

if ($Write) {
    # Both updates are computed before either file is written, so a refusal on
    # one never leaves the other half-applied.
    $updates = @(
        Get-ConsumptionFragmentUpdateLocal -ConsumptionPath $consumptionPath -FragmentLines $fragmentLines.ToArray()
        Get-StateRunTotalUpdateLocal -StatePath $statePath -CostUsd $totalCost -Credits $totalCredits
    )
    if ($observed) {
        $updates[0].Text = Get-ConsumptionWithObservedLocal -Text $updates[0].Text -SectionLines (Get-ObservedSectionLinesLocal -Observed $observed)
    }
    foreach ($u in $updates) { [System.IO.File]::WriteAllText($u.Path, $u.Text, $u.Encoding) }
    foreach ($w in $warnings) { Write-Warning $w }
    Write-Host ("Measure-SquadLedger -Write: rewrote the Attribution, Usage & Cost, and Derivation sections of consumption.md and set run totals in state.json (estCostUsd={0:F4}, estCreditsTotal={1:F2})." -f $totalCost, $totalCredits) -ForegroundColor Green
    exit 0
}

if ($Format -eq 'json') {
    $result = [ordered]@{
        squadRoot         = $SquadRoot
        calibrationFactor = $calibrationFactor
        attribution       = @(
            foreach ($agg in $roleAggregates) {
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
            foreach ($agg in $roleAggregates) {
                [ordered]@{
                    role       = $agg.Label
                    turns      = $agg.Turns
                    input      = $agg.Input
                    cached     = $agg.Cached
                    cacheWrite = $agg.CacheWrite
                    output     = $agg.Output
                    estCostUsd = [math]::Round($agg.Cost, 4)
                    estCredits = [math]::Round($agg.Cost / 0.01, 2)
                    basis      = $agg.Basis
                }
            }
        )
        total             = [ordered]@{
            turns      = $totalTurns
            input      = $totalInput
            cached     = $totalCached
            cacheWrite = $totalCacheWrite
            output     = $totalOutput
            estCostUsd = [math]::Round($totalCost, 4)
            estCredits = [math]::Round($totalCredits, 2)
        }
        historyCounts     = $historyCounts
        stateEstCostUsd   = $stateCostUsd
        stateEstCredits   = $stateCreditsTotal
        observed          = if ($observed) {
            [ordered]@{
                sessionId       = $observed.Session.SessionId
                sessionLog      = $observed.Session.Path
                sessionAiu      = $observed.SessionAiu
                observedTokens  = $observed.ObservedTokens
                estimatedTokens = $observed.EstimatedTokens
                blendedCostUsd  = [math]::Round($observed.SquadCostUsd, 4)
                baselineModel   = $observed.BaselineModel
                baselineCostUsd = if ($null -ne $observed.BaselineCostUsd) { [math]::Round($observed.BaselineCostUsd, 4) } else { $null }
                agents          = @(
                    foreach ($r in $observed.Rows) {
                        [ordered]@{ agent = $r.Agent; dispatches = $r.Dispatches; observedModels = @($r.ObservedModels); ledgerModels = @($r.LedgerModels); match = $r.Match; observedTokens = $r.Tokens; estimatedTokens = $r.Estimated; blendedCostUsd = [math]::Round($r.CostUsd, 4) }
                    }
                )
            }
        }
        else { $null }
        warnings          = @($warnings)
    }
    $result | ConvertTo-Json -Depth 6
    exit 0
}

foreach ($line in $fragmentLines) { Write-Host $line }
if ($observed) {
    Write-Host ''
    foreach ($line in (Get-ObservedSectionLinesLocal -Observed $observed)) { Write-Host $line }
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
Write-Verbose ("Copy these derived totals into currentRun inside state.json: estCostUsd={0:N4}, estCreditsTotal={1:N2}." -f $totalCost, $totalCredits)
