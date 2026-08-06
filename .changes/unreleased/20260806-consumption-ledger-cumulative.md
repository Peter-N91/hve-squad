---
bump: patch
type: Fixed
---

- **The consumption ledger silently dropped every role but the last turn's, and still totalled
  correctly while doing it.** `consumption.md` has always used replace semantics, but nothing ever
  said where its rows come from across turns, so a rewrite could legitimately be built from the
  dispatches in hand. Under the pre-`0.11.11` wide table the Scribe worked around that by appending a
  new section per turn — accidentally correct, structurally non-conforming. The `0.11.11` split into
  two `Role`-aligned tables removed the room for that improvisation, and the ambiguity became visible:
  a nine-turn autopilot run shipped a ledger holding three rows, still headed with the seed run id,
  while every dropped dispatch sat intact in `history/`. Step 7.8 now derives the rows from **every
  consumption block recorded in `history/*.md` for the run**, summed per role, with the
  `orchestration` row summed from the recorded orchestration blocks rather than re-estimated. The file
  replaces; the rows accumulate (`squad-src/.github/agents/squad/squad-scribe.agent.md`,
  `squad-src/.github/instructions/squad/squad-state.instructions.md`,
  `squad-src/.github/skills/squad/SKILL.md`).
- **The ledger's own arithmetic check could not catch this, because a truncated ledger is internally
  consistent.** Verifying that the total equals the sum of the rows just written says nothing about
  the rows that are missing. Step 7.8 gained a completeness check — every agent with a history entry
  for the run has a row, and the ledger's run id names the current run — and Step 7.9 now treats a
  disagreement between the ledger total and `state.json` `currentRun.estCostUsd` as evidence that the
  ledger was left behind (`squad-src/.github/agents/squad/squad-scribe.agent.md`).
- **The coordinator's self-heal only fired on a ledger still at its seed**, so a partially populated
  ledger carrying a plausible non-zero total looked healthy and no turn ever repaired it. The Step 1
  reconcile now checks three conditions and backfills on any of them: seed state, **truncation** (an
  agent with a history entry but no ledger row, or a run id naming a different run), and
  **divergence** between the ledger total and `state.json` `currentRun`
  (`squad-src/.github/agents/squad/squad-coordinator.agent.md`).
- **Per-dispatch consumption blocks were written in whatever shape each turn chose** — one run
  produced JSON blocks, YAML blocks, and a markdown table of `~8,400 (estimated)` values across three
  history files — leaving the aggregate unrebuildable even where the data existed. Step 7.6 now pins
  one container: an `#### Consumption` heading, a fenced `json` block, and bare numbers with no
  separators, approximation marks, or units (`squad-src/.github/agents/squad/squad-scribe.agent.md`,
  `squad-src/.github/instructions/squad/squad-state.instructions.md`).
