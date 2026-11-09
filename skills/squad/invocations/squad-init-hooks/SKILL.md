---
name: squad-init-hooks
description: "Writes the squad's hook backstops into the consuming repository's .github/hooks/ for hosts that require repository hooks or do not reliably execute plugin hooks. Use for Copilot CLI enforcement, cloud-agent/Watch Mode enforcement, or when the user asks to run 'squad-init-hooks'."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Init Hooks

## Why This Exists

Plugin hook discovery is not proof of hook execution. Current validation against Copilot CLI 1.0.105 showed that an installed plugin's hook entries can be listed yet not fire, while Copilot cloud agent loads hooks only from committed `.github/hooks/*.json` files. The agents and reference rules remain the primary behavioral contract; this skill installs repository-owned runtime backstops for the Impactful-Action Gate, append-only state, dispatch-time checks, and autonomous escalation.

This is a **single-purpose action**: it drops hook files into the consuming repository. It does nothing else — no roster seeding, no profile selection, no `team.md`/`routing.md` creation.

## Inputs

* **targetDir** (optional, defaults to `.github/hooks/`): where to write the hook configuration and its scripts in the consuming repository.
* **force** (optional, defaults to `false`): when `true`, overwrite an existing `hve-squad.json`/`hve-squad/` drop from a prior run of this same skill. Never overwrites a file this skill did not itself create — see *Idempotency* below.

## Flow

1. **Read the plugin's own `hooks.json`** and its referenced scripts under `hooks/scripts/`.
2. **Keep the cross-platform command entries.** Preserve each hook's Bash and PowerShell commands. Cloud agent ignores PowerShell, while local Windows clients use it. PowerShell 7.4+ remains required for the dispatch guard; disclose this prerequisite rather than installing it or claiming a hook executed.
3. **Write the hook configuration** to `<targetDir>/hve-squad.json`, replacing the plugin-only `${PLUGIN_ROOT}` working directory with the repository root and rewriting command paths relative to that root.
4. **Copy both script variants** to `<targetDir>/hve-squad/`, including `dispatch-guards.ps1` and `dispatch-guards.sh`, and preserve executable Bash files. Copy the skill's `scripts/SquadCoordinator.psm1`, `scripts/Resolve-SquadConnectorDispatch.ps1` and `scripts/SquadAgentDiscovery.ps1` into `<targetDir>/hve-squad/runtime/`; these are the dispatch guard's required dependencies.
5. **Report exactly what was written** — the hook file path, each script path, whether local execution was tested, and a note that the drop must be committed before cloud agent can see it. An uncommitted drop can still serve a local CLI session.

## Idempotency

* A top-level `"_generatedBy": "squad-init-hooks"` field is written into `hve-squad.json` so a re-run can recognize its own prior output.
* Re-running without `force` when the marker is present and unchanged is a no-op that reports "already up to date."
* Re-running when the target file exists **without** the marker (a human-authored `.github/hooks/hve-squad.json`, or a differently-named file that happens to collide) refuses to overwrite it and reports the conflict, asking the user to rename one side — the same no-clobber discipline the federation naming rule uses elsewhere in the squad.

## What This Skill Does Not Do

* It does not run `apm install` or seed any roster/profile state.
* It does not enable Watch Mode itself — the two GitHub Actions workflows (`skills/squad/github-approval-watcher.workflow.yml`, `skills/squad/squad-watch.workflow.yml`) are a separate, explicit copy-and-commit step a consumer performs when they want Watch Mode's actual trigger and approval enforcement, not just its hooks-layer backstop.
* It does not touch `.mcp.json` or any MCP server registration.
* It does not replace the agent and reference rules. Hooks are runtime backstops and may be unavailable on a host or version.

## Invocation

Perform this as a direct file-write action — it is a mechanical copy-and-rewrite, not a role dispatch.