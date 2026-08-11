---
name: squad
description: 'Operating procedure for the HVE Core Squad Coordinator: initialize squad state from seed templates, route requests to a cast of deployed HVE Core agents in parallel, record decisions and history through the Squad Scribe, and synthesize a response. Use when running, initializing, or maintaining a squad under .copilot-tracking/squad/.'
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-06-10"
---

# Squad Operating Procedure

## Overview

The squad is a user-invocable Squad Coordinator that dispatches a reusable cast of deployed HVE Core agents in parallel and persists roster, routing, decisions, and per-agent history under `.copilot-tracking/squad/`. There is no separate runtime: every squad verb is a thin convention over an existing HVE Core mechanism.

This skill packages the coordinator's operating procedure and the seed templates it stamps out on first run. It complements ten instruction files that auto-apply when squad state is touched:

* `.github/instructions/squad/squad-roster.instructions.md` — roster schema and cast catalog.
* `.github/instructions/squad/squad-routing.instructions.md` — routing table and escalation rules.
* `.github/instructions/squad/squad-intake-gate.instructions.md` — conditional pre-work intake gate that validates requirement and input artifacts before planning or implementation, with a bounded auto-remediation loop and the Intake Readiness Verdict schema.
* `.github/instructions/squad/squad-state.instructions.md` — state layout, single-writer ownership, and tool-to-mechanism mapping.
* `.github/instructions/squad/squad-council.instructions.md` — pre-implementation council protocol with parallel dispatch, most-restrictive-wins synthesis, and the Council Verdict schema.
* `.github/instructions/squad/squad-autonomous.instructions.md` — opt-in `auto-validated` autonomy tier with a bounded re-validation loop, divergence detection, and mandatory escalation triggers.
* `.github/instructions/squad/squad-autopilot.instructions.md` — opt-in `mode=autopilot` full pipeline (research→plan→implement→review) with Human Gates only on impactful actions and final-outcome validation.
* `.github/instructions/squad/squad-notifications.instructions.md` — user-contact capture at squad build time and the delivery-agnostic notification (ping) contract per mode.
* `.github/instructions/squad/squad-watch-mode.instructions.md` — event-driven Watch Mode (DR-01) trigger contract: opt-in gates, event-to-intent map, injection-safe payloads, the event-scoped sub-squad bootstrap, and the pull-request deliverable.
* `.github/instructions/squad/squad-federation.instructions.md` — opt-in federation of named sub-squads under one repo: the parameterized squad root, the registry (`federation.md`) and meta-routing (`meta-routing.md`) schemas, detection precedence, and the two-level single-writer rule.
* `.github/instructions/squad/squad-federation-autopilot.instructions.md` — opt-in federation-level autopilot: the meta-pipeline (`mode=autopilot` with no `squad=` target) that orders sub-squad autopilot runs under one set of federation gates, an aggregate cost ceiling, and one consolidated final-outcome validation.

## Prerequisites

* A `runSubagent` or `task` tool is available so the coordinator can dispatch `user-invocable: false` agents.
* The deployed HVE Core cast exists (System Architecture Reviewer, Security Planner, RAI Planner, UX UI Designer, Finding Deep Verifier, PowerPoint Subagent) plus the squad-owned charters (Squad Scribe, Squad Researcher, Squad Lead, Squad Implementor, Squad Reviewer, Squad Challenger, Squad Technical Writer, Squad Prompt Engineer).
* Every roster Primary resolves to an installed agent that does **not** set `disable-model-invocation: true`; the coordinator's Step 1b roster-resolution precheck confirms this before any dispatch.
* The memory tool is available for durable per-agent notes under `/memories/repo/`.

## Procedure

The coordinator runs four stages each turn: **init**, **route**, **decide**, and **handoff**. Only the coordinator initiates state changes, and only the Squad Scribe performs the writes.

### Squad Profiles

A profile is a curated subset of the cast tailored to a kind of project. The coordinator seeds only the profile's members into `team.md`, and the routing table is filtered to those roles. The `scribe` role is always included (the single writer of squad state), and so is the **methodology spine** (`researcher`, `lead`, `developer`, `tester`) that runs the Research → Plan → Implement → Review cycle in every profile; the `intake-validator` role is seeded into the `product` and `full` profiles and can be added to any roster. Profiles are defined canonically in `.github/instructions/squad/squad-roster.instructions.md`; the catalog below mirrors them.

One catalog role — `backlog-executor`, which writes work items into a live Azure DevOps or Jira project — is **opt-in** and appears in no profile, not even `full`, because a tracker write reaches a whole team's backlog. The coordinator offers to add it the first time a request needs a tracker write, and adds it only on the user's say-so. See *Opt-In Roles* in the roster conventions.

| Profile         | Members                                                                                                                       | Use When                                                                                     |
|-----------------|-------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `default`       | researcher, lead, developer, tester, scribe                                                                                   | General-purpose work; recommended starting point                                             |
| `full`          | researcher, lead, developer, tester, challenger, architect, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, security, supply-chain, vuln-manager, rai, privacy, accessibility, risk-manager, performance, observability, designer, fact-checker, cost-manager, modernizer, prompt-engineer, analyst, product-owner, presenter, technical-writer, experimenter, data-scientist, intake-validator, scribe | Complex, cross-cutting projects that need every discipline except the opt-in roles |
| `security`      | researcher, lead, developer, tester, security, supply-chain, rai, privacy, fact-checker, scribe                               | Security, supply-chain, privacy, threat-modeling, and responsible-AI focus                   |
| `design`        | researcher, lead, developer, tester, designer, accessibility, scribe                                                          | UX/UI and product-design focus                                                               |
| `accessibility` | researcher, lead, developer, tester, accessibility, designer, scribe                                                          | Accessibility conformance as the goal itself (WCAG 2.2, Section 508, EN 301 549)             |
| `architecture`  | researcher, lead, developer, tester, architect, azure-architect, cost-manager, scribe                                        | System design and architecture focus                                                         |
| `azure`         | researcher, lead, developer, tester, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, architect, cost-manager, security, modernizer, scribe | Azure-focused build with budget and security oversight (Bicep, landing-zone, FinOps signals) |
| `modernization` | researcher, lead, developer, tester, modernizer, architect, azure-architect, iac-author, cost-manager, asbuilt-author, scribe | Legacy uplift: framework and dependency upgrades, re-platforming, SQL or cloud migration      |
| `compliance`    | researcher, lead, developer, tester, security, supply-chain, vuln-manager, privacy, rai, accessibility, risk-manager, scribe  | Conformance evidence as the goal: an audit, an attestation, or a customer security questionnaire |
| `operations`    | researcher, lead, developer, tester, azure-diagnose, performance, observability, asbuilt-author, iac-author, deployer, scribe | Running a deployed system: incidents, reliability targets, instrumentation design, and as-built docs |
| `product`       | researcher, lead, developer, tester, analyst, designer, product-owner, presenter, technical-writer, experimenter, data-scientist, intake-validator, scribe | Business discovery and delivery — requirements, design thinking, roadmap, and stakeholder deliverables (often non-technical) |

### Squad Packs

A **pack** is a named set of roles added *on top of* a profile, never instead of one. A profile answers "what kind of work is this" and carries the methodology spine; a pack answers "what is it built on" and carries specialists only, so technology verticals arrive as packs and compose with any profile. Exactly one profile, zero or more packs. Packs are defined canonically in `.github/instructions/squad/squad-roster.instructions.md`; the catalog below mirrors them.

| Pack             | Adds                       | Use When                                                                                       | Arrival                                                                       |
|------------------|----------------------------|-------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------|
| `power-platform` | pp-architect, pp-connector | The project is built on Power Platform — Power Apps, Power Automate, Dataverse, Power Pages, or Copilot Studio | Opt-in; both roles rest on registered external agents the consumer installs |
| `m365-copilot` | m365-agent-architect, m365-agent-integrator | The project is built on Microsoft 365 Copilot — declarative agents, TypeSpec agent definitions, API plugins, MCP-backed agents, or Microsoft Graph integration | Opt-in; both roles rest on registered external agents the consumer installs |
| `aws`          | aws-architect, aws-diagnose | The project is built on AWS — Lambda and serverless, ECS or EKS, CDK, SAM, CloudFormation, Organizations and landing zones, or a live AWS workload to triage | Opt-in; both roles rest on registered external agents the consumer installs |

The Scribe records a roster's provenance — the profile plus any applied packs — in the Init decision in `decisions.md`, and in a federation in the registry's `Profile` column. A pack's roles obey every rule a profile's roles obey: a role whose external resource is not installed is offered with its install command rather than seeded.

