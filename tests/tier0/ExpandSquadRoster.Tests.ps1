#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# AI cost: none; exercises sealed additive roster expansion for plain/member roots.

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
    $script:Plan = Join-Path $skillRoot 'scripts/Get-SquadRosterExpansionPlan.ps1'
    $script:Expand = Join-Path $skillRoot 'scripts/Expand-SquadRoster.ps1'
    $script:InitPlan = Join-Path $skillRoot 'scripts/Get-SquadInitContext.ps1'
    $script:Initialize = Join-Path $skillRoot 'scripts/Initialize-Squad.ps1'
    $script:FederationPlan = Join-Path $skillRoot 'scripts/Get-SquadFederationInitPlan.ps1'
    $script:FederationInitialize = Join-Path $skillRoot 'scripts/Initialize-SquadFederation.ps1'
    $script:Handoff = Join-Path $skillRoot 'scripts/Write-SquadHandoff.ps1'
    $script:Ledger = Join-Path $skillRoot 'scripts/Measure-SquadLedger.ps1'
    $script:OriginalCopilotHome = $env:COPILOT_HOME
    $env:COPILOT_HOME = Join-Path $TestDrive 'empty-copilot-home'
    $null = [IO.Directory]::CreateDirectory($env:COPILOT_HOME)

    function Write-Json {
        param([string]$Path, $Value)
        [IO.File]::WriteAllText(
            $Path,
            ($Value | ConvertTo-Json -Depth 40),
            [Text.UTF8Encoding]::new($false)
        )
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
        @(
            Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
                $relative = [IO.Path]::GetRelativePath($Root, $_.FullName)
                if ($_.PSIsContainer) { "D:$relative" }
                else { "F:${relative}:$($_.Length):$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
            }
        ) -join "`n"
    }

    function New-Agent {
        param([string]$Root, [string]$Name)
        $file = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-') + '.agent.md'
        [IO.File]::WriteAllText(
            (Join-Path $Root $file),
            "---`nname: $Name`nuser-invocable: false`n---`n`nFixture agent.`n",
            [Text.UTF8Encoding]::new($false)
        )
    }

    function New-RepoFixture {
        $repo = Join-Path $TestDrive ("roster-expansion-$([guid]::NewGuid().ToString('N'))")
        $agentRoot = Join-Path $repo '.github/agents'
        $null = [IO.Directory]::CreateDirectory($agentRoot)
        foreach ($agent in @(
                'Squad Researcher', 'Squad Lead', 'Squad Implementor', 'Squad Reviewer',
                'Squad Scribe', 'System Architecture Reviewer', 'Squad Backlog Executor',
                'Security Planner', 'aws-principal-architect', 'AWS Incident Triage'
            )) {
            New-Agent -Root $agentRoot -Name $agent
        }
        $repo
    }

    function Initialize-PlainSquad {
        param([string]$Repo, [string]$Root = '.copilot-tracking/squad')
        $choicesPath = Join-Path $Repo ("init-choices-$([guid]::NewGuid().ToString('N')).json")
        $payloadPath = Join-Path $Repo ("init-payload-$([guid]::NewGuid().ToString('N')).json")
        Write-Json $choicesPath @{
            confirmed = $true
            squadRoot = $Root
            runId = 'roster-expansion-init'
            profile = 'default'
            naming = 'aliases'
            notify = @{ approvalChannel = 'in-chat'; enabled = $false }
            sessionModel = 'claude-sonnet-5.5'
        }
        $prepared = Invoke-Local $script:InitPlan $Repo @(
            '-RepoRoot', $Repo, '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath
        )
        if ($prepared.ExitCode -ne 0) { throw $prepared.Output }
        $initialized = Invoke-Local $script:Initialize $Repo @(
            '-RepoRoot', $Repo, '-PayloadPath', $payloadPath, '-Direct'
        )
        if ($initialized.ExitCode -ne 0) { throw $initialized.Output }
        Join-Path $Repo $Root
    }

    function Initialize-Federation {
        param([string]$Repo)
        $choicesPath = Join-Path $Repo ("federation-choices-$([guid]::NewGuid().ToString('N')).json")
        $payloadPath = Join-Path $Repo ("federation-payload-$([guid]::NewGuid().ToString('N')).json")
        Write-Json $choicesPath @{
            confirmed = $true
            runId = 'roster-expansion-federation'
            naming = 'aliases'
            notify = @{ approvalChannel = 'in-chat'; enabled = $false }
            sessionModel = 'claude-sonnet-5.5'
            subSquads = @(
                @{
                    name = 'product'
                    profile = 'default'
                    owner = 'business'
                    description = 'Product work'
                    routes = @(@{ pattern = 'requirements, roadmap'; parallelEligible = $true })
                }
            )
        }
        $prepared = Invoke-Local $script:FederationPlan $Repo @(
            '-RepoRoot', $Repo, '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath
        )
        if ($prepared.ExitCode -ne 0) { throw $prepared.Output }
        $receipt = $prepared.Output | ConvertFrom-Json -AsHashtable
        $initialized = Invoke-Local $script:FederationInitialize $Repo @(
            '-RepoRoot', $Repo,
            '-PayloadPath', $payloadPath,
            '-ExpectedPayloadSha256', $receipt.payloadSha256,
            '-Confirmed'
        )
        if ($initialized.ExitCode -ne 0) { throw $initialized.Output }
        [pscustomobject]@{
            Root = Join-Path $Repo '.copilot-tracking/squad'
            Member = Join-Path $Repo '.copilot-tracking/squad/members/product'
        }
    }

    function New-ExpansionPlan {
        param(
            [string]$Repo,
            [string]$Root = '.copilot-tracking/squad',
            $Choices = @{
                confirmed = $true
                runId = 'roster-expansion-run'
                roles = @('architect')
                names = @{ architect = 'Atlas' }
            }
        )
        $choicesPath = Join-Path $Repo ("expand-choices-$([guid]::NewGuid().ToString('N')).json")
        $payloadPath = Join-Path $Repo ("expand-plan-$([guid]::NewGuid().ToString('N')).json")
        Write-Json $choicesPath $Choices
        $result = Invoke-Local $script:Plan $Repo @(
            '-RepoRoot', $Repo, '-SquadRoot', $Root,
            '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath
        )
        [pscustomobject]@{
            Path = $payloadPath
            Result = $result
            Receipt = $(if ($result.ExitCode -eq 0) { $result.Output | ConvertFrom-Json -AsHashtable } else { $null })
        }
    }

    function Invoke-Expansion {
        param(
            [string]$Repo,
            $Plan,
            [string]$Sha,
            [switch]$WithoutConfirmation,
            [int]$LockTimeoutSeconds = 120
        )
        if (-not $Sha) { $Sha = $Plan.Receipt.planSha256 }
        $arguments = @(
            '-RepoRoot', $Repo,
            '-PlanPath', $Plan.Path,
            '-ExpectedPlanSha256', $Sha,
            '-LockTimeoutSeconds', [string]$LockTimeoutSeconds
        )
        if (-not $WithoutConfirmation) { $arguments += '-Confirmed' }
        Invoke-Local $script:Expand $Repo $arguments
    }

    function Set-ExactLedger {
        param([string]$Repo, [string]$Root)
        $artifact = Join-Path $Root 'research/exact-ledger.md'
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $artifact))
        [IO.File]::WriteAllText($artifact, '# Exact ledger fixture', [Text.UTF8Encoding]::new($false))
        $payload = Join-Path $Repo ("handoff-$([guid]::NewGuid().ToString('N')).json")
        Write-Json $payload @{
            runId = 'roster-expansion-exact'
            historyRecords = @(@{
                    agent = 'Squad Researcher'
                    request = 'Produce exact-ledger fixture evidence.'
                    deliverable = '.copilot-tracking/squad/research/exact-ledger.md'
                    outcome = 'Produced exact-ledger fixture evidence.'
                    reportedModel = 'claude-sonnet-4.6'
                })
            stateAdvance = @{ activeRoles = @('Squad Researcher'); sessionModel = 'claude-sonnet-5.5' }
        }
        $handoff = Invoke-Local $script:Handoff $Repo @('-SquadRoot', $Root, '-PayloadPath', $payload, '-Quiet')
        if ($handoff.ExitCode -ne 0) { throw $handoff.Output }

        $session = Join-Path $Repo ("session-$([guid]::NewGuid().ToString('N'))")
        $null = [IO.Directory]::CreateDirectory($session)
        $start = [DateTimeOffset]::UtcNow.AddMinutes(-10)
        $events = @(
            @{
                type = 'session.start'
                timestamp = $start.ToString('o')
                data = @{ sessionId = 'roster-expansion-exact-session' }
            }
            @{
                type = 'subagent.started'
                agentId = 'roster-expansion-researcher'
                timestamp = $start.AddSeconds(1).ToString('o')
                data = @{
                    toolCallId = 'roster-expansion-researcher-call'
                    agentName = 'Squad Researcher'
                    agentDisplayName = 'researcher'
                    model = 'claude-sonnet-4.6'
                }
            }
            @{
                type = 'session.usage_record'
                agentId = 'roster-expansion-researcher'
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
                        accounting = @{ sourceSessionId = 'roster-expansion-researcher-session'; usageId = 'one' }
                    }
                }
            }
            @{
                type = 'subagent.completed'
                agentId = 'roster-expansion-researcher'
                timestamp = $start.AddSeconds(3).ToString('o')
                data = @{
                    toolCallId = 'roster-expansion-researcher-call'
                    agentName = 'Squad Researcher'
                    model = 'claude-sonnet-4.6'
                    totalTokens = 190000
                    durationMs = 2000
                }
            }
            @{
                type = 'subagent.started'
                agentId = 'roster-expansion-scribe'
                timestamp = $start.AddSeconds(4).ToString('o')
                data = @{
                    toolCallId = 'roster-expansion-scribe-call'
                    agentName = 'Squad Scribe'
                    agentDisplayName = 'scribe'
                    model = 'claude-haiku-4.5'
                }
            }
            @{
                type = 'session.usage_record'
                agentId = 'roster-expansion-scribe'
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
                        accounting = @{ sourceSessionId = 'roster-expansion-scribe-session'; usageId = 'one' }
                    }
                }
            }
            @{
                type = 'subagent.completed'
                agentId = 'roster-expansion-scribe'
                timestamp = $start.AddSeconds(6).ToString('o')
                data = @{
                    toolCallId = 'roster-expansion-scribe-call'
                    agentName = 'Squad Scribe'
                    model = 'claude-haiku-4.5'
                    totalTokens = 65000
                    durationMs = 2000
                }
            }
        )
        $eventText = ($events | ForEach-Object { $_ | ConvertTo-Json -Depth 12 -Compress }) -join "`n"
        [IO.File]::WriteAllText((Join-Path $session 'events.jsonl'), $eventText + "`n", [Text.UTF8Encoding]::new($false))
        $ledger = Invoke-Local $script:Ledger $Repo @('-SquadRoot', $Root, '-SessionLog', $session, '-Write')
        if ($ledger.ExitCode -ne 0) { throw $ledger.Output }
    }
}

