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
  <!-- The canonical api.scorecard.dev/badge endpoint redirects to shields.io's
       ossf-scorecard route, which still reads the legacy api.securityscorecards.dev
       mirror. That mirror has not ingested this repository, so the canonical badge
       renders "invalid repo path". Read the score from the live API instead. -->
  <a href="https://scorecard.dev/viewer/?uri=github.com/Peter-N91/hve-squad"><img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fapi.scorecard.dev%2Fprojects%2Fgithub.com%2FPeter-N91%2Fhve-squad&query=%24.score&label=openssf%20scorecard&suffix=%20%2F%2010&color=brightgreen" alt="OpenSSF Scorecard" /></a>
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
| [Usage](https://peter-n91.github.io/hve-squad/usage.html)                     | Profiles, autonomy modes, cost ceilings, remote approval, and Init Mode  |
| [Ecosystem](https://peter-n91.github.io/hve-squad/ecosystem.html)             | The MCP server and the Copilot CLI plugin, and which surface to use      |
| [Maintaining](https://peter-n91.github.io/hve-squad/maintaining.html)         | Dependency generation, author workflow, customization, release process   |
| [Troubleshooting](https://peter-n91.github.io/hve-squad/troubleshooting.html) | Known install errors with fixes, versioning, and repository notes        |

The site source is in [docs/](docs/) and is published to GitHub Pages by
[.github/workflows/docs.yml](.github/workflows/docs.yml) on every push to `main` that touches
`docs/`.

## Related repositories

This repository is the source of truth. The squad also ships through two sibling repositories,
each generated from a tagged `hve-squad` release rather than maintained as a fork:

- **[hve-squad-mcp](https://github.com/Peter-N91/hve-squad-mcp)** — an outbound MCP server that
  publishes the squad as model-invocable tools, so hosts such as Copilot Studio can call it.
  Docs: [peter-n91.github.io/hve-squad-mcp](https://peter-n91.github.io/hve-squad-mcp/)
- **[hve-squad-plugin](https://github.com/Peter-N91/hve-squad-plugin)** — a generated,
  release-gated mirror of the squad's GitHub Copilot CLI plugin tree, published as a plugin
  marketplace. Docs: [peter-n91.github.io/hve-squad-plugin](https://peter-n91.github.io/hve-squad-plugin/)

Use this package when you want `/squad` in VS Code Copilot Chat with the full cast installed in your
repository, the plugin when you want the squad in the Copilot CLI or desktop app with no `apm install`,
and the MCP server when another host should call the squad as tools. See
[Ecosystem](https://peter-n91.github.io/hve-squad/ecosystem.html) for the full comparison.

## Quick start

The APM installation path currently requires **APM CLI 0.29.0**. A regression in APM
0.29.1 and 0.30.0 causes 11 HVE Squad dependencies to fail, so do not use an unversioned
latest installation for now. Confirm the CLI version before installing the package:

```powershell
apm --version  # must report 0.29.0
apm install "Peter-N91/hve-squad#vX.Y.z" --target copilot
```

See [Getting Started](https://peter-n91.github.io/hve-squad/getting-started.html) for pinned
APM installation commands for Windows and macOS, and
[Troubleshooting](https://peter-n91.github.io/hve-squad/troubleshooting.html) if an earlier
attempt left a partial installation.

Then invoke `/squad` in Copilot Chat:

```text
/squad request="add input validation to the login form"
```

Add an optional model-spend ceiling when you want a conservative forecast before work starts:

```text
/squad request="add input validation to the login form" cost-ceiling=10
```

Within the same run, omitting the argument preserves an active ceiling. Use
`cost-ceiling=unset` to remove it explicitly. See
[Cost admission control](https://peter-n91.github.io/hve-squad/usage.html#cost-admission-control)
for estimation, approval, stopping, and federation behavior. Fresh-squad initialization is outside
admission. Ordinary federation routing applies the ceiling independently to each selected sub-squad;
only untargeted federation autopilot uses one aggregate federation ceiling.

### Choosing models per role (`routing=` / `models=`)

**Default behavior (no `routing=` or `models=`):** When neither input is given, no `model` parameter is passed to any dispatch, so each agent runs on its own frontmatter model or the session model, exactly as before this feature existed.

Optionally, you can take direct control of model selection with two inputs:

* **`routing=ranked`** — Opt into capability-ranked model selection. The squad ranks the best-qualified model from the declared model catalog for each role, filters by availability on your host, and applies consequence floors to prevent models below a role's tier. With `routing=off` (or omitted), `models=` overrides only the named keys; every other role omits the parameter.

* **`models=<key>:<id>,<key>:<id>,...`** — Explicit per-role or per-assignment-class overrides. Supported keys:
  - **Role IDs** from your `team.md`: `researcher`, `lead`, `developer`, `tester`, `challenger`, `architect`, `security`, `cost-manager`, `rai`, `product-owner`, `prompt-engineer`, `intake-validator`, `scribe`, and any other role in the seeded rosters.
  - **Assignment classes**: `research`, `planning`, `implementation`, `review`, `council`, `intake`, `bookkeeping`.

  Unknown keys or model IDs are refused and logged rather than guessed. A model below your role's roster tier is also refused—raise the tier in `.copilot-tracking/squad/team.md` if you need it.

**Precedence** (highest wins, per role):
1. A `models=<role-id>:<model-id>` pair naming that exact role id.
2. A `models=<class>:<model-id>` pair naming that role's assignment class.
3. `routing=ranked` output for that role, when no override applies.
4. `tier=` (the existing static-tier input) or the seeded `team.md` Model Tier — today's fallback, unchanged.
5. Omit the parameter — the no-policy default.

**Re-ranking:** When the host rejects the chosen model id, the routing procedure re-ranks to the next eligible candidate under the same floor and class, and records the substitution (requested, actual, why) in that dispatch's history.

**Unevaluated models:** A model the host advertises but the catalog does not carry is never auto-ranked. It is usable only through an explicit `models=` override and is labelled `unevaluated` in the dispatch record.

**Examples:**

```text
/squad request="..." routing=ranked
```
Enable ranked selection; every role picks its best-qualified model from the catalog and your host.

```text
/squad request="..." routing=ranked models=review:claude-opus-5.5
```
Enable ranking, but use Claude Opus 5.5 explicitly for `review` class (or specific reviewer roles).

```text
/squad request="..." models=researcher:gpt-5.5 tier=default
```
No ranking (`routing=off` by default); only `researcher` uses `gpt-5.5`, every other role falls back to `default` tier.

```text
/squad-federation squad=product routing=ranked models=bookkeeping:gpt-5-mini
```
Route to the `product` sub-squad with ranked selection, but use `gpt-5-mini` for bookkeeping roles.

**Rejection example:**

```text
/squad request="..." models=architect:claude-haiku-4.5
```
If `architect` has a `default` tier floor and `claude-haiku-4.5` is classified as `fast-lightweight`, this is refused (logged as "below-floor") and the architect falls back to the precedence chain instead.

**How to see available models:**

- **Copilot CLI:** Run `/model` to see the model ids the `task` tool advertises — the same list that `routing=ranked` uses.
- **VS Code:** Use the model picker when you see a model selector in the UI. A rejected model id is automatically re-ranked.
- **Full catalog:** See `squad-src/.github/skills/squad/references/model-catalog.md` in the repository. It is a dated snapshot (retrieved 2026-09-27) with capability classifications, pricing rates, and host-availability notes. The catalog has a 90-day staleness threshold; older catalogs fall back to static tier pricing.

**History and identity bullets:**

The squad records which model routing requested, which model actually ran (if the host substituted one), and which model the host reported. These details appear in `.copilot-tracking/squad/history/` (single squad) or `.copilot-tracking/squad/members/<name>/history/` (federation) only when a `routing=` or `models=` policy applied. See the identity bullets in those history files for: Requested model, Effective model, Observed model, and Route rationale.

**Important notes:**

- **Estimates, not bills** — Token counts and cost figures are estimated from a dispatch-size model, not from runtime telemetry. Premium-request multipliers and long-context pricing come from the catalog and are estimates. See `squad-src/.github/skills/squad/references/model-catalog.md` and `consumption-rates.md` for methodology.
- **Availability sources** — The catalog cites three GitHub official documentation pages (fetched at catalog build time): Supported AI models, Models and pricing, and AI model comparison. URLs are listed in the catalog header.

**Optional ledger check:**

After a squad run, you can verify the consumed and estimated consumption against the recorded history using the read-only script:

```powershell
.github/skills/squad/scripts/Measure-SquadLedger.ps1 -SquadRoot .copilot-tracking/squad -Check
```

Or, for a sub-squad in a federation:

```powershell
.github/skills/squad/scripts/Measure-SquadLedger.ps1 -SquadRoot .copilot-tracking/squad/members/<name> -Check
```

This script (PowerShell 7+) validates that every recorded dispatch has a consumption block, that token counts and cost derivations round-trip correctly, and that the aggregated ledger totals match the sum of all recorded history entries. It is optional, never required, and is useful for post-run audits or when troubleshooting cost reporting.

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
