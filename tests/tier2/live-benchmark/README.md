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

## Squad benchmark

[benchmarks/efficiency/README.md](../../../benchmarks/efficiency/README.md) is the guide for scoring a branch. In short, one command
benchmarks the squad in your checkout and saves the score in `benchmarks/efficiency/`:

```powershell
pwsh -NoProfile -File ./tests/tier2/live-benchmark/Invoke-Benchmark.ps1 -Runs 3
```

| File | Role |
| --- | --- |
| `Invoke-Benchmark.ps1` | Installs this checkout's squad, runs the engine once per run and saves the score files |
| `invoke-benchmark.sh` | Bash starter for `Invoke-Benchmark.ps1`: checks that PowerShell 7.4+ (`pwsh`) is installed, prints Ubuntu install commands if not (it installs nothing) and passes its options through |
| `BenchmarkScore.psm1` | Turns run results into `score.json`, `badge.svg` and `report.md`, and compares two scores |
| `Compare-Benchmark.ps1` | Writes the pull request comparison; warns about lower scores or failed runs and never fails |
| `Invoke-EfficiencyExercise.ps1`, `EfficiencyBenchmark.psm1` | Engine that executes and checks one run |
| `efficiency-scenario.json` | Frozen scenario, rubric and limits |

The runner uses **observational collection** (`-ObservationOnly`). Readiness,
functional, review and quality failures are measured, not prerequisites for scoring.
Feasible later stages and remaining runs still happen; missing grades remain
unavailable, never zero or invented success. Reports retain individual checks,
independent scores, timing, requests, credits and reliability counts.

Observational workflows have no request-count cap, allow up to 1,000 native autopilot
continuations, and use a 180-minute hung-run watchdog. They reserve 30 credits for
the independently metered judge and the remainder for the shared workflow: 970/30
at a 1,000-credit trial ceiling. At least 60 total credits are required because both
native sessions need a 30-credit minimum. Credit exhaustion, invalid metering,
credential/setup failures, actual safety boundaries and evidence-identity changes
still stop affected work. Native context-window limits remain unchanged.
The independently tool-denied judge retains its ten-request allowance.

This is a separate scenario beside the existing inventory arms, not a replacement.
One `Run` executes cold Squad Coordinator initialization, BRD and PRD authoring,
the complete RPI task-CLI build, independent functional/state/history checks, and
independent document judging. Routine decisions come from the frozen
[efficiency-scenario.json](efficiency-scenario.json); `ask_user` is disabled.

The direct exercise CLI remains **strict by default** unless `-ObservationOnly`
is supplied. The strict readiness, recovery, quality and promotion rules below
are unchanged; observational collection records their failures separately.

In strict mode, each stage must pass both process/telemetry checks and stage-readiness checks
before the next stage launches. Initialization requires nonempty shared state,
Scribe dispatch/history evidence and the existing state verifier. Requirements
also require the published BRD/PRD and dispatch-backed history pointing to nonempty
artifacts for both builders and both quality reviewers. Artifact presence does
not replace workflow approval or final independent quality judging. Build retains
the closing-review and role-evidence checks; functional acceptance and judging
remain mandatory. A zero-exit blocked stage is not treated as successful merely
because the CLI returned normally. Eligible context-budget failures may use the
bounded same-stage recovery below; other failures stop dependent work.

### Bounded context recovery

A stage with a structured prompt-budget error can receive one native context
compaction and one continuation in the same session. The CLI must advertise ACP
session loading and the `compact` command. Recovery requires normal process exit,
complete metered evidence, no questions and a passing state verifier. Unresolved
permission, explicit policy/auth/credit, user-abort, integrity and ordinary
missing-evidence failures do not qualify.

A known Scribe reference discovery denial caused by unavailable interactive
approval may be resolved only by later same-actor actual workspace content for
that reference. The exact known reference glob requires all four core files.
Relative views require native absolute-path metadata; single-file content grep
requires nonzero matches and an already established actor workspace root. Size
notices, prior reads, other actors, unknown targets and path escapes are not proof.
Shell/write denials remain terminal. This neither approves the denied path nor
changes native permissions. Child prompts carry explicit workspace and skill
roots outside schema payloads. Portable results expose only the aggregate
`resolvedDiscoveryDenials`, leaving original failed-tool counts and logs intact.

The compaction controller uses ACP `initialize`, `session/load` and the advertised
`/compact` command. Replayed history or a model claiming it compacted is not proof:
a fresh canonical `session.compaction_complete` and fresh usage accounting must
exist before continuation. Unsupported, unmetered, failed or no-op compaction
stops. The continuation repairs the interrupted Scribe handoff first, without
rerunning completed roles or duplicating history, then finishes pending stage work.
A failed continuation stops; there is no second cycle or replacement trial.

In strict mode, the shared workflow receives **75% of the complete run's credit ceiling from its
first CLI invocation**; the independent judge keeps the other 25%. Initialization,
requirements, build, compaction and continuation all use that same workflow cap.
There are no smaller stage caps to retain on session resume. For example,
`-MaxCredits 1000` gives the workflow 750 credits from the outset and the judge 250.
Changing the credit policy requires a fresh run; it does not repair an already
saved session with a lower native limit.

