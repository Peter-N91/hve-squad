#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    REFERENCE TEMPLATE — captures effective Azure Policy assignments (read-only) into a baseline file.
.DESCRIPTION
    Documentation-only reference template shipped under the azure-scaffold skill. It never runs from
    the hve-squad package. Copy it to scripts/Get-PolicyBaseline.ps1 in your consumer repo. It reads
    the effective Azure Policy assignments for a subscription — including management-group inheritance
    — and writes them, sorted for stable diffs, to a JSON baseline the IaC planner consumes as real
    governance constraints. It is strictly read-only and never mutates Azure Policy.
.PARAMETER SubscriptionId
    The Azure subscription ID to capture policy assignments for.
.PARAMETER OutputPath
    Destination JSON file for the baseline.
.EXAMPLE
    ./scripts/Get-PolicyBaseline.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000
.EXAMPLE
    ./scripts/Get-PolicyBaseline.ps1 -SubscriptionId $env:AZURE_SUBSCRIPTION_ID -OutputPath agent-output/_baseline/policy-baseline.json
.NOTES
    Requires the Azure CLI (az), authenticated with at least Reader on the subscription. Provided by
    the devcontainer.template.json in this skill.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = 'agent-output/_baseline/policy-baseline.json'
)

$ErrorActionPreference = 'Stop'

#region Functions

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

#endregion Functions

#region Main Execution

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if (-not (Test-CommandExists -Name 'az')) {
            throw "Required CLI 'az' is not installed or not on PATH."
        }

        az account set --subscription $SubscriptionId

        # Read-only: list assignments effective at the subscription, including ancestor (management
        # group) assignments. --disable-scope-strict-match includes inherited assignments.
        $AssignmentsJson = az policy assignment list `
            --scope "/subscriptions/$SubscriptionId" `
            --disable-scope-strict-match `
            --output json

        $Assignments = $AssignmentsJson | ConvertFrom-Json

        # Project a stable, minimal shape and sort by id so the baseline diffs cleanly across runs.
        $Baseline = [ordered]@{
            subscriptionId = $SubscriptionId
            capturedUtc    = (Get-Date).ToUniversalTime().ToString('o')
            assignments    = @(
                $Assignments |
                    Sort-Object -Property id |
                    ForEach-Object {
                        [ordered]@{
                            id                 = $_.id
                            name               = $_.name
                            displayName        = $_.displayName
                            scope              = $_.scope
                            policyDefinitionId = $_.policyDefinitionId
                            enforcementMode    = $_.enforcementMode
                        }
                    }
            )
        }

        $OutputDir = Split-Path -Path $OutputPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($OutputDir) -and -not (Test-Path -Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }

        $Baseline | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Host "✅ Captured $($Baseline.assignments.Count) policy assignments to $OutputPath" -ForegroundColor Green
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Get-PolicyBaseline failed: $($_.Exception.Message)"
        exit 1
    }
}

#endregion Main Execution
