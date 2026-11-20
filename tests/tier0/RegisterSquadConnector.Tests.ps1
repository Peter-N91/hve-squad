#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

# AI cost: none; exercises the deterministic connector registration transaction.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Fixture helpers mutate only Pester TestDrive repositories.')]
param([Parameter(Mandatory)][string]$PackageRoot)

BeforeAll {
    $skillRoot = if (Test-Path -LiteralPath (Join-Path $PackageRoot 'squad-src/.github/skills/squad')) {
        Join-Path $PackageRoot 'squad-src/.github/skills/squad'
    }
    else {
        Join-Path $PackageRoot '.agents/skills/squad'
    }
    $script:Register = Join-Path $skillRoot 'scripts/Register-SquadConnector.ps1'
    $script:Initialize = Join-Path $skillRoot 'scripts/Initialize-Squad.ps1'
    $script:Resolve = Join-Path $skillRoot 'scripts/Resolve-SquadConnectorDispatch.ps1'
    $script:Ledger = Join-Path $skillRoot 'scripts/Measure-SquadLedger.ps1'

    function Write-JsonLocal {
        param([string]$Path, $Value)
        [IO.File]::WriteAllText(
            $Path,
            ($Value | ConvertTo-Json -Depth 30),
            [Text.UTF8Encoding]::new($false)
        )
    }

    function Invoke-Local {
        param(
            [Parameter(Mandatory)][string]$Repo,
            [Parameter(Mandatory)][string]$Script,
            [string[]]$Arguments = @()
        )
        Push-Location $Repo
        try {
            $output = & pwsh -NoProfile -File $Script @Arguments 2>&1 | Out-String
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
        }
        finally { Pop-Location }
    }

    function Get-StateHash {
        param([string]$Root)
        @(
            Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
                $relative = [IO.Path]::GetRelativePath($Root, $_.FullName)
                if ($_.PSIsContainer) { "D:$relative" }
                else { "F:${relative}:$($_.Length):$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
            }
        ) -join "`n"
    }

    function Get-ConnectorManifest {
        param(
            [string]$ConnectorId = 'fixture-research',
            [string[]]$Roles = @('researcher')
        )
        [ordered]@{
            connectorId = $ConnectorId
            schemaVersion = '1.1'
            endpointKind = 'agent'
            transport = 'file'
            capabilities = @('Performs the declared bounded work')
            roles = @($Roles)
            dropPath = ".connector-drops/$ConnectorId"
            deadlineMinutesDefault = 30
            retryCapDefault = 1
            contact = 'connectors@example.invalid'
            version = '1.0.0'
        }
    }

    function New-AgentLocal {
        param([string]$Repo, [string]$Name)
        $root = Join-Path $Repo '.github/agents'
        $null = [IO.Directory]::CreateDirectory($root)
        $file = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-') + '.agent.md'
        [IO.File]::WriteAllText(
            (Join-Path $root $file),
            "---`nname: $Name`nuser-invocable: false`n---`n`nFixture agent.`n",
            [Text.UTF8Encoding]::new($false)
        )
    }

    function New-SquadFixture {
        param(
            [string]$ConnectorId = 'fixture-research',
            [string[]]$Roles = @('researcher')
        )
        $repo = Join-Path $TestDrive ("connector-registration-$([guid]::NewGuid().ToString('N'))")
        $null = [IO.Directory]::CreateDirectory($repo)
        foreach ($agent in @(
                'Squad Researcher', 'Squad Lead', 'Squad Implementor',
                'Squad Reviewer', 'Squad Scribe', 'Squad Connector'
            )) {
            New-AgentLocal -Repo $repo -Name $agent
        }
        $dash = [string][char]0x2014
        $roster = @(
            [ordered]@{ Role = 'researcher'; 'Member Name' = 'Alpha'; 'Agent Name (Primary)' = 'Squad Researcher'; 'Alternate Agents' = $dash; 'Selection Cue' = $dash; Invocation = 'runSubagent / task'; 'Model Tier' = 'default'; 'Deliverable Root' = '.copilot-tracking/research/' }
            [ordered]@{ Role = 'lead'; 'Member Name' = 'Beta'; 'Agent Name (Primary)' = 'Squad Lead'; 'Alternate Agents' = $dash; 'Selection Cue' = $dash; Invocation = 'runSubagent / task'; 'Model Tier' = 'default'; 'Deliverable Root' = '.copilot-tracking/plans/' }
            [ordered]@{ Role = 'developer'; 'Member Name' = 'Gamma'; 'Agent Name (Primary)' = 'Squad Implementor'; 'Alternate Agents' = $dash; 'Selection Cue' = $dash; Invocation = 'runSubagent / task'; 'Model Tier' = 'default'; 'Deliverable Root' = '.copilot-tracking/changes/' }
            [ordered]@{ Role = 'tester'; 'Member Name' = 'Delta'; 'Agent Name (Primary)' = 'Squad Reviewer'; 'Alternate Agents' = $dash; 'Selection Cue' = $dash; Invocation = 'runSubagent / task'; 'Model Tier' = 'fast'; 'Deliverable Root' = '.copilot-tracking/reviews/' }
            [ordered]@{ Role = 'scribe'; 'Member Name' = ''; 'Agent Name (Primary)' = 'Squad Scribe'; 'Alternate Agents' = $dash; 'Selection Cue' = $dash; Invocation = 'runSubagent / task'; 'Model Tier' = 'fast'; 'Deliverable Root' = '(squad state)' }
        )
        $payloadPath = Join-Path $repo 'init.json'
        Write-JsonLocal $payloadPath @{
            squadRoot = '.copilot-tracking/squad'
            runId = 'connector-registration-init'
            roster = $roster
            provenance = 'custom'
            modelRouting = 'off'
            sessionModel = 'claude-sonnet-5.5'
            stateAdvance = @{ activeRoles = @() }
        }
        $initialized = Invoke-Local -Repo $repo -Script $script:Initialize -Arguments @(
            '-RepoRoot', $repo,
            '-PayloadPath', $payloadPath,
            '-Direct'
        )
        if ($initialized.ExitCode -ne 0) { throw $initialized.Output }
        $manifestDirectory = Join-Path $repo 'connectors'
        $null = [IO.Directory]::CreateDirectory($manifestDirectory)
        $manifestPath = Join-Path $manifestDirectory "$ConnectorId.json"
        Write-JsonLocal $manifestPath (Get-ConnectorManifest -ConnectorId $ConnectorId -Roles $Roles)
        [pscustomobject]@{
            Repo = $repo
            Root = Join-Path $repo '.copilot-tracking/squad'
            Manifest = "connectors/$ConnectorId.json"
            ManifestPath = $manifestPath
        }
    }

    function Get-ReplaceArgument {
        param(
            [Parameter(Mandatory)]$Fixture,
            [string]$BindingId = 'research-fixture',
            [string]$DefaultExecution = 'connector',
            [string]$MemberName = 'Org Researcher'
        )
        @(
            '-RepoRoot', $Fixture.Repo
            '-ManifestPath', $Fixture.Manifest
            '-BindingId', $BindingId
            '-RoleMode', 'replace'
            '-TargetRole', 'researcher'
            '-MemberName', $MemberName
            '-DefaultExecution', $DefaultExecution
            '-RunId', 'connector-registration-test'
        )
    }
}

