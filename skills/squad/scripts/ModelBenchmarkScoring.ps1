# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

function Get-SquadBenchmarkPolicy {
    [CmdletBinding()]
    param()

    $profiles = [ordered]@{
        research = @{
            Primary = @('GDP.pdf', 'GPQA diamond')
            Secondary = @('DeepResearch Bench', 'SimpleQA Verified', 'CritPt', 'HLE')
        }
        planning = @{
            Primary = @('FrontierMath-Tiers-1-3-v2', 'GPQA diamond')
            Secondary = @('FrontierMath-Tier-4-v2', 'ProofBench', 'OTIS Mock AIME')
        }
        implementation = @{
            Primary = @('SciCode', 'Terminal-Bench')
            Secondary = @('SWE-Bench verified', 'FrontierCode', 'DeepSWE', 'APEX-Agents', 'FrontierSWE', 'OSWorld 2.0')
        }
        review = @{
            Primary = @('SciCode', 'GPQA diamond')
            Secondary = @('SWE-Bench verified', 'Terminal-Bench', 'CritPt', 'ProofBench')
        }
        council = @{
            Primary = @('GPQA diamond', 'HLE')
            Secondary = @('GDP.pdf', 'FrontierMath-Tiers-1-3-v2', 'CritPt')
        }
        intake = @{
            Primary = @('GDP.pdf', 'GPQA diamond')
            Secondary = @('SimpleQA Verified', 'APEX-Agents')
        }
        bookkeeping = @{
            Primary = @('SciCode', 'GPQA diamond')
            Secondary = @('SimpleQA Verified')
        }
    }
    foreach ($class in $profiles.Keys) {
        $profiles[$class].Panels = @(
            [pscustomobject]@{
                Id = "$class-full"; Version = '1'; Level = 'full'
                Primary = $profiles[$class].Primary
                MinimumPercentile = [decimal]0.50
                Qualification = "$class-full-midpoint-v1"
            }
        )
    }
    $profiles.implementation.Panels += [pscustomobject]@{
        Id = 'implementation-scicode'; Version = '1'; Level = 'reduced'
        Primary = @('SciCode')
        MinimumPercentile = [decimal]0.75
        Qualification = 'implementation-scicode-upper-quartile-v1'
    }
    [pscustomobject]@{
        Version = 'squad-capability-v3'
        Schema = 'squad-benchmark-evidence-v3'
        StaleAfterDays = 90
        MinimumReferenceCount = 2
        Profiles = $profiles
        SourceHosts = @{
            'epoch-ai' = 'epoch.ai'
            'artificial-analysis' = 'artificialanalysis.ai'
            'terminal-bench' = 'tbench.ai'
            'cognition-frontiercode' = 'cognition.com'
            'surge-gdp-pdf' = 'surgehq.ai'
            'deepswe-datacurve-ai' = 'deepswe.datacurve.ai'
            'evals-futuresearch-ai' = 'evals.futuresearch.ai'
            'frontierswe-com' = 'frontierswe.com'
            'osworld-v2-xlang-ai' = 'osworld-v2.xlang.ai'
            'vals-ai' = 'vals.ai'
        }
    }
}

