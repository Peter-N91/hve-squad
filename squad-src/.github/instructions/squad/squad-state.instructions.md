---
description: "Squad state layout and mapping of squad coordination tools to HVE Core mechanisms"
applyTo: '**/.copilot-tracking/squad/**'
---

# Squad State Conventions

These conventions define where squad state lives, who may change it, and how the squad's coordination tools map onto concrete HVE Core mechanisms. The Squad Coordinator reads this layout to locate roster, routing, decisions, and history; the Squad Scribe writes to it on the coordinator's behalf.

State is per-project and runtime-created. It is never packaged with the squad source — only the coordinator produces it under `.copilot-tracking/squad/` when a project first runs the squad.

## State Layout

All squad state lives under `.copilot-tracking/squad/`:

| Path                  | Purpose                                                                    | Write Semantics      |
|-----------------------|----------------------------------------------------------------------------|----------------------|
| `team.md`             | Roster of roles and the agents that fill them (see roster conventions)     | Replace via scribe   |
| `routing.md`          | Request-pattern routing table (see routing conventions)                    | Replace via scribe   |
| `decisions.md`        | Chronological log of squad decisions and their rationale                   | Append-only          |
| `notifications.md`    | Chronological log of notifications (pings) fired and their delivery channel | Append-only          |
| `history/<agent>.md`  | Per-agent dispatch history: requests handled, findings, outcomes           | Append-only          |
| `history/autopilot-run-<id>.md` | Per-run autopilot pipeline summary: stages, gates, approvals     | Append-only by id    |
| `state.json`          | Machine-readable squad status: current turn, active roles, mode, notification contact, open escalations | Replace via scribe   |

* `decisions.md`, `notifications.md`, and the `history/<agent>.md` files are **append-only**. New entries are added to the end; prior entries are never edited or removed.
* `state.json` mirrors the HVE Core `state.json` precedent: a small, machine-readable status document the coordinator overwrites as the squad advances. It carries the `notify` object (the captured notification contact) and the current `mode`.

### state.json Shape

The Scribe seeds `state.json` on first run and overwrites it as the squad advances:

```json
{
  "schemaVersion": "1.1",
  "updated": "",
  "turn": 0,
  "mode": "interactive",
  "activeRoles": [],
  "openEscalations": [],
  "notify": {
    "approvalChannel": "in-chat",
    "enabled": false,
    "email": "",
    "github": {
      "handle": "",
      "repo": ""
    }
  }
}
```

The `notify` object follows `.github/instructions/squad/squad-notifications.instructions.md`: `approvalChannel` is `in-chat`, `github-issue`, or `webhook`; the `github` block is used only by the `github-issue` channel; and webhook URLs are never stored here. The `mode` field records the autonomy mode in effect for the current turn (`interactive`, `autonomous`, or `autopilot`).

## State Ownership

Only the Squad Coordinator initiates state changes, and only the Squad Scribe performs the writes. Dispatched cast agents (Task Researcher, Task Planner, and the rest) return findings to the coordinator; they never write squad state directly.

This single-writer rule keeps shared state consistent across parallel dispatch: concurrent roles cannot race on the same files because every mutation funnels through the scribe.

## Proof of Dispatch

A `history/<agent>.md` entry is the squad's proof that a role actually ran. Because only the Scribe writes history — and only when the coordinator dispatched the agent and handed back findings — the presence of a per-agent history entry is verifiable evidence that the stage happened; its absence is evidence that it did not.

The coordinator and the pipeline gates treat history as the gate mechanism:

* A stage (research, plan, council, implement, review) counts as complete only when both its domain artifact and a `history/<agent>.md` entry for the dispatched agent exist.
* A missing history entry means the stage did not run, regardless of any narrative claim that it did. The coordinator may not advance past a stage whose history entry is absent — it dispatches the owning agent (or escalates) instead of synthesizing the stage itself.
* This makes the methodology checkable after the fact: every completed run leaves a research file, a plan file, a Council Verdict, change records, and one `history/<agent>.md` per dispatched agent. If any is missing, the run is provably incomplete.

## Tool-to-Mechanism Mapping

The squad's coordination verbs map onto existing HVE Core mechanisms. There is no separate squad runtime; each verb is a thin convention over a deployed capability.

| Squad Tool       | HVE Core Mechanism                                                                                       |
|------------------|----------------------------------------------------------------------------------------------------------|
| `squad_route`    | Dispatch the assigned role via `runSubagent` / `task` against a `user-invocable: false` agent            |
| `squad_decide`   | Append the decision and rationale to `decisions.md`; optionally record an ADR via the `adr-author` skill |
| `squad_memory`   | Write durable per-agent notes with the memory tool to `/memories/repo/squad-<agent>.md`                  |
| `squad_notify`   | Fire a notification per `squad-notifications.instructions.md`; deliver via a configured notification tool when present, else in-chat, and append the record to `notifications.md` |
| `squad_escalate` | Apply the escalate-to-user convention from the routing rules before any role acts                        |

### Decision Recording

* `squad_decide` always appends to `decisions.md` so the squad keeps a complete, ordered decision trail.
* When a decision is architecturally significant, additionally capture it as an Architecture Decision Record through the `adr-author` skill. The `decisions.md` entry references the ADR so the two stay linked.

### Memory Recording

* `squad_memory` persists role-scoped learnings to `/memories/repo/squad-<agent>.md` via the memory tool, keeping squad notes in repository memory rather than ephemeral turn context.
* Repository memory survives across conversations in the workspace, so durable squad facts (conventions a role discovered, recurring routing choices) belong here rather than in `decisions.md`.

## Deferred: Watch Mode (DR-01)

A GitHub Actions "watch mode" hook — triggering the squad automatically on repository events — is intentionally deferred. The state layout already supports it: a future Actions workflow can read `routing.md` and append to `decisions.md` and `history/<agent>.md` through the same single-writer scribe path. No state-schema change is required to add watch mode later.
