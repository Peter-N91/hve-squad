---
bump: minor
type: Added
---

- **The squad ran in VS Code and had no entry point anywhere else.** `/squad-document`,
  `/squad-governance-report`, and `/squad-learn` existed only as prompt files, which the Copilot CLI
  and the Copilot app never read. All three now ship as agents selectable on any host, with their
  prompts reduced to thin wrappers so VS Code keeps its slash-command ergonomics
  (`squad-src/.github/agents/squad/`).
- **A dispatched agent could run without the squad's non-negotiable rules.** Every squad instruction
  file is gated on `**/.copilot-tracking/squad/**`, so an agent that had not yet touched squad state
  ran without them. A new `squad-floor.instructions.md` is scoped `**` and carries dispatch
  discipline, the single-writer Scribe rule, the state paths, and proof of dispatch on every turn
  (`squad-src/.github/instructions/squad/squad-floor.instructions.md`).
- **Consumers discovered host limits by hitting them.** The usage guide now documents per-host
  invocation, the agent-name convention, the four remaining host limits, and why a fixed session model
  beats `auto` when cost attribution matters (`docs/usage.html`).
