#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Compares the deployable agent, skill, and prompt surface between two microsoft/hve-core
    refs and reports the delta that matters to the squad roster.
.DESCRIPTION
    The squad roster binds each role to an hve-core agent by its exact `name:` frontmatter
    value. When hve-core renames, removes, or converts an agent into a skill, a roster row
    silently stops resolving: the dispatch returns nothing and a lighter coordinator model
    tends to fill the gap by doing the role's work inline. That is invisible in a diff of
    SHAs, so this script turns it into an explicit signal.

    Agents are not the only binding. A squad-owned charter reaches its capability through a
    named skill, and two charters execute a deployed prompt by path. Those bindings break the
    same way and just as silently, so the script covers all three surfaces.

    For each ref the script collects:
      - every `.github/agents/**/*.agent.md`: its exact `name:` value, and whether it is
        dispatchable (it is NOT when `disable-model-invocation: true`)
      - every `.github/skills/**/SKILL.md`: its skill id, and whether a model may invoke it
        (it may NOT when `disable-model-invocation: true`)
      - every `.github/prompts/**/*.prompt.md`: its prompt id

    It then reports what was added, removed, or flipped, and cross-checks each removed or
    newly-uninvocable id against the local squad source tree. An id the squad still
    references is a BREAKING delta: the package must be adapted before its hve-core pin moves.
.PARAMETER FromRef
    The baseline hve-core ref. Defaults to the SHA currently pinned in the apm file.
.PARAMETER ToRef
    The candidate hve-core ref. Defaults to 'main'.
.PARAMETER ApmFile
    The apm manifest used to discover FromRef when it is not supplied.
.PARAMETER RepoSlug
    The hve-core repository slug.
.PARAMETER SquadSourceRoot
    The local squad source tree cross-checked for references to removed ids.
.PARAMETER MarkdownPath
    Optional path to write a human-readable delta brief. This is the file handed to the
    squad as the adaptation task description.
.PARAMETER JsonPath
    Optional path to write the machine-readable delta.
.PARAMETER GitHubOutput
    Emit `has_delta`, `is_breaking`, `added_count`, `removed_count`, `flipped_count`,
    `skill_delta_count`, and `prompt_delta_count` to $env:GITHUB_OUTPUT for workflow branching.
.EXAMPLE
    ./scripts/Get-HveCoreCastDelta.ps1
    Compares the pinned SHA against hve-core main and prints the delta.
.EXAMPLE
    ./scripts/Get-HveCoreCastDelta.ps1 -ToRef 214791a0 -MarkdownPath delta.md -GitHubOutput
    Writes an adaptation brief and sets workflow outputs.
.NOTES
    Read-only. Never edits apm.yml or squad-src.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$FromRef,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ToRef = 'main',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ApmFile = 'apm.yml',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoSlug = 'microsoft/hve-core',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SquadSourceRoot = 'squad-src',

    [Parameter(Mandatory = $false)]
    [string]$MarkdownPath,

    [Parameter(Mandatory = $false)]
    [string]$JsonPath,

    [Parameter(Mandatory = $false)]
    [switch]$GitHubOutput
)

$ErrorActionPreference = 'Stop'

#region Functions
function Get-PinnedHveCoreSha {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Apm manifest '$Path' was not found."
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $match = [regex]::Match($line, 'microsoft/hve-core/.+#([0-9a-f]{7,40})\s*$')
        if ($match.Success) {
            return $match.Groups[1].Value
        }
    }

    throw "No pinned microsoft/hve-core SHA was found in '$Path'."
}

