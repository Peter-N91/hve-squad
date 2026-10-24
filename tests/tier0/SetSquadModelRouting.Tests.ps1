#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll.')]
param([Parameter(Mandatory)][string]$PackageRoot)

BeforeAll {
    $script:Script = Join-Path $PackageRoot '.agents/skills/squad/scripts/Set-SquadModelRouting.ps1'
    $script:Utf8 = [Text.UTF8Encoding]::new($false)

    function New-RoutingFixture {
        param([ValidateSet('off', 'ranked', 'economy', 'manual')][string]$Mode = 'ranked')
        $repo = Join-Path $TestDrive ("routing-$([guid]::NewGuid().ToString('N'))")
        $root = Join-Path $repo '.copilot-tracking/squad'
        $null = [IO.Directory]::CreateDirectory($root)
        $team = if ($Mode -eq 'off') {
            @(
                '# Squad Roster'
                ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Deliverable Root |'
                '| ---- | ----------- | -------------------- | ---------- | ---------------- |'
                '| developer | Dev | Squad Implementor | default | `.copilot-tracking/changes/` |'
                '| tester | Rev | Squad Reviewer | fast | `.copilot-tracking/reviews/` |'
            ) -join "`n"
        }
        else {
            @(
                '# Squad Roster'
                "Model routing: $Mode"
                ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '| ---- | ----------- | -------------------- | ---------- | ----- | ---------------- |'
                '| developer | Dev | Squad Implementor | default | `old-model` | `.copilot-tracking/changes/` |'
                '| tester | Rev | Squad Reviewer | fast | `gpt-6-sol` | `.copilot-tracking/reviews/` |'
            ) -join "`n"
        }
        [IO.File]::WriteAllText((Join-Path $root 'team.md'), $team, $script:Utf8)
        [IO.File]::WriteAllText((Join-Path $root 'decisions.md'), "# Decisions`n", $script:Utf8)
        [pscustomobject]@{ Repo = $repo; Root = $root }
    }

    function New-RoutingPlan {
        param(
            $Fixture,
            [string]$Hash,
            [bool]$Required = $true,
            [ValidateSet('off', 'ranked', 'economy', 'manual')][string]$RecordedMode = 'ranked',
            [ValidateSet('ranked', 'economy', 'manual')][string]$Mode = 'ranked',
            $EconomyConsent
        )
        $path = Join-Path $Fixture.Repo ("plan-$([guid]::NewGuid().ToString('N')).json")
        $from = if ($RecordedMode -eq 'off') { '' } else { 'old-model' }
        @{
            status = 'ok'
            kind = 'squad'
            units = @(@{ endpoint = @{
                        squadRoot = $Fixture.Root
                        role = 'developer'
                        memberName = 'Dev'
                        model = 'gpt-5.6-sol'
                        persistedModel = $from
                        modelRouting = $Mode
                    } })
            routingRefresh = @{
                required = $Required
                recordedMode = $RecordedMode
                mode = $Mode
                expectedTeamHash = $Hash
                changes = if ($Required) {
                    ,([ordered]@{ role = 'developer'; memberName = 'Dev'; from = $from; to = 'gpt-5.6-sol'; rationale = 'fixture' })
                }
                else { @() }
                economyConsent = $EconomyConsent
            }
        } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
        $path
    }

    function Invoke-RoutingRefresh {
        param([string]$Repo, [string]$Plan)
        $output = & pwsh -NoProfile -File $script:Script -RepoRoot $Repo -PlanPath $Plan 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

Describe 'Set-SquadModelRouting deterministic transaction' {
    It 'changes only the planned Model cell and appends one decision' {
        $fixture = New-RoutingFixture
        $hash = (Get-FileHash -LiteralPath (Join-Path $fixture.Root 'team.md') -Algorithm SHA256).Hash
        $plan = New-RoutingPlan $fixture $hash
        $result = Invoke-RoutingRefresh $fixture.Repo $plan
        $result.ExitCode | Should -Be 0 -Because $result.Output
        ($result.Output | ConvertFrom-Json).status | Should -Be 'written'

        $team = [IO.File]::ReadAllText((Join-Path $fixture.Root 'team.md'))
        $team | Should -Match '\| developer \| Dev \| Squad Implementor \| default \| `gpt-5\.6-sol` \|'
        $team | Should -Match '\| tester \| Rev \| Squad Reviewer \| fast \| `gpt-6-sol` \|'
        $decisions = [IO.File]::ReadAllText((Join-Path $fixture.Root 'decisions.md'))
        ([regex]::Matches($decisions, '(?m)^## Model Routing Refresh ')).Count | Should -Be 1
        $decisions | Should -Match '\* developer / Dev: old-model -> gpt-5\.6-sol'
    }

    It 'rejects a stale team hash and preserves both files byte-for-byte' {
        $fixture = New-RoutingFixture
        $plan = New-RoutingPlan $fixture ('0' * 64)
        $teamBefore = [IO.File]::ReadAllBytes((Join-Path $fixture.Root 'team.md'))
        $decisionsBefore = [IO.File]::ReadAllBytes((Join-Path $fixture.Root 'decisions.md'))
        $result = Invoke-RoutingRefresh $fixture.Repo $plan
        $result.ExitCode | Should -Be 2
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $fixture.Root 'team.md'))) | Should -BeExactly ([Convert]::ToBase64String($teamBefore))
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $fixture.Root 'decisions.md'))) | Should -BeExactly ([Convert]::ToBase64String($decisionsBefore))
    }

    It 'returns unchanged without touching files when the plan needs no refresh' {
        $fixture = New-RoutingFixture
        $hash = (Get-FileHash -LiteralPath (Join-Path $fixture.Root 'team.md') -Algorithm SHA256).Hash
        $plan = New-RoutingPlan $fixture $hash $false
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $fixture.Root 'team.md')))
        $result = Invoke-RoutingRefresh $fixture.Repo $plan
        $result.ExitCode | Should -Be 0
        ($result.Output | ConvertFrom-Json).status | Should -Be 'unchanged'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $fixture.Root 'team.md'))) | Should -BeExactly $before
    }

    It 'switches off to <Mode> by adding the mode line and Model column without Scribe' -ForEach @(
        @{ Mode = 'ranked' }
        @{ Mode = 'manual' }
    ) {
        $fixture = New-RoutingFixture -Mode off
        $hash = (Get-FileHash -LiteralPath (Join-Path $fixture.Root 'team.md') -Algorithm SHA256).Hash
        $plan = New-RoutingPlan $fixture $hash $true off $Mode
        $result = Invoke-RoutingRefresh $fixture.Repo $plan
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $team = [IO.File]::ReadAllText((Join-Path $fixture.Root 'team.md'))
        $team | Should -Match "(?m)^Model routing: $Mode$"
        $team | Should -Match '\| Model Tier \| Model \| Deliverable Root \|'
        $team | Should -Match '\| developer \| Dev \| Squad Implementor \| default \| `gpt-5\.6-sol` \|'
        $team | Should -Match '\| tester \| Rev \| Squad Reviewer \| fast \|  \|'
    }

    It 'switches off to economy and records the accepted trade in the same transaction' {
        $fixture = New-RoutingFixture -Mode off
        $hash = (Get-FileHash -LiteralPath (Join-Path $fixture.Root 'team.md') -Algorithm SHA256).Hash
        $consent = [ordered]@{
            user = 'Peter'
            tradeAccepted = 'Cost-first qualified implementation routing.'
            neverWeakened = 'Floors, gates, and review stay unchanged.'
            timestamp = '2026-10-24T16:00:00Z'
        }
        $plan = New-RoutingPlan $fixture $hash $true off economy $consent
        $result = Invoke-RoutingRefresh $fixture.Repo $plan
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $decisions = [IO.File]::ReadAllText((Join-Path $fixture.Root 'decisions.md'))
        $decisions | Should -Match '(?m)^## Economy Mode Accepted 2026-10-24T16:00:00\.0000000\+00:00$'
        $decisions | Should -Match '\* User: Peter'
        $decisions | Should -Match '\* Previous mode: off'
        $decisions | Should -Match '\* Trade accepted: Cost-first qualified implementation routing\.'
    }
}
