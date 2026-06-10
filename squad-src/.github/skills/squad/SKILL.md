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

This skill packages the coordinator's operating procedure and the seed templates it stamps out on first run. It complements three instruction files that auto-apply when squad state is touched:

* `.github/instructions/squad/squad-roster.instructions.md` — roster schema and cast catalog.
* `.github/instructions/squad/squad-routing.instructions.md` — routing table and escalation rules.
* `.github/instructions/squad/squad-state.instructions.md` — state layout, single-writer ownership, and tool-to-mechanism mapping.

## Prerequisites

* A `runSubagent` or `task` tool is available so the coordinator can dispatch `user-invocable: false` agents.
* The deployed HVE Core cast exists (Task Researcher, Task Planner, Task Implementor, Task Reviewer, System Architecture Reviewer, Security Planner, RAI Planner, UX UI Designer, Finding Deep Verifier) plus the Squad Scribe.
* The memory tool is available for durable per-agent notes under `/memories/repo/`.

## Procedure

The coordinator runs four stages each turn: **init**, **route**, **decide**, and **handoff**. Only the coordinator initiates state changes, and only the Squad Scribe performs the writes.

### Squad Profiles

A profile is a curated subset of the cast tailored to a kind of project. The coordinator seeds only the profile's members into `team.md`, and the routing table is filtered to those roles. The `scribe` role is always included. Profiles are defined canonically in `.github/instructions/squad/squad-roster.instructions.md`; the catalog below mirrors them.

| Profile        | Members                                                  | Use When                                                   |
|----------------|----------------------------------------------------------|------------------------------------------------------------|
| `default`      | lead, researcher, developer, tester, scribe              | General-purpose work; recommended starting point           |
| `full`         | all 10 deployed roles                                    | Complex, cross-cutting projects that need every discipline  |
| `security`     | security, rai, fact-checker, researcher, scribe          | Security, threat-modeling, and responsible-AI focus         |
| `design`       | designer, researcher, lead, tester, scribe               | UX/UI and product-design focus                              |
| `architecture` | architect, researcher, lead, developer, scribe           | System design and architecture focus                        |

### Init

Run once per project, then verify on every turn. Init Mode mirrors a propose → confirm → create flow and never writes files before the user confirms.

1. Check for `.copilot-tracking/squad/team.md` and `.copilot-tracking/squad/routing.md`.
2. When either file is missing, **propose**: discover the project (languages, frameworks, tests, IaC, security/AI markers) read-only, then recommend a profile using the precedence in the roster's *Profile Selection* (explicit `profile=` hint → discovery inference → `default`). Present the recommended profile, its roles, and why it fits, and let the user accept, switch profiles, add or remove roles, or ask for more detail.
3. On **confirm**, hand the chosen roster to the Squad Scribe to **create**: `team.md` from the confirmed profile's members, `routing.md` from the default routing rules filtered to that roster, plus `decisions.md`, `state.json`, and a `history/` directory.
4. Confirm the roster and routing table are present before classifying the request. The coordinator never writes these files itself.

### Route

1. Read `team.md` and `routing.md`.
2. Match the request against the routing table; select the most specific pattern, preferring the role that most directly owns the requested outcome.
3. Resolve each matched role to a deployed agent through the roster. A role marked **thin charter needed** has no deployed agent — escalate instead of substituting.
4. Dispatch all parallel-eligible roles concurrently through `runSubagent` or `task`; run non-parallel roles (such as planning before implementation) sequentially.
5. Apply cost-first model selection: prefer the `fast` tier for read-heavy `auto` roles and reserve the `default` tier for reasoning-heavy `confirm` roles. A user tier hint overrides the per-role default for the turn.

### Decide

1. Collect each dispatched agent's structured findings and reconcile conflicts.
2. Hand the turn's decision and rationale to the Squad Scribe, which appends to `decisions.md` (append-only).
3. When a decision is architecturally significant, additionally capture it as an Architecture Decision Record via the `adr-author` skill and reference that ADR from the decision entry.
4. Persist durable, role-scoped learnings to `/memories/repo/squad-<agent>.md` through the Squad Scribe and the memory tool.

### Handoff

1. Hand each dispatched agent's request and outcome to the Squad Scribe, which appends to `history/<agent>.md` (append-only).
2. Synthesize the collected findings into a concise answer for the user.
3. Escalate to the user — rather than acting — when the matched rule is at the `escalate` tier, no pattern matches with reasonable confidence, a role resolves to **thin charter needed**, or two rules conflict with no clearly more specific match. State the ambiguity, list the candidate roles, and ask the user to choose.

## Tool-to-Mechanism Mapping

| Squad verb       | HVE Core mechanism                                                                                       |
|------------------|----------------------------------------------------------------------------------------------------------|
| `squad_route`    | Dispatch the assigned role via `runSubagent` / `task` against a `user-invocable: false` agent             |
| `squad_decide`   | Append the decision and rationale to `decisions.md`; optionally record an ADR via the `adr-author` skill  |
| `squad_memory`   | Write durable per-agent notes with the memory tool to `/memories/repo/squad-<agent>.md`                   |
| `squad_escalate` | Apply the escalate-to-user convention from the routing rules before any role acts                         |

