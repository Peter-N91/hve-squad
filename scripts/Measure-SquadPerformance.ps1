#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Measures the squad's prefill/dispatch/session/history shape and a correctness
    inventory, without touching squad-src or invoking any model.
.DESCRIPTION
    This is the P00 measurement harness (routing-performance plan, D2). It is
    deterministic and offline: every figure comes from a file already on disk, or from
    a fixed, cited derivation of the pipeline text in squad-autopilot.instructions.md
    and gates-and-modes.md. No network cmdlet or tool is used anywhere in this script.

    It measures both host paths for every session type named in the plan's P00-T01
    spec (Coordinator, Federation Coordinator, Scribe, a representative specialist,
    and a representative council member):

    * Path (b), plugin/CLI: the explicit-read file set an agent's own contract names,
      measured directly. This total holds regardless of host, so it is always
      "hostLoadingVerified: true".
    * Path (a), VS Code/APM: the same explicit-read set, plus the full `applyTo`
      bundle (every `.github/instructions/squad/*.instructions.md` file, grouped by
      its own frontmatter `applyTo` glob) discovered dynamically rather than
      hardcoded, so a later split is reflected automatically. Whether a host actually
      loads that bundle for a given session's working context is unresolved (research
      Gap-1), so this add-on is always flagged "hostLoadingVerified: false" -- it is
      computed additively, never asserted as measured.

    Bytes and file counts are directly measured (FileInfo.Length / Get-ChildItem).
    tokensApprox is bytes/4, always labeled "computed". The Scribe per-dispatch and
    per-run figures, the canonical autopilot run model, and the four measured
    instructions/reference duplication pairs are carried forward from
    performance-research.md (2026-09-27) as "derived"/"cited" figures -- they describe
    the pipeline's own text and a prior lane's exact byte-span measurement, not
    something this script can re-derive from a static file scan alone. The
    correctness inventory (normative-sentence and heading counts) is measured fresh,
    every run, straight off the current tree.

    All paths written into the JSON are repo-relative (forward-slash), never
    absolute, so the baseline is portable across machines and CI runners.
.PARAMETER SourceRoot
    Repository root holding `squad-src/`. Accepts a worktree of any commit (for
    example a `git worktree` checkout of `600ccae`) so the same script can capture a
    BEFORE baseline from history and an AFTER baseline from the working tree. Defaults
    to the repository root two levels above this script.
.PARAMETER OutputPath
    Where to write the measured JSON. Defaults to a timestamped file under the
    system temp directory; the caller decides whether to promote it to a checked-in
    baseline via -UpdateBaseline.
.PARAMETER UpdateBaseline
    Also write the JSON to `tests/tier0/baselines/prefill-baseline.json` under
    SourceRoot. Guarded by ShouldProcess because it overwrites a checked-in file.
.EXAMPLE
    ./scripts/Measure-SquadPerformance.ps1 -SourceRoot . -UpdateBaseline
.EXAMPLE
    ./scripts/Measure-SquadPerformance.ps1 -SourceRoot ../hve-squad-600ccae -OutputPath ./before.json
.NOTES
    See .copilot-tracking/squad/members/routing-performance/plans/2026-09-27-routing-performance-plan.md
    (P00-T01/T02) and its amendment-1 (condition #19, #23) for this script's contract.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SourceRoot,

    [string]$OutputPath,

    [switch]$UpdateBaseline
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $SourceRoot) {
    $SourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$SourceRootFull = $SourceRoot.TrimEnd('\', '/')

function ConvertTo-RepoRelative {
    param([Parameter(Mandatory)][string]$Path)

    $full = (Resolve-Path -LiteralPath $Path).Path
    $relative = $full.Substring($SourceRootFull.Length).TrimStart('\', '/')
    return ($relative -replace '\\', '/')
}

function Get-FileByteCount {
    param([Parameter(Mandatory)][string]$RelativePath)

    $full = Join-Path $SourceRootFull $RelativePath
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Measure-SquadPerformance: expected file not found at repo-relative path '$RelativePath' (resolved: $full)."
    }
    return (Get-Item -LiteralPath $full).Length
}

function Get-LineByteLength {
    <#
    .SYNOPSIS
        Byte length (UTF8) of an inclusive line range, used only to re-derive the four
        already-cited duplication byte spans from the current tree rather than freeze
        a stale number.
    #>
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][int]$StartLine,
        [Parameter(Mandatory)][int]$EndLine
    )

    $full = Join-Path $SourceRootFull $RelativePath
    $lines = Get-Content -LiteralPath $full
    $count = $lines.Count
    $start = [Math]::Max(1, $StartLine)
    $end = [Math]::Min($count, $EndLine)
    if ($start -gt $end) { return 0 }
    $span = ($lines[($start - 1)..($end - 1)] -join "`n")
    return [System.Text.Encoding]::UTF8.GetByteCount($span)
}

