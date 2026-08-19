# Squad Behavior Contract and Regression Test Plan

Defines the end result a squad run must produce, so a release can be blocked when it stops producing it.

Every assertion below is derived from the squad source itself — the coordinators, the Scribe, the `squad-*` instruction files, and the `squad` skill references. Nothing here is invented: each case cites the file that states the rule.

## How this plan is used

The suite runs twice against two different refs and the two results are compared.

1. **Baseline run — against `main`.** Establishes that the suite itself is correct. Every case must pass. A case that fails on `main` is a defect in the case, not in the product, and is fixed before proceeding.
2. **Candidate run — against `v0.16.0-pre`.** Any case that passed on `main` and fails here is a regression introduced by the refactor. Any case that fails on both is a pre-existing gap. Any case that only exists for `0.16.0` is a new-feature check.
3. **Release gate.** The candidate run must be green before the release workflow is allowed to tag.

Both runs install the package from a published ref into a scratch directory and exercise it there. They never test the working tree — testing the installed artifact is what catches packaging and reference-resolution defects.

## Tiers

| Tier | What it is | LLM calls | Runs on |
|---|---|---|---|
| 0 | Static conformance of the installed package | none | every PR, and the release gate |
| 1 | Live behavioral runs against fixture repos | yes | the release gate |
| 2 | Semantic comparison against a golden baseline | yes | advisory at first |

Tier 0 is deterministic and free. Tier 1 asserts on **state artifacts on disk**, never on prose, which is what makes it stable despite model nondeterminism. Tier 2 is the only tier that judges wording, and it starts advisory until the noise floor is known.

## Verified parity evidence

Checked directly while writing this plan, comparing `origin/main` (`de7feef`, 0.15.3) against the branch:

* On `main` the `/squad-document`, `/squad-governance-report`, and `/squad-learn` prompts carry **no `agent:` binding** — the whole procedure is inline and runs on whatever agent the user is in. On the branch each binds to a dedicated agent. This is the single largest behavioral change in the three entrypoints and is why they need output-level cases, not structural ones.
* The moved text is otherwise verbatim. The `docx` conversion command, the `Open Questions` section, the seven governance section titles, the `SL-`/`TL-` id conventions, and both learnings target paths are byte-identical between main's prompts and the branch's agents.

That parity is evidence, not proof. The cases below are what turn it into proof.

## Tier 0 — Static conformance

No Copilot invocation. Install the ref into a scratch directory, then inspect the delivered tree.

| ID | Assertion | Rationale |
|---|---|---|
| PKG-01 | `apm install` completes and emits **zero** unpinned-reference warnings | The defect class that made tags non-reproducible |
| PKG-02 | Every agent named in a coordinator `agents:` roster resolves to a delivered `*.agent.md` whose `name:` matches exactly | A roster naming an undelivered agent makes the coordinator stop and escalate at runtime |
| PKG-03 | Every reference file named in an agent's Skill Reference Contract exists at the stated path | A missing reference silently strips the agent's procedure |
| PKG-04 | Every `*.agent.md` prompt body is at most 30,000 characters | Host cap; exceeding it truncates the contract |
| PKG-05 | Every `*.prompt.md` `agent:` value resolves to a delivered agent `name:` | New binding introduced by the refactor |
| PKG-06 | Every agent and prompt frontmatter parses, and agents carry `name`, `description`, `user-invocable`, `disable-model-invocation` | |
| PKG-07 | `squad-floor.instructions.md` is delivered and declares `applyTo: '**'` | It is the always-on floor; if it is not delivered the floor is silently absent |
| PKG-08 | No relative link inside a delivered skill reference points at a missing file | |
| PKG-09 | All five entrypoint prompts are delivered: `squad`, `squad-federation`, `squad-document`, `squad-governance-report`, `squad-learn` | |
| PKG-10 | Worker agents declare `user-invocable: false`; the three user-facing agents declare `user-invocable: true` | Wrong flag either hides an entrypoint or exposes a worker |

## Tier 1 — Single squad

Fixture: a small repository with no `.copilot-tracking/squad/` directory.

### Init

| ID | Assertion | Source |
|---|---|---|
| SQ-01 | After Init, these exist under `.copilot-tracking/squad/`: `team.md`, `routing.md`, `decisions.md`, `state.json`, `notifications.md`, `consumption.md`, `consumption-rates.md`, and a `history/` directory | `squad-state.instructions.md`, State Layout |
| SQ-02 | `history/` contains **no** `<agent>.md` files yet | History is created lazily on first dispatch, never seeded empty |
| SQ-03 | `state.json` parses and carries `schemaVersion`, `updated`, `turn`, `mode`, `activeRoles`, `openEscalations`, `currentRun.{sessionModel,modelOverrides,estCostUsd,estCreditsTotal}`, `notify.{approvalChannel,enabled,email,github.{handle,repo}}` | `entry-schemas.md` |
| SQ-04 | `state.json` `mode` is one of `interactive`, `autonomous`, `autopilot`; `notify.approvalChannel` is one of `in-chat`, `github-issue`, `webhook` | `squad-state.instructions.md` |
| SQ-05 | `team.md` contains a `## Members` table with columns `Role`, `Member Name`, `Agent Name (Primary)`, `Alternate Agents`, `Invocation`, `Model Tier`, `Deliverable Root` | `squad-roster.instructions.md`, Members Schema |
| SQ-06 | Every `Agent Name (Primary)` value in `team.md` matches a delivered agent `name:` | Ties runtime roster to PKG-02 |
| SQ-07 | `routing.md` contains columns `Pattern / Keyword`, `Role(s)`, `Autonomy Tier`, `Parallel-Eligible`; every `Autonomy Tier` is `auto`, `confirm`, or `escalate` | `squad-routing.instructions.md` |
| SQ-08 | Every `Role(s)` value in `routing.md` resolves to a `Role` in `team.md` | Unroutable role means a dead branch |

### Ordinary routing turn

