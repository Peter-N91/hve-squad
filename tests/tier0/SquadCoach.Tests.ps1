#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    Set-StrictMode -Version Latest
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $model = Get-SquadPackageModel -PackageRoot $PackageRoot
    $script:CoachAgent = @($model.SquadAgents | Where-Object Name -eq 'squad-coach.agent.md')
    $script:CoachPrompt = @($model.Prompts | Where-Object Name -eq 'squad-coach.prompt.md')
    $script:SquadPrompt = @($model.Prompts | Where-Object Name -eq 'squad.prompt.md')
    $script:InventoryScript = Join-Path $PackageRoot '.agents/skills/squad/scripts/Get-SquadCoachContext.ps1'
    $script:InitProcedure = Get-Content -LiteralPath (Join-Path $PackageRoot '.agents/skills/squad/references/operating-procedure.md') -Raw
    $script:DiscoveryContract = Get-Content -LiteralPath (Join-Path $PackageRoot '.agents/skills/squad/references/coach-discovery.md') -Raw
    $script:AdmissionReference = Get-Content -LiteralPath (Join-Path $PackageRoot '.agents/skills/squad/references/consumption.md') -Raw

    function Write-CoachFixture {
        param([string]$Path, [string]$Content)
        New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
        Set-Content -LiteralPath $Path -Value $Content -Encoding utf8NoBOM
    }

    function New-CoachFixture {
        param([ValidateSet('Source', 'Apm', 'Plugin')][string]$Layout = 'Apm')
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $package = if ($Layout -eq 'Plugin') { Join-Path $repo 'selected-plugin' } else { $repo }
        $skill = switch ($Layout) {
            'Source' { Join-Path $package 'squad-src/.github/skills/squad' }
            'Apm' { Join-Path $package '.agents/skills/squad' }
            'Plugin' { Join-Path $package 'skills/squad' }
        }
        $artifacts = switch ($Layout) {
            'Source' { Join-Path $package 'squad-src/.github' }
            'Apm' { Join-Path $package '.github' }
            'Plugin' { $package }
        }
        Write-CoachFixture (Join-Path $skill 'SKILL.md') "---`nname: squad`n---`n# Squad`n"
        Write-CoachFixture (Join-Path $skill 'references/00-index.md') "# Index`n"
        $agent = if ($Layout -eq 'Apm') { 'agents/squad-future.agent.md' } else { 'agents/squad/squad-future.agent.md' }
        Write-CoachFixture (Join-Path $artifacts $agent) @'
---
name: Squad Future
description: "A future capability discovered without editing the Coach"
user-invocable: true
disable-model-invocation: true
argument-hint: "request=... [future=...]"
---
# Future Workflow
## Inputs
Read the source before advising.
'@
        $prompt = if ($Layout -eq 'Apm') { 'prompts/squad-future.prompt.md' } else { 'prompts/squad/squad-future.prompt.md' }
        if ($Layout -eq 'Plugin') {
            Write-CoachFixture (Join-Path $skill 'invocations/squad-future/SKILL.md') "---`nname: squad-future`n---`n# Future Invocation`n"
            Write-CoachFixture (Join-Path $package 'plugin.json') '{"name":"hve-squad"}'
        }
        else {
            Write-CoachFixture (Join-Path $artifacts $prompt) "---`nagent: Squad Future`nargument-hint: future=...`n---`n# Future Prompt`n"
            if ($Layout -eq 'Source') {
                Write-CoachFixture (Join-Path $package 'apm.yml') "name: hve-squad`nversion: 1.0.0"
            }
        }
        [pscustomobject]@{ Repo = $repo; Package = $package; Skill = $skill }
    }

    function Get-CoachTreeSnapshot {
        param([string]$Root)
        (Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
            $hash = if ($_.PSIsContainer) { '' } else { (Get-FileHash -LiteralPath $_.FullName).Hash }
            $modified = if ($_.PSIsContainer) { '' } else { $_.LastWriteTimeUtc.Ticks }
            "$($_.FullName)|$modified|$hash"
        }) -join "`n"
    }

    function Get-CoachInventory {
        param([pscustomobject]$Fixture)
        & $script:InventoryScript -RepoRoot $Fixture.Repo -SkillRoot $Fixture.Skill | ConvertFrom-Json
    }
}

