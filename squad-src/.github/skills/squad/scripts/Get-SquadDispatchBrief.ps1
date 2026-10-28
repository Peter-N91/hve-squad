#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Prints, in one read-only call, everything a coordinator otherwise discovers turn by
    turn before a dispatch and its hand-off.
.DESCRIPTION
    AI cost: none; reads local state and references without dispatching a model.
    Each coordinator turn resends its whole context, so every discovery turn (reading
    agent files, the rate table, the roster, the hand-off format) is paid again on every
    later turn. This script gathers those facts deterministically and prints one compact
    Markdown brief:

      - status: current UTC time, PowerShell version, initialization, federation, cost
        ceiling, ledger shape (ok, stub, partial), the next hand-off `turn`, the model
        routing mode, and the concurrency cap (`COPILOT_SUBAGENT_MAX_CONCURRENT`, else 4);
      - roster: each role's agent, dispatchability, frontmatter model pin, its `team.md`
        `Model` cell (only when the roster has that column), the rate-table row and tier
        that price it, and its deliverable root, read from `team.md` by column header;
      - consumption: a ready ten-field consumption object per implementation- and
        review-class role, sized by the dispatch-size estimator floors in
        `references/consumption-rates-template.md`;
      - hand-off: the command line the coordinator runs synchronously for an ordinary write;
      - procedure: the verbatim Bounded Lane, Plan-Driven Parallelism, and Scripted Writes
        sections of `references/economy-mode.md`, so a bounded request needs no whole reference.

    Metadata is available in every routing mode. Only economy enables its existing
    Bounded Lane. -AsJson emits compact machine-readable data without procedure text
    or suggested consumption blocks. Federation roots return registry/meta-routing;
    absent state returns an Init pointer. The script writes nothing.
.PARAMETER SquadRoot
    The squad root (`.copilot-tracking/squad/`).
.PARAMETER RepoRoot
    The repository root that holds `.github/agents/`. Defaults to the current directory.
.PARAMETER SessionModel
    The coordinator's session model id, used for the orchestration consumption object.
.PARAMETER RequestedModelRouting
    The trusted user's routing input for this turn. Overrides the recorded mode in
    this read-only brief; it does not persist the change or authorize dispatch.
.PARAMETER AvailableModels
    The exact host-advertised model IDs, used only by the human-readable routing
    report. JSON mode defers scoring to New-SquadDispatchPlan.ps1.
.PARAMETER AsOf
    Evaluation date for the human-readable routing report; defaults to today.
.PARAMETER AsJson
    Compact metadata in every mode, including federation and uninitialized roots.
    Active model routing is marked deferred and is not scored in this discovery call.
.PARAMETER Roles
    Optional exact role IDs limiting roster and human-readable routing output, not
    changing policy.
.PARAMETER CheckLedger
    Run the trusted read-only ledger check once at turn start. Writer receipts replace
    repeated post-write audits; a shape check alone is never a ledger PASS.
.PARAMETER SnapshotPath
    Federation JSON only: explicitly save a new pre-dispatch transport snapshot
    outside squad state for Write-SquadFederationHandoff. Default remains read-only.
