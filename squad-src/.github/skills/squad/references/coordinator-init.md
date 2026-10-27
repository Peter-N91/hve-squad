---
description: "Confirmed script-backed squad/member initialization without model roster transcription."
---

# Coordinator Initialization

Success means a confirmed roster and a fresh tree whose initializer receipt has
`status`, `rosterCheck`, `ledgerCheck` all `PASS`, `verified: true`.
No state is written before confirmation. Initialization is outside Cost Preflight;
evaluate the original request before its first work dispatch afterward.

## Propose and Capture

Offer unsure users Squad Coach once before Init; if accepted, pause for manual
selection rather than dispatching it or writing state.

Run `Get-SquadInitContext.ps1 -RepoRoot <repo>` for the installed root, profiles,
packs, naming choices and project metadata; add `-Profile <id>` for resolved
Primaries and availability. Use repository/request signals to recommend a
profile; explicit `profile=` wins, then discovery, then `default`. Offer packs
when their domain fits, never impose one. A pack adds to a profile and is not a
federation. A missing external agent is offered with its install path, not seeded.

With neither top-level `team.md` nor `federation.md`, ask single squad versus
federation first; single is the recommended start. Federation seeds nothing here:
hand off to `/squad-federation`. An existing single squad moving to federation
uses promotion, never fresh Init.

Ask and wait for all required choices: profile/packs or custom roster, member
naming, and approval channel. Use a host's combined native form only if it
actually supports the distinct required answers; otherwise ask sequentially.
Never silently default an unasked question. Inherited federation naming/notify
skip their capture steps. Declining naming means `skip`; declining notifications
means disabled `in-chat`. Record the session model silently, including literal
`auto`; never search the host log or ask the user to identify it.

Show every proposed role with its resolved Primary, packs grouped by name.
On decline offer a different profile or a custom role menu, including when the
profile is close but not exact. Keep the methodology spine and `scribe`.
Offer needed council lenses in the same roster confirmation. A custom roster
or explicit exclusions reflect the user's choice, never missing-agent guesses.

## Prepare Compact Choices

Write a small confirmed choices JSON with an advertised editor, outside squad
state. Required fields:

```json
{
  "confirmed": true,
  "squadRoot": ".copilot-tracking/squad",
  "runId": "<actual run id>",
  "profile": "default",
  "naming": "skip",
  "notify": { "approvalChannel": "in-chat", "enabled": false },
  "sessionModel": "auto"
}
```

Use only actual confirmed values. Optional fields: `packs` array; `roles` for
`profile: custom`; `excludeRoles` for explicitly dropped non-spine roles;
`names` role-to-name map; `modelRouting`, confirmed `models` map; `mode`,
`modelOverrides`, and actual coordinator `usage`. Naming is `skip`, `aliases`,
`custom` or `mixed`; custom supplies all names, mixed supplies selected ones.
The helper assigns aliases in canonical order, skipping supplied names and
cycling `-2`, `-3`; never retype the wordlist.

Run:

```powershell
pwsh -NoProfile -File "<skill>/scripts/Get-SquadInitContext.ps1" -RepoRoot "<repo>" -ChoicesPath "<choices.json>" -PayloadPath "<new-payload.json>"
pwsh -NoProfile -File "<skill>/scripts/Initialize-Squad.ps1" -RepoRoot "<repo>" -PayloadPath "<new-payload.json>" -Direct
```

The first command resolves canonical profile/pack/cast/root/tier/name data into
the existing full payload; it writes transport only, not squad state. The second
is the existing staged initializer: template/rate copy, root rebasing, history
and state creation, ledger derivation/check and publication. Direct execution
records coordinator overhead only in `history/Squad Scribe.md`, never a fictional
Scribe actor. Missing usage is a disclosed estimate, not billed telemetry.

Trust a valid current helper receipt: confirm roles/packs, naming/notification
choices and paths, then classify the original request. Do not reread rates,
recompute Cost Comparison, repeat the ledger check or dispatch an Init auditor.
No baseline/savings can be invented at setup.

## Compatibility and Failure

Existing full `roster` payloads remain accepted; a real dispatched Scribe can
still use `scribe-init.md` without `-Direct`, recording its own usage separately.
Neither path is a license to fabricate usage or edit an existing tree.

Confirmed additions of catalog roles or packs use `roster-expansion.md` for an
existing plain squad or selected federation member. Connector setup/additive
bindings, repeated-role custom members, removal, recasting, existing-root edits,
and unavailable runtime keep their cold procedure. Supported Federation Expansion
uses the same sealed Init transaction as a fresh federation; supported promotion
uses the federation runtime's sealed-plan transaction.
Read `connector-role-modes.md` when applicable, then the relevant roster/cast
sections and pass confirmed `connectorBindings`/`customRoutingRows` through cold
Scribe. Preserve existing bindings, model choices and edited output roots on
refresh. Never drop unsupported fields to force the fast path.

Wrong input fails before publication. Correct the named confirmed input and retry
once, not a recursive Scribe loop. An existing/partial root, ambiguous publication,
history-integrity, or failed restore stops and requires explicit repair; never
overwrite it. A successful ledger receipt settles Init accounting. A synchronous
Scribe return is not a background handle: only use observed native continuation.
