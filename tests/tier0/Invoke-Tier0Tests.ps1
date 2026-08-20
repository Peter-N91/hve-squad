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

    Supply -Ref to install a published ref into a scratch directory, -PackageRoot to
    assert against a tree that is already installed, or -SourceRoot to test a working
    copy.

    -SourceRoot exists because a pull request branch cannot be installed: the manifest's
    self-references are bare paths, so APM resolves them against the default branch and
    any file the branch adds is reported missing. Source mode installs the manifest
    normally - hve-core at its pin, squad files from the default branch - and then
    overlays the working copy's squad-src/ on top, which is the tree the branch would
    deliver once merged.
.PARAMETER Ref
    Git ref of the package to install and test, for example 'v0.15.3' or 'main'.
.PARAMETER Package
    Package slug to install. Defaults to the squad package.
.PARAMETER PackageRoot
    Directory holding an already-installed tree (the parent of .github/ and .agents/).
    Skips installation entirely.
.PARAMETER SourceRoot
    Repository root holding apm.yml and squad-src/. Installs the manifest, then overlays
    squad-src/ and additionally runs the manifest-coverage cases.
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
    ./Invoke-Tier0Tests.ps1 -SourceRoot .
.NOTES
    See tests/squad-behavior-contract.md for the cases this implements (PKG-01..PKG-11).
#>
[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Install')]
    [string]$Ref = 'main',

    [Parameter(ParameterSetName = 'Install')]
    [string]$Package = 'Peter-N91/hve-squad',

    [Parameter(Mandatory, ParameterSetName = 'Installed')]
    [string]$PackageRoot,

    [Parameter(Mandatory, ParameterSetName = 'Source')]
    [string]$SourceRoot,

    [string]$ScratchRoot,

    [string]$Target = 'copilot',

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed',

    # Cap breaches in third-party agents are reported, not gated.
    [switch]$IncludeAdvisory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'SquadInstall.psm1') -Force

$installLog = $null

if ($PSCmdlet.ParameterSetName -ne 'Installed') {
    if (-not $ScratchRoot) {
        $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) "hve-squad-tier0-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    }

    if ($PSCmdlet.ParameterSetName -eq 'Source') {
        $SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
        Write-Host "Installing the manifest from $SourceRoot into $ScratchRoot" -ForegroundColor Cyan
        $install = Install-SquadPackage -Destination $ScratchRoot -SourceRoot $SourceRoot -Target $Target
        Write-Host "Overlaid squad-src/ from $SourceRoot" -ForegroundColor Cyan
    }
    else {
        Write-Host "Installing $Package#$Ref into $ScratchRoot" -ForegroundColor Cyan
        $install = Install-SquadPackage -Destination $ScratchRoot -Ref $Ref -Package $Package -Target $Target
    }

    $installLog = $install.InstallLog
    $PackageRoot = $install.Root
}

$PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path

# Only a release tag pins its own references; main ships the unpinned manifest by design.
$expectPinned = $PSCmdlet.ParameterSetName -eq 'Install' -and $Ref -match '^v\d+\.\d+\.\d+'

$containers = @(
    New-PesterContainer -Path (Join-Path $PSScriptRoot 'SquadPackage.Tests.ps1') -Data @{
        PackageRoot  = $PackageRoot
        InstallLog   = $installLog
        ExpectPinned = [bool]$expectPinned
    }
)

# Manifest coverage is a property of the working copy, not of an installed tree.
if ($PSCmdlet.ParameterSetName -eq 'Source') {
    $containers += New-PesterContainer -Path (Join-Path $PSScriptRoot 'Manifest.Tests.ps1') -Data @{
        SourceRoot = $SourceRoot
    }
}

$config = New-PesterConfiguration
$config.Run.Container = $containers
$config.Run.PassThru = $true
$config.Output.Verbosity = $Output
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $PSScriptRoot 'tier0-results.xml'

if (-not $IncludeAdvisory) {
    $config.Filter.ExcludeTag = 'Advisory'
}

# An empty case set is a legitimate state - a package with no skill references claims
# none - but Pester 6 treats it as an error by default.
try { $config.Run.FailOnNullOrEmptyForEach = $false } catch { }

$result = Invoke-Pester -Configuration $config

# A discovery failure yields zero tests and zero failures, which reads as success to
# anything checking only the failure count. Treat an empty run as a failure.
if ($result.FailedCount -gt 0 -or $result.TotalCount -eq 0 -or $result.Result -ne 'Passed') {
    if ($result.TotalCount -eq 0) {
        Write-Error 'No tests ran. Discovery failed, or the container was filtered to nothing.' -ErrorAction Continue
    }
    exit 1
}