.EXAMPLE
    & .agents/skills/squad/scripts/Get-SquadDispatchBrief.ps1 -SquadRoot .copilot-tracking/squad -SessionModel claude-sonnet-5
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SquadRoot,

    [string]$RepoRoot = (Get-Location).Path,

    [string]$SessionModel,

    [ValidateSet('off', 'ranked', 'economy', 'manual')]
    [string]$RequestedModelRouting,

    [string[]]$AvailableModels = @(),

    [datetime]$AsOf = (Get-Date),

    [switch]$AsJson,

    [string[]]$Roles = @(),

    [switch]$CheckLedger,

    [string]$SnapshotPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$refs = Join-Path $skillRoot 'references'
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
$SquadRoot = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $SquadRoot -AllowMissing
$Roles = @($Roles | ForEach-Object { $_ -split ',' } | ForEach-Object Trim | Where-Object { $_ } | Select-Object -Unique)
if ($SnapshotPath -and (-not $AsJson -or -not (Test-Path -LiteralPath (Join-Path $SquadRoot 'federation.md')))) { throw 'SnapshotPath requires federation -AsJson output.' }
if (-not (Test-Path -LiteralPath $SquadRoot -PathType Container)) {
    if ($AsJson) {
        [ordered]@{ status = 'ok'; kind = 'none'; squadRoot = $SquadRoot; requestedModelRouting = $RequestedModelRouting; action = 'initialize'; reference = 'references/coordinator-init.md' } | ConvertTo-Json -Compress
        exit 0
    }
    Write-Error "Get-SquadDispatchBrief: squad root not found: $SquadRoot"
    exit 1
}
$SquadRoot = (Resolve-Path -LiteralPath $SquadRoot).Path
if ($AsJson -and (Test-Path -LiteralPath (Join-Path $SquadRoot 'federation.md') -PathType Leaf)) {
    $registryTables = @(Read-SquadTables (Join-Path $SquadRoot 'federation.md') | Where-Object { 'Sub-squad' -in $_.Header -and 'Location' -in $_.Header })
    $metaTables = @(Read-SquadTables (Join-Path $SquadRoot 'meta-routing.md') | Where-Object { 'Sub-squad' -in $_.Header -and 'Parallel-Eligible' -in $_.Header })
    if ($registryTables.Count -ne 1 -or $metaTables.Count -ne 1) { throw 'Federation registry/meta-routing table missing or ambiguous.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $registry = @(
        foreach ($row in $registryTables[0].Rows) {
            $name = $row['Sub-squad']
            if ($name -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or -not $seen.Add($name) -or
                ($row.Location -replace '\\', '/').TrimEnd('/') -cne "members/$name" -or $row.Kind -ne 'in-repo') {
                throw "Invalid, duplicate or unsupported federation member: $name"
            }
            $memberRoot = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $SquadRoot 'members' $name) -AllowMissing
            [ordered]@{ name = $name; profile = $row.Profile; owner = $row.Owner; description = $row.Description; squadRoot = $memberRoot; initialized = (Test-Path -LiteralPath (Join-Path $memberRoot 'team.md')) -and (Test-Path -LiteralPath (Join-Path $memberRoot 'routing.md')) }
        }
    )
    foreach ($row in $metaTables[0].Rows) {
        if (-not $seen.Contains($row['Sub-squad'])) { throw "Meta-route points to an unregistered squad: $($row['Sub-squad'])" }
    }
    $federationState = Get-Content -LiteralPath (Join-Path $SquadRoot 'state.json') -Raw | ConvertFrom-Json -AsHashtable
    $savedSnapshot = if ($SnapshotPath) {
        Write-SquadTransportJson -Path $SnapshotPath -SquadRoot $SquadRoot -Value (Get-SquadFederationSnapshot -SquadRoot $SquadRoot -RepoRoot $RepoRoot)
    } else { '' }
    [ordered]@{ status = 'ok'; kind = 'federation'; squadRoot = $SquadRoot; state = $federationState; registry = $registry; routing = $metaTables[0].Rows; requestedModelRouting = $RequestedModelRouting; snapshotPath = $savedSnapshot; reference = 'references/federation-runtime.md'; observedExecution = 'host-unreported' } | ConvertTo-Json -Depth 12 -Compress
    exit 0
}

function Get-SectionLines {
    param([string]$File, [string]$Heading)
    $lines = @(Get-Content -LiteralPath (Join-Path $refs $File) -Encoding utf8)
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].StartsWith($Heading)) { $start = $i; break } }
    if ($start -lt 0) { return $null }
    $level = ($Heading -split ' ')[0].Length
    $end = $start + 1
    while ($end -lt $lines.Count -and $lines[$end] -notmatch "^#{1,$level} ") { $end++ }
    , @($lines[$start..($end - 1)])
}

function Get-Section {
    param([string]$File, [string]$Heading)
    $lines = Get-SectionLines -File $File -Heading $Heading
    if ($null -eq $lines) { return "(section '$Heading' not found in $File; read the file)" }
    ($lines -join "`n").TrimEnd()
}

function Split-TableLine {
    param([string]$Line)
    , @($Line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim().Trim('`').Trim() })
}

function Get-TableRows {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    @(Get-Content -LiteralPath $Path -Encoding utf8 | Where-Object { $_ -match '^\|' -and $_ -notmatch '^\|\s*:?-' } |
            ForEach-Object { , (Split-TableLine $_) })
}

