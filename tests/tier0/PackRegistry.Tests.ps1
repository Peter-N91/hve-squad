#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
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
    $script:CoordinatorInitPath = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/coordinator-init.md'
    $script:FederationPath = Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-federation.instructions.md'
    $script:FoundryBlueprintPath = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/foundry-blueprint.md'
    $script:FabricBlueprintPath = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/fabric-blueprint.md'
    $script:ReferenceRoot = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references'

    $script:RosterBody = Get-Content -LiteralPath $script:RosterPath -Raw
    $script:RosterCatalogBody = Get-Content -LiteralPath $script:RosterCatalogPath -Raw
    $script:ProfilesBody = Get-Content -LiteralPath $script:ProfilesPath -Raw
    $script:RoutingBody = Get-Content -LiteralPath $script:RoutingPath -Raw
    $script:PromptBody = Get-Content -LiteralPath $script:PromptPath -Raw
    $script:CoordinatorBody = Get-Content -LiteralPath $script:CoordinatorPath -Raw
    $script:CoordinatorInitBody = Get-Content -LiteralPath $script:CoordinatorInitPath -Raw
    $script:FederationBody = Get-Content -LiteralPath $script:FederationPath -Raw
    $script:FoundryBlueprintBody = Get-Content -LiteralPath $script:FoundryBlueprintPath -Raw
    $script:FabricBlueprintBody = Get-Content -LiteralPath $script:FabricBlueprintPath -Raw
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
        $script:CoordinatorBody | Should -Match 'references/coordinator-init\.md'
        $script:CoordinatorInitBody | Should -Match 'profiles,\s+packs'
        $script:CoordinatorInitBody | Should -Match 'Offer packs'

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
            $packCell = '<td(?:\s+[^>]*)?><code>{0}</code></td>' -f [regex]::Escape($name)
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
        $foundrySkills = @('appinsights-instrumentation', 'azure-aigateway', 'caira', 'foundry-iq', 'microsoft-foundry', 'use-ai-gateway')
        $blueprintSkills -join ',' | Should -BeExactly ($foundrySkills -join ',')

        $registeredSkills = @(
            Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast') `
                -HeaderCell 'Role' |
                Where-Object { $_[4].Trim() -eq 'skill' } |
                ForEach-Object { $_[3].Trim().Trim('`') } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
        foreach ($skill in $foundrySkills) {
            $registeredSkills | Should -Contain $skill
            $blueprintSkills | Should -Contain $skill
        }
    }

    It 'maps every Foundry and Fabric pack skill to one registered opt-in skill' {
        $packRows = @(
            Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered Pack Skills') `
                -HeaderCell 'Pack'
        )
        $mapped = @{}
        foreach ($cells in $packRows) {
            $pack = $cells[1].Trim().Trim('`')
            if (-not $mapped.ContainsKey($pack)) { $mapped[$pack] = @() }
            $mapped[$pack] += $cells[2].Trim().Trim('`')
        }
        $expectedFoundry = @('appinsights-instrumentation', 'azure-aigateway', 'caira', 'foundry-iq', 'microsoft-foundry', 'use-ai-gateway')
        $expectedFabric = @(
            Get-MarkdownTableRows -Body $script:FabricBlueprintBody -HeaderCell 'Skill' |
                ForEach-Object { $_[1].Trim().Trim('`') } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
        @($mapped.foundry | Sort-Object) -join ',' | Should -BeExactly (@($expectedFoundry | Sort-Object) -join ',')
        @($mapped.fabric | Sort-Object) -join ',' | Should -BeExactly (@($expectedFabric | Sort-Object) -join ',')
        $profileSkillRows = @(Get-MarkdownTableRows -Body $script:ProfilesBody -HeaderCell 'Resource pack')
        $profileMapped = @{}
        foreach ($cells in $profileSkillRows) {
            $profileMapped[$cells[1].Trim().Trim('`')] = @($cells[2] -split ',' | ForEach-Object { $_.Trim().Trim('`') } | Where-Object { $_ })
        }
        @($profileMapped.foundry | Sort-Object) -join ',' | Should -BeExactly (@($expectedFoundry | Sort-Object) -join ',')
        @($profileMapped.fabric | Sort-Object) -join ',' | Should -BeExactly (@($expectedFabric | Sort-Object) -join ',')

        $registered = @(
            Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast') `
                -HeaderCell 'Role'
        )
        foreach ($resource in @($expectedFoundry + $expectedFabric)) {
            $rows = @($registered | Where-Object { $_[3].Trim().Trim('`') -eq $resource })
            $rows | Should -Not -BeNullOrEmpty
            @($rows | Where-Object { $_[2].Trim() -eq 'opt-in' -and $_[4].Trim() -eq 'skill' }).Count |
                Should -Be $rows.Count
        }
        $script:CoordinatorInitBody | Should -Match 'Pack Resource Preflight'
        $script:CoordinatorInitBody | Should -Match 'displaying an install command is not installation'
        $script:FederationBody | Should -Match 'No unattended pack installs'
    }

    It 'keeps origin class inline inside the ten-column registry' {
        $registered = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast'
        $rows = @(Get-MarkdownTableRows -Body $registered -HeaderCell 'Role')
        $rows | Should -Not -BeNullOrEmpty
        $allowed = 'vendor-official|github-marketplace|community'
        foreach ($cells in $rows) {
            $cells.Count | Should -Be 12 -Because 'a ten-column row keeps the leading and trailing empty split cells'
            $cells[5].Trim() | Should -MatchExactly ('^`[^`]+` \(`({0})`\), `[^`]+`$' -f $allowed)
        }
        $script:RosterCatalogBody | Should -Match '#### Origin Preference'
        $script:RosterCatalogBody | Should -Not -Match 'Azure/ai-gateway'
        $script:RosterCatalogBody | Should -Not -Match '(?<!hve-core/)\.github/instructions/licensing-posture\.instructions\.md'
        $script:RosterCatalogBody | Should -Match '\.github/instructions/hve-core/licensing-posture\.instructions\.md'
        $gateway = @($rows | Where-Object { $_[3].Trim() -eq '`use-ai-gateway`' })
        $gateway | Should -HaveCount 1
        $gateway[0][5].Trim() | Should -BeExactly '`Azure/aigateway` (`vendor-official`), `skills/use-ai-gateway/SKILL.md`'
        $gateway[0][6].Trim() | Should -BeExactly '`copilot plugin marketplace add Azure/aigateway`, then `copilot plugin install ai-gateway@azure`'
        $gateway[0][10].Trim() | Should -BeExactly '2026-11-04'
    }

    It 'defers Azure same-job replacement without moving the blocklist' {
        $registered = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast'
        $rows = @(Get-MarkdownTableRows -Body $registered -HeaderCell 'Role')
        $resources = @($rows | ForEach-Object { $_[3].Trim().Trim('`') })
        $resources | Should -Contain 'azure-deployment-preflight'
        $resources | Should -Not -Contain 'azure-validate'
        $resources | Should -Not -Contain 'azure-enterprise-infra-planner'
        $blocklist = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'External Cast Blocklist'
        $blocklist | Should -Not -Match 'azure-deployment-preflight'
        $blocklist | Should -Not -Match 'azure-validate'
        $blocklist | Should -Not -Match 'azure-enterprise-infra-planner'
        $script:RosterCatalogBody | Should -Match '#### Deferred official candidates'
        $script:RosterCatalogBody | Should -Match '33200af2901bce6da01ce37498aa2b68e0c43f7c'
    }
}

