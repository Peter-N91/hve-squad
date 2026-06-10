# hve-squad

APM package that assembles HVE Core agents, prompts, instructions, and skills into one installable bundle for Copilot target environments.

## What this project does

This repository provides a curated APM package that references content from `microsoft/hve-core` under:

- `.github/agents`
- `.github/instructions`
- `.github/prompts`
- `.github/skills`

Instead of manually maintaining hundreds of dependency paths, this project uses an automation script to regenerate the dependency list in `apm.yml`.

## Why this exists

Maintaining explicit APM dependency links by hand is error-prone because HVE Core evolves frequently.
This package solves that by:

- Auto-discovering all supported markdown artifacts from selected HVE Core folders
- Updating `dependencies.apm` in `apm.yml`
- Providing a repeatable author workflow before lock/pack/publish

## Repository structure

- `apm.yml`: package metadata, dependency list, and scripts
- `apm.lock.yaml`: resolved dependency lock file
- `scripts/Update-ApmDependencies.ps1`: dependency generator
- `squad-src/.github/`: locally authored squad source (agents, prompts, instructions, skills)
- `apm_modules/`: installed dependencies (ignored by git)
- `.github/`: generated/deployed local assets (ignored by git, except `.github/workflows/` if tracked)

## Prerequisites

- PowerShell 7+
- Git
- APM CLI installed and available in `PATH`
- Access to `microsoft/hve-core` repository

## Scripts

Defined in `apm.yml`:

- `sync-deps`
  - Regenerates `dependencies.apm` from HVE Core content.
- `install-sync`
  - Regenerates `dependencies.apm` and runs `apm install`.

## Maintainer workflow (author of this package)

1. Regenerate dependencies:

   ```powershell
   apm run sync-deps
   ```

2. Install dependencies locally:

   ```powershell
   apm install
   ```

   Or:

   ```powershell
   apm run install-sync
   ```

3. Refresh lockfile:

   ```powershell
   apm lock
   ```

4. [OPTIONAL] Build package artifact (only needed to build a plugin):

   ```powershell
   apm pack
   ```

5. [OPTIONAL] Publish (if applicable):

   ```powershell
   apm publish
   ```

Recommended sequence before release:

1. `apm run sync-deps`
2. `apm lock`
3. `apm pack` (optional)

## Consumer workflow (GitHub installs for your package)

This is everything a consumer needs to install the package, run the squad, and rebuild
their deployed assets.

### 1. Install the package

Run `apm install` from the root of the project you want the squad in.

> **Heads-up (APM 0.18.0+).** APM no longer silently defaults to the Copilot harness. In
> a project with no existing `.github/agents/`, `.github/prompts/`, `.github/instructions/`,
> `.claude/`, `.cursor/`, etc., `apm install` will fail with `[x] No harness detected`
> *after* downloading sources into `apm_modules/` but *before* deploying anything into
> `.github/`. You must tell APM which harness to deploy to using one of the options below.

**Option A — pass `--target copilot` on every install (one-off):**

```powershell
apm install "Peter-N91/hve-squad#v0.2.0" --target copilot  # pinned (recommended)
# or
apm install Peter-N91/hve-squad --target copilot           # latest on default branch
```

**Option B — declare the target once in your project's `apm.yml` (persistent, recommended):**

Create an `apm.yml` at the root of your consumer project:

```yaml
name: my-project
version: 0.1.0
targets:
  - copilot
```

Then `apm install "Peter-N91/hve-squad#v0.2.0"` (no flag needed) will deploy to
Copilot from now on. This also makes future `apm install` / `apm update` runs reproducible.

Either way, this deploys the bundled HVE Core agents, prompts, instructions, and skills —
plus the squad — into your project's `.github/` tree. Consumers do **not** need
`sync-deps` or `install-sync`; those are maintainer-only scripts for regenerating the
dependency list.

**If your first install already failed with `No harness detected`:** the sources are
already in `apm_modules/`. Just re-run with `--target copilot` (Option A) or add the
`targets:` block to `apm.yml` (Option B) and re-run `apm install`; APM will re-run the
deploy step and populate `.github/`.

### 2. Run the squad

