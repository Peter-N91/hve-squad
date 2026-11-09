---
name: squad-verdict-writer
description: "Deterministic Council, Intake Readiness, and Discovery Verdict payloads."
license: MIT
---

# Deterministic Verdict Writer

After `Write-SquadHandoff.ps1 -Quiet` persists the turn's dispatch history,
consumption, and state, run synchronously at the same root:

`pwsh -NoProfile -File <skill>/scripts/Write-SquadVerdict.ps1 -SquadRoot <squadRoot> -PayloadPath <verdict.json> -Quiet`

The script shares the handoff lock, appends only `decisions.md`, rejects replay
or chronology drift, and returns the stable Decision Ref. A federation member
passes its `members/<name>/` root unchanged; the federation meta-root is refused.

## Closed Payloads

All payloads require `kind`, `topicId` (lower-kebab-case), and `topic`;
`timestamp` is optional ISO-8601.

* `council`: `proposalRef`, `membersDispatched[]`,
  `membersNotProposed[{role,reason}]`, and
  `findings[{role,verdict,risk,blockingIssues[],conditions[],suggestedFollowUps[]}]`.
  Finding verdicts are `Approve|Conditional|Concern|Block`; risks are
  `Low|Medium|High` with an optional `Risk:` prefix. The writer derives most-restrictive-wins synthesis, gate
  permission, and the unique condition count.
* `intake`: `inputsReviewed[]`, `validatorDispatched`, `verdict`,
  `remediationCycles`, all five canonical
  `findings[{dimension,result,blockingGaps[],nonBlockingGaps[]}]`,
  `clarifyingQuestions[]`, and `recordedAssumptions[]`. The writer validates the
  returned label against the gap counts and derives the gate.
* `discovery`: `optIn`, `depth`, `rolesDispatched[]`, `brief`, `handoff`,
  `framing{problem,successMeasure}`, `options[{option,outcome,reason}]`,
  `objections[]`, `riskiestAssumption`, and `openQuestions[]`. `skip` requires
  `Brief: none` and empty body data; `handoff: abandoned` permits incomplete
  non-skip sections; discarded reasons remain verbatim.

Quiet success is one JSON receipt with `status`, `kind`, `label`, `topicId`,
`path`, `decisionRef`, and `timestamp`. Exit `1` fixes invalid data once; `2`
takes the cold Scribe fallback; `3` is a failed/restore-attempted write; `8`
waits for the active writer. Never hand-edit or dispatch Scribe merely to
transcribe a supported verdict.