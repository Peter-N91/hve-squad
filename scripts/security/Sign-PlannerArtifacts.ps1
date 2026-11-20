#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Writes a local SHA-256 integrity manifest for an RAI planning session.
.DESCRIPTION
    Inventories files under .copilot-tracking\rai-plans\ProjectSlug and writes
    artifact-manifest.json there. This is an integrity manifest, not a signature
    or proof of cryptographic authorship. No network, credentials, signing
    service, external tools or git process are used.

    Rejects reparse points (including symbolic links and junctions), missing or
    unreadable content, empty files and sessions without artifacts. Includes
    hidden files; excludes the output manifest and prior .sig/.bundle files.
    Inventory paths use forward slashes and ordinal sorting.
.PARAMETER ProjectSlug
    Lowercase ASCII letters or digits separated by single hyphens; not a path
    or a Windows reserved device name.
.PARAMETER RepoRoot
    Local repository root. Defaults to two directories above this script,
    independently of the caller's working directory.
.EXAMPLE
    npm run rai:sign -- -ProjectSlug contoso-ai
.NOTES
    Exit code 0 means the manifest was written; any failure exits with code 1.
    Run against a quiescent local session, not a concurrently modified tree.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectSlug,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..' -AdditionalChildPath '..')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

#region Functions

function Assert-LocalArtifactPath {
    <#
    .SYNOPSIS
        Validates an existing filesystem path without traversing reparse points.
    .PARAMETER Path
        Local path whose ancestors and final item must not be reparse points.
    .OUTPUTS
        System.IO.FileSystemInfo for the validated item.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileSystemInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $FullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if ($FullPath.StartsWith('\\') -or $FullPath.StartsWith('//')) {
        throw "Network and device paths are not supported: $Path"
    }
    if ($IsWindows -and [IO.DriveInfo]::new([IO.Path]::GetPathRoot($FullPath)).DriveType -eq [IO.DriveType]::Network) {
        throw "Network drives are not supported: $FullPath"
    }

    # Check ancestors top-down so even enumeration never crosses a link.
    $Ancestors = [Collections.Generic.Stack[string]]::new()
    $Current = $FullPath
    while ($Current) {
        $Ancestors.Push($Current)
        $Current = [IO.Path]::GetDirectoryName($Current)
    }
    $Item = $null
    while ($Ancestors.Count -gt 0) {
        $Item = Get-Item -LiteralPath $Ancestors.Pop() -Force -ErrorAction Stop
        if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not supported: $($Item.FullName)"
        }
    }
    return $Item
}

function New-PlannerArtifactManifest {
    <#
    .SYNOPSIS
        Hashes local session content and writes its integrity-only manifest.
    .PARAMETER ProjectSlug
        Single RAI session slug, never an arbitrary path.
    .PARAMETER RepoRoot
        Local repository directory containing the session.
    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary describing the manifest.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Explicit local-only CLI operation with a single fixed output path.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectSlug,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot
    )

    if ($ProjectSlug -cnotmatch '\A[a-z0-9]+(?:-[a-z0-9]+)*\z' -or
        $ProjectSlug -match '\A(?:con|prn|aux|nul|com[0-9]|lpt[0-9])\z') {
        throw "Invalid ProjectSlug '$ProjectSlug': use lowercase letters/digits separated by single hyphens, not a path or reserved device name."
    }

    $Root = Assert-LocalArtifactPath -Path $RepoRoot
    if (-not $Root.PSIsContainer) { throw "Repository root is not a directory: $RepoRoot" }
    $SessionPath = Join-Path $Root.FullName '.copilot-tracking' -AdditionalChildPath 'rai-plans', $ProjectSlug
    $Session = Assert-LocalArtifactPath -Path $SessionPath
    if (-not $Session.PSIsContainer) { throw "Artifact session is not a directory: $SessionPath" }
    $ManifestPath = Join-Path $Session.FullName 'artifact-manifest.json'
    $PathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $Files = [Collections.Generic.SortedDictionary[string, string]]::new([StringComparer]::Ordinal)
    $Directories = [Collections.Generic.Queue[string]]::new()
    $Directories.Enqueue($Session.FullName)

    while ($Directories.Count -gt 0) {
        $Directory = Assert-LocalArtifactPath -Path $Directories.Dequeue()
        foreach ($Entry in (Get-ChildItem -LiteralPath $Directory.FullName -Force -ErrorAction Stop)) {
            if (($Entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse points are not supported: $($Entry.FullName)"
            }
            $RelativePath = [IO.Path]::GetRelativePath($Session.FullName, $Entry.FullName)
            if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '^\.\.([\\/]|$)') {
                throw "Artifact path escapes its session: $($Entry.FullName)"
            }
            if ([string]::Equals($RelativePath, 'artifact-manifest.json', $PathComparison)) {
                if ($Entry.PSIsContainer) { throw "Manifest output is a directory: $ManifestPath" }
                continue
            }
            if ($Entry.PSIsContainer) {
                $Directories.Enqueue($Entry.FullName)
            }
            elseif ($Entry.Extension -notin '.sig', '.bundle') {
                $Files.Add(($RelativePath -replace '\\', '/'), $Entry.FullName)
            }
        }
    }
    if ($Files.Count -eq 0) { throw "No artifacts found in session: $SessionPath" }

    $Artifacts = [Collections.Generic.List[object]]::new()
    foreach ($File in $Files.GetEnumerator()) {
        $null = Assert-LocalArtifactPath -Path $File.Value
        $Stream = [IO.File]::Open($File.Value, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            if ($Stream.Length -eq 0) { throw "Artifact file is empty: $($File.Key)" }
            $Artifacts.Add([ordered]@{
                    path = $File.Key
                    sha256 = (Get-FileHash -InputStream $Stream -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                    sizeBytes = $Stream.Length
                })
        }
        finally { $Stream.Dispose() }
    }

    $Manifest = [ordered]@{
        version = '1.0'
        purpose = 'integrity-only'
        projectSlug = $ProjectSlug
        sessionPath = ".copilot-tracking/rai-plans/$ProjectSlug"
        generatedAt = [DateTime]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        algorithm = 'SHA256'
        fileCount = $Artifacts.Count
        artifacts = $Artifacts.ToArray()
    }
    $null = Assert-LocalArtifactPath -Path $Session.FullName
    if (Test-Path -LiteralPath $ManifestPath) {
        $OutputItem = Assert-LocalArtifactPath -Path $ManifestPath
        if ($OutputItem.PSIsContainer) { throw "Manifest output is a directory: $ManifestPath" }
    }
    $Manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ManifestPath -Encoding utf8NoBOM -ErrorAction Stop
    return $Manifest
}

#endregion Functions

#region Main Execution

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $Manifest = New-PlannerArtifactManifest -ProjectSlug $ProjectSlug -RepoRoot $RepoRoot
        Write-Host "Integrity manifest written: $($Manifest.sessionPath)/artifact-manifest.json ($($Manifest.fileCount) files)." -ForegroundColor Green
        Write-Host 'Local SHA-256 integrity only; not a signature or proof of cryptographic authorship.' -ForegroundColor Cyan
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Sign-PlannerArtifacts failed: $($_.Exception.Message)"
        exit 1
    }
}

#endregion Main Execution
