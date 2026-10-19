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
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Fixture helper writes only beneath Pester TestDrive.', Scope = 'Function', Target = 'New-WatchModeBaseline')]
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
            [string]$Deliverable,

            [string]$Outcome = 'Completed successfully.',

            [switch]$Orchestration
        )

        $content = @(
            "# History: $Agent"
            ''
            '### 2026-10-19T08:00:00Z fixture dispatch'
            ''
            '* Turn: 1'
            '* Request: Exercise the Watch Mode lifecycle handoff.'
            ('* Deliverable: `{0}`' -f $Deliverable)
            "* Outcome: $Outcome"
            ''
            $(if ($Orchestration) { '#### Consumption — Orchestration' } else { '#### Consumption' })
            ''
            '```json'
            '{'
            '  "model": "fixture-model",'
            '  "model_source": "cli-pinned",'
            '  "priced_as": "fixture-model",'
            '  "model_tier": "default",'
            '  "internal_turns": 1,'
            '  "input_tokens": 10,'
            '  "cached_tokens": 0,'
            '  "cache_write_tokens": 0,'
            '  "output_tokens": 5,'
            '  "basis": "estimated"'
            '}'
            '```'
            ''
        ) -join "`n"
        Set-WatchModeTestFile -Path $Path -Content $content
    }

    function New-WatchModeBaseline {
        param(
            [Parameter(Mandatory)]
            [string]$Workspace,

            [string]$SubSquad = 'issue-1'
        )

        New-SquadWatchBaseline `
            -WorkspaceRoot $Workspace `
            -MemberRoot (Join-Path $Workspace ".copilot-tracking/squad/members/$SubSquad") `
            -Path (Join-Path $TestDrive "$SubSquad-baseline.json") `
            -Source $script:WatchTrigger.Source `
            -EventRef $script:WatchTrigger.Ref `
            -EventId $script:WatchTrigger.EventId `
            -Actor $script:WatchTrigger.Actor `
            -ReceivedAt $script:WatchTrigger.ReceivedAt
    }

    function New-CompleteWatchModeMember {
        param(
            [Parameter(Mandatory)]
            [string]$Workspace,

            [string]$SubSquad = 'issue-1',

            [switch]$CouncilSkipped,

            [switch]$IncludeEarlierIncomplete,

            [switch]$IncludeSecurityCouncil
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
            $(if ($IncludeSecurityCouncil) {
                    '| security | | Security Planner | | runSubagent / task | default | docs/security/ |'
                })
            '| scribe | | Squad Scribe | | runSubagent / task | fast | (squad state) |'
            ''
        ) -join "`n"
        Set-WatchModeTestFile -Path (Join-Path $member 'team.md') -Content $team
        Set-WatchModeTestFile -Path (Join-Path $member 'routing.md') -Content "# Squad Routing`n"
        Set-WatchModeTestFile -Path (Join-Path $member 'notifications.md') -Content "# Squad Notifications`n"
        Set-WatchModeTestFile -Path (Join-Path $member 'consumption.md') -Content "# Squad Consumption`n"
        Set-WatchModeTestFile -Path (Join-Path $member 'consumption-rates.md') -Content "# Consumption Rates`n"
        $state = [ordered]@{
            schemaVersion   = '1.4'
            updated         = [datetimeoffset]::UtcNow.AddSeconds(1).ToString('o')
            turn            = 1
            mode            = 'autopilot'
            activeRoles     = @()
            openEscalations = @()
            currentRun      = [ordered]@{
                sessionModel   = 'fixture-model'
                modelOverrides = [ordered]@{}
                estCostUsd     = 0
                estCreditsTotal = 0
                costPreflight  = [ordered]@{
                    runId              = ''
                    roundId            = ''
                    ceilingUsd         = $null
                    evaluatedSpendUsd  = 0
                    remainingUsd       = $null
                    plannedDispatches  = 0
                    projectedCostUsd   = 0
                    reserveMultiplier  = 3.0
                    admissionCostUsd   = 0
                    confidence         = 'not-applicable'
                    basis              = 'not-requested'
                    decision           = 'not-requested'
                    reason             = 'No cost ceiling configured.'
                }
            }
            notify          = [ordered]@{
                approvalChannel = 'in-chat'
                enabled         = $false
                email           = ''
                github          = [ordered]@{
                    handle = ''
                    repo   = ''
                }
            }
            trigger         = [ordered]@{
                source     = $script:WatchTrigger.Source
                ref        = $script:WatchTrigger.Ref
                eventId    = $script:WatchTrigger.EventId
                actor      = $script:WatchTrigger.Actor
                receivedAt = $script:WatchTrigger.ReceivedAt
                runId      = 'autopilot-run-fixture'
            }
        }
        Set-WatchModeTestFile `
            -Path (Join-Path $member 'state.json') `
            -Content ($state | ConvertTo-Json -Depth 6)

        $decisions = if ($CouncilSkipped) {
            "# Squad Decisions`n`nNo council was required for this single-domain fixture.`n"
        }
        else {
            $members = if ($IncludeSecurityCouncil) { 'architect, security' } else { 'architect' }
            $councilTimestamp = [datetimeoffset]::UtcNow.AddSeconds(1).ToString('o')
            @(
                '# Squad Decisions'
                ''
                "## Council Verdict $councilTimestamp fixture"
                ''
                '* Topic: Watch Mode lifecycle hardening'
                "* Proposal Ref: $prefix/plans/plan.md"
                "* Council Members Dispatched: $members"
                '* Council Members Not Proposed: cost-manager — no billable change; product-owner — scope unchanged; rai — no AI behavior'
                '* Verdict: Go'
                ''
                '### Findings by Role'
                ''
                '| Role | Verdict | Risk | Blocking Issues | Conditions | Suggested Follow-ups |'
                '| --- | --- | --- | --- | --- | --- |'
                '| architect | Approve | Risk: Low | none | none | none |'
                $(if ($IncludeSecurityCouncil) {
                        '| security | Approve | Risk: Low | none | none | none |'
                    })
                ''
                '### Synthesis'
                ''
                '* Blocking Issues: none'
                '* Conditions: none'
                '* Suggested Follow-ups: none'
                ''
                '### Implementation Gate'
                ''
                '* Permits Implementation Dispatch: yes'
                '* Conditions Outstanding: 0'
                ''
            ) -join "`n"
        }
        Set-WatchModeTestFile -Path (Join-Path $member 'decisions.md') -Content $decisions

        $research = "$prefix/research/2026-10-19/research.md"
        $plan = "$prefix/plans/plan.md"
        $change = "$prefix/changes/change.md"
        $review = "$prefix/reviews/review.md"
        $council = 'docs/architecture/council.md'
        $securityCouncil = 'docs/security/council.md'

        foreach ($artifact in @($research, $plan, $change, $review)) {
            Set-WatchModeTestFile `
                -Path (Join-Path $Workspace $artifact) `
                -Content "# Fixture artifact`n`nThis file records substantive lifecycle evidence for the current run.`n"
        }
        if (-not $CouncilSkipped) {
            Set-WatchModeTestFile `
                -Path (Join-Path $Workspace $council) `
                -Content "# Architecture council finding`n`nThe architecture review approved the bounded handoff.`n"
            if ($IncludeSecurityCouncil) {
                Set-WatchModeTestFile `
                    -Path (Join-Path $Workspace $securityCouncil) `
                    -Content "# Security council finding`n`nThe security review found no blocking issue.`n"
            }
        }

        New-WatchModeHistoryFile -Path (Join-Path $member 'history/Squad Researcher.md') -Agent 'Squad Researcher' -Deliverable $research
        New-WatchModeHistoryFile -Path (Join-Path $member 'history/Squad Lead.md') -Agent 'Squad Lead' -Deliverable $plan
        New-WatchModeHistoryFile -Path (Join-Path $member 'history/Squad Implementor.md') -Agent 'Squad Implementor' -Deliverable $change
        New-WatchModeHistoryFile -Path (Join-Path $member 'history/Squad Reviewer.md') -Agent 'Squad Reviewer' -Deliverable $review
        New-WatchModeHistoryFile `
            -Path (Join-Path $member 'history/Squad Scribe.md') `
            -Agent 'Squad Scribe' `
            -Deliverable "$prefix/state.json" `
            -Orchestration
        if (-not $CouncilSkipped) {
            New-WatchModeHistoryFile -Path (Join-Path $member 'history/System Architecture Reviewer.md') -Agent 'System Architecture Reviewer' -Deliverable $council
            if ($IncludeSecurityCouncil) {
                New-WatchModeHistoryFile -Path (Join-Path $member 'history/Security Planner.md') -Agent 'Security Planner' -Deliverable $securityCouncil
            }
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
        $summary.Add("* Trigger Source: $($script:WatchTrigger.Source)")
        $summary.Add("* Trigger Ref: $($script:WatchTrigger.Ref)")
        $summary.Add("* Trigger Event ID: $($script:WatchTrigger.EventId)")
        $summary.Add("* Trigger Actor: $($script:WatchTrigger.Actor)")
        $summary.Add("* Trigger Received At: $($script:WatchTrigger.ReceivedAt)")
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
            $summary.Add("* Trigger Source: $($script:WatchTrigger.Source)")
            $summary.Add("* Trigger Ref: $($script:WatchTrigger.Ref)")
            $summary.Add("* Trigger Event ID: $($script:WatchTrigger.EventId)")
            $summary.Add("* Trigger Actor: $($script:WatchTrigger.Actor)")
            $summary.Add("* Trigger Received At: $($script:WatchTrigger.ReceivedAt)")
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
            $councilHistory = if ($IncludeSecurityCouncil) {
                '`history/System Architecture Reviewer.md`, `history/Security Planner.md`'
            }
            else {
                '`history/System Architecture Reviewer.md`'
            }
            $councilRoles = if ($IncludeSecurityCouncil) { 'architect, security' } else { 'architect' }
            $summary.Add("| council | $councilRoles | $councilHistory | Go | none |")
        }
        $summary.Add('| implement | developer | `history/Squad Implementor.md` | complete | none |')
        $summary.Add('| review | tester | `history/Squad Reviewer.md` | complete | none |')
        $summary.Add('| final | coordinator | n/a | awaiting draft PR review | Final-Outcome Validation |')
        $summary.Add('')

        Set-WatchModeTestFile -Path (Join-Path $member 'history/autopilot-run-fixture.md') -Content ($summary -join "`n")
        $member
    }

    $script:SourceRootResolved = (Resolve-Path -LiteralPath $SourceRoot).Path
    $script:WatchModule = Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/scripts/SquadWatch.psm1'
    $script:WatchTrigger = [ordered]@{
        Source     = 'issue'
        Ref        = 'Peter-N91/hve-squad#1'
        EventId    = 'issues:1001'
        Actor      = 'watch-mode-tests'
        ReceivedAt = '2026-10-19T08:00:00Z'
    }
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

    It 'rolls back a partially applied overlay when a later destination collides' {
        $workspace = Join-Path $TestDrive 'overlay-transaction-workspace'
        $package = Join-Path $TestDrive 'overlay-transaction-package'
        $backup = Join-Path $TestDrive 'overlay-transaction-backup'

        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace '.github/agents/shared.agent.md') -Content 'original agent'
        Set-WatchModeTestFile -Path (Join-Path $workspace '.agents/skills') -Content 'original collision file'
        Save-WatchModeRepository -Repository $workspace

        Set-WatchModeTestFile -Path (Join-Path $package '.github/agents/shared.agent.md') -Content 'runtime overwrite'
        Set-WatchModeTestFile -Path (Join-Path $package '.github/agents/runtime.agent.md') -Content 'runtime only'
        Set-WatchModeTestFile -Path (Join-Path $package '.agents/skills/squad/SKILL.md') -Content 'runtime skill'

        {
            Enable-SquadWatchRuntimeOverlay `
                -PackageRoot $package `
                -WorkspaceRoot $workspace `
                -BackupRoot $backup
        } | Should -Throw

        (Get-Content -LiteralPath (Join-Path $workspace '.github/agents/shared.agent.md') -Raw).TrimEnd() |
            Should -BeExactly 'original agent'
        Test-Path -LiteralPath (Join-Path $workspace '.github/agents/runtime.agent.md') | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $workspace '.agents/skills') -Raw).TrimEnd() |
            Should -BeExactly 'original collision file'
        Test-Path -LiteralPath $backup | Should -BeFalse
        (Invoke-WatchModeGit -Repository $workspace -Arguments @('status', '--porcelain')).Output |
            Should -BeNullOrEmpty
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
        $baseline = New-WatchModeBaseline -Workspace $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot (Join-Path $workspace '.copilot-tracking/squad/members/missing') `
                -PatchPath (Join-Path $TestDrive 'missing-member.patch') `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Throw '*member root*does not exist*'
    }

    It 'blocks implementation-only evidence before producing a patch' {
        $workspace = Join-Path $TestDrive 'partial-lifecycle-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace
        Remove-Item -LiteralPath (Join-Path $member 'research') -Recurse -Force
        Remove-Item -LiteralPath (Join-Path $member 'plans') -Recurse -Force
        Remove-Item -LiteralPath (Join-Path $member 'history/Squad Researcher.md') -Force
        Remove-Item -LiteralPath (Join-Path $member 'history/Squad Lead.md') -Force
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot $member `
                -PatchPath (Join-Path $TestDrive 'partial-lifecycle.patch') `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Throw '*missing*research*'
        Test-Path -LiteralPath (Join-Path $TestDrive 'partial-lifecycle.patch') | Should -BeFalse
    }

    It 'accepts a complete resumed run, validates deliverable pointers, and remains read-only on repeat' {
        $workspace = Join-Path $TestDrive 'complete-lifecycle-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace -IncludeEarlierIncomplete
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        $before = @(
            Get-ChildItem -LiteralPath $member -File -Recurse |
                Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
        )
        $first = Test-SquadWatchLifecycle `
            -MemberRoot $member `
            -WorkspaceRoot $workspace `
            -BaselinePath $baseline.Path `
            -ExpectedBaselineHash $baseline.Hash
        $second = Test-SquadWatchLifecycle `
            -MemberRoot $member `
            -WorkspaceRoot $workspace `
            -BaselinePath $baseline.Path `
            -ExpectedBaselineHash $baseline.Hash
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
            -BaselinePath $baseline.Path `
            -ExpectedBaselineHash $baseline.Hash
        $handoff.HasChanges | Should -BeTrue
        $handoff.MaterialChanges | Should -Contain 'app.txt'
        Test-Path -LiteralPath $handoff.PatchPath | Should -BeTrue
    }

    It 'preserves conditional council behavior through an explicit skipped stage row' {
        $workspace = Join-Path $TestDrive 'skipped-council-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace -CouncilSkipped
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot $member `
                -PatchPath (Join-Path $TestDrive 'skipped-council.patch') `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Not -Throw
    }

    It 'rejects committed stale evidence and an unrelated run still marked active' {
        $workspace = Join-Path $TestDrive 'stale-evidence-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        $member = New-CompleteWatchModeMember -Workspace $workspace
        $statePath = Join-Path $member 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['trigger']['eventId'] = 'issues:unrelated'
        $state['activeRoles'] = @('Squad Implementor')
        Set-WatchModeTestFile -Path $statePath -Content ($state | ConvertTo-Json -Depth 6)
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot $member `
                -PatchPath (Join-Path $TestDrive 'stale-evidence.patch') `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Throw '*does not match the authorized event*'
    }

    It 'rejects failed stage results through the actual staging entrypoint' {
        $workspace = Join-Path $TestDrive 'failed-stage-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace
        $summaryPath = Join-Path $member 'history/autopilot-run-fixture.md'
        $summary = Get-Content -LiteralPath $summaryPath -Raw
        Set-WatchModeTestFile `
            -Path $summaryPath `
            -Content ($summary.Replace(
                    '| plan | lead | `history/Squad Lead.md` | complete | none |',
                    '| plan | lead | `history/Squad Lead.md` | failed | none |'
                ))
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot $member `
                -PatchPath (Join-Path $TestDrive 'failed-stage.patch') `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Throw "*'plan' stage result is not complete*"
    }

    It 'rejects an incomplete latest role-history outcome' {
        $workspace = Join-Path $TestDrive 'incomplete-history-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace
        $historyPath = Join-Path $member 'history/Squad Reviewer.md'
        $history = Get-Content -LiteralPath $historyPath -Raw
        Set-WatchModeTestFile `
            -Path $historyPath `
            -Content ($history.Replace('* Outcome: Completed successfully.', '* Outcome: Incomplete pending validation.'))
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot $member `
                -PatchPath (Join-Path $TestDrive 'incomplete-history.patch') `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Throw '*latest outcome is not complete*'
    }

    It 'rejects an empty state object' {
        $workspace = Join-Path $TestDrive 'empty-state-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace
        Set-WatchModeTestFile -Path (Join-Path $member 'state.json') -Content '{}'
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot $member `
                -PatchPath (Join-Path $TestDrive 'empty-state.patch') `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Throw "*state.json is missing 'schemaVersion'*"
    }

    It 'rejects heading-only stage and scribe evidence' {
        $workspace = Join-Path $TestDrive 'heading-only-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace
        Set-WatchModeTestFile -Path (Join-Path $member 'reviews/review.md') -Content '# Review'
        Set-WatchModeTestFile -Path (Join-Path $member 'history/Squad Scribe.md') -Content '# History: Squad Scribe'
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot $member `
                -PatchPath (Join-Path $TestDrive 'heading-only.patch') `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Throw '*structured evidence*'
    }

    It 'requires dispatch evidence for every selected council role' {
        $workspace = Join-Path $TestDrive 'partial-council-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace -IncludeSecurityCouncil
        Remove-Item -LiteralPath (Join-Path $member 'history/Security Planner.md') -Force
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot $member `
                -PatchPath (Join-Path $TestDrive 'partial-council.patch') `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Throw '*history/Security Planner.md*'
    }

    It 'rejects a stale Council Verdict for current council dispatches' {
        $workspace = Join-Path $TestDrive 'stale-council-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace
        $decisionsPath = Join-Path $member 'decisions.md'
        $decisions = Get-Content -LiteralPath $decisionsPath -Raw
        Set-WatchModeTestFile `
            -Path $decisionsPath `
            -Content ($decisions -replace '(?m)^## Council Verdict \S+ fixture$', '## Council Verdict 2001-01-01T00:00:00Z fixture')
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot $member `
                -PatchPath (Join-Path $TestDrive 'stale-council.patch') `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Throw '*stale Council Verdict*'
    }

    It 'rejects an existing deliverable owned by another federation member' {
        $workspace = Join-Path $TestDrive 'cross-member-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace
        $otherReview = '.copilot-tracking/squad/members/issue-2/reviews/review.md'
        Set-WatchModeTestFile `
            -Path (Join-Path $workspace $otherReview) `
            -Content "# Other review`n`nThis belongs to another event-scoped member.`n"
        $reviewHistory = Join-Path $member 'history/Squad Reviewer.md'
        $history = Get-Content -LiteralPath $reviewHistory -Raw
        Set-WatchModeTestFile `
            -Path $reviewHistory `
            -Content ($history.Replace(
                    '.copilot-tracking/squad/members/issue-1/reviews/review.md',
                    $otherReview
                ))
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -WorkspaceRoot $workspace `
                -MemberRoot $member `
                -PatchPath (Join-Path $TestDrive 'cross-member.patch') `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Throw '*belongs to another federation member*'
    }

    It 'blocks missing and out-of-root deliverables referenced by the current run' {
        $workspace = Join-Path $TestDrive 'invalid-deliverable-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace
        $reviewHistory = Join-Path $member 'history/Squad Reviewer.md'
        $content = Get-Content -LiteralPath $reviewHistory -Raw
        $content = $content.Replace(
            '.copilot-tracking/squad/members/issue-1/reviews/review.md',
            '.copilot-tracking/squad/members/issue-1/changes/missing-review.md'
        )
        Set-WatchModeTestFile -Path $reviewHistory -Content $content
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'after'

        {
            New-SquadWatchHandoff `
                -MemberRoot $member `
                -WorkspaceRoot $workspace `
                -PatchPath (Join-Path $TestDrive 'invalid-deliverable.patch') `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Throw '*references missing deliverable*'
    }

    It 'blocks a startup baseline changed after trusted capture' {
        $workspace = Join-Path $TestDrive 'tampered-baseline-workspace'
        Initialize-WatchModeRepository -Repository $workspace
        Set-WatchModeTestFile -Path (Join-Path $workspace 'app.txt') -Content 'before'
        Save-WatchModeRepository -Repository $workspace
        $baseline = New-WatchModeBaseline -Workspace $workspace
        $member = New-CompleteWatchModeMember -Workspace $workspace
        Add-Content -LiteralPath $baseline.Path -Value "`n"

        {
            Test-SquadWatchLifecycle `
                -MemberRoot $member `
                -WorkspaceRoot $workspace `
                -BaselinePath $baseline.Path `
                -ExpectedBaselineHash $baseline.Hash
        } | Should -Throw '*startup baseline changed*'
    }

    It 'wires the production helper before a patch can be uploaded' {
        $script:WatchWorkflow | Should -Match ([regex]::Escape('Enable-SquadWatchRuntimeOverlay'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('Restore-SquadWatchRuntimeOverlay'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('New-SquadWatchHandoff'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('IMMEDIATE SCRIBE CHECKPOINTS (NON-NEGOTIABLE).'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('Never defer per-role history or state writes to the final summary.'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('watchModuleHash='))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('baselineHash='))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('ExpectedBaselineHash'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('RUNTIME_OUTCOME: ${{ steps.runtime.outcome }}'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('triggerSource: ${{ steps.prep.outputs.triggerSource }}'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('triggerReceivedAt: ${{ steps.prep.outputs.triggerReceivedAt }}'))
        $script:WatchWorkflow | Should -Match ([regex]::Escape('-ReceivedAt $env:TRIGGER_RECEIVED_AT'))
        $script:WatchWorkflow | Should -Not -Match ([regex]::Escape("'.agents', 'apm_modules', 'install.log'"))
    }
}
