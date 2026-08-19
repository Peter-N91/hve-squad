---
bump: patch
type: Added
---

- **Nothing checked that the package a consumer installs is internally consistent.** A Tier 0
  conformance suite now asserts against the delivered tree: rosters resolve to delivered agents or
  registered opt-in external ones, claimed skill references exist, agent bodies fit the host cap,
  prompts bind to a real agent or a reserved host mode, the always-on floor ships with
  `applyTo: '**'`, and every squad artifact is declared in `apm.yml`. It invokes no model and reads
  no secret, so it gates pull requests as well as releases
  (`tests/tier0/`, `.github/workflows/tier0-conformance.yml`, `tests/squad-behavior-contract.md`).

- **A pull request branch cannot be installed, so it could not be tested.** The manifest's
  self-references are bare paths, so APM resolves them against the default branch and reports every
  file a branch adds as missing. Tier 0's source mode installs the manifest, then overlays the
  branch's `squad-src/` on top, which is the tree that branch would deliver once merged
  (`tests/tier0/Invoke-Tier0Tests.ps1`).

- **Nothing verified the state a squad run leaves behind.** A Tier 1 state contract now asserts the
  files Init seeds, the shape of `state.json`, dispatch history as proof a stage ran, and the
  consumption ledger's arithmetic — that every cost follows from its tokens and rates, that rates
  match `consumption-rates.md`, and that the run total is the sum of every recorded block rather than
  of the latest turn alone. The runs are nondeterministic; the assertions are not, because they read
  files. A self-check generates a schema-correct fixture and then mutates it once per rule, requiring
  the contract to catch each break — a suite that cannot fail is not evidence
  (`tests/tier1/`).
