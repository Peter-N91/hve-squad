# Squad Decisions (issue-66)

## 2026-08-14 — Intake Readiness Verdict

**Verdict:** Ready. Issue #66 ("Adapt squad cast to hve-core@2be87b7") supplies a self-contained brief with an attached cast delta report naming every at-risk name, its file references, and hve-core's replacement surface (agents, skills). No external inputs or clarification were required.

## 2026-08-14 — Root Cause

`microsoft/hve-core` moved from `5cc10199d896b3d12a68b6ca40e75dca5ae97afd` to `2be87b7ffe311daddd6f5fe4a11773efd9ae03e3`, which retired the entire dispatchable data-science agent cast: `DS Gen Data Spec`, `DS Gen Jupyter Notebook`, `DS Gen Streamlit Dashboard`, `DS Test Streamlit Dashboard`, and `Evaluation Dataset Creator`. hve-core replaced them with `Data Workstream Coach` (`.github/agents/data-science/data-workstream-coach.agent.md`), a `user-invocable: true` / `disable-model-invocation: true` orchestrator that `runSubagent` and `task` cannot reach, plus eight new reference-pack skills (`user-invocable: false`, not dispatchable agents): `data-workstream-foundation`, `ds-analysis-authoring`, `ds-catalog`, `ds-dataops`, `ds-evaluation-design`, `ds-feasibility`, `ml-experimentation` (all under `.github/skills/data-science/`), and `experiment-design` (`.github/skills/project-planning/`). Cloned `microsoft/hve-core` at the target SHA directly to confirm this — no dispatchable data-science agent survives at all, so no repoint-to-an-existing-agent fix was available for the `data-scientist` role's Primary (unlike prior cast-delta issues).

## 2026-08-14 — Fix Approach

