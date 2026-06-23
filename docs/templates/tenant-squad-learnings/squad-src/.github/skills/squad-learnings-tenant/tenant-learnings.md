---
name: squad-tenant-learnings
description: 'Curated, human-reviewed tenant-internal learnings playbook the Squad Coordinator consults as an authoritative reference during routing and decision-making. Shipped as a private, versioned APM dependency so a learning curated in one tenant project reaches the other tenant projects on the next sync.'
license: MIT
metadata:
  authors: "your-org/tenant-squad-learnings"
  spec_version: "1.0"
  last_updated: "2026-06-22"
---

# Squad Tenant-Internal Learnings

This file is the curated, versioned playbook of durable learnings private to one organization. It ships as a private APM dependency, so a learning reviewed and merged once reaches every project in the tenant on the next `apm run sync-deps`.

## How the Coordinator Uses This

The Squad Coordinator treats this file as a read-only, authoritative playbook. During the route and decide stages of each turn, the coordinator consults these curated entries and applies any rule whose scenario matches the work at hand. Entries here are not live agent memory: they are reviewer-approved rules promoted from sanitized local learnings and shipped as versioned tenant content. The coordinator never writes to this file. Promotion happens only through the organization's internal review path, a pull request or push to the private tenant repository, where a reviewer gate is the defense against poisoning, leakage, and context drift.

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
| TL-001 | A tenant project asks the squad to provision infrastructure into the organization's shared landing zone | Route landing-zone changes through the platform team's approved infrastructure module set instead of authoring net-new resources; the coordinator flags any net-new resource for platform-team review before planning. | Profiles deploying into the organization's shared cloud landing zone | Internal platform-engineering retrospective; generalized, no project, subscription, or tenant identifiers | 2026-06-22 |
