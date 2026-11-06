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
    $script:VersionGateScript = Join-Path $SourceRoot 'scripts/Assert-SquadPluginVersion.ps1'
    $script:PackRosterBody = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-roster.instructions.md') -Raw
    $script:ProgressSourcePath = Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/operating-procedure.md'
    $script:OutputRoot = Join-Path $TestDrive 'plugin-output'
    $script:HveCoreRoot = Join-Path $TestDrive 'hve-core'
    $script:HookScriptNames = @(
        'autonomous-escalation-check'
        'dispatch-guards'
        'impactful-action-gate'
        'notification-audit'
        'prompt-injection-note'
        'session-start-check'
        'state-write-guard'
    )

    $hveAgent = Join-Path $script:HveCoreRoot '.github/agents/security/security-planner.agent.md'
    $hveRule = Join-Path $script:HveCoreRoot '.github/instructions/security/identity.instructions.md'
    $hveSkill = Join-Path $script:HveCoreRoot '.github/skills/security/secure-by-design/SKILL.md'
    $hveExtension = Join-Path $script:HveCoreRoot '.github/extensions/hve-core/extension.json'
    foreach ($path in @($hveAgent, $hveRule, $hveSkill, $hveExtension)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    }
    Set-Content -LiteralPath $hveAgent -Value "---`nname: Security Planner`nmodel: claude-sonnet-5.5`n---`n# Security Planner`n" -Encoding utf8NoBOM
    Set-Content -LiteralPath $hveRule -Value "---`ndescription: Fixture rule`napplyTo: '**'`n---`n# Security rule`n" -Encoding utf8NoBOM
    Set-Content -LiteralPath $hveSkill -Value "---`nname: secure-by-design`ndescription: Fixture skill`n---`n# Secure by design`n" -Encoding utf8NoBOM
    Set-Content -LiteralPath $hveExtension -Value '{"name":"hve-core-fixture"}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $script:HveCoreRoot 'LICENSE') -Value 'MIT fixture' -Encoding utf8NoBOM
    $hveManifest = [ordered]@{
        name = 'hve-core'; version = '0.0.0-test'
        agents = @('.github/agents/security/security-planner.agent.md')
        commands = @()
        rules = @('.github/instructions/security/identity.instructions.md')
        skills = @('.github/skills/security/secure-by-design')
        extensions = @('.github/extensions/hve-core')
    }
    Set-Content -LiteralPath (Join-Path $script:HveCoreRoot 'plugin.json') `
        -Value (($hveManifest | ConvertTo-Json -Depth 6) + "`n") -Encoding utf8NoBOM

    function New-HveCoreGitFixture {
        param([Parameter(Mandatory)][string]$Name)
        $gitRoot = Join-Path $TestDrive $Name
        Copy-Item -LiteralPath $script:HveCoreRoot -Destination $gitRoot -Recurse
        & git -C $gitRoot init --quiet
        & git -C $gitRoot add -- .
        & git -C $gitRoot -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m fixture
        [pscustomobject]@{
            Root   = $gitRoot
            Commit = (& git -C $gitRoot rev-parse HEAD).Trim()
        }
    }

    function Invoke-PluginHookEntry {
        param(
            [Parameter(Mandatory)]$Entry,
            [Parameter(Mandatory)][string]$InputText
        )
        if ($IsWindows) {
            $command = [regex]::Match(
                $Entry.powershell,
                '^(?<exe>powershell\.exe|pwsh) -NoProfile -ExecutionPolicy Bypass -File "(?<path>[^"]+)"$'
            )
            if (-not $command.Success) { throw "Unexpected PowerShell hook command: $($Entry.powershell)" }
            $executable = $command.Groups['exe'].Value
            $scriptPath = $command.Groups['path'].Value
            return $InputText |
                & $executable -NoProfile -ExecutionPolicy Bypass -File $scriptPath |
                Out-String
        }
        return $InputText | & bash -c $Entry.bash | Out-String
    }

    $pwsh = (Get-Process -Id $PID).Path
    $script:BuildOutput = @(
        & $pwsh -NoProfile -File $script:BuildScript `
            -SourceRoot $SourceRoot `
            -OutputRoot $script:OutputRoot `
            -HveCoreRoot $script:HveCoreRoot `
            -AllowUnverifiedHveCoreSource 2>&1
    )
    $script:BuildExitCode = $LASTEXITCODE

    $script:RootManifestPath = Join-Path $script:OutputRoot 'plugin.json'
    $script:NestedManifestPath = Join-Path $script:OutputRoot '.github/plugin/plugin.json'
    $script:MarketplaceManifestPath = Join-Path $script:OutputRoot '.github/plugin/marketplace.json'
    $script:HveCoreSourcePath = Join-Path $script:OutputRoot '.github/plugin/hve-core-source.json'
    $script:HookManifestPath = Join-Path $script:OutputRoot 'hooks.json'
    . $script:BuildScript
}