# ---------------------------------------------------------------------------
# 1. applyTo bundle discovery (dynamic -- reflects a later split automatically)
# ---------------------------------------------------------------------------

$instructionsRelRoot = 'squad-src/.github/instructions/squad'
$instructionsDir = Join-Path $SourceRootFull $instructionsRelRoot
$bundleGroups = [ordered]@{}

foreach ($file in Get-ChildItem -LiteralPath $instructionsDir -Filter '*.instructions.md' -File) {
    $head = (Get-Content -LiteralPath $file.FullName -TotalCount 6) -join "`n"
    $glob = 'unknown'
    $match = [regex]::Match($head, "applyTo:\s*[""']?(?<glob>[^""'\r\n]+)[""']?")
    if ($match.Success) { $glob = $match.Groups['glob'].Value.Trim() }

    if (-not $bundleGroups.Contains($glob)) { $bundleGroups[$glob] = [System.Collections.Generic.List[object]]::new() }
    $bundleGroups[$glob].Add([pscustomobject]@{
            Path  = ConvertTo-RepoRelative $file.FullName
            Bytes = $file.Length
        })
}

# The squad-state glob is the one every non-floor rule file shares; the floor glob
# ('**') is squad-floor.instructions.md, always-on regardless of host or path context.
# pptx-brand-template.instructions.md also mentions the squad tracking path (as part
# of a narrower, comma-joined compound glob) so it must be excluded explicitly rather
# than matched by substring alone.
$squadStateGlobKey = @($bundleGroups.Keys | Where-Object { $_ -like '*copilot-tracking/squad*' -and $_ -notlike '*ppt*' }) | Select-Object -First 1
$floorGlobKey = @($bundleGroups.Keys | Where-Object { $_ -eq '**' }) | Select-Object -First 1

# Assign via a real array-typed variable first, then conditionally overwrite -- an
# `if {} else {}` expression capture silently unwraps a single-element @() result
# back to a scalar, which would break the `+` concatenation below whenever a glob
# group happens to contain exactly one file.
$squadStateFiles = @()
if ($squadStateGlobKey) { $squadStateFiles = @($bundleGroups[$squadStateGlobKey]) }
$floorFiles = @()
if ($floorGlobKey) { $floorFiles = @($bundleGroups[$floorGlobKey]) }

$bundleBytes = (($squadStateFiles + $floorFiles) | Measure-Object -Property Bytes -Sum).Sum
if (-not $bundleBytes) { $bundleBytes = 0 }
$bundleFileCount = $squadStateFiles.Count + $floorFiles.Count

$applyToBundle = [ordered]@{
    squadStateGlob      = $squadStateGlobKey
    squadStateFileCount  = $squadStateFiles.Count
    squadStateBytes      = ($squadStateFiles | Measure-Object -Property Bytes -Sum).Sum
    floorGlob            = $floorGlobKey
    floorFileCount       = $floorFiles.Count
    floorBytes           = ($floorFiles | Measure-Object -Property Bytes -Sum).Sum
    totalBytes           = $bundleBytes
    totalFileCount       = $bundleFileCount
    basis                = 'measured'
    hostLoadingVerified  = $false
    hostLoadingNote      = 'Whether a host that honors applyTo also has a matching path already in a given dispatched session''s working context is unresolved (research Gap-1). This bundle is computed additively onto every VS Code/APM row below; it is never asserted as measured for that row.'
}

