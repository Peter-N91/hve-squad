---
name: squad-coach
description: "Helps a user open the advisory Squad Coach for source-grounded HVE Squad guidance and a detailed runbook. Use for onboarding or questions about how to achieve a goal with the installed Squad version."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Coach

## Input

* **request** (optional): The user's goal, question, or changed demand. Continue from conversation context when it is omitted.
* **host** (optional): `vscode`, `cli`, or `app` when the active host is unclear.

## Flow

1. Tell the user to select the `Squad Coach` agent manually: the agents dropdown in VS Code, `/agent` in Copilot CLI, or the agent picker in Copilot App.
2. Provide their request as a prefix-free, copy-ready message for that conversation, preserving any supplied host hint. Keep selection instructions outside the message.
3. Stop at this handoff. The Coach reads current code and documentation and returns advice without initializing, dispatching delivery work, or changing state.

## Invocation

Do not dispatch `Squad Coach`: it is a user-only agent (`disable-model-invocation: true`). This skill prepares a manual handoff; it neither impersonates the Coach nor applies its recommendations.