---
name: {{WORKER_NAME}}
description: "{{DESCRIPTION}}"
user-invocable: false
agents: []
---

# {{WORKER_NAME}}

Load the `{{SKILL_NAME}}` skill and complete this responsibility:

{{RESPONSIBILITY}}

Write only to the output slot supplied by the parent orchestrator. Return the
artifact path, factual status, and blockers. Never write connector envelopes,
HVE squad state, approvals, or gate outcomes.