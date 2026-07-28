#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Compares the deployable agent cast between two microsoft/hve-core refs and reports
    the delta that matters to the squad roster.
.DESCRIPTION
    The squad roster binds each role to an hve-core agent by its exact `name:` frontmatter
    value. When hve-core renames, removes, or converts an agent into a skill, a roster row
    silently stops resolving: the dispatch returns nothing and a lighter coordinator model
    tends to fill the gap by doing the role's work inline. That is invisible in a diff of
    SHAs, so this script turns it into an explicit signal.

    For each ref the script collects every `.github/agents/**/*.agent.md` file and records:
      - the exact `name:` frontmatter value
      - whether the agent is dispatchable (it is NOT when `disable-model-invocation: true`)

    It then reports agents added, removed, or whose dispatchability flipped, and cross-checks
    each removed or newly-undispatchable name against the local squad source tree. A name the
    squad still references is a BREAKING delta: the package must be adapted before its
    hve-core pin moves.
.PARAMETER FromRef
    The baseline hve-core ref. Defaults to the SHA currently pinned in the apm file.
.PARAMETER ToRef
    The candidate hve-core ref. Defaults to 'main'.
.PARAMETER ApmFile
    The apm manifest used to discover FromRef when it is not supplied.
.PARAMETER RepoSlug
    The hve-core repository slug.
.PARAMETER SquadSourceRoot
    The local squad source tree cross-checked for references to removed agent names.
.PARAMETER MarkdownPath
    Optional path to write a human-readable delta brief. This is the file handed to the
    squad as the adaptation task description.
.PARAMETER JsonPath
    Optional path to write the machine-readable delta.
.PARAMETER GitHubOutput
    Emit `has_delta`, `is_breaking`, `added_count`, `removed_count`, and `flipped_count`
    to $env:GITHUB_OUTPUT for workflow branching.
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

            $paths = & git ls-tree -r --name-only FETCH_HEAD -- '.github/agents' 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git ls-tree failed for '.github/agents'." }

            $agents = [System.Collections.Generic.List[pscustomobject]]::new()
            foreach ($path in $paths) {
                if ([string]::IsNullOrWhiteSpace($path)) { continue }
                if ($path -notmatch '\.agent\.md$') { continue }

                $content = (& git show "FETCH_HEAD:$path" 2>&1) -join "`n"
                if ($LASTEXITCODE -ne 0) { continue }

                $nameMatch = [regex]::Match($content, '(?m)^name:\s*(.+?)\s*$')
                if (-not $nameMatch.Success) { continue }

                $noDispatch = [regex]::IsMatch($content, '(?m)^disable-model-invocation:\s*true\s*$')

                $agents.Add([pscustomobject]@{
                        Name         = $nameMatch.Groups[1].Value.Trim('"', "'", ' ')
                        Path         = $path.Trim()
                        Dispatchable = -not $noDispatch
                    })
            }

            return [pscustomobject]@{
                Ref            = $GitRef
                ResolvedCommit = $resolved.Trim()
                Agents         = @($agents)
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
        [string]$Root
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        return [pscustomobject]@{ Count = 0; Files = @() }
    }

    # Only count the three contexts in which the squad actually binds an agent, so a
    # short agent name that is also an ordinary English word (for example 'Memory')
    # does not match incidental prose:
    #   1. a YAML `agents:` list item      ->   - Agent Name
    #   2. a roster/table cell             ->  | Agent Name |
    #   3. an inline code reference        ->  `Agent Name`
    $escaped = [regex]::Escape($AgentName)
    $pattern = "(?m)^\s*-\s+$escaped\s*$|\|\s*$escaped\s*\||``$escaped``"
    $hits = Get-ChildItem -LiteralPath $Root -Recurse -File -Include '*.md', '*.yml' -ErrorAction SilentlyContinue |
        Select-String -Pattern $pattern -AllMatches -ErrorAction SilentlyContinue

    $files = @($hits | ForEach-Object { $_.Path } | Sort-Object -Unique)
    return [pscustomobject]@{
        Count = @($hits).Count
        Files = $files
    }
}
#endregion

#region Main
if ([string]::IsNullOrWhiteSpace($FromRef)) {
    $FromRef = Get-PinnedHveCoreSha -Path $ApmFile
    Write-Verbose "Baseline resolved from '$ApmFile': $FromRef"
}

