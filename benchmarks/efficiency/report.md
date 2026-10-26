# Benchmark score

Measured: 2026-10-21 10:23 UTC, commit `59880d5`, model `claude-sonnet-5.5`, Copilot CLI `1.0.101-0`, 3 runs.

| Measure | Result |
| --- | --- |
| Document quality (median, out of 100) | 83 |
| Functional (runs passing) | 3/3 |
| Workflow (runs passing) | 0/3 |
| Critical/high findings | 2 (0.67 per run) |
| Average time per run | 19 min 48.5 s |
| Average credits per run | 287.2 |
| Runs that produced a score | 3/3 |

## Document quality by dimension (median, out of 20)

| Dimension | Score |
| --- | --- |
| Business clarity | 18 |
| Scope fidelity | 17 |
| Acceptance criteria | 16 |
| Traceability | 17 |
| Risks and decisions | 15 |

## Runs

| Run | Scored | Quality | Functional | Workflow | Critical/high | Time | Credits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | yes | 83 | yes | no | 1 | 19 min 20 s | 300.43 |
| 2 | yes | 83 | yes | no | 0 | 21 min 11.6 s | 300.5 |
| 3 | yes | 82 | yes | no | 1 | 18 min 54 s | 260.66 |

## What did not pass

- Run 1: `build/stateVerifier`, `requirements/BRD Quality Reviewer`, `requirements/PRD Quality Reviewer`, `requirements/reviewOutcome`, `requirements/stateVerifier`
- Run 2: `requirements/BRD Quality Reviewer`, `requirements/PRD Quality Reviewer`, `requirements/reviewOutcome`
- Run 3: `build/developer`, `build/lead`, `build/researcher`, `build/reviewOutcome`, `build/tester`, `requirements/BRD Quality Reviewer`, `requirements/PRD Quality Reviewer`, `requirements/reviewOutcome`, `requirements/tester`

How to read and refresh this score: [README](README.md).
