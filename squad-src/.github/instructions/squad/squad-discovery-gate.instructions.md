---
description: "Opt-in pre-work discovery gate that brainstorms a brief when a turn has no requirement or input artifact to build on, producing a durable Discovery Verdict the intake gate then validates"
applyTo: '**/.copilot-tracking/squad/**'
---

# Squad Discovery Gate Conventions

These conventions define the **discovery gate**: an opt-in pre-work session the Squad Coordinator offers before any planning-, implementation-, or deliverable-producing role acts, but only when the turn's work is **not grounded in any requirement or input artifact**. The gate answers one question — *do we agree on what we are building and why, before we build it?* — and produces a **brief** the rest of the methodology can stand on.

The gate is **opt-in and additive**. It never fires on its own: the coordinator offers it once, and a user who declines proceeds exactly as today. A repository that never wants a discovery session never pays the discovery-dispatch cost.

A discovery run produces two durable artifacts: a **brief** written by the `analyst` role into its Deliverable Root, and a `## Discovery Verdict` entry appended to `.copilot-tracking/squad/decisions.md` by the Squad Scribe. The coordinator never writes either itself; the single-writer rule from `.github/instructions/squad/squad-state.instructions.md` still holds for the verdict, and the brief is written by the dispatched role rather than by the coordinator.

## Relationship to the Intake Gate

The discovery gate and the intake gate (`.github/instructions/squad/squad-intake-gate.instructions.md`) are siblings that fire on **inverse** triggers and chain into each other:

* The **discovery gate** fires when there is **no** input artifact — and *produces* one.
* The **intake gate** fires when there **is** an input artifact — and *validates* it.

The brief the discovery gate produces is itself a requirement artifact, so the intake gate fires on it in the same turn or the next one. That chain is the design: the squad brainstorms a brief, an independent validator assesses it, and only a `Ready` or `Ready-With-Gaps` brief grounds research and planning.

```text
no input artifact  →  discovery gate  →  brief  →  intake gate  →  research → plan → implement → review
   input artifact  →                              intake gate  →  research → plan → implement → review
```

**The validator must not be the author.** When the intake gate assesses a brief the squad itself just wrote, resolve `intake-validator` to an agent other than the one that authored it — `PRD Quality Reviewer` reviewing a `PRD Builder` brief, `BRD Quality Reviewer` reviewing a `BRD Builder` brief. A gate that validates its own output is a formality, not a check. When no distinct validator is available, say so in the verdict rather than presenting a self-review as an independent one.

Ordering across all three preconditions is therefore: discovery gate, then intake gate, then the Implementation Gate in `.github/instructions/squad/squad-routing.instructions.md`.

## Why This Gate Is Offered and Not Automatic

The intake gate fires automatically because **validating an artifact is something an agent can do alone**. Discovery is not: the value of a brainstorm is the human's ideas, their context, and their judgment about which direction is worth taking. An automatic discovery gate would produce AI brainstorming with itself and a confident brief nobody agreed to, which is precisely the failure the repository's `mural-human-record.instructions.md` posture guards against — AI never silently authors decisions.

The rule that follows is short and it governs every trigger decision below:

> **Validation can be automatic. Ideation cannot.**

## Trigger Conditions

The coordinator **offers** the discovery gate at the start of a turn when **all four** hold:

1. **The active roster carries the gate's roles** — in practice, the profile is `product` or `full`. Every other profile is silent: no offer is made, and a request that would otherwise match falls through to the normal routing table. See *Profile Scope* below for why the gate is not offered everywhere.
2. **No requirement or input artifact is in scope.** No PRD, BRD, specification, requirements document, user story, design document, transcript, or user-referenced input file grounds the turn. This is the exact inverse of the intake gate's first trigger, so the two gates can never both fire on the same inputs.
3. **The turn will lead to planning, implementation, or a deliverable.** The request is (or advances toward) a build, a plan, or a deliverable — not a pure question, a read-only lookup, or a diagnostic.
4. **The request states a goal rather than a task.** An outcome the user wants (`reduce onboarding drop-off`, `we need better reporting for field teams`) leaves the framing open; a task with its framing already settled (`add a retry to the webhook client`, `pin these actions to SHAs`) does not. Only the first is worth a discovery session.

