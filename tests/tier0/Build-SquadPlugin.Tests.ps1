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
    $script:SourceRootResolved = $SourceRoot
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:BuildScript = Join-Path $SourceRoot 'scripts/Build-SquadPlugin.ps1'
    $script:PackRosterBody = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-roster.instructions.md') -Raw
    $script:ProgressSourcePath = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/operating-procedure.md'
    $script:OutputRoot = Join-Path $TestDrive 'plugin-output'
    $script:HookScriptNames = @(
        'autonomous-escalation-check'
        'dispatch-guards'
        'impactful-action-gate'
        'notification-audit'
        'prompt-injection-note'
        'session-start-check'
        'state-write-guard'
    )

    $hookScriptRoot = Join-Path $script:OutputRoot 'hooks/scripts'
    New-Item -ItemType Directory -Path $hookScriptRoot -Force | Out-Null
    foreach ($name in $script:HookScriptNames) {
        foreach ($extension in @('ps1', 'sh')) {
            $content = if ($name -eq 'session-start-check' -and $extension -eq 'ps1') {
                'Set-Content -LiteralPath $env:HOOK_SENTINEL -Value powershell -Encoding UTF8'
            }
            elseif ($name -eq 'session-start-check' -and $extension -eq 'sh') {
                '#!/usr/bin/env bash' + "`n" + 'printf bash > "$HOOK_SENTINEL"'
            }
            else {
                ''
            }
            Set-Content -LiteralPath (Join-Path $hookScriptRoot "$name.$extension") -Value $content -Encoding utf8NoBOM
        }
    }

    $pwsh = (Get-Process -Id $PID).Path
    $script:BuildOutput = @(
        & $pwsh -NoProfile -File $script:BuildScript `
            -SourceRoot $SourceRoot `
            -OutputRoot $script:OutputRoot `
            -McpVersion '0.0.0-test' 2>&1
    )
    $script:BuildExitCode = $LASTEXITCODE

    $script:RootManifestPath = Join-Path $script:OutputRoot 'plugin.json'
    $script:NestedManifestPath = Join-Path $script:OutputRoot '.github/plugin/plugin.json'
    $script:HookManifestPath = Join-Path $script:OutputRoot 'hooks.json'
    . $script:BuildScript
}

Describe 'PKG-14 Plugin host discovery and hook commands' -Tag 'Unit' {
    It 'builds the plugin distribution successfully' {
        $script:BuildExitCode | Should -Be 0 -Because ($script:BuildOutput -join "`n")
    }

    It 'ships shared active-plugin discovery and both coordinator entry contracts' {
        Test-Path -LiteralPath (Join-Path $script:OutputRoot 'skills/squad/scripts/SquadAgentDiscovery.ps1') | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $script:OutputRoot 'skills/squad/references/agent-discovery.md') -Raw |
            Should -Match 'SQUAD_ACTIVE_PLUGIN_ROOTS'
        foreach ($name in @('coordinator-runtime', 'federation-runtime')) {
            Get-Content -LiteralPath (Join-Path $script:OutputRoot "skills/squad/references/$name.md") -Raw |
                Should -Match 'agent-discovery.md'
        }
    }

    It 'ships the user-only Squad Coach and a supported manual-agent handoff' {
        $agentPath = Join-Path $script:OutputRoot 'agents/squad/squad-coach.agent.md'
        Test-Path -LiteralPath $agentPath -PathType Leaf | Should -BeTrue
        Get-Content -LiteralPath $agentPath -Raw | Should -Match 'tools: \["read", "search"\]'
        $skillPath = Join-Path $script:OutputRoot 'skills/squad/invocations/squad-coach/SKILL.md'
        Test-Path -LiteralPath $skillPath -PathType Leaf | Should -BeTrue
        $skill = Get-Content -LiteralPath $skillPath -Raw
        $skill | Should -Match 'select the `Squad Coach` agent manually'
        $skill | Should -Match 'Do not dispatch `Squad Coach`'
        $skill | Should -Match 'prefix-free, copy-ready message'
        $skill | Should -Not -Match '(?m)^\d+\. Dispatch|^Dispatch this request'
        Get-Content -LiteralPath $agentPath -Raw | Should -Match 'disable-model-invocation: true'
    }

    It 'ships both user-invocable builders with their invocation and deterministic runtime' {
        $expected = @(
            @{
                Slug = 'squad-connector-builder'
                Name = 'Squad Connector Builder'
            }
            @{
                Slug = 'squad-external-agent-builder'
                Name = 'Squad External Agent Builder'
            }
        )
        foreach ($builder in $expected) {
            $agentPath = Join-Path $script:OutputRoot "agents/squad/$($builder.Slug).agent.md"
            Test-Path -LiteralPath $agentPath -PathType Leaf | Should -BeTrue
            Get-Content -LiteralPath $agentPath -Raw | Should -Match '(?m)^user-invocable:\s*true\s*$'
            $invocationPath = Join-Path $script:OutputRoot "skills/squad/invocations/$($builder.Slug)/SKILL.md"
            Test-Path -LiteralPath $invocationPath -PathType Leaf | Should -BeTrue
            Get-Content -LiteralPath $invocationPath -Raw |
                Should -Match "Dispatch this request to the ``$([regex]::Escape($builder.Name))`` agent"
        }
        foreach ($path in @(
                'skills/squad/scripts/New-SquadConnector.ps1',
                'skills/squad/scripts/New-SquadExternalEndpoint.ps1',
                'skills/squad/scripts/Test-SquadConnectorManifest.ps1',
                'skills/squad/templates/builders/connector-runner.template.ps1'
            )) {
            Test-Path -LiteralPath (Join-Path $script:OutputRoot $path) -PathType Leaf | Should -BeTrue
        }
    }

    It 'does not advertise the Coach when the selected source lacks its <Missing> artifact' -ForEach @(
        @{ Missing = 'agent'; Present = 'prompts/squad/squad-coach.prompt.md' }
        @{ Missing = 'prompt'; Present = 'agents/squad/squad-coach.agent.md' }
    ) {
        $selectedRoot = Join-Path $TestDrive "missing-$Missing"
        $presentPath = Join-Path $selectedRoot "squad-src/.github/$Present"
        New-Item -ItemType Directory -Path (Split-Path -Parent $presentPath) -Force | Out-Null
        Set-Content -LiteralPath $presentPath -Value 'selected artifact'
        $source = [pscustomobject]@{ Mode = 'Source'; SourceRoot = $selectedRoot }
        $skills = New-InvocationSkillContent -Source $source -RepoRoot $script:SourceRootResolved
        $skills.Contains('squad-coach') | Should -BeFalse
        $skills['squad-run'] | Should -Not -Match 'Squad Coach'
    }

    It 'omits the Coach in an older-ref dry run even when the working copy contains it' {
        $historicalRoot = Join-Path $TestDrive 'historical-source'
        New-Item -ItemType Directory -Path $historicalRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:SourceRootResolved 'squad-src') -Destination $historicalRoot -Recurse
        Copy-Item -LiteralPath (Join-Path $script:SourceRootResolved 'apm.yml') -Destination $historicalRoot
        $coachPaths = @(
            'squad-src/.github/agents/squad/squad-coach.agent.md'
            'squad-src/.github/prompts/squad/squad-coach.prompt.md'
        )
        foreach ($path in $coachPaths) { Remove-Item -LiteralPath (Join-Path $historicalRoot $path) }
        & git -C $historicalRoot init --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize historical-source fixture.' }
        & git -C $historicalRoot add -- apm.yml squad-src
        if ($LASTEXITCODE -ne 0) { throw 'Cannot stage historical-source fixture.' }
        & git -C $historicalRoot -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m 'Before Coach'
        if ($LASTEXITCODE -ne 0) { throw 'Cannot commit historical-source fixture.' }
        & git -C $historicalRoot tag fixture-before-coach
        if ($LASTEXITCODE -ne 0) { throw 'Cannot tag historical-source fixture.' }
        foreach ($path in $coachPaths) {
            Copy-Item -LiteralPath (Join-Path $script:SourceRootResolved $path) -Destination (Join-Path $historicalRoot $path)
        }
        $pwsh = (Get-Process -Id $PID).Path
        $output = @(& $pwsh -NoProfile -File $script:BuildScript -RepoRoot $historicalRoot `
            -Ref fixture-before-coach -OutputRoot (Join-Path $TestDrive 'historical-output') `
            -McpVersion '0.0.0-test' -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        ($output -join "`n") | Should -Not -Match 'invocations[\\/]squad-coach[\\/]SKILL\.md'
        $source = [pscustomobject]@{ Mode = 'Ref'; Ref = 'fixture-before-coach' }
        $skills = New-InvocationSkillContent -Source $source -RepoRoot $historicalRoot
        $skills['squad-run'] | Should -Not -Match 'Squad Coach'
    }

    It 'emits byte-identical root and GitHub plugin manifests' {
        Test-Path -LiteralPath $script:RootManifestPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:NestedManifestPath -PathType Leaf | Should -BeTrue
        Get-Content -LiteralPath $script:RootManifestPath -Raw |
            Should -BeExactly (Get-Content -LiteralPath $script:NestedManifestPath -Raw)
    }

    It 'offers exactly the registered packs in the generated invocation' {
        $registered = @(Get-MarkdownTableRows -Body $script:PackRosterBody -HeaderCell 'Pack' |
                ForEach-Object { $_[1].Trim().Trim('`') } | Sort-Object)
        $registered | Should -Not -BeNullOrEmpty
        $invocation = Get-Content -LiteralPath (Join-Path $script:OutputRoot 'skills/squad/invocations/squad-run/SKILL.md') -Raw
        $choices = [regex]::Match($invocation, '(?m)^\* \*\*pack\*\*.*?\((`[^)]+)\)').Groups[1].Value
        $generated = @([regex]::Matches($choices, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
        $generated -join ',' | Should -BeExactly ($registered -join ',')
    }

    It 'keeps compact coordinator conventions portable in the plugin instructions channel' {
        $coordinator = Get-Content -LiteralPath (Join-Path $script:OutputRoot 'agents/squad/squad-coordinator.agent.md') -Raw
        $coordinator | Should -Not -Match '\.github/instructions/squad/|auto-apply through'
        $coordinator | Should -Match 'references/coordinator-runtime\.md'
        $runtime = Get-Content -LiteralPath (Join-Path $script:OutputRoot 'skills/squad/references/coordinator-runtime.md') -Raw
        $runtime | Should -Match 'Get-SquadProcedure\.ps1'
        $profiles = Get-Content -LiteralPath (Join-Path $script:OutputRoot 'skills/squad/references/profiles-and-packs.md') -Raw
        $profiles | Should -Match 'The optional `Guidance` column is the only pack-to-context mechanism'
    }

    It 'ships the measured inline progress contract without an extra reference read' {
        $procedurePath = Join-Path $script:OutputRoot 'skills/squad/references/operating-procedure.md'
        Test-Path -LiteralPath $procedurePath -PathType Leaf | Should -BeTrue
        $procedure = Get-Content -LiteralPath $procedurePath -Raw
        $progressPattern = '(?ms)^### Progress Presentation\r?\n(?<Body>.*?)(?=^#{1,3} |\z)'
        $sourceProcedure = Get-Content -LiteralPath $script:ProgressSourcePath -Raw
        $progress = [regex]::Match($procedure, $progressPattern).Value
        $progress | Should -Not -BeNullOrEmpty
        $progress | Should -BeExactly ([regex]::Match($sourceProcedure, $progressPattern).Value)
        $procedure | Should -Match '(?m)^### Progress Presentation\r?$'
        $procedure | Should -Match 'Apply Progress Presentation before the first work dispatch'
        Test-Path -LiteralPath (Join-Path $script:OutputRoot 'skills/squad/references/progress.md') -PathType Leaf | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $script:OutputRoot 'agents/squad/squad-coordinator.agent.md') -Raw |
            Should -Not -Match 'references/progress\.md'
    }

    It 'qualifies every hook command with the installed plugin root' {
        $manifest = Get-Content -LiteralPath $script:HookManifestPath -Raw | ConvertFrom-Json
        $entries = @(
            foreach ($eventProperty in $manifest.hooks.PSObject.Properties) {
                $eventProperty.Value
            }
        )

        $entries | Should -HaveCount $script:HookScriptNames.Count
        foreach ($entry in $entries) {
            $entry.bash | Should -Match '^bash "\$\{CLAUDE_PLUGIN_ROOT\}/hooks/scripts/[a-z-]+\.sh"$'
            $entry.powershell | Should -Match '^(powershell\.exe|pwsh) -NoProfile -ExecutionPolicy Bypass -File "\$env:CLAUDE_PLUGIN_ROOT/hooks/scripts/[a-z-]+\.ps1"$'
        }
        $manifest.hooks.preToolUse[2].powershell | Should -Match '^pwsh '
    }

    It 'generates the canonical routing preparation and guard for the plugin as well as APM' {
        foreach ($path in @('references/coordinator-runtime.md', 'references/federation-runtime.md', 'scripts/New-SquadDispatchPlan.ps1')) {
            Get-Content -LiteralPath (Join-Path $script:OutputRoot "skills/squad/$path") -Raw | Should -Match 'ApplyModelRouting'
        }
        foreach ($extension in @('ps1', 'sh')) {
            $source = [IO.File]::ReadAllText((Join-Path $script:SourceRootResolved "scripts/plugin-hooks/dispatch-guards.$extension")) -replace "`r`n", "`n"
            $generated = [IO.File]::ReadAllText((Join-Path $script:OutputRoot "hooks/scripts/dispatch-guards.$extension")) -replace "`r`n", "`n"
            $generated | Should -BeExactly $source
        }
        $dropSkill = [IO.File]::ReadAllText((Join-Path $script:OutputRoot 'skills/squad/invocations/squad-init-hooks/SKILL.md'))
        $dropSkill | Should -Match 'PowerShell 7\.4\+'
        $dropSkill | Should -Match 'dispatch-guards\.ps1'
        $dropSkill | Should -Match 'scripts/SquadCoordinator\.psm1'
        $dropSkill | Should -Match 'scripts/Resolve-SquadConnectorDispatch\.ps1'
    }

    It 'resolves a SourceRoot build without a git repository or tags' {
        $taglessSource = Join-Path $TestDrive 'tagless-source'
        New-Item -ItemType Directory -Path (Join-Path $taglessSource 'squad-src/.github') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $taglessSource 'apm.yml') -Value "name: fixture`nversion: 9.8.7`n" -Encoding utf8NoBOM

        $source = Resolve-BuildSource -RepoRoot $taglessSource `
            -RefSpecified $false -Ref $null `
            -SourceRootSpecified $true -SourceRoot $taglessSource

        $source.PluginVersion | Should -BeExactly '9.8.7+local'
    }

    Describe 'Native plugin routed-model guard (SQ-39)' {
        BeforeAll {
            function Invoke-DispatchGuard {
                param(
                    [string]$Mode = 'ranked',
                    [string]$Agent = 'hve-squad:squad-lead',
                    [string]$Model = '',
                    [string]$Cell = 'gpt-5.6-sol',
                    [string]$Shape = 'camel',
                    [switch]$Member,
                    [string]$Prompt = 'Quick planning'
                )
                $repo = Join-Path $TestDrive ("guard-" + [guid]::NewGuid().ToString('N'))
                $root = Join-Path $repo '.copilot-tracking/squad'
                if ($Member) { $root = Join-Path $root 'members/product' }
                $null = [IO.Directory]::CreateDirectory($root)
                $policy = if ($Mode) { "Model routing: $Mode`n" } else { '' }
                $teamText = @(
                    '# Squad Roster'
                    $policy
                    '| Role | Member Name | Agent Name (Primary) | Alternate Agents | Model |'
                    '| ---- | ----------- | -------------------- | ---------------- | ----- |'
                    "| lead | Beta | Squad Lead | Squad Challenger | $Cell |"
                ) -join "`n"
                [IO.File]::WriteAllText((Join-Path $root 'team.md'), $teamText)
                $dispatch = @{ agent_type = $Agent; prompt = "$Prompt at $root" }
                if ($Model) { $dispatch.model = $Model }
                $inputData = switch ($Shape) {
                    'camel' { @{ cwd = $repo; toolName = 'task'; toolArgs = $dispatch } }
                    'encoded' { @{ cwd = $repo; toolName = 'task'; toolArgs = ($dispatch | ConvertTo-Json -Compress) } }
                    'pascal' { @{ cwd = $repo; tool_name = 'Agent'; tool_input = $dispatch } }
                    'batch' { @{ cwd = $repo; toolCalls = @(@{ id = 'fixture'; name = 'task'; args = $dispatch }) } }
                }
                $raw = $inputData | ConvertTo-Json -Depth 10 -Compress
                $output = $raw | & pwsh -NoProfile -File (Join-Path $script:OutputRoot 'hooks/scripts/dispatch-guards.ps1') 2>&1 | Out-String
                [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
            }
        }

        It 'denies a missing model from a native agent in a <Shape> payload' -ForEach @(
            @{ Shape = 'camel' }, @{ Shape = 'encoded' }, @{ Shape = 'pascal' }, @{ Shape = 'batch' }
        ) {
            $result = Invoke-DispatchGuard -Shape $Shape
            $result.ExitCode | Should -Be 0 -Because $result.Output
            ($result.Output | ConvertFrom-Json).permissionDecision | Should -Be 'deny'
            ($result.Output | ConvertFrom-Json).permissionDecisionReason | Should -Match 'Squad Lead'
        }

        It 'compares the exact Model cell under <Mode>' -ForEach @(
            @{ Mode = 'ranked' }, @{ Mode = 'manual' }, @{ Mode = 'economy' }
        ) {
            $wrong = Invoke-DispatchGuard -Mode $Mode -Model 'claude-sonnet-5.5'
            $wrong.ExitCode | Should -Be 0 -Because $wrong.Output
            ($wrong.Output | ConvertFrom-Json).permissionDecision | Should -Be 'deny'
            $correct = Invoke-DispatchGuard -Mode $Mode -Model 'gpt-5.6-sol'
            $correct.ExitCode | Should -Be 0 -Because $correct.Output
            ($correct.Output | ConvertFrom-Json).permissionDecision | Should -Be 'allow'
        }

        It 'denies unresolved cells and resolves a federation member using Windows paths' {
            $result = Invoke-DispatchGuard -Member -Cell ''
            $result.ExitCode | Should -Be 0 -Because $result.Output
            ($result.Output | ConvertFrom-Json).permissionDecision | Should -Be 'deny'
            ($result.Output | ConvertFrom-Json).permissionDecisionReason | Should -Match '-ApplyModelRouting'
        }

        It 'supports display names and native Alternate agent IDs' {
            foreach ($agent in @('Squad Lead', 'hve-squad:squad-challenger')) {
                $result = Invoke-DispatchGuard -Agent $agent
                $result.ExitCode | Should -Be 0 -Because $result.Output
                ($result.Output | ConvertFrom-Json).permissionDecision | Should -Be 'deny'
            }
        }

        It 'preserves off mode and the native Scribe exemption' {
            $off = Invoke-DispatchGuard -Mode ''
            $off.ExitCode | Should -Be 0 -Because $off.Output
            ($off.Output | ConvertFrom-Json).permissionDecision | Should -Be 'allow'
            $scribe = Invoke-DispatchGuard -Agent 'hve-squad:squad-scribe' -Prompt 'Record the request to create work items in Azure DevOps'
            $scribe.ExitCode | Should -Be 0 -Because $scribe.Output
            ($scribe.Output | ConvertFrom-Json).permissionDecision | Should -Be 'allow'
        }

        It 'retains the tracker-write gate for a native planning agent' {
            $result = Invoke-DispatchGuard -Mode '' -Prompt 'Create work items in Azure DevOps'
            $result.ExitCode | Should -Be 0 -Because $result.Output
            ($result.Output | ConvertFrom-Json).permissionDecision | Should -Be 'deny'
            ($result.Output | ConvertFrom-Json).permissionDecisionReason | Should -Match 'Tracker-Write Gate'
        }

        It 'runs an exported guard with its declared runtime dependencies and no plugin directory' {
            $repo = Join-Path $TestDrive 'cloud-guard-drop'
            $drop = Join-Path $repo '.github/hooks/hve-squad'
            $runtime = Join-Path $drop 'runtime'
            $squad = Join-Path $repo '.copilot-tracking/squad'
            $agents = Join-Path $repo '.github/agents'
            foreach ($path in @($runtime, $squad, $agents)) { $null = [IO.Directory]::CreateDirectory($path) }
            Copy-Item -LiteralPath (Join-Path $script:OutputRoot 'hooks/scripts/dispatch-guards.ps1') -Destination $drop
            foreach ($name in @('SquadCoordinator.psm1', 'Resolve-SquadConnectorDispatch.ps1', 'SquadAgentDiscovery.ps1')) {
                Copy-Item -LiteralPath (Join-Path $script:OutputRoot "skills/squad/scripts/$name") -Destination $runtime
            }
            [IO.File]::WriteAllText((Join-Path $agents 'squad-lead.agent.md'), "---`nname: Squad Lead`n---`n")
            $team = @('# Team', 'Model routing: ranked', '', '| Role | Agent Name (Primary) | Alternate Agents | Model |', '| ---- | -------------------- | ---------------- | ----- |', '| lead | Squad Lead | - | gpt-5.6-sol |') -join "`n"
            [IO.File]::WriteAllText((Join-Path $squad 'team.md'), $team)
            $inputData = @{ cwd = $repo; toolArgs = @{ agent_type = 'hve-squad:squad-lead'; prompt = 'Plan briefly' } } | ConvertTo-Json -Depth 5 -Compress
            $output = $inputData | & pwsh -NoProfile -File (Join-Path $drop 'dispatch-guards.ps1') 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 0 -Because $output
            ($output | ConvertFrom-Json).permissionDecision | Should -Be 'deny'
            ($output | ConvertFrom-Json).permissionDecisionReason | Should -Match 'Routed-model guard'
        }
    }

    It 'executes a generated Bash hook from outside the plugin directory' -Skip:($IsWindows -or -not (Get-Command bash -ErrorAction SilentlyContinue)) {
        $manifest = Get-Content -LiteralPath $script:HookManifestPath -Raw | ConvertFrom-Json
        $foreignWorkingDirectory = Join-Path $TestDrive 'consumer-repository'
        $sentinelPath = Join-Path $TestDrive 'bash-hook-ran'
        New-Item -ItemType Directory -Path $foreignWorkingDirectory -Force | Out-Null
        $previousPluginRoot = $env:CLAUDE_PLUGIN_ROOT
        $previousSentinel = $env:HOOK_SENTINEL

        try {
            $env:CLAUDE_PLUGIN_ROOT = $script:OutputRoot
            $env:HOOK_SENTINEL = $sentinelPath
            Push-Location $foreignWorkingDirectory
            & bash -c $manifest.hooks.sessionStart[0].bash
            $LASTEXITCODE | Should -Be 0
            Get-Content -LiteralPath $sentinelPath -Raw | Should -BeExactly 'bash'
        }
        finally {
            Pop-Location
            $env:CLAUDE_PLUGIN_ROOT = $previousPluginRoot
            $env:HOOK_SENTINEL = $previousSentinel
        }
    }

    It 'executes a PowerShell hook from outside the plugin directory' -Skip:(-not $IsWindows) {
        $manifest = Get-Content -LiteralPath $script:HookManifestPath -Raw | ConvertFrom-Json
        $foreignWorkingDirectory = Join-Path $TestDrive 'consumer-repository'
        $sentinelPath = Join-Path $TestDrive 'powershell-hook-ran'
        New-Item -ItemType Directory -Path $foreignWorkingDirectory -Force | Out-Null
        $previousPluginRoot = $env:CLAUDE_PLUGIN_ROOT
        $previousSentinel = $env:HOOK_SENTINEL

        try {
            $env:CLAUDE_PLUGIN_ROOT = $script:OutputRoot
            $env:HOOK_SENTINEL = $sentinelPath
            Push-Location $foreignWorkingDirectory
            & ([scriptblock]::Create($manifest.hooks.sessionStart[0].powershell))
            $LASTEXITCODE | Should -Be 0
            (Get-Content -LiteralPath $sentinelPath -Raw).Trim() | Should -BeExactly 'powershell'
        }
        finally {
            Pop-Location
            $env:CLAUDE_PLUGIN_ROOT = $previousPluginRoot
            $env:HOOK_SENTINEL = $previousSentinel
        }
    }

    It 'fails before publishing when a referenced hook script is absent' {
        Remove-Item -LiteralPath (Join-Path $script:OutputRoot 'hooks/scripts/session-start-check.ps1')

        { Write-PluginHookManifest -OutputRoot $script:OutputRoot } |
            Should -Throw '*Plugin hook scripts are missing from OutputRoot*session-start-check.ps1*'
    }

    It 'supports a dry run against an empty output root' {
        $dryRunRoot = Join-Path $TestDrive 'empty-dry-run-output'
        New-Item -ItemType Directory -Path $dryRunRoot -Force | Out-Null
        $script:OutputRootResolved = $dryRunRoot
        $script:GeneratedPaths = [System.Collections.Generic.List[string]]::new()

        { Write-PluginHookManifest -OutputRoot $dryRunRoot -DryRun } | Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $dryRunRoot 'hooks.json') | Should -BeFalse
    }
}