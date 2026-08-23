---
bump: patch
type: Changed
---

- **The release gate is Tier 0 only, and now says so.** The behaviour contract described Tier 1 as
  the release gate and told the reader the suite would be wired in "once it is green twice in a row".
  It never was, so a reader comparing `release.yml` against the contract found a gate the workflow
  does not implement — and `v0.16.0` was cut on Tier 0 alone with nothing recording why.

  Tier 1 and Tier 2 are operator-invoked by design. The contract now carries the reasoning: they cost
  Copilot requests and about an hour per cut; two of the three dispatched runs before `0.16.0` failed
  because the contract asserted something the source did not say, so a gate on that record blocks
  releases for test defects; and the defect `0.16.0` actually shipped sits behind `mode=autopilot`,
  which no scenario exercises, so the gate could not have caught it. The conditions that would change
  the decision are written down next to it (`tests/squad-behavior-contract.md`).
