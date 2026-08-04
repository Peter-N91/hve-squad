---
bump: patch
type: Fixed
---

- **The first Release Prep run failed with `Not found: -GitHubOutput`.** The workflow built its arguments as a PowerShell array and splatted it, but array splatting binds *positionally* — so the literal string `-GitHubOutput` landed in the script's first positional parameter, `-ApmFile`, and the existence check threw on a file by that name. The workflow now splats a hashtable, which binds by name (`.github/workflows/release-prep.yml`).
