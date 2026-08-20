# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Reads a squad state tree into the model the Tier 1 contract asserts on, and can
# generate a schema-correct fixture.
#
# The fixture exists to prove the assertions fire, not to prove the squad works: a
# fixture the author wrote to satisfy their own assertions is circular evidence. Its
# real job is to be MUTATED - each mutation in Assertions.Tests.ps1 breaks one rule and
# the contract must catch it. An assertion that never fails on a broken tree is worse
# than no assertion, because it reports success.

#Requires -Version 7.4

Set-StrictMode -Version Latest

# Field order is contractual: the ledger rewrite reparses these blocks.
$script:ConsumptionFields = @(
    'model', 'model_source', 'priced_as', 'model_tier', 'internal_turns'
    'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens'
    'input_rate', 'cached_rate', 'cache_write_rate', 'output_rate'
    'est_cost_usd', 'est_credits', 'basis'
)

$script:ModelSources = @('dispatch-reported', 'agent-pinned', 'operator-declared', 'session-inherited', 'cli-pinned', 'unresolved')
$script:Bases = @('estimated', 'tier-default')
$script:Modes = @('interactive', 'autonomous', 'autopilot')
$script:ApprovalChannels = @('in-chat', 'github-issue', 'webhook')

# Files Init seeds eagerly. history/<agent>.md is deliberately absent: it is created on
# first dispatch, and its presence is the proof that a dispatch happened.
$script:EagerStateFiles = @(
    'team.md', 'routing.md', 'decisions.md', 'state.json'
    'notifications.md', 'consumption.md', 'consumption-rates.md'
)

function Get-ConsumptionBlock {
    <#
    .SYNOPSIS
        Extracts every per-dispatch consumption block from a history file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw

    foreach ($match in [regex]::Matches($raw, '(?ms)^####\s+Consumption(?<orchestration>\s+[-\u2014]\s+Orchestration)?\s*$\r?\n+```json\r?\n(?<json>.*?)\r?\n```')) {
        $json = $match.Groups['json'].Value
        $parsed = $null
        $parseError = $null
        try { $parsed = $json | ConvertFrom-Json -AsHashtable }
        catch { $parseError = $_.Exception.Message }

        # Order is read from the raw text, because ConvertFrom-Json does not preserve it.
        $order = @([regex]::Matches($json, '(?m)^\s*"([a-z_]+)"\s*:') | ForEach-Object { $_.Groups[1].Value })

        # A bare number is the contract. '~8,400 (estimated)' parses as a string and drops
        # the dispatch out of every later aggregate, so the shape is checked, not just the value.
        $nonNumeric = @(
            if ($parsed) {
                foreach ($field in $order) {
                    if ($field -in 'model', 'model_source', 'priced_as', 'model_tier', 'basis') { continue }
                    if ($parsed[$field] -isnot [int] -and $parsed[$field] -isnot [long] -and $parsed[$field] -isnot [double] -and $parsed[$field] -isnot [decimal]) {
                        $field
                    }
                }
            }
        )

        [pscustomobject]@{
            Source          = Split-Path $Path -Leaf
            IsOrchestration = [bool]$match.Groups['orchestration'].Success
            Fields          = $parsed
            Order           = $order
            NonNumeric      = $nonNumeric
            ParseError      = $parseError
        }
    }
}

function Get-LedgerTable {
    <#
    .SYNOPSIS
        Parses one markdown table out of consumption.md by its heading.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$Heading
    )

    # Built by concatenation: in a double-quoted string the anchor '$' followed by '('
    # is parsed as a subexpression and the pattern is silently destroyed.
    $pattern = '(?ms)^##\s+' + [regex]::Escape($Heading) + '\s*$(?<body>.*?)(?=^##\s|\z)'
    $section = [regex]::Match($Content, $pattern)
    if (-not $section.Success) { return @() }

    $rows = @()
    foreach ($line in ($section.Groups['body'].Value -split '\r?\n')) {
        if ($line -notmatch '^\s*\|') { continue }
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') { continue }

        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim() })
        if ($cells[0] -match '^(Role|-+)$') { continue }
        $rows += , $cells
    }

    $rows
}

function ConvertTo-LedgerNumber {
    <#
    .SYNOPSIS
        Strips the bold and currency markup a ledger total carries.
    #>
    param([string]$Value)

    # One character class rather than chained -replace: the comma in `-replace a, b`
    # binds tighter than the operator, so chaining without parentheses silently builds
    # an array instead of applying three replacements.
    $clean = ($Value -replace '[*$,]', '').Trim()
    if ($clean -match '^-?\d+(\.\d+)?$') { return [double]$clean }
    return $null
}

