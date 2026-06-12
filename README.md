<p align="center">
  <img src="docs/assets/logo.svg" alt="hve-squad logo" width="120" height="120" />
</p>

<h1 align="center">hve-squad</h1>

<p align="center">
  APM package that assembles HVE Core agents, prompts, instructions, and skills into one
  installable bundle for Copilot target environments, and ships a Squad Coordinator that routes
  your request to a cast of agents in parallel.
</p>

## Documentation

Full documentation lives on the project site:

**[peter-n91.github.io/hve-squad](https://peter-n91.github.io/hve-squad/)**

| Page                                                                          | What it covers                                                           |
|-------------------------------------------------------------------------------|--------------------------------------------------------------------------|
| [Getting Started](https://peter-n91.github.io/hve-squad/getting-started.html) | Prerequisites, installing the package with the correct target, first run |
| [Usage](https://peter-n91.github.io/hve-squad/usage.html)                     | Profiles, autonomy modes, remote approval, and first-run Init Mode       |
| [Maintaining](https://peter-n91.github.io/hve-squad/maintaining.html)         | Dependency generation, author workflow, customization, release process   |
| [Troubleshooting](https://peter-n91.github.io/hve-squad/troubleshooting.html) | Known install errors with fixes, versioning, and repository notes        |

The site source is in [docs/](docs/) and is published to GitHub Pages by
[.github/workflows/docs.yml](.github/workflows/docs.yml) on every push to `main` that touches
`docs/`.

## Quick start

Install the package into the project you want the squad in, then invoke `/squad` in Copilot Chat:

```powershell
apm install "Peter-N91/hve-squad#v0.4.1" --target copilot
```

```text
/squad request="add input validation to the login form"
```

See [Getting Started](https://peter-n91.github.io/hve-squad/getting-started.html) for the full flow.

## Repository structure

- `apm.yml`: package metadata, dependency list, and scripts
- `apm.lock.yaml`: resolved dependency lock file
- `scripts/Update-ApmDependencies.ps1`: dependency generator
- `squad-src/.github/`: locally authored squad source (agents, prompts, instructions, skills)
- `docs/`: documentation site published to GitHub Pages
- `apm_modules/`: installed dependencies (ignored by git)
- `.github/`: generated/deployed local assets (ignored by git, except `.github/workflows/`)

## Versioning

- Releases follow [Semantic Versioning](https://semver.org/).
- See [CHANGELOG.md](CHANGELOG.md) for what is included in each version.
- Consumers can pin to a tagged version, for example `apm install "Peter-N91/hve-squad#vX.Y.z"`.
