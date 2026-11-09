---
name: squad-power-platform-official-resources
description: "Opt-in Power Platform official skill ownership, prerequisites, and action boundaries."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-11-04"
---

# Power Platform Official Resources

Use this reference only when the resolved root's `team.md` `Packs:` line includes `power-platform`. Removing the pack stops squad selection and this guidance. It does not uninstall or hide a host-installed skill.

## Ownership

| Job | Agent | Skill |
|---|---|---|
| Power Pages ALM planning | `Squad Power Platform Architect` | `plan-alm` |
| Model-driven app building | `Squad Power Platform Architect` | `app-builder` |
| Dataverse overview | `Squad Power Platform Architect` | `dv-overview` |
| Codeful MCP tool or UI generation | `Squad Power Platform Integrator` | `generate-codeful-mcp-tool`, `generate-mcp-app-ui` |
| Dataverse connection | `Squad Power Platform Integrator` | `dv-connect` |
| Broader Power Platform architecture or Copilot Studio | `Power Platform Expert` | community Alternate; not these official skills |
| Broader connector or integration work | `Power Platform MCP Integration Expert` | community Alternate; not these official skills |

Primary is the fallback when no Selection Cue matches. A matching broad cue selects the named Alternate. If that Alternate is absent or not dispatchable, escalate with its registry install command. Do not substitute the local Primary.

## Boundaries

* Official rows are opt-in skills. Install nothing automatically.
* Whole-plugin install forms for hook-bearing or MCP-bearing plugins were rejected on 2026-11-04 because disposable no-tenant validation was unavailable. Use the granular `apm install ... --target copilot` command in *Registered External Cast*.
* `plan-alm` plans and does not deploy. `dv-connect` can install tools and request consent; do not run that path.
* Copilot Studio, Work IQ, and Graph dev-skills stay unregistered here.
* Community agents and skills remain registered and are not blocklisted.