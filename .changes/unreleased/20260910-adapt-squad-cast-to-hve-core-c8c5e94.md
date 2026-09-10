---
bump: minor
type: Changed
---

- **hve-core@c8c5e94 removed the `Code Review PR` findings-perspective subagent outright with no dispatchable one-for-one replacement.** Its Register 1 walkthrough capability moved into `Code Review Orientation`, a new mandatory internal stage the `Code Review` orchestrator now runs itself before any findings perspective rather than a caller-dispatchable subagent -- it consumes a `diff-state.json` only that orchestrator produces, so it fails the roster's worker-agent contract test and cannot serve as a roster alternate. The `tester` role's Cast Catalog row and the `squad-coordinator.agent.md`/`squad-federation-coordinator.agent.md` `agents:` frontmatter were updated to drop the retired alternate; `Code Review Readiness` already covers PR deliverable readiness, so no gap remains and no new squad-owned charter was needed. `apm.yml` is regenerated and repinned to `c8c5e94ecd22438e21460bd4b2064f8516f55603`.
