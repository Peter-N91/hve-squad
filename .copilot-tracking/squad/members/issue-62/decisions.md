# Squad Decisions (issue-62)

## 2026-08-12 — Intake Readiness Verdict

**Verdict:** Ready. Issue #62 ("Adapt squad cast to hve-core@3d681c9") supplies a concrete, self-contained brief with an attached cast delta report naming every removed agent, its file references, and hve-core's replacement surfaces (agents, skills). No external inputs or clarification were required.

## 2026-08-12 — Root Cause

`microsoft/hve-core` moved from `db1be8f09a91525ff0412d38c581e1cd6922e01b` to `3d681c92ff25fc307778f545446b54cf9b26a057` (`refactor(collections)!: consolidate platform backlog collections into project-planning`), which removed the entire `product-owner`-adjacent backlog cast: `ADO Backlog Manager`, `Agile Coach`, `AzDO PRD to WIT`, `GitHub Backlog Manager`, `Jira Backlog Manager`, `Jira PRD to WIT`, and `Product Manager Advisor`. hve-core replaced them with a consolidated `project-planning` surface: `Backlog Manager` (user-invocable-only orchestrator, `disable-model-invocation: true`), `Functional Planner` (dispatchable PRD→work-item-hierarchy planner spanning Azure DevOps, GitHub, and Jira), and three dispatchable per-platform write executors (`ADO Backlog Executor`, `GitHub Backlog Executor`, `Jira Backlog Executor`), plus four new skills (`backlog-execute`, `backlog-management`, `backlog-plan`, `functional-planner`). Eighteen `ado`/`github`/`jira` prompts were also removed with no replacements (their capability moved into the new skills).

## 2026-08-12 — Fix Approach

