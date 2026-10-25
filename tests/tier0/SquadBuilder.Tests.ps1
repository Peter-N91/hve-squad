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
    $script:Root = (Resolve-Path -LiteralPath $SourceRoot).Path
    $script:ScriptsRoot = Join-Path $script:Root 'squad-src/.github/skills/squad/scripts'
    $script:NewConnector = Join-Path $script:ScriptsRoot 'New-SquadConnector.ps1'
    $script:NewEndpoint = Join-Path $script:ScriptsRoot 'New-SquadExternalEndpoint.ps1'
    $script:TestManifest = Join-Path $script:ScriptsRoot 'Test-SquadConnectorManifest.ps1'
    $script:Resolver = Join-Path $script:ScriptsRoot 'Resolve-SquadConnectorDispatch.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path
    . $script:Resolver

    function New-BuilderWorkspace {
        param([Parameter(Mandatory)][string]$Name)
        $path = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        $path
    }

    function New-TestConnector {
        param(
            [Parameter(Mandatory)][string]$Workspace,
            [string]$ConnectorId = 'org-research',
            [ValidateSet('agent', 'orchestrator')][string]$EndpointKind = 'agent'
        )

        $output = & $script:NewConnector `
            -WorkspaceRoot $Workspace `
            -ConnectorId $ConnectorId `
            -EndpointKind $EndpointKind `
            -Capabilities @('Researches approved repository sources') `
            -Roles @('researcher') `
            -Contact 'integrations@example.invalid' | Out-String
        $output | ConvertFrom-Json
    }

    function Invoke-ManifestValidation {
        param([Parameter(Mandatory)][string]$Path)
        $output = & $script:Pwsh -NoProfile -File $script:TestManifest -ManifestPath $Path 2>&1 | Out-String
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = $output
            Result = $output | ConvertFrom-Json
        }
    }
}

Describe 'BUILDER-01 user-invocable builder entrypoints' {
    It '<Agent> is explicitly user-invocable and bound by <Prompt>' -ForEach @(
        @{
            Agent = 'squad-connector-builder.agent.md'
            Prompt = 'squad-connector-builder.prompt.md'
            Name = 'Squad Connector Builder'
        }
        @{
            Agent = 'squad-external-agent-builder.agent.md'
            Prompt = 'squad-external-agent-builder.prompt.md'
            Name = 'Squad External Agent Builder'
        }
    ) {
        $agentPath = Join-Path $script:Root "squad-src/.github/agents/squad/$Agent"
        $promptPath = Join-Path $script:Root "squad-src/.github/prompts/squad/$Prompt"
        $agentText = Get-Content -LiteralPath $agentPath -Raw
        $promptText = Get-Content -LiteralPath $promptPath -Raw
        $agentText | Should -Match '(?m)^user-invocable:\s*true\s*$'
        $agentText | Should -Match 'references/builder-workflows\.md'
        $promptText | Should -Match "(?m)^agent:\s*$([regex]::Escape($Name))\s*$"
    }
}

Describe 'BUILDER-02 configured connector scaffold and validation' {
    It 'creates the manifest, mailbox guidance, examples, removable runner, and runbook' {
        $workspace = New-BuilderWorkspace -Name 'configured-connector'
        $result = New-TestConnector -Workspace $workspace

        $result.status | Should -BeExactly 'ok'
        $result.mode | Should -BeExactly 'configured'
        foreach ($path in @(
                'connectors/org-research.json',
                '.connector-drops/README.md',
                '.connector-drops/org-research/README.md',
                'scripts/Run-org-research-Connector.ps1',
                'connectors/examples/org-research.request.example.json',
                'connectors/examples/org-research.result.example.json',
                'docs/org-research-connector-runbook.md'
            )) {
            Test-Path -LiteralPath (Join-Path $workspace $path) -PathType Leaf | Should -BeTrue
        }

        $validation = Invoke-ManifestValidation -Path (Join-Path $workspace 'connectors/org-research.json')
        $validation.ExitCode | Should -Be 0 -Because $validation.Output
        $validation.Result.status | Should -BeExactly 'ok'
        $validation.Result.issues | Should -HaveCount 0

        $manifest = Get-Content -LiteralPath (Join-Path $workspace 'connectors/org-research.json') -Raw | ConvertFrom-Json
        @($manifest.PSObject.Properties.Name) | Should -Be @(
            'connectorId', 'schemaVersion', 'transport', 'endpointKind', 'capabilities',
            'roles', 'dropPath', 'deadlineMinutesDefault', 'retryCapDefault', 'contact', 'version'
        )
        $manifest.transport | Should -BeExactly 'file'
        $manifest.dropPath | Should -BeExactly '.connector-drops/org-research/'
    }
}

