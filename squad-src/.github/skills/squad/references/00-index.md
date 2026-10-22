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

Read this index first; load only references your Skill Reference Contract names or conditionally requires.

## Which file for which job

| File                                               | Read it when                                                              |
|----------------------------------------------------|---------------------------------------------------------------------------|
| [profiles-and-packs.md](profiles-and-packs.md)     | Seeding or amending a roster: profile choice, packs, which roles exist    |
| [roster-catalog.md](roster-catalog.md)             | Casting a role, recasting after an HVE Core upgrade, applying/registering a pack's external agents, resolving an external role, or assembling a custom roster |
| [operating-procedure.md](operating-procedure.md)   | Running a turn: Init, Route, ledger reconciliation, Decide, Handoff       |
| [gates-and-modes.md](gates-and-modes.md)           | Gates — discovery, intake, council, implementation — and autonomy modes   |
| [requirements-quality.md](requirements-quality.md) | Only BRD/PRD or requirements authoring/review; not startup or code-only reviews |
| [federation.md](federation.md)                     | The squad root is a federation: layout, precedence, federation modes      |
| [economy-scribe.md](economy-scribe.md)             | Ordinary handoffs, all modes: minimal JSON, synchronous `-Quiet`, status verification and failures |
| [scribe-cold-charter.md](scribe-cold-charter.md)    | Full legacy charter for cold init, verdicts, memory, notifications, ceiling slots, federation changes, summaries, unsupported operations |
| [scribe-procedure.md](scribe-procedure.md)         | Writing squad state, Scribe only: Non-Negotiable Rules, payload-to-step rules, Cold-File Dispatch Table, Write-Completeness Self-Check |
| [entry-schemas.md](entry-schemas.md)               | Cold writes and schema reference: `decisions.md` base shape, `history/<agent>.md`, state.json |
| [scribe-payload-template.md](scribe-payload-template.md) | Filling or reading the Scribe hand-off payload: field order and the byte-stable-prefix / volatile-tail section order |
| [scribe-cold-init-and-seeding.md](scribe-cold-init-and-seeding.md) | Scribe only, initialization or memory payload: the full state-tree seed and Repository Memory and Learning Promotion |
| [scribe-cold-federation.md](scribe-cold-federation.md) | Scribe only, promotion, expansion, or a federation-level autopilot-run-summary or history payload |
| [scribe-cold-gates-and-verdicts.md](scribe-cold-gates-and-verdicts.md) | Scribe only, a Council/Intake/Discovery Verdict, an autonomous-loop summary, a single-squad autopilot-run summary, or a notification write |
| [seed-templates.md](seed-templates.md)             | Stamping first-run state, Init only: `team.md`, `routing.md`|
| [consumption.md](consumption.md)                   | Recording or estimating cost: ledger templates, the estimator, and Cost Preflight |
| [consumption-rates-template.md](consumption-rates-template.md) | Scribe only, initialization or a Step 7.1 reseed: the cold seed template for `consumption-rates.md` |
| [model-catalog.md](model-catalog.md)               | Routing a dispatch to a specific model: declared capability, pricing, and host-availability precedence |
| [model-routing.md](model-routing.md)               | Applying `routing=` (all modes): modes, the Model column, fit ranking, floors, and identity bullets |
| [federation-templates.md](federation-templates.md) | Creating or expanding a federation: registry, meta-routing, root files    |

The ordinary hot path reads only `economy-scribe.md`; coordinators run its validated writer directly with `-Quiet` in all modes. Scribe uses it too. Cold operations first read `scribe-cold-charter.md`, then `00-index.md`, `scribe-procedure.md`, `entry-schemas.md`, and `scribe-payload-template.md` plus conditional files required by the Cold-File Dispatch Table. Use small script JSON for ordinary writes; the full template only for cold handoffs. Seed templates remain Init/federation-change-only reads.

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
