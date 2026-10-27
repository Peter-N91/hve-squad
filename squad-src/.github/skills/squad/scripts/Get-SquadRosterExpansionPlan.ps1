#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Seals a confirmed additive roster expansion for one plain squad or federation member.
.DESCRIPTION
    AI cost: none. Resolves confirmed catalog roles and packs, validates their installed
    Primaries, appends only missing roster rows and newly eligible canonical routing rows,
    and writes an exact hash-bound plan outside squad state.

    The plan contains the final team.md, routing.md, and append-only decisions.md bytes.
    It seals state, accounting, rates, notifications, history, and (for a federation
    member) its registry row so the apply transaction can prove they did not change.
    No squad state is written by this helper.
.PARAMETER ChoicesPath
    Confirmed JSON with confirmed, runId, and one or both of packs/roles. Optional:
    names, models, and rationale.
.PARAMETER PayloadPath
    New plan JSON outside all squad state.
.PARAMETER SquadRoot
    Plain squad root or one registered federation member root.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ChoicesPath,
    [Parameter(Mandatory)][string]$PayloadPath,
    [string]$RepoRoot = (Get-Location).ProviderPath,
    [string]$SquadRoot = '.copilot-tracking/squad'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SquadPromotion.psm1') -Force

function Assert-FieldSet {
    param($Object, [string[]]$Required, [string[]]$Optional = @())
    if ($Object -isnot [Collections.IDictionary]) { throw 'Expected a JSON object.' }
    foreach ($field in $Required) {
        if (-not $Object.Contains($field)) { throw "Missing field: $field" }
    }
    foreach ($field in $Object.Keys) {
        if ($field -notin ($Required + $Optional)) { throw "Unsupported field: $field" }
    }
}

function Assert-Line {
    param($Value, [switch]$AllowEmpty)
    if ($Value -isnot [string] -or $Value -match '[\r\n|\x00-\x1f]' -or
        (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value))) {
        throw 'Expected a single-line value without table delimiters or control characters.'
    }
}

function Get-Hash {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Get-FileSnapshot {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked squad-state file refused: $Path" }
    $bytes = [IO.File]::ReadAllBytes($Path)
    [ordered]@{
        bytes = $bytes.Length
        sha256 = Get-Hash $bytes
    }
}

function Get-Document {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf
    $body = if ($hasBom -and $bytes.Length -gt 3) { $bytes[3..($bytes.Length - 1)] }
    elseif ($hasBom) { [byte[]]::new(0) }
    else { $bytes }
    $text = [Text.UTF8Encoding]::new($false).GetString($body)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $trailing = $text.EndsWith("`n")
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in ($text -split "`r?`n")) { $null = $lines.Add($line) }
    if ($trailing -and $lines.Count -and $lines[-1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    [pscustomobject]@{
        bytes = $bytes
        hasBom = $hasBom
        newline = $newline
        trailing = $trailing
        lines = $lines
    }
}

function ConvertTo-DocumentByteArray {
    param([Parameter(Mandatory)]$Document)
    $text = ($Document.lines -join $Document.newline) + $(if ($Document.trailing) { $Document.newline })
    $body = [Text.UTF8Encoding]::new($false).GetBytes($text)
    if (-not $Document.hasBom) { return ,$body }
    $result = [byte[]]::new($body.Length + 3)
    $result[0] = 0xef
    $result[1] = 0xbb
    $result[2] = 0xbf
    [Array]::Copy($body, 0, $result, 3, $body.Length)
    ,$result
}

function ConvertFrom-TableLine {
    param([Parameter(Mandatory)][string]$Line)
    @($Line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
}

function Get-Table {
    param(
        [AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string[]]$RequiredHeaders
    )
    $tables = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -notmatch '^\s*\|') { continue }
        $header = @(ConvertFrom-TableLine $Lines[$index] | ForEach-Object { $_.Trim('`') })
        if (@($RequiredHeaders | Where-Object { $_ -notin $header }).Count) { continue }
        if ($index + 1 -ge $Lines.Count -or $Lines[$index + 1] -notmatch '^\s*\|') {
            throw 'Markdown table has no separator row.'
        }
        $end = $index + 2
        while ($end -lt $Lines.Count -and $Lines[$end] -match '^\s*\|') { $end++ }
        $null = $tables.Add([pscustomobject]@{ start = $index; end = $end; header = $header })
    }
    if ($tables.Count -ne 1) { throw "Expected one table with headers: $($RequiredHeaders -join ', ')." }
    $tables[0]
}

function Resolve-DeliverableRoot {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$RelativeRoot,
        [Parameter(Mandatory)][string]$Repository
    )
    if ($Value -ceq '(squad state)' -or $Value -ceq [string][char]0x2014) { return $Value }
    $resolved = foreach ($alternative in ($Value -split '\s+or\s+')) {
        $label = [regex]::Match($alternative, ' \((?:ADO|Jira)\)$').Value
        $path = $alternative.Substring(0, $alternative.Length - $label.Length).Trim().Trim('`') -replace '\\', '/'
        if ($path -match '(^|/)\.\.(/|$)|^[~/]|:') { throw 'Unsafe Deliverable Root.' }
        $canonical = ([IO.Path]::GetRelativePath($Repository, [IO.Path]::GetFullPath($path, $Repository)) -replace '\\', '/').TrimEnd('/')
        if ($canonical -eq '.' -or $canonical -match '^\.\.(?:/|$)') { throw 'Unsafe Deliverable Root.' }
        if ($RelativeRoot -ne '.copilot-tracking/squad' -and $canonical -notmatch '^(?:docs|outputs)(?:/|$)') {
            if ($canonical -match '^\.copilot-tracking/squad/members(?:/|$)') {
                if ($canonical -cne $RelativeRoot -and
                    -not $canonical.StartsWith($RelativeRoot + '/', [StringComparison]::Ordinal)) {
                    throw 'Deliverable Root must stay under the selected member.'
                }
            }
            else {
                if ($canonical.StartsWith('.copilot-tracking/', [StringComparison]::Ordinal)) {
                    $canonical = $canonical.Substring('.copilot-tracking/'.Length)
                }
                $canonical = $RelativeRoot + '/' + $canonical
            }
        }
        $canonical + $(if ($path.EndsWith('/')) { '/' }) + $label
    }
    $resolved -join ' or '
}

