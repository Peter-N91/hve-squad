# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Offline core of the live benchmark: fixture materialisation, task loading, scheduling,
# scoring, judge anonymisation and summary statistics. Nothing here calls a model, so
# every function is exercised by LiveBenchmark.Tests.ps1 without a Copilot session.

#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:Root = $PSScriptRoot
$script:Invariant = [cultureinfo]::InvariantCulture
$script:Levels = @('easy', 'medium', 'hard')
# A/B and C/D differ only in source, so each pair is a regression check; E is the economy effect against A.
# F is optional because background delivery needs a task with independent items; the easy task has three.
$script:ArmTable = [ordered]@{
    A = @{ Source = 'baseline'; Routing = ''; Delivery = '' }
    B = @{ Source = 'candidate'; Routing = ''; Delivery = '' }
    C = @{ Source = 'baseline'; Routing = 'ranked'; Delivery = '' }
    D = @{ Source = 'candidate'; Routing = 'ranked'; Delivery = '' }
    E = @{ Source = 'candidate'; Routing = 'economy'; Delivery = '' }
    F = @{ Source = 'candidate'; Routing = 'economy'; Delivery = 'background' }
}
$script:ArmNames = @($script:ArmTable.Keys)
$script:DefaultArmNames = @('A', 'B', 'C', 'D', 'E')
$script:MinimumRepeats = 8
$script:PassingVerdicts = @('Pass', 'Pass-With-Findings')
$script:OwnerExcluded = @('Squad Reviewer', 'Squad Scribe')
# Paths a run writes for the squad itself; they reveal the arm and are not the deliverable.
$script:TrackingPathspec = @(':(exclude).copilot-tracking', ':(exclude).github', ':(exclude).agents', ':(exclude)**/__pycache__', ':(exclude)*.pyc')

function Get-LiveBenchmarkLevel { $script:Levels }

function Get-BenchmarkArm { $script:ArmNames }

function Get-DefaultBenchmarkArm { $script:DefaultArmNames }

function Get-MinimumBenchmarkRepeats { $script:MinimumRepeats }

function Write-BenchmarkRepeatWarning {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Repeats)
    if ($Repeats -lt $script:MinimumRepeats) {
        Write-Warning "Results below $script:MinimumRepeats repeats per cell are indicative only."
    }
}

function Get-ArmRouting {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('A', 'B', 'C', 'D', 'E', 'F')][string]$Arm)
    $script:ArmTable[$Arm].Routing
}

function Get-ArmDelivery {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('A', 'B', 'C', 'D', 'E', 'F')][string]$Arm)
    $script:ArmTable[$Arm].Delivery
}

function Get-ArmSource {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('A', 'B', 'C', 'D', 'E', 'F')][string]$Arm)
    $script:ArmTable[$Arm].Source
}

function Get-NonBuiltinMcpServerNames {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Configuration)
    if (-not $Configuration.PSObject.Properties['mcpServers']) { throw 'Copilot MCP configuration has no mcpServers property.' }
    @($Configuration.mcpServers.PSObject.Properties | Where-Object { $_.Value.source -ne 'builtin' } | ForEach-Object Name | Sort-Object -Unique)
}

function Get-ConfiguredMcpServerNames {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CliPath)
    $json = (& $CliPath mcp list --json 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Copilot CLI could not list configured MCP servers: $CliPath" }
    Get-NonBuiltinMcpServerNames -Configuration ($json | ConvertFrom-Json -Depth 32)
}

function ConvertFrom-McpServerArgument {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Names)
    if ([string]::IsNullOrWhiteSpace($Names)) { return @() }
    @($Names.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object Trim | Sort-Object -Unique)
}

function Get-BenchmarkTask {
    <#
    .SYNOPSIS
        Loads one difficulty level's prompt, reference, hidden tests, mutants and doc check.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('easy', 'medium', 'hard')][string]$Level)

    $dir = Join-Path $script:Root "tasks/$Level"
    $spec = Get-Content -LiteralPath (Join-Path $dir 'task.json') -Raw | ConvertFrom-Json
    [pscustomobject]@{
        Level     = $Level
        Directory = $dir
        Prompt    = (Get-Content -LiteralPath (Join-Path $dir 'prompt.txt') -Raw).Trim()
        Reference = Join-Path $dir 'reference_ledger.py'
        Hidden    = Join-Path $dir 'test_hidden.py'
        Mutants   = @($spec.mutants)
        Doc       = $spec.doc
    }
}

function Get-ArmPrompt {
    <#
    .SYNOPSIS
        The level's prompt, identical across arms apart from the trailing routing token.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('easy', 'medium', 'hard')][string]$Level,
        [Parameter(Mandatory)][ValidateSet('A', 'B', 'C', 'D', 'E', 'F')][string]$Arm
    )
    $prompt = (Get-BenchmarkTask -Level $Level).Prompt
    $routing = Get-ArmRouting -Arm $Arm
    $delivery = Get-ArmDelivery -Arm $Arm
    $tokens = @()
    if ($routing) { $tokens += "routing=$routing" }
    if ($delivery) { $tokens += "delivery=$delivery" }
    if ($tokens.Count) { "$prompt $($tokens -join ' ')" } else { $prompt }
}

