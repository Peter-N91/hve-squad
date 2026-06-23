---
title: Shared learnings
description: Two governed options for sharing durable squad learnings: the cross-consumer package path and the tenant-internal private dependency path.
---

## Overview

A shared learning is a durable, broadly applicable rule discovered while using the squad that helps other projects facing the same scenario. Live agent memory always stays local to each consumer. Sharing happens only through a curated, human-reviewed channel. Two options exist, and the right one depends on how far the learning should travel.

## Option 1: Cross-consumer package learnings (Scenario B)

Use this option when a learning is generally useful to every consumer of hve-squad.

Curated learnings ship as package content in `squad-src/.github/skills/squad/learnings/shared-learnings.md`. To promote a learning, sanitize it and open a fork and pull request as described in [Contributing](../../CONTRIBUTING.md). The maintainer review on that pull request is the gate against memory poisoning, data leakage, and context drift. A merged learning reaches every consumer on their next `apm run sync-deps`.

## Option 2: Tenant-internal shared learnings (Scenario C1)

Use this option when learnings should stay inside one organization and flow between that organization's own projects, never reaching the public package.

The mechanism reuses the APM pull model the squad already uses to reference itself. One private internal repository holds a curated learnings skill folder named `squad-learnings-tenant`. Every project in the tenant declares that folder as an APM dependency and pulls it with `apm run sync-deps`. Data never leaves the tenant.

A copyable scaffold for the private repository lives at [docs/templates/tenant-squad-learnings/](tenant-squad-learnings/README.md). Copy its `squad-src/` tree into your private repository, curate the playbook, and tag a release. The scaffold's README is the step-by-step runbook.

### Requirements

* A private git repository in the organization (private GitHub repository or Azure DevOps repository).
* Git credential authentication on each consumer. APM delegates authentication to the git CLI and has no separate auth layer.
* A tagged release on the shared repository so consumers pin to an immutable version.

### Worked apm.yml example

The squad already references its own content through an APM dependency entry. The tenant-internal learnings folder follows the same shape, with one addition: an immutable tag pin.

The existing squad self-reference in apm.yml looks like this:

```yaml
dependencies:
  apm:
    - Peter-N91/hve-squad/squad-src/.github/skills/squad
```

Add the `squad-learnings-tenant` folder as another dependency, pinned to a tag:

```yaml
dependencies:
  apm:
    - Peter-N91/hve-squad/squad-src/.github/skills/squad
    - your-org/tenant-squad-learnings/squad-src/.github/skills/squad-learnings-tenant#v1.0.0
```

Replace `your-org/tenant-squad-learnings` with your private repository and `v1.0.0` with the tag you want to consume. The reference points at the `squad-learnings-tenant` folder with no file extension, so APM deploys the whole skill folder to `.agents/skills/squad-learnings-tenant/`.

### Why a separate skill folder

APM deploys a folder skill reference to `.agents/skills/<name>/`. The shipped squad skill deploys to `.agents/skills/squad/`, with its curated playbook at `.agents/skills/squad/learnings/shared-learnings.md`. A tenant file named `shared-learnings.md` placed under the squad skill would deploy to that same path and overwrite the shipped one, because APM resolves colliding paths last-one-wins. The `squad-learnings-tenant` folder avoids the collision: it deploys to `.agents/skills/squad-learnings-tenant/tenant-learnings.md`, a distinct path that never overwrites shipped content.

### How the coordinator reads it

The Squad Coordinator reads the shipped playbook first, then consults the tenant playbook at `.agents/skills/squad-learnings-tenant/tenant-learnings.md` when that skill folder is present. The tenant surface is read-only: the coordinator applies any rule whose scenario matches the work at hand and never writes back. The folder exists in a consumer only when the organization has configured the tenant dependency, so a project without it simply skips the extra read.

### Why pin to an immutable tag

The `#v1.0.0` tag pin is the poisoning defense. A consumer moves to a new set of learnings only when it deliberately bumps the tag and re-runs `apm run sync-deps`. An unreviewed or incorrect change to the shared repository cannot silently reach consumers, because nothing follows a moving branch.

### Tradeoffs

* Updates are not live. A consumer receives new learnings only when it bumps the tag and re-runs sync.
* Write-back is a pull request or push to the internal repository, governed by the organization's review rules.
* There is no semantic search. The file is a flat, curated list.

## Choosing between the options

Start with the option that matches the learning's reach. A learning that helps everyone belongs in the cross-consumer package. A learning specific to one organization's projects belongs in a tenant-internal repository. Both keep per-project local memory as the substrate and require a sanitization step before anything is shared.
