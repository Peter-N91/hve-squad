---
bump: patch
type: Fixed
---

- **Ranked, Economy, and Manual routing no longer treat `sessionModel: auto` as the host model inventory.** Copilot CLI and app plans must pass the exact model enum advertised by the `task` tool; unresolved or unpriced session metadata now yields no automatic suggestion and fails before any `team.md` Model cell is changed. Concrete priced session models retain the documented unverified VS Code-only cost-ceiling fallback.
