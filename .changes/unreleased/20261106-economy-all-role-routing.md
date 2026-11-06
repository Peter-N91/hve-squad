---
bump: minor
type: Changed
---

- **Economy routing now applies one cost-first rule to every routed role.** Review, council, intake, live-resource, fallback-class, and unattended roles no longer stay on Ranked. Economy prefers the class qualification, then uses the cheapest known-price model inside the role floor under `floor-only-known-price-v1` when none qualifies; no priced floor candidate stops dispatch. Existing consent without `Scope: all-roles` must be upgraded before dispatch instead of producing a mixed Economy/Ranked run.
