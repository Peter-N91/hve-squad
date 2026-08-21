---
bump: patch
type: Fixed
---

- **Promotion left a second tracking directory inside the first.** A live promotion moved every
  artifact correctly and then left `.copilot-tracking/.copilot-tracking/squad/members/<name>/` behind
  it — three empty directories, so no file was lost and no step reported a failure. The move is
  specified as copy → verify → delete-source per file and never said where destination paths are
  rooted, so the parent directories were created from inside `.copilot-tracking/` rather than from
  the project root. Promotion now states that every destination path is written from the project
  root, that it creates nothing outside `.copilot-tracking/squad/`, and that the tracking root is
  listed and cleared of anything the move created by accident before the promotion is confirmed.
  The state contract rejects a nested tracking directory outright
  (`squad-src/.github/instructions/squad/squad-federation.instructions.md`,
  `squad-src/.github/skills/squad/references/scribe-procedure.md`,
  `squad-src/.github/skills/squad/references/federation.md`,
  `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`).

- **The relocation mapping was recorded as its own placeholder.** The same promotion wrote one line
  reading `.copilot-tracking/<type>/ → .copilot-tracking/squad/members/product/<type>/` where four
  concrete lines belonged. That mapping is the only thing that makes a pre-promotion `Deliverable:`
  path resolvable, because the entry holding it is append-only and moved unedited — and a
  placeholder resolves exactly as much as the prose sentence the rule replaced. The step now says
  `<dir>` stands for a directory you name and that four moved directories produce four lines.
