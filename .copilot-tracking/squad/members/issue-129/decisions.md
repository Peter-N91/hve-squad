# Squad Decisions (issue-129)

## 2026-09-30 — Bootstrap and Intake Readiness

**Bootstrap:** Watch Mode Bootstrap ran against `.copilot-tracking/squad/members/`. The existing sub-squads recorded there (`issue-49`, `issue-62`, `issue-66`, `issue-104`, `issue-109`, `issue-116`) are prior federation members but none carries this run's trigger provenance (`ref: Peter-N91/hve-squad#129`), so a new sub-squad `issue-129` was seeded (`team.md`, `routing.md`, `state.json`, `consumption-rates.md`), scoped to `.copilot-tracking/squad/members/issue-129/`, matching the pattern of the five prior cast-delta sub-squads.

**Verdict:** Ready. Issue #129 ("Adapt squad cast to hve-core@5c7f9a7") supplies a self-contained brief with an attached cast delta report naming the one at-risk reference (`graph-research`, a prompt, removed from hve-core) and the single file to update. No external inputs or clarification were required.

## 2026-09-30 — Root Cause

`microsoft/hve-core` moved from `180c85492b5a20380927200ddf926fd712e7d9d1` to `5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb`. Verified directly against a clone of the target SHA and a re-run of `Get-HveCoreCastDelta.ps1`:

* `.github/prompts/experimental/graph-research.prompt.md` (prompt id `graph-research`) is removed outright — not renamed, gone. It was referenced exactly once in `squad-src/`, in the Cast Catalog `researcher` row of `squad-src/.github/instructions/squad/squad-roster.instructions.md`, where the existing text already treated it as a user entry point escalated to rather than dispatched (`the graph-research prompt is a user entry point, not a dispatchable agent, so a request for graph-backed research is escalated to the user to run /graph-research rather than dispatched`).
* Because a prompt can never be a Primary or Alternate agent (`runSubagent`/`task` cannot reach a `.prompt.md`), this reference was already outside the dispatchable roster surface before the removal. The removal does not open a capability gap or require a substitute agent or a new thin charter — it makes the existing escalation text stale, because the command it names to escalate to no longer exists.
* No agent (`.agent.md`) or skill (`SKILL.md`) surface changed between the two refs: `Get-HveCoreCastDelta.ps1`'s `added`, `removed`, and `dispatchFlips` sets were all empty both before and after this fix; only `promptsRemoved` carried an entry, and `squadAtRisk` named only `graph-research`.
* A direct diff of `apm.yml`'s dependency-path set before and after running `Update-ApmDependencies.ps1 -Ref 5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb` showed two additional changes the delta script does not surface because they are outside its agents/skills/prompts scope: `.github/instructions/experimental/graphify.instructions.md` and `.github/instructions/shared/hve-core-location.instructions.md` were removed by hve-core (the latter apparently renamed to the newly added `.github/instructions/hve-core/copilot-tracking-location.instructions.md`). Neither old path is referenced anywhere in `squad-src/`, `docs/`, `README.md`, or `CONTRIBUTING.md`, so no adaptation was required for either.
* Every hve-core-sourced agent named in `squad-coordinator.agent.md`'s and `squad-federation-coordinator.agent.md`'s `agents:` frontmatter lists (71 entries each) was cross-checked by parsing `name:` and `disable-model-invocation:` directly from the cloned `5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb` tree: every entry resolves and none sets `disable-model-invocation: true`. The remaining entries in both lists (`Power Platform Expert`, `Power Platform MCP Integration Expert`, `Declarative Agents Architect`, `MCP M365 Agent Expert`, `QA`, `GitHub Actions Expert`, and three `aws-*` agents) are Registered External Cast entries sourced outside `microsoft/hve-core` and are unaffected by this pin move.

This is the narrowest case the roster instructions define: a reference that names a removed surface but was never itself dispatchable, so the correct fix is a wording correction, not a repoint, a substitute, or a new charter.

## 2026-09-30 — Fix Approach

