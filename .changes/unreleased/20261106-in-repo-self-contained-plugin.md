---
bump: minor
type: Changed
---

- **The Copilot plugin is now self-contained and published from this repository.** Manual stable and preview publication writes one `hve-squad` marketplace entry to the `plugin` or `plugin-preview` branch, bundles the exact HVE Core commit pinned by `apm.yml`, removes the bundled MCP connection, and validates VS Code, Copilot CLI, and Copilot App package contracts on Windows, macOS, and Linux. The plugin is the primary install path; APM remains the repository-local fallback.
