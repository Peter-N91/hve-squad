---
bump: patch
type: Changed
---

- **Council membership was treated as a fixed four-role quorum.** Init, promotion, expansion, and runtime gates now propose a task-fit council, let the user accept, adjust, or decline its membership, and record the decision through the Scribe; unattended runs require an already accepted matching membership or escalate with remediation (`squad-src/.github/instructions/squad/squad-council.instructions.md`).
