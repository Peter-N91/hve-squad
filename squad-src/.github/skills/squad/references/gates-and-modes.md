---
name: squad-gates-and-modes
description: "Operator procedures for the discovery, intake, and council gates and for the autonomous, autopilot, and notification modes."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-08-14"
---

# Squad Gates and Modes

## Discovery Gate Procedure

The discovery gate is the operator's brainstorming session for work that has nothing written down yet. It fires on the exact inverse of the intake gate's trigger: no requirement or input artifact is in scope, the turn advances toward a plan or deliverable, and the request states a goal rather than a settled task. It is **opt-in and offered, never automatic** — validation can be automatic, ideation cannot, because the value of a brainstorm is the human's ideas — and it is **scoped to the `product` and `full` profiles**, the only rosters that carry the roles it dispatches. The full protocol lives in `.github/instructions/squad/squad-discovery-gate.instructions.md`; the operator's view is:

1. In a `product` or `full` squad the coordinator either honors a `discovery=quick|standard|deep|skip` input on `/squad`, or asks once per topic and waits. A declined offer is recorded and never re-asked for that topic; the input still works afterwards. In every other profile the gate is silent — no offer, no escalation — though an explicit `discovery=` is still honored with one combined escalation naming the roles it must add.
2. The chosen depth decides who runs: `quick` dispatches `analyst`; `standard` dispatches `designer` (resolved to `DT Coach`) then `analyst`; `deep` adds `challenger` and `experimenter` before the write-up. `deep` needs `challenger`, which only `full` seeds, so a `product` squad is offered the role or `standard` instead.
3. **The dispatched roles interview you.** Each puts its questions through the question tool one at a time and waits, the same discipline `Squad SQL Migration Advisor` follows. A role that cannot reach you returns its questions rather than inventing the answers — the session stops instead of banking a brief built from guesses.
4. Only `analyst` writes a file: the brief, landing in the `analyst` Deliverable Root as `<date>-<topic-id>-brief.md`. It carries the problem, why now, scope boundaries, the success measure, the options considered **with the reason each was discarded**, the chosen direction, assumptions, and open questions.
5. The Squad Scribe appends a single `## Discovery Verdict <timestamp> <topic-id>` entry to `decisions.md`, including on a `skip`. The coordinator does not write the verdict or the brief.
6. The brief is itself a requirement artifact, so the **intake gate** then assesses it — resolved to an agent other than the one that wrote it, so the check is independent. The two gates are a chain, not a loop: a `Not-Ready` brief runs intake's own remediation loop and never re-opens discovery.
7. The gate is **never available on an unattended path**. In Watch Mode the triggering issue or pull-request body becomes the input artifact and the intake gate assesses it instead, so an unattended run stays gated by validation rather than ungated.

## Intake Gate Procedure

The intake gate is the operator's pre-work readiness check on the inputs a turn builds on. It is conditional: the coordinator runs it only when the turn's work is grounded in requirement or input artifacts (a PRD, BRD, specification, requirements document, user story, design document, transcript, or a user-referenced input file) and advances toward a plan, a build, or a deliverable. When no input grounds the work, the gate is a no-op. The full protocol lives in `.github/instructions/squad/squad-intake-gate.instructions.md`; the operator's view is:

1. The coordinator dispatches `intake-validator` (seeded in the `product` and `full` profiles and addable to any roster, resolved by input type per the roster Selection Cue: PRD → PRD Quality Reviewer, BRD → BRD Quality Reviewer, otherwise the default PRD Quality Reviewer) to assess the inputs for completeness, clarity, testability, consistency, and scope boundaries. When the active roster lacks `intake-validator`, the coordinator offers to add it rather than skipping the check.
2. The validator returns a verdict label (`Ready`, `Ready-With-Gaps`, `Not-Ready`) with its blocking and non-blocking gaps and any clarifying questions.
3. The Squad Scribe appends a single `## Intake Readiness Verdict <timestamp> <topic-id>` entry to `decisions.md`. The coordinator does not write the verdict.
4. On `Ready` or `Ready-With-Gaps`, downstream planning and implementation proceed (non-blocking gaps carried as recorded assumptions). On `Not-Ready`, the coordinator runs the bounded auto-remediation loop — dispatch `analyst` or `product-owner` to fill the blocking gaps, then re-validate; capped at two cycles — and escalates when a gap needs a human decision, the cap is reached with blocking gaps open, or the blocking-gap set stops shrinking.
5. The verdict gates downstream dispatch and runs ahead of the Council and Implementation gates, and behind the discovery gate when one ran; a non-stale `Ready` verdict for the same unchanged inputs is reused rather than re-run.

## Council Procedure

The council is the operator's pre-implementation cross-check. The coordinator triggers it when the user explicitly asks for a council, a validation, a cross-check, or a pre-implementation review, or when a request mixes implementation language with risk language and crosses two or more council-member domains (architecture, security, cost, product-fit, RAI). The full protocol lives in `.github/instructions/squad/squad-council.instructions.md`; the operator's view is:

1. The coordinator dispatches the default council in a single parallel batch: `architect`, `security`, `cost-manager`, `product-owner`, plus optional `rai` when AI/ML, training data, agent autonomy, or regulated data is in scope.
2. Each council role returns a finding with a verdict label (`Approve`, `Conditional`, `Concern`, `Block`) and a risk label (`Risk: Low`, `Risk: Medium`, `Risk: High`).
3. The Squad Scribe synthesizes the findings using a most-restrictive-wins rule: any `Block` or any `Risk: High` drives a `Stop` verdict; any `Conditional` (with no blockers) drives `Go-With-Conditions`; otherwise the verdict is `Go`.
4. The Scribe appends a single `## Council Verdict <timestamp> <topic-id>` entry to `decisions.md`. The coordinator does not write the verdict.
5. The verdict gates the next turn's implementation dispatch: `Go` or `Go-With-Conditions` permits dispatch (with conditions attached as inputs); `Stop` blocks dispatch and the coordinator escalates.

## Autonomous Procedure

The opt-in `auto-validated` tier lets a council validate a developer's output on the same turn, without an intervening user prompt. The full protocol lives in `.github/instructions/squad/squad-autonomous.instructions.md`; the operator's view is:

1. The user opts in per turn by passing `mode=autonomous` to `/squad`. Without that input, the coordinator runs the normal six-step protocol.
2. The coordinator runs the loop: council dispatch → verdict synthesis → implementer dispatch (on `Go` or `Go-With-Conditions`) → council re-validation (cycle 1) → optional council re-validation (cycle 2).
3. The re-validation cap is hard at two cycles; after cycle 2 the coordinator escalates regardless of outcome.
4. The loop stops and escalates immediately on any mandatory trigger: a `Stop` verdict, a `Risk: High` from `security` / `cost-manager` / `rai`, any cost-impacting `confirm`-tier move, any compliance violation, or any irreversible write (production deploy, schema migration, data deletion, force-push).
5. Divergence detection escalates immediately when two consecutive cycles produce different verdicts on the same issue, even before the cap.
6. A per-turn cost ceiling (`cost-ceiling=$X`, optional) caps spend; when exceeded, the coordinator escalates instead of running the next cycle.
7. The Scribe writes a per-topic summary to `history/autonomous-loop-<id>.md` (append-only by topic-id) and per-cycle entries to each role's `history/<agent>.md`.

## Autopilot Procedure

The opt-in `mode=autopilot` runs the full delivery pipeline end-to-end, stopping for the human only at impactful actions and final-outcome validation. The full protocol lives in `.github/instructions/squad/squad-autopilot.instructions.md`; the operator's view is:

1. The user opts in per turn by passing `mode=autopilot` to `/squad`. Without that input, the coordinator runs the interactive per-turn protocol where each stage is gated by its routing tier.
2. The coordinator sequences the pipeline: an opt-in discovery gate (offered before the pipeline starts when nothing is written down yet) → a conditional intake gate (when the work is grounded in requirement or input artifacts) → research → plan → pre-implementation council → implement (via the autonomous validator loop) → review → final-outcome validation, advancing stage-to-stage without a human turn. For a profile that carries two or more deliverable-producing roles (`product` and `full`), the implement stage fans out across the owning specialists — the plan enumerates the deliverables and the coordinator dispatches each specialist in dependency order, each a Scribe-recorded stage — instead of a single `developer`; every other profile keeps the single-build implement stage.
3. The pipeline stops only at two Human Gate classes: an **Impactful-Action Gate** (deploy, `git push`/force-push, PR merge, schema migration, data deletion, destructive infra ops, secret rotation, or any user-marked irreversible action) and a **Risk Gate** (any `Stop` verdict, `Risk: High` from security/cost/RAI, `confirm`-tier cost move, compliance violation, validator divergence, or cost-ceiling breach).
4. Autopilot never auto-releases: after review it fires a `final-outcome` notification to the registered contact and waits for human validation before any release-tier action.
5. The Scribe writes a per-run summary to `history/autopilot-run-<id>.md` (append-only by topic-id) and the notification records to `notifications.md`.

## Notification Procedure

The squad captures an optional contact at build time and pings it for approvals. The full contract lives in `.github/instructions/squad/squad-notifications.instructions.md`; the operator's view is:

1. During Init Mode the coordinator **always asks** for an approval channel and seeds the answer into `state.json` under `notify`. The choices are `github-issue` (recommended for unattended/VM runs — approvable from a phone), `webhook` (outbound team ping only), or `in-chat` (default). Declining is a valid answer; skipping the question is not. A federation asks once at the federation root and every sub-squad inherits that object, so the question is never repeated per sub-squad — and an unattended Watch Mode bootstrap, having no user to ask, inherits it silently.
2. Delivery is resolved at send time by the channel: `github-issue` opens/assigns an approval issue via the GitHub MCP or `gh` CLI; `webhook` POSTs to a configured tool/MCP or `SQUAD_WEBHOOK_URL`; otherwise it degrades to an in-chat ping. The package ships no transport, and the squad always keeps an in-chat approval available so a run is never permanently blocked.
3. For `github-issue`, the human approves remotely with a keyword comment (`/approve`, `/approve-all`, `/changes: <note>`, `/stop`) or a `squad/*` label. Only the registered handle or a repo collaborator can approve, and only the keyword acts — comment prose is never executed as a command. An unattended run resumes via a host-side poll loop or a GitHub Action on `issue_comment` (the inbound half of Watch Mode / DR-01).
4. In `mode=autopilot`, a ping fires at each Human Gate and at final-outcome validation. In interactive mode, a ping fires at each step gate. In `mode=autonomous`, a ping fires on the loop's mandatory escalations.
5. The Scribe appends every fired notification to `notifications.md` (append-only).
