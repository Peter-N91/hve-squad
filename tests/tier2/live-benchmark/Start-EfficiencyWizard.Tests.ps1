#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

# Tests wizard defaults, consent, setup, progress and stage coordination.
# AI cost: none; commands are mocked or replaced with local fixture processes.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Start-EfficiencyWizard.ps1')
    Mock Write-Host {}
    Mock Get-WizardDefaultsPath { Join-Path $TestDrive 'wizard-defaults.json' }
    function New-WizardTestConfig {
        @{ Mode = 'Complete'; InstallRoot = 'install'; Model = 'fixed-model'; PerRunCredits = 60.0; TotalCredits = 360.0; RunRoot = $TestDrive; BaselineSourceRoot = 'baseline'; CandidateSourceRoot = 'candidate'; BaselineEvidencePath = ''; ParallelTrials = $false }
    }
}

Describe 'Wizard offline Python provisioning' -Tag 'Unit' {
    BeforeEach {
        Mock Get-WizardPython { 'python3.12' }
        Mock Invoke-WizardCommand { 0 }
        Push-Location $TestDrive
        $script:OriginalWizardPath = $env:PATH
    }
    AfterEach {
        $env:PATH = $script:OriginalWizardPath
        Pop-Location
    }
    It 'uses isolated pinned pytest and restores PATH when tests return <ExitCode>' -ForEach @(
        @{ ExitCode = 0 }, @{ ExitCode = 1 }
    ) {
        Mock Invoke-WizardCommand {
            if ($Arguments -contains '-File') {
                $env:PATH.Split([IO.Path]::PathSeparator)[0] | Should -Be (Join-Path $TestDrive ".offline-venv/$(if ($IsWindows) { 'Scripts' } else { 'bin' })")
                return $ExitCode
            }
            0
        }
        Invoke-WizardOfflineTest -PesterPath 'pester.psd1' | Should -Be $ExitCode
        $env:PATH | Should -BeExactly $script:OriginalWizardPath
        Should -Invoke Invoke-WizardCommand -Times 1 -Exactly -ParameterFilter { $Command -eq 'python3.12' -and $Arguments[0] -eq '-m' -and $Arguments[1] -eq 'venv' }
        Should -Invoke Invoke-WizardCommand -Times 1 -Exactly -ParameterFilter { $Arguments -contains 'pip' -and $Arguments -contains 'pytest==8.3.5' }
        Should -Invoke Invoke-WizardCommand -Times 1 -Exactly -ParameterFilter { $Arguments -contains 'Invoke-LiveBenchmarkTests.ps1' -or ($Arguments -contains '-File' -and $Arguments -contains 'pester.psd1') }
    }
    It 'stops before tests when <FailedStep> fails' -ForEach @(
        @{ FailedStep = 'venv' }, @{ FailedStep = 'pip' }
    ) {
        Mock Invoke-WizardCommand { if ($Arguments -contains $FailedStep) { return 1 }; 0 }
        { Invoke-WizardOfflineTest -PesterPath 'pester.psd1' } | Should -Throw '*failed*exit 1*'
        Should -Invoke Invoke-WizardCommand -Times 0 -Exactly -ParameterFilter { $Arguments -contains '-File' }
        $env:PATH | Should -BeExactly $script:OriginalWizardPath
    }
}

Describe 'Wizard portable observation finalization' -Tag 'Unit' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot 'BenchmarkResults.psm1')
    }
    It 'exports outside measured source and prints a parseable offline publication command' {
        $Source = Join-Path $TestDrive 'source'
        $Root = Join-Path $TestDrive "run's-evidence"
        $RunFile = Join-Path $Root 'trials/candidate-1/out/run.json'
        [void][IO.Directory]::CreateDirectory($Source)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($RunFile))
        [IO.File]::WriteAllText($RunFile, '{}')
        Mock Export-BenchmarkCampaign {}
        $Result = Complete-WizardBenchmarkExport @{ Mode = 'Series'; CandidateSourceRoot = $Source; TrialRoot = $Root }
        $Result.status | Should -Be 'exported'
        $Result.recordedTrials | Should -Be 1
        $Result.publicationCommand | Should -Match "run''s-evidence"
        $Result.publicationCommand | Should -Match '-ObservationOnly.*-TrialDirectories @\('
        $Result.publicationCommand | Should -Not -Match '-Live|-Mode Run|copilot'
        $Tokens = $null; $Errors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($Result.publicationCommand, [ref]$Tokens, [ref]$Errors)
        $Errors.Count | Should -Be 0
        Should -Invoke Export-BenchmarkCampaign -Times 1 -Exactly -ParameterFilter {
            $Repository -eq $Source -and $TrialDirectories.Count -eq 1 -and $OutputDirectory -eq (Join-Path $Root 'portable')
        }
        @(Get-ChildItem -LiteralPath $Source -Force).Count | Should -Be 0
    }
    It 'finalizes failed collections and never replaces their exit with export success or failure' {
        $Options = @{ Mode = 'Series'; CandidateSourceRoot = (Join-Path $TestDrive 'source'); TrialRoot = (Join-Path $TestDrive 'failed-run') }
        $Unavailable = Complete-WizardBenchmarkExport $Options
        $Unavailable.status | Should -Be 'failed'
        Should -Invoke Write-Host -ParameterFilter { $Object -match 'Offline export failed.*Export-BenchmarkResults.ps1' } -Times 1
        Mock Invoke-WizardCommand { 5 }
        Mock Complete-WizardBenchmarkExport { @{ status = 'exported' } }
        Invoke-WizardBenchmark $Options | Should -Be 5
        Mock Complete-WizardBenchmarkExport { @{ status = 'failed' } }
        Invoke-WizardBenchmark $Options | Should -Be 5
        Mock Invoke-WizardCommand { 0 }
        Invoke-WizardBenchmark $Options | Should -Be 1
        Mock Invoke-WizardCommand { throw 'child launch failed' }
        { Invoke-WizardBenchmark $Options } | Should -Throw '*child launch failed*'
        Should -Invoke Complete-WizardBenchmarkExport -Times 4 -Exactly
    }
}

