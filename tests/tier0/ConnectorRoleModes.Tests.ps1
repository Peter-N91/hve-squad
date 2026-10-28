#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Contract pins for connector role modes (CONN-13..CONN-25). These cases stay
# deterministic and offline: they parse shipped references/scripts and assert the
# normative role-mode boundaries without model dispatch.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:Model = Get-SquadPackageModel -PackageRoot $PackageRoot
    $script:RoleModes = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'references/connector-role-modes.md') -Raw
    $script:SeedTemplates = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'references/seed-templates.md') -Raw
    $script:Council = @($script:Model.Instructions | Where-Object Name -eq 'squad-council.instructions.md')[0].Body
    $script:WriteHandoff = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'scripts/Write-SquadHandoff.ps1') -Raw
    $script:Coordinator = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-coordinator.agent.md')[0].Body
    $script:CoordinatorRuntime = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'references/coordinator-runtime.md') -Raw
    $script:CoordinatorInit = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'references/coordinator-init.md') -Raw
    $script:DispatchPlan = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'scripts/New-SquadDispatchPlan.ps1') -Raw
    $script:Catalog = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'references/roster-catalog.md') -Raw
    $script:OperatingProcedure = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'references/operating-procedure.md') -Raw
    $script:PayloadTemplate = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'references/scribe-payload-template.md') -Raw

    function Split-TableLineLocal {
        param([Parameter(Mandatory)][string]$Line)
        $trimmed = $Line.Trim()
        if ($trimmed.StartsWith('|')) { $trimmed = $trimmed.Substring(1) }
        if ($trimmed.EndsWith('|')) { $trimmed = $trimmed.Substring(0, $trimmed.Length - 1) }
        @($trimmed -split '\|') | ForEach-Object { $_.Trim() }
    }

    function Get-MarkdownTablesLocal {
        param([Parameter(Mandatory)][string]$Content)
        $tables = [System.Collections.Generic.List[object]]::new()
        $lines = $Content -split '\r?\n'
        $run = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $lines) {
            if ($line.TrimStart().StartsWith('|')) {
                $run.Add($line)
            }
            else {
                if ($run.Count -ge 2) {
                    $header = Split-TableLineLocal -Line $run[0]
                    $rows = [System.Collections.Generic.List[hashtable]]::new()
                    foreach ($rowLine in ($run | Select-Object -Skip 1)) {
                        if ($rowLine -match '^\s*\|\s*:?-') { continue }
                        $cells = Split-TableLineLocal -Line $rowLine
                        $row = @{}
                        for ($i = 0; $i -lt $header.Count; $i++) {
                            $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' }
                        }
                        $rows.Add($row)
                    }
                    $tables.Add([pscustomobject]@{ Header = $header; Rows = $rows.ToArray() })
                }
                $run = [System.Collections.Generic.List[string]]::new()
            }
        }
        if ($run.Count -ge 2) {
            $header = Split-TableLineLocal -Line $run[0]
            $rows = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($rowLine in ($run | Select-Object -Skip 1)) {
                if ($rowLine -match '^\s*\|\s*:?-') { continue }
                $cells = Split-TableLineLocal -Line $rowLine
                $row = @{}
                for ($i = 0; $i -lt $header.Count; $i++) {
                    $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' }
                }
                $rows.Add($row)
            }
            $tables.Add([pscustomobject]@{ Header = $header; Rows = $rows.ToArray() })
        }
        $tables.ToArray()
    }

    function Get-SectionBodyLocal {
        param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Heading)
        [regex]::Match($Text, "(?ms)^##\s+$([regex]::Escape($Heading))\s*\r?\n(?<body>.*?)(?=^##\s+|\z)").Groups['body'].Value
    }
}

Describe 'CONN-13 Connector Bindings schema ownership and domains' {
    It 'pins the connector-binding header exactly in role-modes and seed templates' {
        $expectedHeader = @('Binding ID', 'Connector ID', 'Manifest', 'Endpoint Kind', 'Role Mode', 'Target Kind', 'Target', 'Member Name', 'Added Role', 'Aligned Role', 'Default Execution')
        $roleModesTable = @(Get-MarkdownTablesLocal -Content $script:RoleModes | Where-Object { $_.Header -contains 'Binding ID' })[0]
        $seedTable = @(Get-MarkdownTablesLocal -Content $script:SeedTemplates | Where-Object { $_.Header -contains 'Binding ID' })[0]
        $roleModesTable.Header | Should -Be $expectedHeader
        $seedTable.Header | Should -Be $expectedHeader
    }

    It 'keeps the closed enum domains for endpoint kind, role mode, target kind, and default execution' {
        $section = Get-SectionBodyLocal -Text $script:RoleModes -Heading '1) Roster-Owned Binding Authority'
        $section | Should -Match ([regex]::Escape('`Endpoint Kind` is `agent` or `orchestrator`.'))
        $section | Should -Match ([regex]::Escape('`Role Mode` is `replace` or `add`.'))
        $section | Should -Match ([regex]::Escape('`Target Kind` is `role` only.'))
        $section | Should -Match ([regex]::Escape('`Default Execution` is `original`, `connector`, `ask`, or `both`.'))
    }
}

