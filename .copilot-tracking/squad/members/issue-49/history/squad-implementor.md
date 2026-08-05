# History: Squad Implementor (issue-49)

## Dispatch 1 — 2026-08-03

**Request:** Fix the broken table format in the `consumption.md` ledger (and its generating templates/instructions) so a consumer can easily read what a squad run consumed, per issue #49.

**Findings:** The `consumption.md` template in `squad-src/.github/skills/squad/SKILL.md` had grown to one 15-column table across several prior consumption-tracking features (`Role, Member, Agent, Model, Model Source, Priced As, Tier, Turns, In Tokens, Cached, Cache Wr, Out Tokens, Est. Cost (USD), Est. Credits, Basis`). Verified column counts were structurally valid markdown (no mismatched pipe counts), so the defect is readability/UX, not markdown syntax: a table this wide is unreadable at a glance and forces horizontal scrolling on GitHub. A secondary cosmetic misalignment (missing cell padding) was also found in the `consumption-rates.md` tier-fallback table.

**Outcome:** Split the ledger template into two role-aligned tables — **Attribution** (Role, Member, Agent, Model, Model Source, Priced As, Tier) and **Usage & Cost** (Role, Turns, In Tokens, Cached, Cache Wr, Out Tokens, Est. Cost (USD), Est. Credits, Basis) — both ordered identically so a row in one lines up with the same row in the other. Updated three files to keep the ledger's definition and generation consistent:

* `squad-src/.github/skills/squad/SKILL.md` — the `consumption.md` template (two tables) and the `consumption-rates.md` tier-fallback table alignment fix.
* `squad-src/.github/agents/squad/squad-scribe.agent.md` — Step 8 rewritten to instruct the Scribe to write the two tables.
* `squad-src/.github/instructions/squad/squad-state.instructions.md` — the `consumption.md` state-layout description updated to describe the split.

Verified column counts of every row in both new tables (9 columns in Usage & Cost, 7 in Attribution) programmatically to confirm valid, evenly-shaped markdown.

<!-- consumption:begin -->
model: claude-sonnet-5
model_source: session-inherited
priced_as: claude-sonnet-5
model_tier: default
internal_turns: 8
input_tokens: 100000
cached_tokens: 400000
cache_write_tokens: 60000
output_tokens: 12000
input_rate: 2.00
cached_rate: 0.20
cache_write_rate: 2.50
output_rate: 10.00
est_cost_usd: 0.5500
est_credits: 55.00
basis: estimated
<!-- consumption:end -->
