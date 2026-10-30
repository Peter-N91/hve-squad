# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
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

    [string[]]$RelativePaths
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RelativePaths -or $RelativePaths.Count -eq 0) {
    $RelativePaths = @(
        'squad-src/.github/skills/squad/scripts/SquadWatch.psm1',
        'squad-src/.github/skills/squad/scripts/SquadWatch.Delivery.ps1',
        'squad-src/.github/skills/squad/scripts/Invoke-SquadWatchMarkedBody.ps1',
        'scripts/New-ChangeFragment.ps1',
        'tests/lib/SquadInstall.psm1'
    )
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
