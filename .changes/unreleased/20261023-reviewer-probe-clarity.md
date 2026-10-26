---
bump: patch
type: Fixed
---

- **Closing implementation-review briefs now separate authorized scratch probes from review-only durable output.** Required runtime probes may write to an explicitly authorized scratch directory without breaking the review-only output rule.
- **Scribe setup references fit their existing prompt budgets.** Compact redundant descriptions without changing validation, permissions or size limits.
