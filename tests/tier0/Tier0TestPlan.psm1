# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-Tier0TestPlan {
    <#
    .SYNOPSIS
        Selects registered Tier 0 containers without loading Pester or installing a package.
    .PARAMETER Mode
        Source includes repository contracts; Installed includes only delivered-package cases.
    .PARAMETER Scope
        Selects all cases or one of the complementary release selections.
    .PARAMETER Shard
        Selects one isolated CI partition, or the complete local selection.
    .OUTPUTS
        Container descriptors with Name, Directory, Scope and Shard.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Source', 'Installed')]
        [string]$Mode,

        [ValidateSet('All', 'Repository', 'Package')]
        [string]$Scope = 'All',

        [ValidateSet('All', 'Contracts', 'Handoff', 'Lifecycle', 'Coordinator')]
        [string]$Shard = 'All'
    )

    if ($Mode -eq 'Installed' -and $Scope -eq 'Repository') {
        throw 'Repository-only tests require -SourceRoot.'
    }

    # Keep the ten-minute handoff file separate from lifecycle and coordinator work.
    # Each CI job gets its own installed tree, process environment and TestDrive.
    $groups = @(
        @{
            Scope = 'Package'; Shard = 'Contracts'; Directory = 'tier0'
            Files = @(
                'SquadPackage.Tests.ps1'
                'ConnectorRoleModes.Tests.ps1'
                'ScribeHandoffPipelining.Tests.ps1'
                'CouncilMembership.Tests.ps1'
                'SetSquadCostPreflight.Tests.ps1'
                'SquadUsage.Tests.ps1'
                'Invoke-SquadPowerShellProbe.Tests.ps1'
                'WriteSquadVerdict.Tests.ps1'
                'BoundedLane.Tests.ps1'
                'SquadCoach.Tests.ps1'
                'ConnectorDispatch.Tests.ps1'
            )
        }
        @{
            Scope = 'Package'; Shard = 'Handoff'; Directory = 'tier0'
            Files = @('WriteSquadHandoff.Tests.ps1')
        }
        @{
            Scope = 'Package'; Shard = 'Lifecycle'; Directory = 'tier0'
            Files = @(
                'ScribeInitConvergence.Tests.ps1'
                'ConsumptionRatesSeeder.Tests.ps1'
                'PromoteSquadFederation.Tests.ps1'
                'InitializeSquadFederation.Tests.ps1'
                'ExpandSquadRoster.Tests.ps1'
            )
        }
        @{
            Scope = 'Package'; Shard = 'Coordinator'; Directory = 'tier0'
            Files = @(
                'EconomyRouting.Tests.ps1'
                'SetSquadModelRouting.Tests.ps1'
                'GetSquadDispatchBrief.Tests.ps1'
            )
        }
        @{
            Scope = 'Repository'; Shard = 'Contracts'; Directory = 'tier0'
            Files = @(
                'PackRegistry.Tests.ps1'
                'Manifest.Tests.ps1'
                'PrValidation.Tests.ps1'
                'Tier0Runner.Tests.ps1'
                'Build-SquadPlugin.Tests.ps1'
                'Performance.Tests.ps1'
                'Packaging.Tests.ps1'
                'WatchMode.Tests.ps1'
                'HotFileBudget.Tests.ps1'
                'ConnectorContract.Tests.ps1'
                'SquadBuilder.Tests.ps1'
            )
        }
        @{
            Scope = 'Repository'; Shard = 'Contracts'; Directory = 'lib'
            Files = @('SquadInstall.Tests.ps1')
        }
        @{
            Scope = 'Repository'; Shard = 'Coordinator'; Directory = 'tier0'
            Files = @('CoordinatorRuntime.Tests.ps1', 'AgentDiscovery.Tests.ps1')
        }
    )

    foreach ($group in $groups) {
        if ($Mode -eq 'Installed' -and $group.Scope -eq 'Repository') { continue }
        if ($Scope -ne 'All' -and $group.Scope -ne $Scope) { continue }
        if ($Shard -ne 'All' -and $group.Shard -ne $Shard) { continue }
        foreach ($file in $group.Files) {
            [pscustomobject]@{
                Name      = $file
                Directory = $group.Directory
                Scope     = $group.Scope
                Shard     = $group.Shard
            }
        }
    }
}

Export-ModuleMember -Function Get-Tier0TestPlan