Describe 'CONN-14..CONN-20 replacement, execution choice, both, and coordinator shell' {
    It 'states replacement keeps the original row and explicit original/connector selection' {
        $section = Get-SectionBodyLocal -Text $script:RoleModes -Heading '3) Replace/Add Semantics'
        $section | Should -Match ([regex]::Escape('The original internal roster row is retained for explicit `execution=original` and audit.'))
        $section | Should -Match ([regex]::Escape('`role:<role>` or'))
        $section | Should -Match ([regex]::Escape('`role:<role>/<member-name>`'))
    }

    It 'requires additive bindings to carry Member Name, Added Role, and Aligned Role with a matching connector member row' {
        $section = Get-SectionBodyLocal -Text $script:RoleModes -Heading '3) Replace/Add Semantics'
        $section | Should -Match ([regex]::Escape('Additive binding requires `Member Name`, `Added Role`, and `Aligned Role`.'))
        $section | Should -Match ([regex]::Escape('`Agent Name (Primary)=Squad Connector`'))
    }

    It 'keeps deterministic execution precedence and unattended ambiguity stop' {
        $choice = Get-SectionBodyLocal -Text $script:RoleModes -Heading '5) Request-Time Execution Selection'
        $choice | Should -Match '(?m)^1\.\s+Explicit validated `execution=\.\.\.`'
        $choice | Should -Match '(?m)^2\.\s+Exactly one applicable binding with non-`ask` default'
        $choice | Should -Match '(?m)^3\.\s+Interactive clarification'
        $choice | Should -Match '(?m)^4\.\s+Unattended/autopilot stop-escalation'
        $unattended = Get-SectionBodyLocal -Text $script:RoleModes -Heading '11) Unattended Ambiguity Rule'
        $unattended | Should -Match '(?m)^\*\s+stop,'
        $unattended | Should -Match '(?m)^\*\s+escalate,'
    }

    It 'limits both to collision-safe role targets and refuses coordinator/council paths' {
        $section = Get-SectionBodyLocal -Text $script:RoleModes -Heading '6) `both` Constraints'
        $section | Should -Match ([regex]::Escape('target is a **role** (never coordinator),'))
        $section | Should -Match ([regex]::Escape('route is parallel-eligible,'))
        $section | Should -Match ([regex]::Escape('outputs are independently identified (`outputId`) and roots are non-colliding,'))
        $section | Should -Match ([regex]::Escape('no overwrite path exists,'))
        $section | Should -Match ([regex]::Escape('preflight admits each internal dispatch slot.'))
        $section | Should -Match ([regex]::Escape('`both` is refused for council dispatch and for coordinator targets.'))
    }

    It 'keeps coordinator and Scribe governance protected and internal' {
        $section = Get-SectionBodyLocal -Text $script:RoleModes -Heading '8) Protected Governance'
        $section | Should -Match 'Consumers cannot bind, replace, or extend either HVE coordinator, the Scribe'
        foreach ($line in @(
                'intake/discovery/council/implementation gating',
                'Cost Preflight admission',
                'Scribe handoff and state writes',
                'Artifact Gate and Proof-of-Dispatch checks',
                'final synthesis and escalation'
            )) {
            $section | Should -Match ([regex]::Escape($line))
        }
    }
}

Describe 'CONN-21 council bypass remains canonical and internal' {
    It 'keeps the lens-to-role map canonical and free of connector-backed role ids' {
        $lensRows = @(Get-MarkdownTablesLocal -Content $script:Council | Where-Object { $_.Header -contains 'Lens' })[0].Rows
        $map = @{}
        foreach ($row in $lensRows) {
            $role = if ($row.ContainsKey('Role')) { [string]$row['Role'] } else { [string]$row['Role ID'] }
            $map[$row['Lens']] = ($role -replace '`', '').Trim()
        }
        $map['Architecture'] | Should -Be 'architect'
        $map['Security'] | Should -Be 'security'
        $map['Cost'] | Should -Be 'cost-manager'
        $map['Product-fit'] | Should -Be 'product-owner'
        $map['RAI'] | Should -Be 'rai'
        @($map.Values) | Should -Not -Contain 'gcp'
        @($map.Values) | Should -Not -Contain 'Squad Connector'
    }

    It 'pins explicit connector exclusion from council authority in role-modes contract' {
        $section = Get-SectionBodyLocal -Text $script:RoleModes -Heading '7) Canonical Council Exclusion'
        $section | Should -Match ([regex]::Escape('Connector bindings never add, replace, or expand council membership.'))
        $section | Should -Match ([regex]::Escape('Council dispatch always uses internal canonical agents from roster resolution without connector overlays.'))
    }
}

