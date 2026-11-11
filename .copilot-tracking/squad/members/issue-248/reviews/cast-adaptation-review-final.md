# Review (second pass): cast adaptation to hve-core f425e94 (issue #248)

Reviewer: Squad Reviewer · Sub-squad: issue-248 · Date: 2026-11-10
Supersedes for current status: `reviews/cast-adaptation-review.md` (first pass, retained unchanged).
Inputs: prior review `reviews/cast-adaptation-review.md`, updated change record `changes/cast-adaptation-change.md` (including "## Follow-up: presenter role removal"), working tree.
Implementation was not modified by this review. No git commit, push, or gh command was run.

Verdict: Fail

(Brief's terms: **changes-needed**. Scope is narrow: two live docs sentences and one dangling federation pointer. The G1 role-removal blockers from the first pass are resolved in squad-src.)

## 1. `presenter` grep (squad-src/, docs/, tests/)

Command: `grep -rn -i "presenter" squad-src docs tests` returns 9 hits. Each is classified below.

| # | Location | Text (abridged) | Classification |
|---|---|---|---|
| 1 | `squad-src/.github/instructions/squad/squad-autopilot.instructions.md:71` | "the `presenter` role was removed from the roster (historical note)" | Removal note. OK |
| 2 | `squad-src/.github/instructions/squad/pptx-brand-template.instructions.md:8` | "removed upstream ... The squad no longer has a `presenter` role" | Removal note. OK |
| 3 | `docs/usage.html:1751` | "hve-core removed ... so the squad no longer ships a `presenter` role" | Removal note. OK |
| 4 | `docs/fr/usage.html:1751` | "la squad ne fournit donc plus de rôle `presenter`" | Removal note. OK |
| 5 | `docs/demo-3.html:207` | "the `presenter` role ... were removed with hve-core f425e94 ... treat it as a historical walkthrough" | Removal note. OK |
| 6 | `docs/fr/demo-3.html:216` | "le rôle `presenter` ... ont été supprimés avec hve-core f425e94 ... parcours historique" | Removal note. OK |
| 7 | `docs/demo-3.html:248` | "the `product` profile resolves `analyst`, ..., `presenter`, and `technical-writer` to deployed HVE Core agents" | **LIVE assertion. Not historical.** States `presenter` is a current `product` profile member that resolves to a deployed agent. False after this change. |
| 8 | `docs/fr/demo-3.html:259` | "le profil `product` associe ... `presenter` ... aux agents HVE Core déployés" | **LIVE assertion. Not historical.** Same defect, French copy. |
| 9 | `tests/tier0/Performance.Tests.ps1:354` | code comment "hve-core f425e94 removed the powerpoint skill and presenter role" | Historical code comment. OK |

Result: squad-src has no live `presenter` assertion. The `product`/`full` profiles, seed rows, routing, and model-routing no longer name it. Two docs sentences (hits 7 and 8) still assert the role exists. The change record's claim that the demo-3 "troubleshooting profile row" was removed is not accurate for these two rows.

Also confirmed: `concepts.html` (EN and FR) and `usage.html` product-profile lines no longer contain `presenter`.

## 2. Cast-delta script (verbatim verdicts)

### 2a. Substantive run: `-FromRef 17072823c75d6e8cdf288d8ed4371f555dcd09bb -ToRef f425e943bf228052a23e6bc4810b5faef030314f`

Exit code 0. Verbatim verdict and result fields:

```
- Verdict: **BREAKING** - the squad references agents, skills, or prompts this ref no longer exposes

| Id | Kind | Why | References in squad-src |
| `PowerPoint Builder` | agent | removed from hve-core | 1 |
| `PowerPoint Subagent` | agent | removed from hve-core | 1 |
| `powerpoint` | skill | removed from hve-core | 3 |

Invocability changed: `hve-slides` user-invocable-only -> model-invocable
Added: `rpi` - `.github/skills/rpi/rpi/SKILL.md`

hasDelta       : True
isBreaking     : True
```

Expected and confirmed. The BREAKING verdict comes from the PowerPoint agent pair and the `powerpoint` skill, which hve-core removed at f425e94. The three squad-src hits are the intentional "removed upstream" notes, which the script cannot distinguish from live references. This run compares the old pin with the new ref, so BREAKING is the correct result.

### 2b. Current-pin run: `-ToRef f425e943bf228052a23e6bc4810b5faef030314f`

Exit code 0. Verbatim verdict and result fields:

```
Both refs resolve to f425e943bf228052a23e6bc4810b5faef030314f - no cast delta possible.
- Verdict: no surface change
The deployable agents, skills, and prompts are identical between the two refs. A mechanical SHA bump is safe.

hasDelta       : False
isBreaking     : False
```

Expected. `apm.yml` already pins f425e94, so From and To are the same ref. This run is non-breaking but vacuous, as the first pass noted. Assertion 2b does not prove the repin was safe; 2a does.

## 3. Invocability and dispatchability

* No squad-src file asserts that a `presenter` role is dispatchable. The only `presenter` hits in squad-src are the two removal notes (items 1–2 above). Confirmed.
* The five Primaries (`squad-researcher`, `squad-lead`, `squad-implementor`, `squad-reviewer`, `squad-scribe`) each have `user-invocable: false` and no `disable-model-invocation` key. Confirmed.
* Files that set `disable-model-invocation: true` (`squad-coach`, `squad-coordinator`, `squad-federation-coordinator`, `squad-learn`, `squad-backlog-executor`, `squad-vulnerability-manager`, `squad-observability-planner`, `squad-data-scientist`, `squad-risk-manager`) are not Primaries. `roster-catalog.md` mentions `disable-model-invocation: true` only for other HVE Core agents that are never Primaries or Alternates. Confirmed.

## 4. Test runs

| Command | Result |
|---|---|
| `pwsh -NoProfile -Command` with `New-PesterContainer` over `tests/tier0/Performance.Tests.ps1`, `tests/tier0/AgentDiscovery.Tests.ps1`, `tests/tier0/Manifest.Tests.ps1`, each with `-Data @{ SourceRoot = <repo root> }`, run via `Invoke-Pester -Configuration` (`PassThru`) | **Passed: 135, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0.** Exit 0. Per file: Performance 18.2s, AgentDiscovery 14.8s, Manifest 0.15s. Consistent with first pass (AgentDiscovery + Manifest = 88) plus Performance (47). |
| Full `tests/tier0/Invoke-Tier0Tests.ps1` | **Not run in this pass.** Deferred to CI, as in the first pass. |
| `npm run docs:check` / `docs:test` | **Not run in this pass.** Recommended after the docs fix below. |

Test-change observation (Low, not a failure): the follow-up added two retirement exemptions to `tests/tier0/Performance.Tests.ps1` (around lines 352–359 and 445–447). One skips any baseline sentence beginning with `**Never author a substitute deck builder.**`. The other exempts two named headings from the "missing heading" check when they are absent. The exemptions are justified by the removed capability, and the change record explains them. They weaken the guard for those named items only, and they should be retired once `prefill-baseline.json` is refreshed on a later pass.

## 5. Acceptance criteria (issue #248, as enumerated in the first pass)

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | team.md cast from canonical templates, full RPI spine (researcher/lead/developer/tester/scribe) | **Met** | `members/issue-248/team.md` maps the five roles (unchanged from first pass). |
| 2 | Full RPI stage artifacts plus `history/autopilot-run-*.md` | **Not met** | Stage artifacts present (research, plans, changes, reviews). `members/issue-248/history/` has no `autopilot-run-*.md`. The federation entry `.copilot-tracking/squad/history/issue-248.md:9` still points at `history/autopilot-run-42922858257.md`, which does not exist. |
| 3 | history/ holds verified entries for Researcher, Lead, Implementor, Reviewer, Scribe | **Met** (cosmetic notes) | `Squad Researcher.md`, `Squad Lead.md`, `Squad Implementor.md`, `Squad Scribe.md`, and now `Squad Reviewer.md` (33 lines, entry dated 2026-11-10T23:36:21Z) exist. Reviewer entry was pending in the first pass and is now written. Titles are still truncated mid-word. The Scribe file uses "Consumption — Orchestration" headings instead of "Orchestration/Dispatch". Cosmetic. |
| 4 | Every roster Primary names an agent present in hve-core@f425e94; no dangling PowerPoint references | **Met** | Literal grep: only the two removal notes (intentional) name PowerPoint agents or the skill. The `presenter` role is removed from profiles, seeds, routing, and model-routing. The substantive delta (2a) lists no roster Primary removed other than the PowerPoint pair. Presence at f425e94 is inferred from the delta, as in the first pass. |
| 5 | No Primary or Alternate sets `disable-model-invocation: true` | **Met** | Verified in section 3. |
| 6 | Any new thin charter runs a real hve-core skill and declares a Deliverable Root | **N/A** | No charter was authored (plan's scoped decision). |
| 7 | apm.yml pins f425e943…030314f and lists new charter files | **Met** | `grep -c f425e943 apm.yml` = 198. The 6 `#9db369d…` entries are `github/awesome-copilot` skills, out of scope. No new charter files. |
| 8 | `.changes/unreleased/` fragment with `bump: minor` | **Met** | `.changes/unreleased/20261110-adapt-squad-cast-to-hve-core-f425e94.md` is present (untracked). |
| 9 | apm.yml `version:` and CHANGELOG.md untouched | **Met** | `version: 0.20.0` on line 2. `CHANGELOG.md` is not in `git status`. |
| 10 | Docs naming a changed agent/role updated, or PR states none do | **Not met** | Fixed by the Implementor follow-up (verified here): `presenter` removed from `docs/concepts.html`, `docs/fr/concepts.html`, the product-profile lines in `docs/usage.html`, and the FR usage. **Still live:** `docs/demo-3.html:248` and `docs/fr/demo-3.html:259` say the `product` profile resolves `presenter` to a deployed agent. This is false after the removal. The change record's claim that the troubleshooting row was removed is inaccurate for these two rows. |
| 11 | Get-HveCoreCastDelta.ps1 reports non-breaking | **Met literally, vacuous in substance** | Current-pin run (2b): `hasDelta: False`, `isBreaking: False`. Substantive run (2a): `isBreaking: True`, expected from the PowerPoint removals. Criterion wording is satisfied only by the vacuous run. Script "From" default reads apm.yml; see first-pass Low item. |

Summary: 6 Met (1, 4, 5, 7, 8, 9), 1 Met-with-notes (3), 1 N/A (6), 1 Met-literally with vacuous substance (11), 2 Not met (2, 10).

## Findings

| Severity | Location | Issue |
|---|---|---|
| High | `docs/demo-3.html:248` and `docs/fr/demo-3.html:259` | Live docs state the `product` profile includes and resolves `presenter` to a deployed agent. The role was removed from the profile in squad-src, so the published docs contradict the product. Fix: remove `<code>presenter</code>` from the profile list in both sentences (EN and FR together). Consistent with criterion 10. |
| Medium | `.copilot-tracking/squad/history/issue-248.md:9` | Federation entry points at `members/issue-248/history/autopilot-run-42922858257.md`, which does not exist. Criterion 2 is not met. Either write the autopilot-run file or correct the pointer. |
| Low | `docs/demo-3.html` / `fr` (change record accuracy) | The change record says the demo-3 "troubleshooting profile row" was removed. Two rows still name `presenter`. Correct the record when the docs fix lands. |
| Low | `tests/tier0/Performance.Tests.ps1:352–359, 445–447` | Retirement exemptions are name-based and loosen the BEFORE-baseline guard for the removed deck capability. Justified, but retire them when the baseline is refreshed. |
| Low | `history/Squad Researcher.md`, `Squad Lead.md`, `Squad Implementor.md`, `Squad Reviewer.md` | Entry titles truncated mid-word. Cosmetic. |
| Low | `scripts/Get-HveCoreCastDelta.ps1` (behaviour, not this change) | "From" default reads apm.yml, so after a repin the default compares the pin with itself. Pass an explicit `-FromRef` for the prior pin in review runs. |
| Info | `squad-src/.github/instructions/squad/pptx-brand-template.instructions.md:8`; `squad-autopilot.instructions.md:71`; `sql-migration-advisor/SKILL.md` | Removal notes are intentional and are counted by the cast-delta script as `squadAtRisk`. |
| Info | Full tier0 suite, `prefill-baseline.json`, and `docs:check` | Not run in this pass. Residual risk on PRF-10 and the prefill baseline until CI or a local full run. |

## Plan deviations

* **Planned and done since first pass:** remove `presenter` from catalog, seeds, `full`/`product` profiles, routing, model-routing, gates-and-modes, coordinator-legacy, and the autopilot product order. Confirmed by section 1.
* **Planned, not done:** docs sweep (plan edit 12). Done in `concepts.html` and `usage.html`, but two demo-3 troubleshooting sentences were missed and are not listed as deferred.
* **Claimed in change record, not true:** demo-3 troubleshooting profile row removed (two rows remain).
* **Done differently (unchanged):** `hve-slides` path in apm.yml moved to `experimental/`, which matches upstream.

## Conditions honored

Not applicable. The plan records that no council was convened.

## Required fixes before approval

1. Remove `presenter` from the `product` profile sentence in `docs/demo-3.html:248` and `docs/fr/demo-3.html:259`. Correct the change record's claim about those rows.
2. Write `members/issue-248/history/autopilot-run-42922858257.md`, or correct the pointer in `.copilot-tracking/squad/history/issue-248.md:9`.
3. Run `npm run docs:check` (and `docs:test` if configured) after fix 1.
4. Run the full tier0 suite (or CI) to check `prefill-baseline.json` and PRF-10. Retire the Performance exemptions if the baseline is refreshed.

Once fixes 1 and 2 are in, criteria 2 and 10 can be re-verified cheaply with the same grep and file checks used here.

## Review record

Path: `.copilot-tracking/squad/members/issue-248/reviews/cast-adaptation-review-final.md` (this file). The first-pass review at `reviews/cast-adaptation-review.md` is retained unchanged. The Reviewer history entry already exists (`history/Squad Reviewer.md`).

## Overall verdict

Verdict: Fail

The core cast adaptation is correct. The pin is at f425e94 (198 hve-core entries), `version:` and CHANGELOG are untouched, the Primaries are non-invocation-disabled, and squad-src no longer dispatches a `presenter` role. Two items keep the review at changes-needed: live docs (demo-3 EN/FR) still say `presenter` is a `product` profile member, and the federation history pointer is dangling (criterion 2). Both are small, mechanical fixes.
