---
description: "Squad routing rules mapping request patterns to roles, autonomy tiers, and parallel eligibility"
applyTo: '**/.copilot-tracking/squad/**'
---

# Squad Routing Conventions

These conventions define how the Squad Coordinator classifies a user request and selects which roles to dispatch. The coordinator reads the routing table at the start of every turn, matches the request against the patterns, and dispatches the assigned roles at the indicated autonomy tier.

Routing decides *who acts*. The roster (`squad-roster.instructions.md`) decides *which agent fills each role*, and the state conventions (`squad-state.instructions.md`) decide *how outcomes persist*.

## Routing File

The routing table lives at `.copilot-tracking/squad/routing.md`. The coordinator creates it on first use from the default rules below and updates it only through the Squad Scribe.

The file begins with YAML frontmatter and a single H1 title, then a routing table. Each row maps a request pattern to one or more roles, an autonomy tier, and a parallel-eligible flag.

### Routing Schema

The routing table uses these columns:

| Column            | Meaning                                                                              |
|-------------------|--------------------------------------------------------------------------------------|
| Pattern / Keyword | The request trigger the coordinator matches (intent keywords or phrasing)            |
| Role(s)           | The squad role or roles dispatched for the match, resolved through the roster        |
| Autonomy Tier     | How much latitude the role has: `auto`, `confirm`, or `escalate`                     |
| Parallel-Eligible | `yes` when the role can run concurrently with other independent roles; `no` when not |

### Autonomy Tiers

* `auto` — The role proceeds and returns findings without pausing; suitable for read-only research and review.
* `confirm` — The role drafts an action or plan and the coordinator confirms before any change lands.
* `escalate` — The coordinator stops and routes the decision to the user before dispatching (see Escalation).
* `auto-validated` — Opt-in tier defined in `.github/instructions/squad/squad-autonomous.instructions.md`. Runs an implementation role and the council in a bounded re-validation loop (max 2 cycles) on a single turn. Engaged through the `/squad` prompt input `mode=autonomous`. Never downgrades `confirm` for cost-impacting or irreversible-write actions and always escalates on the mandatory triggers listed in the autonomous conventions (Stop verdicts, Risk: High findings from security/cost/RAI, compliance violations, irreversible writes).

## Default Routing Rules

The coordinator seeds `routing.md` with these defaults. Each rule references a real deployed HVE Core agent through its squad role. Adjust per project, but keep every rule pointing at an agent that exists in the roster.

| Pattern / Keyword                          | Role(s)                | Autonomy Tier | Parallel-Eligible |
|--------------------------------------------|------------------------|---------------|-------------------|
| research, investigate, explore, find out   | Task Researcher        | auto          | yes               |
| plan, break down, sequence, design plan    | Task Planner           | confirm       | no                |
| implement, build, code, fix                | Task Implementor       | confirm       | no                |
| review, validate, check quality            | Task Reviewer          | auto          | yes               |
| validate requirements, requirements readiness, requirements complete, requirements clear, intake check, are the requirements ready | intake-validator | auto | yes |
| security, threat, vulnerability, STRIDE    | Security Planner       | confirm       | yes               |
| design, UX, UI, wireframe, accessibility   | UX UI Designer         | confirm       | yes               |
| requirements, BRD, PRD, user story, acceptance criteria | PRD Builder | confirm       | yes               |
| journey map, persona, design thinking, empathize, ideate, problem statement | DT Coach | confirm | yes               |
| roadmap, backlog, epic, sprint, refine, prioritize, story | Agile Coach | confirm    | no                |
| experiment, hypothesis, validate assumption, MVE, riskiest assumption | Experiment Designer | confirm | yes        |
| presentation, deck, slides, executive summary, pitch | PowerPoint Builder | confirm | no                |
| document, write up, summarize for stakeholders, readme | Doc Ops    | confirm       | no                |
| architecture, system design, components    | System Architecture Reviewer | auto    | yes               |
| responsible AI, RAI, fairness, harm        | RAI Planner            | confirm       | yes               |
| verify finding, confirm claim, fact-check  | Finding Deep Verifier  | auto          | yes               |
| author IaC, write Bicep, write Terraform, convert LLD to infra, infrastructure as code | Squad IaC Author | confirm | no |
| deploy, provision, what-if, terraform plan, terraform apply, az deployment | Squad Deployer | confirm | no |
| as-built, resource inventory, compliance matrix, operations runbook, DR plan, document deployed infrastructure | asbuilt-author | confirm | no |
| diagnose, troubleshoot, resource health, why is resource failing, investigate deployed, policy check | azure-diagnose | auto | yes |
| validate, cross-check, pre-implementation review, council, design review, go/no-go, implement-and-cost, implement-and-risk | architect, security, cost-manager, product-owner, rai (optional) | confirm | yes |
| modernize, upgrade framework, migrate, port legacy, .NET upgrade, Java migration, dependency upgrade, containerize | modernizer | confirm | no |
| sql migration, database migration, schema migration, data migration, sql server to azure, downtime migration plan, cutover strategy | modernizer | confirm | no |
| re-platform, rewrite, port to, rebuild in, cross-stack rewrite, Node to .NET, React to Angular, convert to another language | modernizer | confirm | no |

### Filtering to the Active Roster

