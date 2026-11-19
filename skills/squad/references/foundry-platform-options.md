---
name: squad-foundry-platform-options
description: "Foundry platform decision questions, official skill ownership, installation readiness, packaged support files, and non-admitted candidates."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-11-15"
---
<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

# Foundry Platform Options

Read this reference for a `foundry` proposal's resource preflight, or when the resolved root's `team.md` `Packs:` line includes `foundry`. A proposal permits explanation, not skill selection or installation. Removing the pack stops squad selection and workload guidance. It does not uninstall or hide a host-installed skill.

Host visibility is not selection. A declined resource stays unavailable to the squad even if the host exposes it. Preview-gated resources (`foundry-iq` and `agentops-governance`, plus preview cloud/`azd` evaluation modes inside `agentops-eval`) also require explicit preview approval; accepting the pack alone is not that approval.

Use this reference to frame decisions, not to answer volatile product questions from memory. Resolve current capabilities, preview or GA status, supported regions, API versions, and SDK versions through the registered upstream resources in [roster-catalog.md](roster-catalog.md) and the project's actual manifests and lockfiles.

## Paths

| Request | Agent | Skill |
|---|---|---|
| Approved Foundry agent, model, evaluation, troubleshooting, and hosted-agent implementation or gated deployment workflows | `Squad Implementor`, `Squad Deployer` | `microsoft-foundry` |
| Consuming an existing, selected Azure AI Gateway model or MCP endpoint in application code | `Squad Implementor` | `use-ai-gateway` |
| Designing or configuring a selected Azure API Management AI gateway option in HLD/LLD | `Squad Azure Architect` | `azure-aigateway` |
| Inspecting and adapting reference architecture components for an already selected stack | `Squad Implementor` | `caira` |
| Foundry IQ knowledge-base grounding, source readiness, and retrieval design (preview) | `Squad Data Scientist` | `foundry-iq` |
| Application Insights web and agent telemetry instrumentation patterns | `Squad Observability Planner` | `appinsights-instrumentation` |
| AgentOps Doctor `.agentops/agent.yaml` readiness configuration, App Insights / OpenTelemetry span correlation, and supplied `.agentops/agent/report.md` triage | `Squad Observability Planner` | `agentops-agent` |
| Microsoft 10-step agent evaluation methodology, 5-factor risk-tier gate calibration, `pass@k`/`pass^k` sizing, and LLM-as-judge bias checks | `Squad Prompt Engineer` | `eval-faq` |
| Authoring or updating `agentops.yaml` (flat 1.0 schema) for Foundry AgentOps release-readiness gates | `Squad Prompt Engineer` | `agentops-config` |
| Planning Foundry AgentOps release-readiness evaluation execution (`local`, Classic Foundry, or approved preview `cloud` / `azd`) and Rubric threshold alignment | `Squad Prompt Engineer` | `agentops-eval` |
| Reading and explaining supplied AgentOps `results.json`, `report.md`, `cloud_evaluation.json`, and release `evidence.md` artifacts | `Squad Prompt Engineer` | `agentops-report` |
| Drafting reviewable ASSERT `./assert/eval_config.yaml`, Agent Control Specification `acs.yaml` checkpoint contracts, Guided Guardrail readiness notes, and payload-free Red-Team readiness plans (preview) | `RAI Planner` / `RAI Skill Assessor` (ambient reach) | `agentops-governance` |
| Authoring a repository-local fail-closed Agent Governance Toolkit policy `.agt/policy.json` (`strict` baseline, rationale, allow/review/deny matrix) | `Security Planner` (ambient reach) | `agt-policy-authoring` |

`Security Planner` (`security`) and `RAI Planner` / `RAI Skill Assessor` (`rai`) are deployed HVE Core agents and reach `agt-policy-authoring` and `agentops-governance` ambiently when `foundry` is active and the skill is host-visible and not `declined`. Writing and executing test suites stays with opt-in `qa-engineer`; CI/CD workflow authoring stays with opt-in `release-engineer`.

## Installation and readiness

Use the shared **Pack Resource Preflight** in `profiles-and-packs.md` at Init, pack addition, and a missing-resource escalation. `Registered Pack Skills` maps all thirteen `foundry` skills to verified pinned directory entries across `microsoft/azure-skills@968f7bfaa01672e782dae2c6bab4fb9505ae047a`, `Azure/aigateway@8cba384de61ab9d438450a79f44fba0528c56d0a`, `microsoft/CAIRA@a36d043784b0ac899764212178df6d0f9e9b85d9`, `microsoft/skills@f03ec5392f7a0f3aca12af47477e92f1edf7b44c`, `Azure/agentops@0f2173d03a63c73b9cf4a4d9978136cc5dec2909`, `microsoft/eval-guide@7a22a8957ced79a35fd7b4634fd5b5eac56c308e`, and `microsoft/agent-governance-toolkit@678070abf15417acdb4a5dd826667a5d83f54d67`.

