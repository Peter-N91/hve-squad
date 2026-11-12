#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

# AI cost: none; renders local fixture squads and inspects the HTML. No model call.

# Output-level coverage for the deterministic governance report (GOV-01..GOV-08 and GOV-09..GOV-22
# in tests/squad-behavior-contract.md). Every case renders a fixture squad and asserts on the
# displayed fields and values, never only on section presence.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll.')]
param([Parameter(Mandatory)][string]$PackageRoot)

BeforeAll {
    $script:ScriptsRoot = Join-Path $PackageRoot '.agents/skills/squad/scripts'
    $script:Cli = Join-Path $script:ScriptsRoot 'New-SquadGovernanceReport.ps1'
    $script:LedgerScript = Join-Path $script:ScriptsRoot 'Measure-SquadLedger.ps1'
    $script:AgentPath = @(Get-ChildItem -LiteralPath (Join-Path $PackageRoot '.github/agents') -Recurse -Filter 'squad-governance-report.agent.md' | Select-Object -First 1 -ExpandProperty FullName)[0]
    $script:FixtureRoot = Join-Path $PSScriptRoot '../fixtures/scribe-benchmark'
    $script:Rates = [IO.File]::ReadAllText((Join-Path $script:FixtureRoot 'applied/consumption-rates.md'))
    $script:AsOf = [datetimeoffset]::new(2026, 11, 2, 0, 0, 0, [TimeSpan]::Zero)
    Import-Module (Join-Path $script:ScriptsRoot 'SquadGovernanceReport.psm1') -Force

    function Write-GovFile {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
        [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
    }

    function ConvertTo-GovText {
        param([Parameter(Mandatory)][AllowEmptyString()][string]$Html)
        $text = [regex]::Replace($Html, '(?s)<style>.*?</style>', ' ')
        $text = [regex]::Replace($text, '</?(?:code|strong|em)>', '')
        $text = [regex]::Replace($text, '<[^>]+>', ' ')
        $text = [Net.WebUtility]::HtmlDecode($text)
        [regex]::Replace($text, '\s+', ' ').Trim()
    }

    function Get-GovTables {
        param([Parameter(Mandatory)][string]$Html)
        foreach ($table in [regex]::Matches($Html, '(?s)<table.*?</table>')) {
            $rows = @(foreach ($tr in [regex]::Matches($table.Value, '(?s)<tr.*?</tr>')) {
                    , @([regex]::Matches($tr.Value, '(?s)<t[dh][^>]*>(.*?)</t[dh]>') | ForEach-Object { ConvertTo-GovText $_.Groups[1].Value })
                })
            [pscustomobject]@{ Headers = $rows[0]; Rows = @($rows | Select-Object -Skip 1) }
        }
    }

    function Find-GovRow {
        param([Parameter(Mandatory)]$Tables, [Parameter(Mandatory)][string]$HeaderPattern, [Parameter(Mandatory)][string]$First)
        foreach ($table in $Tables) {
            if (($table.Headers -join '|') -notmatch $HeaderPattern) { continue }
            foreach ($row in $table.Rows) {
                if ($row[0] -eq $First) { return , $row }
            }
        }
        $available = (@($Tables | ForEach-Object { '  ' + ($_.Headers -join '|') + '  => ' + ((@($_.Rows | ForEach-Object { $_[0] }) | Select-Object -First 12) -join ' ; ') }) -join "`n")
        throw "No table matching /$HeaderPattern/ has a row starting with '$First'. Tables rendered:`n$available"
    }

    function New-GovHistory {
        param([Parameter(Mandatory)][string]$Agent, [Parameter(Mandatory)][hashtable[]]$Entries)
        $lines = [Collections.Generic.List[string]]::new()
        $lines.Add('---')
        $lines.Add('description: "Append-only dispatch history for a single squad agent"')
        $lines.Add('---')
        $lines.Add('')
        $lines.Add("# History: $Agent")
        foreach ($entry in $Entries) {
            $model = if ($entry.ContainsKey('Model')) { $entry.Model } else { 'claude-sonnet-4.6' }
            $lines.Add('')
            $lines.Add("### $($entry.Ts) $($entry.Title)")
            $lines.Add('')
            $lines.Add("* Turn: $($entry.Turn)")
            $lines.Add("* Request: $($entry.Request)")
            $lines.Add("* Deliverable: $($entry.Deliverable)")
            $lines.Add("* Outcome: $($entry.Outcome)")
            $lines.Add('')
            $lines.Add($(if ($entry.ContainsKey('Orchestration') -and $entry.Orchestration) { '#### Consumption — Orchestration' } else { '#### Consumption' }))
            $lines.Add('')
            $lines.Add('```json')
            $lines.Add(([ordered]@{
                        model = $model; model_source = 'session-inherited'; priced_as = $model; model_tier = 'default'; internal_turns = 4
                        input_tokens = 1000; cached_tokens = 2000; cache_write_tokens = 0; output_tokens = 500; basis = 'estimated'
                    } | ConvertTo-Json))
            $lines.Add('```')
            if ($entry.ContainsKey('Observed')) {
                $lines.Add('')
                $lines.Add("* **Effective model** — $model")
                $lines.Add("* **Observed model** — $($entry.Observed)")
            }
        }
        ($lines -join "`n") + "`n"
    }

    $script:TeamText = @'
---
description: "Squad roster: roles and the deployed HVE Core agents that fill them"
---

# Squad Roster

## Members

| Role | Member Name | Agent Name (Primary) | Alternate Agents | Selection Cue | Invocation | Model Tier | Deliverable Root |
| ---- | ----------- | -------------------- | ---------------- | ------------- | ---------- | ---------- | ---------------- |
| researcher | Alpha | Squad Researcher | — | — | runSubagent / task | default | research/ |
| developer | Beta | Squad Implementor | — | — | runSubagent / task | default | changes/ |
| tester | Gamma | Squad Reviewer | — | — | runSubagent / task | fast | reviews/ |
| security | Delta | Security Planner | — | — | runSubagent / task | default | — |
| scribe |  | Squad Scribe | — | — | runSubagent / task | fast | (squad state) |
'@

    $script:RoutingText = @'
---
description: "Squad routing"
---

# Squad Routing

| Pattern / Keyword | Role(s) | Autonomy Tier | Parallel-Eligible |
| ----------------- | ------- | ------------- | ----------------- |
| research, investigate | researcher | auto | yes |
| implement, build | developer | confirm | no |
| review, validate | tester | auto | yes |
| security, threat | security | escalate | yes |
'@

    $script:StateText = @'
{
  "schemaVersion": "1.4",
  "updated": "2026-10-20T12:00:00Z",
  "turn": 6,
  "mode": "autopilot",
  "activeRoles": [],
  "openEscalations": [],
  "currentRun": {
    "sessionModel": "claude-sonnet-4.6",
    "modelOverrides": {},
    "estCostUsd": 1.0,
    "estCreditsTotal": 100,
    "costPreflight": { "runId": "run-1", "roundId": "r2", "ceilingUsd": 5.0, "decision": "within-ceiling" }
  },
  "notify": { "approvalChannel": "in-chat", "enabled": false },
  "trigger": { "source": "issue", "ref": "Peter-N91/hve-squad#164", "eventId": "issues:1", "actor": "Peter-N91", "sub": "rich" }
}
'@

    $script:ExactLedger = @'
---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: rich-exact)

## Attribution

| Role | Member | Agent | Model | Model Source | Priced As | Tier |
| ---- | ------ | ----- | ----- | ------------ | --------- | ---- |
| researcher | Alpha | Squad Researcher | claude-sonnet-4.6 | host-reported | native credits | default |
| developer | Beta | Squad Implementor | gpt-5.3-codex | host-reported | native credits | default |
| tester | Gamma | Squad Reviewer | claude-haiku-4.5 | host-reported | native credits | fast |
| orchestration |  | Coordinator+Scribe | claude-haiku-4.5 | host-reported | native credits | mixed |

## Usage & Cost

| Role | Requests | In Tokens | Cached | Cache Wr | Out Tokens | Exact Cost (USD) | Exact Credits | Basis |
| ---- | -------- | --------- | ------ | -------- | ---------- | ---------------- | ------------- | ----- |
| researcher | 3 | 40,000 | 80,000 | 5,000 | 6,000 | 0.3000 | 30.00 | exact-native |
| developer | 5 | 60,000 | 150,000 | 0 | 12,000 | 0.4000 | 40.00 | exact-native |
| tester | 2 | 20,000 | 30,000 | 2,000 | 3,000 | 0.1500 | 15.00 | exact-native |
| orchestration | 4 | 15,000 | 40,000 | 4,000 | 4,000 | 0.1500 | 15.00 | exact-native |
| **Total** | **14** | **135,000** | **300,000** | **11,000** | **25,000** | **1.0000** | **100.00** | **exact-native** |

### Derivation

```text
Squad Researcher.md — 1 block(s) — identities: aaaa1111
Squad Scribe.md — 2 block(s) — identities: bbbb2222,cccc3333
Native usage snapshot — session: sess-rich-1; records: 21; through: 2026-10-14T18:00:00.000Z; digest: 0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
researcher         requests 3      input 40000      cached 80000      cache-write 5000       output 6000       nano-AIU 30000000000 = 30.00 credits / 0.3000 USD
developer          requests 5      input 60000      cached 150000     cache-write 0          output 12000      nano-AIU 40000000000 = 40.00 credits / 0.4000 USD
tester             requests 2      input 20000      cached 30000      cache-write 2000       output 3000       nano-AIU 15000000000 = 15.00 credits / 0.1500 USD
orchestration      requests 4      input 15000      cached 40000      cache-write 4000       output 4000       nano-AIU 15000000000 = 15.00 credits / 0.1500 USD
total nano-AIU 100000000000 = 100.00 credits / 1.0000 USD
```

> Basis: exact-native. Every row is host-reported native usage. Calibration factor 1.00 (0 reconciled runs — uncalibrated). 1 AI credit = $0.01 USD.

## Unit Economics (value)

| Measure | Value | Label |
| ------- | ----- | ----- |
| Deliverables produced | 4 | derived |
| Accepted by an independent review | 3 | derived |
| Rejected | 0 | derived |
| Unreviewed | 1 | derived |
| Dispatches (excluding Scribe) | 10 | derived |
| Rework dispatches | 1 | derived |
| First-pass yield | 66.7% | derived |
| Exact credits per accepted deliverable | 33.33 | measured |
| Rework share of exact credits | n/a | unavailable without per-history-run identity |
| Orchestration share of exact credits | 15.0% | measured |

Value is counted only for deliverables an independent review-class verdict accepted.

## Cost Comparison (exact native actual)

| Scenario | Basis | AI Credits | USD |
| -------- | ----- | ----------: | --: |
| With HVE Squad through 2026-10-14T18:00:00.000Z | complete deduplicated native records; coordinator and descendants included | 100.00 | 1.0000 |
| Without HVE Squad: same exact role-request token categories on `gpt-5.6-sol`, no coordinator or Scribe | calculated counterfactual from exact request tokens | 250.00 | 2.5000 |

HVE Squad is **1.5000 USD (60.0%) lower** than the same exact role traffic on `gpt-5.6-sol`.

> The HVE Squad row is exact as of the native session snapshot: 21 complete accounting records. The without-Squad row is not an observed alternate run.
'@

    $script:JournalText = @'
{
  "schemaVersion": 1,
  "sessions": [
    {
      "sessionId": "sess-rich-1", "source": "native-log",
      "first": "2026-10-10T09:00:00.000Z", "last": "2026-10-14T18:00:00.000Z", "through": "2026-10-14T18:00:00.000Z",
      "records": 21, "identityDigest": "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF",
      "requestDetailStatus": "complete", "historyCoverage": {},
      "rows": [
        { "role": "researcher", "requests": 3, "nanoAiu": 30000000000, "requestDetails": [ { "identityHash": "hash-a" }, { "identityHash": "hash-b" } ] },
        { "role": "developer", "requests": 5, "nanoAiu": 70000000000, "requestDetails": [ { "identityHash": "hash-c" } ] }
      ],
      "contentDigest": "x"
    }
  ]
}
'@

    $script:LegacyLedger = @'
---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: legacy-observed)

## Attribution

| Role | Member | Agent | Model | Model Source | Priced As | Tier |
| ---- | ------ | ----- | ----- | ------------ | --------- | ---- |
| researcher | Alpha | Squad Researcher | Claude Sonnet 4.6 | session-inherited | Claude Sonnet 4.6 | default |
| developer | Beta | Squad Implementor | gpt-5.3-codex | agent-pinned | GPT-5.3-Codex | default |
| orchestration |  | Squad Scribe | Claude Haiku 4.5 | agent-pinned | Claude Haiku 4.5 | fast |

## Usage & Cost

| Role | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis |
| ---- | ----- | --------- | ------ | -------- | ---------- | ---------------- | ------------ | ----- |
| researcher | 12 | 9,600 | 38,400 | 8,000 | 15,000 | 0.3000 | 30.00 | estimated |
| developer | 20 | 20,000 | 80,000 | 0 | 20,000 | 0.4000 | 40.00 | estimated |
| orchestration | 4 | 3,000 | 12,000 | 1,250 | 3,200 | 0.1000 | 10.00 | estimated |
| **Total** | **36** | **32,600** | **130,400** | **9,250** | **38,200** | **0.8000** | **80.00** | |

### Derivation

```text
researcher     turns 12    9600 × 3.00 + 38400 × 0.30 +  8000 × 3.75 + 15000 × 15.00 = 295320.0 / 1e6 = 0.3000
```

> Basis: estimated. Calibration factor 1.00 (0 reconciled runs — uncalibrated). 1 AI credit = $0.01 USD.

## Observed Usage (host-reported)

Source: Copilot session `sess-legacy-1` (`events.jsonl`, 2026-10-01T10:00:00.000Z to 2026-10-01T11:30:00.000Z). Complete `session.usage_record` records are deduplicated by host accounting identity for authoritative AI credits. Subagent token totals remain beside the estimates rather than replacing per-role rows.

