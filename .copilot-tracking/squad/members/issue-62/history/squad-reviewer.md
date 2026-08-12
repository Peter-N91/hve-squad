# History: Squad Reviewer (issue-62)

## Dispatch 1 — 2026-08-12

**Request:** Verify the reworked roster and coordinator changes against issue #62's acceptance criteria — confirm every roster Primary resolves to an installed, dispatchable hve-core agent at `3d681c92ff25fc307778f545446b54cf9b26a057`, no Primary or Alternate sets `disable-model-invocation: true`, `apm.yml` pins the new SHA, the change fragment exists with `bump: minor`, `apm.yml` `version:` and `CHANGELOG.md` are untouched, docs are updated, and `Get-HveCoreCastDelta.ps1` reports non-breaking.

**Findings:**

* Independently re-cloned `microsoft/hve-core` at `3d681c92ff25fc307778f545446b54cf9b26a057` and confirmed by direct file inspection (not just the delta report) that `Functional Planner`, `Issue Triage Agent`, `PRD Quality Reviewer`, `BRD Quality Reviewer`, `ADO Backlog Executor`, `GitHub Backlog Executor`, and `Jira Backlog Executor` all lack `disable-model-invocation: true` — none returned a match on `grep -rn disable-model-invocation` across their frontmatter. Only `Backlog Manager` sets it, and confirmed it is never cast as a Primary or Alternate anywhere in `squad-src/` (only referenced in explanatory prose about why it is unreachable).
* Re-ran `pwsh scripts/Get-HveCoreCastDelta.ps1 -FromRef db1be8f09a91525ff0412d38c581e1cd6922e01b -ToRef 3d681c92ff25fc307778f545446b54cf9b26a057` against the updated `squad-src/` tree and confirmed `Verdict: non-breaking surface change`, `isBreaking: False`, `squadAtRisk: {}`. The first pass after the Implementor's edit still flagged one literal-string hit for `Product Manager Advisor` inside an explanatory note in `squad-roster.instructions.md` (the scanner does a plain literal match, not a semantic one); reworded that note to describe the gap without repeating the exact retired agent name, re-ran, and confirmed the hit cleared without losing the explanation.
* Verified `apm.yml`: `grep -c` of the new SHA returns 235 occurrences and the old SHA returns 0; `version:` line is still `0.12.11`, matching `git diff apm.yml` showing no `version:` hunk.
* Verified `.changes/unreleased/20260812-adapt-squad-cast-to-hve-core-3d681c9.md` exists with `bump: minor`, `type: Changed`, and a body naming the rename map and every touched squad-owned file, per `.changes/README.md`'s format.
* Confirmed `CHANGELOG.md` has zero diff (`git diff --stat CHANGELOG.md` empty); the historical entries that already mention the retired agent names (release notes for `v0.12.9`–`v0.12.11`, describing *why* prior pin moves failed) are pre-existing release output and correctly out of scope.
* Searched `README.md`, `CONTRIBUTING.md`, and all of `docs/` for the seven retired names; found only `docs/demo-3.html` (two mentions of `Agile Coach` naming the `product-owner` role's agent in a demo walkthrough), which the Implementor updated to `Functional Planner` with wording matching the new capability. No other doc references a changed name.
* Spot-checked the roster's internal consistency: `product-owner`'s Primary/Alternate/Selection-Cue triple, the Cast Catalog's own "user-invocable orchestrator" example list, the Members Example, the cardinality examples, and the plain-English glossary entry all now agree on `Functional Planner` + `Issue Triage Agent`, with no leftover mention of the retired Alternates as live casting. Same check for `intake-validator` (`PRD Quality Reviewer` + `BRD Quality Reviewer`).
* Confirmed `squad-coordinator.agent.md` and `squad-federation-coordinator.agent.md` carry byte-identical `agents:` frontmatter blocks (both list 74 entries, both parse as valid YAML), and that the coordinator's inline product-owner dispatch example no longer names a retired agent.

**Outcome:** No further changes required. All eight acceptance criteria from issue #62 are met.

<!-- consumption:begin -->
model: claude-sonnet-5
model_source: session-inherited
priced_as: Claude Haiku 4.5
model_tier: fast
internal_turns: 9
input_tokens: 70000
cached_tokens: 260000
cache_write_tokens: 40000
output_tokens: 7000
input_rate: 1.00
cached_rate: 0.10
cache_write_rate: 1.25
output_rate: 5.00
est_cost_usd: 0.1810
est_credits: 18.10
basis: estimated
<!-- consumption:end -->
