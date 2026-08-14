# Change fragments

Every pull request that changes package behavior adds **one new file** to `.changes/unreleased/`. Nobody edits `CHANGELOG.md` and nobody bumps `version:` in `apm.yml` — those are release outputs, produced on `main` from the fragments collected here.

This exists for one reason: a version line and a changelog heading are single-line shared state, so two concurrent pull requests always conflict on them. A fragment is a brand-new file with a unique name, so two concurrent pull requests never do.

## Create one

```powershell
pwsh -File scripts/New-ChangeFragment.ps1
```

The script asks for the change type, the release impact, a short title, and the entry text, then writes the file and prints its path. Pass `-Type`, `-Bump`, `-Title`, and `-Body` to skip the prompts.

## Format

`.changes/unreleased/20260804-backlog-executor.md`

```markdown
---
bump: minor
type: Added
---

- **The squad could plan an ADO or Jira backlog but never write it.** A new `Squad Backlog Executor`
  charter previews every create, update, and link read-only, stops at the Impactful-Action Gate, and
  only then writes (`squad-src/.github/agents/squad/squad-backlog-executor.agent.md`).
```

### `bump`

Selects how the version moves. When several fragments are pending, the **highest** wins.

The level tracks **ideas, not artifacts**. A minor is reserved for a capability class that did not exist before; everything built underneath an idea that already shipped is a patch, no matter how many files it adds.

| Value   | Use when                                                                                      | In this repo                                                        |
|---------|-----------------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `major` | A consumer must change something to keep working.                                              | Not used yet.                                                        |
| `minor` | A genuinely new idea, or a change that materially changes how the package is used.              | `0.10.0` introduced federation. `0.11.0` reworked hve-core attachment. |
| `patch` | Everything else &mdash; **including new agents, skills, prompts, instructions, and roles that extend an idea that already shipped**. | A new squad role under federation. A new OWASP skill. A wording fix.  |

Adding an agent is not a minor. Adding the *concept* the agent belongs to is. When in doubt, choose `patch` &mdash; the maintainer can raise the level at merge time or at release time, and raising is cheap while an accidental minor is permanent.

### `type`

The Keep a Changelog section the entry lands in: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, or `Security`.

### Body

Markdown bullets, written the way they should read in the changelog — the release step copies them verbatim under the matching heading. Start each bullet with `- `. Lead with a bold sentence naming the problem, then explain what changed and cite the file paths in backticks.

One fragment per idea. A pull request that does two unrelated things adds two fragments.

## What happens at release

Merging a pull request that carries a fragment does not release it. The fragment lands in `.changes/unreleased/` and waits there with everything else merged that week.

Two workflows read that directory:

**Rolling Preview** runs on every merge to `main`. It renders the pending fragments into a single GitHub pre-release, named for the version they currently resolve to, and force-moves that pre-release's tag to the new head. Nothing is consumed and no file is written — the preview only reads. The result is one installable ref that always reflects what `main` currently adds up to:

```powershell
apm install "Peter-N91/hve-squad#v0.14.0-pre"
```

**Release Prep** runs only when a maintainer dispatches it. It reads every pending fragment, resolves the new version from the highest `bump`, groups the bodies by `type`, prepends the assembled section to `CHANGELOG.md` with the standard consumer-install block and link reference, writes the new `version:` into `apm.yml`, deletes the fragments it consumed, cuts the tag and GitHub Release, and retires the pre-release. Nothing releases on a timer.

Releasing is therefore a decision about readiness, not a date. A quick fix can ship as soon as it is verified in the preview; a larger change can sit in preview for as long as it needs. Whatever is pending when the workflow is dispatched goes out together, as one version, at the highest `bump` any pending fragment asked for. The pull request is still where a wrong `bump` gets corrected — the PR check reports the version the batch currently resolves to, and the maintainer can edit the `bump:` line directly in the pull request. `-Bump` and `-Version` overrides on `Invoke-ReleasePrep.ps1` remain for batches assembled by hand.

`.changes/unreleased/` is empty from a release until the next merge. That is the expected steady state.