function Get-MarkdownTablesForPath {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $tables = [System.Collections.Generic.List[pscustomobject]]::new()
    $tableLines = $null
    foreach ($line in (@(Get-Content -LiteralPath $Path -Encoding utf8) + '')) {
        if ($line -match '^\s*\|') {
            if ($null -eq $tableLines) { $tableLines = [System.Collections.Generic.List[string]]::new() }
            $tableLines.Add($line)
            continue
        }
        if ($null -eq $tableLines) { continue }
        $rows = [System.Collections.Generic.List[hashtable]]::new()
        $header = Split-TableLine $tableLines[0]
        foreach ($rowLine in ($tableLines | Select-Object -Skip 1)) {
            if ($rowLine -match '^\s*\|\s*:?-') { continue }
            $cells = Split-TableLine $rowLine
            $row = @{}
            for ($i = 0; $i -lt $header.Count; $i++) { $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' } }
            $rows.Add($row)
        }
        $tables.Add([pscustomobject]@{ Header = $header; Rows = $rows })
        $tableLines = $null
    }
    return $tables.ToArray()
}

function Get-Roster {
    # Members table of team.md as hashtables keyed by column header.
    param([string]$Path)
    $tables = @(Get-MarkdownTablesForPath -Path $Path)
    $membersTable = @($tables | Where-Object { 'Role' -in $_.Header } | Select-Object -First 1)
    if ($membersTable.Count -eq 0) {
        return [pscustomobject]@{ Header = @(); Rows = @(); ConnectorBindings = @() }
    }

    $connectorHeader = @('Binding ID', 'Connector ID', 'Manifest', 'Endpoint Kind', 'Role Mode', 'Target Kind', 'Target', 'Member Name', 'Added Role', 'Aligned Role', 'Default Execution')
    $connectorTable = @(
        $tables | Where-Object {
            $table = $_
            @($connectorHeader | Where-Object { $_ -in $table.Header }).Count -eq $connectorHeader.Count
        } | Select-Object -First 1
    )
    $connectorBindings = [System.Collections.Generic.List[pscustomobject]]::new()
    if ($connectorTable.Count -gt 0) {
        foreach ($raw in $connectorTable[0].Rows) {
            $bindingId = ([string]$raw['Binding ID']).Trim().Trim('`').Trim()
            if (-not $bindingId -or $bindingId -in '—', '-') { continue }
            $connectorBindings.Add([pscustomobject]@{
                    BindingId   = $bindingId
                    RoleMode    = ([string]$raw['Role Mode']).Trim().Trim('`').Trim().ToLowerInvariant()
                    MemberName  = ([string]$raw['Member Name']).Trim().Trim('`').Trim()
                    AddedRole   = ([string]$raw['Added Role']).Trim().Trim('`').Trim().ToLowerInvariant()
                    AlignedRole = ([string]$raw['Aligned Role']).Trim().Trim('`').Trim().ToLowerInvariant()
                })
        }
    }

    [pscustomobject]@{ Header = @($membersTable[0].Header); Rows = $membersTable[0].Rows; ConnectorBindings = $connectorBindings.ToArray() }
}

function Get-Cell {
    param([hashtable]$Row, [string[]]$Names)
    foreach ($name in $Names) {
        if ($Row.ContainsKey($name)) {
            $value = $Row[$name]
            if ($value -and $value -notin '—', '-') { return $value }
            return ''
        }
    }
    ''
}

function Resolve-ConnectorAlignedClassForBrief {
    param(
        [Parameter(Mandatory)]$Binding,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Bindings,
        [Parameter(Mandatory)][hashtable]$ClassMap,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$Seen,
        [Parameter(Mandatory)][string]$Context
    )
    $bindingId = [string]$Binding.BindingId
    if ([string]::IsNullOrWhiteSpace($bindingId)) { throw "Get-SquadDispatchBrief: connector alignment error ($Context): binding has no Binding ID." }
    if ($Seen.Contains($bindingId)) { throw "Get-SquadDispatchBrief: connector alignment error ($Context): cyclic Aligned Role chain at binding '$bindingId'." }

    $alignedRole = ([string]$Binding.AlignedRole).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($alignedRole)) { throw "Get-SquadDispatchBrief: connector alignment error ($Context): binding '$bindingId' is missing Aligned Role." }
    if ($ClassMap.ContainsKey($alignedRole)) { return [pscustomobject]@{ Class = $ClassMap[$alignedRole]; Source = "connector-aligned: $alignedRole" } }

    $null = $Seen.Add($bindingId)
    try {
        $next = @($Bindings | Where-Object { $_.RoleMode -eq 'add' -and $_.AddedRole -eq $alignedRole })
        if ($next.Count -eq 0) { throw "Get-SquadDispatchBrief: connector alignment error ($Context): aligned role '$alignedRole' has no assignment class mapping." }
        if ($next.Count -gt 1) { throw "Get-SquadDispatchBrief: connector alignment error ($Context): aligned role '$alignedRole' is ambiguous across $($next.Count) connector bindings." }
        return Resolve-ConnectorAlignedClassForBrief -Binding $next[0] -Bindings $Bindings -ClassMap $ClassMap -Seen $Seen -Context $Context
    }
    finally {
        $null = $Seen.Remove($bindingId)
    }
}

$out = [System.Collections.Generic.List[string]]::new()
$utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$out.Add('# Squad Dispatch Brief')
$out.Add('')
$out.Add("utc: $utc | pwsh: $($PSVersionTable.PSVersion) | squadRoot: $SquadRoot | skill: $skillRoot")

$teamPath = Join-Path $SquadRoot 'team.md'
$statePath = Join-Path $SquadRoot 'state.json'
if (-not (Test-Path -LiteralPath $teamPath) -or -not (Test-Path -LiteralPath $statePath)) {
    if ($AsJson) {
        [ordered]@{ status = 'ok'; kind = 'uninitialized'; squadRoot = $SquadRoot; requestedModelRouting = $RequestedModelRouting; action = 'initialize'; reference = 'references/coordinator-init.md' } | ConvertTo-Json -Compress
        exit 0
    }
    $out.Add('status: NOT INITIALIZED. This brief does not cover Init: read the three reference files whole.')
    $out -join "`n"
    exit 0
}

