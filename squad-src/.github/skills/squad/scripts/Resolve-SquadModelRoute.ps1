#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Deterministically resolves each roster role's model under `routing=ranked` or
    `routing=economy`, and validates or suggests `routing=manual` picks, exactly as
    model-routing.md defines.
.DESCRIPTION
    Reads a squad root's `team.md` (the `Model routing:` mode line, each row's
    `Role`, `Member Name`, `Model Tier`, and optional `Model` cell) together with the
    shipped `references/model-catalog.md` (capability classes and the *Catalog:
    Assignment Fit* table) and `references/model-routing.md` (the role-to-class
    table). For every roster row it returns the role's assignment class, its floor,
    the ranked suggestion, the ordered candidate list a manual-selection question
    offers, and the status of the row's `Model` cell.

    Ranking uses model-scoring.md's versioned, common-panel capability comparison,
    then confidence and cost only on a genuine capability tie. Legacy fit buckets
    are not the decisive ordering key. Floors are minimums: `fast` admits every
    class, `default` admits balanced, code-specialized, and frontier-reasoning, and
    `extended` admits frontier-reasoning only.

    Under `economy` the same candidates are ordered cost first (economy-mode.md): a
    role on the economy allowlist, mapped to the `implementation` class, takes the
    lowest known Blended price meeting the independent primary-evidence minimum
    within its own floor, and every other role
    keeps its ranked pick. Under `economy` every role also reports `escalation` (for an
    economy pick cheaper than its ranked pick, that ranked pick: the one re-dispatch
    target; otherwise empty) and `pin` (its agent's frontmatter `model:`, from the
    repository or the installed plugin's `agents/` folder).
    Under `economy` the report also carries `consent`: `recorded` when `decisions.md`
    beside `team.md` holds a `## Economy Mode Accepted` entry, else `missing` with a
    warning. Missing consent never refuses. Other modes carry no `consent` field.

    The script is read-only. It never writes `team.md` or any other squad-state file:
    the Squad Scribe remains the single writer, and this script only computes what the
    coordinator hands the Scribe.
.PARAMETER SquadRoot
    A squad root holding `team.md`: `.copilot-tracking/squad/` or a federation member
    root such as `.copilot-tracking/squad/members/<name>/`.
.PARAMETER AvailableModels
    The model ids this host can dispatch. On the Copilot CLI and the GitHub Copilot
    app, pass the `task` tool's advertised `model` enum. Ids absent from the catalog
    are reported as `unevaluated` and never ranked.
.PARAMETER SessionModel
    The session model id (VS Code's Local agent advertises no model list). Used only
    when -AvailableModels is omitted: catalog ids whose Input rate exceeds the session
    model's are treated as unavailable, because VS Code rejects a subagent model above
    the session model's cost tier. `auto`, or an id the catalog cannot price, applies
    no such limit.
.PARAMETER Mode
    `ranked`, `economy`, or `manual`. Defaults to the mode recorded in `team.md`; when
    neither is set the script still ranks, so a caller can preview suggestions before
    switching.
.PARAMETER Role
    Optional role ids to report; defaults to every roster row.
.PARAMETER AsOf
    The date the catalog's staleness is measured against. Defaults to today.
.PARAMETER Format
    `json` (default) or `markdown` (a compact table a manual-selection question can show).
.EXAMPLE
    ./Resolve-SquadModelRoute.ps1 -SquadRoot .copilot-tracking/squad -AvailableModels claude-sonnet-5.5,gpt-5.6-sol,claude-haiku-5.5
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SquadRoot,

    [string[]]$AvailableModels = @(),

    [string]$SessionModel,

    [ValidateSet('ranked', 'economy', 'manual')]
    [string]$Mode,

    [string[]]$Role = @(),

    [System.Collections.IDictionary]$ManualModels,

    [datetime]$AsOf = (Get-Date),

    [string]$BenchmarksPath,

    [ValidateSet('json', 'markdown')]
    [string]$Format = 'json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
. (Join-Path $PSScriptRoot 'ModelBenchmarkScoring.ps1')
$ScoringPolicy = Get-SquadBenchmarkPolicy

$ReferencesRoot = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'references'
if (-not $BenchmarksPath) {
    $BenchmarksPath = Join-Path -Path $ReferencesRoot -ChildPath 'model-benchmarks.md'
}
$Classes = @('research', 'planning', 'implementation', 'review', 'council', 'intake', 'bookkeeping')
$MetacharacterPattern = '[\s;|&$<>`''"(){}\[\]]'
$StaleAfterDays = 90
# economy-mode.md *Role Allowlist*: product-owner sits on the council, and the other
# implementation roles touch live resources or a live backlog, so they keep ranked picks.
$EconomyRoles = @('developer', 'technical-writer', 'presenter', 'prompt-engineer', 'data-scientist')

function Get-MarkdownTableLocal {
    <#
    .SYNOPSIS
        Reads every pipe-delimited markdown table in a document as rows keyed by
        their column headers, in document order.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Content = '')

    $tables = [System.Collections.Generic.List[pscustomobject]]::new()
    $header = $null
    $rows = $null

    foreach ($line in ($Content -split '\r?\n')) {
        if ($line -notmatch '^\s*\|') {
            if ($header) { $tables.Add([pscustomobject]@{ Header = $header; Rows = $rows }) }
            $header = $null
            $rows = $null
            continue
        }
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') { continue }

        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim().Trim('`').Trim() })
        if (-not $header) {
            $header = $cells
            $rows = [System.Collections.Generic.List[System.Collections.Specialized.OrderedDictionary]]::new()
            continue
        }

        $row = [ordered]@{}
        for ($i = 0; $i -lt $header.Count; $i++) {
            $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' }
        }
        $rows.Add($row)
    }

    if ($header) { $tables.Add([pscustomobject]@{ Header = $header; Rows = $rows }) }
    $tables
}

function ConvertTo-NumberLocal {
    <#
    .SYNOPSIS
        Returns a [double] for a plain numeric cell, or $null otherwise.
    #>
    param([string]$Value)

    $clean = ($Value -replace '[*$,]', '').Trim()
    if ($clean -match '^-?\d+(\.\d+)?$') { return [decimal]$clean }
    return $null
}

function ConvertTo-CanonicalModelIdLocal {
    <#
    .SYNOPSIS
        Normalizes host-advertised aliases to the catalog id without widening
        the advertised set.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Value)

    if (-not $Value) {
        return ''
    }
    $id = $Value.Trim().ToLowerInvariant()
    if ($id -in @('hydrafusion', 'hydrafusion-balance', 'hydrafusion-efficiency')) {
        return 'hydrafusion-max'
    }
    return $id
}

