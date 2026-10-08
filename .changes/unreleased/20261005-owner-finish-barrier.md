---
bump: minor
type: Added
---

- **Review-saw-the-final-files check for scripted hand-offs (applies only under `routing=economy`).** Under `routing=economy`, `scripts/Write-SquadHandoff.ps1` refuses a hand-off (exit 1, nothing written) when an owner deliverable was modified more than 2 s after the closing review's own deliverable; only re-dispatching the review on the final files clears it. It compares file times and does not prove an owner reported it was finished. An optional `-SnapshotPath`/`-VerifySnapshotPath` pair (with `-WaitStable`) compares hashes for write sets the check cannot see. Both refuse with exit 7 outside economy. See `references/economy-mode.md`.
