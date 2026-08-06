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
| research, investigate, explore, find out   | researcher             | auto          | yes               |
| plan, break down, sequence, design plan    | lead                   | confirm       | no                |
| implement, build, code, fix                | developer              | confirm       | no                |
| review, validate, check quality            | tester                 | auto          | yes               |
| write tests, add test coverage, run the tests, test plan, test case, edge case, boundary case, hostile input, reproduce the bug, regression test, flaky test, exploratory testing | qa-engineer | confirm | no |
| challenge, pressure-test, poke holes, devil's advocate, what could go wrong | challenger | auto | yes               |
| author prompt, write agent file, refactor instructions, analyse skill | prompt-engineer | confirm | no               |
| validate requirements, requirements readiness, requirements complete, requirements clear, intake check, are the requirements ready | intake-validator | auto | yes |
| security, threat, vulnerability, STRIDE    | Security Planner       | confirm       | yes               |
| supply chain, SBOM, SLSA, provenance, OpenSSF Scorecard, Sigstore, signed release, dependency pinning | supply-chain | confirm | yes               |
| CVE, vulnerability triage, VEX, OpenVEX, exploitability, is this CVE exploitable, advisory disposition, not affected | vuln-manager | confirm | yes         |
| privacy, personal data, PII, DPIA, GDPR, data subject, retention | privacy         | confirm       | yes               |
| accessibility, a11y, WCAG, ARIA, screen reader, keyboard navigation, Section 508, EN 301 549, VPAT, conformance audit | accessibility | confirm | yes           |
| design, UX, UI, wireframe, journey, interaction design | UX UI Designer     | confirm       | yes               |
| requirements, BRD, PRD, user story, acceptance criteria | PRD Builder | confirm       | yes               |
| journey map, persona, design thinking, empathize, ideate, problem statement | DT Coach | confirm | yes               |
| roadmap, backlog, epic, sprint, refine, prioritize, story | Agile Coach | confirm    | no                |
| create work items in ADO, push backlog to Azure DevOps, create Jira issues, apply the handoff, execute handoff, sync work items to the tracker | backlog-executor | confirm | no |
| GitLab merge request, GitLab pipeline, GitLab issue, open an MR | product-owner    | escalate      | no                |
| experiment, hypothesis, validate assumption, MVE, riskiest assumption | Experiment Designer | confirm | yes        |
| presentation, deck, slides, executive summary, pitch | presenter    | confirm       | no                |
| document, write up, summarize for stakeholders, readme | technical-writer | confirm  | no                |
| data profile, data dictionary, EDA, exploratory analysis, notebook, dashboard, dataset, Power BI, DAX, semantic model, star schema, report design, Fabric, Lakehouse, OneLake | data-scientist | confirm | no |
| architecture, system design, components    | System Architecture Reviewer | auto    | yes               |
| responsible AI, RAI, fairness, harm        | RAI Planner            | confirm       | yes               |
| verify finding, confirm claim, fact-check  | Finding Deep Verifier  | auto          | yes               |
| risk register, project risk, probability and impact, risk matrix, mitigation plan, contingency, what are the risks | risk-manager | confirm | yes            |
| SLO, SLA, error budget, latency budget, load test plan, capacity planning, performance target, throughput, soak test | performance | confirm | yes           |
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

### Rows That Need a Word of Explanation

Twelve default rows do not mean quite what their keywords suggest:

* **`tester` and `qa-engineer` split on read versus write.** `tester` reads a change — a diff, or an implementation against a plan — and never authors or runs a test. `qa-engineer` writes the tests, runs them, and reports reproducible defects. "Review this change" is `tester`; "write tests for this" or "why does this break on empty input" is `qa-engineer`. The row is `confirm` and non-parallel because it writes files into the project's own test tree, which is a code change like any other.
* **`release-engineer` builds the pipeline; it never runs a deployment.** Authoring and hardening a workflow, pinning actions, moving CI to OIDC, cutting build minutes, defining environments and approvals, and writing the rollout and rollback plan all land here. The moment the request is "deploy this to Azure", it is `deployer` behind the Impactful-Action Gate, and the moment it is "write the Bicep", it is `iac-author`. Its Azure DevOps reach is pipelines, builds, repos, and artifacts; work items stay with `product-owner` and `backlog-executor`.
* **The two AWS rows mirror the Azure pair and never cross into it.** `aws-architect` designs and authors, `aws-diagnose` triages a live incident read-only. Neither reasons about Azure and neither is reached by the Azure keywords; a workload spanning both clouds needs both roles, which is exactly why AWS is a pack that layers onto any profile rather than a profile competing with `azure`.

