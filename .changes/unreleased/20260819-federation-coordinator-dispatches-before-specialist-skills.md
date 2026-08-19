---
bump: patch
type: Fixed
---

- **The specialist-skill rule bound the Squad Coordinator but not the Squad Federation Coordinator.**
  The federation coordinator classifies too, so it could load a specialist skill to decide which
  sub-squad owns a request — the same defect, one layer up. Meta-routing is now metadata-only, and the
  rule moved into the always-on `squad-floor.instructions.md` so it binds every orchestrator rather
  than being restated per agent (`squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`,
  `squad-src/.github/instructions/squad/squad-floor.instructions.md`).
