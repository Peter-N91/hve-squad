---
bump: patch
type: Security
---

**Hardened GitHub Actions workflows** against script injection, excessive permissions, and unpinned tooling.

* Refactored squad-watch.yml to separate untrusted content processing from privileged repository mutations.
* Restricted the Copilot interpretation job to read-only permissions and moved patch application, PR creation, review posting, and escalation into independently scoped jobs.
* Replaced the broad sync token with a dedicated COPILOT_GITHUB_TOKEN for Copilot CLI authentication.
* Passed dynamic workflow values through environment variables instead of interpolating expressions directly into shell and PowerShell scripts.
* Pinned the Copilot CLI to 1.0.78 and zizmor to 1.29.0 for reproducible execution.
* Added short-lived artifact handoffs for generated patches and PR review content.
* Preserved automated draft PR creation, no-change notifications, unauthorized-trigger escalation, and failure reporting under the new privilege-separated design.
