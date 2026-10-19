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

### Guided setup

Launch the interactive wizard in PowerShell 7.4 or newer:

```powershell
pwsh -NoProfile -File ./tests/tier2/live-benchmark/Start-EfficiencyWizard.ps1
```

From Ubuntu, start the same wizard through bash:

```bash
bash tests/tier2/live-benchmark/start-efficiency-wizard.sh

# Optional paths are forwarded unchanged, including spaces.
bash tests/tier2/live-benchmark/start-efficiency-wizard.sh \
    -WorkRoot "$HOME/bench/squad efficiency"
```

The bash starter requires stable PowerShell Core 7.4 or newer. If `pwsh` is
missing or too old, it prints official Ubuntu Microsoft-package-repository
installation commands and stops; it never runs sudo, apt or downloads. Review
the printed commands and supported Ubuntu/architecture guidance, install or
upgrade PowerShell yourself, then rerun. Missing `pwsh` exits `127`; an old,
preview or failing runtime exits `2`; once started, the wizard's exit status
is preserved. No chmod is required when invoking it with `bash`.

In WSL, a Windows checkout can be used directly through its mounted path, for
example `/mnt/c/source/hve-squad`; no push, clone or copy is required. Use Linux
paths for wizard arguments. Missing non-Windows prerequisites receive publisher
installation guidance instead of WinGet commands; the wizard does not elevate
or automatically execute Linux install scripts. The launcher was validated with
Ubuntu 24.04 WSL, PowerShell 7.6.7 and isolated fake-runtime tests. Actual package
installation and model-backed execution are not part of that validation.

Optional `-WorkRoot 'C:\bench\efficiency'` and `-BaselineEvidencePath '<control-series.json>'`
set initial paths. The default work root is `%LOCALAPPDATA%\hve-squad\efficiency`
(the corresponding local application-data directory on Linux), outside the checkout.
Every launch uses a fresh `run-<timestamp>-<id>` and preserves old reports and controls.

| Choice | Work after setup |
| --- | --- |
| Establish | Full offline self-tests, then three complete controls; no improvement claim |
| Series | Full offline self-tests, then three candidates using compatible saved controls, or six fresh paired trials |
| Complete | Full offline self-tests, three fresh controls, then three candidates against them and automatic comparison |
| Offline | Full offline self-tests only; no GitHub/Copilot login or model requests |

Establish is recommended without saved controls; Series is recommended when a
control file is supplied or discovered. Complete is not retry-until-success.
Selecting the same source for both arms tests repeatability, not patch improvement.
Select separate baseline/candidate checkouts to compare an actual patch.

Defaults are `claude-sonnet-5.5`, 100 AI credits per complete run, 300 total for
three new runs or 600 for six. These are ceilings, not cost predictions. Paths,
model and credit ceilings can be changed. The wizard verifies the whole reservation,
requires explicit disposable-isolation and spending confirmation, preserves the
existing watchdog and continuation bounds, and never promotes an accepted baseline.
Isolation is not created by the wizard or by a launcher flag.

Missing Git, uv, GitHub CLI, Copilot CLI and APM can be installed with consent using
exact official WinGet packages in user scope. Pester 5.7.1 can be installed in
CurrentUser scope. Existing tools are not silently upgraded; incompatible versions
stop with guidance. No elevation, downloaded-script execution or TLS bypass is
attempted. If WinGet is missing, install Microsoft App Installer through the Store.
If PowerShell is too old to run the script, bootstrap it first:

```powershell
winget install --id Microsoft.PowerShell --exact --source winget
```

The full offline stage uses isolated Python 3.12 and pinned `pytest==8.3.5` through
uv, with the system certificate store and installed Pester. Downloads may be needed;
no global Python packages are installed. Trusted feed/proxy/TLS failures stop
before any paid trial; repair trust rather than disabling certificate checks.

For live modes, the wizard checks `gh auth status` and offers native
`gh auth login --hostname github.com --web`, followed by a separate Copilot
authorization choice. OAuth obtains/stores credentials through the CLIs; browser,
organization SSO and subscription approval cannot be bypassed. The wizard does
not retrieve/print tokens, request guessed scopes, or fabricate a PAT. It warns
about credential environment-variable precedence without reading values.
Existing authorization can be reused but is not proof of Copilot entitlement;
the first bounded live invocation remains the real validation.