$stateText = Get-Content -LiteralPath $statePath -Raw -Encoding utf8
$state = $stateText | ConvertFrom-Json -AsHashtable
$turn = [int]$state['turn']
# ConvertFrom-Json turns ISO strings into local DateTime values; print the stored text.
$updated = if ($stateText -match '"updated"\s*:\s*"([^"]*)"') { $Matches[1] } else { '' }
$federated = (Test-Path -LiteralPath (Join-Path $SquadRoot 'federation.md')) -or ($SquadRoot -match '[\\/]members[\\/][^\\/]+[\\/]?$')
$preflight = if ($state['currentRun'] -is [hashtable]) { $state['currentRun']['costPreflight'] } else { $null }
$ceiling = $null -ne $preflight -and ($null -ne $preflight['ceilingUsd'] -or ($preflight['decision'] -and $preflight['decision'] -ne 'not-requested'))

$ledgerPath = Join-Path $SquadRoot 'consumption.md'
$ledgerText = if (Test-Path -LiteralPath $ledgerPath) { Get-Content -LiteralPath $ledgerPath -Raw -Encoding utf8 } else { '' }
$sections = @('## Attribution', '## Usage & Cost', '### Derivation' | Where-Object { $ledgerText -match "(?m)^$([regex]::Escape($_))\s*$" })
$ledger = switch ($sections.Count) { 3 { 'ok' } 0 { 'stub (do not dispatch the Scribe to repair it; the next script hand-off reseeds it)' } default { 'partial (reconcile through the Squad Scribe first)' } }

$teamText = Get-Content -LiteralPath $teamPath -Raw -Encoding utf8
$recordedRouting = if ($teamText -match '(?m)^Model routing:\s*`?(?<mode>[a-z]+)`?\s*$') { $Matches['mode'] } else { 'off' }
$routing = if ($RequestedModelRouting) { $RequestedModelRouting } else { $recordedRouting }

$capText = $env:COPILOT_SUBAGENT_MAX_CONCURRENT
$cap = if ($capText -match '^\d+$' -and [int]$capText -gt 0) { [int]$capText } else { 4 }

$covered = $routing -eq 'economy' -and $routing -eq $recordedRouting -and -not $federated -and -not $ceiling
$out.Add("state: schema $($state['schemaVersion']), turn $turn (next hand-off turn: $($turn + 1)), mode $($state['mode']), updated $updated")
$out.Add("federation: $(if ($federated) { 'yes' } else { 'no' }) | cost ceiling: $(if ($ceiling) { 'active' } else { 'none' }) | ledger: $ledger | model routing: $routing | concurrency cap: $cap")
if ($RequestedModelRouting) { $out.Add("routing intent: requested $RequestedModelRouting; recorded $recordedRouting. Prepare the selected role units before dispatch; this brief is not a dispatch plan.") }
# economy-mode.md Consent (the same check Resolve-SquadModelRoute.ps1 and Write-SquadHandoff.ps1 make) and Route Markers.
$decisionsPath = Join-Path $SquadRoot 'decisions.md'
$decisionsText = if (Test-Path -LiteralPath $decisionsPath -PathType Leaf) { [string](Get-Content -LiteralPath $decisionsPath -Raw -Encoding utf8) } else { '' }
$consent = if ($decisionsText -match '(?m)^## Economy Mode Accepted\b') { 'recorded' } else { 'missing' }
if ($routing -eq 'economy') { $out.Add("consent: $consent") }
if ($routing -eq 'economy' -and $consent -eq 'missing') {
    $out.Add('WARN economy consent not recorded: before any dispatch, state the trade once (economy-mode.md Consent) and hand the Scribe the ## Economy Mode Accepted decision with the roster refresh.')
}
if ($routing -eq 'economy') { $out.Add('route markers: every history record needs routingIdentity whose routeRationale starts with Route: economy, or Route: bounded on the Bounded Lane (economy-mode.md Route Markers).') }
if ($covered) {
    $out.Add('coverage: for a request that meets every Bounded Lane criterion below, this brief replaces reading 00-index.md, operating-procedure.md, gates-and-modes.md, economy-mode.md, agent files, and the rate table. Any other request: read the reference files whole.')
}
else {
    $out.Add('coverage: NONE for the economy bounded lane (other mode, federation or active ceiling). Use metadata and read only the applicable gate/mode procedures.')
}

# Read the full frontmatter block; long allowlists can put metadata beyond line 40.
$pins = @{}
$blocked = @{}
$agentIndex = Get-SquadAgentIndex $RepoRoot
foreach ($agent in $agentIndex.Values) {
    $pins[$agent.name] = $agent.model -replace '\s*\(copilot\)\s*$', ''
    $blocked[$agent.name] = -not $agent.dispatchable
}

# Per-model rate rows only (the tier fallback table has a number in its third column): the squad root's, then the template's.
$isModelRow = { param($r) $r.Count -ge 7 -and $r[0] -ne 'Model (as routed)' -and $r[2] -notmatch '^\d' -and $r[3] -match '^\d' }
$rates = @(Get-TableRows (Join-Path $SquadRoot 'consumption-rates.md') | Where-Object { & $isModelRow $_ }) +
@(Get-TableRows (Join-Path $refs 'consumption-rates-template.md') | Where-Object { & $isModelRow $_ })
function Find-Rate {
    param([string]$Model)
    if (-not $Model) { return $null }
    $key = $Model.ToLowerInvariant().Trim()
    if ($key -in @('hydrafusion', 'hydrafusion-balance', 'hydrafusion-efficiency')) { $key = 'hydrafusion-max' }
    foreach ($row in $rates) { if ($row[0].ToLowerInvariant() -eq $key -or $row[1].ToLowerInvariant() -eq $key) { return $row } }
    $null
}