function Get-SquadBenchmarkModelSpec {
    [CmdletBinding()]
    param()

    [ordered]@{
        'gpt-5.6-sol' = @{ Display = 'GPT-5.6 Sol'; VersionRegex = '^gpt-5\.6-sol(_|$)' }
        'gpt-6.1-sol' = @{ Display = 'GPT-6.1 Sol'; VersionRegex = '^gpt-6\.1-sol(_|$)' }
        'gpt-6-sol' = @{ Display = 'GPT-6 Sol'; VersionRegex = '^gpt-6-sol(_|$)' }
        'gpt-6-astra' = @{ Display = 'GPT-6 Astra'; VersionRegex = '^gpt-6-astra(_|$)' }
        'gpt-5.5' = @{ Display = 'GPT-5.5'; VersionRegex = '^gpt-5\.5(_|$)' }
        'gpt-5.4' = @{ Display = 'GPT-5.4'; VersionRegex = '^gpt-5\.4(-2026-03-05)?(_|$)' }
        'gpt-5.6-terra' = @{ Display = 'GPT-5.6 Terra'; VersionRegex = '^gpt-5\.6-terra(_|$)' }
        'gpt-5.3-codex' = @{ Display = 'GPT-5.3 Codex'; VersionRegex = '^gpt-5\.3-codex(_|$)' }
        'gpt-5.4-mini' = @{ Display = 'GPT-5.4 Mini'; VersionRegex = '^gpt-5\.4-mini(-2026-03-17)?(_|$)' }
        'gpt-5-mini' = @{ Display = 'GPT-5 mini'; VersionRegex = '^gpt-5-mini(-2025-08-07)?(_|$)' }
        'gpt-5.4-nano' = @{ Display = 'GPT-5.4 Nano'; VersionRegex = '^gpt-5\.4-nano(-2026-03-17)?(_|$)' }
        'gpt-6-luna' = @{ Display = 'GPT-6 Luna'; VersionRegex = '^gpt-6-luna(_|$)' }
        'gpt-5.6-luna' = @{ Display = 'GPT-5.6 Luna'; VersionRegex = '^gpt-5\.6-luna(_|$)' }
        'claude-opus-5.5' = @{ Display = 'Claude Opus 5.5'; VersionRegex = '^claude-opus-5-5(_|$)' }
        'claude-opus-5' = @{ Display = 'Claude Opus 5'; VersionRegex = '^claude-opus-5(_|$)' }
        'claude-opus-4.8' = @{ Display = 'Claude Opus 4.8'; VersionRegex = '^claude-opus-4-8(_|$)' }
        'claude-opus-4.7' = @{ Display = 'Claude Opus 4.7'; VersionRegex = '^claude-opus-4-7(_|$)' }
        'claude-opus-4.8-fast' = @{ Display = 'Claude Opus 4.8'; VersionRegex = '^claude-opus-4-8(_|$)'; AliasOf = 'claude-opus-4.8' }
        'claude-fable-5.1' = @{ Display = 'Claude Fable 5.1'; VersionRegex = '^claude-fable-5-1(_|$)' }
        'claude-fable-5' = @{ Display = 'Claude Fable 5'; VersionRegex = '^claude-fable-5(_|$)' }
        'claude-sonnet-5.5' = @{ Display = 'Claude Sonnet 5.5'; VersionRegex = '^claude-sonnet-5-5(_|$)' }
        'claude-sonnet-5' = @{ Display = 'Claude Sonnet 5'; VersionRegex = '^claude-sonnet-5(_|$)' }
        'claude-sonnet-4.6' = @{ Display = 'Claude Sonnet 4.6'; VersionRegex = '^claude-sonnet-4-6(_|$)' }
        'claude-sonnet-4' = @{ Display = 'Claude Sonnet 4'; VersionRegex = '^claude-sonnet-4-20250514(_|$)' }
        'claude-haiku-5.5' = @{ Display = 'Claude Haiku 5.5'; VersionRegex = '^claude-haiku-5-5(_|$)' }
        'claude-haiku-4.5' = @{ Display = 'Claude Haiku 4.5'; VersionRegex = '^claude-haiku-4-5(-20251001)?(_|$)' }
        'gemini-3.8-flash' = @{ Display = 'Gemini 3.8 Flash'; VersionRegex = '^gemini-3\.8-flash(_|$)' }
        'gemini-3.7-flash' = @{ Display = 'Gemini 3.7 Flash'; VersionRegex = '^gemini-3\.7-flash(_|$)' }
        'gemini-3.6-flash' = @{ Display = 'Gemini 3.6 Flash'; VersionRegex = '^gemini-3\.6-flash(_|$)' }
        'gemini-3.5-flash' = @{ Display = 'Gemini 3.5 Flash'; VersionRegex = '^gemini-3\.5-flash(_|$)' }
        'grok-4.7' = @{ Display = 'Grok 4.7'; VersionRegex = '^grok-4\.7(_|$)' }
        'grok-4.6' = @{ Display = 'Grok 4.6'; VersionRegex = '^grok-4\.6(_|$)' }
        'grok-4.5' = @{ Display = 'Grok 4.5'; VersionRegex = '^grok-4\.5(_|$)' }
        'kimi-k3' = @{ Display = 'Kimi K3'; VersionRegex = '^kimi-k3(_|$)' }
        'kimi-k2.7-code' = @{ Display = 'Kimi K2.7 Code'; VersionRegex = '^kimi-k2\.7-code(_|$)' }
        'mai-code-1.1-flash' = @{ Display = 'MAI-Code-1.1-Flash'; VersionRegex = '^mai-code-1\.1-flash(_|$)' }
        'hydrafusion-max' = @{ Display = 'GPT-6.1 Sol'; VersionRegex = '^gpt-6\.1-sol(_|$)'; AliasOf = 'gpt-6.1-sol' }
    }
}

