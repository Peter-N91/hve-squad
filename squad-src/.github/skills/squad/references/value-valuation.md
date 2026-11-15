---
name: squad-value-valuation
description: "Deterministic FinOps monetary valuation contract, 9-category conversion formulas, basis separation, and Measure-SquadBenefitValue.ps1 schema."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-11-15"
---
<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

# FinOps Stated Monetary Valuation

Use this reference when `value-economist` (`Squad Value Economist`) interprets FinOps benefit-claim evidence ([business-value-measurement.md](business-value-measurement.md)) and HVE Squad delivery ledgers ([consumption.md](consumption.md)) to derive a **stated monetary representation** for stakeholders.

All decimal arithmetic, currency checks, overlap deductions, sensitivity ranges, cost offsets, Benefit-Cost Ratios (BCR), and ROI percentages are computed deterministically by `scripts/Measure-SquadBenefitValue.ps1` (`SquadBenefitValuation.psm1`). Never compute or round monetary totals by hand in model prose.

## Four strict monetary basis buckets

Every claim and rollup figure belongs to exactly one basis bucket. Never sum across evidenced and counterfactual buckets:

| Basis | Meaning | Counted in `totalStatedEvidencedValue`? |
|---|---|---|
| `finance-approved` | Supported observed outcome (`status: supported` + `evidence_links`), valid category valuation formula, `valuation.financeApproved: true`, and `business_decision.status: approved` with a non-empty `reference`. | **Yes** (`financeApprovedValue`) |
| `stated-indicative` | Supported observed outcome (`status: supported` + `evidence_links`) converted using explicit user- or domain-supplied monetary drivers (`unitValue`, `hourlyRate` + `redeployedShare`, `costPerDefect`, etc.), awaiting Finance sign-off. | **Yes** (`statedIndicativeValue`) |
| `modeled-counterfactual` | Counterfactual model-routing savings from `consumption.md` (`baselineUsd - squadUsd`) or target-based forecasts for `pending` claims whose observation window is still open. | **No** — reported separately in `modeledCounterfactualValue` |
| `unmonetized-native-only` | Claims with `status: gap`, missing conversion parameters, violated guardrails (such as degraded quality floor or unverified demand), currency mismatch without `fx_rates`, or leading-indicator `engagement` claims without downstream conversion rates. | **No** — preserved in native operational units with missing inputs named |

## Invocation

```powershell
pwsh -NoProfile -File <skill>/scripts/Measure-SquadBenefitValue.ps1 `
  [-ClaimsPath <claims.json> | -ClaimsJson '<json>'] `
  [-SquadRoot <squad-or-federation-root>] `
  [-OutputPath <.copilot-tracking/finops/stated-value-YYYY-MM-DD.md>] `
  [-Format json|markdown] `
  [-AsOf YYYY-MM-DD]
