#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Pins the task-fit council and council-extension contract (issue #133) against the
# built package. GATE-29..GATE-37 in tests/squad-behavior-contract.md are this file's
# contract IDs. This is a static text pin only: it proves the contract reads the way it
# must, never that a model turn obeys it.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:Model = Get-SquadPackageModel -PackageRoot $PackageRoot

    function Get-SquadReferenceBody {
        <#
        .SYNOPSIS
            Reads a squad skill reference file's raw text from the built package.
        .PARAMETER Name
            File name under references/, for example 'gates-and-modes.md'.
        #>
        param([Parameter(Mandatory)][string]$Name)
        $path = Join-Path $script:Model.SquadSkillRoot "references/$Name"
        return Get-Content -LiteralPath $path -Raw
    }

    function Get-InstructionBody {
        <#
        .SYNOPSIS
            Returns the body of one delivered squad instruction file.
        .PARAMETER Name
            Instruction file name, for example 'squad-council.instructions.md'.
        #>
        param([Parameter(Mandatory)][string]$Name)
        return @($script:Model.Instructions | Where-Object Name -eq $Name)[0].Body
    }

    function Get-AgentBody {
        <#
        .SYNOPSIS
            Returns the body of one delivered squad agent file.
        .PARAMETER Name
            Agent file name, for example 'squad-coordinator.agent.md'.
        #>
        param([Parameter(Mandatory)][string]$Name)
        return @($script:Model.SquadAgents | Where-Object Name -eq $Name)[0].Body
    }

    $script:Council = Get-InstructionBody -Name 'squad-council.instructions.md'
    $script:Autopilot = Get-InstructionBody -Name 'squad-autopilot.instructions.md'
    $script:Autonomous = Get-InstructionBody -Name 'squad-autonomous.instructions.md'
    $script:WatchMode = Get-InstructionBody -Name 'squad-watch-mode.instructions.md'
    $script:Routing = Get-InstructionBody -Name 'squad-routing.instructions.md'
    $script:Roster = Get-InstructionBody -Name 'squad-roster.instructions.md'
    $script:Coordinator = Get-AgentBody -Name 'squad-coordinator.agent.md'
    $script:ModernizationPlanner = Get-AgentBody -Name 'squad-modernization-planner.agent.md'
    $script:GatesAndModes = Get-SquadReferenceBody -Name 'gates-and-modes.md'
    $script:OperatingProcedure = Get-SquadReferenceBody -Name 'operating-procedure.md'
    $script:ScribeVerdicts = Get-SquadReferenceBody -Name 'scribe-cold-gates-and-verdicts.md'
    $script:ScribeInit = Get-SquadReferenceBody -Name 'scribe-cold-init-and-seeding.md'
    $script:SeedTemplates = Get-SquadReferenceBody -Name 'seed-templates.md'
}

