---
title: Contributing to hve-squad
description: How changes reach the hve-squad package and how to promote a sanitized shared learning through the fork and pull request review gate.
---

## How contributions reach the package

hve-squad gets better when a durable fix found in one environment reaches every other consumer hitting the same scenario. hve-squad ships through APM as one-directional package content: consumers pull the package, and the package never reads from consumer environments. The only route for a change to reach the published package is a fork and pull request against this repository.

1. Fork the repository.
2. Create a branch for your change.
3. Add a change fragment describing what you changed (see [Recording your change](#recording-your-change)).
4. Open a pull request against the default branch.
5. A maintainer reviews, requests changes when needed, and merges.

Consumers receive the merged change the next time they run `apm run sync-deps`.

## Recording your change

Do not edit `CHANGELOG.md` and do not bump `version:` in `apm.yml`. Both are release outputs, assembled on the default branch when a release is cut. A pull request that edits either one is rejected by CI.

The reason is mechanical. A version line is a single line and the newest changelog heading is a single position, so two pull requests that both touch them always conflict, and the second one to merge silently reuses a version number the first already claimed. Instead every pull request adds **one new file** under `.changes/unreleased/`. Two pull requests adding two differently named files never conflict.

Create yours with:

```powershell
apm run change
```

The script asks four things and writes the file for you:

* **Type** — the Keep a Changelog section your entry belongs to: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, or `Security`.
* **Bump** — how the version should move. This tracks **ideas, not artifacts**, so most changes are `patch`.
* **Title** — a short phrase, used only to name the file.
* **Entry** — the changelog text itself, written the way it should read in the release notes.

### Choosing the bump

| Value   | Use when | In this repo |
|---------|----------|--------------|
| `major` | A consumer must change something to keep working. | Not used yet. |
| `minor` | A genuinely new idea, or a change that materially changes how the package is used. | `0.10.0` introduced federation. `0.11.0` reworked hve-core attachment. |
| `patch` | Everything else, **including new agents, skills, prompts, instructions, and roles that extend an idea that already shipped**. | A new squad role under federation. A new OWASP skill. A wording fix. |

Adding an agent is not a minor. Adding the *concept* the agent belongs to is. Ten agents that all serve one idea that already ships are ten patches, not ten minors. When in doubt choose `patch` — the maintainer sees the resolved level on the pull request check and corrects the line before merging, and raising is cheap while an accidental minor is permanent.

Merging your pull request releases it: the fragment landing on the default branch is what assembles the CHANGELOG section, bumps the version, and cuts the tag.

If you prefer to skip the prompts, pass the values directly:

```powershell
pwsh -File scripts/New-ChangeFragment.ps1 -Type Fixed -Bump patch `
  -Title 'roster row resolves to nothing' `
  -Body '- **A roster Primary pointed at an agent hve-core no longer ships.** Repointed it ...'
```

Either way you get a file like `.changes/unreleased/20260804-roster-row-resolves-to-nothing.md`:

```markdown
---
bump: patch
type: Fixed
---

- **A roster Primary pointed at an agent hve-core no longer ships.** Repointed it to ...
```

Write the entry as markdown bullets starting with `- `, because the release step copies them verbatim. Lead with a bold sentence naming the problem, then say what changed, then cite the file paths in backticks. Commit the fragment with the rest of your change. One fragment per idea — a pull request doing two unrelated things adds two fragments.

A pull request that changes nothing a consumer would notice can carry the `skip-changelog` label instead, which a maintainer applies. That skips the version bump too: the version is resolved from fragments at release time, so a pull request that contributes no fragment contributes no bump.

## Adding an agent, skill, prompt, or instruction

New squad content lives under `squad-src/.github/{agents,skills,prompts,instructions}/`, and `apm.yml` carries a generated list of every file the package ships. After adding your files, regenerate that list:

```powershell
apm run sync-deps
```

That rewrites `dependencies:` in `apm.yml` to include your new files, and commits are expected to contain it. It deliberately does **not** move the `microsoft/hve-core` pin: with no `-Ref`, the script stays on whatever SHA `apm.yml` already names. Moving that pin re-points the entire package at a different upstream revision, which is a separate reviewed operation owned by the scheduled sync workflow, and CI rejects a pull request that does it.

The full format reference lives in [.changes/README.md](.changes/README.md).

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
3. Run `apm run change` to record the learning as a change fragment.
4. Open a pull request. The pull request template restates the sanitization checklist as items you confirm before review.

### Promoting to a tenant-internal repository

Not every learning belongs in the public package. When a learning is specific to one organization's projects, promote it to a tenant-internal repository instead of upstream. The choice is about reach: a learning that helps every consumer belongs in the upstream package, while a learning that should stay inside one organization belongs in that organization's private tenant-learnings repository.

The sanitization discipline does not change. Complete the [sanitization checklist](#sanitize-before-you-propose) for every entry, then open a pull request against your organization's private tenant-learnings repository rather than this one. The reviewer gate there serves the same purpose the maintainer review serves upstream: the defense against poisoning, leakage, and context drift. See [Shared learnings](docs/templates/shared-learnings.md) for the tenant-internal private-dependency mechanism and the `squad-learnings-tenant` scaffold.

The `/squad-learn` command automates this promotion. It drafts a sanitized candidate from consumer-local squad memory, lets you choose the target (the upstream package or your organization's tenant-internal repository), and opens the pull request, with a human approving that pull request in both cases.
