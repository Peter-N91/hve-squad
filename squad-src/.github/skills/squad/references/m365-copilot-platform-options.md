---
name: squad-m365-copilot-platform-options
description: "Opt-in M365 Copilot official skill ownership, prerequisites, preview boundaries, and community Alternate split."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-11-12"
---
<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

# M365 Copilot Platform Options

Read this reference for an `m365-copilot` proposal's resource preflight, or when the resolved root's `team.md` `Packs:` line includes `m365-copilot`. A proposal permits explanation, not skill selection or installation. Removing the pack stops squad selection and workload guidance. It does not uninstall or hide a host-installed skill.

Host visibility is not selection. A declined resource stays unavailable to the squad even if the host exposes it. The preview jobs below also require explicit preview approval; accepting the pack alone is not that approval.

## Paths

| Request | Agent | Skill |
|---|---|---|
| .NET Agents SDK production readiness | `Squad M365 Agent Architect` | `agents-sdk-to-prod` |
| Agents SDK Teams app manifest creation or audit | `Squad M365 Agent Architect` | `teams-app-manifest` |
| M365 Copilot evaluation suite schema `1.2.0` authoring or local `.evals/` analysis (preview) | `Squad M365 Agent Architect` | `m365-agent-evaluator` |
| Agents SDK OpenTelemetry (.NET, TypeScript/JS, or Python) | `Squad M365 Agent Integrator` | `agents-sdk-dotnet-otel`, `agents-sdk-typescript-otel`, `agents-sdk-python-otel` |
| Agents SDK provisioning plan | `Squad M365 Agent Integrator` | `agents-sdk-provision` |
| Copilot Chat MCP widget server, React/Fluent UI widget, and `mcpPlugin.json` authoring (preview) | `Squad M365 Agent Integrator` | `ui-widget-developer` |
| Declarative agent, TypeSpec, API plugin, general agent manifest, Agents Toolkit, or broader M365 architecture | `Declarative Agents Architect` | community Alternate; not these official skills |
| Microsoft Graph, Graph SDK, Graph permission scope, MCP-backed Copilot agent, or broader MCP-backed M365 integration | `MCP M365 Agent Expert` | community Alternate; not these official skills |

Primary is the fallback when no Selection Cue matches. A matching broad cue selects the named Alternate. If that Alternate is absent or not dispatchable, escalate with its registry install command. Do not substitute the local Primary.

## Installation and readiness

Use the shared **Pack Resource Preflight** in `profiles-and-packs.md` at Init, pack addition, and a missing-resource escalation. `Registered Pack Skills` maps all fourteen M365 skills to their exact opt-in entries: six core official `microsoft/Agents` skills, six community supplements, and two preview `microsoft/work-iq` skills. The two community agents remain separate, optional Alternate installs, not new Primaries.

1. Explain the missing resources in plain language. Offer the six core official Agents SDK skills, optional community supplements, the two separately approved preview skills, a selected subset, or continuing without them. Preview is not the default; a generic install-all answer without preview disclosure is not preview approval. Say which requested job each choice enables.
2. Before preview approval, disclose the preview posture and excluded execution steps for both `microsoft/work-iq` skills:
   * `m365-agent-evaluator` targets the public-preview `@microsoft/m365-copilot-eval` CLI. Its local schema `1.2.0` dataset authoring and `.evals/` result analysis need no tenant, whereas running the CLI needs Node.js 24.12+, separate human EULA acceptance (`accept-eula`), WorkIQ Client App admin consent, a deployed M365 Copilot agent, and an Azure OpenAI judge. Squad authors and analyzes local files only and never runs that CLI or accepts an EULA.
   * `ui-widget-developer` comes from `microsoft/work-iq`'s Agents Toolkit plugin and includes upstream instructions to install `modelcontextprotocol/ext-apps`, install packages automatically, spawn detached `devtunnel` and server OS processes, call MCP Inspector over a tunnel, run `atk provision`, and hand off to `declarative-agent-developer`/`wiqd` or `setup-sso-ui-widget`. Squad follows its local file-authoring guidance only and never runs those background, install, tunnel, or provisioning steps.
   * Both preview entries install as self-contained pinned skill directories with no hooks or MCP servers, avoiding the whole plugin's `wiqd`-dependent stub and live Entra/ATK setup scripts.
