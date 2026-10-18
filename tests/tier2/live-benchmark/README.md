---
description: "Inventory benchmarks and the unattended squad efficiency regression exercise"
---

# Live benchmark harness

Offline self-tests do not call models. Live benchmark and judge scripts spend credits.

## Prerequisites

- PowerShell 7.4 or later
- Python 3 with pytest: `python -m pip install pytest`, or use a venv
- APM 0.29.0
- GitHub Copilot CLI
- `COPILOT_GITHUB_TOKEN` for live runs

## Arms and defaults

- A: baseline source, routing off
- B: candidate source, routing off
- C: baseline source, `routing=ranked`
- D: candidate source, `routing=ranked`
- E: candidate source, `routing=economy`
- F: optional candidate source, `routing=economy delivery=background`

Default live matrix: arms A to E (F runs every selected level; the easy task has three independent items, so pair F with `-Levels easy` when only background delivery is under test), 8 repeats per cell, model `claude-sonnet-5.5`, blind judge on. Use `-SkipJudge` to report unjudged results. Use `-Arms A,B,C,D,E,F` to include F.

## stopCause values

`stopCause` is classified in this order: `intake-escalation`, `handoff-failure` (with exit code when present), `ledger-crash`, `rate-limit`, `cli-error`, `none`, `unknown`.

## Run offline self-tests

```powershell
python -m venv $env:TEMP\bench-venv
& "$env:TEMP\bench-venv\Scripts\python.exe" -m pip install pytest
$env:PATH = "$env:TEMP\bench-venv\Scripts" + [IO.Path]::PathSeparator + $env:PATH
pwsh -NoProfile -File tests\tier2\live-benchmark\Invoke-LiveBenchmarkTests.ps1 -Output Normal
```

## Unattended efficiency exercise

This is a separate scenario beside the existing inventory arms, not a replacement.
One `Run` executes cold Squad Coordinator initialization, BRD and PRD authoring,
the complete RPI task-CLI build, independent functional/state/history checks, and
independent document judging. Routine decisions come from the frozen
[efficiency-scenario.json](efficiency-scenario.json); `ask_user` is disabled.

`Establish` runs three controls. `Series` runs three baseline/candidate pairs in
AB, BA, AB order and automatically scores, aggregates and compares. Both stop
without questions and leave a terminal summary plus reports. A failed trial is
not retried: it and the remaining not-run slots are retained as an incomplete
series. A successful comparison never promotes an accepted report automatically.

### Live prerequisites

* PowerShell 7.4+, Git, and an authenticated Copilot CLI supporting `--session-id`,
	`--max-ai-credits`, `--max-autopilot-continues`, `--no-ask-user`, `--no-remote`,
	`--no-remote-export`, and `--usage-output-file`
* A clean, prepared full squad/hve-core installation containing deployed BRD
	Builder, PRD Builder, Squad Coordinator and their dependencies, with no runtime
	tracking state; a squad-only source overlay is insufficient
* Source checkout(s) containing `squad-src/`; keep each source unchanged during
	its repetitions. The harness overlays the chosen source onto the same prepared
	installation and records revision, content hashes, CLI/model/role policy,
	fixture/rubric/parser/grader and dependency identity.
* A disposable OS-isolated environment, restricted credentials and no sensitive
	source data. `-IsolatedEnvironment` acknowledges this prerequisite; it does not
	create a sandbox. Shell tool filters cannot isolate arbitrary shell code.
* Explicit per-run and series credit ceilings. The examples are ceilings, not
	cost predictions; choose them for your subscription before launching.

All commands below are launched locally by the operator, never by offline tests.
Example paths must be set to your existing prepared install and chosen output
volume. Evidence directories must not already exist. Run from the repository root.

```powershell
$Harness = Join-Path $PWD 'tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1'
$Install = 'C:\bench\squad-installed'
$Source = $PWD.Path
$Evidence = 'C:\bench\squad-efficiency'
```

To prepare an installation separately using the existing installer, use an empty
destination and a pinned source checkout. This step needs APM and network access,
but does not call a model. Review the installed package before live execution.

```powershell
Import-Module ./tests/lib/SquadInstall.psm1 -Force
Install-SquadPackage -Destination $Install -SourceRoot $Source
```

### Establish the first control

This single command runs three complete control trials unattended. It does not
claim an improvement or invent a previous score. On success the terminal and
report state `baseline established; no previous comparison available`.

```powershell
pwsh -NoProfile -File $Harness -Mode Establish `
	-SourceRoot $Source -InstallRoot $Install `
	-TrialRoot "$Evidence\control-001" `
	-MaxCredits 100 -MaxSeriesCredits 300 -Live -IsolatedEnvironment
$LASTEXITCODE
```

The control is frozen in `control-001/out/control-series.json`. Establishment
creates new evidence only; it does not overwrite an accepted optimization report.

### Run a complete comparison

After making a candidate change, reuse the three saved controls with this one
command. The fixture, parser, grader, model/role policy, CLI, installed dependency
identity and per-run limits must still match. Pair IDs and control source identity
must be consistent; otherwise reuse is refused before any trial is launched.

```powershell
pwsh -NoProfile -File $Harness -Mode Series `
	-CandidateSourceRoot $Source -InstallRoot $Install `
	-BaselineEvidencePath "$Evidence\control-001\out\control-series.json" `
	-TrialRoot "$Evidence\comparison-001" `
	-MaxCredits 100 -MaxSeriesCredits 300 -Live -IsolatedEnvironment
