---
name: squad
description: 'Run or initialize a squad with deterministic scripts, native HVE agent dispatch, gated persistence and verified state. Use when operating .copilot-tracking/squad/.'
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-25"
---

# Squad Operating Procedure

## Overview

The user-invocable Squad Coordinator dispatches HVE Core agents and persists roster, routing, decisions, and history under `.copilot-tracking/squad/`; every squad verb reuses an existing HVE Core mechanism.

Compact contracts and scripts own routine coordination; cold procedures preserve
compatibility. Instructions use artifact-specific scopes, not all squad state.

## Prerequisites

* A `runSubagent` or `task` tool is available so the coordinator can dispatch `user-invocable: false` agents.
* The deployed HVE Core cast exists (System Architecture Reviewer, Security Planner, RAI Planner, UX UI Designer, Finding Deep Verifier, PowerPoint Subagent) plus the squad-owned charters (Squad Scribe, Squad Researcher, Squad Lead, Squad Implementor, Squad Reviewer, Squad Challenger, Squad Technical Writer, Squad Prompt Engineer).
* Each selected work endpoint resolves to an installed, dispatchable agent. Step 1b checks `Squad Connector` for a connector default; its consumer endpoint runs externally.
* The memory tool is available for durable per-agent notes under `/memories/repo/`.

## Procedure

The stages are **init**, **route**, **decide**, **handoff**. Scripts prepare Init,
schedule dependencies, persist supported state and verify completion. Native
agents do specialist work; cold Scribe handles unsupported writes. Schemas and gates remain.

For Squad Coordinator start at [coordinator-runtime.md](references/coordinator-runtime.md);
for Federation Coordinator start at [federation-runtime.md](references/federation-runtime.md).
Read [coordinator-init.md](references/coordinator-init.md) only when seeding.
Other roles follow their own Skill Reference Contract; [00-index.md](references/00-index.md)
is an on-demand map, not a mandatory coordinator startup read.

| Reference                                                     | Covers                                                                         |
|---------------------------------------------------------------|--------------------------------------------------------------------------------|
| [coordinator-runtime.md](references/coordinator-runtime.md) | Compact single/member turn contract and script entrypoints |
| [coordinator-init.md](references/coordinator-init.md) | Confirmed choices to deterministic staged initialization |
| [federation-runtime.md](references/federation-runtime.md) | Compact meta-routing, dependencies, root persistence and proof |
| [state-write-contract.md](references/state-write-contract.md) | Cold manual/no-runtime schema and accounting detail |
| [coordinator-legacy.md](references/coordinator-legacy.md) | Full no-runtime single-squad fallback |
| [federation-coordinator-legacy.md](references/federation-coordinator-legacy.md) | Full no-runtime federation fallback |
| [00-index.md](references/00-index.md)                         | Which file to read for which job, and the companion instruction files          |
| [profiles-and-packs.md](references/profiles-and-packs.md)     | Squad profiles and add-on packs                                                |
| [foundry-blueprint.md](references/foundry-blueprint.md)       | `foundry` role owners/evidence                                                  |
| [foundry-platform-options.md](references/foundry-platform-options.md) | `foundry` platform choices                                         |
| [operating-procedure.md](references/operating-procedure.md)   | Init, Route, ledger reconciliation, Decide, Handoff, tool-to-mechanism mapping |
| [gates-and-modes.md](references/gates-and-modes.md)           | Discovery, intake, council, implementation gates; autopilot and autonomy modes |
| [federation.md](references/federation.md)                     | Federation layout, deterministic Init, detection, and modes                     |
| [economy-scribe.md](references/economy-scribe.md)             | Ordinary writer in every routing mode: minimal JSON, quiet status, serialized writes, fail-closed recovery |
| [scribe-cold-charter.md](references/scribe-cold-charter.md)   | Full legacy Scribe charter; cold operations only, with required procedure/schema/payload reads |
| [scribe-procedure.md](references/scribe-procedure.md)         | The Squad Scribe write procedure, Non-Negotiable Rules, and Cold-File Dispatch Table — Scribe only |
| [entry-schemas.md](references/entry-schemas.md)               | Recurring write shapes: decision base entry, history, state.json          |
| [scribe-payload-template.md](references/scribe-payload-template.md) | The Scribe hand-off payload both coordinators fill, byte-stable-prefix ordered |
| [scribe-cold-init-and-seeding.md](references/scribe-cold-init-and-seeding.md) | Full state-tree seed and Repository Memory promotion — Scribe only, conditional |
| [scribe-cold-federation.md](references/scribe-cold-federation.md) | Unsupported-host federation lifecycle fallbacks, repairs, and federation-level summaries — Scribe only, conditional |
| [scribe-cold-gates-and-verdicts.md](references/scribe-cold-gates-and-verdicts.md) | Verdict schemas, autonomous-loop and autopilot-run summaries, notifications.md — Scribe only, conditional |
| [seed-templates.md](references/seed-templates.md)             | First-run state templates: team.md and routing.md                              |
| [consumption.md](references/consumption.md)                   | Consumption ledger templates, the cost estimator, and Cost Preflight           |
| [consumption-rates-template.md](references/consumption-rates-template.md) | Cold seed template for consumption-rates.md: rate tables, tier fallback, calibration |
| [model-catalog.md](references/model-catalog.md)               | Declared model capability, pricing, and host-availability precedence           |
| [model-benchmarks.md](references/model-benchmarks.md)         | Pinned benchmark knowledge base, source versions, and provenance for `ranked`  |
| [model-routing.md](references/model-routing.md)               | Opt-in modes, Model cells, capability-first ranking, floors, and identity bullets |
| [model-scoring.md](references/model-scoring.md) | Cold scoring methodology: policy changes or evidence audit only |
| [economy-mode.md](references/economy-mode.md)                 | Only under `Model routing: economy`: consent, role allowlist, economy pick, one escalation |
| [federation-templates.md](references/federation-templates.md) | Federation-root seed templates                                                 |

Files at the skill root that are not part of this split — `learnings/shared-learnings.md`, `squad-watch.workflow.yml`, `github-approval-watcher.workflow.yml`, `mcp.template.json`, `mcp-server.template.json`, and `squad-task.issue-template.yml` — keep their existing paths.

## Attribution

Brought to you by the `hve-squad` package, built on Microsoft HVE Core agents and conventions.
