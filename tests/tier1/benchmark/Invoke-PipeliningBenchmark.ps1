#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Paired BEFORE/AFTER live timed benchmark: sequential vs. pipelined Scribe hand-offs.
.DESCRIPTION
    Routing-performance plan, Amendment 1 "Benchmark Protocol", Amendment 2 (S11 /
    R10 / RC12 / Condition 7-8 / Residual 8), Amendment 3 S5 Unit U5, tasks
    P04-T02..T06. This driver is opt-in and lives outside tests/tier1/scenarios/ (it
    is not part of the auto-discovered Tier 1 matrix run by Invoke-Tier1LiveRun.ps1)
    because it spends a live BEFORE/AFTER comparison rather than a single scenario
    pass: it runs the SAME scenario/fixture/pinned model against two isolated
    installs -- BEFORE (the merge-base of HEAD and main, in its own git worktree) and
    AFTER (a snapshot of the current, possibly-uncommitted working tree) -- and
    classifies whether the AFTER arm's Scribe Hand-off Pipelining contract measurably
    changed wall-clock time versus the BEFORE arm's sequential hand-offs.

    Each run's independent overlap evidence, write-completeness, and elapsed time are
    read from disk and from the CLI's own machine-readable output (--output-format
    json, --log-dir, --usage-output-file), never from the model's own transcript
    claim. Classification (gain / inconclusive / no-gain), the AFTER-only void rule,
    the >1-void-forces-inconclusive rule, and the data-sufficiency safeguard all live
    in PipeliningClassification.psm1 and are unit-tested offline by
    PipeliningClassification.Tests.ps1 -- this script only measures and orchestrates.

    Hygiene (Amendment 3 S5 U5, human-run instructions, extended E8 deny list):
    every run denies `git push`, `git remote add`, `gh`, every delete-shaped shell
    verb (Remove-Item/rm/del/rd/rmdir/erase), every network-fetch shell verb
    (Invoke-WebRequest/Invoke-RestMethod/curl/wget), `Start-Process`, `git clean`, and
    `git reset`; strips GH_TOKEN/GITHUB_TOKEN/GH_ENTERPRISE_TOKEN from the child
    process environment and sets GIT_TERMINAL_PROMPT=0; every scratch workspace is
    git-initialized with no remote; results land under -ResultRoot (default
    %TEMP%\rp-bench), never inside the repository; and the report is scanned for
    secret-shaped strings (ghp_/gho_/ghu_/ghs_/ghr_/github_pat_, bearer/AKIA shapes)
    before -CopyReportTo copies anything into the repository -- a scan failure is
    fail-closed and the copy is refused.

    No squad Cost Preflight ceiling is ever configured in either arm's turns (the
    comparison isolates hand-off pipelining from pending-reservation admission --
    this run's human decision). The only spend limit is this harness's
    own -CostCeilingUsd, checked between runs via Test-CostPrecheck, independent of
    anything the squad's own state tracks.

    KNOWN LIMITATIONS, undocumented upstream and NOT empirically validated against a
    real run because COPILOT_GITHUB_TOKEN was unavailable in the authoring
    environment (see the change record for the full account):
      * The exact JSONL event shape `--output-format json` emits for tool-call
        start/complete pairs is undocumented. Get-OverlapEvidence below is a
        best-effort heuristic over plausible field names (type/event, tool/name/
        agent, start/end timestamps) and corroborates against --log-dir when the
        JSONL yields no candidate events. Because the AFTER-only void rule already
        treats "no independently observed overlap" as void, a parser that under-
        detects overlap can only bias the classification toward no-gain/void/
        inconclusive, never manufacture a false gain -- but its positive detections
        have not been checked against a real transcript. The single smoke run this
        script performs before spending on the full design exists specifically to
        catch this: if the smoke's overlap count is suspiciously always 0, that must
        be treated as "parser or design problem" and investigated, per the
        dispatch's own instruction, not spent through.
      * The exact --deny-tool pattern-matching semantics (prefix vs. exact match,
        whether a PowerShell cmdlet name and its command-line alias are matched by
        the same pattern) could not be confirmed live. Get-BenchmarkDenyToolList
        below lists both the POSIX and PowerShell spellings of every denied verb as
        a best-effort, defense-in-depth measure; it is not a substitute for the
        harness's own hygiene (scratch workspace with no remote, stripped tokens,
        results outside the repo, fail-closed secret scan).
.PARAMETER SourceRoot
    Repository root to benchmark. Defaults to the repository containing this script.
.PARAMETER BeforeRef
    Override for the BEFORE arm's ref. Defaults to `git merge-base HEAD main`,
    computed and recorded before either arm runs.
.PARAMETER Scenario
    Tier 1 scenario id to run in both arms. Defaults to 'autopilot-pipelining'
    (P04-T01), the scenario this benchmark exists to exercise.
.PARAMETER Model
    Pinned model for every run in both arms. Defaults to claude-sonnet-5.
.PARAMETER ResultRoot
    Directory for report.md/report.json and per-run evidence. Defaults to
    %TEMP%\rp-bench. Never a path inside the repository.
.PARAMETER WorkspaceRoot
    Directory to provision the BEFORE worktree, the AFTER snapshot, and every
    per-run scratch workspace under. Defaults to a fresh directory under the temp
    directory.