function Get-BenchmarkSchedule {
    <#
    .SYNOPSIS
        Deterministic, counterbalanced run order: every repeat runs every level, arms rotated through positions.
    .DESCRIPTION
        Each level gets one seeded random arm order; repeat r rotates it by r-1 places, so
        over as many repeats as there are arms each arm runs once in every position. That
        cancels time-of-day and cache-warmth drift by position, which a fresh shuffle per
        repeat does not guarantee at n=3. The same seed always yields the same schedule, so
        an interrupted matrix resumes by skipping run ids already in the results file.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Levels = $script:Levels,
        [string[]]$Arms = $script:DefaultArmNames,
        [int]$Repeats = $script:MinimumRepeats,
        [int]$Seed = 137
    )
    $rng = [System.Random]::new($Seed)
    $base = @{}
    foreach ($level in $Levels) {
        $order = [System.Collections.Generic.List[string]]::new([string[]]$Arms)
        for ($i = $order.Count - 1; $i -gt 0; $i--) {
            $j = $rng.Next($i + 1)
            $swap = $order[$i]; $order[$i] = $order[$j]; $order[$j] = $swap
        }
        $base[$level] = @($order)
    }
    $index = 0
    for ($repeat = 1; $repeat -le $Repeats; $repeat++) {
        foreach ($level in $Levels) {
            $n = $base[$level].Count
            for ($position = 1; $position -le $n; $position++) {
                $arm = $base[$level][($position - 1 + $repeat - 1) % $n]
                $index++
                [pscustomobject]@{ Index = $index; Repeat = $repeat; Level = $level; Arm = $arm; Position = $position; RunId = "$level-$arm-r$repeat" }
            }
        }
    }
}

function Invoke-Git {
    param([string]$Directory, [string[]]$Arguments)
    $output = & git -C $Directory -c core.autocrlf=false -c core.quotepath=off @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in ${Directory}: $output" }
    $output
}

function New-InventoryFixture {
    <#
    .SYNOPSIS
        Materialises a fresh git repository of the inventory fixture with a single baseline commit.
    .DESCRIPTION
        The squad seed is stored outside a `.copilot-tracking` path because this repository
        ignores that path at any depth; it is copied into place here. The repository has no
        remote, so a run cannot push anywhere.
    .OUTPUTS
        An object with Root and Commit.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Destination)

    if (Test-Path -LiteralPath $Destination) { throw "Fixture destination already exists: $Destination" }
    $source = Join-Path $script:Root 'fixtures/inventory'
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $Destination = (Resolve-Path -LiteralPath $Destination).Path
    Copy-Item -Path (Join-Path $source 'repo/*') -Destination $Destination -Recurse -Force
    $squad = Join-Path $Destination '.copilot-tracking/squad'
    New-Item -ItemType Directory -Path $squad -Force | Out-Null
    Copy-Item -Path (Join-Path $source 'squad-seed/*') -Destination $squad -Force
    Set-Content -LiteralPath (Join-Path $Destination '.gitignore') -Value "__pycache__/`n*.pyc`n.pytest_cache/" -Encoding utf8NoBOM

    $saved = @{}
    foreach ($name in 'GIT_AUTHOR_DATE', 'GIT_COMMITTER_DATE') { $saved[$name] = [Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name, '2026-10-03T14:00:00Z') }
    try {
        Invoke-Git $Destination @('init', '-q', '-b', 'master') | Out-Null
        Invoke-Git $Destination @('add', '-A') | Out-Null
        Invoke-Git $Destination @('-c', 'user.name=benchmark', '-c', 'user.email=benchmark@example.invalid', 'commit', '-q', '-m', 'baseline') | Out-Null
    }
    finally { foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) } }

    [pscustomobject]@{ Root = $Destination; Commit = ([string](Invoke-Git $Destination @('rev-parse', 'HEAD'))).Trim() }
}

function Invoke-Pytest {
    <#
    .SYNOPSIS
        Runs pytest in a child process with an optional mutant and a hard timeout.
    .DESCRIPTION
        The environment is set on the child only, so a mutant can never leak into a later
        run. The timeout protects the matrix from a delivered ledger that deadlocks.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [string]$Target = 'tests',
        [string]$Mutant = '',
        [int]$TimeoutSeconds = 120
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new('python')
    foreach ($a in @('-m', 'pytest', '-q', '-p', 'no:cacheprovider', $Target)) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $Directory
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.Environment['LEDGER_MUTANT'] = $Mutant
    $psi.Environment['PYTHONDONTWRITEBYTECODE'] = '1'
    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
    $text = $stdout.Result + $stderr.Result
    $count = { param($pattern) $m = [regex]::Match($text, "(\d+) $pattern"); if ($m.Success) { [int]$m.Groups[1].Value } else { 0 } }
    $passed = & $count 'passed'
    $failed = (& $count 'failed') + (& $count 'errors?')
    [pscustomobject]@{
        Passed   = $passed
        Failed   = $failed
        TimedOut = $timedOut
        ExitCode = if ($timedOut) { -1 } else { $process.ExitCode }
        Clean    = (-not $timedOut -and $process.ExitCode -eq 0 -and $failed -eq 0 -and $passed -gt 0)
        Output   = $text
    }
}

function Copy-PythonTree {
    param([string]$From, [string]$To)
    New-Item -ItemType Directory -Path $To -Force | Out-Null
    if (-not (Test-Path -LiteralPath $From)) { return }
    Get-ChildItem -LiteralPath $From -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/](__pycache__|\.pytest_cache)[\\/]' -and $_.Extension -ne '.pyc' } | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($From, $_.FullName)
        $target = Join-Path $To $relative
        New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
}

function New-GradeDirectory {
    param([string]$Path, [string]$LedgerFrom, [string]$SrcFrom, [string]$TestsFrom, [string]$HiddenFrom)
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
    if ($SrcFrom) { Copy-PythonTree -From $SrcFrom -To (Join-Path $Path 'src') } else { New-Item -ItemType Directory -Path (Join-Path $Path 'src') -Force | Out-Null }
    if ($LedgerFrom) { Copy-Item -LiteralPath $LedgerFrom -Destination (Join-Path $Path 'src/ledger.py') -Force }
    if ($TestsFrom) { Copy-PythonTree -From $TestsFrom -To (Join-Path $Path 'tests') } else { New-Item -ItemType Directory -Path (Join-Path $Path 'tests') -Force | Out-Null }
    if ($HiddenFrom) { Copy-Item -LiteralPath $HiddenFrom -Destination (Join-Path $Path 'tests/test_hidden.py') -Force }
    $Path
}

