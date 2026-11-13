---
bump: patch
type: Security
---

- **Split shipped `squad-watch.workflow.yml` into least-privilege jobs and make Watch helpers layout-agnostic (#257).** `squad-watch.workflow.yml` now runs `interpret` strictly read-only (`contents/issues/pull-requests: read`) with `persist-credentials: false`, SHA-pinned Actions and Copilot CLI, runtime fail-closed `COPILOT_GITHUB_TOKEN` zero-write verification, `New-SquadWatchBaseline`, and `New-SquadWatchHandoff`, delegating mutations to minimal-scope `apply`, `post-review`, `escalate-unauthorized`, and `escalate-failure` jobs. `Assert-SquadWatchTrustedCheckout.ps1`, `Invoke-SquadWatchAppliedPatch.ps1`, and `Invoke-SquadWatchMarkedBody.ps1` resolve consumer skill roots across `.agents/skills/squad`, `.github/skills/squad`, and `squad-src/.github/skills/squad` (or validated `SQUAD_WATCH_SKILL_ROOT`).
