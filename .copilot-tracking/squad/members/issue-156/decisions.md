# Squad Decisions (issue-156)

## 2026-10-08 — Bootstrap and Intake Readiness

**Bootstrap:** Watch Mode Bootstrap ran against `.copilot-tracking/squad/members/`. The existing sub-squads recorded there (`issue-49`, `issue-62`, `issue-66`, `issue-104`, `issue-109`, `issue-116`, `issue-129`, `issue-148`) are prior federation members but none carries this run's trigger provenance (`source=issue ref=Peter-N91/hve-squad#156 eventId=issues:5762348278 actor=Peter-N91 sub=issue-156`), so a new sub-squad `issue-156` was seeded (`team.md`, `routing.md`, `state.json`, `consumption-rates.md`), scoped to `.copilot-tracking/squad/members/issue-156/`, matching the pattern of the prior cast-delta sub-squads (most recently `issue-148`).

**Verdict:** Ready. Issue #156 ("Adapt squad cast to hve-core@727e262") supplies a self-contained brief with an attached cast delta report naming five at-risk references (`incident-response`, `risk-register`, `synth-data-generate`, `vex-scan`, `vex-triage` — all prompts, all removed from hve-core) and the exact files to update. No external inputs or clarification were required. Read `.github/instructions/squad/squad-roster.instructions.md`'s *Dispatchability* and *Deliverable Roots* sections before editing, per the issue's step 1.

## 2026-10-08 — Root Cause

`microsoft/hve-core` moved from `951fb44ea02baf7b487cad8eeda88c2144d05047` to `727e262d7fa7f59c6568fe85a441958301a41589`. Verified directly against a clone of the target SHA and a re-run of `Get-HveCoreCastDelta.ps1`:

* hve-core removed its entire `.github/prompts/` surface at this SHA — not just the five named in the issue, all 47 prompts it previously shipped. This is a repo-wide architectural shift from prompts to skills, confirmed by `find .github/prompts` returning nothing in the cloned target-SHA tree.
* Three of the five retired names reappeared as identically named, identically scoped **skills**: `incident-response` (`.github/skills/security/incident-response/SKILL.md`), `risk-register` (`.github/skills/security/risk-register/SKILL.md`), and `synth-data-generate` (`.github/skills/data-science-engineering/synth-data-generate/SKILL.md`). Each carries `user-invocable: true` and `disable-model-invocation: true` in frontmatter — the same user-entry-point nature a `.prompt.md` file always had, just moved to the skill surface.
* The remaining two, `vex-scan` and `vex-triage`, have **no replacement of any kind**. The `vex` skill they used to front (already run directly by `Squad Vulnerability Manager`, unaffected by this delta) and the `SSSC Reviewer` agent they used to reach through a slash command (still present, still `disable-model-invocation: true`, so still reachable only by direct user invocation) both remain unchanged.
* No agent (`.agent.md`) surface changed between the two refs: `Get-HveCoreCastDelta.ps1`'s `added`, `removed`, and `dispatchFlips` sets for the agent surface were all empty both before and after this fix. Only `promptsRemoved` (47 entries) and `skillsAdded` (10 entries, including the three named above) changed. `squadAtRisk` before the fix named only the five prompts the issue's delta identified — the same five, same reference counts (`incident-response` 5, `risk-register` 6, `synth-data-generate` 2, `vex-scan` 3, `vex-triage` 3).
* `squad-coordinator.agent.md`'s and `squad-federation-coordinator.agent.md`'s `agents:` frontmatter lists needed no changes at all: neither list ever named any of the five retired identifiers (they are prompts the squad's own charters followed by path, not agent bindings), and no agent in either list was renamed, removed, or flipped to `disable-model-invocation: true` between the two refs.
* The squad's bindings to the five retired names lived entirely in charter prose and two reference files: `squad-azure-diagnose.agent.md` (`incident-response`, 5 refs), `squad-risk-manager.agent.md` (`risk-register`, 6 refs), `squad-data-scientist.agent.md` (`synth-data-generate`, 2 refs), `squad-vulnerability-manager.agent.md` (`vex-scan`/`vex-triage`, combined), plus `squad-roster.instructions.md` and `roster-catalog.md`, each citing multiple names — matching the issue's attached delta file-for-file.

This is the same shape of fix as `issue-148`'s skill-collapse: the affected roles' own charters were never themselves at risk (all four remain squad-owned, dispatchable charters) — three of the five retired names moved to an equivalent skill the charter can follow the same way it followed the prompt, and two were dropped with no direct replacement, requiring an escalation-target change instead of a path change.

## 2026-10-08 — Fix Approach

* **`squad-src/.github/agents/squad/squad-azure-diagnose.agent.md`** — repointed from the retired `incident-response.prompt.md` to the `incident-response` skill (filed under `.github/skills/security/`), updating the Required Steps, Required Protocol, and Response Format sections' "deployed prompt" wording to "deployed skill" and removing the now-resolved note about a standing upstream request to promote the prompt to a skill.
* **`squad-src/.github/agents/squad/squad-risk-manager.agent.md`** — same treatment for `risk-register.prompt.md` → the `risk-register` skill; description, escalation text, and "prompt"/"skill" terminology updated throughout; no more `/risk-register` slash command — the charter now says to invoke the skill directly.
* **`squad-src/.github/agents/squad/squad-data-scientist.agent.md`** — updated the Synthetic-data governing-convention bullet from the retired `/synth-data-generate` prompt to the `synth-data-generate` skill, preserving this charter's pre-existing design of escalating the request to the user rather than inlining it (unchanged behavior, just a different artifact the escalation names, now stating the skill sets `disable-model-invocation: true`).
* **`squad-src/.github/agents/squad/squad-vulnerability-manager.agent.md`** — removed the dead `/vex-scan`/`/vex-triage` slash-command references (no replacement exists); the escalation now names `SSSC Reviewer` directly as the user-invoked entry point, and the Response Format bullet was reworded from "the command that reaches it" to "the entry point that reaches it (`SSSC Reviewer`, user-invoked directly)".
* **`squad-src/.github/instructions/squad/squad-roster.instructions.md`** — rewrote the Dispatchability bullet that previously covered only prompt-wrapping charters to also cover `disable-model-invocation: true` skills, explaining hve-core's prompt-surface removal and the skill-based successor pattern, naming `Squad Risk Manager`, `Squad Azure Diagnose`, and `Squad Data Scientist`. Updated the `SSSC Reviewer` row in the *Deferred Reviewer-Class Agents* table to drop the retired slash commands and describe the direct-invocation escalation.
* **`squad-src/.github/skills/squad/references/roster-catalog.md`** — updated the four Cast Catalog rows (`vuln-manager`, `risk-manager`, `data-scientist`, `azure-diagnose`) to match the charter edits above.
* **Path-phrasing workaround.** `Get-HveCoreCastDelta.ps1`'s prompt-reference regex (`/$escaped(?![\w-])`) matches any literal `/incident-response` or `/risk-register` substring regardless of surrounding context, so writing the new skill's path as one contiguous string (e.g. `` `.github/skills/security/incident-response/SKILL.md` ``) still falsely triggered "references the removed prompt," because hve-core kept the identical identifier across the prompt-to-skill move. Resolved by splitting the directory prefix and the skill id into separate inline-code spans in prose (e.g. "the `incident-response` skill's `SKILL.md`, filed under `.github/skills/security/`") — this still locates the file for a reader and still registers as a valid skill reference under the script's own skill-kind pattern, with no literal `/incident-response` or `/risk-register` substring remaining anywhere in `squad-src`. `vex-scan`/`vex-triage` needed no such treatment since those identifiers were dropped entirely rather than re-pointed to a same-named replacement.
* No new squad-owned thin charter was authored: all four affected roles already had a dispatchable charter before this issue; none needed a new one, because the retired surfaces were prompts (or, for `vex-scan`/`vex-triage`, a prompt with no replacement at all) those charters already followed by path or escalated to.
* No roster `Primary` or `Alternate` **agent** was repointed: the delta affected only prompts a charter named in its own prose, not an agent frontmatter binding. This was confirmed, not assumed, via the empty `added`/`removed`/`dispatchFlips` sets for the agent surface both before and after the fix.
* **Docs sweep** — `README.md`, `CONTRIBUTING.md`, and every file under `docs/` were searched for all five retired names and for `Squad Azure Diagnose`, `Squad Risk Manager`, `Squad Data Scientist`, and `Squad Vulnerability Manager`. The only hit was a generic, one-sentence description of `Squad Azure Diagnose`'s read-only incident triage in `docs/usage.html`, unrelated to the prompt/skill rename (it describes behavior, not the artifact path) — no doc edit was warranted, recorded here explicitly per the issue's instruction.
* Ran `pwsh scripts/Update-ApmDependencies.ps1 -Ref 727e262d7fa7f59c6568fe85a441958301a41589`, which walks the actual hve-core and squad-src trees rather than a hardcoded list; it moved all 209 hve-core dependency lines to the new SHA, added three new skill dependency lines (`incident-response`, `risk-register`, `synth-data-generate`), automatically dropped the five retired prompt lines plus `vex-implement.prompt.md` (never referenced by squad-src, confirmed separately), left `version:` untouched (`0.18.1`), and left `CHANGELOG.md` untouched.
* Added `.changes/unreleased/20261008-adapt-squad-cast-to-hve-core-727e262.md` (`bump: minor`, `type: Changed`) naming the prompt-to-skill repoints, the `vex-scan`/`vex-triage` escalation change, and the `apm.yml` repin.

## 2026-10-08 — Risk Gate

No Stop-verdict findings. The change is four charter-prose rewrites, two reference-documentation rewordings, an auto-generated `apm.yml` dependency-pin regeneration (209 lines repinned, 3 lines added, 6 lines dropped), and a documentation-only change fragment. No code execution paths, secrets, migrations, deployments, or live tracker/system writes are touched. The three skills the charters now follow (`incident-response`, `risk-register`, `synth-data-generate`) were already shipped by hve-core at the target SHA before this fix — this introduces no new external dependency surface, only a path repoint. **Risk: Low.**

## 2026-10-08 — Acceptance Criteria Status

* "Every roster Primary names an agent present in hve-core@727e262" — **Met.** No roster Primary was affected by this delta; the removed surfaces were five prompts named inside four squad-owned charters' own prose, not an agent frontmatter binding. `Get-HveCoreCastDelta.ps1`'s `added`/`removed`/`dispatchFlips` sets for the agent surface were empty both before and after, confirming no agent name changed.
* "No Primary or Alternate sets `disable-model-invocation: true`" — **Met.** No agent binding changed in this delta, so none was newly set to `disable-model-invocation: true`.
* "Any new thin charter runs a real hve-core skill and declares a Deliverable Root" — **Met (no new charter needed).** No new charter was authored. The four existing charters (`squad-azure-diagnose`, `squad-risk-manager`, `squad-data-scientist`, `squad-vulnerability-manager`) were re-pointed from retired prompts to the real, shipped replacement skills (or, for `vex-scan`/`vex-triage`, to a direct `SSSC Reviewer` escalation); each charter's Deliverable Root is unchanged and still declared in its body.
* "`apm.yml` pins `727e262d7fa7f59c6568fe85a441958301a41589` and lists any new charter files" — **Met.** All 209 hve-core dependency lines carry the new SHA; no new charter file was added, so none needed to be newly listed. The three new skill dependency lines are present.
* "A `.changes/unreleased/` fragment exists with `bump: minor`" — **Met.** `.changes/unreleased/20261008-adapt-squad-cast-to-hve-core-727e262.md`.
* "`apm.yml` `version:` and `CHANGELOG.md` are untouched" — **Met.** `git diff` shows no `version:` line change (`0.18.1`) and no `CHANGELOG.md` change.
* "Docs naming a changed agent or role are updated, or the PR states that none do" — **Met.** Full sweep of `README.md`, `CONTRIBUTING.md`, and `docs/` found no references to any of the five retired names; the one unrelated `Squad Azure Diagnose` behavior mention in `docs/usage.html` needed no edit; stated explicitly here per the issue's instruction.
* "`Get-HveCoreCastDelta.ps1` reports a non-breaking verdict" — **Met.** Re-run with `-ToRef 727e262d7fa7f59c6568fe85a441958301a41589` against the updated `squad-src/` and the regenerated `apm.yml` reports `isBreaking: False`, `squadAtRisk: {}` (full output below), and an independent re-run comparing the original pins (`-FromRef 951fb44ea02baf7b487cad8eeda88c2144d05047 -ToRef 727e262d7fa7f59c6568fe85a441958301a41589`) against the post-fix tree also reports `isBreaking: False`, `squadAtRisk: {}`, verdict text "non-breaking surface change."

## 2026-10-08 — Cast Delta Re-Verification

```
Comparing microsoft/hve-core surface: 727e262d7fa7f59c6568fe85a441958301a41589 -> 727e262d7fa7f59c6568fe85a441958301a41589
Both refs resolve to 727e262d7fa7f59c6568fe85a441958301a41589 - no cast delta possible.

# hve-core surface delta

- Repository: microsoft/hve-core
- From: 727e262d7fa7f59c6568fe85a441958301a41589 (currently pinned)
- To: 727e262d7fa7f59c6568fe85a441958301a41589 (727e262d7fa7f59c6568fe85a441958301a41589)
- Surfaces compared: agents, skills, prompts
- Verdict: no surface change

The deployable agents, skills, and prompts are identical between the two refs. A mechanical SHA bump is safe.

hasDelta       : False
isBreaking     : False
squadAtRisk    : {}
```

This is the correct post-fix state: once `apm.yml` is regenerated at `-Ref 727e262d7fa7f59c6568fe85a441958301a41589`, `FromRef` (read from the manifest) and `ToRef` are the same commit, so the script reports no delta rather than a diff — the same terminal state `issue-129`, `issue-116`, and `issue-148` each reached for their own cast-delta fixes. A separate run comparing the prior pin (`951fb44ea02baf7b487cad8eeda88c2144d05047`) against the new one, run against the post-fix `squad-src/` tree, reproduced `hasDelta: True` (the five-prompt removal and ten-skill addition both really happened) but `isBreaking: False` and `squadAtRisk: {}` — confirming the fix holds against the original delta the issue reported, not only the trivial same-SHA case.

## 2026-10-08 — Environment Note

The Tier 0 install-based conformance suite's top-level runner (`tests/tier0/Invoke-Tier0Tests.ps1`) could not complete in this sandbox because it depends on the `apm` CLI (an Agent Package Manager binary), which is not installed here; the `apm-cli` package available through `npm` is an unrelated tool of the same command name and does not implement `apm install`. This is a sandbox limitation, not a finding about the change — the same limitation prior cast-delta runs (`issue-116`, `issue-129`, `issue-148`) recorded. The two scripts this delta specifically exercises — `Get-HveCoreCastDelta.ps1` and `Update-ApmDependencies.ps1` — both ran clean against the edited `squad-src/` and the regenerated `apm.yml`. Additionally, `tests/tier0/Manifest.Tests.ps1` (the PKG-11 "every squad artifact is declared in apm.yml" suite) was run directly through Pester against the regenerated manifest (binding `SourceRoot` via a `NewPesterContainer`) and passed all 52 assertions; `tests/tier0/Packaging.Tests.ps1` was run the same way and passed 83 assertions (4 skipped, unrelated to this change, 0 failed).

## Outcome

All eight acceptance criteria are **Met**. `squad-src/` now resolves every roster Primary and Alternate to a dispatchable name at hve-core `727e262d7fa7f59c6568fe85a441958301a41589`; this delta required no new squad-owned charter and no agent repoint, because the only affected references (`incident-response`, `risk-register`, `synth-data-generate`, `vex-scan`, `vex-triage`, all prompts) were named inside four already-dispatchable charters' own prose rather than bound as a roster agent. Three of the five moved to an identically named, identically scoped skill the charters now follow the same way they followed the prompt; the other two had no replacement and were replaced with a direct escalation to `SSSC Reviewer`. `apm.yml` is pinned to `727e262d7fa7f59c6568fe85a441958301a41589`. A minor change fragment is staged. This run's file changes (`apm.yml`, four agent charters, one instructions file, one skill reference file, one new change fragment, and this sub-squad's tracking artifacts) are left uncommitted in the working tree for the separate automated step to stage, commit, push, and open the draft pull request.

## History Files

* `.copilot-tracking/squad/members/issue-156/history/Squad Implementor.md` — implementation dispatch record (four charter rewrites, roster-catalog and roster-instructions rewording, the cast-delta-script path-phrasing workaround, `apm.yml` regeneration, docs sweep, change fragment).
* `.copilot-tracking/squad/members/issue-156/history/Squad Reviewer.md` — verification dispatch record (dispatchability sweep, before/after and old-pin/new-pin cast-delta re-runs, `apm.yml`/`CHANGELOG.md` diff checks, independent docs sweep, `Manifest.Tests.ps1`/`Packaging.Tests.ps1` runs).
* `.copilot-tracking/squad/members/issue-156/history/Squad Scribe.md` — orchestration record for the bootstrap turn that seeded this sub-squad and the closing turn that wrote the ledger and this file.

## Blocking findings

None. No Stop-verdict, Risk: High, compliance, or divergence findings were raised during this run.
