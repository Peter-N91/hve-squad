---
bump: patch
type: Changed
---

- **Benchmark reports lead with readable results and performance summaries**, using grouped numbers, minutes and seconds, plain-language findings and checks needing attention while retaining exact measurements and provenance in expandable sections.
- **The benchmark badge includes average measured time per trial**, alongside quality and acceptance. The generator uses the arithmetic mean of workflow-plus-judge timing; comparison gates retain medians (`tests/tier2/live-benchmark/BenchmarkResults.psm1`).
- **The README identifies the primary evaluation and telemetry sources behind the methodology review**, connects them to concrete design choices and separates implemented screening from unestablished calibration and statistical claims (`README.md`).
