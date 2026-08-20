---
bump: patch
type: Fixed
---

- **A role dispatched its Alternate instead of its Primary because the cue lived somewhere the host
  never read.** A research request grounded in a stakeholder brief resolved to `Meeting Analyst`
  rather than `Squad Researcher` — a plausible-looking alternate whose actual cue is
  meeting-transcript mining. The roster's `Alternate Agents` cell says an alternate *exists*; the
  condition that says when it *applies* lived only in the `applyTo`-scoped cast catalog, which does
  not load on every host, so the coordinator had the menu without the rule. The swap is silent and it
  is not cosmetic: the two agents run different methodologies. `team.md` now carries a `Selection
  Cue` column seeded from the catalog, the way `Deliverable Root` already is, and the resolution rule
  moved to the floor with an explicit fallback — no cue read means the Primary
  (`squad-src/.github/instructions/squad/squad-floor.instructions.md`,
  `squad-src/.github/instructions/squad/squad-roster.instructions.md`,
  `squad-src/.github/skills/squad/references/seed-templates.md`,
  `squad-src/.github/skills/squad/references/scribe-procedure.md`,
  `squad-src/.github/agents/squad/squad-coordinator.agent.md`).
- **A ten-turn run left its ledger frozen at turn one.** `consumption.md` was still headed
  `Run: turn-001` with two priced rows and a $0.0298 total while `history/` held nine dispatch
  records and `state.json` reported turn 10. The stale run id is the cheapest available proof that no
  rewrite happened since, so the ledger step now compares it against the current turn before
  finishing and treats a stale id as a failed write rather than a heading to patch
  (`squad-src/.github/skills/squad/references/scribe-procedure.md`).
- **The ledger seeded all thirteen roster roles as zero rows.** Eleven permanent zeros around one
  real row make a ledger that never advanced look populated, which is the opposite of what the file
  is for. A role with no consumption block now has no row at all
  (`squad-src/.github/skills/squad/references/scribe-procedure.md`).
- **`#### Consumption — Orchestration (Turn 1)` is unreadable, and nothing said so.** The suffix rule
  named role-flavoured variants but not a turn marker, so the one orchestration block in the run was
  spent and uncounted. Both legal headings now take no suffix of any kind, and the turn belongs in
  the entry heading above the block (`squad-src/.github/skills/squad/references/scribe-procedure.md`,
  `squad-src/.github/skills/squad/references/entry-schemas.md`).
- **`state.json` collected invented keys and lost the documented ones.** A run wrote `squadMembers`,
  `status`, `completedDispatches`, and a `timestamp` beside `updated`, dropped `schemaVersion` and
  `notify` entirely, and replaced all four `currentRun` keys with a scratchpad holding
  `"estimatedTokens": "moderate"`. With `estCostUsd` absent there is no machine-readable cost figure
  for a cost ceiling to read. The key set is now stated as closed at both levels
  (`squad-src/.github/skills/squad/references/entry-schemas.md`).
- **A stage recorded as complete had no history file, and autopilot advanced anyway.**
  `completedDispatches` claimed `Squad Implementor` finished on turn 4 with nothing in `history/`.
  The history file is the evidence and a status field is a claim about it, so a missing file now
  stops the stage in every mode (`squad-src/.github/instructions/squad/squad-floor.instructions.md`).
- **An autopilot run reached four open sign-off gates with no approval channel captured.** `notify`
  was absent from `state.json` and `notifications.md` was empty, leaving the gates with no way to
  reach anyone. Init now writes the `notify` object whatever the answer was — a decline is
  `in-chat`/`enabled: false`, which is a recorded answer rather than an absent key — and writes the
  Init decision that records the roster's provenance
  (`squad-src/.github/skills/squad/references/scribe-procedure.md`).
- **A mutation control was silently testing nothing.** `Edit-Fixture -Replacement 'a' + "b" + 'c'`
  binds only `'a'`: a plain PowerShell function collects surplus positional arguments into `$args`
  rather than failing, so the reordering control had been deleting a field instead of moving one.
  The concatenations are parenthesised and `Edit-Fixture` now refuses unbound arguments
  (`tests/tier1/Assertions.Tests.ps1`).
- **Four new contract cases with mutation controls**: the roster must carry `Selection Cue`, the
  ledger must carry no row for an undispatched role, and `state.json` must declare no key outside the
  documented set at either level (`tests/tier1/StateContract.Tests.ps1`,
  `tests/tier1/Assertions.Tests.ps1`, `tests/tier1/SquadFixture.psm1`,
  `tests/squad-behavior-contract.md`).
