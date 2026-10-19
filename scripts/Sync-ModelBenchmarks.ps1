#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Builds or refreshes the pinned benchmark knowledge base
    (`squad-src/.github/skills/squad/references/model-benchmarks.md`) from
    independent, versioned upstream benchmark datasets.
.DESCRIPTION
    Fetches the daily-updated Epoch AI Benchmarking Hub archive
    (`https://epoch.ai/data/benchmark_data.zip`, CC BY 4.0) — or reads a local
    archive/directory supplied via -ArchivePath for offline testing — and
    optionally enriches with Artificial Analysis Data API scores when
    -ArtificialAnalysisApiKey (or $env:ARTIFICIAL_ANALYSIS_API_KEY) or
    -ArtificialAnalysisJsonPath is supplied.

    The script extracts task-specific benchmark evaluations across coding,
    agentic execution, mathematics, scientific reasoning, and long-document
    synthesis for the models declared in `model-catalog.md`, tags every score
    with its source ID, source version, retrieval date, and provenance
    (`independent` or `self-reported`), computes the independent composite and
    evidence-derived assignment-class fit table, and writes
    `squad-src/.github/skills/squad/references/model-benchmarks.md`.

    To avoid daily commit churn when upstream scores have not changed, the
    script computes a SHA-256 content digest over normalized source metadata,
    scores, and assignment mappings (excluding the snapshot `Retrieved:` date
    stamp and the date-relative materialized fit view). Runtime routing
    recomputes row freshness from the committed scores, so a score merely
    crossing the 90-day boundary does not create a noisy daily snapshot PR.
    When the semantic digest matches the existing file on disk and the existing
    `Retrieved:` date is younger than -RefreshThresholdDays (default 60 days,
    well below the 90-day staleness cliff), the script reports no update needed
    unless -Force is set.

    Runtime squad dispatches NEVER call this script or fetch live web pages;
    `Resolve-SquadModelRoute.ps1` reads the committed `model-benchmarks.md`
    offline.
.PARAMETER OutputPath
    Destination path for the generated `model-benchmarks.md` knowledge base.
.PARAMETER CatalogPath
    Path to `model-catalog.md` defining the catalog model IDs and declared
    fallback fit scores.
.PARAMETER ArchivePath
    Optional local path to an existing `benchmark_data.zip` file or extracted
    directory. When omitted, downloads -ArchiveUri to a temporary folder.
.PARAMETER ArchiveUri
    Upstream URL for the Epoch AI Benchmarking Hub ZIP archive (CC BY 4.0).
.PARAMETER ArtificialAnalysisJsonPath
    Optional local path to a JSON response from the Artificial Analysis Data API.
.PARAMETER ArtificialAnalysisApiKey
    Optional API key for `https://artificialanalysis.ai/api/v2/language/models/free`.
    Defaults to `$env:ARTIFICIAL_ANALYSIS_API_KEY`.
.PARAMETER EpochVersion
    Version identifier for the Epoch AI snapshot. Defaults to a deterministic
    semantic fingerprint of unique normalized archive records, so redundant
    identical records and retrieval-only dates do not churn the snapshot digest.
.PARAMETER ArtificialAnalysisVersion
    Version identifier for the Artificial Analysis methodology. Defaults to `v4.3.2`.
.PARAMETER AsOf
    Retrieval date stamped into the snapshot (`yyyy-MM-dd`). Defaults to UTC today.
.PARAMETER RefreshThresholdDays
    Maximum age in days before a date-only refresh is written even if the
    content digest has not changed. Defaults to 60 (30 days before the 90-day
    staleness threshold).
.PARAMETER AllowCoverageReduction
    Explicitly accepts removing independent model/evaluation evidence coverage
    that exists in the current snapshot. By default, any such removal is treated
    as an ambiguous upstream truncation or mapping outage and the last-good
    snapshot is kept.
.PARAMETER Force
    Write the snapshot even when the content digest is unchanged and the
    existing file is younger than -RefreshThresholdDays.
.PARAMETER DryRun
    Compute the snapshot and report whether an update is needed without writing
    to -OutputPath.
.PARAMETER GitHubOutput
    Append `updated`, `digest`, `retrieved`, `models_covered`, and `scores_count`
    key-value lines to `$env:GITHUB_OUTPUT`.
.EXAMPLE
    ./scripts/Sync-ModelBenchmarks.ps1
.EXAMPLE
    ./scripts/Sync-ModelBenchmarks.ps1 -Force
.EXAMPLE
    ./scripts/Sync-ModelBenchmarks.ps1 -ArchivePath ./tests/fixtures/benchmarks -DryRun
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$CatalogPath,

    [Parameter(Mandatory = $false)]
    [string]$ArchivePath,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ArchiveUri = 'https://epoch.ai/data/benchmark_data.zip',

    [Parameter(Mandatory = $false)]
    [string]$ArtificialAnalysisJsonPath,

    [Parameter(Mandatory = $false)]
    [string]$ArtificialAnalysisApiKey = $env:ARTIFICIAL_ANALYSIS_API_KEY,

    [Parameter(Mandatory = $false)]
    [string]$EpochVersion,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtificialAnalysisVersion = 'v4.3.2',

    [Parameter(Mandatory = $false)]
    [datetime]$AsOf = [datetime]::UtcNow,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 89)]
    [int]$RefreshThresholdDays = 60,

    [Parameter(Mandatory = $false)]
    [switch]$AllowCoverageReduction,

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
if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot 'squad-src/.github/skills/squad/references/model-benchmarks.md'
}
if (-not $CatalogPath) {
    $CatalogPath = Join-Path $repoRoot 'squad-src/.github/skills/squad/references/model-catalog.md'
}

$retrievedDate = $AsOf.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)

$classes = @('research', 'planning', 'implementation', 'review', 'council', 'intake', 'bookkeeping')

