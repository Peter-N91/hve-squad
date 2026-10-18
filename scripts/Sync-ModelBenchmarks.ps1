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
    script computes a SHA-256 content digest over the normalized score and
    mapping tables (excluding the `Retrieved:` date stamp). When the digest
    matches the existing file on disk and the existing `Retrieved:` date is
    younger than -RefreshThresholdDays (default 60 days, well below the 90-day
    staleness cliff), the script reports no update needed unless -Force is set.

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
    Version identifier for the Epoch AI snapshot. Defaults to -AsOf (`yyyy-MM-dd`).
.PARAMETER ArtificialAnalysisVersion
    Version identifier for the Artificial Analysis methodology. Defaults to `v4.3.2`.
.PARAMETER AsOf
    Retrieval date stamped into the snapshot (`yyyy-MM-dd`). Defaults to UTC today.
.PARAMETER RefreshThresholdDays
    Maximum age in days before a date-only refresh is written even if the
    content digest has not changed. Defaults to 60 (30 days before the 90-day
    staleness threshold).
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
if (-not $EpochVersion) {
    $EpochVersion = $retrievedDate
}

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

function Get-BestVersionScore {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][string]$VersionPattern,
        [Parameter(Mandatory)][string]$ScoreColumn
    )

    $best = $null
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
        if ($null -eq $best -or $val -gt $best) {
            $best = $val
        }
    }
    return $best
}

