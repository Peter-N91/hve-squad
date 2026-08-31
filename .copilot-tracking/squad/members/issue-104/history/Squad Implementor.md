---
description: "Append-only dispatch history for a single squad agent"
---

# History: Squad Implementor

### 2026-08-27 Adapt squad-src to hve-core@8692fe3

* Turn: 1
* Request: Adapt `squad-src/` so every roster Primary resolves to an agent installed and dispatchable at `microsoft/hve-core@8692fe38cc0415ff8d21aa1b5d8198f008cd4038`, per the cast delta attached to issue #104, then move the `apm.yml` pin.
* Deliverable: `squad-src/.github/agents/squad/squad-data-scientist.agent.md`, `squad-src/.github/agents/squad/squad-prompt-engineer.agent.md`, `squad-src/.github/instructions/squad/squad-roster.instructions.md`, `apm.yml`, `.changes/unreleased/20260827-adapt-squad-cast-to-hve-core-8692fe3.md`
* Outcome: Every at-risk skill id and both at-risk agent mentions repointed; `apm.yml` repinned; change fragment staged.

Cloned `microsoft/hve-core` at the target SHA to verify the replacement surface directly. Confirmed `Data Workstream Coach` (`.github/agents/data-science/data-workstream-coach.agent.md`) and `Supply Chain Reviewer` (`.github/agents/security/supply-chain-reviewer.agent.md`) are both gone entirely — neither survives under any path, unlike a prior cast-delta run where a retired agent's directory still held a stub. `Data Workstream Coach`'s replacement, `Data Science and Engineering Coach` (`.github/agents/data-science-engineering/data-science-engineering-coach.agent.md`), still sets `user-invocable: true` and `disable-model-invocation: true`, so it remains unreachable by `runSubagent`/`task` — no roster change follows from its arrival. Confirmed the six retired `data-science` skills now ship renamed under `.github/skills/data-science-engineering/`: `ds-catalog` → `data-catalog`, `ds-analysis-authoring` → `analysis-authoring`, `ds-dataops` → `dataops`, `ds-feasibility` → `feasibility`, `ds-evaluation-design` → `evaluation-design`, and `data-workstream-foundation` → `data-science-engineering-foundation` (this last one unused by any squad charter, so no rename needed). Confirmed `ml-experimentation` kept its id and only moved directory, so no squad-src reference needed a change for it. Confirmed `Supply Chain Reviewer` has no dispatchable replacement, but its coverage was already fully absorbed by `SSSC Planner` and `Supply Chain Skill Assessor`, both unaffected by this delta and still dispatchable.

Edits made:

* `squad-src/.github/agents/squad/squad-data-scientist.agent.md` — mechanically renamed all five `ds-*` skill ids to their `data-science-engineering` equivalents (description frontmatter, rationale paragraph, Purpose bullet, Step 1 routing list); reworded the `Data Workstream Coach` rationale sentence to describe the non-dispatchable coach orchestrator generically rather than name a retired agent in backticks.
* `squad-src/.github/agents/squad/squad-prompt-engineer.agent.md` — mechanically renamed `ds-evaluation-design` to `evaluation-design` everywhere it appears (description, rationale, Purpose, Step 1, Response Format).
* `squad-src/.github/instructions/squad/squad-roster.instructions.md` — renamed all `ds-*` skill ids in the `data-scientist` row to their new equivalents; renamed `ds-evaluation-design` to `evaluation-design` in the `prompt-engineer` row and the `agentic-eval` blocklist cross-reference; reworded the `data-scientist` row's `Data Workstream Coach` mention the same way as the charter; rewrote *Deferred Reviewer-Class Agents* to drop the removed `Supply Chain Reviewer` row, corrected the count from five to four, and added a paragraph stating it was removed outright at `8692fe38cc0415ff8d21aa1b5d8198f008cd4038` with its coverage already absorbed by `SSSC Planner`/`Supply Chain Skill Assessor`.
* Checked `squad-src/.github/agents/squad/squad-coordinator.agent.md` and `squad-federation-coordinator.agent.md` — both already list `Squad Data Scientist` and `Squad Prompt Engineer` in their `agents:` frontmatter (from a prior cast-delta run) and neither lists any of this delta's retired names, so no edit was needed.
* Checked `squad-src/.github/skills/squad/SKILL.md`, `squad-src/.github/skills/squad/references/seed-templates.md`, and `squad-src/.github/instructions/squad/squad-routing.instructions.md` — all already name `Squad Data Scientist`/`Squad Prompt Engineer` as Primaries without hardcoding a skill id, so none needed a change.
* Swept `README.md`, `CONTRIBUTING.md`, and `docs/` for all seven at-risk names; zero hits. No documentation update was needed, and this is recorded explicitly rather than left unstated.
* Ran `pwsh scripts/Update-ApmDependencies.ps1 -Ref 8692fe38cc0415ff8d21aa1b5d8198f008cd4038`, which walks the actual hve-core and squad-src trees rather than a hardcoded list, so it moved all 243 hve-core dependency lines to the new SHA and picked up the renamed `data-science-engineering` skill/agent/prompt paths automatically. Verified `version:` (`0.16.2`, unchanged) and `CHANGELOG.md` were untouched by the run.
* Ran `pwsh scripts/New-ChangeFragment.ps1 -Type Changed -Bump minor` producing `.changes/unreleased/20260827-adapt-squad-cast-to-hve-core-8692fe3.md`, naming the rename map and the reworded deferral table.

#### Consumption

```json
{
  "model": "claude-sonnet-5",
  "model_source": "session-inherited",
  "priced_as": "Claude Sonnet 5",
  "model_tier": "default",
  "internal_turns": 18,
  "input_tokens": 150000,
  "cached_tokens": 500000,
  "cache_write_tokens": 80000,
  "output_tokens": 16000,
  "basis": "estimated"
}
```
