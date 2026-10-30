---
name: squad-scribe-cold-gates-and-verdicts
description: "Scribe cold section: Council/Intake/Discovery verdict placeholders, the autonomous-loop-cycle history variant and its summary file, the single-squad autopilot-run summary, and notifications.md. Read only when the turn's payload is a verdict, an autonomous-loop or autopilot-run summary, or a notification."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-19"
---

# Scribe Cold Section: Gates, Verdicts, and Run Summaries

Read this file only when the turn's payload is one of: a **Council Verdict**, **Intake Readiness Verdict**, or **Discovery Verdict** (Payload-to-Step Map Steps 5, 9, 12), an **autonomous-loop summary** (Step 6), an **autopilot-run summary** at the single-squad root (Step 8), or a **notification**. An ordinary decision or history dispatch never needs this file — see the Cold-File Dispatch Table in [scribe-procedure.md](scribe-procedure.md).

## Verdict Entries in decisions.md

Verdict entries (Council, Intake Readiness, Discovery) are appended to `decisions.md` using the exact schema in the matching instruction file, stamped into the shapes below:

* **Council Verdict** — `squad-council.instructions.md`. `Verdict` is exactly `Go`, `Go-With-Conditions`, or `Stop`.
* **Intake Readiness Verdict** — `squad-intake-gate.instructions.md`. `Verdict` is exactly `Ready`, `Ready-With-Gaps`, or `Not-Ready`.
* **Discovery Verdict** — `squad-discovery-gate.instructions.md`. `Depth` is exactly `quick`, `standard`, `deep`, or `skip`; `Opt-In` is exactly `offer-accepted`, `explicit-input`, or `offer-declined`. Write the entry on a `skip` depth as well, with the body sections empty — a recorded declination is what stops the coordinator re-offering the gate for the same topic, so omitting it silently re-arms a question the user already answered. Preserve the reason attached to every discarded option verbatim rather than summarizing it away.

