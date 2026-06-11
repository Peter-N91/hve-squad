---
description: "Opt-in auto-validated autonomy tier with re-validation cap, divergence detection, and mandatory escalation triggers"
applyTo: '**/.copilot-tracking/squad/**'
---

# Squad Autonomous Conventions

These conventions define the `auto-validated` autonomy tier and the bounded re-validation loop the Squad Coordinator runs when a turn opts in to autonomous mode. The tier is intentionally narrow: it lets a council validate a developer's output without a human turn in between, but it always preserves the most-restrictive synthesis from `.github/instructions/squad/squad-council.instructions.md` and always escalates on the mandatory triggers listed below.

The `auto-validated` tier is opt-in per turn through the `/squad` prompt's `mode=autonomous` input. The consumer's default tier (whatever they chose during Init Mode or set in `routing.md`) is unchanged when `mode=autonomous` is absent.

## Tier Definition

The tier extends the existing autonomy tiers defined in `.github/instructions/squad/squad-routing.instructions.md`:

* `auto-validated` runs the implementation role and the council in a bounded loop on the same turn so that an autonomous build can produce both a draft change and a verdict without an intervening user prompt.
* The tier never downgrades a role's normal autonomy. A role that is normally `confirm` (such as `developer`) stays at `confirm` for any action it cannot self-validate, and any council finding that flips to `Stop` or `Risk: High` lifts the turn straight to escalation.
* The tier never overrides the cost-impacting rule: any move the cost-manager labels `confirm` stays at `confirm` even when `mode=autonomous` is set. The autonomous loop is a validator loop, not a permission upgrade.

## Opt-In Surface

The single opt-in is the `/squad` prompt input `mode=autonomous`. When the input is present:

* The coordinator engages the loop contract below for the matched implementation pattern.
* The coordinator records the opt-in through the Scribe so the autonomous-loop history file (see the History Entries section) carries the per-turn opt-in evidence.

When the input is absent, the coordinator runs the normal per-turn protocol from `.github/agents/squad/squad-coordinator.agent.md` and does not enter the loop.

## Loop Contract

The autonomous loop is a fixed sequence the coordinator runs on a single turn:

1. Council dispatch. The coordinator dispatches the default council (`architect`, `security`, `cost-manager`, `product-owner`, optionally `rai`) in parallel against the proposal under review and waits for findings, per `.github/instructions/squad/squad-council.instructions.md`.
2. Verdict synthesis. The coordinator hands the findings to the Scribe and the Scribe writes the Council Verdict to `decisions.md`. When the verdict is `Stop`, the loop ends and the coordinator escalates immediately; the loop never runs an implementer against a `Stop` verdict.
3. Implementer dispatch. On `Go` or `Go-With-Conditions`, the coordinator dispatches the implementation role (typically `developer`) with the consolidated conditions attached as inputs.
4. Council re-validation. The coordinator dispatches the same council in parallel against the implementer's output for one re-validation cycle.
5. Decision. On a `Go` re-validation, the loop converges; the coordinator hands the final history entry to the Scribe and reports back to the user. On `Go-With-Conditions` whose conditions are all satisfied in the implementer's output, the loop converges. On any other outcome, the coordinator either runs cycle 2 of re-validation or escalates per the cap below.

The implementation role does not modify production resources, push to remote branches, or run irreversible commands inside the loop; those actions remain at `confirm` tier and require the user even when `mode=autonomous` is in effect.

## Re-validation Cap

The loop caps re-validation at two cycles. After cycle 2, the coordinator escalates to the user regardless of outcome:

* Cycle 1 (mandatory): council re-validates the first implementer output.
* Cycle 2 (conditional): council re-validates a second implementer output, used only when cycle 1 returned `Go-With-Conditions` with outstanding conditions or a non-`Stop` verdict whose conditions the implementer addressed in a follow-up draft.
* No cycle 3. Whatever the cycle-2 verdict is (`Go`, `Go-With-Conditions`, or `Stop`), the coordinator stops the loop, hands the final history entry to the Scribe, and surfaces the result to the user.