Describe 'Wizard decisions and guards' -Tag 'Unit' {
    It 'recommends Establish without a control and Series with a supplied control' {
        Mock Read-WizardChoice { $Default }
        Get-WizardMode | Should -Be Establish
        Get-WizardMode -HasBaseline | Should -Be Series
    }
    It 'does not interpret blank confirmation as consent' {
        Mock Read-Host { '' }
        Confirm-WizardAction 'Install?' | Should -BeFalse
    }
    It 'accepts confirmation <ConfirmationInput> as <ExpectedConsent>' -ForEach @(
        @{ ConfirmationInput = 'yes'; ExpectedConsent = $true },
        @{ ConfirmationInput = 'YES'; ExpectedConsent = $true },
        @{ ConfirmationInput = 'Yes'; ExpectedConsent = $true },
        @{ ConfirmationInput = 'y'; ExpectedConsent = $true },
        @{ ConfirmationInput = ' Y '; ExpectedConsent = $true },
        @{ ConfirmationInput = 'no'; ExpectedConsent = $false },
        @{ ConfirmationInput = 'NO'; ExpectedConsent = $false },
        @{ ConfirmationInput = 'No'; ExpectedConsent = $false },
        @{ ConfirmationInput = 'n'; ExpectedConsent = $false },
        @{ ConfirmationInput = ' N '; ExpectedConsent = $false }
    ) {
        Mock Read-Host { $ConfirmationInput }
        Confirm-WizardAction 'Continue?' | Should -Be $ExpectedConsent
        Should -Invoke Read-Host -Times 1 -Exactly
    }
    It 'reprompts for typos instead of treating them as a decline or consent' {
        $script:ConfirmationAnswers = [Collections.Generic.Queue[string]]::new()
        foreach ($Answer in @('maybe', 'yse', 'YeS')) { $script:ConfirmationAnswers.Enqueue($Answer) }
        Mock Read-Host { $script:ConfirmationAnswers.Dequeue() }
        Confirm-WizardAction 'Continue?' | Should -BeTrue
        Should -Invoke Read-Host -Times 3 -Exactly
    }
    It 'keeps reprompting after repeated invalid text and preserves an explicit no' {
        $script:ConfirmationAnswers = [Collections.Generic.Queue[string]]::new()
        foreach ($Answer in @('yes please', 'true', '1', 'yess', 'No')) { $script:ConfirmationAnswers.Enqueue($Answer) }
        Mock Read-Host { $script:ConfirmationAnswers.Dequeue() }
        Confirm-WizardAction 'Spend credits?' | Should -BeFalse
        Should -Invoke Read-Host -Times 5 -Exactly
    }
    It 'allows cancellation after an invalid answer' {
        $script:ConfirmationAnswers = [Collections.Generic.Queue[string]]::new()
        foreach ($Answer in @('typo', 'q')) { $script:ConfirmationAnswers.Enqueue($Answer) }
        Mock Read-Host { $script:ConfirmationAnswers.Dequeue() }
        { Confirm-WizardAction 'Continue?' } | Should -Throw '*cancelled*'
    }
    It 'cancels explicitly before work is launched' {
        Mock Read-Host { 'q' }
        { Confirm-WizardAction 'Install?' } | Should -Throw '*cancelled*'
    }
    It 'rejects invalid credits <InvalidText>' -ForEach @(
        @{ InvalidText = 'NaN' }, @{ InvalidText = 'Infinity' },
        @{ InvalidText = '0' }, @{ InvalidText = '-2' }, @{ InvalidText = 'nonsense' }
    ) {
        Mock Read-WizardText { $InvalidText }
        { Read-WizardCreditLimit 'Credits' 100 } | Should -Throw '*finite positive*'
    }
    It 'accepts a finite decimal credit ceiling' {
        Mock Read-WizardText { '12.5' }
        Read-WizardCreditLimit 'Credits' 100 | Should -Be 12.5
    }
    It 'refuses scratch/source overlap and filesystem roots' {
        $Source = Join-Path $TestDrive 'source'; New-Item -ItemType Directory -Path $Source | Out-Null
        { Assert-WizardScratchPath $Source $Source } | Should -Throw
        { Assert-WizardScratchPath (Join-Path $Source 'scratch') $Source } | Should -Throw
        { Assert-WizardScratchPath $TestDrive $Source } | Should -Throw
        { Assert-WizardScratchPath ([IO.Path]::GetPathRoot($Source)) $Source } | Should -Throw
        Assert-WizardScratchPath (Join-Path $TestDrive 'scratch') $Source | Should -Be (Join-Path $TestDrive 'scratch')
    }
}

