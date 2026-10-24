#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

# Tests wizard defaults, consent, setup, progress and stage coordination.
# AI cost: none; commands are mocked or replaced with local fixture processes.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Start-EfficiencyWizard.ps1')
    Import-Module (Join-Path $PSScriptRoot 'BenchmarkResults.psm1')
    Import-Module (Join-Path $PSScriptRoot '../../lib/SquadInstall.psm1')
    Mock Write-Host {}
    Mock Get-WizardDefaultsPath { Join-Path $TestDrive 'wizard-defaults.json' }
    function New-WizardTestConfig {
        @{ Mode = 'Complete'; SourceRoot = (Join-Path $TestDrive 'source'); WorkRoot = $TestDrive; InstallRoot = 'install'; Model = 'fixed-model'; PerRunCredits = 60.0; TotalCredits = 360.0; RunRoot = (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))); BaselineSourceRoot = 'baseline'; CandidateSourceRoot = 'candidate'; BaselineEvidencePath = ''; ParallelTrials = $false }
    }
    function New-WizardTestSummary {
        @{ collection = 'recorded'; independentChecks = 'passed'; comparison = 'not-evaluable'; recordedTrials = 3; reportPath = 'fixture/report.md'; portableReportPath = 'fixture/portable/campaign-report.md'; exportManifestPath = 'fixture/benchmark-export.json' }
    }
    function New-WizardResultFixture {
        param([string]$Root, [bool]$ChecksPassed = $true)
        [void][IO.Directory]::CreateDirectory((Join-Path $Root 'out'))
        [void][IO.Directory]::CreateDirectory((Join-Path $Root 'portable'))
        @{ schemaVersion = 'efficiency-series-v1'; quality = @{ checksPassed = $ChecksPassed }; regressionVerdict = 'not-evaluable' } |
            ConvertTo-Json | Set-Content (Join-Path $Root 'out/report.json')
        @{ status = 'exported'; recordedTrials = 3; publicationCommand = "& './Export-BenchmarkResults.ps1' -ObservationOnly" } |
            ConvertTo-Json | Set-Content (Join-Path $Root 'out/benchmark-export.json')
        Set-Content (Join-Path $Root 'out/report.md') 'Retained findings'
        Set-Content (Join-Path $Root 'out/control-series.json') '{}'
        $null = Export-BenchmarkScore -SeriesId 'fixture-failure' -OutputDirectory (Join-Path $Root 'portable') -FailureReason 'fixture-unmeasured'
    }
}

