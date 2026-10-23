#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadState.psm1') -Force
    $script:Skill = Join-Path $PSScriptRoot '..\..\squad-src\.github\skills\squad'
    $script:Resolver = Join-Path $script:Skill 'scripts\Resolve-SquadModelRoute.ps1'
    $script:Models = @('gpt-5.3-codex', 'gpt-5.4-mini', 'gpt-5.5', 'claude-sonnet-5')
    $script:Fields = @(
        'model', 'model_source', 'priced_as', 'model_tier', 'internal_turns'
        'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens', 'basis'
    )

    function New-DelegateFixture {
        param([string]$Mode = 'economy', [string]$WorkerPin = '')
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $root = Join-Path $repo '.copilot-tracking\squad'
        $agents = Join-Path $repo '.github\agents'
        New-Item -ItemType Directory -Path $root, $agents -Force | Out-Null
        $modeLine = if ($Mode -ne 'off') { "Model routing: $Mode" } else { '' }
        $writerModel = if ($Mode -eq 'economy') { 'gpt-5.4-mini' } else { 'gpt-5.3-codex' }
        Set-Content -LiteralPath (Join-Path $root 'team.md') -Encoding utf8NoBOM -Value @(
            '# Squad Team', $modeLine, ''
            '| Role | Member Name | Agent Name (Primary) | Alternate Agents | Model Tier | Model |'
            '|------|-------------|----------------------|------------------|------------|-------|'
            '| product-owner | | Functional Planner | | default | gpt-5.3-codex |'
            '| architect | | System Architecture Reviewer | | extended | gpt-5.5 |'
            "| technical-writer | | Fixture Writer | | fast | $writerModel |"
        )
        Set-Content -LiteralPath (Join-Path $root 'decisions.md') -Value '# Squad Decisions'
        # Adapter-style synthetic list, not the pinned upstream planner's frontmatter.
        Set-Content -LiteralPath (Join-Path $agents 'planner.agent.md') -Value @(
            '---', 'name: Functional Planner', 'agents:', '  - ADO Backlog Executor'
            '  - System Architecture Reviewer', '  - Unused Missing Worker', '---'
        )
        $pin = if ($WorkerPin) { "model: $WorkerPin (copilot)" } else { '' }
        Set-Content -LiteralPath (Join-Path $agents 'executor.agent.md') -Value @(
            '---', 'name: ADO Backlog Executor', 'user-invocable: false', $pin, '---'
            'Requires a confirmed destination, sanitized operations, autonomy tier, and tracking directory.'
        )
        Set-Content -LiteralPath (Join-Path $agents 'architect.agent.md') -Value @(
            '---', 'name: System Architecture Reviewer', 'model: GPT-5.5 (copilot)', '---'
        )
        Set-Content -LiteralPath (Join-Path $agents 'writer.agent.md') -Value @(
            '---', 'name: Fixture Writer', 'model: Claude Sonnet 5 (copilot)', '---'
        )
        $root
    }

    function Resolve-Delegate {
        param([string]$Root, [string]$Agent = 'ADO Backlog Executor', [hashtable]$Extra = @{})
        $parameters = @{
            SquadRoot = $Root; DispatchAgent = $Agent; OwningRole = 'product-owner'
            AvailableModels = $script:Models; AsOf = [datetime]'2026-10-10'
        }
        foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
        & $script:Resolver @parameters | ConvertFrom-Json
    }
}