| Agent | Dispatches | Observed Model | Ledger Model | Match | Observed Tokens | Estimated Tokens | Minutes | Calculated Blended USD |
| ----- | ---------- | -------------- | ------------ | ----- | --------------- | ---------------- | ------- | ---------------------- |
| Squad Researcher | 1 | claude-sonnet-4.6 | Claude Sonnet 4.6 | yes | 190,000 | 60,000 | 2.0 | 0.5400 |
| Squad Implementor | 2 | claude-sonnet-5.5 | gpt-5.3-codex | no | 400,000 | 120,000 | 9.5 | 0.9000 |
| Squad Reviewer | 1 | gpt-5.4-mini | unknown | n/a | 50,000 | 20,000 | 1.5 | 0.0900 |
| **Subagents total** | **4** | | | | **640,000** | **200,000** | | **1.5300** |

Exact complete-record total, coordinator and descendants included: **120.00 AI credits** (about 1.20 USD at 0.01 USD per credit) across **45** unique usage records. The coordinator's own turns appear only in this figure, never in the table.

### Without HVE Squad

| Scenario | Tokens | Model | Calculated Blended USD |
| -------- | ------ | ----- | ---------------------- |
| With HVE Squad: routed roles plus Scribe, as observed | 640,000 | as routed | 1.5300 |
| Without HVE Squad: the same role work on one model, no Scribe | 600,000 | claude-opus-5 | 2.5500 |

HVE Squad is **1.0200 USD (40.0%) lower** than running the same role work on `claude-opus-5`. Both rows use the same blended mix.

HydraFusion comparison: **1** role dispatch(es) on `hydrafusion-max` consumed **20,000 host-reported tokens**.

## Cost Comparison (illustrative)

This run consumed an estimated **$0.8000 (~80.00 AI credits)** across 2 specialized agents. Reproducing the same outcome by manually prompting Claude Opus 5 across roughly 6 iterate-and-test turns is estimated at **$2.00 (~200.00 AI credits)** — a saving of about **60%**.

> Estimates only. Token rates change.
'@

    $script:EstimateOnlyLedger = @'
---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: estimate-only)

## Attribution

| Role | Member | Agent | Model | Model Source | Priced As | Tier |
| ---- | ------ | ----- | ----- | ------------ | --------- | ---- |
| researcher | Alpha | Squad Researcher | Claude Sonnet 4.6 | session-inherited | Claude Sonnet 4.6 | default |
| orchestration |  | Squad Scribe | Claude Haiku 4.5 | agent-pinned | Claude Haiku 4.5 | fast |

## Usage & Cost

| Role | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis |
| ---- | ----- | --------- | ------ | -------- | ---------- | ---------------- | ------------ | ----- |
| researcher | 12 | 9,600 | 38,400 | 8,000 | 15,000 | 0.2953 | 29.53 | estimated |
| orchestration | 4 | 3,000 | 12,000 | 1,250 | 3,200 | 0.0218 | 2.18 | estimated |
| **Total** | **16** | **12,600** | **50,400** | **9,250** | **18,200** | **0.3171** | **31.71** | |

### Derivation

```text
researcher     turns 12    9600 × 3.00 + 38400 × 0.30 +  8000 × 3.75 + 15000 × 15.00 = 295320.0 / 1e6 = 0.2953
```

> Basis: estimated. Calibration factor 1.00 (0 reconciled runs — uncalibrated). 1 AI credit = $0.01 USD.

## Cost Comparison (illustrative)

This run consumed an estimated **$0.3171 (~31.71 AI credits)** across 1 specialized role plus orchestration; manual baseline and saving unavailable.

> Estimates only. Token rates change.
'@

    $script:UnknownModelLedger = @'
---
description: "Squad consumption ledger"
---

# Squad Consumption Ledger (Run: unknown-models)

## Attribution

| Role | Member | Agent | Model | Model Source | Priced As | Tier |
| ---- | ------ | ----- | ----- | ------------ | --------- | ---- |
| researcher | Alpha | Squad Researcher | unknown | unresolved | Claude Sonnet 4.6 | default |
| developer | Beta | Squad Implementor | claude-sonnet-5 | session-inherited | Claude Haiku 4.5 | fast |
| orchestration |  | Squad Scribe | Claude Haiku 4.5 | agent-pinned | Claude Haiku 4.5 | fast |

## Usage & Cost

| Role | Turns | In Tokens | Cached | Cache Wr | Out Tokens | Est. Cost (USD) | Est. Credits | Basis |
| ---- | ----- | --------- | ------ | -------- | ---------- | ---------------- | ------------ | ----- |
| researcher | 5 | 1,000 | 2,000 | 0 | 500 | 0.2000 | 20.00 | tier-default |
| developer | 8 | 4,000 | 8,000 | 0 | 2,000 | 0.3000 | 30.00 | estimated |
| orchestration | 2 | 500 | 1,000 | 0 | 200 | 0.0500 | 5.00 | estimated |
| **Total** | **15** | **5,500** | **11,000** | **0** | **2,700** | **0.6000** | **60.00** | |

### Derivation

```text
researcher     turns 5     1000 × 3.00 = 3000.0 / 1e6 = 0.2000
```

> Basis: estimated. Calibration factor 1.00 (0 reconciled runs — uncalibrated).

## Cost Comparison (illustrative)

This run consumed an estimated **$0.6000 (~60.00 AI credits)** across 2 specialized agents. Reproducing the same outcome manually on Claude Opus 5 is estimated at **$1.20 (~120.00 AI credits)** — a saving of about **90%**.

> Estimates only.
'@

    $script:StaleNoteLedger = $script:ExactLedger.Replace('> Basis: exact-native. Every row is host-reported native usage.', '> Basis: estimated. No per-dispatch token telemetry exists.')

    function New-GovSquadRoot {
        param(
            [Parameter(Mandatory)][string]$Root,
            [AllowNull()][string]$Ledger,
            [hashtable]$History = @{},
            [string]$Decisions,
            [string]$Notifications,
            [string]$State = $script:StateText,
            [hashtable]$Runs = @{},
            [string]$Journal,
            [switch]$NoRates
        )
        Write-GovFile (Join-Path $Root 'team.md') $script:TeamText
        Write-GovFile (Join-Path $Root 'routing.md') $script:RoutingText
        if ($State) { Write-GovFile (Join-Path $Root 'state.json') $State }
        if ($Ledger) { Write-GovFile (Join-Path $Root 'consumption.md') $Ledger }
        if (-not $NoRates) { Write-GovFile (Join-Path $Root 'consumption-rates.md') $script:Rates }
        if ($Decisions) { Write-GovFile (Join-Path $Root 'decisions.md') $Decisions }
        if ($Notifications) { Write-GovFile (Join-Path $Root 'notifications.md') $Notifications }
        if ($Journal) { Write-GovFile (Join-Path $Root 'consumption-sessions.json') $Journal }
        foreach ($name in $History.Keys) { Write-GovFile (Join-Path $Root "history/$name.md") $History[$name] }
        foreach ($name in $Runs.Keys) { Write-GovFile (Join-Path $Root "history/$name.md") $Runs[$name] }
    }

    function New-GovDefaultHistory {
        @{
            'Squad Researcher' = New-GovHistory 'Squad Researcher' @(
                @{ Ts = '2026-10-10T09:10:00Z'; Title = 'Surveying the auth options'; Turn = 1; Request = 'Survey auth options'; Deliverable = '`research/auth-options.md`'; Outcome = 'Surveyed three providers and recommended one.' }
            )
            'Squad Implementor' = New-GovHistory 'Squad Implementor' @(
                @{ Ts = '2026-10-11T10:00:00Z'; Title = 'Implementing the auth layer'; Turn = 3; Request = 'Implement'; Deliverable = '`src/auth.py`, `src/session.py`'; Outcome = 'Implemented the layer; 12 tests pass.' }
                @{ Ts = '2026-10-12T10:00:00Z'; Title = 'Fixing lint errors'; Turn = 4; Request = 'Fix lint'; Deliverable = '`src/auth.py`'; Outcome = 'Failed: lint errors remained after the first pass.' }
            )
            'Squad Reviewer' = New-GovHistory 'Squad Reviewer' @(
                @{ Ts = '2026-10-13T11:00:00Z'; Title = 'Reviewing the auth layer'; Turn = 5; Request = 'Review'; Deliverable = '`reviews/auth-review.md`'; Outcome = 'Verified; 14 tests passed and the diff is accepted.' }
            )
            'Security Planner' = New-GovHistory 'Security Planner' @(
                @{ Ts = '2026-10-13T12:00:00Z'; Title = 'Threat model for the auth layer'; Turn = 5; Request = 'Threat model'; Deliverable = '`docs/threat-model.md`'; Outcome = 'Produced the threat model.' }
            )
            'Squad Scribe' = New-GovHistory 'Squad Scribe' @(
                @{ Ts = '2026-10-10T09:00:00Z'; Title = 'Recording turn one'; Turn = 1; Request = 'Record'; Deliverable = '`state.json`'; Outcome = 'Recorded the turn.'; Orchestration = $true }
                @{ Ts = '2026-10-14T18:00:00Z'; Title = 'Recording the final turn'; Turn = 6; Request = 'Record'; Deliverable = '`state.json`'; Outcome = 'Recorded the final turn.'; Orchestration = $true }
            )
        }
    }

    $script:DecisionsText = @'
---
description: "Append-only log of squad decisions and their rationale"
---

# Squad Decisions

## Council Verdict 2026-10-10 auth-layer

* Topic: Auth layer design
* Council Members Dispatched: architect, security
* Verdict: Go

### Findings by Role

| Role | Verdict | Risk | Blocking Issues | Conditions | Suggested Follow-ups |
| ---- | ------- | ---- | --------------- | ---------- | -------------------- |
| architect | Approve | Risk: Low | none | none | none |
| security | Approve | Risk: Low | none | none | none |

### Implementation Gate

* Permits Implementation Dispatch: yes (Go)
* Conditions Outstanding: 0

## Council Verdict 2026-10-12 data-store

* Topic: Data store
* Verdict: Go-With-Conditions

### Findings by Role

| Role | Verdict | Risk | Blocking Issues | Conditions | Suggested Follow-ups |
| ---- | ------- | ---- | --------------- | ---------- | -------------------- |
| architect | Approve | Risk: Low | none | none | none |
| security | Conditional | Risk: Medium | none | (security) encrypt at rest | none |

### Implementation Gate

* Permits Implementation Dispatch: yes (Go-With-Conditions)
* Conditions Outstanding: 2

## Council Verdict 2026-10-14 public-api

* Topic: Public API
* Verdict: Stop

### Findings by Role

| Role | Verdict | Risk | Blocking Issues | Conditions | Suggested Follow-ups |
| ---- | ------- | ---- | --------------- | ---------- | -------------------- |
| architect | Concern | Risk: Medium | none | none | none |
| security | Block | Risk: High | (security) unauthenticated endpoint | none | none |

### Implementation Gate

* Permits Implementation Dispatch: no (Stop)
* Conditions Outstanding: 1

## Intake Readiness Verdict 2026-10-09 intake-1

* Topic: Inputs for the auth work
* Verdict: Ready-With-Gaps
* Remediation Cycles: 1

## Discovery Verdict 2026-10-08 brainstorm-1

* Topic: Explore auth
* Opt-In: offer-accepted
* Depth: standard
* Roles Dispatched: Squad Researcher
* Brief: plans/brief.md

### Options Considered

| Option | Outcome | Reason |
| ------ | ------- | ------ |
| Provider A | chosen | cheapest |
| Provider B | discarded | lock-in |
| Provider C | discarded | immature |

## Discovery Verdict 2026-10-08 brainstorm-2

* Topic: Another topic
* Opt-In: offer-declined
* Depth: skip
* Roles Dispatched: none
* Brief: none

## Cost Preflight 2026-10-10T09:00:00Z run-1 r1

* Ceiling USD: 5.0
* Decision: within-ceiling
* Confidence: medium

## Cost Preflight 2026-10-13T09:00:00Z run-1 r2

* Ceiling USD: 5.0
* Decision: within-ceiling
* Confidence: medium
'@

    $script:NotificationsText = @'
---
description: "Append-only log of squad notifications (pings) and their delivery channel"
---

# Squad Notifications

### 2026-10-15T09:00:00Z impactful-action

* Mode: autopilot
* Channel: github-issue
* Approval Ref: #201 in Peter-N91/hve-squad
* Topic: Deploy to staging
* Awaiting: Approve the staging deploy
* Resolved: approved (Peter-N91, 2026-10-15T09:30:00Z)

### 2026-10-15T11:00:00Z risk-gate

* Mode: autopilot
* Channel: github-issue
* Approval Ref: #202 in Peter-N91/hve-squad
* Topic: Security block resolved
* Awaiting: Approve continuing
* Resolved: approved (Peter-N91, 2026-10-15T11:20:00Z)
'@

    $script:AutopilotRunText = @'
---
description: "Autopilot-run summary for topic run-1"
---

# Autopilot Run: run-1

* Topic: Build the auth layer
* Opt-In: mode=autopilot
* Cost Ceiling: 5.00
* Outcome: completed (awaiting final validation)

## Stages 2026-10-15

