#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Builds the hve-squad GitHub Copilot plugin distribution tree into the
    hve-squad-plugin sibling repository.
.DESCRIPTION
    Per ADR-0006, the plugin distribution tree (agents/, skills/,
    .github/plugin/plugin.json, .github/plugin/marketplace.json) is generated
    output that never lives in hve-squad's own working tree. This script is
    the single, reproducible generator: it resolves an immutable source (a
    git ref or, for local iteration only, a working copy), copies the 26
    squad agents with their dead .instructions.md citations rewritten to the
    plugin's skill-reference targets, ports squad-src/.github/skills/squad/
    with its two housekeeping edits, authors the 5 prompt-derived invocation
    skills, and writes a version-stamped plugin.json plus a marketplace.json
    scaffold.

    Source resolution never reads a live copy of main's working tree unless
    -SourceRoot is explicitly passed. Under -Ref (the default, resolving to
    the latest tag), every file is read via 'git show <ref>:<path>' against
    RepoRoot's own git history, so an uncommitted or ahead-of-tag change in
    the working tree cannot leak into a shippable build.

    Re-running with the same source produces byte-identical output
    (idempotent build): agents/ and skills/ are fully regenerated each run
    rather than patched in place.
.PARAMETER Ref
    Git ref (tag) to build from. Defaults to the latest tag via
    'git describe --tags --abbrev=0'. Mutually exclusive with -SourceRoot.
.PARAMETER SourceRoot
    Local/dev-only: build from a working copy at this path instead of a git
    ref. The stamped version is unambiguously non-release
    ('<latest-tag>+local'). Mutually exclusive with -Ref.
.PARAMETER OutputRoot
    Directory to write the plugin tree into. Defaults to the sibling
    directory '../hve-squad-plugin' next to RepoRoot.
.PARAMETER RepoRoot
    Root of the hve-squad repository. Defaults to the current git repository.
.PARAMETER McpVersion
    Exact @hve-squad/mcp npm version to pin in the generated .mcp.json (e.g.
    '0.7.0'). Never a bare 'latest' — pinning an exact version is what keeps
    a plugin install reproducible across different days/machines. Bumping
    this is a deliberate, separate action from rebuilding agent content via
    -Ref/-SourceRoot: when omitted, the script reuses OutputRoot's existing
    .mcp.json pin unchanged (a content-only rebuild never silently re-pins
    the MCP dependency). Required on a first-ever run against a fresh
    OutputRoot with no existing .mcp.json.
.PARAMETER DryRun
    Report what would be written without touching OutputRoot.
.EXAMPLE
    ./scripts/Build-SquadPlugin.ps1 -SourceRoot .
.EXAMPLE
    ./scripts/Build-SquadPlugin.ps1 -Ref v0.16.1-pre -OutputRoot C:\Solutions\hve-squad-plugin
.EXAMPLE
    ./scripts/Build-SquadPlugin.ps1 -Ref v0.16.0 -McpVersion 0.7.0
.EXAMPLE
    ./scripts/Build-SquadPlugin.ps1
.NOTES
    Invoked manually today; P02-T09's cross-repo publish workflow invokes it
    at release-cut time with -Ref <the tag being cut>.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Ref,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceRoot,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$McpVersion,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

#region Functions