function Get-AdvertisedModelIdLocal {
    param(
        [AllowNull()][AllowEmptyString()][string]$CatalogId,
        [Parameter(Mandatory)][hashtable]$AdvertisedIdByCanonical
    )

    if (-not $CatalogId) {
        return $null
    }
    if ($AdvertisedIdByCanonical.ContainsKey($CatalogId)) {
        return $AdvertisedIdByCanonical[$CatalogId]
    }
    return $CatalogId
}

function ConvertTo-VersionLocal {
    <#
    .SYNOPSIS
        Parses a catalog Generation cell (for example `5.5` or `6`) into a comparable version.
    #>
    param([string]$Value)

    $parts = @($Value -split '\.' | Where-Object { $_ -match '^\d+$' })
    if ($parts.Count -eq 0) { return [version]'0.0' }
    if ($parts.Count -eq 1) { $parts += '0' }
    [version]($parts[0..([Math]::Min(3, $parts.Count - 1))] -join '.')
}

function Get-CatalogLocal {
    <#
    .SYNOPSIS
        Reads model-catalog.md into capability, pricing, and fit lookups plus its Retrieved date.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    $retrieved = $null
    $match = [regex]::Match($raw, '\*\*Retrieved:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*')
    if ($match.Success) {
        $retrieved = [datetime]::ParseExact($match.Groups['date'].Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    $capability = @{}
    $displayName = @{}
    $inputRate = @{}
    $fit = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($table in (Get-MarkdownTableLocal -Content $raw)) {
        if ('Catalog ID' -in $table.Header -and 'Capability class' -in $table.Header) {
            foreach ($row in $table.Rows) {
                $capability[$row['Catalog ID']] = $row['Capability class']
                $displayName[$row['Catalog ID']] = $row['Display name']
            }
        }
        elseif ('Catalog ID' -in $table.Header -and 'Rate-row alias' -in $table.Header) {
            foreach ($row in $table.Rows) {
                $rate = ConvertTo-NumberLocal $row['Input']
                if ($null -ne $rate) { $inputRate[$row['Catalog ID']] = $rate }
            }
        }
        elseif ('Catalog ID' -in $table.Header -and 'Blended' -in $table.Header) {
            $order = 0
            foreach ($row in $table.Rows) {
                $scores = @{}
                $declaredScores = @{}
                $backedByEvidence = @{}
                $evidence = @{}
                foreach ($class in $Classes) {
                    $val = [int](ConvertTo-NumberLocal $row[$class])
                    $scores[$class] = $val
                    $declaredScores[$class] = $val
                    $backedByEvidence[$class] = $false
                    $evidence[$class] = 'declared-fit fallback'
                }
                $fit.Add([pscustomobject]@{
                        Id               = $row['Catalog ID']
                        Family           = $row['Family']
                        Generation       = ConvertTo-VersionLocal $row['Generation']
                        Scores           = $scores
                        DeclaredScores   = $declaredScores
                        BackedByEvidence = $backedByEvidence
                        Evidence         = $evidence
                        Capabilities     = @{}
                        Blended          = ConvertTo-NumberLocal $row['Blended']
                        Order            = $order++
                    })
            }
        }
    }

    if ($fit.Count -eq 0) { throw "No 'Catalog: Assignment Fit' table found in $Path." }

    [pscustomobject]@{
        Retrieved   = $retrieved
        Capability  = $capability
        DisplayName = $displayName
        InputRate   = $inputRate
        Fit         = $fit
    }
}

function Get-BenchmarksLocal {
    <#
    .SYNOPSIS
        Reads the pinned document and delegates every derived result to the
        same scorer used by snapshot generation.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][datetime]$AsOf,
        [Parameter(Mandatory)][string[]]$ModelIds
    )

    $result = [pscustomobject]@{
        Exists = Test-Path -LiteralPath $Path -PathType Leaf
        ParseError = $null
        Retrieved = $null
        Generated = $null
        Legacy = $false
        PolicyVersion = $null
        Digest = $null
        Models = @{}
        Panels = @{}
    }
    if (-not $result.Exists) { return $result }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        $match = [regex]::Match($raw, '\*\*Retrieved:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*')
        if ($match.Success) {
            $parsedRetrieved = [datetime]::MinValue
            if (-not [datetime]::TryParseExact(
                    $match.Groups['date'].Value,
                    'yyyy-MM-dd',
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::None,
                    [ref]$parsedRetrieved
                )) {
                throw "Invalid benchmark snapshot Retrieved date '$($match.Groups['date'].Value)' in $Path."
            }
            if ($parsedRetrieved.Date -gt $AsOf.Date) {
                throw "Benchmark snapshot Retrieved date '$($parsedRetrieved.ToString('yyyy-MM-dd'))' is after routing date '$($AsOf.ToString('yyyy-MM-dd'))' in $Path."
            }
            $result.Retrieved = $parsedRetrieved
        }
        $generation = [regex]::Match($raw, '\*\*Generated:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*')
        if ($generation.Success) {
            $result.Generated = Get-SquadBenchmarkDate -Value $generation.Groups['date'].Value -Field Generated -Identity 'snapshot' -AsOf $AsOf
        }
        $policyMatch = [regex]::Match($raw, '\*\*Scoring Policy:\s*(?<version>[a-z0-9.-]+)\*\*')
        $result.PolicyVersion = $policyMatch.Groups['version'].Value
        $result.Legacy = $result.PolicyVersion -eq 'squad-capability-v2'
        $rows = @(Get-SquadBenchmarkRowsFromMarkdown -Content $raw)
        if ($result.Legacy) {
            foreach ($row in $rows) {
                $row.Verification = 'unverified'
                $row.Verified = 'unknown'
                $row.VerificationReason = 'legacy v2 policy: explicit re-verification and v3 regeneration required; ambiguous dates never establish verification'
            }
        }
        $scoring = Get-SquadBenchmarkScore -Rows $rows -AsOf $AsOf -ModelIds $ModelIds
        if ($result.PolicyVersion -ne $ScoringPolicy.Version -and -not $result.Legacy) {
            throw "Missing or unsupported scoring policy '$($result.PolicyVersion)'; expected '$($ScoringPolicy.Version)'."
        }
        $result.Digest = Get-SquadBenchmarkDigest -Content $raw
        $storedDigest = [regex]::Match($raw, '\*\*Content Digest:\s*(?<digest>sha256:[0-9a-f]{64})\*\*').Groups['digest'].Value
        if (-not $result.Legacy -and $storedDigest -and $storedDigest -cne $result.Digest) {
            throw 'Benchmark evidence content digest does not match its source and verification records.'
        }
        $result.Models = $scoring.Models
        $result.Panels = $scoring.Panels
    }
    catch {
        $result.ParseError = $_.Exception.Message
    }
    $result
}

