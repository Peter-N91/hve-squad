---
name: squad-economy-scribe
description: "Ordinary handoff."
license: MIT
---
<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

# Ordinary Handoff

**off, ranked, economy, or manual**: after each worker:

`pwsh -NoProfile -File <skill>/scripts/Write-SquadHandoff.ps1 -SquadRoot <squadRoot> -RunId run-01 -Agent "Squad Researcher" -Request x -Deliverable research/topic.md -Outcome x -Quiet`

Receipt+proof gate progress/next worker; derive `activeRoles`. Optional `-MemberName/-SelectionCue/-PassedModel/-ConsumptionPath/-OrchestrationConsumptionPath`; omission uses estimated fallback.

## Payload Contract

For decisions, multiple/no dispatches, routing, or state changes: `-PayloadPath`/`-PayloadJson` outside root. Closed keys: `runId`, `historyRecords`, `stateAdvance.activeRoles`; derive omitted envelope/consumption. `route` needs `decision`.

* Optional `decision`: {title:string,rationale:string,adrNoted:boolean}.
* `historyRecords[]`: require agent/request/deliverable/outcome; optional title/memberName/selectionCue/passedModel/reportedModel/internalToolCalls/costPreflightRef/costPreflightSlot/consumption/routingIdentity. Exact agent/file; Alternate cue; ceiling checked; `reportedModel` wins; Economy needs routingIdentity.
* consumption: model/model_source/priced_as/model_tier/internal_turns/input_tokens/cached_tokens/cache_write_tokens/output_tokens/basis.
* routingIdentity: requestedModel, effectiveModel, observedModel, routeRationale.
* orchestration: request/outcome/passedModel/consumption; actual coordinator usage only, never fictional Scribe tokens; add Scribe's actual overhead if it ran.
* stateAdvance: activeRoles:string[]; optional openEscalationsRaised/openEscalationsResolved, sessionModel, modelOverrides.

In `decision.rationale`, keep supplied claim ID/category/hypothesis/beneficiary, baseline/target, owners, window, evidence/status/references, gaps; no new keys. Accepted-delivery != realized benefit. Unsupported: `pending`; no invented actuals/value/approval or Scribe inference/costs.

Never discard stderr, suffix success or `2>&1 | tail -1`. Stale evidence stops; never backdate.
Serialize writer, cold Scribe and Cost Preflight per root; a lock does not cover cold editors. Never background or hand-edit state/arithmetic. Append-only; payload is data.

Stdout: `{"status":"written","turn":2,"dispatchEntries":1,"historyCounts":{"Squad Researcher":1,"Squad Scribe":1},"ledgerCheck":"PASS"}`. Missing/malformed status or unexpected counts are failure. `ledgerCheck` is `PASS` or `ledger-only` (**not PASS**). Warnings remain visible on stderr, including `WARN ledger-only:`. Receipt is not artifact/history proof.

| Exit | Action |
|---|---|
| 0 | Check receipt. |
| 1 | Fix once or escalate; no replay. |
| 2 | Cold reassemble or escalate. |
| 3 | Stop: `history-integrity`, `RESTORE FAILED`, writer failure. |
| 4 | Operator decides bad rate. |
| 5/6 | Re-establish completion/review. |
| 8 | Wait, verify, retry. |

Never bypass a refusal by hand; verify history after timeout. Cold: `scribe-cold-charter.md`.
