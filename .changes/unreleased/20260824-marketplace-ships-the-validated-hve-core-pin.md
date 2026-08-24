---
bump: patch
type: Fixed
---

- **The published plugin marketplace could pair a release with an hve-core commit it was never
  validated against.** The generated `marketplace.json` carried a single `hve-squad` entry and
  `autoUpdate: true`, leaving hve-core to be installed separately from its own source — so a
  consumer resolved whatever was current upstream rather than the commit the installed squad
  version's routing tables and role charters were built against.

  `Build-SquadPlugin.ps1` now emits a second `hve-squad-hve-core` entry whose commit SHA is read
  from the built ref's own `apm.yml`, so each release publishes the exact hve-core pin its
  cast-delta guard validated — `v0.16.1` resolves `b1cae50`, `v0.16.2-pre` resolves `3050cf5`,
  with no manifest hand-editing. `autoUpdate` is dropped deliberately: the two entries are a
  matched pair, and an unattended update of one without the other reintroduces the same skew.

  `publish-plugin.yml` gains an optional `mcp-version` input so a publish can bump the
  `@hve-squad/mcp` pin in the same run; omitted, the existing `.mcp.json` pin is reused rather
  than silently advanced.
