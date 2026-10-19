#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

BeforeAll {
    . (Join-Path $PSScriptRoot 'Start-EfficiencyWizard.ps1')
    Mock Write-Host {}
    function New-WizardTestConfig {
        @{ Mode = 'Complete'; InstallRoot = 'install'; Model = 'fixed-model'; PerRunCredits = 10.0; TotalCredits = 60.0; RunRoot = $TestDrive; BaselineSourceRoot = 'baseline'; CandidateSourceRoot = 'candidate'; BaselineEvidencePath = '' }
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

Describe 'Wizard unattended plan' -Tag 'Unit' {
    It 'runs Complete as offline checks, three controls, then three saved-control candidates' {
        $Steps = New-WizardRunPlan (New-WizardTestConfig)
        $Steps.Count | Should -Be 3
        $Steps[1].arguments.Mode | Should -Be Establish
        $Steps[2].arguments.Mode | Should -Be Series
        $Steps[1].arguments.ObservationOnly | Should -BeTrue
        $Steps[2].arguments.ObservationOnly | Should -BeTrue
        $Steps[2].arguments.BaselineEvidencePath | Should -Be (Join-Path $TestDrive 'control/out/control-series.json')
        $Steps[1].arguments.MaxSeriesCredits + $Steps[2].arguments.MaxSeriesCredits | Should -Be 60
    }
    It 'requires the full combined reservation before starting Complete' {
        $Config = New-WizardTestConfig; $Config.TotalCredits = 59
        { New-WizardRunPlan $Config } | Should -Throw '*reservations*'
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
        Mock Confirm-WizardAction { $Question -notlike '*I confirm*' }
        $Result = Invoke-EfficiencyWizard -Source 'source'
        $Result.exitCode | Should -Be 3
        Should -Invoke Invoke-WizardOfflineTest -Times 0
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
                        $Process = Invoke-EfficiencyProcess -FilePath $script:WizardBash -Arguments @('-c', $Command.Replace("`r", ''), 'test', $Directory.Replace('\', '/'), [string]$CheckStatus, [string]$WizardStatus, $Log.Replace('\', '/'), $script:ShellLauncher, $(if ($Missing) { '1' } else { '0' }), '-WorkRoot', '/tmp/work with spaces') -WorkingDirectory $TestDrive -OutputPath $OutputPath -TimeoutSeconds 10 -InputText ''
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
        $Result.arguments | Should -Contain '-File'
    }
}