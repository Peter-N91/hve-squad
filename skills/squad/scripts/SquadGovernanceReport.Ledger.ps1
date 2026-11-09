# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

# Dot-sourced by SquadGovernanceReport.psm1. Reads a consumption ledger as a document and
# recognizes only what the headline figures need, by header text and never by position.
# Everything else in the ledger is rendered verbatim by the HTML layer, so a ledger that
# gains a section or a column needs no change here to be shown in full; a figure whose
# header this layer no longer recognizes degrades to "not derivable", never to a guess.

Set-StrictMode -Version Latest

# 1 AI credit = 0.01 USD is the ledger's own fixed conversion (consumption-rates.md).
$script:SqUsdPerCredit = [decimal]0.01

function Get-SqCell {
    param([AllowNull()][object[]]$Row, [int]$Index)
    if ($null -eq $Row -or $Index -lt 0 -or $Index -ge $Row.Count) { return '' }
    [string]$Row[$Index]
}

function Get-SqUsageColumns {
    <#
    .SYNOPSIS
        Maps a ledger table's headers to the meanings the economics need (any may be absent).
    #>
    param([Parameter(Mandatory)][object[]]$Headers)
    [pscustomobject]@{
        Role     = (Find-SqColumn $Headers '^Role$')
        Turns    = (Find-SqColumn $Headers '^(Turns|Requests)$')
        In       = (Find-SqColumn $Headers '^In(put)?( Tokens)?$')
        Cached   = (Find-SqColumn $Headers '^(Cached( Tokens)?|Cache Read)$')
        CacheWr  = (Find-SqColumn $Headers '^Cache[ -]?(Wr|Write)')
        Out      = (Find-SqColumn $Headers '^Out(put)?( Tokens)?$')
        CostUsd  = (Find-SqColumn $Headers 'Cost.*USD|^Cost$')
        Credits  = (Find-SqColumn $Headers 'Credits')
        Basis    = (Find-SqColumn $Headers '^Basis$')
    }
}

function ConvertTo-SqUsageRow {
    param([Parameter(Mandatory)][object[]]$Cells, [Parameter(Mandatory)]$Columns)
    $role = ConvertTo-SqPlainText (Get-SqCell $Cells $Columns.Role)
    [pscustomobject]@{
        Role    = $(if ($role) { $role } else { '(unlabeled)' })
        Turns   = (ConvertTo-SqDecimal (Get-SqCell $Cells $Columns.Turns))
        In      = (ConvertTo-SqDecimal (Get-SqCell $Cells $Columns.In))
        Cached  = (ConvertTo-SqDecimal (Get-SqCell $Cells $Columns.Cached))
        CacheWr = (ConvertTo-SqDecimal (Get-SqCell $Cells $Columns.CacheWr))
        Out     = (ConvertTo-SqDecimal (Get-SqCell $Cells $Columns.Out))
        Usd     = (ConvertTo-SqDecimal (Get-SqCell $Cells $Columns.CostUsd))
        Credits = (ConvertTo-SqDecimal (Get-SqCell $Cells $Columns.Credits))
        Basis   = ((ConvertTo-SqPlainText (Get-SqCell $Cells $Columns.Basis)).ToLowerInvariant())
    }
}

function Get-SqRowTokens {
    param([Parameter(Mandatory)]$Row)
    Measure-SqSum @($Row.In, $Row.Cached, $Row.CacheWr, $Row.Out)
}

