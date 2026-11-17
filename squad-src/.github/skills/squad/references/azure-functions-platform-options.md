---
name: squad-azure-functions-platform-options
description: "Opt-in Azure Functions official skill ownership, prerequisites, packaged support files, preview boundaries, and non-admitted candidates."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-11-13"
---
<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

# Azure Functions Platform Options

Read this reference for an `azure-functions` proposal's resource preflight, or when the resolved root's `team.md` `Packs:` line includes `azure-functions`. A proposal permits explanation, not skill selection or installation. Removing the pack stops squad selection and workload guidance. It does not uninstall or hide a host-installed skill.

Host visibility is not selection. A declined resource stays unavailable to the squad even if the host exposes it. The preview jobs below also require explicit preview approval; accepting the pack alone is not that approval.

The pack adds no new catalog role and no external agent Primary or Alternate. It reuses `developer`, `deployer`, `tester`, `azure-diagnose`, and `modernizer` through their existing local charters. `full +azure-functions` and `azure +azure-functions` add no roles; `default +azure-functions` adds `deployer`, `azure-diagnose`, and `modernizer`; `operations +azure-functions` adds `modernizer`; `modernization +azure-functions` adds `deployer` and `azure-diagnose`.

## Paths

| Request | Agent | Skill |
|---|---|---|
| Shared Azure Functions runtime/language (`csharp`, `python`, `node-typescript`, `java`, `powershell`, `go`, `durable-functions`) and trigger/binding extension references | `Squad Implementor` | `azure-functions-common` |
| Scaffold a new Azure Functions v4 project or add triggers/bindings to an existing project | `Squad Implementor` | `azure-functions-create` |
| Azure Functions Hosted Skills authoring (`*.agent.md`, `agents.config.yaml`, remote HTTP `mcp.json`, and Durable Task Scheduler Bicep assets) (preview) | `Squad Implementor` | `azure-functions-hosted-skills` |
| Azure Functions deployment context (Flex Consumption `FC1` `functionAppConfig`, Linux Python/Go constraints, Function auth posture, App Insights, and `GET` endpoint verification) inside gated `infra/{track}/{project}` deployments | `Squad Deployer` | `azure-functions-deploy` |
| Local Azure Functions workspace code, `host.json`, trigger/binding, IaC, and dependency audit | `Squad Reviewer` | `azure-functions-doctor` |
| Production-readiness best-practices review across Function App runtime, scale, auth, networking, observability, and bindings | `Squad Reviewer` | `azure-functions-best-practices` |
| Read-only deployed Function App SKU/plan, runtime, Flex config, networking, identity, redacted setting-name, and trigger inventory | `Squad Azure Diagnose` | `azure-functions-inventory` |
| Read-only deployed Function App status, Resource Health, Azure Monitor metrics, Application Insights KQL, and Activity Log triage | `Squad Azure Diagnose` | `azure-functions-health-status` |
| Read-only Azure Functions deployment, runtime, trigger/binding, and language-worker root-cause investigation | `Squad Azure Diagnose` | `azure-functions-diagnostics` |
| Azure Functions programming-model migration plan (C# in-process to `.NET` isolated worker) (preview) | `Squad Modernization Planner` | `azure-functions-update` |
| Cross-cloud migration (such as AWS Lambda to Azure Functions) or general `.NET` SDK band upgrades | `Squad Modernization Planner` | `modernizer` (plus `dotnet` pack when `.NET` target-framework upgrades are in scope) |

`Squad Reviewer`, `Squad Azure Diagnose`, `Squad Modernization Planner`, and `Squad As-Built Author` may also read non-declined `azure-functions-common` on demand through `../azure-functions-common/references/routing.md` when interpreting language-worker or trigger/binding behavior. When `Squad Implementor` executes an approved C# in-process-to-isolated migration plan phase, it may read non-declined `azure-functions-update` (`references/dotnet-isolated.md`) only when the user explicitly approved that preview workflow, while preserving `.copilot-tracking/changes/` and never running `git commit`.

## Installation and readiness

Use the shared **Pack Resource Preflight** in `profiles-and-packs.md` at Init, pack addition, and a missing-resource escalation. `Registered Pack Skills` maps all ten `azure-functions` skills to their exact opt-in directory entries in `Azure/azure-functions-skills@34e17220ff073b29a0be5bd541f32d287118165f` (the CI-verified `.github/plugins/azure-functions-skills/skills/` Agent Skills payload): eight core entries and two separately approved preview entries (`azure-functions-update` and `azure-functions-hosted-skills`).

1. Explain the missing resources in plain language. Offer the eight core official Azure Functions skills (`azure-functions-common`, `azure-functions-create`, `azure-functions-deploy`, `azure-functions-doctor`, `azure-functions-best-practices`, `azure-functions-inventory`, `azure-functions-health-status`, and `azure-functions-diagnostics`), the two separately approved preview skills, a selected subset, or continuing without them. Recommend keeping `azure-functions-common` in any subset that includes `azure-functions-best-practices`, `azure-functions-inventory`, `azure-functions-health-status`, or `azure-functions-diagnostics`, because those skills route language and binding references through `../azure-functions-common/references/routing.md`. Preview is not the default; a generic install-all answer without preview disclosure is not preview approval.
2. Before preview approval, disclose the preview posture and excluded execution steps for both preview entries (published in `Azure/azure-functions-skills` `0.0.7-preview`):
   * `azure-functions-update` is marked `Draft` upstream and currently implements only the C# in-process to `.NET` isolated worker scenario (requiring explicit user selection). `Squad Modernization Planner` plans the programming-model migration read-only under `.copilot-tracking/plans/`, keeping language-version and hosting-plan changes separate, and `Squad Implementor` edits source only from an approved plan without installing tools or running `git commit`.
   * `azure-functions-hosted-skills` targets the preview Azure Functions Hosted Skills / `azurefunctions-agents-runtime` model (`*.agent.md`, `agents.config.yaml`, remote HTTP `mcp.json`, and Durable Task Scheduler Bicep). `Squad Implementor` authors local project files only from an approved plan; it never provisions Foundry models, Azure Container Apps dynamic sessions, or Connector Namespaces, and never runs `azd up` or `telemetry.mjs`.
   * All ten entries install from `.github/plugins/azure-functions-skills/skills/<skill>` as self-contained pinned directories under `.agents/skills/<skill>/` with no `copilot-hooks.json`, no `telemetry.mjs` runtime, and no `.mcp.json` (`@azure/mcp@latest`).
3. After the user's resource choices, run `Install-SquadPackResources.ps1` with `-Pack azure-functions`, the approved `-Resource` names, a new receipt path, and `-Confirmed`. The helper installs skill payloads only — never Azure Functions Core Tools (`func`), `az`, `azd`, language runtimes, `@azure/functions-skills`, or MCP servers. Preserve native confirmation prompts; a failed or cancelled command remains missing.
4. Require a `PASS` receipt, then stop for a host reload. `PLANNED` is not installation, and an on-disk skill is not yet host-visible. After reload, rerun preflight with the actual native host inventory and record every listed skill as `available` or explicitly `declined`. Pass the preview approval's decision reference or current explicit request with its dispatch; an `available` flag alone is not preview permission. Declining preview skills does not prevent applying the pack or using the other approved resources.
5. Check the packaged support files below before claiming the requested job is ready. Report installed payloads, host visibility, missing packaged support files (including sibling `.agents/skills/azure-functions-common/` when routed), and `func` / `az` / `azd` prerequisites separately. Resume a failed setup at the failed step, without inventing availability or overwriting existing files.

The shared installer runs the exact pinned APM entries without a Functions-specific installer. APM takes **skill directories**, not `SKILL.md` file paths. Give the user the published [English setup guide](https://peter-n91.github.io/hve-squad/usage.html#azure-functions-setup) or [French setup guide](https://peter-n91.github.io/hve-squad/fr/usage.html#azure-functions-setup) for detailed commands and troubleshooting; the consumer repository need not contain this project's documentation.

### Packaged support files and optional reference snapshot

Each pinned `azure-functions` directory install carries its own `references/`, `scripts/`, and `assets/` inside `.agents/skills/<skill>/` (and `apm_modules/`) with no hooks or MCP configuration. Verify the required files below under `.agents/skills/<skill>/` before use; `azure-functions-deploy` is self-contained in `SKILL.md`. If required files (or `.agents/skills/azure-functions-common/references/routing.md` for a skill routing shared language/binding docs) are missing, stop and give the setup remedy instead of answering from memory.

| Skills | Verified source | Required packaged support files |
|---|---|---|
| `azure-functions-common` | `Azure/azure-functions-skills@34e17220ff073b29a0be5bd541f32d287118165f` | `references/routing.md`, `references/local-emulators.md`, `references/languages/csharp.md`, `references/languages/python.md`, `references/languages/node-typescript.md`, `references/languages/durable-functions.md`, `references/extensions/http.md`, and `references/extensions/service-bus.md` |
| `azure-functions-create` | same pin | `references/go-project.md` and `references/language-snippets.md` |
| `azure-functions-doctor` | same pin | `references/routing.md`, `references/source-only-checks.md`, `references/iac-azure-resource-checks.md`, `references/ai-semantic-checks.md`, `references/language-checks.md`, and `references/supply-chain-checks.md` |
| `azure-functions-best-practices` | same pin | `references/review-checklist.md` and `references/remediation-patterns.md` |
| `azure-functions-inventory` | same pin | `references/inventory-commands.md`, `scripts/get-functionapp-inventory.ps1`, and `scripts/get-functionapp-inventory.sh` |
| `azure-functions-health-status` | same pin | `references/health-status-commands-and-kql.md`, `scripts/get-functionapp-health-status.ps1`, and `scripts/get-functionapp-health-status.sh` |
| `azure-functions-diagnostics` | same pin | `references/workflow.md` and `references/evidence-checklist.md` |
| `azure-functions-update` (preview) | same pin | `references/dotnet-isolated.md` |
| `azure-functions-hosted-skills` (preview) | same pin | `assets/infra/app/durable-task-scheduler.bicep`, `assets/infra/app/trigger-config.bicep`, `references/agent-authoring.md`, `references/agent-files.md`, `references/infra-and-deployment.md`, `references/models.md`, `references/project-files.md`, `references/triggers.md`, and `references/troubleshooting.md` |

When offline access to additional `Azure/azure-functions-skills` documentation (such as `docs/azure-skills-boundary.md`) is wanted, ask before fetching a read-only source snapshot into `apm_modules/.squad-pack-support/azure-functions-skills-34e1722` with repository-local `core.longpaths=true`. Verify its detached `HEAD` matches `34e17220ff073b29a0be5bd541f32d287118165f` and do not register that checkout as a plugin or working project. An installed skill or snapshot at a different ref requires re-verification before use.

### Preview selection and exclusions

`azure-functions-update` (`Draft`) owns Azure Functions programming-model migration, currently C# in-process to `.NET` isolated worker, and requires both explicit preview approval and user selection of that migration workflow. `Squad Modernization Planner` writes the migration plan read-only; `Squad Implementor` edits project files only from an approved plan. Keep `.NET` target-framework upgrades and hosting-plan SKU changes in separate approved stages.

`azure-functions-hosted-skills` authors cloud-hosted intelligent capabilities on the preview `azurefunctions-agents-runtime` (`*.agent.md`, `agents.config.yaml`, remote HTTP `mcp.json`, and Bicep templates). `Squad Implementor` authors local files under `.copilot-tracking/changes/` only when explicitly approved; live `azd` provisioning, Foundry model deployment, Container Apps dynamic sessions, and Connector Namespace consent stay outside `developer`.

Other upstream `Azure/azure-functions-skills` items were gated at `34e17220ff073b29a0be5bd541f32d287118165f` and remain **not registered squad capabilities**:

* Whole-plugin `azure-functions-skills@azure-functions-skills` (`0.0.7-preview`), `templates/skills/` source inputs (which include non-Agent-Skills `title:` and `category:` frontmatter stripped by `build:plugin-payload`), and the `@azure/functions-skills` npm companion CLI remain unregistered so `copilot-hooks.json`, `hooks/runtime/telemetry.mjs` (`azure_deployment_observed` ARM queries), and unpinned `@azure/mcp@latest` in `.mcp.json` are never activated silently.
* `azure-functions-help` is a runtime skill router superseded by Squad's own routing and this reference; `azure-functions-setup` recommends OS package-manager installs (`winget`, `brew`, MSI) and prompts to install the whole `azure@azure-skills` plugin; and `azure-functions-feedback` files issues or pull requests against `Azure/azure-functions-skills`.
* `azure-functions-hosted-skills-migrate`, `azure-functions-connector-create`, `azure-functions-connector-mcp`, and `azure-functions-connector-validate` drive interactive outbound-data migration prompts, privileged `Microsoft.Web/connectorGateways` creation, browser OAuth consent at `connectors.azure.com`, live `mcpserverconfigs` registration, and live SaaS smoke tests, and remain unregistered and unblocked.

## Boundaries

* Azure Functions Core Tools (`func`), `az`, `azd`, language worker toolchains, and `@azure/mcp` count as runtime CLI/service prerequisites under *Tier Qualification* test 3, and Azure Functions is an optional serverless vertical under test 4, so every row is `opt-in` and none is `bundled` in `apm.yml`.
* `Squad Reviewer` (`tester`), `Squad Azure Diagnose` (`azure-diagnose`), and `Squad Modernization Planner` (`modernizer`) remain strictly read-only over Function Apps and workspace source: `tester` audits local workspaces (`azure-functions-doctor`) and reviews production readiness (`azure-functions-best-practices`) without applying fixes, running project code, or installing packages; `azure-diagnose` collects redacted setting-name inventories, health/KQL signals, and root-cause hypotheses without restarting apps or changing app settings; `modernizer` plans isolated-worker migrations without editing files.
* `Squad Deployer` (`deployer`) uses `azure-functions-deploy` strictly for Functions deployment and verification context (Flex Consumption `FC1` `functionAppConfig`, Linux Python/Go limits, auth posture, App Insights, and `GET` rather than `HEAD` endpoint checks) inside its own OIDC dry-run (`what-if` / `terraform plan`), `azure-deployment-preflight`, and Impactful-Action Gate workflow; it never prompts to install `azure@azure-skills`, never chains into unregistered `azure-prepare` / `azure-validate` / `azure-deploy` or `azure-functions-setup`, never runs `telemetry.mjs`, and never runs `azd up` or `func azure functionapp publish` without explicit human approval.
* `Squad Implementor` (`developer`) scaffolds or edits Functions projects only from an approved plan phase under `.copilot-tracking/changes/`, and never runs `azd up`, `func azure functionapp publish`, `git commit`, or Connector Namespace provisioning.
* Existing bundled and community rows (`azure-deployment-preflight`, `microsoft-agent-framework`, `semantic-kernel`, `azure-well-architected-review`) remain distinct and are neither superseded nor blocklisted.
