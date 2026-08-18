---
bump: patch
type: Changed
---

- **SQL migration guidance duplicated an upstream questionnaire and could drift from its policy.** `Squad SQL Migration Advisor` now prefers the `recommend-migration-path` and `generate-migration-prerequisite-plan` skills installed through the upstream `sql-migration-advisor` plugin, preserves the bundled advisor as a recommendation-only compatibility fallback, and routes prerequisite/readiness requests explicitly (`squad-src/.github/agents/squad/squad-sql-migration-advisor.agent.md`, `squad-src/.github/skills/sql-migration-advisor/SKILL.md`, and the squad roster and routing instructions).
