---
title: Squad Skill Security Model
description: STRIDE model for local squad routing, connector file exchanges, and state persistence.
author: microsoft/hve-core
ms.topic: reference
ms.date: 2026-10-28
keywords: [squad, connectors, security, STRIDE]
estimated_reading_time: 6
---
<!-- markdownlint-disable-file -->
# Squad Skill Security Model

The runtime comprises `Resolve-SquadConnectorDispatch.ps1`,
`Invoke-SquadConnectorDispatch.ps1`,
`Resolve-SquadConnectorHistory.ps1`,
`Resolve-SquadModelRoute.ps1`, its shared `ModelBenchmarkScoring.ps1`,
`Get-SquadDispatchBrief.ps1`,
`New-SquadDispatchPlan.ps1`, `Set-SquadModelRouting.ps1`,
`Get-SquadPromotionPlan.ps1`, `Promote-SquadFederation.ps1`, and their shared
`SquadPromotion.psm1`,
`Get-SquadFederationInitPlan.ps1`, `Initialize-SquadFederation.ps1`,
`Get-SquadRosterExpansionPlan.ps1`, `Expand-SquadRoster.ps1`,
`Write-SquadHandoff.ps1`, `Write-SquadVerdict.ps1`, `Measure-SquadLedger.ps1`,
the shared `SquadUsage.psm1`, `Set-SquadCostPreflight.ps1`, and
`Initialize-SquadConsumptionRates.ps1`.
The two buckets below cover configuration/dispatch and file exchange/persistence.
Each enumerates all six STRIDE categories. Agent instructions are procedural
controls, not a sandbox or a substitute for host filesystem permissions.

