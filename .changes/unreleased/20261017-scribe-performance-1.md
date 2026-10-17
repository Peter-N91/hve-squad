---
bump: minor
type: Changed
---

- Ordinary squad-state handoffs incurred avoidable Scribe model calls, and rate-card setup varied by routing mode. Coordinators now use the validated writer for ordinary handoffs in every routing mode, while the Scribe handles cold operations. Rate cards are seeded deterministically, and the Scribe guidance, workflow documentation, and regression tests now reflect these responsibilities while preserving existing state formats and safety checks.