# Role-to-class map from model-routing.md's Assignment Classes table; an unlisted role counts as implementation.
$classes = @{}
$routingRef = Join-Path $refs 'model-routing.md'
if (Test-Path -LiteralPath $routingRef) {
    $classText = Get-Content -LiteralPath $routingRef -Raw -Encoding utf8
    $classSection = [regex]::Match($classText, '(?ms)^## Assignment Classes\s*\r?\n(?<body>.*?)(?=^## )').Groups['body'].Value
    foreach ($line in ($classSection -split '\r?\n')) {
        $m = [regex]::Match($line, '^\|\s*`(?<class>[a-z]+)`\s*\|(?<roles>.*)\|\s*$')
        if (-not $m.Success) { continue }
        foreach ($r in [regex]::Matches($m.Groups['roles'].Value, '`([a-z][a-z0-9-]*)`')) {
            if (-not $classes.ContainsKey($r.Groups[1].Value)) { $classes[$r.Groups[1].Value] = $m.Groups['class'].Value }
        }
    }
}

$estimator = @{
    research       = @(12, 40000, 4000, 1250)
    planning       = @(15, 60000, 4000, 2000)
    implementation = @(35, 60000, 6000, 2000)
    review         = @(18, 50000, 4000, 1500)
    bookkeeping    = @(4, 15000, 3000, 800)
}
function New-Consumption {
    param([string]$Model, [string]$Source, [string]$Class)
    $floor = if ($estimator.ContainsKey($Class)) { $estimator[$Class] } else { $estimator['implementation'] }
    $t, $base, $growth, $perTurn = $floor
    $isHydra = ($Model -match '(?i)^hydrafusion')
    $tokenFactor = if ($isHydra) { 0.35 } else { 1.0 }
    $gross = $t * ($base + $growth * ($t - 1) / 2) * $tokenFactor
    $rate = Find-Rate $Model
    [ordered]@{
        model              = $Model
        model_source       = $Source
        priced_as          = if ($rate) { $rate[0] } else { '' }
        model_tier         = if ($rate) { $rate[2] } else { 'default' }
        internal_turns     = $t
        input_tokens       = [long][math]::Round($gross * 0.2)
        cached_tokens      = [long][math]::Round($gross * 0.8)
        cache_write_tokens = if ($Model -match 'claude' -or $isHydra) { [long][math]::Round(($base + $growth * ($t - 1)) * $tokenFactor) } else { 0 }
        output_tokens      = [long]($t * $perTurn)
        basis              = 'estimated'
    }
}

