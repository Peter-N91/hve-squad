---
name: azure-scaffold
description: 'Documentation-only reference templates for the Azure execution layer a consumer repo needs to author IaC, deploy to Azure with OIDC, and govern infrastructure. Use when a squad agent or the coordinator scaffolds a dev container, OIDC setup script, Bicep/Terraform deploy workflows, a governance policy baseline, or the infra/ folder convention into a consumer repo. Templates never run from this package.'
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-06-12"
---

# Azure Scaffold

## Overview

This skill bundles the **documentation-only reference templates** a consumer repository needs to do
Azure work end-to-end — author Infrastructure-as-Code, deploy to Azure, and govern infrastructure —
the way a deployable template repo (such as the APEX accelerator) ships them. Because hve-squad is an
APM **package** (installed *into* a repo) rather than a template repo (cloned *as* a repo), it cannot
ship live pipelines. Instead it ships these templates and a consumer-facing agent copies them into the
consumer's repo on demand.

This mirrors the existing reference-template-in-a-skill pattern already used by the squad skill in
`.github/skills/squad/` (`mcp.template.json` and `github-approval-watcher.workflow.yml`): the package
never reads or writes the consumer's `.devcontainer/`, `.github/workflows/`, `scripts/`, or `infra/`
trees. The consumer owns every copy, merge, and commit.

> **Nothing here runs from the package.** Each file below is an inert reference template. Activation is
> always an explicit, deliberate copy into the consumer repo followed by a reviewed commit.

## Bundled Templates

| Template                                                       | Consumer destination                          | Purpose                                                                                     |
|----------------------------------------------------------------|-----------------------------------------------|---------------------------------------------------------------------------------------------|
| [devcontainer.template.json](devcontainer.template.json)       | `.devcontainer/devcontainer.json`             | Dev container with Azure CLI + Bicep, Terraform + TFLint, GitHub CLI, Node.js, and Python.  |
| [Setup-AzureOidc.template.ps1](Setup-AzureOidc.template.ps1)   | `scripts/Setup-AzureOidc.ps1`                 | One-time wizard: Entra app registration, OIDC federated credentials, RBAC, and GitHub secrets. |
| [deploy-bicep.workflow.yml](deploy-bicep.workflow.yml)         | `.github/workflows/deploy-bicep.yml`          | Bicep what-if + deploy via `azure/login@v2` OIDC (no stored client secret).                 |
| [deploy-terraform.workflow.yml](deploy-terraform.workflow.yml) | `.github/workflows/deploy-terraform.yml`      | Terraform plan + apply via `azure/login@v2` OIDC with an Azure Storage backend.             |
| [Get-PolicyBaseline.template.ps1](Get-PolicyBaseline.template.ps1) | `scripts/Get-PolicyBaseline.ps1`          | Read-only capture of effective Azure Policy assignments (with management-group inheritance). |
| [governance-baseline.workflow.yml](governance-baseline.workflow.yml) | `.github/workflows/governance-baseline.yml` | Scheduled run of the policy baseline that opens a PR when governance drifts.              |

## The `infra/` Folder Convention

Both IaC tracks live under a per-project `infra/` tree so one repo can hold multiple workloads:

```text
infra/
  bicep/
    {project}/
      main.bicep            # entry point (subscription- or resource-group-scoped)
      modules/              # local modules; prefer AVM modules (br/public:avm/res/...)
      main.bicepparam       # parameters per environment
  terraform/
    {project}/
      main.tf               # root module
      modules/              # local modules; prefer AVM (registry.terraform.io/Azure/avm-res-*)
      backend.tf            # Azure Storage backend config
      *.tfvars              # parameters per environment
```

The Squad Azure Architect's LLD table maps one row per Azure resource to one resource declaration in
`{project}/`. The Squad IaC Author converts that table into the files above; the deploy workflows then
target `infra/bicep/{project}` or `infra/terraform/{project}` by a `project` input.

## Scaffolding Flow

A consumer-facing squad agent (Squad IaC Author or Squad Deployer) or the coordinator scaffolds the
Azure layer into a consumer repo with these steps. The flow is copy-then-commit; the package never
writes these paths itself.

1. **Confirm intent and destinations.** Identify which templates the consumer needs and confirm the
   destination paths in the table above. Never overwrite an existing consumer file without showing the
   diff and getting explicit approval.
2. **Copy and rename.** Copy each template to its destination, dropping the `.template` / `.workflow`
   marker so the file becomes active in the consumer repo (for example,
   `devcontainer.template.json` → `.devcontainer/devcontainer.json`,
   `deploy-bicep.workflow.yml` → `.github/workflows/deploy-bicep.yml`).
3. **Fill placeholders.** Replace every `<PLACEHOLDER>` token (subscription ID, resource group, region,
   project name, management-group ID) with the consumer's values. Leave no placeholder behind.
4. **Wire identity.** Run `scripts/Setup-AzureOidc.ps1` once to create the federated identity and
   populate the GitHub secrets/variables the deploy workflows consume. No client secret is ever stored.
5. **Enable PR creation (governance only).** For the governance baseline workflow, the consumer enables
   *Settings → Actions → General → Allow GitHub Actions to create and approve pull requests*.
6. **Commit deliberately.** Stage and commit the scaffolded files in the consumer repo. Any actual
   Azure deployment runs only through the Squad Deployer, strictly behind the squad's
   Impactful-Action Gate.

## Security Posture

Every template follows these non-negotiable constraints (carried from the council verdict for this
capability):

* **OIDC only.** Authentication to Azure uses workload-identity federation through `azure/login@v2`.
  No client secret, PAT, or long-lived credential is stored in the repo or in the templates.
* **Least privilege.** The setup script assigns `Reader` at the management-group scope and `Contributor`
  at the subscription scope by default; narrow these to resource-group scope where the workload allows.
* **No embedded credentials.** Templates contain only `<PLACEHOLDER>` tokens and GitHub
  `secrets`/`vars` references. The setup script never echoes secret values to the console or logs.
* **Deploys stay gated.** Live deployment runs only through the Squad Deployer at the `confirm`
  autonomy tier, behind the Impactful-Action Gate defined in
  `.github/instructions/squad/squad-autopilot.instructions.md`. The package itself deploys nothing.
* **Read-only governance.** The policy baseline capture is read-only; it never mutates Azure Policy.

## Prerequisites (consumer side, when the copied templates are used)

* An Azure subscription with Owner or User Access Administrator rights to run the OIDC setup once.
* The Azure CLI (`az`) with the Bicep extension, and the GitHub CLI (`gh`) authenticated — both are
  provided by `devcontainer.template.json`.
* PowerShell 7+ to run the `.ps1` scripts.

## Troubleshooting

* **`No subscription found`** — run `az login` and `az account set --subscription <id>` before the
  setup script.
* **Workflow fails with `AADSTS700016` / `no matching federated identity record`** — the federated
  credential subject does not match the workflow's `environment`/branch. Re-run
  `Setup-AzureOidc.ps1` and confirm the `subject` matches `repo:<owner>/<repo>:environment:<env>`.
* **`GitHub Actions is not permitted to create or approve pull requests`** — enable the setting in
  *Settings → Actions → General* (governance baseline workflow only).

## Attribution

Part of [hve-squad](https://github.com/Peter-N91/hve-squad), built on
[Microsoft HVE Core](https://github.com/microsoft/hve-core) agents and conventions.