The harness also monitors cumulative native currency usage across the shared
session and its descendants, independently of CLI invocation counters. It counts
unique usage accounting IDs and native compaction attempts, including earlier
stages, and stops active work or prevents the next launch at the workflow ceiling.
Missing or invalid credit evidence stops with `incomplete-credit-metering`;
exhaustion stops with `credit-limit`. Final records are checked even on fast exits.
Actual AI credits are recorded in `*-metrics.json` under `credits.used` and in
attempt process results separately from the configured ceiling. The judge is
metered against its own allowance, never borrowed by workflow recovery.

These are soft limits, not a billing guarantee: asynchronously reported usage
and in-flight requests can overshoot before a stop takes effect. Recovery does
not reset the scenario's shared 1,000-request/45-minute strict-run limits. The
model's context-window limit is separate and is not raised by this credit policy.

Original evidence files remain unchanged. Compaction and continuation write
separate `*-compaction-*` and `*-continuation-*` files. Trial and series JSON retain
`stages[].attempts` and `stages[].recovery`; Markdown reports summarize recovery
call counts and aggregate stage time. Cumulative token/request totals include
recovery and preserve accounting-id deduplication. The recovery policy is part of
compatibility, so older controls cannot silently stand in for this workload.
Offline protocol fakes verify recovery behavior; a real paid recovery is not
implied by those tests. Series-level retries and automatic promotion remain off.

`Establish` runs three controls. `Series` runs three baseline/candidate pairs in
AB, BA, AB order and automatically scores, aggregates and compares. Both stop
without questions and leave a terminal summary plus reports. A failed trial is
not retried: it and the remaining not-run slots are retained as an incomplete
series. A successful comparison never promotes an accepted report automatically.

The sections from here document the engine's direct commands (`Run`, `Establish`,
`Series`, `Analyze`, `Compare` and `Promote`). They are not needed to score a
branch: `Invoke-Benchmark.ps1` prepares the installation and runs the engine for
you, and does not use the paired `Establish`/`Series` modes.

### Live prerequisites

* PowerShell 7.4+, Git, and an authenticated Copilot CLI supporting `--add-dir`, `--session-id`,
	`--max-ai-credits`, `--max-autopilot-continues`, `--no-ask-user`,
	and `--usage-output-file`. Retired `--no-remote` and `--no-remote-export`
	options are neither required nor passed. MCP disabling, tool deny rules,
	secret masking and workspace/budget controls remain in place.
	ACP session loading and the advertised `compact` command are required only for
	eligible context recovery; hosts without them stop with `unsupported-host`.
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
	-MaxCredits 120 -MaxSeriesCredits 360 -Live -IsolatedEnvironment
$LASTEXITCODE
```

The control is frozen in `control-001/out/control-series.json`. Establishment
creates new evidence only; it does not overwrite an accepted optimization report.

### Run a complete comparison

After making a candidate change, reuse the three saved controls with this one
command. The fixture, parser, grader, model/role policy, CLI, installed dependency
identity, selected-source native converter, executing state verifier and per-run limits
must still match. Pair IDs and control source identity
must be consistent; otherwise reuse is refused before any trial is launched.

```powershell
pwsh -NoProfile -File $Harness -Mode Series `
	-CandidateSourceRoot $Source -InstallRoot $Install `
	-BaselineEvidencePath "$Evidence\control-001\out\control-series.json" `
	-TrialRoot "$Evidence\comparison-001" `
	-MaxCredits 120 -MaxSeriesCredits 360 -Live -IsolatedEnvironment
$LASTEXITCODE
```

To rerun both arms instead, use two existing source checkouts and reserve six
trial ceilings. This performs all six trials and comparison in one invocation.

```powershell
pwsh -NoProfile -File $Harness -Mode Series `
	-BaselineSourceRoot 'C:\bench\control-source' `
	-CandidateSourceRoot $Source -InstallRoot $Install `
	-TrialRoot "$Evidence\comparison-002" `
	-MaxCredits 120 -MaxSeriesCredits 720 -Live -IsolatedEnvironment
