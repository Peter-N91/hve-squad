<p align="center">
  <img src="docs/assets/logo.svg" alt="hve-squad logo" width="120" height="120" />
</p>

<h1 align="center">hve-squad</h1>

<p align="center">
  APM package that assembles HVE Core agents, prompts, instructions, and skills into one
  installable bundle for Copilot target environments, and ships a Squad Coordinator that routes
  your request to a cast of agents in parallel.
</p>

<!-- markdownlint-disable MD013 MD033 -->
<p align="center">
  <a href="https://github.com/Peter-N91/hve-squad/actions/workflows/pr-validation.yml"><img src="https://github.com/Peter-N91/hve-squad/actions/workflows/pr-validation.yml/badge.svg" alt="PR Validation" /></a>
  <a href="https://github.com/Peter-N91/hve-squad/actions/workflows/codeql.yml"><img src="https://github.com/Peter-N91/hve-squad/actions/workflows/codeql.yml/badge.svg" alt="CodeQL" /></a>
  <a href="https://github.com/Peter-N91/hve-squad/actions/workflows/zizmor.yml"><img src="https://github.com/Peter-N91/hve-squad/actions/workflows/zizmor.yml/badge.svg" alt="Zizmor" /></a>
  <a href="https://github.com/Peter-N91/hve-squad/actions/workflows/checkov.yml"><img src="https://github.com/Peter-N91/hve-squad/actions/workflows/checkov.yml/badge.svg" alt="Checkov" /></a>
  <br />
  <a href="https://scorecard.dev/viewer/?uri=github.com/Peter-N91/hve-squad"><img src="https://api.scorecard.dev/projects/github.com/Peter-N91/hve-squad/badge" alt="OpenSSF Scorecard" /></a>
  <a href="https://www.bestpractices.dev/projects/14231"><img src="https://www.bestpractices.dev/projects/14231/badge" alt="OpenSSF Best Practices" /></a>
  <a href="https://github.com/Peter-N91/hve-squad/releases/latest"><img src="https://img.shields.io/github/v/release/Peter-N91/hve-squad?sort=semver" alt="Latest release" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/github/license/Peter-N91/hve-squad" alt="License" /></a>
  <a href="https://peter-n91.github.io/hve-squad/"><img src="https://img.shields.io/badge/docs-peter--n91.github.io%2Fhve--squad-blue" alt="Documentation" /></a>
</p>
<!-- markdownlint-enable MD013 MD033 -->

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
apm install "Peter-N91/hve-squad#vX.Y.z" --target copilot
```

```text
/squad request="add input validation to the login form"
```

The `/` picker lists two entries named `squad`: pick the **prompt** ("Hands a request to the Squad
Coordinator...") to run the squad. The **skill** ("Operating procedure for...") only loads the squad
procedure as context and is normally loaded by the coordinator itself.

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

Releases are cut by hand, when the pending work is judged ready rather than on a schedule.
Between releases, everything already merged is installable from a rolling pre-release tagged
with the version it is going to become:

```powershell
apm install "Peter-N91/hve-squad#vX.Y.z-pre" --target copilot
```

That tag moves on every merge, so re-run the command to pick up the newest build. Use it
to try a fix before it ships; pin a released version for anything you depend on.

## Security

Every change to `main` runs CodeQL, Checkov, Zizmor, OpenSSF Scorecard, and a
three-tier conformance suite over the shipped agent assets. Third-party GitHub
Actions are pinned to full commit SHAs and workflows run with least-privilege
tokens.

To report a vulnerability, use
[private security advisories](https://github.com/Peter-N91/hve-squad/security/advisories/new)
rather than a public issue. See [SECURITY.md](SECURITY.md) for the threat model,
scope, and response times.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

The MIT License covers the original work in this repository (the `squad-src/`
tree, `docs/`, `scripts/`, and package metadata). It does not extend to the
third-party dependencies this package composes, which retain their own
licenses. See [NOTICE](NOTICE) for attribution details.

## Acknowledgements

hve-squad is a distribution and composition layer built on top of
[microsoft/hve-core](https://github.com/microsoft/hve-core), which is licensed
under the MIT License (© Microsoft Corporation). Dependencies are declared in
[apm.yml](apm.yml) and fetched at install time into `apm_modules/` (not
redistributed in this repository).

Some `hve-core` skill content is derived from OWASP Foundation publications and
is licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/);
those skills carry their own attribution. See [NOTICE](NOTICE) for the full
third-party attribution and trademark notice.
