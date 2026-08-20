---
name: squad
description: 'Operating procedure for the HVE Core Squad Coordinator: initialize squad state from seed templates, route requests to a cast of deployed HVE Core agents in parallel, record decisions and history through the Squad Scribe, and synthesize a response. Use when running, initializing, or maintaining a squad under .copilot-tracking/squad/.'
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-06-10"
---

# Squad Operating Procedure

## Overview

The squad is a user-invocable Squad Coordinator that dispatches a reusable cast of deployed HVE Core agents in parallel and persists roster, routing, decisions, and per-agent history under `.copilot-tracking/squad/`. There is no separate runtime: every squad verb is a thin convention over an existing HVE Core mechanism.

This skill packages the coordinator's operating procedure and the seed templates it stamps out on first run. The procedure lives in the reference files listed under [Procedure](#procedure) below; the eleven companion instruction files that auto-apply when squad state is touched are catalogued in [references/00-index.md](references/00-index.md).

## Prerequisites

* A `runSubagent` or `task` tool is available so the coordinator can dispatch `user-invocable: false` agents.
* The deployed HVE Core cast exists (System Architecture Reviewer, Security Planner, RAI Planner, UX UI Designer, Finding Deep Verifier, PowerPoint Subagent) plus the squad-owned charters (Squad Scribe, Squad Researcher, Squad Lead, Squad Implementor, Squad Reviewer, Squad Challenger, Squad Technical Writer, Squad Prompt Engineer).
* Every roster Primary resolves to an installed agent that does **not** set `disable-model-invocation: true`; the coordinator's Step 1b roster-resolution precheck confirms this before any dispatch.
* The memory tool is available for durable per-agent notes under `/memories/repo/`.

## Procedure

The coordinator runs four stages each turn: **init**, **route**, **decide**, and **handoff**. Only the coordinator initiates state changes, and only the Squad Scribe performs the writes.

The procedure is split across the reference files below so that each agent loads only what its role needs. Read [references/00-index.md](references/00-index.md) first, then read the files your Skill Reference Contract names — not all of them.

| Reference                                                     | Covers                                                                         |
|---------------------------------------------------------------|--------------------------------------------------------------------------------|
| [00-index.md](references/00-index.md)                         | Which file to read for which job, and the companion instruction files          |
| [profiles-and-packs.md](references/profiles-and-packs.md)     | Squad profiles and add-on packs                                                |
| [operating-procedure.md](references/operating-procedure.md)   | Init, Route, ledger reconciliation, Decide, Handoff, tool-to-mechanism mapping |
| [gates-and-modes.md](references/gates-and-modes.md)           | Discovery, intake, council, implementation gates; autopilot and autonomy modes |
| [federation.md](references/federation.md)                     | Federation layout, detection precedence, and federation modes                  |
| [scribe-procedure.md](references/scribe-procedure.md)         | The Squad Scribe write procedure — Scribe only                                 |
| [entry-schemas.md](references/entry-schemas.md)               | Recurring write shapes: decision and verdict entries, history, state.json      |
| [seed-templates.md](references/seed-templates.md)             | First-run state templates: team.md and routing.md                              |
| [consumption.md](references/consumption.md)                   | Consumption ledger templates and the cost estimator                            |
| [federation-templates.md](references/federation-templates.md) | Federation-root seed templates                                                 |

Files at the skill root that are not part of this split — `learnings/shared-learnings.md`, `squad-watch.workflow.yml`, `github-approval-watcher.workflow.yml`, `mcp.template.json`, `mcp-server.template.json`, and `squad-task.issue-template.yml` — keep their existing paths.

## Attribution

Brought to you by the `hve-squad` package, built on Microsoft HVE Core agents and conventions.
