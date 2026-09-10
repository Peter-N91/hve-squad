# Squad Decisions (issue-109)

## 2026-09-10 — Bootstrap and Intake Readiness

**Bootstrap:** Watch Mode Bootstrap ran against `.copilot-tracking/squad/members/`; the existing sub-squads there (`issue-49`, `issue-62`, `issue-66`, `issue-104`) are recorded federation members but none carries this run's trigger provenance (`ref: Peter-N91/hve-squad#109`), so a new sub-squad `issue-109` was seeded (`team.md`, `routing.md`, `state.json`, `consumption-rates.md`), scoped to `.copilot-tracking/squad/members/issue-109/`, matching the pattern of the prior cast-delta sub-squads.

**Verdict:** Ready. Issue #109 ("Adapt squad cast to hve-core@c8c5e94") supplies a self-contained brief with an attached cast delta report naming the one at-risk agent, its file references, and hve-core's replacement surface (agents). No external inputs or clarification were required.

## 2026-09-10 — Root Cause

`microsoft/hve-core` moved from `abeea85e70290fe9657989fd4fbd4e93afabca3d` to `c8c5e94ecd22438e21460bd4b2064f8516f55603`. Verified directly against a clone of the target SHA:

* `code-review-pr.agent.md` (was `.github/agents/coding-standards/subagents/code-review-pr.agent.md`) is removed outright — not renamed, gone. It was cast only as an alternate under the squad's `tester` role, referenced from three files: `squad-src/.github/instructions/squad/squad-roster.instructions.md` (the Cast Catalog row) and both `squad-src/.github/agents/squad/squad-coordinator.agent.md` and `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md` (`agents:` frontmatter lists).
* Its replacement surface, `code-review-orientation.agent.md` (`.github/agents/coding-standards/subagents/code-review-orientation.agent.md`), sets `user-invocable: false` with no `disable-model-invocation` flag, so it is dispatchable in the narrow *Dispatchability* sense. But reading `code-review.agent.md` (the `Code Review` orchestrator) shows `Code Review Orientation` is described as "a required workflow stage, not a findings perspective" that "runs once before perspective selection" — an internal step the orchestrator itself dispatches, consuming a `diff-state.json` at a `task.outputPath` only that orchestrator's own run constructs. This is the same delegated-worker shape *Worker Agents Are Not Roles* excludes from the roster (the `RPI Researcher` precedent): an agent reachable by `runSubagent` in principle, but one that validates a strict parent-artifact contract before doing anything, so it refuses a plain role-scoped dispatch.
* There is therefore no dispatchable one-for-one replacement for the retired alternate. `Code Review Readiness`, already cast on the same `tester` row, already covers PR deliverable readiness (checkbox/mergeable state, linked-issue alignment, changed-documentation content), so dropping the retired alternate with no substitute closes no capability gap.

Unlike the `issue-104` cast delta (a pure five-skill-id rename) or the `issue-66` delta (an entire agent cast retired with a brand-new charter required), this delta is the narrowest case the roster instructions define: one alternate agent retired outright, with its capability absorbed into an orchestrator's own internal flow rather than exposed as a new dispatch target, so the correct fix is to drop the alternate and record why, not to author a charter or repoint to a substitute.

## 2026-09-10 — Fix Approach

* **`squad-src/.github/instructions/squad/squad-roster.instructions.md`** — the `tester` role's Cast Catalog row: removed the retired alternate from the `Alternate Agents` cell and its `pull-request walkthrough →` clause from the `Selection Cue` prose; added a **Pull-request walkthrough** note explaining the retirement, the disqualifying worker-agent contract found in `Code Review Orientation`, and that `Code Review Readiness` already covers PR deliverable readiness. The note names the retired capability without repeating the agent's literal `name:` string, following the `issue-104` precedent for `Data Workstream Coach`, so a re-run of `Get-HveCoreCastDelta.ps1` reports zero remaining references.
* **`squad-src/.github/agents/squad/squad-coordinator.agent.md`** and **`squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`** — removed the same retired name from the `agents:` frontmatter list in both files. Every other entry in both lists was checked against the cloned `c8c5e94ecd22438e21460bd4b2064f8516f55603` tree and confirmed present and dispatchable.
* **`squad-src/.github/skills/squad/SKILL.md`, `squad-src/.github/instructions/squad/squad-routing.instructions.md`** — checked, not edited: neither names the retired agent, so neither needed a change.
* **Docs sweep** — `README.md`, `CONTRIBUTING.md`, and `docs/` were searched for the retired agent's name; zero hits found. Nothing in the docs refers to the changed name, so no doc file needed updating (recorded here per the issue's instruction to say so explicitly).
* No new squad-owned thin charter was authored: the retired agent's capability moved into an orchestrator-internal stage with no caller-facing replacement to wrap, and the role it filled (`Code Review Readiness`) already covers the gap it would otherwise leave.
* Ran `pwsh scripts/Update-ApmDependencies.ps1 -Ref c8c5e94ecd22438e21460bd4b2064f8516f55603`, which walks the actual hve-core and squad-src trees rather than a hardcoded list, so it moved all 257 hve-core dependency lines to the new SHA.
* Added `.changes/unreleased/20260910-adapt-squad-cast-to-hve-core-c8c5e94.md` (`bump: minor`, `type: Changed`) naming the retirement and the replacement-path reasoning. Left `apm.yml` `version:` and `CHANGELOG.md` untouched.

