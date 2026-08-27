# Squad Decisions (issue-104)

## 2026-08-27 — Bootstrap and Intake Readiness

**Bootstrap:** Watch Mode Bootstrap ran against `.copilot-tracking/squad/members/`; no existing federation or single squad was recorded for this trigger, so a new sub-squad `issue-104` was seeded (`team.md`, `routing.md`, `state.json`, `consumption-rates.md`), scoped to `.copilot-tracking/squad/members/issue-104/`, matching the pattern of the prior cast-delta sub-squads (`issue-49`, `issue-62`, `issue-66`).

**Verdict:** Ready. Issue #104 ("Adapt squad cast to hve-core@8692fe3") supplies a self-contained brief with an attached cast delta report naming every at-risk name, its file references, and hve-core's replacement surface (agents, skills). No external inputs or clarification were required.

## 2026-08-27 — Root Cause

`microsoft/hve-core` moved from `7cc6dc42caf7f842e1f7aa9f3d41cb4581538f33` to `8692fe38cc0415ff8d21aa1b5d8198f008cd4038`. Verified directly against a clone of the target SHA:

* **`Data Workstream Coach`** (`.github/agents/data-science/data-workstream-coach.agent.md`) is removed outright — not renamed, gone. Its replacement, **`Data Science and Engineering Coach`** (`.github/agents/data-science-engineering/data-science-engineering-coach.agent.md`), is `user-invocable: true` / `disable-model-invocation: true`, so still unreachable by `runSubagent`/`task`.
* **`Supply Chain Reviewer`** (`.github/agents/security/supply-chain-reviewer.agent.md`) is removed outright with no replacement agent at all. `SSSC Planner` and `Supply Chain Skill Assessor`, the two subagents that already cover its ground, are unaffected.
* The entire `data-science` skill directory was renamed to `data-science-engineering`, and five ids the squad references were renamed with it: `ds-catalog` → `data-catalog`, `ds-analysis-authoring` → `analysis-authoring`, `ds-dataops` → `dataops`, `ds-feasibility` → `feasibility`, `ds-evaluation-design` → `evaluation-design`. `data-workstream-foundation` also renamed (to `data-science-engineering-foundation`) but was never referenced by squad-src, and `ml-experimentation` kept its id and only moved directory, so neither needed an edit.

Unlike the prior `issue-66` cast delta (where the entire data-science agent cast was retired with zero dispatchable successor and a brand-new charter had to be authored), this delta is a **pure rename**: `Squad Data Scientist` and `Squad Prompt Engineer` already exist as squad-owned charters from that earlier run and only needed their skill ids repointed to survive.

## 2026-08-27 — Fix Approach

