#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$SourceRoot
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force

    $script:RosterPath = Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-roster.instructions.md'
    $script:RosterCatalogPath = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/roster-catalog.md'
    $script:ProfilesPath = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/profiles-and-packs.md'
    $script:RoutingPath = Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-routing.instructions.md'
    $script:PromptPath = Join-Path $SourceRoot 'squad-src/.github/prompts/squad/squad.prompt.md'
    $script:CoordinatorPath = Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-coordinator.agent.md'
    $script:FederationPath = Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-federation.instructions.md'
    $script:FoundryBlueprintPath = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/foundry-blueprint.md'
    $script:ReferenceRoot = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references'

    $script:RosterBody = Get-Content -LiteralPath $script:RosterPath -Raw
    $script:RosterCatalogBody = Get-Content -LiteralPath $script:RosterCatalogPath -Raw
    $script:ProfilesBody = Get-Content -LiteralPath $script:ProfilesPath -Raw
    $script:RoutingBody = Get-Content -LiteralPath $script:RoutingPath -Raw
    $script:PromptBody = Get-Content -LiteralPath $script:PromptPath -Raw
    $script:CoordinatorBody = Get-Content -LiteralPath $script:CoordinatorPath -Raw
    $script:FederationBody = Get-Content -LiteralPath $script:FederationPath -Raw
    $script:FoundryBlueprintBody = Get-Content -LiteralPath $script:FoundryBlueprintPath -Raw
    $script:EnglishDocs = Get-Content -LiteralPath (Join-Path $SourceRoot 'docs/usage.html') -Raw
    $script:FrenchDocs = Get-Content -LiteralPath (Join-Path $SourceRoot 'docs/fr/usage.html') -Raw

    function Get-MarkdownSectionBody {
        param(
            [Parameter(Mandatory)][string]$Body,
            [Parameter(Mandatory)][string]$Heading
        )

        $match = [regex]::Match(
            $Body,
            "(?ms)^#{1,6}\s+$([regex]::Escape($Heading))\s*\r?\n(?<Body>.*?)(?=^#{1,6}\s|\z)"
        )
        if (-not $match.Success) { throw "Markdown section '$Heading' was not found." }
        $match.Groups['Body'].Value
    }
}

