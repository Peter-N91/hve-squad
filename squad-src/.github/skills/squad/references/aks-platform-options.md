---
name: squad-aks-platform-options
description: "Opt-in Azure Kubernetes Service (AKS) official skill ownership, prerequisites, packaged support files, and non-admitted candidates."
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

# AKS Platform Options

Read this reference for an `aks` proposal's resource preflight, or when the resolved root's `team.md` `Packs:` line includes `aks`. A proposal permits explanation, not skill selection or installation. Removing the pack stops squad selection and workload guidance. It does not uninstall or hide a host-installed skill.

Host visibility is not selection. A declined resource stays unavailable to the squad even if the host exposes it.

The pack adds no new catalog role and no external agent Primary or Alternate. It reuses `azure-architect`, `developer`, `modernizer`, `azure-diagnose`, and `cost-manager` through their existing local charters. `full +aks` and `azure +aks` add no roles; `default +aks` adds `azure-architect`, `modernizer`, `azure-diagnose`, and `cost-manager`; `operations +aks` adds `azure-architect`, `modernizer`, and `cost-manager`; `architecture +aks` adds `modernizer` and `azure-diagnose`; `modernization +aks` adds `azure-diagnose`.

## Paths

| Request | Agent | Skill |
|---|---|---|
| Day-0 AKS cluster architecture, Automatic vs Standard SKU, Azure CNI Overlay / Cilium networking, Workload Identity, observability, and autoscaling design | `Squad Azure Architect` | `azure-kubernetes` |
| Containerizing an existing application for AKS (`Dockerfile`, Kubernetes workload manifests, Workload Identity wiring, and DS001–DS013 Deployment Safeguards) | `Squad Implementor` | `azure-kubernetes-app-deploy` |
| AKS Standard or local Kubernetes manifest, Helm, and Kustomize compatibility assessment and migration plan for AKS Automatic | `Squad Modernization Planner` | `azure-kubernetes-automatic-readiness` |
| Live AKS Day-2 incident triage across pod crashes, node `NotReady`/pressure/quota, CNI/DNS/ingress/SNAT, API-server/webhooks, stuck upgrades, and spot/zone disruptions | `Squad Azure Diagnose` | `aks-troubleshooting` |
| Exact AKS error-signature lookup (`VMCannotFitEphemeralOSDisk`, `NodePoolMcVersionIncompatible`, qualified `SkuNotAvailable`, `ZonalAllocationFailed`, `OverconstrainedAllocationRequest`, nested `VMExtensionError_*`, cataloged `AllocationFailed`) | `Squad Azure Diagnose` | `aks-known-issues` |
| Day-2 AKS GPU and KAITO inference incident diagnosis (`Insufficient nvidia.com/gpu`, GPU pod `Pending`, VRAM/container `OOMKilled`, DCGM, KAITO Workspace readiness) | `Squad Azure Diagnose` | `aks-gpu-inference` |
| Advanced AKS cost-efficiency analysis (Node Auto-Provisioning readiness, node-pool bin-packing, blocked scale-down bottlenecks, Kubernetes storage optimization, and commitment-demand evidence) | `Squad Cost Manager` | `aks-cost-optimization` |
| Converting an AKS LLD into Bicep or Terraform under `infra/{track}/{project}` | `Squad IaC Author` | existing `iac-author` charter; `azure-architect` designs and never writes IaC |
| Gated Azure cluster or infrastructure deployment (`what-if` / `plan`, then approved `create` / `apply`) | `Squad Deployer` | existing `deployer` charter behind the Impactful-Action Gate |

When `Squad Implementor` executes an approved AKS Automatic migration plan phase, it may also read non-declined `azure-kubernetes-automatic-readiness` (`references/common-fixes.md` and `references/constraint-spec-v1.yaml`) while preserving its `.copilot-tracking/changes/` deliverable contract and never running `kubectl apply`, `az aks update`, or `git commit`.

## Installation and readiness

Use the shared **Pack Resource Preflight** in `profiles-and-packs.md` at Init, pack addition, and a missing-resource escalation. `Registered Pack Skills` maps all seven `aks` skills to their exact opt-in directory entries in `microsoft/azure-skills@968f7bfaa01672e782dae2c6bab4fb9505ae047a`.

