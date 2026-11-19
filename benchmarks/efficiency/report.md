# Benchmark score

Measured: 2026-11-19 22:55 UTC, measured commit `773b6e9`, measured squad source hash `4350f43e7b6710f1313c3a80c27eeaa7ff94b3bc417bf13b7839f5a87756d79a`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.114-0. Run copilot update to check for up`, 1 run; not an identity of the current checkout.

| Measure | Result |
| --- | --- |
| Document quality (median, out of 100) | 83 |
| Functional (runs passing) | 1/1 |
| Workflow (runs passing) | 0/1 |
| JUDGE-ONLY critical/high findings | 1 (1 per scored run) |
| Average time per scored run | 51 min 8.6 s |
| Average credits per scored run | 858.38 |
| Runs that produced a score | 1/1 |
| All-requested time (total observed) | 51 min 8.6 s; 1/1 requested runs covered |
| All-requested time (average observed) | 51 min 8.6 s; 1/1 requested runs covered |
| All-requested credits (total observed) | 858.38; 1/1 requested runs covered |
| All-requested credits (average observed) | 858.38; 1/1 requested runs covered |

Scored-only averages use 1 scored run(s); all-requested totals/means use only the covered slots, including unscored trials, without imputing missing data.
JUDGE-ONLY findings cover only the inputs supplied to the unchanged document judge, not whole-workflow risk coverage. Stage reviews are separate sources and are never added together; unavailable severity coverage is not zero.
#### Latest stage reviews

| Run | Review source | Outcome check | Review path (workspace-relative) | Critical/high (source only) |
| --- | --- | --- | --- | --- |
| 1 | requirements | failed | `.copilot-tracking/reviews/task-cli-requirements-closing-review.md` | unavailable |
| 1 | build | passed | `.copilot-tracking/reviews/task-cli-implementation-closing-review.md` | unavailable |
Comparison identity: incompatible. Missing identities: . Differing identities: exerciseHash, installHash. Figures are descriptive, not a controlled causal comparison.

## Observed activity

| Observed activity | Earlier run | Latest run |
| --- | --- | --- |
| Scribe dispatches | 0 | 0 |
| Scribe model requests | 0 | 0 |
| Time inside Scribe dispatches | 0 min 0 s | 0 min 0 s |
| Scribe credits | 0 | 0 |
| Coordinator model requests | 61 | 70 |
| BRD/PRD author model requests | 42 | 41 |

Activity is averaged per scored run; a metric is unavailable if any scored run lacks it. Dispatch time is summed per Scribe dispatch, not elapsed benchmark time. Requests count unique usage records; credits cover those records, excluding separate compaction charges and the judge.

Earlier run: 2026-11-19 16:45 UTC, measured commit `256f73b`, measured squad source hash `40fe7bd7d0e2b86fb73fd3480258c6b1e8d51edfb92fea3603fd692bfb53c60e`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.114-0. Run copilot update to check for up`, 1 run; not an identity of the current checkout.

## Document quality by dimension (median, out of 20)

| Dimension | Score |
| --- | --- |
| Business clarity | 17 |
| Scope fidelity | 16 |
| Acceptance criteria | 17 |
| Traceability | 18 |
| Risks and decisions | 15 |

## Runs

| Run | Scored | Quality | Functional | Workflow | JUDGE-ONLY critical/high | Time | Credits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | yes | 83 | yes | no | 1 | 51 min 8.6 s | 858.38 |

## What did not pass

- Run 1: `requirements/reviewOutcome`

How to read and refresh this score: [README](README.md).
