#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Consumed in BeforeAll.')]
param([Parameter(Mandatory)][string]$SourceRoot)

BeforeAll {
    $script:OriginalCopilotHome = $env:COPILOT_HOME
    $env:COPILOT_HOME = Join-Path $TestDrive 'empty-copilot-home'
    $null = [IO.Directory]::CreateDirectory($env:COPILOT_HOME)
    $script:Helpers = Join-Path $SourceRoot 'squad-src' '.github' 'skills' 'squad' 'scripts'
    $script:References = Join-Path (Split-Path -Parent $script:Helpers) 'references'
    Import-Module (Join-Path $script:Helpers 'SquadCoordinator.psm1') -Force

    function Write-FixtureText {
        param([string]$Path, [string]$Text)
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
        [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
    }

    function Write-FixtureJson {
        param([string]$Path, $Value)
        Write-FixtureText $Path ($Value | ConvertTo-Json -Depth 30)
    }

    function Invoke-Local {
        param([string]$Name, [string]$Repo, [string[]]$Arguments = @())
        Push-Location $Repo
        try {
            $output = & pwsh -NoProfile -File (Join-Path $script:Helpers $Name) @Arguments 2>&1 | Out-String
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
        }
        finally { Pop-Location }
    }

    function New-FixtureRepo {
        $repo = Join-Path $TestDrive ("coordinator repo " + [guid]::NewGuid().ToString('N'))
        $null = [IO.Directory]::CreateDirectory($repo)
        $repo
    }

    function Get-FixtureHash {
        param([string]$Root)
        if (-not (Test-Path -LiteralPath $Root)) { return '' }
        @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
                [IO.Path]::GetRelativePath($Root, $_.FullName) + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash
            }) -join "`n"
    }

    function New-Choices {
        param([string]$Root = '.copilot-tracking/squad')
        @{
            confirmed = $true; squadRoot = $Root; runId = 'fixture-run'; profile = 'default'
            naming = 'aliases'; notify = @{ approvalChannel = 'in-chat'; enabled = $false }
            sessionModel = 'claude-sonnet-5.5'
        }
    }

    function Initialize-Fixture {
        param(
            [string]$Repo,
            [string]$Root = '.copilot-tracking/squad',
            [ValidateSet('off', 'ranked', 'economy', 'manual')][string]$ModelRouting = 'off'
        )
        $suffix = [guid]::NewGuid().ToString('N')
        $choicesPath = Join-Path $Repo "$suffix-choices.json"
        $payloadPath = Join-Path $Repo "$suffix-init.json"
        $choices = New-Choices $Root
        if ($ModelRouting -ne 'off') { $choices.modelRouting = $ModelRouting }
        Write-FixtureJson $choicesPath $choices
        $prepared = Invoke-Local 'Get-SquadInitContext.ps1' $Repo @('-RepoRoot', $Repo, '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath)
        if ($prepared.ExitCode -ne 0) { throw $prepared.Output }
        $result = Invoke-Local 'Initialize-Squad.ps1' $Repo @('-RepoRoot', $Repo, '-PayloadPath', $payloadPath, '-Direct')
        if ($result.ExitCode -ne 0) { throw $result.Output }
        [pscustomobject]@{ Root = Join-Path $Repo $Root; Payload = $payloadPath; Status = ($result.Output | ConvertFrom-Json -AsHashtable) }
    }

    function Write-FixtureWork {
        param(
            [string]$Repo,
            [string]$Root,
            [string]$ReportedModel,
            [int]$InternalToolCalls = -1,
            [string]$ActiveRole = 'Squad Implementor'
        )
        $relative = [IO.Path]::GetRelativePath($Repo, (Join-Path $Root 'changes' 'result.md')) -replace '\\', '/'
        if (([IO.Path]::GetRelativePath($Repo, $Root) -replace '\\', '/') -eq '.copilot-tracking/squad') {
            $relative = '.copilot-tracking/changes/result.md'
        }
        Write-FixtureText (Join-Path $Repo $relative) "# Result`n`nActual fixture artifact $([guid]::NewGuid()).`n"
        $path = Join-Path $Repo ("work-" + [guid]::NewGuid().ToString('N') + '.json')
        $payload = @{
            runId = 'fixture-run'
            historyRecords = @(@{ agent = 'Squad Implementor'; request = 'Implement fixture'; deliverable = $relative; outcome = 'Wrote actual artifact.' })
            decision = @{ title = 'Fixture decision'; rationale = 'Recorded actual fixture work.'; adrNoted = $false }
            stateAdvance = @{ activeRoles = @($ActiveRole); sessionModel = 'claude-sonnet-5.5' }
        }
        if ($ReportedModel) { $payload.historyRecords[0].reportedModel = $ReportedModel }
        if ($InternalToolCalls -ge 0) { $payload.historyRecords[0].internalToolCalls = $InternalToolCalls }
        Write-FixtureJson $path $payload
        $written = Invoke-Local 'Write-SquadHandoff.ps1' $Repo @('-SquadRoot', $Root, '-PayloadPath', $path, '-Quiet')
        if ($written.ExitCode -ne 0) { throw $written.Output }
        $status = $written.Output.Trim().Split("`n") | Where-Object { $_ -match '^\{' } | Select-Object -Last 1 | ConvertFrom-Json -AsHashtable
        $headings = [regex]::Matches([IO.File]::ReadAllText((Join-Path $Root 'decisions.md')), '(?m)^## (?<title>[^\r\n]+)')
        $slug = ($headings[-1].Groups['title'].Value.ToLowerInvariant() -replace '[^\p{L}\p{Nd}_ -]', '') -replace ' ', '-'
        [pscustomobject]@{
            Payload = $path; Turn = $status.turn; Artifact = Join-Path $Repo $relative
            DecisionRef = ([IO.Path]::GetRelativePath($Repo, (Join-Path $Root 'decisions.md')) -replace '\\', '/') + '#' + $slug
        }
    }

    function New-FederationFixture {
        $repo = New-FixtureRepo
        $root = Join-Path $repo '.copilot-tracking/squad'
        $members = [ordered]@{}
        foreach ($name in @('product', 'azure')) {
            $members[$name] = Initialize-Fixture $repo ".copilot-tracking/squad/members/$name"
        }
        Write-FixtureText (Join-Path $root 'federation.md') @'
# Squad Federation

| Sub-squad | Profile | Kind | Location | Owner | Description |
|-----------|---------|------|----------|-------|-------------|
| product | default | in-repo | members/product/ | human | Product |
| azure | default | in-repo | members/azure/ | human | Azure |
'@
        Write-FixtureText (Join-Path $root 'meta-routing.md') @'
# Federation Routing

| Pattern / Domain | Sub-squad | Parallel-Eligible |
|------------------|-----------|-------------------|
| product | product | yes |
| Azure | azure | yes |
'@
        Write-FixtureText (Join-Path $root 'decisions.md') "# Squad Federation Decisions`n"
        $null = [IO.Directory]::CreateDirectory((Join-Path $root 'history'))
        [IO.File]::Copy((Join-Path $members.product.Root 'consumption-rates.md'), (Join-Path $root 'consumption-rates.md'))
        $section = Get-SquadReferenceSection -Path (Join-Path $script:References 'federation-templates.md') -Heading '### state.json (federation root)'
        $state = [regex]::Match($section, '(?s)```json\s*\n(?<json>.*?)\n```').Groups['json'].Value | ConvertFrom-Json -AsHashtable
        $state.turn = 1
        $state.updated = [DateTimeOffset]::UtcNow.ToString('o')
        $state.subSquads = @('product', 'azure')
        $state.currentRun.sessionModel = 'claude-sonnet-5.5'
        foreach ($name in $members.Keys) {
            $child = Get-Content -LiteralPath (Join-Path $members[$name].Root 'state.json') -Raw | ConvertFrom-Json -AsHashtable
            $state.currentRun.estCostUsd += $child.currentRun.estCostUsd
            $state.currentRun.estCreditsTotal += $child.currentRun.estCreditsTotal
        }
        Write-FixtureJson (Join-Path $root 'state.json') $state
        [pscustomobject]@{ Repo = $repo; Root = $root; Members = $members }
    }

    function New-FederationTurn {
        param($Fixture, [string[]]$Names = @('product', 'azure'))
        $snapshot = Join-Path $Fixture.Repo ("snapshot-" + [guid]::NewGuid().ToString('N') + '.json')
        $brief = Invoke-Local 'Get-SquadDispatchBrief.ps1' $Fixture.Repo @('-RepoRoot', $Fixture.Repo, '-SquadRoot', $Fixture.Root, '-AsJson', '-SnapshotPath', $snapshot)
        if ($brief.ExitCode -ne 0) { throw $brief.Output }
        $subSquads = @(
            foreach ($name in $Names) {
                $work = Write-FixtureWork $Fixture.Repo $Fixture.Members[$name].Root
                @{ name = $name; proofPath = $work.Payload; turn = $work.Turn; decisionRefs = @($work.DecisionRef); request = "Run $name"; outcome = 'Verified actual work.' }
            }
        )
        $payload = @{
            runId = 'fixture-run'; snapshotPath = $snapshot; routeKind = 'ordinary'
            decision = @{ title = 'Federation routing'; rationale = 'Selected fixture members.' }
            subSquads = $subSquads
        }
        $path = Join-Path $Fixture.Repo ("federation-turn-" + [guid]::NewGuid().ToString('N') + '.json')
        Write-FixtureJson $path $payload
        [pscustomobject]@{ Path = $path; Value = $payload }
    }
}