* **`squad-src/.github/instructions/squad/squad-roster.instructions.md`** — reworded the Cast Catalog `researcher` row's **Knowledge-graph research** note. It now states the `graph-research` prompt was removed outright from hve-core at `5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb`, that it was never a dispatchable agent and so no roster row ever pointed at it, and that no replacement is needed because there is no longer a `/graph-research` command to escalate a request to.
* **`squad-src/.github/agents/squad/squad-coordinator.agent.md`** and **`squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`** — checked, not edited: `graph-research` was never present in either `agents:` frontmatter list (it is a prompt, not an agent), and every other entry in both lists was confirmed present and dispatchable against the cloned `5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb` tree.
* **`squad-src/.github/skills/squad/SKILL.md`** and **`squad-src/.github/instructions/squad/squad-routing.instructions.md`** — checked, not edited: neither names `graph-research` or any other agent affected by this delta.
* **Docs sweep** — `README.md`, `CONTRIBUTING.md`, and `docs/` were searched for `graph-research`; zero hits found in any of the three. Nothing in the docs refers to the changed prompt, so no doc file needed updating (recorded here per the issue's instruction to say so explicitly).
* No new squad-owned thin charter was authored: the retired prompt's only role in the roster was as the target of a user escalation message, not a capability the squad dispatched, so there is nothing to wrap in a charter.
* Ran `pwsh scripts/Update-ApmDependencies.ps1 -Ref 5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb`, which walks the actual hve-core and squad-src trees rather than a hardcoded list; it moved all 257 hve-core dependency lines to the new SHA (dropping the removed `graph-research.prompt.md`, `graphify.instructions.md`, and `hve-core-location.instructions.md` entries automatically and picking up the added `copilot-tracking-location.instructions.md` entry), left `version:` untouched (`0.17.0`), and left `CHANGELOG.md` untouched.
* Added `.changes/unreleased/20260930-adapt-squad-cast-to-hve-core-5c7f9a7.md` (`bump: minor`, `type: Changed`) naming the prompt removal and the no-substitute-needed reasoning.

## 2026-09-30 — Risk Gate

No Stop-verdict findings. The change is a single-paragraph rewording in an instructions file, an auto-generated `apm.yml` dependency-pin regeneration, and a documentation-only change fragment. No code execution paths, secrets, migrations, deployments, or live tracker/system writes are touched. **Risk: Low.**

## 2026-09-30 — Acceptance Criteria Status

* "Every roster Primary names an agent present in hve-core@5c7f9a7" — **Met.** No roster Primary was affected by this delta; the removed surface was a prompt referenced only in explanatory prose, never cast as a Primary or Alternate. Every hve-core-sourced Primary and Alternate named in the roster and in both coordinator agents' `agents:` frontmatter was checked against the cloned tree and remains present at `5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb`.
* "No Primary or Alternate sets `disable-model-invocation: true`" — **Met.** Confirmed by parsing frontmatter directly from the cloned target-SHA tree for every hve-core-sourced name in both coordinator agents' lists.
* "Any new thin charter runs a real hve-core skill and declares a Deliverable Root" — **Met (no new charter needed).** No new charter was authored — this delta required no replacement capability to wrap, because the removed prompt was never dispatched by the squad.
* "`apm.yml` pins `5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb` and lists any new charter files" — **Met.** All hve-core dependency lines carry the new SHA; no new charter file was added, so none needed to be newly listed.
* "A `.changes/unreleased/` fragment exists with `bump: minor`" — **Met.** `.changes/unreleased/20260930-adapt-squad-cast-to-hve-core-5c7f9a7.md`.
* "`apm.yml` `version:` and `CHANGELOG.md` are untouched" — **Met.** `git diff` shows no `version:` line change (`0.17.0`) and no `CHANGELOG.md` change.
* "Docs naming a changed agent or role are updated, or the PR states that none do" — **Met.** Full sweep of `README.md`, `CONTRIBUTING.md`, and `docs/` found no references to `graph-research`; stated explicitly here per the issue's instruction.
* "`Get-HveCoreCastDelta.ps1` reports a non-breaking verdict" — **Met.** Re-run with `-ToRef 5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb` against the updated `squad-src/` and the regenerated `apm.yml` reports `isBreaking: False`, `squadAtRisk: {}`, verdict text "no surface change" (full output below).

## 2026-09-30 — Cast Delta Re-Verification

```
Comparing microsoft/hve-core surface: 5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb -> 5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb
Both refs resolve to 5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb - no cast delta possible.

# hve-core surface delta

- Repository: microsoft/hve-core
- From: 5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb (currently pinned)
- To: 5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb (5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb)
- Surfaces compared: agents, skills, prompts
- Verdict: no surface change

The deployable agents, skills, and prompts are identical between the two refs. A mechanical SHA bump is safe.

hasDelta       : False
isBreaking     : False
squadAtRisk    : {}
```

This is the correct post-fix state: once `apm.yml` is regenerated at `-Ref 5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb`, `FromRef` (read from the manifest) and `ToRef` are the same commit, so the script reports no delta rather than a diff — the same terminal state `issue-116` reached for its own cast-delta fix. A separate run comparing the prior pin (`180c85492b5a20380927200ddf926fd712e7d9d1`) against the new one, captured before any edits were made, reproduced the issue's attached delta exactly: `squadAtRisk` named only `graph-research` (prompt, removed, 1 reference, in `squad-roster.instructions.md`).

## 2026-09-30 — Environment Note

The Tier 0 install-based conformance suite's top-level runner (`tests/tier0/Invoke-Tier0Tests.ps1`) could not complete in this sandbox because it depends on the `apm` CLI (an Agent Package Manager binary), which is not installed here; the `apm-cli` package available through `npm` is an unrelated tool of the same command name and does not implement `apm install`. This is a sandbox limitation, not a finding about the change. The two scripts this delta specifically exercises — `Get-HveCoreCastDelta.ps1` and `Update-ApmDependencies.ps1` — both ran clean against the edited `squad-src/` and the regenerated `apm.yml`. Additionally, `tests/tier0/Manifest.Tests.ps1` (the PKG-11 "every squad artifact is declared in apm.yml" suite) was run directly through Pester against the regenerated manifest and passed all 52 assertions.

## Outcome

All eight acceptance criteria are **Met**. `squad-src/` now resolves every roster Primary and Alternate to a dispatchable name at hve-core `5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb`; this delta required no new squad-owned charter, because the only affected reference (`graph-research`, a prompt) was never a dispatchable roster entry to begin with — it was explanatory prose describing an escalation path that no longer resolves, and that prose has been corrected to say so. `apm.yml` is pinned to `5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb`. A minor change fragment is staged. This run's file changes are left uncommitted in the working tree for the separate automated step to stage, commit, push, and open the draft pull request.

## History Files

* `.copilot-tracking/squad/members/issue-129/history/Squad Implementor.md` — implementation dispatch record (roster-row rewording, `apm.yml` regeneration, change fragment).
* `.copilot-tracking/squad/members/issue-129/history/Squad Reviewer.md` — verification dispatch record (before/after cast-delta runs, live hve-core clone frontmatter audit, docs sweep, Manifest.Tests.ps1 run).
* `.copilot-tracking/squad/members/issue-129/history/Squad Scribe.md` — orchestration record for the bootstrap turn that seeded this sub-squad and the closing turn that wrote the ledger and this file.

## Blocking findings

None. No Stop-verdict, Risk: High, compliance, or divergence findings were raised during this run.