1. Explain the missing resources in plain language. Offer the eleven core `foundry` skills (`microsoft-foundry`, `use-ai-gateway`, `azure-aigateway`, `caira`, `appinsights-instrumentation`, `agentops-agent`, `eval-faq`, `agentops-config`, `agentops-eval`, `agentops-report`, `agt-policy-authoring`), the two separately approved preview skills (`foundry-iq` and `agentops-governance`), a selected subset, or continuing without them. Preview is not the default. Say which requested job each choice enables.
2. Before preview approval, disclose that `foundry-iq` ships from plugin `0.2.8` preview (`0.2.3` skill), `agentops-governance` targets pre-1.0 `agentops-accelerator` (`0.16.2`), `assert-ai 0.1.0`, and public-preview Foundry Guided Guardrail Setup, and `agentops-eval`'s New Foundry `execution: cloud` OpenAI Evals and `azd ai agent eval` paths are preview. All thirteen entries install as self-contained pinned skill directories under `.agents/skills/<skill>/` with no `copilot-hooks.json` (`ghcfa-telem`), no Claude update-check `preamble:`, and no `.mcp.json` or `.github/mcp.json` entries.
3. After the user's resource choices, run `Install-SquadPackResources.ps1` with `-Pack foundry`, the approved `-Resource` names, a new receipt path, and `-Confirmed`. The helper installs skill payloads only — never `az`, `azd`, `agentops-accelerator`, `assert-ai`, `azure-ai-evaluation[redteam]`, `@microsoft/agent-governance-copilot-cli`, `@azure/mcp`, RBAC role assignments, or Foundry resources. Preserve native confirmation prompts; a failed or cancelled command remains missing.
4. Require a `PASS` receipt, then stop for a host reload. `PLANNED` is not installation, and an on-disk skill is not yet host-visible. After reload, rerun preflight with the actual native host inventory and record every listed skill as `available` or explicitly `declined`. Pass preview approval provenance with any `foundry-iq`, `agentops-governance`, or preview `agentops-eval` dispatch; an `available` flag alone is not preview permission. Declining preview skills does not block `foundry` activation.
5. Check the packaged support files below before claiming the requested job is ready. Report installed payloads, host visibility, missing packaged support files, and Azure / CLI prerequisites separately. Resume a failed setup at the failed step, without inventing availability or overwriting existing files.

