---
name: squad-model-benchmarks
description: "Pinned, versioned benchmark knowledge base for routing=ranked: source licensing, assignment-class evidence mapping, per-evaluation scores with provenance, and evidence-derived fit tiers."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-18"
---

# Squad Model Benchmarks Knowledge Base

**This knowledge base is a pinned, versioned snapshot updated by a scheduled workflow (`sync-model-benchmarks.yml`), never fetched live during a squad run.** Runtime model routing (`Resolve-SquadModelRoute.ps1` and `model-routing.md`) reads this file locally so dispatches remain deterministic, reproducible, and isolated from untrusted live web content.

* **Retrieved: 2026-10-18**
* **Content Digest: sha256:76573854d6c603001afaec118ba50f2922762ebe9faafc07d3e6fd7ad2be52a4**
* **Refresh Cadence: Daily check via `.github/workflows/sync-model-benchmarks.yml` (60-day heartbeat refresh; 90-day staleness threshold)**

## Source Terms and Licensing

Every source evaluated for `routing=ranked` was checked for methodology transparency, provenance separation (`independent` versus `self-reported`), and redistribution licensing before any score entered this repository:

| Source ID | Source name | Version | Retrieved | License | Redistribution | Status | URL |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `artificial-analysis` | Artificial Analysis Intelligence Benchmarking | `v4.3.2` | `2026-10-18` | Attribution required (CC-BY-4.0 via Epoch AI bundle; Free Data API ToS) | permitted-with-attribution | active | <https://artificialanalysis.ai/methodology/intelligence-benchmarking> |
| `epoch-ai` | Epoch AI Benchmarking Hub | `2026-10-18` | `2026-10-18` | CC-BY-4.0 | permitted-with-attribution | active | <https://epoch.ai/benchmarks/use-this-data> |
| `vendor-model-card` | Vendor Model Cards and GitHub Comparison Guide | `2026-10` | `2026-10-15` | Public vendor documentation | informational-only | self-reported-only | <https://docs.github.com/en/copilot/reference/ai-models/model-comparison> |
| `llm-stats` | LLM Stats (ZeroEval) | `2026-10` | `2026-10-18` | Commercial contract required for dataset redistribution | prohibited-on-free-tier | excluded | <https://llm-stats.com/developer> |
| `lmarena` | Arena (formerly LMArena) | `2026-10` | `2026-10-18` | CC-BY-4.0 / ToS | excluded-by-methodology | excluded | <https://arena.ai> |

### Required Attributions and Redistribution Notes

