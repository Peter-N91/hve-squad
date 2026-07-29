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
| Alternate Agents     | Optional comma-separated `name:` values the role may resolve to instead, chosen per the catalog cue                                                                 |
| Invocation           | How the coordinator dispatches the agent: `runSubagent`/`task` for non-user-facing roles                                                                            |
| Model Tier           | Preferred cost tier: `fast` for read-heavy roles, `default` for reasoning-heavy roles                                                                               |
| Deliverable Root     | The directory this role writes its artifact into, resolved per *Deliverable Roots* below; makes the Artifact Gate a lookup rather than an inference                 |

Model Tier records a preference, not what actually ran, and it never becomes a model name. The concrete model for each dispatch is *resolved* — from an operator declaration, then the dispatched agent's own `model:` frontmatter, then the session model — and captured in the per-dispatch consumption block in `history/<agent>.md` alongside the `model_source` rung that produced it, then aggregated into `consumption.md`, never into `team.md`. Two consequences matter when reading a ledger: an agent that pins `model:` in its frontmatter does not run on the operator's selected model even when its roster tier suggests otherwise, and an agent that pins nothing runs on the operator's model and must be priced at that model's rates rather than its tier's. See *Model Attribution* in `.github/instructions/squad/squad-state.instructions.md`.

The `Agent Name (Primary)` column holds exactly one agent; the role always has a deterministic default. `Alternate Agents` is optional and may be empty for one-to-one roles. The uniqueness key for a row is the (`Role`, `Member Name`) pair, so two rows with the same `Role` are legal when their `Member Name` values differ. When `Member Name` is empty, only one row per `Role` is allowed and the coordinator dispatches that row whenever the role matches. The coordinator resolves the role to a single concrete agent at dispatch time using the *Resolving a Role to an Agent* rules below.

### Members Example

