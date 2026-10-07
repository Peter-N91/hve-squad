# Hand-off writer A/B: Scribe runs the script vs coordinator runs it (2026-10-05)

Question from review: should `Write-SquadHandoff.ps1` be run by the Squad Scribe (single writer) or by the coordinator? Goal: lower credits at equal quality.

Scope: both arms run the script, which is economy-only (`references/economy-mode.md`). This note does not compare the script with the v0.18.0 hand-written hand-off and makes no speed claim for the script; the five-arm live benchmark (#147) measures economy against `off` and `ranked`.

## Setup

- Copilot CLI 1.0.92-3, `copilot --agent squad-coordinator`, one fresh workspace per run.
- Task: the same small bounded coding task each run (implement a ledger module against hidden tests). Owners `gpt-5.4-mini`, review `claude-haiku-4.5`.
- Arm C: the coordinator runs the script. Arm S: the coordinator dispatches the Scribe with the JSON payload and command line; the Scribe runs the script first, before reading references. Both arms use the hardened script (`priced_as` derived, backticks stripped, `cli-pinned` `passedModel` defaulted).
- Runs interleaved C1, S1, S2, C2, C3, S3.
- Quality: 10 hidden tests, 2 seeded mutants (`release-noop`, `ignore-reserved`) the owner's tests must kill, closing review verdict, `Measure-SquadLedger.ps1 -Check`.

## Results

| Run | Seconds | Credits | Coordinator credits | Scribe credits | Hand-off seconds | Hidden | Mutants | Review | Ledger |
|---|---|---|---|---|---|---|---|---|---|
| C1 | 426 | 85.9 | 61.6 | 0 | 85 | 10/10 | 2/2 | PASS | pass |
| C2 | 269 | 65.2 | 53.8 | 0 | 69 | 10/10 | 2/2 | PASS | pass |
| C3 | 264 | 70.3 | 61.4 | 0 | 49 | 10/10 | 2/2 | PASS | pass |
| S1 | 360 | 75.0 | 52.0 | 5.0 | 107 | 10/10 | 2/2 | PASS | pass |
| S2 | 275 | 56.4 | 43.5 | 2.0 | 77 | 10/10 | 2/2 | PASS | pass |
| S3 | 314 | 59.3 | 43.7 | 3.2 | 66 | 10/10 | 2/2 | PASS | pass |

- Medians: C 269 s / 70.3 credits (coordinator 61.4); S 314 s / 59.3 credits (coordinator 43.7, Scribe 3.2).
- Paired S minus C (by order): time -66, +6, +50 s (median +6 s); credits -10.9, -8.8, -11.0 (about -16%).
- In every S run the coordinator ran the script 0 times and dispatched the Scribe once.

## Earlier attempt

Before hardening, the same comparison favored C (median 339 s / 75.1 credits vs 445 s / 86.9). The Scribe lost time to `priced_as` refusals, a non-JSON payload, and loading about 82 KB of references before running the script. The script now corrects those payload slips with a `WARN`, and the Scribe runs the script before any reference.

## Decision

Under economy, the Scribe runs the script: about 16% fewer credits than the coordinator running it, with no quality difference across six runs. Time showed no consistent difference (median +6 s, pairs ranging -66 to +50 s), so this is not a speed result. Three pairs is a small sample; the credit difference was consistent in all three pairs.
