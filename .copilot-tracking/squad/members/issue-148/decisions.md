# Squad Decisions (issue-148)

## 2026-10-06 — Bootstrap and Intake Readiness

**Bootstrap:** Watch Mode Bootstrap ran against `.copilot-tracking/squad/members/`. The existing sub-squads recorded there (`issue-49`, `issue-62`, `issue-66`, `issue-104`, `issue-109`, `issue-116`, `issue-129`) are prior federation members but none carries this run's trigger provenance (`ref: Peter-N91/hve-squad#148`), so a new sub-squad `issue-148` was seeded (`team.md`, `routing.md`, `state.json`, `consumption-rates.md`), scoped to `.copilot-tracking/squad/members/issue-148/`, matching the pattern of the prior cast-delta sub-squads (most recently `issue-129`).

**Verdict:** Ready. Issue #148 ("Adapt squad cast to hve-core@f7bae49") supplies a self-contained brief with an attached cast delta report naming three at-risk references (`prompt-analyze`, `prompt-builder`, `prompt-refactor` — all skills, all removed outright) and the exact files to update. No external inputs or clarification were required. Read `.github/instructions/squad/squad-roster.instructions.md`'s *Dispatchability* and *Deliverable Roots* sections before editing, per the issue's step 1.

## 2026-10-06 — Root Cause

`microsoft/hve-core` moved from `18f5ac75a1556e49f1e90647a4816d17499e1d7f` to `f7bae49bf68988381a8e13472686c501aea13ebc`. Verified directly against a clone of the target SHA and a re-run of `Get-HveCoreCastDelta.ps1`:

* All three removed surfaces are **skills**, not agents: `.github/skills/hve-core/prompt-analyze/SKILL.md`, `.github/skills/hve-core/prompt-builder/SKILL.md`, and `.github/skills/hve-core/prompt-refactor/SKILL.md` all existed at the old pin and are all absent at the new one.
* At the old pin, all three were already thin **compatibility-alias** skills: each `SKILL.md`'s own `Flow` section stated it translates legacy inputs and activates `hve-builder` (`prompt-builder` for create/improve, `prompt-refactor` with `mode=refactor`, `prompt-analyze` with `mode=review`) rather than doing any authoring itself. `hve-builder` (`.github/skills/hve-core/hve-builder/SKILL.md`) was the real, full-capability skill underneath all three even before this delta, and it is unaffected by the delta — it still exists, unchanged in shape, at `f7bae49bf68988381a8e13472686c501aea13ebc`.
* The squad's only binding to the three retired names was the `Squad Prompt Engineer` charter (`squad-src/.github/agents/squad/squad-prompt-engineer.agent.md`), which named all three explicitly as the skills it routes a request to by mode, plus two reference files that described the same routing in prose: `squad-src/.github/skills/squad/references/roster-catalog.md` (the `prompt-engineer` Cast Catalog row, and an unrelated `custom-agent-foundry` blocklist note that mentioned `prompt-builder` in passing) and `squad-src/.github/instructions/squad/squad-roster.instructions.md` (the one-sentence list of skills HVE Core moved capability to, naming `prompt-builder` among nine others). This matches the issue's attached delta exactly: 4 references in `prompt-analyze`, 6 in `prompt-builder`, 4 in `prompt-refactor`, spread across these same three files.
* No agent (`.agent.md`) or prompt (`.prompt.md`) surface changed between the two refs: `Get-HveCoreCastDelta.ps1`'s `added`, `removed`, `dispatchFlips`, `promptsAdded`, and `promptsRemoved` sets were all empty both before and after this fix; only `skillsRemoved` carried the three entries, and `squadAtRisk` named only them.
* Every hve-core-sourced agent named in `squad-coordinator.agent.md`'s and `squad-federation-coordinator.agent.md`'s `agents:` frontmatter lists (37 hve-core-sourced entries each, out of ~71 total) was cross-checked by parsing `name:` and `disable-model-invocation:` directly from the cloned `f7bae49bf68988381a8e13472686c501aea13ebc` tree: every entry resolves and none sets `disable-model-invocation: true`. The remaining entries (`Power Platform Expert`, `Power Platform MCP Integration Expert`, `Declarative Agents Architect`, `MCP M365 Agent Expert`, `QA`, `GitHub Actions Expert`, and four `aws-*`/`AWS Incident Triage` agents) are Registered External Cast entries sourced outside `microsoft/hve-core` and are unaffected by this pin move — so no roster Primary or Alternate needed repointing, and no new squad-owned charter was required for any role other than the one the three retired skills already affected.
* `apm.yml` already carried pinned dependency lines for `hve-builder`, its companion instructions file, its review subagent, and the `hve-artifact-authoring` skill before this change (used by other roles), confirming `hve-builder` is a real, currently-shipped, dispatchable-through-its-charter capability rather than a new dependency this fix introduces.

