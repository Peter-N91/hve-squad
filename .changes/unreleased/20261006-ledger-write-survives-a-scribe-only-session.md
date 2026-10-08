---
bump: patch
type: Fixed
---

- **`Measure-SquadLedger.ps1 -Write -SessionLog auto` no longer throws when only the Scribe has completed.** Scribe rows are excluded from role totals, so the observed-usage sum ran over an empty collection and `.Sum` threw under `Set-StrictMode` before the null guard, rolling back the hand-off. Sums are now empty-safe, the baseline model is taken with `Select-Object -First 1`, and a session log that cannot be parsed omits the optional observed-usage section with a warning instead of failing the ledger write. Four regression tests in `tests/tier1/LedgerCalculator.Tests.ps1` cover a Scribe-only session, billed usage with no completed dispatch, every live cut point, and malformed session data.