function Resolve-BuildSource {
    <#
    .SYNOPSIS
        Resolves the mutually exclusive -Ref/-SourceRoot inputs into a single
        source descriptor, and fails fast on an invalid combination.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [bool]$RefSpecified,
        [string]$Ref,

        [bool]$SourceRootSpecified,
        [string]$SourceRoot
    )

    if ($RefSpecified -and $SourceRootSpecified) {
        throw "Specify either -Ref <tag> or -SourceRoot <path>, not both. -Ref builds a shippable, tag-pinned tree; -SourceRoot is local/dev-only and stamps a non-release version."
    }

    $latestTag = (git -C $RepoRoot describe --tags --abbrev=0 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $latestTag) {
        throw "Could not resolve the latest tag via 'git describe --tags --abbrev=0' in $RepoRoot. Pass -Ref explicitly, or -SourceRoot for a local/dev build."
    }

    if ($SourceRootSpecified) {
        $resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
        if (-not (Test-Path -LiteralPath (Join-Path $resolvedSourceRoot 'squad-src/.github'))) {
            throw "-SourceRoot '$resolvedSourceRoot' has no squad-src/.github — not an hve-squad working copy."
        }
        return [pscustomobject]@{
            Mode          = 'Source'
            SourceRoot    = $resolvedSourceRoot
            Ref           = $null
            PluginVersion = "$($latestTag -replace '^v', '')+local"
        }
    }

    $resolvedRef = if ($RefSpecified) { $Ref } else { $latestTag }
    return [pscustomobject]@{
        Mode          = 'Ref'
        SourceRoot    = $null
        Ref           = $resolvedRef
        PluginVersion = ($resolvedRef -replace '^v', '')
    }
}

function Get-SourceFileList {
    <#
    .SYNOPSIS
        Lists relative file paths under a squad-src/.github subdirectory,
        from either a git ref or a working copy.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Source,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$RelativeDir
    )

    if ($Source.Mode -eq 'Source') {
        $absDir = Join-Path $Source.SourceRoot $RelativeDir
        if (-not (Test-Path -LiteralPath $absDir)) { return @() }
        return @(Get-ChildItem -LiteralPath $absDir -Recurse -File |
            ForEach-Object { ($_.FullName.Substring($Source.SourceRoot.Length + 1)) -replace '\\', '/' })
    }

    $listing = git -C $RepoRoot ls-tree -r --name-only $Source.Ref -- $RelativeDir 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git ls-tree failed for '$RelativeDir' at ref '$($Source.Ref)'." }
    return @($listing | Where-Object { $_ })
}

function Get-SourceFileContent {
    <#
    .SYNOPSIS
        Reads one file's raw text content from either a git ref or a
        working copy. Never reads a live 'main' working tree in Ref mode.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Source,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ($Source.Mode -eq 'Source') {
        return Get-Content -LiteralPath (Join-Path $Source.SourceRoot $RelativePath) -Raw
    }

    $content = git -C $RepoRoot show "$($Source.Ref):$RelativePath" 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git show failed for '$RelativePath' at ref '$($Source.Ref)'." }
    return ($content -join "`n")
}

function Convert-AgentCitations {
    <#
    .SYNOPSIS
        Rewrites dead squad-namespaced .instructions.md citations in a copied
        agent body to their plugin-tree targets (conversion plan Section 1c),
        and folds squad-floor's inline-only citation (Section 4c).
    .DESCRIPTION
        External (non-squad-namespaced) citations, e.g. to bicep.instructions.md
        or telemetry-overlay.instructions.md, are deliberately left untouched —
        out of scope per the conversion plan's own note.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Section 1c reverse-index: old squad-namespaced instruction file -> new plugin-tree target.
    # Longer/more-specific names (e.g. federation-autopilot) are listed before their prefixes
    # (federation) purely for readability; the trailing '.instructions.md' anchor already
    # prevents 'squad-federation' from matching 'squad-federation-autopilot.instructions.md'.
    $citationMap = [ordered]@{
        'squad-mcp-capability'        = 'skills/squad/references/mcp-capability.md'
        'squad-state'                 = 'skills/squad/references/scribe-procedure.md'
        'squad-autonomous'            = 'skills/squad/references/gates-and-modes.md'
        'squad-autopilot'             = 'skills/squad/references/gates-and-modes.md'
        'squad-council'               = 'skills/squad/references/gates-and-modes.md'
        'squad-roster'                = 'skills/squad/references/profiles-and-packs.md'
        'squad-federation-autopilot'  = 'skills/squad/references/federation.md'
        'squad-federation'            = 'skills/squad/references/federation.md'
    }

    foreach ($name in $citationMap.Keys) {
        $pattern = '`(?:\.github/instructions/squad/)?' + [regex]::Escape($name) + '\.instructions\.md`'
        $Content = $Content -replace $pattern, ('`' + $citationMap[$name] + '`')
    }

    # squad-cost-manager.agent.md's parenthetical named its old source location; that
    # description is dead once the file no longer lives there in the plugin tree.
    $Content = $Content -replace ' \(authored under `squad-src/\.github/instructions/squad/`\)', ''

    # squad-floor.instructions.md is INLINE-only (Section 4c): squad-coordinator.agent.md
    # already restates the Dispatch-Discipline rule in its own words, so the citation is
    # dropped rather than rewritten to a new path.
    if ($FileName -eq 'squad-coordinator.agent.md') {
        $Content = $Content -replace ', and `squad-floor\.instructions\.md` carries it in full\.', '.'
    }

    return $Content
}

