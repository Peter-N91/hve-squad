# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

# Runs the Tier 1 self-check in several worker processes.
#
# Almost every case starts child pwsh processes, so the suite is bound by process
# start-up, and one sequential Pester run outgrows a CI job as cases are added. The cases
# are independent, so this module discovers them once, groups them into bundles, lets a
# fixed number of worker processes take the bundles largest first, and then proves that
# every discovered case ran exactly once. Scheduling changes; coverage does not, and a
# case that is lost or repeated fails the run.
#
# Bundles are handed out as workers become free, so no estimate of how long a case takes
# has to be right. The estimates below only decide the order, and how small neighbours are
# merged so that a bundle is worth the cost of starting a process.

Set-StrictMode -Version Latest

# Containers whose blocks may be dealt to different bundles. Every other container stays
# whole in one bundle: Assertions.Tests.ps1 runs the Tier 1 runner as a child for each
# case, and that runner writes one fixed results file, so two of its Describes must never
# overlap in time.
$script:SplittableFile = @('LedgerCalculator.Tests.ps1')

# Rough seconds per case. Used for ordering and merging only; a wrong guess costs balance,
# never coverage.
$script:SecondsPerTest = @{
    'Assertions.Tests.ps1'       = 3.0
    'LedgerCalculator.Tests.ps1' = 4.0
    'ModelRouting.Tests.ps1'     = 0.5
    'Tier1Parallel.Tests.ps1'    = 3.0
}
$script:DefaultSecondsPerTest = 0.2

# Neighbouring blocks smaller than this are merged, so a bundle repays starting a process.
$script:TargetBundleSeconds = 60

function Get-Tier1TestKey {
    <#
    .SYNOPSIS
        The identity of one case, the same in discovery and in a run's results.
    .DESCRIPTION
        Uses the unexpanded name chain: a -ForEach case's expanded name only exists once it
        runs. Cases that repeat a name are counted, not collapsed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string[]]$Path
    )

    '{0}::{1}' -f (Split-Path -Leaf $File), ($Path -join '.')
}

function Get-Tier1WorkUnit {
    <#
    .SYNOPSIS
        Discovers the cases of the given test files and groups them into work units.
    .DESCRIPTION
        A unit is a top-level Describe. In a splittable file a Describe that holds Contexts is
        split further: one unit per Context, and one for the cases that sit directly in the
        Describe. Every case belongs to exactly one unit.
    .OUTPUTS
        An object with Unit (File, Line, Lines, Name, Tests) and ExpectedTest, one key per case.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Path,
        [string[]]$SplittableFile = @()
    )

    $configuration = New-PesterConfiguration
    $configuration.Run.Container = @($Path | ForEach-Object { New-PesterContainer -Path $_ })
    $configuration.Run.SkipRun = $true
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'None'
    $discovery = Invoke-Pester -Configuration $configuration

    # A discovery failure yields no cases and no failures, which would read as success.
    $broken = @($discovery.Containers | Where-Object { $_.Result -eq 'Failed' })
    if ($broken.Count -gt 0) {
        $detail = foreach ($container in $broken) {
            "$($container.Item): $(@($container.ErrorRecord | ForEach-Object { $_.ToString() }) -join '; ')"
        }
        throw "Test discovery failed for $($broken.Count) container(s): $($detail -join ' | ')"
    }

    $expected = [System.Collections.Generic.List[string]]::new()
    $top = [ordered]@{}
    foreach ($test in @($discovery.Tests | Where-Object { $_.ShouldRun })) {
        $file = $test.ScriptBlock.File
        $expected.Add((Get-Tier1TestKey -File $file -Path $test.Path))

        # Walk up to the top-level block, remembering the block directly beneath it.
        $block = $test.Block
        $child = $null
        while ($block.Parent -and -not $block.Parent.IsRoot) {
            $child = $block
            $block = $block.Parent
        }

        $key = '{0}:{1}' -f $file, $block.StartLine
        if (-not $top.Contains($key)) {
            $top[$key] = [pscustomobject]@{
                File        = $file
                Line        = [int]$block.StartLine
                Name        = [string]$block.Name
                Tests       = 0
                DirectTests = 0
                Direct      = [System.Collections.Generic.SortedSet[int]]::new()
                Children    = [ordered]@{}
            }
        }
        $entry = $top[$key]
        $entry.Tests++
        if ($child) {
            $childKey = [string]$child.StartLine
            if (-not $entry.Children.Contains($childKey)) {
                $entry.Children[$childKey] = [pscustomobject]@{ Line = [int]$child.StartLine; Name = [string]$child.Name; Tests = 0 }
            }
            $entry.Children[$childKey].Tests++
        }
        else {
            $entry.DirectTests++
            $null = $entry.Direct.Add([int]$test.StartLine)
        }
    }

    $unit = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $top.Values) {
        $split = ($SplittableFile -contains (Split-Path -Leaf $entry.File)) -and $entry.Children.Count -gt 0
        if (-not $split) {
            $unit.Add([pscustomobject]@{ File = $entry.File; Line = $entry.Line; Lines = @($entry.Line); Name = $entry.Name; Tests = $entry.Tests })
            continue
        }
        foreach ($child in $entry.Children.Values) {
            $unit.Add([pscustomobject]@{ File = $entry.File; Line = $child.Line; Lines = @($child.Line); Name = "$($entry.Name) > $($child.Name)"; Tests = $child.Tests })
        }
        if ($entry.DirectTests -gt 0) {
            $own = @($entry.Direct)
            $unit.Add([pscustomobject]@{ File = $entry.File; Line = $own[0]; Lines = $own; Name = "$($entry.Name) (its own cases)"; Tests = $entry.DirectTests })
        }
    }

    [pscustomobject]@{ Unit = $unit.ToArray(); ExpectedTest = $expected.ToArray() }
}

