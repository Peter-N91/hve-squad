#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Assembles pending .changes/unreleased fragments into a CHANGELOG release
    section, bumps apm.yml, and clears the consumed fragments.
.DESCRIPTION
    Version and changelog are release outputs, not things a pull request edits.
    This script turns the fragments collected on the default branch into both:

      1. Resolves the new version from the highest 'bump' across all fragments.
      2. Groups fragment bodies by 'type' in Keep a Changelog order.
      3. Prepends the assembled section to CHANGELOG.md, with the standard
         consumer-install block and the link reference.
      4. Writes the new version into apm.yml.
      5. Deletes the fragments it consumed.

    Fragment format is documented in .changes/README.md.
.PARAMETER ApmFile
    Path to apm.yml, whose 'version:' line is rewritten.
.PARAMETER ChangelogFile
    Path to CHANGELOG.md, which the new section is prepended to.
.PARAMETER FragmentDir
    Directory holding pending fragments.
.PARAMETER RepoSlug
    Repository slug in owner/repo format, used for the install snippet and the
    release link reference.
.PARAMETER Version
    Explicit version to release. Overrides the version resolved from fragments.
.PARAMETER Bump
    Release level to apply, overriding the highest bump the fragments requested.
    The maintainer has the last word on whether a batch of work is a new idea
    (minor) or more of one that already shipped (patch). Ignored when Version is
    supplied.
.PARAMETER ReleaseDate
    Date stamped on the section. Defaults to today in UTC.
.PARAMETER ExtraEntry
    Additional changelog bullet appended to the Changed section, for automation
    that has something to record beyond the pending fragments.
.PARAMETER AllowEmpty
    Proceed with a patch bump even when no fragments are pending. Without this,
    an empty fragment directory is a no-op.
.PARAMETER DryRun
    Print the assembled section and resolved version without writing anything.
.PARAMETER GitHubOutput
    Append 'version', 'previous_version', and 'has_changes' to $env:GITHUB_OUTPUT.
.PARAMETER SectionOutFile
    Also write the assembled section to this path. Honoured under -DryRun, which
    is how the rolling pre-release renders the notes for the release currently
    accumulating on main without consuming the fragments.
.PARAMETER InstallRef
    Tag the consumer-install snippet and link reference point at. Defaults to
    'v<newVersion>'. The pre-release passes its own rolling tag.
.EXAMPLE
    ./scripts/Invoke-ReleasePrep.ps1
.EXAMPLE
    ./scripts/Invoke-ReleasePrep.ps1 -DryRun
.EXAMPLE
    ./scripts/Invoke-ReleasePrep.ps1 -DryRun -SectionOutFile notes.md -InstallRef v0.14.0-pre
.EXAMPLE
    ./scripts/Invoke-ReleasePrep.ps1 -Version 1.0.0
.EXAMPLE
    ./scripts/Invoke-ReleasePrep.ps1 -Bump minor
.NOTES
    Intended for use with: apm run release-prep
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ApmFile = 'apm.yml',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ChangelogFile = 'CHANGELOG.md',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$FragmentDir = '.changes/unreleased',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoSlug = 'Peter-N91/hve-squad',

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [ValidateSet('major', 'minor', 'patch')]
    [string]$Bump,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ReleaseDate,

    [Parameter(Mandatory = $false)]
    [string]$ExtraEntry,

    [Parameter(Mandatory = $false)]
    [switch]$AllowEmpty,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$GitHubOutput,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SectionOutFile,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$InstallRef
)

$ErrorActionPreference = 'Stop'

$script:SectionOrder = @('Added', 'Changed', 'Deprecated', 'Removed', 'Fixed', 'Security')
$script:BumpRank = @{ patch = 1; minor = 2; major = 3 }

