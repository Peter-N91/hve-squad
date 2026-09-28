#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Verifies a squad root's Scribe write completeness against an expectation, usable
    on any squad root (federation root or member sub-squad).
.DESCRIPTION
    This is the P00-T04 write-completeness verifier (routing-performance plan
    amendment-1, condition #39, OBJ-12). It never asserts on rule content or wording;
    it asserts only that the Scribe's turn actually happened end-to-end:

    * every expected decision heading exists in decisions.md,
    * every expected history entry exists (`###` dispatch-entry count per agent file
      is at or above the expectation),
    * every consumption JSON block found carries the ten contractual fields, in the
      contractual order, with no parse error and no non-numeric value,
    * consumption.md's Usage & Cost Total row's raw columns (turns, in/cached/cache
      write/output tokens) equal the sum of the consumption blocks behind them within
      -LedgerTolerance, and its cost column equals those blocks priced at the squad
      root's own consumption-rates.md within the same tolerance (the ledger is
      rewritten from the full history, so only display rounding may differ),
    * state.json parses, schemaVersion is unchanged, and turn/updated/activeRoles
      advanced at least as far as expected,
    * every deliverable path a dispatch entry names exists on disk (resolved against
      the squad root, its ancestors up to the repository root, and the previous
      path's directory for comma-list shorthand; `*` globs allowed) and was last
      written no more than -TimeWindowMinutes before that entry's own timestamp -- the
      write-completeness core (OBJ-12): a Scribe write that records an entry but drops
      (or never writes) the file behind it is exactly what this line exists to catch.
      A later write is accepted because append-only shared files are touched again.

    Never asserts on rule wording, never invokes a model, no network access anywhere
    in this script.
.PARAMETER SquadRoot
    Path to a squad root: `.copilot-tracking/squad/` or a member sub-squad root such
    as `.copilot-tracking/squad/members/<name>/`.
.PARAMETER ExpectationPath
    Path to a JSON expectation file. See the comment-based EXAMPLE below for its
    shape. Individual -DecisionHeadings/-HistoryMinCounts/... parameters are read
    only when this is omitted.
.PARAMETER TimeWindowMinutes
    How many minutes a deliverable file's last-write-time may precede its declared
    history-entry timestamp and still count as backing that entry. Defaults
    to 180 minutes -- generous enough for a slow dispatch, tight enough to catch a
    file that was never actually touched this turn.
.PARAMETER LedgerTolerance
    Relative error the consumption.md Total row may carry against the sum of the
    history blocks (token columns) and against those blocks priced at the squad
    root's consumption-rates.md (cost column). Defaults to 0.01 (1%).
.PARAMETER OutputPath
    Optional path to also write the structured result object as JSON.
.EXAMPLE
    ./scripts/Test-SquadScribeOutput.ps1 -SquadRoot .copilot-tracking/squad -ExpectationPath tests/fixtures/scribe-benchmark/expected.json
.NOTES
    Expectation JSON shape:
    {
      "decisionHeadings": ["Council Verdict"],
      "decisionContains": ["two-role"],
      "historyMinCounts": { "Squad Researcher": 1 },
      "schemaVersion": "1.4",
      "minTurn": 2,
      "updatedNotBefore": "2026-09-27T00:00:00Z",
      "expectedActiveRoles": ["Squad Scribe"],
      "timeWindowMinutes": 180
    }
    See .copilot-tracking/squad/members/routing-performance/plans/2026-09-27-routing-performance-plan-amendment-1.md
    (P00-T04, OBJ-12, condition #39) for this script's contract.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'DecisionHeadings',
    Justification = 'Read only when -ExpectationPath is omitted; PSScriptAnalyzer cannot see the conditional use.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'DecisionContains',
    Justification = 'Read only when -ExpectationPath is omitted; PSScriptAnalyzer cannot see the conditional use.')]
param(
    [Parameter(Mandatory)]
    [string]$SquadRoot,

    [string]$ExpectationPath,

    [string[]]$DecisionHeadings = @(),

    [string[]]$DecisionContains = @(),

    [hashtable]$HistoryMinCounts = @{},

    [string]$SchemaVersion,

    [int]$MinTurn,

    [string]$UpdatedNotBefore,

    [string[]]$ExpectedActiveRoles = @(),

    [int]$TimeWindowMinutes = 180,

    [ValidateRange(0.0, 1.0)]
    [double]$LedgerTolerance = 0.01,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'tests', 'tier1', 'SquadState.psm1') -Force

