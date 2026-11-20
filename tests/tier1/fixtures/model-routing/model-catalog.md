<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->
# Frozen model-routing policy fixture

* **Retrieved: 2026-10-19**

These rows are synthetic contract data for policy tests. They intentionally
preserve retired model IDs so live catalog refreshes cannot rewrite the test
scenario being exercised.

## Capability

| Catalog ID | Display name | Capability class |
| --- | --- | --- |
| `gpt-5.3-codex` | GPT-5.3 Codex | code-specialized |
| `gpt-5.4-nano` | GPT-5.4 Nano | fast-lightweight |
| `gpt-5.6-luna` | GPT-5.6 Luna | fast-lightweight |
| `gpt-5.6-sol` | GPT-5.6 Sol | frontier-reasoning |
| `gpt-5.6-terra` | GPT-5.6 Terra | balanced |
| `gpt-6-luna` | GPT-6 Luna | fast-lightweight |
| `gpt-6-sol` | GPT-6 Sol | balanced |
| `gpt-6.1-sol` | GPT-6.1 Sol | frontier-reasoning |
| `claude-fable-5` | Claude Fable 5 | frontier-reasoning |
| `claude-haiku-5.5` | Claude Haiku 5.5 | fast-lightweight |
| `claude-opus-4.8` | Claude Opus 4.8 | frontier-reasoning |
| `claude-opus-5` | Claude Opus 5 | frontier-reasoning |
| `claude-sonnet-5.5` | Claude Sonnet 5.5 | balanced |
| `gemini-4-argon` | Gemini 4 Argon | frontier-reasoning |
| `mai-code-1.1-flash` | MAI-Code-1.1-Flash | fast-lightweight |

## Pricing

| Catalog ID | Rate-row alias | Input |
| --- | --- | ---: |
| `gpt-5.3-codex` | GPT-5.3 Codex | 1.75 |
| `gpt-5.4-nano` | GPT-5.4 Nano | 0.20 |
| `gpt-5.6-luna` | GPT-5.6 Luna | 0.20 |
| `gpt-5.6-sol` | GPT-5.6 Sol | 4.00 |
| `gpt-5.6-terra` | GPT-5.6 Terra | 2.00 |
| `gpt-6-luna` | GPT-6 Luna | 0.10 |
| `gpt-6-sol` | GPT-6 Sol | 2.00 |
| `gpt-6.1-sol` | GPT-6.1 Sol | 2.00 |
| `claude-fable-5` | Claude Fable 5 | 10.00 |
| `claude-haiku-5.5` | Claude Haiku 5.5 | 0.10 |
| `claude-opus-4.8` | Claude Opus 4.8 | 5.00 |
| `claude-opus-5` | Claude Opus 5 | 5.00 |
| `claude-sonnet-5.5` | Claude Sonnet 5.5 | 2.00 |
| `gemini-4-argon` | Gemini 4 Argon | 2.00 |
| `mai-code-1.1-flash` | MAI-Code-1.1-Flash | 0.20 |

## Catalog: Assignment Fit

| Catalog ID | Family | Generation | research | planning | implementation | review | council | intake | bookkeeping | Blended |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `gpt-5.3-codex` | gpt-codex | 5.3 | 1 | 1 | 3 | 2 | 0 | 1 | 0 | 0.770 |
| `gpt-5.4-nano` | gpt-nano | 5.4 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 0.081 |
| `gpt-5.6-luna` | gpt-luna | 5.6 | 0 | 0 | 1 | 0 | 0 | 1 | 2 | 0.100 |
| `gpt-5.6-sol` | gpt-sol | 5.6 | 3 | 3 | 2 | 3 | 2 | 2 | 0 | 1.920 |
| `gpt-5.6-terra` | gpt-terra | 5.6 | 1 | 2 | 2 | 2 | 1 | 3 | 0 | 1.000 |
| `gpt-6-luna` | gpt-luna | 6 | 0 | 0 | 1 | 0 | 0 | 1 | 2 | 0.048 |
| `gpt-6-sol` | gpt-sol | 6 | 1 | 2 | 3 | 3 | 2 | 2 | 0 | 0.960 |
| `gpt-6.1-sol` | gpt-sol | 6.1 | 2 | 2 | 3 | 2 | 2 | 2 | 0 | 0.880 |
| `claude-fable-5` | claude-fable | 5 | 3 | 3 | 2 | 2 | 2 | 1 | 0 | 4.800 |
| `claude-haiku-5.5` | claude-haiku | 5.5 | 1 | 0 | 1 | 1 | 0 | 2 | 3 | 0.048 |
| `claude-opus-4.8` | claude-opus | 4.8 | 2 | 3 | 2 | 3 | 3 | 2 | 0 | 2.400 |
| `claude-opus-5` | claude-opus | 5 | 3 | 3 | 2 | 3 | 3 | 2 | 0 | 2.400 |
| `claude-sonnet-5.5` | claude-sonnet | 5.5 | 2 | 2 | 3 | 2 | 2 | 3 | 0 | 0.880 |
| `gemini-4-argon` | gemini-argon | 4 | 2 | 3 | 3 | 3 | 2 | 2 | 0 | 0.880 |
| `mai-code-1.1-flash` | mai-code-flash | 1.1 | 0 | 0 | 1 | 0 | 0 | 1 | 2 | 0.080 |