Describe 'BUILDER-03 editable templates' {
    It 'identifies placeholders and remains invalid until they are edited' {
        $workspace = New-BuilderWorkspace -Name 'editable-template'
        $result = (& $script:NewConnector -WorkspaceRoot $workspace -EditableTemplate | Out-String) |
            ConvertFrom-Json

        @($result.placeholders) | Should -Be @(
            'REPLACE_CONNECTOR_ID', 'REPLACE_CAPABILITY', 'REPLACE_ROLE', 'REPLACE_CONTACT'
        )
        $manifestPath = Join-Path $workspace 'connectors/connector.template.json'
        $validation = Invoke-ManifestValidation -Path $manifestPath
        $validation.ExitCode | Should -Be 1
        @($validation.Result.issues) | Should -Contain 'unresolved-placeholder'
        Get-Content -LiteralPath (Join-Path $workspace 'docs/connector-template-connector-runbook.md') -Raw |
            Should -Match 'REPLACE_CONNECTOR_ID'
    }
}

Describe 'BUILDER-04 safe reruns' {
    It 'reports identical files unchanged' {
        $workspace = New-BuilderWorkspace -Name 'unchanged-rerun'
        $null = New-TestConnector -Workspace $workspace
        $second = New-TestConnector -Workspace $workspace
        @($second.files.Action | Sort-Object -Unique) | Should -Be @('unchanged')
    }

    It 'preflights every target and writes nothing when a customized file conflicts' {
        $workspace = New-BuilderWorkspace -Name 'conflicting-rerun'
        $null = New-TestConnector -Workspace $workspace
        $manifestPath = Join-Path $workspace 'connectors/org-research.json'
        Add-Content -LiteralPath $manifestPath -Value 'customized' -Encoding utf8NoBOM
        $runbookPath = Join-Path $workspace 'docs/org-research-connector-runbook.md'
        Remove-Item -LiteralPath $runbookPath

        { $null = New-TestConnector -Workspace $workspace } |
            Should -Throw '*Refusing to overwrite customized file(s):*connectors/org-research.json*'
        Test-Path -LiteralPath $runbookPath | Should -BeFalse -Because 'the complete plan is checked before the first write'
        Get-Content -LiteralPath $manifestPath -Raw | Should -Match 'customized'
    }
}

Describe 'BUILDER-05 removable runner' {
    It 'processes an agent request into a contract-valid result without overwriting' {
        $workspace = New-BuilderWorkspace -Name 'runner-round-trip'
        $null = New-TestConnector -Workspace $workspace
        $taskId = 'example-org-research-001'
        Copy-Item `
            -LiteralPath (Join-Path $workspace 'connectors/examples/org-research.request.example.json') `
            -Destination (Join-Path $workspace ".connector-drops/org-research/$taskId.request.json")

        & (Join-Path $workspace 'scripts/Run-org-research-Connector.ps1') `
            -WorkspaceRoot $workspace -Once

        $resultPath = Join-Path $workspace ".connector-drops/org-research/$taskId.result.json"
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        $shape = Test-SquadConnectorResultShape -Result $result -SchemaVersion '1.1' -EndpointKind 'agent'
        $shape.Status | Should -BeExactly 'ok' -Because ($shape.Issues -join ', ')
        $result.connectorId | Should -BeExactly 'org-research'
        $result.status | Should -BeExactly 'completed'
        $artifactPath = Join-Path $workspace "connector-output/org-research/$($result.artifacts[0].path)"
        Test-Path -LiteralPath $artifactPath -PathType Leaf | Should -BeTrue
        Get-Content -LiteralPath $artifactPath -Raw | Should -Match 'transport compatibility only'

        $hash = (Get-FileHash -LiteralPath $resultPath).Hash
        & (Join-Path $workspace 'scripts/Run-org-research-Connector.ps1') `
            -WorkspaceRoot $workspace -Once
        (Get-FileHash -LiteralPath $resultPath).Hash | Should -BeExactly $hash
    }
}

