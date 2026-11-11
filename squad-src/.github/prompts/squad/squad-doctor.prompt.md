---
description: "Check Squad after an upgrade or diagnose a runtime failure with deterministic, confirmed repairs."
agent: Squad Doctor
argument-hint: "[check|repair] [squadRoot=<path>] [issue=<failure>] [scope=<domain>]"
---

# Squad Doctor

Pass the user's check or repair request, explicit squad root, issue, and optional
domain scope to Squad Doctor. Default to read-only checks. Repair confirmation
and script execution belong to the agent; this prompt grants no write approval.