Precondition: an initialized squad. Action: one request that routes to at least one role.

| ID | Assertion | Source |
|---|---|---|
| SQ-10 | A `history/<agent>.md` file exists for each dispatched agent | `scribe-procedure.md` Step 2 |
| SQ-10a | **Completeness, both directions.** The set of agents with a new history entry equals the set of roles the run reports as dispatched — no dispatched role without an entry, and no entry for a role the run never claimed | Proof of Dispatch |
| SQ-10b | **No orphan history.** Every `history/<agent>.md` corresponds to an `Agent Name (Primary)` or `Alternate Agents` value in `team.md` | Roster is the source of truth |
| SQ-10c | Each dispatch entry records the request the agent received, the findings or outcome it returned, and the turn it was dispatched on | `entry-schemas.md`, history schema |
| SQ-10d | The history file carries its `# History: <agent>` heading and description frontmatter when created | `entry-schemas.md` |
| SQ-11 | Each dispatch entry is followed by a `#### Consumption` heading (or `#### Consumption — Orchestration`) and a fenced `json` block | `scribe-procedure.md` Step 6 |
| SQ-12 | That JSON block carries exactly these keys in this order: `model`, `model_source`, `priced_as`, `model_tier`, `internal_turns`, `input_tokens`, `cached_tokens`, `cache_write_tokens`, `output_tokens`, `input_rate`, `cached_rate`, `cache_write_rate`, `output_rate`, `est_cost_usd`, `est_credits`, `basis` | `scribe-procedure.md` Step 6 |
| SQ-13 | Every numeric field in that block is a bare number — no thousands separators, no `~`, no units, no parenthetical qualifiers | `scribe-procedure.md` Step 6; the ledger rewrite reparses these |
| SQ-14 | **No history entry exists without its consumption block** | `squad-state.instructions.md`, Proof of Dispatch |
| SQ-15 | `decisions.md` grew, and its pre-turn content is byte-identical as a prefix of its post-turn content | Append-only; catches silent rewrites |
| SQ-16 | `consumption.md` contains two separate tables, `## Attribution` and `## Usage & Cost`, never merged into one wide table, each with an `orchestration` row and the latter with a `**Total**` row | `consumption.md` reference |
| SQ-17 | Roles appear in `consumption.md` in roster order, and every dispatched role appears | `scribe-procedure.md` Step 8 |
| SQ-18 | `state.json` `turn` incremented by exactly one, `updated` changed, `activeRoles` equals the set of roles dispatched this turn | `scribe-procedure.md` Step 13 |
| SQ-19 | `state.json` was written **last** — its `updated` is at or after every timestamp written this turn | `scribe-procedure.md` Step 13 |

### Proof of dispatch — the cases that matter most

These are the ones that catch a coordinator quietly doing the work itself, which is the failure mode the whole architecture exists to prevent.

| ID | Assertion | Source |
|---|---|---|
| SQ-20 | For every stage the run reports as complete, **both** exist: the domain artifact on disk at that role's `Deliverable Root`, and a `history/<agent>.md` entry carrying its consumption block | `squad-state.instructions.md` and `squad-floor.instructions.md`, Proof of Dispatch |
| SQ-20a | **Exemption.** `cost-manager`, `deployer`, `fact-checker`, `intake-validator`, `asbuilt-author`, `azure-diagnose`, and `aws-diagnose` have no Deliverable Root and write no standalone artifact. For these, the history entry alone is proof; asserting an artifact would be a false failure | `squad-roster.instructions.md`, Deliverable Roots |
| SQ-21 | The deliverable is located at the `Deliverable Root` the roster names for that role — not at a path the coordinator chose | Makes the Artifact Gate a lookup |
| SQ-22 | No stage is reported complete while its history entry is absent | "No history entry means the stage did not happen" |
| SQ-23 | **Negative case.** Point one roster row at an agent that is not installed, then send a request that routes to it. The run must **stop and escalate**. Assert: no deliverable produced for that role, no history entry, an escalation recorded, and no substitute agent dispatched | `squad-coordinator.agent.md`, Dispatch Discipline |
| SQ-24 | **Negative case.** Send a request whose domain matches a bundled specialist skill. Assert the coordinator activated only the `squad` skill and produced no specialist artifact before dispatching; the specialist artifact appears only after the resolved role ran | `squad-coordinator.agent.md`, Dispatch Discipline — the rule added by PR #74 |

## Tier 1 — Consumption integrity

Presence of a consumption block is not the same as a correct ledger. These cases check the numbers, and they are almost all pure arithmetic over files on disk — deterministic despite the run that produced them being nondeterministic.

### Per-dispatch block correctness

| ID | Assertion | Source |
|---|---|---|
| CON-01 | `est_cost_usd` equals `((input_tokens × input_rate) + (cached_tokens × cached_rate) + (cache_write_tokens × cache_write_rate) + (output_tokens × output_rate)) / 1e6 × calibration_factor`, within a rounding tolerance | `consumption-rates.md` cost derivation |
| CON-02 | `est_credits` equals `est_cost_usd / 0.01` | Same |
| CON-03 | Each of `input_rate`, `cached_rate`, `cache_write_rate`, `output_rate` matches the row for that `model` in `consumption-rates.md` — no hand-typed rate that drifts from the table | Only that file holds token rates |
| CON-04 | `basis` is exactly one of `estimated` or `tier-default`, never a combined value | `scribe-procedure.md` Step 5 |
| CON-05 | When `basis` is `tier-default`, the rates used are the **tier fallback** rates, priced at the tier's most expensive member — deliberately conservative-high | `consumption-rates.md`, Tier fallback |
| CON-06 | `model_source` is one of `dispatch-reported`, `agent-pinned`, `operator-declared`, `session-inherited`, `cli-pinned`, or the unresolved value — never a free-text string | `scribe-procedure.md` Step 5 |
| CON-07 | `model` is either a model present in `consumption-rates.md` or the literal `unknown` — **never an invented model name** | `squad-scribe.agent.md`: "never carries an invented model name" |
| CON-08 | `priced_as` is populated only when it differs from `model` | `scribe-procedure.md` Step 8 |
| CON-09 | A block is produced for **every** dispatch, including ones where no consumption payload was supplied | `squad-scribe.agent.md`: Step 7 runs for every dispatch recorded in Step 2 |
| CON-10 | Anthropic-family models carry a non-zero `cache_write_rate`; models without one leave it at `0` | `consumption-rates.md` |

