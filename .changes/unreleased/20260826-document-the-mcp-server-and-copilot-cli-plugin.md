---
bump: patch
type: Added
---

- **The documentation never pointed to the MCP server or the Copilot CLI plugin.** The home page mentioned `hve-squad-mcp` in passing with a bare GitHub link, and `hve-squad-plugin` was absent from the site and the README entirely, so a consumer had no path from this repository to either sibling's documentation. Added an **Ecosystem** page (`docs/ecosystem.html`, wired into the navigation and pager across the site) covering what each of the three repositories is, which surface to use for which host, the MCP server's two execution modes and its tool set, the plugin's install-as-a-pair rule and its two update rules, and how releases stay aligned. The home page's companion section now covers both siblings with links to their GitHub Pages sites, and `README.md` gained a **Related repositories** table (`docs/index.html`, `README.md`).