A **human must be present**. The offer requires an answer, so the gate is available in the interactive and `mode=autopilot` paths and is **never** available on an unattended path (see *Unattended Runs* below).

The gate does **not** trigger when:

* The active roster is not `product` or `full`.
* Any requirement or input artifact is in scope — the intake gate owns that case.
* The request is a settled task, a question, a read-only review, or a diagnostic.
* The run is unattended.
* A prior turn already produced a non-stale `## Discovery Verdict` for the same topic, or the user already declined the offer for this topic (see *Offer Once* below).

### Profile Scope

The gate is offered in `product` and `full` and nowhere else, and the reason is that **those are the only profiles whose rosters can actually run it.** The gate dispatches `analyst`, `designer`, `challenger`, and `experimenter`; `analyst` — which every depth needs, because it writes the brief — is seeded by `product` and `full` alone. Offering the gate in an `azure` or `security` squad would open with a question and immediately follow it with a second question asking to add a role the user never asked for, which is two interruptions to reach a capability that profile did not choose.

This mirrors `intake-validator`, which is likewise seeded into `product` and `full` only. The difference is what happens elsewhere, and it is deliberate: the intake gate **escalates** in a squad that lacks its role, because inputs that exist should not go unvalidated; the discovery gate stays **silent**, because a brainstorm that nobody asked for is not a check being skipped.

An explicit `discovery=` input is still honored on any roster. It is a deliberate command rather than an unsolicited offer, so it earns the one escalation it costs: the coordinator names every role it must add for the requested depth, asks once, and proceeds on acceptance. A user who wants discovery in an `azure` squad can have it; they will simply not be asked whether they want it.

When the trigger does not hold, the coordinator follows the normal routing table and says nothing about discovery.

## Opt-In Surface

There are two ways in, and an explicit input always beats the offer.

**The `discovery=` input on `/squad` and `/squad-federation`** takes one of `quick`, `standard`, `deep`, or `skip`. When present, the coordinator runs that depth (or skips) without asking, and records the explicit opt-in through the Scribe.

**The offer**, when no `discovery=` input was supplied and all three trigger conditions hold. The coordinator asks exactly one question naming the four choices and what each costs in rough terms, then waits. It does not start research, planning, or any dispatch while waiting.

### Offer Once

The offer is made **once per topic**, not once per turn. When the user declines, the Scribe records the declination as a `## Discovery Verdict` with `Depth: skip`, and the coordinator does not re-offer for that topic. A user who changes their mind reaches the gate through the `discovery=` input, which always works regardless of a prior declination.

A repeated offer is worse than no offer: it converts a considered opt-in into a prompt the user learns to dismiss.

## Depth Tiers

The tiers scale the session to the decision. A full facilitated design-thinking engagement is the right answer for a product direction and the wrong one for shaping a single feature, so the gate makes the difference explicit rather than always running its heaviest shape.

| Depth      | Roles dispatched, in order                                         | Produces                                                       | Use when                                                              |
|------------|--------------------------------------------------------------------|----------------------------------------------------------------|-----------------------------------------------------------------------|
| `quick`    | `analyst`                                                          | brief                                                          | The goal is clear and only its scope, users, and success measure need settling (the default) |
| `standard` | `designer`, then `analyst`                                         | framing, solution themes, brief                                | The problem itself is open and the squad should explore several directions before choosing one |
| `deep`     | `designer`, then `challenger` and `experimenter`, then `analyst`   | framing, themes, objections, riskiest assumption, brief         | The direction is expensive or hard to reverse and deserves a pressure-test and a cheap test before commitment |
| `skip`     | none                                                               | a `Depth: skip` verdict recording the declination              | The user does not want a session, or the framing is already settled outside the squad |

