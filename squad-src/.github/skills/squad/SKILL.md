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

This skill packages the coordinator's operating procedure and the seed templates it stamps out on first run. It complements eight instruction files that auto-apply when squad state is touched:

* `.github/instructions/squad/squad-roster.instructions.md` — roster schema and cast catalog.
* `.github/instructions/squad/squad-routing.instructions.md` — routing table and escalation rules.
* `.github/instructions/squad/squad-state.instructions.md` — state layout, single-writer ownership, and tool-to-mechanism mapping.
* `.github/instructions/squad/squad-council.instructions.md` — pre-implementation council protocol with parallel dispatch, most-restrictive-wins synthesis, and the Council Verdict schema.
* `.github/instructions/squad/squad-autonomous.instructions.md` — opt-in `auto-validated` autonomy tier with a bounded re-validation loop, divergence detection, and mandatory escalation triggers.
* `.github/instructions/squad/squad-autopilot.instructions.md` — opt-in `mode=autopilot` full pipeline (research→plan→implement→review) with Human Gates only on impactful actions and final-outcome validation.
* `.github/instructions/squad/squad-notifications.instructions.md` — user-contact capture at squad build time and the delivery-agnostic notification (ping) contract per mode.
* `.github/instructions/squad/squad-watch-mode.instructions.md` — event-driven Watch Mode (DR-01) trigger contract: opt-in gates, event-to-intent map, injection-safe payloads, and the pull-request deliverable.

## Prerequisites

* A `runSubagent` or `task` tool is available so the coordinator can dispatch `user-invocable: false` agents.
* The deployed HVE Core cast exists (Task Researcher, Task Planner, Task Implementor, Task Reviewer, System Architecture Reviewer, Security Planner, RAI Planner, UX UI Designer, Finding Deep Verifier) plus the Squad Scribe.
* The memory tool is available for durable per-agent notes under `/memories/repo/`.

## Procedure

The coordinator runs four stages each turn: **init**, **route**, **decide**, and **handoff**. Only the coordinator initiates state changes, and only the Squad Scribe performs the writes.

### Squad Profiles

A profile is a curated subset of the cast tailored to a kind of project. The coordinator seeds only the profile's members into `team.md`, and the routing table is filtered to those roles. The `scribe` role is always included, and so is the **methodology spine** (`researcher`, `lead`, `developer`, `tester`) that runs the Research → Plan → Implement → Review cycle in every profile. Profiles are defined canonically in `.github/instructions/squad/squad-roster.instructions.md`; the catalog below mirrors them.

| Profile        | Members                                                                                                                       | Use When                                                                                     |
|----------------|-------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `default`      | researcher, lead, developer, tester, scribe                                                                                   | General-purpose work; recommended starting point                                             |
| `full`         | researcher, lead, developer, tester, architect, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, security, rai, designer, fact-checker, cost-manager, modernizer, scribe | Complex, cross-cutting projects that need every discipline                                  |
| `security`     | researcher, lead, developer, tester, security, rai, fact-checker, scribe                                                      | Security, threat-modeling, and responsible-AI focus                                          |
| `design`       | researcher, lead, developer, tester, designer, scribe                                                                         | UX/UI and product-design focus                                                               |
| `architecture` | researcher, lead, developer, tester, architect, azure-architect, cost-manager, scribe                                        | System design and architecture focus                                                         |
| `azure`        | researcher, lead, developer, tester, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, architect, cost-manager, security, modernizer, scribe | Azure-focused build with budget and security oversight (Bicep, landing-zone, FinOps signals) |
| `product`      | researcher, lead, developer, tester, analyst, designer, product-owner, presenter, technical-writer, experimenter, scribe | Business discovery and delivery — requirements, design thinking, roadmap, and stakeholder deliverables (often non-technical) |

### Init

Run once per project, then verify on every turn. Init Mode mirrors a propose → confirm → create flow and never writes files before the user confirms.