function Test-BenchmarkTask {
    <#
    .SYNOPSIS
        Offline validity of a level: hidden tests pass on the reference, kill every mutant, and fail on the fixture baseline.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('easy', 'medium', 'hard')][string]$Level,
        [Parameter(Mandatory)][string]$WorkRoot
    )
    $task = Get-BenchmarkTask -Level $Level
    $grade = New-GradeDirectory -Path (Join-Path $WorkRoot "validate-$Level") -LedgerFrom $task.Reference -HiddenFrom $task.Hidden
    $reference = Invoke-Pytest -Directory $grade
    $mutants = foreach ($mutant in $task.Mutants) {
        $run = Invoke-Pytest -Directory $grade -Mutant $mutant
        [pscustomobject]@{ Name = $mutant; Killed = -not $run.Clean; Failed = $run.Failed }
    }
    Copy-Item -LiteralPath (Join-Path $script:Root 'fixtures/inventory/repo/src/ledger.py') -Destination (Join-Path $grade 'src/ledger.py') -Force
    $baseline = Invoke-Pytest -Directory $grade
    [pscustomobject]@{
        Level           = $Level
        ReferencePassed = $reference.Passed
        ReferenceClean  = $reference.Clean
        Mutants         = @($mutants)
        MutantsKilled   = @($mutants | Where-Object Killed).Count
        BaselinePassed  = $baseline.Passed
        BaselineFailed  = $baseline.Failed
    }
}

function Measure-DocCheck {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace, [Parameter(Mandatory)]$Task)
    if (-not $Task.Doc) { return [pscustomobject]@{ Check = 'n/a'; Concepts = 'n/a' } }
    $path = Join-Path $Workspace $Task.Doc.path
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]@{ Check = 'missing'; Concepts = "0/$(@($Task.Doc.concepts).Count)" } }
    $text = Get-Content -LiteralPath $path -Raw
    $concepts = @($Task.Doc.concepts)
    $hits = @($concepts | Where-Object { $text -match $_.pattern }).Count
    [pscustomobject]@{ Check = $(if ($hits -eq $concepts.Count) { 'pass' } else { 'fail' }); Concepts = "$hits/$($concepts.Count)" }
}

function Get-ReviewVerdict {
    <#
    .SYNOPSIS
        The closing review verdict from the newest review file, normalised; 'none' when no review was written.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace)
    $reviews = @(Get-ChildItem -LiteralPath (Join-Path $Workspace '.copilot-tracking/reviews') -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc)
    if ($reviews.Count -eq 0) { return 'none' }
    $text = Get-Content -LiteralPath $reviews[-1].FullName -Raw
    $word = '(pass[- ]with[- ]findings|pass(?:ed)?|approved?|fail(?:ed)?|reject(?:ed)?|blocked)'
    $m = [regex]::Match($text, "(?im)verdict[^\r\n\w]*(?:\w+[^\r\n\w]+){0,3}?$word")
    if (-not $m.Success) { $m = [regex]::Match($text, "(?i)\b$word\b") }
    if (-not $m.Success) { return 'unknown' }
    switch -Regex ($m.Groups[1].Value) {
        '(?i)with' { 'Pass-With-Findings'; break }
        '(?i)^(pass|approv)' { 'Pass'; break }
        '(?i)^(fail|reject)' { 'Fail'; break }
        default { 'Blocked' }
    }
}

function Get-LedgerCheck {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace)
    $script = Get-ChildItem -LiteralPath (Join-Path $Workspace '.agents') -Recurse -Filter 'Measure-SquadLedger.ps1' -ErrorAction SilentlyContinue | Select-Object -First 1
    $squadRoot = Join-Path $Workspace '.copilot-tracking/squad'
    if (-not $script -or -not (Test-Path -LiteralPath $squadRoot)) { return 'n/a' }
    & pwsh -NoProfile -File $script.FullName -SquadRoot $squadRoot -Check *> $null
    if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }
}

function Get-TokenTotals {
    param($ModelMetrics)
    $totals = [ordered]@{ input = 0L; output = 0L; cacheRead = 0L; cacheWrite = 0L }
    if (-not $ModelMetrics) { return [pscustomobject]$totals }
    foreach ($model in $ModelMetrics.PSObject.Properties) {
        $usage = $model.Value.usage
        if (-not $usage) { continue }
        $totals.input += [long]$usage.inputTokens
        $totals.output += [long]$usage.outputTokens
        $totals.cacheRead += [long]$usage.cacheReadTokens
        $totals.cacheWrite += [long]$usage.cacheWriteTokens
    }
    [pscustomobject]$totals
}

function Get-UsageSummary {
    <#
    .SYNOPSIS
        Credits and tokens overall and per agent from the CLI's --usage-output-file.
    .DESCRIPTION
        Credits are totalNanoAiu / 1e9. `input` is the CLI's inputTokens, which already
        includes cache reads and cache writes; they are reported separately as well.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$UsagePath)
    $usage = Get-Content -LiteralPath $UsagePath -Raw | ConvertFrom-Json
    $agents = foreach ($agent in $usage.agentMetrics.PSObject.Properties) {
        $name = if ($agent.Name -eq 'main') { 'coordinator' } else { [string]$agent.Value.agentName }
        [pscustomobject]@{
            Id      = $agent.Name
            Agent   = $name
            Credits = [double]$agent.Value.totalNanoAiu / 1e9
            Models  = @($agent.Value.modelMetrics.PSObject.Properties.Name)
            Tokens  = Get-TokenTotals $agent.Value.modelMetrics
        }
    }
    [pscustomobject]@{
        Credits = [double]$usage.totalNanoAiu / 1e9
        Tokens  = Get-TokenTotals $usage.modelMetrics
        Agents  = @($agents)
    }
}

function Read-EventLog {
    param([string]$EventsPath)
    @(Get-Content -LiteralPath $EventsPath -ErrorAction SilentlyContinue | ForEach-Object { try { $_ | ConvertFrom-Json -Depth 64 } catch { Write-Debug "Skipped a non-JSON event line: $_" } } | Where-Object { $_ })
}

