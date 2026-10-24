---
name: squad-profiles-and-packs
description: "Squad profile catalog and add-on packs: which roles a profile seeds and which roles a pack appends."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-24"
---

# Squad Profiles and Packs

## Squad Profiles

A profile is a curated subset of the cast tailored to a kind of project. The coordinator seeds only the profile's members into `team.md`, and the routing table is filtered to those roles. The `scribe` role is always included (the ordinary state writer after Cost Preflight), and so is the **methodology spine** (`researcher`, `lead`, `developer`, `tester`) that runs the Research → Plan → Implement → Review cycle in every profile; the `intake-validator` role is seeded into the `product` and `full` profiles and can be added to any roster. Profiles are defined canonically in `.github/instructions/squad/squad-roster.instructions.md`; the catalog below mirrors them.

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

## Registered Packs

A **pack** is a named set of roles added *on top of* a profile, never instead of one. A profile answers "what kind of work is this" and carries the methodology spine; a pack answers "what is it built on" and carries specialists only, so technology verticals arrive as packs and compose with any profile. Exactly one profile, zero or more packs. Packs are defined canonically in `.github/instructions/squad/squad-roster.instructions.md`; the catalog below mirrors them.

| Pack             | Adds                       | Guidance | Use When                                                                                       | Arrival                                                                       |
|------------------|----------------------------|----------|-------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------|
| `power-platform` | pp-architect, pp-connector |          | The project is built on Power Platform — Power Apps, Power Automate, Dataverse, Power Pages, or Copilot Studio | Opt-in; both roles rest on registered external agents the consumer installs |
| `m365-copilot` | m365-agent-architect, m365-agent-integrator |          | The project is built on Microsoft 365 Copilot — declarative agents, TypeSpec agent definitions, API plugins, MCP-backed agents, or Microsoft Graph integration | Opt-in; both roles rest on registered external agents the consumer installs |
| `aws`          | aws-architect, aws-diagnose |          | The project is built on AWS — Lambda and serverless, ECS or EKS, CDK, SAM, CloudFormation, Organizations and landing zones, or a live AWS workload to triage | Opt-in; both roles rest on registered external agents the consumer installs |
| `foundry` | architect, azure-architect, deployer, prompt-engineer, security, rai, observability, cost-manager | [foundry-blueprint.md](foundry-blueprint.md); [foundry-platform-options.md](foundry-platform-options.md) | Designing or delivering a Microsoft Foundry agentic AI project | Opt-in; reuses existing roles and registered external skills |

The optional `Guidance` column is the only pack-to-context mechanism. For an active pack, the coordinator passes those files to the roles named in `Adds` and to the methodology spine (`researcher`, `lead`, `developer`, `tester`); a blank value means role composition only. Pass guidance only when the request or approved plan touches that pack's workload, and pass only the relevant section plus any shared evidence contract rather than the whole file by default. Read active packs from the resolved root's `team.md` `Packs:` line; accepted Init and apply/remove entries in `decisions.md` remain the append-only audit trail. A missing line means no active pack carries guidance; the legacy packs have none. When a pack is next applied or removed and the line is absent, reconcile the accepted pack decisions once and pass the full current list in `packs`. Apply this at Init and at each federation member root without changing siblings. Removing a pack updates or removes the `Packs:` line, stops its guidance handoff, and removes only roles no other roster source owns, including custom roster rows.

Pack guidance supplements ordinary routing. It never replaces a role's governing skills or output roots, changes write permissions, installs an external resource, approves a preview, upgrades an SDK, or provisions infrastructure.

The Scribe records active packs in `team.md` and records provenance in literal `profile +pack` form in the Init decision and federation registry. A pack's roles obey every rule a profile's roles obey: a role whose external resource is not installed is offered with its install command rather than seeded.

A pack is proposed, never imposed. The coordinator offers one at Init when the repository carries the domain's signals **or the request itself names the domain**, and offers one mid-project when a request needs a role only that pack provides. A pack is equally removable: dropping one removes only the roles it still owns — never a role the profile or another pack also contributes — and appends a decision rather than editing anything. The append-only `decisions.md` and `history/<agent>.md` are untouched by a removal, the removed member's row stays in `consumption.md` marked removed so the run total stays truthful, and deliverables already written stay on disk. See *Removing a Pack* in `.github/instructions/squad/squad-roster.instructions.md`.

### Pack Discovery

An explicit `pack=` hint wins; otherwise either repository signals or the request's domain is enough to propose a pack, never to apply it. Present the profile and proposed packs together for one confirmation. Offer install commands for missing registered resources instead of seeding absent roles.

| Pack | Repository signals |
|------|--------------------|
| `power-platform` | `.cdsproj`, `solution.xml`, a `pac` CLI configuration, a canvas app `.msapp`, or a Dataverse solution folder |
| `m365-copilot` | A `declarativeAgent.json` or `manifest.json` Copilot agent manifest, `m365agents.yml`, `teamsapp.yml`, `appPackage/`, or `main.tsp` importing `@microsoft/typespec-m365-copilot` |
| `aws` | CloudFormation, including `template.yaml` with `AWS::Serverless`; `cdk.json`, `samconfig.toml`, `serverless.yml`, `.aws/`, or Terraform's `hashicorp/aws` provider |
| `foundry` | SDK dependencies (`azure-ai-projects`, `azure-ai-agents`, `Azure.AI.Projects`, `Azure.AI.Agents.Persistent`, `@azure/ai-projects`, `@azure/ai-agents`), `azure.yaml` using the `azure.ai.agents` azd extension, or `AZURE_AI_PROJECT_ENDPOINT` / a `services.ai.azure.com/api/projects` URL in configuration or `.env` templates |

**A pack is not a federation.** One piece of work that needs extra expertise is a profile plus a pack, because those roles must share a plan, a council, and a review. Two streams of work with separate deliverables and owners is a federation. Federation does not reach a vertical any faster — a sub-squad is seeded from a profile and takes the pack the same way any roster does — so building a sub-squad to obtain a role buys a duplicated spine and a second state tree for no extra reach. See *Pack or Federation* in `.github/instructions/squad/squad-roster.instructions.md`.
