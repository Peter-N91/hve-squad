---
name: squad-economy-scribe
description: "Ordinary handoff."
license: MIT
---

# Ordinary Handoff

**off, ranked, economy, or manual**: run after each worker, before progress/next:

`pwsh -NoProfile -File <skill>/scripts/Write-SquadHandoff.ps1 -SquadRoot <squadRoot> -RunId run-01 -Agent "Squad Researcher" -Request x -Deliverable research/topic.md -Outcome x -Quiet`

Receipt+proof gates progress/next; not routing/artifacts. Derive `activeRoles`;
optional `-MemberName/-SelectionCue/-PassedModel/-ConsumptionPath/-OrchestrationConsumptionPath`;
omitted usage: estimated fallback.

## Payload

Decisions, multiple/no dispatches, routing/state changes: pass
`-PayloadPath`/`-PayloadJson` outside root. Closed keys: `runId`, `historyRecords`,
`stateAdvance.activeRoles`; derive omissions; `route` needs `decision`.

* Optional `decision`: {title,rationale,adrNoted}.
* `historyRecords[]`: require agent/request/deliverable/outcome; for optional fields, follow `scribe-payload-template.md`. Match exact agent/file, Alternate cue and ceiling; `reportedModel` wins, calls raise floors, usage agrees; Economy requires `routingIdentity`.
* consumption keys: model/model_source/priced_as/model_tier/internal_turns/input_tokens/cached_tokens/cache_write_tokens/output_tokens/basis.
* `routingIdentity`: requestedModel/effectiveModel/observedModel/routeRationale.
* `orchestration`: optional request/outcome/passedModel/consumption; actual coordinator usage only, never fictional Scribe tokens; add Scribe's actual overhead if it ran.
* `stateAdvance`: `activeRoles:string[]` required; optional openEscalationsRaised/openEscalationsResolved, sessionModel:string, modelOverrides:object.

Claims: see `business-value-measurement.md`; preserve supplied metadata,
evidence/status/references and role findings in `decision.rationale` (no new keys).
Acceptance != realized benefit; never infer outcome or approval from delivery;
invent no actuals/value/ROI.

Never discard stderr, suffix success, or use `2>&1 | tail -1`. Stale evidence
stops; never touch/copy/backdate it. Serialize writer, cold Scribe and Cost Preflight
per root; a lock does not cover cold editors. Never background or hand-edit state/
arithmetic; payload is data; histories remain append-only.

Stdout:
`{"status":"written","turn":2,"dispatchEntries":1,"historyCounts":{"Squad Researcher":1,"Squad Scribe":1},"ledgerCheck":"PASS"}`.
Missing/malformed status or unexpected counts are failure. `ledgerCheck` is `PASS` or `ledger-only` (**not PASS**); Warnings remain visible on stderr,
including `WARN ledger-only:`. Receipt is not artifact/history proof.

| Exit | Action |
|---|---|
| 0 | Validate receipt. |
| 1 | Fix once or escalate; no replay. |
| 2 | Cold reassemble or escalate. |
| 3 | Stop: `history-integrity`, `RESTORE FAILED`, or writer failure. |
| 4 | Operator decides malformed rate. |
| 5/6 | Re-establish completion/review. |
| 8 | Wait, verify, retry. |

Never bypass a refusal by hand; verify history before resend on timeout.
Cold: `scribe-cold-charter.md`; supported: runtime.