function Get-EventProperty {
    param($Object, [string[]]$Path)
    foreach ($name in $Path) {
        if ($null -eq $Object -or -not $Object.PSObject.Properties[$name]) { return $null }
        $Object = $Object.$name
    }
    $Object
}

function Get-EventSummary {
    <#
    .SYNOPSIS
        Dispatch and Scribe-writer signals from the CLI's JSONL event stream.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EventsPath, [int]$Seconds = 0)
    $events = Read-EventLog $EventsPath
    $starts = @($events | Where-Object { $_.type -eq 'tool.execution_start' })
    $isTop = { -not (Get-EventProperty $_ @('data', 'parentToolCallId')) }
    $tasks = @($starts | Where-Object { (Get-EventProperty $_ @('data', 'toolName')) -eq 'task' } | ForEach-Object {
            [pscustomobject]@{
                Event = $_
                Top   = -not (Get-EventProperty $_ @('data', 'parentToolCallId'))
                Agent = [string](Get-EventProperty $_ @('data', 'arguments', 'agent_type'))
                Model = [string](Get-EventProperty $_ @('data', 'arguments', 'model'))
            }
        })
    $topCommands = @($starts | Where-Object $isTop | ForEach-Object { [string](Get-EventProperty $_ @('data', 'arguments', 'command')) })

    $handoff = $null
    $review = @($tasks | Where-Object Agent -EQ 'Squad Reviewer' | Select-Object -Last 1 | ForEach-Object Event)
    if ($review.Count -and $events.Count -and $Seconds -gt 0) {
        $id = Get-EventProperty $review[0] @('data', 'toolCallId')
        $done = @($events | Where-Object { $_.type -eq 'tool.execution_complete' -and (Get-EventProperty $_ @('data', 'toolCallId')) -eq $id } | Select-Object -First 1)
        $first = @($events | Where-Object { Get-EventProperty $_ @('timestamp') } | Select-Object -First 1)
        if ($done.Count -and (Get-EventProperty $done[0] @('timestamp')) -and $first.Count) {
            $handoff = [int]($Seconds - ([datetime]$done[0].timestamp - [datetime]$first[0].timestamp).TotalSeconds)
        }
    }
    $dispatchModels = @{}
    foreach ($t in $tasks | Where-Object { $_.Agent -and $_.Model }) {
        if (-not $dispatchModels.ContainsKey($t.Agent)) { $dispatchModels[$t.Agent] = [System.Collections.Generic.List[string]]::new() }
        if (-not $dispatchModels[$t.Agent].Contains($t.Model)) { $dispatchModels[$t.Agent].Add($t.Model) }
    }
    [pscustomobject]@{
        Dispatches        = @($tasks | Where-Object Top).Count
        DispatchesAll     = $tasks.Count
        ScribeDispatches  = @($tasks | Where-Object Agent -EQ 'Squad Scribe').Count
        OwnerDispatches   = @($tasks | Where-Object { $_.Agent -like 'Squad *' -and $_.Agent -notin $script:OwnerExcluded }).Count
        GenericDispatches = @($tasks | Where-Object Agent -NotLike 'Squad *').Count
        CoordScriptRuns   = @($topCommands | Where-Object { $_ -match 'Write-SquadHandoff' }).Count
        BriefRan          = [bool](@($topCommands | Where-Object { $_ -match 'Get-SquadDispatchBrief' }).Count)
        HandoffSeconds    = $handoff
        DispatchModels    = $dispatchModels
    }
}

function Get-StopCause {
    <#
    .SYNOPSIS
        Best-effort reason a run stopped before normal squad completion.
    .DESCRIPTION
        Detection precedence is intentional and first-match wins:
        1. intake-escalation: the squad state records an open escalation mentioning intake.
        2. handoff-failure: a Write-SquadHandoff tool call failed; include its exit code when present.
        3. ledger-crash: Measure-SquadLedger appears with exception/crash wording.
        4. rate-limit: stderr or events mention HTTP 403/429 throttling or rate limits.
        5. cli-error: the top-level Copilot CLI process returned a non-zero exit code.
        6. none: no stop signal and the run dispatched an owner with a zero exit code.
        7. unknown: halted or inline/early stop with no recognized signal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TrialRoot,
        [int]$ExitCode = 0,
        [string]$Outcome = 'dispatched'
    )

    $out = Join-Path $TrialRoot 'out'
    $workspace = Join-Path $TrialRoot 'workspace'
    $eventsPath = Join-Path $out 'events.jsonl'
    $stderrPath = Join-Path $out 'stderr.txt'
    $events = Read-EventLog $eventsPath
    $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
    $eventText = if (Test-Path -LiteralPath $eventsPath) { Get-Content -LiteralPath $eventsPath -Raw } else { '' }
    $text = "$stderr`n$eventText"

    $statePath = Join-Path $workspace '.copilot-tracking/squad/state.json'
    if (Test-Path -LiteralPath $statePath) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -Depth 32
            if ($state.PSObject.Properties['openEscalations']) {
                $escalations = ($state.openEscalations | ConvertTo-Json -Depth 16 -Compress)
                if ($escalations -match '(?i)intake') { return 'intake-escalation' }
            }
        }
        catch { Write-Debug "Could not parse squad state for stop cause: $_" }
    }

    $handoffIds = @($events | Where-Object {
            $_.type -eq 'tool.execution_start' -and
            ([string](Get-EventProperty $_ @('data', 'arguments', 'command'))) -match 'Write-SquadHandoff'
        } | ForEach-Object { [string](Get-EventProperty $_ @('data', 'toolCallId')) })
    foreach ($event in @($events | Where-Object { $_.type -eq 'tool.execution_complete' -and $handoffIds -contains [string](Get-EventProperty $_ @('data', 'toolCallId')) })) {
        $exit = Get-EventProperty $event @('data', 'exitCode')
        if ($null -eq $exit) { $exit = Get-EventProperty $event @('data', 'result', 'exitCode') }
        $success = Get-EventProperty $event @('data', 'success')
        if (($null -ne $exit -and [int]$exit -ne 0) -or ($null -ne $success -and -not [bool]$success)) {
            if ($null -ne $exit) { return "handoff-failure (exit $([int]$exit))" }
            return 'handoff-failure'
        }
    }
    $m = [regex]::Match($text, '(?is)Write-SquadHandoff.*?exit(?:ed)?(?: code)?\s*(\d+)')
    if ($m.Success) { return "handoff-failure (exit $($m.Groups[1].Value))" }
    if ($text -match '(?is)Write-SquadHandoff.*?(failed|error)') { return 'handoff-failure' }

    if ($text -match '(?is)Measure-SquadLedger.*?(exception|runtimeexception|parsererror|traceback|crash)') { return 'ledger-crash' }
    if ($text -match '(?is)(HTTP\s*(403|429).*?(throttl|rate limit)|(throttl|rate limit).*?HTTP\s*(403|429)|\b(403|429)\b.*?(throttl|rate limit)|rate limit(ed)?|too many requests)') { return 'rate-limit' }
    if ($ExitCode -ne 0) { return 'cli-error' }
    if ($Outcome -eq 'dispatched') { return 'none' }
    'unknown'
}

