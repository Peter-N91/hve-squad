# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Generates a schema-correct squad state tree, and mutates it.
#
# Every number below is internally consistent so the arithmetic cases have something
# true to verify against:
#   researcher    (10000 x 3.0 + 5000 x 0.3 + 1000 x 3.75 + 2000 x 15.0) / 1e6 = 0.06525
#   orchestration ( 4000 x 3.0 +                            1000 x 15.0) / 1e6 = 0.02700
#   run total                                                                   = 0.09225
# and est_credits is est_cost_usd / 0.01 throughout.

#Requires -Version 7.4

Set-StrictMode -Version Latest

function New-SquadStateFixture {
    <#
    .SYNOPSIS
        Writes a schema-correct squad state tree and returns its root.
    .PARAMETER Path
        Directory to create the squad root in. Created if absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $root = Join-Path $Path '.copilot-tracking/squad'
    New-Item -ItemType Directory -Path (Join-Path $root 'history') -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $root 'team.md') -Encoding utf8NoBOM -Value @'
---
description: "Squad roster: roles and the deployed HVE Core agents that fill them"
---

# Squad Roster

## Members

| Role        | Member Name | Agent Name (Primary) | Alternate Agents | Invocation  | Model Tier | Deliverable Root            |
|-------------|-------------|----------------------|------------------|-------------|------------|-----------------------------|
| researcher  |             | Squad Researcher     |                  | runSubagent | fast       | `.copilot-tracking/research/` |
| lead        |             | Squad Lead           |                  | runSubagent | default    | `.copilot-tracking/plans/`    |
| scribe      |             | Squad Scribe         |                  | runSubagent | fast       | `.copilot-tracking/squad/`    |
'@

    Set-Content -LiteralPath (Join-Path $root 'routing.md') -Encoding utf8NoBOM -Value @'
---
description: "Squad routing: request patterns mapped to roles, autonomy tiers, and parallel eligibility"
---

# Squad Routing

| Pattern / Keyword                        | Role(s)    | Autonomy Tier | Parallel-Eligible |
|------------------------------------------|------------|---------------|-------------------|
| research, investigate, explore, find out | researcher | auto          | yes               |
| plan, break down, sequence, design plan  | lead       | confirm       | no                |
'@

    Set-Content -LiteralPath (Join-Path $root 'decisions.md') -Encoding utf8NoBOM -Value @'
---
description: "Append-only log of squad decisions and their rationale"
---

# Squad Decisions

## 2026-08-19T10:00:00Z Route research request to researcher

* Turn: 1
* Rationale: The request matched the research routing pattern at the auto tier.
'@

    Set-Content -LiteralPath (Join-Path $root 'notifications.md') -Encoding utf8NoBOM -Value @'
---
description: "Append-only log of notifications fired and their delivery channel"
---

# Squad Notifications
'@

    Set-Content -LiteralPath (Join-Path $root 'state.json') -Encoding utf8NoBOM -Value @'
{
  "schemaVersion": "1.3",
  "updated": "2026-08-19T10:00:05Z",
  "turn": 1,
  "mode": "interactive",
  "activeRoles": [ "researcher" ],
  "openEscalations": [],
  "currentRun": {
    "sessionModel": "claude-sonnet-5",
    "modelOverrides": {},
    "estCostUsd": 0.09225,
    "estCreditsTotal": 9.225
  },
  "notify": {
    "approvalChannel": "in-chat",
    "enabled": false,
    "email": "",
    "github": { "handle": "", "repo": "" }
  }
}
'@

    Set-Content -LiteralPath (Join-Path $root 'consumption-rates.md') -Encoding utf8NoBOM -Value @'
---
description: "Per-model token rates, dispatch-size estimator, and calibration factor for squad consumption estimates"
---

# Consumption Rates

## Per-model token rates in USD per 1M tokens

| Model           | Input | Cached | Cache write | Output |
|-----------------|-------|--------|-------------|--------|
| claude-sonnet-5 | 3.00  | 0.30   | 3.75        | 15.00  |
| gpt-5.4         | 1.25  | 0.13   | 0.00        | 10.00  |

## Tier fallback rates (used only when `basis: tier-default`)

| Tier    | Priced as       |
|---------|-----------------|
| fast    | claude-sonnet-5 |
| default | claude-sonnet-5 |

## Dispatch-size estimator

Token counts are estimated from dispatch class; no per-dispatch telemetry exists.

## Calibration

* calibration_factor: 1.00
* observations: 0

Uncalibrated: the factor stays 1.00 until at least one run is reconciled.
'@

    Set-Content -LiteralPath (Join-Path $root 'consumption.md') -Encoding utf8NoBOM -Value @'
---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: fixture-001)

## Attribution

| Role          | Member | Agent                          | Model           | Model Source      | Priced As | Tier  |
| ------------- | ------ | ------------------------------ | --------------- | ----------------- | --------- | ----- |
| researcher    |        | Squad Researcher               | claude-sonnet-5 | dispatch-reported |           | fast  |
| orchestration |        | Squad Coordinator + Squad Scribe | claude-sonnet-5 | session-inherited |           | mixed |

## Usage & Cost

| Role          | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------ | -------- | ---------- | --------------- | ------------ | --------- |
| researcher    | 1     | 10000     | 5000   | 1000     | 2000       | 0.0653          | 6.53         | estimated |
| orchestration | 1     | 4000      | 0      | 0        | 1000       | 0.0270          | 2.70         | estimated |
| **Total**     | **2** | **14000** | **5000** | **1000** | **3000**   | **$0.0923**     | **9.23**     |           |

> Basis: estimated. No per-dispatch token telemetry exists.
'@

    Set-Content -LiteralPath (Join-Path $root 'history/squad-researcher.md') -Encoding utf8NoBOM -Value @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: Squad Researcher

## 2026-08-19T10:00:03Z Investigate the login validation path

* Turn: 1
* Request: Investigate how login input is validated today.
* Outcome: Wrote `.copilot-tracking/research/2026-08-19-login-validation.md`.

#### Consumption

```json
{
  "model": "claude-sonnet-5",
  "model_source": "dispatch-reported",
  "priced_as": "",
  "model_tier": "fast",
  "internal_turns": 1,
  "input_tokens": 10000,
  "cached_tokens": 5000,
  "cache_write_tokens": 1000,
  "output_tokens": 2000,
  "input_rate": 3.0,
  "cached_rate": 0.3,
  "cache_write_rate": 3.75,
  "output_rate": 15.0,
  "est_cost_usd": 0.06525,
  "est_credits": 6.525,
  "basis": "estimated"
}
```
'@

    Set-Content -LiteralPath (Join-Path $root 'history/squad-scribe.md') -Encoding utf8NoBOM -Value @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: Squad Scribe

## 2026-08-19T10:00:05Z Persist turn 1

* Turn: 1
* Request: Record the researcher dispatch and advance state.
* Outcome: Appended history, rewrote the ledger, advanced `state.json`.

#### Consumption — Orchestration

```json
{
  "model": "claude-sonnet-5",
  "model_source": "session-inherited",
  "priced_as": "",
  "model_tier": "mixed",
  "internal_turns": 1,
  "input_tokens": 4000,
  "cached_tokens": 0,
  "cache_write_tokens": 0,
  "output_tokens": 1000,
  "input_rate": 3.0,
  "cached_rate": 0.3,
  "cache_write_rate": 3.75,
  "output_rate": 15.0,
  "est_cost_usd": 0.027,
  "est_credits": 2.7,
  "basis": "estimated"
}
```
'@

    $root
}

Export-ModuleMember -Function New-SquadStateFixture
