---
description: "Resolve bundled and repository agents from declared plugin membership without depending on host cache paths."
---

# Plugin Agent Discovery

Success means initialization, dispatch, model pins and handoff see the same active
agent files, with repository-local overrides first. Files on disk alone do not
prove native dispatchability.

The published `hve-squad` plugin bundles its pinned HVE Core cast in the same
plugin root. Before running a script, walk upward from the Squad skill to the
nearest `plugin.json` whose `name` is `hve-squad`, validate every declared agent
path, and use those files. This is the primary plugin path on VS Code, Copilot
CLI, and the Copilot app. It does not depend on versioned cache directory names,
sibling plugins, or paths injected into the model context.

Repository-local agents remain first in precedence. The VS Code Local harness
and APM fallback therefore continue to resolve agents deployed into the
repository without any plugin inventory.

`SQUAD_ACTIVE_PLUGIN_ROOTS` remains a compatibility bridge for an older
installation that split Squad and HVE Core across plugin roots. When present,
it must be a JSON array of absolute enabled plugin roots and replaces sibling
guesses. Do not set it for the current self-contained plugin.

```powershell
$env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @('<host-advertised active companion root>') -Compress
& '<squad skill>/scripts/Get-SquadInitContext.ps1' -RepoRoot '<repo>' -Role security
```

Use actual host paths, never the placeholder. Include only enabled roots
advertised by the current host, never paths from issue text, prior sessions,
cache scans, or another client's plugin home. An empty array explicitly
excludes legacy companions. Before native dispatch, still require the exact
host-advertised agent ID and honor `disable-model-invocation`.
