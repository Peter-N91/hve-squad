---
name: squad-entry-schemas
description: "Recurring squad write schemas: decisions.md entries and verdicts, history files, the autonomous-loop and autopilot-run summaries, notifications.md, and state.json."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-08-18"
---

# Entry Schemas

The shapes the Squad Scribe writes on an ordinary turn. Initialization is outside admission. Before later work dispatch, Cost Preflight is the one exception: the coordinator appends its decision and compare-and-swap updates only `currentRun.costPreflight`, then reads both back. Every later write remains Scribe-owned.

These schemas are separate from [seed-templates.md](seed-templates.md), which stamps `team.md` and `routing.md` once during Init: every file below is written or appended to repeatedly for the life of a squad, so the Scribe reads this file on every turn while it reads the seed templates only when it is actually seeding.

Write semantics follow the state layout: `decisions.md`, `history/<agent>.md`, `history/autonomous-loop-<id>.md`, `history/autopilot-run-<id>.md`, and `notifications.md` are append-only; `state.json` uses replace semantics.

## decisions.md

Append-only log. The header is written once; every decision is appended below it and prior entries are never edited. Council Verdicts (from the Council Procedure) use the same append-only contract but a fixed schema; the placeholder below shows the shape the Scribe stamps in.

```markdown
---
description: "Append-only log of squad decisions and their rationale"
---

# Squad Decisions

Entries are appended below in chronological order. Each entry records the decision, its rationale, the turn it was made on, and a reference to an ADR when the decision is architecturally significant. Council Verdicts use the `## Council Verdict <timestamp> <topic-id>` heading and the schema in `.github/instructions/squad/squad-council.instructions.md`; Discovery Verdicts and Intake Readiness Verdicts use their own headings and schemas from `.github/instructions/squad/squad-discovery-gate.instructions.md` and `.github/instructions/squad/squad-intake-gate.instructions.md`. Prior entries are never edited or removed.

<!-- Append new decision entries below this line. -->

<!--
Cost Preflight placeholder (the coordinator stamps this shape before post-initialization work dispatch):

## Cost Preflight <timestamp> <run-id> <round-id>

* Ceiling USD: <positive number>
* Estimated Spend So Far USD: <currentRun.estCostUsd>
* Remaining USD: <max(0, ceiling - spend)>
* Projected Cost USD: <calibrated point estimate>
* Reserve Multiplier: 3.0
* Admission Cost USD: <projected cost x 3.0>
* Confidence: low | medium
* Basis: estimated | calibrated
* Decision: within-ceiling | over-ceiling | approved-over-ceiling | cannot-confirm
* Approved From: <prior over-ceiling Decision Ref; approved-over-ceiling only>
* Approval Ref: <in-chat or remote human approval reference; approved-over-ceiling only>
* Reason: <one-line reproducible reason>
* Evaluated Dispatch Set: <ordered slot ids>
* Permitted Next Dispatch Set: <ordered slot ids or none>
* Estimate Notice: Forecast only; not billed cost.

### Planned Demand

| Slot | Stage | Role | Count | Dispatch Class | Pricing Basis | Internal Turns | Base Context | Growth/Turn | Output/Turn | Projected Cost |
|------|-------|------|------:|----------------|---------------|---------------:|-------------:|------------:|------------:|---------------:|
| <id> | <stage> | <role> | <n> | <class> | <model or max-candidate set> | <turns> | <tokens> | <tokens> | <tokens> | <usd> |

-->

<!--
Council Verdict placeholder (Scribe stamps this shape when a council runs):

## Council Verdict <timestamp> <topic-id>

* Topic: <one-line summary of the proposal>
* Proposal Ref: <path-to-plan-or-design>
* Council Members Dispatched: architect, security, cost-manager, product-owner
* Verdict: Go | Go-With-Conditions | Stop

### Findings by Role

| Role          | Verdict | Risk        | Blocking Issues | Conditions | Suggested Follow-ups |
|---------------|---------|-------------|-----------------|------------|----------------------|
| architect     | <label> | <risk>      | <list-or-none>  | <list>     | <list>               |
| security      | <label> | <risk>      | <list-or-none>  | <list>     | <list>               |
| cost-manager  | <label> | <risk>      | <list-or-none>  | <list>     | <list>               |
| product-owner | <label> | <risk>      | <list-or-none>  | <list>     | <list>               |

### Synthesis

