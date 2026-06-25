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

Model Tier records a preference, not what actually ran: the concrete model used for each dispatch is captured in the per-dispatch consumption block in `history/<agent>.md` and aggregated into `consumption.md`, never in `team.md`.

The `Agent Name (Primary)` column holds exactly one agent; the role always has a deterministic default. `Alternate Agents` is optional and may be empty for one-to-one roles. The uniqueness key for a row is the (`Role`, `Member Name`) pair, so two rows with the same `Role` are legal when their `Member Name` values differ. When `Member Name` is empty, only one row per `Role` is allowed and the coordinator dispatches that row whenever the role matches. The coordinator resolves the role to a single concrete agent at dispatch time using the *Resolving a Role to an Agent* rules below.

### Members Example

<!-- <example-roster> -->
```markdown
## Members

| Role          | Member Name | Agent Name (Primary)          | Alternate Agents                                  | Invocation         | Model Tier |
|---------------|-------------|-------------------------------|---------------------------------------------------|--------------------|------------|
| lead          | Alpha       | Task Planner                  | RPI Agent, Phase Implementor, Task Challenger     | runSubagent / task | default    |
| developer     | Beta        | Task Implementor              | Phase Implementor                                 | runSubagent / task | default    |
| developer     | Gamma       | Task Implementor              | Phase Implementor                                 | runSubagent / task | default    |
| tester        | Delta       | Task Reviewer                 | Code Review Full, PR Review, Plan Validator       | runSubagent / task | fast       |
| product-owner |             | ADO Backlog Manager           | GitHub Backlog Manager, Jira Backlog Manager      | runSubagent / task | default    |
| scribe        |             | Squad Scribe                  | Memory                                            | runSubagent / task | fast       |
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

## Cast Catalog

The cast catalog is the default casting source and the canonical mapping between squad roles (members) and deployed HVE Core agents, keyed by each agent's exact `name:` frontmatter value. When a project has no `team.md`, the coordinator seeds the roster from this catalog.

The relationship between roles and agents is **many-to-many**. A role names one **Primary** agent — the default the coordinator dispatches — plus optional **Alternate** agents it may resolve to instead when the request matches a **Selection Cue**. A single agent may also fill more than one role (for example, `Codebase Profiler` serves both `researcher` and `security`). See *Relationship Cardinality* below.

Roles that have no stable HVE Core equivalent are marked **thin charter needed**. A thin charter is a small, squad-owned subagent authored under `squad-src/.github/agents/squad/` when the role is actually required; until then the coordinator omits the role or escalates to the user.

| Role             | Primary Agent (`name:`)       | Alternate Agents (`name:`)                                                                                          | Selection Cue                                                                                                                                                                                                 |
|------------------|-------------------------------|---------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| lead             | Task Planner                  | RPI Agent, Phase Implementor, Task Challenger                                                                        | Full research→plan→implement cycle → RPI Agent; execute one numbered plan phase → Phase Implementor; pressure-test a plan or assumptions → Task Challenger; otherwise plan a single task → Task Planner       |
| researcher       | Task Researcher               | Researcher Subagent, Codebase Profiler, Meeting Analyst                                                              | External/web/MCP research → Researcher Subagent; technology-profile scan → Codebase Profiler; meeting-transcript mining → Meeting Analyst; otherwise codebase research → Task Researcher                       |
| developer        | Task Implementor              | Phase Implementor                                                                                                   | Execute a numbered plan phase → Phase Implementor; otherwise implement a single task → Task Implementor                                                                                                       |
| tester           | Task Reviewer                 | Code Review Full, Code Review Standards, Code Review Functional, PR Review, Implementation Validator, Plan Validator, RPI Validator | Full pre-PR review → Code Review Full; standards diff → Code Review Standards; correctness/edge-case diff → Code Review Functional; pull-request review → PR Review; implementation-vs-design → Implementation Validator; plan-vs-research → Plan Validator; changes-vs-plan → RPI Validator; otherwise task review → Task Reviewer |
| challenger       | Task Challenger               | —                                                                                                                   | Single agent — devil's-advocate review of plans, assumptions, and scope                                                                                                                                       |
| architect        | System Architecture Reviewer  | Arch Diagram Builder, ADR Creator, Network ISA-95 Planner                                                            | Architecture diagram → Arch Diagram Builder; decision record → ADR Creator; ISA-95 / OT network design → Network ISA-95 Planner; otherwise design-tradeoff review → System Architecture Reviewer              |
| security         | Security Planner              | Security Reviewer, SSSC Planner, Skill Assessor, Finding Deep Verifier, Report Generator, Dependency Reviewer, Codebase Profiler | Code-level security review → Security Reviewer; supply-chain posture → SSSC Planner; single-skill assessment → Skill Assessor; verify a finding → Finding Deep Verifier; compile vulnerability report → Report Generator; dependency-change review → Dependency Reviewer; tech profiling → Codebase Profiler; otherwise security planning → Security Planner |
| rai              | RAI Planner                   | —                                                                                                                   | Single agent — responsible-AI assessment and planning                                                                                                                                                        |
| fact-checker     | Finding Deep Verifier         | —                                                                                                                   | Verification-focused (confirms FAIL/PARTIAL findings); confirm fit before dispatch                                                                                                                            |
| designer         | UX UI Designer                | DT Coach, DT Learning Tutor                                                                                          | Facilitated design-thinking session → DT Coach; DT curriculum/learning → DT Learning Tutor; otherwise UX research, JTBD, journey mapping → UX UI Designer                                                     |
| product-owner    | ADO Backlog Manager           | GitHub Backlog Manager, Jira Backlog Manager, Issue Triage Agent, AzDO PRD to WIT, Jira PRD to WIT, Agile Coach, Product Manager Advisor | Tracker selects the manager: GitHub → GitHub Backlog Manager, Jira → Jira Backlog Manager, ADO → ADO Backlog Manager; PRD→work items for ADO → AzDO PRD to WIT, for Jira → Jira PRD to WIT; single-issue triage → Issue Triage Agent; story refinement → Agile Coach; requirements discovery → Product Manager Advisor |
| analyst          | PRD Builder                   | BRD Builder, Product Manager Advisor, Meeting Analyst                                                                | Business requirements → BRD Builder; advisory/validation → Product Manager Advisor; transcript→requirements → Meeting Analyst; otherwise product requirements → PRD Builder                                    |
| data-scientist   | DS Gen Data Spec              | DS Gen Jupyter Notebook, DS Gen Streamlit Dashboard, DS Test Streamlit Dashboard                                    | EDA notebook → DS Gen Jupyter Notebook; dashboard build → DS Gen Streamlit Dashboard; dashboard test → DS Test Streamlit Dashboard; otherwise data dictionary/profile → DS Gen Data Spec                       |
| prompt-engineer  | Prompt Builder                | Prompt Updater, Prompt Evaluator, Prompt Tester, Evaluation Dataset Creator                                          | Modify an existing prompt artifact → Prompt Updater; evaluate output quality → Prompt Evaluator; sandbox-test a prompt → Prompt Tester; build an eval dataset → Evaluation Dataset Creator; otherwise author a new prompt/agent/skill → Prompt Builder |
| technical-writer | Doc Ops                       | Documentation Update Checker                                                                                         | Detect stale docs vs code → Documentation Update Checker; otherwise author/maintain documentation → Doc Ops                                                                                                   |
| presenter        | PowerPoint Builder            | PowerPoint Subagent                                                                                                 | Delegated build/extract/validate step → PowerPoint Subagent; otherwise own the deck end-to-end → PowerPoint Builder                                                                                           |
| experimenter     | Experiment Designer           | —                                                                                                                   | Single agent — Minimum Viable Experiment design                                                                                                                                                               |
| cost-manager     | Squad Cost Manager            | —                                                                                                                   | Pricing lookups (Azure Retail Prices REST via Researcher Subagent), budget envelopes, FinOps-aligned tradeoffs, WAF Cost Optimization checklist (CO:01–CO:14); cost-impact review on plans and architecture     |
| azure-architect  | Squad Azure Architect         | —                                                                                                                   | Azure HLD/LLD authoring with AVM modules and landing-zone patterns; distinct from `architect` (the System Architecture Reviewer reviews tradeoffs while this role authors)                                      |
| scribe           | Squad Scribe                  | Memory                                                                                                              | Cross-session durable memory persistence → Memory; otherwise squad-state writes → Squad Scribe (squad-owned subagent)                                                                                         |
| devrel           | —                             | —                                                                                                                   | Thin charter needed (no HVE Core equivalent)                                                                                                                                                                  |
| iac-author       | Squad IaC Author              | —                                                                                                                   | Convert the Squad Azure Architect's LLD table into Bicep or Terraform under infra/{track}/{project} with AVM modules; authors IaC but never deploys (deployment is the deployer's role)                          |
| deployer         | Squad Deployer                | —                                                                                                                   | Run Azure deployments (what-if/plan, then gated create/apply) in the consumer's environment, strictly behind the Impactful-Action Gate; defaults to a read-only dry-run                                          |
| modernizer       | Squad Modernization Planner   | —                                                                                                                   | Framework, dependency, deprecated-API, containerization, or Azure-migration-readiness modernization; plans and coordinates execution, delegating to the developer role or the official App Modernization tooling |
| asbuilt-author   | Squad As-Built Author         | —                                                                                                                   | Author drop-in as-built artifacts (resource inventory, compliance matrix, operations runbook, DR plan) for already-deployed infrastructure; strictly read-only, never deploys or authors IaC                     |
| azure-diagnose   | Squad Azure Diagnose          | —                                                                                                                   | Read-only triage of deployed Azure resources (Resource Health, Monitor/Log Analytics, configuration) into ranked hypotheses; recommends fixes but never applies them, deferring to the deployer or IaC author    |

## Relationship Cardinality

The mapping deliberately supports three shapes so squad roles can stay human-meaningful while reusing the full HVE Core cast:

* **One-to-one** — a role maps to a single agent with no alternates. Examples: `rai → RAI Planner`, `challenger → Task Challenger`, `experimenter → Experiment Designer`.
* **One-to-many** — a role maps to a Primary plus Alternates, and the coordinator resolves to one agent per the Selection Cue. Examples: `product-owner` resolves across the ADO/GitHub/Jira backlog managers by tracker; `tester` resolves across the review and validator agents by review sub-type.
* **Many-to-one** — a single agent fills more than one role. Examples: `Codebase Profiler` serves `researcher` and `security`; `Finding Deep Verifier` serves `fact-checker`, `tester`, and `security`; `Product Manager Advisor` serves `product-owner` and `analyst`; `Phase Implementor` serves `lead` and `developer`; `Plan Validator` serves `lead` and `tester`; `Meeting Analyst` serves `researcher` and `analyst`.

A shared agent is not a conflict: each role dispatches it with role-scoped context, and the Squad Scribe records which role invoked it under that role's history.

## Resolving a Role to an Agent

The coordinator turns a matched role into exactly one concrete agent at dispatch time:

1. **Default to the Primary agent** named in the role's `team.md` row (seeded from this catalog).
2. **Apply the Selection Cue** — when the request matches a cue, dispatch the indicated Alternate instead of the Primary.
3. **Verify the agent is installed.** The resolved agent must be present in the project (its APM package deployed into `.github/`). When it is absent, escalate to the user — treat it the same as a **thin charter needed** role rather than silently substituting.
4. **Record any non-primary resolution** through the Squad Scribe, so `history/<agent>.md` reflects the agent that actually ran and the cue that selected it.
5. **Never self-fill an absent role.** When the resolved agent is not installed or not available, the coordinator stops and escalates to the user. It must not perform the role's work itself, and must not substitute a non-mapped agent to fill the gap. An absent role blocks the stage until the user installs the agent, names a substitute, or removes the role.

## Casting Rules

* Use the exact `name:` frontmatter value from the deployed agent. Names with spaces are quoted when referenced from prompt or agent frontmatter.
* Prefer a deployed HVE Core agent (Primary or Alternate) over a new charter. Author a thin charter only when a required role has no reasonable HVE Core fit.
* Keep exactly one Primary per role so dispatch is always deterministic; list every other valid agent under Alternate Agents with a Selection Cue.
* Treat `fact-checker → Finding Deep Verifier` as a best-fit mapping: the agent verifies findings rather than performing general fact-checking, so confirm it suits the request before dispatch.
* Record any deviation from the catalog (a substituted agent, a non-primary resolution, or a new charter) through the Squad Scribe so the roster stays the single source of truth.

## Squad Profiles

A squad profile is a named, project-tailored subset of the cast catalog. Profiles let a project choose the squad that fits its work instead of always seeding the full cast. The coordinator selects a profile during Init Mode (see the Squad Coordinator agent), and the Squad Scribe stamps the chosen profile's members into `team.md`.

The `scribe` role is always included in every profile — it is the single writer of squad state and is never proposed as an optional member.

Every profile also carries the **methodology spine**: `researcher`, `lead`, `developer`, and `tester` — the four roles that run the HVE Core delivery cycle of Research → Plan → Implement → Review. The spine guarantees that, whatever a project's specialization, the squad can always research a question, plan the work, implement the change, and review the result; each profile adds its specialist roles on top. A user may drop a spine role during Init Mode, but that disables the matching leg of the methodology and the Implementation Gate in `squad-routing.instructions.md` escalates if the removed role is later needed.

Some profiles also carry **deliverable-producing roles** — roles whose output is a standalone, user-facing artifact (a requirements document, a refined backlog, a design study, an experiment design, a slide deck, written documentation, or a data notebook) rather than a code or infrastructure change owned by `developer`. These roles are `analyst`, `product-owner`, `designer`, `experimenter`, `presenter`, `technical-writer`, and `data-scientist`. When a profile carries two or more of them — the `product` profile is the canonical case — the work is a set of distinct deliverables rather than a single build, and autopilot fans its Implement stage out across the owning specialists instead of dispatching a single `developer` (see *Deliverable Fan-Out* in `squad-autopilot.instructions.md`). Every other profile carries at most one deliverable-producing role, so its Implement stage stays the unchanged single build.

| Profile        | Members (roles)                                                                                                                                | Choose when the project is…                                              |
|----------------|------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------|
| `default`      | researcher, lead, developer, tester, scribe                                                                                                    | General build and delivery work — a balanced team (recommended default)  |
| `full`         | researcher, lead, developer, tester, architect, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, security, rai, designer, fact-checker, cost-manager, modernizer, scribe                   | You want every deployed capability available                             |
| `security`     | researcher, lead, developer, tester, security, rai, fact-checker, scribe                                                                       | Security-, threat-, or responsible-AI-focused (auth, secrets, ML, LLM)   |
| `design`       | researcher, lead, developer, tester, designer, scribe                                                                                          | UX/UI, accessibility, or product-design focused                          |
| `architecture` | researcher, lead, developer, tester, architect, azure-architect, cost-manager, scribe                                                          | System design, infrastructure, or architecture-review focused            |
| `azure`        | researcher, lead, developer, tester, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, architect, cost-manager, security, scribe                                                | Azure-focused build with budget and security oversight (Bicep, landing-zone, FinOps signals) |
| `product`      | researcher, lead, developer, tester, analyst, designer, product-owner, presenter, technical-writer, experimenter, scribe                       | Business discovery and delivery — requirements, design thinking, roadmap, and stakeholder deliverables (often non-technical) |

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

A profile only ever lists roles that exist in the cast catalog. Roles marked **thin charter needed** (such as `devrel`) are never part of a profile until a charter is authored.
