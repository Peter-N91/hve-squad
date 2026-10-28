#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Analyzes CLI logs or explicitly launches a bounded cold-init squad exercise.
.DESCRIPTION
    Run spends credits and requires a prepared full install and isolated environment.
    Analyze, Compare and Promote are offline. No command commits or pushes.
.PARAMETER Mode
    Analyze freezes a log; Run launches one trial; Compare and Promote gate reports.
.PARAMETER TrialRoot
    A new evidence directory, never an existing workspace.
.PARAMETER MaxCredits
    Required positive total ceiling for live execution, divided across stages and judge.
.EXAMPLE
    ./Invoke-EfficiencyExercise.ps1 -Mode Analyze -EventsPath ./events.jsonl -OutputPath ./analysis
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Analyze', 'Run', 'Compare', 'Promote', 'Establish', 'Series')][string]$Mode,
    [string]$EventsPath,
    [string]$OutputPath,
    [string]$TrialRoot,
    [string]$SourceRoot,
    [string]$BaselineSourceRoot,
    [string]$CandidateSourceRoot,
    [string]$BaselineEvidencePath,
    [string]$InstallRoot,
    [ValidateSet('baseline', 'candidate')][string]$Arm = 'baseline',
    [ValidateRange(1, 3)][int]$Pair = 1,
    [string]$Model = 'claude-sonnet-5.5',
    [string]$CliPath = '',
    [double]$MaxCredits = 0,
    [double]$MaxSeriesCredits = 0,
    [switch]$Live,
    [switch]$IsolatedEnvironment,
    [string[]]$RunPaths,
    [string]$AcceptedPath,
    [string]$ProgressPath = '',
    [switch]$ObservationOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1') -Force

