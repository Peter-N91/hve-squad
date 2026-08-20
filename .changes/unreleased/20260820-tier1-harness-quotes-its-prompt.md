---
bump: patch
type: Fixed
---

- **The Tier 1 behaviour harness could not start a squad turn.** `Start-Process` concatenates its
  argument list with spaces and does no quoting of its own, so the scenario prompt reached the
  Copilot CLI as a stream of separate words and every turn exited on `Invalid command format` in
  under a second. The failure sat exactly in the gap the harness's own `-ProvisionOnly` mode skips,
  which is why provisioning had passed on all three scenarios while no scenario had ever run a turn.
  Arguments carrying whitespace now bring their own quotes, following the Windows argv rules
  PowerShell also applies when it tokenizes the string on Unix (`tests/tier1/SquadRun.psm1`).
