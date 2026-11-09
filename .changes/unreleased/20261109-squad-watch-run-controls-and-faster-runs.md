---
bump: patch
type: Changed
---

- **Watch run controls:** the Watch workflow and consumer template gain optional depth (default standard), routing (default off) and economy consent inputs, settable as committed defaults or per manual run; event text still cannot change them.
- **Faster, publishable runs:** Watch no longer runs the full Tier 0 suite, requires specialists from a canonical profile, and pins Copilot CLI 1.0.106.
- **Fixed Watch profile:** a new `profile` run control (default `default`, or `auto` or any catalog profile) makes Watch use exactly that profile with no packs and no added roles, which is what the publication gate accepts.
