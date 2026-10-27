#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# AI cost: none; exercises the sealed promotion plan and local transactional writer.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.') ]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Fixture helpers mutate only Pester TestDrive repositories.') ]
param([Parameter(Mandatory)][string]$PackageRoot)

BeforeAll {
    $skillRoot = if (Test-Path -LiteralPath (Join-Path $PackageRoot 'squad-src/.github/skills/squad')) {
        Join-Path $PackageRoot 'squad-src/.github/skills/squad'
    }
    else {
        Join-Path $PackageRoot '.agents/skills/squad'
    }
    $script:Plan = Join-Path $skillRoot 'scripts/Get-SquadPromotionPlan.ps1'
    $script:Promote = Join-Path $skillRoot 'scripts/Promote-SquadFederation.ps1'
    $script:Ledger = Join-Path $skillRoot 'scripts/Measure-SquadLedger.ps1'
    $script:InitContext = Join-Path $skillRoot 'scripts/Get-SquadInitContext.ps1'
    $script:Initialize = Join-Path $skillRoot 'scripts/Initialize-Squad.ps1'
    $script:Handoff = Join-Path $skillRoot 'scripts/Write-SquadHandoff.ps1'
    $script:OriginalCopilotHome = $env:COPILOT_HOME
    $env:COPILOT_HOME = Join-Path $TestDrive 'empty-copilot-home'
    $null = [IO.Directory]::CreateDirectory($env:COPILOT_HOME)

    function Write-Json {
        param([string]$Path, $Value)
        $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
    }

    function Invoke-Local {
        param([string]$Script, [string]$Repo, [string[]]$Arguments = @())
        Push-Location $Repo
        try {
            $output = & pwsh -NoProfile -File $Script @Arguments 2>&1 | Out-String
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
        }
        finally { Pop-Location }
    }

    function Get-TreeHash {
        param([string]$Root)
        if (-not (Test-Path -LiteralPath $Root)) { return '' }
        $lines = @(
            Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
                $relative = [IO.Path]::GetRelativePath($Root, $_.FullName)
                if ($_.PSIsContainer) { "D:$relative" }
                else { "F:${relative}:$($_.Length):$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
            }
        )
        $lines -join "`n"
    }

    function New-PlainSquad {
        $repo = Join-Path $TestDrive ("promotion-$([guid]::NewGuid().ToString('N'))")
        $null = [IO.Directory]::CreateDirectory($repo)
        $agentRoot = Join-Path $repo '.github/agents'
        $null = [IO.Directory]::CreateDirectory($agentRoot)
        foreach ($agent in @('Squad Researcher', 'Squad Lead', 'Squad Implementor', 'Squad Reviewer', 'Squad Scribe')) {
            $file = ($agent.ToLowerInvariant() -replace '[^a-z0-9]+', '-') + '.agent.md'
            [IO.File]::WriteAllText(
                (Join-Path $agentRoot $file),
                "---`nname: $agent`nuser-invocable: false`n---`n`nFixture agent.`n",
                [Text.UTF8Encoding]::new($false)
            )
        }
        $choicesPath = Join-Path $repo 'choices.json'
        $payloadPath = Join-Path $repo 'init.json'
        Write-Json $choicesPath @{
            confirmed = $true
            squadRoot = '.copilot-tracking/squad'
            runId = 'promotion-fixture'
            profile = 'default'
            naming = 'aliases'
            notify = @{ approvalChannel = 'in-chat'; enabled = $false }
            sessionModel = 'claude-sonnet-5.5'
        }
        $prepared = Invoke-Local $script:InitContext $repo @('-RepoRoot', $repo, '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath)
        if ($prepared.ExitCode -ne 0) { throw $prepared.Output }
        $initialized = Invoke-Local $script:Initialize $repo @('-RepoRoot', $repo, '-PayloadPath', $payloadPath, '-Direct')
        if ($initialized.ExitCode -ne 0) { throw $initialized.Output }
        [pscustomobject]@{
            Repo = $repo
            Root = Join-Path $repo '.copilot-tracking/squad'
            Tracking = Join-Path $repo '.copilot-tracking'
        }
    }

    function Add-Candidate {
        param($Fixture, [string]$Name, [string]$File = 'artifact.md')
        $path = Join-Path $Fixture.Tracking $Name
        $null = [IO.Directory]::CreateDirectory($path)
        [IO.File]::WriteAllText((Join-Path $path $File), "# $Name`n", [Text.UTF8Encoding]::new($false))
    }

    function New-Plan {
        param($Fixture, [string]$Name = 'product')
        $path = Join-Path $Fixture.Repo ("plan-$([guid]::NewGuid().ToString('N')).json")
        $result = Invoke-Local $script:Plan $Fixture.Repo @('-RepoRoot', $Fixture.Repo, '-Name', $Name, '-PlanPath', $path)
        if ($result.ExitCode -ne 0) { throw $result.Output }
        [pscustomobject]@{ Path = $path; Result = ($result.Output | ConvertFrom-Json -AsHashtable) }
    }

    function Invoke-Promotion {
        param(
            $Fixture,
            $Plan,
            [string[]]$Relocate = @(),
            [string[]]$Keep = @(),
            [switch]$WithoutConfirmation,
            [string]$Sha,
            [int]$LockTimeoutSeconds = 120
        )
        if (-not $Sha) { $Sha = $Plan.Result.planSha256 }
        $arguments = @(
            '-RepoRoot', $Fixture.Repo,
            '-PlanPath', $Plan.Path,
            '-ExpectedPlanSha256', $Sha,
            '-LockTimeoutSeconds', [string]$LockTimeoutSeconds
        )
        if ($Relocate.Count) { $arguments += '-RelocateDirectory'; $arguments += $Relocate }
        if ($Keep.Count) { $arguments += '-KeepDirectory'; $arguments += $Keep }
        if (-not $WithoutConfirmation) { $arguments += '-Confirmed' }
        Invoke-Local $script:Promote $Fixture.Repo $arguments
    }

    function Set-ExactLedger {
        param($Fixture)
        $artifact = Join-Path $Fixture.Root 'research/exact-ledger.md'
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $artifact))
        [IO.File]::WriteAllText($artifact, '# Exact ledger fixture', [Text.UTF8Encoding]::new($false))
        $payload = Join-Path $Fixture.Repo ("handoff-$([guid]::NewGuid().ToString('N')).json")
        Write-Json $payload @{
            runId = 'promotion-exact-run'
            historyRecords = @(@{
                    agent = 'Squad Researcher'
                    request = 'Produce exact-ledger fixture evidence.'
                    deliverable = '.copilot-tracking/squad/research/exact-ledger.md'
                    outcome = 'Produced exact-ledger fixture evidence.'
                    reportedModel = 'claude-sonnet-4.6'
                })
            stateAdvance = @{ activeRoles = @('Squad Researcher'); sessionModel = 'claude-sonnet-5.5' }
        }
        $handoff = Invoke-Local $script:Handoff $Fixture.Repo @('-SquadRoot', $Fixture.Root, '-PayloadPath', $payload, '-Quiet')
        if ($handoff.ExitCode -ne 0) { throw $handoff.Output }

        $session = Join-Path $Fixture.Repo ("session-$([guid]::NewGuid().ToString('N'))")
        $null = [IO.Directory]::CreateDirectory($session)
        $start = [DateTimeOffset]::UtcNow.AddMinutes(-10)
        $events = @(
            @{
                type = 'session.start'
                timestamp = $start.ToString('o')
                data = @{ sessionId = 'promotion-exact-session' }
            }
            @{
                type = 'subagent.started'
                agentId = 'promotion-researcher'
                timestamp = $start.AddSeconds(1).ToString('o')
                data = @{
                    toolCallId = 'promotion-researcher-call'
                    agentName = 'Squad Researcher'
                    agentDisplayName = 'researcher'
                    model = 'claude-sonnet-4.6'
                }
            }
            @{
                type = 'session.usage_record'
                agentId = 'promotion-researcher'
                timestamp = $start.AddSeconds(2).ToString('o')
                data = @{
                    usage = @{
                        model = 'claude-sonnet-4.6'
                        inputTokens = 180000
                        outputTokens = 10000
                        cacheReadTokens = 80000
                        cacheWriteTokens = 0
                        aiCreditsStatus = 'complete'
                        copilotUsage = @{
                            totalNanoAiu = 47400000000
                            tokenDetails = @(
                                @{ tokenType = 'input'; tokenCount = 100000; batchSize = 1000000; costPerBatch = 300000000000 }
                                @{ tokenType = 'cache_read'; tokenCount = 80000; batchSize = 1000000; costPerBatch = 30000000000 }
                                @{ tokenType = 'cache_write'; tokenCount = 0; batchSize = 1000000; costPerBatch = 375000000000 }
                                @{ tokenType = 'output'; tokenCount = 10000; batchSize = 1000000; costPerBatch = 1500000000000 }
                            )
                        }
                        accounting = @{ sourceSessionId = 'promotion-researcher-session'; usageId = 'one' }
                    }
                }
            }
            @{
                type = 'subagent.completed'
                agentId = 'promotion-researcher'
                timestamp = $start.AddSeconds(3).ToString('o')
                data = @{
                    toolCallId = 'promotion-researcher-call'
                    agentName = 'Squad Researcher'
                    model = 'claude-sonnet-4.6'
                    totalTokens = 190000
                    durationMs = 2000
                }
            }
            @{
                type = 'subagent.started'
                agentId = 'promotion-scribe'
                timestamp = $start.AddSeconds(4).ToString('o')
                data = @{
                    toolCallId = 'promotion-scribe-call'
                    agentName = 'Squad Scribe'
                    agentDisplayName = 'scribe'
                    model = 'claude-haiku-4.5'
                }
            }
            @{
                type = 'session.usage_record'
                agentId = 'promotion-scribe'
                timestamp = $start.AddSeconds(5).ToString('o')
                data = @{
                    usage = @{
                        model = 'claude-haiku-4.5'
                        inputTokens = 60000
                        outputTokens = 5000
                        cacheReadTokens = 40000
                        cacheWriteTokens = 10000
                        aiCreditsStatus = 'complete'
                        copilotUsage = @{
                            totalNanoAiu = 5150000000
                            tokenDetails = @(
                                @{ tokenType = 'input'; tokenCount = 10000; batchSize = 1000000; costPerBatch = 100000000000 }
                                @{ tokenType = 'cache_read'; tokenCount = 40000; batchSize = 1000000; costPerBatch = 10000000000 }
                                @{ tokenType = 'cache_write'; tokenCount = 10000; batchSize = 1000000; costPerBatch = 125000000000 }
                                @{ tokenType = 'output'; tokenCount = 5000; batchSize = 1000000; costPerBatch = 500000000000 }
                            )
                        }
                        accounting = @{ sourceSessionId = 'promotion-scribe-session'; usageId = 'one' }
                    }
                }
            }
            @{
                type = 'subagent.completed'
                agentId = 'promotion-scribe'
                timestamp = $start.AddSeconds(6).ToString('o')
                data = @{
                    toolCallId = 'promotion-scribe-call'
                    agentName = 'Squad Scribe'
                    model = 'claude-haiku-4.5'
                    totalTokens = 65000
                    durationMs = 2000
                }
            }
        )
        $eventText = ($events | ForEach-Object { $_ | ConvertTo-Json -Depth 12 -Compress }) -join "`n"
        [IO.File]::WriteAllText((Join-Path $session 'events.jsonl'), $eventText + "`n", [Text.UTF8Encoding]::new($false))
        $result = Invoke-Local $script:Ledger $Fixture.Repo @('-SquadRoot', $Fixture.Root, '-SessionLog', $session, '-Write')
        if ($result.ExitCode -ne 0) { throw $result.Output }
    }

    function Set-LegacyNullCoverage {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$FileName
        )
        $document = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 100 -DateKind String
        $session = @($document.sessions)[-1]
        $session.historyCoverage[$FileName] = @($null)
        $sortedCoverage = [ordered]@{}
        foreach ($name in @($session.historyCoverage.Keys | Sort-Object)) {
            $sortedCoverage[[string]$name] = @($session.historyCoverage[$name])
        }
        $session['historyCoverage'] = $sortedCoverage
        $null = $session.Remove('contentDigest')
        $material = $session | ConvertTo-Json -Compress -Depth 20
        $session['contentDigest'] = [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($material))
        )
        [IO.File]::WriteAllText($Path, (($document | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
    }
}

AfterAll { $env:COPILOT_HOME = $script:OriginalCopilotHome }

Describe 'Sealed federation promotion planning' {
    It 'is read-only, inventories every tracking directory, and marks roster-owned roots required' {
        $fixture = New-PlainSquad
        Add-Candidate $fixture 'plans'
        Add-Candidate $fixture 'pr'
        $before = Get-TreeHash $fixture.Tracking

        $plan = New-Plan $fixture

        Get-TreeHash $fixture.Tracking | Should -BeExactly $before
        $plan.Result.status | Should -Be 'planned'
        $plan.Result.stateWritten | Should -BeFalse
        $plan.Result.candidates.name | Should -Be @('plans', 'pr')
        ($plan.Result.candidates | Where-Object name -eq 'plans').requiredToRelocate | Should -BeTrue
        ($plan.Result.candidates | Where-Object name -eq 'pr').requiredToRelocate | Should -BeFalse
        (Get-FileHash -LiteralPath $plan.Path).Hash | Should -Be $plan.Result.planSha256
    }

    It 'refuses linked candidates and stale transaction directories without writing a plan' {
        $fixture = New-PlainSquad
        $null = [IO.Directory]::CreateDirectory((Join-Path $fixture.Tracking '.squad-promotion-stale'))
        $path = Join-Path $fixture.Repo 'plan.json'

        $result = Invoke-Local $script:Plan $fixture.Repo @('-RepoRoot', $fixture.Repo, '-Name', 'product', '-PlanPath', $path)

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'Stale promotion transaction directory'
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}

Describe 'Deterministic federation promotion transaction' {
    It 'requires confirmation, the exact plan hash, and an exhaustive candidate partition' {
        $fixture = New-PlainSquad
        Add-Candidate $fixture 'plans'
        Add-Candidate $fixture 'pr'
        $plan = New-Plan $fixture
        $before = Get-TreeHash $fixture.Tracking

        (Invoke-Promotion $fixture $plan -Relocate plans -Keep pr -WithoutConfirmation).ExitCode | Should -Be 1
        (Invoke-Promotion $fixture $plan -Relocate plans -Keep pr -Sha ('0' * 64)).ExitCode | Should -Be 1
        (Invoke-Promotion $fixture $plan -Relocate plans).ExitCode | Should -Be 1
        $requiredKept = Invoke-Promotion $fixture $plan -Relocate pr -Keep plans

        $requiredKept.ExitCode | Should -Be 1
        $requiredKept.Output | Should -Match 'must relocate'
        Get-TreeHash $fixture.Tracking | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $fixture.Root 'federation.md') | Should -BeFalse
    }

    It 'rejects a stale source or candidate without changing the live tree' {
        $fixture = New-PlainSquad
        Add-Candidate $fixture 'plans'
        $plan = New-Plan $fixture
        [IO.File]::AppendAllText((Join-Path $fixture.Root 'decisions.md'), "`nexternal change`n")
        $before = Get-TreeHash $fixture.Tracking

        $result = Invoke-Promotion $fixture $plan -Relocate plans

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'changed after the promotion plan'
        Get-TreeHash $fixture.Tracking | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $fixture.Root 'federation.md') | Should -BeFalse

        $candidateFixture = New-PlainSquad
        Add-Candidate $candidateFixture 'plans'
        $candidatePlan = New-Plan $candidateFixture
        [IO.File]::AppendAllText((Join-Path $candidateFixture.Tracking 'plans/artifact.md'), "`nexternal change`n")
        $candidateBefore = Get-TreeHash $candidateFixture.Tracking

        $candidateResult = Invoke-Promotion $candidateFixture $candidatePlan -Relocate plans

        $candidateResult.ExitCode | Should -Be 1
        $candidateResult.Output | Should -Match "candidate 'plans' changed"
        Get-TreeHash $candidateFixture.Tracking | Should -BeExactly $candidateBefore
    }

    It 'refuses a deliverable collision before any source path moves' {
        $fixture = New-PlainSquad
        Add-Candidate $fixture 'plans'
        $null = [IO.Directory]::CreateDirectory((Join-Path $fixture.Root 'plans'))
        [IO.File]::WriteAllText((Join-Path $fixture.Root 'plans/state-owned.md'), '# state', [Text.UTF8Encoding]::new($false))
        $plan = New-Plan $fixture
        $before = Get-TreeHash $fixture.Tracking

        $result = Invoke-Promotion $fixture $plan -Relocate plans

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'collides with existing squad state'
        Get-TreeHash $fixture.Tracking | Should -BeExactly $before
    }

    It 'promotes a newly initialized squad with no candidate directories' {
        $fixture = New-PlainSquad
        $plan = New-Plan $fixture

        $result = Invoke-Promotion $fixture $plan

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $receipt = $result.Output | ConvertFrom-Json
        @($receipt.relocatedDirectories).Count | Should -Be 0
        @($receipt.keptDirectories).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $fixture.Root 'members/product/team.md') | Should -BeTrue
    }

    It 'times out behind the ordinary writer lock and cleans its unpublished stage' {
        $fixture = New-PlainSquad
        $plan = New-Plan $fixture
        $before = Get-TreeHash $fixture.Tracking
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
                [Text.UTF8Encoding]::new($false).GetBytes($fixture.Root.ToLowerInvariant())
            )).Substring(0, 16)
        $lockPath = Join-Path ([IO.Path]::GetTempPath()) "hve-squad-handoff-$hash.lock"
        $lock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            $result = Invoke-Promotion $fixture $plan -LockTimeoutSeconds 1
        }
        finally { $lock.Dispose() }

        $result.ExitCode | Should -Be 8
        $result.Output | Should -Match 'lock timed out'
        Get-TreeHash $fixture.Tracking | Should -BeExactly $before
        @((Get-ChildItem -LiteralPath $fixture.Tracking -Directory -Force | Where-Object Name -like '.squad-promotion-*')).Count | Should -Be 0
    }

    It 'promotes in seconds, preserves append-only prefixes, moves selected artifacts, and keeps explicit exclusions' {
        $fixture = New-PlainSquad
        Add-Candidate $fixture 'plans' 'existing-plan.md'
        Add-Candidate $fixture 'pr' 'keep.md'
        $memberDecisions = [IO.File]::ReadAllBytes((Join-Path $fixture.Root 'decisions.md'))
        $scribePrefix = [IO.File]::ReadAllBytes((Join-Path $fixture.Root 'history/Squad Scribe.md'))
        $plan = New-Plan $fixture

        $result = Invoke-Promotion $fixture $plan -Relocate plans -Keep pr

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $receipt = $result.Output | ConvertFrom-Json -AsHashtable
        $receipt.verified | Should -BeTrue
        $receipt.elapsedMs | Should -BeLessThan 30000
        $receipt.relocatedDirectories | Should -Be @('plans')
        $receipt.keptDirectories | Should -Be @('pr')
        Test-Path -LiteralPath (Join-Path $fixture.Root 'team.md') | Should -BeFalse
        $member = Join-Path $fixture.Root 'members/product'
        Test-Path -LiteralPath (Join-Path $member 'plans/existing-plan.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture.Tracking 'plans') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fixture.Tracking 'pr/keep.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture.Root 'federation.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture.Root 'meta-routing.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture.Root 'history/product.md') | Should -BeTrue
        [IO.File]::ReadAllBytes((Join-Path $member 'decisions.md')) | Should -Be $memberDecisions
        $scribeAfter = [IO.File]::ReadAllBytes((Join-Path $member 'history/Squad Scribe.md'))
        $scribeAfter.Length | Should -BeGreaterThan $scribePrefix.Length
        [Text.Encoding]::UTF8.GetString($scribeAfter, 0, $scribePrefix.Length) |
            Should -BeExactly ([Text.Encoding]::UTF8.GetString($scribePrefix))
        $team = [IO.File]::ReadAllText((Join-Path $member 'team.md'))
        $team | Should -Match ([regex]::Escape('.copilot-tracking/squad/members/product/plans/'))
        $team | Should -Not -Match '\|\s*\.copilot-tracking/plans/'
        $rootState = Get-Content -LiteralPath (Join-Path $fixture.Root 'state.json') -Raw | ConvertFrom-Json
        $memberState = Get-Content -LiteralPath (Join-Path $member 'state.json') -Raw | ConvertFrom-Json
        $rootState.currentRun.estCostUsd | Should -Be $memberState.currentRun.estCostUsd
        $rootState.currentRun.estCreditsTotal | Should -Be $memberState.currentRun.estCreditsTotal
        @((Get-ChildItem -LiteralPath $fixture.Tracking -Directory -Force | Where-Object Name -like '.squad-promotion-*')).Count | Should -Be 0

        $replay = Invoke-Promotion $fixture $plan -Relocate plans -Keep pr
        $replay.ExitCode | Should -Be 4
        $replay.Output | Should -Match 'already promoted'
    }

    It 'preserves an exact ledger and adds no fictional promotion consumption' {
        $fixture = New-PlainSquad
        Set-ExactLedger $fixture
        $stateBefore = Get-Content -LiteralPath (Join-Path $fixture.Root 'state.json') -Raw | ConvertFrom-Json
        $ledgerBefore = [IO.File]::ReadAllBytes((Join-Path $fixture.Root 'consumption.md'))
        $journalPath = Join-Path $fixture.Root 'consumption-sessions.json'
        Set-LegacyNullCoverage -Path $journalPath -FileName 'Squad Lead.md'
        $journalBeforeText = [IO.File]::ReadAllText($journalPath)
        $journalBeforeText | Should -Match '"Squad Lead\.md"\s*:\s*\[\s*null\s*\]'
        $journalBefore = $journalBeforeText | ConvertFrom-Json
        $recordsBefore = ($journalBefore.sessions | Measure-Object records -Sum).Sum
        $sessionIdsBefore = @($journalBefore.sessions.sessionId)
        $plan = New-Plan $fixture
        $plan.Result.exactSessionJournal | Should -Be 'included'

        $result = Invoke-Promotion $fixture $plan

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $receipt = $result.Output | ConvertFrom-Json
        $receipt.exactSessionJournal | Should -Be 'preserved'
        $member = Join-Path $fixture.Root 'members/product'
        $memberState = Get-Content -LiteralPath (Join-Path $member 'state.json') -Raw | ConvertFrom-Json
        $rootState = Get-Content -LiteralPath (Join-Path $fixture.Root 'state.json') -Raw | ConvertFrom-Json
        $memberState.currentRun.estCostUsd | Should -Be $stateBefore.currentRun.estCostUsd
        $memberState.currentRun.estCreditsTotal | Should -Be $stateBefore.currentRun.estCreditsTotal
        $rootState.currentRun.estCostUsd | Should -Be $stateBefore.currentRun.estCostUsd
        $rootState.currentRun.estCreditsTotal | Should -Be $stateBefore.currentRun.estCreditsTotal
        [IO.File]::ReadAllBytes((Join-Path $member 'consumption.md')) | Should -Be $ledgerBefore
        $journalAfterText = [IO.File]::ReadAllText((Join-Path $member 'consumption-sessions.json'))
        $journalAfterText | Should -Not -Match '"Squad Lead\.md"\s*:\s*\[\s*null\s*\]'
        $journalAfter = $journalAfterText | ConvertFrom-Json
        ($journalAfter.sessions | Measure-Object records -Sum).Sum | Should -Be $recordsBefore
        @($journalAfter.sessions.sessionId) | Should -Be $sessionIdsBefore
        $ledger = [IO.File]::ReadAllText((Join-Path $member 'consumption.md'))
        $ledger | Should -Match 'Exact Cost \(USD\)'
        $ledger | Should -Not -Match 'Est\. Cost \(USD\)'
        $scribe = [IO.File]::ReadAllText((Join-Path $member 'history/Squad Scribe.md'))
        $promotionEntry = [regex]::Match($scribe, '(?ms)^###[^\r\n]* Federation promotion[^\r\n]*\r?\n.*\z').Value
        $promotionEntry | Should -Not -BeNullOrEmpty
        $promotionEntry | Should -Not -Match '#### Consumption'
    }

    It 'supports an ordinary deterministic member handoff immediately after promotion' {
        $fixture = New-PlainSquad
        Add-Candidate $fixture 'changes'
        $plan = New-Plan $fixture
        $promotion = Invoke-Promotion $fixture $plan -Relocate changes
        $promotion.ExitCode | Should -Be 0 -Because $promotion.Output
        $member = Join-Path $fixture.Root 'members/product'
        $artifact = Join-Path $member 'changes/post-promotion.md'
        [IO.File]::WriteAllText($artifact, '# Post promotion', [Text.UTF8Encoding]::new($false))
        $payload = Join-Path $fixture.Repo 'handoff.json'
        Write-Json $payload @{
            runId = 'promotion-fixture'
            historyRecords = @(@{
                    agent = 'Squad Implementor'
                    request = 'Verify promoted member continuity'
                    deliverable = '.copilot-tracking/squad/members/product/changes/post-promotion.md'
                    outcome = 'Wrote through the promoted member root.'
                    reportedModel = 'claude-sonnet-5.5'
                })
            decision = @{ title = 'Post-promotion continuity'; rationale = 'Use the ordinary member writer.'; adrNoted = $false }
            stateAdvance = @{ activeRoles = @('Squad Implementor'); sessionModel = 'claude-sonnet-5.5' }
        }

        $result = Invoke-Local $script:Handoff $fixture.Repo @('-SquadRoot', $member, '-PayloadPath', $payload, '-Quiet')

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $status = ($result.Output.Trim().Split("`n") | Where-Object { $_ -match '^\{' } | Select-Object -Last 1) | ConvertFrom-Json
        $status.ledgerCheck | Should -Be 'PASS'
        $status.turn | Should -Be 3
    }
}
