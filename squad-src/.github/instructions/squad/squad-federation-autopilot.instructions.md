---
description: "Opt-in federation-level autopilot: a meta-pipeline that orders sub-squad autopilot runs under one set of federation gates, aggregating their gates, verdicts, and cost to the federation level"
applyTo: '**/.copilot-tracking/squad/**'
---

# Squad Federation Autopilot Conventions

These conventions define **federation-level autopilot**: a thin meta-pipeline the Squad Federation Coordinator runs across several sub-squads under one coherent set of Human Gates. Where single-squad autopilot sequences a squad's *roles* end-to-end (`.github/instructions/squad/squad-autopilot.instructions.md`), federation autopilot sequences *sub-squads*, running each sub-squad's standard single-squad autopilot unchanged as the inner engine and aggregating their gates, verdicts, and cost to the federation level.

Federation autopilot is **opt-in and additive**. It reuses every existing mechanism — each sub-squad's autopilot pipeline, council, validator loop, review, deliverable fan-out, and single-writer Scribe discipline — without changing any of them. A federation that never opts in, and any single-squad project, is completely unaffected.

## Relationship to Single-Squad Autopilot

Federation autopilot adds exactly one level above single-squad autopilot; it does not replace or alter it.

* **Single-squad autopilot** (`.github/instructions/squad/squad-autopilot.instructions.md`) runs the research → plan → council → implement → review → final-outcome pipeline for one squad. It is unchanged by these conventions.
* **Federation autopilot** orders the selected sub-squads, runs each one's single-squad autopilot inner run scoped to `members/<name>/`, and aggregates every gate and verdict those inner runs raise to a single federation-level set of gates and one consolidated final-outcome validation.

Each sub-squad's inner run is byte-for-byte the single-squad autopilot pipeline: its own Research, Plan, pre-implementation council, Implement (including the bounded validator loop and any deliverable fan-out), and Review stages all run exactly as they do for a plain squad. Federation autopilot never reaches inside an inner run to change a stage; it only orders the inner runs and lifts their gates to the meta level.

## Trigger (Opt-In Surface)

Federation autopilot engages only through the `/squad-federation` prompt input `mode=autopilot`, and only when the request has **no single `squad=` target**:

* **`mode=autopilot` with no `squad=` target** → **federation autopilot**. The Federation Coordinator runs the Meta-Pipeline Contract below across the sub-squads that meta-routing selects for the request.
* **`mode=autopilot` with a single `squad=<name>` target** → **forward-only, unchanged**. The mode forwards to that one sub-squad, which runs its standard single-squad autopilot; there is no meta-pipeline. This preserves today's behavior exactly.
* **No `mode` flag** → the Federation Coordinator runs its normal per-turn protocol, forwarding any per-turn autonomy tiers to the selected sub-squad(s).

The single opt-in is the `mode=autopilot` input on `/squad-federation` without a target. When present, the Federation Coordinator records the opt-in through the Squad Scribe so the federation-root autopilot-run history file (see *Two-Level Provenance*) carries the per-run opt-in evidence.

## Precondition — the Federation Must Be Built First

Before the meta-pipeline runs, a confirmed federation must exist: `.copilot-tracking/squad/federation.md` and `meta-routing.md` are present, and every targeted sub-squad already has its built squad tree under `members/<name>/` (`team.md` and `routing.md` present). When the federation is missing, the coordinator runs **Federation Init Mode** (propose → confirm → create) from `.github/agents/squad/squad-federation-coordinator.agent.md` to completion — including the user's confirmation of the sub-squad set — and only then enters the meta-pipeline. When the federation exists but a targeted sub-squad is not yet built, the coordinator escalates to run that sub-squad's Init before autopilot sequences it.

Federation autopilot never auto-seeds the federation or a sub-squad roster and never starts a meta-run without a built federation; the opt-in sequences the work, it does not waive the build.

## Meta-Pipeline Contract

Federation autopilot runs the selected sub-squads as an ordered pipeline. Each meta-stage dispatches a sub-squad's single-squad autopilot inner run scoped to `members/<name>/`, waits for its outcome and any raised gate, aggregates the result to the federation level, hands the meta-transition to the Scribe at the federation root, and advances — except where a federation-level Human Gate (below) fires.

1. **Federation plan.** Order the meta-routing-selected sub-squads by declared dependency. Derive the order from the request and the registry (for example, a `product` sub-squad's requirements before an `azure` sub-squad's build), mark independent sub-squads parallel-eligible, and confirm the proposed order with the user at the build or first gate. This meta-stage produces the ordered sub-squad execution script; it does not replace any sub-squad's own Plan stage.
2. **Per-sub-squad inner run.** For each sub-squad in order (or in a parallel batch when independent and the runtime supports concurrent dispatch), run its standard single-squad autopilot pipeline scoped to `members/<name>/` — its own Research, Plan, pre-implementation council, Implement (validator loop and deliverable fan-out included), and Review stages. Each inner run is a first-class Scribe-recorded set of stages under that sub-squad's root, exactly as for a plain autopilot run.
3. **Meta-gate aggregation.** Any Impactful-Action Gate or Risk Gate raised inside *any* sub-squad's inner run surfaces as a **federation-level gate**, attributed to the sub-squad that raised it, using the same most-restrictive-wins posture as the council. The meta-pipeline pauses at the federation level; the human's approval resumes the owning sub-squad's inner run.
4. **Consolidated final-outcome validation.** After every sub-squad completes its Review stage, the federation fires a single `final-outcome` notification summarizing each sub-squad's outcome and waits for one human validation before any release-tier action anywhere. Federation autopilot never auto-releases.