The squad is a user-invocable Squad Coordinator that routes your request to a cast of
HVE Core agents and persists its state under `.copilot-tracking/squad/`. Invoke it with
the `/squad` prompt in Copilot Chat:

```text
/squad request="add input validation to the login form"
```

Optional inputs:

- `profile=default|full|security|design|architecture` — seeds which cast is created on
  first run. If omitted on a fresh project, the coordinator inspects your repo and
  proposes a recommended profile before creating anything.
- `tier=fast|default` — a per-turn model-tier hint that overrides the coordinator's
  cost-first defaults.

```text
/squad request="threat-model the auth service" profile=security
/squad request="summarize the data layer" tier=fast
```

**First run (Init Mode).** When a project has no `.copilot-tracking/squad/team.md`, the
coordinator proposes a squad profile, waits for your confirmation, then seeds
`team.md`, `routing.md`, `decisions.md`, `state.json`, and a `history/` directory. It
never writes files before you confirm. After that, each `/squad` call routes against the
seeded roster.

**Profiles** (the cast each one seeds):

| Profile        | Members                                            | Use when                                          |
|----------------|----------------------------------------------------|---------------------------------------------------|
| `default`      | lead, researcher, developer, tester, scribe        | General-purpose work; recommended starting point  |
| `full`         | all 10 deployed roles                              | Complex, cross-cutting projects                   |
| `security`     | security, rai, fact-checker, researcher, scribe    | Security, threat-modeling, responsible-AI focus   |
| `design`       | designer, researcher, lead, tester, scribe         | UX/UI and product-design focus                    |
| `architecture` | architect, researcher, lead, developer, scribe     | System design and architecture focus              |

Requirements for running the squad:

- A `runSubagent` or `task` tool must be enabled so the coordinator can dispatch the
  cast.
- The memory tool should be available for durable per-agent notes under `/memories/repo/`.

You can re-cast the squad later by editing `.copilot-tracking/squad/team.md` or asking the
coordinator to switch profiles.

### 3. Rebuild (re-deploy) after updating

