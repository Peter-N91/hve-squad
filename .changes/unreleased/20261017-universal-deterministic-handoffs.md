---
bump: patch
type: Changed
---

- **Use deterministic ordinary handoffs in every routing mode.** Coordinators invoke the validated writer directly with a one-line quiet status, avoiding a Scribe model call for ordinary persistence. Keep existing history, ledger, decision and state formats, single-writer and completion gates, rollback behavior and cold Scribe operations. Compact the Scribe definition and seed rate cards deterministically regardless of routing mode.
- **Initialize from one short, confirmed setup brief.** The Scribe helper validates the JSON payload and atomically stages the complete squad tree, rates and setup usage; initialization records Cost Comparison as not applicable. Keep root and history protections, prefer available local tools and require explicit opt-in for external persistence (`squad-scribe.agent.md`, `Initialize-Squad.ps1`).
- **Make source context and AI costs explicit.** Map literal source clauses to existing requirement and acceptance-criteria IDs, preserve unmapped gaps and require genuine stage-appropriate reviews. Script guidance documents purpose, paid trial and judge multipliers, and offline switches (`requirements-quality.md`, `tests/tier2/live-benchmark/README.md`).