Describe 'BUILDER-06 external endpoint creation' {
    It 'creates a standalone agent and actionable skill guidance' {
        $workspace = New-BuilderWorkspace -Name 'standalone-agent'
        $result = (& $script:NewEndpoint `
                -WorkspaceRoot $workspace `
                -Mode Create `
                -ConnectorId org-analysis `
                -EndpointKind agent `
                -Capabilities @('Analyzes approved repository sources') `
                -Roles @('researcher') `
                -Responsibilities @('Return a cited analysis note') `
                -SkillRequirements @('Cite exact repository paths') `
                -Contact 'integrations@example.invalid' | Out-String) | ConvertFrom-Json

        $result.status | Should -BeExactly 'ok'
        Test-Path -LiteralPath (Join-Path $workspace '.github/agents/org-analysis.agent.md') | Should -BeTrue
        $skillPath = Join-Path $workspace '.github/skills/org-analysis/SKILL.md'
        Test-Path -LiteralPath $skillPath | Should -BeTrue
        Get-Content -LiteralPath $skillPath -Raw | Should -Match 'Cite exact repository paths'
        Get-Content -LiteralPath (Join-Path $workspace '.github/agents/org-analysis.agent.md') -Raw |
            Should -Match '(?m)^user-invocable:\s*true\s*$'
    }

    It 'creates a multi-agent orchestrator with one bounded worker per responsibility' {
        $workspace = New-BuilderWorkspace -Name 'multi-agent-orchestrator'
        $null = & $script:NewEndpoint `
            -WorkspaceRoot $workspace `
            -Mode Create `
            -ConnectorId org-delivery `
            -EndpointKind orchestrator `
            -Capabilities @('Implements bounded changes', 'Validates changes') `
            -Roles @('developer') `
            -Responsibilities @('Implement the approved change', 'Validate the resulting diff') `
            -SkillRequirements @('Follow repository conventions', 'Run existing tests') `
            -Contact 'integrations@example.invalid'

        $parent = Get-Content -LiteralPath (Join-Path $workspace '.github/agents/org-delivery.agent.md') -Raw
        $parent | Should -Match 'Org Delivery Worker 1'
        $parent | Should -Match 'Org Delivery Worker 2'
        Test-Path -LiteralPath (Join-Path $workspace '.github/agents/org-delivery-worker-1.agent.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $workspace '.github/agents/org-delivery-worker-2.agent.md') | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $workspace '.github/agents/org-delivery-worker-1.agent.md') -Raw |
            Should -Match '(?m)^user-invocable:\s*false\s*$'
    }
}

Describe 'BUILDER-07 existing implementation adaptation' {
    It 'does not modify the implementation and generates only integration artifacts' {
        $workspace = New-BuilderWorkspace -Name 'adapt-existing'
        $existing = Join-Path $workspace 'tools/existing-agent.txt'
        New-Item -ItemType Directory -Path (Split-Path -Parent $existing) -Force | Out-Null
        Set-Content -LiteralPath $existing -Value 'consumer-owned' -Encoding utf8NoBOM
        $before = (Get-FileHash -LiteralPath $existing).Hash

        $null = & $script:NewEndpoint `
            -WorkspaceRoot $workspace `
            -Mode Adapt `
            -ConnectorId org-existing `
            -EndpointKind agent `
            -Capabilities @('Researches approved sources') `
            -Roles @('researcher') `
            -Responsibilities @('Return a cited research note') `
            -ExistingPath 'tools/existing-agent.txt' `
            -Contact 'integrations@example.invalid'

        (Get-FileHash -LiteralPath $existing).Hash | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $workspace '.github/agents') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $workspace '.github/skills') | Should -BeFalse
        $runbook = Get-Content -LiteralPath (Join-Path $workspace 'docs/org-existing-adaptation-runbook.md') -Raw
        $runbook | Should -Match 'tools/existing-agent\.txt'
        $runbook | Should -Match 'was not modified'
    }
}

Describe 'BUILDER-08 generated artifacts contain no execution or credential fields' {
    It 'keeps execution mapping outside the closed manifest' {
        $workspace = New-BuilderWorkspace -Name 'manifest-boundary'
        $null = New-TestConnector -Workspace $workspace
        $manifest = Get-Content -LiteralPath (Join-Path $workspace 'connectors/org-research.json') -Raw
        $manifest | Should -Not -Match '(?i)"(?:command|exec|script|url|token|password|secret)"\s*:'
        $manifest | Should -Not -Match '\.agent\.md'
    }
}
