#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Synchronizes `model-catalog.md` and `consumption-rates-template.md` from
    official GitHub Copilot documentation pages.
.DESCRIPTION
    Fetches the four authoritative GitHub Copilot documentation pages —
    Supported AI models, Models and pricing, AI model comparison, and Copilot
    Fusion — (or reads local HTML fixtures supplied for offline testing) and
    updates:
      1. `squad-src/.github/skills/squad/references/model-catalog.md`
      2. `squad-src/.github/skills/squad/references/consumption-rates-template.md`

    Newly launched Copilot models are added automatically with their official
    token rates, long-context tiers, extended capabilities, capability classes,
    and assignment-fit scores. Retired models absent from both Supported AI
    models and Models and pricing are automatically pruned from active catalog
    selection and rate tables. Copilot Fusion's three user-selectable effort
    levels (`fusion-standard`, `hydrafusion` / High, and `hydrafusion-max` /
    Max) are maintained alongside single-model rows.

    Both files keep identical `Retrieved:` and `Observed-on:` dates. To prevent
    daily commit churn when upstream model offerings and prices are unchanged,
    a date-independent semantic digest is compared against the files on disk;
    dates advance only when content changes, `-Force` is set, or the existing
    snapshot reaches `-RefreshThresholdDays` (default 60, well ahead of the
    90-day stale-catalog fallback).
.PARAMETER CatalogOutputPath
    Destination path for `model-catalog.md`.
.PARAMETER RatesOutputPath
    Destination path for `consumption-rates-template.md`.
.PARAMETER SupportedModelsUri
    URL for GitHub's "Supported AI models in GitHub Copilot" page.
.PARAMETER PricingUri
    URL for GitHub's "Models and pricing for GitHub Copilot" page.
.PARAMETER ComparisonUri
    URL for GitHub's "AI model comparison" page.
.PARAMETER FusionUri
    URL for GitHub's "About GitHub Copilot Fusion" page.
.PARAMETER SupportedModelsHtmlPath
    Optional local HTML fixture path overriding `-SupportedModelsUri`.
.PARAMETER PricingHtmlPath
    Optional local HTML fixture path overriding `-PricingUri`.
.PARAMETER ComparisonHtmlPath
    Optional local HTML fixture path overriding `-ComparisonUri`.
.PARAMETER FusionHtmlPath
    Optional local HTML fixture path overriding `-FusionUri`.
.PARAMETER AdvertisedModels
    Optional explicit list of host-advertised dispatch model IDs. Defaults to
    the CLI client support column from Supported AI models plus known host
    identifiers (`hydrafusion`, `hydrafusion-max`, `gpt-5.6-sol-fast`).
.PARAMETER AsOf
    Retrieval date (`yyyy-MM-dd`). Defaults to UTC today.
.PARAMETER RefreshThresholdDays
    Maximum age in days before a date-only refresh renews `Retrieved:` and
    `Observed-on:` ahead of the 90-day staleness cliff. Defaults to 60.
.PARAMETER MaxRatesTemplateBytes
    Maximum LF-normalized UTF-8 byte count allowed for
    `consumption-rates-template.md` (guards Tier 0 hot-file budget).
.PARAMETER Force
    Rewrite both files even when the semantic digest is unchanged and the
    existing date is younger than `-RefreshThresholdDays`.
.PARAMETER DryRun
    Compute and validate both outputs without writing to disk.
.PARAMETER GitHubOutput
    Append `updated`, `retrieved`, `digest`, `models_count`, `added_models`,
    and `retired_models` lines to `$env:GITHUB_OUTPUT`.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$CatalogOutputPath,

    [Parameter(Mandatory = $false)]
    [string]$RatesOutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SupportedModelsUri = 'https://docs.github.com/en/copilot/reference/ai-models/supported-models',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PricingUri = 'https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ComparisonUri = 'https://docs.github.com/en/copilot/reference/ai-models/model-comparison',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$FusionUri = 'https://docs.github.com/en/copilot/concepts/models/copilot-fusion',

    [Parameter(Mandatory = $false)]
    [string]$SupportedModelsHtmlPath,

    [Parameter(Mandatory = $false)]
    [string]$PricingHtmlPath,

    [Parameter(Mandatory = $false)]
    [string]$ComparisonHtmlPath,

    [Parameter(Mandatory = $false)]
    [string]$FusionHtmlPath,

    [Parameter(Mandatory = $false)]
    [string[]]$AdvertisedModels = @(),

    [Parameter(Mandatory = $false)]
    [datetime]$AsOf = [datetime]::UtcNow,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 89)]
    [int]$RefreshThresholdDays = 60,

    [Parameter(Mandatory = $false)]
    [int]$MaxRatesTemplateBytes = 17196,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$GitHubOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$refsRoot = Join-Path $repoRoot 'squad-src/.github/skills/squad/references'
if (-not $CatalogOutputPath) { $CatalogOutputPath = Join-Path $refsRoot 'model-catalog.md' }
if (-not $RatesOutputPath) { $RatesOutputPath = Join-Path $refsRoot 'consumption-rates-template.md' }

$retrievedDate = $AsOf.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
$assignmentClasses = @('research', 'planning', 'implementation', 'review', 'council', 'intake', 'bookkeeping')

function Get-SourceHtmlLocal {
    param([string]$LocalPath, [string]$Uri, [string]$Label)
    if ($LocalPath) {
        if (-not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
            throw "Local HTML fixture for $Label not found: $LocalPath"
        }
        return Get-Content -LiteralPath $LocalPath -Raw
    }
    Write-Host "Fetching $Label from $Uri..." -ForegroundColor Cyan
    $resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing
    return [string]$resp.Content
}

function ConvertFrom-HtmlCellLocal {
    param([string]$CellHtml)
    $cleaned = [regex]::Replace($CellHtml, '(?is)<sup\b.*?</sup>', '')
    $cleaned = [regex]::Replace($cleaned, '\[\^[^\]]+\]', '')
    $svg = [regex]::Match($cleaned, 'aria-label=["''](?<lbl>Supported|Not supported|Included|Not included)["'']')
    if ($svg.Success) { return $svg.Groups['lbl'].Value }
    $decoded = [System.Net.WebUtility]::HtmlDecode(($cleaned -replace '<[^>]+>', ' '))
    return ($decoded -replace '\s+', ' ').Trim()
}

function Get-HtmlTablesLocal {
    param([Parameter(Mandatory)][string]$Html)

    $scope = [regex]::Match($Html, '(?is)<main\b.*?</main>').Value
    if (-not $scope) { $scope = $Html }

    $tokens = [regex]::Matches($scope, '(?is)<h(?<lvl>[234])\b[^>]*>(?<htext>.*?)</h\k<lvl>>|(?<table><table\b.*?</table>)')
    $h2 = ''
    $h3 = ''
    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($tok in $tokens) {
        if ($tok.Groups['lvl'].Success) {
            $heading = ConvertFrom-HtmlCellLocal -CellHtml $tok.Groups['htext'].Value
            if ($tok.Groups['lvl'].Value -eq '2') { $h2 = $heading; $h3 = '' }
            elseif ($tok.Groups['lvl'].Value -eq '3') { $h3 = $heading }
            continue
        }

        $trMatches = [regex]::Matches($tok.Groups['table'].Value, '(?is)<tr\b.*?</tr>')
        if ($trMatches.Count -eq 0) { continue }

        $header = @(
            [regex]::Matches($trMatches[0].Value, '(?is)<t[hd]\b[^>]*>(.*?)</t[hd]>') |
                ForEach-Object { ConvertFrom-HtmlCellLocal -CellHtml $_.Groups[1].Value }
        )
        $rows = [System.Collections.Generic.List[hashtable]]::new()
        for ($i = 1; $i -lt $trMatches.Count; $i++) {
            $cells = @(
                [regex]::Matches($trMatches[$i].Value, '(?is)<t[hd]\b[^>]*>(.*?)</t[hd]>') |
                    ForEach-Object { ConvertFrom-HtmlCellLocal -CellHtml $_.Groups[1].Value }
            )
            if ($cells.Count -eq 0 -or (@($cells | Where-Object { $_ }).Count -eq 0)) { continue }
            $row = @{}
            for ($c = 0; $c -lt $header.Count; $c++) {
                $row[$header[$c]] = if ($c -lt $cells.Count) { $cells[$c] } else { '' }
            }
            $rows.Add($row)
        }
        $results.Add([pscustomobject]@{ H2 = $h2; H3 = $h3; Header = $header; Rows = $rows })
    }
    return $results.ToArray()
}

function ConvertTo-CleanModelDisplayLocal {
    param([string]$DisplayName)
    $clean = ($DisplayName -replace '\[\^[^\]]+\]', '' -replace '\s+', ' ').Trim()
    return $clean
}

function ConvertTo-CatalogIdLocal {
    param([Parameter(Mandatory)][string]$DisplayName)

    $clean = ConvertTo-CleanModelDisplayLocal -DisplayName $DisplayName
    switch -Regex ($clean) {
        '(?i)^Claude Opus 4\.8\s*\(fast mode\)' { return 'claude-opus-4.8-fast' }
        '(?i)^(?:Copilot\s+)?Fusion Standard$' { return 'fusion-standard' }
        '(?i)^(?:Copilot\s+)?Fusion High$' { return 'hydrafusion' }
        '(?i)^(?:Copilot\s+|Hydra)?Fusion Max$' { return 'hydrafusion-max' }
    }
    $base = $clean -replace '(?i)\s*\((?:preview|public preview|github)\)\s*$', ''
    $slug = ($base.ToLowerInvariant() -replace '[^a-z0-9.]+', '-').Trim('-')
    return $slug
}

function ConvertTo-RateAliasLocal {
    param([Parameter(Mandatory)][string]$CatalogId, [Parameter(Mandatory)][string]$DisplayName)
    switch ($CatalogId) {
        'claude-opus-4.8-fast' { return 'Claude Opus 4.8 (fast mode)' }
        'fusion-standard' { return 'Copilot Fusion Standard' }
        'hydrafusion' { return 'Copilot Fusion High' }
        'hydrafusion-max' { return 'Copilot Fusion Max' }
        default {
            return (ConvertTo-CleanModelDisplayLocal -DisplayName $DisplayName) -replace '(?i)\s*\((?:public )?preview\)\s*$', ''
        }
    }
}

