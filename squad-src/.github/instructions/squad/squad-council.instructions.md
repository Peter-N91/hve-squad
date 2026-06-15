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
* A prior turn produced a plan whose scope crosses two or more council-member domains (for example, an Azure landing-zone change that touches budget and security).

When none of the triggers hold, the coordinator follows the normal routing table and does not pay the council-dispatch cost.

## Council Membership

The default council is four roles dispatched in parallel:

* `architect`
* `security`
* `cost-manager`
* `product-owner`

The council adds a fifth role when the request involves AI/ML behavior, model selection, training data, agent autonomy, or any RAI-relevant decision:

* `rai` (optional, conditional on RAI-relevance)

Each role resolves to its concrete agent through the roster's *Resolving a Role to an Agent* rules in `.github/instructions/squad/squad-roster.instructions.md`. A council membership change for a specific turn is acceptable (for example, swapping a Primary for an Alternate per a Selection Cue), but the council membership is recorded in the Council Verdict so the verdict is auditable.

When a council role is absent from the active roster (`team.md`), or its mapped agent is not installed or not available at dispatch time, the coordinator escalates rather than dispatching a partial council. A council quorum is the full default membership (`architect`, `security`, `cost-manager`, `product-owner`); the optional `rai` slot is the only conditional role. The coordinator never synthesizes a Council Verdict from its own reasoning to cover a missing role, and never substitutes a non-mapped agent for an absent council member — a verdict assembled without the full quorum's dispatched findings is invalid and must not gate implementation.

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

| Role           | Verdict     | Risk        | Blocking Issues | Conditions | Suggested Follow-ups |
|----------------|-------------|-------------|-----------------|------------|----------------------|
| architect      | <label>     | <risk>      | <list-or-none>  | <list>     | <list>               |
| security       | <label>     | <risk>      | <list-or-none>  | <list>     | <list>               |
| cost-manager   | <label>     | <risk>      | <list-or-none>  | <list>     | <list>               |
| product-owner  | <label>     | <risk>      | <list-or-none>  | <list>     | <list>               |
| rai (optional) | <label>     | <risk>      | <list-or-none>  | <list>     | <list>               |

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

The schema is the contract: any Scribe write that omits one of these sections fails the council protocol and the coordinator escalates rather than proceeding.

## Single-Writer Rule

The Squad Scribe is the only agent that writes the Council Verdict entry. The coordinator assembles the synthesis prompt (raw findings, council membership, topic id, timestamp) and hands it to the Scribe through the normal dispatch contract. Council roles never edit `decisions.md`. This preserves the parallel-dispatch race-prevention guarantee from `.github/instructions/squad/squad-state.instructions.md`.

When the Scribe receives a Council Verdict payload it writes the entry as an append (never edits or removes prior entries) and returns a confirmation listing the verdict label, the topic id, and the file path.

## Implementation Gate

Implementation-tier roles (`developer`, `tester` when it acts as an implementer, or any role whose routing tier is `confirm` or `auto-validated` for an implementation pattern) consult the latest Council Verdict for the topic before they accept dispatch:

* `Go` permits dispatch on the next turn with no extra conditions.
* `Go-With-Conditions` permits dispatch only when the implementer's payload acknowledges each consolidated condition (a condition may be satisfied in-flight or deferred with an explicit recorded acceptance).
* `Stop` blocks dispatch entirely. The coordinator escalates to the user with the verdict, the blocking issues, and the council membership.

The coordinator does not bypass the gate. When a user explicitly overrides a `Stop` verdict, the coordinator records the override decision through the Scribe before any implementer dispatches, so the audit trail shows both the verdict and the override.