1. Explain the missing resources in plain language. Offer all seven core official `aks` skills (Day-0 cluster design, app containerization/manifests, AKS Automatic readiness, live AKS troubleshooting, known-issue lookup, GPU/KAITO incident diagnosis, and AKS cost optimization), a selected subset, or continuing without them. Say which requested job each choice enables.
2. Disclose that all seven entries install as self-contained pinned skill directories under `.agents/skills/<skill>/` with no hooks (`copilot-hooks.json` / `ghcfa-telem`) and no `.mcp.json` or `mcpServers` entries. Note that `Registered Pack Skills` lists `azure-kubernetes-app-deploy` and `azure-kubernetes-automatic-readiness` ahead of `azure-kubernetes` because upstream nests those two directories beneath `skills/azure-kubernetes/`; if a consumer previously installed `azure-kubernetes` alone, run the explicit `apm install` command for `azure-kubernetes-app-deploy` or `azure-kubernetes-automatic-readiness` so its top-level `.agents/skills/<skill>/SKILL.md` directory exists before host reload.
3. After the user's resource choices, run `Install-SquadPackResources.ps1` with `-Pack aks`, the approved `-Resource` names, a new receipt path, and `-Confirmed`. The helper installs skill payloads only — never `az`, `kubectl`, `helm`, `jq`, `@azure/mcp`, kubeconfig credentials, or cluster add-ons. Preserve native confirmation prompts; a failed or cancelled command remains missing.
4. Require a `PASS` receipt, then stop for a host reload. `PLANNED` is not installation, and an on-disk skill is not yet host-visible. After reload, rerun preflight with the actual native host inventory and record every listed skill as `available` or explicitly `declined`.
5. Check the packaged support files below before claiming the requested job is ready. Report installed payloads, host visibility, missing packaged support files, and `az` / `kubectl` / cluster-context prerequisites separately. Resume a failed setup at the failed step, without inventing availability or overwriting existing files.

