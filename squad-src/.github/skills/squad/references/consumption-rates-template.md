---
name: squad-consumption-rates-template
description: "Cold seed template for consumption-rates.md: per-model token rates, the tier-fallback table, the dispatch-size estimator, and the calibration block."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-09-30"
---

# Squad Consumption Rates Template

This is the literal seed content for a squad root's `consumption-rates.md` — the Scribe copies the fenced block below verbatim at Init and at every sub-squad seeding or federation promotion, and reseeds it (Step 7.1) whenever the existing file fails its shape check: it must carry a per-model rate table with `Input`, `Cached`, `Cache write`, and `Output` columns, a tier-fallback table, a dispatch-size estimator, and a calibration block. Preserve the calibration block across a reseed rather than resetting it to the template's placeholder values.

**Seed with the script when `pwsh` 7+ is available.** Run `scripts/Initialize-SquadConsumptionRates.ps1 -SquadRoot <squadRoot>` from the installed squad skill: it extracts the fenced block below byte-for-byte, writes `consumption-rates.md`, leaves a file that already passes the shape check alone, carries the calibration block across (resetting it only when its observations were measured against a different basis, per the Calibration section), and exits non-zero on failure. `-Reseed` forces a rewrite and `-Check` validates the shape read-only. A well-formed per-model row an operator adds for a newly released model is kept across a reseed and only warns in `-Check`; a missing template row fails. A malformed operator row is never deleted silently: the script exits non-zero, names each row, and leaves the file untouched; **surface that message in your confirmation**, leave the rate file as it is, and report the ledger `unverified` until the operator fixes or removes the row (or approves `-DropMalformedRows`, which rewrites and prints a `Dropped malformed operator row` note you must also surface). A model-authored rate table has repeatedly come back with invented rows or no per-model table, so never compose one; the verbatim copy described above is the fallback only when no shell or `pwsh` 7+ is available.

**This file is cold.** It is read only on initialization and at a Step 7.1 reseed — never for an ordinary decision or history dispatch. `consumption.md` stays hot (read on every history dispatch) and carries the derivation math, the orchestration-overhead and cost-formula guidance, and Cost Preflight, none of which are part of what gets copied to `consumption-rates.md`.

````markdown
---
description: "Per-model token rates, dispatch-size estimator, and calibration factor for squad consumption estimates"
---

# Consumption Rates (verify against the current GitHub Copilot "Models and pricing" docs)

* Billing model: usage-based billing (UBB), token-metered, effective 2026-06-01.
* Observed-on: 2026-09-30. Source: <https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing>
* Credit conversion: 1 AI credit = $0.01 USD (fixed).
* All rates are USD per 1M tokens. Anthropic models bill a separate cache-write rate on top of cached input; models without one leave the column at 0.
* `Observed-on:` above must equal `model-catalog.md`'s `Retrieved:` date exactly, not merely "close" — both are `2026-09-30` as of this snapshot; a future re-verification that updates one must update the other in the same change.

## Per-model token rates in USD per 1M tokens (volatile, verify before commit)

`Model ID` is the exact dispatch id the Copilot CLI and the GitHub Copilot app accept, and the only value a `team.md` `Model` cell may hold under `routing=ranked` or `routing=manual` (see `model-routing.md`); `Model (as routed)` stays the row key and the display name VS Code's picker shows. `—` marks a retired row no host can dispatch. `LC Threshold` and the `LC *` columns record GitHub's own long-context tier: an explicit higher input-token threshold and a second, higher rate above it. Only OpenAI and xAI publish one. Anthropic and Google publish no threshold column at all for any model in this table — `none (flat rate)` is a positive confirmation of that absence, never a blank cell standing in for "unknown." `Tier` here is this table's own cost-based routing bucket (`fast`/`default`/`extended`), independent of the vendor's own capability category on the official page; a model's `Tier` need not match its `model-catalog.md` capability class.

