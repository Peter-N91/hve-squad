# Benchmark score

Measured: 2026-11-15 10:23 UTC, measured commit `dfc7ff0`, measured squad source hash `4710cecc9f8af51991f03a20ff88fe87b3c307e72c1d48018d3f58453685fffe`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 1 run; not an identity of the current checkout.

| Measure | Result |
| --- | --- |
| Document quality (median, out of 100) | 78 |
| Functional (runs passing) | 0/1 |
| Workflow (runs passing) | 0/1 |
| JUDGE-ONLY critical/high findings | 1 (1 per scored run) |
| Average time per scored run | 38 min 37.3 s |
| Average credits per scored run | 589.69 |
| Runs that produced a score | 1/1 |
| All-requested time (total observed) | 38 min 37.3 s; 1/1 requested runs covered |
| All-requested time (average observed) | 38 min 37.3 s; 1/1 requested runs covered |
| All-requested credits (total observed) | 589.69; 1/1 requested runs covered |
| All-requested credits (average observed) | 589.69; 1/1 requested runs covered |

Scored-only averages use 1 scored run(s); all-requested totals/means use only the covered slots, including unscored trials, without imputing missing data.
JUDGE-ONLY findings cover only the inputs supplied to the unchanged document judge, not whole-workflow risk coverage. Stage reviews are separate sources and are never added together; unavailable severity coverage is not zero.
#### Latest stage reviews

| Run | Review source | Outcome check | Review path (workspace-relative) | Critical/high (source only) |
| --- | --- | --- | --- | --- |
| 1 | requirements | failed | `.copilot-tracking/reviews/task-cli-closing-review.md` | unavailable |
| 1 | build | passed | `.copilot-tracking/reviews/task-cli-implementation-review.md` | unavailable |
Comparison identity: incompatible. Missing identities: . Differing identities: installHash. Figures are descriptive, not a controlled causal comparison.

## Observed activity

| Observed activity | Earlier run | Latest run |
| --- | --- | --- |
| Scribe dispatches | 0 | 0 |
| Scribe model requests | 0 | 0 |
| Time inside Scribe dispatches | 0 min 0 s | 0 min 0 s |
| Scribe credits | 0 | 0 |
| Coordinator model requests | 60 | 51 |
| BRD/PRD author model requests | 44 | 36 |

Activity is averaged per scored run; a metric is unavailable if any scored run lacks it. Dispatch time is summed per Scribe dispatch, not elapsed benchmark time. Requests count unique usage records; credits cover those records, excluding separate compaction charges and the judge.

Earlier run: 2026-11-14 21:45 UTC, measured commit `9a0a716`, measured squad source hash `afb878de7ce7324ea31f65a351213121b5b45e8c825daacff0f3bbfc88e1d435`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 1 run; not an identity of the current checkout.

## Document quality by dimension (median, out of 20)

| Dimension | Score |
| --- | --- |
| Business clarity | 16 |
| Scope fidelity | 15 |
| Acceptance criteria | 15 |
| Traceability | 17 |
| Risks and decisions | 15 |

## Runs

| Run | Scored | Quality | Functional | Workflow | JUDGE-ONLY critical/high | Time | Credits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | yes | 78 | no | no | 1 | 38 min 37.3 s | 589.69 |

## What did not pass

- Run 1: `functional/id-boundary-preserves-store`, `init/bookkeepingEvidence`, `requirements/bookkeepingEvidence`, `requirements/reviewOutcome`, `requirements/stateVerifier`, `build/stateVerifier`

How to read and refresh this score: [README](README.md).
