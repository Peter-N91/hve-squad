---
bump: patch
type: Changed
---

- **Long-running Squad runs exposed only the current step.** The coordinator now presents a stable outcome plan through a host-native task list when available and a matching in-chat `## Plan` on every host (`squad-src/.github/agents/squad/squad-coordinator.agent.md`, `squad-src/.github/prompts/squad/squad.prompt.md`, `squad-src/.github/skills/squad/references/operating-procedure.md`).
