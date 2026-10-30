---
description: "Starts the Squad External Agent Builder to create a standalone agent or multi-agent orchestrator, or adapt an existing implementation, for HVE Squad interoperability"
agent: Squad External Agent Builder
argument-hint: "[request=...] [action=create|adapt] [kind=agent|orchestrator] [destination=<path>]"
---

# Squad External Agent Builder

## Inputs

* `${input:request}` (Optional): Intended capabilities, environment,
  responsibilities, skills, and known integration details.
* `${input:action}` (Optional): `create` a consumer-owned endpoint or `adapt` an
  existing one without replacing it.
* `${input:kind}` (Optional): `agent` or `orchestrator`.
* `${input:destination}` (Optional): Repository root to scaffold. Defaults to
  the active workspace after confirmation.

## Requirements

1. Hand supplied values to Squad External Agent Builder and ask only for
   missing decisions.
2. Let the builder reuse suitable installed skills, preview the output, invoke
   deterministic scaffolding, validate the connector, and report TODOs.
3. Preserve consumer execution boundaries and never pass credentials.
