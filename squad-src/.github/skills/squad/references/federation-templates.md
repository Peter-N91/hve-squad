---
name: squad-federation-templates
description: "Federation-root seed templates: federation.md, meta-routing.md, decisions.md, state.json, and the autopilot meta-run summary."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-08-14"
---

# Squad Federation Seed Templates

## Federation Seed Templates

The Squad Federation Coordinator hands these templates to the Squad Scribe when it creates a federation (after the user confirms the sub-squad set in Federation Init Mode). They stay consistent with `.github/instructions/squad/squad-federation.instructions.md`: `federation.md`, `meta-routing.md`, and the federation `state.json` use replace semantics; the federation `decisions.md` and `history/<sub-squad>.md` are append-only. Each `members/<name>/` sub-squad is seeded with the ordinary `team.md` and `routing.md` templates in [seed-templates.md](seed-templates.md) plus the `decisions.md`, `state.json`, and `history/` shapes in [entry-schemas.md](entry-schemas.md), rooted at `members/<name>/`.

### federation.md

Registry of local sub-squads and explicitly enrolled advisory repositories. For `Kind=in-repo`, `Sub-squad` also names its `members/<name>/` directory. For `Kind=repo`, Location is a canonical GitHub HTTPS identity and no member directory is created. Read [repo-exchange.md](repo-exchange.md) for advisory enrollment, local validation and persistence rules.

```markdown
---
description: "Squad federation registry: the named sub-squads in this repository and the profile each was seeded from"
---

# Squad Federation

## Sub-Squads

| Sub-squad | Profile | Kind    | Location          | Owner         | Description                                              |
|-----------|---------|---------|-------------------|---------------|---------------------------------------------------------|
| product   | product | in-repo | members/product/  | business-team | Requirements, roadmap, and stakeholder deliverables     |
| azure     | azure   | in-repo | members/azure/    | architects    | Azure build: Bicep, landing-zone, cost, and deployment  |
```

### meta-routing.md

Maps a request pattern or domain to a registered sub-squad. Seeded from each sub-squad's profile and description; every row points at a sub-squad that exists in `federation.md`.

```markdown
---
description: "Squad federation meta-routing: request patterns mapped to the sub-squad that handles them"
---

# Squad Federation Meta-Routing

| Pattern / Domain                                                 | Sub-squad | Parallel-Eligible |
|------------------------------------------------------------------|-----------|-------------------|
| requirements, PRD, BRD, roadmap, backlog, stakeholder, discovery | product   | yes               |
| Azure, Bicep, landing zone, deploy, IaC, cost, infrastructure    | azure     | yes               |
```

### decisions.md (federation root)

Append-only log of federation-level routing decisions — which sub-squad handled a request and why. Each entry references the sub-squad's own decision entries so the two levels stay linked. Uses the same append-only contract as a per-squad `decisions.md`.

```markdown
---
description: "Append-only log of squad federation routing decisions and their rationale"
---

# Squad Federation Decisions

Entries are appended below in chronological order. Each entry records which sub-squad(s) a request was routed to, the matched meta-routing pattern or explicit `squad=` target, the turn it was made on, and a reference to the sub-squad's own decision entries. Prior entries are never edited or removed.

<!-- Append new federation decision entries below this line. -->
```

### state.json (federation root)

Machine-readable federation status. Replace semantics — the Scribe overwrites it as the federation advances.

```json
{
  "schemaVersion": "1.2",
  "updated": "",
  "turn": 0,
  "mode": "interactive",
  "subSquads": [],
  "activeSubSquads": [],
  "openEscalations": [],
  "currentRun": {
    "sessionModel": "",
    "modelOverrides": {},
    "estCostUsd": 0,
    "estCreditsTotal": 0
  }
}
```

`subSquads` lists every registered sub-squad name (mirroring `federation.md`); `activeSubSquads` lists the sub-squad(s) dispatched on the current turn. `currentRun.sessionModel` and `currentRun.modelOverrides` are the federation-wide defaults a sub-squad inherits unless its own `state.json` sets them. Each sub-squad keeps its own `state.json` under `members/<name>/` per `.github/instructions/squad/squad-state.instructions.md`.