function Get-RoleClassMapLocal {
    <#
    .SYNOPSIS
        Reads model-routing.md's Assignment Classes table into a role-to-class map.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    $section = [regex]::Match($raw, '(?ms)^## Assignment Classes\s*\r?\n(?<body>.*?)(?=^## )').Groups['body'].Value
    $map = @{}
    foreach ($line in ($section -split '\r?\n')) {
        $row = [regex]::Match($line, '^\|\s*`(?<class>[a-z]+)`\s*\|(?<roles>.*)\|\s*$')
        if (-not $row.Success) { continue }
        foreach ($roleMatch in [regex]::Matches($row.Groups['roles'].Value, '`([a-z][a-z0-9-]*)`')) {
            $roleId = $roleMatch.Groups[1].Value
            if (-not $map.ContainsKey($roleId)) { $map[$roleId] = $row.Groups['class'].Value }
        }
    }
    $map
}

function Get-RosterLocal {
    <#
    .SYNOPSIS
        Reads team.md's mode line, Members rows, and optional Connector Bindings.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    $modeMatch = [regex]::Match($raw, '(?m)^Model routing:\s*`?(?<mode>off|ranked|economy|manual)`?\s*$')
    $recordedMode = if ($modeMatch.Success) { $modeMatch.Groups['mode'].Value } else { 'off' }

    $tables = @(Get-MarkdownTableLocal -Content $raw)
    $members = @($tables | Where-Object { 'Role' -in $_.Header -and 'Model Tier' -in $_.Header } | Select-Object -First 1)
    if ($members.Count -eq 0) { throw "No Members table with Role and Model Tier columns found in $Path." }

    $connectorHeader = @('Binding ID', 'Connector ID', 'Manifest', 'Endpoint Kind', 'Role Mode', 'Target Kind', 'Target', 'Member Name', 'Added Role', 'Aligned Role', 'Default Execution')
    $connectorTable = @(
        $tables | Where-Object {
            $table = $_
            @($connectorHeader | Where-Object { $_ -in $table.Header }).Count -eq $connectorHeader.Count
        } | Select-Object -First 1
    )
    $connectorBindings = [System.Collections.Generic.List[pscustomobject]]::new()
    if ($connectorTable.Count -gt 0) {
        foreach ($row in $connectorTable[0].Rows) {
            $bindingId = ([string]$row['Binding ID']).Trim().Trim('`').Trim()
            if (-not $bindingId -or $bindingId -in '—', '-') { continue }
            $connectorBindings.Add([pscustomobject]@{
                    BindingId    = $bindingId
                    ConnectorId  = ([string]$row['Connector ID']).Trim().Trim('`').Trim()
                    EndpointKind = ([string]$row['Endpoint Kind']).Trim().Trim('`').Trim().ToLowerInvariant()
                    RoleMode     = ([string]$row['Role Mode']).Trim().Trim('`').Trim().ToLowerInvariant()
                    TargetKind   = ([string]$row['Target Kind']).Trim().Trim('`').Trim().ToLowerInvariant()
                    Target       = ([string]$row['Target']).Trim().Trim('`').Trim()
                    MemberName   = ([string]$row['Member Name']).Trim().Trim('`').Trim()
                    AddedRole    = ([string]$row['Added Role']).Trim().Trim('`').Trim().ToLowerInvariant()
                    AlignedRole  = ([string]$row['Aligned Role']).Trim().Trim('`').Trim().ToLowerInvariant()
                })
        }
    }

    [pscustomobject]@{
        Mode              = $recordedMode
        HasModel          = 'Model' -in $members[0].Header
        Rows              = $members[0].Rows
        ConnectorBindings = $connectorBindings.ToArray()
    }
}

function Resolve-ConnectorAlignedClassLocal {
    <#
    .SYNOPSIS
        Resolves a connector-added role's assignment class from its validated
        Aligned Role chain, failing on missing, ambiguous, or cyclic alignment.
    #>
    param(
        [Parameter(Mandatory)]$Binding,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Bindings,
        [Parameter(Mandatory)][hashtable]$ClassMap,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$Seen,
        [Parameter(Mandatory)][string]$Context
    )

    if (-not $Binding) { throw "Connector alignment error ($Context): binding not found." }

    $bindingId = [string]$Binding.BindingId
    if ([string]::IsNullOrWhiteSpace($bindingId)) { throw "Connector alignment error ($Context): binding has no Binding ID." }
    if ($Seen.Contains($bindingId)) {
        throw "Connector alignment error ($Context): cyclic Aligned Role chain at binding '$bindingId'."
    }

    $alignedRole = ([string]$Binding.AlignedRole).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($alignedRole)) {
        throw "Connector alignment error ($Context): binding '$bindingId' is missing Aligned Role."
    }

    if ($ClassMap.ContainsKey($alignedRole)) {
        return [pscustomobject]@{ Class = $ClassMap[$alignedRole]; Source = "connector-aligned: $alignedRole" }
    }

    [void]$Seen.Add($bindingId)
    try {
        $next = @($Bindings | Where-Object { $_.RoleMode -eq 'add' -and $_.AddedRole -eq $alignedRole })
        if ($next.Count -eq 0) {
            throw "Connector alignment error ($Context): aligned role '$alignedRole' has no assignment class mapping."
        }
        if ($next.Count -gt 1) {
            throw "Connector alignment error ($Context): aligned role '$alignedRole' is ambiguous across $($next.Count) connector bindings."
        }
        return Resolve-ConnectorAlignedClassLocal -Binding $next[0] -Bindings $Bindings -ClassMap $ClassMap -Seen $Seen -Context $Context
    }
    finally {
        $null = $Seen.Remove($bindingId)
    }
}

function Get-AdmittedClassesLocal {
    <#
    .SYNOPSIS
        Returns the capability classes a Model Tier floor admits, per model-routing.md.
    #>
    param([string]$Tier)

    switch ($Tier) {
        'extended' { return @('frontier-reasoning') }
        'default' { return @('balanced', 'code-specialized', 'frontier-reasoning') }
        'fast' { return @('fast-lightweight', 'balanced', 'code-specialized', 'frontier-reasoning') }
        default { return @() }
    }
}

