---
name: squad-model-scoring
description: "Versioned capability comparison shared by generation and offline routing: verified evidence, separate dates, common comparison panels, qualification, and explicit coverage limitations."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-23"
---

# Capability Comparison Policy

**Policy `squad-capability-v3` compares supported task evidence, not price.**
`scripts/ModelBenchmarkScoring.ps1` is the single executable owner used by
snapshot generation and offline routing. Identical evidence, policy and
evaluation date produce identical results. A snapshot generation date never
refreshes evidence.

## Separate Decisions

| Concern | Meaning |
| --- | --- |
| Availability | The host offers the exact dispatch ID. Missing evidence is not missing model access. |
| Eligibility | Availability, minimum capability-class floor and basic suitability. A floor is not a spending ceiling. |
| Capability | Benchmark-specific percentiles combined on one selected, versioned primary panel. |
| Confidence | Comparable independent coverage and genuine verification, not publication recency or extra capability weight. |
| Cost | Known nonnegative representative-token Blended USD/1M, not latency, billing or measured end-to-end efficiency. |

Manual retains valid explicit cells. Off applies no model selection. The Scribe
keeps its explicit pin and coordinators keep the selected session model. Floors,
consent, protected roles, gates, persisted dispatch cells and Cost Preflight are
unchanged.

## Evidence Schema and Dates

The `Benchmark Scores` table retains score, category, original publisher,
publisher/data version and provenance, and adds explicit model/configuration,
verification and date metadata:

| Field | Meaning |
| --- | --- |
| Model version | The exact evaluated source model, including checkpoint and reasoning-setting suffix where supplied; must match this catalog model, never a solver alias or a different release. |
| Configuration | Versioned evaluation dataset, prompting, scoring, repeats and harness basis. A publisher/data release is not automatically a harness version. |
| Result date | Known measurement or publication date. Model release dates and archive record creation dates are not substituted. `unknown` stays unknown. |
| Retrieved | Actual acquisition of the evidence record, not the result date or artifact assembly date. |
| Verified | Actual check of the exact identity, original publisher, result and configuration. |
| Verification | `verified`, `unverified`, `incomparable`, `invalidated`, or `superseded`; the reason remains explicit. |
| Source URL / Verification basis | Original authority and retained source-content hash(es) supporting the check. A URL or a recent download alone is not verification. |
| Legacy date | Unchanged historical row `Retrieved` value whose meaning was ambiguous. It is not silently promoted to any of the three dates above. |
| Generated | Snapshot header: assembly/evaluation date for the generated views, never source verification. |

The **90-day safeguard applies to Verified**, inclusive of day 90, not result
publication age. Verified evidence also needs a real acquisition date, valid
original source, exact model identity, known compatible configuration and
verification basis. Older valid results remain usable; unknown result dates
are disclosed, not invented. A new model version never inherits an older
version's check. Invalidated or superseded *results* are unusable; the existence
of a successor model does not by itself invalidate an exact older model's result
if the host still offers it.

Future or malformed dates, invalid normalized scores, unsupported provenance
and conflicting duplicates invalidate input. Unknown dates are represented
explicitly. A known result cannot postdate its acquisition or verification.
A later re-download may postdate an older check; it does not renew that check.
Self-reports and aggregate indices never enter capability or confidence.

Legacy eight-column snapshots, including `squad-capability-v2`, are read as
**unverified legacy evidence**. Their raw scores and ambiguous date values
remain auditable, but installation, rebuilding or changing the policy label
cannot make them verified. The generator can attach separately supplied,
record-bound verification; otherwise routing visibly falls back.

## Fixed Assignment Profiles

Every selected primary has equal weight, `1 / primary count`. Secondary
evaluations have capability weight **0** and only break a genuine capability
tie. Missing difficult evidence is never replaced per model.

| Class | Full primary panel | Secondary evaluations |
| --- | --- | --- |
| research | GDP.pdf; GPQA diamond | DeepResearch Bench; SimpleQA Verified; CritPt; HLE |
| planning | FrontierMath-Tiers-1-3-v2; GPQA diamond | FrontierMath-Tier-4-v2; ProofBench; OTIS Mock AIME |
| implementation | SciCode; Terminal-Bench | SWE-Bench verified; FrontierCode; DeepSWE; APEX-Agents; FrontierSWE; OSWorld 2.0 |
| review | SciCode; GPQA diamond | SWE-Bench verified; Terminal-Bench; CritPt; ProofBench |
| council | GPQA diamond; HLE | GDP.pdf; FrontierMath-Tiers-1-3-v2; CritPt |
| intake | GDP.pdf; GPQA diamond | SimpleQA Verified; APEX-Agents |
| bookkeeping | SciCode; GPQA diamond | SimpleQA Verified |

Full panel IDs are `<class>-full`, version `1`. Implementation additionally
defines **`implementation-scicode`, version `1`**, with SciCode alone at weight
1 and evidence level **reduced**. It is a narrower scientific-Python proxy, not
an equivalent measurement of repository work, terminal agents, review quality
or universal implementation superiority. Quantitative roles retain that same
declared proxy rather than claiming a separately validated assessment.

### Panel Selection

Select once per assignment class from the **complete pinned population**, before
host availability, floors, prices or model scores are considered:

1. Count distinct models with verified comparable coverage of every primary on
   each declared panel. A defensible panel needs at least two such models.
2. Prefer the panel with the greatest complete-model count.
3. On equal count prefer more primary evaluations, then the declared panel order.
4. Use only that panel for every candidate in the class. Never compare a
   full-panel score with a reduced-panel score or select a different favorable
   benchmark for each model.