* **`product-owner`** — Primary repointed from `GitHub Backlog Manager` to the new dispatchable `Functional Planner`, which performs the exact PRD-to-work-item-hierarchy planning this role needs across all three trackers via a `platform` argument. Kept `Issue Triage Agent` (still shipped, dispatchable) as the single-issue-triage Alternate. Dropped the `AzDO PRD to WIT`, `Jira PRD to WIT`, and `Agile Coach` Alternates and their Selection Cues (subsumed by `Functional Planner`'s cross-platform planning).
* **`analyst`** — Dropped the `Product Manager Advisor` Alternate (no replacement ships); added a note routing "requirements validation" requests to `intake-validator` instead.
* **`intake-validator`** — Primary repointed from the now-removed `Product Manager Advisor` to `PRD Quality Reviewer` (already an Alternate, dispatchable, standards-conformance reviewer), keeping `BRD Quality Reviewer` as the BRD-input Alternate.
* **`backlog-executor`** (`Squad Backlog Executor`, squad-owned thin charter) — Updated its rationale (HVE Core's write-blocking entry point is now `Backlog Manager`, not the two retired per-tracker managers) and its Governing Conventions to run the new `backlog-execute` skill (which resolves the `backlog-management` skill's per-platform reference and dispatches to the matching `ADO/GitHub/Jira Backlog Executor`) instead of citing execution-instruction files hve-core no longer ships. Extended its scope from Azure DevOps/Jira-only to also cover GitHub, matching the new upstream GitHub executor and keeping the roster's `product-owner`/`backlog-executor` split intentional and complete rather than silently narrower than the upstream surface.
* Updated the `agents:` frontmatter allowlist in `squad-coordinator.agent.md` and `squad-federation-coordinator.agent.md` (both): removed the six retired names, added `Functional Planner`, `ADO Backlog Executor`, `GitHub Backlog Executor`, `Jira Backlog Executor`; kept `Issue Triage Agent`. Updated the coordinator's product-owner dispatch example.
* Updated `squad-roster.instructions.md` (Cast Catalog rows for `product-owner`, `analyst`, `intake-validator`; the Members Example; the user-invocable-orchestrator example list; the Many-to-one and One-to-many cardinality examples; the plain-English role glossary entries) and mirrored the same catalog changes into `squad-routing.instructions.md` and `.github/skills/squad/SKILL.md` (seed template roster, default routing table, intake-validator description).
* Extended `squad-mcp-capability.instructions.md`'s `tracker-write` capability row to name the `github` MCP alongside ADO and Jira, since `backlog-executor` now writes GitHub too.
* Updated `docs/demo-3.html`, the only doc naming the retired `Agile Coach` by name, to name `Functional Planner` instead.
* Ran `scripts/Update-ApmDependencies.ps1 -Ref 3d681c92ff25fc307778f545446b54cf9b26a057`, which auto-discovers the hve-core tree (no hardcoded name list) and moved every `apm.yml` dependency pin, picking up the new agent and skill files automatically.
* Added `.changes/unreleased/20260812-adapt-squad-cast-to-hve-core-3d681c9.md` with `bump: minor` (a cast change is not a patch: the roster that ships is not the one that shipped before).

## 2026-08-12 — Risk Gate

No Stop-verdict findings. Change is squad-owned documentation, instruction, and thin-charter markdown (roster catalog, routing table, skill seed template, coordinator agent frontmatter allowlists, one docs page) plus a mechanical, auto-generated `apm.yml` dependency-pin regeneration. No code execution paths, secrets, migrations, deployments, or live tracker writes are touched — `Squad Backlog Executor` remains behind its existing Impactful-Action Gate and this change only redirects which upstream skill/agent it reaches through, never loosening the gate. Risk: Low.

## 2026-08-12 — Acceptance Criteria Status

* "Every roster Primary names an agent present in hve-core@3d681c9" — **Met.** `product-owner → Functional Planner`, `intake-validator → PRD Quality Reviewer`; every other Primary was already unaffected by this delta.
* "No Primary or Alternate sets `disable-model-invocation: true`" — **Met.** `Functional Planner`, `Issue Triage Agent`, `PRD Quality Reviewer`, `BRD Quality Reviewer`, `ADO/GitHub/Jira Backlog Executor` are all dispatchable (verified against the cloned `3d681c92ff25fc307778f545446b54cf9b26a057` tree); `Backlog Manager` (`disable-model-invocation: true`) is referenced only as context for why it is unreachable, never cast as a Primary or Alternate.
* "Any new thin charter runs a real hve-core skill and declares a Deliverable Root" — **Met, no new charter needed.** `Squad Backlog Executor` (pre-existing squad-owned charter) now runs the real `backlog-execute` skill; its Deliverable Root (`—`, structured payload only) is unchanged.
* "`apm.yml` pins `3d681c92ff25fc307778f545446b54cf9b26a057` and lists any new charter files" — **Met.** Verified 235/235 hve-core dependency lines carry the new SHA and zero carry the old one; `Update-ApmDependencies.ps1`'s tree-based discovery picked up `backlog-manager.agent.md`, `functional-planner.agent.md`, the three `subagents/*-backlog-executor.agent.md` files, and the four new skills automatically.
* "A `.changes/unreleased/` fragment exists with `bump: minor`" — **Met.**
* "`apm.yml` `version:` and `CHANGELOG.md` are untouched" — **Met.** `git diff` shows no `version:` line change and no `CHANGELOG.md` change.
* "Docs naming a changed agent or role are updated, or the PR states that none do" — **Met.** `docs/demo-3.html` (two `Agile Coach` mentions) updated to `Functional Planner`. Full sweep of `README.md`, `CONTRIBUTING.md`, and `docs/` for the seven retired names found no other hits; `CHANGELOG.md` hits are historical release entries and are correctly left untouched per the release-state constraint.
* "`Get-HveCoreCastDelta.ps1` reports a non-breaking verdict" — **Met.** Re-run with `-FromRef db1be8f09a91525ff0412d38c581e1cd6922e01b -ToRef 3d681c92ff25fc307778f545446b54cf9b26a057` against the updated `squad-src/` reports `isBreaking: False`, `squadAtRisk: {}` (see the pasted output below).

## 2026-08-12 — Cast Delta Re-Verification

```
Comparing microsoft/hve-core surface: db1be8f09a91525ff0412d38c581e1cd6922e01b -> 3d681c92ff25fc307778f545446b54cf9b26a057

# hve-core surface delta

- Repository: microsoft/hve-core
- From: db1be8f09a91525ff0412d38c581e1cd6922e01b (previously pinned)
- To: 3d681c92ff25fc307778f545446b54cf9b26a057 (3d681c92ff25fc307778f545446b54cf9b26a057)
- Surfaces compared: agents, skills, prompts
- Verdict: non-breaking (squad references only agents/skills this ref still exposes)

hasDelta       : True
isBreaking     : False
squadAtRisk    : {}
```

Full list of removed/added agents, added skills, and removed prompts matches the issue's attached delta report exactly; `squadAtRisk` is empty because every squad-src reference to the seven retired names was repointed.
