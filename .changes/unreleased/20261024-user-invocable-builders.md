---
bump: patch
type: Added
---

- **Connector and external endpoint setup no longer requires hand-copying every artifact.** User-invocable Squad Connector Builder and Squad External Agent Builder entrypoints gather decisions, then deterministic PowerShell scripts safely create or adapt agents, orchestrators, skills, closed-schema manifests, file-drop guidance, examples, a removable runner, and detailed runbooks without overwriting customized files (`squad-src/.github/skills/squad/references/builder-workflows.md`).
