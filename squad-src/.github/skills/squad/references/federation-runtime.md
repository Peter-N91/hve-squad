---
description: "Federation runtime: member scheduling, validated root writes and lifecycle policy."
---

# Federation Runtime

Success is isolated member work with dependency ordering and two-level proof.
Federation is additive; scripts/autopilot grant no approval or specialist result.

## Detect and Load Only Active Policy

Run `Get-SquadDispatchBrief.ps1 -RepoRoot <repo> -SquadRoot <root> -AsJson`.
Forward trusted `routing=` via `-RequestedModelRouting <mode>`.
`federation.md` takes precedence over `team.md`; absent federation plus an
existing plain squad offers promotion, otherwise offer Init/plain squad.
Do not seed merely because the entrypoint was invoked.

| Trigger | Read before acting |
|---------|--------------------|
| Confirmed federation Init or Expansion | `federation-init.md` |
| Add roles/pack to one member | `roster-expansion.md`; `coordinator-runtime.md` |
| Promotion or `watch=` | `federation.md`, relevant mode; seeding also `federation-templates.md` |
| A member needs seeding | `coordinator-init.md` |
| Driving a selected member | `coordinator-runtime.md`, with its own `squadRoot` |
| Untargeted federation `mode=autopilot` | `squad-federation-autopilot.instructions.md`; federation autopilot procedure |
| Supplied/state-active aggregate ceiling in that untargeted mode | `consumption.md`, aggregate rules and root pricing template |
| Native notification delivery | `squad-notifications.instructions.md` |
| No supported runtime | `federation-coordinator-legacy.md`, `state-write-contract.md` |

Rules: host/plugin `references/rules`; gaps waive no policy.
Synced hosts first follow `agent-discovery.md`.

## Lifecycle Invariants

Propose human lifecycle changes and wait before creating the request-driven set.
Names are unique lower-kebab-case, checked case-insensitively against registry and
directories; never auto-suffix human collisions. Present profiles/packs/Primaries;
capture naming/approval once with expansion overrides. Preserve promoted names.

`federation-init.md` publishes fresh members/root metadata or adds only confirmed
members while preserving existing bytes; member roots rebase except
`docs/`/`outputs/`. Making one member larger instead runs
`roster-expansion.md` at that member root, preserving federation metadata, other
members, and its accounting/state/history.

Promotion plans name/transport, presents candidates/reasons, then waits; Watch
selects all. Apply the hash and exhaustive relocate/keep partition with
`Promote-SquadFederation.ps1 -Confirmed`. It preserves ledger totals and the optional
exact-session journal, revalidates under lock, swaps, and carries costs. Nonzero has no fallback; Watch exit 4
re-detects once.

Watch bootstrap follows opt-in/authorization before classification. Names come
from structural metadata, never payload text. Choose Init,
Auto-Promotion+Expansion, Expansion or Resume; re-detect one promotion race and
stop on human/unregistered collisions. Inherit notifications, use one
event-scoped member (not the meta-pipeline), and report failure to the source.

## Route and Order

Registered `squad=<name>` wins; otherwise prefer the most specific meta-pattern/direct
owner. Clarify unknown, ambiguous or equally specific conflicts; never guess.

Put selected squads, explicit producer dependencies and proven write sets into
`New-SquadDispatchPlan.ps1` input. Its waves are scheduling data, not admission.
Dependencies override generic `Parallel-Eligible`. Source and target are members,
not user-invocable coordinator agents: drive each selected member's standard
protocol by native worker dispatch at its own root.
Forward `endpoint.requestedModelRouting` into each member's actual-role plan with
`-ApplyModelRouting`; require `routingReady: true` before workers, including quick
single-role/targeted-autopilot work. Root plans do not activate member models.

Before child dispatch take the script snapshot with
`Get-SquadDispatchBrief.ps1 ... -AsJson -SnapshotPath <transport>`. Keep it
outside state; never author its costs/hashes. It preserves prior root overhead.