function Get-RankedCandidatesLocal {
    <#
    .SYNOPSIS
        Orders one class's eligible rows by comparable capability, using declared
        fit only as fallback, or by known price after Economy qualification.
    #>
    param(
        [Parameter(Mandatory)]$Catalog,
        [Parameter(Mandatory)][string]$Class,
        [Parameter(Mandatory)][string[]]$Admitted,
        [AllowNull()][System.Collections.Generic.HashSet[string]]$Available,
        [ValidateSet('fit', 'cost')][string]$Order = 'fit',
        [int]$MinFit = 1
    )

    $eligible = @($Catalog.Fit | Where-Object {
            $_.Scores[$Class] -ge $MinFit -and
            $Catalog.Capability.ContainsKey($_.Id) -and
            $Catalog.Capability[$_.Id] -in $Admitted -and
            ($null -eq $Available -or $Available.Contains($_.Id))
        })
    if ($eligible.Count -eq 0) { return }

    if ($Order -eq 'cost') {
        $eligible = @($eligible | Where-Object {
                $_.BackedByEvidence[$Class] -and $_.Capabilities[$Class].economyQualified -and
                $null -ne $_.Blended -and $_.Blended -ge 0
            })
    }
    if ($eligible.Count -eq 0) { return }

    $orderMode = $Order
    $comparer = [System.Comparison[object]] {
        param($a, $b)
        if ($orderMode -ne 'cost') {
            $byMeasured = ([int][bool]$b.BackedByEvidence[$Class]).CompareTo([int][bool]$a.BackedByEvidence[$Class])
            if ($byMeasured -ne 0) { return $byMeasured }
        }
        $useCapability = $a.BackedByEvidence[$Class] -and $b.BackedByEvidence[$Class]
        $byFit = $b.Scores[$Class].CompareTo($a.Scores[$Class])
        $costA = if ($null -ne $a.Blended -and $a.Blended -ge 0) { $a.Blended } else { [decimal]::MaxValue }
        $costB = if ($null -ne $b.Blended -and $b.Blended -ge 0) { $b.Blended } else { [decimal]::MaxValue }
        $byCost = $costA.CompareTo($costB)
        $byCapability = 0
        $byCoverage = 0
        $byFreshness = 0
        if ($useCapability) {
            $byCapability = $b.Capabilities[$Class].capability.CompareTo($a.Capabilities[$Class].capability)
            $byCoverage = $b.Capabilities[$Class].secondaryCoverage.CompareTo($a.Capabilities[$Class].secondaryCoverage)
            $byFreshness = [string]::CompareOrdinal($b.Capabilities[$Class].oldestPrimary, $a.Capabilities[$Class].oldestPrimary)
        }
        if ($orderMode -eq 'cost') {
            if ($byCost -ne 0) { return $byCost }
            if ($byCapability -ne 0) { return $byCapability }
        }
        else {
            if ($useCapability) {
                if ($byCapability -ne 0) { return $byCapability }
            }
            elseif ($byFit -ne 0) { return $byFit }
        }
        if ($byCoverage -ne 0) { return $byCoverage }
        if ($byFreshness -ne 0) { return $byFreshness }
        if ($byCost -ne 0) { return $byCost }
        if ($a.Family -eq $b.Family) {
            $byGeneration = $b.Generation.CompareTo($a.Generation)
            if ($byGeneration -ne 0) { return $byGeneration }
        }
        return $a.Order.CompareTo($b.Order)
    }
    $list = [System.Collections.Generic.List[object]]::new()
    $eligible | ForEach-Object { $list.Add($_) }
    $list.Sort($comparer)
    $list.ToArray()
}

function Get-AgentPinLocal {
    <#
    .SYNOPSIS
        An agent's frontmatter `model:` (first entry, vendor suffix dropped), or $null, from the
        repository agent folders above .copilot-tracking, then the installed plugin's agents/.
    #>
    param([string]$AgentName, [string]$Root)

    if (-not $AgentName) { return $null }
    # Same search order as Find-AgentPin in Write-SquadHandoff.ps1.
    $bases = @()
    $match = [regex]::Match(($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root) -replace '\\', '/'), '^(?<repo>.*?)/\.copilot-tracking(/|$)')
    if ($match.Success) { $bases += @('.github/agents', '.agents/agents', '.claude/agents') | ForEach-Object { Join-Path $match.Groups['repo'].Value $_ } }
    $bases += @((Join-Path $PSScriptRoot '../../../agents'), (Join-Path $PSScriptRoot '../../agents'), (Join-Path $PSScriptRoot '../agents'))
    foreach ($base in $bases) {
        if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $base -Recurse -File -Filter '*.md')) {
            $lines = @([System.IO.File]::ReadLines($file.FullName) | Select-Object -First 40)
            if ($lines.Count -lt 2 -or $lines[0].Trim() -ne '---') { continue }
            $name = $null
            $model = $null
            for ($i = 1; $i -lt $lines.Count -and $lines[$i].Trim() -ne '---'; $i++) {
                if ($lines[$i] -match '^name:\s*(.+?)\s*$') { $name = $Matches[1].Trim('"', "'") }
                elseif ($lines[$i] -match '^model:\s*(.+?)\s*$') { $model = (($Matches[1].Trim('[', ']').Split(',')[0]).Trim().Trim('"', "'") -replace '\s*\((?:copilot|github|anthropic|openai)\)\s*$', '').Trim() }
            }
            if ($name -ceq $AgentName) { return $model }
        }
    }
    return $null
}

function Get-EscalationTarget {
    <#
    .SYNOPSIS
        The one economy re-dispatch target: the role's ranked pick, or $null when none resolves.
    #>
    param([object[]]$Ranked)

    if (@($Ranked).Count -gt 0) { return $Ranked[0].Id }
    return $null
}

$teamPath = Join-Path -Path $SquadRoot -ChildPath 'team.md'
if (-not (Test-Path -LiteralPath $teamPath -PathType Leaf)) { throw "team.md not found under $SquadRoot." }

$catalog = Get-CatalogLocal -Path (Join-Path -Path $ReferencesRoot -ChildPath 'model-catalog.md')
$classMap = Get-RoleClassMapLocal -Path (Join-Path -Path $ReferencesRoot -ChildPath 'model-routing.md')
$roster = Get-RosterLocal -Path $teamPath
$effectiveMode = if ($Mode) { $Mode } else { $roster.Mode }
$manualSelections = if ($null -ne $ManualModels) { $ManualModels } else { [ordered]@{} }
if ($manualSelections.Count -gt 0 -and $effectiveMode -ne 'manual') {
    throw 'ManualModels may be supplied only when the effective routing mode is manual.'
}
foreach ($key in $manualSelections.Keys) {
    if ($key -isnot [string] -or $key -cnotmatch '^[a-z][a-z0-9-]*$' -or $manualSelections[$key] -isnot [string]) {
        throw 'ManualModels must map lower-kebab-case role IDs to model ID strings.'
    }
    if ($key -cnotin @($roster.Rows | ForEach-Object { $_['Role'] })) {
        throw "ManualModels names a role that is not on the roster: $key"
    }
}
$usesBenchmarkRanking = $effectiveMode -in @('ranked', 'economy', 'manual')
$logsBenchmarkWarnings = $effectiveMode -in @('ranked', 'economy')
$modelIds = @($catalog.Fit | ForEach-Object Id)
$benchmarks = Get-BenchmarksLocal -Path $BenchmarksPath -AsOf $AsOf -ModelIds $modelIds
$emptyScores = Get-SquadBenchmarkScore -Rows @() -AsOf $AsOf -ModelIds $modelIds