function Get-SqLedgerView {
    <#
    .SYNOPSIS
        Parses a consumption ledger into its document, the recognized tables, and the headline figures it states.
    .DESCRIPTION
        Present is $false for a missing ledger. Every other property is $null or empty when the
        ledger does not state it; nothing is computed from outside the ledger and nothing is repaired.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [pscustomobject]@{
            Present = $false; Document = $null; Sections = @(); Title = ''; RunId = ''
            Attribution = @(); Usage = $null; Snapshot = $null; Calibration = $null
            UnitEconomics = $null; Comparison = $null; Observed = $null
        }
    }
    $document = ConvertFrom-SqMarkdown $Text
    $sections = Split-SqSections $document
    $title = ($document.Blocks | Where-Object { $_.Type -eq 'heading' -and $_.Level -eq 1 } | Select-Object -First 1)
    $runId = ''
    if ($title -and $title.Text -match '\(Run:\s*(?<id>[^)]+?)\s*\)') { $runId = $Matches.id }

    $tables = @($document.Blocks | Where-Object Type -eq 'table')
    $paragraphs = @($document.Blocks | Where-Object { $_.Type -in 'paragraph', 'quote' } | ForEach-Object {
            if ($_.Type -eq 'quote') { $_.Paragraphs } else { $_.Text }
        })

    $attributionTable = $tables | Where-Object { (Find-SqColumn $_.Headers 'Model Source') -ge 0 -and (Find-SqColumn $_.Headers '^Role$') -ge 0 } | Select-Object -First 1
    $usageTable = $tables | Where-Object {
        (Find-SqColumn $_.Headers '^Role$') -eq 0 -and ((Find-SqColumn $_.Headers 'Cost.*USD|^Cost$') -ge 0 -or (Find-SqColumn $_.Headers 'Credits') -ge 0)
    } | Select-Object -First 1

    $attribution = @()
    if ($attributionTable) {
        $h = $attributionTable.Headers
        $index = [pscustomobject]@{
            Role = (Find-SqColumn $h '^Role$'); Member = (Find-SqColumn $h '^Member'); Agent = (Find-SqColumn $h '^Agent')
            Model = (Find-SqColumn $h '^Model$'); Source = (Find-SqColumn $h 'Model Source'); PricedAs = (Find-SqColumn $h 'Priced As'); Tier = (Find-SqColumn $h '^Tier$')
        }
        $attribution = @(foreach ($row in $attributionTable.Rows) {
                [pscustomobject]@{
                    Role = (ConvertTo-SqPlainText (Get-SqCell $row $index.Role)); Member = (ConvertTo-SqPlainText (Get-SqCell $row $index.Member))
                    Agent = (ConvertTo-SqPlainText (Get-SqCell $row $index.Agent)); Model = (ConvertTo-SqPlainText (Get-SqCell $row $index.Model))
                    ModelSource = (ConvertTo-SqPlainText (Get-SqCell $row $index.Source)); PricedAs = (ConvertTo-SqPlainText (Get-SqCell $row $index.PricedAs))
                    Tier = (ConvertTo-SqPlainText (Get-SqCell $row $index.Tier))
                }
            })
    }

    $usage = $null
    if ($usageTable) {
        $columns = Get-SqUsageColumns -Headers $usageTable.Headers
        $roleRows = [Collections.Generic.List[object]]::new()
        $total = $null
        $totalInferred = $false
        $attributedKeys = @($attribution | ForEach-Object { Get-SqKey $_.Role } | Where-Object { $_ })
        foreach ($row in $usageTable.Rows) {
            $converted = ConvertTo-SqUsageRow -Cells $row -Columns $columns
            # Only a label that says nothing but "total" is the Total row, so a role such as "Total Recall Analyst" stays a role.
            if ($converted.Role -match '^(?i)(?:grand\s+)?totals?\s*(?:[\(\[][^\)\]]*[\)\]])?\s*:?\s*$') { $total = $converted } else { $roleRows.Add($converted) }
        }
        if ($null -eq $total -and $roleRows.Count -ge 3) {
            # A relabeled Total row must not be read as one more role. The last row is the total only when its label is bold or blank,
            # its cost is bold and equals the sum of the rows above it, and no Attribution row names it as a role.
            $lastRow = @($usageTable.Rows)[-1]
            $lastLabel = Get-SqCell $lastRow $columns.Role
            $lastCost = Get-SqCell $lastRow $columns.CostUsd
            $last = $roleRows[$roleRows.Count - 1]
            $others = Measure-SqSum @($roleRows | Select-Object -First ($roleRows.Count - 1) | ForEach-Object { $_.Usd })
            $labelFits = [string]::IsNullOrWhiteSpace($lastLabel) -or $lastLabel -match '^\s*\*\*.+\*\*\s*$'
            if ($labelFits -and $lastCost -match '^\s*\*\*.+\*\*\s*$' -and $attributedKeys -notcontains (Get-SqKey $last.Role) -and $null -ne $last.Usd -and $null -ne $others -and [Math]::Abs($last.Usd - $others) -le [Math]::Max([decimal]0.0001, [Math]::Abs($others) * [decimal]0.001)) {
                $total = $last
                $roleRows.RemoveAt($roleRows.Count - 1)
                $totalInferred = $true
            }
        }
        $computedTotal = [pscustomobject]@{
            Role = 'Total'; Turns = $null; In = $null; Cached = $null; CacheWr = $null; Out = $null; Usd = $null; Credits = $null; Basis = ''
        }
        foreach ($field in 'Turns', 'In', 'Cached', 'CacheWr', 'Out', 'Usd', 'Credits') {
            $computedTotal.$field = Measure-SqSum @($roleRows | ForEach-Object { $_.$field })
        }
        $costHeader = if ($columns.CostUsd -ge 0) { ConvertTo-SqPlainText $usageTable.Headers[$columns.CostUsd] } else { '' }
        $basisValues = @($roleRows | ForEach-Object { $_.Basis } | Where-Object { $_ } | Select-Object -Unique)
        if ($total -and $total.Basis) { $basisValues = @($basisValues + $total.Basis | Select-Object -Unique) }
        $basis = 'unknown'
        if ($basisValues.Count -gt 0) {
            $exact = @($basisValues | Where-Object { $_ -eq 'exact-native' })
            $basis = if ($exact.Count -eq $basisValues.Count) { 'exact-native' } elseif ($exact.Count -gt 0) { 'mixed' } else { 'estimated' }
        }
        elseif ($costHeader -match '^(?i)exact') { $basis = 'exact-native' }
        elseif ($costHeader -match '^(?i)est') { $basis = 'estimated' }
        $usage = [pscustomobject]@{
            Headers = $usageTable.Headers; Columns = $columns; Rows = $roleRows.ToArray(); Total = $total; ComputedTotal = $computedTotal
            Basis = $basis; HasTierDefault = ($basisValues -contains 'tier-default'); HasTotalRow = ($null -ne $total); TotalInferred = $totalInferred
        }
    }

    $snapshot = $null
    foreach ($block in $document.Blocks) {
        if ($block.Type -ne 'code') { continue }
        if ($block.Text -match '(?m)^Native usage snapshot — session: (?<s>[^;]+); records: (?<r>\d{1,15}); through: (?<t>[^;]+); digest: (?<d>[A-Fa-f0-9]{64})') {
            $snapshot = [pscustomobject]@{ Sessions = 1; SessionId = $Matches.s.Trim(); Records = [long]$Matches.r; Through = $Matches.t.Trim(); Digest = $Matches.d }
        }
        elseif ($block.Text -match '(?m)^Native usage snapshots — sessions: (?<n>\d{1,9}); records: (?<r>\d{1,15}); through: (?<t>[^;]+); digest: (?<d>[A-Fa-f0-9]{64})') {
            $snapshot = [pscustomobject]@{ Sessions = [int]$Matches.n; SessionId = ''; Records = [long]$Matches.r; Through = $Matches.t.Trim(); Digest = $Matches.d }
        }
    }

    $calibration = $null
    foreach ($paragraph in $paragraphs) {
        if ($paragraph -match '(?i)Calibration factor\s+(?<f>[\d.]+)\s*\((?<n>\d{1,9})\s+reconciled runs?(?:\s*[—–-]\s*(?<s>[^)]+))?\)') {
            $calibration = [pscustomobject]@{ Factor = (ConvertTo-SqDecimal $Matches['f']); ReconciledRuns = [int]$Matches['n']; Status = $(if ($Matches['s']) { $Matches['s'].Trim() } else { '' }) }
            break
        }
    }

    $unitEconomics = $null
    $comparison = $null
    $observed = $null
    foreach ($section in $sections) {
        if ($section.Level -eq 2 -and $section.Title -match '^Unit Economics') {
            $table = $section.Blocks | Where-Object Type -eq 'table' | Select-Object -First 1
            if ($table) {
                $measures = [ordered]@{}
                $valueIndex = Find-SqColumn $table.Headers '^Value$'
                $labelIndex = Find-SqColumn $table.Headers '^Label$'
                foreach ($row in $table.Rows) {
                    $name = ConvertTo-SqPlainText (Get-SqCell $row 0)
                    if ($name -and -not $measures.Contains($name)) {
                        $measures[$name] = [pscustomobject]@{
                            Value = (ConvertTo-SqPlainText (Get-SqCell $row $(if ($valueIndex -ge 0) { $valueIndex } else { 1 })))
                            Label = (ConvertTo-SqPlainText (Get-SqCell $row $labelIndex))
                        }
                    }
                }
                $unitEconomics = [pscustomobject]@{ Measures = $measures }
            }
        }
        elseif ($section.Level -eq 2 -and $section.Title -match '^Cost Comparison') {
            $comparison = Get-SqComparisonView -Section $section
        }
        elseif ($section.Level -eq 2 -and $section.Title -match '^Observed Usage') {
            $observed = Get-SqObservedView -Section $section -Sections $sections
        }
    }

    [pscustomobject]@{
        Present = $true; Document = $document; Sections = $sections; Title = $(if ($title) { [string]$title.Text } else { '' }); RunId = $runId
        Attribution = $attribution; Usage = $usage; Snapshot = $snapshot; Calibration = $calibration
        UnitEconomics = $unitEconomics; Comparison = $comparison; Observed = $observed
    }
}