function Get-Tier1WorkBundle {
    <#
    .SYNOPSIS
        Groups work units into bundles and orders the bundles largest first.
    .DESCRIPTION
        A file that is not splittable is one indivisible piece. Each unit of a splittable file
        is a piece of its own. Neighbouring pieces smaller than TargetSeconds are merged until
        they reach it, and a piece at or above it stays alone. Every unit lands in exactly one
        bundle, the plan is deterministic, and bundles are numbered from one in dispatch order.
    .PARAMETER Unit
        Objects with File, Line, Name and Tests, as returned by Get-Tier1WorkUnit.
    .PARAMETER SecondsPerTest
        Estimated seconds per case by file name, for ordering and merging only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Unit,
        [string[]]$SplittableFile = @(),
        [hashtable]$SecondsPerTest = @{},
        [double]$DefaultSecondsPerTest = 1.0,
        [double]$TargetSeconds = 60
    )

    # Files are taken in the order they were given, so neighbours are neighbours in the run.
    $byFile = [ordered]@{}
    foreach ($one in $Unit) {
        if (-not $byFile.Contains($one.File)) { $byFile[$one.File] = [System.Collections.Generic.List[object]]::new() }
        $byFile[$one.File].Add($one)
    }

    $piece = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $byFile.Keys) {
        $leaf = Split-Path -Leaf $file
        $rate = if ($SecondsPerTest.ContainsKey($leaf)) { [double]$SecondsPerTest[$leaf] } else { $DefaultSecondsPerTest }
        $member = @($byFile[$file] | Sort-Object -Property Line)

        if ($SplittableFile -contains $leaf) {
            foreach ($one in $member) {
                $label = if ($member.Count -gt 1) { "${leaf}: $($one.Name)" } else { $leaf }
                $piece.Add([pscustomobject]@{ Label = $label; Cost = $one.Tests * $rate; Unit = @($one) })
            }
        }
        else {
            $tests = 0
            foreach ($one in $member) { $tests += $one.Tests }
            $piece.Add([pscustomobject]@{ Label = $leaf; Cost = $tests * $rate; Unit = $member })
        }
    }

    $merged = [System.Collections.Generic.List[object]]::new()
    $open = [System.Collections.Generic.List[object]]::new()
    $flush = {
        if ($open.Count -gt 0) {
            $cost = 0.0
            foreach ($one in $open) { $cost += $one.Cost }
            $labels = @($open | ForEach-Object { $_.Label } | Select-Object -Unique)
            $label = if ($labels.Count -le 2) { $labels -join ', ' } else { "$($labels[0]) (+$($labels.Count - 1) more)" }
            $merged.Add([pscustomobject]@{ Label = $label; Cost = $cost; Unit = @($open | ForEach-Object { $_.Unit }) })
            $open.Clear()
        }
    }
    foreach ($one in $piece) {
        if ($one.Cost -ge $TargetSeconds) {
            & $flush
            $open.Add($one)
            & $flush
            continue
        }
        $open.Add($one)
        $openCost = 0.0
        foreach ($held in $open) { $openCost += $held.Cost }
        if ($openCost -ge $TargetSeconds) { & $flush }
    }
    & $flush

    $index = 0
    foreach ($bundle in ($merged | Sort-Object -Property @{ Expression = { $_.Cost }; Descending = $true }, @{ Expression = { $_.Unit[0].File } }, @{ Expression = { $_.Unit[0].Line } })) {
        $index++
        [pscustomobject]@{
            Index = $index
            Cost  = $bundle.Cost
            Label = $bundle.Label
            Unit  = @($bundle.Unit | Sort-Object -Property File, Line)
        }
    }
}

