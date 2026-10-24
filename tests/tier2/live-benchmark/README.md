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
    -ParallelTrials \
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
Formal launches use a fresh `run-<timestamp>-<id>` and preserve old reports and controls.
Local smoke/comparison launches use separate `local-test-<id>` directories.

The last completed valid questionnaire is remembered in
`.efficiency-wizard-defaults.json` at the wizard checkout root. This file and its
atomic-write temporaries are gitignored. Both launchers reuse the saved mode,
paths, model, credit ceilings and scheduling as question defaults; explicit
work/control paths and `-ParallelTrials` take precedence. A changed plan raises
the total default if needed to cover every reservation. Offline mode preserves
your previous live answers. Cancelled or invalid questionnaires do not replace
them, and later prerequisite/test failures do not discard completed answers.
Delete this file to reset defaults; malformed settings stop with reset guidance.
The Copilot login method and later setup answers are saved immediately, even if
a later login or preparation step fails. The next run defaults to the last login
method and clean-install reuse answer; install validity is still checked.
Credentials and tokens are never stored. Remembered login methods do not
authorize authentication: browser/PAT login still requires fresh confirmation.
Installation, archival and launch answers are reminders only; those confirmations
still default to no. The spending authorization answer is also saved against its
configuration as a reminder only: every live run still requires fresh explicit
isolation/spending confirmation; blank means no.

During execution the wizard prints a plain-text progress snapshot every 30 seconds,
plus snapshots at child start and finish. Each scheduled baseline/candidate trial
shows its active phase, phase duration, completed milestone count, and available
CLI-output byte count/last activity, including all three parallel trials.
The seven unequal milestones are preflight, init, requirements, build, functional
acceptance, judge and report: they are **not** a model-completion percentage or
time estimate. A long build can legitimately remain at 3/7; changing duration and
output activity provide context without inventing an ETA. Pending serial trials
say awaiting preflight. Finished/failed snapshots print once unless their result
changes, with known independent-check and observation-recording status.
Offline progress counts the three self-test files; wizard boundaries count
scheduled steps. Neither count implies quality approval.

Child stdout/stderr is retained in `wizard-stage-<id>.log` and its `.stderr`
sibling under the fresh wizard run directory and displayed when that stage ends.
Trial phase snapshots are retained as `trials/<arm>-<pair>/out/progress.json`
inside the control/comparison directory. Progress reporting does not alter
spending limits, trial scheduling, watchdogs or baseline promotion.

`wizard-result.json` includes each benchmark stage's independent-check outcome,
record count, report and portable-record paths, saved-control path when available,
and offline publication command. Exit zero means the selected collection
completed, not that the measured process passed: quality/readiness failures produce
`completed-with-findings`, not `passed`. Missing/malformed expected result evidence
is an execution error. Records remain local and **uncommitted to Git** until the
printed offline export command is used in a compatible writable delivery checkout.
Reporting/publication repairs do not require another paid run.

Live modes accept current CLI versions advertising `--sync-session off`, or older
versions advertising both `--no-remote` and `--no-remote-export`. The wizard no
longer demands flags removed in CLI 1.0.103. The same policy protects workflow,
judge and ACP launches; an unrecognized sync policy fails closed. Modern sync-off
disables account-history upload, not incoming control: the harness creates local
sessions and never opts into remote connection/hosting modes. This is not an OS sandbox.

After the credit ceilings, choose **Serial** (initial default) or **Three observations in
parallel**, or pass `-ParallelTrials` through either launcher to select it directly.
The bash starter forwards this switch unchanged with quoted path arguments.
Parallel mode starts three independent native trials, each with its
own workspace, session, log, credit allowance and watchdog. All three allowances
must fit before launch; failures do not retry or discard already-started siblings.
Concurrent runs compete for host resources and service capacity. Scheduling mode
is part of compatibility: parallel candidates require parallel controls, and older
controls must be recollected after this protocol change. Complete still finishes
the control phase before starting candidates; offline checks remain first.

| Choice | Work and AI cost | Recommended use |
| --- | --- | --- |
| 1. Establish | Full offline checks + 3 paid controls; records failures, no improvement claim | First baseline or changed benchmark protocol |
| 2. Series | Full offline checks + 3 paid candidates vs compatible controls, or 6 fresh paired trials | Measure a patch with formal benchmark evidence |
| 3. Complete | Full offline checks + 3 fresh paid controls + 3 paid candidates | Refresh both arms; highest total cost |
| 4. Offline | All self-tests; no AI/login, Python/pytest setup may download packages | Thorough harness validation before formal collection |
| 5. Offline smoke | Exactly 1 simulated candidate; no AI/login/downloads/Python; installed Git/Pester required | Fast harness editing feedback, including uncommitted changes |
| 6. Single candidate vs saved scores | Smoke first, then 1 paid candidate workflow including judge; no benchmark export | Debug the current local changes against historical scores |
| 7. Repair setup | Reviews measured changes, offers a source-only local commit, then keeps a valid install or offers archive/rebuild; no push, AI, login or benchmark runs | Recover setup before choosing 1 or 2; rebuilding packages may download dependencies |

