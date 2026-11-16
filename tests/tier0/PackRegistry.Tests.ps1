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
        $foundrySkills = @(
            'agentops-agent', 'agentops-config', 'agentops-eval', 'agentops-governance',
            'agentops-report', 'agt-policy-authoring', 'appinsights-instrumentation',
            'azure-aigateway', 'caira', 'eval-faq', 'foundry-iq', 'microsoft-foundry',
            'use-ai-gateway'
        )
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
        $expectedFoundry = @(
            'agentops-agent', 'agentops-config', 'agentops-eval', 'agentops-governance',
            'agentops-report', 'agt-policy-authoring', 'appinsights-instrumentation',
            'azure-aigateway', 'caira', 'eval-faq', 'foundry-iq', 'microsoft-foundry',
            'use-ai-gateway'
        )
        $expectedFabric = @(
            Get-MarkdownTableRows -Body $script:FabricBlueprintBody -HeaderCell 'Skill' |
                ForEach-Object { $_[1].Trim().Trim('`') } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
        $expectedFabric | Should -HaveCount 15
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
        $gateway[0][6].Trim() | Should -BeExactly '`apm install Azure/aigateway/skills/use-ai-gateway#8cba384de61ab9d438450a79f44fba0528c56d0a --target copilot`'
        $gateway[0][10].Trim() | Should -BeExactly '2026-11-15'
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
    It 'adds missing roles, pins all thirteen official Foundry directory skills, and blocklists colliding candidates (SRC-06, SRC-20)' {
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
        foreach ($role in @('data-scientist', 'observability', 'prompt-engineer', 'rai', 'security')) {
            $rosterAdds | Should -Contain $role
        }

        $full = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'full'
        $azure = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'azure'
        $fullAdded = @($rosterAdds | Where-Object { $_ -notin $full })
        $azureAdded = @($rosterAdds | Where-Object { $_ -notin $azure })
        $fullAdded | Should -BeNullOrEmpty
        (@($azureAdded | Sort-Object) -join ',') | Should -BeExactly 'data-scientist,observability,prompt-engineer,rai'

        $registered = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast'
        $rows = @(Get-MarkdownTableRows -Body $registered -HeaderCell 'Role')
        $packSkillRows = @(Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered Pack Skills') `
                -HeaderCell 'Pack' |
                Where-Object { $_[1].Trim() -eq 'foundry' } |
                ForEach-Object { $_[2].Trim().Trim('`') })
        $packSkillRows | Should -HaveCount 13
        $foundryRows = @($rows | Where-Object { $_[3].Trim().Trim('`') -in $packSkillRows })
        $foundryRows | Should -HaveCount 14 -Because 'microsoft-foundry has developer and deployer rows'
        foreach ($row in $foundryRows) {
            $row[2].Trim() | Should -BeExactly 'opt-in'
            $row[4].Trim() | Should -BeExactly 'skill'
            $row[5].Trim() | Should -Match '\(`vendor-official`\)'
            $row[6].Trim() | Should -Match '^`apm install [^#]+#[a-f0-9]{40} --target copilot`$'
            $row[6].Trim() | Should -Not -Match '/SKILL\.md'
            $row[7].Trim() | Should -BeExactly 'MIT'
            $row[8].Trim() | Should -Match 'Reach only while `foundry` is active'
            $row[8].Trim() | Should -Match 'Do not auto-install'
            $row[10].Trim() | Should -BeExactly '2026-11-15'
        }
        foreach ($preview in @('foundry-iq', 'agentops-governance')) {
            $pRow = @($foundryRows | Where-Object { $_[3].Trim().Trim('`') -eq $preview })
            $pRow | Should -HaveCount 1
            $pRow[0][8] | Should -Match 'Preview'
            $pRow[0][8] | Should -Match 'explicit preview approval'
        }
        $msFoundry = @($foundryRows | Where-Object { $_[3].Trim() -eq '`microsoft-foundry`' })
        $msFoundry | Should -HaveCount 2
        foreach ($row in $msFoundry) {
            $row[8].Trim() | Should -Match 'Azure MCP server only'
            $row[8].Trim() | Should -Not -Match 'Foundry MCP servers'
            $row[8].Trim() | Should -Match 'mcpServers\.azure'
        }

        $blocklist = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'External Cast Blocklist'
        $blocklistResources = @(Get-MarkdownTableRows -Body $blocklist -HeaderCell 'Resource' | ForEach-Object { $_[1] }) -join ' '
        foreach ($blocked in @(
                'agent-governance', 'agent-owasp-compliance', 'agent-governance-reviewer',
                'agentops-dataset', 'agentops-workflow', 'eval-guide', 'eval-suite-planner',
                'eval-generator', 'eval-result-interpreter', 'eval-triage-and-improvement')) {
            $blocklistResources | Should -Match ([regex]::Escape($blocked))
            $packSkillRows | Should -Not -Contain $blocked
        }
    }

    It 'guards Foundry preview selection, packaged support files, and local charter boundaries in charters and docs (SRC-20, SRC-21)' {
        $options = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/foundry-platform-options.md') -Raw
        $options | Should -Match 'Host visibility is not selection'
        $options | Should -Match 'declined resource stays unavailable'
        $options | Should -Match 'Preview is not the default'
        $options | Should -Match 'does not uninstall or hide'
        $options | Should -Match 'separate Foundry MCP server'
        $options | Should -Match 'mcpServers\.azure'
        $options | Should -Match 'not registered squad capabilities'
        $options | Should -Match 'https://peter-n91\.github\.io/hve-squad/usage\.html#foundry-setup'
        $script:FoundryBlueprintBody | Should -Match 'Host visibility is not selection'
        $script:ProfilesBody | Should -Match '(?s)For `foundry`, read \[foundry-platform-options\.md\].*?before asking to install resources'
        $script:ProfilesBody | Should -Match 'only when this pack is active'

        foreach ($name in @(
                'squad-azure-architect', 'squad-data-scientist', 'squad-deployer',
                'squad-implementor', 'squad-observability-planner', 'squad-prompt-engineer')) {
            $charter = Get-Content -LiteralPath (Join-Path $SourceRoot "squad-src/.github/agents/squad/$name.agent.md") -Raw
            $charter | Should -Match 'foundry-platform-options\.md'
            $charter | Should -Match 'only while this pack is active'
            $charter | Should -Match 'decision is not `declined`'
            $charter | Should -Match 'missing support files is not ready'
            $charter | Should -Match 'Do not write squad state'
        }
        foreach ($name in @('squad-data-scientist', 'squad-prompt-engineer')) {
            $charter = Get-Content -LiteralPath (Join-Path $SourceRoot "squad-src/.github/agents/squad/$name.agent.md") -Raw
            $charter | Should -Match 'user explicitly approved the preview'
        }
        foreach ($docs in @($script:EnglishDocs, $script:FrenchDocs)) {
            $docs | Should -Match 'id="foundry-setup"'
            $docs | Should -Match 'microsoft-foundry#968f7bfaa01672e782dae2c6bab4fb9505ae047a --target copilot'
            $docs | Should -Match 'use-ai-gateway#8cba384de61ab9d438450a79f44fba0528c56d0a --target copilot'
            $docs | Should -Match 'foundry-iq#f03ec5392f7a0f3aca12af47477e92f1edf7b44c --target copilot'
            $docs | Should -Match 'agentops-governance#0f2173d03a63c73b9cf4a4d9978136cc5dec2909 --target copilot'
            $docs | Should -Match 'agt-policy-authoring#678070abf15417acdb4a5dd826667a5d83f54d67 --target copilot'
        }
    }
}

