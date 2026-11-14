# Benchmark score

Measured: 2026-11-14 11:03 UTC, measured commit `5928d57`, measured squad source hash `6ed4aa9fd381d68dfe5026055262a6dbbcdd973d956a18f6965a3df350ed7c73`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 3 runs; not an identity of the current checkout.

| Measure | Result |
| --- | --- |
| Document quality (median, out of 100) | 82 |
| Functional (runs passing) | 3/3 |
| Workflow (runs passing) | 0/3 |
| JUDGE-ONLY critical/high findings | 0 (0 per scored run) |
| Average time per scored run | 27 min 34.4 s |
| Average credits per scored run | 424.76 |
| Runs that produced a score | 3/3 |
| All-requested time (total observed) | 82 min 43.2 s; 3/3 requested runs covered |
| All-requested time (average observed) | 27 min 34.4 s; 3/3 requested runs covered |
| All-requested credits (total observed) | 1274.29; 3/3 requested runs covered |
| All-requested credits (average observed) | 424.76; 3/3 requested runs covered |

Scored-only averages use 3 scored run(s); all-requested totals/means use only the covered slots, including unscored trials, without imputing missing data.
JUDGE-ONLY findings cover only the inputs supplied to the unchanged document judge, not whole-workflow risk coverage. Stage reviews are separate sources and are never added together; unavailable severity coverage is not zero.
#### Latest stage reviews

| Run | Review source | Outcome check | Review path (workspace-relative) | Critical/high (source only) |
| --- | --- | --- | --- | --- |
| 1 | requirements | failed | `.copilot-tracking/reviews/2026-11-14-task-cli-closing-review-capture.md` | unavailable |
| 1 | build | passed | `.copilot-tracking/reviews/2026-11-14-task-cli-impl-closing-review-capture.md` | unavailable |
| 2 | requirements | failed | `.copilot-tracking/reviews/task-cli-requirements-review.md` | unavailable |
| 2 | build | passed | `.copilot-tracking/reviews/task-cli-implementation-review.md` | unavailable |
| 3 | requirements | failed | `.copilot-tracking/reviews/2026-11-14-task-cli-brd-prd-closing-review.md` | unavailable |
| 3 | build | failed | `.copilot-tracking/reviews/2026-11-14-task-cli-implementation-review.md` | unavailable |
Comparison identity: incompatible. Missing identities: . Differing identities: installHash. Figures are descriptive, not a controlled causal comparison.

## Observed activity

| Observed activity | Earlier run | Latest run |
| --- | --- | --- |
| Scribe dispatches | 0 | 0 |
| Scribe model requests | 0 | 0 |
| Time inside Scribe dispatches | 0 min 0 s | 0 min 0 s |
| Scribe credits | 0 | 0 |
| Coordinator model requests | 48.33 | 52.67 |
| BRD/PRD author model requests | 49 | 20 |

Activity is averaged per scored run; a metric is unavailable if any scored run lacks it. Dispatch time is summed per Scribe dispatch, not elapsed benchmark time. Requests count unique usage records; credits cover those records, excluding separate compaction charges and the judge.

Earlier run: 2026-11-13 21:16 UTC, measured commit `28dcec0`, measured squad source hash `6ed4aa9fd381d68dfe5026055262a6dbbcdd973d956a18f6965a3df350ed7c73`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 3 runs; not an identity of the current checkout.

## Document quality by dimension (median, out of 20)

| Dimension | Score |
| --- | --- |
| Business clarity | 16 |
| Scope fidelity | 15 |
| Acceptance criteria | 17 |
| Traceability | 16 |
| Risks and decisions | 16 |

## Runs

| Run | Scored | Quality | Functional | Workflow | JUDGE-ONLY critical/high | Time | Credits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | yes | 79 | yes | no | 0 | 36 min 21.5 s | 568.49 |
| 2 | yes | 82 | yes | no | 0 | 19 min 19 s | 285.84 |
| 3 | yes | 82 | yes | no | 0 | 27 min 2.8 s | 419.95 |

## What did not pass

- Run 1: `init/bookkeepingEvidence`, `requirements/bookkeepingEvidence`, `requirements/reviewOutcome`
- Run 2: `init/bookkeepingEvidence`, `requirements/bookkeepingEvidence`, `requirements/reviewOutcome`
- Run 3: `init/bookkeepingEvidence`, `requirements/bookkeepingEvidence`, `requirements/reviewOutcome`, `build/reviewOutcome`

How to read and refresh this score: [README](README.md).
