---
name: squad-model-catalog
description: "Declared, dated snapshot of the GitHub Copilot model offering: capability class, per-assignment-class fit scores, context/reasoning documentation status, pricing including long-context tiers, rate-row alias, and host-availability precedence."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.1"
  last_updated: "2026-11-12"
---

# Squad Model Catalog

**This catalog is declared, not live-discovered.** No chat or interactive Copilot host exposes a callable model-list API to the agent at dispatch time (research finding F7); the CLI's dispatch tool advertises an enum, which this catalog intersects. Every row below was retrieved by fetching GitHub's own documentation pages on the date stamped below (`scripts/Sync-ModelCatalog.ps1`), not by querying a runtime discovery endpoint. A routing procedure that reads this file is reading a curated, dated snapshot — never an assertion that the catalog was assembled live for the current session.

* **Retrieved: 2026-11-12**
* Sources (fetched directly for this snapshot; all retrieved 2026-11-12):
  * Supported AI models in GitHub Copilot — <https://docs.github.com/en/copilot/reference/ai-models/supported-models>
  * Models and pricing for GitHub Copilot — <https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing>
  * AI model comparison — <https://docs.github.com/en/copilot/reference/ai-models/model-comparison>
  * About GitHub Copilot Fusion — <https://docs.github.com/en/copilot/concepts/models/copilot-fusion>

This catalog is **host-neutral**: it lists what GitHub Copilot can offer across hosts, not what any one user or host currently has enabled. Filtering to what a given host actually advertises happens in the routing procedure that consumes this file (`model-routing.md`, delivered separately), never here.

## Curation Criteria

A row is added only when at least one of the official sources above names the model, and retired rows absent from both Supported AI models and Models and pricing are pruned automatically on refresh. A row is priced only when the pricing page states a rate (or, for Copilot Fusion effort tiers, a documented representative pool blend over the underlying billed models); a model named elsewhere but absent from pricing is marked `unpriced`, never assigned an invented number. Capability class, best-fit assignment classes, and fit scores are editorial curation over the sources' stated category and task-fit text.

## Maintainer and Review

This file is CODEOWNERS-level content refreshed by `scripts/Sync-ModelCatalog.ps1` and reviewed via pull request before merge. Every change updates `consumption-rates-template.md` in lockstep so pricing and routing never drift.

## Staleness and Re-verification

The retrieval date above is this catalog's freshness signal. **A catalog older than 90 days from its `Retrieved:` date, or a catalog that fails to parse, is stale**: the routing procedure that would otherwise rank against it must fall back to `consumption.md`'s static `fast`/`default`/`extended` tiers and log a warning, rather than blocking the run or guessing at a value this file no longer confirms.

`consumption-rates.md`'s `Observed-on:` date **must equal** this file's `Retrieved:` date exactly, not merely "close" — both are `2026-11-12` as of this snapshot. A future re-verification that updates one must update the other in the same change.

## How This Catalog Is Consumed

A model is **eligible** for automatic ranking only when it is in the intersection of what the dispatching host's own tool/function-calling schema advertises (when it advertises one at all — e.g., this Copilot CLI host's `task` tool exposes a fixed `model` enum) and what this catalog declares. The source order is:

1. **Host-advertised enum ∩ catalog** — when the dispatching host advertises a `model` list (for example, this CLI host's `task` tool), intersect it with this catalog. This intersection is the eligible set for automatic ranking.
2. **Host config/picker** — when no enum is advertised (for example, VS Code's `runSubagent`), the effective host-available set is whatever the operator's picker/config allows; the routing procedure re-ranks reactively on rejection.
3. **Declared catalog** — this file, used as the ranking universe once the eligible set from (1) or (2) is known, or as the static fallback when the catalog itself is stale or unparsable (see Staleness above).

Ranked selection uses the comparable task-evidence policy in `model-scoring.md`; the *Catalog: Assignment Fit* table below is its explicit declared-fit fallback. Capability class decides which minimum Model Tier floors a model can serve, never a maximum spending or capability ceiling.

Two labels describe a mismatch between what the host advertises and what this catalog declares, and neither is ever silently dropped:

* **`unevaluated`** — advertised by the host but not present in this catalog. Excluded from automatic ranking; reachable only as an explicit `routing=manual` pick, never ranked as if this catalog had evaluated it.
* **declared but unavailable** — present in this catalog but not advertised by the host. Never passed to a dispatch call regardless of how well it ranks, because the host has not offered it.

## Capability Class Legend

| Capability class | Definition (this catalog's own curation) | Best-fit assignment classes |
| --- | --- | --- |
| `frontier-reasoning` | The vendor's highest-capability tier ("Powerful" category on the official pricing page, or an explicit "deep reasoning" task-area recommendation); highest per-token cost | research, planning, review, council |
| `balanced` | The vendor's mid tier ("Versatile" category); general-purpose coding/writing/agentic fit at moderate cost | planning, implementation, review, intake |
| `fast-lightweight` | The vendor's lowest tier ("Lightweight" category, or an explicit "fast help with simple/repetitive tasks" recommendation); lowest per-token cost | intake, bookkeeping |
| `code-specialized` | Marketed specifically for agentic/coding workflows over general reasoning (e.g., a "-Codex"/"-Code" name or an explicit "agentic software development" task area) | implementation |

## Catalog: Capability and Availability

Catalog IDs use the same lowercase, hyphenated form as this CLI host's advertised `model` enum (e.g., `claude-opus-5.5`). Where GitHub's documentation names a model or effort level not in the default static enum, the ID is **constructed** in that same style and flagged `(constructed)`; every other ID matches the advertised enum literally and is flagged `(advertised)`.

### OpenAI

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `gpt-5.3-codex` | advertised | GPT-5.3-Codex | GA | code-specialized | 1M | configurable | implementation | "Agentic software development — Agentic tasks"; LTS fallback model for Auto selection |
| `gpt-5.4-nano` | constructed | GPT-5.4 nano | GA (documented, not advertised) | fast-lightweight | undocumented | undocumented | intake, bookkeeping | Lightweight category on the pricing page |
| `gpt-5.6-luna` | advertised | GPT-5.6 Luna | GA | fast-lightweight | 1M | configurable | intake, bookkeeping | "Fast help with simple or repetitive tasks — Quick, cost-efficient responses for smaller, faster coding tasks" |
| `gpt-5.6-sol` | advertised | GPT-5.6 Sol | GA | frontier-reasoning | 1M | configurable | research, planning, review, council | "Deep reasoning and debugging — Complex reasoning over large codebases and long-running agentic work" |
| `gpt-5.6-terra` | advertised | GPT-5.6 Terra | GA | balanced | 1M | configurable | planning, implementation, review | "General-purpose coding and agent tasks — Balanced everyday interactive and agentic coding" |
| `gpt-6-astra` | advertised | GPT-6 Astra | GA | frontier-reasoning | 1M | configurable | research, planning, review, council | "Long-horizon, autonomous coding and agentic tasks — Long-horizon coding tasks with continuous planning, batched diagnosis and verification, and independent result confirmation" |
| `gpt-6-luna` | advertised | GPT-6 Luna | GA | fast-lightweight | 1M | configurable | intake, bookkeeping | "Fast help with simple or repetitive tasks — Quick, cost-efficient responses for smaller, faster tasks" |
| `gpt-6-sol` | advertised | GPT-6 Sol | GA | balanced | 1M | configurable | planning, implementation, review | "Interactive and agentic coding — All-round development tasks that benefit from careful, multistep validation" |
| `gpt-6.1-sol` | advertised | GPT-6.1 Sol | GA | frontier-reasoning | 1M | configurable | implementation, review, planning | "Complex coding tasks — Advanced, efficient reasoning for complex coding tasks" |
| `gpt-6.1-terra` | advertised | GPT-6.1 Terra | GA | balanced | 1M | configurable | planning, implementation, review, intake | "General-purpose coding and agent tasks — Everyday agentic coding and terminal work" |

### Anthropic

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `claude-fable-5` | constructed | Claude Fable 5 | GA (documented, not advertised) | frontier-reasoning | 1M | configurable | research, planning | "Long-horizon, autonomous coding and knowledge-work — First-attempt correctness through upfront reasoning, aggressive parallel tool batching, and proactive verification of pre-existing test state before debugging"; enterprise ZDR/EFS data-retention gating |
| `claude-fable-5.1` | constructed | Claude Fable 5.1 | GA (documented, not advertised) | frontier-reasoning | 1M | configurable | research, planning | "Long-horizon, autonomous coding and knowledge-work — Substantial, long-running coding tasks, including deep codebase research, feature development, and complex agentic workflows"; enterprise ZDR/EFS data-retention gating |
| `claude-fable-5.2` | constructed | Claude Fable 5.2 | GA (documented, not advertised) | frontier-reasoning | 1M | configurable | research, planning, implementation | "Long-horizon, autonomous coding and knowledge-work — Substantial, long-running coding tasks, including deep codebase research, feature development, and complex agentic workflows"; enterprise ZDR/EFS data-retention gating |
| `claude-haiku-4.5` | advertised | Claude Haiku 4.5 | GA | fast-lightweight | undocumented | undocumented | intake, bookkeeping | "Fast help with simple or repetitive tasks — Fast, reliable answers to lightweight coding questions" |
| `claude-haiku-5.5` | advertised | Claude Haiku 5.5 | GA | fast-lightweight | 1M | configurable | intake, bookkeeping | "Fast help with simple or repetitive tasks — Fast, reliable answers to lightweight coding questions" |
| `claude-opus-4.8` | advertised | Claude Opus 4.8 | GA | frontier-reasoning | 1M | configurable | research, planning, review, council | "Deep reasoning and debugging — Complex problem-solving challenges, sophisticated reasoning" |
| `claude-opus-4.8-fast` | constructed | Claude Opus 4.8 (fast mode) (preview) | GA (documented, not advertised) | frontier-reasoning | undocumented | configurable | research, planning, review, council | "Deep reasoning and debugging — Complex problem-solving challenges, sophisticated reasoning" |
| `claude-opus-5` | advertised | Claude Opus 5 | GA | frontier-reasoning | 1M | configurable | research, planning, review, council | "Deep reasoning and debugging — Complex problem-solving challenges, sophisticated reasoning" |
| `claude-opus-5.5` | advertised | Claude Opus 5.5 | GA | frontier-reasoning | 1M | configurable | research, council, review | "Long-running agentic coding and knowledge work — Efficient multistep tasks, error recovery, and collaboration" |
| `claude-sonnet-4` | constructed | Claude Sonnet 4 | **priced, not in current supported list** — see Contradictions below | balanced | undocumented | undocumented | planning, implementation | Not in "Supported AI models" at retrieval; carried because the pricing table still lists it |
| `claude-sonnet-4.6` | constructed | Claude Sonnet 4.6 | GA (documented, not advertised) | balanced | 1M | configurable | planning, implementation, review | "General-purpose coding and agent tasks — Complex problem-solving challenges, sophisticated reasoning" |
| `claude-sonnet-5` | advertised | Claude Sonnet 5 | GA | balanced | 1M | configurable | planning, implementation, review | "General-purpose coding and agent tasks — Complex problem-solving challenges, sophisticated reasoning" |
| `claude-sonnet-5.5` | advertised | Claude Sonnet 5.5 | GA | balanced | 1M | configurable | implementation, intake, review | "General-purpose coding and agent tasks — Efficient task completion with fewer steps, tokens, and tool calls" |

### Google

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `gemini-3.8-flash` | advertised | Gemini 3.8 Flash | GA | balanced | undocumented | undocumented | intake, bookkeeping | "Fast help with simple or repetitive tasks — Fast, reliable answers to lightweight coding questions" |
| `gemini-4-argon` | advertised | Gemini 4 Argon | GA | frontier-reasoning | undocumented | undocumented | planning, implementation, review, council | "Complex coding, agentic, and reasoning tasks — Thorough work that tests edge cases before finishing" |
| `gemini-4-carbon` | advertised | Gemini 4 Carbon | GA | frontier-reasoning | undocumented | undocumented | implementation, review, council | "Complex coding, agentic, and reasoning tasks — Secure code generation and security-focused work" |

### xAI

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `grok-4.5` | constructed | Grok 4.5 | GA (documented, not advertised) | balanced | undocumented | undocumented | planning, implementation, review | "General-purpose coding and agent tasks — Complex problem-solving challenges, sophisticated reasoning" |
| `grok-4.6` | advertised | Grok 4.6 | GA | balanced | undocumented | undocumented | planning, implementation, review | "General-purpose coding and agent tasks — Complex problem-solving challenges, sophisticated reasoning" |
| `grok-4.7` | advertised | Grok 4.7 | GA | balanced | undocumented | undocumented | planning, implementation, review | "Agentic coding and complex, multistep workflows — Complex problem-solving challenges, sophisticated reasoning" |

### Microsoft

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `mai-code-1.1-flash` | advertised | MAI-Code-1.1-Flash | GA | fast-lightweight | undocumented | undocumented | intake, bookkeeping | "General-purpose coding and writing, image understanding — Fast code completions and explanations, instruction following, tool use"; continuously improving checkpoint |

### Moonshot AI

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `kimi-k3` | constructed | Kimi K3 | GA (documented, not advertised) | code-specialized | 1M | configurable | implementation | "Agentic coding and long-context work — Multi-step agent tasks across large codebases"; elevated-risk safeguards per source note |

### Copilot Fusion

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `fusion-standard` | constructed | Copilot Fusion Standard | GA (documented, not advertised) | balanced | dynamic (pool minimum) | dynamic (per step) | planning, implementation, intake, bookkeeping | Copilot Fusion `standard` effort (`--model fusion --fusion-tier standard`); single-model routing across versatile and lightweight models (`1.0x` token footprint; billed at underlying model rates) |
| `hydrafusion` | advertised | Copilot Fusion High | GA | balanced | dynamic (pool minimum) | dynamic (per step) | research, planning, implementation, review, intake | Copilot Fusion `high` effort (`hydrafusion` / `--fusion-tier high`); balanced cascade orchestration with moderate token savings (~0.55x token footprint; billed at underlying model rates) |
| `hydrafusion-max` | advertised | Copilot Fusion Max | GA | frontier-reasoning | dynamic (pool minimum) | dynamic (per step) | research, planning, implementation, review, council, intake | Copilot Fusion `max` effort (`hydrafusion-max` / `--fusion-tier max`); frontier cascade/critique orchestration (~0.35x token footprint; billed at underlying model rates) |

## Catalog: Pricing (USD per 1M tokens)

Every single-model price below is transcribed verbatim from the "Models and pricing" page retrieved 2026-11-12; **`unpriced` never means `0`**. Copilot Fusion rows record representative blended solver rates for Cost Preflight and fallback estimation (live native billing charges each underlying model invoked). The `Rate-row alias` column names the exact `consumption-rates.md` "Model (as routed)" row this ID prices as.

### OpenAI (has a documented long-context tier)

| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output | LC input | LC cached | LC cache write | LC output |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `gpt-5.3-codex` | GPT-5.3-Codex | none (flat rate) | 1.75 | 0.175 | n/a | 14.00 | n/a | n/a | n/a | n/a |
| `gpt-5.4-nano` | GPT-5.4 nano | none (flat rate) | 0.20 | 0.02 | n/a | 1.25 | n/a | n/a | n/a | n/a |
| `gpt-5.6-luna` | GPT-5.6 Luna | ≤200K / >200K | 0.20 | 0.02 | 0.25 | 1.20 | 0.40 | 0.04 | 0.50 | 1.80 |
| `gpt-5.6-sol` | GPT-5.6 Sol | ≤272K / >272K | 4.00 | 0.40 | 5.00 | 20.00 | 8.00 | 0.80 | 10.00 | 30.00 |
| `gpt-5.6-terra` | GPT-5.6 Terra | ≤272K / >272K | 2.00 | 0.20 | 2.50 | 12.00 | 4.00 | 0.40 | 5.00 | 18.00 |
| `gpt-6-astra` | GPT-6 Astra | ≤272K / >272K | 10.00 | 1.00 | 12.50 | 50.00 | 20.00 | 2.00 | 25.00 | 75.00 |
| `gpt-6-luna` | GPT-6 Luna | ≤272K / >272K | 0.10 | 0.01 | 0.125 | 0.50 | 0.20 | 0.02 | 0.25 | 0.75 |
| `gpt-6-sol` | GPT-6 Sol | ≤272K / >272K | 2.00 | 0.20 | 2.50 | 10.00 | 4.00 | 0.40 | 5.00 | 15.00 |
| `gpt-6.1-sol` | GPT-6.1 Sol | ≤272K / >272K | 2.00 | 0.10 | 2.50 | 10.00 | 4.00 | 0.20 | 5.00 | 15.00 |
| `gpt-6.1-terra` | GPT-6.1 Terra | ≤272K / >272K | 1.00 | 0.05 | 1.25 | 5.00 | 2.00 | 0.10 | 2.50 | 7.50 |

### Anthropic (Claude Haiku 5.5 has a documented long-context tier)

| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output | LC input | LC cached | LC cache write | LC output |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `claude-fable-5` | Claude Fable 5 | none (flat rate) | 10.00 | 1.00 | 12.50 | 50.00 | n/a | n/a | n/a | n/a |
| `claude-fable-5.1` | Claude Fable 5.1 | none (flat rate) | 10.00 | 0.25 | 12.50 | 50.00 | n/a | n/a | n/a | n/a |
| `claude-fable-5.2` | Claude Fable 5.2 | none (flat rate) | 8.00 | 0.20 | 10.00 | 40.00 | n/a | n/a | n/a | n/a |
| `claude-haiku-4.5` | Claude Haiku 4.5 | none (flat rate) | 1.00 | 0.10 | 1.25 | 5.00 | n/a | n/a | n/a | n/a |
| `claude-haiku-5.5` | Claude Haiku 5.5 | ≤100K / >100K | 0.10 | 0.01 | 0.125 | 0.50 | 0.50 | 0.05 | 0.625 | 2.50 |
| `claude-opus-4.8` | Claude Opus 4.8 | none (flat rate) | 5.00 | 0.50 | 6.25 | 25.00 | n/a | n/a | n/a | n/a |
| `claude-opus-4.8-fast` | Claude Opus 4.8 (fast mode) | none (flat rate) | 10.00 | 1.00 | 12.50 | 50.00 | n/a | n/a | n/a | n/a |
| `claude-opus-5` | Claude Opus 5 | none (flat rate) | 5.00 | 0.50 | 6.25 | 25.00 | n/a | n/a | n/a | n/a |
| `claude-opus-5.5` | Claude Opus 5.5 | none (flat rate) | 4.00 | 0.20 | 5.00 | 20.00 | n/a | n/a | n/a | n/a |
| `claude-sonnet-4` | Claude Sonnet 4 | none (flat rate) | 3.00 | 0.30 | 3.75 | 15.00 | n/a | n/a | n/a | n/a |
| `claude-sonnet-4.6` | Claude Sonnet 4.6 | none (flat rate) | 3.00 | 0.30 | 3.75 | 15.00 | n/a | n/a | n/a | n/a |
| `claude-sonnet-5` | Claude Sonnet 5 | none (flat rate) | 2.00 | 0.20 | 2.50 | 10.00 | n/a | n/a | n/a | n/a |
| `claude-sonnet-5.5` | Claude Sonnet 5.5 | none (flat rate) | 2.00 | 0.10 | 2.50 | 10.00 | n/a | n/a | n/a | n/a |

### Google (no long-context tier documented — flat rate)

| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `gemini-3.8-flash` | Gemini 3.8 Flash | none (flat rate) | 0.75 | 0.075 | 0 | 3.75 |
| `gemini-4-argon` | Gemini 4 Argon | none (flat rate) | 2.00 | 0.10 | 0 | 10.00 |
| `gemini-4-carbon` | Gemini 4 Carbon | none (flat rate) | 2.00 | 0.10 | 0 | 10.00 |

### xAI (has a documented long-context tier)

| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output | LC input | LC cached | LC cache write | LC output |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `grok-4.5` | Grok 4.5 | ≤200K / >200K | 2.00 | 0.50 | 0 | 6.00 | 4.00 | 1.00 | 0 | 12.00 |
| `grok-4.6` | Grok 4.6 | ≤200K / >200K | 2.00 | 0.50 | 0 | 6.00 | 4.00 | 1.00 | 0 | 12.00 |
| `grok-4.7` | Grok 4.7 | ≤200K / >200K | 2.00 | 0.50 | 0 | 6.00 | 4.00 | 1.00 | 0 | 12.00 |

### Microsoft and Moonshot AI (no long-context tier documented — flat rate)

| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `mai-code-1.1-flash` | MAI-Code-1.1-Flash | none (flat rate) | 0.20 | 0.02 | 0 | 1.20 |
| `kimi-k3` | Kimi K3 | none (flat rate) | 3.00 | 0.30 | 0 | 15.00 |

### Copilot Fusion (has a documented long-context tier)

| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output | LC input | LC cached | LC cache write | LC output |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `fusion-standard` | Copilot Fusion Standard | ≤272K / >272K | 0.40 | 0.025 | 0.50 | 2.00 | 0.80 | 0.05 | 1.00 | 3.00 |
| `hydrafusion` | Copilot Fusion High | ≤272K / >272K | 0.60 | 0.04 | 0.75 | 3.00 | 1.20 | 0.08 | 1.50 | 4.50 |
| `hydrafusion-max` | Copilot Fusion Max | ≤272K / >272K | 0.80 | 0.05 | 1.00 | 4.00 | 1.60 | 0.10 | 2.00 | 6.00 |

## Catalog: Assignment Fit

This table is Ranked's operational fallback when the pinned independent evidence cannot support a comparison. Its coarse editorial scores are not granular measured capability, calibrated uncertainty, or a validated Economy quality threshold:

* `3` — best in class: the source pages name this model for exactly this kind of work.
* `2` — capable: a sound choice for the class, but not what the sources lead with.
* `1` — usable: acceptable for the class, but weaker at it than its cost suggests.
* `0` — unsuitable: never ranked for the class.

`Family` and `Generation` resolve a tie between two generations of the same line (`claude-sonnet` `5.5` ranks ahead of `5` at equal fit and price). `Blended` is USD per 1M tokens of a representative agentic dispatch, derived from the pricing tables above as `0.20 × Input + 0.80 × Cached + 0.08 × Cache write + 0.02 × Output` (`n/a` counts as `0`). Rows are grouped by family, newest generation first; that order is the final tie-break.

| Catalog ID | Family | Generation | research | planning | implementation | review | council | intake | bookkeeping | Blended |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `gpt-6.1-sol` | gpt-sol | 6.1 | 2 | 2 | 3 | 2 | 2 | 2 | 0 | 0.880 |
| `gpt-6-sol` | gpt-sol | 6 | 1 | 2 | 3 | 3 | 2 | 2 | 0 | 0.960 |
| `gpt-5.6-sol` | gpt-sol | 5.6 | 3 | 3 | 2 | 3 | 2 | 2 | 0 | 1.920 |
| `gpt-6-astra` | gpt-astra | 6 | 3 | 3 | 2 | 2 | 3 | 1 | 0 | 4.800 |
| `gpt-6.1-terra` | gpt-terra | 6.1 | 1 | 2 | 3 | 2 | 1 | 3 | 0 | 0.440 |
| `gpt-5.6-terra` | gpt-terra | 5.6 | 1 | 2 | 2 | 2 | 1 | 3 | 0 | 1.000 |
| `gpt-5.3-codex` | gpt-codex | 5.3 | 1 | 1 | 3 | 2 | 0 | 1 | 0 | 0.770 |
| `gpt-5.4-nano` | gpt-nano | 5.4 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 0.081 |
| `gpt-6-luna` | gpt-luna | 6 | 0 | 0 | 1 | 0 | 0 | 1 | 2 | 0.048 |
| `gpt-5.6-luna` | gpt-luna | 5.6 | 0 | 0 | 1 | 0 | 0 | 1 | 2 | 0.100 |
| `claude-opus-5.5` | claude-opus | 5.5 | 3 | 2 | 2 | 2 | 2 | 1 | 0 | 1.760 |
| `claude-opus-5` | claude-opus | 5 | 3 | 3 | 2 | 3 | 3 | 2 | 0 | 2.400 |
| `claude-opus-4.8` | claude-opus | 4.8 | 2 | 3 | 2 | 3 | 3 | 2 | 0 | 2.400 |
| `claude-opus-4.8-fast` | claude-opus-fast | 4.8 | 2 | 2 | 2 | 2 | 2 | 1 | 0 | 4.800 |
| `claude-fable-5.2` | claude-fable | 5.2 | 3 | 3 | 3 | 2 | 2 | 1 | 0 | 3.360 |
| `claude-fable-5.1` | claude-fable | 5.1 | 3 | 2 | 3 | 2 | 2 | 1 | 0 | 4.200 |
| `claude-fable-5` | claude-fable | 5 | 3 | 3 | 2 | 2 | 2 | 1 | 0 | 4.800 |
| `claude-sonnet-5.5` | claude-sonnet | 5.5 | 2 | 2 | 3 | 2 | 2 | 3 | 0 | 0.880 |
| `claude-sonnet-5` | claude-sonnet | 5 | 2 | 2 | 2 | 2 | 2 | 3 | 0 | 0.960 |
| `claude-sonnet-4.6` | claude-sonnet | 4.6 | 1 | 2 | 2 | 2 | 1 | 2 | 0 | 1.440 |
| `claude-sonnet-4` | claude-sonnet | 4 | 1 | 1 | 1 | 1 | 1 | 1 | 0 | 1.440 |
| `claude-haiku-5.5` | claude-haiku | 5.5 | 1 | 0 | 1 | 1 | 0 | 2 | 3 | 0.048 |
| `claude-haiku-4.5` | claude-haiku | 4.5 | 1 | 0 | 1 | 1 | 0 | 2 | 3 | 0.480 |
| `gemini-4-argon` | gemini-argon | 4 | 2 | 3 | 3 | 3 | 2 | 2 | 0 | 0.680 |
| `gemini-4-carbon` | gemini-carbon | 4 | 2 | 2 | 3 | 3 | 3 | 2 | 0 | 0.680 |
| `gemini-3.8-flash` | gemini-flash | 3.8 | 1 | 1 | 1 | 1 | 0 | 1 | 2 | 0.285 |
| `grok-4.7` | grok | 4.7 | 1 | 2 | 2 | 2 | 1 | 2 | 0 | 0.920 |
| `grok-4.6` | grok | 4.6 | 1 | 1 | 2 | 1 | 1 | 1 | 0 | 0.920 |
| `grok-4.5` | grok | 4.5 | 1 | 1 | 2 | 1 | 1 | 1 | 0 | 0.920 |
| `kimi-k3` | kimi | 3 | 1 | 1 | 2 | 1 | 0 | 1 | 0 | 1.140 |
| `mai-code-1.1-flash` | mai-code-flash | 1.1 | 0 | 0 | 1 | 0 | 0 | 1 | 2 | 0.080 |
| `hydrafusion-max` | copilot-fusion | 3 | 2 | 2 | 2 | 2 | 2 | 2 | 1 | 0.360 |
| `hydrafusion` | copilot-fusion | 2 | 2 | 2 | 2 | 2 | 1 | 2 | 1 | 0.272 |
| `fusion-standard` | copilot-fusion | 1 | 1 | 2 | 2 | 1 | 1 | 2 | 2 | 0.180 |

## Advertised but Unevaluated

This host's `task` dispatch tool advertises `model` values that this snapshot's official sources do not document at all. Each is `unevaluated`: excluded from automatic ranking, priced `unpriced` (never `0`), and reachable only as an explicit `routing=manual` pick.

| Advertised ID | Why unevaluated | Price |
| --- | --- | --- |
| `gpt-5.6-sol-fast` | No "GPT-5.6 Sol (fast mode)" or equivalent variant appears in "Supported AI models," "Models and pricing," or "AI model comparison" at retrieval. | unpriced |

## Documented but Not Advertised

These models are named by the official sources but are not in the default static `task.model` enum at retrieval. Host-availability filtering happens in the routing procedure, never by deleting a documented active row here.

| Catalog ID | Display name | Why not advertised (as observed, not asserted) |
| --- | --- | --- |
| `claude-fable-5` | Claude Fable 5 | Enterprise-gated ZDR/EFS model; requires enterprise enablement |
| `claude-fable-5.1` | Claude Fable 5.1 | Enterprise-gated ZDR/EFS model; requires enterprise enablement |
| `claude-fable-5.2` | Claude Fable 5.2 | Enterprise-gated ZDR/EFS model; requires enterprise enablement |
| `claude-opus-4.8-fast` | Claude Opus 4.8 (fast mode) (preview) | Documented and priced in official Copilot docs; not in default `task.model` enum at retrieval |
| `claude-sonnet-4` | Claude Sonnet 4 | Absent from "Supported AI models" (see Contradictions); retained from billing table |
| `claude-sonnet-4.6` | Claude Sonnet 4.6 | Documented and priced in official Copilot docs; not in default `task.model` enum at retrieval |
| `fusion-standard` | Copilot Fusion Standard | Copilot Fusion Standard session policy (`--model fusion --fusion-tier standard`); not a separate `task.model` enum entry |
| `gpt-5.4-nano` | GPT-5.4 nano | Documented and priced in official Copilot docs; not in default `task.model` enum at retrieval |
| `grok-4.5` | Grok 4.5 | Documented and priced in official Copilot docs; not in default `task.model` enum at retrieval |
| `kimi-k3` | Kimi K3 | Documented and priced in official Copilot docs; not in default `task.model` enum at retrieval |

## Named Only in the Comparison Guide (Degraded Confidence)

| Catalog ID | Display name | Why degraded | Price |
| --- | --- | --- | --- |
| `qwen2.5` | Qwen2.5 | Appears in the "AI model comparison" page's recommended-models table (task area: general-purpose coding and writing) but is absent from both "Supported AI models" and "Models and pricing" at retrieval — named by only one of the three sources, with no corroborating pricing or supported-status row | unpriced |

## Contradictions and Notes Observed at Retrieval

* **Claude Sonnet 4 is priced but not currently in Supported AI models.** The "Models and pricing" Anthropic table lists Claude Sonnet 4 ($3.00 / $0.30 / $3.75 / $15.00), while "Supported AI models" omits it. Retained cautiously so historical/legacy dispatches remain priceable and auditable.
* **Copilot Fusion effort levels (`fusion-standard`, `hydrafusion`, `hydrafusion-max`).** Copilot Fusion dynamically selects models and execution patterns (`Single`, `Cascade`, `Critique`) across three user-selectable effort levels (`Standard`, `High`, `Max`) and bills each underlying model at its standard rate. The catalog records all three effort levels distinctly instead of collapsing `hydrafusion` (High) into `hydrafusion-max` (Max).
* **Retired models pruned from active selection.** Models listed in GitHub's retirement history and absent from current supported/pricing tables — including Claude Opus 4.1 (2026-02-17), Gemini 3 Flash (2026-07-31), Claude Sonnet 3.5 (2025-11-06), GPT-5.4 (2026-10-19), Gemini 3.1 Pro (2026-09-01), GPT-5.1-Codex-Max (2026-04-01), Claude Opus 4.7 (2026-10-02), Claude Sonnet 4.6 (2026-09-01), Claude Opus 4 (2025-10-23), Gemini 3.7 Flash (2026-10-19) — are excluded from active catalog ranking and benchmark coverage gates.

## Squad Assignment Classes Referenced Above

`research`, `planning`, `implementation`, `review`, `council`, `intake`, `bookkeeping` — the seven fixed assignment classes this catalog's "best-fit assignment classes" column draws from, per `model-routing.md`. Consequence floors live in `team.md`'s Model Tier column and are independent of this catalog.