This is a narrower case than a roster Primary repoint: the affected name (`Squad Prompt Engineer`) was never itself at risk — it is a squad-owned charter and remains fully dispatchable — but three of the **skills it names in its own body** were retired in favor of the skill they already forwarded to. The correct fix is to point the charter directly at `hve-builder`, collapsing a three-way skill selection into a one-skill, multi-mode selection.

## 2026-10-06 — Fix Approach

* **`squad-src/.github/agents/squad/squad-prompt-engineer.agent.md`** — rewrote `description`, the intro paragraph, *Purpose*, *Governing Conventions*, *Inputs*, Step 1 (mode/skill selection), Step 2, Step 3, and *Response Format* to route every create/improve/refactor/review/validate request through `hve-builder` with the matching `mode` value(s), instead of selecting among `prompt-builder` (create/update), `prompt-refactor` (restructure), and `prompt-analyze` (evaluate). Dropped the stale `prompt-builder.instructions.md` authoring-standard citation — that file does not exist in hve-core at either ref checked, and was never a real dependency (it carries no `apm.yml` entry) — in favor of `hve-builder`'s own `references/requirements-catalog.md`. The `evaluation-design` alternate path, and the `Vally Test Author` / `HVE Artifact Tester` alternates, are untouched: none were named in the issue's delta and none changed between the two refs.
* **`squad-src/.github/skills/squad/references/roster-catalog.md`** — reworded the Cast Catalog `prompt-engineer` row's Selection Cue to read "...otherwise create, improve, refactor, or review a prompt artifact → Squad Prompt Engineer (squad-owned charter running the `hve-builder` skill)", and appended a note stating the three retired compatibility skills already forwarded every request to `hve-builder` before their removal at `f7bae49bf68988381a8e13472686c501aea13ebc`. Also reworded the unrelated `custom-agent-foundry` blocklist row (an explanatory historical note, not a roster binding) to name `hve-builder` as the still-current skill while preserving the historical context that it was originally reached via `prompt-builder`.
* **`squad-src/.github/instructions/squad/squad-roster.instructions.md`** — in the paragraph introducing the ten squad-owned charters, replaced `prompt-builder` with `hve-builder` in the list of skills HVE Core moved capability to, and appended a sentence naming the three retired compatibility skills and the SHA at which they were removed.
* No new squad-owned thin charter was authored: `Squad Prompt Engineer` already existed, was already dispatchable, and already wrapped a user-invocable skill tier — the fix is a capability re-binding inside an existing charter, not a new role or a new agent.
* No roster `Primary` or `Alternate` **agent** was repointed: the delta affected skills a charter names in its own prose, not an agent frontmatter binding. All 37 hve-core-sourced agent names across both coordinator charters were independently verified still present and dispatchable (see *Root Cause*), confirming this delta's scope is exactly the three skills the issue's report named and nothing wider.
* **Docs sweep** — `README.md`, `CONTRIBUTING.md`, and `docs/` were searched for `prompt-analyze`, `prompt-builder`, and `prompt-refactor`; zero hits found for all three in any of them. Nothing in the docs refers to any of the retired skills, so no doc file needed updating (recorded here per the issue's instruction to say so explicitly).
* Ran `pwsh scripts/Update-ApmDependencies.ps1 -Ref f7bae49bf68988381a8e13472686c501aea13ebc`, which walks the actual hve-core and squad-src trees rather than a hardcoded list; it moved all 247 hve-core dependency lines to the new SHA, dropped the three `prompt-analyze`/`prompt-builder`/`prompt-refactor` skill lines automatically (they no longer resolve and are no longer referenced), left `version:` untouched (`0.18.0`), and left `CHANGELOG.md` untouched.
* Added `.changes/unreleased/20261006-adapt-squad-cast-to-hve-core-f7bae49.md` (`bump: minor`, `type: Changed`) naming the three-skill removal, the `hve-builder` re-binding, and the files touched.

## 2026-10-06 — Risk Gate

No Stop-verdict findings. The change is a charter-prose rewrite (one agent file), two reference-documentation rewordings, an auto-generated `apm.yml` dependency-pin regeneration, and a documentation-only change fragment. No code execution paths, secrets, migrations, deployments, or live tracker/system writes are touched. The capability the charter wraps (`hve-builder`) was already a pinned, shipped, verified dependency of this package before this change, so this fix introduces no new external dependency surface. **Risk: Low.**

## 2026-10-06 — Acceptance Criteria Status

* "Every roster Primary names an agent present in hve-core@f7bae49" — **Met.** No roster Primary was affected by this delta; the removed surfaces were three skills named inside the `Squad Prompt Engineer` charter's own prose, not an agent frontmatter binding. Every hve-core-sourced Primary and Alternate named in the roster and in both coordinator agents' `agents:` frontmatter (37 entries each) was checked against the cloned target-SHA tree and remains present and dispatchable at `f7bae49bf68988381a8e13472686c501aea13ebc`.
* "No Primary or Alternate sets `disable-model-invocation: true`" — **Met.** Confirmed by parsing frontmatter directly from the cloned target-SHA tree for every hve-core-sourced name in both coordinator agents' lists.
* "Any new thin charter runs a real hve-core skill and declares a Deliverable Root" — **Met (no new charter needed).** No new charter was authored. The existing `Squad Prompt Engineer` charter was re-bound from three retired compatibility skills to the real, shipped `hve-builder` skill those three already forwarded to; its Deliverable Root (`.copilot-tracking/prompts/` for review output; the target artifact's real repository location for authored/refactored output) is unchanged and still declared in the charter body.
* "`apm.yml` pins `f7bae49bf68988381a8e13472686c501aea13ebc` and lists any new charter files" — **Met.** All 247 hve-core dependency lines carry the new SHA; no new charter file was added, so none needed to be newly listed. `hve-builder`'s own dependency lines were already present and remain pinned to the new SHA.
* "A `.changes/unreleased/` fragment exists with `bump: minor`" — **Met.** `.changes/unreleased/20261006-adapt-squad-cast-to-hve-core-f7bae49.md`.
* "`apm.yml` `version:` and `CHANGELOG.md` are untouched" — **Met.** `git diff` shows no `version:` line change (`0.18.0`) and no `CHANGELOG.md` change.
* "Docs naming a changed agent or role are updated, or the PR states that none do" — **Met.** Full sweep of `README.md`, `CONTRIBUTING.md`, and `docs/` found no references to `prompt-analyze`, `prompt-builder`, or `prompt-refactor`; stated explicitly here per the issue's instruction.
* "`Get-HveCoreCastDelta.ps1` reports a non-breaking verdict" — **Met.** Re-run with `-ToRef f7bae49bf68988381a8e13472686c501aea13ebc` against the updated `squad-src/` and the regenerated `apm.yml` reports `isBreaking: False`, `squadAtRisk: {}`, verdict text "no surface change" (full output below).

## 2026-10-06 — Cast Delta Re-Verification

```
Comparing microsoft/hve-core surface: f7bae49bf68988381a8e13472686c501aea13ebc -> f7bae49bf68988381a8e13472686c501aea13ebc
Both refs resolve to f7bae49bf68988381a8e13472686c501aea13ebc - no cast delta possible.

# hve-core surface delta

- Repository: microsoft/hve-core
- From: f7bae49bf68988381a8e13472686c501aea13ebc (currently pinned)
- To: f7bae49bf68988381a8e13472686c501aea13ebc (f7bae49bf68988381a8e13472686c501aea13ebc)
- Surfaces compared: agents, skills, prompts
- Verdict: no surface change

The deployable agents, skills, and prompts are identical between the two refs. A mechanical SHA bump is safe.

hasDelta       : False
isBreaking     : False
squadAtRisk    : {}
```

This is the correct post-fix state: once `apm.yml` is regenerated at `-Ref f7bae49bf68988381a8e13472686c501aea13ebc`, `FromRef` (read from the manifest) and `ToRef` are the same commit, so the script reports no delta rather than a diff — the same terminal state `issue-129` and `issue-116` each reached for their own cast-delta fixes. A separate run comparing the prior pin (`18f5ac75a1556e49f1e90647a4816d17499e1d7f`) against the new one, captured before any edits were made, reproduced the issue's attached delta exactly: `squadAtRisk` named `prompt-analyze` (skill, removed, 4 references), `prompt-builder` (skill, removed, 6 references), and `prompt-refactor` (skill, removed, 4 references), matching the file lists in the issue body file-for-file.

## 2026-10-06 — Environment Note

The Tier 0 install-based conformance suite's top-level runner (`tests/tier0/Invoke-Tier0Tests.ps1`) could not complete in this sandbox because it depends on the `apm` CLI (an Agent Package Manager binary), which is not installed here; the `apm-cli` package available through `npm` is an unrelated tool of the same command name and does not implement `apm install`. This is a sandbox limitation, not a finding about the change — the same limitation prior cast-delta runs (`issue-116`, `issue-129`) recorded. The two scripts this delta specifically exercises — `Get-HveCoreCastDelta.ps1` and `Update-ApmDependencies.ps1` — both ran clean against the edited `squad-src/` and the regenerated `apm.yml`. Additionally, `tests/tier0/Manifest.Tests.ps1` (the PKG-11 "every squad artifact is declared in apm.yml" suite) was run directly through Pester against the regenerated manifest (binding `SourceRoot` via a `NewPesterContainer`) and passed all 52 assertions.

## Outcome

All eight acceptance criteria are **Met**. `squad-src/` now resolves every roster Primary and Alternate to a dispatchable name at hve-core `f7bae49bf68988381a8e13472686c501aea13ebc`; this delta required no new squad-owned charter and no agent repoint, because the only affected references (`prompt-analyze`, `prompt-builder`, `prompt-refactor`, all skills) were named inside the already-dispatchable `Squad Prompt Engineer` charter's own prose rather than bound as a roster agent, and all three had already forwarded every request to the still-shipped `hve-builder` skill before their removal. `apm.yml` is pinned to `f7bae49bf68988381a8e13472686c501aea13ebc`. A minor change fragment is staged. This run's file changes are left uncommitted in the working tree for the separate automated step to stage, commit, push, and open the draft pull request.

## History Files

* `.copilot-tracking/squad/members/issue-148/history/Squad Implementor.md` — implementation dispatch record (charter rewrite, roster-catalog and roster-instructions rewording, `apm.yml` regeneration, change fragment).
* `.copilot-tracking/squad/members/issue-148/history/Squad Reviewer.md` — verification dispatch record (before/after cast-delta runs, live hve-core clone frontmatter audit across both coordinator agents' 37 hve-core-sourced entries, docs sweep, `Manifest.Tests.ps1` run).
* `.copilot-tracking/squad/members/issue-148/history/Squad Scribe.md` — orchestration record for the bootstrap turn that seeded this sub-squad and the closing turn that wrote the ledger and this file.

## Blocking findings

None. No Stop-verdict, Risk: High, compliance, or divergence findings were raised during this run.