function Get-AgentCastAtRef {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$GitRef
    )
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("hve-cast-" + [Guid]::NewGuid().ToString('N'))
    $repoUrl = "https://github.com/$Repository.git"

    try {
        # init + fetch (not 'clone --branch') so GitRef may be a branch, tag, or bare SHA.
        $null = & git init --quiet $tempRoot 2>&1
        if ($LASTEXITCODE -ne 0) { throw "git init failed for '$Repository'." }

        Push-Location $tempRoot
        try {
            $null = & git remote add origin $repoUrl 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git remote add failed for '$Repository'." }

            $null = & git fetch --depth 1 origin $GitRef 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "git fetch failed for '$Repository@$GitRef'. The ref must be a branch, tag, or commit SHA."
            }

            $resolved = (& git rev-parse FETCH_HEAD 2>&1 | Where-Object { $_ -match '^[0-9a-f]{40}$' } | Select-Object -First 1)
            if ([string]::IsNullOrWhiteSpace($resolved)) {
                throw "git could not resolve a commit for '$Repository@$GitRef'."
            }

            $paths = & git ls-tree -r --name-only FETCH_HEAD -- '.github/agents' '.github/skills' '.github/prompts' 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git ls-tree failed for the hve-core surface paths." }

            $agents = [System.Collections.Generic.List[pscustomobject]]::new()
            $skills = [System.Collections.Generic.List[pscustomobject]]::new()
            $prompts = [System.Collections.Generic.List[pscustomobject]]::new()

            foreach ($path in $paths) {
                if ([string]::IsNullOrWhiteSpace($path)) { continue }
                $trimmed = $path.Trim()

                $isAgent = $trimmed -match '\.agent\.md$'
                $isSkill = $trimmed -match '(^|/)SKILL\.md$'
                $isPrompt = $trimmed -match '\.prompt\.md$'
                if (-not ($isAgent -or $isSkill -or $isPrompt)) { continue }

                $content = (& git show "FETCH_HEAD:$trimmed" 2>&1) -join "`n"
                if ($LASTEXITCODE -ne 0) { continue }

                # A model cannot reach an agent, skill, or prompt that opts out of model
                # invocation, whichever surface it lives on.
                $noInvoke = [regex]::IsMatch($content, '(?m)^disable-model-invocation:\s*true\s*$')
                $nameMatch = [regex]::Match($content, '(?m)^name:\s*(.+?)\s*$')

                if ($isAgent) {
                    if (-not $nameMatch.Success) { continue }
                    $agents.Add([pscustomobject]@{
                            Name         = $nameMatch.Groups[1].Value.Trim('"', "'", ' ')
                            Path         = $trimmed
                            Dispatchable = -not $noInvoke
                        })
                    continue
                }

                if ($isSkill) {
                    # A charter names a skill by its id, which is the frontmatter name when
                    # present and otherwise the directory the SKILL.md sits in.
                    $id = if ($nameMatch.Success) {
                        $nameMatch.Groups[1].Value.Trim('"', "'", ' ')
                    }
                    else {
                        Split-Path -Path (Split-Path -Path $trimmed -Parent) -Leaf
                    }
                    $skills.Add([pscustomobject]@{
                            Name         = $id
                            Path         = $trimmed
                            Dispatchable = -not $noInvoke
                        })
                    continue
                }

                # A charter executes a prompt by its deployed file name, so the id is the
                # basename rather than the source path, which APM flattens on install.
                $promptId = [System.IO.Path]::GetFileName($trimmed) -replace '\.prompt\.md$', ''
                $prompts.Add([pscustomobject]@{
                        Name         = $promptId
                        Path         = $trimmed
                        Dispatchable = -not $noInvoke
                    })
            }

            return [pscustomobject]@{
                Ref            = $GitRef
                ResolvedCommit = $resolved.Trim()
                Agents         = @($agents)
                Skills         = @($skills)
                Prompts        = @($prompts)
            }
        }
        finally {
            Pop-Location
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

function Get-SquadReferenceCount {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentName,

        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $false)]
        [ValidateSet('agent', 'skill', 'prompt')]
        [string]$Kind = 'agent'
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        return [pscustomobject]@{ Count = 0; Files = @() }
    }

    $escaped = [regex]::Escape($AgentName)

    # Match only the contexts in which the squad actually binds the id, so a short id that
    # is also an ordinary English word (for example 'Memory' or 'vex') does not match
    # incidental prose.
    $pattern = switch ($Kind) {
        #   1. a YAML `agents:` list item      ->   - Agent Name
        #   2. a roster/table cell             ->  | Agent Name |
        #   3. an inline code reference        ->  `Agent Name`
        'agent' { "(?m)^\s*-\s+$escaped\s*$|\|\s*$escaped\s*\||``$escaped``" }
        #   a charter names a skill in inline code, or apm.yml pins its source path
        'skill' { "``$escaped``|/skills/[^\s``]*$escaped(?![\w-])" }
        #   a charter names a prompt by deployed path, and prose names its slash command
        'prompt' { "$escaped\.prompt\.md|/$escaped(?![\w-])" }
    }

    $hits = Get-ChildItem -LiteralPath $Root -Recurse -File -Include '*.md', '*.yml' -ErrorAction SilentlyContinue |
        Select-String -Pattern $pattern -AllMatches -ErrorAction SilentlyContinue

    $files = @($hits | ForEach-Object { $_.Path } | Sort-Object -Unique)
    return [pscustomobject]@{
        Count = @($hits).Count
        Files = $files
    }
}

