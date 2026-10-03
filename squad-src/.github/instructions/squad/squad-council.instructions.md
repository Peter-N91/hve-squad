---
description: "Pre-implementation council protocol with parallel dispatch, most-restrictive-wins synthesis, and durable Council Verdict"
applyTo: '**/.copilot-tracking/squad/**'
---

# Squad Council Conventions

These conventions define the pre-implementation council that the Squad Coordinator dispatches before any implementation-tier role acts on a non-trivial plan, design, or change. The council surfaces architecture, security, cost, product-fit, and (when AI/ML work is in scope) responsible-AI concerns in parallel so that the Squad Scribe can record a single, auditable verdict that downstream implementers consult.

A council run produces exactly one durable artifact: a `## Council Verdict` entry appended to `.copilot-tracking/squad/decisions.md` by the Squad Scribe. The coordinator never writes that entry itself; the single-writer rule from `.github/instructions/squad/squad-state.instructions.md` still holds.

## Trigger Conditions

The coordinator dispatches a council when any of the following hold:

* The user explicitly asks for a council, a pre-implementation review, a cross-check, a design review, a go/no-go, or a validation pass before implementation.
* The user's request contains both implementation language (build, ship, deploy, roll out, merge, apply) and risk language (cost, security, compliance, AI, regulated data, production, irreversible).
* A routing row in `routing.md` resolves to the council pattern (see `squad-routing.instructions.md` for the canonical row).
* A prior turn produced a plan with a material review concern in one or more council-member domains (architecture, security, cost, product-fit, or responsible AI).

When none of the triggers hold, the coordinator follows the normal routing table and does not pay the council-dispatch cost.

## Council Membership

There is no fixed council quorum. For each review, the coordinator proposes the smallest role set that covers the material concerns in the plan or decision, using the role lenses in *Task-Fit Council Offers* in `.github/instructions/squad/squad-roster.instructions.md`. Membership may be one role, several relevant roles, or `rai` alone. Explain each role's review question and that the council validates the plan before implementation; the user may accept, adjust, or decline the proposed membership. If no role is clearly relevant to an explicit council request, ask which reviewer lens the user expects rather than silently skipping the offer or dispatching an arbitrary set.

Each role resolves to its concrete agent through the roster's *Resolving a Role to an Agent* rules in `.github/instructions/squad/squad-roster.instructions.md`. A council membership change for a specific turn is acceptable (for example, swapping a Primary for an Alternate per a Selection Cue), but the exact accepted membership is recorded in the Council Verdict so the verdict is auditable.

### Council Offer Before Dispatch

Whenever a council trigger fires, always present the work-specific council proposal before dispatch, even if all recommended roles are already in `team.md`. Ask once for that roster and trigger/topic whether to accept, adjust, or decline; do not start dispatch while waiting. At Init, Promotion, and Expansion, present the same kind of proposal alongside the roster choice. Never add every absent council role by default.

On acceptance or adjustment, hand the Scribe the exact user-approved membership, any missing role rows and filtered routing rows to add, and a `Council Role Offer` decision recording the roster role set, trigger/topic, proposed and accepted membership, role rationales, and outcome. Verify accepted roster updates and agent availability before dispatch. Dispatch exactly the accepted roles in parallel; this set is the complete council for this review. On decline, hand the Scribe a decision recording declination and escalate without dispatching any council role. Do not repeat a declined offer for the same roster role set and trigger/topic; a changed roster, scope, or trigger/topic is a new offer case. If an accepted addition cannot be installed, recorded, or verified, escalate instead of dispatching.

For Watch Mode and every other run with no interactive user available, make no offer and never auto-add or infer approval for new membership. Reuse an explicitly accepted membership only for the same unchanged topic and scope, if its roles remain available; otherwise escalate through the configured approval channel with the proposed roles, their rationales, and instructions for an authorized user to approve or add them before resuming. Missing, unavailable, or unapproved roles mean no council dispatch and no synthesized verdict; this holds for explicit council triggers and the `autopilot` and `autonomous` council stages.

## Parallel Dispatch Contract

The coordinator dispatches all council roles in a single turn through one batch of parallel `runSubagent` (or `task`) calls. The contract is:

1. All council roles run concurrently against the same scoped input (the plan, design, or change under review).
2. Each role returns a structured finding that names: its verdict label (`Approve`, `Conditional`, `Concern`, `Block`), its risk label (`Risk: Low`, `Risk: Medium`, `Risk: High`), the blocking issues it raised (may be empty), the conditions it requires (may be empty), and any suggested follow-ups.
3. No council role writes squad state directly. Findings flow back to the coordinator and the coordinator hands them to the Squad Scribe for the verdict write.
4. When the dispatched role has an MCP-capability hint relevant to its work (per `.github/instructions/squad/squad-mcp-capability.instructions.md`), the coordinator passes `capability=<hint>` in the dispatch payload.
5. Council dispatch is parallel-eligible by definition; the coordinator does not serialize council roles.

The coordinator does not begin implementation dispatch on the same turn as a council run. The council's output is a precondition for the next turn's implementation dispatch, not a parallel branch alongside it.

## Most-Restrictive-Wins Synthesis

The Scribe applies a single synthesis rule across all council findings:

* Any `Block` verdict from any council role drives the Council Verdict to `Stop`.
* Any `Risk: High` finding from any council role drives the Council Verdict to `Stop`, even when that role's own verdict label is softer (a `Concern` carrying `Risk: High` still blocks).
* When no role reports `Block` or `Risk: High`, but at least one role returned `Conditional` (or raised explicit conditions), the verdict is `Go-With-Conditions` and the conditions are consolidated and de-duplicated under role attribution.
* When every role reports `Approve` (or `Concern` with `Risk: Low` or `Risk: Medium` and zero blocking issues), the verdict is `Go`.

Cost-impacting findings stay restrictive even inside autonomous mode: the `auto-validated` tier defined in `.github/instructions/squad/squad-autonomous.instructions.md` does not downgrade a `Block` or a `Risk: High` from `cost-manager`.

## Council Verdict Schema

The Squad Scribe writes the verdict to `.copilot-tracking/squad/decisions.md` under a new `## Council Verdict` H2. The entry is append-only and uses this shape:

```markdown
## Council Verdict <timestamp> <topic-id>

* Topic: <one-line summary of the proposal>
* Proposal Ref: <path-to-plan-or-design>
* Council Members Dispatched: <comma-separated roles>
* Verdict: Go | Go-With-Conditions | Stop

### Findings by Role

| Role            | Verdict     | Risk        | Blocking Issues | Conditions | Suggested Follow-ups |
|-----------------|-------------|-------------|-----------------|------------|----------------------|
| <accepted role> | <label>     | <risk>      | <list-or-none>  | <list>     | <list>               |

### Synthesis

* Blocking Issues: <consolidated list with role attribution; empty when verdict is Go>
* Conditions: <consolidated list with role attribution; empty when verdict is Go>
* Suggested Follow-ups: <consolidated list with role attribution; may be non-empty for any verdict>

### Implementation Gate

* Permits Implementation Dispatch: yes (Go, Go-With-Conditions) | no (Stop)
* Conditions Outstanding: <count> (must be satisfied or explicitly accepted before implementation lands)
```

Required fields:

* The `timestamp` is the turn's ISO-8601 date or datetime.
* The `topic-id` is a short slug (kebab-case) the coordinator generates from the proposal title so that future turns can reference the verdict by id.
* The `Verdict` value is one of exactly `Go`, `Go-With-Conditions`, or `Stop`.
* The Blocking Issues, Conditions, and Suggested Follow-ups lists carry role attribution inline (for example, `(security) rotate secrets weekly`).

The schema is the contract: include exactly one findings row for every dispatched role and no row for an undispatched role. Any Scribe write that omits a dispatched role or includes an undispatched role fails the council protocol; the coordinator escalates rather than proceeding.

## Verdict Anchor and Decision Ref

Because `decisions.md` is append-only and grows over time, a new `## Council Verdict` entry lands *inside* the file rather than always at the end, which makes it hard for a human to find the entry a gate is talking about. To remove that friction, every Council Verdict entry is addressable by a stable **Decision Ref** — a link straight to the entry's own section — that the coordinator surfaces whenever it reports the verdict or opens a gate.

The Decision Ref is the `decisions.md` path plus the GitHub/VS Code Markdown heading anchor of the `## Council Verdict <timestamp> <topic-id>` line. The anchor is derived from that heading the standard way: lower-case the text, drop punctuation other than hyphens, and replace each run of spaces with a single hyphen. So the heading `## Council Verdict 2026-07-07 residual-controls` yields:

```text
.copilot-tracking/squad/decisions.md#council-verdict-2026-07-07-residual-controls
```

Whenever the coordinator reports a verdict to the user — in a chat reply, at a Human Gate, or in a final-outcome summary — it includes this Decision Ref so the human can open the exact section in one click instead of scanning the middle of the file. The reference is derived deterministically from the entry's heading; it is not a new stored field, so it stays valid for the life of the append-only entry.

## Single-Writer Rule

The Squad Scribe is the only agent that writes the Council Verdict entry. The coordinator assembles the synthesis prompt (raw findings, council membership, topic id, timestamp) and hands it to the Scribe through the normal dispatch contract. Council roles never edit `decisions.md`. This preserves the parallel-dispatch race-prevention guarantee from `.github/instructions/squad/squad-state.instructions.md`.

When the Scribe receives a Council Verdict payload it writes the entry as an append (never edits or removes prior entries) and returns a confirmation listing the verdict label, the topic id, the file path, and the **Decision Ref** (the file path plus the entry's heading anchor, per *Verdict Anchor and Decision Ref* above) so the coordinator can link straight to the section when it reports the verdict or opens a gate.

## Implementation Gate

Implementation-tier roles (`developer`, `tester` when it acts as an implementer, or any role whose routing tier is `confirm` or `auto-validated` for an implementation pattern) consult the latest Council Verdict for the topic before they accept dispatch:

* `Go` permits dispatch on the next turn with no extra conditions.
* `Go-With-Conditions` permits dispatch only when the implementer's payload acknowledges each consolidated condition (a condition may be satisfied in-flight or deferred with an explicit recorded acceptance).
* `Stop` blocks dispatch entirely. The coordinator escalates to the user with the verdict, the blocking issues, the council membership, and the **Decision Ref** (per *Verdict Anchor and Decision Ref*) so the user can open the full verdict section directly.

The coordinator does not bypass the gate. When a user explicitly overrides a `Stop` verdict, the coordinator records the override decision through the Scribe before any implementer dispatches, so the audit trail shows both the verdict and the override.
