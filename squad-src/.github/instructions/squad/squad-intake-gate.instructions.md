---
description: "Pre-work intake gate that validates requirement and input artifacts for completeness and clarity before planning or implementation, with a bounded auto-remediation loop and a durable Intake Readiness Verdict"
applyTo: '**/.copilot-tracking/squad/**'
---

# Squad Intake Gate Conventions

These conventions define the **intake gate**: a conditional pre-work check the Squad Coordinator runs before any planning-, implementation-, or deliverable-producing role acts, but only when the turn's work is **grounded in requirement or input artifacts**. The gate answers one question — *are the inputs we are about to build on complete and clear enough to start?* — and either clears the squad to proceed, remediates the inputs first, or escalates.

The gate is **conditional and additive**. When a turn has no requirement or input artifacts to validate, the gate is a silent no-op and the squad proceeds exactly as today. A repository that never grounds work in inputs never pays the intake-dispatch cost.

An intake run produces exactly one durable artifact: an `## Intake Readiness Verdict` entry appended to `.copilot-tracking/squad/decisions.md` by the Squad Scribe. The coordinator never writes that entry itself; the single-writer rule from `.github/instructions/squad/squad-state.instructions.md` still holds.

## Relationship to the Implementation Gate

The intake gate and the Implementation Gate (`.github/instructions/squad/squad-routing.instructions.md`) are siblings that guard different edges of the methodology:

* The **intake gate** fires at the *front* of the work — before research or planning consumes the inputs — and validates that the requirement/input artifacts the work is based on are ready to build on.
* The **Implementation Gate** fires *before implementation* and validates that research, a plan, and (when applicable) a Council Verdict exist.

Both are preconditions the coordinator checks at routing time, and both leave a durable verdict in `decisions.md`. The intake gate runs first because ready inputs are a precondition for meaningful research and planning.

## Trigger Conditions

The coordinator runs the intake gate at the start of a turn when **both** hold:

1. **The turn's work is grounded in input artifacts.** One or more requirement or input artifacts are in scope — for example a PRD, BRD, requirements document, specification, user story or backlog item, design document, meeting transcript, ADR, or any file the user references or attaches as the basis for the work. Freeform requests with no referenced inputs do not trigger the gate.
2. **The turn will lead to planning, implementation, or a deliverable.** The request is (or advances toward) a build, a plan, or a deliverable that consumes those inputs — not a pure question, a read-only lookup, or a request that only discovers or lists the inputs.

The gate does **not** trigger when:

* No requirement or input artifact is in scope (the no-op case).
* The work is purely exploratory research, a read-only review, or a diagnostic with no downstream build.
* A prior turn already produced a non-stale `## Intake Readiness Verdict` of `Ready` for the same inputs (see *Verdict Reuse* below).

When neither trigger holds, the coordinator follows the normal routing table and does not dispatch the intake gate.

## Gate Membership

The gate dispatches exactly one role — `intake-validator` — resolved to its concrete agent through the roster's *Resolving a Role to an Agent* rules in `.github/instructions/squad/squad-roster.instructions.md`. The role is **seeded into the `product` and `full` profiles** (where requirement and input artifacts are most central) and can be added to any roster. When the gate would fire in a squad that does not carry `intake-validator`, the coordinator offers to add the role (or name a substitute) rather than skipping the check — the same absent-role escalation the roster defines.

The `intake-validator` role reuses existing HVE Core agents by input type via the roster Selection Cue:

* A PRD-shaped input → the PRD-quality reviewer.
* A BRD-shaped input → the BRD-quality reviewer.
* An assumption-, scope-, or ambiguity-pressure-test of any input → the challenger.
* Any other requirement/input artifact → the requirements advisor (the role's Primary).

When the resolved validator agent is absent from the active roster or not installed, the coordinator escalates rather than dispatching a partial gate or substituting its own reasoning — an intake verdict assembled without a dispatched validator is invalid and must not clear the squad.

## Dispatch Contract

1. The coordinator dispatches the `intake-validator` against the scoped inputs (the requirement/input artifacts under review), passing the artifacts and the intended downstream work as context.
2. The validator returns a structured finding that names: its verdict label (`Ready`, `Ready-With-Gaps`, `Not-Ready`), the completeness and clarity gaps it found (may be empty), the specific clarifying questions a human must answer (may be empty), and any assumptions it recommends recording.
3. The validator is read-only. It never edits the input artifacts and never writes squad state directly; findings flow back to the coordinator, which hands them to the Squad Scribe for the verdict write.
4. Intake runs on its own turn edge: the coordinator does not dispatch planning or implementation on the same turn it runs the gate when the verdict is `Not-Ready`. A `Ready` or a remediated-then-`Ready` verdict clears the same-turn or next-turn work.

## Readiness Assessment

The validator assesses each in-scope input against these dimensions and reports gaps under the ones that fail:

* **Completeness** — the input covers the problem, the desired outcome, and the constraints; no required section is missing or a placeholder.
* **Clarity** — requirements are unambiguous and interpretable one way; terms are defined; there is no contradictory language.
* **Testability** — the outcome is stated so that "done" is checkable (acceptance criteria, measurable goals, or an equivalent).
* **Consistency** — the input does not contradict itself or other in-scope inputs.
* **Scope boundaries** — what is in and out of scope is stated well enough to plan against.

A gap is **blocking** when it would force the downstream role to guess a material decision; it is **non-blocking** when a reasonable, recordable assumption closes it.

## Verdict Synthesis

The Scribe records the label the validator returned; it does not synthesize or downgrade it. The labels mean:

* `Ready` — no blocking gaps. The squad proceeds; any non-blocking gaps are recorded as assumptions.
* `Ready-With-Gaps` — only non-blocking gaps remain. The squad proceeds **with the gaps recorded as explicit assumptions** carried into the downstream work; the coordinator surfaces them to the user.
* `Not-Ready` — one or more blocking gaps remain. The squad does not proceed to plan or implement; the coordinator runs the auto-remediation loop below.

## Auto-Remediation Loop

On a `Not-Ready` verdict, the coordinator remediates the inputs before it proceeds, rather than stopping outright:

1. **Dispatch a remediation role.** Route the specific blocking gaps to the role that owns the input's shape — `analyst` (PRD/BRD authoring) to fill or correct a requirements document, or `product-owner` to refine a backlog item — with the validator's gap list and clarifying questions as inputs. The remediation role updates the input artifact (or drafts the missing content for the user to confirm).
2. **Re-validate.** Re-dispatch the `intake-validator` against the remediated inputs and synthesize a new verdict.
3. **Bounded cap.** The remediation loop is capped at **two** cycles. After the second re-validation, the coordinator stops looping regardless of outcome.
4. **Escalate on unresolved or human-only gaps.** The coordinator escalates to the user — rather than looping again — the moment a blocking gap requires a human decision the squad cannot make (a business choice, a missing external fact, a stakeholder trade-off), when the cap is reached with blocking gaps still open, or when two consecutive cycles fail to reduce the blocking-gap set (divergence). On escalation it presents the outstanding blocking gaps and the validator's clarifying questions and waits.

Each validator dispatch and each remediation dispatch is a Scribe-recorded stage with its own `history/<agent>.md` entry and consumption block, so the loop is auditable after the fact.

## Intake Readiness Verdict Schema

The Squad Scribe writes the verdict to `.copilot-tracking/squad/decisions.md` under a new `## Intake Readiness Verdict` H2. The entry is append-only and uses this shape:

```markdown
## Intake Readiness Verdict <timestamp> <topic-id>

* Topic: <one-line summary of the work the inputs ground>
* Inputs Reviewed: <comma-separated artifact paths or references>
* Validator Dispatched: <resolved agent name>
* Verdict: Ready | Ready-With-Gaps | Not-Ready
* Remediation Cycles: <0, 1, or 2>

### Findings

| Dimension       | Result       | Blocking Gaps    | Non-Blocking Gaps |
|-----------------|--------------|------------------|-------------------|
| Completeness    | pass/fail    | <list-or-none>   | <list-or-none>    |
| Clarity         | pass/fail    | <list-or-none>   | <list-or-none>    |
| Testability     | pass/fail    | <list-or-none>   | <list-or-none>    |
| Consistency     | pass/fail    | <list-or-none>   | <list-or-none>    |
| Scope Boundaries| pass/fail    | <list-or-none>   | <list-or-none>    |

### Clarifying Questions

* <question for the user; empty when verdict is Ready>

### Recorded Assumptions

* <assumption carried into downstream work; empty when none>

### Intake Gate

* Permits Downstream Dispatch: yes (Ready, Ready-With-Gaps) | no (Not-Ready)
* Blocking Gaps Outstanding: <count>
```

Required fields:

* The `timestamp` is the turn's ISO-8601 date or datetime.
* The `topic-id` is a short kebab-case slug the coordinator generates from the work title so future turns can reference the verdict by id.
* The `Verdict` value is one of exactly `Ready`, `Ready-With-Gaps`, or `Not-Ready`.
* Blocking and non-blocking gaps carry artifact attribution inline when more than one input is in scope (for example, `(prd.md) no acceptance criteria`).

The schema is the contract: any Scribe write that omits one of these sections fails the intake protocol and the coordinator escalates rather than proceeding.

## Verdict Anchor and Decision Ref

Like the Council Verdict, every Intake Readiness Verdict is addressable by a stable **Decision Ref** so a human can open the exact entry a gate is talking about instead of scanning the append-only `decisions.md`. The Decision Ref is the `decisions.md` path plus the Markdown heading anchor of the `## Intake Readiness Verdict <timestamp> <topic-id>` line, derived the standard way (lower-case, drop punctuation other than hyphens, replace each run of spaces with a single hyphen). So the heading `## Intake Readiness Verdict 2026-07-20 checkout-redesign` yields:

```text
.copilot-tracking/squad/decisions.md#intake-readiness-verdict-2026-07-20-checkout-redesign
```

Whenever the coordinator reports an intake verdict — in a chat reply, at a gate, or in an autopilot final-outcome summary — it includes this Decision Ref.

## Verdict Reuse

Because inputs are usually validated once and then built on across several turns, the coordinator reuses a prior `Ready` (or `Ready-With-Gaps`) verdict for the same inputs rather than re-running the gate every turn:

* A verdict is reusable while the in-scope input artifacts are unchanged since the verdict's timestamp. When an input changes, the prior verdict is stale and the gate re-runs.
* A `Not-Ready` verdict is never "reused" to proceed — it always requires remediation or escalation first.

## Mode Interaction

The gate applies in every mode; how an unresolved `Not-Ready` presents differs by mode:

* **Interactive** — the coordinator runs the remediation loop; on escalation it asks the user the clarifying questions before any planning or implementation dispatch.
* **Autopilot** (`.github/instructions/squad/squad-autopilot.instructions.md`) — the intake gate runs at the front of the pipeline. A `Not-Ready` that the remediation loop cannot clear fires a **Human Gate** (an intake-readiness gate) and the pipeline pauses for the user, notified per `.github/instructions/squad/squad-notifications.instructions.md`.
* **Autonomous** (`.github/instructions/squad/squad-autonomous.instructions.md`) — an unresolved `Not-Ready` is a mandatory escalation trigger; the loop stops and hands control to the user.
* **Federation** — the gate applies within each sub-squad exactly as for a plain squad, because the Squad Federation Coordinator runs each sub-squad's per-turn protocol scoped to its own root (`.github/instructions/squad/squad-federation.instructions.md`). Each sub-squad's Intake Readiness Verdict lands in its own `members/<name>/decisions.md`.

## Single-Writer Rule

The Squad Scribe is the only agent that writes the Intake Readiness Verdict entry. The coordinator assembles the payload (the validator's findings, the inputs reviewed, the topic id, the timestamp, the remediation-cycle count, and the verdict label) and hands it to the Scribe through the normal dispatch contract. The validator and remediation roles never edit `decisions.md`. This preserves the parallel-dispatch race-prevention guarantee from `.github/instructions/squad/squad-state.instructions.md`.
