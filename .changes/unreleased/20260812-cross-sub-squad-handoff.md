---
bump: patch
type: Fixed
---

- **A federated sub-squad could not reach another's work, and nothing said how it should.** A run
  scoped to `members/azure/` resolves every path under its own root, so a `product` sub-squad's PRD
  at `members/product/plans/` was invisible to it — and a sub-squad's inner run never reads
  federation-level state, so the federation `decisions.md` was not a discovery mechanism either. The
  only prior mention of a handoff was one line in the federation autopilot instructions, with no
  mechanism and nothing for an interactive turn. A new *Cross-Sub-Squad Handoff* contract makes the
  Squad Federation Coordinator — the only component that sees both roots — resolve the producer's
  artifacts from its `team.md` deliverable roots, **verify each file on disk** rather than infer it,
  and hand them to the consumer as explicit read-only `inputs=` paths. The producer runs to
  completion first, the pair is not parallel-eligible for that turn, the consumer never writes across
  the boundary, and the handoff is recorded in the federation `decisions.md` so a two-sub-squad
  outcome stays reconstructable (`squad-src/.github/instructions/squad/squad-federation.instructions.md`,
  `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`,
  `squad-src/.github/agents/squad/squad-coordinator.agent.md`,
  `squad-src/.github/instructions/squad/squad-federation-autopilot.instructions.md`).
- **A missing upstream artifact had no defined recovery.** Stopping is the safety property, not the
  outcome, and a consumer left to work the requirements out for itself returns a complete-looking
  deliverable built on requirements the producer never agreed — a divergence nothing in the output
  reveals. A new recovery ladder mirrors the bounded auto-remediation loop of the intake gate rather
  than inventing a second vocabulary: run the registered producer and **resume the consumer in the
  same turn**, or re-dispatch only the producing stage when the artifact is partial or stale, or
  offer Federation Expansion when no sub-squad owns the artifact, or take a user-supplied path or a
  user's explicit decision to proceed with the gap recorded as an assumption. Interactive turns state
  what will run and wait; autopilot and Watch Mode proceed unasked, because dependency-first ordering
  was already settled at the plan meta-stage. The loop is capped at one producer run per handoff per
  turn, and every recovery dispatch is a Scribe-recorded stage with its own consumption block
  (`squad-src/.github/instructions/squad/squad-federation.instructions.md`,
  `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`).
