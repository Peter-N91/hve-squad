---
name: squad-profiles-and-packs
description: "Squad profile catalog and add-on packs: which roles a profile seeds and which roles a pack appends."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-11-12"
---

# Squad Profiles and Packs

## Squad Profiles

A profile is a curated subset of the cast tailored to a kind of project. The coordinator seeds only the profile's members into `team.md`, and the routing table is filtered to those roles. The `scribe` role is always included (the ordinary state writer after Cost Preflight), and so is the **methodology spine** (`researcher`, `lead`, `developer`, `tester`) that runs the Research → Plan → Implement → Review cycle in every profile; the `intake-validator` role is seeded into the `product` and `full` profiles and can be added to any roster. Profiles are defined canonically in `.github/instructions/squad/squad-roster.instructions.md`; the catalog below mirrors them.

One catalog role — `backlog-executor`, which writes work items into a live Azure DevOps or Jira project — is **opt-in** and appears in no profile, not even `full`, because a tracker write reaches a whole team's backlog. The coordinator offers to add it the first time a request needs a tracker write, and adds it only on the user's say-so. See *Opt-In Roles* in the roster conventions.

| Profile         | Members                                                                                                                       | Use When                                                                                     |
|-----------------|-------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `default`       | researcher, lead, developer, tester, scribe                                                                                   | General-purpose work; recommended starting point                                             |
| `full`          | researcher, lead, developer, tester, challenger, architect, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, security, supply-chain, vuln-manager, rai, privacy, accessibility, risk-manager, performance, observability, designer, fact-checker, cost-manager, modernizer, prompt-engineer, analyst, product-owner, technical-writer, experimenter, data-scientist, intake-validator, scribe | Complex, cross-cutting projects that need every discipline except the opt-in roles |
| `security`      | researcher, lead, developer, tester, security, supply-chain, rai, privacy, fact-checker, scribe                               | Security, supply-chain, privacy, threat-modeling, and responsible-AI focus                   |
| `design`        | researcher, lead, developer, tester, designer, accessibility, scribe                                                          | UX/UI and product-design focus                                                               |
| `accessibility` | researcher, lead, developer, tester, accessibility, designer, scribe                                                          | Accessibility conformance as the goal itself (WCAG 2.2, Section 508, EN 301 549)             |
| `architecture`  | researcher, lead, developer, tester, architect, azure-architect, cost-manager, scribe                                        | System design and architecture focus                                                         |
| `azure`         | researcher, lead, developer, tester, azure-architect, iac-author, deployer, asbuilt-author, azure-diagnose, architect, cost-manager, security, modernizer, scribe | Azure-focused build with budget and security oversight (Bicep, landing-zone, FinOps signals) |
| `modernization` | researcher, lead, developer, tester, modernizer, architect, azure-architect, iac-author, cost-manager, asbuilt-author, scribe | Legacy uplift: framework and dependency upgrades, re-platforming, SQL or cloud migration      |
| `compliance`    | researcher, lead, developer, tester, security, supply-chain, vuln-manager, privacy, rai, accessibility, risk-manager, scribe  | Conformance evidence as the goal: an audit, an attestation, or a customer security questionnaire |
| `operations`    | researcher, lead, developer, tester, azure-diagnose, performance, observability, asbuilt-author, iac-author, deployer, scribe | Running a deployed system: incidents, reliability targets, instrumentation design, and as-built docs |
| `product`       | researcher, lead, developer, tester, analyst, designer, product-owner, technical-writer, experimenter, data-scientist, intake-validator, scribe | Business discovery and delivery — requirements, design thinking, roadmap, and stakeholder deliverables (often non-technical) |

## Registered Packs

A **pack** is a named set of roles added *on top of* a profile, never instead of one. A profile answers "what kind of work is this" and carries the methodology spine; a pack answers "what is it built on" and carries specialists only, so technology verticals arrive as packs and compose with any profile. Exactly one profile, zero or more packs. Packs are defined canonically in `.github/instructions/squad/squad-roster.instructions.md`; the catalog below mirrors them.

