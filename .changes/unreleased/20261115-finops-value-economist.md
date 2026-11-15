---
bump: patch
type: Added
---

- **Add `Squad Value Economist` (`value-economist`) and deterministic FinOps monetary valuation engine.** Introduce the `value-economist` specialist role (`squad-value-economist.agent.md`, Deliverable Root `.copilot-tracking/finops/`), deterministic calculator `Measure-SquadBenefitValue.ps1` (`SquadBenefitValuation.psm1`), and companion references `business-value-measurement.md` and `value-valuation.md`. The engine and specialist preserve supplied benefit hypotheses across intake, planning, review, and ordinary handoffs, then interpret 9-category business/workload benefit evidence alongside read-only HVE Squad consumption ledgers to derive stated monetary representations separated into `finance-approved`, `stated-indicative`, `modeled-counterfactual`, and `unmonetized-native-only` buckets — enforcing redeployment, quality-floor, pipeline-conversion, leading-indicator, FX-isolation, and `overlap_group` double-count guardrails while keeping Finance/business sign-off at `confirm` tier and separate from execution/release gates.
