#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Static pins for the fixed `tools:` lists (RTE-42, RTE-43, RTE-45). They prove the shipped
# frontmatter and boundary text read the way the contract says; they cannot prove what a host
# loads or that a model obeys the prose-only shell rule.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:Model = Get-SquadPackageModel -PackageRoot $PackageRoot

    function Get-SquadAgent {
        param([Parameter(Mandatory)][string]$Name)
        @($script:Model.SquadAgents | Where-Object Name -eq $Name)[0]
    }

    $script:Coordinator = Get-SquadAgent -Name 'squad-coordinator.agent.md'
    $script:Scribe = Get-SquadAgent -Name 'squad-scribe.agent.md'
    $script:Floor = @($script:Model.Instructions | Where-Object Name -eq 'squad-floor.instructions.md')[0]
    $script:CoordinatorTools = @($script:Coordinator.Meta['tools'])
    $script:ScribeTools = @($script:Scribe.Meta['tools'])
    $script:EditTools = @('edit', 'create', 'apply_patch', 'str_replace_editor', 'editFiles', 'createFile')
    $script:ShellTools = @('execute', 'powershell', 'bash')
}

Describe 'Coordinator tool boundary and budget fail-closed (RTE-42, RTE-43)' {
    It 'the coordinator tools list is exactly the reviewed set, so any change is deliberate' {
        $expected = @('read', 'search', 'view', 'glob', 'grep', 'agent', 'task', 'skill', 'execute', 'powershell', 'bash', 'read_agent')
        $script:CoordinatorTools.Count | Should -Be $expected.Count
        @($script:CoordinatorTools | Sort-Object) | Should -Be @($expected | Sort-Object)
    }

    It 'the coordinator lists skill because its charter activates the squad skill' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('activate only the `squad` skill'))
        $script:CoordinatorTools | Should -Contain 'skill'
    }

    It 'the coordinator tools list grants no file-editing tool and no wildcard' {
        foreach ($tool in @($script:EditTools) + '*') {
            $script:CoordinatorTools | Should -Not -Contain $tool
        }
    }

    It 'the coordinator holds read_agent for the owner-finish barrier and lists no question tool' {
        $script:CoordinatorTools | Should -Contain 'read_agent'
        $script:Coordinator.Body | Should -Match 'read_agent.*wait: true'
        foreach ($tool in 'ask_user', 'vscode/askQuestions') {
            $script:CoordinatorTools | Should -Not -Contain $tool
        }
        $script:Coordinator.Body | Should -Not -Match '(?i)ask_user|askQuestions'
    }

    It 'the coordinator and the floor justify the shell and say the no-write rule is prose-enforced' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('The shell in `tools:` runs only the squad''s scripts, read-only inspection, and procedure-assigned steps, never a write to squad state, deliverables, or source (prose-enforced).'))
        $script:Floor.Body | Should -Match ([regex]::Escape('The coordinator never uses the shell to create or modify squad state files or any role''s deliverables or source.'))
        $script:Floor.Body | Should -Match ([regex]::Escape('A `tools:` list cannot limit a shell to these commands, so this rule is enforced by instruction only.'))
    }

    It 'every script the floor lets the coordinator shell run ships in the squad skill' {
        foreach ($helper in 'Set-SquadCostPreflight.ps1', 'Resolve-SquadModelRoute.ps1', 'Measure-SquadLedger.ps1') {
            $script:Floor.Body | Should -Match ([regex]::Escape("``$helper"))
            Test-Path -LiteralPath (Join-Path $script:Model.SquadSkillRoot "scripts/$helper") | Should -BeTrue
        }
    }

    It 'no text says the coordinator runs the hand-off script; the Scribe runs it' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('the Scribe writes an ordinary payload by running `scripts/Write-SquadHandoff.ps1`'))
        foreach ($body in $script:Coordinator.Body, $script:Floor.Body) {
            $body | Should -Not -Match '(?i)coordinator(-run| runs?)[^.]{0,40}Write-SquadHandoff'
            $body | Should -Not -Match ([regex]::Escape('Running `scripts/Write-SquadHandoff.ps1` is that script run'))
        }
    }

    It 'the coordinator and the floor both state the budget fail-closed rule' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('A host budget notice (e.g. `<session_limits_status>`) never authorizes inline work, skipped stages, self-review, or a skipped Scribe or ledger hand-off; Cost Preflight with a user `cost-ceiling` is the only admission gate.'))
        $script:Floor.Body | Should -Match ([regex]::Escape('never authorizes inline role work, skipped or collapsed stages, self-review, or a skipped Scribe or ledger hand-off.'))
        $script:Floor.Body | Should -Match ([regex]::Escape('run the stages in order and hand each to the Scribe as it returns, so the recorded state shows which stages ran, and report the risk once if the limit may not cover them.'))
        $script:Floor.Body | Should -Match ([regex]::Escape('Cost Preflight with a user `cost-ceiling` remains the only admission gate.'))
        $script:Floor.Body | Should -Not -Match ([regex]::Escape('stop before dispatch and report the shortfall'))
    }
}

Describe 'Role charters keep the tools they need (RTE-45)' {
    It 'the Scribe declares exactly the reviewed tools list' {
        $expected = @('read', 'search', 'edit', 'execute', 'view', 'glob', 'grep', 'create', 'apply_patch', 'powershell', 'bash', 'skill', 'memory', 'vscode/memory')
        $script:ScribeTools.Count | Should -Be $expected.Count
        @($script:ScribeTools | Sort-Object) | Should -Be @($expected | Sort-Object)
        $script:ScribeTools | Should -Not -Contain '*'
    }

    It 'the Scribe keeps a shell because it runs the hand-off script, and keeps its edit tools' {
        $script:Scribe.Body | Should -Match ([regex]::Escape('run `scripts/Write-SquadHandoff.ps1`'))
        foreach ($tool in @($script:ShellTools) + 'edit', 'create', 'apply_patch') {
            $script:ScribeTools | Should -Contain $tool
        }
    }

    It '<Agent> declares no tools list, so it keeps the consumer''s MCP servers' -ForEach @(
        @{ Agent = 'squad-lead.agent.md' }
        @{ Agent = 'squad-reviewer.agent.md' }
        @{ Agent = 'squad-implementor.agent.md' }
        @{ Agent = 'squad-technical-writer.agent.md' }
        @{ Agent = 'squad-researcher.agent.md' }
    ) {
        $agent = Get-SquadAgent -Name $Agent
        $agent | Should -Not -BeNullOrEmpty
        $agent.Meta.Contains('tools') | Should -BeFalse -Because "$Agent relies on MCP servers named by the consumer's own configuration"
    }

    It 'only the coordinator and the Scribe declare a tools list' {
        $restricted = @($script:Model.SquadAgents | Where-Object { $_.Meta.Contains('tools') } | ForEach-Object Name | Sort-Object)
        $restricted | Should -Be @('squad-coordinator.agent.md', 'squad-scribe.agent.md')
    }
}
