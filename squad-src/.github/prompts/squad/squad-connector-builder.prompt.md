---
description: "Starts the Squad Connector Builder to interactively scaffold a validated connector or create editable contract-compatible templates with a removable runner and runbook"
agent: Squad Connector Builder
argument-hint: "[request=...] [mode=interactive|template] [destination=<path>]"
---

# Squad Connector Builder

## Inputs

* `${input:request}` (Optional): What the user wants to connect and any known
  connector values. Continue from conversation context when omitted.
* `${input:mode}` (Optional): `interactive` for a configured scaffold or
  `template` for clearly marked editable placeholders.
* `${input:destination}` (Optional): Repository root to scaffold. Defaults to
  the active workspace after confirmation.

## Requirements

1. Hand the supplied values to Squad Connector Builder without asking again for
   information already present.
2. Let the builder gather missing contract decisions, preview the plan, invoke
   deterministic scripts, validate configured manifests, and report remaining
   placeholders.
3. Do not place credentials in arguments or generated artifacts.
