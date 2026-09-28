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
    files it re-derives, so a consumer with the skill installed already has it. It is
    read-only: it never writes `consumption.md`, `consumption-rates.md`, or any other
    squad-state file. The Scribe remains the single writer of squad state; this script
    only computes what the Scribe should write, or checks what it did write.

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
    is also supplied.
.PARAMETER Format
    Output shape: `markdown` (default) prints the pasteable table and Derivation
    block; `json` prints the same figures as a structured object instead, for a
    caller that wants to consume them programmatically rather than paste them.
.EXAMPLE
    ./Measure-SquadLedger.ps1 -SquadRoot .copilot-tracking/squad/members/routing-performance
.EXAMPLE
    ./Measure-SquadLedger.ps1 -SquadRoot .copilot-tracking/squad -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 1; 'Squad Scribe' = 1 }
.NOTES
    See .copilot-tracking/squad/members/routing-performance/changes/2026-09-28-d6b-ledger-tool.md
    for this script's contract and the benchmark regression it remedies.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SquadRoot,

    [switch]$Check,

    [hashtable]$ExpectedHistoryCounts = @{},

    [ValidateSet('markdown', 'json')]
    [string]$Format = 'markdown'
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
    if (-not $Content) { return [pscustomobject]@{ ByModel = $byModel; ByTier = $byTier } }

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
                if ($rate.tier -and -not $byTier.ContainsKey($rate.tier)) { $byTier[$rate.tier] = $rate }
            }
            else {
                # Per-model table read first, so it stays authoritative over any
                # tier-fallback duplicate of the same model name.
                $byModel[$key] = $rate
                if ('Tier' -in $table.Header -and $row['Tier'] -and -not $byTier.ContainsKey($row['Tier'])) {
                    $byTier[$row['Tier']] = $rate
                }
            }
        }
    }

    [pscustomobject]@{ ByModel = $byModel; ByTier = $byTier }
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

        foreach ($row in $table.Rows) {
            $names = [System.Collections.Generic.List[string]]::new()
            foreach ($column in @('Agent Name (Primary)', 'Alternate Agents')) {
                if ($column -notin $table.Header) { continue }
                foreach ($name in ($row[$column] -split ',')) {
                    $trimmed = $name.Trim()
                    if ($trimmed -and $trimmed -ne '—' -and $trimmed -ne '-') { $names.Add($trimmed) }
                }
            }
            if (-not $row['Role']) { continue }
            $memberName = if ('Member Name' -in $table.Header) { $row['Member Name'] } else { '' }
            $primaryAgent = if ('Agent Name (Primary)' -in $table.Header) { $row['Agent Name (Primary)'] } else { '' }
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
                Failures = @("History identity guard: consumption.md's ### Derivation block records no history-entry identities. This is the Scribe's post-write self-check (-ExpectedHistoryCounts was supplied), which always follows a fresh write, so a missing Derivation here is a bad paste, not a legacy ledger -- paste the helper's Derivation verbatim including identity lines.")
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
        $recordedByFile[$fileName] = if (-not $idsText -or $idsText -eq '(none)') { @() } else { @($idsText -split ',' | ForEach-Object { $_.Trim() }) }
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
            $failures.Add("History identity guard: $message This is the Scribe's post-write self-check, so a partial paste must not pass -- paste the helper's Derivation verbatim including identity lines for every history file, not just some.")
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

    foreach ($match in [regex]::Matches($Content, $pattern)) {
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
        `priced_as` row when it resolves, otherwise the block's `model_tier` row
        (flagged), and never a fabricated or zero rate.
    #>
    param(
        [Parameter(Mandatory)]$Block,
        [Parameter(Mandatory)]$Rates,
        # Not [Parameter(Mandatory)]: PowerShell's binder rejects an empty
        # collection argument for a Mandatory collection-typed parameter, and an
        # accumulator list legitimately starts empty on a run with no warnings.
        [System.Collections.Generic.List[string]]$Warnings
    )

    $pricedAs = [string]$Block.Fields['priced_as']
    if ($pricedAs -and $Rates.ByModel.ContainsKey($pricedAs)) {
        return $Rates.ByModel[$pricedAs]
    }

    $tier = [string]$Block.Fields['model_tier']
    if ($tier -and $Rates.ByTier.ContainsKey($tier)) {
        $Warnings.Add("WARN: $($Block.Source): priced_as '$pricedAs' has no rate row; priced at the '$tier' tier fallback instead.")
        return $Rates.ByTier[$tier]
    }

    throw "Measure-SquadLedger: block in '$($Block.Source)' has priced_as '$pricedAs' and model_tier '$tier', neither of which resolves to a rate row. Refusing to price at 0 -- fix consumption-rates.md or the block."
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
        [System.Collections.Generic.List[string]]$Warnings
    )

    $rate = Resolve-RateForBlockLocal -Block $Block -Rates $Rates -Warnings $Warnings

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
    param([Parameter(Mandatory)][string]$Role, [Parameter(Mandatory)][string]$Agent)
    '{0}|{1}' -f $Role.Trim().ToLowerInvariant(), $Agent.Trim().ToLowerInvariant()
}

# ---------------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $SquadRoot -PathType Container)) {
    throw "Measure-SquadLedger: squad root not found at '$SquadRoot'."
}
$SquadRoot = (Resolve-Path -LiteralPath $SquadRoot).Path

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

