#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Consumed in BeforeAll.')]
param([Parameter(Mandatory)][string]$SourceRoot)

BeforeAll {
    $script:OriginalActiveRoots = $env:SQUAD_ACTIVE_PLUGIN_ROOTS
    $script:DiscoverySource = Join-Path $SourceRoot 'squad-src/.github/skills/squad'
    . (Join-Path $script:DiscoverySource 'scripts/SquadAgentDiscovery.ps1')

    function Write-AgentFile {
        param([string]$Path, [string]$Name, [string]$Extra = '')
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
        [IO.File]::WriteAllText($Path, "---`nname: $Name`n$Extra`n---`n# Fixture`n")
    }

    function New-AgentLayout {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Creates only isolated Pester TestDrive fixtures.')]
        param([switch]$Synced)
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $base 'consumer repo'
        $null = [IO.Directory]::CreateDirectory($repo)
        $squad = Join-Path $base 'installed-plugins/market/hve-squad'
        $core = Join-Path $base 'installed-plugins/market/hve-squad-hve-core'
        if ($Synced) {
            $squad = Join-Path $base 'agentPlugins/squad-source/current-squad'
            $core = Join-Path $base 'agentPlugins/core-source/current-core'
        }
        $skill = Join-Path $squad 'skills/squad'
        $null = [IO.Directory]::CreateDirectory($skill)
        Copy-Item -LiteralPath (Join-Path $script:DiscoverySource 'scripts') -Destination $skill -Recurse
        Copy-Item -LiteralPath (Join-Path $script:DiscoverySource 'references') -Destination $skill -Recurse
        Copy-Item -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/instructions') -Destination $squad -Recurse
        $null = [IO.Directory]::CreateDirectory((Join-Path $squad 'agents'))
        Copy-Item -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/agents/squad') -Destination (Join-Path $squad 'agents') -Recurse
        Write-AgentFile -Path (Join-Path $core '.github/agents/security/security-planner.agent.md') -Name 'Security Planner' -Extra 'model: claude-sonnet-5.5'
        [IO.File]::WriteAllText((Join-Path $core 'plugin.json'), '{"name":"hve-core","agents":[".github/agents/security/security-planner.agent.md"]}')
        [pscustomobject]@{ Repo = $repo; Squad = $squad; Core = $core; Scripts = Join-Path $skill 'scripts'; Base = $base }
    }

    function Read-AgentIndex {
        param($Layout)
        $module = Import-Module (Join-Path $Layout.Scripts 'SquadCoordinator.psm1') -Force -PassThru -DisableNameChecking
        try { Get-SquadAgentIndex -RepoRoot $Layout.Repo }
        finally { Remove-Module $module.Name -Force }
    }
}

AfterAll { $env:SQUAD_ACTIVE_PLUGIN_ROOTS = $script:OriginalActiveRoots }

