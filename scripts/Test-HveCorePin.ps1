#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Verifies that an installed Copilot CLI plugin tree really is the commit its
    marketplace entry pins.
.DESCRIPTION
    marketplace.json pins 'hve-squad-hve-core' to an exact microsoft/hve-core
    commit via source.sha. Nothing in the CLI proves after the fact that the tree
    on disk came from that commit:

      * config.json records 'source_sha' as a 64-hex content digest of the
        downloaded payload, not the git commit SHA-1, so it cannot be compared
        against source.sha by eye.
      * config.json records 'version' from the *upstream* plugin.json (hve-core
        3.2.2), not from the marketplace entry, so bumping the marketplace
        version alongside a new sha does not make 'copilot plugin update' report
        an upgrade. It answers 'already at latest' and may leave the previously
        pinned tree in place.

    This script closes that gap by comparing content, not metadata. It reads the
    pin from marketplace.json, fetches the full recursive git tree at that
    commit, and recomputes the git blob SHA-1 of every installed file. A tree
    that matches on every path and every blob can only have come from the pinned
    commit.

    Files are compared byte-for-byte first, then retried with CRLF collapsed to
    LF, because a Windows checkout normalises line endings while git blob hashes
    are always computed over LF content.
.PARAMETER PluginRoot
    Directory holding the installed plugin tree to verify.
.PARAMETER MarketplaceUrl
    Raw URL of the marketplace.json carrying the pin. Defaults to main of the
    published plugin repository, so the check runs against what users install.
.PARAMETER PluginName
    Marketplace entry whose source.sha is verified.
.PARAMETER GitHubToken
    Optional PAT. Supply it when the unauthenticated GitHub API rate limit bites.
.EXAMPLE
    ./scripts/Test-HveCorePin.ps1
.EXAMPLE
    ./scripts/Test-HveCorePin.ps1 -PluginRoot ~/.copilot/installed-plugins/hve-squad-plugin/hve-squad-hve-core
.NOTES
    Exit code 0 means verified, 1 means drift. Safe to wire into CI after a
    release bumps the hve-core pin.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PluginRoot = (Join-Path $HOME '.copilot/installed-plugins/hve-squad-plugin/hve-squad-hve-core'),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$MarketplaceUrl = 'https://raw.githubusercontent.com/Peter-N91/hve-squad-plugin/main/.github/plugin/marketplace.json',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PluginName = 'hve-squad-hve-core',

    [Parameter(Mandatory = $false)]
    [string]$GitHubToken
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PluginRoot)) {
    throw "Plugin root not found: $PluginRoot"
}
$root = (Resolve-Path -LiteralPath $PluginRoot).Path

$headers = @{ 'User-Agent' = 'hve-squad-pin-check' }
if ($GitHubToken) { $headers['Authorization'] = "Bearer $GitHubToken" }

$marketplace = Invoke-RestMethod -Uri $MarketplaceUrl -Headers $headers
$entry = $marketplace.plugins | Where-Object { $_.name -eq $PluginName }
if (-not $entry) { throw "No plugin named '$PluginName' in $MarketplaceUrl" }

$pinnedSha = $entry.source.sha
if (-not $pinnedSha) {
    throw "'$PluginName' has no source.sha - it tracks '$($entry.source.ref)' and cannot be verified by commit."
}
$repo = $entry.source.repo

Write-Host "repo        : $repo"
Write-Host "pinned sha  : $pinnedSha"
Write-Host "plugin root : $root"

$tree = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/git/trees/$pinnedSha`?recursive=1" -Headers $headers
if ($tree.truncated) {
    throw 'GitHub truncated the tree response; the repository is too large for a single-request verification.'
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
    return [System.Convert]::ToHexString($sha1.ComputeHash($buffer)).ToLowerInvariant()
}

$verified = 0
$mismatched = [System.Collections.Generic.List[string]]::new()
$untracked = [System.Collections.Generic.List[string]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new()

foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
    $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
    if ($relative -like '.git/*') { continue }

    if (-not $expected.ContainsKey($relative)) {
        $untracked.Add($relative)
        continue
    }
    [void]$seen.Add($relative)

    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ((Get-GitBlobSha $bytes) -eq $expected[$relative]) { $verified++; continue }

    $normalised = [System.Text.Encoding]::UTF8.GetBytes(
        ([System.Text.Encoding]::UTF8.GetString($bytes) -replace "`r`n", "`n"))
    if ((Get-GitBlobSha $normalised) -eq $expected[$relative]) { $verified++; continue }

    $mismatched.Add($relative)
}

$absent = $expected.Keys | Where-Object { -not $seen.Contains($_) }

Write-Host ''
Write-Host "verified    : $verified / $($expected.Count)"
Write-Host "mismatched  : $($mismatched.Count)"
Write-Host "not in pin  : $($untracked.Count)"
Write-Host "missing     : $(@($absent).Count)"

foreach ($path in ($mismatched | Select-Object -First 20)) { Write-Warning "content differs: $path" }
foreach ($path in ($untracked | Select-Object -First 20)) { Write-Warning "extra file: $path" }
foreach ($path in (@($absent) | Select-Object -First 20)) { Write-Warning "absent locally: $path" }

if ($mismatched.Count -eq 0 -and $untracked.Count -eq 0 -and @($absent).Count -eq 0) {
    Write-Host ''
    Write-Host "OK: installed tree matches $repo@$pinnedSha exactly." -ForegroundColor Green
    exit 0
}

Write-Host ''
Write-Error "DRIFT: installed tree does not match $repo@$pinnedSha."
exit 1
