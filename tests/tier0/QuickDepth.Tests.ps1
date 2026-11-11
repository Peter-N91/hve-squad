#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Consumed in BeforeAll.')]
param([Parameter(Mandatory)][string]$SourceRoot)

BeforeAll {
    $script:OriginalCopilotHome = $env:COPILOT_HOME
    $env:COPILOT_HOME = Join-Path $TestDrive 'empty-copilot-home'
    $null = [IO.Directory]::CreateDirectory($env:COPILOT_HOME)
    $script:Helpers = Join-Path $SourceRoot 'squad-src' '.github' 'skills' 'squad' 'scripts'
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
        $repo = Join-Path $TestDrive ("quick depth repo " + [guid]::NewGuid().ToString('N'))
        $null = [IO.Directory]::CreateDirectory($repo)
        $repo
    }

    function Get-FixtureHash {
        param([string]$Root)
        @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
                [IO.Path]::GetRelativePath($Root, $_.FullName) + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash
            }) -join "`n"
    }

    function Initialize-Fixture {
        param([string]$Repo, [string[]]$Roles = @())
        $choicesPath = Join-Path $Repo 'choices.json'
        $payloadPath = Join-Path $Repo 'init.json'
        $choices = @{
            confirmed = $true
            squadRoot = '.copilot-tracking/squad'
            runId = 'quick-depth-fixture'
            profile = $(if ($Roles.Count) { 'custom' } else { 'default' })
            naming = 'aliases'
            notify = @{ approvalChannel = 'in-chat'; enabled = $false }
            sessionModel = 'claude-sonnet-5.5'
        }
        if ($Roles.Count) { $choices.roles = $Roles }
        Write-FixtureJson $choicesPath $choices
        $prepared = Invoke-Local 'Get-SquadInitContext.ps1' $Repo @('-RepoRoot', $Repo, '-ChoicesPath', $choicesPath, '-PayloadPath', $payloadPath)
        if ($prepared.ExitCode -ne 0) { throw $prepared.Output }
        $initialized = Invoke-Local 'Initialize-Squad.ps1' $Repo @('-RepoRoot', $Repo, '-PayloadPath', $payloadPath, '-Direct')
        if ($initialized.ExitCode -ne 0) { throw $initialized.Output }
        Join-Path $Repo '.copilot-tracking/squad'
    }

    function Invoke-DepthPlan {
        param([string]$Repo, [hashtable]$PlanInput)
        $path = Join-Path $Repo ("depth-" + [guid]::NewGuid().ToString('N') + '.json')
        Write-FixtureJson $path $PlanInput
        Invoke-Local 'New-SquadDispatchPlan.ps1' $Repo @('-RepoRoot', $Repo, '-InputPath', $path)
    }

    function New-FullPipelineUnits {
        @(
            @{ id = 'research'; role = 'researcher' }
            @{ id = 'plan'; role = 'lead'; dependsOn = @('research') }
            @{ id = 'implement'; role = 'developer'; dependsOn = @('plan'); writePaths = @('src/ledger.py') }
            @{ id = 'review'; role = 'tester'; dependsOn = @('implement'); readOnly = $true }
        )
    }
}

AfterAll {
    $env:COPILOT_HOME = $script:OriginalCopilotHome
}

