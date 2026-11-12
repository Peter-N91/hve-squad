# Benchmark score

Measured: 2026-11-12 18:02 UTC, commit `6d178b0`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.106-9. Run copilot update to check for up`, 3 runs.

| Measure | Result |
| --- | --- |
| Document quality (median, out of 100) | 81.5 |
| Functional (runs passing) | 3/3 |
| Workflow (runs passing) | 0/3 |
| Critical/high findings | 0 (0 per run) |
| Average time per run | 22 min 42.4 s |
| Average credits per run | 320.31 |
| Runs that produced a score | 2/3 |

## Observed activity

| Observed activity | Earlier run | Latest run |
| --- | --- | --- |
| Scribe dispatches | 1 | 0 |
| Scribe model requests | 3 | 0 |
| Time inside Scribe dispatches | 0 min 11.5 s | 0 min 0 s |
| Scribe credits | 0.38 | 0 |
| Coordinator model requests | 46 | 45.5 |
| BRD/PRD author model requests | 40 | 7 |

Activity is averaged per scored run; a metric is unavailable if any scored run lacks it. Dispatch time is summed per Scribe dispatch, not elapsed benchmark time. Requests count unique usage records; credits cover those records, excluding separate compaction charges and the judge.

Earlier run: 2026-10-26 16:26 UTC, commit `3bf61f0`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.104-3. Run copilot update to check for up`, 1 run.

## Document quality by dimension (median, out of 20)

| Dimension | Score |
| --- | --- |
| Business clarity | 17 |
| Scope fidelity | 18 |
| Acceptance criteria | 16.5 |
| Traceability | 15 |
| Risks and decisions | 15 |

## Runs

| Run | Scored | Quality | Functional | Workflow | Critical/high | Time | Credits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | yes | 82 | yes | no | 0 | 24 min 27.5 s | 335.28 |
| 2 | no | n/a | yes | no | n/a | 32 min 45.3 s | n/a |
| 3 | yes | 81 | yes | no | 0 | 20 min 57.3 s | 305.34 |

## What did not pass

- Run 1: `init/scribeHistory`, `requirements/scribeHistory`, `requirements/reviewOutcome`, `requirements/stateVerifier`, `build/stateVerifier`
- Run 2: the judge result is missing or invalid, `init/scribeHistory`, `requirements/scribeHistory`, `requirements/reviewOutcome`, `requirements/stateVerifier`, `build/stateVerifier`
- Run 3: `init/scribeHistory`, `requirements/scribeHistory`, `requirements/stateVerifier`, `build/stateVerifier`

How to read and refresh this score: [README](README.md).
