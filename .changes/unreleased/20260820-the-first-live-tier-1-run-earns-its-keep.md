---
bump: patch
type: Fixed
---

- **The consumption ledger reported costs that did not follow from its own numbers.** A dispatch
  block recorded 57,600 input tokens at $3.00, 230,400 cached at $0.30, 95,200 cache-write at $3.75
  and 15,000 output at $15.00, then set `est_cost_usd` to `4.869` where those figures derive
  `0.82392` — a run priced at almost six times what it recorded. The same run priced one Scribe
  block correctly and another at `0.0603` where its own tokens give `0.03912`, so the cost was being
  computed on some blocks and guessed on others. `est_cost_usd` is now stated as derived rather than
  estimated, with a worked example and a read-back check, because every figure above it — the run
  total, the `state.json` totals, the savings claim, and any autonomous-mode cost ceiling — is
  computed from it (`squad-src/.github/skills/squad/references/scribe-procedure.md`,
  `squad-src/.github/agents/squad/squad-scribe.agent.md`,
  `squad-src/.github/instructions/squad/squad-floor.instructions.md`).
- **The ledger rewrite skipped a block that was sitting on disk.** `history/Squad Scribe.md` carried
  three orchestration blocks and the ledger's `orchestration` row was short by exactly the middle
  one. The rule already said the row is the sum of every recorded block; what was missing was the act
  of re-reading. The rewrite now enumerates the blocks on disk and confirms the count it folded in
  matches, because a ledger built from the two blocks the turn happens to remember still adds up and
  is still wrong (`squad-src/.github/skills/squad/references/scribe-procedure.md`).
- **Consumption blocks were written under headings the ledger cannot read.** One run wrote
  `### Consumption — Research` and `### Consumption — Review` instead of `#### Consumption`, and
  headed history files `# Squad Researcher` instead of `# History: Squad Researcher`. Both shapes
  were described in prose but neither appeared as a template in `entry-schemas.md`, the file an agent
  reads to learn what a history file looks like. That file now carries the literal dispatch entry
  with its consumption block, and the heading rule says what is not legal
  (`squad-src/.github/skills/squad/references/entry-schemas.md`,
  `squad-src/.github/skills/squad/references/scribe-procedure.md`).
- **Init pre-created a history file for every roster member.** A squad seeded five header-only files
  before dispatching anything, which makes an undispatched role indistinguishable from a dispatched
  one and breaks the invariant the whole proof-of-dispatch check rests on. The seed lists said
  `history/` and never said the directory stays empty; they do now
  (`squad-src/.github/skills/squad/references/operating-procedure.md`,
  `squad-src/.github/skills/squad/references/scribe-procedure.md`,
  `squad-src/.github/skills/squad/references/entry-schemas.md`,
  `squad-src/.github/instructions/squad/squad-floor.instructions.md`,
  `squad-src/.github/instructions/squad/squad-state.instructions.md`,
  `squad-src/.github/agents/squad/squad-coordinator.agent.md`,
  `squad-src/.github/agents/squad/squad-scribe.agent.md`).
- **Model attribution was wrong in both directions.** One run recorded `Claude Sonnet 4.6` as
  `agent-pinned` for an agent whose file pins `Claude Sonnet 5`; another recorded `unresolved` for
  the same agent, which the ladder only allows once that file has been opened and found to carry no
  pin. Both failures are the same skipped step, so the ladder now says to open the agent's file
  before writing either value and to copy the pinned name verbatim
  (`squad-src/.github/skills/squad/references/scribe-procedure.md`,
  `squad-src/.github/agents/squad/squad-scribe.agent.md`).
