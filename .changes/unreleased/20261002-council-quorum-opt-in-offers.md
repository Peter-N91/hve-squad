---
bump: patch
type: Changed
---

- **A partial roster could reach a council trigger without being offered missing roles.** Init, promotion, expansion, and runtime council gates now offer each missing quorum role, record acceptance or decline through the Scribe, and never run a partial council; unattended runs stop with explicit remediation (`squad-src/.github/instructions/squad/squad-council.instructions.md`).
