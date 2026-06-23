---
name: squad-shared-learnings
description: 'Curated, human-reviewed shared learnings playbook the Squad Coordinator consults as an authoritative reference during routing and decision-making. Shipped as versioned package content so a learning captured in one consumer reaches every consumer on the next sync.'
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-06-22"
---

# Squad Shared Learnings

This file is the curated, versioned playbook of durable learnings that earlier squad runs surfaced. It ships as package content, so a learning reviewed and merged once reaches every consumer on the next `apm run sync-deps`.

## How the Coordinator Uses This

The Squad Coordinator treats this file as a read-only, authoritative playbook. During the route and decide stages of each turn, the coordinator consults these curated entries and applies any rule whose scenario matches the work at hand. Entries here are not live agent memory: they are maintainer-reviewed rules promoted from sanitized local learnings and shipped as versioned content. The coordinator never writes to this file. Promotion happens only through the fork-and-PR contribution path described in the repository contribution guide, where a maintainer review gate is the defense against poisoning, leakage, and context drift.

## Sanitization Reminder

> [!IMPORTANT]
> Every entry must be sanitized before it ships. Do not include secrets or tokens, customer or organization names, or repo-specific absolute paths. Generalize stack-specific details so the learning applies broadly. When in doubt, leave it out.

## Entry Schema

Each learning occupies one row in the table below. The columns carry the following meaning.

| Field | Description |
| --- | --- |
| `id` | Stable identifier for the entry, unique within this file. |
| Scenario / Trigger | The situation or signal that makes this learning relevant. |
| Learning / Rule | The durable rule to apply, stated as a concrete action. |
| Scope / Applicability | Which stacks or squad profiles the rule applies to. |
| Source Context | Sanitized origin of the learning, with no identifying detail. |
| Date Added | ISO 8601 date (`YYYY-MM-DD`) the entry was curated. |

## Learnings

| id | Scenario / Trigger | Learning / Rule | Scope / Applicability | Source Context | Date Added |
| --- | --- | --- | --- | --- | --- |
| SL-001 | Re-running a scenario whose prior squad run failed code review | Reviewer verdicts are durable history, not auto-gating inputs; before re-dispatching, the coordinator re-reads the prior verdict under `.copilot-tracking/reviews/code-reviews/` so known findings are not silently repeated. | All profiles using the Research, Plan, Implement, Review spine | Squad memory-mechanism review; generalized, no customer or repo specifics | 2026-06-22 |
