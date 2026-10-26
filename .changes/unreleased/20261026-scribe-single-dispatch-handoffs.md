---
bump: patch
type: Fixed
---

- **Ordinary handoffs no longer need a model-generated payload file.** The existing writer accepts actual single-dispatch facts, derives the record envelope and active roles, and retains supplied consumption evidence or clearly estimated fallbacks. The same serialization, freshness, attribution, rollback and receipt checks remain in force; Scribe guidance preserves failure exits and prohibits refreshing stale evidence (`squad-src/.github/skills/squad/scripts/Write-SquadHandoff.ps1`, `squad-src/.github/skills/squad/references/economy-scribe.md`).
- **Coordinator guidance uses the matching fact interface.** Complex metadata and state changes retain full JSON; supplied usage remains authoritative without requiring manually prepared consumption blocks (`squad-src/.github/agents/squad/squad-coordinator.agent.md`).
