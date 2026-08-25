#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Creates a change fragment under .changes/unreleased/ for the current pull request.
.DESCRIPTION
    Contributors never edit CHANGELOG.md or bump apm.yml — both are release outputs
    assembled on the default branch. Instead each pull request adds one uniquely
    named fragment here, which is why concurrent pull requests never conflict on
    release state.

    Run with no parameters for an interactive prompt, or supply Type, Bump, Title,
    and Body to generate the file non-interactively.
.PARAMETER Type
    Keep a Changelog section the entry belongs to.
.PARAMETER Bump
    Release impact of this change. When several fragments are pending at release
    time, the highest bump across all of them selects the new version. The level
    tracks ideas, not artifacts: a new agent or skill under an idea that already
    shipped is a patch, and minor is reserved for a capability class that did not
    exist before.
.PARAMETER Title
    Short description used to build the file name. Slugified to lowercase words.
.PARAMETER Body
    Changelog text. Markdown bullets starting with '- '. A value that does not
    start with '- ' is wrapped into a single bullet.
.PARAMETER FragmentDir
    Directory that pending fragments are written to.
.PARAMETER Force
    Overwrite an existing fragment with the same name.
.EXAMPLE
    ./scripts/New-ChangeFragment.ps1
.EXAMPLE
    ./scripts/New-ChangeFragment.ps1 -Type Fixed -Bump patch -Title 'consumption table width' -Body '- **The ledger was unreadable at render width.** Split into two tables.'
.NOTES
    Intended for use with: apm run change
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Added', 'Changed', 'Deprecated', 'Removed', 'Fixed', 'Security')]
    [string]$Type,

    [Parameter(Mandatory = $false)]
    [ValidateSet('major', 'minor', 'patch')]
    [string]$Bump,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Title,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Body,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$FragmentDir = '.changes/unreleased',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

#region Functions
function Select-FromMenu {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $true)]
        [string[]]$Options,

        [Parameter(Mandatory = $true)]
        [string[]]$Hints,

        [Parameter(Mandatory = $false)]
        [string]$Default
    )

    Write-Host ''
    Write-Host $Prompt -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($Options[$i] -eq $Default) { ' (default)' } else { '' }
        Write-Host ("  {0}) {1,-10} {2}{3}" -f ($i + 1), $Options[$i], $Hints[$i], $marker)
    }

    while ($true) {
        $answer = (Read-Host 'Choice').Trim()
        if (-not $answer -and $Default) { return $Default }
        if ($answer -match '^\d+$') {
            $index = [int]$answer - 1
            if ($index -ge 0 -and $index -lt $Options.Count) { return $Options[$index] }
        }
        $match = $Options | Where-Object { $_ -ieq $answer }
        if ($match) { return $match }
        Write-Host 'Pick one of the listed values.' -ForegroundColor Yellow
    }
}

function ConvertTo-Slug {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $slug = $Text.ToLowerInvariant()
    $slug = [regex]::Replace($slug, '[^a-z0-9]+', '-')
    $slug = $slug.Trim('-')
    if ($slug.Length -gt 48) { $slug = $slug.Substring(0, 48).Trim('-') }
    if (-not $slug) { $slug = 'change' }
    return $slug
}

function Read-MultilineBody {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Write-Host ''
    Write-Host 'Changelog entry' -ForegroundColor Cyan
    Write-Host '  Write it the way it should read in the release notes. Lead with a bold'
    Write-Host '  sentence naming the problem, then what changed, then the file paths.'
    Write-Host '  Blank line to finish. The leading "- " is added for you.'
    Write-Host ''

    $lines = @()
    while ($true) {
        $line = Read-Host '>'
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        $lines += $line
    }
    return ($lines -join ' ')
}
#endregion Functions

#region Main
$typeHints = @(
    'a new agent, skill, prompt, role, or capability',
    'behavior of something that already shipped',
    'still works, but is on its way out',
    'no longer shipped',
    'a defect corrected',
    'a vulnerability or hardening change'
)
$bumpHints = @(
    'extends an idea that already ships - most changes land here',
    'a genuinely new idea, or the package is used differently now',
    'a consumer must change something to keep working'
)

if (-not $Type) {
    $Type = Select-FromMenu -Prompt 'What kind of change is this?' `
        -Options @('Added', 'Changed', 'Deprecated', 'Removed', 'Fixed', 'Security') `
        -Hints $typeHints
}

if (-not $Bump) {
    Write-Host ''
    Write-Host 'The level tracks ideas, not artifacts. A new agent, skill, or role under' -ForegroundColor DarkGray
    Write-Host 'an idea that already ships is a patch, however many files it adds.' -ForegroundColor DarkGray
    $Bump = Select-FromMenu -Prompt 'How should the version move?' `
        -Options @('patch', 'minor', 'major') `
        -Hints $bumpHints `
        -Default 'patch'
}

if (-not $Title) {
    Write-Host ''
    Write-Host 'Short title (used for the file name only)' -ForegroundColor Cyan
    while (-not $Title) { $Title = (Read-Host 'Title').Trim() }
}

if (-not $Body) {
    $Body = Read-MultilineBody
    if (-not $Body) { throw 'A changelog entry is required.' }
}

$normalizedBody = $Body.TrimEnd()
if ($normalizedBody -notmatch '(?m)^\s*-\s') {
    $normalizedBody = "- $normalizedBody"
}

$slug = ConvertTo-Slug -Text $Title
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd')
$fileName = "$stamp-$slug.md"

if (-not (Test-Path -LiteralPath $FragmentDir)) {
    New-Item -ItemType Directory -Path $FragmentDir -Force | Out-Null
}

$fragmentPath = Join-Path $FragmentDir $fileName
if ((Test-Path -LiteralPath $fragmentPath) -and -not $Force) {
    throw "$fragmentPath already exists. Choose a different title or pass -Force."
}

$content = @"
---
bump: $Bump
type: $Type
---

$normalizedBody
"@

if ($PSCmdlet.ShouldProcess($fragmentPath, 'Write change fragment')) {
    Set-Content -LiteralPath $fragmentPath -Value $content -Encoding utf8NoBOM
    Write-Host ''
    Write-Host "Created $fragmentPath" -ForegroundColor Green
    Write-Host 'Commit it with your change. Do not edit CHANGELOG.md or apm.yml.' -ForegroundColor DarkGray
}
#endregion Main