<!-- <example-roster> -->
```markdown
## Members

| Role          | Member Name | Agent Name (Primary)   | Alternate Agents                                       | Invocation         | Model Tier | Deliverable Root           |
|---------------|-------------|------------------------|--------------------------------------------------------|--------------------|------------|----------------------------|
| lead          | Alpha       | Squad Lead             | RPI Planner                                            | runSubagent / task | default    | .copilot-tracking/plans/   |
| developer     | Beta        | Squad Implementor      |                                                        | runSubagent / task | default    | .copilot-tracking/changes/ |
| developer     | Gamma       | Squad Implementor      |                                                        | runSubagent / task | default    | .copilot-tracking/changes/ |
| tester        | Delta       | Squad Reviewer         | Code Review Functional, Code Review Standards          | runSubagent / task | fast       | .copilot-tracking/reviews/ |
| product-owner |             | GitHub Backlog Manager | Issue Triage Agent, Agile Coach, Product Manager Advisor | runSubagent / task | default  | .copilot-tracking/plans/   |
| scribe        |             | Squad Scribe           |                                                        | runSubagent / task | fast       | (squad state)              |
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

The cast catalog is the default casting source and the canonical mapping between squad roles (members) and deployed HVE Core agents, keyed by each agent's exact `name:` frontmatter value. When a project has no `team.md`, the coordinator seeds the roster from this catalog.

The relationship between roles and agents is **many-to-many**. A role names one **Primary** agent — the default the coordinator dispatches — plus optional **Alternate** agents it may resolve to instead when the request matches a **Selection Cue**. A single agent may also fill more than one role (for example, `Codebase Profiler` serves both `researcher` and `security`). See *Relationship Cardinality* below.

Roles that have no stable HVE Core equivalent are marked **thin charter needed**. A thin charter is a small, squad-owned subagent authored under `squad-src/.github/agents/squad/` when the role is actually required; until then the coordinator omits the role or escalates to the user.

Every Primary in this catalog is **dispatchable** (see *Dispatchability* below). Agents that HVE Core ships as user-invocable orchestrators — `PowerPoint Builder`, `ADO Backlog Manager`, `Jira Backlog Manager`, `Code Review`, `Documentation`, `RPI Agent`, `Security Reviewer`, `Network ISA-95 Planner`, and the other `disable-model-invocation: true` entry points — are never a Primary and never an Alternate, because `runSubagent` and `task` cannot reach them. Where HVE Core moved a capability from an agent to a skill (research, planning, implementation, review, documentation), the squad dispatches a thin charter that runs that skill.

| Role             | Primary Agent (`name:`)       | Alternate Agents (`name:`)                                                                                          | Selection Cue                                                                                                                                                                                                 |
|------------------|-------------------------------|---------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| lead             | Squad Lead                    | RPI Planner                                                                                                         | Revise one numbered phase inside an existing plan artifact → RPI Planner; otherwise author the plan and enumerate the run's deliverables → Squad Lead (squad-owned charter running the `rpi-plan` skill)      |
| researcher       | Squad Researcher              | Codebase Profiler, Meeting Analyst                                                                                  | Technology-profile scan → Codebase Profiler; meeting-transcript mining → Meeting Analyst; otherwise own the primary research artifact and delegate bounded lanes → Squad Researcher (squad-owned charter running the `rpi-research` skill). `RPI Researcher` is a delegated lane worker and never a roster entry — see *Worker Agents Are Not Roles* |
| developer        | Squad Implementor             | —                                                                                                                   | Squad-owned charter running the `rpi-implement` skill; writes the change record under `.copilot-tracking/changes/` and stops at every impactful action                                                         |
| tester           | Squad Reviewer                | Code Review Functional, Code Review Standards, Code Review Security, Code Review Accessibility, Code Review Readiness, Code Review PR | Correctness/edge-case diff → Code Review Functional; standards diff → Code Review Standards; security diff → Code Review Security; accessibility diff → Code Review Accessibility; PR deliverable readiness → Code Review Readiness; pull-request walkthrough → Code Review PR; otherwise implementation-versus-plan review → Squad Reviewer |
| challenger       | Squad Challenger              | —                                                                                                                   | Squad-owned charter running the `rpi-challenger` and `rpi-plan-critique` skills; pressure-tests plans, proposals, and assumptions, and checks a plan against the research it rests on (the capability the retired `Plan Validator` used to provide)                    |
| architect        | System Architecture Reviewer  | ADR Creator                                                                                                         | Decision record → ADR Creator; otherwise design-tradeoff and well-architected review → System Architecture Reviewer                                                                                            |
| security         | Security Planner              | SSSC Planner, Skill Assessor, Supply Chain Skill Assessor, Finding Deep Verifier, Report Generator, Dependency Reviewer, Codebase Profiler | Supply-chain posture → SSSC Planner; single security-skill assessment → Skill Assessor; supply-chain skill assessment → Supply Chain Skill Assessor; verify a finding → Finding Deep Verifier; compile vulnerability report → Report Generator; dependency-change review → Dependency Reviewer; tech profiling → Codebase Profiler; otherwise security planning → Security Planner |
| rai              | RAI Planner                   | RAI Skill Assessor                                                                                                  | Single-framework assessment against the codebase → RAI Skill Assessor; otherwise responsible-AI assessment and planning → RAI Planner                                                                          |
| privacy          | Privacy Planner               | —                                                                                                                   | Single agent — data maps, DPIA thresholds, and privacy controls for a processing activity                                                                                                                     |
| fact-checker     | Finding Deep Verifier         | —                                                                                                                   | Verification-focused (confirms FAIL/PARTIAL findings); confirm fit before dispatch                                                                                                                            |
| designer         | UX UI Designer                | DT Coach, DT Learning Tutor                                                                                          | Facilitated design-thinking session → DT Coach; DT curriculum/learning → DT Learning Tutor; otherwise UX research, JTBD, journey mapping → UX UI Designer                                                     |
| product-owner    | GitHub Backlog Manager        | Issue Triage Agent, AzDO PRD to WIT, Jira PRD to WIT, Agile Coach, Product Manager Advisor                           | PRD→work items for ADO → AzDO PRD to WIT, for Jira → Jira PRD to WIT; single-issue triage → Issue Triage Agent; story refinement → Agile Coach; requirements discovery → Product Manager Advisor; otherwise backlog management → GitHub Backlog Manager. **ADO and Jira**: `ADO Backlog Manager` and `Jira Backlog Manager` are user-invocable only and cannot be dispatched; when the project's tracker is ADO or Jira, plan the work items here and escalate the tracker write to the user, who runs that manager directly |
| analyst          | PRD Builder                   | BRD Builder, Product Manager Advisor, Meeting Analyst                                                                | Business requirements → BRD Builder; advisory/validation → Product Manager Advisor; transcript→requirements → Meeting Analyst; otherwise product requirements → PRD Builder                                    |
| data-scientist   | DS Gen Data Spec              | DS Gen Jupyter Notebook, DS Gen Streamlit Dashboard, DS Test Streamlit Dashboard                                    | EDA notebook → DS Gen Jupyter Notebook; dashboard build → DS Gen Streamlit Dashboard; dashboard test → DS Test Streamlit Dashboard; otherwise data dictionary/profile → DS Gen Data Spec                       |
| prompt-engineer  | Squad Prompt Engineer         | Evaluation Dataset Creator, Vally Test Author, HVE Artifact Tester                                                   | Eval dataset → Evaluation Dataset Creator; conformance stimuli → Vally Test Author; artifact conformance run → HVE Artifact Tester; otherwise author, refactor, or analyse a prompt artifact → Squad Prompt Engineer (squad-owned charter running the `prompt-builder`, `prompt-refactor`, and `prompt-analyze` skills) |
| technical-writer | Squad Technical Writer        | —                                                                                                                   | Squad-owned charter running the `documentation` skill; `Documentation` itself is user-invocable only and cannot be dispatched                                                                                  |
| presenter        | PowerPoint Subagent           | —                                                                                                                   | Owns the deck end-to-end through the `powerpoint` skill pipeline (extract → content YAML → build → validate). `PowerPoint Builder` is the user-invocable orchestrator and cannot be dispatched, so the subagent is the Primary |
| experimenter     | Experiment Designer           | —                                                                                                                   | Single agent — Minimum Viable Experiment design                                                                                                                                                               |
| cost-manager     | Squad Cost Manager            | —                                                                                                                   | Pricing lookups (Azure Retail Prices REST via Squad Researcher), budget envelopes, FinOps-aligned tradeoffs, WAF Cost Optimization checklist (CO:01–CO:14); cost-impact review on plans and architecture        |
| azure-architect  | Squad Azure Architect         | —                                                                                                                   | Azure HLD/LLD authoring with AVM modules and landing-zone patterns; distinct from `architect` (the System Architecture Reviewer reviews tradeoffs while this role authors)                                      |
| scribe           | Squad Scribe                  | —                                                                                                                   | Squad-owned subagent; the single writer of squad state and of durable per-agent notes under `/memories/repo/`                                                                                                 |
| devrel           | —                             | —                                                                                                                   | **No agent and no backing skill.** Unlike the other charter-backed roles, developer relations has no HVE Core capability to wrap, so a charter here would invent a capability rather than expose one. The role stays listed and unselectable until a real skill backs it; escalate this work to the user |
| iac-author       | Squad IaC Author              | —                                                                                                                   | Convert the Squad Azure Architect's LLD table into Bicep or Terraform under infra/{track}/{project} with AVM modules; authors IaC but never deploys (deployment is the deployer's role)                          |
| deployer         | Squad Deployer                | —                                                                                                                   | Run Azure deployments (what-if/plan, then gated create/apply) in the consumer's environment, strictly behind the Impactful-Action Gate; defaults to a read-only dry-run                                          |
| modernizer       | Squad Modernization Planner   | Squad SQL Migration Advisor                                                                                          | Framework, dependency, deprecated-API, containerization, or Azure-migration-readiness modernization routes to Squad Modernization Planner. SQL migration advisory requests (SQL Server to Azure, schema or data migration path selection, downtime-class migration planning) route to Squad SQL Migration Advisor. |
| asbuilt-author   | Squad As-Built Author         | —                                                                                                                   | Author drop-in as-built artifacts (resource inventory, compliance matrix, operations runbook, DR plan) for already-deployed infrastructure; strictly read-only, never deploys or authors IaC                     |
| azure-diagnose   | Squad Azure Diagnose          | —                                                                                                                   | Read-only triage of deployed Azure resources (Resource Health, Monitor/Log Analytics, configuration) into ranked hypotheses; recommends fixes but never applies them, deferring to the deployer or IaC author    |
| intake-validator | Product Manager Advisor       | PRD Quality Reviewer, BRD Quality Reviewer                                                                          | Seeded in the `product` and `full` profiles (addable to any roster); dispatched only by the intake gate in `.github/instructions/squad/squad-intake-gate.instructions.md`. PRD input → PRD Quality Reviewer; BRD input → BRD Quality Reviewer; otherwise requirements completeness and clarity check → Product Manager Advisor |

### Dispatchability

A role's Primary must be an agent the coordinator can actually reach. An agent is **dispatchable** through `runSubagent` or `task` only when its frontmatter does **not** set `disable-model-invocation: true`. HVE Core sets that flag on its user-invocable entry points, so those agents are reachable by a person typing their name and by nothing else.

* Never seed a `disable-model-invocation: true` agent as a Primary or an Alternate. A dispatch against one silently returns nothing, and a lighter model that receives nothing tends to fill the gap by doing the work inline — which is exactly the protocol violation *Dispatch Discipline* forbids.
* When the only agent that fits a role is user-invocable, the role is **thin charter needed**: either author a squad-owned charter that runs the same underlying skill, or escalate the step to the user so they invoke that agent themselves.
* The squad-owned charters `Squad Researcher`, `Squad Lead`, `Squad Implementor`, `Squad Reviewer`, `Squad Challenger`, `Squad Technical Writer`, and `Squad Prompt Engineer` exist for exactly this reason. HVE Core moved research, planning, implementation, review, critique, documentation, and prompt authoring from agents to the `rpi-research`, `rpi-plan`, `rpi-implement`, `rpi-review`, `rpi-challenger`, `documentation`, and `prompt-builder` skills; the charters are the dispatchable shells that run them.

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
| developer, iac-author                             | `.copilot-tracking/changes/`                        |
| tester, challenger                                | `.copilot-tracking/reviews/`                        |
| prompt-engineer                                   | `.copilot-tracking/prompts/`                        |
| analyst, product-owner, designer, experimenter    | `.copilot-tracking/plans/`                          |
| presenter                                         | `.copilot-tracking/ppt/<date>/<deck-slug>/`         |
| technical-writer                                  | `docs/`                                             |
| architect, azure-architect                        | `docs/architecture/`                                |
| scribe                                            | the squad root itself (state, not a deliverable)    |

**In a federation, deliverable roots are rebased.** A sub-squad's `squadRoot` is `.copilot-tracking/squad/members/<name>/`, and every root in the table above is written relative to it — a `product` sub-squad's plan lands at `.copilot-tracking/squad/members/product/plans/`, and its deck at `.copilot-tracking/squad/members/product/ppt/<date>/<deck-slug>/`. Only `docs/` stays at the repository root, because published documentation and architecture are repository-wide outputs rather than per-sub-squad working state. A sub-squad that writes a deliverable to the repository-root tracking path has escaped its root; the coordinator treats that as a failed stage and re-dispatches with the rebased path stated explicitly.

## Relationship Cardinality

The mapping deliberately supports three shapes so squad roles can stay human-meaningful while reusing the full HVE Core cast:

* **One-to-one** — a role maps to a single agent with no alternates. Examples: `privacy → Privacy Planner`, `experimenter → Experiment Designer`, `presenter → PowerPoint Subagent`.
* **One-to-many** — a role maps to a Primary plus Alternates, and the coordinator resolves to one agent per the Selection Cue. Examples: `product-owner` resolves across the triage, PRD-to-work-item, and refinement agents by request shape; `tester` resolves across the code-review perspective subagents by review sub-type.
* **Many-to-one** — a single agent fills more than one role. Examples: `Codebase Profiler` serves `researcher` and `security`; `Finding Deep Verifier` serves `fact-checker` and `security`; `Product Manager Advisor` serves `product-owner`, `analyst`, and `intake-validator`; `Meeting Analyst` serves `researcher` and `analyst`.

A shared agent is not a conflict: each role dispatches it with role-scoped context, and the Squad Scribe records which role invoked it under that role's history.

## Resolving a Role to an Agent

The coordinator turns a matched role into exactly one concrete agent at dispatch time:

1. **Default to the Primary agent** named in the role's `team.md` row (seeded from this catalog).
2. **Apply the Selection Cue** — when the request matches a cue, dispatch the indicated Alternate instead of the Primary.
3. **Verify the agent is installed and dispatchable.** The resolved agent must be present in the project (its APM package deployed into `.github/agents/`) **and** must not set `disable-model-invocation: true`. Check both before dispatching, not after a silent no-op. When either check fails, escalate to the user — treat it the same as a **thin charter needed** role rather than silently substituting.
4. **Record any non-primary resolution** through the Squad Scribe, so `history/<agent>.md` reflects the agent that actually ran and the cue that selected it.
5. **Never self-fill an absent role.** When the resolved agent is not installed, not dispatchable, or returns nothing, the coordinator stops and escalates to the user. It must not perform the role's work itself, and must not substitute a non-mapped agent to fill the gap. An absent role blocks the stage until the user installs the agent, names a substitute, or removes the role. A dispatch that returns nothing is an absent role, not an invitation to improvise.

## Casting Rules

* Use the exact `name:` frontmatter value from the deployed agent. Names with spaces are quoted when referenced from prompt or agent frontmatter.
* Prefer a deployed HVE Core agent (Primary or Alternate) over a new charter. Author a thin charter only when a required role has no reasonable **dispatchable** HVE Core fit.
* Never name a `disable-model-invocation: true` agent as a Primary or an Alternate (see *Dispatchability*).
* Keep exactly one Primary per role so dispatch is always deterministic; list every other valid agent under Alternate Agents with a Selection Cue.
* Treat `fact-checker → Finding Deep Verifier` as a best-fit mapping: the agent verifies findings rather than performing general fact-checking, so confirm it suits the request before dispatch.
* Record any deviation from the catalog (a substituted agent, a non-primary resolution, or a new charter) through the Squad Scribe so the roster stays the single source of truth.
* **Re-validate the catalog against the deployed cast whenever the HVE Core dependency is upgraded.** Agent names move when upstream consolidates agents into skills; a roster row pointing at a name that no longer ships is indistinguishable at run time from a broken dispatch. The coordinator's Step 1 roster-resolution precheck is the runtime guard, but the catalog itself is the thing to correct.

## Squad Profiles

A squad profile is a named, project-tailored subset of the cast catalog. Profiles let a project choose the squad that fits its work instead of always seeding the full cast. The coordinator selects a profile during Init Mode (see the Squad Coordinator agent), and the Squad Scribe stamps the chosen profile's members into `team.md`.

The `scribe` role is always included in every profile — it is the single writer of squad state and is never proposed as an optional member. The `intake-validator` role is seeded into the `product` and `full` profiles, where requirement and input artifacts are most central; other profiles can add it on demand, and when the conditional intake gate (`.github/instructions/squad/squad-intake-gate.instructions.md`) would fire in a squad that does not carry the role, the coordinator offers to add it rather than skipping the readiness check.

Every profile also carries the **methodology spine**: `researcher`, `lead`, `developer`, and `tester` — the four roles that run the HVE Core delivery cycle of Research → Plan → Implement → Review. The spine guarantees that, whatever a project's specialization, the squad can always research a question, plan the work, implement the change, and review the result; each profile adds its specialist roles on top. A user may drop a spine role during Init Mode, but that disables the matching leg of the methodology and the Implementation Gate in `squad-routing.instructions.md` escalates if the removed role is later needed.

Some profiles also carry **deliverable-producing roles** — roles whose output is a standalone, user-facing artifact (a requirements document, a refined backlog, a design study, an experiment design, a slide deck, written documentation, or a data notebook) rather than a code or infrastructure change owned by `developer`. These roles are `analyst`, `product-owner`, `designer`, `experimenter`, `presenter`, `technical-writer`, and `data-scientist`. When a profile carries two or more of them — the `product` profile is the canonical case — the work is a set of distinct deliverables rather than a single build, and autopilot fans its Implement stage out across the owning specialists instead of dispatching a single `developer` (see *Deliverable Fan-Out* in `squad-autopilot.instructions.md`). Every other profile carries at most one deliverable-producing role, so its Implement stage stays the unchanged single build.

| Profile        | Members (roles)                                                                                                                                | Choose when the project is…                                              |
|----------------|------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------|
| `default`      | researcher, lead, developer, tester, scribe                                                                                                    | General build and delivery work — a balanced team (recommended default)  |
| `full`         | researcher, lead, developer, tester, challenger, architect, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, security, rai, designer, fact-checker, cost-manager, modernizer, prompt-engineer, intake-validator, scribe                   | You want every deployed capability available                             |
| `security`     | researcher, lead, developer, tester, security, rai, fact-checker, scribe                                                                       | Security-, threat-, or responsible-AI-focused (auth, secrets, ML, LLM)   |
| `design`       | researcher, lead, developer, tester, designer, scribe                                                                                          | UX/UI, accessibility, or product-design focused                          |
| `architecture` | researcher, lead, developer, tester, architect, azure-architect, cost-manager, scribe                                                          | System design, infrastructure, or architecture-review focused            |
| `azure`        | researcher, lead, developer, tester, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, architect, cost-manager, security, modernizer, scribe                                    | Azure-focused build with budget and security oversight (Bicep, landing-zone, FinOps signals) |
| `product`      | researcher, lead, developer, tester, analyst, designer, product-owner, presenter, technical-writer, experimenter, intake-validator, scribe                       | Business discovery and delivery — requirements, design thinking, roadmap, and stakeholder deliverables (often non-technical) |

### Profile Selection

The coordinator chooses a profile in this order of precedence:

1. **Explicit choice** — the user names a profile (for example, `profile=security`) or confirms one during Init Mode.
2. **Project discovery** — the coordinator infers a profile from repository signals when the user does not name one:
   * Source files, tests, and package manifests with no specialized signal → `default`.
   * Authentication, secrets, threat modeling, ML/LLM, or data-handling signals → `security`.
   * Frontend frameworks (React, Vue, Svelte, Angular), CSS, or accessibility signals → `design`.
   * Bicep templates plus budget, pricing, FinOps, or `cost-manager` signals (or `.bicep` files alongside an Azure landing-zone reference) → `azure`.
   * Infrastructure-as-code (Bicep, Terraform without Azure-specific cost signals), system-design docs, or component diagrams → `architecture`.
   * Requirements documents (BRD/PRD), product or roadmap docs, discovery/design-thinking artifacts, or a repository with little or no source code where the work is business discovery and delivery → `product`.
   * Mixed or unclear signals → propose `default` and offer `full`.
3. **Fallback** — when discovery is inconclusive and the user gives no hint, propose `default` as the recommended profile.

A profile only ever lists roles that exist in the cast catalog. A role with no dispatchable Primary — currently only `devrel`, which has no backing skill either — is never part of a profile until a charter is authored.

### Building a Custom Roster

When no named profile fits — or when one is close but not exact — the coordinator helps the user assemble a custom roster rather than inventing one. The coordinator presents the role menu below — each row is a role the squad can dispatch, the plain-language work it contributes, and the deployed agent that fills it by default — and the user picks any subset. The user may start from a profile's roles and add or remove from there; when they do, the roster is recorded as a custom roster derived from that profile, because any change to a profile's exact member set makes it custom.

Three rules bound a custom roster so it never references work the squad cannot actually do:

* **`scribe` is always included** — it is the single writer of squad state and is never offered as optional.
* **The methodology spine (`researcher`, `lead`, `developer`, `tester`) is recommended** so the Research → Plan → Implement → Review cycle stays intact. The user may drop a spine role, but that disables the matching leg and the Implementation Gate in `squad-routing.instructions.md` escalates if it is later needed.
* **Only catalog roles with a dispatchable Primary are selectable.** The coordinator never invents a role or an agent outside the cast catalog. A role whose mapped agent is not installed or is not dispatchable, or a role with no backing capability at all such as `devrel`, is flagged and left out rather than seeded.

The menu mirrors the Cast Catalog above; each item names the role, the deployed agent that fills it by default (in parentheses), and the user-facing gloss.

* **researcher** (Squad Researcher) — Investigates the codebase, the web, and connected tools to gather the context the squad needs.
* **lead** (Squad Lead) — Plans the work: breaks a request into phases, sequences them, and names the deliverables and their owners.
* **developer** (Squad Implementor) — Implements the change: writes and edits code to carry out the plan.
* **tester** (Squad Reviewer) — Reviews changes for quality, correctness, and standards before they ship.
* **challenger** (Squad Challenger) — Plays devil's advocate: pressure-tests plans and assumptions, and checks that a plan is backed by the research it claims to rest on.
* **architect** (System Architecture Reviewer) — Reviews system-design tradeoffs and well-architected alignment; can produce ADRs.
* **security** (Security Planner) — Plans security: threat-models the work, identifies risks, and maps controls.
* **rai** (RAI Planner) — Assesses responsible-AI concerns such as fairness, harm, and transparency for AI/ML work.
* **privacy** (Privacy Planner) — Maps personal-data flows, tests DPIA thresholds, and plans privacy controls.
* **fact-checker** (Finding Deep Verifier) — Independently verifies findings and claims before the squad trusts them.
* **designer** (UX UI Designer) — Researches users and designs the experience: journey maps, jobs-to-be-done, and accessibility.
* **product-owner** (GitHub Backlog Manager) — Manages the backlog: triages, refines, and organizes work items. ADO and Jira writes are planned here and handed to you to run.
* **analyst** (PRD Builder) — Captures product and business requirements as a PRD or BRD.
* **data-scientist** (DS Gen Data Spec) — Profiles data and builds exploratory-analysis notebooks and dashboards.
* **prompt-engineer** (Squad Prompt Engineer) — Authors, refactors, and analyses prompt artifacts: prompts, instructions, agents, and skills.
* **technical-writer** (Squad Technical Writer) — Authors and maintains documentation that stays in step with the code.
* **presenter** (PowerPoint Subagent) — Builds slide decks and executive summaries through the PowerPoint skill pipeline.
* **experimenter** (Experiment Designer) — Designs a Minimum Viable Experiment to validate the riskiest assumption.
* **cost-manager** (Squad Cost Manager) — Estimates Azure cost and applies FinOps and Well-Architected cost guidance.
* **azure-architect** (Squad Azure Architect) — Authors Azure high- and low-level designs with AVM modules and landing-zone patterns.
* **iac-author** (Squad IaC Author) — Converts an Azure design into Bicep or Terraform; authors IaC but never deploys.
* **deployer** (Squad Deployer) — Runs Azure deployments behind a human approval gate; defaults to a read-only dry run.
* **modernizer** (Squad Modernization Planner) — Plans framework, dependency, and cloud-migration modernization; SQL migration advisory cues resolve to Squad SQL Migration Advisor.
* **asbuilt-author** (Squad As-Built Author) — Documents already-deployed infrastructure (inventory, compliance, runbook, DR); strictly read-only.
* **azure-diagnose** (Squad Azure Diagnose) — Triages deployed Azure resources read-only into ranked hypotheses; recommends but never applies fixes.
* **intake-validator** (Product Manager Advisor) — Validates that requirement and input artifacts are complete and clear before the squad builds on them. Seeded in the `product` and `full` profiles; addable to any roster; dispatched only by the conditional intake gate.
* **scribe** (Squad Scribe) — Writes squad state: decisions, history, and memory. Always included; never optional.