$LASTEXITCODE
```

To rerun both arms instead, use two existing source checkouts and reserve six
trial ceilings. This performs all six trials and comparison in one invocation.

```powershell
pwsh -NoProfile -File $Harness -Mode Series `
	-BaselineSourceRoot 'C:\bench\control-source' `
	-CandidateSourceRoot $Source -InstallRoot $Install `
	-TrialRoot "$Evidence\comparison-002" `
	-MaxCredits 100 -MaxSeriesCredits 600 -Live -IsolatedEnvironment
$LASTEXITCODE
```

The complete scheduled reservation must fit `MaxSeriesCredits` before any model
call. A run allocates a quarter of `MaxCredits` to each of its three coordinator
invocations and the independent judge. Resumed-session CLI accounting may make
this more conservative. No outer stage/trial retries are performed. Each stage
has at most two host continuations and a 15-minute watchdog within a 45-minute
run budget; the judge has at most five minutes within the remaining budget.
Observed usage stops a stage at 96 records or an unexpected `ask_user` invocation;
the judge has a ten-record bound, and >300 total metered requests fails eligibility.
Parallel in-flight requests can cross an observed-event threshold before
termination; the CLI credit ceiling remains the spending control. Internal model
repair rounds are not independently identifiable and are reported as unknown,
not falsely claimed to be limited or counted.

### Reports and exits

Each series writes:

* `out/report.md`: concise quality, efficiency, trial outcomes and regression verdict
* `out/report.json`: sanitized machine-readable quality dimensions, functional
	and state/history checks, efficiency metrics, comparison deltas, completeness,
	source/compatibility identities and reserved spending limits
* `out/series-evidence.json`: local full run evidence for explicit offline comparison
* `out/control-series.json`: reusable controls, only after successful Establish
* `trials/<arm>-<pair>/out/run.json`: per-trial execution, checks and measured usage
* Per-stage snapshots, stdout/stderr and usage files: local diagnostic evidence

Quality and efficiency are separate gates, never a synthetic composite score.
Every trial needs the functional and state checks, a passing closing review,
quality >=90/100 with no unresolved critical/high finding, and complete telemetry.
A comparison requires >=10% lower median metered requests or input tokens, no
>5% regression in the other main efficiency medians, no increase in failed-tool
median, and no decline in total or dimension quality medians. Judge overhead is
metered separately and included in totals. Three pairs are screening evidence,
not statistical significance or proof of universal non-regression.

| Exit | Meaning |
|---|---|
| `0` | Successful control establishment, passing comparison, successful Run, or complete Analyze |
| `1` | Invalid configuration, incompatible reuse, missing dependency, launch/evidence error or refused promotion; no passing outcome |
| `2` | Failed/incomplete trial or series, exhausted observed limit/watchdog, regression, or incomplete Analyze; evidence retained |

Preflight errors may occur before a trial directory exists. Errors after output
creation additionally leave `out/error.json`. Raw logs, stderr, documents and full
judge responses stay local: they may contain sensitive data. Only reviewed,
sanitized comparison reports belong in the repository. A first control has no
previous-comparison deltas; failed/incomplete series never count as passing.

### Individual and offline commands

```powershell
# One complete trial, independently scored and judged.
pwsh -NoProfile -File $Harness -Mode Run -SourceRoot $Source `
	-InstallRoot $Install -TrialRoot "$Evidence\one-run" `
	-Arm candidate -Pair 1 -MaxCredits 100 -Live -IsolatedEnvironment

# Analyze an immutable snapshot of an existing CLI event stream; no model calls.
pwsh -NoProfile -File $Harness -Mode Analyze `
	-EventsPath 'C:\path\events.jsonl' -OutputPath "$Evidence\log-analysis-001"

# Recompute a comparison from six saved run files; no model calls.
$Runs = Get-ChildItem "$Evidence\comparison-002\trials\*\out\run.json" |
	Select-Object -ExpandProperty FullName
& $Harness -Mode Compare -RunPaths $Runs -OutputPath "$Evidence\comparison.json"

# Explicit promotion only, after reviewing the successful comparison.
& $Harness -Mode Promote -RunPaths $Runs -OutputPath "$Evidence\promotion.json" `
	-AcceptedPath './tests/tier2/live-benchmark/efficiency-accepted.json'
```

When saved controls were reused, obtain the six paths from the original control
trials and the three new candidate trials, rather than only the new directory.
Promotion recomputes gates, rejects quality/dimension decline and >5% efficiency
regression against the compatible last accepted report, and preserves a create-only
`.initial.json` alongside it. No successful report is preseeded before real runs.
Neither comparison nor promotion commits, pushes, or changes global CLI settings.

### Validation boundary

Offline tests cover event parsing/deduplication, missing metrics, snapshots, hook
interval union, subprocess watchdog/request limits, the twelve functional probes
against a reference CLI, state/review gating, independent judge schema/hash checks,
three-control/six-trial scheduling, safe reuse, credit reservations, retained failed
slots, compatibility/quality/efficiency gates and guarded promotion. Run them without
Python or model access:

```powershell
Invoke-Pester -Path ./tests/tier2/live-benchmark/EfficiencyBenchmark.Tests.ps1 -Output Detailed
```

The combined `Invoke-LiveBenchmarkTests.ps1` command above runs both the existing
inventory self-tests and these tests; its existing Python/pytest prerequisite remains.
Real autonomous document quality, installed CLI/session behavior, provider spending
enforcement and full live completion still require an operator-launched live run.
No offline result is a claim of measured performance improvement.

Hook sums and overlap-corrected unions are measured event intervals, not blocked
agent time or critical-path savings. Those fields remain null without actual await
instrumentation. Request-body bytes are not exact prompt tokens; input usage and
tool-schema counts are separate observations and must not be double-added.
