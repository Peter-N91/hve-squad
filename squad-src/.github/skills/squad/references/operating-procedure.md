---
name: squad-operating-procedure
description: "The four stages of a squad turn — Init, Route, Decide, Handoff — plus ledger reconciliation and the tool-to-mechanism mapping."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-08-14"
---

# Squad Operating Procedure — Turn Stages

## Init

Run once per project, then verify on every turn. Init Mode mirrors a propose → confirm → create flow and never writes files before the user confirms.

1. Check for `.copilot-tracking/squad/team.md` and `.copilot-tracking/squad/routing.md`.
2. When either file is missing (and no `.copilot-tracking/squad/federation.md` exists), first **offer single squad or federation** (Phase 0): a single squad (default) for one team across the repo, or a federation of named sub-squads when different teams or domains each want their own squad. When the user chooses a federation, hand off to `/squad-federation` (the Squad Federation Coordinator) instead of seeding a single squad; otherwise continue. Then **propose**: discover the project (languages, frameworks, tests, IaC, security/AI markers) read-only, then recommend a profile using the precedence in the roster's *Profile Selection* (explicit `profile=` hint → discovery inference → `default`), plus any packs an explicit `pack=` hint or the repository's domain signals call for. Present the profile under consideration — the user's `profile=` choice when given, otherwise the most appropriate profile the coordinator selected — together with any proposed packs, with its roles and why it fits, and ask the user to proceed or choose differently. On **proceed** the flow is unchanged; on **decline** the user either picks a different profile from the listed set or builds a custom roster from the role menu (each role shown with a plain-language description), per the roster's *Building a Custom Roster*. Once a profile or customized roster is on the table, also offer naming choices for the seeded members per the roster's *Naming Conventions* (user-supplied per role, coordinator-assigned aliases from the deterministic wordlist, a mix, or skip). Wait on the user before any write.
3. On **confirm**, hand the chosen roster to the Squad Scribe to **create**: `team.md` from the confirmed profile's members plus the roles of every applied pack, deduplicated (including the `Member Name` column when names were provided), `routing.md` from the default routing rules filtered to that roster, plus `decisions.md`, `notifications.md`, `state.json`, `consumption.md`, `consumption-rates.md`, and an **empty** `history/` directory. Both consumption files are seeded here rather than left for the first cost write — the rate table is the only source of token rates, so a squad that starts without it cannot price its first dispatch. `history/` is the opposite case: it stays empty, because each file inside it is created by the dispatch it records and its presence is the proof that dispatch happened. The Init decision records the roster's provenance — the profile plus any applied packs, or `custom`. Before the create step, **always ask** for an approval channel per `.github/instructions/squad/squad-notifications.instructions.md` (`github-issue` for remote/unattended approval, `webhook`, or `in-chat`) and seed the answer into the `state.json` `notify` object. The answer is optional — declining keeps `in-chat` — but the question is never skipped or silently defaulted. In a federation the question is asked once at the federation level and inherited by every sub-squad.
4. Confirm the roster and routing table are present before classifying the request. The coordinator never writes these files itself.

## Route

1. Read `team.md` and `routing.md`.
2. Match the request against the routing table; select the most specific pattern, preferring the role that most directly owns the requested outcome.
3. Resolve each matched role to a deployed agent through the roster. A role marked **thin charter needed** has no deployed agent — escalate instead of substituting.
4. Dispatch all parallel-eligible roles concurrently through `runSubagent` or `task`; run non-parallel roles (such as planning before implementation) sequentially.
5. Apply cost-first model selection: prefer the `fast` tier for read-heavy `auto` roles and reserve the `default` tier for reasoning-heavy `confirm` roles. A user tier hint overrides the per-role default for the turn.

### Ledger Reconciliation (before new work)

Check three conditions against `consumption.md`, and treat any one as proof that a prior turn dropped consumption attribution:

* **Seed** — `history/` holds dispatch entries but the ledger has no per-role rows, or its seed note still claims no dispatches have run.
* **Truncation** — an agent holds a `history/<agent>.md` entry for this run but no ledger row, or the ledger's run id names a run other than the current one.
* **Divergence** — the ledger total disagrees with `state.json` `currentRun.estCostUsd` in either direction, including `currentRun` still reading `0` while history shows dispatches.

