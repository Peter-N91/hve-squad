#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Self-checks the Tier 2 comparator against known-good and deliberately drifted pairs.
.DESCRIPTION
    Invokes no model and needs no secret, so it can gate every pull request alongside
    Tier 0. It proves the comparator moves when - and only when - something drifted.
.PARAMETER Output
    Pester output verbosity.
.EXAMPLE
    ./Invoke-Tier2Tests.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$config = New-PesterConfiguration
$config.Run.Container = New-PesterContainer -Path (Join-Path $PSScriptRoot 'Compare.Tests.ps1')
$config.Run.PassThru = $true
$config.Output.Verbosity = $Output
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $PSScriptRoot 'tier2-selfcheck-results.xml'

try { $config.Run.FailOnNullOrEmptyForEach = $false } catch { Write-Debug 'FailOnNullOrEmptyForEach is a Pester 6 setting; Pester 5 has no such property and needs no opt-out.' }

$result = Invoke-Pester -Configuration $config

# A discovery failure yields zero tests and zero failures, which reads as success to
# anything checking only the failure count. Treat an empty run as a failure.
if ($result.FailedCount -gt 0 -or $result.TotalCount -eq 0 -or $result.Result -ne 'Passed') {
    if ($result.TotalCount -eq 0) {
        Write-Error 'No tests ran. Discovery failed, or the container was filtered to nothing.' -ErrorAction Continue
    }
    exit 1
}
