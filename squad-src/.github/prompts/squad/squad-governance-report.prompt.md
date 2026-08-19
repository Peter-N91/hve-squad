---
description: "Reads squad state artifacts and generates a self-contained HTML governance dashboard with 7 sections covering governance gates, council verdicts, cost, role dispatches, compliance, timeline, and key outcomes"
agent: Squad Governance Report
argument-hint: "[outputPath=<path>] [squad=<name>] [period={all|30d|7d}]"
---

# Squad Governance Report

## Inputs

* ${input:outputPath}: (Optional) Local filesystem path for the HTML file. Defaults to `docs/squad-governance-report-<YYYY-MM-DD>.html`.
* ${input:squad}: (Optional) In a federation, scope to a specific sub-squad. When omitted in a federation, the agent aggregates across all sub-squads.
* ${input:period:all}: (Optional, defaults to `all`) Time window to include: `all`, `30d`, or `7d`.

## Requirements

1. Hand this turn to the Squad Governance Report agent and let its required steps resolve the squad scope, extract the governance data, compute the aggregate metrics, and render the dashboard.
2. Pass `${input:outputPath}`, `${input:squad}`, and `${input:period}` through as-is. The agent owns the default output path, federation scoping, and period filtering.
3. Let the agent own its guardrails: squad state is read-only, every metric is grounded in parsed artifact content, empty sections render their empty state rather than being omitted, and the HTML stays fully self-contained.