# ---------------------------------------------------------------------------
# 2. Per-session-type load manifests (data-driven; Q1 of performance-research.md)
# ---------------------------------------------------------------------------

$referencesRoot = 'squad-src/.github/skills/squad/references'
$agentsRoot = 'squad-src/.github/agents/squad'

$sessionManifests = @(
    [ordered]@{
        SessionType        = 'coordinator'
        Description        = 'Squad Coordinator, unconditional read set'
        UnconditionalFiles = @(
            "$agentsRoot/squad-coordinator.agent.md"
            "$referencesRoot/00-index.md"
            "$referencesRoot/profiles-and-packs.md"
            "$referencesRoot/operating-procedure.md"
            "$referencesRoot/gates-and-modes.md"
        )
        ConditionalFiles   = [ordered]@{
            'init-only-seed-templates'    = @("$referencesRoot/seed-templates.md")
            'cost-ceiling-before-step-2b' = @("$referencesRoot/consumption.md")
            'routing-ranked-or-models-override' = @("$referencesRoot/model-catalog.md", "$referencesRoot/model-routing.md")
        }
        BundleEligible     = $true
    }
    [ordered]@{
        SessionType        = 'federation-coordinator'
        Description        = 'Squad Federation Coordinator, unconditional read set'
        UnconditionalFiles = @(
            "$agentsRoot/squad-federation-coordinator.agent.md"
            "$referencesRoot/00-index.md"
            "$referencesRoot/federation.md"
            "$referencesRoot/operating-procedure.md"
            "$referencesRoot/gates-and-modes.md"
        )
        ConditionalFiles   = [ordered]@{
            'seeding-mode-only' = @("$referencesRoot/federation-templates.md")
            'aggregate-ceiling' = @("$referencesRoot/consumption.md", "$referencesRoot/federation-templates.md")
        }
        BundleEligible     = $true
    }
    [ordered]@{
        SessionType        = 'scribe'
        Description        = 'Squad Scribe, unconditional read set (every turn)'
        UnconditionalFiles = @(
            "$agentsRoot/squad-scribe.agent.md"
            "$referencesRoot/00-index.md"
            "$referencesRoot/scribe-procedure.md"
            "$referencesRoot/entry-schemas.md"
            "$referencesRoot/scribe-payload-template.md"
        )
        ConditionalFiles   = [ordered]@{
            'consumption-write'            = @("$referencesRoot/consumption.md")
            'roster-stamp-or-seed'         = @("$referencesRoot/seed-templates.md")
            'federation-level-payload'     = @("$referencesRoot/federation-templates.md")
            'initialization-or-memory-payload' = @("$referencesRoot/scribe-cold-init-and-seeding.md")
            'promotion-expansion-or-federation-summary-payload' = @("$referencesRoot/scribe-cold-federation.md")
            'verdict-autonomous-loop-or-autopilot-summary-payload' = @("$referencesRoot/scribe-cold-gates-and-verdicts.md")
        }
        BundleEligible     = $true
    }
    [ordered]@{
        SessionType        = 'specialist-researcher'
        Description        = 'Squad Researcher, representative specialist (Deliverable Root: .copilot-tracking/research/<date>/)'
        UnconditionalFiles = @(
            "$agentsRoot/squad-researcher.agent.md"
        )
        ConditionalFiles   = [ordered]@{}
        BundleEligible     = $true
        ExternalDependency = [ordered]@{
            name              = 'rpi-research skill'
            repoScoped        = $false
            note              = 'Ships from the hve-core package, not squad-src, so it is out of this script''s repo-scoped measurement boundary (condition #19). Cited from performance-research.md 2026-09-27, not measured here.'
            citedBytes        = 78606
            basis             = 'cited'
        }
    }
    [ordered]@{
        SessionType        = 'council-cost-manager'
        Description        = 'Squad Cost Manager, representative council member'
        UnconditionalFiles = @(
            "$agentsRoot/squad-cost-manager.agent.md"
        )
        ConditionalFiles   = [ordered]@{}
        BundleEligible     = $true
        ExternalDependency = [ordered]@{
            name       = 'azure-pricing skill'
            repoScoped = $false
            note       = 'External cast dependency out of this script''s repo-scoped measurement boundary; size was out of performance-research.md''s measured scope too.'
            citedBytes = $null
            basis      = 'unmeasured'
        }
    }
)

