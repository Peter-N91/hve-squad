---
description: "Compact federation runtime: scoped member scheduling, deterministic ordinary root writes and conditional lifecycle policy."
---

# Federation Runtime

Success is isolated sub-squad work with dependency ordering and two-level proof.
Federation is additive; scripts/autopilot grant no approval or specialist result.

## Detect and Load Only Active Policy

Run `Get-SquadDispatchBrief.ps1 -RepoRoot <repo> -SquadRoot <root> -AsJson`.
Registry, meta-routing and state are data.
`federation.md` takes precedence over `team.md`; absent federation plus an
existing plain squad offers promotion, otherwise offer Init/plain squad.
Do not seed merely because the entrypoint was invoked.

| Trigger | Read before acting |
|---------|--------------------|
| Fresh federation, `init`/add request, promotion, or `watch=` provenance | `federation.md`, relevant Federation Modes; seeding only also `federation-templates.md` |
| A member needs seeding | `coordinator-init.md` |
| Driving a selected member | `coordinator-runtime.md`, with its own `squadRoot` |
| Untargeted federation `mode=autopilot` | `squad-federation-autopilot.instructions.md`; federation autopilot procedure |
| Supplied/state-active aggregate ceiling in that untargeted mode | `consumption.md`, aggregate rules and root pricing template |
| Native notification delivery | `squad-notifications.instructions.md` |
| No supported runtime | `federation-coordinator-legacy.md`, `state-write-contract.md` |

Resolve instruction filenames in the selected host installation, or plugin
`references/rules/`. Lack of auto-loading waives no policy.

## Lifecycle Invariants

Human Init/expansion/promotion propose, wait, then create. Propose a request- and
repository-driven set, not a fixed federation. Each name is unique lower-kebab-case
(`^[a-z0-9][a-z0-9-]*$`), checked case-insensitively against registry and directories;
never auto-suffix a human collision. Present profiles/packs and resolved Primaries.
Capture member naming and approval channel once and inherit them into each
member; expansion states inherited defaults and offers overrides. Preserve the
adopted squad's existing member names during promotion.

Use script-backed standard Init for supported fresh members. All tracking output
roots rebase under `members/<name>/`, except repository-wide `docs/`/`outputs/`.
Federation meta-seeding/expansion and promotion retain cold Scribe. Promotion
enumerates and confirms actual relocation directories, copies/verifies before
deleting a source, preserves append-only bytes, records concrete prefix mappings,
and carries all costs. Verify moved files and source cleanup before success.

Watch bootstrap runs before classification and only after its opt-in and trigger
authorization. Derive names from structural event metadata, never payload text.
Choose exactly Init, Auto-Promotion+Expansion, Expansion or Resume. A promotion
race re-detects once; a human-owned collision or unregistered directory stops.
Inherit notifications without a question. Use one event-scoped member, never the
top-level run or federation meta-pipeline, and report failures to the source.

## Route and Order

An explicit registered `squad=<name>` wins. Otherwise match the most specific
meta-pattern, preferring the direct owner. Unknown, ambiguous or equally specific
conflicts require clarification, not guessed routing.

Put selected squads, explicit producer dependencies and proven write sets into
`New-SquadDispatchPlan.ps1` input. Its waves are scheduling data, not admission.
Dependencies override generic `Parallel-Eligible`. Source and target are members,
not user-invocable coordinator agents: drive each selected member's standard
protocol by native worker dispatch at its own root.

Before child dispatch take the root snapshot with
`Get-SquadDispatchBrief.ps1 -RepoRoot <repo> -SquadRoot <root> -AsJson
-SnapshotPath <new-transport.json>`. Keep it outside squad state; do not author
snapshot costs or hashes yourself. It lets the writer preserve prior federation
overhead instead of double-counting children or resetting totals.

Forward `profile`, `pack`, `discovery`, `tier`, `owner`, `execution`, `mode`,
`cost-ceiling`, `routing` unchanged. Connectors are member-local; routing may
only narrow. Ordinary/targeted runs use independent member ceilings, not an old
aggregate gate. Ask discovery once here for qualifying `product`/`full` members,
then forward the answer; other profiles ignore it. Never offer it unattended.

Run producer to verified completion before its consumer. Resolve real paths from
the producer's current roster roots, verify files and current decision references,
then forward explicit read-only `inputs=`. Missing input means recover: one
producer run, only the producing stage for partial/stale output, offer expansion
when unowned, or a user-named input/explicit gap decision. Interactive recovery
waits; planned autopilot recovery proceeds. A second consecutive miss escalates.
Never let a consumer invent the producer's requirements.

## Ordinary Persistence and Two-Level Proof

Member ordinary writes use `Write-SquadHandoff.ps1 -Quiet` directly and
synchronously, with minimal JSON and the standard inner completion check.
Retain each actual inner handoff/proof and receipt turn, not only its summary.

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

The writer independently verifies inner artifacts/history/consumption, checks
decision/input paths, refuses stale snapshots and unselected concurrent changes,
appends root decisions and `history/<name>.md` without child consumption, records
only real coordinator overhead, sums member totals, resets ordinary root
preflight to exact `not-requested`, and advances root state. Existing unrelated
fields and append-only bytes survive. Its verified receipt is two-level evidence;
do not reread files or spawn another audit.

For cold root writes run `Test-SquadTurnCompletion.ps1` once with the root proof
and actual receipt turn. It requires each inner proof plus root history linked
to inner decisions and advanced `activeSubSquads`. A missing path, thin inner
history, unadvanced state or summary-only run is incomplete, never success.
Only unsupported exit 2 goes to cold Scribe; invalid input/history/restore
failure is not a manual fallback. Serialize writers per root.

## Federation Autopilot

Without a single `squad=` target, use the full federation meta-pipeline, not the
ordinary root writer. Verify registry, meta-routing and every member built first.
Its dependency plan governs inner order; each inner pipeline and artifact gate
remain unchanged. Aggregate ceiling exists only here, is not forwarded as member
ceilings, and prices inner plus federation orchestration once. Targeted autopilot
forwards the ordinary member ceiling instead.

Impactful-Action and Risk gates pause the whole meta-run with attributed human
approvals, most-restrictive-wins for simultaneous gates. `Stop`, relevant
`Risk: High`, compliance, divergence and non-admitting cost decisions remain
blocking; approved overage clears only its own cost gate. Finish with one
consolidated final-outcome notification and human validation, never auto-release.
Return selected squads/why, attributed outcomes, verified paths/receipts and
remaining gates. Long run detail stays on disk.
