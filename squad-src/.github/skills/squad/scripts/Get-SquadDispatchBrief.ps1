#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Prints, in one read-only call, everything a coordinator otherwise discovers turn by
    turn before a dispatch and its hand-off.
.DESCRIPTION
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
      - hand-off: the `Write-SquadHandoff.ps1` command line the Squad Scribe runs;
      - procedure: the verbatim Bounded Lane, Plan-Driven Parallelism, and Scripted Writes
        sections of `references/economy-mode.md` (the hand-off payload shape and a complete
        example), so a bounded request needs no whole reference file.

    Economy only (references/economy-mode.md): it reads `team.md` first and refuses with
    exit 7 unless it records `Model routing: economy`.

    It never picks a model: the roster's `Model` cell, the agent pin, or the session model
    is what each dispatch runs on. The script writes nothing. Exit codes: 0 brief printed;
    1 usage error; 7 refused, not economy (the coordinator reads its references as in v0.18.1).
.PARAMETER SquadRoot
    The squad root (`.copilot-tracking/squad/`).
.PARAMETER RepoRoot
    The repository root that holds `.github/agents/`. Defaults to the current directory.
.PARAMETER SessionModel
    The coordinator's session model id, used for the orchestration consumption object.
.EXAMPLE
    & .agents/skills/squad/scripts/Get-SquadDispatchBrief.ps1 -SquadRoot .copilot-tracking/squad -SessionModel claude-sonnet-5
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SquadRoot,

    [string]$RepoRoot = (Get-Location).Path,

    [string]$SessionModel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$refs = Join-Path $skillRoot 'references'