AfterAll { $env:COPILOT_HOME = $script:OriginalCopilotHome }

Describe 'Sealed roster expansion planning' {
    It 'is read-only and resolves confirmed packs from canonical rows' {
        $repo = New-RepoFixture
        $root = Initialize-PlainSquad $repo
        $before = Get-TreeHash $root
        $choices = @{
            confirmed = $true
            runId = 'pack-expansion'
            packs = @('aws')
            names = @{ 'aws-architect' = 'Atlas'; 'aws-diagnose' = 'Beacon' }
        }

        $plan = New-ExpansionPlan -Repo $repo -Choices $choices

        $plan.Result.ExitCode | Should -Be 0 -Because $plan.Result.Output
        $plan.Receipt.status | Should -Be 'planned'
        $plan.Receipt.scope | Should -Be 'plain-squad'
        $plan.Receipt.addedRoles | Should -Be @('aws-architect', 'aws-diagnose')
        $plan.Receipt.routingRowsAdded | Should -Be 2
        $plan.Receipt.accountingPreserved | Should -BeTrue
        (Get-FileHash -LiteralPath $plan.Path).Hash | Should -Be $plan.Receipt.planSha256
        Get-TreeHash $root | Should -BeExactly $before
    }

    It 'refuses unavailable roles, repeated roles, and member roots without a registry' {
        $repo = New-RepoFixture
        $null = Initialize-PlainSquad $repo
        $missing = @{
            confirmed = $true
            runId = 'missing-role'
            roles = @('qa-engineer')
        }
        (New-ExpansionPlan -Repo $repo -Choices $missing).Result.ExitCode | Should -Be 1

        $existing = @{
            confirmed = $true
            runId = 'existing-role'
            roles = @('researcher')
        }
        (New-ExpansionPlan -Repo $repo -Choices $existing).Result.Output | Should -Match 'already present'

        $member = Initialize-PlainSquad $repo '.copilot-tracking/squad/members/unregistered'
        $memberChoice = @{
            confirmed = $true
            runId = 'unregistered-member'
            roles = @('architect')
        }
        $result = New-ExpansionPlan -Repo $repo -Root '.copilot-tracking/squad/members/unregistered' -Choices $memberChoice
        $result.Result.ExitCode | Should -Be 1
        $result.Result.Output | Should -Match 'federation registry'
        Test-Path -LiteralPath $member | Should -BeTrue
    }

    It 'keeps roster expansion transport outside all squad state' {
        $repo = New-RepoFixture
        $federation = Initialize-Federation $repo
        $choicesPath = Join-Path $repo 'member-expansion-choices.json'
        $payloadPath = Join-Path $federation.Root 'member-expansion-plan.json'
        Write-Json $choicesPath @{
            confirmed = $true
            runId = 'member-state-transport'
            roles = @('architect')
        }

        $result = Invoke-Local $script:Plan $repo @(
            '-RepoRoot', $repo,
            '-SquadRoot', '.copilot-tracking/squad/members/product',
            '-ChoicesPath', $choicesPath,
            '-PayloadPath', $payloadPath
        )

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'outside squad state'
        Test-Path -LiteralPath $payloadPath | Should -BeFalse
    }
}