Describe 'Registered pack consistency' -Tag 'Unit' {
    It 'keeps every pack aligned across roster, guidance, routing, prompt, federation, and docs' {
        $rosterRows = @(Get-MarkdownTableRows -Body $script:RosterBody -HeaderCell 'Pack')
        $profileRows = @(Get-MarkdownTableRows -Body $script:ProfilesBody -HeaderCell 'Pack')
        $rosterRows | Should -Not -BeNullOrEmpty
        $profileRows | Should -HaveCount $rosterRows.Count

        $packs = @{}
        foreach ($cells in $rosterRows) {
            $name = $cells[1].Trim().Trim('`')
            $packs[$name] = @{
                roles = @($cells[2] -split ',' | ForEach-Object { $_.Trim().Trim('`') } | Where-Object { $_ })
                guidance = @([regex]::Matches($cells[3], '[a-z0-9-]+\.md') | ForEach-Object { $_.Value } | Sort-Object -Unique)
            }

        }

        $mirror = @{}
        foreach ($cells in $profileRows) {
            $name = $cells[1].Trim().Trim('`')
            $mirror[$name] = @{
                roles = @($cells[2] -split ',' | ForEach-Object { $_.Trim().Trim('`') } | Where-Object { $_ })
                guidance = @([regex]::Matches($cells[3], '[a-z0-9-]+\.md') | ForEach-Object { $_.Value } | Sort-Object -Unique)
            }
        }

        @($mirror.Keys | Sort-Object) -join ',' | Should -BeExactly (@($packs.Keys | Sort-Object) -join ',')
        $castRoles = @(Get-SquadCastCatalogRoles -Body $script:RosterCatalogBody)
        $castRows = @(Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Cast Catalog') `
                -HeaderCell 'Role')
        $castPrimary = @{}
        foreach ($cells in $castRows) {
            $role = $cells[1].Trim().Trim('`')
            if ($role) { $castPrimary[$role] = $cells[2].Trim().Trim('`') }
        }
        $profileRoles = @(
            Get-MarkdownTableRows -Body $script:RosterBody -HeaderCell 'Profile' |
                ForEach-Object { $_[2] -split ',' } |
                ForEach-Object { $_.Trim().Trim('`') } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
        $routingRoles = @(
            Get-MarkdownTableRows -Body $script:RoutingBody -HeaderCell 'Pattern / Keyword' |
                ForEach-Object { $_[2] -split ',' } |
                ForEach-Object { $_.Trim().Trim('`') } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )

        $promptPacks = [regex]::Match($script:PromptBody, '\[pack=([^\]]+)\]').Groups[1].Value -split '\|'
        @($promptPacks | Sort-Object) -join ',' | Should -BeExactly (@($packs.Keys | Sort-Object) -join ',')
        $coordinatorPackLine = [regex]::Match(
            $script:CoordinatorBody,
            '(?m)^\* \(Optional\) `pack=`[^\r\n]+\r?$'
        ).Value
        $coordinatorPackLine | Should -Not -BeNullOrEmpty
        $coordinatorPacks = @(
            [regex]::Matches($coordinatorPackLine, '`([^`]+)`') |
                ForEach-Object { $_.Groups[1].Value } |
                Where-Object { $_ -ne 'pack=' } |
                Sort-Object -Unique
        )
        $coordinatorPacks -join ',' | Should -BeExactly (@($packs.Keys | Sort-Object) -join ',')

        $discoveryRows = @(Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:ProfilesBody -Heading 'Pack Discovery') `
                -HeaderCell 'Pack')
        $discoveryPacks = @(
            $discoveryRows |
                ForEach-Object { $_[1].Trim().Trim('`') } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
        $discoveryPacks -join ',' | Should -BeExactly (@($packs.Keys | Sort-Object) -join ',')

        foreach ($name in $packs.Keys) {
            @($mirror[$name].roles | Sort-Object) -join ',' | Should -BeExactly (@($packs[$name].roles | Sort-Object) -join ',')
            @($mirror[$name].guidance | Sort-Object) -join ',' | Should -BeExactly (@($packs[$name].guidance | Sort-Object) -join ',')
            foreach ($role in $packs[$name].roles) {
                $castRoles | Should -Contain $role -Because "pack '$name' must use a registered cast role"
                $castPrimary[$role] | Should -Not -BeNullOrEmpty -Because "pack role '$role' must resolve to a Primary"
                $castPrimary[$role] | Should -Not -BeExactly '—' -Because "pack role '$role' must be dispatchable"
                if ($role -notin $profileRoles) {
                    $routingRoles | Should -Contain $role -Because "pack-exclusive role '$role' needs a routing row"
                }
            }
            foreach ($guidance in $packs[$name].guidance) {
                Test-Path -LiteralPath (Join-Path $script:ReferenceRoot $guidance) | Should -BeTrue
            }
            $packCell = '<td><code>{0}</code></td>' -f [regex]::Escape($name)
            $script:EnglishDocs | Should -MatchExactly $packCell
            $script:FrenchDocs | Should -MatchExactly $packCell
            $script:FederationBody | Should -MatchExactly ('`{0}`' -f [regex]::Escape($name))
        }
    }

    It 'keeps the Foundry blueprint skill table aligned with Registered External Cast' {
        $blueprintSkills = @(
            Get-MarkdownTableRows -Body $script:FoundryBlueprintBody -HeaderCell 'Skill' |
                ForEach-Object { $_[1].Trim().Trim('`') } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
        $blueprintSkills -join ',' | Should -BeExactly 'azure-aigateway,caira,microsoft-foundry,use-ai-gateway'

        $registeredSkills = @(
            Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast') `
                -HeaderCell 'Role' |
                Where-Object { $_[4].Trim() -eq 'skill' } |
                ForEach-Object { $_[3].Trim().Trim('`') } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
        foreach ($skill in $blueprintSkills) {
            $registeredSkills | Should -Contain $skill
        }
    }
}