function Get-SurfaceDelta {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Before,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$After
    )

    $beforeByName = @{}
    foreach ($item in $Before) { $beforeByName[$item.Name] = $item }
    $afterByName = @{}
    foreach ($item in $After) { $afterByName[$item.Name] = $item }

    $added = @($After | Where-Object { -not $beforeByName.ContainsKey($_.Name) } | Sort-Object Name)
    $removed = @($Before | Where-Object { -not $afterByName.ContainsKey($_.Name) } | Sort-Object Name)

    $flipped = @(
        foreach ($item in $Before) {
            if (-not $afterByName.ContainsKey($item.Name)) { continue }
            $now = $afterByName[$item.Name]
            if ($item.Dispatchable -ne $now.Dispatchable) {
                [pscustomobject]@{
                    Name   = $item.Name
                    Path   = $now.Path
                    Before = if ($item.Dispatchable) { 'model-invocable' } else { 'user-invocable-only' }
                    After  = if ($now.Dispatchable) { 'model-invocable' } else { 'user-invocable-only' }
                }
            }
        }
    ) | Sort-Object Name

    return [pscustomobject]@{
        Added   = @($added)
        Removed = @($removed)
        Flipped = @($flipped)
    }
}
#endregion

#region Main
if ([string]::IsNullOrWhiteSpace($FromRef)) {
    $FromRef = Get-PinnedHveCoreSha -Path $ApmFile
    Write-Verbose "Baseline resolved from '$ApmFile': $FromRef"
}

Write-Host "Comparing $RepoSlug surface: $FromRef -> $ToRef"

$before = Get-AgentCastAtRef -Repository $RepoSlug -GitRef $FromRef
$after = Get-AgentCastAtRef -Repository $RepoSlug -GitRef $ToRef

if ($before.ResolvedCommit -eq $after.ResolvedCommit) {
    Write-Host "Both refs resolve to $($after.ResolvedCommit) - no cast delta possible."
}

$agentDelta = Get-SurfaceDelta -Before $before.Agents -After $after.Agents
$skillDelta = Get-SurfaceDelta -Before $before.Skills -After $after.Skills
$promptDelta = Get-SurfaceDelta -Before $before.Prompts -After $after.Prompts

$added = $agentDelta.Added
$removed = $agentDelta.Removed
$flipped = $agentDelta.Flipped

# A removed id, or one that became user-invocable-only, breaks the squad only when the
# squad source still references it. The same test applies to all three surfaces: a charter
# that names a vanished skill, or executes a vanished prompt, fails exactly as silently as
# a roster row pointing at a vanished agent.
$atRisk = [System.Collections.Generic.List[pscustomobject]]::new()
$surfaces = @(
    [pscustomobject]@{ Kind = 'agent'; Label = 'agent'; Delta = $agentDelta }
    [pscustomobject]@{ Kind = 'skill'; Label = 'skill'; Delta = $skillDelta }
    [pscustomobject]@{ Kind = 'prompt'; Label = 'prompt'; Delta = $promptDelta }
)