Describe 'Squad Coach entrypoint and packaging' {
    It 'delivers one user-invocable Coach and one bound prompt' {
        $script:CoachAgent | Should -HaveCount 1
        $script:CoachPrompt | Should -HaveCount 1
        $script:CoachAgent[0].Meta['name'] | Should -BeExactly 'Squad Coach'
        $script:CoachAgent[0].Meta['user-invocable'] | Should -BeExactly 'true'
        $script:CoachAgent[0].Meta['disable-model-invocation'] | Should -BeExactly 'true'
        $script:CoachPrompt[0].Meta['agent'] | Should -BeExactly 'Squad Coach'
    }

    It 'limits the Coach to portable read-only tools' {
        @($script:CoachAgent[0].Meta['tools']) | Should -HaveCount 2
        $script:CoachAgent[0].Meta['tools'] | Should -Contain 'read'
        $script:CoachAgent[0].Meta['tools'] | Should -Contain 'search'
    }

    It 'surfaces the Coach once on the fresh path without interrupting existing squads' {
        $script:SquadPrompt | Should -HaveCount 1
        $script:SquadPrompt[0].Body | Should -Match 'mention the advisory Squad Coach once'
        $script:SquadPrompt[0].Body | Should -Match 'never repeat the hint after either state file exists'
        $script:InitProcedure | Should -Match 'Offer unsure users Squad Coach once before first Init'
        $script:InitProcedure | Should -Match 'pause for manual selection'
    }
}