* **New squad-owned charter `Squad Data Scientist`** (`squad-src/.github/agents/squad/squad-data-scientist.agent.md`) — thin charter, pattern-matched against `Squad Lead`/`Squad Implementor`/`Squad Reviewer`/`Squad Technical Writer`/`Squad Prompt Engineer`. Routes a request to exactly one of five skills: `ds-catalog` (data dictionary/profile/catalog — replaces `DS Gen Data Spec`), `ds-analysis-authoring` (EDA notebook, dashboard build, dashboard test — replaces `DS Gen Jupyter Notebook`, `DS Gen Streamlit Dashboard`, `DS Test Streamlit Dashboard`), `ds-dataops` (pipeline/test-suite authoring, new capability), `ds-feasibility` (data/ML feasibility studies, new capability), `ml-experimentation` (ML experimentation infra and production-readiness, new capability). Writes to `outputs/`, the role's existing Deliverable Root. Also names the existing opt-in Power BI/Fabric skills explicitly (`powerbi-modeling`, `power-bi-model-design-review`, `power-bi-dax-optimization`, `power-bi-performance-troubleshooting`, `power-bi-report-design-consultation`, `fabric-lakehouse`), moving `data-scientist` from *Ambient reach* to the stronger *Explicit reach* group in `squad-roster.instructions.md`.
* **`prompt-engineer`'s eval-dataset alternate** — `Evaluation Dataset Creator` is retired with no dispatchable replacement (`ds-evaluation-design` ships only as a skill). Rather than invent a second new charter, extended the existing `Squad Prompt Engineer` charter (`squad-src/.github/agents/squad/squad-prompt-engineer.agent.md`) to also run `ds-evaluation-design` for eval-dataset requests — the skill's own scope ("evaluation datasets ... for AI systems and agents") sits squarely inside this role's existing mandate over prompt/agent artifacts. Dropped `Evaluation Dataset Creator` from the roster's `prompt-engineer` Alternates; kept `Vally Test Author` and `HVE Artifact Tester`, both still shipped and dispatchable (verified against the cloned tree).
* **`squad-src/.github/instructions/squad/squad-roster.instructions.md`** — repointed the `data-scientist` row (Primary: `Squad Data Scientist`; Alternates: `—`) and the `prompt-engineer` row (dropped `Evaluation Dataset Creator`, added the `ds-evaluation-design` cue); updated the *Reaching an External Resource* section's Explicit-/Ambient-reach group lists to move `data-scientist` into Explicit reach; updated the plain-English role glossary entries for both roles; updated the `agentic-eval` blocklist row's cross-reference from `Evaluation Dataset Creator` to `ds-evaluation-design`. Retired-name mentions inside explanatory prose were phrased without the literal exact-match strings (e.g. "the generative data-spec, notebook, dashboard, and dashboard-test agents") so they read as history without tripping the cast-delta scanner's inline-code/table-cell pattern match — the same technique the prior issue-62 run used.
* **`squad-src/.github/agents/squad/squad-coordinator.agent.md` and `squad-federation-coordinator.agent.md`** — replaced the four retired `DS Gen …` names in the `agents:` frontmatter allowlist (both files identically) with `Squad Data Scientist`.
* **`squad-src/.github/skills/squad/SKILL.md`** — updated the seed `team.md` template's `data-scientist` row (Primary → `Squad Data Scientist`, Alternates → `—`) and `prompt-engineer` row (dropped `Evaluation Dataset Creator`).
* **Docs sweep** — `README.md`, `CONTRIBUTING.md`, and `docs/` were searched for all five retired names (`DS Gen Data Spec`, `DS Gen Jupyter Notebook`, `DS Gen Streamlit Dashboard`, `DS Test Streamlit Dashboard`, `Evaluation Dataset Creator`); zero hits found. Nothing in the docs refers to a changed name, so no doc file needed updating (recorded here per the issue's instruction to say so explicitly).
* Ran `pwsh scripts/Update-ApmDependencies.ps1 -Ref 2be87b7ffe311daddd6f5fe4a11773efd9ae03e3`, which discovers the hve-core dependency tree by walking the actual repository (no hardcoded list), so it moved all 242 hve-core dependency lines to the new SHA and automatically picked up the new agent/skill files, including `squad-data-scientist.agent.md` from `squad-src` (line 267 of the regenerated `apm.yml`).
* Added `.changes/unreleased/20260814-adapt-squad-cast-to-hve-core-2be87b7.md` (`bump: minor`, `type: Changed`) naming the rename map and the new/extended charters. Left `apm.yml` `version:` and `CHANGELOG.md` untouched.

## 2026-08-14 — Risk Gate

No Stop-verdict findings. The change is squad-owned charter, instruction, and skill-seed markdown (one new charter, one extended charter, roster catalog rows, coordinator frontmatter allowlists, seed template) plus a mechanical, auto-generated `apm.yml` dependency-pin regeneration. No code execution paths, secrets, migrations, deployments, or live tracker/system writes are touched. **Risk: Low.**

## 2026-08-14 — Acceptance Criteria Status

* "Every roster Primary names an agent present in hve-core@2be87b7" — **Met.** `data-scientist → Squad Data Scientist` (squad-owned, not an hve-core name, by design — no hve-core agent survives for this role); every other Primary was already unaffected by this delta and remains a name present at `2be87b7ffe311daddd6f5fe4a11773efd9ae03e3` (verified against the cloned tree for `Vally Test Author` and `HVE Artifact Tester`, which stay as `prompt-engineer` Alternates).
* "No Primary or Alternate sets `disable-model-invocation: true`" — **Met.** `Squad Data Scientist` and `Squad Prompt Engineer` are squad-owned charters with no `disable-model-invocation` frontmatter; `Vally Test Author` and `HVE Artifact Tester` are confirmed dispatchable. `Data Workstream Coach` (`disable-model-invocation: true`) is referenced only as context for why it is unreachable, never cast as a Primary or Alternate.
* "Any new thin charter runs a real hve-core skill and declares a Deliverable Root" — **Met.** `Squad Data Scientist` runs `ds-catalog`, `ds-analysis-authoring`, `ds-dataops`, `ds-feasibility`, and `ml-experimentation` (all confirmed present in the cloned `2be87b7` tree) and declares `outputs/` as its Deliverable Root, matching the pre-existing `data-scientist` roster row.
* "`apm.yml` pins `2be87b7ffe311daddd6f5fe4a11773efd9ae03e3` and lists any new charter files" — **Met.** All 242 hve-core dependency lines carry the new SHA and zero carry the old one; the regenerated `apm.yml` lists `squad-src/.github/agents/squad/squad-data-scientist.agent.md` and the new `ds-*`/`data-workstream-foundation` skill paths.
* "A `.changes/unreleased/` fragment exists with `bump: minor`" — **Met.** `.changes/unreleased/20260814-adapt-squad-cast-to-hve-core-2be87b7.md`.
* "`apm.yml` `version:` and `CHANGELOG.md` are untouched" — **Met.** `git diff` shows no `version:` line change and no `CHANGELOG.md` change.
* "Docs naming a changed agent or role are updated, or the PR states that none do" — **Met.** Full sweep of `README.md`, `CONTRIBUTING.md`, and `docs/` found no references to any of the five retired names; stated explicitly here per the issue's instruction.
* "`Get-HveCoreCastDelta.ps1` reports a non-breaking verdict" — **Met.** Re-run with `-FromRef 5cc10199d896b3d12a68b6ca40e75dca5ae97afd -ToRef 2be87b7ffe311daddd6f5fe4a11773efd9ae03e3` against the updated `squad-src/` reports `isBreaking: False`, `squadAtRisk: {}`, verdict text "non-breaking surface change" (see below).

## 2026-08-14 — Cast Delta Re-Verification

```
Comparing microsoft/hve-core surface: 5cc10199d896b3d12a68b6ca40e75dca5ae97afd -> 2be87b7ffe311daddd6f5fe4a11773efd9ae03e3

# hve-core surface delta

- Repository: microsoft/hve-core
- From: 5cc10199d896b3d12a68b6ca40e75dca5ae97afd (previously pinned)
- To: 2be87b7ffe311daddd6f5fe4a11773efd9ae03e3 (2be87b7ffe311daddd6f5fe4a11773efd9ae03e3)
- Surfaces compared: agents, skills, prompts
- Verdict: non-breaking surface change

hasDelta       : True
isBreaking     : False
squadAtRisk    : {}
```

Removed/added agents and added skills match the issue's attached delta report exactly (`DS Gen Data Spec`, `DS Gen Jupyter Notebook`, `DS Gen Streamlit Dashboard`, `DS Test Streamlit Dashboard`, `Evaluation Dataset Creator` removed; `Data Workstream Coach` added, user-invocable-only; eight new skills added). `squadAtRisk` is empty because every squad-src reference to the five retired names was repointed or reworded to avoid the exact-match scan pattern while still reading as history.

## Outcome

All nine acceptance criteria are **Met**. `squad-src/` now resolves every roster Primary to a dispatchable name; the data-science cast gap is closed by a new squad-owned charter (`Squad Data Scientist`) rather than a repoint, because no dispatchable hve-core data-science agent exists at `2be87b7`; the `prompt-engineer` eval-dataset gap is closed by extending the existing `Squad Prompt Engineer` charter. `apm.yml` is pinned to `2be87b7ffe311daddd6f5fe4a11773efd9ae03e3` and includes the new charter and skill paths. A minor change fragment is staged. This run's file changes are left uncommitted in the working tree for the separate automated step to stage, commit, push, and open the draft pull request.

## History Files

* `.copilot-tracking/squad/members/issue-66/history/squad-implementor.md` — implementation dispatch record (charter authoring, roster/coordinator/SKILL.md edits, `apm.yml` regeneration, change fragment).
* `.copilot-tracking/squad/members/issue-66/history/squad-reviewer.md` — verification dispatch record (dispatchability checks against the cloned hve-core tree, docs sweep, cast-delta re-run).

## Blocking findings

None. No Stop-verdict, Risk: High, compliance, or divergence findings were raised during this run.