The coordinator advances meta-stage to meta-stage by reading each sub-squad inner run's outcome; it hands every meta-transition to the Scribe, which records it in the federation-root autopilot-run history file and updates the federation `state.json`. The coordinator never authors sub-squad or federation state directly.

## Sub-Squad Execution Order

The Federation plan meta-stage orders sub-squads before any inner run starts:

* **Dependency-first.** When one sub-squad's output feeds another (a `product` sub-squad's requirements consumed by an `azure` sub-squad's build), the producer runs before the consumer. Dependencies are inferred from the request and the registry descriptions in `federation.md`.
* **Parallel when independent.** Sub-squads with no declared dependency between them are marked parallel-eligible and may run their inner autopilot runs concurrently when the runtime supports concurrent dispatch. Sequential execution is the default; parallel runs only when the sub-squads are explicitly independent.
* **Confirmed at the first gate.** The coordinator proposes the inferred order and confirms it with the user at the build or first gate rather than assuming it silently.

Cross-sub-squad handoff of a producer's deliverables to a downstream sub-squad flows through the producer sub-squad's recorded artifacts under `members/<producer>/`, which the downstream sub-squad's inner run consumes as research input.

## Federation Human Gates

Federation Human Gates are the only points where federation autopilot stops and hands control to the human. They reuse the two gate classes from `.github/instructions/squad/squad-autopilot.instructions.md` unchanged, lifted to the meta level.

* A gate raised inside a sub-squad inner run **pauses the whole meta-pipeline** at the federation level, is **attributed to the sub-squad** that raised it, and fires a notification per `.github/instructions/squad/squad-notifications.instructions.md`. The human's approval flows back to the owning sub-squad's inner run, which resumes; the meta-pipeline then continues.
* **Impactful-Action Gate.** Any deploy, `git push` or force-push, PR merge, schema migration, data deletion, destructive infrastructure operation, secret rotation, or user-marked irreversible side effect inside any sub-squad fires the gate at the meta level. Federation autopilot completes all non-impactful work across sub-squads and stops precisely at the impactful step.
* **Risk Gate.** Any `Stop` verdict, any `Risk: High` from `security`/`cost-manager`/`rai`, any `confirm`-tier cost move, any compliance violation, validator divergence, or a cost-ceiling breach inside any sub-squad fires the gate at the meta level.
* **Most-restrictive-wins.** When two sub-squads running in parallel each raise a gate, both surface individually, each attributed to its sub-squad; the meta-pipeline resolves them with the same most-restrictive-wins posture the council uses. Simultaneous gates present as individual, attributed approvals rather than one coalesced approval.

When the approval channel is `github-issue`, a federation gate is approvable remotely from a phone exactly as a single-squad gate is: the coordinator persists the pending gate in the federation `state.json`, fires the notification, and resumes the owning sub-squad only when an authorized approval returns — never on a timeout.

## Federation Cost Ceiling

An optional `cost-ceiling=$X` on a federation autopilot run applies **across the whole federation run**, not per sub-squad. The coordinator tracks the aggregate estimated cost across every sub-squad inner run and escalates through the Risk Gate when the aggregate would exceed the ceiling on the next meta-stage or inner-run cycle, rather than enforcing a separate ceiling inside each sub-squad. Each sub-squad's own consumption ledger under `members/<name>/` is unchanged; the federation-level aggregate is the sum across sub-squads recorded in the federation `state.json` `currentRun`.

## Consolidated Final-Outcome Validation

When the meta-pipeline reaches Consolidated final-outcome validation:

1. The coordinator compiles one federation outcome: for each sub-squad, what it built, its review result, any conditions left open, and the impactful actions awaiting approval; plus the aggregate cost estimate. For any council-gated work inside a sub-squad it includes that sub-squad's Council Verdict **Decision Ref** so the human can open the exact verdict section.
2. The coordinator fires a single `final-outcome` notification to the registered approval channel through `.github/instructions/squad/squad-notifications.instructions.md`. When the channel is `github-issue`, the human can validate the whole federation outcome from a phone. When no channel is configured, the notification degrades to an in-chat summary and is still logged.
3. The coordinator waits for one human validation. The human may approve (releasing the gated impactful actions across sub-squads one by one), request changes (re-entering the owning sub-squad's inner run at the appropriate stage), or stop.

## What Federation Autopilot Does Not Do

* It does not change the single-squad autopilot pipeline. Each sub-squad's inner run is unchanged.
* It does not run a meta-pipeline for a single `squad=` target. A targeted `mode=autopilot` forwards to that one sub-squad exactly as today.
* It does not auto-seed the federation or any sub-squad roster. The build precondition is never waived.
* It does not perform any impactful action without explicit human approval at a federation-level Impactful-Action Gate.
* It does not auto-release: the consolidated final outcome always returns to the human for one validation before any deploy, push, or merge in any sub-squad.
* It does not downgrade a `confirm`-tier action to `auto`. It changes *which sub-squad sequences the work*, not *which actions need a human*.

## References

* `.github/instructions/squad/squad-autopilot.instructions.md`
* `.github/instructions/squad/squad-federation.instructions.md`
* `.github/instructions/squad/squad-council.instructions.md`
* `.github/instructions/squad/squad-autonomous.instructions.md`
* `.github/instructions/squad/squad-notifications.instructions.md`
* `.github/instructions/squad/squad-watch-mode.instructions.md`
* `.github/agents/squad/squad-federation-coordinator.agent.md`
* `.github/agents/squad/squad-coordinator.agent.md`
