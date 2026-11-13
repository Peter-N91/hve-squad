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
- **Checkov** infrastructure-as-code and GitHub Actions scanning across `.github/workflows/` and shipped `.workflow.yml` templates.
- **Zizmor** blocking GitHub Actions security analysis across `.github/workflows/`, `.github/dependabot.yml`, and shipped `.workflow.yml` templates, reported to the Security tab.
- **OpenSSF Scorecard** supply-chain posture analysis, published publicly.
- **Tier 0 conformance testing** over the shipped agent assets. Tier 1
  behavioural and Tier 2 semantic testing are available as manual runs.
- **Dependabot** weekly updates for GitHub Actions with a 7-day release cooldown.

Third-party GitHub Actions are pinned to full commit SHAs, workflows declare
token permissions explicitly with job-level scopes, and checkouts use
`persist-credentials: false`. Automated repository mutations (`sync-hve-core.yml`,
`release-prep.yml`, `sync-model-benchmarks.yml`) run in the `automation-governance`
GitHub Environment using short-lived `actions/create-github-app-token`
installation tokens (with transitional PAT fallback prior to organization
transfer) and propose pull requests rather than pushing directly to `main`.
Headless Copilot workflows (`squad-watch.yml`, `tier1-behavior.yml`,
`tier2-semantic.yml`) run in the `copilot-headless` GitHub Environment, with
event-driven Watch gated on `vars.SQUAD_WATCH_ENABLED == 'true'`. These controls
do not replace the destination organization's required reviews, branch
protection, SDL, or release approval.

### Watch Mode credential boundary

Both `.github/workflows/squad-watch.yml` and the shipped consumer template
`squad-src/.github/skills/squad/squad-watch.workflow.yml` separate read-only
interpretation (`interpret`, `persist-credentials: false`, runtime zero-write
verification of `COPILOT_GITHUB_TOKEN`) from minimal-scope publication jobs
(`apply`, `post-review`, `escalate-*`), and sanitize failure diagnostic
artifacts (redacting token patterns and skipping symlinks with 1-day retention)
before upload.

- **Repository workflow (`.github/workflows/squad-watch.yml`):** `copilot --allow-all-tools`
  executes inside SHA- and digest-pinned `github/gh-aw-firewall` (`awf`).
  `COPILOT_GITHUB_TOKEN` is held exclusively by the isolated `api-proxy`
  sidecar container outside the `agent` container's environment and `/proc`,
  `GH_TOKEN`/`GITHUB_TOKEN` are excluded, `.squad-trusted` is mounted
  read-only, and Squid restricts agent HTTP/HTTPS egress to an explicit domain
  allowlist.
- **Consumer reference template (`squad-watch.workflow.yml`):** Ships without
  requiring container runtime privileges by default, so `--allow-all-tools`
  shares the runner OS process environment with `COPILOT_GITHUB_TOKEN`. Prompt
  injection cannot mutate the repository, but untrusted tool execution could
  access `COPILOT_GITHUB_TOKEN` (Copilot-Requests quota scope only) unless
  consumers configure short token expiry and collaborator-only triggers or wrap
  execution in `github/gh-aw-firewall` (`awf`).
