# Benchmark score

Measured: 2026-10-26 14:20 UTC, commit `9bd6c88`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.103. Run copilot update to check for upda`, 1 run.

| Measure | Result |
| --- | --- |
| Document quality (median, out of 100) | 77 |
| Functional (runs passing) | 1/1 |
| Workflow (runs passing) | 0/1 |
| Critical/high findings | 1 (1 per run) |
| Average time per run | 33 min 20.8 s |
| Average credits per run | 495.39 |
| Runs that produced a score | 1/1 |

## Observed activity

| Observed activity | Earlier run | Latest run |
| --- | --- | --- |
| Scribe dispatches | unavailable | 1 |
| Scribe model requests | unavailable | 2 |
| Time inside Scribe dispatches | unavailable | 0 min 13.1 s |
| Scribe credits | unavailable | 0.26 |
| Coordinator model requests | unavailable | 41 |
| BRD/PRD author model requests | unavailable | 39 |

Activity is averaged per scored run; a metric is unavailable if any scored run lacks it. Dispatch time is summed per Scribe dispatch, not elapsed benchmark time. Requests count unique usage records; credits cover those records, excluding separate compaction charges and the judge.

Earlier run: 2026-10-26 13:09 UTC, commit `7c6a861`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.104-3. Run copilot update to check for up`, 1 run.

## Document quality by dimension (median, out of 20)

| Dimension | Score |
| --- | --- |
| Business clarity | 16 |
| Scope fidelity | 15 |
| Acceptance criteria | 15 |
| Traceability | 17 |
| Risks and decisions | 14 |

## Runs

| Run | Scored | Quality | Functional | Workflow | Critical/high | Time | Credits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | yes | 77 | yes | no | 1 | 33 min 20.8 s | 495.39 |

## What did not pass

- Run 1: `requirements/reviewOutcome`, `build/reviewOutcome`

How to read and refresh this score: [README](README.md).
