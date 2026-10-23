---
bump: patch
type: Fixed
---

- **The Scribe verifier mispriced long-context and calibrated ledger blocks.** It now prices each block at its own long-context tier, applies calibration once, and refuses malformed long-context rates; the changed `verifierHash` makes earlier benchmark series incompatible until matching new evidence.