Describe 'Quick depth trusted input and graph enforcement' {
    It 'treats omitted depth as explicit standard and never infers quick from a bounded-looking graph' {
        $repo = New-FixtureRepo
        $root = Initialize-Fixture $repo
        $before = Get-FixtureHash $root
        $result = Invoke-DepthPlan -Repo $repo -PlanInput @{
            squadRoot = $root
            units = New-FullPipelineUnits
            depthEvidence = @{}
        }
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $plan = $result.Output | ConvertFrom-Json
        $plan.depth.requested | Should -Be 'standard'
        $plan.depth.source | Should -Be 'default'
        $plan.depth.effective | Should -Be 'standard'
        @($plan.units).Count | Should -Be 4
        @($plan.depth.skippedUnits).Count | Should -Be 0
        Get-FixtureHash $root | Should -BeExactly $before
    }

    It 'accepts the brief default pair requestedDepth standard with depthSource default' {
        $repo = New-FixtureRepo
        $root = Initialize-Fixture $repo
        $result = Invoke-DepthPlan -Repo $repo -PlanInput @{
            squadRoot = $root
            requestedDepth = 'standard'
            depthSource = 'default'
            units = New-FullPipelineUnits
        }
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $plan = $result.Output | ConvertFrom-Json
        $plan.depth.requested | Should -Be 'standard'
        $plan.depth.source | Should -Be 'default'
    }

    It 'refuses quick without a trusted input or federation source' {
        $repo = New-FixtureRepo
        $root = Initialize-Fixture $repo
        $result = Invoke-DepthPlan -Repo $repo -PlanInput @{
            squadRoot = $root
            requestedDepth = 'quick'
            units = @(@{ id = 'work'; role = 'developer'; writePaths = @('src/work.ps1') })
        }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'requestedDepth quick requires trusted depthSource input, federation, or workflow'
    }

    It 'computes the bounded plan before waves and removes supplied Research and Plan units' {
        $repo = New-FixtureRepo
        $root = Initialize-Fixture $repo
        $result = Invoke-DepthPlan -Repo $repo -PlanInput @{
            squadRoot = $root
            requestedDepth = 'quick'
            depthSource = 'input'
            depthEvidence = @{
                exactTargets = 'src/ledger.py: add the named method'
                noOpenQuestions = 'the requested behavior and validation are explicit'
                noCouncilLens = 'no architecture, security, cost, product-fit, or RAI lens applies'
                noGateTrigger = 'no risk, impactful action, intake, or discovery trigger applies'
                noCritiqueRequested = 'the user requested implementation and final review only'
            }
            units = New-FullPipelineUnits
        }
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $plan = $result.Output | ConvertFrom-Json
        $plan.depth.route | Should -Be 'bounded'
        @($plan.depth.skippedUnits.id | Sort-Object) | Should -Be @('plan', 'research')
        @($plan.units.id) | Should -Be @('implement', 'review')
        @($plan.waves[0].units) | Should -Be @('implement')
        @($plan.waves[1].units) | Should -Be @('review')
        @($plan.units | Where-Object id -eq 'implement')[0].endpoint.depth | Should -Be 'quick'
        @($plan.units | Where-Object id -eq 'review')[0].endpoint.depth | Should -Be 'standard'
    }

    It 'keeps the full graph when quick evidence proves neither a lane nor artifact reuse' {
        $repo = New-FixtureRepo
        $root = Initialize-Fixture $repo
        $result = Invoke-DepthPlan -Repo $repo -PlanInput @{
            squadRoot = $root
            requestedDepth = 'quick'
            depthSource = 'input'
            units = New-FullPipelineUnits
        }
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $plan = $result.Output | ConvertFrom-Json
        $plan.depth.route | Should -BeNullOrEmpty
        @($plan.units).Count | Should -Be 4
        @($plan.depth.skippedUnits).Count | Should -Be 0
        @($plan.depth.stages | Where-Object stage -in @('research', 'plan') | ForEach-Object action | Sort-Object -Unique) |
            Should -Be @('shrink')
    }

    It 'ignores quick on an unattended state and preserves every supplied stage' {
        $repo = New-FixtureRepo
        $root = Initialize-Fixture $repo
        $statePath = Join-Path $root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['trigger'] = @{ source = 'issue'; ref = 'Peter-N91/hve-squad#224' }
        Write-FixtureJson $statePath $state
        $before = Get-FixtureHash $root
        $result = Invoke-DepthPlan -Repo $repo -PlanInput @{
            squadRoot = $root
            requestedDepth = 'quick'
            depthSource = 'input'
            depthEvidence = @{
                exactTargets = 'src/ledger.py: add the named method'
                noOpenQuestions = 'none'
                noCouncilLens = 'none'
                noGateTrigger = 'none'
            }
            units = New-FullPipelineUnits
        }
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $plan = $result.Output | ConvertFrom-Json
        $plan.depth.requested | Should -Be 'quick'
        $plan.depth.effective | Should -Be 'standard'
        $plan.depth.ignored | Should -Match 'unattended run'
        @($plan.units).Count | Should -Be 4
        Get-FixtureHash $root | Should -BeExactly $before
    }

    It 'honors quick from trusted workflow configuration on an unattended state and shrinks without a lane' {
        $repo = New-FixtureRepo
        $root = Initialize-Fixture $repo
        $statePath = Join-Path $root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['trigger'] = @{ source = 'issue'; ref = 'Peter-N91/hve-squad#224' }
        Write-FixtureJson $statePath $state
        $result = Invoke-DepthPlan -Repo $repo -PlanInput @{
            squadRoot = $root
            requestedDepth = 'quick'
            depthSource = 'workflow'
            units = New-FullPipelineUnits
        }
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $plan = $result.Output | ConvertFrom-Json
        $plan.depth.source | Should -Be 'workflow'
        $plan.depth.effective | Should -Be 'quick'
        $plan.depth.ignored | Should -BeNullOrEmpty
        $plan.depth.route | Should -BeNullOrEmpty
        @($plan.units).Count | Should -Be 4
        @($plan.depth.skippedUnits).Count | Should -Be 0
        @($plan.depth.stages | Where-Object { $_.kind -eq 'gate' -and $_.action -ne 'run' }).Count | Should -Be 0
    }

    It 'refuses the workflow depth source outside an unattended Watch Mode run' {
        $repo = New-FixtureRepo
        $root = Initialize-Fixture $repo
        $result = Invoke-DepthPlan -Repo $repo -PlanInput @{
            squadRoot = $root
            requestedDepth = 'quick'
            depthSource = 'workflow'
            units = New-FullPipelineUnits
        }
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'unattended Watch Mode run'
    }
}