function Get-SqComparisonView {
    <#
    .SYNOPSIS
        Extracts the with/without HVE Squad figures a Cost Comparison section states, in either its table or its prose form.
    #>
    param([Parameter(Mandatory)]$Section)
    $kind = if ($Section.Title -match '(?i)exact native') { 'exact-native' } else { 'estimated-illustrative' }
    $squad = $null; $baseline = $null; $squadCredits = $null; $baselineCredits = $null; $model = ''
    foreach ($table in ($Section.Blocks | Where-Object Type -eq 'table')) {
        $scenario = Find-SqColumn $table.Headers '^Scenario$'
        if ($scenario -lt 0) { continue }
        $usdIndex = Find-SqColumn $table.Headers 'USD'
        $creditIndex = Find-SqColumn $table.Headers 'Credits'
        foreach ($row in $table.Rows) {
            $name = ConvertTo-SqPlainText (Get-SqCell $row $scenario)
            if ($name -match '^(?i)With HVE Squad') {
                $squad = ConvertTo-SqDecimal (Get-SqCell $row $usdIndex); $squadCredits = ConvertTo-SqDecimal (Get-SqCell $row $creditIndex)
            }
            elseif ($name -match '^(?i)Without HVE Squad') {
                $baseline = ConvertTo-SqDecimal (Get-SqCell $row $usdIndex); $baselineCredits = ConvertTo-SqDecimal (Get-SqCell $row $creditIndex)
                if ($name -match '`(?<m>[^`]+)`') { $model = $Matches.m }
            }
        }
    }
    $statedPct = $null; $statedDirection = ''; $statedUsd = $null
    $prose = @($Section.Blocks | Where-Object Type -eq 'paragraph' | ForEach-Object Text)
    foreach ($text in $prose) {
        if ($text -match '(?i)HVE Squad is \*\*(?<usd>[\d,]+(?:\.\d+)?) USD \((?<pct>[\d.]+)%\) (?<dir>lower|higher)\*\*') {
            $statedUsd = ConvertTo-SqDecimal $Matches.usd; $statedPct = ConvertTo-SqDecimal $Matches.pct; $statedDirection = $Matches.dir.ToLowerInvariant()
            if (-not $model -and $text -match '`(?<m>[^`]+)`') { $model = $Matches.m }
        }
    }
    if ($null -eq $squad -and $null -eq $baseline) {
        foreach ($text in $prose) {
            $money = @([regex]::Matches($text, '\*\*\$(?<usd>[\d,]+(?:\.\d+)?)(?:\s*\(~?(?<cr>[\d,.]+)\s*AI credits\))?\*\*'))
            if ($money.Count -ge 1) {
                $squad = ConvertTo-SqDecimal $money[0].Groups['usd'].Value
                if ($money[0].Groups['cr'].Success) { $squadCredits = ConvertTo-SqDecimal $money[0].Groups['cr'].Value }
                if ($money.Count -ge 2) {
                    $baseline = ConvertTo-SqDecimal $money[1].Groups['usd'].Value
                    if ($money[1].Groups['cr'].Success) { $baselineCredits = ConvertTo-SqDecimal $money[1].Groups['cr'].Value }
                    if ($text -match '(?i)(?:saving|savings|reduction|lower|cheaper)[^%]{0,60}?(?<p>\d+(?:\.\d+)?)\s*%') { $statedPct = ConvertTo-SqDecimal $Matches.p; $statedDirection = 'lower' }
                    if ($text -match '\bat (?<m>(?-i:[A-Z])[\w .-]+?)(?:''s)? (?:default )?rate') { $model = $Matches.m.Trim() }
                }
                break
            }
        }
    }
    [pscustomobject]@{
        Title = $Section.Title; Kind = $kind; SquadUsd = $squad; BaselineUsd = $baseline; SquadCredits = $squadCredits; BaselineCredits = $baselineCredits
        BaselineModel = $model; StatedPct = $statedPct; StatedDirection = $statedDirection; StatedUsd = $statedUsd
        Complete = ($null -ne $squad -and $null -ne $baseline)
    }
}

