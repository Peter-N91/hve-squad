#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    REFERENCE TEMPLATE — configures Azure OIDC (workload-identity federation) for GitHub Actions.
.DESCRIPTION
    Documentation-only reference template shipped under the azure-scaffold skill. It never runs from
    the hve-squad package. Copy it to scripts/Setup-AzureOidc.ps1 in your consumer repo, then run it
    once to create an Entra app registration, OIDC federated credentials (for the main branch, pull
    requests, and each environment), assign least-privilege RBAC, and populate the GitHub secrets the
    deploy workflows consume. No client secret is ever created or stored — federation replaces it.

    The script is idempotent: re-running it reuses the existing app registration and only adds what is
    missing. It never echoes secret material; the client, tenant, and subscription IDs it sets are
    non-secret identifiers required by azure/login@v2.
.PARAMETER GitHubRepo
    The GitHub repository in owner/repo form that the federated credentials authorize.
.PARAMETER SubscriptionId
    The target Azure subscription ID. Contributor is assigned at this scope.
.PARAMETER ManagementGroupId
    Optional management-group ID. When supplied, Reader is assigned at the management-group scope.
.PARAMETER AppName
    Display name for the Entra app registration.
.PARAMETER Environments
    GitHub deployment environments to federate (one federated credential each).
.PARAMETER Branch
    The branch whose pushes may deploy.
.EXAMPLE
    ./scripts/Setup-AzureOidc.ps1 -GitHubRepo contoso/my-infra -SubscriptionId 00000000-0000-0000-0000-000000000000
.NOTES
    Requires the Azure CLI (az) and GitHub CLI (gh), both authenticated. Provided by the
    devcontainer.template.json in this skill. Run once per repository; safe to re-run.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GitHubRepo,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ManagementGroupId,

    [Parameter(Mandatory = $false)]
    [string]$AppName = "gha-oidc-$($GitHubRepo -replace '[/]', '-')",

    [Parameter(Mandatory = $false)]
    [string[]]$Environments = @('dev', 'staging', 'prod'),

    [Parameter(Mandatory = $false)]
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'

#region Functions

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Add-FederatedCredential {
    # Adds one federated credential if a credential with the same name is not already present.
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Subject
    )

    $existing = az ad app federated-credential list --id $AppId --query "[?name=='$Name'] | length(@)" --output tsv
    if ($existing -eq '0') {
        $parameters = @{
            name      = $Name
            issuer    = 'https://token.actions.githubusercontent.com'
            subject   = $Subject
            audiences = @('api://AzureADTokenExchange')
        } | ConvertTo-Json -Compress

        az ad app federated-credential create --id $AppId --parameters $parameters | Out-Null
        Write-Host "  + federated credential: $Name" -ForegroundColor Green
    }
    else {
        Write-Host "  = federated credential already present: $Name" -ForegroundColor DarkGray
    }
}

#endregion Functions

#region Main Execution

if ($MyInvocation.InvocationName -ne '.') {
    try {
        foreach ($tool in @('az', 'gh')) {
            if (-not (Test-CommandExists -Name $tool)) {
                throw "Required CLI '$tool' is not installed or not on PATH."
            }
        }

        Write-Host "Configuring Azure OIDC for $GitHubRepo" -ForegroundColor Cyan
        az account set --subscription $SubscriptionId
        $TenantId = az account show --query tenantId --output tsv

        # 1. App registration (idempotent: reuse by display name when it already exists).
        $AppId = az ad app list --display-name $AppName --query "[0].appId" --output tsv
        if ([string]::IsNullOrWhiteSpace($AppId)) {
            $AppId = az ad app create --display-name $AppName --query appId --output tsv
            Write-Host "Created app registration: $AppName" -ForegroundColor Green
        }
        else {
            Write-Host "Reusing app registration: $AppName" -ForegroundColor DarkGray
        }

        # 2. Service principal for the app (idempotent).
        $SpExists = az ad sp list --filter "appId eq '$AppId'" --query "length(@)" --output tsv
        if ($SpExists -eq '0') {
            az ad sp create --id $AppId | Out-Null
            Write-Host "Created service principal." -ForegroundColor Green
        }

        # 3. Federated credentials: branch, pull requests, and one per environment.
        Write-Host "Federated credentials:" -ForegroundColor Cyan
        Add-FederatedCredential -AppId $AppId -Name "branch-$Branch" -Subject "repo:${GitHubRepo}:ref:refs/heads/$Branch"
        Add-FederatedCredential -AppId $AppId -Name 'pull-request' -Subject "repo:${GitHubRepo}:pull_request"
        foreach ($env in $Environments) {
            Add-FederatedCredential -AppId $AppId -Name "env-$env" -Subject "repo:${GitHubRepo}:environment:$env"
        }

        # 4. Least-privilege RBAC: Contributor at the subscription, optional Reader at the MG.
        Write-Host "Role assignments:" -ForegroundColor Cyan
        az role assignment create --assignee $AppId --role 'Contributor' --scope "/subscriptions/$SubscriptionId" --only-show-errors | Out-Null
        Write-Host "  + Contributor on subscription $SubscriptionId" -ForegroundColor Green
        if (-not [string]::IsNullOrWhiteSpace($ManagementGroupId)) {
            az role assignment create --assignee $AppId --role 'Reader' --scope "/providers/Microsoft.Management/managementGroups/$ManagementGroupId" --only-show-errors | Out-Null
            Write-Host "  + Reader on management group $ManagementGroupId" -ForegroundColor Green
        }

        # 5. GitHub repository secrets the deploy workflows consume (non-secret identifiers; no client secret exists).
        Write-Host "GitHub secrets on ${GitHubRepo}:" -ForegroundColor Cyan
        gh secret set AZURE_CLIENT_ID --body $AppId --repo $GitHubRepo
        gh secret set AZURE_TENANT_ID --body $TenantId --repo $GitHubRepo
        gh secret set AZURE_SUBSCRIPTION_ID --body $SubscriptionId --repo $GitHubRepo
        Write-Host "  + AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID" -ForegroundColor Green

        Write-Host "✅ OIDC configuration complete. No client secret was created." -ForegroundColor Green
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Setup-AzureOidc failed: $($_.Exception.Message)"
        exit 1
    }
}

#endregion Main Execution
