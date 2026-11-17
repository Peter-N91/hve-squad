---
name: squad-azure-cloud-platform-options
description: "Opt-in Azure Cloud and FinOps official skill ownership, preview boundary, prerequisites, packaged support files, and non-admitted candidates."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-11-17"
---
<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

# Azure Cloud and FinOps Platform Options

Read this reference for an `azure-cloud` proposal's resource preflight, or when the resolved root's `team.md` `Packs:` line includes `azure-cloud`. A proposal permits explanation, not skill selection or installation. Removing the pack stops squad selection and workload guidance. It does not uninstall or hide a host-installed skill.

Host visibility is not selection. A declined resource stays unavailable to the squad even if the host exposes it.

Preview is not the default. Standard-scale Azure Local (`azure-local`) is part of the core official set, while rack-scale Azure Local (`azure-local-multi-rack`) is a preview workflow over `Microsoft.NetworkCloud` and `Microsoft.ManagedNetworkFabric`: select it only when `azure-cloud` is active, its resource decision is not `declined`, and the user explicitly approved the preview.

The pack adds no new catalog role and no external agent Primary or Alternate. It reuses `cost-manager`, `azure-diagnose`, `asbuilt-author`, `azure-architect`, and `modernizer` through their existing local charters. `full +azure-cloud` and `azure +azure-cloud` add no roles; `default +azure-cloud` adds `asbuilt-author`, `azure-architect`, `azure-diagnose`, `cost-manager`, and `modernizer`; `modernization +azure-cloud` adds `azure-diagnose`; `operations +azure-cloud` adds `azure-architect`, `cost-manager`, and `modernizer`; `architecture +azure-cloud` adds `asbuilt-author`, `azure-diagnose`, and `modernizer`.

## Paths

| Request | Agent | Skill |
|---|---|---|
| Existing-scope Azure spend forecasts, planned workload pricing, or negotiated EA/MCA Price Sheet rate-card lookups | `Squad Cost Manager` | `cost-estimation` (alongside bundled `azure-pricing` for public Retail Prices) |
| Idle/orphaned Azure resource discovery, workload rightsizing, and Reservation or Savings Plan utilization, transactions, and commitment recommendations | `Squad Cost Manager` | `cost-optimization` |
| Historical Azure spend queries, bill-spike or anomaly investigation, AKS namespace/idle cost analysis, and Foundry/AI service spend breakdown | `Squad Cost Manager` | `cost-analysis` |
| Configured Azure budget health, overrun alerts, `CostCenter` tag coverage, Azure Policy SKU/region guardrails, and `confirm`-tier budget recommendations | `Squad Cost Manager` | `cost-governance` |
| Read-only Azure production troubleshooting across App Service, Container Apps, Function Apps, Azure VMs (RDP/SSH/NSG), and Event Hubs / Service Bus SDKs via AppLens, Monitor/KQL, Resource Health, or supplied evidence | `Squad Azure Diagnose` | `azure-diagnostics` |
| Post-deploy `azqr` compliance scans, Resource Graph posture checks, and Key Vault key/secret/certificate expiration audits for the compliance matrix | `Squad As-Built Author` | `azure-compliance` |
| Cross-subscription Azure Resource Graph (`az graph query`) inventory, orphaned-resource discovery, and tag audits (including App Service and Container Apps) | `Squad As-Built Author` | `azure-resource-lookup` |
| Deployed resource-group relationship mapping and Mermaid topology diagrams with secret placeholders for as-built handoff | `Squad As-Built Author` | `azure-resource-visualizer` |
| Read-only PaaS reliability posture checklist (App Service and Azure Functions zone redundancy, ZRS/GZRS storage, health probes, and multi-region failover) for HLD/LLD planning | `Squad Azure Architect` | `azure-reliability` |
| Regional subscription quota, usage, and capacity validation (`az quota`) during region and SKU selection | `Squad Azure Architect` | `azure-quotas` |
| Standard-scale (1–16 node hyperconverged, up to 64 disaggregated, and rack-aware) Azure Local / Azure Stack HCI sizing, Arc resource bridge, logical networks, SDN, and AKS-hybrid HLD/LLD planning | `Squad Azure Architect` | `azure-local` |
| Explicitly approved preview: rack-scale (100+ machine, aggregation + compute racks, Network Fabric Controller, Cluster Manager, isolation domains) Azure Local HLD/LLD planning | `Squad Azure Architect` | `azure-local-multi-rack` |
| Cross-cloud workload assessment and phased migration plan (AWS Lambda, Elastic Beanstalk, Heroku, App Engine, Fargate/ECS, GKE/EKS, Cloud Run, or Spring Apps to Azure) | `Squad Modernization Planner` | `azure-cloud-migrate` |
| Azure hosting-plan, SKU, or SDK upgrade assessment and phased plan (Functions Consumption to Flex Consumption, Azure Cache for Redis ACR/ACRE to Managed Redis AMR, or legacy Java `com.microsoft.azure.*` to `com.azure.*`) | `Squad Modernization Planner` | `azure-upgrade` |
| Converting an Azure HLD/LLD or reliability/migration design into Bicep or Terraform under `infra/{track}/{project}` | `Squad IaC Author` | existing `iac-author` charter; `azure-architect` and `modernizer` plan read-only |
| OIDC dry-run (`what-if` / `terraform plan`), `azure-deployment-preflight` checks, and gated Azure deployment | `Squad Deployer` | existing `deployer` charter behind the Impactful-Action Gate |

