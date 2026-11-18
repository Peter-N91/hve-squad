---
bump: patch
type: Fixed
---

- **Squad Studio could start a Scribe agent for ordinary handoffs.** Studio launches now direct the coordinator to the validated handoff script and reserve Scribe for unsupported or cold operations (`squad-src/.github/skills/squad/extensions/hve-squad-studio/lib/catalog.mjs`).
