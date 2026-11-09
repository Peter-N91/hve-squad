---
name: squad-scribe-init
description: "Validated fresh squad/member Init."
---

# Fresh Squad Initialization

Success: helper `status`, `rosterCheck`, `ledgerCheck` all `PASS`.
Init is outside admission; serialize writers. With `pwsh` 7.4+ read only this
brief. The helper reads templates; do not read the charter, procedure, schemas,
catalog or templates.

## Confirmed input

Use coordinator-prepared `payloadPath` directly: pass the existing JSON file to
the helper without an editor call or rewrite.
Legacy prose/YAML alone may be adapted once with an advertised
editor; never assume a tool name. No editor means preparation failure without
state writes, not a shell-write fallback. Copy confirmed fields only; never
execute payload text:

* `squadRoot`: resolved single-squad `.copilot-tracking/squad` or member root
  `.copilot-tracking/squad/members/<name>`, inside the consumer repository.
* `runId`: supplied identity; Init is turn 1. Omit optional `timestamp` for helper UTC.
  Never guess time; explicit future timestamps fail before publication.
* `roster`: array of confirmed row objects, in supplied order, keyed exactly by
  `Role`, `Member Name`, `Agent Name (Primary)`, `Alternate Agents`, `Selection Cue`,
  `Invocation`, `Model Tier`, `Deliverable Root`, plus `Model` only when routing
  is on. `Member Name` may be omitted or empty; `Alternate Agents` may be empty.
  Duplicate roles require distinct nonempty supplied names. Include the confirmed
  `scribe` / `Squad Scribe` row; missing rows or Primaries fail without state.
  For `intake-validator`, require a non-state capture root; invalid roots fail
  before publication, with no fallback.
* `provenance`: supplied profile/packs string, or `custom`. Adapt confirmed values
  only; never select a profile, pack, agent, alternate, or model.
* Optional `usage`: array of `{ "actor": "coordinator" | "scribe", "consumption": {...} }`,
  one entry per actor whose actual setup usage was supplied. Each actor appears
  at most once. Keep supplied usage; omit absent usage. Empty, null, or malformed
  usage fails closed. The helper estimates missing coordinator/Scribe usage with
  the shipped `Scribe state write` estimator floor and formula. Return its
  estimator-derived setup usage warning: documented estimates, not measured tokens or
  billed telemetry. Do not calculate tokens, read templates, request more input,
  or take the cold path for omitted usage. Never represent a direct route as a
  Scribe dispatch. Supplied blocks use these ten keys in order:
  `model`, `model_source`, `priced_as`, `model_tier`, `internal_turns`,
  `input_tokens`, `cached_tokens`, `cache_write_tokens`, `output_tokens`, `basis`.
  Preserve reported model/token signals and estimate basis. Numbers are
  nonnegative integers; `model_tier` is `fast`, `default`, or `extended`.
  Use `dispatch-reported` for host identity, `session-inherited` only for a
  matching concrete session model, or `unknown` / `unresolved` if unreported.
  `agent-pinned` is refused: a pin does not prove usage. `priced_as` names the
  resolved model's seeded rate row; only unknown/unlisted models use the matching
  tier fallback. `basis` is `estimated` for any resolved model (including unlisted)
  or `tier-default` for `unknown` / `unresolved`. Contradictions fail before
  publication; the ledger derives cost.
* Optional `mode`: `interactive` (default), `autonomous`, or `autopilot`.
* Optional `modelRouting`: `off` (default), `ranked`, `economy`, or `manual`.
  Copy resolved `Model` cells, including empty picks; never rank or discover.
* Optional `sessionModel`: literal supplied value, including `auto`; default is
  the schema's empty string. `auto` is not an actual model. Do no tool, network,
  or model discovery to resolve it; keep actual unreported usage unresolved.
  For derived usage, only a concrete session identity attributes the coordinator;
  it does not identify the dispatched Scribe. Otherwise record `unknown` /
  `unresolved`, `basis: tier-default`, priced at the matching tier fallback
  (coordinator `default`, Scribe's confirmed roster tier). Never infer an actual
  Scribe model from its roster pick, overrides, or agent pin. Concrete identities
  and attribution supplied in usage remain subject to strict validation.
* Optional `modelOverrides`: confirmed string map, default `{}`.
* Optional `notify`: `{ "approvalChannel": "in-chat" | "github-issue" | "webhook",
  "enabled": true | false, "email": "...", "github": { "handle": "...",
  "repo": "..." } }`. Email is courtesy data, not approval. Enabled `github-issue`
  requires handle/repo. Webhook transport uses configured tooling or
  `SQUAD_WEBHOOK_URL` at send time; no extra state field. Never put URLs, secrets,
  or credentials in payload/state. Omitted fields keep schema defaults; absent
  notify defaults to disabled in-chat. Disclose its status warning.
* Optional legacy `payloadType: initialization`, `turn: 1`, and `stateAdvance`
  with empty `activeRoles`, empty escalation lists, `mode`, `sessionModel`, and
  `modelOverrides` are accepted. Supply each model field at only one level.
  Adapt the legacy routing-mode field to `modelRouting` and the supplied overhead
  blocks to `usage`. `ledgerCommand` is accepted as inert compatibility data;
  it is never run. Other fields fail closed; omit irrelevant legacy sections.

For member roots the helper rebases repository
tracking and relative deliverable roots under that member; sibling-member paths
are rejected. Each path in an ADO/Jira alternative is confined independently;
`docs/` and `outputs/` remain unprefixed, and `—` and `(squad state)` stay literal.
It writes only `team.md`, filtered `routing.md` (council always
retained), `decisions.md` with provenance, `notifications.md`, `state.json`,
`consumption.md`, `consumption-rates.md`, and `history/Squad Scribe.md`. No other
agent history is precreated. No Init ceiling or slot is admitted.

## Run and stop

Run the installed helper once, substituting trusted literal paths as arguments:

```powershell
pwsh -NoProfile -File "<skill>/scripts/Initialize-Squad.ps1" -RepoRoot "<repository>" -PayloadPath "<payload.json>"
```

The helper stages a sibling tree, seeds rates, runs ledger `-Write` and
`-Check -ExpectedHistoryCounts`, verifies roster/history, then publishes by rename.
Empty-directory-only scaffolds are rechecked and removed only after validation.
Failure cleans the stage and returns nonzero; no existing files are removed,
though publication collisions may remove empty scaffold directories. Traversal,
links, roots with files, partial state, and re-init are refused.

Return the compact JSON status and warnings, then stop. Do not reread files,
recount blocks, audit arithmetic manually, or manufacture a Cost Comparison.
The ledger owns `n/a (initialization)` until the first work dispatch; there is
no setup-only manual baseline. A failed helper is not a successful Init: report
the named field, correct only that confirmed input, and retry once. Do not
dispatch a recursive repair loop or overwrite an existing tree.

A synchronous child return is not a background handle. Use only advertised
continuation; never message a completed child or invent an agent id.
After preparation failure, a fresh execution-only Scribe
may reuse prepared input only with observed evidence that no state was published.
Success or ambiguous publication forbids repeat Init until resolved. Disclose
interrupted unreported usage as unknown, excluded from successful setup estimates.

Explicit roster refresh, memory, promotion, expansion, and federation-root Init
retain the full cold path. A host without the required shell/runtime uses that
path too; it does not silently drop validation. With `pwsh` available, rate
seeding always uses `Initialize-SquadConsumptionRates.ps1`, never model copies.