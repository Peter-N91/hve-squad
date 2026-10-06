---
description: "Squad roster schema and cast catalog mapping squad roles to deployed HVE Core agents"
applyTo: '**/.copilot-tracking/squad/**'
---

# Squad Roster Conventions

These conventions define the squad roster: the durable list of roles the Squad Coordinator can dispatch and the HVE Core agent that fills each role. The coordinator reads the roster at the start of every turn to decide who is available, how to invoke them, and which model tier to prefer.

The roster is data, not behavior. It records identities and invocation details. Routing logic lives in `squad-routing.instructions.md`, and persistence rules live in `squad-state.instructions.md`.

## Roster File

The roster lives at `.copilot-tracking/squad/team.md`. The coordinator creates it on first use from the cast catalog below and updates it only through the Squad Scribe.

The file begins with YAML frontmatter and a single H1 title, then a `## Members` table. Each row binds a squad role to a concrete agent.

### Members Schema

The `## Members` table uses these columns:

| Column               | Meaning                                                                                                                                                            |
|----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Role                 | The squad role name (for example, `lead`, `developer`, `tester`); roles may appear on more than one row when distinguished by `Member Name`                         |
| Member Name          | Optional display name for an individual squad member; required only when two rows share the same `Role` (see *Naming Conventions* below)                            |
| Agent Name (Primary) | The exact `name:` frontmatter value of the deployed HVE Core agent the role resolves to by default                                                                  |
| Alternate Agents     | Optional comma-separated `name:` values the role may resolve to instead, chosen per the row's `Selection Cue`                                                        |
| Selection Cue        | Short condition naming which Alternate applies; `—` when the role has none. Seeded from this catalog so dispatch is a lookup rather than a recollection            |
| Invocation           | How the coordinator dispatches the agent: `runSubagent`/`task` for non-user-facing roles                                                                            |
| Model Tier           | Preferred cost tier: `fast` for read-heavy roles, `default` for reasoning-heavy roles                                                                               |
| Model                | Present only under `routing=ranked` or `routing=manual`: the role's Model ID (a `consumption-rates.md` `Model ID`), a ranked readout or the user's pick             |
| Deliverable Root     | The directory this role writes its artifact into, resolved per *Deliverable Roots* below; makes the Artifact Gate a lookup rather than an inference                 |

Model Tier records a preference, not what actually ran, and it never becomes a model name. It is also the floor for any `Model` pick. The routing mode itself is the `Model routing: ranked|manual` line beneath the H1; no line means `off` and no `Model` column. Both are defined in the squad skill's `references/model-routing.md`, and a `Model` cell is a request passed at dispatch, never proof of what ran. The concrete model for each dispatch is *resolved* — from an operator declaration, then the dispatched agent's own `model:` frontmatter, then the session model — and captured in the per-dispatch consumption block in `history/<agent>.md` alongside the `model_source` rung that produced it, then aggregated into `consumption.md`, never into `team.md`. Two consequences matter when reading a ledger: an agent that pins `model:` in its frontmatter does not run on the operator's selected model even when its roster tier suggests otherwise, and an agent that pins nothing runs on the operator's model and must be priced at that model's rates rather than its tier's. See *Model Attribution* in `.github/instructions/squad/squad-state.instructions.md`.

The `Agent Name (Primary)` column holds exactly one agent; the role always has a deterministic default. `Alternate Agents` is optional and may be empty for one-to-one roles. `Selection Cue` carries the condition that picks an Alternate; it is seeded here rather than left to the catalog because the catalog is an `applyTo`-scoped instruction file and does not load on every host, while `team.md` is read on every turn. A roster written before this column existed simply has no cue, which resolves to the Primary. The uniqueness key for a row is the (`Role`, `Member Name`) pair, so two rows with the same `Role` are legal when their `Member Name` values differ. When `Member Name` is empty, only one row per `Role` is allowed and the coordinator dispatches that row whenever the role matches. The coordinator resolves the role to a single concrete agent at dispatch time using the *Resolving a Role to an Agent* rules below.

### Members Example

<!-- <example-roster> -->
```markdown
## Members

| Role          | Member Name | Agent Name (Primary)   | Alternate Agents                              | Selection Cue                                                             | Invocation         | Model Tier | Deliverable Root           |
|---------------|-------------|------------------------|-----------------------------------------------|---------------------------------------------------------------------------|--------------------|------------|----------------------------|
| lead          | Alpha       | Squad Lead             |                                               | —                                                                         | runSubagent / task | default    | .copilot-tracking/plans/   |
| developer     | Beta        | Squad Implementor      |                                               | —                                                                         | runSubagent / task | default    | .copilot-tracking/changes/ |
| developer     | Gamma       | Squad Implementor      |                                               | —                                                                         | runSubagent / task | default    | .copilot-tracking/changes/ |
| tester        | Delta       | Squad Reviewer         | Code Review Functional, Code Review Standards | correctness diff → Code Review Functional; conventions diff → Code Review Standards | runSubagent / task | fast       | .copilot-tracking/reviews/ |
| product-owner |             | Functional Planner     | Issue Triage Agent                            | single-issue triage → Issue Triage Agent                                  | runSubagent / task | default    | .copilot-tracking/plans/   |
| scribe        |             | Squad Scribe           |                                               | —                                                                         | runSubagent / task | fast       | (squad state)              |
```
<!-- </example-roster> -->

### Naming Conventions

The `Member Name` column gives each member a human-readable handle that survives across turns. Names are optional. When a row's `Member Name` is empty, the role is dispatched by role alone (the existing single-row-per-role behavior). When two or more rows share the same `Role`, every such row needs a unique `Member Name` so the coordinator can disambiguate at dispatch time via the user-supplied `owner=<Member Name>` hint.

