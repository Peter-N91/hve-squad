---
name: squad-external-agent-builder
description: "Starts the Squad External Agent Builder to create a standalone agent or multi-agent orchestrator, or adapt an existing implementation, for HVE Squad interoperability."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad External Agent Builder

## Inputs

* **request** (optional): Capabilities, environment, responsibilities, skills, and known integration details.
* **action** (optional): `create` or `adapt`.
* **kind** (optional): `agent` or `orchestrator`.
* **destination** (optional): Existing repository root to scaffold.

## Flow

1. Dispatch supplied values to `Squad External Agent Builder` and ask only for missing decisions.
2. Let the builder reuse suitable skills, preserve an adapted implementation, preview the plan, and invoke deterministic scaffolding and validation.
3. Return generated paths, TODOs, direct-test and adapter steps, and the end-to-end runbook. Never pass credentials.

## Invocation

Dispatch this request to the `Squad External Agent Builder` agent. The skill does not render files itself.