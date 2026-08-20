---
name: squad-seed-templates
description: "First-run squad state templates stamped once during Init: team.md and routing.md."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-08-18"
---

# Seed Templates

The coordinator hands these templates to the Squad Scribe on first run, after the user confirms a profile in Init Mode. They are stamped **once** and then only refreshed on an explicit re-cast, which is why they live apart from the recurring write shapes in [entry-schemas.md](entry-schemas.md) — an ordinary turn never needs them.

They stay consistent with the three squad instruction files: `team.md` holds the confirmed profile's members (the full cast catalog shown below is the `full` profile), and `routing.md` mirrors the default routing rules filtered to the seeded roster. Both use replace semantics.

## team.md

Seeded from the confirmed profile's members plus the roles of every applied pack; the template below shows the `full` profile with no pack applied. For other profiles, only the profile's rows are written, and each applied pack appends its own roles to them. The `Member Name` column is populated from the Init Mode naming step: it may be empty for roles the user chose not to name, and it must be unique within a `Role` when two rows share the same role. The role-to-agent relationship is many-to-many: each role names one **Primary** agent the coordinator dispatches by default plus optional **Alternate** agents it resolves to per the row's `Selection Cue`. **Seed the `Selection Cue` cell with the row's condition, and `—` when the role has no alternates**, because the full cast catalog lives in an `applyTo`-scoped instruction file that does not load on every host: a roster that lists alternates without saying when they apply invites the coordinator to pick the one that sounds closest, which swaps a role's methodology silently. The `devrel`, `networking`, `gcp`, and `identity` roles have no deployed HVE Core agent and no backing skill, so they stay unselectable until one exists. The opt-in `backlog-executor` role is absent from every profile and is appended to `team.md` only when the user accepts the coordinator's offer to add it. Pack roles such as `pp-architect` and `pp-connector` are likewise absent from every profile template and are appended only when a pack is applied, and `qa-engineer` and `release-engineer` are absent for the related reason that their Primaries are registered opt-in external agents — a registered-but-uninstalled role is never seeded.

