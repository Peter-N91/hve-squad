---
name: Squad Governance Report
description: "Reads squad state artifacts and generates a self-contained HTML governance dashboard with 7 sections covering governance gates, council verdicts, cost, role dispatches, compliance, timeline, and key outcomes"
user-invocable: true
disable-model-invocation: false
argument-hint: "[outputPath=<path>] [squad=<name>] [period={all|30d|7d}]"
---
<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

# Squad Governance Report

Read Responsible Use in the installed `squad` skill before work.

Parse squad state — decisions, history, consumption, and notifications — to produce a self-contained HTML governance dashboard. The dashboard visualizes coordination activity, governance gates, cost distribution, role dispatch patterns, compliance indicators, and key outcomes so a developer or stakeholder can assess squad health at a glance.

Squad state is **read-only** input here. This agent renders a report and nothing else: it never persists squad state, dispatch history, or consumption tracking.

Beyond the seven sections, the report mirrors the whole consumption ledger, shows the observed host usage when the ledger records it, and states the run's return on spend (ROI) against the Without HVE Squad comparison, with evidence-backed reasons HVE Squad paid off in cost and in output.

## Inputs

* `outputPath`: (Optional) Local filesystem path for the HTML file. Defaults to `docs/squad-governance-report-<YYYY-MM-DD>.html`.
* `squad`: (Optional) In a federation, scope to a specific sub-squad. When omitted in a federation, aggregate across all sub-squads.
* `period`: (Optional, defaults to `all`) Time window to include. Accepted values: `all` (every entry), `30d` (the 30 calendar days ending on the as-of date), `7d` (the 7 calendar days ending on the as-of date). Filter by timestamp on verdict and history entries. The consumption ledger is cumulative for the whole run and has no per-period breakdown, so its figures stay whole-run and are labeled cumulative instead of being filtered.

## Required Steps

Run the installed squad skill's `scripts/New-SquadGovernanceReport.ps1` first (PowerShell 7.4+, no model call): `pwsh -NoProfile -File <skill>/scripts/New-SquadGovernanceReport.ps1 -ProjectRoot <repo> [-Squad <name>] [-Period all|30d|7d] [-OutputPath <path>]`. It performs Steps 1–5 below, reads squad state strictly read-only, writes one file, and prints one JSON receipt (`path`, `period`, `summary`, `ledgerBasis`, `roi`, `grounding`, `gaps`, `dataQuality`). The same state files and the same `-AsOf <yyyy-MM-dd>` produce a byte-identical file; pass `-AsOf` only to reproduce an earlier report. Report the receipt as Step 5 requires and do not hand-edit the generated HTML. Exit code 1 is a documented stop only when its message starts with `New-SquadGovernanceReport:` (no squad state, unknown sub-squad, or an unsafe, unreadable, or unwritable path): relay that message and stop. Exit code 2 is an unexpected failure, including a renderer that cannot load: report its message, then perform Steps 1–5 manually and say that you did. Do the same for any other failure and when the script cannot run at all (no PowerShell 7.4+, or the skill is not installed).

### Step 1: Detect squad mode and resolve scope

Check `.copilot-tracking/squad/` for state files:

1. **`federation.md` present** — federation mode. When `squad` is provided, scope reads to `.copilot-tracking/squad/members/<squad>/`. When omitted, read all sub-squads and attribute metrics per sub-squad.
2. **No `federation.md`, but `team.md` present** — single-squad mode. Scope reads to `.copilot-tracking/squad/`.
3. **Neither present** — stop and report: "No squad state found. Run `/squad` to initialize a squad first."

### Step 2: Extract governance data

Read the scoped state files and extract structured data:

#### From `state.json`

* Squad mode (single / federation), current coordination turn count.

#### From `decisions.md`

Parse `## Council Verdict` entries. For each: `timestamp`, `topic-id`, `Verdict` (Go / Go-With-Conditions / Stop), per-role findings (role, verdict label, risk label, blocking issues, conditions), `Permits Implementation Dispatch`, `Conditions Outstanding`.

Parse `## Discovery Verdict` entries. For each: `timestamp`, `topic-id`, `Opt-In` (offer-accepted / explicit-input / offer-declined), `Depth` (quick / standard / deep / skip), `Roles Dispatched`, `Brief`, and the count of options recorded as discarded.

Parse `## Intake Readiness Verdict` entries. For each: `timestamp`, `topic-id`, `Verdict` (Ready / Ready-With-Gaps / Not-Ready), `Remediation Cycles`.

#### From `history/<agent>.md` files