* **`squad-src/.github/agents/squad/squad-data-scientist.agent.md`** — mechanically renamed all five `ds-*` skill ids to their `data-science-engineering` equivalents throughout (description frontmatter, rationale paragraph, Purpose bullet, Step 1 routing list). Reworded the `Data Workstream Coach` rationale sentence to describe the non-dispatchable coach orchestrator generically, since the retired name no longer exists to cite.
* **`squad-src/.github/agents/squad/squad-prompt-engineer.agent.md`** — mechanically renamed `ds-evaluation-design` → `evaluation-design` everywhere it appears.
* **`squad-src/.github/instructions/squad/squad-roster.instructions.md`** — renamed the same skill ids in the `data-scientist` and `prompt-engineer` rows and the `agentic-eval` blocklist cross-reference; reworded the `data-scientist` row's `Data Workstream Coach` mention the same way as the charter; rewrote *Deferred Reviewer-Class Agents* — dropped the `Supply Chain Reviewer` row, corrected "Five" to "Four" agents, and added a paragraph stating the fifth reviewer-class agent was removed outright at `8692fe38cc0415ff8d21aa1b5d8198f008cd4038` with its coverage already absorbed by `SSSC Planner`/`Supply Chain Skill Assessor`.
* **`squad-coordinator.agent.md` / `squad-federation-coordinator.agent.md`** — checked, not edited: both already list `Squad Data Scientist` and `Squad Prompt Engineer` in their `agents:` frontmatter from the prior `issue-66` run, and neither lists any name this delta retires.
* **`squad-src/.github/skills/squad/SKILL.md`, `references/seed-templates.md`, `squad-routing.instructions.md`** — checked, not edited: all name `Squad Data Scientist`/`Squad Prompt Engineer` as Primaries without hardcoding a skill id.
* **Docs sweep** — `README.md`, `CONTRIBUTING.md`, and `docs/` were searched for all seven at-risk names; zero hits found. Nothing in the docs refers to a changed name, so no doc file needed updating (recorded here per the issue's instruction to say so explicitly).
* Ran `pwsh scripts/Update-ApmDependencies.ps1 -Ref 8692fe38cc0415ff8d21aa1b5d8198f008cd4038`, which walks the actual hve-core and squad-src trees rather than a hardcoded list, so it moved all 243 hve-core dependency lines to the new SHA and picked up the renamed `data-science-engineering` agent, prompt, and skill paths automatically.
* Added `.changes/unreleased/20260827-adapt-squad-cast-to-hve-core-8692fe3.md` (`bump: minor`, `type: Changed`) naming the rename map. Left `apm.yml` `version:` and `CHANGELOG.md` untouched.

## 2026-08-27 — Risk Gate

No Stop-verdict findings. The change is a mechanical rename across three squad-owned markdown files (two charters, one roster catalog) plus an auto-generated `apm.yml` dependency-pin regeneration and a documentation-only change fragment. No code execution paths, secrets, migrations, deployments, or live tracker/system writes are touched. **Risk: Low.**

## 2026-08-27 — Acceptance Criteria Status

* "Every roster Primary names an agent present in hve-core@8692fe3" — **Met.** `Squad Data Scientist` and `Squad Prompt Engineer` are squad-owned charters (not hve-core names, by design, inherited unchanged from `issue-66`); every other Primary was unaffected by this delta and remains present at `8692fe38cc0415ff8d21aa1b5d8198f008cd4038` (verified against the cloned tree).
* "No Primary or Alternate sets `disable-model-invocation: true`" — **Met.** Neither charter sets it; `Data Science and Engineering Coach` and the retired `Data Workstream Coach`/`Supply Chain Reviewer` are referenced only as rationale prose, never cast as a Primary or Alternate.
* "Any new thin charter runs a real hve-core skill and declares a Deliverable Root" — **Met (no new charter needed).** No new charter was authored — this delta only required repointing five skill ids inside the two charters `issue-66` already created. `Squad Data Scientist` now runs `data-catalog`, `analysis-authoring`, `dataops`, `feasibility`, and `ml-experimentation` (all confirmed present at the target SHA) and still declares `outputs/` as its Deliverable Root.
* "`apm.yml` pins `8692fe38cc0415ff8d21aa1b5d8198f008cd4038` and lists any new charter files" — **Met.** All 243 hve-core dependency lines carry the new SHA and zero carry the old one; no new charter file was added, so none needed to be newly listed, but the regenerated manifest correctly lists the renamed `data-science-engineering` agent/prompt/skill paths.
* "A `.changes/unreleased/` fragment exists with `bump: minor`" — **Met.** `.changes/unreleased/20260827-adapt-squad-cast-to-hve-core-8692fe3.md`.
* "`apm.yml` `version:` and `CHANGELOG.md` are untouched" — **Met.** `git diff` shows no `version:` line change (`0.16.2`) and no `CHANGELOG.md` change.
* "Docs naming a changed agent or role are updated, or the PR states that none do" — **Met.** Full sweep of `README.md`, `CONTRIBUTING.md`, and `docs/` found no references to any of the seven at-risk names; stated explicitly here per the issue's instruction.
* "`Get-HveCoreCastDelta.ps1` reports a non-breaking verdict" — **Met.** Re-run with `-FromRef 7cc6dc42caf7f842e1f7aa9f3d41cb4581538f33 -ToRef 8692fe38cc0415ff8d21aa1b5d8198f008cd4038` against the updated `squad-src/` reports `isBreaking: False`, `squadAtRisk: {}`, verdict text "non-breaking surface change" (see below).

## 2026-08-27 — Cast Delta Re-Verification

```
Comparing microsoft/hve-core surface: 7cc6dc42caf7f842e1f7aa9f3d41cb4581538f33 -> 8692fe38cc0415ff8d21aa1b5d8198f008cd4038

# hve-core surface delta

- Repository: microsoft/hve-core
- From: 7cc6dc42caf7f842e1f7aa9f3d41cb4581538f33 (currently pinned)
- To: 8692fe38cc0415ff8d21aa1b5d8198f008cd4038 (8692fe38cc0415ff8d21aa1b5d8198f008cd4038)
- Surfaces compared: agents, skills, prompts
- Verdict: non-breaking surface change

hasDelta       : True
isBreaking     : False
squadAtRisk    : {}
```

Removed/added agents and skills match the issue's attached delta report exactly (`Data Workstream Coach`, `Supply Chain Reviewer` removed; `Data Science and Engineering Coach` added, user-invocable-only; six `data-science` skills removed and replaced by six `data-science-engineering` skills). `squadAtRisk` is empty because every squad-src reference to the five retired skill ids was renamed and every reference to the two retired agent names was reworded to avoid the exact-match scan pattern while still reading as accurate history.

## Outcome

All eight acceptance criteria are **Met**. `squad-src/` now resolves every roster Primary to a dispatchable name; this delta required no new squad-owned charter, because `Squad Data Scientist` and `Squad Prompt Engineer` (authored for the unrelated, more severe `issue-66` delta) already existed and only needed their `ds-*` skill ids repointed to the renamed `data-science-engineering` equivalents. `apm.yml` is pinned to `8692fe38cc0415ff8d21aa1b5d8198f008cd4038`. A minor change fragment is staged. This run's file changes are left uncommitted in the working tree for the separate automated step to stage, commit, push, and open the draft pull request.

## History Files

* `.copilot-tracking/squad/members/issue-104/history/Squad Implementor.md` — implementation dispatch record (skill-id renames, roster/deferral-table edits, `apm.yml` regeneration, change fragment).
* `.copilot-tracking/squad/members/issue-104/history/Squad Reviewer.md` — verification dispatch record (dispatchability re-check against the cloned hve-core tree, docs sweep, cast-delta re-run).
* `.copilot-tracking/squad/members/issue-104/history/Squad Scribe.md` — orchestration record for the turn that seeded this sub-squad and rewrote its ledger.

## Blocking findings

None. No Stop-verdict, Risk: High, compliance, or divergence findings were raised during this run.
