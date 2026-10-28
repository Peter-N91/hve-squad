---
name: squad-federation-init
description: "Deterministic federation planning, fresh initialization, and additive member expansion."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-25"
---

# Deterministic Federation Init

Read this file when the user confirms either a fresh federation or new members
for an existing federation. The same Init command and scripts own both cases.

## Prepare

The coordinator decides the proposed members semantically, presents every name,
profile, pack, resolved Primary, owner, description and meta-route, captures
naming and notifications once, then waits for confirmation. No script decides
those choices or grants approval.

Write confirmed choices to a new transport JSON outside squad state and run:

```powershell
pwsh -NoProfile -File <skill>/scripts/Get-SquadFederationInitPlan.ps1 `
  -RepoRoot <repo> -ChoicesPath <choices.json> -PayloadPath <new-payload.json>
```

Required choice fields are `confirmed: true`, `runId`, `naming`, `notify`, and
`subSquads`. Each sub-squad supplies:

* `name`: unique lower-kebab-case.
* `profile`, plus optional standard Init fields such as `packs`, `roles`,
  `excludeRoles`, names, routing and model choices.
* `owner`, optional and single-line.
* `description`, single-line.
* `routes`: one or more `{pattern, parallelEligible}` objects.

The preparer calls the same `New-SquadInitPayload` used by single-squad Init for
every new member. It therefore validates profiles, packs, roster rows, installed
Primaries, shared or overridden naming, notifications, routing and rebased member
roots before any state write.

The root determines the operation:

* No `federation.md`: `operation=fresh`; seal the absent or empty scaffold.
* Existing `federation.md`: `operation=expand`; validate the registry, routes,
  state, member directories and history, reject existing names/routes/history,
  and seal root-file hashes plus every registered member state and total.
* Top-level `team.md` without a federation: refuse and use Promotion.

## Publish

After checking the prepared summary, invoke:

```powershell
pwsh -NoProfile -File <skill>/scripts/Initialize-SquadFederation.ps1 `
  -RepoRoot <repo> -PayloadPath <payload.json> `
  -ExpectedPayloadSha256 <sha256> -Confirmed
```

The initializer:

1. Revalidates the exact payload hash, confirmation and sealed root baseline.
2. Starts every new member's existing `Initialize-Squad.ps1 -Direct` transaction
   in parallel inside an isolated repository-shaped stage. Agent validation reads
   the real consumer repository.
3. Requires every new member receipt to report `verified=true` and
   `ledgerCheck=PASS`; one failure discards the whole stage.
4. Builds and validates the final root projection, including registry/routes,
   append-only decisions/history, root orchestration and aggregate state. Existing
   member trees are never copied, rewritten or repriced.
5. Takes the ordinary root writer lock and rechecks the sealed baseline.
6. Fresh Init publishes the complete tree with one directory move. Expansion
   moves only the verified new member roots, atomically replaces the planned root
   files, verifies the final snapshot, and rolls owned writes back on failure.

Success is one JSON receipt with `operation`, newly created member names, total
member count, root turn/totals, elapsed milliseconds,
`parallelMemberInitialization=true`, member start skew, warnings and cleanup
status. Nonzero exit means failure; never dispatch Scribe or hand-author a
fallback after validation, lock, publish or restore failure.

## Ownership and Compatibility

The direct transaction records coordinator setup usage only; it never invents a
Scribe dispatch. Each member keeps the standard single-squad state format under
`members/<name>/`. Expansion preserves every existing member byte, appends root
rows/history, advances aggregate state and invalidates any prior aggregate cost
approval. Hosts without the scripts retain the cold compatibility procedure.
