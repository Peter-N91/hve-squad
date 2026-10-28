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
    with its source ID, source version, exact model/configuration and distinct
    result, acquisition and verification facts, plus provenance
    (`independent` or `self-reported`), computes the shared versioned capability
    and compatibility-fit views, and writes
    `squad-src/.github/skills/squad/references/model-benchmarks.md`.

    To avoid daily commit churn when upstream scores have not changed, the
    script computes a SHA-256 content digest over normalized source metadata,
    scores, acquisition/verification facts and assignment panels (excluding
    assembly dates and date-relative views). Runtime routing recomputes
    the 90-day verification window, never publication-age expiration.
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
.PARAMETER SnapshotPath
    Rebuild derived views from a local pinned snapshot without fetching any data.
    Source tables, score precision, provenance, and evidence dates are preserved.
    Defaults -AsOf to that snapshot's generation date when not explicitly supplied.
.PARAMETER VerificationPath
    Optional JSON evidence checks with schemaVersion squad-benchmark-verification-v1.
    Each record is bound to Get-SquadBenchmarkRecordDigest and supplies explicit
    model/configuration, acquisition, verification, source URL and content hashes.
    A local archive or offline rebuild never invents these facts from -AsOf.
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
    Evaluation/generation date (`yyyy-MM-dd`). Defaults to UTC today. It never
    establishes acquisition or verification for a local archive.
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
    [string]$SnapshotPath,

    [Parameter(Mandatory = $false)]
    [string]$VerificationPath,

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
. (Join-Path $repoRoot 'squad-src/.github/skills/squad/scripts/ModelBenchmarkScoring.ps1')
$scoringPolicy = Get-SquadBenchmarkPolicy
if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot 'squad-src/.github/skills/squad/references/model-benchmarks.md'
}
if (-not $CatalogPath) {
    $CatalogPath = Join-Path $repoRoot 'squad-src/.github/skills/squad/references/model-catalog.md'
}

$retrievedDate = $AsOf.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)

$catalogModelSpecs = Get-SquadBenchmarkModelSpec