$catalogModelSpecs = [ordered]@{
    'gpt-5.6-sol'         = @{ Display = 'GPT-5.6 Sol'; VersionRegex = '^gpt-5\.6-sol(_|$)' }
    'gpt-6.1-sol'         = @{ Display = 'GPT-6.1 Sol'; VersionRegex = '^gpt-6\.1-sol(_|$)' }
    'gpt-6-sol'           = @{ Display = 'GPT-6 Sol'; VersionRegex = '^gpt-6-sol(_|$)' }
    'gpt-6-astra'         = @{ Display = 'GPT-6 Astra'; VersionRegex = '^gpt-6-astra(_|$)' }
    'gpt-5.5'             = @{ Display = 'GPT-5.5'; VersionRegex = '^gpt-5\.5(_|-pre-release|$)' }
    'gpt-5.4'             = @{ Display = 'GPT-5.4'; VersionRegex = '^gpt-5\.4(-2026-03-05)?(_|$)' }
    'gpt-5.6-terra'       = @{ Display = 'GPT-5.6 Terra'; VersionRegex = '^gpt-5\.6-terra(_|$)' }
    'gpt-5.3-codex'       = @{ Display = 'GPT-5.3 Codex'; VersionRegex = '^gpt-5\.3-codex(_|$)' }
    'gpt-5.4-mini'        = @{ Display = 'GPT-5.4 Mini'; VersionRegex = '^gpt-5\.4-mini(-2026-03-17)?(_|$)' }
    'gpt-5-mini'          = @{ Display = 'GPT-5 mini'; VersionRegex = '^gpt-5-mini(-2025-08-07)?(_|$)' }
    'gpt-5.4-nano'        = @{ Display = 'GPT-5.4 Nano'; VersionRegex = '^gpt-5\.4-nano(-2026-03-17)?(_|$)' }
    'gpt-6-luna'          = @{ Display = 'GPT-6 Luna'; VersionRegex = '^gpt-6-luna(_|$)' }
    'gpt-5.6-luna'        = @{ Display = 'GPT-5.6 Luna'; VersionRegex = '^gpt-5\.6-luna(_|$)' }
    'claude-opus-5.5'     = @{ Display = 'Claude Opus 5.5'; VersionRegex = '^claude-opus-5-5(_|$)' }
    'claude-opus-5'       = @{ Display = 'Claude Opus 5'; VersionRegex = '^claude-opus-5(_|$)' }
    'claude-opus-4.8'     = @{ Display = 'Claude Opus 4.8'; VersionRegex = '^claude-opus-4-8(_|$)' }
    'claude-opus-4.7'     = @{ Display = 'Claude Opus 4.7'; VersionRegex = '^claude-opus-4-7(_|$)' }
    'claude-opus-4.8-fast' = @{ Display = 'Claude Opus 4.8'; VersionRegex = '^claude-opus-4-8(_|$)'; AliasOf = 'claude-opus-4.8' }
    'claude-fable-5.1'    = @{ Display = 'Claude Fable 5.1'; VersionRegex = '^claude-fable-5-1(_|$)' }
    'claude-fable-5'      = @{ Display = 'Claude Fable 5'; VersionRegex = '^claude-fable-5(_|$)' }
    'claude-sonnet-5.5'   = @{ Display = 'Claude Sonnet 5.5'; VersionRegex = '^claude-sonnet-5-5(_|$)' }
    'claude-sonnet-5'     = @{ Display = 'Claude Sonnet 5'; VersionRegex = '^claude-sonnet-5(_|$)' }
    'claude-sonnet-4.6'   = @{ Display = 'Claude Sonnet 4.6'; VersionRegex = '^claude-sonnet-4-6(_|$)' }
    'claude-sonnet-4'     = @{ Display = 'Claude Sonnet 4'; VersionRegex = '^claude-sonnet-4-20250514(_|$)' }
    'claude-haiku-5.5'    = @{ Display = 'Claude Haiku 5.5'; VersionRegex = '^claude-haiku-5-5(_|$)' }
    'claude-haiku-4.5'    = @{ Display = 'Claude Haiku 4.5'; VersionRegex = '^claude-haiku-4-5(-20251001)?(_|$)' }
    'gemini-3.8-flash'    = @{ Display = 'Gemini 3.8 Flash'; VersionRegex = '^gemini-3\.8-flash(_|$)' }
    'gemini-3.7-flash'    = @{ Display = 'Gemini 3.7 Flash'; VersionRegex = '^gemini-3\.7-flash(_|$)' }
    'gemini-3.6-flash'    = @{ Display = 'Gemini 3.6 Flash'; VersionRegex = '^gemini-3\.6-flash(_|$)' }
    'gemini-3.5-flash'    = @{ Display = 'Gemini 3.5 Flash'; VersionRegex = '^gemini-3\.5-flash(_|$)' }
    'grok-4.7'            = @{ Display = 'Grok 4.7'; VersionRegex = '^grok-4\.7(_|$)' }
    'grok-4.6'            = @{ Display = 'Grok 4.6'; VersionRegex = '^grok-4\.6(_|$)' }
    'grok-4.5'            = @{ Display = 'Grok 4.5'; VersionRegex = '^grok-4\.5(_|$)' }
    'kimi-k3'             = @{ Display = 'Kimi K3'; VersionRegex = '^kimi-k3(_|$)' }
    'kimi-k2.7-code'      = @{ Display = 'Kimi K2.7 Code'; VersionRegex = '^kimi-k2\.7-code(_|$)' }
    'mai-code-1.1-flash'  = @{ Display = 'MAI-Code-1.1-Flash'; VersionRegex = '^mai-code-1\.1-flash(_|$)' }
    'hydrafusion-max'     = @{ Display = 'GPT-6.1 Sol'; VersionRegex = '^gpt-6\.1-sol(_|$)'; AliasOf = 'gpt-6.1-sol' }
}

function Get-CatalogFitMap {
    param([Parameter(Mandatory)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    $fitMap = @{}
    $inFit = $false
    $header = $null
    foreach ($line in ($raw -split '\r?\n')) {
        if ($line -match '^## Catalog: Assignment Fit\s*$') {
            $inFit = $true
            continue
        }
        if ($inFit -and $line -match '^## ') {
            break
        }
        if (-not $inFit -or $line -notmatch '^\s*\|') {
            continue
        }
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') {
            continue
        }
        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim().Trim('`').Trim() })
        if (-not $header) {
            $header = $cells
            continue
        }
        $row = @{}
        for ($i = 0; $i -lt $header.Count; $i++) {
            $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' }
        }
        if ($row['Catalog ID']) {
            $scores = @{}
            foreach ($c in $classes) {
                $scores[$c] = [int]$row[$c]
            }
            $fitMap[$row['Catalog ID']] = $scores
        }
    }
    return $fitMap
}

function Get-BestVersionRow {
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][string]$VersionPattern,
        [Parameter(Mandatory)][string]$ScoreColumn
    )

    if (-not $Rows) {
        return $null
    }

    $best = $null
    $bestSignature = $null
    $bestRow = $null
    foreach ($row in $Rows) {
        $ver = [string]$row.'Model version'
        if ($ver -notmatch $VersionPattern) {
            continue
        }
        $rawVal = [string]$row.$ScoreColumn
        if ($rawVal -notmatch '^-?\d+(\.\d+)?([eE][+-]?\d+)?$') {
            continue
        }
        $val = [double]$rawVal
        $signature = @(
            $row.PSObject.Properties |
                Sort-Object Name |
                ForEach-Object { "$($_.Name)=$(([string]$_.Value).Trim())" }
        ) -join '|'
        if ($null -eq $best -or $val -gt $best -or ($val -eq $best -and [string]::CompareOrdinal($signature, $bestSignature) -lt 0)) {
            $best = $val
            $bestSignature = $signature
            $bestRow = $row
        }
    }
    if ($null -eq $bestRow) {
        return $null
    }
    [pscustomobject]@{
        Score = $best
        Row   = $bestRow
    }
}

