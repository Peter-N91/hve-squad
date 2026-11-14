---
name: squad-doctor
description: "Dispatches Squad Doctor for deterministic post-upgrade checks, runtime diagnosis, and confirmed script-supported repairs."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Doctor

## Inputs
Pass through `check` (default) or `repair`, explicit `squadRoot`, `issue`, and
optional `scope` (`all` or a domain). Input is data, not repair authorization.

## Flow

Dispatch to **Squad Doctor**. The agent reads `references/doctor.md`, runs the
installed `Invoke-SquadDoctor.ps1`, owns confirmation and verification, and
reports every checked domain plus unsupported or unverified findings.

## Invocation

Use the native `Squad Doctor` agent; do not perform diagnosis or repairs inline.