#region Functions
function Read-Fragment {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    $raw = Get-Content -LiteralPath $File.FullName -Raw
    $match = [regex]::Match($raw, '(?s)^\s*---\s*\r?\n(?<fm>.*?)\r?\n---\s*\r?\n(?<body>.*)$')
    if (-not $match.Success) {
        throw "$($File.Name): missing YAML frontmatter. See .changes/README.md."
    }

    $frontMatter = @{}
    foreach ($line in ($match.Groups['fm'].Value -split '\r?\n')) {
        if ($line -match '^\s*(?<key>[A-Za-z_]+)\s*:\s*(?<value>.+?)\s*$') {
            $frontMatter[$Matches['key'].ToLowerInvariant()] = $Matches['value'].Trim('"', "'")
        }
    }

    $bump = $frontMatter['bump']
    $type = $frontMatter['type']
    $body = $match.Groups['body'].Value.Trim()

    if (-not $script:BumpRank.ContainsKey($bump)) {
        throw "$($File.Name): bump must be major, minor, or patch (found '$bump')."
    }
    $canonicalType = $script:SectionOrder | Where-Object { $_ -ieq $type }
    if (-not $canonicalType) {
        throw "$($File.Name): type must be one of $($script:SectionOrder -join ', ') (found '$type')."
    }
    if (-not $body) {
        throw "$($File.Name): the changelog entry body is empty."
    }
    if ($body -notmatch '(?m)^\s*-\s') {
        throw "$($File.Name): the body must be markdown bullets starting with '- '."
    }

    return [pscustomobject]@{
        Name = $File.Name
        Path = $File.FullName
        Bump = $bump
        Type = $canonicalType
        Body = $body
    }
}

function Get-NextVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Current,

        [Parameter(Mandatory = $true)]
        [string]$Bump
    )

    $parts = $Current -split '\.'
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $patch = [int]$parts[2]

    switch ($Bump) {
        'major' { return "$($major + 1).0.0" }
        'minor' { return "$major.$($minor + 1).0" }
        default { return "$major.$minor.$($patch + 1)" }
    }
}

function New-ChangelogSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NewVersion,

        [Parameter(Mandatory = $true)]
        [string]$Date,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [pscustomobject[]]$Fragments,

        [Parameter(Mandatory = $false)]
        [string]$Additional,

        [Parameter(Mandatory = $false)]
        [string]$Ref
    )

    if (-not $Ref) { $Ref = "v$NewVersion" }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("## [$NewVersion] - $Date")

    foreach ($section in $script:SectionOrder) {
        $bodies = @($Fragments | Where-Object { $_.Type -eq $section } | ForEach-Object { $_.Body })
        if ($section -eq 'Changed' -and $Additional) { $bodies += $Additional.Trim() }
        if (-not $bodies) { continue }

        $lines.Add('')
        $lines.Add("### $section")
        foreach ($entry in $bodies) {
            $lines.Add('')
            $lines.Add($entry)
        }
    }

    $lines.Add('')
    $lines.Add('### Consumer install')
    $lines.Add('')
    $lines.Add('Pin to this version:')
    $lines.Add('')
    $lines.Add('```powershell')
    $lines.Add("apm install `"$RepoSlug#$Ref`"")
    $lines.Add('```')
    $lines.Add('')
    $lines.Add("[$NewVersion]: https://github.com/$RepoSlug/releases/tag/$Ref")
    $lines.Add('')

    return ($lines -join "`n")
}
#endregion Functions

#region Main
foreach ($required in @($ApmFile, $ChangelogFile)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Not found: $required" }
}

$fragmentFiles = @()
if (Test-Path -LiteralPath $FragmentDir) {
    $fragmentFiles = @(Get-ChildItem -LiteralPath $FragmentDir -Filter '*.md' -File |
        Where-Object { $_.Name -ne 'README.md' } |
        Sort-Object Name)
}

if (-not $fragmentFiles -and -not $AllowEmpty -and -not $Version) {
    Write-Host 'No pending fragments in .changes/unreleased — nothing to release.' -ForegroundColor Yellow
    if ($GitHubOutput -and $env:GITHUB_OUTPUT) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value 'has_changes=false'
    }
    return
}