`mode` and `currentRun` are additive fields for federation-level autopilot (`.github/instructions/squad/squad-federation-autopilot.instructions.md`). `mode` records the autonomy mode in effect for the current federation turn (`interactive` or `autopilot`); `currentRun` aggregates the estimated cost and credits summed across every sub-squad inner run of the current meta-run, so the federation-level cost ceiling reads one number. All of these are backward-compatible — a federation that never runs autopilot leaves `mode` at `interactive` and `currentRun` at zero, and `sessionModel` / `modelOverrides` default to empty — so the `schemaVersion` bumps (`1.0` → `1.1` for autopilot, `1.1` → `1.2` for model attribution) keep existing federation state valid.

### history/autopilot-run-\<id>.md (federation root)

One file per federation autopilot meta-run, at the federation root. Append-only by topic-id: a subsequent meta-run against the same topic appends a new dated `## Meta-Stages` section rather than overwriting. The Scribe writes this file only when the Federation Coordinator runs in `mode=autopilot` with no `squad=` target (a single-target `mode=autopilot` forwards to one sub-squad and writes only that sub-squad's own `members/<name>/history/autopilot-run-<id>.md`).

```markdown
---
description: "Federation autopilot meta-run summary for topic <id>"
---

# Federation Autopilot Run: <id>

* Topic: <one-line summary>
* Opt-In: mode=autopilot (no squad= target)
* Cost Ceiling: <value or unset>
* Aggregate Cost: <est-usd> (~<est-credits> AI credits, estimated, not billed)
* Outcome: completed (awaiting final validation) | escalated (<reason>) | stopped (<reason>)

## Meta-Stages

| Order | Sub-squad | Inner Run                                        | Result             | Gate Fired (attributed)     |
|-------|-----------|--------------------------------------------------|--------------------|-----------------------------|
| 1     | <name>    | members/<name>/history/autopilot-run-<inner>.md  | <one-line outcome> | <none or gate + sub-squad>  |
| 2     | <name>    | members/<name>/history/autopilot-run-<inner>.md  | <one-line outcome> | <none or gate + sub-squad>  |
| final | (federation) | consolidated final-outcome                    | notified <recipient-or-in-chat> | Final-Outcome Validation |

## Gates and Approvals

| Timestamp | Gate                       | Raised By (sub-squad) | Awaiting / Resolved By      | Notes      |
|-----------|----------------------------|-----------------------|-----------------------------|------------|
| <ts>      | <Impactful / Risk / Final> | <sub-squad>           | <human decision or pending> | <one-line> |
```

Each row's `Inner Run` links the sub-squad's own `members/<name>/history/autopilot-run-<inner>.md`, so the two levels of provenance stay linked and auditable.

## Advisory Exchange Examples

Use these as synthetic structured examples, not preapproved tasks or completed runtime records. [repo-exchange.md](repo-exchange.md) owns the normative schemas, limits, validation and Scribe write order. All JSON examples in this section are exact compact UTF-8 lines with no trailing newline; hashes bind those bytes. Fixed dates and IDs make tests reproducible, not reusable live correlations.

### Mixed Registry

```markdown
| Sub-squad     | Profile  | Kind    | Location                             | Owner        | Description                 |
|---------------|----------|---------|--------------------------------------|--------------|-----------------------------|
| api           | software | in-repo | members/api/                         | api-team     | Local API work              |
| sdk           | software | in-repo | members/sdk/                         | sdk-team     | Local SDK work              |
| repo-exchange | software | in-repo | members/repo-exchange/                | tools-team   | Valid local member name     |
| service       | advisory | repo    | https://github.com/contoso/service    | service-team | Human-transported advisory  |
```

The service row creates no `members/service/`. An optional service meta-route has `Parallel-Eligible=no`. Advisory send/import use `history/repo-exchange/audit.md`; the valid member's flat `history/repo-exchange.md` remains unchanged and retains ordinary dispatch/consumption meaning.

### Packet Candidate

Owning hub Scribe stages this at `exchanges/staging/22222222-2222-4222-8222-222222222222/packet.json`. No final outbox exists yet. Run Issue before create-new byte copy and Issue audit/state/seal; transport only the committed outbox packet. SHA-256 is `634275dba25d9670c243a0d47c5fa6f0c99382282178f0ab3680c1a22d239bcc`.

```json
{"schemaVersion":"1.0","kind":"squad-repo-task","correlationId":"11111111-1111-4111-8111-111111111111","sourceRepository":"https://github.com/contoso/hub","sourceRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","targetRepository":"https://github.com/contoso/service","targetRevision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","taskId":"api-contract","createdAt":"2026-09-08T11:00:00Z","expiresAt":"2026-09-15T11:00:00Z","request":{"summary":"Assess compatibility.","acceptanceCriteria":["Record the compatibility result."],"inputs":[]},"constraints":{"execution":"advisory-only","transport":"user","authority":"target-local"}}
```

### Repository Claim

Only RepositoryRoot Scribe creates `exchanges/claims/11111111-1111-4111-8111-111111111111/claim.json` and its separate Claim commit. This single-root example pins the local squad. For a federated target, use the user's registered root (for example `.copilot-tracking/squad/members/api/`) with `executionKind=member` and compute new bytes/hash. Never derive the selected root from packet text.

```json
{"schemaVersion":"1.0","kind":"squad-repo-claim","correlationId":"11111111-1111-4111-8111-111111111111","packetSha256":"634275dba25d9670c243a0d47c5fa6f0c99382282178f0ab3680c1a22d239bcc","targetRepository":"https://github.com/contoso/service","targetRevision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","taskId":"api-contract","executionRoot":".copilot-tracking/squad/","executionKind":"single","claimedAt":"2026-09-08T12:00:00Z","claimAttemptId":"33333333-3333-4333-8333-333333333333"}
```

### Locally Observed Intake

Target Scribe writes `exchanges/inbox/11111111-1111-4111-8111-111111111111/intake.json` only in the live immediate continuation after successful Claim. The separate Accept operation binds this record, saved packet and fixed claim. The accepted base stays unchanged after local work advances HEAD.

```json
{"schemaVersion":"1.0","kind":"squad-repo-intake","correlationId":"11111111-1111-4111-8111-111111111111","packetSha256":"634275dba25d9670c243a0d47c5fa6f0c99382282178f0ab3680c1a22d239bcc","targetRepository":"https://github.com/contoso/service","targetRevision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","taskId":"api-contract","squadRoot":".copilot-tracking/squad/","acceptedAt":"2026-09-08T12:00:00Z"}
```

### Receipt Candidate

Target Scribe stages `exchanges/staging/44444444-4444-4444-8444-444444444444/receipt.json` with no final receipt present, validates Report against committed Claim/Accept, then copies bytes create-new and commits Report. Here the artifact bytes are UTF-8 `compatibility result` without newline; the Scribe history bytes are `# History: Squad Scribe\n\n### Recorded local work\n` with literal LF characters. These are synthetic evidence, not proof of substantive work or approvals.

```json
{"schemaVersion":"1.0","kind":"squad-repo-receipt","correlationId":"11111111-1111-4111-8111-111111111111","packetSha256":"634275dba25d9670c243a0d47c5fa6f0c99382282178f0ab3680c1a22d239bcc","sourceRepository":"https://github.com/contoso/hub","sourceRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","targetRepository":"https://github.com/contoso/service","targetRevision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","taskId":"api-contract","reportedAt":"2026-09-08T12:00:00Z","status":"reported","outcome":"completed","resultRevision":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","summary":"Local outcome recorded.","evidence":[{"path":"src/result.txt","sha256":"49190a2b24004c8ae950c23ec7dafd073c7839603dbc1b398f091749291ad73d"},{"path":".copilot-tracking/squad/history/Squad Scribe.md","sha256":"83091f9f6d39db3cee6262826778c2ea09978aab3c38f7240fdc855d48c01f86"}]}
```

### Prepared Existing State

This ordinary single-squad state advances turn 1 to 2 for the Accept example. It adds no exchange fields. The seal records successful read-back of exactly these bytes; later legitimate turns can advance beyond it.

```json
{"schemaVersion":"1.3","updated":"2026-09-08T12:00:00Z","turn":2,"mode":"interactive","activeRoles":[],"openEscalations":[],"currentRun":{"sessionModel":"","modelOverrides":{},"estCostUsd":0,"estCreditsTotal":0},"notify":{"approvalChannel":"in-chat","enabled":false,"email":"","github":{"handle":"","repo":""}}}
```

### Accept Audit Line

Append this same JSON line to both `decisions.md` and `history/repo-exchange/audit.md`, surrounded by the exact whole lines `<!-- squad-repo-audit:55555555-5555-4555-8555-555555555555:begin -->` and `<!-- squad-repo-audit:55555555-5555-4555-8555-555555555555:end -->`. Its artifact hashes refer to the packet, intake and claim lines above. Claim must already have its own complete root audit/state/seal; this Accept example alone is not a committed chain.

```json
{"schemaVersion":"1.0","kind":"squad-repo-audit","attemptId":"55555555-5555-4555-8555-555555555555","operation":"Accept","recordedAt":"2026-09-08T12:00:00Z","squadRoot":".copilot-tracking/squad/","correlationId":"11111111-1111-4111-8111-111111111111","taskId":"api-contract","registryAlias":"","packetSha256":"634275dba25d9670c243a0d47c5fa6f0c99382282178f0ab3680c1a22d239bcc","receiptSha256":"","sourceRepository":"https://github.com/contoso/hub","targetRepository":"https://github.com/contoso/service","sourceRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","targetRevision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","resultRevision":"","disposition":"accepted","reason":"","artifacts":[{"path":".copilot-tracking/squad/exchanges/inbox/11111111-1111-4111-8111-111111111111/packet.json","sha256":"634275dba25d9670c243a0d47c5fa6f0c99382282178f0ab3680c1a22d239bcc"},{"path":".copilot-tracking/squad/exchanges/inbox/11111111-1111-4111-8111-111111111111/intake.json","sha256":"191f61b820a013fd04e606f8392e515c40b8a88aec7ec0cdd32e964be50e9750"},{"path":".copilot-tracking/squad/exchanges/claims/11111111-1111-4111-8111-111111111111/claim.json","sha256":"3364ef17f58dd155039e6ee2d78970f3d2223465f3dcd94f80c84aee9a3e262b"}],"stateAdvance":{"fromTurn":1,"toTurn":2,"updated":"2026-09-08T12:00:00Z","stateSha256":"9ee03486e6d6da0c9cb187d43753b964399f93001ad2ea6b4115ba2cb5eb4547"}}
```

### Post-State Completion Seal

After both audit read-backs and the normal final state read-back succeed, create-new `exchanges/operations/55555555-5555-4555-8555-555555555555/commit.json`. This narrow post-state exception adds no state turn. Missing/tampered seal, incomplete audit, failed state advance or wrong immutable digest means incomplete, even if the packet and intake exist.

```json
{"schemaVersion":"1.0","kind":"squad-repo-commit","attemptId":"55555555-5555-4555-8555-555555555555","operation":"Accept","squadRoot":".copilot-tracking/squad/","correlationId":"11111111-1111-4111-8111-111111111111","packetSha256":"634275dba25d9670c243a0d47c5fa6f0c99382282178f0ab3680c1a22d239bcc","receiptSha256":"","auditSha256":"cff586f32c4f288642219a4af9df169c4b96cf0f70e07761a17946be2749bfda","stateAdvance":{"fromTurn":1,"toTurn":2,"updated":"2026-09-08T12:00:00Z","stateSha256":"9ee03486e6d6da0c9cb187d43753b964399f93001ad2ea6b4115ba2cb5eb4547"},"committedAt":"2026-09-08T12:00:00Z"}
```

### Retry and Context Examples

* Api accepts one correlation; sdk later presents the same bytes. Read the same repository claim, validate api's committed chain and return already-accepted at api with no second dispatch. Changed bytes conflict; Claim without complete Accept is incomplete at both roots.
* Two successful preflights compete. RepositoryRoot Scribe's create-new claim permits only one creator to complete Claim and the immediate member Accept payload. A losing or restarted session cannot finish the old acceptance.
* A single squad is promoted. Preserve its repository-root exchanges/claims unchanged. The old single-root binding is now root-relocated; do not migrate it into a member or reaccept the same ID.
* A staged candidate fails validation, a final copy collides, an audit append is partial, state fails to advance or seal creation fails. Retain bytes and withhold transport/work. Candidate-only failure may use a fresh attempt after confirmation; persisted claim/final/audit requires human review and a fresh correlation after accounting for work.
* Report/Import completes, then the identical receipt is presented after expiry. A full historical commit chain permits already-reported with no new writes, state, dispatch or cost; an unsealed final cannot become a positive retry.
* Git lacks offline capability or the hub lacks the source commit locally. Return offline-git-unavailable with no network fallback or configuration change. A receipt remains reported until separate current human review and a committed Verify record.
