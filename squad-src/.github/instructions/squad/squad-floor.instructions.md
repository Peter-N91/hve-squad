---
description: "Unconditional squad floor: state paths and write semantics, the single-writer Scribe rule, dispatch discipline, proof of dispatch, and the Research → Plan → Implement → Review spine — the rules that must hold before any file is in play"
applyTo: '**'
---

# Squad Agent Floor

This file carries only the squad rules that must hold before any file is in play. It is scoped to `**` deliberately: every other squad instruction file is gated on `**/.copilot-tracking/squad/**`, so a freshly dispatched agent that has not yet touched squad state runs without them — which is exactly when these rules matter most.

Everything else — profiles, routing, gates, seed templates, the consumption ledger — lives in the `squad` skill and the instruction files named at the bottom, and is read on demand. This is a floor, not a copy.

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

The consumption block is a `#### Consumption` heading followed by a fenced `json` block — level four, no suffix, bare numbers throughout. The only legal variant is `#### Consumption — Orchestration`. Any other heading is unreadable to the ledger rewrite, so the dispatch it records is spent and uncounted. Its `est_cost_usd` is derived from the tokens and rates in that same block and must reproduce from them; a figure that does not is fabricated and corrupts every aggregate above it.

Verification is an act, not an assertion: list the directory and read the file. Never report a path this turn did not actually enumerate.

**A stage recorded as complete in `state.json` but absent from `history/` did not run.** The history file is the evidence; a status field is a claim about it. Autonomous and autopilot runs remove the human turn between stages, not this check — when the file is missing, stop at that stage and escalate rather than advancing on the strength of the claim.

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