Count the rows against the history before assuming the ledger is healthy. A populated ledger carrying a plausible non-zero total is exactly what a truncated one looks like, so an existence check clears the very failure worth catching — the run whose first two turns are recorded and whose remaining eight are not. On any hit, hand the existing `history/<agent>.md` entries to the Scribe to backfill the per-dispatch blocks and rewrite `consumption.md` from the full set, resolving each dispatch's model through the ladder and recording `unknown` where a backfilled entry cannot establish what ran. This self-heals a disrupted run on the next turn; it is a Scribe-only write and touches no implementation file.

## Decide

1. Collect each dispatched agent's structured findings and reconcile conflicts.
2. Hand the turn's decision and rationale to the Squad Scribe, which appends to `decisions.md` (append-only).
3. When a decision is architecturally significant, additionally capture it as an Architecture Decision Record via the `adr-author` skill and reference that ADR from the decision entry.
4. Persist durable, role-scoped learnings to `/memories/repo/squad-<agent>.md` through the Squad Scribe and the memory tool.
5. Consult the shipped `learnings/shared-learnings.md` playbook (skill-root-relative within the deployed `squad` skill) as read-only, authoritative context and apply any curated entry whose scenario matches the work at hand. This shipped file complements the consumer-local memory written in the prior step: the coordinator reads the shared playbook and writes local learnings, and it never writes back to the shipped file. When the organization has configured the tenant-internal APM dependency, the consumer also carries a tenant playbook at `.agents/skills/squad-learnings-tenant/tenant-learnings.md`; consult it after the shipped playbook as additional read-only, authoritative context and apply any entry whose scenario matches. That tenant file is present only when the organization configured the dependency, and the coordinator never writes to it. The full read order is local memory first, then the shipped playbook, then the optional tenant playbook. A local learning reaches the shared playbook only through the fork-and-PR promotion path in `CONTRIBUTING.md`.

## Handoff

1. Hand each dispatched agent's request and outcome to the Squad Scribe, which appends them to `history/<agent>.md` (append-only) along with the per-dispatch consumption block (the resolved model and how it was resolved, plus estimated input, cached, cache-write, and output token cost and credits), then rewrites the `consumption.md` ledger and updates the `state.json` `currentRun` totals. The consumption block is written for every dispatch, never conditionally: the coordinator resolves the model through the ladder in *Model Attribution* and passes it with the roster tier, and when it omits the payload the Scribe resolves the model itself — recording `unknown` and a `tier-default` price rather than inventing a model name — so a history append never lands without its consumption block and the ledger never stays at its seed while dispatches have run. Every consumption figure is an estimate.
2. Synthesize the collected findings into a concise answer for the user.
3. Escalate to the user — rather than acting — when the matched rule is at the `escalate` tier, no pattern matches with reasonable confidence, a role resolves to **thin charter needed**, or two rules conflict with no clearly more specific match. State the ambiguity, list the candidate roles, and ask the user to choose.

## Tool-to-Mechanism Mapping

| Squad verb       | HVE Core mechanism                                                                                       |
|------------------|----------------------------------------------------------------------------------------------------------|
| `squad_route`    | Dispatch the assigned role via `runSubagent` / `task` against a `user-invocable: false` agent             |
| `squad_decide`   | Append the decision and rationale to `decisions.md`; optionally record an ADR via the `adr-author` skill  |
| `squad_memory`   | Write durable per-agent notes with the memory tool to `/memories/repo/squad-<agent>.md`                   |
| `squad_notify`   | Fire a notification per `squad-notifications.instructions.md`; deliver via a configured tool when present, else in-chat, and append the record to `notifications.md` |
| `squad_escalate` | Apply the escalate-to-user convention from the routing rules before any role acts                         |

`squad_memory` spans up to three surfaces. It reads the shipped `learnings/shared-learnings.md` playbook (skill-root-relative within the deployed `squad` skill) as read-only, authoritative shared context, and when the organization configured the tenant-internal APM dependency it also reads the tenant playbook at `.agents/skills/squad-learnings-tenant/tenant-learnings.md` as read-only context, in addition to writing durable per-agent notes to the consumer-local `/memories/repo/squad-<agent>.md`. Neither shared playbook is ever written from a run: promotion of a local learning into a shared surface flows only through the human-reviewed promotion paths in `CONTRIBUTING.md`.
