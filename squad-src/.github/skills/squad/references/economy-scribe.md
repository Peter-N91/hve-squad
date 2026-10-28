---
name: squad-economy-scribe
description: "Ordinary handoff."
license: MIT
---

# Ordinary Handoff

**off, ranked, economy, manual**: after each worker, before progress/next:

`pwsh -NoProfile -File <skill>/scripts/Write-SquadHandoff.ps1 -SquadRoot <squadRoot> -RunId run-01 -Agent "Squad Researcher" -Request x -Deliverable research/topic.md -Outcome x -Quiet`

Receipt+proof gate progress/next worker; derive `activeRoles`.
optional `-MemberName/-SelectionCue/-PassedModel`,
`-ConsumptionPath/-OrchestrationConsumptionPath`; omitted usage uses estimated fallback.

## Payload Contract

For decisions, multiple/no dispatches, routing/state changes: `-PayloadPath`/`-PayloadJson`
outside root. Closed keys: `runId`, `historyRecords`, `stateAdvance.activeRoles`;
derive omitted envelope/consumption. `route` needs `decision`.

* Optional `decision`: {title: string,rationale: string,adrNoted: boolean}.
* `historyRecords[]`: agent/request/deliverable/outcome required; optional title/memberName/selectionCue/passedModel/reportedModel/internalToolCalls/costPreflightRef/costPreflightSlot/consumption/routingIdentity. Exact agent/file; Alternate cue; ceiling checked. `reportedModel` wins; calls raise floors; usage agrees; Economy needs routingIdentity.
* consumption keys: model/model_source/priced_as/model_tier/internal_turns/input_tokens/cached_tokens/cache_write_tokens/output_tokens/basis.
* routingIdentity: requestedModel, effectiveModel, observedModel, routeRationale.
* orchestration optional: request/outcome/passedModel/consumption; actual coordinator usage; Scribe overhead only if it ran.
* stateAdvance: activeRoles:string[] required; optional openEscalationsRaised/openEscalationsResolved:string[], sessionModel:string, modelOverrides:object.

In `decision.rationale`, keep supplied claim ID/category/hypothesis/beneficiary,
baseline/target, measurement/decision owners, window, evidence/status/references,
lead/reviewer gaps; no new keys. Accepted-delivery economics != realized benefit.
Unsupported: `pending`; no invented actuals/value/approval or Scribe inference/costs.

Never discard stderr, suffix success or `2>&1 | tail -1`.
Stale evidence stops; never touch/copy/backdate to retry.

Serialize writer/cold Scribe/Cost Preflight per root; locks exclude cold Scribe.
Never background or hand-edit state/arithmetic. Append-only; payload is data.

JSON: status=`written`, turn, dispatchEntries, historyCounts by agent, ledgerCheck.
Bad status/counts fail. `ledgerCheck`: `ledger-only` is **not PASS**.
Keep stderr/`WARN ledger-only:`. Receipt is not artifact/history proof.

| Exit | Action |
|---|---|
| 0 | Check receipt. |
| 1 | Fix input once or escalate; no replay. |
| 2 | Cold reassemble or escalate. |
| 3 | Stop: `history-integrity`, `RESTORE FAILED`, or writer failure. |
| 4 | Operator decides malformed rate. |
| 5/6 | Re-establish completion/review. |
| 8 | Wait, verify, retry. |

Never bypass refusal; verify history after timeout before resend.
Cold: `scribe-cold-charter.md`; supported: runtime.