$sessionTypeRows = [System.Collections.Generic.List[object]]::new()

foreach ($manifest in $sessionManifests) {
    $unconditionalBytes = ($manifest.UnconditionalFiles | ForEach-Object { Get-FileByteCount $_ } | Measure-Object -Sum).Sum
    if (-not $unconditionalBytes) { $unconditionalBytes = 0 }
    $fileCount = $manifest.UnconditionalFiles.Count

    $conditionalBytes = [ordered]@{}
    foreach ($trigger in $manifest.ConditionalFiles.Keys) {
        $files = $manifest.ConditionalFiles[$trigger]
        $bytes = ($files | ForEach-Object { Get-FileByteCount $_ } | Measure-Object -Sum).Sum
        if (-not $bytes) { $bytes = 0 }
        $conditionalBytes[$trigger] = $bytes
    }

    # Path (b): plugin/CLI. Explicit reads only; no ambient applyTo bundle exists on
    # this path (research Q1, C3) so this figure holds on every host.
    $pluginCliRow = [ordered]@{
        sessionType         = $manifest.SessionType
        hostPath             = 'plugin-cli'
        unconditionalBytes   = $unconditionalBytes
        conditionalBytes     = $conditionalBytes
        fileCount            = $fileCount
        tokensApprox         = [Math]::Round($unconditionalBytes / 4)
        tokensApproxBasis    = 'computed'
        hostLoadingVerified  = $true
        files                = $manifest.UnconditionalFiles
    }
    if ($manifest.Contains('ExternalDependency')) {
        $pluginCliRow['externalDependency'] = $manifest.ExternalDependency
    }
    $sessionTypeRows.Add([pscustomobject]$pluginCliRow)

    # Path (a): VS Code/APM. Same explicit reads, plus the applyTo bundle add-on when
    # this session type's own state lives under a squad-state path (every one here
    # does). The add-on's host-loading precondition is unverified -- see $applyToBundle.
    if ($manifest.BundleEligible) {
        $vscodeUnconditional = $unconditionalBytes + $bundleBytes
        $vscodeRow = [ordered]@{
            sessionType         = $manifest.SessionType
            hostPath             = 'vscode-apm'
            unconditionalBytes   = $vscodeUnconditional
            conditionalBytes     = $conditionalBytes
            fileCount            = $fileCount + $bundleFileCount
            tokensApprox         = [Math]::Round($vscodeUnconditional / 4)
            tokensApproxBasis    = 'computed'
            hostLoadingVerified  = $false
            hostLoadingNote      = $applyToBundle.hostLoadingNote
            explicitReadBytes    = $unconditionalBytes
            applyToBundleBytes   = $bundleBytes
            files                = $manifest.UnconditionalFiles
        }
        if ($manifest.Contains('ExternalDependency')) {
            $vscodeRow['externalDependency'] = $manifest.ExternalDependency
        }
        $sessionTypeRows.Add([pscustomobject]$vscodeRow)
    }
}

# ---------------------------------------------------------------------------
# 3. Scribe per-dispatch and per-run figures (canonical autopilot run)
# ---------------------------------------------------------------------------

$scribePlugin = $sessionTypeRows | Where-Object { $_.sessionType -eq 'scribe' -and $_.hostPath -eq 'plugin-cli' } | Select-Object -First 1
$scribeVsCode = $sessionTypeRows | Where-Object { $_.sessionType -eq 'scribe' -and $_.hostPath -eq 'vscode-apm' } | Select-Object -First 1
$consumptionBytes = Get-FileByteCount "$referencesRoot/consumption.md"

