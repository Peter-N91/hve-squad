---
bump: patch
type: Fixed
---

- **Ranked, Economy, and Manual routing no longer treat `sessionModel: auto` as the host model inventory.** Copilot CLI and app plans must pass the exact model enum advertised by the `task` tool; unresolved or unpriced session metadata now yields no automatic suggestion and fails before any `team.md` Model cell is changed. Concrete priced session models retain the documented unverified VS Code-only cost-ceiling fallback.
- **Resolved routes now control the native dispatch.** The coordinator copies each non-empty planned model into the `task` or `runSubagent` `model` argument, so an agent's frontmatter pin can no longer silently replace the Ranked, Economy, or Manual selection.
- **Exact native consumption now accumulates across Copilot sessions.** The ledger writer keeps one human-readable `consumption.md` and a lazy, closed-schema `consumption-sessions.json` journal that upserts each native session, rejects duplicate accounting identities or history-prefix drift, and commits with `state.json` and the ledger as one transaction. Existing single-session exact ledgers migrate without resetting historical totals.
