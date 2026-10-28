---
description: "Compact squad safety floor: native delegation, scoped single-writer state, proof, attribution and human gates."
applyTo: '**'
---

# Squad Agent Floor

These rules bind turns that run, resume or write a squad. Ordinary project work
is unaffected. Detailed schemas and no-runtime/manual accounting live in the
`squad` skill's `references/state-write-contract.md`, not every agent's context.

## Scope and Ownership

The squad root is `.copilot-tracking/squad/`, or
`.copilot-tracking/squad/members/<name>/` for a federation member.
Detection is `federation.md` first, then `team.md`, otherwise Init.
Keep existing paths and schemas: `team.md`, `routing.md`, `decisions.md`,
`notifications.md`, `history/<agent>.md`, `state.json`, `consumption.md`,
`consumption-rates.md`. Squad runtime state is never packaged.

Validated scripts own supported deterministic writes; cold Squad Scribe owns
unsupported state operations and memory. Confirmed direct Init is outside Cost
Preflight. A script invocation is not a Scribe dispatch. No coordinator or role
hand-authors ordinary state.
Never overlap direct writer, cold Scribe, or Cost Preflight at one root.
Never two Scribe subagents in flight for one root at once; queue hand-offs strictly in stage order.
Member roots may run concurrently.

Decisions, notifications and history are append-only: never edit, reorder,
truncate or remove a persisted entry, even one appended earlier this turn.
Preserve existing bytes and the ledger's heading-identity guard. Replace roster,
routing, state and pricing only through their defined transaction, preserving
unrelated fields and operator choices. Promotion alone relocates state, after
confirmation, through a sealed-plan copy -> verify -> locked publish transaction.

## Native Delegation and Gates

Coordinators classify, dispatch, collect, synthesize and escalate; they never do
a role's research, plan, implementation, review or verdict inline. Activate only
`squad` before dispatch, not a specialist skill to refine a route. Use native
`task`/`runSubagent` with the roster's installed, dispatchable agent. Missing
agents stop the turn; never substitute or work inline. A fast model does not
relax the contract.

Primary is the default. An Alternate needs a Selection Cue actually read from
that row and matched to the request. Preserve role/member/connector identities.
The row's current `Deliverable Root` is binding and passed as an output argument;
operator edits win. Substitute `<date>`/`<slug>` directories and record real
paths, never placeholders. Federation tracking roots rebase to the member;
`docs/` and `outputs/` remain repository-wide. Other-member inputs are explicit
and read-only.

Substantive delivery follows Research -> Plan -> Implement -> Review. Only the
existing economy Bounded Lane may omit its documented stages; other modes do
not inherit it. Intake, discovery, council, security, closing review and human
gates retain their triggers and exceptions. Before impactful actions (deploy,
push/force-push, merge, migrations, deletion, secret rotation, live tracker writes
or user-marked irreversible effects), stop for approval. Stop on Risk Gate or
non-admitting cost decisions. Final release remains human-validated.

## Proof and Accounting

Exception: read-only BRD/PRD reviewers return full payloads for coordinator capture at their roster root.
A verified, attributed capture plus history/consumption satisfies the artifact gate. Forward this exception in their briefs.
Capture is lossless transport, never review authorship: preserve the whole return,
separate reviewer/serializer attribution and never write protected squad state.

An artifact gates dependent dispatch. The actual dispatch entry, consumption and
advanced state additionally gate completion. No old entry, invented path, status
field or agent summary proves a current dispatch. Verify by the trusted script
that reads those files, or list/read manually when the runtime is unavailable.
After a script already verified the same evidence, do not launch another model
audit. Missing history calls for its missing handoff, not re-running the producer.

Use the agent's exact `name:` as `history/<agent>.md`, including case and spaces.
The header is `# History: <agent>`. Init creates no speculative worker histories;
only `history/Squad Scribe.md` holds actual orchestration. Federation root history
names sub-squads and carries no duplicate child consumption. Consultative
exceptions follow the roster/gate contract and retain durable findings.

Every real dispatch has one `#### Consumption` fenced `json` block, with exactly
these keys in order: `model`, `model_source`, `priced_as`, `model_tier`,
`internal_turns`, `input_tokens`, `cached_tokens`, `cache_write_tokens`,
`output_tokens`, `basis`. Orchestration alone uses
`#### Consumption — Orchestration`. Numbers are bare nonnegative integers;
rates and cost never belong in a block. Keep raw host model/size signals;
host-reported identity wins over a predicted pin, then applicable operator and
session evidence. `auto` is literal session metadata, not an actual model.
Unreported usage is `unknown`/`unresolved`, not an invented name or Scribe actor.

The ledger derives all rows/totals from all recorded blocks, once, using the
canonical rates and calibration. Seed rates with the shipped helper, never by
model transcription. Init Cost Comparison is `n/a (initialization)`; a missing
manual baseline is unavailable, not fabricated savings. `ledger-only` is a
visible accounting warning, not PASS; `history-integrity` fails closed. Never
repair append-only history to clear a refusal.

Cost Preflight remains the narrow coordinator-owned compare-and-swap transaction.
Preserve admission run/round/Decision Ref/slot identities, consume a permitted
slot once, and dispatch nothing after collision, partial write, `cannot-confirm`,
or an already-reached ceiling. A script receipt never grants approval.
Runtime: `New-SquadDispatchPlan.ps1 -ApplyModelRouting` gates workers with
`routingReady: true`; `routing=off`, roster, routing rows and state stay cold.
