#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# AI cost: none; exercises confirmed federation planning and transactional Init.

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
    $script:Plan = Join-Path $skillRoot 'scripts/Get-SquadFederationInitPlan.ps1'
    $script:Initialize = Join-Path $skillRoot 'scripts/Initialize-SquadFederation.ps1'
    $script:MemberInitialize = Join-Path $skillRoot 'scripts/Initialize-Squad.ps1'
    $script:OriginalCopilotHome = $env:COPILOT_HOME
    $env:COPILOT_HOME = Join-Path $TestDrive 'empty-copilot-home'
    $null = [IO.Directory]::CreateDirectory($env:COPILOT_HOME)

    function Write-Json {
        param([string]$Path, $Value)
        $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
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

    function Get-FederationRepoFixture {
        $repo = Join-Path $TestDrive ("federation-init-$([guid]::NewGuid().ToString('N'))")
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
        $repo
    }

    function Get-FederationChoice {
        param([switch]$OneMember)
        $members = @(
            @{
                name = 'product'
                profile = 'default'
                owner = 'business'
                description = 'Product work'
                routes = @(@{ pattern = 'requirements, roadmap'; parallelEligible = $true })
            }
        )
        if (-not $OneMember) {
            $members += @{
                name = 'platform'
                profile = 'default'
                owner = 'engineering'
                description = 'Platform work'
                routes = @(@{ pattern = 'platform, infrastructure'; parallelEligible = $true })
            }
        }

        @{
            confirmed = $true
            runId = 'federation-init-fixture'
            naming = 'aliases'
            notify = @{ approvalChannel = 'in-chat'; enabled = $false }
            sessionModel = 'claude-sonnet-5.5'
            subSquads = $members
        }
    }

    function Get-ExpansionChoice {
        param(
            [string]$Name = 'platform',
            [string]$Pattern = 'platform, infrastructure'
        )
        @{
            confirmed = $true
            runId = 'federation-expansion-fixture'
            naming = 'aliases'
            notify = @{ approvalChannel = 'in-chat'; enabled = $false }
            sessionModel = 'claude-sonnet-5.5'
            subSquads = @(
                @{
                    name = $Name
                    profile = 'default'
                    owner = 'engineering'
                    description = "$Name work"
                    routes = @(@{ pattern = $Pattern; parallelEligible = $true })
                }
            )
        }
    }

    function New-FederationPlan {
        param($Repo, $Choices = (Get-FederationChoice))
        $choicesPath = Join-Path $Repo ("choices-$([guid]::NewGuid().ToString('N')).json")
        $payloadPath = Join-Path $Repo ("payload-$([guid]::NewGuid().ToString('N')).json")
        Write-Json $choicesPath $Choices
        $result = Invoke-Local $script:Plan $Repo @('-RepoRoot', $Repo, '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath)
        if ($result.ExitCode -ne 0) { throw $result.Output }
        [pscustomobject]@{ Path = $payloadPath; Result = ($result.Output | ConvertFrom-Json -AsHashtable) }
    }

    function Invoke-FederationInit {
        param(
            $Repo,
            $Plan,
            [switch]$WithoutConfirmation,
            [string]$Sha,
            [int]$LockTimeoutSeconds = 120
        )
        if (-not $Sha) { $Sha = $Plan.Result.payloadSha256 }
        $arguments = @(
            '-RepoRoot', $Repo,
            '-PayloadPath', $Plan.Path,
            '-ExpectedPayloadSha256', $Sha,
            '-LockTimeoutSeconds', [string]$LockTimeoutSeconds
        )
        if (-not $WithoutConfirmation) { $arguments += '-Confirmed' }
        Invoke-Local $script:Initialize $Repo $arguments
    }

    function Initialize-ExistingFederation {
        param($Repo)
        $plan = New-FederationPlan $Repo -Choices (Get-FederationChoice -OneMember)
        $result = Invoke-FederationInit $Repo $plan
        if ($result.ExitCode -ne 0) { throw $result.Output }
        [pscustomobject]@{ Plan = $plan; Receipt = ($result.Output | ConvertFrom-Json -AsHashtable) }
    }
}

AfterAll { $env:COPILOT_HOME = $script:OriginalCopilotHome }

Describe 'Confirmed federation Init planning' {
    It 'validates all member rosters and writes no squad state' {
        $repo = Get-FederationRepoFixture
        $before = Get-TreeHash $repo

        $plan = New-FederationPlan $repo

        $plan.Result.status | Should -Be 'prepared'
        $plan.Result.stateWritten | Should -BeFalse
        $plan.Result.members.name | Should -Be @('product', 'platform')
        $plan.Result.members[0].roles | Should -Contain 'scribe'
        (Get-FileHash -LiteralPath $plan.Path).Hash | Should -Be $plan.Result.payloadSha256
        Test-Path -LiteralPath (Join-Path $repo '.copilot-tracking') | Should -BeFalse
        Get-TreeHash $repo | Should -Not -BeExactly $before -Because 'only the explicit choices/payload transport files were added outside squad state'
    }

    It 'refuses unconfirmed, duplicate, or plain-squad federation choices' {
        $repo = Get-FederationRepoFixture
        $unconfirmed = Get-FederationChoice
        $unconfirmed.confirmed = $false
        $choicesPath = Join-Path $repo 'unconfirmed.json'
        $payloadPath = Join-Path $repo 'unconfirmed-payload.json'
        Write-Json $choicesPath $unconfirmed
        (Invoke-Local $script:Plan $repo @('-RepoRoot', $repo, '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath)).ExitCode | Should -Be 1

        $duplicate = Get-FederationChoice
        $duplicate.subSquads[1].name = 'PRODUCT'
        Write-Json $choicesPath $duplicate
        (Invoke-Local $script:Plan $repo @('-RepoRoot', $repo, '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath)).ExitCode | Should -Be 1

        $root = Join-Path $repo '.copilot-tracking/squad'
        $null = [IO.Directory]::CreateDirectory($root)
        [IO.File]::WriteAllText((Join-Path $root 'team.md'), '# Existing', [Text.UTF8Encoding]::new($false))
        Write-Json $choicesPath (Get-FederationChoice)
        $existing = Invoke-Local $script:Plan $repo @('-RepoRoot', $repo, '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath)
        $existing.ExitCode | Should -Be 1
        $existing.Output | Should -Match 'use promotion'
    }

    It 'prepares an existing federation expansion without changing squad state' {
        $repo = Get-FederationRepoFixture
        $null = Initialize-ExistingFederation $repo
        $root = Join-Path $repo '.copilot-tracking/squad'
        $before = Get-TreeHash $root

        $plan = New-FederationPlan $repo -Choices (Get-ExpansionChoice)

        $plan.Result.operation | Should -Be 'expand'
        $payload = Get-Content -LiteralPath $plan.Path -Raw | ConvertFrom-Json -AsHashtable
        $payload.operation | Should -Be 'expand'
        $payload.rootBaseline.kind | Should -Be 'federation'
        $payload.rootBaseline.snapshot.members.Keys | Should -Be @('product')
        Get-TreeHash $root | Should -BeExactly $before
    }

    It 'refuses expansion name, route, and history collisions before writing state' {
        $repo = Get-FederationRepoFixture
        $null = Initialize-ExistingFederation $repo
        $root = Join-Path $repo '.copilot-tracking/squad'
        $before = Get-TreeHash $root

        $duplicateName = Get-ExpansionChoice -Name 'product' -Pattern 'new product'
        $choicesPath = Join-Path $repo 'duplicate-name.json'
        $payloadPath = Join-Path $repo 'duplicate-name-payload.json'
        Write-Json $choicesPath $duplicateName
        (Invoke-Local $script:Plan $repo @('-RepoRoot', $repo, '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath)).ExitCode | Should -Be 1

        $duplicateRoute = Get-ExpansionChoice -Pattern 'requirements, roadmap'
        Write-Json $choicesPath $duplicateRoute
        (Invoke-Local $script:Plan $repo @('-RepoRoot', $repo, '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath)).ExitCode | Should -Be 1

        [IO.File]::WriteAllText((Join-Path $root 'history/platform.md'), '# Reserved', [Text.UTF8Encoding]::new($false))
        $historyBefore = Get-TreeHash $root
        Write-Json $choicesPath (Get-ExpansionChoice)
        $historyCollision = Invoke-Local $script:Plan $repo @('-RepoRoot', $repo, '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath)
        $historyCollision.ExitCode | Should -Be 1
        $historyCollision.Output | Should -Match 'history'
        Get-TreeHash $root | Should -BeExactly $historyBefore
        $before | Should -Not -BeExactly $historyBefore
    }
}

Describe 'Deterministic fresh federation initialization' {
    It 'requires confirmation and the exact payload hash without writing state' {
        $repo = Get-FederationRepoFixture
        $plan = New-FederationPlan $repo

        (Invoke-FederationInit $repo $plan -WithoutConfirmation).ExitCode | Should -Be 1
        (Invoke-FederationInit $repo $plan -Sha ('0' * 64)).ExitCode | Should -Be 1
        Test-Path -LiteralPath (Join-Path $repo '.copilot-tracking') | Should -BeFalse
    }

    It 'does not allow AgentRepoRoot to validate an unrelated staging repository' {
        $repo = Get-FederationRepoFixture
        $plan = New-FederationPlan $repo -Choices (Get-FederationChoice -OneMember)
        $payload = Get-Content -LiteralPath $plan.Path -Raw | ConvertFrom-Json -AsHashtable
        $stage = Join-Path $repo 'unowned-stage'
        $null = [IO.Directory]::CreateDirectory($stage)
        $memberPayload = Join-Path $stage 'member.json'
        Write-Json $memberPayload $payload.members[0].initPayload

        $result = Invoke-Local $script:MemberInitialize $stage @(
            '-RepoRoot', $stage, '-AgentRepoRoot', $repo, '-PayloadPath', $memberPayload, '-Direct'
        )

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'owned federation Init staging repository'
        Test-Path -LiteralPath (Join-Path $stage '.copilot-tracking/squad') | Should -BeFalse
    }

    It 'rejects a changed root precondition and leaves it byte-identical' {
        $repo = Get-FederationRepoFixture
        $plan = New-FederationPlan $repo
        $root = Join-Path $repo '.copilot-tracking/squad'
        $null = [IO.Directory]::CreateDirectory($root)
        [IO.File]::WriteAllText((Join-Path $root 'unexpected.md'), '# Changed', [Text.UTF8Encoding]::new($false))
        $before = Get-TreeHash (Join-Path $repo '.copilot-tracking')

        $result = Invoke-FederationInit $repo $plan

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'changed after confirmation'
        Get-TreeHash (Join-Path $repo '.copilot-tracking') | Should -BeExactly $before
    }

    It 'rolls back every staged member when installed agent validation fails' {
        $repo = Get-FederationRepoFixture
        $plan = New-FederationPlan $repo
        $payload = Get-Content -LiteralPath $plan.Path -Raw | ConvertFrom-Json -AsHashtable
        $payload.members[0].initPayload.roster[0]['Agent Name (Primary)'] = 'Missing Fixture Agent'
        Write-Json $plan.Path $payload
        $plan.Result.payloadSha256 = (Get-FileHash -LiteralPath $plan.Path).Hash

        $result = Invoke-FederationInit $repo $plan

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'member initialization failed'
        Test-Path -LiteralPath (Join-Path $repo '.copilot-tracking/squad') | Should -BeFalse
        if (Test-Path -LiteralPath (Join-Path $repo '.copilot-tracking')) {
            @((Get-ChildItem -LiteralPath (Join-Path $repo '.copilot-tracking') -Force)).Count | Should -Be 0
        }
    }

    Describe 'Deterministic federation expansion' {
        It 'adds members through the Init transaction while preserving existing member bytes' {
            $repo = Get-FederationRepoFixture
            $fresh = Initialize-ExistingFederation $repo
            $root = Join-Path $repo '.copilot-tracking/squad'
            $existingMember = Join-Path $root 'members/product'
            $memberBefore = Get-TreeHash $existingMember
            $registryBefore = [IO.File]::ReadAllText((Join-Path $root 'federation.md'))
            $routingBefore = [IO.File]::ReadAllText((Join-Path $root 'meta-routing.md'))
            $decisionsBefore = [IO.File]::ReadAllBytes((Join-Path $root 'decisions.md'))
            $historyBefore = [IO.File]::ReadAllBytes((Join-Path $root 'history/product.md'))
            $costBefore = [double]$fresh.Receipt.costUsd
            $statePath = Join-Path $root 'state.json'
            $preflightState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
            $preflightState.currentRun.costPreflight.runId = 'prior-run'
            $preflightState.currentRun.costPreflight.decision = 'within-ceiling'
            $preflightState.currentRun.costPreflight.basis = 'estimated-reservation'
            Write-Json $statePath $preflightState
            $choices = Get-ExpansionChoice
            $choices.subSquads += @{
                name = 'security'
                profile = 'default'
                owner = 'security'
                description = 'Security work'
                routes = @(@{ pattern = 'security, threat model'; parallelEligible = $true })
            }
            $plan = New-FederationPlan $repo -Choices $choices

            $result = Invoke-FederationInit $repo $plan

            $result.ExitCode | Should -Be 0 -Because $result.Output
            $receipt = $result.Output | ConvertFrom-Json -AsHashtable
            $receipt.operation | Should -Be 'expand'
            $receipt.status | Should -Be 'expanded'
            $receipt.turn | Should -Be 2
            $receipt.members | Should -Be @('platform', 'security')
            $receipt.totalMemberCount | Should -Be 3
            $receipt.memberStartSkewMs | Should -BeLessThan 2000
            $receipt.elapsedMs | Should -BeLessThan 30000
            Get-TreeHash $existingMember | Should -BeExactly $memberBefore
            [IO.File]::ReadAllBytes((Join-Path $root 'history/product.md')) | Should -Be $historyBefore
            [IO.File]::ReadAllBytes((Join-Path $root 'decisions.md'))[0..($decisionsBefore.Length - 1)] | Should -Be $decisionsBefore
            [IO.File]::ReadAllText((Join-Path $root 'federation.md')) | Should -Match ([regex]::Escape($registryBefore.TrimEnd()))
            [IO.File]::ReadAllText((Join-Path $root 'meta-routing.md')) | Should -Match ([regex]::Escape($routingBefore.TrimEnd()))
            Test-Path -LiteralPath (Join-Path $root 'members/platform/state.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $root 'history/platform.md') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $root 'members/security/state.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $root 'history/security.md') -PathType Leaf | Should -BeTrue
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            $state.subSquads | Should -Be @('product', 'platform', 'security')
            @($state.activeSubSquads).Count | Should -Be 0
            $state.currentRun.costPreflight.decision | Should -Be 'not-requested'
            [double]$state.currentRun.estCostUsd | Should -BeGreaterThan $costBefore
            @((Get-ChildItem -LiteralPath (Join-Path $repo '.copilot-tracking') -Directory -Force |
                    Where-Object Name -like '.squad-federation-init-*')).Count | Should -Be 0

            $replay = Invoke-FederationInit $repo $plan
            $replay.ExitCode | Should -Be 1
            $replay.Output | Should -Match 'changed after confirmation'
        }

        It 'rejects a stale concurrent expansion without changing the winning result' {
            $repo = Get-FederationRepoFixture
            $null = Initialize-ExistingFederation $repo
            $platform = New-FederationPlan $repo -Choices (Get-ExpansionChoice)
            $security = New-FederationPlan $repo -Choices (Get-ExpansionChoice -Name 'security' -Pattern 'security, threat model')
            (Invoke-FederationInit $repo $platform).ExitCode | Should -Be 0
            $root = Join-Path $repo '.copilot-tracking/squad'
            $winner = Get-TreeHash $root

            $loser = Invoke-FederationInit $repo $security

            $loser.ExitCode | Should -Be 1
            $loser.Output | Should -Match 'changed after confirmation'
            Test-Path -LiteralPath (Join-Path $root 'members/security') | Should -BeFalse
            Get-TreeHash $root | Should -BeExactly $winner
        }

        It 'leaves the existing federation byte-identical when a new member fails validation' {
            $repo = Get-FederationRepoFixture
            $null = Initialize-ExistingFederation $repo
            $plan = New-FederationPlan $repo -Choices (Get-ExpansionChoice)
            $payload = Get-Content -LiteralPath $plan.Path -Raw | ConvertFrom-Json -AsHashtable
            $payload.members[0].initPayload.roster[0]['Agent Name (Primary)'] = 'Missing Fixture Agent'
            Write-Json $plan.Path $payload
            $plan.Result.payloadSha256 = (Get-FileHash -LiteralPath $plan.Path).Hash
            $root = Join-Path $repo '.copilot-tracking/squad'
            $before = Get-TreeHash $root

            $result = Invoke-FederationInit $repo $plan

            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'member initialization failed'
            Get-TreeHash $root | Should -BeExactly $before
            Test-Path -LiteralPath (Join-Path $root 'members/platform') | Should -BeFalse
        }

        It 'rolls back moved members and root files when the final state replace fails' {
            $repo = Get-FederationRepoFixture
            $null = Initialize-ExistingFederation $repo
            $plan = New-FederationPlan $repo -Choices (Get-ExpansionChoice)
            $root = Join-Path $repo '.copilot-tracking/squad'
            $before = Get-TreeHash $root
            $statePath = Join-Path $root 'state.json'
            $hold = [IO.FileStream]::new($statePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                $result = Invoke-FederationInit $repo $plan
            }
            finally { $hold.Dispose() }

            $result.ExitCode | Should -Be 3
            $result.Output | Should -Match 'process|access|used'
            Get-TreeHash $root | Should -BeExactly $before
            Test-Path -LiteralPath (Join-Path $root 'members/platform') | Should -BeFalse
            @((Get-ChildItem -LiteralPath (Join-Path $repo '.copilot-tracking') -Directory -Force |
                    Where-Object Name -like '.squad-federation-init-*')).Count | Should -Be 0
        }
    }

    It 'times out behind the ordinary root writer lock without publishing' {
        $repo = Get-FederationRepoFixture
        $plan = New-FederationPlan $repo -Choices (Get-FederationChoice -OneMember)
        $root = Join-Path $repo '.copilot-tracking/squad'
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
                [Text.UTF8Encoding]::new($false).GetBytes($root.ToLowerInvariant())
            )).Substring(0, 16)
        $lockPath = Join-Path ([IO.Path]::GetTempPath()) "hve-squad-handoff-$hash.lock"
        $lock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            $result = Invoke-FederationInit $repo $plan -LockTimeoutSeconds 1
        }
        finally { $lock.Dispose() }

        $result.ExitCode | Should -Be 8
        $result.Output | Should -Match 'lock timed out'
        Test-Path -LiteralPath $root | Should -BeFalse
        if (Test-Path -LiteralPath (Join-Path $repo '.copilot-tracking')) {
            @((Get-ChildItem -LiteralPath (Join-Path $repo '.copilot-tracking') -Directory -Force |
                    Where-Object Name -like '.squad-federation-init-*')).Count | Should -Be 0
        }
    }

    It 'publishes two member roots in parallel with complete root metadata and accounting' {
        $repo = Get-FederationRepoFixture
        $plan = New-FederationPlan $repo

        $result = Invoke-FederationInit $repo $plan

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $receipt = $result.Output | ConvertFrom-Json -AsHashtable
        $receipt.verified | Should -BeTrue
        $receipt.parallelMemberInitialization | Should -BeTrue
        $receipt.memberStartSkewMs | Should -BeLessThan 2000
        $receipt.elapsedMs | Should -BeLessThan 30000
        $receipt.members | Should -Be @('product', 'platform')
        $root = Join-Path $repo '.copilot-tracking/squad'
        foreach ($file in @('federation.md', 'meta-routing.md', 'decisions.md', 'state.json', 'consumption-rates.md')) {
            Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf | Should -BeTrue
        }
        foreach ($name in @('product', 'platform')) {
            $member = Join-Path $root 'members' $name
            foreach ($file in @('team.md', 'routing.md', 'decisions.md', 'notifications.md', 'state.json', 'consumption.md', 'consumption-rates.md')) {
                Test-Path -LiteralPath (Join-Path $member $file) -PathType Leaf | Should -BeTrue
            }
            Test-Path -LiteralPath (Join-Path $root 'history' "$name.md") -PathType Leaf | Should -BeTrue
        }
        $registry = [IO.File]::ReadAllText((Join-Path $root 'federation.md'))
        $registry | Should -Match '\| product \| default \| in-repo \| members/product/'
        $registry | Should -Match '\| platform \| default \| in-repo \| members/platform/'
        $routing = [IO.File]::ReadAllText((Join-Path $root 'meta-routing.md'))
        $routing | Should -Match '\| requirements, roadmap \| product \| yes \|'
        $routing | Should -Match '\| platform, infrastructure \| platform \| yes \|'
        $orchestration = [IO.File]::ReadAllText((Join-Path $root 'history/Squad Scribe.md'))
        $orchestration | Should -Match 'no Scribe dispatch'
        $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json
        $state.subSquads | Should -Be @('product', 'platform')
        @($state.activeSubSquads).Count | Should -Be 0
        $memberCost = 0.0
        foreach ($name in $state.subSquads) {
            $memberCost += (Get-Content -LiteralPath (Join-Path $root 'members' $name 'state.json') -Raw | ConvertFrom-Json).currentRun.estCostUsd
        }
        $state.currentRun.estCostUsd | Should -BeGreaterThan $memberCost
        @((Get-ChildItem -LiteralPath (Join-Path $repo '.copilot-tracking') -Directory -Force |
                Where-Object Name -like '.squad-federation-init-*')).Count | Should -Be 0
    }

    It 'replaces an unchanged empty scaffold and refuses replay' {
        $repo = Get-FederationRepoFixture
        $empty = Join-Path $repo '.copilot-tracking/squad/scaffold/nested'
        $null = [IO.Directory]::CreateDirectory($empty)
        $plan = New-FederationPlan $repo -Choices (Get-FederationChoice -OneMember)

        $result = Invoke-FederationInit $repo $plan

        $result.ExitCode | Should -Be 0 -Because $result.Output
        Test-Path -LiteralPath (Join-Path $repo '.copilot-tracking/squad/federation.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $repo '.copilot-tracking/squad/scaffold') | Should -BeFalse
        $replay = Invoke-FederationInit $repo $plan
        $replay.ExitCode | Should -Be 1
        $replay.Output | Should -Match 'changed after confirmation'
    }
}