function ConvertTo-SquadBenchmarkRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Row)

    $structured = $null -ne $Row.PSObject.Properties['Verification']
    $record = [ordered]@{}
    foreach ($field in @('CatalogId', 'Evaluation', 'Category', 'NumericScore', 'SourceId', 'SourceVersion', 'Provenance')) {
        $property = $Row.PSObject.Properties[$field]
        $record[$field] = if ($property) { [string]$property.Value } else { '' }
    }
    if ($Row.PSObject.Properties['Score'] -and $Row.Score -is [string]) {
        $record.NumericScore = $Row.Score
    }
    foreach ($field in @('ModelVersion', 'Configuration', 'ResultDate', 'Retrieved', 'Verified',
            'Verification', 'SourceUrl', 'VerificationBasis', 'VerificationReason', 'LegacyDate')) {
        $property = $Row.PSObject.Properties[$field]
        $record[$field] = if ($property -and [string]$property.Value) { [string]$property.Value } else { 'unknown' }
    }
    if (-not $structured) {
        $record.LegacyDate = $record.Retrieved
        $record.Retrieved = 'unknown'
        $record.Verified = 'unknown'
        $record.Verification = 'unverified'
        $record.VerificationReason = 'legacy ambiguous Retrieved value; exact identity/configuration and genuine verification were not recorded'
    }
    [pscustomobject]$record
}

function Get-SquadBenchmarkRowsFromMarkdown {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Content)

    $section = [regex]::Match($Content, '(?ms)^## Benchmark Scores\s*\r?\n(?<body>.*?)(?=^## |\z)')
    if (-not $section.Success) { throw "No 'Benchmark Scores' table found." }
    $legacyHeader = @('Catalog ID', 'Evaluation', 'Category', 'Score', 'Source ID', 'Source version', 'Retrieved', 'Provenance')
    $header = $null
    foreach ($line in ($section.Groups['body'].Value -split '\r?\n')) {
        if ($line -notmatch '^\s*\|' -or $line -match '^\s*\|[\s\-:|]+\|\s*$') { continue }
        $cells = @($line.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim().Trim('`').Trim() })
        if (-not $header) {
            $header = $cells
            if (($header -join '|') -cne ($legacyHeader -join '|') -and
                ($header -join '|') -cne ((Get-SquadBenchmarkColumn).Header -join '|')) {
                throw 'Invalid benchmark score header; expected the explicit evidence schema or the legacy eight columns.'
            }
            continue
        }
        if ($cells.Count -ne $header.Count) { throw "Invalid benchmark score row: expected $($header.Count) columns." }
        if ($header.Count -eq 8) {
            ConvertTo-SquadBenchmarkRecord -Row ([pscustomobject]@{
                    CatalogId = $cells[0]; Evaluation = $cells[1]; Category = $cells[2]
                    NumericScore = $cells[3]; SourceId = $cells[4]; SourceVersion = $cells[5]
                    Retrieved = $cells[6]; Provenance = $cells[7]
                })
        }
        else {
            $record = [ordered]@{}
            $columns = @(Get-SquadBenchmarkColumn)
            for ($i = 0; $i -lt $columns.Count; $i++) { $record[$columns[$i].Property] = $cells[$i] }
            ConvertTo-SquadBenchmarkRecord -Row ([pscustomobject]$record)
        }
    }
    if (-not $header) { throw "No 'Benchmark Scores' table found." }
}

function Get-SquadBenchmarkColumn {
    [CmdletBinding()]
    param()

    foreach ($pair in @(
            @('Catalog ID', 'CatalogId'), @('Evaluation', 'Evaluation'), @('Category', 'Category'),
            @('Score', 'NumericScore'), @('Source ID', 'SourceId'), @('Source version', 'SourceVersion'),
            @('Model version', 'ModelVersion'), @('Configuration', 'Configuration'), @('Result date', 'ResultDate'),
            @('Retrieved', 'Retrieved'), @('Verified', 'Verified'), @('Verification', 'Verification'),
            @('Source URL', 'SourceUrl'), @('Verification basis', 'VerificationBasis'),
            @('Verification reason', 'VerificationReason'), @('Legacy date', 'LegacyDate'), @('Provenance', 'Provenance')
        )) {
        [pscustomobject]@{ Header = $pair[0]; Property = $pair[1] }
    }
}

function Get-SquadBenchmarkScoreLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows)

    $columns = @(Get-SquadBenchmarkColumn)
    '| ' + ($columns.Header -join ' | ') + ' |'
    '| ' + (@($columns | ForEach-Object { if ($_.Property -eq 'NumericScore') { '---:' } else { '---' } }) -join ' | ') + ' |'
    foreach ($inputRow in $Rows) {
        $row = ConvertTo-SquadBenchmarkRecord -Row $inputRow
        $cells = foreach ($column in $columns) {
            $value = [string]$row.($column.Property)
            if ($value -match '[|\r\n]') { throw "Benchmark field '$($column.Header)' contains a table delimiter or newline." }
            if ($column.Property -in @('NumericScore', 'Evaluation')) { $value }
            else { "``$value``" }
        }
        '| ' + ($cells -join ' | ') + ' |'
    }
}

