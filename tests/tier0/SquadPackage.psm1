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

function Get-MarkdownTableRows {
    <#
    .SYNOPSIS
        Returns the raw cell array of every data row in the first GFM table whose
        header row's first cell equals $HeaderCell.
    .DESCRIPTION
        Deliberately not a general markdown-table parser: it assumes every row starts
        and ends with `|` and that a header row is followed immediately by a
        `|---|`-shaped separator row, which is the shape every table this function
        reads (Squad Profiles, Squad Packs, Cast Catalog) actually uses. $Body may
        hold more than one table; only the first whose header matches $HeaderCell is
        read, so callers that need a specific table (for example Cast Catalog, not the
        later Registered External Cast table that also starts with `Role`) must scope
        $Body to that table's section first.
    .PARAMETER Body
        Raw markdown text to scan.
    .PARAMETER HeaderCell
        Exact text of the header row's first cell, for example 'Profile' or 'Role'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Body,

        [Parameter(Mandatory)]
        [string]$HeaderCell
    )

    $lines = $Body -split '\r?\n'
    $rows = New-Object System.Collections.Generic.List[object]
    $inTable = $false
    $headerPattern = "^\|\s*$([regex]::Escape($HeaderCell))\s*\|"

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if (-not $inTable) {
            if ($line -match $headerPattern -and
                $i + 1 -lt $lines.Count -and $lines[$i + 1] -match '^\|[\s:|-]+$') {
                $inTable = $true
                $i++ # the separator row carries no data; skip past it
            }
            continue
        }

        if ($line -notmatch '^\|.*\|\s*$') {
            break # the table ended; a second same-named table (if any) is not this one
        }

        $rows.Add(@($line -split '\|'))
    }

    # `@($rows)` (rather than `.ToArray()`) makes PowerShell's array-literal binder
    # try to flatten a `List[object]` whose own elements are string arrays, which
    # throws `ArgumentException: Argument types do not match` on this host's
    # PowerShell 7.4. `.ToArray()` returns the outer array without touching the
    # element type.
    return $rows.ToArray()
}

function Get-SquadRosterRoles {
    <#
    .SYNOPSIS
        Extracts every role named in a Squad Profiles or Squad Packs table's members
        column, across one or more raw file bodies.
    .PARAMETER Body
        One or more raw file contents to scan (for example
        squad-roster.instructions.md and profiles-and-packs.md).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Body
    )

    $roles = New-Object System.Collections.Generic.List[string]

    foreach ($text in $Body) {
        foreach ($headerCell in @('Profile', 'Pack')) {
            foreach ($cells in (Get-MarkdownTableRows -Body $text -HeaderCell $headerCell)) {
                # cells[0] is the empty text before the row's leading `|`; cells[1] is
                # the Profile/Pack label; cells[2] is the members/adds column.
                if ($cells.Count -lt 3) { continue }

                foreach ($role in ($cells[2] -split ',')) {
                    $clean = $role.Trim().Trim('`').Trim()
                    if ($clean) { $roles.Add($clean) }
                }
            }
        }
    }

    return @($roles | Sort-Object -Unique)
}

function Get-SquadCastCatalogRoles {
    <#
    .SYNOPSIS
        Extracts every role named in the Cast Catalog table's Role column.
    .DESCRIPTION
        Scopes $Body to the `## Cast Catalog` section (up to the next heading of any
        level) before reading the table, so the later `Registered External Cast`
        table - whose own Role column cites catalog roles rather than declaring new
        ones - is never read as a second Cast Catalog.
    .PARAMETER Body
        Raw content of roster-catalog.md (or an equivalent fixture string).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Body
    )

    $lines = $Body -split '\r?\n'
    $start = $null

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^## Cast Catalog\s*$') { $start = $i; break }
    }
    if ($null -eq $start) { return @() }

    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^#{1,6}\s') { $end = $i; break }
    }

    $section = ($lines[$start..($end - 1)]) -join "`n"
    $roles = New-Object System.Collections.Generic.List[string]

    foreach ($cells in (Get-MarkdownTableRows -Body $section -HeaderCell 'Role')) {
        # cells[0] is the empty text before the row's leading `|`; cells[1] is Role.
        if ($cells.Count -lt 2) { continue }

        $clean = $cells[1].Trim().Trim('`').Trim()
        if ($clean -and $clean -ne '—') { $roles.Add($clean) }
    }

    return @($roles | Sort-Object -Unique)
}

Export-ModuleMember -Function Read-SquadArtifact, Get-SquadPackageModel, Get-MarkdownTableRows, Get-SquadRosterRoles, Get-SquadCastCatalogRoles
