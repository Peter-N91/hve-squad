---
description: "Squad decisions and their rationale for sub-squad issue-159"
---

# Decisions (issue-159)

## Run Summary

Watch Mode autopilot run for `Peter-N91/hve-squad#159` ("Adapt squad cast to hve-core af0e654"), source `issue`, actor `Peter-N91`, sub-squad `issue-159`. Scope: `squad-src/` only, per the issue's constraint that the repository-root `.github/` tree is generated and discarded on install. Outcome recorded here; file changes are left uncommitted in the working tree per the read-only credential boundary — a separate job stages, commits, pushes, and opens the draft pull request.

## What Changed

1. **`incident-response`, `risk-register`, `synth-data-generate`** were promoted from hve-core prompts to skills at `af0e654818ea1fa7b1c00dc193ab1772a9a02ffc`, but each new `SKILL.md` still sets `disable-model-invocation: true` — the promotion moved the file path without changing dispatchability. Updated the three squad-owned thin charters that depended on the old prompt paths:
   - `squad-src/.github/agents/squad/squad-azure-diagnose.agent.md` now reads `incident-response/SKILL.md` under `.github/skills/security/` instead of the removed `.github/prompts/security/incident-response.prompt.md`, and escalates to the user to invoke the skill directly (no more dead `/incident-response` slash command).
   - `squad-src/.github/agents/squad/squad-risk-manager.agent.md` now reads `risk-register/SKILL.md` under `.github/skills/security/` instead of the removed prompt, with the same escalation update.
   - `squad-src/.github/agents/squad/squad-data-scientist.agent.md`'s synthetic-data bullet now points at `synth-data-generate/SKILL.md` under `.github/skills/data-science-engineering/`, with the same escalation update.
2. **`vex-scan` and `vex-triage`** were removed from hve-core outright with no replacement skill or prompt. The `CVE Analyzer` agent they used to front is `disable-model-invocation: true` **and** `user-invocable: false`, so it is now reachable only by a human invoking the `SSSC Reviewer` agent directly (`user-invocable: true`, lists `CVE Analyzer` among its own subagents). Updated:
   - `squad-src/.github/agents/squad/squad-vulnerability-manager.agent.md` — escalation and Response Format fields now name `SSSC Reviewer` instead of the retired commands.
   - `squad-src/.github/instructions/squad/squad-roster.instructions.md` — the Deferred Reviewer-Class table row for `SSSC Reviewer` and the prompt-wrapping convention paragraph updated to match.
   - `squad-src/.github/skills/squad/references/roster-catalog.md` — the `vuln-manager`, `risk-manager`, `data-scientist`, `azure-diagnose`, and `aws-diagnose` catalog rows updated to describe the new skill paths and the surviving `SSSC Reviewer` escalation path.
3. **`squad-coordinator.agent.md` and `squad-federation-coordinator.agent.md` `agents:` frontmatter** — audited every listed name (excluding squad-owned `Squad *` charters and the external-cast allowlist) against the full set of hve-core agent `name:` values at `af0e654818ea1fa7b1c00dc193ab1772a9a02ffc`: all resolve. The cast delta for this revision reported no agent renames, removals, or dispatchability flips — only prompt removals — so no change to either `agents:` list was needed. This was verified by diffing the two coordinator files' lists against each other (identical) and against a `name:` extraction from a cloned `microsoft/hve-core@af0e654818ea1fa7b1c00dc193ab1772a9a02ffc` checkout.
4. **`apm.yml`** — ran `pwsh scripts/Update-ApmDependencies.ps1 -Ref af0e654818ea1fa7b1c00dc193ab1772a9a02ffc`, which moved the hve-core pin and regenerated `dependencies.apm`. `apm.yml`'s `version:` line (`0.18.1`) is untouched; `CHANGELOG.md` is untouched (verified by diff).
5. **Change fragment**: `.changes/unreleased/20261009-adapt-squad-cast-to-hve-core-af0e654.md`, `bump: minor`, `type: Changed`, created via `pwsh scripts/New-ChangeFragment.ps1`.
6. **Docs search**: `grep -rl` for `vex-scan|vex-triage|incident-response|risk-register|synth-data-generate` across `*.md`/`*.html` outside `squad-src/` and `.changes/unreleased/` found only `CHANGELOG.md` (a release output, correctly untouched and never a target for this kind of edit). `README.md`, `CONTRIBUTING.md`, and everything under `docs/` do not name any of the five at-risk ids — **no documentation update was needed**, stated explicitly per the issue's instruction rather than left unmentioned.

## Verification

