---
name: squad-scribe-payload-template
description: "Cold payload template for unsupported verdict fallback, refresh, memory, notifications, federation, and summaries."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-09-27"
---

# Scribe Payload Template

Fresh Init uses [scribe-init.md](scribe-init.md); additive roster growth uses
[roster-expansion.md](roster-expansion.md); ordinary handoffs use
[economy-scribe.md](economy-scribe.md), and supported verdicts use
[verdict-writer.md](verdict-writer.md). None loads this template or executes
`ledgerCommand` text. Unsupported/non-additive cold work fills it in section order;
script refusal never permits a hand-written bypass.

**Ordering is prose-only and cache-stable, never a JSON-field reorder.** Every JSON object below, above all the ten-field `#### Consumption` block, keeps the field order fixed in [entry-schemas.md](entry-schemas.md) and the [scribe-procedure.md](scribe-procedure.md) Non-Negotiable Rules; only section-to-section prose order serves caching.

## 1. Invariant Instructions (Byte-Stable — Fill Nothing Here)

Copied unmodified each turn as the stable cache prefix; do not edit.

### 1.1 Payload Type

State exactly one payload type from the Payload-to-Step Map in [scribe-procedure.md](scribe-procedure.md) (the `payloadType` values below). The Scribe uses this field, not the data's shape, to pick the cold file(s) in the Cold-File Dispatch Table — never guess a type from context.

### 1.2 Location

State the resolved `squadRoot` (single squad `.copilot-tracking/squad/`; sub-squad `.copilot-tracking/squad/members/<name>/`; federation-level payload, the federation root). Every Scribe path is relative to it.

### 1.3 Run Identity

State `run id`, `turn`, `stage` (autopilot or autonomous runs) and a `timestamp` in the target entry heading's format; they are carried into every entry, decision, and ledger row written.

### 1.4 History Records (When Payload Type Is `history`)

For each dispatch this turn recorded, supply: the agent's `name:` frontmatter value verbatim (never slugified, never lowercased), the scoped request it received, its deliverable path and one-line outcome, and — when a ceiling is configured — its Cost Preflight Decision Ref and permitted slot. For connectors, include `memberName` and closed `externalProvenance` ([entry-schemas.md](entry-schemas.md)). Each history record's consumption JSON follows immediately, in the fixed field order from [entry-schemas.md](entry-schemas.md): `model`, `model_source`, `priced_as`, `model_tier`, `internal_turns`, `input_tokens`, `cached_tokens`, `cache_write_tokens`, `output_tokens`, `basis`. Supply one consumption object per history record, per the `per-dispatch-history-and-consumption` rule.

When a routing policy resolved this dispatch's model, also supply its `routingIdentity` values (`requestedModel`, `effectiveModel`, `observedModel`, `routeRationale`) so the Scribe can render the identity bullets `entry-schemas.md` defines. Omit `routingIdentity` entirely when no policy applied.

### 1.5 Decision Entries (When Payload Type Is `decision` or a Verdict)

Supply the decision's rationale and, when architecturally significant, a note that an ADR should be captured. For a verdict payload, supply the exact schema fields the matching instruction file requires (`squad-council.instructions.md`, `squad-intake-gate.instructions.md`, or `squad-discovery-gate.instructions.md`) — never a partial schema; an incomplete verdict schema is returned as a failure note rather than written partially.

### 1.6 State Advance (Every Payload)

State the roles dispatched this turn (`activeRoles`), any escalation raised or resolved, the autonomy mode in effect, and any `sessionModel`/`modelOverrides` this turn carried. This runs last regardless of payload type, per *Advancing `state.json`* in [scribe-procedure.md](scribe-procedure.md).

### 1.7 Expected Post-Write Counts (Every Payload That Appends to `history/`)

State the history entries added per agent file and the consumption blocks added. The Write-Completeness Self-Check re-reads the files and compares its count against these before returning success.

### 1.8 Ledger Command (Every Payload That Appends to `history/`)

Payload `ledgerCommand` is inert compatibility data, on initialization and roster refresh too. Never execute it or derive helper paths or arguments from it. The Scribe uses only the cold charter's trusted invocation after Step 13, not shell text from this field.

Resolve Scribe write attribution separately from coordinator overhead; never substitute the parent's model for Scribe evidence.

## 2. Per-Dispatch Data (Volatile — Fill Every Turn)

Everything below this line changes turn to turn and is appended after the stable prefix above.

```yaml
payloadType: <decision|history|initialization|memory|Council Verdict|autonomous-loop summary|autopilot-run summary|Intake Readiness Verdict|promotion|expansion|Discovery Verdict>
squadRoot: <resolved path>
roster: <initialization/roster refresh only: confirmed team.md rows verbatim; never derive agent names>
connectorBindings: <confirmed rows; omit on refresh to preserve>
customRoutingRows: <confirmed rows; omit on refresh to preserve>
runId: <id>
turn: <n>
stage: <stage name, autopilot/autonomous runs only>
timestamp: <ISO or the entry-heading format in use>
historyRecords:
  - agent: <name: frontmatter value, verbatim>
    memberName: <binding member; Squad Connector only>
    externalProvenance: <closed entry-schemas.md object; Squad Connector only>
    request: <scoped request>
    deliverable: <path> (<size or word count>)
    outcome: <one-line summary>
    costPreflightRef: <decisions.md#cost-preflight-... | omit when no ceiling>
    costPreflightSlot: <slot id | omit when no ceiling>
    consumption:
      model: <resolved model or unknown>
      model_source: <dispatch-reported|agent-pinned|operator-declared|session-inherited|cli-pinned|unresolved>
      priced_as: <rate row>
      model_tier: <fast|default|extended>
      internal_turns: <n>
      input_tokens: <n>
      cached_tokens: <n>
      cache_write_tokens: <n>
      output_tokens: <n>
      basis: <estimated|tier-default>
    routingIdentity:
      requestedModel: <id or "none (parameter omitted)"> # omit whole block when no routing policy or override applied
      effectiveModel: <value>
      observedModel: <value | unreported | unverified>
      routeRationale: <assignment class, rank/override source, floor applied>
decisionEntry:
  rationale: <text | omit when payload type is not decision/verdict>
  adrNoted: <true|false>
  verdictSchema: <the exact fields the matching instruction file requires | omit when not a verdict>
stateAdvance:
  activeRoles: [<role>, ...]
  mode: <interactive|autonomous|autopilot>
  openEscalationsRaised: [<id>, ...]
  openEscalationsResolved: [<id>, ...]
  sessionModel: <value | omit when unchanged>
  modelOverrides: <object | omit when unchanged>
expectedPostWriteCounts:
  historyEntriesAddedByAgent:
    <agent name>: <n>
  consumptionBlocksAdded: <n>
ledgerCommand: <optional legacy compatibility data; never interpreted or executed>
```