function Get-SqObservedView {
    <#
    .SYNOPSIS
        Extracts the legacy Observed Usage (host-reported) facts: window, per-agent rows, whole-session total, and the without-Squad comparison.
    #>
    param([Parameter(Mandatory)]$Section, [Parameter(Mandatory)][object[]]$Sections)
    $text = ($Section.Blocks | Where-Object Type -eq 'paragraph' | ForEach-Object Text) -join "`n"
    $sessionId = ''; $first = ''; $last = ''
    if ($text -match 'Copilot session `(?<s>[^`]+)`') { $sessionId = $Matches.s }
    if ($text -match '`events\.jsonl`,\s*(?<a>\S+)\s+to\s+(?<b>[^)\s]+)') { $first = $Matches.a; $last = $Matches.b }
    $rows = @()
    $table = $Section.Blocks | Where-Object { $_.Type -eq 'table' -and (Find-SqColumn $_.Headers 'Observed Model') -ge 0 } | Select-Object -First 1
    $mismatches = [Collections.Generic.List[string]]::new()
    $unverifiable = [Collections.Generic.List[string]]::new()
    $subagentTokens = $null; $estimatedTokens = $null; $blendedUsd = $null
    if ($table) {
        $h = $table.Headers
        $agentIndex = Find-SqColumn $h '^Agent$'; $matchIndex = Find-SqColumn $h '^Match$'; $observedModelIndex = Find-SqColumn $h 'Observed Model'
        $ledgerModelIndex = Find-SqColumn $h 'Ledger Model'; $tokensIndex = Find-SqColumn $h 'Observed Tokens'; $estimatedIndex = Find-SqColumn $h 'Estimated Tokens'
        $usdIndex = Find-SqColumn $h 'USD'; $dispatchIndex = Find-SqColumn $h 'Dispatches'
        $rows = @(foreach ($row in $table.Rows) {
                $agent = ConvertTo-SqPlainText (Get-SqCell $row $agentIndex)
                $match = ConvertTo-SqPlainText (Get-SqCell $row $matchIndex)
                if ($agent -match '^(?i)subagents total$') {
                    $subagentTokens = ConvertTo-SqDecimal (Get-SqCell $row $tokensIndex); $estimatedTokens = ConvertTo-SqDecimal (Get-SqCell $row $estimatedIndex)
                    $blendedUsd = ConvertTo-SqDecimal (Get-SqCell $row $usdIndex)
                    continue
                }
                if ($match -match '^(?i)(no|mismatch|differs|✗)') {
                    $mismatches.Add(('{0}: observed {1}, ledger {2} ({3})' -f $agent, (ConvertTo-SqPlainText (Get-SqCell $row $observedModelIndex)), (ConvertTo-SqPlainText (Get-SqCell $row $ledgerModelIndex)), $match))
                }
                elseif ($match -match '^(?i)(n/a|—|–|-)$') { $unverifiable.Add($agent) }
                [pscustomobject]@{ Agent = $agent; Match = $match; Dispatches = (ConvertTo-SqDecimal (Get-SqCell $row $dispatchIndex)); Usd = (ConvertTo-SqDecimal (Get-SqCell $row $usdIndex)) }
            })
    }
    $credits = $null; $usd = $null; $records = $null; $checkpointOnly = $false
    $totalParagraph = @($Section.Blocks | Where-Object { $_.Type -eq 'paragraph' -and $_.Text -match 'unique usage records' } | ForEach-Object Text) | Select-Object -First 1
    if ($totalParagraph) {
        $recordsMatch = [regex]::Match($totalParagraph, '\*\*(?<n>[\d,]+)\*\*\s+unique usage records')
        if ($recordsMatch.Success) { $records = ConvertTo-SqDecimal $recordsMatch.Groups['n'].Value }
        $creditsMatch = [regex]::Match($totalParagraph, '\*\*(?<c>[\d,]+(?:\.\d+)?) AI credits\*\*')
        if ($creditsMatch.Success) { $credits = ConvertTo-SqDecimal $creditsMatch.Groups['c'].Value }
        $usdMatch = [regex]::Match($totalParagraph, '(?i)\babout\s+\$?(?<u>[\d,]+(?:\.\d+)?)\s*USD\b')
        if ($usdMatch.Success) { $usd = ConvertTo-SqDecimal $usdMatch.Groups['u'].Value }
    }
    elseif ($text -match 'no complete usage-record total is available') { $checkpointOnly = $true }
    $withoutSquad = $null
    foreach ($sub in $Sections) {
        if ($sub.Level -eq 3 -and $sub.Title -match '^Without HVE Squad') {
            $withoutSquad = Get-SqComparisonView -Section ([pscustomobject]@{ Title = 'Observed blended (Without HVE Squad)'; Blocks = $sub.Blocks })
            $withoutSquad.Kind = 'observed-blended'
        }
    }
    [pscustomobject]@{
        SessionId = $sessionId; First = $first; Last = $last; Rows = $rows; Mismatches = $mismatches.ToArray(); Unverifiable = $unverifiable.ToArray()
        SubagentTokens = $subagentTokens; EstimatedTokens = $estimatedTokens; BlendedUsd = $blendedUsd
        SessionCredits = $credits; SessionUsd = $usd; SessionRecords = $records; CheckpointOnly = $checkpointOnly
        Comparison = $withoutSquad; Scope = $(if ($text -match 'members/(?<m>[\w.-]+)') { $Matches.m } else { '' })
    }
}

