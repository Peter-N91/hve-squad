---
bump: patch
type: Changed
---

- **The consumption block stored the same fact a dozen times and could store it wrong each
  time.** Every per-dispatch block carried the four token rates and a derived `est_cost_usd` and
  `est_credits` alongside its own token counts — so a rate that belongs to a model was restated once
  per dispatch, and a cost fully determined by its own inputs was stored next to them where the two
  could disagree. A live Copilot CLI run showed both failure modes in one turn: a block carrying
  Claude Sonnet 5's rate fields whose cost had been derived at Claude Sonnet 4.6's rates, and an
  orchestration block whose recorded cost was 2.2× what its own numbers produced.

  The block is now ten fields and records consumption only — `model`, `model_source`, `priced_as`,
  `model_tier`, `internal_turns`, the four token counts, and `basis`. `input_rate`, `cached_rate`,
  `cache_write_rate`, `output_rate`, `est_cost_usd`, and `est_credits` are gone from `history/`
  entirely. Cost is derived once per role in `consumption.md`, from that row's summed token columns
  and the rates of the row `priced_as` names in `consumption-rates.md`, which remains the single
  source of rates. `priced_as` is what carries the pricing decision from the dispatch to the ledger.

  Four of the run's five consumption defect classes cease to exist rather than being caught later:
  there is no rate field to copy wrongly, no rate to contradict a tier, no per-block divide to slip a
  decimal on, and no second copy of a cost to disagree with the first. The arithmetic that remains
  happens once per row in one table a reader can check at a glance. Nothing is lost — every role
  still has its own cost row in `consumption.md`; it simply stops being written twice.

  The Tier 1 contract moves with the shape: per-block assertions for rates, cost, and credits are
  replaced by a per-ledger-row derivation check and a `priced_as` resolution check, and the run-total
  and orchestration-row checks now reconcile the token columns against the blocks rather than
  reconciling a cost against a cost. Mutation self-check 26 → 27
  (`squad-src/.github/instructions/squad/squad-floor.instructions.md`,
  `squad-src/.github/skills/squad/references/`, `tests/tier1/`).
