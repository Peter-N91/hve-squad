---
bump: patch
type: Fixed
---

- **A release now has to pass the behavioural suite before it can tag.** `v0.16.0` was cut on Tier 0
  alone, because Tier 1 was left unwired while it was still unproven — so the only tier that can see
  a squad that stops routing, stops dispatching, or stops accounting for what it did had no say in
  whether the release shipped. `release.yml` gains a `preflight` job that resolves the tag before
  anything is paid for, and a `behavior` job that runs Tier 1 in source mode against the ref about to
  be tagged. The `release` job depends on it, so a red suite means no tag — which is the only point
  in the cut where a failure is still free to act on. A `verify` input clears the gate for a re-cut
  of a ref already verified, and a version whose tag already exists never reaches the paid job.

- **Tier 2 now scores every release instead of only itself.** It rides along inside the Tier 1 call
  and stays advisory: until the noise floor across repeat runs on one ref is measured, a low score is
  not evidence of a regression. It reports `unbaselined` and scores nothing until
  `tests/tier2/baselines/<scenario>.baseline.json` is captured from a known-good release and
  committed, which is the state every release up to and including `v0.16.0` shipped in.
