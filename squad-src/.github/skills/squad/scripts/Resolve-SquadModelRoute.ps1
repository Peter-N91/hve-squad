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

    Ranking follows model-routing.md's *Ranking Algorithm*: fit for the class
    (highest first), then the catalog's Blended rate (lowest first), then the newer
    generation within one model family, then the fit table's row order. A Catalog ID's
    spelling never breaks a tie. Floors follow *Consequence Floors*: `default` admits
    balanced, code-specialized, and frontier-reasoning rows; `extended` admits only
    frontier-reasoning; and under ranked selection a `fast` floor also excludes
    frontier-reasoning rows.

    Under `economy` the same candidates are ordered cost first (economy-mode.md): a
    role on the economy allowlist, mapped to the `implementation` class, takes the
    lowest-Blended id at fit 2 or better within its own floor, and every other role
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
.PARAMETER DispatchAgent
    Exact name of one selected delegate. Adds a dispatch report, or explicitly refuses
    that dispatch. Never expands or admits an agent's advertised delegates.
.PARAMETER OwningRole
    Explicit roster role owning the delegated work. A roster-backed delegate keeps its
    own route; an unrostered worker keeps its pin or the owner's undiscounted ranked pick.
.PARAMETER OwningMemberName
    Disambiguates the owning roster row when the role has multiple named members.
.PARAMETER ObservedModel
    Model actually reported by the host for this dispatch, if any. Overrides attribution
    predictions, never the requested model. Without a report, auto attribution is unknown.
.PARAMETER AsOf
    The date the catalog's staleness is measured against. Defaults to today.
.PARAMETER Format
    `json` (default) or `markdown` (a compact table a manual-selection question can show).
.EXAMPLE
    ./Resolve-SquadModelRoute.ps1 -SquadRoot .copilot-tracking/squad -AvailableModels claude-sonnet-5.5,gpt-5.6-sol,claude-haiku-4.5
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

    [string]$DispatchAgent,

    [string]$OwningRole,

    [string]$OwningMemberName,

    [string]$ObservedModel,

    [datetime]$AsOf = (Get-Date),

    [ValidateSet('json', 'markdown')]
    [string]$Format = 'json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

