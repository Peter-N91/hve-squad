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

## Default Routing Rules

The coordinator seeds `routing.md` with these defaults. Each rule references a real deployed HVE Core agent through its squad role. Adjust per project, but keep every rule pointing at an agent that exists in the roster.

| Pattern / Keyword                          | Role(s)                | Autonomy Tier | Parallel-Eligible |
|--------------------------------------------|------------------------|---------------|-------------------|
| research, investigate, explore, find out   | Task Researcher        | auto          | yes               |
| plan, break down, sequence, design plan    | Task Planner           | confirm       | no                |
| implement, build, code, fix                | Task Implementor       | confirm       | no                |
| review, validate, check quality            | Task Reviewer          | auto          | yes               |
| security, threat, vulnerability, STRIDE    | Security Planner       | confirm       | yes               |
| design, UX, UI, wireframe, accessibility   | UX UI Designer         | confirm       | yes               |
| architecture, system design, components    | System Architecture Reviewer | auto    | yes               |
| responsible AI, RAI, fairness, harm        | RAI Planner            | confirm       | yes               |
| verify finding, confirm claim, fact-check  | Finding Deep Verifier  | auto          | yes               |

### Filtering to the Active Roster

The seeded `routing.md` contains only the rules whose role exists in the project's `team.md`. When a profile (see *Squad Profiles* in `squad-roster.instructions.md`) seeds a subset of the cast, the Squad Scribe drops every routing row whose role is not on the seeded team. This keeps routing consistent with the chosen squad: the coordinator never matches a request to a role the project did not hire.

When a request matches a pattern whose role is absent from the active roster, the coordinator escalates (see Escalation) and offers to add the role or switch profiles rather than dispatching a role that is not on the team.

## Dispatch Rules

* Match the most specific pattern first. When several patterns match, prefer the one whose role most directly owns the requested outcome.
* Dispatch all parallel-eligible roles for a turn concurrently; run non-parallel roles (such as planning and implementation) sequentially.
* Resolve every matched role through the roster before dispatch. If a role maps to **thin charter needed**, escalate rather than guessing a substitute.
* Apply cost-first model selection: prefer the `fast` tier for read-heavy `auto` roles and reserve the `default` tier for reasoning-heavy `confirm` roles.

## Escalation

The coordinator escalates to the user, rather than dispatching, when any of these hold:

* The matched rule is at the `escalate` tier.
* No routing pattern matches the request with reasonable confidence.
* A matched role resolves to **thin charter needed** in the roster.
* Two rules conflict and no pattern is clearly more specific.

On escalation, the coordinator states the ambiguity, lists the candidate roles, and asks the user to choose before any role acts.
