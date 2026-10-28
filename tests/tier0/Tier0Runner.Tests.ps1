#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# AI cost: none; checks exact-once selection and runs only tiny local runner fixtures.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Consumed in Pester BeforeAll.')]
param([Parameter(Mandatory)][string]$SourceRoot)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'Tier0TestPlan.psm1') -Force
    $script:RunnerSource = Join-Path -Path $SourceRoot -ChildPath 'tests' -AdditionalChildPath 'tier0', 'Invoke-Tier0Tests.ps1'
    $script:Shards = @('Contracts', 'Handoff', 'Lifecycle', 'Coordinator')

    function Get-PlanKey {
        param([object[]]$Plan)
        @($Plan | ForEach-Object { "$($_.Directory)/$($_.Name)" } | Sort-Object)
    }

    function New-RunnerFixture {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Creates only owned Pester TestDrive fixtures.')]
        [CmdletBinding()]
        param()
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $tier0 = Join-Path -Path $root -ChildPath 'tests' -AdditionalChildPath 'tier0'
        $lib = Join-Path -Path $root -ChildPath 'tests' -AdditionalChildPath 'lib'
        foreach ($path in @($tier0, $lib)) { $null = [IO.Directory]::CreateDirectory($path) }
        Copy-Item -LiteralPath $script:RunnerSource -Destination $tier0
        Set-Content -LiteralPath (Join-Path $root 'source-marker') -Value 'source'
        Set-Content -LiteralPath (Join-Path $lib 'SquadInstall.psm1') -Value @'
function Install-SquadPackage {
    param($Destination, $SourceRoot, $Ref, $Package, $Target)
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..'))
    $log = Join-Path $root 'install.log'
    Set-Content -LiteralPath $log -Value "Ref=$Ref; Source=$SourceRoot"
    @{ Root = $root; InstallLog = $log }
}
Export-ModuleMember -Function Install-SquadPackage
'@
        Set-Content -LiteralPath (Join-Path $tier0 'Tier0TestPlan.psm1') -Value @'
function Get-Tier0TestPlan {
    param($Mode, $Scope, $Shard)
    if ($env:TIER0_FIXTURE_EMPTY -eq 'true') { return }
    if ($Scope -ne 'Package' -and $Mode -eq 'Source') {
        [pscustomobject]@{ Name = 'RepositoryFixture.Tests.ps1'; Directory = 'tier0'; Scope = 'Repository' }
    }
    if ($Scope -ne 'Repository') {
        [pscustomobject]@{ Name = 'SquadPackage.Tests.ps1'; Directory = 'tier0'; Scope = 'Package' }
    }
}
Export-ModuleMember -Function Get-Tier0TestPlan
'@
        Set-Content -LiteralPath (Join-Path $tier0 'RepositoryFixture.Tests.ps1') -Value @'
param([string]$SourceRoot)
Describe 'Repository fixture' {
    It 'receives the source checkout without installation' {
        Test-Path -LiteralPath (Join-Path $SourceRoot 'source-marker') | Should -BeTrue
    }
}
'@
        Set-Content -LiteralPath (Join-Path $tier0 'SquadPackage.Tests.ps1') -Value @'
param([string]$PackageRoot, [string]$InstallLog, [bool]$ExpectPinned)
Describe 'Installed fixture' {
    It 'receives the installed root and pin expectation' {
        Test-Path -LiteralPath (Join-Path $PackageRoot 'source-marker') | Should -BeTrue
        $ExpectPinned | Should -Be ($env:TIER0_FIXTURE_PINNED -eq 'true')
    }
}
'@
        $root
    }

    function Invoke-RunnerFixture {
        param([string]$Root, [string[]]$Arguments, [bool]$Pinned = $false, [bool]$Empty = $false)
        $start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        $runner = Join-Path -Path $Root -ChildPath 'tests' -AdditionalChildPath 'tier0', 'Invoke-Tier0Tests.ps1'
        foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $runner) + $Arguments) {
            $start.ArgumentList.Add($argument)
        }
        $start.Environment['TIER0_FIXTURE_PINNED'] = $Pinned.ToString().ToLowerInvariant()
        $start.Environment['TIER0_FIXTURE_EMPTY'] = $Empty.ToString().ToLowerInvariant()
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.UseShellExecute = $false
        $process = [Diagnostics.Process]::Start($start)
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            @{ ExitCode = $process.ExitCode; Output = $stdout.Result + $stderr.Result }
        }
        finally { $process.Dispose() }
    }
}

