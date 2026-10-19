#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Fixture helper writes only beneath Pester TestDrive.', Scope = 'Function', Target = 'Set-WatchModeTestFile')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Fixture helper writes only beneath Pester TestDrive.', Scope = 'Function', Target = 'New-WatchModeHistoryFile')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Fixture helper writes only beneath Pester TestDrive.', Scope = 'Function', Target = 'New-CompleteWatchModeMember')]
param(
    [Parameter(Mandatory)]
    [string]$SourceRoot
)

BeforeAll {
    function Set-WatchModeTestFile {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Content
        )

        $parent = Split-Path -Parent $Path
        if ($parent) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Set-Content -LiteralPath $Path -Value $Content -Encoding utf8NoBOM
    }

    function Invoke-WatchModeGit {
        param(
            [Parameter(Mandatory)]
            [string]$Repository,

            [Parameter(Mandatory)]
            [string[]]$Arguments,

            [switch]$AllowFailure
        )

        $output = @(& git -C $Repository @Arguments 2>&1)
        if (-not $AllowFailure -and $LASTEXITCODE -ne 0) {
            throw "git $($Arguments -join ' ') failed:`n$($output -join "`n")"
        }

        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = $output
        }
    }

    function Initialize-WatchModeRepository {
        param(
            [Parameter(Mandatory)]
            [string]$Repository
        )

        New-Item -ItemType Directory -Path $Repository -Force | Out-Null
        Invoke-WatchModeGit -Repository $Repository -Arguments @('init', '--quiet', '-b', 'main') | Out-Null
        Invoke-WatchModeGit -Repository $Repository -Arguments @('config', 'user.name', 'Watch Mode Tests') | Out-Null
        Invoke-WatchModeGit -Repository $Repository -Arguments @('config', 'user.email', 'watch-mode-tests@example.invalid') | Out-Null
    }

    function Save-WatchModeRepository {
        param(
            [Parameter(Mandatory)]
            [string]$Repository,

            [string]$Message = 'fixture'
        )

        Invoke-WatchModeGit -Repository $Repository -Arguments @('add', '-A') | Out-Null
        Invoke-WatchModeGit -Repository $Repository -Arguments @('commit', '--quiet', '-m', $Message) | Out-Null
    }

    function New-WatchModeHistoryFile {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$Agent,

            [Parameter(Mandatory)]
            [string]$Deliverable
        )

        $content = @(
            "# History: $Agent"
            ''
            '### 2026-10-19T08:00:00Z fixture dispatch'
            ''
            '* Turn: 1'
            '* Request: Exercise the Watch Mode lifecycle handoff.'
            ('* Deliverable: `{0}`' -f $Deliverable)
            '* Outcome: Completed.'
            ''
        ) -join "`n"
        Set-WatchModeTestFile -Path $Path -Content $content
    }

    function New-CompleteWatchModeMember {
        param(
            [Parameter(Mandatory)]
            [string]$Workspace,

            [string]$SubSquad = 'issue-1',

            [switch]$CouncilSkipped,

            [switch]$IncludeEarlierIncomplete
        )

        $member = Join-Path $Workspace ".copilot-tracking/squad/members/$SubSquad"
        $prefix = ".copilot-tracking/squad/members/$SubSquad"

        $team = @(
            '---'
            'description: "Watch Mode test roster"'
            '---'
            ''
            '# Squad Roster'
            ''
            '## Members'
            ''
            '| Role | Member Name | Agent Name (Primary) | Alternate Agents | Invocation | Model Tier | Deliverable Root |'
            '| --- | --- | --- | --- | --- | --- | --- |'
            "| researcher | | Squad Researcher | | runSubagent / task | default | $prefix/research/ |"
            "| lead | | Squad Lead | | runSubagent / task | default | $prefix/plans/ |"
            "| developer | | Squad Implementor | | runSubagent / task | default | $prefix/changes/ |"
            "| tester | | Squad Reviewer | Code Review Functional | runSubagent / task | fast | $prefix/reviews/ |"
            '| architect | | System Architecture Reviewer | | runSubagent / task | default | docs/architecture/ |'
            '| scribe | | Squad Scribe | | runSubagent / task | fast | (squad state) |'
            ''
        ) -join "`n"
        Set-WatchModeTestFile -Path (Join-Path $member 'team.md') -Content $team
        Set-WatchModeTestFile -Path (Join-Path $member 'routing.md') -Content "# Squad Routing`n"
        Set-WatchModeTestFile -Path (Join-Path $member 'notifications.md') -Content "# Squad Notifications`n"
        Set-WatchModeTestFile -Path (Join-Path $member 'consumption.md') -Content "# Squad Consumption`n"
        Set-WatchModeTestFile -Path (Join-Path $member 'consumption-rates.md') -Content "# Consumption Rates`n"
        Set-WatchModeTestFile -Path (Join-Path $member 'state.json') -Content '{"schemaVersion":"1.4","updated":"2026-10-19T08:00:00Z","turn":1,"mode":"autopilot","activeRoles":[],"openEscalations":[],"currentRun":{},"notify":{}}'

        $decisions = if ($CouncilSkipped) {
            "# Squad Decisions`n"
        }
        else {
            @(
                '# Squad Decisions'
                ''
                '## Council Verdict 2026-10-19T08:00:00Z fixture'
                ''
                '* Verdict: Go'
                ''
            ) -join "`n"
        }
        Set-WatchModeTestFile -Path (Join-Path $member 'decisions.md') -Content $decisions

        $research = "$prefix/research/2026-10-19/research.md"
        $plan = "$prefix/plans/plan.md"
        $change = "$prefix/changes/change.md"
        $review = "$prefix/reviews/review.md"
        $council = 'docs/architecture/council.md'

        foreach ($artifact in @($research, $plan, $change, $review)) {
            Set-WatchModeTestFile -Path (Join-Path $Workspace $artifact) -Content "# Fixture artifact`n"
        }
        if (-not $CouncilSkipped) {
            Set-WatchModeTestFile -Path (Join-Path $Workspace $council) -Content "# Council finding`n"
        }

        New-WatchModeHistoryFile -Path (Join-Path $member 'history/Squad Researcher.md') -Agent 'Squad Researcher' -Deliverable $research
        New-WatchModeHistoryFile -Path (Join-Path $member 'history/Squad Lead.md') -Agent 'Squad Lead' -Deliverable $plan
        New-WatchModeHistoryFile -Path (Join-Path $member 'history/Squad Implementor.md') -Agent 'Squad Implementor' -Deliverable $change
        New-WatchModeHistoryFile -Path (Join-Path $member 'history/Squad Reviewer.md') -Agent 'Squad Reviewer' -Deliverable $review
        New-WatchModeHistoryFile -Path (Join-Path $member 'history/Squad Scribe.md') -Agent 'Squad Scribe' -Deliverable "$prefix/state.json"
        if (-not $CouncilSkipped) {
            New-WatchModeHistoryFile -Path (Join-Path $member 'history/System Architecture Reviewer.md') -Agent 'System Architecture Reviewer' -Deliverable $council
        }
        if ($IncludeEarlierIncomplete) {
            $researchHistoryPath = Join-Path $member 'history/Squad Researcher.md'
            $currentEntry = (Get-Content -LiteralPath $researchHistoryPath -Raw) -replace '(?s)^# History: Squad Researcher\s*', ''
            $resumedHistory = @(
                '# History: Squad Researcher'
                ''
                '### 2026-10-19T07:00:00Z incomplete fixture dispatch'
                ''
                '* Turn: 0'
                '* Request: Record an intentionally stale entry.'
                '* Deliverable: `research/missing-old.md`'
                '* Outcome: Incomplete.'
                ''
                $currentEntry.TrimStart()
            ) -join "`n"
            Set-WatchModeTestFile -Path $researchHistoryPath -Content $resumedHistory
        }

        $summary = [System.Collections.Generic.List[string]]::new()
        $summary.Add('---')
        $summary.Add('description: "Autopilot-run fixture"')
        $summary.Add('---')
        $summary.Add('')
        $summary.Add('# Autopilot Run: fixture')
        $summary.Add('')
        $summary.Add($(if ($IncludeEarlierIncomplete) {
                    '* Outcome: incomplete (four stages without a dispatch record)'
                }
                else {
                    '* Outcome: completed (awaiting final validation)'
                }))
        $summary.Add('')

        if ($IncludeEarlierIncomplete) {
            $summary.Add('## Stages')
            $summary.Add('')
            $summary.Add('| Stage | Role(s) | Dispatch Record | Result | Gate Fired |')
            $summary.Add('| --- | --- | --- | --- | --- |')
            $summary.Add('| research | researcher | none recorded | incomplete | none |')
            $summary.Add('| plan | lead | none recorded | incomplete | none |')
            $summary.Add('| council | none | n/a | skipped - not applicable | none |')
            $summary.Add('| implement | developer | none recorded | incomplete | none |')
            $summary.Add('| review | tester | none recorded | incomplete | none |')
            $summary.Add('')
            $summary.Add('## Resume')
            $summary.Add('')
            $summary.Add('The resumed run repaired the incomplete dispatch record.')
            $summary.Add('')
            $summary.Add('* Outcome: completed (awaiting final validation)')
            $summary.Add('')
        }

        $summary.Add('## Stages')
        $summary.Add('')
        $summary.Add('| Stage | Role(s) | Dispatch Record | Result | Gate Fired |')
        $summary.Add('| --- | --- | --- | --- | --- |')
        $summary.Add('| research | researcher | `history/Squad Researcher.md` | complete | none |')
        $summary.Add('| plan | lead | `history/Squad Lead.md` | complete | none |')
        if ($CouncilSkipped) {
            $summary.Add('| council | none | n/a | skipped - single-domain change | none |')
        }
        else {
            $summary.Add('| council | architect | `history/System Architecture Reviewer.md` | Go | none |')
        }
        $summary.Add('| implement | developer | `history/Squad Implementor.md` | complete | none |')
        $summary.Add('| review | tester | `history/Squad Reviewer.md` | complete | none |')
        $summary.Add('| final | coordinator | n/a | awaiting draft PR review | Final-Outcome Validation |')
        $summary.Add('')

        Set-WatchModeTestFile -Path (Join-Path $member 'history/autopilot-run-fixture.md') -Content ($summary -join "`n")
        $member
    }

    $script:SourceRootResolved = (Resolve-Path -LiteralPath $SourceRoot).Path
    $script:WatchModule = Join-Path $script:SourceRootResolved 'scripts/SquadWatch.psm1'
    $script:StateModule = Join-Path $script:SourceRootResolved 'tests/tier1/SquadState.psm1'
    $script:StateModuleHash = (Get-FileHash -LiteralPath $script:StateModule -Algorithm SHA256).Hash.ToLowerInvariant()
    $script:WatchWorkflow = Get-Content -LiteralPath (Join-Path $script:SourceRootResolved '.github/workflows/squad-watch.yml') -Raw
    Import-Module $script:WatchModule -Force
}

