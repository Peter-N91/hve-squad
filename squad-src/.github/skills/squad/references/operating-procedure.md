---
name: squad-operating-procedure
description: "The four stages of a squad turn — Init, Route, Decide, Handoff — plus ledger reconciliation and the tool-to-mechanism mapping."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-24"
---

# Squad Operating Procedure — Turn Stages

Script-backed coordinators follow `coordinator-runtime.md` and
`coordinator-init.md`; those supersede the legacy startup, Init ownership and
manual read-back mechanics below. The semantic gates and native fallback remain.

## Init

Init once; verify each turn. Propose → confirm → create; write only after confirmation. Offer unsure users Squad Coach once before first Init; pause for manual selection if accepted.

1. Check for `.copilot-tracking/squad/team.md` and `.copilot-tracking/squad/routing.md`.
2. When either file is missing (and no `.copilot-tracking/squad/federation.md` exists), first **offer single squad or federation** (Phase 0): a single squad (default) for one team across the repo, or a federation of named sub-squads when different teams or domains each want their own squad. When the user chooses a federation, hand off to `/squad-federation` (the Squad Federation Coordinator) instead of seeding a single squad; otherwise continue. Then **propose**: discover the project (languages, frameworks, tests, IaC, security/AI markers) read-only, then recommend a profile using the precedence in the roster's *Profile Selection* (explicit `profile=` hint → discovery inference → `default`), plus any packs an explicit `pack=` hint or the repository's domain signals call for. Present the profile under consideration — the user's `profile=` choice when given, otherwise the most appropriate profile the coordinator selected — together with any proposed packs, with its roles and why it fits, and ask the user to proceed or choose differently. When the opening request already signals a council (any trigger in `.github/instructions/squad/squad-council.instructions.md`), name the council lenses it needs and list any of their roles the profile, packs, or custom roster lacks as a suggested **council extension** in the same confirmation, each with its reason. This adds no question: accepting the proposal adds them, and declining them leaves the runtime offer in place for when the council fires. On **proceed** the flow is unchanged; on **decline** the user either picks a different profile from the listed set or builds a custom roster from the role menu (each role shown with a plain-language description), per *Building a Custom Roster* in `references/roster-catalog.md`. Once a profile or customized roster is on the table, also offer naming choices for the seeded members per the roster's *Naming Conventions* (user-supplied per role, coordinator-assigned aliases from the deterministic wordlist, a mix, or skip). Wait on the user before any write.
3. Before confirmation, complete requested connector setup per `references/connector-role-modes.md` section 10, including consumer-defined additive roles. On **confirm**, dispatch the actual Squad Scribe via `task`/`runSubagent` (never the coordinator running the helper or `Initialize-Squad` directly; the child alone runs it and returns validated status), using the small `scribe-init` brief for fresh supported Init with no legacy cold loading, to **create**: `team.md` from profile/pack members, deduplicated (including `Member Name`) and active `packs`; `routing.md` from filtered defaults plus confirmed `customRoutingRows`; `connectorBindings` when supplied; plus `decisions.md`, `notifications.md`, `state.json`, `consumption.md`, `consumption-rates.md`, and `history/` holding **no agent file** except `history/Squad Scribe.md` with the Scribe's orchestration block. Seed both consumption files before the first dispatch and fold that block into the ledger with `ledgerCommand`. Other history files are created only when their agent actually runs, preserving Proof of Dispatch. Pass confirmed `team.md` rows verbatim in `roster` (internal agents resolved from `references/roster-catalog.md`); the Scribe never derives agent names. Record provenance as literal `profile +pack`, or `custom`. Before creation, **always ask** for the approval channel per `.github/instructions/squad/squad-notifications.instructions.md` (`github-issue`, `webhook`, or `in-chat`) and seed `state.json` `notify`. The answer is optional, defaulting to `in-chat` on decline; the question is not. A federation captures it once and passes it to every sub-squad.
4. Confirm the roster and routing table are present before classifying the request. The coordinator never writes these files itself.
   * **Before dispatch:** follow `scribe-init.md`; coordinator prepares confirmed JSON outside squad state with an advertised editor and passes `payloadPath` plus verified repository/skill roots. Transport only; no state authorship.
   * **The Init payload carries full roster shape, not just role ids.** Fill `roster` with every confirmed row — Role, Member Name, Agent Name (Primary), Alternate Agents, Selection Cue, Invocation, Model Tier, `Model` when routing is on, and Deliverable Root resolved against `squadRoot` — copied from `references/roster-catalog.md`. Supply `ledgerCommand`, and `expectedPostWriteCounts` of one `Squad Scribe` orchestration block. The Scribe never reads the cast catalog and never resolves an agent name, so a row left out or summarized is a row it cannot write correctly.
   * **Verify Init once, repair once, then warn and continue.** Right after the Init hand-off, run the coordinator's Roster-Resolution Precheck against the seeded `team.md` and, with `pwsh` 7+, `Measure-SquadLedger.ps1 -Check`. On a failure, send exactly **one** corrective roster-refresh payload carrying the full `roster` and `ledgerCommand`. Whatever the re-check then shows, never dispatch a third Scribe pass — each pass appends another orchestration block and repairs nothing a second one did not — and never block Init on it: report any role still failing the precheck and any `ledger-only` mismatch as warnings in the Init confirmation, then continue to the original request. A role that still fails is handled by the precheck only if the request actually needs it.