function Get-CatalogFitMap {
    param([Parameter(Mandatory)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    $classes = @((Get-SquadBenchmarkPolicy).Profiles.Keys)
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
        $val = ConvertTo-SquadBenchmarkDecimal -Value $rawVal
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
        [AllowNull()][AllowEmptyString()][string]$RetrievedHint
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
    $retrieved = ConvertTo-IsoDate -Value $RetrievedHint -Fallback 'unknown'

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
    # This function is used only for the API's explicitly 0..100 aggregate indices.
    (ConvertTo-SquadBenchmarkDecimal -Value ([string]$Value)) / 100
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
        $score = ConvertTo-SquadBenchmarkDecimal -Value $rawScore
        if ($score -lt 0.0 -or $score -gt 1.0) {
            throw "Benchmark row for '$CatalogId' / '$Evaluation' has out-of-range normalized score '$rawScore'; expected 0.0 through 1.0."
        }
        $signature = @(
            $score.ToString('0.############################', [System.Globalization.CultureInfo]::InvariantCulture)
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
    foreach ($row in (Get-SquadBenchmarkRowsFromMarkdown -Content (Get-Content -LiteralPath $Path -Raw))) {
        if ($row.Provenance -eq 'independent') { [void]$keys.Add("$($row.CatalogId)`n$($row.Evaluation)") }
    }
    @($keys)
}

function Get-ExplicitVerificationRowsLocal {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows, [string]$Path)

    $checks = @{}
    if ($Path) {
        $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if ($manifest.schemaVersion -ne 'squad-benchmark-verification-v1') {
            throw 'Unsupported verification manifest schema; expected squad-benchmark-verification-v1.'
        }
        foreach ($check in $manifest.records) {
            if ($check.recordDigest -notmatch '^sha256:[0-9a-f]{64}$' -or $checks.ContainsKey($check.recordDigest)) {
                throw 'Verification records need unique exact recordDigest identities.'
            }
            $checks[$check.recordDigest] = $check
        }
    }
    $used = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($inputRow in $Rows) {
        $row = ConvertTo-SquadBenchmarkRecord -Row $inputRow
        $digest = Get-SquadBenchmarkRecordDigest -Row $row
        if ($checks.ContainsKey($digest)) {
            $check = $checks[$digest]
            foreach ($field in @('ModelVersion', 'Configuration', 'ResultDate', 'Retrieved', 'Verified',
                    'Verification', 'SourceUrl', 'VerificationBasis', 'VerificationReason')) {
                $property = $check.PSObject.Properties[$field]
                if (-not $property -or -not [string]$property.Value) { throw "Verification record $digest has no $field." }
                $row.$field = [string]$property.Value
            }
            [void]$used.Add($digest)
        }
        $row
    }
    if ($used.Count -ne $checks.Count) {
        throw 'Verification manifest contains an unmatched record digest; refusing to attach a check to different evidence.'
    }
}

function Get-ArtificialAnalysisModelRecordsLocal {
    param([Parameter(Mandatory)][string]$Html)

    $flight = [System.Text.StringBuilder]::new()
    foreach ($match in [regex]::Matches($Html, '<script[^>]*>self\.__next_f\.push\((?<payload>.*?)\)</script>', 'Singleline')) {
        $payload = ConvertFrom-Json -InputObject $match.Groups['payload'].Value -Depth 100 -NoEnumerate
        if ($payload.Count -gt 1 -and $payload[1] -is [string]) { [void]$flight.Append($payload[1]) }
    }
    $queue = [System.Collections.Generic.Queue[System.Text.Json.JsonElement]]::new()
    foreach ($line in ($flight.ToString() -split "`n")) {
        if ($line -notmatch '^[0-9a-f]+:(?<json>[\[{].*)$') { continue }
        $json = $Matches['json']
        try {
            $document = [System.Text.Json.JsonDocument]::Parse($json)
            $queue.Enqueue($document.RootElement.Clone())
            $document.Dispose()
        }
        catch [System.Text.Json.JsonException] { continue } # RSC also carries non-JSON transport records.
    }
    while ($queue.Count) {
        $value = $queue.Dequeue()
        if ($value.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
            $slug = [System.Text.Json.JsonElement]::new()
            $name = [System.Text.Json.JsonElement]::new()
            $score = [System.Text.Json.JsonElement]::new()
            if ($value.TryGetProperty('slug', [ref]$slug) -and $value.TryGetProperty('name', [ref]$name) -and
                $value.TryGetProperty('scicode', [ref]$score) -and
                $slug.ValueKind -eq [System.Text.Json.JsonValueKind]::String -and
                $name.ValueKind -eq [System.Text.Json.JsonValueKind]::String -and
                $score.ValueKind -eq [System.Text.Json.JsonValueKind]::Number) {
                [pscustomobject]@{
                    Slug = $slug.GetString(); Name = $name.GetString()
                    Score = ConvertTo-SquadBenchmarkDecimal -Value $score.GetRawText()
                }
            }
            foreach ($property in $value.EnumerateObject()) { $queue.Enqueue($property.Value) }
        }
        elseif ($value.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
            foreach ($item in $value.EnumerateArray()) { $queue.Enqueue($item) }
        }
    }
}

function Get-OnlineSciCodeVerificationLocal {
    param([Parameter(Mandatory)][object[]]$Rows, [Parameter(Mandatory)][object[]]$SciCodeRows)

    $date = [datetime]::UtcNow.ToString('yyyy-MM-dd')
    $methodUri = 'https://artificialanalysis.ai/methodology/intelligence-benchmarking'
    $method = Invoke-WebRequest -Uri $methodUri -UseBasicParsing
    $methodHtml = [string]$method.Content
    $section = [regex]::Match($methodHtml, '(?is)<h4\b[^>]*\bid=["'']scicode["''][^>]*>.*?(?=<h[234]\b|\z)').Value
    $tableRow = [regex]::Match($methodHtml, '(?is)<tr\b[^>]*>(?:(?!</tr>).)*\bSciCode\b(?:(?!</tr>).)*</tr>').Value
    $tableText = [regex]::Replace([System.Net.WebUtility]::HtmlDecode(($tableRow -replace '<[^>]+>', ' ')), '\s+', ' ')
    $methodSupported = $section -match 'dataset v1\.0\.1' -and $section -match '300-second' -and
    $section -match 'scientist-annotated background' -and $section -match 'sub-problem level scoring' -and
    $section -match 'pass@1' -and $tableText -match '288 subproblems \(test set\)\s+3\b'
    $methodHash = Get-SquadBenchmarkTextHash -Text $methodHtml
    $publisherRecords = @{}
    foreach ($row in $Rows) {
        if ($row.Evaluation -ne 'SciCode' -or $row.SourceId -ne 'artificial-analysis') { continue }
        $rowScore = ConvertTo-SquadBenchmarkDecimal -Value $row.NumericScore
        $rawMatches = @($SciCodeRows | Where-Object {
                $_.'Model version' -ceq $row.ModelVersion -and
                (ConvertTo-SquadBenchmarkDecimal -Value ([string]$_.Score)) -eq $rowScore
            })
        $slugs = @($rawMatches | ForEach-Object {
                if ($_.PSObject.Properties['AA model slug']) { [string]$_.'AA model slug' }
            } | Where-Object { $_ } | Sort-Object -Unique)
        $row.Retrieved = $date
        $row.Configuration = if ($methodSupported) { 'aa-scicode-v1.0.1-background-subproblem-pass1-r3-t300-v1' } else { 'unknown' }
        if ($slugs.Count -ne 1 -or $slugs[0] -notmatch '^[a-z0-9-]+$' -or -not $methodSupported) {
            $row.VerificationReason = 'original source model slug or supported SciCode methodology is unknown; retrieval is not verification'
            continue
        }
        $slug = $slugs[0]
        if (-not $publisherRecords.ContainsKey($slug)) {
            $uri = "https://artificialanalysis.ai/models/$slug"
            $page = Invoke-WebRequest -Uri $uri -UseBasicParsing
            $actualUri = $page.BaseResponse.RequestMessage.RequestUri
            if ($actualUri.Host -ne 'artificialanalysis.ai' -or $actualUri.AbsolutePath.TrimEnd('/') -cne "/models/$slug") {
                $row.VerificationReason = 'original model record redirected; exact source identity not verified'
                continue
            }
            $hash = Get-SquadBenchmarkTextHash -Text ([string]$page.Content)
            foreach ($record in (Get-ArtificialAnalysisModelRecordsLocal -Html ([string]$page.Content))) {
                if ($publisherRecords.ContainsKey($record.Slug) -and $publisherRecords[$record.Slug].Score -ne $record.Score) {
                    throw "Conflicting original SciCode records for '$($record.Slug)'; preserving the last-good snapshot."
                }
                $publisherRecords[$record.Slug] = [pscustomobject]@{
                    Score = $record.Score; Name = $record.Name; Uri = $uri; Basis = "$hash+$methodHash"
                }
            }
        }
        if (-not $publisherRecords.ContainsKey($slug) -or $publisherRecords[$slug].Score -ne $rowScore) {
            $row.VerificationReason = 'original publisher does not reproduce this exact model variant and score; result may have been superseded'
            continue
        }
        $record = $publisherRecords[$slug]
        $row.SourceUrl = $record.Uri
        $row.VerificationBasis = $record.Basis
        if ($record.Name -match '(?i)fallback' -or $row.ModelVersion -match '_unknown$') {
            $row.Verification = 'incomparable'
            $row.VerificationReason = "single-model/configuration attribution unproven: $($record.Name); measured $($row.ModelVersion)"
            continue
        }
        $row.Verified = $date
        $row.Verification = 'verified'
        $row.VerificationReason = "original exact model variant/value and versioned SciCode protocol checked; measured configuration $($record.Name), not a host execution claim"
    }
    $Rows
}

function Get-BenchmarkSnapshotContentLocal {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)]$Scoring,
        [Parameter(Mandatory)][string]$SourceTerms,
        [string]$LegacyStamp
    )

    $date = $Scoring.EvaluationDate
    $acquisitions = @($Rows | Where-Object { $_.Retrieved -ne 'unknown' } | ForEach-Object Retrieved | Sort-Object -Descending)
    $latestAcquisition = if ($acquisitions.Count) { $acquisitions[0] } else { 'unknown' }
    $sourceBody = ($SourceTerms -replace "`r`n", "`n").Trim()
    $sourceBody = $sourceBody -replace 'Every source evaluated for `routing=ranked` was checked for methodology transparency, provenance separation \(`independent` versus `self-reported`\), and redistribution licensing before any score entered this repository:', 'Source terms preserve attribution and provenance. Inclusion or active source status is not proof that every result is verified; each score records its own identity, configuration and verification facts.'
    $lines = @(
        '---'
        'name: squad-model-benchmarks'
        'description: "Pinned benchmark evidence with explicit model/configuration identities, separate dates, verification, selected comparison panels and auditable source terms."'
        'license: MIT'
        'metadata:'
        '  authors: "Peter-N91/hve-squad"'
        '  spec_version: "1.0"'
        "  last_updated: `"$date`""
        '---', '', '# Squad Model Benchmarks Knowledge Base', ''
        '**Pinned, reviewed evidence; runtime stays offline.** Generation does not verify or refresh source records. See [model-scoring.md](model-scoring.md) for policy, date semantics, panels, qualification and limitations.'
        ''
        "* **Generated: $date**"
        "* **Retrieved: $latestAcquisition**"
        "* **Evidence Schema: $($scoringPolicy.Schema)**"
        "* **Scoring Policy: $($scoringPolicy.Version)**"
        '* **Content Digest: DIGEST_PLACEHOLDER**'
        '* **Refresh Cadence: Daily source check; verification renewal at 60 days; verification expires after 90 days**'
    )
    if ($LegacyStamp) { $lines += "* **Legacy snapshot stamp: $LegacyStamp**" }
    $lines += @(
        ''
        'Retrieved above is the latest recorded evidence acquisition, not universal verification. Per-row result, acquisition and verification dates are authoritative; unknown dates stay unknown.'
        ''
        $sourceBody
        ''
        '## Assignment Class Evidence Mapping', ''
        "Policy ``$($scoringPolicy.Version)`` selects one common versioned panel by complete independent snapshot-wide coverage, then primary count and declared order, never scores, price or host availability. Every selected primary has equal weight. Secondary coverage is only a confidence tie-break."
        ''
        Get-SquadBenchmarkMappingLine
        ''
        '### Design Decisions on Open Questions', ''
        '1. **Date semantics and legacy handling**: Result, acquisition, verification and generation dates are distinct. Legacy ambiguous Retrieved values are retained as Legacy date, not reinterpreted as genuine verification. Publication or model-release age alone never expires a verified result.'
        '2. **Task proxies**: Reduced implementation evidence is explicitly narrower than the full SciCode/Terminal-Bench panel. Unknown original configurations, mixed/fallback identities and incomparable agent harnesses remain excluded with reasons, not relabeled as model unavailability.'
        '3. **Verification and refresh**: Runtime recalculates the 90-day verification window offline. Only sync acquires sources. An unchanged score is not proof of verification; acquisition/verification facts affect the digest. New assembly or retrieval never renews an old verification.'
        '4. **Coverage continuity**: An automatic refresh refuses loss of independent model/evaluation keys unless a reviewed -AllowCoverageReduction explicitly accepts it. Unverified evidence stays auditable rather than disappearing.'
        '5. **Shared scoring**: Generated views and runtime use the same scorer, evidence and evaluation date. The report always names its panel, evidence level, coverage and date; numerical results from different panels are never pooled.'
        '6. **Semantic duplicate normalization**: Unique normalized records define archive identity. Equivalent decimal spellings count once; conflicting records are rejected before snapshot replacement.'
        ''
        Get-SquadBenchmarkDerivedLine -Scoring $Scoring
        '## Benchmark Scores', ''
        'Each row preserves its numerical source record and provenance. Model/configuration identity, result date, actual acquisition, genuine verification and historical ambiguous dates are separate fields. Unknowns never become fresh by generation.'
        ''
        Get-SquadBenchmarkScoreLine -Rows $Rows
        ''
    )
    $content = $lines -join "`n"
    $digest = Get-SquadBenchmarkDigest -Content $content
    $content.Replace('DIGEST_PLACEHOLDER', $digest)
}

