---
bump: patch
type: Fixed
---

- **VS Code's Copilot harness could report installed HVE Core agents as missing.**
  Shared discovery now accepts active plugin roots advertised by the current host,
  so separately synced plugin copies resolve consistently during initialization,
  dispatch planning, model-pin lookup, and handoff attribution. Repository-local
  overrides, the working VS Code Local-harness path, and CLI/App sibling-plugin
  discovery remain supported. The resolver does not scan stale plugin caches;
  native dispatch still requires the host-advertised agent identity and honors
  invocation restrictions. Updated coordinator guidance, plugin packaging,
  regression coverage, and English/French troubleshooting
  (`squad-src/.github/skills/squad/scripts/SquadAgentDiscovery.ps1`,
  `squad-src/.github/skills/squad/references/agent-discovery.md`).
