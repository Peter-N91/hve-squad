#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Deterministically seeds (or validates) a squad root's `consumption-rates.md` from
    the shipped `references/consumption-rates-template.md`, so no model ever authors
    a rate table.
.DESCRIPTION
    `consumption-rates.md` is the only source of token rates, and the template says it
    is copied verbatim. A model asked to do that copy has instead invented rows (a
    `gpt-4o` table) or written a tier-fallback table with no per-model table at all,
    and every later ledger derivation then priced from a table that was never real.

    Seed mode (the default) extracts the fenced `markdown` block from the template and
    writes it to `<SquadRoot>/consumption-rates.md`, line endings normalized to LF.
    An existing file that already passes the shape check is left untouched unless
    -Reseed is given. A missing, shape-failed, or -Reseed target is rewritten from the
    template, carrying forward the existing file's calibration yaml block: its factor,
    observation count, and last-reconciled stamp are real observations that a reseed
    must not reset. The one exception follows the template's own rule: a block with
    `observations` above zero whose `calibration_basis` differs from the template's
    current basis (`<Observed-on>|<estimator_revision>`) was measured against other
    rates and is reset to the template's placeholder block, with a warning.

    -Check is read-only and validates shape: a per-model rate table with `Input`,
    `Cached`, `Cache write`, and `Output` columns (plus `Model ID` and `Tier`) that holds
    every model row the template lists (a missing template row fails, which is how an
    invented-only table is caught; a rate that differs from the template only warns,
    because rates move between releases). A row the template does not list is an
    operator-added model: when well-formed (backticked `Model ID`, a fast/default/
    extended `Tier`, four numeric rate cells) it only warns and is carried across a
    reseed, and when malformed it fails, and a seed or reseed that would delete it exits 1 with the
    file untouched unless -DropMalformedRows is given. The file also needs a tier-fallback table
    covering fast, default, and extended, a dispatch-size estimator, and a calibration
    yaml block with its five keys.

    Exit code 0 means the file was seeded, or already valid, or passed -Check. Exit 7 means
    refused: the squad is not under `Model routing: economy`, so nothing was read or written
    and the Scribe seeds the table by hand as in v0.18.1. Any other outcome exits 1 after
    naming what failed.

    Economy only (references/economy-mode.md): the mode is the `Model routing:` line in
    `<SquadRoot>/team.md`; during Init, before `team.md` exists, it is -Mode, which the
    Scribe copies from the initialization payload.
.PARAMETER SquadRoot
    A squad root: `.copilot-tracking/squad/` or a member root such as
    `.copilot-tracking/squad/members/<name>/`. Seed mode creates it when missing;
    -Check requires `consumption-rates.md` to exist.
.PARAMETER Mode
    The routing mode, consulted only while `<SquadRoot>/team.md` does not exist (Init).
    Anything but `economy` refuses with exit 7. Defaults to `off`.
.PARAMETER TemplatePath
    Override for the template file. Defaults to the shipped
    `references/consumption-rates-template.md` beside this script's skill.
.PARAMETER Check
    Validate the existing `consumption-rates.md` and write nothing.
.PARAMETER Reseed
    Rewrite the file from the template even when it already passes the shape check.
    The calibration block is still carried forward.
.PARAMETER DropMalformedRows
    Allow a rewrite to delete malformed operator-added rows. Without it, a seed or reseed that
    would delete one exits 1 and leaves the file untouched, naming each row; use it only after
    the operator agrees to drop them.
.EXAMPLE
    ./Initialize-SquadConsumptionRates.ps1 -SquadRoot .copilot-tracking/squad
.EXAMPLE
    ./Initialize-SquadConsumptionRates.ps1 -SquadRoot .copilot-tracking/squad -Mode economy
.EXAMPLE
    ./Initialize-SquadConsumptionRates.ps1 -SquadRoot .copilot-tracking/squad -Check
.EXAMPLE
    ./Initialize-SquadConsumptionRates.ps1 -SquadRoot .copilot-tracking/squad/members/product -Reseed
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SquadRoot,

    [ValidateSet('off', 'ranked', 'economy', 'manual')]
    [string]$Mode = 'off',

    [string]$TemplatePath = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'references', 'consumption-rates-template.md'),

    [switch]$Check,

    [switch]$Reseed,

    [switch]$DropMalformedRows
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