To pull a newer version of the package or refresh your deployed assets, re-run install
with the version tag you want (include `--target copilot` if you have not declared
`targets:` in your project's `apm.yml`):

```powershell
apm install "Peter-N91/hve-squad#v0.2.0" --target copilot
```

`apm install` re-flattens the package into `.github/`. Your squad **state** under
`.copilot-tracking/squad/` is created per-project and is never packaged, so re-installing
does not overwrite your roster, routing, decisions, or history.

## How dependency generation works

The generator script:

- Connects to `microsoft/hve-core` at a target ref (default: `main`)
- Enumerates files under:
  - `.github/agents`
  - `.github/instructions`
  - `.github/prompts`
  - `.github/skills`
- Filters for markdown artifacts
- Rewrites only `dependencies.apm` in `apm.yml`

This keeps package metadata stable while updating the dependency list safely.

## Squad source

In addition to the `microsoft/hve-core` dependencies, this package ships a locally authored
"squad" — a Squad Coordinator plus supporting agents, instructions, a prompt, and a skill.
The squad source lives under:

- `squad-src/.github/agents/squad/`
- `squad-src/.github/instructions/squad/`
- `squad-src/.github/prompts/squad/`
- `squad-src/.github/skills/squad/`

### Why the source is separate from the deployed `.github/` tree

`apm install` deploys agents and prompts *flattened* into the consumer's `.github/` tree. If the
squad source lived directly under the top-level `.github/agents/` (or `.github/prompts/`), a later
`apm install` would clobber it. Keeping the authored source under `squad-src/.github/...` places it
outside the deploy flatten zone while preserving the `.github/{agents,prompts,instructions,skills}/`
prefix the deploy mapping expects. Runtime squad *state* is created per-project under
`.copilot-tracking/squad/` and is never packaged.

### How squad entries are generated

`Update-ApmDependencies.ps1` enumerates the squad source from the *local* filesystem (it is not
cloned, because the source lives in this working tree and may not be pushed yet). Squad entries are
emitted as remote virtual paths of the form
`<SquadRepoSlug>/<SquadSourceRoot>/.github/...`, for example
`Peter-N91/hve-squad/squad-src/.github/agents/squad/squad-coordinator.agent.md`. They are appended
after the hve-core entries in `dependencies.apm`.

The sync command accepts two squad-specific parameters:

```powershell
pwsh -File scripts/Update-ApmDependencies.ps1 `
  -SquadSourceRoot squad-src `
  -SquadRepoSlug Peter-N91/hve-squad
```

- `SquadSourceRoot`: local path to the squad source tree (default: `squad-src`). If the path does
  not exist, squad enumeration is skipped without error.
- `SquadRepoSlug`: `owner/repo` that hosts the squad source (default: `Peter-N91/hve-squad`).

Use `-DryRun` to preview both the hve-core and squad entries without writing `apm.yml`.

> Note: `apm lock` and `apm install` can only resolve the squad virtual paths once the
> `squad-src/` tree has been pushed to the `SquadRepoSlug` remote. Until then, `apm.yml` lists the
> squad entries but `apm.lock.yaml` will not record them.

## Customization

You can tune generation behavior in `scripts/Update-ApmDependencies.ps1`:

- `RepoSlug`: source repository
- `Ref`: branch/tag/commit to scan
- `IncludeRoots`: folders included in discovery
- `IncludeRegex`: file filter pattern
- `SquadSourceRoot`: local squad source tree path
- `SquadRepoSlug`: `owner/repo` hosting the squad source

## Troubleshooting

- `[x] No harness detected` after `apm install` (APM 0.18.0+):
  - APM downloaded the sources into `apm_modules/` but skipped the deploy step because
    no harness marker was found in your project (no `.github/agents/`, `.github/prompts/`,
    `.claude/`, `.cursor/`, etc.). Re-run with `--target copilot`:

    ```powershell
    apm install "Peter-N91/hve-squad#v0.2.0" --target copilot
    ```

    Or add a `targets:` block to your project's `apm.yml` so future installs work without
    the flag (see *Consumer workflow \u2192 Install the package, Option B*).
- `apm_modules/` populated but `.github/` is empty and no error visible:
  - Same root cause as above \u2014 scroll up in your terminal for the `No harness detected`
    message and apply the `--target copilot` fix.
- No scripts found:
  - Check the `scripts` block in `apm.yml` and run `apm list`.
- Access failures to HVE Core:
  - Confirm git authentication and repository visibility.
- Dependencies look stale:
  - Run `apm run sync-deps`, then `apm lock`.
- `.github` still appears in git status after ignoring:
  - Run `git rm -r --cached .github` once, then `git add .github/workflows` (if you track workflows here), then commit.

## Versioning

- Releases follow [Semantic Versioning](https://semver.org/).
- See [CHANGELOG.md](CHANGELOG.md) for what is included in each version.
- Consumers can pin to a tagged version, for example `apm install "Peter-N91/hve-squad#v0.2.0"`.

## Release process

Releases use a tag-based flow on top of the default branch (`main`). The tag is the
release artifact consumers install with `apm install "Peter-N91/hve-squad#vX.Y.Z"`.

1. Cut a release branch from `main`:

   ```powershell
   git checkout main
   git pull
   git checkout -b release/vX.Y.Z
   ```

2. Update version metadata:
   - Bump `version:` in `apm.yml` to `X.Y.Z`.
   - Add a `## [X.Y.Z]` section to [CHANGELOG.md](CHANGELOG.md) describing the changes.
   - Refresh the lockfile if dependencies changed: `apm run sync-deps` then `apm lock`.

3. Open a PR into `main` titled `release: vX.Y.Z` (the PR template fills in the checklist).

4. After the PR is merged, tag the merge commit on `main` and push the tag:

   ```powershell
   git checkout main
   git pull
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```

5. (Optional) Publish a GitHub Release for the tag.

Avoid a long-lived `release` branch. Only create `release/vX.Y.z` from an existing
tag when you need to patch an older version after newer work has landed on `main`.

## Notes

- `.gitignore` ignores `apm_modules/`, generated `.github` assets, and keeps `.github/workflows/` tracked.
- The package remains reproducible through `apm.lock.yaml`.
