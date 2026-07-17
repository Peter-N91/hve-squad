---
description: "Hands a request to the Squad Federation Coordinator, which routes it to one or more named sub-squads and runs each scoped to its own squad root"
agent: Squad Federation Coordinator
argument-hint: "request=... [squad=<name>] [init] [profile=...] [tier=...] [owner=...] [mode=autonomous|autopilot]"
---

# Squad Federation

## Inputs

* ${input:request}: (Required) The work for the federation this turn, from the user prompt or conversation.
* ${input:squad}: (Optional) The registered sub-squad to route this request to (for example, `squad=product` or `squad=azure`). Overrides meta-routing for the turn; when omitted, the coordinator matches the request against `meta-routing.md`.
* ${input:init}: (Optional) When present, triggers Federation Init Mode so the coordinator proposes, confirms, and creates a set of named sub-squads before routing the request.
* ${input:profile}: (Optional) A profile hint forwarded to a sub-squad's Init when that sub-squad has no squad yet.
* ${input:tier}: (Optional) A model-tier hint (`fast` or `default`) forwarded to the selected sub-squad's coordinator run to override cost-first defaults for this turn.
* ${input:owner}: (Optional) A `Member Name` forwarded to the selected sub-squad's coordinator run to pick a specific named member when two rows share the same `Role`.
* ${input:mode}: (Optional) The autonomy mode (`autonomous` or `autopilot`). With a single `squad=` target, or with `mode=autonomous`, it is forwarded to the selected sub-squad's coordinator run. With `mode=autopilot` and **no** `squad=` target, the coordinator runs the federation-level autopilot meta-pipeline across the meta-routing-selected sub-squads per `.github/instructions/squad/squad-federation-autopilot.instructions.md`. When omitted, the sub-squad uses the standard interactive tiers.

## Requirements

1. Hand `${input:request}` to the Squad Federation Coordinator and let its per-turn protocol classify the request to one or more sub-squads and run each scoped to its own squad root.
2. When `${input:squad}` is provided, route the request to that registered sub-squad (escalate when the name is not in `federation.md`); otherwise let the coordinator match `meta-routing.md`.
3. When `${input:init}` is present, or when the project has no `.copilot-tracking/squad/federation.md`, let the coordinator run Federation Init Mode (propose → confirm → create) before routing, per `.github/instructions/squad/squad-federation.instructions.md`.
4. Forward `${input:profile}`, `${input:tier}`, `${input:owner}`, and `${input:mode}` as pass-through hints to the selected sub-squad's coordinator run. When `${input:mode}` is `autopilot` and no `${input:squad}` target is given, let the coordinator run the federation-level autopilot meta-pipeline (federation plan → ordered sub-squad autopilot inner runs → aggregated federation gates → one consolidated final-outcome validation) per `.github/instructions/squad/squad-federation-autopilot.instructions.md`; a single `${input:squad}` target keeps the forward-only behavior.
5. Let the coordinator own the registry, meta-routing, and two-level state; it reads `.copilot-tracking/squad/{federation.md,meta-routing.md,state.json}`, seeds them and each `members/<name>/` sub-squad on first run through Federation Init Mode, and persists federation-level decisions and history through the Squad Scribe while each sub-squad persists its own state under its root.