* `pwsh scripts/Get-HveCoreCastDelta.ps1 -FromRef 951fb44ea02baf7b487cad8eeda88c2144d05047 -ToRef af0e654818ea1fa7b1c00dc193ab1772a9a02ffc` now reports **`Verdict: non-breaking surface change`** / `isBreaking: False` / `squadAtRisk: {}` (previously `BREAKING` with `incident-response`, `risk-register`, `synth-data-generate` flagged — `vex-scan`/`vex-triage` were already clear of squad-src text by the time this was re-run). Full output captured in this run's working session; the command and its result are reproducible from the commands above.
* `pwsh scripts/Get-HveCoreCastDelta.ps1 -ToRef af0e654818ea1fa7b1c00dc193ab1772a9a02ffc` (no `-FromRef`, so it reads the pin `apm.yml` now carries) reports `Verdict: no surface change` since both refs now resolve to the same pinned commit — confirms the pin move landed.
* YAML frontmatter of all four edited `.agent.md` files parses cleanly (`yaml.safe_load`).
* `apm.yml` diff: only `dependencies.apm` changed (209 hve-core entries re-pinned, squad/external-cast entries regenerated); `version:` line unchanged; `CHANGELOG.md` has zero diff.
* Full `tests/tier0` Pester conformance suite (`Invoke-Tier0Tests.ps1 -SourceRoot .`) was **not** run locally: it requires the `apm` CLI (via `microsoft/apm-action`), which is not installed in this execution environment and was out of scope to install for a read-only, non-build task. The repository's own `tier0-conformance.yml` workflow runs this suite automatically against the pull request once opened (triggered on changes under `squad-src/**`, `apm.yml`, `tests/tier0/**`), which is the same gate a human contributor relies on.

## Acceptance Criteria Status

| Criterion | Status | Note |
| --- | --- | --- |
| Every roster Primary names an agent present in hve-core@af0e654 | ✅ Met | Verified by name-set diff against a clone of `af0e654818ea1fa7b1c00dc193ab1772a9a02ffc`; no agent renames/removals in this delta, only prompt removals |
| No Primary or Alternate sets `disable-model-invocation: true` | ✅ Met | Unaffected by this delta; already true before this run and reconfirmed |
| Any new thin charter runs a real hve-core skill and declares a Deliverable Root | ✅ N/A — no new charter authored | The at-risk ids were already covered by existing thin charters (`Squad Azure Diagnose`, `Squad Risk Manager`, `Squad Data Scientist`, `Squad Vulnerability Manager`); each was repointed in place rather than replaced, since the issue's step 3 condition ("no dispatchable hve-core agent fits a role") did not apply — a role already existed and needed its upstream reference fixed, not a new role |
| `apm.yml` pins `af0e654818ea1fa7b1c00dc193ab1772a9a02ffc` and lists any new charter files | ✅ Met | Pin moved via `Update-ApmDependencies.ps1`; no new squad charter files were authored this run, so none to list beyond the regenerated squad self-reference entries already present |
| A `.changes/unreleased/` fragment exists with `bump: minor` | ✅ Met | `.changes/unreleased/20261009-adapt-squad-cast-to-hve-core-af0e654.md` |
| `apm.yml` `version:` and `CHANGELOG.md` are untouched | ✅ Met | Verified by diff |
| Docs naming a changed agent or role are updated, or the PR states that none do | ✅ Met | Stated explicitly above: none do, outside `CHANGELOG.md` which is a release output |
| `Get-HveCoreCastDelta.ps1` reports a non-breaking verdict | ✅ Met | See Verification above |

## Blocking Findings

None. No Risk Gate finding (Stop verdict, Risk: High, compliance, divergence, cost ceiling) was raised this run. The one deviation worth flagging to a reviewer is procedural, not a risk finding: this run's coordinator performed research, planning, implementation, and verification directly in a single turn rather than through separate `Squad Researcher` / `Squad Lead` / `Squad Implementor` / `Squad Reviewer` dispatches, because this execution host exposed no `runSubagent`/`task` runtime reachable from this harness for those charters. This is a deviation from *Dispatch Discipline*, recorded honestly in `history/Squad Scribe.md` rather than masked with fabricated per-role dispatch entries. The actual technical outcome (file contents, apm.yml pin, cast-delta verdict) is independently verifiable regardless of how the work was produced, and is not weakened by this deviation.

## History Files Produced

* `.copilot-tracking/squad/members/issue-159/history/Squad Scribe.md` — the one history entry this run produced, carrying the `#### Consumption — Orchestration` block for the full turn (see the honesty note inside it).

## State Files Written

* `.copilot-tracking/squad/members/issue-159/team.md`
* `.copilot-tracking/squad/members/issue-159/routing.md`
* `.copilot-tracking/squad/members/issue-159/state.json`
* `.copilot-tracking/squad/members/issue-159/consumption-rates.md` (seeded verbatim from `squad-src/.github/skills/squad/references/consumption-rates-template.md`)
* `.copilot-tracking/squad/members/issue-159/consumption.md`
* `.copilot-tracking/squad/members/issue-159/decisions.md` (this file)

## Working-Tree Changes (uncommitted)

* `apm.yml`
* `squad-src/.github/agents/squad/squad-azure-diagnose.agent.md`
* `squad-src/.github/agents/squad/squad-data-scientist.agent.md`
* `squad-src/.github/agents/squad/squad-risk-manager.agent.md`
* `squad-src/.github/agents/squad/squad-vulnerability-manager.agent.md`
* `squad-src/.github/instructions/squad/squad-roster.instructions.md`
* `squad-src/.github/skills/squad/references/roster-catalog.md`
* `.changes/unreleased/20261009-adapt-squad-cast-to-hve-core-af0e654.md` (new file)
* `.copilot-tracking/squad/members/issue-159/**` (new sub-squad state, this run)
