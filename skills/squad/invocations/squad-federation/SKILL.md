---
name: squad-federation
description: "Routes a request to the Squad Federation Coordinator, which dispatches one or more named sub-squads. Use when the user's project has (or wants) multiple named sub-squads, or names init, promote, watch, or a specific squad=<name> target."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Federation

## Inputs

* **request** (required): The work for the federation this turn, from the user's own words.
* **squad** (optional): The registered sub-squad to route this request to (for example, `squad=product`). Overrides meta-routing for the turn; when omitted, the coordinator matches `meta-routing.md`.
* **init** (optional): When present, triggers Federation Init Mode (propose → confirm → create) before routing. When a federation already exists, the same flag runs Federation Expansion Mode instead.
* **promote** (optional): When present on an existing single-squad project, triggers Federation Promotion Mode, adopting the existing squad into a federation as its first sub-squad before routing.
* **watch** (optional): Watch Mode provenance supplied by an event-triggered run — the event `source`, `ref`, `eventId`, `actor`, `receivedAt`, and the derived sub-squad name. When present, the coordinator runs Watch Mode Bootstrap Mode.
* **profile** (optional): A profile hint forwarded to a sub-squad's Init when that sub-squad has no squad yet.
* **discovery** (optional): The discovery-gate depth (`quick`, `standard`, `deep`, or `skip`) forwarded to every qualifying sub-squad the turn starts. Ignored on a Watch Mode or otherwise unattended run.
* **tier** (optional): A model-tier hint (`fast` or `default`) forwarded to the selected sub-squad's coordinator run.
* **owner** (optional): A `Member Name` forwarded to the selected sub-squad's coordinator run.
* **routing** (optional): `off`, `ranked`, `economy`, or `manual`, forwarded verbatim for each sub-squad to persist: capability-first Ranked, qualified cost-first work for every role, or explicit Manual choices. Never change the selected coordinator session model or Scribe pin.
* **depth** (optional): `quick` or `standard` (default), forwarded to every selected sub-squad, which never widens it. It changes how much work runs, never a model; ignored on an unattended run.
* **mode** (optional): The autonomy mode (`autonomous` or `autopilot`). With a single **squad** target, or with `mode=autonomous`, it is forwarded to that sub-squad's coordinator run. With `mode=autopilot` and no **squad** target, the coordinator runs the federation-level autopilot meta-pipeline across the meta-routing-selected sub-squads.

## Flow

1. Hand **request** to the Squad Federation Coordinator and let its per-turn protocol classify the request to one or more sub-squads and run each scoped to its own squad root.
2. When **squad** is provided, route the request to that registered sub-squad (escalate when the name is not registered); otherwise let the coordinator match `meta-routing.md`.
3. When **init** is present, or the project has no federation yet, let the coordinator run Federation Init Mode (or Federation Expansion Mode when a federation already exists) before routing. When **promote** is present, or an existing single-squad project asks to move to a federation, let the coordinator run Federation Promotion Mode instead of a from-scratch Init.
4. Forward **profile**, **discovery**, **tier**, **owner**, **routing**, **depth**, and **mode** as pass-through hints to the selected sub-squad's coordinator run. Preserve the received routing mode and floors; a child may only narrow them. When **discovery** is omitted and at least one selected sub-squad qualifies, let the coordinator ask the discovery question once at the federation level and apply the answer to every qualifying sub-squad. When **mode** is `autopilot` and no **squad** target is given, let the coordinator run the federation-level autopilot meta-pipeline; a single **squad** target keeps the forward-only behavior.
5. When **watch** is present, let the coordinator run Watch Mode Bootstrap Mode ahead of any classification: derive the sub-squad name from structural event metadata only, bootstrap the federation, reuse the sub-squad on matching provenance, escalate on a human-owned name collision, and then run that sub-squad's standard single-squad autopilot scoped to `members/<name>/`. An explicit **squad** target overrides the event sub-squad and creates nothing.
6. Let the coordinator own the registry, meta-routing, and two-level state — it seeds `.copilot-tracking/squad/{federation.md,meta-routing.md,state.json}` and each `members/<name>/` sub-squad on first run, and persists federation-level decisions and history through the Squad Scribe while each sub-squad persists its own state under its root.

## Invocation

Dispatch this request to the `Squad Federation Coordinator` agent. This skill does not run the federation logic itself — it only resolves which parameters to pass.