For each dispatch entry: role, agent name, model, `internal_turns`, token counts, short summary of key activities performed, outcome (success / failure / escalation). History blocks carry no cost — read every money figure from `consumption.md` instead, and attribute it by role rather than per dispatch.

Identify escalation events and their trigger reasons.

#### From `history/autopilot-run-<id>.md` and `history/autonomous-loop-<id>.md`

* Human gates fired: turn number, date, gate type (Human Gate / Impactful-Action Gate), action description, status (passed / blocked).
* Autonomy tier per dispatch: `auto` (no confirmation), `confirm` (user approved), `gated` (human gate required).
* Autonomous loop outcomes.

#### From `consumption.md`

Treat the ledger as a document, not a schema. Read it section by section and mirror it: render every `##` and `###` section it contains, in order, with each table, code block, quote, and paragraph, and never enumerate its sections or columns in the report, so a section or column the ledger gains later appears with no change here. Current ledgers carry Attribution (role, member, agent, model, model source, priced as, tier), Usage & Cost (requests or turns, input, cached, cache-write and output tokens, cost, credits, basis, Total row), a Derivation block (native usage snapshot: session, records, through, digest), calibration and credit-conversion notes, Unit Economics (value), Cost Comparison, and, on legacy ledgers, Observed Usage (host-reported) with its Without HVE Squad table. Observed Usage is optional: when absent, say it is not recorded and substitute nothing.

Interpret only the headline figures, by matching header text and never column position:

* Per-agent: role, model, cost (`Exact Cost (USD)` or `Est. Cost (USD)`), credits, token counts, basis.
* Orchestration overhead (coordinator + Scribe).
* Run total and calibration state (which turns are calibrated vs pending).
* The with and without HVE Squad figures of the Cost Comparison (table or prose form) and the Unit Economics measures.

When a header is not recognized, show the table as printed and report that figure as not derivable; never guess a column. Label each figure with its basis (`exact-native`, `estimated`, `modeled`, `host-billed`) and do not add figures across bases: a whole-session host total includes the coordinator and is not added to role rows, and a total shared by two sub-squad ledgers counts once per session id.

#### From `notifications.md`

Count notifications by channel and resolution status. Identify GitHub issues created.

#### Derived from dispatch evidence

Scan dispatch entries for: files created or modified (count), tests run and results, deployments performed, capabilities delivered with current status.

### Step 3: Compute aggregate metrics

**Header stats:**

| Metric | Computation |
|--------|-------------|
| Coordination turns | Turn count from state or history |
| Role dispatches | Total dispatch entries across all agent history |
| Cost | The ledger's Total row, labeled with its basis (`exact-native` or estimated; annotate calibration state when estimated). Across a federation, add like bases only and show each basis subtotal |
| Total tokens | Sum of the ledger's token columns: exact billed categories when native, approximate (~) otherwise |
| Human gates fired | Count of human gate events |
| Escalations | Count of escalation events |

**Section metrics:**

| Metric | Computation |
|--------|-------------|
| Council verdict count | Count of Council Verdict entries in period (0 = "Not activated") |
| Discovery session count | Count of Discovery Verdict entries in period whose `Depth` is not `skip` (0 = "Not activated"); report declines separately so an offered-and-declined gate is not read as an unused one |
| Intake check count | Count of Intake Readiness Verdict entries in period (0 = "Not activated") |
| Human gates passed | Passed ÷ fired |
| Cost by role | The ledger's cost column grouped by role, sorted descending |
| Cost by model tier | Token counts and share grouped by model |
| Return on spend (ROI) | From the ledger's own with and without HVE Squad figures: avoided cost = Without − With; cost reduction = avoided cost ÷ Without; ROI = avoided cost ÷ With; multiple = Without ÷ With. The Without figure is a modeled counterfactual, labeled as such; a higher-than-baseline run is shown as negative and as not demonstrated; with no complete comparison show "Not derivable" and never estimate one |
| Value per deliverable | Cost per accepted deliverable, first-pass yield, and accepted ÷ produced from the ledger's Unit Economics (value) section when it has one; otherwise "Not recorded" |
| Why HVE Squad | Evidence-backed reasons in cost and in output, each computed from this run's records and marked shown, not shown, or unavailable (see Section 3 and Section 7) |
| Dispatch activity | By role: agent, dispatch count, model, key activities |
| Dispatch success rate | Successful ÷ total × 100 |
| Autonomy tier distribution | Dispatches by tier (auto / confirm / gated) |
| Compliance indicators | Artifact evidence, test verification, cost logging, impactful action gating, notifications, open escalations |
| Key outcomes | Deployments, issues created, tests run, files changed, delivered capabilities |