Describe 'Fabric and Power BI official pack' -Tag 'Unit' {
    It 'reuses data-scientist, pins all fifteen official Fabric and Power BI directory skills, and blocklists superseded community and upstream entries (SRC-07)' {
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
            'semantic-model-authoring', 'powerbi-report-cli', 'e2e-medallion-architecture',
            'sqldw-cli', 'sqldb-cli', 'eventhouse-cli', 'eventstream-cli', 'activator-cli',
            'spark-cli', 'dataflows-cli', 'onelake-catalog-cli', 'databricks-migration',
            'synapse-migration', 'hdinsight-migration', 'pipeline-migration'
        )
        foreach ($name in $admitted) {
            $row = @($rows | Where-Object { $_[3].Trim() -eq ('`' + $name + '`') })
            $row | Should -HaveCount 1
            $row[0][1].Trim() | Should -BeExactly 'data-scientist'
            $row[0][2].Trim() | Should -BeExactly 'opt-in'
            $row[0][4].Trim() | Should -BeExactly 'skill'
            $row[0][5].Trim() | Should -BeExactly ('`microsoft/skills-for-fabric` (`vendor-official`), `skills/{0}/SKILL.md`' -f $name)
            $row[0][6].Trim() | Should -BeExactly ('`apm install microsoft/skills-for-fabric/skills/{0}#e31422e7d1045ef3a0906df9ff5991f2338af010 --target copilot`' -f $name)
            $row[0][6].Trim() | Should -Not -Match '/SKILL\.md'
            $row[0][7].Trim() | Should -BeExactly 'MIT'
            $row[0][8].Trim() | Should -Match 'Reach only while `fabric` is active'
            $row[0][8].Trim() | Should -Match 'Do not auto-install'
            $row[0][10].Trim() | Should -BeExactly '2026-11-15'
        }
        foreach ($mcpSkill in @('semantic-model-authoring', 'powerbi-report-cli', 'sqldw-cli', 'synapse-migration')) {
            $mRow = @($rows | Where-Object { $_[3].Trim() -eq ('`' + $mcpSkill + '`') })[0]
            $mRow[8] | Should -Match '\.github/mcp\.json'
            $mRow[8] | Should -Match 'disclose before install'
        }

        $resources = @($rows | ForEach-Object { $_[3].Trim().Trim('`') })
        $supersededAndBlocked = @(
            'powerbi-modeling', 'power-bi-model-design-review', 'power-bi-dax-optimization',
            'power-bi-performance-troubleshooting', 'power-bi-report-design-consultation',
            'fabric-lakehouse', 'FabricAdmin', 'FabricAppDev', 'FabricDataEngineer',
            'FabricIQ', 'FabricMigrationEngineer', 'fabriciq', 'ontology-cli',
            'project-osmos', 'e2e-fabric-cost-estimation'
        )
        $blocklist = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'External Cast Blocklist'
        $blocklistResources = @(Get-MarkdownTableRows -Body $blocklist -HeaderCell 'Resource' | ForEach-Object { $_[1] }) -join ' '
        foreach ($blocked in $supersededAndBlocked) {
            $resources | Should -Not -Contain $blocked
            $blocklistResources | Should -Match ([regex]::Escape($blocked))
        }
        foreach ($deferred in @(
                'deployment-pipelines-authoring-cli', 'git-integration-operations-cli',
                'variable-library-cli', 'fabric-policies-cli', 'eventschemaset-cli',
                'databasehub-cli', 'azmon-mirroredcatalogs-operations-cli', 'search-consumption-cli')) {
            $resources | Should -Not -Contain $deferred
            $blocklistResources | Should -Not -Match ('`' + [regex]::Escape($deferred) + '`')
        }
    }

    It 'guards Fabric MCP disclosure, shared common support files, and write boundaries in charter and docs (SRC-07, SRC-21)' {
        $blueprint = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/fabric-blueprint.md') -Raw
        $blueprint | Should -Match 'Host visibility is not selection'
        $blueprint | Should -Match 'declined resource stays unavailable'
        $blueprint | Should -Match 'powerbi-modeling-mcp'
        $blueprint | Should -Match 'fabric-sqlendpoint'
        $blueprint | Should -Match '\.github/mcp\.json'
        $blueprint | Should -Match 'common/COMMON-CLI\.md'
        $blueprint | Should -Match 'https://peter-n91\.github\.io/hve-squad/usage\.html#fabric-setup'
        $script:ProfilesBody | Should -Match '(?s)For `fabric`, read \[fabric-blueprint\.md\].*?before asking to install resources'
        $script:ProfilesBody | Should -Match 'select the admitted Fabric skills only when this pack is active'
        $script:RoutingBody | Should -Match 'only while `fabric` is active'

        $scientist = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-data-scientist.agent.md') -Raw
        $scientist | Should -Match 'fabric-blueprint\.md'
        $scientist | Should -Match 'semantic-model-authoring'
        $scientist | Should -Match 'powerbi-report-cli'
        $scientist | Should -Match 'e2e-medallion-architecture'
        $scientist | Should -Match 'only while this pack is active'
        $scientist | Should -Match 'decision is not `declined`'
        $scientist | Should -Match 'missing support files is not ready'
        $scientist | Should -Match 'Do not write squad state'

        foreach ($docs in @($script:EnglishDocs, $script:FrenchDocs)) {
            $docs | Should -Match '<td(?:\s+[^>]*)?><code>fabric</code></td>'
            $docs | Should -Match 'id="fabric-setup"'
            $docs | Should -Match 'semantic-model-authoring#e31422e7d1045ef3a0906df9ff5991f2338af010 --target copilot'
            $docs | Should -Match 'powerbi-report-cli#e31422e7d1045ef3a0906df9ff5991f2338af010 --target copilot'
            $docs | Should -Match 'e2e-medallion-architecture#e31422e7d1045ef3a0906df9ff5991f2338af010 --target copilot'
            $docs | Should -Match 'skills-for-fabric-e31422e'
        }
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

Describe 'AKS and Azure Functions official packs' -Tag 'Unit' {
    It 'reuses existing roles for aks and azure-functions, orders AKS sub-skills ahead of parent, and blocklists archived/colliding candidates (SRC-17)' {
        function Get-RoleSet {
            param([string]$Body, [string]$Header, [string]$Name)
            $rows = @(Get-MarkdownTableRows -Body $Body -HeaderCell $Header)
            $row = @($rows | Where-Object { $_[1].Trim().Trim('`') -eq $Name })
            $row | Should -HaveCount 1
            @($row[0][2] -split ',' | ForEach-Object { $_.Trim().Trim('`') } | Where-Object { $_ } | Sort-Object -Unique)
        }

        $aksAdds = Get-RoleSet -Body $script:RosterBody -Header 'Pack' -Name 'aks'
        $aksMirror = Get-RoleSet -Body $script:ProfilesBody -Header 'Pack' -Name 'aks'
        ($aksMirror -join ',') | Should -BeExactly ($aksAdds -join ',')
        ($aksAdds -join ',') | Should -BeExactly 'azure-architect,azure-diagnose,cost-manager,developer,modernizer'

        $fnAdds = Get-RoleSet -Body $script:RosterBody -Header 'Pack' -Name 'azure-functions'
        $fnMirror = Get-RoleSet -Body $script:ProfilesBody -Header 'Pack' -Name 'azure-functions'
        ($fnMirror -join ',') | Should -BeExactly ($fnAdds -join ',')
        ($fnAdds -join ',') | Should -BeExactly 'azure-diagnose,deployer,developer,modernizer,tester'

        $full = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'full'
        $azure = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'azure'
        $default = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'default'
        $operations = Get-RoleSet -Body $script:RosterBody -Header 'Profile' -Name 'operations'
        @($aksAdds | Where-Object { $_ -notin $full }) | Should -BeNullOrEmpty
        @($aksAdds | Where-Object { $_ -notin $azure }) | Should -BeNullOrEmpty
        (@($aksAdds | Where-Object { $_ -notin $default } | Sort-Object) -join ',') | Should -BeExactly 'azure-architect,azure-diagnose,cost-manager,modernizer'
        (@($aksAdds | Where-Object { $_ -notin $operations } | Sort-Object) -join ',') | Should -BeExactly 'azure-architect,cost-manager,modernizer'
        @($fnAdds | Where-Object { $_ -notin $full }) | Should -BeNullOrEmpty
        @($fnAdds | Where-Object { $_ -notin $azure }) | Should -BeNullOrEmpty
        (@($fnAdds | Where-Object { $_ -notin $default } | Sort-Object) -join ',') | Should -BeExactly 'azure-diagnose,deployer,modernizer'
        @($fnAdds | Where-Object { $_ -notin $operations }) | Should -BeExactly @('modernizer')

        $rows = @(Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast') `
                -HeaderCell 'Role')
        $packSkillRows = @(Get-MarkdownTableRows `
                -Body (Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered Pack Skills') `
                -HeaderCell 'Pack')

        $aksOrdered = @($packSkillRows | Where-Object { $_[1].Trim() -eq 'aks' } | ForEach-Object { $_[2].Trim().Trim('`') })
        $aksOrdered | Should -HaveCount 7
        $aksOrdered.IndexOf('azure-kubernetes-app-deploy') | Should -BeLessThan $aksOrdered.IndexOf('azure-kubernetes')
        $aksOrdered.IndexOf('azure-kubernetes-automatic-readiness') | Should -BeLessThan $aksOrdered.IndexOf('azure-kubernetes')

        $aksSkills = @($rows | Where-Object { $_[3].Trim().Trim('`') -in $aksOrdered })
        $aksSkills | Should -HaveCount 7
        foreach ($row in $aksSkills) {
            $row[2].Trim() | Should -BeExactly 'opt-in'
            $row[4].Trim() | Should -BeExactly 'skill'
            $row[5].Trim() | Should -Match '^`microsoft/azure-skills` \(`vendor-official`\), `(\.github/plugins/aks-skills/skills/[^`]+|skills/azure-kubernetes(?:/[^`]+)?)/SKILL\.md`$'
            $row[6].Trim() | Should -Match '^`apm install microsoft/azure-skills/[^#]+#968f7bfaa01672e782dae2c6bab4fb9505ae047a --target copilot`$'
            $row[6].Trim() | Should -Not -Match '/SKILL\.md'
            $row[7].Trim() | Should -BeExactly 'MIT'
            $row[8].Trim() | Should -Match 'Reach only while `aks` is active'
            $row[8].Trim() | Should -Match 'Do not auto-install'
            $row[10].Trim() | Should -BeExactly '2026-11-13'
        }

        $fnOrdered = @($packSkillRows | Where-Object { $_[1].Trim() -eq 'azure-functions' } | ForEach-Object { $_[2].Trim().Trim('`') })
        $fnOrdered | Should -HaveCount 10
        $fnSkills = @($rows | Where-Object { $_[5].Trim() -match '^`Azure/azure-functions-skills`' })
        $fnSkills | Should -HaveCount 10
        (@($fnOrdered | Sort-Object) -join ',') | Should -BeExactly (@($fnSkills | ForEach-Object { $_[3].Trim().Trim('`') } | Sort-Object) -join ',')
        foreach ($row in $fnSkills) {
            $row[2].Trim() | Should -BeExactly 'opt-in'
            $row[4].Trim() | Should -BeExactly 'skill'
            $row[5].Trim() | Should -Match '^`Azure/azure-functions-skills` \(`vendor-official`\), `\.github/plugins/azure-functions-skills/skills/[^`]+/SKILL\.md`$'
            $row[6].Trim() | Should -Match '^`apm install Azure/azure-functions-skills/\.github/plugins/azure-functions-skills/skills/[^#]+#34e17220ff073b29a0be5bd541f32d287118165f --target copilot`$'
            $row[6].Trim() | Should -Not -Match '/SKILL\.md'
            $row[7].Trim() | Should -BeExactly 'MIT'
            $row[8].Trim() | Should -Match 'Reach only while `azure-functions` is active'
            $row[8].Trim() | Should -Match 'Do not auto-install'
            $row[10].Trim() | Should -BeExactly '2026-11-13'
        }
        foreach ($preview in @('azure-functions-update', 'azure-functions-hosted-skills')) {
            $row = @($fnSkills | Where-Object { $_[3].Trim().Trim('`') -eq $preview })
            $row | Should -HaveCount 1
            $row[0][8] | Should -Match 'Preview'
            $row[0][8] | Should -Match 'explicit preview approval'
        }

        foreach ($packName in @('aks', 'azure-functions')) {
            $profileRow = @(Get-MarkdownTableRows -Body $script:ProfilesBody -HeaderCell 'Resource pack' |
                    Where-Object { $_[1].Trim().Trim('`') -eq $packName })[0]
            $expected = if ($packName -eq 'aks') { $aksOrdered } else { $fnOrdered }
            (@($profileRow[2] -split ',' | ForEach-Object { $_.Trim() } | Sort-Object) -join ',') |
                Should -BeExactly ((@($expected | Sort-Object)) -join ',')
        }

        @($rows | Where-Object { $_[3].Trim().Trim('`') -in @(
                    'aks-network-capture', 'airunway-aks-setup', 'azure-search-nav',
                    'azure-functions-help', 'azure-functions-setup', 'azure-functions-feedback',
                    'azure-functions-hosted-skills-migrate', 'azure-functions-connector-create',
                    'azure-functions-connector-mcp', 'azure-functions-connector-validate'
                ) }) | Should -BeNullOrEmpty

        $blocklist = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'External Cast Blocklist'
        $blocklistResources = @(Get-MarkdownTableRows -Body $blocklist -HeaderCell 'Resource' | ForEach-Object { $_[1] }) -join ' '
        $blocklistResources | Should -Match '`aks`'
        $blocklistResources | Should -Match '`platform-sre-kubernetes`'
        foreach ($preserved in @('azure-deployment-preflight', 'azure-pricing', 'az-cost-optimize', 'azure-well-architected-review')) {
            @($rows | Where-Object { $_[3].Trim().Trim('`') -eq $preserved }) | Should -Not -BeNullOrEmpty
            $blocklistResources | Should -Not -Match ('`' + [regex]::Escape($preserved) + '`')
        }
    }

    It 'guards AKS and Azure Functions preview selection, packaged support files, and read-only/gated charter boundaries in charters and docs (SRC-18)' {
        $aksGuidance = Get-Content -LiteralPath (Join-Path $script:ReferenceRoot 'aks-platform-options.md') -Raw
        $aksGuidance | Should -Match 'Host visibility is not selection'
        $aksGuidance | Should -Match 'declined resource stays unavailable'
        $aksGuidance | Should -Match 'aks-network-capture'
        $aksGuidance | Should -Match 'airunway-aks-setup'
        $aksGuidance | Should -Match 'ghcfa-telem'
        $aksGuidance | Should -Match 'not registered squad capabilities'
        $aksGuidance | Should -Match 'https://peter-n91\.github\.io/hve-squad/usage\.html#aks-setup'

        $fnGuidance = Get-Content -LiteralPath (Join-Path $script:ReferenceRoot 'azure-functions-platform-options.md') -Raw
        $fnGuidance | Should -Match 'Host visibility is not selection'
        $fnGuidance | Should -Match 'declined resource stays unavailable'
        $fnGuidance | Should -Match 'Preview is not the default'
        $fnGuidance | Should -Match 'azure-functions-setup'
        $fnGuidance | Should -Match 'telemetry\.mjs'
        $fnGuidance | Should -Match 'azure-prepare'
        $fnGuidance | Should -Match 'not registered squad capabilities'
        $fnGuidance | Should -Match 'https://peter-n91\.github\.io/hve-squad/usage\.html#azure-functions-setup'

        $script:ProfilesBody | Should -Match '(?s)For `aks`, read \[aks-platform-options\.md\].*?before asking to install resources'
        $script:ProfilesBody | Should -Match '(?s)For `azure-functions`, read \[azure-functions-platform-options\.md\].*?before asking to install resources'
        $script:RoutingBody | Should -Match 'only while that pack is active'

        foreach ($name in @(
                'squad-azure-architect', 'squad-azure-diagnose', 'squad-cost-manager',
                'squad-implementor', 'squad-modernization-planner')) {
            $charter = Get-Content -LiteralPath (Join-Path $SourceRoot "squad-src/.github/agents/squad/$name.agent.md") -Raw
            $charter | Should -Match 'aks-platform-options\.md'
            $charter | Should -Match 'only while this pack is active'
            $charter | Should -Match 'decision is not `declined`'
            $charter | Should -Match 'missing support files is not ready'
            $charter | Should -Match 'Do not write squad state'
        }
        foreach ($name in @(
                'squad-azure-diagnose', 'squad-deployer', 'squad-implementor',
                'squad-modernization-planner', 'squad-reviewer')) {
            $charter = Get-Content -LiteralPath (Join-Path $SourceRoot "squad-src/.github/agents/squad/$name.agent.md") -Raw
            $charter | Should -Match 'azure-functions-platform-options\.md'
            $charter | Should -Match 'only while this pack is active'
            $charter | Should -Match 'decision is not `declined`'
            $charter | Should -Match 'missing support files is not ready'
            $charter | Should -Match 'Do not write squad state'
        }
        foreach ($name in @('squad-implementor', 'squad-modernization-planner')) {
            $charter = Get-Content -LiteralPath (Join-Path $SourceRoot "squad-src/.github/agents/squad/$name.agent.md") -Raw
            $charter | Should -Match 'user explicitly approved the preview'
        }
        $deployerCharter = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-deployer.agent.md') -Raw
        $deployerCharter | Should -Match 'do not chain into unregistered `azure-prepare`/`azure-validate`/`azure-deploy`'
        $deployerCharter | Should -Match 'do not run `telemetry\.mjs`'

        foreach ($docs in @($script:EnglishDocs, $script:FrenchDocs)) {
            $docs | Should -Match 'id="aks-setup"'
            $docs | Should -Match 'id="azure-functions-setup"'
            $docs | Should -Match 'aks-troubleshooting#968f7bfaa01672e782dae2c6bab4fb9505ae047a --target copilot'
            $docs | Should -Match 'azure-skills-968f7bf'
            $docs | Should -Match 'azure-functions-common#34e17220ff073b29a0be5bd541f32d287118165f --target copilot'
            $docs | Should -Match 'azure-functions-update#34e17220ff073b29a0be5bd541f32d287118165f --target copilot'
            $docs | Should -Match 'azure-functions-hosted-skills#34e17220ff073b29a0be5bd541f32d287118165f --target copilot'
            $docs | Should -Match 'azure-functions-skills-34e1722'
        }
    }
}

Describe 'External Cast backstop pins and split-mode renewal automation' -Tag 'Unit' {
    It 'pins every Registered External Cast row to a 40-char SHA and keeps opt-in rows within the 90-day backstop' {
        $lastUpdatedMatch = [regex]::Match($script:RosterCatalogBody, '(?m)^\s*last_updated:\s*"(?<Date>\d{4}-\d{2}-\d{2})"\s*$')
        $lastUpdatedMatch.Success | Should -BeTrue
        $catalogAsOf = [datetime]::ParseExact($lastUpdatedMatch.Groups['Date'].Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)

        $apmRaw = Get-Content -LiteralPath (Join-Path $SourceRoot 'apm.yml') -Raw
        $registeredBody = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast'
        $registeredBody | Should -Not -Match 'fredgis'
        $rows = @(Get-MarkdownTableRows -Body $registeredBody -HeaderCell 'Role')
        $rows.Count | Should -BeGreaterOrEqual 139

        foreach ($row in $rows) {
            $tier = $row[2].Trim()
            $resource = $row[3].Trim().Trim('`')
            $kind = $row[4].Trim()
            $install = $row[6].Trim()
            $verifiedOn = $row[10].Trim()

            $verifiedOn | Should -Match '^\d{4}-\d{2}-\d{2}$' -Because "row '$resource' needs an ISO Verified On date"
            $verifiedDate = [datetime]::ParseExact($verifiedOn, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            $ageDays = [int][Math]::Floor(($catalogAsOf - $verifiedDate).TotalDays)
            $ageDays | Should -BeGreaterOrEqual 0 -Because "row '$resource' Verified On cannot exceed catalog last_updated"

            if ($tier -eq 'bundled') {
                $entryMatch = [regex]::Match($install, '^`(?<Entry>[^`]+#[0-9a-f]{40})` in apm\.yml$')
                $entryMatch.Success | Should -BeTrue -Because "bundled row '$resource' must pin #<40-hex> in apm.yml"
                $apmRaw | Should -Match ([regex]::Escape($entryMatch.Groups['Entry'].Value))
            } else {
                $ageDays | Should -BeLessOrEqual 90 -Because "opt-in row '$resource' must stay within the 90-day re-verification backstop"
                $install | Should -Match '^`apm install [^#\s`]+#[0-9a-f]{40} --target copilot`$' -Because "opt-in row '$resource' must pin #<40-hex> --target copilot"
                if ($kind -eq 'skill') {
                    $install | Should -Not -Match '/SKILL\.md#' -Because "APM skill row '$resource' must use a directory path"
                }
            }
        }
    }

    It 'sources SQL migration and Azure SQL skills from official microsoft/microsoft-sql and blocklists fredgis' {
        $registeredBody = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'Registered External Cast'
        $rows = @(Get-MarkdownTableRows -Body $registeredBody -HeaderCell 'Role')
        $sqlRows = @($rows | Where-Object { $_[5].Trim() -match '^`microsoft/microsoft-sql`' })
        $expectedSql = @(
            'analyze-readiness-at-scale', 'design-azure-sql-schema', 'diagnose-blocking-and-deadlocks',
            'diagnose-connection-errors', 'diagnose-resource-pressure', 'diagnose-slow-query',
            'entra-id-auth', 'generate-migration-prerequisite-plan', 'get-migration-assessment',
            'github-actions-for-sql', 'prevent-sql-injection', 'read-execution-plan',
            'recommend-migration-path', 'rls-multi-tenant', 'schema-migrations-safely',
            'sql-database-projects', 't-sql-correctness'
        )
        $sqlRows | Should -HaveCount 17
        (@($sqlRows | ForEach-Object { $_[3].Trim().Trim('`') } | Sort-Object) -join ',') |
            Should -BeExactly (($expectedSql | Sort-Object) -join ',')
        foreach ($row in $sqlRows) {
            $row[2].Trim() | Should -BeExactly 'opt-in'
            $row[4].Trim() | Should -BeExactly 'skill'
            $row[5].Trim() | Should -Match '^`microsoft/microsoft-sql` \(`vendor-official`\), `plugins/(microsoft-sql-migration|microsoft-sql)/skills/[^`]+/SKILL\.md`$'
            $row[6].Trim() | Should -Match '^`apm install microsoft/microsoft-sql/plugins/(microsoft-sql-migration|microsoft-sql)/skills/[^#]+#eeb1c6867c2d128763516a1aad41671c593cc189 --target copilot`$'
            $row[7].Trim() | Should -BeExactly 'MIT'
            $row[8].Trim() | Should -Match 'Do not auto-install'
            $row[10].Trim() | Should -BeExactly '2026-11-16'
        }

        @($rows | Where-Object { $_[3].Trim().Trim('`') -in @(
                    'sql-backup-restore-to-azure-sql-vm-migration', 'sql-bacpac-to-azure-sql-db-migration',
                    'sql-server-to-sql-mi-lrs-migration', 'evaluate-azure-migration-assessment',
                    'evaluate-offline-migration-readiness', 'recommend-sku-sizing',
                    'validate-post-migration-data', 'run-migration-assessment'
                ) }) | Should -BeNullOrEmpty

        $blocklist = Get-MarkdownSectionBody -Body $script:RosterCatalogBody -Heading 'External Cast Blocklist'
        $blocklist | Should -Match 'sql-migration-advisor@fredgis'
        $blocklist | Should -Match 'eeb1c6867c2d128763516a1aad41671c593cc189'

        $sqlCharter = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-sql-migration-advisor.agent.md') -Raw
        $sqlCharter | Should -Match 'microsoft/microsoft-sql/plugins/microsoft-sql-migration/skills/recommend-migration-path#eeb1c6867c2d128763516a1aad41671c593cc189'
        $sqlCharter | Should -Match 'get-migration-assessment'
        $sqlCharter | Should -Match 'analyze-readiness-at-scale'
        $sqlCharter | Should -Not -Match 'fredgis'

        $fallbackSkill = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/sql-migration-advisor/SKILL.md') -Raw
        $fallbackRules = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/sql-migration-advisor/reference/decision-rules.md') -Raw
        $noticeText = Get-Content -LiteralPath (Join-Path $SourceRoot 'NOTICE') -Raw
        foreach ($text in @($fallbackSkill, $fallbackRules, $noticeText)) {
            $text | Should -Match 'microsoft/microsoft-sql'
            $text | Should -Not -Match 'fredgis'
        }
    }

    It 'auto-renews zero-diff rows and escalates content, MCP, archive, or redirect drift in Sync-ExternalCast.ps1' {
        $syncScript = Join-Path $SourceRoot 'scripts/Sync-ExternalCast.ps1'
        Test-Path -LiteralPath $syncScript | Should -BeTrue

        $pinSha = '1111111111111111111111111111111111111111'
        $headSha = '2222222222222222222222222222222222222222'
        $workDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null

        $apmFixture = Join-Path $workDir 'apm.yml'
        Set-Content -LiteralPath $apmFixture -Value @(
            'dependencies:'
            '  apm:'
            "    - acme/clean-repo/skills/bundled-skill#$pinSha"
        )

        $catalogFixture = Join-Path $workDir 'roster-catalog.md'
        $initialCatalog = @(
            '---'
            'name: fixture-catalog'
            'metadata:'
            '  last_updated: "2026-09-01"'
            '---'
            ''
            '#### Registered External Cast'
            ''
            '| Role | Tier | Resource | Resource Kind | Origin | Install or Entry | License | Prerequisites | Dispatchability Verified | Verified On |'
            '|---|---|---|---|---|---|---|---|---|---|'
            "| developer | bundled | ``bundled-skill`` | skill | ``acme/clean-repo`` (``vendor-official``), ``skills/bundled-skill/SKILL.md`` | ``acme/clean-repo/skills/bundled-skill#$pinSha`` in apm.yml | MIT | none | ``n/a`` | 2026-08-05 |"
            "| developer | opt-in | ``zero-diff-skill`` | skill | ``acme/clean-repo`` (``vendor-official``), ``skills/zero-diff-skill/SKILL.md`` | ``apm install acme/clean-repo/skills/zero-diff-skill#$pinSha --target copilot`` | MIT | none | ``n/a`` | 2026-09-01 |"
            "| developer | opt-in | ``fresh-skill`` | skill | ``acme/clean-repo`` (``vendor-official``), ``skills/fresh-skill/SKILL.md`` | ``apm install acme/clean-repo/skills/fresh-skill#$pinSha --target copilot`` | MIT | none | ``n/a`` | 2026-11-10 |"
            "| developer | opt-in | ``changed-skill`` | skill | ``acme/clean-repo`` (``vendor-official``), ``skills/changed-skill/SKILL.md`` | ``apm install acme/clean-repo/skills/changed-skill#$pinSha --target copilot`` | MIT | none | ``n/a`` | 2026-09-01 |"
            "| developer | opt-in | ``mcp-hazard-skill`` | skill | ``acme/clean-repo`` (``vendor-official``), ``skills/mcp-hazard-skill/SKILL.md`` | ``apm install acme/clean-repo/skills/mcp-hazard-skill#$pinSha --target copilot`` | MIT | none | ``n/a`` | 2026-09-01 |"
            "| tester | opt-in | ``archived-skill`` | skill | ``acme/archived-repo`` (``community``), ``skills/archived-skill/SKILL.md`` | ``apm install acme/archived-repo/skills/archived-skill#$pinSha --target copilot`` | MIT | none | ``n/a`` | 2026-11-10 |"
            "| tester | opt-in | ``redirected-skill`` | skill | ``acme/old-name`` (``community``), ``skills/redirected-skill/SKILL.md`` | ``apm install acme/old-name/skills/redirected-skill#$pinSha --target copilot`` | MIT | none | ``n/a`` | 2026-11-10 |"
        ) -join "`n"
        [System.IO.File]::WriteAllText($catalogFixture, "$initialCatalog`n", [System.Text.UTF8Encoding]::new($false))

        $validFm = "---`nname: sample`ndescription: sample`n---`n# Sample`n"
        $fixtureJsonPath = Join-Path $workDir 'upstream-fixture.json'
        $fixtureData = @{
            'acme/clean-repo' = @{
                fullName = 'acme/clean-repo'
                archived = $false
                spdxId = 'MIT'
                headSha = $headSha
                trees = @{
                    $pinSha = @{
                        'LICENSE' = 'lic1'
                        'skills/bundled-skill/SKILL.md' = 'b1'
                        'skills/zero-diff-skill/SKILL.md' = 'z1'
                        'skills/zero-diff-skill/references/guide.md' = 'z2'
                        'skills/fresh-skill/SKILL.md' = 'f1'
                        'skills/changed-skill/SKILL.md' = 'c1'
                        'skills/mcp-hazard-skill/SKILL.md' = 'm1'
                        'skills/mcp-hazard-skill/apm.yml' = 'm2'
                    }
                    $headSha = @{
                        'LICENSE' = 'lic1'
                        'skills/bundled-skill/SKILL.md' = 'b1'
                        'skills/zero-diff-skill/SKILL.md' = 'z1'
                        'skills/zero-diff-skill/references/guide.md' = 'z2'
                        'skills/fresh-skill/SKILL.md' = 'f1'
                        'skills/changed-skill/SKILL.md' = 'c2-modified'
                        'skills/mcp-hazard-skill/SKILL.md' = 'm1'
                        'skills/mcp-hazard-skill/apm.yml' = 'm2'
                    }
                }
                contents = @{
                    "${headSha}:skills/zero-diff-skill/SKILL.md" = $validFm
                    "${headSha}:skills/changed-skill/SKILL.md" = $validFm
                    "${headSha}:skills/mcp-hazard-skill/SKILL.md" = $validFm
                    "${headSha}:skills/mcp-hazard-skill/apm.yml" = "name: mcp-hazard`ndependencies:`n  mcp:`n    - foo`n"
                }
            }
            'acme/archived-repo' = @{
                fullName = 'acme/archived-repo'
                archived = $true
                spdxId = 'MIT'
                headSha = $headSha
                trees = @{
                    $pinSha = @{ 'LICENSE' = 'lic1'; 'skills/archived-skill/SKILL.md' = 'a1' }
                    $headSha = @{ 'LICENSE' = 'lic1'; 'skills/archived-skill/SKILL.md' = 'a1' }
                }
                contents = @{}
            }
            'acme/old-name' = @{
                fullName = 'acme/new-name'
                archived = $false
                spdxId = 'MIT'
                headSha = $headSha
                trees = @{
                    $pinSha = @{ 'LICENSE' = 'lic1'; 'skills/redirected-skill/SKILL.md' = 'r1' }
                    $headSha = @{ 'LICENSE' = 'lic1'; 'skills/redirected-skill/SKILL.md' = 'r1' }
                }
                contents = @{}
            }
        }
        [System.IO.File]::WriteAllText($fixtureJsonPath, ($fixtureData | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))

        $beforeBytes = [System.IO.File]::ReadAllText($catalogFixture)
        $dryRes = & $syncScript -CatalogPath $catalogFixture -ApmPath $apmFixture -FixturePath $fixtureJsonPath -AsOf '2026-11-16' -DryRun
        [System.IO.File]::ReadAllText($catalogFixture) | Should -BeExactly $beforeBytes
        $dryRes.Updated | Should -BeTrue
        $dryRes.AutoRenewedCount | Should -Be 1
        $dryRes.NeedsReviewCount | Should -Be 4

        $ghOutPath = Join-Path $workDir 'gh-output.txt'
        $mdReportPath = Join-Path $workDir 'delta.md'
        $oldGhOut = $env:GITHUB_OUTPUT
        try {
            $env:GITHUB_OUTPUT = $ghOutPath
            $liveRes = & $syncScript -CatalogPath $catalogFixture -ApmPath $apmFixture -FixturePath $fixtureJsonPath -AsOf '2026-11-16' -MarkdownPath $mdReportPath -GitHubOutput -Confirm:$false
            $liveRes.AutoRenewedResources | Should -BeExactly @('zero-diff-skill')
            (@($liveRes.NeedsReviewResources | Sort-Object) -join ',') | Should -BeExactly 'archived-skill,changed-skill,mcp-hazard-skill,redirected-skill'
            $liveRes.ReviewDigest | Should -Match '^[0-9a-f]{12}$'

            $afterCatalog = [System.IO.File]::ReadAllText($catalogFixture)
            $afterCatalog | Should -Match 'last_updated: "2026-11-16"'
            $afterCatalog | Should -Match '\| developer \| opt-in \| `zero-diff-skill` .* \| 2026-11-16 \|'
            $afterCatalog | Should -Match '\| developer \| opt-in \| `fresh-skill` .* \| 2026-11-10 \|'
            $afterCatalog | Should -Match '\| developer \| opt-in \| `changed-skill` .* \| 2026-09-01 \|'
            $afterCatalog | Should -Match '\| developer \| opt-in \| `mcp-hazard-skill` .* \| 2026-09-01 \|'

            $reportBody = [System.IO.File]::ReadAllText($mdReportPath)
            $reportBody | Should -Match 'content_changed'
            $reportBody | Should -Match 'undisclosed_skill_apm_mcp'
            $reportBody | Should -Match 'repo_archived'
            $reportBody | Should -Match 'repo_redirected'

            $ghOut = Get-Content -LiteralPath $ghOutPath
            $ghOut | Should -Contain 'updated=true'
            $ghOut | Should -Contain 'needs_review=true'
            $ghOut | Should -Contain 'auto_renewed_count=1'
            $ghOut | Should -Contain 'needs_review_count=4'
        } finally {
            $env:GITHUB_OUTPUT = $oldGhOut
        }

        $syncWf = Get-Content -LiteralPath (Join-Path $SourceRoot '.github/workflows/sync-external-cast.yml') -Raw
        $prWf = Get-Content -LiteralPath (Join-Path $SourceRoot '.github/workflows/pr-validation.yml') -Raw
        $syncWf | Should -Match 'PackRegistry\.Tests\.ps1'
        $syncWf | Should -Match 'chore/sync-external-cast'
        $syncWf | Should -Match 'external-cast-sync:'
        $syncWf | Should -Not -Match 'git push .*main'
        $prWf | Should -Match "github\.head_ref == 'chore/sync-external-cast'"
    }
}
