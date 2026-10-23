---
name: squad-reference-index
description: "Maps squad jobs to reference files and companion instructions."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-09-27"
---

# Squad Reference Index

Read this index first, then only references your Skill Reference Contract names or conditionally requires. Unneeded whole-file reads cost attention.

## Which file for which job

| File                                               | Read it when                                                              |
|----------------------------------------------------|---------------------------------------------------------------------------|
| [profiles-and-packs.md](profiles-and-packs.md)     | Roster seeding/changes: profiles, packs, roles |
| [roster-catalog.md](roster-catalog.md)             | Casting/upgrades, custom/external roles, pack registration/resolution |
| [connector-role-modes.md](connector-role-modes.md) | Setup/refresh, bindings, execution; [shim transport](connector-contract.md) |
| [operating-procedure.md](operating-procedure.md)   | Running a turn: Init, Route, ledger reconciliation, Decide, Handoff       |
| [gates-and-modes.md](gates-and-modes.md)           | Gates — discovery, intake, council, implementation — and autonomy modes   |
| [federation.md](federation.md)                     | The squad root is a federation: layout, precedence, federation modes      |
| [scribe-procedure.md](scribe-procedure.md)         | Scribe state writes: rules, payload/step map, cold reads, completeness |
| [entry-schemas.md](entry-schemas.md)               | Ordinary Scribe writes: decision/history/state schemas |
| [scribe-payload-template.md](scribe-payload-template.md) | Every hand-off: fields and stable-prefix/volatile-tail order |
| [scribe-cold-init-and-seeding.md](scribe-cold-init-and-seeding.md) | Scribe Init or memory: state seeds and memory/learning promotion |
| [scribe-cold-federation.md](scribe-cold-federation.md) | Scribe promotion, expansion, federation autopilot summary/history |
| [scribe-cold-gates-and-verdicts.md](scribe-cold-gates-and-verdicts.md) | Scribe verdict, loop or single-squad autopilot summary, notification |
| [seed-templates.md](seed-templates.md)             | Stamping first-run state, Init only: `team.md` and `routing.md`           |
| [consumption.md](consumption.md)                   | Recording or estimating cost: ledger templates, the estimator, and Cost Preflight |
| [consumption-rates-template.md](consumption-rates-template.md) | Scribe only, initialization or a Step 7.1 reseed: the cold seed template for `consumption-rates.md` |
| [model-catalog.md](model-catalog.md)               | Model routing: declared capability, prices, host precedence |
| [model-benchmarks.md](model-benchmarks.md) | Offline evidence, provenance, and source versions |
| [model-routing.md](model-routing.md) | Applying routing: modes, cells, floors, and identity |
| [model-scoring.md](model-scoring.md) | Policy or evidence audit only |
| [federation-templates.md](federation-templates.md) | Federation creation/expansion: registry, meta-routing, root seeds |
| [coach-discovery.md](coach-discovery.md)           | Coach only: discover current code, documentation, entrypoints, and state without a feature-specific playbook |

The Scribe reads `00-index.md`, `scribe-procedure.md`, `entry-schemas.md`, and `scribe-payload-template.md` on every turn — this hot core replaced a heavier unconditional set so the common case reads less — and reads every other file above, including the three `scribe-cold-*.md` files, only when the turn's payload calls for it per the Cold-File Dispatch Table in `scribe-procedure.md`. The coordinators read `seed-templates.md` and `federation-templates.md` only to verify deliverable roots during Init or a federation change, and fill `scribe-payload-template.md` on every hand-off.

## Companion instruction files

The `squad` skill complements eleven instruction files that auto-apply when squad state is touched. Their `applyTo` globs only fire in a host that loads modular instructions, so a rule that must hold unconditionally belongs in a reference file above, not only here.

* `.github/instructions/squad/squad-roster.instructions.md` — roster schema, `### Dispatchability`, Casting Rules, and Squad Profiles/Packs; the Cast Catalog and External Cast are canonical in `references/roster-catalog.md`.
* `.github/instructions/squad/squad-routing.instructions.md` — routing table and escalation rules.
* `.github/instructions/squad/squad-discovery-gate.instructions.md` — opt-in pre-work discovery gate, scoped to the `product` and `full` profiles, that brainstorms a brief when a turn has no requirement or input artifact to build on, with depth tiers, an offer-once rule, an unattended-run prohibition, and the Discovery Verdict schema.
* `.github/instructions/squad/squad-intake-gate.instructions.md` — conditional pre-work intake gate that validates requirement and input artifacts before planning or implementation, with a bounded auto-remediation loop and the Intake Readiness Verdict schema.
* `.github/instructions/squad/squad-state.instructions.md` — state layout, single-writer ownership, and tool-to-mechanism mapping.
* `.github/instructions/squad/squad-council.instructions.md` — pre-implementation council protocol with parallel dispatch, most-restrictive-wins synthesis, and the Council Verdict schema.
* `.github/instructions/squad/squad-autonomous.instructions.md` — opt-in `auto-validated` autonomy tier with a bounded re-validation loop, divergence detection, and mandatory escalation triggers.
* `.github/instructions/squad/squad-autopilot.instructions.md` — opt-in `mode=autopilot` full pipeline (research→plan→implement→review) with Human Gates only on impactful actions and final-outcome validation.
* `.github/instructions/squad/squad-notifications.instructions.md` — user-contact capture at squad build time and the delivery-agnostic notification (ping) contract per mode.
* `.github/instructions/squad/squad-watch-mode.instructions.md` — event-driven Watch Mode (DR-01) trigger contract: opt-in gates, event-to-intent map, injection-safe payloads, the event-scoped sub-squad bootstrap, and the pull-request deliverable.
* `.github/instructions/squad/squad-federation.instructions.md` — opt-in federation of named sub-squads under one repo: the parameterized squad root, the registry (`federation.md`) and meta-routing (`meta-routing.md`) schemas, detection precedence, and the two-level single-writer rule.
* `.github/instructions/squad/squad-federation-autopilot.instructions.md` — opt-in federation-level autopilot: the meta-pipeline (`mode=autopilot` with no `squad=` target) that orders sub-squad autopilot runs under one set of federation gates, an aggregate cost ceiling, and one consolidated final-outcome validation.