function ConvertTo-IsoDate {
    param(
        [AllowNull()][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][string]$Fallback
    )

    if (-not $Value) {
        return $Fallback
    }

    $parsed = [datetime]::MinValue
    foreach ($format in @('yyyy-MM-dd', 'MM/dd/yyyy', 'M/d/yyyy', 'dd/MM/yyyy', 'd/M/yyyy')) {
        if ([datetime]::TryParseExact($Value.Trim(), $format, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            return $parsed.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        }
    }
    if ([datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        return $parsed.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $Fallback
}

function ConvertTo-SourceSlug {
    param([AllowNull()][AllowEmptyString()][string]$Value)

    if (-not $Value) {
        return ''
    }
    $slug = $Value.ToLowerInvariant() -replace '^https?://', '' -replace '^www\.', ''
    $slug = $slug -replace '[^a-z0-9]+', '-'
    $slug.Trim('-')
}

function Get-SourceDetailLocal {
    param(
        [AllowNull()][AllowEmptyString()][string]$RawSource,
        [Parameter(Mandatory)][string]$DefaultId,
        [Parameter(Mandatory)][string]$DefaultName,
        [Parameter(Mandatory)][string]$DefaultVersion,
        [AllowNull()][AllowEmptyString()][string]$VersionHint,
        [AllowNull()][AllowEmptyString()][string]$RetrievedHint,
        [Parameter(Mandatory)][string]$SnapshotRetrieved
    )

    $source = if ($RawSource) { $RawSource.Trim() } else { '' }
    $id = $DefaultId
    $name = $DefaultName
    $url = ''
    $independentSources = @{
        'epoch-ai' = 'Epoch AI Benchmarking Hub'
        'artificial-analysis' = 'Artificial Analysis'
        'cognition-frontiercode' = 'Cognition FrontierCode'
        'terminal-bench' = 'Terminal-Bench'
        'surge-gdp-pdf' = 'Surge AI GDP.pdf'
        'deepswe-datacurve-ai' = 'deepswe.datacurve.ai'
        'evals-futuresearch-ai' = 'evals.futuresearch.ai'
        'frontierswe-com' = 'frontierswe.com'
        'osworld-v2-xlang-ai' = 'osworld-v2.xlang.ai'
        'vals-ai' = 'vals.ai'
    }
    $knownIndependent = -not $source -and $independentSources.ContainsKey($DefaultId)
    $publisherId = $null

    $uri = $null
    if ($source -and [uri]::TryCreate($source, [System.UriKind]::Absolute, [ref]$uri)) {
        $url = $uri.AbsoluteUri
        $sourceHost = $uri.Host.ToLowerInvariant() -replace '^www\.', ''
        $id = ConvertTo-SourceSlug -Value $sourceHost
        $name = $sourceHost
        if ($uri.Scheme -in @('http', 'https')) {
            $publisherId = switch -Regex ($sourceHost) {
                '(^|\.)epoch\.ai$' { 'epoch-ai' }
                '(^|\.)artificialanalysis\.ai$' { 'artificial-analysis' }
                '(^|\.)cognition\.com$' { 'cognition-frontiercode' }
                '(^|\.)tbench\.ai$' { 'terminal-bench' }
                '(^|\.)surgehq\.ai$' { 'surge-gdp-pdf' }
                '^deepswe\.datacurve\.ai$' { 'deepswe-datacurve-ai' }
                '^evals\.futuresearch\.ai$' { 'evals-futuresearch-ai' }
                '^frontierswe\.com$' { 'frontierswe-com' }
                '^osworld-v2\.xlang\.ai$' { 'osworld-v2-xlang-ai' }
                '^vals\.ai$' { 'vals-ai' }
            }
        }
    }
    elseif ($source) {
        $id = ConvertTo-SourceSlug -Value $source
        $name = $source
        $publisherId = switch -Regex ($source) {
            '(?i)^\s*epoch[- ]ai\s*$' {
                'epoch-ai'
            }
            '(?i)^\s*artificial analysis(?:\s+(?:scicode|critpt))?\s*$' {
                $url = 'https://artificialanalysis.ai'
                'artificial-analysis'
            }
            '(?i)^\s*terminal[- ]bench\s*$' {
                $url = 'https://www.tbench.ai'
                'terminal-bench'
            }
            '(?i)^\s*(?:cognition(?:\s+frontiercode)?|frontiercode)\s*$' {
                $url = 'https://cognition.com/frontiercode'
                'cognition-frontiercode'
            }
            '(?i)^\s*surge(?:\s+ai)?\s+gdp(?:\.pdf)?\s*$' {
                $url = 'https://surgehq.ai/leaderboards/gdp-pdf'
                'surge-gdp-pdf'
            }
        }
    }

    if ($publisherId) {
        $id = $publisherId
        $name = $independentSources[$publisherId]
        $knownIndependent = $true
    }
    elseif (-not $knownIndependent -and $independentSources.ContainsKey($id)) {
        $id = "unverified-$id"
    }

    if (-not $url) {
        $url = switch ($id) {
            'epoch-ai' { 'https://epoch.ai/benchmarks/use-this-data' }
            'artificial-analysis' { 'https://artificialanalysis.ai/methodology/intelligence-benchmarking' }
            'cognition-frontiercode' { 'https://cognition.com/frontiercode' }
            'terminal-bench' { 'https://www.tbench.ai' }
            'surge-gdp-pdf' { 'https://surgehq.ai/leaderboards/gdp-pdf' }
            default { '' }
        }
    }

    $provenance = if ($knownIndependent) { 'independent' } else { 'self-reported' }

    $version = switch ($id) {
        'epoch-ai' { $DefaultVersion }
        'artificial-analysis' { $DefaultVersion }
        default {
            if ($VersionHint) { ConvertTo-IsoDate -Value $VersionHint -Fallback $DefaultVersion } else { $DefaultVersion }
        }
    }
    $retrieved = ConvertTo-IsoDate -Value $RetrievedHint -Fallback $SnapshotRetrieved

    $license = switch ($id) {
        'epoch-ai' { 'CC-BY-4.0' }
        'artificial-analysis' { 'Attribution required (Free Data API ToS / CC-BY-4.0 via Epoch AI bundle)' }
        default { 'CC-BY-4.0 via Epoch AI bundle' }
    }
    $redistribution = if ($provenance -eq 'self-reported') { 'informational-only' } else { 'permitted-with-attribution' }
    $status = if ($provenance -eq 'self-reported') { 'self-reported-only' } else { 'active' }

    [pscustomobject][ordered]@{
        Id             = $id
        Name           = $name
        Version        = $version
        Retrieved      = $retrieved
        Provenance     = $provenance
        License        = $license
        Redistribution = $redistribution
        Status         = $status
        Url            = $url
    }
}

function ConvertTo-NormalizedScore {
    param([AllowNull()]$Value)

    if ($null -eq $Value -or [string]$Value -notmatch '^-?\d+(\.\d+)?([eE][+-]?\d+)?$') {
        return $null
    }
    $score = [double]$Value
    if ([math]::Abs($score) -gt 1.0 -and [math]::Abs($score) -le 100.0) {
        $score /= 100.0
    }
    [Math]::Round($score, 3)
}

function ConvertTo-EvidenceFit {
    param([Parameter(Mandatory)][double]$Average)

    if ($Average -ge 0.75) { return 3 }
    if ($Average -ge 0.50) { return 2 }
    if ($Average -ge 0.25) { return 1 }
    return 0
}

function Get-ModelLookupKey {
    param([AllowNull()][AllowEmptyString()][string]$Value)

    if (-not $Value) {
        return ''
    }
    ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
}

function Get-StringSha256 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Text -replace "`r`n", "`n"))
        $hash = $sha.ComputeHash($bytes)
        return -join ($hash | ForEach-Object { $_.ToString('x2') })
    }
    finally {
        $sha.Dispose()
    }
}

function Get-NormalizedDataSetRecord {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$DataSets)

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($dataSetName in @($DataSets.Keys | Sort-Object)) {
        foreach ($row in @($DataSets[$dataSetName])) {
            $fields = @(
                $row.PSObject.Properties |
                    Sort-Object Name |
                    ForEach-Object { "$($_.Name)=$(([string]$_.Value).Trim())" }
            )
            $lines.Add("$dataSetName|$($fields -join '|')")
        }
    }
    @($lines | Sort-Object -Unique -CaseSensitive)
}

function Get-UniqueProcessedEvaluationRow {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][string]$CatalogId,
        [Parameter(Mandatory)][string]$Evaluation
    )

    $candidates = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($row in $Rows) {
        $rawScore = [string]$row.performance
        if ($rawScore -notmatch '^-?\d+(\.\d+)?([eE][+-]?\d+)?$') {
            continue
        }
        $score = [double]$rawScore
        if ($score -lt 0.0 -or $score -gt 1.0) {
            throw "Benchmark row for '$CatalogId' / '$Evaluation' has out-of-range normalized score '$rawScore'; expected 0.0 through 1.0."
        }
        $signature = @(
            $score.ToString('0.###############', [System.Globalization.CultureInfo]::InvariantCulture)
            ([string]$row.benchmark_release_date).Trim()
            ([string]$row.model_version).Trim()
            ([string]$row.date).Trim()
            ([string]$row.source).Trim()
        ) -join '|'
        $candidates.Add([pscustomobject]@{
                Signature = $signature
                Row       = $row
            })
    }

    if ($candidates.Count -eq 0) {
        return $null
    }
    $signatures = @($candidates | ForEach-Object { $_.Signature } | Sort-Object -Unique)
    if ($signatures.Count -gt 1) {
        throw "Conflicting benchmark rows for '$CatalogId' / '$Evaluation'; refusing row-order-dependent selection."
    }
    @($candidates | Sort-Object Signature | Select-Object -First 1)[0].Row
}

function Get-IndependentSnapshotEvidenceKey {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $keys = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    $inScores = $false
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match '^## Benchmark Scores\s*$') {
            $inScores = $true
            continue
        }
        if ($inScores -and $line -match '^## ') {
            break
        }
        if ($inScores -and $line -match '^\|\s*`(?<id>[^`]+)`\s*\|\s*(?<evaluation>[^|]+?)\s*\|.*\|\s*`independent`\s*\|\s*$') {
            [void]$keys.Add("$($Matches['id'])`n$($Matches['evaluation'].Trim())")
        }
    }
    @($keys)
}

