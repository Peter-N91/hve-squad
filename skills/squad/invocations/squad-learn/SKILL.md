---
name: squad-learn
description: "Drafts a sanitized learning from consumer-local squad memory and opens a pull request to promote it upstream or to a tenant learnings repo. Use when the user asks to promote, share, or upstream a learning the squad captured."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Learn

## Inputs

* **target** (optional): Where to promote the learning. `upstream` reaches every consumer of the public hve-squad package on their next sync; `tenant` stays inside your organization's private learnings repository. When omitted, the agent asks after a candidate is drafted.
* **learning** (optional): A specific learning or topic to promote. When omitted, the agent discovers candidates from consumer-local memory.

## Flow

1. Hand this turn to the Squad Learn agent and let its required steps discover candidates, draft and sanitize the entry, resolve the target repository, and prepare the pull request.
2. Pass **target** and **learning** through as-is. The agent owns candidate discovery, the sanitization checklist, and the `SL-` versus `TL-` id convention.
3. Let the agent own its guardrails: live agent memory is read-only, nothing is forked, pushed, or opened without explicit user approval at the impactful-action gate, and unsanitized content stops the run.

## Invocation

Dispatch this request to the `Squad Learn` agent. This skill does not perform discovery or draft the PR itself — it only resolves which parameters to pass.