---
description: "Deterministic Squad Doctor checks, allowlisted repairs, receipts, and coordinator recovery."
---

# Squad Doctor Runtime

Select **Squad Doctor** after every upgrade, in a fresh session in the affected
client. Request `check` first, then `repair` to confirm supported fixes. The
`/squad-doctor` prompt and plugin invocation dispatch this same agent. Doctor
works before Init and never creates a team merely because state is absent.

## Script Contract

Run the installed `scripts/Invoke-SquadDoctor.ps1` with `-RepoRoot <repo>`,
optional `-SquadRoot <root>`, and optional `-InventoryPath <transport.json>`.
The inventory is a JSON array of exact native IDs or display names from the
host's dispatchable-agent listing, not a filesystem inventory. No inventory
means `unverified`, not present or absent. `-Scope` narrows only domain checks;
its default `all` checks all seven domains. No network or AI call is made.

The script checks its required runtime files, domain representatives, existing
squad/federation structure, rate-table shape, and the existing read-only
dispatch brief with ledger checks. A federation checks only registered members;
an explicit member root stays scoped. Unsupported faults remain findings with
no automatic fix. Receipts include schema version, scope, findings, repairs,
and `status`: `healthy`, `repaired`, `attention`, or `error`.

Exit `0` means all implemented checks passed; `2` means unresolved or unverified
findings, including after a partial repair; `1` means execution/validation failed.
Keep stdout as one JSON receipt; do not treat exit `2` as success.

## Repair Allowlist

| ID | Trigger | Writer and scope |
|---|---|---|
| `rates` | Missing or invalid `consumption-rates.md` in an existing squad or federation | `Initialize-SquadConsumptionRates.ps1`, at each affected registered root |

Use `-Repair rates -Confirmed` only after user approval naming this scope.
Without `-Confirmed`, repair is rejected before writes. The shared per-root
handoff lock rejects concurrent writers. Each existing rate file is backed up
by content hash before the seeder runs; linked paths and repository escapes
are rejected. Seeder rules preserve valid custom model rows and compatible
calibration, refuse malformed custom rows, and disclose calibration resets.
Doctor does not force reseed a valid table or drop malformed operator data.
Repairs are idempotent and rechecked; a backup alone is not a successful repair.
Repairs across federation members are per-root, not one atomic transaction;
the receipt retains successful earlier repairs if a later member fails.

Missing agents/runtime require updating or reinstalling the one `hve-squad`
plugin in the affected client, or rerunning the pinned APM install for that
distribution. Do not install a second HVE Core plugin. Repository-hook refresh,
history backfill, roster changes, malformed state, model entitlement, and unknown
failures have no Doctor repair yet: report them blocked with their existing
recovery path. File presence cannot prove hooks executed or agents dispatched.

## Coordinator Recovery

On an explicit Doctor request, dispatch native **Squad Doctor** before Init,
classification, or roster/model preparation. On a runtime/availability failure,
stop affected work and all writers at that root, then invoke Doctor once with
the exact repository, root, original operation and error. Maintenance is outside
the roster planner so a broken roster cannot prevent diagnosis. Doctor gains no
work-role authority or gate waiver; account for actual maintenance usage in the
next valid handoff rather than inventing a completed worker.

Forward only trusted repair approval. Without it Doctor checks and asks; in an
unattended run it returns the repair request as a blocker. After a successful
repair, rerun the original failing operation once. Resume only if it passes
and all original gates/admission still hold. Otherwise escalate; do not loop
Doctor, retry an irreversible action, or replace a missing proof with its receipt.
