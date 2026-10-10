#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Behavioral coverage for the read-only dispatch brief, squad skill
# scripts/Get-SquadDispatchBrief.ps1. Runs the script as a child process against TestDrive
# repositories, because it calls `exit`. Invokes no model.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    $script:Script = Join-Path $PackageRoot '.agents/skills/squad/scripts/Get-SquadDispatchBrief.ps1'
    $script:Utf8 = [System.Text.UTF8Encoding]::new($false)

    function Invoke-Brief {
        param([Parameter(Mandatory)][string]$Repo, [string[]]$Extra = @())
        Push-Location $Repo
        try {
            $output = & pwsh -NoProfile -File $script:Script -SquadRoot '.copilot-tracking/squad' @Extra 2>&1 | Out-String
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
        }
        finally { Pop-Location }
    }

    function Write-Text {
        param([string]$Path, [string]$Text)
        New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
        [System.IO.File]::WriteAllText($Path, $Text, $script:Utf8)
    }

    function New-BriefRepo {
        param(
            [switch]$Uninitialized,
            [switch]$Ceiling,
            [switch]$StubLedger,
            [switch]$BlockedReviewer,
            [switch]$ModelColumn,
            [switch]$DriftedHeader,
            [AllowEmptyString()][string]$Routing = 'economy',
            [string]$Alternate = '—'
        )
        $modeLines = if ($Routing) { @("Model routing: $Routing", '') } else { @() }
        $repo = Join-Path $TestDrive "repo-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        $squad = Join-Path $repo '.copilot-tracking/squad'
        New-Item -ItemType Directory -Path $squad -Force | Out-Null
        $agents = Join-Path $repo '.github/agents'
        Write-Text (Join-Path $agents 'squad-implementor.agent.md') "---`nname: Squad Implementor`nmodel: Claude Sonnet 5 (copilot)`n---`n`nBody.`n"
        $flag = if ($BlockedReviewer) { "disable-model-invocation: true`n" } else { '' }
        Write-Text (Join-Path $agents 'squad-reviewer.agent.md') "---`nname: Squad Reviewer`n$($flag)model: Claude Haiku 4.5 (copilot)`n---`n`nBody.`n"
        if ($Uninitialized) { return $repo }
        $team = if ($ModelColumn) {
            @(
                '# Squad Team', '') + $modeLines + @('## Members', '',
                '| Role | Member Name | Agent Name (Primary) | Alternate Agents | Selection Cue | Invocation | Model Tier | Model | Deliverable Root |',
                '| ---- | ----------- | -------------------- | ---------------- | ------------- | ---------- | ---------- | ----- | ---------------- |',
                '| developer | Dev | Squad Implementor | — | — | task | default | `claude-haiku-4.5` | `.copilot-tracking/changes/` |',
                '| tester | Rev | Squad Reviewer | — | — | task | fast | — | `.copilot-tracking/reviews/` |'
            )
        }
        elseif ($DriftedHeader) {
            @(
                '# Squad Team', '') + $modeLines + @('## Members', '',
                '| Primary Agent | Role | Deliverable Root | Model Tier | Member Name |',
                '| ------------- | ---- | ---------------- | ---------- | ----------- |',
                '| Squad Implementor | developer | `.copilot-tracking/changes/` | default | Dev |',
                '| Squad Reviewer | tester | `.copilot-tracking/reviews/` | fast | Rev |'
            )
        }
        else {
            @(
                '# Squad Team', '') + $modeLines + @('## Members', '',
                '| Role | Member Name | Agent Name (Primary) | Alternate Agents | Selection Cue | Invocation | Model Tier | Deliverable Root |',
                '| ---- | ----------- | -------------------- | ---------------- | ------------- | ---------- | ---------- | ---------------- |',
                "| developer | Dev | Squad Implementor | $Alternate | when a second opinion is asked | task | default | ``.copilot-tracking/changes/`` |",
                '| tester | Rev | Squad Reviewer | — | — | task | fast | `.copilot-tracking/reviews/` |'
            )
        }
        Write-Text (Join-Path $squad 'team.md') ($team -join "`n")
        $preflight = if ($Ceiling) { '{"ceilingUsd":5,"decision":"within-ceiling"}' } else { '{"ceilingUsd":null,"decision":"not-requested"}' }
        Write-Text (Join-Path $squad 'state.json') ('{"schemaVersion":"1.4","updated":"2026-10-03T18:00:00Z","turn":4,"mode":"interactive","currentRun":{"costPreflight":' + $preflight + '}}')
        $ledger = if ($StubLedger) { "# Squad Consumption Ledger`n" } else { "# Squad Consumption Ledger`n`n## Attribution`n`n## Usage & Cost`n`n### Derivation`n" }
        Write-Text (Join-Path $squad 'consumption.md') $ledger
        $repo
    }

    function Get-TreeHash {
        param([string]$Root)
        (Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash }) -join ','
    }
}

