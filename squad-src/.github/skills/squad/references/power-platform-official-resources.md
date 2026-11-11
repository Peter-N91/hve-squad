---
name: squad-power-platform-official-resources
description: "Opt-in Power Platform official skill ownership, prerequisites, and action boundaries."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-11-11"
---

# Power Platform Official Resources

Read this reference for a `power-platform` proposal's resource preflight, or when the resolved root's `team.md` `Packs:` line includes `power-platform`. A proposal permits explanation, not skill selection or installation. Removing the pack stops squad selection and workload guidance. It does not uninstall or hide a host-installed skill.

Host visibility is not selection. A declined resource stays unavailable to the squad even if the host exposes it. The preview jobs below also require explicit preview approval; accepting the pack alone is not that approval.

## Ownership

| Job | Agent | Skill |
|---|---|---|
| Power Pages ALM planning | `Squad Power Platform Architect` | `plan-alm` |
| Model-driven app building | `Squad Power Platform Architect` | `app-builder` |
| Dataverse overview | `Squad Power Platform Architect` | `dv-overview` |
| Copilot Studio knowledge YAML for a locally cloned agentic-loop agent (preview) | `Squad Power Platform Architect` | `add-knowledge` |
| Codeful MCP tool or UI generation | `Squad Power Platform Integrator` | `generate-codeful-mcp-tool`, `generate-mcp-app-ui` |
| Dataverse connection | `Squad Power Platform Integrator` | `dv-connect` |
| Copilot Studio skill import into a locally cloned agentic-loop agent (preview) | `Squad Power Platform Integrator` | `add-skill` |
| Broader Power Platform architecture, Standard-agent topics, or other Copilot Studio work | `Power Platform Expert` | community Alternate; not these official skills |
| Broader connector or integration work | `Power Platform MCP Integration Expert` | community Alternate; not these official skills |

Primary is the fallback when no Selection Cue matches. A matching broad cue selects the named Alternate. If that Alternate is absent or not dispatchable, escalate with its registry install command. Do not substitute the local Primary.

## Installation and readiness

Use the shared **Pack Resource Preflight** in `profiles-and-packs.md` at Init, pack addition, and a missing-resource escalation. `Registered Pack Skills` maps all eleven PP skills to their exact opt-in entries: six existing official skills, three community supplements, and two preview skills. The two community agents remain separate, optional Alternate installs, not new Primaries.

1. Explain the missing resources in plain language. Offer the six existing official skills, optional community supplements, the separate preview bundle, a selected subset, or continuing without them. Preview is not the default. Say which requested job each choice enables.
2. Before preview approval, disclose that the pinned `microsoft/copilot-studio-plugin` bundle installs **all eight skills, four agents, two command prompts, shared scripts/references, and a SessionStart hook**, not only `add-knowledge` and `add-skill`. Its hook can run `npm install` for `keytar` and `@azure/msal-node-extensions` and write a local plugin-path index. This is WIP with support through upstream GitHub Issues only, not a production-readiness guarantee. Installation approval does not approve running that setup, authentication, Graph access checks, migration, or tenant operations. Ask separately before startup dependency setup; if the host cannot keep unapproved hooks from running, do not install the preview bundle there.
3. After the user's resource choices, run `Install-SquadPackResources.ps1` with `-Pack power-platform`, the approved `-Resource` names, a new receipt path, and `-Confirmed`. Both preview rows use the same pinned complete bundle; one successful installation supplies both, so install it once by selecting either preview resource. Do not run its hook manually. The helper installs payloads, not prerequisites. Preserve native confirmation prompts; a failed or cancelled command remains missing.
4. Require a `PASS` receipt, then stop for a host reload. `PLANNED` is not installation, and an on-disk skill is not yet host-visible. After reload, rerun preflight with the actual native host inventory and record every listed skill as `available` or explicitly `declined`, including both preview skills when the user accepted their bundle. Pass the preview approval's decision reference or current explicit request with its dispatch; an `available` flag alone is not preview permission. A declined preview does not prevent applying the pack or using the other approved resources.
5. Check the support roots below before claiming the requested job is ready. Report installed payloads, host visibility, missing support/prerequisites, and tenant readiness separately. Resume a failed setup at the failed step, without inventing availability or overwriting existing files.

