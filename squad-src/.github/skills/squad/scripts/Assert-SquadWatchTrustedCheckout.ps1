# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

<#
.SYNOPSIS
    Proves a trusted checkout HEAD and every imported helper match the pinned base.
.DESCRIPTION
    Run this script before Import-Module or dot-sourcing. It reads pinned blobs with
    git show and never trusts a working-tree copy that differs from trustedBaseSha.
#>
#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TrustedRoot,

    [Parameter(Mandatory)]
    [string]$ExpectedSha,

    [string]$SkillRoot,

    [string[]]$RelativePaths,

    [string[]]$AdditionalRelativePaths
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-PinnedSkillRoot {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Sha,
        [AllowNull()][string]$Configured
    )

    if (-not [string]::IsNullOrWhiteSpace($Configured)) {
        $normalized = ($Configured.Trim() -replace '\\', '/').TrimEnd('/')
        if ([string]::IsNullOrWhiteSpace($normalized) -or
            [System.IO.Path]::IsPathRooted($normalized) -or
            $normalized.StartsWith('-') -or
            $normalized -match '[:\x00-\x1f]' -or
            $normalized -match '(^|/)\.\.?(/|$)') {
            throw "Invalid SQUAD_WATCH_SKILL_ROOT '$Configured': must be a safe repository-relative path."
        }
        & git -C $Root cat-file -e "${Sha}:${normalized}/scripts/SquadWatch.psm1" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Pinned Squad Watch skill root '$normalized' is missing SquadWatch.psm1 at $Sha."
        }
        return $normalized
    }

    foreach ($candidate in @('.agents/skills/squad', '.github/skills/squad', 'squad-src/.github/skills/squad')) {
        & git -C $Root cat-file -e "${Sha}:${candidate}/scripts/SquadWatch.psm1" 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $candidate
        }
    }

    throw "Pinned Squad Watch skill root not found at $Sha (checked .agents/skills/squad, .github/skills/squad, squad-src/.github/skills/squad)."
}

function ConvertTo-SquadWatchPinnedText {
    param([AllowNull()][string]$Text)
    return (([string]$Text -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd("`n"))
}

$headLines = @(& git -C $TrustedRoot rev-parse HEAD 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Trusted checkout has no HEAD: $($headLines -join "`n")"
}
$head = ([string]$headLines[-1]).Trim()
if ($head -cne $ExpectedSha) {
    throw "Trusted checkout HEAD '$head' is not pinned '$ExpectedSha'."
}

if (-not $RelativePaths -or $RelativePaths.Count -eq 0) {
    $configuredRoot = if (-not [string]::IsNullOrWhiteSpace($SkillRoot)) { $SkillRoot } else { [string]$env:SQUAD_WATCH_SKILL_ROOT }
    $resolvedSkillRoot = Resolve-PinnedSkillRoot -Root $TrustedRoot -Sha $ExpectedSha -Configured $configuredRoot
    $RelativePaths = @(
        "$resolvedSkillRoot/scripts/SquadWatch.psm1",
        "$resolvedSkillRoot/scripts/SquadWatch.Delivery.ps1",
        "$resolvedSkillRoot/scripts/Invoke-SquadWatchMarkedBody.ps1",
        "$resolvedSkillRoot/references/profiles-and-packs.md"
    )
    if (-not [string]::IsNullOrWhiteSpace($env:SQUAD_WATCH_ADDITIONAL_PATHS)) {
        $AdditionalRelativePaths = @(@($AdditionalRelativePaths) + @($env:SQUAD_WATCH_ADDITIONAL_PATHS))
    }
}

if ($AdditionalRelativePaths -and $AdditionalRelativePaths.Count -gt 0) {
    $extras = @(
        $AdditionalRelativePaths |
            ForEach-Object { ([string]$_) -split '[,;]' } |
            ForEach-Object { ($_.Trim() -replace '\\', '/').TrimStart('/') } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $RelativePaths = @(@($RelativePaths) + @($extras) | Select-Object -Unique)
}

foreach ($relative in $RelativePaths) {
    $blob = @(& git -C $TrustedRoot show "${ExpectedSha}:${relative}" 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Pinned helper missing at ${ExpectedSha}:${relative}."
    }
    $diskPath = Join-Path $TrustedRoot ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $diskPath -PathType Leaf)) {
        throw "Trusted helper is not on disk: $relative"
    }
    $pinned = ConvertTo-SquadWatchPinnedText -Text ($blob -join "`n")
    $disk = ConvertTo-SquadWatchPinnedText -Text ([System.IO.File]::ReadAllText($diskPath))
    if ($pinned -cne $disk) {
        throw "Helper '$relative' does not match pinned $ExpectedSha."
    }
}
