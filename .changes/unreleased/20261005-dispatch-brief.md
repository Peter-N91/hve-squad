---
bump: minor
type: Added
---

- **Dispatch brief under `routing=economy` (economy-only).** New read-only `scripts/Get-SquadDispatchBrief.ps1` prints in one call, under the Copilot CLI's 20,480-byte inline output limit, what an economy coordinator otherwise finds out turn by turn: next hand-off `turn`, federation, cost-ceiling, ledger and routing status, the roster read from `team.md` by column header (agent and Alternates with dispatchability for the Step 1b precheck, pin, `Model` cell, rate row, deliverable root), ready consumption objects, the Scribe's `Write-SquadHandoff.ps1` command line, and the *Bounded Lane*, *Plan-Driven Parallelism*, and *Scripted Writes* sections of `references/economy-mode.md` verbatim. It picks no model and refuses with exit 7, printing nothing, unless `team.md` records `Model routing: economy`. Earlier paired live runs (3 each, Sonnet 5 coordinator) moved the median from 369 s / 101.2 credits to 307 s / 67.3 credits, but those runs also gave owners a cheaper model and predate the economy-only rework; the five-arm benchmark (#147) is the measurement of record.
