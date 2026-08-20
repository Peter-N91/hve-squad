# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Builds the model of an installed hve-squad package that the Tier 0 suite asserts on.
# Pester discovers and runs in separate scopes, so both phases call Get-SquadPackageModel
# rather than sharing state through script-scoped variables.

#Requires -Version 7.4

Set-StrictMode -Version Latest

# The host caps an agent's prompt BODY; frontmatter is not counted against it.
$script:AgentBodyCharLimit = 30000

$script:EntrypointPromptNames = @(
    'squad.prompt.md'
    'squad-federation.prompt.md'
    'squad-document.prompt.md'
    'squad-governance-report.prompt.md'
    'squad-learn.prompt.md'
)

# Built-in host modes a prompt may bind to instead of a custom agent.
$script:ReservedAgentModes = @('agent', 'ask', 'edit')

# The `agent`-kind rows of *Registered External Cast* in squad-roster.instructions.md.
# These are opt-in by design and deliberately not shipped: an uninstalled one is an
# absent role the coordinator escalates on, not a packaging defect. Adding an external
# agent without adding it here fails PKG-02, which is the intended forcing function.
$script:OptInExternalAgents = @(
    'Power Platform Expert'
    'Power Platform MCP Integration Expert'
    'Declarative Agents Architect'
    'MCP M365 Agent Expert'
    'QA'
    'GitHub Actions Expert'
    'aws-principal-architect'
    'aws-cloud-expert'
    'aws-serverless-architect'
    'AWS Incident Triage'
)

function Read-SquadArtifact {
    <#
    .SYNOPSIS
        Splits a Copilot artifact into its frontmatter map and its prompt body.
    .PARAMETER Path
        Full path to a .agent.md, .prompt.md, or .instructions.md file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw
    $meta = @{}
    $body = $raw
    $hasFront = $raw.StartsWith('---')

    if ($raw -match '(?s)^---\r?\n(.*?)\r?\n---\r?\n?(.*)$') {
        $body = $Matches[2]
        $listKey = $null

        foreach ($line in ($Matches[1] -split '\r?\n')) {
            # A list item continues whichever key opened with an empty value.
            if ($listKey -and $line -match '^\s*-\s+(.+?)\s*$') {
                $meta[$listKey] = @($meta[$listKey]) + $Matches[1].Trim("'", '"')
                continue
            }

            if ($line -match '^([A-Za-z0-9_-]+):\s*(.*)$') {
                $key = $Matches[1]
                $value = $Matches[2].Trim()

                # An inline flow sequence is a complete value, not the start of a block list.
                if ($value -match '^\[(.*)\]$') {
                    $inner = $Matches[1].Trim()
                    $meta[$key] = if ($inner) { @($inner -split ',' | ForEach-Object { $_.Trim().Trim("'", '"') }) } else { @() }
                    $listKey = $null
                }
                elseif ($value) {
                    $meta[$key] = $value.Trim("'", '"')
                    $listKey = $null
                }
                else {
                    $meta[$key] = @()
                    $listKey = $key
                }
            }
        }
    }

    @{
        Path      = $Path
        Name      = Split-Path $Path -Leaf
        Slug      = (Split-Path $Path -Leaf) -replace '\.(agent|prompt|instructions)\.md$', ''
        Meta      = $meta
        Body      = $body
        BodyChars = $body.Length
        HasFront  = $hasFront
        Limit     = $script:AgentBodyCharLimit
    }
}

