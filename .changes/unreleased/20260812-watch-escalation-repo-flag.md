---
bump: patch
type: Fixed
---

- **Watch Mode could not report its own failure.** Both `gh issue comment` calls ran in jobs that
  never check out the repository — the escalation job has no checkout at all, and the no-changes
  notice runs ahead of a checkout that is itself conditional on there being changes. With no git
  remote to infer from, `gh` exited `not a git repository`, so the run that most needed to reach a
  human was the one that could not. Both calls now pass `--repo` explicitly
  (`.github/workflows/squad-watch.yml`).
- **A missing `COPILOT_GITHUB_TOKEN` surfaced as a generic authentication error.** The Copilot CLI
  reports `Authentication failed - your GitHub token may be invalid, expired, or lacking the
  required permissions`, which reads like a problem with a token that exists and sends the reader to
  inspect the PAT they already configured rather than the dedicated one they never created. The step
  now checks the secret first and names it, along with the permission it needs and the fact that
  `GH_TOKEN` and `SYNC_DEPS_TOKEN` cannot substitute for it
  (`.github/workflows/squad-watch.yml`).