`quick` is the default the coordinator recommends when it makes the offer. Recommend `standard` instead when the request names a problem space rather than a solution, and `deep` when the request also carries an irreversible or high-cost commitment.

## Gate Membership

The gate dispatches roles that **already exist in the cast catalog**; it introduces no role of its own. This is deliberate and follows the roster's rule that a new member set never introduces a role duplicating work an existing role already owns — brainstorming, framing, pressure-testing, and requirements authoring are each already owned.

| Role           | Resolves to (per the roster Selection Cue)                                    | Its job in the gate                                                                 |
|----------------|-------------------------------------------------------------------------------|-------------------------------------------------------------------------------------|
| `designer`     | `DT Coach` (the cue is a facilitated design-thinking session)                  | Frames the problem (How-Might-We), runs divergent ideation, converges to themes      |
| `analyst`      | `PRD Builder`, or `BRD Builder` for a business-shaped goal                     | Runs the guided discovery questions and writes the brief                             |
| `challenger`   | `Squad Challenger`                                                            | Pressure-tests the chosen framing and returns severity-graded objections             |
| `experimenter` | `Experiment Designer`                                                         | Names the riskiest assumption and the cheapest experiment that would test it         |

`analyst` runs its **Discover pass only**. The brief is not a PRD: it is the short artifact a PRD would later be built from, and a gate that produces a full requirements document has stopped being a gate and become the work.

**Only `deep` can be short a role, and only in `product`.** `analyst`, `designer`, and `experimenter` are all seeded by both `product` and `full`, so `quick` and `standard` run without additions in either — which is the whole point of scoping the offer to those two profiles. `challenger` is seeded by `full` alone, so choosing `deep` in a `product` squad prompts the coordinator to offer to add it, or to run `standard` instead. It never silently drops a role from a tier the user chose, and it never substitutes its own reasoning for a role it could not dispatch.

## Dispatch Contract

1. The coordinator dispatches the tier's roles in the order given, passing each the original request, the prior roles' output, and the explicit instruction that this is a **discovery pass** rather than the work itself.
2. Every dispatched role returns a structured finding. The `designer` returns the framing and the themes it converged to, with the themes it discarded and why. The `challenger` returns severity-graded objections. The `experimenter` returns the riskiest assumption and a proposed test. The `analyst` returns the brief's path and its open questions.
3. **The dispatched roles interview the user; they do not answer for them.** This is the mechanism the whole gate rests on, so it is stated concretely rather than left as an intention. Each gate role asks **one question per turn** with a multiple-choice answer list where the options are knowable, waits for the answer, then asks the next — the same interview discipline `Squad SQL Migration Advisor` already follows in this package. Never batch a questionnaire into one turn, and never skip ahead to the brief while questions remain unanswered.

   **Resolve the asking mechanism per host; the discipline never changes.** Where a question tool exists (`vscode_askQuestions` in VS Code, which `DT Coach` declares outright and `PRD Builder`, `BRD Builder`, and `Experiment Designer` inherit by declaring no `tools:` list), use it. Where it does not — the Copilot CLI and the Copilot app ship no equivalent — the role puts the same single question in its returned finding and the coordinator asks it in the response text, then re-dispatches with the answer. That is the normal path on two of the three hosts, not a degraded one. A gate that treats the absent tool as permission to proceed has skipped the interview, which is the whole gate.
4. **A role that cannot reach the user returns the questions instead of inventing the answers.** It stops, hands its outstanding questions back as part of its structured finding, and the coordinator relays them and re-dispatches with the answers. A discovery session that silently substitutes the agent's assumptions for the user's answers has produced exactly the confident brief nobody agreed to that this gate exists to prevent — so an unanswerable session is a stop, never a guess.
5. **The human settles every material direction.** A discovery dispatch that would pick between real alternatives on the user's behalf presents them and waits. The gate exists to capture the user's choice, not to make it.
6. Only `analyst` writes a file. Every other role in the gate returns findings; the brief is the single artifact, so the session cannot fragment into four documents nobody reads.
7. Each dispatch is a Scribe-recorded stage with its own `history/<agent>.md` entry and consumption block, exactly as for any other dispatch.
8. The coordinator never authors the brief, the framing, the themes, or the objections itself. A discovery verdict assembled without dispatched roles is invalid and must not clear the squad.