Describe 'Quick depth gate and parallel policy' {
    It 'keeps every fixed gate at run and standard depth' {
        $plan = Get-SquadDepthPlan -RequestedDepth quick -DepthSource input -StateMode interactive -Evidence @{
            exactTargets = 'src/a.ps1 and src/b.ps1'
            noOpenQuestions = 'none'
            noCouncilLens = 'none'
            noGateTrigger = 'none'
        } -Units @(
            [pscustomobject]@{ Id = 'intake'; Role = 'intake-validator'; Class = 'intake'; ReadOnly = $true; WritePaths = @(); Tier = 'confirm' }
            [pscustomobject]@{ Id = 'security'; Role = 'security'; Class = 'review'; ReadOnly = $true; WritePaths = @(); Tier = 'confirm' }
            [pscustomobject]@{ Id = 'review'; Role = 'tester'; Class = 'review'; ReadOnly = $true; WritePaths = @(); Tier = 'auto' }
        )
        $gateRows = @($plan.stages | Where-Object kind -eq 'gate')
        @($gateRows.stage | Sort-Object) | Should -Be @(
            'cost-preflight', 'final-review', 'impactful-action-gate', 'intake-gate',
            'risk-gate', 'security-review', 'task-fit-council'
        )
        @($gateRows.action | Sort-Object -Unique) | Should -Be @('run')
    }

    It 'records a closing review as required follow-up for a per-role implementation plan' {
        $plan = Get-SquadDepthPlan -RequestedDepth quick -DepthSource input -StateMode interactive -Units @(
            [pscustomobject]@{ Id = 'work'; Role = 'developer'; Class = 'implementation'; Stage = 'implement'; ReadOnly = $false; WritePaths = @('src/work.ps1'); Tier = 'confirm' }
        )
        @($plan.gateCoverage | Where-Object stage -eq 'final-review')[0].status | Should -Be 'required-follow-up'
        @($plan.stages | Where-Object stage -eq 'final-review')[0].action | Should -Be 'run'
    }

    It 'adds concurrency only for a verified deliverable-fan-out plan' {
        $repo = New-FixtureRepo
        $root = Initialize-Fixture $repo -Roles @('researcher', 'lead', 'developer', 'technical-writer', 'tester', 'scribe')
        $routingPath = Join-Path $root 'routing.md'
        $routing = [IO.File]::ReadAllText($routingPath) -replace '(?m)\|\s*yes\s*\|\s*$', '| no |'
        Write-FixtureText $routingPath $routing
        $planRelative = '.copilot-tracking/plans/2026-11-06-implementation.md'
        $planPath = Join-Path $repo $planRelative
        Write-FixtureText $planPath "# Plan`n`n* **Implement Shape** - ``single-build```n"
        $input = @{
            squadRoot = $root
            requestedDepth = 'quick'
            depthSource = 'input'
            planPath = $planRelative
            units = @(
                @{ id = 'code'; role = 'developer'; parallel = $true; writePaths = @('src/code.ps1') }
                @{ id = 'docs'; role = 'technical-writer'; parallel = $true; writePaths = @('docs/code.md') }
                @{ id = 'review'; role = 'tester'; parallel = $true; readOnly = $true }
            )
        }
        $sequential = Invoke-DepthPlan -Repo $repo -PlanInput $input
        $sequential.ExitCode | Should -Be 0 -Because $sequential.Output
        $sequentialPlan = $sequential.Output | ConvertFrom-Json
        $sequentialPlan.depth.parallelism.enabled | Should -BeFalse
        @($sequentialPlan.waves).Count | Should -Be 3

        Write-FixtureText $planPath "# Plan`n`n* **Implement Shape** - ``deliverable-fan-out```n"
        $parallel = Invoke-DepthPlan -Repo $repo -PlanInput $input
        $parallel.ExitCode | Should -Be 0 -Because $parallel.Output
        $parallelPlan = $parallel.Output | ConvertFrom-Json
        $parallelPlan.depth.parallelism.enabled | Should -BeTrue
        $parallelPlan.depth.parallelism.basis | Should -Be 'deliverable-fan-out'
        @($parallelPlan.waves).Count | Should -Be 2
        @($parallelPlan.waves[0].units | Sort-Object) | Should -Be @('code', 'docs')
        @($parallelPlan.waves[1].units) | Should -Be @('review')
        @($parallelPlan.units | Where-Object id -eq 'review')[0].parallel | Should -BeFalse
        @($parallelPlan.depth.parallelism.batches).Count | Should -Be 1
    }
}