| Model (as routed) | Model ID             | Tier     | Input | Cached | Cache write | Output | LC Threshold      | LC Input | LC Cached | LC Cache write | LC Output | Notes                      |
| ------------------ | -------------------- | -------- | ----- | ------ | ----------- | ------ | ----------------- | -------- | --------- | --------------- | --------- | -------------------------- |
| GPT-5.4 nano        | `gpt-5.4-nano`       | fast     | 0.20  | 0.02   | 0           | 1.25   | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | lightweight, read-heavy    |
| GPT-5.4 mini        | `gpt-5.4-mini`       | fast     | 0.75  | 0.075  | 0           | 4.50   | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | lightweight                |
| Claude Haiku 4.5    | `claude-haiku-4.5`   | fast     | 1.00  | 0.10   | 1.25        | 5.00   | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | lightweight reasoning      |
| Claude Sonnet 4.6   | `claude-sonnet-4.6`  | default  | 3.00  | 0.30   | 3.75        | 15.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | versatile                  |
| Claude Sonnet 5     | `claude-sonnet-5`    | default  | 2.00  | 0.20   | 2.50        | 10.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | versatile (promo pricing)  |
| Claude Sonnet 5.5   | `claude-sonnet-5.5`  | default  | 2.00  | 0.20   | 2.50        | 10.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | versatile                  |
| GPT-5.4             | `gpt-5.4`            | default  | 2.50  | 0.25   | 0           | 15.00  | \<=272K / >272K   | 5.00     | 0.50      | n/a             | 22.50     | versatile                  |
| Gemini 3.1 Pro (retired) | —                    | default  | 2.00  | 0.20   | 0           | 12.00  | not currently listed | n/a  | n/a       | n/a             | n/a       | Deprecated 2026-09-27; no longer in official GitHub Copilot offering. Preserved for backward compatibility with existing consumption ledgers referencing this rate row. |
| Claude Opus 4.8     | `claude-opus-4.8`    | extended | 5.00  | 0.50   | 6.25        | 25.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | high-capability reasoning  |
| Claude Opus 5       | `claude-opus-5`      | extended | 5.00  | 0.50   | 6.25        | 25.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | high-capability reasoning  |
| GPT-5.5             | `gpt-5.5`            | extended | 5.00  | 0.50   | 0           | 30.00  | \<=272K / >272K   | 10.00    | 1.00      | n/a             | 45.00     | high-capability reasoning  |
| GPT-5 mini          | `gpt-5-mini`         | fast     | 0.25  | 0.025  | 0           | 2.00   | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | lightweight, deep-reasoning-capable |
| GPT-5.3-Codex       | `gpt-5.3-codex`      | fast     | 1.75  | 0.175  | 0           | 14.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | code-specialized, agentic; Auto-selection LTS fallback |
| GPT-5.6 Luna        | `gpt-5.6-luna`       | fast     | 0.20  | 0.02   | 0.25        | 1.20   | \<=200K / >200K   | 0.40     | 0.04      | 0.50            | 1.80      | lightweight                |
| GPT-5.6 Sol         | `gpt-5.6-sol`        | extended | 4.00  | 0.40   | 5.00        | 20.00  | \<=272K / >272K   | 8.00     | 0.80      | 10.00           | 30.00     | high-capability reasoning  |
| GPT-5.6 Terra       | `gpt-5.6-terra`      | default  | 2.00  | 0.20   | 2.50        | 12.00  | \<=272K / >272K   | 4.00     | 0.40      | 5.00            | 18.00     | versatile                  |
| GPT-6 Astra         | `gpt-6-astra`        | extended | 10.00 | 1.00   | 12.50       | 50.00  | \<=272K / >272K   | 20.00    | 2.00      | 25.00           | 75.00     | high-capability reasoning  |
| GPT-6 Luna          | `gpt-6-luna`         | fast     | 0.10  | 0.01   | 0.125       | 0.50   | \<=272K / >272K   | 0.20     | 0.02      | 0.25            | 0.75      | lightweight                |
| GPT-6 Sol           | `gpt-6-sol`          | default  | 2.00  | 0.20   | 2.50        | 10.00  | \<=272K / >272K   | 4.00     | 0.40      | 5.00            | 15.00     | versatile                  |
| GPT-6.1 Sol         | `gpt-6.1-sol`        | default  | 2.00  | 0.10   | 2.50        | 10.00  | \<=272K / >272K   | 4.00     | 0.20      | 5.00            | 15.00     | high-capability coding, efficient reasoning |
| Claude Opus 4.7     | `claude-opus-4.7`    | extended | 5.00  | 0.50   | 6.25        | 25.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | high-capability reasoning  |
| Claude Opus 4.8 (fast mode) | `claude-opus-4.8-fast` | extended | 10.00 | 1.00 | 12.50   | 50.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | high-capability reasoning, preview, latency-optimized |
| Claude Opus 5.5     | `claude-opus-5.5`    | extended | 4.00  | 0.20   | 5.00        | 20.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | high-capability, long-running agentic |
| Claude Sonnet 4     | `claude-sonnet-4`    | default  | 3.00  | 0.30   | 3.75        | 15.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | Priced per official GitHub Copilot billing docs but not in current "Supported AI models" list as of 2026-09-27. Preserved for backward compatibility; new routing should prefer Claude Sonnet 4.6 or Claude Sonnet 5. See model-catalog.md Contradictions. |
| Claude Fable 5      | `claude-fable-5`     | extended | 10.00 | 1.00   | 12.50       | 50.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | high-capability, enterprise data-retention gating (ZDR/EFS) |
| Claude Fable 5.1    | `claude-fable-5.1`   | extended | 10.00 | 0.25   | 12.50       | 50.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | high-capability, same data-retention gating as Claude Fable 5 |
| Gemini 3.5 Flash    | `gemini-3.5-flash`   | fast     | 1.50  | 0.15   | 0           | 9.00   | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | lightweight                |
| Gemini 3.6 Flash    | `gemini-3.6-flash`   | fast     | 0.75  | 0.075  | 0           | 3.75   | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | versatile; promotional rate through 2026-12-31 |
| Gemini 3.7 Flash    | `gemini-3.7-flash`   | fast     | 0.75  | 0.075  | 0           | 3.75   | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | versatile; promotional rate through 2026-12-31 |
| Gemini 3.8 Flash    | `gemini-3.8-flash`   | fast     | 0.75  | 0.075  | 0           | 3.75   | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | versatile; promotional rate through 2026-12-31 |
| MAI-Code-1.1-Flash  | `mai-code-1.1-flash` | fast     | 0.20  | 0.02   | 0           | 1.20   | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | lightweight, code-specialized; continuously-improving checkpoint |
| Grok 4.5            | `grok-4.5`           | default  | 2.00  | 0.50   | 0           | 6.00   | \<=200K / >200K   | 4.00     | 1.00      | n/a             | 12.00     | versatile                  |
| Grok 4.6            | `grok-4.6`           | default  | 2.00  | 0.50   | 0           | 6.00   | \<=200K / >200K   | 4.00     | 1.00      | n/a             | 12.00     | versatile                  |
| Grok 4.7            | `grok-4.7`           | default  | 2.00  | 0.50   | 0           | 6.00   | \<=200K / >200K   | 4.00     | 1.00      | n/a             | 12.00     | versatile                  |
| Kimi K2.7 Code      | `kimi-k2.7-code`     | fast     | 0.95  | 0.19   | 0           | 4.00   | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | code-specialized           |
| Kimi K3             | `kimi-k3`            | default  | 3.00  | 0.30   | 0           | 15.00  | none (flat rate)  | n/a      | n/a       | n/a             | n/a       | code-specialized, long-context agentic; elevated-risk safeguards per source |
| (additional)        |                      |          |       |        |             |        |                    |          |           |                 |           | update when GitHub changes |