# Canonical autopilot run dispatch count (Q2 of performance-research.md, derived from
# the pipeline text in squad-autopilot.instructions.md and its Artifact Gates table --
# this is not a live-run measurement, it is a fixed reading of that contract).
$canonicalScribeDispatches = 7

function Get-ScribeRunTotal {
    param([Parameter(Mandatory)]$UnconditionalBytes, [Parameter(Mandatory)][int]$Dispatches, [Parameter(Mandatory)][int]$ConsumptionBytes)

    $unconditionalOnly = $UnconditionalBytes * $Dispatches
    $withConsumption = ($UnconditionalBytes + $ConsumptionBytes) * $Dispatches
    [ordered]@{
        dispatches               = $Dispatches
        perDispatchUnconditionalBytes = $UnconditionalBytes
        unconditionalOnlyBytes   = $unconditionalOnly
        unconditionalOnlyTokensApprox = [Math]::Round($unconditionalOnly / 4)
        withConsumptionBytes     = $withConsumption
        withConsumptionTokensApprox = [Math]::Round($withConsumption / 4)
        tokensApproxBasis        = 'computed'
        dispatchCountBasis       = 'derived (performance-research.md Q2, from squad-autopilot.instructions.md pipeline/Artifact Gates text)'
    }
}

# D6b (routing-performance remedy): the Scribe's Cold-File Dispatch Table reads
# references/consumption.md on every history dispatch (every history-entry write, not
# only the subset of turns a "consumption-write" trigger implies), so the honest
# per-dispatch read set for that history-dispatch class is the unconditional hot core
# PLUS consumption.md, every time -- never the hot core alone. This is reported as its
# own manifest (not multiplied by a run's dispatch count) precisely so a BEFORE/AFTER
# -SourceRoot comparison isolates the effect of the D3/D6b consumption.md byte change
# from the unrelated per-run dispatch-count model.
function Get-ScribeHistoryDispatchManifest {
    param([Parameter(Mandatory)]$UnconditionalBytes, [Parameter(Mandatory)][int]$ConsumptionBytes)

    $historyDispatchBytes = $UnconditionalBytes + $ConsumptionBytes
    [ordered]@{
        description                 = 'Honest per-history-dispatch read set: the Scribe unconditional hot core plus consumption.md, read on every history-entry write per the Cold-File Dispatch Table.'
        hotCoreBytes                = $UnconditionalBytes
        consumptionBytes            = $ConsumptionBytes
        historyDispatchBytes        = $historyDispatchBytes
        historyDispatchTokensApprox = [Math]::Round($historyDispatchBytes / 4)
        tokensApproxBasis           = 'computed'
    }
}

$scribeSummary = [ordered]@{
    perRun = [ordered]@{
        'plugin-cli' = Get-ScribeRunTotal -UnconditionalBytes $scribePlugin.unconditionalBytes -Dispatches $canonicalScribeDispatches -ConsumptionBytes $consumptionBytes
        'vscode-apm' = Get-ScribeRunTotal -UnconditionalBytes $scribeVsCode.unconditionalBytes -Dispatches $canonicalScribeDispatches -ConsumptionBytes $consumptionBytes
    }
    historyDispatch = [ordered]@{
        'plugin-cli' = Get-ScribeHistoryDispatchManifest -UnconditionalBytes $scribePlugin.unconditionalBytes -ConsumptionBytes $consumptionBytes
        'vscode-apm' = Get-ScribeHistoryDispatchManifest -UnconditionalBytes $scribeVsCode.unconditionalBytes -ConsumptionBytes $consumptionBytes
    }
}

