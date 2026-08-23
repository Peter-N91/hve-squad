---
bump: patch
type: Fixed
---

- **Autopilot decided the Implement stage's shape from a list of seven role names.** Deliverable
  fan-out engaged only when the roster carried two or more of `analyst`, `product-owner`, `designer`,
  `experimenter`, `presenter`, `technical-writer`, `data-scientist` — which is `product` and `full`,
  and nothing else. Every other profile was classified as a single `developer` build regardless of
  what its roster actually owned.

  An `azure` roster owns nine artifact roots. A live run produced a target architecture, an IaC
  scaffold, a cost model, a security review, and a migration sequence — five specialist artifacts —
  under a classification that says its plan is always a single build. It improvised a fan-out the
  pipeline does not define, so none of the per-dispatch recording rules that belong to the fan-out
  path applied: it reported ten stages and left no `history/<agent>.md` behind any of them.

  Fan-out now engages when the plan's deliverable list names **two or more artifact-owning roles** —
  a roster row whose `Deliverable Root` names a real path, counting every one except `researcher`,
  `lead`, and `tester`, which own the Research, Plan, and Review stages instead. The test is read
  off `team.md` rather than off a profile name, so a consumer who edited a root or hired an extra
  specialist is judged on the roster they actually have. A plan naming one candidate stays the
  unchanged single-`developer` shape, which is the ordinary case for `default`
  (`squad-roster.instructions.md`, `squad-autopilot.instructions.md`, `gates-and-modes.md`,
  `squad-coordinator.agent.md`, `squad-lead.agent.md`).

  The narrower term **deliverable-producing role** survives and now names one thing only: the roles
  whose output the Implementation Gate treats as the turn's substantive output alongside `developer`.
  That gate is unchanged.
