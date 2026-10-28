# Scribe and linked-wiki optimization handoff

**Handoff date:** 2026-10-19

**Status:** Optimization paused for colleague ownership. Higher quality and lower
cost have **not** been established.

This is a **handoff-only document**, not an implementation release. The linked-wiki,
adversarial and source-capture implementation remains local and is not included in
this PR. Historical results below describe local development revisions, not the
current upstream package or validation of this documentation branch.

## Release reassessment: 2026-10-28

This addendum compares the handoff with upstream **v0.19.0**, commit
`a200b15dd929c1c1045176cae87f1a1ee381a429`. The dated investigation and negative
results below remain historical evidence, not measurements of this release.
The documentation PR merges cleanly with that release; the unpublished wiki
implementation has not been ported or validated against it.
The Scribe-only ownership blocker described below belongs to the dated upstream
publication attempt, not v0.19.0's ordinary persistence contract.

* Ordinary persistence is no longer Scribe-only. The coordinator directly runs
  `Write-SquadHandoff.ps1 -Quiet` synchronously in every routing mode. Supported
  Council, Intake and Discovery verdicts then use `Write-SquadVerdict.ps1 -Quiet`
  synchronously at the same root; completion uses
  `Test-SquadTurnCompletion.ps1`. Scribe remains responsible for cold operations,
  including memory and unsupported-operation fallback. Preserve these boundaries
  rather than restoring the old per-stage Scribe dispatch.
* Read `references/coordinator-runtime.md` and `references/economy-scribe.md`
  for the ordinary path. `scribe-payload-template.md` describes the cold path;
  it is not the ordinary writer's JSON schema. The ordinary writer accepts
  `decision.rationale` but rejects unknown keys. Do not forward the old
  `payloadType/historyRecords/notesForState` envelope or add an unimplemented wiki
  field to it. Define any producer-sidecar adapter and transaction boundary
  explicitly, including rollback, replay, and completion proof.
* The release contains no wiki ingestion/recall helpers. Its deterministic
  persistence removes one historical cost mechanism, not the need to validate
  wiki capture, semantic curation, retrieval or independent review. An actual
  memory/curation dispatch must still be attributed and charged.
* Native accounting now uses cumulative, deduplicated session snapshots in
  `consumption-sessions.json`, reconciled with `consumption.md` and `state.json`.
  Complete native records supply exact role costs, with nested workers assigned
  to their owning role and coordinator/Scribe usage assigned to orchestration.
  Incomplete coverage remains explicitly estimated. Direct script writes must
  not invent Scribe model usage.
* The ledger's single-model, identical-traffic Cost Comparison is a derived
  counterfactual, not an observed no-wiki control. Preserve the historical
  baseline and add a frozen, measured v0.19.0 no-feature control before testing
  a port; repricing identical traffic does not measure a feature's causal benefit.
  Include failed attempts, curation, recall, retries and session tails in any
  new delivery-economics comparison. Do not equate accepted output with validated
  business benefit, or treat old model/provider observations as current prices.

**Wiki revival gate:** Before resuming feature experiments or claiming release
compatibility, the colleague must port and freeze a separate candidate, then
pass the full applicable v0.19.0 installed-source validation suite, not only the
historical focused checks. Cover ordinary handoff and supported verdict schemas,
cold fallback, snapshot/verify/write modes, exact source bytes, rollback, no-op
replay, writer serialization and completion proof. Define whether wiki sidecars
participate in the transaction or a separately recoverable transaction; do not
silently widen either closed writer schema. Preserve atomic reconciliation of
`consumption.md`, `state.json` and `consumption-sessions.json`, including session
deduplication, late tails and explicit estimated fallback when coverage is
incomplete. Prove a complete accepted workflow with real capture/curation calls,
nonempty role recall, required independent reviews/dispositions and ledger
closure before admitting fresh independent families under the resume checklist.
Charge Scribe/curation model usage only when those calls actually occur. These
are pending integration requirements, not a claim that the paused implementation
is compatible or that new paid execution is authorized by this handoff.

