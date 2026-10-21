#Requires -Modules Pester
#Requires -Version 7.4
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadInstall.psm1') -Force
    function Write-InstallFixture([string]$Root, [string]$Path, [string]$Value = 'fixture') {
        $Full = Join-Path $Root $Path
        New-Item -ItemType Directory -Path (Split-Path $Full -Parent) -Force | Out-Null
        Set-Content -LiteralPath $Full -Value $Value
    }
}

Describe 'Selected-source replacement' {
    It 'removes deleted legacy squad content and old native references while preserving dependencies' {
        $Install = Join-Path $TestDrive 'legacy'
        foreach ($Path in @(
            '.github/agents/squad-deleted.agent.md', '.github/agents/squad-renamed.agent.md',
            '.github/prompts/squad.prompt.md', '.github/instructions/squad-removed.instructions.md',
            '.github/instructions/pptx-brand-template.instructions.md',
            '.agents/skills/squad/references/deleted.md',
            '.agents/skills/squad/references/rules/squad-deleted.md',
            '.agents/skills/python-diagrams/deleted.txt'
        )) { Write-InstallFixture $Install $Path }
        $Dependencies = @('.github/agents/brd-builder.agent.md', '.github/instructions/retained.instructions.md', '.agents/skills/requirements-author/SKILL.md')
        foreach ($Path in $Dependencies) { Write-InstallFixture $Install $Path 'dependency bytes' }
        $Source = Join-Path $TestDrive 'selected'
        Write-InstallFixture $Source '.github/agents/squad/squad-new-name.agent.md' 'selected agent'
        Write-InstallFixture $Source '.github/skills/squad/SKILL.md' 'selected skill'
        Copy-SquadSource -From $Source -To $Install
        Test-Path (Join-Path $Install '.github/agents/squad-deleted.agent.md') | Should -BeFalse
        Test-Path (Join-Path $Install '.github/agents/squad-renamed.agent.md') | Should -BeFalse
        Test-Path (Join-Path $Install '.github/prompts/squad.prompt.md') | Should -BeFalse
        Test-Path (Join-Path $Install '.github/instructions/squad-removed.instructions.md') | Should -BeFalse
        Test-Path (Join-Path $Install '.github/instructions/pptx-brand-template.instructions.md') | Should -BeFalse
        Test-Path (Join-Path $Install '.agents/skills/squad/references/deleted.md') | Should -BeFalse
        Test-Path (Join-Path $Install '.agents/skills/squad/references/rules/squad-deleted.md') | Should -BeFalse
        Test-Path (Join-Path $Install '.agents/skills/python-diagrams') | Should -BeFalse
        Get-Content (Join-Path $Install '.github/agents/squad-new-name.agent.md') | Should -Be 'selected agent'
        foreach ($Path in $Dependencies) { Get-Content (Join-Path $Install $Path) | Should -Be 'dependency bytes' }
    }

    Describe 'PKG-16 Source-mode failure tolerance' {
        BeforeEach {
            $script:Source = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:AgentPath = 'squad-src/.github/agents/squad/squad-coach.agent.md'
            $script:PromptPath = 'squad-src/.github/prompts/squad/squad-coach.prompt.md'
            Write-InstallFixture $script:Source 'apm.yml' "name: hve-squad`nversion: 1.0.0"
            Write-InstallFixture $script:Source $script:AgentPath 'selected Coach agent'
            Write-InstallFixture $script:Source $script:PromptPath 'selected Coach prompt'
            $script:Destination = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        }

        It 'overlays an agent and prompt sharing a package slug after both missing-path failures' {
            $diagnostics = @(
                '+- hve-squad-squad-coach -- Failed to download dependency'
                'Peter-N91/hve-squad: Failed to download virtual package: File not found:'
                "$script:AgentPath in Peter-N91/hve-squad"
                "+- hve-squad-squad-coach -- File '$script:PromptPath' not found after git sparse checkout"
            )
            $install = { param($InstallArgs, $Target, $Attempt) [pscustomobject]@{ ExitCode = 1; Output = $diagnostics } }.GetNewClosure()
            $result = Install-SquadPackage -SourceRoot $script:Source -Destination $script:Destination -InstallCommand $install
            $result.Mode | Should -BeExactly 'Source'
            Get-Content -LiteralPath (Join-Path $result.Root '.github/agents/squad-coach.agent.md') |
                Should -BeExactly 'selected Coach agent'
            Get-Content -LiteralPath (Join-Path $result.Root '.github/prompts/squad-coach.prompt.md') |
                Should -BeExactly 'selected Coach prompt'
        }

        It 'rejects a separate unexplained dependency failure even beside tolerated self-references' {
            $diagnostics = @(
                "+- hve-squad-squad-coach -- File not found: $script:AgentPath in Peter-N91/hve-squad"
                '+- hve-core-other -- Authentication failed'
            )
            $install = { param($InstallArgs, $Target, $Attempt) [pscustomobject]@{ ExitCode = 1; Output = $diagnostics } }.GetNewClosure()
            { Install-SquadPackage -SourceRoot $script:Source -Destination $script:Destination -InstallCommand $install } |
                Should -Throw '*Unexplained failure for hve-core-other*'
        }

        It 'rejects a failed dependency path the selected overlay does not supply' {
            $diagnostics = @("+- hve-squad-missing -- File not found: squad-src/.github/agents/squad/missing.agent.md in Peter-N91/hve-squad")
            $install = { param($InstallArgs, $Target, $Attempt) [pscustomobject]@{ ExitCode = 1; Output = $diagnostics } }.GetNewClosure()
            { Install-SquadPackage -SourceRoot $script:Source -Destination $script:Destination -InstallCommand $install } |
                Should -Throw '*Not explained by the working copy*'
        }

        It 'does not tolerate missing content outside the squad overlay' {
            Write-InstallFixture $script:Source 'other/agent.md'
            $diagnostics = @('+- external-agent -- File not found: other/agent.md in external/package')
            $install = { param($InstallArgs, $Target, $Attempt) [pscustomobject]@{ ExitCode = 1; Output = $diagnostics } }.GetNewClosure()
            { Install-SquadPackage -SourceRoot $script:Source -Destination $script:Destination -InstallCommand $install } |
                Should -Throw '*Not explained by the working copy*'
        }

        It 'keeps published-ref installation failures fatal' {
            $diagnostics = @("+- hve-squad-squad-coach -- File not found: $script:AgentPath in Peter-N91/hve-squad")
            $install = { param($InstallArgs, $Target, $Attempt) [pscustomobject]@{ ExitCode = 1; Output = $diagnostics } }.GetNewClosure()
            { Install-SquadPackage -Ref main -Destination $script:Destination -InstallCommand $install } |
                Should -Throw '*apm install failed*'
        }
    }

    It 'tracks renamed nonreserved package paths across prepared overlays' {
        $Install = Join-Path $TestDrive 'prepared'
        $Older = Join-Path $TestDrive 'older-source'; $Selected = Join-Path $TestDrive 'newer-source'
        Write-InstallFixture $Older '.github/agents/custom/old.agent.md'
        Write-InstallFixture $Older '.github/instructions/custom/old.instructions.md'
        Write-InstallFixture $Older '.github/skills/old-skill/references/deleted.md'
        Copy-SquadSource -From $Older -To $Install
        Write-InstallFixture $Selected '.github/agents/custom/new.agent.md'
        Write-InstallFixture $Selected '.github/skills/new-skill/SKILL.md'
        Copy-SquadSource -From $Selected -To $Install
        foreach ($Path in @('.github/agents/old.agent.md', '.github/instructions/old.instructions.md', '.agents/skills/old-skill')) {
            Test-Path (Join-Path $Install $Path) | Should -BeFalse
        }
        Test-Path (Join-Path $Install '.github/agents/new.agent.md') | Should -BeTrue
        Test-Path (Join-Path $Install '.agents/skills/new-skill/SKILL.md') | Should -BeTrue
    }
}