function Get-SquadBenchmarkTextHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
        'sha256:' + (-join ($hash | ForEach-Object { $_.ToString('x2') }))
    }
    finally { $sha.Dispose() }
}

function ConvertTo-SquadBenchmarkDecimal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value)

    [decimal]::Parse($Value, [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-SquadBenchmarkRecordDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Row)

    $record = ConvertTo-SquadBenchmarkRecord -Row $Row
    $score = (ConvertTo-SquadBenchmarkDecimal -Value $record.NumericScore).ToString('0.############################', [System.Globalization.CultureInfo]::InvariantCulture)
    Get-SquadBenchmarkTextHash -Text (@($record.CatalogId, $record.Evaluation, $record.Category, $score,
            $record.SourceId, $record.SourceVersion, $record.Provenance) -join "`n")
}

function Get-SquadBenchmarkDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Content)

    $policy = Get-SquadBenchmarkPolicy
    $records = [System.Collections.Generic.List[string]]::new()
    $records.Add("$($policy.Version)|$($policy.Schema)|$($policy.MinimumReferenceCount)|$($policy.StaleAfterDays)")
    $modelSpecs = Get-SquadBenchmarkModelSpec
    foreach ($id in $modelSpecs.Keys) {
        $alias = if ($modelSpecs[$id].Contains('AliasOf')) { $modelSpecs[$id].AliasOf } else { '' }
        $records.Add("model-identity|$id|$($modelSpecs[$id].VersionRegex)|$alias")
    }
    foreach ($id in $policy.SourceHosts.Keys) { $records.Add("source-authority|$id|$($policy.SourceHosts[$id])") }
    foreach ($line in (Get-SquadBenchmarkMappingLine)) { $records.Add($line) }
    $inSources = $false
    foreach ($line in ($Content -split '\r?\n')) {
        if ($line -notmatch '^\s*\|') { $inSources = $false; continue }
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') { continue }
        $cells = @($line.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim().Trim('`').Trim() })
        if ($cells[0] -eq 'Source ID') { $inSources = $true; continue }
        if ($inSources -and $cells.Count -eq 8) {
            $records.Add('source|' + ($cells[0, 1, 2, 4, 5, 6, 7] -join '|'))
        }
    }
    foreach ($row in (Get-SquadBenchmarkRowsFromMarkdown -Content $Content)) {
        $values = @(
            Get-SquadBenchmarkRecordDigest -Row $row
            foreach ($field in @('ModelVersion', 'Configuration', 'ResultDate', 'Retrieved', 'Verified', 'Verification',
                    'SourceUrl', 'VerificationBasis', 'VerificationReason', 'LegacyDate')) { $row.$field }
        )
        $records.Add('evidence|' + ($values -join '|'))
    }
    $canonical = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($record in $records) { [void]$canonical.Add($record) }
    Get-SquadBenchmarkTextHash -Text (@($canonical) -join "`n")
}

function Get-SquadBenchmarkDate {
    [CmdletBinding()]
    param([string]$Value, [Parameter(Mandatory)][string]$Field, [Parameter(Mandatory)][string]$Identity, [datetime]$AsOf)

    if (-not $Value -or $Value -eq 'unknown') { return $null }
    $date = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None, [ref]$date)) {
        throw "Invalid benchmark score $Field date '$Value' for $Identity."
    }
    if ($date.Date -gt $AsOf.Date) { throw "Benchmark score $Field date '$Value' for $Identity is after routing date '$($AsOf.ToString('yyyy-MM-dd'))'." }
    $date
}

