---
name: {{ENDPOINT_NAME}}
description: "{{DESCRIPTION}}"
user-invocable: true
agents:
{{AGENTS}}
---

# {{ENDPOINT_NAME}}

Coordinate the consumer-owned workers below for one bounded connector request.
Preserve their execution boundaries and map every final artifact to a declared
`allowedOutputs[].outputId`.

## Responsibilities

{{RESPONSIBILITIES}}

## Contract

1. Validate the deadline, worker availability, skills, and output slots first.
2. Dispatch only the workers required for the bounded request.
3. Keep write scopes non-overlapping and stop on a worker failure.
4. Return one aggregate status and output mapping to the adapter.
5. Do not write HVE squad state or claim HVE gates, approvals, or verification.
