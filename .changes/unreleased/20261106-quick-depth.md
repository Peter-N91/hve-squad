---
bump: minor
type: Added
---

- **`depth=quick` is now an independent, trusted per-turn workflow control.** Omission is always `standard`; quick requires prompt or federation provenance, computes its stage policy before model validation and dependency waves, removes only explicitly skipped optional work, records absent gates as required follow-up or external evaluation, keeps every gate at standard depth, and adds concurrency only for a bounded request or a verified `deliverable-fan-out` Lead plan. `routing=` continues to choose models independently. The live benchmark adds a counterbalanced candidate `depth=quick` arm against candidate standard depth, its frozen roster now uses the current `Agent Name (Primary)` header, and the full efficiency scenario supports paired standard-versus-quick runs with `-CompareDepth`.