$LASTEXITCODE
```

The complete scheduled reservation must fit `MaxSeriesCredits` before any model
call. These commands use **strict execution**: all three coordinator invocations
share one workflow allowance of 75% of `MaxCredits`; the independent judge
receives the remaining 25%. Both allocations must meet the native 30-credit
minimum before any launch, so strict execution requires at least **120 credits
per trial** (360 for three reservations; 720 for six). The workflow shares a
990-request allowance and a 45-minute watchdog across its stages and any
same-session recovery. Each stage has at most two host continuations. The judge
has a separate ten-request bound and at most five minutes **within the remaining
45-minute budget**. More than 1000 combined metered workflow/judge requests fails
strict eligibility. An unexpected `ask_user` invocation stops execution.
No outer stage/trial retries are performed.

With `-ObservationOnly` (used by `Invoke-Benchmark.ps1`), the judge reserves a fixed 30
credits and the workflow receives `MaxCredits - 30`; the minimum is **60 credits
per trial**. The workflow and judge share a 180-minute watchdog, with the judge
still limited to five minutes within the remaining time. Observational collection
uses up to 1000 host continuations, disables the workflow observed request-count
ceiling and benchmark recovery, and retains failed checks instead of stopping for quality
gates. It does not disable spending, timeout, isolation or unexpected-question guards.
The judge retains its ten-request bound in both modes.
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

For an incomplete Establish/Series run, inspect the first failed slot, not the
not-run trials. New reports include `Failure Diagnostics`, safe failure categories,
child exit/stop status where available, and paths to existing local evidence:

```bash
# Set this to the Establish/Series directory.
series=/path/to/control
cat "$series/out/baseline-1-launch.jsonl.stderr"
cat "$series/out/baseline-1-launch.jsonl.exception.txt"
# When the child reached evidence creation:
cat "$series/trials/baseline-1/out/error.json"
cat "$series/trials/baseline-1/out/run.json"
```

Some files may not exist after an early preflight failure; the new report lists
only existing paths. Raw stderr/exception files stay local and may contain
sensitive content: review/redact before sharing. Portable reports contain paths,
categories and status, not arbitrary exception messages or raw CLI output.

If `run.json` contains only a failed `init` stage with no metrics, inspect
`trials/baseline-1/out/init-stdout.jsonl.stderr` first. A CLI argument/startup error
occurs before independent functional, state/history or document judging checks;
their missing results do not identify the startup cause. New reports list the
failed stage's exit/stop status and existing stage stderr paths directly.

For stages that exited zero but failed readiness, inspect
`stages[].readiness.checks` in the trial's `out/run.json`. Series diagnostics expose
the failed check names as `failedStages[].failedChecks`, including missing reviewer
history or artifacts. The judge is not launched when a preceding gate fails.

CLI prompts are passed as one argv element, not as a shell-joined command. Secret
variable names use one canonical comma-separated `--secret-env-vars=...` option.
The CLI forbids combining one-shot `--trust-folder` with explicit `--session-id`,
so repository hooks are opted in through the child-only
`GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=true` environment setting instead. This
does not persist trust, enable all path/URL permissions, or change global settings.
The offline suite verifies the complete init argv using a non-model fake CLI.

The launcher grants only the copied trial workspace through `--add-dir`; it does
not enable unrestricted path or URL access or override managed/sandbox policy.
The prompt resolves skills and customization within that root, requests ranged
reads for large references and one complete Scribe handoff per completed dispatch.
These measures preserve shared sessions, model selection and existing limits;
they do not enlarge a model's context window or guarantee a successful live run.

On Linux, deployed agents live under the hidden `.github/agents` directory. The
launcher checks that directory explicitly; a recursive install-root scan without
hidden-directory traversal could incorrectly report missing BRD/PRD agents.
The offline suite now exercises the actual Establish child launch with a fake
CLI on Ubuntu, including this early-failure path. No paid retry is necessary to
verify this fix. Keep failed evidence and choose a new bounded run only after
updating the affected files and inspecting any remaining diagnostic.

```powershell
# One complete trial, independently scored and judged.
pwsh -NoProfile -File $Harness -Mode Run -SourceRoot $Source `
	-InstallRoot $Install -TrialRoot "$Evidence\one-run" `
	-Arm candidate -Pair 1 -MaxCredits 120 -Live -IsolatedEnvironment

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

The score, comparer and installer self-tests have a separate entry point that
needs only PowerShell 7.4+ and pinned Pester 5.7.1, no Python:

```powershell
pwsh -NoProfile -File ./tests/tier2/live-benchmark/Invoke-BenchmarkEvidenceTests.ps1
```

`Invoke-LiveBenchmarkTests.ps1` (above) runs the inventory and efficiency-engine
suites and keeps its Python/pytest prerequisite.
Real autonomous document quality, installed CLI/session behavior, provider spending
enforcement and full live completion still require an operator-launched live run.
No offline result is a claim of measured performance improvement.

Hook sums and overlap-corrected unions are measured event intervals, not blocked
agent time or critical-path savings. Those fields remain null without actual await
instrumentation. Request-body bytes are not exact prompt tokens; input usage and
tool-schema counts are separate observations and must not be double-added.

## Reading the score

See [benchmarks/efficiency/README.md](../../../benchmarks/efficiency/README.md) for
what the score measures, what a run costs and how the pull request comparison behaves.

The document score grades BRD/PRD content, not software quality. Benchmark timing
combines workflow-stage wall clocks (including some harness checks) and the
independent judge; pure agent latency is not measured. The badge's average time
is the arithmetic mean across scored runs; quality is the median. Invalid-input
and corrupt-storage probes must terminate naturally with a nonzero exit and
preserve storage: watchdog termination is not correct rejection.
