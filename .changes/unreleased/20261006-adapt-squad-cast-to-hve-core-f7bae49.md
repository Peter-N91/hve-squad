---
bump: minor
type: Changed
---

- **hve-core f7bae49bf68988381a8e13472686c501aea13ebc removed the `prompt-builder`, `prompt-refactor`, and `prompt-analyze` compatibility skills outright**, breaking the `prompt-engineer` role's binding (`squad-src/.github/agents/squad/squad-prompt-engineer.agent.md`). All three had already routed every request to the `hve-builder` skill before their removal, so `Squad Prompt Engineer` now calls `hve-builder` directly for create, improve, refactor, review, and validate modes — no new charter or agent repoint was needed. Updated the Cast Catalog `prompt-engineer` row and the `custom-agent-foundry` blocklist note in `squad-src/.github/skills/squad/references/roster-catalog.md`, and the charter-rationale sentence in `squad-src/.github/instructions/squad/squad-roster.instructions.md`, to name `hve-builder` instead of the retired skills. `apm.yml` now pins `microsoft/hve-core@f7bae49bf68988381a8e13472686c501aea13ebc`.
