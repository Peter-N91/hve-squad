#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the Tier 0 static conformance suite against an installed hve-squad package.
.DESCRIPTION
    Tier 0 asserts that the package a consumer actually receives is internally
    consistent: rosters resolve, skill references exist, agent bodies fit the host
    cap, and prompts bind to delivered agents. It invokes no model and needs no
    secrets, which is why it can gate every pull request as well as the release.

    The suite deliberately inspects an installed tree rather than squad-src/, because
    the defects it exists to catch - an undelivered agent, a reference that resolves
    to the wrong ref - only appear after packaging.

    Supply -Ref to install a published ref into a scratch directory, or -PackageRoot
    to assert against a tree that is already installed.
.PARAMETER Ref
    Git ref of the package to install and test, for example 'v0.15.3' or 'main'.
    Ignored when -PackageRoot is supplied.
.PARAMETER Package
    Package slug to install. Defaults to the squad package.
.PARAMETER PackageRoot
    Directory holding an already-installed tree (the parent of .github/ and .agents/).
    Skips installation entirely.
.PARAMETER ScratchRoot
    Directory to install into. Defaults to a new folder under the temp directory.
.PARAMETER Target
    Harness to deploy to. APM refuses to guess in an empty directory, so this is
    always passed explicitly.
.PARAMETER Output
    Pester output verbosity.
.EXAMPLE
    ./Invoke-Tier0Tests.ps1 -Ref v0.15.3
.EXAMPLE
    ./Invoke-Tier0Tests.ps1 -PackageRoot .
.NOTES
    See tests/squad-behavior-contract.md for the cases this implements (PKG-01..PKG-10).
#>
[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Install')]
    [string]$Ref = 'main',

    [Parameter(ParameterSetName = 'Install')]
    [string]$Package = 'Peter-N91/hve-squad',

    [Parameter(ParameterSetName = 'Install')]
    [string]$ScratchRoot,

    [Parameter(ParameterSetName = 'Install')]
    [string]$Target = 'copilot',

    [Parameter(Mandatory, ParameterSetName = 'Installed')]
    [string]$PackageRoot,

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed',

    # Cap breaches in third-party agents are reported, not gated.
    [switch]$IncludeAdvisory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$installLog = $null

if ($PSCmdlet.ParameterSetName -eq 'Install') {
    if (-not (Get-Command apm -ErrorAction SilentlyContinue)) {
        throw "The 'apm' CLI was not found on PATH. Install it, or re-run with -PackageRoot against an already-installed tree."
    }

    if (-not $ScratchRoot) {
        $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) "hve-squad-tier0-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    }

    New-Item -ItemType Directory -Path $ScratchRoot -Force | Out-Null
    $installLog = Join-Path $ScratchRoot 'install.log'

    Write-Host "Installing $Package#$Ref into $ScratchRoot" -ForegroundColor Cyan

    Push-Location $ScratchRoot
    try {
        # Both streams are captured: the unpinned-reference warning PKG-01 asserts on
        # is emitted to stderr.
        & apm install "$Package#$Ref" --target $Target *>&1 | Tee-Object -FilePath $installLog
        if ($LASTEXITCODE -ne 0) {
            throw "apm install failed with exit code $LASTEXITCODE. See $installLog."
        }
    }
    finally {
        Pop-Location
    }

    $PackageRoot = $ScratchRoot
}

$PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path

# Only a release tag pins its own references; main ships the unpinned manifest by design.
$expectPinned = $PSCmdlet.ParameterSetName -eq 'Install' -and $Ref -match '^v\d+\.\d+\.\d+'

$container = New-PesterContainer -Path (Join-Path $PSScriptRoot 'SquadPackage.Tests.ps1') -Data @{
    PackageRoot  = $PackageRoot
    InstallLog   = $installLog
    ExpectPinned = [bool]$expectPinned
}

$config = New-PesterConfiguration
$config.Run.Container = $container
$config.Run.PassThru = $true
$config.Output.Verbosity = $Output
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $PSScriptRoot 'tier0-results.xml'

if (-not $IncludeAdvisory) {
    $config.Filter.ExcludeTag = 'Advisory'
}

$result = Invoke-Pester -Configuration $config

if ($result.FailedCount -gt 0) {
    exit 1
}
