---
description: "Unconditional squad floor: state paths and write semantics, the single-writer Scribe rule, dispatch discipline, proof of dispatch and the binding Deliverable Root, the literal consumption block, cost derived only in the ledger, and the Research → Plan → Implement → Review spine — the rules that must hold before any file is in play"
applyTo: '**'
---

# Squad Agent Floor

This file carries only the squad rules that must hold before any file is in play. It is scoped to `**` deliberately: every other squad instruction file is gated on `**/.copilot-tracking/squad/**`, so a freshly dispatched agent that has not yet touched squad state runs without them — which is exactly when these rules matter most.

Everything else — profiles, routing, gates, seed templates, the ledger procedure — lives in the `squad` skill and the instruction files named at the bottom, and is read on demand. This is a floor, not a copy. The one exception is the consumption block below: it is reproduced literally here because a dispatch that guesses its shape is unreadable to every aggregate above it, and the file that defines it does not load until squad state is already in play.

## When This Applies

These rules bind any turn that runs, resumes, or writes to a squad. Ordinary work in a project is unaffected.

## Squad State Paths

All squad state lives under a **squad root**: `.copilot-tracking/squad/` for a single squad, or `.copilot-tracking/squad/members/<name>/` for a sub-squad in a federation.

| Path                   | Purpose                                     | Write semantics    |
|------------------------|---------------------------------------------|--------------------|
| `team.md`              | Roster of roles and the agents filling them | Replace via Scribe |
| `routing.md`           | Request-pattern routing table               | Replace via Scribe |
| `decisions.md`         | Squad decisions and their rationale         | Append-only        |
| `notifications.md`     | Notifications fired and their channel       | Append-only        |
| `history/<agent>.md`   | Per-agent dispatch history                  | Append-only        |
| `state.json`           | Machine-readable squad status               | Replace via Scribe |
| `consumption.md`       | Member, model, and credit ledger            | Replace via Scribe |
| `consumption-rates.md` | Per-model token-rate table                  | Replace via Scribe |

`<agent>` is the agent's `name:` frontmatter value **verbatim** — spaces and capitalization intact, as in `history/BRD Builder.md`. Never slugify, lowercase, or substitute the role id; a renamed file reads as a missing entry and drops that agent from every later ledger rewrite.

Init seeds `history/` **empty**. Each file inside it is created by the dispatch it records, so its presence is what proves that stage ran; a header-only file seeded per roster member at Init destroys that signal.

Detection precedence: `federation.md` present means federation; otherwise `team.md` present means a single squad; otherwise the squad is not initialized and Init Mode runs. Squad state is runtime-created and is never packaged with the squad source.

## The Squad Scribe Is the Single Writer

Only the **Squad Scribe** writes squad state. Every other agent, including both coordinators, reads state to decide and hands each mutation to the Scribe through `runSubagent` or `task`. This is what lets parallel dispatch run without racing on the same files.

Append-only files are appended to and never edited or removed. A coordinator that edits `decisions.md`, `history/`, or `state.json` directly has broken the contract, even when the edit is correct.

**Line numbers are never file content.** A read tool renders a `1.`, `2.`, `12:` gutter down the left margin so you can cite a line; it belongs to the viewer, not to the file. Copying a template out of a numbered view and writing it back with the gutter intact produces a file nothing downstream can parse — including this contract's own checks. Strip the numbering before writing, every time.

## Dispatch Discipline

A coordinator classifies, dispatches, collects, synthesizes, and escalates. It never performs a role's work itself, in any mode — interactive, autonomous, or autopilot. This is the rule that makes the squad a methodology rather than one model improvising.

* Producing research, a plan, a Council Verdict, implementation, or a review inline instead of dispatching the mapped agent is a protocol violation, even when inlining would be faster.
* **Loading or invoking a specialist skill is role work.** Classify only from the request and the roster and routing metadata, and activate only the `squad` skill itself. Host discovery metadata may establish that a skill exists; only the resolved specialist activates it, and only after dispatch.
* Every stage runs by dispatching its mapped agent against the `user-invocable: false` agent the roster resolves.
* When a mapped agent is missing or not dispatchable, **stop and escalate**. Never substitute your own reasoning and never swap in an unmapped agent.
* Running on a fast or auto-selected model never relaxes any of the above. Determinism completes a squad turn, not model strength.

## Resolving a Role to an Agent

A roster row names one **Primary** agent and optionally some **Alternates**. The Primary is what the role dispatches; an Alternate is a documented exception, never a preference.

