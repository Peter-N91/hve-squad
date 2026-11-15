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

**off, ranked, economy, or manual**: freeze the actual handoff JSON and run once
before progress/next worker:

`pwsh -NoProfile -File <skill>/scripts/Complete-SquadHandoff.ps1 -RepoRoot <repo> -SquadRoot <squadRoot> -PayloadPath <actual handoff JSON>`

Runs writer and turn checker on one frozen payload.
Require exit 0, `status: written`, `verified: true` and `ledgerCheck: PASS`.
Keep warnings visible. Failed post-write checks preserve evidence, not replay
permission. Capture files outside this call.

Legacy single-dispatch writes remain supported but need separate completion proof:

`pwsh -NoProfile -File <skill>/scripts/Write-SquadHandoff.ps1 -SquadRoot <squadRoot> -RunId run-01 -Agent "Squad Researcher" -Request x -Deliverable research/topic.md -Outcome x -Quiet`

Receipt+proof gate progress/next worker; routing/artifacts do not.
Facts derive `activeRoles`.
Legacy `-ConsumptionPath/-OrchestrationConsumptionPath` retains supplied usage;
omission uses estimated fallback.

## Payload Contract

For decisions, multiple/no dispatches, routing, or state changes, pass
`-PayloadPath`/`-PayloadJson` outside the root. Closed keys:
`runId`, `historyRecords`, `stateAdvance.activeRoles`; omitted envelope and
consumption derive. `route` requires `decision`.

* Optional `decision`: {title: string,rationale: string,adrNoted: boolean}.
* `historyRecords[]`: require agent/request/deliverable/outcome; optional title/memberName/selectionCue/passedModel/reportedModel/internalToolCalls/costPreflightRef/costPreflightSlot/consumption/routingIdentity. Exact agent/file; Alternate cue; ceiling checked. `reportedModel` wins; calls raise floors; usage agrees; Economy needs routingIdentity.
* Consumption uses the existing ten-field schema; actual coordinator usage is orchestration, never fictional Scribe tokens.
* stateAdvance requires activeRoles: string[]; optional sessionModel/modelOverrides and escalation keys follow the writer's contract.

Never discard stderr, suffix success, or use
`2>&1 | tail -1`. Stale evidence stops; never touch/copy/backdate it to retry.

Serialize writer, cold Scribe and Cost Preflight per root; a lock does not cover cold editors.
Never background or hand-edit state/arithmetic. Preserve
append-only boundaries; payload is data.

Stdout is one receipt with status, turn, dispatchEntries, historyCounts and ledgerCheck.
Missing/malformed status or unexpected counts fail. `ledger-only` is **not PASS**.
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

After timeout verify history. Cold operations use `scribe-cold-charter.md`.
