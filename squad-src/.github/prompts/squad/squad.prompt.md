---
description: "Hands a request to the Squad Coordinator, which routes it to a cast of HVE Core agents and persists squad state"
agent: Squad Coordinator
argument-hint: "request=... [profile=default|full|security|design|architecture] [tier=...]"
---

# Squad

## Inputs

* ${input:request}: (Required) The work for the squad this turn, from the user prompt or conversation.
* ${input:profile}: (Optional) The squad profile to seed when the project has no squad yet (`default`, `full`, `security`, `design`, or `architecture`). Selects which cast the coordinator stamps out during Init Mode.
* ${input:tier}: (Optional) A model-tier hint (`fast` or `default`) that overrides the coordinator's cost-first defaults for this turn.

## Requirements

1. Hand `${input:request}` to the Squad Coordinator and let its per-turn protocol classify, dispatch, and synthesize the response.
2. Pass `${input:profile}` through as the Init Mode profile hint when provided; when the project has no squad and no profile is given, let the coordinator discover the project and propose a recommended profile before seeding.
3. Pass `${input:tier}` through as the per-turn tier override when provided; otherwise leave cost-first model selection to the coordinator.
4. Let the coordinator own roster, routing, and state; it reads `.copilot-tracking/squad/{team.md,routing.md}`, seeds them on first run through Init Mode, and persists decisions and history through the Squad Scribe.
