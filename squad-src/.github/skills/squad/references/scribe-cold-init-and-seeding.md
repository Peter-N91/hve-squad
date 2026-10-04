---
name: squad-scribe-cold-init-and-seeding
description: "Scribe cold section: Initialization, Deliverable Root resolution, and repository-memory/learning-promotion writes. Read only for an initialization payload, a memory payload, or the roster-rebasing step of a promotion/expansion."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-09-27"
---

# Scribe Cold Section: Init, Seeding, and Repository Memory

Read this file only when the turn's payload is one of: an **initialization** payload (Payload-to-Step Map Step 3), a **memory** payload (Step 4), or the deliverable-root rebasing sub-step of a **promotion** or **expansion** payload (Steps 10–11, which cross-reference *Initialization and Deliverable Roots* below for the rebasing rule). Every other turn skips this file entirely — see the Cold-File Dispatch Table in [scribe-procedure.md](scribe-procedure.md).

### Initialization and Deliverable Roots

Create `team.md` from the coordinator-confirmed roster — the chosen profile's members, not the full cast catalog — and `routing.md` from the default routing rules filtered to that roster, dropping any routing row whose role is not on the seeded team. Always include the `scribe` role. Include the `Member Name` column whenever the coordinator supplies names, leaving cells empty for unnamed roles; two rows sharing a `Role` are legal only when each has a unique `Member Name`. Seed the `Selection Cue` cell for every row, using `—` where the role has no alternates: the cast catalog is canonical in `references/roster-catalog.md`, a reference file that loads only when a role's Skill Reference Contract calls for it, so a roster listing alternates without their condition leaves the coordinator to guess which one applies. Both files use replace semantics — write them only when missing or on an explicit refresh.

**Seed the whole state tree, including both consumption files.** Init creates `team.md`, `routing.md`, `decisions.md`, `notifications.md`, `state.json`, `history/`, **`consumption.md`**, and **`consumption-rates.md`** — the ledger from its own template in [consumption.md](consumption.md) at its seed state, and the rate table from the cold [consumption-rates-template.md](consumption-rates-template.md) at current rates. They are squad state like every other file here, not artifacts that appear once someone happens to write a cost. Leaving them to be created lazily by the first consumption write is how a run reaches turn nine with a populated `history/` and no ledger at all: the rate table is the only source of token rates, so a Scribe that finds it missing cannot price a dispatch, and the block it cannot write takes the history append down with it.

**Seed `history/` as an empty directory.** Init creates no file inside it — not even a header-only one, and not for roster members it expects to dispatch later. A history file is the proof that agent ran, so pre-creating one per roster row makes an undispatched role indistinguishable from a dispatched one and leaves the ledger rewrite reading files that record nothing. Each file is created with its header at the moment its first entry is appended.

**Write the `notify` object and the Init decision, both of them.** `state.json` carries `notify` from the answer the coordinator captured; when the user declined, that is `approvalChannel: in-chat` with `enabled: false`, which is a recorded answer rather than an absent key. A run in `autonomous` or `autopilot` mode with no `notify` object has no way to reach the person its gates are waiting on. The Init decision entry records the roster's provenance — the profile plus any applied packs, or `custom` — because without it nothing in the state explains why this roster exists, and a later turn re-deriving it is guessing.

When Init proposed a task-fit council, record the user's accepted, adjusted, or declined answer as a `Council Role Offer` decision in `decisions.md`, including the exact roster role set, lifecycle trigger id, proposed roles and rationale, `Not Proposed` roles and rationale, and exact selected membership. On acceptance, seed only selected roles absent from the initial roster and their routing rows into `team.md` and `routing.md`; on decline, record `Council Waiver: waived by user` and add none. Include `rai` only when its review lens is relevant. In a federation, make and record the proposal separately for each sub-squad using that sub-squad's ask, roster, and answer.

**Resolve each row's `Deliverable Root` against the `squadRoot` in hand before writing it.** The lookup table in *Deliverable Roots* (`squad-roster.instructions.md`) states roots relative to `squadRoot`, so seeding a sub-squad writes `members/<name>/plans/` into the `lead` row, not `.copilot-tracking/plans/`. Copying the table's literal paths into a sub-squad roster points every role at the repository root and puts its whole run outside its own sub-squad. `docs/` and `outputs/` are the two exceptions and are written unprefixed at every root.

**On a refresh, preserve every `Deliverable Root` cell already present.** The column is consumer-editable and the roster is the running value the coordinator dispatches against, so a refresh reseeds a root only for a role whose row it is adding. Rewriting an existing cell back to the default silently redirects a role the user deliberately pointed elsewhere.

**Write the model-routing mode and `Model` column exactly as handed over.** When the payload carries a routing mode (`ranked` or `manual`), write the single line `Model routing: <mode>` directly beneath `team.md`'s H1, and a `Model` column between `Model Tier` and `Deliverable Root` holding each role's Model ID as supplied — one lowercase id per cell, never a display name, and empty for a role the payload leaves unset. On a routing refresh, change only that line and the `Model` cells the payload names, preserving every other cell and row. When the mode is `off`, remove both the line and the column, and list the removed picks in the same turn's decision entry so a later switch back to `manual` can offer them. Record every mode change and every `manual` pick in a decision entry; a ranked readout refresh needs only the `state.json` advance. See `model-routing.md` for what each mode means; the Scribe never ranks or picks a model itself.

### Repository Memory and Learning Promotion

Write role-scoped notes to `/memories/repo/squad-<agent>.md` with the memory tool. Repository memory survives across conversations, so durable squad facts — conventions a role discovered, recurring routing choices — belong here rather than in the decision log.

When a learning is broadly applicable beyond this consumer, the Scribe may surface a sanitized promotion candidate and point the user to the promotion paths in `CONTRIBUTING.md` or to `/squad-learn`. The candidate may target the upstream package or the organization's tenant-internal repository, based on how far the learning should travel. This is a suggestion only: the Scribe writes nothing outside consumer-local `/memories/repo/` memory and never edits a shipped or tenant playbook.