The shared installer can run the exact pinned APM entries without a PP-specific installer. APM takes **skill directories**, not `SKILL.md` file paths. Give the user the published [English setup guide](https://peter-n91.github.io/hve-squad/usage.html#power-platform-setup) or [French setup guide](https://peter-n91.github.io/hve-squad/fr/usage.html#power-platform-setup) for detailed commands and troubleshooting; the consumer repository need not contain this project's documentation.

### Complete support roots

Granular installation retains a skill's own files, not its parent plugin's shared files. Resolve a complete installed plugin at the verified ref, or offer a read-only source snapshot in an ignored, user-approved support folder. Fetching a snapshot needs approval too; it does not activate that plugin's hooks, MCP configuration, or extra skills. The documented snapshot commands use `apm_modules/.squad-pack-support/`, which stays under APM's ignored dependency root, and repository-local `core.longpaths=true` for Windows paths. Do not open that checkout as the working project or register it as a plugin.

| Skills | Verified source | Required support root and examples |
|---|---|---|
| `plan-alm` | `microsoft/power-platform-skills@8021d27d517d81963da22e728125a26c9ecfbbe1` | `plugins/power-pages/`, including `scripts/check-version.js` and `scripts/lib/check-alm-plan.js` |
| `app-builder` | same pin | `plugins/model-apps/`, including `references/authoring-flow.md` and `scripts/check-version.js` |
| `generate-codeful-mcp-tool`, `generate-mcp-app-ui` | same pin | `plugins/mcp-apps/`, including `references/`, `samples/`, and `scripts/inline-self-contained-runtime.js` |
| `dv-overview`, `dv-connect` | `microsoft/Dataverse-skills@27e6f6a3fef23075ede87d8e5f028cde29e0130e` | `.github/plugins/dataverse/`, including `scripts/auth.py`; setup still requires a separate approval |
| `add-knowledge`, `add-skill` | `microsoft/copilot-studio-plugin@4014ae689d1228d86cb3aaab938b1e66f8e2e10d` | Full bundle at `apm_modules/microsoft/copilot-studio-plugin/`: `reference/knowledge-schema.md`, `reference/skill-schema.md`, and `scripts/add-skill.js` |

Pass the resolved support root with the dispatch. Resolve `${PLUGIN_ROOT}` and plugin-relative paths to that root, not to the consumer repository or an unrelated plugin. For the preview, use the installed bundle directly when its plugin-path index does not exist; do not run startup setup merely to create that index. Check the pin and required files before use. If they are missing, stop and give the setup remedy instead of generating from memory. An installed plugin at a different ref requires re-verification before it substitutes for the reviewed source.

### Preview selection and exclusions

`add-knowledge` authors modern `capabilities/knowledge` files for a locally cloned **agentic-loop** agent. It needs that agent's `settings.mcs.yml` and `schemaName`; it does not create or clone a cloud agent. Skip its optional authenticated SharePoint/OneDrive access pre-check. A local file or YAML definition is not proof that end users can access the source.

`add-skill` imports a user-selected skill into `behaviors/` in an existing `template: cliagent-*` workspace. Import files only: review the chosen payload, do not execute imported scripts, do not use `--force` to overwrite existing content, and do not push. Downloading a gallery entry is a separate user-selected network action. This is a skill **inside a Copilot Studio agent**, not an HVE customization authored by `prompt-engineer`.

The old `microsoft/skills-for-copilot-studio@9c42d3a612c6e06389b6e5b4eed579aaed1a8b63` targets **Standard** agents and remains experimental and unregistered. Do not mix its topic/knowledge schema with agentic-loop components or migrate implicitly. Broader topic/action design stays on the community Alternate. Evaluation is not admitted by this pack.

The full preview bundle also carries create, clone, pull, push, publish, and delete workflows. They are **not registered squad capabilities** and are not selected by this pack. Neither its four agents nor its two command prompts become roster entries. A request to create a cloud agent, synchronize, migrate, or publish is not permission to run those workflows through a PP charter.

## Boundaries

* Official rows are opt-in skills. Install nothing automatically.
* Whole-plugin install forms for the existing Power Pages, model-apps, and Dataverse plugins remain unregistered. Their shared files can be read from an approved support snapshot without activating hooks or MCP. Only the separately approved Copilot Studio preview uses a complete plugin bundle, verified by disposable no-tenant installation.
* `plan-alm` plans and does not deploy. `dv-connect` can install tools and request consent; do not run that path.
* File-authoring authority does not include an upstream skill's deployment, automatic commit, CLI installation, consent, or authentication steps. If an upstream workflow requires an interactive main conversation, return that entry-point remedy instead of attempting it inside a worker.
* Work IQ and Graph dev-skills stay unregistered here. Do not run `pac` or `paconn` against a tenant, publish, import a solution, or execute the preview's startup dependency setup from a PP charter.
* Community agents and skills remain registered and are not blocklisted.