| Pack             | Adds                       | Guidance | Use When                                                                                       | Arrival                                                                       |
|------------------|----------------------------|----------|-------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------|
| `power-platform` | pp-architect, pp-connector | [power-platform-official-resources.md](power-platform-official-resources.md) | The project is built on Power Platform — Power Apps, Power Automate, Dataverse, Power Pages, or Copilot Studio | Opt-in; local charter Primaries ship in the package; community Alternates stay external |
| `m365-copilot` | m365-agent-architect, m365-agent-integrator | [m365-copilot-platform-options.md](m365-copilot-platform-options.md) | The project is built on Microsoft 365 Copilot — declarative agents, TypeSpec agent definitions, API plugins, MCP-backed agents, or Microsoft Graph integration | Opt-in; local charter Primaries ship in the package; community Alternates stay external |
| `aws`          | aws-architect, aws-diagnose |          | The project is built on AWS — Lambda and serverless, ECS or EKS, CDK, SAM, CloudFormation, Organizations and landing zones, or a live AWS workload to triage | Opt-in; both roles rest on registered external agents the consumer installs |
| `foundry` | architect, azure-architect, deployer, prompt-engineer, security, rai, observability, cost-manager, data-scientist | [foundry-blueprint.md](foundry-blueprint.md); [foundry-platform-options.md](foundry-platform-options.md) | Designing or delivering a Microsoft Foundry agentic AI project | Opt-in; reuses existing roles, including `data-scientist` for Foundry IQ, and registered external skills |
| `fabric` | data-scientist | [fabric-blueprint.md](fabric-blueprint.md) | Fabric Warehouse, Eventhouse, Spark, or Dataflow work beyond the Lakehouse primer | Opt-in; reuses `data-scientist` and adds no role |
| `dotnet` | modernizer, tester, performance, developer | [dotnet-platform-options.md](dotnet-platform-options.md) | The project is built on .NET — SDK or target-framework upgrades, NuGet Central Package Management, test-runner migration, `.NET` test and breaking-change review, hot-path performance and BenchmarkDotNet planning, or EF Core, ASP.NET Core Web API, Blazor, C#, and MSBuild implementation | Opt-in; reuses `modernizer`, `tester`, `performance`, and `developer` with registered official skills and adds no role |

The optional `Guidance` column is the only pack-to-context mechanism. For an active pack, the coordinator passes those files to the roles named in `Adds` and to the methodology spine (`researcher`, `lead`, `developer`, `tester`); a blank value means role composition only. Pass guidance only when the request or approved plan touches that pack's workload, and pass only the relevant section plus any shared evidence contract rather than the whole file by default. Read active packs from the resolved root's `team.md` `Packs:` line; accepted Init and apply/remove entries in `decisions.md` remain the append-only audit trail. A missing line means no active pack carries guidance; the legacy packs have none. When a pack is next applied or removed and the line is absent, reconcile the accepted pack decisions once and pass the full current list in `packs`. Apply this at Init and at each federation member root without changing siblings. Removing a pack updates or removes the `Packs:` line, stops its guidance handoff, and removes only roles no other roster source owns, including custom roster rows.

Pack guidance supplements ordinary routing. It never replaces a role's governing skills or output roots, changes write permissions, installs an external resource, approves a preview, upgrades an SDK, or provisions infrastructure.

Init records active packs in `team.md` and records the profile plus build-time
packs in `decisions.md`; a federation copies that initial provenance into the
registry's `Profile` column. A later pack addition updates the selected
squad/member's `Packs:` line and decision through `roster-expansion.md`; it never
turns a member-local roster change into a federation-root write. A pack's roles
obey every profile rule: a role whose external resource is absent is offered
with its install command rather than seeded.

A pack is proposed, never imposed. The coordinator offers one at Init when the repository carries the domain's signals **or the request itself names the domain**, and offers one mid-project when a request needs a role only that pack provides. Confirmed mid-project additions use the sealed `roster-expansion.md` transaction for a plain squad or one selected federation member; it adds no model consumption and preserves the existing ledger, state, rates, notifications, and history byte-for-byte. A pack is equally removable: dropping one removes only the roles it still owns — never a role the profile or another pack also contributes — and appends a decision rather than editing anything. The append-only `decisions.md` and `history/<agent>.md` are untouched by a removal, the removed member's row stays in `consumption.md` marked removed so the run total stays truthful, and deliverables already written stay on disk. See *Removing a Pack* in `.github/instructions/squad/squad-roster.instructions.md`.