Describe 'Wizard remembered defaults' -Tag 'Unit' {
    BeforeEach {
        $script:MemorySource = Join-Path $TestDrive 'memory-source'
        $script:MemoryConfig = New-WizardTestConfig
        $script:MemoryConfig.WorkRoot = Join-Path $TestDrive 'memory-work'
        $script:MemoryConfig.BaselineSourceRoot = Join-Path $TestDrive 'memory-baseline'
        $script:MemoryConfig.CandidateSourceRoot = Join-Path $TestDrive 'memory-candidate'
        $script:MemoryConfig.Model = 'remembered-model'
        $script:MemoryConfig.PerRunCredits = 1000.0
        $script:MemoryConfig.TotalCredits = 7500.0
        $script:MemoryConfig.ParallelTrials = $true
        foreach ($Source in @($script:MemorySource, $script:MemoryConfig.BaselineSourceRoot, $script:MemoryConfig.CandidateSourceRoot)) {
            New-Item -ItemType Directory -Path (Join-Path $Source 'squad-src'), (Join-Path $Source '.git') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $Source 'apm.yml') -Value 'name: fixture'
        }
        Mock Read-WizardText { $Default }
        Mock Read-WizardChoice { $Default }
    }
    It 'uses remembered answers as defaults while creating fresh run evidence' {
        $script:MemoryConfig.Token = 'not-a-real-credential'
        Save-WizardDefaults -Config $script:MemoryConfig
        $Config = Get-WizardConfiguration -Source $script:MemorySource
        foreach ($Key in @('Mode', 'WorkRoot', 'BaselineSourceRoot', 'CandidateSourceRoot', 'Model', 'PerRunCredits', 'TotalCredits', 'ParallelTrials')) {
            $Config[$Key] | Should -Be $script:MemoryConfig[$Key]
        }
        $Config.RunRoot | Should -Not -Be $script:MemoryConfig.RunRoot
        $Saved = Get-Content -LiteralPath (Get-WizardDefaultsPath) -Raw
        $Saved | Should -Not -Match 'Token|not-a-real-credential|RunRoot|InstallRoot'
        Should -Invoke Read-WizardChoice -Times 1 -Exactly -ParameterFilter { $Question -eq 'What should run?' -and $Default -eq '3' }
        Should -Invoke Read-WizardChoice -Times 1 -Exactly -ParameterFilter { $Question -eq 'Execution' -and $Default -eq '2' }
    }
    It 'honors explicit work paths and adjusts total defaults to changed reservations' {
        $script:MemoryConfig.Mode = 'Establish'
        $script:MemoryConfig.TotalCredits = 3000.0
        Save-WizardDefaults -Config $script:MemoryConfig
        Mock Read-WizardText { if ($Question -eq 'Maximum AI credits per complete run') { '2000' } else { $Default } }
        Mock Read-WizardChoice { if ($Question -eq 'What should run?') { '3' } else { $Default } }
        $Override = Join-Path $TestDrive 'explicit-work'
        $Config = Get-WizardConfiguration -Source $script:MemorySource -Scratch $Override -ParallelTrials
        $Config.WorkRoot | Should -Be $Override
        $Config.TotalCredits | Should -Be 12000
        $Config.ParallelTrials | Should -BeTrue
        Should -Invoke Read-WizardChoice -Times 0 -Exactly -ParameterFilter { $Question -eq 'Execution' }
    }
    It 'preserves live answers in Offline mode and never treats remembered authorization as consent' {
        Save-WizardDefaults -Config $script:MemoryConfig -SpendingAuthorized $true
        Mock Read-WizardChoice { '4' }
        $Config = Get-WizardConfiguration -Source $script:MemorySource
        $Config.Mode | Should -Be Offline
        $Saved = Read-WizardDefaults
        $Saved.Model | Should -Be 'remembered-model'
        $Saved.PerRunCredits | Should -Be 1000
        $Saved.ParallelTrials | Should -BeTrue
        $Saved.SpendingAuthorization.approved | Should -BeTrue
        Mock Read-Host { '' }
        Confirm-WizardAction 'Spend credits?' | Should -BeFalse
    }
    It 'remembers an explicit none control choice instead of rediscovering older controls' {
        $script:MemoryConfig.Mode = 'Series'
        $script:MemoryConfig.ParallelTrials = $false
        Save-WizardDefaults -Config $script:MemoryConfig
        $Control = Join-Path $script:MemoryConfig.WorkRoot 'run-old/control/out/control-series.json'
        New-Item -ItemType Directory -Path (Split-Path $Control -Parent) -Force | Out-Null
        @{ schemaVersion = 'efficiency-control-v1'; runs = @(@{}, @{}, @{}) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Control
        $Config = Get-WizardConfiguration -Source $script:MemorySource
        $Config.BaselineEvidencePath | Should -Be ''
        $Config.ParallelTrials | Should -BeFalse
        $Saved = Read-WizardDefaults
        $Saved.Mode = 'Offline'
        Save-WizardDefaults -Config @{ Mode = 'Offline'; WorkRoot = $Config.WorkRoot } -Previous $Saved
        $Explicit = Get-WizardConfiguration -Source $script:MemorySource -SavedControl $Control
        $Explicit.Mode | Should -Be Series
        $Explicit.BaselineEvidencePath | Should -Be $Control
    }
    It 'leaves memory unchanged for cancelled or invalid questionnaires' {
        Save-WizardDefaults -Config $script:MemoryConfig
        $Before = (Get-FileHash -LiteralPath (Get-WizardDefaultsPath)).Hash
        Mock Read-WizardText {
            if ($Question -like 'Coordinator*') { throw [OperationCanceledException]::new('Wizard cancelled.') }
            $Default
        }
        { Get-WizardConfiguration -Source $script:MemorySource } | Should -Throw '*cancelled*'
        (Get-FileHash -LiteralPath (Get-WizardDefaultsPath)).Hash | Should -Be $Before
        Mock Read-WizardText { if ($Question -eq 'Maximum AI credits per complete run') { 'NaN' } else { $Default } }
        { Get-WizardConfiguration -Source $script:MemorySource } | Should -Throw '*finite positive*'
        (Get-FileHash -LiteralPath (Get-WizardDefaultsPath)).Hash | Should -Be $Before
    }
    It 'retains completed answers when a later prerequisite fails' {
        Save-WizardDefaults -Config $script:MemoryConfig
        Mock Read-WizardText { if ($Question -like 'Coordinator*') { 'retry-model' } else { $Default } }
        Mock Install-WizardPrerequisite { throw 'Fixture prerequisite failure' }
        Mock Confirm-WizardAction { throw 'No authorization should be requested yet' }
        $Result = Invoke-EfficiencyWizard -Source $script:MemorySource
        $Result.failedStage | Should -Be 'Prerequisite installation'
        (Read-WizardDefaults).Model | Should -Be 'retry-model'
        Should -Invoke Confirm-WizardAction -Times 0
    }
    It 'rejects invalid saved data with reset guidance: <Case>' -ForEach @(
        @{ Case = 'syntax'; Json = '{invalid-json' },
        @{ Case = 'version'; Json = '{"schemaVersion":"unknown"}' },
        @{ Case = 'unexpected consent'; Json = '{"schemaVersion":"efficiency-wizard-defaults-v1","Live":true}' },
        @{ Case = 'credit type'; Json = '{"schemaVersion":"efficiency-wizard-defaults-v1","PerRunCredits":"1000"}' },
        @{ Case = 'credit value'; Json = '{"schemaVersion":"efficiency-wizard-defaults-v1","PerRunCredits":0}' },
        @{ Case = 'parallel type'; Json = '{"schemaVersion":"efficiency-wizard-defaults-v1","ParallelTrials":"yes"}' },
        @{ Case = 'authorization type'; Json = '{"schemaVersion":"efficiency-wizard-defaults-v1","SpendingAuthorization":true}' }
    ) {
        Set-Content -LiteralPath (Get-WizardDefaultsPath) -Value $Json
        { Read-WizardDefaults } | Should -Throw '*Remove this file to reset*'
    }
    It 'surfaces write failures without replacing previous memory' {
        Save-WizardDefaults -Config $script:MemoryConfig
        $Before = (Get-FileHash -LiteralPath (Get-WizardDefaultsPath)).Hash
        Mock Set-Content { throw [IO.IOException]::new('Fixture write failure') } -ParameterFilter { $LiteralPath -like '*wizard-defaults.json.*.tmp' }
        { Save-WizardDefaults -Config $script:MemoryConfig } | Should -Throw '*write failure*'
        (Get-FileHash -LiteralPath (Get-WizardDefaultsPath)).Hash | Should -Be $Before
    }
}

