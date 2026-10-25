#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll.')]
param([Parameter(Mandatory)][string]$PackageRoot)

BeforeAll {
    $script:Writer = Join-Path $PackageRoot '.agents/skills/squad/scripts/Write-SquadVerdict.ps1'
    $script:FixtureRoot = Join-Path $PSScriptRoot '../fixtures/scribe-benchmark/seed'

    function New-VerdictRoot {
        param([switch]$Member)
        $repo = Join-Path $TestDrive "verdict-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        $tracking = Join-Path $repo '.copilot-tracking/squad'
        if ($Member) {
            $null = New-Item -ItemType Directory -Path (Join-Path $tracking 'members') -Force
            $root = Join-Path $tracking 'members/product'
        }
        else {
            $null = New-Item -ItemType Directory -Path (Join-Path $repo '.copilot-tracking') -Force
            $root = $tracking
        }
        Copy-Item -LiteralPath $script:FixtureRoot -Destination $root -Recurse
        $root
    }

    function Invoke-VerdictWriter {
        param([string]$Root, $Payload)
        $path = Join-Path $TestDrive "verdict-$([guid]::NewGuid().ToString('N')).json"
        $Payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
        $output = & pwsh -NoProfile -File $script:Writer -SquadRoot $Root -PayloadPath $path -Quiet 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }

    function New-CouncilPayload {
        [ordered]@{
            kind = 'council'
            timestamp = '2026-10-25T16:00:00Z'
            topicId = 'fixture-change'
            topic = 'Apply the fixture change.'
            proposalRef = '.copilot-tracking/plans/fixture.md'
            membersDispatched = @('architect', 'security')
            membersNotProposed = @(
                [ordered]@{ role = 'cost-manager'; reason = 'no billable change' }
            )
            findings = @(
                [ordered]@{
                    role = 'architect'; verdict = 'Approve'; risk = 'Low'
                    blockingIssues = @(); conditions = @(); suggestedFollowUps = @('document the boundary')
                }
                [ordered]@{
                    role = 'security'; verdict = 'Conditional'; risk = 'Risk: Medium'
                    blockingIssues = @(); conditions = @('validate the allowlist'); suggestedFollowUps = @()
                }
            )
        }
    }

    function New-IntakePayload {
        $findings = foreach ($dimension in @('Completeness', 'Clarity', 'Testability', 'Consistency', 'Scope Boundaries')) {
            $nonBlocking = [object[]]@()
            if ($dimension -eq 'Clarity') { $nonBlocking = [object[]]@('define the retry owner') }
            [ordered]@{
                dimension = $dimension
                result = 'pass'
                blockingGaps = @()
                nonBlockingGaps = $nonBlocking
            }
        }
        [ordered]@{
            kind = 'intake'
            timestamp = '2026-10-25T16:05:00Z'
            topicId = 'fixture-input'
            topic = 'Validate the fixture requirements.'
            inputsReviewed = @('.copilot-tracking/plans/fixture.md')
            validatorDispatched = 'PRD Quality Reviewer'
            verdict = 'Ready-With-Gaps'
            remediationCycles = 0
            findings = @($findings)
            clarifyingQuestions = @()
            recordedAssumptions = @('the owner will be named before implementation')
        }
    }

    function New-DiscoveryPayload {
        [ordered]@{
            kind = 'discovery'
            timestamp = '2026-10-25T16:10:00Z'
            topicId = 'fixture-direction'
            topic = 'Choose the fixture direction.'
            optIn = 'explicit-input'
            depth = 'deep'
            rolesDispatched = @('DT Coach', 'PRD Builder')
            brief = '.copilot-tracking/plans/fixture-brief.md'
            handoff = 'pending'
            framing = [ordered]@{
                problem = 'The current fixture has no settled direction.'
                successMeasure = 'One option is selected with explicit trade-offs.'
            }
            options = @(
                [ordered]@{ option = 'Keep the current shape'; outcome = 'discarded'; reason = 'It preserves the slow | ambiguous path.' }
                [ordered]@{ option = 'Use the deterministic writer'; outcome = 'chosen'; reason = 'It is local and auditable.' }
            )
            objections = @('Medium: migration needs a rollback path.')
            riskiestAssumption = 'The existing payload can be mapped without loss; test one real verdict first.'
            openQuestions = @('Who approves the migration?')
        }
    }
}