## 2026-09-10 — Risk Gate

No Stop-verdict findings. The change is a two-cell removal (one roster Alternate Agents cell, two agent-frontmatter lists) plus an accompanying explanatory rewording, an auto-generated `apm.yml` dependency-pin regeneration, and a documentation-only change fragment. No code execution paths, secrets, migrations, deployments, or live tracker/system writes are touched. **Risk: Low.**

## 2026-09-10 — Acceptance Criteria Status

* "Every roster Primary names an agent present in hve-core@c8c5e94" — **Met.** No roster Primary was affected by this delta; the retired agent was only ever cast as a `tester` Alternate. Every Primary was checked against the cloned tree and remains present at `c8c5e94ecd22438e21460bd4b2064f8516f55603`.
* "No Primary or Alternate sets `disable-model-invocation: true`" — **Met.** The retired alternate is removed; its would-be replacement, `Code Review Orientation`, was deliberately **not** seeded as a role Alternate because it fails the *Worker Agents Are Not Roles* contract test (it requires a `diff-state.json` only the `Code Review` orchestrator produces), not because it sets the flag — it does not set `disable-model-invocation`, but a worker that refuses a plain role dispatch is excluded on that separate, correct ground.
* "Any new thin charter runs a real hve-core skill and declares a Deliverable Root" — **Met (no new charter needed).** No new charter was authored — this delta required no replacement capability to wrap, because the retired agent's role (`Code Review Readiness`, already cast) already covers PR deliverable readiness.
* "`apm.yml` pins `c8c5e94ecd22438e21460bd4b2064f8516f55603` and lists any new charter files" — **Met.** All 257 hve-core dependency lines carry the new SHA and zero carry the old one; no new charter file was added, so none needed to be newly listed.
* "A `.changes/unreleased/` fragment exists with `bump: minor`" — **Met.** `.changes/unreleased/20260910-adapt-squad-cast-to-hve-core-c8c5e94.md`.
* "`apm.yml` `version:` and `CHANGELOG.md` are untouched" — **Met.** `git diff` shows no `version:` line change (`0.16.2`) and no `CHANGELOG.md` change.
* "Docs naming a changed agent or role are updated, or the PR states that none do" — **Met.** Full sweep of `README.md`, `CONTRIBUTING.md`, and `docs/` found no references to the retired agent's name; stated explicitly here per the issue's instruction.
* "`Get-HveCoreCastDelta.ps1` reports a non-breaking verdict" — **Met.** Re-run with `-FromRef abeea85e70290fe9657989fd4fbd4e93afabca3d -ToRef c8c5e94ecd22438e21460bd4b2064f8516f55603` against the updated `squad-src/` reports `isBreaking: False`, `squadAtRisk: {}`, verdict text "non-breaking surface change" (see below).

## 2026-09-10 — Cast Delta Re-Verification

```
Comparing microsoft/hve-core surface: abeea85e70290fe9657989fd4fbd4e93afabca3d -> c8c5e94ecd22438e21460bd4b2064f8516f55603

# hve-core surface delta

- Repository: microsoft/hve-core
- From: abeea85e70290fe9657989fd4fbd4e93afabca3d (currently pinned)
- To: c8c5e94ecd22438e21460bd4b2064f8516f55603 (c8c5e94ecd22438e21460bd4b2064f8516f55603)
- Surfaces compared: agents, skills, prompts
- Verdict: non-breaking surface change

hasDelta       : True
isBreaking     : False
squadAtRisk    : {}
```

The removed/added agent matches the issue's attached delta report exactly (`Code Review PR` removed; `Code Review Orientation` added, dispatchable in principle). `squadAtRisk` is empty because every squad-src reference to the retired agent's exact name was removed or reworded to avoid the exact-match scan pattern while still reading as accurate history.

## Outcome

All eight acceptance criteria are **Met**. `squad-src/` now resolves every roster Primary and Alternate to a dispatchable name; this delta required no new squad-owned charter, because the retired agent's only casting was as a `tester` Alternate whose PR-readiness coverage was already fully absorbed by the still-cast `Code Review Readiness`, and its walkthrough capability moved into an orchestrator-internal stage that the *Worker Agents Are Not Roles* test correctly excludes from the roster. `apm.yml` is pinned to `c8c5e94ecd22438e21460bd4b2064f8516f55603`. A minor change fragment is staged. This run's file changes are left uncommitted in the working tree for the separate automated step to stage, commit, push, and open the draft pull request.

## History Files

* `.copilot-tracking/squad/members/issue-109/history/Squad Implementor.md` — implementation dispatch record (Cast Catalog row edit, both coordinators' `agents:` frontmatter edit, `apm.yml` regeneration, change fragment).
* `.copilot-tracking/squad/members/issue-109/history/Squad Reviewer.md` — verification dispatch record (dispatchability and worker-contract re-check against the cloned hve-core tree, docs sweep, cast-delta re-run).
* `.copilot-tracking/squad/members/issue-109/history/Squad Scribe.md` — orchestration record for the turn that seeded this sub-squad and wrote this ledger.

## Blocking findings

None. No Stop-verdict, Risk: High, compliance, or divergence findings were raised during this run.
