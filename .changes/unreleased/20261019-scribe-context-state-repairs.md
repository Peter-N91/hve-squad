---
bump: patch
type: Fixed
---

- **Scribe loads manual accounting only when needed, keeping ordinary complete hand-offs smaller** while preserving consumption and full-history ledger checks. Detail lives in a dedicated cold reference rather than the coordinator-loaded ledger guide (`squad-src/.github/agents/squad/squad-scribe.agent.md`, `squad-src/.github/skills/squad/references/scribe-procedure.md`, `squad-src/.github/skills/squad/references/scribe-cold-consumption.md`).
- **Scribe separates deliverable file paths from decision links and prepares state/history directories before creating files**, rejecting malformed paths before partial content writes (`squad-src/.github/skills/squad/references/entry-schemas.md`, `squad-src/.github/skills/squad/references/scribe-cold-init-and-seeding.md`).
- **Native efficiency runs load conditional squad rules on demand without dropping their full text or the unconditional floor**, avoiding oversized instruction injection on state reads. Saved controls distinguish the host and preparation code (`tests/lib/SquadInstall.psm1`, `tests/tier2/live-benchmark/EfficiencyBenchmark.psm1`).
- **Efficiency stages share the remaining run allowance instead of hidden lower stage ceilings**, while retaining the 300-request total, independent judge reservation, 45-minute watchdog and credit ceilings (`tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1`).
- **Requirements readiness honors the closing review instead of just reviewer-file presence**, accepts standard verdict headings, and resolves legacy unquoted size annotations without weakening file or dispatch checks. The Scribe payload example now keeps size metadata out of literal Deliverable paths (`tests/tier2/live-benchmark/EfficiencyBenchmark.psm1`, `squad-src/.github/skills/squad/references/scribe-payload-template.md`).
