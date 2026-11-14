#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Materializes the HVE Squad Studio canvas extension for APM, repository, user, or session scope.
.DESCRIPTION
    AI cost: none. Copies the shipped HVE Squad Studio extension (`extensions/hve-squad-studio`)
    into `.github/extensions/hve-squad-studio` (repository), `$COPILOT_HOME/extensions/hve-squad-studio`
    (user), or a session state extensions folder (session) while rejecting symlinks/reparse points.
    Plugin installations load HVE Squad Studio automatically via `plugin.json` without running this script.
.PARAMETER Scope
    Target extension discovery scope: `repository` (default), `user`, or `session`.
.PARAMETER RepoRoot
    Consumer repository root when `-Scope repository` is selected.
.PARAMETER CopilotHome
    Overrides `$env:COPILOT_HOME` (defaults to `~/.copilot`) when `-Scope user` is selected.
.PARAMETER SessionStatePath
    Session state directory when `-Scope session` is selected.
.PARAMETER Check
    Verifies whether the target directory matches the shipped HVE Squad Studio files without writing.
#>
[CmdletBinding()]
param(
    [ValidateSet('repository', 'user', 'session')]
    [string]$Scope = 'repository',

    [string]$RepoRoot = (Get-Location).ProviderPath,

    [string]$CopilotHome = $(if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.copilot' }),

    [string]$SessionStatePath = '',

    [switch]$Check
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-NoReparsePoint {
    param([Parameter(Mandatory)][string]$Path)
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing symlink or reparse point path: $cursor"
        }
        $parent = Split-Path -Path $cursor -Parent
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}

$sourceDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../extensions/hve-squad-studio'))
if (-not (Test-Path -LiteralPath (Join-Path $sourceDir 'extension.mjs') -PathType Leaf)) {
    throw "Shipped HVE Squad Studio source not found at '$sourceDir'."
}
Assert-NoReparsePoint -Path $sourceDir

$targetRoot = switch ($Scope) {
    'repository' {
        if ([string]::IsNullOrWhiteSpace($RepoRoot)) { throw 'RepoRoot is required for repository scope.' }
        Join-Path ([IO.Path]::GetFullPath($RepoRoot)) '.github/extensions/hve-squad-studio'
    }
    'user' {
        if ([string]::IsNullOrWhiteSpace($CopilotHome)) { throw 'CopilotHome is required for user scope.' }
        Join-Path ([IO.Path]::GetFullPath($CopilotHome)) 'extensions/hve-squad-studio'
    }
    'session' {
        if ([string]::IsNullOrWhiteSpace($SessionStatePath)) { throw 'SessionStatePath is required for session scope.' }
        Join-Path ([IO.Path]::GetFullPath($SessionStatePath)) 'extensions/hve-squad-studio'
    }
}
Assert-NoReparsePoint -Path $targetRoot

$sourceFiles = @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File -Force | Sort-Object FullName)
foreach ($file in $sourceFiles) {
    Assert-NoReparsePoint -Path $file.FullName
}

if ($Check) {
    $drifted = [Collections.Generic.List[string]]::new()
    foreach ($file in $sourceFiles) {
        $rel = [IO.Path]::GetRelativePath($sourceDir, $file.FullName).Replace('\', '/')
        $destFile = Join-Path $targetRoot $rel
        if (-not (Test-Path -LiteralPath $destFile -PathType Leaf)) {
            $drifted.Add($rel)
            continue
        }
        if ((Get-FileHash -LiteralPath $destFile -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) {
            $drifted.Add($rel)
        }
    }
    $receipt = [ordered]@{
        status = if ($drifted.Count -eq 0) { 'up-to-date' } else { 'drift-detected' }
        scope = $Scope
        source = $sourceDir
        destination = $targetRoot
        missingOrChanged = @($drifted)
    }
    Write-Output ($receipt | ConvertTo-Json -Depth 5)
    if ($drifted.Count -gt 0) { exit 2 }
    exit 0
}

$written = [Collections.Generic.List[string]]::new()
foreach ($file in $sourceFiles) {
    $rel = [IO.Path]::GetRelativePath($sourceDir, $file.FullName).Replace('\', '/')
    $destFile = Join-Path $targetRoot $rel
    $destParent = Split-Path -Path $destFile -Parent
    if (-not (Test-Path -LiteralPath $destParent -PathType Container)) {
        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }
    Assert-NoReparsePoint -Path $destParent
    [IO.File]::WriteAllBytes($destFile, [IO.File]::ReadAllBytes($file.FullName))
    $written.Add($rel)
}

$receipt = [ordered]@{
    status = 'installed'
    scope = $Scope
    source = $sourceDir
    destination = $targetRoot
    filesWritten = @($written)
    nextStep = 'Reload extensions in GitHub Copilot (or open a new session) and select HVE Squad Studio from Canvases.'
}
Write-Output ($receipt | ConvertTo-Json -Depth 5)