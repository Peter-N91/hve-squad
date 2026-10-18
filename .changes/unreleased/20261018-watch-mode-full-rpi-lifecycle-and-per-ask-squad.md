---
bump: patch
type: Fixed
---

- **Watch Mode now selects a sub-squad per case and per ask and executes the complete RPI lifecycle across all triggers (#176).** `squad-watch-mode.instructions.md`, `references/federation.md`, `squad-watch.workflow.yml`, `.github/workflows/squad-watch.yml`, and `.github/workflows/sync-hve-core.yml` now require every Watch Mode event (`issues`, `pull_request`, `issue_comment`, `schedule`, `workflow_dispatch`, `push`) to seed its event sub-squad from the canonical templates with a profile and packs tailored to the case and ask (always including the full `researcher`, `lead`, `developer`, `tester`, `scribe` spine rather than copying a prior `members/*` roster), repair a missing federation root when `members/*` directories exist on disk without `federation.md`, and run the full Research → Plan → Council → Implement → Review pipeline via `runSubagent`/`task` dispatches (including on Sync and Adapt adaptation briefs). `.github/workflows/squad-watch.yml` also provisions the installed squad and `hve-core` package before invoking the headless Copilot CLI and cleans up the runtime overlay before staging changes.
