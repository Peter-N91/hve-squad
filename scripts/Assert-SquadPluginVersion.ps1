#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Validates a stable or preview plugin publication version.
.DESCRIPTION
    Stable publications require a plain MAJOR.MINOR.PATCH version. Preview
    publications require a SemVer prerelease label. When an existing branch
    version is supplied, the new version may stay equal for an idempotent build
    but must never move backwards under SemVer ordering.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('stable', 'preview')]
    [string]$Channel,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$NewVersion,

    [Parameter(Mandatory = $false)]
    [string]$OldVersion
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

try {
    $newSemanticVersion = [System.Management.Automation.SemanticVersion]::Parse($NewVersion)
}
catch {
    throw "Invalid plugin version '$NewVersion': $($_.Exception.Message)"
}

if ($Channel -eq 'stable' -and $NewVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "Stable plugin publication requires a plain MAJOR.MINOR.PATCH version; received '$NewVersion'."
}
if ($Channel -eq 'preview' -and -not $newSemanticVersion.PreReleaseLabel) {
    throw "Preview plugin publication requires a prerelease version; received '$NewVersion'."
}

if ($OldVersion) {
    try {
        $oldSemanticVersion = [System.Management.Automation.SemanticVersion]::Parse($OldVersion)
    }
    catch {
        throw "Invalid existing plugin version '$OldVersion': $($_.Exception.Message)"
    }
    if ($newSemanticVersion -lt $oldSemanticVersion) {
        throw "Refusing to move the $Channel plugin branch backwards from $OldVersion to $NewVersion."
    }
}

Write-Host "Version gate passed: $Channel $($OldVersion ?? '<first publish>') -> $NewVersion" -ForegroundColor Green
