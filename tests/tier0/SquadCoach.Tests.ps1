#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $model = Get-SquadPackageModel -PackageRoot $PackageRoot
    $script:CoachAgent = @($model.SquadAgents | Where-Object Name -eq 'squad-coach.agent.md')
    $script:CoachPrompt = @($model.Prompts | Where-Object Name -eq 'squad-coach.prompt.md')
    $script:SquadPrompt = @($model.Prompts | Where-Object Name -eq 'squad.prompt.md')
}

Describe 'Squad Coach entrypoint and packaging' {
    It 'delivers one user-invocable Coach and one bound prompt' {
        $script:CoachAgent | Should -HaveCount 1
        $script:CoachPrompt | Should -HaveCount 1
        $script:CoachAgent[0].Meta['name'] | Should -BeExactly 'Squad Coach'
        $script:CoachAgent[0].Meta['user-invocable'] | Should -BeExactly 'true'
        $script:CoachAgent[0].Meta['disable-model-invocation'] | Should -BeExactly 'true'
        $script:CoachPrompt[0].Meta['agent'] | Should -BeExactly 'Squad Coach'
    }

    It 'surfaces the Coach once on the fresh path without interrupting existing squads' {
        $script:SquadPrompt | Should -HaveCount 1
        $script:SquadPrompt[0].Body | Should -Match 'mention the advisory Squad Coach once'
        $script:SquadPrompt[0].Body | Should -Match 'never repeat the hint after either state file exists'
    }
}

Describe 'Squad Coach behavior contract' {
    BeforeAll {
        $script:Body = $script:CoachAgent[0].Body
    }

    It 'works before initialization and adapts to existing state' {
        $script:Body | Should -Match 'No squad state is required'
        $script:Body | Should -Match 'neither `team\.md` nor `federation\.md`'
        $script:Body | Should -Match 'When `federation\.md` exists'
        $script:Body | Should -Match 'When only `team\.md` exists'
    }

    It 'derives current recommendations from shipped sources instead of a copied feature list' {
        $script:Body | Should -Match 'installed package is the source of truth'
        $script:Body | Should -Match 'references/00-index\.md'
        $script:Body | Should -Match 'references/profiles-and-packs\.md'
        $script:Body | Should -Match 'enumerate the installed prompts or invocation skills'
        $script:Body | Should -Match 'Never invent a command, flag, profile, pack, role, model, or capability'
    }

    It 'covers single squad, federation, migration, and demand-specific recommendations' {
        $script:Body | Should -Match 'simplest sufficient setup'
        $script:Body | Should -Match 'single squad'
        $script:Body | Should -Match 'federation'
        $script:Body | Should -Match '/squad-federation promote'
        $script:Body | Should -Match 'per-member profile'
    }

    It 'returns preparation and invocation material beginners can act on' {
        $script:Body | Should -Match 'Essential inputs'
        $script:Body | Should -Match 'Optional inputs'
        $script:Body | Should -Match 'copy-ready'
        $script:Body | Should -Match 'Copilot CLI'
        $script:Body | Should -Match 'Copilot App'
        $script:Body | Should -Match 'VS Code'
        $script:Body | Should -Match 'installation'
        $script:Body | Should -Match 'progress'
        $script:Body | Should -Match 'resume'
    }

    It 'is advisory-only and never asks for secrets' {
        $script:Body | Should -Match 'Advisory-only boundary'
        $script:Body | Should -Match 'Never initialize, dispatch, migrate, write, edit, or delete'
        $script:Body | Should -Match 'Even when the user asks you to perform delivery work'
        $script:Body | Should -Match 'Never ask the user to paste secrets'
    }
}