3. After the user's resource choices, run `Install-SquadPackResources.ps1` with `-Pack m365-copilot`, the approved `-Resource` names, a new receipt path, and `-Confirmed`. The helper installs payloads, not prerequisites, CLIs, extensions, or EULA acceptances. Preserve native confirmation prompts; a failed or cancelled command remains missing.
4. Require a `PASS` receipt, then stop for a host reload. `PLANNED` is not installation, and an on-disk skill is not yet host-visible. After reload, rerun preflight with the actual native host inventory and record every listed skill as `available` or explicitly `declined`. Pass the preview approval's decision reference or current explicit request with its dispatch; an `available` flag alone is not preview permission. Declining preview skills does not prevent applying the pack or using the other approved resources.
5. Check the packaged support files below before claiming the requested job is ready. Report installed payloads, host visibility, missing support/prerequisites, and tenant readiness separately. Resume a failed setup at the failed step, without inventing availability or overwriting existing files.

The shared installer runs the exact pinned APM entries without an M365-specific installer. APM takes **skill directories**, not `SKILL.md` file paths. Give the user the published [English setup guide](https://peter-n91.github.io/hve-squad/usage.html#m365-copilot-setup) or [French setup guide](https://peter-n91.github.io/hve-squad/fr/usage.html#m365-copilot-setup) for detailed commands and troubleshooting; the consumer repository need not contain this project's documentation.

### Packaged support files and optional reference snapshot

Each pinned M365 directory install carries its own `references/`, `assets/`, and `examples/` inside `.agents/skills/<skill>/` (and `apm_modules/`) with no parent-plugin `${PLUGIN_ROOT}` dependency, hooks, or MCP configuration. Verify the required files below under the installed skill root before use; if they are missing, stop and give the setup remedy instead of generating from memory.

| Skills | Verified source | Required packaged support files |
|---|---|---|
| `agents-sdk-to-prod` | `microsoft/Agents@a5caf57ff062369c410aa5542039b50ce1a9c7e8` | `references/readiness-matrix.md` under `.agents/skills/agents-sdk-to-prod/`; optional offline `samples/dotnet/production-reference/` snapshot |
| `teams-app-manifest` | same pin | `assets/base-manifest.template.json`, `assets/manifest-evidence.template.md`, `references/capability-sources.md`, and `references/schema-validation.md` |
| `agents-sdk-dotnet-otel`, `agents-sdk-typescript-otel`, `agents-sdk-python-otel` | same pin | `references/sdk-signals.md` (and `assets/start-aspire-dashboard.ps1` as read-only reference; do not execute from the charter) |
| `agents-sdk-provision` | same pin | `assets/ProvisionABS.bicep`, `assets/Create_SSO_AppRegistration.bicep`, `assets/Create_SSO_PreAuthorize.bicep`, and `references/oauth-setup.md` |
| `m365-agent-evaluator` (preview) | `microsoft/work-iq@72c889460aa7ac6d7ed3bb02179332abafc963d4` | `references/prompts-schema.json`, `references/output-schema.json`, `references/eval-templates.md`, and `references/guardrails.md` |
| `ui-widget-developer` (preview) | same pin | `references/copilot-widget-protocol.md`, `references/mcp-server-pattern.md`, `references/widget-patterns.md`, and `references/plugin-schema.md` |
| `msgraph-sdk` | `github/awesome-copilot@9db369d00f121542e1c99fd9b6cd6f707bade765` | `references/dotnet.md`, `references/typescript.md`, and `references/python.md` |

When offline access to `microsoft/Agents`'s `samples/dotnet/production-reference/` is needed for `agents-sdk-to-prod`, ask before fetching a read-only source snapshot into `apm_modules/.squad-pack-support/agents-a5caf57` with repository-local `core.longpaths=true`. Verify its detached `HEAD` matches `a5caf57ff062369c410aa5542039b50ce1a9c7e8` and do not register that checkout as a plugin or working project. An installed skill or snapshot at a different ref requires re-verification before use.

### Preview selection and exclusions

`m365-agent-evaluator` authors schema `1.2.0` evaluation suites (`evals/evals.json` with a root `items` array and public case-sensitive evaluators) and analyzes existing local `.evals/` outputs to recommend targeted instruction or capability changes. Do not execute `npx -y --package @microsoft/m365-copilot-eval@latest runevals`, run `accept-eula`, uninstall global packages, or call a live tenant or Azure OpenAI judge from the charter.

`ui-widget-developer` authors MCP server source, React + Fluent UI widget components (`text/html+skybridge`, `structuredContent`, `openai/outputTemplate`), and local `mcpPlugin.json` configuration (`RemoteMCPServer`, schema `v2.4`). Keep its OpenAI Apps versus MCP Apps choice explicit through the coordinator rather than running `/plugin marketplace add modelcontextprotocol/ext-apps` automatically. Do not install packages or plugins, spawn detached OS servers or `devtunnel` processes, run MCP Inspector against a tunnel, run `atk provision`, or chain into `declarative-agent-developer`, `wiqd`, or `setup-sso-ui-widget`.

Other upstream M365 candidates were gated and remain **not registered squad capabilities**:

* `declarative-agent-developer` in `microsoft/work-iq@72c889460aa7ac6d7ed3bb02179332abafc963d4` contains no standalone manifest or TypeSpec guidance; it forbids inspecting files and delegates unconditionally to `wiqd` (`microsoft/wiqd@47f230e3943f8948d78d8b17817c8f41f0783627`), a pre-release preview backed by a closed-source CLI with mandatory runtime EULA gates. Neither supersedes `declarative-agents`, `typespec-create-agent`, `typespec-create-api-plugin`, or `Declarative Agents Architect`.
* `install-atk`, `setup-sso-ui-widget`, and `teams-app-developer` in `microsoft/work-iq` install workstation tooling, register live Entra apps/tunnels, or run `atk` provisioning and sideloading while redirecting declarative agents to `wiqd`. `workiq` and `workiq-productivity` query live tenant mail, calendar, Teams, and SharePoint data via WorkIQ MCP rather than authoring Copilot agents.
* `teams-dev` in `microsoft/teams-sdk@64aebb60e8e17c9087f86c16e2cc3672ee302450` targets preview `@microsoft/teams.cli` (`3.*`) with `teams self-update`, live bot/Entra/OAuth mutations, and an ambient trigger claiming every mention of `"Teams"` while forbidding external search. `microsoftgraph/dev-skills@175381470b0d7e09da89be0608017d208e79933a` generates custom Kiota/AI clients via global `.NET` tools rather than `Microsoft.Graph` SDK integration, so `msgraph-sdk` and `MCP M365 Agent Expert` remain unchanged.
* `microsoft/Agents` duplicates the `agents-sdk-to-prod` skill name across `agents-for-net`, `agents-for-js`, and `agents-for-python`, so only the `.NET` entry can occupy `.agents/skills/agents-sdk-to-prod/`; general SDK coding/debugging and Bot Framework or Teams SDK migrations remain with `developer` and `modernizer`.

## Boundaries

* Official rows are opt-in skills. Install nothing automatically.
* Whole-plugin install forms (`microsoft-365-agents-toolkit@work-iq`, `workiq@work-iq`, `wiqd`, `agents-for-dotnet`, `agents-sdk-common`, `teams-sdk@teams-skills`) remain unregistered so unapproved hooks, MCP servers, `wiqd` stubs, duplicate skill names, and live CLI workflows are never pulled in silently.
* `agents-sdk-provision` is a plan here. Do not create Azure Bot, Entra, or Bicep resources, and do not consent to a tenant.
* File-authoring authority does not include an upstream skill's CLI execution, package or plugin installation, EULA acceptance, detached background processes, `devtunnel` hosting, `atk` provisioning, sideloading, or tenant operations. Return interactive or live execution steps to the user as an explicit handoff.
* Community agents and skills remain registered and are not blocklisted.
