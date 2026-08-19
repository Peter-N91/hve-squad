---
name: squad-federation-templates
description: "Federation-root seed templates: federation.md, meta-routing.md, decisions.md, state.json, and the autopilot meta-run summary."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-08-14"
---

# Squad Federation Seed Templates

## Federation Seed Templates

The Squad Federation Coordinator hands these templates to the Squad Scribe when it creates a federation (after the user confirms the sub-squad set in Federation Init Mode). They stay consistent with `.github/instructions/squad/squad-federation.instructions.md`: `federation.md`, `meta-routing.md`, and the federation `state.json` use replace semantics; the federation `decisions.md` and `history/<sub-squad>.md` are append-only. Each `members/<name>/` sub-squad is seeded with the ordinary `team.md` and `routing.md` templates in [seed-templates.md](seed-templates.md) plus the `decisions.md`, `state.json`, and `history/` shapes in [entry-schemas.md](entry-schemas.md), rooted at `members/<name>/`.

### federation.md

Registry of the sub-squads in this repository. One row per sub-squad; the `Sub-squad` value is also its `members/<name>/` directory. `Kind` is `in-repo` for a sub-squad whose state lives under `members/<name>/`; `repo` is reserved for the deferred multi-repo federation.

```markdown
---
description: "Squad federation registry: the named sub-squads in this repository and the profile each was seeded from"
---

# Squad Federation

## Sub-Squads

| Sub-squad | Profile | Kind    | Location          | Owner         | Description                                              |
|-----------|---------|---------|-------------------|---------------|---------------------------------------------------------|
| product   | product | in-repo | members/product/  | business-team | Requirements, roadmap, and stakeholder deliverables     |
| azure     | azure   | in-repo | members/azure/    | architects    | Azure build: Bicep, landing-zone, cost, and deployment  |
```

### meta-routing.md

Maps a request pattern or domain to a registered sub-squad. Seeded from each sub-squad's profile and description; every row points at a sub-squad that exists in `federation.md`.

```markdown
---
description: "Squad federation meta-routing: request patterns mapped to the sub-squad that handles them"
---

# Squad Federation Meta-Routing

| Pattern / Domain                                                 | Sub-squad | Parallel-Eligible |
|------------------------------------------------------------------|-----------|-------------------|
| requirements, PRD, BRD, roadmap, backlog, stakeholder, discovery | product   | yes               |
| Azure, Bicep, landing zone, deploy, IaC, cost, infrastructure    | azure     | yes               |
```

### decisions.md (federation root)

Append-only log of federation-level routing decisions — which sub-squad handled a request and why. Each entry references the sub-squad's own decision entries so the two levels stay linked. Uses the same append-only contract as a per-squad `decisions.md`.

```markdown
---
description: "Append-only log of squad federation routing decisions and their rationale"
---

# Squad Federation Decisions

Entries are appended below in chronological order. Each entry records which sub-squad(s) a request was routed to, the matched meta-routing pattern or explicit `squad=` target, the turn it was made on, and a reference to the sub-squad's own decision entries. Prior entries are never edited or removed.

<!-- Append new federation decision entries below this line. -->
```

### state.json (federation root)

Machine-readable federation status. Replace semantics — the Scribe overwrites it as the federation advances.

```json
{
  "schemaVersion": "1.2",
  "updated": "",
  "turn": 0,
  "mode": "interactive",
  "subSquads": [],
  "activeSubSquads": [],
  "openEscalations": [],
  "currentRun": {
    "sessionModel": "",
    "modelOverrides": {},
    "estCostUsd": 0,
    "estCreditsTotal": 0
  }
}
```

`subSquads` lists every registered sub-squad name (mirroring `federation.md`); `activeSubSquads` lists the sub-squad(s) dispatched on the current turn. `currentRun.sessionModel` and `currentRun.modelOverrides` are the federation-wide defaults a sub-squad inherits unless its own `state.json` sets them. Each sub-squad keeps its own `state.json` under `members/<name>/` per `.github/instructions/squad/squad-state.instructions.md`.

`mode` and `currentRun` are additive fields for federation-level autopilot (`.github/instructions/squad/squad-federation-autopilot.instructions.md`). `mode` records the autonomy mode in effect for the current federation turn (`interactive` or `autopilot`); `currentRun` aggregates the estimated cost and credits summed across every sub-squad inner run of the current meta-run, so the federation-level cost ceiling reads one number. All of these are backward-compatible — a federation that never runs autopilot leaves `mode` at `interactive` and `currentRun` at zero, and `sessionModel` / `modelOverrides` default to empty — so the `schemaVersion` bumps (`1.0` → `1.1` for autopilot, `1.1` → `1.2` for model attribution) keep existing federation state valid.

### history/autopilot-run-\<id>.md (federation root)

One file per federation autopilot meta-run, at the federation root. Append-only by topic-id: a subsequent meta-run against the same topic appends a new dated `## Meta-Stages` section rather than overwriting. The Scribe writes this file only when the Federation Coordinator runs in `mode=autopilot` with no `squad=` target (a single-target `mode=autopilot` forwards to one sub-squad and writes only that sub-squad's own `members/<name>/history/autopilot-run-<id>.md`).

```markdown
---
description: "Federation autopilot meta-run summary for topic <id>"
---

# Federation Autopilot Run: <id>

* Topic: <one-line summary>
* Opt-In: mode=autopilot (no squad= target)
* Cost Ceiling: <value or unset>
* Aggregate Cost: <est-usd> (~<est-credits> AI credits, estimated, not billed)
* Outcome: completed (awaiting final validation) | escalated (<reason>) | stopped (<reason>)

## Meta-Stages

| Order | Sub-squad | Inner Run                                        | Result             | Gate Fired (attributed)     |
|-------|-----------|--------------------------------------------------|--------------------|-----------------------------|
| 1     | <name>    | members/<name>/history/autopilot-run-<inner>.md  | <one-line outcome> | <none or gate + sub-squad>  |
| 2     | <name>    | members/<name>/history/autopilot-run-<inner>.md  | <one-line outcome> | <none or gate + sub-squad>  |
| final | (federation) | consolidated final-outcome                    | notified <recipient-or-in-chat> | Final-Outcome Validation |

## Gates and Approvals

| Timestamp | Gate                       | Raised By (sub-squad) | Awaiting / Resolved By      | Notes      |
|-----------|----------------------------|-----------------------|-----------------------------|------------|
| <ts>      | <Impactful / Risk / Final> | <sub-squad>           | <human decision or pending> | <one-line> |
```

Each row's `Inner Run` links the sub-squad's own `members/<name>/history/autopilot-run-<inner>.md`, so the two levels of provenance stay linked and auditable.
