---
bump: patch
type: Changed
---

- **The Tier 1 self-check no longer outgrows its CI job.** Almost every case starts child `pwsh` processes, so one sequential run took 15 to 19 minutes against a 20 minute limit and timed out as soon as the ledger cases grew. `Invoke-Tier1Tests.ps1 -SelfCheck -Parallel <n>` now discovers every case, groups the work into bundles (a large ledger Describe is split by Context, and a file that shares one results file stays whole), and runs the bundles largest first on `n` worker processes, each taking the next as it finishes, so no estimate of how long a case takes has to be right. The runner fails unless every discovered case ran exactly once, so scheduling changes and coverage does not. CI runs it with `-Parallel 4`; the default is still one process. See `tests/tier1/Tier1Parallel.psm1`, `tests/tier1/Invoke-Tier1Tests.ps1`, and `.github/workflows/tier1-behavior.yml`.