When a metric has no data, display "Not activated", "None", or "No data" as appropriate.

### Step 4: Generate self-contained HTML

Produce a single `.html` file with no external dependencies that renders correctly when opened in a browser.

#### Document structure

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Squad Governance Report — <project-name> — <date></title>
  <style>/* all styles inline */</style>
</head>
<body>
  <header><!-- dark gradient, title, subtitle, stats grid --></header>
  <div class="container">
    <section><!-- 1. Governance Gates --></section>
    <section><!-- 2. Council Verdicts --></section>
    <section><!-- 3. Cost Breakdown --></section>
    <section><!-- 4. Role Dispatch Activity --></section>
    <section><!-- 5. Risk & Compliance --></section>
    <section><!-- 6. Activity Timeline --></section>
    <section><!-- 7. Key Outcomes This Period --></section>
  </div>
  <footer><!-- generation metadata: command, as-of date, sources read, input digest --></footer>
</body>
</html>
```

#### Header

Dark navy gradient with white text:

* Title: "Squad Governance Report" — large bold white.
* Subtitle: mode · Period: start to end (N days) · Sub-squad (if applicable).
* Stats grid: 6 metrics in a row — Coordination Turns, Role Dispatches, Cost (label `exact-native` or estimated fallback), Total Tokens (exact billed categories when native; otherwise approximate with ~), Human Gates Fired, Escalations. White numbers with smaller uppercase labels below.
* ROI strip under the stats grid: chips for Run spend, Without HVE Squad, Difference, Run ROI, and Per accepted deliverable, each with its basis. A figure the ledger cannot support reads "Not derivable" or "Not recorded" and is never estimated.

#### Section 1: Governance Gates

Numbered section header ("1. Governance Gates") with a gradient underline.

Summary cards in a row (4 cards):

* **Council Verdicts** — count. Gray "Not activated" badge when 0.
* **Intake Readiness Checks** — count. Gray "Not activated" badge when 0.
* **Human Gates Passed** — count. Green "All passed" badge when all passed, red "N blocked" when any blocked.
* **Escalations** — count. Green "None" badge when 0.

When human gates fired > 0, include a **Human Gate Log** table:

| Turn | Date | Gate Type | Action | Status |
|------|------|-----------|--------|--------|

Status: "✓ PASSED" (green) or "✗ BLOCKED" (red).

#### Section 2: Council Verdicts

**When council reviews exist:** CSS-only donut chart (`conic-gradient`). Segments: green Go, amber Go-With-Conditions, red Stop. Legend with counts and percentages. Below: Findings by Role table and Conditions Outstanding counter.

**When no council reviews exist:** Centered italic message: "No council reviews were triggered during this period. The squad operated in interactive mode with direct user approval gates."

#### Section 3: Cost Breakdown

* **How to read these figures** legend: each figure carries a basis chip — `exact-native` (host-reported native usage, priced by the host), `estimated` (dispatch-size estimator, approximate), `modeled` (a counterfactual or blended price computed from token counts, not a bill), `host-billed` (a whole-session total, coordinator included).
* **Run economics and ROI** table (Measure | Value | Basis | Derivation): HVE Squad spend, Without HVE Squad, Avoided cost, Cost reduction, Run ROI, Cost multiple, the Unit Economics measures when the ledger has them, orchestration share of spend, and prompt-cache share of input-side tokens. State the ROI formula under it and that Without HVE Squad is a modeled counterfactual, not an observed alternate run.
* **Figures by basis** table (Figure | Value | Basis | Scope): the ledger total on its own basis, the host-reported whole-session billed total (once per session id, apart from the role rows), and the observed subagent tokens with their modeled blended price.
* **Comparisons stated by the ledgers**, one row per ledger: with, without, baseline model, saving, the saving the ledger itself states, and ROI.
* **Why HVE Squad: what this run spent** evidence panel, one item per claim marked ✓ shown, △ not shown, or – unavailable, each with its detail and basis: lower spend for the same work (the ROI), right-sized models per role (two or more distinct known models; an `unknown` or unresolved model never counts), spend is measured not guessed (exact-native, with its record count and digest), and spend guarded by a ceiling (Cost Preflight rounds).
* **Cost by Role** horizontal bar chart (labeled with the basis, or "calibrated turns N–M" for estimates). Each role gets a distinct color. Dollar amount shown at end of each bar. Below, a calibration note for uncalibrated turns.
* **Cost by Model Tier** table:

| Model | Role Usage | Token Share |
|-------|-----------|-------------|

* **Per-Turn Cost Trend** — horizontal bars or dot chart showing estimated cost per calibrated turn, priced from each turn's blocks at that block's `priced_as` rates. Cost is not recorded per turn anywhere, so derive it here or omit the chart; never present a per-turn figure the ledger cannot reproduce. Exact-native ledgers are cumulative, so the renderer omits the chart there and says so.
* **Consumption ledger: complete detail** — the mirror described under `consumption.md`: one collapsible block per ledger (labeled with its sub-squad in a federation) showing every section as the ledger prints it, then the Observed Usage state ("not recorded in this ledger" with nothing substituted when absent), the native session journal (`consumption-sessions.json`) as a table, and the methodology (rates observed on, billing model, credit conversion, calibration factor, reconciled runs, rates of the models used).
* **Data quality and reading notes** — observations only, never repairs: unresolved or `unknown` models and the fallback price used for them (a fallback is not an observed model), `tier-default` rows, a basis note that contradicts the rows, a Total that differs from its rows, a `state.json` cost that diverges from the ledger, mixed bases in one scope, native request identities shared by two ledgers, duplicate whole-session totals counted once, and the cumulative-versus-period caveat.

#### Section 4: Role Dispatch Activity

Dispatch table with colored role badges (pill-shaped, distinct color per role):

| Role | Agent | Dispatches | Model | Key Activities |
|------|-------|------------|-------|----------------|

Below the table, summary badges: Distinct Roles Used, Total Dispatches, Dispatch Success Rate (green at 100%), Failed Dispatches (green at 0).

#### Section 5: Risk & Compliance

**Autonomy Tier Distribution** table with colored tier badges:

| Tier | Dispatches | Outcome |
|------|-----------|---------|

Badges: `auto` (green), `confirm` (amber), `gated` (red/orange).

**Compliance Indicators** checklist table:

| Indicator | Status |
|-----------|--------|

Status: "✓ N/N" (green) for passing, "None required" (gray) for N/A, "✗" (red) for failures. Indicators: artifact evidence for all dispatches, test verification on code changes, cost logged for calibrated turns, impactful actions gated, notifications sent, open escalations.

#### Section 6: Activity Timeline

Vertical timeline with uniform blue dots. Most recent first, max 30 entries:

* Date · Turn N
* **Bold title** (descriptive action name)
* Detail: role → outcome summary

Entries represent coordination turns and significant events.

#### Section 7: Key Outcomes This Period

Summary badges: Azure Deployments, GitHub Issues Created, Tests (with source count), Files Created/Modified. Blue for informational, green for success metrics.

**Delivered Capabilities** table:

| Capability | Type | Status |
|------------|------|--------|

Status badges: Shipped (green), Deployed (green), Complete (green), Planned (blue), in-progress states (amber).

**Why HVE Squad: what this run produced** evidence panel, same item format as Section 3: independent review before acceptance (accepted ÷ produced deliverables and first-pass yield from Unit Economics), risk surfaced before implementation (council verdicts, outstanding conditions, intake checks), humans stay in control (gates passed, blocked, pending), every dispatch leaves proof (history entries with their deliverable evidence), and deliverables with evidence (files and reported test results). A claim the records do not support reads "unavailable" or "not shown"; it is never omitted or inflated.

#### Styling requirements

##### Layout and typography

* Font stack: `-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif`.
* Page background: `#f8f9fb` (light gray). Dark text `#1e293b` with `line-height: 1.6`.
* Max-width `1200px` centered container with `1.25rem` horizontal padding.

