---
name: squad-entry-schemas
description: "Recurring Markdown/state schemas for cold Scribe operations and compatibility reference. Ordinary handoffs use the small deterministic writer contract, not this full schema read."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-09-27"
---

# Entry Schemas

These historical shapes are preserved by the validated ordinary writer and cold Scribe. Ordinary handoffs in every routing mode read only [economy-scribe.md](economy-scribe.md); coordinators may run the writer synchronously with `-Quiet` without Scribe startup. Cold operations load this full schema. Serialize all writers with Cost Preflight; never hand-author ordinary state or arithmetic.

These schemas are separate from [seed-templates.md](seed-templates.md), which stamps `team.md` and `routing.md` only during Init. Scribe reads full schemas for cold operations; seed templates remain seeding-only.

Write semantics follow the state layout: `decisions.md`, `history/<agent>.md`, `history/autonomous-loop-<id>.md`, `history/autopilot-run-<id>.md`, and `notifications.md` are append-only; `state.json` uses replace semantics.

**This file carries recurring compatibility shapes, not a mandatory ordinary read.** Cost Preflight, verdicts, cycle/run summaries, and notifications are in [scribe-cold-gates-and-verdicts.md](scribe-cold-gates-and-verdicts.md), loaded by the Cold-File Dispatch Table in [scribe-procedure.md](scribe-procedure.md).

## decisions.md

Append-only log. The header is written once; every decision is appended below it and prior entries are never edited. Council Verdicts (from the Council Procedure) use the same append-only contract but a fixed schema; the placeholder shapes are in [scribe-cold-gates-and-verdicts.md](scribe-cold-gates-and-verdicts.md).

```markdown
---
description: "Append-only log of squad decisions and their rationale"
---

# Squad Decisions

Entries are appended below in chronological order. Each entry records the decision, its rationale, the turn it was made on, and a reference to an ADR when the decision is architecturally significant. Council Verdicts use the `## Council Verdict <timestamp> <topic-id>` heading and the schema in `.github/instructions/squad/squad-council.instructions.md`; Discovery Verdicts and Intake Readiness Verdicts use their own headings and schemas from `.github/instructions/squad/squad-discovery-gate.instructions.md` and `.github/instructions/squad/squad-intake-gate.instructions.md`. Prior entries are never edited or removed.
```

No append-only file ends with a marker comment: the last entry is the last thing in the file, so a new entry is always written at the very end.

## history/<agent>.md

One append-only file per dispatched agent. Replace `<agent>` with the agent's `name:` frontmatter value **verbatim** — the display name, spaces and capitalization intact, as in `history/Squad Researcher.md` or `history/BRD Builder.md`. Never slugify it, never lowercase it, and never substitute the role id: the file name is how a later turn matches a history entry back to the roster row it came from, so `squad-researcher.md` and `researcher.md` both read as a missing entry and the ledger rewrite drops that agent. Autonomous-loop runs add per-cycle dispatch entries to each role's history file using the placeholder shape below.

**The role file is created by its first dispatch, never before it.** Init writes only `history/Squad Scribe.md` with initialization overhead, not header-only role files. Create each role file and its first history/consumption entry together.

`history/Squad Scribe.md` retains `#### Consumption — Orchestration` blocks on both routes. Count actual coordinator usage plus Scribe usage only when dispatched; the filename never implies fictional Scribe tokens or a completed stage.

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

**Optional identity bullets.** When a `routing=` mode other than `off` resolved this dispatch's model, the entry additionally carries four narrative bullets immediately beneath the `#### Consumption` block, using exactly this wording, per [model-routing.md](model-routing.md) § *Identity Bullets*:

```markdown
* **Requested model** — <id routing resolved, or "none (parameter omitted)">
* **Effective model** — <the `model` value this entry's Consumption block actually recorded>
* **Observed model** — <what the host reported, per the Model Attribution ladder rung 1, or `unreported`/`unverified`>
* **Route rationale** — <assignment class, rank/override source, floor applied, `identity-mismatch:` token when applicable>
```

These bullets are additive and never a new JSON key — the closed ten-field block above is unchanged whether or not they are present. Omit all four entirely when no routing policy applied to this dispatch: a no-policy entry keeps exactly the block shape above with nothing beneath it.

**Connector provenance.** Only `Squad Connector` uses `externalProvenance` (`connector-role-modes.md` §9): no extra/missing keys. Literal `* ` bullets only. Validated reports go in `Deliverable:`; source changes go in `Outcome:`.

When Cost Preflight is configured, the `Cost Preflight Ref` and `Cost Preflight Slot` pair is also unique across history. One admitted slot authorizes one dispatch; a second entry carrying the same run, round, and slot is a replay and must be rejected before any write.

An autonomous-loop cycle replaces the entry body above with a shape that still carries its own `#### Consumption` block — see [scribe-cold-gates-and-verdicts.md](scribe-cold-gates-and-verdicts.md) for the exact placeholder, `history/autonomous-loop-<id>.md`, `history/autopilot-run-<id>.md`, and `notifications.md`, read only for the payload types named there.

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

`currentRun.modelOverrides` is always present as a key — it is never omitted — and its value is `{}` unless the user volunteered a model for a role this run; a populated map (`{"<role or agent>": "<id>"}`) records that declaration. Routed ids live in `team.md`'s `Model` column instead — see [model-routing.md](model-routing.md).

Watch Mode runs additionally carry an optional, additive `trigger` object recording the event that started the run; interactive, autonomous, and autopilot runs omit it. See `.github/instructions/squad/squad-watch-mode.instructions.md`.

Read legacy single-squad schema `1.3` without `costPreflight` as an unset ceiling with the default `not-requested` object above. On the next coordinator Cost Preflight transaction or ordinary Scribe write, atomically add the exact object, bump only `schemaVersion` to `1.4`, and preserve every existing root, `notify`, `trigger`, model, override, and accumulated-total value. Never reject or reset an existing no-ceiling run only because it predates this object.
