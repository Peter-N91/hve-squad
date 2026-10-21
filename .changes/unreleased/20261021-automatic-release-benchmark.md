---
bump: patch
type: Changed
---

- **Release benchmarks no longer depend on manual local evidence collection.**
  Release Prep now requires an automatic, bounded campaign of three fresh reference
  and three candidate observations using reviewed evaluation code and configurable
  spending limits. Operational failures and regressions block publication; successful
  releases attach sanitized comparison records and a tag-bound identity manifest.
  The explicit manual Release benchmark bypass remains available.