### Orchestration overhead

| ID | Assertion | Source |
|---|---|---|
| CON-20 | An `#### Consumption — Orchestration` block exists for the turn — the coordinator's own turns and the Scribe's writes are never uncounted | `scribe-procedure.md` Step 7 |
| CON-21 | The orchestration block covers one coordinator turn **per dispatch round** plus one `Scribe state write` per hand-off; a turn with three dispatch rounds does not record one coordinator turn | Same |
| CON-22 | `consumption.md` carries an `orchestration` row in **both** the Attribution and the Usage & Cost tables | `consumption.md` template |
| CON-23 | The `orchestration` row `Tier` is `mixed` | `consumption.md` template |

### Ledger accumulation — the highest-value group

The ledger has replace semantics but the rows accumulate. The documented failure mode is a Scribe that rewrites from the turn's payload alone, silently deleting every earlier role from the ledger while leaving its history intact. That is invisible unless tested across multiple turns.

| ID | Assertion | Source |
|---|---|---|
| CON-30 | **Multi-turn.** Run at least three turns dispatching different roles. After the last turn, `consumption.md` still holds a row for the role dispatched on turn 1 | `scribe-procedure.md` Step 8: "a role dispatched on turn 2 still holds a row on turn 9" |
| CON-31 | **Repeat dispatch.** A role dispatched three times holds **one** row whose token counts and cost are the sum of its three blocks — not three rows and not the latest block only | Same |
| CON-32 | Every row in `consumption.md` is re-derivable from the blocks in `history/*.md`: for each role, the row equals the sum of that agent's blocks | Same: "Derive the rows from every consumption block recorded in `history/*.md`" |
| CON-33 | The `orchestration` row equals the sum of every recorded orchestration block across the run | Same |
| CON-34 | The `**Total**` row equals the sum of all role rows plus the orchestration row, for every numeric column | `squad_cost = sum over dispatched roles of est_cost_usd` |
| CON-35 | **Round-trip.** Delete `consumption.md`, trigger a Scribe write, and assert the regenerated file is equivalent to the deleted one. This proves the blocks are actually parseable, which is the entire reason the format is strict | `scribe-procedure.md` Step 6 |
| CON-36 | **Negative case.** Inject a malformed block (`~8,400 (estimated)` instead of a bare number) and assert it is detected rather than silently dropped from the aggregate | Same: an unparseable block "drops that dispatch out of every later aggregate" |
| CON-37 | `consumption.md` is never left at its seed values while `history/*.md` shows dispatches occurred | `squad-state.instructions.md`, Proof of Dispatch |
| CON-38 | Roles appear in `consumption.md` in the same order as `team.md` | `scribe-procedure.md` Step 8: "mirroring roster order" |

### Rates file and calibration

| ID | Assertion | Source |
|---|---|---|
| CON-40 | `consumption-rates.md` passes the shape check: a per-model rate table with `Input`, `Cached`, `Cache write`, and `Output` columns, plus the tier fallback table, the estimator, and the calibration block | `scribe-procedure.md` Step 4 |
| CON-41 | **Negative case.** Corrupt or truncate `consumption-rates.md`, then run a turn. The Scribe must reseed it from the template rather than silently degrading every estimate | Same: seeds "when the file is missing **or** when the existing file fails the shape check" |
| CON-42 | `calibration_factor` is within `0.25`–`10.0` | `consumption-rates.md` |
| CON-43 | While `observations` is `0`, `calibration_factor` is exactly `1.00` and the ledger carries an **uncalibrated** note | Same |
| CON-44 | Every model named in any consumption block has a rate row in `consumption-rates.md`, or its block is flagged `basis: tier-default` | Cross-check binding CON-03 and CON-05 |

## Tier 1 — Routing and role selection

Checks that the *right* roles fire, not merely that some role fired. Each case sends a request and asserts on which `history/<agent>.md` files appeared.

### Positive selection

| ID | Request pattern | Must dispatch | Tier | Parallel |
|---|---|---|---|---|
| RTE-01 | `research, investigate, explore, find out` | `researcher` | `auto` | yes |
| RTE-02 | `plan, break down, sequence, design plan` | `lead` | `confirm` | no |
| RTE-03 | `implement, build, code, fix` | `developer` | `confirm` | no |
| RTE-04 | `review, validate, check quality` | `tester` | `auto` | yes |
| RTE-05 | `write tests, add test coverage, regression test` | `qa-engineer` — **not** `tester` | `confirm` | no |
| RTE-06 | `validate, council, design review, go/no-go` | `architect`, `security`, `cost-manager`, `product-owner` together | `confirm` | yes |

`tester` versus `qa-engineer` (RTE-04 against RTE-05) is worth its own pair because the split is read-versus-write and easy to regress: "review this change" is `tester`; "write tests for this" is `qa-engineer`.

### Negative selection and escalation

| ID | Assertion | Source |
|---|---|---|
| RTE-10 | A request matching a pattern whose role is **absent from the active roster** escalates and offers to add the role or switch profiles. It never dispatches, and never substitutes a different role | `squad-routing.instructions.md`, Roster Coverage |
| RTE-11 | A role that maps to `thin charter needed` escalates rather than a substitute being guessed | Dispatch Rules |
| RTE-12 | A GitLab merge-request or pipeline request escalates — the `escalate` tier — and states no dispatchable agent exists, rather than dispatching `product-owner` to do it | Routing notes |
| RTE-13 | A Power Platform request in a squad without the `power-platform` pack escalates **with the install command**, rather than dispatching | Routing notes |
| RTE-14 | When the roster lacks `intake-validator`, the intake gate **escalates** rather than skipping the check | Routing, Intake Gate |
| RTE-15 | An `escalate`-tier match never produces a dispatch — assert no new `history/<agent>.md` for that role | Escalation |

