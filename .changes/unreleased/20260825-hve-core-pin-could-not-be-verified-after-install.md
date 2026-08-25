---
bump: patch
type: Fixed
---

- **An installed `hve-squad-hve-core` tree could not be proven to match the commit its marketplace entry pins.** `config.json` records a content digest rather than the git commit SHA-1, and its `version` comes from upstream hve-core's own `plugin.json`, so `copilot plugin update` reports 'already at latest' even when the pin moves. Added `scripts/Test-HveCorePin.ps1`, which recomputes the git blob SHA-1 of every installed file against the pinned tree, and rewrote the marketplace description in `scripts/Build-SquadPlugin.ps1` to say the plugin replaces the official hve-core plugin rather than sitting beside it, and must be refreshed with uninstall-then-install.
