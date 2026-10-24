---
bump: patch
type: Fixed
---

- **Initialization could fill the no-ceiling Cost Preflight record with an Init or ledger id.** The Scribe now copies the exact `not-requested` object from `entry-schemas.md` at Init, keeping `runId` and `roundId` empty (`squad-src/.github/skills/squad/references/scribe-cold-init-and-seeding.md`).
