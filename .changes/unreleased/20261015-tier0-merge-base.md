---
bump: patch
type: Fixed
---

- **Retrying Tier 0 after `main` advanced could fail every hot-file budget case.**
  The retry checked out a refreshed pull-request merge commit but retained the
  original event's stale base SHA. The budget ratchet now uses the checked-out
  merge commit's first parent, preserving inherited debt without relaxing either
  per-file or aggregate performance limits.