* **Dispatch the Primary unless a Selection Cue you actually read matches the request.** The cue lives in the roster row's `Selection Cue` cell, seeded at Init from the cast catalog. Reading the `Alternate Agents` cell tells you an alternate exists, not when to use it.
* **No cue in hand means the Primary.** A roster with no `Selection Cue` column, a cue that does not match, or a cue table you could not load all resolve the same way: dispatch the Primary. Picking the alternate that sounds closest to the request is a guess, and it silently swaps the methodology the role was cast for.
* **Record any non-primary resolution** through the Scribe, naming the cue that selected it, so the history entry explains why that agent ran.

## Proof of Dispatch

A stage counts as run only when both exist: its domain artifact on disk at the role's `Deliverable Root`, and a `history/<agent>.md` entry written by the Scribe carrying the dispatch's consumption block. No history entry means the stage did not happen and the turn cannot advance past it.

A history file is created by the dispatch it records, with this preamble and nothing else above the first entry:

```markdown
---
description: "Append-only dispatch history for a single squad agent"
---

# History: <agent>
```

The heading is literally `# History: <agent>` — not the bare agent name, not a rewrite of the description. A later turn locates the file by that heading, so a file headed `# Squad Researcher` reads as a file with no heading at all and drops that agent from every ledger rewrite. The file name is the agent's `name:` verbatim, so `history/Squad Scribe.md`, never `history/scribe.md`.

Verification is an act, not an assertion: list the directory and read the file. Never report a path this turn did not actually enumerate.

**A stage recorded as complete in `state.json` but absent from `history/` did not run.** The history file is the evidence; a status field is a claim about it. Autonomous and autopilot runs remove the human turn between stages, not this check — when the file is missing, stop at that stage and escalate rather than advancing on the strength of the claim.

**Every dispatch is handed over, one payload per dispatch, as it returns.** The Scribe writes what it is given and cannot record a dispatch nobody mentioned. Assembling the run's history at the end from memory reliably drops the stages that ran earliest — leaving their artifact on disk with no history entry, no ledger row, and no `activeRoles` membership, so `state.json` agrees with the ledger and neither agrees with what happened.

### The Deliverable Root Is Binding

The `Deliverable Root` cell of the role's `team.md` row is where that role's artifact goes. It is an operator declaration, not a default, and it **overrides any path convention carried in the dispatched agent's own definition** — `.copilot-tracking/details/`, `docs/`, or wherever that agent writes when it runs outside a squad.

* **Write there, or stop and escalate.** A role that cannot use the root it was given says so; it never substitutes a path it prefers. Roles quietly falling back to their habitual folder leave a roster whose every cell is a lie and give the operator no way to steer output at all.
* **A `<date>` or `<slug>` segment is a directory, not a filename prefix.** `.copilot-tracking/research/<date>/` means `.copilot-tracking/research/2026-08-21/topic.md`, never `.copilot-tracking/research/2026-08-21-topic.md`. **Substitute it; never write the angle brackets.** A path recorded as `.copilot-tracking/research/<date>/findings.md` names a directory literally called `<date>`, so the file it points at is not the file that was written and the existence check has nothing to find.
* **The entry's `Deliverable:` path is the artifact's real path** — resolved, confirmed to exist by listing it, and under that role's root.
* **Write the path the way the root is written.** The `Deliverable:` path extends the `Deliverable Root` cell verbatim, so `.copilot-tracking/squad/members/persistence/plans/` yields `.copilot-tracking/squad/members/persistence/plans/2026-08-21-plan.md` — never `members/persistence/plans/2026-08-21-plan.md`. A path shortened to whatever the writer's working directory happened to be cannot be resolved by anyone reading the entry later, and a path that cannot be resolved is not evidence that the file exists.
* **A stage that wrote no file did not run.** `Deliverable: N/A`, `inline verdict`, `no artifact written`, and an entry with no `Deliverable:` line at all are the same statement: this stage produced nothing the next one can read. A role whose output is a judgment writes that judgment to a file at its Deliverable Root — a verdict that exists only in a chat turn is gone when the turn ends, and the gate that depends on it has nothing to open.

A promotion rebases the roster's roots but **cannot rebase the entries**. History is append-only, so a `Deliverable:` path recorded before a promotion still names the pre-promotion location while the file now sits under `members/<name>/`. Resolve it through the relocation the promotion recorded; never edit the entry to match. An edited history file has broken a stronger rule than the one it repaired.

Reconcile both directions before reporting a run complete: every `Deliverable:` path names a file that exists, and every file under a role's Deliverable Root is claimed by some history entry. **An unclaimed artifact is a dispatch nobody recorded** — stop and escalate rather than reporting the run complete, because that stage is missing from the ledger, from `activeRoles`, and from every cost figure derived from them.

## The Consumption Block Is Literal

