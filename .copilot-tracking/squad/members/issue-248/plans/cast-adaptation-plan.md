# Plan: Adapt squad cast to hve-core f425e94 (issue #248)

Date: 2026-11-10 · Role: lead · Research: `../research/2026-11-10/cast-delta-research.md`

## Decision

Drop the dead `PowerPoint Subagent` / `PowerPoint Builder` references and the `powerpoint` skill references. Do **not** author a replacement `Squad Presenter` charter (out of scope; acceptance criteria only require every roster Primary to resolve to a dispatchable agent and no dangling references). The `presenter` role is removed from the catalog and seeds rather than redirected. Skill references are reworded to state the upstream skill no longer exists and to name the limitation.

Council: **NOT applicable.** No architect, security, cost-manager, product-owner, or rai roles are on this roster. The change is a mechanical cast/reference repoint with no cross-domain architecture, security, cost, product, or RAI risk beyond normal review.

## Phases

1. **Edit squad-src** (steps 1–9): remove or reword references. Developer.
2. **Repin and fragment** (steps 10–12): regenerate apm.yml, add change fragment, sweep docs. Developer.
3. **Review** (step 13 plus grep sweep): cast delta confirms non-BREAKING. Tester.
4. **Scribe**: record history, decisions, and state.

Success criteria: no literal `PowerPoint Subagent`, `PowerPoint Builder`, or live `powerpoint` skill reference remains in squad-src except explicit "removed upstream" notes. Cast delta shows no BREAKING rows.

## File-by-file edits

| # | File | Edit |
|---|---|---|
| 1 | `squad-src/.github/skills/squad/references/roster-catalog.md` | Line 23: drop `PowerPoint Builder` from the non-dispatchable orchestrator example list (keep the sentence grammatical). Line 49: remove the `presenter` row. Line 402: remove the `presenter (PowerPoint Subagent)` role-menu line. |
| 2 | `squad-src/.github/agents/squad/squad-coordinator.agent.md` | Line ~48: remove `PowerPoint Subagent` from the `agents:` frontmatter list. |
| 3 | `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md` | Line ~48: same removal. |
| 4 | `squad-src/.github/skills/squad/references/seed-templates.md` | Line ~61: remove the presenter seed row (`PowerPoint Subagent`, `.copilot-tracking/ppt/<date>/<slug>/`). |
| 5 | `squad-src/.github/skills/squad/SKILL.md` | Line ~23: remove `PowerPoint Subagent` from the deployed cast list. |
| 6 | `squad-src/.github/instructions/squad/squad-roster.instructions.md` | Line ~165: replace the `presenter` / `powerpoint` skill-pipeline Deliverable Roots example with another agent-derived-path example already on the roster, or drop it. Line ~181: replace the one-to-one example `presenter → PowerPoint Subagent` with `privacy → Privacy Planner` (already listed). |
| 7 | `squad-src/.github/instructions/squad/pptx-brand-template.instructions.md` | Lines 2, 6, 8, 12 (and 14, 26, 45, 46 where they name the removed agents or skill): remove the `PowerPoint Builder` / `PowerPoint Subagent` names. State that the `powerpoint` skill (`build_deck.py`, `Invoke-PptxPipeline.ps1`) was removed upstream at hve-core f425e94, so the squad has no deck pipeline. Keep the brand-template guidance as reference only for consumers who supply their own pptx tooling. Do not delete the file or the template asset. |
| 8 | `squad-src/.github/instructions/squad/squad-autopilot.instructions.md` | Line ~71: reword "built by the `powerpoint` skill pipeline" to a neutral statement that no deck-building skill ships (the `powerpoint` skill was removed upstream). Keep any link to the brand instruction consistent with edit 7. |
| 9 | `squad-src/.github/skills/sql-migration-advisor/SKILL.md` | Line ~78: replace "hand off to the `powerpoint` skill" with a note that the skill was removed upstream and slide production is out of scope; the report remains a Markdown deliverable. |
| 10 | `apm.yml` (via script only) | `pwsh scripts/Update-ApmDependencies.ps1 -Ref f425e943bf228052a23e6bc4810b5faef030314f`. Do not hand-edit dependencies. Do not touch `version:`. Verify the pptx agent, pptx-subagent, `powerpoint` skill, and likely `pptx.instructions.md` entries vanish, and `hve-slides` and any new `rpi` skill are present. |
| 11 | `.changes/unreleased/` fragment | `pwsh scripts/New-ChangeFragment.ps1 -Type Changed -Bump minor -Title 'adapt squad cast to hve-core f425e94' -Body '<bullets: repin to f425e94; drop PowerPoint Builder/Subagent and the presenter role; powerpoint skill references reworded as removed upstream>'`. Never edit `CHANGELOG.md` or the `apm.yml` `version:`. |
| 12 | `docs/`, `README.md`, `CONTRIBUTING.md` | Grep for `PowerPoint Subagent`, `PowerPoint Builder`, `powerpoint`, and `presenter`. Research found hits in `docs/usage.html`, `docs/concepts.html`, `docs/demo-3.html`, `docs/ppt-templates.html`, and `docs/fr/*`. Update live-cast statements (EN and FR together) or record "none apply" per file. Do not rewrite CHANGELOG history. |
| 13 | Verification | `pwsh scripts/Get-HveCoreCastDelta.ps1 -ToRef f425e943bf228052a23e6bc4810b5faef030314f`. Expect a non-BREAKING verdict. |

