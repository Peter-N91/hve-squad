---
description: "Squad state layout and mapping of squad coordination tools to HVE Core mechanisms"
applyTo: '**/.copilot-tracking/squad/**'
---

# Squad State Conventions

These conventions define where squad state lives, who may change it, and how the squad's coordination tools map onto concrete HVE Core mechanisms. The Squad Coordinator reads this layout to locate roster, routing, decisions, and history; the Squad Scribe writes to it on the coordinator's behalf.

State is per-project and runtime-created. It is never packaged with the squad source — only the coordinator produces it under `.copilot-tracking/squad/` when a project first runs the squad.

## Squad Root (parameterized state root)

Every state path below is relative to a **squad root**. The root is parameterized so the same layout can serve either a single squad or a sub-squad within a federation:

* The default squad root is `.copilot-tracking/squad/`. When no root is supplied, the paths in this file are literal and behavior is exactly today's single-squad behavior.
* In a **federation** (opt-in), each sub-squad roots at `.copilot-tracking/squad/members/<name>/`, and every path in this file is read as `<squadRoot>/...`. The Squad Coordinator and Squad Scribe accept an optional `squadRoot`; when omitted, the default preserves single-squad behavior.

The federation layout, the registry, meta-routing, detection precedence (`federation.md` → federation, else `team.md` → plain squad, else Init), and the two-level single-writer rule are defined in `.github/instructions/squad/squad-federation.instructions.md`. The remainder of this file describes the state tree under a single squad root; it applies unchanged to each sub-squad root in a federation.

## State Layout