function Get-SquadBenchmarkScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][datetime]$AsOf,
        [string[]]$ModelIds = @()
    )

    $policy = Get-SquadBenchmarkPolicy
    $modelSpecs = Get-SquadBenchmarkModelSpec
    $unique = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $byModel = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($id in $ModelIds) { $byModel[$id] = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal) }
    $usableByEvaluation = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($inputRow in $Rows) {
        $row = ConvertTo-SquadBenchmarkRecord -Row $inputRow
        $id = $row.CatalogId
        $evaluation = $row.Evaluation
        $score = [decimal]0
        $validScore = [decimal]::TryParse($row.NumericScore, [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$score)
        if ($id -cnotmatch '^[a-z0-9]+(?:[.-][a-z0-9]+)*$' -or -not $evaluation -or -not $validScore -or -not $row.SourceId -or
            -not $row.SourceVersion -or $row.Provenance -cnotin @('independent', 'self-reported')) {
            throw "Invalid benchmark score row for '$id' / '$evaluation': source, version, score, and Provenance are required."
        }
        if ($score -lt 0 -or $score -gt 1) { throw "Invalid benchmark score '$score' for '$id' / '$evaluation'; normalized scores must be between 0.0 and 1.0." }
        if ($row.Verification -cnotin @('verified', 'unverified', 'incomparable', 'invalidated', 'superseded')) {
            throw "Invalid benchmark Verification '$($row.Verification)' for '$id' / '$evaluation'."
        }
        $dates = @{}
        foreach ($field in @('ResultDate', 'Retrieved', 'Verified', 'LegacyDate')) {
            $dates[$field] = Get-SquadBenchmarkDate -Value $row.$field -Field $field -Identity "'$id' / '$evaluation'" -AsOf $AsOf
        }
        if (($dates.ResultDate -and $dates.Retrieved -and $dates.ResultDate -gt $dates.Retrieved) -or
            ($dates.ResultDate -and $dates.Verified -and $dates.ResultDate -gt $dates.Verified)) {
            throw "Invalid benchmark evidence date chronology for '$id' / '$evaluation'."
        }
        $signatureValues = @(
            Get-SquadBenchmarkRecordDigest -Row $row
            foreach ($field in @('ModelVersion', 'Configuration', 'ResultDate', 'Retrieved', 'Verified', 'Verification',
                    'SourceUrl', 'VerificationBasis', 'VerificationReason', 'LegacyDate')) { $row.$field }
        )
        $signature = $signatureValues -join '|'
        $key = "$id`n$evaluation"
        if ($unique.ContainsKey($key)) {
            if ($unique[$key].Signature -cne $signature) { throw "Conflicting duplicate benchmark score rows for '$id' / '$evaluation'." }
            continue
        }
        $uri = $null
        $sourceValid = $policy.SourceHosts.ContainsKey($row.SourceId) -and
        [uri]::TryCreate($row.SourceUrl, [System.UriKind]::Absolute, [ref]$uri) -and
        $uri.Scheme -in @('http', 'https') -and
        ($uri.Host -eq $policy.SourceHosts[$row.SourceId] -or $uri.Host.EndsWith('.' + $policy.SourceHosts[$row.SourceId], [System.StringComparison]::OrdinalIgnoreCase))
        $identityValid = $modelSpecs.Contains($id) -and -not $modelSpecs[$id].Contains('AliasOf') -and
        $row.ModelVersion -cmatch $modelSpecs[$id].VersionRegex
        $status = 'verified'
        $reason = 'exact model, original source and evaluation configuration genuinely verified within the cache window'
        if ($row.Provenance -ne 'independent') {
            $status = 'unverified'; $reason = 'self-reported evidence is informational, not independent comparison evidence'
        }
        elseif ($row.Verification -in @('invalidated', 'superseded', 'incomparable')) {
            $status = $row.Verification; $reason = $row.VerificationReason
        }
        elseif ($row.ModelVersion -ne 'unknown' -and -not $identityValid) {
            $status = 'incomparable'; $reason = "identity mismatch: measured '$($row.ModelVersion)' is not exact catalog model '$id'"
        }
        elseif ($row.Verification -ne 'verified' -or -not $dates.Verified -or -not $dates.Retrieved -or
            -not $identityValid -or -not $sourceValid -or $row.Configuration -eq 'unknown' -or
            $row.ModelVersion -match '_unknown$' -or $row.VerificationBasis -notmatch '^sha256:[0-9a-f]{64}(?:\+sha256:[0-9a-f]{64})*$') {
            $status = 'unverified'
            $reason = "identity, original source, known configuration, acquisition and record-bound verification required; $($row.VerificationReason)"
        }
        elseif (($AsOf.Date - $dates.Verified.Date).TotalDays -gt $policy.StaleAfterDays) {
            $status = 'verification-expired'
            $reason = "verification/cache expired: last checked $($row.Verified), more than $($policy.StaleAfterDays) days before $($AsOf.ToString('yyyy-MM-dd'))"
        }
        elseif ($dates.ResultDate -and ($AsOf.Date - $dates.ResultDate.Date).TotalDays -gt $policy.StaleAfterDays) {
            $status = 'older-valid-result'; $reason = 'older measurement remains valid: exact identity/configuration and original source recently verified'
        }
        $entry = [pscustomobject]@{
            CatalogId = $id; Evaluation = $evaluation; Score = $score
            SourceId = $row.SourceId; SourceVersion = $row.SourceVersion
            ModelVersion = $row.ModelVersion; Configuration = $row.Configuration
            ResultDate = $row.ResultDate; Retrieved = $row.Retrieved; Verified = $row.Verified
            Verification = $row.Verification; VerificationBasis = $row.VerificationBasis
            SourceUrl = $row.SourceUrl; LegacyDate = $row.LegacyDate; Provenance = $row.Provenance
            Status = $status; Reason = $reason; Usable = $status -in @('verified', 'older-valid-result')
            Signature = $signature
        }
        $unique.Add($key, $entry)
        if (-not $byModel.ContainsKey($id)) { $byModel[$id] = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal) }
        $byModel[$id][$evaluation] = $entry
        if ($entry.Usable) {
            if (-not $usableByEvaluation.ContainsKey($evaluation)) { $usableByEvaluation[$evaluation] = [System.Collections.Generic.List[object]]::new() }
            $usableByEvaluation[$evaluation].Add($entry)
        }
    }

    $references = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($evaluation in $usableByEvaluation.Keys) {
        $peers = @($usableByEvaluation[$evaluation])
        $identities = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($peer in $peers) {
            [void]$identities.Add((ConvertTo-Json -InputObject @($peer.SourceId, $peer.SourceVersion, $peer.Configuration) -Compress))
        }
        $status = if ($identities.Count -ne 1) { 'incomparable' }
        elseif ($peers.Count -lt $policy.MinimumReferenceCount) { 'insufficient-coverage' } else { 'sufficient' }
        $basis = if ($identities.Count -eq 1) { "$($peers[0].SourceId)@$($peers[0].SourceVersion)@$($peers[0].Configuration)" }
        else { $identities -join ', ' }
        $references[$evaluation] = [pscustomobject]@{ Status = $status; Identity = $basis; Count = $peers.Count; Rows = $peers }
    }

    $panels = @{}
    foreach ($class in $policy.Profiles.Keys) {
        $options = @(
            foreach ($panel in $policy.Profiles[$class].Panels) {
                $completeIds = @(
                    foreach ($id in $byModel.Keys) {
                        $missing = @($panel.Primary | Where-Object {
                                -not $byModel[$id].ContainsKey($_) -or -not $byModel[$id][$_].Usable -or
                                -not $references.ContainsKey($_) -or $references[$_].Status -ne 'sufficient'
                            })
                        if ($missing.Count -eq 0) { $id }
                    }
                )
                [pscustomobject]@{
                    id = $panel.Id; version = $panel.Version; level = $panel.Level
                    primary = $panel.Primary; populationCount = $completeIds.Count
                    minimumPercentile = $panel.MinimumPercentile; qualificationRule = $panel.Qualification
                }
            }
        )
        $selected = @($options | Sort-Object -Stable @{ Expression = 'populationCount'; Descending = $true },
            @{ Expression = { $_.primary.Count }; Descending = $true })[0]
        $panels[$class] = [pscustomobject][ordered]@{
            id = $selected.id; version = $selected.version; evidenceLevel = $selected.level
            primary = $selected.primary; weight = [decimal]1 / $selected.primary.Count
            populationCount = $selected.populationCount
            defensible = $selected.populationCount -ge $policy.MinimumReferenceCount
            minimumPercentile = $selected.minimumPercentile; qualificationRule = $selected.qualificationRule
            options = $options
            selectionRule = 'greatest complete independent snapshot-wide coverage; then more primaries; then declared order; never host availability, scores or prices'
            limitation = if ($selected.level -eq 'reduced') { 'reduced evidence: scientific-Python proxy only; not equivalent to the full implementation profile or universal model superiority' }
            else { 'declared task proxies, not a validated guarantee of assignment success' }
        }
    }

    $models = @{}
    foreach ($id in @($byModel.Keys | Sort-Object -CaseSensitive)) {
        $evaluations = $byModel[$id]
        $models[$id] = @{}
        foreach ($class in $policy.Profiles.Keys) {
            $assignmentProfile = $policy.Profiles[$class]
            $panel = $panels[$class]
            $primary = [System.Collections.Generic.List[object]]::new()
            $diagnostics = @(
                foreach ($evaluation in @(@($assignmentProfile.Primary) + @($panel.primary) | Select-Object -Unique)) {
                    $row = if ($evaluations.ContainsKey($evaluation)) { $evaluations[$evaluation] } else { $null }
                    $reference = if ($references.ContainsKey($evaluation)) { $references[$evaluation] } else { $null }
                    $status = if ($row) { $row.Status } else { 'missing-evaluation' }
                    $reason = if ($row) { $row.Reason } else { "missing evaluation: no result for exact model '$id' and '$evaluation'" }
                    $percentile = $null
                    $usable = $row -and $row.Usable -and $reference -and $reference.Status -eq 'sufficient'
                    if ($row -and $row.Usable -and $reference -and $reference.Status -ne 'sufficient') {
                        $status = $reference.Status
                        $reason = if ($status -eq 'incomparable') { 'incomparable source/version/evaluation configuration cohorts; never pooled' }
                        else { "insufficient coverage: fewer than $($policy.MinimumReferenceCount) comparable independent models" }
                    }
                    if ($usable) {
                        $lower = @($reference.Rows | Where-Object Score -lt $row.Score).Count
                        $equal = @($reference.Rows | Where-Object Score -eq $row.Score).Count
                        $percentile = ([decimal]$lower + ([decimal]($equal - 1) / 2)) / ($reference.Count - 1)
                    }
                    $detail = [pscustomobject][ordered]@{
                        evaluation = $evaluation; status = $status; reason = $reason
                        selectedPrimary = $evaluation -in $panel.primary
                        fullProfilePrimary = $evaluation -in $assignmentProfile.Primary
                        score = if ($row) { $row.Score } else { $null }; percentile = $percentile
                        weight = if ($evaluation -in $panel.primary) { $panel.weight } else { [decimal]0 }
                        referenceCount = if ($reference) { $reference.Count } else { 0 }
                        basis = if ($reference) { $reference.Identity } else { $null }
                        modelVersion = if ($row) { $row.ModelVersion } else { 'unknown' }
                        configuration = if ($row) { $row.Configuration } else { 'unknown' }
                        sourceId = if ($row) { $row.SourceId } else { 'unknown' }
                        sourceVersion = if ($row) { $row.SourceVersion } else { 'unknown' }
                        provenance = if ($row) { $row.Provenance } else { 'unknown' }
                        verificationBasis = if ($row) { $row.VerificationBasis } else { 'unknown' }
                        resultDate = if ($row) { $row.ResultDate } else { 'unknown' }
                        retrieved = if ($row) { $row.Retrieved } else { 'unknown' }
                        verified = if ($row) { $row.Verified } else { 'unknown' }
                        legacyDate = if ($row) { $row.LegacyDate } else { 'unknown' }
                        sourceUrl = if ($row) { $row.SourceUrl } else { 'unknown' }
                    }
                    if ($usable -and $detail.selectedPrimary) { $primary.Add($detail) }
                    $detail
                }
            )
            $complete = $panel.defensible -and $primary.Count -eq $panel.primary.Count
            $selectedDiagnostics = @($diagnostics | Where-Object selectedPrimary)
            $status = if ($complete) { 'sufficient' }
            elseif (@($selectedDiagnostics | Where-Object status -eq 'incomparable').Count) { 'incomparable' }
            elseif (@($selectedDiagnostics | Where-Object status -eq 'verification-expired').Count) { 'verification-expired' }
            elseif (@($selectedDiagnostics | Where-Object status -in @('unverified', 'invalidated', 'superseded')).Count) { 'unverified' }
            else { 'insufficient-coverage' }
            $secondary = @(
                foreach ($evaluation in $assignmentProfile.Secondary) {
                    if ($evaluations.ContainsKey($evaluation) -and $evaluations[$evaluation].Usable -and
                        $references.ContainsKey($evaluation) -and $references[$evaluation].Status -eq 'sufficient') { $evaluation }
                }
            )
            $capability = $null
            $fit = 0
            if ($complete) {
                $capability = [decimal]0
                $nativeMean = [decimal]0
                foreach ($item in $primary) { $capability += $panel.weight * $item.percentile; $nativeMean += $panel.weight * $item.score }
                $fit = if ($nativeMean -ge 0.75) { 3 } elseif ($nativeMean -ge 0.50) { 2 } elseif ($nativeMean -ge 0.25) { 1 } else { 0 }
            }
            $sources = @($primary | ForEach-Object basis | Sort-Object -Unique -CaseSensitive)
            $oldest = if ($primary.Count) { @($primary | Sort-Object verified)[0].verified } else { $null }
            $gaps = @($diagnostics | Where-Object { $_.status -notin @('verified', 'older-valid-result') } |
                    ForEach-Object { "$($_.evaluation): $($_.status) ($($_.reason))" })
            $models[$id][$class] = [pscustomobject][ordered]@{
                status = $status; capability = $capability; fit = $fit; panel = $panel
                primaryCoverage = $primary.Count; requiredCoverage = $panel.primary.Count
                fullProfileCoverage = @($diagnostics | Where-Object { $_.fullProfilePrimary -and $null -ne $_.percentile }).Count
                fullProfileRequired = $assignmentProfile.Primary.Count
                primary = @($primary); evaluations = $diagnostics; gaps = $gaps
                secondary = $secondary; secondaryCoverage = $secondary.Count
                oldestPrimary = $oldest
                economyQualified = $complete -and $fit -ge 1 -and
                @($primary | Where-Object { $_.percentile -lt $panel.minimumPercentile }).Count -eq 0
                evidence = "$($sources -join ', ') [$(@($primary | ForEach-Object evaluation) -join ', ')]; panel $($panel.id) v$($panel.version) ($($panel.evidenceLevel))"
            }
        }
    }
    [pscustomobject]@{
        PolicyVersion = $policy.Version; EvaluationDate = $AsOf.ToString('yyyy-MM-dd')
        Models = $models; Panels = $panels; Records = @($unique.Values)
        FreshIndependentModels = @($unique.Values | Where-Object Usable | ForEach-Object CatalogId | Sort-Object -Unique)
        IndependentModels = @($unique.Values | Where-Object Provenance -eq 'independent' | ForEach-Object CatalogId | Sort-Object -Unique)
    }
}