### Repair after a local diagnostic

`invalid-record:measured-source-mismatch` means the measured `squad-src/` bytes
do not match the selected checkout's Git `HEAD`. Option 6 allows uncommitted
changes; it does **not** damage the install or make those changes formal evidence.

Choose **7**, review the exact measured paths, and explicitly approve a
**source-only local commit** if they contain the changes you intend to measure.
Blank means no: declining leaves source, index and HEAD unchanged. The commit
includes the complete current contents of those paths, including deletions and
untracked/ignored additions, not just staged hunks. Unrelated staged and unstaged
work is preserved. Normal Git identity, signing and hooks apply; nothing is pushed.
Then choose **1** or **2**. Already committed source needs no new commit.

Formal modes still check measured source and the actual executing protocol
**before prerequisite setup or login**. Repair verifies the approved bytes and
commit scope before declaring success. Changed inputs, failed hooks/signing, or
byte-changing Git attributes/filters/EOL conversion stop repair with diagnostics;
it does not bypass Git policy, reset files or automatically retry a commit.
Any commit or hook effects already produced are retained for inspection.
Repair never rewrites old evidence or turns diagnostic scores into controls.

Option 7 asks only for the evidence root and source checkout. A valid install is
kept by default. Choose rebuild only when needed: the wizard asks for fresh consent
to archive the managed `install/` directory and prepare its replacement. Nothing
is deleted; previous runs, controls and installation contents remain available.
Rebuilding may download packages and change dependency hashes. A successful repair
checks source/protocol and package layout/manifest, **not** live authorization,
saved-control compatibility, offline-suite success or benchmark quality. Options 1
and 2 still perform their full checks and require fresh spending consent.

| Failure | Recovery |
| --- | --- |
| Uncommitted measured source | Choose 7, review the named changes and approve the source-only local commit, then 1 or 2; alternatively commit them yourself |
| Git identity/signing/hooks fail, inputs change, or filters alter bytes | Inspect Git output/status and the named attributes/filter/EOL issue; repair the local Git configuration or source, then rerun 7; no automatic rollback or policy bypass |
| Missing, stale or damaged prepared install | Choose 7 and consent to archive/rebuild; old evidence stays untouched |
| Saved controls have a different runtime/model/dependency/protocol | Restore the exact environment or explicitly collect fresh controls; never edit saved evidence |
| Parent/candidate commits have different measured protocols | Stop: these revisions cannot be formally compared by this harness; fresh trials or rebuilding dependencies do not fix this |

### Compare a committed PR with its parent

Commit the intended PR changes first. Create two detached worktrees so editing the
development checkout cannot change the measured arms. From the development
checkout, with the intended target branch available locally:

```bash
target=origin/main  # Use the actual PR target, not an arbitrary saved baseline.
candidate=$(git rev-parse HEAD)
parent=$(git merge-base "$target" "$candidate")
sources="$HOME/bench/hve-squad-sources"
git worktree add --detach "$sources/parent" "$parent"
git worktree add --detach "$sources/pr" "$candidate"
bash "$sources/pr/tests/tier2/live-benchmark/start-efficiency-wizard.sh" \
  -WorkRoot "$HOME/bench/hve-squad-evidence"
```

Use fresh worktree paths if these already exist. This runs the **candidate's**
wizard/protocol. Choose **2**, enter **none** for saved controls, select
`$HOME/bench/hve-squad-sources/parent` as baseline and
`$HOME/bench/hve-squad-sources/pr` as candidate. This collects six fresh paired
trials, after checks and your explicit isolation/spending consent. The commands
above start setup only; no paid collection occurs without that consent.

Both commits must support the same executing benchmark protocol; the early check
stops otherwise. Do not copy newer protocol files into the parent worktree to
force admission. If compatible three-control evidence already measures this exact
parent, select that `control-series.json` instead of **none** to collect only three
candidates. Fresh pairs replace stale saved controls only when both measured
revisions are themselves protocol-compatible. Same-checkout arms measure
repeatability, not PR improvement.

### Local diagnostics

Options **5 and 6 are local diagnostics, never benchmark evidence**. The offline
smoke normally takes seconds, uses fake AI responses and intentionally checks
failure handling; its success does not mean an application passed quality review.
Run it directly without the questionnaire:

