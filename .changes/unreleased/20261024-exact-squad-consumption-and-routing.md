---
bump: patch
type: Changed
---

- Use complete deduplicated host usage records as authoritative consumed spend and per-role accounting: join event agent identities, roll nested workers into their owning role, publish exact uncached/cache-read/cache-write/output tokens and native credits, and calculate the without-Squad comparison from the same exact request traffic. Estimates remain only as a fallback and future reservation, recorded as `host-exact+estimated-reservation` for capped work. Also reserve only the actual next dispatch wave for ceilings, defer model scoring from discovery to the real dispatch plan, and persist active routing transitions through a hash-bound PowerShell transaction without a Scribe dispatch.