Describe 'CONN-22 and Consumption shape: trusted provenance extends history without widening consumption schema' {
    It 'pins the fixed trusted-provenance rendering bullets' {
        $section = Get-SectionBodyLocal -Text $script:RoleModes -Heading '9) Trusted Provenance'
        $rendered = [regex]::Match($section, '(?ms)^```markdown\r?\n(?<bullets>.*?)\r?\n```').Groups['bullets'].Value
        @($rendered -split '\r?\n') | Should -Be @(
            '* External provenance: connector=<connectorId>; binding=<bindingId>; endpoint=<endpointKind>; mode=<roleMode>; target=<target>'
            '* Verification: external, unverified'
            '* External-unmetered: connector=<connectorId>'
        )
    }

    Describe 'connector registration activates the setup contract and generic additive policy' -Tag 'Unit' {
        It 'conditionally loads role modes for setup, refresh, and manually edited bindings' {
            $script:Coordinator | Should -Match 'references/coordinator-runtime\.md'
            $script:CoordinatorRuntime | Should -Match 'Connector bindings, setup/refresh, execution override or pending exchange.*connector-role-modes\.md'
            $setup = Get-SectionBodyLocal -Text $script:RoleModes -Heading '10) Build/Refresh Question Group'
            $setup | Should -Match 'asking one missing\s+decision at a time'
            $setup | Should -Match 'Complete manually supplied decisions need validation and confirmation'
            $script:OperatingProcedure | Should -Match 'complete requested connector setup per `references/connector-role-modes.md` section 10'
        }

        It 'passes bindings, routes, and connector identity through the Scribe payload' {
            $script:CoordinatorInit | Should -Match '(?s)pass confirmed `connectorBindings`/`customRoutingRows` through cold'
            $script:PayloadTemplate | Should -Match '(?m)^connectorBindings:'
            $script:PayloadTemplate | Should -Match '(?m)^customRoutingRows:'
            $script:PayloadTemplate | Should -Match '(?m)^    memberName:'
            $script:PayloadTemplate | Should -Match '(?m)^    externalProvenance:'
        }

        It 'allows consumer-defined additive roles and no longer claims a connector council lens' {
            $script:Catalog | Should -Match 'Consumer-defined roles.*`gcp`, `dotnet-practices`, or `data-quality`'
            $script:Catalog | Should -Not -Match '`gcp` is a special case'
            $script:Catalog | Should -Not -Match 'connector-backed role counts toward a council lens'
            $script:Catalog | Should -Match 'never satisfy, replace, or add a council lens'
        }

        It 'keeps coordinator and Scribe out of connector registration' {
            $shell = Get-SectionBodyLocal -Text $script:RoleModes -Heading '8) Protected Governance'
            $shell | Should -Match 'Reject `targetKind=coordinator`'
            $shell | Should -Match 'Do not offer such\s+targets during setup'
            $shell | Should -Match 'preserve the internal Scribe\s+handoff'
        }

        It 'uses saved defaults at every autopilot work stage without execution flags' {
            $choice = Get-SectionBodyLocal -Text $script:RoleModes -Heading '5) Request-Time Execution Selection'
            $choice | Should -Match 'Configure once, then run `/squad mode=autopilot <task>` without `execution=`'
            $choice | Should -Match 'every ordinary work-role dispatch'
            $choice | Should -Match 'including planning, review'
            $choice | Should -Match 'with `unattended=true`'
            $choice | Should -Match 'An external `awaiting`\s+result holds the current stage'
            $script:CoordinatorRuntime | Should -Match 'Honor connector defaults'
            $selection = $script:DispatchPlan.IndexOf('Resolve-SquadConnectorExecution')
            $models = $script:DispatchPlan.IndexOf('$persistedModel = if')
            $selection | Should -BeGreaterThan 0
            $selection | Should -BeLessThan $models
            $script:Coordinator | Should -Match '(?s)Check the selected endpoint.*not an unused original'
        }
    }

    It 'keeps the consumption block key order and basis enum unchanged in Write-SquadHandoff.ps1' {
        $script:WriteHandoff | Should -Match ([regex]::Escape('$ConsumptionOrder = @(''model'', ''model_source'', ''priced_as'', ''model_tier'', ''internal_turns'', ''input_tokens'', ''cached_tokens'', ''cache_write_tokens'', ''output_tokens'', ''basis'')'))
        $script:WriteHandoff | Should -Match ([regex]::Escape('$Bases = @(''estimated'', ''tier-default'')'))
        $script:WriteHandoff | Should -Match ([regex]::Escape('-Required @($ConsumptionOrder | Where-Object { $_ -ne ''priced_as'' }) -Optional @(''priced_as'')'))
    }
}
