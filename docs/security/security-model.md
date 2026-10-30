---
title: Security model registry
description: Index of scoped STRIDE models for shipped HVE Squad skill scripts.
ms.date: 2026-10-28
---

## Scope

This registry indexes the available per-skill STRIDE models. It does not claim
a completed repository-wide threat assessment. The repository's supported
versions, reporting process, and broader scope remain in the
[security policy](../../SECURITY.md).

## Skill Security Models

| Skill | Model | Classification | Current scope |
|---|---|---|---|
| squad | [Squad Skill Security Model](../../squad-src/.github/skills/squad/SECURITY.md) | Required: parses separately controlled connector results, local input files, lifecycle/roster/verdict plans, host usage logs, and persisted exact-session snapshots | Persisted work-role defaults, protected coordinators/Scribe, host-bounded actual-unit model routing, hash-bound verdict/roster/federation transactions, cumulative exact per-role native token/credit accounting with unique APM/plugin agent-name canonicalization, digest-bound legacy empty-coverage migration, promotion journal preservation, bounded active-tail bootstrap and completed-session refresh, history-prefix and identity deduplication, file exchange, and persistence |

Primary residual gaps are unauthenticated file-drop producers, consumer-owned
runner/replay lifecycle, host-dependent worktree isolation, and filesystem/content
checks that are not performed by the stateless envelope validator alone.
Model-routing preparation applies the existing hash-bound writer transaction;
native dispatch still depends on host capabilities and coordinator compliance.
Plugin guards compare active cells but cannot enforce an unpersisted routing intent.
Curated benchmark verification metadata is also an operator-controlled,
unsigned record, not authenticated proof of a measurement or future task quality.
Consult the model's gap register before deploying an unattended integration.
