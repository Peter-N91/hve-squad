---
description: "Drafts a sanitized, broadly applicable learning from consumer-local squad memory and opens a pull request to promote it, targeting either the public hve-squad package (cross-consumer) or your organization's tenant-internal learnings repository"
argument-hint: "[target=upstream|tenant] [learning=...]"
---

# Squad Learn

Promote a durable learning that one squad run surfaced into a curated, human-reviewed playbook so other projects facing the same scenario benefit. Live agent memory always stays local to this consumer; this command only reads it and prepares a sanitized candidate for a pull request. The reviewer gate on that pull request is the defense against memory poisoning, data leakage, and context drift.

## Inputs

* ${input:target}: (Optional) Where to promote the learning. `upstream` promotes to the public hve-squad package (Scenario B), so the merged learning reaches every consumer on their next sync. `tenant` promotes to your organization's private tenant-internal learnings repository (C1), so the learning flows between the organization's own projects and never leaves the tenant. When omitted, the workflow asks after a candidate is drafted.
* ${input:learning}: (Optional) A specific learning or topic to promote. When omitted, the workflow discovers candidates from consumer-local memory.

## Workflow

### Step 1: Discover candidates

Read consumer-local memory at `/memories/repo/squad-*.md` and squad state under `.copilot-tracking/squad/` (`decisions.md` and the per-agent files under `history/`). Identify durable, broadly applicable learnings: a correction, convention, or routing choice that would help a different project hitting the same scenario. Skip anything one-off or specific to this repository's runtime state.

This step is read-only. Never modify or delete live memory or squad state. When `${input:learning}` is provided, use it to focus discovery; otherwise present the candidates you found and let the user pick one.

### Step 2: Draft and sanitize

Draft a candidate entry that follows the shipped entry schema in `.agents/skills/squad/learnings/shared-learnings.md` (the columns `id`, Scenario / Trigger, Learning / Rule, Scope / Applicability, Source Context, Date Added). Then apply the sanitization checklist and show the redacted draft to the user:

* Remove all secrets, tokens, credentials, and connection strings.
* Remove customer, organization, and individual names.
* Remove repository-specific absolute paths and internal URLs.
* Generalize stack-specific or environment-specific details so the learning applies beyond its origin.
* Confirm the learning is broadly applicable across scenarios. When in doubt, leave it out.

Stop and ask the user to confirm the sanitized text before going further. Never proceed with unsanitized content; if the user cannot confirm sanitization, stop here.

### Step 3: Choose the target

Use `${input:target}` when provided; otherwise ask the user to choose `upstream` or `tenant`. Explain the reach so the choice is informed:

* `upstream`: reaches every consumer of the public package; gated by the maintainer's pull request review.
* `tenant`: stays inside the organization and flows between its own projects; gated by the organization's review rules.

### Step 4: Resolve the repository and target file

* For `upstream`: the public package repository. Derive the slug from the squad dependency entry in this project's `apm.yml` (for example `Peter-N91/hve-squad` from a `…/hve-squad/squad-src/…` line) and confirm it with the user. The target file is `squad-src/.github/skills/squad/learnings/shared-learnings.md`. Consumers have no write access, so promotion is a fork and pull request. Use the `SL-` id prefix and pick the next free number by reading the existing rows.
* For `tenant`: the organization's private tenant-internal repository. Derive the slug from the `squad-learnings-tenant` dependency line in `apm.yml` when present (for example `your-org/tenant-squad-learnings`); otherwise ask the user for it. The target file is `squad-src/.github/skills/squad-learnings-tenant/tenant-learnings.md`. Promotion is a branch and pull request, or a direct push, governed by the organization's review rules. Use the `TL-` id prefix and pick the next free number by reading the existing rows.

### Step 5: Open the pull request

Opening or pushing to a remote repository is an impactful action. Before any network-mutating step (fork, push, or pull request creation), state exactly what will happen and to which repository, and get explicit user approval. Then:

1. Fork or clone the resolved repository, create a branch, append the new row to the target file with the chosen id and today's date in ISO 8601 (`YYYY-MM-DD`), and commit with a clear message.
2. Push the branch and open a pull request. Use the GitHub CLI (`gh`) when it is available and authenticated. When `gh` is unavailable, print the exact `git` and `gh` commands plus the drafted diff so the user can run them.
3. Restate the sanitization checklist in the pull request body so the reviewer can verify it before merging.

### Step 6: Confirm

Report the pull request URL, or the prepared branch and the exact commands when the push was deferred to the user. Remind the user that the reviewer gate on that pull request is the final defense against poisoning, leakage, and context drift, and that consumers receive the merged learning on their next `apm run sync-deps`.

## Guardrails

* Live agent memory is read-only input to this command; it is never modified or deleted.
* Nothing is forked, pushed, or opened without explicit user approval at the impactful-action gate.
* Never include unsanitized content. If sanitization cannot be confirmed, stop.
* The shipped `shared-learnings.md` and any tenant playbook deployed into this consumer are never edited in place; promotion always flows through a pull request to the source repository, where the human review gate governs the merge.
