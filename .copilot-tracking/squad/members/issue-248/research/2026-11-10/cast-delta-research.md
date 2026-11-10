# Research: Adapt squad cast to hve-core@f425e94 (issue #248)

Date: 2026-11-10 · Role: researcher · Lanes: none dispatched (bounded single-thread workspace trace, done directly). No remote hve-core fetch was performed, so the upstream removals are taken from the issue text and are **unverified** here.

## Scope and non-goals

Scope: find every squad-owned reference to the removed `PowerPoint Builder`, `PowerPoint Subagent` and `powerpoint` skill, and recommend a replacement strategy. Non-goals: editing files, running scripts, committing.

## (a) Confirmed references (squad-src + apm.yml)

### squad-src (literal matches)

| File | Line | Reference |
|---|---|---|
| `squad-src/.github/skills/squad/references/roster-catalog.md` | 23 | `PowerPoint Builder` named as a non-dispatchable orchestrator example |
| same | 49 | `presenter` row: Primary `PowerPoint Subagent`; notes `powerpoint` skill pipeline; mentions `PowerPoint Builder` |
| same | 402 | `presenter (PowerPoint Subagent)` role-menu line, "PowerPoint skill pipeline" |
| `squad-src/.github/agents/squad/squad-coordinator.agent.md` | 48 | `PowerPoint Subagent` in `agents:` frontmatter list |
| `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md` | 48 | same, `agents:` list |
| `squad-src/.github/skills/squad/references/seed-templates.md` | 61 | presenter seed row, `PowerPoint Subagent`, path `.copilot-tracking/ppt/<date>/<slug>/` |
| `squad-src/.github/instructions/squad/pptx-brand-template.instructions.md` | 2, 6, 8, 12 (also 14, 26, 45, 46 pptx/PowerPoint wording) | `PowerPoint Builder`/`PowerPoint Subagent` in description and body; line 12 binds decks to the `powerpoint` skill (`build_deck.py`, `Invoke-PptxPipeline.ps1`) |
| `squad-src/.github/instructions/squad/squad-autopilot.instructions.md` | 71 | "built by the `powerpoint` skill pipeline" |
| `squad-src/.github/instructions/squad/squad-roster.instructions.md` | 165 | Deliverable Roots: `presenter`, `powerpoint` skill pipeline derives its own output path |
| same | 181 | One-to-one example `presenter → PowerPoint Subagent` |
| `squad-src/.github/skills/sql-migration-advisor/SKILL.md` | 78 | "hand off to the `powerpoint` skill" |

### Gaps in the issue's list

* `squad-src/.github/skills/squad/SKILL.md` line 23 lists `PowerPoint Subagent` in the deployed cast. **Missing from the issue.**
* `apm.yml` pins removed artifacts: line 38 `agents/experimental/pptx.agent.md`, line 39 `agents/experimental/subagents/pptx-subagent.agent.md`, line 97 `instructions/experimental/pptx.instructions.md`, line 151 `skills/experimental/powerpoint`. Line 164 pins `skills/hve-slides`. Line 254 is the squad's own `pptx-brand-template.instructions.md` (squad-owned). `pptx.instructions.md` (line 97) is probably removed too; confirm via the cast delta.
* No hits in `squad-routing.instructions.md`, `squad.prompt.md`; `tests/squad-behavior-contract.md:610` mentions only the role `presenter`.
* Outside squad-src: `docs/usage.html`, `docs/concepts.html`, `docs/demo-3.html` and `docs/fr/*` mention powerpoint/presenter; `docs/ppt-templates.html` is referenced by CHANGELOG. CHANGELOG history lines must not be rewritten.

## (b) Replacement strategy

Facts about the installed tree (old pin 17072823):

* `.github/agents/` holds installed agents (including the pptx ones, from apm.yml 38/39). No agent there can replace PowerPoint duties.
* `.github/skills/` does not exist; skills are installed at `.agents/skills/`. `.agents/skills/powerpoint/` exists (old pin copy; disappears when the pin moves). `.agents/skills/hve-slides/` exists; at the old pin it is already `user-invocable: true` + `disable-model-invocation: true` (the issue says it flips to model-invocable at f425e94, unverified). `hve-slides` produces HTML decks about HVE Core under `slides/`, not general .pptx decks. No other pptx-capable skill is installed.
* apm.yml (generated) is the sole source of the hve-core artifacts; the squad has no vendored copy.

