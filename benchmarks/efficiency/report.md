# Benchmark score

Measured: 2026-11-14 16:21 UTC, measured commit `3d9bd03`, measured squad source hash `cf31f281d9591955cb384b8d3308e83750071f31e116e77aa2c87a7df97910f7`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 1 run; not an identity of the current checkout.

| Measure | Result |
| --- | --- |
| Document quality (median, out of 100) | 85 |
| Functional (runs passing) | 1/1 |
| Workflow (runs passing) | 0/1 |
| JUDGE-ONLY critical/high findings | 0 (0 per scored run) |
| Average time per scored run | 44 min 21.2 s |
| Average credits per scored run | 723.45 |
| Runs that produced a score | 1/1 |
| All-requested time (total observed) | 44 min 21.2 s; 1/1 requested runs covered |
| All-requested time (average observed) | 44 min 21.2 s; 1/1 requested runs covered |
| All-requested credits (total observed) | 723.45; 1/1 requested runs covered |
| All-requested credits (average observed) | 723.45; 1/1 requested runs covered |

Scored-only averages use 1 scored run(s); all-requested totals/means use only the covered slots, including unscored trials, without imputing missing data.
JUDGE-ONLY findings cover only the inputs supplied to the unchanged document judge, not whole-workflow risk coverage. Stage reviews are separate sources and are never added together; unavailable severity coverage is not zero.
#### Latest stage reviews

| Run | Review source | Outcome check | Review path (workspace-relative) | Critical/high (source only) |
| --- | --- | --- | --- | --- |
| 1 | requirements | failed | `.copilot-tracking/reviews/2026-11-14/exercise-task-cli-closing-review.md` | unavailable |
| 1 | build | passed | `.copilot-tracking/reviews/2026-11-14/exercise-task-cli-impl-review.md` | unavailable |
Comparison identity: incompatible. Missing identities: . Differing identities: parserHash, installHash. Figures are descriptive, not a controlled causal comparison.

## Observed activity

| Observed activity | Earlier run | Latest run |
| --- | --- | --- |
| Scribe dispatches | 0 | 0 |
| Scribe model requests | 0 | 0 |
| Time inside Scribe dispatches | 0 min 0 s | 0 min 0 s |
| Scribe credits | 0 | 0 |
| Coordinator model requests | 52.67 | 58 |
| BRD/PRD author model requests | 20 | 38 |

Activity is averaged per scored run; a metric is unavailable if any scored run lacks it. Dispatch time is summed per Scribe dispatch, not elapsed benchmark time. Requests count unique usage records; credits cover those records, excluding separate compaction charges and the judge.

Earlier run: 2026-11-14 11:03 UTC, measured commit `5928d57`, measured squad source hash `6ed4aa9fd381d68dfe5026055262a6dbbcdd973d956a18f6965a3df350ed7c73`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 3 runs; not an identity of the current checkout.

## Document quality by dimension (median, out of 20)

| Dimension | Score |
| --- | --- |
| Business clarity | 17 |
| Scope fidelity | 17 |
| Acceptance criteria | 17 |
| Traceability | 18 |
| Risks and decisions | 16 |

## Runs

| Run | Scored | Quality | Functional | Workflow | JUDGE-ONLY critical/high | Time | Credits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | yes | 85 | yes | no | 0 | 44 min 21.2 s | 723.45 |

## What did not pass

- Run 1: `requirements/reviewOutcome`

How to read and refresh this score: [README](README.md).
