---
bump: patch
type: Fixed
---

- **Candidate benchmark scores no longer require compatible parent evidence.** Formal Series collects three candidates, while local runs retain descriptive single-sample scores. Real attempts preserve sanitized score records, numeric badges and failure outcomes before optional comparison; missing grades remain unknown rather than invented. Explicit strict comparison and promotion rules remain unchanged (`tests/tier2/live-benchmark/BenchmarkResults.psm1`, `Start-EfficiencyWizard.ps1`, `Invoke-EfficiencyExercise.ps1`).
