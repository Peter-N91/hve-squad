# Review: cast adaptation to hve-core f425e94 (issue #248)

Reviewer: Squad Reviewer · Sub-squad: issue-248 · Date: 2026-11-10
Inputs: plan `plans/cast-adaptation-plan.md`, change record `changes/cast-adaptation-change.md`, research `research/2026-11-10/cast-delta-research.md`, working-tree diff (squad-src/, apm.yml, docs/, .changes/unreleased/).
Implementation was not modified by this review.

Verdict: Fail

(Brief's terms: changes-needed. Blocking gap G1 below.)

## Cast-delta script output (verbatim)

### Required run: ToRef f425e943bf228052a23e6bc4810b5faef030314f

```
Comparing microsoft/hve-core surface: f425e943bf228052a23e6bc4810b5faef030314f -> f425e943bf228052a23e6bc4810b5faef030314f
Both refs resolve to f425e943bf228052a23e6bc4810b5faef030314f - no cast delta possible.

# hve-core surface delta

- Repository: `microsoft/hve-core`
- From: `f425e943bf228052a23e6bc4810b5faef030314f` (currently pinned)
- To: `f425e943bf228052a23e6bc4810b5faef030314f` (`f425e943bf228052a23e6bc4810b5faef030314f`)
- Surfaces compared: agents, skills, prompts
- Verdict: no surface change

The deployable agents, skills, and prompts are identical between the two refs. A mechanical SHA bump is safe.

hasDelta       : False
isBreaking     : False
added          : {}
removed        : {}
dispatchFlips  : {}
skillsAdded    : {}
skillsRemoved  : {}
skillFlips     : {}
promptsAdded   : {}
promptsRemoved : {}
squadAtRisk    : {}
EXIT=0
```

**Reading this verdict.** The script's "From" is read from apm.yml, which the change has already repinned to f425e94. The run therefore compares f425e94 with itself. The literal criterion (non-breaking) is satisfied, but the run proves nothing about the change.

### Substantive run: FromRef 17072823c75d6e8cdf288d8ed4371f555dcd09bb (prior pin) to ToRef f425e94

```
Comparing microsoft/hve-core surface: 17072823c75d6e8cdf288d8ed4371f555dcd09bb -> f425e943bf228052a23e6bc4810b5faef030314f

# hve-core surface delta

- From: `17072823c75d6e8cdf288d8ed4371f555dcd09bb` (currently pinned)
- To: `f425e943bf228052a23e6bc4810b5faef030314f` (`f425e943bf228052a23e6bc4810b5faef030314f`)
- Verdict: **BREAKING** - the squad references agents, skills, or prompts this ref no longer exposes

| `PowerPoint Builder` (agent) | removed from hve-core | 1 |
| `PowerPoint Subagent` (agent) | removed from hve-core | 1 |
| `powerpoint` (skill) | removed from hve-core | 3 |

Removed: PowerPoint Builder (.github/agents/experimental/pptx.agent.md); PowerPoint Subagent (.github/agents/experimental/subagents/pptx-subagent.agent.md); powerpoint (.github/skills/experimental/powerpoint/SKILL.md)
Invocability changed: hve-slides user-invocable-only -> model-invocable
Added: rpi (.github/skills/rpi/rpi/SKILL.md)

hasDelta       : True
isBreaking     : True
```

**Reading this verdict.** The upstream removals the plan relied on are confirmed. The only removals are PowerPoint Builder, PowerPoint Subagent, and the powerpoint skill. The `squadAtRisk` hits (1 + 1 + 3) are the squad's own "removed upstream" notes in pptx-brand-template, squad-autopilot, and sql-migration-advisor. The script cannot tell those notes apart from live references, so the BREAKING verdict is expected for this change and is not a defect in the repin. The Required-run verdict stays non-breaking only because it compares the pin to itself.

## Acceptance-criteria checklist

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | team.md cast from canonical templates, full RPI spine (researcher/lead/developer/tester/scribe) | **Met** | `members/issue-248/team.md` lines 11–15 list researcher→Squad Researcher, lead→Squad Lead, developer→Squad Implementor, tester→Squad Reviewer, scribe→Squad Scribe. Template conformance was not audited line by line. |
| 2 | Full RPI stage artifacts plus `history/autopilot-run-*.md` | **Not met** | research ✓ (`research/2026-11-10/cast-delta-research.md`); plans ✓; changes ✓; reviews: this file. **`members/issue-248/history/autopilot-run-*.md` does not exist**, though the federation entry in `.copilot-tracking/squad/history/issue-248.md` points to `history/autopilot-run-42922858257.md`. |
| 3 | history/ holds verified entries for Researcher, Lead, Implementor, Reviewer, Scribe | **Partially met** | Researcher ✓, Lead ✓, Implementor ✓, Scribe ✓ (each with a `### <timestamp>` entry and a `#### Consumption` JSON block). **Reviewer: missing.** It is written after this review, so it is pending, not a defect. Titles in the three role files are truncated mid-word (for example "…Subagent/skill r"). |
| 4 | Every roster Primary names an agent present in hve-core@f425e94; no dangling PowerPoint references | **Met with caveat** | Literal grep of squad-src finds no live "PowerPoint Builder" or "PowerPoint Subagent" references (only the three intentional removal notes). The substantive delta shows no roster agent was removed other than the PowerPoint pair. Roster Primaries are squad-owned `Squad *` charters, which are not hve-core agents. Direct upstream reads were blocked (GitHub MCP 403 on token lifetime), so presence at f425e94 is inferred from the delta, not read. **See gap G1 for the `presenter` role.** |
| 5 | No Primary or Alternate sets `disable-model-invocation: true` | **Met** | The five Primaries (`squad-researcher`, `-lead`, `-implementor`, `-reviewer`, `-scribe`) have `user-invocable: false` and no `disable-model-invocation`. The files that set `true` are `squad-coach`, `squad-coordinator`, `squad-federation-coordinator`, and `squad-learn`. None appears in the roster-catalog role table. Several other charters set `disable-model-invocation: false`, which is not true. |
| 6 | Any new thin charter runs a real hve-core skill and declares a Deliverable Root | **N/A** | No charter was authored (plan's scoped decision). |
| 7 | apm.yml pins f425e943…030314f and lists new charter files | **Met** | 198 hve-core entries at `#f425e943bf228052a23e6bc4810b5faef030314f`. The 6 `#9db369d…` entries are `github/awesome-copilot` skills, which this change does not touch. No new charter files, so none to list. |
| 8 | `.changes/unreleased/` fragment with `bump: minor` | **Met** | `.changes/unreleased/20261110-adapt-squad-cast-to-hve-core-f425e94.md` has `bump: minor` and `type: Changed`. It is the only fragment there. |
| 9 | apm.yml `version:` and CHANGELOG.md untouched | **Met** | `version: 0.20.0` on line 2, identical to HEAD. `CHANGELOG.md` is absent from `git status`. |
| 10 | Docs naming a changed agent/role updated, or PR states none do | **Not met** | Updated: `docs/usage.html`, `docs/fr/usage.html` (the PowerPoint paragraph), `docs/demo-3.html`, `docs/fr/demo-3.html`. **Still stale:** `docs/concepts.html:290,425`, `docs/fr/concepts.html:424` (presenter seed row, product profile), `docs/usage.html:1301` and `:1748` (product profile lists presenter; the presenter role section is still present), and `docs/fr/usage.html` (3 presenter hits). The change record does not list these as deferred. |
| 11 | Get-HveCoreCastDelta.ps1 reports non-breaking | **Met literally, vacuous in substance** | Required run (ToRef f425e94): `isBreaking: False`, verbatim above. The From/To refs are identical, so it proves nothing. The substantive delta (prior pin to f425e94) is BREAKING only because of the expected PowerPoint and powerpoint removals. |

## Findings

| Severity | Location | Issue |
|---|---|---|
| High | `squad-src/.github/skills/squad/references/profiles-and-packs.md:22` and `:31`; `squad-src/.github/instructions/squad/squad-roster.instructions.md:234` and `:243` | **G1 — dangling `presenter` role.** The `full` and `product` profiles still seed `presenter`. The role's catalog row and its only agent (PowerPoint Subagent) were removed. Seeding the profile produces a role with no dispatch target. The plan (decision, edit 4 and 6) and the change record ("Review should check both") called for removal from the seeds. |
| High | `squad-src/.github/instructions/squad/squad-roster.instructions.md:158` | Seed table still has the `presenter` row mapping to `.copilot-tracking/ppt/<date>/<deck-slug>/`. Part of G1. |
| Medium | `squad-src/.github/instructions/squad/squad-routing.instructions.md:65`; `squad-src/.github/skills/squad/references/model-routing.md:78` | Routing still maps "presentation, deck, slides" to `presenter` and lists it in the implementation class. Routing can send a deck request to a role with no agent. Plan edit 6 did not cover these files. |
| Medium | `squad-src/.github/instructions/squad/squad-roster.instructions.md:229` | Narrower deliverable-producing role list still names `presenter`. Consistency with G1. |
| Medium | `docs/concepts.html:290`, `:425`; `docs/fr/concepts.html:424`; `docs/usage.html:1301`, `:1748`; `docs/fr/usage.html` | Criterion 10 not met. Live docs still describe `presenter` as a seeded role. |
| Medium | `tests/squad-behavior-contract.md:610` (PRF-10); `tests/tier0/baselines/prefill-baseline.json:434` | The behaviour contract still lists `presenter` in the `product` profile, and the prefill baseline still has a "Brand Template for PowerPoint Builds" entry. Not checked by a run in this review. When G1 is fixed, the contract row and baseline may need a refresh, which should be confirmed by the full tier0 run. |
| Low | `members/issue-248/history/autopilot-run-*.md` (absent) | Criterion 2. Federation history links to a file that does not exist. |
| Low | `members/issue-248/history/Squad Researcher.md`, `Squad Lead.md`, `Squad Implementor.md` | Entry titles truncated at about 80 characters. The Scribe file uses "Consumption — Orchestration" headings, not "Orchestration/Dispatch" as the brief asked. Cosmetic. |
| Low | `scripts/Get-HveCoreCastDelta.ps1` (behaviour, not this change) | The "From" default reads apm.yml, so after a repin the script compares the new pin with itself and always reports no change. Consider making the review run pass an explicit `-FromRef` for the prior pin. |
| Info | `squad-src/.github/instructions/squad/pptx-brand-template.instructions.md:8` and others | The "removed upstream" notes are intentional. They are the only remaining literal PowerPoint names in squad-src, and the cast delta counts them as `squadAtRisk`. |
| Info | `apm.yml` | Removed: pptx agent, pptx-subagent, pptx instructions, powerpoint skill. Added: `hve-slides` at `skills/experimental/hve-slides` and the `rpi/*` skills. The `hve-slides` path changed from `skills/hve-slides` to `skills/experimental/hve-slides`. |

## Plan deviations

* **Planned, not done:** remove `presenter` from the catalog and seeds (plan edits 4 and 6). The catalog row and the seed-templates row are gone, but `roster.instructions` seed table, the `product` and `full` profiles, `routing`, `model-routing`, and the docs still name it (G1 and the Medium rows above).
* **Planned, not done:** docs sweep of `concepts.html` and FR counterparts (plan edit 12, ASM-1). Not recorded as deferred.
* **Done, not planned:** `pptx-brand-template` and `squad-autopilot` were reworded as "removed upstream" notes. These were in plan edit 7/8, so this is planned. Listed for completeness.
* **Done differently:** the `hve-slides` path in apm.yml moved to `experimental/`. This matches upstream.

## Conditions honored

Not applicable. The plan records that no council was convened.

## Tests run

| Command | Result |
|---|---|
| `pwsh -NoProfile` with `New-PesterContainer -Path tests/tier0/AgentDiscovery.Tests.ps1 -Data @{SourceRoot=<repo>}` and `tests/tier0/Manifest.Tests.ps1` (same data), via `Invoke-Pester -PassThru` | 88 passed, 0 failed, 0 skipped (exit 0) |
| Running either file without `-Data` | Error: mandatory `SourceRoot` missing, so no tests run. This was a harness error, not a test result. |
| Full `tests/tier0/Invoke-Tier0Tests.ps1` | **Not run.** Deferred to CI. The prefill baseline and PRF-10 may need a refresh after G1. |
| `npm run docs:check` / `docs:test` | **Not run.** Docs were edited (usage, demo-3); a docs check is recommended after G1 fixes. |

## Review record

Path: `.copilot-tracking/squad/members/issue-248/reviews/cast-adaptation-review.md` (this file). The history entry for Squad Reviewer is pending, and the Scribe writes it after this review.

## Required fixes before approval

1. Remove `presenter` from `full` and `product` in `profiles-and-packs.md` and in the matching `squad-roster.instructions.md` profile table (lines 234, 243). Remove the seed row (line 158) and the narrow role line (line 229).
2. Remove or redirect the presenter entries in `squad-routing.instructions.md:65` and `model-routing.md:78`. Route deck requests to the "no deck capability" note, not to a role.
3. Update `docs/concepts.html`, `docs/fr/concepts.html`, `docs/usage.html`, and `docs/fr/usage.html` (presenter lines), in EN and FR together. Or record them as deferred with a reason.
4. Write `history/autopilot-run-*.md` or correct the federation pointer.
5. Re-run `pwsh scripts/Get-HveCoreCastDelta.ps1 -FromRef 17072823c75d6e8cdf288d8ed4371f555dcd09bb -ToRef f425e943bf228052a23e6bc4810b5faef030314f` to record the substantive delta alongside the required run.
6. After fixes, run the full tier0 suite (or CI) to check the prefill baseline and PRF-10.

## Overall verdict

The pin, apm.yml version, CHANGELOG, fragment, the Primaries' flags, and the core squad-src references are all correct. The `presenter` role remains live in profiles, seed tables, and routing, which leaves a dispatch target with no agent. Docs naming it are also still live.