Write-Host "Comparing $RepoSlug cast: $FromRef -> $ToRef"

$before = Get-AgentCastAtRef -Repository $RepoSlug -GitRef $FromRef
$after = Get-AgentCastAtRef -Repository $RepoSlug -GitRef $ToRef

if ($before.ResolvedCommit -eq $after.ResolvedCommit) {
    Write-Host "Both refs resolve to $($after.ResolvedCommit) - no cast delta possible."
}

$beforeByName = @{}
foreach ($agent in $before.Agents) { $beforeByName[$agent.Name] = $agent }
$afterByName = @{}
foreach ($agent in $after.Agents) { $afterByName[$agent.Name] = $agent }

$added = @($after.Agents | Where-Object { -not $beforeByName.ContainsKey($_.Name) } | Sort-Object Name)
$removed = @($before.Agents | Where-Object { -not $afterByName.ContainsKey($_.Name) } | Sort-Object Name)

$flipped = @(
    foreach ($agent in $before.Agents) {
        if (-not $afterByName.ContainsKey($agent.Name)) { continue }
        $now = $afterByName[$agent.Name]
        if ($agent.Dispatchable -ne $now.Dispatchable) {
            [pscustomobject]@{
                Name   = $agent.Name
                Path   = $now.Path
                Before = if ($agent.Dispatchable) { 'dispatchable' } else { 'user-invocable-only' }
                After  = if ($now.Dispatchable) { 'dispatchable' } else { 'user-invocable-only' }
            }
        }
    }
) | Sort-Object Name

# A removed name, or a name that became user-invocable-only, breaks the squad only when
# the squad source still references it.
$atRisk = [System.Collections.Generic.List[pscustomobject]]::new()
foreach ($agent in $removed) {
    $refs = Get-SquadReferenceCount -AgentName $agent.Name -Root $SquadSourceRoot
    if ($refs.Count -gt 0) {
        $atRisk.Add([pscustomobject]@{
                Name    = $agent.Name
                Reason  = 'removed from hve-core'
                Hits    = $refs.Count
                Files   = $refs.Files
            })
    }
}
foreach ($agent in $flipped) {
    if ($agent.After -ne 'user-invocable-only') { continue }
    $refs = Get-SquadReferenceCount -AgentName $agent.Name -Root $SquadSourceRoot
    if ($refs.Count -gt 0) {
        $atRisk.Add([pscustomobject]@{
                Name    = $agent.Name
                Reason  = 'became user-invocable-only (no longer dispatchable)'
                Hits    = $refs.Count
                Files   = $refs.Files
            })
    }
}

$hasDelta = ($added.Count + $removed.Count + $flipped.Count) -gt 0
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
    squadAtRisk    = @($atRisk)
}

#region Reporting
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# hve-core cast delta')
$lines.Add('')
$lines.Add("- Repository: ``$RepoSlug``")
$lines.Add("- From: ``$($before.ResolvedCommit)`` (currently pinned)")
$lines.Add("- To: ``$($after.ResolvedCommit)`` (``$ToRef``)")
$lines.Add("- Verdict: " + $(if ($isBreaking) { '**BREAKING** - the squad references agents this ref no longer exposes' } elseif ($hasDelta) { 'non-breaking cast change' } else { 'no cast change' }))
$lines.Add('')

if ($atRisk.Count -gt 0) {
    $lines.Add('## Squad references that will stop resolving')
    $lines.Add('')
    $lines.Add('| Agent name | Why | References in squad-src |')
    $lines.Add('| --- | --- | --- |')
    foreach ($item in $atRisk) {
        $lines.Add("| ``$($item.Name)`` | $($item.Reason) | $($item.Hits) |")
    }
    $lines.Add('')
    $lines.Add('Each of these must be repointed at a shipped, dispatchable agent, or replaced by a squad-owned thin charter, before the pin moves.')
    $lines.Add('')
    foreach ($item in $atRisk) {
        $lines.Add("### ``$($item.Name)`` - files to update")
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

if (-not $hasDelta) {
    $lines.Add('The deployable cast is identical between the two refs. A mechanical SHA bump is safe.')
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
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "from_commit=$($before.ResolvedCommit)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "to_commit=$($after.ResolvedCommit)"
}

Write-Host ''
Write-Host $markdown
#endregion

return $result
#endregion