Describe 'Get-SquadDispatchBrief.ps1' {
    It 'forwards selected-delegate ownership and cold worker routing when the brief replaces normal reference reads' {
        $result = Invoke-Brief -Repo (New-BriefRepo)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Delegating parents additionally read delegated-worker-routing.md'
        $result.Output | Should -Match 'admit only a selected delegate.*never inherit a discounted owner pick'
    }

    It 'ships with the squad skill' {
        Test-Path -LiteralPath $script:Script | Should -BeTrue
    }

    It 'refuses an uninitialized squad (no team.md) with exit 7' {
        $result = Invoke-Brief -Repo (New-BriefRepo -Uninitialized)
        $result.ExitCode | Should -Be 7 -Because $result.Output
        $result.Output | Should -Not -Match 'Squad Dispatch Brief'
    }

    It 'refuses with exit 7 and prints no brief when team.md records <Case> (G2)' -ForEach @(
        @{ Case = 'Model routing: ranked'; Routing = 'ranked' }
        @{ Case = 'Model routing: manual'; Routing = 'manual' }
        @{ Case = 'no Model routing line'; Routing = '' }
    ) {
        $repo = New-BriefRepo -Routing $Routing
        $before = Get-TreeHash -Root $repo
        $result = Invoke-Brief -Repo $repo
        $result.ExitCode | Should -Be 7 -Because $result.Output
        $result.Output | Should -Match 'economy-only'
        $result.Output | Should -Not -Match 'Squad Dispatch Brief'
        Get-TreeHash -Root $repo | Should -Be $before
    }

    It 'fails the precheck for an Alternate that is not installed' {
        $result = Invoke-Brief -Repo (New-BriefRepo -Alternate 'Squad Ghost')
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match ([regex]::Escape('roster precheck (Step 1b): FAIL for developer alternate -> Squad Ghost (not installed)'))
    }

    It 'fails the precheck for an Alternate with disable-model-invocation' {
        $result = Invoke-Brief -Repo (New-BriefRepo -BlockedReviewer -Alternate 'Squad Reviewer')
        $result.Output | Should -Match ([regex]::Escape('developer alternate -> Squad Reviewer (disable-model-invocation)'))
    }

    It 'prints the roster by column header with pins, rate rows, dispatchability, the next turn, and the procedure, and writes nothing' {
        $repo = New-BriefRepo
        $before = Get-TreeHash -Root $repo
        $result = Invoke-Brief -Repo $repo -Extra @('-SessionModel', 'claude-sonnet-5')
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match ([regex]::Escape('next hand-off turn: 5'))
        $result.Output | Should -Match ([regex]::Escape('updated 2026-10-03T18:00:00Z'))
        $result.Output | Should -Match ([regex]::Escape('model routing: economy'))
        $result.Output | Should -Match ([regex]::Escape('| Role | Agent | Dispatchable | Pin | Priced as (tier) | Deliverable root |'))
        $result.Output | Should -Match ([regex]::Escape('| developer | Squad Implementor | yes | Claude Sonnet 5 | Claude Sonnet 5 (default) | .copilot-tracking/changes/ |'))
        $result.Output | Should -Match ([regex]::Escape('| tester | Squad Reviewer | yes | Claude Haiku 4.5 | Claude Haiku 4.5 (fast) | .copilot-tracking/reviews/ |'))
        $result.Output | Should -Match ([regex]::Escape('roster precheck (Step 1b): PASS'))
        $result.Output | Should -Match ([regex]::Escape('never `general-purpose`'))
        $result.Output | Should -Match 'coverage: for a request that meets every Bounded Lane criterion'
        $result.Output | Should -Match '"model":"Claude Sonnet 5","model_source":"agent-pinned","priced_as":"Claude Sonnet 5"'
        $result.Output | Should -Match '"model_source":"session-inherited"'
        $result.Output | Should -Match '(?m)^## Bounded Lane'
        $result.Output | Should -Match '(?m)^## Plan-Driven Parallelism'
        $result.Output | Should -Match '(?m)^## Scripted Writes'
        $result.Output | Should -Match ([regex]::Escape('This is a complete, valid payload:'))
        $result.Output | Should -Match '(?m)^```json'
        $result.Output | Should -Not -Match 'not found in'
        Get-TreeHash -Root $repo | Should -Be $before
    }

    It 'picks no model: no bounded pick, no route helper call, and no Model column when the roster has none' {
        $result = Invoke-Brief -Repo (New-BriefRepo)
        $result.Output | Should -Not -Match '(?i)bounded pick|boundedPick|-Bounded'
        $result.Output | Should -Not -Match '\| Model \|'
        $result.Output | Should -Not -Match 'on its Model cell'
    }

    It 'prints each role''s Model cell under routing and prices the dispatch on it' {
        $result = Invoke-Brief -Repo (New-BriefRepo -ModelColumn) -Extra @('-SessionModel', 'claude-sonnet-5')
        $result.Output | Should -Match ([regex]::Escape('model routing: economy'))
        $result.Output | Should -Match ([regex]::Escape('| Role | Agent | Dispatchable | Pin | Model | Priced as (tier) | Deliverable root |'))
        $result.Output | Should -Match ([regex]::Escape('| developer | Squad Implementor | yes | Claude Sonnet 5 | claude-haiku-4.5 | Claude Haiku 4.5 (fast) | .copilot-tracking/changes/ |'))
        $result.Output | Should -Match ([regex]::Escape('| tester | Squad Reviewer | yes | Claude Haiku 4.5 | none | Claude Haiku 4.5 (fast) | .copilot-tracking/reviews/ |'))
        $result.Output | Should -Match ([regex]::Escape('developer on its Model cell (add `"passedModel": "claude-haiku-4.5"`)'))
        $result.Output | Should -Match '"model":"claude-haiku-4.5","model_source":"cli-pinned","priced_as":"Claude Haiku 4.5"'
        $result.Output | Should -Match ([regex]::Escape('Pass each role''s Model cell as the dispatch `model` exactly as written'))
    }

    It 'reads team.md by header name, so a reordered or drifted header still maps each column' {
        $result = Invoke-Brief -Repo (New-BriefRepo -DriftedHeader)
        $result.Output | Should -Match ([regex]::Escape('| developer | Squad Implementor | yes | Claude Sonnet 5 | Claude Sonnet 5 (default) | .copilot-tracking/changes/ |'))
        $result.Output | Should -Match ([regex]::Escape('| tester | Squad Reviewer | yes | Claude Haiku 4.5 | Claude Haiku 4.5 (fast) | .copilot-tracking/reviews/ |'))
        $result.Output | Should -Match ([regex]::Escape('roster precheck (Step 1b): PASS'))
    }

    It 'gives the Scribe the hand-off command line and tells the coordinator never to run it' {
        $result = Invoke-Brief -Repo (New-BriefRepo)
        $result.Output | Should -Match ([regex]::Escape('Dispatch the Squad Scribe with the payload JSON and this exact command line, which the Scribe runs as its first action; never run it yourself:'))
        $result.Output | Should -Match '`pwsh -File ''[^'']+Write-SquadHandoff\.ps1'' -SquadRoot ''[^'']+'' -PayloadPath <payload\.json>`'
        $result.Output | Should -Not -Match ([regex]::Escape('-PayloadJson $p'))
        $result.Output | Should -Not -Match '(?m)^### Script Hand-off'
    }

    It 'stays under the host inline output limit' {
        $result = Invoke-Brief -Repo (New-BriefRepo) -Extra @('-SessionModel', 'claude-sonnet-5')
        [System.Text.Encoding]::UTF8.GetByteCount($result.Output) | Should -BeLessThan 20480
        $result.Output | Should -Not -Match 'WARN brief exceeds'
    }

    It 'flags a disable-model-invocation Primary as not dispatchable and fails the precheck' {
        $result = Invoke-Brief -Repo (New-BriefRepo -BlockedReviewer)
        $result.Output | Should -Match '\| tester \| Squad Reviewer \| no \(disable-model-invocation\) \|'
        $result.Output | Should -Match ([regex]::Escape('roster precheck (Step 1b): FAIL for tester -> Squad Reviewer'))
    }

    It 'withdraws coverage under an active cost ceiling' {
        $result = Invoke-Brief -Repo (New-BriefRepo -Ceiling)
        $result.Output | Should -Match 'cost ceiling: active'
        $result.Output | Should -Match 'coverage: NONE'
    }

    It 'reports a stub ledger so no Scribe repair is dispatched' {
        $result = Invoke-Brief -Repo (New-BriefRepo -StubLedger)
        $result.Output | Should -Match ([regex]::Escape('ledger: stub (do not dispatch the Scribe to repair it'))
    }
}

