# Security Policy

## Supported versions

hve-squad is a solo-maintained, pre-1.0 project. Only the latest published
release receives security fixes. Older tags are kept for reproducibility and are
not patched. See [CHANGELOG.md](CHANGELOG.md) for what shipped in each version.

| Version              | Supported |
|----------------------|-----------|
| Latest release       | Yes       |
| Rolling `-pre` tag   | Best effort |
| Any earlier tag      | No        |

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.**

Report it privately through GitHub Security Advisories:
[Report a vulnerability](https://github.com/Peter-N91/hve-squad/security/advisories/new).

Please include:

- The affected version or commit.
- The component involved (agent, prompt, instruction, skill, workflow, or script).
- Reproduction steps and the impact you observed.
- Any suggested mitigation.

You can expect an acknowledgement within 5 business days and a status update
within 10 business days. Fixes ship in the next release; the advisory is
published once a fix is available. Coordinated disclosure is appreciated.

Vulnerabilities in a dependency (most notably
[microsoft/hve-core](https://github.com/microsoft/hve-core)) should be reported
to that project. If the issue is in how hve-squad composes or deploys a
dependency, report it here.

## Threat model and scope

hve-squad is a distribution and composition layer for AI agent assets. It ships
markdown assets, PowerShell build scripts, and CI workflows. It does not run a
service and holds no user data or secrets.

In scope:

- Prompt-injection paths in the shipped agents, prompts, instructions, and
  skills, including bypasses of the intake gate, council, and impactful-action
  gate.
- Supply-chain weaknesses in the build, release, and plugin publishing
  workflows.
- Insecure defaults in the deployed asset set that would grant an agent more
  capability than intended.
- Anything in the packaging path that could deliver tampered assets to a
  consumer's Copilot target.

Out of scope:

- Behaviour of GitHub Copilot, the underlying models, or any MCP server not
  authored in this repository.
- Vulnerabilities in third-party dependencies fetched at install time into
  `apm_modules/` (report upstream, see [NOTICE](NOTICE)).
- Findings that require a user to deliberately run the squad in an autonomy
  mode with the gates disabled.

## Security practices in this repository

Every change to `main` goes through pull request validation plus these
automated controls:

- **CodeQL** static analysis on the Python surface.
- **Checkov** infrastructure-as-code scanning.
- **Zizmor** GitHub Actions security analysis, reported to the Security tab.
- **OpenSSF Scorecard** supply-chain posture analysis, published publicly.
- **Tiered conformance testing** (Tier 0 conformance, Tier 1 behaviour,
  Tier 2 semantic) over the shipped agent assets.
- **Dependabot** weekly updates for GitHub Actions.

All third-party GitHub Actions are pinned to a full commit SHA, workflows
declare an empty top-level `permissions: {}` and grant the minimum token scope
per job, and checkouts use `persist-credentials: false`.