Describe 'Wizard unattended plan' -Tag 'Unit' {
    It 'monitors every scheduled trial separately for <Case> runs' -ForEach @(
        @{ Case = 'parallel baseline'; Mode = 'Establish'; Saved = $false; Count = 3; First = 'baseline-1' },
        @{ Case = 'parallel candidates'; Mode = 'Series'; Saved = $true; Count = 3; First = 'candidate-1' },
        @{ Case = 'fresh paired'; Mode = 'Series'; Saved = $false; Count = 6; First = 'baseline-1' }
    ) {
        $Options = @{ Mode = $Mode; TrialRoot = Join-Path $TestDrive 'progress-series' }
        if ($Saved) { $Options.BaselineEvidencePath = 'controls.json' }
        Mock Invoke-WizardCommand { 0 }
        Mock Complete-WizardBenchmarkExport { @{ status = 'exported' } }
        Invoke-WizardBenchmark $Options | Should -Be 0
        Should -Invoke Invoke-WizardCommand -Times 1 -Exactly -ParameterFilter {
            $ProgressPaths.Count -eq $Count -and
            $ProgressPaths.Contains($First) -and
            $ProgressPaths[$First] -eq (Join-Path $Options.TrialRoot "trials/$First/out/progress.json")
        }
    }
    It 'preserves output and exit codes while observing a real child command' {
        Push-Location $TestDrive
        try {
            $Progress = Join-Path $TestDrive 'command-progress.json'
            $Code = Invoke-WizardCommand -Command (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', '"retained fixture output"; exit 7') -ProgressPaths @{ 'baseline-1' = $Progress } -InformationVariable ProgressMessages
            $Code | Should -Be 7
            $Logs = @(Get-ChildItem -LiteralPath $TestDrive -Filter 'wizard-stage-*.log')
            $Logs.Count | Should -Be 1
            Get-Content $Logs[0].FullName | Should -Be 'retained fixture output'
            @($ProgressMessages | Where-Object { $_.MessageData.ToString() -like 'Progress*baseline-1: 0%*' }).Count | Should -Be 2
        }
        finally { Pop-Location }
    }
    It 'honors command-line parallel selection without repeating the scheduling question' {
        $Source = Join-Path $TestDrive 'cli-source'; $Scratch = Join-Path $TestDrive 'cli-scratch'
        New-Item -ItemType Directory -Path (Join-Path $Source 'squad-src'), (Join-Path $Source '.git') -Force | Out-Null
        Set-Content (Join-Path $Source 'apm.yml') 'name: fixture'
        Mock Get-WizardMode { 'Establish' }
        Mock Read-WizardText { $Default }
        Mock Read-WizardCreditLimit { 100 }
        Mock Read-WizardChoice { throw 'Unexpected scheduling question' }
        Mock New-WizardRunPlan {}
        $Config = Get-WizardConfiguration -Source $Source -Scratch $Scratch -ParallelTrials
        $Config.ParallelTrials | Should -BeTrue
        Should -Invoke Read-WizardChoice -Times 0
    }
    It 'keeps serial default and propagates opt-in concurrency to both dependent Complete arms' {
        $Config = New-WizardTestConfig
        $Serial = New-WizardRunPlan $Config
        $Serial[1].arguments.ContainsKey('ParallelTrials') | Should -BeFalse
        $Config.ParallelTrials = $true
        $Parallel = New-WizardRunPlan $Config
        $Parallel[1].arguments.ParallelTrials | Should -BeTrue
        $Parallel[2].arguments.ParallelTrials | Should -BeTrue
        $Parallel[2].arguments.BaselineEvidencePath | Should -Be (Join-Path $TestDrive 'control/out/control-series.json')
        $Parallel[1].arguments.MaxSeriesCredits + $Parallel[2].arguments.MaxSeriesCredits | Should -Be 360
        $Config.Mode = 'Series'
        { New-WizardRunPlan $Config } | Should -Throw '*six fresh*'
    }
    It 'runs Complete as offline checks, three controls, then three saved-control candidates' {
        $Steps = New-WizardRunPlan (New-WizardTestConfig)
        $Steps.Count | Should -Be 3
        $Steps[1].arguments.Mode | Should -Be Establish
        $Steps[2].arguments.Mode | Should -Be Series
        $Steps[1].arguments.ObservationOnly | Should -BeTrue
        $Steps[2].arguments.ObservationOnly | Should -BeTrue
        $Steps[2].arguments.BaselineEvidencePath | Should -Be (Join-Path $TestDrive 'control/out/control-series.json')
        $Steps[1].arguments.MaxSeriesCredits + $Steps[2].arguments.MaxSeriesCredits | Should -Be 360
    }
    It 'requires the full combined reservation before starting Complete' {
        $Config = New-WizardTestConfig; $Config.TotalCredits = 359
        { New-WizardRunPlan $Config } | Should -Throw '*reservations*'
    }
    It 'rejects an observational allocation below the native minimum before planning paid work' {
        $Config = New-WizardTestConfig; $Config.PerRunCredits = 59
        { New-WizardRunPlan $Config } | Should -Throw '*at least 60*'
    }
    It 'keeps Offline free of benchmark steps' {
        $Config = New-WizardTestConfig; $Config.Mode = 'Offline'
        $Steps = New-WizardRunPlan $Config
        $Steps.Count | Should -Be 1
        $Steps[0].kind | Should -Be Offline
    }
    It 'executes all selected steps once without promoting or asking questions' {
        $script:Calls = [Collections.Generic.List[string]]::new()
        $Result = Invoke-WizardRunPlan (New-WizardRunPlan (New-WizardTestConfig)) { param($Step) $script:Calls.Add($Step.name); 0 }
        $Result.exitCode | Should -Be 0
        $script:Calls.Count | Should -Be 3
        $Result.acceptedBaselineChanged | Should -BeFalse
    }
    It 'stops before paid work when offline checks fail and explains repair' {
        $script:Calls = 0
        $Result = Invoke-WizardRunPlan (New-WizardRunPlan (New-WizardTestConfig)) { param($Step) $script:Calls++; 1 }
        $script:Calls | Should -Be 1
        $Result.exitCode | Should -Be 2
        $Result.notRun | Should -Be 2
        $Result.repair | Should -Match 'TLS|Pester'
    }
    It 'retains the failed control stage and never starts candidate work' {
        $script:Calls = 0
        $Result = Invoke-WizardRunPlan (New-WizardRunPlan (New-WizardTestConfig)) { param($Step) $script:Calls++; if ($Step.kind -eq 'Offline') { 0 } else { 2 } }
        $script:Calls | Should -Be 2
        $Result.stages.Count | Should -Be 2
        $Result.failedStage | Should -Be 'Establish controls'
        $Result.notRun | Should -Be 1
    }
}

Describe 'Wizard setup boundaries' -Tag 'Unit' {
    BeforeEach { Mock Get-WizardHostPlatform { 'Windows' } }
    It 'renders the existing-install reuse prompt under strict mode and reuses without installation' {
        $Source = Join-Path $TestDrive 'reuse-source'; $Install = Join-Path $TestDrive 'reuse-install'
        New-Item -ItemType Directory -Path $Source, $Install | Out-Null
        Set-Content -LiteralPath (Join-Path $Source 'apm.yml') -Value 'name: fixture'
        Mock Test-WizardInstall { $true }
        Mock Confirm-WizardAction { $true }
        Mock Move-WizardInstallArchive { throw 'A reusable installation must not be archived.' }
        Initialize-WizardInstall -Path $Install -ManagedRoot $TestDrive -Source $Source
        Should -Invoke Confirm-WizardAction -Times 1 -Exactly -ParameterFilter { $Question -ceq "Reuse clean prepared install ${Install}?" }
        Should -Invoke Move-WizardInstallArchive -Times 0
        Test-Path -LiteralPath (Join-Path $Install 'wizard-install.json') | Should -BeFalse
    }
    It 'allows declining reuse without archiving or modifying the existing installation' {
        $Source = Join-Path $TestDrive 'decline-source'; $Install = Join-Path $TestDrive 'decline-install'
        New-Item -ItemType Directory -Path $Source, $Install | Out-Null
        Set-Content -LiteralPath (Join-Path $Source 'apm.yml') -Value 'name: fixture'
        Set-Content -LiteralPath (Join-Path $Install 'preserve.txt') -Value 'keep'
        Mock Test-WizardInstall { $true }
        Mock Confirm-WizardAction { $false }
        Mock Move-WizardInstallArchive { throw 'Declined reuse must not archive anything.' }
        { Initialize-WizardInstall -Path $Install -ManagedRoot $TestDrive -Source $Source } | Should -Throw '*reuse declined*'
        Get-Content -LiteralPath (Join-Path $Install 'preserve.txt') | Should -Be 'keep'
        Should -Invoke Move-WizardInstallArchive -Times 0
    }
    It 'gives Ubuntu installation guidance rather than attempting WinGet on Unix' {
        Mock Get-WizardHostPlatform { 'Unix' }
        Mock Get-Command { $null }
        Mock Confirm-WizardAction { throw 'Unexpected install consent' }
        Mock Invoke-WizardCommand { throw 'Unexpected installer' }
        { Install-WizardTool gh GitHub.cli } | Should -Throw '*Ubuntu/non-Windows*'
        Should -Invoke Invoke-WizardCommand -Times 0
    }
    It 'does not install or prompt when a command is already present' {
        Mock Get-Command { @{ Source = 'existing' } }
        Mock Confirm-WizardAction { throw 'Unexpected question' }
        Mock Invoke-WizardCommand { throw 'Unexpected install' }
        Install-WizardTool git Git.Git
        Should -Invoke Invoke-WizardCommand -Times 0
    }
    It 'does not install without consent' {
        Mock Get-Command { $null }
        Mock Confirm-WizardAction { $false }
        Mock Invoke-WizardCommand { throw 'Unexpected install' }
        { Install-WizardTool git Git.Git } | Should -Throw '*declined*'
        Should -Invoke Invoke-WizardCommand -Times 0
    }
    It 'rechecks command availability after one successful installer invocation' {
        $script:Installed = $false
        Mock Get-Command { if ($Name -eq 'winget' -or $script:Installed) { @{ Source = 'available' } } }
        Mock Confirm-WizardAction { $true }
        Mock Invoke-WizardCommand { $script:Installed = $true; 0 }
        Mock Update-WizardProcessPath {}
        Install-WizardTool git Git.Git
        Should -Invoke Invoke-WizardCommand -Times 1 -ParameterFilter { $Arguments -contains 'Git.Git' -and $Arguments -contains 'user' }
        Should -Invoke Update-WizardProcessPath -Times 1
    }
    It 'stops after an installer failure instead of retrying or elevating' {
        Mock Get-Command { if ($Name -eq 'winget') { @{ Source = 'winget' } } }
        Mock Confirm-WizardAction { $true }
        Mock Invoke-WizardCommand { 5 }
        { Install-WizardTool git Git.Git } | Should -Throw '*does not elevate or retry*'
        Should -Invoke Invoke-WizardCommand -Times 1
    }
    It 'delegates GitHub and Copilot OAuth to native CLIs without retrieving a token' {
        $script:Authenticated = $false
        Mock Test-Path { $false } -ParameterFilter { $Path -like 'Env:*' }
        Mock Confirm-WizardAction { $true }
        Mock Read-WizardChoice { '1' }
        Mock Invoke-WizardCommand {
            if ($Command -eq 'gh' -and $Arguments -contains 'status' -and -not $script:Authenticated) { return 1 }
            if ($Command -eq 'gh' -and $Arguments -contains 'login') { $script:Authenticated = $true }
            0
        }
        Connect-WizardGitHub
        Should -Invoke Invoke-WizardCommand -Times 1 -ParameterFilter { $Command -eq 'copilot' -and $Arguments[0] -eq 'login' }
        Should -Invoke Invoke-WizardCommand -Times 0 -ParameterFilter { $Arguments -contains 'token' -or $Arguments -contains '--scopes' }
    }
    It 'refuses to archive a source directory or unowned location' {
        $Source = Join-Path $TestDrive 'source'; $Managed = Join-Path $TestDrive 'managed'
        Mock Confirm-WizardAction { throw 'No consent should be requested for unsafe paths' }
        { Move-WizardInstallArchive $Source $Managed $Source } | Should -Throw
        { Move-WizardInstallArchive (Join-Path $TestDrive 'outside') $Managed $Source } | Should -Throw '*managed install*'
    }
    It 'archives stale managed state without deleting its contents' {
        $Source = Join-Path $TestDrive 'src'; $Managed = Join-Path $TestDrive 'managed'; $Install = Join-Path $Managed 'install'
        New-Item -ItemType Directory -Path $Install -Force | Out-Null
        Set-Content (Join-Path $Install 'preserve.txt') 'evidence'
        Mock Confirm-WizardAction { $true }
        $Archive = Move-WizardInstallArchive $Install $Managed $Source
        Test-Path $Install | Should -BeFalse
        Get-Content (Join-Path $Archive 'preserve.txt') | Should -Be 'evidence'
    }
}

Describe 'Wizard complete coordination' -Tag 'Unit' {
    BeforeEach {
        $script:WizardConfig = New-WizardTestConfig
        $script:WizardConfig.WorkRoot = Join-Path $TestDrive 'wizard-work'
        $script:WizardConfig.RunRoot = Join-Path $script:WizardConfig.WorkRoot ([guid]::NewGuid().ToString())
        $script:WizardCalls = [Collections.Generic.List[string]]::new()
        Mock Get-WizardConfiguration { $script:WizardConfig }
        Mock Install-WizardPrerequisite { 'mock-pester.psd1' }
        Mock Connect-WizardGitHub {}
        Mock Initialize-WizardInstall {}
        Mock Test-WizardCompatibility {}
        Mock Confirm-WizardAction { $true }
        Mock Invoke-WizardOfflineTest { $script:WizardCalls.Add('Offline'); 0 }
        Mock Invoke-WizardBenchmark { $script:WizardCalls.Add($Options.Mode); 0 }
        Mock Read-WizardText { throw 'Unexpected interactive input during execution' }
    }
    It 'runs Complete end to end and writes the result without invoking a model' {
        $Result = Invoke-EfficiencyWizard -Source 'source'
        $Result.exitCode | Should -Be 0
        $script:WizardCalls -join ',' | Should -Be 'Offline,Establish,Series'
        $Saved = Get-Content (Join-Path $script:WizardConfig.RunRoot 'wizard-result.json') -Raw | ConvertFrom-Json
        $Saved.outcome | Should -Be passed
        $Saved.acceptedBaselineChanged | Should -BeFalse
        (Read-WizardDefaults).SpendingAuthorization.approved | Should -BeTrue
        Should -Invoke Read-WizardText -Times 0
    }
    It 'stops before any benchmark when the full offline test stage fails' {
        Mock Invoke-WizardOfflineTest { 1 }
        $Result = Invoke-EfficiencyWizard -Source 'source'
        $Result.exitCode | Should -Be 2
        $Result.failedStage | Should -Be 'Offline self-tests'
        Should -Invoke Invoke-WizardBenchmark -Times 0
        Test-Path (Join-Path $script:WizardConfig.RunRoot 'wizard-result.json') | Should -BeTrue
    }
    It 'does not launch on declined isolation or spending consent' {
        Save-WizardDefaults -Config $script:WizardConfig -SpendingAuthorized $true
        Mock Confirm-WizardAction { $Question -notlike '*I confirm*' }
        $Result = Invoke-EfficiencyWizard -Source 'source'
        $Result.exitCode | Should -Be 3
        Should -Invoke Invoke-WizardOfflineTest -Times 0
        Should -Invoke Invoke-WizardBenchmark -Times 0
        Should -Invoke Confirm-WizardAction -Times 1 -Exactly -ParameterFilter { $Question -like '*I confirm*' }
        (Read-WizardDefaults).SpendingAuthorization.approved | Should -BeFalse
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like 'Previous spending authorization*yes*' }
    }
    It 'does not present previous authorization as matching changed credit ceilings' {
        Save-WizardDefaults -Config $script:WizardConfig -SpendingAuthorized $true
        $script:WizardConfig.PerRunCredits = 120.0
        $script:WizardConfig.TotalCredits = 720.0
        Mock Confirm-WizardAction { $Question -notlike '*I confirm*' }
        $Result = Invoke-EfficiencyWizard -Source 'source'
        $Result.exitCode | Should -Be 3
        Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter { $Object -like 'Previous spending authorization*' }
        Should -Invoke Invoke-WizardBenchmark -Times 0
    }
    It 'does not authenticate or prepare packages in Offline mode' {
        $script:WizardConfig.Mode = 'Offline'
        $Result = Invoke-EfficiencyWizard -Source 'source'
        $Result.exitCode | Should -Be 0
        Should -Invoke Connect-WizardGitHub -Times 0
        Should -Invoke Initialize-WizardInstall -Times 0
        Should -Invoke Invoke-WizardBenchmark -Times 0
    }
}