if (-not (Test-Path -LiteralPath $SquadRoot)) {
    throw "Test-SquadScribeOutput: squad root not found at '$SquadRoot'."
}
$SquadRoot = (Resolve-Path -LiteralPath $SquadRoot).Path

function ConvertTo-Utc {
    <#
    .SYNOPSIS
        Converts a timestamp value to a UTC [datetimeoffset], safely, regardless of
        whether it arrived as a raw ISO-8601 string or as a [datetime] that
        ConvertFrom-Json's built-in date-pattern auto-detection already produced
        (this happens silently for any JSON string that looks like an ISO timestamp,
        e.g. state.json's `updated` field or an expectation file's
        `updatedNotBefore`, but never for non-date-shaped strings like
        schemaVersion "1.4").

        This function exists because the naive fix -- stringifying that auto-
        produced [datetime] via interpolation ("$value") and re-parsing it -- uses
        the current culture's default format (e.g. en-US "MM/dd/yyyy HH:mm:ss" or
        fr-FR "dd/MM/yyyy HH:mm:ss") with no timezone marker, which a
        [datetimeoffset]::TryParse under a *different* culture can silently
        misparse or reject outright, corrupting the comparison. Converting the
        [datetime] object directly (preserving its already-correct Kind) and
        parsing raw strings with InvariantCulture + AssumeUniversal avoids both
        failure modes.
    #>
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetimeoffset]) { return $Value.ToUniversalTime() }
    if ($Value -is [datetime]) { return ([datetimeoffset]$Value).ToUniversalTime() }
    $parsed = [datetimeoffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetimeoffset]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

if ($ExpectationPath) {
    $expectation = Get-Content -LiteralPath $ExpectationPath -Raw | ConvertFrom-Json -AsHashtable
    $DecisionHeadings = @($expectation['decisionHeadings'] | Where-Object { $_ })
    $DecisionContains = @($expectation['decisionContains'] | Where-Object { $_ })
    $HistoryMinCounts = if ($expectation.ContainsKey('historyMinCounts')) { $expectation['historyMinCounts'] } else { @{} }
    $SchemaVersion = $expectation['schemaVersion']
    $MinTurn = if ($expectation.ContainsKey('minTurn')) { [int]$expectation['minTurn'] } else { 0 }
    # Normalize through ConvertTo-Utc + the round-trip 'o' format immediately: the
    # raw value may already be a [datetime] (ConvertFrom-Json's silent date-pattern
    # auto-detection) rather than a string, and assigning that straight into this
    # [string]-typed parameter would otherwise invoke a culture-dependent, offset-
    # free ToString() that a later TryParse can misparse under a non-US culture.
    $updatedNotBeforeRaw = $expectation['updatedNotBefore']
    $UpdatedNotBefore = if ($updatedNotBeforeRaw) {
        $normalized = ConvertTo-Utc $updatedNotBeforeRaw
        if ($normalized) { $normalized.ToString('o') } else { "$updatedNotBeforeRaw" }
    }
    else { $null }
    $ExpectedActiveRoles = @($expectation['expectedActiveRoles'])
    if ($expectation.ContainsKey('timeWindowMinutes')) { $TimeWindowMinutes = [int]$expectation['timeWindowMinutes'] }
}

$model = Get-SquadStateModel -SquadRoot $SquadRoot

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $checks.Add([pscustomobject]@{ name = $Name; passed = $Passed; detail = $Detail })
}

# ---------------------------------------------------------------------------
# 1. Expected decision headings exist
# ---------------------------------------------------------------------------

foreach ($heading in $DecisionHeadings) {
    $pattern = '(?m)^##\s+' + [regex]::Escape($heading) + '\b'
    $found = [bool]($model.Decisions -and ([regex]::IsMatch($model.Decisions, $pattern)))
    Add-Check -Name "decision heading '$heading' exists" -Passed $found -Detail $(if (-not $found) { "no '## $heading ...' heading found in decisions.md" } else { 'found' })
}

