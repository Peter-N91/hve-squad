---
bump: patch
type: Changed
---

- **Manual benchmark reports no longer require copying commit SHAs.** Blank inputs resolve the selected branch's latest commit and its open PR's parent branch, including upstream fork PRs; branches without a PR use the repository default branch. Independent explicit SHA overrides remain available, and ambiguous parents fail with an actionable error (`.github/workflows/tier2-benchmark.yml`).
