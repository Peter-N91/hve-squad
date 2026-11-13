---
bump: patch
type: Security
---

- **Pin all shipped `.workflow.yml` templates to commit SHAs, harden `github-approval-watcher.workflow.yml`, and enforce blocking template security scans (#257).** `github-approval-watcher.workflow.yml` and the `azure-scaffold` workflow templates (`deploy-bicep.workflow.yml`, `deploy-terraform.workflow.yml`, `governance-baseline.workflow.yml`) now pin every GitHub Action to a 40-character commit SHA with version comment, set `persist-credentials: false` on every checkout, enforce empty workflow-level permissions with minimal per-job scopes, and pass expressions into `run:` steps exclusively via `env:`. `github-approval-watcher.workflow.yml` additionally restricts its token to `issues: write`, ignores pull-request and self-relayed comments, anchors standalone `Approver: @handle` lines, and sanitizes `/changes:` notes inside single-line inline code spans. CI's Zizmor and Checkov workflows now stage all shipped `squad-src/**/*.workflow.yml` templates with SARIF URI remapping back to `squad-src/...`, enforce a 7-day Dependabot cooldown on GitHub Actions, and block pull requests on unsuppressed Zizmor errors and warnings.
