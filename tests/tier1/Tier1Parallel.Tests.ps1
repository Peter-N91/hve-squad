#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

# AI cost: none; offline planning and accounting checks of the parallel self-check,
# despite the Tier 1 directory.

# Tier1Parallel.psm1 spreads the self-check over worker processes. What must never
# change is coverage, so these cases pin the two things that protect it: the plan puts
# every unit of work in exactly one bundle, and the accounting fails the run unless
# every discovered case ran exactly once. The planning and accounting are pure and
# tested directly. The end-to-end cases run the coordinator on tiny generated test files
# in a child process, because Pester does not nest.

BeforeAll {
    $script:Module = Join-Path $PSScriptRoot 'Tier1Parallel.psm1'
    $script:Runner = Join-Path $PSScriptRoot 'Invoke-Tier1Tests.ps1'
    Import-Module $script:Module -Force
}

Describe 'Get-Tier1WorkBundle puts every unit in exactly one bundle' {
    BeforeAll {
        function Build-UnitLocal {
            param([string]$File, [int]$Line, [int]$Tests)
            [pscustomobject]@{ File = $File; Line = $Line; Lines = @($Line); Name = "block $Line"; Tests = $Tests }
        }

        function Get-BundleLocal {
            param([double]$Target = 60, [object[]]$Unit = $script:Unit)
            @(Get-Tier1WorkBundle -Unit $Unit -SplittableFile $script:Split -SecondsPerTest $script:Rate -DefaultSecondsPerTest 0.5 -TargetSeconds $Target)
        }

        $script:WholeFile = Join-Path $TestDrive 'Whole.Tests.ps1'
        $script:SplitFile = Join-Path $TestDrive 'Split.Tests.ps1'
        $script:SmallFile = Join-Path $TestDrive 'Small.Tests.ps1'
        $script:Split = @('Split.Tests.ps1')
        $script:Rate = @{ 'Whole.Tests.ps1' = 3.0; 'Split.Tests.ps1' = 4.0 }
        $script:Unit = @(
            @{ File = $script:WholeFile; Line = 5; Tests = 40 }
            @{ File = $script:WholeFile; Line = 60; Tests = 30 }
            @{ File = $script:WholeFile; Line = 120; Tests = 10 }
            @{ File = $script:SplitFile; Line = 5; Tests = 50 }
            @{ File = $script:SplitFile; Line = 80; Tests = 35 }
            @{ File = $script:SplitFile; Line = 150; Tests = 20 }
            @{ File = $script:SplitFile; Line = 210; Tests = 20 }
            @{ File = $script:SplitFile; Line = 300; Tests = 5 }
            @{ File = $script:SplitFile; Line = 350; Tests = 1 }
            @{ File = $script:SmallFile; Line = 3; Tests = 6 }
            @{ File = $script:SmallFile; Line = 30; Tests = 2 }
        ) | ForEach-Object { Build-UnitLocal -File $_.File -Line $_.Line -Tests $_.Tests }
    }

    It 'gives each unit to one bundle when blocks under <Target> seconds are merged' -ForEach @(
        @{ Target = 0.1 }, @{ Target = 1 }, @{ Target = 30 }, @{ Target = 60 }, @{ Target = 1000 }, @{ Target = 100000 }
    ) {
        $bundle = Get-BundleLocal -Target $Target
        $dealt = @($bundle | ForEach-Object { $_.Unit } | ForEach-Object { '{0}:{1}' -f $_.File, $_.Line } | Sort-Object)
        $given = @($script:Unit | ForEach-Object { '{0}:{1}' -f $_.File, $_.Line } | Sort-Object)
        $dealt | Should -Be $given
    }

    It 'keeps every unit of a file that must not be split in one bundle when merging under <Target> seconds' -ForEach @(
        @{ Target = 0.1 }, @{ Target = 60 }, @{ Target = 100000 }
    ) {
        $bundle = Get-BundleLocal -Target $Target
        foreach ($file in $script:WholeFile, $script:SmallFile) {
            $owners = @($bundle | Where-Object { @($_.Unit | Where-Object { $_.File -eq $file }).Count -gt 0 })
            $owners.Count | Should -Be 1 -Because "$file has to stay whole"
            @($owners[0].Unit | Where-Object { $_.File -eq $file }).Count | Should -Be (@($script:Unit | Where-Object { $_.File -eq $file }).Count)
        }
    }

    It 'separates the blocks of a splittable file that are at or above the target' {
        $bundle = Get-BundleLocal -Target 60
        foreach ($line in 5, 80, 150, 210) {
            $owner = @($bundle | Where-Object { @($_.Unit | Where-Object { $_.File -eq $script:SplitFile -and $_.Line -eq $line }).Count -gt 0 })
            $owner.Count | Should -Be 1
            @($owner[0].Unit).Count | Should -Be 1 -Because "block $line is large enough to run alone"
        }
    }

    It 'merges small neighbouring blocks until they reach the target' {
        $unit = @(1..10 | ForEach-Object { Build-UnitLocal -File $script:SplitFile -Line ($_ * 10) -Tests 5 })
        $bundle = Get-BundleLocal -Target 60 -Unit $unit
        @($bundle | ForEach-Object { @($_.Unit).Count }) | Should -Be @(3, 3, 3, 1)
    }

    It 'merges small blocks across files but still never splits a whole file' {
        $bundle = Get-BundleLocal -Target 60
        $last = @($bundle | Where-Object { @($_.Unit | Where-Object { $_.File -eq $script:SmallFile }).Count -gt 0 })
        $last.Count | Should -Be 1
        @($last[0].Unit | ForEach-Object { $_.File } | Select-Object -Unique).Count | Should -BeGreaterThan 1
    }

    It 'orders bundles largest first and numbers them from one' {
        $bundle = Get-BundleLocal
        @($bundle | ForEach-Object { $_.Index }) | Should -Be @(1..$bundle.Count)
        for ($i = 1; $i -lt $bundle.Count; $i++) {
            $bundle[$i].Cost | Should -BeLessOrEqual $bundle[$i - 1].Cost
        }
    }

    It 'lists the units of every bundle by file and line' {
        foreach ($bundle in (Get-BundleLocal -Target 100000)) {
            $listed = @($bundle.Unit | ForEach-Object { '{0}|{1:D6}' -f $_.File, $_.Line })
            $listed | Should -Be @($listed | Sort-Object)
        }
    }

    It 'plans the same way every time' {
        $first = Get-BundleLocal | ConvertTo-Json -Depth 6
        $second = Get-BundleLocal | ConvertTo-Json -Depth 6
        $second | Should -Be $first
    }

    It 'weighs a file it has no estimate for at the default rate' {
        $bundle = Get-BundleLocal -Unit @(Build-UnitLocal -File (Join-Path $TestDrive 'Other.Tests.ps1') -Line 1 -Tests 10)
        $bundle.Count | Should -Be 1
        $bundle[0].Cost | Should -Be 5
    }

    It 'names a bundle after the file, or the block it runs alone' {
        $bundle = Get-BundleLocal -Target 60
        ($bundle | Where-Object { $_.Unit[0].File -eq $script:WholeFile }).Label | Should -Be 'Whole.Tests.ps1'
        ($bundle | Where-Object { $_.Unit[0].File -eq $script:SplitFile -and $_.Unit[0].Line -eq 5 }).Label | Should -Be 'Split.Tests.ps1: block 5'
    }

    It 'summarises a merged bundle by its first label and a count' {
        $bundle = Get-BundleLocal -Target 60
        $merged = @($bundle | Where-Object { @($_.Unit | Where-Object { $_.File -eq $script:SmallFile }).Count -gt 0 })
        $merged[0].Label | Should -Match '\(\+2 more\)$'
    }
}