if (-not (Test-Path -LiteralPath $SquadRoot -PathType Container)) {
    Write-Error "Get-SquadDispatchBrief: squad root not found: $SquadRoot"
    exit 1
}
$SquadRoot = (Resolve-Path -LiteralPath $SquadRoot).Path
$routingTeam = Join-Path $SquadRoot 'team.md'
$routingMode = 'off'
if (Test-Path -LiteralPath $routingTeam -PathType Leaf) {
    $routingMatch = [regex]::Match([System.IO.File]::ReadAllText($routingTeam), '(?m)^Model routing:\s*`?(?<mode>off|ranked|economy|manual)`?\s*$')
    if ($routingMatch.Success) { $routingMode = $routingMatch.Groups['mode'].Value }
}
if ($routingMode -ne 'economy') {
    [Console]::Error.WriteLine("Get-SquadDispatchBrief: refused: $routingTeam records Model routing: $routingMode, not economy. The dispatch brief is economy-only; read the references as the coordinator charter lists them.")
    exit 7
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

function Get-Roster {
    # Members table of team.md as hashtables keyed by column header.
    param([string]$Path)
    $lines = @(Get-Content -LiteralPath $Path -Encoding utf8)
    $header = $null
    $rows = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($line in $lines) {
        if ($line -notmatch '^\s*\|') {
            if ($header -and $rows.Count -gt 0) { break }
            $header = $null
            continue
        }
        if ($line -match '^\s*\|\s*:?-') { continue }
        $cells = Split-TableLine $line
        if (-not $header) {
            if ($cells -contains 'Role') { $header = $cells }
            continue
        }
        $row = @{}
        for ($i = 0; $i -lt $header.Count; $i++) { $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' } }
        $rows.Add($row)
    }
    [pscustomobject]@{ Header = @($header); Rows = $rows }
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

$out = [System.Collections.Generic.List[string]]::new()
$utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$out.Add('# Squad Dispatch Brief')
$out.Add('')
$out.Add("utc: $utc | pwsh: $($PSVersionTable.PSVersion) | squadRoot: $SquadRoot | skill: $skillRoot")

$teamPath = Join-Path $SquadRoot 'team.md'
$statePath = Join-Path $SquadRoot 'state.json'
if (-not (Test-Path -LiteralPath $teamPath) -or -not (Test-Path -LiteralPath $statePath)) {
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
$routing = if ($teamText -match '(?m)^Model routing:\s*`?(?<mode>[a-z]+)`?\s*$') { $Matches['mode'] } else { 'off' }

$capText = $env:COPILOT_SUBAGENT_MAX_CONCURRENT
$cap = if ($capText -match '^\d+$' -and [int]$capText -gt 0) { [int]$capText } else { 4 }

$covered = -not $federated -and -not $ceiling
$out.Add("state: schema $($state['schemaVersion']), turn $turn (next hand-off turn: $($turn + 1)), mode $($state['mode']), updated $updated")
$out.Add("federation: $(if ($federated) { 'yes' } else { 'no' }) | cost ceiling: $(if ($ceiling) { 'active' } else { 'none' }) | ledger: $ledger | model routing: $routing | concurrency cap: $cap")
# economy-mode.md Consent (the same check Resolve-SquadModelRoute.ps1 and Write-SquadHandoff.ps1 make) and Route Markers.
$decisionsPath = Join-Path $SquadRoot 'decisions.md'
$decisionsText = if (Test-Path -LiteralPath $decisionsPath -PathType Leaf) { [string](Get-Content -LiteralPath $decisionsPath -Raw -Encoding utf8) } else { '' }
$consent = if ($decisionsText -match '(?m)^## Economy Mode Accepted\b') { 'recorded' } else { 'missing' }
$out.Add("consent: $consent")
if ($consent -eq 'missing') {
    $out.Add('WARN economy consent not recorded: before any dispatch, state the trade once (economy-mode.md Consent) and hand the Scribe the ## Economy Mode Accepted decision with the roster refresh.')
}
$out.Add('route markers: every history record needs routingIdentity whose routeRationale starts with Route: economy, or Route: bounded on the Bounded Lane (economy-mode.md Route Markers).')
if ($covered) {
    $out.Add('coverage: for a request that meets every Bounded Lane criterion below, this brief replaces reading 00-index.md, operating-procedure.md, gates-and-modes.md, economy-mode.md, agent files, and the rate table. Any other request: read the reference files whole.')
}
else {
    $out.Add('coverage: NONE (federation or active cost ceiling). Read the reference files whole; use the roster below only as data.')
}

# Agent pins and dispatchability from frontmatter: repository folders first, then an installed plugin's agents/.
$pins = @{}
$blocked = @{}
$agentBases = @('.github/agents', '.agents/agents', '.claude/agents' | ForEach-Object { Join-Path $RepoRoot $_ }) +
    @('../../../agents', '../../agents', '../agents' | ForEach-Object { Join-Path $PSScriptRoot $_ })
foreach ($base in $agentBases) {
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $base -Recurse -Filter '*.agent.md' -File) {
        $head = (Get-Content -LiteralPath $file.FullName -TotalCount 40 -Encoding utf8) -join "`n"
        if ($head -notmatch '(?s)^---\n(.*?)\n---') { continue }
        $front = $Matches[1]
        if ($front -notmatch '(?m)^name:\s*["'']?(.+?)["'']?\s*$') { continue }
        $name = $Matches[1]
        if ($pins.ContainsKey($name)) { continue }
        $model = if ($front -match '(?m)^model:\s*["'']?(.+?)["'']?\s*$') { $Matches[1] -replace '\s*\(copilot\)\s*$', '' } else { '' }
        $pins[$name] = $model
        $blocked[$name] = $front -match '(?m)^disable-model-invocation:\s*true\s*$'
    }
}

# Per-model rate rows only (the tier fallback table has a number in its third column): the squad root's, then the template's.
$isModelRow = { param($r) $r.Count -ge 7 -and $r[0] -ne 'Model (as routed)' -and $r[2] -notmatch '^\d' -and $r[3] -match '^\d' }
$rates = @(Get-TableRows (Join-Path $SquadRoot 'consumption-rates.md') | Where-Object { & $isModelRow $_ }) +
    @(Get-TableRows (Join-Path $refs 'consumption-rates-template.md') | Where-Object { & $isModelRow $_ })
function Find-Rate {
    param([string]$Model)
    if (-not $Model) { return $null }
    $key = $Model.ToLowerInvariant()
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
    $gross = $t * ($base + $growth * ($t - 1) / 2)
    $rate = Find-Rate $Model
    [ordered]@{
        model              = $Model
        model_source       = $Source
        priced_as          = if ($rate) { $rate[0] } else { '' }
        model_tier         = if ($rate) { $rate[2] } else { 'default' }
        internal_turns     = $t
        input_tokens       = [long][math]::Round($gross * 0.2)
        cached_tokens      = [long][math]::Round($gross * 0.8)
        cache_write_tokens = if ($Model -match 'claude') { [long]($base + $growth * ($t - 1)) } else { 0 }
        output_tokens      = [long]($t * $perTurn)
        basis              = 'estimated'
    }
}

$roster = Get-Roster $teamPath
$agentColumns = @('Agent Name (Primary)', 'Primary Agent', 'Primary', 'Agent')
$hasModel = $roster.Header -contains 'Model'
$out.Add('')
$out.Add('## Roster')
$out.Add('')
$out.Add('Dispatch each role with `task` `agent_type` (and `name`) set to its Agent cell verbatim; never `general-purpose`, `task`, or another built-in type.')
if ($hasModel) { $out.Add('Pass each role''s Model cell as the dispatch `model` exactly as written; an empty cell passes no `model`.') }
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
    $runs = if ($cell) { $cell } elseif ($pin) { $pin } else { $SessionModel }
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
$out.Add('Dispatch the Squad Scribe with the payload JSON and this exact command line, which the Scribe runs as its first action; never run it yourself:')
$out.Add("``pwsh -File '$(Join-Path $PSScriptRoot 'Write-SquadHandoff.ps1')' -SquadRoot '$SquadRoot' -PayloadPath <payload.json>``")

$out.Add('')
$out.Add('## Procedure (verbatim, economy-mode.md)')
$out.Add('')
$out.Add('Delegating parents additionally read delegated-worker-routing.md. Carry the owning roster row and squadRoot; admit only a selected delegate, preserve worker inputs and pins, never inherit a discounted owner pick, and return worker routing and host-model reports separately.')
$out.Add('')
$out.Add((Get-Section 'economy-mode.md' '## Bounded Lane'))
$out.Add('')
$out.Add((Get-Section 'economy-mode.md' '## Plan-Driven Parallelism'))
$out.Add('')
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