function Join-SqAttributionToUsage {
    <#
    .SYNOPSIS
        Pairs each usage row with its attribution row (same order when the role sequences agree, else by role label).
    #>
    param([Parameter(Mandatory)]$View)
    if (-not $View.Present -or $null -eq $View.Usage) { return @() }
    $attribution = @($View.Attribution)
    $rows = @($View.Usage.Rows)
    $sameOrder = ($attribution.Count -eq $rows.Count)
    if ($sameOrder) {
        for ($i = 0; $i -lt $rows.Count; $i++) {
            if ((Get-SqKey $attribution[$i].Role) -ne (Get-SqKey $rows[$i].Role)) { $sameOrder = $false; break }
        }
    }
    $used = [Collections.Generic.HashSet[int]]::new()
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $match = $null
        if ($sameOrder) { $match = $attribution[$i] }
        else {
            for ($j = 0; $j -lt $attribution.Count; $j++) {
                if (-not $used.Contains($j) -and (Get-SqKey $attribution[$j].Role) -eq (Get-SqKey $rows[$i].Role)) { $match = $attribution[$j]; [void]$used.Add($j); break }
            }
        }
        [pscustomobject]@{ Usage = $rows[$i]; Attribution = $match }
    }
}

function Get-SqLedgerQuality {
    <#
    .SYNOPSIS
        Flags what a reader must not misread: unresolved models, fallback pricing, estimate bases, mismatches, missing or inconsistent totals.
    .DESCRIPTION
        Observations only. Nothing here repairs or recomputes a ledger value.
    #>
    param([Parameter(Mandatory)]$View, [AllowNull()]$State, [AllowNull()]$Rates)
    $notes = [Collections.Generic.List[object]]::new()
    $add = { param($severity, $code, $message) $notes.Add([pscustomobject]@{ Severity = $severity; Code = $code; Message = $message }) }
    if (-not $View.Present) {
        & $add 'warn' 'ledger-missing' 'No consumption.md was found: cost, token, and ROI figures are unavailable and nothing is estimated in its place.'
        return $notes.ToArray()
    }
    if ($null -eq $View.Usage) {
        & $add 'warn' 'usage-table-unrecognized' 'consumption.md has no Usage & Cost table this report recognizes. Its sections are shown verbatim; headline cost, tokens, and ROI are unavailable.'
        return $notes.ToArray()
    }
    foreach ($pair in (Join-SqAttributionToUsage -View $View)) {
        $a = $pair.Attribution
        if ($null -eq $a) { & $add 'warn' 'attribution-missing' ("Role '{0}' has a usage row but no Attribution row." -f $pair.Usage.Role); continue }
        $hostPriced = ($a.PricedAs -match '(?i)^native credits$' -or $pair.Usage.Basis -eq 'exact-native')
        if ($a.Model -match '(?i)\b(unknown|unresolved)\b' -or $a.ModelSource -match '(?i)\bunresolved\b') {
            & $add 'warn' 'model-unresolved' ("Role '{0}': model identity is unresolved ({1}); it is priced as {2}, which is a rate fallback and not an observed model." -f $a.Role, $(if ($a.Model) { $a.Model } else { 'blank' }), $(if ($a.PricedAs) { $a.PricedAs } else { 'no recorded rate row' }))
        }
        elseif (-not $hostPriced -and $a.PricedAs -and $a.Model -and (Get-SqKey $a.PricedAs) -ne (Get-SqKey $a.Model)) {
            & $add 'info' 'priced-as-differs' ("Role '{0}': recorded model {1} is priced as {2} (tier fallback or rate proxy)." -f $a.Role, $a.Model, $a.PricedAs)
        }
    }
    if ($View.Usage.HasTierDefault) { & $add 'info' 'tier-default' 'At least one row has basis tier-default: its model was unknown and its price is the conservative tier fallback.' }
    if ($View.Usage.Basis -eq 'mixed') { & $add 'warn' 'mixed-basis' 'The ledger mixes exact-native and estimated rows; figures are labeled per row and are not one basis.' }
    if (-not $View.Usage.HasTotalRow) { & $add 'info' 'total-row-missing' 'The Usage & Cost table has no Total row; totals shown are the sum of its rows.' }
    else {
        if ($View.Usage.TotalInferred) { & $add 'info' 'total-row-inferred' 'The last Usage & Cost row is bold and equals the sum of the rows above it, so it is read as the Total row although it is not labeled Total.' }
        foreach ($field in @(@('Usd', 'cost (USD)'), @('Credits', 'credits'))) {
            $stated = $View.Usage.Total.($field[0]); $sum = $View.Usage.ComputedTotal.($field[0])
            if ($null -ne $stated -and $null -ne $sum) {
                $tolerance = [Math]::Max([decimal]0.0001, [Math]::Abs($stated) * [decimal]0.001)
                if ([Math]::Abs($stated - $sum) -gt $tolerance) {
                    & $add 'warn' 'total-mismatch' ("Ledger Total {0} is {1} but its rows sum to {2}." -f $field[1], (Format-SqNumber $stated 4), (Format-SqNumber $sum 4))
                }
            }
        }
    }
    if ($null -ne $State -and $View.Usage.Total -and $null -ne $View.Usage.Total.Usd) {
        $run = $null
        if ($State -is [System.Collections.IDictionary] -and $State.Contains('currentRun')) { $run = $State['currentRun'] }
        if ($run -is [System.Collections.IDictionary] -and $run.Contains('estCostUsd') -and $null -ne $run['estCostUsd']) {
            $stateUsd = ConvertTo-SqDecimal ([string]$run['estCostUsd'])
            $tolerance = [Math]::Max([decimal]0.0001, [Math]::Abs($View.Usage.Total.Usd) * [decimal]0.001)
            if ($null -ne $stateUsd -and [Math]::Abs($stateUsd - $View.Usage.Total.Usd) -gt $tolerance) {
                & $add 'warn' 'state-ledger-divergence' ("state.json currentRun.estCostUsd is {0} but the ledger Total is {1}: one of them is stale. Neither was changed." -f (Format-SqNumber $stateUsd 4), (Format-SqNumber $View.Usage.Total.Usd 4))
            }
        }
    }
    if ($View.Usage.Basis -eq 'estimated') {
        if ($View.Calibration -and $View.Calibration.ReconciledRuns -eq 0) {
            & $add 'info' 'uncalibrated' ("Estimated figures are uncalibrated (calibration factor {0}, {1} reconciled runs): treat them as approximate." -f (Format-SqNumber $View.Calibration.Factor 2), $View.Calibration.ReconciledRuns)
        }
        elseif ($null -eq $View.Calibration) { & $add 'info' 'calibration-unstated' 'The ledger does not state its calibration state; estimated figures are approximate.' }
    }
    $statedBasis = @($View.Document.Blocks | Where-Object { $_.Type -eq 'quote' } | ForEach-Object { $_.Paragraphs } | Where-Object { $_ -match '^(?i)Basis:\s*(?<b>exact-native|estimated)\b' } | ForEach-Object { $null = $_ -match '^(?i)Basis:\s*(?<b>exact-native|estimated)\b'; $Matches.b.ToLowerInvariant() } | Select-Object -Unique)
    foreach ($noteBasis in $statedBasis) {
        if (($View.Usage.Basis -in @('exact-native', 'estimated')) -and $noteBasis -ne $View.Usage.Basis) {
            & $add 'warn' 'basis-note-conflict' ("The ledger's own Basis note says '{0}' but its Usage & Cost rows are '{1}': the note is stale. The rows are what this report uses; the note is shown unchanged." -f $noteBasis, $View.Usage.Basis)
        }
    }
    if ($null -eq $View.Comparison) { & $add 'info' 'comparison-missing' 'The ledger has no Cost Comparison section: the without-HVE-Squad scenario and ROI are not available.' }
    elseif (-not $View.Comparison.Complete) { & $add 'info' 'comparison-incomplete' 'The Cost Comparison does not state both a with- and a without-HVE-Squad figure (manual baseline unavailable), so ROI is not derivable from it.' }
    elseif ($null -ne $View.Comparison.StatedPct -and $View.Comparison.BaselineUsd -gt 0) {
        $computed = ($View.Comparison.BaselineUsd - $View.Comparison.SquadUsd) / $View.Comparison.BaselineUsd * 100
        $stated = if ($View.Comparison.StatedDirection -eq 'higher') { -1 * $View.Comparison.StatedPct } else { $View.Comparison.StatedPct }
        if ([Math]::Abs($computed - $stated) -gt [decimal]1.0) {
            & $add 'warn' 'comparison-inconsistent' ("The Cost Comparison states a {0}% {1} saving but its own figures give {2}%." -f (Format-SqNumber $View.Comparison.StatedPct 1), $View.Comparison.StatedDirection, (Format-SqNumber $computed 1))
        }
    }
    if ($View.Observed) {
        foreach ($mismatch in $View.Observed.Mismatches) { & $add 'warn' 'model-mismatch' ("Observed Usage model mismatch: $mismatch") }
        if (@($View.Observed.Unverifiable).Count -gt 0) {
            & $add 'info' 'model-match-unverifiable' ("Observed Usage could not compare the model for {0}: the ledger records no model identity to match against." -f (@($View.Observed.Unverifiable) -join ', '))
        }
        if ($View.Observed.CheckpointOnly) { & $add 'info' 'checkpoint-only' 'Observed Usage has only a lagging host checkpoint, not a complete usage-record total; it is not authoritative.' }
    }
    if ($null -ne $Rates) {
        $rateKeys = [Collections.Generic.HashSet[string]]::new()
        if ($Rates.RateTable) {
            foreach ($row in $Rates.RateTable.Rows) { foreach ($cell in $row[0..([Math]::Min(1, $row.Count - 1))]) { [void]$rateKeys.Add((Get-SqKey $cell)) } }
            foreach ($pair in (Join-SqAttributionToUsage -View $View)) {
                if ($null -eq $pair.Attribution) { continue }
                $priced = $pair.Attribution.PricedAs
                if ($priced -and $priced -notmatch '(?i)^native credits$') {
                    foreach ($name in ($priced -split '\s*,\s*')) {
                        if ($name -and -not $rateKeys.Contains((Get-SqKey $name)) -and $name -notmatch '(?i)^(unknown|n/a|none)$') {
                            & $add 'info' 'rate-row-missing' ("Priced-as model '{0}' (role {1}) has no row in this root's consumption-rates.md; its price cannot be checked here." -f $name, $pair.Usage.Role)
                        }
                    }
                }
            }
        }
    }
    $notes.ToArray()
}