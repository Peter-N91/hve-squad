#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Returns compact Init metadata or prepares confirmed choices for Initialize-Squad.
.DESCRIPTION
    AI cost: none. Reads canonical shipped tables; never initializes squad state.
    Preparation requires all answered choices and explicit confirmation. PayloadPath
    must be a new JSON file outside squad state. Additive catalog-role/pack
    expansion has its own sealed transaction; unsupported connector setup and
    non-additive roster refresh retain their cold procedure.
.PARAMETER Profile
    Optional profile whose resolved Primary agents should be shown in the proposal.
.PARAMETER Pack
    Optional additive packs to include in the proposal, never silently installed.
.PARAMETER Role
    Optional catalog role IDs for a custom proposal.
.PARAMETER ChoicesPath
    Confirmed JSON: confirmed, squadRoot, runId, profile, naming, notify; optional
    packs, roles (custom), excludeRoles, names, modelRouting, models, mode,
    sessionModel, modelOverrides, usage.
.PARAMETER PayloadPath
    New transport file for the canonical legacy initializer payload.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).ProviderPath,
    [Alias('Profile')][string]$ProfileName,
    [string[]]$Pack = @(),
    [string[]]$Role = @(),
    [string]$ChoicesPath,
    [string]$PayloadPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force

try {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    if ($ChoicesPath -or $PayloadPath) {
        if (-not $ChoicesPath -or -not $PayloadPath) { throw 'Preparation requires both ChoicesPath and PayloadPath.' }
        $choices = Get-Content -LiteralPath $ChoicesPath -Raw | ConvertFrom-Json -AsHashtable
        if ($choices -isnot [Collections.IDictionary]) { throw 'Choices must be a JSON object.' }
        $payload = New-SquadInitPayload -Choices $choices -RepoRoot $RepoRoot
        $destination = [IO.Path]::GetFullPath($PayloadPath)
        if ([IO.Path]::GetExtension($destination) -ne '.json' -or (Test-Path -LiteralPath $destination)) {
            throw 'PayloadPath must be a new JSON transport file.'
        }
        $stateRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot '.copilot-tracking' 'squad'))
        $fromState = [IO.Path]::GetRelativePath($stateRoot, $destination)
        if ($fromState -ne '..' -and $fromState -notmatch '^\.\.[\\/]' -and -not [IO.Path]::IsPathRooted($fromState)) {
            throw 'PayloadPath must be outside squad state.'
        }
        $null = Write-SquadTransportJson -Path $destination -SquadRoot $stateRoot -Value $payload
        [ordered]@{ status = 'prepared'; payloadPath = $destination; provenance = $payload.provenance; roles = @($payload.roster | ForEach-Object { $_.Role }); stateWritten = $false } | ConvertTo-Json -Compress
        exit 0
    }

    $data = Get-SquadInitData -RepoRoot $RepoRoot
    $agents = Get-SquadAgentIndex $RepoRoot
    $profiles = @(
        foreach ($row in $data.profiles) {
            [ordered]@{ profile = $row.Profile; roles = @($row['Members (roles)'] -split ',\s*') }
        }
    )
    $members = @()
    $selectedRoles = @()
    if ($ProfileName -and $ProfileName -ne 'custom') {
        $selected = @($profiles | Where-Object { $_.profile -ceq $ProfileName })
        if ($selected.Count -ne 1) { throw "Unknown profile: $ProfileName" }
        $selectedRoles += $selected[0].roles
    }
    $selectedRoles += @($Role | ForEach-Object { $_ -split ',' })
    foreach ($name in @($Pack | ForEach-Object { $_ -split ',' })) {
        $packRows = @($data.packs | Where-Object { $_.Pack -ceq $name })
        if ($packRows.Count -ne 1) { throw "Unknown pack: $name" }
        $selectedRoles += @($packRows[0]['Adds (roles)'] -split ',\s*')
    }
    if ($selectedRoles.Count) {
        $members = @(
            foreach ($role in $selectedRoles | Select-Object -Unique) {
                $row = @($data.cast | Where-Object { $_.Role -ceq $role })
                if ($row.Count -ne 1) { throw "Missing catalog role: $role" }
                $primary = $row[0]['Primary Agent (`name:`)']
                [ordered]@{ role = $role; primary = $primary; available = $agents.ContainsKey($primary) -and $agents[$primary].dispatchable }
            }
        )
    }
    $relativeFiles = @()
    $discoveryScope = 'bounded-local-metadata'
    if (Test-Path -LiteralPath (Join-Path $RepoRoot '.git')) {
        $relativeFiles = @(& git -C $RepoRoot ls-files --cached --others --exclude-standard)
        if ($LASTEXITCODE -ne 0) { throw 'Repository discovery failed; git did not return its local file inventory.' }
        $discoveryScope = 'git-tracked-and-unignored'
    }
    else {
        $queue = [Collections.Generic.Queue[object]]::new()
        $queue.Enqueue(@{ path = $RepoRoot; depth = 0 })
        $excluded = @('.git', '.copilot-tracking', 'node_modules', 'apm_modules', '.venv', 'vendor', 'dist', 'build', 'bin', 'obj')
        while ($queue.Count) {
            $current = $queue.Dequeue()
            foreach ($item in Get-ChildItem -LiteralPath $current.path -Force) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($item.PSIsContainer) {
                    if ($current.depth -lt 2 -and $item.Name -notin $excluded) { $queue.Enqueue(@{ path = $item.FullName; depth = $current.depth + 1 }) }
                }
                else { $relativeFiles += [IO.Path]::GetRelativePath($RepoRoot, $item.FullName) -replace '\\', '/' }
            }
        }
    }
    $extensions = @($relativeFiles | ForEach-Object { [IO.Path]::GetExtension($_).ToLowerInvariant() } | Where-Object { $_ } | Group-Object | Sort-Object Name |
            ForEach-Object { [ordered]@{ extension = $_.Name; files = $_.Count } })
    $manifests = @($relativeFiles | Where-Object { $_ -match '(?i)(?:^|/)(?:package\.json|pyproject\.toml|requirements\.txt|go\.mod|Cargo\.toml|pom\.xml|.*\.csproj|.*\.sln|azure\.ya?ml|Dockerfile|compose\.ya?ml|.*\.bicep|.*\.tf)$' })
    $dependencyNames = @()
    if (Test-Path -LiteralPath (Join-Path $RepoRoot 'package.json') -PathType Leaf) {
        $manifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'package.json') -Raw | ConvertFrom-Json -AsHashtable
        foreach ($key in @('dependencies', 'devDependencies')) {
            if ($manifest.Contains($key)) {
                if ($manifest[$key] -isnot [Collections.IDictionary]) { throw "package.json $key must be an object." }
                $dependencyNames += @($manifest[$key].Keys)
            }
        }
    }
    $top = @(Get-ChildItem -LiteralPath $RepoRoot -Force | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | ForEach-Object Name)
    $kind = if (Test-Path -LiteralPath (Join-Path $RepoRoot '.copilot-tracking' 'squad' 'federation.md')) { 'federation' }
    elseif (Test-Path -LiteralPath (Join-Path $RepoRoot '.copilot-tracking' 'squad' 'team.md')) { 'squad' } else { 'none' }
    [ordered]@{
        status = 'ok'
        skillRoot = Split-Path -Parent $PSScriptRoot
        kind = $kind
        topLevelSignals = $top
        discovery = [ordered]@{ scope = $discoveryScope; extensions = $extensions; manifests = @($manifests | Select-Object -First 30); additionalManifestCount = [Math]::Max(0, $manifests.Count - 30); dependencies = @($dependencyNames | Sort-Object -Unique) }
        profiles = $profiles
        packs = @($data.packs | ForEach-Object { [ordered]@{ pack = $_.Pack; roles = @($_['Adds (roles)'] -split ',\s*') } })
        members = $members
        naming = @('skip', 'aliases', 'custom', 'mixed')
        aliases = $data.aliases
        requiredAnswers = @('structure (unless scoped/inherited)', 'profile and packs', 'naming (unless inherited)', 'notify (unless inherited)')
        confirmationRequired = $true
        stateWritten = $false
    } | ConvertTo-Json -Depth 8 -Compress
}
catch {
    [Console]::Error.WriteLine("Get-SquadInitContext: $($_.Exception.Message)")
    exit 1
}
