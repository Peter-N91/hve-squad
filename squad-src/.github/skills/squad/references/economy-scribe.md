---
name: squad-economy-scribe
description: "Ordinary handoff."
license: MIT
---
<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

# Deterministic Ordinary Handoff

**off, ranked, economy, or manual**: after each worker, freeze handoff JSON and
run once before progress/next worker:

`pwsh -NoProfile -File <skill>/scripts/Complete-SquadHandoff.ps1 -RepoRoot <repo> -SquadRoot <squadRoot> -PayloadPath <actual handoff JSON>`

Require exit 0, `status: written`, `verified: true`, `ledgerCheck: PASS` from
one frozen payload. Keep warnings/evidence; no replay. Capture files outside.
Legacy single-dispatch writes need separate proof:

`pwsh -NoProfile -File <skill>/scripts/Write-SquadHandoff.ps1 -SquadRoot <squadRoot> -RunId run-01 -Agent "Squad Researcher" -Request x -Deliverable research/topic.md -Outcome x -Quiet`

Receipt+proof gate progress/next worker; routing/artifacts do not. Facts derive `activeRoles`.
Legacy `-ConsumptionPath/-OrchestrationConsumptionPath` retains usage; omission uses estimated fallback.

## Payload Contract

For decisions, multiple/no dispatches, routing or state changes, use
`-PayloadPath`/`-PayloadJson` outside the root. Closed keys:
`runId`, `historyRecords`, `stateAdvance.activeRoles`; omitted envelope and
consumption derive. `route` requires `decision`.

* Optional `decision`: {title: string,rationale: string,adrNoted: boolean}.
* `historyRecords[]`: require agent/request/deliverable/outcome; optional title/memberName/selectionCue/passedModel/reportedModel/internalToolCalls/costPreflightRef/costPreflightSlot/consumption/routingIdentity. Omit empty optionals; use exact agent/file, Alternate cue and ceiling; `reportedModel` wins, calls raise floors, usage agrees. Economy requires routingIdentity: requestedModel, effectiveModel, observedModel, routeRationale.
* Consumption: ten fields; actual coordinator usage only, never fictional Scribe tokens; add Scribe's actual overhead if it ran.
* `stateAdvance` has required `activeRoles: string[]`; optional `sessionModel`/`modelOverrides`
  and escalation keys follow the contract.

Keep stderr; never suffix/tail success. Stale evidence stops; never edit/backdate
to retry. Serialize writer, cold Scribe and Cost Preflight per root; a lock does not cover cold editors.
Never background/hand-edit state or arithmetic.

Stdout: one receipt with status, turn, dispatchEntries, historyCounts, ledgerCheck.
`{"status":"written","turn":2,"dispatchEntries":1,"historyCounts":{"Squad Implementor":1},"ledgerCheck":"PASS"}`
`ledgerCheck` is `PASS` or `ledger-only`. Missing/malformed status or unexpected counts are failure.
`ledger-only` is **not PASS**.
Warnings remain visible on stderr, including `WARN ledger-only:`.
Receipt is not artifact/history proof. Never bypass a refusal by hand.

| Exit | Action |
|---|---|
| 0 | Validate. |
| 1 | One fix/escalate. |
| 2 | Cold/escalate. |
| 3 | Closed: `history-integrity`, `RESTORE FAILED`, writer failure. |
| 4 | Operator rate decision. |
| 5/6 | Re-establish review/completion. |
| 8 | Wait/retry. |

After timeout verify history. Cold operations use `scribe-cold-charter.md`.