```markdown
---
description: "Squad roster: roles and the deployed HVE Core agents that fill them"
---

# Squad Roster

## Members

| Role            | Member Name | Agent Name (Primary)         | Alternate Agents                                       | Selection Cue                                                                                          | Invocation         | Model Tier              | Deliverable Root                      |
|-----------------|-------------|------------------------------|--------------------------------------------------------|--------------------------------------------------------------------------------------------------------|--------------------|-------------------------|---------------------------------------|
| researcher      | Alpha       | Squad Researcher             | Codebase Profiler, Meeting Analyst                     | technology-profile scan → Codebase Profiler; meeting-transcript mining → Meeting Analyst                | runSubagent / task | default                 | .copilot-tracking/research/<date>/    |
| lead            | Beta        | Squad Lead                   | RPI Planner                                            | revise one numbered phase of an existing plan → RPI Planner                                            | runSubagent / task | default                 | .copilot-tracking/plans/              |
| developer       | Gamma       | Squad Implementor            | —                                                      | —                                                                                                       | runSubagent / task | default                 | .copilot-tracking/changes/            |
| tester          | Delta       | Squad Reviewer               | Code Review Functional, Code Review Standards          | correctness/edge-case diff → Code Review Functional; project-conventions diff → Code Review Standards   | runSubagent / task | fast                    | .copilot-tracking/reviews/            |
| challenger      | Epsilon     | Squad Challenger             | —                                                      | —                                                                                                       | runSubagent / task | default                 | .copilot-tracking/reviews/            |
| architect       | Zeta        | System Architecture Reviewer | ADR Creator                                            | capture a decision record → ADR Creator                                                                 | runSubagent / task | default                 | docs/architecture/                    |
| azure-architect | Eta         | Squad Azure Architect        | —                                                      | —                                                                                                       | runSubagent / task | default                 | docs/architecture/                    |
| security        | Theta       | Security Planner             | SSSC Planner, Skill Assessor, Finding Deep Verifier    | supply-chain posture → SSSC Planner; single security-skill assessment → Skill Assessor; verify a finding → Finding Deep Verifier | runSubagent / task | default                 | —                                     |
| supply-chain    | Phi         | SSSC Planner                 | Supply Chain Skill Assessor                            | single supply-chain skill assessment → Supply Chain Skill Assessor                                      | runSubagent / task | default                 | .copilot-tracking/sssc-plans/         |
| vuln-manager    | Delta-2     | Squad Vulnerability Manager  | —                                                      | —                                                                                                       | runSubagent / task | default                 | .copilot-tracking/security/vex/       |
| rai             | Iota        | RAI Planner                  | RAI Skill Assessor                                     | single-framework assessment against the codebase → RAI Skill Assessor                                   | runSubagent / task | default                 | —                                     |
| privacy         | Chi         | Privacy Planner              | —                                                      | —                                                                                                       | runSubagent / task | default                 | —                                     |
| accessibility   | Psi         | Accessibility Framework Assessor | Accessibility Surface Inventory                    | discover runtime surfaces before assessing → Accessibility Surface Inventory                            | runSubagent / task | default                 | .copilot-tracking/accessibility/      |
| designer        | Kappa       | UX UI Designer               | DT Coach, DT Learning Tutor                            | facilitated design-thinking session → DT Coach; DT curriculum or learning → DT Learning Tutor           | runSubagent / task | default                 | .copilot-tracking/plans/              |
| fact-checker    | Lambda      | Finding Deep Verifier        | —                                                      | —                                                                                                       | runSubagent / task | fast                    | —                                     |
| risk-manager    | Epsilon-2   | Squad Risk Manager           | —                                                      | —                                                                                                       | runSubagent / task | default                 | docs/risks/                           |
| cost-manager    | Mu          | Squad Cost Manager           | —                                                      | —                                                                                                       | runSubagent / task | default                 | —                                     |
| iac-author      | Nu          | Squad IaC Author             | —                                                      | —                                                                                                       | runSubagent / task | default                 | .copilot-tracking/changes/            |
| deployer        | Xi          | Squad Deployer               | —                                                      | —                                                                                                       | runSubagent / task | default                 | —                                     |
| asbuilt-author  | Omicron     | Squad As-Built Author        | —                                                      | —                                                                                                       | runSubagent / task | default                 | docs/architecture/                    |
| azure-diagnose  | Pi          | Squad Azure Diagnose         | —                                                      | —                                                                                                       | runSubagent / task | fast                    | —                                     |
| performance     | Zeta-2      | Squad Performance Planner    | —                                                      | —                                                                                                       | runSubagent / task | default                 | .copilot-tracking/performance-plans/  |
| observability   | Eta-2       | Squad Observability Planner  | —                                                      | —                                                                                                       | runSubagent / task | default                 | .copilot-tracking/observability-plans/ |
| modernizer      | Rho         | Squad Modernization Planner  | Squad SQL Migration Advisor                            | SQL Server-to-Azure path or method selection → Squad SQL Migration Advisor                              | runSubagent / task | default                 | .copilot-tracking/plans/              |
| prompt-engineer | Sigma       | Squad Prompt Engineer        | Vally Test Author, HVE Artifact Tester                 | conformance stimuli → Vally Test Author; artifact conformance run → HVE Artifact Tester                 | runSubagent / task | default                 | .copilot-tracking/prompts/            |
| analyst         | Omega       | PRD Builder                  | BRD Builder, Meeting Analyst                           | business requirements → BRD Builder; transcript-to-requirements → Meeting Analyst                       | runSubagent / task | default                 | .copilot-tracking/plans/              |
| product-owner   | Alpha-2     | Functional Planner           | Issue Triage Agent                                     | single-issue triage → Issue Triage Agent                                                                | runSubagent / task | default                 | .copilot-tracking/plans/              |
| presenter       | Tau         | PowerPoint Subagent          | —                                                      | —                                                                                                       | runSubagent / task | default                 | .copilot-tracking/ppt/<date>/<slug>/  |
| technical-writer | Upsilon    | Squad Technical Writer       | —                                                      | —                                                                                                       | runSubagent / task | fast                    | docs/                                 |
| experimenter    | Beta-2      | Experiment Designer          | —                                                      | —                                                                                                       | runSubagent / task | default                 | .copilot-tracking/plans/              |
| data-scientist  | Gamma-2     | Squad Data Scientist         | —                                                      | —                                                                                                       | runSubagent / task | default                 | outputs/                              |
| intake-validator |            | PRD Quality Reviewer         | BRD Quality Reviewer                                   | BRD under review → BRD Quality Reviewer                                                                 | runSubagent / task | fast                    | —                                     |
| scribe          |             | Squad Scribe                 | —                                                      | —                                                                                                       | runSubagent / task | fast                    | (squad state)                         |
| devrel          |             | —                            | —                                                      | —                                                                                                       | —                  | — (no backing skill)    | —                                     |
```