## Tier fallback rates (used only when `basis: tier-default`)

A tier is a routing preference, not a price. When the actual model is unknown, price the tier at its **most expensive member** rather than a blend: the observed failure mode of this ledger is undercounting, so the fallback is deliberately conservative-high and every row it produces is flagged `basis: tier-default`.

The `Priced as` column below names a model for **pricing only**. Never write it into a consumption block's `model` field — that field records what actually ran and is resolved per *Model Attribution* in `.github/instructions/squad/squad-state.instructions.md`, or left as the literal `unknown`. Copying a `Priced as` name into `model` is exactly the fabrication that makes a ledger report spend against a model the operator never chose.

| Tier     | Priced as         | Input | Cached | Cache write | Output |
| -------- | ----------------- | ----- | ------ | ----------- | ------ |
| fast     | Claude Haiku 4.5  | 1.00  | 0.10   | 1.25        | 5.00   |
| default  | Claude Sonnet 4.6 | 3.00  | 0.30   | 3.75        | 15.00  |
| extended | Claude Opus 5     | 5.00  | 0.50   | 6.25        | 25.00  |

## Dispatch-size estimator

A dispatch is **not one model call**. A dispatched subagent runs an internal tool loop, and every internal turn resends the accumulated context. Input therefore scales with `internal_turns × average_context`, not with a single prompt-and-reply pair. Pricing a dispatch as one call is what makes a ledger read an order of magnitude below the bill.

