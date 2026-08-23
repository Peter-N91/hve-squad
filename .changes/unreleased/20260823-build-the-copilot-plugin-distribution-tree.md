---
bump: minor
type: Added
---

- **hve-squad can now build its own GitHub Copilot plugin distribution.** There was no repeatable way
  to turn a released `hve-squad` tag into the tree `Peter-N91/hve-squad-plugin` ships — every prior
  build was a manual, one-off assembly of `plugin.json`, `marketplace.json`, and `.mcp.json`, with no
  guarantee that a later regeneration wouldn't silently drop hand-authored fields.

  `scripts/Build-SquadPlugin.ps1` resolves either an immutable `-Ref <tag>` or a local `-SourceRoot`
  dev build, and now owns `plugin.json`, `marketplace.json`, and `.mcp.json` generation end to end,
  including an `-McpVersion` pin that reuses the existing `@hve-squad/mcp` version when omitted and
  refuses to guess one when no prior pin exists. `.github/workflows/publish-plugin.yml` wraps the
  generator in a manual (`workflow_dispatch`) cross-repo publish step, failing closed when
  `HVE_SQUAD_PLUGIN_PUSH_TOKEN` is not configured rather than skipping the push silently.

  `squad-src/.github/skills/squad/mcp-server.template.json` is updated to match: `@hve-squad/mcp` is
  now published to npm, the template pins an exact version instead of a bare `@latest` reference, and
  documents why the pin is a deliberate, separate action from a content rebuild.