The shared installer runs the exact pinned APM entries without a Foundry-specific installer. APM takes **skill directories**, not `SKILL.md` file paths. Give the user the published [English setup guide](https://peter-n91.github.io/hve-squad/usage.html#foundry-setup) or [French setup guide](https://peter-n91.github.io/hve-squad/fr/usage.html#foundry-setup) for detailed commands and troubleshooting; the consumer repository need not contain this project's documentation.

### Packaged support files and optional reference snapshots

Each pinned `foundry` directory install carries its own support files inside `.agents/skills/<skill>/` with no parent-plugin hook or MCP configuration. Verify the required files below under `.agents/skills/<skill>/` before use; if they are missing, stop and give the setup remedy instead of answering from memory.

| Skills | Verified source | Required packaged support files |
|---|---|---|
| `microsoft-foundry` | `microsoft/azure-skills@968f7bfaa01672e782dae2c6bab4fb9505ae047a` | `references/auth-best-practices.md`, `references/agent-metadata-contract.md`, `foundry-agent/create/create-hosted.md`, `foundry-agent/deploy/deploy.md`, `foundry-agent/validate/validate.md`, `models/deploy-model/SKILL.md`, and `scripts/check-and-setup-dependencies.ps1` |
| `azure-aigateway` | same pin | `references/auth-best-practices.md`, `references/patterns.md`, `references/policies.md`, and `references/troubleshooting.md` |
| `appinsights-instrumentation` | same pin | `LICENSE.txt`, `examples/appinsights.bicep`, `references/aspnetcore.md`, `references/nodejs.md`, `references/python.md`, and `scripts/appinsights.ps1` |
| `use-ai-gateway` | `Azure/aigateway@8cba384de61ab9d438450a79f44fba0528c56d0a` | `references/authentication.md`, `references/connection.md`, `references/diagnostics.md`, `references/mcp.md`, and `references/models.md` |
| `caira` | `microsoft/CAIRA@a36d043784b0ac899764212178df6d0f9e9b85d9` | `SKILL.md` (self-contained skill root; inspects `reference-architectures/` via GitHub or an optional approved snapshot at `apm_modules/.squad-pack-support/caira-a36d043`) |
| `foundry-iq` (preview) | `microsoft/skills@f03ec5392f7a0f3aca12af47477e92f1edf7b44c` | `references/intent-routing.md`, `references/platform-contracts.md`, `references/resource-intake.md`, `knowledge-bases/create.md`, `knowledge-bases/retrieve.md`, and `helpers/retrieval_verify.py` |
| `agentops-agent`, `agentops-config`, `agentops-eval`, `agentops-report`, `agentops-governance` (preview) | `Azure/agentops@0f2173d03a63c73b9cf4a4d9978136cc5dec2909` | Self-contained `SKILL.md` under `.agents/skills/<skill>/` |
| `eval-faq` | `microsoft/eval-guide@7a22a8957ced79a35fd7b4634fd5b5eac56c308e` | Self-contained `SKILL.md` under `.agents/skills/eval-faq/` (inline 10-step playbook knowledge base; optional approved snapshot at `apm_modules/.squad-pack-support/eval-guide-7a22a89` for `skills/eval-guide/playbook.md`) |
| `agt-policy-authoring` | `microsoft/agent-governance-toolkit@678070abf15417acdb4a5dd826667a5d83f54d67` | Self-contained `SKILL.md` under `.agents/skills/agt-policy-authoring/` (optional approved snapshot at `apm_modules/.squad-pack-support/agent-governance-toolkit-678070a` for `docs/packages/copilot-cli-governance.md`) |

When offline reference snapshots are wanted (for example `microsoft/CAIRA`'s `reference-architectures/` or `microsoft/agent-governance-toolkit`'s package schema docs), ask before fetching a read-only detached checkout under `apm_modules/.squad-pack-support/` with repository-local `core.longpaths=true`. Verify `rev-parse HEAD` matches the pinned SHA and do not register that checkout as a plugin or working project.

### Preview selection and exclusions

* `foundry-iq` (`0.2.8` preview) grounds knowledge bases only when explicitly approved as preview; do not create Azure AI Search services, Blob containers, or knowledge bases without human approval.
* `agentops-governance` drafts reviewable `./assert/eval_config.yaml`, `acs.yaml`, Guided Guardrail review checklists, and safe `.agentops/governance/redteam-plan.md` indexes only when explicitly approved as preview. Never generate attack payloads or jailbreak strings, and never run `pip install assert-ai`, `pip install "azure-ai-evaluation[redteam]"`, `agentops assert run`, or `agentops redteam run` from a squad turn.
* Other candidates were gated and are **not registered squad capabilities**:
  * `agentops-dataset` (`Azure/agentops`) duplicates HVE Core's `evaluation-design` skill and `microsoft-foundry`'s `eval-datasets`; `agentops-workflow` (`Azure/agentops`) authors GitHub Actions and Azure DevOps pipelines owned by `release-engineer`. Both are recorded in *External Cast Blocklist*.
  * `eval-guide` (Claude plugin `preamble:` auto-upgrader, blocking `localhost:3118` `serve.py`, OS browser launch, and Copilot Studio `/clone-agent`), `eval-suite-planner` (unpackaged external `.xlsx` dependency and `evaluation-design` overlap), and `eval-generator`, `eval-result-interpreter`, and `eval-triage-and-improvement` (Copilot Studio CSV/Evaluate-tab workflows overlapping `evaluation-design` and `agentops-report`) from `microsoft/eval-guide` are recorded in *External Cast Blocklist*.
  * Community `agent-governance`, `agent-owasp-compliance`, `agent-governance-reviewer`, `agentic-eval`, and `eval-driven-dev` remain blocklisted. Whole-plugin forms (`azure@azure-skills`, `foundry-iq-skills`, `aigateway@azure`, `agentops-accelerator`, `eval-guide`, and Claude/Codex/Antigravity `agt-governance` hook plugins), `Azure/aigateway`'s `manage-ai-gateway`, `migrate-apim`, `feedback-ai-gateway`, and `azure-ai-gateway-labs`, and `Azure/agentops`'s maintainer `.github/skills/speckit-*` remain unregistered. Identity architecture (`identity` role / `entra-agent-user`) remains a documented cast gap.

## Gateway Questions

Ask:

* Do multiple applications or teams need one governed entry point for models, agents, or tools?
* Which authentication, authorization, quota, routing, observability, and policy requirements belong at a shared gateway?
* Which application controls remain local, including business authorization, approval state, document permissions, and reversible tool execution?
* Does the selected API Management tier support every required capability, or is a direct service path smaller and sufficient?
* Who owns gateway capacity, policy lifecycle, networking, incident response, and cost?

Use the registered `azure-aigateway` and `use-ai-gateway` skills for current product guidance. A gateway remains optional and is never activated or provisioned by applying this pack.

## Cloud and Azure Local Questions

Ask:

* Does the workload require cloud-hosted agent capabilities, local inference, local retrieval, disconnected operation, or a combination?
* Which exact workload and feature are being compared? Do not infer parity between Foundry Agent Service, Foundry Local on Azure Local, and Agentic Retrieval in Foundry Local.
* What do the current official sources say about service status, feature status, supported regions, models, engines, and capacity?
* What Azure Local, Arc-enabled Kubernetes, identity, network, hardware, and connectivity prerequisites apply to the selected version?
* Which control-plane, model-download, update, management, and telemetry paths require connectivity?
* Has the customer accepted every preview dependency and named a supported fallback?

Use the registered `microsoft-foundry` skill for current product guidance, and verify Foundry Local on Azure Local against current Microsoft Learn documentation. The pinned Azure plugin `mcp.json` declares only `mcpServers.azure`. It does not install a separate Foundry MCP server. Foundry operations use that Azure MCP server's `foundry` tool. Record unknown or conflicting claims as unverified with the smallest next check.

Frame Azure Local as a distinct deployment option, not a cloud-equivalent checkbox:

* **Applicable scenarios:** on-premises or edge workloads with a documented need for local inference or retrieval, constrained connectivity, data-locality requirements, or a supported disconnected operating model.
* **Prerequisites:** a supported Azure Local and Arc-enabled Kubernetes baseline, compatible hardware and capacity, identity and network design, and the control-plane, model-download, update, management, and telemetry connectivity required by the selected version.
* **Limitations:** never assume parity with Foundry Agent Service, cloud model availability, managed tools, regions, engines, scaling, or operations. Name the missing capability and fallback for the selected workload.
* **Preview status:** verify the service and each selected feature separately. A preview dependency requires the customer's explicit acceptance, owner, limitations, and supported fallback before production planning continues.

## SDK and API Questions

Ask:

* Which language, package, resolved SDK version, API version, and agent type does the implementation actually use?
* Does the current official quickstart or migration guidance apply to that exact service and agent type?
* Is the selected SDK surface stable or preview, and does the target region support every required feature?
* What build, smoke, integration, and evaluation evidence proves compatibility for the resolved dependency set?
* What changes between planning, implementation, deployment, and acceptance checkpoints?

Do not copy a latest-version number into this reference. Read the manifest and lockfile, then verify that baseline against official release and migration guidance at the checkpoint. A newer version is evidence to assess, not permission to upgrade.

Use `microsoft-foundry` for current Foundry service and SDK workflows, `azure-aigateway` for a selected APIM configuration, `use-ai-gateway` to consume an existing gateway, and `caira` only to inspect reference components for an already selected stack.

## Grounding, evaluation, observability, and governance

Select `foundry-iq` through `data-scientist`, `appinsights-instrumentation` and `agentops-agent` through `observability`, `eval-faq`, `agentops-config`, `agentops-eval`, and `agentops-report` through `prompt-engineer`, `agentops-governance` through `rai`, and `agt-policy-authoring` through `security` only when the resolved root's `Packs:` line includes `foundry` and the resource decision is not `declined`. Pack removal stops that squad selection and this guidance. It does not uninstall or hide a host-installed skill.

## Boundaries

* Azure accounts, `az`, `azd`, `agentops-accelerator`, `assert-ai`, `azure-ai-evaluation[redteam]`, `@microsoft/agent-governance-copilot-cli`, and existing AI Gateways count as runtime CLI/service prerequisites under *Tier Qualification* test 3, and Microsoft Foundry is an optional cloud AI vertical under test 4, so every row is `opt-in` and none is `bundled` in `apm.yml`.
* `Squad Azure Architect` (`azure-architect`), `Squad Observability Planner` (`observability`), `Squad Prompt Engineer` (`prompt-engineer`), `Security Planner` (`security`), and `RAI Planner` (`rai`) stay local/read-only over cloud infrastructure: they author designs, instrumentation plans, `agentops.yaml` configs, score explanations, `.agt/policy.json` policies, and reviewable governance artifacts without running `pip install`, `npm install`, `az role assignment create`, `agentops eval run`, `agentops assert run`, `agentops redteam run`, `agentops cockpit`, or `AGT_COPILOT_POLICY_PATH` activation.
* `Squad Implementor` (`developer`) authors application and agent changes under `.copilot-tracking/changes/` from an approved plan without deploying or running interactive dependency installers; live Azure and Foundry deployments stay with `Squad Deployer` (`deployer`) behind its OIDC dry-run and Impactful-Action Gate.
* Identity architecture (`identity`) remains unselectable and is escalated rather than improvised.