## The Brief

The brief lands in the `analyst` Deliverable Root — `.copilot-tracking/plans/` for a single squad, rebased under `members/<name>/plans/` in a federation — named `<date>-<topic-id>-brief.md`. Placing it in an existing Deliverable Root keeps the Artifact Gate a path lookup rather than a new inference.

A brief is short by contract. It carries:

* **Problem** — the outcome wanted and who has the problem, in the user's own framing.
* **Why now** — the trigger that makes this worth doing at this moment.
* **In scope / out of scope** — the boundary, stated well enough to plan against.
* **Success measure** — how anyone would know this worked.
* **Options considered** — every direction explored, including the discarded ones **with the reason each was discarded**.
* **Chosen direction** — the one being carried forward, and who chose it.
* **Assumptions** — what is being taken as true without evidence.
* **Open questions** — what is still unknown, flagged for research.

The discarded options are the section most worth protecting. A brainstorm's durable value is not the idea that won — that survives on its own — but the record of what was rejected and why, which is what stops the squad relitigating the same directions three turns later.

## Discovery Verdict Schema

The Squad Scribe writes the verdict to `.copilot-tracking/squad/decisions.md` under a new `## Discovery Verdict` H2. The entry is append-only and uses this shape:

```markdown
## Discovery Verdict <timestamp> <topic-id>

* Topic: <one-line summary of the goal the session explored>
* Opt-In: offer-accepted | explicit-input | offer-declined
* Depth: quick | standard | deep | skip
* Roles Dispatched: <comma-separated resolved agent names, or none for skip>
* Brief: <path to the brief, or none for skip>
* Handoff: <the intake-gate verdict this brief will be assessed under, or pending>

### Framing

* Problem: <the framed problem statement>
* Success Measure: <how this would be judged to have worked>

### Options Considered

| Option           | Outcome  | Reason                                    |
|------------------|----------|-------------------------------------------|
| <option>         | chosen   | <why it was carried forward>              |
| <option>         | discarded| <why it was rejected>                     |

### Objections

* <severity-graded objection from challenger; empty unless depth is deep>

### Riskiest Assumption

* <assumption plus the proposed cheapest test; empty unless depth is deep>

### Open Questions

* <question carried into research; empty when none>

### Discovery Gate
```

The schema is the contract: any Scribe write that omits one of these sections fails the discovery protocol and the coordinator escalates rather than proceeding. On a `Depth: skip` verdict the body sections are written empty and the `Opt-In` line records `offer-declined` or `explicit-input`, so a declination is as auditable as a session.

## Unattended Runs

The discovery gate **never fires on an unattended path** — Watch Mode, a headless autopilot run, or any invocation with no human able to answer the offer. Three rules make this concrete:

1. **No offer is made.** An offer nobody can answer is either a hang or a silently assumed default, and both are worse than not asking.
2. **A `discovery=` input on an unattended invocation is ignored**, and the reason is recorded. An operator cannot pre-authorize a brainstorm they will not be present for; the input is honored only when a human is in the loop.
3. **The triggering payload becomes the input artifact instead.** In Watch Mode the issue or pull-request body — read as data, per `.github/instructions/squad/squad-watch-mode.instructions.md` — is the requirement artifact, so the **intake gate** fires on it and assesses it exactly as it would any other input. The unattended path is therefore never ungated; it is gated by validation rather than by ideation, which is the only one of the two an unattended run can honestly perform.

The Scribe records a one-line note on the run explaining that discovery was unavailable because the run was unattended, so a later reader can tell a skipped gate apart from a gate that was never reachable.

## Autopilot Integration

