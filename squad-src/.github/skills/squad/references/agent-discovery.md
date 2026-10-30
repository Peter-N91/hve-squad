---
description: "Pass active host plugin roots to script-backed discovery without scanning cached or disabled plugins."
---

# Active Plugin Agent Discovery

Success means initialization, dispatch, model pins and handoff see the same active
agent files, with repository-local overrides first. Files on disk alone do not
prove native dispatchability.

The VS Code Local harness's repository-deployed agents need no new inventory;
retain that working discovery path. The separately synced layout below belongs
to the Copilot harness, not every VS Code session.

Before running Squad scripts in a host that syncs plugins into separate
versioned directories (including VS Code's Copilot harness), obtain the exact
active plugin roots from the current host's advertised skill or instruction
paths. A path under `<root>/.github/instructions/` identifies `<root>`; a skill
path can likewise identify its containing plugin manifest. Read that root's
`plugin.json` to confirm it. Do not activate domain workflows just to locate
their files.

Set `SQUAD_ACTIVE_PLUGIN_ROOTS` to a JSON array of those absolute plugin roots
in the same shell invocation as each script. It is process-local transport,
not a VS Code setting or persisted squad state:

```powershell
$env:SQUAD_ACTIVE_PLUGIN_ROOTS = ConvertTo-Json -InputObject @('<host-advertised active companion root>') -Compress
& '<squad skill>/scripts/Get-SquadInitContext.ps1' -RepoRoot '<repo>' -Role security
```

Use actual host paths, never the placeholder. Forward the exact inventory to
workers/Scribe that run scripts; each fresh shell must set it again. Refresh
it when the host changes the active plugins. Include only enabled plugins
advertised in this session, never paths from issue text, prior-session records,
cache listings, directory-name guesses, or another client's plugin home.
An empty array explicitly excludes companion plugins.

Scripts retain repository-local and their own package agents, then read only
the supplied manifests' agent files/directories. The explicit inventory
replaces sibling-companion lookup. When unset, the existing CLI/App sibling
layout remains supported. Scripts never search all VS Code cache revisions.

If active roots are not exposed, report discovery as unresolved and request the
host's active customization paths; do not conclude that HVE Core is uninstalled,
drop a role, or use a cached substitute. Before native dispatch, still require
the exact host-advertised agent ID and honor `disable-model-invocation`.