Describe 'PKG-14 Plugin host discovery and hook commands' -Tag 'Unit' {
    It 'builds the plugin distribution successfully' {
        $script:BuildExitCode | Should -Be 0 -Because ($script:BuildOutput -join "`n")
    }

    It 'ships bundled-plugin discovery and both coordinator entry contracts' {
        Test-Path -LiteralPath (Join-Path $script:OutputRoot 'skills/squad/scripts/SquadAgentDiscovery.ps1') | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $script:OutputRoot 'skills/squad/references/agent-discovery.md') -Raw |
            Should -Match 'bundles its pinned HVE Core cast in the same'
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

    It 'ships the selectable and dispatchable Doctor with its scripted invocation (DOC-01)' {
        $agent = Get-Content -LiteralPath (Join-Path $script:OutputRoot 'agents/squad/squad-doctor.agent.md') -Raw
        $agent | Should -Match '(?m)^user-invocable: true\r?$'
        $agent | Should -Not -Match '(?m)^disable-model-invocation: true\r?$'
        $skill = Get-Content -LiteralPath (Join-Path $script:OutputRoot 'skills/squad/invocations/squad-doctor/SKILL.md') -Raw
        $skill | Should -Match 'Dispatch to \*\*Squad Doctor\*\*'
        $skill | Should -Not -Match 'perform it directly'
        Test-Path -LiteralPath (Join-Path $script:OutputRoot 'skills/squad/scripts/Invoke-SquadDoctor.ps1') | Should -BeTrue
        $source = [pscustomobject]@{ Mode = 'Source'; SourceRoot = (Join-Path $TestDrive 'no-doctor') }
        $skills = New-InvocationSkillContent -Source $source -RepoRoot $script:SourceRootResolved
        $skills.Contains('squad-doctor') | Should -BeFalse
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
        foreach ($legalFile in @('LICENSE', 'NOTICE')) {
            Copy-Item -LiteralPath (Join-Path $script:SourceRootResolved $legalFile) -Destination $historicalRoot
        }
        $coachPaths = @(
            'squad-src/.github/agents/squad/squad-coach.agent.md'
            'squad-src/.github/prompts/squad/squad-coach.prompt.md'
        )
        foreach ($path in $coachPaths) { Remove-Item -LiteralPath (Join-Path $historicalRoot $path) }
        & git -C $historicalRoot init --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize historical-source fixture.' }
        & git -C $historicalRoot add -- apm.yml LICENSE NOTICE squad-src
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
            -HveCoreRoot $script:HveCoreRoot -AllowUnverifiedHveCoreSource -DryRun 2>&1)
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

    It 'publishes one self-contained plugin with the bundled HVE Core components' {
        $manifest = Get-Content -LiteralPath $script:RootManifestPath -Raw | ConvertFrom-Json
        $manifest.name | Should -BeExactly 'hve-squad'
        @($manifest.agents) | Should -Contain 'agents/squad/'
        @($manifest.agents) | Should -Contain '.github/agents/security/security-planner.agent.md'
        @($manifest.rules) | Should -Contain '.github/instructions/security/identity.instructions.md'
        @($manifest.skills) | Should -Contain '.github/skills/security/secure-by-design'
        @($manifest.extensions) | Should -Contain '.github/extensions/hve-core'
        Test-Path -LiteralPath (Join-Path $script:OutputRoot '.github/agents/security/security-planner.agent.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:OutputRoot '.github/skills/security/secure-by-design/SKILL.md') | Should -BeTrue
    }

    It 'records the exact HVE Core pin from apm.yml' {
        $expected = [regex]::Match(
            (Get-Content -LiteralPath (Join-Path $script:SourceRootResolved 'apm.yml') -Raw),
            'microsoft/hve-core/[^\s#]+#([0-9a-f]{40})'
        ).Groups[1].Value
        $source = Get-Content -LiteralPath $script:HveCoreSourcePath -Raw | ConvertFrom-Json
        $source.repository | Should -BeExactly 'microsoft/hve-core'
        $source.commit | Should -BeExactly $expected
        $source.version | Should -BeExactly '0.0.0-test'
        @($source.files).source | Should -Contain '.github/agents/security/security-planner.agent.md'
    }

    It 'exposes one relative marketplace entry and no bundled MCP connection' {
        $marketplace = Get-Content -LiteralPath $script:MarketplaceManifestPath -Raw | ConvertFrom-Json
        @($marketplace.plugins) | Should -HaveCount 1
        $marketplace.name | Should -BeExactly 'hve-squad'
        $marketplace.plugins[0].name | Should -BeExactly 'hve-squad'
        $marketplace.plugins[0].source | Should -BeExactly '.'

        $manifest = Get-Content -LiteralPath $script:RootManifestPath -Raw | ConvertFrom-Json -AsHashtable
        $manifest.ContainsKey('$schema') | Should -BeFalse
        $manifest.ContainsKey('mcpServers') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:OutputRoot '.mcp.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:OutputRoot 'mcp.json') | Should -BeFalse
    }

    It 'publishes stable and preview plugins manually from this repository' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:SourceRootResolved '.github/workflows/publish-plugin.yml') -Raw
        $workflow | Should -Match '(?m)^\s*workflow_dispatch:\s*$'
        $workflow | Should -Match 'TARGET_BRANCH=plugin-preview'
        $workflow | Should -Match 'TARGET_BRANCH=plugin'
        $workflow | Should -Match 'GITHUB_REPOSITORY'
        $workflow | Should -Match 'Assert-SquadPluginVersion\.ps1'
        $workflow | Should -Not -Match 'Peter-N91/hve-squad-plugin|HVE_SQUAD_PLUGIN_PUSH_TOKEN|mcp-version'
    }

    It 'rejects prerelease content on the stable channel' {
        $output = @(& pwsh -NoProfile -File $script:VersionGateScript `
                -Channel stable -NewVersion '0.19.3-pre' -OldVersion '0.19.3' 2>&1)
        $LASTEXITCODE | Should -Be 1
        $output -join "`n" | Should -Match 'Stable plugin publication requires'
    }

    It 'uses SemVer ordering to reject a stable rollback' {
        $output = @(& pwsh -NoProfile -File $script:VersionGateScript `
                -Channel stable -NewVersion '0.19.2' -OldVersion '0.19.3' 2>&1)
        $LASTEXITCODE | Should -Be 1
        $outputText = ($output -join "`n") -replace '\x1B\[[0-9;]*m', ''
        $outputText = $outputText -replace '\r?\n\s*(?:\|\s*)?', ' '
        $outputText | Should -Match 'backwards from 0\.19\.3 to 0\.19\.2'
    }

    It 'accepts forward stable and preview publication versions' -ForEach @(
        @{ Channel = 'stable'; Old = '0.19.3'; New = '0.19.4' }
        @{ Channel = 'preview'; Old = '0.20.0-pre.run.1'; New = '0.20.0-pre.run.2' }
        @{ Channel = 'preview'; Old = '0.20.0-pre.run.9'; New = '0.20.0-pre.run.10' }
        @{ Channel = 'preview'; Old = '0.20.0-pre.run.99'; New = '0.20.0-pre.run.100' }
    ) {
        $output = @(& pwsh -NoProfile -File $script:VersionGateScript `
                -Channel $Channel -NewVersion $New -OldVersion $Old 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }

    It 'declares Windows macOS and Linux plugin conformance' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:SourceRootResolved '.github/workflows/plugin-conformance.yml') -Raw
        foreach ($runner in @('windows-latest', 'macos-latest', 'ubuntu-latest')) {
            $workflow | Should -Match ([regex]::Escape($runner))
        }
        foreach ($hostName in @('vscode', 'cli', 'app')) {
            $workflow | Should -Match "'$hostName'"
        }
    }

    It 'rejects an HVE Core checkout whose commit differs from apm.yml' {
        $fixture = New-HveCoreGitFixture -Name 'hve-core-wrong-commit'
        {
            Copy-HveCorePluginContent -HveCoreRoot $fixture.Root `
                -ExpectedCommit ('0' * 40) `
                -OutputRoot (Join-Path $TestDrive 'wrong-pin-output')
        } | Should -Throw '*apm.yml pins*'
    }

    It 'rejects modified or untracked HVE Core content before copying <Kind>' -ForEach @(
        @{ Kind = 'tracked' }
        @{ Kind = 'untracked' }
    ) {
        $fixture = New-HveCoreGitFixture -Name "hve-core-dirty-$Kind"
        if ($Kind -eq 'tracked') {
            Add-Content -LiteralPath (Join-Path $fixture.Root '.github/agents/security/security-planner.agent.md') `
                -Value '# dirty'
        }
        else {
            Set-Content -LiteralPath (Join-Path $fixture.Root '.github/agents/security/untracked.agent.md') `
                -Value '# untracked'
        }
        {
            Copy-HveCorePluginContent -HveCoreRoot $fixture.Root `
                -ExpectedCommit $fixture.Commit `
                -OutputRoot (Join-Path $TestDrive "dirty-output-$Kind")
        } | Should -Throw '*must be clean before publication*'
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
            $entry.cwd | Should -BeExactly '${PLUGIN_ROOT}'
            $entry.bash | Should -Match '^bash "hooks/scripts/[a-z-]+\.sh"$'
            $entry.powershell | Should -Match '^(powershell\.exe|pwsh) -NoProfile -ExecutionPolicy Bypass -File "hooks/scripts/[a-z-]+\.ps1"$'
        }
        $manifest.hooks.preToolUse[2].powershell | Should -Match '^pwsh '
    }

    It 'publishes every hook script from this repository without a distribution-only source' {
        foreach ($name in $script:HookScriptNames) {
            foreach ($extension in @('ps1', 'sh')) {
                $source = Join-Path $script:SourceRootResolved "scripts/plugin-hooks/$name.$extension"
                $generated = Join-Path $script:OutputRoot "hooks/scripts/$name.$extension"
                Test-Path -LiteralPath $source -PathType Leaf | Should -BeTrue
                Test-Path -LiteralPath $generated -PathType Leaf | Should -BeTrue
                (Get-FileHash -LiteralPath $generated).Hash |
                    Should -BeExactly (Get-FileHash -LiteralPath $source).Hash
            }
        }
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
        $dropSkill | Should -Match 'can be listed yet not fire'
        $dropSkill | Should -Match 'Copy both script variants'
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

    It 'executes a generated Bash hook through the plugin-root working directory' -Skip:($IsWindows -or -not (Get-Command bash -ErrorAction SilentlyContinue)) {
        $manifest = Get-Content -LiteralPath $script:HookManifestPath -Raw | ConvertFrom-Json
        $foreignWorkingDirectory = Join-Path $TestDrive 'consumer-repository'
        New-Item -ItemType Directory -Path $foreignWorkingDirectory -Force | Out-Null

        try {
            Push-Location $manifest.hooks.sessionStart[0].cwd.Replace('${PLUGIN_ROOT}', $script:OutputRoot)
            $inputData = @{ cwd = $foreignWorkingDirectory } | ConvertTo-Json -Compress
            $output = $inputData | & bash -c $manifest.hooks.sessionStart[0].bash | Out-String
            $LASTEXITCODE | Should -Be 0
            ($output | ConvertFrom-Json).additionalContext | Should -Match 'No squad state detected'
        }
        finally {
            Pop-Location
        }
    }

    It 'executes a PowerShell hook through the plugin-root working directory' -Skip:(-not $IsWindows) {
        $manifest = Get-Content -LiteralPath $script:HookManifestPath -Raw | ConvertFrom-Json
        $foreignWorkingDirectory = Join-Path $TestDrive 'consumer-repository'
        New-Item -ItemType Directory -Path $foreignWorkingDirectory -Force | Out-Null

        try {
            Push-Location $manifest.hooks.sessionStart[0].cwd.Replace('${PLUGIN_ROOT}', $script:OutputRoot)
            $inputData = @{ cwd = $foreignWorkingDirectory } | ConvertTo-Json -Compress
            $output = Invoke-PluginHookEntry -Entry $manifest.hooks.sessionStart[0] -InputText $inputData
            $LASTEXITCODE | Should -Be 0
            ($output | ConvertFrom-Json).additionalContext | Should -Match 'No squad state detected'
        }
        finally {
            Pop-Location
        }
    }

    It 'installs the plugin with Copilot CLI and validates a blocking hook command from the installed root' -Skip:(-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
        $copilotHome = Join-Path $TestDrive 'copilot-hook-smoke'
        $previousCopilotHome = $env:COPILOT_HOME
        $locationPushed = $false
        try {
            $env:COPILOT_HOME = $copilotHome
            $installOutput = @(& copilot plugin install $script:OutputRoot 2>&1)
            $LASTEXITCODE | Should -Be 0 -Because ($installOutput -join "`n")

            $installedRoot = @(
                Get-ChildItem -LiteralPath $copilotHome -Recurse -File -Filter plugin.json |
                    Where-Object {
                        (Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json).name -eq 'hve-squad' -and
                        (Test-Path -LiteralPath (Join-Path $_.DirectoryName 'hooks.json') -PathType Leaf)
                    } |
                    ForEach-Object { Split-Path -Parent $_.FullName }
            ) | Select-Object -First 1
            $installedRoot | Should -Not -BeNullOrEmpty

            $hooks = Get-Content -LiteralPath (Join-Path $installedRoot 'hooks.json') -Raw | ConvertFrom-Json
            $entry = @($hooks.hooks.preToolUse)[0]
            $entry.matcher | Should -BeExactly 'bash|powershell'
            $entry.cwd | Should -BeExactly '${PLUGIN_ROOT}'
            Push-Location $entry.cwd.Replace('${PLUGIN_ROOT}', $installedRoot)
            $locationPushed = $true
            $payload = @{
                toolName = 'powershell'
                toolArgs = @{ command = "Write-Output 'git push'" }
            } | ConvertTo-Json -Depth 5 -Compress
            $output = Invoke-PluginHookEntry -Entry $entry -InputText $payload
            $LASTEXITCODE | Should -Be 0 -Because $output
            ($output | ConvertFrom-Json).permissionDecision | Should -BeExactly 'ask'
        }
        finally {
            if ($locationPushed) { Pop-Location }
            $env:COPILOT_HOME = $previousCopilotHome
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