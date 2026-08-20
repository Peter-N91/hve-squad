---
bump: patch
type: Fixed
---

- **A history file came back with the read tool's line-number gutter baked into it.** Every line of
  `history/Squad Scribe.md` was written as `1. ---`, `2. description: ...`, `5. # History: Squad
  Scribe` — the content was correct, the file was unparseable. The template had been copied out of a
  numbered read view and written back with the numbering intact, which reads as correct to a human
  and as nothing at all to every later turn. The floor now states that line numbers belong to the
  viewer and are stripped before writing, and Tier 1 fails any state file whose opening lines carry a
  gutter (`squad-src/.github/instructions/squad/squad-floor.instructions.md`,
  `tests/tier1/SquadState.psm1`, `tests/tier1/StateContract.Tests.ps1`,
  `tests/tier1/Assertions.Tests.ps1`).
- **Estimator working values were leaking into the consumption block.** Blocks carried
  `dispatch_class`, `base_context`, `growth_per_turn`, and `output_per_turn` alongside the sixteen
  contractual fields. Those are inputs the Scribe reasons with, not fields it records. The floor now
  says the set is closed at sixteen and names the four that leak.
- **The rate fields were being renamed and zeroed.** One run wrote `input_rate_usd_per_1m` and its
  three siblings, which read as four missing fields; another wrote `cache_write_rate: 0` against a
  rate row that says `3.75`. The floor now fixes the four names, states that the unit lives in the
  contract rather than the field name, and requires all four rates to be copied from the row as the
  row states them even when the matching token count is zero.
- **`priced_as` was omitted or written as a slug.** Blocks priced `claude-sonnet-5` against a table
  whose row is `Claude Sonnet 5`, or dropped the field entirely and left the ledger pricing from
  `model`. The floor now requires the field on every block, copied character-for-character from the
  rate table's `Model (as routed)` cell, equal to `model` when no fallback happened.
- **A factor-of-ten slip survived every other check.** A block summing to `113520` recorded
  `est_cost_usd: 1.17` rather than `0.11352`; the block was otherwise perfectly formed. The floor now
  calls out the single division by `1e6` and asks for a digit comparison before the block is
  appended.
- **The orchestration row kept appearing without a block behind it.** One ledger carried a zero
  `orchestration` row, another a `0.0779` row, and neither had a single `#### Consumption —
  Orchestration` block in `history/`. The floor now says the Scribe writes that block on every turn
  it writes state, Init included, and that no block means no row.
- **The literal history-file preamble is now in the floor.** Files were still headed `# Squad
  Researcher` under invented descriptions like `"Dispatch history for Squad Researcher role"`,
  because the heading rule was stated while the template it describes lived two files away. Both now
  sit together in the one file that loads on every host.
