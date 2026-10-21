#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Prints a read-only inventory of the selected Squad installation and project state.
.DESCRIPTION
    Discovers source paths, headings, entrypoint metadata, and script parameters without
    executing discovered code, fetching remote content, or writing files. No squad state
    is required. New sources are included without a feature-specific list.
.PARAMETER RepoRoot
    Consumer project or source repository. Defaults to the current directory.
.PARAMETER SkillRoot
    Selected squad skill. Defaults to the skill containing this script, including APM,
    repository-source, and plugin layouts.
.OUTPUTS
    JSON source pointers. Read the cited files before making a behavior claim.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$SkillRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($root in @($RepoRoot, $SkillRoot)) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Coach inventory directory not found: $root"
    }
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SkillRoot = (Resolve-Path -LiteralPath $SkillRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $SkillRoot 'SKILL.md') -PathType Leaf)) {
    throw "Selected Squad skill has no SKILL.md: $SkillRoot"
}

$sources = [Collections.Generic.List[object]]::new()
$comparison = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
$seen = [Collections.Generic.HashSet[string]]::new($comparison)

function Add-CoachSource {
    param([IO.FileInfo]$File, [string]$Kind)

    if (-not $seen.Add($File.FullName)) { return }
    $content = if ($Kind -eq 'asset') { '' } else { Get-Content -LiteralPath $File.FullName -Raw -Encoding utf8 }
    $body = [string]$content
    $metadata = [ordered]@{}
    if ($body -match '(?s)\A---\r?\n(?<meta>.*?)\r?\n---(?:\r?\n|\z)(?<body>.*)\z') {
        $frontmatter = $Matches['meta']
        $body = $Matches['body']
        foreach ($key in @('name', 'description', 'agent', 'argument-hint', 'user-invocable', 'disable-model-invocation')) {
            $match = [regex]::Match($frontmatter, "(?m)^${key}:[ \t]*(?<value>[^\r\n]*)")
            if ($match.Success) { $metadata[$key] = $match.Groups['value'].Value.Trim().Trim('"', "'") }
        }
    }
    $headings = if ($File.Extension -eq '.html') {
        @([regex]::Matches($body, '(?is)<h[1-6]\b[^>]*>(?<title>.*?)</h[1-6]>') | ForEach-Object {
                [Net.WebUtility]::HtmlDecode(($_.Groups['title'].Value -replace '<[^>]*>', '')).Trim()
            })
    }
    else {
        @([regex]::Matches($body, '(?m)^#{1,6}[ \t]+(?<title>[^\r\n]+)') | ForEach-Object {
                $_.Groups['title'].Value.Trim()
            })
    }
    $parameters = @()
    if ($Kind -eq 'script') {
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw "Cannot inspect script '$($File.FullName)': $($parseErrors[0].Message)" }
        if ($ast.ParamBlock) {
            $parameters = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        }
    }
    $sources.Add([pscustomobject][ordered]@{
            kind       = $Kind
            path       = $File.FullName
            metadata   = $metadata
            headings   = @($headings)
            parameters = $parameters
        })
}

$artifactRoot = Split-Path -Parent (Split-Path -Parent $SkillRoot)
$artifactRoots = @($artifactRoot, (Join-Path $RepoRoot '.github')) | Select-Object -Unique
foreach ($root in $artifactRoots) {
    foreach ($kind in @('agents', 'prompts', 'instructions')) {
        $directory = Join-Path $root $kind
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $directory -Recurse -File -Filter 'squad*.md' | Sort-Object FullName) {
            $sourceKind = switch -Regex ($file.Name) {
                '\.agent\.md$' { 'agent'; break }
                '\.prompt\.md$' { 'prompt'; break }
                '\.instructions\.md$' { 'instruction'; break }
                default { $null }
            }
            if ($sourceKind) { Add-CoachSource -File $file -Kind $sourceKind }
        }
    }
}
foreach ($file in Get-ChildItem -LiteralPath $SkillRoot -Recurse -File | Sort-Object FullName) {
    $kind = if ($file.Extension -eq '.md') {
        if ($file.FullName -match '[\\/]invocations[\\/].+[\\/]SKILL\.md$') { 'invocation' } else { 'reference' }
    }
    elseif ($file.Extension -in @('.ps1', '.psm1')) { 'script' }
    else { 'asset' }
    Add-CoachSource -File $file -Kind $kind
}

$packageRoot = $artifactRoot
if ((Split-Path -Leaf $artifactRoot) -eq '.github' -and
    (Split-Path -Leaf (Split-Path -Parent $artifactRoot)) -eq 'squad-src') {
    $packageRoot = Split-Path -Parent (Split-Path -Parent $artifactRoot)
}
$isProductRoot = $false
$apmPath = Join-Path $packageRoot 'apm.yml'
$pluginPath = Join-Path $packageRoot 'plugin.json'
if (Test-Path -LiteralPath $apmPath -PathType Leaf) {
    $isProductRoot = (Get-Content -LiteralPath $apmPath -Raw) -match '(?m)^name:[ \t]*[''"]?hve-squad[''"]?[ \t]*$'
}
elseif (Test-Path -LiteralPath $pluginPath -PathType Leaf) {
    $manifest = Get-Content -LiteralPath $pluginPath -Raw | ConvertFrom-Json -AsHashtable
    $isProductRoot = $manifest['name'] -eq 'hve-squad'
}
$documentation = [Collections.Generic.List[string]]::new()
if ($isProductRoot) {
    $readme = Join-Path $packageRoot 'README.md'
    if (Test-Path -LiteralPath $readme -PathType Leaf) {
        Add-CoachSource -File (Get-Item -LiteralPath $readme) -Kind 'documentation'
        $documentation.Add($readme)
    }
    $docs = Join-Path $packageRoot 'docs'
    if (Test-Path -LiteralPath $docs -PathType Container) {
        $documentation.Add($docs)
        foreach ($file in Get-ChildItem -LiteralPath $docs -Recurse -File | Sort-Object FullName) {
            if ($file.Extension -in @('.md', '.html')) { Add-CoachSource -File $file -Kind 'documentation' }
        }
    }
}

$squadRoot = Join-Path $RepoRoot '.copilot-tracking' 'squad'
$federationPath = Join-Path $squadRoot 'federation.md'
$teamPath = Join-Path $squadRoot 'team.md'
$stateKind = if (Test-Path -LiteralPath $federationPath -PathType Leaf) { 'federation' }
elseif (Test-Path -LiteralPath $teamPath -PathType Leaf) { 'squad' }
else { 'none' }
$stateFiles = @(
    if (Test-Path -LiteralPath $squadRoot -PathType Container) {
        Get-ChildItem -LiteralPath $squadRoot -File | Where-Object Extension -In '.md', '.json' |
            Sort-Object FullName | ForEach-Object FullName
    }
)

[ordered]@{
    schemaVersion      = 1
    repoRoot           = $RepoRoot
    skillRoot          = $SkillRoot
    documentationRoots = @($documentation)
    state              = [ordered]@{ kind = $stateKind; root = $squadRoot; files = $stateFiles }
    entrypoints        = @($sources | Where-Object {
            $_.kind -in @('prompt', 'invocation') -or
            ($_.kind -eq 'agent' -and $_.metadata['user-invocable'] -eq 'true')
        })
    sources            = $sources.ToArray()
} | ConvertTo-Json -Depth 8
