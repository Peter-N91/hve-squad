#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Validates one generated hve-squad plugin for a supported Copilot host.
.PARAMETER PluginRoot
    Generated plugin distribution root.
.PARAMETER HostName
    vscode, cli, or app.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PluginRoot,

    [Parameter(Mandatory = $true)]
    [ValidateSet('vscode', 'cli', 'app')]
    [string]$HostName
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $PluginRoot).Path
$manifestPath = Join-Path $root 'plugin.json'
$nestedManifestPath = Join-Path $root '.github/plugin/plugin.json'
$marketplacePath = Join-Path $root '.github/plugin/marketplace.json'
$hveCoreSourcePath = Join-Path $root '.github/plugin/hve-core-source.json'

foreach ($required in @($manifestPath, $nestedManifestPath, $marketplacePath, $hveCoreSourcePath, (Join-Path $root 'hooks.json'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "$HostName contract is missing required file: $required"
    }
}

$manifestText = Get-Content -LiteralPath $manifestPath -Raw
if ($manifestText -cne (Get-Content -LiteralPath $nestedManifestPath -Raw)) {
    throw "$HostName contract requires byte-identical root and nested plugin manifests."
}
$manifest = $manifestText | ConvertFrom-Json -AsHashtable -ErrorAction Stop
if ($manifest['name'] -ne 'hve-squad' -or -not $manifest['version']) {
    throw "$HostName contract requires a named, versioned hve-squad manifest."
}
foreach ($forbidden in @('$schema', 'mcpServers')) {
    if ($manifest.ContainsKey($forbidden)) {
        throw "$HostName contract forbids legacy field '$forbidden'."
    }
}
foreach ($mcpPath in @('.mcp.json', 'mcp.json')) {
    if (Test-Path -LiteralPath (Join-Path $root $mcpPath)) {
        throw "$HostName contract forbids bundled MCP file '$mcpPath'."
    }
}

foreach ($field in @('agents', 'commands', 'rules', 'skills', 'extensions')) {
    if (-not $manifest.ContainsKey($field)) { continue }
    foreach ($path in @($manifest[$field])) {
        if ($path -isnot [string] -or -not (Test-Path -LiteralPath (Join-Path $root $path))) {
            throw "$HostName manifest field '$field' has an invalid or missing path: '$path'."
        }
    }
}
if (@($manifest['agents'] | Where-Object { $_ -like '.github/agents/*' }).Count -eq 0) {
    throw "$HostName contract contains no bundled HVE Core agents."
}
if (@($manifest['agents'] | Where-Object { $_ -like 'agents/squad/*' -or $_ -eq 'agents/squad/' }).Count -eq 0) {
    throw "$HostName contract contains no Squad agents."
}

$marketplace = Get-Content -LiteralPath $marketplacePath -Raw |
    ConvertFrom-Json -AsHashtable -ErrorAction Stop
$plugins = @($marketplace['plugins'])
if ($plugins.Count -ne 1 -or $plugins[0]['name'] -ne 'hve-squad' -or $plugins[0]['source'] -ne '.') {
    throw "$HostName marketplace must expose one relative hve-squad entry."
}
if ($plugins[0]['version'] -ne $manifest['version']) {
    throw "$HostName marketplace and plugin versions differ."
}

$hveCoreSource = Get-Content -LiteralPath $hveCoreSourcePath -Raw |
    ConvertFrom-Json -AsHashtable -ErrorAction Stop
if ($hveCoreSource['repository'] -ne 'microsoft/hve-core' -or
    [string]$hveCoreSource['commit'] -notmatch '^[0-9a-f]{40}$' -or
    @($hveCoreSource['files']).Count -eq 0) {
    throw "$HostName contract has invalid HVE Core provenance."
}

Write-Host "PASS: $HostName accepts hve-squad $($manifest['version']) with bundled HVE Core $(([string]$hveCoreSource['commit']).Substring(0, 7))." -ForegroundColor Green