```

* Exit `0`: prints deterministic JSON (default) or Markdown to stdout; writes `-OutputPath` when requested.
* Exit `1`: documented input/validation/guardrail stop (`Measure-SquadBenefitValue: ...` on stderr).
* Exit `2`: unexpected runtime failure.
* `-SquadRoot` is read strictly read-only (single squad or all `members/*` in a federation), extracting AI spend, accepted-deliverable unit economics, counterfactual savings, and any `Claim ID:` entries recorded in `decisions.md`. `-OutputPath` is refused if it points inside `.copilot-tracking/squad/`.

## Input JSON contract

```json
{
  "report_id": "q4-ai-service-desk",
  "as_of": "2026-11-15",
  "currency": "USD",
  "fx_rates": { "EUR": 1.08 },
  "includeSquadAiSpendInCost": true,
  "delivery_valuation": {
    "baselineHoursPerDeliverable": 6.0,
    "observedHoursPerDeliverable": 1.5,
    "hourlyRate": 110.0,
    "redeployedShare": 0.75,
    "attributionShare": 1.0,
    "financeApproved": false
  },
  "benefit_claims": [
    {
      "claim_id": "claim-cap-01",
      "category": "capacity gained",
      "hypothesis": "Reduce L1 triage handling hours via guided resolution",
      "beneficiary": "EMEA Service Desk",
      "measurement_owner": "Ops Analytics Lead",
      "status": "supported",
      "overlap_group": "emea-triage-time",
      "baseline": { "metric": "hours_per_ticket", "value": 0.50, "unit": "hours", "period": "2026-09", "source": "ITSM export" },
      "target": { "metric": "hours_per_ticket", "value": 0.25, "unit": "hours", "by": "2026-12" },
      "observation": { "value": 0.30, "unit": "hours", "period": "2026-10", "source": "ITSM export" },
      "evidence_links": ["docs/evidence/itsm-october.csv"],
      "business_decision": { "status": "approved", "owner": "VP Support", "reference": "FIN-2026-104" },
      "valuation": {
        "direction": "decrease",
        "volume": 4000,
        "hourlyRate": 65.0,
        "redeployedShare": 0.80,
        "attributionShare": 0.90,
        "periodFactor": 1.0,
        "uncertaintyPct": 15,
        "financeApproved": true,
        "primaryInGroup": true
      }
    }
  ],
  "cost_evidence": [
    {
      "scope": "azure-ai-foundry-prod",
      "amount": 4200.00,
      "currency": "USD",
      "period": "2026-10",
      "source": "Azure Cost Management",
      "evidence_link": "docs/evidence/acm-october.csv"
    }
  ]
}
```

## Nine-category monetization formulas & guardrails

For every claim, `nativeDelta = baseline.value - observation.value` when lower is better (`direction: "decrease"` or `target.value < baseline.value`) and `observation.value - baseline.value` otherwise. Baseline and observation units must match; `attributionShare` must be in `(0, 1]`.

1. **Revenue enablement:** `nativeDelta * volume * (conversionToRecognizedRate ?? 1.0) * unitValue * attributionShare * periodFactor`. If `pipelineOnly: true` without `conversionToRecognizedRate`, remains `unmonetized-native-only`.
2. **Cost avoidance:** `(counterfactualCost - observedCost) * attributionShare * periodFactor` or `nativeDelta * volume * unitCost * attributionShare * periodFactor`. Kept `stated-indicative` unless Finance approves it as booked avoidance.
3. **Capacity gained:** `nativeDelta * volume * redeployedShare * hourlyRate * attributionShare * periodFactor` (or `avoidedExpenseAmount * attributionShare * periodFactor`). Raw hours saved are never multiplied by `hourlyRate` without an explicit `redeployedShare` in `(0, 1]`.
4. **Labour augmentation:** `nativeDelta * volume * redeployedShare * hourlyRate * attributionShare * periodFactor`. Refuses monetization (`unmonetized-native-only`) when `qualityFloorMet: false` or when `hourlyRate` / `redeployedShare` is absent.
5. **Quality:** `nativeDelta * volume * costPerDefect * attributionShare * periodFactor` (verified defect, rework, refund, or claim cost per unit).
6. **Speed:** `nativeDelta * volume * valuePerTimeUnit * attributionShare * periodFactor` (verified economic rate per unit of cycle/lead time saved, such as SLA penalty avoided or margin pull-forward).
7. **Risk reduction:** `(baselineLikelihood - observedLikelihood) * impactAmount * attributionShare * periodFactor` or `nativeDelta * volume * costPerIncident * attributionShare * periodFactor`. Expected-exposure reduction stays `stated-indicative` unless Finance approves booking.
8. **New capacity:** `nativeDelta * volume * unitValue * attributionShare * periodFactor`. Refuses monetization when `demandVerified: false`.
9. **Engagement:** `nativeDelta * volume * downstreamConversionRate * downstreamUnitValue * attributionShare * periodFactor`. Without both `downstreamConversionRate` and `downstreamUnitValue`, stays `unmonetized-native-only` as a leading indicator.

## Double-count deduplication, FX, and delivery economics

* **Overlap deduplication (`overlap_group` / `overlapGroup`):** When multiple evidenced claims monetize the same underlying pool (for example, `speed` + `capacity gained` on the same ticket queue, or `capacity gained` + `labour augmentation` on the same team's hours), assign the same `overlap_group`. The engine retains the primary claim (`primaryInGroup: true`, then `finance-approved`, then largest gross value) and deducts `gross * overlapShare` (default `1.0`) from secondary claims in that group, recording every deduction in `overlapAdjustments[]`.
* **Currency isolation:** Amounts in another currency convert only when `fx_rates[<ISO>]` is explicitly supplied; otherwise they remain unmerged and surface in `gaps[]` and `missingValuationInputs[]`.
* **HVE Squad delivery value:** When `-SquadRoot` is supplied, AI spend (`consumption.md`) is reconciled into `costEvidence` (when `includeSquadAiSpendInCost` is `true`), counterfactual model-routing savings stay in `modeledCounterfactualValue`, and engineering time saved across review-accepted deliverables (`acceptedDeliverables`) is monetized only when `delivery_valuation` supplies explicit `hourlyRate`, `redeployedShare`, and hours saved per deliverable.
* **Net value, BCR, and ROI:** `netStatedValue = totalStatedEvidencedValue - totalEvidencedCost`; `benefitCostRatio = totalStatedEvidencedValue / totalEvidencedCost`; `statedRoiPct = (netStatedValue / totalEvidencedCost) * 100`.