function Get-TeamRouting {
    <#
    .SYNOPSIS
        The `Model routing:` mode (off when absent) and the roster rows, including any Model column, from team.md.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TeamPath)
    if (-not (Test-Path -LiteralPath $TeamPath)) { return [pscustomobject]@{ Mode = 'n/a'; Rows = @() } }
    $lines = @(Get-Content -LiteralPath $TeamPath)
    $mode = 'off'
    foreach ($line in $lines) { if ($line -match '^\s*Model routing:\s*`?(\w+)') { $mode = $Matches[1].ToLowerInvariant(); break } }
    $first = [array]::FindIndex([string[]]$lines, [Predicate[string]] { param($l) $l -match '^\s*\|' })
    $tableLines = @()
    if ($first -ge 0) { for ($i = $first; $i -lt $lines.Count -and $lines[$i] -match '^\s*\|'; $i++) { $tableLines += $lines[$i] } }
    $rows = @()
    if ($tableLines.Count -ge 2) {
        $split = { param($l) @(($l.Trim().Trim('|')) -split '\|' | ForEach-Object { $_.Trim().Trim('`') }) }
        $header = & $split $tableLines[0]
        foreach ($line in $tableLines | Select-Object -Skip 2) {
            $cells = & $split $line
            $row = [ordered]@{}
            for ($i = 0; $i -lt $header.Count; $i++) { $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' } }
            $rows += [pscustomobject]$row
        }
    }
    [pscustomobject]@{ Mode = $mode; Rows = $rows }
}

function Get-ModelAssignment {
    <#
    .SYNOPSIS
        Per dispatched agent: role, models it actually ran on, the team.md Model cell, the model the coordinator passed, and whether they match.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Usage, [Parameter(Mandatory)]$Team, $DispatchModels = @{})
    foreach ($agent in $Usage.Agents) {
        $row = $null
        if ($agent.Agent -ne 'coordinator') {
            $row = @($Team.Rows | Where-Object {
                    ($_.PSObject.Properties['Primary'] -and $_.Primary -eq $agent.Agent) -or
                    ($_.PSObject.Properties['Alternate Agents'] -and (($_.'Alternate Agents' -split ',\s*') -contains $agent.Agent))
                } | Select-Object -First 1)
            $row = if ($row.Count) { $row[0] } else { $null }
        }
        $cell = if ($row -and $row.PSObject.Properties['Model']) { [string]$row.Model } else { '' }
        if ($cell -in '—', '-') { $cell = '' }
        $passed = if ($DispatchModels.ContainsKey($agent.Agent)) { @($DispatchModels[$agent.Agent]) } else { @() }
        $match = if (-not $cell) { 'n/a' }
        elseif ($agent.Models.Count -eq 1 -and $agent.Models[0] -eq $cell) { 'yes' }
        elseif ($agent.Models -contains $cell) { 'mixed' }
        else { 'no' }
        [pscustomobject]@{
            role        = if ($agent.Agent -eq 'coordinator') { 'coordinator' } elseif ($row -and $row.PSObject.Properties['Role']) { $row.Role } else { $agent.Agent }
            agent       = $agent.Agent
            modelsUsed  = $agent.Models -join '+'
            modelCell   = $cell
            passedModel = $passed -join '+'
            match       = $match
            credits     = [math]::Round($agent.Credits, 2)
            input       = $agent.Tokens.input
            output      = $agent.Tokens.output
            cacheRead   = $agent.Tokens.cacheRead
            cacheWrite  = $agent.Tokens.cacheWrite
        }
    }
}

function Get-DeliverableDiff {
    <#
    .SYNOPSIS
        Unified diff of everything a run changed outside the squad's own tracking and install trees.
    .DESCRIPTION
        Uses a throwaway index so the scratch workspace's own index is untouched and new
        files are included without `git add` side effects.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace, [Parameter(Mandatory)][string]$BaselineCommit)
    $index = Join-Path ([IO.Path]::GetTempPath()) ("lb-index-" + [guid]::NewGuid().ToString('N'))
    $saved = $env:GIT_INDEX_FILE
    $env:GIT_INDEX_FILE = $index
    try {
        Invoke-Git $Workspace @('read-tree', $BaselineCommit) | Out-Null
        Invoke-Git $Workspace (@('add', '-A', '--', '.') + $script:TrackingPathspec) | Out-Null
        (Invoke-Git $Workspace (@('diff', '--cached', '--no-color', '--no-ext-diff', $BaselineCommit, '--', '.') + $script:TrackingPathspec)) -join "`n"
    }
    finally {
        $env:GIT_INDEX_FILE = $saved
        Remove-Item -LiteralPath $index -Force -ErrorAction SilentlyContinue
    }
}