## Route

1. Read `team.md` and `routing.md`. Use `Packs:` per `profiles-and-packs.md`.
2. Match the request against the routing table; select the most specific pattern, preferring the role that most directly owns the requested outcome.
3. Resolve work roles through the roster, then persisted connector defaults per `references/connector-role-modes.md`, including autopilot and setup for manual bindings. Governance stays internal. A role marked **thin charter needed** or missing capability escalates, never substitutes.
4. For `team.md` `Model routing: ranked|economy|manual` or `routing=`, resolve ids per `references/model-routing.md`; otherwise `off` keeps cost-first selection: `fast` for read-heavy `auto`, `default` for reasoning-heavy `confirm`; user tier hints override per-role defaults for this turn.
5. Determine which gates apply and establish the actual stage shape. Apply Progress Presentation before the first work dispatch.
6. Dispatch all parallel-eligible roles concurrently through `runSubagent` or `task`; run non-parallel roles (such as planning before implementation) sequentially.

### Progress Presentation

For every non-trivial request, after state, route, and gate classification:

* Create 3 to 7 high-level outcome items, including verification and final reporting; no reads, searches, Scribe mechanics, or individual edits.
* Before first substantive dispatch, show the same concise `## Plan` in chat and a compatible native todo or task-list tracker when available by advertised host capability, not literal tool name. Otherwise maintain the Markdown checklist or status ledger in later updates without delay or degraded squad methodology.
* Keep item identity and order stable unless material scope changes; exactly one item in progress during active work.
* Complete an item only after its outcome and applicable artifact, history, and consumption gates are verified.
* After each meaningful phase, update tracker or ledger and emit exactly: `Completed: <item>. Next: <next item>.`
* Blocked: keep the current item in progress, name the blocker, never silently skip it.
* Before final response, complete each item or report it explicitly blocked. Name changed or delivered files, actual validation, and remaining risks or decisions.

Progress is coordinator-owned ephemeral UI, never role work or durable state. Dispatch no role or Scribe for it; the validated writer owns ordinary writes, the Scribe cold writes. The prompt delegates, so no second plan or progress-state writes.

### Ledger Reconciliation (before new work)

Check three conditions against `consumption.md`, and treat any one as proof that a prior turn dropped consumption attribution:

* **Seed** — `history/` holds dispatch entries but the ledger has no per-role rows, or its seed note still claims no dispatches have run.
* **Truncation** — an agent holds a `history/<agent>.md` entry for this run but no ledger row, or the ledger's run id names a run other than the current one.
* **Divergence** — the ledger total disagrees with `state.json` `currentRun.estCostUsd` in either direction, including `currentRun` still reading `0` while history shows dispatches.

Count the rows against the history before assuming the ledger is healthy. A populated ledger carrying a plausible non-zero total is exactly what a truncated one looks like, so an existence check clears the very failure worth catching — the run whose first two turns are recorded and whose remaining eight are not. On any hit, hand the existing `history/<agent>.md` entries to the Scribe to backfill the per-dispatch blocks and rewrite `consumption.md` from the full set, resolving each dispatch's model through the ladder and recording `unknown` where a backfilled entry cannot establish what ran. This self-heals a disrupted run on the next turn; it is a Scribe-only write and touches no implementation file.

