---
bump: patch
type: Changed
---

- **Use deterministic ordinary handoffs in every routing mode.** Coordinators invoke the validated writer directly with a one-line quiet status, avoiding a Scribe model call for ordinary persistence. Keep existing history, ledger, decision and state formats, single-writer and completion gates, rollback behavior and cold Scribe operations. Compact the Scribe definition and seed rate cards deterministically regardless of routing mode.
