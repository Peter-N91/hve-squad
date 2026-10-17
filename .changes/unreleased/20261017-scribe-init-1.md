---
bump: patch
type: Changed
---

<!-- markdownlint-disable-file MD041 -->

- Fresh Scribe initialization now reads one short brief and runs a deterministic helper from confirmed JSON. The helper stages and validates the full state tree, seeds rates through the existing seeder, records supplied setup usage, and refuses existing or unsafe roots without resetting history. The ledger owns initialization's not-applicable Cost Comparison; explicit roster refresh and other cold operations keep their full validation path.
