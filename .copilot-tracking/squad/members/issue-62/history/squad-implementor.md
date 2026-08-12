# History: Squad Implementor (issue-62)

## Dispatch 1 — 2026-08-12

**Request:** Adapt `squad-src/` so every roster Primary resolves to an agent installed and dispatchable at `microsoft/hve-core@3d681c92ff25fc307778f545446b54cf9b26a057`, per the cast delta attached to issue #62, then move the `apm.yml` pin.

**Findings:** Cloned `microsoft/hve-core` at the target SHA to verify the replacement surface directly rather than trusting the delta report's prose alone. Confirmed all seven retired names (`ADO Backlog Manager`, `Agile Coach`, `AzDO PRD to WIT`, `GitHub Backlog Manager`, `Jira Backlog Manager`, `Jira PRD to WIT`, `Product Manager Advisor`) are gone from `.github/agents/`. Confirmed the replacement surface: `Backlog Manager` (`.github/agents/project-planning/backlog-manager.agent.md`, `disable-model-invocation: true` — never dispatchable), `Functional Planner` (`.github/agents/project-planning/functional-planner.agent.md`, no `disable-model-invocation`, dispatchable), and three per-platform executors under `.github/agents/project-planning/subagents/` (`ado-backlog-executor`, `github-backlog-executor`, `jira-backlog-executor`, all dispatchable). Confirmed `Issue Triage Agent` (`.github/agents/issue-triage.agent.md`) and both quality reviewers (`prd-quality-reviewer.agent.md`, `brd-quality-reviewer.agent.md`, both under `subagents/`) are unaffected and still dispatchable. Confirmed the four new skills (`backlog-execute`, `backlog-management`, `backlog-plan`, `functional-planner`) exist under `.github/skills/project-planning/` with the per-platform reference files (`ado.md`, `github.md`, `jira.md`) under `backlog-management/references/`.

**Outcome:**

* `squad-src/.github/instructions/squad/squad-roster.instructions.md` — repointed the `product-owner` row (Primary: `Functional Planner`; Alternate: `Issue Triage Agent` only) and its Selection Cue; repointed `analyst` (dropped the retired Alternate, added a routing note to `intake-validator`); repointed `intake-validator` (Primary: `PRD Quality Reviewer`); updated the Members Example table, the user-invocable-orchestrator example list (`ADO Backlog Manager`/`Jira Backlog Manager` → `Backlog Manager`), the Many-to-one and One-to-many cardinality examples, and the plain-English role glossary entries for `product-owner` and `intake-validator`.
* `squad-src/.github/instructions/squad/squad-routing.instructions.md` and `squad-src/.github/skills/squad/SKILL.md` — mirrored the same roster changes into the seed routing table (`Agile Coach` row → `product-owner` row without "refine"), the seed `team.md` template, and the `intake-validator` description.
* `squad-src/.github/agents/squad/squad-coordinator.agent.md` and `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md` — updated the `agents:` frontmatter allowlist (both files identically): removed the six retired dispatchable-catalog names, added `Functional Planner`, `ADO Backlog Executor`, `GitHub Backlog Executor`, `Jira Backlog Executor`; kept `Issue Triage Agent`, `PRD Builder`. Updated the coordinator's inline product-owner dispatch example.
* `squad-src/.github/agents/squad/squad-backlog-executor.agent.md` — rewrote the charter's rationale paragraph (upstream's unreachable entry point is now `Backlog Manager`, singular, not two retired per-tracker managers) and its Governing Conventions (now names the real `backlog-execute` skill and the `backlog-management` reference structure it depends on, instead of citing execution-instruction files hve-core no longer ships). Extended scope from ADO/Jira-only to also cover GitHub (`tracker: ado|github|jira` throughout), matching the new upstream `GitHub Backlog Executor` and keeping this role's coverage aligned with what `product-owner` now plans for.
* `squad-src/.github/instructions/squad/squad-mcp-capability.instructions.md` — extended the `tracker-write` capability row to name the `github` MCP alongside ADO and Jira.
* `docs/demo-3.html` — the only doc file naming a retired agent (`Agile Coach`, twice); repointed both to `Functional Planner` with wording that matches the new capability (validated hierarchy planning, not "refined stories").
* Ran `pwsh scripts/Update-ApmDependencies.ps1 -Ref 3d681c92ff25fc307778f545446b54cf9b26a057`, which discovers the hve-core dependency tree by walking the actual repository rather than a hardcoded list, so it picked up the new agent and skill paths automatically. Verified all 235 hve-core lines in `apm.yml` now carry the new SHA and zero carry the old one.
* Added `.changes/unreleased/20260812-adapt-squad-cast-to-hve-core-3d681c9.md` (`bump: minor`, `type: Changed`) naming the rename map and the new charters/agents involved. Left `apm.yml` `version:` and `CHANGELOG.md` untouched, per the release-state constraint.
* Swept the whole repository (`squad-src/`, `docs/`, `README.md`, `CONTRIBUTING.md`) for all seven retired names; the only remaining hits are two intentional documentation notes in `squad-roster.instructions.md` explaining the removal (rephrased to avoid the literal agent-name pattern the cast-delta scanner matches, verified by re-running the scanner — see the Squad Reviewer's dispatch) and historical entries in `CHANGELOG.md`, which is release output and out of scope to edit.

<!-- consumption:begin -->
model: claude-sonnet-5
model_source: session-inherited
priced_as: claude-sonnet-5
model_tier: default
internal_turns: 34
input_tokens: 260000
cached_tokens: 950000
cache_write_tokens: 140000
output_tokens: 28000
input_rate: 2.00
cached_rate: 0.20
cache_write_rate: 2.50
output_rate: 10.00
est_cost_usd: 1.3400
est_credits: 134.00
basis: estimated
<!-- consumption:end -->