Every dispatch entry carries a `#### Consumption` heading followed by a fenced `json` block — level four, no suffix. The only legal variant is `#### Consumption — Orchestration`, which the coordinator's and Scribe's own turns are recorded under in `history/Squad Scribe.md`. Any other heading is unreadable to the ledger rewrite, so the dispatch it records is spent and uncounted.

**A block records what was consumed, never what it cost.** Rates and money live in `consumption.md` and `consumption-rates.md` and appear nowhere else. A rate is a property of the model, so copying it into every block asserts one fact a dozen times and gives it a dozen chances to be asserted wrong; a cost stored beside the tokens it derives from is a second copy of a number that already exists, and the two can disagree. Record the tokens here and price them once, in the ledger.

The field names, their `snake_case` spelling, their order, and the set itself are contractual. Copy this shape; do not translate it into camelCase, and do not add fields of your own:

```json
{
  "model": "<resolved model or unknown>",
  "model_source": "<dispatch-reported|agent-pinned|operator-declared|session-inherited|cli-pinned|unresolved>",
  "priced_as": "<rate row this dispatch prices from>",
  "model_tier": "<fast|default|extended>",
  "internal_turns": 0,
  "input_tokens": 0,
  "cached_tokens": 0,
  "cache_write_tokens": 0,
  "output_tokens": 0,
  "basis": "<estimated|tier-default>"
}
```

Every numeric field is a bare number: `172800`, never `~172,800`, `"172800"`, or `172800 tokens`.

Three rules keep the block parseable, and each one has been broken by a real run:

* **The set is closed at ten.** Estimator working values — `dispatch_class`, `base_context`, `growth_per_turn`, `output_per_turn`, `gross_input_tokens` — are inputs you reason with, not fields you record. Neither are `turn` and `task`, which belong in the entry prose. Nothing priced belongs here either: `input_rate`, `cached_rate`, `cache_write_rate`, `output_rate`, `est_cost_usd`, and `est_credits` were all fields once and are now the ledger's alone.
* **`priced_as` is always present, and it is copied character-for-character from the rate table's `Model (as routed)` cell.** `Claude Sonnet 5`, never `claude-sonnet-5`. When no fallback happened it equals `model`; write it anyway, because it is the only thing that tells the ledger which row to price this dispatch from, and a slug matches no row.
* **`model_tier` is the `Tier` cell of that same row.** Not the roster's `Model Tier` for the role, and not a judgment about how heavy the dispatch felt.

**Size each dispatch from that dispatch.** Two blocks carrying identical token counts describe one dispatch recorded twice, not two dispatches that happened to consume the same amount to the last thousand tokens. When the numbers you are about to write match a block already in `history/`, the sizing was copied — re-derive it from the dispatch actually in hand.

## Two Files the Ledger Reads Back

`consumption-rates.md` is **copied verbatim** from the template in the `squad` skill's `references/consumption.md`, at Init and at every sub-squad seeding or federation promotion. It carries the per-model rate table, the tier-fallback table, the dispatch-size estimator, and the calibration block, and all four are load-bearing. A shortened, summarized, or hand-rewritten rate file leaves the Scribe pricing from a table that no longer contains what it needs.

In `consumption.md`, the row covering the coordinator's and Scribe's own turns is labelled **`orchestration`** in both tables — never `scribe`, `coordinator`, or a split pair. It is derived from the `#### Consumption — Orchestration` blocks the same way every other row is derived from its dispatch blocks, so the Scribe writes one such block into `history/Squad Scribe.md` on every turn it writes state, including Init. No block means no row — an `orchestration` row carrying a figure no block accounts for is invented, and a zero row hides the cost of running the squad.

An orchestration entry takes the same prose shape a dispatch entry takes. The turn number and the work it covers go in these fields, because the block's field set is closed at ten and neither is in it — with no prose slot to hold them they leak into the JSON and break the block:

```markdown
### <timestamp> <what this turn wrote>

* Turn: <n>
* Request: <what the coordinator handed over>
* Deliverable: <the state files this turn wrote>
* Outcome: <one line>

#### Consumption — Orchestration
```

The ten-field block follows that heading, fenced as `json`, exactly as a dispatch entry's does.

The ledger is rewritten from **every** block recorded for the run, not from this turn's. So a role that has never been dispatched carries no row at all rather than a row of zeros; the run total is the sum of every block in `history/`; the `Run:` id in the heading is the current run, not the one Init seeded; and `state.json`'s `currentRun` cost figures equal that same total. A ledger rewritten from one turn silently drops every earlier role while still looking complete.

