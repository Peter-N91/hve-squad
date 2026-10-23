---
title: Security model registry
description: Index of scoped STRIDE models for shipped HVE Squad skill scripts.
ms.date: 2026-10-23
---

## Scope

This registry indexes the available per-skill STRIDE models. It does not claim
a completed repository-wide threat assessment. The repository's supported
versions, reporting process, and broader scope remain in the
[security policy](../../SECURITY.md).

## Skill Security Models

| Skill | Model | Classification | Current scope |
|---|---|---|---|
| squad | [Squad Skill Security Model](../../squad-src/.github/skills/squad/SECURITY.md) | Required: parses separately controlled connector results and local input files | Persisted work-role defaults, protected coordinators/Scribe, offline capability evidence, file exchange, persistence, and accounting |

Primary residual gaps are unauthenticated file-drop producers, consumer-owned
runner/replay lifecycle, host-dependent worktree isolation, and filesystem/content
checks that are not performed by the stateless envelope validator alone.
Curated benchmark verification metadata is also an operator-controlled,
unsigned record, not authenticated proof of a measurement or future task quality.
Consult the model's gap register before deploying an unattended integration.
