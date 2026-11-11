# Change record: cast adaptation to hve-core f425e94 (issue #248)

## Files modified

* `squad-src/.github/skills/squad/references/roster-catalog.md`: removed the `presenter` row, the `presenter` role-menu line, and `PowerPoint Builder` from the non-dispatchable example list.
* `squad-src/.github/skills/squad/references/seed-templates.md`: removed the `presenter` seed row (PowerPoint Subagent).
* `squad-src/.github/agents/squad/squad-coordinator.agent.md`: dropped `PowerPoint Subagent` from `agents:`.
* `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`: same.
* `squad-src/.github/skills/squad/SKILL.md`: removed PowerPoint Subagent from deployed-cast prerequisites.
* `squad-src/.github/instructions/squad/squad-roster.instructions.md`: removed the `presenter → PowerPoint Subagent` example; generalized the `presenter` Deliverable Root example.
* `squad-src/.github/instructions/squad/pptx-brand-template.instructions.md`: rewrote description, title, and intro; states the powerpoint skill and agents were removed upstream at f425e94 and that no deck capability is available. The pipeline section was replaced by a "no substitute builder" note, and the brand-template guidance was kept as reference only.
* `squad-src/.github/instructions/squad/squad-autopilot.instructions.md`: reworded the deck rule to say the skill was removed upstream and the presenter role is gone.
* `squad-src/.github/skills/sql-migration-advisor/SKILL.md`: slide handoff replaced with an out-of-scope note.
* `docs/usage.html`, `docs/fr/usage.html`: replaced the "coordinator dispatches PowerPoint Subagent" paragraph with a removal note; adjusted the instruction-reader sentence.
* `docs/demo-3.html`, `docs/fr/demo-3.html`: removed the executive-deck table row, adjusted the PowerPoint-role sentence, and added a removal note to the Beat 6 prose.
* `apm.yml`: dependencies only, via the script; the pptx agent, pptx-subagent, pptx instructions, and powerpoint skill entries are gone. `version:` is untouched.

## Created

* `.changes/unreleased/20261110-adapt-squad-cast-to-hve-core-f425e94.md`
* This record.

## Commands

* `pwsh scripts/Update-ApmDependencies.ps1 -Ref f425e943bf228052a23e6bc4810b5faef030314f`: succeeded, 198 hve-core deps, 62 squad deps.
* `pwsh scripts/New-ChangeFragment.ps1 -Type Changed -Bump minor -Title 'adapt squad cast to hve-core f425e94' -Body '...'`: created `.changes/unreleased/20261110-adapt-squad-cast-to-hve-core-f425e94.md`.
* No commit or push was run. Get-HveCoreCastDelta.ps1 was not run (Review stage).

## Left as-is / follow-ups

* `docs/demo-3.html` and `docs/fr/demo-3.html` still mention the presenter role in the Beat 6 command, the autopilot Implement list, and the profile prose. Beat 6 now carries a note marking it historical. A full rewrite is out of scope.
* `docs/usage.html` and `docs/fr/usage.html` retain the brand-template how-to as reference.
* `squad_render_pptx` mentions in `docs/index.html` and `docs/ecosystem.html` are an unrelated squad MCP tool and were not touched.
* Profile seeds (`product`, `full`) may still reference `presenter` elsewhere, and `tests/` baselines were not reviewed. Review should check both.

## Follow-up: presenter role removal

Removed the dangling `presenter` role (its only backing agent, PowerPoint Subagent, was removed upstream).

Changed:

* `squad-src/.github/skills/squad/references/profiles-and-packs.md`, `squad-src/.github/instructions/squad/squad-roster.instructions.md`: dropped `presenter` from `full` and `product` profiles; removed its `.copilot-tracking/ppt/` output-folder row; dropped it from the deliverable-fan-out and deliverable-producing-role lists (and the "slide deck" example).
* `squad-src/.github/instructions/squad/squad-routing.instructions.md`: removed the presentation/deck/slides routing row.
* `squad-src/.github/skills/squad/references/model-routing.md`, `gates-and-modes.md`, `coordinator-legacy.md`: removed `presenter` from the implementation class and deliverable-producing role lists.
* `squad-src/.github/instructions/squad/squad-autopilot.instructions.md`: removed the "then the deck (`presenter`)" step from the typical `product` order.
* `docs/concepts.html`, `docs/fr/concepts.html`: removed presenter output-folder row; `docs/concepts.html` product profile prose.
* `docs/usage.html`, `docs/fr/usage.html`: product profile table; rewrote the "Branded PowerPoint decks" intro to say no deck role exists (reference only).
* `docs/demo-3.html`, `docs/fr/demo-3.html`: removed presenter from the Implement list and the troubleshooting profile row.
* `tests/squad-behavior-contract.md`: PRF-10 `product` profile roster no longer lists `presenter`.
* `tests/tier0/Performance.Tests.ps1`: added explicit retirement allowances (deck-builder sentence; headings "Brand Template for PowerPoint Builds", "The pipeline is the only supported path") so the BEFORE baseline guard accepts the intentional removal. `prefill-baseline.json` itself left untouched (it is the captured BEFORE snapshot). Tests pass (47).

`seed-templates.md` and `roster-catalog.md` contained no `presenter` occurrences.

Intentionally left (historical/removal notes only, none asserting availability): `pptx-brand-template.instructions.md` header, `squad-autopilot.instructions.md` item 4, the removal Notes in `docs/usage.html`, `docs/fr/usage.html`, `docs/demo-3.html`, `docs/fr/demo-3.html`. CHANGELOG.md untouched.

## Follow-up 2: troubleshooting table cleanup

* `docs/demo-3.html` and `docs/fr/demo-3.html`: the "A role does not dispatch" troubleshooting row no longer lists `presenter` among roles the `product` profile resolves, with a parenthetical noting its removal with hve-core f425e94.
