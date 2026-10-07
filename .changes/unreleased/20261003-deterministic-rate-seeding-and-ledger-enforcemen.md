---
bump: minor
type: Added
---

- **Scripted rate-table seeding under `routing=economy` (economy-only; `off`, `ranked`, and `manual` keep the v0.18.0 Scribe procedure).** New `scripts/Initialize-SquadConsumptionRates.ps1` (PowerShell 7+) copies the template seed block into `consumption-rates.md`, preserves the calibration block, and validates shape with `-Check`: a missing template row fails, a well-formed operator-added row only warns and survives a reseed, and a malformed operator row is never deleted silently (exit 1, file untouched, unless the operator approves `-DropMalformedRows`). It reads `team.md` and refuses with exit 7 unless it records `Model routing: economy`; at Init, before `team.md` exists, it takes `-Mode` from the payload. `Measure-SquadLedger.ps1` also accepts `-ExpectedHistoryCounts` as a string (`'Squad Implementor=2;Squad Scribe=1'` or JSON) so it can cross `pwsh -File`, and reads the roster's primary-agent column under its common spellings; both are additive and change nothing for existing callers. See `references/economy-mode.md`.