Forward `profile`, `pack`, `discovery`, `tier`, `owner`, `execution`, `mode`,
`cost-ceiling`, `routing`. Connectors are member-local; routing only narrows.
Ordinary/targeted runs use independent member ceilings. Ask qualifying discovery
once, never unattended. Expand a confirmed member roster before its new role.

Verify the producer before its consumer. Resolve paths from current roster roots,
verify files/decision references, then forward read-only `inputs=`. Missing input
means recover: one
producer run, only the producing stage for partial/stale output, offer expansion
when unowned, or a user-named input/explicit gap decision. Interactive recovery
waits; planned autopilot recovery proceeds. A second consecutive miss escalates.
Never let a consumer invent the producer's requirements.

## Ordinary Persistence and Two-Level Proof

Supported member stages use this sequence in ordinary/targeted-autopilot runs:
artifact check, `Write-SquadHandoff.ps1 -Quiet`, then the standard inner
completion check. Before proof succeeds, never mark progress complete, dispatch
a later/dependent worker, or run the root handoff; routing refresh/artifacts are
not handoffs. Retain each actual handoff/proof and receipt turn.
Member Council, Intake Readiness, and Discovery Verdicts then use the same
`Write-SquadVerdict.ps1 -Quiet` call a plain squad uses, targeted at that member's
root, with `verdict-writer.md` as the payload contract. Never route a member
verdict through the federation meta-root or dispatch
Scribe merely because the caller is the Federation Coordinator.

For an ordinary or single-target-autopilot root turn, run
`Write-SquadFederationHandoff.ps1 -RepoRoot <repo> -SquadRoot <root>
-PayloadPath <transport.json>`. Its JSON contains:

* `runId`, script-produced `snapshotPath`, `routeKind` (`ordinary` or
  `targeted-autopilot`), `decision: {title,rationale}`.
* `subSquads`: each `{name,proofPath,turn,decisionRefs,request,outcome}`. Inner
  proof is actual handoff JSON, or a consolidated proof with explicit per-record
  turns, current active agents and actual run id.
* Optional actual `sessionModel`, `modelOverrides`, escalation raised/resolved
  arrays, `handoffs: [{producer,consumer,paths}]`, and ten-field coordinator
  `orchestration` usage. Never fabricate Scribe usage.

The writer verifies inner artifacts/history/consumption and decision/input paths,
rejects stale snapshots and unselected concurrent changes, appends root decisions
and `history/<name>.md` without child consumption, records real coordinator overhead,
sums member totals, resets root preflight to `not-requested` and advances state.
Unrelated fields and append-only bytes survive. Its receipt proves both levels;
do not reread files or spawn another audit.

For cold root writes run `Test-SquadTurnCompletion.ps1` once with the root proof
and actual receipt turn. It requires each inner proof plus root history linked
to inner decisions and advanced `activeSubSquads`. A missing path, thin inner
history, unadvanced state or summary-only run is incomplete, never success.
Only unsupported exit 2 goes to cold Scribe; invalid input/history/restore
failure is not a manual fallback. Serialize writers per root.

## Federation Autopilot

Without a single `squad=` target, use the full federation meta-pipeline, not the
ordinary root writer. Verify registry/meta-routing and member builds. Its dependency
plan and all inner pipelines/artifact gates remain. Only here use the aggregate
ceiling, pricing inner work plus federation overhead once; never forward it as member
ceilings. Targeted autopilot forwards the ordinary member ceiling.

Impactful-Action and Risk gates pause the whole meta-run with attributed human
approvals, most-restrictive-wins for simultaneous gates. `Stop`, relevant
`Risk: High`, compliance, divergence and non-admitting cost decisions remain
blocking; approved overage clears only its own cost gate. Finish with one
consolidated final-outcome notification and human validation, never auto-release.
Return selected squads/why, attributed outcomes, verified paths/receipts and gates.