$warnings = [System.Collections.Generic.List[string]]::new()
$parseErrors = [System.Collections.Generic.List[string]]::new()
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
        if ($block.ParseError) {
            $parseErrors.Add("$($block.Source): JSON parse error: $($block.ParseError)")
            continue
        }
        if (-not $block.OrderOk) {
            $parseErrors.Add("$($block.Source): field order/set does not match the contractual ten fields (got: $($block.Order -join ', '))")
            continue
        }
        if ($block.NonNumeric.Count -gt 0) {
            $parseErrors.Add("$($block.Source): non-numeric value in field(s): $($block.NonNumeric -join ', ')")
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
            Add-BlockToAggregateLocal -Aggregate $orchestrationAggregate -Block $block -Rates $rates -CalibrationFactor $calibrationFactor -Warnings $warnings
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
        Add-BlockToAggregateLocal -Aggregate $existing.Aggregate -Block $block -Rates $rates -CalibrationFactor $calibrationFactor -Warnings $warnings
    }
}

if ($parseErrors.Count -gt 0) {
    foreach ($e in $parseErrors) { Write-Warning $e }
    throw "Measure-SquadLedger: $($parseErrors.Count) consumption block(s) failed to parse or validate; see warnings above. Refusing to compute a ledger from unreadable blocks."
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
        $legalModelSources = @('cli-pinned', 'operator-declared', 'dispatch-reported', 'agent-pinned', 'session-inherited', 'unresolved')

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
                $candidates = if ($ledgerRowsByRole.ContainsKey($roleKeyLower)) { $ledgerRowsByRole[$roleKeyLower] } else { @() }
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
# Output (markdown, pasteable into consumption.md; or json).
# ---------------------------------------------------------------------------

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
        warnings          = @($warnings)
    }
    $result | ConvertTo-Json -Depth 6
    exit 0
}

Write-Host '## Attribution'
Write-Host ''
Write-Host '| Role | Member | Agent | Model | Model Source | Priced As | Tier |'
Write-Host '| ---- | ------ | ----- | ----- | ------------ | --------- | ---- |'
foreach ($agg in $roleAggregates) {
    Write-Host ('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f `
            $agg.Label, $agg.Member, $agg.Agent, ($agg.Models -join ', '), ($agg.ModelSources -join ', '), ($agg.PricedAsUsed -join ', '), $agg.Tier)
}
Write-Host ''
Write-Host '## Usage & Cost'
Write-Host ''
Write-Host '| Role | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis |'
Write-Host '| ---- | ----- | --------- | ------ | -------- | ---------- | ---------------- | ------------ | ----- |'
foreach ($agg in $roleAggregates) {
    Write-Host ('| {0} | {1:N0} | {2:N0} | {3:N0} | {4:N0} | {5:N0} | {6:N4} | {7:N2} | {8} |' -f `
            $agg.Label, $agg.Turns, $agg.Input, $agg.Cached, $agg.CacheWrite, $agg.Output, $agg.Cost, ($agg.Cost / 0.01), $agg.Basis)
}
Write-Host ('| **Total** | **{0:N0}** | **{1:N0}** | **{2:N0}** | **{3:N0}** | **{4:N0}** | **{5:N4}** | **{6:N2}** | |' -f `
        $totalTurns, $totalInput, $totalCached, $totalCacheWrite, $totalOutput, $totalCost, $totalCredits)
Write-Host ''
Write-Host '### Derivation'
Write-Host ''
Write-Host '```text'
foreach ($line in $enumerationLines) { Write-Host $line }
foreach ($agg in $roleAggregates) {
    if ($agg.Blocks.Count -eq 0) { continue }
    $firstRate = $agg.Blocks[0].Rate
    $mismatch = @($agg.Blocks | Where-Object { $_.Rate.input -ne $firstRate.input -or $_.Rate.output -ne $firstRate.output }).Count -gt 0
    if ($mismatch) {
        Write-Host "NOTE: $($agg.Label) blocks priced at more than one rate; the line below uses the first block's rate over the aggregated tokens, but the role's Cost column above sums each block at its own rate."
    }

    $turnsPerBlock = @($agg.Blocks | ForEach-Object { [double]$_.Block.Fields['internal_turns'] })
    $turnsExpr = if ($turnsPerBlock.Count -gt 1) { "$($turnsPerBlock -join '+')=$($agg.Turns)" } else { "$($agg.Turns)" }

    $rawSum = [math]::Round($agg.Input * $firstRate.input + $agg.Cached * $firstRate.cached + $agg.CacheWrite * $firstRate.cache_write + $agg.Output * $firstRate.output, 4)
    $rawLine = '{0} × {1:N2} + {2} × {3:N2} + {4} × {5:N2} + {6} × {7:N2} = {8} / 1e6 = {9:N4}' -f $agg.Input, $firstRate.input, $agg.Cached, $firstRate.cached, $agg.CacheWrite, $firstRate.cache_write, $agg.Output, $firstRate.output, $rawSum, $agg.Cost
    Write-Host ("{0,-14} turns {1,-12} {2}" -f $agg.Label, $turnsExpr, $rawLine)
}
Write-Host ("{0,-14} {1,-12} {2,-59} total = {3:N4}" -f '', '', '', $totalCost)
Write-Host '```'

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