* **Epoch AI Benchmarking Hub (`epoch-ai`, CC BY 4.0)**: Data is licensed under the [Creative Commons Attribution 4.0 International License](https://creativecommons.org/licenses/by/4.0/). Attribution: *Epoch AI, "Capabilities & benchmarking". Published online at epoch.ai. Retrieved from `https://epoch.ai/benchmarks/use-this-data` (archive `https://epoch.ai/data/benchmark_data.zip`).*
* **Artificial Analysis (`artificial-analysis`, Intelligence Index v4.3.2)**: Independent evaluation methodology and sub-evaluation scores (`SciCode`, `CritPt`, `GDP.pdf`, `Terminal-Bench`, `HLE`, `APEX-Agents`, `FrontierCode`) are attributed to [Artificial Analysis](https://artificialanalysis.ai/methodology/intelligence-benchmarking) (`v4.3.2`: Agents 30%, General 30%, Coding 20%, Scientific Reasoning 20%). Public evaluation scores redistributed via Epoch AI's CC BY 4.0 archive and the Artificial Analysis Free Data API carry explicit source and version tags below.
* **LLM Stats (`llm-stats`, excluded from snapshot)**: ZeroEval / `llm-stats.com` developer terms state that redistributing the dataset requires a commercial contract license and that the aggregator blends vendor self-reported figures with verified ones. No `llm-stats.com` data is copied into this repository.
* **Arena (`lmarena`, excluded from snapshot)**: Crowd-sourced chat preference votes measure general conversational preference rather than task-specific coding, mathematical, or long-document capability, and are never used to rank squad roles.

## Assignment Class Evidence Mapping

`routing=ranked` ranks models for each assignment class using independently measured benchmark evidence first, before consulting the declared *Catalog: Assignment Fit* table in `model-catalog.md`. Self-reported vendor figures (`Provenance = self-reported`) are recorded for transparency only and **never** decide or boost a ranked pick.

| Assignment class | Primary evaluations | Secondary evaluations | Primary sources | Evidence rule |
| --- | --- | --- | --- | --- |
| `research` | `GDP.pdf`, `GPQA diamond`, `HLE`, `CritPt`, `DeepResearch Bench`, `SimpleQA Verified` | `APEX-Agents`, `Epoch Capabilities Index` | `artificial-analysis`, `epoch-ai` | Long-document synthesis, scientific/general reasoning, and factual accuracy (`fit 3..0`, then `Blended` cost) |
| `planning` | `FrontierMath-Tiers-1-3-v2`, `FrontierMath-Tier-4-v2`, `GPQA diamond`, `CritPt`, `HLE`, `GDP.pdf` | `APEX-Agents`, `ProofBench`, `OTIS Mock AIME`, `Epoch Capabilities Index` | `epoch-ai`, `artificial-analysis` | Multi-step architectural, mathematical, and scientific reasoning (`fit 3..0`, then `Blended` cost) |
| `implementation` | `SciCode`, `Terminal-Bench`, `SWE-Bench verified`, `FrontierCode`, `DeepSWE`, `APEX-Agents` | `FrontierSWE`, `OSWorld 2.0`, `Epoch Capabilities Index` | `artificial-analysis`, `epoch-ai` | Agentic software engineering and coding sub-evaluations; math-specific sources (`FrontierMath`, `ProofBench`) apply to quantitative analysis roles (`data-scientist`, `experimenter`, `performance`) rather than general implementation (`fit 3..0`, then `Blended` cost) |
| `review` | `SWE-Bench verified`, `Terminal-Bench`, `SciCode`, `GPQA diamond`, `CritPt`, `HLE` | `DeepSWE`, `FrontierCode`, `ProofBench`, `Epoch Capabilities Index` | `artificial-analysis`, `epoch-ai` | Code verification, defect detection, and adversarial scientific reasoning (`fit 3..0`, then `Blended` cost) |
| `council` | `GPQA diamond`, `FrontierMath-Tiers-1-3-v2`, `FrontierMath-Tier-4-v2`, `CritPt`, `HLE`, `GDP.pdf` | `APEX-Agents`, `SimpleQA Verified`, `Epoch Capabilities Index` | `artificial-analysis`, `epoch-ai` | Cross-domain architectural, security, cost, and governance judgment (`fit 3..0`, then `Blended` cost) |
| `intake` | `APEX-Agents`, `GDP.pdf`, `GPQA diamond`, `SimpleQA Verified` | `FrontierCode`, `SciCode`, `Epoch Capabilities Index` | `artificial-analysis`, `epoch-ai` | Cost and latency (`Blended`) among models clearing the requirements-judgment capability floor (`fit 3..0`, then `Blended` cost) |
| `bookkeeping` | `GPQA diamond`, `SciCode`, `APEX-Agents`, `FrontierCode` | `Epoch Capabilities Index` | `epoch-ai`, `artificial-analysis` | Cost and latency (`Blended`) first among models clearing the structured-output capability floor (`ECI >= 140` or `GPQA diamond >= 0.60`; `fit 3..0`, then `Blended` cost) |

### Design Decisions on Open Questions

1. **Epoch AI and Artificial Analysis coverage and licensing**: Confirmed as of `2026-10-18`. Epoch AI covers 35 of the 36 catalog models under `CC BY 4.0` (including `FrontierMath-Tiers-1-3-v2`, `FrontierMath-Tier-4-v2`, `GPQA diamond`, `SWE-Bench verified`, `OTIS Mock AIME`, and `SimpleQA Verified`), and bundles attributed Artificial Analysis sub-evaluations (`SciCode`, `CritPt`, `GDP.pdf`, `Terminal-Bench`, `HLE`, `APEX-Agents`, `FrontierCode`).
2. **Math-specific sources (`FrontierMath`, `ProofBench`, `OTIS Mock AIME`)**: Required for `planning`, `council`, and math-heavy analysis roles (`data-scientist`, `experimenter`, `performance`, `cost-manager`), where quantitative and formal reasoning drive task quality. Standard `implementation` roles (`developer`, `iac-author`, `deployer`, `release-engineer`, `technical-writer`, `presenter`, `prompt-engineer`) rank on Coding and Agents sub-evaluations (`SciCode`, `Terminal-Bench`, `SWE-Bench verified`, `FrontierCode`, `DeepSWE`, `APEX-Agents`) without requiring `FrontierMath`.
3. **Snapshot refresh cadence and staleness threshold**: `.github/workflows/sync-model-benchmarks.yml` runs daily at `06:30 UTC`, runs `scripts/Sync-ModelBenchmarks.ps1`, validates the snapshot with Pester, and opens or updates a reviewed pull request whenever benchmark scores or source versions change (or when the snapshot age reaches 60 days). At runtime, a snapshot older than **90 days** from its `Retrieved:` date (or one that fails to parse or lacks independent evidence for a candidate) falls back to `model-catalog.md`'s declared fit table and logs one warning.

## Evidence-Derived Assignment Fit

Each row below is derived exclusively from rows in *Benchmark Scores* with `Provenance = independent`. Models with no independent benchmark evaluations (`mai-code-1.1-flash`) are omitted from this table so `Resolve-SquadModelRoute.ps1` falls back to `model-catalog.md`'s declared fit table with a warning and never ranks on self-reported numbers.

| Catalog ID | research | planning | implementation | review | council | intake | bookkeeping | Composite | Sources | Key evaluations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `gpt-5.6-sol` | 3 | 3 | 2 | 3 | 2 | 2 | 0 | 0.620 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gpt-6.1-sol` | 2 | 2 | 3 | 2 | 2 | 2 | 0 | 0.716 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gpt-6-sol` | 1 | 2 | 3 | 3 | 2 | 2 | 0 | 0.664 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gpt-6-astra` | 3 | 3 | 2 | 2 | 3 | 1 | 0 | 0.706 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, HLE, CritPt, SimpleQA Verified, APEX-Agents |
| `gpt-5.5` | 2 | 3 | 1 | 3 | 3 | 2 | 0 | 0.605 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, DeepResearch Bench, SimpleQA Verified, APEX-Agents |
| `gpt-5.4` | 2 | 2 | 2 | 2 | 2 | 2 | 0 | 0.590 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GPQA diamond, HLE, CritPt, DeepResearch Bench, SimpleQA Verified, APEX-Agents |
| `gpt-5.6-terra` | 1 | 2 | 2 | 2 | 1 | 3 | 0 | 0.618 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gpt-5.3-codex` | 1 | 1 | 3 | 2 | 0 | 1 | 0 | 0.700 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | Epoch Capabilities Index, Terminal-Bench, SWE-Bench verified |
| `gpt-5.4-mini` | 1 | 0 | 2 | 1 | 0 | 1 | 2 | 0.415 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GPQA diamond, CritPt, DeepResearch Bench, SimpleQA Verified, Epoch Capabilities Index, FrontierMath-Tiers-1-3-v2 |
| `gpt-5-mini` | 1 | 0 | 1 | 1 | 0 | 1 | 2 | 0.402 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GPQA diamond, HLE, SimpleQA Verified, Epoch Capabilities Index, FrontierMath-Tiers-1-3-v2, FrontierMath-Tier-4-v2 |
| `gpt-5.4-nano` | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 0.373 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GPQA diamond, CritPt, SimpleQA Verified, Epoch Capabilities Index, FrontierMath-Tiers-1-3-v2, FrontierMath-Tier-4-v2 |
| `gpt-6-luna` | 0 | 0 | 1 | 0 | 0 | 1 | 2 | 0.556 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gpt-5.6-luna` | 0 | 0 | 1 | 0 | 0 | 1 | 2 | 0.565 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `claude-opus-5.5` | 3 | 2 | 2 | 2 | 2 | 1 | 0 | 0.717 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `claude-opus-5` | 3 | 3 | 2 | 3 | 3 | 2 | 0 | 0.638 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `claude-opus-4.8` | 2 | 3 | 2 | 3 | 3 | 2 | 0 | 0.551 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, DeepResearch Bench, SimpleQA Verified, APEX-Agents |
| `claude-opus-4.7` | 2 | 2 | 2 | 2 | 2 | 2 | 0 | 0.524 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, HLE, CritPt, SimpleQA Verified, APEX-Agents |
| `claude-opus-4.8-fast` | 2 | 2 | 2 | 2 | 2 | 1 | 0 | 0.551 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, DeepResearch Bench, SimpleQA Verified, APEX-Agents |
| `claude-fable-5.1` | 3 | 2 | 3 | 2 | 2 | 1 | 0 | 0.659 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, HLE, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `claude-fable-5` | 3 | 3 | 2 | 2 | 2 | 1 | 0 | 0.671 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `claude-sonnet-5.5` | 2 | 2 | 3 | 2 | 2 | 3 | 0 | 0.665 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, HLE, CritPt, SimpleQA Verified, APEX-Agents |
| `claude-sonnet-5` | 2 | 2 | 2 | 2 | 2 | 3 | 0 | 0.555 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index, FrontierMath-Tiers-1-3-v2 |
| `claude-sonnet-4.6` | 1 | 2 | 2 | 2 | 1 | 2 | 0 | 0.448 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, DeepResearch Bench, SimpleQA Verified, APEX-Agents |
| `claude-sonnet-4` | 1 | 1 | 1 | 1 | 1 | 1 | 0 | 0.353 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GPQA diamond, HLE, CritPt, DeepResearch Bench, Epoch Capabilities Index, OTIS Mock AIME |
| `claude-haiku-5.5` | 1 | 0 | 1 | 1 | 0 | 2 | 3 | 0.561 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GPQA diamond, HLE, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `claude-haiku-4.5` | 1 | 0 | 1 | 1 | 0 | 2 | 3 | 0.397 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GPQA diamond, DeepResearch Bench, SimpleQA Verified, Epoch Capabilities Index, OTIS Mock AIME, SciCode |
| `gemini-3.8-flash` | 1 | 1 | 1 | 1 | 0 | 1 | 2 | 0.531 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, HLE, CritPt, SimpleQA Verified, APEX-Agents |
| `gemini-3.7-flash` | 1 | 1 | 1 | 1 | 0 | 1 | 2 | 0.556 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gemini-3.6-flash` | 1 | 1 | 1 | 1 | 0 | 1 | 2 | 0.484 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gemini-3.5-flash` | 0 | 0 | 1 | 0 | 0 | 1 | 2 | 0.502 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `grok-4.7` | 1 | 2 | 2 | 2 | 1 | 2 | 0 | 0.487 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `grok-4.6` | 1 | 1 | 2 | 1 | 1 | 1 | 0 | 0.532 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `grok-4.5` | 1 | 1 | 2 | 1 | 1 | 1 | 0 | 0.493 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `kimi-k3` | 1 | 1 | 2 | 1 | 0 | 1 | 0 | 0.561 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `kimi-k2.7-code` | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0.444 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index, FrontierMath-Tiers-1-3-v2 |
| `hydrafusion-max` | 2 | 2 | 2 | 2 | 2 | 2 | 1 | 0.716 | artificial-analysis@v4.3.2, epoch-ai@2026-10-18 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |

## Benchmark Scores

Every score entry records its exact `Source ID`, `Source version`, `Retrieved` date (`yyyy-MM-dd`), and `Provenance` (`independent` or `self-reported`). Validation tests reject any row missing provenance or carrying an unrecognized provenance value.

| Catalog ID | Evaluation | Category | Score | Source ID | Source version | Retrieved | Provenance |
| --- | --- | --- | ---: | --- | --- | --- | --- |
| `gpt-5.6-sol` | GPQA diamond | `scientific-reasoning` | 0.913 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | FrontierMath-Tiers-1-3-v2 | `math` | 0.891 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | FrontierMath-Tier-4-v2 | `math` | 0.829 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | ProofBench | `math` | 0.830 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | FrontierCode | `coding` | 0.475 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | DeepSWE | `coding` | 0.727 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | FrontierSWE | `agents` | 0.322 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | APEX-Agents | `agents` | 0.514 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | OSWorld 2.0 | `agents` | 0.273 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | SimpleQA Verified | `general-long-doc` | 0.697 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | SciCode | `coding` | 0.578 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | CritPt | `scientific-reasoning` | 0.323 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | GDP.pdf | `general-long-doc` | 0.307 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-sol` | Epoch Capabilities Index | `general-long-doc` | 0.617 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6.1-sol` | GPQA diamond | `scientific-reasoning` | 0.939 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6.1-sol` | FrontierMath-Tiers-1-3-v2 | `math` | 0.937 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6.1-sol` | FrontierMath-Tier-4-v2 | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6.1-sol` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6.1-sol` | ProofBench | `math` | 0.990 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6.1-sol` | FrontierCode | `coding` | 0.502 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6.1-sol` | APEX-Agents | `agents` | 0.600 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6.1-sol` | SimpleQA Verified | `general-long-doc` | 0.739 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6.1-sol` | SciCode | `coding` | 0.558 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6.1-sol` | CritPt | `scientific-reasoning` | 0.317 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6.1-sol` | GDP.pdf | `general-long-doc` | 0.350 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6.1-sol` | Epoch Capabilities Index | `general-long-doc` | 0.663 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-sol` | GPQA diamond | `scientific-reasoning` | 0.924 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-sol` | FrontierMath-Tiers-1-3-v2 | `math` | 0.898 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-sol` | FrontierMath-Tier-4-v2 | `math` | 0.900 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-sol` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-sol` | ProofBench | `math` | 0.830 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-sol` | FrontierCode | `coding` | 0.493 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-sol` | APEX-Agents | `agents` | 0.543 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-sol` | SimpleQA Verified | `general-long-doc` | 0.607 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-sol` | SciCode | `coding` | 0.576 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-sol` | CritPt | `scientific-reasoning` | 0.309 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-sol` | GDP.pdf | `general-long-doc` | 0.264 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-sol` | Epoch Capabilities Index | `general-long-doc` | 0.626 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-astra` | GPQA diamond | `scientific-reasoning` | 0.944 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-astra` | FrontierMath-Tiers-1-3-v2 | `math` | 0.937 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-astra` | FrontierMath-Tier-4-v2 | `math` | 0.976 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-astra` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-astra` | ProofBench | `math` | 0.990 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-astra` | FrontierCode | `coding` | 0.533 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-astra` | DeepSWE | `coding` | 0.741 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-astra` | FrontierSWE | `agents` | 0.655 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-astra` | APEX-Agents | `agents` | 0.647 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-astra` | HLE | `scientific-reasoning` | 0.525 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-astra` | SimpleQA Verified | `general-long-doc` | 0.756 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-astra` | SciCode | `coding` | 0.565 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-astra` | CritPt | `scientific-reasoning` | 0.317 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-astra` | GDP.pdf | `general-long-doc` | 0.342 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-astra` | Epoch Capabilities Index | `general-long-doc` | 0.664 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.5` | GPQA diamond | `scientific-reasoning` | 0.920 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.853 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.5` | FrontierMath-Tier-4-v2 | `math` | 0.725 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.5` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.5` | ProofBench | `math` | 0.500 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.5` | SWE-Bench verified | `coding` | 0.806 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.5` | Terminal-Bench | `coding` | 0.847 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.5` | FrontierCode | `coding` | 0.430 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.5` | DeepSWE | `coding` | 0.670 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.5` | APEX-Agents | `agents` | 0.551 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.5` | OSWorld 2.0 | `agents` | 0.130 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.5` | SimpleQA Verified | `general-long-doc` | 0.630 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.5` | DeepResearch Bench | `general-long-doc` | 0.540 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.5` | SciCode | `coding` | 0.561 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.5` | CritPt | `scientific-reasoning` | 0.271 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.5` | GDP.pdf | `general-long-doc` | 0.260 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.5` | Epoch Capabilities Index | `general-long-doc` | 0.589 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4` | GPQA diamond | `scientific-reasoning` | 0.911 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4` | FrontierMath-Tiers-1-3-v2 | `math` | 0.786 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4` | FrontierMath-Tier-4-v2 | `math` | 0.490 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4` | OTIS Mock AIME | `math` | 0.978 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4` | ProofBench | `math` | 0.560 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4` | SWE-Bench verified | `coding` | 0.769 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4` | Terminal-Bench | `coding` | 0.818 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.4` | DeepSWE | `coding` | 0.518 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4` | APEX-Agents | `agents` | 0.524 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.4` | HLE | `scientific-reasoning` | 0.330 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.4` | SimpleQA Verified | `general-long-doc` | 0.451 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4` | DeepResearch Bench | `general-long-doc` | 0.351 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4` | SciCode | `coding` | 0.566 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.4` | CritPt | `scientific-reasoning` | 0.234 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.4` | Epoch Capabilities Index | `general-long-doc` | 0.567 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | GPQA diamond | `scientific-reasoning` | 0.911 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | FrontierMath-Tiers-1-3-v2 | `math` | 0.860 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | FrontierMath-Tier-4-v2 | `math` | 0.707 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | OTIS Mock AIME | `math` | 0.997 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | ProofBench | `math` | 0.740 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | FrontierCode | `coding` | 0.413 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | DeepSWE | `coding` | 0.696 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | APEX-Agents | `agents` | 0.582 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | SimpleQA Verified | `general-long-doc` | 0.432 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | SciCode | `coding` | 0.550 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | CritPt | `scientific-reasoning` | 0.300 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | GDP.pdf | `general-long-doc` | 0.247 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-terra` | Epoch Capabilities Index | `general-long-doc` | 0.594 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.3-codex` | SWE-Bench verified | `coding` | 0.748 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.3-codex` | Terminal-Bench | `coding` | 0.784 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.3-codex` | Epoch Capabilities Index | `general-long-doc` | 0.568 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-mini` | GPQA diamond | `scientific-reasoning` | 0.825 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-mini` | FrontierMath-Tiers-1-3-v2 | `math` | 0.512 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-mini` | FrontierMath-Tier-4-v2 | `math` | 0.098 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-mini` | OTIS Mock AIME | `math` | 0.889 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-mini` | ProofBench | `math` | 0.210 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-mini` | FrontierCode | `coding` | 0.270 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.4-mini` | SimpleQA Verified | `general-long-doc` | 0.294 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-mini` | DeepResearch Bench | `general-long-doc` | 0.363 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-mini` | SciCode | `coding` | 0.521 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.4-mini` | CritPt | `scientific-reasoning` | 0.100 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.4-mini` | Epoch Capabilities Index | `general-long-doc` | 0.488 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5-mini` | GPQA diamond | `scientific-reasoning` | 0.667 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5-mini` | FrontierMath-Tiers-1-3-v2 | `math` | 0.467 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5-mini` | FrontierMath-Tier-4-v2 | `math` | 0.122 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5-mini` | OTIS Mock AIME | `math` | 0.867 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5-mini` | ProofBench | `math` | 0.090 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5-mini` | SWE-Bench verified | `coding` | 0.647 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5-mini` | Terminal-Bench | `coding` | 0.348 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5-mini` | HLE | `scientific-reasoning` | 0.154 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5-mini` | SimpleQA Verified | `general-long-doc` | 0.216 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5-mini` | SciCode | `coding` | 0.392 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5-mini` | Epoch Capabilities Index | `general-long-doc` | 0.454 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-nano` | GPQA diamond | `scientific-reasoning` | 0.713 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-nano` | FrontierMath-Tiers-1-3-v2 | `math` | 0.449 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-nano` | FrontierMath-Tier-4-v2 | `math` | 0.122 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-nano` | OTIS Mock AIME | `math` | 0.878 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-nano` | ProofBench | `math` | 0.050 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-nano` | SimpleQA Verified | `general-long-doc` | 0.117 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.4-nano` | SciCode | `coding` | 0.472 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.4-nano` | CritPt | `scientific-reasoning` | 0.093 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.4-nano` | Epoch Capabilities Index | `general-long-doc` | 0.461 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-luna` | GPQA diamond | `scientific-reasoning` | 0.873 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-luna` | FrontierMath-Tiers-1-3-v2 | `math` | 0.789 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-luna` | FrontierMath-Tier-4-v2 | `math` | 0.561 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-luna` | OTIS Mock AIME | `math` | 0.989 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-luna` | ProofBench | `math` | 0.640 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-luna` | FrontierCode | `coding` | 0.424 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-luna` | APEX-Agents | `agents` | 0.443 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-luna` | SimpleQA Verified | `general-long-doc` | 0.414 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-6-luna` | SciCode | `coding` | 0.546 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-luna` | CritPt | `scientific-reasoning` | 0.194 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-luna` | GDP.pdf | `general-long-doc` | 0.230 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-6-luna` | Epoch Capabilities Index | `general-long-doc` | 0.563 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | GPQA diamond | `scientific-reasoning` | 0.888 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | FrontierMath-Tiers-1-3-v2 | `math` | 0.821 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | FrontierMath-Tier-4-v2 | `math` | 0.610 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | OTIS Mock AIME | `math` | 0.983 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | ProofBench | `math` | 0.600 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | FrontierCode | `coding` | 0.398 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | DeepSWE | `coding` | 0.672 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | APEX-Agents | `agents` | 0.430 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | SimpleQA Verified | `general-long-doc` | 0.410 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | SciCode | `coding` | 0.536 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | CritPt | `scientific-reasoning` | 0.206 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | GDP.pdf | `general-long-doc` | 0.227 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gpt-5.6-luna` | Epoch Capabilities Index | `general-long-doc` | 0.563 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | GPQA diamond | `scientific-reasoning` | 0.875 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.912 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | FrontierMath-Tier-4-v2 | `math` | 0.950 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | ProofBench | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | FrontierCode | `coding` | 0.546 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | FrontierSWE | `agents` | 0.623 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | APEX-Agents | `agents` | 0.735 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | SimpleQA Verified | `general-long-doc` | 0.722 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | SciCode | `coding` | 0.669 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | CritPt | `scientific-reasoning` | 0.317 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | GDP.pdf | `general-long-doc` | 0.306 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-5.5` | Epoch Capabilities Index | `general-long-doc` | 0.668 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5` | GPQA diamond | `scientific-reasoning` | 0.918 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.856 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5` | FrontierMath-Tier-4-v2 | `math` | 0.732 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5` | OTIS Mock AIME | `math` | 0.989 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5` | ProofBench | `math` | 0.990 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5` | FrontierCode | `coding` | 0.534 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-5` | DeepSWE | `coding` | 0.736 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5` | FrontierSWE | `agents` | 0.520 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5` | APEX-Agents | `agents` | 0.658 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-5` | OSWorld 2.0 | `agents` | 0.314 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5` | SimpleQA Verified | `general-long-doc` | 0.599 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-5` | SciCode | `coding` | 0.564 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-5` | CritPt | `scientific-reasoning` | 0.291 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-5` | GDP.pdf | `general-long-doc` | 0.240 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-5` | Epoch Capabilities Index | `general-long-doc` | 0.626 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | GPQA diamond | `scientific-reasoning` | 0.880 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | FrontierMath-Tiers-1-3-v2 | `math` | 0.800 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | FrontierMath-Tier-4-v2 | `math` | 0.561 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | OTIS Mock AIME | `math` | 0.983 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | ProofBench | `math` | 0.690 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | FrontierCode | `coding` | 0.465 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | DeepSWE | `coding` | 0.590 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | APEX-Agents | `agents` | 0.489 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | OSWorld 2.0 | `agents` | 0.206 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | SimpleQA Verified | `general-long-doc` | 0.530 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | DeepResearch Bench | `general-long-doc` | 0.502 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | SciCode | `coding` | 0.535 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | CritPt | `scientific-reasoning` | 0.209 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | GDP.pdf | `general-long-doc` | 0.240 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.8` | Epoch Capabilities Index | `general-long-doc` | 0.583 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | GPQA diamond | `scientific-reasoning` | 0.869 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | FrontierMath-Tiers-1-3-v2 | `math` | 0.702 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | FrontierMath-Tier-4-v2 | `math` | 0.317 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | OTIS Mock AIME | `math` | 0.978 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | ProofBench | `math` | 0.540 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | SWE-Bench verified | `coding` | 0.835 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | Terminal-Bench | `coding` | 0.802 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | FrontierCode | `coding` | 0.385 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | APEX-Agents | `agents` | 0.492 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | OSWorld 2.0 | `agents` | 0.182 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | HLE | `scientific-reasoning` | 0.330 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | SimpleQA Verified | `general-long-doc` | 0.517 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | SciCode | `coding` | 0.545 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | CritPt | `scientific-reasoning` | 0.120 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | GDP.pdf | `general-long-doc` | 0.210 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.7` | Epoch Capabilities Index | `general-long-doc` | 0.563 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | GPQA diamond | `scientific-reasoning` | 0.880 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | FrontierMath-Tiers-1-3-v2 | `math` | 0.800 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | FrontierMath-Tier-4-v2 | `math` | 0.561 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | OTIS Mock AIME | `math` | 0.983 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | ProofBench | `math` | 0.690 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | FrontierCode | `coding` | 0.465 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | DeepSWE | `coding` | 0.590 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | APEX-Agents | `agents` | 0.489 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | OSWorld 2.0 | `agents` | 0.206 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | SimpleQA Verified | `general-long-doc` | 0.530 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | DeepResearch Bench | `general-long-doc` | 0.502 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | SciCode | `coding` | 0.535 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | CritPt | `scientific-reasoning` | 0.209 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | GDP.pdf | `general-long-doc` | 0.240 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-opus-4.8-fast` | Epoch Capabilities Index | `general-long-doc` | 0.583 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | FrontierMath-Tiers-1-3-v2 | `math` | 0.902 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | FrontierMath-Tier-4-v2 | `math` | 0.878 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | ProofBench | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | FrontierCode | `coding` | 0.509 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | FrontierSWE | `agents` | 0.563 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | APEX-Agents | `agents` | 0.686 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | HLE | `scientific-reasoning` | 0.438 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | SimpleQA Verified | `general-long-doc` | 0.708 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | SciCode | `coding` | 0.631 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | CritPt | `scientific-reasoning` | 0.311 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | GDP.pdf | `general-long-doc` | 0.296 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-fable-5.1` | Epoch Capabilities Index | `general-long-doc` | 0.647 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5` | GPQA diamond | `scientific-reasoning` | 0.811 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.870 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5` | FrontierMath-Tier-4-v2 | `math` | 0.902 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5` | ProofBench | `math` | 0.950 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5` | FrontierCode | `coding` | 0.535 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-fable-5` | DeepSWE | `coding` | 0.699 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5` | FrontierSWE | `agents` | 0.470 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5` | APEX-Agents | `agents` | 0.636 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-fable-5` | SimpleQA Verified | `general-long-doc` | 0.707 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-fable-5` | SciCode | `coding` | 0.610 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-fable-5` | CritPt | `scientific-reasoning` | 0.286 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-fable-5` | GDP.pdf | `general-long-doc` | 0.300 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-fable-5` | Epoch Capabilities Index | `general-long-doc` | 0.621 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | GPQA diamond | `scientific-reasoning` | 0.941 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.888 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | FrontierMath-Tier-4-v2 | `math` | 0.805 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | ProofBench | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | FrontierCode | `coding` | 0.521 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | FrontierSWE | `agents` | 0.619 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | APEX-Agents | `agents` | 0.755 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | HLE | `scientific-reasoning` | 0.434 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | SimpleQA Verified | `general-long-doc` | 0.465 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | SciCode | `coding` | 0.610 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | CritPt | `scientific-reasoning` | 0.314 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | GDP.pdf | `general-long-doc` | 0.314 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-5.5` | Epoch Capabilities Index | `general-long-doc` | 0.644 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5` | GPQA diamond | `scientific-reasoning` | 0.874 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.656 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5` | FrontierMath-Tier-4-v2 | `math` | 0.293 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5` | OTIS Mock AIME | `math` | 0.947 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5` | ProofBench | `math` | 0.770 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5` | FrontierCode | `coding` | 0.427 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-5` | DeepSWE | `coding` | 0.538 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5` | APEX-Agents | `agents` | 0.545 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-5` | SimpleQA Verified | `general-long-doc` | 0.337 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-5` | SciCode | `coding` | 0.543 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-5` | CritPt | `scientific-reasoning` | 0.169 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-5` | Epoch Capabilities Index | `general-long-doc` | 0.564 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | GPQA diamond | `scientific-reasoning` | 0.832 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | FrontierMath-v1 | `math` | 0.568 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | OTIS Mock AIME | `math` | 0.858 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | ProofBench | `math` | 0.450 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | SWE-Bench verified | `coding` | 0.752 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | Terminal-Bench | `coding` | 0.534 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | FrontierCode | `coding` | 0.243 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | DeepSWE | `coding` | 0.299 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | APEX-Agents | `agents` | 0.430 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | OSWorld 2.0 | `agents` | 0.093 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | SimpleQA Verified | `general-long-doc` | 0.355 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | DeepResearch Bench | `general-long-doc` | 0.549 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | SciCode | `coding` | 0.468 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | CritPt | `scientific-reasoning` | 0.031 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | GDP.pdf | `general-long-doc` | 0.180 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-4.6` | Epoch Capabilities Index | `general-long-doc` | 0.524 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4` | GPQA diamond | `scientific-reasoning` | 0.723 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4` | FrontierMath-v1 | `math` | 0.073 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4` | OTIS Mock AIME | `math` | 0.711 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4` | HLE | `scientific-reasoning` | 0.031 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-4` | DeepResearch Bench | `general-long-doc` | 0.466 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-sonnet-4` | SciCode | `coding` | 0.400 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-4` | CritPt | `scientific-reasoning` | 0.003 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-sonnet-4` | Epoch Capabilities Index | `general-long-doc` | 0.417 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | GPQA diamond | `scientific-reasoning` | 0.862 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.751 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | FrontierMath-Tier-4-v2 | `math` | 0.463 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | OTIS Mock AIME | `math` | 0.989 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | ProofBench | `math` | 0.890 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | FrontierCode | `coding` | 0.464 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | FrontierSWE | `agents` | 0.438 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | APEX-Agents | `agents` | 0.561 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | HLE | `scientific-reasoning` | 0.266 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | SimpleQA Verified | `general-long-doc` | 0.238 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | SciCode | `coding` | 0.550 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | CritPt | `scientific-reasoning` | 0.226 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-haiku-5.5` | Epoch Capabilities Index | `general-long-doc` | 0.590 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-4.5` | GPQA diamond | `scientific-reasoning` | 0.616 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-4.5` | FrontierMath-v1 | `math` | 0.104 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-4.5` | OTIS Mock AIME | `math` | 0.666 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-4.5` | Terminal-Bench | `coding` | 0.355 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-haiku-4.5` | SimpleQA Verified | `general-long-doc` | 0.132 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-4.5` | DeepResearch Bench | `general-long-doc` | 0.455 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `claude-haiku-4.5` | SciCode | `coding` | 0.422 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `claude-haiku-4.5` | Epoch Capabilities Index | `general-long-doc` | 0.424 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | GPQA diamond | `scientific-reasoning` | 0.939 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | FrontierMath-Tiers-1-3-v2 | `math` | 0.684 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | FrontierMath-Tier-4-v2 | `math` | 0.220 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | OTIS Mock AIME | `math` | 0.989 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | ProofBench | `math` | 0.480 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | FrontierCode | `coding` | 0.412 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | DeepSWE | `coding` | 0.738 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | FrontierSWE | `agents` | 0.196 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | APEX-Agents | `agents` | 0.643 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | HLE | `scientific-reasoning` | 0.417 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | SimpleQA Verified | `general-long-doc` | 0.697 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | SciCode | `coding` | 0.566 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | CritPt | `scientific-reasoning` | 0.183 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | GDP.pdf | `general-long-doc` | 0.234 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.8-flash` | Epoch Capabilities Index | `general-long-doc` | 0.572 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | GPQA diamond | `scientific-reasoning` | 0.931 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | FrontierMath-Tiers-1-3-v2 | `math` | 0.716 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | FrontierMath-Tier-4-v2 | `math` | 0.366 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | OTIS Mock AIME | `math` | 0.972 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | ProofBench | `math` | 0.580 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | FrontierCode | `coding` | 0.436 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | DeepSWE | `coding` | 0.655 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | FrontierSWE | `agents` | 0.203 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | APEX-Agents | `agents` | 0.678 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | SimpleQA Verified | `general-long-doc` | 0.692 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | SciCode | `coding` | 0.598 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | CritPt | `scientific-reasoning` | 0.143 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | GDP.pdf | `general-long-doc` | 0.238 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.7-flash` | Epoch Capabilities Index | `general-long-doc` | 0.572 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | GPQA diamond | `scientific-reasoning` | 0.922 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | FrontierMath-Tiers-1-3-v2 | `math` | 0.589 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | FrontierMath-Tier-4-v2 | `math` | 0.220 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | OTIS Mock AIME | `math` | 0.942 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | ProofBench | `math` | 0.360 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | FrontierCode | `coding` | 0.344 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | DeepSWE | `coding` | 0.467 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | APEX-Agents | `agents` | 0.469 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | SimpleQA Verified | `general-long-doc` | 0.662 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | SciCode | `coding` | 0.534 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | CritPt | `scientific-reasoning` | 0.106 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | GDP.pdf | `general-long-doc` | 0.140 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.6-flash` | Epoch Capabilities Index | `general-long-doc` | 0.542 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | GPQA diamond | `scientific-reasoning` | 0.904 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | FrontierMath-Tiers-1-3-v2 | `math` | 0.628 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | FrontierMath-Tier-4-v2 | `math` | 0.268 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | OTIS Mock AIME | `math` | 0.956 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | ProofBench | `math` | 0.310 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | SWE-Bench verified | `coding` | 0.793 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | DeepSWE | `coding` | 0.374 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | APEX-Agents | `agents` | 0.275 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | SimpleQA Verified | `general-long-doc` | 0.662 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | SciCode | `coding` | 0.539 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | CritPt | `scientific-reasoning` | 0.131 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | GDP.pdf | `general-long-doc` | 0.140 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `gemini-3.5-flash` | Epoch Capabilities Index | `general-long-doc` | 0.544 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.7` | GPQA diamond | `scientific-reasoning` | 0.903 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.7` | FrontierMath-Tiers-1-3-v2 | `math` | 0.530 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.7` | FrontierMath-Tier-4-v2 | `math` | 0.171 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.7` | OTIS Mock AIME | `math` | 0.981 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.7` | ProofBench | `math` | 0.340 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.7` | FrontierCode | `coding` | 0.476 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.7` | FrontierSWE | `agents` | 0.295 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.7` | APEX-Agents | `agents` | 0.546 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.7` | SimpleQA Verified | `general-long-doc` | 0.560 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.7` | SciCode | `coding` | 0.578 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.7` | CritPt | `scientific-reasoning` | 0.180 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.7` | GDP.pdf | `general-long-doc` | 0.228 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.7` | Epoch Capabilities Index | `general-long-doc` | 0.544 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.6` | GPQA diamond | `scientific-reasoning` | 0.920 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.6` | FrontierMath-Tiers-1-3-v2 | `math` | 0.660 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.6` | FrontierMath-Tier-4-v2 | `math` | 0.317 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.6` | OTIS Mock AIME | `math` | 0.992 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.6` | ProofBench | `math` | 0.510 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.6` | FrontierCode | `coding` | 0.480 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.6` | DeepSWE | `coding` | 0.675 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.6` | FrontierSWE | `agents` | 0.253 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.6` | APEX-Agents | `agents` | 0.653 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.6` | SimpleQA Verified | `general-long-doc` | 0.493 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.6` | SciCode | `coding` | 0.565 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.6` | CritPt | `scientific-reasoning` | 0.197 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.6` | GDP.pdf | `general-long-doc` | 0.172 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.6` | Epoch Capabilities Index | `general-long-doc` | 0.563 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.5` | GPQA diamond | `scientific-reasoning` | 0.912 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.572 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.5` | FrontierMath-Tier-4-v2 | `math` | 0.244 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.5` | OTIS Mock AIME | `math` | 0.978 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.5` | ProofBench | `math` | 0.310 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.5` | FrontierCode | `coding` | 0.424 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.5` | DeepSWE | `coding` | 0.538 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.5` | APEX-Agents | `agents` | 0.562 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.5` | SimpleQA Verified | `general-long-doc` | 0.483 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `grok-4.5` | SciCode | `coding` | 0.550 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.5` | CritPt | `scientific-reasoning` | 0.154 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.5` | GDP.pdf | `general-long-doc` | 0.140 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `grok-4.5` | Epoch Capabilities Index | `general-long-doc` | 0.539 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k3` | GPQA diamond | `scientific-reasoning` | 0.908 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k3` | FrontierMath-Tiers-1-3-v2 | `math` | 0.722 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k3` | FrontierMath-Tier-4-v2 | `math` | 0.390 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k3` | OTIS Mock AIME | `math` | 0.972 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k3` | ProofBench | `math` | 0.870 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k3` | FrontierCode | `coding` | 0.442 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `kimi-k3` | DeepSWE | `coding` | 0.685 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k3` | FrontierSWE | `agents` | 0.259 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k3` | APEX-Agents | `agents` | 0.506 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `kimi-k3` | SimpleQA Verified | `general-long-doc` | 0.506 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k3` | SciCode | `coding` | 0.595 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `kimi-k3` | CritPt | `scientific-reasoning` | 0.234 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `kimi-k3` | GDP.pdf | `general-long-doc` | 0.190 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `kimi-k3` | Epoch Capabilities Index | `general-long-doc` | 0.574 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k2.7-code` | GPQA diamond | `scientific-reasoning` | 0.838 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k2.7-code` | FrontierMath-Tiers-1-3-v2 | `math` | 0.540 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k2.7-code` | FrontierMath-Tier-4-v2 | `math` | 0.122 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k2.7-code` | OTIS Mock AIME | `math` | 0.956 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k2.7-code` | FrontierCode | `coding` | 0.301 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `kimi-k2.7-code` | DeepSWE | `coding` | 0.305 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k2.7-code` | APEX-Agents | `agents` | 0.376 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `kimi-k2.7-code` | SimpleQA Verified | `general-long-doc` | 0.365 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `kimi-k2.7-code` | SciCode | `coding` | 0.478 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `kimi-k2.7-code` | CritPt | `scientific-reasoning` | 0.100 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `kimi-k2.7-code` | Epoch Capabilities Index | `general-long-doc` | 0.499 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `hydrafusion-max` | GPQA diamond | `scientific-reasoning` | 0.939 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `hydrafusion-max` | FrontierMath-Tiers-1-3-v2 | `math` | 0.937 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `hydrafusion-max` | FrontierMath-Tier-4-v2 | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `hydrafusion-max` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `hydrafusion-max` | ProofBench | `math` | 0.990 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `hydrafusion-max` | FrontierCode | `coding` | 0.502 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `hydrafusion-max` | APEX-Agents | `agents` | 0.600 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `hydrafusion-max` | SimpleQA Verified | `general-long-doc` | 0.739 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `hydrafusion-max` | SciCode | `coding` | 0.558 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `hydrafusion-max` | CritPt | `scientific-reasoning` | 0.317 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `hydrafusion-max` | GDP.pdf | `general-long-doc` | 0.350 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |
| `hydrafusion-max` | Epoch Capabilities Index | `general-long-doc` | 0.663 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |
| `mai-code-1.1-flash` | Vendor Task-Area Declaration | `coding` | 0.500 | `vendor-model-card` | `2026-10` | `2026-10-15` | `self-reported` |
