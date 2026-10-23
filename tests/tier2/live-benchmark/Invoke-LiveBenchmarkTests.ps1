#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the live benchmark harness's offline self-checks. Calls no model and needs no secret.
.DESCRIPTION
    AI cost: none; even launch/accounting cases use fake CLIs. Local subprocess tests can take minutes.
    Covers fixture materialisation, scheduling, per-level task validity (reference passes,
    every mutant killed, baseline fails), the scorer on synthetic workspaces, the judge
    anonymise/shuffle/de-anonymise round trip, and report generation. Needs Python with
    pytest on PATH. Deliberately not part of Tier 0 or the Tier 2 self-check.
    Export/report/study suites run separately through Invoke-BenchmarkEvidenceTests.ps1
    on PowerShell 7.5+ and in the Tier 2 comparator CI self-check.
.PARAMETER PesterPath
    Optional path to a Pester 5 module manifest to import instead of the installed one.
.PARAMETER ProgressPath
    Optional atomic progress snapshot for the wizard's periodic observer.
.EXAMPLE
    ./Invoke-LiveBenchmarkTests.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed',
    [string]$PesterPath,
    [string]$ProgressPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$pytestCheck = & python -m pytest --version 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "python -m pytest is required for the live benchmark offline self-tests. Install it with 'python -m pip install pytest' or create and activate a virtual environment, then rerun this script."
}
if ($PesterPath) { Import-Module $PesterPath -Force } else { Import-Module Pester -MinimumVersion 5.0 -Force }

$TestFiles = @(
    (Join-Path $PSScriptRoot 'LiveBenchmark.Tests.ps1'),
    (Join-Path $PSScriptRoot 'EfficiencyBenchmark.Tests.ps1'),
    (Join-Path $PSScriptRoot 'Start-EfficiencyWizard.Tests.ps1')
)
if ($ProgressPath) {
    Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1')
    $Completed = 0
    Write-EfficiencyProgress -Path $ProgressPath -Stage offline -Completed 0 -Total $TestFiles.Count
    $Failed = $false
    foreach ($TestFile in $TestFiles) {
        $config = New-PesterConfiguration
        $config.Run.Container = New-PesterContainer -Path $TestFile
        $config.Run.PassThru = $true
        $config.Output.Verbosity = $Output
        $result = Invoke-Pester -Configuration $config
        $Failed = $Failed -or $result.FailedCount -gt 0 -or $result.TotalCount -eq 0 -or $result.Result -ne 'Passed'
        $Completed++
        Write-EfficiencyProgress -Path $ProgressPath -Stage offline -Completed $Completed -Total $TestFiles.Count -Status $(if ($Completed -lt $TestFiles.Count) { 'running' } elseif ($Failed) { 'failed' } else { 'finished' })
    }
    if ($Failed) { exit 1 }
}
else {
    $config = New-PesterConfiguration
    $config.Run.Container = New-PesterContainer -Path $TestFiles
    $config.Run.PassThru = $true
    $config.Output.Verbosity = $Output
    $result = Invoke-Pester -Configuration $config
    # A discovery failure yields zero tests and zero failures; treat an empty run as a failure.
    if ($result.FailedCount -gt 0 -or $result.TotalCount -eq 0 -or $result.Result -ne 'Passed') { exit 1 }
}
