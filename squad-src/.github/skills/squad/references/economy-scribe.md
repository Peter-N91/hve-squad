---
name: squad-economy-scribe
description: "Scribe-only: the scripted hand-off a payload carrying handoff: script asks for under routing=economy. Read instead of the hot core; the hot core only on fallback."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-08"
---

# Economy Scribe Hand-off

Read this file, and nothing else first, when the payload carries `"handoff": "script"`. It exists only under `Model routing: economy`.

## Run

As your first action, write the payload JSON to a file outside the squad root and run:

`pwsh -NoProfile -File <skill>/scripts/Write-SquadHandoff.ps1 -SquadRoot <squadRoot> -PayloadPath <payload.json>`

Run it once per payload; never read or debug it. Quote its last line in your confirmation: `Measure-SquadLedger -Check: PASS`, or the `WARN ledger-only:` line (the writes stand; v0.18.1 never blocks on cost accounting). Quote any other `WARN` lines too (`economy consent not recorded`, a `Route:` marker added, no `routingIdentity`).

## Exit Codes

| Exit | Meaning | You do |
|---|---|---|
| 0 | Written; ledger check PASS or ledger-only warning | Confirm, quoting the last line |
| 1 | Invalid payload, replay, or a deliverable already credited | Correct the one field named and rerun once; a second 1 is a fallback |
| 1 | `owner deliverable ... changed after the closing review` | Not a payload fault: return it, write nothing; the coordinator re-dispatches the review |
| 2 | Outside the script's scope (ceiling, federation, legacy schema, agent not on the roster, secret-like text, unseeded ledger) | Fallback |
| 3 | Write failed or history-integrity check failed, files restored | Fallback |
| 3 | `RESTORE FAILED`, or a file left as another writer changed it | Stop and tell the user |
| 4 | Malformed operator rate row | Ask the user |
| 7 | `team.md` is not economy | Fallback |
| 8 | Another hand-off holds this root | Rerun once it finishes |

## Fallback

On 2, 3 with files restored, 7, or a second 1: read the normal hot core (`00-index.md`, `scribe-procedure.md`, `entry-schemas.md`, `scribe-payload-template.md`) and compose the hand-off by hand, quoting the refusal. A stub ledger the script reseeds itself; do not repair it separately.

## Fields You May Correct on Exit 1

Every object is a closed key set. Required: `runId`, `historyRecords[]` (`agent`, `request`, `deliverable`, `outcome`), `stateAdvance.activeRoles`. `agent` is the roster's Agent Name verbatim; `deliverable` is one existing file path plus an optional `(size)`, written this turn. `turn`, `timestamp`, `mode`, and omitted `consumption` blocks are derived: drop a stale `turn` or `timestamp` rather than guess one.
