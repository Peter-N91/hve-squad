# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

function Get-DeclaredPluginAgentPath {
    param(
        [Parameter(Mandatory)][string]$PluginRoot,
        [Parameter(Mandatory)][string]$ManifestPath,
        [string]$Context = 'Plugin'
    )

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw |
        ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ($manifest -isnot [Collections.IDictionary]) {
        throw "Expected an object in $ManifestPath."
    }

    $agentPaths = @('agents')
    if ($manifest.ContainsKey('agents')) {
        $agentPaths = $manifest.agents
    }
    elseif (-not (Test-Path -LiteralPath (Join-Path $PluginRoot 'agents') -PathType Container)) {
        return
    }
    if ($agentPaths -is [string]) { $agentPaths = @($agentPaths) }
    if ($agentPaths -isnot [array]) { throw "Expected agent paths in $ManifestPath." }

    foreach ($path in $agentPaths) {
        if ($path -isnot [string] -or [string]::IsNullOrWhiteSpace($path) -or [IO.Path]::IsPathRooted($path)) {
            throw "Invalid agent path in $ManifestPath."
        }
        $fullPath = [IO.Path]::GetFullPath((Join-Path $PluginRoot $path))
        $relative = [IO.Path]::GetRelativePath($PluginRoot, $fullPath)
        if ($relative -eq '..' -or $relative -match '^\.\.[\\/]' -or [IO.Path]::IsPathRooted($relative)) {
            throw "Agent path leaves $Context plugin: $path"
        }
        $cursor = $fullPath
        while ($cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
            if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Linked $Context plugin path refused: $cursor"
            }
            if ($cursor -eq $PluginRoot) { break }
            $cursor = Split-Path -Parent $cursor
        }
        if (-not (Test-Path -LiteralPath $fullPath)) {
            throw "$Context plugin agent path not found: $fullPath"
        }
        $fullPath
    }
}

function Get-SquadAgentFile {
    param([string]$RepoRoot, [Parameter(Mandatory)][string]$ScriptRoot)

    $artifactRoot = [IO.Path]::GetFullPath((Join-Path $ScriptRoot '../../..'))
    $paths = @()
    if ($RepoRoot) {
        $paths += @('.github/agents', '.agents/agents', '.claude/agents') |
            ForEach-Object { Join-Path $RepoRoot $_ }
    }
    $paths += @(
        (Join-Path $artifactRoot 'agents'),
        (Join-Path (Split-Path -Parent $artifactRoot) 'agents'),
        (Join-Path $ScriptRoot '../../agents'),
        (Join-Path $ScriptRoot '../agents')
    )

    # The current distribution bundles HVE Core and Squad in one plugin. Resolve
    # every manifest-declared agent from that same root before consulting legacy
    # host inventory or sibling layouts.
    $cursor = [IO.Path]::GetFullPath($ScriptRoot)
    while ($cursor) {
        $manifestPath = Join-Path $cursor 'plugin.json'
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw |
                ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ($manifest -is [Collections.IDictionary] -and $manifest['name'] -eq 'hve-squad') {
                $paths += @(Get-DeclaredPluginAgentPath -PluginRoot $cursor -ManifestPath $manifestPath -Context 'bundled')
                break
            }
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }

    # An explicit host inventory replaces sibling guesses, including an empty inventory.
    if (Test-Path Env:SQUAD_ACTIVE_PLUGIN_ROOTS) {
        $roots = ConvertFrom-Json -InputObject $env:SQUAD_ACTIVE_PLUGIN_ROOTS -NoEnumerate -ErrorAction Stop
        if ($roots -isnot [array]) { throw 'SQUAD_ACTIVE_PLUGIN_ROOTS must be a JSON array of active plugin roots.' }
        foreach ($root in $roots) {
            if ($root -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($root)) {
                throw 'Each SQUAD_ACTIVE_PLUGIN_ROOTS entry must be an absolute plugin directory.'
            }
            $root = [IO.Path]::GetFullPath($root)
            $manifestPath = Join-Path $root 'plugin.json'
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                throw "Active plugin manifest not found: $manifestPath"
            }
            $paths += @(Get-DeclaredPluginAgentPath -PluginRoot $root -ManifestPath $manifestPath -Context 'active')
        }

    }
    else {
        $parent = Split-Path -Parent $artifactRoot
        $paths += @(
            (Join-Path $parent 'hve-squad-hve-core/.github/agents'),
            (Join-Path $parent 'hve-core/.github/agents'),
            (Join-Path $parent 'hve-core/agents')
        )
    }

    $comparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
    $seen = [Collections.Generic.HashSet[string]]::new($comparer)
    foreach ($path in $paths | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $files = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Item -LiteralPath $path }
        else { Get-ChildItem -LiteralPath $path -Recurse -File -Filter '*.md' | Sort-Object FullName }
        foreach ($file in $files) {
            if ($file.Extension -ine '.md' -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
            if ($seen.Add($file.FullName)) { $file }
        }
    }

}