$ReferencesRoot = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'references'
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
    if ($clean -match '^-?\d+(\.\d+)?$') { return [double]$clean }
    return $null
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
                foreach ($class in $Classes) { $scores[$class] = [int](ConvertTo-NumberLocal $row[$class]) }
                $fit.Add([pscustomobject]@{
                        Id         = $row['Catalog ID']
                        Family     = $row['Family']
                        Generation = ConvertTo-VersionLocal $row['Generation']
                        Scores     = $scores
                        Blended    = [double](ConvertTo-NumberLocal $row['Blended'])
                        Order      = $order++
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
        Reads team.md's mode line and Members rows.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    $modeMatch = [regex]::Match($raw, '(?m)^Model routing:\s*`?(?<mode>off|ranked|economy|manual)`?\s*$')
    $recordedMode = if ($modeMatch.Success) { $modeMatch.Groups['mode'].Value } else { 'off' }

    $members = @(Get-MarkdownTableLocal -Content $raw | Where-Object { 'Role' -in $_.Header -and 'Model Tier' -in $_.Header } | Select-Object -First 1)
    if ($members.Count -eq 0) { throw "No Members table with Role and Model Tier columns found in $Path." }

    [pscustomobject]@{
        Mode      = $recordedMode
        HasModel  = 'Model' -in $members[0].Header
        Rows      = $members[0].Rows
    }
}

function Get-AdmittedClassesLocal {
    <#
    .SYNOPSIS
        Returns the capability classes a Model Tier floor admits, per model-routing.md.
    #>
    param([string]$Tier, [string]$Purpose)

    switch ($Tier) {
        'extended' { return @('frontier-reasoning') }
        'default' { return @('balanced', 'code-specialized', 'frontier-reasoning') }
        'fast' {
            if ($Purpose -eq 'ranked') { return @('fast-lightweight', 'balanced', 'code-specialized') }
            return @('fast-lightweight', 'balanced', 'code-specialized', 'frontier-reasoning')
        }
        default { return @() }
    }
}

function Get-RankedCandidatesLocal {
    <#
    .SYNOPSIS
        Orders the eligible fit rows for one class and floor: fit first (ranked), or
        Blended first (economy, which also raises the minimum fit).
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

    # Newer generation wins only against the same family; across families the fit
    # table's own row order (grouped by family, newest first) is the final tie-break.
    $comparer = [System.Comparison[object]] {
        param($a, $b)
        $byFit = $b.Scores[$Class].CompareTo($a.Scores[$Class])
        $byCost = $a.Blended.CompareTo($b.Blended)
        $first, $second = if ($Order -eq 'cost') { $byCost, $byFit } else { $byFit, $byCost }
        if ($first -ne 0) { return $first }
        if ($second -ne 0) { return $second }
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

function Get-AgentMetadataLocal {
    <#
    .SYNOPSIS
        An agent's frontmatter pin and dispatchability, or $null, from the
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
            $lines = [System.Collections.Generic.List[string]]::new()
            $reader = [System.IO.File]::OpenText($file.FullName)
            try {
                while ($null -ne ($line = $reader.ReadLine())) {
                    $lines.Add($line)
                    if ($lines.Count -eq 1 -and $line.Trim() -ne '---') { break }
                    if ($lines.Count -gt 1 -and $line.Trim() -eq '---') { break }
                }
            }
            finally { $reader.Dispose() }
            if ($lines.Count -lt 2 -or $lines[0].Trim() -ne '---') { continue }
            $name = $null
            $model = $null
            $disabled = $false
            for ($i = 1; $i -lt $lines.Count -and $lines[$i].Trim() -ne '---'; $i++) {
                if ($lines[$i] -match '^name:\s*(.+?)\s*$') { $name = $Matches[1].Trim('"', "'") }
                elseif ($lines[$i] -match '^model:\s*(.+?)\s*$') { $model = (($Matches[1].Trim('[', ']').Split(',')[0]).Trim().Trim('"', "'") -replace '\s*\((?:copilot|github|anthropic|openai)\)\s*$', '').Trim() }
                elseif ($lines[$i] -match '^disable-model-invocation:\s*true\s*$') { $disabled = $true }
            }
            if ($name -ceq $AgentName) { return [pscustomobject]@{ Model = $model; Disabled = $disabled } }
        }
    }
    return $null
}

function Get-AgentPinLocal {
    param([string]$AgentName, [string]$Root)
    $metadata = Get-AgentMetadataLocal -AgentName $AgentName -Root $Root
    if ($metadata) { return $metadata.Model }
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
$purpose = if ($effectiveMode -eq 'manual') { 'manual' } else { 'ranked' }

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

$available = $null
$availability = 'unverified'
$unevaluated = @()
if ($AvailableModels.Count -gt 0) {
    $ids = @($AvailableModels | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $available = [System.Collections.Generic.HashSet[string]]::new([string[]]$ids)
    $availability = 'host-advertised'
    $unevaluated = @($ids | Where-Object { -not $catalog.Capability.ContainsKey($_) } | Sort-Object -Unique)
}
elseif ($SessionModel -and $SessionModel -ne 'auto' -and $catalog.InputRate.ContainsKey($SessionModel)) {
    $ceiling = $catalog.InputRate[$SessionModel]
    $ids = @($catalog.Fit | Where-Object { $catalog.InputRate.ContainsKey($_.Id) -and $catalog.InputRate[$_.Id] -le $ceiling } | ForEach-Object { $_.Id })
    $available = [System.Collections.Generic.HashSet[string]]::new([string[]]$ids)
    $availability = "unverified (priced at or below session model $SessionModel)"
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
    if (-not $DispatchAgent -and $Role.Count -gt 0 -and $roleId -notin $Role) { continue }

    $tier = $row['Model Tier']
    $class = if ($classMap.ContainsKey($roleId)) { $classMap[$roleId] } else { 'implementation' }
    $classSource = if ($classMap.ContainsKey($roleId)) { 'mapped' } else { 'fallback: implementation' }

    $rankedAdmitted = @(Get-AdmittedClassesLocal -Tier $tier -Purpose 'ranked')
    $manualAdmitted = @(Get-AdmittedClassesLocal -Tier $tier -Purpose 'manual')
    $ranked = @(if (-not $stale -and $rankedAdmitted.Count -gt 0) { Get-RankedCandidatesLocal -Catalog $catalog -Class $class -Admitted $rankedAdmitted -Available $available })
    $offered = @(if ($manualAdmitted.Count -gt 0) { Get-RankedCandidatesLocal -Catalog $catalog -Class $class -Admitted $manualAdmitted -Available $available })

    $suggested = if ($ranked.Count -gt 0) { $ranked[0].Id } else { $null }
    $rationale = if ($stale) { 'stale-catalog fallback' }
    elseif ($rankedAdmitted.Count -eq 0) { "no routable floor ('$tier')" }
    elseif (-not $suggested) { 'floor exhausted' }
    else { "rank 1 of $($ranked.Count) in $class at fit $($ranked[0].Scores[$class]), floor $tier" }

    # Economy narrows only allowlisted, mapped implementation roles; an unmapped role's class is a guess.
    $economyApplies = $effectiveMode -eq 'economy' -and $roleId -in $EconomyRoles -and $classSource -eq 'mapped' -and $class -eq 'implementation'
    if ($economyApplies -and $suggested) {
        $economy = @(Get-RankedCandidatesLocal -Catalog $catalog -Class $class -Admitted $rankedAdmitted -Available $available -Order cost -MinFit 2)
        if ($economy.Count -gt 0) {
            $suggested = $economy[0].Id
            $rationale = "economy pick: rank 1 of $($economy.Count) in $class at fit $($economy[0].Scores[$class]) (fit >= 2, lowest Blended), floor $tier"
        }
        else { $rationale = "economy: no id at fit >= 2; $rationale" }
    }

    $cell = if ($roster.HasModel) { ([string]$row['Model']).Trim() } else { '' }
    $cellStatus = 'empty'
    if ($cell) {
        if ($cell -match $MetacharacterPattern) { $cellStatus = 'refused: metacharacter' }
        elseif (-not $catalog.Capability.ContainsKey($cell) -and ($null -eq $available -or -not $available.Contains($cell))) { $cellStatus = 'refused: unknown id' }
        elseif ($null -ne $available -and -not $available.Contains($cell)) { $cellStatus = 'refused: not available on this host' }
        elseif (-not $catalog.Capability.ContainsKey($cell)) { $cellStatus = 'valid: unevaluated' }
        elseif ($catalog.Capability[$cell] -notin $manualAdmitted) { $cellStatus = "refused: below the $tier floor" }
        else { $cellStatus = 'valid' }
    }

    $resolved = switch ($effectiveMode) {
        'manual' { if ($cellStatus -like 'valid*') { $cell } else { $null } }
        default { $suggested }
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
        cellStatus  = $cellStatus
        resolved    = $resolved
        candidates  = @($offered | Select-Object -First 8 | ForEach-Object {
                [pscustomobject][ordered]@{
                    id              = $_.Id
                    displayName     = $catalog.DisplayName[$_.Id]
                    capabilityClass = $catalog.Capability[$_.Id]
                    fit             = $_.Scores[$class]
                    blended         = $_.Blended
                }
            })
    }
    if ($effectiveMode -eq 'economy') {
        $target = if ($economyApplies) { Get-EscalationTarget -Ranked $ranked } else { $null }
        $entry['escalation'] = if ($target -and $target -ne $suggested) { $target } else { $null }
        $primaryName = @('Agent Name (Primary)', 'Primary Agent', 'Primary', 'Agent' | ForEach-Object { [string]$row[$_] } | Where-Object { $_ }) | Select-Object -First 1
        $entry['pin'] = Get-AgentPinLocal -AgentName ([string]$primaryName).Trim('`') -Root $SquadRoot
    }
    [pscustomobject]$entry
}

$dispatch = $null
if ($DispatchAgent) {
    $refusal = "Delegate dispatch refused for '$DispatchAgent'"
    if (-not $OwningRole) { throw "${refusal}: an explicit OwningRole is required." }
    $owners = @($results | Where-Object {
        $_.role -ceq $OwningRole -and (-not $OwningMemberName -or $_.memberName -ceq $OwningMemberName)
    })
    if ($owners.Count -ne 1) { throw "${refusal}: owning role '$OwningRole' must resolve to exactly one roster member." }
    $owner = $owners[0]
    $refusal += " (owning role $($owner.role), floor $($owner.floor))"
    $metadata = Get-AgentMetadataLocal -AgentName $DispatchAgent -Root $SquadRoot
    if (-not $metadata -or $metadata.Disabled) { throw "${refusal}: the selected agent is absent or disables model invocation." }

    $delegateRows = @(foreach ($candidateRow in $roster.Rows) {
        $names = @('Agent Name (Primary)', 'Primary Agent', 'Primary', 'Agent' | ForEach-Object {
            ([string]$candidateRow[$_]).Trim('`')
        })
        $names += @(([string]$candidateRow['Alternate Agents'] -split ',') | ForEach-Object { $_.Trim().Trim('`') })
        if ($DispatchAgent -cin $names) { $candidateRow }
    })
    if ($delegateRows.Count -gt 0 -and $Role.Count -gt 0) {
        $delegateRows = @($delegateRows | Where-Object { $_['Role'] -in $Role })
        if ($delegateRows.Count -eq 0) { throw "${refusal}: the selected Role does not match the delegate's roster identity." }
    }
    if ($delegateRows.Count -gt 1) { throw "${refusal}: multiple roster members match; select a unique delegate Role." }
    $worker = $delegateRows.Count -eq 0
    $route = $owner
    if (-not $worker) {
        $delegateRow = $delegateRows[0]
        $route = @($results | Where-Object {
            $_.role -ceq $delegateRow['Role'] -and $_.memberName -ceq $delegateRow['Member Name']
        })[0]
    }

    $selected = $null
    $requested = 'none (parameter omitted)'
    $source = 'agent-pinned'
    $reason = 'agent pin'
    $rankRationale = $route.rationale
    if ($metadata.Model -and ($worker -or $effectiveMode -eq 'off' -or $DispatchAgent -ceq 'Squad Scribe')) {
        $selected = @($catalog.DisplayName.Keys | Where-Object {
            $_ -ceq $metadata.Model -or $catalog.DisplayName[$_] -eq $metadata.Model
        }) | Select-Object -First 1
        if (-not $selected) { throw "${refusal}: agent pin '$($metadata.Model)' has no catalogued capability; its floor cannot be verified." }
    }
    elseif ($worker) {
        $admitted = @(Get-AdmittedClassesLocal -Tier $owner.floor -Purpose 'ranked')
        $ownerRanked = @(if (-not $stale -and $admitted.Count -gt 0) {
            Get-RankedCandidatesLocal -Catalog $catalog -Class $owner.class -Admitted $admitted -Available $available
        })
        if ($ownerRanked.Count -gt 0) {
            $selected = $ownerRanked[0].Id
            $rankRationale = "rank 1 of $($ownerRanked.Count) at fit $($ownerRanked[0].Scores[$owner.class])"
        }
        else { $rankRationale = if ($stale) { 'stale-catalog fallback cannot verify a worker floor' } else { 'floor exhausted' } }
        $source = 'cli-pinned'
        $reason = 'owning-role ranked model (not discounted pick)'
    }
    elseif ($effectiveMode -in @('ranked', 'economy', 'manual')) {
        $selected = $route.resolved
        $source = 'cli-pinned'
        $reason = "$effectiveMode role routing"
        if ($selected -and $effectiveMode -in @('ranked', 'economy')) {
            if ($route.modelCell -cne $selected) {
                throw "${refusal}: Model cell for '$($route.role)' must be refreshed through the Scribe to '$selected' before dispatch."
            }
            $selected = $route.modelCell
        }
    }
    elseif ($SessionModel -and $SessionModel -ne 'auto') {
        $selected = $SessionModel
        $source = 'session-inherited'
        $reason = 'session fallback'
    }
    if (-not $selected) { throw "${refusal}: no valid model meets the $($route.floor) floor ($rankRationale); no downgrade or unverified host fallback is permitted." }
    if ($null -ne $available -and -not $available.Contains($selected)) { throw "${refusal}: model '$selected' is not available on this host." }
    $admitted = @(Get-AdmittedClassesLocal -Tier $route.floor -Purpose 'manual')
    $explicitUnevaluated = -not $worker -and $effectiveMode -eq 'manual' -and $route.cellStatus -eq 'valid: unevaluated'
    if (-not $explicitUnevaluated -and (-not $catalog.Capability.ContainsKey($selected) -or $catalog.Capability[$selected] -notin $admitted)) {
        throw "${refusal}: model '$selected' cannot be verified at the $($route.floor) floor."
    }
    if ($source -eq 'cli-pinned') { $requested = $selected }
    $effective = $selected
    $observed = 'unverified'
    if ($ObservedModel) {
        if ($ObservedModel -in @('auto', 'unknown', 'unreported', 'unverified')) { throw 'ObservedModel must be a concrete host-reported model, not a placeholder.' }
        $effective = $ObservedModel
        $source = 'dispatch-reported'
        $observed = $ObservedModel
    }
    elseif ($SessionModel -eq 'auto') {
        $effective = 'unknown'
        $source = 'unresolved'
        $observed = 'unreported'
    }
    $marker = if ($effectiveMode -eq 'economy') { 'Route: economy; ' } else { '' }
    $rationale = "${marker}owning role $($owner.role); routing role $($route.role); $reason; class $($route.class); floor $($route.floor); $rankRationale"
    $observedId = @($catalog.DisplayName.Keys | Where-Object {
        $_ -ceq $ObservedModel -or $catalog.DisplayName[$_] -eq $ObservedModel
    }) | Select-Object -First 1
    if ($ObservedModel -and $requested -ne 'none (parameter omitted)' -and $selected -cne $(if ($observedId) { $observedId } else { $ObservedModel })) {
        $rationale += "; identity-mismatch: requested $requested, observed $ObservedModel"
    }
    $observedFloor = 'unreported'
    if ($ObservedModel) {
        $observedFloor = if (-not $observedId) { 'unverified' }
        elseif ($catalog.Capability[$observedId] -in $admitted) { 'admitted' }
        else { 'below-floor' }
        if ($observedFloor -ne 'admitted') { $rationale += "; host model floor ${observedFloor}: escalate, not successful admission" }
    }
    $dispatch = [pscustomobject][ordered]@{
        agent = $DispatchAgent
        owningRole = $owner.role
        owningMemberName = $owner.memberName
        routingRole = $route.role
        worker = $worker
        class = $route.class
        floor = $route.floor
        selectedModel = $selected
        attributionSource = $source
        observedFloor = $observedFloor
        routingIdentity = [pscustomobject][ordered]@{
            requestedModel = $requested
            effectiveModel = $effective
            observedModel = $observed
            routeRationale = $rationale
        }
    }
}
elseif ($OwningRole -or $OwningMemberName -or $ObservedModel) { throw 'OwningRole/OwningMemberName/ObservedModel requires a selected DispatchAgent.' }

$report = [pscustomobject][ordered]@{
    squadRoot        = $SquadRoot
    recordedMode     = $roster.Mode
    mode             = $effectiveMode
    catalogRetrieved = if ($catalog.Retrieved) { $catalog.Retrieved.ToString('yyyy-MM-dd') } else { $null }
    availability     = $availability
    unevaluated      = $unevaluated
    warnings         = @($warnings)
    roles            = @($results)
}
if ($dispatch) { $report | Add-Member -NotePropertyName dispatch -NotePropertyValue $dispatch }
if ($effectiveMode -eq 'economy') { $report | Add-Member -NotePropertyName consent -NotePropertyValue $consent }

if ($Format -eq 'json') {
    $report | ConvertTo-Json -Depth 6
    return
}

"Model routing: $effectiveMode (recorded: $($roster.Mode)); availability: $availability"
if ($dispatch) {
    "Delegate $($dispatch.agent): selected $($dispatch.selectedModel); requested $($dispatch.routingIdentity.requestedModel); attribution $($dispatch.attributionSource); $($dispatch.routingIdentity.routeRationale)"
}
if ($effectiveMode -eq 'economy') { "consent: $consent" }
foreach ($warning in $warnings) { "WARN: $warning" }
''
$economyHead = if ($effectiveMode -eq 'economy') { ' Escalation |' } else { '' }
$economyRule = if ($effectiveMode -eq 'economy') { '------------|' } else { '' }
"| Role | Class | Floor | Suggested | Model cell | Cell status |$economyHead"
"|------|-------|-------|-----------|------------|-------------|$economyRule"
foreach ($result in $results) {
    $suggestedText = if ($result.suggested) { $result.suggested } else { "— ($($result.rationale))" }
    $cellText = if ($result.modelCell) { $result.modelCell } else { '—' }
    $economyCell = if ($effectiveMode -eq 'economy') { " $(if ($result.escalation) { $result.escalation } else { '—' }) |" } else { '' }
    "| $($result.role) | $($result.class) | $($result.floor) | $suggestedText | $cellText | $($result.cellStatus) |$economyCell"
}
