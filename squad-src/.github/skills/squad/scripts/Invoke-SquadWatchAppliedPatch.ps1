# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

<#
.SYNOPSIS
    Revalidates an applied Watch patch from the files the patch wrote.
.DESCRIPTION
    The script is executed from a git show blob, not from a model-writable copy.
    It refuses to push when the applied decisions.md lacks required current-run coverage.
#>
#Requires -Version 7.4
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$trusted = Join-Path $env:GITHUB_WORKSPACE '.squad-trusted'
$sha = [string]$env:TRUSTED_BASE_SHA
if ([string]::IsNullOrWhiteSpace($sha)) {
    throw 'trustedBaseSha is empty. Refusing to validate the applied patch.'
}
$head = (& git -C $trusted rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -cne $sha) {
    throw "Trusted checkout HEAD '$head' is not pinned '$sha'."
}

$configuredRoot = ([string]$env:SQUAD_WATCH_SKILL_ROOT).Trim().Replace('\', '/').TrimEnd('/')
$skillRoot = ''
if (-not [string]::IsNullOrWhiteSpace($configuredRoot)) {
    if ([System.IO.Path]::IsPathRooted($configuredRoot) -or
        $configuredRoot.StartsWith('-') -or
        $configuredRoot -match '[:\x00-\x1f]' -or
        $configuredRoot -match '(^|/)\.\.?(/|$)') {
        throw "Invalid SQUAD_WATCH_SKILL_ROOT '$configuredRoot': must be a safe repository-relative path."
    }
    & git -C $trusted cat-file -e "${sha}:${configuredRoot}/scripts/SquadWatch.psm1" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Pinned Squad Watch skill root '$configuredRoot' is missing SquadWatch.psm1 at $sha."
    }
    $skillRoot = $configuredRoot
}
else {
    foreach ($candidate in @('.agents/skills/squad', '.github/skills/squad', 'squad-src/.github/skills/squad')) {
        & git -C $trusted cat-file -e "${sha}:${candidate}/scripts/SquadWatch.psm1" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $skillRoot = $candidate
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($skillRoot)) {
    throw "Pinned Squad Watch skill root not found at $sha."
}

$assertBlob = (& git -C $trusted show "${sha}:${skillRoot}/scripts/Assert-SquadWatchTrustedCheckout.ps1") -join "`n"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($assertBlob)) {
    throw 'Pinned trusted-checkout verifier is missing from git show.'
}
$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$assertPath = Join-Path $tempRoot 'Assert-SquadWatchTrustedCheckout.ps1'
[System.IO.File]::WriteAllText($assertPath, $assertBlob)
& $assertPath -TrustedRoot $trusted -ExpectedSha $sha -SkillRoot $skillRoot

. (Join-Path $trusted ($skillRoot -replace '/', [System.IO.Path]::DirectorySeparatorChar) 'scripts/SquadWatch.Delivery.ps1')
$catalog = (& git -C $trusted show "${sha}:${skillRoot}/references/profiles-and-packs.md") -join "`n"
$gate = Test-SquadWatchAppliedPublication `
    -Repository $env:GITHUB_WORKSPACE `
    -Member $env:SUB_SQUAD `
    -CurrentRunId $env:RUN_ID `
    -CurrentThread $env:SOURCE_THREAD_REF `
    -StableRef $env:STABLE_REF `
    -TrustedBaseSha $sha `
    -CatalogMarkdown $catalog `
    -InstalledPacks @() `
    -InstalledSkills @()
if ($gate.BlockPublication) {
    throw 'Applied patch failed current-run profile or question validation.'
}
