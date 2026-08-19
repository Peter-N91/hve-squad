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

- **That workaround still aborted on the branches most worth testing.** A branch that *adds* a
  squad artifact makes `apm install` exit non-zero, and source mode threw before a single case
  ran — so any additive branch reported nothing rather than a result. Source mode now tolerates
  an install failure only when every unresolved reference names a file present in the working
  copy, which is precisely the file the overlay is about to supply. A failure naming anything
  else still aborts (`tests/lib/SquadInstall.psm1`).

- **Nothing verified the state a squad run leaves behind.** A Tier 1 state contract now asserts the
  files Init seeds, the shape of `state.json`, dispatch history as proof a stage ran, and the
  consumption ledger's arithmetic — that every cost follows from its tokens and rates, that rates
  match `consumption-rates.md`, and that the run total is the sum of every recorded block rather than
  of the latest turn alone. The runs are nondeterministic; the assertions are not, because they read
  files. A self-check generates a schema-correct fixture and then mutates it once per rule, requiring
  the contract to catch each break — a suite that cannot fail is not evidence
  (`tests/tier1/`).

- **Nothing exercised a real run.** A Tier 1 live harness now provisions a scratch repository
  per scenario, installs the package into it, copies a small fixture over it, and drives real
  headless turns before the state contract reads what was left behind. The model is pinned
  because a headless run ignores the `model:` frontmatter the editor honors, every turn is
  bounded, and a failed scenario is retried once with both attempts kept so a flake is
  separable from a regression (`tests/tier1/Invoke-Tier1LiveRun.ps1`,
  `tests/tier1/scenarios/`, `.github/workflows/tier1-behavior.yml`).

- **A squad can write a valid tree while quietly routing to a different cast.** Tier 2 scores
  each run against a golden baseline on four facts read from disk: the roles dispatched, the
  deliverable roots and types produced, the gate verdicts recorded, and — only when asked —
  whether the answer is materially equivalent. Deliverables compare as root and type rather
  than filename, because the topic slug is the model's to choose while the root is the
  roster's promise. Advisory until the noise floor across repeat runs is measured
  (`tests/tier2/`, `.github/workflows/tier2-semantic.yml`).

- **A release could be cut over a broken package.** The release workflow now runs Tier 0 twice:
  once against the ref being released, and once against the tag it just pushed. Only the second
  can assert that the tag pinned its own self-references, because that check needs a ref to
  install — and a tag that freezes the dependency list but not its contents is the defect that
  made earlier tags non-reproducible. A failure there leaves a tag but no Release
  (`.github/workflows/release.yml`).

- **The state contract had no live run to assert against.** A Tier 1 harness now provisions a
  scratch repository per scenario, installs the package into it, copies a tiny fixture on top, and
  drives real headless Copilot CLI turns before handing the resulting tree to the state contract.
  Scenarios cover Init, an ordinary routing turn, and promotion from a single squad to a federation
  with a cross-sub-squad handoff. The model is pinned because a headless run does not read the
  `model:` frontmatter the editor honors and results are otherwise incomparable; every turn carries a
  timeout, and a failed scenario is retried once with both attempts kept, so a flake is
  distinguishable from a regression
  (`tests/tier1/Invoke-Tier1LiveRun.ps1`, `tests/tier1/scenarios/`, `tests/fixtures/`,
  `.github/workflows/tier1-behavior.yml`).

- **A squad can write a valid tree while quietly routing to a different cast.** Neither Tier 0 nor
  Tier 1 can see that. Tier 2 now reduces each run to four deterministic facts — which roles ran,
  which deliverable types landed at which roots, which gates fired with which verdict, and what the
  run answered — and scores them against a golden baseline captured from a known-good release. Only
  the answer is prose, and it is judged only when asked for. The tier is advisory until the noise
  floor across repeat runs is measured, because a gate that blocks on unmeasured variance gets turned
  off. Its comparator carries its own drift controls
  (`tests/tier2/`, `.github/workflows/tier2-semantic.yml`).