.PARAMETER TargetN
    Target run count per arm. Defaults to 3 (Amendment 1's N-sizing target).
.PARAMETER CostCeilingUsd
    Harness spend ceiling (the human-settled 150 USD limit), independent of any
    squad Cost Preflight ceiling, which is never configured in this run's turns.
.PARAMETER EstimatedCostPerRunUsd
    Pre-run cost estimate per single scenario run, used by the harness precheck
    between runs (Test-CostPrecheck) and by the N=2 downgrade decision
    (Get-NDowngradeDecision). Required unless -ProvisionOnly or -SmokeOnly is used
    for plumbing verification only.
.PARAMETER TimeoutMinutes
    Per-turn timeout, same convention as Invoke-Tier1LiveRun.ps1.
.PARAMETER CopyReportTo
    Path under .copilot-tracking/ to copy the scanned report to, once the
    fail-closed secret scan passes. Optional; when omitted, the report is written
    only under -ResultRoot.
.PARAMETER ProvisionOnly
    Build the BEFORE worktree, the AFTER snapshot, and one scratch workspace per arm,
    then stop before the first turn. Spends no Copilot requests and needs no token.
.PARAMETER SmokeOnly
    Run exactly one AFTER-arm run (no BEFORE run) and report its overlap evidence,
    then stop. This is the single cheap smoke run the dispatch requires before the
    full paired design is spent: if it shows 0 independently-observed overlaps, the
    full design is a guaranteed void and must not be run.
.EXAMPLE
    ./Invoke-PipeliningBenchmark.ps1 -SourceRoot . -ProvisionOnly
.EXAMPLE
    ./Invoke-PipeliningBenchmark.ps1 -SourceRoot . -SmokeOnly -EstimatedCostPerRunUsd 2.0
.EXAMPLE
    ./Invoke-PipeliningBenchmark.ps1 -SourceRoot . -EstimatedCostPerRunUsd 2.0
#>
[CmdletBinding()]
param(
    [string]$SourceRoot,

    [string]$BeforeRef,

    [string]$Scenario = 'autopilot-pipelining',

    [string]$Model = 'claude-sonnet-5',

    [string]$ResultRoot,

    [string]$WorkspaceRoot,

    [int]$TargetN = 3,

    [double]$CostCeilingUsd = 150.0,

    [double]$EstimatedCostPerRunUsd,

    [int]$TimeoutMinutes = 20,

    [string]$CopyReportTo,

    [switch]$ProvisionOnly,

    [switch]$SmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' 'SquadRun.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'PipeliningClassification.psm1') -Force

if (-not $SourceRoot) { $SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path }
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path

if (-not $ProvisionOnly) {
    if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
        throw "The 'copilot' CLI was not found on PATH. Install @github/copilot at a pinned version first."
    }
    # Fails fast on the missing secret rather than on the CLI's generic
    # authentication error, matching Invoke-Tier1LiveRun.ps1's own convention.
    if (-not $env:COPILOT_GITHUB_TOKEN) {
        throw 'COPILOT_GITHUB_TOKEN is not set. This benchmark needs a token carrying the Copilot Requests permission. Do not source one via gh -- that tool is on this run''s deny list and out of scope for this harness to obtain credentials through.'
    }
    if (-not $ProvisionOnly -and -not $SmokeOnly -and -not $PSBoundParameters.ContainsKey('EstimatedCostPerRunUsd')) {
        throw '-EstimatedCostPerRunUsd is required for a live paired run (used by the harness cost precheck and the N=2 downgrade decision). Supply it, or use -ProvisionOnly / -SmokeOnly for plumbing verification only.'
    }
}

if (-not $ResultRoot) { $ResultRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'rp-bench' }
New-Item -ItemType Directory -Path $ResultRoot -Force | Out-Null
$ResultRoot = (Resolve-Path -LiteralPath $ResultRoot).Path

if (-not $WorkspaceRoot) {
    $WorkspaceRoot = Join-Path ([System.IO.Path]::GetTempPath()) "rp-bench-work-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
}
New-Item -ItemType Directory -Path $WorkspaceRoot -Force | Out-Null
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path

$fixtureRoot = Join-Path $PSScriptRoot '..' 'fixtures'
$scenarioFile = Join-Path $PSScriptRoot '..' 'scenarios' "$Scenario.json"
if (-not (Test-Path -LiteralPath $scenarioFile)) { throw "Scenario '$Scenario' not found at $scenarioFile." }
$definition = Get-Content -LiteralPath $scenarioFile -Raw | ConvertFrom-Json
$fixture = Join-Path $fixtureRoot $definition.fixture

# tests/tier1/fixtures/<name> named by every scenario JSON in this repository
# (including the three pre-existing ones this benchmark did not touch) does not
# exist on disk at authoring time -- confirmed by hand: New-SquadWorkspace's
# Copy-Item overlay either silently no-ops (observed once) or throws (observed
# once, apparently timing/context-dependent) when the source directory is
# missing. This is a pre-existing environment gap, not introduced by U5 and out
# of scope to fix here (fixing it for every scenario is not a P04-T01..T06
# deliverable); it is recorded as a Discrepancy in the change record. This
# benchmark degrades gracefully instead of hard-failing on it: an empty
# placeholder directory stands in for the missing fixture, and the scenario's
# own prompt (see scenarios/autopilot-pipelining.json) was written to be
# self-contained precisely because of this finding, so the substitution does
# not change what the scenario actually exercises.
if (-not (Test-Path -LiteralPath $fixture)) {
    Write-Host "WARNING: fixture '$($definition.fixture)' not found at $fixture (pre-existing repository gap, not introduced by this benchmark -- see the change record). Using an empty placeholder." -ForegroundColor Yellow
    $fixture = Join-Path $WorkspaceRoot 'empty-fixture-placeholder'
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
}

# ---------------------------------------------------------------------------
# BEFORE / AFTER source provisioning
# ---------------------------------------------------------------------------

