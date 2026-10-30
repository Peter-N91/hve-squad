# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
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
$assertBlob = (& git -C $trusted show "${sha}:squad-src/.github/skills/squad/scripts/Assert-SquadWatchTrustedCheckout.ps1") -join "`n"
if ($LASTEXITCODE -ne 0) {
    throw 'Pinned trusted-checkout verifier is missing from git show.'
}
$assertPath = Join-Path $env:RUNNER_TEMP 'Assert-SquadWatchTrustedCheckout.ps1'
[System.IO.File]::WriteAllText($assertPath, $assertBlob)
& $assertPath -TrustedRoot $trusted -ExpectedSha $sha

. (Join-Path $trusted 'squad-src/.github/skills/squad/scripts/SquadWatch.Delivery.ps1')
$catalog = (& git -C $trusted show "${sha}:squad-src/.github/skills/squad/references/profiles-and-packs.md") -join "`n"
$gate = Test-SquadWatchAppliedPublication `
    -Repository $env:GITHUB_WORKSPACE `
    -Member $env:SUB_SQUAD `
    -CurrentRunId $env:RUN_ID `
    -CurrentThread $env:SOURCE_THREAD_REF `
    -StableRef $env:STABLE_REF `
    -TrustedBaseSha $sha `
    -CatalogMarkdown $catalog
if ($gate.BlockPublication) {
    throw 'Applied patch failed current-run profile or question validation.'
}
