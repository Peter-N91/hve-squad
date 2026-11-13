# Benchmark score

Measured: 2026-11-13 13:46 UTC, measured commit `55a6a14`, measured squad source hash `0837686ea435cbac29cb267ff06a29b459c236662df34216e34c93dff8c247af`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 3 runs; not an identity of the current checkout.
The squad source had uncommitted changes when this was measured.

| Measure | Result |
| --- | --- |
| Document quality (median, out of 100) | 75.5 |
| Functional (runs passing) | 3/3 |
| Workflow (runs passing) | 0/3 |
| JUDGE-ONLY critical/high findings | 4 (2 per scored run) |
| Average time per scored run | 41 min 12.7 s |
| Average credits per scored run | 631.58 |
| Runs that produced a score | 2/3 |
| All-requested time (total observed) | 134 min 14.8 s; 3/3 requested runs covered |
| All-requested time (average observed) | 44 min 44.9 s; 3/3 requested runs covered |
| All-requested credits (total observed) | 1263.16; 2/3 requested runs covered |
| All-requested credits (average observed) | 631.58; 2/3 requested runs covered |

Scored-only averages use 2 scored run(s); all-requested totals/means use only the covered slots, including unscored trials, without imputing missing data.
JUDGE-ONLY findings cover only the inputs supplied to the unchanged document judge, not whole-workflow risk coverage. Stage reviews are separate sources and are never added together; unavailable severity coverage is not zero.
#### Latest stage reviews

| Run | Review source | Outcome check | Review path (workspace-relative) | Critical/high (source only) |
| --- | --- | --- | --- | --- |
| 1 | requirements | failed | `.copilot-tracking/reviews/2026-11-13/task-cli-requirements-closing-review.md` | unavailable |
| 1 | build | passed | `.copilot-tracking/reviews/2026-11-13/task-cli-implementation-closing-review.md` | unavailable |
| 2 | requirements | failed | `.copilot-tracking/reviews/2026-11-13/closing-review.md` | unavailable |
| 2 | build | passed | `.copilot-tracking/reviews/2026-11-13/implementation-closing-review.md` | unavailable |
| 3 | requirements | failed | `.copilot-tracking/reviews/2026-11-13/task-cli-requirements-closing-review.md` | unavailable |
| 3 | build | passed | `.copilot-tracking/reviews/2026-11-13/task-cli-implementation-closing-review.md` | unavailable |
Comparison identity: unknown. Missing identities: schema, rubric, hostProfile, scenarioHash, parserHash, exerciseHash, preparationHash, graderHash, verifierHash, converterHash, installHash, model, cli, powershell, roleModelPolicy, disabledMcpServers, maxCredits, continuations, recoveryPolicy, evaluationPolicy. Differing identities: . Figures are descriptive, not a controlled causal comparison.

## Observed activity

| Observed activity | Earlier run | Latest run |
| --- | --- | --- |
| Scribe dispatches | 0 | 0 |
| Scribe model requests | 0 | 0 |
| Time inside Scribe dispatches | 0 min 0 s | 0 min 0 s |
| Scribe credits | 0 | 0 |
| Coordinator model requests | 49.67 | 57.5 |
| BRD/PRD author model requests | 7 | 32 |

Activity is averaged per scored run; a metric is unavailable if any scored run lacks it. Dispatch time is summed per Scribe dispatch, not elapsed benchmark time. Requests count unique usage records; credits cover those records, excluding separate compaction charges and the judge.

Earlier run: 2026-11-12 23:30 UTC, measured commit `4dc0a3a`, measured squad source hash `74079ce3be48cbb9c4835c8523152274389d7f83f95847ddbf7e8e85d394cfbb`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 3 runs; not an identity of the current checkout.

## Document quality by dimension (median, out of 20)

| Dimension | Score |
| --- | --- |
| Business clarity | 15 |
| Scope fidelity | 15 |
| Acceptance criteria | 15.5 |
| Traceability | 15 |
| Risks and decisions | 15 |

## Runs

| Run | Scored | Quality | Functional | Workflow | JUDGE-ONLY critical/high | Time | Credits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | yes | 78 | yes | no | 3 | 37 min 33.3 s | 596.5 |
| 2 | yes | 73 | yes | no | 1 | 44 min 52.2 s | 666.66 |
| 3 | no | n/a | yes | no | n/a | 51 min 49.3 s | n/a |

## What did not pass

- Run 1: `init/bookkeepingEvidence`, `requirements/bookkeepingEvidence`, `requirements/reviewOutcome`, `requirements/stateVerifier`, `build/stateVerifier`
- Run 2: `init/bookkeepingEvidence`, `requirements/bookkeepingEvidence`, `requirements/reviewOutcome`, `requirements/stateVerifier`, `build/stateVerifier`
- Run 3: the judge result is missing or invalid, `init/bookkeepingEvidence`, `requirements/bookkeepingEvidence`, `requirements/reviewOutcome`, `requirements/stateVerifier`, `build/stateVerifier`

How to read and refresh this score: [README](README.md).
