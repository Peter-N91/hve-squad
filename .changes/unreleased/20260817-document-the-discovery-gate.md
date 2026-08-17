---
bump: patch
type: Changed
---

- **The discovery gate shipped with no consumer documentation.** The usage guide now covers it as a
  sibling of the intake gate — the inverse triggers that chain a brainstorm into a validation, why it
  is offered rather than automatic, the four trigger conditions, the `quick`/`standard`/`deep`/`skip`
  depth tiers, and why it stays silent outside the `product` and `full` profiles while the intake gate
  escalates. The `discovery=` and `owner=` inputs are documented for the first time (`docs/usage.html`,
  `docs/index.html`).