### Sequencing and concurrency

| ID | Assertion | Source |
|---|---|---|
| RTE-20 | All parallel-eligible roles for a turn are dispatched concurrently; non-parallel roles run sequentially | Dispatch Rules |
| RTE-21 | Two `Parallel-Eligible: no` roles matched in one turn produce history entries in a strict sequence, not interleaved | Same |
| RTE-22 | **Cost-first model selection.** Read-heavy `auto` roles resolve to the `fast` tier; reasoning-heavy `confirm` roles resolve to `default`. Assert against `model_tier` in each consumption block | Dispatch Rules |

### Methodology enforcement — Research to Plan to Implement to Review

This is the group that proves the squad is a methodology rather than an agent that happens to write code.

| ID | Assertion | Source |
|---|---|---|
| RTE-30 | **Cold implementation is refused.** Send an implement request with no research artifact under `.copilot-tracking/research/`. The coordinator must dispatch `researcher` first, not implement | Routing, methodology preconditions |
| RTE-31 | With research present but no plan under `.copilot-tracking/plans/`, the coordinator dispatches `lead` first | Same |
| RTE-32 | The coordinator **never produces** the missing research, plan, or verdict itself — assert no such artifact appears without a corresponding history entry for `researcher` or `lead` | "It never produces the missing research, plan, or verdict itself" |
| RTE-33 | **Closing review is mandatory.** After any implementation-tier role lands a change, `tester` is dispatched as the closing stage — in **every** mode, interactive, autonomous, and autopilot. Assert a `history/<tester-agent>.md` entry exists after every implementation | Routing, Closing Review |
| RTE-34 | With a `Stop` Council Verdict as the latest entry for the topic, an implementation request escalates instead of dispatching the implementer | Routing, council gate |
| RTE-35 | With `Go-With-Conditions`, the implementer is dispatched **and** the consolidated conditions are passed as inputs | Same |
| RTE-36 | A user override of a `Stop` is recorded through the Scribe **before** any implementer dispatches | Same |
| RTE-37 | `backlog-executor` is never dispatched without a finalized handoff; when none exists, `product-owner` is dispatched first | Routing, backlog notes |

## Tier 1 — Profile seeding

Init with each profile and assert the seeded roster holds exactly the documented member set. Cheap, fully deterministic once Init has run, and it catches a roster template that drifts from the catalog.

| ID | Profile | Expected members |
|---|---|---|
| PRF-01 | `default` | researcher, lead, developer, tester, scribe |
| PRF-02 | `security` | researcher, lead, developer, tester, security, supply-chain, rai, privacy, fact-checker, scribe |
| PRF-03 | `design` | researcher, lead, developer, tester, designer, accessibility, scribe |
| PRF-04 | `accessibility` | researcher, lead, developer, tester, accessibility, designer, scribe |
| PRF-05 | `architecture` | researcher, lead, developer, tester, architect, azure-architect, cost-manager, scribe |
| PRF-06 | `azure` | researcher, lead, developer, tester, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, architect, cost-manager, security, modernizer, scribe |
| PRF-07 | `modernization` | researcher, lead, developer, tester, modernizer, architect, azure-architect, iac-author, cost-manager, asbuilt-author, scribe |
| PRF-08 | `compliance` | researcher, lead, developer, tester, security, supply-chain, vuln-manager, privacy, rai, accessibility, risk-manager, scribe |
| PRF-09 | `operations` | researcher, lead, developer, tester, azure-diagnose, performance, observability, asbuilt-author, iac-author, deployer, scribe |
| PRF-10 | `product` | researcher, lead, developer, tester, analyst, designer, product-owner, presenter, technical-writer, experimenter, data-scientist, intake-validator, scribe |
| PRF-11 | `full` | the full 32-role set, and **only** it — no opt-in pack roles |

| ID | Assertion |
|---|---|
| PRF-20 | Applying `power-platform` adds exactly `pp-architect` and `pp-connector`; `m365-copilot` adds exactly `m365-agent-architect` and `m365-agent-integrator`; `aws` adds exactly `aws-architect` and `aws-diagnose` |
| PRF-21 | `federation.md` records applied packs in `+pack` form, for example `azure +power-platform` |
| PRF-22 | Every seeded role has a non-empty `Deliverable Root`, and no two roles at different tiers share a root in a way that makes the Artifact Gate ambiguous |
| PRF-23 | Every seeded role's `Agent Name (Primary)` resolves to a delivered agent — the runtime counterpart of PKG-02 |

## Tier 1 — Federation

### Federation init

| ID | Assertion | Source |
|---|---|---|
| FD-01 | Federation root holds `federation.md`, `meta-routing.md`, `decisions.md`, `state.json`, and a `history/` directory | `squad-federation.instructions.md`, Federation State Layout |
| FD-02 | Each sub-squad root `.copilot-tracking/squad/members/<name>/` holds `team.md`, `routing.md`, `decisions.md`, `notifications.md`, `state.json`, `consumption.md`, `consumption-rates.md`, and `history/` | |
| FD-03 | `history/<sub-squad>.md` exists at the federation root for every registered sub-squad | |
| FD-04 | `federation.md` has columns `Sub-squad`, `Profile`, `Kind`, `Location`, `Owner`, `Description`; every `Kind` is `in-repo`; every `Location` equals `members/<Sub-squad>/` | Registry Schema |
| FD-05 | Every `Sub-squad` name is lower-kebab-case and unique | Sub-Squad Naming and Uniqueness |
| FD-06 | `meta-routing.md` has columns `Pattern / Domain`, `Sub-squad`, `Parallel-Eligible`; every `Sub-squad` value exists as a row in `federation.md` | Meta-Routing Schema |

