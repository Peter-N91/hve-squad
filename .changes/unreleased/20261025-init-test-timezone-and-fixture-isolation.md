---
bump: patch
type: Fixed
---

- **Init conformance tests no longer depend on the host timezone or earlier test cases.** Preserve parsed timestamp instants and give re-initialization, ledger-tampering, and first-work checks their own initialized repositories without changing production freshness rules or weakening assertions (`tests/tier0/ScribeInitConvergence.Tests.ps1`).