$roster = Get-Roster $teamPath
if ($Roles.Count) {
    foreach ($role in $Roles) {
        if ($role -cnotin @($roster.Rows | ForEach-Object { $_['Role'] })) { throw "Role not on roster: $role" }
    }
    $roster.Rows = @($roster.Rows | Where-Object { $_['Role'] -cin $Roles })
}
$agentColumns = @('Agent Name (Primary)', 'Primary Agent', 'Primary', 'Agent')
$hasModel = $routing -ne 'off' -and $roster.Header -contains 'Model'
$out.Add('')
$out.Add('## Roster')
$out.Add('')
$out.Add('Resolve the roster Agent name to the host-advertised custom-agent type; a display name is not necessarily its API id. Use native dispatch, never `general-purpose`, `task`, or another built-in substitute.')
if ($hasModel) { $out.Add('Pass each role''s Model cell as the dispatch `model` exactly as written; an empty cell passes no `model`. Scribe exception: omit the parameter so its explicit pin governs. Coordinators keep the selected session model.') }
$out.Add('')
if ($hasModel) {
    $out.Add('| Role | Agent | Dispatchable | Pin | Model | Priced as (tier) | Deliverable root |')
    $out.Add('| ---- | ----- | ------------ | --- | ----- | ---------------- | ---------------- |')
}
else {
    $out.Add('| Role | Agent | Dispatchable | Pin | Priced as (tier) | Deliverable root |')
    $out.Add('| ---- | ----- | ------------ | --- | ---------------- | ---------------- |')
}
$consumption = [System.Collections.Generic.List[string]]::new()
$unreachable = [System.Collections.Generic.List[string]]::new()
foreach ($row in $roster.Rows) {
    $role = Get-Cell $row @('Role')
    $agent = Get-Cell $row $agentColumns
    if (-not $role -or -not $agent) { continue }
    $root = Get-Cell $row @('Deliverable Root')
    $cell = if ($hasModel) { Get-Cell $row @('Model') } else { '' }
    $alternates = Get-Cell $row @('Alternate Agents')
    $pin = if ($pins.ContainsKey($agent)) { $pins[$agent] } else { $null }
    $pinText = if ($null -eq $pin) { 'agent file not found' } elseif ($pin) { $pin } else { 'none (session-inherited)' }
    $runs = if ($role -eq 'scribe' -and $pin) { $pin } elseif ($cell) { $cell } elseif ($pin) { $pin } else { $SessionModel }
    $rate = Find-Rate $runs
    $priced = if ($rate) { "$($rate[0]) ($($rate[2]))" } elseif ($runs) { 'no rate row' } else { 'session model' }
    $alts = if ($alternates) { " (alternates: $alternates; cue: $(Get-Cell $row @('Selection Cue')))" } else { '' }
    $reach = if ($null -eq $pin) { 'no (not installed)' } elseif ($blocked[$agent]) { 'no (disable-model-invocation)' } else { 'yes' }
    if ($reach -ne 'yes') { $unreachable.Add("$role -> $agent") }
    foreach ($alt in @($alternates -split ',' | ForEach-Object { $_.Trim().Trim('`').Trim() } | Where-Object { $_ -and $_ -notin '—', '-' })) {
        if (-not $pins.ContainsKey($alt)) { $unreachable.Add("$role alternate -> $alt (not installed)") }
        elseif ($blocked[$alt]) { $unreachable.Add("$role alternate -> $alt (disable-model-invocation)") }
    }
    $modelCol = if ($hasModel) { " $(if ($cell) { $cell } else { 'none' }) |" } else { '' }
    $out.Add("| $role | $agent$alts | $reach | $pinText |$modelCol $priced | $root |")
    $class = if ($classes.ContainsKey($role)) { $classes[$role] } else { 'implementation' }
    if ($agent -ceq 'Squad Connector') {
        $member = Get-Cell $row @('Member Name')
        if (-not $member) {
            throw "Get-SquadDispatchBrief: connector alignment error (role '$role'): connector-backed row is missing Member Name."
        }
        $bindingRows = @($roster.ConnectorBindings | Where-Object {
                $_.RoleMode -eq 'add' -and $_.AddedRole -eq $role.ToLowerInvariant() -and $_.MemberName -ceq $member
            })
        if ($bindingRows.Count -gt 1) {
            throw "Get-SquadDispatchBrief: connector alignment error (role '$role', member '$member'): $($bindingRows.Count) matching add bindings found."
        }
        if ($bindingRows.Count -eq 1) {
            $aligned = Resolve-ConnectorAlignedClassForBrief -Binding $bindingRows[0] -Bindings @($roster.ConnectorBindings) -ClassMap $classes -Seen ([System.Collections.Generic.HashSet[string]]::new([System.Collections.Generic.IEqualityComparer[string]][System.StringComparer]::OrdinalIgnoreCase)) -Context "role '$role', member '$member'"
            $class = $aligned.Class
        }
    }
    if ($reach -ne 'yes' -or $class -notin 'implementation', 'review' -or -not $runs) { continue }
    if ($cell) {
        $c = New-Consumption -Model $cell -Source 'cli-pinned' -Class $class
        $consumption.Add("- $role on its Model cell (add ``""passedModel"": ""$cell""``): $($c | ConvertTo-Json -Compress)")
    }
    elseif ($pin) {
        $c = New-Consumption -Model $pin -Source 'agent-pinned' -Class $class
        $consumption.Add("- $role on its pin: $($c | ConvertTo-Json -Compress)")
    }
    else {
        $sessionRate = Find-Rate $SessionModel
        $c = New-Consumption -Model $(if ($sessionRate) { $sessionRate[0] } else { $SessionModel }) -Source 'session-inherited' -Class $class
        $consumption.Add("- $role on the session model: $($c | ConvertTo-Json -Compress)")
    }
}
$out.Add('')
$out.Add($(if ($unreachable.Count -eq 0) { 'roster precheck (Step 1b): PASS, every Primary and Alternate is installed and dispatchable; no agent-file read is needed.' } else { "roster precheck (Step 1b): FAIL for $($unreachable -join ', '); escalate before dispatching those roles." }))