When `Squad Azure Diagnose` investigates an Azure Local incident while `azure-cloud` is active, it may read non-declined `azure-local` (`workflows/troubleshooting/troubleshooting.md`), and when preview is also explicitly approved it may read non-declined `azure-local-multi-rack` (`workflows/operate-and-monitor/operate-and-monitor.md`), keeping every check strictly read-only. When `Squad Deployer` runs its dry-run preflight while `azure-cloud` is active, it may consult non-declined `azure-quotas` read-only for regional capacity checks without submitting quota-increase requests. When `Squad Implementor` executes an approved cross-cloud or Java SDK modernization plan phase while `azure-cloud` is active, it may read non-declined `azure-cloud-migrate` or `azure-upgrade` packaged guides while recording changes under `.copilot-tracking/changes/` only, without creating `<workspace>-azure/` directories outside Deliverable Root, provisioning `<source>-flex` resources, or chaining into `azure-prepare`, `azure-validate`, or `azure-deploy`.

## Installation and readiness

Use the shared **Pack Resource Preflight** in `profiles-and-packs.md` at Init, pack addition, and a missing-resource escalation. `Registered Pack Skills` maps all fourteen `azure-cloud` skills to their exact opt-in directory entries in `microsoft/azure-skills@65922d293cba61a40d5edf61a9eb4b6b0e799788`.

1. Explain the missing resources in plain language. Separate the thirteen core official `azure-cloud` skills (four FinOps cost skills, cross-service diagnostics, `azqr`/Key Vault compliance, Resource Graph lookup, Mermaid resource visualizer, PaaS reliability assessment, regional quota checks, standard Azure Local, cross-cloud migration, and Azure plan/SKU/SDK upgrade) from the one optional preview skill (`azure-local-multi-rack`). Offer all thirteen core skills, a selected subset, or continuing without them, and ask separately before including `azure-local-multi-rack`. Say which requested job each choice enables; generic install-all approval without preview disclosure does not approve `azure-local-multi-rack`.
2. Disclose that all fourteen entries install as self-contained pinned skill directories under `.agents/skills/<skill>/` with no hooks (`copilot-hooks.json` / `ghcfa-telem`) and no `.mcp.json`, `.github/mcp.json`, or `mcpServers` entries.
3. After the user's resource choices, run `Install-SquadPackResources.ps1` with `-Pack azure-cloud`, the approved `-Resource` names, a new receipt path, and `-Confirmed`. The helper installs skill payloads only — never `az`, `azqr`, `resource-graph` or `quota` CLI extensions, `@azure/mcp`, ARM Cost Management MCP, credentials, or Azure resources. Preserve native confirmation prompts; a failed or cancelled command remains missing.
4. Require a `PASS` receipt, then stop for a host reload. `PLANNED` is not installation, and an on-disk skill is not yet host-visible. After reload, rerun preflight with the actual native host inventory and record every listed skill as `available` or explicitly `declined`.
5. Check the packaged support files below before claiming the requested job is ready. Report installed payloads, host visibility, missing packaged support files, and `az` / RBAC / billing-scope prerequisites separately. Resume a failed setup at the failed step, without inventing availability or overwriting existing files.