```powershell
pwsh -NoProfile -File ./tests/tier2/live-benchmark/Invoke-LiveBenchmarkTests.ps1 -SingleCandidate -Output Normal
```

Option 6 still performs a complete real workflow and may take minutes/use substantial
credits: one candidate is not one model request. It asks for a saved
`control-series.json` containing three distinct, valid scored baseline observations,
reads it without modification, and displays dimension medians plus the median of
per-run totals. Invalid/missing historical scores stop before authentication or
spending. Missing candidate scores display as unavailable, never zero. Protocol,
model and rubric differences are disclosed; deltas are descriptive only, not
compatible comparisons, regression verdicts or evidence of improvement.

Both local options allow uncommitted changes; formal modes still require measured
files to match Git. Local live execution pins working bytes and stops on later drift.
No `run.json`, controls, portable records or accepted baseline is produced by the
local candidate. Its labelled `diagnostic.json` and raw failure logs stay outside
the checkout; even renaming the diagnostic to `run.json` cannot pass export validation.
One-candidate modes are serial and reject `-ParallelTrials`; remembered formal
scheduling is preserved. Use formal Establish/Series/Complete for publishable results.
Wizard scratch paths and local diagnostics require physical checkout/output paths.
Source and output links, including ancestor links and junctions, are rejected before
creating test output; use the target directory's physical path instead.

### Formal collection and setup

Initially, Establish is recommended without saved controls; Series is recommended
when a control file is supplied or discovered. Later runs default to the remembered
mode; an explicitly supplied control path recommends Series. Complete is not retry-until-success.
Selecting the same source for both arms tests repeatability, not patch improvement.
Select separate baseline/candidate checkouts to compare an actual patch.

Initial wizard observational defaults are `claude-sonnet-5.5`, 100 AI credits per complete run, 300 total for
three new runs or 600 for six. These are ceilings, not cost predictions. Paths,
model and credit ceilings can be changed. The wizard verifies the whole reservation,
requires explicit disposable-isolation and spending confirmation, preserves the
financial and isolation protections, and never automatically promotes a baseline.
Isolation is not created by the wizard or by a launcher flag.

Formal wizard live modes use **observational collection** (`-ObservationOnly`). Readiness,
functional, review and quality failures are measured, not prerequisites for collecting
the baseline. Feasible later stages and remaining samples still run; missing grades
remain unavailable, never zero or invented success. `baseline-recorded` means three
observations were saved, not that the workflow passed. Reports retain individual
checks, independent scores, timing, tokens, requests, credits and reliability counts.
Comparisons assess relative quality and reliability as well as efficiency; an
imperfect baseline need not first score 90. Unavailable evidence makes a comparison
not evaluable, and observations are never automatically promoted.