Describe 'Squad Coach behavior contract' {
    BeforeAll {
        $script:Body = $script:CoachAgent[0].Body
    }

    It 'works before initialization and adapts to existing state' {
        $script:Body | Should -Match 'No squad state is required'
        $script:Body | Should -Match 'neither `team\.md` nor `federation\.md`'
        $script:Body | Should -Match 'When `federation\.md` exists'
        $script:Body | Should -Match 'When only `team\.md` exists'
    }

    It 'derives current recommendations from shipped sources instead of a copied feature list' {
        $script:Body | Should -Match 'installed package is the source of truth'
        $script:Body | Should -Match 'references/00-index\.md'
        $script:Body | Should -Match 'references/coach-discovery\.md'
        $script:Body | Should -Match 'read the owning implementation and documentation'
        $script:Body | Should -Match 'Read exact agent inputs and entrypoint requirements'
        $script:Body | Should -Match 'Never invent a command, flag, profile, pack, role, model, or capability'
        $script:Body | Should -Not -Match '/squad-federation promote|mode=autopilot|routing=ranked|references/profiles-and-packs\.md'
    }

    It 'covers topology and end-to-end transitions without embedding feature recipes' {
        $script:Body | Should -Match 'simplest sufficient setup'
        $script:Body | Should -Match 'single squad'
        $script:Body | Should -Match 'federation'
        $script:Body | Should -Match 'per-member profile'
        $script:Body | Should -Match 'prerequisite setup and transitions'
        $script:Body | Should -Match 'Preserve completed setup'
    }

    It 'closes admission prerequisites through seed defaults without hardcoding a workflow' {
        $script:Body | Should -Match 'admission conditions'
        $script:Body | Should -Match 'seed defaults'
        $script:Body | Should -Match 'bounded line ranges'
        $script:Body | Should -Match 'readiness evidence table'
        $script:Body | Should -Not -Match 'calibrat|cost-ceiling|observations|last_reconciled'
        $script:DiscoveryContract | Should -Match '## Prerequisite Closure'
        $script:DiscoveryContract | Should -Match '## Retrieval Completeness'
        $script:DiscoveryContract | Should -Match 'even when the tool reports success'
        $script:DiscoveryContract | Should -Match 'access or policy refusal'
        $script:DiscoveryContract | Should -Match 'do not try alternate routes'
        $script:DiscoveryContract | Should -Match 'Read linked seed/default files themselves'
        $script:DiscoveryContract | Should -Match 'initial or effective value'
        $script:DiscoveryContract | Should -Match 'producer identity, scope, revision, and observation window'
        $script:DiscoveryContract | Should -Match '\| Transition \| Admission condition \| Initial/effective value \|'
        $script:DiscoveryContract | Should -Match 'Carry every condition'
        $script:DiscoveryContract | Should -Match 'one row per predicate'
        $script:AdmissionReference | Should -Match 'Get-SquadUsage\.ps1'
        $script:AdmissionReference | Should -Match 'Missing identities, non-complete credit status.*`cannot-confirm`'
        $script:DiscoveryContract | Should -Match 'unmet or unverified'
        $script:DiscoveryContract | Should -Match 'before its dependent'
        $script:DiscoveryContract | Should -Match 'Never fabricate'
        $script:DiscoveryContract | Should -Match 'explicit approval'
        $script:DiscoveryContract | Should -Match 'every copy-ready'
    }

    It 'requires disk-scope evidence before reporting artifacts absent' {
        $script:Body | Should -Match 'source-defined artifact scope'
        $script:DiscoveryContract | Should -Match '## Artifact Scope'
        $script:DiscoveryContract | Should -Match 'not just state or history'
        $script:DiscoveryContract | Should -Match 'unverified, not absent'
        $script:DiscoveryContract | Should -Match 'Resolve expected output paths'
        $script:DiscoveryContract | Should -Match 'does not install or update'
    }

    It 'returns preparation and invocation material beginners can act on' {
        $script:Body | Should -Match 'essential inputs'
        $script:Body | Should -Match 'optional inputs'
        $script:Body | Should -Match 'copy-ready'
        $script:Body | Should -Match 'Copilot CLI'
        $script:Body | Should -Match 'Copilot App'
        $script:Body | Should -Match 'VS Code'
        $script:Body | Should -Match 'detailed, ordered runbook'
        $script:Body | Should -Match 'expected outputs and required confirmations'
        $script:Body | Should -Match 'cite the source path or documentation section'
        $script:Body | Should -Match 'progress'
        $script:Body | Should -Match 'resume'
        $script:Body | Should -Match 'VS Code:\*\* select the owning agent'
        $script:Body | Should -Match 'Do not prescribe a Squad slash command'
    }

    It 'is advisory-only and never asks for secrets' {
        $script:Body | Should -Match 'Coaching is advisory-only'
        $script:Body | Should -Match 'Never initialize, dispatch, migrate, write, edit, or delete'
        $script:Body | Should -Match 'Even when the user asks you to perform delivery work'
        $script:Body | Should -Match 'Never ask the user to paste secrets'
    }
}

