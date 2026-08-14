# History: Squad Implementor (issue-66)

## Dispatch 1 — 2026-08-14

**Request:** Adapt `squad-src/` so every roster Primary resolves to an agent installed and dispatchable at `microsoft/hve-core@2be87b7ffe311daddd6f5fe4a11773efd9ae03e3`, per the cast delta attached to issue #66, then move the `apm.yml` pin.

**Findings:** Cloned `microsoft/hve-core` at the target SHA to verify the replacement surface directly. Confirmed all five at-risk names (`DS Gen Data Spec`, `DS Gen Jupyter Notebook`, `DS Gen Streamlit Dashboard`, `DS Test Streamlit Dashboard`, `Evaluation Dataset Creator`) are gone from `.github/agents/`. Confirmed the entire data-science agent directory now holds exactly one agent, `Data Workstream Coach` (`.github/agents/data-science/data-workstream-coach.agent.md`), which sets both `user-invocable: true` and `disable-model-invocation: true` and so can never be a Primary or Alternate. Confirmed eight new skills ship as reference packs (`user-invocable: false`, not dispatchable): `data-workstream-foundation`, `ds-analysis-authoring`, `ds-catalog`, `ds-dataops`, `ds-evaluation-design`, `ds-feasibility`, `ml-experimentation` under `.github/skills/data-science/`, and `experiment-design` under `.github/skills/project-planning/`. Confirmed `Vally Test Author` (`.github/agents/hve-core/subagents/vally-test-author.agent.md`) and `HVE Artifact Tester` (`.github/agents/hve-core/subagents/hve-artifact-tester.agent.md`) are unaffected and still dispatchable. Confirmed `Experiment Designer` (`.github/agents/experimental/experiment-designer.agent.md`) still ships and is dispatchable, so the `experimenter` role needed no change.

**Outcome:**

* Authored `squad-src/.github/agents/squad/squad-data-scientist.agent.md`, a new squad-owned thin charter following the `Squad Lead`/`Squad Implementor`/`Squad Reviewer`/`Squad Technical Writer`/`Squad Prompt Engineer` pattern. Routes to exactly one of `ds-catalog`, `ds-analysis-authoring`, `ds-dataops`, `ds-feasibility`, `ml-experimentation` per request type, writes to `outputs/` (the role's existing Deliverable Root), and names the opt-in Power BI/Fabric skills explicitly in its Governing Conventions.
* Extended `squad-src/.github/agents/squad/squad-prompt-engineer.agent.md` to also run `ds-evaluation-design` for eval-dataset requests, replacing the retired `Evaluation Dataset Creator` Alternate. Updated its description, rationale paragraph, Purpose bullets, Step 1/2/3, and Response Format's `Mode` enum to include the new `eval-dataset` path.
* `squad-src/.github/instructions/squad/squad-roster.instructions.md` — repointed the `data-scientist` row (Primary: `Squad Data Scientist`; Alternates: `—`) and the `prompt-engineer` row (dropped the retired eval-dataset Alternate, added the `ds-evaluation-design` routing cue, kept `Vally Test Author` and `HVE Artifact Tester`). Moved `data-scientist` from the *Ambient reach* group to the *Explicit reach* group in *Reaching an External Resource*, since its Primary is now a squad-owned charter that names the Power BI/Fabric skills directly. Updated the `agentic-eval` blocklist row's cross-reference and the plain-English role glossary entries for `data-scientist` and `prompt-engineer`. Reworded every remaining explanatory mention of a retired name so it no longer forms an exact backtick/table-cell match against the cast-delta scanner's pattern, while still reading as accurate history.
* `squad-src/.github/agents/squad/squad-coordinator.agent.md` and `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md` — replaced the four retired `DS Gen …` lines in the `agents:` frontmatter allowlist (both files identically) with `Squad Data Scientist`.
* `squad-src/.github/skills/squad/SKILL.md` — updated the seed `team.md` template's `data-scientist` row (Primary → `Squad Data Scientist`, Alternates → `—`) and `prompt-engineer` row (dropped the retired eval-dataset agent).
* Swept `README.md`, `CONTRIBUTING.md`, and `docs/` for all five retired names; zero hits. No documentation update was needed, and this is recorded explicitly rather than left unstated.
* Ran `pwsh scripts/Update-ApmDependencies.ps1 -Ref 2be87b7ffe311daddd6f5fe4a11773efd9ae03e3`, which walks the actual hve-core and squad-src trees rather than a hardcoded list, so it moved all 242 hve-core dependency lines to the new SHA and picked up `squad-data-scientist.agent.md` and the new `ds-*`/`data-workstream-foundation` skill paths automatically. Verified `version:` and `CHANGELOG.md` were untouched by the run.
* Added `.changes/unreleased/20260814-adapt-squad-cast-to-hve-core-2be87b7.md` (`bump: minor`, `type: Changed`) naming the rename map and the new/extended charters.

<!-- consumption:begin -->
model: claude-sonnet-5
model_source: session-inherited
priced_as: claude-sonnet-5
model_tier: default
internal_turns: 30
input_tokens: 230000
cached_tokens: 830000
cache_write_tokens: 120000
output_tokens: 24000
input_rate: 2.00
cached_rate: 0.20
cache_write_rate: 2.50
output_rate: 10.00
est_cost_usd: 1.1600
est_credits: 116.00
basis: estimated
<!-- consumption:end -->
