---
name: squad-m365-copilot-platform-options
description: "Opt-in M365 Copilot path split between Agents SDK official skills and community declarative-agent or MCP work."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-11-04"
---

# M365 Copilot Platform Options

Use this reference only when the resolved root's `team.md` `Packs:` line includes `m365-copilot`. Removing the pack stops squad selection and this guidance. It does not uninstall or hide a host-installed skill.

## Paths

| Request | Agent | Skill |
|---|---|---|
| .NET Agents SDK production readiness | `Squad M365 Agent Architect` | `agents-sdk-to-prod` |
| Agents SDK OpenTelemetry | `Squad M365 Agent Integrator` | `agents-sdk-dotnet-otel` |
| Agents SDK provisioning plan | `Squad M365 Agent Integrator` | `agents-sdk-provision` |
| Declarative agent, TypeSpec, API plugin, or broader M365 architecture | `Declarative Agents Architect` | community Alternate |
| Broader MCP-backed M365 integration | `MCP M365 Agent Expert` | community Alternate |

Primary is the fallback when no Selection Cue matches. A matching broad cue selects the named Alternate. If that Alternate is absent or not dispatchable, escalate. Do not substitute the local Primary.

## Boundaries

* Work IQ and Microsoft Graph dev-skills stay deferred. Do not register or select them from this pack.
* `agents-sdk-provision` is a plan here. Do not create Azure Bot, Entra, or Bicep resources, and do not consent to a tenant.
* Whole-plugin install was not sandbox-validated. Use the granular install command in *Registered External Cast*. Install nothing automatically.
* Community agents remain registered Alternates and are not blocklisted.