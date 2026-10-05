---
bump: patch
type: Fixed
---

- **An owner's early `task` return let the closing review start before the owner had finished editing.** Owners now write the change record last, ending with a `Status: complete — <validation command> exit <n>` line, and send one final message carrying files changed, validation result, and change-record path; the coordinator treats anything less as unfinished and dispatches no review until every owner is finished. `scripts/Write-SquadHandoff.ps1` enforces review-on-final-files at the hand-off: an owner deliverable modified more than 2 s after the review's deliverable exits 1 and writes nothing until the review is re-dispatched. An optional `-SnapshotPath`/`-VerifySnapshotPath` pair (with `-WaitStable`) covers write sets the check cannot see. Changed in the implementor, lead, reviewer, and technical-writer charters and `references/operating-procedure.md`.