foreach ($surface in $surfaces) {
    foreach ($item in $surface.Delta.Removed) {
        $refs = Get-SquadReferenceCount -AgentName $item.Name -Root $SquadSourceRoot -Kind $surface.Kind
        if ($refs.Count -gt 0) {
            $atRisk.Add([pscustomobject]@{
                    Name   = $item.Name
                    Kind   = $surface.Label
                    Reason = "removed from hve-core"
                    Hits   = $refs.Count
                    Files  = $refs.Files
                })
        }
    }
    foreach ($item in $surface.Delta.Flipped) {
        if ($item.After -ne 'user-invocable-only') { continue }
        $refs = Get-SquadReferenceCount -AgentName $item.Name -Root $SquadSourceRoot -Kind $surface.Kind
        if ($refs.Count -gt 0) {
            $atRisk.Add([pscustomobject]@{
                    Name   = $item.Name
                    Kind   = $surface.Label
                    Reason = 'became user-invocable-only (a model can no longer reach it)'
                    Hits   = $refs.Count
                    Files  = $refs.Files
                })
        }
    }
}

$skillDeltaCount = $skillDelta.Added.Count + $skillDelta.Removed.Count + $skillDelta.Flipped.Count
$promptDeltaCount = $promptDelta.Added.Count + $promptDelta.Removed.Count + $promptDelta.Flipped.Count
$hasDelta = ($added.Count + $removed.Count + $flipped.Count + $skillDeltaCount + $promptDeltaCount) -gt 0
$isBreaking = $atRisk.Count -gt 0

$result = [pscustomobject]@{
    repo           = $RepoSlug
    fromRef        = $FromRef
    fromCommit     = $before.ResolvedCommit
    toRef          = $ToRef
    toCommit       = $after.ResolvedCommit
    hasDelta       = $hasDelta
    isBreaking     = $isBreaking
    added          = @($added | Select-Object Name, Path, Dispatchable)
    removed        = @($removed | Select-Object Name, Path, Dispatchable)
    dispatchFlips  = @($flipped)
    skillsAdded    = @($skillDelta.Added | Select-Object Name, Path, Dispatchable)
    skillsRemoved  = @($skillDelta.Removed | Select-Object Name, Path, Dispatchable)
    skillFlips     = @($skillDelta.Flipped)
    promptsAdded   = @($promptDelta.Added | Select-Object Name, Path)
    promptsRemoved = @($promptDelta.Removed | Select-Object Name, Path)
    squadAtRisk    = @($atRisk)
}

#region Reporting
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# hve-core surface delta')
$lines.Add('')
$lines.Add("- Repository: ``$RepoSlug``")
$lines.Add("- From: ``$($before.ResolvedCommit)`` (currently pinned)")
$lines.Add("- To: ``$($after.ResolvedCommit)`` (``$ToRef``)")
$lines.Add("- Surfaces compared: agents, skills, prompts")
$lines.Add("- Verdict: " + $(if ($isBreaking) { '**BREAKING** - the squad references agents, skills, or prompts this ref no longer exposes' } elseif ($hasDelta) { 'non-breaking surface change' } else { 'no surface change' }))
$lines.Add('')

if ($atRisk.Count -gt 0) {
    $lines.Add('## Squad references that will stop resolving')
    $lines.Add('')
    $lines.Add('| Id | Kind | Why | References in squad-src |')
    $lines.Add('| --- | --- | --- | --- |')
    foreach ($item in $atRisk) {
        $lines.Add("| ``$($item.Name)`` | $($item.Kind) | $($item.Reason) | $($item.Hits) |")
    }
    $lines.Add('')
    $lines.Add('An agent must be repointed at a shipped, dispatchable agent or replaced by a squad-owned thin charter. A skill or prompt must be replaced by a shipped equivalent, or the charter that names it must state what it does instead. Either way, before the pin moves.')
    $lines.Add('')
    foreach ($item in $atRisk) {
        $lines.Add("### ``$($item.Name)`` ($($item.Kind)) - files to update")
        $lines.Add('')
        foreach ($file in $item.Files) {
            $lines.Add("- ``$file``")
        }
        $lines.Add('')
    }
}