> See also: [repo-wide STRIDE model registry](https://github.com/Peter-N91/hve-squad/blob/main/docs/security/security-model.md#skill-security-models).
> This repository previously had a security policy but no model registry; that
> registry indexes this scoped model, not a completed repository-wide assessment.

## Executive Summary

### Security Posture Overview

| Surface | Current controls | Residual boundary |
|---|---|---|
| Routing and registration | Explicit roster bindings, actual-unit model resolution, hash-bound Model-cell and additive roster expansion, manifest role admission, reserved governance roles, fail-closed ambiguity | Configuration and installed scripts must remain operator-controlled. |
| Offline capability evidence | Exact model/configuration checks, explicit verification dates, common versioned panels, digest validation and visible fallback | Curated verification facts and source hashes are not authenticated measurement signatures. |
| External file exchange | Closed schemas, request/result identity matching, output allowlists, structural path containment | A matching envelope does not authenticate its author. |
| Persistence | Closed handoff/verdict payload validation, shared per-root writer locks, hash/CAS routing and preflight transactions, staged federation Init/Expansion/Promotion with verification and rollback, binding-matched provenance, distinct member accounting, cumulative exact-session journal with history-prefix and native-identity deduplication, unique APM/plugin agent-name canonicalization, ledger checks | History, verdicts, lifecycle plans, and exact-session snapshots are local and editable by principals with repository write access; hashes detect changes but do not authenticate authors. |
| Domain execution | Consumer-owned adapter; no connector command execution | Host permissions and consumer automation govern actual source changes. |

Ratings are qualitative under the assumption that an external producer can
write its mailbox, but cannot modify trusted configuration or shipped scripts.
Different filesystem permissions or unattended policies change the risk.

## Contents

* [System Description](#system-description)
* [Trust Boundaries](#trust-boundaries)
* [Assets](#assets)
* [Adversaries](#adversaries)
* [Bucket B1: Configuration and Dispatch](#bucket-b1-configuration-and-dispatch)
* [Bucket B2: File Exchange and Persistence](#bucket-b2-file-exchange-and-persistence)
* [Enterprise Readiness Gaps](#enterprise-readiness-gaps)
* [References](#references)

## System Description

### Components

* The coordinator classifies work and retains governance and admission.
* Connector/model resolvers and the dispatch brief read roster, manifests,
  packaged model metadata, and local availability information.
* The dispatch planner resolves only selected role units. Its routing writer may
  add/change an active mode, Model column/cells, and supplied economy consent under
  the exact team hash; roster membership, routing rows, `routing=off`, and state
  remain outside its authority.
  `-ApplyModelRouting` delegates that same hash-bound transaction to the existing
  writer after plan validation and returns readiness only on its written receipt.
  Discovery carries trusted requested policy separately from recorded policy and
  grants no dispatch authority. Plugin dispatch guards resolve native agent IDs
  through installed definitions; they compare active Model cells, not routing
  intent, and cannot enforce activation when a coordinator skips preparation.
* The shared benchmark scorer validates pinned evidence and recalculates
  verification expiry offline. The repository's maintainer-only
  `Sync-ModelBenchmarks.ps1` acquires original-source evidence; dispatch never
  calls that networked generator. Unknown or incomparable evidence cannot
  become a measured capability claim through snapshot generation.
* The thin connector agent runs the lifecycle wrapper once. That wrapper owns
  request/snapshot publication, result checks, and private replay state; the
  shared resolver remains side-effect free.
* The historical identity helper validates confirmed retirement snapshots for
  the ledger and assurance reader. Exact completed headings scope that evidence;
  duplicate binding/heading authority and malformed manifest integer limits
  reject in both readers. It cannot register a removed endpoint or authorize
  later work.
* The consumer's adapter runs its own agents or workflow outside this package.
* The handoff writer, routing writer, ledger calculator, preflight helper, and
  rate seeder write their declared local state/output files. `SquadUsage.psm1`
  streams local host usage logs, deduplicates complete accounting identities,
  exposes native per-top-level-agent token categories and credits, and rolls nested
  agents up through host parent identities. `Measure-SquadLedger.ps1` stores only
  closed-schema per-session aggregates, hashed accounting identities, and ordered
  history coverage in `consumption-sessions.json`; repeated writes replace one
  native session and cross-session merges reject overlaps or history-prefix drift.
  If the journal is absent, bootstrap reads only repository-matching local logs and
  accepts them only when complete native event windows uniquely cover every metered
  history timestamp; overlapping or missing coverage fails closed. Only the selected
  active session receives a bounded open-tail allowance while its outer tool completion
  is pending. A later session revalidates and refreshes the latest cached native session
  from the completed log before appending. JSON timestamps remain strings during digest
  validation, avoiding culture-dependent replay drift.
  The ledger, run totals, and journal publish as one rollback-capable transaction.
  These helpers never emit prompts, responses, tool arguments, or raw log lines;
  host logs and the journal are not connector identity evidence.
* The promotion planner writes only a transport plan outside squad state. It hashes
  the complete plain-squad tree and every candidate directory. The promotion writer
  requires that exact plan hash plus an exhaustive relocate/keep partition, stages
  the final federation, revalidates under the ordinary writer lock, refuses linked
  paths/collisions/replay, and publishes only verified local copies. The plan and
  lock establish local integrity and serialization, not user identity.
* The federation Init preparer validates every new member through the standard
  Init payload builder and seals either a fresh root or the existing federation
  snapshot. The initializer runs member transactions in parallel inside an
  isolated stage and requires all receipts/ledgers. Fresh Init lock-publishes one
  complete tree; Expansion validates an additive projection, then moves only new
  members and owned root files under the same lock. A member failure or stale root
  discards the stage. `Initialize-Squad.ps1` accepts a distinct agent validation
  root only for the initializer's owned `.squad-federation-init-*` repository
  stage, preventing general cross-repository roster validation.
* The roster expansion planner resolves only confirmed shipped catalog roles and
  packs, validates installed dispatchable Primaries, seals the selected root's
  state/accounting/history and (for a member) its registry row, and emits exact
  final roster/routing/decision bytes. The apply helper requires that plan hash,
  revalidates under the plain lock or ordered federation/member locks, writes only those three files,
  preserves accounting/state/history byte-for-byte, and checks the ledger
  read-only. Recasting, removal, duplicate-role members, connectors, and existing
  root edits remain outside this writer.

### Data Flow

```mermaid
flowchart TD
  subgraph Operator["Operator-controlled host"]
    Config["Roster, manifests, pinned evidence, installed scripts"]
    Shell["Coordinator and resolver helpers"]
    Scribe["Handoff, routing refresh, preflight, rates, ledger"]
  end
  subgraph Exchange["Untrusted producer boundary"]
    Mailbox["Request and result files"]
    Endpoint["Consumer adapter and agents"]
  end
  subgraph Repository["Local repository storage"]
    Reports["Declared report roots and authorized worktree"]
    State["Squad history, state, decisions and ledger"]
    Usage["Local host usage logs"]
  end
  Config -->|"local Markdown/JSON reads"| Shell
  Shell -->|"file JSON request"| Mailbox
  Mailbox -->|"file JSON request"| Endpoint
  Endpoint -->|"file JSON result"| Mailbox
  Endpoint -->|"authorized local file writes"| Reports
  Mailbox -->|"validated JSON result"| Shell
  Shell -->|"structured handoff"| Scribe
  Usage -->|"local accounting reads"| Scribe
  Scribe -->|"local state writes"| State
```

## Trust Boundaries

### Boundary Diagram

```text
+---------------------------+       +---------------------------+
| Trusted host/configuration |       | Consumer process          |
| Coordinator and helpers    |--JSON-| Own agents and skills     |
| Scribe and preflight       |<-files| No HVE governance authority|
+-------------+-------------+       +-------------+-------------+
              | authorized writes                  | scoped writes
+-------------v-----------------------------------v-------------+
| Local files: reports/worktree, history, state, usage accounting |
| Permissions, process isolation and backup are host concerns.   |
+---------------------------------------------------------------+
```

### Boundary Descriptions

| Boundary | Trusted input | Untrusted or separately controlled input |
|---|---|---|
| B1 configuration to dispatch | Operator-confirmed roster and installed helpers | User task prose and external narrative cannot grant role authority. |
| B2 mailbox to validation | Pending request identity and declared output roots | Result JSON, artifact contents, endpoint availability, and fan-out claims |
| B2 persistence | Validated handoff and binding-derived identity | External outcome claims and host-log contents require their own validation. |

## Assets

| ID | Asset | Required property |
|---|---|---|
| A1 | Governance, council, and Scribe ownership | External work cannot acquire these authorities. |
| A2 | Declared reports and authorized source worktree | No undeclared overwrite or cross-squad write |
| A3 | Task/binding/member identity | Results stay attached to the intended request and squad. |
| A4 | History and accounting | External work stays unverified and unmetered; shim spend remains attributable; accepted exact sessions cannot overlap or detach from their covered history prefix. |
| A5 | Local inputs, host usage records, and exact-session journal | Expose only hashed accounting identity, session/agent/model labels, token categories, and credits; no prompts, responses, tool arguments, credentials, or raw-log disclosure |

## Adversaries

| ID | Capability | Assumption |
|---|---|---|
| ADV-a | Faulty or compromised external producer | Can send malformed/misleading results and modify files it is allowed to write |
| ADV-b | Another local process with mailbox access | Can race or replace an envelope; identity fields are not signatures. |
| ADV-c | Untrusted text in domain artifacts | Can make authority claims, but is data rather than an instruction source. |

## Bucket B1: Configuration and Dispatch

### Spoofing

The resolver binds connector id, endpoint kind, role, and target to a readable
manifest and applicable roster binding. These checks establish configuration
consistency, not the identity of the process behind a mailbox.

### Tampering

Closed fields and reserved role targets reject unsupported authority changes.
Keep roster/manifests and installed helpers writable only by trusted operators;
an adversary allowed to modify them can change the routing policy itself.
Benchmark checks reject invalid normalized scores/dates, conflicting records,
wrong model versions, incompatible configurations and mismatched evidence
digests. Acquisition and genuine verification remain separate from publication
and generation dates. These checks constrain a curated record's use; they do
not authenticate its publisher or make operator-supplied verification facts
cryptographic proof. Protect the pinned evidence and review refreshes as code.
Model refresh additionally requires the exact planned `team.md` hash, unchanged
source cells, one unambiguous roster row per role, and a safe lowercase model id.
Cost admission never trusts a lagging checkpoint as exact spend: native usage
records require complete status and stable host accounting identities. Cumulative
accounting additionally requires a unique native session id, non-overlapping hashed
request identities, a closed cache schema, and cached history identities that remain
an ordered prefix of current append-only history. Any mismatch keeps the journal
unchanged and returns to the all-history estimator.

Native role attribution does not trust a package-qualified host label by itself.
The raw `agentName`, `agentDisplayName`, and final namespace/path segment may resolve
only to one history-backed canonical agent name. This gives APM and plugin dispatches
the same accounting identity while refusing collisions or ambiguous aliases.

One legacy writer defect encoded an intentionally empty per-file session coverage
suffix as `[null]`. The reader recognizes only a one-null coverage array whose
persisted snapshot content digest still validates, normalizes it to empty in memory,
and rewrites canonical `[]` on the next ordinary transaction. Other nulls, invalid
identity strings, or digest drift remain rejected. Promotion's full-tree digest
already seals the journal; the apply path additionally verifies its presence in the
staged and published member. Its journal-only lifecycle advance accepts only newly
appended identities with no consumption block and revalidates unchanged exact totals
before publication.

### Repudiation

Binding/member ids and Scribe-rendered provenance identify the selected
configuration. They are not a signed record of who authored that configuration.
Pending identity hashes include the external member and owning roster, so a
rename or cross-squad resume cannot silently relabel a result. Retirement records
retain historical attribution only while the trusted local record remains intact.
Routing refresh and Cost Preflight decisions record their selected roles/slots and
inputs. Exact-session snapshots record native session and history coverage but remain
local evidence rather than signed audit events.

### Information Disclosure

Dispatch metadata and bounded inputs reach the selected endpoint. Limit those
inputs and output roots to the approved task. Required skill names are local
consumer configuration; manifests intentionally contain no credentials.
Usage parsing returns aggregate accounting fields. The persistent journal hashes
native accounting identities and never writes raw event content into squad state;
host-log and journal access, retention, and repository visibility remain deployment
concerns.

### Denial of Service

Unknown bindings and ambiguous execution stop or request clarification.
Unattended ambiguity fails closed. Invalid configuration can therefore block
work deliberately; it must not cause an inline substitute.
Incomplete or malformed native metering also blocks capped dispatch. Usage logs are
streamed rather than loaded whole, but very large local logs still consume host I/O.

### Elevation of Privilege

Connector role targets cannot replace Scribe/council identities. Council routing
bypasses overlays; coordinator and Scribe targets are rejected in bindings,
envelopes, and persistence. Saved work-role defaults also apply in autopilot.
These routing controls
do not restrict the operating-system privileges of the consumer's runner.

### Risk Rating

| Threat | Likelihood | Impact | Residual Risk | Status |
|---|---|---|---|---|
| Untrusted prose changes role authority | Medium | High | Low | Closed binding checks and canonical council routing; host configuration remains trusted. |
| Configuration or pinned model evidence changed by a local writer | Deployment-dependent | High | Medium | Host ACLs and change review required; not authenticated by the skill. |

## Bucket B2: File Exchange and Persistence

### Spoofing

Task, connector, role, binding, and output ids must match the request. Single-agent
results may omit `outputs`; orchestrators use declared slots. A local mailbox
writer can still reproduce these ids. Scribe marks accepted work unverified.

### Tampering

The deterministic helper rejects undeclared output ids, escaping/reserved paths,
reparse points, file-type/size/depth/count violations, and secret-shaped content.
The wrapper supplies the real workspace and immutable collision baseline,
checks hashes, and publishes without overwrite. A stateless validation call
alone does not prove replay protection or request/snapshot immutability.
Use distinct write scopes; separate report roots do not isolate source writers.
Promotion additionally rejects a changed plan hash, source/candidate digest,
candidate set, required-directory omission, existing federation or destination
collision before publish. Federation Init/Expansion binds the exact payload hash
to either an absent/empty root or a snapshot of every root/history file, registered
member state total and member-directory name. Expansion validates a staged final
projection, refuses name/route/history collisions, revalidates under the root
writer lock, never replaces existing member trees, and rolls back only files and
member moves whose owned hashes still match. A principal able to replace both the
installed scripts and the confirmed plan remains inside the trusted operator
boundary.
Roster expansion similarly binds exact final bytes to the current roster,
routing, decisions, state, accounting, rates, notifications, history, and
optional federation registry hashes. It refuses stale baselines and restores
only files still matching its planned output, so it cannot silently overwrite a
concurrent writer or reprice an exact ledger.

### Repudiation

Scribe records bound member identities, timestamps, artifact references, and
trusted accounting markers, and checks the resulting ledger. Local history is
not an immutable audit store. The wrapper persists hashes, unanswered attempts,
and consumed ids under `dropPath/.squad-connector`, using an exclusive task lock
and atomic state updates before returning terminal results. The stateless
resolver cannot prevent replay alone. Protect private state from the producer:
a local principal able to rewrite or delete it can defeat those checks.
Confirmed binding changes retain prior identities through Scribe-owned retirement
decisions scoped to exact completed history entries. These decisions do not grant
dispatch authority and, like the roster, rely on trusted local state writers.
Every Connector entry requires nonempty provenance, verification and unmetered
metadata, even when a synthetic roster member matches; every calculator mode
rejects incomplete records without rewriting history, ledger or state. Appending
a correction note does not supersede an invalid record. Scribe append-only and
native-model attribution rules are procedural controls, not host-enforced
immutability or proof of which model executed.

### Information Disclosure

Artifacts and usage logs may contain sensitive material. Apply the transport's
secret-content checks before accepting reports, and protect local logs and
outputs with host permissions. The wrapper returns validated metadata and
stable reasons, never raw external narrative or artifact contents. External
spend is not measured by the shim.

### Denial of Service

Missing results return `awaiting` and eventually escalate under deadline/retry
rules. The wrapper enforces protocol caps and atomic request publication;
consumers must also publish results atomically. The validator does
not supervise or terminate an external workflow.

### Elevation of Privilege

External content remains data and cannot approve a gate or supply a council
verdict. The connector has no command-execution transport. A consumer process
can nevertheless modify any files its own host credentials permit; use
least-privilege worktrees and isolation outside the prompt layer.

### Risk Rating

| Threat | Likelihood | Impact | Residual Risk | Status |
|---|---|---|---|---|
| Forged or replaced mailbox result | Medium | Medium | Medium | Identity checks and unverified marking; no message authentication |
| Escaping/undeclared report path | Medium | High | Medium | Wrapper filesystem/content checks tested; filesystem races and host permissions remain deployment boundaries |
| Duplicate/partial or absent delivery | Medium | Medium | Medium | Consumer/shim lifecycle and atomic publication required |
| Sensitive report/log disclosure | Deployment-dependent | High | Medium | Data minimization, content checks, and host ACLs required |
| Stale or tampered federation promotion plan | Low | High | Low | Exact plan SHA-256, full-tree digests, explicit candidate partition, linked-path refusal, locked revalidation and staged publish |
| Partial or conflicting federation initialization/expansion | Low | High | Low | Exact payload SHA-256, fresh/existing root snapshot, isolated parallel member staging, all-member receipt gate, root CAS lock, additive publish and owned-hash rollback |

## Enterprise Readiness Gaps

| ID | Severity | Gap | Status |
|---|---|---|---|
| G-SPF-1 | Spoofing-Med | File identities do not authenticate the producer. | Accepted transport limitation; require an appropriately protected mailbox. |
| G-TAM-1 | Tampering-Med | A stateless validation call alone does not establish lifecycle integrity. | Use the lifecycle wrapper and protect its private state with host permissions. |
| G-REP-1 | Repudiation-Med | Local durable replay state is not an immutable audit store. | Wrapper enforces consumption; host ACLs, retention, and backups remain consumer responsibilities. |
| G-INF-1 | InfoDisc-Med | Sensitive source/report/log access depends on host permissions and consumer data handling. | Consumer deployment responsibility |
| G-DOS-1 | DoS-Med | No packaged external runner, process supervision, or live transport | External runner and wake-up remain consumer-owned. |

## References

* [Connector transport contract](references/connector-contract.md)
* [Connector binding and governance contract](references/connector-role-modes.md)
* [Connector resolver](scripts/Resolve-SquadConnectorDispatch.ps1)
* [Connector lifecycle wrapper](scripts/Invoke-SquadConnectorDispatch.ps1)
* [Handoff writer](scripts/Write-SquadHandoff.ps1)
* [Verdict writer](scripts/Write-SquadVerdict.ps1)
* [Promotion planner](scripts/Get-SquadPromotionPlan.ps1)
* [Promotion transaction](scripts/Promote-SquadFederation.ps1)
* [Federation Init preparer](scripts/Get-SquadFederationInitPlan.ps1)
* [Federation Init transaction](scripts/Initialize-SquadFederation.ps1)
* [Roster expansion planner](scripts/Get-SquadRosterExpansionPlan.ps1)
* [Roster expansion transaction](scripts/Expand-SquadRoster.ps1)
* [Consumer guide and examples](https://github.com/Peter-N91/hve-squad/blob/main/docs/templates/connector-example/CONSUMER-GUIDE.md)
* [Repository security policy](https://github.com/Peter-N91/hve-squad/blob/main/SECURITY.md)
