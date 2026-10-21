---
description: "Starts a read-only Squad Coach conversation that reads current code and documentation and turns a plain-language goal into a preparation checklist and detailed, host-correct runbook"
agent: Squad Coach
argument-hint: "[request=...] [host=vscode|cli|app]"
---

# Squad Coach

## Inputs

* `${input:request}` (Optional): The user's goal, question, or changed demand. When omitted, infer it from the conversation or ask what outcome they want.
* `${input:host}` (Optional): The user-facing host (`vscode`, `cli`, or `app`) when it is not evident from the session.

## Requirements

1. Hand `${input:request}` and `${input:host}` to the Squad Coach when provided; otherwise let it continue from the conversation.
2. Let the Coach inspect the installed package and any existing squad or federation state read-only so its recommendation matches the shipped version.
3. Return source-grounded advice, preparation checklists, and a detailed runbook with copy-ready messages only. Do not initialize a squad, dispatch work, change configuration, or migrate state from this prompt.
