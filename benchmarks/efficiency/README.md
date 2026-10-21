# Repository benchmark evidence

[![Observed document quality, acceptance and average benchmark time](badge.svg)](report.md)

`current.json` selects one immutable `records/<series-id>.json` by SHA-256.
This is **recorded observational evidence, not an approved quality baseline**.
The three original pristine observations include real functional, state and
review-deliverable failures. A score must never conceal those failures.
Private logs, generated documents, judge explanations and session identifiers
are not committed. File hashes provide integrity, not authenticated execution.

## How the benchmark measures a run

The benchmark has the squad build a small offline task-list CLI (`src/task.ps1`)
and write a BRD and PRD first. The exercise is repeated three times, and each
run is checked in three separate ways. They are reported separately so a good
score on one cannot hide a failure in another.

### Quality: are the documents good?

A blind AI judge reads the BRD and PRD and scores five dimensions from 0 to 20
each, for a total out of 100. 18–20 means complete, specific and consistent;
14–17 means material omissions; 0–13 means major gaps.

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

After each run the benchmark executes the delivered CLI and tries specific
behaviours. Each is a pass/fail check, shown as passes out of 3 trials: Unicode
titles round-trip, blank or missing titles are rejected, unknown IDs fail,
marking done twice is safe, IDs are unique and increasing, empty and filtered
lists work, data persists across separate runs, and a corrupt store is left
untouched.

### Workflow: did the squad follow its process?

This ignores whether the code works. It checks that the squad completed its own
process through the init, requirements and build stages and left evidence:
state, team, routing and decision files, cost logs, proof that the expected
roles (researcher, developer, tester, lead, BRD/PRD builders) were dispatched,
a recorded review outcome, and a state verifier confirming the recorded state
matches reality.

### Regression rules

A change must not lower the quality total or any dimension median, and must not
reduce any functional or workflow pass count. The badge shows all three measures
plus **average measured benchmark time per trial**, and is not a claim that every gate
passed. `avg benchmark time` is the arithmetic mean of the three stage-plus-judge
wall times. Stage clocks include some harness checks; setup, report generation
and some independent evaluation are excluded. This is neither pure agent latency
nor whole-wizard duration. The performance
table and comparison gates still use medians; an outlier can make the badge's
mean differ from the report's median.

## Record and regenerate

PowerShell **7.5+**, Git and the existing harness are required. Select exactly
three private trial directories and their saved `efficiency-control-v1` series:

```powershell
$trials = 1..3 | ForEach-Object { "/private/control/trials/baseline-$_" }
./tests/tier2/live-benchmark/Export-BenchmarkResults.ps1 `
  -ControlPath /private/control/out/control-series.json `
  -TrialDirectories $trials -SeriesId run-YYYYMMDD-HHMMSS-identifier -SelectCurrent
```

For a native `-Mode Series` run reusing saved controls, use its
`out/series-evidence.json` as `-ControlPath` and the three `candidate-1` through
`candidate-3` trial directories. That file contains six original raw runs:
three saved controls and three new candidates. The importer validates those
arm/slot identities and selects **all three** supplied candidate trials without
rebuilding native Run objects or inventing a new control series.

Import validates saved runs against the selected trial files, original judge and
document hashes, complete numeric coverage, source/protocol fingerprints and
measured revision ancestry. It creates a new record exclusively; never overwrite
an earlier series. `-SelectCurrent` explicitly updates the pointer and generates
`report.json`, `report.md`, and `badge.svg`. Review/commit these files together.
No model is called and no observation is regraded during export.
Incomplete metering or unavailable required fields stop import; product failures
remain false. SHA changes for docs/results alone need no new measurements.

The root README uses relative image/report links, so its badge follows the
branch being viewed. It shows quality median, functional pass count and complete
workflow pass count independently; incomplete acceptance is amber, unavailable
grey. SVG is static, contains no script and uses no remote badge service.

## Compare the actual parent

```powershell
./tests/tier2/live-benchmark/Compare-BranchBenchmark.ps1 `
  -BaseRef origin/jmservera/performance-comparison -HeadRef HEAD `
  -OutputDirectory ./benchmark-report
```

The parent is explicit, not assumed to be `main`. The separate read-only
**Tier 2 Recorded Benchmark** workflow resolves immutable parent/head SHAs,
including stacked/fork PRs. Each pointer,
record and source fingerprint is read from its own snapshot. The merge-base is
reported only for context, not used as the baseline. A head-edited policy or
copy of the original file cannot replace the base's policy/evidence.