## Seed Templates

The coordinator hands these templates to the Squad Scribe on first run, after the user confirms a profile in Init Mode. They stay consistent with the three squad instruction files: `team.md` holds the confirmed profile's members (the full cast catalog shown below is the `full` profile), `routing.md` mirrors the default routing rules filtered to the seeded roster, and the write semantics match the state layout (`decisions.md` and `history/<agent>.md` are append-only; `team.md`, `routing.md`, and `state.json` use replace semantics).

### team.md

Seeded from the confirmed profile's members; the template below shows the `full` profile (the entire cast catalog). For other profiles, only the profile's rows are written. The role-to-agent relationship is many-to-many: each role names one **Primary** agent the coordinator dispatches by default plus optional **Alternate** agents it resolves to per the cast catalog's Selection Cue (see `squad-roster.instructions.md`). The `devrel` role has no deployed HVE Core agent and is left as **thin charter needed** until a charter is authored.

```markdown
---
description: "Squad roster: roles and the deployed HVE Core agents that fill them"
---

# Squad Roster

## Members

| Role         | Agent Name (Primary)         | Alternate Agents                                       | Invocation         | Model Tier              |
|--------------|------------------------------|--------------------------------------------------------|--------------------|-------------------------|
| lead         | Task Planner                 | RPI Agent, Phase Implementor, Task Challenger          | runSubagent / task | default                 |
| researcher   | Task Researcher              | Researcher Subagent, Codebase Profiler, Meeting Analyst | runSubagent / task | fast                    |
| developer    | Task Implementor             | Phase Implementor                                      | runSubagent / task | default                 |
| tester       | Task Reviewer                | Code Review Full, PR Review, Plan Validator            | runSubagent / task | fast                    |
| architect    | System Architecture Reviewer | Arch Diagram Builder, ADR Creator                      | runSubagent / task | default                 |
| security     | Security Planner             | Security Reviewer, SSSC Planner, Finding Deep Verifier | runSubagent / task | default                 |
| rai          | RAI Planner                  | —                                                      | runSubagent / task | default                 |
| designer     | UX UI Designer               | DT Coach, DT Learning Tutor                            | runSubagent / task | default                 |
| fact-checker | Finding Deep Verifier        | —                                                      | runSubagent / task | fast                    |
| scribe       | Squad Scribe                 | Memory                                                 | runSubagent / task | fast                    |
| devrel       | —                            | —                                                      | —                  | — (thin charter needed) |
```

### routing.md

Seeded from the default routing rules. Each rule points at a role that exists in `team.md`.

```markdown
---
description: "Squad routing: request patterns mapped to roles, autonomy tiers, and parallel eligibility"
---

# Squad Routing

| Pattern / Keyword                          | Role(s)                      | Autonomy Tier | Parallel-Eligible |
|--------------------------------------------|------------------------------|---------------|-------------------|
| research, investigate, explore, find out   | Task Researcher              | auto          | yes               |
| plan, break down, sequence, design plan    | Task Planner                 | confirm       | no                |
| implement, build, code, fix                | Task Implementor             | confirm       | no                |
| review, validate, check quality            | Task Reviewer                | auto          | yes               |
| security, threat, vulnerability, STRIDE    | Security Planner             | confirm       | yes               |
| design, UX, UI, wireframe, accessibility   | UX UI Designer               | confirm       | yes               |
| architecture, system design, components    | System Architecture Reviewer | auto          | yes               |
| responsible AI, RAI, fairness, harm        | RAI Planner                  | confirm       | yes               |
| verify finding, confirm claim, fact-check  | Finding Deep Verifier        | auto          | yes               |
```

### decisions.md

Append-only log. The header is written once; every decision is appended below it and prior entries are never edited.

```markdown
---
description: "Append-only log of squad decisions and their rationale"
---

# Squad Decisions

Entries are appended below in chronological order. Each entry records the decision, its rationale, the turn it was made on, and a reference to an ADR when the decision is architecturally significant. Prior entries are never edited or removed.

<!-- Append new decision entries below this line. -->
```

### history/<agent>.md

One append-only file per dispatched agent. Replace `<agent>` with the dispatched agent's name (for example, `history/Task Researcher.md`). The header is created with the file; dispatch records are appended.

```markdown
---
description: "Append-only dispatch history for a single squad agent"
---

# History: <agent>

Each entry records a request this agent handled, the findings or outcome it returned, and the turn it was dispatched on. Entries are appended in chronological order and never edited.

<!-- Append new dispatch entries below this line. -->
```

### state.json

Machine-readable squad status. Uses replace semantics — the coordinator overwrites it (through the Squad Scribe) as the squad advances.

```json
{
  "schemaVersion": "1.0",
  "updated": "",
  "turn": 0,
  "activeRoles": [],
  "openEscalations": []
}
```

## Attribution

Brought to you by the `hve-squad` package, built on Microsoft HVE Core agents and conventions.