1. Check for `.copilot-tracking/squad/team.md` and `.copilot-tracking/squad/routing.md`.
2. When either file is missing, **propose**: discover the project (languages, frameworks, tests, IaC, security/AI markers) read-only, then recommend a profile using the precedence in the roster's *Profile Selection* (explicit `profile=` hint → discovery inference → `default`). Present the profile under consideration — the user's `profile=` choice when given, otherwise the most appropriate profile the coordinator selected — with its roles and why it fits, and ask the user to proceed or choose differently. On **proceed** the flow is unchanged; on **decline** the user either picks a different profile from the listed set or builds a custom roster from the role menu (each role shown with a plain-language description), with `scribe` and the methodology spine preselected by default, per the roster's *Building a Custom Roster*. Once a profile or customized roster is on the table, also offer naming choices for the seeded members per the roster's *Naming Conventions* (user-supplied per role, coordinator-assigned aliases from the deterministic wordlist, a mix, or skip). Wait on the user before any write.
3. On **confirm**, hand the chosen roster to the Squad Scribe to **create**: `team.md` from the confirmed profile's members (including the `Member Name` column when names were provided), `routing.md` from the default routing rules filtered to that roster, plus `decisions.md`, `notifications.md`, `state.json`, and a `history/` directory. Before the create step, capture an optional approval channel per `.github/instructions/squad/squad-notifications.instructions.md` (`github-issue` for remote/unattended approval, `webhook`, or `in-chat`) and seed it into the `state.json` `notify` object.
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

1. Hand each dispatched agent's request and outcome to the Squad Scribe, which appends them to `history/<agent>.md` (append-only) along with the per-dispatch consumption block (the model used plus estimated input, cached, and output token cost and credits), then rewrites the `consumption.md` ledger and updates the `state.json` `currentRun` totals. The consumption block is written for every dispatch, never conditionally: the coordinator always supplies at least the resolved role's model tier, and when it omits the payload the Scribe self-derives a `tier-default` estimate, so a history append never lands without its consumption block and the ledger never stays at its seed while dispatches have run. Every consumption figure is an estimate.
2. Synthesize the collected findings into a concise answer for the user.
3. Escalate to the user — rather than acting — when the matched rule is at the `escalate` tier, no pattern matches with reasonable confidence, a role resolves to **thin charter needed**, or two rules conflict with no clearly more specific match. State the ambiguity, list the candidate roles, and ask the user to choose.

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
2. The coordinator sequences the pipeline: research → plan → pre-implementation council → implement (via the autonomous validator loop) → review → final-outcome validation, advancing stage-to-stage without a human turn. For a profile that carries two or more deliverable-producing roles (the `product` profile), the implement stage fans out across the owning specialists — the plan enumerates the deliverables and the coordinator dispatches each specialist in dependency order, each a Scribe-recorded stage — instead of a single `developer`; every other (spine-shaped) profile keeps the single-build implement stage.
3. The pipeline stops only at two Human Gate classes: an **Impactful-Action Gate** (deploy, `git push`/force-push, PR merge, schema migration, data deletion, destructive infra ops, secret rotation, or any user-marked irreversible action) and a **Risk Gate** (any `Stop` verdict, `Risk: High` from security/cost/RAI, `confirm`-tier cost move, compliance violation, validator divergence, or cost-ceiling breach).
4. Autopilot never auto-releases: after review it fires a `final-outcome` notification to the registered contact and waits for human validation before any release-tier action.
5. The Scribe writes a per-run summary to `history/autopilot-run-<id>.md` (append-only by topic-id) and the notification records to `notifications.md`.

### Notification Procedure

The squad captures an optional contact at build time and pings it for approvals. The full contract lives in `.github/instructions/squad/squad-notifications.instructions.md`; the operator's view is:

1. During Init Mode the coordinator asks for an optional approval channel and seeds it into `state.json` under `notify`. The choices are `github-issue` (recommended for unattended/VM runs — approvable from a phone), `webhook` (outbound team ping only), or `in-chat` (default).
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

Seeded from the confirmed profile's members; the template below shows the `full` profile (the entire cast catalog). For other profiles, only the profile's rows are written. The `Member Name` column is populated from the Init Mode naming step: it may be empty for roles the user chose not to name, and it must be unique within a `Role` when two rows share the same role. The role-to-agent relationship is many-to-many: each role names one **Primary** agent the coordinator dispatches by default plus optional **Alternate** agents it resolves to per the cast catalog's Selection Cue (see `squad-roster.instructions.md`). The `devrel` role has no deployed HVE Core agent and is left as **thin charter needed** until a charter is authored.