Describe 'Deterministic additive roster expansion' {
    It 'preserves an exact ledger and all non-roster state byte-for-byte' {
        $repo = New-RepoFixture
        $root = Initialize-PlainSquad $repo
        Set-ExactLedger -Repo $repo -Root $root
        $ledgerBefore = [IO.File]::ReadAllBytes((Join-Path $root 'consumption.md'))
        $stateBefore = [IO.File]::ReadAllBytes((Join-Path $root 'state.json'))
        $ratesBefore = [IO.File]::ReadAllBytes((Join-Path $root 'consumption-rates.md'))
        $notificationsBefore = [IO.File]::ReadAllBytes((Join-Path $root 'notifications.md'))
        $historyBefore = Get-TreeHash (Join-Path $root 'history')
        $teamBefore = [IO.File]::ReadAllText((Join-Path $root 'team.md'))
        $routingBefore = [IO.File]::ReadAllText((Join-Path $root 'routing.md'))
        $decisionsBefore = [IO.File]::ReadAllBytes((Join-Path $root 'decisions.md'))
        $plan = New-ExpansionPlan -Repo $repo

        $result = Invoke-Expansion -Repo $repo -Plan $plan

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $receipt = $result.Output | ConvertFrom-Json -AsHashtable
        $receipt.status | Should -Be 'expanded'
        $receipt.addedRoles | Should -Be @('architect')
        $receipt.accountingPreserved | Should -BeTrue
        $receipt.statePreserved | Should -BeTrue
        $receipt.historyPreserved | Should -BeTrue
        $receipt.elapsedMs | Should -BeLessThan 15000
        [IO.File]::ReadAllBytes((Join-Path $root 'consumption.md')) | Should -Be $ledgerBefore
        [IO.File]::ReadAllBytes((Join-Path $root 'state.json')) | Should -Be $stateBefore
        [IO.File]::ReadAllBytes((Join-Path $root 'consumption-rates.md')) | Should -Be $ratesBefore
        [IO.File]::ReadAllBytes((Join-Path $root 'notifications.md')) | Should -Be $notificationsBefore
        Get-TreeHash (Join-Path $root 'history') | Should -BeExactly $historyBefore
        [IO.File]::ReadAllText((Join-Path $root 'team.md')) | Should -Match ([regex]::Escape('| architect | Atlas | System Architecture Reviewer |'))
        [IO.File]::ReadAllText((Join-Path $root 'team.md')) | Should -Match ([regex]::Escape($teamBefore.TrimEnd()))
        [IO.File]::ReadAllText((Join-Path $root 'routing.md')) | Should -Match ([regex]::Escape($routingBefore.TrimEnd()))
        [IO.File]::ReadAllBytes((Join-Path $root 'decisions.md'))[0..($decisionsBefore.Length - 1)] | Should -Be $decisionsBefore
        $ledgerText = [IO.File]::ReadAllText((Join-Path $root 'consumption.md'))
        $ledgerText | Should -Match 'Exact Cost \(USD\)'
        $ledgerText | Should -Not -Match 'Observed Usage'
        $ledgerText | Should -Not -Match 'Est\. Cost \(USD\)'
    }

    It 'rejects missing confirmation, a wrong hash, and a stale plan without partial writes' {
        $repo = New-RepoFixture
        $root = Initialize-PlainSquad $repo
        $plan = New-ExpansionPlan -Repo $repo
        $before = Get-TreeHash $root

        (Invoke-Expansion -Repo $repo -Plan $plan -WithoutConfirmation).ExitCode | Should -Be 1
        (Invoke-Expansion -Repo $repo -Plan $plan -Sha ('0' * 64)).ExitCode | Should -Be 1
        Get-TreeHash $root | Should -BeExactly $before

        [IO.File]::AppendAllText((Join-Path $root 'decisions.md'), "`nexternal change`n", [Text.UTF8Encoding]::new($false))
        $staleBefore = Get-TreeHash $root
        $stale = Invoke-Expansion -Repo $repo -Plan $plan
        $stale.ExitCode | Should -Be 2
        $stale.Output | Should -Match 'changed after confirmation'
        Get-TreeHash $root | Should -BeExactly $staleBefore
    }

    It 'restores earlier files when a later roster file cannot be replaced' {
        $repo = New-RepoFixture
        $root = Initialize-PlainSquad $repo
        $plan = New-ExpansionPlan -Repo $repo
        $before = Get-TreeHash $root
        $routing = Get-Item -LiteralPath (Join-Path $root 'routing.md')
        $routing.IsReadOnly = $true
        try {
            $result = Invoke-Expansion -Repo $repo -Plan $plan
            $result.ExitCode | Should -Be 3
            $result.Output | Should -Match 'restored'
            Get-TreeHash $root | Should -BeExactly $before
        }
        finally {
            $routing.IsReadOnly = $false
        }
    }

    It 'preserves edited roots and custom routes while adding only canonical missing rows' {
        $repo = New-RepoFixture
        $root = Initialize-PlainSquad $repo
        $teamPath = Join-Path $root 'team.md'
        $routingPath = Join-Path $root 'routing.md'
        $team = [IO.File]::ReadAllText($teamPath).Replace(
            '.copilot-tracking/changes/',
            '.copilot-tracking/custom-change-root/'
        )
        [IO.File]::WriteAllText($teamPath, $team, [Text.UTF8Encoding]::new($false))
        [IO.File]::AppendAllText(
            $routingPath,
            '| custom architecture request | developer | confirm | no |' + "`n",
            [Text.UTF8Encoding]::new($false)
        )
        $plan = New-ExpansionPlan -Repo $repo

        $result = Invoke-Expansion -Repo $repo -Plan $plan

        $result.ExitCode | Should -Be 0 -Because $result.Output
        [IO.File]::ReadAllText($teamPath) | Should -Match ([regex]::Escape('.copilot-tracking/custom-change-root/'))
        [IO.File]::ReadAllText($routingPath) | Should -Match ([regex]::Escape('| custom architecture request | developer | confirm | no |'))
        ([regex]::Matches([IO.File]::ReadAllText($routingPath), '\| architecture, system design, components\s+\| architect')).Count | Should -Be 1
    }

    It 'uses the same transaction for one registered federation member only' {
        $repo = New-RepoFixture
        $federation = Initialize-Federation $repo
        $rootFilesBefore = [ordered]@{}
        foreach ($name in @('federation.md', 'meta-routing.md', 'decisions.md', 'state.json', 'consumption-rates.md')) {
            $rootFilesBefore[$name] = [IO.File]::ReadAllBytes((Join-Path $federation.Root $name))
        }
        $rootHistoryBefore = Get-TreeHash (Join-Path $federation.Root 'history')
        $ledgerBefore = [IO.File]::ReadAllBytes((Join-Path $federation.Member 'consumption.md'))
        $stateBefore = [IO.File]::ReadAllBytes((Join-Path $federation.Member 'state.json'))
        $historyBefore = Get-TreeHash (Join-Path $federation.Member 'history')
        $plan = New-ExpansionPlan -Repo $repo -Root '.copilot-tracking/squad/members/product' -Choices @{
            confirmed = $true
            runId = 'member-roster-expansion'
            roles = @('security')
            names = @{ security = 'Guardian' }
        }

        $result = Invoke-Expansion -Repo $repo -Plan $plan

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $receipt = $result.Output | ConvertFrom-Json -AsHashtable
        $receipt.scope | Should -Be 'federation-member'
        [IO.File]::ReadAllBytes((Join-Path $federation.Member 'consumption.md')) | Should -Be $ledgerBefore
        [IO.File]::ReadAllBytes((Join-Path $federation.Member 'state.json')) | Should -Be $stateBefore
        Get-TreeHash (Join-Path $federation.Member 'history') | Should -BeExactly $historyBefore
        [IO.File]::ReadAllText((Join-Path $federation.Member 'team.md')) |
            Should -Match ([regex]::Escape('.copilot-tracking/squad/members/product/security-plans/'))
        foreach ($name in $rootFilesBefore.Keys) {
            [IO.File]::ReadAllBytes((Join-Path $federation.Root $name)) | Should -Be $rootFilesBefore[$name]
        }
        Get-TreeHash (Join-Path $federation.Root 'history') | Should -BeExactly $rootHistoryBefore
        [IO.File]::ReadAllText((Join-Path $federation.Root 'federation.md')) |
            Should -Not -Match 'security'
    }

    It 'serializes a member expansion with federation-root lifecycle writes' {
        $repo = New-RepoFixture
        $federation = Initialize-Federation $repo
        $plan = New-ExpansionPlan -Repo $repo -Root '.copilot-tracking/squad/members/product'
        $before = Get-TreeHash $federation.Root
        $key = [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData(
                [Text.Encoding]::UTF8.GetBytes($federation.Root.ToLowerInvariant())
            )
        ).Substring(0, 16)
        $lockPath = Join-Path ([IO.Path]::GetTempPath()) "hve-squad-handoff-$key.lock"
        $held = [IO.FileStream]::new(
            $lockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
        try {
            $result = Invoke-Expansion -Repo $repo -Plan $plan -LockTimeoutSeconds 1
            $result.ExitCode | Should -Be 8
            $result.Output | Should -Match 'writer lock timed out'
            Get-TreeHash $federation.Root | Should -BeExactly $before
        }
        finally {
            $held.Dispose()
        }
    }
}