Describe 'Wizard source diagnosis and setup repair' -Tag 'Unit' {
    BeforeAll {
        function New-RepairSource {
            $Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory((Join-Path $Root 'squad-src'))
            Set-Content (Join-Path $Root 'squad-src/source.md') 'committed source'
            Set-Content (Join-Path $Root 'squad-src/keep.md') 'unchanged source'
            Set-Content (Join-Path $Root 'apm.yml') 'name: fixture'
            foreach ($Path in @('tests/tier2/live-benchmark/efficiency-scenario.json', 'tests/tier2/live-benchmark/EfficiencyBenchmark.psm1',
                    'tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1', 'tests/lib/SquadInstall.psm1',
                    'tests/tier2/live-benchmark/Test-EfficiencyTask.ps1', 'scripts/Test-SquadScribeOutput.ps1', 'scripts/Build-SquadPlugin.ps1')) {
                $Target = Join-Path $Root $Path
                [void][IO.Directory]::CreateDirectory((Split-Path $Target -Parent))
                Copy-Item -LiteralPath (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) $Path) -Destination $Target
            }
            & git -C $Root init --quiet
            & git -C $Root config user.name Fixture
            & git -C $Root config user.email fixture@example.invalid
            & git -C $Root config commit.gpgsign false
            & git -C $Root config core.hooksPath (Join-Path $Root '.git/hooks')
            & git -C $Root add --all
            & git -C $Root -c user.name=Fixture -c user.email=fixture@example.invalid -c core.hooksPath=/dev/null commit --quiet -m fixture
            if ($LASTEXITCODE -ne 0) { throw 'Fixture commit failed.' }
            $Root
        }
        function Set-RepairHook($Root, $Body) {
            $Hook = Join-Path $Root '.git/hooks/pre-commit'
            [IO.File]::WriteAllText($Hook, "#!/bin/sh`n$Body`n")
            if (-not $IsWindows) { [IO.File]::SetUnixFileMode($Hook, 'UserRead, UserWrite, UserExecute') }
        }
        function Get-RepairIndexState($Root) {
            $Lines = & git -C $Root ls-files --stage --debug
            @($Lines | ForEach-Object {
                if ($_ -match "`t") { $_ }
                elseif ($_ -match 'flags: [0-9a-f]+') { $Matches[0] }
            }) -join "`n"
        }
        function Get-RepairAdmission($Root) {
            Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1')
            $Compatibility = @{ cli = 'GitHub Copilot CLI 1.0.103'; installHash = 'a' * 64 }
            foreach ($Pair in @{
                    scenarioHash = 'tests/tier2/live-benchmark/efficiency-scenario.json'
                    parserHash = 'tests/tier2/live-benchmark/EfficiencyBenchmark.psm1'
                    exerciseHash = 'tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1'
                    preparationHash = 'tests/lib/SquadInstall.psm1'
                    graderHash = 'tests/tier2/live-benchmark/Test-EfficiencyTask.ps1'
                    verifierHash = 'scripts/Test-SquadScribeOutput.ps1'
                    converterHash = 'scripts/Build-SquadPlugin.ps1'
                }.GetEnumerator()) {
                $Compatibility[$Pair.Key] = (Get-FileHash (Join-Path $Root $Pair.Value)).Hash.ToLowerInvariant()
            }
            Get-BenchmarkExecutionIdentity -Repository $Root -Compatibility $Compatibility -SourceHash (Get-EfficiencyTreeHash (Join-Path $Root 'squad-src'))
        }
    }
    It 'names <Change> measured source without changing Git or evidence' -ForEach @(
        @{ Change = 'modified' }, @{ Change = 'deleted' }, @{ Change = 'untracked' }, @{ Change = 'ignored' }
    ) {
        $Root = New-RepairSource
        $Head = & git -C $Root rev-parse HEAD
        $Path = 'squad-src/source.md'
        if ($Change -eq 'modified') { Set-Content (Join-Path $Root $Path) 'working changes' }
        elseif ($Change -eq 'deleted') { Remove-Item (Join-Path $Root $Path) }
        else {
            $Path = 'squad-src/added.md'
            if ($Change -eq 'ignored') { Set-Content (Join-Path $Root '.git/info/exclude') 'added.md' }
            Set-Content (Join-Path $Root $Path) 'new source'
        }
        { Assert-BenchmarkSourceReady -Repository $Root -ProtocolRepository $Root } | Should -Throw "*source: $Path*"
        (& git -C $Root rev-parse HEAD) | Should -Be $Head
    }
    It 'allows unrelated dirt in a compatible checkout' {
        $Root = New-RepairSource
        Set-Content (Join-Path $Root 'notes.txt') 'unrelated'
        { Assert-BenchmarkSourceReady -Repository $Root -ProtocolRepository $Root } | Should -Not -Throw
    }
    It 'compares actual executing protocol bytes rather than only checking checkout cleanliness' {
        $Measured = New-RepairSource; $Executing = New-RepairSource
        Set-Content (Join-Path $Executing 'tests/tier2/live-benchmark/EfficiencyBenchmark.psm1') 'new protocol'
        { Assert-BenchmarkSourceReady -Repository $Measured -ProtocolRepository $Executing } |
            Should -Throw '*protocol: tests/tier2/live-benchmark/EfficiencyBenchmark.psm1*'
        (& git -C $Measured status --porcelain) | Should -BeNullOrEmpty
    }
    It 'really repairs <Change> source and passes formal identity without changing old evidence' -ForEach @(
        @{ Change = 'modified' }, @{ Change = 'deleted' }, @{ Change = 'untracked' }, @{ Change = 'ignored' }, @{ Change = 'local protocol' }
    ) {
        $Root = New-RepairSource
        $Before = & git -C $Root rev-parse HEAD
        $Evidence = Join-Path $TestDrive "retained-$Change.json"; Set-Content $Evidence 'old evidence'
        $Path = Join-Path $Root 'squad-src/source.md'
        switch ($Change) {
            modified { Set-Content $Path 'intended patch' }
            deleted { Remove-Item $Path }
            untracked { Set-Content (Join-Path $Root 'squad-src/new.md') 'new source' }
            ignored {
                Set-Content (Join-Path $Root '.git/info/exclude') 'new.md'
                Set-Content (Join-Path $Root 'squad-src/new.md') 'ignored intended source'
            }
            'local protocol' { Add-Content (Join-Path $Root 'tests/tier2/live-benchmark/EfficiencyBenchmark.psm1') '# local protocol change' }
        }
        $Reason = if ($Change -eq 'local protocol') { '*measured-protocol-mismatch*' } else { '*measured-source-mismatch*' }
        { Get-RepairAdmission $Root } | Should -Throw $Reason
        Mock Confirm-WizardAction { $true }
        Repair-WizardSource -Repository $Root -ProtocolRepository $Root
        { Assert-BenchmarkSourceReady -Repository $Root -ProtocolRepository $Root } | Should -Not -Throw
        $Identity = Get-RepairAdmission $Root
        $Identity.revision | Should -Not -Be $Before
        (Get-BenchmarkSourceHash $Root $Identity.revision) | Should -Be $Identity.sourceHash
        & git -C $Root merge-base --is-ancestor $Identity.revision HEAD
        $LASTEXITCODE | Should -Be 0
        $After = $Identity.revision
        Repair-WizardSource -Repository $Root -ProtocolRepository $Root
        (& git -C $Root rev-parse HEAD) | Should -Be $After
        Test-Path Env:GIT_INDEX_FILE | Should -BeFalse
        Should -Invoke Confirm-WizardAction -Times 1 -Exactly
        Get-Content $Evidence | Should -Be 'old evidence'
    }
    It 'preserves unrelated partial staging and <Extra> index state' -ForEach @(
        @{ Extra = 'ordinary' }, @{ Extra = 'intent-to-add' }
    ) {
        $Root = New-RepairSource
        Set-Content (Join-Path $Root 'notes.md') 'committed notes'
        & git -C $Root add -- notes.md
        & git -C $Root commit --quiet -m notes
        Set-Content (Join-Path $Root 'notes.md') 'staged notes'
        & git -C $Root add -- notes.md
        Set-Content (Join-Path $Root 'notes.md') 'unstaged notes'
        if ($Extra -eq 'intent-to-add') {
            Set-Content (Join-Path $Root 'pending.md') 'user intent'
            & git -C $Root add --intent-to-add -- pending.md
        }
        $BeforeNotes = (& git -C $Root ls-files --stage -- notes.md) -join "`n"
        $BeforeIntent = (& git -C $Root ls-files --stage --debug -- pending.md) -join "`n"
        Set-Content (Join-Path $Root 'squad-src/source.md') 'approved source'
        Set-Content (Join-Path $Root 'squad-src/new.md') 'approved addition'
        Mock Confirm-WizardAction { $true }
        Repair-WizardSource -Repository $Root -ProtocolRepository $Root
        ((& git -C $Root ls-files --stage -- notes.md) -join "`n") | Should -Be $BeforeNotes
        ((& git -C $Root ls-files --stage --debug -- pending.md) -join "`n") | Should -Be $BeforeIntent
        (& git -C $Root show HEAD:notes.md) | Should -Be 'committed notes'
        (& git -C $Root show :notes.md) | Should -Be 'staged notes'
        Get-Content (Join-Path $Root 'notes.md') | Should -Be 'unstaged notes'
        (& git -C $Root show HEAD:squad-src/new.md) | Should -Be 'approved addition'
    }
    It 'leaves source, HEAD and index byte-identical when source commit is declined' {
        $Root = New-RepairSource
        Set-Content (Join-Path $Root 'squad-src/new.md') 'not approved'
        $Before = & git -C $Root rev-parse HEAD
        $Index = (Get-FileHash (Join-Path $Root '.git/index')).Hash
        Mock Confirm-WizardAction { $false }
        { Repair-WizardSource -Repository $Root -ProtocolRepository $Root } | Should -Throw '*declined*'
        (& git -C $Root rev-parse HEAD) | Should -Be $Before
        (Get-FileHash (Join-Path $Root '.git/index')).Hash | Should -Be $Index
        Get-Content (Join-Path $Root 'squad-src/new.md') | Should -Be 'not approved'
    }
    It 'honors a failed hook and removes only repair-owned intent-to-add entries' {
        $Root = New-RepairSource
        Set-Content (Join-Path $Root 'notes.md') 'user staging'
        & git -C $Root add --intent-to-add -- notes.md
        Set-Content (Join-Path $Root 'squad-src/new.md') 'approved new source'
        $Before = & git -C $Root rev-parse HEAD
        $Index = Get-RepairIndexState $Root
        Set-RepairHook $Root 'git add -- squad-src/new.md; exit 1'
        Mock Confirm-WizardAction { $true }
        { Repair-WizardSource -Repository $Root -ProtocolRepository $Root } | Should -Throw '*commit failed*'
        (& git -C $Root rev-parse HEAD) | Should -Be $Before
        (Get-RepairIndexState $Root) | Should -Be $Index
        Get-Content (Join-Path $Root 'squad-src/new.md') | Should -Be 'approved new source'
        Test-Path (Join-Path $Root '.git/index.lock') | Should -BeFalse
        $env:GIT_INDEX_FILE | Should -BeNullOrEmpty
    }
    It 'rejects <Drift> after consent rather than committing newly changed inputs' -ForEach @(
        @{ Drift = 'source drift' }, @{ Drift = 'HEAD drift' }
    ) {
        $Root = New-RepairSource
        Set-Content (Join-Path $Root 'squad-src/source.md') 'reviewed source'
        $Before = & git -C $Root rev-parse HEAD
        Mock Confirm-WizardAction {
            if ($Drift -eq 'source drift') { Set-Content (Join-Path $Root 'squad-src/source.md') 'different bytes' }
            else { & git -C $Root commit --quiet --allow-empty -m intervening }
            $true
        }.GetNewClosure()
        { Repair-WizardSource -Repository $Root -ProtocolRepository $Root } | Should -Throw '*changed after review*'
        if ($Drift -eq 'source drift') { (& git -C $Root rev-parse HEAD) | Should -Be $Before }
        else { (& git -C $Root log -1 --format=%s) | Should -Be 'intervening' }
    }
    It 'rejects byte-changing Git EOL conversion without changing HEAD or index' {
        $Root = New-RepairSource
        Set-Content (Join-Path $Root '.gitattributes') 'squad-src/*.md text eol=lf'
        & git -C $Root add -- .gitattributes
        & git -C $Root commit --quiet -m attributes
        [IO.File]::WriteAllText((Join-Path $Root 'squad-src/source.md'), "new source`r`n")
        $Before = & git -C $Root rev-parse HEAD
        $Index = (Get-FileHash (Join-Path $Root '.git/index')).Hash
        Mock Confirm-WizardAction { throw 'Unexpected consent request' }
        { Repair-WizardSource -Repository $Root -ProtocolRepository $Root } | Should -Throw '*attributes/filter/EOL*'
        (& git -C $Root rev-parse HEAD) | Should -Be $Before
        (Get-FileHash (Join-Path $Root '.git/index')).Hash | Should -Be $Index
    }
    It 'does not claim repair when a normal hook <Effect>' -ForEach @(
        @{ Effect = 'rewrites approved bytes'; Body = "printf 'hook rewrite\n' > squad-src/source.md; git add -- squad-src/source.md" },
        @{ Effect = 'adds an extra committed file'; Body = "printf 'hook extra\n' > hook-added.md; git add -- hook-added.md" },
        @{ Effect = 'rewrites previously clean source'; Body = "printf 'hook rewrite\n' > squad-src/keep.md; git add -- squad-src/keep.md" }
    ) {
        $Root = New-RepairSource
        Set-Content (Join-Path $Root 'squad-src/source.md') 'reviewed source'
        $Before = & git -C $Root rev-parse HEAD
        Set-RepairHook $Root $Body
        Mock Confirm-WizardAction { $true }
        { Repair-WizardSource -Repository $Root -ProtocolRepository $Root } | Should -Throw '*differ from the reviewed inputs*'
        (& git -C $Root rev-parse HEAD) | Should -Not -Be $Before
        Test-Path (Join-Path $Root '.git/index.lock') | Should -BeFalse
    }
    It 'does not overwrite another Git operation index lock' {
        $Root = New-RepairSource
        Set-Content (Join-Path $Root 'squad-src/source.md') 'reviewed source'
        Set-Content (Join-Path $Root '.git/index.lock') 'another operation'
        $Before = & git -C $Root rev-parse HEAD
        Mock Confirm-WizardAction { $true }
        { Repair-WizardSource -Repository $Root -ProtocolRepository $Root } | Should -Throw '*already exists*'
        Get-Content (Join-Path $Root '.git/index.lock') | Should -Be 'another operation'
        (& git -C $Root rev-parse HEAD) | Should -Be $Before
    }
    It 'refuses an incompatible external protocol before commit consent' {
        $Root = New-RepairSource; $Executing = New-RepairSource
        Add-Content (Join-Path $Executing 'tests/tier2/live-benchmark/EfficiencyBenchmark.psm1') '# different executing harness'
        Set-Content (Join-Path $Root 'squad-src/source.md') 'uncommitted source'
        $Before = & git -C $Root rev-parse HEAD
        Mock Confirm-WizardAction { throw 'Unexpected commit consent' }
        { Repair-WizardSource -Repository $Root -ProtocolRepository $Executing } | Should -Throw '*cannot be repaired by a local commit*'
        (& git -C $Root rev-parse HEAD) | Should -Be $Before
    }
    It 'repairs a detached worktree without moving the original branch or its index' {
        $Root = New-RepairSource
        $Worktree = Join-Path $TestDrive 'repair-worktree'
        & git -C $Root worktree add --quiet --detach $Worktree HEAD
        $Before = & git -C $Root rev-parse HEAD
        $Index = (Get-FileHash (Join-Path $Root '.git/index')).Hash
        Set-Content (Join-Path $Worktree 'squad-src/new.md') 'worktree source'
        Mock Confirm-WizardAction { $true }
        Repair-WizardSource -Repository $Worktree -ProtocolRepository $Worktree
        { Assert-BenchmarkSourceReady -Repository $Worktree -ProtocolRepository $Worktree } | Should -Not -Throw
        (& git -C $Root rev-parse HEAD) | Should -Be $Before
        (Get-FileHash (Join-Path $Root '.git/index')).Hash | Should -Be $Index
        Test-Path (Join-Path $Root 'squad-src/new.md') | Should -BeFalse
    }
    It 'repairs the supplied dirty-source pattern and then completes the formal orchestration offline' {
        $Messages = [Collections.Generic.List[string]]::new()
        Mock Write-Host { param($Object) $Messages.Add(($Object -join ' ')) }.GetNewClosure()
        $Root = New-RepairSource; $Work = Join-Path $TestDrive 'actual-recovery'
        [void][IO.Directory]::CreateDirectory($Work)
        Set-Content (Join-Path $Root 'squad-src/source.md') 'intended tracked patch'
        Set-Content (Join-Path $Root 'squad-src/new.md') 'intended untracked script'
        $Config = New-WizardTestConfig
        $Config.Mode = 'Repair'; $Config.SourceRoot = $Root; $Config.BaselineSourceRoot = $Root
        $Config.CandidateSourceRoot = $Root; $Config.WorkRoot = $Work
        $Config.InstallRoot = Join-Path $Work 'install'; $Config.RunRoot = $null
        Mock Get-WizardConfiguration { $Config }.GetNewClosure()
        Mock Confirm-WizardAction { $true }
        Mock Initialize-WizardInstall {}
        Mock Connect-WizardGitHub { throw 'Repair must not login' }
        Mock Install-WizardPrerequisite { throw 'Repair must not provision tests' }
        (Invoke-EfficiencyWizard -Source $Root).outcome | Should -Be 'setup-ready'
        Should -Invoke Connect-WizardGitHub -Times 0
        Should -Invoke Install-WizardPrerequisite -Times 0
        $Config.Mode = 'Establish'; $Config.RunRoot = Join-Path $Work 'formal-run'
        Mock Connect-WizardGitHub {}
        Mock Install-WizardPrerequisite { $TestDrive }
        Mock Test-WizardCompatibility { param($Config) $null = Get-RepairAdmission $Config.BaselineSourceRoot }
        Mock Invoke-WizardOfflineTest { 0 }
        Mock Invoke-WizardBenchmark {
            Assert-BenchmarkSourceReady -Repository $Options.SourceRoot
            New-WizardResultFixture $Options.TrialRoot
            0
        }
        $Result = Invoke-EfficiencyWizard -Source $Root
        $Result.outcome | Should -Be 'completed' -Because ($Messages -join '; ')
        $Result.exitCode | Should -Be 0
        Should -Invoke Invoke-WizardBenchmark -Times 1 -Exactly
    }
    It 'checks exactly the measured roots for <Mode> with saved controls <Saved>' -ForEach @(
        @{ Mode = 'Establish'; Saved = $false; Roots = @('baseline') },
        @{ Mode = 'Series'; Saved = $true; Roots = @('candidate') },
        @{ Mode = 'Series'; Saved = $false; Roots = @('candidate') },
        @{ Mode = 'Complete'; Saved = $false; Roots = @('baseline', 'candidate') },
        @{ Mode = 'Repair'; Saved = $false; Roots = @('baseline') }
    ) {
        $Config = New-WizardTestConfig; $Config.Mode = $Mode
        if ($Saved) { $Config.BaselineEvidencePath = 'controls.json' }
        Mock Assert-BenchmarkSourceReady {}
        Test-WizardSource $Config
        Should -Invoke Assert-BenchmarkSourceReady -Times $Roots.Count -Exactly
        foreach ($Root in $Roots) { Should -Invoke Assert-BenchmarkSourceReady -Times 1 -Exactly -ParameterFilter { $Repository -eq $Root } }
    }
    It 'stops <Mode> before setup or login when a measured arm fails source preflight' -ForEach @(
        @{ Mode = 'Establish' }, @{ Mode = 'Series' }, @{ Mode = 'Complete' }, @{ Mode = 'Repair' }
    ) {
        $Config = New-WizardTestConfig; $Config.Mode = $Mode
        Mock Get-WizardConfiguration { $Config }.GetNewClosure()
        Mock Test-WizardSource { throw 'Formal source check failed: source: squad-src/source.md' }
        Mock Install-WizardPrerequisite { throw 'Unexpected prerequisite work' }
        Mock Connect-WizardGitHub { throw 'Unexpected login' }
        Mock Initialize-WizardInstall { throw 'Unexpected installation' }
        $Result = Invoke-EfficiencyWizard -Source 'fixture'
        $Result.exitCode | Should -Be 1
        $Result.failedStage | Should -Be 'Source preflight'
        Should -Invoke Install-WizardPrerequisite -Times 0
        Should -Invoke Connect-WizardGitHub -Times 0
        Should -Invoke Initialize-WizardInstall -Times 0
    }
    It 'returns from repair without login, tests, collection or spending authorization' {
        $Root = New-RepairSource
        $Work = Join-Path $TestDrive 'repair-work'; [void][IO.Directory]::CreateDirectory($Work)
        $Config = @{ Mode = 'Repair'; SourceRoot = $Root; BaselineSourceRoot = $Root; WorkRoot = $Work; InstallRoot = Join-Path $Work 'install'; RunRoot = $null }
        Mock Get-WizardConfiguration { $Config }.GetNewClosure()
        Mock Test-WizardSource {}
        Mock Initialize-WizardInstall {}
        Mock Connect-WizardGitHub { throw 'Unexpected login' }
        Mock Install-WizardPrerequisite { throw 'Unexpected prerequisites' }
        Mock Invoke-WizardOfflineTest { throw 'Unexpected tests' }
        Mock Invoke-WizardBenchmark { throw 'Unexpected collection' }
        Mock Confirm-WizardAction { throw 'Unexpected authorization' }
        $Result = Invoke-EfficiencyWizard -Source $Root
        $Result.outcome | Should -Be 'setup-ready'
        $Result.exitCode | Should -Be 0
        Should -Invoke Initialize-WizardInstall -Times 1 -Exactly -ParameterFilter { $Repair }
        Test-Path (Join-Path $Work 'wizard-result.json') | Should -BeFalse
    }
    It 'remembers Repair without replacing live defaults or asking for credits or models' {
        $Root = New-RepairSource
        $Work = Join-Path $TestDrive 'repair-defaults'
        $Live = New-WizardTestConfig; $Live.WorkRoot = $Work
        Save-WizardDefaults -Config $Live -SpendingAuthorized $true
        $Before = Read-WizardDefaults
        Mock Get-WizardMode { 'Repair' }
        Mock Read-WizardText { $Default }
        Mock Read-WizardCreditLimit { throw 'Unexpected credits' }
        $Config = Get-WizardConfiguration -Source $Root -Scratch $Work
        $Config.Mode | Should -Be 'Repair'
        $After = Read-WizardDefaults
        $After.Model | Should -Be $Before.Model
        $After.PerRunCredits | Should -Be $Before.PerRunCredits
        $After.SpendingAuthorization.planHash | Should -Be $Before.SpendingAuthorization.planHash
        Should -Invoke Read-WizardText -Times 2 -Exactly
    }
    It 'preserves a valid install by default without asking to reuse or prepare it' {
        $Root = New-RepairSource; $Work = Join-Path $TestDrive 'keep-work'; $Install = Join-Path $Work 'install'
        [void][IO.Directory]::CreateDirectory($Install)
        Set-Content (Join-Path $Install 'keep.txt') 'keep'
        Mock Test-WizardInstall { $true }
        Mock Confirm-WizardAction { $false }
        Mock Move-WizardInstallArchive { throw 'Unexpected archive' }
        Initialize-WizardInstall -Path $Install -ManagedRoot $Work -Source $Root -Repair
        Get-Content (Join-Path $Install 'keep.txt') | Should -Be 'keep'
        Should -Invoke Confirm-WizardAction -Times 1 -Exactly -ParameterFilter { $MemoryKey -eq 'RebuildInstall' }
        Should -Invoke Move-WizardInstallArchive -Times 0
    }
    It 'archives <State> installs only after consent, leaving old evidence intact' -ForEach @(
        @{ State = 'stale'; Consent = $true }, @{ State = 'valid'; Consent = $true }, @{ State = 'stale'; Consent = $false }
    ) {
        $Root = New-RepairSource; $Work = Join-Path $TestDrive "rebuild-$State-$Consent"; $Install = Join-Path $Work 'install'
        [void][IO.Directory]::CreateDirectory($Install)
        Set-Content (Join-Path $Install 'keep.txt') 'old install'
        Set-Content (Join-Path $Work 'control-series.json') 'retained evidence'
        if ($State -eq 'stale') { '{"manifestHash":"stale"}' | Set-Content (Join-Path $Install 'wizard-install.json') }
        Mock Test-WizardInstall { $true }
        Mock Confirm-WizardAction { $Consent }.GetNewClosure()
        Mock Import-Module {}
        Mock Install-SquadPackage { [void][IO.Directory]::CreateDirectory($Destination) }
        if ($Consent) {
            Initialize-WizardInstall -Path $Install -ManagedRoot $Work -Source $Root -Repair
            $Archives = @(Get-ChildItem $Work -Directory -Filter 'install-archive-*')
            $Archives.Count | Should -Be 1
            Get-Content (Join-Path $Archives[0].FullName 'keep.txt') | Should -Be 'old install'
            Should -Invoke Install-SquadPackage -Times 1 -Exactly
        }
        else {
            { Initialize-WizardInstall -Path $Install -ManagedRoot $Work -Source $Root -Repair } | Should -Throw '*Archive declined*'
            Get-Content (Join-Path $Install 'keep.txt') | Should -Be 'old install'
            Should -Invoke Install-SquadPackage -Times 0
        }
        Get-Content (Join-Path $Work 'control-series.json') | Should -Be 'retained evidence'
    }
}

