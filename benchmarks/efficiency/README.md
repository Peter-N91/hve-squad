# Squad benchmark

[![Observed document quality, acceptance and average benchmark time](badge.svg)](report.md)

This folder holds the benchmark score of the squad **in the branch you are viewing**:
`score.json` (the data), `badge.svg` (the badge above) and `report.md` (a readable
report). Open `main` to see main's score. Developers run the benchmark locally and
commit the result with their branch.

## Run the benchmark

```powershell
pwsh -NoProfile -File ./tests/tier2/live-benchmark/Invoke-Benchmark.ps1
```

One command does everything. It benchmarks the squad in your current checkout
(`squad-src/`, including uncommitted changes), then writes `score.json`, `badge.svg`
and `report.md` into this folder. Commit those files with your branch. It does not
look at any other branch.

From a bash shell (Linux, WSL), `bash tests/tier2/live-benchmark/invoke-benchmark.sh` does the
same and takes the same options (for example `-Runs 1` or `-WhatIf`). It first checks that
PowerShell 7.4 or later (`pwsh`) is installed; if not, it prints Ubuntu installation commands
and stops without installing anything.

**It spends Copilot credits.** One run takes about 20 minutes and uses about 300
credits (the recorded runs used 261 to 301 credits and took 19 to 21 minutes).
Choose how many runs with `-Runs`, from 1 to 3 (default 3):

| Command | Runs | Time | Copilot credits |
| --- | --- | --- | --- |
| `Invoke-Benchmark.ps1 -Runs 1` | 1 | about 20 min | about 300 |
| `Invoke-Benchmark.ps1 -Runs 2` | 2 | about 40 min | about 600 |
| `Invoke-Benchmark.ps1` | 3 | about 1 h | about 900 |

Runs happen one after another, after a short setup that installs the squad. Each run
stops at 1,000 credits (a soft limit, because usage is reported asynchronously) and a
hung run is stopped after 3 hours. One run is a quick check: the judge is an AI model,
so a single run varies more than the median of three. Add `-WhatIf` to see what would
run without spending anything.

### Progress output

The console timestamps installation, run results and report generation, including
the local UTC offset. Each run reports seven planned steps: workspace preparation,
squad initialization, requirements, build, acceptance/workflow checks, document
judging, and saving evidence. Every transition shows its step number and how many
steps remain **after the current step**; run headers also show later runs remaining.

While the run subprocess is active, a quiet period of 30 seconds produces a
heartbeat with elapsed run time and the last timestamped step update. Progress is
forwarded through a dedicated `run-N-progress.log` in the retained evidence folder;
model output and raw diagnostics remain in their existing logs, not streamed to
the console. Context recovery stays inside its current step, skipped work is
marked explicitly, and a finished step means execution finished, not that its
quality or workflow checks passed. Remaining steps are a plan, not an ETA.

Before you run it:

* PowerShell 7.4 or later, Git, the APM CLI (`apm`, version 0.29.0 as in
  [Getting Started](https://peter-n91.github.io/hve-squad/getting-started.html)) and the
  GitHub Copilot CLI (`copilot`, signed in) on your `PATH`, plus network access.
* A throwaway machine, container or VM. The benchmark runs an autonomous Copilot
  agent with tool filters, not an OS sandbox.
* Commit your `squad-src/` changes first, so the commit recorded in the score matches
  the code that was measured. The score files are outside `squad-src/`, so committing
  them afterwards does not change what was measured.

When it finishes, the command prints the badge text and saves:

| File | Contents |
| --- | --- |
| `score.json` | The score and every run, in a fixed format that the pull request comparison reads |
| `badge.svg` | The badge shown at the top of this page and in the root README |
| `report.md` | The score, observed agent activity, the five quality dimensions, each run and the checks that did not pass |

A run that does not finish, or has no valid judged result, is recorded as failed: it is
left out of the quality median and averages, and the functional and workflow counts are
always out of the runs you asked for. If no run produces a score, this folder is left
unchanged and the command exits with code 1.
Logs and evidence stay in a temporary folder whose path the command prints. They can
contain generated documents, so review them before sharing, and delete them when you
are done.

## Pull requests

A pull request that changes `squad-src/` or this folder gets a **Benchmark score**
comment (`.github/workflows/benchmark-score.yml`) with its `score.json` next to the
base branch's. It never runs the benchmark, spends nothing and **never fails** the
pull request.

* **Warnings** are shown for lower document quality or dimension medians, a lower
  functional or workflow pass rate, more critical or high findings per run, and runs
  that did not produce a score.
* **Notes** explain what limits the comparison. Scores with different run counts, models
  or Copilot CLI versions are still compared (pass rates and per-run averages) but are
  flagged as indicative. When the base branch has no readable score, or the pull request
  does not change the score, the comment just shows the current score. If `squad-src/`
  changed and the score was not refreshed, it suggests running the command above.
* Pull requests from forks cannot be commented on, so they get the same text in the job
  summary.

## What a run measures

The squad builds a small offline task-list CLI (`src/task.ps1`) after writing a BRD and
a PRD. Each run is checked in three separate ways, reported separately so a good result
on one cannot hide a failure in another.

### Quality: are the documents good?

A blind AI judge reads the BRD and PRD and scores five dimensions from 0 to 20 each,
for a total out of 100. 18–20 means complete, specific and consistent; 14–17 means
material omissions; 0–13 means major gaps. The score is the median over the runs.

| Dimension           | What the judge asks                                    |
|---------------------|--------------------------------------------------------|
| Business clarity    | Is the problem, sponsor and expected outcome clear?    |
| Scope fidelity      | Does it stay within the brief, without extra features? |
| Acceptance criteria | Are success conditions specific and testable?          |
| Traceability        | Can requirements be followed through to decisions?     |
| Risks and decisions | Are risks, assumptions and choices recorded?           |

Critical or high-severity findings (missing mandatory requirements, unresolved
production-safety claims) are counted separately.

### Functional: does the product work?

After each run the benchmark executes the delivered CLI and tries specific behaviours:
Unicode titles round-trip, blank or missing titles are rejected, unknown IDs fail,
marking done twice is safe, IDs are unique and increasing, empty and filtered lists
work, data persists across separate runs, and a corrupt store is left untouched. Each is
a pass/fail check and a run passes only if all of them do. The result is shown as runs
passing out of runs requested.

### Workflow: did the squad follow its process?

This ignores whether the code works. It checks that the squad completed its own process
through the init, requirements and build stages and left evidence: state, team, routing
and decision files, cost logs, proof that the expected roles (researcher, developer,
tester, lead, BRD/PRD builders) were dispatched, a recorded review outcome, and a state
verifier confirming the recorded state matches reality. A run passes only if every check
passes.

## Reading a score

### Observed activity

Generated reports compare **Earlier run** (the previous local `score.json`, read
before replacement) with **Latest run** (the new score). PR comments use the base
branch and PR scores respectively. Neither comparison launches a benchmark.
The six rows show Scribe dispatches, model requests, summed dispatch time and
credits, Coordinator model requests, and combined BRD/PRD author model requests.
They use native runtime identities rather than model names or the Scribe's
estimated ledger.

Activity is stored in each trial's `activity` and in `summary.activity` in
`score.json`, without changing `benchmark-score-v1`. Summary values are arithmetic
means over scored runs, so counts can be fractional. A metric is **unavailable**
if any scored run lacks it, if runtime attribution is incomplete, or if an older
score does not contain it. Missing data is never replaced with zero; an observed
absence of dispatches or author usage can be zero. Failed, unscored trials retain
their available activity but do not enter these averages.

Model requests count unique `(sourceSessionId, usageId)` usage records in the
final cumulative workflow log; stage snapshots are not added together. Requests
without usage records cannot be counted. Credits sum complete native credit
records for Scribe requests, excluding separate compaction charges and the judge;
incomplete Scribe credit coverage makes that cell unavailable. Dispatch time sums
completed Scribe dispatch durations and is unavailable if a completion is missing.
Overlapping dispatches can therefore exceed wall-clock time.

These are diagnostic observations, not new scoring rules or evidence of a causal
speed improvement. Older saved scores remain readable and are not backfilled.

### Score interpretation

* The badge shows the quality median, the functional and workflow pass counts and the
  **average benchmark time per run**. It is green only when every run was scored and
  passed both checks, amber otherwise and grey when no run was scored. It is not a claim
  that every check passed: `report.md` lists the ones that did not.
* The time is the mean of each run's workflow stages plus the judge. Stage clocks include
  some harness checks; setup and report generation are excluded. It is neither pure
  agent latency nor total command duration. Credits count the workflow and the judge.
* The quality score grades the BRD and PRD, not the delivered software. The judge is an
  AI model, so treat a difference of a few points as noise and prefer three runs.
* Scores measured with a different model or Copilot CLI version are not directly
  comparable. Both are recorded in `score.json`, and the runner sets
  `COPILOT_AUTO_UPDATE=false` so the CLI does not update during a run.
* The score is evidence, not a gate: failures are recorded, never hidden or turned into
  a pass.