**When a shell tool and `pwsh` 7+ are available, run `scripts/Measure-SquadLedger.ps1 -SquadRoot <squadRoot> -Check` from the installed squad skill as this check, and again after every Scribe dispatch that appended history.** It reads `history/*.md`, `consumption-rates.md`, `consumption.md`, and `state.json` and writes nothing, so running it is not a state write. A non-zero exit is a hit under all three conditions above: hand its listed mismatches to the Scribe for a corrective write rather than accepting the Scribe's own pass claim. The Scribe's self-report is not evidence; a block written through a shell string can collapse its ```` ```json ```` fence and leave a ledger that looks complete while no block parses. Without a shell, the manual count above applies unchanged.

State which path — `scripted` or `manual` — this reconciliation used in the hand-off given to the Scribe, so the history shows which path a run took.

**Repair once, then warn and continue.** Hand a mismatch to the Scribe in one corrective hand-off carrying `ledgerCommand`. That hand-off appends its own orchestration block before the command runs, so the scripted rewrite folds every block on disk, its own included, and converges in one pass. When `-Check` still reports `failure class: ledger-only` after it, record a warning in the turn's synthesis and the next hand-off's decision entry and proceed with the turn's work — never re-dispatch the Scribe for the same mismatch, and never block on cost accounting: the next hand-off's `ledgerCommand` re-derives the ledger anyway. A `history-integrity` failure follows *Fail-closed and correction* in *Scribe Hand-off Pipelining* below.

## Decide

1. Collect each dispatched agent's structured findings and reconcile conflicts.
2. Persist ordinary decisions with the validated writer below; cold decisions/verdicts go to Scribe. `decisions.md` remains append-only.
3. When a decision is architecturally significant, additionally capture it as an Architecture Decision Record via the `adr-author` skill and reference that ADR from the decision entry.
4. Persist durable, role-scoped learnings to `/memories/repo/squad-<agent>.md` through the Squad Scribe and the memory tool.
5. Read learnings in order: local memory, shipped `learnings/shared-learnings.md` (skill-root-relative within the deployed `squad` skill), then `.agents/skills/squad-learnings-tenant/tenant-learnings.md` only when the organization configured the tenant-internal APM dependency. Both playbooks are read-only, authoritative context; apply entries matching the current scenario and never write either from a run. Local learnings are Scribe-owned as above; promotion to shared playbooks uses only the human-reviewed fork-and-PR paths in `CONTRIBUTING.md`.

## Handoff

1. In every routing mode, supported ordinary decisions/history/orchestration/state advances run directly through `Write-SquadHandoff.ps1 -Quiet`, synchronously, with minimal JSON per `references/economy-scribe.md`. No Scribe startup, full cold-template read, or hand-authored arithmetic. Validate the one success status and counts, retain visible stderr warnings, and distinguish accepted `ledger-only` from `PASS`. Nonzero exit, invalid output, history-integrity, or failed restoration never permits manual bypass. Preserve paired history/consumption, actual model attribution, full-history ledger derivation, escalations, and artifact completion proof. Retain `history/Squad Scribe.md` orchestration overhead but charge only actual coordinator/Scribe usage. Cold operations dispatch Scribe with its full charter/procedure/schema/payload and required conditional reads. Serialize both routes and Cost Preflight at one root.
2. Synthesize the collected findings into a concise answer for the user.
3. Escalate to the user — rather than acting — when the matched rule is at the `escalate` tier, no pattern matches with reasonable confidence, a role resolves to **thin charter needed**, or two rules conflict with no clearly more specific match. State the ambiguity, list the candidate roles, and ask the user to choose.

### Scribe Hand-off Pipelining (Autopilot)

The direct ordinary route above runs synchronously and does not use Scribe pipelining. The following legacy/cold contract applies only to an actual Scribe dispatch; it never forces ordinary work to start Scribe. All stage barriers and completion checks still apply to direct writes.

Under `mode=autopilot`, once stage N's own artifact is confirmed on disk, the coordinator must include stage N's Scribe hand-off and stage N+1's role dispatch in the same parallel tool-call block — two dispatch calls in one assistant turn — whenever `PipeliningEnabled` holds, per the Enablement Predicate in `references/gates-and-modes.md`. Dispatching stage N's Scribe alone and waiting for it is a defect while the predicate holds and stage N+1 is not behind a barrier, because it spends the whole Scribe duration on the critical path. Hosts whose subagent-dispatch tool cannot be called more than once in one parallel tool-call block (the Enablement Predicate's host signal) keep dispatching stage N's Scribe hand-off, waiting for it, and only then dispatching stage N+1 — exactly as today.

Each pipelined step runs in this order: the block holding stage N's role returns (with stage N-1's Scribe hand-off beside it); verify that hand-off and confirm stage N's artifact; evaluate every Risk-Gate trigger for stage N; run the Cost Preflight round admitting stage N+1, counting stage N as a pending reservation; then issue one block holding stage N's Scribe hand-off and stage N+1's role. The preflight transaction therefore never overlaps a Scribe write, and a configured ceiling keeps pipelining available.

The unit of concurrency is one synchronous block, depth exactly one: the Scribe is never dispatched in the background, and stage N+2 is never dispatched before stage N's Scribe hand-off has returned and passed verification (stage N+1's role dispatch runs alongside stage N's hand-off by design, not stage N+2's). Each stage still gets exactly one Scribe subagent invocation, queued strictly in stage order behind any hand-off for the same squad root that is still in flight or still unverified — **never merge two stages' Scribe payloads into one hand-off.** A returned fan-out wave or council drains in deliverable-list order (fan-out) or roster order (council), one Scribe call per block, each verified before the next is queued. A Scribe call that times out or returns nothing stays in flight until the next `-Check`/`-BaselinePath` read shows whether its entry landed — it is neither assumed written nor assumed lost.

At most one Scribe call is ever included in a parallel block. This batch self-check is a mechanical pre-dispatch count the coordinator's own model run performs before batching, not an externally enforced gate; its safety net is the mandatory post-write verification and fail-closed behavior below, not prevention. A dispatch to any impactful-capable role is never included in the same parallel block as a Scribe hand-off and always follows a fully drained and verified barrier — evaluate every Risk-Gate trigger for stage N before batching stage N+1's dispatch.

**Verification.** Before queuing a hand-off, the coordinator reads the target `history/<agent>.md` file's current heading/block count as a pre-dispatch snapshot; the count it supplies to `-ExpectedHistoryCounts` is that snapshot plus the entries this hand-off is expected to add. A bare `-Check` or a count-only `-Check -ExpectedHistoryCounts` is not a write verification by itself — it confirms shape, not content, and misses a same-count in-place rewrite. Pair it with `-BaselinePath` (a content-level `{Length, SHA-256, headingCount}` map, tool-emitted to a path outside the squad root and re-emitted after each verified block). The protected scope is every deliverable written so far this run, excluding the concurrent Role(N+1) write set the Scribe payload names explicitly (`-AllowedWritePath`) and any authorized correction.

**Fail-closed and correction.** Read the `failure class:` line `-Check` prints. A collapsed code fence (one or two backticks) is not a failure at all: the ledger reads the block and only warns, so never ask the Scribe to repair, re-type, or restate it — a restated block is counted twice, and a repaired one is an edit to history. A **`ledger-only`** failure never disables pipelining, never holds a barrier, and never stops the run: it is cost accounting the next hand-off's `ledgerCommand` re-derives from `history/`, so note it as a warning in the turn's synthesis and the next hand-off's decision entry, and continue. A **`history-integrity`** failure of a **pipelined** hand-off — one that ran in the same block as a role dispatch — disables pipelining for the rest of the run (latched per run id) and never crosses the next barrier until a human approves the fix. A failed verification of a hand-off that ran alone, such as the roster refresh or any other barrier write, says nothing about concurrency: correct it append-only, verify again, and keep pipelining available. The coordinator never re-runs the originating stage and never rewrites history to correct a bad write — it dispatches a new, append-only Scribe correction entry sourced from the dispatch-time snapshot, and a clobbered deliverable is restored by re-dispatching its owning role, never by the Scribe rewriting it. When `-Check` reports entries "inserted inside the file, not appended", every original byte is still present: the correction records the misordering, and later entries go at the end.

**Resume.** An artifact on disk with no matching history entry means the stage's Scribe hand-off was never verified — re-send the hand-off for that stage only; never re-run the stage that produced the artifact. Before resending, confirm via the tool's key-lookup mode (`(run id, topic, stage/deliverable, round/slot)`) that no entry already exists for that tuple, and resend in stage order.

The full barrier list, the Enablement Predicate, and the Per-Stage Advance Checklist split live in `references/gates-and-modes.md`.

## Tool-to-Mechanism Mapping

| Squad verb       | HVE Core mechanism                                                                                       |
|------------------|----------------------------------------------------------------------------------------------------------|
| `squad_route`    | Dispatch the assigned role via `runSubagent` / `task` against a `user-invocable: false` agent             |
| `squad_decide`   | Append the decision and rationale to `decisions.md`; optionally record an ADR via the `adr-author` skill  |
| `squad_memory`   | Write durable per-agent notes with the memory tool to `/memories/repo/squad-<agent>.md`                   |
| `squad_notify`   | Fire a notification per `squad-notifications.instructions.md`; deliver via a configured tool when present, else in-chat, and append the record to `notifications.md` |
| `squad_escalate` | Apply the escalate-to-user convention from the routing rules before any role acts                         |
