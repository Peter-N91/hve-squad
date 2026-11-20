#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Writes and verifies one ordinary handoff using the same frozen payload.
.DESCRIPTION
    AI cost: none. Reuses the existing writer and read-only turn checker.
    Writer refusals retain their exit codes. A failed completion check exits 3
    without replaying or rolling back a handoff already persisted by the writer.
.PARAMETER RepoRoot
    Absolute consumer repository containing the selected squad.
.PARAMETER SquadRoot
    Selected single-squad or member root within RepoRoot.
.PARAMETER PayloadPath
    Actual handoff JSON, outside protected squad state. No captures are created.
.EXAMPLE
    pwsh -NoProfile -File Complete-SquadHandoff.ps1 -RepoRoot C:\repo -SquadRoot C:\repo\.copilot-tracking\squad -PayloadPath C:\repo\handoff.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SquadRoot,
    [Parameter(Mandatory)][string]$PayloadPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force

if ($MyInvocation.InvocationName -ne '.') {
    $Snapshot = $null
    try {
        $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
        $SquadRoot = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $SquadRoot
        $Payload = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $PayloadPath).ProviderPath)
        $Snapshot = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($Snapshot, $Payload, [Text.UTF8Encoding]::new($false))
        $Written = Invoke-SquadLocalScript -Name 'Write-SquadHandoff.ps1' -Arguments @(
            '-SquadRoot', $SquadRoot, '-PayloadPath', $Snapshot, '-Quiet')
        if ($Written.stderr) { [Console]::Error.Write($Written.stderr) }
        if ($Written.exitCode -ne 0) { exit $Written.exitCode }
        $Receipt = $Written.stdout | ConvertFrom-Json -AsHashtable
        if ($Receipt -isnot [Collections.IDictionary] -or $Receipt['status'] -ne 'written' -or
            $Receipt['ledgerCheck'] -ne 'PASS' -or
            ($Receipt['turn'] -isnot [int] -and $Receipt['turn'] -isnot [long])) {
            throw 'Writer did not return a passing handoff receipt; persisted state is not completion proof.'
        }
        $Checked = Invoke-SquadLocalScript -Name 'Test-SquadTurnCompletion.ps1' -Arguments @(
            '-RepoRoot', $RepoRoot, '-SquadRoot', $SquadRoot, '-ProofPath', $Snapshot,
            '-ExpectedTurn', [string]$Receipt.turn)
        if ($Checked.stderr) { [Console]::Error.Write($Checked.stderr) }
        if ($Checked.exitCode -ne 0) { throw 'Completion check failed; retain the written handoff and resolve its evidence without replay.' }
        $Proof = $Checked.stdout | ConvertFrom-Json -AsHashtable
        if ($Proof -isnot [Collections.IDictionary] -or $Proof['status'] -ne 'ok' -or
            $Proof['verified'] -isnot [bool] -or $Proof['verified'] -ne $true -or $Proof['ledgerCheck'] -ne 'PASS' -or
            $Proof['dispatchEntries'] -ne $Receipt.dispatchEntries) {
            throw 'Completion proof does not match the writer receipt.'
        }
        foreach ($Warning in $Proof['warnings']) { [Console]::Error.WriteLine($Warning) }
        $Receipt['verified'] = $true
        $Receipt | ConvertTo-Json -Depth 5 -Compress
    }
    catch {
        [Console]::Error.WriteLine("Complete-SquadHandoff: $($_.Exception.Message)")
        exit 3
    }
    finally {
        if ($Snapshot) { [IO.File]::Delete($Snapshot) }
    }
}