function Add-TableRow {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)]$Table,
        [Parameter(Mandatory)][string[]]$Rows
    )
    $offset = 0
    foreach ($row in $Rows) {
        $Document.lines.Insert($Table.end + $offset, $row)
        $offset++
    }
}

function Add-DecisionEntry {
    param(
        [Parameter(Mandatory)][byte[]]$Before,
        [Parameter(Mandatory)][string]$Entry
    )
    $hasBom = $Before.Length -ge 3 -and $Before[0] -eq 0xef -and $Before[1] -eq 0xbb -and $Before[2] -eq 0xbf
    $body = if ($hasBom -and $Before.Length -gt 3) { $Before[3..($Before.Length - 1)] }
    elseif ($hasBom) { [byte[]]::new(0) }
    else { $Before }
    $text = [Text.UTF8Encoding]::new($false).GetString($body)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $prefix = if (-not $Before.Length) { '' } elseif ($text.EndsWith("`n")) { $newline } else { "$newline$newline" }
    $tail = $prefix + ($Entry -replace "`r?`n", $newline) + $newline
    $tailBytes = [Text.UTF8Encoding]::new($false).GetBytes($tail)
    $result = [byte[]]::new($Before.Length + $tailBytes.Length)
    [Array]::Copy($Before, 0, $result, 0, $Before.Length)
    [Array]::Copy($tailBytes, 0, $result, $Before.Length, $tailBytes.Length)
    ,$result
}

