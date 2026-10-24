# Repository benchmark evidence

[![Latest campaign: comparison unavailable](campaign-badge.svg)](campaign-report.md)

The latest [committed campaign](campaign-report.md) measured revision
`b436d794efd971c01861e15c0015b4c9298d7ff5` on 22 October 2026, the exact
PR45 requirements-repair head. Three original sequential candidate trials scored
**80, 78, 69** (median **78/100**) and consumed **1533.8963735 credits** with
complete canonical accounting. No paid parent trials or replacements ran.
Readiness was **Init 3/3, Requirements 0/3, Build 1/3**; functional probes passed
**3/3**, but full workflow completion was **0/3**.

Both BRD/PRD reviewer-evidence checks passed in every trial; Requirements still
failed its closing-review outcome. Original reviews retain unresolved business
facts, incomplete captures, author-disposition inconsistencies and unsupported
requirements. Build closing reviews in trials 2/3 could not execute required
runtime probes because permission was denied; passing independent functional
probes do not erase that failure. No corrective rerun was performed.

Actual campaign wall time was **70m56.954s**, from **20:18:50.831 UTC** to
**21:29:47.784 UTC**. Child wall times were **23m42.200s**, **20m34.876s** and
**26m33.062s**. These UTC-derived elapsed times are not timeout ceilings or the
stage-plus-judge benchmark-time metric. Native event accounting includes all
five compaction identities and counts final cumulative workflow plus judge once.
CLI usage-output files undercounted trials 1/3 by **6.80717** and **5.41306**
credits; the canonical totals above retain that spend.

`latest-campaign.json` selects a separate immutable `benchmark-campaign-v1`
archive by digest. It is not selectable as a complete comparison series.
The strict comparison remains non-evaluable: the historical parent's changed
exercise protocol is incompatible and was not waived. These observations
establish neither a quality improvement nor Requirements readiness.

## New candidate scoring

The wizard's **Series (2)** collects three candidates without requiring parent
scores. It retains an absolute score, immutable `benchmark-score-v1` record,
Markdown/JSON report and numeric badge before any optional comparison.
**Complete (3)** explicitly collects six observations; missing controls never
silently doubles the Series cost.

Scores use the existing document-quality rubric. Three valid grades produce the
same median /100; fewer formal grades are labeled partial. A local sample is
descriptive 1/1, not a formal series. No trustworthy grade produces a visibly
failed **0/100, not judged** outcome while raw quality stays unknown. This differs
from an actual measured judge grade of zero. Functional/workflow failures remain
separate and prevent approval-green styling.

Use the wizard's printed offline `Export-BenchmarkResults.ps1 -Standalone`
command to append sanitized records here. Explicit `-SelectScore` updates the
existing `current.json` selection after report/badge publication; no baseline
is promoted. Local/partial/failed evidence remains ineligible for strict comparison.
Missing or incompatible parent data means **comparison unavailable**, not
no-regression. The explicit strict comparator and required hosted gate are unchanged.

The independent hosted candidate artifact includes record hashes, reports and a
badge even when parent discovery fails. New-schema reporter activation is pending
owner review and an immutable trusted reporter-pin update; candidate code is never
executed as a reporting fallback. The historical records and numbers below have
not been rewritten by this feature.

## Earlier complete comparison record

[![Earlier complete-series observations](badge.svg)](report.md)

`current.json` selects one immutable `records/<series-id>.json` by SHA-256.
This is **recorded observational evidence, not an approved quality baseline**.
The selected v2 Scribe observations scored **81, 82, 81** (median **81/100**) at
revision `5324132b72a5a2116ce0f7ecf7fc71ed811c8cfa`, after PR #33 merged.
All functional probes passed, but no complete workflow passed. The approximate
comparison against main's stored median 83 detected a regression; the report
preserves that verdict. New consumption was **801.4277195 credits** across three
candidate trials, with no fresh baseline trials.

These observations predate the subsequent cold-Scribe safety fix and merge of
main's dependency update. They describe the measured revision, not the current
branch tip: strict current-source comparison must reject stale evidence until
that changed source is measured. Recording this score does not approve or
promote a baseline. A score must never conceal workflow or provenance failures.
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

### Preserve an incomplete campaign

`-Mode Run` produces private observations, not Git-ready files. Previously only
the explicit complete-series export existed, so a missing grade blocked all
publication. The separate observational exporter now retains available evidence
without loosening the complete-series schema:

```powershell
$trials = @(
  '/private/first-campaign/trials/candidate-1'
  '/private/continued-campaign/trials/candidate-2'
  '/private/continued-campaign/trials/candidate-3'
)
./tests/tier2/live-benchmark/Export-BenchmarkResults.ps1 `
  -ObservationOnly -Repository . -TrialDirectories $trials `
  -SeriesId observed-YYYYMMDD-source
```

Review/commit `campaigns/<id>.json`, `latest-campaign.json`,
`campaign-report.json`, `campaign-report.md`, and `campaign-badge.svg` together.
The command succeeds when export succeeds; the generated report still carries
**comparison exit 2**, not a passing benchmark. `current.json` stays unchanged.
Campaign records cannot be overwritten, selected as complete series, passed to
complete reducers, or promoted. Slots must have disjoint IDs and the same
measured source/protocol; every available run, event and judged-document digest
is checked. Workflow metering must be complete; unavailable judge/grade/documents
stay null. Known spend counts final workflow and available judge exactly once;
no stage-snapshot summation or assumed zero judge cost is permitted.

