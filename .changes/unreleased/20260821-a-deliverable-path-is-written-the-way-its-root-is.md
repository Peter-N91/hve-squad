---
bump: patch
type: Fixed
---

- **A role wrote its artifact in the right place and then recorded a path nobody could resolve.** A
  live federation run put the plan at the roster's declared root and logged
  `Deliverable: members/persistence/plans/2026-08-21-persistence-layer-plan.md` — the same location
  with `.copilot-tracking/squad/` shaved off the front, because that was the writer's working
  directory at the time. Proof of dispatch turns on listing the path, so a path that resolves only
  from one process's cwd is not evidence the file exists, and the reconciliation reported a missing
  deliverable for a file sitting exactly where it belonged. The floor now requires the `Deliverable:`
  path to extend the `Deliverable Root` cell verbatim, and the entry template names the root instead
  of a bare `<path>` (`squad-src/.github/instructions/squad/squad-floor.instructions.md`,
  `squad-src/.github/skills/squad/references/entry-schemas.md`).

- **The Tier 1 evidence upload dropped the deliverables it was added to capture.** The harness copies
  the tracking tree beside each attempt under its own dot-prefixed name so an uploaded result replays
  against the same path resolver the run used, but `actions/upload-artifact` skips hidden paths unless
  told otherwise — so every uploaded artifact carried the squad state and none of the files that state
  points at, and a failed existence check could not be investigated from the artifact alone
  (`.github/workflows/tier1-behavior.yml`).