function Get-Baseline {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$RelativeRoot
    )
    $files = [ordered]@{}
    foreach ($name in @(
            'team.md', 'routing.md', 'decisions.md', 'notifications.md',
            'state.json', 'consumption.md', 'consumption-rates.md'
        )) {
        $path = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required squad state: $name" }
        $files[$name] = Get-FileSnapshot $path
    }
    $sessionCache = Join-Path $Root 'consumption-sessions.json'
    if (Test-Path -LiteralPath $sessionCache -PathType Leaf) {
        $files['consumption-sessions.json'] = Get-FileSnapshot $sessionCache
    }
    $history = Join-Path $Root 'history'
    if (-not (Test-Path -LiteralPath $history -PathType Container)) { throw 'Missing required squad state: history' }
    $baseline = [ordered]@{
        files = $files
        history = Get-SquadPromotionTreeSnapshot $history
    }
    if ($RelativeRoot -match '^\.copilot-tracking/squad/members/(?<name>[a-z0-9][a-z0-9-]*)$') {
        $memberName = $Matches.name
        $federationRoot = Join-Path $Repository '.copilot-tracking' 'squad'
        $registryPath = Join-Path $federationRoot 'federation.md'
        if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
            throw "Member '$memberName' is not under a federation registry."
        }
        $registry = @(Read-SquadTables $registryPath |
                Where-Object { 'Sub-squad' -in $_.Header -and 'Location' -in $_.Header })
        if ($registry.Count -ne 1) { throw 'Federation registry is missing or ambiguous.' }
        $rows = @($registry[0].Rows | Where-Object {
                $_['Sub-squad'] -ceq $memberName -and
                (($_.Location -replace '\\', '/').TrimEnd('/')) -ceq "members/$memberName"
            })
        if ($rows.Count -ne 1) { throw "Member '$memberName' is not registered at its selected root." }
        $baseline['federation'] = [ordered]@{
            member = $memberName
            registry = Get-FileSnapshot $registryPath
        }
    }
    $baseline
}

function Assert-Baseline {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$RelativeRoot
    )
    $actual = Get-Baseline -Root $Root -Repository $Repository -RelativeRoot $RelativeRoot
    foreach ($name in $Expected.files.Keys) {
        foreach ($field in @('bytes', 'sha256')) {
            if ($Expected.files[$name][$field] -cne $actual.files[$name][$field]) {
                throw "Squad state changed while the roster expansion plan was being prepared: $name"
            }
        }
    }
    foreach ($field in @('digest', 'files', 'directories', 'bytes')) {
        if ($Expected.history[$field] -cne $actual.history[$field]) {
            throw 'Squad history changed while the roster expansion plan was being prepared.'
        }
    }
    if ($Expected.Contains('federation')) {
        foreach ($field in @('bytes', 'sha256')) {
            if ($Expected.federation.registry[$field] -cne $actual.federation.registry[$field]) {
                throw 'Federation registry changed while the roster expansion plan was being prepared.'
            }
        }
    }
}