AfterAll { $env:COPILOT_HOME = $script:OriginalCopilotHome }

Describe 'Compact confirmed initialization (COORD-01..03)' {
    It 'returns canonical profiles and Primaries without squad state' {
        $repo = New-FixtureRepo
        $result = Invoke-Local 'Get-SquadInitContext.ps1' $repo @('-RepoRoot', $repo, '-Profile', 'default')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $context = $result.Output | ConvertFrom-Json
        $context.kind | Should -Be 'none'
        $context.members.primary | Should -Be @('Squad Researcher', 'Squad Lead', 'Squad Implementor', 'Squad Reviewer', 'Squad Scribe')
        $context.profiles.Count | Should -Be 11
        [Text.Encoding]::UTF8.GetByteCount($result.Output) | Should -BeLessThan 8000
        Test-Path -LiteralPath (Join-Path $repo '.copilot-tracking') | Should -BeFalse
    }

    It 'refuses invalid or unconfirmed <Case> choices without state' -ForEach @(
        @{ Case = 'confirmation'; Key = 'confirmed'; Value = $false }
        @{ Case = 'profile'; Key = 'profile'; Value = 'imaginary' }
        @{ Case = 'naming'; Key = 'naming'; Value = 'guess' }
        @{ Case = 'traversal'; Key = 'squadRoot'; Value = '../escaped' }
        @{ Case = 'custom roles'; Key = 'profile'; Value = 'custom' }
    ) {
        $repo = New-FixtureRepo
        $choices = New-Choices
        $choices[$Key] = $Value
        $path = Join-Path $repo 'choices.json'
        Write-FixtureJson $path $choices
        $result = Invoke-Local 'Get-SquadInitContext.ps1' $repo @('-RepoRoot', $repo, '-ChoicesPath', $path, '-PayloadPath', (Join-Path $repo 'payload.json'))
        $result.ExitCode | Should -Be 1
        Test-Path -LiteralPath (Join-Path $repo 'payload.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $repo '.copilot-tracking') | Should -BeFalse
    }

    It 'requires the naming and notification answers rather than silently defaulting' {
        $repo = New-FixtureRepo
        foreach ($key in @('naming', 'notify')) {
            $choices = New-Choices
            $choices.Remove($key)
            { New-SquadInitPayload -Choices $choices -RepoRoot $repo } | Should -Throw "*$key*"
        }
    }

    It 'resolves aliases deterministically, skipping supplied names' {
        $repo = New-FixtureRepo
        $choices = New-Choices
        $choices.naming = 'mixed'
        $choices.names = @{ researcher = 'Beta' }
        $payload = New-SquadInitPayload -Choices $choices -RepoRoot $repo
        @($payload.roster | ForEach-Object { $_['Member Name'] }) | Should -Be @('Beta', 'Alpha', 'Gamma', 'Delta', 'Epsilon')
        $payload.roster[0]['Agent Name (Primary)'] | Should -BeExactly 'Squad Researcher'
    }

    It 'prepares full profiles and additive packs from canonical installed cast data' {
        $repo = New-FixtureRepo
        $data = Get-SquadInitData
        $index = 0
        foreach ($cast in $data.cast) {
            $primary = $cast['Primary Agent (`name:`)']
            if ($primary -notmatch '^[A-Za-z]' -or $primary -match '[/\\:]') { continue }
            Write-FixtureText (Join-Path $repo '.github/agents' "fixture-$index.agent.md") "---`nname: $primary`n---`n"
            $index++
        }
        $choices = New-Choices
        $choices.profile = 'full'
        $choices.packs = @('aws')
        $payload = New-SquadInitPayload -Choices $choices -RepoRoot $repo
        $payload.provenance | Should -Be 'full +aws'
        @($payload.roster | ForEach-Object Role) | Should -Contain 'aws-architect'
        @($payload.roster | ForEach-Object Role) | Should -Not -Contain 'backlog-executor'
        $payload.roster[9]['Member Name'] | Should -Be 'Kappa'
        $payload.roster[24]['Member Name'] | Should -Be 'Alpha-2'
        @($payload.roster | Where-Object Role -eq 'security')[0]['Deliverable Root'] | Should -Be '.copilot-tracking/security-plans/'
        @($payload.roster | Where-Object Role -eq 'intake-validator')[0]['Deliverable Root'] | Should -Be '.copilot-tracking/reviews/'
    }

    It 'publishes direct Init once with coordinator-only overhead and no speculative histories' {
        $repo = New-FixtureRepo
        $fixture = Initialize-Fixture $repo
        $fixture.Status.status | Should -Be 'PASS'
        $fixture.Status.verified | Should -BeTrue
        @($fixture.Status.actors) | Should -Be @('coordinator')
        $fixture.Status.historyEntries | Should -Be 1
        @(Get-ChildItem -LiteralPath (Join-Path $fixture.Root 'history') -File).Name | Should -Be @('Squad Scribe.md')
        [IO.File]::ReadAllText((Join-Path $fixture.Root 'consumption.md')) | Should -Match 'n/a \(initialization\)'
        $before = Get-FixtureHash $fixture.Root
        $repeat = Invoke-Local 'Initialize-Squad.ps1' $repo @('-RepoRoot', $repo, '-PayloadPath', $fixture.Payload, '-Direct')
        $repeat.ExitCode | Should -Be 1
        Get-FixtureHash $fixture.Root | Should -BeExactly $before
    }

    It 'rebases member roots and leaves docs/outputs repository-wide' {
        $repo = New-FixtureRepo
        $fixture = Initialize-Fixture $repo '.copilot-tracking/squad/members/example'
        $rows = @(Get-SquadRoster $fixture.Root)
        $rows[0]['Deliverable Root'] | Should -Be '.copilot-tracking/squad/members/example/research/<date>/'
        $rows[2]['Deliverable Root'] | Should -Be '.copilot-tracking/squad/members/example/changes/'
    }
}

Describe 'Universal compact metadata and deterministic scheduling (COORD-04..06)' {
    BeforeAll {
        $script:MetadataRepo = New-FixtureRepo
        $script:MetadataFixture = Initialize-Fixture $script:MetadataRepo
    }

    It 'returns read-only JSON in routing mode <Mode> without enabling other modes bounded lane' -ForEach @(
        @{ Mode = 'off' }, @{ Mode = 'ranked' }, @{ Mode = 'manual' }, @{ Mode = 'economy' }
    ) {
        $path = Join-Path $script:MetadataFixture.Root 'team.md'
        $team = [IO.File]::ReadAllText($path) -replace '(?m)^Model routing:.*\r?\n', ''
        Write-FixtureText $path ($team -replace '# Squad Roster', "# Squad Roster`nModel routing: $Mode")
        $before = Get-FixtureHash $script:MetadataFixture.Root
        $result = Invoke-Local 'Get-SquadDispatchBrief.ps1' $script:MetadataRepo @('-RepoRoot', $script:MetadataRepo, '-SquadRoot', $script:MetadataFixture.Root, '-AsJson', '-Roles', 'developer')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $data = $result.Output | ConvertFrom-Json
        $data.modelRouting | Should -Be $Mode
        $data.observedExecution | Should -Be 'host-unreported'
        $data.roster.Count | Should -Be 1
        $data.modelRoutingDeferred | Should -Be ($Mode -ne 'off')
        $data.modelPolicy | Should -Be $(if ($Mode -eq 'off') { 'off' } else { 'deferred-to-dispatch-plan' })
        if ($Mode -ne 'economy') { $data.boundedLaneEligible | Should -BeFalse }
        $data.ledgerCheck.status | Should -Be 'not-run'
        $result.Output | Should -Not -Match '## Procedure|## Consumption objects'
        Get-FixtureHash $script:MetadataFixture.Root | Should -BeExactly $before
        Write-FixtureText $path $team
    }

    It 'reads dispatchability beyond a long frontmatter allowlist' {
        $repo = New-FixtureRepo
        $lines = @('---', 'name: Long Frontmatter', 'agents:') + @(1..60 | ForEach-Object { "  - Agent $_" }) + @('disable-model-invocation: true', '---')
        Write-FixtureText (Join-Path $repo '.github/agents/long.agent.md') ($lines -join "`n")
        $index = Get-SquadAgentIndex $repo
        $index['Long Frontmatter'].dispatchable | Should -BeFalse
    }

    It 'orders dependencies even when the consumer was listed first and keeps native endpoint/root values' {
        $inputData = @{
            squadRoot = $script:MetadataFixture.Root
            units = @(@{ id = 'consumer'; role = 'tester'; dependsOn = @('producer') }, @{ id = 'producer'; role = 'researcher' })
        }
        $path = Join-Path $script:MetadataRepo 'plan.json'
        Write-FixtureJson $path $inputData
        $before = Get-FixtureHash $script:MetadataFixture.Root
        $result = Invoke-Local 'New-SquadDispatchPlan.ps1' $script:MetadataRepo @('-RepoRoot', $script:MetadataRepo, '-InputPath', $path)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $plan = $result.Output | ConvertFrom-Json
        $plan.waves[0].units | Should -Be @('producer')
        $plan.waves[1].units | Should -Be @('consumer')
        $plan.waves[0].barrier | Should -BeExactly 'artifact-before-handoff; verified-ordinary-handoff-before-dependent-dispatch; cold-exit-2-follows-pipelining-contract; history-consumption-state-before-completion'
        $plan.units[0].endpoint.agent | Should -BeExactly 'Squad Reviewer'
        $plan.units[0].endpoint.deliverableRoot | Should -Be '.copilot-tracking/reviews/'
        $plan.admission | Should -Be 'not-requested'
        Get-FixtureHash $script:MetadataFixture.Root | Should -BeExactly $before
    }

    It 'resolves <Mode> routing only for the actual dispatch-plan role and returns a script refresh' -ForEach @(
        @{ Mode = 'ranked' }
        @{ Mode = 'economy' }
        @{ Mode = 'manual' }
    ) {
        $repo = New-FixtureRepo
        $fixture = Initialize-Fixture $repo -ModelRouting $Mode
        $path = Join-Path $repo "$Mode-plan.json"
        $input = @{
            squadRoot = $fixture.Root
            sessionModel = 'gpt-5.6-sol'
            availableModels = @('gpt-5.6-sol')
            units = @(@{ id = 'work'; role = 'developer' })
        }
        if ($Mode -eq 'manual') { $input.manualModels = @{ developer = 'gpt-5.6-sol' } }
        Write-FixtureJson $path $input
        $result = Invoke-Local 'New-SquadDispatchPlan.ps1' $repo @('-RepoRoot', $repo, '-InputPath', $path)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $plan = $result.Output | ConvertFrom-Json
        $plan.units.Count | Should -Be 1
        $plan.units[0].endpoint.role | Should -Be 'developer'
        $plan.units[0].endpoint.model | Should -BeExactly 'gpt-5.6-sol'
        $plan.routingRefresh.required | Should -BeTrue
        $plan.routingRefresh.changes.Count | Should -Be 1
        $plan.routingRefresh.changes[0].role | Should -BeExactly 'developer'
        $plan.routingRefresh.changes[0].to | Should -BeExactly 'gpt-5.6-sol'
    }

    It 'requires the planned model to control the native dispatch rather than agent frontmatter' {
        $runtime = Get-Content -LiteralPath (Join-Path $script:References 'coordinator-runtime.md') -Raw
        $coordinator = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-coordinator.agent.md') -Raw
        $runtime | Should -Match 'Pass non-empty `endpoint\.model` exactly as the native\s+`model`; omit only when empty\.'
        $runtime | Should -Match 'Never use `pricingModel` or frontmatter instead'
        $coordinator | Should -Match 'Copy every non-empty planned `endpoint\.model` into the native dispatch\s+tool''s `model` argument exactly'
        $coordinator | Should -Match 'never substitute the pricing model or defer an active route to frontmatter'
    }

    It 'refuses active routing when sessionModel auto is supplied without the host model enum' {
        $repo = New-FixtureRepo
        $fixture = Initialize-Fixture $repo -ModelRouting ranked
        $path = Join-Path $repo 'ranked-auto-without-host-models.json'
        Write-FixtureJson $path @{
            squadRoot = $fixture.Root
            sessionModel = 'auto'
            units = @(@{ id = 'work'; role = 'developer' })
        }
        $before = Get-FixtureHash $fixture.Root
        $result = Invoke-Local 'New-SquadDispatchPlan.ps1' $repo @('-RepoRoot', $repo, '-InputPath', $path)
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'sessionModel ''auto'' is routing metadata, not an availability inventory'
        $result.Output | Should -Match 'availableModels'
        Get-FixtureHash $fixture.Root | Should -BeExactly $before
    }

    It 'plans the first off-to-<Mode> transition over only the actual role' -ForEach @(
        @{ Mode = 'ranked' }
        @{ Mode = 'economy' }
        @{ Mode = 'manual' }
    ) {
        $repo = New-FixtureRepo
        $fixture = Initialize-Fixture $repo
        $path = Join-Path $repo "transition-$Mode.json"
        $input = @{
            squadRoot = $fixture.Root
            requestedModelRouting = $Mode
            sessionModel = 'gpt-5.6-sol'
            availableModels = @('gpt-5.6-sol')
            units = @(@{ id = 'work'; role = 'developer' })
        }
        if ($Mode -eq 'manual') { $input.manualModels = @{ developer = 'gpt-5.6-sol' } }
        if ($Mode -eq 'economy') {
            $input.economyConsent = @{
                user = 'fixture-user'
                tradeAccepted = 'Cost-first qualified implementation routing.'
                neverWeakened = 'Floors, gates, and review stay unchanged.'
                timestamp = '2026-10-24T16:00:00Z'
            }
        }
        Write-FixtureJson $path $input
        $result = Invoke-Local 'New-SquadDispatchPlan.ps1' $repo @('-RepoRoot', $repo, '-InputPath', $path)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $plan = $result.Output | ConvertFrom-Json
        $plan.recordedModelRouting | Should -Be 'off'
        $plan.modelRouting | Should -Be $Mode
        $plan.units.Count | Should -Be 1
        $plan.routingRefresh.required | Should -BeTrue
        $plan.routingRefresh.recordedMode | Should -Be 'off'
        $plan.routingRefresh.mode | Should -Be $Mode
        $plan.routingRefresh.changes.Count | Should -Be 1
        if ($Mode -eq 'economy') { $plan.routingRefresh.economyConsent.user | Should -Be 'fixture-user' }
    }

    It 'persists the first ranked transition directly from the actual plan receipt' {
        $repo = New-FixtureRepo
        $fixture = Initialize-Fixture $repo
        $inputPath = Join-Path $repo 'transition-input.json'
        Write-FixtureJson $inputPath @{
            squadRoot = $fixture.Root
            requestedModelRouting = 'ranked'
            sessionModel = 'gpt-5.6-sol'
            availableModels = @('gpt-5.6-sol')
            units = @(@{ id = 'work'; role = 'developer' })
        }
        $planned = Invoke-Local 'New-SquadDispatchPlan.ps1' $repo @('-RepoRoot', $repo, '-InputPath', $inputPath)
        $planned.ExitCode | Should -Be 0 -Because $planned.Output
        $planPath = Join-Path $repo 'transition-plan.json'
        Write-FixtureText $planPath $planned.Output.Trim()
        $written = Invoke-Local 'Set-SquadModelRouting.ps1' $repo @('-RepoRoot', $repo, '-PlanPath', $planPath)
        $written.ExitCode | Should -Be 0 -Because $written.Output
        $team = [IO.File]::ReadAllText((Join-Path $fixture.Root 'team.md'))
        $team | Should -Match '(?m)^Model routing: ranked$'
        $team | Should -Match '\| Model Tier \| Model \| Deliverable Root \|'
        $team | Should -Match '\| developer \| Gamma \| Squad Implementor .* \| default \| `gpt-5\.6-sol` \|'
    }

    It 'uses complete host records as exact spend and reserves only the actual next wave' {
        $repo = New-FixtureRepo
        $fixture = Initialize-Fixture $repo
        $events = Join-Path $repo 'events.jsonl'
        @(
            @{ type = 'session.usage_record'; timestamp = '2026-10-24T10:00:00.000Z'; data = @{ usage = @{
                        model = 'gpt-5.6-sol'; inputTokens = 100; outputTokens = 10; cacheReadTokens = 80; cacheWriteTokens = 0
                        accounting = @{ sourceSessionId = 'session'; usageId = 'one' }
                        aiCreditsStatus = 'complete'; copilotUsage = @{ totalNanoAiu = 2000000000 }
                    } } }
            @{ type = 'session.usage_checkpoint'; timestamp = '2026-10-24T10:01:00.000Z'; data = @{ totalNanoAiu = 1000000000 } }
        ) | ForEach-Object { $_ | ConvertTo-Json -Depth 10 -Compress } | Set-Content -LiteralPath $events -Encoding utf8NoBOM
        $path = Join-Path $repo 'cost-plan.json'
        Write-FixtureJson $path @{
            squadRoot = $fixture.Root
            sessionModel = 'gpt-5.6-sol'
            units = @(@{ id = 'work'; role = 'developer' })
            cost = @{ runId = 'fixture-run'; roundId = 'round-1'; ceilingUsd = 100; sessionLog = $events; baselineNanoAiu = 0 }
        }
        $result = Invoke-Local 'New-SquadDispatchPlan.ps1' $repo @('-RepoRoot', $repo, '-InputPath', $path)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $plan = $result.Output | ConvertFrom-Json
        $plan.usage.status | Should -Be 'complete'
        $plan.usage.usd | Should -Be 0.02
        $plan.usage.checkpointNanoAiu | Should -Be 1000000000
        $plan.costPreflight.evaluatedSpendUsd | Should -Be 0.02
        $plan.costPreflight.projectedCostUsd | Should -BeGreaterThan 0
        $plan.costPreflight.basis | Should -Be 'host-exact+estimated-reservation'
        $plan.costPreflight.decision | Should -Be 'within-ceiling'
        @($plan.admittedUnits) | Should -Be @('work')
        $plan.costDecisionText | Should -Match '\* Permitted Next Dispatch Set: `work`'
    }

    It 'rejects cycles, missing dependencies and unknown roles' {
        foreach ($units in @(
                @(@{ id = 'a'; role = 'researcher'; dependsOn = @('b') }, @{ id = 'b'; role = 'tester'; dependsOn = @('a') }),
                @(@{ id = 'a'; role = 'researcher'; dependsOn = @('missing') }),
                @(@{ id = 'a'; role = 'unknown' })
            )) {
            $path = Join-Path $script:MetadataRepo ("bad-plan-" + [guid]::NewGuid().ToString('N') + '.json')
            Write-FixtureJson $path @{ squadRoot = $script:MetadataFixture.Root; units = $units }
            (Invoke-Local 'New-SquadDispatchPlan.ps1' $script:MetadataRepo @('-RepoRoot', $script:MetadataRepo, '-InputPath', $path)).ExitCode | Should -Be 1
        }
    }

    It 'batches independent eligible work and rejects overlapping declared write sets' {
        $path = Join-Path $script:MetadataRepo 'parallel.json'
        $units = @(
            @{ id = 'a'; role = 'researcher'; parallel = $true; writePaths = @('one.md') },
            @{ id = 'b'; role = 'tester'; parallel = $true; writePaths = @('two.md') }
        )
        Write-FixtureJson $path @{ squadRoot = $script:MetadataFixture.Root; units = $units }
        $result = Invoke-Local 'New-SquadDispatchPlan.ps1' $script:MetadataRepo @('-RepoRoot', $script:MetadataRepo, '-InputPath', $path, '-MaxConcurrent', '2')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        @((($result.Output | ConvertFrom-Json).waves)[0].units) | Should -Be @('a', 'b')
        $units[1].writePaths = @('one.md')
        Write-FixtureJson $path @{ squadRoot = $script:MetadataFixture.Root; units = $units }
        $bad = Invoke-Local 'New-SquadDispatchPlan.ps1' $script:MetadataRepo @('-RepoRoot', $script:MetadataRepo, '-InputPath', $path)
        $bad.ExitCode | Should -Be 1
        $bad.Output | Should -Match 'overlap'
    }

    It 'prints only the requested canonical gate and refuses unknown names' {
        $result = Invoke-Local 'Get-SquadProcedure.ps1' $script:MetadataRepo @('-Name', 'implementation')
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match '## Implementation Gate Procedure'
        $result.Output | Should -Match '### Review Follow-Through'
        $result.Output | Should -Not -Match '## Autopilot Procedure|## Intake Gate Procedure'
        (Invoke-Local 'Get-SquadProcedure.ps1' $script:MetadataRepo @('-Name', 'unknown')).ExitCode | Should -Be 1
    }

    It 'resolves a provider-qualified native type instead of dispatching the display name' {
        $path = Join-Path $script:MetadataRepo 'native-plan.json'
        Write-FixtureJson $path @{
            squadRoot = $script:MetadataFixture.Root
            agentTypes = @('fixture:squad-implementor', 'general-purpose')
            units = @(@{ id = 'work'; role = 'developer' })
        }
        $result = Invoke-Local 'New-SquadDispatchPlan.ps1' $script:MetadataRepo @('-RepoRoot', $script:MetadataRepo, '-InputPath', $path)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        ($result.Output | ConvertFrom-Json).units[0].endpoint.nativeAgentTypes.'Squad Implementor' | Should -BeExactly 'fixture:squad-implementor'
    }

    It 'finds pending connector ids in their registered dropPath, preserving consumed-task state' {
        $repo = New-FixtureRepo
        $root = Join-Path $repo '.copilot-tracking/squad'
        Write-FixtureText (Join-Path $root 'team.md') "# Team`n`n| Binding ID | Manifest |`n|---|---|`n| delivery | connector.json |`n"
        Write-FixtureJson (Join-Path $repo 'connector.json') @{ connectorId = 'delivery'; dropPath = 'mailbox' }
        foreach ($id in @('pending', 'consumed')) {
            Write-FixtureJson (Join-Path $repo "mailbox/.squad-connector/$id.state.json") @{ taskId = $id; connectorId = 'delivery'; consumed = ($id -eq 'consumed') }
            Write-FixtureJson (Join-Path $repo "mailbox/$id.request.json") @{ taskId = $id; connectorId = 'delivery'; role = 'developer' }
        }
        $before = Get-FixtureHash $repo
        $pending = @(Get-SquadPendingConnectors -RepoRoot $repo -SquadRoot $root)
        $pending.Count | Should -Be 1
        $pending[0].taskId | Should -Be 'pending'
        $pending[0].requestPath | Should -Be (Join-Path $repo 'mailbox/pending.request.json')
        Get-FixtureHash $repo | Should -BeExactly $before
    }

    It 'uses the matched routing row and never batches an escalate-tier endpoint' {
        $routingPath = Join-Path $script:MetadataFixture.Root 'routing.md'
        $original = [IO.File]::ReadAllText($routingPath)
        try {
            [IO.File]::WriteAllText($routingPath, $original.TrimEnd("`r", "`n") + "`n| escalation fixture | researcher | escalate | yes |`n")
            $autoPattern = @(Read-SquadTables $routingPath | Where-Object { 'Role(s)' -in $_.Header })[0].Rows |
                Where-Object { $_['Role(s)'] -ceq 'researcher' -and $_['Autonomy Tier'] -eq 'auto' } |
                Select-Object -First 1
            foreach ($pattern in @($autoPattern['Pattern / Keyword'], 'escalation fixture')) {
                $path = Join-Path $script:MetadataRepo 'tier-plan.json'
                Write-FixtureJson $path @{
                    squadRoot = $script:MetadataFixture.Root
                    units = @(@{ id = 'work'; role = 'researcher'; pattern = $pattern; parallel = $true; readOnly = $true })
                }
                $result = Invoke-Local 'New-SquadDispatchPlan.ps1' $script:MetadataRepo @('-RepoRoot', $script:MetadataRepo, '-InputPath', $path)
                $result.ExitCode | Should -Be 0 -Because "pattern '$pattern': $($result.Output)"
                $unit = ($result.Output | ConvertFrom-Json).units[0]
                if ($pattern -eq 'escalation fixture') {
                    $unit.parallel | Should -BeFalse
                    $unit.endpoint.autonomyTier | Should -Be 'escalate'
                }
                else { $unit.endpoint.autonomyTier | Should -Be 'auto' }
            }
        }
        finally { [IO.File]::WriteAllText($routingPath, $original) }
    }
}

Describe 'Actual completion evidence (COORD-07)' {
    BeforeAll {
        $script:ProofRepo = New-FixtureRepo
        $script:ProofFixture = Initialize-Fixture $script:ProofRepo
        $script:Work = Write-FixtureWork $script:ProofRepo $script:ProofFixture.Root
    }

    Describe 'Script-derived actual usage facts (COORD-12)' {
        It 'uses reported model identity and tool-call floors without changing history keys' {
            $repo = New-FixtureRepo
            $fixture = Initialize-Fixture $repo
            $work = Write-FixtureWork $repo $fixture.Root -ReportedModel 'claude-haiku-5.5' -InternalToolCalls 45
            $history = [IO.File]::ReadAllText((Join-Path $fixture.Root 'history/Squad Implementor.md'))
            $block = [regex]::Match($history, '(?s)```json\s*\n(?<json>.*?)\n```').Groups['json'].Value | ConvertFrom-Json -AsHashtable
            $block.model | Should -Be 'claude-haiku-5.5'
            $block.model_source | Should -Be 'dispatch-reported'
            $block.internal_turns | Should -Be 45
            $block.Count | Should -Be 10
            $work.Turn | Should -Be 2
        }
    }

    It 'verifies exact current-turn files, history, consumption, state and ledger without writes' {
        $before = Get-FixtureHash $script:ProofFixture.Root
        $result = Invoke-Local 'Test-SquadTurnCompletion.ps1' $script:ProofRepo @('-RepoRoot', $script:ProofRepo, '-SquadRoot', $script:ProofFixture.Root, '-ProofPath', $script:Work.Payload, '-ExpectedTurn', [string]$script:Work.Turn)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $receipt = $result.Output | ConvertFrom-Json
        $receipt.verified | Should -BeTrue
        $receipt.dispatchEntries | Should -Be 1
        $receipt.ledgerCheck | Should -Be 'PASS'
        Get-FixtureHash $script:ProofFixture.Root | Should -BeExactly $before
    }

    It 'accepts the canonical roster role id in activeRoles for its mapped agent dispatch' {
        $repo = New-FixtureRepo
        $fixture = Initialize-Fixture $repo
        $work = Write-FixtureWork $repo $fixture.Root -ActiveRole 'developer'
        $result = Invoke-Local 'Test-SquadTurnCompletion.ps1' $repo @(
            '-RepoRoot', $repo,
            '-SquadRoot', $fixture.Root,
            '-ProofPath', $work.Payload,
            '-ExpectedTurn', [string]$work.Turn
        )
        $result.ExitCode | Should -Be 0 -Because $result.Output
    }

    It 'does not count a previous turn as the expected current dispatch' {
        $result = Invoke-Local 'Test-SquadTurnCompletion.ps1' $script:ProofRepo @('-RepoRoot', $script:ProofRepo, '-SquadRoot', $script:ProofFixture.Root, '-ProofPath', $script:Work.Payload, '-ExpectedTurn', [string]($script:Work.Turn + 1))
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'did not advance'
    }

    It 'refuses a real but unrelated artifact instead of accepting the existence proxy' {
        $payload = Get-Content -LiteralPath $script:Work.Payload -Raw | ConvertFrom-Json -AsHashtable
        Write-FixtureText (Join-Path $script:ProofRepo 'unrelated.md') '# Unrelated'
        $payload.historyRecords[0].deliverable = 'unrelated.md'
        $path = Join-Path $script:ProofRepo 'wrong-proof.json'
        Write-FixtureJson $path $payload
        $result = Invoke-Local 'Test-SquadTurnCompletion.ps1' $script:ProofRepo @('-RepoRoot', $script:ProofRepo, '-SquadRoot', $script:ProofFixture.Root, '-ProofPath', $path, '-ExpectedTurn', [string]$script:Work.Turn)
        $result.ExitCode | Should -Be 1
    }
}

Describe 'Federation scheduling and deterministic persistence (COORD-08, COORD-11)' {
    BeforeAll {
        $script:Federation = New-FederationFixture
        $script:FedTurn = New-FederationTurn $script:Federation
    }

    It 'rejects root mutation after the pre-dispatch snapshot without changing any other bytes' {
        $statePath = Join-Path $script:Federation.Root 'state.json'
        $bytes = [IO.File]::ReadAllBytes($statePath)
        try {
            [IO.File]::AppendAllText($statePath, "`n")
            $before = Get-FixtureHash $script:Federation.Root
            $result = Invoke-Local 'Write-SquadFederationHandoff.ps1' $script:Federation.Repo @('-RepoRoot', $script:Federation.Repo, '-SquadRoot', $script:Federation.Root, '-PayloadPath', $script:FedTurn.Path)
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'changed since'
            Get-FixtureHash $script:Federation.Root | Should -BeExactly $before
        }
        finally { [IO.File]::WriteAllBytes($statePath, $bytes) }
    }

    It 'rejects missing inner artifact proof before any root write' {
        $inner = Get-Content -LiteralPath $script:FedTurn.Value.subSquads[0].proofPath -Raw | ConvertFrom-Json -AsHashtable
        $path = Join-Path $script:Federation.Repo $inner.historyRecords[0].deliverable
        $bytes = [IO.File]::ReadAllBytes($path)
        try {
            [IO.File]::Delete($path)
            $before = Get-FixtureHash $script:Federation.Root
            $result = Invoke-Local 'Write-SquadFederationHandoff.ps1' $script:Federation.Repo @('-RepoRoot', $script:Federation.Repo, '-SquadRoot', $script:Federation.Root, '-PayloadPath', $script:FedTurn.Path)
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'Inner completion failed'
            Get-FixtureHash $script:Federation.Root | Should -BeExactly $before
        }
        finally { [IO.File]::WriteAllBytes($path, $bytes) }
    }

    It 'writes both levels and preserves bytes, unrelated state, totals and root-only overhead' {
        $beforeDecisions = [IO.File]::ReadAllText((Join-Path $script:Federation.Root 'decisions.md'))
        $result = Invoke-Local 'Write-SquadFederationHandoff.ps1' $script:Federation.Repo @('-RepoRoot', $script:Federation.Repo, '-SquadRoot', $script:Federation.Root, '-PayloadPath', $script:FedTurn.Path)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $receipt = $result.Output | ConvertFrom-Json
        $receipt.verified | Should -BeTrue
        $receipt.turn | Should -Be 2
        $receipt.activeSubSquads | Should -Be @('product', 'azure')
        [IO.File]::ReadAllText((Join-Path $script:Federation.Root 'decisions.md')).StartsWith($beforeDecisions) | Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $script:Federation.Root 'history/product.md')) | Should -Not -Match '#### Consumption'
        $state = Get-Content -LiteralPath (Join-Path $script:Federation.Root 'state.json') -Raw | ConvertFrom-Json
        $state.subSquads | Should -Be @('product', 'azure')
        $state.notify.approvalChannel | Should -Be 'in-chat'
        $state.currentRun.costPreflight.decision | Should -Be 'not-requested'
        $check = Invoke-Local 'Test-SquadTurnCompletion.ps1' $script:Federation.Repo @('-RepoRoot', $script:Federation.Repo, '-SquadRoot', $script:Federation.Root, '-ProofPath', $script:FedTurn.Path, '-ExpectedTurn', '2')
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }

    It 'rejects replay of an already-written snapshot' {
        (Get-Content -LiteralPath (Join-Path $script:Federation.Root 'state.json') -Raw | ConvertFrom-Json).turn | Should -Be 2
        $before = Get-FixtureHash $script:Federation.Root
        $result = Invoke-Local 'Write-SquadFederationHandoff.ps1' $script:Federation.Repo @('-RepoRoot', $script:Federation.Repo, '-SquadRoot', $script:Federation.Root, '-PayloadPath', $script:FedTurn.Path)
        $result.ExitCode | Should -Be 1
        Get-FixtureHash $script:Federation.Root | Should -BeExactly $before
    }

    It 'carries previous root overhead once on a later member turn' {
        $rootStatePath = Join-Path $script:Federation.Root 'state.json'
        $before = Get-Content -LiteralPath $rootStatePath -Raw | ConvertFrom-Json
        $memberBefore = 0.0
        foreach ($name in @('product', 'azure')) {
            $memberBefore += (Get-Content -LiteralPath (Join-Path $script:Federation.Members[$name].Root 'state.json') -Raw | ConvertFrom-Json).currentRun.estCostUsd
        }
        $overhead = $before.currentRun.estCostUsd - $memberBefore
        $overhead | Should -BeGreaterThan 0
        $second = New-FederationTurn $script:Federation @('product')
        $result = Invoke-Local 'Write-SquadFederationHandoff.ps1' $script:Federation.Repo @('-RepoRoot', $script:Federation.Repo, '-SquadRoot', $script:Federation.Root, '-PayloadPath', $second.Path)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $after = Get-Content -LiteralPath $rootStatePath -Raw | ConvertFrom-Json
        $memberAfter = 0.0
        foreach ($name in @('product', 'azure')) {
            $memberAfter += (Get-Content -LiteralPath (Join-Path $script:Federation.Members[$name].Root 'state.json') -Raw | ConvertFrom-Json).currentRun.estCostUsd
        }
        [Math]::Abs(($after.currentRun.estCostUsd - $memberAfter) - 2 * $overhead) | Should -BeLessOrEqual 0.0001 -Because "root before=$($before.currentRun.estCostUsd), members before=$memberBefore, overhead=$overhead; root after=$($after.currentRun.estCostUsd), members after=$memberAfter"
        $after.activeSubSquads | Should -Be @('product')
    }
}
