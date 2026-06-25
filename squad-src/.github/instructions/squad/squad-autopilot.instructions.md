---
description: "Opt-in autopilot mode: a full research→plan→implement→review pipeline that runs end-to-end with human gates only on impactful actions and final-outcome validation"
applyTo: '**/.copilot-tracking/squad/**'
---

# Squad Autopilot Conventions

These conventions define `mode=autopilot`: a full delivery pipeline the Squad Coordinator runs end-to-end on the user's behalf. Autopilot sequences the squad's normal roles — research, then planning, then implementation, then review — without pausing for a human at every stage. It pauses **only** at the two places that matter: any impactful or irreversible action, and the final outcome.

Autopilot exists so the squad earns its keep. If a human had to approve every intermediate step, there would be no reason to run a squad over the individual HVE Core agents. Autopilot delegates the *flow* to the coordinator while keeping the *consequential decisions* with the human.

## Relationship to the Other Modes

The squad has three operating modes. They are selected per turn through the `/squad` prompt's `mode` input.

| Mode                     | Opt-in              | Who approves what                                                                                                  |
|--------------------------|---------------------|-------------------------------------------------------------------------------------------------------------------|
| Interactive (default)    | no `mode` flag      | The human approves **each stage** (research, plan, implement, review). A notification fires at every stage gate.    |
| `mode=autonomous`        | `mode=autonomous`   | A narrow validator loop: the council re-validates a single implementer output (max 2 cycles). See `.github/instructions/squad/squad-autonomous.instructions.md`. |
| `mode=autopilot`         | `mode=autopilot`    | The human approves **only** impactful actions and the **final outcome**. Everything in between runs autonomously.   |

Autopilot is the higher-level orchestration; `mode=autonomous` is one component it reuses at the implementation stage. Setting `mode=autopilot` does not require also setting `mode=autonomous`.

## Opt-In Surface

The single opt-in is the `/squad` prompt input `mode=autopilot`. When the input is present:

* The coordinator runs the Pipeline Contract below across the matched work instead of the normal single-pattern, single-turn classification.
* The coordinator records the opt-in through the Squad Scribe so the autopilot-run history file (see History Entries) carries the per-run opt-in evidence.

When the input is absent, the coordinator runs the normal interactive per-turn protocol from `.github/agents/squad/squad-coordinator.agent.md`, where each routed stage is gated by its routing autonomy tier.

## Pipeline Contract

Autopilot runs the squad's roles as an ordered pipeline. Each stage dispatches the roles that own it (resolved through `team.md`), waits for their findings, hands the outcome to the Scribe, and advances to the next stage without a human turn — except where a Human Gate (below) fires.

**Precondition — the squad must be built first.** Before the Research stage runs, a confirmed squad must exist: `.copilot-tracking/squad/team.md` and `routing.md` are present. When they are missing, the coordinator runs Init Mode (propose → confirm → create) from `.github/agents/squad/squad-coordinator.agent.md` to completion — including the user's profile confirmation — and only then enters the pipeline. Autopilot never auto-seeds the roster or starts Research without a built squad; the opt-in sequences the work, it does not waive the build.

1. **Research.** Dispatch the `researcher` role (and any parallel-eligible read-only roles the request matches) at `auto` tier. Gather findings; no human gate.
2. **Plan.** Dispatch the `lead` role to produce the implementation plan. In autopilot the plan does not pause for per-step human confirmation; the coordinator advances once the plan is recorded through the Scribe. When the team carries two or more **deliverable-producing roles** (see *Deliverable Fan-Out* below), the plan also enumerates the requested deliverables and the specialist role that owns each, in dependency order; that deliverable list becomes the Implement stage's execution script.
3. **Pre-implementation council.** When the work crosses two or more council-member domains (architecture, security, cost, product-fit, RAI), run the council per `.github/instructions/squad/squad-council.instructions.md` before any implementation dispatch. A `Stop` verdict fires a Human Gate. A `Go` or `Go-With-Conditions` verdict permits the implementation stage with the conditions attached as inputs.
4. **Implement.** The Implement stage takes one of two shapes, selected by what the Plan stage produced:
   * **Single build (default).** Dispatch the `developer` role. The implementation stage runs the bounded validator loop from `.github/instructions/squad/squad-autonomous.instructions.md` (council re-validation, max two cycles, divergence detection) so the build self-validates before review. Any action the implementer cannot self-validate — and every impactful action — fires a Human Gate rather than proceeding. This is the shape for every spine-shaped profile (`default`, `full`, `security`, `design`, `architecture`, `azure`).
   * **Deliverable fan-out.** When the plan's deliverable list names two or more deliverable-producing roles on the team, dispatch each owning specialist in dependency order instead of a single `developer`, each a Scribe-recorded stage. See *Deliverable Fan-Out* below.
5. **Review.** Dispatch the `tester` role at `auto` tier against the implemented changes. Record the review outcome through the Scribe.
6. **Final-outcome validation.** Autopilot never auto-releases. After review, the coordinator compiles the run outcome and fires a final-outcome notification to the registered user per `.github/instructions/squad/squad-notifications.instructions.md`, then waits for human validation before any release-tier action.