```markdown
---
description: "Squad roster: roles and the deployed HVE Core agents that fill them"
---

# Squad Roster

## Members

| Role            | Member Name | Agent Name (Primary)         | Alternate Agents                                       | Invocation         | Model Tier              |
|-----------------|-------------|------------------------------|--------------------------------------------------------|--------------------|-------------------------|
| lead            | Alpha       | Task Planner                 | RPI Agent, Phase Implementor, Task Challenger          | runSubagent / task | default                 |
| researcher      | Beta        | Task Researcher              | Researcher Subagent, Codebase Profiler, Meeting Analyst | runSubagent / task | fast                    |
| developer       | Gamma       | Task Implementor             | Phase Implementor                                      | runSubagent / task | default                 |
| tester          | Delta       | Task Reviewer                | Code Review Full, PR Review, Plan Validator            | runSubagent / task | fast                    |
| architect       | Epsilon     | System Architecture Reviewer | Arch Diagram Builder, ADR Creator                      | runSubagent / task | default                 |
| azure-architect | Zeta        | Squad Azure Architect        | —                                                      | runSubagent / task | default                 |
| security        | Eta         | Security Planner             | Security Reviewer, SSSC Planner, Finding Deep Verifier | runSubagent / task | default                 |
| rai             | Theta       | RAI Planner                  | —                                                      | runSubagent / task | default                 |
| designer        | Iota        | UX UI Designer               | DT Coach, DT Learning Tutor                            | runSubagent / task | default                 |
| fact-checker    | Kappa       | Finding Deep Verifier        | —                                                      | runSubagent / task | fast                    |
| cost-manager    | Lambda      | Squad Cost Manager           | —                                                      | runSubagent / task | default                 |
| iac-author      | Mu          | Squad IaC Author             | —                                                      | runSubagent / task | default                 |
| deployer        | Nu          | Squad Deployer               | —                                                      | runSubagent / task | default                 |
| asbuilt-author  | Xi          | Squad As-Built Author        | —                                                      | runSubagent / task | default                 |
| azure-diagnose  | Omicron     | Squad Azure Diagnose         | —                                                      | runSubagent / task | fast                    |
| modernizer      | Pi          | Squad Modernization Planner  | Squad SQL Migration Advisor                            | runSubagent / task | default                 |
| scribe          |             | Squad Scribe                 | Memory                                                 | runSubagent / task | fast                    |
| devrel          |             | —                            | —                                                      | —                  | — (thin charter needed) |
```

### routing.md

Seeded from the default routing rules. Each rule points at a role that exists in `team.md`.

```markdown
---
description: "Squad routing: request patterns mapped to roles, autonomy tiers, and parallel eligibility"
---

# Squad Routing

| Pattern / Keyword                          | Role(s)                      | Autonomy Tier | Parallel-Eligible |
|--------------------------------------------|------------------------------|---------------|-------------------|
| research, investigate, explore, find out   | Task Researcher              | auto          | yes               |
| plan, break down, sequence, design plan    | Task Planner                 | confirm       | no                |
| implement, build, code, fix                | Task Implementor             | confirm       | no                |
| review, validate, check quality            | Task Reviewer                | auto          | yes               |
| security, threat, vulnerability, STRIDE    | Security Planner             | confirm       | yes               |
| design, UX, UI, wireframe, accessibility   | UX UI Designer               | confirm       | yes               |
| architecture, system design, components    | System Architecture Reviewer | auto          | yes               |
| responsible AI, RAI, fairness, harm        | RAI Planner                  | confirm       | yes               |
| verify finding, confirm claim, fact-check  | Finding Deep Verifier        | auto          | yes               |
| author IaC, write Bicep, write Terraform, convert LLD to infra, infrastructure as code | Squad IaC Author | confirm | no |
| deploy, provision, what-if, terraform plan, terraform apply, az deployment | Squad Deployer | confirm | no |
| as-built, resource inventory, compliance matrix, operations runbook, DR plan, document deployed infrastructure | asbuilt-author | confirm | no |
| diagnose, troubleshoot, resource health, why is resource failing, investigate deployed, policy check | azure-diagnose | auto | yes |
| validate, cross-check, pre-implementation review, council, design review, go/no-go, implement-and-cost, implement-and-risk | architect, security, cost-manager, product-owner, rai (optional) | confirm | yes |
| modernize, upgrade framework, migrate, port legacy, .NET upgrade, Java migration, dependency upgrade, containerize | modernizer | confirm | no |
| sql migration, database migration, schema migration, data migration, sql server to azure, downtime migration plan, cutover strategy | modernizer | confirm | no |
| re-platform, rewrite, port to, rebuild in, cross-stack rewrite, Node to .NET, React to Angular, convert to another language | modernizer | confirm | no |
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
```

