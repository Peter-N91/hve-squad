---
bump: patch
type: Fixed
---

- **The Watch workflow comments said the CLI ignores agent `model:` pins.** Corrected to the behaviour observed on Copilot CLI 1.0.92: pins are honored for subagents and `SQUAD_MODEL` sets the session model for the coordinator and unpinned agents (`.github/workflows/squad-watch.yml`, `squad-src/.github/skills/squad/squad-watch.workflow.yml`).