| Stage | Role(s) | Dispatch Record | Result | Gate Fired |
| ----- | ------- | --------------- | ------ | ---------- |
| research | researcher | `history/Squad Researcher.md` | Surveyed providers | none |
| implement | developer | `history/Squad Implementor.md` | Implemented the layer | Impactful-Action Gate: deploy to staging |
| review | tester | `history/Squad Reviewer.md` | Verified | Risk Gate: security block resolved |
'@

    function New-GovRichRoot {
        param([Parameter(Mandatory)][string]$Root, [string]$Ledger = $script:ExactLedger)
        New-GovSquadRoot -Root $Root -Ledger $Ledger -History (New-GovDefaultHistory) -Decisions $script:DecisionsText -Notifications $script:NotificationsText -Runs @{ 'autopilot-run-run-1' = $script:AutopilotRunText } -Journal $script:JournalText
    }

    function New-GovProject {
        <# A project directory holding .copilot-tracking/squad; returns the project and state root. #>
        $project = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $state = Join-Path $project '.copilot-tracking/squad'
        $null = New-Item -ItemType Directory -Path $state -Force
        [pscustomobject]@{ Project = $project; State = $state }
    }

    function Get-GovReport {
        param([Parameter(Mandatory)]$Project, [string]$Squad, [string]$Period = 'all', [string]$SquadRoot)
        $arguments = @{ ProjectRoot = $Project.Project; Period = $Period; AsOf = $script:AsOf; ProjectName = 'fixture' }
        if ($Squad) { $arguments.Squad = $Squad }
        if ($SquadRoot) { $arguments.SquadRoot = $SquadRoot }
        $model = Get-SquadGovernanceModel @arguments
        $html = ConvertTo-SquadGovernanceHtml -Model $model
        [pscustomobject]@{ Model = $model; Html = $html; Text = (ConvertTo-GovText $html); Tables = @(Get-GovTables $html) }
    }

    function Invoke-GovCli {
        param([Parameter(Mandatory)][string[]]$Arguments, [string]$Script = $script:Cli)
        $info = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $Script) + $Arguments) { $info.ArgumentList.Add($argument) }
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.UseShellExecute = $false
        $process = [Diagnostics.Process]::Start($info)
        try {
            $out = $process.StandardOutput.ReadToEndAsync()
            $err = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $out.Result; Error = $err.Result }
        }
        finally { $process.Dispose() }
    }

    function Get-GovTreeHash {
        param([Parameter(Mandatory)][string]$Root)
        $hashes = foreach ($file in (Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName)) {
            '{0}={1}' -f $file.FullName.Substring($Root.Length), (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
        $hashes -join "`n"
    }

    function Get-GovTextByUiCulture {
        <# The report text rendered once per UI culture, to prove no message follows the session's language. #>
        param([Parameter(Mandatory)]$Project)
        $previous = [Globalization.CultureInfo]::CurrentUICulture
        try {
            @(foreach ($name in 'en-US', 'fr-FR', 'de-DE') {
                    try { [Globalization.CultureInfo]::CurrentUICulture = [Globalization.CultureInfo]::GetCultureInfo($name) } catch { continue }
                    (Get-GovReport -Project $Project).Text
                })
        }
        finally { [Globalization.CultureInfo]::CurrentUICulture = $previous }
    }

    function Get-GovMissingLedgerTokens {
        <# An independent completeness oracle: every word of the ledger source must be visible in the report text. #>
        param([Parameter(Mandatory)][string]$LedgerText, [Parameter(Mandatory)][string]$Text)
        $body = [regex]::Replace(($LedgerText -replace "`r`n?", "`n"), '(?s)\A---\n.*?\n---\n', '')
        $tokens = foreach ($line in ($body -split "`n")) {
            if ($line -match '^\s*(`{3,}|~{3,})' -or $line -match '^\s*\|?\s*:?-{2,}') { continue }
            ($line -replace '[`*|#>]', ' ') -split '\s+'
        }
        @($tokens | Where-Object { $_ -and $_ -notmatch '^[-=:.,;()\[\]/\\+]+$' -and -not $Text.Contains($_) } | Select-Object -Unique)
    }

    # Scenarios rendered once and inspected by many cases.
    $script:Rich = New-GovProject
    New-GovRichRoot -Root $script:Rich.State
    $script:RichReport = Get-GovReport -Project $script:Rich
}

Describe 'GOV-02 and GOV-03 structure is preserved' {
    It 'keeps the seven numbered sections, in order, with their exact titles' {
        $titles = @([regex]::Matches($script:RichReport.Html, '<div class="section-header">(.*?)</div>') | ForEach-Object { [Net.WebUtility]::HtmlDecode($_.Groups[1].Value) })
        $titles | Should -Be @('1. Governance Gates', '2. Council Verdicts', '3. Cost Breakdown', '4. Role Dispatch Activity', '5. Risk & Compliance', '6. Activity Timeline', '7. Key Outcomes This Period')
    }

    It 'shows the six header metrics, each with its value and a basis-labeled cost' {
        $html = $script:RichReport.Html
        foreach ($label in 'Coordination Turns', 'Role Dispatches', 'Exact Cost (exact-native)', 'Total Tokens (exact billed categories)', 'Human Gates Fired', 'Escalations') {
            $html | Should -Match ([regex]::Escape($label))
        }
        $stats = @([regex]::Matches($html, '<div class="stat"><div class="value">(.*?)</div><div class="label">(.*?)</div>') | ForEach-Object { , @($_.Groups[2].Value, $_.Groups[1].Value) })
        ($stats | Where-Object { $_[0] -eq 'Coordination Turns' })[1] | Should -Be '6'
        ($stats | Where-Object { $_[0] -eq 'Role Dispatches' })[1] | Should -Be '7'
        ($stats | Where-Object { $_[0] -like 'Exact Cost*' })[1] | Should -Be '$1.0000'
        ($stats | Where-Object { $_[0] -like 'Total Tokens*' })[1] | Should -Be '471,000'
        ($stats | Where-Object { $_[0] -eq 'Human Gates Fired' })[1] | Should -Be '2'
        ($stats | Where-Object { $_[0] -eq 'Escalations' })[1] | Should -Be '0'
    }

    It 'is self-contained: no script, no external reference, inline styles only' {
        $html = $script:RichReport.Html
        $html | Should -Not -Match '(?i)<script'
        $html | Should -Not -Match '(?i)\b(src|href)\s*=\s*"?\s*(https?:|//)'
        $html | Should -Not -Match '(?i)<link\b'
        $html | Should -Not -Match '(?i)@import'
        $html | Should -Match '(?s)<style>.*</style>'
    }

    It 'is well formed: every container element opens and closes the same number of times' {
        foreach ($tag in 'div', 'details', 'summary', 'table', 'thead', 'tbody', 'tr', 'td', 'th', 'ul', 'li', 'p', 'pre', 'code', 'header', 'footer', 'strong') {
            ([regex]::Matches($script:RichReport.Html, "<$tag(\s[^>]*)?>")).Count | Should -Be ([regex]::Matches($script:RichReport.Html, "</$tag>")).Count -Because "<$tag> must balance"
        }
    }
}

Describe 'GOV-09 a rich exact-native ledger is displayed in full, with its values' {
    It 'shows every Attribution field per role, including model source and priced-as' {
        $row = Find-GovRow $script:RichReport.Tables '^Role\|Member\|Agent\|Model\|Model Source\|Priced As\|Tier$' 'developer'
        $row | Should -Be @('developer', 'Beta', 'Squad Implementor', 'gpt-5.3-codex', 'host-reported', 'native credits', 'default')
        (Find-GovRow $script:RichReport.Tables '^Role\|Member' 'orchestration')[2] | Should -Be 'Coordinator+Scribe'
    }

    It 'shows usage, tokens, cost, credits and basis per role exactly as the ledger prints them' {
        $header = '^Role\|Requests\|In Tokens\|Cached\|Cache Wr\|Out Tokens\|Exact Cost \(USD\)\|Exact Credits\|Basis$'
        (Find-GovRow $script:RichReport.Tables $header 'researcher') | Should -Be @('researcher', '3', '40,000', '80,000', '5,000', '6,000', '0.3000', '30.00', 'exact-native')
        (Find-GovRow $script:RichReport.Tables $header 'developer') | Should -Be @('developer', '5', '60,000', '150,000', '0', '12,000', '0.4000', '40.00', 'exact-native')
        (Find-GovRow $script:RichReport.Tables $header 'tester') | Should -Be @('tester', '2', '20,000', '30,000', '2,000', '3,000', '0.1500', '15.00', 'exact-native')
        (Find-GovRow $script:RichReport.Tables $header 'orchestration') | Should -Be @('orchestration', '4', '15,000', '40,000', '4,000', '4,000', '0.1500', '15.00', 'exact-native')
        (Find-GovRow $script:RichReport.Tables $header 'Total') | Should -Be @('Total', '14', '135,000', '300,000', '11,000', '25,000', '1.0000', '100.00', 'exact-native')
    }

    It 'keeps the Derivation evidence: record count, window, digest and per-role nano-AIU lines' {
        $script:RichReport.Text | Should -Match 'Native usage snapshot — session: sess-rich-1; records: 21; through: 2026-10-14T18:00:00.000Z; digest: 0123456789ABCDEF'
        $script:RichReport.Text | Should -Match 'researcher requests 3 input 40000 cached 80000 cache-write 5000 output 6000 nano-AIU 30000000000 = 30.00 credits / 0.3000 USD'
        $script:RichReport.Text | Should -Match 'Squad Scribe.md — 2 block\(s\) — identities: bbbb2222,cccc3333'
    }

    It 'shows the calibration state and the credit conversion the ledger states' {
        $script:RichReport.Text | Should -Match 'Calibration factor 1.00 \(0 reconciled runs — uncalibrated\)'
        $script:RichReport.Text | Should -Match '1 AI credit = \$0.01 USD'
        $script:RichReport.Html | Should -Match 'Calibration:</strong> .*factor 1.00, 0 reconciled run\(s\) \(uncalibrated\)'
    }

    It 'shows the Cost Comparison table and its stated saving, with the counterfactual caveat' {
        $row = Find-GovRow $script:RichReport.Tables '^Scenario\|Basis\|AI Credits\|USD$' 'Without HVE Squad: same exact role-request token categories on gpt-5.6-sol, no coordinator or Scribe'
        $row[2] | Should -Be '250.00'
        $row[3] | Should -Be '2.5000'
        $script:RichReport.Text | Should -Match 'HVE Squad is 1.5000 USD \(60.0%\) lower than the same exact role traffic on gpt-5.6-sol'
        $script:RichReport.Text | Should -Match 'not an observed alternate run'
    }

    It 'shows Unit Economics (value) when the ledger has it, including the accepted-deliverable measures' {
        $header = '^Measure\|Value\|Label$'
        (Find-GovRow $script:RichReport.Tables $header 'Accepted by an independent review') | Should -Be @('Accepted by an independent review', '3', 'derived')
        (Find-GovRow $script:RichReport.Tables $header 'First-pass yield') | Should -Be @('First-pass yield', '66.7%', 'derived')
        (Find-GovRow $script:RichReport.Tables $header 'Exact credits per accepted deliverable') | Should -Be @('Exact credits per accepted deliverable', '33.33', 'measured')
    }

    It 'renders the native sessions behind the exact ledger from the journal' {
        $row = Find-GovRow $script:RichReport.Tables '^Session\|First record\|Through\|Records' 'sess-rich-1'
        $row[1] | Should -Be '2026-10-10T09:00:00.000Z'
        $row[3] | Should -Be '21'
        $row[6] | Should -Be '100.00'
    }

    It 'explains that exact-native ledgers have no separate Observed Usage section instead of inventing one' {
        $script:RichReport.Text | Should -Match 'Observed Usage \(host-reported\): not recorded in this ledger. An exact-native ledger folds host-reported usage into its main tables'
    }

    It 'shows the complete ledger source (independent word-level completeness oracle)' {
        Get-GovMissingLedgerTokens -LedgerText $script:ExactLedger -Text $script:RichReport.Text | Should -BeNullOrEmpty
    }
}

Describe 'GOV-10 ROI is computed from the ledger and labeled by basis' {
    It 'derives avoided cost, reduction, ROI and multiple from the with and without figures' {
        $roi = $script:RichReport.Model.Economics.Rollup
        $roi.SquadUsd | Should -Be 1.0000
        $roi.BaselineUsd | Should -Be 2.5000
        $roi.SavingsUsd | Should -Be 1.5000
        [Math]::Round([double]$roi.SavingsPct, 4) | Should -Be 60
        [Math]::Round([double]$roi.RoiPct, 4) | Should -Be 150
        [Math]::Round([double]$roi.Multiple, 4) | Should -Be 2.5
        $roi.Kind | Should -Be 'exact-native'
    }

    It 'shows the ROI strip in the header and the derivation table with each figure''s basis' {
        $script:RichReport.Html | Should -Match '(?s)<div class="roi-chip rc-good"><div class="rc-label">Run ROI</div><div class="rc-value">\+150%</div>'
        $table = @($script:RichReport.Tables | Where-Object { ($_.Headers -join '|') -eq 'Measure|Value|Basis|Derivation' })
        $measure = '^Measure\|Value\|Basis\|Derivation$'
        (Find-GovRow $table $measure 'Without HVE Squad')[1] | Should -Be '$2.5000'
        (Find-GovRow $table $measure 'Avoided cost')[1] | Should -Be '$1.5000'
        (Find-GovRow $table $measure 'Cost reduction')[1] | Should -Be '60.0%'
        (Find-GovRow $table $measure 'Run ROI')[1] | Should -Be '150.0%'
        (Find-GovRow $table $measure 'Cost multiple')[1] | Should -Be '2.50×'
        (Find-GovRow $table $measure 'Without HVE Squad')[2] | Should -Match 'modeled'
        (Find-GovRow $table $measure 'Orchestration share of spend')[1] | Should -Be '15.0%'
        (Find-GovRow $table $measure 'Prompt-cache share of input-side tokens')[1] | Should -Be '67.3%'
        (Find-GovRow $table $measure 'Cost per accepted deliverable')[1] | Should -Be '$0.3333'
    }

    It 'never adds categories: the figures-by-basis table keeps the ledger total on its own basis' {
        $row = Find-GovRow $script:RichReport.Tables '^Figure\|Value\|Basis\|Scope$' 'Ledger total'
        $row[1] | Should -Be '$1.0000'
        $row[2] | Should -Be 'exact-native'
    }

    It 'states a higher-than-baseline run honestly instead of claiming a saving' {
        $ledger = $script:ExactLedger.Replace('| 250.00 | 2.5000 |', '| 80.00 | 0.8000 |').Replace('**1.5000 USD (60.0%) lower**', '**0.2000 USD (25.0%) higher**')
        $project = New-GovProject
        New-GovRichRoot -Root $project.State -Ledger $ledger
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Rollup.SavingsUsd | Should -Be (-0.2)
        $report.Text | Should -Match 'In this run HVE Squad''s spend was \$0.2000 \(25.0%\) higher than the modeled single-model baseline'
        $report.Html | Should -Match '(?s)<div class="roi-chip rc-bad"><div class="rc-label">Run ROI</div><div class="rc-value">-20%</div>'
        $report.Model.Justifications.Cost[0].State | Should -Be 'not-shown'
    }

    It 'claims neither a saving nor an overspend when the run cost the same as its baseline' {
        $project = New-GovProject
        New-GovRichRoot -Root $project.State -Ledger $script:ExactLedger.Replace('| 250.00 | 2.5000 |', '| 100.00 | 1.0000 |')
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Rollup.SavingsUsd | Should -Be 0
        $report.Html | Should -Match 'same as the baseline'
        $report.Html | Should -Not -Match '(lower|higher) with HVE Squad'
        $claim = $report.Model.Justifications.Cost[0]
        $claim.State | Should -Be 'not-shown'
        $claim.Detail | Should -Match 'equals the modeled single-model baseline'
    }

    It 'shows percentages as not available, never as zero, when the stated baseline is zero' {
        $project = New-GovProject
        New-GovRichRoot -Root $project.State -Ledger $script:ExactLedger.Replace('| 250.00 | 2.5000 |', '| 0.00 | 0.0000 |')
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Rollup.SavingsPct | Should -BeNullOrEmpty
        $report.Model.Justifications.Cost[0].Detail | Should -Match '\$1\.0000 \(n/a\) higher than the modeled single-model baseline'
        $report.Html | Should -Not -Match 'n/a%'
        $report.Html | Should -Not -Match 'n/a×'
    }
}

Describe 'GOV-11 legacy ledgers with Observed Usage keep every observed field and keep the categories apart' {
    BeforeAll {
        $script:Legacy = New-GovProject
        New-GovSquadRoot -Root $script:Legacy.State -Ledger $script:LegacyLedger -History (New-GovDefaultHistory)
        $script:LegacyReport = Get-GovReport -Project $script:Legacy
    }

    It 'shows each observed agent row, its model comparison, tokens, minutes and blended cost' {
        $header = '^Agent\|Dispatches\|Observed Model\|Ledger Model\|Match\|Observed Tokens\|Estimated Tokens\|Minutes\|Calculated Blended USD$'
        (Find-GovRow $script:LegacyReport.Tables $header 'Squad Researcher') | Should -Be @('Squad Researcher', '1', 'claude-sonnet-4.6', 'Claude Sonnet 4.6', 'yes', '190,000', '60,000', '2.0', '0.5400')
        (Find-GovRow $script:LegacyReport.Tables $header 'Squad Implementor') | Should -Be @('Squad Implementor', '2', 'claude-sonnet-5.5', 'gpt-5.3-codex', 'no', '400,000', '120,000', '9.5', '0.9000')
        (Find-GovRow $script:LegacyReport.Tables $header 'Squad Reviewer') | Should -Be @('Squad Reviewer', '1', 'gpt-5.4-mini', 'unknown', 'n/a', '50,000', '20,000', '1.5', '0.0900')
        (Find-GovRow $script:LegacyReport.Tables $header 'Subagents total') | Should -Be @('Subagents total', '4', '', '', '', '640,000', '200,000', '', '1.5300')
    }

    It 'keeps the observation window, session provenance, scope and the whole-session total with its units' {
        $script:LegacyReport.Text | Should -Match 'Copilot session sess-legacy-1 \(events.jsonl, 2026-10-01T10:00:00.000Z to 2026-10-01T11:30:00.000Z\)'
        $script:LegacyReport.Text | Should -Match 'Exact complete-record total, coordinator and descendants included: 120.00 AI credits \(about 1.20 USD at 0.01 USD per credit\) across 45 unique usage records'
        $row = Find-GovRow $script:LegacyReport.Tables '^Figure\|Value\|Basis\|Scope$' 'Host-reported whole-session billed'
        $row[1] | Should -Be '120.00 AI credits ($1.20)'
        $row[2] | Should -Be 'host-billed'
        $row[3] | Should -Match 'coordinator included'
    }

    It 'distinguishes observed tokens, modeled blended prices and host-billed usage in separate rows' {
        $tokens = Find-GovRow $script:LegacyReport.Tables '^Figure\|Value\|Basis\|Scope$' 'Observed subagent tokens (squad)'
        $tokens[1] | Should -Be '640,000 tokens'
        $tokens[2] | Should -Be 'host-reported'
        $tokens[3] | Should -Match 'blended USD \$1.5300 is modeled, not billed'
        $script:LegacyReport.Model.Economics.Spend.Basis | Should -Be 'estimated'
    }

    It 'keeps the Without HVE Squad table, its stated saving and the HydraFusion comparison' {
        $row = Find-GovRow $script:LegacyReport.Tables '^Scenario\|Tokens\|Model\|Calculated Blended USD$' 'Without HVE Squad: the same role work on one model, no Scribe'
        $row | Should -Be @('Without HVE Squad: the same role work on one model, no Scribe', '600,000', 'claude-opus-5', '2.5500')
        $script:LegacyReport.Text | Should -Match 'HVE Squad is 1.0200 USD \(40.0%\) lower than running the same role work on claude-opus-5'
        $script:LegacyReport.Text | Should -Match 'HydraFusion comparison: 1 role dispatch\(es\) on hydrafusion-max'
    }

    It 'flags the model mismatch and the unverifiable comparison instead of hiding them' {
        $codes = @($script:LegacyReport.Model.Quality | ForEach-Object Code)
        $codes | Should -Contain 'model-mismatch'
        $codes | Should -Contain 'model-match-unverifiable'
        ($script:LegacyReport.Model.Quality | Where-Object Code -eq 'model-mismatch').Message | Should -Match 'Squad Implementor: observed claude-sonnet-5.5, ledger gpt-5.3-codex'
        $script:LegacyReport.Html | Should -Match '<span class="chip chip-bad">no</span>'
    }

    It 'derives ROI from the illustrative comparison and reports the observed blended comparison separately' {
        $comparisons = @($script:LegacyReport.Model.Economics.Comparisons)
        $comparisons.Count | Should -Be 2
        @($comparisons.Comparison.Kind) | Should -Contain 'estimated-illustrative'
        @($comparisons.Comparison.Kind) | Should -Contain 'observed-blended'
        $script:LegacyReport.Model.Economics.Rollup.Kind | Should -Be 'estimated-illustrative'
        $script:LegacyReport.Model.Economics.Rollup.BaselineUsd | Should -Be 2.00
    }

    It 'annotates estimated totals as approximate' {
        $script:LegacyReport.Html | Should -Match '<div class="value">~(\d|,)+</div><div class="label">Total Tokens \(estimated ~\)'
        $script:LegacyReport.Text | Should -Match 'Est. Cost \(estimated\)'
    }

    It 'shows the complete ledger source' {
        Get-GovMissingLedgerTokens -LedgerText $script:LegacyLedger -Text $script:LegacyReport.Text | Should -BeNullOrEmpty
    }
}

Describe 'GOV-12 an estimate-only ledger renders with a clear unavailable state and no fabricated telemetry' {
    BeforeAll {
        $script:Est = New-GovProject
        New-GovSquadRoot -Root $script:Est.State -Ledger $script:EstimateOnlyLedger -History (New-GovDefaultHistory)
        $script:EstReport = Get-GovReport -Project $script:Est
    }

    It 'states that observed usage is not recorded and substitutes nothing' {
        $script:EstReport.Text | Should -Match 'Observed Usage \(host-reported\): not recorded in this ledger. This ledger is estimate-only, so no host telemetry, token split, billing value or model identity is shown. Nothing is substituted.'
        $script:EstReport.Text | Should -Not -Match 'Observed Model'
        $basisRows = @($script:EstReport.Tables | Where-Object { ($_.Headers -join '|') -eq 'Figure|Value|Basis|Scope' } | ForEach-Object { $_.Rows })
        @($basisRows | Where-Object { $_[2] -match 'host-' }) | Should -BeNullOrEmpty
        $script:EstReport.Model.Economics.HostBilled.Sessions.Count | Should -Be 0
    }

    It 'shows ROI and unit economics as not recorded when the ledger states no baseline or value' {
        $script:EstReport.Model.Economics.Rollup | Should -BeNullOrEmpty
        $script:EstReport.Model.Economics.Value | Should -BeNullOrEmpty
        $script:EstReport.Html | Should -Match '(?s)<div class="rc-label">Run ROI</div><div class="rc-value">Not derivable</div>'
        $script:EstReport.Text | Should -Match 'Without HVE Squad and ROI not recorded unavailable No ledger states both a with and a without HVE Squad figure; nothing is estimated in its place'
        $script:EstReport.Text | Should -Match 'Unit Economics \(value\) not recorded unavailable'
        $codes = @($script:EstReport.Model.Quality | ForEach-Object Code)
        $codes | Should -Contain 'comparison-incomplete'
        $codes | Should -Contain 'uncalibrated'
    }

    It 'labels every figure as estimated and keeps the totals the ledger prints' {
        $script:EstReport.Model.Economics.Spend.Basis | Should -Be 'estimated'
        $script:EstReport.Model.Economics.Spend.Usd | Should -Be 0.3171
        $script:EstReport.Text | Should -Match 'Est. Cost \(estimated\) ~'
        (Find-GovRow $script:EstReport.Tables '^Role\|Turns\|In Tokens' 'Total') | Should -Be @('Total', '16', '12,600', '50,400', '9,250', '18,200', '0.3171', '31.71', '')
    }

    It 'shows the complete ledger source' {
        Get-GovMissingLedgerTokens -LedgerText $script:EstimateOnlyLedger -Text $script:EstReport.Text | Should -BeNullOrEmpty
    }

    It 'renders a squad whose consumption.md is <Case> without inventing a figure' -ForEach @(
        @{ Case = 'missing'; Ledger = $null; Message = 'No consumption.md was found' }
        @{ Case = 'empty'; Ledger = ''; Message = 'No consumption.md was found' }
        @{ Case = 'only a title'; Ledger = "# Squad Consumption Ledger (Run: bare)`n"; Message = 'no Usage & Cost table this report recognizes' }
    ) {
        $project = New-GovProject
        New-GovSquadRoot -Root $project.State -Ledger $Ledger -History (New-GovDefaultHistory)
        if ($Case -eq 'empty') { Write-GovFile (Join-Path $project.State 'consumption.md') '' }
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Spend.Usd | Should -BeNullOrEmpty
        $report.Model.Economics.Spend.Basis | Should -Be 'unavailable'
        $report.Model.Economics.Rollup | Should -BeNullOrEmpty
        (@($report.Model.Quality | ForEach-Object Message) -join ' ') | Should -Match ([regex]::Escape($Message))
        $report.Html | Should -Match '(?s)<div class="rc-label">Run ROI</div><div class="rc-value">Not derivable</div>'
        $report.Text | Should -Match 'No data Cost \(unavailable\)'
        $report.Model.Header.Dispatches | Should -Be 7 -Because 'dispatch counts come from history, not from the ledger'
        (Get-SquadGovernanceReceipt -Model $report.Model).Summary | Should -Match '7 dispatches, no cost data'
    }
}

Describe 'GOV-13 unknown and unresolved models, fallback pricing and stale summaries stay visible' {
    BeforeAll {
        $script:Unknown = New-GovProject
        New-GovSquadRoot -Root $script:Unknown.State -Ledger $script:UnknownModelLedger -History (New-GovDefaultHistory)
        $script:UnknownReport = Get-GovReport -Project $script:Unknown
    }

    It 'never presents a fallback price as an observed model' {
        $notes = @($script:UnknownReport.Model.Quality)
        ($notes | Where-Object Code -eq 'model-unresolved').Message | Should -Match "Role 'researcher': model identity is unresolved \(unknown\); it is priced as Claude Sonnet 4.6, which is a rate fallback and not an observed model"
        ($notes | Where-Object Code -eq 'priced-as-differs').Message | Should -Match "Role 'developer': recorded model claude-sonnet-5 is priced as Claude Haiku 4.5"
        ($notes | Where-Object Code -eq 'tier-default').Severity | Should -Be 'info'
        $row = Find-GovRow $script:UnknownReport.Tables '^Role\|Member\|Agent\|Model\|Model Source' 'researcher'
        $row[3] | Should -Be 'unknown'
        $row[4] | Should -Be 'unresolved'
        $script:UnknownReport.Html | Should -Match '<span class="chip chip-bad">unknown</span>'
        $script:UnknownReport.Html | Should -Match '<span class="chip chip-warn">tier-default</span>'
    }

    It 'does not count an unknown model as evidence of model right-sizing' {
        $claim = $script:UnknownReport.Model.Justifications.Cost | Where-Object Title -eq 'Right-sized models per role'
        $claim.State | Should -Be 'shown'
        $claim.Detail | Should -Match '^2 distinct models served the roles'
        $claim.Detail | Should -Not -Match '(?i)unknown'

        $oneKnown = $script:UnknownModelLedger.Replace('| orchestration |  | Squad Scribe | Claude Haiku 4.5 | agent-pinned |', '| orchestration |  | Squad Scribe | claude-sonnet-5 | session-inherited |')
        $project = New-GovProject
        New-GovSquadRoot -Root $project.State -Ledger $oneKnown -History (New-GovDefaultHistory)
        $single = (Get-GovReport -Project $project).Model.Justifications.Cost | Where-Object Title -eq 'Right-sized models per role'
        $single.State | Should -Be 'unavailable'
        $single.Detail | Should -Match 'Every role ran on one model \(claude-sonnet-5\)'
    }

    It 'flags a stale basis note, a divergent state.json total, and a ledger total that differs from its rows without repairing any of them' {
        $stale = New-GovProject
        $state = $script:StateText.Replace('"estCostUsd": 1.0', '"estCostUsd": 0.5')
        New-GovSquadRoot -Root $stale.State -Ledger $script:StaleNoteLedger.Replace('| **1.0000** |', '| **1.7500** |') -History (New-GovDefaultHistory) -State $state
        $report = Get-GovReport -Project $stale
        $codes = @($report.Model.Quality | ForEach-Object Code)
        $codes | Should -Contain 'basis-note-conflict'
        $codes | Should -Contain 'state-ledger-divergence'
        $codes | Should -Contain 'total-mismatch'
        $report.Text | Should -Match 'Basis: estimated. No per-dispatch token telemetry exists.'
        $report.Model.Economics.Spend.Usd | Should -Be 1.75
        (Find-GovRow $report.Tables '^Role\|Requests' 'Total')[6] | Should -Be '1.7500'
    }

    It 'renders usage rows that have no Attribution row while the rate table is present (<Case>)' -ForEach @(
        @{ Case = 'no Attribution section'; Pattern = '(?s)## Attribution.*?(?=## Usage & Cost)'; Replacement = '' }
        @{ Case = 'one role missing from Attribution'; Pattern = '\| tester \| Gamma[^\r\n]*\r?\n'; Replacement = '' }
        @{ Case = 'a role renamed in one table only'; Pattern = '\| researcher \| Alpha \|'; Replacement = '| scout | Alpha |' }
    ) {
        $project = New-GovProject
        New-GovRichRoot -Root $project.State -Ledger ([regex]::Replace($script:ExactLedger, $Pattern, $Replacement))
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Spend.Usd | Should -Be 1.0
        @($report.Model.Quality | ForEach-Object Code) | Should -Contain 'attribution-missing'
        $report.Html | Should -Match 'Methodology: rates, observation date, calibration'
    }

    It 'does not read a relabeled Total row as one more role (<Case>)' -ForEach @(
        @{ Case = 'Total (all roles)'; Label = '**Total (all roles)**'; Inferred = $false }
        @{ Case = 'a bold label that does not say total'; Label = '**All roles**'; Inferred = $true }
        @{ Case = 'a blank label'; Label = ''; Inferred = $true }
    ) {
        $project = New-GovProject
        New-GovRichRoot -Root $project.State -Ledger $script:ExactLedger.Replace('| **Total** | **14** |', "| $Label | **14** |")
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Spend.Usd | Should -Be 1.0 -Because 'a relabeled total must not be added to the roles'
        $report.Model.Economics.Spend.Credits | Should -Be 100
        @($report.Model.Economics.ByRole | ForEach-Object Role) | Should -Be @('researcher', 'developer', 'tester', 'orchestration')
        (@($report.Model.Quality | ForEach-Object Code) -contains 'total-row-inferred') | Should -Be $Inferred
    }

    It 'keeps a plain last row as a role even when it equals the sum above it, so a figure is never silently dropped' {
        $project = New-GovProject
        $ledger = [regex]::Replace($script:ExactLedger, '\| \*\*Total\*\*[^\r\n]*', '| extra | 14 | 135,000 | 300,000 | 11,000 | 25,000 | 1.0000 | 100.00 | exact-native |')
        New-GovRichRoot -Root $project.State -Ledger $ledger
        $report = Get-GovReport -Project $project
        @($report.Model.Economics.ByRole | ForEach-Object Role) | Should -Contain 'extra'
        $report.Model.Economics.Spend.Usd | Should -Be 2.0
        $codes = @($report.Model.Quality | ForEach-Object Code)
        $codes | Should -Contain 'total-row-missing'
        $codes | Should -Not -Contain 'total-row-inferred'
    }

    It 'keeps a role whose name only begins with "total" as a role' {
        $project = New-GovProject
        $ledger = $script:ExactLedger.Replace('| tester | Gamma |', '| Total Recall Analyst | Gamma |').Replace('| tester | 2 |', '| Total Recall Analyst | 2 |')
        New-GovRichRoot -Root $project.State -Ledger $ledger
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Spend.Usd | Should -Be 1.0
        @($report.Model.Economics.ByRole | ForEach-Object Role) | Should -Be @('researcher', 'developer', 'Total Recall Analyst', 'orchestration')
        $codes = @($report.Model.Quality | ForEach-Object Code)
        $codes | Should -Not -Contain 'total-row-missing'
        $codes | Should -Not -Contain 'total-row-inferred'
        $codes | Should -Not -Contain 'total-mismatch'
    }

    It 'does not read a bold last row as the total when it is named as a role (<Case>)' -ForEach @(
        @{ Case = 'its label is not bold and no Attribution row names it'; Row = '| overall | 4 | 15,000 | 40,000 | 4,000 | 4,000 | **0.8500** | 85.00 | exact-native |'; Role = 'overall' }
        @{ Case = 'its label is not bold'; Row = '| orchestration | 4 | 15,000 | 40,000 | 4,000 | 4,000 | **0.8500** | 85.00 | exact-native |'; Role = 'orchestration' }
        @{ Case = 'an Attribution row names it'; Row = '| **orchestration** | 4 | 15,000 | 40,000 | 4,000 | 4,000 | **0.8500** | **85.00** | exact-native |'; Role = 'orchestration' }
    ) {
        $project = New-GovProject
        $ledger = [regex]::Replace($script:ExactLedger, '\| orchestration \| 4 \| 15,000[^\r\n]*\r?\n\| \*\*Total\*\*[^\r\n]*', $Row)
        New-GovRichRoot -Root $project.State -Ledger $ledger
        $report = Get-GovReport -Project $project
        @($report.Model.Economics.ByRole | ForEach-Object Role) | Should -Contain $Role
        $report.Model.Economics.Spend.Usd | Should -Be 1.7 -Because 'a role is never dropped on the strength of a coincidence'
        $codes = @($report.Model.Quality | ForEach-Object Code)
        $codes | Should -Contain 'total-row-missing'
        $codes | Should -Not -Contain 'total-row-inferred'
    }
}

Describe 'GOV-14 Unit Economics is optional' {
    It 'omits no figure and invents none when the ledger has no Unit Economics section' {
        $ledger = [regex]::Replace($script:ExactLedger, '(?s)## Unit Economics \(value\).*?(?=## Cost Comparison)', '')
        $project = New-GovProject
        New-GovRichRoot -Root $project.State -Ledger $ledger
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Value | Should -BeNullOrEmpty
        $report.Text | Should -Not -Match 'Accepted by an independent review'
        $report.Text | Should -Match 'Unit Economics \(value\) not recorded unavailable'
        ($report.Model.Justifications.Output | Where-Object Title -eq 'Independent review before acceptance').State | Should -Be 'unavailable'
        $report.Html | Should -Match '(?s)<div class="rc-label">Per accepted deliverable</div><div class="rc-value">Not recorded</div>'
    }

    It 'derives cost per accepted deliverable from the ledger when it is present' {
        $script:RichReport.Model.Economics.Value.Accepted | Should -Be 3
        [Math]::Round([double]$script:RichReport.Model.Economics.Value.CostPerAcceptedUsd, 4) | Should -Be 0.3333
        ($script:RichReport.Model.Justifications.Output | Where-Object Title -eq 'Independent review before acceptance').Detail | Should -Match '3 of 4 deliverable\(s\) accepted by an independent review \(0 rejected, 1 unreviewed\); first-pass yield 66.7%'
    }
}

Describe 'GOV-15 the report follows the ledger: nothing is enumerated, nothing is silently dropped' {
    It 'renders a section and a column the ledger gains later, with no change to the report' {
        $future = $script:ExactLedger.Replace('| Role | Requests | In Tokens | Cached | Cache Wr | Out Tokens | Exact Cost (USD) | Exact Credits | Basis |', '| Role | Requests | In Tokens | Cached | Cache Wr | Out Tokens | Exact Cost (USD) | Exact Credits | Basis | Latency P95 (ms) |')
        $future = $future.Replace('| ---- | -------- | --------- | ------ | -------- | ---------- | ---------------- | ------------- | ----- |', '| ---- | -------- | --------- | ------ | -------- | ---------- | ---------------- | ------------- | ----- | ---: |')
        $future = $future.Replace('| researcher | 3 | 40,000 | 80,000 | 5,000 | 6,000 | 0.3000 | 30.00 | exact-native |', '| researcher | 3 | 40,000 | 80,000 | 5,000 | 6,000 | 0.3000 | 30.00 | exact-native | 1,234 |')
        $future += "`n## Carbon Footprint (estimated)`n`n| Scope | gCO2e | Method |`n| ----- | ----- | ------ |`n| Inference | 412.5 | location-based |`n`nCarbon figures are indicative only.`n"
        $project = New-GovProject
        New-GovRichRoot -Root $project.State -Ledger $future
        $report = Get-GovReport -Project $project
        $report.Text | Should -Match 'Carbon Footprint \(estimated\)'
        (Find-GovRow $report.Tables '^Scope\|gCO2e\|Method$' 'Inference') | Should -Be @('Inference', '412.5', 'location-based')
        $report.Text | Should -Match 'Carbon figures are indicative only.'
        $usage = @($report.Tables | Where-Object { $_.Headers -contains 'Latency P95 (ms)' })
        (Find-GovRow $usage '^Role\|' 'researcher')[9] | Should -Be '1,234'
        $report.Model.Economics.Spend.Usd | Should -Be 1.0 -Because 'a new column must not disturb the recognized figures'
        Get-GovMissingLedgerTokens -LedgerText $future -Text $report.Text | Should -BeNullOrEmpty
    }

    It 'degrades to not derivable, and says so, when the Usage & Cost headers are not recognized' {
        $renamed = $script:ExactLedger.Replace('Exact Cost (USD)', 'Spend').Replace('Exact Credits', 'Units')
        $project = New-GovProject
        New-GovRichRoot -Root $project.State -Ledger $renamed
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Spend.Usd | Should -BeNullOrEmpty
        $report.Text | Should -Match 'Cost \(unavailable\)'
        $report.Text | Should -Match 'No data'
        @($report.Model.Quality | ForEach-Object Code) | Should -Contain 'usage-table-unrecognized'
        (Find-GovRow $report.Tables '^Role\|Requests\|In Tokens\|Cached\|Cache Wr\|Out Tokens\|Spend\|Units\|Basis$' 'Total')[6] | Should -Be '1.0000'
        Get-GovMissingLedgerTokens -LedgerText $renamed -Text $report.Text | Should -BeNullOrEmpty
    }

    It 'shows the complete source of the ledger the real writer produces from native session records' -Skip:(-not (Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
        $project = New-GovProject
        $null = New-Item -ItemType Directory -Path $project.State -Force
        Copy-Item -Path (Join-Path $script:FixtureRoot 'applied/*') -Destination $project.State -Recurse -Force
        $copilotHome = Join-Path $project.Project '_copilot_home'
        $session = Join-Path $copilotHome 'session-state/sess-0001'
        $null = New-Item -ItemType Directory -Path $session -Force
        Write-GovFile (Join-Path $session 'workspace.yaml') "id: sess-0001`ncwd: $($project.Project)`n"
        $usage = {
            param($agent, $id, $model, $inTokens, $cached, $cacheWrite, $output, $rates, $stamp)
            $details = @(
                @{ tokenType = 'input'; tokenCount = $inTokens; batchSize = 1000000; costPerBatch = [decimal]$rates[0] * [decimal]1e11 }
                @{ tokenType = 'cache_read'; tokenCount = $cached; batchSize = 1000000; costPerBatch = [decimal]$rates[1] * [decimal]1e11 }
                @{ tokenType = 'cache_write'; tokenCount = $cacheWrite; batchSize = 1000000; costPerBatch = [decimal]$rates[2] * [decimal]1e11 }
                @{ tokenType = 'output'; tokenCount = $output; batchSize = 1000000; costPerBatch = [decimal]$rates[3] * [decimal]1e11 }
            )
            $nano = [decimal]0
            foreach ($d in $details) { $nano += [decimal]$d.tokenCount * [decimal]$d.costPerBatch / [decimal]$d.batchSize }
            @{ type = 'session.usage_record'; agentId = $agent; timestamp = $stamp; data = @{ usage = @{
                        model = $model; inputTokens = $inTokens + $cached + $cacheWrite; outputTokens = $output; cacheReadTokens = $cached; cacheWriteTokens = $cacheWrite
                        aiCreditsStatus = 'complete'; copilotUsage = @{ totalNanoAiu = $nano; tokenDetails = $details }; accounting = @{ sourceSessionId = "src-$agent"; usageId = $id }
                    } } } | ConvertTo-Json -Depth 12 -Compress
        }
        $events = @(
            '{"type":"session.start","data":{"sessionId":"sess-0001"},"timestamp":"2026-09-27T09:59:00.000Z"}'
            '{"type":"subagent.started","agentId":"owner-research","data":{"toolCallId":"t1","agentName":"Squad Researcher","agentDisplayName":"researcher","model":"claude-sonnet-4.6"},"timestamp":"2026-10-01T10:00:02.000Z"}'
            (& $usage 'owner-research' 'one' 'claude-sonnet-4.6' 100000 80000 0 10000 @(3, 0.3, 3.75, 15) '2026-10-01T10:02:00.000Z')
            '{"type":"subagent.completed","agentId":"owner-research","data":{"toolCallId":"t1","agentName":"Squad Researcher","model":"claude-sonnet-4.6","totalTokens":190000,"durationMs":120000},"timestamp":"2026-10-01T10:02:01.000Z"}'
            '{"type":"subagent.started","agentId":"owner-scribe","data":{"toolCallId":"t2","agentName":"Squad Scribe","agentDisplayName":"scribe","model":"claude-haiku-4.5"},"timestamp":"2026-10-01T10:02:02.000Z"}'
            (& $usage 'owner-scribe' 'two' 'claude-haiku-4.5' 10000 40000 10000 5000 @(1, 0.1, 1.25, 5) '2026-10-01T10:03:00.000Z')
            '{"type":"subagent.completed","agentId":"owner-scribe","data":{"toolCallId":"t2","agentName":"Squad Scribe","model":"claude-haiku-4.5","totalTokens":65000,"durationMs":60000},"timestamp":"2026-10-01T10:03:01.000Z"}'
        )
        Write-GovFile (Join-Path $session 'events.jsonl') ($events -join "`n")
        $info = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        foreach ($argument in @('-NoProfile', '-File', $script:LedgerScript, '-SquadRoot', $project.State, '-SessionLog', $session, '-Write')) { $info.ArgumentList.Add($argument) }
        $info.Environment['COPILOT_HOME'] = $copilotHome
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.UseShellExecute = $false
        $writer = [Diagnostics.Process]::Start($info)
        $writerOutput = $writer.StandardOutput.ReadToEndAsync()
        $writerError = $writer.StandardError.ReadToEndAsync()
        $writer.WaitForExit()
        $writer.ExitCode | Should -Be 0 -Because ($writerOutput.Result + $writerError.Result)

        $ledger = [IO.File]::ReadAllText((Join-Path $project.State 'consumption.md'))
        $ledger | Should -Match 'exact-native'
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Spend.Basis | Should -Be 'exact-native'
        $report.Model.Economics.Spend.Usd | Should -Be 0.5255
        $report.Model.Economics.Rollup.Kind | Should -Be 'exact-native'
        $report.Model.Economics.Rollup.SquadUsd | Should -Be 0.5255
        $report.Model.Economics.Rollup.BaselineUsd | Should -Be 0.4740
        @($report.Model.Quality | ForEach-Object Code) | Should -Contain 'basis-note-conflict' -Because 'the writer leaves its Basis note unchanged, which the report must call out rather than repair'
        $report.Text | Should -Match 'Cost Comparison \(exact native actual\)'
        Get-GovMissingLedgerTokens -LedgerText $ledger -Text $report.Text | Should -BeNullOrEmpty
    }

    It 'shows every packaged and fixture ledger in full' -ForEach @(
        @{ Name = 'applied' }, @{ Name = 'seed' }
    ) {
        $project = New-GovProject
        Copy-Item -Path (Join-Path $script:FixtureRoot "$Name/*") -Destination $project.State -Recurse -Force
        $report = Get-GovReport -Project $project
        Get-GovMissingLedgerTokens -LedgerText ([IO.File]::ReadAllText((Join-Path $project.State 'consumption.md'))) -Text $report.Text | Should -BeNullOrEmpty
    }
}

Describe 'GOV-16 federation reports keep provenance and never double count shared host totals' {
    BeforeAll {
        $script:Fed = New-GovProject
        Write-GovFile (Join-Path $script:Fed.State 'federation.md') "# Squad Federation`n`n## Sub-Squads`n`n| Sub-squad | Profile | Kind | Location | Owner | Description |`n|-----------|---------|------|----------|-------|-------------|`n| alpha | default | in-repo | members/alpha/ | team | first |`n"
        Write-GovFile (Join-Path $script:Fed.State 'decisions.md') "# Squad Federation Decisions`n"
        New-GovRichRoot -Root (Join-Path $script:Fed.State 'members/alpha')
        $shared = { param($ledger) $ledger.Replace('sess-legacy-1', 'sess-shared') }
        New-GovSquadRoot -Root (Join-Path $script:Fed.State 'members/bravo') -Ledger (& $shared $script:LegacyLedger) -History (New-GovDefaultHistory) -Journal ($script:JournalText.Replace('sess-rich-1', 'sess-bravo').Replace('"hash-a"', '"hash-b"'))
        New-GovSquadRoot -Root (Join-Path $script:Fed.State 'members/charlie') -Ledger (& $shared $script:LegacyLedger) -History (New-GovDefaultHistory)
        $script:FedReport = Get-GovReport -Project $script:Fed
        $script:FedBefore = Get-GovTreeHash $script:Fed.State
    }

    It 'aggregates every sub-squad, attributes each ledger, and labels a mixed-basis total with its per-basis subtotals' {
        $script:FedReport.Model.Meta.Mode | Should -Be 'federation'
        $script:FedReport.Model.Meta.Units | Should -Be @('alpha', 'bravo', 'charlie')
        $script:FedReport.Model.Header.Dispatches | Should -Be 21
        $script:FedReport.Model.Economics.Spend.Usd | Should -Be 2.6
        $script:FedReport.Model.Economics.Spend.Basis | Should -Be 'mixed'
        $subtotals = @($script:FedReport.Model.Economics.Spend.ByBasis)
        ($subtotals | Where-Object Basis -eq 'exact-native').Usd | Should -Be 1.0
        ($subtotals | Where-Object Basis -eq 'estimated').Usd | Should -Be 1.6
        $script:FedReport.Html | Should -Match 'Cost \(mixed basis\)'
        $script:FedReport.Html | Should -Match 'estimated \$1.6000 · exact-native \$1.0000'
        @($script:FedReport.Model.Quality | ForEach-Object Code) | Should -Contain 'mixed-scope-basis'
    }

    It 'counts a whole-session host-billed total shared by two sub-squads once' {
        $hostBilled = $script:FedReport.Model.Economics.HostBilled
        $hostBilled.Sessions.Count | Should -Be 1
        $hostBilled.Duplicates.Count | Should -Be 1
        $hostBilled.Credits | Should -Be 120
        $row = Find-GovRow $script:FedReport.Tables '^Figure\|Value\|Basis\|Scope$' 'Host-reported whole-session billed'
        $row[1] | Should -Be '120.00 AI credits ($1.20)'
        $row[3] | Should -Match '1 distinct session\(s\), each counted once'
        @($script:FedReport.Model.Quality | ForEach-Object Code) | Should -Contain 'shared-session'
    }

    It 'warns when sub-squad journals share native request identities' {
        @($script:FedReport.Model.Quality | ForEach-Object Code) | Should -Contain 'native-overlap'
        $script:FedReport.Model.Economics.NativeOverlap | Should -Contain 'hash-b'
    }

    It 'does not call a missing request identity an overlap between sub-squad journals' {
        $project = New-GovProject
        Write-GovFile (Join-Path $project.State 'federation.md') "# Squad Federation`n`n## Sub-Squads`n`n| Sub-squad | Profile | Kind | Location | Owner | Description |`n|-----------|---------|------|----------|-------|-------------|`n| alpha | default | in-repo | members/alpha/ | team | first |`n| bravo | default | in-repo | members/bravo/ | team | second |`n"
        Write-GovFile (Join-Path $project.State 'decisions.md') "# Squad Federation Decisions`n"
        $anonymous = '{"sessions":[{"sessionId":"s-%","rows":[{"requestDetails":[{"identityHash":null},{"identityHash":""},{"identityHash":false},{"other":1}]}]}]}'
        New-GovSquadRoot -Root (Join-Path $project.State 'members/alpha') -Ledger $script:ExactLedger -History (New-GovDefaultHistory) -Journal $anonymous.Replace('%', 'a')
        New-GovSquadRoot -Root (Join-Path $project.State 'members/bravo') -Ledger $script:ExactLedger -History (New-GovDefaultHistory) -Journal $anonymous.Replace('%', 'b')
        $report = Get-GovReport -Project $project
        @($report.Model.Meta.Units) | Should -Be @('alpha', 'bravo')
        @($report.Model.Quality | ForEach-Object Code) | Should -Not -Contain 'native-overlap'
        @($report.Model.Economics.NativeOverlap).Count | Should -Be 0
    }

    It 'rolls the comparison up only over ledgers that state both figures and says how many that is' {
        $roll = $script:FedReport.Model.Economics.Rollup
        $roll.Covered | Should -Be 3
        $roll.SquadUsd | Should -Be 2.6
        $roll.BaselineUsd | Should -Be 6.5
        $roll.Kind | Should -Be 'mixed'
    }

    It 'shows one ledger per sub-squad and attributes the trigger provenance' {
        foreach ($name in 'alpha', 'bravo', 'charlie') { $script:FedReport.Html | Should -Match "<summary>Ledger: $name" }
        $row = Find-GovRow $script:FedReport.Tables '^Squad\|Trigger\|Ledger run' 'alpha'
        $row[1] | Should -Be 'issue Peter-N91/hve-squad#164 by Peter-N91'
        $row[2] | Should -Be 'rich-exact'
    }

    It 'scopes to one sub-squad and reads nothing outside it' {
        $project = $script:Fed
        $report = Get-GovReport -Project $project -Squad 'bravo'
        $report.Model.Meta.Units | Should -Be @('bravo')
        $report.Model.Economics.Spend.Basis | Should -Be 'estimated'
        @($report.Model.Sources | ForEach-Object Path) | ForEach-Object { $_ | Should -Match 'members/bravo/' }
        $report.Model.RootUnit | Should -BeNullOrEmpty
        $report.Html | Should -Match 'Sub-squad: bravo'
    }

    It 'rejects an unknown or malformed sub-squad name' {
        { Get-GovReport -Project $script:Fed -Squad 'nope' } | Should -Throw '*Sub-squad ''nope'' was not found under members/. Available: alpha, bravo, charlie.*'
        { Get-GovReport -Project $script:Fed -Squad '../alpha' } | Should -Throw '*is not valid*'
    }

    It 'leaves every squad state file untouched (GOV-06)' {
        (Get-GovTreeHash $script:Fed.State) | Should -Be $script:FedBefore
    }

    It 'keeps rendering when a sub-squad has no ledger and another has a Usage & Cost table it cannot recognize' {
        $project = New-GovProject
        Write-GovFile (Join-Path $project.State 'federation.md') "# Squad Federation`n`n## Sub-Squads`n`n| Sub-squad | Profile | Kind | Location | Owner | Description |`n|-----------|---------|------|----------|-------|-------------|`n| alpha | default | in-repo | members/alpha/ | team | first |`n"
        New-GovRichRoot -Root (Join-Path $project.State 'members/alpha')
        $renamed = $script:ExactLedger.Replace('| Role | Requests | In Tokens |', '| Agent role | Requests | In Tokens |')
        New-GovSquadRoot -Root (Join-Path $project.State 'members/bravo') -Ledger $renamed -History (New-GovDefaultHistory)
        New-GovSquadRoot -Root (Join-Path $project.State 'members/charlie') -Ledger $null -History (New-GovDefaultHistory)
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Spend.Usd | Should -Be 1.0 -Because 'only alpha has a Usage & Cost table the report recognizes'
        $codes = @($report.Model.Quality | ForEach-Object Code)
        $codes | Should -Contain 'usage-table-unrecognized'
        $codes | Should -Contain 'ledger-missing'
        foreach ($name in 'bravo', 'charlie') {
            $report.Html | Should -Match "<summary>Ledger: $name"
            (Get-GovReport -Project $project -Squad $name).Model.Meta.Units | Should -Be @($name)
        }
        Get-GovMissingLedgerTokens -LedgerText $renamed -Text $report.Text | Should -BeNullOrEmpty -Because 'an unrecognized table is still shown as the ledger prints it'
    }
}

Describe 'GOV-17 the period filter never presents cumulative ledger totals as period-specific' {
    BeforeAll {
        $script:Period = New-GovProject
        New-GovRichRoot -Root $script:Period.State
        $script:All = Get-GovReport -Project $script:Period
        $script:Last7 = Get-GovReport -Project $script:Period -Period '7d'
        $script:Last30 = Get-GovReport -Project $script:Period -Period '30d'
    }

    It 'filters dated entries by the window ending at -AsOf' {
        $script:All.Model.Header.Dispatches | Should -Be 7
        $script:Last30.Model.Header.Dispatches | Should -Be 7 -Because 'every fixture entry (2026-10-10 to 2026-10-14) is inside the 30 days ending 2026-11-02'
        $script:Last7.Model.Header.Dispatches | Should -Be 0 -Because 'every fixture entry is older than 7 days before 2026-11-02'
        $script:Last30.Model.Meta.SpanStart.ToString('yyyy-MM-dd') | Should -Be '2026-10-04'
        $script:Last30.Text | Should -Match 'Period: 2026-10-04 to 2026-11-02 \(30 days\)'
        $script:Last7.Text | Should -Match 'Period: 2026-10-27 to 2026-11-02 \(7 days\)'
    }

    It 'labels ledger figures cumulative and identifies the unsupported breakdown' {
        $script:Last30.Html | Should -Match 'cumulative ledger'
        ($script:Last30.Model.Quality | Where-Object Code -eq 'period-cumulative').Message | Should -Match 'cumulative for the whole run and are not filtered to the 30d period; the ledger records no per-period breakdown'
        $script:Last30.Model.Economics.Spend.Usd | Should -Be 1.0
        @($script:All.Model.Quality | ForEach-Object Code) | Should -Not -Contain 'period-cumulative'
    }

    It 'keeps the empty states instead of omitting sections' {
        $script:Last7.Text | Should -Match 'No council reviews were triggered during this period'
        $script:Last7.Text | Should -Match 'No dispatch entries were recorded in this period'
        $script:Last7.Text | Should -Match '6. Activity Timeline No dated activity was recorded in this period'
    }

    It 'includes a verdict and a dispatch inside the window' {
        $project = New-GovProject
        $recent = $script:DecisionsText.Replace('2026-10-14 public-api', '2026-10-30 public-api')
        $history = New-GovDefaultHistory
        $history['Squad Researcher'] = New-GovHistory 'Squad Researcher' @(@{ Ts = '2026-10-31T09:10:00Z'; Title = 'Late survey'; Turn = 7; Request = 'x'; Deliverable = '`research/late.md`'; Outcome = 'Done.' })
        New-GovSquadRoot -Root $project.State -Ledger $script:ExactLedger -History $history -Decisions $recent
        $report = Get-GovReport -Project $project -Period '7d'
        $report.Model.Header.Dispatches | Should -Be 1
        $report.Model.Governance.CouncilCount | Should -Be 1
        $report.Model.Governance.VerdictCounts['Stop'] | Should -Be 1
    }
}

Describe 'GOV-18 governance sections keep their grounded counts' {
    It 'counts council verdicts, findings by role and outstanding conditions per latest verdict' {
        $g = $script:RichReport.Model.Governance
        $g.CouncilCount | Should -Be 3
        $g.VerdictCounts['Go'] | Should -Be 1
        $g.VerdictCounts['Go-With-Conditions'] | Should -Be 1
        $g.VerdictCounts['Stop'] | Should -Be 1
        $g.Outstanding | Should -Be 3
        $security = Find-GovRow $script:RichReport.Tables '^Role\|Approve\|Conditional\|Concern\|Block\|Risk: High$' 'security'
        $security | Should -Be @('security', '1', '1', '0', '1', '1')
        $script:RichReport.Text | Should -Match 'Go 1 \(33%\)'
        $script:RichReport.Text | Should -Match '3 conditions outstanding'
    }

    It 'counts intake checks, discovery sessions and declines separately, and the human gate log' {
        $g = $script:RichReport.Model.Governance
        $g.IntakeCount | Should -Be 1
        $g.DiscoveryCount | Should -Be 1
        $g.DiscoveryDeclined | Should -Be 1
        $script:RichReport.Text | Should -Match 'Discovery sessions: 1 · Discovery offers declined: 1 · Council waivers: 0 · Cost preflight rounds: 2'
        $log = @($script:RichReport.Tables | Where-Object { ($_.Headers -join '|') -eq 'Turn|Date|Gate Type|Action|Status' })[0]
        $log.Rows.Count | Should -Be 2
        $log.Rows[0][1] | Should -Be '2026-10-15'
        $log.Rows[0][2] | Should -Be 'Impactful-Action Gate'
        $log.Rows[0][4] | Should -Be '✓ PASSED'
        $script:RichReport.Text | Should -Match '2 / 2 Human Gates Passed All passed'
    }

    It 'grounds dispatch counts in the history entries, with success, failure and tier from the records' {
        $d = $script:RichReport.Model.Dispatch
        $d.Total | Should -Be 7
        $d.DistinctRoles | Should -Be 5
        $d.Failed | Should -Be 1
        [Math]::Round([double]$d.SuccessRate, 1) | Should -Be 85.7
        $implementor = Find-GovRow $script:RichReport.Tables '^Role\|Agent\|Dispatches\|Model\|Key Activities$' 'Developer'
        $implementor[1] | Should -Be 'Squad Implementor'
        $implementor[2] | Should -Be '2'
        $tiers = @($d.Tiers | ForEach-Object { '{0}:{1}' -f $_.Tier, $_.Dispatches })
        $tiers | Should -Contain 'confirm:2'
        $tiers | Should -Contain 'auto:2'
        $tiers | Should -Contain 'gated:1'
    }

    It 'derives compliance indicators and outcomes from dispatch evidence' {
        $c = $script:RichReport.Model.Compliance
        $c.ArtifactEvidence | Should -Be @(7, 7)
        $c.CodeChanges | Should -Be 2
        $c.TestVerified | Should -Be 1 -Because 'the failed lint dispatch has no test evidence of its own and nothing verified it in the same turn'
        $c.ImpactfulFired | Should -Be 1
        $c.Notifications | Should -Be 2
        $o = $script:RichReport.Model.Outcomes
        $o.Files | Should -Be 5 -Because 'src/auth.py is delivered twice and state.json is a squad state path'
        $o.Tests | Should -Be 26
        $o.TestSources | Should -Be 2
        $o.Issues | Should -Be 2
    }

    It 'shows evidence-backed reasons HVE Squad paid off, in cost and in output' {
        $cost = $script:RichReport.Model.Justifications.Cost
        $cost[0].State | Should -Be 'shown'
        $cost[0].Detail | Should -Match 'HVE Squad spent \$1.0000 against \$2.5000 for the same work without HVE Squad \(single model: gpt-5.6-sol\): \$1.5000 \(60.0%\) lower. Return on spend 150%; the single-model approach would have cost 2.50× as much'
        ($cost | Where-Object Title -eq 'Spend is measured, not guessed').Detail | Should -Match '21 complete accounting record\(s\) through 2026-10-14T18:00:00.000Z'
        ($cost | Where-Object Title -eq 'Right-sized models per role').Detail | Should -Match '3 distinct models served the roles'
        ($cost | Where-Object Title -eq 'Spend guarded by a ceiling').Detail | Should -Match 'Cost ceiling \$5.00: 2 preflight round\(s\)'
        $output = $script:RichReport.Model.Justifications.Output
        ($output | Where-Object Title -eq 'Risk surfaced before implementation').Detail | Should -Match '3 council verdict\(s\) \(1 Go, 1 Go-With-Conditions, 1 Stop\) with 3 condition\(s\) outstanding, and 1 intake readiness check'
        ($output | Where-Object Title -eq 'Humans stay in control').Detail | Should -Match '2 human gate\(s\) fired: 2 passed, 0 blocked, 0 pending'
        $script:RichReport.Text | Should -Match 'Why HVE Squad: what this run spent'
        $script:RichReport.Text | Should -Match 'Why HVE Squad: what this run produced'
    }
}

Describe 'GOV-19 the report is deterministic, read-only and safe' {
    It 'produces byte-identical output for the same state and -AsOf, independent of file creation order' {
        $a = New-GovProject
        New-GovRichRoot -Root $a.State
        $b = New-GovProject
        $files = Get-ChildItem -LiteralPath $a.State -Recurse -File | Sort-Object FullName -Descending
        foreach ($file in $files) { Write-GovFile (Join-Path $b.State ([IO.Path]::GetRelativePath($a.State, $file.FullName))) ([IO.File]::ReadAllText($file.FullName)) }
        $first = (Get-GovReport -Project $a).Html
        $second = (Get-GovReport -Project $b).Html
        $first | Should -BeExactly $second
        $first | Should -BeExactly (Get-GovReport -Project $a).Html
    }

    It 'does not change a single byte of squad state' {
        $project = New-GovProject
        New-GovRichRoot -Root $project.State
        $before = Get-GovTreeHash $project.State
        $null = Get-GovReport -Project $project
        $null = Get-GovReport -Project $project -Period '7d'
        Get-GovTreeHash $project.State | Should -Be $before
    }

    It 'escapes hostile state content: it can never inject markup or an external reference' {
        $project = New-GovProject
        $hostile = '<script>alert(1)</script><img src="https://evil.example/x.png" onerror="x()">'
        $history = New-GovDefaultHistory
        $history['Squad Researcher'] = New-GovHistory 'Squad Researcher' @(@{ Ts = '2026-10-10T09:10:00Z'; Title = "Survey $hostile"; Turn = 1; Request = 'x'; Deliverable = '`research/a.md`'; Outcome = $hostile })
        New-GovSquadRoot -Root $project.State -Ledger ($script:ExactLedger.Replace('Coordinator+Scribe', $hostile)) -History $history
        $report = Get-GovReport -Project $project
        $report.Html | Should -Not -Match '(?i)<(script|img|iframe|object|embed|link|form)\b'
        $report.Html | Should -Not -Match '(?i)<[^>]*\son[a-z]+\s*='
        $report.Html | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
        $report.Html | Should -Not -Match '(?i)\b(src|href)\s*=\s*"?\s*https?:'
    }

    It 'does not follow a linked history directory out of the squad root' {
        $project = New-GovProject
        New-GovRichRoot -Root $project.State
        $outside = Join-Path $project.Project 'outside-history'
        Write-GovFile (Join-Path $outside 'Linked Agent.md') (New-GovHistory 'Linked Agent' @(@{ Ts = '2026-10-10T09:10:00Z'; Title = 'Leaked'; Turn = 1; Request = 'x'; Deliverable = '`a.md`'; Outcome = 'Leaked.' }))
        $link = Join-Path $project.State 'history'
        Remove-Item -LiteralPath $link -Recurse -Force
        try { $null = New-Item -ItemType $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }) -Path $link -Target $outside -ErrorAction Stop }
        catch { Set-ItResult -Skipped -Because 'links are not permitted in this environment'; return }
        try {
            $report = Get-GovReport -Project $project
            $report.Text | Should -Not -Match 'Leaked'
            $report.Model.Header.Dispatches | Should -Be 0
            @($report.Model.Skipped) | Should -Contain '.copilot-tracking/squad/history (linked path; not followed)'
        }
        finally { [IO.Directory]::Delete($link) }
    }

    It 'does not follow a linked members directory out of a federation root' {
        $project = New-GovProject
        Write-GovFile (Join-Path $project.State 'federation.md') "# Squad Federation`n"
        $outside = Join-Path $project.Project 'outside-members'
        New-GovSquadRoot -Root (Join-Path $outside 'secret-member') -Ledger $script:ExactLedger -History (New-GovDefaultHistory)
        $link = Join-Path $project.State 'members'
        try { $null = New-Item -ItemType $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }) -Path $link -Target $outside -ErrorAction Stop }
        catch { Set-ItResult -Skipped -Because 'links are not permitted in this environment'; return }
        try {
            $report = Get-GovReport -Project $project
            @($report.Model.Meta.Units) | Should -BeNullOrEmpty
            $report.Text | Should -Not -Match 'secret-member'
            @($report.Model.Skipped) | Should -Contain '.copilot-tracking/squad/members (linked path; not followed)'
        }
        finally { [IO.Directory]::Delete($link) }
    }

    It 'gives the same bytes whatever the culture of the calling session is' {
        $project = New-GovProject
        New-GovRichRoot -Root $project.State
        $baseline = (Get-GovReport -Project $project).Html
        $previous = [Globalization.CultureInfo]::CurrentCulture
        try {
            foreach ($name in 'fr-FR', 'de-DE', 'tr-TR', 'ar-SA', 'ja-JP') {
                try { $culture = [Globalization.CultureInfo]::GetCultureInfo($name) } catch { continue }
                [Globalization.CultureInfo]::CurrentCulture = $culture
                (Get-GovReport -Project $project).Html | Should -BeExactly $baseline -Because "the $name culture must not change a byte"
            }
        }
        finally { [Globalization.CultureInfo]::CurrentCulture = $previous }
        [Globalization.CultureInfo]::CurrentCulture.Name | Should -Be $previous.Name -Because 'the renderer restores the caller''s culture'
    }

    It 'does not follow a linked history file out of the squad root' -Skip:(-not ($IsWindows -or $IsLinux -or $IsMacOS)) {
        $project = New-GovProject
        New-GovRichRoot -Root $project.State
        $outside = Join-Path $project.Project 'outside.md'
        Write-GovFile $outside (New-GovHistory 'Linked Agent' @(@{ Ts = '2026-10-10T09:10:00Z'; Title = 'Leaked'; Turn = 1; Request = 'x'; Deliverable = '`a.md`'; Outcome = 'Leaked.' }))
        try { $null = New-Item -ItemType SymbolicLink -Path (Join-Path $project.State 'history/Linked Agent.md') -Target $outside -ErrorAction Stop }
        catch { Set-ItResult -Skipped -Because 'symbolic links are not permitted in this environment'; return }
        $report = Get-GovReport -Project $project
        $report.Text | Should -Not -Match 'Leaked'
        @($report.Model.Skipped) | Should -Contain '.copilot-tracking/squad/history/Linked Agent.md (linked path; not followed)'
    }
}