if ($MyInvocation.InvocationName -ne '.') {
    $Out = $null
    $ProgressStep = $null; $ProgressLabel = ''
    try {
        if ($Mode -eq 'Analyze') {
            if (-not $EventsPath -or -not $OutputPath) { throw 'Analyze requires EventsPath and a new OutputPath directory.' }
            if (Test-Path -LiteralPath $OutputPath) { throw 'OutputPath must not exist.' }
            New-Item -ItemType Directory -Path $OutputPath | Out-Null
            $Snapshot = Join-Path $OutputPath 'events.jsonl'
            Copy-EfficiencySnapshot -Path $EventsPath -Destination $Snapshot | Out-Null
            $Metrics = Measure-EfficiencyEvents -Path $Snapshot
            $Metrics | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $OutputPath 'metrics.json') -Encoding utf8NoBOM
            Write-Host "Analysis complete: $($Metrics.complete). Metrics: $(Join-Path $OutputPath 'metrics.json')"
            if (-not $Metrics.complete) { exit 2 }
            return
        }
        if ($Mode -in @('Compare', 'Promote')) {
            if (-not $RunPaths -or -not $OutputPath) { throw 'Compare/Promote requires six RunPaths and OutputPath.' }
            $Runs = @($RunPaths | ForEach-Object { Get-Content -LiteralPath $_ -Raw | ConvertFrom-Json -AsHashtable })
            $Report = Compare-EfficiencyRuns -Runs $Runs -ObservationOnly:$ObservationOnly
            if ($Mode -eq 'Promote') {
                if (-not $AcceptedPath) { throw 'Promote requires AcceptedPath.' }
                Save-EfficiencyBaseline -Runs $Runs -Path $AcceptedPath | Out-Null
            }
            $Report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
            $Markdown = @('# Squad efficiency comparison', '', "Eligible: $($Report.eligible)", '', '| Metric | Baseline | Candidate | Change % |', '|---|---:|---:|---:|')
            foreach ($Name in $Report.metrics.Keys) {
                $Metric = $Report.metrics[$Name]
                $Change = if ($null -eq $Metric.changePercent) { 'n/a' } else { $Metric.changePercent.ToString('F2', [Globalization.CultureInfo]::InvariantCulture) }
                $Markdown += "| $Name | $($Metric.baseline) | $($Metric.candidate) | $Change |"
            }
            $Markdown += @('', '## Gate Results', '') + @($Report.reasons | ForEach-Object { '* ' + $_ }) + @('', 'Elapsed times are diagnostics, not acceptance metrics. Hook intervals are not measured blocking delay.')
            $Markdown | Set-Content -LiteralPath ([IO.Path]::ChangeExtension($OutputPath, '.md')) -Encoding utf8NoBOM
            Write-Host "Comparison eligible: $($Report.eligible). Report: $OutputPath. Accepted baseline changes only in Promote mode."
            if (-not $Report.eligible) { exit 2 }
            return
        }
        if (-not $Live -or -not $IsolatedEnvironment -or $MaxCredits -le 0 -or [double]::IsNaN($MaxCredits) -or [double]::IsInfinity($MaxCredits)) {
            throw 'Run requires -Live -IsolatedEnvironment and a finite positive -MaxCredits. Tool filters are not an OS sandbox.'
        }
        $RecoveryPolicy = Get-EfficiencyRecoveryPolicy -MaxCredits $MaxCredits -ObservationOnly:$ObservationOnly
        if ($Mode -in @('Establish', 'Series')) {
            if (-not $TrialRoot -or -not $InstallRoot -or $MaxSeriesCredits -le 0 -or [double]::IsNaN($MaxSeriesCredits) -or [double]::IsInfinity($MaxSeriesCredits)) { throw 'Establish/Series requires a new TrialRoot, InstallRoot and finite positive MaxSeriesCredits.' }
            if (Test-Path -LiteralPath $TrialRoot) { throw 'TrialRoot must not exist; saved evidence is never overwritten.' }
            if (-not $BaselineSourceRoot) { $BaselineSourceRoot = $SourceRoot }
            if ($BaselineSourceRoot) { $BaselineSourceRoot = (Resolve-Path -LiteralPath $BaselineSourceRoot).Path }
            if ($CandidateSourceRoot) { $CandidateSourceRoot = (Resolve-Path -LiteralPath $CandidateSourceRoot).Path }
            if ($Mode -eq 'Establish' -and -not $BaselineSourceRoot) { throw 'Establish requires SourceRoot or BaselineSourceRoot.' }
            if ($Mode -eq 'Series' -and (-not $CandidateSourceRoot -or (-not $BaselineSourceRoot -and -not $BaselineEvidencePath))) { throw 'Series requires CandidateSourceRoot and either BaselineSourceRoot or BaselineEvidencePath.' }
            if (-not $CliPath) { $CliPath = (Get-Command copilot -ErrorAction Stop).Source }
            $CliPath = (Resolve-Path -LiteralPath $CliPath).Path
            $InstallRoot = (Resolve-Path -LiteralPath $InstallRoot).Path
            $Saved = if ($BaselineEvidencePath) { Get-Content -LiteralPath $BaselineEvidencePath -Raw | ConvertFrom-Json -AsHashtable } else { $null }
            $IdentitySource = if ($Mode -eq 'Establish') { $BaselineSourceRoot } else { $CandidateSourceRoot }
            $Expected = Get-EfficiencyCompatibility -SourceRoot $IdentitySource -InstallRoot $InstallRoot -CliPath $CliPath -Model $Model -MaxCredits $MaxCredits -ObservationOnly:$ObservationOnly
            if ($Mode -eq 'Series' -and $BaselineSourceRoot) {
                $ControlCompatibility = Get-EfficiencyCompatibility -SourceRoot $BaselineSourceRoot -InstallRoot $InstallRoot -CliPath $CliPath -Model $Model -MaxCredits $MaxCredits -ObservationOnly:$ObservationOnly
                $Before = @($ControlCompatibility.Keys | Sort-Object | ForEach-Object { $_ + '=' + ($ControlCompatibility[$_] | ConvertTo-Json -Depth 10 -Compress) }) -join "`n"
                $After = @($Expected.Keys | Sort-Object | ForEach-Object { $_ + '=' + ($Expected[$_] | ConvertTo-Json -Depth 10 -Compress) }) -join "`n"
                if ($Before -cne $After) { throw 'Baseline/candidate model policy or installed environment is incompatible.' }
                if ($Saved -and $Saved['runs'][0]['metadata']['sourceHash'] -cne (Get-EfficiencyTreeHash (Join-Path $BaselineSourceRoot 'squad-src'))) { throw 'Saved control does not match BaselineSourceRoot.' }
            }
            $TrialRoot = [IO.Path]::GetFullPath($TrialRoot)
            $Out = Join-Path $TrialRoot 'out'; $Trials = Join-Path $TrialRoot 'trials'
            New-Item -ItemType Directory -Path $Out, $Trials | Out-Null
            $EntryScript = $PSCommandPath
            $SourcePaths = @{ baseline = $BaselineSourceRoot; candidate = $CandidateSourceRoot }
            $TrialRunner = {
                param($TrialArm, $TrialPair, [double]$CreditCeiling)
                $TrialPath = Join-Path $Trials "$TrialArm-$TrialPair"
                $Arguments = @('-NoProfile', '-File', $EntryScript, '-Mode', 'Run', '-TrialRoot', $TrialPath, '-SourceRoot', $SourcePaths[$TrialArm], '-InstallRoot', $InstallRoot, '-Arm', $TrialArm, '-Pair', [string]$TrialPair, '-Model', $Model, '-CliPath', $CliPath, '-MaxCredits', $CreditCeiling.ToString('R', [Globalization.CultureInfo]::InvariantCulture), '-Live', '-IsolatedEnvironment')
                if ($ObservationOnly) { $Arguments += '-ObservationOnly' }
                $LaunchPath = Join-Path $Out "$TrialArm-$TrialPair-launch.jsonl"
                try {
                    $ScenarioLimits = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'efficiency-scenario.json') -Raw | ConvertFrom-Json -AsHashtable
                    $TrialSeconds = if ($ObservationOnly) { [int]$ScenarioLimits.observationTimeoutMinutes * 60 + 120 } else { 2820 }
                    $Process = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments $Arguments -WorkingDirectory $Trials -OutputPath $LaunchPath -TimeoutSeconds $TrialSeconds
                    $EvidencePath = Join-Path $TrialPath 'out/run.json'
                    if (-not (Test-Path -LiteralPath $EvidencePath)) {
                        $Failure = [InvalidOperationException]::new('Trial did not produce run evidence; inspect its retained launch stderr.')
                        $Failure.Data['efficiencyCategory'] = 'child-exited-without-run-evidence'
                        $Failure.Data['efficiencyExitCode'] = [int]$Process.exitCode
                        $Failure.Data['efficiencyStopCause'] = [string]$Process.stopCause
                        throw $Failure
                    }
                    Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json -AsHashtable
                }
                catch {
                    ($_ | Out-String) + "`n" + $_.ScriptStackTrace | Set-Content -LiteralPath ($LaunchPath + '.exception.txt') -Encoding utf8NoBOM
                    throw
                }
            }.GetNewClosure()
            $Series = Invoke-EfficiencySeries -Kind $Mode -RunTrial $TrialRunner -PerRunCredits $MaxCredits -SeriesCredits $MaxSeriesCredits -BaselineEvidence $Saved -ExpectedCompatibility $Expected -ObservationOnly:$ObservationOnly
            foreach ($Slot in $Series.report.slots) {
                if ($Slot.status -ne 'failed') { continue }
                $Prefix = "$($Slot.arm)-$($Slot.pair)"
                $Candidates = @("out/$Prefix-launch.jsonl.stderr", "out/$Prefix-launch.jsonl.exception.txt", "trials/$Prefix/out/error.json", "trials/$Prefix/out/run.json")
                foreach ($StageName in @('init', 'requirements', 'build', 'judge')) { $Candidates += "trials/$Prefix/out/$StageName-stdout.jsonl.stderr" }
                $Slot['evidence'] = @($Candidates | Where-Object { Test-Path -LiteralPath (Join-Path $TrialRoot $_) -PathType Leaf })
            }
            $Series.report | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath (Join-Path $Out 'report.json') -Encoding utf8NoBOM
            @{ runs = $Series.runs } | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath (Join-Path $Out 'series-evidence.json') -Encoding utf8NoBOM
            if ($Series.controls) { $Series.controls | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath (Join-Path $Out 'control-series.json') -Encoding utf8NoBOM }
            $Lines = @('# Squad efficiency series', '', $Series.report.message, '', "Outcome: $($Series.report.outcome)", "Regression verdict: $($Series.report.regressionVerdict)", '', '## Quality', '', '| Arm | Pair | Quality /100 |', '|---|---:|---:|')
            foreach ($Score in $Series.report.quality.scores) { $Lines += "| $($Score.arm) | $($Score.pair) | $($Score.total) |" }
            $Lines += @('', '## Efficiency', '')
            if ($Series.report.comparison) {
                $Lines += @('| Metric | Baseline | Candidate | Change % |', '|---|---:|---:|---:|')
                foreach ($Name in @('modelRequests', 'inputTokens', 'outputTokens', 'toolCalls', 'failedTools', 'quality', 'reliability', 'criticalHighFindings')) {
                    if (-not $Series.report.comparison.metrics.ContainsKey($Name)) { continue }
                    $Metric = $Series.report.comparison.metrics[$Name]
                    $Change = if ($null -eq $Metric.changePercent) { 'n/a' } else { $Metric.changePercent.ToString('F2', [Globalization.CultureInfo]::InvariantCulture) }
                    $Lines += "| $Name | $($Metric.baseline) | $($Metric.candidate) | $Change |"
                }
                $Lines += @('', 'Gate reasons:') + @($Series.report.comparison.reasons | ForEach-Object { '* ' + $_ })
            }
            else { $Lines += 'No baseline/candidate deltas are available for this outcome.' }
            $Lines += @('', '## Trial Outcomes', '', "Collection policy: $($Series.report.collectionPolicy). Samples: $($Series.report.reliability.samples). Workflow completed: $($Series.report.reliability.workflowCompleted). Independent checks passed: $($Series.report.reliability.independentChecksPassed).", '', '| Arm | Pair | Status |', '|---|---:|---|')
            foreach ($Slot in $Series.report.slots) { $Lines += "| $($Slot.arm) | $($Slot.pair) | $($Slot.status) |" }
            $Recoveries = @(foreach ($Trial in $Series.report.trials) {
                foreach ($TrialStage in $Trial.stages) {
                    if ($TrialStage.recovery -and $TrialStage.recovery.count -gt 0) {
                        [pscustomobject]@{ arm = $Trial.arm; pair = $Trial.pair; stage = $TrialStage.name; status = $TrialStage.recovery.status; reason = $TrialStage.recovery.reason; calls = @($TrialStage.attempts).Count; seconds = $TrialStage.process.seconds }
                    }
                }
            })
            if ($Recoveries.Count) {
                $Lines += @('', '## Context Recovery', '', '| Arm | Pair | Stage | Calls Including Initial | Status | Reason | Stage Seconds |', '|---|---:|---|---:|---|---|---:|')
                foreach ($RecoveryRow in $Recoveries) { $Lines += "| $($RecoveryRow.arm) | $($RecoveryRow.pair) | $($RecoveryRow.stage) | $($RecoveryRow.calls) | $($RecoveryRow.status) | $($RecoveryRow.reason) | $($RecoveryRow.seconds) |" }
            }
            $FailedSlots = @($Series.report.slots | Where-Object status -EQ 'failed')
            if ($FailedSlots.Count) {
                $Lines += @('', '## Failure Diagnostics', '', 'Raw diagnostics stay local and may contain sensitive content. Review before sharing.')
                foreach ($Slot in $FailedSlots) {
                    $Lines += @('', "Failed: $($Slot.arm) pair $($Slot.pair); category: $($Slot.reason).")
                    if ($Slot.ContainsKey('childExitCode')) { $Lines += "Child exit: $($Slot.childExitCode); stop cause: $($Slot.stopCause)." }
                    if ($Slot.ContainsKey('failedStages')) {
                        foreach ($FailedStage in $Slot.failedStages) {
                            $Lines += "Stage: $($FailedStage.name); exit: $($FailedStage.exitCode); stop cause: $($FailedStage.stopCause)."
                            if ($FailedStage.failedChecks.Count) { $Lines += "Failed readiness checks: $($FailedStage.failedChecks -join ', ')." }
                            if ($FailedStage.recovery -and $FailedStage.recovery.count -gt 0) { $Lines += "Context recovery: $($FailedStage.recovery.status); reason: $($FailedStage.recovery.reason)." }
                        }
                    }
                    foreach ($Evidence in $Slot.evidence) { $Lines += "* $Evidence" }
                    if (-not $Slot.evidence.Count) { $Lines += 'No child evidence was written; inspect local launcher errors. No passing outcome was recorded.' }
                }
            }
            $Lines += @('', 'Hook interval sums/unions are diagnostics, not blocking-time measurements. No composite score is used. Accepted baseline unchanged.')
            $Lines | Set-Content -LiteralPath (Join-Path $Out 'report.md') -Encoding utf8NoBOM
            Write-Host $Series.report.message
            Write-Host "Quality: $($Series.report.quality.checksPassed). Regression: $($Series.report.regressionVerdict). Report: $(Join-Path $Out 'report.md')"
            foreach ($Slot in $FailedSlots) {
                Write-Host "Failed $($Slot.arm) pair $($Slot.pair): $($Slot.reason)"
                if ($Slot.ContainsKey('childExitCode')) { Write-Host "Child exit: $($Slot.childExitCode); stop cause: $($Slot.stopCause)" }
                if ($Slot.ContainsKey('failedStages')) {
                    foreach ($FailedStage in $Slot.failedStages) {
                        Write-Host "Stage: $($FailedStage.name); exit: $($FailedStage.exitCode); stop cause: $($FailedStage.stopCause)"
                        if ($FailedStage.failedChecks.Count) { Write-Host "Failed readiness checks: $($FailedStage.failedChecks -join ', ')" }
                        if ($FailedStage.recovery -and $FailedStage.recovery.count -gt 0) { Write-Host "Context recovery: $($FailedStage.recovery.status); reason: $($FailedStage.recovery.reason)" }
                    }
                }
                foreach ($Evidence in $Slot.evidence) { Write-Host "Diagnostic: $(Join-Path $TrialRoot $Evidence)" }
            }
            exit $Series.exitCode
        }
        $ProgressStep = 1; $ProgressLabel = 'Preparing workspace'
        Write-EfficiencyProgress -Step $ProgressStep -Label $ProgressLabel -Path $ProgressPath
        if (-not $TrialRoot -or -not $SourceRoot -or -not $InstallRoot) { throw 'Run requires TrialRoot, SourceRoot and a prepared full InstallRoot.' }
        if (Test-Path -LiteralPath $TrialRoot) { throw 'TrialRoot must not exist.' }
        $SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
        $InstallRoot = (Resolve-Path -LiteralPath $InstallRoot).Path
        $InstalledAgents = Join-Path $InstallRoot '.github/agents'
        if (-not (Test-Path -LiteralPath $InstalledAgents -PathType Container)) { throw 'Prepared install lacks deployed .github/agents.' }
        foreach ($Name in @('brd-builder.agent.md', 'prd-builder.agent.md', 'squad-coordinator.agent.md')) {
            if (-not (Get-ChildItem -LiteralPath $InstalledAgents -Recurse -File -Force -Filter $Name | Select-Object -First 1)) { throw "Prepared install lacks $Name" }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/agents'))) { throw 'SourceRoot must contain squad-src.' }
        if (Test-Path -LiteralPath (Join-Path $InstallRoot '.copilot-tracking')) { throw 'Prepared install must not contain runtime state.' }
        if (-not $CliPath) { $CliPath = (Get-Command copilot -ErrorAction Stop).Source }
        $CliPath = (Resolve-Path -LiteralPath $CliPath).Path
        $HelpText = (& $CliPath --help | Out-String)
        foreach ($Flag in @('--session-id', '--max-ai-credits', '--no-ask-user', '--max-autopilot-continues', '--usage-output-file', '--add-dir')) {
            if (-not $HelpText.Contains($Flag)) { throw "Installed CLI does not support $Flag" }
        }
        $Revision = (& git -C $SourceRoot rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source revision.' }
        Import-Module (Join-Path $PSScriptRoot '../../lib/SquadInstall.psm1') -Force
        Import-Module (Join-Path $PSScriptRoot 'LiveBenchmark.psm1') -Force
        $DisabledServers = @(Get-ConfiguredMcpServerNames -CliPath $CliPath)
        $TrialRoot = [IO.Path]::GetFullPath($TrialRoot)
        $Workspace = Join-Path $TrialRoot 'workspace'; $Out = Join-Path $TrialRoot 'out'
        New-Item -ItemType Directory -Path $Workspace, $Out | Out-Null
        foreach ($Directory in @('.github', '.agents', 'apm_modules')) {
            $From = Join-Path $InstallRoot $Directory
            if (Test-Path -LiteralPath $From) { Copy-Item -LiteralPath $From -Destination $Workspace -Recurse -Force }
        }
        Copy-SquadSource -From (Join-Path $SourceRoot 'squad-src') -To $Workspace -NativeCli
        New-Item -ItemType Directory -Path (Join-Path $Workspace '.copilot-tracking/squad/history') -Force | Out-Null
        $ScenarioPath = Join-Path $PSScriptRoot 'efficiency-scenario.json'
        $Scenario = Get-Content -LiteralPath $ScenarioPath -Raw | ConvertFrom-Json -AsHashtable
        Set-Content -LiteralPath (Join-Path $Workspace 'EXERCISE.txt') -Value ($Scenario.brief + "`n" + $Scenario.contract) -Encoding utf8NoBOM
        $Session = [guid]::NewGuid().ToString()
        $SessionEvents = Join-Path $HOME ".copilot/session-state/$Session/events.jsonl"
        if (Test-Path -LiteralPath $SessionEvents) { throw 'Fresh session UUID unexpectedly exists.' }
        $Common = 'This is a synthetic, preauthorized exercise in an isolated environment. Make all routine product and planning decisions from EXERCISE.txt. Do not ask questions, deploy, publish externally, access secrets, use external systems or install packages. Preserve all squad gates, state/history and role Deliverable Roots. If a safety or evidence gate cannot be satisfied, stop and record the blocker. No claim of human review unless actually provided.'
        if ($ObservationOnly) {
            $Common = 'This is a synthetic baseline-measurement exercise in an isolated environment. Make routine decisions from EXERCISE.txt. Run the requested local work and reviews, preserving their real findings, state/history and role Deliverable Roots. Quality scores and bookkeeping failures are observations, not benchmark stop gates: record them and continue feasible local work without repeated remediation merely to reach a benchmark threshold. Do not fabricate missing artifacts, successful tests or human approval. Do not deploy, publish externally, access secrets, use external systems or install packages. Stop for a real safety boundary or required human authorization and record it.'
        }
        $Common += " The authorized local root is '$Workspace'; resolve installed skills from '$Workspace/.agents/skills' and customization from '$Workspace/.github'. Keep discovery and scripts inside that root, without parent traversal. Prefer native read/list/search tools; split large reference reads into explicit ranges covering all required sections. Send one complete Scribe handoff per completed dispatch, in order; do not merge stages into catch-up payloads or invent missing reviewer outputs."
        $Common += " Prepend this context to every dispatched role and Scribe prompt, outside any schema payload: absolute workspace '$Workspace'; absolute skill root '$Workspace/.agents/skills'. Do not assume children inherit the working directory or discover skills from home directories."
        $Prompts = [ordered]@{
            init = "$Common Initialize the squad with profile=product and mode=autopilot. Use the current installed squad implementation. Set up the roster and routing, including BRD and PRD capability. Initialization only; no substantive business deliverables yet."
            requirements = "$Common Using the initialized squad, create both a BRD and a PRD for EXERCISE.txt. Use mapped requirements agents and the required methodology. Author and review roster-root drafts first. Before requesting review, complete the authors' required self-validation checklists and reconcile cross-document IDs, counts and traceability; keep acceptance-criterion references unambiguous. Assess business clarity, scope fidelity, acceptance criteria, traceability, and risks/decisions. Record evidence-grounded risks with mitigations and owners, assumptions and decisions; distinguish engineering choices from mandatory product requirements. Use BR-nnn and FR-nnn identifiers and explicit measurable acceptance criteria. All scenario facts are synthetic and the fixed brief is authoritative; do not add unsupported requirements or invent deadlines. Resolve required domain-review findings, then dispatch the roster's tester role for a separate independent closing review of the final roster-root drafts. Domain quality reviews do not replace that tester dispatch, its review artifact or its Scribe history. This is a requirements-only stage: no implementation or destination copies are expected during that review. Only after all required reviews pass, copy the reviewed documents byte-for-byte to docs/requirements/brd.md and docs/requirements/prd.md. These are local copies, not external publication or human approval."
            build = "$Common Implement docs/requirements/prd.md and the frozen EXERCISE.txt CLI contract through a complete Research, Plan, Implement, Review cycle with the mapped roles. Produce src/task.ps1, tests and a short README. Before closing review, test persisted ID boundaries and data preservation: an add must never report success then leave storage unreadable; if an increasing integer cannot be represented, fail without modifying stored bytes. Do not defer known data corruption merely because it needs a seeded boundary case. Run your own tests, preserve independent closing review and state/ledger integrity. Do not invent successful tests; disclose host-only validation limits. Record remaining required findings as blockers."
        }
        if ($ObservationOnly) {
            $Prompts.requirements = "$Common Using the initialized squad and mapped requirements roles, produce a BRD and PRD for EXERCISE.txt and collect independent domain and closing reviews. Preserve unresolved findings as measured quality results; do not repeatedly rewrite merely to reach a quality threshold. Keep roster-root deliverables and copy available drafts byte-for-byte to docs/requirements/brd.md and docs/requirements/prd.md for independent measurement, clearly identifying them as unapproved baseline artifacts. Missing or failed review is a recorded outcome, not permission to claim approval."
            $Prompts.build = "$Common Implement the frozen EXERCISE.txt CLI contract using available requirements, mapped roles and a Research, Plan, Implement, Review cycle. Produce src/task.ps1, tests and a short README. Run your own tests and closing review; record actual failures, unresolved findings and missing evidence rather than inventing success. This stage must still attempt feasible work if the preceding stage had quality or bookkeeping failures."
        }
        $Compatibility = Get-EfficiencyCompatibility -SourceRoot $SourceRoot -InstallRoot $InstallRoot -CliPath $CliPath -Model $Model -MaxCredits $MaxCredits -ObservationOnly:$ObservationOnly
        $Metadata = @{ runId = [guid]::NewGuid().ToString(); pair = $Pair; arm = $Arm; revision = $Revision; sourceHash = Get-EfficiencyTreeHash (Join-Path $SourceRoot 'squad-src'); hostProfile = $Compatibility.hostProfile; compatibility = $Compatibility; sessionId = $Session; started = [datetime]::UtcNow.ToString('o') }
        $Metadata | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $Out 'metadata.json') -Encoding utf8NoBOM
        $Stages = [Collections.Generic.List[object]]::new()
        $AllPassed = $true; $StartLine = 0; $Metrics = $null
        $SessionCreditCeiling = $RecoveryPolicy.workflowCredits
        # Reserve the independent judge's existing ten-request allowance.
        $WorkflowRequestCeiling = if ($ObservationOnly) { [int]::MaxValue } else { [int]$Scenario.maxModelRequests - 10 }
        $WorkflowSeconds = if ($ObservationOnly) { [int]$Scenario.observationTimeoutMinutes * 60 } else { [int]$Scenario.timeoutMinutes * 60 }
        $Watch = [Diagnostics.Stopwatch]::StartNew()
        Write-EfficiencyProgress -Step $ProgressStep -Label $ProgressLabel -Status finished -Path $ProgressPath
        $StageLabels = [ordered]@{ init = 'Initializing squad'; requirements = 'Writing requirements'; build = 'Building product' }
        foreach ($Stage in $Prompts.Keys) {
            $ProgressStep++; $ProgressLabel = $StageLabels[$Stage]
            Write-EfficiencyProgress -Step $ProgressStep -Label $ProgressLabel -Path $ProgressPath
            $StageWatch = [Diagnostics.Stopwatch]::StartNew()
            $StageStartLine = $StartLine; $PreviousMetrics = $Metrics
            $PriorRequests = if ($Metrics -and $null -ne $Metrics.modelRequests) { $Metrics.modelRequests } else { 0 }
            $StageRequestCeiling = $WorkflowRequestCeiling - $PriorRequests
            $Attempts = [Collections.Generic.List[object]]::new()
            $Recovery = @{ count = 0; status = 'not-needed'; reason = $null; resolvedDiscoveryDenials = 0 }
            $UsagePath = Join-Path $Out "$Stage-usage.json"
            $CliArgs = @('-p', $Prompts[$Stage], '--agent', 'squad-coordinator', '--model', $Model, '--session-id', $Session, '--autopilot', '--max-autopilot-continues', '2', '--max-ai-credits', $SessionCreditCeiling.ToString('R', [Globalization.CultureInfo]::InvariantCulture), '--allow-all-tools', '--add-dir', $Workspace, '--no-ask-user', '--disable-builtin-mcps', '--output-format', 'json', '--usage-output-file', $UsagePath, '--secret-env-vars=GH_TOKEN,GITHUB_TOKEN,COPILOT_GITHUB_TOKEN')
            if ($ObservationOnly) { $CliArgs[[array]::IndexOf($CliArgs, '--max-autopilot-continues') + 1] = '1000'; $StageRequestCeiling = 0 }
            foreach ($Server in $DisabledServers) { $CliArgs += @('--disable-mcp-server', $Server) }
            foreach ($Denied in @('shell(git push)', 'shell(gh)', 'shell(az)', 'shell(curl)', 'shell(wget)', 'shell(Invoke-WebRequest)', 'shell(Invoke-RestMethod)', 'shell(Start-Process)')) { $CliArgs += @('--deny-tool', $Denied) }
            $Executable = $CliPath
            if ($CliPath.EndsWith('.ps1')) { $Executable = (Get-Command pwsh).Source; $CliArgs = @('-NoProfile', '-File', $CliPath) + $CliArgs }
            $InitialSeconds = [Math]::Floor($WorkflowSeconds - $Watch.Elapsed.TotalSeconds)
            $Result = if (-not $ObservationOnly -and $StageRequestCeiling -lt 1) { [pscustomobject]@{ exitCode = -1; stopCause = 'request-limit'; seconds = 0; observedRequests = 0 } } elseif ($InitialSeconds -ge 1) { Invoke-EfficiencyProcess -FilePath $Executable -Arguments $CliArgs -WorkingDirectory $Workspace -OutputPath (Join-Path $Out "$Stage-stdout.jsonl") -TimeoutSeconds ([int]$InitialSeconds) -EventsPath $SessionEvents -StartLine $StageStartLine -MaxRequests $StageRequestCeiling -MaxCredits $SessionCreditCeiling -EnvironmentVariables @{ GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS = 'true' } } else { [pscustomobject]@{ exitCode = -1; stopCause = 'timeout'; seconds = 0; observedRequests = 0 } }
            $Saved = Save-EfficiencyAttemptEvidence -EventsPath $SessionEvents -Out $Out -Prefix $Stage
            $Metrics = $Saved.metrics; $StartLine = $Saved.lineCount
            $StagePassed = ($Result.exitCode -eq 0 -and $Result.stopCause -eq 'none' -and $null -ne $Metrics -and $Metrics.complete -and $null -ne $Metrics.modelRequests -and $Metrics.modelRequests -le $WorkflowRequestCeiling -and $Metrics.counts.questions -eq 0)
            $Readiness = if ($StagePassed) { Test-EfficiencyWorkflow -Workspace $Workspace -Metrics $Metrics -Stage $Stage } else { [pscustomobject]@{ passed = $false; checks = @{ processEvidence = $false }; reviewPath = $null } }
            $StagePassed = $StagePassed -and $Readiness.passed -and $Watch.Elapsed.TotalSeconds -le $WorkflowSeconds
            $Attempts.Add(@{ kind = 'stage'; process = $Result; readiness = $Readiness; passed = $StagePassed; sessionCreditCeiling = $SessionCreditCeiling; evidence = @(@("out/$Stage-stdout.jsonl", "out/$Stage-events.jsonl", "out/$Stage-metrics.json") | Where-Object { Test-Path -LiteralPath (Join-Path $TrialRoot $_) -PathType Leaf }) })
            if (-not $StagePassed -and -not $ObservationOnly) {
                $RemainingRequests = if ($Metrics -and $null -ne $Metrics.modelRequests) { $WorkflowRequestCeiling - $Metrics.modelRequests } else { 0 }
                $RemainingSeconds = $WorkflowSeconds - $Watch.Elapsed.TotalSeconds
                $Decision = Get-EfficiencyRecoveryDecision -Path (Join-Path $Out "$Stage-stdout.jsonl") -Workspace $Workspace -Metrics $Metrics -Process $Result -Readiness $Readiness -RemainingRequests $RemainingRequests -RemainingSeconds $RemainingSeconds -AcpSupported ($HelpText.Contains('--acp')) -RecoveryUsed $false
                $Recovery.status = 'not-eligible'; $Recovery.reason = $Decision.reason
                $Recovery.resolvedDiscoveryDenials = $Decision.resolvedDiscoveryDenials
                if ($Decision.allowed -and [Math]::Floor($RemainingSeconds) -ge 1) {
                    $Recovery.count = 1; $Recovery.status = 'attempted'
                    Write-EfficiencyProgress -Step $ProgressStep -Label "$ProgressLabel (context recovery)" -Path $ProgressPath
                    $Compact = Invoke-EfficiencyCompaction -CliPath $CliPath -SessionId $Session -Workspace $Workspace -EventsPath $SessionEvents -OutputPath (Join-Path $Out "$Stage-compaction-stdout.jsonl") -UsagePath (Join-Path $Out "$Stage-compaction-usage.json") -MaxCredits $SessionCreditCeiling -Model $Model -TimeoutSeconds ([int][Math]::Min(300, [Math]::Floor($RemainingSeconds))) -StartLine $StageStartLine -MaxRequests $StageRequestCeiling -DisabledServers $DisabledServers -EnvironmentVariables @{ GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS = 'true' }
                    $Saved = Save-EfficiencyAttemptEvidence -EventsPath $SessionEvents -Out $Out -Prefix "$Stage-compaction"
                    $Metrics = $Saved.metrics; $StartLine = $Saved.lineCount
                    $Attempts.Add(@{ kind = 'compaction'; process = $Compact; passed = $Compact.succeeded; sessionCreditCeiling = $SessionCreditCeiling; evidence = @(@("out/$Stage-compaction-stdout.jsonl", "out/$Stage-compaction-events.jsonl", "out/$Stage-compaction-metrics.json") | Where-Object { Test-Path -LiteralPath (Join-Path $TrialRoot $_) -PathType Leaf }) })
                    $RemainingSeconds = $WorkflowSeconds - $Watch.Elapsed.TotalSeconds
                    $WithinRequests = $Metrics -and $null -ne $Metrics.modelRequests -and $Metrics.modelRequests -lt $WorkflowRequestCeiling
                    if ($Compact.succeeded -and $Metrics -and $Metrics.complete -and $Metrics.counts.questions -eq 0 -and $WithinRequests -and [Math]::Floor($RemainingSeconds) -ge 1) {
                        Write-EfficiencyProgress -Step $ProgressStep -Label "$ProgressLabel (continuation)" -Path $ProgressPath
                        $ContinueArgs = @($CliArgs)
                        $ContinueArgs[[array]::IndexOf($ContinueArgs, '-p') + 1] = $Prompts[$Stage] + ' This is a continuation of this same stage after verified context compaction, not a new run. Resume only the interrupted Scribe handoff first; inspect existing history and do not duplicate it or rerun completed specialist roles. After the handoff verifies, finish only the pending stage work. Preserve run identity, artifacts and safety gates. If still blocked, record the remaining blocker and stop; no further recovery is allowed.'
                        $ContinueArgs[[array]::IndexOf($ContinueArgs, '--max-ai-credits') + 1] = $SessionCreditCeiling.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
                        $ContinueArgs[[array]::IndexOf($ContinueArgs, '--usage-output-file') + 1] = Join-Path $Out "$Stage-continuation-usage.json"
                        $Result = Invoke-EfficiencyProcess -FilePath $Executable -Arguments $ContinueArgs -WorkingDirectory $Workspace -OutputPath (Join-Path $Out "$Stage-continuation-stdout.jsonl") -TimeoutSeconds ([int][Math]::Floor($RemainingSeconds)) -EventsPath $SessionEvents -StartLine $StageStartLine -MaxRequests $StageRequestCeiling -MaxCredits $SessionCreditCeiling -EnvironmentVariables @{ GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS = 'true' }
                        $Saved = Save-EfficiencyAttemptEvidence -EventsPath $SessionEvents -Out $Out -Prefix "$Stage-continuation"
                        $Metrics = $Saved.metrics; $StartLine = $Saved.lineCount
                        $StagePassed = ($Result.exitCode -eq 0 -and $Result.stopCause -eq 'none' -and $Metrics -and $Metrics.complete -and $null -ne $Metrics.modelRequests -and $Metrics.modelRequests -le $WorkflowRequestCeiling -and $Metrics.counts.questions -eq 0 -and $Watch.Elapsed.TotalSeconds -le $WorkflowSeconds)
                        $Readiness = if ($StagePassed) { Test-EfficiencyWorkflow -Workspace $Workspace -Metrics $Metrics -Stage $Stage } else { [pscustomobject]@{ passed = $false; checks = @{ processEvidence = $false }; reviewPath = $null } }
                        $StagePassed = $StagePassed -and $Readiness.passed -and $Watch.Elapsed.TotalSeconds -le $WorkflowSeconds
                        $Attempts.Add(@{ kind = 'continuation'; process = $Result; readiness = $Readiness; passed = $StagePassed; sessionCreditCeiling = $SessionCreditCeiling; evidence = @(@("out/$Stage-continuation-stdout.jsonl", "out/$Stage-continuation-events.jsonl", "out/$Stage-continuation-metrics.json") | Where-Object { Test-Path -LiteralPath (Join-Path $TrialRoot $_) -PathType Leaf }) })
                        $Recovery.status = if ($StagePassed) { 'recovered' } else { 'failed' }
                        $Recovery.reason = if ($StagePassed) { 'context-compacted' } else { 'continuation-incomplete' }
                    }
                    else { $Recovery.status = 'failed'; $Recovery.reason = if (-not $Compact.succeeded) { $Compact.stopCause } elseif (-not $WithinRequests -or $RemainingSeconds -lt 1) { 'stage-limit' } else { 'incomplete-metering' } }
                }
            }
            $Delta = @{}
            if ($Metrics) {
                foreach ($Field in @('inputTokens', 'outputTokens', 'cacheReadTokens', 'cacheWriteTokens', 'requestBodyBytes', 'toolTokenCount')) {
                    $Prior = if ($PreviousMetrics) { $PreviousMetrics.totals[$Field] } else { 0 }
                    $Delta[$Field] = if ($null -ne $Metrics.totals[$Field] -and $null -ne $Prior) { $Metrics.totals[$Field] - $Prior } else { $null }
                }
            }
            $StageProcess = @{ exitCode = $Result.exitCode; stopCause = $Result.stopCause; seconds = [Math]::Round($StageWatch.Elapsed.TotalSeconds, 3); observedRequests = if ($Metrics -and $null -ne $Metrics.modelRequests) { $Metrics.modelRequests - $PriorRequests } else { $null } }
            $Stages.Add(@{ name = $Stage; process = $StageProcess; readiness = $Readiness; attempts = @($Attempts); recovery = $Recovery; metrics = $Metrics; metricScope = 'cumulative-session'; stageTokenDelta = $Delta; passed = $StagePassed })
            Write-EfficiencyProgress -Step $ProgressStep -Label $ProgressLabel -Status finished -Path $ProgressPath
            if (-not $StagePassed) {
                $AllPassed = $false
                if (-not $ObservationOnly -or $Result.stopCause -ne 'none' -or -not $Metrics -or -not $Metrics.credits.complete) { break }
            }
        }
        foreach ($SkippedStage in @($StageLabels.Keys | Select-Object -Skip $Stages.Count)) {
            $ProgressStep++
            Write-EfficiencyProgress -Step $ProgressStep -Label $StageLabels[$SkippedStage] -Status skipped -Path $ProgressPath
        }
        $ProgressStep = 5; $ProgressLabel = 'Checking acceptance and workflow'
        Write-EfficiencyProgress -Step $ProgressStep -Label $ProgressLabel -Path $ProgressPath
        $Acceptance = & (Join-Path $PSScriptRoot 'Test-EfficiencyTask.ps1') -Workspace $Workspace | ConvertFrom-Json -AsHashtable
        $Workflow = if ($Stages[-1].name -eq 'build') { $Stages[-1].readiness } else { Test-EfficiencyWorkflow -Workspace $Workspace -Metrics $Metrics }
        Write-EfficiencyProgress -Step $ProgressStep -Label $ProgressLabel -Status finished -Path $ProgressPath
        $ProgressStep = 6; $ProgressLabel = 'Judging documents'
        $Judge = $null
        if (($ObservationOnly -or ($AllPassed -and $Acceptance.passed -and $Workflow.passed)) -and $Watch.Elapsed.TotalSeconds -lt $WorkflowSeconds) {
            Write-EfficiencyProgress -Step $ProgressStep -Label $ProgressLabel -Path $ProgressPath
            $Judge = Invoke-EfficiencyJudge -Workspace $Workspace -Out $Out -CliPath $CliPath -Model $Model -MaxCredits $RecoveryPolicy.judgeCredits -ReviewPath ([string]$Workflow.reviewPath) -TimeoutSeconds ([Math]::Max(1, [Math]::Min(300, $WorkflowSeconds - $Watch.Elapsed.TotalSeconds))) -ObservationOnly:$ObservationOnly
            Write-EfficiencyProgress -Step $ProgressStep -Label $ProgressLabel -Status finished -Path $ProgressPath
        }
        else { Write-EfficiencyProgress -Step $ProgressStep -Label $ProgressLabel -Status skipped -Path $ProgressPath }
        $ProgressStep = 7; $ProgressLabel = 'Saving run evidence'
        Write-EfficiencyProgress -Step $ProgressStep -Label $ProgressLabel -Path $ProgressPath
        $Run = @{ schemaVersion = $Scenario.schemaVersion; metadata = $Metadata; stages = @($Stages); metrics = $Metrics; acceptance = $Acceptance; workflow = $Workflow; judge = $Judge; completed = ($AllPassed -and $Acceptance.passed -and $Workflow.passed -and $null -ne $Judge -and $Judge.valid) }
        if ($ObservationOnly) { $Run.collection = @{ policy = 'baseline-observation-v1'; recorded = $true; stagesAttempted = $Stages.Count; judgeAvailable = ($null -ne $Judge -and $Judge.valid) } }
        $Run | ConvertTo-Json -Depth 45 | Set-Content -LiteralPath (Join-Path $Out 'run.json') -Encoding utf8NoBOM
        $Succeeded = Test-EfficiencyRun $Run -ObservationOnly:$ObservationOnly
        Write-EfficiencyProgress -Step $ProgressStep -Label $ProgressLabel -Status finished -Path $ProgressPath
        Write-Host "Run complete: $($Run.completed). Independent checks passed: $Succeeded. Report: $(Join-Path $Out 'run.json')"
        if ($ObservationOnly) {
            $Recorded = Test-EfficiencyObservation $Run
            Write-Host "Baseline observation recorded: $Recorded. Failed checks remain findings, not a passing workflow."
            if (-not $Recorded) { exit 2 }
        }
        elseif (-not $Succeeded) { exit 2 }
    }
    catch {
        if ($null -ne $ProgressStep) { Write-EfficiencyProgress -Step $ProgressStep -Label $ProgressLabel -Status failed -Path $ProgressPath }
        if ($Out -and (Test-Path -LiteralPath $Out)) {
            @{ schemaVersion = 'efficiency-error-v1'; outcome = 'incomplete'; reason = 'execution-or-evidence-error'; acceptedBaselineChanged = $false } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Out 'error.json') -Encoding utf8NoBOM
        }
        Write-Error -Message $_.Exception.Message -ErrorAction Continue
        exit 1
    }
}