A pack is proposed, never imposed. The coordinator offers one at Init when the repository carries the domain's signals **or the request itself names the domain**, and offers one mid-project when a request needs a role only that pack provides. A pack is equally removable: dropping one removes only the roles it still owns — never a role the profile or another pack also contributes — and appends a decision rather than editing anything. The append-only `decisions.md` and `history/<agent>.md` are untouched by a removal, the removed member's row stays in `consumption.md` marked removed so the run total stays truthful, and deliverables already written stay on disk. See *Removing a Pack* in `.github/instructions/squad/squad-roster.instructions.md`.

**A pack is not a federation.** One piece of work that needs extra expertise is a profile plus a pack, because those roles must share a plan, a council, and a review. Two streams of work with separate deliverables and owners is a federation. Federation does not reach a vertical any faster — a sub-squad is seeded from a profile and takes the pack the same way any roster does — so building a sub-squad to obtain a role buys a duplicated spine and a second state tree for no extra reach. See *Pack or Federation* in `.github/instructions/squad/squad-roster.instructions.md`.

### Federation (Sub-Squads)

Federation is an opt-in way to run several named sub-squads under one repository — for example, a business team's `product` sub-squad and an architecture team's `azure` sub-squad, side by side. It is additive: a repository that never opts in keeps exactly the single-squad behavior described here. The full contract is `.github/instructions/squad/squad-federation.instructions.md`; the operator's view is:

* **Parameterized squad root.** Each squad's state lives under a *squad root*. The default is `.copilot-tracking/squad/`; a federation roots each sub-squad at `.copilot-tracking/squad/members/<name>/`. Every state path is `<squadRoot>/...`, so a sub-squad is an ordinary squad rooted at a named path — same roster, routing, decisions, history, consumption, and single-writer Scribe.
* **Detection precedence.** At the start of a turn the coordinator checks `.copilot-tracking/squad/`: a `federation.md` registry means a federation (the Squad Federation Coordinator owns the turn); otherwise a top-level `team.md` means a plain squad (unchanged); otherwise Init Mode. `federation.md` versus `team.md` at the top is the single discriminator.
* **Meta layer.** The federation root adds `federation.md` (the sub-squad registry) and `meta-routing.md` (request pattern → sub-squad) plus a federation-level `decisions.md`, `history/<sub-squad>.md`, and `state.json`. The Squad Federation Coordinator reads the registry and meta-routing, classifies the request to one or more sub-squads (or honors an explicit `squad=<name>` target), and runs each sub-squad's per-turn protocol scoped to `members/<name>/`.
* **Required unique names.** Every sub-squad — including a custom one — must have a required, unique, lower-kebab-case name, because the name is at once the `members/<name>/` directory and the `squad=<name>` selector. Init Mode validates names against each other and against the registry before creating any folder and asks the user to rename on a collision; it never auto-suffixes or reuses an existing sub-squad directory.
* **Entry point.** `/squad-federation` invokes the Squad Federation Coordinator. Its Federation Init Mode proposes → confirms → creates a set of sub-squads (each seeded from a profile via the standard Init), then routes the request. `/squad` continues to serve plain single-squad projects.
* **Promotion (single squad → federation).** An existing single-squad project already has a top-level `team.md`, so the fresh-project single-squad-or-federation offer never reaches it. `/squad-federation promote` runs Federation Promotion Mode: it adopts the existing squad into a federation as its first sub-squad by relocating its top-level state tree **and its pre-promotion deliverables** into `members/<name>/` intact (append-only decision and history logs preserved byte-for-byte) and seeding the meta layer, which flips detection to federation mode. The deliverable list is enumerated from disk and confirmed with the user, because deliverable roots rebase under `members/<name>/` and artifacts left at the old paths fall outside the roster that now points at them. Every move is copy → verify → delete-source, never delete-then-move, and the consumption ledger carries across so the federation does not report a zero-cost first turn. Promotion is confirmation-gated, non-destructive, refuses on a name collision or when a `federation.md` already exists, and is the recommended path when a single-squad project grows into the multi-team or multi-domain shape a federation serves. The contract is *Promotion: Single Squad → Federation* in `.github/instructions/squad/squad-federation.instructions.md`.
* **Expansion (add a sub-squad).** Once a federation exists, `/squad-federation init` (or an add-a-sub-squad request) runs Federation Expansion Mode: it proposes and, on confirmation, seeds a new sub-squad under `members/<new>/` and registers it by appending a row to `federation.md` and a route to `meta-routing.md` (preserve-on-replace, so existing sub-squads are untouched), plus a federation decision and `history/<new>.md`. It is additive and confirmation-gated and refuses on a name collision. The same `init` entry point *builds* a federation on a fresh project and *expands* one when a `federation.md` is already present. The contract is *Expansion: Add a Sub-Squad to an Existing Federation* in `.github/instructions/squad/squad-federation.instructions.md`.
* **Two-level single writer.** The Squad Scribe remains the only writer at both levels: it writes each sub-squad's state under its own root and the federation-level decision/history at the federation root, with each level's entries linked. Each sub-squad's writes stay inside its own root, so parallel sub-squads never race.
* **Event-scoped sub-squads (Watch Mode).** Every event-triggered run executes in a sub-squad dedicated to its event — `issue-123`, `pr-456`, `sweep-2026-07-27`, `push-release-2-0-a1b2c3d`, `dispatch-<runId>` — so continuous-AI activity leaves a per-event audit trail. The Squad Federation Coordinator bootstraps whatever the repository is missing before the run starts: it initializes a federation on a bare project, **auto-promotes** an existing single squad into one (relocating its state intact) and then adds the event sub-squad, or **auto-expands** an existing federation. These unattended variants are auto-approved rather than confirmation-gated — bounded because they write only under `.copilot-tracking/`, run only after the Watch Mode opt-in and authorization gates, and waive no Human Gate. Names derive only from structural event metadata, never from issue or comment text; a re-triggered event reuses its sub-squad; and a collision with a human-created sub-squad escalates instead of overwriting. Watch-created rows carry `Owner=watch-mode` and a narrow ref-keyed meta-routing pattern so interactive requests never route into them. The contract is *Event-Scoped Sub-Squads (Federation Bootstrap)* in `.github/instructions/squad/squad-watch-mode.instructions.md`.
* **Federation autopilot (opt-in).** `/squad-federation mode=autopilot` with no `squad=` target runs a federation-level meta-pipeline: it orders the selected sub-squads by dependency (confirmed at the first gate), runs each one's standard single-squad autopilot inner run scoped to `members/<name>/`, aggregates every Impactful-Action and Risk Gate to the federation level (attributed to the sub-squad that raised it), applies one aggregate `cost-ceiling`, and ends with a single consolidated final-outcome validation. A single `squad=` target keeps the forward-only behavior, and each sub-squad's inner autopilot pipeline is unchanged. The full contract is `.github/instructions/squad/squad-federation-autopilot.instructions.md`.

The **multi-repo** federation — a hub coordinating one squad per repository — reuses this layout and only changes a sub-squad's kind to `repo` with an external location plus a cross-repo execution driver; it is deferred (see the multi-repo plan).

### Init

Run once per project, then verify on every turn. Init Mode mirrors a propose → confirm → create flow and never writes files before the user confirms.

1. Check for `.copilot-tracking/squad/team.md` and `.copilot-tracking/squad/routing.md`.
2. When either file is missing (and no `.copilot-tracking/squad/federation.md` exists), first **offer single squad or federation** (Phase 0): a single squad (default) for one team across the repo, or a federation of named sub-squads when different teams or domains each want their own squad. When the user chooses a federation, hand off to `/squad-federation` (the Squad Federation Coordinator) instead of seeding a single squad; otherwise continue. Then **propose**: discover the project (languages, frameworks, tests, IaC, security/AI markers) read-only, then recommend a profile using the precedence in the roster's *Profile Selection* (explicit `profile=` hint → discovery inference → `default`), plus any packs an explicit `pack=` hint or the repository's domain signals call for. Present the profile under consideration — the user's `profile=` choice when given, otherwise the most appropriate profile the coordinator selected — together with any proposed packs, with its roles and why it fits, and ask the user to proceed or choose differently. On **proceed** the flow is unchanged; on **decline** the user either picks a different profile from the listed set or builds a custom roster from the role menu (each role shown with a plain-language description), per the roster's *Building a Custom Roster*. Once a profile or customized roster is on the table, also offer naming choices for the seeded members per the roster's *Naming Conventions* (user-supplied per role, coordinator-assigned aliases from the deterministic wordlist, a mix, or skip). Wait on the user before any write.
3. On **confirm**, hand the chosen roster to the Squad Scribe to **create**: `team.md` from the confirmed profile's members plus the roles of every applied pack, deduplicated (including the `Member Name` column when names were provided), `routing.md` from the default routing rules filtered to that roster, plus `decisions.md`, `notifications.md`, `state.json`, and a `history/` directory. The Init decision records the roster's provenance — the profile plus any applied packs, or `custom`. Before the create step, **always ask** for an approval channel per `.github/instructions/squad/squad-notifications.instructions.md` (`github-issue` for remote/unattended approval, `webhook`, or `in-chat`) and seed the answer into the `state.json` `notify` object. The answer is optional — declining keeps `in-chat` — but the question is never skipped or silently defaulted. In a federation the question is asked once at the federation level and inherited by every sub-squad.
4. Confirm the roster and routing table are present before classifying the request. The coordinator never writes these files itself.