Seeded Selection Cues, copied from the cast catalog: Power Pages ALM planning, model-driven app building, Dataverse overview, or Copilot Studio knowledge YAML → Squad Power Platform Architect; broader Power Platform architecture or Copilot Studio, Power Automate, cloud flow, canvas app, DLP policy, or solution ALM → Power Platform Expert. codeful MCP tool or UI generation, Dataverse connection, or Copilot Studio skill import → Squad Power Platform Integrator; broader connector or integration work, custom connector, or connector certification → Power Platform MCP Integration Expert. Both specific Copilot Studio cues are preview: explicit approval and an existing agentic-loop workspace required; other Copilot Studio work keeps the broad Alternate. .NET Agents SDK production readiness, Agents SDK Teams manifest, or M365 evaluation suite → Squad M365 Agent Architect; declarative agent, TypeSpec, API plugin, or broader M365 architecture, Microsoft 365 Copilot agent, agent manifest, or Agents Toolkit → Declarative Agents Architect. Agents SDK OpenTelemetry, Agents SDK provisioning, or Copilot MCP widget server → Squad M365 Agent Integrator; broader MCP-backed M365 integration, Microsoft Graph, Graph SDK, Graph permission scope, or MCP-backed Copilot agent → MCP M365 Agent Expert. Both M365 evaluation suite and Copilot MCP widget server cues are preview: explicit approval required for local file authoring only; broader declarative-agent and MCP work keeps the community Alternate. No cue match keeps the Primary. A matched Alternate that is absent or not dispatchable escalates; do not substitute. Pack absence means the role is not seeded, so installed official skills are not squad-selected. Fabric Warehouse, Eventhouse, Spark, Dataflow, or an admitted migration selects the registered Fabric skills only while `fabric` is active. Admitted `.NET` upgrade, test-review, diagnostics, EF Core, ASP.NET Core, Blazor, C#, and MSBuild skills select on their existing local charters only while `dotnet` is active, and `.NET 11` migration plus experimental mock-usage analysis require explicit preview approval. Host visibility is not selection.

### Pack Resource Preflight

| Resource pack | Registered skills |
|---|---|
| `power-platform` | plan-alm, app-builder, dv-overview, generate-codeful-mcp-tool, generate-mcp-app-ui, dv-connect, power-platform-architect, power-platform-mcp-connector-suite, mcp-copilot-studio-server-generator, add-knowledge, add-skill |
| `m365-copilot` | agents-sdk-to-prod, teams-app-manifest, agents-sdk-dotnet-otel, agents-sdk-typescript-otel, agents-sdk-python-otel, agents-sdk-provision, declarative-agents, typespec-create-agent, typespec-create-api-plugin, msgraph-sdk, mcp-create-declarative-agent, mcp-deploy-manage-agents, m365-agent-evaluator, ui-widget-developer |
| `foundry` | microsoft-foundry, use-ai-gateway, azure-aigateway, caira, foundry-iq, appinsights-instrumentation |
| `fabric` | sqldw-cli, sqldb-cli, eventhouse-cli, eventstream-cli, spark-cli, dataflows-cli, databricks-migration, pipeline-migration |
| `dotnet` | migrate-dotnet8-to-dotnet9, migrate-dotnet9-to-dotnet10, migrate-dotnet10-to-dotnet11, migrate-nullable-references, dotnet-aot-compat, msbuild-modernization, convert-to-cpm, migrate-vstest-to-mtp, test-value-evidence, coverage-analysis, dotnet-breaking-changes, exp-mock-usage-analysis, analyzing-dotnet-performance, microbenchmarking, dotnet-trace-collect, dotnet-webapi, author-component, optimizing-ef-core-queries, csharp-refactoring, msbuild |

For `power-platform`, read [power-platform-official-resources.md](power-platform-official-resources.md) before asking to install resources, including during an Init proposal. Its core skills, optional community supplements, complete support files, and separately approved preview bundle are distinct choices; a generic install-all answer without that disclosure is not preview approval.

For `m365-copilot`, read [m365-copilot-platform-options.md](m365-copilot-platform-options.md) before asking to install resources, including during an Init proposal. Its six core Agents SDK skills, optional community supplements, packaged support files, and two separately approved `microsoft/work-iq` preview skills are distinct choices; a generic install-all answer without that disclosure is not preview approval.

For `dotnet`, read [dotnet-platform-options.md](dotnet-platform-options.md) before asking to install resources, including during an Init proposal. Its eighteen core `dotnet/skills` entries, packaged support files, and two separately approved preview skills (`migrate-dotnet10-to-dotnet11` and `exp-mock-usage-analysis`) are distinct choices; a generic install-all answer without that disclosure is not preview approval.