### history/<agent>.md

One append-only file per dispatched agent. Replace `<agent>` with the dispatched agent's name (for example, `history/Task Researcher.md`). The header is created with the file; dispatch records are appended. Autonomous-loop runs add per-cycle dispatch entries to each role's history file using the placeholder shape below.

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
  "schemaVersion": "1.2",
  "updated": "",
  "turn": 0,
  "mode": "interactive",
  "activeRoles": [],
  "openEscalations": [],
  "currentRun": {
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

```markdown
---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: <run-id>)

| Role      | Member | Agent   | Model   | Tier   | In Tokens | Cached | Out Tokens | Est. Cost (USD) | Est. Credits |
|-----------|--------|---------|---------|--------|-----------|--------|------------|-----------------|--------------|
| <role>    |        | <agent> | <model> | <tier> | 0         | 0      | 0          | 0.0000          | 0.00         |
| **Total** |        |         |         |        | **0**     | **0**  | **0**      | **$0.00**       | **0.00**     |

> Basis: estimated. No per-dispatch token telemetry exists; the runtime exposes only the per-user aggregate `ai_credits_used` via the Copilot usage-metrics REST API (optional post-hoc reconciliation). Token rates come from `consumption-rates.md` (observed <date>). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$<squad-cost> (~<squad-credits> AI credits)** across <n> specialized agents, routing read-heavy roles to lightweight models and reserving high-output reasoning models only where needed. Reproducing the same outcome by manually prompting a single high-capability model across roughly <iterations> iterate-and-test turns is estimated at **$<manual-cost> (~<manual-credits> AI credits)**, a reduction of about <savings-pct>%.

> Estimates only. Token rates change. See `consumption-rates.md` for current rates and methodology. Token counts and iteration counts are illustrative, not guarantees.
```

### consumption-rates.md

Single maintainable rate table that isolates volatile per-model token pricing from agent logic. Uses replace semantics. The Scribe seeds it from this template on first run when the file is missing; every rate cell ships as a `<verify>` placeholder until confirmed against the current GitHub Copilot "Models and pricing" docs (verify before commit). Because only this file holds token rates, a price change updates one table and never touches an agent prompt.

```markdown
---
description: "Maintainable per-model token-rate table and comparison methodology for squad consumption estimates"
---

# Consumption Rates (verify against the current GitHub Copilot "Models and pricing" docs)

* Billing model: usage-based billing (UBB), token-metered, effective 2026-06-01.
* Observed-on: <YYYY-MM-DD>. Source: <https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing>
* Credit conversion: 1 AI credit = $0.01 USD (fixed).

## Per-model token rates in USD per 1M tokens (volatile, verify before commit)

| Model (as routed)   | Tier    | Input    | Cached   | Output   | Notes                      |
|---------------------|---------|----------|----------|----------|----------------------------|
| GPT-5.4 nano        | fast    | <verify> | <verify> | <verify> | lightweight, read-heavy    |
| Claude Haiku 4.5    | fast    | <verify> | <verify> | <verify> | lightweight reasoning      |
| Claude Sonnet 4.6   | default | <verify> | <verify> | <verify> | versatile                  |
| Claude Opus 4.8     | default | <verify> | <verify> | <verify> | high-capability reasoning  |
| (additional models) |         | <verify> | <verify> | <verify> | update when GitHub changes |

## Comparison methodology (token terms)

* `est_cost_usd = (input_tokens × input_rate + cached_tokens × cached_rate + output_tokens × output_rate) / 1e6`
* `est_credits = est_cost_usd / 0.01`
* `squad_cost = sum over dispatched roles of est_cost_usd`
* `manual_baseline = expected_iterations × baseline_model_cost_per_turn`
* `savings_pct = 1 - (squad_cost / manual_baseline)`

All values are labeled estimated, and token counts are estimated because no per-dispatch telemetry exists. Optionally reconcile the run total against the per-user aggregate `ai_credits_used` from the usage-metrics REST API after the run.
```

## Attribution

Brought to you by the `hve-squad` package, built on Microsoft HVE Core agents and conventions.