### Route

1. Read `team.md` and `routing.md`.
2. Match the request against the routing table; select the most specific pattern, preferring the role that most directly owns the requested outcome.
3. Resolve each matched role to a deployed agent through the roster. A role marked **thin charter needed** has no deployed agent — escalate instead of substituting.
4. Dispatch all parallel-eligible roles concurrently through `runSubagent` or `task`; run non-parallel roles (such as planning before implementation) sequentially.
5. Apply cost-first model selection: prefer the `fast` tier for read-heavy `auto` roles and reserve the `default` tier for reasoning-heavy `confirm` roles. A user tier hint overrides the per-role default for the turn.

### Decide

1. Collect each dispatched agent's structured findings and reconcile conflicts.
2. Hand the turn's decision and rationale to the Squad Scribe, which appends to `decisions.md` (append-only).
3. When a decision is architecturally significant, additionally capture it as an Architecture Decision Record via the `adr-author` skill and reference that ADR from the decision entry.
4. Persist durable, role-scoped learnings to `/memories/repo/squad-<agent>.md` through the Squad Scribe and the memory tool.
5. Consult the shipped `learnings/shared-learnings.md` playbook (skill-root-relative within the deployed `squad` skill) as read-only, authoritative context and apply any curated entry whose scenario matches the work at hand. This shipped file complements the consumer-local memory written in the prior step: the coordinator reads the shared playbook and writes local learnings, and it never writes back to the shipped file. When the organization has configured the tenant-internal APM dependency, the consumer also carries a tenant playbook at `.agents/skills/squad-learnings-tenant/tenant-learnings.md`; consult it after the shipped playbook as additional read-only, authoritative context and apply any entry whose scenario matches. That tenant file is present only when the organization configured the dependency, and the coordinator never writes to it. The full read order is local memory first, then the shipped playbook, then the optional tenant playbook. A local learning reaches the shared playbook only through the fork-and-PR promotion path in `CONTRIBUTING.md`.

### Handoff

1. Hand each dispatched agent's request and outcome to the Squad Scribe, which appends them to `history/<agent>.md` (append-only) along with the per-dispatch consumption block (the resolved model and how it was resolved, plus estimated input, cached, cache-write, and output token cost and credits), then rewrites the `consumption.md` ledger and updates the `state.json` `currentRun` totals. The consumption block is written for every dispatch, never conditionally: the coordinator resolves the model through the ladder in *Model Attribution* and passes it with the roster tier, and when it omits the payload the Scribe resolves the model itself — recording `unknown` and a `tier-default` price rather than inventing a model name — so a history append never lands without its consumption block and the ledger never stays at its seed while dispatches have run. Every consumption figure is an estimate.
2. Synthesize the collected findings into a concise answer for the user.
3. Escalate to the user — rather than acting — when the matched rule is at the `escalate` tier, no pattern matches with reasonable confidence, a role resolves to **thin charter needed**, or two rules conflict with no clearly more specific match. State the ambiguity, list the candidate roles, and ask the user to choose.

### Intake Gate Procedure

The intake gate is the operator's pre-work readiness check on the inputs a turn builds on. It is conditional: the coordinator runs it only when the turn's work is grounded in requirement or input artifacts (a PRD, BRD, specification, requirements document, user story, design document, transcript, or a user-referenced input file) and advances toward a plan, a build, or a deliverable. When no input grounds the work, the gate is a no-op. The full protocol lives in `.github/instructions/squad/squad-intake-gate.instructions.md`; the operator's view is:

1. The coordinator dispatches `intake-validator` (seeded in the `product` and `full` profiles and addable to any roster, resolved by input type per the roster Selection Cue: PRD → PRD Quality Reviewer, BRD → BRD Quality Reviewer, otherwise Product Manager Advisor) to assess the inputs for completeness, clarity, testability, consistency, and scope boundaries. When the active roster lacks `intake-validator`, the coordinator offers to add it rather than skipping the check.
2. The validator returns a verdict label (`Ready`, `Ready-With-Gaps`, `Not-Ready`) with its blocking and non-blocking gaps and any clarifying questions.
3. The Squad Scribe appends a single `## Intake Readiness Verdict <timestamp> <topic-id>` entry to `decisions.md`. The coordinator does not write the verdict.
4. On `Ready` or `Ready-With-Gaps`, downstream planning and implementation proceed (non-blocking gaps carried as recorded assumptions). On `Not-Ready`, the coordinator runs the bounded auto-remediation loop — dispatch `analyst` or `product-owner` to fill the blocking gaps, then re-validate; capped at two cycles — and escalates when a gap needs a human decision, the cap is reached with blocking gaps open, or the blocking-gap set stops shrinking.
5. The verdict gates downstream dispatch and runs ahead of the Council and Implementation gates; a non-stale `Ready` verdict for the same unchanged inputs is reused rather than re-run.

### Council Procedure

The council is the operator's pre-implementation cross-check. The coordinator triggers it when the user explicitly asks for a council, a validation, a cross-check, or a pre-implementation review, or when a request mixes implementation language with risk language and crosses two or more council-member domains (architecture, security, cost, product-fit, RAI). The full protocol lives in `.github/instructions/squad/squad-council.instructions.md`; the operator's view is:

1. The coordinator dispatches the default council in a single parallel batch: `architect`, `security`, `cost-manager`, `product-owner`, plus optional `rai` when AI/ML, training data, agent autonomy, or regulated data is in scope.
2. Each council role returns a finding with a verdict label (`Approve`, `Conditional`, `Concern`, `Block`) and a risk label (`Risk: Low`, `Risk: Medium`, `Risk: High`).
3. The Squad Scribe synthesizes the findings using a most-restrictive-wins rule: any `Block` or any `Risk: High` drives a `Stop` verdict; any `Conditional` (with no blockers) drives `Go-With-Conditions`; otherwise the verdict is `Go`.
4. The Scribe appends a single `## Council Verdict <timestamp> <topic-id>` entry to `decisions.md`. The coordinator does not write the verdict.
5. The verdict gates the next turn's implementation dispatch: `Go` or `Go-With-Conditions` permits dispatch (with conditions attached as inputs); `Stop` blocks dispatch and the coordinator escalates.

### Autonomous Procedure

The opt-in `auto-validated` tier lets a council validate a developer's output on the same turn, without an intervening user prompt. The full protocol lives in `.github/instructions/squad/squad-autonomous.instructions.md`; the operator's view is:

1. The user opts in per turn by passing `mode=autonomous` to `/squad`. Without that input, the coordinator runs the normal six-step protocol.
2. The coordinator runs the loop: council dispatch → verdict synthesis → implementer dispatch (on `Go` or `Go-With-Conditions`) → council re-validation (cycle 1) → optional council re-validation (cycle 2).
3. The re-validation cap is hard at two cycles; after cycle 2 the coordinator escalates regardless of outcome.
4. The loop stops and escalates immediately on any mandatory trigger: a `Stop` verdict, a `Risk: High` from `security` / `cost-manager` / `rai`, any cost-impacting `confirm`-tier move, any compliance violation, or any irreversible write (production deploy, schema migration, data deletion, force-push).
5. Divergence detection escalates immediately when two consecutive cycles produce different verdicts on the same issue, even before the cap.
6. A per-turn cost ceiling (`cost-ceiling=$X`, optional) caps spend; when exceeded, the coordinator escalates instead of running the next cycle.
7. The Scribe writes a per-topic summary to `history/autonomous-loop-<id>.md` (append-only by topic-id) and per-cycle entries to each role's `history/<agent>.md`.

### Autopilot Procedure

The opt-in `mode=autopilot` runs the full delivery pipeline end-to-end, stopping for the human only at impactful actions and final-outcome validation. The full protocol lives in `.github/instructions/squad/squad-autopilot.instructions.md`; the operator's view is:

1. The user opts in per turn by passing `mode=autopilot` to `/squad`. Without that input, the coordinator runs the interactive per-turn protocol where each stage is gated by its routing tier.
2. The coordinator sequences the pipeline: a conditional intake gate (when the work is grounded in requirement or input artifacts) → research → plan → pre-implementation council → implement (via the autonomous validator loop) → review → final-outcome validation, advancing stage-to-stage without a human turn. For a profile that carries two or more deliverable-producing roles (`product` and `full`), the implement stage fans out across the owning specialists — the plan enumerates the deliverables and the coordinator dispatches each specialist in dependency order, each a Scribe-recorded stage — instead of a single `developer`; every other profile keeps the single-build implement stage.
3. The pipeline stops only at two Human Gate classes: an **Impactful-Action Gate** (deploy, `git push`/force-push, PR merge, schema migration, data deletion, destructive infra ops, secret rotation, or any user-marked irreversible action) and a **Risk Gate** (any `Stop` verdict, `Risk: High` from security/cost/RAI, `confirm`-tier cost move, compliance violation, validator divergence, or cost-ceiling breach).
4. Autopilot never auto-releases: after review it fires a `final-outcome` notification to the registered contact and waits for human validation before any release-tier action.
5. The Scribe writes a per-run summary to `history/autopilot-run-<id>.md` (append-only by topic-id) and the notification records to `notifications.md`.

### Notification Procedure

The squad captures an optional contact at build time and pings it for approvals. The full contract lives in `.github/instructions/squad/squad-notifications.instructions.md`; the operator's view is:

1. During Init Mode the coordinator **always asks** for an approval channel and seeds the answer into `state.json` under `notify`. The choices are `github-issue` (recommended for unattended/VM runs — approvable from a phone), `webhook` (outbound team ping only), or `in-chat` (default). Declining is a valid answer; skipping the question is not. A federation asks once at the federation root and every sub-squad inherits that object, so the question is never repeated per sub-squad — and an unattended Watch Mode bootstrap, having no user to ask, inherits it silently.
2. Delivery is resolved at send time by the channel: `github-issue` opens/assigns an approval issue via the GitHub MCP or `gh` CLI; `webhook` POSTs to a configured tool/MCP or `SQUAD_WEBHOOK_URL`; otherwise it degrades to an in-chat ping. The package ships no transport, and the squad always keeps an in-chat approval available so a run is never permanently blocked.
3. For `github-issue`, the human approves remotely with a keyword comment (`/approve`, `/approve-all`, `/changes: <note>`, `/stop`) or a `squad/*` label. Only the registered handle or a repo collaborator can approve, and only the keyword acts — comment prose is never executed as a command. An unattended run resumes via a host-side poll loop or a GitHub Action on `issue_comment` (the inbound half of Watch Mode / DR-01).
4. In `mode=autopilot`, a ping fires at each Human Gate and at final-outcome validation. In interactive mode, a ping fires at each step gate. In `mode=autonomous`, a ping fires on the loop's mandatory escalations.
5. The Scribe appends every fired notification to `notifications.md` (append-only).

## Tool-to-Mechanism Mapping

| Squad verb       | HVE Core mechanism                                                                                       |
|------------------|----------------------------------------------------------------------------------------------------------|
| `squad_route`    | Dispatch the assigned role via `runSubagent` / `task` against a `user-invocable: false` agent             |
| `squad_decide`   | Append the decision and rationale to `decisions.md`; optionally record an ADR via the `adr-author` skill  |
| `squad_memory`   | Write durable per-agent notes with the memory tool to `/memories/repo/squad-<agent>.md`                   |
| `squad_notify`   | Fire a notification per `squad-notifications.instructions.md`; deliver via a configured tool when present, else in-chat, and append the record to `notifications.md` |
| `squad_escalate` | Apply the escalate-to-user convention from the routing rules before any role acts                         |

`squad_memory` spans up to three surfaces. It reads the shipped `learnings/shared-learnings.md` playbook (skill-root-relative within the deployed `squad` skill) as read-only, authoritative shared context, and when the organization configured the tenant-internal APM dependency it also reads the tenant playbook at `.agents/skills/squad-learnings-tenant/tenant-learnings.md` as read-only context, in addition to writing durable per-agent notes to the consumer-local `/memories/repo/squad-<agent>.md`. Neither shared playbook is ever written from a run: promotion of a local learning into a shared surface flows only through the human-reviewed promotion paths in `CONTRIBUTING.md`.

## Seed Templates

The coordinator hands these templates to the Squad Scribe on first run, after the user confirms a profile in Init Mode. They stay consistent with the three squad instruction files: `team.md` holds the confirmed profile's members (the full cast catalog shown below is the `full` profile), `routing.md` mirrors the default routing rules filtered to the seeded roster, and the write semantics match the state layout (`decisions.md` and `history/<agent>.md` are append-only; `team.md`, `routing.md`, `state.json`, `consumption.md`, and `consumption-rates.md` use replace semantics).

### team.md

Seeded from the confirmed profile's members plus the roles of every applied pack; the template below shows the `full` profile with no pack applied. For other profiles, only the profile's rows are written, and each applied pack appends its own roles to them. The `Member Name` column is populated from the Init Mode naming step: it may be empty for roles the user chose not to name, and it must be unique within a `Role` when two rows share the same role. The role-to-agent relationship is many-to-many: each role names one **Primary** agent the coordinator dispatches by default plus optional **Alternate** agents it resolves to per the cast catalog's Selection Cue (see `squad-roster.instructions.md`). The `devrel`, `networking`, `gcp`, and `identity` roles have no deployed HVE Core agent and no backing skill, so they stay unselectable until one exists. The opt-in `backlog-executor` role is absent from every profile and is appended to `team.md` only when the user accepts the coordinator's offer to add it. Pack roles such as `pp-architect` and `pp-connector` are likewise absent from every profile template and are appended only when a pack is applied, and `qa-engineer` and `release-engineer` are absent for the related reason that their Primaries are registered opt-in external agents — a registered-but-uninstalled role is never seeded.

```markdown
---
description: "Squad roster: roles and the deployed HVE Core agents that fill them"
---

# Squad Roster

## Members

| Role            | Member Name | Agent Name (Primary)         | Alternate Agents                                       | Invocation         | Model Tier              | Deliverable Root                      |
|-----------------|-------------|------------------------------|--------------------------------------------------------|--------------------|-------------------------|---------------------------------------|
| researcher      | Alpha       | Squad Researcher             | Codebase Profiler, Meeting Analyst                     | runSubagent / task | default                 | .copilot-tracking/research/<date>/    |
| lead            | Beta        | Squad Lead                   | RPI Planner                                            | runSubagent / task | default                 | .copilot-tracking/plans/              |
| developer       | Gamma       | Squad Implementor            | —                                                      | runSubagent / task | default                 | .copilot-tracking/changes/            |
| tester          | Delta       | Squad Reviewer               | Code Review Functional, Code Review Standards          | runSubagent / task | fast                    | .copilot-tracking/reviews/            |
| challenger      | Epsilon     | Squad Challenger             | —                                                      | runSubagent / task | default                 | .copilot-tracking/reviews/            |
| architect       | Zeta        | System Architecture Reviewer | ADR Creator                                            | runSubagent / task | default                 | docs/architecture/                    |
| azure-architect | Eta         | Squad Azure Architect        | —                                                      | runSubagent / task | default                 | docs/architecture/                    |
| security        | Theta       | Security Planner             | SSSC Planner, Skill Assessor, Finding Deep Verifier    | runSubagent / task | default                 | —                                     |
| supply-chain    | Phi         | SSSC Planner                 | Supply Chain Skill Assessor                            | runSubagent / task | default                 | .copilot-tracking/sssc-plans/         |
| vuln-manager    | Delta-2     | Squad Vulnerability Manager  | —                                                      | runSubagent / task | default                 | .copilot-tracking/security/vex/       |
| rai             | Iota        | RAI Planner                  | RAI Skill Assessor                                     | runSubagent / task | default                 | —                                     |
| privacy         | Chi         | Privacy Planner              | —                                                      | runSubagent / task | default                 | —                                     |
| accessibility   | Psi         | Accessibility Framework Assessor | Accessibility Surface Inventory                    | runSubagent / task | default                 | .copilot-tracking/accessibility/      |
| designer        | Kappa       | UX UI Designer               | DT Coach, DT Learning Tutor                            | runSubagent / task | default                 | .copilot-tracking/plans/              |
| fact-checker    | Lambda      | Finding Deep Verifier        | —                                                      | runSubagent / task | fast                    | —                                     |
| risk-manager    | Epsilon-2   | Squad Risk Manager           | —                                                      | runSubagent / task | default                 | docs/risks/                           |
| cost-manager    | Mu          | Squad Cost Manager           | —                                                      | runSubagent / task | default                 | —                                     |
| iac-author      | Nu          | Squad IaC Author             | —                                                      | runSubagent / task | default                 | .copilot-tracking/changes/            |
| deployer        | Xi          | Squad Deployer               | —                                                      | runSubagent / task | default                 | —                                     |
| asbuilt-author  | Omicron     | Squad As-Built Author        | —                                                      | runSubagent / task | default                 | docs/architecture/                    |
| azure-diagnose  | Pi          | Squad Azure Diagnose         | —                                                      | runSubagent / task | fast                    | —                                     |
| performance     | Zeta-2      | Squad Performance Planner    | —                                                      | runSubagent / task | default                 | .copilot-tracking/performance-plans/  |
| observability   | Eta-2       | Squad Observability Planner  | —                                                      | runSubagent / task | default                 | .copilot-tracking/observability-plans/ |
| modernizer      | Rho         | Squad Modernization Planner  | Squad SQL Migration Advisor                            | runSubagent / task | default                 | .copilot-tracking/plans/              |
| prompt-engineer | Sigma       | Squad Prompt Engineer        | Evaluation Dataset Creator, Vally Test Author          | runSubagent / task | default                 | .copilot-tracking/prompts/            |
| analyst         | Omega       | PRD Builder                  | BRD Builder, Product Manager Advisor, Meeting Analyst  | runSubagent / task | default                 | .copilot-tracking/plans/              |
| product-owner   | Alpha-2     | GitHub Backlog Manager       | Issue Triage Agent, Agile Coach                        | runSubagent / task | default                 | .copilot-tracking/plans/              |
| presenter       | Tau         | PowerPoint Subagent          | —                                                      | runSubagent / task | default                 | .copilot-tracking/ppt/<date>/<slug>/  |
| technical-writer | Upsilon    | Squad Technical Writer       | —                                                      | runSubagent / task | fast                    | docs/                                 |
| experimenter    | Beta-2      | Experiment Designer          | —                                                      | runSubagent / task | default                 | .copilot-tracking/plans/              |
| data-scientist  | Gamma-2     | DS Gen Data Spec             | DS Gen Jupyter Notebook, DS Gen Streamlit Dashboard    | runSubagent / task | default                 | outputs/                              |
| intake-validator |            | Product Manager Advisor      | PRD Quality Reviewer, BRD Quality Reviewer             | runSubagent / task | fast                    | —                                     |
| scribe          |             | Squad Scribe                 | —                                                      | runSubagent / task | fast                    | (squad state)                         |
| devrel          |             | —                            | —                                                      | —                  | — (no backing skill)    | —                                     |
```

