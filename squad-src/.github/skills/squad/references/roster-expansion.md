---
name: squad-roster-expansion
description: "Confirmed hash-bound addition of catalog roles and packs to a plain squad or one federation member."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-25"
---

# Deterministic Roster Expansion

Use this path when the user confirms adding one or more shipped catalog roles or
registered packs to an existing squad. The same transaction targets either the
plain root `.copilot-tracking/squad/` or one registered federation member root
`.copilot-tracking/squad/members/<name>/`.

This operation only makes a roster larger. Removal, recasting an existing row,
adding a second member for an existing role, connector binding changes, custom
routing edits, an existing Deliverable Root change, and `routing=off` retain the
cold refresh procedure. A missing external Primary is offered with its install
command and is never seeded.

## Prepare and Confirm

After the user accepts the proposed pack or roles, write a small choices JSON
outside squad state:

```json
{
  "confirmed": true,
  "runId": "<actual run id>",
  "packs": ["aws"],
  "roles": ["backlog-executor"],
  "names": {
    "backlog-executor": "Tracker"
  },
  "models": {},
  "rationale": "Add the confirmed delivery capabilities."
}
```

At least one of `packs` or `roles` is required. `names`, `models`, and `rationale`
are optional. A supplied name must be unique in the selected roster. `models`
is accepted only when the current roster already has active
`ranked`, `economy`, or `manual` routing; otherwise new Model cells stay empty
and lazy routing resolves them when those roles are first selected.

Run:

```powershell
pwsh -NoProfile -File "<skill>/scripts/Get-SquadRosterExpansionPlan.ps1" `
  -RepoRoot "<repo>" -SquadRoot "<root>" `
  -ChoicesPath "<choices.json>" -PayloadPath "<new-plan.json>"
```

The planner writes transport only. It resolves roles, Primaries, tiers, roots,
and canonical routing rows from shipped tables; checks installed dispatchability;
preserves every existing roster row and route; and seals the current roster,
routing, decisions, state, accounting, rates, notifications, and history. For a
member it also verifies the exact federation registry row. Present the returned
packs, added roles, already-present roles, and routing-row count, then wait for
confirmation.

## Apply the Exact Plan

Run:

```powershell
pwsh -NoProfile -File "<skill>/scripts/Expand-SquadRoster.ps1" `
  -RepoRoot "<repo>" -PlanPath "<plan.json>" `
  -ExpectedPlanSha256 "<planSha256>" -Confirmed
```

The writer takes the plain root lock, or the federation root then selected member
lock, and revalidates the sealed baseline.
It writes only:

* new rows appended to the existing `team.md` Members table;
* newly eligible canonical rows appended to the existing `routing.md` table;
* one append-only `Roster Expansion` decision.

Existing rows, custom routes, connector sections, names, model cells, and edited
Deliverable Roots remain byte-identical. New roots use the same resolver as Init,
including member rebasing and repository-wide `docs/` / `outputs/` exceptions.

The transaction launches no model and no Scribe. It appends no dispatch history,
does not advance the state turn, and never runs the ledger writer. It requires
`consumption.md`, `state.json`, `consumption-rates.md`, `notifications.md`, and
`history/` to remain byte-identical, then runs `Measure-SquadLedger.ps1 -Check`
read-only. This is what prevents an exact ledger from being replaced by the old
estimated/observed refresh output.

A nonzero exit is final for that plan: stale state, changed history, registry
drift, invalid data, a lock timeout, a failed read-back, or a ledger failure never
authorizes a Scribe retry or hand edit. Correct the named input, prepare a new
plan, and reconfirm when needed.

## Federation Boundary

Expanding one registered member is the ordinary single-squad operation scoped to
that member root. The federation registry, meta-routing, root decisions, root
history, aggregate state, and other members are not changed. Adding an entirely
new sub-squad remains Federation Expansion through
`Get-SquadFederationInitPlan.ps1` and `Initialize-SquadFederation.ps1`.

Hosts without PowerShell 7.4 or the delivered scripts retain the cold compatibility
path. That fallback is not a retry for a rejected or stale deterministic plan.