* Blocking Issues: <consolidated list with role attribution; empty when verdict is Go>
* Conditions: <consolidated list with role attribution; empty when verdict is Go>
* Suggested Follow-ups: <consolidated list with role attribution>

### Implementation Gate

* Permits Implementation Dispatch: yes (Go, Go-With-Conditions) | no (Stop)
* Conditions Outstanding: <count>
-->

<!--
Intake Readiness Verdict placeholder (Scribe stamps this shape when the intake gate runs):

## Intake Readiness Verdict <timestamp> <topic-id>

* Topic: <one-line summary of the work the inputs ground>
* Inputs Reviewed: <comma-separated artifact paths or references>
* Validator Dispatched: <resolved agent name>
* Verdict: Ready | Ready-With-Gaps | Not-Ready
* Remediation Cycles: <0, 1, or 2>

### Findings

| Dimension        | Result    | Blocking Gaps  | Non-Blocking Gaps |
|------------------|-----------|----------------|-------------------|
| Completeness     | pass/fail | <list-or-none> | <list-or-none>    |
| Clarity          | pass/fail | <list-or-none> | <list-or-none>    |
| Testability      | pass/fail | <list-or-none> | <list-or-none>    |
| Consistency      | pass/fail | <list-or-none> | <list-or-none>    |
| Scope Boundaries | pass/fail | <list-or-none> | <list-or-none>    |

### Clarifying Questions

* <question for the user; empty when verdict is Ready>

### Recorded Assumptions

* <assumption carried into downstream work; empty when none>

### Intake Gate

* Permits Downstream Dispatch: yes (Ready, Ready-With-Gaps) | no (Not-Ready)
* Blocking Gaps Outstanding: <count>
-->
```

## history/<agent>.md

One append-only file per dispatched agent. Replace `<agent>` with the agent's `name:` frontmatter value **verbatim** — the display name, spaces and capitalization intact, as in `history/Squad Researcher.md` or `history/BRD Builder.md`. Never slugify it, never lowercase it, and never substitute the role id: the file name is how a later turn matches a history entry back to the roster row it came from, so `squad-researcher.md` and `researcher.md` both read as a missing entry and the ledger rewrite drops that agent. Autonomous-loop runs add per-cycle dispatch entries to each role's history file using the placeholder shape below.

**The file is created by the first dispatch to that agent, never before it.** Init seeds the `history/` directory and nothing inside it. A header-only file seeded for every roster member at Init destroys the one signal this directory exists to carry — a file's presence is the proof a stage ran — and turns "which roles have been dispatched" into a question the state can no longer answer. Create the file with its header at the moment the first entry is appended, in the same write.

`history/Squad Scribe.md` follows the same naming rule but holds `#### Consumption — Orchestration` blocks rather than dispatch records, because the coordinator's own turns and the Scribe's writes need somewhere in `history/` for the ledger rewrite to read them back from. It is not a dispatched stage and is not counted as one.

An orchestration entry uses the dispatch entry shape below with the `#### Consumption — Orchestration` heading in place of `#### Consumption`, and `Deliverable:` naming the state files that turn wrote:

````markdown
### <timestamp> <what this turn wrote>

* Turn: <n>
* Request: <what the coordinator handed over>
* Deliverable: <the state files this turn wrote>
* Outcome: <one line>

#### Consumption — Orchestration

```json
{ ... the same ten fields, in the same order ... }
```
````

Write every one of those four prose fields. The turn number and the work the turn covered have no field in the block — the set is closed at ten — so an entry that omits the prose leaves them nowhere to go and they leak into the JSON as `turn` and `task`, which breaks the field-order contract and drops the block out of the ledger rewrite.

```markdown
---
description: "Append-only dispatch history for a single squad agent"
---

# History: <agent>

Each entry records a request this agent handled, the findings or outcome it returned, and the turn it was dispatched on. Entries are appended in chronological order and never edited.

<!-- Append new dispatch entries below this line. -->
```

**The heading is literally `# History: <agent>`.** Not the bare agent name, not a role-flavored rewrite of the description. A later turn locates a history file by that heading, and a file headed `# Squad Researcher` reads as a file with no header at all.

Every appended dispatch entry uses exactly this shape. The `#### Consumption` heading is the container the ledger rewrite reads blocks back from, so its level and wording are fixed and it takes **no suffix**: `### Consumption`, `#### Consumption Block`, `#### Consumption — Research`, and `#### Consumption — Orchestration (Turn 1)` are all unreadable and drop that dispatch out of every later aggregate. The only legal variant is `#### Consumption — Orchestration`, which marks an orchestration block rather than a dispatch. Turn and timestamp belong in the entry heading above the block or inside the JSON, never appended to the heading.

