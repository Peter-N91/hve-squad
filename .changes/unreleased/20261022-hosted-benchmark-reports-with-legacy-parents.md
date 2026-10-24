---
bump: patch
type: Fixed
---

- **Hosted benchmark reports hid current incomplete observations behind an older parent comparator.** A fixed reviewed report-only engine now renders independently validated campaign data while retaining original strict artifacts and nonzero verdicts. Candidate tooling is never executed; unavailable evidence cannot pass the final gate (`.github/workflows/tier2-recorded-benchmark.yml`).