The coordinator picks a name through one of four paths during Init Mode (see the Squad Coordinator's *Init Mode* propose phase):

1. The user supplies a name per member.
2. The coordinator assigns a deterministic alias from the wordlist below.
3. A mix of (1) and (2): the user names selected members; the coordinator fills the rest.
4. The user skips naming: every `Member Name` stays empty and the role-only behavior holds.

#### Deterministic Alias Wordlist

The coordinator picks aliases in order from this list, skipping any name already in use within the seeded roster. The list is intentionally small, ASCII-safe, and stable across runs so two squads seeded with the same profile receive the same default names.

```text
Alpha, Beta, Gamma, Delta, Epsilon, Zeta, Eta, Theta, Iota, Kappa, Lambda, Mu, Nu, Xi, Omicron, Pi, Rho, Sigma, Tau, Upsilon, Phi, Chi, Psi, Omega
```

When the seeded roster needs more than 24 names, the coordinator restarts the list and appends `-2`, `-3`, and so on (`Alpha-2`, `Beta-2`).

#### Naming in a Federation

A federation seeds several rosters in one build, so asking the four-part naming question once per sub-squad would be repetitive. The contract mirrors *Capture in a Federation* in `.github/instructions/squad/squad-notifications.instructions.md`: **ask the policy once, then apply it per sub-squad.**

1. **Ask once, at the federation level.** The Squad Federation Coordinator puts the naming question to the user exactly once per build — during Federation Init Phase 1, Promotion Phase 1, or Expansion Phase 1 — before any sub-squad is seeded. It is the same required question with the same wait-for-the-user gate the single-squad Init applies, and it is never resolved silently to "skip".
2. **What is captured is a policy, not a name list.** The answer is one of the four paths above, plus any per-role names the user supplied. Recording choice 4 (skip) is a decision the user made; never treat an unasked question as choice 4.
3. **Apply the policy to every sub-squad.** The federation coordinator passes the captured policy down with each sub-squad's Init, and the Squad Coordinator running with an inherited naming policy applies it rather than asking again.
4. **Names are scoped to one roster.** Uniqueness is the (`Role`, `Member Name`) pair *within* a single `team.md`, so two sub-squads may both carry an `Alpha`. Under choice 2 the alias wordlist restarts at the top for each sub-squad.
5. **A per-sub-squad override is allowed.** When the user wants different names for one sub-squad, capture them for that sub-squad only and leave the federation policy untouched.
6. **Promotion preserves what exists.** A promoted single squad's `team.md` already carries its `Member Name` column; relocation never renames a member. Ask the naming question only for sub-squads the promotion additionally creates.
7. **Unattended runs never ask.** A Watch Mode bootstrap has no user in the loop: it seeds the event sub-squad under the federation's captured policy, falling back to choice 4 (empty `Member Name`) when the federation has none. It never invents names and never blocks on a question it cannot ask.

## Cast Catalog

The full cast catalog is canonical in `references/roster-catalog.md`: the role-to-agent mapping for every catalog role, the registered External Cast of opt-in and bundled third-party resources (with the Verification Gate and the External Cast Blocklist), and the Building a Custom Roster role menu. Read it when casting a role for the first time, recasting after an HVE Core upgrade, applying or registering a pack's external agents, resolving an external role, or assembling a custom roster. This file stays canonical for the roster schema above, `### Dispatchability` and *Deliverable Roots* below, *Casting Rules*, and *Squad Profiles*/*Squad Packs*.

**Safety summary** — full procedure in `references/roster-catalog.md`'s *Verification Gate* and *External Cast Blocklist*: a role's backing resource is always in exactly one of three states — **bundled** (ships with the package and can never be absent), **registered opt-in and installed** (resolves like any local agent, subject to every rule in *Casting Rules*), or **registered opt-in and not installed** (an absent role). The coordinator never fetches, installs, or improvises a resource that has no registry row in the catalog; for an absent opt-in role it escalates with the install command and stops, naming the role, the registered resource, its exact `Install or Entry` value, and its `Prerequisites`, rather than seeding, substituting, or performing the work itself.

### Dispatchability

A role's Primary must be an agent the coordinator can actually reach. An agent is **dispatchable** through `runSubagent` or `task` only when its frontmatter does **not** set `disable-model-invocation: true`. HVE Core sets that flag on its user-invocable entry points, so those agents are reachable by a person typing their name and by nothing else.

* Never seed a `disable-model-invocation: true` agent as a Primary or an Alternate. A dispatch against one silently returns nothing, and a lighter model that receives nothing tends to fill the gap by doing the work inline — which is exactly the protocol violation *Dispatch Discipline* forbids.
* When the only agent that fits a role is user-invocable, the role is **thin charter needed**: either author a squad-owned charter that runs the same underlying skill, or escalate the step to the user so they invoke that agent themselves.
* The squad-owned charters `Squad Researcher`, `Squad Lead`, `Squad Implementor`, `Squad Reviewer`, `Squad Challenger`, `Squad Technical Writer`, `Squad Prompt Engineer`, `Squad Performance Planner`, `Squad Observability Planner`, and `Squad Vulnerability Manager` exist for exactly this reason. HVE Core moved research, planning, implementation, review, critique, documentation, prompt authoring, performance and SLO planning, telemetry vocabulary, and VEX management from agents to the `rpi-research`, `rpi-plan`, `rpi-implement`, `rpi-review`, `rpi-challenger`, `documentation`, `prompt-builder`, `performance-slo-planner`, `telemetry-foundations`, and `vex` skills; the charters are the dispatchable shells that run them.
* **A prompt is not dispatchable either, and a charter may wrap one.** A `.prompt.md` file is a user entry point that `runSubagent` cannot reach, but it is still deployed into the consumer's `.github/prompts/` as a pinned dependency. A charter may therefore *follow* a deployed prompt: it reads the file at dispatch time and executes its steps, rather than restating the workflow and letting the copy drift. Two rules make this safe. The charter must re-read the file each dispatch instead of working from memory, and it must escalate to the user with the slash command when the file is absent rather than improvising the workflow. `Squad Risk Manager` follows `risk-register.prompt.md`, and `Squad Azure Diagnose` follows `incident-response.prompt.md` for the phases beyond diagnosis. Where upstream promotion of a prompt to a skill would remove the file-path coupling, the charter says so, so the dependency is visible rather than silent.

#### Deferred Reviewer-Class Agents

Four HVE Core agents whose names end in *Reviewer* set `disable-model-invocation: true`, and every one was assessed for a charter rather than chartered by default. All four were **deferred**, and they stay listed here with the reason, following the same visible-deferral precedent as `devrel`.

The common finding is structural: each of the four is an **orchestrator**, not a capability. It profiles the codebase, dispatches assessor subagents, verifies their findings, and asks a report generator to collate them. Every one of those subagents is already dispatchable and already cast. A charter around the orchestrator would therefore duplicate the Squad Coordinator, which performs exactly that loop, rather than expose capability the squad cannot otherwise reach.

| Agent                   | Decision | Reason and the path that already covers it                                                                                                                                                                     |
|-------------------------|----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Accessibility Reviewer  | Deferred | The `accessibility` role reaches `Accessibility Framework Assessor` and `Accessibility Surface Inventory` directly, and `Report Generator` collates accessibility findings as well as security ones                 |
| RAI Reviewer            | Deferred | The `rai` role reaches `RAI Planner` and `RAI Skill Assessor` directly; the reviewer adds orchestration the coordinator already performs                                                                            |
| SSSC Reviewer           | Deferred | The `supply-chain` role reaches `SSSC Planner` and `Supply Chain Skill Assessor` directly. Its VEX pipeline modes are reached instead through `vuln-manager`, or escalated to the user as `/vex-scan` or `/vex-triage` |
| Privacy Reviewer        | Deferred | The `privacy` role reaches `Privacy Planner` directly. Unlike the other three this one has no dispatchable assessor beneath it, so a charter would have to reimplement the review rather than wrap it — which is the case for authoring a real capability later, not for a thin shell now. Diff-level privacy checks stay with `tester` |

A fifth reviewer-class orchestrator, previously covering the same supply-chain ground as SSSC Reviewer through the same two subagents, was removed outright from HVE Core at `8692fe38cc0415ff8d21aa1b5d8198f008cd4038` with no replacement agent. Its coverage was already fully absorbed by `SSSC Planner` and `Supply Chain Skill Assessor`, both still shipped and dispatchable, so its removal closes no gap and the roster needed no other change here.

Revisit a deferral when the squad has a concrete need the listed path cannot meet. Record the need before authoring the charter, so the roster does not accumulate shells nobody dispatches.

### Worker Agents Are Not Roles

Dispatchability is necessary but not sufficient. Some shipped agents are `user-invocable: false` — so `runSubagent` can reach them — yet still refuse a plain role dispatch, because they are **delegated workers** that validate a strict input contract before doing anything. `RPI Researcher` is the canonical case: it requires a cycle number, a wave type, one bounded lane, an exact lane artifact path, and a distinct **parent primary artifact path**, and it returns `Blocked` without writing when any of those is missing.

A worker like that can never be a role Primary or Alternate, because the coordinator dispatches roles with a role-scoped prompt, not with a delegated-input contract. Seeding one produces a role that blocks on every turn while looking installed and dispatchable.

* Only an agent that accepts a role-scoped prompt belongs in this catalog. When the capability is real but the agent demands a contract, the answer is a charter that owns the parent artifact and constructs that contract — which is what `Squad Researcher` does for `RPI Researcher`.
* A worker's required parent artifact is also the role's Deliverable Root. When the catalog assigns a role a Deliverable Root its Primary is contractually forbidden to write, the row is wrong. Treat that mismatch as the detection test for this class of error.

### Deliverable Roots

Each role writes its artifact into a fixed directory so the Artifact Gate in `.github/instructions/squad/squad-autopilot.instructions.md` is a path lookup rather than a per-run inference. The Scribe records the resolved root in the `Deliverable Root` column of `team.md` when it seeds the roster.

| Role                                              | Deliverable Root                                    |
|---------------------------------------------------|-----------------------------------------------------|
| researcher                                        | `.copilot-tracking/research/<date>/`                |
| lead                                              | `.copilot-tracking/plans/`                          |
| developer, iac-author, pp-connector, m365-agent-integrator | `.copilot-tracking/changes/`               |
| tester, challenger                                | `.copilot-tracking/reviews/`                        |
| qa-engineer                                       | `.copilot-tracking/qa/<date>/`                      |
| prompt-engineer                                   | `.copilot-tracking/prompts/`                        |
| security                                          | `.copilot-tracking/security-plans/`                 |
| rai                                               | `.copilot-tracking/rai-plans/`                      |
| privacy                                           | `.copilot-tracking/privacy-plans/`                  |
| accessibility                                     | `.copilot-tracking/accessibility/`                  |
| supply-chain                                      | `.copilot-tracking/sssc-plans/`                     |
| vuln-manager                                      | `.copilot-tracking/security/vex/`                   |
| performance                                       | `.copilot-tracking/performance-plans/`              |
| observability                                     | `.copilot-tracking/observability-plans/`            |
| release-engineer                                  | `.copilot-tracking/release-plans/`                  |
| risk-manager                                      | `docs/risks/`                                       |
| analyst, product-owner, designer, experimenter, modernizer | `.copilot-tracking/plans/`                 |
| data-scientist                                    | `outputs/`                                          |
| backlog-executor                                  | `.copilot-tracking/workitems/execution/<date>/` (ADO) or `.copilot-tracking/jira-issues/execution/<date>/` (Jira) |
| presenter                                         | `.copilot-tracking/ppt/<date>/<deck-slug>/`         |
| technical-writer                                  | `docs/`                                             |
| architect, azure-architect, aws-architect, pp-architect, m365-agent-architect | `docs/architecture/`     |
| scribe                                            | the squad root itself (state, not a deliverable)    |

**The discovery gate writes into an existing root rather than claiming a new one.** A discovery brief is written by `analyst` and therefore lands in the `analyst` root as `<date>-<topic-id>-brief.md`, which keeps the Artifact Gate a path lookup. The gate's other roles (`designer`, `challenger`, `experimenter`) return findings for the Discovery Verdict and write nothing during a discovery session, so one session produces one artifact rather than four.

**Some agents build their own output path, so the root must be passed as an argument rather than as context.** `presenter` is the clearest case: the `powerpoint` skill pipeline derives `<date>/<deck-slug>/` itself and takes the parent as an explicit output argument. Naming the roster cell in the dispatch prose is not enough — pass it as the pipeline's output path, or the agent composes its own and a hand-edited cell is silently ignored. Verify at the roster cell afterwards: an artifact found at the agent's default path instead is a failed dispatch to report, not a location to accept.

**A role absent from this table returns its findings to the coordinator rather than writing a standalone artifact, and that is the correct shape for it rather than a gap.** `cost-manager`, `deployer`, `fact-checker`, `intake-validator`, `asbuilt-author`, `azure-diagnose`, and `aws-diagnose` each hand a structured result back — an estimate, a deploy result, a verification verdict, an intake verdict, drafted as-built content, or a ranked hypothesis — and the durable record is either the Scribe's history entry or the artifact of the role that publishes it, usually `technical-writer`. The Artifact Gate therefore has nothing to look up for them, which is why the lookup table stays silent rather than naming a directory none of them writes. `qa-engineer` is a hybrid worth stating plainly: its test *code* lands in the project's existing test tree, and only its test plan and defect report land in the root above.

**In a federation, deliverable roots are rebased.** A sub-squad's `squadRoot` is `.copilot-tracking/squad/members/<name>/`, and every root in the table above is written relative to it — a `product` sub-squad's plan lands at `.copilot-tracking/squad/members/product/plans/`, and its deck at `.copilot-tracking/squad/members/product/ppt/<date>/<deck-slug>/`. Only `docs/` and `outputs/` stay at the repository root, because published documentation, architecture, and data-science artifacts are repository-wide outputs rather than per-sub-squad working state — and the notebook and dashboard agents resolve `outputs/` relative to the project root regardless of which squad ran them. A sub-squad that writes a deliverable to the repository-root tracking path has escaped its root; the coordinator treats that as a failed stage and re-dispatches with the rebased path stated explicitly.

**The table holds `squadRoot`-relative roots; `team.md` holds resolved ones.** Read every `.copilot-tracking/...` entry in the table above as `<squadRoot>/...` with the `.copilot-tracking/squad/` prefix elided for the default root, and `docs/` and `outputs/` as the two absolute exceptions that never take a prefix. The Scribe resolves each root against the `squadRoot` it was handed **at seed time** and writes the resolved path into the `Deliverable Root` column, so a sub-squad's roster reads `.copilot-tracking/squad/members/product/plans/` while a plain squad's reads `.copilot-tracking/plans/`. A federation roster seeded with the bare repository-root path is a seeding defect, not a variant: every role on it will write outside its own sub-squad.

**`team.md` is the authority at dispatch time, not this table.** The coordinator hands each dispatched agent the `Deliverable Root` read from the roster row it resolved, and the Artifact Gate looks for the artifact at that same cell. A root the user edited by hand therefore takes effect on the very next dispatch with no reseed and no other change: the table is the seed-time default, and the cell is the running value. Never re-derive a root from the table when the roster carries one, never normalize a user-edited cell back to the default, and never treat a divergence between the two as drift to repair — a consumer pointing a role at their own directory is the column working as intended. A roster refresh preserves edited cells; it reseeds a `Deliverable Root` only for a role whose row it is adding.

## Relationship Cardinality

The mapping deliberately supports three shapes so squad roles can stay human-meaningful while reusing the full HVE Core cast:

* **One-to-one** — a role maps to a single agent with no alternates. Examples: `privacy → Privacy Planner`, `experimenter → Experiment Designer`, `presenter → PowerPoint Subagent`.
* **One-to-many** — a role maps to a Primary plus Alternates, and the coordinator resolves to one agent per the Selection Cue. Examples: `product-owner` resolves across the PRD-to-work-item and single-issue-triage agents by request shape; `tester` resolves across the code-review perspective subagents by review sub-type; `aws-architect` resolves across three external agents by workload shape, which is the first time an *external* role carries Alternates rather than a lone Primary.
* **Many-to-one** — a single agent fills more than one role. Examples: `Codebase Profiler` serves `researcher` and `security`; `Finding Deep Verifier` serves `fact-checker` and `security`; `Meeting Analyst` serves `researcher` and `analyst`.

A shared agent is not a conflict: each role dispatches it with role-scoped context, and the Squad Scribe records which role invoked it under that role's history.

## Resolving a Role to an Agent

The coordinator turns a matched role into exactly one concrete agent at dispatch time:

1. **Default to the Primary agent** named in the role's `team.md` row (seeded from this catalog).
2. **Apply the Selection Cue** — when the request matches the cue in the row's `Selection Cue` cell, dispatch the indicated Alternate instead of the Primary. **A cue must be read, not recalled.** When the row carries no cue, the cue does not match, or this catalog did not load, dispatch the Primary: an alternate chosen because it sounds adjacent to the request swaps the role's methodology without saying so, which is how a research stage runs a transcript miner against a document that is not a transcript.
3. **Verify the agent is installed and dispatchable.** The resolved agent must be present in the project (its APM package deployed into `.github/agents/`) **and** must not set `disable-model-invocation: true`. Check both before dispatching, not after a silent no-op. When either check fails, escalate to the user — treat it the same as a **thin charter needed** role rather than silently substituting.
4. **Apply the external cast when the role is backed by a registered resource.** Follow *Resolving an External Role* in the *External Cast* section: a registered **opt-in** agent that is not installed is an absent role, and the escalation names the exact `Install or Entry` value from its row. A **bundled** resource ships with the package and cannot be absent; a missing one is a broken installation rather than an absent role.
5. **Record any non-primary resolution** through the Squad Scribe, so `history/<agent>.md` reflects the agent that actually ran and the cue that selected it.
6. **Never self-fill an absent role.** When the resolved agent is not installed, not dispatchable, or returns nothing, the coordinator stops and escalates to the user. It must not perform the role's work itself, and must not substitute a non-mapped agent to fill the gap. An absent role blocks the stage until the user installs the agent, names a substitute, or removes the role. A dispatch that returns nothing is an absent role, not an invitation to improvise.

## Casting Rules

* Use the exact `name:` frontmatter value from the deployed agent. Names with spaces are quoted when referenced from prompt or agent frontmatter.
* Prefer a deployed HVE Core agent (Primary or Alternate) over a new charter. Author a thin charter only when a required role has no reasonable **dispatchable** HVE Core fit.
* Prefer registering a third-party resource in the *External Cast* over copying it into this package. Vendoring a third-party file is an exception that needs a stated reason, not the default mechanism.
* Never name a `disable-model-invocation: true` agent as a Primary or an Alternate (see *Dispatchability*).
* Keep exactly one Primary per role so dispatch is always deterministic; list every other valid agent under Alternate Agents with a Selection Cue.
* Treat `fact-checker → Finding Deep Verifier` as a best-fit mapping: the agent verifies findings rather than performing general fact-checking, so confirm it suits the request before dispatch.
* Record any deviation from the catalog (a substituted agent, a non-primary resolution, or a new charter) through the Squad Scribe so the roster stays the single source of truth.
* **Re-validate the catalog against the deployed cast whenever the HVE Core dependency is upgraded.** Agent names move when upstream consolidates agents into skills; a roster row pointing at a name that no longer ships is indistinguishable at run time from a broken dispatch. The coordinator's Step 1 roster-resolution precheck is the runtime guard, but the catalog itself is the thing to correct.

## Squad Profiles

A squad profile is a named, project-tailored subset of the cast catalog. Profiles let a project choose the squad that fits its work instead of always seeding the full cast. The coordinator selects a profile during Init Mode (see the Squad Coordinator agent), and the Squad Scribe stamps the chosen profile's members into `team.md`.

The `scribe` role is always included in every profile — it owns every ordinary squad-state write after Cost Preflight and is never proposed as an optional member. The `intake-validator` role is seeded into the `product` and `full` profiles, where requirement and input artifacts are most central; other profiles can add it on demand, and when the conditional intake gate (`.github/instructions/squad/squad-intake-gate.instructions.md`) would fire in a squad that does not carry the role, the coordinator offers to add it rather than skipping the readiness check; when it cannot ask, it records the unassessed inputs as an open escalation and continues (see the intake gate).

The opt-in discovery gate (`.github/instructions/squad/squad-discovery-gate.instructions.md`) introduces **no role of its own**: it dispatches `analyst`, `designer`, `challenger`, and `experimenter`, which already own requirements authoring, facilitated ideation, pressure-testing, and hypothesis design respectively. It is therefore **offered only in `product` and `full`**, the two profiles whose rosters can run it — `analyst` writes the brief at every depth and no other profile seeds it. In every other profile the gate is silent rather than escalating, which is the deliberate difference from `intake-validator` above: an unvalidated input that exists is a skipped check worth interrupting for, while an unrequested brainstorm is not. `deep` additionally needs `challenger`, which only `full` seeds, so choosing it in a `product` squad prompts the coordinator to offer to add the role or to run `standard` instead.

Every profile also carries the **methodology spine**: `researcher`, `lead`, `developer`, and `tester` — the four roles that run the HVE Core delivery cycle of Research → Plan → Implement → Review. The spine guarantees that, whatever a project's specialization, the squad can always research a question, plan the work, implement the change, and review the result; each profile adds its specialist roles on top. A user may drop a spine role during Init Mode, but that disables the matching leg of the methodology and the Implementation Gate in `squad-routing.instructions.md` escalates if the removed role is later needed.

Some roles are **artifact-owning**: their `Deliverable Root` cell in `team.md` names a real path rather than `—` or `(squad state)`, so a dispatch is expected to leave a standalone artifact there. Read this from the roster, never from a list of role names — the cell is an operator declaration and a consumer may edit it. `researcher`, `lead`, and `tester` are artifact-owning too, but they own the Research, Plan, and Review stages rather than Implement, so the Implement stage's candidates are every other artifact-owning role, `developer` among them.

When the plan's deliverable list names **two or more Implement-stage candidates**, the work is a set of distinct artifacts rather than a single build, and autopilot fans its Implement stage out across the owning specialists instead of dispatching a single `developer` (see *Deliverable Fan-Out* in `squad-autopilot.instructions.md`). `product` is the canonical case — a requirements document, a refined backlog, a design study, an experiment design, a slide deck, written documentation, and a data notebook, owned by `analyst`, `product-owner`, `designer`, `experimenter`, `presenter`, `technical-writer`, and `data-scientist`. It is not the only one: an `azure` roster carries `azure-architect`, `iac-author`, `asbuilt-author`, `modernizer`, and `architect` alongside `developer`, and an architecture document, an IaC scaffold, and a migration sequence are as distinct from one another as a BRD is from a deck. A plan that names one candidate stays a single build, which leaves `default` and every simple run unchanged.

**Reading eligibility off a fixed list of role names was the defect this replaces.** A live `azure` run carried none of the seven `product` roles, was therefore classified as a single build, produced five specialist artifacts anyway, and improvised a fan-out the pipeline does not define — so none of the per-dispatch recording rules that the fan-out path carries applied to it. It reported ten stages and left no `history/<agent>.md` behind any of them.

The narrower term **deliverable-producing role** — `analyst`, `product-owner`, `designer`, `experimenter`, `presenter`, `technical-writer`, `data-scientist` — survives, and now names one thing only: the roles whose output the *Implementation Gate* treats as the turn's substantive output alongside `developer`. It no longer decides the Implement stage's shape, because a role list cannot see a roster it was not written for.

| Profile         | Members (roles)                                                                                                                                | Choose when the project is…                                              |
|-----------------|------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------|
| `default`       | researcher, lead, developer, tester, scribe                                                                                                    | General build and delivery work — a balanced team (recommended default)  |
| `full`          | researcher, lead, developer, tester, challenger, architect, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, security, supply-chain, vuln-manager, rai, privacy, accessibility, risk-manager, performance, observability, designer, fact-checker, cost-manager, modernizer, prompt-engineer, analyst, product-owner, presenter, technical-writer, experimenter, data-scientist, intake-validator, scribe | You want every deployed capability available except the opt-in roles     |
| `security`      | researcher, lead, developer, tester, security, supply-chain, rai, privacy, fact-checker, scribe                                                | Security-, supply-chain-, threat-, privacy-, or responsible-AI-focused (auth, secrets, ML, LLM, personal data) |
| `design`        | researcher, lead, developer, tester, designer, accessibility, scribe                                                                           | UX/UI or product-design focused, with accessibility alongside            |
| `accessibility` | researcher, lead, developer, tester, accessibility, designer, scribe                                                                           | Accessibility conformance is the goal itself — WCAG 2.2, Section 508, or EN 301 549 assessment and remediation |
| `architecture`  | researcher, lead, developer, tester, architect, azure-architect, cost-manager, scribe                                                          | System design, infrastructure, or architecture-review focused            |
| `azure`         | researcher, lead, developer, tester, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, architect, cost-manager, security, modernizer, scribe                                    | Azure-focused build with budget and security oversight (Bicep, landing-zone, FinOps signals) |
| `modernization` | researcher, lead, developer, tester, modernizer, architect, azure-architect, iac-author, cost-manager, asbuilt-author, scribe                  | Legacy uplift — framework or dependency upgrades, re-platforming, SQL or cloud migration |
| `compliance`    | researcher, lead, developer, tester, security, supply-chain, vuln-manager, privacy, rai, accessibility, risk-manager, scribe                   | Conformance evidence is the goal — an audit, an attestation, or a customer questionnaire that needs privacy, accessibility, responsible-AI, supply-chain, and vulnerability answers together |
| `operations`    | researcher, lead, developer, tester, azure-diagnose, performance, observability, asbuilt-author, iac-author, deployer, scribe                  | Running and keeping a deployed system healthy — incident response, reliability targets, instrumentation design, and as-built documentation |
| `product`       | researcher, lead, developer, tester, analyst, designer, product-owner, presenter, technical-writer, experimenter, data-scientist, intake-validator, scribe                       | Business discovery and delivery — requirements, design thinking, roadmap, and stakeholder deliverables (often non-technical) |

### Profile Selection

The coordinator chooses a profile in this order of precedence:

1. **Explicit choice** — the user names a profile (for example, `profile=security`) or confirms one during Init Mode.
2. **Project discovery** — the coordinator infers a profile from repository signals when the user does not name one:
   * Source files, tests, and package manifests with no specialized signal → `default`.
   * Authentication, secrets, threat modeling, ML/LLM, or data-handling signals → `security`.
   * Frontend frameworks (React, Vue, Svelte, Angular) or CSS with no explicit conformance signal → `design`.
   * WCAG, ARIA, Section 508, EN 301 549, VPAT, or an existing `.copilot-tracking/accessibility/` tree → `accessibility`.
   * Bicep templates plus budget, pricing, FinOps, or `cost-manager` signals (or `.bicep` files alongside an Azure landing-zone reference) → `azure`.
   * End-of-life runtimes or frameworks, pinned-back dependency manifests, `.NET Framework` or legacy Java projects, or migration and re-platforming documents → `modernization`.
   * Audit, attestation, conformance-questionnaire, or regulatory documents, or an existing `docs/risks/` tree alongside privacy or accessibility tracking artifacts → `compliance`.
   * Runbooks, incident or postmortem records, SLO or error-budget documents, dashboards-as-code, or an OpenTelemetry collector configuration → `operations`.
   * Infrastructure-as-code (Bicep, Terraform without Azure-specific cost signals), system-design docs, or component diagrams → `architecture`.
   * Requirements documents (BRD/PRD), product or roadmap docs, discovery/design-thinking artifacts, or a repository with little or no source code where the work is business discovery and delivery → `product`.
   * Mixed or unclear signals → propose `default` and offer `full`.
3. **Fallback** — when discovery is inconclusive and the user gives no hint, propose `default` as the recommended profile.

A profile only ever lists roles that exist in the cast catalog. A role with no dispatchable Primary — currently `devrel`, `networking`, `gcp`, and `identity`, none of which has a backing skill either — is never part of a profile until a resource exists that a charter could wrap.

**Packs are selected alongside the profile, never instead of it** (see *Squad Packs* below). An explicit `pack=` hint wins; otherwise the coordinator proposes a pack from either of two signals. The first is the repository: for `power-platform`, a `.cdsproj` or `solution.xml`, a `pac` CLI configuration, a canvas app `.msapp`, or a Dataverse solution folder; for `m365-copilot`, a `declarativeAgent.json` or `manifest.json` Copilot agent manifest, an `m365agents.yml` or `teamsapp.yml`, an `appPackage/` folder, or a `main.tsp` importing `@microsoft/typespec-m365-copilot`; for `aws`, a `template.yaml` with `AWS::Serverless` transforms or any CloudFormation template, a `cdk.json`, a `samconfig.toml`, a `serverless.yml`, an `.aws/` configuration directory, or Terraform declaring the `hashicorp/aws` provider. The second is the **request itself** — a user who asks to build a Power Automate approvals flow into an empty repository has told the coordinator the domain before a single file exists, and waiting for disk evidence that will not arrive until after the work starts would be perverse. Either signal is enough to propose; neither is enough to apply. The coordinator presents the profile and any proposed packs together for a single confirmation, so the user never answers two questions where one will do. A proposed pack whose external resources are not installed is presented with its install commands rather than seeded.

### Opt-In Roles

An **opt-in role** is a catalog role that no profile seeds, not even `full`. It is selectable in a custom roster; it simply never arrives by default. A role becomes opt-in for one of two reasons, and the reason changes what the coordinator says when the role is missing.

**Reason one: its work writes somewhere the user may not expect a squad to reach.** `backlog-executor` is the only role in this class today. It writes into a live Azure DevOps or Jira backlog, where a create is announced to a whole team by notifications, subscriptions, and webhooks the moment it lands. Arriving in a seeded roster would make that reach a surprise, so the role is added deliberately or not at all. The role is fully dispatchable the whole time; only its seeding is withheld.

**Reason two: its Primary is a registered opt-in external resource that is absent until the consumer installs it.** `qa-engineer`, `release-engineer`, `aws-architect`, `aws-diagnose`, and every pack role (`pp-architect`, `pp-connector`, `m365-agent-architect`, `m365-agent-integrator`) are in this class. These roles are opt-in by construction rather than by policy: *Resolving an External Role* already forbids seeding a registered-but-uninstalled role, so no profile could carry them honestly even if it wanted to. This is also why the rule that `full` contains every non-opt-in role stays true while `full` carries none of them.

An opt-in role is offered on demand rather than hidden. When a request matches an opt-in role's routing pattern in a squad that does not carry it, the coordinator escalates and **proposes adding the role** — naming what it would be able to write and to which project, and, for a reason-two role, naming the exact `Install or Entry` command from its registry row together with its `Prerequisites` — instead of silently declining or falling back to a role that cannot do the work. This is the same offer the coordinator makes for `intake-validator` when the intake gate fires in a squad without it. On acceptance the Squad Scribe appends the role to `team.md` and its routing rows to `routing.md`, and the turn continues; on decline the coordinator reports what it cannot do rather than substituting.

Adding an opt-in role is a roster change like any other: it persists for the project until the user removes it, and the Scribe records the addition so the roster stays the single source of truth. For a reason-two role the resource must be present first; a roster never advertises capability the project has not installed.

### Squad Packs

A **pack** is a named, additive set of catalog roles layered onto a profile. A profile answers *what kind of work is this*; a pack answers *what is it built on*. Technology verticals arrive as packs, because a profile is single-choice while a domain is not mutually exclusive with a concern — a Power Platform project can need `compliance` evidence exactly as easily as a general build can.

A pack is not a replacement for a custom roster, it is the maintained version of one. A custom roster is assembled by hand, dies with the project, and is discoverable by nobody; a pack is written down once, named, and reusable across every profile.

#### Profile or Pack

Three tests decide which shape a new member set takes, and for everything currently in the catalog all three agree:

| Test                                                                    | Profile                                          | Pack                                      | Federation                                        |
|-------------------------------------------------------------------------|--------------------------------------------------|-------------------------------------------|---------------------------------------------------|
| **Self-sufficiency** — does the set carry the methodology spine and deliver alone? | Yes                                    | No, it is specialists only                | Yes, once per sub-squad — the spine is duplicated |
| **Exclusivity** — is choosing two at once incoherent?                    | Yes, one dominant team shape wins                | No, two can sensibly apply together       | No, but each runs its own turns                   |
| **Question answered**                                                    | "What kind of work is this?" — a mode or concern | "What is it built on?" — a technology domain | "Who owns this stream of work?" — a separate team |

`azure` and `modernization` sit closest to the line and stay profiles by decision rather than by oversight: this repository's work is intrinsically Azure- and modernization-shaped, so each behaves as the dominant team shape rather than as an addition to one. The tests govern **new** capability from here on.

#### Pack or Federation

A pack and a federation both add capability a single profile does not carry, so the two get confused. They solve different problems, and one rule separates them:

> **One piece of work that needs extra expertise is a profile plus a pack.** Those roles must share a plan, a council, and a review.
> **Two streams of work with separate deliverables and owners is a federation.** Those teams need coordination, not the same room.

The reason is mechanical rather than stylistic. A pack composes *within* one roster: `pp-architect` and `privacy` are dispatched in the same turn against the same request, and both findings land in one Council Verdict, one plan, and one review. A federation coordinates *between* rosters: each `members/<name>/` is a complete squad with its own `team.md`, `decisions.md`, `history/`, and consumption ledger, and meta-routing decides which sub-squad owns a turn. Split one piece of work across two sub-squads and its two halves are decided in two councils that never met.

Federation also does not remove the need for a pack — it multiplies it. A sub-squad is seeded from a profile, and a technology vertical reaches that sub-squad the same way it reaches any roster: by applying the pack to it. There is no path from federation to `pp-architect` that does not go through `power-platform`.

A compliance-plus-Power-Platform project is therefore `profile=compliance pack=power-platform`, not two sub-squads, because compliance is a lens on the work rather than a stream of it. Two sub-squads earn their keep when there really are two products — a Power Platform app and an Azure data platform, different owners, shipping separately — and the first of those still carries the pack. See `.github/instructions/squad/squad-federation.instructions.md` for the federation mechanics.

#### Composition Rules

* **A pack selects catalog roles; it never defines them.** Every role a pack names already exists in the *Cast Catalog* with exactly one Primary, so two packs naming the same role produce a deduplicated union rather than a conflict, and the role is seeded once.
* **A pack never introduces a role that duplicates work an existing role already owns.** Check the catalog first and widen the existing role instead — the same rule that gave the incident lifecycle to `azure-diagnose` rather than to a second `sre` role. Two roles claiming one phase is worse than a missing role, and that stays true across packs.
* **Exactly one profile, zero or more packs.** A pack is never chosen *instead of* a profile, because a pack carries no methodology spine and cannot research, plan, implement, and review on its own.
* **A pack's roles obey every rule a profile's roles obey.** In particular, a role whose registered external resource is not installed is offered with its `Install or Entry` command rather than seeded, per *Building a Custom Roster* below.
* **The Scribe records the roster's provenance when it seeds.** A roster is a profile plus zero or more packs, or `custom`, and that is written into the Init decision in `decisions.md`; in a federation it is also the `Profile` column of the `federation.md` registry, in `azure +power-platform` form. A pack applied later is recorded the same way, as a decision, exactly like an added opt-in role.
* **A pack can be applied to a roster that already exists**, and it is offered rather than assumed. When a request matches the routing pattern of a role that belongs to a registered pack the roster does not carry — or names the pack's domain plainly, which is the same signal arriving in words rather than keywords — the coordinator escalates and proposes applying the pack, naming its roles, what they would add, and the install command for any registered resource that is not yet present. This is the same offer the coordinator already makes for `intake-validator` and for an opt-in role, one level up: a group of roles instead of one. On acceptance the Scribe appends the pack's roles to `team.md`, their rows to `routing.md`, and a decision recording the applied pack; on decline the coordinator reports what it cannot do rather than substituting a role that cannot do the work.

#### Removing a Pack

A pack is removable, and removing one is a roster change like any other rather than a special operation. A user who no longer works on a vertical should not carry its roles, its routing rows, or its context.

Removal is safe for the record because of how squad state is already split. `decisions.md` and `history/<agent>.md` are **append-only**: removing a pack appends a new decision and edits nothing, and every dispatch a removed role ever ran stays in its history file. `team.md` and `routing.md` use replace semantics, so their rows come out cleanly. Nothing that happened is unwritten.

Four rules keep a removal honest:

* **Remove only what the pack still owns.** Drop a role only when the pack contributed it *and* nothing else on the roster does — not the base profile, not another applied pack, and not the user's own hand-added row. A role two packs share survives the removal of one of them, which is the same deduplication that applied when the packs were added, run in reverse.
* **Keep the spend visible.** `consumption.md` mirrors roster order and recomputes the run total, so silently dropping a removed member's row would understate what the project actually spent. Keep the row and mark it removed; the run total stays truthful and the per-dispatch blocks in `history/<agent>.md` remain the durable evidence behind it.
* **Leave the work where it is.** Deliverables a removed role already wrote stay on disk. Removing a role withdraws it from future dispatch; it does not retract what it produced.
* **Removal is not an uninstall.** The pack's registered external resources stay installed and stay registered in the *External Cast*. Re-applying the pack later reseeds the roles with no reinstall, and a consumer who wants the disk space back uninstalls the resource deliberately, as a separate act.

Removing a single role follows the same four rules. A pack is only the convenient way to name several at once.

#### Registered Packs

| Pack             | Adds (roles)               | Choose when the project is…                                                                          | Arrival                                                                                                       |
|------------------|----------------------------|-------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------|
| `power-platform` | pp-architect, pp-connector | Built on Power Platform — Power Apps, Power Automate, Dataverse, Power Pages, or Copilot Studio        | Opt-in. Both roles rest on registered external agents; the install commands are in *Registered External Cast* |
| `m365-copilot`   | m365-agent-architect, m365-agent-integrator | Built on Microsoft 365 Copilot — declarative agents, TypeSpec agent definitions, API plugins, MCP-backed agents, or Microsoft Graph integration | Opt-in. Both roles rest on registered external agents; the install commands are in *Registered External Cast* |
| `aws`            | aws-architect, aws-diagnose | Built on AWS — Lambda and serverless, ECS or EKS, CDK, SAM, CloudFormation, Organizations and landing zones, or a live AWS workload to triage | Opt-in. Both roles rest on registered external agents; the install commands are in *Registered External Cast* |

**AWS is a pack while `azure` is a profile, and that asymmetry is deliberate.** `azure` predates the pack mechanism and stays a profile by the decision recorded in *Profile or Pack*: this repository's work is intrinsically Azure-shaped, so an Azure squad behaves as the dominant team shape rather than as an addition to one. AWS is new capability, so the three tests govern it, and all three say pack — it carries no methodology spine, it is not incoherent alongside any profile, and it answers "what is it built on". The practical consequence is the one the tests intend: a multi-cloud project takes `profile=azure` plus `pack=aws` and gets both, where two competing profiles would have forced a false choice. An AWS-only project takes whichever profile matches its *work* — usually `architecture` or `default` — plus the pack. Carrying the `aws` pack says the squad can reason about AWS; it does not imply general multi-cloud capability, and it says nothing at all about Google Cloud, which has no coverage anywhere (see the `gcp` row in the *Cast Catalog*).

**Worked pairings.** The profile is chosen from the shape of the work and the pack from the technology, so the same pack appears against several profiles. These are illustrations rather than an allowlist — any pack composes with any profile:

| Situation                                                       | Profile        | Pack                          |
|-----------------------------------------------------------------|----------------|-------------------------------|
| Greenfield Power Platform app                                    | `default`      | `power-platform`              |
| Power Platform app that has to produce audit evidence            | `compliance`   | `power-platform`              |
| Designing an AWS workload before anything is built               | `architecture` | `aws`                         |
| One estate spanning Azure and AWS                                | `azure`        | `aws`                         |
| On call for a live AWS workload                                  | `operations`   | `aws`                         |
| A Microsoft 365 Copilot agent that handles personal data         | `security`     | `m365-copilot`                |
| A Power Platform solution fronted by an M365 Copilot agent       | `default`      | `power-platform`, `m365-copilot` |

The `operations` plus `aws` row is the case a profile could never have served: `operations` already carries `azure-diagnose`, and the pack adds `aws-diagnose` beside it, so one squad triages both clouds. The last row is the case a profile could not have served either, because two verticals apply at once and a profile is single-choice.

Power BI is deliberately absent from the `power-platform` pack. Its upstream agents serve analytics modeling and report performance rather than Power Platform application delivery, so they belong with the data and analytics vertical, which is registered against `data-scientist` rather than as a pack of its own.

**Two adjacent Microsoft verticals were assessed and deliberately produced no pack.** Data and Power BI, and AI application engineering, both reached the verification gate with no agent surviving it: the four `power-bi-*-expert` agents fail gate step 3, and every AI-engineering candidate duplicates capability HVE Core already deploys. A pack selects roles, and a role needs a dispatchable Primary, so inventing one would have meant authoring a squad charter purely to make a pack exist — and in the AI-engineering case that charter would have claimed work `developer` already owns. Both verticals are therefore registered as skills against widened existing roles, and their surviving resources are listed in *Registered External Cast*. Revisit the pack shape only when an upstream agent in either domain passes the gate.

There is no Power Platform ALM or solution-deployment role. No verified resource can perform a solution import, and a role with no resource behind it is aspirational rather than dispatchable. ALM *planning* — environment strategy, solution segmentation, managed versus unmanaged, pipeline design — sits with `pp-architect`, which advises and never executes. Should an ALM writing role ever be added, it inherits both existing write postures rather than a default: opt-in like `backlog-executor`, because a solution import is announced to everyone in the target environment the moment it lands, and preview-first like `deployer`, because the import itself is not cleanly reversible.

