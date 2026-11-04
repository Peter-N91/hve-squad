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
    $script:CoordinatorInitPath = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/coordinator-init.md'
    $script:FederationPath = Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-federation.instructions.md'
    $script:FoundryBlueprintPath = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/foundry-blueprint.md'
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

    It 'registers the nine official skills and keeps the community Alternates' {
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
            'agents-sdk-dotnet-otel' = 'agent-plugins/agents-for-net/skills/agents-sdk-dotnet-otel/SKILL.md'
            'agents-sdk-provision' = 'agent-plugins/agents-sdk-common/skills/agents-sdk-provision/SKILL.md'
        }
        foreach ($name in $expected.Keys) {
            $row = @($rows | Where-Object { $_[3].Trim() -eq ('`{0}`' -f $name) })
            $row | Should -HaveCount 1
            $row[0][5].Trim() | Should -Match '\(`vendor-official`\)'
            $row[0][5].Trim() | Should -Match ([regex]::Escape($expected[$name]))
            $row[0][6].Trim() | Should -Match 'apm install .+ --target copilot'
            $row[0][7].Trim() | Should -Be 'MIT'
            $row[0][10].Trim() | Should -Be '2026-11-04'
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
            @{ Role = 'pp-architect'; Request = 'broader Power Platform architecture for this tenant'; Agent = 'Power Platform Expert' }
            @{ Role = 'pp-architect'; Request = 'Copilot Studio topic design'; Agent = 'Power Platform Expert' }
            @{ Role = 'pp-connector'; Request = 'generate a codeful MCP tool'; Agent = 'Squad Power Platform Integrator' }
            @{ Role = 'pp-connector'; Request = 'Dataverse connection diagnostics'; Agent = 'Squad Power Platform Integrator' }
            @{ Role = 'pp-connector'; Request = 'broader connector or integration work and certification'; Agent = 'Power Platform MCP Integration Expert' }
            @{ Role = 'm365-agent-architect'; Request = '.NET Agents SDK production readiness review'; Agent = 'Squad M365 Agent Architect' }
            @{ Role = 'm365-agent-architect'; Request = 'declarative agent with a TypeSpec manifest'; Agent = 'Declarative Agents Architect' }
            @{ Role = 'm365-agent-integrator'; Request = 'Agents SDK OpenTelemetry for the bot'; Agent = 'Squad M365 Agent Integrator' }
            @{ Role = 'm365-agent-integrator'; Request = 'broader MCP-backed M365 integration'; Agent = 'MCP M365 Agent Expert' }
            @{ Role = 'pp-architect'; Request = 'review this pull request'; Agent = 'Squad Power Platform Architect' }
        )
        $phrases = @(
            'Power Pages ALM planning, model-driven app building, or Dataverse overview → Squad Power Platform Architect'
            'broader Power Platform architecture or Copilot Studio → Power Platform Expert'
            'codeful MCP tool or UI generation, or Dataverse connection → Squad Power Platform Integrator'
            'broader connector or integration work → Power Platform MCP Integration Expert'
            '.NET Agents SDK production readiness → Squad M365 Agent Architect'
            'declarative agent, TypeSpec, API plugin, or broader M365 architecture → Declarative Agents Architect'
            'Agents SDK OpenTelemetry or provisioning → Squad M365 Agent Integrator'
            'broader MCP-backed M365 integration → MCP M365 Agent Expert'
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
}