The coordinator advances stage-to-stage by reading the prior stage's findings; it hands every stage transition to the Scribe, which records it in the autopilot-run history file and updates `state.json`.

## Deliverable Fan-Out (Specialist Profiles)

Some profiles deliver their value through several distinct, specialist-owned artifacts rather than a single code or infrastructure build. The canonical case is the `product` profile, whose work spans requirements, a roadmap and backlog, an experiment, written documentation, and a stakeholder deck — each owned by a different **deliverable-producing role** (`analyst`, `product-owner`, `designer`, `experimenter`, `presenter`, `technical-writer`, `data-scientist`; defined in `.github/instructions/squad/squad-roster.instructions.md`). The fixed single-`developer` Implement stage cannot produce these, so autopilot fans the Implement stage out across the owning specialists.

**When fan-out engages.** The coordinator selects fan-out when the Plan stage's deliverable list names **two or more deliverable-producing roles that are present on the team**. Every spine-shaped profile (`default`, `full`, `security`, `design`, `architecture`, `azure`) carries at most one deliverable-producing role, so its plan is always a single build and the Implement stage runs the unchanged single-`developer` shape. Fan-out never changes the Research, Plan, council, Review, or Final-outcome stages — only the Implement stage's internal shape.

**How fan-out runs.** The Implement stage becomes an ordered sub-pipeline driven by the plan's deliverable list:

1. For each deliverable, in dependency order, the coordinator resolves the owning role to a concrete agent through the roster's *Resolving a Role to an Agent* rules and dispatches it via `runSubagent`/`task`, passing the prior deliverables as context.
2. Deliverables that do not depend on each other are dispatched in the same parallel batch; dependent deliverables run sequentially. A typical `product` order is: requirements (`analyst`) → then the roadmap and backlog (`product-owner`) and the experiment (`experimenter`) in parallel → then documentation (`technical-writer`) → then the deck (`presenter`). Design research (`designer`) runs alongside requirements when the request needs it.
3. Each specialist dispatch is a first-class recorded stage: the Scribe appends its `history/<agent>.md` entry and a consumption block, exactly as for any other dispatch. The proof-of-dispatch rule from `.github/instructions/squad/squad-state.instructions.md` applies per deliverable — a deliverable with no history entry did not run, and the run is not complete until every planned deliverable has one or the coordinator has escalated.
4. The Human Gates are unchanged. A deliverable-producing specialist that reaches an impactful action (for example, `product-owner` creating work items in a live tracker) fires the Impactful-Action Gate; a `Risk: High` or `Stop` finding fires the Risk Gate. Document and design artifacts that only write under `.copilot-tracking/` and `docs/` are not impactful and flow automatically.

**Dispatch discipline still holds.** Fan-out changes which agents the Implement stage dispatches, not the rule that the coordinator dispatches them. The coordinator never authors a deliverable itself; when an owning agent is not installed it stops and escalates per *Dispatch Discipline* rather than substituting its own output.

## Artifact Gates (Evidence Required)

Each pipeline stage is gated on the prior stage's artifact existing on disk. The coordinator confirms the evidence before advancing; a stage with no artifact and no `history/<agent>.md` entry did not run, and the pipeline cannot skip it. This is what makes the methodology auditable rather than assumed.

| Stage     | Mapped role(s)                                                                  | Must produce                              | Cannot start until                                     |
|-----------|--------------------------------------------------------------------------------|-------------------------------------------|--------------------------------------------------------|
| research  | `researcher`                                                                   | `.copilot-tracking/research/<date>/*.md`  | request classified                                     |
| plan      | `lead`                                                                          | `.copilot-tracking/plans/*.md`            | a research artifact exists                             |
| council   | `architect`, `security`, `cost-manager`, `product-owner` (+`rai` when relevant) | a `## Council Verdict` in `decisions.md`  | a plan artifact exists                                 |
| implement | `developer`                                                                    | `.copilot-tracking/changes/*`             | a plan artifact and a non-`Stop` Council Verdict exist |
| review    | `tester`                                                                       | a review record + `history/<agent>.md`    | implementation changes exist                           |

When a required artifact is missing, the coordinator dispatches the owning agent to produce it — it never authors the artifact itself and never advances on assumed completion. When the owning agent is not installed, the coordinator stops and escalates per *Dispatch Discipline* in `.github/agents/squad/squad-coordinator.agent.md`.

