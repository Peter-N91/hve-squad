---
name: squad-scribe-payload-template
description: "The single payload template both the Squad Coordinator and Squad Federation Coordinator fill when handing state to the Squad Scribe. Byte-stable instructions first, volatile per-dispatch data last, for cache-stable prefixing. Read always."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-09-27"
---

# Scribe Payload Template

This is the one payload shape both coordinators fill at hand-off. Filling it in this section order keeps a host's prompt cache warm: the fixed text at the top never changes, so only the tail needs re-encoding.

**Ordering is prose-only and cache-stable, never a JSON-field reorder.** Every JSON object below — most importantly the ten-field `#### Consumption` block — keeps the exact field order fixed in [entry-schemas.md](entry-schemas.md) and [scribe-procedure.md](scribe-procedure.md) Non-Negotiable Rules regardless of where the object sits in this template. Only the section-to-section prose order is chosen for cache stability.

## 1. Invariant Instructions (Byte-Stable — Fill Nothing Here)

Read, do not edit, this section on every dispatch. It is copied unmodified each turn, the stable prefix a cache-aware host reuses.

### 1.1 Payload Type

State exactly one payload type from the Payload-to-Step Map in [scribe-procedure.md](scribe-procedure.md): `decision`, `history`, `initialization`, `memory`, `Council Verdict`, `autonomous-loop summary`, `autopilot-run summary`, `Intake Readiness Verdict`, `promotion`, `expansion`, or `Discovery Verdict`. The Scribe uses this single field, not the shape of the data below it, to decide which cold file(s) the Cold-File Dispatch Table names — never guess a type from context.

### 1.2 Location

State the resolved `squadRoot` this payload targets. The default `.copilot-tracking/squad/` preserves single-squad behavior; a federation sub-squad resolves to `.copilot-tracking/squad/members/<name>/`; a federation-level payload resolves to the federation root. Every path the Scribe writes is relative to this value.

### 1.3 Run Identity

State `run id`, `turn`, `stage` (when the run is autopilot or autonomous), and a `timestamp` in the format the target entry heading uses. These four identify which run and turn this payload belongs to and are carried into every entry, decision, and ledger row this dispatch writes.

### 1.4 History Records (When Payload Type Is `history`)

For each dispatch this turn recorded, supply: the agent's `name:` frontmatter value verbatim (never slugified, never lowercased), the scoped request it received, its deliverable path and one-line outcome, and — when a ceiling is configured — its Cost Preflight Decision Ref and permitted slot. Each history record's consumption JSON follows immediately, in the fixed field order from [entry-schemas.md](entry-schemas.md): `model`, `model_source`, `priced_as`, `model_tier`, `internal_turns`, `input_tokens`, `cached_tokens`, `cache_write_tokens`, `output_tokens`, `basis`. Supply one consumption object per history record — never one without the other, per the `per-dispatch-history-and-consumption` rule.

When a routing policy resolved this dispatch's model, also supply its `routingIdentity` values (`requestedModel`, `effectiveModel`, `observedModel`, `routeRationale`) so the Scribe can render the four identity bullets `entry-schemas.md` defines. Omit `routingIdentity` entirely when no policy applied — never emit it for a no-policy dispatch.

### 1.5 Decision Entries (When Payload Type Is `decision` or a Verdict)

Supply the decision's rationale and, when architecturally significant, a note that an ADR should be captured. For a verdict payload, supply the exact schema fields the matching instruction file requires (`squad-council.instructions.md`, `squad-intake-gate.instructions.md`, or `squad-discovery-gate.instructions.md`) — never a partial schema; an incomplete verdict schema is returned as a failure note rather than written partially.

### 1.6 State Advance (Every Payload)

State the roles dispatched this turn (`activeRoles`), any escalation raised or resolved, the autonomy mode in effect, and any `sessionModel`/`modelOverrides` this turn carried. This runs last regardless of payload type, per *Advancing `state.json`* in [scribe-procedure.md](scribe-procedure.md).

### 1.7 Expected Post-Write Counts (Every Payload That Appends to `history/`)

State what the Scribe should find after writing: the number of history entries this turn is adding per agent file, and the number of consumption blocks this turn is adding. The Scribe's Write-Completeness Self-Check re-reads the files and compares its own count against these numbers before returning success — this field is what makes that check possible rather than advisory.

### 1.8 Ledger Command (Every Payload That Appends to `history/`)

When the coordinator has a shell with `pwsh` 7+, supply `ledgerCommand`: the exact `-Write` command with the installed squad skill's absolute script path, as in the YAML below — on initialization and roster refresh too, which append the Scribe's orchestration block. The Scribe runs it verbatim as its last write and never hand-writes `consumption.md` rows or the two `currentRun` totals while it is supplied.

## 2. Per-Dispatch Data (Volatile — Fill Every Turn)

Everything below this line changes turn to turn and is appended after the stable prefix above.

```yaml
payloadType: <decision|history|initialization|memory|Council Verdict|autonomous-loop summary|autopilot-run summary|Intake Readiness Verdict|promotion|expansion|Discovery Verdict>
squadRoot: <resolved path>
roster: <initialization/roster refresh only: every confirmed team.md row, cells verbatim; the Scribe never derives an agent name>
runId: <id>
turn: <n>
stage: <stage name, autopilot/autonomous runs only>
timestamp: <ISO or the entry-heading format in use>
historyRecords:
  - agent: <name: frontmatter value, verbatim>
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
ledgerCommand: pwsh -NoProfile -File "<skill root>/scripts/Measure-SquadLedger.ps1" -SquadRoot "<squadRoot>" -Write -SessionLog auto  # omit only without pwsh 7+
```
