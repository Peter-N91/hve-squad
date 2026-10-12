---
name: squad-foundry-platform-options
description: "Foundry platform decision questions and upstream skills for gateway, cloud, and Azure Local choices."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-12"
---

# Foundry Platform Options

Use this reference to frame decisions, not to answer volatile product questions from memory. Resolve current capabilities, preview or GA status, supported regions, API versions, and SDK versions through the registered upstream resources in [roster-catalog.md](roster-catalog.md) and the project's actual manifests and lockfiles.

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

Use the registered `microsoft-foundry` and `azure-local` skills for current product guidance. The former is available through the official Microsoft Foundry plugin, while the latter is distributed by the official Azure Local Skills plugin. The Azure Local skill covers the platform, not Foundry Local on Azure Local; verify that preview workload against current Microsoft Learn documentation. Record unknown or conflicting claims as unverified with the smallest next check.

## SDK and API Questions

Ask:

* Which language, package, resolved SDK version, API version, and agent type does the implementation actually use?
* Does the current official quickstart or migration guidance apply to that exact service and agent type?
* Is the selected SDK surface stable or preview, and does the target region support every required feature?
* What build, smoke, integration, and evaluation evidence proves compatibility for the resolved dependency set?
* What changes between planning, implementation, deployment, and acceptance checkpoints?

Do not copy a latest-version number into this reference. Read the manifest and lockfile, then verify that baseline against official release and migration guidance at the checkpoint. A newer version is evidence to assess, not permission to upgrade.