$warnings = [System.Collections.Generic.List[string]]::new()
$stale = $false
if (-not $catalog.Retrieved) {
    $stale = $true
    $warnings.Add('model-catalog.md has no parsable Retrieved date; ranking falls back to static tiers.')
}
elseif (($AsOf.Date - $catalog.Retrieved.Date).TotalDays -gt $StaleAfterDays) {
    $stale = $true
    $warnings.Add("model-catalog.md was retrieved $($catalog.Retrieved.ToString('yyyy-MM-dd')), more than $StaleAfterDays days before $($AsOf.ToString('yyyy-MM-dd')); ranking falls back to static tiers.")
}

$benchmarksFallback = $false
$benchmarkWarning = $null
if (-not $stale -and $usesBenchmarkRanking) {
    if (-not $benchmarks.Exists) {
        $benchmarksFallback = $true
        $benchmarkWarning = 'model-benchmarks.md was not found; ranking falls back to the declared fit table in model-catalog.md.'
    }
    elseif ($benchmarks.ParseError) {
        $benchmarksFallback = $true
        $benchmarkWarning = "model-benchmarks.md could not be parsed ($($benchmarks.ParseError)); ranking falls back to the declared fit table in model-catalog.md."
    }
}
if ($benchmarkWarning -and $logsBenchmarkWarnings) { $warnings.Add($benchmarkWarning) }
foreach ($fitEntry in $catalog.Fit) {
    foreach ($c in $Classes) {
        $result = if (-not $benchmarksFallback -and $usesBenchmarkRanking -and $benchmarks.Models.ContainsKey($fitEntry.Id)) {
            $benchmarks.Models[$fitEntry.Id][$c]
        }
        else { $emptyScores.Models[$fitEntry.Id][$c] }
        $fitEntry.Capabilities[$c] = $result
        if ($result.status -eq 'sufficient') {
            $fitEntry.Scores[$c] = $result.fit
            $fitEntry.BackedByEvidence[$c] = $true
            $fitEntry.Evidence[$c] = $result.evidence
        }
    }
}
$loggedMissingEvidenceFallback = $false