An organization-required PAT must be user-owned, fine-grained, and have the
**Copilot Requests** account permission. Enter it directly into native
`copilot login --with-token`, never a wizard field. Classic PATs are unsupported.
Custom/BYOK provider environments are refused because GitHub credit ceilings
cannot bound third-party spending.

Package preparation reuses a clean full install or offers to archive only the
managed `install/` directory before rebuilding it. Consent is required; contents
are moved, not deleted. Source overlaps, filesystem roots and reparse-point
ancestors are refused. No git cleanup/reset or old evidence deletion occurs.
Choose a new work root when an existing directory cannot safely be reused.

After setup and final launch consent, no routine questions are asked. Any failed
stage stops dependent work: no benchmark after failed offline checks, no candidate
after failed controls, and no outer retries. Terminal guidance identifies the
failure and repair; `run-.../wizard-result.json` records status and not-run count.
Benchmark reports are under `control/out/` and `comparison/out/`. Exit codes:
`0` all selected stages passed; `1` setup/launch error; `2` failed checks/benchmark;
`3` cancelled or declined consent. Type `q` at a wizard input to cancel; blank
confirmations mean no. Failed evidence remains available for repair.
Confirmation prompts accept `yes`/`y` and `no`/`n`, ignoring case and surrounding
whitespace. Other text displays guidance and repeats the question without
authorizing an action or terminating the wizard. Blank remains no; `q` cancels.

Wizard tests mock installation, login, preparation and model-backed commands.
Actual native setup and live provider enforcement remain operator-run validation;
offline tests do not claim paid-run success. Official references:
[GitHub CLI auth](https://cli.github.com/manual/gh_auth_login),
[Copilot auth](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli),
[APM install](https://microsoft.github.io/apm/getting-started/installation/).

This is a separate scenario beside the existing inventory arms, not a replacement.
One `Run` executes cold Squad Coordinator initialization, BRD and PRD authoring,
the complete RPI task-CLI build, independent functional/state/history checks, and
independent document judging. Routine decisions come from the frozen
[efficiency-scenario.json](efficiency-scenario.json); `ask_user` is disabled.

Each stage must pass both process/telemetry checks and stage-readiness checks
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
complete metered evidence, no questions and a passing state verifier. Permission,
policy, user-abort, integrity and ordinary missing-evidence failures do not qualify.

The compaction controller uses ACP `initialize`, `session/load` and the advertised
`/compact` command. Replayed history or a model claiming it compacted is not proof:
a fresh canonical `session.compaction_complete` and fresh usage accounting must
exist before continuation. Unsupported, unmetered, failed or no-op compaction
stops. The continuation repairs the interrupted Scribe handoff first, without
rerunning completed roles or duplicating history, then finishes pending stage work.
A failed continuation stops; there is no second cycle or replacement trial.

Each stage keeps its original quarter of the run's credit reservation: half goes
to initial work, a quarter to compaction and a quarter to continuation. The judge
keeps its quarter-run reservation. The shared session's CLI credit ceiling grows
only by admitted reservations; it is not reset for each subprocess. These are
bounded reservations and provider soft limits, not a billing guarantee. Recovery
does not reset the 96-request/900-second stage or 2700-second trial limits.

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

### Live prerequisites

* PowerShell 7.4+, Git, and an authenticated Copilot CLI supporting `--add-dir`, `--session-id`,
	`--max-ai-credits`, `--max-autopilot-continues`, `--no-ask-user`, `--no-remote`,
	`--no-remote-export`, and `--usage-output-file`
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

For an incomplete Establish/Series run, inspect the first failed slot, not the
not-run trials. New reports include `Failure Diagnostics`, safe failure categories,
child exit/stop status where available, and paths to existing local evidence:

```bash
# Set this to the Establish/Series directory, e.g. <wizard-run>/control.
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

Wizard unit tests intentionally exercise failed/cancelled setup and suppress
their simulated console messages. Only the Pester aggregate failure count decides
whether the offline test stage passed. Actual live stage diagnostics remain visible.

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