Describe 'GOV-20 the command writes one local file and reports it' {
    BeforeDiscovery {
        $OutputRefusals = @(
            @{ Target = 'https://example.com/report.html'; Reason = 'not a local filesystem path' }
            @{ Target = '\\server\share\report.html'; Reason = 'not a local filesystem path' }
            @{ Target = '\\?\UNC\server\share\report.html'; Reason = 'not a local filesystem path' }
            @{ Target = 'docs/'; Reason = 'names a directory' }
            @{ Target = 'docs\'; Reason = 'names a directory' }
            @{ Target = '.copilot-tracking/squad/state.json'; Reason = 'inside the squad state tree' }
            @{ Target = '.copilot-tracking/squad/history/report.html'; Reason = 'inside the squad state tree' }
            @{ Target = '.copilot-tracking/squad/../squad/state.json'; Reason = 'inside the squad state tree' }
        )
        if ($IsWindows) {
            $OutputRefusals += @{ Target = 'C:report.html'; Reason = 'relative to a drive' }
            $OutputRefusals += @{ Target = 'docs/report.html:stream'; Reason = 'alternate data stream' }
        }
    }

    BeforeAll {
        $script:Cli1 = New-GovProject
        New-GovRichRoot -Root $script:Cli1.State
        $script:CliBefore = Get-GovTreeHash $script:Cli1.State
    }

    It 'writes docs/squad-governance-report-YYYY-MM-DD.html by default and prints a receipt (GOV-01)' {
        $result = Invoke-GovCli @('-ProjectRoot', $script:Cli1.Project, '-AsOf', '2026-11-02')
        $result.ExitCode | Should -Be 0 -Because $result.Error
        $receipt = $result.Output | ConvertFrom-Json
        $receipt.path | Should -Be 'docs/squad-governance-report-2026-11-02.html'
        (Test-Path -LiteralPath (Join-Path $script:Cli1.Project 'docs/squad-governance-report-2026-11-02.html')) | Should -BeTrue
        $receipt.status | Should -Be 'ok'
        $receipt.period | Should -Be 'all'
        $receipt.ledgerBasis | Should -Be 'exact-native'
        $receipt.summary | Should -Be '6 coordination turns, 7 dispatches, $1.0000 exact-native cost, 2 human gates, 0 escalations, ROI +150% vs without HVE Squad (exact-native)'
        $receipt.roi.roiPct | Should -Be 150
        $receipt.grounding | Should -Contain '.copilot-tracking/squad/consumption.md'
        $receipt.gaps | Should -Not -Contain 'Council Verdicts: Not activated'
        $receipt.sha256 | Should -Match '^[0-9a-f]{64}$'
        (Get-FileHash -LiteralPath (Join-Path $script:Cli1.Project 'docs/squad-governance-report-2026-11-02.html') -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $receipt.sha256
    }

    It 'matches the in-process renderer byte for byte and leaves squad state unmodified' {
        $path = Join-Path $script:Cli1.Project 'custom/out/report.html'
        $result = Invoke-GovCli @('-ProjectRoot', $script:Cli1.Project, '-AsOf', '2026-11-02', '-OutputPath', $path, '-ProjectName', 'fixture')
        $result.ExitCode | Should -Be 0 -Because $result.Error
        [IO.File]::ReadAllText($path) | Should -BeExactly (Get-GovReport -Project $script:Cli1).Html
        Get-GovTreeHash $script:Cli1.State | Should -Be $script:CliBefore
    }

    It 'stops with the documented message when there is no squad state' {
        $empty = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $empty -Force
        $result = Invoke-GovCli @('-ProjectRoot', $empty)
        $result.ExitCode | Should -Be 1
        $result.Error | Should -Match 'No squad state found. Run `/squad` to initialize a squad first.'
        $result.Output | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $empty 'docs') | Should -BeFalse
    }

    It 'refuses a remote, directory-like, or state-tree output path and writes nothing' -ForEach $OutputRefusals {
        $result = Invoke-GovCli @('-ProjectRoot', $script:Cli1.Project, '-OutputPath', $Target)
        $result.ExitCode | Should -Be 1
        $result.Error | Should -Match $Reason
        Get-GovTreeHash $script:Cli1.State | Should -Be $script:CliBefore
    }

    It 'refuses an output path that reaches the squad state tree through a link' {
        $project = New-GovProject
        New-GovRichRoot -Root $project.State
        $link = Join-Path $project.Project 'docs'
        try { $null = New-Item -ItemType $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }) -Path $link -Target $project.State -ErrorAction Stop }
        catch { Set-ItResult -Skipped -Because 'links are not permitted in this environment'; return }
        $before = Get-GovTreeHash $project.State
        try {
            $result = Invoke-GovCli @('-ProjectRoot', $project.Project, '-OutputPath', 'docs/report.html', '-AsOf', '2026-11-02')
            $result.ExitCode | Should -Be 1
            $result.Error | Should -Match 'inside the squad state tree'
            Get-GovTreeHash $project.State | Should -Be $before
        }
        finally { [IO.Directory]::Delete($link) }
    }

    It 'reports an invalid -AsOf and an unknown sub-squad clearly' {
        (Invoke-GovCli @('-ProjectRoot', $script:Cli1.Project, '-AsOf', 'not-a-date')).Error | Should -Match 'is not a valid date'
        $result = Invoke-GovCli @('-ProjectRoot', $script:Cli1.Project, '-Squad', 'alpha')
        $result.ExitCode | Should -Be 0
        ($result.Output | ConvertFrom-Json).gaps | Should -Contain 'squad=alpha was ignored: this is a single squad, not a federation.'
    }

    It 'exits 1 with the system message, and leaves nothing behind, when the output location cannot be written' {
        $project = New-GovProject
        New-GovRichRoot -Root $project.State
        [IO.File]::WriteAllText((Join-Path $project.Project 'a-file'), 'not a directory')
        $result = Invoke-GovCli @('-ProjectRoot', $project.Project, '-OutputPath', 'a-file/report.html', '-AsOf', '2026-11-02')
        $result.ExitCode | Should -Be 1 -Because $result.Error
        $result.Error | Should -Not -Match 'unexpected failure'
        $result.Output | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $project.Project -Recurse -File -Force | Where-Object Name -match '\.tmp$').Count | Should -Be 0
        [IO.File]::ReadAllText((Join-Path $project.Project 'a-file')) | Should -Be 'not a directory'
    }

    It 'exits 2, telling the agent to follow the manual steps, when the renderer module cannot be loaded' {
        $copy = Join-Path $TestDrive 'incomplete-skill'
        $null = New-Item -ItemType Directory -Path $copy -Force
        Copy-Item -Path (Join-Path $script:ScriptsRoot 'SquadGovernanceReport*.ps*1') -Destination $copy
        Copy-Item -LiteralPath $script:Cli -Destination $copy
        Remove-Item -LiteralPath (Join-Path $copy 'SquadGovernanceReport.Html.ps1')
        $result = Invoke-GovCli @('-ProjectRoot', $script:Cli1.Project, '-AsOf', '2026-11-02', '-OutputPath', (Join-Path $TestDrive 'never.html')) -Script (Join-Path $copy 'New-SquadGovernanceReport.ps1')
        $result.ExitCode | Should -Be 2
        $result.Error | Should -Match 'unexpected failure; follow the manual steps'
        $result.Output | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $TestDrive 'never.html') | Should -BeFalse
    }
}