Describe 'GATE-46 Watch Mode runtime overlay ownership' {
    It 'merges into populated destinations, restores tracked content, and stages no deletion' {
        $workspace = Join-Path $TestDrive 'overlay-populated-workspace'
        $package = Join-Path $TestDrive 'overlay-populated-package'
        $backup = Join-Path $TestDrive 'overlay-populated-backup'

        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace '.github/agents/custom.agent.md') -Content 'keep agent'
        Set-WatchModeTestFile -Path (Join-Path $workspace '.github/prompts/custom.prompt.md') -Content 'keep prompt'
        Set-WatchModeTestFile -Path (Join-Path $workspace '.github/instructions/custom.instructions.md') -Content 'keep instruction'
        Set-WatchModeTestFile -Path (Join-Path $workspace '.agents/skills/custom/keep.txt') -Content 'keep skill'
        Set-WatchModeTestFile -Path (Join-Path $workspace 'apm_modules/custom/keep.txt') -Content 'keep module'
        Set-WatchModeTestFile -Path (Join-Path $workspace 'install.log') -Content 'keep log'
        Save-WatchModeRepository -Repository $workspace

        Set-WatchModeTestFile -Path (Join-Path $package '.github/agents/squad-federation-coordinator.agent.md') -Content 'runtime agent'
        Set-WatchModeTestFile -Path (Join-Path $package '.github/prompts/squad.prompt.md') -Content 'runtime prompt'
        Set-WatchModeTestFile -Path (Join-Path $package '.github/instructions/squad.instructions.md') -Content 'runtime instruction'
        Set-WatchModeTestFile -Path (Join-Path $package '.agents/skills/squad/SKILL.md') -Content 'runtime skill'

        $overlay = Enable-SquadWatchRuntimeOverlay -PackageRoot $package -WorkspaceRoot $workspace -BackupRoot $backup

        Test-Path -LiteralPath (Join-Path $workspace '.github/agents/squad-federation-coordinator.agent.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $workspace '.github/agents/agents/squad-federation-coordinator.agent.md') | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $workspace '.github/agents/custom.agent.md') -Raw).TrimEnd() | Should -BeExactly 'keep agent'

        Set-WatchModeTestFile -Path (Join-Path $workspace '.github/agents/squad-federation-coordinator.agent.md') -Content 'runtime mutation'
        Restore-SquadWatchRuntimeOverlay `
            -WorkspaceRoot $workspace `
            -BackupRoot $backup `
            -ExpectedManifestHash $overlay.ManifestHash

        Test-Path -LiteralPath (Join-Path $workspace '.github/agents/squad-federation-coordinator.agent.md') | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $workspace '.github/agents/custom.agent.md') -Raw).TrimEnd() | Should -BeExactly 'keep agent'
        (Get-Content -LiteralPath (Join-Path $workspace '.github/prompts/custom.prompt.md') -Raw).TrimEnd() | Should -BeExactly 'keep prompt'
        (Get-Content -LiteralPath (Join-Path $workspace '.github/instructions/custom.instructions.md') -Raw).TrimEnd() | Should -BeExactly 'keep instruction'
        (Get-Content -LiteralPath (Join-Path $workspace '.agents/skills/custom/keep.txt') -Raw).TrimEnd() | Should -BeExactly 'keep skill'
        (Get-Content -LiteralPath (Join-Path $workspace 'apm_modules/custom/keep.txt') -Raw).TrimEnd() | Should -BeExactly 'keep module'
        (Get-Content -LiteralPath (Join-Path $workspace 'install.log') -Raw).TrimEnd() | Should -BeExactly 'keep log'

        $handoff = New-SquadWatchHandoff `
            -WorkspaceRoot $workspace `
            -MemberRoot (Join-Path $workspace '.copilot-tracking/squad/members/not-created') `
            -PatchPath (Join-Path $TestDrive 'overlay-populated.patch')
        $handoff.HasChanges | Should -BeFalse
        (Invoke-WatchModeGit -Repository $workspace -Arguments @('status', '--porcelain')).Output | Should -BeNullOrEmpty
    }

    It 'removes an overlay cleanly when runtime destinations were initially absent' {
        $workspace = Join-Path $TestDrive 'overlay-empty-workspace'
        $package = Join-Path $TestDrive 'overlay-empty-package'
        $backup = Join-Path $TestDrive 'overlay-empty-backup'

        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'README.md') -Content 'fixture'
        Save-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $package '.github/agents/squad.agent.md') -Content 'runtime agent'
        Set-WatchModeTestFile -Path (Join-Path $package '.agents/skills/squad/SKILL.md') -Content 'runtime skill'

        $overlay = Enable-SquadWatchRuntimeOverlay -PackageRoot $package -WorkspaceRoot $workspace -BackupRoot $backup
        Restore-SquadWatchRuntimeOverlay `
            -WorkspaceRoot $workspace `
            -BackupRoot $backup `
            -ExpectedManifestHash $overlay.ManifestHash

        Test-Path -LiteralPath (Join-Path $workspace '.github/agents') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $workspace '.agents') | Should -BeFalse
        (Invoke-WatchModeGit -Repository $workspace -Arguments @('status', '--porcelain')).Output | Should -BeNullOrEmpty
    }

    It 'refuses a tampered backup before changing the workspace during cleanup' {
        $workspace = Join-Path $TestDrive 'overlay-tamper-workspace'
        $package = Join-Path $TestDrive 'overlay-tamper-package'
        $backup = Join-Path $TestDrive 'overlay-tamper-backup'

        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace '.github/agents/custom.agent.md') -Content 'keep agent'
        Save-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $package '.github/agents/squad.agent.md') -Content 'runtime agent'

        $overlay = Enable-SquadWatchRuntimeOverlay -PackageRoot $package -WorkspaceRoot $workspace -BackupRoot $backup
        Set-WatchModeTestFile -Path (Join-Path $backup 'original/.github/agents/custom.agent.md') -Content 'tampered'

        {
            Restore-SquadWatchRuntimeOverlay `
                -WorkspaceRoot $workspace `
                -BackupRoot $backup `
                -ExpectedManifestHash $overlay.ManifestHash
        } | Should -Throw '*backup file changed*'

        Test-Path -LiteralPath (Join-Path $workspace '.github/agents/squad.agent.md') | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $workspace '.github/agents/custom.agent.md') -Raw).TrimEnd() |
            Should -BeExactly 'keep agent'
    }
}

