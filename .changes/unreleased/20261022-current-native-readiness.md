---
bump: patch
type: Fixed
---

- **Fresh initialization uses actual UTC rather than a model-invented clock.** The deterministic helper supplies an omitted timestamp and rejects a future one before publishing state, preventing fresh role artifacts from appearing stale. Explicit historical timestamps remain supported.
- **Closing reviews preserve exact input paths and local probe boundaries.** Requirements handoffs carry verified research, plan, draft and capture locations without guessing filenames. Local review probes use literal authorized workspace paths; denied probes and genuine quality findings remain failures, not permission or verdict bypasses.