Describe 'Test-Tier1WorkerOutcome accounts for every case' {
    BeforeAll {
        function Build-WorkerLocal {
            param([int]$Index, [string[]]$Executed = @(), [int]$ExitCode = 0, [switch]$NoSummary)
            $summary = if ($NoSummary) { $null } else { [pscustomobject]@{ executed = @($Executed) } }
            [pscustomobject]@{ Index = $Index; ExitCode = $ExitCode; Summary = $summary }
        }
        $script:Expected = @('A.Tests.ps1::one.a', 'A.Tests.ps1::one.b', 'B.Tests.ps1::two.c')
    }

    It 'accepts a run in which every case ran exactly once' {
        $worker = @(
            Build-WorkerLocal -Index 1 -Executed @('A.Tests.ps1::one.a', 'A.Tests.ps1::one.b')
            Build-WorkerLocal -Index 2 -Executed @('B.Tests.ps1::two.c')
        )
        @(Test-Tier1WorkerOutcome -ExpectedTest $script:Expected -Worker $worker).Count | Should -Be 0
    }

    It 'reports a case that never ran' {
        $worker = @(
            Build-WorkerLocal -Index 1 -Executed @('A.Tests.ps1::one.a')
            Build-WorkerLocal -Index 2 -Executed @('B.Tests.ps1::two.c')
        )
        $problem = @(Test-Tier1WorkerOutcome -ExpectedTest $script:Expected -Worker $worker)
        $problem.Count | Should -Be 1
        $problem[0] | Should -Match 'never ran'
        $problem[0] | Should -Match 'A\.Tests\.ps1::one\.b'
    }

    It 'reports a case that ran in two bundles' {
        $worker = @(
            Build-WorkerLocal -Index 1 -Executed @('A.Tests.ps1::one.a', 'A.Tests.ps1::one.b', 'B.Tests.ps1::two.c')
            Build-WorkerLocal -Index 2 -Executed @('B.Tests.ps1::two.c')
        )
        $problem = @(Test-Tier1WorkerOutcome -ExpectedTest $script:Expected -Worker $worker)
        $problem.Count | Should -Be 1
        $problem[0] | Should -Match 'ran more often than discovered'
        $problem[0] | Should -Match 'B\.Tests\.ps1::two\.c'
    }

    It 'reports a case nobody discovered' {
        $worker = @(Build-WorkerLocal -Index 1 -Executed @('A.Tests.ps1::one.a', 'A.Tests.ps1::one.b', 'B.Tests.ps1::two.c', 'C.Tests.ps1::three.d'))
        $problem = @(Test-Tier1WorkerOutcome -ExpectedTest $script:Expected -Worker $worker)
        $problem.Count | Should -Be 1
        $problem[0] | Should -Match 'C\.Tests\.ps1::three\.d'
    }

    It 'counts cases that share a name one by one' {
        $worker = @(Build-WorkerLocal -Index 1 -Executed @('A.Tests.ps1::each.case'))
        $problem = @(Test-Tier1WorkerOutcome -ExpectedTest @('A.Tests.ps1::each.case', 'A.Tests.ps1::each.case') -Worker $worker)
        $problem.Count | Should -Be 1
        $problem[0] | Should -Match '^1 case\(s\) never ran'
    }

    It 'reports how many cases of a repeated name never ran' {
        $problem = @(Test-Tier1WorkerOutcome -ExpectedTest @('A.Tests.ps1::each.case', 'A.Tests.ps1::each.case') -Worker @(Build-WorkerLocal -Index 1))
        $problem.Count | Should -Be 1
        $problem[0] | Should -Match '^2 case\(s\) never ran'
        $problem[0] | Should -Match 'each\.case \(x2\)'
    }

    It 'reports a bundle that wrote no summary' {
        $worker = @(
            Build-WorkerLocal -Index 1 -Executed $script:Expected
            Build-WorkerLocal -Index 2 -NoSummary
        )
        $problem = @(Test-Tier1WorkerOutcome -ExpectedTest $script:Expected -Worker $worker)
        $problem.Count | Should -Be 1
        $problem[0] | Should -Match 'Bundle 2 wrote no summary'
    }

    It 'reports a bundle that exited with a failure even though its cases are accounted for' {
        $worker = @(Build-WorkerLocal -Index 1 -Executed $script:Expected -ExitCode 1)
        $problem = @(Test-Tier1WorkerOutcome -ExpectedTest $script:Expected -Worker $worker)
        $problem.Count | Should -Be 1
        $problem[0] | Should -Match 'Bundle 1 exited with code 1'
    }

    It 'names at most ten missing cases and counts the rest' {
        $expected = @(1..14 | ForEach-Object { "F.Tests.ps1::case.$_" })
        $problem = @(Test-Tier1WorkerOutcome -ExpectedTest $expected -Worker @(Build-WorkerLocal -Index 1))
        $problem.Count | Should -Be 1
        $problem[0] | Should -Match '^14 case\(s\) never ran'
        $problem[0] | Should -Match 'and 4 more'
    }
}