Describe 'Ubuntu bash wizard starter' -Tag 'Unit' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1') -Force
        $script:WizardBash = if ($IsWindows) {
            @('C:/Program Files/Git/bin/bash.exe', 'C:/Program Files/Git/usr/bin/bash.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        }
        else { (Get-Command bash -ErrorAction SilentlyContinue).Source }
        $script:ShellLauncher = (Join-Path $PSScriptRoot 'start-efficiency-wizard.sh').Replace('\', '/')
        function Invoke-TestBashLauncher {
            param([int]$CheckStatus, [int]$WizardStatus, [switch]$Missing)
            $Directory = Join-Path $TestDrive ([guid]::NewGuid().ToString()); New-Item -ItemType Directory -Path $Directory | Out-Null
            $Fake = Join-Path $Directory 'pwsh'; $Log = Join-Path $Directory 'arguments.txt'
            if (-not $Missing) {
                @'
#!/bin/bash
for argument in "$@"; do
  if [[ "$argument" == '-Command' ]]; then exit "${CHECK_STATUS:-0}"; fi
done
printf '%s\n' "$@" > "$ARG_LOG"
exit "${WIZARD_STATUS:-0}"
'@.Replace("`r", '') | Set-Content -LiteralPath $Fake -Encoding utf8NoBOM -NoNewline
                & $script:WizardBash -c 'chmod +x "$1"' test ($Fake.Replace('\', '/'))
            }
                        $Command = @'
set -euo pipefail
test_bin="$1"; log_path="$4"; launcher="$5"; bash_path="$BASH"
if command -v cygpath >/dev/null 2>&1; then
    test_bin="$(cygpath -u "$test_bin")"
    log_path="$(cygpath -u "$log_path")"
    launcher="$(cygpath -u "$launcher")"
fi
if [[ "$6" == 1 ]]; then
    export PATH="$test_bin"
else
    export PATH="$test_bin:/usr/bin:/bin"
    [[ -x "$test_bin/pwsh" ]] || exit 90
    [[ "$(command -v pwsh)" == "$test_bin/pwsh" ]] || exit 91
fi
export CHECK_STATUS="$2" WIZARD_STATUS="$3" ARG_LOG="$log_path"
exec "$bash_path" "$launcher" "${@:7}"
'@
                        $OutputPath = Join-Path $Directory 'output.txt'
                        $Process = Invoke-EfficiencyProcess -FilePath $script:WizardBash -Arguments @('-c', $Command.Replace("`r", ''), 'test', $Directory.Replace('\', '/'), [string]$CheckStatus, [string]$WizardStatus, $Log.Replace('\', '/'), $script:ShellLauncher, $(if ($Missing) { '1' } else { '0' }), '-ParallelTrials', '-WorkRoot', '/tmp/work with spaces') -WorkingDirectory $TestDrive -OutputPath $OutputPath -TimeoutSeconds 10 -InputText ''
                        $Logged = @(); if (Test-Path -LiteralPath $Log) { $Logged = @(Get-Content -LiteralPath $Log) }
                        @{ code = $Process.exitCode; output = ((Get-Content -LiteralPath $OutputPath -Raw) + (Get-Content -LiteralPath ($OutputPath + '.stderr') -Raw)); arguments = $Logged }
        }
    }
    It 'has valid bash syntax' {
        if (-not $script:WizardBash) { Set-ItResult -Skipped -Because 'bash unavailable'; return }
        & $script:WizardBash -n $script:ShellLauncher
        $LASTEXITCODE | Should -Be 0
    }
    It 'proposes Ubuntu installation without installing when pwsh is missing' {
        if (-not $script:WizardBash) { Set-ItResult -Skipped -Because 'bash unavailable'; return }
        $Result = Invoke-TestBashLauncher -Missing -CheckStatus 0 -WizardStatus 0
        $Result.code | Should -Be 127 -Because $Result.output
        $Result.output | Should -Match 'packages.microsoft.com/config/ubuntu'
        $Result.output | Should -Match 'No installation has been performed'
        $Result.arguments.Count | Should -Be 0
    }
    It 'refuses an old or failing PowerShell before launching the wizard' {
        if (-not $script:WizardBash) { Set-ItResult -Skipped -Because 'bash unavailable'; return }
        $Result = Invoke-TestBashLauncher -CheckStatus 1 -WizardStatus 0
        $Result.code | Should -Be 2
        $Result.output | Should -Match 'too old, a preview, or could not run'
        $Result.arguments.Count | Should -Be 0
    }
    It 'forwards quoted arguments and preserves the wizard exit status' {
        if (-not $script:WizardBash) { Set-ItResult -Skipped -Because 'bash unavailable'; return }
        $Result = Invoke-TestBashLauncher -CheckStatus 0 -WizardStatus 3
        $Result.code | Should -Be 3 -Because $Result.output
        $Result.arguments[-1] | Should -Be '/tmp/work with spaces'
        $Result.arguments | Should -Contain '-ParallelTrials'
        $Result.arguments | Should -Contain '-File'
    }
}