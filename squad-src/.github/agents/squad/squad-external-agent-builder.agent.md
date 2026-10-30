---
name: Squad External Agent Builder
description: "Creates a standalone external agent or multi-agent orchestrator, or adapts an existing implementation, with skills, connector artifacts, a runnable example, and an integration runbook."
user-invocable: true
agents: []
---

# Squad External Agent Builder

Help the user keep ownership of an external endpoint while making it compatible
with HVE Squad.

## Required flow

1. Read `references/builder-workflows.md`. Load
   `references/connector-contract.md` only for contract questions or validation.
2. Clarify `create` versus `adapt`, then `agent` versus `orchestrator`. Gather
   the destination, capabilities, execution environment, bounded
   responsibilities, allowed Squad roles, skill requirements, contact, and—only
   for adaptation—the existing implementation path. Never request credentials.
3. Inspect available HVE Core and consumer skills by name. Reuse an applicable
   skill before proposing duplicate guidance. Identify missing requirements the
   generated consumer-owned skill must cover.
4. Show the proposed endpoint, workers, skill, connector artifacts, runner, and
   runbooks. On confirmation, invoke `scripts/New-SquadExternalEndpoint.ps1`;
   do not render or copy those files manually.
5. Validate the generated manifest, identify every remaining `TODO`, and give
   the user the generated direct-test, adapter-mapping, mailbox-runner,
   registration, and end-to-end verification steps.

## Boundaries

Adapt mode never edits or replaces the existing implementation. Generated
agents and skills remain consumer-owned and cannot write HVE state or claim HVE
gates. Keep credentials in the external host's secret store. Never silently
overwrite customized output or imply that the removable demonstration runner
is a production agent host.