### Promotion — single squad to federation

This is the highest-risk operation in the system because it moves state. Fixture: a squad with several turns of accumulated history, decisions, and deliverables. Take a full checksum manifest before promoting.

| ID | Assertion | Source |
|---|---|---|
| FD-10 | Precondition detection: promotion runs only when a top-level `team.md` exists and no top-level `federation.md` exists | Promotion Mode trigger |
| FD-11 | Nothing is written before the user confirms | "Nothing is moved or written before the user confirms" |
| FD-12 | After promotion the top-level `team.md` is **gone**, and the full tree is present under `members/<name>/` | Step 2 |
| FD-13 | **Every append-only file is byte-identical** to its pre-promotion checksum: `decisions.md`, every `history/<agent>.md`, every per-dispatch consumption block | Step 2, byte-for-byte guarantee |
| FD-14 | `team.md` is the **only** file whose content changed, and within it only the `Deliverable Root` column | Step 5 |
| FD-15 | Every `Deliverable Root` cell that began with `.copilot-tracking/` now reads `.copilot-tracking/squad/members/<name>/...` — the `.copilot-tracking/` segment is **replaced**, not prepended to. Cells beginning `docs/` or `outputs/` are unchanged | Step 5, disambiguated by `squad-roster.instructions.md`: a sub-squad roster reads `.copilot-tracking/squad/members/product/plans/` |
| FD-15a | **Strongest form.** Every rebased `Deliverable Root` cell resolves to a directory that actually exists on disk after promotion. This is the assertion that catches a literal prepend producing `.copilot-tracking/squad/members/<name>/.copilot-tracking/plans/` | See the source ambiguity noted below |
| FD-16 | Deliverable directories were enumerated **from disk**, not from the roster table: every directory under `.copilot-tracking/` except `squad/` was offered as a candidate | Step 3 |
| FD-17 | No source file was removed before its destination copy existed and verified — assert zero data loss by comparing the full manifest | Copy, Verify, Then Delete |
| FD-18 | Federation `decisions.md` first entry records the promotion and the source-to-destination move | Step 6 |
| FD-19 | `federation.md` has exactly one row, with `Location` = `members/<name>/` and `Profile` inferred from the moved `team.md` | Step 6 |
| FD-20 | `members/<name>/history/scribe.md` carries the promotion's orchestration consumption block, and federation `state.json` `currentRun` totals are seeded from the relocated ledger total row | Step 7 — the ledger must not show a gap across the boundary |
| FD-21 | After promotion, detection flips: `/squad-federation` owns turns and `/squad` detects the federation and defers | Detection precedence |

### Expansion

| ID | Assertion | Source |
|---|---|---|
| FD-30 | New sub-squad tree seeded at `members/<new>/` with the same file set as FD-02 | Expansion Step 2 |
| FD-31 | `federation.md` and `meta-routing.md` are **read-merge-written**: every pre-existing row and route is byte-identical afterward, with the new ones appended | Expansion Step 3, preserve-on-replace |
| FD-32 | Federation `decisions.md` gained an entry recording the addition; `history/<new>.md` created | Expansion Step 3 |
| FD-33 | **Negative case.** Adding a sub-squad whose name collides with an existing `members/<name>/` directory is refused | Naming and Uniqueness |

### Meta-routing turn

| ID | Assertion |
|---|---|
| FD-40 | A request routed to a sub-squad appends to federation `history/<sub-squad>.md` and to that sub-squad's own state under `members/<name>/`, with the full single-squad ordinary-turn contract (SQ-10 to SQ-19) holding at the sub-squad root |
| FD-41 | Federation-level state records the meta-routing decision; sub-squad state records the role dispatches. Neither is written into the other |
| FD-42 | A sub-squad's **inner run** reads and writes only inside its own root. It cannot discover another sub-squad's work on its own, and it does not read federation-level state | `squad-federation.instructions.md`, Cross-Sub-Squad Handoff |

## Tier 1 — Post-promotion functional continuity

FD-10 to FD-21 prove the *files* moved correctly. These prove the squad still **works** afterwards. Run the full single-squad contract again, rooted at `members/<name>/`, on a squad that was promoted rather than freshly seeded.

| ID | Assertion | Source |
|---|---|---|
| FD-60 | The entire single-squad ordinary-turn contract (SQ-10 to SQ-19) holds at `members/<name>/` after promotion, on a turn run post-promotion | Federation reuses every existing mechanism unchanged |
| FD-61 | The entire consumption-integrity contract (CON-01 to CON-44) holds at `members/<name>/` after promotion | Same |
| FD-62 | **The ledger spans the boundary.** `members/<name>/consumption.md` after promotion includes the roles dispatched **before** promotion. The pre-promotion history blocks must still aggregate into the post-promotion ledger | Promotion Step 7: "a recorded turn rather than a gap in the ledger" |
| FD-63 | Federation `state.json` `currentRun` cost totals are non-zero and equal the relocated ledger's total row — the federation must not report a zero-cost first turn | Promotion Step 7 |
| FD-64 | CON-32 still holds across the move: every row in the relocated `consumption.md` is re-derivable from the blocks in the relocated `history/*.md` | Ledger accumulation |
| FD-65 | A post-promotion dispatch writes its deliverable to the **rebased** root, not the old repository-root path | Deliverable Roots rebasing |
| FD-66 | **Escaped-root detection.** Force a role to write to the repository-root tracking path. The coordinator must treat that as a **failed stage** and re-dispatch with the rebased path stated explicitly | `squad-roster.instructions.md`: "has escaped its root" |
| FD-67 | The gates still fire post-promotion: run a council, a discovery, and an intake turn at `members/<name>/` and assert GATE-01 to GATE-08 hold there | Federation reuses mechanisms unchanged |
| FD-68 | `/squad-document` and `/squad-governance-report` scoped to the promoted sub-squad still produce their documented output, reading the relocated state | DOC and GOV contracts |
| FD-69 | Roster resolution still works: every `Agent Name (Primary)` in the relocated `team.md` resolves, and a dispatch succeeds through it | SQ-06 post-promotion |