After each formal wizard collection step, offline finalization exports available
observations into that step's external `portable/` directory and prints a
PowerShell command to publish them in a matching writable delivery checkout.
This also runs after collection failure, preserves the collection exit, and
never retries paid work. Export needs PowerShell 7.5+; failures remain explicit.
Review and commit generated evidence yourself; no files are written into the
measured source while collecting. Direct `-Mode Run` calls still only collect
private evidence. See [complete and incomplete export commands](../../../benchmarks/efficiency/README.md#record-and-regenerate).
Unavailable grades/accounting are retained in a separate campaign archive,
not accepted as a complete three-trial series.

Observational workflows have no request-count cap, allow up to 1,000 native autopilot
continuations, and use a 180-minute hung-run watchdog. They reserve 30 credits for
the independently metered judge and the remainder for the shared workflow: 970/30
at a 1,000-credit trial ceiling. At least 60 total credits are required because both
native sessions need a 30-credit minimum. Credit exhaustion, invalid metering,
credential/setup failures, actual safety boundaries and evidence-identity changes
still stop affected work. Native context-window limits remain unchanged.
The independently tool-denied judge retains its ten-request allowance.

Missing Git, Python 3.12, GitHub CLI, Copilot CLI and APM can be installed with consent using
exact official WinGet packages in user scope. Pester 5.7.1 can be installed in
CurrentUser scope. Existing tools are not silently upgraded; incompatible versions
stop with guidance. No elevation, downloaded-script execution or TLS bypass is
attempted. If WinGet is missing, install Microsoft App Installer through the Store.
If PowerShell is too old to run the script, bootstrap it first:

```powershell
winget install --id Microsoft.PowerShell --exact --source winget
```

The full offline stage uses a run-local Python 3.12 virtual environment and pinned
`pytest==8.3.5` installed through pip, with installed Pester. Downloads may be needed;
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

After setup and final launch consent, no routine questions are asked. Setup,
offline-test, accounting or collection failures stop dependent work; observed
workflow/quality failures do not. There are no outer retries. Terminal guidance identifies the
failure and repair; `run-.../wizard-result.json` records status and not-run count.
Benchmark reports are under `control/out/` and `comparison/out/`. Exit codes:
`0` collection/comparison finished (not a workflow-quality pass); `1` setup/launch error;
`2` failed setup/collection or comparative regression/unavailable comparison;
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

The direct exercise CLI remains **strict by default** unless `-ObservationOnly`
is supplied. The strict readiness, recovery, quality and promotion rules below
are unchanged; observational collection records their failures separately.

Live preflight uses the offline export validator (PowerShell 7.5+) before any
model launch. The executing protocol files and selected `squad-src/` must match
their recorded Git revision; unrelated local edits are allowed. Commit intended
measured changes before collection, including local grader fixes. Both source
arms need revisions containing the same executing benchmark protocol. Saved
controls must bind to their original commits in the baseline repository, or the
candidate repository when no baseline checkout is supplied; missing objects stop
without fetching. Serial and parallel children receive the original admission
pin and recheck it before each paid stage/recovery/judge call. Drift stops further
work and retains known stages, attempts and accounting in `out/error.json` as
`provenance-failure`, not a passing/exportable observation. This is point-in-time
validation, not a filesystem freeze or cancellation of already-running calls.

The fixture supplies synthetic KPI baseline, target, measurement window and
decision ownership; these are planning inputs, not achieved production results.
Expected unapproved draft labels alone are not content defects. Blocked canonical
gates, false approval and unresolved critical/high findings still count. Draft
copies authorize no governed handoff; observation mode's contract prototype is a
separately authorized synthetic task. The v2 rubric/scenario is incompatible with
older controls: preserve them as historical evidence, never relabel their revision.
Runtime reviewers receive the validated literal-path brief from
`Get-SquadRuntimeReviewBrief.ps1`; its checks do not certify native permission
behavior, and denied probes remain unverified failures.

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
	-MaxCredits 120 -MaxSeriesCredits 360 -Live -IsolatedEnvironment
$LASTEXITCODE
```

The control is frozen in `control-001/out/control-series.json`. Establishment
creates new evidence only; it does not overwrite an accepted optimization report.

Add `-ParallelTrials` to Establish, or to Series with saved controls, to overlap
the three trials. Use the same switch when collecting those controls. Six fresh
paired trials remain serial to preserve alternating arm order; combining that
mode with `-ParallelTrials` is rejected before launch. Catchable cancellation
stops owned native process trees before removing worker jobs and preserves local
evidence; forcibly killing the entire host cannot guarantee this cleanup.

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

With `-ObservationOnly` (used by the wizard), the judge reserves a fixed 30
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

Portable record/study and installer self-tests have a separate PowerShell 7.5+
entry point using pinned Pester 5.7.1:

```powershell
pwsh -NoProfile -File ./tests/tier2/live-benchmark/Invoke-BenchmarkEvidenceTests.ps1
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
# Branch-relative repository results

See [repository benchmark evidence](../../../benchmarks/efficiency/README.md)
for sanitized immutable records, explicit parent selection, offline comparison
commands, numeric policy, Actions summaries and generated README SVG badges.
This sidecar does not change the frozen producer or strict promotion gates.

The document score grades BRD/PRD content, not software quality. Benchmark timing
combines workflow-stage wall clocks (including some harness checks) and the
independent judge; pure agent latency and full wizard duration are not measured.
The average-time badge uses the arithmetic mean; comparison gates still use
medians. Invalid-input and corrupt-storage probes must terminate naturally with
a nonzero exit and preserve storage: watchdog termination is not correct rejection.
Changing this oracle invalidates current-protocol comparisons with inherited
observations; historical records remain immutable descriptive evidence.

Current portable exports use `benchmark-series-v2`: `converterHash` binds the
builder actually loaded from the selected source checkout, while `verifierHash`
binds the verifier actually executed from the harness checkout. Export requires
both digests to match the measured Git revision; it cannot relabel mismatched
execution as that revision. Old `benchmark-series-v1` records remain available
for historical analysis, but are explicitly `stale-record:unbound-execution-protocol`
for current snapshot validation. The existing selected baseline therefore needs
new, separately authorized evidence; old records and pointers are not rewritten.

The Scribe verifier's pricing evaluator (v2) prices long-context blocks per block
and applies calibration once, so its script source changed and `verifierHash`
changed with it. That hash covers the verifier script only, not imported modules
such as `SquadState.psm1`; module-only drift is not fingerprinted. The earlier
83/81 series carry the old verifier hash, remain immutable, and are incompatible
for direct strict comparison until matching new-verifier evidence is collected.
There is no waiver and no automatic paid parent refresh.
