---
name: squad-model-benchmarks
description: "Pinned, versioned benchmark knowledge base for routing=ranked: source licensing, assignment-class evidence mapping, per-evaluation scores with provenance, and evidence-derived fit tiers."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-19"
---

# Squad Model Benchmarks Knowledge Base

**This knowledge base is a pinned, versioned snapshot updated by a scheduled workflow (`sync-model-benchmarks.yml`), never fetched live during a squad run.** Runtime model routing (`Resolve-SquadModelRoute.ps1` and `model-routing.md`) reads this file locally so dispatches remain deterministic, reproducible, and isolated from untrusted live web content.

* **Retrieved: 2026-10-19**
* **Content Digest: sha256:53b4d3b8ec7be11fc50b33b3c4fc152d79fdb5c488ee249791d8f3884932cdeb**
* **Refresh Cadence: Daily check via `.github/workflows/sync-model-benchmarks.yml` (60-day heartbeat refresh; 90-day staleness threshold)**

## Source Terms and Licensing

Every source evaluated for `routing=ranked` was checked for methodology transparency, provenance separation (`independent` versus `self-reported`), and redistribution licensing before any score entered this repository:

| Source ID | Source name | Version | Retrieved | License | Redistribution | Status | URL |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `artificial-analysis` | Artificial Analysis | `v4.3.2` | `2026-10-19` | Attribution required (Free Data API ToS / CC-BY-4.0 via Epoch AI bundle) | permitted-with-attribution | active | <https://artificialanalysis.ai/evaluations/scicode> |
| `cognition-frontiercode` | Cognition FrontierCode | `2026-06-08` | `2026-10-19` | CC-BY-4.0 via Epoch AI bundle | permitted-with-attribution | active | <https://cognition.com/frontiercode> |
| `deepswe-datacurve-ai` | deepswe.datacurve.ai | `2026-05-26` | `2026-10-19` | CC-BY-4.0 via Epoch AI bundle | permitted-with-attribution | active | <https://deepswe.datacurve.ai/> |
| `epoch-ai` | Epoch AI Benchmarking Hub | `2026-10-19` | `2026-10-19` | CC-BY-4.0 | permitted-with-attribution | active | <https://epoch.ai/benchmarks/use-this-data> |
| `evals-futuresearch-ai` | evals.futuresearch.ai | `2025-06-13` | `2026-10-19` | CC-BY-4.0 via Epoch AI bundle | permitted-with-attribution | active | <https://evals.futuresearch.ai/#drb> |
| `frontierswe-com` | frontierswe.com | `2026-09-02` | `2026-10-19` | CC-BY-4.0 via Epoch AI bundle | permitted-with-attribution | active | <https://www.frontierswe.com/> |
| `osworld-v2-xlang-ai` | osworld-v2.xlang.ai | `2026-06-26` | `2026-10-19` | CC-BY-4.0 via Epoch AI bundle | permitted-with-attribution | active | <https://osworld-v2.xlang.ai/> |
| `surge-gdp-pdf` | Surge AI GDP.pdf | `2026-06-06, 2026-10-19` | `2026-10-19` | CC-BY-4.0 via Epoch AI bundle | permitted-with-attribution | active | <https://surgehq.ai/benchmarks/gdp-pdf> |
| `terminal-bench` | Terminal-Bench | `2025-05-19` | `2026-10-19` | CC-BY-4.0 via Epoch AI bundle | permitted-with-attribution | active | <https://www.tbench.ai/leaderboard/terminal-bench/2.0> |
| `vals-ai` | vals.ai | `2026-01-30` | `2026-10-19` | CC-BY-4.0 via Epoch AI bundle | permitted-with-attribution | active | <https://www.vals.ai/benchmarks/proof_bench> |
| `vendor-model-card` | Vendor Model Cards and GitHub Comparison Guide | `2026-10` | `2026-10-19` | Public vendor documentation | informational-only | self-reported-only | <https://docs.github.com/en/copilot/reference/ai-models/model-comparison> |
| `llm-stats` | LLM Stats (ZeroEval) | `2026-10` | `2026-10-19` | Commercial contract required for dataset redistribution | prohibited-on-free-tier | excluded | <https://llm-stats.com/developer> |
| `lmarena` | Arena (formerly LMArena) | `2026-10` | `2026-10-19` | CC-BY-4.0 / ToS | excluded-by-methodology | excluded | <https://arena.ai> |

### Required Attributions and Redistribution Notes

