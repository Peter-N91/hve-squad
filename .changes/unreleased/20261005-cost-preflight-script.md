---
bump: minor
type: Added
---

- **Scripted Cost Preflight write under `routing=economy` (economy-only; other modes keep the v0.18.0 transaction).** New `scripts/Set-SquadCostPreflight.ps1` performs the coordinator's pre-dispatch Cost Preflight transaction deterministically: closed key set, compare-and-swap on `updated`, the exact legacy schema bump, and read-back. It reads `team.md` and refuses with exit 7, writing nothing, unless it records `Model routing: economy`. See `references/economy-mode.md`.