# The Scribe chooses the heading wording, so a payload that supplies no label is
# checked by content: some `## ` entry body must carry the decision text.
$decisionSections = if ($model.Decisions) { @([regex]::Split($model.Decisions, '(?m)^(?=##\s)') | Where-Object { $_ -match '^##\s' }) } else { @() }
foreach ($text in $DecisionContains) {
    $found = [bool]($decisionSections | Where-Object { $_.IndexOf($text, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 1)
    Add-Check -Name "decision entry containing '$text' exists" -Passed $found -Detail $(if (-not $found) { "no '## ' entry in decisions.md contains '$text'" } else { 'found' })
}

# ---------------------------------------------------------------------------
# 2. Expected history entry counts (### dispatch-entry headings per agent file)
# ---------------------------------------------------------------------------

foreach ($agent in $HistoryMinCounts.Keys) {
    $expectedCount = [int]$HistoryMinCounts[$agent]
    $historyFile = $model.HistoryFiles | Where-Object { $_.BaseName -eq $agent } | Select-Object -First 1
    $actualCount = 0
    if ($historyFile) {
        $raw = Get-Content -LiteralPath $historyFile.FullName -Raw
        $actualCount = @([regex]::Matches($raw, '(?m)^###\s+')).Count
    }
    $passed = $actualCount -ge $expectedCount
    Add-Check -Name "history/$agent.md has >= $expectedCount entries" -Passed $passed -Detail "found $actualCount"
}

# ---------------------------------------------------------------------------
# 3. Every consumption block carries the 10 contractual fields, in order
# ---------------------------------------------------------------------------

if ($model.Blocks.Count -eq 0) {
    Add-Check -Name 'at least one consumption block present' -Passed $false -Detail 'history/ contains no #### Consumption block at all'
}
else {
    foreach ($block in $model.Blocks) {
        $orderOk = ($block.Order -join '|') -eq ($model.ConsumptionFields -join '|')
        $noParseError = -not $block.ParseError
        $noNonNumeric = $block.NonNumeric.Count -eq 0
        $passed = $orderOk -and $noParseError -and $noNonNumeric
        $detail = if ($passed) {
            'ok'
        }
        else {
            $reasons = @()
            if (-not $orderOk) { $reasons += "field order was [$($block.Order -join ', ')]" }
            if (-not $noParseError) { $reasons += "JSON parse error: $($block.ParseError)" }
            if (-not $noNonNumeric) { $reasons += "non-numeric field(s): $($block.NonNumeric -join ', ')" }
            $reasons -join '; '
        }
        Add-Check -Name "$($block.Source) consumption block carries the 10 contractual fields in order" -Passed $passed -Detail $detail
    }
}

# ---------------------------------------------------------------------------
# 4. consumption.md ledger total is within an order of magnitude of the blocks
# ---------------------------------------------------------------------------

function Test-LedgerBand {
    <#
    .SYNOPSIS
        Relative reconciliation band. The ledger is rewritten from the full history,
        so it should equal the sum of blocks up to display rounding: -Tolerance is the
        allowed relative error (default 1%), -Floor an absolute allowance for tiny sums.
        StateContract.Tests.ps1's order-of-magnitude band is a structural test of the
        shipped seed; this script verifies a live write and is deliberately tighter.
    #>
    param([double]$Actual, [double]$Expected, [double]$Tolerance = 0.01, [double]$Floor = 0.5)
    return ([math]::Abs($Actual - $Expected) -le [math]::Max($Floor, [math]::Abs($Expected) * $Tolerance))
}

if (-not $model.Ledger) {
    Add-Check -Name 'consumption.md ledger total reconciles with blocks' -Passed $false -Detail 'consumption.md is empty or missing'
}
else {
    $totalRow = @($model.UsageAndCost | Where-Object { $_[0] -match 'Total' }) | Select-Object -First 1
    if (-not $totalRow) {
        Add-Check -Name 'consumption.md ledger total reconciles with blocks' -Passed $false -Detail 'no Total row found in the Usage & Cost table'
    }
    else {
        foreach ($column in @(
                @{ Name = 'Turns'; Index = 1; Field = 'internal_turns' }
                @{ Name = 'In Tokens'; Index = 2; Field = 'input_tokens' }
                @{ Name = 'Cached'; Index = 3; Field = 'cached_tokens' }
                @{ Name = 'Cache Wr'; Index = 4; Field = 'cache_write_tokens' }
                @{ Name = 'Out Tokens'; Index = 5; Field = 'output_tokens' }
            )) {
            $expected = ($model.Blocks | ForEach-Object { $_.Fields[$column.Field] } | Measure-Object -Sum).Sum
            if (-not $expected) { $expected = 0 }
            $actual = ConvertTo-LedgerNumber $totalRow[$column.Index]
            $passed = Test-LedgerBand -Actual $actual -Expected $expected -Tolerance $LedgerTolerance
            Add-Check -Name "ledger Total $($column.Name) column reconciles with blocks" -Passed $passed -Detail "ledger says $actual against blocks summing to $expected"
        }

        # The ledger's cost is recomputed here from the squad root's own rate table, so
        # an arithmetic slip is caught even when every token column reconciles.
        $expectedCost = 0.0
        $unpriced = [System.Collections.Generic.List[string]]::new()
        foreach ($block in $model.Blocks) {
            $rate = if ($block.Fields['priced_as']) { $model.Rates[[string]$block.Fields['priced_as']] }
            if (-not $rate) { $unpriced.Add("$($block.Source):$($block.Fields['priced_as'])"); continue }
            $expectedCost += (([double]$block.Fields['input_tokens'] * $rate.input) + ([double]$block.Fields['cached_tokens'] * $rate.cached) +
                ([double]$block.Fields['cache_write_tokens'] * $rate.cache_write) + ([double]$block.Fields['output_tokens'] * $rate.output)) / 1e6
        }
        if ($unpriced.Count -gt 0) {
            Add-Check -Name 'ledger Total cost reconciles with blocks priced at consumption-rates.md' -Passed $false -Detail "no rate row for: $($unpriced -join ', ')"
        }
        elseif ($totalRow.Count -gt 6) {
            $actualCost = ConvertTo-LedgerNumber $totalRow[6]
            $passed = ($null -ne $actualCost) -and (Test-LedgerBand -Actual $actualCost -Expected $expectedCost -Tolerance $LedgerTolerance -Floor 0.01)
            Add-Check -Name 'ledger Total cost reconciles with blocks priced at consumption-rates.md' -Passed $passed -Detail ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, 'ledger says {0} against blocks pricing to {1:N4}', $actualCost, $expectedCost))
        }
    }
}

