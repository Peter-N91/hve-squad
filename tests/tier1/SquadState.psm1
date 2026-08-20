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

    $ledgerContent = Read-Text 'consumption.md'
    $ratesContent = Read-Text 'consumption-rates.md'

    # Only this file holds token rates, so every block's rates are checked against it.
    $rates = @{}
    if ($ratesContent) {
        foreach ($line in ($ratesContent -split '\r?\n')) {
            if ($line -notmatch '^\s*\|\s*`?([A-Za-z0-9._-]+)`?\s*\|') { continue }
            $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim().Trim('`') })
            if ($cells.Count -lt 5) { continue }

            $numbers = @($cells[1..4] | ForEach-Object { ConvertTo-LedgerNumber $_ })
            if ($numbers -contains $null) { continue }

            $rates[$cells[0]] = @{
                input      = $numbers[0]
                cached     = $numbers[1]
                cache_write = $numbers[2]
                output     = $numbers[3]
            }
        }
    }

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
        State            = $stateJson
        Team             = Read-Text 'team.md'
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

Export-ModuleMember -Function Get-SquadStateModel, Get-ConsumptionBlock, Get-LedgerTable, ConvertTo-LedgerNumber
