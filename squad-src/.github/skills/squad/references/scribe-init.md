---
name: squad-scribe-init
description: "Fresh single-squad or member-root Init: confirmed JSON, one deterministic helper, validated status."
---

# Fresh Squad Initialization

Success is one published state tree and a helper JSON status with `status`,
`rosterCheck`, and `ledgerCheck` all `PASS`. Initialization is outside admission.
Serialize it with other writers. Read only this brief for fresh Init when a shell
and `pwsh` 7.4+ are available. The helper reads templates; you do not read the
charter, procedure, schemas, cast catalog, seed templates, or rate template.

## Confirmed input

Write a JSON object to a temporary payload file outside the squad root. Copy the
already-confirmed coordinator fields once; do not ask the coordinator to change
its payload. Legacy prose/YAML is adapted to this JSON, never executed:

* `squadRoot`: resolved single-squad `.copilot-tracking/squad` or member root
  `.copilot-tracking/squad/members/<name>`, inside the consumer repository.
* `runId`, `timestamp`: supplied run identity and ISO timestamp; Init is turn 1.
* `roster`: array of confirmed row objects, in supplied order, keyed exactly by
  `Role`, `Member Name`, `Agent Name (Primary)`, `Alternate Agents`, `Selection Cue`,
  `Invocation`, `Model Tier`, `Deliverable Root`, plus `Model` only when routing
  is on. `Member Name` may be omitted or empty; `Alternate Agents` may be empty.
  Preserve these cells without inventing names or alternates.
  Duplicate roles require distinct nonempty supplied names. Include the confirmed
  `scribe` / `Squad Scribe` row; missing rows or Primaries fail without state.
* `provenance`: one supplied string recording profile and applied packs, or
  `custom`. Adapt the coordinator's confirmed profile/packs into that string;
  do not select a profile, pack, agent, alternate, or model.
* `usage`: array of `{ "actor": "coordinator" | "scribe", "consumption": {...} }`,
  one entry per actor whose actual setup usage was supplied. Each actor appears
  at most once. At least one supplied block is required; missing consumption is
  a cheap failure, not permission to invent tokens. Both actors' supplied usage
  must be included. Blocks use these ten keys in order:
  `model`, `model_source`, `priced_as`, `model_tier`, `internal_turns`,
  `input_tokens`, `cached_tokens`, `cache_write_tokens`, `output_tokens`, `basis`.
  Copy actual reported model/token signals and their declared estimate basis.
  Numeric fields are nonnegative integers. `model_tier` is `fast`, `default`, or
  `extended`; `basis` is `estimated` or `tier-default`. Use `dispatch-reported`
  for supplied host identity, `session-inherited` only for a matching concrete
  session model, or `unknown` / `unresolved` when identity is unreported. The
  helper refuses `agent-pinned` rather than predicting actual usage from a pin.
  `priced_as` must name the resolved model's own seeded rate row when listed;
  only unknown or unlisted models use the matching tier fallback. Keep actual
  model attribution unchanged. `basis` is `estimated` for a resolved model,
  including an unlisted one, or `tier-default` for `unknown` / `unresolved`.
  Contradictions fail before publication; the ledger derives cost.
* Optional `mode`: `interactive` (default), `autonomous`, or `autopilot`.
* Optional `modelRouting`: `off` (default), `ranked`, `economy`, or `manual`.
  Copy resolved `Model` cells, including empty picks; never rank or discover.
* Optional `sessionModel`: literal supplied value, including `auto`; default is
  the schema's empty string. `auto` is not an actual model. Do no tool, network,
  or model discovery to resolve it; keep actual unreported usage unresolved.
* Optional `modelOverrides`: confirmed string map, default `{}`.
* Optional `notify`: `{ "approvalChannel": "in-chat" | "github-issue" | "webhook",
  "enabled": true | false, "email": "...", "github": { "handle": "...",
  "repo": "..." } }`. Email is optional courtesy data, never an approval adapter.
  Enabled `github-issue` requires handle and repo. Webhook selection needs no
  extra state field: transport reads configured tooling or `SQUAD_WEBHOOK_URL`
  at send time. Do not include webhook URLs, secrets, or credentials in payload
  or state. Omitted fields retain schema defaults. When absent, notifications
  default to disabled in-chat; disclose the status warning.
* Optional legacy `payloadType: initialization`, `turn: 1`, and `stateAdvance`
  with empty `activeRoles`, empty escalation lists, `mode`, `sessionModel`, and
  `modelOverrides` are accepted. Supply each model field at only one level.
  Adapt the legacy routing-mode field to `modelRouting` and the supplied overhead
  blocks to `usage`. `ledgerCommand` is accepted as inert compatibility data;
  it is never run. Other fields fail closed; omit irrelevant legacy sections.

The helper preserves cells and names. For member roots it rebases repository
tracking and relative deliverable roots under that member; sibling-member paths
are rejected. Each path in an ADO/Jira alternative is confined independently;
`docs/` and `outputs/` remain unprefixed, and `(squad state)` stays literal.
It writes only `team.md`, filtered `routing.md` (council always
retained), `decisions.md` with provenance, `notifications.md`, `state.json`,
`consumption.md`, `consumption-rates.md`, and `history/Squad Scribe.md`. No other
agent history is precreated. No Init ceiling or slot is admitted.

## Run and stop

Run the installed helper once, substituting trusted literal paths as arguments:

```powershell
pwsh -NoProfile -File "<skill>/scripts/Initialize-Squad.ps1" -RepoRoot "<repository>" -PayloadPath "<payload.json>"
```

The helper stages a new tree in a temporary sibling, invokes the deterministic
rate seeder, runs ledger `-Write` and `-Check -ExpectedHistoryCounts`, verifies the
roster/history, and publishes by directory rename only on success. Failure cleans
the stage, returns nonzero, and leaves any existing root unchanged. Traversal,
linked ancestor paths, collisions, partial roots, and re-init are refused.

Return the compact JSON status and warnings, then stop. Do not reread files,
recount blocks, audit arithmetic manually, or manufacture a Cost Comparison.
The ledger owns `n/a (initialization)` until the first work dispatch; there is
no setup-only manual baseline. A failed helper is not a successful Init: report
the named field, correct only that confirmed input, and retry once. Do not
dispatch a recursive repair loop or overwrite an existing tree.

Explicit roster refresh, memory, promotion, expansion, and federation-root Init
retain the full cold path. A host without the required shell/runtime uses that
path too; it does not silently drop validation. With `pwsh` available, rate
seeding always uses `Initialize-SquadConsumptionRates.ps1`, never model copies.
