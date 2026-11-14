---
bump: patch
type: Fixed
---

- **Hook backstops now decode tool arguments and use the consumer workspace.** Fixed escaped and batched action checks, Windows and relative append-only paths, and value-free notification audit placement. Shared parsing ships with exported hooks; malformed pre-action input denies. These remain runtime backstops, not independent authorization or send prevention.
