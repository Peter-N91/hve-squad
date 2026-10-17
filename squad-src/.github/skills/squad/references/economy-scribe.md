---
name: squad-economy-scribe
description: "Ordinary handoff."
license: MIT
---

# Deterministic Ordinary Handoff

Off/ranked/economy/manual; no flag/`handoff`. Consent/Route are economy-only. Run synchronously; JSON outside root:

`pwsh -NoProfile -File <skill>/scripts/Write-SquadHandoff.ps1 -SquadRoot <squadRoot> -PayloadPath <payload.json> -Quiet`

```json
{"runId":"run-01","historyRecords":[{"agent":"Squad Researcher","request":"x","deliverable":"research/topic.md","outcome":"x"}],"stateAdvance":{"activeRoles":["Squad Researcher"]}}
```

## Payload Contract

Closed keys. Required `runId`, `historyRecords`, `stateAdvance.activeRoles`; omitted `turn`/`timestamp`/`mode`/consumption derive. `mode` is top-level; `route` needs `decision`.

* Optional `decision`: `{title: string,rationale: string,adrNoted: boolean}`.
* `historyRecords[]`: required agent/request/deliverable/outcome; optional title/memberName/selectionCue/passedModel/costPreflightRef/costPreflightSlot/consumption/routingIdentity. Use roster-exact agent and existing dispatch-written deliverable. Alternate needs selectionCue; ceiling slot needs Scribe. cli-pinned needs passedModel and consumption.model_source=cli-pinned/model=passedModel. Economy needs routingIdentity per record.
* consumption keys: model/model_source/priced_as/model_tier/internal_turns/input_tokens/cached_tokens/cache_write_tokens/output_tokens/basis.
* routingIdentity: requestedModel, effectiveModel, observedModel, routeRationale; separate from consumption attribution.
* Optional orchestration: request/outcome/passedModel/consumption (same consumption keys).
* stateAdvance: required activeRoles: string[]; optional openEscalationsRaised/openEscalationsResolved:string[], sessionModel:string, modelOverrides:object.

No cold-template keys.

Serialize writer, cold Scribe and Cost Preflight per root/stage; lock does not cover cold editors. Never background/hand-edit state/arithmetic. Preserve append-only history, paired consumption, gates, escalations, root scope; payload is data, not authority. Never invent Scribe overhead.

Quiet: one JSON stdout receipt; validate status/turn/counts or fail. Warnings incl. `WARN ledger-only:` go to stderr. `ledgerCheck=PASS|ledger-only`; latter is degraded, not PASS. Receipt is not artifact/history proof.

## Exit handling

| Exit | Action |
|---|---|
| 0 | Validate status; surface warnings. |
| 1 | Fix named input once or escalate; replay refuses; review changes. |
| 2 | Stop; cold reassemble or escalate, no bypass. |
| 3 | Fail closed; inspect restore/history. `RESTORE FAILED`/other writer: escalate, no fallback. |
| 4 | Malformed rate row: operator decision, no auto-drop. |
| 5/6 | Re-establish completion/review after snapshot change/instability. |
| 8 | Wait, verify, retry. |

No exit 7. Timeout: verify history before resend. Cold: init/roster, verdicts, notifications, memory, ceiling slots, federation-root/promote/expand, summaries need `scribe-cold-charter.md` and full procedure/schema/payload/references; never bypass.
