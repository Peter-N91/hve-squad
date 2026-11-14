# Benchmark score

Measured: 2026-11-13 21:16 UTC, measured commit `28dcec0`, measured squad source hash `6ed4aa9fd381d68dfe5026055262a6dbbcdd973d956a18f6965a3df350ed7c73`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 3 runs; not an identity of the current checkout.
The squad source had uncommitted changes when this was measured.

| Measure | Result |
| --- | --- |
| Document quality (median, out of 100) | 80 |
| Functional (runs passing) | 3/3 |
| Workflow (runs passing) | 0/3 |
| JUDGE-ONLY critical/high findings | 3 (1 per scored run) |
| Average time per scored run | 38 min 25.1 s |
| Average credits per scored run | 617.37 |
| Runs that produced a score | 3/3 |
| All-requested time (total observed) | 115 min 15.2 s; 3/3 requested runs covered |
| All-requested time (average observed) | 38 min 25.1 s; 3/3 requested runs covered |
| All-requested credits (total observed) | 1852.1; 3/3 requested runs covered |
| All-requested credits (average observed) | 617.37; 3/3 requested runs covered |

Scored-only averages use 3 scored run(s); all-requested totals/means use only the covered slots, including unscored trials, without imputing missing data.
JUDGE-ONLY findings cover only the inputs supplied to the unchanged document judge, not whole-workflow risk coverage. Stage reviews are separate sources and are never added together; unavailable severity coverage is not zero.
#### Latest stage reviews

| Run | Review source | Outcome check | Review path (workspace-relative) | Critical/high (source only) |
| --- | --- | --- | --- | --- |
| 1 | requirements | failed | `.copilot-tracking/reviews/2026-11-13/closing-review.md` | unavailable |
| 1 | build | passed | `.copilot-tracking/reviews/2026-11-13/implementation-closing-review.md` | unavailable |
| 2 | requirements | failed | `.copilot-tracking/reviews/2026-11-13/closing-review.md` | unavailable |
| 2 | build | passed | `.copilot-tracking/reviews/2026-11-13/implementation-closing-review.md` | unavailable |
| 3 | requirements | failed | `.copilot-tracking/reviews/2026-11-13/task-cli-closing-review.md` | unavailable |
| 3 | build | passed | `.copilot-tracking/reviews/2026-11-13/task-cli-implementation-review.md` | unavailable |
Comparison identity: incompatible. Missing identities: . Differing identities: parserHash, exerciseHash, installHash. Figures are descriptive, not a controlled causal comparison.

## Observed activity

| Observed activity | Earlier run | Latest run |
| --- | --- | --- |
| Scribe dispatches | 0 | 0 |
| Scribe model requests | 0 | 0 |
| Time inside Scribe dispatches | 0 min 0 s | 0 min 0 s |
| Scribe credits | 0 | 0 |
| Coordinator model requests | 57.5 | 48.33 |
| BRD/PRD author model requests | 32 | 49 |

Activity is averaged per scored run; a metric is unavailable if any scored run lacks it. Dispatch time is summed per Scribe dispatch, not elapsed benchmark time. Requests count unique usage records; credits cover those records, excluding separate compaction charges and the judge.

Earlier run: 2026-11-13 13:46 UTC, measured commit `55a6a14`, measured squad source hash `0837686ea435cbac29cb267ff06a29b459c236662df34216e34c93dff8c247af`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 3 runs; not an identity of the current checkout.

## Document quality by dimension (median, out of 20)

| Dimension | Score |
| --- | --- |
| Business clarity | 16 |
| Scope fidelity | 16 |
| Acceptance criteria | 16 |
| Traceability | 16 |
| Risks and decisions | 15 |

## Runs

| Run | Scored | Quality | Functional | Workflow | JUDGE-ONLY critical/high | Time | Credits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | yes | 76 | yes | no | 2 | 39 min 57.6 s | 625.95 |
| 2 | yes | 80 | yes | no | 1 | 37 min 33.9 s | 603.42 |
| 3 | yes | 83 | yes | no | 0 | 37 min 43.7 s | 622.73 |

## What did not pass

- Run 1: `init/bookkeepingEvidence`, `requirements/bookkeepingEvidence`, `requirements/reviewOutcome`, `requirements/stateVerifier`, `build/stateVerifier`
- Run 2: `init/bookkeepingEvidence`, `requirements/bookkeepingEvidence`, `requirements/reviewOutcome`, `requirements/stateVerifier`, `build/stateVerifier`
- Run 3: `init/bookkeepingEvidence`, `requirements/bookkeepingEvidence`, `requirements/reviewOutcome`, `requirements/stateVerifier`, `build/stateVerifier`

How to read and refresh this score: [README](README.md).