Describe 'Power Platform and M365 official selection' -Tag 'Unit' {
    BeforeAll {
        function Resolve-OfficialRoleAgent {
            param(
                [Parameter(Mandatory)][string]$Cue,
                [Parameter(Mandatory)][string]$Primary,
                [Parameter(Mandatory)][string]$Request,
                [string[]]$Installed = @()
            )

            $clauses = @(
                $Cue -split ';' |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ -match '→' }
            )
            foreach ($clause in $clauses) {
                $parts = @($clause -split '→', 2)
                $condition = $parts[0].Trim()
                $agent = ($parts[1] -split '\.')[0].Trim()
                $phrases = @(
                    $condition -split ', or |, | or ' |
                        ForEach-Object { $_.Trim() } |
                        Where-Object { $_.Length -gt 8 }
                )
                foreach ($phrase in $phrases) {
                    if ($Request.IndexOf($phrase, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
                    if ($agent -ceq $Primary) {
                        return [pscustomobject]@{ Status = 'primary'; Agent = $Primary; Cue = $null }
                    }
                    if ($Installed -notcontains $agent) {
                        return [pscustomobject]@{ Status = 'escalate'; Agent = $null; Cue = $phrase }
                    }
                    if ($Cue.IndexOf($phrase, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                        throw "Resolved cue '$phrase' is not a roster Selection Cue substring."
                    }
                    return [pscustomobject]@{ Status = 'alternate'; Agent = $agent; Cue = $phrase }
                }
            }

            return [pscustomobject]@{ Status = 'primary'; Agent = $Primary; Cue = $null }
        }
    }

    It 'registers the twelve core official skills and keeps the community Alternates' {
        $registered = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast'
        $rows = @(Get-MarkdownTableRows -Body $registered -HeaderCell 'Role')
        $expected = @{
            'plan-alm' = 'plugins/power-pages/skills/plan-alm/SKILL.md'
            'app-builder' = 'plugins/model-apps/skills/app-builder/SKILL.md'
            'generate-codeful-mcp-tool' = 'plugins/mcp-apps/skills/generate-codeful-mcp-tool/SKILL.md'
            'generate-mcp-app-ui' = 'plugins/mcp-apps/skills/generate-mcp-app-ui/SKILL.md'
            'dv-overview' = '.github/plugins/dataverse/skills/dv-overview/SKILL.md'
            'dv-connect' = '.github/plugins/dataverse/skills/dv-connect/SKILL.md'
            'agents-sdk-to-prod' = 'agent-plugins/agents-for-net/skills/agents-sdk-to-prod/SKILL.md'
            'teams-app-manifest' = 'agent-plugins/agents-sdk-common/skills/teams-app-manifest/SKILL.md'
            'agents-sdk-dotnet-otel' = 'agent-plugins/agents-for-net/skills/agents-sdk-dotnet-otel/SKILL.md'
            'agents-sdk-typescript-otel' = 'agent-plugins/agents-for-js/skills/agents-sdk-typescript-otel/SKILL.md'
            'agents-sdk-python-otel' = 'agent-plugins/agents-for-python/skills/agents-sdk-python-otel/SKILL.md'
            'agents-sdk-provision' = 'agent-plugins/agents-sdk-common/skills/agents-sdk-provision/SKILL.md'
        }
        foreach ($name in $expected.Keys) {
            $row = @($rows | Where-Object { $_[3].Trim() -eq ('`{0}`' -f $name) })
            $row | Should -HaveCount 1
            $row[0][5].Trim() | Should -Match '\(`vendor-official`\)'
            $row[0][5].Trim() | Should -Match ([regex]::Escape($expected[$name]))
            $row[0][6].Trim() | Should -Match 'apm install .+ --target copilot'
            $row[0][7].Trim() | Should -Be 'MIT'
            $row[0][6].Trim() | Should -Match '#[a-f0-9]{40} --target copilot'
            $row[0][6].Trim() | Should -Not -Match '/SKILL\.md'
            if ($row[0][1].Trim() -in @('pp-architect', 'pp-connector')) {
                $row[0][10].Trim() | Should -Be '2026-11-11'
            }
            else {
                $row[0][10].Trim() | Should -Be '2026-11-12'
            }
            $row[0][8].Trim() | Should -Match 'Do not auto-install'
        }

        $resources = @($rows | ForEach-Object { $_[3].Trim().Trim('`') })
        foreach ($alternate in @(
                'power-platform-expert', 'power-platform-mcp-integration-expert',
                'declarative-agents-architect', 'mcp-m365-agent-expert')) {
            $resources | Should -Contain $alternate
        }
        $blocklist = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'External Cast Blocklist'
        foreach ($alternate in @(
                'power-platform-expert', 'power-platform-mcp-integration-expert',
                'declarative-agents-architect', 'mcp-m365-agent-expert')) {
            $blocklist | Should -Not -Match ([regex]::Escape($alternate))
        }
    }

    It 'resolves supported jobs to local Primaries and broad jobs to installed Alternates' {
        $cast = @(Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Cast Catalog') `
                -HeaderCell 'Role')
        $cases = @(
            @{ Role = 'pp-architect'; Request = 'Power Pages ALM planning for a site'; Agent = 'Squad Power Platform Architect' }
            @{ Role = 'pp-architect'; Request = 'model-driven app building for claims'; Agent = 'Squad Power Platform Architect' }
            @{ Role = 'pp-architect'; Request = 'Dataverse overview of the tables'; Agent = 'Squad Power Platform Architect' }
            @{ Role = 'pp-architect'; Request = 'Copilot Studio knowledge YAML for a cloned agentic-loop agent'; Agent = 'Squad Power Platform Architect' }
            @{ Role = 'pp-architect'; Request = 'broader Power Platform architecture for this tenant'; Agent = 'Power Platform Expert' }
            @{ Role = 'pp-architect'; Request = 'Copilot Studio topic design'; Agent = 'Power Platform Expert' }
            @{ Role = 'pp-connector'; Request = 'generate a codeful MCP tool'; Agent = 'Squad Power Platform Integrator' }
            @{ Role = 'pp-connector'; Request = 'Dataverse connection diagnostics'; Agent = 'Squad Power Platform Integrator' }
            @{ Role = 'pp-connector'; Request = 'Copilot Studio skill import into this CLI-agent workspace'; Agent = 'Squad Power Platform Integrator' }
            @{ Role = 'pp-connector'; Request = 'broader connector or integration work and certification'; Agent = 'Power Platform MCP Integration Expert' }
            @{ Role = 'm365-agent-architect'; Request = '.NET Agents SDK production readiness review'; Agent = 'Squad M365 Agent Architect' }
            @{ Role = 'm365-agent-architect'; Request = 'Agents SDK Teams manifest audit for this bot'; Agent = 'Squad M365 Agent Architect' }
            @{ Role = 'm365-agent-architect'; Request = 'M365 evaluation suite for this declarative agent'; Agent = 'Squad M365 Agent Architect' }
            @{ Role = 'm365-agent-architect'; Request = 'declarative agent with a TypeSpec manifest'; Agent = 'Declarative Agents Architect' }
            @{ Role = 'm365-agent-integrator'; Request = 'Agents SDK OpenTelemetry for the bot'; Agent = 'Squad M365 Agent Integrator' }
            @{ Role = 'm365-agent-integrator'; Request = 'Agents SDK provisioning plan for Azure Bot'; Agent = 'Squad M365 Agent Integrator' }
            @{ Role = 'm365-agent-integrator'; Request = 'Copilot MCP widget server in Fluent UI'; Agent = 'Squad M365 Agent Integrator' }
            @{ Role = 'm365-agent-integrator'; Request = 'broader MCP-backed M365 integration'; Agent = 'MCP M365 Agent Expert' }
            @{ Role = 'pp-architect'; Request = 'Build a Power Automate cloud flow for invoice approval'; Agent = 'Power Platform Expert' }
            @{ Role = 'pp-architect'; Request = 'Review the canvas app DLP policy and solution ALM'; Agent = 'Power Platform Expert' }
            @{ Role = 'pp-connector'; Request = 'Certify this custom connector before publication'; Agent = 'Power Platform MCP Integration Expert' }
            @{ Role = 'm365-agent-architect'; Request = 'Author a Microsoft 365 Copilot agent manifest in Agents Toolkit'; Agent = 'Declarative Agents Architect' }
            @{ Role = 'm365-agent-integrator'; Request = 'Call Microsoft Graph with the Graph SDK'; Agent = 'MCP M365 Agent Expert' }
            @{ Role = 'pp-architect'; Request = 'review this pull request'; Agent = 'Squad Power Platform Architect' }
        )
        $phrases = @(
            'Power Pages ALM planning, model-driven app building, Dataverse overview, or Copilot Studio knowledge YAML → Squad Power Platform Architect'
            'broader Power Platform architecture or Copilot Studio, Power Automate, cloud flow, canvas app, DLP policy, or solution ALM → Power Platform Expert'
            'codeful MCP tool or UI generation, Dataverse connection, or Copilot Studio skill import → Squad Power Platform Integrator'
            'broader connector or integration work, custom connector, or connector certification → Power Platform MCP Integration Expert'
            '.NET Agents SDK production readiness, Agents SDK Teams manifest, or M365 evaluation suite → Squad M365 Agent Architect'
            'declarative agent, TypeSpec, API plugin, or broader M365 architecture, Microsoft 365 Copilot agent, agent manifest, or Agents Toolkit → Declarative Agents Architect'
            'Agents SDK OpenTelemetry, Agents SDK provisioning, or Copilot MCP widget server → Squad M365 Agent Integrator'
            'broader MCP-backed M365 integration, Microsoft Graph, Graph SDK, Graph permission scope, or MCP-backed Copilot agent → MCP M365 Agent Expert'
        )
        foreach ($phrase in $phrases) {
            $script:RosterCatalogBody | Should -Match ([regex]::Escape($phrase))
            $script:RosterBody | Should -Match ([regex]::Escape($phrase))
            $script:ProfilesBody | Should -Match ([regex]::Escape($phrase))
        }

        foreach ($case in $cases) {
            $row = @($cast | Where-Object { $_[1].Trim().Trim('`') -eq $case.Role })
            $row | Should -HaveCount 1
            $primary = $row[0][2].Trim().Trim('`')
            $cue = $row[0][4].Trim()
            $installed = @($primary, 'Power Platform Expert', 'Power Platform MCP Integration Expert', 'Declarative Agents Architect', 'MCP M365 Agent Expert')
            $resolved = Resolve-OfficialRoleAgent -Cue $cue -Primary $primary -Request $case.Request -Installed $installed
            $resolved.Status | Should -BeIn @('primary', 'alternate')
            $resolved.Agent | Should -BeExactly $case.Agent -Because $case.Request
            if ($resolved.Status -eq 'alternate') {
                $cue.IndexOf($resolved.Cue, [StringComparison]::OrdinalIgnoreCase) | Should -BeGreaterOrEqual 0
            }
        }

        $absent = @($cast | Where-Object { $_[1].Trim().Trim('`') -eq 'pp-architect' })[0]
        $missing = Resolve-OfficialRoleAgent -Cue $absent[4] -Primary $absent[2].Trim().Trim('`') -Request 'Copilot Studio topic design' -Installed @('Squad Power Platform Architect')
        $missing.Status | Should -BeExactly 'escalate'
        $missing.Agent | Should -BeNullOrEmpty
    }

    It 'keeps the new charters hidden, dispatchable, and unbound to a prompt' {
        $agents = Join-Path $SourceRoot 'squad-src/.github/agents/squad'
        $prompts = Get-ChildItem -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/prompts') -Recurse -Filter '*.prompt.md' |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
        foreach ($file in @(
                'squad-pp-architect.agent.md', 'squad-pp-connector.agent.md',
                'squad-m365-agent-architect.agent.md', 'squad-m365-agent-integrator.agent.md')) {
            $raw = (Get-Content -LiteralPath (Join-Path $agents $file) -Raw) -replace "`r`n", "`n"
            $raw | Should -Match '(?m)^user-invocable: false$'
            $raw | Should -Match '(?m)^disable-model-invocation: false$'
            $raw | Should -Not -Match '(?m)^argument-hint:'
            ($raw -replace '(?s)^---.*?---\r?\n', '').Length | Should -BeLessThan 30000
            $name = [regex]::Match($raw, '(?m)^name: (.+)$').Groups[1].Value
            foreach ($prompt in $prompts) {
                $prompt | Should -Not -Match ('(?m)^agent:\s*' + [regex]::Escape($name) + '\s*$')
            }
        }
    }

    It 'offers every PP skill through shared preflight and keeps preview installation complete and optional (SRC-08)' {
        $rows = @(Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast') `
                -HeaderCell 'Role')
        $ppSkills = @($rows | Where-Object {
                $_[1].Trim() -in @('pp-architect', 'pp-connector') -and $_[4].Trim() -eq 'skill'
            })
        $mapped = @(
            Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered Pack Skills') `
                -HeaderCell 'Pack' |
                Where-Object { $_[1].Trim() -eq 'power-platform' } |
                ForEach-Object { $_[2].Trim().Trim('`') } |
                Sort-Object
        )
        $mapped | Should -HaveCount 11
        $mapped -join ',' | Should -BeExactly (@($ppSkills | ForEach-Object { $_[3].Trim().Trim('`') } | Sort-Object) -join ',')
        $profileRow = @(Get-MarkdownTableRows -Body $script:ProfilesBody -HeaderCell 'Resource pack' |
                Where-Object { $_[1].Trim().Trim('`') -eq 'power-platform' })[0]
        @($profileRow[2] -split ',' | ForEach-Object { $_.Trim() } | Sort-Object) -join ',' |
            Should -BeExactly ($mapped -join ',')

        foreach ($name in @('add-knowledge', 'add-skill')) {
            $row = @($ppSkills | Where-Object { $_[3].Trim().Trim('`') -eq $name })
            $row | Should -HaveCount 1
            $row[0][5].Trim() | Should -BeExactly ('`microsoft/copilot-studio-plugin` (`vendor-official`), `skills/{0}/SKILL.md`' -f $name)
            $row[0][6].Trim() | Should -BeExactly '`apm install microsoft/copilot-studio-plugin#4014ae689d1228d86cb3aaab938b1e66f8e2e10d --target copilot`'
            $row[0][8] | Should -Match 'Preview/WIP'
            $row[0][8] | Should -Match 'explicit preview approval'
            $row[0][8] | Should -Match 'startup'
            $row[0][7].Trim() | Should -BeExactly 'MIT'
            $row[0][10].Trim() | Should -BeExactly '2026-11-11'
        }
        @($ppSkills | Where-Object { $_[3].Trim().Trim('`') -in @(
                    'create-agent', 'clone-agent', 'pull-agent', 'push-agent', 'publish-agent', 'delete-agent'
                ) }) | Should -BeNullOrEmpty
    }

    It 'guards PP preview selection, support files and setup authority in both charters and guidance (SRC-09)' {
        $guidance = Get-Content -LiteralPath (Join-Path $script:ReferenceRoot 'power-platform-official-resources.md') -Raw
        $guidance | Should -Match 'Host visibility is not selection'
        $guidance | Should -Match 'declined resource stays unavailable'
        $guidance | Should -Match 'Preview is not the default'
        $guidance | Should -Match 'all eight skills, four agents, two command prompts'
        $guidance | Should -Match 'SessionStart'
        $guidance | Should -Match 'npm install'
        $guidance | Should -Match 'separate.*approval'
        $guidance | Should -Match 'cannot keep unapproved hooks from running, do not install'
        $guidance | Should -Match 'complete.*support|support.*complete'
        $guidance | Should -Match 'source snapshot'
        $guidance | Should -Match 'not registered squad capabilities'
        $guidance | Should -Match 'https://peter-n91\.github\.io/hve-squad/usage\.html#power-platform-setup'
        $script:ProfilesBody | Should -Match '(?s)For `power-platform`, read \[power-platform-official-resources\.md\].*?before asking to install resources'

        foreach ($name in @('squad-pp-architect', 'squad-pp-connector')) {
            $charter = Get-Content -LiteralPath (Join-Path $SourceRoot "squad-src/.github/agents/squad/$name.agent.md") -Raw
            $charter | Should -Match 'only while this pack is active'
            $charter | Should -Match 'user explicitly approved the preview'
            $charter | Should -Match 'decision is not `declined`'
            $charter | Should -Match 'missing support files is not ready'
            $charter | Should -Match 'Do not write squad state'
        }
        $cast = @(Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Cast Catalog') `
                -HeaderCell 'Role')
        foreach ($role in @('pp-architect', 'pp-connector')) {
            @($cast | Where-Object { $_[1].Trim() -eq $role })[0][4] | Should -Match 'preview: explicit approval'
        }
        foreach ($docs in @($script:EnglishDocs, $script:FrenchDocs)) {
            $docs | Should -Match 'id="power-platform-setup"'
            $docs | Should -Match 'copilot-studio-plugin#4014ae689d1228d86cb3aaab938b1e66f8e2e10d'
            $docs | Should -Match 'npm install'
            $docs | Should -Match 'rev-parse HEAD'
            $docs | Should -Match 'git clone --config core.longpaths=true'
            $docs | Should -Match 'apm install github/awesome-copilot/agents/power-platform-expert\.agent\.md#9db369d00f121542e1c99fd9b6cd6f707bade765 --target copilot'
        }
    }

    It 'offers every M365 skill through shared preflight and keeps preview directories pinned and optional (SRC-11)' {
        $rows = @(Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast') `
                -HeaderCell 'Role')
        $m365Skills = @($rows | Where-Object {
                $_[1].Trim() -in @('m365-agent-architect', 'm365-agent-integrator') -and $_[4].Trim() -eq 'skill'
            })
        $mapped = @(
            Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered Pack Skills') `
                -HeaderCell 'Pack' |
                Where-Object { $_[1].Trim() -eq 'm365-copilot' } |
                ForEach-Object { $_[2].Trim().Trim('`') } |
                Sort-Object
        )
        $mapped | Should -HaveCount 14
        $mapped -join ',' | Should -BeExactly (@($m365Skills | ForEach-Object { $_[3].Trim().Trim('`') } | Sort-Object) -join ',')
        $profileRow = @(Get-MarkdownTableRows -Body $script:ProfilesBody -HeaderCell 'Resource pack' |
                Where-Object { $_[1].Trim().Trim('`') -eq 'm365-copilot' })[0]
        @($profileRow[2] -split ',' | ForEach-Object { $_.Trim() } | Sort-Object) -join ',' |
            Should -BeExactly ($mapped -join ',')

        foreach ($row in $m365Skills) {
            $row[6].Trim() | Should -Match '#[a-f0-9]{40} --target copilot'
            $row[6].Trim() | Should -Not -Match '/SKILL\.md'
            $row[7].Trim() | Should -BeExactly 'MIT'
            $row[10].Trim() | Should -BeExactly '2026-11-12'
        }
        foreach ($name in @('m365-agent-evaluator', 'ui-widget-developer')) {
            $row = @($m365Skills | Where-Object { $_[3].Trim().Trim('`') -eq $name })
            $row | Should -HaveCount 1
            $row[0][5].Trim() | Should -BeExactly ('`microsoft/work-iq` (`vendor-official`), `plugins/microsoft-365-agents-toolkit/skills/{0}/SKILL.md`' -f $name)
            $row[0][6].Trim() | Should -BeExactly ('`apm install microsoft/work-iq/plugins/microsoft-365-agents-toolkit/skills/{0}#72c889460aa7ac6d7ed3bb02179332abafc963d4 --target copilot`' -f $name)
            $row[0][8] | Should -Match 'Preview'
            $row[0][8] | Should -Match 'explicit preview approval'
        }
        @($m365Skills | Where-Object { $_[3].Trim().Trim('`') -in @(
                    'declarative-agent-developer', 'wiqd', 'install-atk', 'setup-sso-ui-widget',
                    'teams-app-developer', 'teams-dev', 'workiq'
                ) }) | Should -BeNullOrEmpty
        $blocklist = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'External Cast Blocklist'
        foreach ($community in @(
                'declarative-agents', 'typespec-create-agent', 'typespec-create-api-plugin',
                'msgraph-sdk', 'mcp-create-declarative-agent', 'mcp-deploy-manage-agents')) {
            $mapped | Should -Contain $community
            $blocklist | Should -Not -Match ([regex]::Escape($community))
        }
    }

    It 'guards M365 preview selection, packaged support files, and execution boundaries in charters and docs (SRC-12)' {
        $guidance = Get-Content -LiteralPath (Join-Path $script:ReferenceRoot 'm365-copilot-platform-options.md') -Raw
        $guidance | Should -Match 'Host visibility is not selection'
        $guidance | Should -Match 'declined resource stays unavailable'
        $guidance | Should -Match 'Preview is not the default'
        $guidance | Should -Match 'accept-eula'
        $guidance | Should -Match 'devtunnel'
        $guidance | Should -Match 'declarative-agent-developer'
        $guidance | Should -Match 'wiqd'
        $guidance | Should -Match 'teams-dev'
        $guidance | Should -Match 'not registered squad capabilities'
        $guidance | Should -Match 'https://peter-n91\.github\.io/hve-squad/usage\.html#m365-copilot-setup'
        $script:ProfilesBody | Should -Match '(?s)For `m365-copilot`, read \[m365-copilot-platform-options\.md\].*?before asking to install resources'

        foreach ($name in @('squad-m365-agent-architect', 'squad-m365-agent-integrator')) {
            $charter = Get-Content -LiteralPath (Join-Path $SourceRoot "squad-src/.github/agents/squad/$name.agent.md") -Raw
            $charter | Should -Match 'only while this pack is active'
            $charter | Should -Match 'user explicitly approved the preview'
            $charter | Should -Match 'decision is not `declined`'
            $charter | Should -Match 'missing support files is not ready'
            $charter | Should -Match 'Do not write squad state'
        }
        $cast = @(Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Cast Catalog') `
                -HeaderCell 'Role')
        foreach ($role in @('m365-agent-architect', 'm365-agent-integrator')) {
            @($cast | Where-Object { $_[1].Trim() -eq $role })[0][4] | Should -Match 'preview: explicit approval'
        }
        foreach ($docs in @($script:EnglishDocs, $script:FrenchDocs)) {
            $docs | Should -Match 'id="m365-copilot-setup"'
            $docs | Should -Match 'agents-sdk-to-prod#a5caf57ff062369c410aa5542039b50ce1a9c7e8'
            $docs | Should -Match 'm365-agent-evaluator#72c889460aa7ac6d7ed3bb02179332abafc963d4'
            $docs | Should -Match 'ui-widget-developer#72c889460aa7ac6d7ed3bb02179332abafc963d4'
            $docs | Should -Match 'apm install github/awesome-copilot/agents/declarative-agents-architect\.agent\.md#9db369d00f121542e1c99fd9b6cd6f707bade765 --target copilot'
        }
    }
}

Describe 'Foundry pack-aware selection' -Tag 'Unit' {
    It 'adds data-scientist only when the profile lacks it and gates skill selection on the active pack' {
        function Get-RoleSet {
            param([string]$Body, [string]$Header, [string]$Name)
            $rows = @(Get-MarkdownTableRows -Body $Body -HeaderCell $Header)
            $row = @($rows | Where-Object { $_[1].Trim().Trim('`') -eq $Name })
            $row | Should -HaveCount 1
            @($row[0][2] -split ',' | ForEach-Object { $_.Trim().Trim('`') } | Where-Object { $_ } | Sort-Object -Unique)
        }

        $rosterAdds = Get-RoleSet -Body $script:RosterBody -Header 'Pack' -Name 'foundry'
        $mirrorAdds = Get-RoleSet -Body $script:ProfilesBody -Header 'Pack' -Name 'foundry'
        ($mirrorAdds -join ',') | Should -BeExactly ($rosterAdds -join ',')
        $rosterAdds | Should -Contain 'data-scientist'

        $full = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'full'
        $azure = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'azure'
        $fullAdded = @($rosterAdds | Where-Object { $_ -notin $full })
        $azureAdded = @($rosterAdds | Where-Object { $_ -notin $azure })
        $fullAdded | Should -BeNullOrEmpty
        $azureAdded | Should -Contain 'data-scientist'

        function Test-FoundrySelected {
            param([string]$PacksLine)
            return $PacksLine -match '(?m)^Packs:.*\bfoundry\b'
        }
        Test-FoundrySelected '' | Should -BeFalse
        Test-FoundrySelected "Packs: aws`n" | Should -BeFalse
        Test-FoundrySelected "Packs: foundry`n" | Should -BeTrue
        Test-FoundrySelected (("Packs: foundry`n" -replace '(?m)^Packs: foundry\r?\n', '')) | Should -BeFalse
        Test-FoundrySelected "Packs: foundry`n" | Should -BeTrue

        $scientist = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-data-scientist.agent.md') -Raw
        $observability = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-observability-planner.agent.md') -Raw
        $scientist | Should -Match 'foundry-iq'
        $scientist | Should -Match 'Packs:'
        $scientist | Should -Match 'do not select'
        $observability | Should -Match 'appinsights-instrumentation'
        $observability | Should -Match 'do not select'
        $options = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/foundry-platform-options.md') -Raw
        $options | Should -Match 'does not uninstall or hide'
        $options | Should -Match 'separate Foundry MCP server'
        $options | Should -Match 'mcpServers\.azure'
        $registered = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast'
        $foundryRows = @(Get-MarkdownTableRows -Body $registered -HeaderCell 'Role' | Where-Object { $_[3].Trim() -eq '`microsoft-foundry`' })
        $foundryRows | Should -HaveCount 2
        foreach ($row in $foundryRows) {
            $row[6].Trim() | Should -Match 'Azure MCP server only'
            $row[6].Trim() | Should -Not -Match 'Foundry MCP servers'
            $row[6].Trim() | Should -Match 'mcpServers\.azure'
            $row[8].Trim() | Should -Match 'plugin MCP server;'
            $row[8].Trim() | Should -Not -Match 'plugin MCP servers'
        }
        $script:FoundryBlueprintBody | Should -Match 'Host visibility is not selection'
        $script:ProfilesBody | Should -Match 'foundry-iq'
        $script:ProfilesBody | Should -Match 'only when this pack is active'
    }
}

Describe 'Fabric supplement pack' -Tag 'Unit' {
    It 'reuses data-scientist, gates admitted skills, and leaves current Fabric rows unchanged' {
        function Get-RoleSet {
            param([string]$Body, [string]$Header, [string]$Name)
            $rows = @(Get-MarkdownTableRows -Body $Body -HeaderCell $Header)
            $row = @($rows | Where-Object { $_[1].Trim().Trim('`') -eq $Name })
            $row | Should -HaveCount 1
            @($row[0][2] -split ',' | ForEach-Object { $_.Trim().Trim('`') } | Where-Object { $_ } | Sort-Object -Unique)
        }

        $rosterAdds = Get-RoleSet -Body $script:RosterBody -Header 'Pack' -Name 'fabric'
        $mirrorAdds = Get-RoleSet -Body $script:ProfilesBody -Header 'Pack' -Name 'fabric'
        ($mirrorAdds -join ',') | Should -BeExactly ($rosterAdds -join ',')
        ($rosterAdds -join ',') | Should -BeExactly 'data-scientist'

        $full = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'full'
        $azure = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'azure'
        @($rosterAdds | Where-Object { $_ -notin $full }) | Should -BeNullOrEmpty
        @($rosterAdds | Where-Object { $_ -notin $azure }) | Should -BeExactly @('data-scientist')

        $registered = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast'
        $rows = @(Get-MarkdownTableRows -Body $registered -HeaderCell 'Role')
        $admitted = @(
            'sqldw-cli', 'sqldb-cli', 'eventhouse-cli', 'eventstream-cli',
            'spark-cli', 'dataflows-cli', 'databricks-migration', 'pipeline-migration'
        )
        foreach ($name in $admitted) {
            $row = @($rows | Where-Object { $_[3].Trim() -eq ('`' + $name + '`') })
            $row | Should -HaveCount 1
            $row[0][5].Trim() | Should -BeExactly ('`microsoft/skills-for-fabric` (`vendor-official`), `skills/{0}/SKILL.md`' -f $name)
            $row[0][6].Trim() | Should -BeExactly ('`apm install microsoft/skills-for-fabric/skills/{0} --target copilot`' -f $name)
            $row[0][10].Trim() | Should -BeExactly '2026-11-04'
        }
        $lakehouse = @($rows | Where-Object { $_[3].Trim() -eq '`fabric-lakehouse`' })
        $lakehouse | Should -HaveCount 1
        $lakehouse[0][6].Trim() | Should -BeExactly '`apm install github/awesome-copilot/skills/fabric-lakehouse`'
        $resources = @($rows | ForEach-Object { $_[3].Trim().Trim('`') })
        foreach ($excluded in @(
                'semantic-model-authoring', 'powerbi-report-cli', 'e2e-medallion-architecture',
                'onelake-catalog-govern-cli', 'activator-cli', 'synapse-migration', 'hdinsight-migration')) {
            $resources | Should -Not -Contain $excluded
        }
        $blocklist = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'External Cast Blocklist'
        $blocklist | Should -Not -Match 'sqldw-cli|semantic-model-authoring|fabric-lakehouse'

        $scientist = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-data-scientist.agent.md') -Raw
        $scientist | Should -Match 'sqldw-cli'
        $scientist | Should -Match 'do not select the Fabric supplement skills'
        $blueprint = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/fabric-blueprint.md') -Raw
        $blueprint | Should -Match 'Host visibility is not selection'
        $script:ProfilesBody | Should -Match 'Select the admitted Fabric skills only when this pack is active'
        $script:RoutingBody | Should -Match 'only while `fabric` is active'
        $script:EnglishDocs | Should -Match '<td(?:\s+[^>]*)?><code>fabric</code></td>'
        $script:FrenchDocs | Should -Match '<td(?:\s+[^>]*)?><code>fabric</code></td>'
    }
}

Describe '.NET official pack' -Tag 'Unit' {
    It 'reuses existing roles, offers all twenty pinned directory skills through shared preflight, and blocklists upstream agents (SRC-14)' {
        function Get-RoleSet {
            param([string]$Body, [string]$Header, [string]$Name)
            $rows = @(Get-MarkdownTableRows -Body $Body -HeaderCell $Header)
            $row = @($rows | Where-Object { $_[1].Trim().Trim('`') -eq $Name })
            $row | Should -HaveCount 1
            @($row[0][2] -split ',' | ForEach-Object { $_.Trim().Trim('`') } | Where-Object { $_ } | Sort-Object -Unique)
        }

        $rosterAdds = Get-RoleSet -Body $script:RosterBody -Header 'Pack' -Name 'dotnet'
        $mirrorAdds = Get-RoleSet -Body $script:ProfilesBody -Header 'Pack' -Name 'dotnet'
        ($mirrorAdds -join ',') | Should -BeExactly ($rosterAdds -join ',')
        ($rosterAdds -join ',') | Should -BeExactly 'developer,modernizer,performance,tester'

        $full = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'full'
        $default = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'default'
        $azure = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'azure'
        $operations = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'operations'
        @($rosterAdds | Where-Object { $_ -notin $full }) | Should -BeNullOrEmpty
        (@($rosterAdds | Where-Object { $_ -notin $default } | Sort-Object) -join ',') | Should -BeExactly 'modernizer,performance'
        @($rosterAdds | Where-Object { $_ -notin $azure }) | Should -BeExactly @('performance')
        @($rosterAdds | Where-Object { $_ -notin $operations }) | Should -BeExactly @('modernizer')

        $rows = @(Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast') `
                -HeaderCell 'Role')
        $dotnetSkills = @($rows | Where-Object { $_[5].Trim() -match '^`dotnet/skills`' })
        $mapped = @(
            Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered Pack Skills') `
                -HeaderCell 'Pack' |
                Where-Object { $_[1].Trim() -eq 'dotnet' } |
                ForEach-Object { $_[2].Trim().Trim('`') } |
                Sort-Object
        )
        $mapped | Should -HaveCount 20
        ($mapped -join ',') | Should -BeExactly (@($dotnetSkills | ForEach-Object { $_[3].Trim().Trim('`') } | Sort-Object) -join ',')
        $profileRow = @(Get-MarkdownTableRows -Body $script:ProfilesBody -HeaderCell 'Resource pack' |
                Where-Object { $_[1].Trim().Trim('`') -eq 'dotnet' })[0]
        (@($profileRow[2] -split ',' | ForEach-Object { $_.Trim() } | Sort-Object) -join ',') |
            Should -BeExactly ($mapped -join ',')

        foreach ($row in $dotnetSkills) {
            $row[2].Trim() | Should -BeExactly 'opt-in'
            $row[4].Trim() | Should -BeExactly 'skill'
            $row[5].Trim() | Should -Match '^`dotnet/skills` \(`vendor-official`\), `plugins/[^`]+/skills/[^`]+/SKILL\.md`$'
            $row[6].Trim() | Should -Match '^`apm install dotnet/skills/plugins/[^#]+#2877c712edc20643b72f64e2983b168e6661d607 --target copilot`$'
            $row[6].Trim() | Should -Not -Match '/SKILL\.md'
            $row[7].Trim() | Should -BeExactly 'MIT'
            $row[8].Trim() | Should -Match 'Reach only while `dotnet` is active'
            $row[8].Trim() | Should -Match 'Do not auto-install'
            $row[10].Trim() | Should -BeExactly '2026-11-12'
        }
        foreach ($preview in @('migrate-dotnet10-to-dotnet11', 'exp-mock-usage-analysis')) {
            $row = @($dotnetSkills | Where-Object { $_[3].Trim().Trim('`') -eq $preview })
            $row | Should -HaveCount 1
            $row[0][8] | Should -Match 'Preview'
            $row[0][8] | Should -Match 'explicit preview approval'
        }
        @($rows | Where-Object { $_[3].Trim().Trim('`') -in @(
                    'setup-local-sdk', 'system-text-json-net11', 'csharp-expert',
                    'binlog-failure-analysis', 'troubleshoot-binlog-mcp', 'code-testing',
                    'run-tests', 'test-analysis-extensions', 'code-testing-extensions'
                ) }) | Should -BeNullOrEmpty

        $blocklist = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'External Cast Blocklist'
        $blocklistResources = @(Get-MarkdownTableRows -Body $blocklist -HeaderCell 'Resource' | ForEach-Object { $_[1] }) -join ' '
        foreach ($agent in @('code-testing-implementer', 'test-quality-auditor', 'test-engineer', 'test-migration', 'optimizing-dotnet-performance')) {
            $blocklistResources | Should -Match ([regex]::Escape($agent))
        }
        foreach ($preserved in @('microsoft-agent-framework', 'semantic-kernel', 'recommend-migration-path', 'qa-subagent')) {
            @($rows | Where-Object { $_[3].Trim().Trim('`') -eq $preserved }) | Should -Not -BeNullOrEmpty
            $blocklistResources | Should -Not -Match ('`' + [regex]::Escape($preserved) + '`')
        }
    }

    It 'guards .NET preview selection, packaged support files, and read-only charter boundaries in charters and docs (SRC-15)' {
        $guidance = Get-Content -LiteralPath (Join-Path $script:ReferenceRoot 'dotnet-platform-options.md') -Raw
        $guidance | Should -Match 'Host visibility is not selection'
        $guidance | Should -Match 'declined resource stays unavailable'
        $guidance | Should -Match 'Preview is not the default'
        $guidance | Should -Match 'dotnet-install'
        $guidance | Should -Match 'setup-local-sdk'
        $guidance | Should -Match 'Microsoft\.AITools\.BinlogMcp'
        $guidance | Should -Match 'not registered squad capabilities'
        $guidance | Should -Match 'https://peter-n91\.github\.io/hve-squad/usage\.html#dotnet-setup'
        $script:ProfilesBody | Should -Match '(?s)For `dotnet`, read \[dotnet-platform-options\.md\].*?before asking to install resources'
        $script:RoutingBody | Should -Match 'only while `dotnet` is active'

        foreach ($name in @(
                'squad-modernization-planner', 'squad-reviewer',
                'squad-performance-planner', 'squad-implementor')) {
            $charter = Get-Content -LiteralPath (Join-Path $SourceRoot "squad-src/.github/agents/squad/$name.agent.md") -Raw
            $charter | Should -Match 'dotnet-platform-options\.md'
            $charter | Should -Match 'only while this pack is active'
            $charter | Should -Match 'decision is not `declined`'
            $charter | Should -Match 'missing support files is not ready'
            $charter | Should -Match 'Do not write squad state'
        }
        foreach ($name in @('squad-modernization-planner', 'squad-reviewer', 'squad-implementor')) {
            $charter = Get-Content -LiteralPath (Join-Path $SourceRoot "squad-src/.github/agents/squad/$name.agent.md") -Raw
            $charter | Should -Match 'user explicitly approved the preview'
        }
        foreach ($docs in @($script:EnglishDocs, $script:FrenchDocs)) {
            $docs | Should -Match 'id="dotnet-setup"'
            $docs | Should -Match 'migrate-dotnet9-to-dotnet10#2877c712edc20643b72f64e2983b168e6661d607 --target copilot'
            $docs | Should -Match 'migrate-dotnet10-to-dotnet11#2877c712edc20643b72f64e2983b168e6661d607 --target copilot'
            $docs | Should -Match 'exp-mock-usage-analysis#2877c712edc20643b72f64e2983b168e6661d607 --target copilot'
            $docs | Should -Match 'dotnet-skills-2877c71'
        }
    }
}