Describe 'Register-SquadConnector.ps1 deterministic registration' -Tag 'Unit' {
    It 'previews a replacement without writing squad state' {
        $fixture = New-SquadFixture
        $before = Get-StateHash $fixture.Root
        $result = Invoke-Local -Repo $fixture.Repo -Script $script:Register `
            -Arguments (Get-ReplaceArgument $fixture)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $receipt = $result.Output | ConvertFrom-Json
        $receipt.status | Should -Be 'planned'
        $receipt.stateWritten | Should -BeFalse
        $receipt.aiCost | Should -Be 'none'
        (Get-StateHash $fixture.Root) | Should -BeExactly $before
    }

    It 'writes only roster, routing, and decision state for a replacement' {
        $fixture = New-SquadFixture
        $root = $fixture.Root
        $preserved = @('state.json', 'consumption.md', 'consumption-rates.md', 'notifications.md', 'history/Squad Scribe.md')
        $before = [ordered]@{}
        foreach ($name in $preserved) {
            $before[$name] = (Get-FileHash -LiteralPath (Join-Path $root $name) -Algorithm SHA256).Hash
        }
        $result = Invoke-Local -Repo $fixture.Repo -Script $script:Register -Arguments (
            (Get-ReplaceArgument $fixture) + '-Confirmed'
        )
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $receipt = $result.Output | ConvertFrom-Json
        $receipt.status | Should -Be 'written'
        $receipt.accountingPreserved | Should -BeTrue
        $receipt.historyPreserved | Should -BeTrue
        $receipt.aiCost | Should -Be 'none'
        $team = Get-Content -LiteralPath (Join-Path $root 'team.md') -Raw
        $team | Should -Match '(?m)^\| research-fixture \| fixture-research \|' -Because 'the registration row is roster-owned'
        $team | Should -Match '\| Org Researcher \|  \|  \| connector \|' -Because 'blank additive cells and the default are explicit'
        Get-Content -LiteralPath (Join-Path $root 'decisions.md') -Raw |
            Should -Match 'Source: Register-SquadConnector\.ps1; deterministic local registration; AI cost none'
        foreach ($name in $preserved) {
            (Get-FileHash -LiteralPath (Join-Path $root $name) -Algorithm SHA256).Hash |
                Should -BeExactly $before[$name] -Because $name
        }
        $resolveInput = @{ teamPath = Join-Path $root 'team.md'; role = 'researcher'; unattended = $true } |
            ConvertTo-Json -Compress
        $resolved = Invoke-Local -Repo $fixture.Repo -Script $script:Resolve -Arguments @(
            '-Operation', 'resolve-execution',
            '-InputJson', $resolveInput
        )
        $resolved.ExitCode | Should -Be 0 -Because $resolved.Output
        ($resolved.Output | ConvertFrom-Json).Choice | Should -Be 'connector:research-fixture'
        $ledger = Invoke-Local -Repo $fixture.Repo -Script $script:Ledger `
            -Arguments @('-SquadRoot', $root, '-Check')
        $ledger.ExitCode | Should -Be 0 -Because $ledger.Output
    }

    It 'creates the additive member, route, binding, and saved alignment' {
        $fixture = New-SquadFixture -ConnectorId 'fixture-dotnet' -Roles @('dotnet-practices')
        $arguments = @(
            '-RepoRoot', $fixture.Repo
            '-ManifestPath', $fixture.Manifest
            '-BindingId', 'dotnet-assessor'
            '-RoleMode', 'add'
            '-TargetRole', 'dotnet-practices'
            '-AlignedRole', 'tester'
            '-MemberName', 'Dotnet Assessor'
            '-DefaultExecution', 'connector'
            '-DeliverableRoot', '.copilot-tracking/reviews/dotnet/'
            '-RoutePattern', 'dotnet practices, csharp quality'
            '-AutonomyTier', 'confirm'
            '-ParallelEligible'
            '-RunId', 'connector-add-test'
            '-Confirmed'
        )
        $result = Invoke-Local -Repo $fixture.Repo -Script $script:Register -Arguments $arguments
        $result.ExitCode | Should -Be 0 -Because $result.Output
        ($result.Output | ConvertFrom-Json).memberAdded | Should -BeTrue
        $team = Get-Content -LiteralPath (Join-Path $fixture.Root 'team.md') -Raw
        $team | Should -Match '\| dotnet-practices \| Dotnet Assessor \| Squad Connector \|'
        $team | Should -Match '\| dotnet-assessor \| fixture-dotnet \|'
        $team | Should -Match 'role:dotnet-practices/Dotnet Assessor'
        Get-Content -LiteralPath (Join-Path $fixture.Root 'routing.md') -Raw |
            Should -Match '\| dotnet practices, csharp quality \| dotnet-practices \| confirm \| yes \|'
        $resolveInput = @{ teamPath = Join-Path $fixture.Root 'team.md'; role = 'dotnet-practices'; unattended = $true } |
            ConvertTo-Json -Compress
        $resolved = Invoke-Local -Repo $fixture.Repo -Script $script:Resolve -Arguments @(
            '-Operation', 'resolve-execution',
            '-InputJson', $resolveInput
        )
        $resolved.ExitCode | Should -Be 0 -Because $resolved.Output
        $value = $resolved.Output | ConvertFrom-Json
        $value.MemberName | Should -Be 'Dotnet Assessor'
        $value.BindingId | Should -Be 'dotnet-assessor'
    }

    It 'treats an exact replay as unchanged' {
        $fixture = New-SquadFixture
        $arguments = (Get-ReplaceArgument $fixture) + '-Confirmed'
        $first = Invoke-Local -Repo $fixture.Repo -Script $script:Register -Arguments $arguments
        $first.ExitCode | Should -Be 0 -Because $first.Output
        $before = Get-StateHash $fixture.Root
        $second = Invoke-Local -Repo $fixture.Repo -Script $script:Register -Arguments $arguments
        $second.ExitCode | Should -Be 0 -Because $second.Output
        ($second.Output | ConvertFrom-Json).status | Should -Be 'unchanged'
        (Get-StateHash $fixture.Root) | Should -BeExactly $before
    }

    It 'refuses identity changes through the new-registration path' {
        $fixture = New-SquadFixture
        $first = Invoke-Local -Repo $fixture.Repo -Script $script:Register -Arguments (
            (Get-ReplaceArgument $fixture) + '-Confirmed'
        )
        $first.ExitCode | Should -Be 0 -Because $first.Output
        $before = Get-StateHash $fixture.Root
        $changed = Invoke-Local -Repo $fixture.Repo -Script $script:Register -Arguments (
            (Get-ReplaceArgument $fixture -DefaultExecution 'ask') + '-Confirmed'
        )
        $changed.ExitCode | Should -Not -Be 0
        $changed.Output | Should -Match 'audited binding refresh path'
        (Get-StateHash $fixture.Root) | Should -BeExactly $before
    }

    It 'rejects reserved roles and target member collisions without writing' {
        $fixture = New-SquadFixture
        $before = Get-StateHash $fixture.Root
        $reserved = Get-ReplaceArgument $fixture
        $reserved[[array]::IndexOf($reserved, '-TargetRole') + 1] = 'scribe'
        $reservedResult = Invoke-Local -Repo $fixture.Repo -Script $script:Register `
            -Arguments ($reserved + '-Confirmed')
        $reservedResult.ExitCode | Should -Not -Be 0
        $reservedResult.Output | Should -Match 'reserved for HVE governance'
        $collision = Get-ReplaceArgument $fixture -MemberName 'Alpha'
        $collisionResult = Invoke-Local -Repo $fixture.Repo -Script $script:Register `
            -Arguments ($collision + '-Confirmed')
        $collisionResult.ExitCode | Should -Not -Be 0
        $collisionResult.Output | Should -Match 'differ from the targeted internal member'
        (Get-StateHash $fixture.Root) | Should -BeExactly $before
    }

    It 'accepts a closed JSON registration transport outside squad state' {
        $fixture = New-SquadFixture -ConnectorId 'fixture-json' -Roles @('developer')
        $inputPath = Join-Path $fixture.Repo 'registration.json'
        Write-JsonLocal $inputPath @{
            squadRoot = '.copilot-tracking/squad'
            manifestPath = $fixture.Manifest
            bindingId = 'developer-json'
            roleMode = 'replace'
            targetRole = 'developer'
            memberName = 'JSON Developer'
            defaultExecution = 'ask'
            runId = 'connector-json-test'
            confirmationRef = 'test:confirmed-json'
            confirmed = $true
        }
        $result = Invoke-Local -Repo $fixture.Repo -Script $script:Register -Arguments @(
            '-RepoRoot', $fixture.Repo
            '-InputPath', $inputPath
            '-Confirmed'
        )
        $result.ExitCode | Should -Be 0 -Because $result.Output
        ($result.Output | ConvertFrom-Json).bindingId | Should -Be 'developer-json'
        Get-Content -LiteralPath (Join-Path $fixture.Root 'decisions.md') -Raw |
            Should -Match 'Confirmation: test:confirmed-json'
    }
}
