---
bump: patch
type: Changed
---

- **Release benchmarks no longer depend on manual local evidence collection.**
  Release Prep now requires an automatic, bounded campaign of three candidate
  observations against the trusted parent's unchanged stored record, with a
  permanent approximate-comparison warning and exact disclosed environment differences.
  Explicit `refresh_reference=true` retains six fresh paired observations, never
  selected automatically. Both modes use reviewed evaluation code and configurable
  spending limits. Operational failures and regressions block publication; successful
  releases attach sanitized comparison records and a tag-bound identity manifest.
  Failed campaigns preserve known spending and explicitly distinguish unknown totals.
  Publication binds the independently requested mode, exact reference bytes,
  current-run series identities and only today's actual spending.
  The prior no-cost stored-record analysis remains separately available.
  The explicit manual Release benchmark bypass remains available.
  Pull requests to `main` additionally run the stored comparison once per PR.
