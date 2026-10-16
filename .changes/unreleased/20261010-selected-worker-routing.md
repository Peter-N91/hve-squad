---
bump: patch
type: Changed
---

- **Delegated model ownership is explicit without casting workers as roles.**
  The existing resolver admits only a selected delegate, preserves genuine roster
  policy and worker pins, and ranks unpinned workers at their owner's real floor
  rather than inheriting an economy discount. Cold-loaded worker instructions use
  the existing history/consumption schema, keep requests distinct from host reports,
  and leave ordinary role reports and economy consent unchanged. This closes a
  compatibility contract gap; it does not assert an upstream MCP startup bug.