````markdown
### <timestamp> <short title>

* Turn: <n>
* Request: <scoped request the agent received>
* Deliverable: `<the role's Deliverable Root cell, extended verbatim, plus the filename>` (<size or word count>)
* Outcome: <one-line summary>
* Cost Preflight Ref: `decisions.md#cost-preflight-<timestamp>-<run-id>-<round-id>`
* Cost Preflight Slot: <permitted slot id>

#### Consumption

```json
{
  "model": "<resolved model or unknown>",
  "model_source": "<dispatch-reported|agent-pinned|operator-declared|session-inherited|cli-pinned|unresolved>",
  "priced_as": "<rate row this dispatch prices from>",
  "model_tier": "<fast|default|extended>",
  "internal_turns": 0,
  "input_tokens": 0,
  "cached_tokens": 0,
  "cache_write_tokens": 0,
  "output_tokens": 0,
  "basis": "<estimated|tier-default>"
}
```
````

Field order is contractual and every numeric field is a bare number. The block records consumption only: rates, `est_cost_usd`, and `est_credits` are the ledger's, and `priced_as` is what tells it which rate row to use. See *Consumption Accounting* in [scribe-procedure.md](scribe-procedure.md) for how each value is resolved and how the ledger prices them.

When Cost Preflight is configured, the `Cost Preflight Ref` and `Cost Preflight Slot` pair is also unique across history. One admitted slot authorizes one dispatch; a second entry carrying the same run, round, and slot is a replay and must be rejected before any write.

An autonomous-loop cycle replaces the entry body above with the shape below and still carries its own `#### Consumption` block:

```markdown
### <timestamp> autonomous-loop:<topic-id> cycle:<1|2>

* Request: <scoped request the agent received>
* Verdict Returned: <label> (Risk: <level>)
* Blocking Issues: <list-or-none>
* Conditions: <list-or-none>
* Outcome: <one-line summary>
* See: `.copilot-tracking/squad/history/autonomous-loop-<topic-id>.md`
```

## history/autonomous-loop-<id>.md

One file per autonomous-loop topic. Append-only by topic-id: subsequent runs against the same topic append a new dated `## Iterations` section rather than overwriting. The Scribe writes this file only when the coordinator runs in `mode=autonomous`.

```markdown
---
description: "Autonomous-loop summary for topic <id>"
---

# Autonomous Loop: <id>

* Topic: <one-line summary>
* Opt-In: mode=autonomous
* Cost Ceiling: <value or unset>
* Outcome: converged (Go) | converged (Go-With-Conditions) | escalated (<reason>)

## Cost Preflight Rounds

| Round | Decision | Confidence | Remaining USD | Admission USD | Decision Ref |
|-------|----------|------------|--------------:|--------------:|--------------|
| <round-id> | <within-ceiling / over-ceiling / approved-over-ceiling / cannot-confirm> | <low / medium> | <usd> | <usd> | `decisions.md#cost-preflight-<timestamp>-<run-id>-<round-id>` |

## Iterations

| Cycle | Verdict                        | Blocking Issues | Conditions     | Notes                    |
|-------|--------------------------------|-----------------|----------------|--------------------------|
| 1     | Go / Go-With-Conditions / Stop | <list-or-none>  | <list-or-none> | <one-line cycle summary> |
| 2     | (when run)                     | <list-or-none>  | <list-or-none> | <one-line cycle summary> |

## Final Verdict Reference

* Council Verdict: see `decisions.md` under `## Council Verdict <timestamp> <id>`
```

## history/autopilot-run-<id>.md

One file per autopilot run. Append-only by topic-id: subsequent runs against the same topic append a new dated `## Stages` section rather than overwriting. The Scribe writes this file only when the coordinator runs in `mode=autopilot`.