The shared installer runs the exact pinned APM entries without an Azure-specific installer. APM takes **skill directories**, not `SKILL.md` file paths. Give the user the published [English setup guide](https://peter-n91.github.io/hve-squad/usage.html#azure-cloud-setup) or [French setup guide](https://peter-n91.github.io/hve-squad/fr/usage.html#azure-cloud-setup) for detailed commands and troubleshooting; the consumer repository need not contain this project's documentation.

### Packaged support files and optional reference snapshot

Each pinned `azure-cloud` directory install carries its own `references/`, `scripts/`, `assets/`, and `workflows/` inside `.agents/skills/<skill>/` (and `apm_modules/`) with no parent-plugin hook or MCP configuration. Verify the required files below under the top-level `.agents/skills/<skill>/` root before use; if they are missing, stop and give the setup remedy instead of answering from memory.

| Skills | Verified source | Required packaged support files |
|---|---|---|
| `cost-estimation` | `microsoft/azure-skills@65922d293cba61a40d5edf61a9eb4b6b0e799788` | `references/cost-forecast/workflow.md`, `references/pricing-estimate.md`, and `references/tool-fallback.md` |
| `cost-optimization` | same pin | `references/optimization.md`, `references/commitments.md`, `references/resource-graph.md`, and `references/tool-fallback.md` |
| `cost-analysis` | same pin | `references/cost-query/workflow.md`, `references/cost-investigation.md`, `references/aks-cost-analysis.md`, `references/ai-cost-analysis.md`, and `references/tools-and-safety.md` |
| `cost-governance` | same pin | `references/budget-health.md`, `references/budget-setup.md`, `references/guardrails.md`, and `references/tool-fallback.md` |
| `azure-diagnostics` | same pin | `references/kql-queries.md`, `references/azure-resource-graph.md`, `references/container-apps/README.md`, `references/app-service/README.md`, `references/functions/README.md`, `troubleshooting/compute/vm-troubleshooting.md`, and `troubleshooting/messaging/README.md` |
| `azure-compliance` | same pin | `references/azure-quick-review.md`, `references/azure-keyvault-expiration-audit.md`, `references/azqr-recommendations.md`, and `references/azure-resource-graph.md` |
| `azure-resource-lookup` | same pin | `references/azure-resource-graph.md` |
| `azure-resource-visualizer` | same pin | `references/azure-resource-graph.md`, `assets/example-diagram.md`, and `assets/template-architecture.md` |
| `azure-reliability` | same pin | `references/zone-redundancy-checks.md`, `references/storage-redundancy-checks.md`, `references/multi-region-checks.md`, `references/health-probe-checks.md`, `references/services/app-service/reliability.md`, and `references/services/functions/reliability.md` |
| `azure-quotas` | same pin | `references/commands.md`, `references/advanced-commands.md`, `scripts/check-quota.ps1`, and `scripts/check-quota.sh` |
| `azure-local` | same pin | `references/docs-map.md`, `references/mcp-and-cli-tools.md`, `references/safety-rules.md`, `workflows/plan-and-deploy/plan-and-deploy.md`, and `workflows/troubleshooting/troubleshooting.md` |
| `azure-local-multi-rack` (preview) | same pin | `references/docs-map.md`, `references/cli-and-prereqs.md`, `references/safety-rules.md`, `workflows/plan-and-deploy/plan-and-deploy.md`, and `workflows/operate-and-monitor/operate-and-monitor.md` |
| `azure-cloud-migrate` | same pin | `references/workflow-details.md`, `references/services/functions/lambda-to-functions.md`, `references/services/app-service/beanstalk-to-app-service.md`, and `references/services/container-apps/fargate-to-container-apps.md` |
| `azure-upgrade` | same pin | `references/global-rules.md`, `references/workflow-details.md`, `references/services/functions/consumption-to-flex/linux/workflow.md`, `references/services/redis/redis-to-amr.md`, and `references/languages/java/README.md` |

When offline access to additional `microsoft/azure-skills` documentation is wanted, ask before fetching a read-only source snapshot into `apm_modules/.squad-pack-support/azure-skills-65922d2` with repository-local `core.longpaths=true`. Verify its detached `HEAD` matches `65922d293cba61a40d5edf61a9eb4b6b0e799788` and do not register that checkout as a plugin or working project. An installed skill or snapshot at a different ref requires re-verification before use.

### Exclusions and blocklisted candidates

Other Azure cost, FinOps, Advisor, and deployment candidates were gated and are **not registered squad capabilities**:

* Community `az-cost-optimize` (`github/awesome-copilot@dc0083dbe22133bfa7ce3500dee85e187e0cd47a`) is superseded by the official `cost-optimization`, `cost-estimation`, `cost-analysis`, and `cost-governance` skills (`microsoft/azure-skills@65922d293cba61a40d5edf61a9eb4b6b0e799788`) and is recorded in *External Cast Blocklist*; bundled `azure-pricing` remains unchanged because `cost-estimation` requires authenticated Cost Management Forecast and EA/MCA Price Sheet APIs beyond public Retail Prices (*Tier Qualification* test 3).
* `microsoft/finops-toolkit@6ad89cd25ff873794cf5dd9eb5f6daa8e23201e9` (`finops-toolkit` and its five agents `azure-capacity-manager`, `chief-financial-officer`, `finops-practitioner`, `ftk-database-query`, `ftk-hubs-agent`) fails raw GitHub APM directory installation because `Build-AgentPlugin.ps1` is required to materialize `src/queries` and `docs-mslearn` over cross-tree git symlinks, requires a deployed FinOps Hub Azure Data Explorer (`kusto_query`) or Fabric RTI `Hub` database plus `.ftk/environments.local.md`, and duplicates `cost-manager` and `azure-architect`; `.github/plugins/azure-advisor` (`azure-advisor`, `azure-advisor-cost-optimization`, `azure-advisor-actionability`) binds to beta `@azure/mcp@4.0.0-beta.7` `advisor_*` operations while forbidding ARM, CLI, Cost Management, or Resource Graph fallback (`skills/squad/references/rules/squad-mcp-capability.md` violation). Both sets are recorded in *External Cast Blocklist*.
* `azure-prepare`, `azure-validate`, `azure-deploy`, and `azure-enterprise-infra-planner` (`microsoft/azure-skills@65922d293cba61a40d5edf61a9eb4b6b0e799788`) fail Gate steps 4 and 5: `azure-validate` and `azure-deploy` enforce mandatory `⛔ STOP` gates requiring `.azure/deployment-plan.md` authored by `azure-prepare` (`Ready for Validation` / `Validated`) and refuse standalone validation of `infra/{track}/{project}`, while `azure-prepare` and `azure-enterprise-infra-planner` combine architecture planning (`.azure/`), Bicep/Terraform generation (`infra/`), and live deployment (`azd up` / `az deployment` / `terraform apply`) across `lead`, `azure-architect`, `iac-author`, `developer`, and `deployer`. All four are recorded in *External Cast Blocklist*, and community `azure-deployment-preflight` stays registered and unblocked so unpacked squads keep their existing `deployer` preflight behavior.
* Whole-plugin install forms (`azure@azure-skills`, `azure-cost@azure-skills`, `azure-advisor@azure-skills`, `azure-local-skills@azure-skills`, `azure-observability@azure-skills`, and `azure-kusto-graph-skills@azure-skills`) bundle `copilot-hooks.json` (`install-telemetry` / `ghcfa-telem`) and plugin `mcp.json` configurations, so only pinned skill directories are registered. Journey-coordinating `.github/plugins/azure-observability` skills, `discover-azure-skills`, `azure-ai`, `azure-app-onboard*`, `python-appservice-deploy`, `azure-compute`, `azure-storage`, `azure-messaging`, `azure-kusto*`, and live tenant identity skills (`entra-agent-id`, `entra-app-registration`) remain unregistered and unblocked.

## Boundaries

* Authenticated Azure CLI (`az`), Cost Management Forecast / Query / Price Sheet / Benefit / Budgets APIs, Azure Resource Graph, `azqr`, `az quota`, and `@azure/mcp` count as runtime CLI/service prerequisites under *Tier Qualification* test 3, and extended Azure cloud FinOps, compliance, diagnostics, reliability, migration, and Azure Local workflows arrive as an optional technology vertical under test 4, so every row is `opt-in` and bundled `azure-pricing` stays unchanged in `apm.yml`.
* `Squad Cost Manager` (`cost-manager`), `Squad Azure Diagnose` (`azure-diagnose`), `Squad As-Built Author` (`asbuilt-author`), `Squad Azure Architect` (`azure-architect`), and `Squad Modernization Planner` (`modernizer`) remain strictly read-only over live Azure resources: `cost-manager` labels estimates indicative and flags any budget, commitment, or SKU recommendation at the `confirm` tier without purchasing, resizing, or creating budgets; `azure-diagnose` triages read-only with secret values redacted; `asbuilt-author` inventories, scans compliance, and maps Mermaid diagrams with secret placeholders without mutating resources or Vault items; `azure-architect` assesses PaaS reliability, regional quotas, and Azure Local topologies read-only under `docs/architecture/` without executing CLI/IaC remediation writes or cluster mutations; `modernizer` writes phased cross-cloud and Azure upgrade plans under `.copilot-tracking/plans/` without creating `<workspace>-azure/` directories, provisioning `<source>-flex` resources, or editing source.
* `Squad Implementor` (`developer`) authors code changes only from an approved plan phase under `.copilot-tracking/changes/`, and `Squad Deployer` (`deployer`) keeps its OIDC dry-run (`what-if` / `terraform plan`), `azure-deployment-preflight`, and Impactful-Action Gate workflow without chaining into blocklisted `azure-prepare`, `azure-validate`, `azure-deploy`, or `azure-enterprise-infra-planner`.
* Existing bundled and community rows (`azure-pricing`, `azure-deployment-preflight`, `update-avm-modules-in-bicep`, `import-infrastructure-as-code`, `azure-well-architected-review`) and sibling `foundry`, `aks`, and `azure-functions` pack skills remain unchanged.