Describe 'Wizard local single-candidate diagnostics' -Tag 'Unit' {
    BeforeAll {
        function New-LocalScoreFile {
            $Path = Join-Path $TestDrive "scores-$([guid]::NewGuid().ToString('N')).json"
            $Names = @('businessClarity', 'scopeFidelity', 'acceptanceCriteria', 'traceability', 'risksAndDecisions')
            $Runs = @(foreach ($Pair in 1..3) {
                $Scores = @{}; $Evidence = @{}
                foreach ($Name in $Names) { $Scores[$Name] = 0; $Evidence[$Name] = 'synthetic evidence' }
                $Scores[$Names[$Pair - 1]] = 20
                $Hashes = @{ brd = 'a' * 64; prd = 'b' * 64; closingReview = 'c' * 64 }
                @{ metadata = @{ arm = 'baseline'; pair = $Pair; runId = "saved-$Pair"; revision = 'historical'; compatibility = @{ model = 'old'; rubric = 'old' } }
                    judge = @{ valid = $true; documentHashes = $Hashes; response = @{ scores = $Scores; evidence = $Evidence; criticalHighFindings = 0; documentHashes = $Hashes } } }
            })
            @{ schemaVersion = 'efficiency-control-v1'; runs = $Runs } | ConvertTo-Json -Depth 12 | Set-Content $Path
            $Path
        }
        function New-LocalDiagnosticFile($Root, $Recorded, [bool]$JudgeAvailable = $true) {
            [void][IO.Directory]::CreateDirectory((Join-Path $Root 'out'))
            @{ schemaVersion = 'efficiency-local-test-v1'; localDiagnostic = $true
                metadata = @{ compatibility = @{ model = 'new'; rubric = 'new' } }
                collection = @{ recorded = $false }
                diagnostic = @{ executionComplete = $true; independentChecksPassed = $false; judgeAvailable = $JudgeAvailable }
                judge = if ($JudgeAvailable) { $Recorded.runs[0].judge } else { $null }
            } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Root 'out/diagnostic.json')
        }
    }
    It 'runs <LocalMode> with one candidate, fresh consent and no formal export paths' -ForEach @(
        @{ LocalMode = 'OfflineSmoke' }, @{ LocalMode = 'LocalCompare' }
    ) {
        $Config = New-WizardTestConfig; $Config.Mode = $LocalMode
        $Config.WorkRoot = Join-Path $TestDrive 'work'; $Config.RunRoot = Join-Path $Config.WorkRoot "local-test-$LocalMode"
        $Config.BaselineEvidencePath = New-LocalScoreFile
        $Config.RecordedScores = Read-WizardRecordedScores $Config.BaselineEvidencePath
        $Steps = New-WizardRunPlan $Config
        $Steps[0].kind | Should -Be OfflineSmoke
        if ($LocalMode -eq 'LocalCompare') {
            $Steps.Count | Should -Be 2
            $Steps[1].arguments.Mode | Should -Be Run
            $Steps[1].arguments.Arm | Should -Be candidate
            $Steps[1].arguments.LocalTest | Should -BeTrue
            $Steps[1].arguments.ContainsKey('MaxSeriesCredits') | Should -BeFalse
        } else { $Steps.Count | Should -Be 1 }
        Mock Get-WizardConfiguration { $Config }.GetNewClosure()
        Mock Get-WizardSmokePrerequisite { 'installed-pester' }
        Mock Install-WizardPrerequisite { 'installed-pester' }
        Mock Connect-WizardGitHub {}
        Mock Initialize-WizardInstall {}
        Mock Confirm-WizardAction { $true }
        Mock Save-WizardDefaults {}
        Mock Invoke-WizardSingleCandidateSmoke { 0 }
        Mock Invoke-WizardLocalCandidate { 0 }
        Mock Get-WizardLocalSummary { @{ executionComplete = $true; independentChecks = 'failed'; judgeAvailable = $false; diagnosticPath = 'local diagnostic'; collection = 'not-recorded'; publication = 'forbidden' } }
        Mock Test-WizardCompatibility { throw 'Formal preflight forbidden' }
        Mock Invoke-WizardOfflineTest { throw 'Full offline suite forbidden' }
        Mock Invoke-WizardBenchmark { throw 'Formal benchmark forbidden' }
        Mock Complete-WizardBenchmarkExport { throw 'Export forbidden' }
        Mock Get-WizardBenchmarkSummary { throw 'Formal summary forbidden' }
        $Result = Invoke-EfficiencyWizard -Source $PSScriptRoot
        $Result.exitCode | Should -Be 0
        $Result.outcome | Should -Be $(if ($LocalMode -eq 'LocalCompare') { 'completed-with-findings' } else { 'passed' })
        Should -Invoke Invoke-WizardSingleCandidateSmoke -Times 1 -Exactly
        Should -Invoke Invoke-WizardLocalCandidate -Times $(if ($LocalMode -eq 'LocalCompare') { 1 } else { 0 }) -Exactly
        Should -Invoke Connect-WizardGitHub -Times $(if ($LocalMode -eq 'LocalCompare') { 1 } else { 0 }) -Exactly
        Should -Invoke Install-WizardPrerequisite -Times $(if ($LocalMode -eq 'LocalCompare') { 1 } else { 0 }) -Exactly
        Should -Invoke Complete-WizardBenchmarkExport -Times 0 -Exactly
        if ($LocalMode -eq 'LocalCompare') {
            Should -Invoke Confirm-WizardAction -Times 1 -Exactly -ParameterFilter { $Question -like '*authorize the displayed bounded spending*' }
        }
    }
    It 'rejects <Damage> historical scores before candidate dispatch' -ForEach @(
        @{ Damage = 'string-score' }, @{ Damage = 'out-of-range' }, @{ Damage = 'wrong-dimension' }, @{ Damage = 'duplicate-pair' }
    ) {
        $Path = New-LocalScoreFile
        $Control = Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable
        switch ($Damage) {
            'string-score' { $Control.runs[0].judge.response.scores.businessClarity = '20' }
            'out-of-range' { $Control.runs[0].judge.response.scores.businessClarity = 21 }
            'wrong-dimension' { $Control.runs[0].judge.response.scores.Remove('businessClarity'); $Control.runs[0].judge.response.scores.extra = 20 }
            'duplicate-pair' { $Control.runs[1].metadata.pair = 1 }
        }
        $Control | ConvertTo-Json -Depth 12 | Set-Content $Path
        Mock Invoke-WizardLocalCandidate { throw 'Must not launch' }
        { Read-WizardRecordedScores $Path } | Should -Throw
        Should -Invoke Invoke-WizardLocalCandidate -Times 0 -Exactly
    }
    It 'uses median totals, accepts historical protocol differences read-only and prints descriptive deltas' {
        $Path = New-LocalScoreFile; $Before = (Get-FileHash $Path).Hash
        $Recorded = Read-WizardRecordedScores $Path
        $Recorded.medians.total | Should -Be 20
        ($Recorded.medians.Values | Select-Object -First 5 | Measure-Object -Sum).Sum | Should -Be 0
        $Root = Join-Path $TestDrive 'local-test-scores'
        New-LocalDiagnosticFile $Root $Recorded
        $Summary = Get-WizardLocalSummary -Options @{ TrialRoot = $Root } -Recorded $Recorded
        $Summary.publication | Should -Be descriptive-only
        $Summary.collection | Should -Be 'recorded-local'
        (Get-FileHash $Path).Hash | Should -Be $Before
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Protocol/model/rubric differences*model*rubric*' } -Times 1
        Should -Invoke Write-Host -ParameterFilter { $Object -eq '| total | 20 | 20 | 0 |' } -Times 1
    }
    It 'shows an unavailable candidate judge as findings rather than zero or a passed quality result' {
        $Recorded = Read-WizardRecordedScores (New-LocalScoreFile)
        $Root = Join-Path $TestDrive 'local-test-unavailable'
        New-LocalDiagnosticFile $Root $Recorded $false
        $Summary = Get-WizardLocalSummary -Options @{ TrialRoot = $Root } -Recorded $Recorded
        $Summary.judgeAvailable | Should -BeFalse
        $Summary.independentChecks | Should -Be failed
        Should -Invoke Write-Host -ParameterFilter { $Object -eq '| total | 20 | unavailable | unavailable |' } -Times 1
    }
    It 'passes one local Run to the child and never invokes export' {
        Mock Invoke-WizardCommand { 0 }
        Mock Complete-WizardBenchmarkExport { throw 'Forbidden' }
        $Config = New-WizardTestConfig; $Config.Mode = 'LocalCompare'
        $Step = (New-WizardRunPlan $Config)[1]
        Invoke-WizardLocalCandidate -Options $Step.arguments | Should -Be 0
        Should -Invoke Invoke-WizardCommand -Times 1 -Exactly -ParameterFilter { $Arguments -contains '-LocalTest' -and $Arguments -contains 'candidate' -and $Arguments -contains 'Run' -and $Arguments -notcontains 'Series' }
        Should -Invoke Complete-WizardBenchmarkExport -Times 0 -Exactly
    }
    It 'fails missing installed <Missing> without installers, Python or login' -ForEach @(
        @{ Missing = 'Git' }, @{ Missing = 'Pester' }
    ) {
        Mock Get-Command { if ($Missing -eq 'Pester') { @{ Source = 'git' } } } -ParameterFilter { $Name -eq 'git' }
        Mock Get-Module { @() } -ParameterFilter { $ListAvailable -and $Name -eq 'Pester' }
        Mock Install-WizardPrerequisite { throw 'No installer' }
        Mock Get-WizardPython { throw 'No Python' }
        Mock Connect-WizardGitHub { throw 'No login' }
        { Get-WizardSmokePrerequisite } | Should -Throw "*$Missing*"
        Should -Invoke Install-WizardPrerequisite -Times 0 -Exactly
        Should -Invoke Get-WizardPython -Times 0 -Exactly
        Should -Invoke Connect-WizardGitHub -Times 0 -Exactly
    }
    It 'remembers local answers without discarding formal parallel defaults and rejects explicit parallel local work' {
        $Config = New-WizardTestConfig; $Config.Mode = 'OfflineSmoke'; $Config.WorkRoot = $TestDrive
        Save-WizardDefaults -Config $Config -Previous @{ ParallelTrials = $true; Model = 'remembered' }
        $Saved = Read-WizardDefaults
        $Saved.Mode | Should -Be OfflineSmoke
        $Saved.ParallelTrials | Should -BeTrue
        $Saved.Model | Should -Be remembered
        $Config.Mode = 'LocalCompare'; $Config.ParallelTrials = $true
        { New-WizardRunPlan $Config } | Should -Throw '*one candidate*'
    }
}