* **Epoch AI Benchmarking Hub (`epoch-ai`, CC BY 4.0)**: Data is licensed under the [Creative Commons Attribution 4.0 International License](https://creativecommons.org/licenses/by/4.0/). Attribution: *Epoch AI, "Capabilities & benchmarking". Published online at epoch.ai. Retrieved from `https://epoch.ai/benchmarks/use-this-data` (archive `https://epoch.ai/data/benchmark_data.zip`).*
* **Artificial Analysis (`artificial-analysis`, Intelligence Index v4.3.2)**: Artificial Analysis API indices plus its `SciCode` and `CritPt` evaluations are attributed to [Artificial Analysis](https://artificialanalysis.ai/methodology/intelligence-benchmarking). Scores published by Cognition, Terminal-Bench, Surge AI, or another upstream publisher retain that publisher's source ID and version instead of being relabeled as Artificial Analysis.
* **LLM Stats (`llm-stats`, excluded from snapshot)**: ZeroEval / `llm-stats.com` developer terms state that redistributing the dataset requires a commercial contract license and that the aggregator blends vendor self-reported figures with verified ones. No `llm-stats.com` data is copied into this repository.
* **Arena (`lmarena`, excluded from snapshot)**: Crowd-sourced chat preference votes measure general conversational preference rather than task-specific coding, mathematical, or long-document capability, and are never used to rank squad roles.

## Assignment Class Evidence Mapping

`routing=ranked` ranks models for each assignment class using independently measured benchmark evidence first, before consulting the declared *Catalog: Assignment Fit* table in `model-catalog.md`. Self-reported vendor figures (`Provenance = self-reported`) are recorded for transparency only and **never** decide or boost a ranked pick.

| Assignment class | Primary evaluations | Secondary evaluations | Primary sources | Evidence rule |
| --- | --- | --- | --- | --- |
| `research` | `Artificial Analysis Intelligence Index`, `GDP.pdf`, `GPQA diamond`, `HLE`, `CritPt`, `DeepResearch Bench`, `SimpleQA Verified` | `Artificial Analysis Agentic Index`, `APEX-Agents`, `Epoch Capabilities Index` | source-specific rows from the pinned snapshot | Long-document synthesis, scientific/general reasoning, and factual accuracy (`fit 3..0`, then `Blended` cost) |
| `planning` | `FrontierMath-Tiers-1-3-v2`, `FrontierMath-Tier-4-v2`, `GPQA diamond`, `CritPt`, `HLE`, `GDP.pdf`, `Artificial Analysis Intelligence Index` | `Artificial Analysis Agentic Index`, `APEX-Agents`, `ProofBench`, `OTIS Mock AIME`, `Epoch Capabilities Index` | source-specific rows from the pinned snapshot | Multi-step architectural, mathematical, and scientific reasoning (`fit 3..0`, then `Blended` cost) |
| `implementation` | `Artificial Analysis Coding Index`, `Artificial Analysis Agentic Index`, `SciCode`, `Terminal-Bench`, `SWE-Bench verified`, `FrontierCode`, `DeepSWE`, `APEX-Agents` | `FrontierSWE`, `OSWorld 2.0`, `Epoch Capabilities Index` | source-specific rows from the pinned snapshot | Agentic software engineering and coding sub-evaluations; math-specific sources (`FrontierMath`, `ProofBench`) apply to quantitative analysis roles (`data-scientist`, `experimenter`, `performance`) rather than general implementation (`fit 3..0`, then `Blended` cost) |
| `review` | `Artificial Analysis Coding Index`, `SWE-Bench verified`, `Terminal-Bench`, `SciCode`, `GPQA diamond`, `CritPt`, `HLE` | `DeepSWE`, `FrontierCode`, `ProofBench`, `Epoch Capabilities Index` | source-specific rows from the pinned snapshot | Code verification, defect detection, and adversarial scientific reasoning (`fit 3..0`, then `Blended` cost) |
| `council` | `Artificial Analysis Intelligence Index`, `GPQA diamond`, `FrontierMath-Tiers-1-3-v2`, `FrontierMath-Tier-4-v2`, `CritPt`, `HLE`, `GDP.pdf` | `Artificial Analysis Agentic Index`, `APEX-Agents`, `SimpleQA Verified`, `Epoch Capabilities Index` | source-specific rows from the pinned snapshot | Cross-domain architectural, security, cost, and governance judgment (`fit 3..0`, then `Blended` cost) |
| `intake` | `Artificial Analysis Agentic Index`, `Artificial Analysis Intelligence Index`, `APEX-Agents`, `GDP.pdf`, `GPQA diamond`, `SimpleQA Verified` | `FrontierCode`, `Artificial Analysis Coding Index`, `SciCode`, `Epoch Capabilities Index` | source-specific rows from the pinned snapshot | Cost and latency (`Blended`) among models clearing the requirements-judgment capability floor (`fit 3..0`, then `Blended` cost) |
| `bookkeeping` | `Artificial Analysis Intelligence Index`, `GPQA diamond`, `Artificial Analysis Coding Index`, `SciCode`, `Artificial Analysis Agentic Index`, `APEX-Agents`, `FrontierCode` | `Epoch Capabilities Index` | source-specific rows from the pinned snapshot | Cost and latency (`Blended`) first among models clearing the structured-output capability floor (`ECI >= 140` or `GPQA diamond >= 0.60`; `fit 3..0`, then `Blended` cost) |

### Design Decisions on Open Questions

1. **Coverage and licensing**: Confirmed as of `2026-10-19`. The generated snapshot contains 435 independently sourced score rows across 34 catalog models. Every row retains its actual publisher, version, score date, and provenance; synthetic aliases such as `hydrafusion-max` are not presented as measured models.
2. **Math-specific sources (`FrontierMath`, `ProofBench`, `OTIS Mock AIME`)**: Required for `planning`, `council`, and math-heavy analysis roles (`data-scientist`, `experimenter`, `performance`, `cost-manager`), where quantitative and formal reasoning drive task quality. Standard `implementation` roles (`developer`, `iac-author`, `deployer`, `release-engineer`, `technical-writer`, `presenter`, `prompt-engineer`) rank on Coding and Agents sub-evaluations (`SciCode`, `Terminal-Bench`, `SWE-Bench verified`, `FrontierCode`, `DeepSWE`, `APEX-Agents`) without requiring `FrontierMath`.
3. **Snapshot refresh cadence and staleness threshold**: `.github/workflows/sync-model-benchmarks.yml` runs daily at `06:30 UTC`, runs `scripts/Sync-ModelBenchmarks.ps1`, validates the snapshot with Pester, and opens or updates a reviewed pull request whenever benchmark scores or source versions change (or when the snapshot age reaches 60 days). At runtime, a snapshot older than **90 days** from its `Retrieved:` date (or one that fails to parse or lacks independent evidence for a candidate) falls back to `model-catalog.md`'s declared fit table and logs one warning.

## Evidence-Derived Assignment Fit

Each row below is derived exclusively from rows in *Benchmark Scores* with `Provenance = independent`. Models with no independent benchmark evaluations (`mai-code-1.1-flash`) are omitted from this table so `Resolve-SquadModelRoute.ps1` falls back to `model-catalog.md`'s declared fit table with a warning and never ranks on self-reported numbers.

| Catalog ID | research | planning | implementation | review | council | intake | bookkeeping | Composite | Sources | Key evaluations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `gpt-5.6-sol` | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0.620 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, osworld-v2-xlang-ai@2026-06-26, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gpt-6.1-sol` | 2 | 3 | 2 | 2 | 2 | 2 | 2 | 0.716 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, epoch-ai@2026-10-19, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gpt-6-sol` | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0.664 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, epoch-ai@2026-10-19, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gpt-6-astra` | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0.706 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, HLE, CritPt, SimpleQA Verified, APEX-Agents |
| `gpt-5.5` | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0.605 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, evals-futuresearch-ai@2025-06-13, osworld-v2-xlang-ai@2026-06-26, surge-gdp-pdf@2026-06-06, terminal-bench@2025-05-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, DeepResearch Bench, SimpleQA Verified, APEX-Agents |
| `gpt-5.4` | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 0.590 | artificial-analysis@v4.3.2, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, evals-futuresearch-ai@2025-06-13, terminal-bench@2025-05-19, vals-ai@2026-01-30 | GPQA diamond, HLE, CritPt, DeepResearch Bench, SimpleQA Verified, APEX-Agents |
| `gpt-5.6-terra` | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0.618 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gpt-5.3-codex` | 2 | 0 | 3 | 3 | 0 | 0 | 2 | 0.700 | epoch-ai@2026-10-19, terminal-bench@2025-05-19 | Epoch Capabilities Index, Terminal-Bench, SWE-Bench verified |
| `gpt-5.4-mini` | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 0.415 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, epoch-ai@2026-10-19, evals-futuresearch-ai@2025-06-13, vals-ai@2026-01-30 | GPQA diamond, CritPt, DeepResearch Bench, SimpleQA Verified, Epoch Capabilities Index, FrontierMath-Tiers-1-3-v2 |
| `gpt-5-mini` | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 0.402 | artificial-analysis@v4.3.2, epoch-ai@2026-10-19, terminal-bench@2025-05-19, vals-ai@2026-01-30 | GPQA diamond, HLE, SimpleQA Verified, Epoch Capabilities Index, FrontierMath-Tiers-1-3-v2, FrontierMath-Tier-4-v2 |
| `gpt-5.4-nano` | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 0.373 | artificial-analysis@v4.3.2, epoch-ai@2026-10-19, vals-ai@2026-01-30 | GPQA diamond, CritPt, SimpleQA Verified, Epoch Capabilities Index, FrontierMath-Tiers-1-3-v2, FrontierMath-Tier-4-v2 |
| `gpt-6-luna` | 1 | 2 | 1 | 2 | 2 | 1 | 2 | 0.556 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, epoch-ai@2026-10-19, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gpt-5.6-luna` | 1 | 2 | 2 | 2 | 2 | 1 | 2 | 0.565 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `claude-opus-5.5` | 2 | 3 | 2 | 2 | 2 | 2 | 2 | 0.717 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `claude-opus-5` | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0.638 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, osworld-v2-xlang-ai@2026-06-26, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `claude-opus-4.8` | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 0.551 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, evals-futuresearch-ai@2025-06-13, osworld-v2-xlang-ai@2026-06-26, surge-gdp-pdf@2026-06-06, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, DeepResearch Bench, SimpleQA Verified, APEX-Agents |
| `claude-opus-4.7` | 1 | 2 | 2 | 2 | 1 | 2 | 2 | 0.524 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, epoch-ai@2026-10-19, osworld-v2-xlang-ai@2026-06-26, surge-gdp-pdf@2026-06-06, terminal-bench@2025-05-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, HLE, CritPt, SimpleQA Verified, APEX-Agents |
| `claude-fable-5.1` | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0.659 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, HLE, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `claude-fable-5` | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0.671 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, surge-gdp-pdf@2026-06-06, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `claude-sonnet-5.5` | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0.665 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, HLE, CritPt, SimpleQA Verified, APEX-Agents |
| `claude-sonnet-5` | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 0.555 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, vals-ai@2026-01-30 | GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index, FrontierMath-Tiers-1-3-v2 |
| `claude-sonnet-4.6` | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0.448 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, evals-futuresearch-ai@2025-06-13, osworld-v2-xlang-ai@2026-06-26, surge-gdp-pdf@2026-10-19, terminal-bench@2025-05-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, DeepResearch Bench, SimpleQA Verified, APEX-Agents |
| `claude-sonnet-4` | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 0.353 | artificial-analysis@v4.3.2, epoch-ai@2026-10-19, evals-futuresearch-ai@2025-06-13 | GPQA diamond, HLE, CritPt, DeepResearch Bench, Epoch Capabilities Index, OTIS Mock AIME |
| `claude-haiku-5.5` | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 0.561 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, vals-ai@2026-01-30 | GPQA diamond, HLE, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `claude-haiku-4.5` | 1 | 2 | 1 | 1 | 2 | 1 | 1 | 0.397 | artificial-analysis@v4.3.2, epoch-ai@2026-10-19, evals-futuresearch-ai@2025-06-13, terminal-bench@2025-05-19 | GPQA diamond, DeepResearch Bench, SimpleQA Verified, Epoch Capabilities Index, OTIS Mock AIME, SciCode |
| `gemini-3.8-flash` | 2 | 2 | 2 | 2 | 1 | 2 | 2 | 0.531 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, HLE, CritPt, SimpleQA Verified, APEX-Agents |
| `gemini-3.7-flash` | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0.556 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gemini-3.6-flash` | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 0.484 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `gemini-3.5-flash` | 1 | 1 | 1 | 2 | 1 | 2 | 2 | 0.502 | artificial-analysis@v4.3.2, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, surge-gdp-pdf@2026-06-06, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `grok-4.7` | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 0.487 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `grok-4.6` | 1 | 2 | 2 | 2 | 1 | 2 | 2 | 0.532 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `grok-4.5` | 1 | 1 | 2 | 1 | 1 | 2 | 2 | 0.493 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `kimi-k3` | 1 | 2 | 1 | 2 | 1 | 2 | 2 | 0.561 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19, frontierswe-com@2026-09-02, surge-gdp-pdf@2026-10-19, vals-ai@2026-01-30 | GDP.pdf, GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index |
| `kimi-k2.7-code` | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0.444 | artificial-analysis@v4.3.2, cognition-frontiercode@2026-06-08, deepswe-datacurve-ai@2026-05-26, epoch-ai@2026-10-19 | GPQA diamond, CritPt, SimpleQA Verified, APEX-Agents, Epoch Capabilities Index, FrontierMath-Tiers-1-3-v2 |

## Benchmark Scores

Every score entry records its exact `Source ID`, `Source version`, `Retrieved` date (`yyyy-MM-dd`), and `Provenance` (`independent` or `self-reported`). Validation tests reject any row missing provenance or carrying an unrecognized provenance value.

| Catalog ID | Evaluation | Category | Score | Source ID | Source version | Retrieved | Provenance |
| --- | --- | --- | ---: | --- | --- | --- | --- |
| `gpt-5.6-sol` | GPQA diamond | `scientific-reasoning` | 0.913 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-sol` | FrontierMath-Tiers-1-3-v2 | `math` | 0.891 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-sol` | FrontierMath-Tier-4-v2 | `math` | 0.829 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-sol` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-sol` | ProofBench | `math` | 0.830 | `vals-ai` | `2026-01-30` | `2026-07-09` | `independent` |
| `gpt-5.6-sol` | FrontierCode | `coding` | 0.475 | `cognition-frontiercode` | `2026-06-08` | `2026-07-09` | `independent` |
| `gpt-5.6-sol` | DeepSWE | `coding` | 0.727 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-07-09` | `independent` |
| `gpt-5.6-sol` | FrontierSWE | `agents` | 0.322 | `frontierswe-com` | `2026-09-02` | `2026-07-09` | `independent` |
| `gpt-5.6-sol` | APEX-Agents | `agents` | 0.514 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-sol` | OSWorld 2.0 | `agents` | 0.273 | `osworld-v2-xlang-ai` | `2026-06-26` | `2026-07-09` | `independent` |
| `gpt-5.6-sol` | SimpleQA Verified | `general-long-doc` | 0.697 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-sol` | SciCode | `coding` | 0.578 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.6-sol` | CritPt | `scientific-reasoning` | 0.323 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.6-sol` | GDP.pdf | `general-long-doc` | 0.307 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-5.6-sol` | Epoch Capabilities Index | `general-long-doc` | 0.617 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-6.1-sol` | GPQA diamond | `scientific-reasoning` | 0.939 | `epoch-ai` | `2026-10-19` | `2026-09-29` | `independent` |
| `gpt-6.1-sol` | FrontierMath-Tiers-1-3-v2 | `math` | 0.937 | `epoch-ai` | `2026-10-19` | `2026-09-29` | `independent` |
| `gpt-6.1-sol` | FrontierMath-Tier-4-v2 | `math` | 1.000 | `epoch-ai` | `2026-10-19` | `2026-09-29` | `independent` |
| `gpt-6.1-sol` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-19` | `2026-09-29` | `independent` |
| `gpt-6.1-sol` | ProofBench | `math` | 0.990 | `vals-ai` | `2026-01-30` | `2026-09-29` | `independent` |
| `gpt-6.1-sol` | FrontierCode | `coding` | 0.502 | `cognition-frontiercode` | `2026-06-08` | `2026-09-29` | `independent` |
| `gpt-6.1-sol` | APEX-Agents | `agents` | 0.600 | `epoch-ai` | `2026-10-19` | `2026-09-29` | `independent` |
| `gpt-6.1-sol` | SimpleQA Verified | `general-long-doc` | 0.739 | `epoch-ai` | `2026-10-19` | `2026-09-29` | `independent` |
| `gpt-6.1-sol` | SciCode | `coding` | 0.558 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-6.1-sol` | CritPt | `scientific-reasoning` | 0.317 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-6.1-sol` | GDP.pdf | `general-long-doc` | 0.350 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-6.1-sol` | Epoch Capabilities Index | `general-long-doc` | 0.663 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-6-sol` | GPQA diamond | `scientific-reasoning` | 0.924 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `gpt-6-sol` | FrontierMath-Tiers-1-3-v2 | `math` | 0.898 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `gpt-6-sol` | FrontierMath-Tier-4-v2 | `math` | 0.900 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `gpt-6-sol` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `gpt-6-sol` | ProofBench | `math` | 0.830 | `vals-ai` | `2026-01-30` | `2026-09-22` | `independent` |
| `gpt-6-sol` | FrontierCode | `coding` | 0.493 | `cognition-frontiercode` | `2026-06-08` | `2026-09-22` | `independent` |
| `gpt-6-sol` | APEX-Agents | `agents` | 0.543 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `gpt-6-sol` | SimpleQA Verified | `general-long-doc` | 0.607 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `gpt-6-sol` | SciCode | `coding` | 0.576 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-6-sol` | CritPt | `scientific-reasoning` | 0.309 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-6-sol` | GDP.pdf | `general-long-doc` | 0.264 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-6-sol` | Epoch Capabilities Index | `general-long-doc` | 0.626 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-6-astra` | GPQA diamond | `scientific-reasoning` | 0.944 | `epoch-ai` | `2026-10-19` | `2026-09-03` | `independent` |
| `gpt-6-astra` | FrontierMath-Tiers-1-3-v2 | `math` | 0.937 | `epoch-ai` | `2026-10-19` | `2026-09-03` | `independent` |
| `gpt-6-astra` | FrontierMath-Tier-4-v2 | `math` | 0.976 | `epoch-ai` | `2026-10-19` | `2026-09-03` | `independent` |
| `gpt-6-astra` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-19` | `2026-09-03` | `independent` |
| `gpt-6-astra` | ProofBench | `math` | 0.990 | `vals-ai` | `2026-01-30` | `2026-09-03` | `independent` |
| `gpt-6-astra` | FrontierCode | `coding` | 0.533 | `cognition-frontiercode` | `2026-06-08` | `2026-09-03` | `independent` |
| `gpt-6-astra` | DeepSWE | `coding` | 0.741 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-09-03` | `independent` |
| `gpt-6-astra` | FrontierSWE | `agents` | 0.655 | `frontierswe-com` | `2026-09-02` | `2026-09-03` | `independent` |
| `gpt-6-astra` | APEX-Agents | `agents` | 0.647 | `epoch-ai` | `2026-10-19` | `2026-09-03` | `independent` |
| `gpt-6-astra` | HLE | `scientific-reasoning` | 0.525 | `epoch-ai` | `2026-10-19` | `2026-09-03` | `independent` |
| `gpt-6-astra` | SimpleQA Verified | `general-long-doc` | 0.756 | `epoch-ai` | `2026-10-19` | `2026-09-03` | `independent` |
| `gpt-6-astra` | SciCode | `coding` | 0.565 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-6-astra` | CritPt | `scientific-reasoning` | 0.317 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-6-astra` | GDP.pdf | `general-long-doc` | 0.342 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-6-astra` | Epoch Capabilities Index | `general-long-doc` | 0.664 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-5.5` | GPQA diamond | `scientific-reasoning` | 0.920 | `epoch-ai` | `2026-10-19` | `2026-04-23` | `independent` |
| `gpt-5.5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.853 | `epoch-ai` | `2026-10-19` | `2026-04-23` | `independent` |
| `gpt-5.5` | FrontierMath-Tier-4-v2 | `math` | 0.725 | `epoch-ai` | `2026-10-19` | `2026-04-23` | `independent` |
| `gpt-5.5` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-19` | `2026-04-23` | `independent` |
| `gpt-5.5` | ProofBench | `math` | 0.500 | `vals-ai` | `2026-01-30` | `2026-04-23` | `independent` |
| `gpt-5.5` | SWE-Bench verified | `coding` | 0.806 | `epoch-ai` | `2026-10-19` | `2026-04-23` | `independent` |
| `gpt-5.5` | Terminal-Bench | `coding` | 0.847 | `terminal-bench` | `2025-05-19` | `2026-04-23` | `independent` |
| `gpt-5.5` | FrontierCode | `coding` | 0.430 | `cognition-frontiercode` | `2026-06-08` | `2026-04-23` | `independent` |
| `gpt-5.5` | DeepSWE | `coding` | 0.670 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-04-23` | `independent` |
| `gpt-5.5` | APEX-Agents | `agents` | 0.551 | `epoch-ai` | `2026-10-19` | `2026-04-23` | `independent` |
| `gpt-5.5` | OSWorld 2.0 | `agents` | 0.130 | `osworld-v2-xlang-ai` | `2026-06-26` | `2026-04-23` | `independent` |
| `gpt-5.5` | SimpleQA Verified | `general-long-doc` | 0.630 | `epoch-ai` | `2026-10-19` | `2026-04-23` | `independent` |
| `gpt-5.5` | DeepResearch Bench | `general-long-doc` | 0.540 | `evals-futuresearch-ai` | `2025-06-13` | `2026-04-23` | `independent` |
| `gpt-5.5` | SciCode | `coding` | 0.561 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.5` | CritPt | `scientific-reasoning` | 0.271 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.5` | GDP.pdf | `general-long-doc` | 0.260 | `surge-gdp-pdf` | `2026-06-06` | `2026-06-06` | `independent` |
| `gpt-5.5` | Epoch Capabilities Index | `general-long-doc` | 0.589 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-5.4` | GPQA diamond | `scientific-reasoning` | 0.911 | `epoch-ai` | `2026-10-19` | `2026-03-05` | `independent` |
| `gpt-5.4` | FrontierMath-Tiers-1-3-v2 | `math` | 0.786 | `epoch-ai` | `2026-10-19` | `2026-03-05` | `independent` |
| `gpt-5.4` | FrontierMath-Tier-4-v2 | `math` | 0.490 | `epoch-ai` | `2026-10-19` | `2026-03-05` | `independent` |
| `gpt-5.4` | OTIS Mock AIME | `math` | 0.978 | `epoch-ai` | `2026-10-19` | `2026-03-05` | `independent` |
| `gpt-5.4` | ProofBench | `math` | 0.560 | `vals-ai` | `2026-01-30` | `2026-03-05` | `independent` |
| `gpt-5.4` | SWE-Bench verified | `coding` | 0.769 | `epoch-ai` | `2026-10-19` | `2026-03-05` | `independent` |
| `gpt-5.4` | Terminal-Bench | `coding` | 0.818 | `terminal-bench` | `2025-05-19` | `2026-03-05` | `independent` |
| `gpt-5.4` | DeepSWE | `coding` | 0.518 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-03-05` | `independent` |
| `gpt-5.4` | APEX-Agents | `agents` | 0.524 | `epoch-ai` | `2026-10-19` | `2026-03-05` | `independent` |
| `gpt-5.4` | HLE | `scientific-reasoning` | 0.330 | `epoch-ai` | `2026-10-19` | `2026-03-05` | `independent` |
| `gpt-5.4` | SimpleQA Verified | `general-long-doc` | 0.451 | `epoch-ai` | `2026-10-19` | `2026-03-05` | `independent` |
| `gpt-5.4` | DeepResearch Bench | `general-long-doc` | 0.351 | `evals-futuresearch-ai` | `2025-06-13` | `2026-03-05` | `independent` |
| `gpt-5.4` | SciCode | `coding` | 0.566 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.4` | CritPt | `scientific-reasoning` | 0.234 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.4` | Epoch Capabilities Index | `general-long-doc` | 0.567 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-5.6-terra` | GPQA diamond | `scientific-reasoning` | 0.911 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-terra` | FrontierMath-Tiers-1-3-v2 | `math` | 0.860 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-terra` | FrontierMath-Tier-4-v2 | `math` | 0.707 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-terra` | OTIS Mock AIME | `math` | 0.997 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-terra` | ProofBench | `math` | 0.740 | `vals-ai` | `2026-01-30` | `2026-07-09` | `independent` |
| `gpt-5.6-terra` | FrontierCode | `coding` | 0.413 | `cognition-frontiercode` | `2026-06-08` | `2026-07-09` | `independent` |
| `gpt-5.6-terra` | DeepSWE | `coding` | 0.696 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-07-09` | `independent` |
| `gpt-5.6-terra` | APEX-Agents | `agents` | 0.582 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-terra` | SimpleQA Verified | `general-long-doc` | 0.432 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-terra` | SciCode | `coding` | 0.550 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.6-terra` | CritPt | `scientific-reasoning` | 0.300 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.6-terra` | GDP.pdf | `general-long-doc` | 0.247 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-5.6-terra` | Epoch Capabilities Index | `general-long-doc` | 0.594 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-5.3-codex` | SWE-Bench verified | `coding` | 0.748 | `epoch-ai` | `2026-10-19` | `2026-02-05` | `independent` |
| `gpt-5.3-codex` | Terminal-Bench | `coding` | 0.784 | `terminal-bench` | `2025-05-19` | `2026-02-05` | `independent` |
| `gpt-5.3-codex` | Epoch Capabilities Index | `general-long-doc` | 0.568 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-5.4-mini` | GPQA diamond | `scientific-reasoning` | 0.825 | `epoch-ai` | `2026-10-19` | `2026-03-17` | `independent` |
| `gpt-5.4-mini` | FrontierMath-Tiers-1-3-v2 | `math` | 0.512 | `epoch-ai` | `2026-10-19` | `2026-03-17` | `independent` |
| `gpt-5.4-mini` | FrontierMath-Tier-4-v2 | `math` | 0.098 | `epoch-ai` | `2026-10-19` | `2026-03-17` | `independent` |
| `gpt-5.4-mini` | OTIS Mock AIME | `math` | 0.889 | `epoch-ai` | `2026-10-19` | `2026-03-17` | `independent` |
| `gpt-5.4-mini` | ProofBench | `math` | 0.210 | `vals-ai` | `2026-01-30` | `2026-03-17` | `independent` |
| `gpt-5.4-mini` | FrontierCode | `coding` | 0.270 | `cognition-frontiercode` | `2026-06-08` | `2026-03-17` | `independent` |
| `gpt-5.4-mini` | SimpleQA Verified | `general-long-doc` | 0.294 | `epoch-ai` | `2026-10-19` | `2026-03-17` | `independent` |
| `gpt-5.4-mini` | DeepResearch Bench | `general-long-doc` | 0.363 | `evals-futuresearch-ai` | `2025-06-13` | `2026-03-17` | `independent` |
| `gpt-5.4-mini` | SciCode | `coding` | 0.521 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.4-mini` | CritPt | `scientific-reasoning` | 0.100 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.4-mini` | Epoch Capabilities Index | `general-long-doc` | 0.488 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-5-mini` | GPQA diamond | `scientific-reasoning` | 0.667 | `epoch-ai` | `2026-10-19` | `2025-08-07` | `independent` |
| `gpt-5-mini` | FrontierMath-Tiers-1-3-v2 | `math` | 0.467 | `epoch-ai` | `2026-10-19` | `2025-08-07` | `independent` |
| `gpt-5-mini` | FrontierMath-Tier-4-v2 | `math` | 0.122 | `epoch-ai` | `2026-10-19` | `2025-08-07` | `independent` |
| `gpt-5-mini` | OTIS Mock AIME | `math` | 0.867 | `epoch-ai` | `2026-10-19` | `2025-08-07` | `independent` |
| `gpt-5-mini` | ProofBench | `math` | 0.090 | `vals-ai` | `2026-01-30` | `2025-08-07` | `independent` |
| `gpt-5-mini` | SWE-Bench verified | `coding` | 0.647 | `epoch-ai` | `2026-10-19` | `2025-08-07` | `independent` |
| `gpt-5-mini` | Terminal-Bench | `coding` | 0.348 | `terminal-bench` | `2025-05-19` | `2025-08-07` | `independent` |
| `gpt-5-mini` | HLE | `scientific-reasoning` | 0.154 | `epoch-ai` | `2026-10-19` | `2025-08-07` | `independent` |
| `gpt-5-mini` | SimpleQA Verified | `general-long-doc` | 0.216 | `epoch-ai` | `2026-10-19` | `2025-08-07` | `independent` |
| `gpt-5-mini` | SciCode | `coding` | 0.392 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5-mini` | Epoch Capabilities Index | `general-long-doc` | 0.454 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-5.4-nano` | GPQA diamond | `scientific-reasoning` | 0.713 | `epoch-ai` | `2026-10-19` | `2026-03-17` | `independent` |
| `gpt-5.4-nano` | FrontierMath-Tiers-1-3-v2 | `math` | 0.449 | `epoch-ai` | `2026-10-19` | `2026-03-17` | `independent` |
| `gpt-5.4-nano` | FrontierMath-Tier-4-v2 | `math` | 0.122 | `epoch-ai` | `2026-10-19` | `2026-03-17` | `independent` |
| `gpt-5.4-nano` | OTIS Mock AIME | `math` | 0.878 | `epoch-ai` | `2026-10-19` | `2026-03-17` | `independent` |
| `gpt-5.4-nano` | ProofBench | `math` | 0.050 | `vals-ai` | `2026-01-30` | `2026-03-17` | `independent` |
| `gpt-5.4-nano` | SimpleQA Verified | `general-long-doc` | 0.117 | `epoch-ai` | `2026-10-19` | `2026-03-17` | `independent` |
| `gpt-5.4-nano` | SciCode | `coding` | 0.472 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.4-nano` | CritPt | `scientific-reasoning` | 0.093 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.4-nano` | Epoch Capabilities Index | `general-long-doc` | 0.461 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-6-luna` | GPQA diamond | `scientific-reasoning` | 0.873 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `gpt-6-luna` | FrontierMath-Tiers-1-3-v2 | `math` | 0.789 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `gpt-6-luna` | FrontierMath-Tier-4-v2 | `math` | 0.561 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `gpt-6-luna` | OTIS Mock AIME | `math` | 0.989 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `gpt-6-luna` | ProofBench | `math` | 0.640 | `vals-ai` | `2026-01-30` | `2026-09-22` | `independent` |
| `gpt-6-luna` | FrontierCode | `coding` | 0.424 | `cognition-frontiercode` | `2026-06-08` | `2026-09-22` | `independent` |
| `gpt-6-luna` | APEX-Agents | `agents` | 0.443 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `gpt-6-luna` | SimpleQA Verified | `general-long-doc` | 0.414 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `gpt-6-luna` | SciCode | `coding` | 0.546 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-6-luna` | CritPt | `scientific-reasoning` | 0.194 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-6-luna` | GDP.pdf | `general-long-doc` | 0.230 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-6-luna` | Epoch Capabilities Index | `general-long-doc` | 0.563 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-5.6-luna` | GPQA diamond | `scientific-reasoning` | 0.888 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-luna` | FrontierMath-Tiers-1-3-v2 | `math` | 0.821 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-luna` | FrontierMath-Tier-4-v2 | `math` | 0.610 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-luna` | OTIS Mock AIME | `math` | 0.983 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-luna` | ProofBench | `math` | 0.600 | `vals-ai` | `2026-01-30` | `2026-07-09` | `independent` |
| `gpt-5.6-luna` | FrontierCode | `coding` | 0.398 | `cognition-frontiercode` | `2026-06-08` | `2026-07-09` | `independent` |
| `gpt-5.6-luna` | DeepSWE | `coding` | 0.672 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-07-09` | `independent` |
| `gpt-5.6-luna` | APEX-Agents | `agents` | 0.430 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-luna` | SimpleQA Verified | `general-long-doc` | 0.410 | `epoch-ai` | `2026-10-19` | `2026-07-09` | `independent` |
| `gpt-5.6-luna` | SciCode | `coding` | 0.536 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.6-luna` | CritPt | `scientific-reasoning` | 0.206 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gpt-5.6-luna` | GDP.pdf | `general-long-doc` | 0.227 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `gpt-5.6-luna` | Epoch Capabilities Index | `general-long-doc` | 0.563 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-opus-5.5` | GPQA diamond | `scientific-reasoning` | 0.875 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `claude-opus-5.5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.912 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `claude-opus-5.5` | FrontierMath-Tier-4-v2 | `math` | 0.950 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `claude-opus-5.5` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `claude-opus-5.5` | ProofBench | `math` | 1.000 | `vals-ai` | `2026-01-30` | `2026-09-22` | `independent` |
| `claude-opus-5.5` | FrontierCode | `coding` | 0.546 | `cognition-frontiercode` | `2026-06-08` | `2026-09-22` | `independent` |
| `claude-opus-5.5` | FrontierSWE | `agents` | 0.623 | `frontierswe-com` | `2026-09-02` | `2026-09-22` | `independent` |
| `claude-opus-5.5` | APEX-Agents | `agents` | 0.735 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `claude-opus-5.5` | SimpleQA Verified | `general-long-doc` | 0.722 | `epoch-ai` | `2026-10-19` | `2026-09-22` | `independent` |
| `claude-opus-5.5` | SciCode | `coding` | 0.669 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-opus-5.5` | CritPt | `scientific-reasoning` | 0.317 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-opus-5.5` | GDP.pdf | `general-long-doc` | 0.306 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-opus-5.5` | Epoch Capabilities Index | `general-long-doc` | 0.668 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-opus-5` | GPQA diamond | `scientific-reasoning` | 0.918 | `epoch-ai` | `2026-10-19` | `2026-07-24` | `independent` |
| `claude-opus-5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.856 | `epoch-ai` | `2026-10-19` | `2026-07-24` | `independent` |
| `claude-opus-5` | FrontierMath-Tier-4-v2 | `math` | 0.732 | `epoch-ai` | `2026-10-19` | `2026-07-24` | `independent` |
| `claude-opus-5` | OTIS Mock AIME | `math` | 0.989 | `epoch-ai` | `2026-10-19` | `2026-07-24` | `independent` |
| `claude-opus-5` | ProofBench | `math` | 0.990 | `vals-ai` | `2026-01-30` | `2026-07-24` | `independent` |
| `claude-opus-5` | FrontierCode | `coding` | 0.534 | `cognition-frontiercode` | `2026-06-08` | `2026-07-24` | `independent` |
| `claude-opus-5` | DeepSWE | `coding` | 0.736 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-07-24` | `independent` |
| `claude-opus-5` | FrontierSWE | `agents` | 0.520 | `frontierswe-com` | `2026-09-02` | `2026-07-24` | `independent` |
| `claude-opus-5` | APEX-Agents | `agents` | 0.658 | `epoch-ai` | `2026-10-19` | `2026-07-24` | `independent` |
| `claude-opus-5` | OSWorld 2.0 | `agents` | 0.314 | `osworld-v2-xlang-ai` | `2026-06-26` | `2026-07-24` | `independent` |
| `claude-opus-5` | SimpleQA Verified | `general-long-doc` | 0.599 | `epoch-ai` | `2026-10-19` | `2026-07-24` | `independent` |
| `claude-opus-5` | SciCode | `coding` | 0.564 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-opus-5` | CritPt | `scientific-reasoning` | 0.291 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-opus-5` | GDP.pdf | `general-long-doc` | 0.240 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-opus-5` | Epoch Capabilities Index | `general-long-doc` | 0.626 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-opus-4.8` | GPQA diamond | `scientific-reasoning` | 0.880 | `epoch-ai` | `2026-10-19` | `2026-05-28` | `independent` |
| `claude-opus-4.8` | FrontierMath-Tiers-1-3-v2 | `math` | 0.800 | `epoch-ai` | `2026-10-19` | `2026-05-28` | `independent` |
| `claude-opus-4.8` | FrontierMath-Tier-4-v2 | `math` | 0.561 | `epoch-ai` | `2026-10-19` | `2026-05-28` | `independent` |
| `claude-opus-4.8` | OTIS Mock AIME | `math` | 0.983 | `epoch-ai` | `2026-10-19` | `2026-05-28` | `independent` |
| `claude-opus-4.8` | ProofBench | `math` | 0.690 | `vals-ai` | `2026-01-30` | `2026-05-28` | `independent` |
| `claude-opus-4.8` | FrontierCode | `coding` | 0.465 | `cognition-frontiercode` | `2026-06-08` | `2026-05-28` | `independent` |
| `claude-opus-4.8` | DeepSWE | `coding` | 0.590 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-05-28` | `independent` |
| `claude-opus-4.8` | APEX-Agents | `agents` | 0.489 | `epoch-ai` | `2026-10-19` | `2026-05-28` | `independent` |
| `claude-opus-4.8` | OSWorld 2.0 | `agents` | 0.206 | `osworld-v2-xlang-ai` | `2026-06-26` | `2026-05-28` | `independent` |
| `claude-opus-4.8` | SimpleQA Verified | `general-long-doc` | 0.530 | `epoch-ai` | `2026-10-19` | `2026-05-28` | `independent` |
| `claude-opus-4.8` | DeepResearch Bench | `general-long-doc` | 0.502 | `evals-futuresearch-ai` | `2025-06-13` | `2026-05-28` | `independent` |
| `claude-opus-4.8` | SciCode | `coding` | 0.535 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-opus-4.8` | CritPt | `scientific-reasoning` | 0.209 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-opus-4.8` | GDP.pdf | `general-long-doc` | 0.240 | `surge-gdp-pdf` | `2026-06-06` | `2026-06-06` | `independent` |
| `claude-opus-4.8` | Epoch Capabilities Index | `general-long-doc` | 0.583 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-opus-4.7` | GPQA diamond | `scientific-reasoning` | 0.869 | `epoch-ai` | `2026-10-19` | `2026-04-16` | `independent` |
| `claude-opus-4.7` | FrontierMath-Tiers-1-3-v2 | `math` | 0.702 | `epoch-ai` | `2026-10-19` | `2026-04-16` | `independent` |
| `claude-opus-4.7` | FrontierMath-Tier-4-v2 | `math` | 0.317 | `epoch-ai` | `2026-10-19` | `2026-04-16` | `independent` |
| `claude-opus-4.7` | OTIS Mock AIME | `math` | 0.978 | `epoch-ai` | `2026-10-19` | `2026-04-16` | `independent` |
| `claude-opus-4.7` | ProofBench | `math` | 0.540 | `vals-ai` | `2026-01-30` | `2026-04-16` | `independent` |
| `claude-opus-4.7` | SWE-Bench verified | `coding` | 0.835 | `epoch-ai` | `2026-10-19` | `2026-04-16` | `independent` |
| `claude-opus-4.7` | Terminal-Bench | `coding` | 0.802 | `terminal-bench` | `2025-05-19` | `2026-04-16` | `independent` |
| `claude-opus-4.7` | FrontierCode | `coding` | 0.385 | `cognition-frontiercode` | `2026-06-08` | `2026-04-16` | `independent` |
| `claude-opus-4.7` | APEX-Agents | `agents` | 0.492 | `epoch-ai` | `2026-10-19` | `2026-04-16` | `independent` |
| `claude-opus-4.7` | OSWorld 2.0 | `agents` | 0.182 | `osworld-v2-xlang-ai` | `2026-06-26` | `2026-04-16` | `independent` |
| `claude-opus-4.7` | HLE | `scientific-reasoning` | 0.330 | `epoch-ai` | `2026-10-19` | `2026-04-16` | `independent` |
| `claude-opus-4.7` | SimpleQA Verified | `general-long-doc` | 0.517 | `epoch-ai` | `2026-10-19` | `2026-04-16` | `independent` |
| `claude-opus-4.7` | SciCode | `coding` | 0.545 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-opus-4.7` | CritPt | `scientific-reasoning` | 0.120 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-opus-4.7` | GDP.pdf | `general-long-doc` | 0.210 | `surge-gdp-pdf` | `2026-06-06` | `2026-06-06` | `independent` |
| `claude-opus-4.7` | Epoch Capabilities Index | `general-long-doc` | 0.563 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-fable-5.1` | FrontierMath-Tiers-1-3-v2 | `math` | 0.902 | `epoch-ai` | `2026-10-19` | `2026-09-01` | `independent` |
| `claude-fable-5.1` | FrontierMath-Tier-4-v2 | `math` | 0.878 | `epoch-ai` | `2026-10-19` | `2026-09-01` | `independent` |
| `claude-fable-5.1` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-19` | `2026-09-01` | `independent` |
| `claude-fable-5.1` | ProofBench | `math` | 1.000 | `vals-ai` | `2026-01-30` | `2026-09-01` | `independent` |
| `claude-fable-5.1` | FrontierCode | `coding` | 0.509 | `cognition-frontiercode` | `2026-06-08` | `2026-09-01` | `independent` |
| `claude-fable-5.1` | FrontierSWE | `agents` | 0.563 | `frontierswe-com` | `2026-09-02` | `2026-09-01` | `independent` |
| `claude-fable-5.1` | APEX-Agents | `agents` | 0.686 | `epoch-ai` | `2026-10-19` | `2026-09-01` | `independent` |
| `claude-fable-5.1` | HLE | `scientific-reasoning` | 0.438 | `epoch-ai` | `2026-10-19` | `2026-09-01` | `independent` |
| `claude-fable-5.1` | SimpleQA Verified | `general-long-doc` | 0.708 | `epoch-ai` | `2026-10-19` | `2026-09-01` | `independent` |
| `claude-fable-5.1` | SciCode | `coding` | 0.631 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-fable-5.1` | CritPt | `scientific-reasoning` | 0.311 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-fable-5.1` | GDP.pdf | `general-long-doc` | 0.296 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-fable-5.1` | Epoch Capabilities Index | `general-long-doc` | 0.647 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-fable-5` | GPQA diamond | `scientific-reasoning` | 0.811 | `epoch-ai` | `2026-10-19` | `2026-06-09` | `independent` |
| `claude-fable-5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.870 | `epoch-ai` | `2026-10-19` | `2026-06-09` | `independent` |
| `claude-fable-5` | FrontierMath-Tier-4-v2 | `math` | 0.902 | `epoch-ai` | `2026-10-19` | `2026-06-09` | `independent` |
| `claude-fable-5` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-19` | `2026-06-09` | `independent` |
| `claude-fable-5` | ProofBench | `math` | 0.950 | `vals-ai` | `2026-01-30` | `2026-06-09` | `independent` |
| `claude-fable-5` | FrontierCode | `coding` | 0.535 | `cognition-frontiercode` | `2026-06-08` | `2026-06-09` | `independent` |
| `claude-fable-5` | DeepSWE | `coding` | 0.699 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-06-09` | `independent` |
| `claude-fable-5` | FrontierSWE | `agents` | 0.470 | `frontierswe-com` | `2026-09-02` | `2026-06-09` | `independent` |
| `claude-fable-5` | APEX-Agents | `agents` | 0.636 | `epoch-ai` | `2026-10-19` | `2026-06-09` | `independent` |
| `claude-fable-5` | SimpleQA Verified | `general-long-doc` | 0.707 | `epoch-ai` | `2026-10-19` | `2026-06-09` | `independent` |
| `claude-fable-5` | SciCode | `coding` | 0.610 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-fable-5` | CritPt | `scientific-reasoning` | 0.286 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-fable-5` | GDP.pdf | `general-long-doc` | 0.300 | `surge-gdp-pdf` | `2026-06-06` | `2026-06-06` | `independent` |
| `claude-fable-5` | Epoch Capabilities Index | `general-long-doc` | 0.621 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-sonnet-5.5` | GPQA diamond | `scientific-reasoning` | 0.941 | `epoch-ai` | `2026-10-19` | `2026-09-28` | `independent` |
| `claude-sonnet-5.5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.888 | `epoch-ai` | `2026-10-19` | `2026-09-28` | `independent` |
| `claude-sonnet-5.5` | FrontierMath-Tier-4-v2 | `math` | 0.805 | `epoch-ai` | `2026-10-19` | `2026-09-28` | `independent` |
| `claude-sonnet-5.5` | OTIS Mock AIME | `math` | 1.000 | `epoch-ai` | `2026-10-19` | `2026-09-28` | `independent` |
| `claude-sonnet-5.5` | ProofBench | `math` | 1.000 | `vals-ai` | `2026-01-30` | `2026-09-28` | `independent` |
| `claude-sonnet-5.5` | FrontierCode | `coding` | 0.521 | `cognition-frontiercode` | `2026-06-08` | `2026-09-28` | `independent` |
| `claude-sonnet-5.5` | FrontierSWE | `agents` | 0.619 | `frontierswe-com` | `2026-09-02` | `2026-09-28` | `independent` |
| `claude-sonnet-5.5` | APEX-Agents | `agents` | 0.755 | `epoch-ai` | `2026-10-19` | `2026-09-28` | `independent` |
| `claude-sonnet-5.5` | HLE | `scientific-reasoning` | 0.434 | `epoch-ai` | `2026-10-19` | `2026-09-28` | `independent` |
| `claude-sonnet-5.5` | SimpleQA Verified | `general-long-doc` | 0.465 | `epoch-ai` | `2026-10-19` | `2026-09-28` | `independent` |
| `claude-sonnet-5.5` | SciCode | `coding` | 0.610 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-sonnet-5.5` | CritPt | `scientific-reasoning` | 0.314 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-sonnet-5.5` | GDP.pdf | `general-long-doc` | 0.314 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-sonnet-5.5` | Epoch Capabilities Index | `general-long-doc` | 0.644 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-sonnet-5` | GPQA diamond | `scientific-reasoning` | 0.874 | `epoch-ai` | `2026-10-19` | `2026-06-30` | `independent` |
| `claude-sonnet-5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.656 | `epoch-ai` | `2026-10-19` | `2026-06-30` | `independent` |
| `claude-sonnet-5` | FrontierMath-Tier-4-v2 | `math` | 0.293 | `epoch-ai` | `2026-10-19` | `2026-06-30` | `independent` |
| `claude-sonnet-5` | OTIS Mock AIME | `math` | 0.947 | `epoch-ai` | `2026-10-19` | `2026-06-30` | `independent` |
| `claude-sonnet-5` | ProofBench | `math` | 0.770 | `vals-ai` | `2026-01-30` | `2026-06-30` | `independent` |
| `claude-sonnet-5` | FrontierCode | `coding` | 0.427 | `cognition-frontiercode` | `2026-06-08` | `2026-06-30` | `independent` |
| `claude-sonnet-5` | DeepSWE | `coding` | 0.538 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-06-30` | `independent` |
| `claude-sonnet-5` | APEX-Agents | `agents` | 0.545 | `epoch-ai` | `2026-10-19` | `2026-06-30` | `independent` |
| `claude-sonnet-5` | SimpleQA Verified | `general-long-doc` | 0.337 | `epoch-ai` | `2026-10-19` | `2026-06-30` | `independent` |
| `claude-sonnet-5` | SciCode | `coding` | 0.543 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-sonnet-5` | CritPt | `scientific-reasoning` | 0.169 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-sonnet-5` | Epoch Capabilities Index | `general-long-doc` | 0.564 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-sonnet-4.6` | GPQA diamond | `scientific-reasoning` | 0.832 | `epoch-ai` | `2026-10-19` | `2026-02-17` | `independent` |
| `claude-sonnet-4.6` | FrontierMath-v1 | `math` | 0.568 | `epoch-ai` | `2026-10-19` | `2026-02-17` | `independent` |
| `claude-sonnet-4.6` | OTIS Mock AIME | `math` | 0.858 | `epoch-ai` | `2026-10-19` | `2026-02-17` | `independent` |
| `claude-sonnet-4.6` | ProofBench | `math` | 0.450 | `vals-ai` | `2026-01-30` | `2026-02-17` | `independent` |
| `claude-sonnet-4.6` | SWE-Bench verified | `coding` | 0.752 | `epoch-ai` | `2026-10-19` | `2026-02-17` | `independent` |
| `claude-sonnet-4.6` | Terminal-Bench | `coding` | 0.534 | `terminal-bench` | `2025-05-19` | `2026-02-17` | `independent` |
| `claude-sonnet-4.6` | FrontierCode | `coding` | 0.243 | `cognition-frontiercode` | `2026-06-08` | `2026-02-17` | `independent` |
| `claude-sonnet-4.6` | DeepSWE | `coding` | 0.299 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-02-17` | `independent` |
| `claude-sonnet-4.6` | APEX-Agents | `agents` | 0.430 | `epoch-ai` | `2026-10-19` | `2026-02-17` | `independent` |
| `claude-sonnet-4.6` | OSWorld 2.0 | `agents` | 0.093 | `osworld-v2-xlang-ai` | `2026-06-26` | `2026-02-17` | `independent` |
| `claude-sonnet-4.6` | SimpleQA Verified | `general-long-doc` | 0.355 | `epoch-ai` | `2026-10-19` | `2026-02-17` | `independent` |
| `claude-sonnet-4.6` | DeepResearch Bench | `general-long-doc` | 0.549 | `evals-futuresearch-ai` | `2025-06-13` | `2026-02-17` | `independent` |
| `claude-sonnet-4.6` | SciCode | `coding` | 0.468 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-sonnet-4.6` | CritPt | `scientific-reasoning` | 0.031 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-sonnet-4.6` | GDP.pdf | `general-long-doc` | 0.180 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-sonnet-4.6` | Epoch Capabilities Index | `general-long-doc` | 0.524 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-sonnet-4` | GPQA diamond | `scientific-reasoning` | 0.723 | `epoch-ai` | `2026-10-19` | `2025-05-22` | `independent` |
| `claude-sonnet-4` | FrontierMath-v1 | `math` | 0.073 | `epoch-ai` | `2026-10-19` | `2025-05-22` | `independent` |
| `claude-sonnet-4` | OTIS Mock AIME | `math` | 0.711 | `epoch-ai` | `2026-10-19` | `2025-05-22` | `independent` |
| `claude-sonnet-4` | HLE | `scientific-reasoning` | 0.031 | `epoch-ai` | `2026-10-19` | `2025-05-22` | `independent` |
| `claude-sonnet-4` | DeepResearch Bench | `general-long-doc` | 0.466 | `evals-futuresearch-ai` | `2025-06-13` | `2025-05-22` | `independent` |
| `claude-sonnet-4` | SciCode | `coding` | 0.400 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-sonnet-4` | CritPt | `scientific-reasoning` | 0.003 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-sonnet-4` | Epoch Capabilities Index | `general-long-doc` | 0.417 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-haiku-5.5` | GPQA diamond | `scientific-reasoning` | 0.862 | `epoch-ai` | `2026-10-19` | `2026-10-07` | `independent` |
| `claude-haiku-5.5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.751 | `epoch-ai` | `2026-10-19` | `2026-10-07` | `independent` |
| `claude-haiku-5.5` | FrontierMath-Tier-4-v2 | `math` | 0.463 | `epoch-ai` | `2026-10-19` | `2026-10-07` | `independent` |
| `claude-haiku-5.5` | OTIS Mock AIME | `math` | 0.989 | `epoch-ai` | `2026-10-19` | `2026-10-07` | `independent` |
| `claude-haiku-5.5` | ProofBench | `math` | 0.890 | `vals-ai` | `2026-01-30` | `2026-10-07` | `independent` |
| `claude-haiku-5.5` | FrontierCode | `coding` | 0.464 | `cognition-frontiercode` | `2026-06-08` | `2026-10-07` | `independent` |
| `claude-haiku-5.5` | FrontierSWE | `agents` | 0.438 | `frontierswe-com` | `2026-09-02` | `2026-10-07` | `independent` |
| `claude-haiku-5.5` | APEX-Agents | `agents` | 0.561 | `epoch-ai` | `2026-10-19` | `2026-10-07` | `independent` |
| `claude-haiku-5.5` | HLE | `scientific-reasoning` | 0.266 | `epoch-ai` | `2026-10-19` | `2026-10-07` | `independent` |
| `claude-haiku-5.5` | SimpleQA Verified | `general-long-doc` | 0.238 | `epoch-ai` | `2026-10-19` | `2026-10-07` | `independent` |
| `claude-haiku-5.5` | SciCode | `coding` | 0.550 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-haiku-5.5` | CritPt | `scientific-reasoning` | 0.226 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-haiku-5.5` | Epoch Capabilities Index | `general-long-doc` | 0.590 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `claude-haiku-4.5` | GPQA diamond | `scientific-reasoning` | 0.616 | `epoch-ai` | `2026-10-19` | `2025-10-15` | `independent` |
| `claude-haiku-4.5` | FrontierMath-v1 | `math` | 0.104 | `epoch-ai` | `2026-10-19` | `2025-10-15` | `independent` |
| `claude-haiku-4.5` | OTIS Mock AIME | `math` | 0.666 | `epoch-ai` | `2026-10-19` | `2025-10-15` | `independent` |
| `claude-haiku-4.5` | Terminal-Bench | `coding` | 0.355 | `terminal-bench` | `2025-05-19` | `2025-10-15` | `independent` |
| `claude-haiku-4.5` | SimpleQA Verified | `general-long-doc` | 0.132 | `epoch-ai` | `2026-10-19` | `2025-10-15` | `independent` |
| `claude-haiku-4.5` | DeepResearch Bench | `general-long-doc` | 0.455 | `evals-futuresearch-ai` | `2025-06-13` | `2025-10-15` | `independent` |
| `claude-haiku-4.5` | SciCode | `coding` | 0.422 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `claude-haiku-4.5` | Epoch Capabilities Index | `general-long-doc` | 0.424 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gemini-3.8-flash` | GPQA diamond | `scientific-reasoning` | 0.939 | `epoch-ai` | `2026-10-19` | `2026-09-02` | `independent` |
| `gemini-3.8-flash` | FrontierMath-Tiers-1-3-v2 | `math` | 0.684 | `epoch-ai` | `2026-10-19` | `2026-09-02` | `independent` |
| `gemini-3.8-flash` | FrontierMath-Tier-4-v2 | `math` | 0.220 | `epoch-ai` | `2026-10-19` | `2026-09-02` | `independent` |
| `gemini-3.8-flash` | OTIS Mock AIME | `math` | 0.989 | `epoch-ai` | `2026-10-19` | `2026-09-02` | `independent` |
| `gemini-3.8-flash` | ProofBench | `math` | 0.480 | `vals-ai` | `2026-01-30` | `2026-09-02` | `independent` |
| `gemini-3.8-flash` | FrontierCode | `coding` | 0.412 | `cognition-frontiercode` | `2026-06-08` | `2026-09-02` | `independent` |
| `gemini-3.8-flash` | DeepSWE | `coding` | 0.738 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-09-02` | `independent` |
| `gemini-3.8-flash` | FrontierSWE | `agents` | 0.196 | `frontierswe-com` | `2026-09-02` | `2026-09-02` | `independent` |
| `gemini-3.8-flash` | APEX-Agents | `agents` | 0.643 | `epoch-ai` | `2026-10-19` | `2026-09-02` | `independent` |
| `gemini-3.8-flash` | HLE | `scientific-reasoning` | 0.417 | `epoch-ai` | `2026-10-19` | `2026-09-02` | `independent` |
| `gemini-3.8-flash` | SimpleQA Verified | `general-long-doc` | 0.697 | `epoch-ai` | `2026-10-19` | `2026-09-02` | `independent` |
| `gemini-3.8-flash` | SciCode | `coding` | 0.566 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gemini-3.8-flash` | CritPt | `scientific-reasoning` | 0.183 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gemini-3.8-flash` | GDP.pdf | `general-long-doc` | 0.234 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `gemini-3.8-flash` | Epoch Capabilities Index | `general-long-doc` | 0.572 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gemini-3.7-flash` | GPQA diamond | `scientific-reasoning` | 0.931 | `epoch-ai` | `2026-10-19` | `2026-08-13` | `independent` |
| `gemini-3.7-flash` | FrontierMath-Tiers-1-3-v2 | `math` | 0.716 | `epoch-ai` | `2026-10-19` | `2026-08-13` | `independent` |
| `gemini-3.7-flash` | FrontierMath-Tier-4-v2 | `math` | 0.366 | `epoch-ai` | `2026-10-19` | `2026-08-13` | `independent` |
| `gemini-3.7-flash` | OTIS Mock AIME | `math` | 0.972 | `epoch-ai` | `2026-10-19` | `2026-08-13` | `independent` |
| `gemini-3.7-flash` | ProofBench | `math` | 0.580 | `vals-ai` | `2026-01-30` | `2026-08-13` | `independent` |
| `gemini-3.7-flash` | FrontierCode | `coding` | 0.436 | `cognition-frontiercode` | `2026-06-08` | `2026-08-13` | `independent` |
| `gemini-3.7-flash` | DeepSWE | `coding` | 0.655 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-08-13` | `independent` |
| `gemini-3.7-flash` | FrontierSWE | `agents` | 0.203 | `frontierswe-com` | `2026-09-02` | `2026-08-13` | `independent` |
| `gemini-3.7-flash` | APEX-Agents | `agents` | 0.678 | `epoch-ai` | `2026-10-19` | `2026-08-13` | `independent` |
| `gemini-3.7-flash` | SimpleQA Verified | `general-long-doc` | 0.692 | `epoch-ai` | `2026-10-19` | `2026-08-13` | `independent` |
| `gemini-3.7-flash` | SciCode | `coding` | 0.598 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gemini-3.7-flash` | CritPt | `scientific-reasoning` | 0.143 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gemini-3.7-flash` | GDP.pdf | `general-long-doc` | 0.238 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `gemini-3.7-flash` | Epoch Capabilities Index | `general-long-doc` | 0.572 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gemini-3.6-flash` | GPQA diamond | `scientific-reasoning` | 0.922 | `epoch-ai` | `2026-10-19` | `2026-07-21` | `independent` |
| `gemini-3.6-flash` | FrontierMath-Tiers-1-3-v2 | `math` | 0.589 | `epoch-ai` | `2026-10-19` | `2026-07-21` | `independent` |
| `gemini-3.6-flash` | FrontierMath-Tier-4-v2 | `math` | 0.220 | `epoch-ai` | `2026-10-19` | `2026-07-21` | `independent` |
| `gemini-3.6-flash` | OTIS Mock AIME | `math` | 0.942 | `epoch-ai` | `2026-10-19` | `2026-07-21` | `independent` |
| `gemini-3.6-flash` | ProofBench | `math` | 0.360 | `vals-ai` | `2026-01-30` | `2026-07-21` | `independent` |
| `gemini-3.6-flash` | FrontierCode | `coding` | 0.344 | `cognition-frontiercode` | `2026-06-08` | `2026-07-21` | `independent` |
| `gemini-3.6-flash` | DeepSWE | `coding` | 0.467 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-07-21` | `independent` |
| `gemini-3.6-flash` | APEX-Agents | `agents` | 0.469 | `epoch-ai` | `2026-10-19` | `2026-07-21` | `independent` |
| `gemini-3.6-flash` | SimpleQA Verified | `general-long-doc` | 0.662 | `epoch-ai` | `2026-10-19` | `2026-07-21` | `independent` |
| `gemini-3.6-flash` | SciCode | `coding` | 0.534 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gemini-3.6-flash` | CritPt | `scientific-reasoning` | 0.106 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gemini-3.6-flash` | GDP.pdf | `general-long-doc` | 0.140 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `gemini-3.6-flash` | Epoch Capabilities Index | `general-long-doc` | 0.542 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `gemini-3.5-flash` | GPQA diamond | `scientific-reasoning` | 0.904 | `epoch-ai` | `2026-10-19` | `2026-05-19` | `independent` |
| `gemini-3.5-flash` | FrontierMath-Tiers-1-3-v2 | `math` | 0.628 | `epoch-ai` | `2026-10-19` | `2026-05-19` | `independent` |
| `gemini-3.5-flash` | FrontierMath-Tier-4-v2 | `math` | 0.268 | `epoch-ai` | `2026-10-19` | `2026-05-19` | `independent` |
| `gemini-3.5-flash` | OTIS Mock AIME | `math` | 0.956 | `epoch-ai` | `2026-10-19` | `2026-05-19` | `independent` |
| `gemini-3.5-flash` | ProofBench | `math` | 0.310 | `vals-ai` | `2026-01-30` | `2026-05-19` | `independent` |
| `gemini-3.5-flash` | SWE-Bench verified | `coding` | 0.793 | `epoch-ai` | `2026-10-19` | `2026-05-19` | `independent` |
| `gemini-3.5-flash` | DeepSWE | `coding` | 0.374 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-05-19` | `independent` |
| `gemini-3.5-flash` | APEX-Agents | `agents` | 0.275 | `epoch-ai` | `2026-10-19` | `2026-05-19` | `independent` |
| `gemini-3.5-flash` | SimpleQA Verified | `general-long-doc` | 0.662 | `epoch-ai` | `2026-10-19` | `2026-05-19` | `independent` |
| `gemini-3.5-flash` | SciCode | `coding` | 0.539 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gemini-3.5-flash` | CritPt | `scientific-reasoning` | 0.131 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `gemini-3.5-flash` | GDP.pdf | `general-long-doc` | 0.140 | `surge-gdp-pdf` | `2026-06-06` | `2026-06-06` | `independent` |
| `gemini-3.5-flash` | Epoch Capabilities Index | `general-long-doc` | 0.544 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `grok-4.7` | GPQA diamond | `scientific-reasoning` | 0.903 | `epoch-ai` | `2026-10-19` | `2026-09-21` | `independent` |
| `grok-4.7` | FrontierMath-Tiers-1-3-v2 | `math` | 0.530 | `epoch-ai` | `2026-10-19` | `2026-09-21` | `independent` |
| `grok-4.7` | FrontierMath-Tier-4-v2 | `math` | 0.171 | `epoch-ai` | `2026-10-19` | `2026-09-21` | `independent` |
| `grok-4.7` | OTIS Mock AIME | `math` | 0.981 | `epoch-ai` | `2026-10-19` | `2026-09-21` | `independent` |
| `grok-4.7` | ProofBench | `math` | 0.340 | `vals-ai` | `2026-01-30` | `2026-09-21` | `independent` |
| `grok-4.7` | FrontierCode | `coding` | 0.476 | `cognition-frontiercode` | `2026-06-08` | `2026-09-21` | `independent` |
| `grok-4.7` | FrontierSWE | `agents` | 0.295 | `frontierswe-com` | `2026-09-02` | `2026-09-21` | `independent` |
| `grok-4.7` | APEX-Agents | `agents` | 0.546 | `epoch-ai` | `2026-10-19` | `2026-09-21` | `independent` |
| `grok-4.7` | SimpleQA Verified | `general-long-doc` | 0.560 | `epoch-ai` | `2026-10-19` | `2026-09-21` | `independent` |
| `grok-4.7` | SciCode | `coding` | 0.578 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `grok-4.7` | CritPt | `scientific-reasoning` | 0.180 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `grok-4.7` | GDP.pdf | `general-long-doc` | 0.228 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `grok-4.7` | Epoch Capabilities Index | `general-long-doc` | 0.544 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `grok-4.6` | GPQA diamond | `scientific-reasoning` | 0.920 | `epoch-ai` | `2026-10-19` | `2026-08-12` | `independent` |
| `grok-4.6` | FrontierMath-Tiers-1-3-v2 | `math` | 0.660 | `epoch-ai` | `2026-10-19` | `2026-08-12` | `independent` |
| `grok-4.6` | FrontierMath-Tier-4-v2 | `math` | 0.317 | `epoch-ai` | `2026-10-19` | `2026-08-12` | `independent` |
| `grok-4.6` | OTIS Mock AIME | `math` | 0.992 | `epoch-ai` | `2026-10-19` | `2026-08-12` | `independent` |
| `grok-4.6` | ProofBench | `math` | 0.510 | `vals-ai` | `2026-01-30` | `2026-08-12` | `independent` |
| `grok-4.6` | FrontierCode | `coding` | 0.480 | `cognition-frontiercode` | `2026-06-08` | `2026-08-12` | `independent` |
| `grok-4.6` | DeepSWE | `coding` | 0.675 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-08-12` | `independent` |
| `grok-4.6` | FrontierSWE | `agents` | 0.253 | `frontierswe-com` | `2026-09-02` | `2026-08-12` | `independent` |
| `grok-4.6` | APEX-Agents | `agents` | 0.653 | `epoch-ai` | `2026-10-19` | `2026-08-12` | `independent` |
| `grok-4.6` | SimpleQA Verified | `general-long-doc` | 0.493 | `epoch-ai` | `2026-10-19` | `2026-08-12` | `independent` |
| `grok-4.6` | SciCode | `coding` | 0.565 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `grok-4.6` | CritPt | `scientific-reasoning` | 0.197 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `grok-4.6` | GDP.pdf | `general-long-doc` | 0.172 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `grok-4.6` | Epoch Capabilities Index | `general-long-doc` | 0.563 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `grok-4.5` | GPQA diamond | `scientific-reasoning` | 0.912 | `epoch-ai` | `2026-10-19` | `2026-07-08` | `independent` |
| `grok-4.5` | FrontierMath-Tiers-1-3-v2 | `math` | 0.572 | `epoch-ai` | `2026-10-19` | `2026-07-08` | `independent` |
| `grok-4.5` | FrontierMath-Tier-4-v2 | `math` | 0.244 | `epoch-ai` | `2026-10-19` | `2026-07-08` | `independent` |
| `grok-4.5` | OTIS Mock AIME | `math` | 0.978 | `epoch-ai` | `2026-10-19` | `2026-07-08` | `independent` |
| `grok-4.5` | ProofBench | `math` | 0.310 | `vals-ai` | `2026-01-30` | `2026-07-08` | `independent` |
| `grok-4.5` | FrontierCode | `coding` | 0.424 | `cognition-frontiercode` | `2026-06-08` | `2026-07-08` | `independent` |
| `grok-4.5` | DeepSWE | `coding` | 0.538 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-07-08` | `independent` |
| `grok-4.5` | APEX-Agents | `agents` | 0.562 | `epoch-ai` | `2026-10-19` | `2026-07-08` | `independent` |
| `grok-4.5` | SimpleQA Verified | `general-long-doc` | 0.483 | `epoch-ai` | `2026-10-19` | `2026-07-08` | `independent` |
| `grok-4.5` | SciCode | `coding` | 0.550 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `grok-4.5` | CritPt | `scientific-reasoning` | 0.154 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `grok-4.5` | GDP.pdf | `general-long-doc` | 0.140 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `grok-4.5` | Epoch Capabilities Index | `general-long-doc` | 0.539 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `kimi-k3` | GPQA diamond | `scientific-reasoning` | 0.908 | `epoch-ai` | `2026-10-19` | `2026-07-16` | `independent` |
| `kimi-k3` | FrontierMath-Tiers-1-3-v2 | `math` | 0.722 | `epoch-ai` | `2026-10-19` | `2026-07-16` | `independent` |
| `kimi-k3` | FrontierMath-Tier-4-v2 | `math` | 0.390 | `epoch-ai` | `2026-10-19` | `2026-07-16` | `independent` |
| `kimi-k3` | OTIS Mock AIME | `math` | 0.972 | `epoch-ai` | `2026-10-19` | `2026-07-16` | `independent` |
| `kimi-k3` | ProofBench | `math` | 0.870 | `vals-ai` | `2026-01-30` | `2026-07-16` | `independent` |
| `kimi-k3` | FrontierCode | `coding` | 0.442 | `cognition-frontiercode` | `2026-06-08` | `2026-07-16` | `independent` |
| `kimi-k3` | DeepSWE | `coding` | 0.685 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-07-16` | `independent` |
| `kimi-k3` | FrontierSWE | `agents` | 0.259 | `frontierswe-com` | `2026-09-02` | `2026-07-16` | `independent` |
| `kimi-k3` | APEX-Agents | `agents` | 0.506 | `epoch-ai` | `2026-10-19` | `2026-07-16` | `independent` |
| `kimi-k3` | SimpleQA Verified | `general-long-doc` | 0.506 | `epoch-ai` | `2026-10-19` | `2026-07-16` | `independent` |
| `kimi-k3` | SciCode | `coding` | 0.595 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `kimi-k3` | CritPt | `scientific-reasoning` | 0.234 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `kimi-k3` | GDP.pdf | `general-long-doc` | 0.190 | `surge-gdp-pdf` | `2026-10-19` | `2026-10-19` | `independent` |
| `kimi-k3` | Epoch Capabilities Index | `general-long-doc` | 0.574 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `kimi-k2.7-code` | GPQA diamond | `scientific-reasoning` | 0.838 | `epoch-ai` | `2026-10-19` | `2026-06-12` | `independent` |
| `kimi-k2.7-code` | FrontierMath-Tiers-1-3-v2 | `math` | 0.540 | `epoch-ai` | `2026-10-19` | `2026-06-12` | `independent` |
| `kimi-k2.7-code` | FrontierMath-Tier-4-v2 | `math` | 0.122 | `epoch-ai` | `2026-10-19` | `2026-06-12` | `independent` |
| `kimi-k2.7-code` | OTIS Mock AIME | `math` | 0.956 | `epoch-ai` | `2026-10-19` | `2026-06-12` | `independent` |
| `kimi-k2.7-code` | FrontierCode | `coding` | 0.301 | `cognition-frontiercode` | `2026-06-08` | `2026-06-12` | `independent` |
| `kimi-k2.7-code` | DeepSWE | `coding` | 0.305 | `deepswe-datacurve-ai` | `2026-05-26` | `2026-06-12` | `independent` |
| `kimi-k2.7-code` | APEX-Agents | `agents` | 0.376 | `epoch-ai` | `2026-10-19` | `2026-06-12` | `independent` |
| `kimi-k2.7-code` | SimpleQA Verified | `general-long-doc` | 0.365 | `epoch-ai` | `2026-10-19` | `2026-06-12` | `independent` |
| `kimi-k2.7-code` | SciCode | `coding` | 0.478 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `kimi-k2.7-code` | CritPt | `scientific-reasoning` | 0.100 | `artificial-analysis` | `v4.3.2` | `2026-10-19` | `independent` |
| `kimi-k2.7-code` | Epoch Capabilities Index | `general-long-doc` | 0.499 | `epoch-ai` | `2026-10-19` | `2026-10-19` | `independent` |
| `mai-code-1.1-flash` | Vendor Task-Area Declaration | `coding` | 0.500 | `vendor-model-card` | `2026-10` | `2026-10-15` | `self-reported` |
