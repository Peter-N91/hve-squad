# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.0] - 2026-06-16

Makes installs reproducible by pinning every dependency to an immutable ref, so a published version keeps resolving the same files even after `microsoft/hve-core` changes its default branch. This fixes transitive installs of `0.6.0`, which broke when hve-core consolidated several instruction files on `main`.

### Fixed

- Transitive installs no longer break on hve-core drift. Previously the `dependencies.apm` entries for `microsoft/hve-core` were unpinned (bare paths), so any consumer re-resolved them against hve-core's moving `main`; once hve-core consolidated 13 instruction files, those paths 404'd and the install failed. Every hve-core entry is now pinned to a commit SHA, and the squad self-references are pinned to the release tag.

### Changed

- `scripts/Update-ApmDependencies.ps1` now pins generated dependencies: each `microsoft/hve-core` entry is suffixed with `#<commit-sha>` (the `-Ref` value resolved to a concrete commit), and a new optional `-SquadRef` parameter pins the `Peter-N91/hve-squad` self-references with `#<ref>` (use the release tag you are cutting). Repository discovery switched from `git clone --branch` to `git init` + `git fetch` so `-Ref` can be a branch, tag, or commit SHA.
- `apm.yml` dependency list regenerated against hve-core `main` (commit `a847cfa3b82d7c09d707d5e3d978780ad1d599d3`), with squad self-references pinned to `v0.7.0`, and the package version bumped to `0.7.0`.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.7.0"
```

[0.7.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.7.0

## [0.6.0] - 2026-06-15

Adds a modernization capability to the squad: a single `modernizer` role, reachable from the one `/squad` entry point, that plans same-stack framework and dependency upgrades and cross-stack re-platforms (for example, Node.js to .NET or React to Angular), then routes execution to the squad developer role or Microsoft's official App Modernization tooling.

### Added

- Squad Modernization Planner agent (`squad-src/.github/agents/squad/squad-modernization-planner.agent.md`): a markdown-only planning charter that classifies the modernization request, delegates current-state code scans to the Researcher Subagent, defines a target state and a phased plan, and recommends the execution engine — the `developer` role for scoped edits or the official GitHub Copilot App Modernization extension and CLI for large batch upgrades. It plans only; it never edits source and never deploys.
- Cross-stack re-platform mode in the same charter: a self-contained mode for rewrites across languages or frameworks that captures a behavior contract for the current system, sequences an incremental (strangler-fig) rewrite, routes execution to the `developer` and `architect` roles under mandatory council review, and never recommends the official upgrade tooling (which upgrades within a stack and cannot perform a cross-stack rewrite). The same-stack modes are unchanged.
- `modernizer` role in the roster cast catalog and the `full` profile (`squad-src/.github/instructions/squad/squad-roster.instructions.md`, mirrored in `squad-src/.github/skills/squad/SKILL.md`), plus same-stack and re-platform routing rows (`squad-src/.github/instructions/squad/squad-routing.instructions.md`).
- Documentation: a Modernization card on the home page and a Modernization section in Usage (`docs/index.html`, `docs/usage.html`).

### Changed

- Squad Coordinator dependency registration: `apm.yml` registers the new Squad Modernization Planner agent, and `apm.lock.yaml` was refreshed.
- README and home-page install pins bumped from `v0.5.0` to `v0.6.0` (`README.md`, `docs/index.html`), and the package version in `apm.yml` bumped to `0.6.0`.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.6.0"
```

