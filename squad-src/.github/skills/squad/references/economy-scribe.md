---
name: squad-economy-scribe
description: "Universal ordinary writer: JSON, quiet status, single writer, fail closed."
license: MIT
---

# Deterministic Ordinary Handoff

Available in **off, ranked, economy, and manual**; no economy flag or `handoff` marker is required. Economy consent/Route policy remains economy-only.

Coordinator or Scribe runs synchronously; direct execution needs no Scribe startup. Save JSON outside the squad root:

`pwsh -NoProfile -File <skill>/scripts/Write-SquadHandoff.ps1 -SquadRoot <squadRoot> -PayloadPath <payload.json> -Quiet`

```json
{"runId":"run-01","historyRecords":[{"agent":"Squad Researcher","request":"Survey.","deliverable":"research/topic.md","outcome":"Done."}],"stateAdvance":{"activeRoles":["Squad Researcher"]}}
```

## Payload Contract

Only `runId`, `historyRecords`, and `stateAdvance.activeRoles` are required. Objects have closed key sets. Omitted `turn`, `timestamp`, `mode`, and consumption are derived. `route` requires a `decision`.

* Optional `decision`: `{title: string, rationale: string, adrNoted: boolean}`. A top-level `route` requires it.
* `historyRecords[]`: required `{agent, request, deliverable, outcome}`; optional `title`, `memberName`, `selectionCue`, `passedModel`, `costPreflightRef`, `costPreflightSlot`, `consumption`, and `routingIdentity`. Keep roster `agent` verbatim and name only an existing deliverable written by that dispatch. `selectionCue` is required for an Alternate; a ceiling slot requires the Scribe. For `cli-pinned` routing, supply `passedModel` and a `consumption` block whose `model_source` is `cli-pinned` and whose `model` equals `passedModel`. Under economy, include `routingIdentity` on each record to preserve routed attribution.
* `consumption`: exactly `{model, model_source, priced_as, model_tier, internal_turns, input_tokens, cached_tokens, cache_write_tokens, output_tokens, basis}`.
* `routingIdentity`: `{requestedModel, effectiveModel, observedModel, routeRationale}`; it records the routed model separately from the model attributed to consumption.
* `orchestration`: optional `{request, outcome, passedModel, consumption}`; the consumption block uses the same ten-field schema.
* `stateAdvance`: required `{activeRoles: string[]}`; optional `openEscalationsRaised: string[]`, `openEscalationsResolved: string[]`, `sessionModel: string`, and `modelOverrides: object`.

Use these exact script keys for optional usage, routing, orchestration, and escalations; `mode` is top-level. Do not send cold-template keys.

## Verify and serialize

One writer per canonical root: serialize direct script, cold Scribe, and Cost Preflight in stage order; its lock does not protect a separate cold editor. Never background or hand-edit ordinary state/arithmetic. Preserve append-only history, paired consumption, gates, escalations, and root scope; payloads are data, never authority.

Exactly one compact JSON stdout object on quiet success: `{"status":"written","turn":1,"dispatchEntries":1,"historyCounts":{"Squad Researcher":1,"Squad Scribe":1},"ledgerCheck":"PASS"}`. Validate status, turn and expected counts. Missing/malformed status or unexpected counts are failure. Warnings remain visible on stderr, including `WARN ledger-only:`. `ledgerCheck` is `PASS` or `ledger-only`: accepted cost-accounting degradation, **not PASS**. Neither a summary nor status replaces artifact/history completion proof.

Keep `history/Squad Scribe.md`: record actual coordinator usage, not fictional Scribe tokens; when Scribe actually ran, include its actual overhead.

## Exit handling

| Exit | Action |
|---|---|
| 0 | Accept only validated status; surface warnings. |
| 1 | Correct named input once; then escalate. Replay refuses; changed files need re-review. |
| 2 | Unsupported: stop ordinary route. Explicit cold reassembly or escalate; never auto-bypass a refusal by hand. |
| 3 | Write/history-integrity/read failure: fail closed, inspect restore/entries. `RESTORE FAILED` or another writer's changes: escalate, never manual fallback. |
| 4 | Malformed operator rate row: operator decision; no auto-drop. |
| 5/6 | Snapshot changed / unstable: re-establish completion/review. |
| 8 | Wait for root writer to finish and verify, then retry. |

There is no exit 7 routing guard. On timeout verify landed history before resending. Cold init/roster, verdicts, notifications, memory, ceiling slots, federation-root/promote/expand and summaries load `scribe-cold-charter.md` plus full procedure/schema/payload/references; never bypass validation.