## routing.md

Seeded from the default routing rules. Each rule points at a role that exists in `team.md`. The canonical rule set is *Default Routing Rules* in `.github/instructions/squad/squad-routing.instructions.md`; the table below mirrors it in full, and the instructions win on any difference. The Scribe drops every row whose role is not on the seeded team, so a narrow profile writes only its own subset.

**The `Role(s)` column holds role ids, never agent names.** `team.md` is keyed on the role id, so the id is what carries the row's `Member Name`, `Model Tier`, Selection Cues, and `Deliverable Root`. Writing an agent name here resolves to no roster row and the dispatch silently loses all four — most visibly the output path, which then falls back to the agent's own default. Copy the ids below verbatim; the concrete agent is resolved at dispatch time.

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
| security, threat, vulnerability, STRIDE    | security                     | confirm       | yes               |
| supply chain, SBOM, SLSA, provenance, OpenSSF Scorecard, Sigstore, signed release, dependency pinning | supply-chain | confirm | yes         |
| CVE, vulnerability triage, VEX, OpenVEX, exploitability, is this CVE exploitable, advisory disposition, not affected | vuln-manager | confirm | yes |
| privacy, personal data, PII, DPIA, GDPR, data subject, retention | privacy               | confirm       | yes               |
| accessibility, a11y, WCAG, ARIA, screen reader, keyboard navigation, Section 508, EN 301 549, VPAT, conformance audit | accessibility | confirm | yes |
| design, UX, UI, wireframe, journey, interaction design | designer                | confirm       | yes               |
| requirements, BRD, PRD, user story, acceptance criteria | analyst                     | confirm       | yes               |
| journey map, persona, design thinking, empathize, ideate, problem statement | designer | confirm | yes           |
| roadmap, backlog, epic, sprint, prioritize, story, PRD to work items, work item hierarchy | product-owner | confirm    | no                |
| create work items in ADO, push backlog to Azure DevOps, create Jira issues, apply the handoff, execute handoff, sync work items to the tracker | backlog-executor | confirm | no |
| GitLab merge request, GitLab pipeline, GitLab issue, open an MR | product-owner        | escalate      | no                |
| experiment, hypothesis, validate assumption, MVE, riskiest assumption | experimenter        | confirm | yes         |
| presentation, deck, slides, executive summary, pitch | presenter                    | confirm       | no                |
| document, write up, summarize for stakeholders, readme | technical-writer           | confirm       | no                |
| data profile, data dictionary, EDA, exploratory analysis, notebook, dashboard, dataset, Power BI, DAX, semantic model, star schema, report design, Fabric, Lakehouse, OneLake | data-scientist | confirm | no |
| architecture, system design, components    | architect                    | auto          | yes               |
| responsible AI, RAI, fairness, harm        | rai                          | confirm       | yes               |
| verify finding, confirm claim, fact-check  | fact-checker                 | auto          | yes               |
| risk register, project risk, probability and impact, risk matrix, mitigation plan, contingency, what are the risks | risk-manager | confirm | yes |
| SLO, SLA, error budget, latency budget, load test plan, capacity planning, performance target, throughput, soak test | performance | confirm | yes |
| observability, instrumentation, telemetry design, spans, traces, metrics, structured logging, OpenTelemetry, what should we emit | observability | confirm | yes |
| author IaC, write Bicep, write Terraform, convert LLD to infra, infrastructure as code | iac-author | confirm | no |
| deploy, provision, what-if, terraform plan, terraform apply, az deployment | deployer | confirm | no |
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

