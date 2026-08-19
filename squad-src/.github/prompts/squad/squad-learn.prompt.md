---
description: "Drafts a sanitized, broadly applicable learning from consumer-local squad memory and opens a pull request to promote it, targeting either the public hve-squad package (cross-consumer) or your organization's tenant-internal learnings repository"
agent: Squad Learn
argument-hint: "[target=upstream|tenant] [learning=...]"
---

# Squad Learn

## Inputs

* ${input:target}: (Optional) Where to promote the learning. `upstream` reaches every consumer of the public hve-squad package on their next sync; `tenant` stays inside your organization's private learnings repository. When omitted, the agent asks after a candidate is drafted.
* ${input:learning}: (Optional) A specific learning or topic to promote. When omitted, the agent discovers candidates from consumer-local memory.

## Requirements

1. Hand this turn to the Squad Learn agent and let its required steps discover candidates, draft and sanitize the entry, resolve the target repository, and prepare the pull request.
2. Pass `${input:target}` and `${input:learning}` through as-is. The agent owns candidate discovery, the sanitization checklist, and the `SL-` versus `TL-` id convention.
3. Let the agent own its guardrails: live agent memory is read-only, nothing is forked, pushed, or opened without explicit user approval at the impactful-action gate, and unsanitized content stops the run.