The cap is hard. Iteration limits guard against the thrashing failure mode documented in the autonomous-validation research (see `.copilot-tracking/research/subagents/2026-06-11/autonomous-validation-patterns-research.md`).

## Divergence Detection

When two consecutive cycles produce different verdicts on the same issue, the coordinator escalates immediately and does not start the next cycle, even when the cap has not been reached:

* Example A: cycle 1 returns `Go-With-Conditions` (security flagged secret rotation), cycle 2 returns `Stop` on the same secret-rotation issue. Escalate after cycle 2.
* Example B: cycle 1 returns `Stop` on a cost ceiling, cycle 2 returns `Go-With-Conditions` after a SKU swap but security flips from `Go` to `Concern: Risk: Medium`. Escalate; divergence on either role triggers the rule.

Divergence detection prevents the loop from oscillating on a contested finding and forces a human read of the conflict.

## Mandatory Escalation Triggers

The following triggers always escalate to the user and cannot be auto-resolved by additional cycles. They apply at every step of the loop, not only at the cap:

* Any `Stop` verdict from the council or from any individual council role.
* Any `Risk: High` finding from `security`, `cost-manager`, or `rai`.
* Any cost-impacting move that the `cost-manager` flags at `confirm` tier (the autonomous tier does not downgrade `confirm` to `auto` for budget-impacting recommendations).
* Any compliance violation flagged by `rai` or by `security` (for example, regulated-data handling, PII leakage, GDPR/HIPAA scope).
* Any irreversible write the implementer would need to perform to satisfy the proposal: production deploys, schema migrations, data deletions, force-push to a protected branch, destructive `terraform apply -auto-approve`, or any side effect the user has marked irreversible in the project.

A trigger fires per-occurrence: a single qualifying finding is enough to escalate, regardless of how many other findings are clean.

## Cost Ceiling

The autonomous loop honors an indicative per-turn spend cap. The cap is a placeholder the consumer sets in their `routing.md` or in the `/squad` prompt invocation (`cost-ceiling=$X`):

* When the dispatched roles' projected token spend (or the cost-manager's indicative estimate of the change's runtime cost) exceeds the cap, the coordinator escalates instead of running the next cycle.
* The default cap is unset; consumers opt in by naming a value. An unset cap means the loop runs to its cycle-2 boundary or to a mandatory escalation, whichever fires first.
* The cap is advisory at the model-spend level (no runtime metering ships with the package); it is enforceable at the change-cost level through the `cost-manager` charter (`.github/agents/squad/squad-cost-manager.agent.md`).

## History Entries

Every loop iteration produces history entries that the Squad Scribe writes (the single-writer rule from `.github/instructions/squad/squad-state.instructions.md` still holds):

1. Per-agent history. Each dispatched role (council members and the implementer) adds one entry per cycle to its existing `.copilot-tracking/squad/history/<agent>.md` file. The entry names the cycle index (1 or 2), the verdict the role returned, and a one-line outcome summary.
2. Auto-loop summary. The coordinator hands the Scribe one auto-loop summary payload per turn. The Scribe writes it to `.copilot-tracking/squad/history/autonomous-loop-<id>.md`, where `<id>` is the topic-id slug from the Council Verdict. The summary file uses this shape:

```markdown
---
description: "Autonomous-loop summary for topic <id>"
---

# Autonomous Loop: <id>

* Topic: <one-line summary>
* Opt-In: mode=autonomous
* Cost Ceiling: <value or unset>
* Outcome: converged (Go) | converged (Go-With-Conditions) | escalated (<reason>)

## Iterations

| Cycle | Verdict              | Blocking Issues          | Conditions               | Notes                          |
|-------|----------------------|--------------------------|--------------------------|--------------------------------|
| 1     | Go / Go-With-Conditions / Stop | <list-or-none> | <list-or-none>           | <one-line cycle summary>       |
| 2     | (when run)           | <list-or-none>           | <list-or-none>           | <one-line cycle summary>       |

## Final Verdict Reference

* Council Verdict: see `decisions.md` under `## Council Verdict <timestamp> <id>`
```

The auto-loop file is append-only by topic-id; one file per topic. Subsequent runs against the same topic append a new `## Iterations` section dated by turn rather than overwriting prior runs.