# ---------------------------------------------------------------------------
# 5. state.json parses, schemaVersion unchanged, turn/updated/activeRoles advanced
# ---------------------------------------------------------------------------

$stateParsed = $null -ne $model.State
Add-Check -Name 'state.json parses' -Passed $stateParsed -Detail $(if (-not $stateParsed) { 'ConvertFrom-Json failed or state.json is missing' } else { 'ok' })

if ($stateParsed) {
    if ($SchemaVersion) {
        $actualSchema = "$($model.State['schemaVersion'])"
        Add-Check -Name "schemaVersion unchanged (expected '$SchemaVersion')" -Passed ($actualSchema -eq $SchemaVersion) -Detail "actual '$actualSchema'"
    }

    if ($MinTurn -gt 0) {
        $actualTurn = [int]$model.State['turn']
        Add-Check -Name "turn advanced to at least $MinTurn" -Passed ($actualTurn -ge $MinTurn) -Detail "actual $actualTurn"
    }

    if ($UpdatedNotBefore) {
        $actualUpdated = ConvertTo-Utc $model.State['updated']
        $expectedUpdated = ConvertTo-Utc $UpdatedNotBefore
        $bothParse = ($null -ne $actualUpdated) -and ($null -ne $expectedUpdated)
        $passed = $bothParse -and ($actualUpdated -ge $expectedUpdated)
        $actualUpdatedText = if ($actualUpdated) { $actualUpdated.ToString('o') } else { "$($model.State['updated'])" }
        Add-Check -Name "updated advanced to at least $UpdatedNotBefore" -Passed $passed -Detail "actual '$actualUpdatedText'"
    }

    if ($ExpectedActiveRoles.Count -gt 0) {
        $actualRoles = @($model.State['activeRoles'])
        $missing = @($ExpectedActiveRoles | Where-Object { $_ -notin $actualRoles })
        Add-Check -Name 'activeRoles advanced to include every expected role' -Passed ($missing.Count -eq 0) -Detail $(if ($missing.Count -gt 0) { "missing: $($missing -join ', ')" } else { 'ok' })
    }
}

# ---------------------------------------------------------------------------
# 6. OBJ-12 write-completeness: every declared deliverable exists and was written
#    within its own entry's declared time window
# ---------------------------------------------------------------------------

function Get-DispatchEntryTimestamp {
    <#
    .SYNOPSIS
        Local, thin extraction of the `### <timestamp> <title>` heading's timestamp
        token, kept separate from SquadState.psm1 because no exported function there
        correlates an entry's own timestamp with the deliverable paths inside its
        body -- Get-HistoryEntry and Get-DeliverableEntry are read independently and
        are not indexed against each other.
    #>
    param([string]$HeadingText)
    $match = [regex]::Match($HeadingText, '^(?<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))')
    if ($match.Success) { return $match.Groups['ts'].Value }
    return $null
}

