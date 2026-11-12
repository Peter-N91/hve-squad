---
title: Security policy
description: Microsoft security reporting instructions and the hve-squad security scope.
---

<!-- BEGIN MICROSOFT SECURITY.MD V1.0.0 BLOCK -->

## Security

Microsoft takes the security of our software products and services seriously, which
includes all source code repositories in our GitHub organizations.

**Please do not report security vulnerabilities through public GitHub issues.**

For security reporting information, locations, contact information, and policies,
please review the latest guidance for Microsoft repositories at
[https://aka.ms/SECURITY.md](https://aka.ms/SECURITY.md).

<!-- END MICROSOFT SECURITY.MD BLOCK -->

## Supported versions

hve-squad is a pre-1.0 project. Only the latest published
release receives security fixes. Older tags are kept for reproducibility and are
not patched. See [CHANGELOG.md](CHANGELOG.md) for what shipped in each version.

| Version              | Supported |
|----------------------|-----------|
| Latest release       | Yes       |
| Rolling `-pre` tag   | Best effort |
| Any earlier tag      | No        |

## Threat model and scope

hve-squad is a distribution and composition layer for AI agent assets. It ships
markdown assets, PowerShell build scripts, and CI workflows; the repository does
not operate a hosted inference service. When used, agents and helpers can
process repository/task content and write local state, histories, usage
accounting, and notification contacts. Watch workflows can publish selected
artifacts through pull requests, and optional notifications send configured
payloads to GitHub or a webhook. Host/model-provider processing and consumer
data-handling responsibilities remain separate. Do not treat local state or
generated histories as safe to publish without review.

### Responsible-use boundary

Shipped agents and helpers must not independently report usage, prompts, source,
identities, model identifiers or local histories to maintainers or analytics/error
collectors. Local accounting and audit records stay local. Customer-requested web
research, tracker actions and explicitly enabled notifications are purposeful task
actions governed by their own authorization and payload contracts, not background
usage reporting.

The shared contract is the Squad skill's **Responsible Use** section, required
by every first-party agent and skill and the Squad Agent Floor.
These are instructions, not a sandbox:
the host's permissions and customer configuration remain the enforcement boundary.
Users and their organizations control model availability, entitlements, identities
and acceptable-use policy. Optional routing uses available models and role floors;
it neither certifies models nor establishes organization-policy approval.
Harness/provider inference processing and telemetry are separate. Running the
assets locally does not imply local inference or disable provider telemetry.

Package-level assurance must identify the reviewed version, include pinned
upstream content and disclose incomplete coverage. Static source checks cannot
prove arbitrary model behavior. Do not describe an unreviewed package as
telemetry-free. User-requested instrumentation of a customer's application is
separate from reporting use of these agents.

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

The repository provides pull request validation and these automated workflows:

- **CodeQL** static analysis on the Python surface.
- **Checkov** infrastructure-as-code scanning.
- **Zizmor** GitHub Actions security analysis, reported to the Security tab.
- **OpenSSF Scorecard** supply-chain posture analysis, published publicly.
- **Tier 0 conformance testing** over the shipped agent assets. Tier 1
  behavioural and Tier 2 semantic testing are available as manual runs.
- **Dependabot** weekly updates for GitHub Actions.

Third-party GitHub Actions are pinned to full commit SHAs, workflows declare
token permissions explicitly with job-level scopes, and checkouts use
`persist-credentials: false`. These controls do not replace the destination
organization's required reviews, branch protection, SDL, or release approval.