### routing.md

Seeded from the default routing rules. Each rule points at a role that exists in `team.md`. The canonical rule set is *Default Routing Rules* in `.github/instructions/squad/squad-routing.instructions.md`; the table below mirrors it in full, and the instructions win on any difference. The Scribe drops every row whose role is not on the seeded team, so a narrow profile writes only its own subset.

```markdown
---
description: "Squad routing: request patterns mapped to roles, autonomy tiers, and parallel eligibility"
---

# Squad Routing

| Pattern / Keyword                          | Role(s)                      | Autonomy Tier | Parallel-Eligible |
|--------------------------------------------|------------------------------|---------------|-------------------|
| research, investigate, explore, find out   | researcher                   | auto          | yes               |
| plan, break down, sequence, design plan    | lead                         | confirm       | no                |
| implement, build, code, fix                | developer                    | confirm       | no                |
| review, validate, check quality            | tester                       | auto          | yes               |
| write tests, add test coverage, run the tests, test plan, test case, edge case, boundary case, hostile input, reproduce the bug, regression test, flaky test, exploratory testing | qa-engineer | confirm | no |
| challenge, pressure-test, poke holes, devil's advocate, what could go wrong | challenger | auto | yes         |
| author prompt, write agent file, refactor instructions, analyse skill | prompt-engineer | confirm | no         |
| validate requirements, requirements readiness, requirements complete, requirements clear, intake check, are the requirements ready | intake-validator | auto | yes |
| security, threat, vulnerability, STRIDE    | Security Planner             | confirm       | yes               |
| supply chain, SBOM, SLSA, provenance, OpenSSF Scorecard, Sigstore, signed release, dependency pinning | supply-chain | confirm | yes         |
| CVE, vulnerability triage, VEX, OpenVEX, exploitability, is this CVE exploitable, advisory disposition, not affected | vuln-manager | confirm | yes |
| privacy, personal data, PII, DPIA, GDPR, data subject, retention | privacy               | confirm       | yes               |
| accessibility, a11y, WCAG, ARIA, screen reader, keyboard navigation, Section 508, EN 301 549, VPAT, conformance audit | accessibility | confirm | yes |
| design, UX, UI, wireframe, journey, interaction design | UX UI Designer          | confirm       | yes               |
| requirements, BRD, PRD, user story, acceptance criteria | PRD Builder                 | confirm       | yes               |
| journey map, persona, design thinking, empathize, ideate, problem statement | DT Coach | confirm | yes           |
| roadmap, backlog, epic, sprint, refine, prioritize, story | Agile Coach               | confirm       | no                |
| create work items in ADO, push backlog to Azure DevOps, create Jira issues, apply the handoff, execute handoff, sync work items to the tracker | backlog-executor | confirm | no |
| GitLab merge request, GitLab pipeline, GitLab issue, open an MR | product-owner        | escalate      | no                |
| experiment, hypothesis, validate assumption, MVE, riskiest assumption | Experiment Designer | confirm | yes         |
| presentation, deck, slides, executive summary, pitch | presenter                    | confirm       | no                |
| document, write up, summarize for stakeholders, readme | technical-writer           | confirm       | no                |
| data profile, data dictionary, EDA, exploratory analysis, notebook, dashboard, dataset, Power BI, DAX, semantic model, star schema, report design, Fabric, Lakehouse, OneLake | data-scientist | confirm | no |
| architecture, system design, components    | System Architecture Reviewer | auto          | yes               |
| responsible AI, RAI, fairness, harm        | RAI Planner                  | confirm       | yes               |
| verify finding, confirm claim, fact-check  | Finding Deep Verifier        | auto          | yes               |
| risk register, project risk, probability and impact, risk matrix, mitigation plan, contingency, what are the risks | risk-manager | confirm | yes |
| SLO, SLA, error budget, latency budget, load test plan, capacity planning, performance target, throughput, soak test | performance | confirm | yes |
| observability, instrumentation, telemetry design, spans, traces, metrics, structured logging, OpenTelemetry, what should we emit | observability | confirm | yes |
| author IaC, write Bicep, write Terraform, convert LLD to infra, infrastructure as code | Squad IaC Author | confirm | no |
| deploy, provision, what-if, terraform plan, terraform apply, az deployment | Squad Deployer | confirm | no |
| as-built, resource inventory, compliance matrix, operations runbook, DR plan, document deployed infrastructure | asbuilt-author | confirm | no |
| diagnose, troubleshoot, resource health, why is resource failing, investigate deployed, policy check, incident, outage, sev1, sev2, on-call, postmortem, root cause | azure-diagnose | auto | yes |
| validate, cross-check, pre-implementation review, council, design review, go/no-go, implement-and-cost, implement-and-risk | architect, security, cost-manager, product-owner, rai (optional) | confirm | yes |
| modernize, upgrade framework, migrate, port legacy, .NET upgrade, Java migration, dependency upgrade, containerize | modernizer | confirm | no |
| sql migration, database migration, schema migration, data migration, sql server to azure, downtime migration plan, cutover strategy | modernizer | confirm | no |
| re-platform, rewrite, port to, rebuild in, cross-stack rewrite, Node to .NET, React to Angular, convert to another language | modernizer | confirm | no |
| Power Platform, Power Apps, canvas app, model-driven app, Power Automate, cloud flow, Dataverse, Power Pages, Copilot Studio, DLP policy, Power Platform environment, solution ALM | pp-architect | confirm | yes |
| custom connector, connector certification, apiDefinition.swagger.json, apiProperties.json, script.csx, paconn, MCP connector, Copilot Studio MCP, agentic protocol | pp-connector | confirm | no |
| declarative agent, Microsoft 365 Copilot agent, M365 Copilot agent, agent manifest, TypeSpec agent, API plugin, conversation starter, agent capability, Agents Toolkit | m365-agent-architect | confirm | yes |
| Microsoft Graph, Graph SDK, Graph permission scope, MCP-backed Copilot agent, agent tool import, M365 admin center, Copilot agent rollout, agent governance in M365 | m365-agent-integrator | confirm | no |
| GitHub Actions, workflow file, CI pipeline, pipeline hardening, pin actions to SHA, OIDC in CI, CI minutes, build cost, deployment environment, release train, rollout plan, rollback plan, Azure DevOps pipeline | release-engineer | confirm | no |
| AWS, Lambda, S3, DynamoDB, EC2, ECS, EKS, Fargate, API Gateway, EventBridge, Step Functions, CloudFormation, AWS CDK, SAM, AWS landing zone, AWS Organizations, Control Tower, AWS Well-Architected | aws-architect | confirm | yes |
| CloudWatch alarm, AWS incident, AWS outage, Lambda throttling, Logs Insights, X-Ray trace, AWS root cause | aws-diagnose | auto | yes |
```