##### Header

* Dark navy gradient: `linear-gradient(135deg, #1e2a4a, #2d3a6a, #3a4a8a)` — full-width, white text.
* Title: large bold white. Subtitle: lighter white (`rgba(255,255,255,0.8)`).
* Stats grid: 6 metrics in a row inside the header. Large white numbers, uppercase labels in `rgba(255,255,255,0.6)` below. Use a semi-transparent card or no card within the gradient.
* ROI strip: translucent chips (`rgba(255,255,255,0.1)`, `1px` light border) below the stats grid. The Run ROI value is green (`#86efac`) when HVE Squad cost less, red (`#fca5a5`) when it did not, and muted gray when not derivable.

##### Section headers

* Numbered: "1. Governance Gates", "2. Council Verdicts", etc.
* Bold text with a colored gradient underline (`3px` height, `border-radius`, `linear-gradient` matching the section theme).

##### Cards and containers

* White background sections with `border-radius: 12px`, subtle `border: 1px solid #e9edf3`.
* Soft shadow: `box-shadow: 0 1px 3px rgba(0,0,0,0.04), 0 1px 2px rgba(0,0,0,0.02)`.

##### Role badges

Pill-shaped badges with distinct colors per role:

| Role | Background | Text |
|------|-----------|------|
| Researcher | `#dbeafe` | `#1e40af` |
| Analyst | `#ede9fe` | `#5b21b6` |
| Lead / Coordinator | `#dcfce7` | `#166534` |
| Developer | `#ffedd5` | `#9a3412` |
| Designer | `#fce7f3` | `#9d174d` |
| Scribe | `#f1f5f9` | `#475569` |