If no panel is defensible there is no numeric capability comparison. If a
selected panel excludes an otherwise eligible model, report the exact missing,
expired, unverified or incomparable evaluation. Also report full-profile gaps
when a reduced panel is selected. Host list changes cannot change the panel,
evidence labels or normalization. A new snapshot or evaluation date can.

The 2026-10-23 inventory for this policy demonstrates why the reduced panel is useful:
22 existing SciCode records can be reproduced against exact original publisher
variants and a common protocol; the legacy Terminal-Bench maxima mix agents and
do not establish one verified harness. The reduction is a coverage decision,
not a replacement chosen for a preferred winner. Fallback configurations and
unreproduced exact variants stay visible and are not credited to one model.

## Normalization and Comparability

Compare models within each evaluation first, never average unrelated raw
fractions into a capability claim. The reference population is all distinct
usable independent model rows in the snapshot, including unavailable models.
An evaluation needs at least two models and exactly one
`Source ID @ Source version @ Configuration` identity. Different known harness
or configuration cohorts are incomparable, not pooled. Repeated equivalent
decimal spellings count once; conflicting model/evaluation records are refused.

For score `s`, population `N`, number of lower scores `L` and number of equal
scores `E`, its percentile is:

```text
(L + (E - 1) / 2) / (N - 1)
```

Capability is the equal-weight mean of the selected primary percentiles. These
are snapshot-relative ordinal standings, not success probabilities or measured
effect sizes. Native scores, reference counts and configuration remain visible.
Published model/effort settings are conditional evidence, not a claim that the
host executes that setting; differing or mixed agent harnesses are not pooled.
No intermediate rounding or invented tie tolerance is used. Display rounding
never affects selection. Missing uncertainty estimates are not manufactured.

## Coverage and Fallbacks

Per-evaluation diagnostics distinguish `missing-evaluation`,
`verification-expired`, `older-valid-result`, `unverified`, `incomparable`,
`invalidated`, `superseded`, and usable `verified` evidence. A class with valid
evidence but incomplete selected-panel coverage is `insufficient-coverage`;
only `sufficient` results receive a numeric capability. Reduced is an evidence
level, not a synonym for full coverage or a reason to hide full-profile gaps.

With no supported comparison for an eligible candidate, retain declared fit as
a last resort. If no eligible model has sufficient evidence, order declared
fit, known Blended cost and deterministic tie-breaks, label **declared-fit
fallback**, and explain the actual rejected evaluations. It is not a measured
capability winner. Manual advisory suggestions disclose this quietly; valid
explicit cells and Off behavior do not depend on evidence availability.

The legacy fit `0..3` remains basic suitability/display: bucket the native
selected-primary mean at 0.25, 0.50 and 0.75. Fit never decides the ordering of
sufficient comparable candidates. Catalog age still governs the existing
static-tier fallback; floor exhaustion still follows its existing escalation.

## Selection Objectives

**Ranked:** eligibility; highest supported task capability on the selected panel;
comparable secondary coverage on an exact capability tie; freshest oldest
**verification** date; lowest known Blended cost on a remaining tie; newer
generation within a family; fixed catalog order, never name spelling.

**Economy:** only `developer`, `technical-writer`, `presenter`,
`prompt-engineer`, and `data-scientist` may change Ranked's pick. Require the same
eligibility and selected-panel evidence plus a known nonnegative price:

| Implementation panel | Versioned Economy qualification |
| --- | --- |
| implementation-full v1 | `implementation-full-midpoint-v1`: each primary percentile >= 0.50 |
| implementation-scicode v1, reduced | `implementation-scicode-upper-quartile-v1`: SciCode percentile >= 0.75 |

The reduced minimum is intentionally different: one upper-quartile coding proxy
is not silently equated to two midpoint requirements. Both are declared policy
minimums, not empirically validated guarantees. Take the lowest qualified price,
then higher capability, then confidence and deterministic tie-breaks. Additional
capability never overrides lower price. Unknown prices are not zero.

No qualified candidate means explicit Ranked fallback with qualification and
rejection reasons. Modes may legitimately agree; never force different winners.
Failure escalates once to Ranked after Scribe persistence and a new Cost
Preflight when required. Equal picks have no higher-ranked escalation target.
All ordinary review and safety gates remain required.

## Synchronization, Digests and Explanations

Runtime is offline. Sync owns source acquisition and verification. Local archive
inputs alone are not newly verified: `-VerificationPath` supplies explicit
record-digest-bound evidence checks. Online SciCode refresh cross-checks the
original publisher's exact variant/value and versioned methodology; unknown
configurations, mixed/fallback attribution and source changes fail closed with
reasons. Other sources need equally explicit verification, not guessed harnesses.
Offline `-SnapshotPath` preserves acquisition and verification facts.

The content digest includes policy/panels, scores, identities, configurations,
result/acquisition dates, verification state/date/basis and legacy facts.
Acquisition facts are hashed because unknown acquisition is ineligible.
New retrieval or assembly never renews an old verification. A real renewal changes
the digest even if scores do not. Sync may retain a still-current identical
record's previous acquisition/check until the 60-day renewal window, avoiding
date-only PRs without extending a check it did not persist.

Expiration is recalculated at runtime and on regeneration using the evaluation
date, so an unchanged content digest is never proof that evidence is still
eligible. Reports identify snapshot digest **and evaluation date**.

Reports include the selected panel/version, evidence level, selection rule and
coverage alternatives; per-candidate selected and full-profile diagnostics with
the relevant dates; qualification rule; availability separately from evidence;
objective, score, cost/basis, reason and escalation. `rationale` carries the
same facts into Route rationale. Existing ten-field consumption/history schemas
do not change. Requested, expected and host-unreported effective/observed
execution remain distinct; deterministic routing spends no inference request.
