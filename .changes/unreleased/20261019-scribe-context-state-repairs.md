---
bump: patch
type: Fixed
---

- **Scribe loads manual accounting only when needed, keeping ordinary complete hand-offs smaller** while preserving consumption and full-history ledger checks. Detail lives in a dedicated cold reference rather than the coordinator-loaded ledger guide (`squad-src/.github/agents/squad/squad-scribe.agent.md`, `squad-src/.github/skills/squad/references/scribe-procedure.md`, `squad-src/.github/skills/squad/references/scribe-cold-consumption.md`).
- **Scribe separates deliverable file paths from decision links and prepares state/history directories before creating files**, rejecting malformed paths before partial content writes (`squad-src/.github/skills/squad/references/entry-schemas.md`, `squad-src/.github/skills/squad/references/scribe-cold-init-and-seeding.md`).
