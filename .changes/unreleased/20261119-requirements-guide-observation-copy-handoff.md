---
bump: patch
type: Fixed
---

- **The requirements guide told authors to list a draft observation copy as the handoff deliverable, which the completion check rejects.** The author now names the copies in its return, and the handoff `deliverable` stays the draft under its roster Deliverable Root, because `Test-SquadTurnCompletion.ps1` fails a deliverable outside that root (`squad-src/.github/skills/squad/references/requirements-quality.md`).
