---
name: squad-scribe-tools
description: "Configure Scribe tools for a consumer project; consult only when changing tool access or adding a persistence adapter."
---

# Scribe Tool Configuration

The shipped Scribe selects `read`, `search`, `edit`, and `execute`, plus
`vscode/memory`. File operations persist confirmed records; execution runs the
deterministic writers and checks; memory stores local repository learnings.
Read/write alone cannot run those helpers. Portable aliases retain host-specific
file operations needed by cold writes without selecting every installed tool.

This is a tool-surface limit, not a filesystem or network sandbox. Shell access
can launch other programs. Keep host approvals, filesystem protections, network
controls, and the existing helper-only shell policy in force. Unsupported tool
names are ignored by the host; verify available tools before relying on them.
VS Code repository memory is not automatically a CLI subagent capability. Report
an unavailable memory or relocation operation rather than substituting unverified
writes or claiming success.

## Project-Specific Persistence

Keep the default local. Adding Confluence, Azure DevOps, or another source of
truth requires an approved persistence contract, not merely an available tool.
Specify canonical versus mirrored records, allowed destinations and operations,
idempotency and version checks, receipts, retries, and partial-failure reporting.
Preserve local history and ledger obligations unless an approved contract
explicitly replaces them. Never put credentials in the agent or payload.

Configure and authenticate the selected MCP server through the host. In a
consumer-owned Scribe definition, retain the baseline tools and add only the
actual, discovered `server/tool` IDs required by that adapter. Do not grant `*`
or server-wide wildcards for a hypothetical integration. No remote adapter is
implemented or enabled by the default definition.

Agent YAML has no assumed additive tool overlay. Maintain a complete static
definition under consumer ownership, outside regenerated upstream output, and
verify which definition the target host dispatches. Do not assume a same-name
workspace file always overrides a plugin; host precedence differs. Prompt-level
tool overrides are invocation-specific, not a general hidden-subagent overlay.
Recheck the consumer definition when upstream Scribe behavior changes.

## References

* [GitHub custom agent tools and aliases](https://docs.github.com/en/copilot/reference/custom-agents-configuration#tools)
* [VS Code tools reference](https://code.visualstudio.com/docs/agents/reference/tools-reference)
* [VS Code custom agents](https://code.visualstudio.com/docs/agent-customization/custom-agents)
* [Copilot CLI reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)