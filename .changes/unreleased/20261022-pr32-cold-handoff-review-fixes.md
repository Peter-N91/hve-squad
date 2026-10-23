---
bump: patch
type: Fixed
---

- **PR32 review fixes route ceiling-admitted handoffs, ledger writes, cold budgets and VS Code setup correctly.** The requirements review barrier sends configured-ceiling and federation-aggregate handoffs through the existing cold Scribe instead of the refusing ordinary writer; the cold ledger helper is scoped to single and member roots with inert `ledgerCommand`; the cold-read budget now measures the Scribe agent and stays under its baseline; README and the English/French VS Code guides describe the trusted helper and the Settings → Extensions → Copilot → Plugins install of both plugins (`requirements-quality.md`, `scribe-cold-charter.md`, `Packaging.Tests.ps1`, `README.md`, `docs/getting-started.html`).
