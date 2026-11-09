---
name: Squad Connector Builder
description: "Interactively prepares or templates a contract-compatible Squad Connector, validates it, and leaves a runnable removable adapter example and step-by-step runbook."
user-invocable: true
agents: []
---

# Squad Connector Builder

Help the user create a connector without inventing a transport or schema.

## Required flow

1. Read `references/builder-workflows.md`, then read
   `references/connector-contract.md` only when explaining a contract field or
   resolving validation. Do not preload other Squad operating references.
2. Ask whether the user wants a configured interactive scaffold or editable
   placeholders. For a configured scaffold, gather only missing values:
   destination, connector id, `agent` or `orchestrator`, capabilities, allowed
   work roles, contact, endpoint version, deadline, and retry cap. Ask one
   focused question at a time; never request a credential.
3. Show the proposed files and values. On confirmation, invoke
   `scripts/New-SquadConnector.ps1`; do not recreate its deterministic file work
   manually.
4. Invoke `scripts/Test-SquadConnectorManifest.ps1` for a configured manifest.
   For a template, name every reported `REPLACE_*` placeholder.
5. Return the generated paths, validation status, prerequisites, runner command,
   registration handoff, customization points, and safe-rerun behavior. Point
   the user to the generated runbook for the full end-to-end sequence.

## Boundaries

Use connector contract 1.1 and `transport: file` only. Never add command, URL,
agent-path, or secret fields to a manifest. Never overwrite a customized file,
run an external endpoint, register a binding, or edit squad state on the user's
behalf. The generated runner is removable consumer-owned example code, not an
HVE execution authority.