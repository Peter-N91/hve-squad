#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the Tier 1 state contract against a squad root, or self-checks the contract.
.DESCRIPTION
    Tier 1 asserts the state a squad run leaves on disk: the files Init seeds, the
    shape of state.json, dispatch history as proof a stage ran, and the consumption
    ledger's arithmetic. The runs that produce that state are nondeterministic; these
    assertions are not, because they read files.

    -SelfCheck generates a schema-correct fixture, asserts the contract passes on it,
    then mutates the fixture once per rule and asserts the contract FAILS each time. A
    suite that cannot fail is not evidence, so the mutations - not the fixture - are
    what make this trustworthy. It invokes no model and needs no secret.
.PARAMETER SquadRoot
    A squad root to assert: .copilot-tracking/squad/ or one sub-squad under members/.
.PARAMETER InitOnly
    Assert only the Init cases. Use for a squad that has been initialized but has not
    yet dispatched anything, where the turn and consumption cases have no subject.
.PARAMETER SelfCheck
    Verify the contract itself against a generated fixture and its mutations.
.PARAMETER Output
    Pester output verbosity.
.EXAMPLE
    ./Invoke-Tier1Tests.ps1 -SelfCheck
.EXAMPLE
    ./Invoke-Tier1Tests.ps1 -SquadRoot .copilot-tracking/squad
.NOTES
    See tests/squad-behavior-contract.md for the cases this implements.
#>
[CmdletBinding(DefaultParameterSetName = 'SelfCheck')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Assert')]
    [string]$SquadRoot,

    [Parameter(ParameterSetName = 'Assert')]
    [switch]$InitOnly,

    [Parameter(ParameterSetName = 'SelfCheck')]
    [switch]$SelfCheck,

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$config = New-PesterConfiguration
$config.Run.PassThru = $true
$config.Output.Verbosity = $Output
$config.TestResult.Enabled = $true

if ($PSCmdlet.ParameterSetName -eq 'Assert') {
    $SquadRoot = (Resolve-Path -LiteralPath $SquadRoot).Path

    $config.Run.Container = New-PesterContainer -Path (Join-Path $PSScriptRoot 'StateContract.Tests.ps1') -Data @{
        SquadRoot        = $SquadRoot
        ExpectDispatches = -not $InitOnly.IsPresent
    }
    $config.TestResult.OutputPath = Join-Path $PSScriptRoot 'tier1-results.xml'
}
else {
    $config.Run.Container = New-PesterContainer -Path (Join-Path $PSScriptRoot 'Assertions.Tests.ps1')
    $config.TestResult.OutputPath = Join-Path $PSScriptRoot 'tier1-selfcheck-results.xml'
}

# An empty case set is a legitimate state, but Pester 6 treats it as an error by default.
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
