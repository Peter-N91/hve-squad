#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# GATE-29..GATE-38 pin the task-fit council selection and waiver contract text
# against the built package. They assert prompt content, not model behavior.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:Model = Get-SquadPackageModel -PackageRoot $PackageRoot

    function Get-CouncilReference {
        param([Parameter(Mandatory)][string]$Name)
        $path = Join-Path $script:Model.SquadSkillRoot "references/$Name"
        return Get-Content -LiteralPath $path -Raw
    }

    $script:Council = @($script:Model.Instructions | Where-Object Name -eq 'squad-council.instructions.md')[0]
    $script:Roster = @($script:Model.Instructions | Where-Object Name -eq 'squad-roster.instructions.md')[0]
    $script:Routing = @($script:Model.Instructions | Where-Object Name -eq 'squad-routing.instructions.md')[0]
    $script:Autopilot = @($script:Model.Instructions | Where-Object Name -eq 'squad-autopilot.instructions.md')[0]
    $script:Autonomous = @($script:Model.Instructions | Where-Object Name -eq 'squad-autonomous.instructions.md')[0]
    $script:Watch = @($script:Model.Instructions | Where-Object Name -eq 'squad-watch-mode.instructions.md')[0]
    $script:Coordinator = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-coordinator.agent.md')[0]
    $script:FederationCoordinator = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-federation-coordinator.agent.md')[0]
    $script:ModernizationPlanner = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-modernization-planner.agent.md')[0]
    $script:OperatingProcedure = Get-CouncilReference -Name 'operating-procedure.md'
    $script:FederationReference = Get-CouncilReference -Name 'federation.md'
    $script:ScribeDecisionSchema = Get-CouncilReference -Name 'scribe-cold-gates-and-verdicts.md'
    $script:ScribeProcedure = Get-CouncilReference -Name 'scribe-procedure.md'
    $script:ScribeFederation = Get-CouncilReference -Name 'scribe-cold-federation.md'
}

Describe 'Council selection contract pins (GATE-29..GATE-38)' {
    It 'GATE-29 offers a task-fit council at single-squad Init and explains its purpose' {
        $script:Roster.Body | Should -Match ([regex]::Escape('At Init, Promotion, and Expansion, always propose a council tailored to the request and discovery'))
        $script:OperatingProcedure | Should -Match ([regex]::Escape('Explain that the council validates the plan before implementation'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('ask the user to accept, adjust, or decline'))
    }

    It 'GATE-30 restores the two-domain automatic trigger while allowing explicit focused councils' {
        $script:Council.Body | Should -Match ([regex]::Escape('at least two non-RAI council domains'))
        $script:Council.Body | Should -Match ([regex]::Escape('any responsible-AI concern'))
        $script:Council.Body | Should -Match ([regex]::Escape('An explicit user request for council or validation may use a single review role'))
        $script:ModernizationPlanner.Body | Should -Not -Match 'architect.{0,30}security.{0,30}cost-manager.{0,30}product-owner'
    }

    It 'GATE-31 records considered roles and adds only selected missing roster roles' {
        $script:ScribeDecisionSchema | Should -Match ([regex]::Escape('* Not Proposed:'))
        $script:ScribeDecisionSchema | Should -Match ([regex]::Escape('<role> — <reason its review lens is not material>'))
        $script:ScribeDecisionSchema | Should -Match ([regex]::Escape('add only selected roles absent from the roster'))
    }

    It 'GATE-32 records declines as council waivers without waiving independent gates' {
        $script:Council.Body | Should -Match ([regex]::Escape('Council Waived: waived by user'))
        $script:Routing.Body | Should -Match ([regex]::Escape('or a matching `Council Waived: waived by user` is recorded'))
        $script:Council.Body | Should -Match ([regex]::Escape('does not waive an independent Risk Gate'))
        $script:ScribeDecisionSchema | Should -Match ([regex]::Escape('A decline records `Council Waiver: waived by user`'))
    }

    It 'GATE-33 records promotion selection or waiver before the relocated tree is committed' {
        $script:FederationCoordinator.Body | Should -Match ([regex]::Escape('the Scribe records the answer and applies accepted additions before relocation'))
        $script:ScribeFederation | Should -Match ([regex]::Escape('record `Council Waiver: waived by user`'))
        $script:ScribeFederation | Should -Match ([regex]::Escape('Not Proposed` rationales'))
    }

    It 'GATE-34 scopes federation Init and Expansion council offers to each sub-squad' {
        $script:FederationReference | Should -Match ([regex]::Escape('For each sub-squad, always propose a task-fit council'))
        $script:FederationReference | Should -Match ([regex]::Escape('including a per-sub-squad task-fit council proposal'))
        $script:ScribeDecisionSchema | Should -Match ([regex]::Escape('store this entry in the newly seeded sub-squad''s `decisions.md`'))
    }

    It 'GATE-35 separates interactive offers from roster-based automated selections' {
        $script:Council.Body | Should -Match ([regex]::Escape('In `mode=autopilot`, `mode=autonomous`, and Watch Mode'))
        $script:Council.Body | Should -Match ([regex]::Escape('select the task-fit subset from roles already on the accepted active roster'))
        $script:Council.Body | Should -Match ([regex]::Escape('Selection Mode: interactive-accepted | autopilot-roster | autonomous-roster | watch-roster'))
        $script:Council.Body | Should -Match ([regex]::Escape('Dispatch exactly the selected council roles in parallel'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('without asking'))
    }

    It 'GATE-36 applies a decline to the same roster and topic scope without overriding Risk Gates' {
        $script:ScribeProcedure | Should -Match ([regex]::Escape('Do not repeat a decline for the same roster role set and topic/scope'))
        $script:Council.Body | Should -Match ([regex]::Escape('A new topic or materially changed scope requires a new offer'))
        $script:Council.Body | Should -Match ([regex]::Escape('An independent Risk Gate'))
    }

    It 'GATE-37 lets Watch Mode select roster roles per new topic and escalates only for a missing lens' {
        $script:Watch.Body | Should -Match ([regex]::Escape('Each issue is a new topic'))
        $script:Watch.Body | Should -Match ([regex]::Escape('selects the task-fit subset from roles already on the accepted sub-squad roster'))
        $script:Watch.Body | Should -Match ([regex]::Escape('if a needed lens has no available role on the roster'))
        $script:Watch.Body | Should -Not -Match 'reuses only a Scribe-recorded, user-accepted membership for the same unchanged topic'
    }

    It 'GATE-38 keeps autonomous and autopilot on the accepted roster and honors a waiver in re-validation' {
        $script:Autopilot.Body | Should -Match ([regex]::Escape('do not ask for another membership approval'))
        $script:Autopilot.Body | Should -Match ([regex]::Escape('If the user declines the missing-role offer, record a council waiver and continue'))
        $script:Autonomous.Body | Should -Match ([regex]::Escape('do not ask for a new membership approval'))
        $script:Autonomous.Body | Should -Match ([regex]::Escape('A waiver for the same topic and scope skips council re-validation'))
    }
}