## Tier 1 — Cross-Sub-Squad Handoff

A sub-squad **can** build on another's data, but only through a defined handoff. Isolation is write-side and discovery-side; reads happen only via paths the Federation Coordinator resolves and hands over. This group is where a silent divergence between two sub-squads would show up.

### The sanctioned path

| ID | Assertion | Source |
|---|---|---|
| FD-50 | A consumer sub-squad cannot discover a producer's artifact on its own — with no handoff, a `product` PRD at `members/product/plans/` is invisible to a run scoped to `members/azure/` | "cannot discover another's work on its own" |
| FD-51 | Federation `decisions.md` is **not** a discovery mechanism — the inner run does not consult it as a path index | Same |
| FD-52 | Only the Federation Coordinator sees both roots; it resolves the producer's artifacts and hands them to the consumer as **explicit read-only input paths** | "A consumer that was handed no paths was handed no dependency" |
| FD-53 | The handoff passes the producer's **artifacts**, not its state — the PRD, research, or plan file, with `decisions.md` and `history/` passed alongside as context only, never as a substitute | "The interface is the producer's artifacts, not its state" |
| FD-54 | Paths are resolved by reading the producer's `team.md` `Deliverable Root` cells, then **verified by listing** before being passed. Assert every handed path was enumerated this turn and exists | "A handoff path that this turn did not enumerate is a guess" |
| FD-55 | **Ordering.** The producer runs to completion — including its artifact gate — before the consumer is dispatched, and the pair is **never parallel-eligible**, even when meta-routing fans out to both | "Producer before consumer" |
| FD-56 | The fan-out proposal states the ordering to the user | Same |
| FD-57 | **Read-only across the boundary.** The consumer never writes into `members/<producer>/`, never edits a producer artifact, and never appends to a producer's logs. Checksum the producer's whole tree before and after the consumer's run | "Read-only across the boundary, always" |
| FD-58 | A consumer change implying an edit to a producer artifact is **routed back to the producer** as a request, not applied across the boundary | Same |
| FD-59 | **The handoff is recorded.** A federation-level `decisions.md` entry names the producer, the consumer, and the artifacts passed | "Record the handoff" |

### Missing-input recovery

The documented worst case is a consumer that re-derives requirements the producer never agreed, producing a plausible deliverable whose divergence is invisible in the output. These cases exist to make sure that cannot happen.

| ID | Assertion | Source |
|---|---|---|
| FD-70 | **Never re-derive.** With the producer's deliverable root empty, the consumer is **not** dispatched to work it out | "never falls back to re-derivation" |
| FD-71 | **Case 1 — producer registered but has not run.** The producer runs first, then the consumer resumes **in the same turn** once the artifact verifies on disk. The user does not re-issue the request | Recovery order, case 1 |
| FD-72 | An interactive turn states what will run and waits for a go-ahead; an autopilot or Watch Mode run proceeds without asking | Same |
| FD-73 | **Case 2 — artifact partial or stale.** Only the producing **stage** is re-dispatched inside the producer sub-squad, not the whole sub-squad, and the run says which artifact fell short and how | Recovery order, case 2 |
| FD-74 | **Case 3 — no sub-squad owns the artifact.** Federation Expansion is offered, or a user-supplied path accepted. The work is **not** routed to the consumer merely because it is the sub-squad in front of the coordinator | Recovery order, case 3 |
| FD-75 | **Case 4 — user override.** Proceeding with a gap records it as an explicit assumption in the `Ready-With-Gaps` shape, and the consumer's output carries a visible statement of what it assumed and who chose to proceed | Recovery order, case 4 |
| FD-76 | **Bounded loop.** One producer run per handoff per turn; a second consecutive miss on the same artifact escalates rather than looping | "Bound the loop" |
| FD-77 | Every producer run and re-dispatch during recovery is a normal Scribe-recorded stage with its own history entry **and consumption block** — recovery is never invisible in the ledger | Same; binds recovery to CON-09 |

## Tier 1 — Deliverable Root resolution

The `Deliverable Root` cell is the running value and the Artifact Gate's lookup key, so a wrong cell breaks proof-of-dispatch everywhere. A hand-edited cell is explicitly supported, which makes "does a manual edit actually take effect" a first-class case rather than an edge case.

| ID | Assertion | Source |
|---|---|---|
| DLR-01 | **`team.md` is the authority at dispatch time, not the catalog table.** The agent is handed the root read from the resolved roster row, and the Artifact Gate looks in that same cell | `squad-roster.instructions.md` |
| DLR-02 | **A hand-edited cell takes effect on the very next dispatch**, with no reseed and no other change. Edit a cell to a custom directory, dispatch that role, and assert the artifact lands there | "takes effect on the very next dispatch" |
| DLR-03 | The Artifact Gate looks for the artifact at the **edited** cell, so proof-of-dispatch still passes with a custom root | Same |
| DLR-04 | **Never normalized back.** A subsequent turn does not rewrite the edited cell to the catalog default | "never normalize a user-edited cell back to the default" |
| DLR-05 | **Not treated as drift.** No turn reports the divergence between the edited cell and the catalog table as something to repair | "never treat a divergence between the two as drift to repair" |
| DLR-06 | **Roster refresh preserves edits.** A refresh reseeds a `Deliverable Root` only for a role whose row it is **adding**; every pre-existing edited cell is byte-identical afterward | "A roster refresh preserves edited cells" |
| DLR-07 | A plain squad's roster resolves to `.copilot-tracking/plans/`; a sub-squad's resolves to `.copilot-tracking/squad/members/<name>/plans/` | "The table holds `squadRoot`-relative roots; `team.md` holds resolved ones" |
| DLR-08 | **Negative case.** A federation roster carrying a bare repository-root tracking path is a **seeding defect** and must be detected, not accepted | "is a seeding defect, not a variant" |
| DLR-09 | `docs/` and `outputs/` never take a sub-squad prefix, in a plain squad or a federation | "the two absolute exceptions" |
| DLR-10 | `outputs/` resolves relative to the project root regardless of which sub-squad ran | Same |