For every verdict: when a required schema section is missing from the payload, do not write a partial verdict — return a failure note so the coordinator can re-assemble it. On success, return the verdict label, the topic id, the file path, and the **Decision Ref** (the file path plus the entry's Markdown heading anchor, for example `decisions.md#council-verdict-<timestamp>-<topic-id>`) so the coordinator can link straight to the section.

The autonomous-loop summary uses the shape in `squad-autonomous.instructions.md` and is append-only by topic-id: when the file exists, append a new dated `## Iterations` section rather than overwriting prior runs. Hand each loop iteration's per-agent dispatch records through the normal history append so each role's file also reflects the cycle.

### Cost Preflight Placeholder

The coordinator stamps this shape into `decisions.md` before post-initialization work dispatch:

```markdown
## Cost Preflight <timestamp> <run-id> <round-id>

* Ceiling USD: <positive number>
* Estimated Spend So Far USD: <currentRun.estCostUsd>
* Remaining USD: <max(0, ceiling - spend)>
* Projected Cost USD: <calibrated point estimate>
* Reserve Multiplier: 3.0
* Admission Cost USD: <projected cost x 3.0>
* Confidence: low | medium
* Basis: estimated | calibrated
* Decision: within-ceiling | over-ceiling | approved-over-ceiling | cannot-confirm
* Approved From: <prior over-ceiling Decision Ref; approved-over-ceiling only>
* Approval Ref: <in-chat or remote human approval reference; approved-over-ceiling only>
* Reason: <one-line reproducible reason>
* Evaluated Dispatch Set: <ordered slot ids>
* Permitted Next Dispatch Set: <ordered slot ids or none>
* Estimate Notice: Forecast only; not billed cost.

### Planned Demand

| Slot | Stage | Role | Count | Dispatch Class | Pricing Basis | Internal Turns | Base Context | Growth/Turn | Output/Turn | Projected Cost |
|------|-------|------|------:|----------------|---------------|---------------:|-------------:|------------:|------------:|---------------:|
| <id> | <stage> | <role> | <n> | <class> | <model or max-candidate set> | <turns> | <tokens> | <tokens> | <tokens> | <usd> |
```

### Council Verdict Placeholder

The Scribe stamps this shape when a council runs. The council is task-fit, so the Findings by Role table carries one row per dispatched role only, and every lens left out is listed under `Council Members Not Proposed` with its reason:

```markdown
## Council Verdict <timestamp> <topic-id>

* Topic: <one-line summary of the proposal>
* Proposal Ref: <path-to-plan-or-design>
* Council Members Dispatched: architect, security
* Council Members Not Proposed: cost-manager — no billable change; product-owner — scope unchanged; rai — no AI/ML behavior
* Verdict: Go | Go-With-Conditions | Stop

### Findings by Role

| Role          | Verdict | Risk        | Blocking Issues | Conditions | Suggested Follow-ups |
|---------------|---------|-------------|-----------------|------------|----------------------|
| architect     | <label> | <risk>      | <list-or-none>  | <list>     | <list>               |
| security      | <label> | <risk>      | <list-or-none>  | <list>     | <list>               |

### Synthesis

* Blocking Issues: <consolidated list with role attribution; empty when verdict is Go>
* Conditions: <consolidated list with role attribution; empty when verdict is Go>
* Suggested Follow-ups: <consolidated list with role attribution>

### Implementation Gate

* Permits Implementation Dispatch: yes (Go, Go-With-Conditions) | no (Stop)
* Conditions Outstanding: <count>
```

For a Watch Mode material handoff, the final topic verdict must agree with the most-restrictive findings: a `Block`, `Risk: High`, or unresolved blocking issue cannot be synthesized as `Go`. A skipped summary row never overrides a Council Verdict already recorded for that run. `Go-With-Conditions` still permits implementation dispatch with the conditions attached. Before handoff, record their satisfaction or explicit acceptance in the latest verdict for the topic; append a resolved verdict rather than rewriting an earlier decision. `Conditions Outstanding` must be a nonnegative integer. Zero declares no unresolved conditions. When a positive count remains (for example, an accepted deferral), add `* Conditions Satisfied:` and/or `* Conditions Accepted:` bullets naming every condition as `(role) <exact condition text from Findings by Role>`. Missing, unrelated, or incomplete disposition records block handoff; a valid explicit acceptance still permits it.

### Intake Readiness Verdict Placeholder

The Scribe stamps this shape when the intake gate runs:

```markdown
## Intake Readiness Verdict <timestamp> <topic-id>

* Topic: <one-line summary of the work the inputs ground>
* Inputs Reviewed: <comma-separated artifact paths or references>
* Validator Dispatched: <resolved agent name>
* Verdict: Ready | Ready-With-Gaps | Not-Ready
* Remediation Cycles: <0, 1, or 2>

### Findings

| Dimension        | Result    | Blocking Gaps  | Non-Blocking Gaps |
|------------------|-----------|----------------|-------------------|
| Completeness     | pass/fail | <list-or-none> | <list-or-none>    |
| Clarity          | pass/fail | <list-or-none> | <list-or-none>    |
| Testability      | pass/fail | <list-or-none> | <list-or-none>    |
| Consistency      | pass/fail | <list-or-none> | <list-or-none>    |
| Scope Boundaries | pass/fail | <list-or-none> | <list-or-none>    |

### Clarifying Questions

* <question for the user; empty when verdict is Ready>

### Recorded Assumptions

* <assumption carried into downstream work; empty when none>

### Intake Gate

* Permits Downstream Dispatch: yes (Ready, Ready-With-Gaps) | no (Not-Ready)
* Blocking Gaps Outstanding: <count>
```

## Autonomous-Loop-Cycle History Variant

An autonomous-loop cycle replaces the `history/<agent>.md` entry body (see [entry-schemas.md](entry-schemas.md)) with the shape below and still carries its own `#### Consumption` block:

```markdown
### <timestamp> autonomous-loop:<topic-id> cycle:<1|2>

* Request: <scoped request the agent received>
* Verdict Returned: <label> (Risk: <level>)
* Blocking Issues: <list-or-none>
* Conditions: <list-or-none>
* Outcome: <one-line summary>
* See: `.copilot-tracking/squad/history/autonomous-loop-<topic-id>.md`
```

## history/autonomous-loop-<id>.md

One file per autonomous-loop topic. Append-only by topic-id: subsequent runs against the same topic append a new dated `## Iterations` section rather than overwriting. The Scribe writes this file only when the coordinator runs in `mode=autonomous`.

```markdown
---
description: "Autonomous-loop summary for topic <id>"
---

# Autonomous Loop: <id>

* Topic: <one-line summary>
* Opt-In: mode=autonomous
* Cost Ceiling: <value or unset>
* Outcome: converged (Go) | converged (Go-With-Conditions) | escalated (<reason>)

## Cost Preflight Rounds

| Round | Decision | Confidence | Remaining USD | Admission USD | Decision Ref |
|-------|----------|------------|--------------:|--------------:|--------------|
| <round-id> | <within-ceiling / over-ceiling / approved-over-ceiling / cannot-confirm> | <low / medium> | <usd> | <usd> | `decisions.md#cost-preflight-<timestamp>-<run-id>-<round-id>` |

## Iterations

| Cycle | Verdict                        | Blocking Issues | Conditions     | Notes                    |
|-------|---------------------------------|-----------------|----------------|--------------------------|
| 1     | Go / Go-With-Conditions / Stop | <list-or-none>  | <list-or-none> | <one-line cycle summary> |
| 2     | (when run)                     | <list-or-none>  | <list-or-none> | <one-line cycle summary> |

## Final Verdict Reference

* Council Verdict: see `decisions.md` under `## Council Verdict <timestamp> <id>`
```

### Autopilot-Run Summary

Append the run summary to `history/autopilot-run-<id>.md` using the template in the section below, append-only by topic-id. This runs at the single-squad root; a federation meta-run uses [scribe-cold-federation.md](scribe-cold-federation.md) instead.

**Write the `Dispatch Record` column from `history/`, never from the coordinator's stage narrative.** For each stage row, name the `history/<agent>.md` file this run recorded for that stage's role. When no such file exists, the cell is the literal `— none recorded` and the row stands. The Scribe is the only writer of history, so it is the only participant that knows which stages actually left a record, and the coordinator's account of the run is exactly the thing that cannot be trusted to say so.

**Then set `Outcome` from the column, not from the narrative.** When any row reads `— none recorded`, the outcome is `incomplete (<n> stage(s) without a dispatch record)` — never `completed`. A run whose deliverables look finished and whose cast left no history was authored inline rather than dispatched, and this is the line that says so in the document the human reads. Return the same count in the confirmation note.

## history/autopilot-run-<id>.md

One file per autopilot run. Append-only by topic-id: subsequent runs against the same topic append a new dated `## Stages` section rather than overwriting. The Scribe writes this file only when the coordinator runs in `mode=autopilot`.

```markdown
---
description: "Autopilot-run summary for topic <id>"
---

# Autopilot Run: <id>

* Topic: <one-line summary>
* Opt-In: mode=autopilot
* Cost Ceiling: <value or unset>
* Outcome: completed (awaiting final validation) | incomplete (<n> stage(s) without a dispatch record) | escalated (<reason>) | stopped (<reason>)
* Trigger Source: <state.json trigger.source; Watch Mode only>
* Trigger Ref: <state.json trigger.ref; Watch Mode only>
* Trigger Event ID: <state.json trigger.eventId; Watch Mode only>
* Trigger Actor: <state.json trigger.actor; Watch Mode only>
* Trigger Received At: <state.json trigger.receivedAt; Watch Mode only>

## Cost Preflight Rounds

| Round | Evaluated Dispatch Set | Permitted Next Dispatch Set | Decision | Confidence | Remaining USD | Admission USD | Decision Ref |
|-------|------------------------|-----------------------------|----------|------------|--------------:|--------------:|--------------|
| <round-id> | <ordered slot ids> | <ordered slot ids or none> | <within-ceiling / over-ceiling / approved-over-ceiling / cannot-confirm> | <low / medium> | <usd> | <usd> | `decisions.md#cost-preflight-<timestamp>-<run-id>-<round-id>` |

## Stages

| Stage     | Role(s)     | Dispatch Record              | Result                          | Gate Fired                 |
|-----------|-------------|------------------------------|----------------------------------|-----------------------------|
| research  | <agent(s)>  | `history/<agent>.md`         | <one-line outcome>              | none                       |
| plan      | <agent>     | `history/<agent>.md`         | <one-line outcome>              | none                       |
| council   | <roles>     | `history/<agent>.md` each    | <verdict-or-skipped>            | <none or Risk Gate reason> |
| implement | <agent>     | `history/<agent>.md`         | <one-line outcome>              | <none or Impactful-Action> |
| review    | <agent>     | `history/<agent>.md`         | <one-line outcome>              | none                       |
| final     | coordinator | n/a                          | notified <recipient-or-in-chat> | Final-Outcome Validation   |
```

`Dispatch Record` names the history file the Scribe wrote for that stage, and is filled from `history/` rather than from the coordinator's account of the run. A stage with no such file carries the literal `— none recorded`, and any such cell forces the `incomplete` outcome above. This is the run's own report that its cast was not dispatched, written by the only participant that knows.

The five `Trigger ...` bullets are omitted outside Watch Mode. In Watch Mode they are required, copied exactly from `state.json trigger`, and repeated on a resumed run's latest summary entry so the trusted handoff can bind the latest stages to the authorized event rather than to an older committed summary.

Preserve fractional seconds in `receivedAt`; the handoff compares timestamp instants, so equivalent timezone offsets are valid without rounding away milliseconds. Stage results, the latest role outcomes, and the final summary must describe completed work, never `not started`, `in progress`, or a failed result. Successful test reports such as `8 pass, 0 fail` remain successful outcomes. Plain-text deliverables may omit Markdown headings, but a heading alone is not substantive evidence in either `.md` or `.txt` files.

In a deliverable fan-out run, the single `implement` row expands into one row per deliverable (`implement: <deliverable>` with its owning agent).

## notifications.md

Append-only log of notifications (pings) the squad fired. The header is written once; every notification is appended below it. Records the trigger, the recipient, the resolved channel, and the decision awaited.

```markdown
---
description: "Append-only log of squad notifications (pings) and their delivery channel"
---

# Squad Notifications

Each entry records a notification the squad fired: when, to whom, the trigger, the channel it resolved to, and the decision awaited. Entries are appended in chronological order and never edited.
```

## Watch Open Questions

When the payload includes current-run Open Questions, validate every `ID`, `Source`, `Question`, `Impact`, and `Status` cell before writing. After normalization, limits are ID 32, Source 256, Question 1,000, Impact 1,000, and Status 256. Reject empty cells, overlength cells, and duplicate IDs. `Source` accepts only `OQ-WATCH-NNN`, `decisions.md#lower-kebab-anchor`, or the current thread `owner/repo#N`.

Rendering is deterministic and idempotent: normalize CR, LF, and table pipes to spaces; HTML-escape `&`, `<`, and `>`; neutralize every `@` with U+200B; break image, link, and fence delimiters; and insert U+200B before `#` in `Closes`, `Fixes`, or `Resolves` references. Do not write a partial attacker-controlled table. On validation failure, record the generic failure and escalate on the source thread.

Publish the encoded table between `<!-- squad-watch-open-questions:start -->` and `<!-- squad-watch-open-questions:end -->` on a material draft or an existing mapped PR. Leave every byte outside that pair unchanged. If the markers are duplicated or ambiguous, stop and leave the body unchanged. A run with no material change and no existing deliverable creates no branch, placeholder, or pull request; its encoded questions travel on the source thread. The current-run slice starts at the single `## Watch Profile Selection` heading whose run id equals the trusted resolver run id. A later selection heading, or a second heading for that same run id, fails closed and is not a truncation boundary. A heading inside a completed fence or DATA frame is quoted text, not a boundary. Council coverage uses one question id per verdict and finding, `COUNCIL-<ordinal>-<ROLE>-RISK` and `COUNCIL-<ordinal>-<ROLE>-COND-<n>`. Two verdicts by the same role require two ids. A no-material numeric source-thread comment renders the staging artifact only after its member, run id, thread, stable ref, and trusted base match the resolver; a mismatch posts the generic failure. That artifact is produced in the same read-only job as the model. The binding check makes it self-consistent, but it is not independently attested. Isolating that attestation from the model runner is a residual limitation, not part of this publication path.