function Test-Tier1WorkerOutcome {
    <#
    .SYNOPSIS
        Checks that every discovered case ran exactly once and every bundle finished cleanly.
    .PARAMETER ExpectedTest
        One key per discovered case, from Get-Tier1WorkUnit.
    .PARAMETER Worker
        One object per bundle run, with Index, ExitCode and Summary. Summary is the report the
        worker process wrote, or $null when it wrote none.
    .OUTPUTS
        One message per problem; nothing when the run is accounted for.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExpectedTest,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Worker
    )

    $problem = [System.Collections.Generic.List[string]]::new()
    $remaining = @{}
    foreach ($key in $ExpectedTest) {
        $remaining[$key] = if ($remaining.ContainsKey($key)) { $remaining[$key] + 1 } else { 1 }
    }

    $surplus = @{}
    foreach ($entry in $Worker) {
        if ($entry.ExitCode -ne 0) {
            $problem.Add("Bundle $($entry.Index) exited with code $($entry.ExitCode).")
        }
        if ($null -eq $entry.Summary) {
            $problem.Add("Bundle $($entry.Index) wrote no summary, so its cases cannot be accounted for.")
            continue
        }
        foreach ($key in @($entry.Summary.executed)) {
            if ($remaining.ContainsKey($key) -and $remaining[$key] -gt 0) {
                $remaining[$key]--
            }
            else {
                $surplus[$key] = if ($surplus.ContainsKey($key)) { $surplus[$key] + 1 } else { 1 }
            }
        }
    }

    $missing = @($remaining.Keys | Where-Object { $remaining[$_] -gt 0 } | Sort-Object)
    if ($missing.Count -gt 0) {
        $total = 0
        foreach ($key in $missing) { $total += $remaining[$key] }
        $shown = @($missing | Select-Object -First 10 | ForEach-Object { "$_ (x$($remaining[$_]))" })
        $more = if ($missing.Count -gt $shown.Count) { " and $($missing.Count - $shown.Count) more" } else { '' }
        $problem.Add("$total case(s) never ran: $($shown -join '; ')$more")
    }
    $extra = @($surplus.Keys | Sort-Object)
    if ($extra.Count -gt 0) {
        $total = 0
        foreach ($key in $extra) { $total += $surplus[$key] }
        $shown = @($extra | Select-Object -First 10 | ForEach-Object { "$_ (x$($surplus[$_]))" })
        $more = if ($extra.Count -gt $shown.Count) { " and $($extra.Count - $shown.Count) more" } else { '' }
        $problem.Add("$total case(s) ran more often than discovered: $($shown -join '; ')$more")
    }

    $problem.ToArray()
}

function Get-Tier1WorkerAssignment {
    <#
    .SYNOPSIS
        Reads one bundle of the plan the coordinator wrote.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][int]$Index
    )

    $plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
    $share = @($plan.bundles | Where-Object { $_.index -eq $Index })
    if ($share.Count -ne 1) { throw "Bundle $Index is not in the plan at $PlanPath." }

    @($share[0].units | ForEach-Object {
            [pscustomobject]@{ File = [string]$_.file; Lines = @($_.lines | ForEach-Object { [int]$_ }); Name = [string]$_.name; Tests = [int]$_.tests }
        })
}

function Write-Tier1WorkerSummary {
    <#
    .SYNOPSIS
        Records what a worker process ran, next to the plan, for the coordinator to account for.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][int]$ExitCode
    )

    $executed = @($Result.Tests |
            Where-Object { $_.Result -ne 'NotRun' } |
            ForEach-Object { Get-Tier1TestKey -File $_.ScriptBlock.File -Path $_.Path })
    $failed = @($Result.Failed | ForEach-Object { [string]$_.ExpandedPath })

    $summary = [ordered]@{
        index    = $Index
        exitCode = $ExitCode
        passed   = [int]$Result.PassedCount
        failed   = [int]$Result.FailedCount
        skipped  = [int]$Result.SkippedCount
        seconds  = [math]::Round($Result.Duration.TotalSeconds, 1)
        failures = $failed
        executed = $executed
    }
    $summaryPath = Join-Path (Split-Path -Parent $PlanPath) "bundle-$Index.json"
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
}