function Get-SquadBenchmarkMappingLine {
    [CmdletBinding()]
    param()

    $policy = Get-SquadBenchmarkPolicy
    '| Assignment class | Panel | Primary evaluations | Secondary evaluations | Evidence rule |'
    '| --- | --- | --- | --- | --- |'
    foreach ($class in $policy.Profiles.Keys) {
        $secondary = @($policy.Profiles[$class].Secondary | ForEach-Object { "``$_``" }) -join ', '
        foreach ($panel in $policy.Profiles[$class].Panels) {
            $primary = @($panel.Primary | ForEach-Object { "``$_``" }) -join ', '
            "| ``$class`` | $($panel.Id) v$($panel.Version) ($($panel.Level)) | $primary | $secondary | $($policy.Version): common verified panel; equal weights; $($panel.Qualification), each percentile >= $($panel.MinimumPercentile); secondary coverage only |"
        }
    }
}

function Get-SquadBenchmarkDerivedLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Scoring)

    $classes = @((Get-SquadBenchmarkPolicy).Profiles.Keys)
    '## Comparison Panels'
    ''
    'Selected from complete independent snapshot-wide coverage, never model scores, prices or host availability. Full wins a coverage tie; no panel with fewer than two comparable models supports a capability claim.'
    ''
    '| Assignment class | Selected panel | Level | Complete models | Alternatives | Limitation |'
    '| --- | --- | --- | ---: | --- | --- |'
    foreach ($class in $classes) {
        $panel = $Scoring.Panels[$class]
        $options = @($panel.options | ForEach-Object { "$($_.id) v$($_.version): $($_.populationCount)" }) -join '; '
        "| $class | $($panel.id) v$($panel.version) | $($panel.evidenceLevel) | $($panel.populationCount) | $options | $($panel.limitation) |"
    }
    ''
    '## Evidence-Derived Assignment Fit'
    ''
    'Generated on the evaluation date. Zero without sufficient evidence is not a measured suitability judgment. Legacy buckets never order comparable Ranked results. Composite is retired (n/a).'
    ''
    '| Catalog ID | research | planning | implementation | review | council | intake | bookkeeping | Composite | Sources | Key evaluations |'
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |'
    foreach ($id in $Scoring.FreshIndependentModels) {
        $results = $Scoring.Models[$id]
        $fits = @($classes | ForEach-Object { $results[$_].fit }) -join ' | '
        $primary = @($classes | ForEach-Object { $results[$_].primary })
        $sources = @($primary | ForEach-Object basis | Sort-Object -Unique -CaseSensitive) -join ', '
        $evaluations = @($primary | ForEach-Object evaluation | Sort-Object -Unique -CaseSensitive) -join ', '
        "| ``$id`` | $fits | n/a | $sources | $evaluations |"
    }
    ''
    '## Capability Results'
    ''
    'Only sufficient selected-panel results have a numeric capability. Reduced panels are narrower evidence, never interchangeable with full panels. Result, acquisition and verification dates remain distinct. See [model-scoring.md](model-scoring.md).'
    ''
    '| Catalog ID | Assignment class | Panel | Level | Capability | Evidence status | Primary coverage | Full profile | Secondary coverage | Primary results and gaps |'
    '| --- | --- | --- | --- | ---: | --- | --- | --- | ---: | --- |'
    foreach ($id in @($Scoring.Models.Keys | Sort-Object -CaseSensitive)) {
        foreach ($class in $classes) {
            $result = $Scoring.Models[$id][$class]
            $number = if ($null -ne $result.capability) { $result.capability.ToString('0.000000', [System.Globalization.CultureInfo]::InvariantCulture) } else { 'insufficient' }
            $details = @(
                foreach ($item in $result.primary) {
                    "$($item.evaluation)=$($item.score) (percentile $($item.percentile.ToString('0.000000', [System.Globalization.CultureInfo]::InvariantCulture)); n=$($item.referenceCount); result $($item.resultDate); retrieved $($item.retrieved); verified $($item.verified); $($item.status))"
                }
                $result.gaps
            ) -join '; '
            "| ``$id`` | ``$class`` | $($result.panel.id) v$($result.panel.version) | $($result.panel.evidenceLevel) | $number | $($result.status) | $($result.primaryCoverage)/$($result.requiredCoverage) | $($result.fullProfileCoverage)/$($result.fullProfileRequired) | $($result.secondaryCoverage) | $details |"
        }
    }
    ''
}