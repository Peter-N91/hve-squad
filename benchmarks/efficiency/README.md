# Repository benchmark evidence

[![Observed quality and acceptance](badge.svg)](report.md)

`current.json` selects one immutable `records/<series-id>.json` by SHA-256.
This is **recorded observational evidence, not an approved quality baseline**.
The three original pristine observations include real functional, state and
review-deliverable failures. A score must never conceal those failures.
Private logs, generated documents, judge explanations and session identifiers
are not committed. File hashes provide integrity, not authenticated execution.

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

The parent is explicit, not assumed to be `main`. PR Actions use immutable
`pull_request.base.sha` and `head.sha`, including stacked/fork PRs. Each pointer,
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

## Report and screening policy

`policy.json` is loaded from the base. Version 1 permits at most 5% growth in
combined per-trial median credits, usage-accounting requests, input/output
tokens, tool calls and **measured process wall seconds**. Workflow counters are
the final cumulative snapshot counted once; independently metered judge counters
are added once. Time sums each stage's `process.seconds` and the judge's process
seconds. It is not event-span time or whole-wizard duration.

Quality total and each of five dimension medians cannot decline. Critical/high
findings and combined tool failures use three-trial sums with no increase
(failure sums deliberately expose outliers hidden by the old failure median).
Every functional probe/state/readiness/workflow boolean uses pass count out of
three, with no decrease. Split workflow/judge values, optional cache tokens and
event intervals are diagnostic, not extra gates. Missing required token coverage
cannot become zero even if general metering says complete. From zero, positive
growth has an undefined percentage and explicit absolute worsening.

Reports include all samples, medians/ranges, sums, per-check pass counts,
fingerprints and failure reasons. A 10% request/input-token improvement screen
is separate from non-regression, product acceptance and strict promotion.
Three independent series samples are unpaired screening evidence, not
statistical significance or a guarantee of causality.

## GitHub Actions and bootstrap

The read-only **Efficiency comparison** workflow publishes the full report in
the run Summary and uploads Markdown, JSON and SVG even when comparison fails.
It calls no paid model, uses no model secrets and executes the selected **base**
comparator/dependencies; head contents are Git blobs/JSON, not executable code.
Actions are SHA-pinned and checkout credentials are not persisted.

The reviewed workflow YAML/bootstrap is itself the controller trust root.
A PR editing it is review-required infrastructure, not independently
authenticated evidence. Manual dispatch requires authorized reviewed base and
candidate **full commit SHAs** in this repository; never choose an unreviewed
base merely because it is called base. Fork identity does not grant code trust.

When the base lacks the helper or selected record, the bootstrap explicitly
reports missing baseline/tooling and fails; it never runs a head helper.
The initial infrastructure/seed PR therefore has an expected nonzero comparison.
Do not make this new check required until the parent is seeded, and never bypass
existing required checks. Dispatch for a workflow introduced only on a
nondefault branch may remain unavailable until default-branch registration;
use the PR Summary or the same local report, and do not invent an Actions run.

## Reproduce the original environment

The record preserves the original actual revision and source hash plus protocol
and dependency-install identities. The verifier hash is derived from the
measured Git revision, not retrospectively claimed native telemetry. Full
machine attestation is unavailable. For compatible new observations, pin both:

```powershell
$env:COPILOT_CLI_DIST_DIR = '/local/cache/copilot/pkg/linux-x64/1.0.101-0'
$env:COPILOT_AUTO_UPDATE = 'false'
```

Validate the actual CLI, model, PowerShell, prepared installation and frozen
scenario/parser/exercise/preparation/grader/verifier before any paid execution.
Use fresh workspaces. A mismatch blocks the historical comparison: do not
waive it or automatically buy replacement controls. A different reference
campaign needs separate authorization. Never retry until the result looks good.
