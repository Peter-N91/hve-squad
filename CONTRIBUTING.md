---
title: Contributing to hve-squad
description: How changes reach the hve-squad package and how to promote a sanitized shared learning through the fork and pull request review gate.
---

## How contributions reach the package

hve-squad gets better when a durable fix found in one environment reaches every other consumer hitting the same scenario. hve-squad ships through APM as one-directional package content: consumers pull the package, and the package never reads from consumer environments. The only route for a change to reach the published package is a fork and pull request against this repository.

1. Fork the repository.
2. Create a branch for your change.
3. Open a pull request against the default branch.
4. A maintainer reviews, requests changes when needed, and merges.

Consumers receive the merged change the next time they run `apm run sync-deps`.

## Proposing a shared learning

A shared learning is a durable, broadly applicable rule or correction discovered while using the squad that should help every other consumer facing the same scenario. Live agent memory always stays local to each consumer and is never promoted automatically. Promotion is a deliberate, human-reviewed pull request.

Curated shared learnings live in `squad-src/.github/skills/squad/learnings/shared-learnings.md` and travel as package content, so a merged learning reaches every consumer on their next sync.

### Sanitize before you propose

Every learning carries the context of where it was found, and that context can contain secrets, customer identities, or details that are wrong outside its origin. Complete this sanitization checklist for every proposed learning:

* [ ] Remove all secrets, tokens, credentials, and connection strings.
* [ ] Remove customer, organization, and individual names.
* [ ] Remove repository-specific absolute paths and internal URLs.
* [ ] Generalize stack-specific or environment-specific details so the learning applies beyond its origin.
* [ ] Confirm the learning is broadly applicable across consumers and scenarios.

### The maintainer review gate

The maintainer pull request review is the defense against the three primary risks of shared learnings:

* Memory poisoning: one incorrect learning would otherwise propagate to every downstream consumer.
* Data leakage: secrets, PII, or intellectual property could cross from one environment into another.
* Context drift: a fix that is correct for one stack can be wrong for a different one.

A maintainer verifies the sanitization checklist, confirms broad applicability, and confirms the entry follows the schema in `shared-learnings.md` before merging. Learnings that are environment-specific are declined or scoped with an explicit applicability note.

### Steps to propose

1. Open a "Propose a shared learning" issue using the template to capture the scenario, the proposed learning, the sanitized source context, and applicability.
2. Add the entry to `squad-src/.github/skills/squad/learnings/shared-learnings.md` following the entry schema in that file.
3. Open a pull request. The pull request template restates the sanitization checklist as items you confirm before review.

### Promoting to a tenant-internal repository

Not every learning belongs in the public package. When a learning is specific to one organization's projects, promote it to a tenant-internal repository instead of upstream. The choice is about reach: a learning that helps every consumer belongs in the upstream package, while a learning that should stay inside one organization belongs in that organization's private tenant-learnings repository.

The sanitization discipline does not change. Complete the [sanitization checklist](#sanitize-before-you-propose) for every entry, then open a pull request against your organization's private tenant-learnings repository rather than this one. The reviewer gate there serves the same purpose the maintainer review serves upstream: the defense against poisoning, leakage, and context drift. See [Shared learnings](docs/templates/shared-learnings.md) for the tenant-internal private-dependency mechanism and the `squad-learnings-tenant` scaffold.

The `/squad-learn` command automates this promotion. It drafts a sanitized candidate from consumer-local squad memory, lets you choose the target (the upstream package or your organization's tenant-internal repository), and opens the pull request, with a human approving that pull request in both cases.
