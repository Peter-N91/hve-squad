---
bump: patch
type: Fixed
---

- **Generated connector runners now honor the request deadline's UTC offset.** Invalid or expired requests return a failed result before the endpoint starts.