### decisions.md

Append-only log. The header is written once; every decision is appended below it and prior entries are never edited. Council Verdicts (from the Council Procedure) use the same append-only contract but a fixed schema; the placeholder below shows the shape the Scribe stamps in.

```markdown
---
description: "Append-only log of squad decisions and their rationale"
---

# Squad Decisions

Entries are appended below in chronological order. Each entry records the decision, its rationale, the turn it was made on, and a reference to an ADR when the decision is architecturally significant. Council Verdicts use the `## Council Verdict <timestamp> <topic-id>` heading and the schema in `.github/instructions/squad/squad-council.instructions.md`. Prior entries are never edited or removed.

<!-- Append new decision entries below this line. -->

<!--
Council Verdict placeholder (Scribe stamps this shape when a council runs):

## Council Verdict <timestamp> <topic-id>

* Topic: <one-line summary of the proposal>
* Proposal Ref: <path-to-plan-or-design>
* Council Members Dispatched: architect, security, cost-manager, product-owner
* Verdict: Go | Go-With-Conditions | Stop

### Findings by Role

| Role          | Verdict | Risk        | Blocking Issues | Conditions | Suggested Follow-ups |
|---------------|---------|-------------|-----------------|------------|----------------------|
| architect     | <label> | <risk>      | <list-or-none>  | <list>     | <list>               |
| security      | <label> | <risk>      | <list-or-none>  | <list>     | <list>               |
| cost-manager  | <label> | <risk>      | <list-or-none>  | <list>     | <list>               |
| product-owner | <label> | <risk>      | <list-or-none>  | <list>     | <list>               |

### Synthesis

* Blocking Issues: <consolidated list with role attribution; empty when verdict is Go>
* Conditions: <consolidated list with role attribution; empty when verdict is Go>
* Suggested Follow-ups: <consolidated list with role attribution>

### Implementation Gate

* Permits Implementation Dispatch: yes (Go, Go-With-Conditions) | no (Stop)
* Conditions Outstanding: <count>
-->

<!--
Intake Readiness Verdict placeholder (Scribe stamps this shape when the intake gate runs):

## Intake Readiness Verdict <timestamp> <topic-id>

* Topic: <one-line summary of the work the inputs ground>
* Inputs Reviewed: <comma-separated artifact paths or references>
* Validator Dispatched: <resolved agent name>
* Verdict: Ready | Ready-With-Gaps | Not-Ready
* Remediation Cycles: <0, 1, or 2>

### Findings

| Dimension        | Result    | Blocking Gaps  | Non-Blocking Gaps |
|------------------|-----------|----------------|-------------------|
| Completeness     | pass/fail | <list-or-none> | <list-or-none>    |
| Clarity          | pass/fail | <list-or-none> | <list-or-none>    |
| Testability      | pass/fail | <list-or-none> | <list-or-none>    |
| Consistency      | pass/fail | <list-or-none> | <list-or-none>    |
| Scope Boundaries | pass/fail | <list-or-none> | <list-or-none>    |

### Clarifying Questions

* <question for the user; empty when verdict is Ready>

### Recorded Assumptions

* <assumption carried into downstream work; empty when none>

### Intake Gate

* Permits Downstream Dispatch: yes (Ready, Ready-With-Gaps) | no (Not-Ready)
* Blocking Gaps Outstanding: <count>
-->
```

### history/<agent>.md

One append-only file per dispatched agent. Replace `<agent>` with the dispatched agent's name (for example, `history/Squad Researcher.md`). The header is created with the file; dispatch records are appended. Autonomous-loop runs add per-cycle dispatch entries to each role's history file using the placeholder shape below.

```markdown
---
description: "Append-only dispatch history for a single squad agent"
---

# History: <agent>

Each entry records a request this agent handled, the findings or outcome it returned, and the turn it was dispatched on. Entries are appended in chronological order and never edited.

<!-- Append new dispatch entries below this line. -->

<!--
Autonomous-loop dispatch entry pattern (Scribe stamps this shape when mode=autonomous is in effect):

### <timestamp> autonomous-loop:<topic-id> cycle:<1|2>

* Request: <scoped request the agent received>
* Verdict Returned: <label> (Risk: <level>)
* Blocking Issues: <list-or-none>
* Conditions: <list-or-none>
* Outcome: <one-line summary>
* See: `.copilot-tracking/squad/history/autonomous-loop-<topic-id>.md`
-->
```

### history/autonomous-loop-<id>.md

One file per autonomous-loop topic. Append-only by topic-id: subsequent runs against the same topic append a new dated `## Iterations` section rather than overwriting. The Scribe writes this file only when the coordinator runs in `mode=autonomous`.

```markdown
---
description: "Autonomous-loop summary for topic <id>"
---

# Autonomous Loop: <id>

* Topic: <one-line summary>
* Opt-In: mode=autonomous
* Cost Ceiling: <value or unset>
* Outcome: converged (Go) | converged (Go-With-Conditions) | escalated (<reason>)

## Iterations

| Cycle | Verdict                        | Blocking Issues | Conditions     | Notes                    |
|-------|--------------------------------|-----------------|----------------|--------------------------|
| 1     | Go / Go-With-Conditions / Stop | <list-or-none>  | <list-or-none> | <one-line cycle summary> |
| 2     | (when run)                     | <list-or-none>  | <list-or-none> | <one-line cycle summary> |

## Final Verdict Reference

* Council Verdict: see `decisions.md` under `## Council Verdict <timestamp> <id>`
```

### history/autopilot-run-<id>.md

One file per autopilot run. Append-only by topic-id: subsequent runs against the same topic append a new dated `## Stages` section rather than overwriting. The Scribe writes this file only when the coordinator runs in `mode=autopilot`.

```markdown
---
description: "Autopilot-run summary for topic <id>"
---

# Autopilot Run: <id>

* Topic: <one-line summary>
* Opt-In: mode=autopilot
* Cost Ceiling: <value or unset>
* Outcome: completed (awaiting final validation) | escalated (<reason>) | stopped (<reason>)

## Stages

| Stage     | Role(s)     | Result                          | Gate Fired                 |
|-----------|-------------|---------------------------------|----------------------------|
| research  | <agent(s)>  | <one-line outcome>              | none                       |
| plan      | <agent>     | <one-line outcome>              | none                       |
| council   | <roles>     | <verdict-or-skipped>            | <none or Risk Gate reason> |
| implement | <agent>     | <one-line outcome>              | <none or Impactful-Action> |
| review    | <agent>     | <one-line outcome>              | none                       |
| final     | coordinator | notified <recipient-or-in-chat> | Final-Outcome Validation   |
```

In a deliverable fan-out run (the `product` profile), the single `implement` row expands into one row per deliverable (`implement: <deliverable>` with its owning agent).

### notifications.md

Append-only log of notifications (pings) the squad fired. The header is written once; every notification is appended below it. Records the trigger, the recipient, the resolved channel, and the decision awaited.

```markdown
---
description: "Append-only log of squad notifications (pings) and their delivery channel"
---

# Squad Notifications

Each entry records a notification the squad fired: when, to whom, the trigger, the channel it resolved to, and the decision awaited. Entries are appended in chronological order and never edited.

<!-- Append new notification entries below this line. -->
```

### state.json

Machine-readable squad status. Uses replace semantics — the coordinator overwrites it (through the Squad Scribe) as the squad advances.

```json
{
  "schemaVersion": "1.3",
  "updated": "",
  "turn": 0,
  "mode": "interactive",
  "activeRoles": [],
  "openEscalations": [],
  "currentRun": {
    "sessionModel": "",
    "modelOverrides": {},
    "estCostUsd": 0,
    "estCreditsTotal": 0
  },
  "notify": {
    "approvalChannel": "in-chat",
    "enabled": false,
    "email": "",
    "github": {
      "handle": "",
      "repo": ""
    }
  }
}
```

Watch Mode runs additionally carry an optional, additive `trigger` object recording the event that started the run; interactive, autonomous, and autopilot runs omit it. See `.github/instructions/squad/squad-watch-mode.instructions.md`.

### consumption.md