function Format-Number {
    param($Value, [int]$Digits = 2)
    if ($null -eq $Value -or ($Value -is [string] -and $Value -eq '')) { return '' }
    ([math]::Round([double]$Value, $Digits)).ToString($script:Invariant)
}

function ConvertFrom-InvariantNumber {
    param([string]$Text)
    $value = 0.0
    if ([double]::TryParse($Text, [System.Globalization.NumberStyles]::Float, $script:Invariant, [ref]$value)) { $value } else { $null }
}

function Measure-LiveBenchmarkRun {
    <#
    .SYNOPSIS
        Scores one finished run directory and returns its results row.
    .DESCRIPTION
        Expects <TrialRoot>/workspace and <TrialRoot>/out/{metadata,result,usage}.json and
        events.jsonl, as Invoke-LiveBenchmarkRun.ps1 writes them. Writes out/score.json and
        out/deliverable.diff. Numbers are formatted with the invariant culture so the CSV
        reads the same on every machine.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TrialRoot)

    $out = Join-Path $TrialRoot 'out'
    $workspace = Join-Path $TrialRoot 'workspace'
    $meta = Get-Content -LiteralPath (Join-Path $out 'metadata.json') -Raw | ConvertFrom-Json
    $result = Get-Content -LiteralPath (Join-Path $out 'result.json') -Raw | ConvertFrom-Json
    $task = Get-BenchmarkTask -Level $meta.level
    $grade = Join-Path $TrialRoot 'grade'

    $hidden = Invoke-Pytest -Directory (New-GradeDirectory -Path (Join-Path $grade 'hidden') -SrcFrom (Join-Path $workspace 'src') -HiddenFrom $task.Hidden)
    $referenceHidden = Invoke-Pytest -Directory (New-GradeDirectory -Path (Join-Path $grade 'hidden-reference') -LedgerFrom $task.Reference -HiddenFrom $task.Hidden)
    $mutantDir = New-GradeDirectory -Path (Join-Path $grade 'owner-on-reference') -LedgerFrom $task.Reference -TestsFrom (Join-Path $workspace 'tests')
    $onReference = Invoke-Pytest -Directory $mutantDir
    # Mutants only mean something against tests that pass on the reference; otherwise they are not scored.
    $killed = 'skipped'
    if ($onReference.Clean) { $killed = 0; foreach ($mutant in $task.Mutants) { if (-not (Invoke-Pytest -Directory $mutantDir -Mutant $mutant).Clean) { $killed++ } } }
    $own = Invoke-Pytest -Directory $workspace
    $doc = Measure-DocCheck -Workspace $workspace -Task $task

    $usagePath = Join-Path $out 'usage.json'
    $usage = if (Test-Path -LiteralPath $usagePath) { Get-UsageSummary -UsagePath $usagePath } else { [pscustomobject]@{ Credits = $null; Tokens = [pscustomobject]@{ input = $null; output = $null; cacheRead = $null; cacheWrite = $null }; Agents = @() } }
    $events = Get-EventSummary -EventsPath (Join-Path $out 'events.jsonl') -Seconds ([int]$result.seconds)
    $team = Get-TeamRouting -TeamPath (Join-Path $workspace '.copilot-tracking/squad/team.md')
    $assignment = @(Get-ModelAssignment -Usage $usage -Team $team -DispatchModels $events.DispatchModels)
    $sumCredits = { param($filter) $total = 0.0; foreach ($a in @($usage.Agents | Where-Object $filter)) { $total += $a.Credits }; $total }
    $coord = @($usage.Agents | Where-Object Agent -EQ 'coordinator')
    $withCells = @($assignment | Where-Object match -NE 'n/a')

    $diff = Get-DeliverableDiff -Workspace $workspace -BaselineCommit $meta.baselineCommit
    Set-Content -LiteralPath (Join-Path $out 'deliverable.diff') -Value $diff -Encoding utf8NoBOM
    $verdict = Get-ReviewVerdict -Workspace $workspace
    $hiddenAllPass = ($hidden.Clean -and $hidden.Passed -eq $referenceHidden.Passed)

    $outcome = if ($events.OwnerDispatches -gt 0) { 'dispatched' } elseif ($diff -match '(?m)^diff --git a/(src|tests|docs)/') { 'inline' } else { 'halted' }

    $row = [pscustomobject][ordered]@{
        runId             = $meta.runId
        level             = $meta.level
        arm               = $meta.arm
        repeat            = $meta.repeat
        position          = $meta.position
        trial             = $TrialRoot
        exitCode          = $result.exitCode
        seconds           = $result.seconds
        # halted: no owner ran and no deliverable path changed (scratch files left by the coordinator do not count).
        outcome           = $outcome
        stopCause         = Get-StopCause -TrialRoot $TrialRoot -ExitCode ([int]$result.exitCode) -Outcome $outcome
        ownerDispatches   = $events.OwnerDispatches
        credits           = Format-Number $usage.Credits
        coordCr           = Format-Number $(if ($coord.Count) { $coord[0].Credits })
        ownerCr           = Format-Number (& $sumCredits { $_.Agent -ne 'coordinator' -and $_.Agent -notin $script:OwnerExcluded })
        reviewCr          = Format-Number (& $sumCredits { $_.Agent -eq 'Squad Reviewer' })
        scribeCr          = Format-Number (& $sumCredits { $_.Agent -eq 'Squad Scribe' })
        inputTokens       = $usage.Tokens.input
        outputTokens      = $usage.Tokens.output
        cacheReadTokens   = $usage.Tokens.cacheRead
        cacheWriteTokens  = $usage.Tokens.cacheWrite
        coordInputTokens  = if ($coord.Count) { $coord[0].Tokens.input } else { $null }
        coordOutputTokens = if ($coord.Count) { $coord[0].Tokens.output } else { $null }
        dispatches        = $events.Dispatches
        dispatchesAll     = $events.DispatchesAll
        scribeDispatches  = $events.ScribeDispatches
        genericDispatches = $events.GenericDispatches
        coordScriptRuns   = $events.CoordScriptRuns
        handoffSeconds    = $events.HandoffSeconds
        briefRan          = $events.BriefRan
        routingMode       = $team.Mode
        modelCells        = (@($team.Rows | Where-Object { $_.PSObject.Properties['Model'] -and $_.Model -and $_.Model -notin '—', '-' } | ForEach-Object { "$($_.Role)=$($_.Model)" }) -join ';')
        modelMatch        = if ($withCells.Count) { "$(@($withCells | Where-Object match -EQ 'yes').Count)/$($withCells.Count)" } else { 'n/a' }
        hiddenPassed      = $hidden.Passed
        hiddenTotal       = $referenceHidden.Passed
        hiddenAllPass     = $hiddenAllPass
        # A hidden-test pass the squad's own reviewer failed is not a completed run.
        completed         = ($hiddenAllPass -and $verdict -in $script:PassingVerdicts)
        ownTestsPass      = $own.Clean
        testsOnReference  = $onReference.Clean
        mutantsKilled     = $killed
        mutantsTotal      = $task.Mutants.Count
        docCheck          = $doc.Check
        docConcepts       = $doc.Concepts
        reviewVerdict     = $verdict
        ledgerCheck       = Get-LedgerCheck -Workspace $workspace
        model             = $meta.requestedModel
        cliVersion        = ([string]$meta.cliVersion -split '\r?\n')[0].Trim()
        srcTreeHash       = $meta.srcTreeHash
        installed         = [bool]($meta.PSObject.Properties['installed'] -and $meta.installed)
        agentsJson        = ConvertTo-Json -InputObject $assignment -Compress -Depth 4
    }
    $row | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $out 'score.json') -Encoding utf8NoBOM
    $row
}