### Hand-edited roots across promotion

This is the intersection the user asked about, and it is the case most likely to break, because three separate promotion steps have to agree.

| ID | Assertion | Source |
|---|---|---|
| DLR-20 | Edit a role's `Deliverable Root` to a custom path under `.copilot-tracking/`, produce an artifact there, then promote. The custom directory is enumerated as a promotion candidate **from disk** — it is not in the catalog table, so a table-driven enumeration would miss it entirely | Promotion Step 3: "never from the table" |
| DLR-21 | The candidate list is confirmed with the user before anything moves | Step 3 |
| DLR-22 | The custom directory and its contents are relocated under `members/<name>/`, byte-for-byte | Step 4 |
| DLR-23 | The edited cell is rebased to point at the relocated custom directory — **not** normalized back to the catalog default | Step 5: "including a path the consumer edited by hand, so a customized root survives the promotion pointing at its own relocated directory" |
| DLR-24 | **The decisive assertion.** After promotion, the rebased edited cell resolves to a directory that exists and contains the pre-promotion artifact. Cell and disk must agree | Combines Steps 3, 4, and 5 |
| DLR-25 | A dispatch immediately after promotion writes to that rebased custom root | DLR-02 post-promotion |

### Source ambiguity worth resolving

Promotion Step 5 says to "prefix each `Deliverable Root` cell that begins with `.copilot-tracking/` with `.copilot-tracking/squad/members/<name>/`". Read literally, prefixing `.copilot-tracking/plans/` yields `.copilot-tracking/squad/members/<name>/.copilot-tracking/plans/`.

Step 4 moves that directory to `.copilot-tracking/squad/members/<name>/plans/`, and `squad-roster.instructions.md` states the resolved form plainly: "a sub-squad's roster reads `.copilot-tracking/squad/members/product/plans/`". So the intent is unambiguous — **replace** the leading `.copilot-tracking/` segment, do not prepend to it — but Step 5's wording does not say that, and a literal reading produces a path that does not exist.

FD-15a and DLR-24 are written to fail on the literal reading. Tightening Step 5's wording to match the roster instruction would remove the ambiguity at the source.

## Tier 1 — Squad Document

| ID | Assertion | Source |
|---|---|---|
| DOC-01 | With no `outputPath`, the file lands at `docs/squad-document-<YYYY-MM-DD>.<ext>` and the directory is created if absent | `squad-document.agent.md` |
| DOC-02 | Formats `md`, `html`, `pdf`, `docx` are accepted; an unrecognized value falls back to `md` **and the run says so** | |
| DOC-03 | When the `docx` toolchain is unavailable, the run falls back to `md` and says so rather than failing | |
| DOC-04 | The output carries an **Open Questions** section, valued `none` when there are none | |
| DOC-05 | **Squad state is unmodified.** Checksum every file under `.copilot-tracking/squad/` before and after; all must match | "Squad state is read-only input" |
| DOC-06 | No new dispatch history, decision, or consumption entry was written — this agent does not persist squad state | |
| DOC-07 | With `squad=<name>` in a federation, no file outside that sub-squad's root was read | Federation boundary |
| DOC-08 | The output path resolves to the local filesystem; a remote or URL target is refused | |

## Tier 1 — Governance Report

| ID | Assertion | Source |
|---|---|---|
| GOV-01 | With no `outputPath`, the file lands at `docs/squad-governance-report-<YYYY-MM-DD>.html` | `squad-governance-report.agent.md` |
| GOV-02 | The HTML contains all seven sections, in order, titled exactly: `1. Governance Gates`, `2. Council Verdicts`, `3. Cost Breakdown`, `4. Role Dispatch Activity`, `5. Risk & Compliance`, `6. Activity Timeline`, `7. Key Outcomes This Period` | |
| GOV-03 | The stats grid carries six metrics: Coordination Turns, Role Dispatches, Est. Cost, Total Tokens, Human Gates Fired, Escalations | |
| GOV-04 | **Empty-state, not omission.** Run against a squad with no council verdicts; section 2 must still render, with an empty-state message | |
| GOV-05 | **Self-contained.** No `src` or `href` resolving to an external origin, no CDN reference, no external JavaScript library | |
| GOV-06 | Squad state is unmodified — same checksum assertion as DOC-05 | |
| GOV-07 | Counts are grounded: the reported role-dispatch count equals the number of dispatch entries actually present across `history/*.md` | "Never invent data points, fabricate counts" |
| GOV-08 | When cost data includes uncalibrated turns, the cost figures are annotated with calibration state | |

## Tier 1 — Squad Learn

| ID | Assertion | Source |
|---|---|---|
| LRN-01 | The drafted entry uses the shipped schema columns: `id`, Scenario / Trigger, Learning / Rule, Scope / Applicability, Source Context, Date Added | `squad-learn.agent.md` |
| LRN-02 | **Sanitization.** Seed local memory with a fake secret, a fake customer name, an absolute path, and an internal URL. None may appear in the draft | Sanitization checklist |
| LRN-03 | `target=upstream` produces an `SL-` id and targets `squad-src/.github/skills/squad/learnings/shared-learnings.md`; `target=tenant` produces a `TL-` id and targets `squad-src/.github/skills/squad-learnings-tenant/tenant-learnings.md` | Target resolution |
| LRN-04 | The chosen id is the next free number, read from the existing rows | |
| LRN-05 | **Impactful-action gate.** With approval withheld, no fork, no push, and no pull request occurs. The run states exactly what it would do and to which repository, then stops | "Nothing is forked, pushed, or opened without explicit user approval" |
| LRN-06 | **Live memory is unmodified.** Checksum memory files before and after | |
| LRN-07 | The deployed `shared-learnings.md` in the consumer is never edited in place | |
| LRN-08 | **Negative case.** When sanitization cannot be confirmed, the run stops rather than proceeding | |