Describe 'Selected delegate admission on the current economy path' {
    It 'resolves Functional Planner without rostering its advertised ADO worker or admitting unused delegates' {
        $root = New-DelegateFixture
        $before = (Get-FileHash -LiteralPath (Join-Path $root 'team.md')).Hash
        $result = Resolve-Delegate -Root $root -Agent 'Functional Planner'
        $result.dispatch.selectedModel | Should -Be 'gpt-5.3-codex'
        $result.dispatch.routingRole | Should -Be 'product-owner'
        $result.dispatch.worker | Should -BeFalse
        $result.consent | Should -Be 'missing' -Because 'the helper still reports consent, rather than enforcing it'
        (Get-FileHash -LiteralPath (Join-Path $root 'team.md')).Hash | Should -Be $before
        (Get-Content -LiteralPath (Join-Path $root 'team.md') -Raw) | Should -Not -Match 'ADO Backlog Executor'
    }

    It 'retains a known-role delegate own class, floor and policy under <_>' -ForEach @('economy', 'ranked', 'manual') {
        $root = New-DelegateFixture -Mode $_
        $result = Resolve-Delegate -Root $root -Agent 'System Architecture Reviewer'
        $result.dispatch.owningRole | Should -Be 'product-owner'
        $result.dispatch.routingRole | Should -Be 'architect'
        $result.dispatch.class | Should -Be 'council'
        $result.dispatch.floor | Should -Be 'extended'
        $result.dispatch.routingIdentity.requestedModel | Should -Be 'gpt-5.5'
    }

    It 'retains a genuine roster delegate own economy pick instead of using its owner or pin' {
        $result = Resolve-Delegate -Root (New-DelegateFixture) -Agent 'Fixture Writer'
        $result.dispatch.routingRole | Should -Be 'technical-writer'
        $result.dispatch.floor | Should -Be 'fast'
        $result.dispatch.selectedModel | Should -Be 'gpt-5.4-mini'
        $result.dispatch.attributionSource | Should -Be 'cli-pinned'
    }

    It 'lets an unused ineligible known-role delegate remain exhausted without blocking the parent' {
        $result = Resolve-Delegate -Root (New-DelegateFixture) -Agent 'Functional Planner' -Extra @{
            AvailableModels = @('gpt-5.3-codex', 'gpt-5.4-mini')
        }
        $result.dispatch.selectedModel | Should -Be 'gpt-5.3-codex'
        $unused = $result.roles | Where-Object role -EQ 'architect'
        $unused.resolved | Should -BeNullOrEmpty
        $unused.rationale | Should -Be 'floor exhausted'
    }

    It 'explicitly refuses that delegate only when selected, without downgrading to its owner' {
        $root = New-DelegateFixture
        { Resolve-Delegate -Root $root -Agent 'System Architecture Reviewer' -Extra @{
            AvailableModels = @('gpt-5.3-codex', 'gpt-5.4-mini')
        } } | Should -Throw '*Delegate dispatch refused*extended floor*'
    }

    It 'routes an unpinned worker on its owner undiscounted rank, not suggested or resolved economy picks' {
        $result = Resolve-Delegate -Root (New-DelegateFixture) -Extra @{ OwningRole = 'technical-writer' }
        $owner = $result.roles | Where-Object role -EQ 'technical-writer'
        $owner.suggested | Should -Be 'gpt-5.4-mini'
        $owner.resolved | Should -Be 'gpt-5.4-mini'
        $result.dispatch.selectedModel | Should -Be 'gpt-5.3-codex'
        $result.dispatch.floor | Should -Be 'fast'
        $result.dispatch.routingIdentity.routeRationale | Should -Match '^Route: economy; owning role technical-writer.*owning-role ranked model.*floor fast'
    }

    It 'does not inherit a manual owner cell or a session model for an unpinned worker' {
        $root = New-DelegateFixture -Mode manual
        $team = Get-Content -LiteralPath (Join-Path $root 'team.md') -Raw
        Set-Content -LiteralPath (Join-Path $root 'team.md') -Value ($team -replace 'default \| gpt-5.3-codex', 'default | claude-sonnet-5')
        $result = Resolve-Delegate -Root $root -Extra @{ SessionModel = 'claude-sonnet-5' }
        $result.dispatch.selectedModel | Should -Be 'gpt-5.3-codex'
    }

    It 'preserves worker pins and omits the parameter rather than overriding them with owner routing' {
        $result = Resolve-Delegate -Root (New-DelegateFixture -WorkerPin 'Claude Sonnet 5')
        $result.dispatch.selectedModel | Should -Be 'claude-sonnet-5'
        $result.dispatch.routingIdentity.requestedModel | Should -Be 'none (parameter omitted)'
        $result.dispatch.attributionSource | Should -Be 'agent-pinned'
    }

    It 'refuses unavailable, below-floor and uncatalogued pins, never replaces them' -ForEach @(
        @{ Pin = 'Claude Sonnet 5'; Models = @('gpt-5.3-codex'); Error = '*not available*' }
        @{ Pin = 'Claude Haiku 4.5'; Models = @('gpt-5.3-codex', 'claude-haiku-4.5'); Error = '*default floor*' }
        @{ Pin = 'Uncatalogued Model'; Models = @('gpt-5.3-codex'); Error = '*no catalogued capability*' }
    ) {
        $root = New-DelegateFixture -WorkerPin $Pin
        { Resolve-Delegate -Root $root -Extra @{ AvailableModels = $Models } } | Should -Throw $Error
    }

    It 'refuses worker floor exhaustion and a stale automatic rank instead of unverified fallback' {
        $root = New-DelegateFixture
        { Resolve-Delegate -Root $root -Extra @{ AvailableModels = @('claude-haiku-4.5') } } |
            Should -Throw '*no valid model meets the default floor*'
        { Resolve-Delegate -Root $root -Extra @{ AsOf = [datetime]'2027-06-01' } } |
            Should -Throw '*stale-catalog*'
    }

    It 'requires an explicit owning row and never reclassifies a mismatched known role as a worker' {
        $root = New-DelegateFixture
        { Resolve-Delegate -Root $root -Extra @{ OwningRole = '' } } | Should -Throw '*explicit OwningRole*'
        { Resolve-Delegate -Root $root -Agent 'System Architecture Reviewer' -Extra @{ Role = @('product-owner') } } |
            Should -Throw '*does not match*roster identity*'
    }

    It 'requires Scribe refresh before copying a changed role cell under <_>' -ForEach @('ranked', 'economy') {
        $root = New-DelegateFixture -Mode $_
        $team = Get-Content -LiteralPath (Join-Path $root 'team.md') -Raw
        Set-Content -LiteralPath (Join-Path $root 'team.md') -Value ($team -replace 'default \| gpt-5.3-codex', 'default | claude-sonnet-5')
        { Resolve-Delegate -Root $root -Agent 'Functional Planner' } | Should -Throw '*Model cell*refreshed through the Scribe*'
    }

    It 'retains the existing advertised unevaluated manual exception for a genuine roster role' {
        $root = New-DelegateFixture -Mode manual
        $team = Get-Content -LiteralPath (Join-Path $root 'team.md') -Raw
        Set-Content -LiteralPath (Join-Path $root 'team.md') -Value ($team -replace 'extended \| gpt-5.5', 'extended | gpt-5.6-sol-fast')
        $result = Resolve-Delegate -Root $root -Agent 'System Architecture Reviewer' -Extra @{
            AvailableModels = $script:Models + @('gpt-5.6-sol-fast')
        }
        $result.dispatch.selectedModel | Should -Be 'gpt-5.6-sol-fast'
    }

    It 'uses the host report for attribution while keeping the requested model distinct' {
        $result = Resolve-Delegate -Root (New-DelegateFixture) -Extra @{ ObservedModel = 'claude-sonnet-5' }
        $result.dispatch.selectedModel | Should -Be 'gpt-5.3-codex'
        $result.dispatch.attributionSource | Should -Be 'dispatch-reported'
        $identity = $result.dispatch.routingIdentity
        $identity.requestedModel | Should -Be 'gpt-5.3-codex'
        $identity.effectiveModel | Should -Be 'claude-sonnet-5'
        $identity.observedModel | Should -Be 'claude-sonnet-5'
        $identity.routeRationale | Should -Match 'identity-mismatch: requested gpt-5.3-codex, observed claude-sonnet-5$'
    }

    It 'does not report requests or pins as fact under auto without a host report' -ForEach @('', 'Claude Sonnet 5') {
        $result = Resolve-Delegate -Root (New-DelegateFixture -WorkerPin $_) -Extra @{ SessionModel = 'auto' }
        $result.dispatch.selectedModel | Should -Not -BeNullOrEmpty
        $result.dispatch.attributionSource | Should -Be 'unresolved'
        $result.dispatch.routingIdentity.effectiveModel | Should -Be 'unknown'
        $result.dispatch.routingIdentity.observedModel | Should -Be 'unreported'
        $reported = Resolve-Delegate -Root (New-DelegateFixture -WorkerPin $_) -Extra @{
            SessionModel = 'auto'; ObservedModel = 'gpt-5.5'
        }
        $reported.dispatch.attributionSource | Should -Be 'dispatch-reported'
        $reported.dispatch.routingIdentity.effectiveModel | Should -Be 'gpt-5.5'
    }

    It 'retains a below-floor host report truthfully and marks escalation rather than successful admission' {
        $result = Resolve-Delegate -Root (New-DelegateFixture) -Extra @{ ObservedModel = 'claude-haiku-4.5' }
        $result.dispatch.selectedModel | Should -Be 'gpt-5.3-codex'
        $result.dispatch.routingIdentity.effectiveModel | Should -Be 'claude-haiku-4.5'
        $result.dispatch.attributionSource | Should -Be 'dispatch-reported'
        $result.dispatch.observedFloor | Should -Be 'below-floor'
        $result.dispatch.routingIdentity.routeRationale | Should -Match 'below-floor: escalate, not successful admission'
    }

    It 'rejects placeholder host reports and absent or non-dispatchable selected agents' {
        $root = New-DelegateFixture
        { Resolve-Delegate -Root $root -Extra @{ ObservedModel = 'unknown' } } | Should -Throw '*concrete host-reported*'
        { Resolve-Delegate -Root $root -Agent 'Unused Missing Worker' } | Should -Throw '*absent or disables*'
        $agent = Join-Path (Split-Path (Split-Path $root -Parent) -Parent) '.github\agents\executor.agent.md'
        Set-Content -LiteralPath $agent -Value @('---', 'name: ADO Backlog Executor', 'disable-model-invocation: true', '---')
        { Resolve-Delegate -Root $root } | Should -Throw '*absent or disables*'
    }

    It 'preserves repository-first lookup and finds worker pins in an installed plugin' {
        $plugin = Join-Path $TestDrive 'plugin'
        New-Item -ItemType Directory -Path (Join-Path $plugin 'skills\squad'), (Join-Path $plugin 'agents') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:Skill 'scripts'), (Join-Path $script:Skill 'references') -Destination (Join-Path $plugin 'skills\squad') -Recurse
        Set-Content -LiteralPath (Join-Path $plugin 'agents\worker.agent.md') -Value @(
            '---', 'name: Plugin Worker', 'model: Claude Sonnet 5 (copilot)', '---'
        )
        $root = New-DelegateFixture
        $parameters = @{
            SquadRoot = $root; DispatchAgent = 'Plugin Worker'; OwningRole = 'product-owner'
            AvailableModels = $script:Models; AsOf = [datetime]'2026-10-10'
        }
        $result = & (Join-Path $plugin 'skills\squad\scripts\Resolve-SquadModelRoute.ps1') @parameters | ConvertFrom-Json
        $result.dispatch.selectedModel | Should -Be 'claude-sonnet-5'
        $repo = Split-Path (Split-Path $root -Parent) -Parent
        Set-Content -LiteralPath (Join-Path $repo '.github\agents\plugin-worker.agent.md') -Value @(
            '---', 'name: Plugin Worker', 'model: GPT-5.5 (copilot)', '---'
        )
        $result = & (Join-Path $plugin 'skills\squad\scripts\Resolve-SquadModelRoute.ps1') @parameters | ConvertFrom-Json
        $result.dispatch.selectedModel | Should -Be 'gpt-5.5'
    }
}

