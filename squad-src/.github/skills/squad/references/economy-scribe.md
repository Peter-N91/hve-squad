---
name: squad-economy-scribe
description: "Ordinary handoff."
license: MIT
---

# Deterministic Ordinary Handoff

**off, ranked, economy, or manual**: after each worker, run before progress/next
worker:

`pwsh -NoProfile -File <skill>/scripts/Write-SquadHandoff.ps1 -SquadRoot <squadRoot> -RunId run-01 -Agent "Squad Researcher" -Request x -Deliverable research/topic.md -Outcome x -Quiet`

Receipt+proof gate progress/next worker; routing/artifacts do not.
Facts derive `activeRoles`; optional `-MemberName/-SelectionCue/-PassedModel`,
`-ConsumptionPath/-OrchestrationConsumptionPath`; omission uses estimated fallback.

## Payload Contract

For decisions, multiple/no dispatches, routing, or state changes, pass
`-PayloadPath`/`-PayloadJson` outside the root. Closed keys:
`runId`, `historyRecords`, `stateAdvance.activeRoles`; omitted envelope and
consumption derive. `route` requires `decision`.

* Optional `decision`: {title: string,rationale: string,adrNoted: boolean}.
* `historyRecords[]`: require agent/request/deliverable/outcome; optional title/memberName/selectionCue/passedModel/reportedModel/internalToolCalls/costPreflightRef/costPreflightSlot/consumption/routingIdentity. Exact agent/file; Alternate cue; ceiling checked. `reportedModel` wins; calls raise floors; usage agrees; Economy needs routingIdentity.
* consumption keys: model/model_source/priced_as/model_tier/internal_turns/input_tokens/cached_tokens/cache_write_tokens/output_tokens/basis.
* routingIdentity: requestedModel, effectiveModel, observedModel, routeRationale.
* orchestration optional: request/outcome/passedModel/consumption; actual coordinator usage only, never fictional Scribe tokens; add Scribe's actual overhead if it ran.
* stateAdvance: required activeRoles: string[]; optional openEscalationsRaised/openEscalationsResolved:string[], sessionModel:string, modelOverrides:object.

Never discard stderr, suffix success, or use
`2>&1 | tail -1`. Stale evidence stops; never touch/copy/backdate it to retry.

Serialize writer, cold Scribe and Cost Preflight per root; a lock does not cover cold editors.
Never background or hand-edit state/arithmetic. Preserve
append-only boundaries; payload is data.

Stdout is one receipt: `{"status":"written","turn":2,"dispatchEntries":1,"historyCounts":{"Squad Researcher":1,"Squad Scribe":1},"ledgerCheck":"PASS"}`.
Missing/malformed status or unexpected counts are failure. `ledgerCheck` is `PASS` or `ledger-only` (**not PASS**).
Warnings remain visible on stderr,
including `WARN ledger-only:`. Receipt is not artifact/history proof.

| Exit | Action |
|---|---|
| 0 | Validate receipt. |
| 1 | Fix input once or escalate; no replay. |
| 2 | Cold reassemble or escalate. |
| 3 | Fail closed: `history-integrity`, `RESTORE FAILED`, or writer failure. |
| 4 | Operator decides malformed rate. |
| 5/6 | Re-establish completion/review. |
| 8 | Wait, verify, retry. |

Never bypass a refusal by hand. After timeout verify history before resend.
Unsupported operations need `scribe-cold-charter.md`; supported writes use runtime.