$RateColumns = @('Input', 'Cached', 'Cache write', 'Output')
$RequiredTiers = @('fast', 'default', 'extended')
$CalibrationKeys = @('calibration_factor', 'last_reconciled', 'observations', 'estimator_revision', 'calibration_basis')

function ConvertTo-LfText {
    param([AllowEmptyString()][string]$Text)
    return ($Text -replace "`r`n", "`n" -replace "`r", "`n")
}

function Get-MarkdownTableLocal {
    <#
    .SYNOPSIS
        Reads every pipe-delimited markdown table as header plus rows keyed by header.
    #>
    param([string]$Content)

    $tables = [System.Collections.Generic.List[pscustomobject]]::new()
    $header = $null
    $rows = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($line in ((ConvertTo-LfText $Content) -split "`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith('|')) {
            if ($header) { $tables.Add([pscustomobject]@{ Header = $header; Rows = $rows }) }
            $header = $null
            $rows = [System.Collections.Generic.List[hashtable]]::new()
            continue
        }

        $cells = @($trimmed.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if (-not $header) { $header = $cells; continue }
        if (@($cells | Where-Object { $_ -notmatch '^:?-{2,}:?$' }).Count -eq 0) { continue }

        $row = @{ '__raw' = $trimmed }
        for ($i = 0; $i -lt $header.Count; $i++) { $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' } }
        $rows.Add($row)
    }
    if ($header) { $tables.Add([pscustomobject]@{ Header = $header; Rows = $rows }) }
    $tables
}

function Get-TemplateSeedBlock {
    <#
    .SYNOPSIS
        Returns the LF-normalized body of the template's fenced `markdown` seed block.
    #>
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Template not found: $Path" }
    $text = ConvertTo-LfText (Get-Content -LiteralPath $Path -Raw)
    $match = [regex]::Match($text, '(?ms)^````markdown\n(?<body>.*?)\n````[ \t]*$')
    if (-not $match.Success) { throw "No ````markdown fenced seed block found in template: $Path" }
    return ($match.Groups['body'].Value.TrimEnd("`n") + "`n")
}

function Get-CalibrationBlock {
    <#
    .SYNOPSIS
        Returns the calibration yaml body (without fences) and its key/value pairs, or $null.
    #>
    param([string]$Content)

    $match = [regex]::Match((ConvertTo-LfText $Content), '(?ms)^##[ \t]+Calibration[ \t]*\n.*?^```yaml\n(?<body>.*?)\n```[ \t]*$')
    if (-not $match.Success) { return $null }

    $values = @{}
    foreach ($line in ($match.Groups['body'].Value -split "`n")) {
        $pair = [regex]::Match($line, '^\s*(?<key>[A-Za-z_]+):\s*(?<value>.*?)\s*$')
        if ($pair.Success) { $values[$pair.Groups['key'].Value] = $pair.Groups['value'].Value.Trim('"') }
    }
    [pscustomobject]@{ Body = $match.Groups['body'].Value; Values = $values; Index = $match.Groups['body'].Index; Length = $match.Groups['body'].Length }
}

function Get-RateNumber {
    param([string]$Cell)
    $parsed = 0.0
    if ([double]::TryParse($Cell, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { return $parsed }
    return $null
}

function Get-TemplateModelRates {
    <#
    .SYNOPSIS
        Maps each template per-model row name to its four rate cells.
    #>
    param([string]$SeedBlock)

    $map = @{}
    foreach ($table in (Get-MarkdownTableLocal -Content $SeedBlock)) {
        if ('Model (as routed)' -notin $table.Header) { continue }
        foreach ($row in $table.Rows) {
            $name = $row['Model (as routed)']
            if ($name -and $name -notmatch '^\(additional\)') { $map[$name] = @($RateColumns | ForEach-Object { $row[$_] }) }
        }
    }
    $map
}

function Test-OperatorRow {
    <#
    .SYNOPSIS
        True when a non-template per-model row is well-formed: backticked Model ID, a valid
        Tier, and four numeric rate cells.
    #>
    param([hashtable]$Row)

    if ($Row['Model ID'] -notmatch '^`[^`\s]+`$') { return $false }
    if ($Row['Tier'] -notin $RequiredTiers) { return $false }
    return (@($RateColumns | Where-Object { $null -eq (Get-RateNumber $Row[$_]) }).Count -eq 0)
}

function Test-RatesShape {
    <#
    .SYNOPSIS
        Validates a consumption-rates.md body. Returns Failures and Warnings arrays.
    #>
    param([string]$Content, [string]$SeedBlock)

    $failures = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $tables = @(Get-MarkdownTableLocal -Content $Content)

    $perModel = @($tables | Where-Object {
            $header = $_.Header
            'Model (as routed)' -in $header -and @($RateColumns | Where-Object { $_ -notin $header }).Count -eq 0
        })

    if ($perModel.Count -eq 0) {
        $failures.Add('No per-model rate table: expected a table with Model (as routed), Input, Cached, Cache write, and Output columns.')
    }
    else {
        $templateRates = Get-TemplateModelRates -SeedBlock $SeedBlock
        $seen = @{}
        foreach ($row in $perModel[0].Rows) {
            $name = $row['Model (as routed)']
            if (-not $name -or $name -match '^\(additional\)') { continue }
            $seen[$name] = $true

            $numbers = @($RateColumns | ForEach-Object { Get-RateNumber $row[$_] })
            if ($numbers -contains $null) { $failures.Add("Per-model row '$name' has a non-numeric Input/Cached/Cache write/Output cell.") }

            if (-not $templateRates.ContainsKey($name)) {
                if (Test-OperatorRow -Row $row) { $warnings.Add("Per-model row '$name' is not in the template: kept as an operator-added row.") }
                else { $failures.Add("Per-model row '$name' is not in the template and is malformed (needs a backticked Model ID, a fast/default/extended Tier, and four numeric rates).") }
            }
            elseif ((@($RateColumns | ForEach-Object { $row[$_] }) -join '|') -ne ($templateRates[$name] -join '|')) {
                $warnings.Add("Per-model row '$name' rates differ from the current template (rates move between releases).")
            }
        }
        $missing = @($templateRates.Keys | Where-Object { -not $seen.ContainsKey($_) } | Sort-Object)
        if ($missing.Count -gt 0) { $failures.Add("Per-model table lacks $($missing.Count) of $($templateRates.Count) template row(s), e.g. '$($missing[0])'; reseed from the template.") }
        foreach ($column in @('Model ID', 'Tier')) {
            if ($column -notin $perModel[0].Header) { $failures.Add("Per-model rate table has no '$column' column.") }
        }
        if ($seen.Count -eq 0) { $failures.Add('Per-model rate table has no model rows.') }
    }

    $tierTable = @($tables | Where-Object {
            $header = $_.Header
            'Priced as' -in $header -and 'Tier' -in $header -and @($RateColumns | Where-Object { $_ -notin $header }).Count -eq 0
        })
    if ($tierTable.Count -eq 0) {
        $failures.Add('No tier-fallback table: expected Tier, Priced as, Input, Cached, Cache write, and Output columns.')
    }
    else {
        $tiers = @($tierTable[0].Rows | ForEach-Object { $_['Tier'] })
        foreach ($tier in $RequiredTiers) {
            if ($tier -notin $tiers) { $failures.Add("Tier-fallback table has no '$tier' row.") }
        }
    }

    $normalized = ConvertTo-LfText $Content
    if ($normalized -notmatch '(?m)^##[ \t]+Dispatch-size estimator' -or $normalized -notmatch 'internal_turns' -or $normalized -notmatch 'gross_input') {
        $failures.Add('No dispatch-size estimator section (expected a "## Dispatch-size estimator" heading using internal_turns and gross_input).')
    }

    $calibration = Get-CalibrationBlock -Content $Content
    if (-not $calibration) {
        $failures.Add('No calibration block: expected a "## Calibration" heading followed by a yaml block.')
    }
    else {
        foreach ($key in $CalibrationKeys) {
            if (-not $calibration.Values.ContainsKey($key)) { $failures.Add("Calibration block is missing '$key'.") }
        }
        if ($calibration.Values.ContainsKey('calibration_factor') -and $null -eq (Get-RateNumber $calibration.Values['calibration_factor'])) {
            $failures.Add('Calibration block: calibration_factor is not a number.')
        }
        if ($calibration.Values.ContainsKey('observations') -and $calibration.Values['observations'] -notmatch '^\d+$') {
            $failures.Add('Calibration block: observations is not a non-negative integer.')
        }
    }

    [pscustomobject]@{ Failures = @($failures); Warnings = @($warnings) }
}

function Get-RatesBasis {
    <#
    .SYNOPSIS
        The template's current calibration basis: "<Observed-on>|<estimator_revision>".
    #>
    param([string]$SeedBlock)

    $observed = [regex]::Match($SeedBlock, '(?m)^\*[ \t]+Observed-on:[ \t]*(?<date>\d{4}-\d{2}-\d{2})')
    $calibration = Get-CalibrationBlock -Content $SeedBlock
    if (-not $observed.Success -or -not $calibration -or -not $calibration.Values.ContainsKey('estimator_revision')) { return $null }
    return "$($observed.Groups['date'].Value)|$($calibration.Values['estimator_revision'])"
}

function Merge-CalibrationBlock {
    <#
    .SYNOPSIS
        Returns the seed block with the existing calibration yaml body carried over,
        unless the existing observations were measured against a different basis.
    #>
    param([string]$SeedBlock, [string]$ExistingContent, [System.Collections.Generic.List[string]]$Notes)

    $seedCalibration = Get-CalibrationBlock -Content $SeedBlock
    $existing = if ($ExistingContent) { Get-CalibrationBlock -Content $ExistingContent } else { $null }
    if (-not $existing -or -not $seedCalibration) { return $SeedBlock }

    foreach ($key in $CalibrationKeys) {
        if (-not $existing.Values.ContainsKey($key)) { $Notes.Add('Existing calibration block is incomplete; using the template block.'); return $SeedBlock }
    }

    if ($existing.Values['observations'] -notmatch '^\d+$' -or $null -eq (Get-RateNumber $existing.Values['calibration_factor'])) {
        $Notes.Add('Existing calibration block has a non-numeric calibration_factor or observations; using the template block.')
        return $SeedBlock
    }

    $observations = [int]$existing.Values['observations']
    $basis = Get-RatesBasis -SeedBlock $SeedBlock
    $storedBasis = $existing.Values['calibration_basis']
    if ($observations -gt 0 -and $basis -and $storedBasis -ne $basis) {
        $Notes.Add("Calibration reset: its $observations observation(s) were measured against basis '$storedBasis', not the template's '$basis'.")
        return $SeedBlock
    }

    $Notes.Add('Calibration block preserved.')
    return $SeedBlock.Remove($seedCalibration.Index, $seedCalibration.Length).Insert($seedCalibration.Index, $existing.Body)
}

function Get-ExistingOperatorRow {
    <#
    .SYNOPSIS
        Rows of the existing file's per-model table that the template does not list. Only a
        table with every structural column is read; any other shape carries no operator rows.
    #>
    param([string]$ExistingContent, [string]$SeedBlock)

    if (-not $ExistingContent) { return @() }
    $templateRates = Get-TemplateModelRates -SeedBlock $SeedBlock
    $table = @(Get-MarkdownTableLocal -Content $ExistingContent | Where-Object {
            $header = $_.Header
            'Model (as routed)' -in $header -and @($RateColumns + 'Model ID' + 'Tier' | Where-Object { $_ -notin $header }).Count -eq 0
        }) | Select-Object -First 1
    if (-not $table) { return @() }

    @($table.Rows | Where-Object {
            $name = $_['Model (as routed)']
            $name -and $name -notmatch '^\(additional\)' -and -not $templateRates.ContainsKey($name)
        })
}

function Add-OperatorRow {
    <#
    .SYNOPSIS
        Re-inserts the existing file's well-formed operator-added per-model rows into a seeded
        body, just above the `(additional)` row. Duplicates are skipped; a malformed row is
        dropped only here, after the caller has refused unless -DropMalformedRows was given.
    #>
    param([string]$Content, [string]$ExistingContent, [string]$SeedBlock, [System.Collections.Generic.List[string]]$Notes)

    $kept = [System.Collections.Generic.List[string]]::new()
    $names = @{}
    foreach ($row in (Get-ExistingOperatorRow -ExistingContent $ExistingContent -SeedBlock $SeedBlock)) {
        $name = $row['Model (as routed)']
        if ($names.ContainsKey($name)) { continue }
        if (-not (Test-OperatorRow -Row $row)) { $Notes.Add("Dropped malformed operator row '$name' (-DropMalformedRows)."); continue }
        $names[$name] = $true
        $kept.Add($row['__raw'])
    }
    if ($kept.Count -eq 0) { return $Content }

    $Notes.Add("Preserved $($kept.Count) operator-added model row(s).")
    $lines = [System.Collections.Generic.List[string]]::new([string[]]($Content -split "`n"))
    $anchor = $lines.FindIndex({ param($l) $l -match '^\|\s*\(additional\)' })
    if ($anchor -lt 0) { return $Content }
    $lines.InsertRange($anchor, $kept)
    return ($lines -join "`n")
}

function Write-Findings {
    param([pscustomobject]$Result, [string]$Path)
    foreach ($warning in $Result.Warnings) { Write-Host "WARN: $warning" }
    foreach ($failure in $Result.Failures) { Write-Host "FAIL: $failure" }
    if ($Result.Failures.Count -eq 0) { Write-Host "OK: $Path passes the consumption-rates shape check." }
}

if ($Check -and $Reseed) { throw '-Check is read-only and cannot be combined with -Reseed.' }

# Resolve against the PowerShell location: .NET file APIs use the process directory, which Set-Location does not change.
$SquadRoot = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($SquadRoot)
$TemplatePath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($TemplatePath)

$teamPath = Join-Path -Path $SquadRoot -ChildPath 'team.md'
$effectiveMode = $Mode
if (Test-Path -LiteralPath $teamPath -PathType Leaf) {
    $modeMatch = [regex]::Match([System.IO.File]::ReadAllText($teamPath), '(?m)^Model routing:\s*`?(?<mode>off|ranked|economy|manual)`?\s*$')
    $effectiveMode = if ($modeMatch.Success) { $modeMatch.Groups['mode'].Value } else { 'off' }
}
if ($effectiveMode -ne 'economy') {
    [Console]::Error.WriteLine("Initialize-SquadConsumptionRates: refused: the squad routes as '$effectiveMode', not economy. Scripted rate seeding is economy-only; the Squad Scribe seeds consumption-rates.md itself.")
    exit 7
}

$seedBlock = Get-TemplateSeedBlock -Path $TemplatePath
$target = Join-Path -Path $SquadRoot -ChildPath 'consumption-rates.md'

if ($Check) {
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        Write-Host "FAIL: $target does not exist."
        exit 1
    }
    $result = Test-RatesShape -Content (Get-Content -LiteralPath $target -Raw) -SeedBlock $seedBlock
    Write-Findings -Result $result -Path $target
    exit $(if ($result.Failures.Count -eq 0) { 0 } else { 1 })
}

$existingContent = if (Test-Path -LiteralPath $target -PathType Leaf) { Get-Content -LiteralPath $target -Raw } else { $null }

if ($existingContent -and -not $Reseed) {
    $current = Test-RatesShape -Content $existingContent -SeedBlock $seedBlock
    if ($current.Failures.Count -eq 0) {
        Write-Findings -Result $current -Path $target
        Write-Host 'UNCHANGED: existing file is valid; pass -Reseed to rewrite it from the template.'
        exit 0
    }
    Write-Host "Existing file failed the shape check ($($current.Failures.Count) problem(s)); reseeding from the template."
}

# A rewrite must never silently destroy an operator's edit: refuse and leave the file untouched.
$malformedRows = @(Get-ExistingOperatorRow -ExistingContent $existingContent -SeedBlock $seedBlock | Where-Object { -not (Test-OperatorRow -Row $_) })
if ($malformedRows.Count -gt 0 -and -not $DropMalformedRows) {
    $names = ($malformedRows | ForEach-Object { "'$($_['Model (as routed)'])'" }) -join ', '
    Write-Host "FAIL: refusing to rewrite $target; it would delete $($malformedRows.Count) malformed operator-added row(s): $names. File left untouched."
    Write-Host 'Fix each row (backticked Model ID, a fast/default/extended Tier, four numeric Input/Cached/Cache write/Output cells) or delete it yourself and re-run, or re-run with -DropMalformedRows once the operator agrees to drop them.'
    exit 1
}

$notes = [System.Collections.Generic.List[string]]::new()
$content = Merge-CalibrationBlock -SeedBlock $seedBlock -ExistingContent $existingContent -Notes $notes
$content = Add-OperatorRow -Content $content -ExistingContent $existingContent -SeedBlock $seedBlock -Notes $notes

if (-not (Test-Path -LiteralPath $SquadRoot -PathType Container)) { $null = New-Item -ItemType Directory -Path $SquadRoot -Force }
[System.IO.File]::WriteAllText($target, $content, [System.Text.UTF8Encoding]::new($false))
foreach ($note in $notes) { Write-Host $note }

$written = Test-RatesShape -Content (Get-Content -LiteralPath $target -Raw) -SeedBlock $seedBlock
Write-Findings -Result $written -Path $target
if ($written.Failures.Count -gt 0) { exit 1 }
Write-Host "SEEDED: $target"
exit 0
