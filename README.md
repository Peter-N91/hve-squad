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

Consumers should run:

```powershell
apm install "Peter-N91/hve-squad#v0.1.0"  # pinned (recommended); update the version tag to the one you need
# or
apm install Peter-N91/hve-squad          # latest on default branch
```

They do not need to run `install-sync` unless they are maintaining this package source itself.

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

## Customization

You can tune generation behavior in `scripts/Update-ApmDependencies.ps1`:

- `RepoSlug`: source repository
- `Ref`: branch/tag/commit to scan
- `IncludeRoots`: folders included in discovery
- `IncludeRegex`: file filter pattern

## Troubleshooting

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
- Consumers can pin to a tagged version, for example `apm install "Peter-N91/hve-squad#v0.1.0"`.

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