Describe 'GOV-21 the agent delegates to the deterministic renderer and keeps its contract' {
    BeforeAll { $script:Agent = [IO.File]::ReadAllText($script:AgentPath) }

    It 'runs the packaged script first and falls back to the manual contract only when it is unavailable' {
        $script:Agent | Should -Match 'New-SquadGovernanceReport\.ps1'
        $script:Agent | Should -Match 'byte-identical|same inputs'
    }

    It 'tells the agent to relay a documented stop (exit 1) and to fall back to the manual steps on an unexpected failure (exit 2)' {
        $script:Agent | Should -Match 'Exit code 1 is a documented stop only when its message starts with `New-SquadGovernanceReport:`'
        $script:Agent | Should -Match 'relay that message and stop'
        $script:Agent | Should -Match 'Exit code 2 is an unexpected failure'
        $script:Agent | Should -Match 'perform Steps 1.5 manually and say that you did'
    }

    It 'requires the ledger to be rendered as a document and ROI and evidence to be derived, never enumerated' {
        $script:Agent | Should -Match 'every `##` and `###` section'
        $script:Agent | Should -Match 'never enumerate'
        $script:Agent | Should -Match 'ROI'
        $script:Agent | Should -Match 'Without HVE Squad'
    }

    It 'keeps the read-only, grounding and self-contained guardrails' {
        $script:Agent | Should -Match 'Squad state is \*\*read-only\*\*\. Never modify, delete, or append to any squad state file\.'
        $script:Agent | Should -Match 'Never invent data points'
        $script:Agent | Should -Match 'self-contained'
    }
}