| Reference | Strategy |
|---|---|
| `presenter` Primary (roster-catalog:49, :402; seed-templates:61; roster.instructions:181; squad/SKILL.md:23) | No hve-core agent can replace it. Options: (1) new squad-owned thin charter (e.g. `Squad Presenter`) wrapping `hve-slides` (HTML decks; scope change from .pptx), if the deck capability must survive; (2) mark `presenter` Deferred/unavailable (like the Deferred Reviewer-Class table) and report the gap. Decide at Plan stage (product decision). |
| coordinator and federation-coordinator `agents:` line 48 | Remove `PowerPoint Subagent`; if a charter is authored, add its name to both lists. |
| roster-catalog:23 | Drop `PowerPoint Builder` from the non-dispatchable example list. |
| `pptx-brand-template.instructions.md` | Premise (python-pptx `powerpoint` pipeline, `.github/brand/pptx-brand-template.pptx`) is void without the skill. Delete (with apm.yml:254 entry and docs/ppt-templates.html) or retarget to the new presenter path. |
| `squad-autopilot.instructions.md:71` | Reword to the new presenter mechanism or remove; drop the brand-instruction link if that file goes. |
| `squad-roster.instructions.md:165, 181` | 165: replace the `powerpoint` example with another agent-builds-own-path case or the new skill. 181: swap the one-to-one example (e.g. `privacy → Privacy Planner`, already listed). |
| `sql-migration-advisor/SKILL.md:78` | Repoint to the `presenter` role/`hve-slides`, or drop the slide handoff. |
| new `rpi` skill | Additive, no breakage. Optional follow-up for the `rpi-*` charters. |

## (c) apm.yml pin mechanism

* Current pin: all `microsoft/hve-core/...#17072823c75d6e8cdf288d8ed4371f555dcd09bb`; `version: 0.20.0`.
* `scripts/Update-ApmDependencies.ps1` regenerates only `dependencies.apm`: clones hve-core at `-Ref`, filters `.github` folders, appends the curated external cast allowlist, then enumerates squad-src. `-Ref` defaults to the already-pinned SHA (adding squad files does not move the pin); moving the pin is a separate reviewed step, which the scheduled sync workflow does with an explicit `-Ref` after running the cast delta. Entries for removed upstream files vanish on regeneration.
* Related: `Test-HveCorePin.ps1` (verify installed bytes vs pin), `Set-SquadSelfRefPin.ps1`, `Build-SquadPlugin.ps1`. Contributors do not hand-edit `apm.yml` version or `CHANGELOG.md`; they add a change fragment.

## (d) Verification scripts (not executed)

* `scripts/Get-HveCoreCastDelta.ps1` exists. Params: `-FromRef` (default: SHA pinned in apm.yml), `-ToRef` (default `main`), `-ApmFile`, `-RepoSlug`, `-SquadSourceRoot`, `-MarkdownPath`, `-JsonPath`, `-GitHubOutput`. Example: `./scripts/Get-HveCoreCastDelta.ps1 -ToRef f425e943bf228052a23e6bc4810b5faef030314f -MarkdownPath delta.md`. Read-only; diffs agents (`name:`, dispatchability), skills (id, invocability) and prompts, and flags BREAKING any removed/uninvocable id still referenced in squad-src. Needs pwsh 7+ and network. Run before moving the pin and again after the fix (expect no BREAKING rows).
* `scripts/New-ChangeFragment.ps1` exists. Writes a fragment under `.changes/unreleased/` (`apm run change`, or `./scripts/New-ChangeFragment.ps1 -Type Changed -Bump patch -Title '...' -Body '- ...'`). Per its help, a new agent/skill under an already-shipped idea is `patch`; `minor` is for a new capability class. Removing the deck capability might warrant a higher bump; decide at Plan. `.changes/unreleased/` was not present at research time.

## Thin-charter feasibility

Feasible. `squad-technical-writer.agent.md` template: frontmatter `name`, `description`, `user-invocable: false`, `model`; body says to run the named skill, with steps and a "Return to the coordinator" Response Format. It needs no hve-core agent, only the skill's `SKILL.md` deployed. Roster Dispatchability (lines 98–105) explicitly blesses charters wrapping skills, and a user-invocable `disable-model-invocation: true` skill may be followed by re-reading its `SKILL.md` each dispatch and escalating to the user if absent. A new charter must also be added to both coordinators' `agents:` lists, the roster-catalog Primary column, Deliverable Roots/seed-templates, and the charter list at roster.instructions:104; `Update-ApmDependencies.ps1` picks up squad-src files automatically.

## Open risks and assumptions

1. Upstream facts (removals, `hve-slides` flip, `rpi` addition) come from the issue and are unverified; run the cast delta to confirm, including `pptx.instructions.md` and any removal the issue missed.
2. `hve-slides` is HTML/HVE-Core-focused, not general .pptx; wrapping it changes `presenter` scope and requires docs updates (EN+FR usage/concepts/demo-3/ppt-templates).
3. `tests/squad-behavior-contract.md` and `tests/tier0/baselines/prefill-baseline.json` reference `presenter`/powerpoint; coordinator `agents:` edits may shift the prefill baseline.
4. A coordinator `agents:` entry for a missing agent may break frontmatter resolution; adapt and move the pin in the same change.
5. `.agents/skills/powerpoint` and `.github/agents/pptx*` are generated outputs; do not hand-delete.
