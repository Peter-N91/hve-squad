---
name: Squad Governance Report
description: "Reads squad state artifacts and generates a self-contained HTML governance dashboard with 7 sections covering governance gates, council verdicts, cost, role dispatches, compliance, timeline, and key outcomes"
user-invocable: true
disable-model-invocation: false
argument-hint: "[outputPath=<path>] [squad=<name>] [period={all|30d|7d}]"
---

# Squad Governance Report

Parse squad state — decisions, history, consumption, and notifications — to produce a self-contained HTML governance dashboard. The dashboard visualizes coordination activity, governance gates, cost distribution, role dispatch patterns, compliance indicators, and key outcomes so a developer or stakeholder can assess squad health at a glance.

Squad state is **read-only** input here. This agent renders a report and nothing else: it never persists squad state, dispatch history, or consumption tracking.

## Inputs

* `outputPath`: (Optional) Local filesystem path for the HTML file. Defaults to `docs/squad-governance-report-<YYYY-MM-DD>.html`.
* `squad`: (Optional) In a federation, scope to a specific sub-squad. When omitted in a federation, aggregate across all sub-squads.
* `period`: (Optional, defaults to `all`) Time window to include. Accepted values: `all` (every entry), `30d` (last 30 days), `7d` (last 7 days). Filter by timestamp on verdict and history entries.

## Required Steps

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

* Per-agent: role, model, `est_cost_usd`, `est_credits`, token counts.
* Orchestration overhead (coordinator + Scribe).
* Run total and calibration state (which turns are calibrated vs pending).

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
| Estimated cost | Sum of est_cost_usd (annotate calibration state) |
| Total tokens | Sum of token counts from consumption.md |
| Human gates fired | Count of human gate events |
| Escalations | Count of escalation events |

**Section metrics:**

| Metric | Computation |
|--------|-------------|
| Council verdict count | Count of Council Verdict entries in period (0 = "Not activated") |
| Discovery session count | Count of Discovery Verdict entries in period whose `Depth` is not `skip` (0 = "Not activated"); report declines separately so an offered-and-declined gate is not read as an unused one |
| Intake check count | Count of Intake Readiness Verdict entries in period (0 = "Not activated") |
| Human gates passed | Passed ÷ fired |
| Cost by role | est_cost_usd grouped by role, sorted descending |
| Cost by model tier | Token counts and share grouped by model |
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
  <footer><!-- generation metadata --></footer>
</body>
</html>
```

#### Header

Dark navy gradient with white text:

* Title: "Squad Governance Report" — large bold white.
* Subtitle: mode · Period: start to end (N days) · Sub-squad (if applicable).
* Stats grid: 6 metrics in a row — Coordination Turns, Role Dispatches, Est. Cost (note calibration state), Total Tokens (approximate with ~), Human Gates Fired, Escalations. White numbers with smaller uppercase labels below.

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

* **Cost by Role** horizontal bar chart (labeled "calibrated turns N–M"). Each role gets a distinct color. Dollar amount shown at end of each bar. Below, a calibration note for uncalibrated turns.
* **Cost by Model Tier** table:

| Model | Role Usage | Token Share |
|-------|-----------|-------------|

* **Per-Turn Cost Trend** — horizontal bars or dot chart showing estimated cost per calibrated turn, priced from each turn's blocks at that block's `priced_as` rates. Cost is not recorded per turn anywhere, so derive it here or omit the chart; never present a per-turn figure the ledger cannot reproduce.

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

#### Styling requirements

##### Layout and typography

* Font stack: `-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif`.
* Page background: `#f8f9fb` (light gray). Dark text `#1e293b` with `line-height: 1.6`.
* Max-width `1200px` centered container with `1.25rem` horizontal padding.

##### Header

* Dark navy gradient: `linear-gradient(135deg, #1e2a4a, #2d3a6a, #3a4a8a)` — full-width, white text.
* Title: large bold white. Subtitle: lighter white (`rgba(255,255,255,0.8)`).
* Stats grid: 6 metrics in a row inside the header. Large white numbers, uppercase labels in `rgba(255,255,255,0.6)` below. Use a semi-transparent card or no card within the gradient.

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
* **Metrics summary** — one-line summary of headline numbers (e.g., "12 coordination turns, 8 dispatches, $1.87 est. cost, 2 human gates, 0 escalations").
* **Grounding** — the squad artifacts that sourced the data.
* **Gaps** — any sections rendered as "Not activated" or "No data" because the state files lacked the entries.

## Guardrails

* Squad state is **read-only**. Never modify, delete, or append to any squad state file.
* Ground every metric in parsed artifact content. Never invent data points, fabricate counts, or extrapolate trends from insufficient data.
* When an entire section has no data (e.g., no council verdicts exist), render the section with the appropriate empty-state message rather than omitting it.
* The output HTML must be fully self-contained — no external dependencies, no CDN links, no JavaScript libraries.
* Respect federation boundaries: when `squad` scopes to a sub-squad, do not read other sub-squads' state.
* Output path must resolve to the **local filesystem**. Never write to remote locations.
* When cost data includes uncalibrated turns, annotate the cost figures with calibration state (e.g., "calibrated turns 1–8, turns 9–12 pending calibration"). Do not present uncalibrated totals as precise.
* Color thresholds for badges are guidance, not absolute rules. When context makes a different threshold more meaningful, note the context in the footer.
