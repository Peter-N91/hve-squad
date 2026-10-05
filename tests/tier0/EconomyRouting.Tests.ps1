#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Static text pins for the opt-in `routing=economy` mode (SQ-35 in
# tests/squad-behavior-contract.md) against the built package: every place that
# enumerates the routing modes names `economy`, the *Economy Mode* contract keeps its
# scope, floor, and one-escalation wording, and no floor exception or model id enters
# contract text. Resolver behaviour is covered by tests/tier1/ModelRouting.Tests.ps1.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:Model = Get-SquadPackageModel -PackageRoot $PackageRoot

    function Get-EconomyFileText {
        param([Parameter(Mandatory)][string]$Path)
        return (Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n"
    }

    function Get-EconomySection {
        <#
        .SYNOPSIS
            The body of one `## ` section, up to the next `## ` heading.
        #>
        param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Heading)
        return [regex]::Match($Text, "(?ms)^## $([regex]::Escape($Heading))\s*\n(?<body>.*?)(?=^## |\z)").Groups['body'].Value
    }

    $skill = $script:Model.SquadSkillRoot
    $script:Routing = Get-EconomyFileText (Join-Path $skill 'references/model-routing.md')
    $script:EconomySection = Get-EconomySection -Text $script:Routing -Heading 'Economy Mode'
    $script:OperatingProcedure = Get-EconomyFileText (Join-Path $skill 'references/operating-procedure.md')
    $script:Resolver = Get-EconomyFileText (Join-Path $skill 'scripts/Resolve-SquadModelRoute.ps1')
    $script:Coordinator = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-coordinator.agent.md')[0]
    $script:FederationCoordinator = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-federation-coordinator.agent.md')[0]
    $script:Roster = @($script:Model.Instructions | Where-Object Name -eq 'squad-roster.instructions.md')[0]
    $script:PromptText = @{}
    foreach ($name in 'squad.prompt.md', 'squad-federation.prompt.md') {
        $prompt = @($script:Model.Prompts | Where-Object Name -eq $name)[0]
        $script:PromptText[$name] = Get-EconomyFileText $prompt.Path
    }
}

Describe 'Every routing-mode enumeration names economy (SQ-35)' {
    It '<Name> offers routing=economy in its argument-hint' -ForEach @(
        @{ Name = 'squad.prompt.md' }
        @{ Name = 'squad-federation.prompt.md' }
    ) {
        $hint = [regex]::Match($script:PromptText[$Name], '(?m)^argument-hint:.*$').Value
        $hint | Should -Match ([regex]::Escape('[routing=off|ranked|economy|manual]'))
    }

    It 'the coordinator routing input and the federation pass-through list economy' {
        $script:Coordinator.Body | Should -Match ([regex]::Escape('`routing=off|ranked|economy|manual`'))
        $script:FederationCoordinator.Body | Should -Match ([regex]::Escape('`routing` (`off`, `ranked`, `economy`, or `manual`'))
    }

    It 'the roster instructions and the Route step read the persisted economy line' {
        $script:Roster.Body | Should -Match ([regex]::Escape('`Model routing: ranked|economy|manual`'))
        $script:OperatingProcedure | Should -Match ([regex]::Escape('`Model routing: ranked|economy|manual`'))
    }

    It 'the model-routing mode table carries an economy row persisted as Model routing: economy' {
        $script:Routing | Should -Match ([regex]::Escape('`routing=off|ranked|economy|manual`'))
        $script:Routing | Should -Match '(?m)^\| `economy` \|.*`Model routing: economy`'
    }

    It 'the resolver accepts economy as -Mode and as the recorded mode' {
        $script:Resolver | Should -Match ([regex]::Escape("[ValidateSet('ranked', 'economy', 'manual')]"))
        $script:Resolver | Should -Match ([regex]::Escape('(?<mode>off|ranked|economy|manual)'))
    }
}

Describe 'Economy Mode keeps its scope, floors, and one escalation (SQ-35)' {
    It 'has an Economy Mode section' {
        $script:EconomySection | Should -Not -BeNullOrEmpty
    }

    It 'picks the lowest-Blended id at fit 2 or better within the role''s own floor, implementation class only' {
        $script:EconomySection | Should -Match '`implementation`-class roles are ordered cost first'
        $script:EconomySection | Should -Match ([regex]::Escape('under the role''s own floor, keep the rows at fit 2 or better, and take the lowest **Blended** rate'))
        $script:EconomySection | Should -Match ([regex]::Escape('Every other role, the review class included'))
        $script:EconomySection | Should -Match ([regex]::Escape('the review that checks the cheaper work is never weakened'))
    }

    It 'never relaxes a floor through a routing input' {
        $script:EconomySection | Should -Match ([regex]::Escape('The pick never leaves *Consequence Floors*'))
        $script:EconomySection | Should -Match ([regex]::Escape('takes a `team.md` Model Tier edit, never a routing input'))
    }

    It 'escalates once to the ranked pick, written into the Model cell by the Scribe first, reset by the next re-rank' {
        $script:EconomySection | Should -Match ([regex]::Escape('After a `Fail` verdict, a Critical or High finding, or a `blocked` owner, re-dispatch that owner once on its ranked pick'))
        $script:EconomySection | Should -Match ([regex]::Escape('The coordinator hands the Scribe that id for the role''s `Model` cell before the re-dispatch'))
        $script:EconomySection | Should -Match ([regex]::Escape('the next turn''s re-rank resets the cell'))
        $script:Coordinator.Body | Should -Match ([regex]::Escape('re-dispatch that `implementation` owner once on its ranked pick, which the Scribe writes into its `Model` cell first'))
    }

    It 'leaves off as the no-policy default' {
        $script:Routing | Should -Match ([regex]::Escape('**No policy is the default and is byte-for-byte today''s behavior.**'))
        $script:Routing | Should -Match '(?m)^\| `off` +\| Nothing'
        $script:EconomySection | Should -Match ([regex]::Escape('It is opt-in; `off` stays the default.'))
    }

    It 'names no model id and no bounded lane in the Economy Mode section' {
        $script:EconomySection | Should -Not -Match '\b(gpt|claude|gemini|grok|mai|o\d)-[a-z0-9.]+'
        $script:EconomySection | Should -Not -Match '(?i)bounded|\blane\b'
    }
}

Describe 'No floor exception and a single ranking path' {
    It 'model-routing.md declares no floor exception' {
        $script:Routing | Should -Not -Match '(?i)declared exception'
        $script:Routing | Should -Not -Match 'Bounded Lane Pick'
        $script:Routing | Should -Match ([regex]::Escape('never widen it, substitute a different mode, or lower a floor the parent enforced.'))
    }

    It 'the resolver has no bounded switch or second pick field' {
        $script:Resolver | Should -Not -Match '(?i)\$Bounded|boundedPick|boundedRationale|CostFirst'
        $script:Resolver | Should -Match ([regex]::Escape("[ValidateSet('fit', 'cost')][string]`$Order = 'fit'"))
    }

    It 'the escalation target is the ranked pick' {
        $function = [regex]::Match($script:Resolver, '(?ms)^function Get-EscalationTarget \{.*?^\}').Value
        $function | Should -Match ([regex]::Escape('return $Ranked[0].Id'))
        $script:Resolver | Should -Match ([regex]::Escape('Get-EscalationTarget -Ranked $ranked'))
    }
}