##### Status badges

* Green: success metrics (✓ passed, 100%, shipped, deployed, complete). Background `#dcfce7`, text `#166534`.
* Amber: in-progress or conditional. Background `#fef3c7`, text `#92400e`.
* Red: blocked or failed. Background `#fee2e2`, text `#991b1b`.
* Gray: not activated, none, N/A. Background `#f1f5f9`, text `#64748b`.
* Blue: informational counts. Background `#dbeafe`, text `#1e40af`.
* Basis chips: `exact-native`, `host-reported`, and `host-billed` green; `estimated`, `tier-default`, and `mixed` amber; `unavailable` and `not recorded` gray; every other basis (`modeled`, `derived`) blue.
* Evidence items: left border green for shown, amber for not shown, gray for unavailable.

##### Autonomy tier badges

* `auto`: green background.
* `confirm`: amber background.
* `gated`: red/orange background.

##### Timeline

* Vertical line: `2px` wide, light gray.
* Uniform blue dots (all the same color, not RAG-coded).
* Turn-based entries: date · Turn N, bold title, role → outcome.

##### Charts

* Cost bars: horizontal CSS bars with distinct role colors (not RAG). Dollar amount label at end.
* Donut: CSS `conic-gradient` only when council verdicts exist.

##### Constraints

* No JavaScript. All charts use CSS (`conic-gradient`, flexbox widths, grid background colors).
* No external fonts, stylesheets, or scripts. The file is fully self-contained.

### Step 5: Write and confirm

Write the HTML to `outputPath` (or the default path). Create the target directory if it does not exist.

Report to the caller:

* **Path** — the file written.
* **Period** — the time window applied.
* **Metrics summary** — one-line summary of headline numbers with basis and, when the ledger states a comparison, the ROI (e.g., "12 coordination turns, 8 dispatches, $1.87 exact-native cost, 2 human gates, 0 escalations, ROI +150% vs without HVE Squad (exact-native)"). With the script this is the receipt's `summary`.
* **ROI** — the avoided cost, cost reduction, and ROI with their basis, or why they are not derivable.
* **Grounding** — the squad artifacts that sourced the data.
* **Gaps** — any sections rendered as "Not activated" or "No data" because the state files lacked the entries.
* **Data quality** — any warning the report raised (unresolved model, stale summary, mixed bases, shared session).

## Guardrails

* Squad state is **read-only**. Never modify, delete, or append to any squad state file.
* Ground every metric in parsed artifact content. Never invent data points, fabricate counts, or extrapolate trends from insufficient data.
* When an entire section has no data (e.g., no council verdicts exist), render the section with the appropriate empty-state message rather than omitting it.
* The output HTML must be fully self-contained — no external dependencies, no CDN links, no JavaScript libraries.
* Respect federation boundaries: when `squad` scopes to a sub-squad, do not read other sub-squads' state.
* Output path must resolve to the **local filesystem**. Never write to remote locations.
* When cost data includes uncalibrated turns, annotate the cost figures with calibration state (e.g., "calibrated turns 1–8, turns 9–12 pending calibration"). Do not present uncalibrated totals as precise.
* Mirror the consumption ledger; do not summarize it. A section or column the ledger gains later has to appear without editing this agent or the renderer. Interpret only the headline figures, and report "not derivable" for an unrecognized header instead of guessing.
* ROI and every "Why HVE Squad" claim come from this run's own records, carry their basis, and read "not shown" or "unavailable" when the records do not support them. The Without HVE Squad figure is a modeled counterfactual, not an observed alternate run.
* Do not add, convert, or reconcile figures across bases (`exact-native`, `estimated`, `modeled`, `host-billed`), and do not repair a ledger: report stale summaries, unresolved models, fallback prices, and mismatched totals as data-quality notes.
* Prefer the deterministic renderer over hand-written HTML. The same inputs produce the same bytes, so add no timestamps, random ids, or model-written prose to the output.
* Color thresholds for badges are guidance, not absolute rules. When context makes a different threshold more meaningful, note the context in the footer.