$routeReport = if ($routing -eq 'off') {
    [pscustomobject]@{ scoringPolicy = 'off'; snapshotIdentity = 'not-evaluated'; evaluationDate = $AsOf.ToString('yyyy-MM-dd'); availability = 'not-evaluated'; roles = @(); warnings = @() }
}
elseif ($AsJson) {
    [pscustomobject]@{ scoringPolicy = 'deferred-to-dispatch-plan'; snapshotIdentity = 'not-evaluated'; evaluationDate = $AsOf.ToString('yyyy-MM-dd'); availability = 'deferred'; roles = @(); warnings = @() }
}
else {
    & (Join-Path $PSScriptRoot 'Resolve-SquadModelRoute.ps1') -SquadRoot $SquadRoot -Mode $routing -AvailableModels $AvailableModels -SessionModel $SessionModel -Role $Roles -AsOf $AsOf | ConvertFrom-Json
}
if ($AsJson) {
    $ledgerCheck = [ordered]@{ status = 'not-run'; failureClass = ''; output = '' }
    if ($CheckLedger) {
        $check = Invoke-SquadLocalScript -Name 'Measure-SquadLedger.ps1' -Arguments @('-SquadRoot', $SquadRoot, '-Check')
        $checkText = ($check.stdout + $check.stderr) -replace '\x1b\[[0-9;]*[A-Za-z]', ''
        $failure = [regex]::Match($checkText, 'failure class:\s*(?<class>[a-z-]+)')
        $ledgerCheck.status = if ($check.exitCode -eq 0 -and $checkText -match 'Measure-SquadLedger -Check: PASS') { 'PASS' } else { 'FAIL' }
        $ledgerCheck.failureClass = if ($failure.Success) { $failure.Groups['class'].Value } else { '' }
        $ledgerCheck.output = if ($ledgerCheck.status -eq 'PASS') { '' } else { $checkText.Trim() }
    }
    $records = @(
        foreach ($row in $roster.Rows) {
            $name = Get-Cell $row $agentColumns
            $item = [ordered]@{
                role = Get-Cell $row @('Role')
                memberName = Get-Cell $row @('Member Name')
                agent = $name
            }
            if ($Roles.Count) {
                $item.installed = $agentIndex.ContainsKey($name)
                $item.dispatchable = $agentIndex.ContainsKey($name) -and $agentIndex[$name].dispatchable
                $item.pin = $(if ($agentIndex.ContainsKey($name)) { $agentIndex[$name].model } else { '' })
                $item.model = $(if ($routing -ne 'off') { Get-Cell $row @('Model') } else { '' })
                $item.tier = Get-Cell $row @('Model Tier')
                $item.deliverableRoot = Get-Cell $row @('Deliverable Root')
                $item.alternates = Get-Cell $row @('Alternate Agents')
                $item.selectionCue = Get-Cell $row @('Selection Cue')
            }
            $item
        }
    )
    $routes = @(
        foreach ($route in $routeReport.roles) {
            if ($Roles.Count -and $route.role -cnotin $Roles) { continue }
            $item = [ordered]@{ role = $route.role; persisted = $route.modelCell; suggested = $route.suggested }
            if ($Roles.Count) { $item.rationale = $route.rationale }
            if ($route.PSObject.Properties['escalation']) { $item.escalation = $route.escalation }
            $item
        }
    )
    $routingTables = @(Read-SquadTables (Join-Path $SquadRoot 'routing.md') | Where-Object { 'Role(s)' -in $_.Header })
    if ($routingTables.Count -ne 1) { throw 'Expected exactly one request routing table.' }
    $requestRoutes = @($routingTables[0].Rows)
    if ($Roles.Count) {
        $requestRoutes = @($requestRoutes | Where-Object {
            @($_['Role(s)'] -split ',\s*' | ForEach-Object { $_ -replace ' \(optional\)$', '' } | Where-Object { $_ -cin $Roles }).Count -gt 0
        })
    }
    $profileMatch = [regex]::Matches($decisionsText, '(?m)^\* (?:Provenance|Profile):[ \t]*(?<value>[^\r\n]+)')
    $provenance = if ($profileMatch.Count) { $profileMatch[-1].Groups['value'].Value.Trim() } else { '' }
    [ordered]@{
        status = 'ok'
        kind = $(if ($federated) { 'member' } else { 'squad' })
        squadRoot = $SquadRoot
        turn = $turn
        nextTurn = $turn + 1
        updated = $updated
        mode = $state['mode']
        recordedModelRouting = $recordedRouting
        requestedModelRouting = $RequestedModelRouting
        modelRouting = $routing
        dispatchReady = $false
        dispatchPreparation = $(if ($RequestedModelRouting -eq 'off' -and $recordedRouting -ne 'off') { 'cold-scribe-routing-off' } else { 'New-SquadDispatchPlan.ps1 -ApplyModelRouting' })
        costPreflight = $preflight
        ledgerCheck = $ledgerCheck
        roster = $records
        routing = $requestRoutes
        modelRoutes = $routes
        modelPolicy = $routeReport.scoringPolicy
        modelRoutingDeferred = $routing -ne 'off'
        observedExecution = 'host-unreported'
        provenance = $provenance
        gates = 'not-evaluated'
        economyConsent = $(if ($routing -eq 'economy') { $consent } else { 'not-applicable' })
        boundedLaneEligible = $covered -and $state['mode'] -eq 'interactive'
        concurrencyCap = $cap
        pendingConnectorTasks = @(Get-SquadPendingConnectors -RepoRoot $RepoRoot -SquadRoot $SquadRoot)
        reference = 'references/coordinator-runtime.md'
    } | ConvertTo-Json -Depth 12 -Compress
    exit 0
}
$out.Add('')
$out.Add('## Routing report (advisory until the Scribe persists changed Model cells)')
$out.Add("Policy $($routeReport.scoringPolicy); snapshot $($routeReport.snapshotIdentity); evaluated $($routeReport.evaluationDate); availability $($routeReport.availability). Execution is host-unreported, not observed by this brief.")
foreach ($warning in @($routeReport.warnings | Where-Object { $_ -notlike 'economy consent*' })) {
    $out.Add("WARN routing: $warning")
}
foreach ($route in $routeReport.roles) {
    $escalationText = if ($route.PSObject.Properties['escalation']) { "; escalation: $($route.escalation) ($($route.escalationReason))" } else { '' }
    $out.Add("- $($route.role) [$($route.selectionObjective)], suggested $($route.suggested), persisted '$($route.modelCell)': Route rationale: $($route.rationale)$escalationText.")
}
$reportedClasses = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($route in $routeReport.roles) {
    if (-not $reportedClasses.Add($route.class)) { continue }
    if (-not $route.PSObject.Properties['evidenceCandidates']) { continue }
    foreach ($candidate in @($route.evidenceCandidates | Where-Object evidenceStatus -ne 'sufficient')) {
        $issues = @(
            foreach ($item in @($candidate.evaluations | Where-Object { $_.status -notin @('verified', 'older-valid-result') })) {
                if ($item.status -eq 'missing-evaluation') { "$($item.evaluation): missing exact-model result" }
                elseif ($item.status -eq 'verification-expired') { "$($item.evaluation): verification/cache expired since $($item.verified)" }
                elseif ($item.status -eq 'unverified') {
                    $unknown = @(
                        if ($item.modelVersion -eq 'unknown') { 'model' }
                        if ($item.configuration -eq 'unknown') { 'configuration' }
                        if ($item.verified -eq 'unknown') { 'verification' }
                        if ($item.retrieved -eq 'unknown') { 'acquisition' }
                        if ($item.sourceUrl -eq 'unknown') { 'source' }
                        if ($item.verificationBasis -eq 'unknown') { 'proof' }
                    )
                    if ($unknown.Count) { "$($item.evaluation): unverified ($($unknown -join ', ') unknown)" }
                    else { "$($item.evaluation): unverified ($($item.reason))" }
                }
                else { "$($item.evaluation): $($item.status) ($($item.reason))" }
            }
        )
        $out.Add("- Evidence exclusion $($route.class)/$($candidate.id): $($issues -join '; ').")
    }
}