$available = $null
$advertised = $null
$advertisedIdByCanonical = @{}
$availability = 'unverified'
$unevaluated = @()
if ($AvailableModels.Count -gt 0) {
    $rawIds = @(
        $AvailableModels |
            ForEach-Object { $_ -split ',' } |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
    $advertised = [System.Collections.Generic.HashSet[string]]::new([string[]]$rawIds)
    $canonicalIds = [System.Collections.Generic.List[string]]::new()
    foreach ($rawId in $rawIds) {
        $canonicalId = ConvertTo-CanonicalModelIdLocal -Value $rawId
        if (-not $advertisedIdByCanonical.ContainsKey($canonicalId) -or $rawId -eq $canonicalId) {
            $advertisedIdByCanonical[$canonicalId] = $rawId
        }
        if (-not $canonicalIds.Contains($canonicalId)) {
            $canonicalIds.Add($canonicalId)
        }
    }
    $available = [System.Collections.Generic.HashSet[string]]::new([string[]]$canonicalIds)
    $availability = 'host-advertised'
    $unevaluated = @($rawIds | Where-Object { -not $catalog.Capability.ContainsKey((ConvertTo-CanonicalModelIdLocal -Value $_)) } | Sort-Object -Unique)
}
elseif ($SessionModel) {
    $canonicalSessionModel = ConvertTo-CanonicalModelIdLocal -Value $SessionModel
    if ($canonicalSessionModel -ne 'auto' -and $catalog.InputRate.ContainsKey($canonicalSessionModel)) {
        $ceiling = $catalog.InputRate[$canonicalSessionModel]
        $ids = @($catalog.Fit | Where-Object { $catalog.InputRate.ContainsKey($_.Id) -and $catalog.InputRate[$_.Id] -le $ceiling } | ForEach-Object { $_.Id })
        $available = [System.Collections.Generic.HashSet[string]]::new([string[]]$ids)
        $availability = "unverified (priced at or below session model $canonicalSessionModel)"
    }
}

# economy-mode.md *Consent*: report a missing ## Economy Mode Accepted entry; never refuse on it.
$consent = $null
if ($effectiveMode -eq 'economy') {
    $decisionsPath = Join-Path -Path $SquadRoot -ChildPath 'decisions.md'
    $decisionsText = if (Test-Path -LiteralPath $decisionsPath -PathType Leaf) { [string](Get-Content -LiteralPath $decisionsPath -Raw) } else { '' }
    $consent = if ($decisionsText -match '(?m)^## Economy Mode Accepted\b') { 'recorded' } else { 'missing' }
    if ($consent -eq 'missing') {
        $warnings.Add('economy consent not recorded: decisions.md has no ## Economy Mode Accepted entry; state the trade and hand the Scribe that decision before the next dispatch (economy-mode.md Consent).')
    }
}
$results = foreach ($row in $roster.Rows) {
    $roleId = $row['Role']
    if (-not $roleId) { continue }
    if ($Role.Count -gt 0 -and $roleId -notin $Role) { continue }

    $tier = $row['Model Tier']
    $class = if ($classMap.ContainsKey($roleId)) { $classMap[$roleId] } else { 'implementation' }
    $classSource = if ($classMap.ContainsKey($roleId)) { 'mapped' } else { 'fallback: implementation' }
    $primaryName = @('Agent Name (Primary)', 'Primary Agent', 'Primary', 'Agent' | ForEach-Object { [string]$row[$_] } | Where-Object { $_ }) | Select-Object -First 1
    $memberName = ([string]$row['Member Name']).Trim()
    if ($primaryName -ceq 'Squad Connector') {
        if ([string]::IsNullOrWhiteSpace($memberName)) {
            throw "Connector alignment error (role '$roleId'): connector-backed row is missing Member Name."
        }
        $bindingMatches = @($roster.ConnectorBindings | Where-Object {
                $_.RoleMode -eq 'add' -and $_.AddedRole -eq $roleId.ToLowerInvariant() -and $_.MemberName -ceq $memberName
            })
        if ($bindingMatches.Count -gt 1) {
            throw "Connector alignment error (role '$roleId', member '$memberName'): $($bindingMatches.Count) matching add bindings found."
        }
        if ($bindingMatches.Count -eq 1) {
            $aligned = Resolve-ConnectorAlignedClassLocal -Binding $bindingMatches[0] -Bindings @($roster.ConnectorBindings) -ClassMap $classMap -Seen ([System.Collections.Generic.HashSet[string]]::new([System.Collections.Generic.IEqualityComparer[string]][System.StringComparer]::OrdinalIgnoreCase)) -Context "role '$roleId', member '$memberName'"
            $class = $aligned.Class
            $classSource = $aligned.Source
        }
        else {
            $classSource = "$classSource; connector:legacy-no-binding"
        }
    }

    $rankedAdmitted = @(Get-AdmittedClassesLocal -Tier $tier)
    $manualAdmitted = $rankedAdmitted
    $ranked = @(if (-not $stale -and $rankedAdmitted.Count -gt 0) { Get-RankedCandidatesLocal -Catalog $catalog -Class $class -Admitted $rankedAdmitted -Available $available })
    $offered = @(if ($manualAdmitted.Count -gt 0) { Get-RankedCandidatesLocal -Catalog $catalog -Class $class -Admitted $manualAdmitted -Available $available })

    $selectedEntry = if ($ranked.Count -gt 0) { $ranked[0] } else { $null }
    $suggestedCatalogId = if ($ranked.Count -gt 0) { $ranked[0].Id } else { $null }
    $objective = 'capability-first'
    $rationale = if ($stale) { 'stale-catalog fallback' }
    elseif ($rankedAdmitted.Count -eq 0) { "no routable floor ('$tier')" }
    elseif (-not $suggestedCatalogId) { 'floor exhausted' }
    elseif ($selectedEntry.BackedByEvidence[$class]) {
        $score = $selectedEntry.Capabilities[$class].capability
        $reason = "Ranked: selected $suggestedCatalogId with comparable $class capability $score"
        if ($ranked.Count -gt 1 -and $ranked[1].BackedByEvidence[$class]) {
            $other = $ranked[1]
            if ($score -gt $other.Capabilities[$class].capability) {
                $reason += " exceeding $($other.Id) ($($other.Capabilities[$class].capability)); cost does not override capability"
            }
            else {
                $reason += "; capability tied with $($other.Id), resolved by secondary coverage, freshness, known Blended cost, then deterministic catalog tie-breaks"
            }
        }
        else { $reason += '; alternatives lack sufficient comparable primary evidence' }
        "$reason (evidence: $($selectedEntry.Evidence[$class])), floor $tier"
    }
    else { "Ranked: selected $suggestedCatalogId by declared fit $($selectedEntry.Scores[$class]), known Blended cost, then deterministic tie-breaks (declared-fit fallback); insufficient comparable primary evidence, not proof of superiority; floor $tier" }

    # Economy narrows only allowlisted, mapped implementation roles; an unmapped role's class is a guess.
    $economyApplies = $effectiveMode -eq 'economy' -and $roleId -in $EconomyRoles -and $classSource -eq 'mapped' -and $class -eq 'implementation'
    if ($economyApplies -and $suggestedCatalogId) {
        $economy = @(Get-RankedCandidatesLocal -Catalog $catalog -Class $class -Admitted $rankedAdmitted -Available $available -Order cost)
        if ($economy.Count -gt 0) {
            $objective = 'cost-first'
            $selectedEntry = $economy[0]
            $suggestedCatalogId = $economy[0].Id
            $qualification = $selectedEntry.Capabilities[$class].panel
            $rationale = "economy pick: selected $suggestedCatalogId under $($qualification.qualificationRule), each selected primary percentile >= $($qualification.minimumPercentile); its known Blended $($selectedEntry.Blended) USD/1M is lowest among $($economy.Count) qualified candidates"
            if ($economy.Count -gt 1) {
                $other = $economy[1]
                $rationale += "; next alternative $($other.Id) costs $($other.Blended), capability $($other.Capabilities[$class].capability); extra capability or confidence never overrides lower cost"
            }
            $rationale += " (evidence: $($selectedEntry.Evidence[$class])), floor $tier"
        }
        else {
            $qualification = $selectedEntry.Capabilities[$class].panel
            $rationale = "economy: no candidate meets $($qualification.qualificationRule) (each selected primary percentile >= $($qualification.minimumPercentile), sufficient verified panel and known price); explicit Ranked fallback; $rationale"
        }
    }
    $suggested = Get-AdvertisedModelIdLocal -CatalogId $suggestedCatalogId -AdvertisedIdByCanonical $advertisedIdByCanonical

    $cellSource = if ($manualSelections.Contains($roleId)) { 'supplied' } else { 'persisted' }
    $cell = if ($cellSource -eq 'supplied') { ([string]$manualSelections[$roleId]).Trim() }
    elseif ($roster.HasModel) { ([string]$row['Model']).Trim() }
    else { '' }
    $cellId = $cell.ToLowerInvariant()
    $canonicalCell = ConvertTo-CanonicalModelIdLocal -Value $cell
    $cellStatus = 'empty'
    if ($cell) {
        if ($cell -match $MetacharacterPattern) { $cellStatus = 'refused: metacharacter' }
        elseif (-not $catalog.Capability.ContainsKey($canonicalCell) -and ($null -eq $advertised -or -not $advertised.Contains($cellId))) { $cellStatus = 'refused: unknown id' }
        elseif ($null -ne $advertised -and -not $advertised.Contains($cellId)) { $cellStatus = 'refused: not available on this host' }
        elseif (-not $catalog.Capability.ContainsKey($canonicalCell)) { $cellStatus = 'valid: unevaluated' }
        elseif ($catalog.Capability[$canonicalCell] -notin $manualAdmitted) { $cellStatus = "refused: below the $tier floor" }
        else { $cellStatus = 'valid' }
    }

    $resolved = switch ($effectiveMode) {
        'manual' { if ($cellStatus -like 'valid*') { $cellId } else { $null } }
        'off' { $null }
        default { $suggested }
    }

    $primaryName = @('Agent Name (Primary)', 'Primary Agent', 'Primary', 'Agent' | ForEach-Object { [string]$row[$_] } | Where-Object { $_ }) | Select-Object -First 1
    $pin = Get-AgentPinLocal -AgentName ([string]$primaryName).Trim('`') -Root $SquadRoot
    $exception = $null
    $expected = $resolved
    if ($roleId -eq 'scribe' -and $pin) {
        $exception = 'scribe-pin'
        $objective = 'pin-exception'
        $pinned = @($catalog.Fit | Where-Object { $_.Id -eq $pin -or $catalog.DisplayName[$_.Id] -eq $pin } | Select-Object -First 1)
        $pinId = if ($pinned.Count -gt 0) { $pinned[0].Id } else { $pin }
        $expected = $pinId
        $selectedEntry = if ($pinned.Count -gt 0) { $pinned[0] } else { $null }
        $canUsePin = $null -eq $available -or $available.Contains($pinId)
        $suggested = if ($canUsePin) { Get-AdvertisedModelIdLocal -CatalogId $pinId -AdvertisedIdByCanonical $advertisedIdByCanonical } else { $null }
        $resolved = if ($effectiveMode -ne 'off') { $suggested } else { $null }
        $rationale = "pin exception: Scribe retains its explicit $pin pin; omit the dispatch model parameter"
        if (-not $canUsePin) { $rationale += '; pin unavailable on this host: escalate, never suggest a substitute' }
        $offered = @()
    }
    elseif ($roleId -in @('coordinator', 'squad-coordinator', 'federation-coordinator') -or
        ([string]$primaryName).Trim('`') -in @('Squad Coordinator', 'Squad Federation Coordinator')) {
        $exception = 'session-model'
        $objective = 'session-model-exception'
        $suggested = $SessionModel
        $resolved = $null
        $expected = $SessionModel
        $selectedEntry = $null
        $rationale = "session-model exception: coordinator retains the selected session model '$SessionModel'; routing never substitutes it"
        $offered = @()
    }
    elseif ($effectiveMode -eq 'manual') {
        $objective = 'explicit-manual-selection'
        $rationale = "Manual: preserve the $cellStatus explicit cell '$cell'; advisory capability-first suggestion only: $rationale"
        $actual = @($catalog.Fit | Where-Object Id -eq $canonicalCell | Select-Object -First 1)
        $selectedEntry = if ($resolved -and $actual.Count -gt 0) { $actual[0] } else { $null }
    }
    elseif ($effectiveMode -eq 'off') {
        $objective = 'no-policy'
        $expected = if ($pin) { $pin } else { $SessionModel }
        $rationale = 'off: omit the dispatch model parameter; any suggestion is a preview, not an applied routing policy'
    }
    $fallback = $null -ne $selectedEntry -and -not $selectedEntry.BackedByEvidence[$class]
    if ($logsBenchmarkWarnings -and -not $exception -and -not $stale -and -not $benchmarksFallback -and $fallback -and -not $loggedMissingEvidenceFallback) {
        $loggedMissingEvidenceFallback = $true
        $rejected = $selectedEntry.Capabilities[$class]
        $warnings.Add("No supported $class benchmark comparison for $($selectedEntry.Id): $($rejected.gaps -join '; '); panel $($rejected.panel.id) v$($rejected.panel.version), $($rejected.primaryCoverage)/$($rejected.requiredCoverage) comparable primaries. Declared-fit fallback, not a measured capability winner; model availability remains $availability.")
    }
    $capabilityResult = if ($selectedEntry) { $selectedEntry.Capabilities[$class] } else { $emptyScores.Models[$modelIds[0]][$class] }
    $reason = $rationale
    if (-not $stale -and $effectiveMode -ne 'off') {
        $panel = $capabilityResult.panel
        $rationale += "; policy $($ScoringPolicy.Version); snapshot $($benchmarks.Digest); evaluated $($AsOf.ToString('yyyy-MM-dd')); panel $($panel.id) v$($panel.version), $($panel.evidenceLevel), complete population $($panel.populationCount); $($panel.limitation); evidence $($capabilityResult.status), primary $($capabilityResult.primaryCoverage)/$($capabilityResult.requiredCoverage), full profile $($capabilityResult.fullProfileCoverage)/$($capabilityResult.fullProfileRequired), secondary $($capabilityResult.secondaryCoverage)"
        if ($capabilityResult.gaps.Count) { $rationale += "; evidence gaps: $($capabilityResult.gaps -join '; ')" }
        if ($capabilityResult.primary.Count) {
            $dates = @($capabilityResult.primary | ForEach-Object { "$($_.evaluation): result $($_.resultDate), retrieved $($_.retrieved), verified $($_.verified) [$($_.status)]" })
            $rationale += "; evidence dates: $($dates -join '; ')"
        }
        $rationale += "; estimated Blended $(if ($selectedEntry -and $null -ne $selectedEntry.Blended) { $selectedEntry.Blended } else { 'unpriced' }) USD/1M (representative token blend)"
        if ($benchmarks.Legacy) { $rationale += '; legacy v2 metadata is unverified; ambiguous Retrieved values were not promoted to genuine verification' }
    }
    $entry = [ordered]@{
        role        = $roleId
        memberName  = $row['Member Name']
        class       = $class
        classSource = $classSource
        floor       = $tier
        suggested   = $suggested
        rationale   = $rationale
        modelCell   = $cell
        modelCellSource = $cellSource
        cellStatus  = $cellStatus
        resolved    = $resolved
        selectionObjective = $objective
        selectionException = $exception
        capability = $capabilityResult.capability
        evidenceStatus = if ($stale) { 'stale-catalog' } else { $capabilityResult.status }
        comparisonPanel = $capabilityResult.panel
        evidenceLevel = $capabilityResult.panel.evidenceLevel
        qualificationRule = $capabilityResult.panel.qualificationRule
        comparisonOutcome = if ($exception) { $exception } elseif ($fallback) { 'declared-fit fallback' } else { $capabilityResult.status }
        coverage = [ordered]@{
            achieved = $capabilityResult.primaryCoverage
            required = $capabilityResult.requiredCoverage
            requiredEvaluations = $capabilityResult.panel.primary
            fullProfileRequiredEvaluations = $ScoringPolicy.Profiles[$class].Primary
            fullProfileAchieved = $capabilityResult.fullProfileCoverage
            fullProfileRequired = $capabilityResult.fullProfileRequired
            primary = $capabilityResult.primary
            evaluations = $capabilityResult.evaluations
            gaps = $capabilityResult.gaps
            secondary = $capabilityResult.secondary
        }
        estimatedCost = if (-not $stale -and $selectedEntry) { $selectedEntry.Blended } else { $null }
        pricingBasis = 'USD/1M representative tokens: 0.20 Input + 0.80 Cached + 0.08 Cache write + 0.02 Output'
        selectionReason = $reason
        policyVersion = $ScoringPolicy.Version
        snapshotIdentity = $benchmarks.Digest
        evaluationDate = $AsOf.ToString('yyyy-MM-dd')
        requestedDispatchModel = if ($exception -or $effectiveMode -eq 'off') { $null } else { $resolved }
        expectedModel = $expected
        effectiveModel = 'unreported'
        observedModel = 'unreported'
        candidates  = @($offered | Select-Object -First 8 | ForEach-Object {
                [pscustomobject][ordered]@{
                    id              = Get-AdvertisedModelIdLocal -CatalogId $_.Id -AdvertisedIdByCanonical $advertisedIdByCanonical
                    displayName     = $catalog.DisplayName[$_.Id]
                    capabilityClass = $catalog.Capability[$_.Id]
                    fit             = $_.Scores[$class]
                    blended         = $_.Blended
                    capability      = $_.Capabilities[$class].capability
                    evidenceStatus  = $_.Capabilities[$class].status
                    panel           = "$($_.Capabilities[$class].panel.id) v$($_.Capabilities[$class].panel.version)"
                    evidenceLevel   = $_.Capabilities[$class].panel.evidenceLevel
                    qualificationRule = $_.Capabilities[$class].panel.qualificationRule
                    coverage        = $_.Capabilities[$class].primaryCoverage
                    requiredCoverage = $_.Capabilities[$class].requiredCoverage
                    primary         = $_.Capabilities[$class].primary
                    evaluations     = $_.Capabilities[$class].evaluations
                    secondaryCoverage = $_.Capabilities[$class].secondaryCoverage
                    economyQualified = $_.Capabilities[$class].economyQualified -and $null -ne $_.Blended -and $_.Blended -ge 0
                }
            })
        evidenceCandidates = @($catalog.Fit | Where-Object {
                $catalog.Capability.ContainsKey($_.Id) -and $catalog.Capability[$_.Id] -in $rankedAdmitted -and
                $_.DeclaredScores[$class] -ge 1 -and ($null -eq $available -or $available.Contains($_.Id))
            } | ForEach-Object {
                [pscustomobject][ordered]@{
                    id = Get-AdvertisedModelIdLocal -CatalogId $_.Id -AdvertisedIdByCanonical $advertisedIdByCanonical
                    availability = $availability
                    evidenceStatus = $_.Capabilities[$class].status
                    panel = "$($_.Capabilities[$class].panel.id) v$($_.Capabilities[$class].panel.version)"
                    evidenceLevel = $_.Capabilities[$class].panel.evidenceLevel
                    capability = $_.Capabilities[$class].capability
                    economyQualified = $_.Capabilities[$class].economyQualified -and $null -ne $_.Blended -and $_.Blended -ge 0
                    estimatedCost = $_.Blended
                    suitabilityFit = $_.Scores[$class]
                    routingEligible = $_.Scores[$class] -ge 1
                    qualificationReason = if ($_.Capabilities[$class].status -ne 'sufficient') {
                        "insufficient selected-panel evidence: $($_.Capabilities[$class].status)"
                    }
                    elseif ($null -eq $_.Blended -or $_.Blended -lt 0) { 'unknown/nonnegative price requirement not met' }
                    elseif (-not $_.Capabilities[$class].economyQualified) {
                        "$($_.Capabilities[$class].panel.qualificationRule) minimum or basic suitability not met"
                    }
                    else { 'qualified at the documented selected-panel minimum and known price' }
                    selectedCoverage = "$($_.Capabilities[$class].primaryCoverage)/$($_.Capabilities[$class].requiredCoverage)"
                    fullProfileCoverage = "$($_.Capabilities[$class].fullProfileCoverage)/$($_.Capabilities[$class].fullProfileRequired)"
                    evaluations = $_.Capabilities[$class].evaluations
                    gaps = $_.Capabilities[$class].gaps
                }
            })
    }
    if ($effectiveMode -eq 'economy') {
        $target = if ($economyApplies) {
            Get-AdvertisedModelIdLocal -CatalogId (Get-EscalationTarget -Ranked $ranked) -AdvertisedIdByCanonical $advertisedIdByCanonical
        }
        else { $null }
        $entry['escalation'] = if ($target -and $target -ne $suggested) { $target } else { $null }
        $entry['escalationReason'] = if ($entry['escalation']) { 'one retry on capability-first Ranked; persist Model cell and rerun required Cost Preflight before redispatch' }
        elseif ($economyApplies) { 'no higher-ranked escalation target exists' }
        else { 'role is outside the Economy allowlist or has an explicit pin exception' }
        $entry['pin'] = $pin
    }
    [pscustomobject]$entry
}

$report = [pscustomobject][ordered]@{
    squadRoot           = $SquadRoot
    recordedMode        = $roster.Mode
    mode                = $effectiveMode
    catalogRetrieved    = if ($catalog.Retrieved) { $catalog.Retrieved.ToString('yyyy-MM-dd') } else { $null }
    benchmarksRetrieved = if ($benchmarks.Retrieved) { $benchmarks.Retrieved.ToString('yyyy-MM-dd') } else { $null }
    benchmarksGenerated = if ($benchmarks.Generated) { $benchmarks.Generated.ToString('yyyy-MM-dd') } else { $null }
    benchmarkSourcePolicy = $benchmarks.PolicyVersion
    legacyEvidence = $benchmarks.Legacy
    scoringPolicy       = $ScoringPolicy.Version
    snapshotIdentity    = $benchmarks.Digest
    evaluationDate      = $AsOf.ToString('yyyy-MM-dd')
    executionEvidence   = 'selection only; host execution unreported'
    availability        = $availability
    unevaluated         = $unevaluated
    warnings            = @($warnings)
    roles               = @($results)
}
if ($effectiveMode -eq 'economy') { $report | Add-Member -NotePropertyName consent -NotePropertyValue $consent }

if ($Format -eq 'json') {
    $report | ConvertTo-Json -Depth 12
    return
}

"Model routing: $effectiveMode (recorded: $($roster.Mode)); availability: $availability"
if ($effectiveMode -eq 'economy') { "consent: $consent" }
foreach ($warning in $warnings) { "WARN: $warning" }
''
$economyHead = if ($effectiveMode -eq 'economy') { ' Escalation |' } else { '' }
$economyRule = if ($effectiveMode -eq 'economy') { '------------|' } else { '' }
"| Role | Class | Floor | Suggested | Model cell | Cell status | Objective | Capability | Evidence | Reason |$economyHead"
"|------|-------|-------|-----------|------------|-------------|-----------|------------|----------|--------|$economyRule"
foreach ($result in $results) {
    $suggestedText = if ($result.suggested) { $result.suggested } else { "— ($($result.rationale))" }
    $cellText = if ($result.modelCell) { $result.modelCell } else { '—' }
    $economyCell = if ($effectiveMode -eq 'economy') { " $(if ($result.escalation) { $result.escalation } else { '—' }) |" } else { '' }
    "| $($result.role) | $($result.class) | $($result.floor) | $suggestedText | $cellText | $($result.cellStatus) | $($result.selectionObjective) | $($result.capability) | $($result.evidenceStatus) | $($result.rationale -replace '\|', '/') |$economyCell"
}