Describe 'Active host plugin agent discovery (COORD-13)' {
    BeforeEach { Remove-Item Env:SQUAD_ACTIVE_PLUGIN_ROOTS -ErrorAction SilentlyContinue }
    It 'preserves the sibling-plugin layout used by <HostName>' -ForEach @(
        @{ HostName = 'CLI' }, @{ HostName = 'GitHub Copilot App' }
    ) {
        $layout = New-AgentLayout
        $index = Read-AgentIndex $layout
        $index.ContainsKey('Squad Researcher') | Should -BeTrue
        $index['Security Planner'].path | Should -BeExactly (Join-Path $layout.Core '.github/agents/security/security-planner.agent.md')
        $index['Security Planner'].model | Should -BeExactly 'claude-sonnet-5.5'
    }

    It 'finds an explicitly active companion in the separately versioned VS Code layout' {
        $layout = New-AgentLayout -Synced
        (Read-AgentIndex $layout).ContainsKey('Security Planner') | Should -BeFalse
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @($layout.Core) -Compress
        $index = Read-AgentIndex $layout
        $index.ContainsKey('Squad Researcher') | Should -BeTrue
        $index['Security Planner'].dispatchable | Should -BeTrue
        $index['Security Planner'].path | Should -BeExactly (Join-Path $layout.Core '.github/agents/security/security-planner.agent.md')
    }

    It 'preserves Local-harness discovery from repository-deployed agents without a plugin inventory' {
        $layout = New-AgentLayout -Synced
        $localAgent = Join-Path $layout.Repo '.github/agents/security-planner.agent.md'
        Write-AgentFile $localAgent 'Security Planner'
        $index = Read-AgentIndex $layout
        $index['Security Planner'].path | Should -BeExactly $localAgent
        $index['Security Planner'].dispatchable | Should -BeTrue
    }

    It 'uses the same active roots in the actual initialization proposal command' {
        $layout = New-AgentLayout -Synced
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @($layout.Core) -Compress
        $output = & pwsh -NoProfile -File (Join-Path $layout.Scripts 'Get-SquadInitContext.ps1') -RepoRoot $layout.Repo -Role security 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $proposal = $output | ConvertFrom-Json
        $proposal.members[0].primary | Should -BeExactly 'Security Planner'
        $proposal.members[0].available | Should -BeTrue
    }

    It 'keeps repository-local precedence over the active companion' {
        $layout = New-AgentLayout -Synced
        $override = Join-Path $layout.Repo '.github/agents/security-planner.agent.md'
        Write-AgentFile -Path $override -Name 'Security Planner' -Extra 'model: local-pin'
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @($layout.Core) -Compress
        $index = Read-AgentIndex $layout
        $index['Security Planner'].path | Should -BeExactly $override
        $index['Security Planner'].model | Should -BeExactly 'local-pin'
    }

    It 'initializes and prepares native security dispatch through the synced plugin scripts' {
        $layout = New-AgentLayout -Synced
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @($layout.Core) -Compress
        $choices = @{
            confirmed = $true; squadRoot = '.copilot-tracking/squad'; runId = 'plugin-discovery'
            profile = 'custom'; naming = 'skip'; sessionModel = 'claude-sonnet-5.5'
            notify = @{ approvalChannel = 'in-chat'; enabled = $false }
            roles = @('researcher', 'lead', 'developer', 'tester', 'scribe', 'security')
        }
        $choicesPath = Join-Path $layout.Repo 'choices.json'
        $payloadPath = Join-Path $layout.Repo 'payload.json'
        [IO.File]::WriteAllText($choicesPath, ($choices | ConvertTo-Json -Depth 10))
        $output = & pwsh -NoProfile -File (Join-Path $layout.Scripts 'Get-SquadInitContext.ps1') -RepoRoot $layout.Repo -ChoicesPath $choicesPath -PayloadPath $payloadPath 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $output = & pwsh -NoProfile -File (Join-Path $layout.Scripts 'Initialize-Squad.ps1') -RepoRoot $layout.Repo -PayloadPath $payloadPath -Direct 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        ($output | ConvertFrom-Json).verified | Should -BeTrue
        $plan = @{
            squadRoot = '.copilot-tracking/squad'; units = @(@{ id = 'security'; role = 'security' })
            agentTypes = @('hve-squad-hve-core:security-planner')
        }
        $planPath = Join-Path $layout.Repo 'plan.json'
        [IO.File]::WriteAllText($planPath, ($plan | ConvertTo-Json -Depth 10))
        $output = & pwsh -NoProfile -File (Join-Path $layout.Scripts 'New-SquadDispatchPlan.ps1') -RepoRoot $layout.Repo -InputPath $planPath 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $dispatch = $output | ConvertFrom-Json
        $dispatch.units[0].endpoint.agent | Should -BeExactly 'Security Planner'
        $dispatch.units[0].endpoint.nativeAgentTypes.'Security Planner' | Should -BeExactly 'hve-squad-hve-core:security-planner'
        $squadRoot = Join-Path $layout.Repo '.copilot-tracking/squad'
        $output = & pwsh -NoProfile -File (Join-Path $layout.Scripts 'Resolve-SquadModelRoute.ps1') -SquadRoot $squadRoot -Role security -SessionModel 'claude-haiku-5.5' 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        ($output | ConvertFrom-Json).roles[0].expectedModel | Should -BeExactly 'claude-sonnet-5.5'
        $artifact = '.copilot-tracking/security/discovery.md'
        $artifactPath = Join-Path $layout.Repo $artifact
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $artifactPath))
        [IO.File]::WriteAllText($artifactPath, '# Actual fixture security artifact')
        $output = & pwsh -NoProfile -File (Join-Path $layout.Scripts 'Write-SquadHandoff.ps1') -SquadRoot $squadRoot -RunId 'plugin-discovery' -Agent 'Security Planner' -Request 'Check fixture discovery' -Deliverable $artifact -Outcome 'Recorded fixture result' -Quiet 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        Get-Content -LiteralPath (Join-Path $squadRoot 'history/Security Planner.md') -Raw |
            Should -Match 'agent-pinned'
        $plan.agentTypes = @('hve-squad:squad-researcher')
        [IO.File]::WriteAllText($planPath, ($plan | ConvertTo-Json -Depth 10))
        $output = & pwsh -NoProfile -File (Join-Path $layout.Scripts 'New-SquadDispatchPlan.ps1') -RepoRoot $layout.Repo -InputPath $planPath 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $output | Should -Match 'No unique host-advertised native type'
    }

    It 'does not scan stale revisions, unlisted agents, disabled companions or another plugin home' {
        $layout = New-AgentLayout -Synced
        Write-AgentFile (Join-Path $layout.Base 'agentPlugins/core-source/stale/.github/agents/stale.agent.md') 'Stale Agent'
        Write-AgentFile (Join-Path $layout.Base 'another-home/installed-plugins/market/hve-core/.github/agents/other.agent.md') 'Other Home Agent'
        Write-AgentFile (Join-Path $layout.Core '.github/agents/unlisted.agent.md') 'Unlisted Agent'
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @($layout.Core) -Compress
        $index = Read-AgentIndex $layout
        $index.ContainsKey('Stale Agent') | Should -BeFalse
        $index.ContainsKey('Other Home Agent') | Should -BeFalse
        $index.ContainsKey('Unlisted Agent') | Should -BeFalse
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = '[]'
        $index = Read-AgentIndex $layout
        $index.ContainsKey('Security Planner') | Should -BeFalse
        $index.ContainsKey('Squad Researcher') | Should -BeTrue
    }

    It 'does not fall back to an installed sibling omitted from the active inventory' {
        $layout = New-AgentLayout
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = '[]'
        (Read-AgentIndex $layout).ContainsKey('Security Planner') | Should -BeFalse
    }

    It 'honors disable-model-invocation in an active plugin' {
        $layout = New-AgentLayout -Synced
        Write-AgentFile -Path (Join-Path $layout.Core '.github/agents/security/security-planner.agent.md') -Name 'Security Planner' -Extra 'disable-model-invocation: true'
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @($layout.Core) -Compress
        (Read-AgentIndex $layout)['Security Planner'].dispatchable | Should -BeFalse
    }

    It 'supports manifest-declared agent directories' {
        $layout = New-AgentLayout -Synced
        [IO.File]::WriteAllText((Join-Path $layout.Core 'plugin.json'), '{"agents":[".github/agents/"]}')
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @($layout.Core) -Compress
        @(Get-SquadAgentFile -RepoRoot $layout.Repo -ScriptRoot $layout.Scripts).FullName |
            Should -Contain (Join-Path $layout.Core '.github/agents/security/security-planner.agent.md')
    }

    It 'reports a missing companion without substituting a cached revision' {
        $layout = New-AgentLayout -Synced
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @((Join-Path $layout.Base 'missing')) -Compress
        { Read-AgentIndex $layout } | Should -Throw '*Active plugin manifest not found*'
    }

    It 'accepts active plugins with no agent declarations <Manifest>' -ForEach @(
        @{ Manifest = '{"name":"skills-only","skills":["skills"]}' },
        @{ Manifest = '{"name":"no-agents","agents":[]}' }
    ) {
        $layout = New-AgentLayout -Synced
        [IO.File]::WriteAllText((Join-Path $layout.Core 'plugin.json'), $Manifest)
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @($layout.Core) -Compress
        $index = Read-AgentIndex $layout
        $index.ContainsKey('Squad Researcher') | Should -BeTrue
        $index.ContainsKey('Security Planner') | Should -BeFalse
    }

    It 'rejects an explicitly declared missing agent location' {
        $layout = New-AgentLayout -Synced
        [IO.File]::WriteAllText((Join-Path $layout.Core 'plugin.json'), '{"agents":["missing-agents"]}')
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @($layout.Core) -Compress
        { Read-AgentIndex $layout } | Should -Throw '*Active plugin agent path not found*'
    }

    It 'rejects malformed or non-array inventory <Inventory>' -ForEach @(
        @{ Inventory = '{' }, @{ Inventory = '{}' }, @{ Inventory = '"relative"' }, @{ Inventory = '[null]' }
    ) {
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = $Inventory
        { Get-SquadAgentFile -ScriptRoot (Join-Path $script:DiscoverySource 'scripts') } | Should -Throw
    }

    It 'rejects a manifest path that leaves the active plugin' {
        $layout = New-AgentLayout -Synced
        [IO.File]::WriteAllText((Join-Path $layout.Core 'plugin.json'), '{"agents":["../stale/agents"]}')
        $env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @($layout.Core) -Compress
        { Read-AgentIndex $layout } | Should -Throw '*Agent path leaves active plugin*'
    }
}