Describe 'GOV-22 one malformed record never aborts the report' {
    It 'renders when state.json, the journal, history and decisions carry unusable values' {
        $project = New-GovProject
        $state = $script:StateText.Replace('"estCostUsd": 1.0', '"estCostUsd": "n/a"')
        $journal = $script:JournalText.Replace('"nanoAiu": 30000000000', '"nanoAiu": "abc"')
        $decisions = $script:DecisionsText.Replace('* Conditions Outstanding: 2', '* Conditions Outstanding: 99999999999999').Replace('* Remediation Cycles: 1', '* Remediation Cycles: 99999999999999')
        $history = New-GovDefaultHistory
        $odd = New-GovHistory 'Squad Researcher' @(@{ Ts = '2026-10-10T09:10:00Z'; Title = 'Odd turn'; Turn = 99999999999; Request = 'x'; Deliverable = '`a.md`'; Outcome = 'Done.' })
        $history['Squad Researcher'] = [regex]::Replace($odd, '(?s)```json\r?\n.*?\r?\n```', "``````json`n[1,2]`n``````")
        New-GovSquadRoot -Root $project.State -Ledger $script:ExactLedger -History $history -Decisions $decisions -Notifications $script:NotificationsText -State $state -Journal $journal -Runs @{ 'autopilot-run-run-1' = $script:AutopilotRunText }
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Spend.Usd | Should -Be 1.0
        $report.Model.Header.Dispatches | Should -Be 7
        @($report.Model.Quality | ForEach-Object Code) | Should -Not -Contain 'state-ledger-divergence' -Because 'an unusable state.json figure is ignored, not compared'
    }

    It 'renders a state.json that is not an object, and a journal that is not valid JSON' {
        $project = New-GovProject
        New-GovSquadRoot -Root $project.State -Ledger $script:ExactLedger -History (New-GovDefaultHistory) -State '[1,2,3]' -Journal '{"sessions": [1, "x", null'
        $report = Get-GovReport -Project $project
        $report.Model.Economics.Spend.Usd | Should -Be 1.0
        $report.Text | Should -Match 'consumption-sessions.json could not be read'
    }

    It 'parses JSON without reinterpreting date-like strings and without depending on the PowerShell version' {
        $module = Get-Module SquadGovernanceReport
        $parsed = & $module { ConvertFrom-SqJson -Text '{"when":"2026-10-20T12:00:00Z","day":"2026-10-20","n":[1,2.5,"x",null,true,false],"o":{},"e":[],"big":12345678901234567890,"deep":{"a":{"b":[{"c":1}]}},}' }
        $parsed['when'] | Should -BeOfType [string]
        $parsed['when'] | Should -BeExactly '2026-10-20T12:00:00Z'
        $parsed['day'] | Should -BeExactly '2026-10-20'
        $parsed['n'].Count | Should -Be 6
        $parsed['n'][0] | Should -Be 1
        $parsed['n'][1] | Should -Be 2.5
        $parsed['n'][2] | Should -BeExactly 'x'
        $parsed['n'][3] | Should -BeNullOrEmpty
        $parsed['n'][4] | Should -BeTrue
        $parsed['n'][5] | Should -BeFalse
        ($parsed['o'] -is [System.Collections.IDictionary]) | Should -BeTrue
        $parsed['o'].Count | Should -Be 0
        ($parsed['e'] -is [object[]]) | Should -BeTrue
        $parsed['e'].Count | Should -Be 0
        $parsed['big'] | Should -Be ([decimal]'12345678901234567890')
        $parsed['deep']['a']['b'][0]['c'] | Should -Be 1
        { & $module { ConvertFrom-SqJson -Text '{"a":' } } | Should -Throw '*Invalid JSON at line 1, position*'
    }

    It 'reports corrupt JSON without any text that follows the UI culture' {
        $project = New-GovProject
        New-GovSquadRoot -Root $project.State -Ledger $script:ExactLedger -History (New-GovDefaultHistory) -State '{ not json' -Journal '{"sessions": [ oops'
        $texts = Get-GovTextByUiCulture -Project $project
        if ($texts.Count -lt 2) { Set-ItResult -Skipped -Because 'fewer than two UI cultures are available (globalization-invariant runtime)'; return }
        @($texts | Select-Object -Unique).Count | Should -Be 1
        $texts[0] | Should -Match 'Invalid JSON at line 1, position \d+'
    }

    It 'reports a lone surrogate in a JSON string or property name with fixed text, in every UI culture' -ForEach @(
        @{ Case = 'a string value'; State = '{"a":"\ud800"}'; Journal = '{"sessions":[{"sessionId":"\ud800"}]}' }
        @{ Case = 'a property name'; State = '{"\ud800":1}'; Journal = '{"sessions":[{"\ud800":1,"rows":[{"requestDetails":[{"identityHash":"\udc00"}]}]}]}' }
    ) {
        $project = New-GovProject
        New-GovSquadRoot -Root $project.State -Ledger $script:ExactLedger -History (New-GovDefaultHistory) -State $State -Journal $Journal
        $texts = Get-GovTextByUiCulture -Project $project
        if ($texts.Count -lt 2) { Set-ItResult -Skipped -Because 'fewer than two UI cultures are available (globalization-invariant runtime)'; return }
        @($texts | Select-Object -Unique).Count | Should -Be 1
        $texts[0] | Should -Match 'state\.json could not be parsed: Invalid JSON value\.'
        $texts[0] | Should -Match 'consumption-sessions\.json could not be read \(a value is invalid or out of range\)'
        $texts[0] | Should -Not -Match 'Exception|GetString|InvalidOperation'
        (Get-GovReport -Project $project).Model.Economics.Spend.Usd | Should -Be 1.0
    }

    It 'shows a journal with an unreadable value as unreadable, with fixed text, and keeps the rest of the report (<Case>)' -ForEach @(
        @{ Case = 'an unpaired surrogate'; Journal = '{"sessions":[{"sessionId":"ok"},{"sessionId":"\ud800"}]}' }
        @{ Case = 'numbers whose sum overflows'; Journal = '{"sessions":[{"rows":[{"nanoAiu":79228162514264337593543950335},{"nanoAiu":79228162514264337593543950335}]}]}' }
    ) {
        $module = Get-Module SquadGovernanceReport
        $read = & $module { param($text) Read-SqJournal -Text $text } $Journal
        $read.Valid | Should -BeFalse
        $read.Error | Should -BeExactly 'a value is invalid or out of range'
        @($read.Sessions).Count | Should -Be 0
        @($read.RequestHashes).Count | Should -Be 0
        $project = New-GovProject
        New-GovSquadRoot -Root $project.State -Ledger $script:ExactLedger -History (New-GovDefaultHistory) -State $script:StateText -Journal $Journal
        $report = Get-GovReport -Project $project
        $report.Text | Should -Match 'consumption-sessions\.json could not be read \(a value is invalid or out of range\)'
        $report.Model.Economics.Spend.Usd | Should -Be 1.0
    }

    It 'never shows a message it did not write itself' {
        $module = Get-Module SquadGovernanceReport
        $text = & $module {
            $own = New-SqFixedError 'Invalid JSON value.'
            $runtime = try { [IO.File]::ReadAllText('Z:\no\such\file.txt') } catch { $_.Exception }
            @((Get-SqErrorText $own), (Get-SqErrorText $runtime), (Get-SqErrorText ([FormatException]::new('Input string was not in a correct format.'))))
        }
        $text[0] | Should -BeExactly 'Invalid JSON value.'
        $text[1] | Should -BeExactly 'unexpected read error'
        $text[2] | Should -BeExactly 'unexpected read error'
    }

    It 'reads the journal fields it needs and tolerates odd shapes' {
        $module = Get-Module SquadGovernanceReport
        $json = '{"sessions":[{"sessionId":"s1","records":"7","rows":[{"requests":2,"nanoAiu":"5000000000","requestDetails":[{"identityHash":"h1"},{"identityHash":2},"x",{"other":1},{"identityHash":null},{"identityHash":""},{"identityHash":true},{"identityHash":{"a":1}}]},"bad",{"requests":"abc","nanoAiu":null}]},"notAnObject",{"sessionId":"s2","rows":{"a":1}}]}'
        $journal = & $module { param($text) Read-SqJournal -Text $text } $json
        $journal.Valid | Should -BeTrue
        @($journal.Sessions).Count | Should -Be 2
        $journal.Sessions[0].SessionId | Should -Be 's1'
        $journal.Sessions[0].Records | Should -Be 7
        $journal.Sessions[0].Roles | Should -Be 2
        $journal.Sessions[0].Requests | Should -Be 2
        $journal.Sessions[0].NanoAiu | Should -Be 5000000000
        @($journal.RequestHashes) | Should -Be @('h1', '2') -Because 'a null, empty, boolean, or object identity is no identity and must never look like an overlap'
        $journal.Sessions[1].Roles | Should -Be 0
    }

    It 'separates documented stops (exit 1) from unexpected failures (exit 2)' {
        Get-SquadGovernanceExitCode -Exception (New-SquadGovernanceStop 'No squad state found.') | Should -Be 1
        Get-SquadGovernanceExitCode -Exception ([IO.IOException]::new('disk is full')) | Should -Be 1
        Get-SquadGovernanceExitCode -Exception ([UnauthorizedAccessException]::new('access denied')) | Should -Be 1
        Get-SquadGovernanceExitCode -Exception ([InvalidOperationException]::new('an internal defect')) | Should -Be 2
        Get-SquadGovernanceExitCode -Exception ([NullReferenceException]::new('an internal defect')) | Should -Be 2
        $caught = $null
        try { $null = Get-GovReport -Project (New-GovProject) } catch { $caught = $_.Exception }
        $caught | Should -Not -BeNullOrEmpty
        $caught.Message | Should -Match 'No squad state found'
        Get-SquadGovernanceExitCode -Exception $caught | Should -Be 1
    }

    It 'classifies a .NET failure that PowerShell wrapped by the exception it carries' {
        $wrapped = $null
        try { [IO.File]::ReadAllText((Join-Path $TestDrive 'missing-directory/none.txt')) } catch { $wrapped = $_.Exception }
        $wrapped | Should -BeOfType [System.Management.Automation.MethodInvocationException]
        $wrapped.InnerException | Should -BeOfType [IO.IOException]
        Get-SquadGovernanceExitCode -Exception $wrapped | Should -Be 1
        $defect = $null
        try { [void][int]::Parse($null) } catch { $defect = $_.Exception }
        $defect | Should -BeOfType [System.Management.Automation.MethodInvocationException]
        Get-SquadGovernanceExitCode -Exception $defect | Should -Be 2
    }
}