function Get-SquadPackageModel {
    <#
    .SYNOPSIS
        Enumerates an installed package into the collections the Tier 0 cases assert on.
    .PARAMETER PackageRoot
        Directory holding the installed tree - the parent of .github/ and .agents/.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageRoot
    )

    function Get-Artifacts {
        param([string]$Directory, [string]$Filter)

        if (-not (Test-Path -LiteralPath $Directory)) { return @() }
        @(Get-ChildItem -LiteralPath $Directory -Recurse -Filter $Filter | ForEach-Object { Read-SquadArtifact -Path $_.FullName })
    }

    $agents = Get-Artifacts (Join-Path $PackageRoot '.github/agents') '*.agent.md'
    $prompts = Get-Artifacts (Join-Path $PackageRoot '.github/prompts') '*.prompt.md'
    $instructions = Get-Artifacts (Join-Path $PackageRoot '.github/instructions') '*.instructions.md'
    $skillRoot = Join-Path $PackageRoot '.agents/skills'

    $agentNames = @($agents | ForEach-Object { $_.Meta['name'] } | Where-Object { $_ })
    # A binding may name the agent's `name:` or its file slug; both resolve on the host.
    $agentIdentifiers = @($agentNames) + @($agents | ForEach-Object { $_.Slug })
    $squadSkillRoot = Join-Path $PackageRoot '.agents/skills/squad'

    # Squad-owned agents are the ones this package governs. HVE Core agents carry
    # their own contracts and are asserted only where the squad references them.
    $squadAgents = @($agents | Where-Object { $_.Name -like 'squad-*' })

    # A prompt's `agent:` names the agent that owns an entrypoint. Every other squad
    # agent is a worker and must stay out of the user-facing picker.
    $entrypointAgentNames = @($prompts | ForEach-Object { $_.Meta['agent'] } | Where-Object { $_ })

    $rosterEntries = @(
        foreach ($owner in $agents) {
            foreach ($member in @($owner.Meta['agents'])) {
                if ($member) { @{ Owner = $owner.Name; Member = $member } }
            }
        }
    )
    # Skill Reference Contract: an agent names the exact reference files it must read.
    # A reference may belong to any bundled skill, so resolution searches them all.
    $referenceRoots = @(
        if (Test-Path -LiteralPath $skillRoot) {
            Get-ChildItem -LiteralPath $skillRoot -Recurse -Directory -Filter 'references' | ForEach-Object { $_.FullName }
        }
    )

    $referenceClaims = @(
        $seen = @{}
        foreach ($agent in $squadAgents) {
            foreach ($match in [regex]::Matches($agent.Body, 'references/([A-Za-z0-9._-]+\.md)')) {
                $reference = $match.Groups[1].Value
                $key = "$($agent.Name)|$reference"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    @{ Agent = $agent.Name; Reference = $reference; Roots = $referenceRoots }
                }
            }
        }
    )

    $skillLinks = @(
        if (Test-Path -LiteralPath $squadSkillRoot) {
            $seen = @{}
            foreach ($file in Get-ChildItem -LiteralPath $squadSkillRoot -Recurse -Filter '*.md') {
                $content = Get-Content -LiteralPath $file.FullName -Raw
                foreach ($match in [regex]::Matches($content, '\]\((?!https?://|#)([^)#]+\.md)(?:#[^)]*)?\)')) {
                    $link = $match.Groups[1].Value
                    $key = "$($file.Name)|$link"
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        @{ Source = $file.Name; Link = $link; Base = $file.DirectoryName }
                    }
                }
            }
        }
    )

    @{
        PackageRoot          = $PackageRoot
        Agents               = $agents
        Prompts              = $prompts
        Instructions         = $instructions
        AgentNames           = $agentNames
        AgentIdentifiers     = $agentIdentifiers
        OptInExternalAgents  = $script:OptInExternalAgents
        SquadAgents          = $squadAgents
        ThirdPartyAgents     = @($agents | Where-Object { $_.Name -notlike 'squad-*' })
        EntrypointAgentNames = $entrypointAgentNames
        BoundPrompts         = @($prompts | Where-Object { $_.Meta['agent'] -and $script:ReservedAgentModes -notcontains $_.Meta['agent'] })
        RosterEntries        = $rosterEntries
        ReferenceClaims      = $referenceClaims
        SkillLinks           = $skillLinks
        SquadSkillRoot       = $squadSkillRoot
        AgentBodyCharLimit   = $script:AgentBodyCharLimit
        EntrypointPrompts    = @($script:EntrypointPromptNames | ForEach-Object { @{ Expected = $_ } })
        FloorInstructions    = @($instructions | Where-Object { $_.Name -eq 'squad-floor.instructions.md' })
    }
}

Export-ModuleMember -Function Read-SquadArtifact, Get-SquadPackageModel