Describe 'GATE-46 Watch Mode patch source identity' {
    It 'carries the producing checkout SHA into the apply job' {
        $script:WatchWorkflow | Should -Match ([regex]::Escape('sourceSha: ${{ steps.source.outputs.sha }}'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('"sha=$(git rev-parse HEAD)"'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('ref: ${{ needs.interpret.outputs.sourceSha }}'))
    }

    It 'applies a PR-head patch only when the consumer starts from the recorded source SHA' {
        $repository = Join-Path $TestDrive 'patch-source-repository'
        $patch = Join-Path $TestDrive 'pr-head.patch'

        Initialize-WatchModeRepository -Repository $repository
        Set-WatchModeTestFile -Path (Join-Path $repository 'app.txt') -Content "header`nmain`nfooter"
        Save-WatchModeRepository -Repository $repository -Message 'main'

        Invoke-WatchModeGit -Repository $repository -Arguments @('checkout', '--quiet', '-b', 'feature') | Out-Null
        Set-WatchModeTestFile -Path (Join-Path $repository 'app.txt') -Content "header`npr-head`nfooter"
        Save-WatchModeRepository -Repository $repository -Message 'PR head'
        $sourceSha = (Invoke-WatchModeGit -Repository $repository -Arguments @('rev-parse', 'HEAD')).Output[0]

        Set-WatchModeTestFile -Path (Join-Path $repository 'app.txt') -Content "header`nrequested-change`nfooter"
        Invoke-WatchModeGit -Repository $repository -Arguments @('diff', '--binary', "--output=$patch") | Out-Null
        Invoke-WatchModeGit -Repository $repository -Arguments @('restore', '--worktree', 'app.txt') | Out-Null

        Invoke-WatchModeGit -Repository $repository -Arguments @('checkout', '--quiet', 'main') | Out-Null
        $wrongBase = Invoke-WatchModeGit -Repository $repository -Arguments @('apply', '--binary', '--index', $patch) -AllowFailure
        $wrongBase.ExitCode | Should -Not -Be 0
        Invoke-WatchModeGit -Repository $repository -Arguments @('restore', '--staged', '--worktree', 'app.txt') | Out-Null

        Invoke-WatchModeGit -Repository $repository -Arguments @('checkout', '--quiet', '--detach', $sourceSha) | Out-Null
        Invoke-WatchModeGit -Repository $repository -Arguments @('checkout', '--quiet', '-b', 'apply-result') | Out-Null
        Invoke-WatchModeGit -Repository $repository -Arguments @('apply', '--binary', '--index', $patch) | Out-Null

        ((Get-Content -LiteralPath (Join-Path $repository 'app.txt') -Raw) -replace "`r`n", "`n").TrimEnd() |
            Should -BeExactly "header`nrequested-change`nfooter"
    }
}

Describe 'GATE-46 Watch Mode lifecycle handoff gate' {
    It 'treats an unchanged workspace as a legitimate no-change result without requiring state' {
        $workspace = Join-Path $TestDrive 'no-change-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'README.md') -Content 'fixture'
        Save-WatchModeRepository -Repository $workspace

        $result = New-SquadWatchHandoff `
            -WorkspaceRoot $workspace `
            -MemberRoot (Join-Path $workspace '.copilot-tracking/squad/members/missing') `
            -PatchPath (Join-Path $TestDrive 'no-change.patch')

        $result.HasChanges | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $TestDrive 'no-change.patch') | Should -BeFalse
    }

    It 'blocks an application change when the selected member root is missing' {
        $workspace = Join-Path $TestDrive 'missing-member-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot (Join-Path $workspace '.copilot-tracking/squad/members/missing') `
                -PatchPath (Join-Path $TestDrive 'missing-member.patch')
        } | Should -Throw '*member root*does not exist*'
    }

    It 'blocks implementation-only evidence before producing a patch' {
        $workspace = Join-Path $TestDrive 'partial-lifecycle-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace
        Remove-Item -LiteralPath (Join-Path $member 'research') -Recurse -Force
        Remove-Item -LiteralPath (Join-Path $member 'plans') -Recurse -Force
        Remove-Item -LiteralPath (Join-Path $member 'history/Squad Researcher.md') -Force
        Remove-Item -LiteralPath (Join-Path $member 'history/Squad Lead.md') -Force
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot $member `
                -PatchPath (Join-Path $TestDrive 'partial-lifecycle.patch') `
                -StateModulePath $script:StateModule `
                -ExpectedStateModuleHash $script:StateModuleHash
        } | Should -Throw '*missing lifecycle artifact*'
        Test-Path -LiteralPath (Join-Path $TestDrive 'partial-lifecycle.patch') | Should -BeFalse
    }

    It 'accepts a complete resumed run, validates deliverable pointers, and remains read-only on repeat' {
        $workspace = Join-Path $TestDrive 'complete-lifecycle-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace -IncludeEarlierIncomplete
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        $before = @(
            Get-ChildItem -LiteralPath $member -File -Recurse |
                Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
        )
        $first = Test-SquadWatchLifecycle `
            -MemberRoot $member `
            -WorkspaceRoot $workspace `
            -StateModulePath $script:StateModule `
            -ExpectedStateModuleHash $script:StateModuleHash
        $second = Test-SquadWatchLifecycle `
            -MemberRoot $member `
            -WorkspaceRoot $workspace `
            -StateModulePath $script:StateModule `
            -ExpectedStateModuleHash $script:StateModuleHash
        $after = @(
            Get-ChildItem -LiteralPath $member -File -Recurse |
                Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
        )

        $first.Stages | Should -Contain 'research'
        $second.Summary | Should -BeExactly $first.Summary
        $after | Should -Be $before

        $handoff = New-SquadWatchHandoff `
            -WorkspaceRoot $workspace `
            -MemberRoot $member `
            -PatchPath (Join-Path $TestDrive 'complete-lifecycle.patch') `
            -StateModulePath $script:StateModule `
            -ExpectedStateModuleHash $script:StateModuleHash
        $handoff.HasChanges | Should -BeTrue
        $handoff.MaterialChanges | Should -Contain 'app.txt'
        Test-Path -LiteralPath $handoff.PatchPath | Should -BeTrue
    }

    It 'preserves conditional council behavior through an explicit skipped stage row' {
        $workspace = Join-Path $TestDrive 'skipped-council-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace -CouncilSkipped
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot $member `
                -PatchPath (Join-Path $TestDrive 'skipped-council.patch') `
                -StateModulePath $script:StateModule `
                -ExpectedStateModuleHash $script:StateModuleHash
        } | Should -Not -Throw
    }

    It 'blocks missing and out-of-root deliverables referenced by the current run' {
        $workspace = Join-Path $TestDrive 'invalid-deliverable-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace
        $reviewHistory = Join-Path $member 'history/Squad Reviewer.md'
        $content = Get-Content -LiteralPath $reviewHistory -Raw
        $content = $content.Replace(
            '.copilot-tracking/squad/members/issue-1/reviews/review.md',
            '.copilot-tracking/squad/members/issue-1/changes/missing-review.md'
        )
        Set-WatchModeTestFile -Path $reviewHistory -Content $content

        {
            Test-SquadWatchLifecycle `
                -MemberRoot $member `
                -WorkspaceRoot $workspace `
                -StateModulePath $script:StateModule `
                -ExpectedStateModuleHash $script:StateModuleHash
        } | Should -Throw '*references missing deliverable*'
    }

    It 'blocks a state parser changed after the trusted provisioning step' {
        $workspace = Join-Path $TestDrive 'tampered-parser-workspace'
        New-Item -ItemType Directory -Path $workspace -Force | Out-Null
        $member = New-CompleteWatchModeMember -Workspace $workspace
        $tamperedStateModule = Join-Path $TestDrive 'SquadState-tampered.psm1'
        Copy-Item -LiteralPath $script:StateModule -Destination $tamperedStateModule
        Add-Content -LiteralPath $tamperedStateModule -Value '# tampered'

        {
            Test-SquadWatchLifecycle `
                -MemberRoot $member `
                -WorkspaceRoot $workspace `
                -StateModulePath $tamperedStateModule `
                -ExpectedStateModuleHash $script:StateModuleHash
        } | Should -Throw '*state parser changed after checkout*'
    }

    It 'wires the production helper before a patch can be uploaded' {
        $script:WatchWorkflow | Should -Match ([regex]::Escape('Enable-SquadWatchRuntimeOverlay'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('Restore-SquadWatchRuntimeOverlay'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('New-SquadWatchHandoff'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('watchModuleHash='))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('stateModuleHash='))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('ExpectedStateModuleHash'))
        $script:WatchWorkflow | Should -Not -Match ([regex]::Escape("'.agents', 'apm_modules', 'install.log'"))
    }
}
