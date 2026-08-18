---
bump: patch
type: Fixed
---

- **The Squad Coordinator could activate a specialist skill before dispatching its owning agent.**
  Dispatch discipline now keeps classification metadata-only and leaves project, plugin, and bundled
  specialist skills inactive until the resolved specialist runs
  (`squad-src/.github/agents/squad/squad-coordinator.agent.md`).