Describe 'Task-fit council and council extension wording pins (GATE-29..GATE-37)' {

    Context 'GATE-29: membership is task-fit, mapped lens by lens, and auditable' {
        It 'the council instructions state there is no fixed quorum and map every lens to its role' {
            $script:Council | Should -Match ([regex]::Escape('The council has no fixed quorum. It is **task-fit**'))
            foreach ($row in @('| Architecture | `architect`', '| Security     | `security`', '| Cost         | `cost-manager`', '| Product-fit  | `product-owner`', '| RAI          | `rai`')) {
                $script:Council | Should -Match ([regex]::Escape($row))
            }
            $script:Council | Should -Match ([regex]::Escape('A council may therefore be two of the four classic roles, all five, or `rai` alone.'))
        }

        It 'the verdict records the lenses left out and carries rows for dispatched roles only' {
            $script:Council | Should -Match ([regex]::Escape('* Council Members Not Proposed: <role — reason; one per lens left out, or none>'))
            $script:Council | Should -Match ([regex]::Escape('The Findings by Role table carries one row per dispatched role only'))
            $script:ScribeVerdicts | Should -Match ([regex]::Escape('* Council Members Not Proposed: cost-manager — no billable change'))
            $script:GatesAndModes | Should -Match ([regex]::Escape('recording each lens left out under `Council Members Not Proposed` with its reason. There is no fixed quorum.'))
        }
    }

    Context 'GATE-30: the automatic trigger is unchanged; only membership is sized to the work' {
        It 'keeps two or more domains or any RAI concern, and lets an explicit request ask for one role' {
            $script:Council | Should -Match ([regex]::Escape('crosses two or more council-member domains, or raises any responsible-AI concern'))
            $script:Council | Should -Match ([regex]::Escape('The automatic triggers stay at two or more domains or any RAI concern; what is sized to the work is the membership, not the trigger.'))
            $script:Council | Should -Match ([regex]::Escape('An explicit request may still ask for a council of any size, including a single role.'))
            $script:Autopilot | Should -Match ([regex]::Escape('When the work crosses two or more council-member domains (architecture, security, cost, product-fit) or raises any RAI concern'))
        }
    }

    Context 'GATE-31: Init proposes missing council roles inside the existing confirmation' {
        It 'the Init procedure offers a council extension with no extra question' {
            $script:OperatingProcedure | Should -Match ([regex]::Escape('as a suggested **council extension** in the same confirmation, each with its reason. This adds no question'))
            $script:Council | Should -Match ([regex]::Escape('* **Init (every mode).**'))
            $script:Roster | Should -Match ([regex]::Escape('and for a missing council role (a **council extension**)'))
        }
    }

    Context 'GATE-32: interactive mode proposes the council and persists an accepted role' {
        It 'the confirm step offers accept, adjust, or decline and the Scribe appends an accepted role' {
            $script:Council | Should -Match ([regex]::Escape('The user accepts, adjusts, or declines.'))
            $script:Council | Should -Match ([regex]::Escape('On acceptance the Squad Scribe appends the role to `team.md` and its routing rows to `routing.md`, and the role stays on the roster for later councils.'))
        }
    }

    Context 'GATE-33: autopilot and autonomous add no new human stop' {
        It 'autopilot selects from the roster without asking and stops only for a missing role' {
            $script:Autopilot | Should -Match ([regex]::Escape('Select the task-fit roles from the roster without asking and record the selection'))
            $script:Autopilot | Should -Match ([regex]::Escape('this adds no Human Gate. Stop only when a needed role is absent from the roster'))
            $script:Council | Should -Match ([regex]::Escape('* **`mode=autopilot` and `mode=autonomous`.** No new question.'))
        }

        It 'autonomous selects from the roster and a waived council ends the loop for the turn' {
            $script:Autonomous | Should -Match ([regex]::Escape('It selects the roles without asking and stops only when a needed role is absent from the roster'))
            $script:Autonomous | Should -Match ([regex]::Escape('a waived council ends the loop for the turn'))
        }
    }

    Context 'GATE-34: Watch Mode never adds a role and never waives a council' {
        It 'the unattended disposition selects from the roster and escalates a missing role' {
            $script:WatchMode | Should -Match ([regex]::Escape('| Council membership (task-fit roles, council extension) | **Select from the roster.**'))
            $script:WatchMode | Should -Match ([regex]::Escape('the run never adds the role and never waives the council.'))
            $script:Council | Should -Match ([regex]::Escape('An unattended run never adds a role and never waives a council.'))
        }
    }

    Context 'GATE-35: a decline waives the council without clearing other gates' {
        It 'a decline records a Council Waiver that satisfies the Implementation Gate only' {
            $script:Council | Should -Match ([regex]::Escape('**A decline waives the council; it does not block the work.**'))
            $script:Council | Should -Match ([regex]::Escape('`## Council Waiver <timestamp> <topic-id>`'))
            $script:Council | Should -Match ([regex]::Escape('It never clears a Risk Gate or an Impactful-Action Gate'))
            $script:Council | Should -Match ([regex]::Escape('A waived topic is not re-offered unless its scope changes.'))
        }

        It 'every Implementation Gate statement accepts a waiver in place of a verdict' {
            $script:Council | Should -Match ([regex]::Escape('* A `## Council Waiver` for the topic, recorded on the user''s decline'))
            $script:Routing | Should -Match ([regex]::Escape('A non-`Stop` Council Verdict, or a user''s `## Council Waiver`, exists for the topic'))
            $script:GatesAndModes | Should -Match ([regex]::Escape('a non-`Stop` Council Verdict, or a user''s `## Council Waiver`, for the topic'))
            $script:Coordinator | Should -Match ([regex]::Escape('a non-`Stop` Council Verdict or a user''s Council Waiver'))
        }
    }

    Context 'GATE-36: the council row survives the roster filter' {
        It 'is seeded on every roster' {
            $script:Routing | Should -Match ([regex]::Escape('The council row is the one exception and is seeded on every roster'))
            $script:ScribeInit | Should -Match ([regex]::Escape('except the council row, which is seeded on every roster because its membership is task-fit'))
            $script:SeedTemplates | Should -Match ([regex]::Escape('except the council row, which every roster keeps'))
        }
    }

    Context 'GATE-37: dispatch discipline holds and the fixed quorum does not resurface' {
        It 'the council still never invents a finding or substitutes an agent' {
            $script:Council | Should -Match ([regex]::Escape('never synthesizes a Council Verdict from its own reasoning to cover a lens it did not dispatch'))
            $script:Council | Should -Match ([regex]::Escape('never substitutes a non-mapped agent for an absent council member'))
            $script:Coordinator | Should -Match ([regex]::Escape('Dispatch in one parallel batch only the task-fit roles the work needs'))
        }

        It 'no fixed four-role council remains in the contract text' {
            $script:Council | Should -Not -Match ([regex]::Escape('A council quorum is the full default membership'))
            $script:Council | Should -Not -Match ([regex]::Escape('The default council is four roles dispatched in parallel'))
            $script:Coordinator | Should -Not -Match ([regex]::Escape('Dispatch `architect`, `security`, `cost-manager`, `product-owner` in one parallel batch'))
            $script:Autonomous | Should -Not -Match ([regex]::Escape('dispatches the default council'))
            $script:GatesAndModes | Should -Not -Match ([regex]::Escape('dispatches the default council in a single parallel batch'))
            $script:ModernizationPlanner | Should -Not -Match ([regex]::Escape('council review (`architect`, `security`, `cost-manager`, `product-owner`)'))
        }
    }
}
