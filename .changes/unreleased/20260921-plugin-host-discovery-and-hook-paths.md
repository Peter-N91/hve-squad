---
bump: patch
type: Fixed
---

- **VS Code omitted squad agents and local Copilot sessions could not launch plugin hooks.** The plugin builder now emits identical manifests at the root and `.github/plugin/plugin.json`, generates hook commands relative to `${CLAUDE_PLUGIN_ROOT}`, invokes Windows PowerShell with an execution-policy bypass, and rejects missing hook scripts (`scripts/Build-SquadPlugin.ps1`).
