#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$SourceRoot,

    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force

    $script:RosterPath = Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-roster.instructions.md'
    $script:RosterCatalogPath = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/roster-catalog.md'
    $script:ProfilesPath = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/profiles-and-packs.md'
    $script:RoutingPath = Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-routing.instructions.md'
    $script:PromptPath = Join-Path $SourceRoot 'squad-src/.github/prompts/squad/squad.prompt.md'
    $script:FederationPath = Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-federation.instructions.md'
    $script:ReferenceRoot = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references'

    $script:RosterBody = Get-Content -LiteralPath $script:RosterPath -Raw
    $script:RosterCatalogBody = Get-Content -LiteralPath $script:RosterCatalogPath -Raw
    $script:ProfilesBody = Get-Content -LiteralPath $script:ProfilesPath -Raw
    $script:RoutingBody = Get-Content -LiteralPath $script:RoutingPath -Raw
    $script:PromptBody = Get-Content -LiteralPath $script:PromptPath -Raw
    $script:FederationBody = Get-Content -LiteralPath $script:FederationPath -Raw
    $script:EnglishDocs = Get-Content -LiteralPath (Join-Path $SourceRoot 'docs/usage.html') -Raw
    $script:FrenchDocs = Get-Content -LiteralPath (Join-Path $SourceRoot 'docs/fr/usage.html') -Raw

    $script:InvocationPath = @(
        Join-Path $PackageRoot '.agents/skills/squad/invocations/squad-run/SKILL.md'
        Join-Path $PackageRoot '.github/skills/squad/invocations/squad-run/SKILL.md'
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

Describe 'Registered pack consistency' -Tag 'Unit' {
    It 'keeps every pack aligned across roster, guidance, routing, entrypoints, package output, federation, and docs' {
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
        $castRoles = @(
            Get-MarkdownTableRows -Body $script:RosterCatalogBody -HeaderCell 'Role' |
                ForEach-Object { $_[1].Trim().Trim('`') } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
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
        $script:InvocationPath | Should -Not -BeNullOrEmpty
        $invocationBody = Get-Content -LiteralPath $script:InvocationPath -Raw
        $invocationChoices = [regex]::Match($invocationBody, '(?m)^\* \*\*pack\*\*.*?\((`[^)]+)\)').Groups[1].Value
        $generatedPacks = @([regex]::Matches($invocationChoices, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })

        @($promptPacks | Sort-Object) -join ',' | Should -BeExactly (@($packs.Keys | Sort-Object) -join ',')
        @($generatedPacks | Sort-Object) -join ',' | Should -BeExactly (@($packs.Keys | Sort-Object) -join ',')

        foreach ($name in $packs.Keys) {
            @($mirror[$name].roles | Sort-Object) -join ',' | Should -BeExactly (@($packs[$name].roles | Sort-Object) -join ',')
            @($mirror[$name].guidance | Sort-Object) -join ',' | Should -BeExactly (@($packs[$name].guidance | Sort-Object) -join ',')
            foreach ($role in $packs[$name].roles) {
                $castRoles | Should -Contain $role -Because "pack '$name' must use a registered cast role"
                if ($role -notin $profileRoles) {
                    $routingRoles | Should -Contain $role -Because "pack-exclusive role '$role' needs a routing row"
                }
            }
            foreach ($guidance in $packs[$name].guidance) {
                Test-Path -LiteralPath (Join-Path $script:ReferenceRoot $guidance) | Should -BeTrue
            }
            $script:FederationBody | Should -Match ([regex]::Escape($name))
            $script:EnglishDocs | Should -Match ([regex]::Escape($name))
            $script:FrenchDocs | Should -Match ([regex]::Escape($name))
        }
    }
}
