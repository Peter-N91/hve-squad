---
bump: patch
type: Fixed
---

- **Documentation on `main` presented merged features as if they were already released.** Every guide now distinguishes the stable release from the rolling pre-release, with versioned feature badges linked to installation and testing instructions in English and French. Versions and exact APM commands are derived from `apm.yml` and pending change fragments; consuming a feature's fragment retires its badges automatically, and fragment-only merges rebuild the site (`scripts/docs-release.mjs`, `site/pages.njk`, `docs/getting-started.html`, `.github/workflows/docs.yml`).