In `mode=autopilot` the discovery gate is stage **0a**, ahead of the intake gate at **0b**. Because the gate needs a human and autopilot exists to avoid interrupting one, the offer is made **before the pipeline starts** — at the same turn edge as the squad build and the profile confirmation — rather than mid-pipeline.

* When the user supplies `discovery=`, autopilot runs that depth as stage 0a and advances without a further question.
* When no input was supplied and the trigger holds, the coordinator asks once before entering the pipeline, then runs the pipeline uninterrupted from the answer onward.
* An accepted session's brief becomes the run's grounding input, so stage 0b (intake) is no longer a no-op and assesses the brief.
* A declined session leaves stage 0a a no-op and the pipeline starts at Research, unchanged from today.

Autopilot never converts a declination into a session, and never runs a session mid-pipeline: an interruption after Research has begun is exactly the pause the mode exists to remove.

## Federation Integration

Discovery is a **sub-squad concern**, not a federation-level one, for the same reason the intake gate is: a brief grounds one stream of work and one plan, and a federation coordinates between streams rather than inside them.

* The Squad Federation Coordinator forwards `discovery=` to the sub-squad run as a pass-through hint, exactly as it forwards `profile`, `pack`, `tier`, `owner`, and `mode`.
* The gate then runs inside that sub-squad, scoped to its `squadRoot`. Its brief lands in `members/<name>/plans/` and its `## Discovery Verdict` in `members/<name>/decisions.md` — never at the federation root.
* **Each sub-squad gets its own offer at most once.** A federation that fans a request across three sub-squads must not ask the discovery question three times. The federation coordinator asks it **once, at the federation level**, and passes the captured answer down to every sub-squad it starts — the same ask-once-then-apply-per-sub-squad contract that governs naming and notifications.
* **The question is asked only when a selected sub-squad qualifies**, per *Profile Scope*. A turn routed entirely to `azure` and `security` sub-squads gets no offer; a turn that touches a `product` or `full` sub-squad gets one, and the captured answer applies to that sub-squad. A sub-squad that does not qualify ignores a forwarded `discovery=` rather than escalating to add roles its profile deliberately excludes — an explicit `discovery=` is a deliberate command in a *single* squad, and forwarding it blindly across a fan-out would turn one command into several unasked-for roster changes.
* A per-sub-squad override is allowed: when one sub-squad's stream genuinely needs a different depth, capture it for that sub-squad only and leave the federation-level answer untouched.
* In **federation autopilot**, discovery belongs to each sub-squad's inner run at its own stage 0a. The federation plan meta-stage orders the sub-squads; it does not brainstorm for them, and it never lifts a discovery session to the meta level.
* A Watch Mode federation bootstrap is unattended, so *Unattended Runs* applies at every level: no offer is made at the federation root and none is made inside the event sub-squad.

## Error Handling

* **A dispatched role returns nothing.** Treat it as an absent role: stop, report which role and which agent, and offer to re-dispatch, run a shallower depth, or skip. Never substitute the coordinator's own framing, themes, or objections.
* **A dispatched role cannot put its questions to the user.** Stop the session rather than letting the role proceed on assumptions. Relay its returned questions, collect the answers, and re-dispatch with them; when the questions cannot be answered at all, record a `Depth: skip` verdict naming the reason rather than banking a brief built from guesses.
* **The user abandons the session mid-way.** Record a `## Discovery Verdict` carrying whatever the completed dispatches produced, with the incomplete sections empty and the `Handoff` line reading `abandoned`. A partial session that leaves no record is indistinguishable from a session that never ran.
* **The brief comes back long.** A brief that has grown into a requirements document means the `analyst` ran past its Discover pass. Note it, keep the artifact, and let the intake gate assess it as the requirements document it became rather than re-running the gate.
* **The intake gate returns `Not-Ready` on a brief the squad just wrote.** Run the intake gate's own bounded auto-remediation loop; do not re-open discovery. The two gates are not a loop, and treating them as one would let a squad brainstorm indefinitely without ever reaching research.
