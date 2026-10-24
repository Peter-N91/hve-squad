---
name: squad-economy-scribe
description: "Ordinary handoff."
license: MIT
---

# Deterministic Ordinary Handoff

Applies in **off, ranked, economy, and manual**; no marker required. Consent/Route are economy-only. Run synchronously:

`pwsh -NoProfile -File <skill>/scripts/Write-SquadHandoff.ps1 -SquadRoot <squadRoot> -RunId run-01 -Agent "Squad Researcher" -Request x -Deliverable research/topic.md -Outcome x -Quiet`

Use actual facts; `activeRoles` derives from `Agent`. `-MemberName`,
`-SelectionCue`, and `-PassedModel` are optional attribution. Supply usage through
`-ConsumptionPath` and `-OrchestrationConsumptionPath`; omissions are estimated,
not measured.

## Payload Contract

For decisions, multiple/no dispatches, connector/routing metadata, escalations, or
state changes, use `-PayloadPath`/`-PayloadJson` with JSON outside the squad root.
Keys are closed. `runId`, `historyRecords`, and `stateAdvance.activeRoles` are
required; omitted `turn`, `timestamp`, `mode`, and consumption derive. `mode` is
top-level; `route` needs `decision`.

* Optional `decision`: `{title: string,rationale: string,adrNoted: boolean}`.
* `historyRecords[]`: required agent/request/deliverable/outcome; optional title/memberName/selectionCue/passedModel/reportedModel/internalToolCalls/costPreflightRef/costPreflightSlot/consumption/routingIdentity. Use the roster-exact agent and a real file. Alternate needs its cue; ceiling slots need Scribe. `reportedModel` is actual host/worker identity and outranks pins/requests; tool counts raise estimator floors. Supplied consumption must agree. Economy needs routingIdentity.
* consumption keys: model/model_source/priced_as/model_tier/internal_turns/input_tokens/cached_tokens/cache_write_tokens/output_tokens/basis.
* routingIdentity: requestedModel, effectiveModel, observedModel, routeRationale.
* Optional orchestration: request/outcome/passedModel/consumption (same keys): actual coordinator usage only, never fictional Scribe tokens; add Scribe's actual overhead if it ran.
* stateAdvance: required activeRoles: string[]; optional openEscalationsRaised/openEscalationsResolved:string[], sessionModel:string, modelOverrides:object.

No cold-template keys. Preserve exits: never use `2>&1 | tail -1`, discard
stderr, or append a success suffix. Stale evidence stops; never touch, copy, or
backdate it to retry.

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

Never bypass a refusal by hand; there is no exit 7 routing guard. On timeout,
verify history before resend. Unsupported operations need
`scribe-cold-charter.md`; supported direct Init and federation-root writes use
their runtime contract.
