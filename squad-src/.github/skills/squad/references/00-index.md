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

This is an on-demand map. Coordinators start with their compact runtime contract;
load only references that contract conditionally requires.

## Which file for which job

| File                                               | Read it when                                                              |
|----------------------------------------------------|---------------------------------------------------------------------------|
| [coordinator-runtime.md](coordinator-runtime.md) | Single/member startup |
| [coordinator-init.md](coordinator-init.md) | Fresh confirmed Init |
| [federation-runtime.md](federation-runtime.md) | Federation startup |
| [state-write-contract.md](state-write-contract.md) | Manual/no-runtime writes |
| [coordinator-legacy.md](coordinator-legacy.md) | Single-squad fallback |
| [federation-coordinator-legacy.md](federation-coordinator-legacy.md) | Federation fallback |
| [profiles-and-packs.md](profiles-and-packs.md) | Roster profiles/packs |
| [roster-catalog.md](roster-catalog.md) | Casting, custom/external roles, upgrades |
| [connector-role-modes.md](connector-role-modes.md) | Bindings/execution; [transport](connector-contract.md) |
| [operating-procedure.md](operating-procedure.md) | Full legacy turn procedure |
| [gates-and-modes.md](gates-and-modes.md) | Active gate/mode sections |
| [requirements-quality.md](requirements-quality.md) | Requirements authoring/review only |
| [federation.md](federation.md) | Federation lifecycle/layout |
| [economy-scribe.md](economy-scribe.md) | Ordinary writes, all routing modes |
| [scribe-cold-charter.md](scribe-cold-charter.md) | Unsupported/cold Scribe work |
| [scribe-procedure.md](scribe-procedure.md) | Cold rules, step map and checks |
| [entry-schemas.md](entry-schemas.md) | Decision/history/state schemas |
| [scribe-payload-template.md](scribe-payload-template.md) | Cold payload fields/order |
| [scribe-cold-init-and-seeding.md](scribe-cold-init-and-seeding.md) | Init/refresh, memory/learnings |
| [scribe-cold-federation.md](scribe-cold-federation.md) | Federation seed/promotion/expansion/history |
| [scribe-cold-gates-and-verdicts.md](scribe-cold-gates-and-verdicts.md) | Verdicts, summaries, notifications |
| [seed-templates.md](seed-templates.md) | Init roster/routing templates |
| [consumption.md](consumption.md) | Ledger, estimator, Cost Preflight |
| [consumption-rates-template.md](consumption-rates-template.md) | Init/reseed rates without the script |
| [model-catalog.md](model-catalog.md) | Capability, pricing, availability |
| [model-benchmarks.md](model-benchmarks.md) | Offline evidence, provenance, and source versions |
| [model-routing.md](model-routing.md) | Applying routing: modes, cells, floors, and identity |
| [model-scoring.md](model-scoring.md) | Policy or evidence audit only |
| [federation-templates.md](federation-templates.md) | Federation creation/expansion: registry, meta-routing, root seeds |
| [coach-discovery.md](coach-discovery.md) | Coach discovery, code/docs/state |

For Scribe, the ordinary hot path reads only `economy-scribe.md`; coordinators
reach this write contract through their runtime. Run the writer directly with
`-Quiet` in all modes. Cold Scribe loads its charter, this index, procedure,
schemas and payload template plus the Cold-File Dispatch Table's required files.
Seed templates remain Init/federation-change-only reads.

## Companion instruction files

These companions apply to squad state only in hosts honoring `applyTo`; unconditional rules belong in references above. Names below resolve to installed instructions, or ported rules in plugin hosts:

* `squad-roster` — roster schema, `### Dispatchability`, Casting Rules, Profiles/Packs (Cast Catalog and External Cast: `roster-catalog.md`).
* `squad-routing` — routing table and escalation rules.
* `squad-discovery-gate` — opt-in pre-work discovery gate (`product`/`full` profiles): depth tiers, offer-once, no unattended runs, Discovery Verdict schema.
* `squad-intake-gate` — conditional intake gate validating requirement/input artifacts, bounded auto-remediation, Intake Readiness Verdict schema.
* `squad-state` — state layout, single-writer ownership, tool-to-mechanism mapping.
* `squad-council` — pre-implementation council: parallel dispatch, most-restrictive-wins, Council Verdict schema.
* `squad-autonomous` — opt-in `auto-validated` tier: bounded re-validation loop, divergence detection, mandatory escalations.
* `squad-autopilot` — opt-in `mode=autopilot` pipeline with Human Gates only on impactful actions and final-outcome validation.
* `squad-notifications` — user-contact capture at build time and the delivery-agnostic ping contract per mode.
* `squad-watch-mode` — event-driven Watch Mode (DR-01): opt-in gates, event-to-intent map, injection-safe payloads, event-scoped sub-squad bootstrap, pull-request deliverable.
* `squad-federation` — opt-in federation of named sub-squads: parameterized squad root, `federation.md`/`meta-routing.md` schemas, detection precedence, two-level single-writer rule.
* `squad-federation-autopilot` — federation-level autopilot meta-pipeline under one set of gates, an aggregate cost ceiling, and one final-outcome validation.