Describe 'Existing history and consumption schema for selected workers' {
    It 'persists worker ownership and truthful host attribution without casting or extending consumption keys' {
        $result = Resolve-Delegate -Root (New-DelegateFixture) -Extra @{ ObservedModel = 'claude-sonnet-5' }
        $identity = $result.dispatch.routingIdentity
        $root = Join-Path $TestDrive 'worker-ledger'
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\fixtures\scribe-benchmark\seed') -Destination $root -Recurse
        $consumption = [ordered]@{
            model = $identity.effectiveModel; model_source = $result.dispatch.attributionSource
            priced_as = 'Claude Sonnet 5'; model_tier = $result.dispatch.floor; internal_turns = 6
            input_tokens = 9000; cached_tokens = 30000; cache_write_tokens = 4000; output_tokens = 1200; basis = 'estimated'
        }
        $path = Join-Path $root 'history\ADO Backlog Executor.md'
        Set-Content -LiteralPath $path -Value @(
            '# History: ADO Backlog Executor', ''
            '### 2026-10-10T05:00:00Z Worker dispatch', ''
            '* Turn: 1', '* Request: Execute approved operations.', '* Deliverable: handoff-logs.md', '* Outcome: Returned the ledger.', ''
            '#### Consumption', '', '```json', ($consumption | ConvertTo-Json), '```'
            "* **Requested model** - $($identity.requestedModel)"
            "* **Effective model** - $($identity.effectiveModel)"
            "* **Observed model** - $($identity.observedModel)"
            "* **Route rationale** - $($identity.routeRationale)"
        )
        $before = (Get-FileHash -LiteralPath $path).Hash
        $blocks = @(Get-ConsumptionBlock -Path $path)
        $blocks[0].Order | Should -Be $script:Fields
        $blocks[0].Fields.model | Should -Be 'claude-sonnet-5'
        $blocks[0].Fields.model_source | Should -Be 'dispatch-reported'
        $bullets = @(Get-RoutingIdentityBullets -Path $path)
        $bullets[0].Labels | Should -Be @('Requested model', 'Effective model', 'Observed model', 'Route rationale')
        $bullets[0].Values[-1].Value | Should -Match 'owning role product-owner'
        $ledger = Join-Path $script:Skill 'scripts\Measure-SquadLedger.ps1'
        $output = & pwsh -NoProfile -File $ledger -SquadRoot $root -Write 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $output = & pwsh -NoProfile -File $ledger -SquadRoot $root -Check -ExpectedHistoryCounts 'ADO Backlog Executor=1' 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        (Get-Content -LiteralPath (Join-Path $root 'consumption.md') -Raw) | Should -Match 'ADO Backlog Executor.*claude-sonnet-5.*dispatch-reported'
        (Get-Content -LiteralPath (Join-Path $root 'team.md') -Raw) | Should -Not -Match 'ADO Backlog Executor'
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $before
    }
}