Describe 'Get-SquadDispatchBrief.ps1 consent and Route markers (B1)' {
    It 'prints consent: missing and a WARN to record consent before any dispatch when decisions.md is absent' {
        $result = Invoke-Brief -Repo (New-BriefRepo)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match '(?m)^consent: missing\r?$'
        $result.Output | Should -Match ([regex]::Escape('WARN economy consent not recorded: before any dispatch, state the trade once (economy-mode.md Consent) and hand the Scribe the ## Economy Mode Accepted decision'))
    }

    It 'prints consent: missing when decisions.md has no Economy Mode Accepted entry' {
        $repo = New-BriefRepo
        Write-Text (Join-Path $repo '.copilot-tracking/squad/decisions.md') "# Squad Decisions`n`n## 2026-10-03T17:00:00Z Init`n`n* Seeded.`n"
        (Invoke-Brief -Repo $repo).Output | Should -Match '(?m)^consent: missing\r?$'
    }

    It 'prints consent: recorded, without the WARN, once the decision exists' {
        $repo = New-BriefRepo
        Write-Text (Join-Path $repo '.copilot-tracking/squad/decisions.md') "# Squad Decisions`n`n## Economy Mode Accepted 2026-10-03T17:30:00Z`n`n* User: Fixture`n* Previous mode: ranked`n* Trade accepted: cheaper picks`n* Never weakened: every gate`n"
        $result = Invoke-Brief -Repo $repo
        $result.Output | Should -Match '(?m)^consent: recorded\r?$'
        $result.Output | Should -Not -Match '(?m)^WARN economy consent not recorded'
    }

    It 'reminds the coordinator that every history record needs Route: economy or Route: bounded' {
        (Invoke-Brief -Repo (New-BriefRepo)).Output | Should -Match ([regex]::Escape('route markers: every history record needs routingIdentity whose routeRationale starts with Route: economy, or Route: bounded on the Bounded Lane'))
    }

    It 'still refuses outside economy with exit 7 before any consent check' {
        $result = Invoke-Brief -Repo (New-BriefRepo -Routing 'ranked')
        $result.ExitCode | Should -Be 7
        $result.Output | Should -Not -Match 'consent:'
    }
}