function Get-LedgerDecimal {
    <#
    .SYNOPSIS
        Counts the decimals a ledger cell displays.
    .DESCRIPTION
        The ledger prints role rows at four decimals and the run total at two, so a sum
        compared at full precision fails on display rounding alone. Reading the printed
        precision back keeps the comparison exact at whatever the ledger chose, instead
        of widening a tolerance until real drift fits inside it. Two decimals is the
        floor, so a total printed as a whole dollar cannot pass on rounding slack.
    #>
    param([string]$Value)

    $clean = ($Value -replace '[*$,]', '').Trim()
    if ($clean -match '^-?\d+\.(\d+)$') { return [math]::Max(2, $Matches[1].Length) }
    return 2
}

function Get-MarkdownTable {
    <#
    .SYNOPSIS
        Reads every markdown table in a document as rows keyed by their column headers.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Content = ''
    )

    $tables = @()
    $header = $null
    $rows = $null

    foreach ($line in ($Content -split '\r?\n')) {
        if ($line -notmatch '^\s*\|') {
            if ($header) { $tables += , [pscustomobject]@{ Header = $header; Rows = $rows } }
            $header = $null
            $rows = $null
            continue
        }

        # The delimiter row separates header from body and carries no data of its own.
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') { continue }

        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim().Trim('`').Trim() })

        if (-not $header) {
            $header = $cells
            $rows = @()
            continue
        }

        $row = [ordered]@{}
        for ($i = 0; $i -lt $header.Count; $i++) {
            $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' }
        }
        $rows += , $row
    }

    if ($header) { $tables += , [pscustomobject]@{ Header = $header; Rows = $rows } }
    $tables
}

function Get-RateTable {
    <#
    .SYNOPSIS
        Reads the per-model and tier-fallback rate tables out of consumption-rates.md.
    .DESCRIPTION
        Tables are selected by column header and cells are read by header name, never by
        position. The shipped table carries Tier and Notes columns around the four rate
        columns, so a positional read lands on the wrong cells, and a model name like
        'Claude Sonnet 4.6' does not survive a key pattern that forbids spaces. Selecting
        on the four rate headers also keeps the dispatch-size estimator's class rows out:
        they are five numeric-looking columns that a looser match would happily register
        as a price.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Content = ''
    )

    $rates = @{}
    if (-not $Content) { return $rates }

    $rateColumns = @('Input', 'Cached', 'Cache write', 'Output')

    foreach ($table in (Get-MarkdownTable -Content $Content)) {
        if (@($rateColumns | Where-Object { $_ -notin $table.Header }).Count -gt 0) { continue }

        # 'Priced as' names the rate row on the tier-fallback table, whose first column is
        # the tier. Everywhere else the first column is the model itself.
        $keyColumn = if ('Priced as' -in $table.Header) { 'Priced as' } else { $table.Header[0] }

        foreach ($row in $table.Rows) {
            $key = $row[$keyColumn]

            # The per-model table is read first, so it stays authoritative over the
            # tier-fallback duplicates of the same model.
            if (-not $key -or $rates.ContainsKey($key)) { continue }

            $numbers = @($rateColumns | ForEach-Object { ConvertTo-LedgerNumber $row[$_] })
            if ($numbers -contains $null) { continue }

            $rates[$key] = @{
                input       = $numbers[0]
                cached      = $numbers[1]
                cache_write = $numbers[2]
                output      = $numbers[3]
            }
        }
    }

    $rates
}

