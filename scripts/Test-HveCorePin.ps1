#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Verifies the HVE Core files bundled inside an installed hve-squad plugin.
.DESCRIPTION
    The generated plugin records its microsoft/hve-core commit and every copied
    source/target path in .github/plugin/hve-core-source.json. This script
    fetches the recursive git tree for that commit and recomputes each installed
    file's git blob SHA-1. A successful result proves that the installed plugin
    contains the exact HVE Core bytes declared by its provenance record.
.PARAMETER PluginRoot
    Installed hve-squad plugin directory.
.PARAMETER GitHubToken
    Optional GitHub token used when unauthenticated API limits are insufficient.
.EXAMPLE
    ./scripts/Test-HveCorePin.ps1
.EXAMPLE
    ./scripts/Test-HveCorePin.ps1 -PluginRoot ~/.copilot/installed-plugins/hve-squad/hve-squad
.NOTES
    Exit code 0 means verified; exit code 1 means missing or mismatched content.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PluginRoot = (Join-Path $HOME '.copilot/installed-plugins/hve-squad/hve-squad'),

    [Parameter(Mandatory = $false)]
    [string]$GitHubToken
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PluginRoot -PathType Container)) {
    throw "Plugin root not found: $PluginRoot"
}
$root = (Resolve-Path -LiteralPath $PluginRoot).Path
$sourcePath = Join-Path $root '.github/plugin/hve-core-source.json'
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Bundled HVE Core provenance not found: $sourcePath"
}

$source = Get-Content -LiteralPath $sourcePath -Raw |
    ConvertFrom-Json -AsHashtable -ErrorAction Stop
if ($source['repository'] -ne 'microsoft/hve-core') {
    throw "Unexpected HVE Core repository in provenance: '$($source['repository'])'."
}
$commit = [string]$source['commit']
if ($commit -notmatch '^[0-9a-f]{40}$') {
    throw "Invalid HVE Core commit in provenance: '$commit'."
}
$files = @($source['files'])
if ($files.Count -eq 0) {
    throw 'Bundled HVE Core provenance declares no copied files.'
}

$headers = @{ 'User-Agent' = 'hve-squad-pin-check' }
if ($GitHubToken) { $headers['Authorization'] = "Bearer $GitHubToken" }

Write-Host "repo        : microsoft/hve-core"
Write-Host "pinned sha  : $commit"
Write-Host "plugin root : $root"

$tree = Invoke-RestMethod `
    -Uri "https://api.github.com/repos/microsoft/hve-core/git/trees/$commit`?recursive=1" `
    -Headers $headers
if ($tree.truncated) {
    throw 'GitHub truncated the HVE Core tree response; exact verification cannot continue.'
}

$expected = @{}
foreach ($node in $tree.tree) {
    if ($node.type -eq 'blob') { $expected[$node.path] = $node.sha }
}

$sha1 = [System.Security.Cryptography.SHA1]::Create()
function Get-GitBlobSha {
    param([byte[]]$Content)
    $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($Content.Length)`0")
    $buffer = [byte[]]::new($header.Length + $Content.Length)
    [Array]::Copy($header, 0, $buffer, 0, $header.Length)
    [Array]::Copy($Content, 0, $buffer, $header.Length, $Content.Length)
    [System.Convert]::ToHexString($sha1.ComputeHash($buffer)).ToLowerInvariant()
}

$verified = 0
$problems = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $files) {
    $sourceRelative = [string]$entry['source']
    $targetRelative = [string]$entry['target']
    if (-not $sourceRelative -or -not $targetRelative) {
        $problems.Add('Provenance contains an entry without source and target paths.') | Out-Null
        continue
    }
    if (-not $expected.ContainsKey($sourceRelative)) {
        $problems.Add("Pinned commit has no file '$sourceRelative'.") | Out-Null
        continue
    }

    $targetPath = [IO.Path]::GetFullPath((Join-Path $root $targetRelative))
    $relativeToRoot = [IO.Path]::GetRelativePath($root, $targetPath)
    if ($relativeToRoot -eq '..' -or $relativeToRoot -match '^\.\.[\\/]' -or [IO.Path]::IsPathRooted($relativeToRoot)) {
        $problems.Add("Provenance target leaves the plugin root: '$targetRelative'.") | Out-Null
        continue
    }
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        $problems.Add("Bundled file is missing: '$targetRelative'.") | Out-Null
        continue
    }

    $bytes = [IO.File]::ReadAllBytes($targetPath)
    if ((Get-GitBlobSha $bytes) -eq $expected[$sourceRelative]) {
        $verified++
        continue
    }
    $normalized = [System.Text.Encoding]::UTF8.GetBytes(
        ([System.Text.Encoding]::UTF8.GetString($bytes) -replace "`r`n", "`n")
    )
    if ((Get-GitBlobSha $normalized) -eq $expected[$sourceRelative]) {
        $verified++
        continue
    }
    $problems.Add("Bundled content differs: '$targetRelative'.") | Out-Null
}

Write-Host ''
Write-Host "verified    : $verified / $($files.Count)"
Write-Host "problems    : $($problems.Count)"
foreach ($problem in ($problems | Select-Object -First 30)) {
    Write-Warning $problem
}

if ($problems.Count -eq 0) {
    Write-Host ''
    Write-Host "OK: bundled HVE Core content matches microsoft/hve-core@$commit." -ForegroundColor Green
    exit 0
}

Write-Host ''
Write-Error "DRIFT: bundled HVE Core content does not match microsoft/hve-core@$commit."
exit 1
