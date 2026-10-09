---
bump: minor
type: Changed
---

- **Repointed the squad cast to hve-core `af0e654818ea1fa7b1c00dc193ab1772a9a02ffc`.** `incident-response`, `risk-register`, and `synth-data-generate` were promoted from prompts to skills upstream and still set `disable-model-invocation: true`; `Squad Azure Diagnose`, `Squad Risk Manager`, and `Squad Data Scientist` now read the new `SKILL.md` locations instead of the removed `.prompt.md` files, and still escalate to the user to invoke each skill directly when deeper work is needed. The `vex-scan` and `vex-triage` prompts were removed outright with no replacement; `Squad Vulnerability Manager` and the roster docs now point deep per-CVE escalation at the user-invocable `SSSC Reviewer` agent instead of the retired slash commands. No roster Primary or Alternate changed agent identity, and no dispatchable agent name was renamed or removed in this hve-core revision.
