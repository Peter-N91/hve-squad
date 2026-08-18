#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Pins this package's own squad self-references in apm.yml to a git ref.
.DESCRIPTION
    Every dependency in apm.yml that points back at this repository
    (Peter-N91/hve-squad/squad-src/...) ships as a bare path with no '#ref'.
    APM resolves a bare path against the repository's default branch, so a
    release tag freezes the dependency *list* but not the dependency *contents*:
    installing an old tag delivers today's squad files.

    Measured 2026-08-18: installing '#v0.14.0' returned main's coordinator, while
    the hve-core entries in the same manifest — which do carry '#<sha>' — resolved
    correctly to the pinned commit. APM itself warns
    '47 dependencies unpinned: Peter-N91/hve-squad -- add #tag or #sha to prevent drift'.

    This script appends '#<Ref>' to those entries and nothing else. It is
    deliberately separate from Update-ApmDependencies.ps1, which reaches the same
    result via -SquadRef but must clone hve-core to enumerate it first. At release
    time the manifest is already correct and only needs the suffix, so an offline,
    deterministic rewrite is the safer operation.

    Entries that already carry a ref are left untouched, so the script is
    idempotent. hve-core entries are never modified.
.PARAMETER ApmFile
    Path to the apm.yml to rewrite.
.PARAMETER Ref
    Git ref to pin to — normally the release tag being cut, for example 'v0.16.0'.
.PARAMETER RepoSlug
    Repository slug whose self-references are pinned.
.PARAMETER DryRun
    Report what would change without writing the file.
.EXAMPLE
    ./scripts/Set-SquadSelfRefPin.ps1 -Ref v0.16.0
.EXAMPLE
    ./scripts/Set-SquadSelfRefPin.ps1 -Ref v0.16.0 -DryRun
.NOTES
    Runs in release.yml against the commit the tag will point at. That commit is
    intentionally not pushed to main: main keeps the unpinned manifest so
    development installs continue to track main.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ApmFile = 'apm.yml',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Ref,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoSlug = 'Peter-N91/hve-squad',

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ApmFile)) {
    throw "Manifest not found: $ApmFile"
}

if ($Ref -match '[\s#]') {
    throw "Ref '$Ref' contains whitespace or '#'."
}

$lines = Get-Content -LiteralPath $ApmFile
$pattern = '^(?<indent>\s*-\s+)(?<path>' + [regex]::Escape($RepoSlug) + '/\S+)$'

$pinned = 0
$alreadyPinned = 0

$updated = foreach ($line in $lines) {
    if ($line -match $pattern) {
        if ($Matches['path'] -like '*#*') {
            $alreadyPinned++
            $line
        }
        else {
            $pinned++
            "$($Matches['indent'])$($Matches['path'])#$Ref"
        }
    }
    else {
        $line
    }
}

if ($pinned -eq 0 -and $alreadyPinned -eq 0) {
    throw "No $RepoSlug self-references found in $ApmFile. Refusing to write a manifest this script does not understand."
}

if ($DryRun) {
    Write-Host "[dry run] would pin $pinned entries to #$Ref ($alreadyPinned already pinned)." -ForegroundColor Yellow
    return
}

Set-Content -LiteralPath $ApmFile -Value $updated
Write-Host "Pinned $pinned $RepoSlug entries to #$Ref ($alreadyPinned already pinned)." -ForegroundColor Green
