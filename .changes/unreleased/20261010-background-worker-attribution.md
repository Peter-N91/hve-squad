---
bump: patch
type: Fixed
---

- **Background reports preserve selected-worker ownership and truthful model attribution.**
  The Workstream Lead forwards owner/floor context without eagerly admitting unused
  delegates, keeps role cells separate from worker requests, and returns actual
  worker records without double-counting. Lead consumption now accepts a concrete
  host report or unresolved attribution instead of requiring its pin as fact.
  Background remains economy-only; a live background benchmark is still required.
