---
bump: patch
type: Fixed
---

- **Only manually annotated Economy guidance showed which documented features were still in pre-release.** The documentation build now traces every pending change fragment to its merge commit, automatically badges affected English and French sections with the current rolling tag, and removes those badges when Release Prep consumes the fragments; the current Coach, Connector, model-routing, and release-guide documentation is covered without feature-specific markup (`scripts/docs-release.mjs`, `.github/workflows/docs.yml`, `docs/maintaining.html`).