function Get-SquadStateModel {
    <#
    .SYNOPSIS
        Reads a squad root into the collections the Tier 1 contract asserts on.
    .PARAMETER SquadRoot
        A squad root: .copilot-tracking/squad/ or .copilot-tracking/squad/members/<name>/.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SquadRoot
    )

    function Read-Text {
        param([string]$Name)
        $path = Join-Path $SquadRoot $Name
        if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw } else { $null }
    }

    $stateJson = $null
    $statePath = Join-Path $SquadRoot 'state.json'
    if (Test-Path -LiteralPath $statePath) {
        try { $stateJson = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable } catch { $stateJson = $null }
    }

    $historyDirectory = Join-Path $SquadRoot 'history'
    $historyFiles = @(
        if (Test-Path -LiteralPath $historyDirectory) {
            Get-ChildItem -LiteralPath $historyDirectory -Filter '*.md' -File
        }
    )

    $blocks = @(foreach ($file in $historyFiles) { Get-ConsumptionBlock -Path $file.FullName })

    # A template copied out of a line-numbered read view keeps the viewer's gutter, which
    # leaves the file well formed to the eye and unparseable to everything downstream.
    # Scoped to state files: a deliverable may legitimately open with a numbered list.
    $numberedFiles = @(
        foreach ($file in (@(Get-ChildItem -LiteralPath $SquadRoot -Filter '*.md' -File -ErrorAction SilentlyContinue) + $historyFiles)) {
            $lines = @(Get-Content -LiteralPath $file.FullName -TotalCount 12 -ErrorAction SilentlyContinue)
            $gutter = @($lines | Where-Object { $_ -match '^\s*\d+[.:]\s' })
            if ($gutter.Count -ge 3) { $file.Name }
        }
    )

    $ledgerContent = Read-Text 'consumption.md'
    $ratesContent = Read-Text 'consumption-rates.md'
    $teamContent = Read-Text 'team.md'

    # The ledger rewrite matches a history file back to its roster row by file name, so
    # the roster is what makes a basename legal. Alternates count: a dispatch can be
    # routed to one and it writes its own history file.
    $rosterAgents = @(
        foreach ($table in (Get-MarkdownTable -Content $teamContent)) {
            if ('Agent Name (Primary)' -notin $table.Header) { continue }
            foreach ($row in $table.Rows) {
                if ($row['Agent Name (Primary)']) { $row['Agent Name (Primary)'] }
                if ('Alternate Agents' -in $table.Header) {
                    foreach ($alternate in ($row['Alternate Agents'] -split ',')) {
                        $trimmed = $alternate.Trim()
                        if ($trimmed -and $trimmed -notmatch '^[-\u2014]$') { $trimmed }
                    }
                }
            }
        }
    ) | Sort-Object -Unique

    # Only this file holds token rates, so every block's rates are checked against it.
    $rates = Get-RateTable -Content $ratesContent

    $calibration = 1.0
    $observations = 0
    if ($ratesContent) {
        $factor = [regex]::Match($ratesContent, '(?im)^\s*[*-]?\s*`?calibration_factor`?\s*[:=]\s*([0-9.]+)')
        if ($factor.Success) { $calibration = [double]$factor.Groups[1].Value }
        $seen = [regex]::Match($ratesContent, '(?im)^\s*[*-]?\s*`?observations`?\s*[:=]\s*([0-9]+)')
        if ($seen.Success) { $observations = [int]$seen.Groups[1].Value }
    }

    @{
        SquadRoot        = $SquadRoot
        Exists           = Test-Path -LiteralPath $SquadRoot
        EagerFiles       = @($script:EagerStateFiles | ForEach-Object {
                @{ Name = $_; Present = Test-Path -LiteralPath (Join-Path $SquadRoot $_) }
            })
        HasHistoryDir    = Test-Path -LiteralPath $historyDirectory
        HistoryFiles     = $historyFiles
        HistoryNames     = @($historyFiles | ForEach-Object { $_.BaseName })
        NumberedFiles    = @($numberedFiles)
        State            = $stateJson
        Team             = $teamContent
        RosterAgents     = @($rosterAgents)
        Routing          = Read-Text 'routing.md'
        Decisions        = Read-Text 'decisions.md'
        Notifications    = Read-Text 'notifications.md'
        Ledger           = $ledgerContent
        RatesContent     = $ratesContent
        Rates            = $rates
        Calibration      = $calibration
        Observations     = $observations
        Blocks           = $blocks
        DispatchBlocks   = @($blocks | Where-Object { -not $_.IsOrchestration })
        OrchestrationBlocks = @($blocks | Where-Object { $_.IsOrchestration })
        Attribution      = @(if ($ledgerContent) { Get-LedgerTable -Content $ledgerContent -Heading 'Attribution' })
        UsageAndCost     = @(if ($ledgerContent) { Get-LedgerTable -Content $ledgerContent -Heading 'Usage & Cost' })
        ConsumptionFields = $script:ConsumptionFields
        ModelSources     = $script:ModelSources
        Bases            = $script:Bases
        Modes            = $script:Modes
        ApprovalChannels = $script:ApprovalChannels
    }
}

Export-ModuleMember -Function Get-SquadStateModel, Get-ConsumptionBlock, Get-LedgerTable, Get-MarkdownTable, Get-RateTable, ConvertTo-LedgerNumber, Get-LedgerDecimal
