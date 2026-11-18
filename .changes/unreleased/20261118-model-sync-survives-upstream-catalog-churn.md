---
bump: patch
type: Fixed
---

- Frozen synthetic routing-policy catalog data so upstream model additions and retirements cannot invalidate unrelated contract fixtures.
- Threaded the selected catalog through scoring and digest validation while preserving the shipped catalog as the runtime default.
