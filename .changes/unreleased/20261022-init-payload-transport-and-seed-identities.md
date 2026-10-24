---
bump: patch
type: Fixed
---

- **Fresh initialization prepares input before dispatch.** The coordinator hands the actual Scribe an existing confirmed JSON payload, so initialization does not depend on a child-only editor or a host-specific tool name. Synchronous results are not treated as background handles, and retries require evidence that no state was published.
- **Fresh ledgers record consistent history identity keys.** The seed uses the same basename keys as the ledger helper, preventing a false partial-paste warning while preserving missing-identity, overwrite, and removal checks.
