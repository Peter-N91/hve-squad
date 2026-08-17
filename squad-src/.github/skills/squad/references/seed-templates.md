---
name: squad-seed-templates
description: "First-run squad state templates: team.md, routing.md, decisions.md, history files, notifications.md, and state.json."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-08-14"
---

# Seed Templates

The coordinator hands these templates to the Squad Scribe on first run, after the user confirms a profile in Init Mode. They stay consistent with the three squad instruction files: `team.md` holds the confirmed profile's members (the full cast catalog shown below is the `full` profile), `routing.md` mirrors the default routing rules filtered to the seeded roster, and the write semantics match the state layout (`decisions.md` and `history/<agent>.md` are append-only; `team.md`, `routing.md`, `state.json`, `consumption.md`, and `consumption-rates.md` use replace semantics).

## team.md

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
| prompt-engineer | Sigma       | Squad Prompt Engineer        | Vally Test Author, HVE Artifact Tester                 | runSubagent / task | default                 | .copilot-tracking/prompts/            |
| analyst         | Omega       | PRD Builder                  | BRD Builder, Meeting Analyst                           | runSubagent / task | default                 | .copilot-tracking/plans/              |
| product-owner   | Alpha-2     | Functional Planner           | Issue Triage Agent                                     | runSubagent / task | default                 | .copilot-tracking/plans/              |
| presenter       | Tau         | PowerPoint Subagent          | —                                                      | runSubagent / task | default                 | .copilot-tracking/ppt/<date>/<slug>/  |
| technical-writer | Upsilon    | Squad Technical Writer       | —                                                      | runSubagent / task | fast                    | docs/                                 |
| experimenter    | Beta-2      | Experiment Designer          | —                                                      | runSubagent / task | default                 | .copilot-tracking/plans/              |
| data-scientist  | Gamma-2     | Squad Data Scientist         | —                                                      | runSubagent / task | default                 | outputs/                              |
| intake-validator |            | PRD Quality Reviewer         | BRD Quality Reviewer                                   | runSubagent / task | fast                    | —                                     |
| scribe          |             | Squad Scribe                 | —                                                      | runSubagent / task | fast                    | (squad state)                         |
| devrel          |             | —                            | —                                                      | —                  | — (no backing skill)    | —                                     |
```

## routing.md

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
| brainstorm, ideate, shape this idea, explore options, what should we build, help me think through, we want to, kick off a brief | designer, analyst | confirm | no |
| validate requirements, requirements readiness, requirements complete, requirements clear, intake check, are the requirements ready | intake-validator | auto | yes |
| security, threat, vulnerability, STRIDE    | Security Planner             | confirm       | yes               |
| supply chain, SBOM, SLSA, provenance, OpenSSF Scorecard, Sigstore, signed release, dependency pinning | supply-chain | confirm | yes         |
| CVE, vulnerability triage, VEX, OpenVEX, exploitability, is this CVE exploitable, advisory disposition, not affected | vuln-manager | confirm | yes |
| privacy, personal data, PII, DPIA, GDPR, data subject, retention | privacy               | confirm       | yes               |
| accessibility, a11y, WCAG, ARIA, screen reader, keyboard navigation, Section 508, EN 301 549, VPAT, conformance audit | accessibility | confirm | yes |
| design, UX, UI, wireframe, journey, interaction design | UX UI Designer          | confirm       | yes               |
| requirements, BRD, PRD, user story, acceptance criteria | PRD Builder                 | confirm       | yes               |
| journey map, persona, design thinking, empathize, ideate, problem statement | DT Coach | confirm | yes           |
| roadmap, backlog, epic, sprint, prioritize, story, PRD to work items, work item hierarchy | product-owner | confirm    | no                |
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

## decisions.md

Append-only log. The header is written once; every decision is appended below it and prior entries are never edited. Council Verdicts (from the Council Procedure) use the same append-only contract but a fixed schema; the placeholder below shows the shape the Scribe stamps in.

```markdown
---
description: "Append-only log of squad decisions and their rationale"
---

# Squad Decisions

Entries are appended below in chronological order. Each entry records the decision, its rationale, the turn it was made on, and a reference to an ADR when the decision is architecturally significant. Council Verdicts use the `## Council Verdict <timestamp> <topic-id>` heading and the schema in `.github/instructions/squad/squad-council.instructions.md`; Discovery Verdicts and Intake Readiness Verdicts use their own headings and schemas from `.github/instructions/squad/squad-discovery-gate.instructions.md` and `.github/instructions/squad/squad-intake-gate.instructions.md`. Prior entries are never edited or removed.

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

## history/<agent>.md

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

## history/autonomous-loop-<id>.md

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

## history/autopilot-run-<id>.md

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

## notifications.md

Append-only log of notifications (pings) the squad fired. The header is written once; every notification is appended below it. Records the trigger, the recipient, the resolved channel, and the decision awaited.

```markdown
---
description: "Append-only log of squad notifications (pings) and their delivery channel"
---

# Squad Notifications

Each entry records a notification the squad fired: when, to whom, the trigger, the channel it resolved to, and the decision awaited. Entries are appended in chronological order and never edited.

<!-- Append new notification entries below this line. -->
```

## state.json

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
