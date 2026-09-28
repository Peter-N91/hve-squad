---
name: squad-model-catalog
description: "Declared, dated snapshot of the GitHub Copilot model offering: capability class, context/reasoning documentation status, pricing including long-context tiers, rate-row alias, and host-availability precedence."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-09-27"
---

# Squad Model Catalog

**This catalog is declared, not live-discovered.** No chat or interactive Copilot host exposes a callable model-list API to the agent at dispatch time (research finding F7); the CLI's dispatch tool advertises an enum, which this catalog intersects. Every row below was retrieved by fetching GitHub's own documentation pages on the date stamped below, not by querying a runtime discovery endpoint. A routing procedure that reads this file is reading a curated, dated snapshot — never an assertion that the catalog was assembled live for the current session.

* **Retrieved: 2026-09-27**
* Sources (fetched directly for this snapshot; all three retrieved 2026-09-27):
  * Supported AI models in GitHub Copilot — <https://docs.github.com/en/copilot/reference/ai-models/supported-models>
  * Models and pricing for GitHub Copilot — <https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing>
  * AI model comparison — <https://docs.github.com/en/copilot/reference/ai-models/model-comparison>

This catalog is **host-neutral**: it lists what GitHub Copilot can offer across hosts, not what any one user or host currently has enabled. Filtering to what a given host actually advertises happens in the routing procedure that consumes this file (`model-routing.md`, delivered separately), never here.

## Curation Criteria

A row is added only when at least one of the three sources above names the model. A row is priced only when the pricing page states a rate; a model named elsewhere but absent from the pricing page is marked `unpriced`, never assigned an invented number. A row's capability class, "best-fit assignment classes," and notes are this catalog's own editorial curation over the sources' stated task-fit guidance (the "AI model comparison" page's task-area and "excels at" text) — the price and existence facts are sourced verbatim; the assignment-class mapping is a judgment call, labeled as such, not a fourth official source.

## Maintainer and Review

This file is CODEOWNERS-level content: a change to it is reviewed the same way any other `squad-src/.github/skills/` reference is reviewed before merge. The cost-manager role additionally performs an independent pricing review of every catalog delivery (see this delivery's own history entry and D4 in `.copilot-tracking/squad/members/routing-performance/`), because a declared price is exactly the kind of fact that degrades silently if only one reviewer ever reads it.

## Staleness and Re-verification

The retrieval date above is this catalog's only freshness signal — there is no live "last confirmed" heartbeat. **A catalog older than 90 days from its `Retrieved:` date, or a catalog that fails to parse, is stale**: the routing procedure that would otherwise rank against it must fall back to `consumption.md`'s static `fast`/`default`/`extended` tiers and log a warning, rather than blocking the run or guessing at a value this file no longer confirms. Re-verification is a normal Follow-Up trigger for whichever role next touches routing, not an ongoing maintenance obligation of this delivery.

`consumption-rates.md`'s `Observed-on:` date **must equal** this file's `Retrieved:` date exactly, not merely "close" — both are `2026-09-27` as of this snapshot. A future re-verification that updates one must update the other in the same change.

## How This Catalog Is Consumed

A model is **eligible** for automatic ranking only when it is in the intersection of what the dispatching host's own tool/function-calling schema advertises (when it advertises one at all — e.g., this Copilot CLI host's `task` tool exposes a fixed `model` enum) and what this catalog declares. The source order is:

1. **Host-advertised enum ∩ catalog** — when the dispatching host advertises a `model` list (for example, this CLI host's `task` tool), intersect it with this catalog. This intersection is the eligible set for automatic ranking.
2. **Host config/picker** — when no enum is advertised (for example, VS Code's `runSubagent`), the effective host-available set is whatever the operator's picker/config allows; the routing procedure re-ranks reactively on rejection.
3. **Declared catalog** — this file, used as the ranking universe once the eligible set from (1) or (2) is known, or as the static fallback when the catalog itself is stale or unparsable (see Staleness above).

Two labels describe a mismatch between what the host advertises and what this catalog declares, and neither is ever silently dropped:

* **`unevaluated`** — advertised by the host but not present in this catalog. Excluded from automatic ranking; reachable only via an explicit `models=` override, never ranked as if this catalog had evaluated it.
* **declared but unavailable** — present in this catalog but not advertised by the host. Never passed to a dispatch call regardless of how well it ranks, because the host has not offered it.

## Capability Class Legend

| Capability class | Definition (this catalog's own curation) | Best-fit assignment classes |
| --- | --- | --- |
| `frontier-reasoning` | The vendor's highest-capability tier ("Powerful" category on the official pricing page, or an explicit "deep reasoning" task-area recommendation); highest per-token cost | research, planning, review, council |
| `balanced` | The vendor's mid tier ("Versatile" category); general-purpose coding/writing/agentic fit at moderate cost | planning, implementation, review, intake |
| `fast-lightweight` | The vendor's lowest tier ("Lightweight" category, or an explicit "fast help with simple/repetitive tasks" recommendation); lowest per-token cost | intake, bookkeeping |
| `code-specialized` | Marketed specifically for agentic/coding workflows over general reasoning (e.g., a "-Codex"/"-Code" name or an explicit "agentic software development" task area) | implementation |

A model's row states which of the seven assignment classes (`research`, `planning`, `implementation`, `review`, `council`, `intake`, `bookkeeping`) it best fits, derived from this legend plus the source pages' own "task area"/"excels at" text — never a number this catalog invented.

## Catalog: Capability and Availability

Catalog IDs use the same lowercase, hyphenated form as this CLI host's advertised `model` enum (e.g., `claude-opus-4.7`). Where GitHub's documentation names a model this catalog must carry but never publishes a dispatch-id string for it, the ID is **constructed** in that same style and flagged `(constructed)`; every other ID matches this host's advertised enum literally and is flagged `(advertised)`. Context window and reasoning-effort support are recorded as `undocumented` wherever the three source pages do not state a figure — no page fetched for this snapshot publishes a per-model context-window token count or a per-model reasoning-effort flag, so every row currently reads `undocumented` for both columns; this is a fact about the sources, not an omission by this catalog.

### OpenAI

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `gpt-5-mini` | advertised | GPT-5 mini | GA | fast-lightweight | undocumented | undocumented | intake, bookkeeping | "Fast, accurate code completions and explanations"; also recommended for deep reasoning at lower resource cost per the comparison guide |
| `gpt-5.3-codex` | advertised | GPT-5.3-Codex | GA | code-specialized | undocumented | undocumented | implementation | "Agentic software development... agentic tasks"; long-term-support fallback model for Auto selection |
| `gpt-5.4` | advertised | GPT-5.4 | GA | balanced | undocumented | undocumented | planning, review | "Deep reasoning and debugging... multi-step problem solving and architecture-level code analysis" |
| `gpt-5.4-mini` | advertised | GPT-5.4 mini | GA | fast-lightweight | undocumented | undocumented | implementation, intake | "Agentic software development... codebase exploration... especially effective using grep-style tools" |
| `gpt-5.4-nano` | constructed | GPT-5.4 nano | GA (documented, not advertised) | fast-lightweight | undocumented | undocumented | intake, bookkeeping | Lightweight category; no task-area entry in the comparison guide |
| `gpt-5.5` | advertised | GPT-5.5 | GA | frontier-reasoning | undocumented | undocumented | research, planning, review, council | "Deep reasoning and debugging... multi-step problem solving and architecture-level code analysis" |
| `gpt-5.6-luna` | advertised | GPT-5.6 Luna | GA | fast-lightweight | undocumented | undocumented | intake, bookkeeping | "Fast help with simple or repetitive tasks... lowest-cost model in the GPT-5.6 family" |
| `gpt-5.6-sol` | advertised | GPT-5.6 Sol | GA | frontier-reasoning | undocumented | undocumented | research, planning, review, council | "The highest reasoning ceiling in the GPT-5.6 family... complex reasoning over large codebases and demanding, long-running agentic work" |
| `gpt-5.6-terra` | advertised | GPT-5.6 Terra | GA | balanced | undocumented | undocumented | planning, implementation, review | "Balanced everyday interactive and agentic coding" |
| `gpt-6-astra` | advertised | GPT-6 Astra | GA | frontier-reasoning | undocumented | undocumented | research, planning, review, council | "Long-horizon, autonomous coding and agentic tasks... continuous planning, batched diagnosis and verification, and independent result confirmation" |
| `gpt-6-luna` | advertised | GPT-6 Luna | GA | fast-lightweight | undocumented | undocumented | intake, bookkeeping | "Fast help with simple or repetitive tasks"; card "Coming soon" |
| `gpt-6-sol` | advertised | GPT-6 Sol | GA | balanced | undocumented | undocumented | planning, implementation, review | "Interactive and agentic coding... all-round development tasks that benefit from careful, multistep validation"; card "Coming soon" |

### Anthropic

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `claude-haiku-4.5` | advertised | Claude Haiku 4.5 | GA | fast-lightweight | undocumented | undocumented | intake, bookkeeping | "Fast help with simple or repetitive tasks... balances fast responses with quality output" |
| `claude-sonnet-4` | constructed | Claude Sonnet 4 | **priced, not in current supported list** — see Contradictions below | balanced | undocumented | undocumented | planning, implementation | Not in the "Supported AI models" table at retrieval; carried here only because the pricing table still names it |
| `claude-sonnet-4.6` | constructed | Claude Sonnet 4.6 | GA (documented, not advertised) | balanced | undocumented | undocumented | planning, implementation, review | "General-purpose coding and agent tasks... reliable completions and smarter reasoning under pressure" |
| `claude-sonnet-5` | advertised | Claude Sonnet 5 | GA | balanced | undocumented | undocumented | planning, implementation, review | "General-purpose coding and agent tasks... complex problem-solving challenges, sophisticated reasoning" |
| `claude-opus-4.7` | advertised | Claude Opus 4.7 | GA | frontier-reasoning | undocumented | undocumented | research, planning, review, council | "Deep reasoning and debugging... Anthropic's most powerful model. Strong at deep reasoning over large, complex codebases" |
| `claude-opus-4.8` | advertised | Claude Opus 4.8 | GA | frontier-reasoning | undocumented | undocumented | research, planning, review, council | "Deep reasoning and debugging... complex problem-solving challenges, sophisticated reasoning" |
| `claude-opus-4.8-fast` | constructed | Claude Opus 4.8 (fast mode) (preview) | preview (documented, not advertised) | frontier-reasoning | undocumented | undocumented | research, planning, review, council | Same task fit as Opus 4.8; priced materially higher (see pricing table) — a latency/cost trade, not a capability difference the sources describe |
| `claude-opus-5` | advertised | Claude Opus 5 | GA | frontier-reasoning | undocumented | undocumented | research, planning, review, council | "Deep reasoning and debugging... complex problem-solving challenges, sophisticated reasoning" |
| `claude-opus-5.5` | advertised | Claude Opus 5.5 | GA | frontier-reasoning | undocumented | undocumented | research, council, review | "Long-running agentic coding and knowledge work... efficient multistep tasks, error recovery, and collaboration" |
| `claude-fable-5` | constructed | Claude Fable 5 | GA (documented, not advertised) | frontier-reasoning | undocumented | undocumented | research, planning | "Long-horizon, autonomous coding and knowledge-work... first-attempt correctness through upfront reasoning, aggressive parallel tool batching"; data-retention terms differ by enterprise configuration (ZDR/EFS) — see source footnote |
| `claude-fable-5.1` | constructed | Claude Fable 5.1 | GA (documented, not advertised) | frontier-reasoning | undocumented | undocumented | research, planning | "Substantial, long-running coding tasks, including deep codebase research, feature development, and complex agentic workflows"; same data-retention note as Claude Fable 5 |

### Google

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `gemini-3.5-flash` | advertised | Gemini 3.5 Flash | GA | fast-lightweight | undocumented | undocumented | intake, bookkeeping | "Fast help with simple or repetitive tasks... fast, reliable answers to lightweight coding questions" |
| `gemini-3.6-flash` | advertised | Gemini 3.6 Flash | GA | balanced | undocumented | undocumented | intake, bookkeeping | Same task-fit text as 3.5/3.7/3.8; priced at the promotional rate through 2026-12-31 (footnote) |
| `gemini-3.7-flash` | advertised | Gemini 3.7 Flash | GA | balanced | undocumented | undocumented | intake, bookkeeping | Same promotional-pricing footnote |
| `gemini-3.8-flash` | advertised | Gemini 3.8 Flash | GA | balanced | undocumented | undocumented | intake, bookkeeping | Same promotional-pricing footnote |

### xAI

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `grok-4.5` | advertised | Grok 4.5 | GA | balanced | undocumented | undocumented | planning, implementation, review | "General-purpose coding and agent tasks... complex problem-solving challenges, sophisticated reasoning" |
| `grok-4.6` | advertised | Grok 4.6 | GA | balanced | undocumented | undocumented | planning, implementation, review | Same task-fit text as 4.5 |
| `grok-4.7` | advertised | Grok 4.7 | GA | balanced | undocumented | undocumented | planning, implementation, review | "Agentic coding and complex, multistep workflows... complex problem-solving challenges, sophisticated reasoning" |

### Microsoft

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `mai-code-1.1-flash` | advertised | MAI-Code-1.1-Flash | GA | fast-lightweight | undocumented | undocumented | intake, bookkeeping | "General-purpose coding and writing, image understanding... fast code completions and explanations, instruction following, tool use"; source footnote: a "continuously improving" checkpoint, behavior may evolve |

### Moonshot AI

| Catalog ID | ID source | Display name | Status | Capability class | Context window | Reasoning effort | Best-fit assignment classes | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `kimi-k2.7-code` | constructed | Kimi K2.7 Code | GA (documented, not advertised) | code-specialized | undocumented | undocumented | implementation | "General-purpose coding and agent tasks... fast, reliable answers to lightweight coding questions"; fine-tuned variants individual-plan-only per source note |
| `kimi-k3` | constructed | Kimi K3 | GA (documented, not advertised) | code-specialized | undocumented | undocumented | implementation | "Agentic coding and long-context work... multi-step agent tasks across large codebases"; source notes elevated risk on certain higher-risk prompts and additional deployed safeguards |

## Catalog: Pricing (USD per 1M tokens)

Every price below is transcribed verbatim from the "Models and pricing" page retrieved 2026-09-27; **`unpriced` never means `0`**. The `Rate-row alias` column names the exact `consumption-rates.md` "Model (as routed)" row this ID prices as — every ID above resolves to exactly one alias here, or is explicitly `unpriced`. `LC threshold` follows the source page's own wording: OpenAI and xAI publish an explicit input-token threshold with a second, higher rate above it (a genuine tiered price); Anthropic and Google publish **no threshold column at all** for any model in this snapshot — that absence is recorded as `none (flat rate)`, a positive confirmation that the tier does not exist today, never a blank cell.

### OpenAI (has a documented long-context tier)

| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output | LC input | LC cached | LC cache write | LC output |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `gpt-5-mini` | GPT-5 mini | none (flat rate) | 0.25 | 0.025 | n/a | 2.00 | n/a | n/a | n/a | n/a |
| `gpt-5.3-codex` | GPT-5.3-Codex | none (flat rate) | 1.75 | 0.175 | n/a | 14.00 | n/a | n/a | n/a | n/a |
| `gpt-5.4` | GPT-5.4 | ≤272K / >272K | 2.50 | 0.25 | n/a | 15.00 | 5.00 | 0.50 | n/a | 22.50 |
| `gpt-5.4-mini` | GPT-5.4 mini | none (flat rate) | 0.75 | 0.075 | n/a | 4.50 | n/a | n/a | n/a | n/a |
| `gpt-5.4-nano` | GPT-5.4 nano | none (flat rate) | 0.20 | 0.02 | n/a | 1.25 | n/a | n/a | n/a | n/a |
| `gpt-5.5` | GPT-5.5 | ≤272K / >272K | 5.00 | 0.50 | n/a | 30.00 | 10.00 | 1.00 | n/a | 45.00 |
| `gpt-5.6-luna` | GPT-5.6 Luna | ≤200K / >200K | 0.20 | 0.02 | 0.25 | 1.20 | 0.40 | 0.04 | 0.50 | 1.80 |
| `gpt-5.6-sol` | GPT-5.6 Sol | ≤272K / >272K | 4.00 | 0.40 | 5.00 | 20.00 | 8.00 | 0.80 | 10.00 | 30.00 |
| `gpt-5.6-terra` | GPT-5.6 Terra | ≤272K / >272K | 2.00 | 0.20 | 2.50 | 12.00 | 4.00 | 0.40 | 5.00 | 18.00 |
| `gpt-6-astra` | GPT-6 Astra | ≤272K / >272K | 10.00 | 1.00 | 12.50 | 50.00 | 20.00 | 2.00 | 25.00 | 75.00 |
| `gpt-6-luna` | GPT-6 Luna | ≤272K / >272K | 0.10 | 0.01 | 0.125 | 0.50 | 0.20 | 0.02 | 0.25 | 0.75 |
| `gpt-6-sol` | GPT-6 Sol | ≤272K / >272K | 2.00 | 0.20 | 2.50 | 10.00 | 4.00 | 0.40 | 5.00 | 15.00 |

### Anthropic (no long-context tier documented — flat rate)

| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `claude-haiku-4.5` | Claude Haiku 4.5 | none (flat rate) | 1.00 | 0.10 | 1.25 | 5.00 |
| `claude-sonnet-4` | Claude Sonnet 4 | none (flat rate) | 3.00 | 0.30 | 3.75 | 15.00 |
| `claude-sonnet-4.6` | Claude Sonnet 4.6 | none (flat rate) | 3.00 | 0.30 | 3.75 | 15.00 |
| `claude-sonnet-5` | Claude Sonnet 5 | none (flat rate) | 2.00 | 0.20 | 2.50 | 10.00 |
| `claude-opus-4.7` | Claude Opus 4.7 | none (flat rate) | 5.00 | 0.50 | 6.25 | 25.00 |
| `claude-opus-4.8` | Claude Opus 4.8 | none (flat rate) | 5.00 | 0.50 | 6.25 | 25.00 |
| `claude-opus-4.8-fast` | Claude Opus 4.8 (fast mode) | none (flat rate) | 10.00 | 1.00 | 12.50 | 50.00 |
| `claude-opus-5` | Claude Opus 5 | none (flat rate) | 5.00 | 0.50 | 6.25 | 25.00 |
| `claude-opus-5.5` | Claude Opus 5.5 | none (flat rate) | 4.00 | 0.20 | 5.00 | 20.00 |
| `claude-fable-5` | Claude Fable 5 | none (flat rate) | 10.00 | 1.00 | 12.50 | 50.00 |
| `claude-fable-5.1` | Claude Fable 5.1 | none (flat rate) | 10.00 | 0.25 | 12.50 | 50.00 |

### Google (no long-context tier documented — flat rate)

| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `gemini-3.5-flash` | Gemini 3.5 Flash | none (flat rate) | 1.50 | 0.15 | 0 | 9.00 |
| `gemini-3.6-flash` | Gemini 3.6 Flash | none (flat rate) | 0.75 | 0.075 | 0 | 3.75 |
| `gemini-3.7-flash` | Gemini 3.7 Flash | none (flat rate) | 0.75 | 0.075 | 0 | 3.75 |
| `gemini-3.8-flash` | Gemini 3.8 Flash | none (flat rate) | 0.75 | 0.075 | 0 | 3.75 |

Gemini 3.6/3.7/3.8 Flash are priced at a promotional rate ($0.75 / $0.075 / – / $3.75) through 2026-12-31 per the source page's footnote; the table above records that promotional rate as observed, not a projected post-promotion rate, since no post-promotion figure is published yet.

### xAI (has a documented long-context tier)

| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output | LC input | LC cached | LC cache write | LC output |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `grok-4.5` | Grok 4.5 | ≤200K / >200K | 2.00 | 0.50 | n/a | 6.00 | 4.00 | 1.00 | n/a | 12.00 |
| `grok-4.6` | Grok 4.6 | ≤200K / >200K | 2.00 | 0.50 | n/a | 6.00 | 4.00 | 1.00 | n/a | 12.00 |
| `grok-4.7` | Grok 4.7 | ≤200K / >200K | 2.00 | 0.50 | n/a | 6.00 | 4.00 | 1.00 | n/a | 12.00 |

### Microsoft and Moonshot AI (no long-context tier documented — flat rate)

| Catalog ID | Rate-row alias | LC threshold | Input | Cached | Cache write | Output |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `mai-code-1.1-flash` | MAI-Code-1.1-Flash | none (flat rate) | 0.20 | 0.02 | 0 | 1.20 |
| `kimi-k2.7-code` | Kimi K2.7 Code | none (flat rate) | 0.95 | 0.19 | 0 | 4.00 |
| `kimi-k3` | Kimi K3 | none (flat rate) | 3.00 | 0.30 | 0 | 15.00 |

## Advertised but Unevaluated

This host's `task` dispatch tool advertises `model` values that this snapshot's three sources do not document at all. Each is `unevaluated`: excluded from automatic ranking, priced `unpriced` (never `0`), and reachable only via an explicit `models=` override.

| Advertised ID | Why unevaluated | Price |
| --- | --- | --- |
| `gpt-5.6-sol-fast` | No "GPT-5.6 Sol (fast mode)" or equivalent variant appears in "Supported AI models," "Models and pricing," or "AI model comparison" at retrieval. A fast-mode variant exists for Claude Opus 4.8 in these sources, but no analogous GPT-5.6 Sol variant is documented. | unpriced |

## Documented but Not Advertised

These models are named by at least one of the three sources but are not in this CLI host's advertised `model` enum today. They stay in the catalog — per the host-neutral principle above, host-availability filtering happens in the routing procedure, never by deleting a row here.

| Catalog ID | Display name | Why not advertised (as observed, not asserted) |
| --- | --- | --- |
| `gpt-5.4-nano` | GPT-5.4 nano | Not in this host's `model` enum at retrieval; documented and priced normally |
| `claude-sonnet-4` | Claude Sonnet 4 | Not in this host's `model` enum; also absent from "Supported AI models" (see Contradictions) |
| `claude-sonnet-4.6` | Claude Sonnet 4.6 | Not in this host's `model` enum at retrieval; documented and priced normally |
| `claude-opus-4.8-fast` | Claude Opus 4.8 (fast mode) (preview) | Preview status; not in this host's `model` enum at retrieval |
| `claude-fable-5` | Claude Fable 5 | Enterprise-gated data-retention model; not in this host's `model` enum at retrieval |
| `claude-fable-5.1` | Claude Fable 5.1 | Same gating as Claude Fable 5; not in this host's `model` enum at retrieval |
| `kimi-k2.7-code` | Kimi K2.7 Code | Not in this host's `model` enum at retrieval; documented and priced normally |
| `kimi-k3` | Kimi K3 | Not in this host's `model` enum at retrieval; source notes elevated-risk safeguards |

## Named Only in the Comparison Guide (Degraded Confidence)

| Catalog ID | Display name | Why degraded | Price |
| --- | --- | --- | --- |
| `qwen2.5` | Qwen2.5 | Appears in the "AI model comparison" page's recommended-models table (task area: general-purpose coding and writing) but is absent from both "Supported AI models" and "Models and pricing" at retrieval — named by only one of the three sources, with no corroborating pricing or supported-status row | unpriced |

## Contradictions and Notes Observed at Retrieval

* **Claude Sonnet 4 is priced but not currently supported.** The "Models and pricing" page's Anthropic table carries a Claude Sonnet 4 row ($3.00 / $0.30 / $3.75 / $15.00), but the "Supported AI models" table does not list Claude Sonnet 4 among the current Anthropic offering (it lists Claude Sonnet 4.6 and Claude Sonnet 5 instead). This catalog records both facts rather than silently dropping the model or inferring a status the sources do not state; treat this row cautiously pending the cost-manager review (D4).
* **`Gemini 3.1 Pro` in the existing `consumption-rates.md` template does not appear in any of the three sources fetched for this snapshot.** Google's current pricing table lists only Flash-tier models (3.5/3.6/3.7/3.8). This catalog does not add a `gemini-3.1-pro` row and does not reprice the existing template row (no current official source to reprice it against); the existing row is flagged for cost-manager attention in this delivery's change record rather than deleted or guessed at.
* **Qwen2.5** is named only in "AI model comparison," not in "Supported AI models" or "Models and pricing" — see the degraded-confidence section above.

## Squad Assignment Classes Referenced Above

`research`, `planning`, `implementation`, `review`, `council`, `intake`, `bookkeeping` — the seven fixed assignment classes this catalog's "best-fit assignment classes" column draws from, per the routing policy this catalog is declared to support (`model-routing.md`, delivered separately). This catalog does not define per-assignment consequence floors; those live in `team.md`'s Model Tier column and are independent of anything this catalog contains.
