---
bump: patch
type: Changed
---

- **Long-running Squad runs exposed only the current step.** The coordinator now presents a stable outcome plan through a host-native task list when available and a matching in-chat `## Plan` on every host. The contract stays inline in the measured `operating-procedure.md`, after classification and before work dispatch; the prompt delegates through its existing per-turn requirement without a second plan or state write. Shared-learning rules are deduplicated within the same measured procedure, preserving read order, read-only playbooks, and Scribe-owned local memory. No extra progress reference read, budget exclusion, or threshold increase is needed.