function Invoke-Tier1WorkerProcess {
    <#
    .SYNOPSIS
        Runs each bundle in its own worker process, a fixed number at a time, largest first.
        Output is echoed live behind a [bNN] prefix.
    .OUTPUTS
        One object per bundle with Index, ExitCode and Seconds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Bundle,
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$RunnerPath,
        [Parameter(Mandatory)][string]$Output,
        [Parameter(Mandatory)][ValidateRange(1, 64)][int]$Workers
    )

    $pwsh = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $queue = [System.Collections.Generic.Queue[object]]::new()
    foreach ($next in $Bundle) { $queue.Enqueue($next) }
    $running = [System.Collections.Generic.List[object]]::new()
    $finished = [System.Collections.Generic.List[object]]::new()

    try {
        while ($queue.Count -gt 0 -or $running.Count -gt 0) {
            while ($queue.Count -gt 0 -and $running.Count -lt $Workers) {
                $next = $queue.Dequeue()
                $startInfo = [System.Diagnostics.ProcessStartInfo]::new($pwsh)
                foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $RunnerPath, '-SelfCheck', '-WorkerPlan', $PlanPath, '-WorkerIndex', [string]$next.Index, '-Output', $Output)) {
                    $startInfo.ArgumentList.Add($argument)
                }
                $startInfo.RedirectStandardOutput = $true
                $startInfo.RedirectStandardError = $true
                $startInfo.UseShellExecute = $false
                $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
                $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

                Write-Host ('[b{0:D2}] starting: about {1:N0}s: {2}' -f $next.Index, $next.Cost, $next.Label)
                $process = [System.Diagnostics.Process]::Start($startInfo)
                $running.Add([pscustomobject]@{
                        Index    = $next.Index
                        Process  = $process
                        Started  = [datetime]::UtcNow
                        Out      = $process.StandardOutput.ReadLineAsync()
                        Err      = $process.StandardError.ReadLineAsync()
                        OutOpen  = $true
                        ErrOpen  = $true
                        ExitSeen = $null
                    })
            }

            $moved = $false
            foreach ($entry in @($running)) {
                if ($entry.OutOpen -and $entry.Out.IsCompleted) {
                    $line = $entry.Out.Result
                    if ($null -eq $line) { $entry.OutOpen = $false }
                    else {
                        Write-Host ('[b{0:D2}] {1}' -f $entry.Index, $line)
                        $entry.Out = $entry.Process.StandardOutput.ReadLineAsync()
                    }
                    $moved = $true
                }
                if ($entry.ErrOpen -and $entry.Err.IsCompleted) {
                    $line = $entry.Err.Result
                    if ($null -eq $line) { $entry.ErrOpen = $false }
                    else {
                        Write-Host ('[b{0:D2}] {1}' -f $entry.Index, $line)
                        $entry.Err = $entry.Process.StandardError.ReadLineAsync()
                    }
                    $moved = $true
                }

                # A grandchild that outlives its worker can hold the pipes open, so a worker
                # that has exited is not waited for forever.
                if ($null -eq $entry.ExitSeen -and $entry.Process.HasExited) { $entry.ExitSeen = [datetime]::UtcNow }
                $drained = -not $entry.OutOpen -and -not $entry.ErrOpen
                $abandoned = $null -ne $entry.ExitSeen -and ([datetime]::UtcNow - $entry.ExitSeen).TotalSeconds -gt 3
                if ($drained -or $abandoned) {
                    $entry.Process.WaitForExit()
                    # Process.StartTime is not available once a process has exited on Linux, so
                    # the clock is the one started with the process.
                    $ended = if ($null -ne $entry.ExitSeen) { $entry.ExitSeen } else { [datetime]::UtcNow }
                    $finished.Add([pscustomobject]@{
                            Index    = $entry.Index
                            ExitCode = $entry.Process.ExitCode
                            Seconds  = [math]::Round(($ended - $entry.Started).TotalSeconds, 1)
                        })
                    $entry.Process.Dispose()
                    $null = $running.Remove($entry)
                    $moved = $true
                }
            }
            if (-not $moved) { Start-Sleep -Milliseconds 25 }
        }
    }
    finally {
        foreach ($entry in $running) {
            if (-not $entry.Process.HasExited) { $entry.Process.Kill($true) }
            $entry.Process.Dispose()
        }
    }

    $finished.ToArray()
}