Describe 'CI-03 Exact-once Tier 0 selection' {
    It 'registers every repository test exactly once' {
        $actual = Get-PlanKey @(Get-Tier0TestPlan -Mode Source)
        $expected = @(
            Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File | ForEach-Object { "tier0/$($_.Name)" }
            Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'lib') -Filter '*.Tests.ps1' -File | ForEach-Object { "lib/$($_.Name)" }
        ) | Sort-Object
        @($actual | Select-Object -Unique).Count | Should -Be $actual.Count
        @(Compare-Object $actual $expected).Count | Should -Be 0
    }

    It 'partitions <Mode> across isolated shards without missing or repeated containers' -ForEach @(
        @{ Mode = 'Source' }
        @{ Mode = 'Installed' }
    ) {
        $all = Get-PlanKey @(Get-Tier0TestPlan -Mode $Mode)
        $partition = Get-PlanKey @(
            foreach ($shard in $script:Shards) { Get-Tier0TestPlan -Mode $Mode -Shard $shard }
        )
        @($partition | Select-Object -Unique).Count | Should -Be $partition.Count
        @(Compare-Object $all $partition).Count | Should -Be 0
        foreach ($shard in $script:Shards) {
            @(Get-Tier0TestPlan -Mode $Mode -Shard $shard).Count | Should -BeGreaterThan 0
        }
    }

    It 'keeps repository and installed-package release selections disjoint and complete' {
        $all = Get-PlanKey @(Get-Tier0TestPlan -Mode Source)
        $repository = @(Get-Tier0TestPlan -Mode Source -Scope Repository)
        $package = @(Get-Tier0TestPlan -Mode Installed -Scope Package)
        $combined = Get-PlanKey @($repository + $package)
        @($combined | Select-Object -Unique).Count | Should -Be $combined.Count
        @(Compare-Object $all $combined).Count | Should -Be 0
        @($repository.Shard | Select-Object -Unique | Sort-Object) | Should -Be @('Contracts', 'Coordinator')
        @(Get-Tier0TestPlan -Mode Installed).Count | Should -Be 20
    }

    It 'rejects repository-only selection without a source checkout' {
        { Get-Tier0TestPlan -Mode Installed -Scope Repository } | Should -Throw '*require -SourceRoot*'
    }
}

Describe 'CI-03 Tier 0 runner compatibility and failure boundaries' {
    It 'preserves <Case>' -ForEach @(
        @{ Case = 'repository-only execution without APM'; Mode = 'Repository'; Installed = $false; Tests = 1; Pinned = $false }
        @{ Case = 'the complete default source selection'; Mode = 'Source'; Installed = $true; Tests = 2; Pinned = $false }
        @{ Case = 'an already-installed package'; Mode = 'Installed'; Installed = $false; Tests = 1; Pinned = $false }
        @{ Case = 'published-tag installation and pin checks'; Mode = 'Ref'; Installed = $true; Tests = 1; Pinned = $true }
    ) {
        $root = New-RunnerFixture
        $arguments = switch ($Mode) {
            Repository { @('-SourceRoot', $root, '-Scope', 'Repository', '-Shard', 'Contracts') }
            Source { @('-SourceRoot', $root) }
            Installed { @('-PackageRoot', $root) }
            Ref { @('-Ref', 'v0.19.1', '-ScratchRoot', (Join-Path $root 'scratch')) }
        }
        $result = Invoke-RunnerFixture -Root $root -Arguments $arguments -Pinned $Pinned
        $result.ExitCode | Should -Be 0 -Because $result.Output
        Test-Path -LiteralPath (Join-Path $root 'install.log') | Should -Be $Installed
        $resultPath = Join-Path -Path $root -ChildPath 'tests' -AdditionalChildPath 'tier0', 'tier0-results.xml'
        [xml]$xml = Get-Content -LiteralPath $resultPath -Raw
        [int]$xml.'test-results'.total | Should -Be $Tests
        [int]$xml.'test-results'.failures | Should -Be 0
    }

    It 'rejects an empty selection rather than reporting a green shard' {
        $root = New-RunnerFixture
        $result = Invoke-RunnerFixture -Root $root -Arguments @('-SourceRoot', $root, '-Scope', 'Repository') -Empty $true
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'No Tier 0 containers selected'
    }

    It 'keeps <Case> nonzero' -ForEach @(
        @{ Case = 'a failing assertion'; Body = "Describe 'Failure' { It 'fails' { 1 | Should -Be 2 } }" }
        @{ Case = 'a discovery failure'; Body = "throw 'Fixture discovery failed.'" }
        @{ Case = 'zero discovered tests'; Body = "Describe 'Empty' {}" }
    ) {
        $root = New-RunnerFixture
        $path = Join-Path -Path $root -ChildPath 'tests' -AdditionalChildPath 'tier0', 'RepositoryFixture.Tests.ps1'
        Set-Content -LiteralPath $path -Value $Body
        $result = Invoke-RunnerFixture -Root $root -Arguments @('-SourceRoot', $root, '-Scope', 'Repository')
        $result.ExitCode | Should -Not -Be 0 -Because $result.Output
        Test-Path -LiteralPath (Join-Path $root 'install.log') | Should -BeFalse
    }
}