Describe 'COACH-07 Deterministic source discovery' {
    It 'ships the read-only helper and its portable discovery contract' {
        Test-Path -LiteralPath $script:InventoryScript -PathType Leaf | Should -BeTrue
        $contract = Get-Content -LiteralPath (Join-Path $PackageRoot '.agents/skills/squad/references/coach-discovery.md') -Raw
        $contract | Should -Match 'portable read/search-only'
        $contract | Should -Match '\.github/prompts/\*\.prompt\.md'
        $contract | Should -Match 'consumer project'
        $contract | Should -Match 'version mismatch'
    }

    It 'discovers <Layout> entrypoints before initialization and writes nothing' -ForEach @(
        @{ Layout = 'Source' }
        @{ Layout = 'Apm' }
        @{ Layout = 'Plugin' }
    ) {
        $fixture = New-CoachFixture -Layout $Layout
        $before = Get-CoachTreeSnapshot -Root $fixture.Repo
        $inventory = Get-CoachInventory -Fixture $fixture
        $inventory.schemaVersion | Should -Be 1
        $inventory.state.kind | Should -BeExactly 'none'
        $inventory.tracking.root | Should -BeExactly (Join-Path $fixture.Repo '.copilot-tracking')
        @($inventory.tracking.directories) | Should -HaveCount 0
        @($inventory.tracking.files) | Should -HaveCount 0
        $agents = @($inventory.entrypoints | Where-Object kind -eq 'agent')
        $agents | Should -HaveCount 1
        $agents[0].metadata.name | Should -BeExactly 'Squad Future'
        @($inventory.sources | Where-Object kind -eq 'reference').Count | Should -BeGreaterThan 0
        $entrypointKind = if ($Layout -eq 'Plugin') { 'invocation' } else { 'prompt' }
        $entrypoints = @($inventory.entrypoints | Where-Object kind -eq $entrypointKind)
        $entrypoints | Should -HaveCount 1
        if ($entrypointKind -eq 'prompt') {
            $entrypoints[0].metadata.agent | Should -BeExactly 'Squad Future'
        }
        if ($Layout -eq 'Apm') {
            Test-Path -LiteralPath (Join-Path $fixture.Repo '.github/prompts/squad') | Should -BeFalse
            $inventory.entrypoints.path | Should -Contain (Join-Path $fixture.Repo '.github/prompts/squad-future.prompt.md')
        }
        Get-CoachTreeSnapshot -Root $fixture.Repo | Should -BeExactly $before
    }

    It 'discovers new documentation, references, script parameters, and agents without executing code' {
        $fixture = New-CoachFixture -Layout Source
        Write-CoachFixture (Join-Path $fixture.Package 'README.md') "# Product documentation`n"
        Write-CoachFixture (Join-Path $fixture.Package 'docs/new-workflow.html') '<h1>A newly shipped workflow</h1>'
        Write-CoachFixture (Join-Path $fixture.Skill 'references/new-workflow.md') "# Future Capability`n## New transition`n"
        Write-CoachFixture (Join-Path $fixture.Skill 'scripts/Future-Workflow.ps1') 'param([string]$NewInput); throw "Discovery must not execute this script."'
        Write-CoachFixture (Join-Path $fixture.Skill 'scripts/future-language.py') 'raise RuntimeError("Discovery must not execute this source.")'
        $before = Get-CoachTreeSnapshot -Root $fixture.Repo
        $inventory = Get-CoachInventory -Fixture $fixture
        $inventory.sources.headings | Should -Contain 'A newly shipped workflow'
        $inventory.sources.headings | Should -Contain 'New transition'
        $scriptSource = @($inventory.sources | Where-Object path -Like '*Future-Workflow.ps1')
        $scriptSource | Should -HaveCount 1
        $scriptSource[0].parameters | Should -Contain 'NewInput'
        $inventory.sources.path | Should -Contain (Join-Path $fixture.Skill 'scripts/future-language.py')
        $agent = @($inventory.entrypoints | Where-Object kind -eq 'agent')[0]
        $agent.metadata.'argument-hint' | Should -BeExactly 'request=... [future=...]'
        Get-CoachTreeSnapshot -Root $fixture.Repo | Should -BeExactly $before
    }

    It 'does not mistake consumer documentation for the product installation guide' {
        $fixture = New-CoachFixture
        Write-CoachFixture (Join-Path $fixture.Repo 'README.md') '# Consumer project, not HVE Squad'
        Write-CoachFixture (Join-Path $fixture.Repo 'docs/getting-started.html') '<h1>Consumer deployment instructions</h1>'
        $inventory = Get-CoachInventory -Fixture $fixture
        @($inventory.documentationRoots) | Should -HaveCount 0
        @($inventory.sources | Where-Object kind -eq 'documentation') | Should -HaveCount 0
    }

    It 'detects existing squad state with federation precedence and leaves it unchanged' {
        $fixture = New-CoachFixture
        $squad = Join-Path $fixture.Repo '.copilot-tracking/squad'
        Write-CoachFixture (Join-Path $squad 'team.md') '# Existing team'
        (Get-CoachInventory -Fixture $fixture).state.kind | Should -BeExactly 'squad'
        Write-CoachFixture (Join-Path $squad 'federation.md') '# Existing federation'
        $before = Get-CoachTreeSnapshot -Root $fixture.Repo
        $inventory = Get-CoachInventory -Fixture $fixture
        $inventory.state.kind | Should -BeExactly 'federation'
        $inventory.state.files | Should -Contain (Join-Path $squad 'federation.md')
        Get-CoachTreeSnapshot -Root $fixture.Repo | Should -BeExactly $before
    }

    It 'discovers unrecorded <Layout> artifacts outside squad state without writing' -ForEach @(
        @{ Layout = 'Source' }
        @{ Layout = 'Apm' }
        @{ Layout = 'Plugin' }
    ) {
        $fixture = New-CoachFixture -Layout $Layout
        $tracking = Join-Path $fixture.Repo '.copilot-tracking'
        $team = Join-Path $tracking 'squad/team.md'
        $plan = Join-Path $tracking 'plans/claims-plan.txt'
        $unknown = Join-Path $tracking 'legacy-output/nested/release.txt'
        $memberHistory = Join-Path $tracking 'squad/members/existing/history/worker.md'
        Write-CoachFixture $team '# Existing team; no artifact references'
        Write-CoachFixture $plan 'An unrecorded pre-promotion plan'
        Write-CoachFixture $unknown 'An artifact outside the current cast root table'
        Write-CoachFixture $memberHistory '# Existing member history'
        $before = Get-CoachTreeSnapshot -Root $fixture.Repo
        $inventory = Get-CoachInventory -Fixture $fixture
        $inventory.state.kind | Should -BeExactly 'squad'
        $inventory.state.files | Should -Not -Contain $plan
        $inventory.tracking.directories | Should -Contain (Join-Path $tracking 'plans')
        $inventory.tracking.directories | Should -Contain (Join-Path $tracking 'legacy-output')
        $inventory.tracking.files | Should -Contain $plan
        $inventory.tracking.files | Should -Contain $unknown
        $inventory.tracking.files | Should -Contain $memberHistory
        $inventory.tracking.files | Should -Contain $team
        Get-CoachTreeSnapshot -Root $fixture.Repo | Should -BeExactly $before
    }

    It 'reports an invalid source root rather than returning an empty success' {
        $fixture = New-CoachFixture
        { & $script:InventoryScript -RepoRoot $fixture.Repo -SkillRoot (Join-Path $fixture.Repo 'missing') } |
            Should -Throw '*Coach inventory directory not found*'
    }
}