```markdown
---
description: "Autopilot-run summary for topic <id>"
---

# Autopilot Run: <id>

* Topic: <one-line summary>
* Opt-In: mode=autopilot
* Cost Ceiling: <value or unset>
* Outcome: completed (awaiting final validation) | incomplete (<n> stage(s) without a dispatch record) | escalated (<reason>) | stopped (<reason>)

## Cost Preflight Rounds

| Round | Evaluated Dispatch Set | Permitted Next Dispatch Set | Decision | Confidence | Remaining USD | Admission USD | Decision Ref |
|-------|------------------------|-----------------------------|----------|------------|--------------:|--------------:|--------------|
| <round-id> | <ordered slot ids> | <ordered slot ids or none> | <within-ceiling / over-ceiling / approved-over-ceiling / cannot-confirm> | <low / medium> | <usd> | <usd> | `decisions.md#cost-preflight-<timestamp>-<run-id>-<round-id>` |

## Stages

| Stage     | Role(s)     | Dispatch Record              | Result                          | Gate Fired                 |
|-----------|-------------|------------------------------|---------------------------------|----------------------------|
| research  | <agent(s)>  | `history/<agent>.md`         | <one-line outcome>              | none                       |
| plan      | <agent>     | `history/<agent>.md`         | <one-line outcome>              | none                       |
| council   | <roles>     | `history/<agent>.md` each    | <verdict-or-skipped>            | <none or Risk Gate reason> |
| implement | <agent>     | `history/<agent>.md`         | <one-line outcome>              | <none or Impactful-Action> |
| review    | <agent>     | `history/<agent>.md`         | <one-line outcome>              | none                       |
| final     | coordinator | n/a                          | notified <recipient-or-in-chat> | Final-Outcome Validation   |
```

`Dispatch Record` names the history file the Scribe wrote for that stage, and is filled from `history/` rather than from the coordinator's account of the run. A stage with no such file carries the literal `— none recorded`, and any such cell forces the `incomplete` outcome above. This is the run's own report that its cast was not dispatched, written by the only participant that knows.

In a deliverable fan-out run, the single `implement` row expands into one row per deliverable (`implement: <deliverable>` with its owning agent).

## notifications.md

Append-only log of notifications (pings) the squad fired. The header is written once; every notification is appended below it. Records the trigger, the recipient, the resolved channel, and the decision awaited.

```markdown
---
description: "Append-only log of squad notifications (pings) and their delivery channel"
---

# Squad Notifications

Each entry records a notification the squad fired: when, to whom, the trigger, the channel it resolved to, and the decision awaited. Entries are appended in chronological order and never edited.

<!-- Append new notification entries below this line. -->
```

## state.json

Machine-readable squad status. Uses replace semantics. The Scribe owns ordinary advances; the coordinator may compare-and-swap only `currentRun.costPreflight` as the deterministic pre-dispatch transaction, plus the exact `1.3` to `1.4` schema bump when that transaction migrates legacy state.

**The key set below is closed.** Write these keys and no others, at all three levels: every one of `schemaVersion`, `updated`, `turn`, `mode`, `activeRoles`, `openEscalations`, `currentRun`, and `notify` is present on every write; `currentRun` always carries `sessionModel`, `modelOverrides`, `estCostUsd`, `estCreditsTotal`, and `costPreflight`; and `costPreflight` carries exactly the keys shown below. This file is read by machine, so a run that invents scratch fields produces a file that looks informative and answers none of the questions the squad asks it.

```json
{
  "schemaVersion": "1.4",
  "updated": "",
  "turn": 0,
  "mode": "interactive",
  "activeRoles": [],
  "openEscalations": [],
  "currentRun": {
    "sessionModel": "",
    "modelOverrides": {},
    "estCostUsd": 0,
    "estCreditsTotal": 0,
    "costPreflight": {
      "runId": "",
      "roundId": "",
      "ceilingUsd": null,
      "evaluatedSpendUsd": 0,
      "remainingUsd": null,
      "plannedDispatches": 0,
      "projectedCostUsd": 0,
      "reserveMultiplier": 3.0,
      "admissionCostUsd": 0,
      "confidence": "not-applicable",
      "basis": "not-requested",
      "decision": "not-requested",
      "reason": "No cost ceiling configured."
    }
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

Watch Mode runs additionally carry an optional, additive `trigger` object recording the event that started the run; interactive, autonomous, and autopilot runs omit it. See `.github/instructions/squad/squad-watch-mode.instructions.md`.

Read legacy single-squad schema `1.3` without `costPreflight` as an unset ceiling with the default `not-requested` object above. On the next coordinator Cost Preflight transaction or ordinary Scribe write, atomically add the exact object, bump only `schemaVersion` to `1.4`, and preserve every existing root, `notify`, `trigger`, model, override, and accumulated-total value. Never reject or reset an existing no-ceiling run only because it predates this object.