```text
tokens(bytes)      = bytes / 4
base_context       = agent prompt + auto-applied instructions + loaded skill content
average_context    = base_context + growth_per_turn × (internal_turns - 1) / 2
gross_input        = internal_turns × average_context
```

Split `gross_input` across the billed rates. Turn 1 is fully uncached; on turns 2..n the carried-forward prefix is a cached read and only the new tool result is fresh input:

```text
cached_tokens      = gross_input × 0.80
input_tokens       = gross_input × 0.20
cache_write_tokens = base_context + growth_per_turn × (internal_turns - 1)   (Anthropic models only; 0 otherwise)
output_tokens      = internal_turns × output_per_turn
```

Estimate `internal_turns` and `base_context` from what the dispatch actually reported. These class rows are **floors, not fallbacks** — start here and raise, never start below:

| Dispatch class            | Internal turns | Base context | Growth/turn | Output/turn |
| ------------------------- | -------------- | ------------ | ----------- | ----------- |
| Lookup / single-file read | 3              | 20,000       | 3,000       | 800         |
| Research / file survey    | 12             | 40,000       | 4,000       | 1,250       |
| Plan / synthesis          | 15             | 60,000       | 4,000       | 2,000       |
| Implement / edit loop     | 35             | 60,000       | 6,000       | 2,000       |
| Review / verification     | 18             | 50,000       | 4,000       | 1,500       |
| Council member opinion    | 10             | 50,000       | 4,000       | 1,500       |
| Scribe state write        | 4              | 15,000       | 3,000       | 800         |

Observable proxies that raise a floor whenever available: the number of files the agent reported reading and their byte size, the byte size of artifacts it wrote, the count of tool calls it reported, and the length of the findings it returned.

**Validity check.** After estimating, confirm `gross_input / internal_turns >= base_context` for the class. A derived average context below the floor means the dispatch was sized from the summary the coordinator handed over rather than from the dispatch's own context. That summary is a report *about* the dispatch, not the context the dispatch ran on — an agent's prompt plus its auto-applied instructions already exceeds most floors before it reads a single file. When the check fails, raise the numbers and recompute rather than recording the smaller figure.

## Calibration

```yaml
calibration_factor: 1.00
last_reconciled: never
observations: 0
estimator_revision: 2
calibration_basis: "<observed-on>|2"
```

The factor is the running mean of `observed_credits / estimated_credits` across reconciled runs, clamped to the range 0.25-10.0. To reconcile: read the per-user aggregate `ai_credits_used` from the Copilot usage-metrics REST API immediately before and after a run, take the delta as `observed_credits`, divide by the run's `est_credits` total, fold that ratio into the mean, and rewrite this block. Until `observations` is at least 1 the factor stays 1.00 and the ledger carries an "uncalibrated" note.

`calibration_basis` binds those observations to the rate table's `Observed-on` value and `estimator_revision`, joined with `|`. A calibration is eligible for Cost Preflight only when `observations` is positive, `last_reconciled` is not `never`, and the stored basis exactly matches the current rate and estimator basis. When a rate-table reseed or estimator revision changes that basis, reset `calibration_factor` to `1.00`, `last_reconciled` to `never`, and `observations` to `0` rather than applying an old factor to a new calculation.
````