* **Accessibility has two owners, and they do different jobs.** The `accessibility` row owns product-level conformance work: assessing the codebase against WCAG 2.2, ARIA, Section 508, or EN 301 549, and discovering the surfaces and interaction states that need assessing. Reviewing one diff for accessibility stays with `tester`, which resolves to `Code Review Accessibility` per the roster Selection Cue. The `designer` row no longer carries the bare `accessibility` keyword, because a request that names accessibility explicitly now has a role that owns it; accessible *design* work still reaches `designer` through the design keywords.
* **Supply chain is separate from security, deliberately.** `security` threat-models the software; `supply-chain` assesses how it is built, signed, and released. `SSSC Planner` and `Supply Chain Skill Assessor` remain alternates under `security` as well, which is legal many-to-one casting, so a squad carrying only `security` still reaches them.
* **`vuln-manager` is the third member of that family, and the narrowest.** It starts from a vulnerability that already has an identifier and asks one question: does it reach *this* product. It does not threat-model the design and does not assess build posture. A request naming a CVE, an advisory, or VEX belongs here; a request about vulnerabilities in the abstract belongs with `security`.
* **`azure-diagnose` carries the incident keywords, and there is no `sre` role.** The role already owned the diagnosis phase, so the rest of the incident lifecycle was given to it rather than to a second role that would claim the same phase. Mitigation still leaves the role: it recommends, and `Squad Deployer` applies behind the Impactful-Action Gate.
* **`performance` and `observability` are adjacent and separate.** `performance` decides the target and what must be measurable; `observability` decides how it is emitted and named. A request that says "make it fast" is `performance`; one that says "we cannot see what it is doing" is `observability`. Both are pre-production and neither runs anything.
* **GitLab is at the `escalate` tier because no GitLab agent ships.** `product-owner` covers GitHub, Azure DevOps, and Jira through mapped agents; for GitLab it plans the work the same way, but there is no dispatchable agent and no equivalent of `backlog-executor`. Merge-request and pipeline operations are reached through the `gitlab` skill by whichever role owns the change, so the coordinator states that and asks the user how to proceed rather than dispatching a role that cannot complete the request.
* **The two Power Platform rows arrive with a pack, not a profile.** `pp-architect` and `pp-connector` are seeded only when the `power-platform` pack is applied, and their Primaries are registered **opt-in** external agents (see *External Cast* in `squad-roster.instructions.md`). Until the pack is applied and its resources installed, a matching request escalates with the install command rather than dispatching. Neither row overlaps `azure-architect`: Logic Apps and Azure integration stay Azure, and Power Automate stays Power Platform.
* **The two Microsoft 365 Copilot rows behave the same way**, arriving with the `m365-copilot` pack rather than any profile. They do not overlap the Power Platform rows: Copilot Studio agents and Power Platform custom connectors stay with `pp-connector`, while M365 Copilot declarative agents, API plugins, and Microsoft Graph stay here. `m365-agent-architect` is also distinct from `prompt-engineer`, which authors this repository's own Copilot customization artifacts rather than a declarative agent shipped to a tenant.
* **`data-scientist` carries the Power BI and Fabric keywords, and there is no `bi-analyst` role.** All four upstream Power BI agents failed the external-cast verification gate, so the capability arrives as opt-in skills registered against the role that already owns analytical deliverables. A Fabric request outside the Lakehouse primer — Data Factory, Warehouse, Real-Time Intelligence, deployment pipelines, or capacity administration — has no registered resource behind it and is escalated rather than answered.

### Filtering to the Active Roster

The seeded `routing.md` contains only the rules whose role exists in the project's `team.md`. When a profile (see *Squad Profiles* in `squad-roster.instructions.md`) seeds a subset of the cast, the Squad Scribe drops every routing row whose role is not on the seeded team. This keeps routing consistent with the chosen squad: the coordinator never matches a request to a role the project did not hire.