if ($removed.Count -gt 0) {
    $lines.Add('## Removed from hve-core')
    $lines.Add('')
    foreach ($agent in $removed) { $lines.Add("- ``$($agent.Name)`` (was ``$($agent.Path)``)") }
    $lines.Add('')
}

if ($added.Count -gt 0) {
    $lines.Add('## Added in hve-core')
    $lines.Add('')
    foreach ($agent in $added) {
        $flag = if ($agent.Dispatchable) { 'dispatchable' } else { 'user-invocable-only' }
        $lines.Add("- ``$($agent.Name)`` ($flag) - ``$($agent.Path)``")
    }
    $lines.Add('')
}

if ($flipped.Count -gt 0) {
    $lines.Add('## Dispatchability changed')
    $lines.Add('')
    $lines.Add('| Agent name | Before | After |')
    $lines.Add('| --- | --- | --- |')
    foreach ($agent in $flipped) { $lines.Add("| ``$($agent.Name)`` | $($agent.Before) | $($agent.After) |") }
    $lines.Add('')
}

if ($skillDelta.Removed.Count -gt 0 -or $skillDelta.Flipped.Count -gt 0 -or $skillDelta.Added.Count -gt 0) {
    $lines.Add('## Skills')
    $lines.Add('')
    foreach ($skill in $skillDelta.Removed) { $lines.Add("- Removed: ``$($skill.Name)`` (was ``$($skill.Path)``)") }
    foreach ($skill in $skillDelta.Flipped) { $lines.Add("- Invocability changed: ``$($skill.Name)`` $($skill.Before) -> $($skill.After)") }
    foreach ($skill in $skillDelta.Added) { $lines.Add("- Added: ``$($skill.Name)`` - ``$($skill.Path)``") }
    $lines.Add('')
}

if ($promptDelta.Removed.Count -gt 0 -or $promptDelta.Added.Count -gt 0) {
    $lines.Add('## Prompts')
    $lines.Add('')
    foreach ($prompt in $promptDelta.Removed) { $lines.Add("- Removed: ``$($prompt.Name)`` (was ``$($prompt.Path)``)") }
    foreach ($prompt in $promptDelta.Added) { $lines.Add("- Added: ``$($prompt.Name)`` - ``$($prompt.Path)``") }
    $lines.Add('')
}

if (-not $hasDelta) {
    $lines.Add('The deployable agents, skills, and prompts are identical between the two refs. A mechanical SHA bump is safe.')
    $lines.Add('')
}

$markdown = $lines -join [Environment]::NewLine

if ($MarkdownPath) {
    $markdown | Set-Content -LiteralPath $MarkdownPath -Encoding utf8
    Write-Host "Wrote delta brief to $MarkdownPath"
}

if ($JsonPath) {
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $JsonPath -Encoding utf8
    Write-Host "Wrote delta JSON to $JsonPath"
}

if ($GitHubOutput -and $env:GITHUB_OUTPUT) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "has_delta=$($hasDelta.ToString().ToLowerInvariant())"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "is_breaking=$($isBreaking.ToString().ToLowerInvariant())"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "added_count=$($added.Count)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "removed_count=$($removed.Count)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "flipped_count=$($flipped.Count)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "skill_delta_count=$skillDeltaCount"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "prompt_delta_count=$promptDeltaCount"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "from_commit=$($before.ResolvedCommit)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "to_commit=$($after.ResolvedCommit)"
}

Write-Host ''
Write-Host $markdown
#endregion

return $result
#endregion
