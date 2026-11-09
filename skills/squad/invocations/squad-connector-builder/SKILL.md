---
name: squad-connector-builder
description: "Starts the Squad Connector Builder to interactively scaffold a validated connector or create editable contract-compatible templates with a removable runner and runbook."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Connector Builder

## Inputs

* **request** (optional): What the user wants to connect and any known connector values.
* **mode** (optional): `interactive` or `template`.
* **destination** (optional): Existing repository root to scaffold.

## Flow

1. Dispatch the supplied values to `Squad Connector Builder`; do not ask again for values already present.
2. Let the builder gather missing decisions, preview the plan, invoke the packaged deterministic scripts, and validate configured manifests.
3. Return its generated paths, placeholders, prerequisites, runner invocation, registration handoff, and safe-rerun guidance. Never pass credentials.

## Invocation

Dispatch this request to the `Squad Connector Builder` agent. The skill does not render files itself.