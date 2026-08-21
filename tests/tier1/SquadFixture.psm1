# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Generates a schema-correct squad state tree, and mutates it.
#
# Every number below is internally consistent so the arithmetic cases have something
# true to verify against. Cost lives only in the ledger, derived per row from that
# row's tokens and the rates of the model its Attribution row names:
#   researcher    (10000 x 3.0 + 5000 x 0.3 + 1000 x 3.75 + 2000 x 15.0) / 1e6 = 0.06525
#   orchestration ( 4000 x 3.0 +                            1000 x 15.0) / 1e6 = 0.02700
#   run total                                                                   = 0.09225
# and est_credits is est_cost_usd / 0.01 throughout.
#
# The rate table is lifted from the shipped skill rather than written here. A
# hand-written one drifted from the product's shape and the contract's reader was
# tuned to the fixture instead of to the file a real squad seeds, so the self-check
# stayed green while not one real rate could be read.

#Requires -Version 7.4

Set-StrictMode -Version Latest

function Get-ShippedRateTemplate {
    <#
    .SYNOPSIS
        Lifts the consumption-rates.md seed template out of the shipped squad skill.
    #>
    [CmdletBinding()]
    param()

    $reference = Join-Path $PSScriptRoot '..' '..' 'squad-src' '.github' 'skills' 'squad' 'references' 'consumption.md'
    if (-not (Test-Path -LiteralPath $reference)) {
        throw "The shipped consumption reference was not found at '$reference'."
    }

    $match = [regex]::Match(
        (Get-Content -LiteralPath $reference -Raw),
        '(?ms)^##\s+consumption-rates\.md\s*$.*?^````markdown\r?\n(?<body>.*?)\r?\n````\s*$')

    if (-not $match.Success) {
        throw "Could not extract the consumption-rates.md template from '$reference'."
    }

    $match.Groups['body'].Value
}

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

    # The artifact the researcher entry declares. Proof of dispatch is the entry and the
    # file together, so a fixture without the file cannot exercise either direction of
    # the Deliverable Root reconciliation.
    $research = Join-Path $Path '.copilot-tracking/research'
    New-Item -ItemType Directory -Path $research -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $research '2026-08-19-login-validation.md') -Encoding utf8NoBOM -Value @'
---
description: "Research: login validation path"
---

# Login Validation Path

Input reaches the validator through a single entry point.
'@

    Set-Content -LiteralPath (Join-Path $root 'team.md') -Encoding utf8NoBOM -Value @'
---
description: "Squad roster: roles and the deployed HVE Core agents that fill them"
---

# Squad Roster

## Members

| Role        | Member Name | Agent Name (Primary) | Alternate Agents | Selection Cue                                       | Invocation  | Model Tier | Deliverable Root            |
|-------------|-------------|----------------------|------------------|-----------------------------------------------------|-------------|------------|-----------------------------|
| researcher  |             | Squad Researcher     |                  | —                                                   | runSubagent | fast       | `.copilot-tracking/research/` |
| lead        |             | Squad Lead           | RPI Planner      | revise one phase of an existing plan → RPI Planner  | runSubagent | default    | `.copilot-tracking/plans/`    |
| scribe      |             | Squad Scribe         |                  | —                                                   | runSubagent | fast       | `.copilot-tracking/squad/`    |
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
    "sessionModel": "Claude Sonnet 4.6",
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

    Set-Content -LiteralPath (Join-Path $root 'consumption-rates.md') -Encoding utf8NoBOM -Value (Get-ShippedRateTemplate)

    Set-Content -LiteralPath (Join-Path $root 'consumption.md') -Encoding utf8NoBOM -Value @'
---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: fixture-001)

## Attribution

| Role          | Member | Agent                          | Model           | Model Source      | Priced As         | Tier    |
| ------------- | ------ | ------------------------------ | --------------- | ----------------- | ----------------- | ------- |
| researcher    |        | Squad Researcher               | Claude Sonnet 4.6 | dispatch-reported | Claude Sonnet 4.6 | default |
| orchestration |        | Squad Coordinator + Squad Scribe | Claude Sonnet 4.6 | session-inherited | Claude Sonnet 4.6 | default |

## Usage & Cost

| Role          | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis     |
| ------------- | ----- | --------- | ------ | -------- | ---------- | --------------- | ------------ | --------- |
| researcher    | 1     | 10000     | 5000   | 1000     | 2000       | 0.0653          | 6.53         | estimated |
| orchestration | 1     | 4000      | 0      | 0        | 1000       | 0.0270          | 2.70         | estimated |
| **Total**     | **2** | **14000** | **5000** | **1000** | **3000**   | **0.0923**      | **9.23**     |           |

### Derivation

```text
researcher     turns 1      10000 × 3.00 +   5000 × 0.30 +   1000 × 3.75 +  2000 × 15.00 =  65250 / 1e6 = 0.0653
orchestration  turns 1       4000 × 3.00 +      0 × 0.30 +      0 × 3.75 +  1000 × 15.00 =  27000 / 1e6 = 0.0270
                                                                                              total = 0.0923
```

> Basis: estimated. No per-dispatch token telemetry exists.

## Cost Comparison (illustrative)

This run consumed an estimated **$0.0923 (~9.23 AI credits)** across 1 specialized agent. Reproducing the same outcome by manually prompting Claude Sonnet 4.6 across roughly 6 iterate-and-test turns, each priced through the same dispatch-size estimator, is estimated at **$0.2400 (~24.00 AI credits)** — a saving of about **62%**.

> Estimates only. Token rates change.
'@

    Set-Content -LiteralPath (Join-Path $root 'history/Squad Researcher.md') -Encoding utf8NoBOM -Value @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: Squad Researcher

## 2026-08-19T10:00:03Z Investigate the login validation path

* Turn: 1
* Request: Investigate how login input is validated today.
* Deliverable: `.copilot-tracking/research/2026-08-19-login-validation.md` (410 words)
* Outcome: Wrote `.copilot-tracking/research/2026-08-19-login-validation.md`.

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "dispatch-reported",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 1,
  "input_tokens": 10000,
  "cached_tokens": 5000,
  "cache_write_tokens": 1000,
  "output_tokens": 2000,
  "basis": "estimated"
}
```
'@

    Set-Content -LiteralPath (Join-Path $root 'history/Squad Scribe.md') -Encoding utf8NoBOM -Value @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: Squad Scribe

## 2026-08-19T10:00:05Z Persist turn 1

* Turn: 1
* Request: Record the researcher dispatch and advance state.
* Deliverable: `.copilot-tracking/squad/consumption.md`
* Outcome: Appended history, rewrote the ledger, advanced `state.json`.

#### Consumption — Orchestration

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "session-inherited",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 1,
  "input_tokens": 4000,
  "cached_tokens": 0,
  "cache_write_tokens": 0,
  "output_tokens": 1000,
  "basis": "estimated"
}
```
'@

    $root
}

Export-ModuleMember -Function New-SquadStateFixture, Get-ShippedRateTemplate
