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
