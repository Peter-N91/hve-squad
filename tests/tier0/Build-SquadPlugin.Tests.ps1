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

    It 'rewrites compact coordinator conventions for the plugin instructions channel' {
        $coordinator = Get-Content -LiteralPath (Join-Path $script:OutputRoot 'agents/squad/squad-coordinator.agent.md') -Raw
        $coordinator | Should -Not -Match '\.github/instructions/squad/|auto-apply through'
        $coordinator | Should -Match 'skills/squad/references/rules/'
        $coordinator | Should -Match 'they do not auto-apply at all'
        $coordinator | Should -Match 'Give each active pack'
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
            $entry.powershell | Should -Match '^powershell\.exe -NoProfile -ExecutionPolicy Bypass -File "\$env:CLAUDE_PLUGIN_ROOT/hooks/scripts/[a-z-]+\.ps1"$'
        }
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