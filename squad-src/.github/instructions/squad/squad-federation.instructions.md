---
description: "Squad federation layout: opt-in sub-squads under one repo, the parameterized squad root, the federation registry and meta-routing schemas, detection precedence, two-level single-writer state, and the unattended Watch Mode bootstrap"
applyTo: '**/.copilot-tracking/squad/federation.md'
---

# Squad Federation Conventions

These conventions define **federation**: running several named sub-squads under one hub so a single repository can host more than one squad — for example, a business team's `product` sub-squad and an architecture team's `azure` sub-squad, side by side. Federation is **opt-in and additive**. A repository that never opts in keeps exactly today's single-squad behavior.

Federation reuses every existing squad mechanism unchanged. Each sub-squad is an ordinary squad — same roster, routing, decisions, history, consumption, and single-writer Scribe discipline — only rooted at a named path instead of the top-level `.copilot-tracking/squad/`. The only new pieces are a **parameterized state root** and a thin **meta layer** (a registry, a meta-routing table, and the Squad Federation Coordinator) that classifies a request to one or more sub-squads and runs each scoped to its own root.

Routing across sub-squads is decided here and in `meta-routing.md`; routing *within* a sub-squad is unchanged (`squad-routing.instructions.md`). Roster and persistence rules are unchanged (`squad-roster.instructions.md`, `squad-state.instructions.md`).

## When a Pack Is the Answer Instead

Federation and packs both add capability a single profile does not carry, and the two are easy to confuse. The separating rule lives in *Pack or Federation* in `squad-roster.instructions.md`; the short form is that **one piece of work needing extra expertise is a profile plus a pack, and two streams of work with separate deliverables and owners is a federation.**

Two consequences matter before anyone builds a federation to solve a capability gap:

* **A federation does not reach a technology vertical any faster than a plain squad does.** A sub-squad is seeded from a profile, so a vertical arrives on it by applying the pack, exactly as on any other roster. Building a sub-squad named after a vertical still requires the pack, and adds a duplicated methodology spine, a second state tree, and a second consumption ledger for no additional reach.
* **Splitting one piece of work across two sub-squads splits its record.** Each sub-squad keeps its own `decisions.md`, `history/`, and deliverable roots rebased under `members/<name>/`, so two halves of one decision are taken in two councils that never met. A pack keeps those roles in one turn, one council, one plan, and one review.

Federate when the sub-squads own genuinely separate outcomes — a business team's discovery work beside an architecture team's infrastructure build, or Watch Mode giving each triggering event its own sub-squad and its own pull request. Do not federate to obtain a role.

Registered packs are `power-platform`, `m365-copilot`, `aws`, and `foundry`; Foundry is normally `profile=azure pack=foundry`.

## Squad Root (`squadRoot`)

A squad's state lives under a **squad root**. The root is parameterized:

* The default squad root is `.copilot-tracking/squad/`. Every state path in `squad-state.instructions.md` (`team.md`, `routing.md`, `decisions.md`, `history/<agent>.md`, `state.json`, `consumption.md`, and the rest) is `<squadRoot>/...`, and the default keeps today's literal paths.
* In a federation, each sub-squad roots at `.copilot-tracking/squad/members/<name>/`, where `<name>` is the sub-squad's registered name (lower-kebab-case). That directory holds the sub-squad's full standard state tree.
* The Squad Coordinator and the Squad Scribe accept an optional `squadRoot`; when omitted, the default preserves single-squad behavior. The Squad Federation Coordinator sets `squadRoot=.copilot-tracking/squad/members/<name>/` when it drives a sub-squad.

Because every squad instruction file's `applyTo` is `**/.copilot-tracking/squad/**`, all conventions auto-apply at any depth, so a sub-squad tree under `members/<name>/` inherits the roster, routing, and state rules without any `applyTo` change.

## Federation State Layout

A federation adds a small meta layer at the federation root (`.copilot-tracking/squad/`) and nests each sub-squad under `members/<name>/`:

| Path                                   | Purpose                                                                     | Write Semantics    |
|----------------------------------------|-----------------------------------------------------------------------------|--------------------|
| `federation.md`                        | Registry of sub-squads (name, profile, kind, location, owner, description)   | Replace via validated Init or Scribe |
| `meta-routing.md`                      | Request pattern / domain → sub-squad routing table                          | Replace via validated Init or Scribe |
| `decisions.md`                         | Federation-level cross-squad routing decisions and rationale                | Append-only; Cost Preflight via coordinator |
| `history/<sub-squad>.md`               | Per-sub-squad federation dispatch history (which sub-squad ran, for what)   | Append-only        |
| `history/autopilot-run-<id>.md`        | Federation autopilot meta-run summary linking each sub-squad's inner run     | Append-only        |
| `state.json`                           | Federation status: active sub-squads, mode, current-run cost, open escalations, federation-wide `notify` default | Replace via validated writer or Scribe; Cost Preflight compare-and-swap via coordinator |
| `consumption-rates.md`                 | Rate, estimator, and calibration source used only by untargeted federation autopilot | Replace via validated Init or Scribe |
| `members/<name>/`                      | A full ordinary squad state tree (the sub-squad's `squadRoot`)              | Per squad-state    |

Each `members/<name>/` directory is an unmodified squad: `team.md`, `routing.md`, `decisions.md`, `notifications.md`, `history/<agent>.md`, `state.json`, `consumption.md`, and `consumption-rates.md`, all governed by `squad-state.instructions.md` rooted at `members/<name>/`.

**A healthy federation root holds five files plus a `history/` directory.** `federation.md`, `meta-routing.md`, `decisions.md`, `state.json`, and `consumption-rates.md` are seeded when the federation is built or promoted; `history/<sub-squad>.md` is created for each registered sub-squad. The root rate file is dormant during ordinary routing and supplies one consistent estimator and calibration only for untargeted federation autopilot. `history/autopilot-run-<id>.md` appears only after that mode runs. There is deliberately no root `team.md`, `routing.md`, `notifications.md`, or `consumption.md`.

The federation `state.json` also carries the `notify` object captured **once** at build time. Every sub-squad inherits it into its own `state.json`, and a sub-squad's Init never re-asks the approval-channel question; a sub-squad may hold its own overriding `notify` object, which wins over the federation default at send time. Its `currentRun.estCostUsd` is the sum of realized inner-ledger totals plus estimated federation coordinator and root-writer orchestration exactly once. The aggregate Cost Preflight entry is the accounting evidence for that meta-orchestration because the federation root has no second consumption ledger. See *Capture in a Federation* in `.github/instructions/squad/squad-notifications.instructions.md`.

The federation root's `decisions.md` and `history/<sub-squad>.md` are **append-only**; `federation.md`, `meta-routing.md`, and the federation `state.json` use **replace** semantics — mirroring the per-squad rules one level up. The federation `history/autopilot-run-<id>.md` is **append-only by topic-id** and is written only for a federation-level autopilot meta-run; see `.github/instructions/squad/squad-federation-autopilot.instructions.md`. The federation `state.json` carries additive `mode` and `currentRun` fields for that meta-run (the autonomy mode in effect and the cost aggregated across every sub-squad inner run); both are backward-compatible, so a federation that never runs autopilot omits or zeroes them and existing state stays valid.

## Detection Precedence

The Squad Coordinator resolves what kind of squad a project has at the start of a turn, checking `.copilot-tracking/squad/` in this order:

1. **`federation.md` present** → **federation mode**. The Squad Federation Coordinator owns the turn: it reads the registry and meta-routing, selects the target sub-squad(s), and runs each scoped to `members/<name>/`. When the Squad Coordinator itself is invoked with an explicit `squadRoot`, it operates directly against that sub-squad root.
2. **No `federation.md`, but `team.md` present** → **plain single-squad mode**. Behavior is exactly today's: the Squad Coordinator runs the six-step protocol against `.copilot-tracking/squad/`.
3. **Neither present** → **Init Mode**. The user is offered a plain squad (the default) or a federation of named sub-squads.

`federation.md` at the top level versus `team.md` at the top level is the single discriminator between a federation and a plain squad. The two are mutually exclusive at the federation root: a federation keeps `team.md` only inside each `members/<name>/`, never at the top. When both are present — a state a manual edit can produce — precedence still makes the project a federation, and the stray top-level `team.md` is reported for a human to reconcile rather than silently promoted.

An **event-triggered Watch Mode run** resolves the same precedence but never stops at case 2 or 3: it bootstraps whatever is missing (Init, automatic Promotion, or automatic Expansion) so the run always executes inside a sub-squad dedicated to its triggering event. See `.github/instructions/squad/squad-watch-mode.instructions.md`.

### Federation Init Transaction

After the user confirms all names, profiles, packs, owners, descriptions, routes,
naming and notifications, `Get-SquadFederationInitPlan.ps1` validates every
member through the standard single-squad payload builder and writes no state.
`Initialize-SquadFederation.ps1` requires that exact payload hash and explicit
confirmation. With no federation it initializes the member trees in parallel,
seeds and prices the root meta layer, then publishes the complete federation.
With an existing federation it seals the current root/member snapshot, initializes
only the new member trees in parallel, builds a validated additive root projection,
then commits the new directories and root metadata under the same writer lock.
Existing member trees are never rewritten. A stale root, failed member, collision,
timeout, invalid receipt or restore failure writes no successful state and never
falls back to hand-authored or Scribe state. Hosts without the scripts retain the
compatibility procedure.

## Promotion: Single Squad → Federation

An existing single-squad project already has a top-level `team.md`, so the Init-Mode single-squad-or-federation offer (which fires only when neither `team.md` nor `federation.md` exists) never reaches it, and detection precedence keeps it a plain squad. **Promotion** is the additive path that adopts that existing squad into a federation as its first sub-squad without losing any state. It is opt-in and confirmation-gated: a consumer who never promotes is completely unaffected.

Promotion is a **relocation, not a rebuild**. It moves the existing top-level squad tree under a named sub-squad root and seeds the thin meta layer; it never re-creates the roster or rewrites prior append-only bytes. Supported hosts execute the relocation through the sealed-plan transaction in `Get-SquadPromotionPlan.ps1` and `Promote-SquadFederation.ps1`; the Scribe procedure is compatibility fallback only when those scripts are unavailable.

### Trigger

The Squad Federation Coordinator enters Promotion Mode when **all** of these hold: a top-level `team.md` is present, no top-level `federation.md` is present, and the user asks to move to a federation (or invokes `/squad-federation promote`). The single Squad Coordinator, on detecting a top-level `team.md` and a user request to federate, offers the handoff to `/squad-federation promote` rather than promoting anything itself. Nothing is moved or written before the user confirms.

### Steps

1. **Choose the sub-squad name and seal a plan.** Default to a name derived from the existing squad's seeded profile (for example, `default`, `azure`, `product`), normalized to lower-kebab-case and validated per *Sub-Squad Naming and Uniqueness*. Run `Get-SquadPromotionPlan.ps1` with that name and a new transport path outside squad state. It writes no state; it seals compact digests for the complete squad and every candidate directory. The name must not collide with an existing member directory.
2. **Enumerate from disk and confirm an exhaustive partition.** Present every planned directory under `.copilot-tracking/` except `squad/`, including file/byte counts and any `requiredToRelocate` reasons derived from roster roots or append-only history. The confirmed `RelocateDirectory` and `KeepDirectory` sets are disjoint and together name every candidate. A required candidate cannot be kept. Ambiguity is resolved by asking, never by omission.
3. **Apply the exact sealed plan.** Invoke `Promote-SquadFederation.ps1` with the exact plan SHA-256 and `-Confirmed`. A changed source tree, candidate, plan file, candidate set, existing federation or member collision refuses before mutation.
4. **Stage, verify, then publish.** The writer builds the complete final federation in a sibling transaction directory, copies and verifies every source tree, rebases the roster, appends a zero-consumption promotion entry, preserves and checks the ledger/totals, and validates the federation snapshot. Only then does it take the ordinary writer lock, revalidate the plan, move sources into a rollback backup and publish the staged root. A pre-commit failure leaves every source path intact; a publish failure restores owned sources when they remain unchanged.
5. **Rebase the relocated roster's deliverable roots.** The moved `team.md` still points every role at the repository-root tracking paths the artifacts just left, so prefix each `Deliverable Root` cell that begins with `.copilot-tracking/` with `.copilot-tracking/squad/members/<name>/`, leaving `docs/` and `outputs/` unchanged. Rebase whatever the cell holds, including a path the consumer edited by hand, so a customized root survives the promotion pointing at its own relocated directory. This column is the one field a promotion rewrites, and it is deliberate: `team.md` has replace semantics, and the byte-for-byte guarantee protects the append-only logs rather than freezing a roster whose paths the promotion has just invalidated. Nothing else in the roster changes — no role is re-cast, renamed, added, or dropped.
6. **Seed the meta layer** at the federation root `.copilot-tracking/squad/`: `federation.md` with one row for the promoted sub-squad (profile inferred from the moved `team.md`, `kind=in-repo`, `location=members/<name>/`); `meta-routing.md` whose patterns all route to that sole sub-squad initially (derived from its profile and description); a federation `decisions.md` whose first entry records the promotion and the source→destination move; `history/<name>.md`; and a federation `state.json`.
7. **Carry the consumption ledger across the boundary.** The relocated `consumption.md` and `consumption-rates.md` describe a continuing run. Record the model-free promotion in `members/<name>/history/Squad Scribe.md` without a Consumption block, preserve `consumption.md` and member run totals unchanged, check the ledger read-only, and seed federation totals from that verified member state.

The move (step 2) removes the top-level `team.md`, so detection precedence flips from "top-level `team.md`" (plain squad) to "top-level `federation.md`" (federation) the moment promotion completes. From the next turn, `/squad-federation` owns turns and `/squad` detects the federation and defers.

### Copy, Verify, Then Delete

Every source tree in step 4 follows **copy → verify → remove-source**, in that order. The final destination is completely staged and checked first. Source paths disappear only inside the short locked publish, where they are renamed into the rollback backup before the stage replaces them. Nothing is cleared or truncated before its verified copy exists.

Deleting first is the one failure mode this contract exists to prevent: a relocation that clears the source and then cannot find the files to move has destroyed append-only decision and history logs that no later step can reconstruct. When a destination write fails, stop and escalate with the source still intact; a partially relocated tree with an intact source is recoverable, and a deleted source is not.

**Every destination path is resolved from the project root**, and the transaction creates only its named stage/backup siblings under `.copilot-tracking/`; both are removed before a success receipt. `.copilot-tracking/squad/members/<name>/plans/` is the whole final path, never a segment appended to the caller's working directory. The writer rejects a nested `.copilot-tracking/`, verifies relocated sources are absent, verifies kept directories still match their sealed digests, and reports no success while a transaction directory remains.

### Guards

* **Idempotency.** When a top-level `federation.md` already exists, the project is already a federation — the coordinator does not promote; it routes the request (or runs Federation Init to add a sub-squad) instead.
* **No overwrite.** Promotion never moves the existing tree into a `members/<name>/` directory that already exists; on a name collision the coordinator stops and asks the user to choose a different name.
* **No deliverable overwrite.** A deliverable directory is never merged into an existing one of the same name under `members/<name>/`; on a collision the promotion stops with both copies intact and asks the user how to reconcile, rather than overwriting an artifact.
* **Additional sub-squads (optional).** In the same promotion turn the user may add further sub-squads by reusing Federation Init's propose → confirm → create for each new one; the minimum promotion wraps the existing squad as exactly one sub-squad.

### Automatic Promotion (Watch Mode)

An event-triggered **Watch Mode** run has no human in the loop at trigger time, yet it must execute inside an event-scoped sub-squad. When such a run finds a plain single squad — a top-level `team.md` and no `federation.md` — it performs the same promotion **auto-approved**, then adds the event's own sub-squad through *Automatic Expansion* below. The full trigger contract is `.github/instructions/squad/squad-watch-mode.instructions.md`.

Everything about the promotion is otherwise identical: the same sealed-plan writer, verified staging, append-only-prefix preservation, meta-layer seed, collision refusal and consumption carry-over. Only the confirmation step differs, and that exception is deliberately bounded — the operation writes only under `.copilot-tracking/`, it runs only after the Watch Mode opt-in gate and trigger authorization have already passed, it is a relocation rather than a rebuild, and it waives no Human Gate inside the run.

* **Unattended deliverable enumeration.** There is no user to confirm the candidate list, so the run moves every `.copilot-tracking/` directory except `squad/` and records the moved list in the promotion decision entry for a human to review. A collision still stops the run rather than resolving itself.
* **Name derivation.** The promoted sub-squad takes the name of the profile recorded in the existing `team.md` (for example `azure`, `product`), normalized and validated per *Sub-Squad Naming and Uniqueness*, falling back to `default` when the profile cannot be read. The name is never derived from the triggering event, because the squad predates it.
* **Concurrent promotion is a compare-and-swap.** Two events may be in flight and both observe a plain single squad. The promotion writer's locked revalidation and exit 4 are the swap check: the loser re-detects the repository state once and continues as an expansion instead. Only a second consecutive failure escalates.
* **Escalation, not overwrite.** A collision with an existing `members/<name>/` directory stops the run and escalates on the source thread, exactly as the interactive guard does. Watch Mode never proceeds without its sub-squad.

## Expansion: Add a Sub-Squad to an Existing Federation

Once a federation exists, a team can grow it by **adding a new sub-squad** — for example, adding a `security` sub-squad alongside an existing `product` and `azure`. Expansion is the first-class operation for this; it is additive and confirmation-gated, and it never touches an existing sub-squad. Expansion is what the Federation Init entry point does when a federation is **already present**: Init *builds* a federation on a fresh project (no `federation.md`) and *expands* one when a `federation.md` is already there.

### Trigger

The Squad Federation Coordinator runs Expansion when a top-level `federation.md` is present and the user asks to add a sub-squad (or passes `init`, which on an existing federation means expand, not rebuild). Nothing is written before the user confirms.

### Steps (script-backed)

1. **Propose the new sub-squad(s).** Each is a unique lower-kebab-case name, a profile (or a custom roster), an optional owner, and a one-line description, proposed from the repo and request exactly as Init proposes a sub-squad.
2. **Prepare one sealed Init payload.** Run `Get-SquadFederationInitPlan.ps1`. It validates names against both the registry and member directories, rejects route/history collisions, validates every new roster through the single-squad Init builder, and seals the current federation root files plus registered member state.
3. **Apply the exact payload.** Run `Initialize-SquadFederation.ps1 -Confirmed` with the exact payload hash. It initializes all new members in parallel inside an isolated stage, requires every ledger receipt, and builds the final root projection without copying or editing any existing member tree.
4. **Commit additively under the root lock.** The transaction revalidates the sealed federation, moves only the verified new member directories, appends registry/routes/decisions/history, advances aggregate state and verifies the final snapshot. A stale root, collision, timeout or failed write rolls back owned changes and returns nonzero; never dispatch Scribe as a retry.

### Guards

* **No overwrite.** Expansion never seeds into a `members/<new>/` directory that already exists, and never registers a name already in `federation.md`; on a collision the coordinator stops and asks the user to choose a different name.
* **Additive only.** Expansion adds a sub-squad; it never edits, renames, or removes an existing one. Renaming or removing a sub-squad is a separate, explicit Scribe-performed operation.
* **Requires a federation.** When no top-level `federation.md` exists, this is not an expansion: build a federation (Init) or adopt an existing single squad (Promotion) instead.

### Automatic Expansion (Watch Mode)

A **Watch Mode** run adds its own event-scoped sub-squad through this same
transaction, **auto-approved** rather than confirmation-gated, for the same
bounded reasons given under *Automatic Promotion (Watch Mode)*. Supported hosts
use the sealed Init payload and additive locked commit; compatibility hosts use
the preserve-on-replace cold procedure.

* **Event-derived name.** The new sub-squad's name comes from the event's structural identity (`issue-<N>`, `pr-<N>`, `sweep-<YYYY-MM-DD>`, `push-<branch-slug>-<sha7>`, `dispatch-<runId>`), never from payload prose. The naming table and normalization rules live in `.github/instructions/squad/squad-watch-mode.instructions.md`.
* **Reuse before create.** When the derived name already exists as a watch-owned sub-squad whose recorded trigger provenance matches this event, the run reuses it and no expansion occurs. A watch-owned name with different provenance is disambiguated by appending the workflow run id once.
* **Never into a human-owned sub-squad.** When the derived name matches a sub-squad that is not watch-owned, the run escalates and stops. A `members/<name>/` directory with **no registry row** is resolved by evidence rather than refused outright: when its `state.json` `trigger.ref` and `trigger.eventId` match the current event it is this run's own prior attempt, so the row is re-registered and the run resumes; otherwise it is treated as human-owned and the run escalates and stops. See *Reuse, Collisions, and Concurrency* in `.github/instructions/squad/squad-watch-mode.instructions.md`. The no-overwrite guard remains absolute in the unattended path: nothing that cannot prove it belongs to this event is ever written into.

## Cross-Sub-Squad Handoff

Sub-squad isolation is deliberate: each sub-squad reads and writes inside its own root so parallel runs never race and each keeps its own auditable record. That same isolation means a sub-squad **cannot discover another's work on its own**. A run scoped to `members/azure/` resolves every deliverable root under `members/azure/`, so a `product` sub-squad's PRD sitting at `members/product/plans/` is invisible to it. Nothing in a sub-squad's inner run reads federation-level state, so the federation `decisions.md` is not a discovery mechanism either — it records that a sub-squad ran, for the federation's audit trail, not a path index the next sub-squad consults.

The Squad Federation Coordinator is the only component that sees both roots, so **it resolves the producer's artifacts and hands them to the consumer as explicit read-only input paths.** A consumer that was handed no paths was handed no dependency.

* **The interface is the producer's artifacts, not its state.** A handoff passes files under `members/<producer>/` — the PRD, the research, the plan. The producer's `decisions.md` and `history/` say *which* artifact is current and why, and are worth passing alongside for that reason, but they are never the substitute for the artifact itself.
* **Resolve paths by reading, then verify by listing.** Read the producer's `team.md` `Deliverable Root` cells to know where its roles write, then list those directories and confirm each file exists before passing it. A handoff path that this turn did not enumerate is a guess, and a consumer sent to a path that does not exist fails in the middle of its run rather than at the boundary.
* **Producer before consumer, and the pair is not parallel-eligible.** A dependency makes the two runs ordered by definition. When meta-routing fans a request out to both, run the producer's turn to completion — including its artifact gate — before dispatching the consumer, and say so when proposing the fan-out.
* **Read-only across the boundary, always.** The consumer reads the producer's artifacts and writes its own output under its own root. A sub-squad never writes into another's `members/<name>/` tree, never edits a producer's artifact to suit itself, and never appends to a producer's logs. When the consumer's work implies a change to the producer's artifact, that is a request routed back to the producer, not an edit made across the boundary.
* **Record the handoff.** Append a federation-level `decisions.md` entry naming the producer, the consumer, and the artifacts passed. This is what makes a two-sub-squad outcome reconstructable later: without it, the consumer's plan cites requirements whose origin is nowhere in the record.
* **A missing producer artifact escalates; it never falls back to re-derivation.** When the producer has not produced the artifact yet, or its deliverable root is empty, stop and run the recovery below rather than dispatching the consumer to work it out. A consumer that re-derives the requirements produces a plausible, complete-looking deliverable built on requirements the product sub-squad never agreed \u2014 the two halves then diverge silently, which is worse than a stalled run because nothing in the output reveals it.

### Recovery: What Happens When the Input Is Missing

Stopping is the safety property, not the outcome. The coordinator already knows which sub-squad owns the missing artifact, so the default recovery is to **produce it and then continue the same turn** \u2014 the user should not have to re-issue the request. This mirrors the bounded auto-remediation loop in `.github/instructions/squad/squad-intake-gate.instructions.md`, and reuses its vocabulary rather than inventing a second one.

Resolve in this order, taking the first case that applies:

1. **The producer sub-squad is registered and simply has not run.** Run it first, then resume the consumer in the same turn once its artifact verifies on disk. Ordering was already the declared contract for a dependency, so this is enforcing the order rather than making a new decision. Interactive turns state what will run and wait for a go-ahead; an autopilot or Watch Mode run does it without asking, because dependency-first ordering was settled at its plan meta-stage.
2. **The artifact exists but is partial or stale.** Re-dispatch only the producing **stage** inside the producer sub-squad, not the whole sub-squad, and say which artifact fell short and how. Re-running a completed sub-squad to fix one stage discards work that was fine.
3. **No sub-squad owns the artifact.** This is a structural gap, not a run failure: the federation has no producer for what the consumer needs. Offer Federation Expansion to add the owning sub-squad, or accept a path the user supplies to an artifact that already exists elsewhere in the repository. Do not route the work to the consumer because it happens to be the sub-squad in front of you.
4. **The user overrides.** The user may always name an input path directly, or accept proceeding **with the gap recorded as an explicit assumption** — the `Ready-With-Gaps` shape from the intake gate. Recording is what separates this from re-derivation: the consumer's output then carries a visible statement of what it assumed and who chose to proceed, instead of presenting an invented requirement as an agreed one.

**Bound the loop.** One producer run per handoff per turn. A second consecutive miss on the same artifact escalates to the user rather than looping again, exactly as the intake gate escalates on divergence. Each producer run and each re-dispatch is a normal Scribe-recorded stage with its own history entry and consumption block, so the recovery is auditable rather than invisible.

The same contract governs a **federation autopilot** meta-run, where the ordering is resolved once in the plan meta-stage; see `.github/instructions/squad/squad-federation-autopilot.instructions.md`.

## Registry Schema (`federation.md`)

The registry is the durable list of sub-squads the Federation Coordinator can route to. It begins with YAML frontmatter and a single H1, then a `## Sub-Squads` table:

| Column      | Meaning                                                                                              |
|-------------|------------------------------------------------------------------------------------------------------|
| Sub-squad   | Unique name, lower-kebab-case (for example, `product`, `azure`); also the `members/<name>/` directory |
| Profile     | The profile the sub-squad was seeded from (`default`, `full`, `security`, `design`, `accessibility`, `architecture`, `azure`, `modernization`, `compliance`, `operations`, `product`) or `custom`, followed by any registered packs in `+pack` form (for example, `azure +foundry`) |
| Kind        | `in-repo` (state under `members/<name>/`) — `repo` is reserved for the deferred multi-repo federation |
| Location    | `members/<name>/` for an `in-repo` sub-squad                                                          |
| Owner       | Optional human or team label (for example, `business-team`, `architects`)                            |
| Description | One-line purpose the meta-routing table uses to choose this sub-squad                                 |

`Kind=repo` and external `Location` values are defined by the deferred multi-repo plan and are not seeded by the in-repo flow.

### Registry Example

```markdown
## Sub-Squads

| Sub-squad | Profile | Kind    | Location          | Owner         | Description                                              |
|-----------|---------|---------|-------------------|---------------|---------------------------------------------------------|
| product   | product | in-repo | members/product/  | business-team | Requirements, roadmap, and stakeholder deliverables     |
| azure     | azure   | in-repo | members/azure/    | architects    | Azure build: Bicep, landing-zone, cost, and deployment  |
```

### Watch-Owned Sub-Squads

Sub-squads created by the unattended Watch Mode bootstrap are marked with the registry's existing optional columns, so no schema change is needed and every existing registry stays valid:

* `Owner` is `watch-mode`. This marker is the discriminator that lets the unattended path decide whether a name collision is a safe reuse or a refusal.
* `Description` records the source ref and the terminal deliverable, for example `Watch Mode run for owner/repo#123 (issue) -> PR #456`.
* The `meta-routing.md` route for a watch-owned sub-squad is **narrow and ref-keyed**: its `Pattern / Domain` is the exact event ref token (for example `watch: owner/repo#123`) and `Parallel-Eligible` is `no`. A broad keyword pattern would hijack interactive routing, so watch-owned sub-squads are never selected by keyword matching — Watch Mode targets them by name.

```markdown
| Sub-squad | Profile | Kind    | Location           | Owner      | Description                                          |
|-----------|---------|---------|--------------------|------------|------------------------------------------------------|
| issue-123 | default | in-repo | members/issue-123/ | watch-mode | Watch Mode run for owner/repo#123 (issue) -> PR #456 |
```

Watch-owned sub-squads are **retained**: they are the audit trail of what continuous AI did, so nothing prunes them automatically. Archiving or removing one is a separate, explicit, human-initiated Scribe operation, exactly as renaming or removing any sub-squad is.

### Sub-Squad Naming and Uniqueness

Every sub-squad has a **required, unique name** because the name is simultaneously the registry key, the `members/<name>/` state directory, and the `squad=<name>` selector the user types to target it. A collision would make two sub-squads share one folder and one selector, so names are validated before any folder is created.

* **Required.** No sub-squad may be nameless — including a custom sub-squad the user builds from a role menu. When the user proposes a custom sub-squad without naming it, the coordinator asks for a name before creating it.
* **Format.** Lower-kebab-case, matching `^[a-z0-9][a-z0-9-]*$` (letters, digits, and internal hyphens; no spaces, slashes, dots, uppercase, or leading hyphen) so the name is a safe directory segment and an unambiguous selector. The coordinator suggests a normalized form when the user offers a name that does not fit (for example, `Data Platform` → `data-platform`).
* **Unique within the federation.** No two sub-squads may share a name, compared case-insensitively after normalization. Before creating sub-squads, the coordinator checks the proposed set against itself and against any name already in `federation.md`; on a duplicate it stops and asks the user to rename one before proceeding — it never auto-suffixes silently or reuses an existing `members/<name>/` directory.
* **Stable.** The name is the durable handle used across turns. Renaming a sub-squad later means renaming its `members/<name>/` directory and its `federation.md` row together (a Scribe-performed change), so the coordinator treats a rename as an explicit operation, not a routine edit.

These rules are the sub-squad-level analogue of the per-member `Member Name` uniqueness in `squad-roster.instructions.md`: there, names disambiguate two rows of the same role; here, names disambiguate two sub-squads so each maps to exactly one folder and one selector.

## Meta-Routing Schema (`meta-routing.md`)

Meta-routing decides *which sub-squad* handles a request, the layer above the per-squad routing that decides *which role* acts. It begins with YAML frontmatter and a single H1, then a routing table:

| Column            | Meaning                                                                                     |
|-------------------|---------------------------------------------------------------------------------------------|
| Pattern / Domain  | The request trigger the Federation Coordinator matches (keywords, domain, or phrasing)       |
| Sub-squad         | The registered sub-squad the pattern routes to (must exist in `federation.md`)              |
| Parallel-Eligible | `yes` when the sub-squad can run concurrently with other sub-squads for one request; else `no` |

### Meta-Routing Example

```markdown
| Pattern / Domain                                                | Sub-squad | Parallel-Eligible |
|-----------------------------------------------------------------|-----------|-------------------|
| requirements, PRD, BRD, roadmap, backlog, stakeholder, discovery | product   | yes               |
| Azure, Bicep, landing zone, deploy, IaC, cost, infrastructure    | azure     | yes               |
```

### Meta-Routing Rules

* Match the most specific pattern first; when several match, prefer the sub-squad that most directly owns the requested outcome.
* An explicit `squad=<name>` target from the user overrides meta-routing for the turn.
* Dispatch parallel-eligible sub-squads concurrently; run non-parallel sub-squads sequentially. Each sub-squad's own routing then governs role dispatch inside it.
* Escalate to the user — rather than guessing — when no pattern matches with reasonable confidence, when a matched sub-squad is not in the registry, or when two patterns conflict with no clearly more specific match. State the ambiguity, list the candidate sub-squads, and ask the user to choose.

## Two-Level State and the Single Writer

Supported Init/Expansion, Promotion, and ordinary federation handoffs use their
validated root writers. Member roster growth is member-scoped; root state is
unchanged. Aggregate summaries, repairs, renames/removals and
unsupported-host fallbacks remain cold Scribe work. Supported ordinary
member-root handoffs run the validated writer directly and synchronously with
`-Quiet` in every routing mode, per `references/economy-scribe.md`. Serialize
direct writer, cold Scribe, and Cost Preflight at each root. Initialization stays
outside admission; Cost Preflight remains the narrow coordinator hand-edited
transaction (matching decision plus compare-and-swap
`currentRun.costPreflight`, then read back).

* **Sub-squad level.** When the Federation Coordinator drives a sub-squad, the Scribe writes that sub-squad's `decisions.md`, `history/<agent>.md`, `consumption.md`, and the rest under `members/<name>/`, exactly as for a plain squad. Proof-of-dispatch is unchanged: a sub-squad stage is proven by a `members/<name>/history/<agent>.md` entry plus its consumption block. The pre-work gates are sub-squad state like everything else: a `## Discovery Verdict` and a `## Intake Readiness Verdict` land in `members/<name>/decisions.md`, and a discovery brief lands in `members/<name>/plans/`, never at the federation root.
* **Federation level.** Ordinary or targeted routing forwards the same ceiling lifecycle to every selected sub-squad, where each ceiling is independent; the root records routing but performs no aggregate preflight. Untargeted `mode=autopilot` instead keeps one aggregate ceiling at the root, uses the root rate table, and does not double-gate child runs. Federation decisions and `history/<sub-squad>.md` link both levels.

No coordinator hand-edits history, prior decisions, or state outside Cost Preflight; direct validated execution is not a bypass. Every admitted child carries its preflight run, round, and slot to cold Scribe. Each member's writes stay inside its root, so parallel sub-squads never touch the same files.

Cold Scribe hand-off pipelining follows this same per-root scoping: the federation root itself never pipelines its own meta-transitions, and each sub-squad's inner run evaluates the Enablement Predicate (`.github/instructions/squad/squad-autopilot.instructions.md`) against its own root. Direct ordinary writes are synchronous. An inner run under an aggregate ceiling may pipeline cold Scribe work because meta rounds read its ledger only after all its writers have returned and verified.

## Relationship to Multi-Repo Federation (deferred)

This file specifies the **in-repo** federation. The **multi-repo** federation — a hub that coordinates one squad per repository — reuses everything here and only changes a sub-squad's `Kind` to `repo` and its `Location` to an external repository, plus a cross-repo execution driver. Its research and plan live in `.copilot-tracking/plans/2026-07-16/squad-federation-multi-repo-plan.instructions.md`. The `repo` kind is reserved but not seeded by the in-repo flow.