Describe 'Wizard recorded collection outcomes' -Tag 'Unit' {
    BeforeEach {
        $script:SummaryOptions = @{ TrialRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')) }
    }
    It 'links actual retained reports and saved controls without claiming Git publication' {
        New-WizardResultFixture -Root $script:SummaryOptions.TrialRoot
        $Summary = Get-WizardBenchmarkSummary $script:SummaryOptions
        $Summary.collection | Should -Be recorded
        $Summary.recordedTrials | Should -Be 3
        $Summary.independentChecks | Should -Be passed
        $Summary.publication | Should -Be 'local-only'
        $Summary.publicationCommand | Should -Match '-ObservationOnly'
        foreach ($Key in @('reportPath', 'rawReportPath', 'controlEvidencePath', 'portableReportPath', 'exportManifestPath')) {
            Test-Path -LiteralPath $Summary[$Key] -PathType Leaf | Should -BeTrue
        }
    }
    It 'retains failed quality in the serialized wizard result despite successful collection' {
        New-WizardResultFixture -Root $script:SummaryOptions.TrialRoot -ChecksPassed $false
        $Steps = @(@{ name = 'Establish controls'; kind = 'Benchmark'; arguments = $script:SummaryOptions })
        $Result = Invoke-WizardRunPlan -Steps $Steps -Execute { 0 }
        $Saved = $Result | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
        $Saved.exitCode | Should -Be 0
        $Saved.outcome | Should -Be 'completed-with-findings'
        $Saved.stages[0].benchmark.independentChecks | Should -Be failed
        $Saved.stages[0].benchmark.recordedTrials | Should -Be 3
        $Saved.stages[0].benchmark.portableReportPath | Should -Be (Join-Path $script:SummaryOptions.TrialRoot 'portable/report.md')
        $Saved.acceptedBaselineChanged | Should -BeFalse
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Independent checks: failed*' } -Times 1 -Exactly
    }
    It 'fails explicitly on <Damage> evidence after executor exit <ExecutorExit>' -ForEach @(
        @{ Damage = 'missing-report'; ExecutorExit = 0 }
        @{ Damage = 'malformed-report'; ExecutorExit = 0 }
        @{ Damage = 'invalid-report'; ExecutorExit = 0 }
        @{ Damage = 'failed-export'; ExecutorExit = 0 }
        @{ Damage = 'failed-export'; ExecutorExit = 1 }
        @{ Damage = 'failed-export'; ExecutorExit = 2 }
    ) {
        New-WizardResultFixture -Root $script:SummaryOptions.TrialRoot
        switch ($Damage) {
            'missing-report' { Remove-Item -LiteralPath (Join-Path $script:SummaryOptions.TrialRoot 'out/report.json') }
            'malformed-report' { Set-Content (Join-Path $script:SummaryOptions.TrialRoot 'out/report.json') '{"PRIVATE":"unfinished"' }
            'invalid-report' { Set-Content (Join-Path $script:SummaryOptions.TrialRoot 'out/report.json') '{"schemaVersion":"efficiency-series-v1","quality":{"checksPassed":true}}' }
            'failed-export' { Set-Content (Join-Path $script:SummaryOptions.TrialRoot 'out/benchmark-export.json') '{"status":"failed","recordedTrials":3}' }
        }
        { Get-WizardBenchmarkSummary $script:SummaryOptions } | Should -Throw '*Benchmark result evidence*offline*without paid retries*'
        Mock Write-Warning {}
        $Result = Invoke-WizardRunPlan -Steps @(@{ name = 'Establish controls'; kind = 'Benchmark'; arguments = $script:SummaryOptions }) -Execute { $ExecutorExit }.GetNewClosure()
        $Result.exitCode | Should -Be $(if ($ExecutorExit -eq 2) { 2 } else { 1 })
        $Result.outcome | Should -Be failed
        $Result.repair | Should -Match 'offline, without paid retries'
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*result evidence could not be read*' -and $Message -notlike '*PRIVATE*' }
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
    It 'retains a candidate score before optional <Comparison> and preserves its exit' -ForEach @(
        @{ Comparison = 'regression'; Evaluable = $true; Eligible = $false; Fault = 'none'; ChildCode = 0; Code = 2 },
        @{ Comparison = 'unavailable'; Evaluable = $false; Eligible = $false; Fault = 'none'; ChildCode = 0; Code = 0 },
        @{ Comparison = 'regression-write-failure'; Evaluable = $true; Eligible = $false; Fault = 'publication'; ChildCode = 0; Code = 2 },
        @{ Comparison = 'non-regression-write-failure'; Evaluable = $true; Eligible = $true; Fault = 'publication'; ChildCode = 0; Code = 1 },
        @{ Comparison = 'prior-child-failure'; Evaluable = $true; Eligible = $false; Fault = 'publication'; ChildCode = 1; Code = 1 },
        @{ Comparison = 'evaluation-failure'; Evaluable = $false; Eligible = $false; Fault = 'evaluation'; ChildCode = 0; Code = 1 },
        @{ Comparison = 'missing-history'; Evaluable = $false; Eligible = $false; Fault = 'missing'; ChildCode = 0; Code = 0 },
        @{ Comparison = 'malformed-history'; Evaluable = $false; Eligible = $false; Fault = 'malformed'; ChildCode = 0; Code = 0 },
        @{ Comparison = 'malformed-run'; Evaluable = $false; Eligible = $false; Fault = 'malformed-run'; ChildCode = 0; Code = 0 },
        @{ Comparison = 'incompatible-history'; Evaluable = $false; Eligible = $false; Fault = 'incompatible'; ChildCode = 0; Code = 0 },
        @{ Comparison = 'missing-history-objects'; Evaluable = $false; Eligible = $false; Fault = 'missing-objects'; ChildCode = 0; Code = 0 },
        @{ Comparison = 'setup-failure'; Evaluable = $false; Eligible = $false; Fault = 'setup'; ChildCode = 0; Code = 1 },
        @{ Comparison = 'admission-failure'; Evaluable = $false; Eligible = $false; Fault = 'admission'; ChildCode = 0; Code = 1 }
    ) {
        Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1')
        $Root = Join-Path $TestDrive "optional-$Comparison"
        $Source = Join-Path $TestDrive 'optional-source'
        [void][IO.Directory]::CreateDirectory($Source)
        [void][IO.Directory]::CreateDirectory((Join-Path $Root 'out'))
        [void][IO.Directory]::CreateDirectory((Join-Path $Root 'trials/candidate-1/out'))
        Set-Content (Join-Path $Root 'trials/candidate-1/out/run.json') '{}'
        $Saved = Join-Path $TestDrive "saved-$Comparison.json"
        if ($Fault -eq 'malformed') { Set-Content $Saved '{' }
        elseif ($Fault -ne 'missing') {
            $Controls = if ($Fault -eq 'malformed-run') { @(@{}, @{}, @{}) } else { @(@{ fixture = $true }, @{ fixture = $true }, @{ fixture = $true }) }
            @{ schemaVersion = 'efficiency-control-v1'; runs = $Controls } | ConvertTo-Json | Set-Content $Saved
        }
        $Options = @{ Mode = 'Series'; CandidateOnly = $true; TrialRoot = $Root; CandidateSourceRoot = $Source; BaselineEvidencePath = $Saved }
        Mock Invoke-WizardCommand { $ChildCode }
        Mock Export-BenchmarkScore { [void][IO.Directory]::CreateDirectory($OutputDirectory); @{ score = @{ value = 80; state = 'partial' } } }
        Mock Test-EfficiencyObservation { $true }
        Mock Assert-BenchmarkRecordedIdentity {
            if ($Fault -eq 'incompatible') { throw [IO.InvalidDataException]::new('invalid-record:measured-source-mismatch') }
            if ($Fault -eq 'missing-objects') { throw [IO.InvalidDataException]::new('operational-error:git-operation') }
            if ($Fault -eq 'admission') { throw [IO.IOException]::new('fixture admission failed') }
        }
        if ($Fault -eq 'setup') {
            Mock Import-Module { throw [IO.IOException]::new('fixture setup failed') } -ParameterFilter { $Name -like '*/EfficiencyBenchmark.psm1' }
        }
        if ($Fault -eq 'publication') {
            Mock Set-Content { throw [IO.IOException]::new('fixture comparison write denied') } -ParameterFilter { $LiteralPath -like '*/comparison.json' }
        }
        Mock Compare-EfficiencyRuns {
            Should -Invoke Export-BenchmarkScore -Times 1 -Exactly
            if ($Fault -eq 'evaluation') { throw [IO.IOException]::new('fixture evaluation failed') }
            [pscustomobject]@{ evaluable = $Evaluable; eligible = $Eligible; verdict = $Comparison }
        }
        Invoke-WizardBenchmark $Options | Should -Be $Code
        Should -Invoke Export-BenchmarkScore -Times 1 -Exactly
        $Compared = $Fault -in @('none', 'publication', 'evaluation')
        Should -Invoke Compare-EfficiencyRuns -Times $(if ($Compared) { 1 } else { 0 }) -Exactly
        $Manifest = Get-Content (Join-Path $Root 'out/benchmark-export.json') -Raw | ConvertFrom-Json
        $Manifest.score.value | Should -Be 80
        $OperationalFailure = $Fault -in @('publication', 'evaluation', 'setup', 'admission')
        $Manifest.status | Should -Be $(if ($OperationalFailure) { 'failed' } else { 'exported' })
        $Manifest.comparison.evaluable | Should -Be $Evaluable
        $Manifest.comparison.eligible | Should -Be $Eligible
        if ($Compared -and $Fault -ne 'evaluation') { $Manifest.comparison.verdict | Should -BeExactly $Comparison }
        if ($OperationalFailure) {
            $FailureStage = if ($Fault -eq 'admission') { 'history-admission' } else { $Fault }
            $Manifest.reason | Should -BeExactly "comparison-$FailureStage-failed"
        }
        elseif ($Fault -ne 'none') { $Manifest.comparison.reason | Should -BeExactly 'saved-controls-missing-or-incompatible' }
        Test-Path (Join-Path $Root 'portable/comparison.json') | Should -Be ($Fault -eq 'none')
    }
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
        Mock Export-BenchmarkScore { @{ score = @{ value = 80; state = 'partial' } } }
        $Result = Complete-WizardBenchmarkExport @{ Mode = 'Series'; CandidateSourceRoot = $Source; TrialRoot = $Root }
        $Result.status | Should -Be 'exported'
        $Result.recordedTrials | Should -Be 1
        $Result.publicationCommand | Should -Match "run''s-evidence"
        $Result.publicationCommand | Should -Match '-Standalone.*-TrialDirectories @\('
        $Result.publicationCommand | Should -Not -Match '-Live|-Mode Run|copilot'
        $Tokens = $null; $Errors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($Result.publicationCommand, [ref]$Tokens, [ref]$Errors)
        $Errors.Count | Should -Be 0
        Should -Invoke Export-BenchmarkScore -Times 1 -Exactly -ParameterFilter {
            $Repository -eq $Source -and $TrialDirectories.Count -eq 1 -and $OutputDirectory -eq (Join-Path $Root 'portable')
        }
        @(Get-ChildItem -LiteralPath $Source -Force).Count | Should -Be 0
    }
    It 'finalizes failed collections and never replaces their exit with export success or failure' {
        $Options = @{ Mode = 'Series'; CandidateSourceRoot = (Join-Path $TestDrive 'source'); TrialRoot = (Join-Path $TestDrive 'failed-run') }
        $Unavailable = Complete-WizardBenchmarkExport $Options
        $Unavailable.status | Should -Be 'failed'
        $Unavailable.score.state | Should -Be failed
        Test-Path (Join-Path $Options.TrialRoot 'portable/badge.svg') | Should -BeTrue
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
    It 'refuses a source <AliasShape> alias before creating wizard output' -ForEach @(
        @{ AliasShape = 'leaf' }, @{ AliasShape = 'ancestor' }
    ) {
        $Target = Join-Path $TestDrive "physical-source-$AliasShape"
        $PhysicalSource = if ($AliasShape -eq 'ancestor') { Join-Path $Target 'nested-source' } else { $Target }
        [void][IO.Directory]::CreateDirectory($PhysicalSource)
        $Alias = Join-Path $TestDrive "source-alias-$AliasShape"
        $null = New-Item -ItemType $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }) -Path $Alias -Target $Target
        $Source = if ($AliasShape -eq 'ancestor') { Join-Path $Alias 'nested-source' } else { $Alias }
        $Path = Join-Path $PhysicalSource 'wizard-scratch'
        { Assert-WizardScratchPath $Path $Source } | Should -Throw '*physical*'
        Test-Path -LiteralPath $Path | Should -BeFalse
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
        Mock Test-WizardSource {}
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

Describe 'Wizard remembered setup answers' -Tag 'Unit' {
    BeforeEach {
        $script:SetupDefaultsPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
        $script:SetupAnswers = [Collections.Generic.Queue[string]]::new()
        $script:SetupPrompts = [Collections.Generic.List[string]]::new()
        Mock Get-WizardDefaultsPath { $script:SetupDefaultsPath }
        Mock Test-Path { $false } -ParameterFilter { $Path -like 'Env:*' }
        Mock Invoke-WizardCommand { 0 }
        Mock Read-Host {
            $script:SetupPrompts.Add($Prompt)
            $script:SetupAnswers.Dequeue()
        }
    }
    It 'remembers Copilot method <Choice> and uses it on the next invocation' -ForEach @(
        @{ Choice = '1'; Arguments = 'login' },
        @{ Choice = '2'; Arguments = '' },
        @{ Choice = '3'; Arguments = 'login --with-token' }
    ) {
        $script:SetupAnswers.Enqueue($Choice)
        if ($Choice -ne '2') { $script:SetupAnswers.Enqueue('yes') }
        $script:SetupAnswers.Enqueue('')
        if ($Choice -ne '2') { $script:SetupAnswers.Enqueue('yes') }
        Connect-WizardGitHub
        Connect-WizardGitHub
        (Read-WizardDefaults).PromptAnswers.CopilotAuthorization | Should -Be $Choice
        $Choices = @($script:SetupPrompts | Where-Object { $_ -like 'Choice *' })
        $Choices[1] | Should -Match "\[$Choice\]"
        if ($Choice -eq '2') {
            Should -Invoke Invoke-WizardCommand -Times 0 -Exactly -ParameterFilter { $Command -eq 'copilot' }
        }
        else {
            $ExpectedArguments = $Arguments
            Should -Invoke Invoke-WizardCommand -Times 2 -Exactly -ParameterFilter { $Command -eq 'copilot' -and ($Arguments -join ' ') -eq $ExpectedArguments }
        }
    }
    It 'reuses the last clean-install answer after checking the prepared install again' {
        $Source = Join-Path $TestDrive 'setup-source'
        New-Item -ItemType Directory -Path $Source -Force | Out-Null
        Set-Content (Join-Path $Source 'apm.yml') 'name: fixture'
        $Install = Join-Path $TestDrive 'setup-install'
        Mock Test-WizardInstall { $true }
        $script:SetupAnswers.Enqueue('y')
        $script:SetupAnswers.Enqueue('')
        Initialize-WizardInstall -Path $Install -ManagedRoot $TestDrive -Source $Source
        Initialize-WizardInstall -Path $Install -ManagedRoot $TestDrive -Source $Source
        (Read-WizardDefaults).PromptAnswers.ReusePreparedInstall | Should -BeTrue
        $script:SetupPrompts[1] | Should -Match '\[yes\]'
        Should -Invoke Test-WizardInstall -Times 2 -Exactly
    }
    It 'remembers <MemoryKey> without reusing its authorization on blank input' -ForEach @(
        @{ MemoryKey = 'ArchiveInstall' },
        @{ MemoryKey = 'Launch' }
    ) {
        $script:SetupAnswers.Enqueue('yes')
        $script:SetupAnswers.Enqueue('')
        Confirm-WizardAction 'Protected action?' -MemoryKey $MemoryKey | Should -BeTrue
        (Read-WizardDefaults).PromptAnswers[$MemoryKey] | Should -BeTrue
        Confirm-WizardAction 'Protected action?' -MemoryKey $MemoryKey | Should -BeFalse
        (Read-WizardDefaults).PromptAnswers[$MemoryKey] | Should -BeFalse
        $script:SetupPrompts[1] | Should -Match '\[no\]'
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like 'Previous answer*yes*Fresh confirmation*' }
    }
    It 'requires fresh authentication even when login methods and prior approval are remembered' {
        Mock Read-Host { '' }
        foreach ($Choice in @('1', '3')) {
            Save-WizardDefaults -Previous (Read-WizardDefaults) -Answers @{ CopilotAuthorization = $Choice; CopilotLogin = $true }
            { Connect-WizardGitHub } | Should -Throw '*Copilot sign-in declined*'
            (Read-WizardDefaults).PromptAnswers.CopilotAuthorization | Should -Be $Choice
            (Read-WizardDefaults).PromptAnswers.CopilotLogin | Should -BeFalse
        }
        Should -Invoke Invoke-WizardCommand -Times 0 -Exactly -ParameterFilter { $Command -eq 'copilot' }
    }
    It 'retains failed-login preferences across configuration, spending and Offline saves' {
        $Config = New-WizardTestConfig
        $Config.WorkRoot = Join-Path $TestDrive 'setup-work'
        Save-WizardDefaults -Config $Config -SpendingAuthorized $true
        $Hash = (Read-WizardDefaults).SpendingAuthorization.planHash
        $script:SetupAnswers.Enqueue('3')
        $script:SetupAnswers.Enqueue('yes')
        Mock Invoke-WizardCommand { if ($Command -eq 'copilot') { 1 } else { 0 } }
        { Connect-WizardGitHub } | Should -Throw '*Copilot login failed*'
        Save-WizardDefaults -Config $Config -Previous (Read-WizardDefaults) -SpendingAuthorized $true
        (Read-WizardDefaults).SpendingAuthorization.planHash | Should -Be $Hash
        Save-WizardDefaults -Config @{ Mode = 'Offline'; WorkRoot = $Config.WorkRoot } -Previous (Read-WizardDefaults)
        $Saved = Read-WizardDefaults
        $Saved.PromptAnswers.CopilotAuthorization | Should -Be '3'
        $Saved.PromptAnswers.CopilotLogin | Should -BeTrue
        $Saved.SpendingAuthorization.planHash | Should -Be $Hash
    }
    It 'does not overwrite the last answer when later choice input is invalid or cancelled' {
        Save-WizardDefaults -Answers @{ CopilotAuthorization = '2' }
        $Before = (Get-FileHash -LiteralPath (Get-WizardDefaultsPath)).Hash
        $script:SetupAnswers.Enqueue('invalid')
        $script:SetupAnswers.Enqueue('q')
        { Connect-WizardGitHub } | Should -Throw '*cancelled*'
        (Get-FileHash -LiteralPath (Get-WizardDefaultsPath)).Hash | Should -Be $Before
        Should -Invoke Invoke-WizardCommand -Times 0 -Exactly -ParameterFilter { $Command -eq 'copilot' }
    }
    It 'rejects invalid remembered setup data: <Case>' -ForEach @(
        @{ Case = 'login enum'; Json = '{"schemaVersion":"efficiency-wizard-defaults-v1","PromptAnswers":{"CopilotAuthorization":"4"}}' },
        @{ Case = 'confirmation type'; Json = '{"schemaVersion":"efficiency-wizard-defaults-v1","PromptAnswers":{"ReusePreparedInstall":"yes"}}' },
        @{ Case = 'unrecognized key'; Json = '{"schemaVersion":"efficiency-wizard-defaults-v1","PromptAnswers":{"Token":"not-a-credential"}}' }
    ) {
        Save-WizardDefaults -Answers @{ CopilotAuthorization = '2' }
        $Before = (Get-FileHash -LiteralPath (Get-WizardDefaultsPath)).Hash
        $InvalidAnswers = (ConvertFrom-Json -InputObject $Json -AsHashtable).PromptAnswers
        { Save-WizardDefaults -Previous (Read-WizardDefaults) -Answers $InvalidAnswers } | Should -Throw '*invalid*'
        (Get-FileHash -LiteralPath (Get-WizardDefaultsPath)).Hash | Should -Be $Before
        Set-Content -LiteralPath (Get-WizardDefaultsPath) -Value $Json
        { Read-WizardDefaults } | Should -Throw '*Remove this file to reset*'
    }
}

Describe 'Wizard unattended plan' -Tag 'Unit' {
    BeforeEach { Mock Get-WizardBenchmarkSummary { New-WizardTestSummary } }
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
            @($ProgressMessages | Where-Object { $_.MessageData.ToString() -like 'Progress*baseline-1: awaiting preflight*' }).Count | Should -Be 2
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
        $Parallel[2].arguments.BaselineEvidencePath | Should -Be (Join-Path $Config.RunRoot 'control/out/control-series.json')
        $Parallel[1].arguments.MaxSeriesCredits + $Parallel[2].arguments.MaxSeriesCredits | Should -Be 360
        $Config.Mode = 'Series'
        (New-WizardRunPlan $Config)[1].arguments.CandidateOnly | Should -BeTrue
    }
    It 'runs Complete as offline checks, three controls, then three saved-control candidates' {
        $Config = New-WizardTestConfig
        $Steps = New-WizardRunPlan $Config
        $Steps.Count | Should -Be 3
        $Steps[1].arguments.Mode | Should -Be Establish
        $Steps[2].arguments.Mode | Should -Be Series
        $Steps[1].arguments.ObservationOnly | Should -BeTrue
        $Steps[2].arguments.ObservationOnly | Should -BeTrue
        $Steps[2].arguments.BaselineEvidencePath | Should -Be (Join-Path $Config.RunRoot 'control/out/control-series.json')
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
        Mock Test-WizardSource {}
        Mock Test-WizardCompatibility {}
        Mock Confirm-WizardAction { $true }
        Mock Invoke-WizardOfflineTest { $script:WizardCalls.Add('Offline'); 0 }
        Mock Invoke-WizardBenchmark { $script:WizardCalls.Add($Options.Mode); 0 }
        Mock Get-WizardBenchmarkSummary { New-WizardTestSummary }
        Mock Read-WizardText { throw 'Unexpected interactive input during execution' }
    }
    It 'runs Complete end to end and writes the result without invoking a model' {
        $Result = Invoke-EfficiencyWizard -Source 'source'
        $Result.exitCode | Should -Be 0
        $script:WizardCalls -join ',' | Should -Be 'Offline,Establish,Series'
        $Saved = Get-Content (Join-Path $script:WizardConfig.RunRoot 'wizard-result.json') -Raw | ConvertFrom-Json
        $Saved.outcome | Should -Be completed
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