$fragments = @($fragmentFiles | ForEach-Object { Read-Fragment -File $_ })

$apmContent = Get-Content -LiteralPath $ApmFile -Raw
$versionMatch = [regex]::Match($apmContent, '(?m)^version:[ \t]*(?<v>\d+\.\d+\.\d+)[ \t]*\r?$')
if (-not $versionMatch.Success) { throw "No 'version: X.Y.Z' line found in $ApmFile." }
$currentVersion = $versionMatch.Groups['v'].Value

if ($Version) {
    $newVersion = $Version
    $resolvedBump = 'explicit'
}
else {
    $resolvedBump = 'patch'
    foreach ($fragment in $fragments) {
        if ($script:BumpRank[$fragment.Bump] -gt $script:BumpRank[$resolvedBump]) { $resolvedBump = $fragment.Bump }
    }
    if ($Bump -and $Bump -ne $resolvedBump) {
        Write-Host "Bump override: fragments resolved to '$resolvedBump', releasing as '$Bump'." -ForegroundColor Yellow
        $resolvedBump = $Bump
    }
    $newVersion = Get-NextVersion -Current $currentVersion -Bump $resolvedBump
}

if (-not $ReleaseDate) { $ReleaseDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd') }

$changelog = Get-Content -LiteralPath $ChangelogFile -Raw
if ($changelog -match "(?m)^## \[$([regex]::Escape($newVersion))\]") {
    throw "CHANGELOG.md already documents $newVersion. Pass -Version to target a different release."
}

$section = New-ChangelogSection -NewVersion $newVersion -Date $ReleaseDate -Fragments $fragments -Additional $ExtraEntry -Ref $InstallRef

if ($SectionOutFile) {
    Set-Content -LiteralPath $SectionOutFile -Value $section -Encoding utf8NoBOM
}

Write-Host "Version:   $currentVersion -> $newVersion ($resolvedBump)" -ForegroundColor Cyan
Write-Host "Fragments: $($fragments.Count)" -ForegroundColor Cyan
foreach ($fragment in $fragments) {
    Write-Host ("  {0,-8} {1,-10} {2}" -f $fragment.Bump, $fragment.Type, $fragment.Name) -ForegroundColor DarkGray
}
Write-Host ''
Write-Host $section

if ($DryRun) {
    Write-Host 'Dry run — nothing written.' -ForegroundColor Yellow
    if ($GitHubOutput -and $env:GITHUB_OUTPUT) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value @(
            "version=$newVersion"
            "previous_version=$currentVersion"
            'has_changes=true'
        )
    }
    return
}

if (-not $PSCmdlet.ShouldProcess("$ChangelogFile and $ApmFile", "Release $newVersion")) { return }

# Insert above the newest existing release heading so the file stays reverse-chronological.
$anchor = [regex]::Match($changelog, '(?m)^## \[')
$updatedChangelog = if ($anchor.Success) {
    $changelog.Substring(0, $anchor.Index) + $section + "`n" + $changelog.Substring($anchor.Index)
}
else {
    $changelog.TrimEnd() + "`n`n" + $section
}
Set-Content -LiteralPath $ChangelogFile -Value $updatedChangelog -Encoding utf8NoBOM -NoNewline

$updatedApm = [regex]::Replace($apmContent, '(?m)^version:[ \t]*\d+\.\d+\.\d+[ \t]*(?=\r?$)', "version: $newVersion")
Set-Content -LiteralPath $ApmFile -Value $updatedApm -Encoding utf8NoBOM -NoNewline

foreach ($fragment in $fragments) {
    Remove-Item -LiteralPath $fragment.Path -Force
}

Write-Host ''
Write-Host "Released $newVersion. Consumed $($fragments.Count) fragment(s)." -ForegroundColor Green

if ($GitHubOutput -and $env:GITHUB_OUTPUT) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value @(
        "version=$newVersion"
        "previous_version=$currentVersion"
        'has_changes=true'
    )
}
#endregion Main
