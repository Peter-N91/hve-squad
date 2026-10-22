---
bump: patch
type: Fixed
---

- **Initialization and dependent handoffs preserve actual Scribe provenance.** Fresh initialization explicitly dispatches the Scribe instead of letting the coordinator impersonate it; requirements authors and closing reviewers finish verified handoffs before dependent work. Invalid, stale and integrity failures remain blockers.
- **Native benchmark validation catches Int64 ID exhaustion.** Observational and strict Build briefs both request boundary/data-preservation tests before review. Independent acceptance probes both Int32 and Int64 capacity, rejecting successful writes that corrupt storage while retaining honest failed review outcomes.