## Tier 1 — Gates

| ID | Assertion | Source |
|---|---|---|
| GATE-01 | A Discovery run appends `## Discovery Verdict <timestamp> <topic-id>` to `decisions.md` with fields `Topic`, `Opt-In`, `Depth`, `Roles Dispatched`, `Brief`, `Handoff`, and sections Framing, Options Considered, Objections, Riskiest Assumption, Open Questions, Discovery Gate | `squad-discovery-gate.instructions.md` |
| GATE-02 | The discovery brief exists at the `analyst` Deliverable Root named `<date>-<topic-id>-brief.md` | |
| GATE-03 | The gate never fires unprompted — a plain request with no opt-in produces no Discovery Verdict | "opt-in and additive" |
| GATE-04 | An Intake run appends `## Intake Readiness Verdict <timestamp> <topic-id>` with `Verdict` in `Ready`, `Ready-With-Gaps`, `Not-Ready`, a five-row Findings table (Completeness, Clarity, Testability, Consistency, Scope Boundaries), and an Intake Gate block | `squad-intake-gate.instructions.md` |
| GATE-05 | On `Not-Ready`, remediation runs and is capped at **two** cycles; a third cycle escalates instead | |
| GATE-06 | A Council run appends `## Council Verdict <timestamp> <topic-id>` with `Verdict` in `Go`, `Go-With-Conditions`, `Stop`, a Findings by Role table, a Synthesis block, and an Implementation Gate block | `squad-council.instructions.md` |
| GATE-07 | **Most-restrictive-wins.** Inject one `Block` from any single role; the Council Verdict must be `Stop` and `Permits Implementation Dispatch` must be `no` | |
| GATE-08 | **Most-restrictive-wins, softer label.** Inject a `Concern` carrying `Risk: High`; the verdict must still be `Stop` | Explicitly called out in the source |
| GATE-09 | Autopilot writes `history/autopilot-run-<id>.md` with `Topic`, `Opt-In`, `Cost Ceiling`, `Outcome`, and a Stages table | `squad-autopilot.instructions.md` |
| GATE-10 | **Impactful-Action Gate never proceeds unattended.** In an autopilot run, no `git push`, no merge, no deploy, no destructive data operation occurs without approval | |
| GATE-11 | Autonomous writes `history/autonomous-loop-<id>.md` with an Iterations table, and escalates on any `Stop`, any `Risk: High` from security, cost-manager, or rai, and on any irreversible write | `squad-autonomous.instructions.md` |
| GATE-12 | Notifications append to `notifications.md` with fields `Mode`, `Channel`, `Approval Ref`, `Topic`, `Awaiting`, `Resolved` | `squad-notifications.instructions.md` |

## Tier 2 — Semantic comparison

Advisory until the noise floor is measured. For the same fixture and the same request, compare the candidate run against a golden baseline captured from the last good release, and score:

* Did it route to the same roles?
* Did it produce the same deliverable types at the same roots?
* Did it fire the same gates with the same verdicts?
* Is the synthesized answer materially equivalent?

Report the score in the job summary. Promote to blocking only after enough runs to distinguish drift from ordinary variance.

## Intended deltas from `main` to `0.16.0`

Triage aid: a difference in this list is expected and is **not** a regression.

| Delta | Effect on the suite |
|---|---|
| `/squad-document`, `/squad-governance-report`, `/squad-learn` gain an `agent:` binding | PKG-05 and PKG-10 are new checks. DOC, GOV, and LRN cases must pass identically on both refs |
| Three new agents delivered: Squad Document, Squad Governance Report, Squad Learn | PKG-02 roster counts change |
| `squad-floor.instructions.md` added; root `AGENTS.md` removed | PKG-07 is a new check. The floor rules it carries were previously stated elsewhere, so behavioral cases must not change |
| `squad` SKILL.md split into a router plus reference files | PKG-03 is a new check. No behavioral case may change |
| Coordinators and Scribe converted to thin Skill Reference Contract agents | This is the change with the widest blast radius. Every Tier 1 case exists to prove it preserved behavior |
| PR #74's specialist-skill rule | SQ-24 is new; it must pass on `main` too, since #74 is already merged there |

## Determinism and cost controls

* **Pin the model** on every Tier 1 run. Results across runs are not comparable otherwise.
* **One automatic retry** before declaring a Tier 1 failure, with both attempts logged. Distinguishes flake from regression.
* **Fixtures stay small** — cost and runtime scale with fixture size.
* **Checksum manifests** before and after every read-only entrypoint case. This is the cheapest high-value assertion in the plan and it needs no judgement.
* **Timeouts and a concurrency group**, so a hung run cannot stall a release.
* Record the cost of the full suite in the job summary.

## Sequencing

1. Build Tier 0 and run it against `main`. It needs no secrets and no Copilot requests.
2. Build the Tier 1 fixtures and the Init and ordinary-turn cases (SQ-01 to SQ-19). Run against `main` until green — that is the baseline.
3. Add the consumption-integrity group (CON-01 to CON-44) next. Most of it is arithmetic over files already on disk, so it is nearly as deterministic as Tier 0 while catching a class of defect Tier 0 cannot see. CON-30 to CON-36 need a multi-turn fixture, so build that fixture once and reuse it.
4. Add routing and role selection (RTE) and profile seeding (PRF). PRF is cheap and fully deterministic after Init. RTE-30 to RTE-37 are the methodology cases and are the strongest evidence that the refactor preserved the squad's character.
5. Add the promotion, entrypoint, and gate cases. Promotion is the highest-value remaining group because it moves state.
6. Merge PR #70, then run the whole suite against `v0.16.0-pre`. Triage every difference against the intended-deltas table.
7. Wire the suite into the release workflow as a blocking job once it is green twice in a row.
