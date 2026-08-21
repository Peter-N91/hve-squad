---
bump: patch
type: Fixed
---

- **A stage could report itself complete having written nothing.** A live run recorded
  `Deliverable: N/A — inline verdict, no review artifact file written` twice, and the review stage
  passed every check: an entry that names no path leaves the existence check with nothing to reject,
  so proof of dispatch was satisfied by a claim rather than by a file. The floor now states that
  `N/A`, `inline verdict`, `no artifact written`, and a missing `Deliverable:` line are the same
  statement — the stage produced nothing the next one can read — and that a role whose output is a
  judgment writes that judgment to a file at its Deliverable Root. A verdict that exists only in a
  chat turn is gone when the turn ends, and the gate depending on it has nothing to open. `SQ-12`
  gains a per-entry assertion to match
  (`squad-src/.github/instructions/squad/squad-floor.instructions.md`).

- **The Tier 1 deliverable reader truncated any path containing a space.** It split each backticked
  token on whitespace to strip trailing prose, but the prose sits outside the backticks and an
  agent's name carries spaces — so `history/Squad Researcher.md` became `history/Squad` and every
  entry naming one failed the existence check it had just passed in review. Brace-expansion
  summaries such as `members/default/{team.md,routing.md}` were read as one path for the same
  reason. The reader no longer splits on whitespace and skips set notation alongside globs.

- **Two file classes were read as dispatch records when they are not.** The Scribe's own entries
  name the state files a turn wrote and cite them across federation roots, and a federation root's
  `history/` names sub-squads rather than agents — recording a `Reference:` to where that turn's
  dispatch records actually live. Neither is a dispatched stage, so proof of dispatch no longer
  applies to either. The live harness also captures the tracking tree under its own dot-prefixed
  name, so an uploaded result replays against the same path resolver the run used (`tests/tier1/`).
