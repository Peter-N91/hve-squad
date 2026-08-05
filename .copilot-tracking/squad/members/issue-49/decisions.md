# Squad Decisions (issue-49)

## 2026-08-03 — Intake Readiness Verdict

**Verdict:** Ready. Issue #49 ("Consumption file Tabulation") supplies a concrete, self-contained brief: the `consumption.md` ledger template's table format is hard to read, so fix the tabulation so a consumer can easily see what was consumed. No external inputs or clarification were required; the fix is scoped to the squad's own documentation/instruction templates that define and generate `consumption.md`.

## 2026-08-03 — Root Cause

The `consumption.md` template in `.github/skills/squad/SKILL.md` had grown to a single 15-column table (`Role, Member, Agent, Model, Model Source, Priced As, Tier, Turns, In Tokens, Cached, Cache Wr, Out Tokens, Est. Cost (USD), Est. Credits, Basis`) across several prior consumption-tracking features. A table this wide renders as an unreadable, horizontally-scrolling wall in GitHub-flavored markdown, defeating the ledger's purpose as a "common readme of members, models, and credits." A secondary cosmetic defect (missing cell padding in the `consumption-rates.md` tier-fallback table) was also identified and fixed while in the area.

## 2026-08-03 — Fix Approach

Split the ledger into two narrower tables that both key on `Role`, in roster order, so a row in one lines up with the matching row in the other:

* **Attribution** — Role, Member, Agent, Model, Model Source, Priced As, Tier.
* **Usage & Cost** — Role, Turns, In Tokens, Cached, Cache Wr, Out Tokens, Est. Cost (USD), Est. Credits, Basis (plus the run-total row).

Updated the three files that define the ledger's shape and generation so they stay consistent:

* `squad-src/.github/skills/squad/SKILL.md` — the `consumption.md` template itself, plus the tier-fallback table alignment fix in `consumption-rates.md`.
* `squad-src/.github/agents/squad/squad-scribe.agent.md` — Step 8 now instructs the Scribe to write the two role-aligned tables instead of one wide table.
* `squad-src/.github/instructions/squad/squad-state.instructions.md` — the state-layout description of `consumption.md` now describes the two-table split.

## 2026-08-03 — Risk Gate

No Stop-verdict findings. Change is documentation/instruction-only (markdown templates and agent guidance describing how a runtime-generated file is shaped); no code execution paths, secrets, migrations, or deployments are touched. Risk: Low.

## 2026-08-03 — Acceptance Criteria Status

* "Fix the tabulation so it easily shows the values inside the md file" — **Met.** The consumption ledger template now renders as two compact, role-aligned tables instead of one 15-column table.