Describe 'Quick depth model-routing independence' {
    It 'skips bounded Research and Plan before manual model validation' {
        $repo = New-FixtureRepo
        $root = Initialize-Fixture $repo
        $result = Invoke-DepthPlan -Repo $repo -PlanInput @{
            squadRoot = $root
            requestedModelRouting = 'manual'
            manualModels = @{ developer = 'gpt-5.6-sol'; tester = 'gpt-5.6-sol' }
            sessionModel = 'gpt-5.6-sol'
            availableModels = @('gpt-5.6-sol')
            requestedDepth = 'quick'
            depthSource = 'input'
            depthEvidence = @{
                exactTargets = 'src/ledger.py: add the named method'
                noOpenQuestions = 'the request is fully specified'
                noCouncilLens = 'no council lens applies'
                noGateTrigger = 'no gate trigger applies'
                noCritiqueRequested = 'no critique was requested'
            }
            units = New-FullPipelineUnits
        }
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $plan = $result.Output | ConvertFrom-Json
        @($plan.units.id) | Should -Be @('implement', 'review')
        @($plan.routingRefresh.changes.role | Sort-Object) | Should -Be @('developer', 'tester')
    }

    It 'keeps the selected model unchanged under routing <Mode>' -ForEach @(
        @{ Mode = 'off' }
        @{ Mode = 'ranked' }
        @{ Mode = 'economy' }
        @{ Mode = 'manual' }
    ) {
        $repo = New-FixtureRepo
        $root = Initialize-Fixture $repo
        $base = @{
            squadRoot = $root
            sessionModel = 'gpt-5.6-sol'
            availableModels = @('gpt-5.6-sol', 'gpt-5.4', 'claude-haiku-5.5')
            units = @(
                @{ id = 'work'; role = 'developer'; writePaths = @('src/work.ps1') }
                @{ id = 'review'; role = 'tester'; dependsOn = @('work'); readOnly = $true }
            )
        }
        if ($Mode -ne 'off') { $base.requestedModelRouting = $Mode }
        if ($Mode -eq 'manual') { $base.manualModels = @{ developer = 'gpt-5.6-sol'; tester = 'gpt-5.6-sol' } }
        if ($Mode -eq 'economy') {
            $base.economyConsent = @{
                user = 'fixture-user'
                tradeAccepted = 'Every routed role uses the cheapest known-price model inside its floor.'
                neverWeakened = 'Floors and gates remain unchanged.'
            }
        }
        $standardInput = @{} + $base
        $standardInput.requestedDepth = 'standard'
        $standardInput.depthSource = 'input'
        $quickInput = @{} + $base
        $quickInput.requestedDepth = 'quick'
        $quickInput.depthSource = 'input'

        $standard = Invoke-DepthPlan -Repo $repo -PlanInput $standardInput
        $quick = Invoke-DepthPlan -Repo $repo -PlanInput $quickInput
        $standard.ExitCode | Should -Be 0 -Because $standard.Output
        $quick.ExitCode | Should -Be 0 -Because $quick.Output
        $standardPlan = $standard.Output | ConvertFrom-Json
        $quickPlan = $quick.Output | ConvertFrom-Json
        $quickWork = @($quickPlan.units | Where-Object id -eq 'work')[0]
        $standardWork = @($standardPlan.units | Where-Object id -eq 'work')[0]
        $quickWork.endpoint.model | Should -BeExactly $standardWork.endpoint.model
        $quickWork.endpoint.pricingModel | Should -BeExactly $standardWork.endpoint.pricingModel
    }
}
