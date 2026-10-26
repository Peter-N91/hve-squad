# Benchmark score

Measured: 2026-10-26 16:26 UTC, commit `3bf61f0`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.104-3. Run copilot update to check for up`, 1 run.

| Measure | Result |
| --- | --- |
| Document quality (median, out of 100) | 82 |
| Functional (runs passing) | 1/1 |
| Workflow (runs passing) | 0/1 |
| Critical/high findings | 0 (0 per run) |
| Average time per run | 21 min 48.8 s |
| Average credits per run | 496.36 |
| Runs that produced a score | 1/1 |

## Observed activity

| Observed activity | Earlier run | Latest run |
| --- | --- | --- |
| Scribe dispatches | 1 | 1 |
| Scribe model requests | 2 | 3 |
| Time inside Scribe dispatches | 0 min 13.1 s | 0 min 11.5 s |
| Scribe credits | 0.26 | 0.38 |
| Coordinator model requests | 41 | 46 |
| BRD/PRD author model requests | 39 | 40 |

Activity is averaged per scored run; a metric is unavailable if any scored run lacks it. Dispatch time is summed per Scribe dispatch, not elapsed benchmark time. Requests count unique usage records; credits cover those records, excluding separate compaction charges and the judge.

Earlier run: 2026-10-26 14:20 UTC, commit `9bd6c88`, model `claude-sonnet-5.5`, Copilot CLI `GitHub Copilot CLI 1.0.103. Run copilot update to check for upda`, 1 run.

## Document quality by dimension (median, out of 20)

| Dimension | Score |
| --- | --- |
| Business clarity | 16 |
| Scope fidelity | 15 |
| Acceptance criteria | 17 |
| Traceability | 18 |
| Risks and decisions | 16 |

## Runs

| Run | Scored | Quality | Functional | Workflow | Critical/high | Time | Credits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | yes | 82 | yes | no | 0 | 21 min 48.8 s | 496.36 |

## What did not pass

- Run 1: `requirements/reviewOutcome`

How to read and refresh this score: [README](README.md).