# Coordinator routing-file variants (D5/condition #23): squad-coordinator.agent.md
# Step 2a reads model-catalog.md/model-routing.md only when routing=ranked or a
# models= override is present; squad-federation-coordinator.agent.md never reads them
# itself (it only forwards the params), so this summary is coordinator-only. Both
# variants are reported explicitly here rather than left implicit in conditionalBytes.
$coordinatorPlugin = $sessionTypeRows | Where-Object { $_.sessionType -eq 'coordinator' -and $_.hostPath -eq 'plugin-cli' } | Select-Object -First 1
$coordinatorVsCode = $sessionTypeRows | Where-Object { $_.sessionType -eq 'coordinator' -and $_.hostPath -eq 'vscode-apm' } | Select-Object -First 1
$routingFilesBytes = $coordinatorPlugin.conditionalBytes.'routing-ranked-or-models-override'
if (-not $routingFilesBytes) { $routingFilesBytes = 0 }

function Get-CoordinatorRoutingVariant {
    param([Parameter(Mandatory)]$UnconditionalBytes, [Parameter(Mandatory)]$RoutingFilesBytes)

    [ordered]@{
        'routing-off-or-unranked'     = [ordered]@{
            unconditionalBytes = $UnconditionalBytes
            tokensApprox       = [Math]::Round($UnconditionalBytes / 4)
        }
        'routing-ranked-or-models-override' = [ordered]@{
            unconditionalBytes = $UnconditionalBytes + $RoutingFilesBytes
            tokensApprox       = [Math]::Round(($UnconditionalBytes + $RoutingFilesBytes) / 4)
        }
        tokensApproxBasis = 'computed'
        basis             = 'measured (both routing= variants of the same unconditional read set; squad-coordinator.agent.md Step 2a)'
    }
}

$coordinatorSummary = [ordered]@{
    variants = [ordered]@{
        'plugin-cli' = Get-CoordinatorRoutingVariant -UnconditionalBytes $coordinatorPlugin.unconditionalBytes -RoutingFilesBytes $routingFilesBytes
        'vscode-apm' = Get-CoordinatorRoutingVariant -UnconditionalBytes $coordinatorVsCode.unconditionalBytes -RoutingFilesBytes $routingFilesBytes
    }
}

# ---------------------------------------------------------------------------
# 4. Canonical autopilot run model (dispatch/session/history/state-advance counts)
# ---------------------------------------------------------------------------

# This table is a fixed reading of the pipeline contract (squad-autopilot.instructions.md
# Pipeline Contract + Artifact Gates table), re-derived independently in
# performance-research.md Q2 rather than measured from a live run. It describes a
# standard single-build autopilot run: no remediation loop, no conditional `rai`
# council member, no deliverable fan-out. basis = 'derived' throughout.
# Note: these must be [pscustomobject], not [ordered]@{} hashtables -- Measure-Object
# -Property only resolves properties (via PSObject adaptation), not hashtable keys.
$canonicalRunStages = @(
    [pscustomobject][ordered]@{ stage = 'intake'; specialistDispatches = 1; scribeHandoffs = 1; historyEntries = 1; requiredArtifact = 'decisions.md#Intake Readiness Verdict' }
    [pscustomobject][ordered]@{ stage = 'research'; specialistDispatches = 1; scribeHandoffs = 1; historyEntries = 1; requiredArtifact = '.copilot-tracking/research/<date>/*.md' }
    [pscustomobject][ordered]@{ stage = 'plan'; specialistDispatches = 1; scribeHandoffs = 1; historyEntries = 1; requiredArtifact = '.copilot-tracking/plans/*.md' }
    [pscustomobject][ordered]@{ stage = 'council'; specialistDispatches = 4; scribeHandoffs = 1; historyEntries = 4; requiredArtifact = 'decisions.md#Council Verdict' }
    [pscustomobject][ordered]@{ stage = 'implement'; specialistDispatches = 1; scribeHandoffs = 1; historyEntries = 1; requiredArtifact = '.copilot-tracking/changes/*' }
    [pscustomobject][ordered]@{ stage = 'review'; specialistDispatches = 1; scribeHandoffs = 1; historyEntries = 1; requiredArtifact = 'review record' }
    [pscustomobject][ordered]@{ stage = 'final'; specialistDispatches = 0; scribeHandoffs = 1; historyEntries = 0; requiredArtifact = 'history/autopilot-run-<id>.md' }
)