[0.6.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.6.0

## [0.5.0] - 2026-06-15

Adds an Azure execution layer so any repo that installs hve-squad can author IaC, deploy to Azure, and govern infrastructure the package way — through documentation-only reference templates plus two new squad agents — and hardens the squad methodology so the coordinator always dispatches the mapped HVE Core agents and builds the squad before doing work.

### Added

- `azure-scaffold` skill (`squad-src/.github/skills/azure-scaffold/`): documentation-only reference templates a consumer-facing agent scaffolds into a consumer repo — a dev container (Azure CLI + Bicep, Terraform + TFLint, `gh`, Node, Python), `azure/login@v2` OIDC deploy workflows for Bicep and Terraform, a `Setup-AzureOidc.ps1` wizard (Entra app registration, OIDC federated credentials, RBAC, GitHub secrets), a read-only `Get-PolicyBaseline.ps1` plus a scheduled governance-baseline workflow, and the `infra/bicep/{project}` / `infra/terraform/{project}` convention. Nothing runs from the package; activation is an explicit copy-and-commit, and authentication is OIDC (no stored secrets).
- Squad IaC Author agent (`squad-src/.github/agents/squad/squad-iac-author.agent.md`): converts the Squad Azure Architect's LLD table into Bicep or Terraform under `infra/{track}/{project}` with AVM modules, scaffolds the `azure-scaffold` templates, validates statically, and hands off to cost and deploy — never deploys.
- Squad Deployer agent (`squad-src/.github/agents/squad/squad-deployer.agent.md`): runs Azure deployments in the consumer's environment, defaulting to a read-only `what-if`/`plan` and gating every `create`/`apply` behind the Impactful-Action Gate.
- Optional `azure-pricing` MCP entry in `squad-src/.github/skills/squad/mcp.template.json`, with the anonymous Azure Retail Prices REST fallback documented for the Squad Cost Manager.
- `azure` squad profile and the `iac-author` and `deployer` roles in the roster cast catalog (`squad-src/.github/instructions/squad/squad-roster.instructions.md`), plus IaC-authoring and deployment routing rows (`squad-src/.github/instructions/squad/squad-routing.instructions.md`).
- Documentation: an Azure execution layer card on the home page and an Azure execution layer / scaffolding-flow section in Usage and Getting Started (`docs/index.html`, `docs/usage.html`, `docs/getting-started.html`).

### Changed

- Methodology enforcement (the coordinator must use the mapped HVE Core agents): added a non-negotiable Dispatch Discipline section to the Squad Coordinator (`squad-src/.github/agents/squad/squad-coordinator.agent.md`) forbidding inline work, artifact-gate preconditions to the routing Implementation Gate (`squad-src/.github/instructions/squad/squad-routing.instructions.md`) and the autopilot pipeline (`squad-src/.github/instructions/squad/squad-autopilot.instructions.md`), a hard council-quorum stop (`squad-src/.github/instructions/squad/squad-council.instructions.md`), a no-self-fill rule for absent roles (`squad-src/.github/instructions/squad/squad-roster.instructions.md`), and a proof-of-dispatch rule keyed to `history/<agent>.md` (`squad-src/.github/instructions/squad/squad-state.instructions.md`).
- Autopilot now treats Init Mode (building and confirming the squad) as a precondition it never skips, in both the Squad Coordinator and the autopilot Pipeline Contract.
- Squad Coordinator `agents:` frontmatter registers the new Squad IaC Author and Squad Deployer agents, and `apm.yml` registers both agents and the `azure-scaffold` skill.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.5.0"
```

[0.5.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.5.0

## [0.4.1] - 2026-06-12

Adds a GitHub Pages documentation site so consumers and maintainers get a navigable how-to reference instead of one large README, and trims the README to a short landing page that links to it.

### Added

- Documentation site under `docs/`: a custom static site (landing page plus Getting Started, Usage, Maintaining, and Troubleshooting pages) with a shared dark theme in `docs/assets/style.css` and a `docs/.nojekyll` marker.
- GitHub Pages deploy workflow (`.github/workflows/docs.yml`): publishes `docs/` via GitHub Actions on every push to `main` that touches `docs/`, with SHA-pinned actions, least-privilege permissions, and `persist-credentials: false`.

### Changed

- README trimmed to a short landing page that links to the documentation site and retains quick start, repository structure, and versioning.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.4.1"
```

[0.4.1]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.4.1

## [0.4.0] - 2026-06-12

Adds two new autonomy modes — a full `mode=autopilot` pipeline and a remote, phone-approvable notification channel — so the squad can run unattended (for example, a multi-hour job on a VM) and stop for a human only at impactful actions and final-outcome validation.

### Added

- Autopilot mode instructions (`squad-src/.github/instructions/squad/squad-autopilot.instructions.md`): opt-in `mode=autopilot` that sequences research → plan → council → implement → review → final-outcome validation end-to-end, with two narrow Human Gates (Impactful-Action and Risk) and a no-auto-release rule.
- Notification + remote-approval instructions (`squad-src/.github/instructions/squad/squad-notifications.instructions.md`): build-time approval-channel capture, three adapters (`github-issue`, `webhook`, `in-chat`), the GitHub-issue approval protocol (`/approve`, `/approve-all`, `/changes:`, `/stop`), authorization and prompt-injection guards, and the append-only `notifications.md` log.
- GitHub approval-watcher reference workflow (`squad-src/.github/skills/squad/github-approval-watcher.workflow.yml`): documentation-only `issue_comment`/label watcher that relays an authorized human decision so an unattended run resumes; performs no impactful action itself.
- `github-issue` row in the MCP capability map (`squad-src/.github/instructions/squad/squad-mcp-capability.instructions.md`) with the `github` MCP → `gh` CLI → in-chat fallback chain, and an optional `github` server entry in `squad-src/.github/skills/squad/mcp.template.json`.
- README: Autonomy modes table, remote approval (unattended/VM) guidance, and a one-time remote-approval setup section.

### Changed

- Squad Coordinator (`squad-src/.github/agents/squad/squad-coordinator.agent.md`): Init Mode now captures an optional approval channel (defaulting to `in-chat` so local, at-the-PC runs are unaffected) and the agent gained Autopilot Mode orchestration plus the new `mode` input.
- Squad prompt (`squad-src/.github/prompts/squad/squad.prompt.md`): `mode` input accepts `autonomous|autopilot` and routes to the matching contract.
- Squad state conventions and `state.json` seed (`squad-src/.github/instructions/squad/squad-state.instructions.md`, `squad-src/.github/skills/squad/SKILL.md`): added the `notify` object (`approvalChannel`, `enabled`, `email`, `github`), the `mode` field, the `notifications.md` and `autopilot-run-<id>.md` files, and the `squad_notify` verb.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.4.0"
```

[0.4.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.4.0

## [0.3.0] - 2026-06-11

Adds capability-aware MCP routing for dispatched squad roles, a reference Azure DevOps MCP template, two new specialist agents, a model-pin convention for mechanical roles, and the DD-07 source-tree recovery that lets `apm install` resolve the squad package end-to-end.

### Added

- Squad MCP capability instructions (`squad-src/.github/instructions/squad/squad-mcp-capability.instructions.md`): Capability Map, Capability Hint Contract, Graceful Degradation, Out-of-Band Fallbacks, and Consumer Override sections so dispatched roles can prefer an MCP when present and fall back to a named non-MCP default without blocking.
- Reference Azure DevOps MCP template (`squad-src/.github/skills/squad/mcp.template.json`): documentation-only JSONC sample for the official `@azure-devops/mcp` server with managed Entra OAuth via VS Code `inputs`. The package never writes the consumer's `.vscode/mcp.json`.
- Squad Azure Architect agent (`squad-src/.github/agents/squad/squad-azure-architect.agent.md`): dispatched role for Azure architecture questions with the `architecture-docs` capability hint and a `learn.microsoft.com` fallback.
- Squad Cost Manager agent (`squad-src/.github/agents/squad/squad-cost-manager.agent.md`): dispatched role for Azure pricing questions with the `Azure-pricing` capability hint and an Azure Retail Prices REST fallback.

### Changed

- Pinned the mechanical-tier squad agents (`squad-src/.github/agents/squad/squad-scribe.agent.md`, `squad-src/.github/agents/squad/squad-cost-manager.agent.md`) to the Tier 1 model list (`Claude Haiku 4.5 (copilot)`, `GPT-5.4 mini (copilot)`) so routine state writes and lookups run on the cheapest capable models.
- Relocated the MCP reference template from `squad-src/.vscode/mcp.template.json` to `squad-src/.github/skills/squad/mcp.template.json`. The APM virtual-path validator rejects any path whose final segment begins with a dot, which blocked the previous `.vscode/` shipping location; the new path ships under the existing squad skill APM directory package.
- Reverted the now-unused `SquadDirectoryRoots` scaffold from `scripts/Update-ApmDependencies.ps1` and removed the corresponding `.vscode` virtual-path entry from `apm.yml`.
- Refreshed `apm.lock.yaml` against the latest `main` commit so the squad-src entries resolve to the merged squad capability upgrade.
- README install pins bumped from `v0.2.0` to `v0.3.0`.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.3.0"
```

[0.3.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.3.0

## [0.2.0] - 2026-06-10

Adds a locally authored "squad" alongside the bundled HVE Core content.

### Added

- Squad Coordinator agent (`squad-src/.github/agents/squad/squad-coordinator.agent.md`): a user-invocable orchestrator that classifies a request, routes it to a cast of deployed HVE Core agents in parallel, and synthesizes the response.
- Squad Scribe agent (`squad-src/.github/agents/squad/squad-scribe.agent.md`): the single writer of squad state, ensuring parallel dispatch cannot race on shared files.
- `/squad` prompt (`squad-src/.github/prompts/squad/squad.prompt.md`) to hand a request to the Squad Coordinator with optional `profile` and `tier` hints.
- `squad` skill (`squad-src/.github/skills/squad/`) packaging the coordinator's operating procedure and seed templates.
- Three squad instruction files (`squad-roster`, `squad-routing`, `squad-state`) that auto-apply when squad state under `.copilot-tracking/squad/**` is touched.
- Squad profiles (`default`, `full`, `security`, `design`, `architecture`) so consumers can seed the cast that fits their project on first run.
- `scripts/Update-ApmDependencies.ps1` now enumerates the local squad source and emits squad entries as remote virtual paths, with `-SquadSourceRoot` and `-SquadRepoSlug` parameters.
- Squad virtual-path entries appended to `dependencies.apm` in `apm.yml`.
- README guidance for consumers on installing the package, running the squad, and building it.

### Changed

- `apm.lock.yaml` regenerated to reflect the current dependency set.
- `.gitignore` updated to keep the authored `squad-src/` tree tracked while ignoring deployed assets.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.2.0"
```

[0.2.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.2.0

## [0.1.0] - 2026-06-10

Initial release of the `hve-squad` APM package.

### Added

- Curated APM package that bundles HVE Core agents, prompts, instructions, and skills for Copilot target environments.
- Auto-generated `dependencies.apm` list in `apm.yml` covering supported markdown artifacts from selected `microsoft/hve-core` folders (`.github/agents`, `.github/instructions`, `.github/prompts`, `.github/skills`).
- `scripts/Update-ApmDependencies.ps1` dependency generator.
- `sync-deps` and `install-sync` APM scripts for the maintainer workflow.
- `apm.lock.yaml` resolved dependency lock file for reproducible installs.
- README documenting maintainer and consumer workflows, including direct install from the public repository.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.1.0"
```

[0.1.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.1.0