The shared installer runs the exact pinned APM entries without an AKS-specific installer. APM takes **skill directories**, not `SKILL.md` file paths. Give the user the published [English setup guide](https://peter-n91.github.io/hve-squad/usage.html#aks-setup) or [French setup guide](https://peter-n91.github.io/hve-squad/fr/usage.html#aks-setup) for detailed commands and troubleshooting; the consumer repository need not contain this project's documentation.

### Packaged support files and optional reference snapshot

Each pinned `aks` directory install carries its own `references/`, `scripts/`, `templates/`, `knowledge-packs/`, and `phases/` inside `.agents/skills/<skill>/` (and `apm_modules/`) with no parent-plugin hook or MCP configuration. Verify the required files below under the top-level `.agents/skills/<skill>/` root before use; if they are missing, stop and give the setup remedy instead of answering from memory.

| Skills | Verified source | Required packaged support files |
|---|---|---|
| `azure-kubernetes-app-deploy` | `microsoft/azure-skills@968f7bfaa01672e782dae2c6bab4fb9505ae047a` | `phases/quick-deploy.md`, `references/detection.md`, `references/safeguards.md`, `references/workload-identity.md`, `references/rollback.md`, `references/base-images.md`, `knowledge-packs/frameworks/aspnet-core.md`, `templates/dockerfiles/dotnet.Dockerfile`, and `templates/k8s/deployment.yaml` |
| `azure-kubernetes-automatic-readiness` | same pin | `references/constraint-spec-v1.yaml`, `references/common-fixes.md`, `references/migration-guide-summary.md`, `references/mcp-integration.md`, and `scripts/sanitize-readiness-input.jq` |
| `azure-kubernetes` | same pin | `references/cli-reference.md`, `references/azure-aks-autoscaler.md`, `references/azure-aks-nap-readiness.md`, `references/azure-aks-rightsizing.md`, `references/azure-aks-spot.md`, `references/azure-aks-vpa.md`, and `references/optional-aks-operations.md` |
| `aks-troubleshooting` | same pin | `general-diagnostics.md`, `pod-failures.md`, `node-issues.md`, `networking.md`, `load-balancer-and-ingress.md`, `network-policy.md`, `upgrade-operations.md`, `spot-and-zone-issues.md`, `references/symptom-map.md`, `references/api-server-webhooks-tunnel.md`, `references/auto-upgrade-evidence.md`, `references/azure-mcp.md`, `references/report-template.md`, `scripts/cluster-snapshot.sh`, and `scripts/pod-deep-dive.sh` |
| `aks-known-issues` | same pin | `references/error-code-map.md` |
| `aks-gpu-inference` | same pin | `references/gpu-scheduling.md`, `references/gpu-observability.md`, `references/kaito-workspaces.md`, and `references/gpu-cost-and-scaling.md` |
| `aks-cost-optimization` | same pin | `references/aks-nap.md`, `references/aks-bin-packing.md`, `references/node-scaling-bottlenecks.md`, `references/aks-storage-optimization.md`, and `references/aks-savings-plans-reservations.md` |

When offline access to additional `microsoft/azure-skills` AKS documentation is wanted, ask before fetching a read-only source snapshot into `apm_modules/.squad-pack-support/azure-skills-968f7bf` with repository-local `core.longpaths=true`. Verify its detached `HEAD` matches `968f7bfaa01672e782dae2c6bab4fb9505ae047a` and do not register that checkout as a plugin or working project. An installed skill or snapshot at a different ref requires re-verification before use.

### Exclusions and blocklisted candidates

Other AKS and Kubernetes candidates were gated and remain **not registered squad capabilities**:

* `Azure/AKS-Skills@7fac4bc786f0bca2a353a92e100f72a132111ef6` (`aks` plugin) is archived upstream and superseded by `microsoft/azure-skills`, and `platform-sre-kubernetes` (`github/awesome-copilot@9db369d00f121542e1c99fd9b6cd6f707bade765`) claims planning, manifest edits, `kubectl apply`/rollback, and monitoring across five existing roles; both are recorded in *External Cast Blocklist*. `microsoft/GitHub-Copilot-for-Azure` carries GitHub Copilot Product Specific Terms (`NOASSERTION`) at its repository root, so skills are sourced strictly from the MIT-licensed `microsoft/azure-skills` distribution repository.
* Whole-plugin install forms (`aks-skills@azure-skills` and `azure@azure-skills`) bundle `copilot-hooks.json` (`install-telemetry.ps1` downloading native `ghcfa-telem` binaries and `track-telemetry`) and plugin `mcp.json` files, so only pinned skill directories are registered.
* `aks-network-capture` installs capture `ConfigMap`s, node/pod packet-capture `Job`s, or debug containers and generates test traffic on live clusters; `airunway-aks-setup` installs AI Runway CRDs, controllers, and GPU inference operators (`make` + `kubectl`); and `azure-search-nav` runs `Connect-AzAccount` (`Az.Accounts`) to send an ARM bearer token to the portal blade-search API. All three stay unregistered and unblocked.

## Boundaries

* `az`, `kubectl`, `jq`, cluster kubeconfig credentials, and `@azure/mcp` count as runtime CLI/service prerequisites under *Tier Qualification* test 3, and AKS is an optional cloud-container vertical under test 4, so every row is `opt-in` and none is `bundled` in `apm.yml`.
* `Squad Azure Architect` (`azure-architect`), `Squad Modernization Planner` (`modernizer`), `Squad Azure Diagnose` (`azure-diagnose`), and `Squad Cost Manager` (`cost-manager`) remain strictly read-only over clusters and source: `azure-architect` authors HLD/LLD designs without running `az aks create` or writing Bicep; `modernizer` assesses manifests or read-only cluster metadata for AKS Automatic without running `kubectl apply` or `az aks update`; `azure-diagnose` investigates incidents read-only without restarting, cordoning, draining, scaling, or capturing packets; `cost-manager` returns indicative findings without changing node pools, autoscalers, storage classes, or commitments.
* `Squad Implementor` (`developer`) authors `Dockerfile`s and Kubernetes manifests only for an approved plan phase under `.copilot-tracking/changes/`, and never runs `kubectl apply`, `helm upgrade`, `az aks`, image pushes, or `git commit` without human approval; live Azure deployments remain with `Squad Deployer` behind the Impactful-Action Gate.
* Existing bundled and community rows (`azure-pricing`, `az-cost-optimize`, `azure-deployment-preflight`, `azure-well-architected-review`) remain distinct and are neither superseded nor blocklisted.