$writeCompletenessFindings = [System.Collections.Generic.List[string]]::new()
$dispatchHistoryFiles = @($model.HistoryFiles | Where-Object { $_.BaseName -ne 'Squad Scribe' -and $_.BaseName -notmatch '^(autonomous-loop|autopilot-run)-' })

foreach ($file in $dispatchHistoryFiles) {
    $raw = Get-Content -LiteralPath $file.FullName -Raw
    $headings = @([regex]::Matches($raw, '(?m)^###[ \t]+(?<title>.+)$'))

    for ($index = 0; $index -lt $headings.Count; $index++) {
        $start = $headings[$index].Index
        $end = if ($index + 1 -lt $headings.Count) { $headings[$index + 1].Index } else { $raw.Length }
        $body = $raw.Substring($start, $end - $start)
        $title = $headings[$index].Groups['title'].Value.Trim()
        $timestampText = Get-DispatchEntryTimestamp -HeadingText $title

        $deliverableLine = [regex]::Match($body, '(?m)^\s*\*\s*Deliverable:\s*(?<value>.+)$')
        if (-not $deliverableLine.Success) { continue }
        $paths = @([regex]::Matches($deliverableLine.Groups['value'].Value, '`(?<path>[^`]+)`') | ForEach-Object { $_.Groups['path'].Value })
        if ($paths.Count -eq 0) { continue }

        $entryTime = $null
        if ($timestampText) {
            $parsed = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse($timestampText, [ref]$parsed)) { $entryTime = $parsed }
        }

        $previousResolved = $null
        foreach ($path in $paths) {
            $relative = $path -replace '^\./', ''
            # Entries name deliverables relative to the squad root, the repository root,
            # or -- in a comma list -- a sibling of the previous path, so each ancestor
            # of those anchors is tried before declaring the file missing.
            $bases = [System.Collections.Generic.List[string]]::new()
            foreach ($anchor in @($SquadRoot, $(if ($previousResolved) { Split-Path -Parent $previousResolved }))) {
                $cursor = $anchor
                while ($cursor) {
                    if (-not $bases.Contains($cursor)) { $bases.Add($cursor) }
                    if (Test-Path -LiteralPath (Join-Path $cursor '.git')) { break }
                    $cursor = Split-Path -Parent $cursor
                }
            }
            $resolved = $null
            foreach ($base in $bases) {
                $candidate = Join-Path $base $relative
                if ($relative -match '[*?]') {
                    $match = Get-ChildItem -Path $candidate -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
                    if ($match) { $resolved = $match.FullName; break }
                }
                elseif (Test-Path -LiteralPath $candidate) { $resolved = (Get-Item -LiteralPath $candidate).FullName; break }
            }
            if ($resolved) { $previousResolved = $resolved }

            if (-not $resolved) {
                $writeCompletenessFindings.Add("$($file.BaseName): '$title' declares '$path' which does not exist on disk")
                continue
            }

            if ($entryTime) {
                # Append-only shared files (decisions.md, state.json, history) are legitimately
                # touched again by later entries, so only a file last written well BEFORE its
                # entry -- one this dispatch never touched -- is a finding.
                $mtime = [datetimeoffset](Get-Item -LiteralPath $resolved).LastWriteTimeUtc
                $delta = ($entryTime - $mtime).TotalMinutes
                if ($delta -gt $TimeWindowMinutes) {
                    $writeCompletenessFindings.Add("$($file.BaseName): '$title' declares '$path' last written $([math]::Round($delta)) minutes before its own timestamp, outside the $TimeWindowMinutes-minute window")
                }
            }
        }
    }
}

Add-Check -Name 'every declared deliverable exists and was written inside its entry''s time window (OBJ-12)' -Passed ($writeCompletenessFindings.Count -eq 0) -Detail $(if ($writeCompletenessFindings.Count -gt 0) { $writeCompletenessFindings -join ' | ' } else { 'ok' })

# ---------------------------------------------------------------------------
# 7. Assemble result, write, exit
# ---------------------------------------------------------------------------

$failures = @($checks | Where-Object { -not $_.passed } | ForEach-Object { "$($_.name): $($_.detail)" })
$passed = $failures.Count -eq 0

$result = [ordered]@{
    squadRoot = $SquadRoot -replace '\\', '/'
    passed    = $passed
    checks    = $checks
    failures  = $failures
}

$resultObject = [pscustomobject]$result

if ($OutputPath) {
    Set-Content -LiteralPath $OutputPath -Value ($result | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM
}

$resultObject
if (-not $passed) { exit 1 }
exit 0