$catalogFit = Get-CatalogFitMap -Path $CatalogPath

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "squad-benchmarks-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    $extractRoot = $null
    if ($ArchivePath) {
        $resolvedArchive = (Resolve-Path -LiteralPath $ArchivePath).Path
        if (Test-Path -LiteralPath $resolvedArchive -PathType Container) {
            $extractRoot = $resolvedArchive
        }
        else {
            $extractRoot = Join-Path $tempDir 'extracted'
            Expand-Archive -LiteralPath $resolvedArchive -DestinationPath $extractRoot -Force
        }
    }
    else {
        $zipFile = Join-Path $tempDir 'benchmark_data.zip'
        Write-Host "Downloading Epoch AI benchmark archive from $ArchiveUri..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $ArchiveUri -OutFile $zipFile -UseBasicParsing
        $extractRoot = Join-Path $tempDir 'extracted'
        Expand-Archive -LiteralPath $zipFile -DestinationPath $extractRoot -Force
    }

    $procPath = Join-Path $extractRoot 'epoch_capabilities_index/processed_data_for_eci.csv'
    $eciPath = Join-Path $extractRoot 'epoch_capabilities_index/eci_scores.csv'
    if (-not (Test-Path -LiteralPath $procPath -PathType Leaf)) {
        throw "Expected Epoch AI file not found at '$procPath'."
    }

    $procLines = @(Get-Content -LiteralPath $procPath)
    $procLines[0] = 'model_id,benchmark_id,performance,benchmark,benchmark_release_date,model_lower,model_version,model_display,date,source'
    $procRows = @($procLines | ConvertFrom-Csv)

    $eciRows = if (Test-Path -LiteralPath $eciPath -PathType Leaf) {
        @(Import-Csv -LiteralPath $eciPath)
    }
    else {
        @()
    }

    $scicodePath = Join-Path $extractRoot 'scicode_external.csv'
    $scicodeRows = if (Test-Path -LiteralPath $scicodePath -PathType Leaf) {
        @(Import-Csv -LiteralPath $scicodePath)
    }
    else {
        @()
    }

    $critptPath = Join-Path $extractRoot 'critpt_external.csv'
    $critptRows = if (Test-Path -LiteralPath $critptPath -PathType Leaf) {
        @(Import-Csv -LiteralPath $critptPath)
    }
    else {
        @()
    }

    $gdpPdfPath = Join-Path $extractRoot 'gdp_pdf_external.csv'
    $gdpPdfRows = if (Test-Path -LiteralPath $gdpPdfPath -PathType Leaf) {
        @(Import-Csv -LiteralPath $gdpPdfPath)
    }
    else {
        @()
    }

    if (-not $EpochVersion) {
        $semanticLines = Get-NormalizedDataSetRecord -DataSets ([ordered]@{
                processed = $procRows
                eci       = $eciRows
                scicode   = $scicodeRows
                critpt    = $critptRows
                gdpPdf    = $gdpPdfRows
            })
        $semanticHash = Get-StringSha256 -Text ($semanticLines -join "`n")
        $EpochVersion = "archive-$($semanticHash.Substring(0, 16))"
    }

    $aaApiModels = @{}
    function Add-ArtificialAnalysisModel {
        param([Parameter(Mandatory)]$Entry)

        foreach ($propertyName in @('slug', 'id', 'name')) {
            $property = $Entry.PSObject.Properties[$propertyName]
            if (-not $property) {
                continue
            }
            $candidate = [string]$property.Value
            $key = Get-ModelLookupKey -Value ([string]$candidate)
            if ($key) {
                $aaApiModels[$key] = $Entry
            }
        }
    }

    if ($ArtificialAnalysisJsonPath -and (Test-Path -LiteralPath $ArtificialAnalysisJsonPath -PathType Leaf)) {
        $aaPayload = Get-Content -LiteralPath $ArtificialAnalysisJsonPath -Raw | ConvertFrom-Json
        if ($aaPayload.PSObject.Properties['intelligence_index_version'] -and $aaPayload.intelligence_index_version) {
            $ArtificialAnalysisVersion = "v$($aaPayload.intelligence_index_version)"
        }
        foreach ($entry in @($aaPayload.data)) {
            Add-ArtificialAnalysisModel -Entry $entry
        }
    }
    elseif ($ArtificialAnalysisApiKey) {
        try {
            $aaPayload = Invoke-RestMethod -Uri 'https://artificialanalysis.ai/api/v2/language/models/free' -Headers @{ 'x-api-key' = $ArtificialAnalysisApiKey } -Method Get
            if ($aaPayload.PSObject.Properties['intelligence_index_version'] -and $aaPayload.intelligence_index_version) {
                $ArtificialAnalysisVersion = "v$($aaPayload.intelligence_index_version)"
            }
            foreach ($entry in @($aaPayload.data)) {
                Add-ArtificialAnalysisModel -Entry $entry
            }
        }
        catch {
            Write-Warning "Artificial Analysis API request failed ($($_.Exception.Message)); continuing with public evaluation datasets."
        }
    }

    # Evaluation catalog: maps ECI benchmark names to normalized evaluation metadata.
    # Source, version, date, and provenance are resolved from each source row rather
    # than inferred from the evaluation name.
    $procEvalSpecs = @(
        [ordered]@{ RawName = 'GPQA diamond'; EvalName = 'GPQA diamond'; Category = 'scientific-reasoning' }
        [ordered]@{ RawName = 'FrontierMath-Tiers-1-3-v2-Private'; EvalName = 'FrontierMath-Tiers-1-3-v2'; Category = 'math' }
        [ordered]@{ RawName = 'FrontierMath-Tier-4-v2-Private'; EvalName = 'FrontierMath-Tier-4-v2'; Category = 'math' }
        [ordered]@{ RawName = 'FrontierMath-2025-02-28-Private'; EvalName = 'FrontierMath-v1'; Category = 'math' }
        [ordered]@{ RawName = 'OTIS Mock AIME 2024-2025'; EvalName = 'OTIS Mock AIME'; Category = 'math' }
        [ordered]@{ RawName = 'ProofBench'; EvalName = 'ProofBench'; Category = 'math' }
        [ordered]@{ RawName = 'SWE-Bench verified'; EvalName = 'SWE-Bench verified'; Category = 'coding' }
        [ordered]@{ RawName = 'Terminal Bench'; EvalName = 'Terminal-Bench'; Category = 'coding' }
        [ordered]@{ RawName = 'FrontierCode'; EvalName = 'FrontierCode'; Category = 'coding' }
        [ordered]@{ RawName = 'DeepSWE'; EvalName = 'DeepSWE'; Category = 'coding' }
        [ordered]@{ RawName = 'FrontierSWE'; EvalName = 'FrontierSWE'; Category = 'agents' }
        [ordered]@{ RawName = 'APEX-Agents'; EvalName = 'APEX-Agents'; Category = 'agents' }
        [ordered]@{ RawName = 'OSWorld 2.0'; EvalName = 'OSWorld 2.0'; Category = 'agents' }
        [ordered]@{ RawName = 'HLE'; EvalName = 'HLE'; Category = 'scientific-reasoning' }
        [ordered]@{ RawName = 'SimpleQA Verified'; EvalName = 'SimpleQA Verified'; Category = 'general-long-doc' }
        [ordered]@{ RawName = 'DeepResearch Bench'; EvalName = 'DeepResearch Bench'; Category = 'general-long-doc' }
    )

    $aaEvaluationSpecs = @(
        [ordered]@{ Property = 'artificial_analysis_intelligence_index'; EvalName = 'Artificial Analysis Intelligence Index'; Category = 'general-long-doc' }
        [ordered]@{ Property = 'artificial_analysis_coding_index'; EvalName = 'Artificial Analysis Coding Index'; Category = 'coding' }
        [ordered]@{ Property = 'artificial_analysis_agentic_index'; EvalName = 'Artificial Analysis Agentic Index'; Category = 'agents' }
    )

    $scoreRows = [System.Collections.Generic.List[pscustomobject]]::new()
    $modelEvalLookup = @{}

    foreach ($catalogId in $catalogModelSpecs.Keys) {
        $spec = $catalogModelSpecs[$catalogId]
        if ($spec.Contains('AliasOf')) {
            continue
        }
        $display = $spec.Display
        $versionRegex = $spec.VersionRegex
        $modelEvalLookup[$catalogId] = [ordered]@{}

        $displayKey = Get-ModelLookupKey -Value $display
        $modelProcRows = @($procRows | Where-Object { (Get-ModelLookupKey -Value ([string]$_.model_display)) -eq $displayKey })
        foreach ($evalSpec in $procEvalSpecs) {
            if ($evalSpec.EvalName -eq 'FrontierMath-v1' -and $modelEvalLookup[$catalogId].Contains('FrontierMath-Tiers-1-3-v2')) {
                continue
            }
            $matchRows = @($modelProcRows | Where-Object { ([string]$_.benchmark).Trim() -eq $evalSpec.RawName })
            $matchRow = Get-UniqueProcessedEvaluationRow -Rows $matchRows -CatalogId $catalogId -Evaluation $evalSpec.EvalName
            if ($matchRow) {
                $scoreVal = [Math]::Round([double]$matchRow.performance, 3)
                $source = Get-SourceDetailLocal `
                    -RawSource ([string]$matchRow.source) `
                    -DefaultId 'epoch-ai' `
                    -DefaultName 'Epoch AI Benchmarking Hub' `
                    -DefaultVersion $EpochVersion `
                    -VersionHint ([string]$matchRow.benchmark_release_date) `
                    -RetrievedHint ([string]$matchRow.date) `
                    -SnapshotRetrieved $retrievedDate
                $entry = [pscustomobject][ordered]@{
                    CatalogId     = $catalogId
                    Evaluation    = $evalSpec.EvalName
                    Category      = $evalSpec.Category
                    Score         = $scoreVal.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
                    NumericScore  = $scoreVal
                    SourceId      = $source.Id
                    SourceName    = $source.Name
                    SourceVersion = $source.Version
                    SourceUrl     = $source.Url
                    Retrieved     = $source.Retrieved
                    Provenance    = $source.Provenance
                    License       = $source.License
                    Redistribution = $source.Redistribution
                    Status        = $source.Status
                }
                $scoreRows.Add($entry)
                $modelEvalLookup[$catalogId][$evalSpec.EvalName] = $entry
            }
        }

        # SciCode (Artificial Analysis Coding evaluation)
        $scicodeBest = Get-BestVersionRow -Rows $scicodeRows -VersionPattern $versionRegex -ScoreColumn 'Score'
        if ($null -ne $scicodeBest) {
            $scoreVal = [Math]::Round($scicodeBest.Score, 3)
            $source = Get-SourceDetailLocal `
                -RawSource ([string]$scicodeBest.Row.Source) `
                -DefaultId 'artificial-analysis' `
                -DefaultName 'Artificial Analysis' `
                -DefaultVersion $ArtificialAnalysisVersion `
                -VersionHint $ArtificialAnalysisVersion `
                -RetrievedHint $retrievedDate `
                -SnapshotRetrieved $retrievedDate
            $entry = [pscustomobject][ordered]@{
                CatalogId     = $catalogId
                Evaluation    = 'SciCode'
                Category      = 'coding'
                Score         = $scoreVal.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
                NumericScore  = $scoreVal
                SourceId      = $source.Id
                SourceName    = $source.Name
                SourceVersion = $source.Version
                SourceUrl     = $source.Url
                Retrieved     = $source.Retrieved
                Provenance    = $source.Provenance
                License       = $source.License
                Redistribution = $source.Redistribution
                Status        = $source.Status
            }
            $scoreRows.Add($entry)
            $modelEvalLookup[$catalogId]['SciCode'] = $entry
        }

        # CritPt (Artificial Analysis Scientific Reasoning evaluation)
        $critptBest = Get-BestVersionRow -Rows $critptRows -VersionPattern $versionRegex -ScoreColumn 'Accuracy'
        if ($null -ne $critptBest -and $critptBest.Score -gt 0) {
            $scoreVal = [Math]::Round($critptBest.Score, 3)
            $source = Get-SourceDetailLocal `
                -RawSource 'Artificial Analysis CritPt' `
                -DefaultId 'artificial-analysis' `
                -DefaultName 'Artificial Analysis' `
                -DefaultVersion $ArtificialAnalysisVersion `
                -VersionHint $ArtificialAnalysisVersion `
                -RetrievedHint $retrievedDate `
                -SnapshotRetrieved $retrievedDate
            $entry = [pscustomobject][ordered]@{
                CatalogId     = $catalogId
                Evaluation    = 'CritPt'
                Category      = 'scientific-reasoning'
                Score         = $scoreVal.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
                NumericScore  = $scoreVal
                SourceId      = $source.Id
                SourceName    = $source.Name
                SourceVersion = $source.Version
                SourceUrl     = $source.Url
                Retrieved     = $source.Retrieved
                Provenance    = $source.Provenance
                License       = $source.License
                Redistribution = $source.Redistribution
                Status        = $source.Status
            }
            $scoreRows.Add($entry)
            $modelEvalLookup[$catalogId]['CritPt'] = $entry
        }

        # GDP.pdf (source publisher retained from the archive row).
        $gdpBest = Get-BestVersionRow -Rows $gdpPdfRows -VersionPattern $versionRegex -ScoreColumn 'GDP.pdf score'
        if ($null -ne $gdpBest -and $gdpBest.Score -gt 0) {
            $scoreVal = [Math]::Round($gdpBest.Score, 3)
            $gdpSource = if ($gdpBest.Row.'Source link') { [string]$gdpBest.Row.'Source link' } else { [string]$gdpBest.Row.Source }
            $source = Get-SourceDetailLocal `
                -RawSource $gdpSource `
                -DefaultId 'surge-gdp-pdf' `
                -DefaultName 'Surge AI GDP.pdf' `
                -DefaultVersion $EpochVersion `
                -VersionHint ([string]$gdpBest.Row.'Last updated') `
                -RetrievedHint ([string]$gdpBest.Row.'Last updated') `
                -SnapshotRetrieved $retrievedDate
            $entry = [pscustomobject][ordered]@{
                CatalogId     = $catalogId
                Evaluation    = 'GDP.pdf'
                Category      = 'general-long-doc'
                Score         = $scoreVal.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
                NumericScore  = $scoreVal
                SourceId      = $source.Id
                SourceName    = $source.Name
                SourceVersion = $source.Version
                SourceUrl     = $source.Url
                Retrieved     = $source.Retrieved
                Provenance    = $source.Provenance
                License       = $source.License
                Redistribution = $source.Redistribution
                Status        = $source.Status
            }
            $scoreRows.Add($entry)
            $modelEvalLookup[$catalogId]['GDP.pdf'] = $entry
        }

        # Epoch Capabilities Index (composite normalized capability score across 40+ evaluations)
        $eciMatches = @($eciRows | Where-Object { (Get-ModelLookupKey -Value ([string]$_.Model)) -eq $displayKey })
        $eciCandidates = @(
            foreach ($eciRow in $eciMatches) {
                $signature = @(
                    $eciRow.PSObject.Properties |
                        Sort-Object Name |
                        ForEach-Object { "$($_.Name)=$(([string]$_.Value).Trim())" }
                ) -join '|'
                [pscustomobject]@{
                    Signature = $signature
                    Row       = $eciRow
                }
            }
        )
        if (@($eciCandidates | ForEach-Object { $_.Signature } | Sort-Object -Unique).Count -gt 1) {
            throw "Conflicting Epoch Capabilities Index rows for '$catalogId'; refusing row-order-dependent selection."
        }
        $eciMatch = if ($eciCandidates.Count -gt 0) {
            @($eciCandidates | Sort-Object Signature | Select-Object -First 1)[0].Row
        }
        else {
            $null
        }
        if ($eciMatch -and $eciMatch.eci -match '^-?\d+(\.\d+)?$') {
            $eciNormalized = [Math]::Round(([double]$eciMatch.eci - 100.0) / 100.0, 3)
            if ($eciNormalized -lt 0.0 -or $eciNormalized -gt 1.0) {
                throw "Epoch Capabilities Index for '$catalogId' normalizes to '$eciNormalized'; expected 0.0 through 1.0."
            }
            $source = Get-SourceDetailLocal `
                -RawSource 'https://epoch.ai/benchmarks' `
                -DefaultId 'epoch-ai' `
                -DefaultName 'Epoch AI Benchmarking Hub' `
                -DefaultVersion $EpochVersion `
                -VersionHint $EpochVersion `
                -RetrievedHint $retrievedDate `
                -SnapshotRetrieved $retrievedDate
            $entry = [pscustomobject][ordered]@{
                CatalogId     = $catalogId
                Evaluation    = 'Epoch Capabilities Index'
                Category      = 'general-long-doc'
                Score         = $eciNormalized.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
                NumericScore  = $eciNormalized
                SourceId      = $source.Id
                SourceName    = $source.Name
                SourceVersion = $source.Version
                SourceUrl     = $source.Url
                Retrieved     = $source.Retrieved
                Provenance    = $source.Provenance
                License       = $source.License
                Redistribution = $source.Redistribution
                Status        = $source.Status
            }
            $scoreRows.Add($entry)
            $modelEvalLookup[$catalogId]['Epoch Capabilities Index'] = $entry
        }

        $aaEntry = $null
        foreach ($lookup in @($catalogId, $display)) {
            $lookupKey = Get-ModelLookupKey -Value $lookup
            if ($lookupKey -and $aaApiModels.ContainsKey($lookupKey)) {
                $aaEntry = $aaApiModels[$lookupKey]
                break
            }
        }
        if ($aaEntry) {
            $evaluations = if ($aaEntry.PSObject.Properties['evaluations']) { $aaEntry.evaluations } else { $aaEntry }
            $source = Get-SourceDetailLocal `
                -RawSource 'https://artificialanalysis.ai/data-api' `
                -DefaultId 'artificial-analysis' `
                -DefaultName 'Artificial Analysis' `
                -DefaultVersion $ArtificialAnalysisVersion `
                -VersionHint $ArtificialAnalysisVersion `
                -RetrievedHint $retrievedDate `
                -SnapshotRetrieved $retrievedDate
            foreach ($apiSpec in $aaEvaluationSpecs) {
                $property = $evaluations.PSObject.Properties[$apiSpec.Property]
                if (-not $property) {
                    continue
                }
                $scoreVal = ConvertTo-NormalizedScore -Value $property.Value
                if ($null -eq $scoreVal) {
                    continue
                }
                $entry = [pscustomobject][ordered]@{
                    CatalogId      = $catalogId
                    Evaluation     = $apiSpec.EvalName
                    Category       = $apiSpec.Category
                    Score          = $scoreVal.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
                    NumericScore   = $scoreVal
                    SourceId       = $source.Id
                    SourceName     = $source.Name
                    SourceVersion  = $source.Version
                    SourceUrl      = $source.Url
                    Retrieved      = $source.Retrieved
                    Provenance     = $source.Provenance
                    License        = $source.License
                    Redistribution = $source.Redistribution
                    Status         = $source.Status
                }
                $scoreRows.Add($entry)
                $modelEvalLookup[$catalogId][$apiSpec.EvalName] = $entry
            }
        }
    }

    # Add informational self-reported row for mai-code-1.1-flash (vendor documentation only;
    # never used by Resolve-SquadModelRoute.ps1 to rank or pick a model).
    $scoreRows.Add([pscustomobject][ordered]@{
            CatalogId     = 'mai-code-1.1-flash'
            Evaluation    = 'Vendor Task-Area Declaration'
            Category      = 'coding'
            Score         = '0.500'
            NumericScore  = 0.500
            SourceId      = 'vendor-model-card'
            SourceName    = 'Vendor Model Cards and GitHub Comparison Guide'
            SourceVersion = '2026-10'
            SourceUrl     = 'https://docs.github.com/en/copilot/reference/ai-models/model-comparison'
            Retrieved     = '2026-10-15'
            Provenance    = 'self-reported'
            License       = 'Public vendor documentation'
            Redistribution = 'informational-only'
            Status        = 'self-reported-only'
        })

    function Test-RoutingFreshScoreLocal {
        param([Parameter(Mandatory)]$Row)

        $scoreDate = [datetime]::MinValue
        if (-not [datetime]::TryParseExact(
                [string]$Row.Retrieved,
                'yyyy-MM-dd',
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$scoreDate
            )) {
            return $false
        }
        $ageDays = ($AsOf.Date - $scoreDate.Date).TotalDays
        return $ageDays -ge 0 -and $ageDays -le 90
    }

    # One mapping drives both the materialized fit table and the runtime-readable
    # Assignment Class Evidence Mapping table, preventing aggregation drift.
    $classEvidenceMap = [ordered]@{
        research = [ordered]@{
            Primary   = @('Artificial Analysis Intelligence Index', 'GDP.pdf', 'GPQA diamond', 'HLE', 'CritPt', 'DeepResearch Bench', 'SimpleQA Verified')
            Secondary = @('Artificial Analysis Agentic Index', 'APEX-Agents', 'Epoch Capabilities Index')
            Rule      = 'Long-document synthesis, scientific/general reasoning, and factual accuracy (`fit 3..0`, then `Blended` cost)'
        }
        planning = [ordered]@{
            Primary   = @('FrontierMath-Tiers-1-3-v2', 'FrontierMath-Tier-4-v2', 'GPQA diamond', 'CritPt', 'HLE', 'GDP.pdf', 'Artificial Analysis Intelligence Index')
            Secondary = @('Artificial Analysis Agentic Index', 'APEX-Agents', 'ProofBench', 'OTIS Mock AIME', 'Epoch Capabilities Index')
            Rule      = 'Multi-step architectural, mathematical, and scientific reasoning (`fit 3..0`, then `Blended` cost)'
        }
        implementation = [ordered]@{
            Primary   = @('Artificial Analysis Coding Index', 'Artificial Analysis Agentic Index', 'SciCode', 'Terminal-Bench', 'SWE-Bench verified', 'FrontierCode', 'DeepSWE', 'APEX-Agents')
            Secondary = @('FrontierSWE', 'OSWorld 2.0', 'Epoch Capabilities Index')
            Rule      = 'Agentic software engineering and coding sub-evaluations; math-specific sources (`FrontierMath`, `ProofBench`) apply to quantitative analysis roles (`data-scientist`, `experimenter`, `performance`) rather than general implementation (`fit 3..0`, then `Blended` cost)'
        }
        review = [ordered]@{
            Primary   = @('Artificial Analysis Coding Index', 'SWE-Bench verified', 'Terminal-Bench', 'SciCode', 'GPQA diamond', 'CritPt', 'HLE')
            Secondary = @('DeepSWE', 'FrontierCode', 'ProofBench', 'Epoch Capabilities Index')
            Rule      = 'Code verification, defect detection, and adversarial scientific reasoning (`fit 3..0`, then `Blended` cost)'
        }
        council = [ordered]@{
            Primary   = @('Artificial Analysis Intelligence Index', 'GPQA diamond', 'FrontierMath-Tiers-1-3-v2', 'FrontierMath-Tier-4-v2', 'CritPt', 'HLE', 'GDP.pdf')
            Secondary = @('Artificial Analysis Agentic Index', 'APEX-Agents', 'SimpleQA Verified', 'Epoch Capabilities Index')
            Rule      = 'Cross-domain architectural, security, cost, and governance judgment (`fit 3..0`, then `Blended` cost)'
        }
        intake = [ordered]@{
            Primary   = @('Artificial Analysis Agentic Index', 'Artificial Analysis Intelligence Index', 'APEX-Agents', 'GDP.pdf', 'GPQA diamond', 'SimpleQA Verified')
            Secondary = @('FrontierCode', 'Artificial Analysis Coding Index', 'SciCode', 'Epoch Capabilities Index')
            Rule      = 'Cost and latency (`Blended`) among models clearing the requirements-judgment capability floor (`fit 3..0`, then `Blended` cost)'
        }
        bookkeeping = [ordered]@{
            Primary   = @('Artificial Analysis Intelligence Index', 'GPQA diamond', 'Artificial Analysis Coding Index', 'SciCode', 'Artificial Analysis Agentic Index', 'APEX-Agents', 'FrontierCode')
            Secondary = @('Epoch Capabilities Index')
            Rule      = 'Cost and latency (`Blended`) first among models clearing the structured-output capability floor (`ECI >= 140` or `GPQA diamond >= 0.60`; `fit 3..0`, then `Blended` cost)'
        }
    }

    $evidenceFitRows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($catalogId in $catalogModelSpecs.Keys) {
        if (-not $modelEvalLookup.ContainsKey($catalogId)) {
            continue
        }
        $evalMap = $modelEvalLookup[$catalogId]
        if ($evalMap.Count -eq 0) {
            continue
        }

        if (-not $catalogFit.ContainsKey($catalogId)) {
            continue
        }

        $freshIndependentRows = @(
            $evalMap.Values |
                Where-Object { $_.Provenance -eq 'independent' -and (Test-RoutingFreshScoreLocal -Row $_) }
        )
        $numericValues = @($freshIndependentRows | ForEach-Object { $_.NumericScore })
        if ($numericValues.Count -eq 0) {
            continue
        }
        $composite = [Math]::Round((($numericValues | Measure-Object -Average).Average), 3)

        $sourceTokens = @(
            $freshIndependentRows |
                ForEach-Object { "$($_.SourceId)@$($_.SourceVersion)" } |
                Sort-Object -Unique
        )

        $keyEvalNames = [System.Collections.Generic.List[string]]::new()
        $fitValues = [ordered]@{}
        foreach ($classKey in $classes) {
            $classRows = @(
                foreach ($pref in @($classEvidenceMap[$classKey].Primary + $classEvidenceMap[$classKey].Secondary)) {
                    if (
                        $evalMap.Contains($pref) -and
                        $evalMap[$pref].Provenance -eq 'independent' -and
                        (Test-RoutingFreshScoreLocal -Row $evalMap[$pref])
                    ) {
                        $evalMap[$pref]
                    }
                }
            )
            if ($classRows.Count -eq 0) {
                $fitValues[$classKey] = 0
                continue
            }
            $average = [double](($classRows | Measure-Object -Property NumericScore -Average).Average)
            $fitValues[$classKey] = ConvertTo-EvidenceFit -Average $average
            foreach ($row in $classRows) {
                if (-not $keyEvalNames.Contains($row.Evaluation) -and $keyEvalNames.Count -lt 6) {
                    $keyEvalNames.Add($row.Evaluation)
                }
            }
        }

        $fitRow = [ordered]@{
            CatalogId = $catalogId
        }
        foreach ($classKey in $classes) {
            $fitRow[$classKey] = $fitValues[$classKey]
        }
        $fitRow['Composite'] = $composite.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
        $fitRow['Sources'] = ($sourceTokens -join ', ')
        $fitRow['KeyEvaluations'] = ($keyEvalNames -join ', ')
        $evidenceFitRows.Add([pscustomobject]$fitRow)
    }

    $independentScoreCount = @($scoreRows | Where-Object { $_.Provenance -eq 'independent' }).Count
    if ($independentScoreCount -eq 0 -or $evidenceFitRows.Count -eq 0) {
        throw "Benchmark refresh produced no usable independent model coverage; preserving the existing snapshot instead of replacing it."
    }
    if (-not $AllowCoverageReduction -and (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        $existingEvidenceKeys = @(Get-IndependentSnapshotEvidenceKey -Path $OutputPath)
        if ($existingEvidenceKeys.Count -gt 0) {
            $nextEvidenceKeys = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@(
                    $scoreRows |
                        Where-Object { $_.Provenance -eq 'independent' } |
                        ForEach-Object { "$($_.CatalogId)`n$($_.Evaluation)" } |
                        Sort-Object -Unique
                ),
                [System.StringComparer]::Ordinal
            )
            $removedKeys = @($existingEvidenceKeys | Where-Object { -not $nextEvidenceKeys.Contains($_) })
            if ($removedKeys.Count -gt 0) {
                $removedLabels = @(
                    $removedKeys |
                        ForEach-Object {
                            $parts = @($_ -split "`n", 2)
                            "$($parts[0])/$($parts[1])"
                        }
                )
                $preview = @($removedLabels | Select-Object -First 8) -join ', '
                $remainder = if ($removedLabels.Count -gt 8) { " (and $($removedLabels.Count - 8) more)" } else { '' }
                throw "Benchmark refresh would remove existing independent evidence coverage for $preview$remainder; preserving the last-good snapshot. Re-run with -AllowCoverageReduction only after confirming the upstream removal is intentional."
            }
        }
    }

    # Build canonical tables first so we can compute a date-independent content digest.
    $sourcesTableLines = @(
        '| Source ID | Source name | Version | Retrieved | License | Redistribution | Status | URL |'
        '| --- | --- | --- | --- | --- | --- | --- | --- |'
    )
    $digestSourceLines = [System.Collections.Generic.List[string]]::new()
    foreach ($group in ($scoreRows | Group-Object SourceId | Sort-Object Name)) {
        $sourceNames = @($group.Group | ForEach-Object { $_.SourceName } | Where-Object { $_ } | Sort-Object -Unique)
        $versions = @($group.Group | ForEach-Object { $_.SourceVersion } | Where-Object { $_ } | Sort-Object -Unique)
        $licenses = @($group.Group | ForEach-Object { $_.License } | Where-Object { $_ } | Sort-Object -Unique)
        $redistributions = @($group.Group | ForEach-Object { $_.Redistribution } | Where-Object { $_ } | Sort-Object -Unique)
        $statuses = @($group.Group | ForEach-Object { $_.Status } | Where-Object { $_ } | Sort-Object -Unique)
        $sourceUrls = @($group.Group | ForEach-Object { $_.SourceUrl } | Where-Object { $_ } | Sort-Object -Unique)
        $sourceUrlCell = if ($sourceUrls.Count -gt 0) { @($sourceUrls | ForEach-Object { "<$_>" }) -join ', ' } else { '—' }
        $sourcesTableLines += "| ``$($group.Name)`` | $($sourceNames -join '; ') | ``$($versions -join ', ')`` | ``$retrievedDate`` | $($licenses -join '; ') | $($redistributions -join '; ') | $($statuses -join '; ') | $sourceUrlCell |"
        $digestSourceLines.Add("$($group.Name)|$($sourceNames -join ';')|$($versions -join ',')|$($licenses -join ';')|$($redistributions -join ';')|$($statuses -join ';')|$($sourceUrls -join ',')")
    }
    $sourcesTableLines += @(
        "| ``llm-stats`` | LLM Stats (ZeroEval) | ``2026-10`` | ``$retrievedDate`` | Commercial contract required for dataset redistribution | prohibited-on-free-tier | excluded | <https://llm-stats.com/developer> |"
        "| ``lmarena`` | Arena (formerly LMArena) | ``2026-10`` | ``$retrievedDate`` | CC-BY-4.0 / ToS | excluded-by-methodology | excluded | <https://arena.ai> |"
    )

    $mappingTableLines = @(
        '| Assignment class | Primary evaluations | Secondary evaluations | Primary sources | Evidence rule |'
        '| --- | --- | --- | --- | --- |'
    )
    foreach ($classKey in $classes) {
        $mapping = $classEvidenceMap[$classKey]
        $primary = @($mapping.Primary | ForEach-Object { "``$_``" }) -join ', '
        $secondary = @($mapping.Secondary | ForEach-Object { "``$_``" }) -join ', '
        $mappingTableLines += "| ``$classKey`` | $primary | $secondary | source-specific rows from the pinned snapshot | $($mapping.Rule) |"
    }

    $fitTableLines = [System.Collections.Generic.List[string]]::new()
    $fitTableLines.Add('| Catalog ID | research | planning | implementation | review | council | intake | bookkeeping | Composite | Sources | Key evaluations |')
    $fitTableLines.Add('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |')
    foreach ($row in $evidenceFitRows) {
        $fitTableLines.Add("| ``$($row.CatalogId)`` | $($row.research) | $($row.planning) | $($row.implementation) | $($row.review) | $($row.council) | $($row.intake) | $($row.bookkeeping) | $($row.Composite) | $($row.Sources) | $($row.KeyEvaluations) |")
    }

    $scoreTableLines = [System.Collections.Generic.List[string]]::new()
    $scoreTableLines.Add('| Catalog ID | Evaluation | Category | Score | Source ID | Source version | Retrieved | Provenance |')
    $scoreTableLines.Add('| --- | --- | --- | ---: | --- | --- | --- | --- |')
    $digestScoreLines = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $scoreRows) {
        $scoreTableLines.Add("| ``$($row.CatalogId)`` | $($row.Evaluation) | ``$($row.Category)`` | $($row.Score) | ``$($row.SourceId)`` | ``$($row.SourceVersion)`` | ``$($row.Retrieved)`` | ``$($row.Provenance)`` |")
        $digestScoreLines.Add("$($row.CatalogId)|$($row.Evaluation)|$($row.Category)|$($row.Score)|$($row.SourceId)|$($row.SourceVersion)|$($row.SourceUrl)|$($row.Provenance)")
    }

    $digestInput = (($digestSourceLines + $mappingTableLines + $digestScoreLines) -join "`n")
    $digest = "sha256:$(Get-StringSha256 -Text $digestInput)"

    $needsUpdate = $true
    if (-not $Force -and (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        $existingRaw = Get-Content -LiteralPath $OutputPath -Raw
        $existingDigestMatch = [regex]::Match($existingRaw, '\*\*Content Digest:\s*(?<digest>sha256:[0-9a-f]{64})\*\*')
        $existingDateMatch = [regex]::Match($existingRaw, '\*\*Retrieved:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*')
        if ($existingDigestMatch.Success -and $existingDateMatch.Success) {
            $existingDate = [datetime]::ParseExact($existingDateMatch.Groups['date'].Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            $ageDays = ($AsOf.Date - $existingDate.Date).TotalDays
            if ($existingDigestMatch.Groups['digest'].Value -eq $digest -and $ageDays -lt $RefreshThresholdDays) {
                $needsUpdate = $false
                Write-Host "Benchmark digest ($digest) is unchanged and snapshot age ($([int]$ageDays)d) is under the ${RefreshThresholdDays}d refresh threshold." -ForegroundColor Green
            }
        }
    }

    $docLines = @(
        '---'
        'name: squad-model-benchmarks'
        'description: "Pinned, versioned benchmark knowledge base for routing=ranked: source licensing, assignment-class evidence mapping, per-evaluation scores with provenance, and evidence-derived fit tiers."'
        'license: MIT'
        'metadata:'
        '  authors: "Peter-N91/hve-squad"'
        '  spec_version: "1.0"'
        "  last_updated: `"$retrievedDate`""
        '---'
        ''
        '# Squad Model Benchmarks Knowledge Base'
        ''
        '**This knowledge base is a pinned, versioned snapshot updated by a scheduled workflow (`sync-model-benchmarks.yml`), never fetched live during a squad run.** Runtime model routing (`Resolve-SquadModelRoute.ps1` and `model-routing.md`) reads this file locally so dispatches remain deterministic, reproducible, and isolated from untrusted live web content.'
        ''
        "* **Retrieved: $retrievedDate**"
        "* **Content Digest: $digest**"
        '* **Refresh Cadence: Daily check via `.github/workflows/sync-model-benchmarks.yml` (60-day heartbeat refresh; 90-day staleness threshold)**'
        ''
        '## Source Terms and Licensing'
        ''
        'Every source evaluated for `routing=ranked` was checked for methodology transparency, provenance separation (`independent` versus `self-reported`), and redistribution licensing before any score entered this repository:'
        ''
        'Independence is established from a recognized publisher''s original HTTP(S) authority or explicit publisher identity, never from a punctuation-normalized source ID. Unrecognized sources retain their original URL for audit and remain informational-only; IDs that would collide with a recognized publisher are prefixed with `unverified-`.'
        ''
    ) + $sourcesTableLines + @(
        ''
        '### Required Attributions and Redistribution Notes'
        ''
        '* **Epoch AI Benchmarking Hub (`epoch-ai`, CC BY 4.0)**: Data is licensed under the [Creative Commons Attribution 4.0 International License](https://creativecommons.org/licenses/by/4.0/). Attribution: *Epoch AI, "Capabilities & benchmarking". Published online at epoch.ai. Retrieved from `https://epoch.ai/benchmarks/use-this-data` (archive `https://epoch.ai/data/benchmark_data.zip`).*'
        "* **Artificial Analysis (``artificial-analysis``, Intelligence Index $ArtificialAnalysisVersion)**: Artificial Analysis API indices plus its ``SciCode`` and ``CritPt`` evaluations are attributed to [Artificial Analysis](https://artificialanalysis.ai/methodology/intelligence-benchmarking). Scores published by Cognition, Terminal-Bench, Surge AI, or another upstream publisher retain that publisher's source ID and version instead of being relabeled as Artificial Analysis."
        '* **LLM Stats (`llm-stats`, excluded from snapshot)**: ZeroEval / `llm-stats.com` developer terms state that redistributing the dataset requires a commercial contract license and that the aggregator blends vendor self-reported figures with verified ones. No `llm-stats.com` data is copied into this repository.'
        '* **Arena (`lmarena`, excluded from snapshot)**: Crowd-sourced chat preference votes measure general conversational preference rather than task-specific coding, mathematical, or long-document capability, and are never used to rank squad roles.'
        ''
        '## Assignment Class Evidence Mapping'
        ''
        '`routing=ranked` ranks models for each assignment class using independently measured benchmark evidence first, before consulting the declared *Catalog: Assignment Fit* table in `model-catalog.md`. Self-reported vendor figures (`Provenance = self-reported`) are recorded for transparency only and **never** decide or boost a ranked pick.'
        ''
    ) + $mappingTableLines + @(
        ''
        '### Design Decisions on Open Questions'
        ''
        "1. **Coverage and licensing**: Confirmed as of ``$retrievedDate``. The generated snapshot contains $independentScoreCount independently sourced score rows across $($evidenceFitRows.Count) catalog models. Every row retains its actual publisher, version, score date, and provenance; synthetic aliases such as ``hydrafusion-max`` are not presented as measured models."
        '2. **Math-specific sources (`FrontierMath`, `ProofBench`, `OTIS Mock AIME`)**: Required for `planning`, `council`, and math-heavy analysis roles (`data-scientist`, `experimenter`, `performance`, `cost-manager`), where quantitative and formal reasoning drive task quality. Standard `implementation` roles (`developer`, `iac-author`, `deployer`, `release-engineer`, `technical-writer`, `presenter`, `prompt-engineer`) rank on Coding and Agents sub-evaluations (`SciCode`, `Terminal-Bench`, `SWE-Bench verified`, `FrontierCode`, `DeepSWE`, `APEX-Agents`) without requiring `FrontierMath`.'
        '3. **Snapshot refresh cadence and staleness threshold**: `.github/workflows/sync-model-benchmarks.yml` runs daily at `06:30 UTC`, runs `scripts/Sync-ModelBenchmarks.ps1`, validates the snapshot with Pester, and opens or updates a reviewed pull request whenever benchmark scores or source versions change (or when the snapshot age reaches 60 days). At runtime, a snapshot older than **90 days** from its `Retrieved:` date (or one that fails to parse or lacks independent evidence for a candidate) falls back to `model-catalog.md`''s declared fit table and logs one warning.'
        '4. **Coverage continuity**: An automatic refresh may add models or change evidence, but it refuses to remove any independent model/evaluation evidence key present in the current snapshot. An intentional upstream removal requires a reviewed rerun with `-AllowCoverageReduction`; this avoids guessing an arbitrary minimum model or score count while preserving the last-good snapshot through broad source or mapping outages.'
        '5. **Materialized fit versus runtime freshness**: The table below is the fit view on this snapshot''s `Retrieved:` date. Its primary-plus-secondary aggregation is identical to the router''s, while `Resolve-SquadModelRoute.ps1` re-applies the 90-day row window on the actual dispatch date. The semantic digest therefore covers sources, mappings, and scores, not age-only changes to this derived view.'
        '6. **Semantic duplicate normalization**: Inferred archive versions hash unique normalized records across every input dataset. Redundant identical records do not change the source version, semantic digest, or emitted evidence; conflicting model/evaluation records are still rejected before the previous snapshot can be replaced.'
        ''
        '## Evidence-Derived Assignment Fit'
        ''
        'Each row below is derived exclusively from rows in *Benchmark Scores* with `Provenance = independent` that are no more than 90 days old on the snapshot date. Models with no fresh independent benchmark evaluations (`mai-code-1.1-flash`) are omitted from this table so `Resolve-SquadModelRoute.ps1` falls back to `model-catalog.md`''s declared fit table with a warning and never ranks on self-reported or stale numbers.'
        ''
    ) + $fitTableLines + @(
        ''
        '## Benchmark Scores'
        ''
        'Every score entry records its exact `Source ID`, `Source version`, `Retrieved` date (`yyyy-MM-dd`), and `Provenance` (`independent` or `self-reported`). Validation tests reject any row missing provenance or carrying an unrecognized provenance value.'
        ''
    ) + $scoreTableLines + @('')

    $content = ($docLines -join "`n")

    if ($DryRun) {
        Write-Host "[DryRun] Would write $($scoreRows.Count) benchmark score rows across $($evidenceFitRows.Count) independently evaluated models (needsUpdate=$needsUpdate)." -ForegroundColor Cyan
    }
    elseif ($needsUpdate -or $Force) {
        if ($PSCmdlet.ShouldProcess($OutputPath, 'Write model-benchmarks.md knowledge base')) {
            Set-Content -LiteralPath $OutputPath -Value $content -Encoding utf8NoBOM -NoNewline
            Write-Host "Wrote $OutputPath ($($scoreRows.Count) score rows, $($evidenceFitRows.Count) independently evaluated models)." -ForegroundColor Green
        }
    }

    if ($GitHubOutput -and $env:GITHUB_OUTPUT) {
        @(
            "updated=$($needsUpdate.ToString().ToLowerInvariant())"
            "retrieved=$retrievedDate"
            "digest=$digest"
            "models_covered=$($evidenceFitRows.Count)"
            "scores_count=$($scoreRows.Count)"
        ) | Add-Content -LiteralPath $env:GITHUB_OUTPUT
    }

    [pscustomobject][ordered]@{
        Updated       = $needsUpdate
        OutputPath    = $OutputPath
        Retrieved     = $retrievedDate
        Digest        = $digest
        ModelsCovered = $evidenceFitRows.Count
        ScoresCount   = $scoreRows.Count
    }
}
finally {
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