Scribe-aggregated ledger of squad members, the model each consumed, and estimated AI-credit cost; this is the common "members and credits" readme. Uses replace semantics: the Scribe rewrites it each turn, mirrors roster order, and recomputes the run total and the comparison line from `consumption-rates.md`. Every figure is an estimate, because no per-dispatch token telemetry exists (the runtime exposes only the per-user aggregate `ai_credits_used`); token counts are estimated and cost and credits are derived, never billed.

The ledger is split into two narrower tables that both key on `Role` — one **Attribution** table (who ran, on what model) and one **Usage & Cost** table (what it cost) — instead of one 15-column table, because a table wide enough to need horizontal scrolling defeats the point of a ledger a consumer should be able to read at a glance.

Replace semantics govern the file, not the rows. Every rewrite is derived from the full set of per-dispatch consumption blocks recorded in `history/*.md` for the run, summed per role, so a role dispatched early keeps its row for the rest of the run and a role dispatched repeatedly holds one summed row. A rewrite that reflects only the current turn's dispatches produces a ledger that adds up correctly and is still wrong.

```markdown
---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: <run-id>)

## Attribution

| Role          | Member | Agent          | Model   | Model Source | Priced As | Tier   |
| ------------- | ------ | -------------- | ------- | ------------ | --------- | ------ |
| <role>        |        | <agent>        | <model> | <source>     | <model>   | <tier> |
| orchestration |        | <coord+scribe> | <model> | <source>     | <model>   | mixed  |

## Usage & Cost

| Role          | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------ | -------- | ---------- | ---------------- | ------------ | --------- |
| <role>        | 0     | 0         | 0      | 0        | 0          | 0.0000           | 0.00         | estimated |
| orchestration | 0     | 0         | 0      | 0        | 0          | 0.0000           | 0.00         | estimated |
| **Total**     | **0** | **0**     | **0**  | **0**    | **0**      | **$0.00**        | **0.00**     |           |

> Basis: estimated. No per-dispatch token telemetry exists; the runtime exposes only the per-user aggregate `ai_credits_used` via the Copilot usage-metrics REST API. `Model` is resolved per *Model Attribution* in `.github/instructions/squad/squad-state.instructions.md` and is never invented — `unknown` where it could not be resolved. `Model Source` is `cli-pinned`, `operator-declared`, `dispatch-reported`, `agent-pinned`, `session-inherited`, or `unresolved`; an `agent-pinned` row legitimately differs from the session model. `Priced As` is the rate row used and differs from `Model` only on a fallback. `Turns` is the estimated internal tool-loop turn count for the dispatch, because a dispatch is many model calls and not one. The two tables share the same `Role` order so a row in one lines up with the same row in the other. Token rates and the dispatch-size estimator come from `consumption-rates.md` (observed <date>). Calibration factor <factor> (<observations> reconciled run(s)). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$<squad-cost> (~<squad-credits> AI credits)** across <n> specialized agents, routing read-heavy roles to lightweight models and reserving high-output reasoning models only where needed. Reproducing the same outcome by manually prompting a single high-capability model across roughly <iterations> iterate-and-test turns is estimated at **$<manual-cost> (~<manual-credits> AI credits)**, a reduction of about <savings-pct>%.

> Estimates only. Token rates change. See `consumption-rates.md` for current rates, the dispatch-size estimator, and the calibration methodology. Token counts and iteration counts are illustrative, not guarantees.
```

### consumption-rates.md

