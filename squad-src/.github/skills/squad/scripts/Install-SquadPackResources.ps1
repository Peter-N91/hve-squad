#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Installs missing registered skills for confirmed squad packs.
.DESCRIPTION
    Runs only registry-approved install commands after explicit confirmation.
    It never installs prerequisites, authenticates accounts, grants tenant consent,
    or runs a skill's setup workflow.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [string]$RepoRoot = (Get-Location).ProviderPath,
    [Parameter(Mandatory)][string[]]$Pack,
    [string[]]$Resource = @(),
    [string[]]$AvailableSkill = @(),
    [string]$ReceiptPath,
    [switch]$Confirmed
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force

function ConvertTo-SquadPackInstallSteps {
    param([Parameter(Mandatory)][string]$InstallOrEntry)
    $apm = [regex]::Match($InstallOrEntry, '(?:^|`)apm install (?<source>[^\s`]+)(?: --target copilot)?(?=`|;|$)')
    if ($apm.Success) {
        return ,([pscustomobject]@{
                executable = 'apm'
                arguments = @('install', $apm.Groups['source'].Value, '--target', 'copilot')
                display = "apm install $($apm.Groups['source'].Value) --target copilot"
            })
    }
    $marketplace = [regex]::Match($InstallOrEntry, '(?:^|`)copilot plugin marketplace add (?<source>[^\s`]+)(?=`|,|$)')
    $plugin = [regex]::Match($InstallOrEntry, '(?:^|`)copilot plugin install (?<source>[^\s`]+)(?=`|,|$)')
    if ($marketplace.Success -or $plugin.Success) {
        if (-not $marketplace.Success -or -not $plugin.Success) { throw 'Plugin pack resources require marketplace-add and plugin-install steps.' }
        return @(
            [pscustomobject]@{
                executable = 'copilot'
                arguments = @('plugin', 'marketplace', 'add', $marketplace.Groups['source'].Value)
                display = "copilot plugin marketplace add $($marketplace.Groups['source'].Value)"
            }
            [pscustomobject]@{
                executable = 'copilot'
                arguments = @('plugin', 'install', $plugin.Groups['source'].Value)
                display = "copilot plugin install $($plugin.Groups['source'].Value)"
            }
        )
    }
    $npx = [regex]::Match($InstallOrEntry, '(?:^|`)npx skills add (?<source>[^\s`]+)(?=`|,|$)')
    if ($npx.Success) {
        return ,([pscustomobject]@{
                executable = 'npx'
                arguments = @('skills', 'add', $npx.Groups['source'].Value)
                display = "npx skills add $($npx.Groups['source'].Value)"
            })
    }
    throw 'Registered pack resource has no supported install command.'
}

function Resolve-SquadPackReceiptPath {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$Path)
    $destination = [IO.Path]::GetFullPath($Path, $Repository)
    $relative = [IO.Path]::GetRelativePath($Repository, $destination)
    if ($relative -eq '..' -or $relative -match '^\.\.[\\/]' -or [IO.Path]::IsPathRooted($relative)) {
        throw 'Pack resource receipt must stay inside the consumer repository.'
    }
    $destination
}

