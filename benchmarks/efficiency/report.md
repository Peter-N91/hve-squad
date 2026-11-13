# Benchmark score

Measured: 2026-11-12 23:30 UTC, commit `4dc0a3a`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 3 runs.

| Measure | Result |
| --- | --- |
| Document quality (median, out of 100) | 81 |
| Functional (runs passing) | 1/3 |
| Workflow (runs passing) | 0/3 |
| Critical/high findings | 0 (0 per run) |
| Average time per run | 32 min 35.4 s |
| Average credits per run | 392.05 |
| Runs that produced a score | 3/3 |

## Observed activity

| Observed activity | Earlier run | Latest run |
| --- | --- | --- |
| Scribe dispatches | 0 | 0 |
| Scribe model requests | 0 | 0 |
| Time inside Scribe dispatches | 0 min 0 s | 0 min 0 s |
| Scribe credits | 0 | 0 |
| Coordinator model requests | 45.5 | 49.67 |
| BRD/PRD author model requests | 7 | 7 |

Activity is averaged per scored run; a metric is unavailable if any scored run lacks it. Dispatch time is summed per Scribe dispatch, not elapsed benchmark time. Requests count unique usage records; credits cover those records, excluding separate compaction charges and the judge.

Earlier run: 2026-11-12 18:02 UTC, commit `6d178b0`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 3 runs.

## Document quality by dimension (median, out of 20)

| Dimension | Score |
| --- | --- |
| Business clarity | 18 |
| Scope fidelity | 16 |
| Acceptance criteria | 17 |
| Traceability | 16 |
| Risks and decisions | 15 |

## Runs

| Run | Scored | Quality | Functional | Workflow | Critical/high | Time | Credits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | yes | 85 | yes | no | 0 | 24 min 41.4 s | 393.02 |
| 2 | yes | 81 | no | no | 0 | 34 min 5.4 s | 356.31 |
| 3 | yes | 76 | no | no | 0 | 38 min 59.5 s | 426.82 |

## What did not pass

- Run 1: `init/scribeHistory`, `requirements/scribeHistory`, `requirements/PRD Quality Reviewer`, `requirements/reviewOutcome`, `requirements/stateVerifier`, `build/stateVerifier`
- Run 2: `functional/id-boundary-preserves-store`, `init/scribeHistory`, `requirements/scribeHistory`, `requirements/stateVerifier`, `build/stateVerifier`
- Run 3: `functional/id-boundary-preserves-store`, `init/scribeHistory`, `requirements/scribeHistory`, `requirements/reviewOutcome`, `requirements/stateVerifier`, `build/stateVerifier`

How to read and refresh this score: [README](README.md).