Single maintainable rate table that isolates volatile per-model token pricing from agent logic, plus the dispatch-size estimator and the calibration factor. Uses replace semantics. The Scribe seeds it from this template when the file is missing **or when the existing file does not carry the required sections** (see the Scribe's Step 7 shape check), so a hand-edited or drifted table can never silently degrade every estimate. Because only this file holds token rates, a price change updates one table and never touches an agent prompt.

````markdown
---
description: "Per-model token rates, dispatch-size estimator, and calibration factor for squad consumption estimates"
---

# Consumption Rates (verify against the current GitHub Copilot "Models and pricing" docs)

* Billing model: usage-based billing (UBB), token-metered, effective 2026-06-01.
* Observed-on: <YYYY-MM-DD>. Source: <https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing>
* Credit conversion: 1 AI credit = $0.01 USD (fixed).
* All rates are USD per 1M tokens. Anthropic models bill a separate cache-write rate on top of cached input; models without one leave the column at 0.

## Per-model token rates in USD per 1M tokens (volatile, verify before commit)

| Model (as routed) | Tier     | Input | Cached | Cache write | Output | Notes                      |
| ----------------- | -------- | ----- | ------ | ----------- | ------ | -------------------------- |
| GPT-5.4 nano      | fast     | 0.20  | 0.02   | 0           | 1.25   | lightweight, read-heavy    |
| GPT-5.4 mini      | fast     | 0.75  | 0.075  | 0           | 4.50   | lightweight                |
| Claude Haiku 4.5  | fast     | 1.00  | 0.10   | 1.25        | 5.00   | lightweight reasoning      |
| Claude Sonnet 4.6 | default  | 3.00  | 0.30   | 3.75        | 15.00  | versatile                  |
| Claude Sonnet 5   | default  | 2.00  | 0.20   | 2.50        | 10.00  | versatile (promo pricing)  |
| GPT-5.4           | default  | 2.50  | 0.25   | 0           | 15.00  | versatile                  |
| Gemini 3.1 Pro    | default  | 2.00  | 0.20   | 0           | 12.00  | versatile                  |
| Claude Opus 4.8   | extended | 5.00  | 0.50   | 6.25        | 25.00  | high-capability reasoning  |
| Claude Opus 5     | extended | 5.00  | 0.50   | 6.25        | 25.00  | high-capability reasoning  |
| GPT-5.5           | extended | 5.00  | 0.50   | 0           | 30.00  | high-capability reasoning  |
| (additional)      |          |       |        |             |        | update when GitHub changes |

## Tier fallback rates (used only when `basis: tier-default`)

A tier is a routing preference, not a price. When the actual model is unknown, price the tier at its **most expensive member** rather than a blend: the observed failure mode of this ledger is undercounting, so the fallback is deliberately conservative-high and every row it produces is flagged `basis: tier-default`.

The `Priced as` column below names a model for **pricing only**. Never write it into a consumption block's `model` field — that field records what actually ran and is resolved per *Model Attribution* in `.github/instructions/squad/squad-state.instructions.md`, or left as the literal `unknown`. Copying a `Priced as` name into `model` is exactly the fabrication that makes a ledger report spend against a model the operator never chose.

| Tier     | Priced as         | Input | Cached | Cache write | Output |
| -------- | ----------------- | ----- | ------ | ----------- | ------ |
| fast     | Claude Haiku 4.5  | 1.00  | 0.10   | 1.25        | 5.00   |
| default  | Claude Sonnet 4.6 | 3.00  | 0.30   | 3.75        | 15.00  |
| extended | Claude Opus 5     | 5.00  | 0.50   | 6.25        | 25.00  |

## Dispatch-size estimator

A dispatch is **not one model call**. A dispatched subagent runs an internal tool loop, and every internal turn resends the accumulated context. Input therefore scales with `internal_turns × average_context`, not with a single prompt-and-reply pair. Pricing a dispatch as one call is what makes a ledger read an order of magnitude below the bill.

```text
tokens(bytes)      = bytes / 4
base_context       = agent prompt + auto-applied instructions + loaded skill content
average_context    = base_context + growth_per_turn × (internal_turns - 1) / 2
gross_input        = internal_turns × average_context
```

Split `gross_input` across the billed rates. Turn 1 is fully uncached; on turns 2..n the carried-forward prefix is a cached read and only the new tool result is fresh input:

```text
cached_tokens      = gross_input × 0.80
input_tokens       = gross_input × 0.20
cache_write_tokens = base_context + growth_per_turn × (internal_turns - 1)   (Anthropic models only; 0 otherwise)
output_tokens      = internal_turns × output_per_turn
```

Estimate `internal_turns` and `base_context` from what the dispatch actually reported. These class rows are **floors, not fallbacks** — start here and raise, never start below:

| Dispatch class            | Internal turns | Base context | Growth/turn | Output/turn |
| ------------------------- | -------------- | ------------ | ----------- | ----------- |
| Lookup / single-file read | 3              | 20,000       | 3,000       | 800         |
| Research / file survey    | 12             | 40,000       | 4,000       | 1,250       |
| Plan / synthesis          | 15             | 60,000       | 4,000       | 2,000       |
| Implement / edit loop     | 35             | 60,000       | 6,000       | 2,000       |
| Review / verification     | 18             | 50,000       | 4,000       | 1,500       |
| Council member opinion    | 10             | 50,000       | 4,000       | 1,500       |
| Scribe state write        | 4              | 15,000       | 3,000       | 800         |

Observable proxies that raise a floor whenever available: the number of files the agent reported reading and their byte size, the byte size of artifacts it wrote, the count of tool calls it reported, and the length of the findings it returned.

**Validity check.** After estimating, confirm `gross_input / internal_turns >= base_context` for the class. A derived average context below the floor means the dispatch was sized from the summary the coordinator handed over rather than from the dispatch's own context. That summary is a report *about* the dispatch, not the context the dispatch ran on — an agent's prompt plus its auto-applied instructions already exceeds most floors before it reads a single file. When the check fails, raise the numbers and recompute rather than recording the smaller figure.

## Orchestration overhead

The coordinator's own turns and each Scribe write consume tokens too, and they are dispatches the ledger would otherwise never see. Record them as a single `orchestration` row per run: one coordinator turn per dispatch round at the coordinator's own model, plus one `Scribe state write` class dispatch per Scribe hand-off.

## Cost formula

```text
raw_cost_usd = ( input_tokens       × input_rate
               + cached_tokens      × cached_rate
               + cache_write_tokens × cache_write_rate
               + output_tokens      × output_rate ) / 1e6
est_cost_usd = raw_cost_usd × calibration_factor
est_credits  = est_cost_usd / 0.01
```

## Calibration

```yaml
calibration_factor: 1.00
last_reconciled: never
observations: 0
```

The factor is the running mean of `observed_credits / estimated_credits` across reconciled runs, clamped to the range 0.25-10.0. To reconcile: read the per-user aggregate `ai_credits_used` from the Copilot usage-metrics REST API immediately before and after a run, take the delta as `observed_credits`, divide by the run's `est_credits` total, fold that ratio into the mean, and rewrite this block. Until `observations` is at least 1 the factor stays 1.00 and the ledger carries an "uncalibrated" note.

## Comparison methodology (token terms)

* `squad_cost = sum over dispatched roles of est_cost_usd`
* `manual_baseline = expected_iterations × baseline_model_cost_per_turn`, where a manual turn is itself priced through the dispatch-size estimator rather than as a single call
* `savings_pct = 1 - (squad_cost / manual_baseline)`

All values are labeled estimated, and token counts are estimated because no per-dispatch telemetry exists.
````

### Federation Seed Templates

The Squad Federation Coordinator hands these templates to the Squad Scribe when it creates a federation (after the user confirms the sub-squad set in Federation Init Mode). They stay consistent with `.github/instructions/squad/squad-federation.instructions.md`: `federation.md`, `meta-routing.md`, and the federation `state.json` use replace semantics; the federation `decisions.md` and `history/<sub-squad>.md` are append-only. Each `members/<name>/` sub-squad is seeded with the ordinary `team.md`, `routing.md`, `decisions.md`, `state.json`, and `history/` templates above, rooted at `members/<name>/`.

#### federation.md

Registry of the sub-squads in this repository. One row per sub-squad; the `Sub-squad` value is also its `members/<name>/` directory. `Kind` is `in-repo` for a sub-squad whose state lives under `members/<name>/`; `repo` is reserved for the deferred multi-repo federation.

```markdown
---
description: "Squad federation registry: the named sub-squads in this repository and the profile each was seeded from"
---

# Squad Federation

## Sub-Squads

| Sub-squad | Profile | Kind    | Location          | Owner         | Description                                              |
|-----------|---------|---------|-------------------|---------------|---------------------------------------------------------|
| product   | product | in-repo | members/product/  | business-team | Requirements, roadmap, and stakeholder deliverables     |
| azure     | azure   | in-repo | members/azure/    | architects    | Azure build: Bicep, landing-zone, cost, and deployment  |
```

#### meta-routing.md

Maps a request pattern or domain to a registered sub-squad. Seeded from each sub-squad's profile and description; every row points at a sub-squad that exists in `federation.md`.

```markdown
---
description: "Squad federation meta-routing: request patterns mapped to the sub-squad that handles them"
---

# Squad Federation Meta-Routing

| Pattern / Domain                                                 | Sub-squad | Parallel-Eligible |
|------------------------------------------------------------------|-----------|-------------------|
| requirements, PRD, BRD, roadmap, backlog, stakeholder, discovery | product   | yes               |
| Azure, Bicep, landing zone, deploy, IaC, cost, infrastructure    | azure     | yes               |
```

#### decisions.md (federation root)

Append-only log of federation-level routing decisions — which sub-squad handled a request and why. Each entry references the sub-squad's own decision entries so the two levels stay linked. Uses the same append-only contract as a per-squad `decisions.md`.

```markdown
---
description: "Append-only log of squad federation routing decisions and their rationale"
---

# Squad Federation Decisions

Entries are appended below in chronological order. Each entry records which sub-squad(s) a request was routed to, the matched meta-routing pattern or explicit `squad=` target, the turn it was made on, and a reference to the sub-squad's own decision entries. Prior entries are never edited or removed.

<!-- Append new federation decision entries below this line. -->
```

#### state.json (federation root)

Machine-readable federation status. Replace semantics — the Scribe overwrites it as the federation advances.

```json
{
  "schemaVersion": "1.2",
  "updated": "",
  "turn": 0,
  "mode": "interactive",
  "subSquads": [],
  "activeSubSquads": [],
  "openEscalations": [],
  "currentRun": {
    "sessionModel": "",
    "modelOverrides": {},
    "estCostUsd": 0,
    "estCreditsTotal": 0
  }
}
```

`subSquads` lists every registered sub-squad name (mirroring `federation.md`); `activeSubSquads` lists the sub-squad(s) dispatched on the current turn. `currentRun.sessionModel` and `currentRun.modelOverrides` are the federation-wide defaults a sub-squad inherits unless its own `state.json` sets them. Each sub-squad keeps its own `state.json` under `members/<name>/` per `.github/instructions/squad/squad-state.instructions.md`.

`mode` and `currentRun` are additive fields for federation-level autopilot (`.github/instructions/squad/squad-federation-autopilot.instructions.md`). `mode` records the autonomy mode in effect for the current federation turn (`interactive` or `autopilot`); `currentRun` aggregates the estimated cost and credits summed across every sub-squad inner run of the current meta-run, so the federation-level cost ceiling reads one number. All of these are backward-compatible — a federation that never runs autopilot leaves `mode` at `interactive` and `currentRun` at zero, and `sessionModel` / `modelOverrides` default to empty — so the `schemaVersion` bumps (`1.0` → `1.1` for autopilot, `1.1` → `1.2` for model attribution) keep existing federation state valid.

#### history/autopilot-run-\<id>.md (federation root)

One file per federation autopilot meta-run, at the federation root. Append-only by topic-id: a subsequent meta-run against the same topic appends a new dated `## Meta-Stages` section rather than overwriting. The Scribe writes this file only when the Federation Coordinator runs in `mode=autopilot` with no `squad=` target (a single-target `mode=autopilot` forwards to one sub-squad and writes only that sub-squad's own `members/<name>/history/autopilot-run-<id>.md`).

```markdown
---
description: "Federation autopilot meta-run summary for topic <id>"
---

# Federation Autopilot Run: <id>

* Topic: <one-line summary>
* Opt-In: mode=autopilot (no squad= target)
* Cost Ceiling: <value or unset>
* Aggregate Cost: <est-usd> (~<est-credits> AI credits, estimated, not billed)
* Outcome: completed (awaiting final validation) | escalated (<reason>) | stopped (<reason>)

## Meta-Stages

| Order | Sub-squad | Inner Run                                        | Result             | Gate Fired (attributed)     |
|-------|-----------|--------------------------------------------------|--------------------|-----------------------------|
| 1     | <name>    | members/<name>/history/autopilot-run-<inner>.md  | <one-line outcome> | <none or gate + sub-squad>  |
| 2     | <name>    | members/<name>/history/autopilot-run-<inner>.md  | <one-line outcome> | <none or gate + sub-squad>  |
| final | (federation) | consolidated final-outcome                    | notified <recipient-or-in-chat> | Final-Outcome Validation |

## Gates and Approvals

| Timestamp | Gate                       | Raised By (sub-squad) | Awaiting / Resolved By      | Notes      |
|-----------|----------------------------|-----------------------|-----------------------------|------------|
| <ts>      | <Impactful / Risk / Final> | <sub-squad>           | <human decision or pending> | <one-line> |
```

Each row's `Inner Run` links the sub-squad's own `members/<name>/history/autopilot-run-<inner>.md`, so the two levels of provenance stay linked and auditable.

## Attribution

Brought to you by the `hve-squad` package, built on Microsoft HVE Core agents and conventions.
