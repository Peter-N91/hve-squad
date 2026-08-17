---
name: squad-profiles-and-packs
description: "Squad profile catalog and add-on packs: which roles a profile seeds and which roles a pack appends."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-08-14"
---

# Squad Profiles and Packs

## Squad Profiles

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

## Squad Packs

A **pack** is a named set of roles added *on top of* a profile, never instead of one. A profile answers "what kind of work is this" and carries the methodology spine; a pack answers "what is it built on" and carries specialists only, so technology verticals arrive as packs and compose with any profile. Exactly one profile, zero or more packs. Packs are defined canonically in `.github/instructions/squad/squad-roster.instructions.md`; the catalog below mirrors them.

| Pack             | Adds                       | Use When                                                                                       | Arrival                                                                       |
|------------------|----------------------------|-------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------|
| `power-platform` | pp-architect, pp-connector | The project is built on Power Platform — Power Apps, Power Automate, Dataverse, Power Pages, or Copilot Studio | Opt-in; both roles rest on registered external agents the consumer installs |
| `m365-copilot` | m365-agent-architect, m365-agent-integrator | The project is built on Microsoft 365 Copilot — declarative agents, TypeSpec agent definitions, API plugins, MCP-backed agents, or Microsoft Graph integration | Opt-in; both roles rest on registered external agents the consumer installs |
| `aws`          | aws-architect, aws-diagnose | The project is built on AWS — Lambda and serverless, ECS or EKS, CDK, SAM, CloudFormation, Organizations and landing zones, or a live AWS workload to triage | Opt-in; both roles rest on registered external agents the consumer installs |

The Scribe records a roster's provenance — the profile plus any applied packs — in the Init decision in `decisions.md`, and in a federation in the registry's `Profile` column. A pack's roles obey every rule a profile's roles obey: a role whose external resource is not installed is offered with its install command rather than seeded.

A pack is proposed, never imposed. The coordinator offers one at Init when the repository carries the domain's signals **or the request itself names the domain**, and offers one mid-project when a request needs a role only that pack provides. A pack is equally removable: dropping one removes only the roles it still owns — never a role the profile or another pack also contributes — and appends a decision rather than editing anything. The append-only `decisions.md` and `history/<agent>.md` are untouched by a removal, the removed member's row stays in `consumption.md` marked removed so the run total stays truthful, and deliverables already written stay on disk. See *Removing a Pack* in `.github/instructions/squad/squad-roster.instructions.md`.

**A pack is not a federation.** One piece of work that needs extra expertise is a profile plus a pack, because those roles must share a plan, a council, and a review. Two streams of work with separate deliverables and owners is a federation. Federation does not reach a vertical any faster — a sub-squad is seeded from a profile and takes the pack the same way any roster does — so building a sub-squad to obtain a role buys a duplicated spine and a second state tree for no extra reach. See *Pack or Federation* in `.github/instructions/squad/squad-roster.instructions.md`.