function Resolve-BeforeRef {
    <#
    .SYNOPSIS
        Computes and records the BEFORE ref: the merge-base of HEAD and main.
    .DESCRIPTION
        Computed and recorded before either arm runs, per the dispatch. This
        repository's merge-base of HEAD and main was NOT HEAD itself at authoring
        time (main's tip) -- the dispatch's own phrasing conditionally assumed HEAD
        only "if merge-base equals HEAD", so the computed value here, not that
        assumption, is authoritative and is recorded verbatim in the report.
    #>
    param([Parameter(Mandatory)][string]$SourceRoot)

    Push-Location $SourceRoot
    try {
        $sha = (& git merge-base HEAD main 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "git merge-base HEAD main failed: $sha" }
        return $sha.Trim()
    }
    finally {
        Pop-Location
    }
}

function New-BeforeWorktree {
    <#
    .SYNOPSIS
        Checks the BEFORE ref out into an isolated, detached git worktree under
        -WorkspaceRoot, registered against the real repository.
    .DESCRIPTION
        A worktree (not a clone) is used so the BEFORE arm installs from a real,
        addressable working copy without touching the caller's own checkout. The
        worktree is registered against $SourceRoot's .git and MUST be removed with
        `git worktree remove` when the benchmark finishes -- it is the only
        artifact this script creates that is not confined to %TEMP%.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$Sha,
        [Parameter(Mandatory)][string]$Destination
    )

    Push-Location $SourceRoot
    try {
        & git worktree add --detach $Destination $Sha 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        if ($LASTEXITCODE -ne 0) { throw "git worktree add failed for $Sha at $Destination." }
    }
    finally {
        Pop-Location
    }
    (Resolve-Path -LiteralPath $Destination).Path
}

function Remove-BeforeWorktree {
    <#
    .SYNOPSIS
        Cleans up the BEFORE worktree this script created, per the constraint that
        no git artifact is left registered against the real repository.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$WorktreePath
    )

    if (-not (Test-Path -LiteralPath $WorktreePath)) { return }
    Push-Location $SourceRoot
    try {
        & git worktree remove --force $WorktreePath 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }
    finally {
        Pop-Location
    }
}

function New-AfterSnapshot {
    <#
    .SYNOPSIS
        Copies the current, possibly-uncommitted working tree into an isolated
        snapshot under -WorkspaceRoot, excluding .git and other VCS/build noise.
    .DESCRIPTION
        AFTER is a snapshot, not a worktree or a branch: the dispatch is explicit
        that AFTER is "a snapshot copy of the current working tree (uncommitted)".
        Excluding .git means Install-SquadPackage's own `git init` inside
        New-SquadWorkspace, run per-run against this snapshot's source, cannot pick
        up the real repository's history or remotes -- this is part of the "scratch
        workspace with no git remote" hygiene requirement, applied at the source
        the per-run workspaces are built from, not only at the per-run workspace
        itself.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$Destination
    )

    $excludeDirs = @('.git', 'apm_modules', 'node_modules', 'results')
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    Get-ChildItem -LiteralPath $SourceRoot -Force | Where-Object { $_.Name -notin $excludeDirs } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }

    (Resolve-Path -LiteralPath $Destination).Path
}

# ---------------------------------------------------------------------------
# Hygiene: extended deny list and stripped child environment (E8)
# ---------------------------------------------------------------------------

function Get-BenchmarkDenyToolList {
    <#
    .SYNOPSIS
        The extended deny list every benchmark run passes via --deny-tool.
    .DESCRIPTION
        Both the POSIX and PowerShell spelling of every denied verb are listed
        (best-effort defense-in-depth; see the script's .DESCRIPTION "KNOWN
        LIMITATIONS" for why the exact --deny-tool matching semantics could not be
        confirmed live). This list is strictly additive over Invoke-Tier1LiveRun's
        own 'shell(rm)' baseline -- it is not a replacement for the scratch
        workspace / no-remote / stripped-token hygiene, which does not depend on the
        model choosing to respect a deny list at all.
    #>
    @(
        'shell(git push)'
        'shell(git remote add)'
        'shell(git clean)'
        'shell(git reset)'
        'shell(gh)'
        'shell(rm)'
        'shell(del)'
        'shell(rd)'
        'shell(rmdir)'
        'shell(erase)'
        'shell(Remove-Item)'
        'shell(curl)'
        'shell(wget)'
        'shell(Invoke-WebRequest)'
        'shell(Invoke-RestMethod)'
        'shell(Start-Process)'
    )
}