The seeded `routing.md` contains only the rules whose role exists in the project's `team.md`. When a profile (see *Squad Profiles* in `squad-roster.instructions.md`) seeds a subset of the cast, the Squad Scribe drops every routing row whose role is not on the seeded team. This keeps routing consistent with the chosen squad: the coordinator never matches a request to a role the project did not hire.

When a request matches a pattern whose role is absent from the active roster, the coordinator escalates (see Escalation) and offers to add the role or switch profiles rather than dispatching a role that is not on the team.

## Dispatch Rules

* Match the most specific pattern first. When several patterns match, prefer the one whose role most directly owns the requested outcome.
* Dispatch all parallel-eligible roles for a turn concurrently; run non-parallel roles (such as planning and implementation) sequentially.
* Resolve every matched role through the roster before dispatch. If a role maps to **thin charter needed**, escalate rather than guessing a substitute.
* Apply cost-first model selection: prefer the `fast` tier for read-heavy `auto` roles and reserve the `default` tier for reasoning-heavy `confirm` roles.

### Intake Gate

Before dispatching any planning-, implementation-, or deliverable-producing role whose work is **grounded in requirement or input artifacts**, the coordinator runs the intake gate defined in `.github/instructions/squad/squad-intake-gate.instructions.md`. The gate is conditional: it fires only when (1) one or more requirement or input artifacts (a PRD, BRD, specification, requirements document, user story, design document, transcript, or a user-referenced input file) are in scope, and (2) the turn advances toward a plan, a build, or a deliverable that consumes them. When no input artifact grounds the work, the gate is a no-op and routing proceeds unchanged.

When it fires:

* The coordinator dispatches `intake-validator` (resolved by input type per the roster Selection Cue) to assess completeness, clarity, testability, consistency, and scope boundaries, and hands its finding to the Scribe, which appends an `## Intake Readiness Verdict` to `decisions.md`.
* On `Ready` or `Ready-With-Gaps`, downstream dispatch proceeds (any non-blocking gaps are carried as recorded assumptions).
* On `Not-Ready`, the coordinator runs the bounded auto-remediation loop — dispatch `analyst` or `product-owner` to fill the blocking gaps, then re-validate; capped at two cycles — before it proceeds, and escalates to the user when a gap needs a human decision, when the cap is reached with blocking gaps still open, or when the blocking-gap set stops shrinking.
* A non-stale `Ready` verdict for the same unchanged inputs is reused rather than re-run.
* When the active roster does not carry `intake-validator` (profiles other than `product` and `full`), the coordinator escalates and offers to add the role rather than skipping the check.

The intake gate runs ahead of the Implementation Gate: ready inputs precede research and planning, which in turn precede implementation.

### Implementation Gate

Before dispatching an implementation-tier role (any role at `confirm` or `auto-validated` tier whose pattern indicates implementation, build, deploy, or merge), the coordinator checks `.copilot-tracking/squad/decisions.md` for the latest `## Council Verdict` entry on the matching topic id.

The coordinator first confirms the methodology artifacts exist on disk. Implementation may not begin "cold":

* A research artifact exists under `.copilot-tracking/research/` for the topic. If missing, dispatch `researcher` first.
* A plan artifact exists under `.copilot-tracking/plans/` for the topic. If missing, dispatch `lead` (planning) first.
* A non-`Stop` Council Verdict exists for the topic when the request crosses two or more council-member domains. If missing, run the council row first.

When any precondition is unmet, the coordinator dispatches the missing stage (or escalates) instead of implementing. It never produces the missing research, plan, or verdict itself. With the preconditions met, the gate behavior is:

* When no Council Verdict exists for the topic and the request crosses two or more council-member domains (architecture, security, cost, product-fit, RAI), the coordinator runs the council row before the implementer.
* When the latest verdict is `Go` or `Go-With-Conditions`, the coordinator dispatches the implementer and passes the consolidated conditions as inputs.
* When the latest verdict is `Stop`, the coordinator escalates instead of dispatching. The user may explicitly override `Stop`, in which case the coordinator records the override through the Scribe before any implementer dispatches.

The gate enforces the council protocol from `.github/instructions/squad/squad-council.instructions.md` and the autonomous loop from `.github/instructions/squad/squad-autonomous.instructions.md` at routing time.

### Review Follow-Through

The methodology does not end at implementation. After any implementation-tier role lands a change, the coordinator dispatches `tester` (review) as the closing stage before it reports the work complete — in every mode (interactive, autonomous, and autopilot). Review is an `auto`-tier, non-destructive read, so it runs without a separate gate. This makes the methodology symmetric: research and plan precede implementation, and review follows it, so Research → Plan → Implement → Review is enforced end-to-end.

* Resolve `tester` to the matching review agent per the roster Selection Cue — for example `Code Review Full` for a pre-PR review, or `Implementation Validator` for an implementation-vs-design check — and fold its findings into the turn summary.
* Every profile carries `tester` through the methodology spine (see `squad-roster.instructions.md`), so the review stage is always available. When a user has explicitly removed `tester` from the roster, the coordinator reports that the change closed unreviewed and recommends re-adding the role rather than silently skipping review.

## Escalation

The coordinator escalates to the user, rather than dispatching, when any of these hold:

* The matched rule is at the `escalate` tier.
* No routing pattern matches the request with reasonable confidence.
* A matched role resolves to **thin charter needed** in the roster.
* Two rules conflict and no pattern is clearly more specific.

On escalation, the coordinator states the ambiguity, lists the candidate roles, and asks the user to choose before any role acts.