After packs are selected, rerun `Get-SquadInitContext.ps1 -Pack <packs>` and
inspect `packResources`. It reports each registered pack skill, whether the
native host inventory exposes it, whether it exists only on disk awaiting reload,
its exact install entry, prerequisites, origin and license.

For missing skills, ask once whether to install all, install a selected subset,
continue without them, or change the pack selection. Approval authorizes running
`Install-SquadPackResources.ps1 -RepoRoot <repo> -Pack <packs> [-Resource <approved names>] [-AvailableSkill <host-visible names>] -ReceiptPath <new-receipt.json> -Confirmed`
for the approved resources now; do not merely print the commands. Run it from
the consumer repository and require receipt `status: PASS`; exit 0 with
`status: PLANNED` is only a preview. A native plugin or
`npx` confirmation remains visible and must succeed. Never install a prerequisite,
CLI, MCP server, account permission, tenant consent or cloud resource from this
step. A failed or cancelled command remains missing.

The installer receipt is audit evidence, not an Init credential. Any resource
reported as `installed` or present only on disk requires a host reload. Stop
before Init or roster expansion, reload the host, rerun preflight, and record one
final `resourceDecisions` entry per listed resource: host-visible `available`, or
explicitly `declined`. Copy the relevant native host inventory into
`availableSkills`; the deterministic planners reject missing, unknown,
on-disk-only, or invented availability.

### Pack Discovery

An explicit `pack=` hint wins; otherwise either repository signals or the request's domain is enough to propose a pack, never to apply it. Present the profile and proposed packs together for one confirmation. Offer install commands for missing registered resources instead of seeding absent roles.

| Pack | Repository signals |
|------|--------------------|
| `power-platform` | `.cdsproj`, `solution.xml`, a `pac` CLI configuration, a canvas app `.msapp`, a Dataverse solution folder, `agent.mcs.yml`, or Copilot Studio `settings.mcs.yml` with `template: cliagent-*`. Follow the PP guidance for core skills versus the separately approved preview bundle; neither a signal nor pack acceptance approves preview setup |
| `m365-copilot` | A `declarativeAgent.json` or `manifest.json` Copilot agent manifest, `mcpPlugin.json`, `m365agents.yml`, `teamsapp.yml`, `appPackage/`, `main.tsp` importing `@microsoft/typespec-m365-copilot`, or Microsoft 365 Agents SDK dependencies (`Microsoft.Agents.Hosting.AspNetCore`, `@microsoft/agents-hosting`, `microsoft-agents-hosting-aiohttp`). Follow the M365 guidance for core skills versus the separately approved preview skills; neither a signal nor pack acceptance approves preview setup |
| `aws` | CloudFormation, including `template.yaml` with `AWS::Serverless`; `cdk.json`, `samconfig.toml`, `serverless.yml`, `.aws/`, or Terraform's `hashicorp/aws` provider |
| `foundry` | SDK dependencies (`azure-ai-projects`, `azure-ai-agents`, `Azure.AI.Projects`, `Azure.AI.Agents.Persistent`, `@azure/ai-projects`, `@azure/ai-agents`), `azure.yaml` using the `azure.ai.agents` azd extension, or `AZURE_AI_PROJECT_ENDPOINT` / a `services.ai.azure.com/api/projects` URL in configuration or `.env` templates. Select `foundry-iq` and `appinsights-instrumentation` only when this pack is active |
| `fabric` | A Fabric `.platform` item whose type is Warehouse, SQLDatabase, Eventhouse, Eventstream, Notebook, or Dataflow, or a Databricks-to-Fabric migration note. Select the admitted Fabric skills only when this pack is active |
| `dotnet` | `*.sln`, `*.slnx`, `*.csproj`, `*.fsproj`, `*.vbproj`, `Directory.Build.props`, `Directory.Build.targets`, `Directory.Packages.props`, or `global.json` declaring `sdk`. Follow the `.NET` guidance for core official skills versus the separately approved preview skills; neither a signal nor pack acceptance approves preview setup or SDK installation |

**A pack is not a federation.** One piece of work that needs extra expertise is a profile plus a pack, because those roles must share a plan, a council, and a review. Two streams of work with separate deliverables and owners is a federation. Federation does not reach a vertical any faster — a sub-squad is seeded from a profile and takes the pack the same way any roster does — so building a sub-squad to obtain a role buys a duplicated spine and a second state tree for no extra reach. See *Pack or Federation* in `.github/instructions/squad/squad-roster.instructions.md`.