$catalogFit = Get-CatalogFitMap -Path $CatalogPath

if ($SnapshotPath) {
    if ($ArchivePath -or $ArtificialAnalysisJsonPath) {
        throw '-SnapshotPath is an offline rebuild and cannot be combined with archive or API JSON input.'
    }
    $original = Get-Content -LiteralPath $SnapshotPath -Raw
    $dateMatch = [regex]::Match($original, '\*\*Generated:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*')
    if (-not $dateMatch.Success) { $dateMatch = [regex]::Match($original, '\*\*Retrieved:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*') }
    if (-not $dateMatch.Success) { throw 'The pinned snapshot has no generation or legacy snapshot date.' }
    $snapshotDate = [datetime]::ParseExact($dateMatch.Groups['date'].Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    if (-not $PSBoundParameters.ContainsKey('AsOf')) { $AsOf = $snapshotDate }
    if ($snapshotDate.Date -gt $AsOf.Date) { throw 'The pinned snapshot is dated after the evaluation date.' }
    $rows = @(Get-ExplicitVerificationRowsLocal -Rows @(Get-SquadBenchmarkRowsFromMarkdown -Content $original) -Path $VerificationPath)
    $scoring = Get-SquadBenchmarkScore -Rows $rows -AsOf $AsOf -ModelIds @($catalogFit.Keys)
    $terms = [regex]::Match($original, '(?ms)^## Source Terms and Licensing\s*\r?\n.*?(?=^## |\z)').Value.Trim()
    if (-not $terms) { $terms = '## Source Terms and Licensing' + "`n`nExplicit synthetic/local evidence; source terms must accompany publication." }
    $legacyStamp = [regex]::Match($original, '\*\*Legacy snapshot stamp:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*').Groups['date'].Value
    if (-not $legacyStamp -and $original -notmatch '\*\*Generated:') { $legacyStamp = $dateMatch.Groups['date'].Value }
    $content = Get-BenchmarkSnapshotContentLocal -Rows $rows -Scoring $scoring -SourceTerms $terms -LegacyStamp $legacyStamp
    $digest = Get-SquadBenchmarkDigest -Content $content
    $reportedAcquisition = [regex]::Match($content, '\*\*Retrieved:\s*(?<date>[^*]+)\*\*').Groups['date'].Value.Trim()
    $existing = if (Test-Path -LiteralPath $OutputPath -PathType Leaf) { Get-Content -LiteralPath $OutputPath -Raw } else { '' }
    $needsUpdate = $content -cne $existing
    if ($DryRun) { Write-Host "[DryRun] Offline derived-view rebuild (needsUpdate=$needsUpdate)." }
    elseif (($needsUpdate -or $Force) -and $PSCmdlet.ShouldProcess($OutputPath, 'Rebuild pinned benchmark views offline')) {
        Set-Content -LiteralPath $OutputPath -Value $content -Encoding utf8NoBOM -NoNewline
    }
    if ($GitHubOutput -and $env:GITHUB_OUTPUT) {
        @(
            "updated=$($needsUpdate.ToString().ToLowerInvariant())"
            "retrieved=$reportedAcquisition"
            "generated=$($scoring.EvaluationDate)"
            "digest=$digest"
            "models_covered=$($scoring.IndependentModels.Count)"
            "verified_models_covered=$($scoring.FreshIndependentModels.Count)"
            "scores_count=$($rows.Count)"
        ) | Add-Content -LiteralPath $env:GITHUB_OUTPUT
    }
    [pscustomobject]@{
        Updated = $needsUpdate
        OutputPath = $OutputPath
        Retrieved = $reportedAcquisition
        Generated = $scoring.EvaluationDate
        Digest = $digest
        ModelsCovered = $scoring.IndependentModels.Count
        VerifiedModelsCovered = $scoring.FreshIndependentModels.Count
        ScoresCount = $rows.Count
        ScoringPolicy = $scoringPolicy.Version
    }
    return
}

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
                $scoreVal = ConvertTo-SquadBenchmarkDecimal -Value ([string]$matchRow.performance)
                $source = Get-SourceDetailLocal `
                    -RawSource ([string]$matchRow.source) `
                    -DefaultId 'epoch-ai' `
                    -DefaultName 'Epoch AI Benchmarking Hub' `
                    -DefaultVersion $EpochVersion `
                    -VersionHint ([string]$matchRow.benchmark_release_date) `
                    -RetrievedHint ([string]$matchRow.date)
                $entry = [pscustomobject][ordered]@{
                    CatalogId     = $catalogId
                    Evaluation    = $evalSpec.EvalName
                    Category      = $evalSpec.Category
                    Score         = $scoreVal.ToString('0.000#########################', [System.Globalization.CultureInfo]::InvariantCulture)
                    NumericScore  = $scoreVal
                    SourceId      = $source.Id
                    SourceName    = $source.Name
                    SourceVersion = $source.Version
                    ModelVersion  = [string]$matchRow.model_version
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
            $scoreVal = [decimal]$scicodeBest.Score
            $source = Get-SourceDetailLocal `
                -RawSource ([string]$scicodeBest.Row.Source) `
                -DefaultId 'artificial-analysis' `
                -DefaultName 'Artificial Analysis' `
                -DefaultVersion $ArtificialAnalysisVersion `
                -VersionHint $ArtificialAnalysisVersion `
                -RetrievedHint $retrievedDate
            $entry = [pscustomobject][ordered]@{
                CatalogId     = $catalogId
                Evaluation    = 'SciCode'
                Category      = 'coding'
                Score         = $scoreVal.ToString('0.000#########################', [System.Globalization.CultureInfo]::InvariantCulture)
                NumericScore  = $scoreVal
                SourceId      = $source.Id
                SourceName    = $source.Name
                SourceVersion = $source.Version
                ModelVersion  = [string]$scicodeBest.Row.'Model version'
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
            $scoreVal = [decimal]$critptBest.Score
            $source = Get-SourceDetailLocal `
                -RawSource 'Artificial Analysis CritPt' `
                -DefaultId 'artificial-analysis' `
                -DefaultName 'Artificial Analysis' `
                -DefaultVersion $ArtificialAnalysisVersion `
                -VersionHint $ArtificialAnalysisVersion `
                -RetrievedHint $retrievedDate
            $entry = [pscustomobject][ordered]@{
                CatalogId     = $catalogId
                Evaluation    = 'CritPt'
                Category      = 'scientific-reasoning'
                Score         = $scoreVal.ToString('0.000#########################', [System.Globalization.CultureInfo]::InvariantCulture)
                NumericScore  = $scoreVal
                SourceId      = $source.Id
                SourceName    = $source.Name
                SourceVersion = $source.Version
                ModelVersion  = [string]$critptBest.Row.'Model version'
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
            $scoreVal = [decimal]$gdpBest.Score
            $gdpSource = if ($gdpBest.Row.'Source link') { [string]$gdpBest.Row.'Source link' } else { [string]$gdpBest.Row.Source }
            $source = Get-SourceDetailLocal `
                -RawSource $gdpSource `
                -DefaultId 'surge-gdp-pdf' `
                -DefaultName 'Surge AI GDP.pdf' `
                -DefaultVersion $EpochVersion `
                -VersionHint ([string]$gdpBest.Row.'Last updated') `
                -RetrievedHint ([string]$gdpBest.Row.'Last updated')
            $entry = [pscustomobject][ordered]@{
                CatalogId     = $catalogId
                Evaluation    = 'GDP.pdf'
                Category      = 'general-long-doc'
                Score         = $scoreVal.ToString('0.000#########################', [System.Globalization.CultureInfo]::InvariantCulture)
                NumericScore  = $scoreVal
                SourceId      = $source.Id
                SourceName    = $source.Name
                SourceVersion = $source.Version
                ModelVersion  = [string]$gdpBest.Row.'Model version'
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
            $eciNormalized = ((ConvertTo-SquadBenchmarkDecimal -Value ([string]$eciMatch.eci)) - 100) / 100
            if ($eciNormalized -lt 0.0 -or $eciNormalized -gt 1.0) {
                throw "Epoch Capabilities Index for '$catalogId' normalizes to '$eciNormalized'; expected 0.0 through 1.0."
            }
            $source = Get-SourceDetailLocal `
                -RawSource 'https://epoch.ai/benchmarks' `
                -DefaultId 'epoch-ai' `
                -DefaultName 'Epoch AI Benchmarking Hub' `
                -DefaultVersion $EpochVersion `
                -VersionHint $EpochVersion `
                -RetrievedHint $retrievedDate
            $entry = [pscustomobject][ordered]@{
                CatalogId     = $catalogId
                Evaluation    = 'Epoch Capabilities Index'
                Category      = 'general-long-doc'
                Score         = $eciNormalized.ToString('0.000#########################', [System.Globalization.CultureInfo]::InvariantCulture)
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
                -RetrievedHint $retrievedDate
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
                    Score          = $scoreVal.ToString('0.000#########################', [System.Globalization.CultureInfo]::InvariantCulture)
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

    $evidenceRows = @(Get-ExplicitVerificationRowsLocal -Rows $scoreRows.ToArray() -Path $VerificationPath)
    foreach ($row in $evidenceRows) {
        if ($row.Evaluation -in @('SciCode', 'CritPt', 'Epoch Capabilities Index',
                'Artificial Analysis Intelligence Index', 'Artificial Analysis Coding Index', 'Artificial Analysis Agentic Index')) {
            $row.LegacyDate = 'unknown'
        }
        if (-not $ArchivePath -and $row.Provenance -eq 'independent') {
            $row.Retrieved = [datetime]::UtcNow.ToString('yyyy-MM-dd')
        }
    }
    if (-not $ArchivePath -and -not $VerificationPath) {
        $evidenceRows = @(Get-OnlineSciCodeVerificationLocal -Rows $evidenceRows -SciCodeRows $scicodeRows)
        if (-not $Force -and (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
            $priorRows = @{}
            foreach ($prior in (Get-SquadBenchmarkRowsFromMarkdown -Content (Get-Content -LiteralPath $OutputPath -Raw))) {
                $priorRows[(Get-SquadBenchmarkRecordDigest -Row $prior)] = $prior
            }
            foreach ($row in $evidenceRows) {
                $key = Get-SquadBenchmarkRecordDigest -Row $row
                if (-not $priorRows.ContainsKey($key)) { continue }
                $prior = $priorRows[$key]
                if ($row.Verification -ne 'verified' -and $prior.Verification -ceq $row.Verification -and
                    $row.ModelVersion -ceq $prior.ModelVersion -and $row.Configuration -ceq $prior.Configuration -and
                    $row.ResultDate -ceq $prior.ResultDate -and $row.SourceUrl -ceq $prior.SourceUrl -and
                    $prior.Retrieved -ne 'unknown') {
                    $acquired = [datetime]::ParseExact($prior.Retrieved, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
                    if (($AsOf.Date - $acquired.Date).TotalDays -lt $RefreshThresholdDays) { $row.Retrieved = $prior.Retrieved }
                }
                if ($prior.Verification -ne 'verified' -or $row.Verification -ne 'verified' -or
                    $row.ModelVersion -cne $prior.ModelVersion -or $row.Configuration -cne $prior.Configuration -or
                    $row.ResultDate -cne $prior.ResultDate -or $prior.Verified -eq 'unknown') { continue }
                $checked = [datetime]::ParseExact($prior.Verified, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
                if (($AsOf.Date - $checked.Date).TotalDays -ge $RefreshThresholdDays) { continue }
                foreach ($field in @('Retrieved', 'Verified', 'VerificationBasis', 'SourceUrl', 'VerificationReason')) {
                    $row.$field = $prior.$field
                }
            }
        }
    }
    $scoring = Get-SquadBenchmarkScore -Rows $evidenceRows -AsOf $AsOf -ModelIds @($catalogFit.Keys)
    $modelsCovered = $scoring.IndependentModels.Count

    $independentScoreCount = @($scoreRows | Where-Object { $_.Provenance -eq 'independent' }).Count
    if ($independentScoreCount -eq 0 -or $modelsCovered -eq 0) {
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

    if ($scoring.FreshIndependentModels.Count -eq 0 -and (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        $priorScoring = Get-SquadBenchmarkScore -Rows @(Get-SquadBenchmarkRowsFromMarkdown -Content (Get-Content -LiteralPath $OutputPath -Raw)) -AsOf $AsOf
        if ($priorScoring.FreshIndependentModels.Count -gt 0 -and -not $AllowCoverageReduction) {
            throw 'Refresh lost all verified evidence; preserving the last-good snapshot. Local archives need explicit record-bound verification.'
        }
    }

    # Source attribution remains separate from per-record eligibility.
    $sourcesTableLines = @(
        '| Source ID | Source name | Version | Retrieved | License | Redistribution | Status | URL |'
        '| --- | --- | --- | --- | --- | --- | --- | --- |'
    )
    foreach ($group in ($scoreRows | Group-Object SourceId | Sort-Object Name)) {
        $sourceNames = @($group.Group | ForEach-Object { $_.SourceName } | Where-Object { $_ } | Sort-Object -Unique)
        $versions = @($group.Group | ForEach-Object { $_.SourceVersion } | Where-Object { $_ } | Sort-Object -Unique)
        $licenses = @($group.Group | ForEach-Object { $_.License } | Where-Object { $_ } | Sort-Object -Unique)
        $redistributions = @($group.Group | ForEach-Object { $_.Redistribution } | Where-Object { $_ } | Sort-Object -Unique)
        $statuses = @($group.Group | ForEach-Object { $_.Status } | Where-Object { $_ } | Sort-Object -Unique)
        $sourceUrls = @($group.Group | ForEach-Object { $_.SourceUrl } | Where-Object { $_ } | Sort-Object -Unique)
        $sourceUrlCell = if ($sourceUrls.Count -gt 0) { @($sourceUrls | ForEach-Object { "<$_>" }) -join ', ' } else { '—' }
        $sourceAcquisitions = @($evidenceRows | Where-Object { $_.SourceId -eq $group.Name -and $_.Retrieved -ne 'unknown' } |
                ForEach-Object Retrieved | Sort-Object -Descending)
        $sourceAcquisition = if ($sourceAcquisitions.Count) { $sourceAcquisitions[0] } else { 'unknown' }
        $sourcesTableLines += "| ``$($group.Name)`` | $($sourceNames -join '; ') | ``$($versions -join ', ')`` | ``$sourceAcquisition`` | $($licenses -join '; ') | $($redistributions -join '; ') | $($statuses -join '; ') | $sourceUrlCell |"
    }
    $sourcesTableLines += @(
        '| `llm-stats` | LLM Stats (ZeroEval) | `2026-10` | `unknown` | Commercial contract required for dataset redistribution | prohibited-on-free-tier | excluded | <https://llm-stats.com/developer> |'
        '| `lmarena` | Arena (formerly LMArena) | `2026-10` | `unknown` | CC-BY-4.0 / ToS | excluded-by-methodology | excluded | <https://arena.ai> |'
    )

    $sourceTerms = @(
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
    )
    $content = Get-BenchmarkSnapshotContentLocal -Rows $evidenceRows -Scoring $scoring -SourceTerms ($sourceTerms -join "`n")
    $digest = Get-SquadBenchmarkDigest -Content $content
    $reportedAcquisition = [regex]::Match($content, '\*\*Retrieved:\s*(?<date>[^*]+)\*\*').Groups['date'].Value.Trim()
    $needsUpdate = $true
    if (-not $Force -and (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        $existingRaw = Get-Content -LiteralPath $OutputPath -Raw
        $existingDigest = [regex]::Match($existingRaw, '\*\*Content Digest:\s*(?<digest>sha256:[0-9a-f]{64})\*\*').Groups['digest'].Value
        $existingDate = [regex]::Match($existingRaw, '\*\*Generated:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*').Groups['date'].Value
        if ($existingDigest -eq $digest -and $existingDate -and
            ($AsOf.Date - [datetime]::ParseExact($existingDate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)).TotalDays -lt $RefreshThresholdDays) {
            $needsUpdate = $false
            Write-Host "Benchmark evidence digest ($digest) unchanged; verification facts retained, not renewed by assembly." -ForegroundColor Green
        }
    }

    if ($DryRun) {
        Write-Host "[DryRun] Would write $($scoreRows.Count) benchmark score rows across $modelsCovered independently evaluated models (needsUpdate=$needsUpdate)." -ForegroundColor Cyan
    }
    elseif ($needsUpdate -or $Force) {
        if ($PSCmdlet.ShouldProcess($OutputPath, 'Write model-benchmarks.md knowledge base')) {
            Set-Content -LiteralPath $OutputPath -Value $content -Encoding utf8NoBOM -NoNewline
            Write-Host "Wrote $OutputPath ($($scoreRows.Count) score rows, $modelsCovered independently evaluated models)." -ForegroundColor Green
        }
    }

    if ($GitHubOutput -and $env:GITHUB_OUTPUT) {
        @(
            "updated=$($needsUpdate.ToString().ToLowerInvariant())"
            "retrieved=$reportedAcquisition"
            "generated=$($scoring.EvaluationDate)"
            "digest=$digest"
            "models_covered=$modelsCovered"
            "verified_models_covered=$($scoring.FreshIndependentModels.Count)"
            "scores_count=$($scoreRows.Count)"
        ) | Add-Content -LiteralPath $env:GITHUB_OUTPUT
    }

    [pscustomobject][ordered]@{
        Updated       = $needsUpdate
        OutputPath    = $OutputPath
        Retrieved     = $reportedAcquisition
        Generated     = $scoring.EvaluationDate
        Digest        = $digest
        ModelsCovered = $modelsCovered
        VerifiedModelsCovered = $scoring.FreshIndependentModels.Count
        ScoresCount   = $scoreRows.Count
        ScoringPolicy = $scoringPolicy.Version
    }
}
finally {
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