The wizard now finalizes available observations after each collection step,
including failed collection, into `<run>/control/portable` or
`<run>/comparison/portable`, **outside measured source**. PowerShell 7.5+ is
needed for this export; a 7.4 collection cannot claim export success. It prints
an executable offline PowerShell publication command. Set its `-Repository` to
the writable delivery checkout with matching source/protocol, review and commit.
Collection failure retains its original exit; export failure is separately
reported and cannot trigger a paid retry. Direct `-Mode Run` callers use the
explicit offline command above.
An explicit successful complete-series `-SelectCurrent` export clears the
replaceable campaign pointer; its immutable campaign archive remains untouched.

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

### Useful reports when comparison is unavailable

Each side resolves and validates independently. A missing/broken parent does
not hide trustworthy head values. Supported v1/v2 records may be displayed as
historical observations only after verifying their original measured Git source
and protocol. They remain stale for current comparison; v1 has no bound executing
converter identity. Unknown schema versions, corrupt pointer digests and invalid
records show diagnostics, never guessed numeric values.

Unavailable reports use **separate parent/head observation sections**, with each
source, revision and protocol explicitly labeled. Valid incompatible records
are descriptive only: no paired deltas, ratios or regression certification.
The latest campaign appears separately, including missing values. There is no
silent substitute baseline or history scan. Missing trusted comparison tooling
still reports unavailable; candidate code is never executed as a fallback.
Reports and a grey badge are written before the nonzero verdict. A current
campaign can be archived alongside older complete records, but cannot make
stale, incomplete or incompatible evidence pass.

### Hosted reporting with an older parent implementation

The hosted workflow still executes the **reviewed base** comparator for its
strict gate. Updating a PR's comparator alone therefore cannot update the
hosted report when main still contains an older implementation.

Reporting uses a separate explicit trust source: the report-only implementation
from reviewed PR42, pinned to
`jmservera/hve-squad@019c894bb0430802f47d2fc513fe326bec4023d2`. The workflow
checks out that fixed commit without persisted credentials and verifies its
identity before importing it. The pin is not chosen by a PR ref, branch input,
campaign pointer or candidate file. Candidate Git objects remain data-only:
no candidate comparator, script, module or generated document is executed.
Changing the reporter requires a reviewer-visible immutable pin update.

The original base report, Markdown and badge are retained byte-for-byte under
the uploaded artifact's `strict/` directory. The report engine independently
validates both sides and current campaign source/protocol. A valid current
campaign leads the summary as **incomplete/not-evaluable**, rather than calling
its new measurements stale merely because an older complete pointer remains.
The old strict `stale-record` result is still shown as an **unchanged gate**,
with its original reason and exit. If campaign data is corrupt or its measured
source is no longer current, it cannot receive that current-campaign headline.

Report generation never overrides a failing strict gate. Conversely, a legacy
strict success cannot hide an unavailable campaign or failed reporter: the
final gate remains nonzero. A missing or mismatched reporting implementation
retains the strict artifacts and fails reporting, never executes head tooling
as a fallback. This affects reporting only; no paid work or baseline promotion
is involved. Workflow changes need owner review/merge before hosted use.

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

> **Release scope.** Release and Release Prep only consume stored evidence: they
> call `.github/workflows/tier2-recorded-benchmark.yml` (strict stored-record
> comparison, no model secret, no paid collection). The paid collector below is
> operator-dispatched diagnostics only; wiring it into Release (the six release
> artifacts, frozen-controller validation and publication binding) is kept on the
> separate experimental branch and PR. Statements below that describe Release
> collecting or publishing records apply only to that experiment.

**Tier 2 Benchmark** (`.github/workflows/tier2-benchmark.yml`) is the bounded
paid collector for standalone manual diagnostics (and the experimental release
wiring). It never runs on PRs or ordinary pushes. It freezes the reviewed default-branch
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
other release checks remain mandatory. Push-triggered releases cannot use that
manual bypass.

The legacy stored-comparison bootstrap was bounded through **v0.18.1 inclusive**:
when the frozen candidate's `apm.yml` declares a stable version no higher than
0.18.1, a missing previous stable release or missing trusted base comparator
could emit a warning and permit the legacy release gate. The original missing-baseline
report remains unchanged; no benchmark approval is claimed. This exception
never applies to standalone recorded comparisons or the current fresh collector:
`COLLECTION_REQUIRED=true` disables it even for v0.18.1. It expires entirely
from v0.18.2. Missing/incompatible evidence, candidate gaps, regressions and
operational failures still block current collection.
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

The read-only workflow `.github/workflows/tier2-recorded-benchmark.yml` is the
Release gate and also runs once per pull request to `main` (`pull_request` event,
no secrets, concurrency group per PR number so a new push cancels the stale run).
For a PR it resolves base SHA/repository and head SHA/repository from the event,
so fork heads are fetched as objects only; just the reviewed base checkout
executes. Release reaches it only through `workflow_call` with the frozen candidate. Its optional base/head overrides
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
`stale-record:unbound-execution-protocol`. Main's stored v2 observations measured
revision `59880d5c0417e99a7fe6ab5f12670f8bd9b7401b`; this branch explicitly selects
its later Scribe observations without replacing main's pointer. Historical v1
and v2 records remain unchanged, not relabeled. Collection never rewrites
existing records or selects a new pointer automatically.

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