Describe 'COACH-10 Native acceptance fixtures' {
    It 'provisions no-state and unrecorded-legacy cases without a model call' {
        $source = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $runner = Join-Path $source 'tests/tier1/coach/Invoke-CoachAcceptance.ps1'
        $prepared = & $runner -SourceRoot $source -ResultRoot (Join-Path $TestDrive 'acceptance') `
            -Model 'not-used-during-provisioning' -ProvisionOnly
        $prepared.Results | Should -HaveCount 2
        $fresh = @($prepared.Results | Where-Object case -EQ 'first-capped-run')[0]
        Test-Path -LiteralPath (Join-Path $fresh.workspace '.copilot-tracking') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fresh.workspace 'package-docs') | Should -BeFalse
        $fresh.productDocumentation | Should -BeFalse
        $legacy = @($prepared.Results | Where-Object case -EQ 'legacy-artifacts')[0]
        Test-Path -LiteralPath (Join-Path $legacy.workspace 'package-docs/docs/usage.html') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $legacy.workspace '.copilot-tracking/plans/claims-plan.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $legacy.workspace '.copilot-tracking/legacy-output/nested/release.txt') | Should -BeTrue
        foreach ($case in $prepared.Results) {
            $case.execution | Should -BeExactly 'Provisioned'
            $case.mechanical | Should -BeExactly 'NotRun'
            $case.semantic | Should -BeExactly 'NotReviewed'
            $case.criteria.Count | Should -BeGreaterThan 0
            @($case.criteria | Where-Object verdict -NE 'NotReviewed') | Should -HaveCount 0
        }
    }
}