$canonicalRunTotals = [ordered]@{
    specialistDispatches  = ($canonicalRunStages | Measure-Object -Property specialistDispatches -Sum).Sum
    scribeHandoffs         = ($canonicalRunStages | Measure-Object -Property scribeHandoffs -Sum).Sum
    historyEntries         = ($canonicalRunStages | Measure-Object -Property historyEntries -Sum).Sum
    stateAdvancementPoints = ($canonicalRunStages | Measure-Object -Property scribeHandoffs -Sum).Sum
    gates                  = @('intake-gate (conditional)', 'implementation-gate', 'council-gate', 'cost-preflight (per stage boundary)')
    requiredArtifacts      = @($canonicalRunStages | ForEach-Object { $_.requiredArtifact })
    basis                  = 'derived (performance-research.md Q2, squad-autopilot.instructions.md pipeline + Artifact Gates table); a standard single-build run: no remediation, no conditional rai, no deliverable fan-out'
}

$canonicalAutopilotRun = [ordered]@{
    stages = $canonicalRunStages
    totals = $canonicalRunTotals
}

# ---------------------------------------------------------------------------
# 5. Duplication bytes (four pairs measured by lane B in performance-research.md Q3)
# ---------------------------------------------------------------------------

$duplicationPairs = @(
    [ordered]@{
        pair           = 'squad-council.instructions.md vs gates-and-modes.md (council section)'
        referenceFile  = "$referencesRoot/gates-and-modes.md"
        startLine      = 41
        endLine        = 49
        classification = '(ii) semantic'
    }
    [ordered]@{
        pair           = 'squad-state.instructions.md vs operating-procedure.md'
        estimatedBytes = 4500
        classification = 'mixed (ii)/(iii)'
    }
    [ordered]@{
        pair           = 'squad-state.instructions.md vs entry-schemas.md'
        estimatedBytes = 3300
        classification = 'mostly (ii)'
    }
    [ordered]@{
        pair           = 'squad-autopilot.instructions.md vs gates-and-modes.md (autopilot section)'
        estimatedBytes = 8800
        classification = '(ii) semantic'
    }
)

$duplicationRows = foreach ($entry in $duplicationPairs) {
    if ($entry.Contains('referenceFile')) {
        $bytes = Get-LineByteLength -RelativePath $entry.referenceFile -StartLine $entry.startLine -EndLine $entry.endLine
        [ordered]@{
            pair           = $entry.pair
            bytes          = $bytes
            basis          = 'computed (re-derived each run from the cited reference-side line span; performance-research.md Q3)'
            classification = $entry.classification
        }
    }
    else {
        [ordered]@{
            pair           = $entry.pair
            bytes          = $entry.estimatedBytes
            basis          = 'cited (performance-research.md Q3, 2026-09-27; an estimate, not an exact byte-span measurement)'
            classification = $entry.classification
        }
    }
}

$duplicationTotalBytes = ($duplicationRows | ForEach-Object { $_.bytes } | Measure-Object -Sum).Sum

# ---------------------------------------------------------------------------
# 6. Correctness inventory (normative sentences + named anchors), measured fresh
# ---------------------------------------------------------------------------

$inventoryFiles = [System.Collections.Generic.List[string]]::new()
$inventoryFiles.Add("$SourceRootFull/squad-src/.github/skills/squad/SKILL.md")
foreach ($dir in @(
        'squad-src/.github/instructions/squad'
        'squad-src/.github/agents/squad'
        'squad-src/.github/skills/squad/references'
        'squad-src/.github/prompts/squad'
    )) {
    $full = Join-Path $SourceRootFull $dir
    if (Test-Path -LiteralPath $full) {
        Get-ChildItem -LiteralPath $full -Filter '*.md' -File | ForEach-Object { $inventoryFiles.Add($_.FullName) }
    }
}

$headingCounts = [ordered]@{}
$normativeCounts = [ordered]@{}
$normativePattern = '(?<!\w)(MUST|NEVER|Never|Always|must not)(?!\w)'