Release sources: [coordinator runtime](https://github.com/Peter-N91/hve-squad/blob/a200b15dd929c1c1045176cae87f1a1ee381a429/squad-src/.github/skills/squad/references/coordinator-runtime.md),
[ordinary writer contract](https://github.com/Peter-N91/hve-squad/blob/a200b15dd929c1c1045176cae87f1a1ee381a429/squad-src/.github/skills/squad/references/economy-scribe.md),
and [accounting contract](https://github.com/Peter-N91/hve-squad/blob/a200b15dd929c1c1045176cae87f1a1ee381a429/squad-src/.github/skills/squad/references/consumption.md).

## Ownership and scope

The operator has assigned Scribe performance work to a colleague. Do not make
further Scribe behavior changes as part of this investigation. Existing
uncommitted changes are preserved, not reverted or approved for adoption by this
handoff. Coordinate ownership before integrating them.

The intended product remains a general, source-cited, well-linked Markdown wiki
for the entire squad, not an adversarial-only wiki and not a separate knowledge
graph. Required Challenger, independent Red Team and Reviewer safeguards remain.

The original completion criterion is **higher accepted-delivery quality and
lower fully accounted provider cost per accepted delivery than the pre-feature
baseline**, with no additional critical authority errors. Working wiring,
smaller prompts, valid JSON and better retrieval alone do not meet that criterion.

## Public upstream and integration blocker

The publication attempt fetched upstream `main` at
`9f39af1cd74e37f6b5daa37a9e92b2c011281a78`. That upstream revision requires
Scribe-only state-writing ownership and uses a different transactional handoff
schema from the local implementation. The local feature delta against preserved
pre-feature staged tree `23b25f85137837b8814d515269ede9b59d36a185` spans
**98 files, 6,561 insertions and 63 deletions**. Three-way integration left
**24 conflicted files**; additionally, the locally modified
`tests/tier0/TaskAwareDispatch.Tests.ps1` does not exist upstream.

This is a material ownership/schema integration blocker, not merely a Markdown
merge. Do not resolve it by choosing the entire local side, discarding upstream
Scribe ownership, or importing unrelated selected-worker, task-aware or FinOps
commits. Implementation publication was stopped; the operator then chose this
docs-only PR so the colleague can integrate the implementation separately.

These links are **available in public upstream**. They describe upstream's
contracts, not approval or publication of the local feature changes:

* [Scribe charter](../squad-src/.github/agents/squad/squad-scribe.agent.md)
* [Coordinator charter](../squad-src/.github/agents/squad/squad-coordinator.agent.md)
* [Scribe procedure](../squad-src/.github/skills/squad/references/scribe-procedure.md)
* [Scribe payload contract](../squad-src/.github/skills/squad/references/scribe-payload-template.md)
* [Operating procedure](../squad-src/.github/skills/squad/references/operating-procedure.md)
* [Transactional handoff](../squad-src/.github/skills/squad/scripts/Write-SquadHandoff.ps1)
* [Reviewer charter](../squad-src/.github/agents/squad/squad-reviewer.agent.md)
* [Handoff tests](../tests/tier0/WriteSquadHandoff.Tests.ps1)

## Local implementation and evidence only

The resources in this section are **plain local paths**, not public links. They
are absent from this PR and may be absent from a normal clone. All paths below
are relative to the original local repository root unless otherwise stated.

### Implementation pickup

* The original dirty primary checkout remains on `fix/task-aware-dispatch` at
  `25ff369`; its files and index were preserved. Do not stage, reset, stash or
  bulk-copy that mixed checkout.
* The fresh-upstream integration candidate is
  `.worktrees\linked-wiki-review`, branch
  `feat/linked-wiki-adversarial-handoff`, based on upstream `9f39af1`.
  It contains unresolved integration conflicts; it is not runnable or approved
  and was **not committed or pushed**.
* The earlier implementation worktree was preserved at
  `.worktrees\linked-wiki-review-implementation`, branch
  `feat/linked-wiki-adversarial-review`. It predates later primary fixes and
  must not be treated as the latest implementation source.
* The latest primary source freeze is Git tree
  `330bf8d8bfaedbe94be6992ee37c761b9d5b5ff7`. Its isolated feature delta is
  `experiments\decision-memory\implementation-baseline\publish-feature-only.patch`,
  computed against staged tree `23b25f85137837b8814d515269ede9b59d36a185`,
  **not HEAD**. The freeze tree itself includes pre-existing user work; use the
  feature-only delta for review, never publish that entire tree.
* Supporting local safety metadata is under
  `experiments\decision-memory\implementation-baseline\`, including
  `publish-freeze-tree.txt` and `publish-preservation.json`.
  Do **not** rerun `Integrate-Feature.ps1 -Apply`: it predates subsequent fixes
  and can overwrite or conflict with preserved work.

For pickup on the same machine, inspect the preserved patch and conflicted
candidate without changing the primary checkout. For another machine, arrange an
approved transfer of the **reviewed feature-only patch** and selected synthetic
evidence; local Git tree IDs and uncommitted branch contents are not retrievable
from this PR or the public remote. Review schema, ownership and prerequisite
differences in a separate integration branch before applying anything. Do not
upload the ignored archive, private corpus, credentials or customer traces.

### Evidence inventory

Evidence is local and ignored by Git. These paths will not accompany a normal
clone or a commit containing this document. Arrange an
approved transfer of the synthetic experiment evidence if the colleague works in
another checkout. Do not publish the whole experiment archive: older studies
include private project material.

| Resource | Purpose |
|---|---|
| `experiments\decision-memory\validation-20261018\recovery-v19\REPORT.md` | Successful wiring report: proven full source-installed baseline and candidate workflows |
| `experiments\decision-memory\wiki-optimization-20261019\REPORT.md` | Fresh-cycle report: initial research, repairs, negative pilot and limitations; predates subsequent development revisions |
| `experiments\decision-memory\wiki-optimization-20261019\development-v2\ROOT-FINDINGS.md` | Concrete capture, helper ergonomics, handoff-schema and lifecycle failures |
| `experiments\decision-memory\wiki-optimization-20261019\development-v3\PROTOCOL.md` | Exposed development replay design, not an unseen study |
| `experiments\decision-memory\wiki-optimization-20261019\RECOVERY-ACCOUNTING.json` | Reconciled known provider usage and interrupted-session caveats |
| `experiments\decision-memory\wiki-optimization-20261019\development-v3-ready\READY-AMENDMENT.md` | Latest prepared execution revision at handoff |

### Exact pause point

No paid inference was started after the Windows restart, and no owned
research/helper processes remain running.

* Latest **complete experiment freeze**:
  `experiments\decision-memory\wiki-optimization-20261019\development-v3-activation\lock.json`.
  Candidate aggregate:
  `6f8ce40aef63e50a56e362d408fe9e4cca52ffb8c1eb3270e6b4ce7d3ccab59d`.
* Latest **incomplete preparation**: `development-v3-ready`. Copying baseline
  scripts failed with Windows EPIPE/file-in-use. It has no lock, execution
  admission, diagnostics or paid calls. Preserve partial files; do not run
  its `execute.mjs`.
* Post-restart runtime regressions: **116/116 passed**, recorded in
  `experiments\decision-memory\wiki-optimization-20261019\development-v3-recovery\offline-full-verified.txt`.
* Source wiki/handoff checks: **94 passed**; an initial coordinator host-cap
  assertion failed. Subsequent coordinator/adversarial and new artifact-copy
  checks passed **17/17**; see
  `experiments\decision-memory\wiki-optimization-20261019\development-v3-activation\source-repair-verified.json`.
  These are separate focused results, not a complete suite pass.
* Post-restart production-facing edits compacted the coordinator below its host
  cap while retaining Scribe public-case ownership, added behavior case WIKI-16,
  new artifact-copy tests and a source-capture release fragment. They are
  uncommitted and unstaged; no existing work was reverted.

## What is established

The earlier native source-installed SDK workflow completed successfully:

* Candidate and immutable baseline each passed 15/15 hidden acceptance tests.
* Candidate created nine cited wiki pages and delivered nine nonempty ordinary
  role recalls.
* Plan/result Challenger, owner dispositions, fresh public-only Red Team,
  Reviewer, Scribe and ledger closure were observed.
* Independent Red Team tests passed 14/14 on the correct reference and detected
  eight wrong implementations.
* The reported validation included 62 host and 164 source regression tests.

That development diagnostic cost **372.848295 provider AI units** for the
candidate versus **179.987720** for baseline. It proves execution, not superior
quality or cheaper operation.

The tagged cached MCP package is version 0.8.0 with embedded coordinator
instructions. Successful source-installed SDK execution does **not** verify
activation through that published/cached MCP route. The cache was not edited.

## Latest development evidence

### Initial fresh-cycle pilot

| Arm | Accepted deliveries | Provider AI units |
|---|---:|---:|
| Pre-feature baseline | 1/1 | 155.606830 |
| Current wiki | 0/1 | 373.716695 |
| Initial optimized wiki | 0/1 | 353.253490 |
| New review gates retained, wiki disabled | 0/1 | 418.215325 |

These are development observations from one family, not independent statistical
replications. The wiki-off arm was an outcome-informed ablation. Its timeout and
all failures remain charged.

### Development v2: C-41

| Arm | Functional acceptance | Provider calls | Provider AI units |
|---|---:|---:|---:|
| Pre-feature baseline | 28/28 | 59 | 174.012545 |
| Producer delta | 28/28 | 144 | 364.832460 |
| Scribe reread | 28/28 | 148 | 382.620955 |

Both wiki arms failed lifecycle/actor/evidence gates despite functional success.
The producer path was not fully realized: structured knowledge was embedded in
prose rather than directly ingestible JSON-array sidecars, so Scribe still had to
reread and reconstruct it. The small cost difference is not a proven delivery
economic advantage. C-41 is exposed development material and must never be
relabelled an unseen holdout.

### Accounting boundary

The recovery reconciliation records **2,244.274390 known provider AI units,
879 calls and 78 sessions** for the fresh cycle through the initial and v2
phases. It separately discloses **4,121.558560 historical units** from the earlier
wiring cycle. These are provider-reported units, not dollar estimates.

Two earlier failed-session tails have explicit exposure warnings: observed
events are counted, but an unobserved final provider boundary is not assumed to
mean zero additional usage. Reconcile any later receipts before quoting a final
total. Historical spending authorization does not authorize new paid calls as
part of this handoff; do not omit costs or resume low-value retries.

## Findings relevant to the colleague

1. **Model curation is not the only cost.** Coordinator context replay, required
   review stages, owner follow-ups, state writing and recovery remain expensive
   even when wiki recall is disabled.
2. **Mechanical work leaked into semantic curation.** Scribe retyped readonly
   critiques/contracts, guessed helper arguments and attempted manual index work.
   A measured producer-Scribe segment spent 249 seconds / 45.787920 units on
   copying, rereading and invalid helper attempts. Exact bytes and public/private
   boundaries matter; copying must not become reinterpretation.
3. **Wrong handoff shape was misdiagnosed as missing identity.** A
   `payloadType/historyRecords/notesForState` envelope was forwarded directly to
   the transactional writer. Its top-level model fields did not match the
   writer's nested `consumption` schema. Validation reported an undefined model;
   the Scribe then removed required records instead of fixing the envelope.
4. **Prevalidation must preserve existing modes.** Snapshot/verify operations
   do not need a write payload. A new unconditional payload validator broke that
   compatibility in development.
5. **Late checks waste paid work.** A final Reviewer was dispatched although
   mandatory isolated correct-reference/wrong-case evidence was already missing.
   Enforce the existing evidence barrier before review, without inventing new
   acceptance criteria.
6. **Conflicting source contracts matter.** Hot operating-procedure, Scribe
   payload guidance and extended transaction scope need to agree. A structured
   supported helper transport is not equivalent to having no execution capability.
7. **Static compliance is not model adherence.** A Reviewer precedence
   contradiction was repaired after a live false acceptance. A later focused
   regression blocked correctly, but one focused success does not establish
   whole-workflow reliability.

## Lessons from the graph experiments

Do not revive a graph solely because wiki maintenance is expensive. The promising
transfer is the **capture path**, independent of storage representation:

* The originating role can propose a bounded evidence-backed knowledge delta
  alongside its ordinary deliverable; Scribe need not rediscover it from history.
* Deterministic helpers can validate hashes/schema, deduplicate, render pages and
  indexes, and apply bounded links transactionally.
* An empty delta is legitimate. Twelve candidates is a maximum, not a target.
* Charge extra producer output, semantic checking, retries and all maintenance.
  Manually seeded perfect candidates would invalidate the comparison.

This remains a hypothesis requiring a proper working implementation and new
validation. Prior graph capture showed that schema validity is not semantic
coverage: a replay captured 4/11 decision-bearing entries with Haiku 4.5 versus
9/11 with Sonnet. Automatic links must not infer approval, adoption or supersession.
Artifact revisions, completed executions and partial feedback are not authority.

The local archived study is `experiments\decision-memory\study\REPORT.md`; it is
not published here and requires a privacy review before any transfer. Do not
transfer its old model price estimates into current provider accounting.

## Existing changes requiring ownership review

The original primary worktree is dirty and includes unrelated pre-existing
selected-worker and task-aware changes. Do not reset, stash, bulk-revert or
overwrite it. The implementation remains uncommitted and unpushed; only this
handoff document and its documentation change fragment are published here.

Inspect current contents and compare against the frozen experiment manifests,
not merely against HEAD. In particular:

The following are **local implementation paths**, not claims that these files
or their modified contents ship in this PR. Shared upstream paths above point
to the upstream versions; review local deltas separately.

* `squad-src\.github\agents\squad\squad-scribe.agent.md`
* `squad-src\.github\agents\squad\squad-coordinator.agent.md`
* `squad-src\.github\skills\squad\references\scribe-procedure.md`
* `squad-src\.github\skills\squad\references\scribe-payload-template.md`
* `squad-src\.github\skills\squad\references\operating-procedure.md`
* `squad-src\.github\skills\squad\scripts\Write-SquadHandoff.ps1`
* `squad-src\.github\skills\squad\scripts\Copy-SquadSourceArtifact.ps1`
* `squad-src\.github\skills\squad\scripts\Sync-SquadWiki.ps1`
* `squad-src\.github\skills\squad\scripts\SquadWiki.psm1`
* `squad-src\.github\skills\squad\scripts\Get-SquadWikiRecall.ps1`
* `squad-src\.github\agents\squad\squad-reviewer.agent.md`
* `squad-src\.github\skills\squad\references\linked-wiki.md`
* `squad-src\.github\skills\squad\references\adversarial-review.md`
* `tests\tier0\LinkedWiki.Tests.ps1`
* `tests\tier0\AdversarialReview.Tests.ps1`
* `tests\tier0\WriteSquadHandoff.Tests.ps1`
* `tests\tier0\CopySquadSourceArtifact.Tests.ps1`
* `.changes\unreleased\20261019-source-capture-ergonomics.md`

Some changes predate performance optimization and implement the agreed wiki and
adversarial features. Others are experimental behavior/ergonomics changes.
Presence in the current checkout is not approval to adopt them. The frozen
secondary reference and per-revision source manifests are the separation tools.

## Resume checklist

1. Agree ownership and review the existing Scribe-related deltas before editing.
2. Preserve the pre-feature baseline: staged tree
   `23b25f85137837b8814d515269ede9b59d36a185` recorded in the local safety metadata.
   It includes the user's pre-existing work; arbitrary upstream is not equivalent.
3. Resolve upstream Scribe ownership/schema differences in a separate
   implementation integration branch; do not adopt the conflicted candidate
   wholesale. Freeze the colleague's candidate and select a new harness revision. Do not
   overwrite protocols, completed receipts or interrupted evidence.
4. Reuse the supported native SDK installed-source host and exact external
   dependency closure. Do not repeat the retired permissive/overrestrictive shell
   parser experiments or mistake static builtin task enums for custom-role support.
5. Validate snapshot/verify/write modes, transactional rollback, exact source
   bytes, actual actor/model attribution, no-op replay and complete error messages.
6. Prove a full accepted development workflow, including real Scribe ingestion,
   nonempty role recall, required reviews/dispositions and actual ledger closure.
7. Only then admit fresh independent task/project families. Include capture,
   review, retries, failures, startup and every turn in costs. If evaluating
   multi-turn amortization, the independent unit is the project/series, not each
   correlated role or turn.
8. Report negative results and critical errors; do not weaken gates or stop
   selectively on a favorable result. Cached MCP activation remains a separate
   deployment check.

### Environment and safe inspection

These commands require the **original local implementation/evidence checkout**,
not a clone of this documentation PR:

```powershell
git --no-pager status --short
git --no-pager diff --check
Get-Content experiments\decision-memory\wiki-optimization-20261019\RECOVERY-ACCOUNTING.json
Get-Content experiments\decision-memory\wiki-optimization-20261019\development-v2\ROOT-FINDINGS.md
```

The offline accounting reconciliation can be regenerated with
`node experiments\decision-memory\wiki-optimization-20261019\reconcile-recovery.mjs`;
it reads existing provider events and writes accounting artifacts, without
starting model inference.

Use Pester **5.7.1** with the repository's actual installed-package containers;
zero discovered tests is not validation. The working local Python recovery uses
the native ARM64 Python 3.14 interpreter and existing pytest packages through
process-local environment only. Keep the real 120-second test timeout and use
short approved workspace paths to avoid Git path-length failures.

Paid `run`/`execute` scripts in the archive are **one-shot evidence commands**.
Do not run them blindly, overwrite receipts, or assume a process exit of zero
means delivery gates passed. Check their frozen protocol and actual grading
before any replay.