**This file is the only place cost is derived.** For each row, sum that role's blocks into the `Turns` column and the four token columns — **five columns, not four** — then look up the rates once from the row `priced_as` names in `consumption-rates.md`. `Turns` accumulates exactly as the token columns do: a role dispatched twice with `internal_turns` of `15` and `4` carries `19`, never `4`. Only the four token columns are priced, which is why the fifth is the one most often left at the last block's value. Compute the four products separately, sum them, divide by `1e6`, then multiply by the `calibration_factor`. Worked example at a factor of `1.00`; the separators are only for reading:

```text
 57600 ×  3.00  =  172800
230400 ×  0.30  =   69120
 95200 ×  3.75  =  357000
 15000 × 15.00  =  225000
                  -------
                   823920  / 1e6  =  0.82392 USD  ->  82.39 credits
```

Credits are `est_cost_usd / 0.01`. Read the row back and confirm the cost reproduces from its own four token columns and that row's rates. Divide by `1e6` exactly once — the commonest corruption here is a factor-of-ten slip, a row summing to `113520` written as `1.17` rather than `0.11352`, which survives every other check because the row is otherwise well formed. Compare the digits of your sum against the digits of what you wrote.

**Show the arithmetic in the file.** Under the Usage & Cost table, a `### Derivation` block carries one line per row — the row's turn sum written as an addition, then the four products, their sum, the divide, and the result — and a final line summing the cost column. Doing the arithmetic in your head and writing only the answers is how a row arrives at a cost its own tokens do not support and a turn count its own blocks do not support, which are the two commonest defects this ledger has. Written-out terms cost a few numbers and make the mistake visible to the next reader instead of leaving a plausible total nobody can check:

```text
lead           turns 4         9600 × 2.00 +  38400 × 0.20 +  14400 × 2.50 +  3600 × 10.00 =  98880 / 1e6 = 0.0989
orchestration  turns 15+4=19   6800 × 2.00 +  27200 × 0.20 +  10800 × 2.50 +  2400 × 10.00 =  70040 / 1e6 = 0.0700
                                                                                            total = 0.1689
```

**The total row is computed, never carried.** Sum every column down the rows the rewrite just wrote — turns, all four token columns, cost, and credits — and write those sums. A total carried over from the previous rewrite, or summed across the rows you happened to be looking at, disagrees with the table printed directly above it. The commonest form drops the one short row belonging to a role dispatched on an earlier turn, which is also the row least likely to be missed by eye.

**The total's cost cell is a bare four-decimal number, like every row above it** — `0.2151`, never `$0.22`. A currency symbol and two decimals turn the one figure `state.json` is reconciled against into a rounded string, so the ledger and the run totals disagree by construction and every later comparison inherits the gap.

**The Cost Comparison section is required, and it names three figures**: what this run cost, what the manual baseline would have cost, and the saving as a percentage. The baseline is `expected_iterations × baseline_model_cost_per_turn` with a manual turn priced through the same dispatch-size estimator, and the section states the iteration count and the baseline model it assumed so a reader can disagree with the assumption rather than only with the answer. A per-turn or per-phase breakdown may be added; it never replaces the comparison. This is the one figure an operator actually reads, so a section that reports only what was spent has dropped the only number that answers *why run a squad at all*.

## The Methodology Spine Is Not Optional

Every squad turn that produces substantive output runs **Research → Plan → Implement → Review**, in every mode and on every profile. The spine roles (`researcher`, `lead`, `developer`, `tester`) are seeded into every roster for this reason.

* The output being a document rather than code changes nothing. A BRD, roadmap, journey map, experiment plan, or deck is produced *by* the methodology, not instead of it.
* Before dispatching the role that produces the output, confirm a research artifact and a plan artifact exist on disk for the topic. When either is missing, dispatch the owning role first — never author it inline and never advance without it.
* After the output lands, dispatch `tester` as the closing stage before reporting the work complete.

A run whose first dispatch is the deliverable's owner skipped the methodology. The deliverable will still look finished, which is exactly why this rule is mechanical rather than a judgment call. The gate procedure lives in *Implementation Gate Procedure* in the `squad` skill's `references/gates-and-modes.md`.

## Model Frontmatter Is a String

`model:` is a single string on every host. A YAML array is accepted by VS Code and makes the agent fail to load on the Copilot CLI. Per-role preference belongs in the `Model Tier` column of `team.md`, not in an array.

## Where the Procedure Lives

* The `squad` skill — Init, Route, Decide, Handoff, gates, modes, Scribe write procedure, seed templates, and the consumption ledger, split across `references/`. Start at `references/00-index.md`.
* The other `squad-*.instructions.md` files in this folder — roster, routing, state, discovery, intake, council, autonomous, autopilot, notifications, federation, and watch mode. They auto-apply once a squad-state path is in play, and are read on demand before then.

Apply what you read verbatim. Do not invent a role, agent, profile, pack, or state file the skill and roster do not define.