function Get-SourceTreeHash {
    <#
    .SYNOPSIS
        One SHA-256 over every file's relative path and content hash, so a run records exactly which squad source it ran.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $lines = Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object { [IO.Path]::GetRelativePath($Path, $_.FullName).Replace('\', '/') } -Culture ([cultureinfo]::InvariantCulture) | ForEach-Object {
        '{0} {1}' -f [IO.Path]::GetRelativePath($Path, $_.FullName).Replace('\', '/'), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Protect-DeliverableText {
    <#
    .SYNOPSIS
        Removes anything in a deliverable that could reveal which arm produced it.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text, [string[]]$Literal = @())
    foreach ($value in $Literal | Where-Object { $_ } | Sort-Object Length -Descending) { $Text = $Text.Replace($value, '<redacted>') }
    $Text = [regex]::Replace($Text, '(?i)routing\s*=\s*\w+', 'routing=<redacted>')
    $Text = [regex]::Replace($Text, '(?im)^([+\- ]?)Model routing:.*$', '$1Model routing: <redacted>')
    $Text = [regex]::Replace($Text, '(?i)\b(claude|gpt|gemini|grok|o\d)-[\w.\-]+', '<model>')
    $Text = [regex]::Replace($Text, '(?i)[a-z]:\\[^\s''"`)]+', '<path>')
    $Text = [regex]::Replace($Text, '(?i)\b(arm|variant)[ _-]?[A-F]\b', '<arm>')
    $Text = [regex]::Replace($Text, '(?i)\b(easy|medium|hard)-[A-F]-r\d+\b', '<run>')
    $Text
}

function Export-JudgeSample {
    <#
    .SYNOPSIS
        Anonymises and shuffles one level's deliverable diffs into S1..Sn files and writes the key separately.
    .OUTPUTS
        The key: sample id to run id.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Runs,
        [Parameter(Mandatory)][string]$SampleDirectory,
        [Parameter(Mandatory)][string]$KeyPath,
        [int]$Seed = 137
    )
    if ([IO.Path]::GetFullPath($KeyPath).StartsWith([IO.Path]::GetFullPath($SampleDirectory), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The judge key must live outside the sample directory the judge can read.'
    }
    New-Item -ItemType Directory -Path $SampleDirectory -Force | Out-Null
    $order = [System.Collections.Generic.List[object]]::new([object[]]$Runs)
    $rng = [System.Random]::new($Seed)
    for ($i = $order.Count - 1; $i -gt 0; $i--) { $j = $rng.Next($i + 1); $swap = $order[$i]; $order[$i] = $order[$j]; $order[$j] = $swap }
    $key = [ordered]@{}
    for ($i = 0; $i -lt $order.Count; $i++) {
        $run = $order[$i]
        $id = "S$($i + 1)"
        $text = if ($run.DiffPath -and (Test-Path -LiteralPath $run.DiffPath)) { Get-Content -LiteralPath $run.DiffPath -Raw } else { '' }
        $literal = @($run.RunId, $run.TrialRoot, (Split-Path -Leaf ([string]$run.TrialRoot)))
        Set-Content -LiteralPath (Join-Path $SampleDirectory "$id.diff") -Value (Protect-DeliverableText -Text $text -Literal $literal) -Encoding utf8NoBOM
        $key[$id] = $run.RunId
    }
    New-Item -ItemType Directory -Path (Split-Path $KeyPath) -Force | Out-Null
    $key | ConvertTo-Json | Set-Content -LiteralPath $KeyPath -Encoding utf8NoBOM
    [pscustomobject]$key
}

function Read-JudgeScore {
    <#
    .SYNOPSIS
        Extracts the judge's {"samples":[...]} JSON from a file or free text (fenced or bare).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($Text, '```(?:json)?\s*(\{[\s\S]*?\})\s*```')) { $candidates.Add($m.Groups[1].Value) }
    $start = $Text.IndexOf('{'); $end = $Text.LastIndexOf('}')
    if ($start -ge 0 -and $end -gt $start) { $candidates.Add($Text.Substring($start, $end - $start + 1)) }
    foreach ($candidate in $candidates) {
        try { $json = $candidate | ConvertFrom-Json -Depth 16 } catch { continue }
        if ($json.PSObject.Properties['samples']) { return @($json.samples) }
    }
    throw 'No judge JSON with a "samples" array was found.'
}