When a request matches a pattern whose role is absent from the active roster, the coordinator escalates (see Escalation) and offers to add the role or switch profiles rather than dispatching a role that is not on the team.

Ten rows never survive the initial filter in most projects, because no profile seeds their role. `intake-validator` is seeded only by `product` and `full`, and `backlog-executor` is an **opt-in role** seeded by no profile at all (see *Opt-In Roles* in `squad-roster.instructions.md`). The `pp-architect` and `pp-connector` rows belong to the `power-platform` **pack**, the `m365-agent-architect` and `m365-agent-integrator` rows to the `m365-copilot` pack, and the `aws-architect` and `aws-diagnose` rows to the `aws` pack; a pack is by definition never part of a profile (see *Squad Packs* in the same file). `qa-engineer` and `release-engineer` belong to no pack but are opt-in for the same underlying reason: their Primaries are registered **opt-in** external agents, and a registered-but-uninstalled role is never seeded. For all ten the escalation above is not a dead end but the designed entry point: the coordinator proposes adding the role — or, for a pack role, applying the whole pack — states what it would be able to do, names the install command and prerequisites its registered resources need, and continues the turn on acceptance.

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

### Tracker-Write Gate

Before any role writes into a live issue tracker — creating, updating, linking, closing, or commenting on work items in Azure DevOps or Jira — the coordinator applies this gate. A tracker write is an impactful action: it is announced to a whole team by notifications, subscriptions, and webhooks the instant it lands, and no undo recalls that.

* **Only `backlog-executor` writes.** `product-owner` plans the work items and stops at a finalized `handoff.md`. When a turn would have any other role write to a tracker, that is a routing error — re-route rather than allowing it.
* **A finalized handoff is a precondition.** When none exists for the request, dispatch `product-owner` first. `backlog-executor` never plans the content it writes.
* **The role is opt-in.** When the active roster does not carry `backlog-executor`, the coordinator proposes adding it (see *Opt-In Roles* in `squad-roster.instructions.md`), naming the tracker and project it would write to, rather than skipping the write or improvising it elsewhere.
* **One approval covers one batch.** The Impactful-Action Gate fires once per handoff, and the gate payload carries the full preview, the item count, and any probable duplicates. A changed handoff, a re-run, or a different project needs a fresh preview and a fresh approval.
* **Unattended runs never write.** In Watch Mode the Impactful-Action Gate never proceeds (`.github/instructions/squad/squad-watch-mode.instructions.md`), so the role completes its preview and stops. Report the preview as the outcome; do not report the write as pending indefinitely.

The tracker-write gate is independent of the Implementation Gate: a backlog write needs no Council Verdict, but it always needs a human approval.

### Review Follow-Through

The methodology does not end at implementation. After any implementation-tier role lands a change, the coordinator dispatches `tester` (review) as the closing stage before it reports the work complete — in every mode (interactive, autonomous, and autopilot). Review is an `auto`-tier, non-destructive read, so it runs without a separate gate. This makes the methodology symmetric: research and plan precede implementation, and review follows it, so Research → Plan → Implement → Review is enforced end-to-end.

* Resolve `tester` to the matching review agent per the roster Selection Cue — for example `Code Review Functional` for a correctness and edge-case diff, or `Code Review Security` for a security diff — and fold its findings into the turn summary. When no sub-type cue matches, the Primary `Squad Reviewer` runs the implementation-versus-plan review.
* Every profile carries `tester` through the methodology spine (see `squad-roster.instructions.md`), so the review stage is always available. When a user has explicitly removed `tester` from the roster, the coordinator reports that the change closed unreviewed and recommends re-adding the role rather than silently skipping review.

## Escalation

The coordinator escalates to the user, rather than dispatching, when any of these hold:

* The matched rule is at the `escalate` tier.
* No routing pattern matches the request with reasonable confidence.
* A matched role resolves to **thin charter needed** in the roster.
* Two rules conflict and no pattern is clearly more specific.

On escalation, the coordinator states the ambiguity, lists the candidate roles, and asks the user to choose before any role acts.