| Exit | Meaning |
|---|---|
| 0 | Valid non-regression, or unchanged source/protocol using identical evidence |
| 1 | Unexpected operational failure |
| 2 | Missing, invalid, stale, incompatible or non-evaluable evidence |
| 3 | Measured regression |

Missing `main` results explicitly fail; there is no fallback to another branch
or Actions artifact. Identical selected evidence means **no independent candidate
measurement**, not improvement. Changed source with inherited evidence is stale;
independent series must have disjoint IDs. Historical records cannot be edited
or removed in a comparison. Selecting a new current record requires review and
does not invoke the harness's strict baseline-promotion function.

Trial UUIDs must use canonical lowercase, hyphenated `D` format. Alternate casing
is rejected as invalid evidence, not normalized, so it cannot disguise reused
trials within or across series.

## Report and screening policy

### Offline study and external rating analysis

The optional study reader does not run agents, change the three-trial collector
or promote evidence. Supply a private local manifest and, optionally, external
ratings:

```powershell
Import-Module ./tests/tier2/live-benchmark/BenchmarkStudy.psm1
Get-BenchmarkStudyAnalysis -Repository . -ManifestPath /private/study.json `
  -AnnotationPath /private/ratings.json | ConvertTo-Json -Depth 32
```

Omit `-AnnotationPath` when no ratings exist. The manifest uses
`schemaVersion: benchmark-study-v1`, `studyId`, `strata`, `batches` and `slots`:

* A stratum declares `stratumId`, `taskId`, `taskRole` (`development` or
  `held-out`), `design` (`descriptive`, `aa` or `ab`) and `protocolFingerprint`.
  The fingerprint is SHA-256 of the UTF-8 `ConvertTo-BenchmarkCanonicalJson`
  representation of the record's complete `protocol`.
* A batch declares `batchId`, `stratumId`, `arm`, `recordPath` (below
  `benchmarks/efficiency/records/`) and `recordSha256` (exact file bytes).
* A slot declares `slotId`, `stratumId`, `arm`, `state` and, for `recorded`,
  `batchId`/`runId`. Every referenced batch's three trials must appear exactly
  once. `planned` slots have no observation; `aborted` slots add a bounded
  operator `reason`, not invented outcomes or resource values.

The reader validates each record at its own measured Git revision, not against
today's protocol. This permits historical description **without** bypassing the
strict current-branch comparison. It rejects overlapping trial IDs, incomplete
batches, invalid digests and path/symlink escapes. Strata and arms remain
separate; statistics reduce all included trials, not medians of batches.
An A/A stratum requires disjoint recorded arms with identical source/protocol;
these declarations do not establish randomized execution or causal effects.

Interrupted attempts remain visible. Recorded-only acceptance is conditional on
exported evidence; when aborts exist, whole-study reliability and complete
resource totals are unavailable. Planned slots are not attempts. Unknown optional
metrics stay unknown, and zero accepted workflows cannot yield a zero-cost ratio.

Optional `benchmark-human-annotations-v1` input contains an `annotations` array.
Each annotation binds its `annotationId`, all three document hashes, record
digest, source/revision/run ID, rubric, judge implementation (`protocol.parserHash`)
and recorded model string to an included trial. `recordedModelHash` is null for
v1, which has no model-artifact hash. It includes the five integer dimension
ratings (0-20) and an external attestation with opaque `annotatorId`,
`attestationRef` and status `externally-attested-human`. Keep documents, actual
ratings, identities and attestation material private; do not commit them here.

Attestation strings do not authenticate humans or expertise. Valid input produces
only descriptive rating coverage/differences and `external-ratings-present`,
never calibrated/approved status. With no annotations calibration is `unassessed`.
Actual expert adjudication, repeated judging of frozen artifacts, representative
task selection and an authorized live A/A pilot remain empirical work.

### Fixed-series screening

`policy.json` is loaded from the base. Version 1 permits at most 5% growth in
combined per-trial median credits, usage-accounting requests, input/output
tokens, tool calls and **measured process wall seconds**. Workflow counters are
the final cumulative snapshot counted once; independently metered judge counters
are added once. Time sums each stage's `process.seconds` and the judge's process
seconds. Stage clocks include snapshot, parsing and readiness work, not just
native subprocess execution. It is not event-span time, pure agent latency or
whole-wizard duration.

The quality score assesses BRD/PRD documents, not delivered software. No expert
calibration or statistical significance is established by these three trials.
Observed total consumption per accepted workflow divides all recorded consumption
(including unsuccessful trials) by full-workflow successes. Zero successes means
unavailable, not zero consumption or an expected retry-cost estimate.

Quality total and each of five dimension medians cannot decline. Critical/high
findings and combined tool failures use three-trial sums with no increase
(failure sums deliberately expose outliers hidden by the old failure median).
Every functional probe/state/readiness/workflow boolean uses pass count out of
three, with no decrease. Split workflow/judge values, optional cache tokens and
event intervals are diagnostic, not extra gates. Missing required token coverage
cannot become zero even if general metering says complete. From zero, positive
growth has an undefined percentage and explicit absolute worsening.

Reports lead with a plain-language verdict, readable performance/consumption
and quality/acceptance summaries, and checks needing attention. Expandable
sections retain all exact samples, medians/ranges, sums, per-check pass counts,
fingerprints, compatibility fields and machine reasons. `report.json` preserves
the full machine-readable data; presentation rounding does not change gates. A 10% request/input-token improvement screen
is separate from non-regression, product acceptance and strict promotion.
Three independent series samples are unpaired screening evidence, not
statistical significance or a guarantee of causality.

## Automatic release collection

**Tier 2 Benchmark** (`.github/workflows/tier2-benchmark.yml`) is the bounded
pre-publication collector used by Release and standalone manual diagnostics.
It never runs on PRs or ordinary pushes; the existing Release event remains the
only automatic paid entry point. It freezes the reviewed default-branch
controller (upstream default branch for a fork), its selected immutable v2
record, candidate SHA, effective release version and policy before installation
or spending. An optional diagnostic `base_sha` must equal that reviewed tip;
`head_sha` defaults to the selected branch's immutable SHA.

By default, **only candidate-1, candidate-2 and candidate-3 are launched**.
The historical base is copied byte-for-byte from the controller selection.
Baseline is not prepared, installed, run or exported. The original candidate
observations are exported in their own frozen candidate HEAD context using the
existing three-run `efficiency-control-v1` wrapper; no baseline runs are invented.
Candidate-edited pointers cannot select the reference. Pointer/digest, measured
source/revision ancestry, immutable common history and all seven executing
scenario/parser/exercise/preparation/grader/verifier/converter digests still
fail closed before spending.

This is always an **approximate historical comparison**, not source-only
causality or proof of equal environments, even when all protocol values agree.
The explicit `Compare-BenchmarkSeries -HistoricalReference` mode permits only
`installHash`, `powershell`, `cliVersion`, `maxCredits` and `roleModelPolicyHash`
differences. Exact original old/new values appear in returned
`protocolDifferences`, JSON, Markdown and the release identity. A role-policy
digest is disclosed as a digest; it cannot recover the original policy text.
Model, schema, rubric, host profile, evaluator digests, MCP configuration,
evaluation/recovery policy and continuations remain strict. Neither record is
normalized. All existing quality, reliability, failure and 5% efficiency gates
remain unchanged; historical credits stay in the statistics, not today's spend.

Manual Release, reusable collection and diagnostic entry points expose
`refresh_reference`, a boolean defaulting to **false**. Only an explicit true
requests fresh paired deployments: baseline-1, candidate-1 through baseline-3,
candidate-3. Both arms use their own frozen source-bound dependency installs,
original six-run evidence and HEAD-correct exports. This mode permits installation
variance only; ordinary stored-record comparisons remain fully strict.
Missing/incompatible evidence, large deltas, regressions and failures never
trigger a refresh, retry, fallback or automatic baseline promotion.

`collection-policy.json` is the reviewed controller authority, not a candidate
input. Its default is 1000 credits per trial and a 6000-credit campaign ceiling
(a maximum, not required spend), with pinned CLI/model and a bounded campaign
timeout. Default mode reserves 3000; explicit refresh reserves 6000.
A future 3000 ceiling permits candidate-only mode and rejects paired refresh
before installation. Failed slots retain known cumulative workflow and
independent judge usage exactly once. Missing, invalid or timed-out accounting
leaves the total unknown, preserves its known lower bound, stops further
launches and blocks publication. Historical usage neither consumes nor expands
the current reservation.

The Release workflow requires comparison success **before any version bump,
tag push or GitHub Release creation**, including draft creation. Regressions,
missing/stale/incompatible evidence and operational errors block publication;
Tier 0 still applies. The release uses the same frozen candidate that was compared,
not a moving branch. Version and self-reference manifest edits do not change the
measured Squad source or benchmark protocol.

Manual **Release** runs expose a boolean **`run_benchmark`**, default **true**.
A human with release-dispatch permission can uncheck it to bypass only this
gate. **Release Prep** explicitly passes `run_benchmark=true` and preserves
candidate-only collection by not requesting refresh.
The skipped gate and warning are recorded in the run summary;
other release checks remain mandatory. Push-triggered releases cannot bypass it.
No post-publication benchmark trigger remains. Direct publication outside the
Release workflow is not controlled by this gate.

The paid secret reaches only the collection step, never installation.
Private trials, logs and documents stay out of uploads. The exact artifact
allowlist is `report.json`, `report.md`, `badge.svg`, `identity.json`,
`base-record.json` and `head-record.json`; failures retain sanitized reports.
Both publication validations receive the independent requested refresh mode.
They recompute scope, differences, warnings, verdict and accounting from original
records, require the historical base digest to equal the exact controller
selection, and bind fresh series IDs to
`release-RUN-ATTEMPT-candidate` (and `release-RUN-ATTEMPT-baseline` on refresh).
Old resealed same-candidate records, wrong modes/slots and current candidate
policy violations cannot pass. Historical bases are not required to match today's
reservation or CLI. Final publication binds the tag commit, permitting only
version/self-reference manifest edits. Existing tags skip paid collection.

The reviewed workflow YAML is itself the controller trust root.
A PR editing it is review-required infrastructure, not independently
authenticated evidence. Manual overrides require **full commit SHAs**; automatic
defaults resolve branch tips once before checkout. The default-branch controller
must be reviewed and trusted; never choose an unreviewed base merely because it
is called base. Fork identity does not grant code trust.

When the controller lacks tooling or selected compatible evidence, collection
fails; it never runs a candidate evaluator as fallback.
Never bypass existing required checks. Workflow registration and automatic
release orchestration requires the workflow on the default branch; a change delivered
only on an integration branch may need that merge before manual dispatch is
available. Hosted use requires the trusted controller to contain this
implementation. Offline tests do not establish a hosted or paid campaign result.

### Strict stored-record analysis (no paid calls)

The prior read-only workflow is retained as
`.github/workflows/tier2-recorded-benchmark.yml`. Its optional base/head overrides
resolve independently to the selected branch and PR parent (including upstream
fork PRs), or the default branch when no PR exists. Ambiguous/self parents
require an explicit base. Release-tag analysis peels annotated tags and paginates
stable releases to find a prior ancestor rather than an unrelated newer hotfix.
It executes only reviewed base tooling, never candidate helpers, and emits
missing-baseline exit 2 if no prior evidence/tooling exists. It does not collect,
refresh or promote records, use model secrets, or waive protocol differences.
Its artifact allowlist remains only Markdown, JSON and SVG.

## Reproduce the original environment

Historical `benchmark-series-v1` records preserve their original actual revision,
source hash, protocol and dependency-install identities. Their verifier hash was
derived from the measured Git revision, not observed executing-file telemetry;
they also lack a native converter digest. They remain readable for descriptive
historical analysis, but current snapshot validation explicitly rejects them as
`stale-record:unbound-execution-protocol`. Existing records and their pointer
are never rewritten by collection.

New exports use `benchmark-series-v2`. Live compatibility binds the native
converter actually loaded from the selected source checkout
(`scripts/Build-SquadPlugin.ps1`) and the state verifier actually executed from
the harness checkout (`scripts/Test-SquadScribeOutput.ps1`). Export requires both
digests to agree with the measured Git revision; mismatched or unbound raw
controls are refused, never retrospectively relabeled. Converter-only changes
invalidate inherited snapshot evidence even when `squad-src` is unchanged.
Full machine attestation remains unavailable. For new observations, pin both:

```powershell
$env:COPILOT_CLI_DIST_DIR = '/local/cache/copilot/pkg/linux-x64/1.0.101-0'
$env:COPILOT_AUTO_UPDATE = 'false'
```

Validate the actual CLI, model, PowerShell, prepared installation and frozen
scenario/parser/exercise/preparation/grader/verifier/converter before any paid execution.
Use fresh workspaces. Outside the five explicitly disclosed historical fields,
a mismatch blocks comparison: do not waive it or automatically buy replacement controls. A different reference
campaign needs separate authorization. Never retry until the result looks good.

Run the portable record, study and installer regressions without paid execution
using PowerShell 7.5+ and pinned Pester 5.7.1:

```powershell
pwsh -NoProfile -File ./tests/tier2/live-benchmark/Invoke-BenchmarkEvidenceTests.ps1
```
