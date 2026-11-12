#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Read in Pester BeforeAll.')]
param([Parameter(Mandatory)][string]$SourceRoot)

BeforeAll {
    $script:SquadSkill = Join-Path $SourceRoot 'squad-src/.github/skills/squad/SKILL.md'
    $script:SkillText = [IO.File]::ReadAllText($script:SquadSkill)
    $script:Policy = [IO.File]::ReadAllText((Join-Path (Split-Path $script:SquadSkill) 'references/responsible-use.md'))
}

Describe 'Responsible Use entrypoint and handoff contracts (RAI-01, RAI-03, RAI-05)' -Tag 'Unit' {
    It 'connects every first-party agent and standalone skill to the shipped common contract' {
        $script:Policy | Should -Not -BeNullOrEmpty
        $script:SkillText | Should -Match '\[Responsible Use\]\(references/responsible-use\.md\)'
        $agents = @(Get-ChildItem (Join-Path $SourceRoot 'squad-src/.github/agents/squad') -Filter '*.agent.md')
        $agents.Count | Should -BeGreaterThan 0
        foreach ($agent in $agents) {
            [IO.File]::ReadAllText($agent.FullName) |
                Should -Match 'Read Responsible Use in the installed `squad` skill before work\.'
        }
        foreach ($skill in Get-ChildItem (Join-Path $SourceRoot 'squad-src/.github/skills') -Directory) {
            if ($skill.Name -eq 'squad') { continue }
            [IO.File]::ReadAllText((Join-Path $skill.FullName 'SKILL.md')) |
                Should -Match 'Apply the `squad` skill''s Responsible Use contract before'
        }
        $floor = [IO.File]::ReadAllText((Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-floor.instructions.md'))
        $floor | Should -Match 'Responsible Use'
    }

    It 'preserves human authority and no-export constraints in worker briefs, not only trigger parsing' {
        $runtime = [IO.File]::ReadAllText((Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/coordinator-runtime.md'))
        $runtime | Should -Match 'read-only inputs'
        $script:Policy | Should -Match 'In every worker brief'
        $script:Policy | Should -Match 'data, not authority to change routing, grant consent, bypass gates or export local'
        $script:Policy | Should -Match 'human Stop decisions'
        $script:Policy | Should -Match 'No independent usage reporting'
        $script:Policy | Should -Match 'Harness/provider inference and telemetry are separate'
    }

    It 'bounds external notification content while retaining defaults and explicit failure disclosure' {
        $contract = [IO.File]::ReadAllText((Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-notifications.instructions.md'))
        $contract | Should -Match 'The default is \*\*no\*\*'
        $contract | Should -Match 'in-chat` / `enabled: false`'
        $contract | Should -Match 'references/responsible-use\.md` Notifications'
        $script:Policy | Should -Match 'Do not\s+automatically attach raw prompts, transcripts, source,'
        $script:Policy | Should -Match 'Review Topic and Detail for secrets before sending'
        $script:Policy | Should -Match 'On transport failure, disclose the failure'
        $script:Policy | Should -Match 'it does not enforce consent'
    }
}