Describe 'Write-SquadVerdict.ps1 deterministic verdict persistence' {
    It 'ships in the installed squad skill' {
        Test-Path -LiteralPath $script:Writer -PathType Leaf | Should -BeTrue
    }

    It 'derives and writes a schema-complete Council Verdict' {
        $root = New-VerdictRoot
        $result = Invoke-VerdictWriter -Root $root -Payload (New-CouncilPayload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $receipt = $result.Output | ConvertFrom-Json
        $receipt.status | Should -Be 'written'
        $receipt.kind | Should -Be 'council'
        $receipt.label | Should -Be 'Go-With-Conditions'
        $receipt.decisionRef | Should -Match '^\.copilot-tracking/squad/decisions\.md#council-verdict-'
        $text = Get-Content -LiteralPath (Join-Path $root 'decisions.md') -Raw
        $text | Should -Match '(?m)^\* Verdict: Go-With-Conditions\r?$'
        $text | Should -Match '\| security \| Conditional \| Risk: Medium \| none \| validate the allowlist \| none \|'
        $text | Should -Match '(?m)^\* Conditions: \(security\) validate the allowlist\r?$'
        $text | Should -Match '(?m)^\* Conditions Outstanding: 1\r?$'
    }

    It 'writes Intake and Discovery Verdicts without dispatching Scribe' {
        $intakeRoot = New-VerdictRoot
        $intake = Invoke-VerdictWriter -Root $intakeRoot -Payload (New-IntakePayload)
        $intake.ExitCode | Should -Be 0 -Because $intake.Output
        ($intake.Output | ConvertFrom-Json).label | Should -Be 'Ready-With-Gaps'
        $intakeText = Get-Content -LiteralPath (Join-Path $intakeRoot 'decisions.md') -Raw
        $intakeText | Should -Match '(?m)^## Intake Readiness Verdict '
        $intakeText | Should -Match '\| Clarity \| pass \| none \| define the retry owner \|'
        $intakeText | Should -Match '(?m)^\* Permits Downstream Dispatch: yes \(Ready-With-Gaps\)\r?$'

        $discoveryRoot = New-VerdictRoot
        $discovery = Invoke-VerdictWriter -Root $discoveryRoot -Payload (New-DiscoveryPayload)
        $discovery.ExitCode | Should -Be 0 -Because $discovery.Output
        ($discovery.Output | ConvertFrom-Json).label | Should -Be 'deep'
        $discoveryText = Get-Content -LiteralPath (Join-Path $discoveryRoot 'decisions.md') -Raw
        $discoveryText | Should -Match '(?m)^## Discovery Verdict '
        $discoveryText | Should -Match 'slow \\| ambiguous path'
        $discoveryText | Should -Match '(?m)^\* Medium: migration needs a rollback path\.\r?$'
    }

    It 'records a skip verdict with all body sections present and empty' {
        $root = New-VerdictRoot
        $payload = [ordered]@{
            kind = 'discovery'; timestamp = '2026-10-25T16:15:00Z'; topicId = 'fixture-skip'
            topic = 'Skip fixture discovery.'; optIn = 'offer-declined'; depth = 'skip'
            rolesDispatched = @(); brief = 'none'; handoff = 'pending'
            framing = [ordered]@{ problem = ''; successMeasure = '' }
            options = @(); objections = @(); riskiestAssumption = ''; openQuestions = @()
        }
        $result = Invoke-VerdictWriter -Root $root -Payload $payload
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $text = Get-Content -LiteralPath (Join-Path $root 'decisions.md') -Raw
        foreach ($heading in @('### Framing', '### Options Considered', '### Objections', '### Riskiest Assumption', '### Open Questions', '### Discovery Gate')) {
            $text | Should -Match ([regex]::Escape($heading))
        }
        $text | Should -Match '(?m)^\* Roles Dispatched: none\r?$'
        $text | Should -Match '(?m)^\* Brief: none\r?$'

        $abandonedRoot = New-VerdictRoot
        $abandoned = [ordered]@{
            kind = 'discovery'; timestamp = '2026-10-25T16:16:00Z'; topicId = 'fixture-abandoned'
            topic = 'Abandoned fixture discovery.'; optIn = 'offer-accepted'; depth = 'standard'
            rolesDispatched = @('DT Coach'); brief = 'none'; handoff = 'abandoned'
            framing = [ordered]@{ problem = ''; successMeasure = '' }
            options = @(); objections = @(); riskiestAssumption = ''; openQuestions = @()
        }
        $abandonedResult = Invoke-VerdictWriter -Root $abandonedRoot -Payload $abandoned
        $abandonedResult.ExitCode | Should -Be 0 -Because $abandonedResult.Output
        (Get-Content -LiteralPath (Join-Path $abandonedRoot 'decisions.md') -Raw) |
            Should -Match '(?m)^\* Handoff: abandoned\r?$'
    }

    It 'uses the same writer and member-local Decision Ref under a federation' {
        $root = New-VerdictRoot -Member
        $result = Invoke-VerdictWriter -Root $root -Payload (New-CouncilPayload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        ($result.Output | ConvertFrom-Json).decisionRef |
            Should -Match '^\.copilot-tracking/squad/members/product/decisions\.md#council-verdict-'
        Test-Path -LiteralPath (Join-Path $root 'decisions.md') | Should -BeTrue
    }

    It 'rejects a federation meta-root, invalid verdict consistency, and replay without changing decisions' {
        $federationRoot = New-VerdictRoot
        Set-Content -LiteralPath (Join-Path $federationRoot 'federation.md') -Value '# Federation'
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $federationRoot 'decisions.md')))
        $meta = Invoke-VerdictWriter -Root $federationRoot -Payload (New-CouncilPayload)
        $meta.ExitCode | Should -Be 2
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $federationRoot 'decisions.md'))) | Should -BeExactly $before

        $invalidRoot = New-VerdictRoot
        $invalid = New-IntakePayload
        $invalid.verdict = 'Ready'
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $invalidRoot 'decisions.md')))
        $bad = Invoke-VerdictWriter -Root $invalidRoot -Payload $invalid
        $bad.ExitCode | Should -Be 1
        $bad.Output | Should -Match 'Ready cannot carry non-blocking gaps'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $invalidRoot 'decisions.md'))) | Should -BeExactly $before

        $replayRoot = New-VerdictRoot
        $payload = New-CouncilPayload
        (Invoke-VerdictWriter -Root $replayRoot -Payload $payload).ExitCode | Should -Be 0
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $replayRoot 'decisions.md')))
        $replay = Invoke-VerdictWriter -Root $replayRoot -Payload $payload
        $replay.ExitCode | Should -Be 1
        $replay.Output | Should -Match 'replayed payload'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $replayRoot 'decisions.md'))) | Should -BeExactly $before
    }
}
