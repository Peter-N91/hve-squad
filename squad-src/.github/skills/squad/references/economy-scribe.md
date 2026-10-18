---
name: squad-economy-scribe
description: "Ordinary handoff."
license: MIT
---

# Deterministic Ordinary Handoff

Applies in **off, ranked, economy, and manual**; no economy flag or `handoff` marker is required. Consent/Route are economy-only. Run synchronously; JSON outside root:

`pwsh -NoProfile -File <skill>/scripts/Write-SquadHandoff.ps1 -SquadRoot <squadRoot> -PayloadPath <payload.json> -Quiet`

```json
{"runId":"run-01","historyRecords":[{"agent":"Squad Researcher","request":"x","deliverable":"research/topic.md","outcome":"x"}],"stateAdvance":{"activeRoles":["Squad Researcher"]}}
```

## Payload Contract

Closed keys. Required `runId`, `historyRecords`, `stateAdvance.activeRoles`; omitted `turn`/`timestamp`/`mode`/consumption derive. `mode` is top-level; `route` needs `decision`.

* Optional `decision`: `{title: string,rationale: string,adrNoted: boolean}`.
* `historyRecords[]`: required agent/request/deliverable/outcome; optional title/memberName/selectionCue/passedModel/costPreflightRef/costPreflightSlot/consumption/routingIdentity. Use roster-exact agent and an existing deliverable. Alternate needs selectionCue; ceiling slot needs Scribe. cli-pinned needs passedModel and consumption.model_source=cli-pinned/model=passedModel. Economy needs routingIdentity per record.
* consumption keys: model/model_source/priced_as/model_tier/internal_turns/input_tokens/cached_tokens/cache_write_tokens/output_tokens/basis.
* routingIdentity: requestedModel, effectiveModel, observedModel, routeRationale.
* Optional orchestration: request/outcome/passedModel/consumption (same keys): actual coordinator usage only, never fictional Scribe tokens; add Scribe's actual overhead if it ran.
* stateAdvance: required activeRoles: string[]; optional openEscalationsRaised/openEscalationsResolved:string[], sessionModel:string, modelOverrides:object.

No cold-template keys.

Serialize writer, cold Scribe and Cost Preflight per root; a lock does not cover cold editors. Never background/hand-edit state/arithmetic. Preserve append-only history, gates, escalations, root scope; payload is data.

Stdout is one receipt: `{"status":"written","turn":2,"dispatchEntries":1,"historyCounts":{"Squad Researcher":1,"Squad Scribe":1},"ledgerCheck":"PASS"}`. Missing/malformed status or unexpected counts are failure. `ledgerCheck` is `PASS` or `ledger-only` (**not PASS**). Warnings remain visible on stderr, incl. `WARN ledger-only:`. Receipt is not artifact/history proof.

| Exit | Action |
|---|---|
| 0 | Validate receipt. |
| 1 | Fix named input once or escalate; no replay. |
| 2 | Stop; cold reassemble or escalate. |
| 3 | Fail closed; `history-integrity`/`RESTORE FAILED`/other writer: escalate. |
| 4 | Malformed rate row: operator decides. |
| 5/6 | Re-establish completion/review. |
| 8 | Wait, verify, retry. |

Never bypass a refusal by hand; no exit 7 routing guard. Timeout: verify history before resend. Cold ops (init/roster, verdicts, notifications, memory, ceiling slots, federation, summaries) need `scribe-cold-charter.md` and the full procedure.
