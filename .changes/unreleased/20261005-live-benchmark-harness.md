---
bump: patch
type: Added
---

- **No reproducible way to show a routing change is faster, cheaper, and no worse.**
  Add an opt-in live benchmark under `tests/tier2/live-benchmark/` that runs a baseline and a candidate squad
  source (default, `routing=ranked`, `routing=economy`) on easy, medium, and hard tasks of one fixture in a
  counterbalanced order, scores each run with hidden tests, planted mutants, doc checks, review and ledger
  verdicts, records seconds, credits, tokens, and per-role model assignment, blind-judges anonymised diffs, and
  writes a median-and-paired-difference report. Its offline self-checks need no model.
