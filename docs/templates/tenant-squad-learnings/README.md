---
title: Tenant-internal squad learnings scaffold
description: Copyable scaffold and runbook for hosting a private tenant-internal squad learnings playbook as a versioned APM dependency.
---

## Overview

A copyable scaffold an organization drops into a private repository to share durable squad learnings across its own projects without publishing them to the public package. It reuses the same APM pull model the squad already uses to reference itself.

Live agent memory always stays local to each consumer. This scaffold adds a second read-only surface: a curated, organization-private playbook the Squad Coordinator consults when present and never writes to.

## What this scaffold contains

```text
tenant-squad-learnings/
  README.md                                       this runbook
  squad-src/.github/skills/squad-learnings-tenant/
    SKILL.md                                      minimal skill manifest
    tenant-learnings.md                           curated tenant playbook
```

## Why a separate skill folder

APM deploys a folder skill reference to `.agents/skills/<name>/`. The shipped squad skill deploys to `.agents/skills/squad/`, with its curated playbook at `.agents/skills/squad/learnings/shared-learnings.md`. A tenant file named `shared-learnings.md` placed under the squad skill would deploy to that same path and overwrite the shipped one, because APM resolves colliding paths last-one-wins.

This scaffold avoids the collision by shipping a separate skill folder named `squad-learnings-tenant`. It deploys to `.agents/skills/squad-learnings-tenant/tenant-learnings.md`, a distinct path that never overwrites shipped content. The Squad Coordinator reads it as read-only context when the dependency is configured.

## Runbook

Follow these steps once per organization, then add the dependency to each consuming project.

### 1. Create the private repository

Create a private git repository in your organization, either a private GitHub repository or an Azure DevOps repository. APM delegates authentication to the git CLI, so each consumer needs git credentials for this repository.

### 2. Copy the scaffold

Copy the `squad-src/` tree from this folder into the root of your private repository, keeping the `squad-src/.github/skills/squad-learnings-tenant/` path intact. Adjust the `authors` and `license` fields in `SKILL.md` and `tenant-learnings.md` to match your organization.

### 3. Curate the playbook

Edit `tenant-learnings.md`. Replace the seed row with your organization's durable learnings, one row per learning, following the entry schema in that file. Sanitize every entry before you commit it.

### 4. Tag an immutable release

Commit your changes and tag a release so consumers pin to an immutable version.

```bash
git tag v1.0.0
git push origin v1.0.0
```

The tag pin is the poisoning defense. A consumer moves to new learnings only when it deliberately bumps the tag and re-runs sync.

### 5. Add the APM dependency line

In each consuming project's `apm.yml`, add the tenant skill folder as a dependency, pinned to your tag. The squad already references its own content the same way, so add one more entry beside it.

```yaml
dependencies:
  apm:
    - Peter-N91/hve-squad/squad-src/.github/skills/squad
    - your-org/tenant-squad-learnings/squad-src/.github/skills/squad-learnings-tenant#v1.0.0
```

Replace `your-org/tenant-squad-learnings` with your private repository and `v1.0.0` with the tag you want to consume. The reference points at the `squad-learnings-tenant` folder with no file extension, so APM deploys the whole skill folder.

### 6. Deploy

Run `apm run sync-deps`, then the APM install step your project uses. The tenant playbook materializes at `.agents/skills/squad-learnings-tenant/tenant-learnings.md`, and the Squad Coordinator consults it as read-only context on its next run.

## Updating

Learnings are not live. To publish a change, edit `tenant-learnings.md`, bump the tag, and have each consumer update the pinned tag and re-run sync. Write-back is a pull request or push to the private repository, governed by your organization's review rules.