All squad state lives under the squad root (`.copilot-tracking/squad/` by default; `.copilot-tracking/squad/members/<name>/` for a federation sub-squad):

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
  "schemaVersion": "1.3",
  "updated": "",
  "turn": 0,
  "mode": "interactive",
  "activeRoles": [],
  "openEscalations": [],
  "currentRun": {
    "sessionModel": "",
    "modelOverrides": {},
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

Watch Mode runs additionally carry an optional `trigger` object recording the event that started the run (`source`, `ref`, `eventId`, `actor`, `receivedAt`, `runId`). It is additive and omitted for interactive, autonomous, and autopilot runs that were not event-triggered; see `.github/instructions/squad/squad-watch-mode.instructions.md`.

## Consumption Tracking

Squad runs estimate the model cost and AI-credit consumption of every dispatch so a project can see what a run spent. The billing model is GitHub Copilot usage-based billing (UBB): token-metered, effective 2026-06-01, priced per model in USD per 1M tokens, where 1 AI credit equals $0.01 USD. No per-dispatch token telemetry exists, so every figure is an estimate. The runtime exposes only a per-user aggregate `ai_credits_used` through the usage-metrics REST API, available after the fact for optional reconciliation.

The Scribe records consumption in three places:

* A per-dispatch consumption block appended to `history/<agent>.md` (append-only), one block per dispatch, with fields in this order: `model`, `model_source`, `priced_as`, `model_tier`, `internal_turns`, `input_tokens`, `cached_tokens`, `cache_write_tokens`, `output_tokens`, `input_rate`, `cached_rate`, `cache_write_rate`, `output_rate`, `est_cost_usd`, `est_credits`, `basis`.
* The aggregated `consumption.md` ledger (replace via scribe), which mirrors roster order, lists every dispatched member with its resolved model, model source, tier, estimated turns and tokens, estimated cost, and estimated credits, adds an `orchestration` row for coordinator and Scribe overhead, totals the run, and carries the cost-comparison line. This ledger is the common readme of members, models, and credits.
* The `consumption-rates.md` table (replace via scribe), the single maintainable source of per-model input, cached, cache-write, and output rates in USD per 1M tokens, plus the tier-fallback rates, the dispatch-size estimator, the calibration block, and the comparison methodology.

Model attribution — which model each block reports and how it is resolved — is governed by [Model Attribution](#model-attribution) below.

### Why a dispatch is not one model call

A dispatched agent runs an internal tool loop, and every internal turn resends the accumulated context. Cost therefore scales with `internal_turns × average_context`, not with a single input-and-output pair, and the accumulated context is largely billed at the cheaper cached rate. Pricing a dispatch as one call is the single largest source of undercounting in this ledger, so the estimator in `consumption-rates.md` models the loop explicitly and every block records the `internal_turns` it assumed.

**Orchestration counts** too: the coordinator's own turns and the Scribe's writes get their own ledger row, because they are real consumption that no dispatch block covers.

The Scribe computes the cost and credit estimates from the rates in `consumption-rates.md`:

```text
raw_cost_usd = ( input_tokens       × input_rate
               + cached_tokens      × cached_rate
               + cache_write_tokens × cache_write_rate
               + output_tokens      × output_rate ) / 1e6
est_cost_usd = raw_cost_usd × calibration_factor
est_credits  = est_cost_usd / 0.01
```

### Calibration

Estimates that are never checked stay wrong. `consumption-rates.md` carries a `calibration_factor` — the running mean of `observed_credits / estimated_credits` across reconciled runs, clamped to 0.25-10.0 — that multiplies every cost estimate. When the coordinator supplies an `observed_credits` figure (the per-user aggregate `ai_credits_used` delta read from the Copilot usage-metrics REST API across the run), the Scribe folds that run's ratio into the mean and stamps the calibration block. Until at least one run has been reconciled the factor stays at 1.00 and the ledger carries an "uncalibrated" note.

Every numeric output carries an "estimated, not billed" disclaimer. These values support run planning and cost comparison, not invoicing.

## Model Attribution

The `model` field records **what actually ran**. It is resolved, never guessed. A ledger that reports a model the operator did not choose is worse than one that reports nothing, because it invites cost decisions based on a fiction.

### Resolution ladder

Resolve every dispatch's model by walking this ladder and stopping at the first hit. Record which rung produced the answer in `model_source`:

1. **Headless CLI run** → `model_source: cli-pinned`. When the run is headless (a Watch Mode run, identifiable by the `trigger` object in `state.json`), the Copilot CLI takes its model from `--model` and **ignores agent `model:` frontmatter entirely**. That one model therefore applies to *every* agent in the run, including agents that pin a different one. Skip rung 3 in this case.
2. **Operator declaration** → `model_source: operator-declared`. The operator stated the model for this run or this role, recorded in `state.json` `currentRun.modelOverrides`.
3. **Agent-pinned** → `model_source: agent-pinned`. The dispatched agent's own file declares a `model:` list in frontmatter and the host honors it (the VS Code host does; the CLI does not); the runtime uses the first entry the operator's plan supports. Read the agent file rather than assuming.
4. **Session-inherited** → `model_source: session-inherited`. The agent declares no `model:`, so it runs on the session model recorded in `state.json` `currentRun.sessionModel`.
5. **Unresolved** → `model_source: unresolved`. None of the above is knowable, so `model` is the literal `unknown`.

Rungs 1-4 are deterministic and require no inference: the host is knowable from state, the agent file is readable, and the session model is recorded state. Rung 5 is a genuine gap, and the only correct value for `model` there is the literal `unknown`.

The host matters as much as the agent. The same roster produces different real models in the VS Code host (where a pinned agent runs its pinned model) and in a headless Watch Mode run (where `--model` flattens every agent onto one model). A ledger that ignores the host will misattribute every pinned role in every unattended run.

### Never invent a model name

* `model` is either a model the ladder resolved or the literal `unknown`. It is **never** derived from a tier, a rate row, a roster preference, or a plausible-sounding guess.
* Never copy the tier-fallback table's "priced as" model into `model`. That table names a model for *pricing* purposes only; writing it into the attribution field is the fabrication this rule exists to prevent.
* `priced_as` records the rate row actually used. It equals `model` whenever the resolved model has its own rate row, and differs only when `model` is `unknown` (priced at the tier fallback) or when the resolved model is missing from the rate table.
* When `model` is `unknown`, the ledger row and the run summary say so plainly rather than presenting a confident-looking name.

### A tier is not a model

`team.md`'s `Model Tier` is a routing preference. It never determines what ran and never appears in `model`. Two consequences follow, and both are common sources of surprise:

* An agent that pins `model:` in its frontmatter does **not** run on the operator's selected model *in a host that honors frontmatter*. The Squad Scribe, Squad Reviewer, Squad Cost Manager, and Squad Technical Writer pin a lightweight model by design, so an operator running a high-capability model everywhere will still see those roles attributed to the pinned lightweight model. That is correct, not a bug — `model_source: agent-pinned` is what makes it legible. In a headless Watch Mode run the same roles run on the `--model` pin instead, and are recorded as `cli-pinned`.
* An agent that pins nothing runs on the operator's model. If the operator selected a high-capability model, that dispatch must be priced at that model's rates, not at its roster tier's rates. Pricing an inherited high-capability dispatch at a mid-tier fallback is a direct undercount.

### Recording the session model

`state.json` `currentRun.sessionModel` is the single source of truth for rung 3. The coordinator captures it at Init, restates it whenever the operator changes model mid-run, and passes it on every Scribe hand-off. `currentRun.modelOverrides` optionally maps a role or agent name to a model the operator declared explicitly. In a federation, a sub-squad inherits both from the federation root unless its own `state.json` sets them.

`basis` describes pricing; `model_source` describes attribution. They are independent, and both are required on every block.

## State Ownership

Only the Squad Coordinator initiates state changes, and only the Squad Scribe performs the writes. Dispatched cast agents (Squad Researcher, Squad Lead, Squad Implementor, and the rest) return findings to the coordinator; they never write squad state directly.

This single-writer rule keeps shared state consistent across parallel dispatch: concurrent roles cannot race on the same files because every mutation funnels through the scribe.

## Proof of Dispatch

A `history/<agent>.md` entry is the squad's proof that a role actually ran. Because only the Scribe writes history — and only when the coordinator dispatched the agent and handed back findings — the presence of a per-agent history entry is verifiable evidence that the stage happened; its absence is evidence that it did not.

The coordinator and the pipeline gates treat history as the gate mechanism:

* A stage (intake, research, plan, council, implement, review) counts as complete only when both its domain artifact and a `history/<agent>.md` entry for the dispatched agent exist.
* Every `history/<agent>.md` dispatch entry MUST be accompanied by its per-dispatch consumption block (see [Consumption Tracking](#consumption-tracking)). A history entry written without its consumption block is an incomplete dispatch record: the Scribe always writes the two together, and the coordinator may not treat a stage as complete — or advance past it — when the consumption block is missing. This binds consumption to the same gate that already guarantees history, so a run can never leave `consumption.md` at its seed while history shows dispatches occurred.
* A missing history entry means the stage did not run, regardless of any narrative claim that it did. The coordinator may not advance past a stage whose history entry is absent — it dispatches the owning agent (or escalates) instead of synthesizing the stage itself.
* This makes the methodology checkable after the fact: every completed run leaves a research file, a plan file, a Council Verdict, change records, and one `history/<agent>.md` per dispatched agent, each carrying its consumption block. When the run's work was grounded in requirement or input artifacts, it also leaves an Intake Readiness Verdict in `decisions.md`. If any is missing, the run is provably incomplete.

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

## Watch Mode (DR-01)

Watch Mode — triggering the squad automatically on repository events (a new issue, a PR, a `/squad` comment, a schedule) so a run produces a pull request — is specified in `.github/instructions/squad/squad-watch-mode.instructions.md`. A Watch Mode run reads `routing.md` and appends to `decisions.md` and `history/<agent>.md` through the same single-writer Scribe path an interactive run uses, rooted at the **event-scoped sub-squad** the run executes in (`.copilot-tracking/squad/members/<name>/`) rather than the top-level squad root.

Watch Mode adds one backward-compatible state change: an optional `trigger` object in `state.json`, with `schemaVersion` moving to `1.2` (see [state.json Shape](#statejson-shape)). The object is additive — a squad that never runs in Watch Mode omits it — so existing state stays valid. The inbound approval half ships as the reference workflow `.github/skills/squad/github-approval-watcher.workflow.yml`; the outbound trigger half ships as the reference workflow `.github/skills/squad/squad-watch.workflow.yml`.