function Write-TextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Host "  [dry run] would write $Path" -ForegroundColor DarkGray
        return
    }

    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding utf8NoBOM -NoNewline
}

function New-InvocationSkillContent {
    <#
    .SYNOPSIS
        Returns the 5 prompt-derived invocation SKILL.md bodies (conversion
        plan Section 2). Content is bespoke per skill, authored once here from
        each source .prompt.md's Inputs/Requirements, not mechanically derived.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return [ordered]@{
        'squad-run'                = @'
---
name: squad-run
description: "Routes a request to the Squad Coordinator, which dispatches a cast of HVE Core agents in parallel and persists squad state. Use when the user asks to run, initialize, or continue a squad, or names a squad profile, pack, discovery depth, model tier, owner, or autonomy mode (autonomous/autopilot)."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Run

## Inputs

* **request** (required): The work for the squad this turn, from the user's own words.
* **profile** (optional): The squad profile to seed when the project has no squad yet (`default`, `full`, `security`, `design`, `accessibility`, `architecture`, `azure`, `modernization`, `compliance`, `operations`, or `product`). Selects which cast the coordinator stamps out during Init Mode.
* **pack** (optional): One or more comma-separated packs added on top of the profile (`power-platform`, `m365-copilot`, `aws`). A pack carries a technology vertical's specialist roles and never replaces the profile.
* **discovery** (optional): The depth of the opt-in discovery gate for this turn (`quick`, `standard`, `deep`, or `skip`). When omitted, the coordinator offers it once per topic in a `product` or `full` squad and stays silent in every other profile. Ignored on an unattended run.
* **tier** (optional): A model-tier hint (`fast` or `default`) overriding cost-first defaults for this turn.
* **owner** (optional): A `Member Name` from `team.md` that picks a specific named member when two rows share the same role.
* **mode** (optional): The autonomy mode for this turn — `autonomous` or `autopilot`. When omitted, the coordinator uses the standard interactive tiers, approving each step.

## Flow

1. Hand **request** (and **owner** when provided) to the Squad Coordinator agent and let its per-turn protocol classify, dispatch, and synthesize the response.
2. Pass **profile** through as the Init Mode profile hint when provided, and **pack** through as the Init Mode pack hint when provided. When the project has no squad and no profile is given, let the coordinator discover the project and propose a recommended profile before seeding.
3. Pass **tier** through as the per-turn tier override when provided; otherwise leave model selection to the coordinator.
4. Pass **discovery** through as the discovery-gate depth when provided; otherwise let the coordinator decide whether to offer the gate.
5. When **mode** is `autonomous`, request the `auto-validated` tier (bounded re-validation loop, always-escalate triggers); when **mode** is `autopilot`, request the full research→plan→implement→review pipeline (Human Gates on impactful actions and final-outcome validation only); otherwise rely on the standard interactive tiers.
6. Let the coordinator own roster, routing, state, and the notification contract — it seeds `.copilot-tracking/squad/{team.md,routing.md,state.json}` on first run and persists decisions, history, and notifications through the Squad Scribe.

## Invocation

Dispatch this request to the `Squad Coordinator` agent. This skill does not run the coordination logic itself — it only resolves which parameters to pass.
'@
        'squad-document'            = @'
---
name: squad-document
description: "Searches squad state and artifacts to answer a question or produce a focused document (md/html/pdf/docx) without the user reading decision logs or routing tables directly. Use when the user asks the squad to summarize, document, or answer a question from its own history."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Document

## Inputs

* **request** (required): What to find or document — a question, a topic to summarize, or a document to generate. Inferred from the caller's prompt or the conversation when not explicitly provided.
* **format** (optional, defaults to `md`): Output format — `md`, `html`, `pdf`, or `docx`.
* **outputPath** (optional): Local filesystem path for the document. When omitted, write to `docs/squad-document-<YYYY-MM-DD>.<ext>`.
* **squad** (optional): In a federation, the registered sub-squad name to scope the search to. Ignored when the project uses a single squad.

## Flow

1. Hand **request** to the Squad Document agent and let its required steps resolve the squad scope, search the artifacts, synthesize the answer, and write the file.
2. Pass **format**, **outputPath**, and **squad** through as-is. The agent owns format fallback, the default output path, and federation scoping.
3. Let the agent own its guardrails: squad state is read-only, every statement is grounded in an artifact, and the output path resolves to the local filesystem.

## Invocation

Dispatch this request to the `Squad Document` agent. This skill does not perform the search or synthesis itself — it only resolves which parameters to pass.
'@
        'squad-federation'          = @'
---
name: squad-federation
description: "Routes a request to the Squad Federation Coordinator, which dispatches one or more named sub-squads. Use when the user's project has (or wants) multiple named sub-squads, or names init, promote, watch, or a specific squad=<name> target."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Federation

## Inputs

* **request** (required): The work for the federation this turn, from the user's own words.
* **squad** (optional): The registered sub-squad to route this request to (for example, `squad=product`). Overrides meta-routing for the turn; when omitted, the coordinator matches `meta-routing.md`.
* **init** (optional): When present, triggers Federation Init Mode (propose → confirm → create) before routing. When a federation already exists, the same flag runs Federation Expansion Mode instead.
* **promote** (optional): When present on an existing single-squad project, triggers Federation Promotion Mode, adopting the existing squad into a federation as its first sub-squad before routing.
* **watch** (optional): Watch Mode provenance supplied by an event-triggered run — the event `source`, `ref`, `eventId`, `actor`, and the derived sub-squad name. When present, the coordinator runs Watch Mode Bootstrap Mode.
* **profile** (optional): A profile hint forwarded to a sub-squad's Init when that sub-squad has no squad yet.
* **discovery** (optional): The discovery-gate depth (`quick`, `standard`, `deep`, or `skip`) forwarded to every qualifying sub-squad the turn starts. Ignored on a Watch Mode or otherwise unattended run.
* **tier** (optional): A model-tier hint (`fast` or `default`) forwarded to the selected sub-squad's coordinator run.
* **owner** (optional): A `Member Name` forwarded to the selected sub-squad's coordinator run.
* **mode** (optional): The autonomy mode (`autonomous` or `autopilot`). With a single **squad** target, or with `mode=autonomous`, it is forwarded to that sub-squad's coordinator run. With `mode=autopilot` and no **squad** target, the coordinator runs the federation-level autopilot meta-pipeline across the meta-routing-selected sub-squads.

## Flow

1. Hand **request** to the Squad Federation Coordinator and let its per-turn protocol classify the request to one or more sub-squads and run each scoped to its own squad root.
2. When **squad** is provided, route the request to that registered sub-squad (escalate when the name is not registered); otherwise let the coordinator match `meta-routing.md`.
3. When **init** is present, or the project has no federation yet, let the coordinator run Federation Init Mode (or Federation Expansion Mode when a federation already exists) before routing. When **promote** is present, or an existing single-squad project asks to move to a federation, let the coordinator run Federation Promotion Mode instead of a from-scratch Init.
4. Forward **profile**, **discovery**, **tier**, **owner**, and **mode** as pass-through hints to the selected sub-squad's coordinator run. When **discovery** is omitted and at least one selected sub-squad qualifies, let the coordinator ask the discovery question once at the federation level and apply the answer to every qualifying sub-squad. When **mode** is `autopilot` and no **squad** target is given, let the coordinator run the federation-level autopilot meta-pipeline; a single **squad** target keeps the forward-only behavior.
5. When **watch** is present, let the coordinator run Watch Mode Bootstrap Mode ahead of any classification: derive the sub-squad name from structural event metadata only, bootstrap the federation, reuse the sub-squad on matching provenance, escalate on a human-owned name collision, and then run that sub-squad's standard single-squad autopilot scoped to `members/<name>/`. An explicit **squad** target overrides the event sub-squad and creates nothing.
6. Let the coordinator own the registry, meta-routing, and two-level state — it seeds `.copilot-tracking/squad/{federation.md,meta-routing.md,state.json}` and each `members/<name>/` sub-squad on first run, and persists federation-level decisions and history through the Squad Scribe while each sub-squad persists its own state under its root.

## Invocation

Dispatch this request to the `Squad Federation Coordinator` agent. This skill does not run the federation logic itself — it only resolves which parameters to pass.
'@
        'squad-governance-report'   = @'
---
name: squad-governance-report
description: "Reads squad state and generates a self-contained HTML governance dashboard (gates, verdicts, cost, dispatches, compliance, timeline, outcomes). Use when the user asks for a squad governance report, dashboard, or audit view."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Governance Report

## Inputs

* **outputPath** (optional): Local filesystem path for the HTML file. Defaults to `docs/squad-governance-report-<YYYY-MM-DD>.html`.
* **squad** (optional): In a federation, scope to a specific sub-squad. When omitted in a federation, the agent aggregates across all sub-squads.
* **period** (optional, defaults to `all`): Time window to include — `all`, `30d`, or `7d`.

## Flow

1. Hand this turn to the Squad Governance Report agent and let its required steps resolve the squad scope, extract the governance data, compute the aggregate metrics, and render the dashboard.
2. Pass **outputPath**, **squad**, and **period** through as-is. The agent owns the default output path, federation scoping, and period filtering.
3. Let the agent own its guardrails: squad state is read-only, every metric is grounded in parsed artifact content, empty sections render their empty state rather than being omitted, and the HTML stays fully self-contained.

## Invocation

Dispatch this request to the `Squad Governance Report` agent. This skill does not extract or render the dashboard itself — it only resolves which parameters to pass.
'@
        'squad-learn'               = @'
---
name: squad-learn
description: "Drafts a sanitized learning from consumer-local squad memory and opens a pull request to promote it upstream or to a tenant learnings repo. Use when the user asks to promote, share, or upstream a learning the squad captured."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Learn

## Inputs

* **target** (optional): Where to promote the learning. `upstream` reaches every consumer of the public hve-squad package on their next sync; `tenant` stays inside your organization's private learnings repository. When omitted, the agent asks after a candidate is drafted.
* **learning** (optional): A specific learning or topic to promote. When omitted, the agent discovers candidates from consumer-local memory.

## Flow

1. Hand this turn to the Squad Learn agent and let its required steps discover candidates, draft and sanitize the entry, resolve the target repository, and prepare the pull request.
2. Pass **target** and **learning** through as-is. The agent owns candidate discovery, the sanitization checklist, and the `SL-` versus `TL-` id convention.
3. Let the agent own its guardrails: live agent memory is read-only, nothing is forked, pushed, or opened without explicit user approval at the impactful-action gate, and unsanitized content stops the run.

## Invocation

Dispatch this request to the `Squad Learn` agent. This skill does not perform discovery or draft the PR itself — it only resolves which parameters to pass.
'@
    }
}