try {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $choices = Get-Content -LiteralPath $ChoicesPath -Raw | ConvertFrom-Json -AsHashtable
    Assert-FieldSet $choices @('confirmed', 'runId') @('packs', 'roles', 'names', 'models', 'rationale')
    if ($choices.confirmed -isnot [bool] -or -not $choices.confirmed) {
        throw 'Roster expansion requires explicit user confirmation.'
    }
    Assert-Line $choices.runId
    if ($choices.Contains('rationale')) { Assert-Line $choices.rationale }
    foreach ($field in @('packs', 'roles')) {
        if ($choices.Contains($field) -and $choices[$field] -isnot [array]) { throw "$field must be an array." }
    }
    $names = if ($choices.Contains('names')) { $choices.names } else { @{} }
    $models = if ($choices.Contains('models')) { $choices.models } else { @{} }
    if ($names -isnot [Collections.IDictionary] -or $models -isnot [Collections.IDictionary]) {
        throw 'names and models must be role-to-value objects.'
    }

    $root = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $SquadRoot
    $relativeRoot = [IO.Path]::GetRelativePath($RepoRoot, $root) -replace '\\', '/'
    if ($relativeRoot -notmatch '^\.copilot-tracking/squad(?:/members/[a-z0-9][a-z0-9-]*)?$') {
        throw 'SquadRoot must be the plain squad root or one federation member root.'
    }
    if (Test-Path -LiteralPath (Join-Path $root 'federation.md') -PathType Leaf) {
        throw 'Roster expansion targets a plain squad or one member root, never the federation root.'
    }
    $baseline = Get-Baseline -Root $root -Repository $RepoRoot -RelativeRoot $relativeRoot

    $teamPath = Join-Path $root 'team.md'
    $routingPath = Join-Path $root 'routing.md'
    $decisionsPath = Join-Path $root 'decisions.md'
    $team = Get-Document $teamPath
    $routing = Get-Document $routingPath
    $teamTable = Get-Table -Lines $team.lines -RequiredHeaders @('Role', 'Agent Name (Primary)', 'Model Tier', 'Deliverable Root')
    $routingTable = Get-Table -Lines $routing.lines -RequiredHeaders @('Pattern / Keyword', 'Role(s)', 'Autonomy Tier', 'Parallel-Eligible')

    $modeMatches = [regex]::Matches(($team.lines -join "`n"), '(?m)^Model routing:\s*`?(?<mode>off|ranked|economy|manual)`?\s*$')
    if ($modeMatches.Count -gt 1) { throw 'team.md has more than one Model routing line.' }
    $mode = if ($modeMatches.Count) { $modeMatches[0].Groups['mode'].Value } else { 'off' }
    $expectedColumns = @(
        'Role', 'Member Name', 'Agent Name (Primary)', 'Alternate Agents',
        'Selection Cue', 'Invocation', 'Model Tier'
    )
    if ($mode -ne 'off') { $expectedColumns += 'Model' }
    $expectedColumns += 'Deliverable Root'
    if (($teamTable.header -join "`n") -cne ($expectedColumns -join "`n")) {
        throw 'Roster expansion requires the current canonical Members columns; use cold refresh for legacy/custom table shapes.'
    }
    if (($mode -eq 'off') -ne ('Model' -notin $teamTable.header)) {
        throw 'team.md routing mode and Model column disagree.'
    }

    $roster = @(Get-SquadRoster $root)
    $existingRoles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $existingNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $roster) {
        $null = $existingRoles.Add([string]$row.Role)
        if ($row['Member Name']) { $null = $existingNames.Add([string]$row['Member Name']) }
    }

    $data = Get-SquadInitData -RepoRoot $RepoRoot
    $requestedPacks = [Collections.Generic.List[string]]::new()
    $requestedRoles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($choices.Contains('packs')) {
        foreach ($packName in $choices.packs) {
            Assert-Line $packName
            $pack = @($data.packs | Where-Object { $_.Pack -ceq $packName })
            if ($pack.Count -ne 1 -or $packName -in $requestedPacks) { throw "Unknown or duplicate pack: $packName" }
            $null = $requestedPacks.Add($packName)
            foreach ($role in @($pack[0]['Adds (roles)'] -split ',\s*')) { $null = $requestedRoles.Add($role) }
        }
    }
    if ($choices.Contains('roles')) {
        foreach ($role in $choices.roles) {
            Assert-Line $role
            if ($role -cnotmatch '^[a-z][a-z0-9-]*$') { throw "Invalid role: $role" }
            $null = $requestedRoles.Add($role)
        }
    }
    if (-not $requestedRoles.Count) { throw 'Roster expansion requires at least one confirmed pack or role.' }

    $catalogOrder = @($data.cast | ForEach-Object Role)
    $unknown = @($requestedRoles | Where-Object { $_ -notin $catalogOrder })
    if ($unknown.Count) { throw "Unknown catalog role(s): $($unknown -join ', ')" }
    $alreadyPresent = @($catalogOrder | Where-Object { $requestedRoles.Contains($_) -and $existingRoles.Contains($_) })
    $addRoles = @($catalogOrder | Where-Object { $requestedRoles.Contains($_) -and -not $existingRoles.Contains($_) })
    if (-not $addRoles.Count) { throw 'Every confirmed role is already present; nothing to expand.' }

    foreach ($key in $names.Keys) {
        if ($key -notin $addRoles) { throw "names contains a role that is not being added: $key" }
        Assert-Line $names[$key]
        if (-not $existingNames.Add([string]$names[$key])) { throw "Duplicate member name: $($names[$key])" }
    }
    foreach ($key in $models.Keys) {
        if ($key -notin $addRoles -or $mode -eq 'off') { throw "models contains an invalid role for routing mode '$mode': $key" }
        Assert-Line $models[$key]
        if ($models[$key] -cnotmatch '^[a-z0-9][a-z0-9.-]*$') { throw "Invalid model id: $($models[$key])" }
    }

    $agents = Get-SquadAgentIndex $RepoRoot
    $teamLines = [Collections.Generic.List[string]]::new()
    foreach ($role in $addRoles) {
        $cast = @($data.cast | Where-Object { $_.Role -ceq $role })
        if ($cast.Count -ne 1) { throw "Unknown or ambiguous catalog role: $role" }
        $primary = [string]$cast[0]['Primary Agent (`name:`)']
        if (-not $agents.ContainsKey($primary) -or -not $agents[$primary].dispatchable) {
            throw "Role '$role' has no installed dispatchable Primary '$primary'; install it or confirm another role."
        }
        $seed = @($data.seeds | Where-Object { $_.Role -ceq $role })
        $rootRows = @($data.roots | Where-Object { $role -cin @($_.Role -split ',\s*') })
        if ($rootRows.Count -gt 1) { throw "Ambiguous canonical Deliverable Root for $role." }
        $deliverable = if ($role -eq 'scribe') { '(squad state)' }
        elseif ($rootRows.Count) { [string]$rootRows[0]['Deliverable Root'] }
        else { [string][char]0x2014 }
        $deliverable = Resolve-DeliverableRoot -Value $deliverable -RelativeRoot $relativeRoot -Repository $RepoRoot
        if ($role -eq 'intake-validator') {
            $capture = $deliverable.TrimEnd('/')
            if ($capture -in @('-', [string][char]0x2014, '(squad state)') -or
                $capture -match '\s+or\s+|[<>]' -or
                $capture -match '^\.copilot-tracking/squad(?:/members/[^/]+)?(?:$|/(?:team\.md|routing\.md|decisions\.md|notifications\.md|state\.json|consumption(?:-rates)?\.md|history|memory)(?:/|$))') {
                throw 'intake-validator requires an explicit non-state capture directory.'
            }
        }
        $row = [ordered]@{
            Role = $role
            'Member Name' = $(if ($names.Contains($role)) { $names[$role] } else { '' })
            'Agent Name (Primary)' = $primary
            'Alternate Agents' = [string]$cast[0]['Alternate Agents (`name:`)']
            'Selection Cue' = [string]$cast[0]['Selection Cue']
            Invocation = 'runSubagent / task'
            'Model Tier' = $(if ($seed.Count) { [string]$seed[0]['Model Tier'] } else { 'default' })
        }
        if ($mode -ne 'off') { $row['Model'] = $(if ($models.Contains($role)) { [string]$models[$role] } else { '' }) }
        $row['Deliverable Root'] = $deliverable
        foreach ($column in $teamTable.header) {
            $value = [string]$row[$column]
            if ($value -match '[\r\n|]') { throw "Catalog row '$role' contains unsafe table content in '$column'." }
        }
        $null = $teamLines.Add('| ' + (($teamTable.header | ForEach-Object { [string]$row[$_] }) -join ' | ') + ' |')
    }
    Add-TableRow -Document $team -Table $teamTable -Rows $teamLines.ToArray()
    $finalTeam = ConvertTo-DocumentByteArray $team

    $finalRoles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($role in $existingRoles) { $null = $finalRoles.Add($role) }
    foreach ($role in $addRoles) { $null = $finalRoles.Add($role) }
    $existingPatterns = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = $routingTable.start + 2; $index -lt $routingTable.end; $index++) {
        $cells = @(ConvertFrom-TableLine $routing.lines[$index])
        if ($cells.Count -ne $routingTable.header.Count) { throw 'Existing routing row width is invalid.' }
        $null = $existingPatterns.Add($cells[[Array]::IndexOf($routingTable.header, 'Pattern / Keyword')])
    }
    $seedTables = @(Read-SquadTables (Join-Path $PSScriptRoot '..' 'references' 'seed-templates.md') |
            Where-Object {
                'Pattern / Keyword' -in $_.Header -and 'Role(s)' -in $_.Header -and
                'Autonomy Tier' -in $_.Header -and 'Parallel-Eligible' -in $_.Header
            })
    if ($seedTables.Count -ne 1) { throw 'Canonical routing seed table is missing or ambiguous.' }
    $routeLines = [Collections.Generic.List[string]]::new()
    foreach ($route in $seedTables[0].Rows) {
        $pattern = [string]$route['Pattern / Keyword']
        if ($existingPatterns.Contains($pattern)) { continue }
        $routeRoles = @($route['Role(s)'] -split ',\s*' | ForEach-Object { $_ -replace ' \(optional\)$', '' })
        $eligible = $pattern -match 'council' -or @($routeRoles | Where-Object { -not $finalRoles.Contains($_) }).Count -eq 0
        if (-not $eligible) { continue }
        $null = $routeLines.Add('| ' + (($routingTable.header | ForEach-Object { [string]$route[$_] }) -join ' | ') + ' |')
        $null = $existingPatterns.Add($pattern)
    }
    if ($routeLines.Count) { Add-TableRow -Document $routing -Table $routingTable -Rows $routeLines.ToArray() }
    $finalRouting = ConvertTo-DocumentByteArray $routing

    $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json -AsHashtable
    if ($state.turn -isnot [ValueType] -or $state.turn -is [bool]) { throw 'state.json turn is invalid.' }
    $provenance = Get-SquadPromotionProfile -DecisionsPath $decisionsPath -Roster $roster -InitData $data
    Assert-Line $provenance
    $nextProvenance = $provenance
    foreach ($pack in $requestedPacks) {
        if ($nextProvenance -notmatch ('(?:^|\s)\+' + [regex]::Escape($pack) + '(?:\s|$)')) {
            $nextProvenance += " +$pack"
        }
    }
    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    $rationale = if ($choices.Contains('rationale')) {
        $choices.rationale
    }
    else {
        'Apply the confirmed additive catalog-role expansion without recasting existing members.'
    }
    $entry = @(
        "## Roster Expansion $timestamp"
        ''
        "* Run: $($choices.runId)"
        "* Turn retained: $($state.turn)"
        "* Added packs: $(if ($requestedPacks.Count) { $requestedPacks -join ', ' } else { '(none)' })"
        "* Added roles: $($addRoles -join ', ')"
        "* Already present: $(if ($alreadyPresent.Count) { $alreadyPresent -join ', ' } else { '(none)' })"
        "* Previous provenance: $provenance"
        "* Provenance: $nextProvenance"
        "* Rationale: $rationale"
        '* Accounting: no model or Scribe dispatch; consumption.md, consumption-sessions.json when present, state.json, rates, notifications, and history are preserved byte-for-byte.'
    ) -join "`n"
    $finalDecisions = Add-DecisionEntry -Before ([IO.File]::ReadAllBytes($decisionsPath)) -Entry $entry

    Assert-Baseline -Expected $baseline -Root $root -Repository $RepoRoot -RelativeRoot $relativeRoot
    $plan = [ordered]@{
        schemaVersion = 1
        squadRoot = $relativeRoot
        scope = $(if ($baseline.Contains('federation')) { 'federation-member' } else { 'plain-squad' })
        runId = $choices.runId
        generatedAt = $timestamp
        modelRouting = $mode
        packs = $requestedPacks.ToArray()
        requestedRoles = @($catalogOrder | Where-Object { $requestedRoles.Contains($_) })
        alreadyPresentRoles = $alreadyPresent
        addedRoles = $addRoles
        provenance = [ordered]@{ before = $provenance; after = $nextProvenance }
        baseline = $baseline
        outputs = [ordered]@{
            team = [ordered]@{
                bytes = $finalTeam.Length
                sha256 = Get-Hash $finalTeam
                contentBase64 = [Convert]::ToBase64String($finalTeam)
            }
            routing = [ordered]@{
                bytes = $finalRouting.Length
                sha256 = Get-Hash $finalRouting
                contentBase64 = [Convert]::ToBase64String($finalRouting)
            }
            decisions = [ordered]@{
                bytes = $finalDecisions.Length
                sha256 = Get-Hash $finalDecisions
                contentBase64 = [Convert]::ToBase64String($finalDecisions)
            }
        }
        routingRowsAdded = $routeLines.Count
    }
    $stateBoundary = [IO.Path]::GetFullPath((Join-Path $RepoRoot '.copilot-tracking' 'squad'))
    $destination = Write-SquadTransportJson -Path ([IO.Path]::GetFullPath($PayloadPath)) -SquadRoot $stateBoundary -Value $plan
    $sha = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    [ordered]@{
        status = 'planned'
        planPath = $destination
        planSha256 = $sha
        scope = $plan.scope
        squadRoot = $relativeRoot
        packs = $plan.packs
        addedRoles = $plan.addedRoles
        alreadyPresentRoles = $plan.alreadyPresentRoles
        routingRowsAdded = $plan.routingRowsAdded
        accountingPreserved = $true
        confirmationRequired = $true
        stateWritten = $false
    } | ConvertTo-Json -Depth 10 -Compress
    exit 0
}
catch {
    [Console]::Error.WriteLine("Get-SquadRosterExpansionPlan: $($_.Exception.Message)")
    exit 1
}