function Invoke-BenchmarkTurn {
    <#
    .SYNOPSIS
        Runs one headless Copilot CLI turn with the benchmark's extended hygiene and
        machine-readable output, and returns the artifacts needed for independent
        overlap evidence and cost extraction.
    .DESCRIPTION
        An adaptation of SquadRun.psm1's Invoke-SquadTurn: this benchmark cannot
        reuse that function directly because it needs the extended E8 deny list, a
        stripped child environment, and --output-format json / --log-dir /
        --usage-output-file, none of which the shared Tier 1 scenario runner needs
        for its own (single-arm, integrity-only) purpose. SquadRun.psm1 is
        deliberately left unedited; this function lives only in this opt-in driver.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Workspace,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$TranscriptPath,
        [Parameter(Mandatory)][string]$LogDir,
        [Parameter(Mandatory)][string]$UsageOutputFile,
        [int]$TimeoutMinutes = 20
    )

    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    $errorPath = [System.IO.Path]::ChangeExtension($TranscriptPath, '.err.log')
    $started = Get-Date

    $denyArgs = @()
    foreach ($pattern in (Get-BenchmarkDenyToolList)) { $denyArgs += @('--deny-tool', $pattern) }

    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add('-p'); $arguments.Add($Prompt)
    $arguments.Add('--model'); $arguments.Add($Model)
    $arguments.Add('--allow-all-tools')
    $arguments.Add('--output-format'); $arguments.Add('json')
    $arguments.Add('--log-dir'); $arguments.Add($LogDir)
    $arguments.Add('--log-level'); $arguments.Add('debug')
    $arguments.Add('--usage-output-file'); $arguments.Add($UsageOutputFile)
    $arguments.Add('--secret-env-vars'); $arguments.Add('GH_TOKEN,GITHUB_TOKEN,GH_ENTERPRISE_TOKEN')
    foreach ($pattern in (Get-BenchmarkDenyToolList)) {
        $arguments.Add('--deny-tool'); $arguments.Add($pattern)
    }

    # E8 hygiene: strip the tokens gh/git-over-https would use, and refuse any
    # interactive credential prompt outright rather than let it hang the run.
    $previous = @{
        GH_TOKEN            = $env:GH_TOKEN
        GITHUB_TOKEN        = $env:GITHUB_TOKEN
        GH_ENTERPRISE_TOKEN = $env:GH_ENTERPRISE_TOKEN
        GIT_TERMINAL_PROMPT = $env:GIT_TERMINAL_PROMPT
    }
    $env:GH_TOKEN = $null
    $env:GITHUB_TOKEN = $null
    $env:GH_ENTERPRISE_TOKEN = $null
    $env:GIT_TERMINAL_PROMPT = '0'

    try {
        $process = Start-Process -FilePath 'copilot' -ArgumentList $arguments -WorkingDirectory $Workspace `
            -NoNewWindow -PassThru -RedirectStandardOutput $TranscriptPath -RedirectStandardError $errorPath

        $timedOut = $false
        if (-not $process.WaitForExit($TimeoutMinutes * 60 * 1000)) {
            $timedOut = $true
            try { $process.Kill($true) } catch { Write-Debug 'The run process exited between the timeout check and the kill; nothing to terminate.' }
            $process.WaitForExit(30 * 1000) | Out-Null
        }
    }
    finally {
        $env:GH_TOKEN = $previous.GH_TOKEN
        $env:GITHUB_TOKEN = $previous.GITHUB_TOKEN
        $env:GH_ENTERPRISE_TOKEN = $previous.GH_ENTERPRISE_TOKEN
        $env:GIT_TERMINAL_PROMPT = $previous.GIT_TERMINAL_PROMPT
    }

    $transcript = if (Test-Path -LiteralPath $TranscriptPath) { Get-Content -LiteralPath $TranscriptPath -Raw } else { '' }
    $usage = if (Test-Path -LiteralPath $UsageOutputFile) {
        try { Get-Content -LiteralPath $UsageOutputFile -Raw | ConvertFrom-Json } catch { $null }
    }
    else { $null }

    [pscustomobject]@{
        ExitCode   = if ($timedOut) { 124 } else { $process.ExitCode }
        TimedOut   = $timedOut
        Seconds    = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        Transcript = $transcript
        ErrorLog   = if (Test-Path -LiteralPath $errorPath) { Get-Content -LiteralPath $errorPath -Raw } else { '' }
        Usage      = $usage
        LogDir     = $LogDir
    }
}

# ---------------------------------------------------------------------------
# Independent overlap evidence (never the model's own transcript claim)
# ---------------------------------------------------------------------------

function Get-OverlapEvidence {
    <#
    .SYNOPSIS
        Counts overlapped-boundary events from the CLI's own JSONL tool-call stream
        and, when that yields nothing, from --log-dir, and never from the model's
        prose answer.
    .DESCRIPTION
        See the script's .DESCRIPTION "KNOWN LIMITATIONS" note: the exact JSONL
        event field names are undocumented and this parser is a best-effort
        heuristic over plausible shapes, corroborated against the debug log
        directory. It looks for a Scribe-flavored tool-call/dispatch event whose
        [start, end) interval overlaps a next-stage-role-flavored event's [start,
        end) interval, over consecutive stage boundaries. Every candidate event
        needs a recognizable timestamp and a recognizable label; anything else is
        ignored rather than guessed at.

        This function can only under-count (never fabricate) overlaps: a stream
        format it cannot parse yields 0 candidate events, which the AFTER-only void
        rule already treats conservatively (void, excluded from the classification
        rather than counted as a false gain).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TranscriptPath,
        [Parameter(Mandatory)][string]$LogDir,
        [int]$ExpectedBoundaries = 2
    )

    $events = [System.Collections.Generic.List[pscustomobject]]::new()

    if (Test-Path -LiteralPath $TranscriptPath) {
        foreach ($line in (Get-Content -LiteralPath $TranscriptPath)) {
            $trimmed = $line.Trim()
            if (-not $trimmed.StartsWith('{')) { continue }
            try { $obj = $trimmed | ConvertFrom-Json } catch { continue }

            $type = @('type', 'event', 'kind') | ForEach-Object { $obj.PSObject.Properties[$_]?.Value } | Where-Object { $_ } | Select-Object -First 1
            $label = @('tool', 'name', 'agent', 'subagent', 'label') | ForEach-Object { $obj.PSObject.Properties[$_]?.Value } | Where-Object { $_ } | Select-Object -First 1
            $timestamp = @('timestamp', 'time', 'ts', 'at') | ForEach-Object { $obj.PSObject.Properties[$_]?.Value } | Where-Object { $_ } | Select-Object -First 1
            if (-not $type -or -not $timestamp) { continue }

            $parsed = $null
            if (-not [datetime]::TryParse([string]$timestamp, [ref]$parsed)) { continue }

            $events.Add([pscustomobject]@{
                    Type      = [string]$type
                    Label     = [string]$label
                    Timestamp = $parsed
                })
        }
    }

    # Corroborate/fall back to the debug log directory when the JSONL stream
    # yielded no candidate events at all -- a format mismatch, not evidence of "no
    # tool calls happened".
    if ($events.Count -eq 0 -and (Test-Path -LiteralPath $LogDir)) {
        foreach ($file in (Get-ChildItem -LiteralPath $LogDir -Filter '*.log' -File -Recurse -ErrorAction SilentlyContinue)) {
            foreach ($line in (Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
                $match = [regex]::Match($line, '^(?<ts>\S+T\S+)\s+.*?(?<label>Scribe|dispatch|subagent)', 'IgnoreCase')
                if (-not $match.Success) { continue }
                $parsed = $null
                if (-not [datetime]::TryParse($match.Groups['ts'].Value, [ref]$parsed)) { continue }
                $events.Add([pscustomobject]@{ Type = 'log-line'; Label = $match.Groups['label'].Value; Timestamp = $parsed })
            }
        }
    }

    $starts = @($events | Where-Object { $_.Type -match 'start|begin|invoke' } | Sort-Object Timestamp)
    $ends = @($events | Where-Object { $_.Type -match 'end|complete|finish|result' } | Sort-Object Timestamp)

    $scribeStarts = @($starts | Where-Object { $_.Label -match 'scribe' })
    $roleStarts = @($starts | Where-Object { $_.Label -notmatch 'scribe' })
    $scribeEnds = @($ends | Where-Object { $_.Label -match 'scribe' })

    $overlaps = 0
    foreach ($scribeStart in $scribeStarts) {
        $scribeEnd = @($scribeEnds | Where-Object { $_.Timestamp -ge $scribeStart.Timestamp } | Sort-Object Timestamp | Select-Object -First 1)
        if ($scribeEnd.Count -eq 0) { continue }
        $overlapping = @($roleStarts | Where-Object { $_.Timestamp -ge $scribeStart.Timestamp -and $_.Timestamp -le $scribeEnd[0].Timestamp })
        if ($overlapping.Count -gt 0) { $overlaps++ }
    }

    [pscustomobject]@{
        OverlapCount     = [math]::Min($overlaps, $ExpectedBoundaries)
        CandidateEvents  = $events.Count
        Source           = if ($events.Count -eq 0) { 'none' } elseif ($starts.Count -gt 0 -and (Test-Path -LiteralPath $TranscriptPath) -and ($events | Where-Object { $_.Type -ne 'log-line' }).Count -gt 0) { 'jsonl' } else { 'log-dir' }
    }
}

# ---------------------------------------------------------------------------
# Write-completeness (per run)
# ---------------------------------------------------------------------------

function Test-WriteCompleteness {
    <#
    .SYNOPSIS
        Runs PipeliningIntegrity.Tests.ps1 and Measure-SquadLedger -Check against a
        completed run's squad root, matching Invoke-Tier1LiveRun.ps1's own hook.
    .DESCRIPTION
        tests/tier1's own write-completeness convention is this repo's
        Test-SquadScribeOutput.ps1, which does not exist in this repository (the
        dispatch names it conditionally: "if present"). PipeliningIntegrity.Tests.ps1
        plus Measure-SquadLedger -Check together cover the same ground for this
        scenario: every stage artifact has a history entry, stage order held, the
        barrier held, and the ledger's own dispatch-entry counts reconcile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$SquadRoot,
        [Parameter(Mandatory)][pscustomobject]$Definition,
        [Parameter(Mandatory)][string]$AttemptRoot
    )

    $failures = [System.Collections.Generic.List[string]]::new()

    if ($Definition.PSObject.Properties.Name -contains 'pipeliningIntegrity') {
        $integrityRunner = Join-Path $PSScriptRoot '..' 'PipeliningIntegrity.Tests.ps1'
        $config = New-PesterConfiguration
        $config.Run.Container = New-PesterContainer -Path $integrityRunner -Data @{
            WorkspaceRoot     = $WorkspaceRoot
            SquadRoot         = $SquadRoot
            Stages            = @($Definition.pipeliningIntegrity.stages)
            BarrierAfterStage = [string]$Definition.pipeliningIntegrity.barrierAfterStage
            ScribeAgentFile   = [string]$Definition.pipeliningIntegrity.scribeAgentFile
        }
        $config.Run.PassThru = $true
        $config.Output.Verbosity = 'None'
        $config.TestResult.Enabled = $true
        $config.TestResult.OutputPath = Join-Path $AttemptRoot 'pipelining-integrity.xml'

        $result = Invoke-Pester -Configuration $config
        if ($result.FailedCount -gt 0 -or $result.TotalCount -eq 0) {
            $failures.Add("pipelining integrity: $($result.FailedCount) of $($result.TotalCount) checks failed")
        }
    }

    # Measure-SquadLedger -Check -ExpectedHistoryCounts, invoked as a literal
    # PowerShell -Command (not -File) so the hashtable arrives as a real
    # [hashtable] rather than a stringified argument, and so the script's own
    # `exit 0`/`exit 1` calls terminate a child process rather than this one. See
    # the change record for why -File cannot carry this parameter.
    $ledgerScript = Join-Path $PSScriptRoot '..' '..' '..' 'squad-src' '.github' 'skills' 'squad' 'scripts' 'Measure-SquadLedger.ps1'
    $historyDir = Join-Path $SquadRoot 'history'
    $counts = @{}
    if (Test-Path -LiteralPath $historyDir) {
        foreach ($file in (Get-ChildItem -LiteralPath $historyDir -Filter '*.md' -File)) {
            $entries = @([regex]::Matches((Get-Content -LiteralPath $file.FullName -Raw), '(?m)^#{2,3}[ \t]+\S'))
            $counts[[System.IO.Path]::GetFileNameWithoutExtension($file.Name)] = $entries.Count
        }
    }
    $literal = '@{' + (($counts.Keys | ForEach-Object { "'$($_ -replace "'", "''")' = $($counts[$_])" }) -join '; ') + '}'
    $cmd = "& '$ledgerScript' -SquadRoot '$SquadRoot' -Check -ExpectedHistoryCounts $literal"
    $ledgerOutput = & pwsh -NoProfile -Command $cmd 2>&1
    $ledgerOutput | Out-File -LiteralPath (Join-Path $AttemptRoot 'ledger-check.log') -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("Measure-SquadLedger -Check exited ${LASTEXITCODE}: $($ledgerOutput -join ' ')")
    }

    [pscustomobject]@{
        Passed   = $failures.Count -eq 0
        Failures = @($failures)
    }
}

# ---------------------------------------------------------------------------
# Secret scan (fail-closed) before anything is copied into the repository
# ---------------------------------------------------------------------------

function Test-SecretScan {
    <#
    .SYNOPSIS
        Fail-closed scan for secret-shaped strings before -CopyReportTo copies
        anything into the repository.
    .DESCRIPTION
        Matches GitHub token prefixes (ghp_/gho_/ghu_/ghs_/ghr_/github_pat_),
        generic bearer-token shapes, and AKIA-style AWS access key ids. A scan that
        errors (rather than cleanly returning zero matches) is treated as a FAIL,
        never as a pass -- fail-closed.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Content)

    $patterns = @(
        'ghp_[A-Za-z0-9]{20,}'
        'gho_[A-Za-z0-9]{20,}'
        'ghu_[A-Za-z0-9]{20,}'
        'ghs_[A-Za-z0-9]{20,}'
        'ghr_[A-Za-z0-9]{20,}'
        'github_pat_[A-Za-z0-9_]{20,}'
        '(?i)bearer\s+[A-Za-z0-9._-]{20,}'
        'AKIA[0-9A-Z]{16}'
    )

    try {
        $hits = [System.Collections.Generic.List[string]]::new()
        foreach ($pattern in $patterns) {
            if ([regex]::IsMatch($Content, $pattern)) { $hits.Add($pattern) }
        }
        [pscustomobject]@{ Clean = $hits.Count -eq 0; MatchedPatterns = @($hits) }
    }
    catch {
        [pscustomobject]@{ Clean = $false; MatchedPatterns = @('scan error (fail-closed): ' + $_.Exception.Message) }
    }
}

# ---------------------------------------------------------------------------
# Per-run driver
# ---------------------------------------------------------------------------

function Invoke-BenchmarkRun {
    <#
    .SYNOPSIS
        Provisions one fresh scratch workspace from an arm's source, runs the
        scenario's turns, and returns elapsed time, overlap evidence, write
        completeness, and cost for that single run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Arm,
        [Parameter(Mandatory)][int]$RunIndex,
        [Parameter(Mandatory)][string]$ArmSourceRoot,
        [Parameter(Mandatory)][pscustomobject]$Definition,
        [Parameter(Mandatory)][string]$Fixture,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$ResultRoot,
        [Parameter(Mandatory)][int]$TimeoutMinutes
    )

    $runId = "$Arm-$RunIndex"
    $workspace = Join-Path $WorkspaceRoot "run-$runId"
    $attemptRoot = Join-Path $ResultRoot 'runs' $runId
    New-Item -ItemType Directory -Path $attemptRoot -Force | Out-Null

    $failures = [System.Collections.Generic.List[string]]::new()
    $totalSeconds = 0.0
    $totalCostUsd = $null
    $overlapCount = 0
    $writeCompleteness = $null

    $install = New-SquadWorkspace -Destination $workspace -FixturePath $Fixture -SourceRoot $ArmSourceRoot

    $lastTranscript = $null
    $lastLogDir = $null
    foreach ($turn in $Definition.turns) {
        $transcript = Join-Path $attemptRoot "turn-$($turn.id).jsonl"
        $logDir = Join-Path $attemptRoot "turn-$($turn.id).logs"
        $usageFile = Join-Path $attemptRoot "turn-$($turn.id).usage.json"

        $result = Invoke-BenchmarkTurn -Workspace $install.Root -Prompt $turn.prompt -Model $Model `
            -TranscriptPath $transcript -LogDir $logDir -UsageOutputFile $usageFile -TimeoutMinutes $TimeoutMinutes

        $totalSeconds += $result.Seconds
        if ($result.Usage -and $result.Usage.PSObject.Properties.Name -contains 'totalCostUsd') {
            if ($null -eq $totalCostUsd) { $totalCostUsd = 0.0 }
            $totalCostUsd = [double]$totalCostUsd + [double]$result.Usage.totalCostUsd
        }
        $lastTranscript = $transcript
        $lastLogDir = $logDir

        if ($result.TimedOut) { $failures.Add("turn '$($turn.id)' exceeded $TimeoutMinutes minutes") }
        elseif ($result.ExitCode -ne 0) { $failures.Add("turn '$($turn.id)' exited $($result.ExitCode): $($result.ErrorLog)") }
        if ($failures.Count -gt 0) { break }
    }

    if ($failures.Count -eq 0 -and $lastTranscript) {
        $evidence = Get-OverlapEvidence -TranscriptPath $lastTranscript -LogDir $lastLogDir -ExpectedBoundaries 2
        $overlapCount = $evidence.OverlapCount
        $overlapCount | Out-Null

        $squadRoots = @(Get-Item -Path (Join-Path $install.Root $Definition.squadRootGlob) -ErrorAction SilentlyContinue |
                Where-Object { $_.PSIsContainer } | ForEach-Object { $_.FullName })
        if ($squadRoots.Count -eq 0) {
            $failures.Add("No squad root matched '$($Definition.squadRootGlob)'.")
        }
        else {
            $writeCompleteness = Test-WriteCompleteness -WorkspaceRoot $install.Root -SquadRoot $squadRoots[0] -Definition $Definition -AttemptRoot $attemptRoot
            if (-not $writeCompleteness.Passed) { $failures.AddRange([string[]]$writeCompleteness.Failures) }
        }
    }

    [pscustomobject]@{
        Arm               = $Arm
        RunIndex          = $RunIndex
        ElapsedSeconds    = $totalSeconds
        OverlapCount      = $overlapCount
        Void              = ($Arm -eq 'after' -and $overlapCount -eq 0)
        CostUsd           = $totalCostUsd
        WriteCompleteness = $writeCompleteness
        Passed            = $failures.Count -eq 0
        Failures          = @($failures)
        AttemptRoot       = $attemptRoot
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Host "Resolving BEFORE ref (merge-base of HEAD and main)..." -ForegroundColor Cyan
$resolvedBeforeRef = if ($BeforeRef) { $BeforeRef } else { Resolve-BeforeRef -SourceRoot $SourceRoot }
Write-Host "  BEFORE = $resolvedBeforeRef" -ForegroundColor DarkGray

$beforeSrc = Join-Path $WorkspaceRoot 'before-src'
$afterSrc = Join-Path $WorkspaceRoot 'after-src'

Write-Host 'Provisioning BEFORE worktree...' -ForegroundColor Cyan
$beforeSrc = New-BeforeWorktree -SourceRoot $SourceRoot -Sha $resolvedBeforeRef -Destination $beforeSrc

Write-Host 'Provisioning AFTER snapshot...' -ForegroundColor Cyan
$afterSrc = New-AfterSnapshot -SourceRoot $SourceRoot -Destination $afterSrc

$manifest = [ordered]@{
    schemaVersion    = 1
    capturedUtc      = (Get-Date).ToUniversalTime().ToString('o')
    sourceRoot       = $SourceRoot
    scenario         = $Scenario
    model            = $Model
    beforeRef        = $resolvedBeforeRef
    beforeSrc        = $beforeSrc
    afterSrc         = $afterSrc
    copilotVersion   = $null
}
try { $manifest.copilotVersion = ((& copilot --version) -join ' ').Trim() } catch { $manifest.copilotVersion = 'unavailable (copilot CLI not runnable in this environment)' }

try {
    if ($ProvisionOnly) {
        Write-Host 'Provisioning one scratch workspace per arm (ProvisionOnly)...' -ForegroundColor Cyan
        foreach ($arm in @(@{ Name = 'before'; Src = $beforeSrc }, @{ Name = 'after'; Src = $afterSrc })) {
            $workspace = Join-Path $WorkspaceRoot "provision-$($arm.Name)"
            $install = New-SquadWorkspace -Destination $workspace -FixturePath $fixture -SourceRoot $arm.Src
            Write-Host "  provisioned $($arm.Name): $($install.Root)" -ForegroundColor DarkGray
        }
        $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ResultRoot 'provision-manifest.json') -Encoding utf8NoBOM
        Write-Host 'ProvisionOnly complete.' -ForegroundColor Green
        return
    }

    $runs = [System.Collections.Generic.List[pscustomobject]]::new()
    $runningTotalUsd = 0.0

    if ($SmokeOnly) {
        Write-Host 'Running the single AFTER-arm smoke run...' -ForegroundColor Cyan
        $precheck = Test-CostPrecheck -RunningTotalUsd 0.0 -NextRunEstimateUsd $EstimatedCostPerRunUsd -CeilingUsd $CostCeilingUsd
        if ($precheck.ShouldAbort) { throw "Smoke run aborted before starting: $($precheck.Reason)" }

        $smoke = Invoke-BenchmarkRun -Arm 'after' -RunIndex 1 -ArmSourceRoot $afterSrc -Definition $definition `
            -Fixture $fixture -Model $Model -WorkspaceRoot $WorkspaceRoot -ResultRoot $ResultRoot -TimeoutMinutes $TimeoutMinutes
        $runs.Add($smoke)

        $manifest.smoke = $smoke
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ResultRoot 'smoke-manifest.json') -Encoding utf8NoBOM

        if ($smoke.Passed -and $smoke.OverlapCount -eq 0) {
            Write-Host 'SMOKE RESULT: 0 independently-observed overlaps on the AFTER arm. Per the dispatch, STOP -- do not spend the full paired design on a guaranteed-void scenario.' -ForegroundColor Red
        }
        else {
            Write-Host "SMOKE RESULT: passed=$($smoke.Passed) overlapCount=$($smoke.OverlapCount)." -ForegroundColor (if ($smoke.Passed) { 'Green' } else { 'Red' })
        }
        return
    }

    # Alternating BEFORE/AFTER, N=3 target with a deterministic N=2 fallback
    # (Amendment 1 "Cost Estimate and N-Sizing"; Get-NDowngradeDecision).
    $targetN = $TargetN
    for ($i = 1; $i -le $targetN; $i++) {
        foreach ($arm in @('before', 'after')) {
            $precheck = Test-CostPrecheck -RunningTotalUsd $runningTotalUsd -NextRunEstimateUsd $EstimatedCostPerRunUsd -CeilingUsd $CostCeilingUsd
            if ($precheck.ShouldAbort) {
                Write-Host "Harness precheck aborting remaining runs: $($precheck.Reason)" -ForegroundColor Red
                $manifest.abortedReason = $precheck.Reason
                break
            }

            $src = if ($arm -eq 'before') { $beforeSrc } else { $afterSrc }
            Write-Host "Run $arm #$i..." -ForegroundColor Cyan
            $run = Invoke-BenchmarkRun -Arm $arm -RunIndex $i -ArmSourceRoot $src -Definition $definition `
                -Fixture $fixture -Model $Model -WorkspaceRoot $WorkspaceRoot -ResultRoot $ResultRoot -TimeoutMinutes $TimeoutMinutes
            $runs.Add($run)
            $runningTotalUsd += if ($null -ne $run.CostUsd) { $run.CostUsd } else { $EstimatedCostPerRunUsd }

            # Power/ceiling check after each arm's first run (Amendment 2 S11).
            if ($i -eq 1) {
                $before1 = @($runs | Where-Object { $_.Arm -eq 'before' } | Select-Object -First 1)
                $after1 = @($runs | Where-Object { $_.Arm -eq 'after' } | Select-Object -First 1)
                if ($before1.Count -gt 0 -and $after1.Count -gt 0) {
                    # Scribe/role round-trip seconds are not independently measured
                    # at this point (no second run exists yet to derive them from);
                    # the first-run elapsed seconds are used as the best available
                    # proxy for both, a documented design decision (see the change
                    # record and Test-PowerCeilingCheck's own docstring).
                    $power = Test-PowerCeilingCheck -BoundaryCount 2 -ScribeRoundTripSeconds ($before1[0].ElapsedSeconds / 4) `
                        -RoleRoundTripSeconds ($before1[0].ElapsedSeconds / 4) -FirstBeforeElapsedSeconds $before1[0].ElapsedSeconds `
                        -FirstAfterElapsedSeconds $after1[0].ElapsedSeconds
                    $manifest.powerCeilingCheck = $power
                    if ($power.ShouldStopAndAskHuman) {
                        Write-Host "Power/ceiling check: $($power.Reason)" -ForegroundColor Yellow
                    }
                }
            }
        }
        if ($manifest.Contains('abortedReason')) { break }

        # N=2 downgrade decision after 2 runs of an arm, before starting the 3rd.
        if ($i -eq 2) {
            $decision = Get-NDowngradeDecision -RunningTotalUsdAfterTwoRuns $runningTotalUsd -ThirdRunEstimateUsd ($EstimatedCostPerRunUsd * 2) -CeilingUsd $CostCeilingUsd
            $manifest.nDowngradeDecision = $decision
            if ($decision.DowngradeToN2) {
                Write-Host "N-downgrade: $($decision.Reason)" -ForegroundColor Yellow
                $targetN = 2
                break
            }
        }
    }

    $beforeSeconds = @($runs | Where-Object { $_.Arm -eq 'before' } | ForEach-Object { [double]$_.ElapsedSeconds })
    $afterRuns = @($runs | Where-Object { $_.Arm -eq 'after' })
    $afterSeconds = @($afterRuns | ForEach-Object { [double]$_.ElapsedSeconds })
    $afterOverlaps = @($afterRuns | ForEach-Object { [int]$_.OverlapCount })

    $classification = if ($beforeSeconds.Count -gt 0 -and $afterSeconds.Count -gt 0) {
        Get-BenchmarkClassification -BeforeElapsedSeconds $beforeSeconds -AfterElapsedSeconds $afterSeconds -AfterOverlapCount $afterOverlaps
    }
    else {
        [pscustomobject]@{ classification = 'inconclusive'; reason = 'No completed runs in one or both arms.' }
    }

    $reportJson = [ordered]@{
        schemaVersion    = 1
        capturedUtc      = (Get-Date).ToUniversalTime().ToString('o')
        manifest         = $manifest
        runs             = @($runs | ForEach-Object {
                [ordered]@{
                    arm               = $_.Arm
                    runIndex          = $_.RunIndex
                    elapsedSeconds    = $_.ElapsedSeconds
                    overlapCount      = $_.OverlapCount
                    void              = $_.Void
                    costUsd           = $_.CostUsd
                    writeComplete     = if ($_.WriteCompleteness) { $_.WriteCompleteness.Passed } else { $null }
                    passed            = $_.Passed
                    failures          = $_.Failures
                }
            })
        classification   = $classification
        actualSpendUsd   = $runningTotalUsd
        costCeilingUsd   = $CostCeilingUsd
    }
    $reportJsonPath = Join-Path $ResultRoot 'report.json'
    $reportJson | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportJsonPath -Encoding utf8NoBOM

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# U5 Pipelining Benchmark Report')
    $lines.Add('')
    $lines.Add("* Captured (UTC): $($reportJson.capturedUtc)")
    $lines.Add("* Scenario: $Scenario")
    $lines.Add("* Model: $Model")
    $lines.Add("* Copilot CLI version: $($manifest.copilotVersion)")
    $lines.Add("* BEFORE ref (merge-base of HEAD and main): $resolvedBeforeRef")
    $lines.Add("* AFTER: snapshot of the working tree at $SourceRoot")
    $lines.Add('')
    $lines.Add('## Runs')
    $lines.Add('')
    $lines.Add('| Arm | # | Elapsed (s) | Overlaps | Void? | Write-complete | Cost (USD) |')
    $lines.Add('|-----|---|-------------|----------|-------|-----------------|------------|')
    foreach ($run in $runs) {
        $lines.Add("| $($run.Arm) | $($run.RunIndex) | $($run.ElapsedSeconds) | $($run.OverlapCount) | $($run.Void) | $(if ($run.WriteCompleteness) { $run.WriteCompleteness.Passed } else { 'n/a' }) | $($run.CostUsd) |")
    }
    $lines.Add('')
    $lines.Add('## Classification')
    $lines.Add('')
    $lines.Add("* Classification: **$($classification.classification)**")
    $lines.Add("* Reason: $($classification.reason)")
    if ($classification.PSObject.Properties.Name -contains 'medianDeltaSecond' -and $null -ne $classification.medianDeltaSecond) {
        $lines.Add("* Median BEFORE: $($classification.medianBefore)s; Median AFTER: $($classification.medianAfter)s")
        $lines.Add("* Median delta: $($classification.medianDeltaSecond)s ($([math]::Round($classification.medianDeltaPct, 1))%)")
        $lines.Add("* Spread BEFORE: $($classification.spreadBefore)s; Spread AFTER: $($classification.spreadAfter)s; larger spread: $($classification.largerSpread)s")
    }
    $lines.Add('')
    $lines.Add('## Caveats')
    $lines.Add('')
    foreach ($caveat in @($classification.caveats)) { $lines.Add("* $caveat") }
    $lines.Add('')
    $lines.Add('## Cost')
    $lines.Add('')
    $lines.Add("* Actual/estimated total spend: `$$([math]::Round($runningTotalUsd, 2)) of a `$$CostCeilingUsd harness ceiling")
    $lines.Add("* No squad Cost Preflight ceiling was configured in either arm's turns.")

    $reportMd = ($lines -join "`n")
    $reportMdPath = Join-Path $ResultRoot 'report.md'
    Set-Content -LiteralPath $reportMdPath -Value $reportMd -Encoding utf8NoBOM

    if ($CopyReportTo) {
        $scan = Test-SecretScan -Content $reportMd
        if (-not $scan.Clean) {
            throw "Fail-closed secret scan found matches ($($scan.MatchedPatterns -join ', ')); refusing to copy the report into the repository."
        }
        New-Item -ItemType Directory -Path (Split-Path $CopyReportTo -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $reportMdPath -Destination $CopyReportTo -Force
        Write-Host "Secret scan passed; copied report to $CopyReportTo" -ForegroundColor Green
    }

    Write-Host ''
    Write-Host "Classification: $($classification.classification) -- $($classification.reason)" -ForegroundColor Green
}
finally {
    Write-Host 'Cleaning up the BEFORE worktree...' -ForegroundColor Cyan
    Remove-BeforeWorktree -SourceRoot $SourceRoot -WorktreePath $beforeSrc
}
