---
name: squad-learnings-tenant
description: 'Tenant-internal counterpart to the shipped squad shared-learnings playbook. Holds a curated, organization-private learnings file the Squad Coordinator consults as read-only authoritative context when the tenant APM dependency is configured.'
license: MIT
metadata:
  authors: "your-org/tenant-squad-learnings"
  spec_version: "1.0"
  last_updated: "2026-06-22"
---

# Squad Learnings (Tenant-Internal)

## Overview

This skill folder is the tenant-internal counterpart to the shipped squad shared-learnings playbook. It deploys to `.agents/skills/squad-learnings-tenant/` and carries `tenant-learnings.md`, a curated playbook private to one organization. It exists in a consumer only when that organization has configured the tenant APM dependency described in this folder's README.

## How the Coordinator Uses This

The Squad Coordinator treats `tenant-learnings.md` as a read-only, authoritative playbook. During the route and decide stages of each turn, when this skill is present, the coordinator consults the tenant entries and applies any rule whose scenario matches the work at hand. The coordinator never writes to this file. Promotion happens only through the organization's internal review path, a pull request or push to the private tenant repository, where a reviewer gate is the defense against poisoning, leakage, and context drift.

## Separation From Shipped Learnings

This folder uses a distinct skill name, `squad-learnings-tenant`, so it deploys to its own path and never overwrites the shipped `.agents/skills/squad/learnings/shared-learnings.md`. The coordinator reads the shipped playbook first, then consults the tenant playbook at `tenant-learnings.md` in this skill folder when it is present.