function Merge-JudgeScore {
    <#
    .SYNOPSIS
        De-anonymises judge scores through the key and returns one row per run id.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Samples, [Parameter(Mandatory)]$Key)
    $lookup = @{}
    foreach ($p in $Key.PSObject.Properties) { $lookup[$p.Name] = $p.Value }
    foreach ($sample in $Samples) {
        if (-not $lookup.ContainsKey([string]$sample.id)) { throw "Judge returned unknown sample id '$($sample.id)'." }
        $score = { param($name) $c = $sample.PSObject.Properties[$name]; if ($c -and $null -ne $c.Value -and $c.Value.PSObject.Properties['score'] -and $null -ne $c.Value.score) { [double]$c.Value.score } else { $null } }
        $values = [ordered]@{ correctness = & $score 'correctness'; tests = & $score 'tests'; design = & $score 'design'; docs = & $score 'docs' }
        $present = @($values.Values | Where-Object { $null -ne $_ })
        [pscustomobject]@{
            runId            = $lookup[[string]$sample.id]
            sample           = [string]$sample.id
            judgeCorrectness = $values.correctness
            judgeTests       = $values.tests
            judgeDesign      = $values.design
            judgeDocs        = $values.docs
            judgeMean        = if ($present.Count) { [math]::Round(($present | Measure-Object -Average).Average, 2) } else { $null }
        }
    }
}

function Invoke-BenchmarkJudgeAndReport {
    <#
    .SYNOPSIS
        Runs the blind judge unless skipped, then writes the Markdown report.
    .DESCRIPTION
        Kept in the offline module so tests can inject a stub judge script. The live
        harness calls this only after the matrix has finished writing results.csv.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResultRoot,
        [string[]]$Levels = $script:Levels,
        [int]$Seed = 137,
        [switch]$SkipJudge,
        [string]$JudgeScript = (Join-Path $script:Root 'Invoke-BlindJudge.ps1'),
        [string]$ReportScript = (Join-Path $script:Root 'New-BenchmarkReport.ps1'),
        [string]$ReportPath = (Join-Path $ResultRoot 'report.md')
    )
    $ResultRoot = (Resolve-Path -LiteralPath $ResultRoot).Path
    $resultsCsv = Join-Path $ResultRoot 'results.csv'
    if (-not (Test-Path -LiteralPath $resultsCsv)) { throw "No results.csv in $ResultRoot" }

    $reportCsv = $resultsCsv
    $judgeInvoked = $false
    if (-not $SkipJudge) {
        $judgeInvoked = $true
        & $JudgeScript -ResultRoot $ResultRoot -Levels $Levels -Seed $Seed
        $judgedCsv = Join-Path $ResultRoot 'results-judged.csv'
        if (Test-Path -LiteralPath $judgedCsv) {
            $reportCsv = $judgedCsv
        }
        else {
            Write-Warning "Judge did not write $judgedCsv; reporting unjudged results."
        }
    }

    & $ReportScript -ResultsCsv $reportCsv -OutFile $ReportPath
    [pscustomobject]@{
        ResultRoot   = $ResultRoot
        ResultsCsv   = $resultsCsv
        ReportCsv    = $reportCsv
        ReportPath   = $ReportPath
        JudgeInvoked = $judgeInvoked
    }
}

function Get-Median {
    param([double[]]$Values)
    $sorted = @($Values | Where-Object { $null -ne $_ } | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    $mid = [int][math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2) { $sorted[$mid] } else { ($sorted[$mid - 1] + $sorted[$mid]) / 2 }
}

function Get-BootstrapMedianInterval {
    <#
    .SYNOPSIS
        Percentile bootstrap interval for a median, seeded so a report is reproducible.
    .OUTPUTS
        An object with Low and High, or $null for fewer than two values.
    #>
    [CmdletBinding()]
    param([double[]]$Values, [int]$Resamples = 2000, [double]$Level = 0.95, [int]$Seed = 137)
    $data = @($Values | Where-Object { $null -ne $_ })
    if ($data.Count -lt 2) { return $null }
    $rng = [System.Random]::new($Seed)
    $medians = [double[]]::new($Resamples)
    $sample = [double[]]::new($data.Count)
    for ($r = 0; $r -lt $Resamples; $r++) {
        for ($i = 0; $i -lt $data.Count; $i++) { $sample[$i] = $data[$rng.Next($data.Count)] }
        $medians[$r] = Get-Median $sample
    }
    [array]::Sort($medians)
    $tail = (1 - $Level) / 2
    [pscustomobject]@{
        Low  = $medians[[int][math]::Floor($tail * ($Resamples - 1))]
        High = $medians[[int][math]::Ceiling((1 - $tail) * ($Resamples - 1))]
    }
}

Export-ModuleMember -Function Get-LiveBenchmarkLevel, Get-BenchmarkArm, Get-DefaultBenchmarkArm, Get-MinimumBenchmarkRepeats, Write-BenchmarkRepeatWarning, Get-ArmRouting, Get-ArmDelivery, Get-ArmSource, Get-BenchmarkTask, Get-ArmPrompt, Get-BenchmarkSchedule,
New-InventoryFixture, Invoke-Pytest, Test-BenchmarkTask, Measure-DocCheck, Get-ReviewVerdict, Get-LedgerCheck, Get-StopCause,
Get-UsageSummary, Get-EventSummary, Get-TeamRouting, Get-ModelAssignment, Get-DeliverableDiff, Measure-LiveBenchmarkRun,
Get-SourceTreeHash, Protect-DeliverableText, Export-JudgeSample, Read-JudgeScore, Merge-JudgeScore, Invoke-BenchmarkJudgeAndReport, Get-Median, Get-BootstrapMedianInterval,
Format-Number, ConvertFrom-InvariantNumber, Get-NonBuiltinMcpServerNames, Get-ConfiguredMcpServerNames, ConvertFrom-McpServerArgument