foreach ($file in $inventoryFiles) {
    foreach ($line in (Get-Content -LiteralPath $file)) {
        $headingMatch = [regex]::Match($line, '^(#{1,6})\s+(?<text>.+?)\s*$')
        if ($headingMatch.Success) {
            $text = $headingMatch.Groups['text'].Value.Trim()
            if ($headingCounts.Contains($text)) { $headingCounts[$text]++ } else { $headingCounts[$text] = 1 }
        }

        if ([regex]::IsMatch($line, $normativePattern)) {
            $normalized = $line.Trim()
            if ($normalized) {
                if ($normativeCounts.Contains($normalized)) { $normativeCounts[$normalized]++ } else { $normativeCounts[$normalized] = 1 }
            }
        }
    }
}

$sortedHeadingKeys = @($headingCounts.Keys | Sort-Object)
$sortedNormativeKeys = @($normativeCounts.Keys | Sort-Object)

$checksumInput = ($sortedHeadingKeys | ForEach-Object { "H|$_|$($headingCounts[$_])" }) -join "`n"
$checksumInput += "`n---`n"
$checksumInput += ($sortedNormativeKeys | ForEach-Object { "N|$_|$($normativeCounts[$_])" }) -join "`n"

$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($checksumInput))
    $checksum = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
}
finally {
    $sha256.Dispose()
}

$correctnessInventory = [ordered]@{
    filesScanned         = $inventoryFiles.Count
    headingCount         = $sortedHeadingKeys.Count
    normativeSentenceCount = $sortedNormativeKeys.Count
    checksum             = "sha256:$checksum"
    headingCounts        = $headingCounts
    normativeCounts       = $normativeCounts
    basis                = 'measured (fresh scan of the current tree; heading/sentence text is compared, not file location, so a rule that moves file during a later split still counts as present)'
}

# ---------------------------------------------------------------------------
# 7. Assemble and write
# ---------------------------------------------------------------------------

$artifactCount = ($sessionManifests | ForEach-Object { $_.UnconditionalFiles.Count } | Measure-Object -Sum).Sum + $bundleFileCount

$result = [ordered]@{
    schemaVersion         = '1.0'
    capturedAtUtc         = (Get-Date).ToUniversalTime().ToString('o')
    sourceRootLabel        = 'squad-src/.github (repo-relative; no absolute paths are written by this script)'
    hostPaths              = @('plugin-cli', 'vscode-apm')
    applyToBundle          = $applyToBundle
    sessionTypes           = $sessionTypeRows
    scribe                 = $scribeSummary
    coordinator            = $coordinatorSummary
    canonicalAutopilotRun  = $canonicalAutopilotRun
    duplicationBytes       = [ordered]@{
        pairs      = $duplicationRows
        totalBytes = $duplicationTotalBytes
    }
    correctnessInventory   = $correctnessInventory
    artifactCount          = $artifactCount
    stateAdvanced          = $null
    stateAdvancedNote       = 'Not applicable to a static measurement capture; this field is populated only when this script is later given a matched before/after state.json pair from a live run (P05).'
}

$json = $result | ConvertTo-Json -Depth 12

if (-not $OutputPath) {
    $OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) "squad-performance-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()).json"
}

Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8NoBOM
Write-Host "Wrote measurement JSON to $OutputPath" -ForegroundColor Cyan

if ($UpdateBaseline) {
    $baselinePath = Join-Path $SourceRootFull 'tests/tier0/baselines/prefill-baseline.json'
    if ($PSCmdlet.ShouldProcess($baselinePath, 'Overwrite checked-in performance baseline')) {
        $baselineDir = Split-Path -Parent $baselinePath
        if (-not (Test-Path -LiteralPath $baselineDir)) { New-Item -ItemType Directory -Path $baselineDir -Force | Out-Null }
        Set-Content -LiteralPath $baselinePath -Value $json -Encoding utf8NoBOM
        Write-Host "Updated baseline at $baselinePath" -ForegroundColor Cyan
    }
}

$result

