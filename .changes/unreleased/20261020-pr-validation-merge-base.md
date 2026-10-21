---
bump: patch
type: Fixed
---

- **PR validation no longer attributes upstream release or dependency changes to a pull request after its base advances.** Release-state, dependency-pin and fragment checks compare against the checked-out merge commit's first parent rather than the stale event base (`.github/workflows/pr-validation.yml`).