For a **deliverable fan-out** run (see above), the single `implement` row expands into one sub-row per planned deliverable: each owning specialist must produce its artifact (under `.copilot-tracking/` or `docs/`, per that agent's convention) and its own `history/<agent>.md` entry before the Review stage runs. The Review stage does not begin until every planned deliverable has a recorded artifact or the coordinator has escalated the gap.

## Human Gates

Human Gates are the only points where autopilot stops and hands control to the human. They are deliberately narrow. A gate stops the pipeline, fires a notification per `.github/instructions/squad/squad-notifications.instructions.md`, and waits for explicit human approval through the configured approval channel before the gated action proceeds.

When the approval channel is `github-issue`, the gate is approvable **remotely from a phone**: the human receives a GitHub mobile push and replies with `/approve`, `/changes: <note>`, or `/stop` from the issue. This is what lets an unattended run on a VM advance through its gates while the human is away from the machine. The squad persists the pending gate in `state.json` and proceeds only when an authorized approval returns — never on a timeout.

Two gate classes exist.

### Impactful-Action Gate

Before performing any impactful or irreversible action, autopilot stops and requires explicit human approval for that specific action. This reuses the **Mandatory Escalation Triggers** from `.github/instructions/squad/squad-autonomous.instructions.md`. Gated actions include, at minimum:

* Any deployment to Azure or any other environment (production or otherwise) the project has not marked safe.
* Any `git push`, and any force-push to any branch.
* Any pull-request merge.
* Schema migrations, data deletions, and other destructive data operations.
* Destructive infrastructure operations such as `terraform apply -auto-approve` or `az` deletes.
* Secret or credential rotation.
* Any side effect the user has marked irreversible for the project.

The gate is per-action: autopilot may complete all non-impactful work and stop precisely at the impactful step, presenting the human with exactly what is about to happen and why.

### Risk Gate

Autopilot also stops, regardless of pipeline stage, on any of these — identical to the autonomous loop's mandatory triggers so the two modes never disagree:

* Any `Stop` verdict from the council or any individual council role.
* Any `Risk: High` finding from `security`, `cost-manager`, or `rai`.
* Any cost-impacting move the `cost-manager` flags at `confirm` tier.
* Any compliance violation flagged by `rai` or `security` (regulated-data handling, PII leakage, GDPR/HIPAA scope).
* Divergence: two consecutive validator cycles producing different verdicts on the same issue.
* The configured per-turn cost ceiling (`cost-ceiling=$X`) would be exceeded by the next stage or cycle.

A single qualifying trigger is enough to fire the gate, no matter how many other findings are clean.

## What Autopilot Does Not Do

* It does not stop for human confirmation at every stage. Research, planning, implementation, and review flow automatically between gates.
* It does not perform any impactful action without explicit human approval at the Impactful-Action Gate.
* It does not auto-release: the final outcome always returns to the human for validation before deploy, push, or merge.
* It does not downgrade a `confirm`-tier action to `auto`. Autopilot changes *who sequences the work*, not *which actions need a human*.

## Final-Outcome Validation

When the pipeline reaches Final-outcome validation:

1. The coordinator compiles a concise outcome: what the squad built, the review result, any conditions left open, and the impactful actions awaiting approval (if any).
2. The coordinator fires a `final-outcome` notification to the registered approval channel through `.github/instructions/squad/squad-notifications.instructions.md`. When the channel is `github-issue`, the human can validate the outcome from a phone. When no channel is configured, or no transport is available, the notification degrades to an in-chat summary and is still logged.
3. The coordinator waits for human validation. The human may approve (releasing the gated impactful actions one by one), request changes (re-entering the pipeline at the appropriate stage), or stop.

## History Entries

Every autopilot run produces history the Squad Scribe writes (the single-writer rule from `.github/instructions/squad/squad-state.instructions.md` still holds):

1. **Per-agent history.** Each dispatched role adds its normal entry to `.copilot-tracking/squad/history/<agent>.md`, plus the autopilot run id and stage so the run is reconstructable.
2. **Autopilot-run summary.** The coordinator hands the Scribe one summary payload per run. The Scribe writes it to `.copilot-tracking/squad/history/autopilot-run-<id>.md`, where `<id>` is the run topic-id slug. The summary uses this shape:

```markdown
---
description: "Autopilot-run summary for topic <id>"
---

# Autopilot Run: <id>

* Topic: <one-line summary>
* Opt-In: mode=autopilot
* Cost Ceiling: <value or unset>
* Outcome: completed (awaiting final validation) | escalated (<reason>) | stopped (<reason>)

## Stages

| Stage  | Role(s)      | Result                          | Gate Fired                    |
|--------|--------------|---------------------------------|-------------------------------|
| research | <agent(s)> | <one-line outcome>              | none                          |
| plan     | <agent>    | <one-line outcome>              | none                          |
| council  | <roles>    | <verdict-or-skipped>            | <none or Risk Gate reason>    |
| implement| <agent>    | <one-line outcome>              | <none or Impactful-Action>    |
| review   | <agent>    | <one-line outcome>              | none                          |
| final    | coordinator| notified <recipient-or-in-chat> | Final-Outcome Validation      |

## Gates and Approvals

| Timestamp | Gate                 | Awaiting / Resolved By        | Notes                  |
|-----------|----------------------|-------------------------------|------------------------|
| <ts>      | <Impactful / Risk / Final> | <human decision or pending> | <one-line>             |
```

In a **deliverable fan-out** run, the single `implement` row expands into one row per deliverable — labelled `implement: <deliverable>` with its owning agent — so the run's per-specialist outcomes and any gates are all visible in the table.

The autopilot-run file is append-only by topic-id; one file per run topic. Re-running the same topic appends a new dated `## Stages` section rather than overwriting.