Also: grep squad-src for any other `presenter` mentions, and review `tests/squad-behavior-contract.md:610` and `tests/tier0/baselines/prefill-baseline.json`. They may need a baseline refresh if the coordinator `agents:` edit shifts the prefill; flag it rather than guess if a test fails. Do not hand-delete generated outputs (`.agents/skills/powerpoint`, `.github/agents/pptx*`).

## Deliverables (execution order)

| # | Deliverable | Owner | Artifact | Depends on | Batch |
|---|---|---|---|---|---|
| D1 | Squad-src reference removals/rewording (edits 1–9) | developer | the nine squad-src files above | none | A |
| D2 | Docs/README/CONTRIBUTING sweep (edit 12) | developer | updated `docs/**`, or a "none apply" note | none (parallel with D1) | A |
| D3 | apm.yml repin (edit 10) | developer | regenerated `apm.yml` dependencies | D1 | B |
| D4 | Change fragment (edit 11) | developer | `.changes/unreleased/*.md` | D1–D3 | B |
| D5 | Cast-delta verification and grep sweep (edit 13) | tester | verdict in the review notes | D1–D4 | C |
| D6 | State/history/decisions entry | scribe | `.copilot-tracking/squad/members/issue-248/{history,decisions.md,state.json}` | D5 | D |

Only one artifact-owning role (developer) appears besides tester and scribe.

## Implement Shape

`single-build`. One owning role (developer) does all edits in one coherent change set; D1 and D2 are independent file groups and can go in one pass. The tester follows.

## Assumptions and Open Decisions

* ASM-1: Docs may reference the removed names. The developer's grep decides which docs need edits; if hits are historical only, record "none apply".
* ASM-2: Upstream removals and the `hve-slides` flip come from the issue and are unverified until the cast delta runs. If the delta reports additional removals (for example `pptx.instructions.md`), the developer addresses them within this same change.
* ASM-3: Removing the `presenter` role is a capability removal; the `minor` bump is accepted as instructed.
* ASM-4: Tier-0 test baselines may need regeneration if prefill changes.
* Deferred, out of scope: a future `Squad Presenter` charter wrapping `hve-slides`.

## Gaps in Research

* No upstream hve-core fetch was performed, so the removals are unverified (see ASM-2).
* Exact docs hit lines were not enumerated (see ASM-1).