if ($MyInvocation.InvocationName -ne '.') {
    $records = [Collections.Generic.List[object]]::new()
    $failed = $false
    try {
        if (-not $Confirmed) { throw 'Pack resource installation requires explicit confirmation.' }
        $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
        $receiptDestination = if ($ReceiptPath) { Resolve-SquadPackReceiptPath -Repository $RepoRoot -Path $ReceiptPath } else { '' }
        $data = Get-SquadInitData -RepoRoot $RepoRoot
        $inventory = @(Get-SquadPackResourceInventory -InitData $data -Pack $Pack -RepoRoot $RepoRoot -AvailableSkill $AvailableSkill)
        if ($Resource.Count) {
            foreach ($name in $Resource) {
                if ($name -notin $inventory.resource) { throw "Resource '$name' is not registered for the selected packs." }
            }
            $inventory = @($inventory | Where-Object { $_.resource -in $Resource })
        }
        Push-Location $RepoRoot
        try {
            foreach ($entry in $inventory) {
                if ($entry.installed) {
                    $records.Add([ordered]@{ resource = $entry.resource; status = 'available'; commands = @(); availableNow = $true; installedOnDisk = $entry.installedOnDisk })
                    continue
                }
                if ($entry.installedOnDisk) {
                    $records.Add([ordered]@{ resource = $entry.resource; status = 'installed'; commands = @(); availableNow = $false; installedOnDisk = $true })
                    continue
                }
                $steps = @(ConvertTo-SquadPackInstallSteps -InstallOrEntry $entry.installOrEntry)
                if (-not $PSCmdlet.ShouldProcess($entry.resource, ($steps.display -join '; '))) {
                    $records.Add([ordered]@{ resource = $entry.resource; status = 'planned'; commands = @($steps.display); availableNow = $false; installedOnDisk = $false })
                    continue
                }
                $resourceFailed = $false
                foreach ($step in $steps) {
                    if (-not (Get-Command $step.executable -ErrorAction SilentlyContinue)) {
                        $records.Add([ordered]@{ resource = $entry.resource; status = 'failed'; commands = @($steps.display); availableNow = $false; installedOnDisk = $false; error = "Missing installer: $($step.executable)" })
                        $resourceFailed = $true
                        break
                    }
                    $arguments = @($step.arguments)
                    & $step.executable @arguments
                    if ($LASTEXITCODE -ne 0) {
                        $records.Add([ordered]@{ resource = $entry.resource; status = 'failed'; commands = @($steps.display); availableNow = $false; installedOnDisk = $false; error = "$($step.display) exited $LASTEXITCODE" })
                        $resourceFailed = $true
                        break
                    }
                }
                if ($resourceFailed) {
                    $failed = $true
                    continue
                }
                $records.Add([ordered]@{ resource = $entry.resource; status = 'installed'; commands = @($steps.display); availableNow = $false; installedOnDisk = $true })
            }
        }
        finally { Pop-Location }

        $refreshed = @(Get-SquadPackResourceInventory -InitData $data -Pack $Pack -RepoRoot $RepoRoot -AvailableSkill $AvailableSkill)
        foreach ($record in $records) {
            $match = @($refreshed | Where-Object resource -ceq $record.resource)
            if ($match.Count -eq 1) {
                $record.availableNow = [bool]$match[0].installed
                $record.installedOnDisk = [bool]$match[0].installedOnDisk
            }
        }
        $restartRequired = @($records | Where-Object {
                $_.status -in @('installed', 'failed')
            }).Count -gt 0
        $receipt = [ordered]@{
            schemaVersion = 1
            status = $(if ($failed) { 'FAIL' } elseif (@($records | Where-Object status -eq 'planned').Count) { 'PLANNED' } else { 'PASS' })
            packs = $Pack
            resources = $records.ToArray()
            restartRequired = $restartRequired
            prerequisitesInstalled = $false
        }
        if ($receiptDestination -and $receipt.status -ne 'PLANNED') {
            $destination = Write-SquadTransportJson -Path $receiptDestination `
                -SquadRoot (Join-Path $RepoRoot '.copilot-tracking/squad') -Value $receipt
            $receipt.receiptPath = $destination
        }
        $receipt | ConvertTo-Json -Depth 10 -Compress
        if ($failed) { exit 1 }
        exit 0
    }
    catch {
        $receipt = [ordered]@{
            schemaVersion = 1
            status = 'FAIL'
            packs = $Pack
            resources = $records.ToArray()
            restartRequired = @($records | Where-Object {
                    $_.status -in @('installed', 'failed')
                }).Count -gt 0
            prerequisitesInstalled = $false
            error = $_.Exception.Message
        }
        if ($ReceiptPath) {
            try {
                $receiptDestination = Resolve-SquadPackReceiptPath -Repository $RepoRoot -Path $ReceiptPath
                $destination = Write-SquadTransportJson -Path $receiptDestination `
                    -SquadRoot (Join-Path $RepoRoot '.copilot-tracking/squad') -Value $receipt
                $receipt.receiptPath = $destination
            }
            catch {
                $receipt.receiptError = $_.Exception.Message
            }
        }
        $receipt | ConvertTo-Json -Depth 10 -Compress
        exit 1
    }
}
