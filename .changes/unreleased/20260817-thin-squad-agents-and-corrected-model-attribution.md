---
bump: patch
type: Changed
---

- **Three squad agents exceeded the 30,000-character host limit and fifteen declared `model:` as a
  YAML array the Copilot CLI rejects outright.** An over-cap profile is why a selected coordinator
  could answer as a plain model, and a `model:` array makes an agent fail to load entirely. The
  coordinator, federation coordinator, and Scribe now bind to the `squad` skill through a named Skill
  Reference Contract and fit the cap; `squad` SKILL.md was split into nine topic reference files so
  each agent loads only its own role's procedure; and every `model:` is now a single string
  (`squad-src/.github/agents/squad/`, `squad-src/.github/skills/squad/references/`).
- **The Model Attribution ladder described host behavior that measurement contradicted.** A valid
  frontmatter pin beats `--model`, an unentitled pin is substituted silently on the dispatch path with
  no warning, and `auto` overrides a subagent's pin entirely. The ladder now leads with the
  host-reported dispatch model, so the consumption ledger records what actually ran rather than what
  was requested (`squad-src/.github/instructions/squad/squad-state.instructions.md`).
