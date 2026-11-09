---
name: squad-governance-report
description: "Reads squad state and generates a self-contained HTML governance dashboard (gates, verdicts, cost, dispatches, compliance, timeline, outcomes). Use when the user asks for a squad governance report, dashboard, or audit view."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Governance Report

## Inputs

* **outputPath** (optional): Local filesystem path for the HTML file. Defaults to `docs/squad-governance-report-<YYYY-MM-DD>.html`.
* **squad** (optional): In a federation, scope to a specific sub-squad. When omitted in a federation, the agent aggregates across all sub-squads.
* **period** (optional, defaults to `all`): Time window to include — `all`, `30d`, or `7d`.

## Flow

1. Hand this turn to the Squad Governance Report agent and let its required steps resolve the squad scope, extract the governance data, compute the aggregate metrics, and render the dashboard.
2. Pass **outputPath**, **squad**, and **period** through as-is. The agent owns the default output path, federation scoping, and period filtering.
3. Let the agent own its guardrails: squad state is read-only, every metric is grounded in parsed artifact content, empty sections render their empty state rather than being omitted, and the HTML stays fully self-contained.

## Invocation

Dispatch this request to the `Squad Governance Report` agent. This skill does not extract or render the dashboard itself — it only resolves which parameters to pass.