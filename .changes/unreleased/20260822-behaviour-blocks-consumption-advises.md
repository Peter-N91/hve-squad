---
bump: minor
type: Changed
---

- **Consumption findings no longer fail a run; behaviour still does.** Every figure in the ledger is
  an estimate produced by a token-size model with no telemetry behind it, so a run that stopped
  because a `model_tier` read `fast` instead of `default`, or because two dispatches were sized from
  the same numbers, reported an accounting nit at the same severity as a stage that produced no
  artifact. The three `CON` groups — per-dispatch rate resolution, the ledger, and the rates file —
  are now tagged `Consumption`: they still execute and still print, because a check nobody runs
  stops being evidence, but they are reported as advisory and the run's exit code ignores them.
  Everything else — proof of dispatch, the Deliverable Root, block shape, state.json, the roster and
  routing tables — is unchanged and still blocking. `-Strict` restores the old behaviour and is what
  the mutation self-check uses, because a mutation the contract merely mentions is one it does not
  catch (`tests/tier1/Invoke-Tier1Tests.ps1`, `tests/tier1/StateContract.Tests.ps1`).

- **The deliverable reader rejected a correct path for want of backticks.** A live run wrote both its
  artifacts to the right roots and recorded
  `* Deliverable: .copilot-tracking/reviews/2026-08-21-reserve-gap-findings-review.md` — resolvable,
  accurate, and unbackticked. The reader accepted only backticked tokens, so proof of dispatch
  reported a stage that wrote nothing, and the same two files then showed up as unclaimed artifacts:
  one formatting slip, four findings, none of them real. When an entry backticks nothing, a single
  bare path is now accepted provided it still looks like one — a separator and a file extension —
  which keeps `N/A — inline verdict, no artifact written` rejected, since that is the case the rule
  exists for (`tests/tier1/SquadState.psm1`).