function ConvertTo-PriceDecimalTextLocal {
    param([string]$Raw)
    if (-not $Raw -or $Raw -match '(?i)^(not applicable|n/a|[-—])$') { return 'n/a' }
    $numText = ($Raw -replace '[$ ,]', '').Trim()
    $val = [decimal]0
    if (-not [decimal]::TryParse($numText, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$val)) {
        throw "Unable to parse price cell '$Raw'."
    }
    # Preserve at least 2 decimal places (`2.00`, `0.10`), and up to 4 when needed (`0.175`, `0.125`, `0.075`, `0.025`).
    $two = $val.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
    if ([decimal]::Parse($two, [System.Globalization.CultureInfo]::InvariantCulture) -eq $val) { return $two }
    return $val.ToString('0.00##', [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-NormalizedThresholdLocal {
    param([string]$DefaultThreshold, [string]$LcThreshold)
    if (-not $LcThreshold -or $DefaultThreshold -match '(?i)^not applicable$') {
        return 'none (flat rate)'
    }
    $d = ($DefaultThreshold -replace '\s+', '')
    $l = ($LcThreshold -replace '\s+', '')
    return "$d / $l"
}

function ConvertTo-RatesTemplateThresholdLocal {
    param([string]$CatalogThreshold)
    if ($CatalogThreshold -eq 'none (flat rate)') { return 'none (flat rate)' }
    return ($CatalogThreshold -replace '≤', '\<=')
}

function Get-BlendedScoreLocal {
    param([string]$InputRate, [string]$CachedRate, [string]$CacheWriteRate, [string]$OutputRate)
    $toDec = {
        param($s)
        $d = [decimal]0
        if ($s -and $s -notin @('n/a', '—') -and [decimal]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
        return [decimal]0
    }
    $blended = ([decimal]0.20 * (& $toDec $InputRate)) +
    ([decimal]0.80 * (& $toDec $CachedRate)) +
    ([decimal]0.08 * (& $toDec $CacheWriteRate)) +
    ([decimal]0.02 * (& $toDec $OutputRate))
    return ([Math]::Round($blended, 3, [System.MidpointRounding]::AwayFromZero)).ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-ExistingCuratedCatalogLocal {
    param([string]$Path)
    $curated = @{
        Fit = @{}
        Capability = @{}
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $curated }
    $raw = (Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n"
    $header = $null
    $rows = $null
    $tables = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($line in ($raw -split "`n")) {
        if ($line -notmatch '^\s*\|') {
            if ($header) { $tables.Add([pscustomobject]@{ Header = $header; Rows = $rows }) }
            $header = $null; $rows = $null
            continue
        }
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') { continue }
        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim().Trim('`').Trim() })
        if (-not $header) {
            $header = $cells
            $rows = [System.Collections.Generic.List[hashtable]]::new()
            continue
        }
        $r = @{}
        for ($i = 0; $i -lt $header.Count; $i++) { $r[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' } }
        $rows.Add($r)
    }
    if ($header) { $tables.Add([pscustomobject]@{ Header = $header; Rows = $rows }) }

    foreach ($t in $tables) {
        if ('Catalog ID' -in $t.Header -and 'Capability class' -in $t.Header) {
            foreach ($r in $t.Rows) {
                if ($r['Catalog ID']) { $curated.Capability[$r['Catalog ID']] = $r }
            }
        }
        elseif ('Catalog ID' -in $t.Header -and 'Blended' -in $t.Header) {
            foreach ($r in $t.Rows) {
                if ($r['Catalog ID']) { $curated.Fit[$r['Catalog ID']] = $r }
            }
        }
    }
    return $curated
}

function Resolve-ModelCurationLocal {
    <#
    .SYNOPSIS
        Returns capability class, best-fit assignment classes, family, generation,
        rates-template cost tier, and 0..3 Assignment Fit scores for a model.
    #>
    param(
        [Parameter(Mandatory)][string]$CatalogId,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$PricingCategory,
        [Parameter(Mandatory)][decimal]$InputPrice,
        [AllowEmptyString()][string]$TaskArea = '',
        [AllowEmptyString()][string]$ExcelsAt = '',
        [Parameter(Mandatory)][hashtable]$ExistingCurated
    )

    # Explicit editorial baseline for well-known and newly released models; unknown future
    # models fall through to the deterministic category + task-area derivation below.
    $presets = @{
        'gpt-5.3-codex'       = @{ Cap = 'code-specialized'; Best = 'implementation'; Fam = 'gpt-codex'; Gen = '5.3'; Tier = 'fast'; Fit = @(1, 1, 3, 2, 0, 1, 0) }
        'gpt-5.4-nano'        = @{ Cap = 'fast-lightweight'; Best = 'intake, bookkeeping'; Fam = 'gpt-nano'; Gen = '5.4'; Tier = 'fast'; Fit = @(0, 0, 0, 0, 0, 1, 2) }
        'gpt-5.6-luna'        = @{ Cap = 'fast-lightweight'; Best = 'intake, bookkeeping'; Fam = 'gpt-luna'; Gen = '5.6'; Tier = 'fast'; Fit = @(0, 0, 1, 0, 0, 1, 2) }
        'gpt-5.6-sol'         = @{ Cap = 'frontier-reasoning'; Best = 'research, planning, review, council'; Fam = 'gpt-sol'; Gen = '5.6'; Tier = 'extended'; Fit = @(3, 3, 2, 3, 2, 2, 0) }
        'gpt-5.6-terra'       = @{ Cap = 'balanced'; Best = 'planning, implementation, review'; Fam = 'gpt-terra'; Gen = '5.6'; Tier = 'default'; Fit = @(1, 2, 2, 2, 1, 3, 0) }
        'gpt-6-astra'         = @{ Cap = 'frontier-reasoning'; Best = 'research, planning, review, council'; Fam = 'gpt-astra'; Gen = '6'; Tier = 'extended'; Fit = @(3, 3, 2, 2, 3, 1, 0) }
        'gpt-6-luna'          = @{ Cap = 'fast-lightweight'; Best = 'intake, bookkeeping'; Fam = 'gpt-luna'; Gen = '6'; Tier = 'fast'; Fit = @(0, 0, 1, 0, 0, 1, 2) }
        'gpt-6-sol'           = @{ Cap = 'balanced'; Best = 'planning, implementation, review'; Fam = 'gpt-sol'; Gen = '6'; Tier = 'default'; Fit = @(1, 2, 3, 3, 2, 2, 0) }
        'gpt-6.1-sol'         = @{ Cap = 'frontier-reasoning'; Best = 'implementation, review, planning'; Fam = 'gpt-sol'; Gen = '6.1'; Tier = 'default'; Fit = @(2, 2, 3, 2, 2, 2, 0) }
        'gpt-6.1-terra'       = @{ Cap = 'balanced'; Best = 'planning, implementation, review, intake'; Fam = 'gpt-terra'; Gen = '6.1'; Tier = 'default'; Fit = @(1, 2, 3, 2, 1, 3, 0) }
        'claude-haiku-4.5'    = @{ Cap = 'fast-lightweight'; Best = 'intake, bookkeeping'; Fam = 'claude-haiku'; Gen = '4.5'; Tier = 'fast'; Fit = @(1, 0, 1, 1, 0, 2, 3) }
        'claude-haiku-5.5'    = @{ Cap = 'fast-lightweight'; Best = 'intake, bookkeeping'; Fam = 'claude-haiku'; Gen = '5.5'; Tier = 'fast'; Fit = @(1, 0, 1, 1, 0, 2, 3) }
        'claude-sonnet-4'     = @{ Cap = 'balanced'; Best = 'planning, implementation'; Fam = 'claude-sonnet'; Gen = '4'; Tier = 'default'; Fit = @(1, 1, 1, 1, 1, 1, 0) }
        'claude-sonnet-4.6'   = @{ Cap = 'balanced'; Best = 'planning, implementation, review'; Fam = 'claude-sonnet'; Gen = '4.6'; Tier = 'default'; Fit = @(1, 2, 2, 2, 1, 2, 0) }
        'claude-sonnet-5'     = @{ Cap = 'balanced'; Best = 'planning, implementation, review'; Fam = 'claude-sonnet'; Gen = '5'; Tier = 'default'; Fit = @(2, 2, 2, 2, 2, 3, 0) }
        'claude-sonnet-5.5'   = @{ Cap = 'balanced'; Best = 'implementation, intake, review'; Fam = 'claude-sonnet'; Gen = '5.5'; Tier = 'default'; Fit = @(2, 2, 3, 2, 2, 3, 0) }
        'claude-opus-4.8'     = @{ Cap = 'frontier-reasoning'; Best = 'research, planning, review, council'; Fam = 'claude-opus'; Gen = '4.8'; Tier = 'extended'; Fit = @(2, 3, 2, 3, 3, 2, 0) }
        'claude-opus-4.8-fast'= @{ Cap = 'frontier-reasoning'; Best = 'research, planning, review, council'; Fam = 'claude-opus-fast'; Gen = '4.8'; Tier = 'extended'; Fit = @(2, 2, 2, 2, 2, 1, 0) }
        'claude-opus-5'       = @{ Cap = 'frontier-reasoning'; Best = 'research, planning, review, council'; Fam = 'claude-opus'; Gen = '5'; Tier = 'extended'; Fit = @(3, 3, 2, 3, 3, 2, 0) }
        'claude-opus-5.5'     = @{ Cap = 'frontier-reasoning'; Best = 'research, council, review'; Fam = 'claude-opus'; Gen = '5.5'; Tier = 'extended'; Fit = @(3, 2, 2, 2, 2, 1, 0) }
        'claude-fable-5'      = @{ Cap = 'frontier-reasoning'; Best = 'research, planning'; Fam = 'claude-fable'; Gen = '5'; Tier = 'extended'; Fit = @(3, 3, 2, 2, 2, 1, 0) }
        'claude-fable-5.1'    = @{ Cap = 'frontier-reasoning'; Best = 'research, planning'; Fam = 'claude-fable'; Gen = '5.1'; Tier = 'extended'; Fit = @(3, 2, 3, 2, 2, 1, 0) }
        'claude-fable-5.2'    = @{ Cap = 'frontier-reasoning'; Best = 'research, planning, implementation'; Fam = 'claude-fable'; Gen = '5.2'; Tier = 'extended'; Fit = @(3, 3, 3, 2, 2, 1, 0) }
        'gemini-3.8-flash'    = @{ Cap = 'balanced'; Best = 'intake, bookkeeping'; Fam = 'gemini-flash'; Gen = '3.8'; Tier = 'fast'; Fit = @(1, 1, 1, 1, 0, 1, 2) }
        'gemini-4-argon'      = @{ Cap = 'frontier-reasoning'; Best = 'planning, implementation, review, council'; Fam = 'gemini-argon'; Gen = '4'; Tier = 'default'; Fit = @(2, 3, 3, 3, 2, 2, 0) }
        'gemini-4-carbon'     = @{ Cap = 'frontier-reasoning'; Best = 'implementation, review, council'; Fam = 'gemini-carbon'; Gen = '4'; Tier = 'default'; Fit = @(2, 2, 3, 3, 3, 2, 0) }
        'grok-4.5'            = @{ Cap = 'balanced'; Best = 'planning, implementation, review'; Fam = 'grok'; Gen = '4.5'; Tier = 'default'; Fit = @(1, 1, 2, 1, 1, 1, 0) }
        'grok-4.6'            = @{ Cap = 'balanced'; Best = 'planning, implementation, review'; Fam = 'grok'; Gen = '4.6'; Tier = 'default'; Fit = @(1, 1, 2, 1, 1, 1, 0) }
        'grok-4.7'            = @{ Cap = 'balanced'; Best = 'planning, implementation, review'; Fam = 'grok'; Gen = '4.7'; Tier = 'default'; Fit = @(1, 2, 2, 2, 1, 2, 0) }
        'mai-code-1.1-flash'  = @{ Cap = 'fast-lightweight'; Best = 'intake, bookkeeping'; Fam = 'mai-code-flash'; Gen = '1.1'; Tier = 'fast'; Fit = @(0, 0, 1, 0, 0, 1, 2) }
        'kimi-k3'             = @{ Cap = 'code-specialized'; Best = 'implementation'; Fam = 'kimi'; Gen = '3'; Tier = 'default'; Fit = @(1, 1, 2, 1, 0, 1, 0) }
        'fusion-standard'     = @{ Cap = 'balanced'; Best = 'planning, implementation, intake, bookkeeping'; Fam = 'copilot-fusion'; Gen = '1'; Tier = 'fast'; Fit = @(1, 2, 2, 1, 1, 2, 2) }
        'hydrafusion'         = @{ Cap = 'balanced'; Best = 'research, planning, implementation, review, intake'; Fam = 'copilot-fusion'; Gen = '2'; Tier = 'default'; Fit = @(2, 2, 2, 2, 1, 2, 1) }
        'hydrafusion-max'     = @{ Cap = 'frontier-reasoning'; Best = 'research, planning, implementation, review, council, intake'; Fam = 'copilot-fusion'; Gen = '3'; Tier = 'default'; Fit = @(2, 2, 2, 2, 2, 2, 1) }
    }

    if ($presets.ContainsKey($CatalogId)) {
        $p = $presets[$CatalogId]
        $fitMap = @{}
        for ($i = 0; $i -lt $assignmentClasses.Count; $i++) { $fitMap[$assignmentClasses[$i]] = [int]$p.Fit[$i] }
        return [pscustomobject]@{
            CapabilityClass = $p.Cap
            BestFit         = $p.Best
            Family          = $p.Fam
            Generation      = $p.Gen
            RateTier        = $p.Tier
            FitScores       = $fitMap
        }
    }

    # Preserve previously curated values if a model is already in model-catalog.md and not in presets.
    if ($ExistingCurated.Fit.ContainsKey($CatalogId) -and $ExistingCurated.Capability.ContainsKey($CatalogId)) {
        $exFit = $ExistingCurated.Fit[$CatalogId]
        $exCap = $ExistingCurated.Capability[$CatalogId]
        $fitMap = @{}
        foreach ($c in $assignmentClasses) { $fitMap[$c] = [int]$exFit[$c] }
        $tier = if ($InputPrice -ge 4.0) { 'extended' } elseif ($InputPrice -lt 1.0 -or $PricingCategory -eq 'Lightweight') { 'fast' } else { 'default' }
        return [pscustomobject]@{
            CapabilityClass = $exCap['Capability class']
            BestFit         = $exCap['Best-fit assignment classes']
            Family          = $exFit['Family']
            Generation      = $exFit['Generation']
            RateTier        = $tier
            FitScores       = $fitMap
        }
    }

    # Automatic curation for brand-new models discovered upstream.
    $combinedText = "$DisplayName $TaskArea $ExcelsAt".ToLowerInvariant()
    $cap = if ($CatalogId -match '(-codex|-code)(-|$)' -or ($PricingCategory -ne 'Powerful' -and $TaskArea -match '(?i)agentic software development')) {
        'code-specialized'
    }
    elseif ($PricingCategory -eq 'Powerful') {
        'frontier-reasoning'
    }
    elseif ($PricingCategory -eq 'Lightweight' -or $TaskArea -match '(?i)fast help|simple or repetitive') {
        'fast-lightweight'
    }
    else {
        'balanced'
    }

    $rateTier = if ($InputPrice -ge 4.0) { 'extended' }
    elseif ($PricingCategory -eq 'Lightweight' -or $InputPrice -lt 1.0) { 'fast' }
    else { 'default' }

    $genMatch = [regex]::Match($CatalogId, '(?<ver>\d+(?:\.\d+)?)')
    $gen = if ($genMatch.Success) { $genMatch.Groups['ver'].Value } else { '1' }
    $fam = (($CatalogId -replace '-?\d+(?:\.\d+)?', '') -replace '-{2,}', '-').Trim('-')
    if (-not $fam) { $fam = $Provider.ToLowerInvariant() }

    $fitArr = switch ($cap) {
        'frontier-reasoning' {
            if ($combinedText -match 'security|review|edge cases') { @(2, 3, 3, 3, 3, 2, 0) }
            elseif ($combinedText -match 'coding|agentic') { @(3, 3, 3, 2, 2, 1, 0) }
            else { @(3, 3, 2, 3, 3, 2, 0) }
        }
        'code-specialized' { @(1, 1, 3, 2, 0, 1, 0) }
        'fast-lightweight' { @(0, 0, 1, 0, 0, 2, 2) }
        default { @(1, 2, 2, 2, 1, 2, 0) }
    }
    $bestList = switch ($cap) {
        'frontier-reasoning' { 'research, planning, implementation, review, council' }
        'code-specialized' { 'implementation' }
        'fast-lightweight' { 'intake, bookkeeping' }
        default { 'planning, implementation, review' }
    }
    $fitMap = @{}
    for ($i = 0; $i -lt $assignmentClasses.Count; $i++) { $fitMap[$assignmentClasses[$i]] = [int]$fitArr[$i] }

    return [pscustomobject]@{
        CapabilityClass = $cap
        BestFit         = $bestList
        Family          = $fam
        Generation      = $gen
        RateTier        = $rateTier
        FitScores       = $fitMap
    }
}

function ConvertTo-VersionSortableLocal {
    param([string]$Gen)
    $parts = @($Gen -split '\.' | Where-Object { $_ -match '^\d+$' })
    if ($parts.Count -eq 0) { return [version]'0.0' }
    if ($parts.Count -eq 1) { $parts += '0' }
    return [version]($parts[0..([Math]::Min(3, $parts.Count - 1))] -join '.')
}

function Get-SemanticCatalogDigestLocal {
    param([string]$CatalogText, [string]$RatesText)
    $normCat = ($CatalogText -replace "`r`n", "`n") `
        -replace '(?m)^\s*last_updated:\s*"\d{4}-\d{2}-\d{2}"\s*$', '  last_updated: "DATE"' `
        -replace '\*\*Retrieved:\s*\d{4}-\d{2}-\d{2}\*\*', '**Retrieved: DATE**' `
        -replace 'retrieved \d{4}-\d{2}-\d{2}', 'retrieved DATE' `
        -replace '`\d{4}-\d{2}-\d{2}` as of this snapshot', '`DATE` as of this snapshot'
    $normRates = ($RatesText -replace "`r`n", "`n") `
        -replace '(?m)^\s*last_updated:\s*"\d{4}-\d{2}-\d{2}"\s*$', '  last_updated: "DATE"' `
        -replace 'Observed-on:\s*\d{4}-\d{2}-\d{2}', 'Observed-on: DATE' `
        -replace '`\d{4}-\d{2}-\d{2}` as of this snapshot', '`DATE` as of this snapshot'

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$normCat`n===RATES===`n$normRates")
        return 'sha256:' + (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }))
    }
    finally {
        $sha.Dispose()
    }
}

# 1. Fetch and parse upstream HTML sources
$supportedHtml = Get-SourceHtmlLocal -LocalPath $SupportedModelsHtmlPath -Uri $SupportedModelsUri -Label 'Supported AI models'
$pricingHtml = Get-SourceHtmlLocal -LocalPath $PricingHtmlPath -Uri $PricingUri -Label 'Models and pricing'
$comparisonHtml = Get-SourceHtmlLocal -LocalPath $ComparisonHtmlPath -Uri $ComparisonUri -Label 'AI model comparison'
$fusionHtml = Get-SourceHtmlLocal -LocalPath $FusionHtmlPath -Uri $FusionUri -Label 'Copilot Fusion'

$supportedTables = @(Get-HtmlTablesLocal -Html $supportedHtml)
$pricingTables = @(Get-HtmlTablesLocal -Html $pricingHtml)
$comparisonTables = @(Get-HtmlTablesLocal -Html $comparisonHtml)
$fusionTables = @(Get-HtmlTablesLocal -Html $fusionHtml)

$supportedMain = @($supportedTables | Where-Object { $_.H2 -match '^Supported AI models in Copilot' -and 'Model name' -in $_.Header } | Select-Object -First 1)
if ($supportedMain.Count -eq 0 -or $supportedMain[0].Rows.Count -lt 5) {
    throw 'Upstream Supported AI models table missing or truncated; preserving existing catalog.'
}

$supportedById = [ordered]@{}
foreach ($row in $supportedMain[0].Rows) {
    $disp = ConvertTo-CleanModelDisplayLocal -DisplayName $row['Model name']
    if (-not $disp) { continue }
    $cid = ConvertTo-CatalogIdLocal -DisplayName $disp
    $supportedById[$cid] = [pscustomobject]@{
        CatalogId     = $cid
        DisplayName   = $disp
        Provider      = $row['Provider']
        ReleaseStatus = $row['Release status']
    }
}

$extendedById = @{}
$extTable = @($supportedTables | Where-Object { $_.H2 -match '^Models with extended capabilities' } | Select-Object -First 1)
if ($extTable.Count -gt 0) {
    foreach ($row in $extTable[0].Rows) {
        $cid = ConvertTo-CatalogIdLocal -DisplayName $row['Model']
        $ctxCol = @($extTable[0].Header | Where-Object { $_ -match '1 million' } | Select-Object -First 1)
        $reasCol = @($extTable[0].Header | Where-Object { $_ -match 'reasoning' } | Select-Object -First 1)
        $extendedById[$cid] = [pscustomobject]@{
            Context1M   = ($ctxCol.Count -gt 0 -and $row[$ctxCol[0]] -eq 'Supported')
            Reasoning   = ($reasCol.Count -gt 0 -and $row[$reasCol[0]] -eq 'Supported')
        }
    }
}

$cliClientIncluded = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$clientTable = @($supportedTables | Where-Object { $_.H2 -match '^Supported AI models per client' -and 'Copilot CLI' -in $_.Header } | Select-Object -First 1)
if ($clientTable.Count -gt 0) {
    foreach ($row in $clientTable[0].Rows) {
        if ($row['Copilot CLI'] -eq 'Included') {
            [void]$cliClientIncluded.Add((ConvertTo-CatalogIdLocal -DisplayName $row['Model']))
        }
    }
}
# GPT-6.1 Sol is advertised on Copilot CLI / App even when omitted from the per-client summary table.
if ($supportedById.Contains('gpt-6.1-sol')) { [void]$cliClientIncluded.Add('gpt-6.1-sol') }

$retiredFromDocs = @{}
$retireTable = @($supportedTables | Where-Object { $_.H2 -match '^Model retirement history' -and 'Model name' -in $_.Header } | Select-Object -First 1)
if ($retireTable.Count -gt 0) {
    foreach ($row in $retireTable[0].Rows) {
        $cid = ConvertTo-CatalogIdLocal -DisplayName $row['Model name']
        if (-not $retiredFromDocs.ContainsKey($cid)) {
            $retiredFromDocs[$cid] = [pscustomobject]@{
                Name = $row['Model name']
                Date = $row['Retirement date']
                Alternative = $row['Suggested alternative']
            }
        }
    }
}

$comparisonById = [ordered]@{}
$compMain = @($comparisonTables | Where-Object { 'Task area' -in $_.Header -and 'Model' -in $_.Header } | Select-Object -First 1)
if ($compMain.Count -gt 0) {
    $excelsCol = @($compMain[0].Header | Where-Object { $_ -match '^Excels at' } | Select-Object -First 1)[0]
    foreach ($row in $compMain[0].Rows) {
        $disp = ConvertTo-CleanModelDisplayLocal -DisplayName $row['Model']
        if (-not $disp) { continue }
        $cid = ConvertTo-CatalogIdLocal -DisplayName $disp
        $comparisonById[$cid] = [pscustomobject]@{
            CatalogId   = $cid
            DisplayName = $disp
            TaskArea    = $row['Task area']
            ExcelsAt    = if ($excelsCol) { $row[$excelsCol] } else { '' }
        }
    }
}

$pricedById = [ordered]@{}
$providerOrder = [System.Collections.Generic.List[string]]::new()
foreach ($tbl in $pricingTables) {
    if ($tbl.H2 -notmatch '^Pricing tables') { continue }
    $provider = $tbl.H3
    if (-not $provider -or $provider -match '(?i)Image generation|Fine-tuned') { continue }
    if ('Input' -notin $tbl.Header -or 'Output' -notin $tbl.Header) { continue }
    if ($tbl.Rows.Count -eq 0) { continue }
    if ($provider -notin $providerOrder) { $providerOrder.Add($provider) }

    $hasTierCol = 'Tier' -in $tbl.Header
    $hasCacheWriteCol = 'Cache write' -in $tbl.Header
    $threshCol = @($tbl.Header | Where-Object { $_ -match '^Threshold' } | Select-Object -First 1)

    foreach ($row in $tbl.Rows) {
        $disp = ConvertTo-CleanModelDisplayLocal -DisplayName $row['Model']
        if (-not $disp) { continue }
        $cid = ConvertTo-CatalogIdLocal -DisplayName $disp
        $tierKind = if ($hasTierCol -and $row['Tier']) { $row['Tier'] } else { 'Default' }
        $threshRaw = if ($threshCol.Count -gt 0) { $row[$threshCol[0]] } else { 'Not applicable' }
        $inp = ConvertTo-PriceDecimalTextLocal -Raw $row['Input']
        $cac = ConvertTo-PriceDecimalTextLocal -Raw $row['Cached input']
        $cw = if ($hasCacheWriteCol) { ConvertTo-PriceDecimalTextLocal -Raw $row['Cache write'] } else { '0' }
        $out = ConvertTo-PriceDecimalTextLocal -Raw $row['Output']

        if (-not $pricedById.Contains($cid)) {
            $pricedById[$cid] = [ordered]@{
                CatalogId        = $cid
                DisplayName      = $disp
                Provider         = $provider
                ReleaseStatus    = $row['Release status']
                Category         = $row['Category']
                HasCacheWriteCol = $hasCacheWriteCol
                DefaultThreshold = $threshRaw
                LcThresholdRaw   = ''
                Input            = $inp
                Cached           = $cac
                CacheWrite       = $cw
                Output           = $out
                LcInput          = 'n/a'
                LcCached         = 'n/a'
                LcCacheWrite     = 'n/a'
                LcOutput         = 'n/a'
            }
        }
        elseif ($tierKind -match '(?i)Long context') {
            $pricedById[$cid].LcThresholdRaw = $threshRaw
            $pricedById[$cid].LcInput = $inp
            $pricedById[$cid].LcCached = $cac
            $pricedById[$cid].LcCacheWrite = $cw
            $pricedById[$cid].LcOutput = $out
        }
    }
}

if ($pricedById.Count -lt 10) {
    throw "Upstream pricing tables yielded only $($pricedById.Count) models; preserving existing catalog."
}

# Parse Copilot Fusion effort levels (Standard, High, Max; skip non-selectable Fusion Fast).
$fusionLevels = [System.Collections.Generic.List[pscustomobject]]::new()
$fusionTable = @($fusionTables | Where-Object { $_.H2 -match 'Copilot Fusion effort levels' -and 'Effort level' -in $_.Header } | Select-Object -First 1)
$fusionSpecMap = [ordered]@{
    'Fusion Standard' = [ordered]@{
        CatalogId = 'fusion-standard'; DisplayName = 'Copilot Fusion Standard'; RateAlias = 'Copilot Fusion Standard'
        Advertised = $false; Input = '0.40'; Cached = '0.025'; CacheWrite = '0.50'; Output = '2.00'
        LcInput = '0.80'; LcCached = '0.05'; LcCacheWrite = '1.00'; LcOutput = '3.00'
        CatalogNote = 'Copilot Fusion `standard` effort (`--model fusion --fusion-tier standard`); single-model routing across versatile and lightweight models (`1.0x` token footprint; billed at underlying model rates)'
        RateNote = 'Fusion Standard (`--fusion-tier standard`); single-model router'
    }
    'Fusion High' = [ordered]@{
        CatalogId = 'hydrafusion'; DisplayName = 'Copilot Fusion High'; RateAlias = 'Copilot Fusion High'
        Advertised = $true; Input = '0.60'; Cached = '0.04'; CacheWrite = '0.75'; Output = '3.00'
        LcInput = '1.20'; LcCached = '0.08'; LcCacheWrite = '1.50'; LcOutput = '4.50'
        CatalogNote = 'Copilot Fusion `high` effort (`hydrafusion` / `--fusion-tier high`); balanced cascade orchestration with moderate token savings (~0.55x token footprint; billed at underlying model rates)'
        RateNote = 'Fusion High (`hydrafusion`); balanced cascade (~0.55x tokens)'
    }
    'Fusion Max' = [ordered]@{
        CatalogId = 'hydrafusion-max'; DisplayName = 'Copilot Fusion Max'; RateAlias = 'Copilot Fusion Max'
        Advertised = $true; Input = '0.80'; Cached = '0.05'; CacheWrite = '1.00'; Output = '4.00'
        LcInput = '1.60'; LcCached = '0.10'; LcCacheWrite = '2.00'; LcOutput = '6.00'
        CatalogNote = 'Copilot Fusion `max` effort (`hydrafusion-max` / `--fusion-tier max`); frontier cascade/critique orchestration (~0.35x token footprint; billed at underlying model rates)'
        RateNote = 'Fusion Max (`hydrafusion-max`); frontier cascade (~0.35x tokens)'
    }
}
if ($fusionTable.Count -gt 0) {
    foreach ($row in $fusionTable[0].Rows) {
        $lvl = ($row['Effort level'] -replace '\*+', '').Trim()
        if ($row['Typical use'] -match '(?i)Not selectable by users') { continue }
        if ($fusionSpecMap.Contains($lvl)) {
            $fusionLevels.Add([pscustomobject]$fusionSpecMap[$lvl])
        }
    }
}
if ($fusionLevels.Count -eq 0) {
    foreach ($k in $fusionSpecMap.Keys) { $fusionLevels.Add([pscustomobject]$fusionSpecMap[$k]) }
}

$existingCurated = Get-ExistingCuratedCatalogLocal -Path $CatalogOutputPath
$previousIds = @($existingCurated.Capability.Keys)

# Determine host-advertised IDs when not explicitly passed.
$effectiveAdvertised = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if ($AdvertisedModels.Count -gt 0) {
    foreach ($m in $AdvertisedModels) {
        if ($m) { [void]$effectiveAdvertised.Add($m.Trim().ToLowerInvariant()) }
    }
}
else {
    foreach ($id in $cliClientIncluded) {
        # Enterprise-gated Fable models and preview fast-mode Opus are CLI-capable when enabled,
        # while default Copilot CLI / App `task.model` enum omits them unless enabled.
        if ($id -notmatch '^claude-fable-' -and $id -notin @('claude-opus-4.8-fast', 'claude-sonnet-4.6', 'kimi-k3', 'grok-4.5')) {
            [void]$effectiveAdvertised.Add($id)
        }
    }
    [void]$effectiveAdvertised.Add('hydrafusion')
    [void]$effectiveAdvertised.Add('hydrafusion-max')
    [void]$effectiveAdvertised.Add('gpt-5.6-sol-fast')
}

# Build unified active catalog records (union of Supported AI models and Pricing tables + Copilot Fusion).
$allActiveIds = [System.Collections.Generic.List[string]]::new()
foreach ($id in $pricedById.Keys) { if ($id -notin $allActiveIds) { $allActiveIds.Add($id) } }
foreach ($id in $supportedById.Keys) { if ($id -notin $allActiveIds) { $allActiveIds.Add($id) } }

$catalogModels = [ordered]@{}
$contradictions = [System.Collections.Generic.List[string]]::new()

foreach ($cid in $allActiveIds) {
    $sup = if ($supportedById.Contains($cid)) { $supportedById[$cid] } else { $null }
    $prc = if ($pricedById.Contains($cid)) { [pscustomobject]$pricedById[$cid] } else { $null }
    $cmp = if ($comparisonById.Contains($cid)) { $comparisonById[$cid] } else { $null }
    $ext = if ($extendedById.ContainsKey($cid)) { $extendedById[$cid] } else { $null }

    $display = if ($sup) { $sup.DisplayName } elseif ($prc) { $prc.DisplayName } else { $cid }
    $provider = if ($prc) { $prc.Provider } else { $sup.Provider }
    $isAdvertised = $effectiveAdvertised.Contains($cid)
    $idSource = if ($isAdvertised) { 'advertised' } else { 'constructed' }

    $status = if ($sup -and $prc) {
        if ($isAdvertised) { $sup.ReleaseStatus } else { "$($sup.ReleaseStatus) (documented, not advertised)" }
    }
    elseif ($prc -and -not $sup) {
        $contradictions.Add("**$display is priced but not currently in Supported AI models.** The `"Models and pricing`" $($prc.Provider) table lists $display (`$$($prc.Input) / `$$($prc.Cached) / $(if ($prc.CacheWrite -ne 'n/a') { "`$$($prc.CacheWrite) / " } else { '' })`$$($prc.Output)), while `"Supported AI models`" omits it. Retained cautiously so historical/legacy dispatches remain priceable and auditable.")
        '**priced, not in current supported list** — see Contradictions below'
    }
    else {
        "$($sup.ReleaseStatus) (unpriced)"
    }

    $ctxWindow = if ($ext -and $ext.Context1M) { '1M' } else { 'undocumented' }
    $reasEffort = if ($ext -and $ext.Reasoning) { 'configurable' } else { 'undocumented' }

    $inputDec = [decimal]0
    if ($prc -and $prc.Input -ne 'n/a') {
        $inputDec = [decimal]::Parse($prc.Input, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $curation = Resolve-ModelCurationLocal `
        -CatalogId $cid `
        -DisplayName $display `
        -Provider $provider `
        -PricingCategory $(if ($prc) { $prc.Category } else { 'Versatile' }) `
        -InputPrice $inputDec `
        -TaskArea $(if ($cmp) { $cmp.TaskArea } else { '' }) `
        -ExcelsAt $(if ($cmp) { $cmp.ExcelsAt } else { '' }) `
        -ExistingCurated $existingCurated

    $noteParts = [System.Collections.Generic.List[string]]::new()
    if ($cmp -and $cmp.TaskArea) {
        $summary = if ($cmp.ExcelsAt) { "$($cmp.TaskArea) — $($cmp.ExcelsAt)" } else { $cmp.TaskArea }
        $noteParts.Add("`"$summary`"")
    }
    elseif (-not $sup) {
        $noteParts.Add('Not in "Supported AI models" at retrieval; carried because the pricing table still lists it')
    }
    else {
        $noteParts.Add("$($prc.Category) category on the pricing page")
    }
    if ($cid -eq 'gpt-5.3-codex') { $noteParts.Add('LTS fallback model for Auto selection') }
    if ($cid -match '^claude-fable-') { $noteParts.Add('enterprise ZDR/EFS data-retention gating') }
    if ($cid -eq 'kimi-k3') { $noteParts.Add('elevated-risk safeguards per source note') }
    if ($cid -eq 'mai-code-1.1-flash') { $noteParts.Add('continuously improving checkpoint') }

    $lcThreshold = if ($prc) { ConvertTo-NormalizedThresholdLocal -DefaultThreshold $prc.DefaultThreshold -LcThreshold $prc.LcThresholdRaw } else { 'none (flat rate)' }
    $rateAlias = ConvertTo-RateAliasLocal -CatalogId $cid -DisplayName $display
    $blended = if ($prc) {
        Get-BlendedScoreLocal -InputRate $prc.Input -CachedRate $prc.Cached -CacheWriteRate $prc.CacheWrite -OutputRate $prc.Output
    }
    else { $null }

    $rateShortNote = switch -Regex ($cid) {
        '^gpt-5\.3-codex$' { 'code-specialized; Auto LTS fallback' }
        '^claude-fable-' { 'frontier reasoning; ZDR/EFS gated' }
        '^claude-opus-4\.8-fast$' { 'frontier reasoning; fast mode' }
        '^claude-sonnet-4$' { 'priced in billing docs; prefer Sonnet 5.5' }
        '^gemini-3\.8-flash$' { 'versatile; promo rate through 2026-12-31' }
        '^gemini-4-' { 'frontier reasoning; promo rate to 2026-12-01' }
        '^mai-code-' { 'lightweight; continuously improving' }
        '^kimi-k3$' { 'long-context agentic; safeguards noted' }
        default {
            switch ($curation.CapabilityClass) {
                'frontier-reasoning' { 'high-capability reasoning' }
                'code-specialized' { 'code-specialized' }
                'fast-lightweight' { 'lightweight' }
                default { 'versatile' }
            }
        }
    }

    $catalogModels[$cid] = [pscustomobject]@{
        CatalogId       = $cid
        DisplayName     = $display
        RateAlias       = $rateAlias
        Provider        = $provider
        IdSource        = $idSource
        IsAdvertised    = $isAdvertised
        IsSupported     = ($null -ne $sup)
        IsPriced        = ($null -ne $prc)
        IsFusion        = $false
        Status          = $status
        CapabilityClass = $curation.CapabilityClass
        ContextWindow   = $ctxWindow
        ReasoningEffort = $reasEffort
        BestFit         = $curation.BestFit
        Notes           = ($noteParts -join '; ')
        RateShortNote   = $rateShortNote
        Family          = $curation.Family
        Generation      = $curation.Generation
        RateTier        = $curation.RateTier
        FitScores       = $curation.FitScores
        LcThreshold     = $lcThreshold
        Input           = if ($prc) { $prc.Input } else { 'unpriced' }
        Cached          = if ($prc) { $prc.Cached } else { 'unpriced' }
        CacheWrite      = if ($prc) { $prc.CacheWrite } else { 'n/a' }
        Output          = if ($prc) { $prc.Output } else { 'unpriced' }
        LcInput         = if ($prc) { $prc.LcInput } else { 'n/a' }
        LcCached        = if ($prc) { $prc.LcCached } else { 'n/a' }
        LcCacheWrite    = if ($prc) { $prc.LcCacheWrite } else { 'n/a' }
        LcOutput        = if ($prc) { $prc.LcOutput } else { 'n/a' }
        Blended         = $blended
    }
}

# Append the three Copilot Fusion effort levels (`fusion-standard`, `hydrafusion`, `hydrafusion-max`).
foreach ($f in $fusionLevels) {
    $cid = $f.CatalogId
    $isAdv = $effectiveAdvertised.Contains($cid)
    $curation = Resolve-ModelCurationLocal `
        -CatalogId $cid -DisplayName $f.DisplayName -Provider 'Copilot Fusion' `
        -PricingCategory $(if ($cid -eq 'hydrafusion-max') { 'Powerful' } else { 'Versatile' }) `
        -InputPrice ([decimal]::Parse($f.Input, [System.Globalization.CultureInfo]::InvariantCulture)) `
        -ExistingCurated $existingCurated
    $blended = Get-BlendedScoreLocal -InputRate $f.Input -CachedRate $f.Cached -CacheWriteRate $f.CacheWrite -OutputRate $f.Output
    $catalogModels[$cid] = [pscustomobject]@{
        CatalogId       = $cid
        DisplayName     = $f.DisplayName
        RateAlias       = $f.RateAlias
        Provider        = 'Copilot Fusion'
        IdSource        = if ($isAdv) { 'advertised' } else { 'constructed' }
        IsAdvertised    = $isAdv
        IsSupported     = $true
        IsPriced        = $true
        IsFusion        = $true
        Status          = if ($isAdv) { 'GA' } else { 'GA (documented, not advertised)' }
        CapabilityClass = $curation.CapabilityClass
        ContextWindow   = 'dynamic (pool minimum)'
        ReasoningEffort = 'dynamic (per step)'
        BestFit         = $curation.BestFit
        Notes           = $f.CatalogNote
        RateShortNote   = $f.RateNote
        Family          = $curation.Family
        Generation      = $curation.Generation
        RateTier        = $curation.RateTier
        FitScores       = $curation.FitScores
        LcThreshold     = '≤272K / >272K'
        Input           = $f.Input
        Cached          = $f.Cached
        CacheWrite      = $f.CacheWrite
        Output          = $f.Output
        LcInput         = $f.LcInput
        LcCached        = $f.LcCached
        LcCacheWrite    = $f.LcCacheWrite
        LcOutput        = $f.LcOutput
        Blended         = $blended
    }
}

# Degraded-confidence models: named ONLY in AI model comparison, absent from Supported and Pricing.
$degradedModels = [System.Collections.Generic.List[pscustomobject]]::new()
foreach ($cid in $comparisonById.Keys) {
    if (-not $catalogModels.Contains($cid)) {
        $cmp = $comparisonById[$cid]
        $degradedModels.Add([pscustomobject]@{
                CatalogId   = $cid
                DisplayName = $cmp.DisplayName
                Reason      = "Appears in the `"AI model comparison`" page's recommended-models table (task area: $($cmp.TaskArea.ToLowerInvariant())) but is absent from both `"Supported AI models`" and `"Models and pricing`" at retrieval — named by only one of the three sources, with no corroborating pricing or supported-status row"
            })
    }
}

# Advertised but unevaluated IDs (present in host enum, absent from catalog and degraded).
$unevaluatedIds = @(
    $effectiveAdvertised |
        Where-Object { -not $catalogModels.Contains($_) -and $_ -notin @($degradedModels | ForEach-Object CatalogId) } |
        Sort-Object
)

# Verify every assignment class still has at least one score of 3 among priced models.
$pricedEntries = @($catalogModels.Values | Where-Object { $_.IsPriced })
foreach ($cls in $assignmentClasses) {
    if (@($pricedEntries | Where-Object { $_.FitScores[$cls] -eq 3 }).Count -eq 0) {
        throw "Validation failed: no priced catalog model has Assignment Fit = 3 for class '$cls'."
    }
}

$currentIds = @($catalogModels.Keys)
$addedModels = @($currentIds | Where-Object { $_ -notin $previousIds })
$retiredModels = @($previousIds | Where-Object { $_ -notin $currentIds })

# Check whether we can preserve the existing Retrieved/Observed-on date to avoid date-only churn.
$existingDate = $null
if (Test-Path -LiteralPath $CatalogOutputPath -PathType Leaf) {
    $rawExistingCat = Get-Content -LiteralPath $CatalogOutputPath -Raw
    $mDate = [regex]::Match($rawExistingCat, '\*\*Retrieved:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*')
    if ($mDate.Success) {
        $existingDate = [datetime]::ParseExact($mDate.Groups['date'].Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    }
}

function Format-CatalogMarkdownLocal {
    param([string]$StampDate)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]@(
            '---'
            'name: squad-model-catalog'
            'description: "Declared, dated snapshot of the GitHub Copilot model offering: capability class, per-assignment-class fit scores, context/reasoning documentation status, pricing including long-context tiers, rate-row alias, and host-availability precedence."'
            'license: MIT'
            'metadata:'
            '  authors: "Peter-N91/hve-squad"'
            '  spec_version: "1.1"'
            "  last_updated: `"$StampDate`""
            '---'
            ''
            '# Squad Model Catalog'
            ''
            '**This catalog is declared, not live-discovered.** No chat or interactive Copilot host exposes a callable model-list API to the agent at dispatch time (research finding F7); the CLI''s dispatch tool advertises an enum, which this catalog intersects. Every row below was retrieved by fetching GitHub''s own documentation pages on the date stamped below (`scripts/Sync-ModelCatalog.ps1`), not by querying a runtime discovery endpoint. A routing procedure that reads this file is reading a curated, dated snapshot — never an assertion that the catalog was assembled live for the current session.'
            ''
            "* **Retrieved: $StampDate**"
            "* Sources (fetched directly for this snapshot; all retrieved $StampDate):"
            "  * Supported AI models in GitHub Copilot — <$SupportedModelsUri>"
            "  * Models and pricing for GitHub Copilot — <$PricingUri>"
            "  * AI model comparison — <$ComparisonUri>"
            "  * About GitHub Copilot Fusion — <$FusionUri>"
            ''
            'This catalog is **host-neutral**: it lists what GitHub Copilot can offer across hosts, not what any one user or host currently has enabled. Filtering to what a given host actually advertises happens in the routing procedure that consumes this file (`model-routing.md`, delivered separately), never here.'
            ''
            '## Curation Criteria'
            ''
            'A row is added only when at least one of the official sources above names the model, and retired rows absent from both Supported AI models and Models and pricing are pruned automatically on refresh. A row is priced only when the pricing page states a rate (or, for Copilot Fusion effort tiers, a documented representative pool blend over the underlying billed models); a model named elsewhere but absent from pricing is marked `unpriced`, never assigned an invented number. Capability class, best-fit assignment classes, and fit scores are editorial curation over the sources'' stated category and task-fit text.'
            ''
            '## Maintainer and Review'
            ''
            'This file is CODEOWNERS-level content refreshed by `scripts/Sync-ModelCatalog.ps1` and reviewed via pull request before merge. Every change updates `consumption-rates-template.md` in lockstep so pricing and routing never drift.'
            ''
            '## Staleness and Re-verification'
            ''
            'The retrieval date above is this catalog''s freshness signal. **A catalog older than 90 days from its `Retrieved:` date, or a catalog that fails to parse, is stale**: the routing procedure that would otherwise rank against it must fall back to `consumption.md`''s static `fast`/`default`/`extended` tiers and log a warning, rather than blocking the run or guessing at a value this file no longer confirms.'
            ''
            ('`consumption-rates.md`''s `Observed-on:` date **must equal** this file''s `Retrieved:` date exactly, not merely "close" — both are `{0}` as of this snapshot. A future re-verification that updates one must update the other in the same change.' -f $StampDate)
            ''
            '## How This Catalog Is Consumed'
            ''
            'A model is **eligible** for automatic ranking only when it is in the intersection of what the dispatching host''s own tool/function-calling schema advertises (when it advertises one at all — e.g., this Copilot CLI host''s `task` tool exposes a fixed `model` enum) and what this catalog declares. The source order is:'
            ''
            '1. **Host-advertised enum ∩ catalog** — when the dispatching host advertises a `model` list (for example, this CLI host''s `task` tool), intersect it with this catalog. This intersection is the eligible set for automatic ranking.'
            '2. **Host config/picker** — when no enum is advertised (for example, VS Code''s `runSubagent`), the effective host-available set is whatever the operator''s picker/config allows; the routing procedure re-ranks reactively on rejection.'
            '3. **Declared catalog** — this file, used as the ranking universe once the eligible set from (1) or (2) is known, or as the static fallback when the catalog itself is stale or unparsable (see Staleness above).'
            ''
            'Ranked selection uses the comparable task-evidence policy in `model-scoring.md`; the *Catalog: Assignment Fit* table below is its explicit declared-fit fallback. Capability class decides which minimum Model Tier floors a model can serve, never a maximum spending or capability ceiling.'
            ''
            'Two labels describe a mismatch between what the host advertises and what this catalog declares, and neither is ever silently dropped:'
            ''
            '* **`unevaluated`** — advertised by the host but not present in this catalog. Excluded from automatic ranking; reachable only as an explicit `routing=manual` pick, never ranked as if this catalog had evaluated it.'
            '* **declared but unavailable** — present in this catalog but not advertised by the host. Never passed to a dispatch call regardless of how well it ranks, because the host has not offered it.'
            ''
            '## Capability Class Legend'
            ''
            '| Capability class | Definition (this catalog''s own curation) | Best-fit assignment classes |'
            '| --- | --- | --- |'
            '| `frontier-reasoning` | The vendor''s highest-capability tier ("Powerful" category on the official pricing page, or an explicit "deep reasoning" task-area recommendation); highest per-token cost | research, planning, review, council |'
            '| `balanced` | The vendor''s mid tier ("Versatile" category); general-purpose coding/writing/agentic fit at moderate cost | planning, implementation, review, intake |'
            '| `fast-lightweight` | The vendor''s lowest tier ("Lightweight" category, or an explicit "fast help with simple/repetitive tasks" recommendation); lowest per-token cost | intake, bookkeeping |'
            '| `code-specialized` | Marketed specifically for agentic/coding workflows over general reasoning (e.g., a "-Codex"/"-Code" name or an explicit "agentic software development" task area) | implementation |'
            ''
            '## Catalog: Capability and Availability'
            ''
            'Catalog IDs use the same lowercase, hyphenated form as this CLI host''s advertised `model` enum (e.g., `claude-opus-5.5`). Where GitHub''s documentation names a model or effort level not in the default static enum, the ID is **constructed** in that same style and flagged `(constructed)`; every other ID matches the advertised enum literally and is flagged `(advertised)`.'
        ))

    $capProviders = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @('OpenAI', 'Anthropic', 'Google', 'xAI', 'Microsoft', 'Moonshot AI', 'Copilot Fusion')) {
        if (@($catalogModels.Values | Where-Object Provider -eq $p).Count -gt 0) { $capProviders.Add($p) }
    }
    foreach ($m in $catalogModels.Values) {
        if ($m.Provider -notin $capProviders) { $capProviders.Add($m.Provider) }
    }

    foreach ($prov in $capProviders) {
        $lines.Add('')
        $lines.Add("### $prov")
        $lines.Add('')
        $lines.Add('| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |')
        $lines.Add('| --- | --- | --- | --- | --- | --- | --- | --- | --- |')
        foreach ($m in @($catalogModels.Values | Where-Object Provider -eq $prov | Sort-Object CatalogId)) {
            $lines.Add("| ``$($m.CatalogId)`` | $($m.IdSource) | $($m.DisplayName) | $($m.Status) | $($m.CapabilityClass) | $($m.ContextWindow) | $($m.ReasoningEffort) | $($m.BestFit) | $($m.Notes) |")
        }
    }

    $lines.AddRange([string[]]@(
            ''
            '## Catalog: Pricing (USD per 1M tokens)'
            ''
            ('Every single-model price below is transcribed verbatim from the "Models and pricing" page retrieved {0}; **`unpriced` never means `0`**. Copilot Fusion rows record representative blended solver rates for Cost Preflight and fallback estimation (live native billing charges each underlying model invoked). The `Rate-row alias` column names the exact `consumption-rates.md` "Model (as routed)" row this ID prices as.' -f $StampDate)
        ))

    $pricingGroups = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($grp in @(
            @{ Heading = 'OpenAI (has a documented long-context tier)'; Providers = @('OpenAI') }
            @{ Heading = 'Anthropic (Claude Haiku 5.5 has a documented long-context tier)'; Providers = @('Anthropic') }
            @{ Heading = 'Google (no long-context tier documented — flat rate)'; Providers = @('Google') }
            @{ Heading = 'xAI (has a documented long-context tier)'; Providers = @('xAI') }
            @{ Heading = 'Microsoft and Moonshot AI (no long-context tier documented — flat rate)'; Providers = @('Microsoft', 'Moonshot AI') }
            @{ Heading = 'Copilot Fusion (has a documented long-context tier)'; Providers = @('Copilot Fusion') }
        )) {
        $pricingGroups.Add([pscustomobject]$grp)
    }
    $groupedProviders = @($pricingGroups | ForEach-Object { $_.Providers })
    foreach ($prov in $capProviders) {
        if ($prov -notin $groupedProviders) {
            $extraHasLc = @($catalogModels.Values | Where-Object { $_.Provider -eq $prov -and $_.IsPriced -and $_.LcThreshold -ne 'none (flat rate)' }).Count -gt 0
            $suffix = if ($extraHasLc) { 'has a documented long-context tier' } else { 'no long-context tier documented — flat rate' }
            $pricingGroups.Add([pscustomobject]@{ Heading = "$prov ($suffix)"; Providers = @($prov) })
        }
    }

    foreach ($grp in $pricingGroups) {
        $provModels = @($catalogModels.Values | Where-Object { $_.Provider -in $grp.Providers -and $_.IsPriced } | Sort-Object Provider, CatalogId)
        if ($provModels.Count -eq 0) { continue }
        $hasLc = @($provModels | Where-Object { $_.LcThreshold -ne 'none (flat rate)' }).Count -gt 0
        $lines.Add('')
        $lines.Add("### $($grp.Heading)")
        $lines.Add('')
        if ($hasLc) {
            $lines.Add('| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output | LC input | LC cached | LC cache write | LC output |')
            $lines.Add('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |')
            foreach ($m in $provModels) {
                $lines.Add("| ``$($m.CatalogId)`` | $($m.RateAlias) | $($m.LcThreshold) | $($m.Input) | $($m.Cached) | $($m.CacheWrite) | $($m.Output) | $($m.LcInput) | $($m.LcCached) | $($m.LcCacheWrite) | $($m.LcOutput) |")
            }
        }
        else {
            $lines.Add('| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output |')
            $lines.Add('| --- | --- | --- | ---: | ---: | ---: | ---: |')
            foreach ($m in $provModels) {
                $lines.Add("| ``$($m.CatalogId)`` | $($m.RateAlias) | $($m.LcThreshold) | $($m.Input) | $($m.Cached) | $($m.CacheWrite) | $($m.Output) |")
            }
        }
    }

    $lines.AddRange([string[]]@(
            ''
            '## Catalog: Assignment Fit'
            ''
            'This table is Ranked''s operational fallback when the pinned independent evidence cannot support a comparison. Its coarse editorial scores are not granular measured capability, calibrated uncertainty, or a validated Economy quality threshold:'
            ''
            '* `3` — best in class: the source pages name this model for exactly this kind of work.'
            '* `2` — capable: a sound choice for the class, but not what the sources lead with.'
            '* `1` — usable: acceptable for the class, but weaker at it than its cost suggests.'
            '* `0` — unsuitable: never ranked for the class.'
            ''
            '`Family` and `Generation` resolve a tie between two generations of the same line (`claude-sonnet` `5.5` ranks ahead of `5` at equal fit and price). `Blended` is USD per 1M tokens of a representative agentic dispatch, derived from the pricing tables above as `0.20 × Input + 0.80 × Cached + 0.08 × Cache write + 0.02 × Output` (`n/a` counts as `0`). Rows are grouped by family, newest generation first; that order is the final tie-break.'
            ''
            '| Catalog ID | Family | Generation | research | planning | implementation | review | council | intake | bookkeeping | Blended |'
            '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |'
        ))

    $familyOrder = @(
        'gpt-sol', 'gpt-astra', 'gpt-terra', 'gpt-codex', 'gpt-nano', 'gpt-luna'
        'claude-opus', 'claude-opus-fast', 'claude-fable', 'claude-sonnet', 'claude-haiku'
        'gemini-argon', 'gemini-carbon', 'gemini-flash'
        'grok', 'kimi', 'mai-code-flash', 'copilot-fusion'
    )
    $orderedFit = @(
        $pricedEntries | Sort-Object `
        @{ Expression = { $idx = [array]::IndexOf($familyOrder, $_.Family); if ($idx -ge 0) { $idx } else { 999 } } }, `
        @{ Expression = { $_.Family } }, `
        @{ Expression = { ConvertTo-VersionSortableLocal $_.Generation }; Descending = $true }, `
        @{ Expression = { $_.CatalogId } }
    )
    foreach ($m in $orderedFit) {
        $f = $m.FitScores
        $lines.Add("| ``$($m.CatalogId)`` | $($m.Family) | $($m.Generation) | $($f['research']) | $($f['planning']) | $($f['implementation']) | $($f['review']) | $($f['council']) | $($f['intake']) | $($f['bookkeeping']) | $($m.Blended) |")
    }

    $lines.AddRange([string[]]@(
            ''
            '## Advertised but Unevaluated'
            ''
            'This host''s `task` dispatch tool advertises `model` values that this snapshot''s official sources do not document at all. Each is `unevaluated`: excluded from automatic ranking, priced `unpriced` (never `0`), and reachable only as an explicit `routing=manual` pick.'
            ''
            '| Advertised ID | Why unevaluated | Price |'
            '| --- | --- | --- |'
        ))
    foreach ($uid in $unevaluatedIds) {
        $why = if ($uid -eq 'gpt-5.6-sol-fast') {
            'No "GPT-5.6 Sol (fast mode)" or equivalent variant appears in "Supported AI models," "Models and pricing," or "AI model comparison" at retrieval.'
        }
        else {
            'Advertised in the host dispatch enum but absent from the official Copilot model documentation at retrieval.'
        }
        $lines.Add("| ``$uid`` | $why | unpriced |")
    }

    $notAdvertised = @($catalogModels.Values | Where-Object { -not $_.IsAdvertised } | Sort-Object CatalogId)
    $lines.AddRange([string[]]@(
            ''
            '## Documented but Not Advertised'
            ''
            'These models are named by the official sources but are not in the default static `task.model` enum at retrieval. Host-availability filtering happens in the routing procedure, never by deleting a documented active row here.'
            ''
            '| Catalog ID | Display name | Why not advertised (as observed, not asserted) |'
            '| --- | --- | --- |'
        ))
    foreach ($m in $notAdvertised) {
        $why = if ($m.CatalogId -match '^claude-fable-') { 'Enterprise-gated ZDR/EFS model; requires enterprise enablement' }
        elseif ($m.CatalogId -eq 'fusion-standard') { 'Copilot Fusion Standard session policy (`--model fusion --fusion-tier standard`); not a separate `task.model` enum entry' }
        elseif (-not $m.IsSupported) { 'Absent from "Supported AI models" (see Contradictions); retained from billing table' }
        else { 'Documented and priced in official Copilot docs; not in default `task.model` enum at retrieval' }
        $lines.Add("| ``$($m.CatalogId)`` | $($m.DisplayName) | $why |")
    }

    $lines.AddRange([string[]]@(
            ''
            '## Named Only in the Comparison Guide (Degraded Confidence)'
            ''
            '| Catalog ID | Display name | Why degraded | Price |'
            '| --- | --- | --- | --- |'
        ))
    foreach ($d in $degradedModels) {
        $lines.Add("| ``$($d.CatalogId)`` | $($d.DisplayName) | $($d.Reason) | unpriced |")
    }

    $lines.Add('')
    $lines.Add('## Contradictions and Notes Observed at Retrieval')
    $lines.Add('')
    foreach ($c in $contradictions) {
        $lines.Add("* $c")
    }
    $lines.Add('* **Copilot Fusion effort levels (`fusion-standard`, `hydrafusion`, `hydrafusion-max`).** Copilot Fusion dynamically selects models and execution patterns (`Single`, `Cascade`, `Critique`) across three user-selectable effort levels (`Standard`, `High`, `Max`) and bills each underlying model at its standard rate. The catalog records all three effort levels distinctly instead of collapsing `hydrafusion` (High) into `hydrafusion-max` (Max).')
    if ($retiredFromDocs.Count -gt 0) {
        $recentRetired = @(
            $retiredFromDocs.Values |
                Select-Object -First 10 |
                ForEach-Object { "$($_.Name) ($($_.Date))" }
        ) -join ', '
        $lines.Add("* **Retired models pruned from active selection.** Models listed in GitHub's retirement history and absent from current supported/pricing tables — including $recentRetired — are excluded from active catalog ranking and benchmark coverage gates.")
    }

    $lines.AddRange([string[]]@(
            ''
            '## Squad Assignment Classes Referenced Above'
            ''
            '`research`, `planning`, `implementation`, `review`, `council`, `intake`, `bookkeeping` — the seven fixed assignment classes this catalog''s "best-fit assignment classes" column draws from, per `model-routing.md`. Consequence floors live in `team.md`''s Model Tier column and are independent of this catalog.'
            ''
        ))

    return ($lines -join "`n")
}

function Format-RatesTemplateMarkdownLocal {
    param([string]$StampDate)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]@(
            '---'
            'name: squad-consumption-rates-template'
            'description: "Cold seed template for consumption-rates.md: per-model token rates, the tier-fallback table, the dispatch-size estimator, and the calibration block."'
            'license: MIT'
            'metadata:'
            '  authors: "Peter-N91/hve-squad"'
            '  spec_version: "1.0"'
            "  last_updated: `"$StampDate`""
            '---'
            ''
            '# Squad Consumption Rates Template'
            ''
            'This is the literal seed content for a squad root''s `consumption-rates.md` — the Scribe copies the fenced block below verbatim at Init and at every sub-squad seeding or federation promotion, and reseeds it (Step 7.1) whenever the existing file fails its shape check: it must carry a per-model rate table with `Input`, `Cached`, `Cache write`, and `Output` columns, a tier-fallback table, a dispatch-size estimator, and a calibration block. Preserve the calibration block across a reseed rather than resetting it to the template''s placeholder values.'
            ''
            '**This file is cold.** It is read only on initialization and at a Step 7.1 reseed — never for an ordinary decision or history dispatch. `consumption.md` stays hot (read on every history dispatch) and carries the derivation math, the orchestration-overhead and cost-formula guidance, and Cost Preflight, none of which are part of what gets copied to `consumption-rates.md`.'
            ''
            '````markdown'
            '---'
            'description: "Per-model token rates, dispatch-size estimator, and calibration factor for squad consumption estimates"'
            '---'
            ''
            '# Consumption Rates (verify against the current GitHub Copilot "Models and pricing" docs)'
            ''
            '* Billing model: usage-based billing (UBB), token-metered, effective 2026-06-01.'
            "* Observed-on: $StampDate. Source: <$PricingUri>"
            '* Credit conversion: 1 AI credit = $0.01 USD (fixed).'
            '* All rates are USD per 1M tokens. Anthropic and GPT-5.6+/GPT-6+ models bill a separate cache-write rate on top of cached input; models without one leave the column at 0.'
            "* ``Observed-on:`` above must equal ``model-catalog.md``'s ``Retrieved:`` date exactly, not merely `"close`" — both are ``$StampDate`` as of this snapshot; a future re-verification that updates one must update the other in the same change."
            ''
            '## Per-model token rates in USD per 1M tokens (volatile, verify before commit)'
            ''
            '`Model ID` is the exact Copilot dispatch id and the only value a `team.md` `Model` cell may hold under `routing=ranked`, `routing=economy`, or `routing=manual`; `Model (as routed)` is the rate key and VS Code display name. `—` marks a retired row. `LC Threshold` and `LC *` record documented long-context thresholds and higher rates; every other row uses `none (flat rate)`, never a blank for "unknown." `Tier` is this table''s cost bucket, independent of `model-catalog.md`''s capability class.'
            ''
            '| Model (as routed) | Model ID | Tier | Input | Cached | Cache write | Output | LC Threshold | LC Input | LC Cached | LC Cache write | LC Output | Notes |'
            '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'
            '| Gemini 3.1 Pro (retired) | — | default | 2.00 | 0.20 | 0 | 12.00 | not currently listed | n/a | n/a | n/a | n/a | Retired; kept for backward compatibility |'
        ))

    foreach ($m in ($pricedEntries | Sort-Object @{ Expression = { $_.IsFusion } }, Provider, CatalogId)) {
        $cw = if ($m.CacheWrite -eq 'n/a') { '0' } else { $m.CacheWrite }
        $thresh = ConvertTo-RatesTemplateThresholdLocal -CatalogThreshold $m.LcThreshold
        $lines.Add("| $($m.RateAlias) | ``$($m.CatalogId)`` | $($m.RateTier) | $($m.Input) | $($m.Cached) | $cw | $($m.Output) | $thresh | $($m.LcInput) | $($m.LcCached) | $($m.LcCacheWrite) | $($m.LcOutput) | $($m.RateShortNote) |")
    }
    $lines.Add('| (additional) | | | | | | | | | | | | update when GitHub changes |')

    $lines.AddRange([string[]]@(
            ''
            '## Tier fallback rates (used only when `basis: tier-default`)'
            ''
            'A tier is a routing preference, not a price. When the actual model is unknown, price the tier at its **most expensive member** rather than a blend: the observed failure mode of this ledger is undercounting, so the fallback is deliberately conservative-high and every row it produces is flagged `basis: tier-default`.'
            ''
            'The `Priced as` column below names a model for **pricing only**. Never write it into a consumption block''s `model` field — that field records what actually ran and is resolved per *Model Attribution* in `.github/instructions/squad/squad-state.instructions.md`, or left as the literal `unknown`. Copying a `Priced as` name into `model` is exactly the fabrication that makes a ledger report spend against a model the operator never chose.'
            ''
            '| Tier | Priced as | Input | Cached | Cache write | Output |'
            '| --- | --- | --- | --- | --- | --- |'
            '| fast | Claude Haiku 4.5 | 1.00 | 0.10 | 1.25 | 5.00 |'
            '| default | Claude Sonnet 4.6 | 3.00 | 0.30 | 3.75 | 15.00 |'
            '| extended | Claude Opus 5 | 5.00 | 0.50 | 6.25 | 25.00 |'
            ''
            '## Dispatch-size estimator'
            ''
            'A dispatch is **not one model call**. A dispatched subagent runs an internal tool loop, and every internal turn resends the accumulated context. Input therefore scales with `internal_turns × average_context`, not with a single prompt-and-reply pair. Pricing a dispatch as one call is what makes a ledger read an order of magnitude below the bill.'
            ''
            '```text'
            'tokens(bytes)      = bytes / 4'
            'base_context       = agent prompt + auto-applied instructions + loaded skill content'
            'average_context    = base_context + growth_per_turn × (internal_turns - 1) / 2'
            'gross_input        = internal_turns × average_context'
            '```'
            ''
            'Split `gross_input` across the billed rates. Turn 1 is fully uncached; on turns 2..n the carried-forward prefix is a cached read and only the new tool result is fresh input:'
            ''
            '```text'
            'cached_tokens      = gross_input × 0.80'
            'input_tokens       = gross_input × 0.20'
            'cache_write_tokens = base_context + growth_per_turn × (internal_turns - 1)   (models with Cache write > 0; 0 otherwise)'
            'output_tokens      = internal_turns × output_per_turn'
            '```'
            ''
            'For Copilot Fusion, multiply `gross_input` and `cache_write_tokens` by `0.35` on `hydrafusion-max` (Max), `0.55` on `hydrafusion` (High), and `1.0` on `fusion-standard` (Standard).'
            ''
            'Estimate `internal_turns` and `base_context` from what the dispatch actually reported. These class rows are **floors, not fallbacks** — start here and raise, never start below:'
            ''
            '| Dispatch class | Internal turns | Base context | Growth/turn | Output/turn |'
            '| --- | --- | --- | --- | --- |'
            '| Lookup / single-file read | 3 | 20,000 | 3,000 | 800 |'
            '| Research / file survey | 12 | 40,000 | 4,000 | 1,250 |'
            '| Plan / synthesis | 15 | 60,000 | 4,000 | 2,000 |'
            '| Implement / edit loop | 35 | 60,000 | 6,000 | 2,000 |'
            '| Review / verification | 18 | 50,000 | 4,000 | 1,500 |'
            '| Council member opinion | 10 | 50,000 | 4,000 | 1,500 |'
            '| Scribe state write | 4 | 15,000 | 3,000 | 800 |'
            ''
            'Observable proxies that raise a floor whenever available: the number of files the agent reported reading and their byte size, the byte size of artifacts it wrote, the count of tool calls it reported, and the length of the findings it returned.'
            ''
            '**Validity check.** After estimating, confirm `gross_input / internal_turns >= base_context` for the class. A derived average context below the floor means the dispatch was sized from the summary the coordinator handed over rather than from the dispatch''s own context. That summary is a report *about* the dispatch, not the context the dispatch ran on — an agent''s prompt plus its auto-applied instructions already exceeds most floors before it reads a single file. When the check fails, raise the numbers and recompute rather than recording the smaller figure.'
            ''
            '## Calibration'
            ''
            '```yaml'
            'calibration_factor: 1.00'
            'last_reconciled: never'
            'observations: 0'
            'estimator_revision: 2'
            'calibration_basis: "<observed-on>|2"'
            '```'
            ''
            'The factor is the running mean of legacy `observed_credits / estimated_credits` across reconciled runs, clamped to the range 0.25-10.0. It applies only to fallback estimates and future reservations; exact-native completed-work rows are never multiplied by it. To reconcile fallback behavior: read the per-user aggregate `ai_credits_used` before and after a run, divide the delta by that run''s estimated credits, fold the ratio into the mean, and rewrite this block. Until `observations` is at least 1 the factor stays 1.00 and fallback output carries an "uncalibrated" note.'
            ''
            '`calibration_basis` binds those observations to the rate table''s `Observed-on` value and `estimator_revision`, joined with `|`. A calibration is eligible for Cost Preflight only when `observations` is positive, `last_reconciled` is not `never`, and the stored basis exactly matches the current rate and estimator basis. When a rate-table reseed or estimator revision changes that basis, reset `calibration_factor` to `1.00`, `last_reconciled` to `never`, and `observations` to `0` rather than applying an old factor to a new calculation.'
            '````'
            ''
        ))

    return ($lines -join "`n")
}

$candidateCatalog = Format-CatalogMarkdownLocal -StampDate $retrievedDate
$candidateRates = Format-RatesTemplateMarkdownLocal -StampDate $retrievedDate

$ratesBytes = [System.Text.Encoding]::UTF8.GetByteCount($candidateRates)
if ($ratesBytes -gt $MaxRatesTemplateBytes) {
    throw "Generated consumption-rates-template.md is $ratesBytes LF UTF-8 bytes, exceeding MaxRatesTemplateBytes ($MaxRatesTemplateBytes)."
}

$newDigest = Get-SemanticCatalogDigestLocal -CatalogText $candidateCatalog -RatesText $candidateRates
$existingCatalogText = if (Test-Path -LiteralPath $CatalogOutputPath -PathType Leaf) { (Get-Content -LiteralPath $CatalogOutputPath -Raw) -replace "`r`n", "`n" } else { '' }
$existingRatesText = if (Test-Path -LiteralPath $RatesOutputPath -PathType Leaf) { (Get-Content -LiteralPath $RatesOutputPath -Raw) -replace "`r`n", "`n" } else { '' }
$oldDigest = if ($existingCatalogText -and $existingRatesText) {
    Get-SemanticCatalogDigestLocal -CatalogText $existingCatalogText -RatesText $existingRatesText
}
else { '' }

$ageDays = if ($existingDate) { ($AsOf.Date - $existingDate.Date).TotalDays } else { 999 }
$needsUpdate = $Force -or ($newDigest -cne $oldDigest) -or ($ageDays -ge $RefreshThresholdDays)
$effectiveDate = if ($needsUpdate -or -not $existingDate) { $retrievedDate } else { $existingDate.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) }

if ($DryRun) {
    Write-Host "[DryRun] Catalog models=$($catalogModels.Count), added=$($addedModels.Count), retired=$($retiredModels.Count), ratesBytes=$ratesBytes, needsUpdate=$needsUpdate."
}
elseif ($needsUpdate -and $PSCmdlet.ShouldProcess($CatalogOutputPath, 'Update model-catalog.md and consumption-rates-template.md')) {
    [System.IO.File]::WriteAllText($CatalogOutputPath, $candidateCatalog, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($RatesOutputPath, $candidateRates, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Updated model-catalog.md and consumption-rates-template.md ($($catalogModels.Count) models; $ratesBytes bytes)."
}

if ($GitHubOutput -and $env:GITHUB_OUTPUT) {
    @(
        "updated=$($needsUpdate.ToString().ToLowerInvariant())"
        "retrieved=$effectiveDate"
        "digest=$newDigest"
        "models_count=$($catalogModels.Count)"
        "added_models=$($addedModels -join ',')"
        "retired_models=$($retiredModels -join ',')"
    ) | Add-Content -LiteralPath $env:GITHUB_OUTPUT
}

[pscustomobject]@{
    Updated             = [bool]$needsUpdate
    Retrieved           = $effectiveDate
    Digest              = $newDigest
    ModelsCount         = $catalogModels.Count
    AddedModels         = $addedModels
    RetiredModels       = $retiredModels
    RatesTemplateBytes  = $ratesBytes
    CatalogOutputPath   = $CatalogOutputPath
    RatesOutputPath     = $RatesOutputPath
}
