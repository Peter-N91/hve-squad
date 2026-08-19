---
bump: patch
type: Added
---

- **Nothing checked that the package a consumer installs is internally consistent.** A Tier 0
  conformance suite now installs a published ref into a scratch directory and asserts against the
  delivered tree: rosters resolve to delivered agents or registered opt-in external ones, claimed
  skill references exist, agent bodies fit the host cap, prompts bind to a real agent or a reserved
  host mode, and the always-on floor ships with `applyTo: '**'`. It invokes no model and needs no
  secrets, so it can gate every pull request as well as a release
  (`tests/tier0/`, `tests/squad-behavior-contract.md`).
