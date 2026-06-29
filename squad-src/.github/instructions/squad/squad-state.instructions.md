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
| `consumption.md`      | Aggregated member/model/credit ledger; carries the cost comparison line    | Replace via scribe   |
| `consumption-rates.md`| Per-model token-rate table (USD per 1M) plus the comparison methodology    | Replace via scribe   |

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
  "currentRun": {
    "estCostUsd": 0,
    "estCreditsTotal": 0
  },
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

The `notify` object follows `.github/instructions/squad/squad-notifications.instructions.md`: `approvalChannel` is `in-chat`, `github-issue`, or `webhook`; the `github` block is used only by the `github-issue` channel; and webhook URLs are never stored here. The `mode` field records the autonomy mode in effect for the current turn (`interactive`, `autonomous`, or `autopilot`). The `currentRun` object holds the run totals `estCostUsd` and `estCreditsTotal`, both seeded at 0 and overwritten by the Scribe as dispatches accumulate; they are per-run estimates, not billed amounts (see [Consumption Tracking](#consumption-tracking)).

## Consumption Tracking

Squad runs estimate the model cost and AI-credit consumption of every dispatch so a project can see what a run spent. The billing model is GitHub Copilot usage-based billing (UBB): token-metered, effective 2026-06-01, priced per model in USD per 1M tokens, where 1 AI credit equals $0.01 USD. No per-dispatch token telemetry exists, so every figure is an estimate. The runtime exposes only a per-user aggregate `ai_credits_used` through the usage-metrics REST API, available after the fact for optional reconciliation.

The Scribe records consumption in three places:

* A per-dispatch consumption block appended to `history/<agent>.md` (append-only), one block per dispatch, with fields in this order: `model`, `model_tier`, `input_tokens`, `cached_tokens`, `output_tokens`, `input_rate`, `cached_rate`, `output_rate`, `est_cost_usd`, `est_credits`, `basis`.
* The aggregated `consumption.md` ledger (replace via scribe), which mirrors roster order, lists every dispatched member with its model, tier, estimated tokens, estimated cost, and estimated credits, totals the run, and carries the cost-comparison line. This ledger is the common readme of members, models, and credits.
* The `consumption-rates.md` per-model token-rate table (replace via scribe), the single maintainable source of input, cached, and output rates in USD per 1M tokens plus the comparison methodology. Volatile rate values use `<verify>` placeholders until confirmed against current billing documentation.

The `basis` field records how a block was derived: `estimated` when the model is known and token counts are estimated from context and response size, or `tier-default` when the actual model is unknown and the roster Model Tier rates were used instead.

The Scribe computes the cost and credit estimates from the rates in `consumption-rates.md`:

```text
est_cost_usd = (input_tokens × input_rate + cached_tokens × cached_rate + output_tokens × output_rate) / 1e6
est_credits  = est_cost_usd / 0.01
```

Every numeric output carries an "estimated, not billed" disclaimer. These values support run planning and cost comparison, not invoicing.

## State Ownership

Only the Squad Coordinator initiates state changes, and only the Squad Scribe performs the writes. Dispatched cast agents (Task Researcher, Task Planner, and the rest) return findings to the coordinator; they never write squad state directly.

This single-writer rule keeps shared state consistent across parallel dispatch: concurrent roles cannot race on the same files because every mutation funnels through the scribe.

## Proof of Dispatch

A `history/<agent>.md` entry is the squad's proof that a role actually ran. Because only the Scribe writes history — and only when the coordinator dispatched the agent and handed back findings — the presence of a per-agent history entry is verifiable evidence that the stage happened; its absence is evidence that it did not.

The coordinator and the pipeline gates treat history as the gate mechanism:

* A stage (research, plan, council, implement, review) counts as complete only when both its domain artifact and a `history/<agent>.md` entry for the dispatched agent exist.
* Every `history/<agent>.md` dispatch entry MUST be accompanied by its per-dispatch consumption block (see [Consumption Tracking](#consumption-tracking)). A history entry written without its consumption block is an incomplete dispatch record: the Scribe always writes the two together, and the coordinator may not treat a stage as complete — or advance past it — when the consumption block is missing. This binds consumption to the same gate that already guarantees history, so a run can never leave `consumption.md` at its seed while history shows dispatches occurred.
* A missing history entry means the stage did not run, regardless of any narrative claim that it did. The coordinator may not advance past a stage whose history entry is absent — it dispatches the owning agent (or escalates) instead of synthesizing the stage itself.
* This makes the methodology checkable after the fact: every completed run leaves a research file, a plan file, a Council Verdict, change records, and one `history/<agent>.md` per dispatched agent, each carrying its consumption block. If any is missing, the run is provably incomplete.

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

Squad learnings live on up to three distinct surfaces: a consumer-local writable surface, a shipped read-only surface, and an optional tenant-internal read-only surface.

* `squad_memory` persists role-scoped learnings to the consumer-local `/memories/repo/squad-<agent>.md` via the memory tool, keeping squad notes in repository memory rather than ephemeral turn context. This surface is writable per consumer and is unchanged by the shared playbooks.
* Repository memory survives across conversations in the workspace, so durable squad facts (conventions a role discovered, recurring routing choices) belong here rather than in `decisions.md`.
* The squad skill's shipped `learnings/shared-learnings.md` playbook is the second surface. It travels as versioned package content, and the coordinator consults it as read-only, authoritative context. No run ever writes to it.
* An optional tenant-internal playbook is the third surface, present only when the organization configured the tenant APM dependency. It deploys to `.agents/skills/squad-learnings-tenant/tenant-learnings.md`, and the coordinator consults it as read-only, authoritative context after the shipped playbook and never writes to it.
* Consumer-local memory is never auto-promoted into either shared surface. Promotion is a deliberate, human-reviewed path documented in `CONTRIBUTING.md`, which keeps a maintainer review gate between a local note and shared content; that governance covers both upstream promotion to the shipped playbook and promotion to a tenant-internal repository.

## Deferred: Watch Mode (DR-01)

A GitHub Actions "watch mode" hook — triggering the squad automatically on repository events — is intentionally deferred. The state layout already supports it: a future Actions workflow can read `routing.md` and append to `decisions.md` and `history/<agent>.md` through the same single-writer scribe path. No state-schema change is required to add watch mode later.
