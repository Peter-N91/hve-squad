---
bump: patch
type: Removed
---

- **Foundry deployment had two registered skills claiming the same job.** Remove the narrower `foundry-agent-sync` registration and record it in the External Cast Blocklist because the broader `microsoft-foundry` skill now owns Foundry validation and gated deployment for `deployer` (`squad-src/.github/skills/squad/references/roster-catalog.md`).