#endregion Functions

#region Main

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $RepoRoot) {
        $RepoRoot = (git rev-parse --show-toplevel 2>$null)
        if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
    }
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

    if (-not $OutputRoot) {
        $OutputRoot = Join-Path (Split-Path -Path $RepoRoot -Parent) 'hve-squad-plugin'
    }

    $source = Resolve-BuildSource -RepoRoot $RepoRoot `
        -RefSpecified $PSBoundParameters.ContainsKey('Ref') -Ref $Ref `
        -SourceRootSpecified $PSBoundParameters.ContainsKey('SourceRoot') -SourceRoot $SourceRoot

    Write-Host "Source:  $($source.Mode) $(if ($source.Mode -eq 'Ref') { $source.Ref } else { $source.SourceRoot })" -ForegroundColor Cyan
    Write-Host "Output:  $OutputRoot" -ForegroundColor Cyan
    Write-Host "Version: $($source.PluginVersion)" -ForegroundColor Cyan
    Write-Host ''

    try {
        # ── Agents: verbatim copy + citation rewrite + inline-fold (P02-T01/T02/T03) ──
        $agentPaths = Get-SourceFileList -Source $source -RepoRoot $RepoRoot -RelativeDir 'squad-src/.github/agents/squad'
        $agentFiles = @($agentPaths | Where-Object { $_ -like '*.agent.md' })
        Write-Host "Agents:  $($agentFiles.Count) files" -ForegroundColor Cyan
        foreach ($relPath in $agentFiles) {
            $fileName = Split-Path -Path $relPath -Leaf
            $content = Get-SourceFileContent -Source $source -RepoRoot $RepoRoot -RelativePath $relPath
            $content = Convert-AgentCitations -FileName $fileName -Content $content
            Write-TextFile -Path (Join-Path $OutputRoot "agents/squad/$fileName") -Content $content -DryRun:$DryRun
        }

        # ── Skill: verbatim port of skills/squad/ + 2 housekeeping edits (P02-T05) ──
        $skillPaths = Get-SourceFileList -Source $source -RepoRoot $RepoRoot -RelativeDir 'squad-src/.github/skills/squad'
        Write-Host "Skill:   $($skillPaths.Count) files under skills/squad/" -ForegroundColor Cyan
        foreach ($relPath in $skillPaths) {
            $subPath = $relPath -replace '^squad-src/\.github/skills/squad/', ''
            $content = Get-SourceFileContent -Source $source -RepoRoot $RepoRoot -RelativePath $relPath

            if ($subPath -eq 'SKILL.md') {
                $content = $content -replace `
                    'the eleven companion instruction files that auto-apply when squad state is touched are catalogued in', `
                    'the companion hook rules and reference files it depends on are catalogued in'
                $content = $content.Replace(
                    ', and `squad-task.issue-template.yml` — keep their existing paths.',
                    ', `squad-task.issue-template.yml`, and `invocations/` (the 5 prompt-derived invocation skills) — keep their existing paths.'
                )
            }
            elseif ($subPath -eq 'references/00-index.md') {
                $content = $content -replace `
                    '## Companion instruction files', `
                    '## Companion hook rules and reference files'
                $content = $content -replace `
                    'The `squad` skill complements eleven instruction files that auto-apply when squad state is touched\. Their `applyTo` globs only fire in a host that loads modular instructions, so a rule that must hold unconditionally belongs in a reference file above, not only here\.', `
                    'In the plugin distribution, these rules no longer ship as `.instructions.md` files: deterministic enforcement moves to `hooks.json` and procedural/reference content moves into the reference files above. The bullets below are pending their P03 rewrite to cite the hook and reference-file targets directly.'
            }

            Write-TextFile -Path (Join-Path $OutputRoot "skills/squad/$subPath") -Content $content -DryRun:$DryRun
        }

        # ── Invocation skills: 5 prompt-derived skills (P02-T04) ──
        $invocationSkills = New-InvocationSkillContent
        Write-Host "Skills:  $($invocationSkills.Count) invocation skills" -ForegroundColor Cyan
        foreach ($name in $invocationSkills.Keys) {
            Write-TextFile -Path (Join-Path $OutputRoot "skills/squad/invocations/$name/SKILL.md") -Content $invocationSkills[$name] -DryRun:$DryRun
        }

        # ── plugin.json (P02-T06; hooks/mcpServers fields added, P03/P04-aware) ──
        $pluginManifest = [ordered]@{
            '$schema'     = 'https://raw.githubusercontent.com/github/open-plugin-spec/main/schemas/plugin.schema.json'
            name          = 'hve-squad'
            version       = $source.PluginVersion
            description   = "Plugin distribution tree for hve-squad: $($agentFiles.Count) Squad Copilot agents and the squad skill (including 5 invocation skills under skills/squad/invocations/), generated and release-gated from Peter-N91/hve-squad."
            agents        = @('agents/squad/')
            skills        = @('skills/squad/')
            hooks         = 'hooks.json'
            mcpServers    = '.mcp.json'
        }
        Write-TextFile -Path (Join-Path $OutputRoot '.github/plugin/plugin.json') `
            -Content (($pluginManifest | ConvertTo-Json -Depth 10) + "`n") -DryRun:$DryRun

        # ── marketplace.json (P02-T07 scaffold, P04-T02-aware) ──
        $marketplaceManifest = [ordered]@{
            name       = 'hve-squad-plugin'
            owner      = [ordered]@{ name = 'Peter-N91' }
            metadata   = [ordered]@{
                description = 'Marketplace for the hve-squad GitHub Copilot plugin, generated and release-gated from Peter-N91/hve-squad.'
                version     = $source.PluginVersion
            }
            autoUpdate = $true
            plugins    = @(
                [ordered]@{
                    name        = 'hve-squad'
                    description = $pluginManifest.description
                    version     = $source.PluginVersion
                    source      = [ordered]@{
                        source = 'github'
                        repo   = 'Peter-N91/hve-squad-plugin'
                        ref    = 'main'
                    }
                    repository  = 'https://github.com/Peter-N91/hve-squad-plugin'
                    license     = 'MIT'
                }
            )
        }
        Write-TextFile -Path (Join-Path $OutputRoot '.github/plugin/marketplace.json') `
            -Content (($marketplaceManifest | ConvertTo-Json -Depth 10) + "`n") -DryRun:$DryRun

        # ── .mcp.json (P03-T04; version-pinned, never silently re-pinned) ──
        $mcpJsonPath = Join-Path $OutputRoot '.mcp.json'
        $resolvedMcpVersion = $McpVersion
        if (-not $resolvedMcpVersion) {
            if (Test-Path -LiteralPath $mcpJsonPath) {
                $existingMcp = Get-Content -LiteralPath $mcpJsonPath -Raw | ConvertFrom-Json
                $existingArgs = $existingMcp.mcpServers.'hve-squad'.args
                $pinnedArg = @($existingArgs) | Where-Object { $_ -like '@hve-squad/mcp@*' } | Select-Object -First 1
                if ($pinnedArg) { $resolvedMcpVersion = $pinnedArg -replace '^@hve-squad/mcp@', '' }
            }
            if (-not $resolvedMcpVersion) {
                throw "No -McpVersion given and no existing pin found at '$mcpJsonPath'. Pass -McpVersion <exact @hve-squad/mcp version> on first generation."
            }
            Write-Host "MCP:     reusing existing pin @hve-squad/mcp@$resolvedMcpVersion (pass -McpVersion to bump deliberately)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "MCP:     pinning @hve-squad/mcp@$resolvedMcpVersion" -ForegroundColor Cyan
        }
        $mcpManifest = [ordered]@{
            mcpServers = [ordered]@{
                'hve-squad' = [ordered]@{
                    type    = 'stdio'
                    command = 'npx'
                    args    = @('-y', "@hve-squad/mcp@$resolvedMcpVersion")
                }
            }
        }
        Write-TextFile -Path $mcpJsonPath -Content (($mcpManifest | ConvertTo-Json -Depth 10) + "`n") -DryRun:$DryRun

        Write-Host ''
        Write-Host "Build complete: $OutputRoot" -ForegroundColor Green
    }
    catch {
        Write-Error -ErrorAction Continue "Build-SquadPlugin failed: $($_.Exception.Message)"
        exit 1
    }
}

#endregion Main
