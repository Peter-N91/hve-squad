# History: Squad Reviewer (issue-66)

## Dispatch 1 — 2026-08-14

**Request:** Verify the Squad Implementor's cast-adaptation work against issue #66's acceptance criteria: every roster Primary dispatchable, no `disable-model-invocation: true` Primary/Alternate, new charters run a real skill and declare a Deliverable Root, `apm.yml` pin and new-file inclusion, a minor change fragment, `version:`/`CHANGELOG.md` untouched, docs coverage, and a non-breaking `Get-HveCoreCastDelta.ps1` verdict.

**Findings and verification steps:**

* Re-checked the cloned `microsoft/hve-core@2be87b7ffe311daddd6f5fe4a11773efd9ae03e3` tree directly: confirmed `Data Workstream Coach` is the only agent under `.github/agents/data-science/` and carries `disable-model-invocation: true`; confirmed the six named data-science/project-planning skills exist at the paths the new charter cites; confirmed `Vally Test Author` and `HVE Artifact Tester` still ship without `disable-model-invocation` set.
* Swept `squad-src/` for the five retired names (`DS Gen Data Spec`, `DS Gen Jupyter Notebook`, `DS Gen Streamlit Dashboard`, `DS Test Streamlit Dashboard`, `Evaluation Dataset Creator`) after the Implementor's edits: zero hits, including inside the new charter and the roster's own explanatory prose (both reworded to avoid the exact-match pattern).
* Ran `pwsh scripts/Get-HveCoreCastDelta.ps1 -FromRef 5cc10199d896b3d12a68b6ca40e75dca5ae97afd -ToRef 2be87b7ffe311daddd6f5fe4a11773efd9ae03e3` against the updated `squad-src/`: `hasDelta: True`, `isBreaking: False`, `squadAtRisk: {}`, verdict text "non-breaking surface change" — matches the acceptance criterion's required outcome.
* Verified `apm.yml`: 242/242 hve-core dependency lines carry `2be87b7ffe311daddd6f5fe4a11773efd9ae03e3` and zero carry the prior SHA; the regenerated squad dependency list includes `squad-src/.github/agents/squad/squad-data-scientist.agent.md`. Confirmed via `git diff` that no `version:` line and no `CHANGELOG.md` line changed.
* Verified `.changes/unreleased/20260814-adapt-squad-cast-to-hve-core-2be87b7.md` exists with `bump: minor`, `type: Changed` frontmatter and a body naming the rename map.
* Confirmed `README.md`, `CONTRIBUTING.md`, and `docs/` carry no reference to any retired name, so the "docs updated or PR states none do" criterion is satisfiable by an explicit statement rather than an edit.
* Confirmed the new `Squad Data Scientist` charter declares `outputs/` as its Deliverable Root, matching the pre-existing `data-scientist` row in `team.md`/`squad-roster.instructions.md`, and that the extended `Squad Prompt Engineer` charter's Deliverable Root (`.copilot-tracking/prompts/`) is unchanged.

**Outcome:** All nine acceptance criteria verified **Met**, no residual references to retired names, no Stop-verdict Risk Gate findings. No corrective changes were required back to the Implementor.

<!-- consumption:begin -->
model: claude-sonnet-5
model_source: session-inherited
priced_as: Claude Haiku 4.5
model_tier: fast
internal_turns: 9
input_tokens: 65000
cached_tokens: 230000
cache_write_tokens: 35000
output_tokens: 6000
input_rate: 1.00
cached_rate: 0.10
cache_write_rate: 1.25
output_rate: 5.00
est_cost_usd: 0.1610
est_credits: 16.10
basis: estimated
<!-- consumption:end -->