function Get-StringSha256 {
    param([Parameter(Mandatory)][string]$Text)

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

    $aaApiModels = @{}
    if ($ArtificialAnalysisJsonPath -and (Test-Path -LiteralPath $ArtificialAnalysisJsonPath -PathType Leaf)) {
        $aaPayload = Get-Content -LiteralPath $ArtificialAnalysisJsonPath -Raw | ConvertFrom-Json
        if ($aaPayload.PSObject.Properties['intelligence_index_version'] -and $aaPayload.intelligence_index_version) {
            $ArtificialAnalysisVersion = "v$($aaPayload.intelligence_index_version)"
        }
        foreach ($entry in @($aaPayload.data)) {
            if ($entry.slug) {
                $aaApiModels[$entry.slug] = $entry
            }
        }
    }
    elseif ($ArtificialAnalysisApiKey) {
        try {
            $aaPayload = Invoke-RestMethod -Uri 'https://artificialanalysis.ai/api/v2/language/models/free' -Headers @{ 'x-api-key' = $ArtificialAnalysisApiKey } -Method Get
            if ($aaPayload.PSObject.Properties['intelligence_index_version'] -and $aaPayload.intelligence_index_version) {
                $ArtificialAnalysisVersion = "v$($aaPayload.intelligence_index_version)"
            }
            foreach ($entry in @($aaPayload.data)) {
                if ($entry.slug) {
                    $aaApiModels[$entry.slug] = $entry
                }
            }
        }
        catch {
            Write-Warning "Artificial Analysis API request failed ($($_.Exception.Message)); continuing with public evaluation datasets."
        }
    }

    # Evaluation catalog: maps ECI benchmark names to normalized evaluation metadata.
    $procEvalSpecs = @(
        [ordered]@{ RawName = 'GPQA diamond'; EvalName = 'GPQA diamond'; Category = 'scientific-reasoning'; SourceId = 'epoch-ai'; SourceVersion = $EpochVersion }
        [ordered]@{ RawName = 'FrontierMath-Tiers-1-3-v2-Private'; EvalName = 'FrontierMath-Tiers-1-3-v2'; Category = 'math'; SourceId = 'epoch-ai'; SourceVersion = $EpochVersion }
        [ordered]@{ RawName = 'FrontierMath-Tier-4-v2-Private'; EvalName = 'FrontierMath-Tier-4-v2'; Category = 'math'; SourceId = 'epoch-ai'; SourceVersion = $EpochVersion }
        [ordered]@{ RawName = 'FrontierMath-2025-02-28-Private'; EvalName = 'FrontierMath-v1'; Category = 'math'; SourceId = 'epoch-ai'; SourceVersion = $EpochVersion }
        [ordered]@{ RawName = 'OTIS Mock AIME 2024-2025'; EvalName = 'OTIS Mock AIME'; Category = 'math'; SourceId = 'epoch-ai'; SourceVersion = $EpochVersion }
        [ordered]@{ RawName = 'ProofBench'; EvalName = 'ProofBench'; Category = 'math'; SourceId = 'epoch-ai'; SourceVersion = $EpochVersion }
        [ordered]@{ RawName = 'SWE-Bench verified'; EvalName = 'SWE-Bench verified'; Category = 'coding'; SourceId = 'epoch-ai'; SourceVersion = $EpochVersion }
        [ordered]@{ RawName = 'Terminal Bench'; EvalName = 'Terminal-Bench'; Category = 'coding'; SourceId = 'artificial-analysis'; SourceVersion = $ArtificialAnalysisVersion }
        [ordered]@{ RawName = 'FrontierCode'; EvalName = 'FrontierCode'; Category = 'coding'; SourceId = 'artificial-analysis'; SourceVersion = $ArtificialAnalysisVersion }
        [ordered]@{ RawName = 'DeepSWE'; EvalName = 'DeepSWE'; Category = 'coding'; SourceId = 'epoch-ai'; SourceVersion = $EpochVersion }
        [ordered]@{ RawName = 'FrontierSWE'; EvalName = 'FrontierSWE'; Category = 'agents'; SourceId = 'epoch-ai'; SourceVersion = $EpochVersion }
        [ordered]@{ RawName = 'APEX-Agents'; EvalName = 'APEX-Agents'; Category = 'agents'; SourceId = 'artificial-analysis'; SourceVersion = $ArtificialAnalysisVersion }
        [ordered]@{ RawName = 'OSWorld 2.0'; EvalName = 'OSWorld 2.0'; Category = 'agents'; SourceId = 'epoch-ai'; SourceVersion = $EpochVersion }
        [ordered]@{ RawName = 'HLE'; EvalName = 'HLE'; Category = 'scientific-reasoning'; SourceId = 'artificial-analysis'; SourceVersion = $ArtificialAnalysisVersion }
        [ordered]@{ RawName = 'SimpleQA Verified'; EvalName = 'SimpleQA Verified'; Category = 'general-long-doc'; SourceId = 'epoch-ai'; SourceVersion = $EpochVersion }
        [ordered]@{ RawName = 'DeepResearch Bench'; EvalName = 'DeepResearch Bench'; Category = 'general-long-doc'; SourceId = 'epoch-ai'; SourceVersion = $EpochVersion }
    )

    $scoreRows = [System.Collections.Generic.List[pscustomobject]]::new()
    $modelEvalLookup = @{}

    foreach ($catalogId in $catalogModelSpecs.Keys) {
        $spec = $catalogModelSpecs[$catalogId]
        $display = $spec.Display
        $versionRegex = $spec.VersionRegex
        $modelEvalLookup[$catalogId] = [ordered]@{}

        $modelProcRows = @($procRows | Where-Object { $_.model_display -eq $display })
        foreach ($evalSpec in $procEvalSpecs) {
            if ($evalSpec.EvalName -eq 'FrontierMath-v1' -and $modelEvalLookup[$catalogId].Contains('FrontierMath-Tiers-1-3-v2')) {
                continue
            }
            $matchRow = $modelProcRows | Where-Object { $_.benchmark -eq $evalSpec.RawName } | Select-Object -First 1
            if ($matchRow -and $matchRow.performance -match '^-?\d+(\.\d+)?([eE][+-]?\d+)?$') {
                $scoreVal = [Math]::Round([double]$matchRow.performance, 3)
                $entry = [pscustomobject][ordered]@{
                    CatalogId     = $catalogId
                    Evaluation    = $evalSpec.EvalName
                    Category      = $evalSpec.Category
                    Score         = $scoreVal.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
                    NumericScore  = $scoreVal
                    SourceId      = $evalSpec.SourceId
                    SourceVersion = $evalSpec.SourceVersion
                    Retrieved     = $retrievedDate
                    Provenance    = 'independent'
                }
                $scoreRows.Add($entry)
                $modelEvalLookup[$catalogId][$evalSpec.EvalName] = $entry
            }
        }

        # SciCode (Artificial Analysis Coding evaluation)
        $scicodeBest = Get-BestVersionScore -Rows $scicodeRows -VersionPattern $versionRegex -ScoreColumn 'Score'
        if ($null -ne $scicodeBest) {
            $scoreVal = [Math]::Round($scicodeBest, 3)
            $entry = [pscustomobject][ordered]@{
                CatalogId     = $catalogId
                Evaluation    = 'SciCode'
                Category      = 'coding'
                Score         = $scoreVal.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
                NumericScore  = $scoreVal
                SourceId      = 'artificial-analysis'
                SourceVersion = $ArtificialAnalysisVersion
                Retrieved     = $retrievedDate
                Provenance    = 'independent'
            }
            $scoreRows.Add($entry)
            $modelEvalLookup[$catalogId]['SciCode'] = $entry
        }

        # CritPt (Artificial Analysis Scientific Reasoning evaluation)
        $critptBest = Get-BestVersionScore -Rows $critptRows -VersionPattern $versionRegex -ScoreColumn 'Accuracy'
        if ($null -ne $critptBest -and $critptBest -gt 0) {
            $scoreVal = [Math]::Round($critptBest, 3)
            $entry = [pscustomobject][ordered]@{
                CatalogId     = $catalogId
                Evaluation    = 'CritPt'
                Category      = 'scientific-reasoning'
                Score         = $scoreVal.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
                NumericScore  = $scoreVal
                SourceId      = 'artificial-analysis'
                SourceVersion = $ArtificialAnalysisVersion
                Retrieved     = $retrievedDate
                Provenance    = 'independent'
            }
            $scoreRows.Add($entry)
            $modelEvalLookup[$catalogId]['CritPt'] = $entry
        }

        # GDP.pdf (Artificial Analysis General long-document evaluation)
        $gdpBest = Get-BestVersionScore -Rows $gdpPdfRows -VersionPattern $versionRegex -ScoreColumn 'GDP.pdf score'
        if ($null -ne $gdpBest -and $gdpBest -gt 0) {
            $scoreVal = [Math]::Round($gdpBest, 3)
            $entry = [pscustomobject][ordered]@{
                CatalogId     = $catalogId
                Evaluation    = 'GDP.pdf'
                Category      = 'general-long-doc'
                Score         = $scoreVal.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
                NumericScore  = $scoreVal
                SourceId      = 'artificial-analysis'
                SourceVersion = $ArtificialAnalysisVersion
                Retrieved     = $retrievedDate
                Provenance    = 'independent'
            }
            $scoreRows.Add($entry)
            $modelEvalLookup[$catalogId]['GDP.pdf'] = $entry
        }

        # Epoch Capabilities Index (composite normalized capability score across 40+ evaluations)
        $eciMatch = $eciRows | Where-Object { $_.Model -eq $display } | Select-Object -First 1
        if ($eciMatch -and $eciMatch.eci -match '^-?\d+(\.\d+)?$') {
            $eciNormalized = [Math]::Round(([double]$eciMatch.eci - 100.0) / 100.0, 3)
            $entry = [pscustomobject][ordered]@{
                CatalogId     = $catalogId
                Evaluation    = 'Epoch Capabilities Index'
                Category      = 'general-long-doc'
                Score         = $eciNormalized.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
                NumericScore  = $eciNormalized
                SourceId      = 'epoch-ai'
                SourceVersion = $EpochVersion
                Retrieved     = $retrievedDate
                Provenance    = 'independent'
            }
            $scoreRows.Add($entry)
            $modelEvalLookup[$catalogId]['Epoch Capabilities Index'] = $entry
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
            SourceVersion = '2026-10'
            Retrieved     = '2026-10-15'
            Provenance    = 'self-reported'
        })

    # Class evaluation preference order for summarizing key evaluations per class/model.
    $classPreferredEvals = [ordered]@{
        research       = @('GDP.pdf', 'GPQA diamond', 'HLE', 'CritPt', 'DeepResearch Bench', 'SimpleQA Verified', 'APEX-Agents', 'Epoch Capabilities Index')
        planning       = @('FrontierMath-Tiers-1-3-v2', 'FrontierMath-Tier-4-v2', 'GPQA diamond', 'CritPt', 'HLE', 'GDP.pdf', 'APEX-Agents', 'ProofBench', 'OTIS Mock AIME')
        implementation = @('SciCode', 'Terminal-Bench', 'SWE-Bench verified', 'FrontierCode', 'DeepSWE', 'APEX-Agents', 'FrontierSWE')
        review         = @('SWE-Bench verified', 'Terminal-Bench', 'SciCode', 'GPQA diamond', 'CritPt', 'HLE', 'FrontierCode', 'DeepSWE', 'ProofBench')
        council        = @('GPQA diamond', 'FrontierMath-Tiers-1-3-v2', 'FrontierMath-Tier-4-v2', 'CritPt', 'HLE', 'GDP.pdf', 'APEX-Agents')
        intake         = @('APEX-Agents', 'GDP.pdf', 'GPQA diamond', 'SimpleQA Verified', 'FrontierCode', 'SciCode')
        bookkeeping    = @('GPQA diamond', 'SciCode', 'APEX-Agents', 'FrontierCode', 'Epoch Capabilities Index')
    }

    $evidenceFitRows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($catalogId in $catalogModelSpecs.Keys) {
        $evalMap = $modelEvalLookup[$catalogId]
        if ($evalMap.Count -eq 0) {
            continue
        }

        $declaredScores = $catalogFit[$catalogId]
        if (-not $declaredScores) {
            continue
        }

        $numericValues = @($evalMap.Values | Where-Object { $_.Provenance -eq 'independent' } | ForEach-Object { $_.NumericScore })
        if ($numericValues.Count -eq 0) {
            continue
        }
        $composite = [Math]::Round((($numericValues | Measure-Object -Average).Average), 3)

        $sourceTokens = @(
            $evalMap.Values |
                Where-Object { $_.Provenance -eq 'independent' } |
                ForEach-Object { "$($_.SourceId)@$($_.SourceVersion)" } |
                Sort-Object -Unique
        )

        $keyEvalNames = [System.Collections.Generic.List[string]]::new()
        foreach ($classKey in $classPreferredEvals.Keys) {
            foreach ($pref in $classPreferredEvals[$classKey]) {
                if ($evalMap.Contains($pref) -and -not $keyEvalNames.Contains($pref) -and $keyEvalNames.Count -lt 6) {
                    $keyEvalNames.Add($pref)
                }
            }
        }

        $evidenceFitRows.Add([pscustomobject][ordered]@{
                CatalogId      = $catalogId
                research       = $declaredScores['research']
                planning       = $declaredScores['planning']
                implementation = $declaredScores['implementation']
                review         = $declaredScores['review']
                council        = $declaredScores['council']
                intake         = $declaredScores['intake']
                bookkeeping    = $declaredScores['bookkeeping']
                Composite      = $composite.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
                Sources        = ($sourceTokens -join ', ')
                KeyEvaluations = ($keyEvalNames -join ', ')
            })
    }

    # Build canonical tables first so we can compute a date-independent content digest.
    $sourcesTableLines = @(
        '| Source ID | Source name | Version | Retrieved | License | Redistribution | Status | URL |'
        '| --- | --- | --- | --- | --- | --- | --- | --- |'
        "| ``artificial-analysis`` | Artificial Analysis Intelligence Benchmarking | ``$ArtificialAnalysisVersion`` | ``$retrievedDate`` | Attribution required (CC-BY-4.0 via Epoch AI bundle; Free Data API ToS) | permitted-with-attribution | active | <https://artificialanalysis.ai/methodology/intelligence-benchmarking> |"
        "| ``epoch-ai`` | Epoch AI Benchmarking Hub | ``$EpochVersion`` | ``$retrievedDate`` | CC-BY-4.0 | permitted-with-attribution | active | <https://epoch.ai/benchmarks/use-this-data> |"
        "| ``vendor-model-card`` | Vendor Model Cards and GitHub Comparison Guide | ``2026-10`` | ``2026-10-15`` | Public vendor documentation | informational-only | self-reported-only | <https://docs.github.com/en/copilot/reference/ai-models/model-comparison> |"
        "| ``llm-stats`` | LLM Stats (ZeroEval) | ``2026-10`` | ``$retrievedDate`` | Commercial contract required for dataset redistribution | prohibited-on-free-tier | excluded | <https://llm-stats.com/developer> |"
        "| ``lmarena`` | Arena (formerly LMArena) | ``2026-10`` | ``$retrievedDate`` | CC-BY-4.0 / ToS | excluded-by-methodology | excluded | <https://arena.ai> |"
    )

    $mappingTableLines = @(
        '| Assignment class | Primary evaluations | Secondary evaluations | Primary sources | Evidence rule |'
        '| --- | --- | --- | --- | --- |'
        '| `research` | `GDP.pdf`, `GPQA diamond`, `HLE`, `CritPt`, `DeepResearch Bench`, `SimpleQA Verified` | `APEX-Agents`, `Epoch Capabilities Index` | `artificial-analysis`, `epoch-ai` | Long-document synthesis, scientific/general reasoning, and factual accuracy (`fit 3..0`, then `Blended` cost) |'
        '| `planning` | `FrontierMath-Tiers-1-3-v2`, `FrontierMath-Tier-4-v2`, `GPQA diamond`, `CritPt`, `HLE`, `GDP.pdf` | `APEX-Agents`, `ProofBench`, `OTIS Mock AIME`, `Epoch Capabilities Index` | `epoch-ai`, `artificial-analysis` | Multi-step architectural, mathematical, and scientific reasoning (`fit 3..0`, then `Blended` cost) |'
        '| `implementation` | `SciCode`, `Terminal-Bench`, `SWE-Bench verified`, `FrontierCode`, `DeepSWE`, `APEX-Agents` | `FrontierSWE`, `OSWorld 2.0`, `Epoch Capabilities Index` | `artificial-analysis`, `epoch-ai` | Agentic software engineering and coding sub-evaluations; math-specific sources (`FrontierMath`, `ProofBench`) apply to quantitative analysis roles (`data-scientist`, `experimenter`, `performance`) rather than general implementation (`fit 3..0`, then `Blended` cost) |'
        '| `review` | `SWE-Bench verified`, `Terminal-Bench`, `SciCode`, `GPQA diamond`, `CritPt`, `HLE` | `DeepSWE`, `FrontierCode`, `ProofBench`, `Epoch Capabilities Index` | `artificial-analysis`, `epoch-ai` | Code verification, defect detection, and adversarial scientific reasoning (`fit 3..0`, then `Blended` cost) |'
        '| `council` | `GPQA diamond`, `FrontierMath-Tiers-1-3-v2`, `FrontierMath-Tier-4-v2`, `CritPt`, `HLE`, `GDP.pdf` | `APEX-Agents`, `SimpleQA Verified`, `Epoch Capabilities Index` | `artificial-analysis`, `epoch-ai` | Cross-domain architectural, security, cost, and governance judgment (`fit 3..0`, then `Blended` cost) |'
        '| `intake` | `APEX-Agents`, `GDP.pdf`, `GPQA diamond`, `SimpleQA Verified` | `FrontierCode`, `SciCode`, `Epoch Capabilities Index` | `artificial-analysis`, `epoch-ai` | Cost and latency (`Blended`) among models clearing the requirements-judgment capability floor (`fit 3..0`, then `Blended` cost) |'
        '| `bookkeeping` | `GPQA diamond`, `SciCode`, `APEX-Agents`, `FrontierCode` | `Epoch Capabilities Index` | `epoch-ai`, `artificial-analysis` | Cost and latency (`Blended`) first among models clearing the structured-output capability floor (`ECI >= 140` or `GPQA diamond >= 0.60`; `fit 3..0`, then `Blended` cost) |'
    )

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
        $digestScoreLines.Add("$($row.CatalogId)|$($row.Evaluation)|$($row.Category)|$($row.Score)|$($row.SourceId)|$($row.Provenance)")
    }

    $digestInput = (($mappingTableLines + $digestScoreLines) -join "`n")
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
    ) + $sourcesTableLines + @(
        ''
        '### Required Attributions and Redistribution Notes'
        ''
        '* **Epoch AI Benchmarking Hub (`epoch-ai`, CC BY 4.0)**: Data is licensed under the [Creative Commons Attribution 4.0 International License](https://creativecommons.org/licenses/by/4.0/). Attribution: *Epoch AI, "Capabilities & benchmarking". Published online at epoch.ai. Retrieved from `https://epoch.ai/benchmarks/use-this-data` (archive `https://epoch.ai/data/benchmark_data.zip`).*'
        "* **Artificial Analysis (``artificial-analysis``, Intelligence Index $ArtificialAnalysisVersion)**: Independent evaluation methodology and sub-evaluation scores (``SciCode``, ``CritPt``, ``GDP.pdf``, ``Terminal-Bench``, ``HLE``, ``APEX-Agents``, ``FrontierCode``) are attributed to [Artificial Analysis](https://artificialanalysis.ai/methodology/intelligence-benchmarking) (``$ArtificialAnalysisVersion``: Agents 30%, General 30%, Coding 20%, Scientific Reasoning 20%). Public evaluation scores redistributed via Epoch AI's CC BY 4.0 archive and the Artificial Analysis Free Data API carry explicit source and version tags below."
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
        '1. **Epoch AI and Artificial Analysis coverage and licensing**: Confirmed as of `2026-10-18`. Epoch AI covers 35 of the 36 catalog models under `CC BY 4.0` (including `FrontierMath-Tiers-1-3-v2`, `FrontierMath-Tier-4-v2`, `GPQA diamond`, `SWE-Bench verified`, `OTIS Mock AIME`, and `SimpleQA Verified`), and bundles attributed Artificial Analysis sub-evaluations (`SciCode`, `CritPt`, `GDP.pdf`, `Terminal-Bench`, `HLE`, `APEX-Agents`, `FrontierCode`).'
        '2. **Math-specific sources (`FrontierMath`, `ProofBench`, `OTIS Mock AIME`)**: Required for `planning`, `council`, and math-heavy analysis roles (`data-scientist`, `experimenter`, `performance`, `cost-manager`), where quantitative and formal reasoning drive task quality. Standard `implementation` roles (`developer`, `iac-author`, `deployer`, `release-engineer`, `technical-writer`, `presenter`, `prompt-engineer`) rank on Coding and Agents sub-evaluations (`SciCode`, `Terminal-Bench`, `SWE-Bench verified`, `FrontierCode`, `DeepSWE`, `APEX-Agents`) without requiring `FrontierMath`.'
        '3. **Snapshot refresh cadence and staleness threshold**: `.github/workflows/sync-model-benchmarks.yml` runs daily at `06:30 UTC`, runs `scripts/Sync-ModelBenchmarks.ps1`, validates the snapshot with Pester, and opens or updates a reviewed pull request whenever benchmark scores or source versions change (or when the snapshot age reaches 60 days). At runtime, a snapshot older than **90 days** from its `Retrieved:` date (or one that fails to parse or lacks independent evidence for a candidate) falls back to `model-catalog.md`''s declared fit table and logs one warning.'
        ''
        '## Evidence-Derived Assignment Fit'
        ''
        'Each row below is derived exclusively from rows in *Benchmark Scores* with `Provenance = independent`. Models with no independent benchmark evaluations (`mai-code-1.1-flash`) are omitted from this table so `Resolve-SquadModelRoute.ps1` falls back to `model-catalog.md`''s declared fit table with a warning and never ranks on self-reported numbers.'
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