Describe 'Plan and summary files' {
    BeforeAll {
        $script:PlanPath = Join-Path $TestDrive 'plan.json'
        [ordered]@{
            version = 2
            bundles = @(
                [ordered]@{ index = 1; units = @([ordered]@{ file = 'C:\a\A.Tests.ps1'; lines = @(12); name = 'one'; tests = 3 }) }
                [ordered]@{ index = 2; units = @([ordered]@{ file = 'C:\a\B.Tests.ps1'; lines = @(7, 9, 11); name = 'two'; tests = 3 }, [ordered]@{ file = 'C:\a\B.Tests.ps1'; lines = @(40); name = 'three'; tests = 2 }) }
            )
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:PlanPath
    }

    It 'reads one bundle of the plan with every line of every unit' {
        $share = @(Get-Tier1WorkerAssignment -PlanPath $script:PlanPath -Index 2)
        $share.Count | Should -Be 2
        @($share[0].Lines) | Should -Be @(7, 9, 11)
        @($share[1].Lines) | Should -Be @(40)
        $share[1].File | Should -Be 'C:\a\B.Tests.ps1'
    }

    It 'keeps a bundle with a single unit and a single line as lists' {
        $share = @(Get-Tier1WorkerAssignment -PlanPath $script:PlanPath -Index 1)
        $share.Count | Should -Be 1
        @($share[0].Lines).Count | Should -Be 1
        $share[0].Tests | Should -Be 3
    }

    It 'refuses a bundle that is not in the plan' {
        { Get-Tier1WorkerAssignment -PlanPath $script:PlanPath -Index 3 } | Should -Throw '*is not in the plan*'
    }

    It 'summarises the cases a worker executed by name and leaves out the ones it was not given' {
        function Build-ResultTestLocal {
            param([string]$Result, [string[]]$Path)
            [pscustomobject]@{ Result = $Result; ScriptBlock = [pscustomobject]@{ File = 'C:\a\A.Tests.ps1' }; Path = $Path; ExpandedPath = ($Path -join '.') }
        }
        $broke = Build-ResultTestLocal -Result 'Failed' -Path @('one', 'breaks')
        $result = [pscustomobject]@{
            Tests        = @(
                Build-ResultTestLocal -Result 'Passed' -Path @('one', 'passes')
                $broke
                Build-ResultTestLocal -Result 'Skipped' -Path @('one', 'waits')
                Build-ResultTestLocal -Result 'NotRun' -Path @('other', 'belongs to a different bundle')
            )
            Failed       = @($broke)
            PassedCount  = 1
            FailedCount  = 1
            SkippedCount = 1
            Duration     = [timespan]::FromSeconds(2.5)
        }

        Write-Tier1WorkerSummary -PlanPath $script:PlanPath -Index 1 -Result $result -ExitCode 1

        $summary = Get-Content -LiteralPath (Join-Path $TestDrive 'bundle-1.json') -Raw | ConvertFrom-Json
        $summary.exitCode | Should -Be 1
        @($summary.executed) | Should -Be @('A.Tests.ps1::one.passes', 'A.Tests.ps1::one.breaks', 'A.Tests.ps1::one.waits')
        @($summary.failures) | Should -Be @('one.breaks')
        $summary.passed | Should -Be 1
    }
}

Describe 'Invoke-Tier1ParallelSelfCheck runs generated test files in worker processes' {
    BeforeAll {
        $script:Work = Join-Path $TestDrive 'generated'
        New-Item -ItemType Directory -Path $script:Work | Out-Null

        function Write-GeneratedFileLocal {
            param([string]$Name, [string]$Content)
            $path = Join-Path $script:Work $Name
            Set-Content -LiteralPath $path -Value $Content
            $path
        }

        $script:Alpha = Write-GeneratedFileLocal -Name 'Alpha.Tests.ps1' -Content @'
Describe 'alpha one' { It 'passes' { 1 | Should -Be 1 } }
Describe 'alpha two' -ForEach @(@{ Value = 1 }, @{ Value = 2 }) { It 'passes with <Value>' { $Value | Should -BeGreaterThan 0 } }
'@
        $script:Beta = Write-GeneratedFileLocal -Name 'Beta.Tests.ps1' -Content @'
Describe 'beta' {
    It 'passes' { 'b' | Should -Be 'b' }
    It 'is skipped' -Skip { }
}
'@
        $script:Gamma = Write-GeneratedFileLocal -Name 'Gamma.Tests.ps1' -Content @'
Describe 'gamma' { It 'breaks' { 1 | Should -Be 2 } }
'@
        $script:Delta = Write-GeneratedFileLocal -Name 'Delta.Tests.ps1' -Content "Describe 'delta' { It 'never parses' { 1 | Should -Be 1 }"
        $script:Epsilon = Write-GeneratedFileLocal -Name 'Epsilon.Tests.ps1' -Content @'
Describe 'epsilon' { It 'passes' { 1 | Should -Be 1 } }
'@
        # A Describe that holds Contexts, split apart: cases sit directly in it, in a Context and in a
        # -ForEach Context, and all of them rely on what the Describe set up once.
        $script:Nested = Write-GeneratedFileLocal -Name 'Nested.Tests.ps1' -Content @'
Describe 'outer' {
    BeforeAll { $script:Shared = 'set by the describe' }
    It 'direct one' { $script:Shared | Should -Be 'set by the describe' }
    Context 'first context' {
        It 'context one' { $script:Shared | Should -Be 'set by the describe' }
        It 'context two' { 1 | Should -Be 1 }
    }
    It 'direct two' { 1 | Should -Be 1 }
    Context 'second context' -ForEach @(@{ N = 1 }, @{ N = 2 }) {
        It 'context three <N>' { $N | Should -BeGreaterThan 0 }
    }
}
Describe 'plain' { It 'plain one' { 1 | Should -Be 1 } }
'@

        # Stand-ins for a worker process that misbehaves: one that exits cleanly without
        # reporting, and one that reports having run nothing.
        $script:Silent = Write-GeneratedFileLocal -Name 'Silent.ps1' -Content 'exit 0'
        $script:Empty = Write-GeneratedFileLocal -Name 'Empty.ps1' -Content @'
param([switch]$SelfCheck, [string]$WorkerPlan, [int]$WorkerIndex, [string]$Output)
[ordered]@{ index = $WorkerIndex; exitCode = 0; passed = 0; failed = 0; skipped = 0; seconds = 0; failures = @(); executed = @() } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path (Split-Path -Parent $WorkerPlan) "bundle-$WorkerIndex.json")
exit 0
'@

        function Invoke-CoordinatorLocal {
            param([string[]]$File, [string]$Runner = $script:Runner, [int]$Workers = 2, [string[]]$Splittable = @())
            $quote = { param($text) "'" + $text.Replace("'", "''") + "'" }
            $list = ($File | ForEach-Object { & $quote $_ }) -join ', '
            $split = ($Splittable | ForEach-Object { & $quote $_ }) -join ', '
            # A target of a tenth of a second keeps each file or block in a bundle of its own.
            $command = "Import-Module $(& $quote $script:Module) -Force; `$code = @(Invoke-Tier1ParallelSelfCheck -Path @($list) -Workers $Workers -RunnerPath $(& $quote $Runner) -Output Normal -SplittableFile @($split) -TargetSeconds 0.1)[-1]; exit `$code"
            $output = & pwsh -NoProfile -Command $command 2>&1 | Out-String
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
        }
    }

    It 'runs every case once across two workers and reports success' {
        $run = Invoke-CoordinatorLocal -File $script:Alpha, $script:Beta
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match 'all 5 cases ran exactly once in 2 bundles on 2 workers'
        $run.Output | Should -Match '\[b01\]'
        $run.Output | Should -Match '\[b02\]'
    }

    It 'queues more bundles than workers and still runs every case once' {
        $run = Invoke-CoordinatorLocal -File $script:Alpha, $script:Beta, $script:Epsilon, $script:Gamma -Workers 2 -Splittable @()
        $run.ExitCode | Should -Be 1 -Because $run.Output
        $run.Output | Should -Match 'Failed cases: 1'
        $run.Output | Should -Not -Match 'never ran'
        $run.Output | Should -Not -Match 'ran more often'
        $run.Output | Should -Match '\[b04\]'
    }

    It 'splits a Describe that holds Contexts and runs every case once' {
        $run = Invoke-CoordinatorLocal -File $script:Nested -Workers 3 -Splittable 'Nested.Tests.ps1'
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match 'all 7 cases ran exactly once in 4 bundles on 3 workers'
    }

    It 'keeps the same Describe whole when its file is not splittable' {
        $run = Invoke-CoordinatorLocal -File $script:Nested -Workers 3
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match 'all 7 cases ran exactly once in 1 bundle on 3 workers'
    }

    It 'fails and names the case when a case fails' {
        $run = Invoke-CoordinatorLocal -File $script:Alpha, $script:Gamma
        $run.ExitCode | Should -Be 1 -Because $run.Output
        $run.Output | Should -Match 'Failed cases: 1'
        $run.Output | Should -Match 'gamma\.breaks'
    }

    It 'fails when a worker process exits cleanly without reporting what it ran' {
        $run = Invoke-CoordinatorLocal -File $script:Alpha, $script:Beta -Runner $script:Silent
        $run.ExitCode | Should -Be 1 -Because $run.Output
        $run.Output | Should -Match 'wrote no summary'
    }

    It 'fails when a worker process reports fewer cases than it was given' {
        $run = Invoke-CoordinatorLocal -File $script:Alpha, $script:Beta -Runner $script:Empty
        $run.ExitCode | Should -Be 1 -Because $run.Output
        $run.Output | Should -Match '5 case\(s\) never ran'
    }

    It 'fails loudly when a test file cannot be discovered' {
        $run = Invoke-CoordinatorLocal -File $script:Alpha, $script:Delta
        $run.ExitCode | Should -Not -Be 0 -Because $run.Output
        $run.Output | Should -Match 'Test discovery failed'
    }

    It 'makes a worker process fail when its line filter selects nothing' {
        $planPath = Join-Path $script:Work 'nothing-plan.json'
        [ordered]@{
            version = 2
            bundles = @([ordered]@{ index = 1; units = @([ordered]@{ file = $script:Alpha; lines = @(9999); name = 'no such block'; tests = 1 }) })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath

        $output = & pwsh -NoProfile -File $script:Runner -SelfCheck -WorkerPlan $planPath -WorkerIndex 1 -Output None 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1 -Because $output
        $output | Should -Match 'No tests ran'
    }
}