$out.Add('')
$out.Add('## Consumption objects (estimator floors; raise internal_turns when the dispatch reported more)')
$out.Add('')
$consumption | ForEach-Object { $out.Add($_) }
if ($SessionModel) {
    $sessionRate = Find-Rate $SessionModel
    $c = New-Consumption -Model $(if ($sessionRate) { $sessionRate[0] } else { $SessionModel }) -Source 'session-inherited' -Class 'planning'
    $out.Add("- orchestration (set internal_turns to your own turn count): $($c | ConvertTo-Json -Compress)")
}

$out.Add('')
$out.Add('## Hand-off')
$out.Add('')
$out.Add("Payload ``turn`` = $($turn + 1); ``timestamp`` = the current UTC time when you fill it (this brief's utc is $utc).")
$out.Add('For a supported ordinary hand-off, save minimal structured JSON per `references/economy-scribe.md` outside the squad root, then run the validated writer directly and synchronously. Do not dispatch the Scribe for this write:')
$payloadContract = Get-Section 'economy-scribe.md' '## Payload Contract'
if ($payloadContract -match "^\(section '## Payload Contract' not found") {
    throw "Required ordinary hand-off payload contract is missing from references/economy-scribe.md."
}
$out.Add($payloadContract)
$out.Add('')
$out.Add("``pwsh -NoProfile -File '$(Join-Path $PSScriptRoot 'Write-SquadHandoff.ps1')' -SquadRoot '$SquadRoot' -PayloadPath <payload.json> -Quiet``")
$out.Add('Validate the returned status, turn, and history counts; preserve stderr warnings and distinguish `ledger-only` from `PASS`. Use the Squad Scribe for cold operations.')

$out.Add('')
if ($routing -eq 'economy') {
    $out.Add('## Procedure (verbatim, economy-mode.md)')
    $out.Add('')
    $out.Add((Get-Section 'economy-mode.md' '## Bounded Lane'))
    $out.Add('')
    $out.Add((Get-Section 'economy-mode.md' '## Plan-Driven Parallelism'))
    $out.Add('')
}
$out.Add((Get-Section 'economy-mode.md' '## Scripted Writes'))

$text = $out -join "`n"
# The CLI spills shell output over 20,480 bytes to a temp file, costing extra read turns.
$limit = 20480
if ($env:COPILOT_LARGE_OUTPUT_THRESHOLD_BYTES -match '^\d+$') { $limit = [int]$env:COPILOT_LARGE_OUTPUT_THRESHOLD_BYTES }
if ([Text.Encoding]::UTF8.GetByteCount($text) -gt $limit) {
    [Console]::Error.WriteLine("WARN brief exceeds the $limit-byte inline output limit; the host will save it to a file")
}
$text
exit 0
