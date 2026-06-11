---
description: "Hands a request to the Squad Coordinator, which routes it to a cast of HVE Core agents and persists squad state"
agent: Squad Coordinator
argument-hint: "request=... [profile=default|full|security|design|architecture|azure] [tier=...] [owner=...] [mode=autonomous]"
---

# Squad

## Inputs

* ${input:request}: (Required) The work for the squad this turn, from the user prompt or conversation.
* ${input:profile}: (Optional) The squad profile to seed when the project has no squad yet (`default`, `full`, `security`, `design`, `architecture`, or `azure`). Selects which cast the coordinator stamps out during Init Mode.
* ${input:tier}: (Optional) A model-tier hint (`fast` or `default`) that overrides the coordinator's cost-first defaults for this turn.
* ${input:owner}: (Optional) A `Member Name` from `team.md` that picks a specific named member when two rows share the same `Role` (for example, `owner=Beta` when both `developer` rows exist as `Beta` and `Gamma`).
* ${input:mode}: (Optional) Set to `autonomous` to engage the `auto-validated` autonomy tier defined in `.github/instructions/squad/squad-autonomous.instructions.md`. When omitted, the coordinator uses the standard `auto` and `confirm` tiers from the routing table.

## Requirements

1. Hand `${input:request}` (and `${input:owner}` when provided) to the Squad Coordinator and let its per-turn protocol classify, dispatch, and synthesize the response.
2. Pass `${input:profile}` through as the Init Mode profile hint when provided; when the project has no squad and no profile is given, let the coordinator discover the project and propose a recommended profile before seeding.
3. Pass `${input:tier}` through as the per-turn tier override when provided; otherwise leave cost-first model selection to the coordinator.
4. When `${input:mode}` is `autonomous`, request the coordinator engage the `auto-validated` tier per `.github/instructions/squad/squad-autonomous.instructions.md` (capped re-validation loop, always-escalate triggers); otherwise rely on the standard `auto` and `confirm` tiers from the routing table.
5. Let the coordinator own roster, routing, and state; it reads `.copilot-tracking/squad/{team.md,routing.md}`, seeds them on first run through Init Mode, and persists decisions and history through the Squad Scribe.