function Invoke-Tier1ParallelSelfCheck {
    <#
    .SYNOPSIS
        Runs the given test files across worker processes and accounts for every case.
    .PARAMETER Path
        The test files that make up the self-check.
    .PARAMETER Workers
        How many worker processes run at once.
    .PARAMETER RunnerPath
        The Tier 1 runner that each worker process re-invokes in worker mode.
    .PARAMETER SplittableFile
        Files whose blocks may be run apart. Defaults to the registered list.
    .PARAMETER TargetSeconds
        Estimated seconds below which neighbouring blocks are merged into one bundle.
    .OUTPUTS
        0 when every case ran once and passed; 1 otherwise. All reporting goes to the host.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string[]]$Path,
        [Parameter(Mandatory)][ValidateRange(2, 64)][int]$Workers,
        [Parameter(Mandatory)][string]$RunnerPath,
        [string]$Output = 'Detailed',
        [string[]]$SplittableFile = $script:SplittableFile,
        [double]$TargetSeconds = $script:TargetBundleSeconds
    )

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $discovery = Get-Tier1WorkUnit -Path $Path -SplittableFile $SplittableFile
    if ($discovery.ExpectedTest.Count -eq 0) {
        Write-Error 'No tests ran. Discovery found no cases in the self-check containers.' -ErrorAction Continue
        return 1
    }

    $bundle = @(Get-Tier1WorkBundle -Unit $discovery.Unit -SplittableFile $SplittableFile -SecondsPerTest $script:SecondsPerTest -DefaultSecondsPerTest $script:DefaultSecondsPerTest -TargetSeconds $TargetSeconds)
    $bundleCount = '{0} bundle{1}' -f $bundle.Count, $(if ($bundle.Count -eq 1) { '' } else { 's' })
    Write-Host "Tier 1 self-check: $($discovery.ExpectedTest.Count) cases in $bundleCount, $Workers worker processes at a time."

    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) "hve-tier1-selfcheck-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $null = New-Item -ItemType Directory -Path $workDir
    try {
        $planPath = Join-Path $workDir 'plan.json'
        [ordered]@{
            version = 2
            bundles = @($bundle | ForEach-Object {
                    [ordered]@{
                        index = $_.Index
                        units = @($_.Unit | ForEach-Object { [ordered]@{ file = $_.File; lines = @($_.Lines); name = $_.Name; tests = $_.Tests } })
                    }
                })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8NoBOM

        $finished = @(Invoke-Tier1WorkerProcess -Bundle $bundle -PlanPath $planPath -RunnerPath $RunnerPath -Output $Output -Workers $Workers)

        $outcome = foreach ($done in ($finished | Sort-Object -Property Index)) {
            $summaryPath = Join-Path $workDir "bundle-$($done.Index).json"
            $summary = if (Test-Path -LiteralPath $summaryPath -PathType Leaf) { Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json } else { $null }
            [pscustomobject]@{ Index = $done.Index; ExitCode = $done.ExitCode; Seconds = $done.Seconds; Summary = $summary }
        }
        $outcome = @($outcome)
    }
    finally {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Host 'Tier 1 self-check bundles:'
    foreach ($done in $outcome) {
        $label = @($bundle | Where-Object { $_.Index -eq $done.Index })[0].Label
        if ($null -ne $done.Summary) {
            Write-Host ('  b{0:D2}: exit {1}, passed {2}, failed {3}, skipped {4}, {5,5:N0}s  {6}' -f $done.Index, $done.ExitCode, $done.Summary.passed, $done.Summary.failed, $done.Summary.skipped, $done.Seconds, $label)
        }
        else {
            Write-Host ('  b{0:D2}: exit {1}, no summary, {2,5:N0}s  {3}' -f $done.Index, $done.ExitCode, $done.Seconds, $label)
        }
    }

    $failures = @($outcome | Where-Object { $null -ne $_.Summary } | ForEach-Object { @($_.Summary.failures) } | Where-Object { $_ })
    if ($failures.Count -gt 0) {
        Write-Host ''
        Write-Host "Failed cases: $($failures.Count)" -ForegroundColor Red
        foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    }

    $problem = @(Test-Tier1WorkerOutcome -ExpectedTest $discovery.ExpectedTest -Worker $outcome)
    if ($problem.Count -gt 0) {
        Write-Host ''
        foreach ($message in $problem) { Write-Host "Tier 1 self-check: $message" -ForegroundColor Red }
        return 1
    }

    Write-Host ''
    Write-Host ('Tier 1 self-check: all {0} cases ran exactly once in {1} on {2} workers in {3:N0}s.' -f $discovery.ExpectedTest.Count, $bundleCount, $Workers, $clock.Elapsed.TotalSeconds)
    return 0
}

Export-ModuleMember -Function Get-Tier1WorkUnit, Get-Tier1WorkBundle, Test-Tier1WorkerOutcome, Get-Tier1WorkerAssignment, Write-Tier1WorkerSummary, Invoke-Tier1ParallelSelfCheck
