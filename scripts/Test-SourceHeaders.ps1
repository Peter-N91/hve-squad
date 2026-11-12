#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Audits copyright headers in tracked first-party release sources.
.DESCRIPTION
    Classifies tracked source files and explicit metadata, data, fixture,
    generated and third-party exclusions. Checks exact notices at the language-aware header
    position without modifying files or inspecting installed/generated copies.
.PARAMETER RepoRoot
    Repository checkout to audit.
.PARAMETER Detailed
    Prints each excluded path and its reason.
.EXAMPLE
    ./scripts/Test-SourceHeaders.ps1 -Detailed
.NOTES
    No dependencies, network requests or generated output.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Detailed
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-SourceHeaderOffset {
    [CmdletBinding()]
    [OutputType([int])]
    param([string]$Content, [string]$Extension)

    $offset = 0
    if ($Extension -in '.md', '.njk') {
        $frontmatter = [regex]::Match($Content, '\A---\r?\n.*?\r?\n---(?:\r?\n|$)', 'Singleline')
        if ($frontmatter.Success) { $offset = $frontmatter.Length }
    }
    if ($Extension -in '.html', '.svg', '.njk') {
        $declaration = [regex]::Match($Content.Substring($offset), '\A(?:<\?xml[^?]*\?>\r?\n)?(?:<!doctype[^>]*>\r?\n)?', 'IgnoreCase')
        $offset += $declaration.Length
    }
    if ($Extension -in '.ps1', '.psm1', '.psd1', '.py', '.sh', '.js', '.mjs') {
        $shebang = [regex]::Match($Content, '\A#![^\r\n]*(?:\r?\n|$)')
        if ($shebang.Success) { $offset = $shebang.Length }
        if ($Extension -eq '.py') {
            $encoding = [regex]::Match($Content.Substring($offset), '\A#[^\r\n]*coding[:=][ \t]*[-\w.]+[^\r\n]*(?:\r?\n|$)')
            if ($encoding.Success) { $offset += $encoding.Length }
        }
        if ($Extension -eq '.ps1' -and $offset -eq 0) {
            $requires = [regex]::Match($Content, '\A#Requires -Modules Pester(?:\r?\n|$)', 'IgnoreCase')
            if ($requires.Success) { $offset = $requires.Length }
        }
    }
    return $offset
}

function Get-SourceHeaderInventory {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([string]$Root)

    $paths = @(& git -C $Root ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
    $extensions = '.ps1', '.psm1', '.psd1', '.py', '.sh', '.js', '.mjs', '.css', '.html', '.svg', '.njk', '.md', '.yml', '.yaml'
    foreach ($path in ($paths | Sort-Object -Unique)) {
        if ($path -notmatch '^(scripts|tests|squad-src|site|docs|benchmarks)/|^\.github/(workflows|ISSUE_TEMPLATE)/|^\.github/(pull_request_template\.md|dependabot\.yml|CODEOWNERS)$|^\.changes/unreleased/20261111-microsoft-release-readiness\.md$|^(eleventy\.config\.js|PSScriptAnalyzerSettings\.psd1|apm\.yml|\.gitignore|\.gitattributes)$') { continue }
        $extension = [IO.Path]::GetExtension($path).ToLowerInvariant()
        $reason = if ($path -in '.gitignore', '.gitattributes', '.github/CODEOWNERS') {
            'Git metadata; not first-party source code'
        }
        elseif ($path -match '(^|/)fixtures/|^tests/tier2/live-benchmark/tasks/') {
            'Fixture or benchmark task payload; preserve exact bytes'
        }
        elseif ($path -match '^squad-src/\.github/skills/sql-migration-advisor/') {
            'Adapted external SQL skill; preserve upstream rights and bytes'
        }
        elseif ($path -match '^docs/assets/fonts/') {
            'Third-party font asset or OFL notice'
        }
        elseif ($path -eq 'site/assets/vendor/mermaid-THIRD-PARTY-NOTICES.txt') {
            'Third-party license/notice text; preserve upstream rights'
        }
        elseif ($path -eq 'benchmarks/efficiency/badge.svg') {
            'Generated benchmark badge, not authored SVG'
        }
        elseif ($path -match '^benchmarks/') {
            'Benchmark evidence/guidance outside the authored-SVG source scope'
        }
        elseif ($path -eq 'docs/squad-governance-report-2026-08-04.html' -or $path -match '^tests/tier1/benchmark/.*\.md$') {
            'Generated benchmark/report evidence, not authored source'
        }
        elseif ($path -match '(^|/)package-lock\.json$') {
            'Dependency lock file'
        }
        elseif ($path -match '(^|/)requirements\.txt$') {
            'Dependency manifest outside the approved manifest-edit scope'
        }
        elseif ($extension -eq '.json') {
            'Strict JSON configuration or data; comments are invalid'
        }
        elseif ($extension -in '.mp4', '.woff2') {
            'Binary media asset'
        }
        elseif ($extension -notin $extensions) {
            'Plain text or sentinel without a source comment syntax'
        }
        else { $null }
        [pscustomobject]@{ Path = $path; Extension = $extension; Exclusion = $reason }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $inventory = @(Get-SourceHeaderInventory -Root $RepoRoot)
    $eligible = @($inventory | Where-Object { -not $_.Exclusion })
    $excluded = @($inventory | Where-Object Exclusion)
    $failures = [Collections.Generic.List[string]]::new()
    foreach ($file in $eligible) {
        $content = [IO.File]::ReadAllText((Join-Path $RepoRoot $file.Path))
        $offset = Get-SourceHeaderOffset -Content $content -Extension $file.Extension
        $prefix = if ($file.Extension -in '.html', '.svg', '.njk', '.md') {
            '<!--\r?\nCopyright \(c\) Microsoft Corporation\.\r?\nLicensed under the MIT license\.\r?\n-->'
        }
        elseif ($file.Extension -eq '.css') {
            '/\*\r?\nCopyright \(c\) Microsoft Corporation\.\r?\nLicensed under the MIT license\.\r?\n\*/'
        }
        elseif ($file.Extension -in '.js', '.mjs') {
            '// Copyright \(c\) Microsoft Corporation\.\r?\n// Licensed under the MIT license\.'
        }
        else {
            '# Copyright \(c\) Microsoft Corporation\.\r?\n# Licensed under the MIT license\.'
        }
        if ($content.Substring($offset) -notmatch "\A$prefix(?:\r?\n|$)") {
            $failures.Add($file.Path)
        }
    }
    "Eligible=$($eligible.Count) Headed=$($eligible.Count - $failures.Count) Excluded=$($excluded.Count)"
    $eligible | Group-Object Extension | Sort-Object Name |
        ForEach-Object { "Eligible $($_.Name): $($_.Count)" }
    $excluded | Group-Object Exclusion | Sort-Object Name |
        ForEach-Object { "Excluded $($_.Count): $($_.Name)" }
    if ($Detailed) { $excluded | ForEach-Object { "$($_.Path): $($_.Exclusion)" } }
    if ($failures.Count) { throw "Missing or misplaced exact notice: $($failures -join ', ')" }
}