function Get-SquadSkillFile {
        param([string]$RepoRoot, [Parameter(Mandatory)][string]$ScriptRoot)

        $artifactRoot = [IO.Path]::GetFullPath((Join-Path $ScriptRoot '../../..'))
        $paths = @()
        if ($RepoRoot) {
            $paths += @('.agents/skills', '.github/skills', '.copilot/skills') |
                ForEach-Object { Join-Path $RepoRoot $_ }
        }
        $copilotHome = if ($env:COPILOT_HOME) {
            [IO.Path]::GetFullPath($env:COPILOT_HOME)
        }
        else {
            Join-Path ([Environment]::GetFolderPath('UserProfile')) '.copilot'
        }
        $paths += @(
            (Join-Path $copilotHome 'skills'),
            (Join-Path $artifactRoot 'skills'),
            (Join-Path (Split-Path -Parent $artifactRoot) 'skills'),
            (Join-Path $ScriptRoot '..')
        )

        if (Test-Path Env:SQUAD_ACTIVE_PLUGIN_ROOTS) {
            $roots = ConvertFrom-Json -InputObject $env:SQUAD_ACTIVE_PLUGIN_ROOTS -NoEnumerate -ErrorAction Stop
            if ($roots -isnot [array]) { throw 'SQUAD_ACTIVE_PLUGIN_ROOTS must be a JSON array of active plugin roots.' }
            foreach ($root in $roots) {
                if ($root -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($root)) {
                    throw 'Each SQUAD_ACTIVE_PLUGIN_ROOTS entry must be an absolute plugin directory.'
                }
                $root = [IO.Path]::GetFullPath($root)
                $manifestPath = Join-Path $root 'plugin.json'
                if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                    throw "Active plugin manifest not found: $manifestPath"
                }
                $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                if ($manifest -isnot [Collections.IDictionary]) { throw "Expected an object in $manifestPath." }
                $skillPaths = @('skills')
                if ($manifest.ContainsKey('skills')) { $skillPaths = $manifest.skills }
                elseif (-not (Test-Path -LiteralPath (Join-Path $root 'skills') -PathType Container)) { continue }
                if ($skillPaths -is [string]) { $skillPaths = @($skillPaths) }
                if ($skillPaths -isnot [array]) { throw "Expected skill paths in $manifestPath." }
                foreach ($path in $skillPaths) {
                    if ($path -isnot [string] -or [string]::IsNullOrWhiteSpace($path) -or [IO.Path]::IsPathRooted($path)) {
                        throw "Invalid skill path in $manifestPath."
                    }
                    $fullPath = [IO.Path]::GetFullPath((Join-Path $root $path))
                    $relative = [IO.Path]::GetRelativePath($root, $fullPath)
                    if ($relative -eq '..' -or $relative -match '^\.\.[\\/]' -or [IO.Path]::IsPathRooted($relative)) {
                        throw "Skill path leaves active plugin: $path"
                    }
                    $cursor = $fullPath
                    while ($cursor) {
                        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
                        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                            throw "Linked active plugin path refused: $cursor"
                        }
                        if ($cursor -eq $root) { break }
                        $cursor = Split-Path -Parent $cursor
                    }
                    if (-not (Test-Path -LiteralPath $fullPath)) { throw "Active plugin skill path not found: $fullPath" }
                    $paths += $fullPath
                }
            }
        }
        else {
            $parent = Split-Path -Parent $artifactRoot
            $paths += @(
                (Join-Path $parent 'hve-squad-hve-core/.github/skills'),
                (Join-Path $parent 'hve-core/.github/skills'),
                (Join-Path $parent 'hve-core/skills')
            )
        }

        $comparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
        $seen = [Collections.Generic.HashSet[string]]::new($comparer)
        foreach ($path in $paths | Select-Object -Unique) {
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $files = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Item -LiteralPath $path }
            else { Get-ChildItem -LiteralPath $path -Recurse -File -Filter 'SKILL.md' | Sort-Object FullName }
            foreach ($file in $files) {
                if ($file.Name -ine 'SKILL.md' -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
                if ($seen.Add($file.FullName)) { $file }
            }
        }
    }