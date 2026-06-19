---
description: "Capability-aware MCP routing for squad dispatched roles, with named fallbacks when an MCP is absent"
applyTo: '**/.copilot-tracking/squad/**'
---

# Squad MCP Capability Conventions

These conventions tell the Squad Coordinator and every dispatched role how to choose between a Model Context Protocol (MCP) server and a non-MCP default for a given capability. Dispatched roles do not assume an MCP is present. They name the capability they need, check whether a preferred MCP is configured in the workspace, and either use it or fall back to the named default without breaking the flow.

The hve-squad package ships a small reference template at `.github/skills/squad/mcp.template.json` (alongside the squad skill `SKILL.md`) that the consumer may merge into their own `.vscode/mcp.json`. The package never reads or writes the consumer's `.vscode/mcp.json`.

## Capability Map

The coordinator passes a capability hint to each dispatched role when the role needs a tool that varies by workspace configuration. The role consults the capability map below, prefers the listed MCP when present, and otherwise uses the named fallback.

| Capability         | Preferred MCP                                | Non-MCP Fallback                                                                |
|--------------------|----------------------------------------------|---------------------------------------------------------------------------------|
| diagram-rendering  | A draw.io MCP server when one is configured  | Render Mermaid in chat; or author Mermaid in repository markdown                |
| ADO query          | `@azure-devops/mcp` (Microsoft official)     | Researcher Subagent against the Azure DevOps REST API with a user-supplied PAT  |
| Azure-pricing      | `msftnadavbh/AzurePricingMCP` community server | Researcher Subagent against the Azure Retail Prices REST API (`https://prices.azure.com/api/retail/prices`) |
| azure-resource     | `@azure/mcp` (official Azure MCP server)      | Researcher Subagent against the Azure CLI (`az`) and the Azure Resource Graph / Resource Manager REST APIs using the user's `az login` context |
| architecture-docs  | `microsoft-docs` MCP when configured         | Researcher Subagent against `learn.microsoft.com` via web fetch                 |
| code-context       | `context7` MCP when configured               | Researcher Subagent against the published library documentation                 |
| github-issue       | `github` MCP (GitHub official) when configured | The `gh` CLI when authenticated; otherwise an in-chat ping (no remote approval) |

The "Preferred MCP" column names the server the role tries first. The "Non-MCP Fallback" column is what the role does when the preferred MCP is not configured, is unreachable, or returns an error during the dispatched turn.

The `github-issue` capability backs the remote approval channel in `.github/instructions/squad/squad-notifications.instructions.md`. Its fallback chain is `github` MCP → `gh` CLI → in-chat: on a headless VM an authenticated `gh` CLI is sufficient and the MCP is not required, and when neither is available the squad degrades to an in-chat approval (the user simply cannot approve remotely).

The `azure-resource` capability backs the squad's Azure governance discovery, as-built inventory, and diagnose roles. It reads Azure control-plane data such as policy assignments, Resource Graph results, and Azure Monitor logs through `@azure/mcp`, and falls back to the `az` CLI and the Azure Resource Graph and Resource Manager REST APIs under the user's `az login` context when that MCP is absent. All reads on this path are non-destructive.

## Capability Hint Contract

The Squad Coordinator includes a capability hint in the subagent invocation when a dispatched role needs a configurable tool. The hint takes the form `capability=<name>` where `<name>` matches a row in the capability map above. The role then follows this contract:

1. Check whether the preferred MCP for the named capability is configured in the active VS Code workspace.
2. When the MCP is configured and reachable, use it for the duration of the turn.
3. When the MCP is absent or returns an error, fall back to the named default in the capability map without pausing the turn.
4. Record the choice in the role's response (`used: <preferred-mcp>` or `used: <fallback-name>`) so the Scribe can capture which path the turn took in `history/<agent>.md`.

## Graceful Degradation

Dispatched roles never block the squad on a missing MCP. When the preferred MCP for a capability is unavailable, the role uses the named fallback in the capability map and continues. The role surfaces the fallback choice in its response so the user and the Scribe both see which tool produced the result.

When neither the preferred MCP nor the named fallback can satisfy the capability (for example, the workspace has no internet for a REST fallback), the role escalates to the coordinator with a `blocked` status and names the capability and the failed paths. The coordinator then escalates to the user per the routing escalation rules.

## Out-of-Band Fallbacks

Two capabilities the squad uses have no official MCP server at the time of writing. The recommended replacement for each is an out-of-band tool that the consumer installs alongside VS Code rather than through `.vscode/mcp.json`.

### Draw.io

Install the `hediet.vscode-drawio` extension from the VS Code Marketplace. The extension edits `.drawio`, `.dio`, `.drawio.svg`, and `.drawio.png` files natively in VS Code and runs offline. Dispatched roles that need a richer diagram than Mermaid can render should ask the user to open or create a `.drawio` file in the workspace and continue authoring there. No MCP entry is required for this path; the extension is the integration surface.

### Python `diagrams` Library

Run the python `diagrams` library through the `python-foundational` skill or directly in the terminal. The library renders architecture diagrams as PNG or SVG via a Graphviz backend. Dispatched roles should scaffold a small Python script that imports from `diagrams`, invoke it through the `python-foundational` skill (which manages the virtual environment), and reference the rendered image in the response. No MCP entry is required for this path; the library is the integration surface.

## Consumer Override

The consumer owns every write to `.vscode/mcp.json`. The hve-squad APM package ships only the reference template at `.github/skills/squad/mcp.template.json` and never overwrites the consumer's MCP configuration. Consumers are free to:

* Adopt the template verbatim by copying its `inputs` and `servers` entries into their `.vscode/mcp.json`.
* Merge only selected entries from the template with servers they already have configured.
* Add servers the template does not include (for example, a community draw.io MCP, an Azure Cost MCP when one ships, or any other server they trust).
* Remove servers from their own `.vscode/mcp.json` at any time; dispatched roles will fall back per the capability map.

The HVE Core installer follows the same boundary. For the canonical merge pattern that consumers may reuse when seeding `.vscode/mcp.json` from multiple templates, see `apm_modules/microsoft/hve-core/.github/skills/installer/hve-core-installer/SKILL.md`. Treat that skill as a reference; do not duplicate its content into the squad package.
