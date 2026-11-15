---
name: squad-reference-index
description: "Maps squad jobs to reference files and companion instructions."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-26"
---
<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

# Squad Reference Index

On-demand map. Coordinators start with their compact runtime contract and load only conditionally required references.

## Which file for which job

| File | Read it when |
|---|---|
| [coordinator-runtime.md](coordinator-runtime.md) | Single/member startup |
| [coordinator-init.md](coordinator-init.md) | Fresh confirmed Init |
| [roster-expansion.md](roster-expansion.md) | Confirmed additive role/pack expansion |
| [federation-runtime.md](federation-runtime.md) | Federation startup |
| [federation-init.md](federation-init.md) | Fresh confirmed federation Init |
| [state-write-contract.md](state-write-contract.md) | Manual/no-runtime writes |
| [coordinator-legacy.md](coordinator-legacy.md) | Single-squad fallback |
| [federation-coordinator-legacy.md](federation-coordinator-legacy.md) | Federation fallback |
| [profiles-and-packs.md](profiles-and-packs.md) | Roster profiles/packs |
| [roster-catalog.md](roster-catalog.md) | Casting, custom/external roles, upgrades |
| [connector-role-modes.md](connector-role-modes.md) | Bindings/execution; [transport](connector-contract.md) |
| [builder-workflows.md](builder-workflows.md) | Connector or external endpoint builder flow |
| [foundry-blueprint.md](foundry-blueprint.md) | `foundry` role guidance |
| [fabric-blueprint.md](fabric-blueprint.md) | Fabric |
| [foundry-platform-options.md](foundry-platform-options.md) | `foundry` platform guidance |
| [operating-procedure.md](operating-procedure.md) | Full legacy turn procedure |
| [gates-and-modes.md](gates-and-modes.md) | Active gate/mode sections |
| [requirements-quality.md](requirements-quality.md) | Requirements authoring/review only |
| [federation.md](federation.md) | Federation lifecycle/layout |
| [economy-scribe.md](economy-scribe.md) | Ordinary writes, all routing modes |
| [verdict-writer.md](verdict-writer.md) | Supported Council, Intake Readiness and Discovery Verdicts |
| [scribe-cold-charter.md](scribe-cold-charter.md) | Unsupported/cold Scribe work |
| [scribe-procedure.md](scribe-procedure.md) | Cold rules, step map and checks |
| [entry-schemas.md](entry-schemas.md) | Decision/history/state schemas |
| [scribe-payload-template.md](scribe-payload-template.md) | Cold payload fields/order |
| [scribe-cold-init-and-seeding.md](scribe-cold-init-and-seeding.md) | Init/refresh, memory/learnings |
| [scribe-cold-federation.md](scribe-cold-federation.md) | Unsupported federation lifecycle, repairs, root history |
| [scribe-cold-gates-and-verdicts.md](scribe-cold-gates-and-verdicts.md) | Unsupported verdict fallback, summaries, notifications |
| [seed-templates.md](seed-templates.md) | Init roster/routing templates |
| [consumption.md](consumption.md) | Ledger, exact-session journal, estimator, Cost Preflight |
| [business-value-measurement.md](business-value-measurement.md) | FinOps benefit claims, nine categories, evidence rules |
| [value-valuation.md](value-valuation.md) | Stated monetary valuation formulas and CLI |
| [consumption-rates-template.md](consumption-rates-template.md) | Init/reseed rates without script |
| [model-catalog.md](model-catalog.md) | Capability, pricing, availability |
| [model-benchmarks.md](model-benchmarks.md) | Offline evidence, provenance, source versions |
| [model-routing.md](model-routing.md) | Applying routing: modes, cells, floors, identity |
| [model-scoring.md](model-scoring.md) | Policy or evidence audit only |
| [federation-templates.md](federation-templates.md) | Federation registry, meta-routing, root seeds |
| [coach-discovery.md](coach-discovery.md) | Coach only: discover code, docs, entrypoints, state |

For Scribe, the ordinary hot path reads only `economy-scribe.md`; coordinators reach it via their runtime (`-Quiet` in all modes). Cold Scribe loads its charter, this index, procedure, schemas, payload template, and the Cold-File Dispatch Table's required files. Seed templates are Init/federation-only reads.

## Companion instruction files

These apply via `applyTo` where supported; unconditional rules live in references above (installed instructions or ported plugin rules):

* `squad-roster` — roster schema, `### Dispatchability`, Casting Rules, Profiles/Packs (Cast/External Catalog: `roster-catalog.md`).
* `squad-routing` — routing table and escalation rules.
* `squad-discovery-gate` — opt-in discovery gate (`product`/`full`): depth tiers, offer-once, Discovery Verdict schema.
* `squad-intake-gate` — conditional intake gate, bounded auto-remediation, Intake Readiness Verdict schema.
* `squad-state` — state layout, single-writer ownership, tool-to-mechanism mapping.
* `squad-council` — pre-implementation council, most-restrictive-wins, Council Verdict schema.
* `squad-autonomous` — opt-in `auto-validated` tier: bounded re-validation loop, mandatory escalations.
* `squad-autopilot` — opt-in `mode=autopilot` pipeline with Human Gates on impactful actions and final validation.
* `squad-notifications` — user-contact capture and delivery-agnostic ping contract.
* `squad-watch-mode` — event-driven Watch Mode (DR-01): gates, event-to-intent map, sub-squad bootstrap, PR deliverable.
* `squad-federation` — opt-in federation: parameterized squad root, `federation.md`/`meta-routing.md` schemas, two-level single-writer rule.
* `squad-federation-autopilot` — federation autopilot meta-pipeline under shared gates, aggregate ceiling, and final validation.
