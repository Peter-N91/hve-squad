# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.10.3] - 2026-07-20

### Added

- **Requirements intake gate (conditional pre-work readiness check)** — before the squad plans, implements, or produces a deliverable on work grounded in requirement or input artifacts (a PRD, BRD, specification, user story, design document, transcript, or a user-referenced file), the coordinator now runs an intake gate that validates those inputs for completeness, clarity, testability, consistency, and scope boundaries, and records an `## Intake Readiness Verdict` (`Ready`, `Ready-With-Gaps`, or `Not-Ready`) in `decisions.md`. On `Not-Ready` it runs a bounded auto-remediation loop (dispatch `analyst`/`product-owner` to fill the blocking gaps, then re-validate; capped at two cycles) and escalates when a gap needs a human decision. The gate is conditional and additive: with no input artifacts in scope it is a silent no-op.
  - New `squad-intake-gate.instructions.md` conventions: trigger conditions, gate membership, readiness assessment, verdict synthesis, the auto-remediation loop, the Intake Readiness Verdict schema, the verdict anchor and reuse, and mode/federation interaction (`squad-src/.github/instructions/squad/squad-intake-gate.instructions.md`).
  - New `intake-validator` role seeded into the `product` and `full` profiles (addable to any roster), reusing existing agents by input type — Product Manager Advisor (default), PRD Quality Reviewer, BRD Quality Reviewer, and Task Challenger (`squad-src/.github/instructions/squad/squad-roster.instructions.md`).
  - Routing gains an Intake Gate section and an explicit `intake-validator` routing row; the gate runs ahead of the Implementation Gate and, in profiles without the role, escalates to add it rather than skipping the check (`squad-src/.github/instructions/squad/squad-routing.instructions.md`).
  - The Squad Coordinator runs the gate in its per-turn protocol and as autopilot stage 0; the Squad Federation Coordinator inherits it per sub-squad; the Squad Scribe writes the Intake Readiness Verdict (`squad-src/.github/agents/squad/squad-coordinator.agent.md`, `squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`, `squad-src/.github/agents/squad/squad-scribe.agent.md`).
  - Autopilot adds a conditional intake stage (stage 0) with an artifact gate and a Risk Gate trigger for an unclearable `Not-Ready`; the state conventions record the intake stage in proof-of-dispatch; the squad skill documents the gate procedure and seed templates (`squad-src/.github/instructions/squad/squad-autopilot.instructions.md`, `squad-src/.github/instructions/squad/squad-state.instructions.md`, `squad-src/.github/skills/squad/SKILL.md`).
  - Documented the intake gate on the usage page and the home page (`docs/usage.html`, `docs/index.html`).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.10.3"
```

[0.10.3]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.10.3

## [0.10.2] - 2026-07-17

### Added

- **Federation-level autopilot (opt-in)** — `/squad-federation mode=autopilot` with no `squad=` target now runs a meta-pipeline that coordinates several sub-squads under one coherent set of Human Gates. It orders the selected sub-squads by dependency (confirmed at the first gate), runs each one's standard single-squad autopilot inner run scoped to `members/<name>/`, aggregates every Impactful-Action and Risk Gate to the federation level (attributed to the raising sub-squad, most-restrictive-wins), applies one aggregate `cost-ceiling`, and ends with a single consolidated final-outcome validation. It is opt-in and backward-compatible: a single `squad=` target keeps the forward-only behavior, single-squad autopilot is unchanged, and each sub-squad's inner pipeline is untouched.
  - New `squad-federation-autopilot.instructions.md` conventions: the trigger and opt-in surface, the build precondition, the meta-pipeline contract, sub-squad execution ordering, federation Human Gates, the aggregate cost ceiling, and consolidated final-outcome validation (`squad-src/.github/instructions/squad/squad-federation-autopilot.instructions.md`).
  - `Squad Federation Coordinator` gains a **Federation Autopilot Mode** section, and the `/squad-federation` prompt documents the meta-pipeline trigger (`squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`, `squad-src/.github/prompts/squad/squad-federation.prompt.md`).
  - Two-level run provenance: the Squad Scribe writes a federation-root `history/autopilot-run-<id>.md` linking each sub-squad's inner run, and the federation `state.json` gains additive `mode` and `currentRun` fields (`schemaVersion` `1.0` → `1.1`) for the aggregate cost (`squad-src/.github/agents/squad/squad-scribe.agent.md`, `squad-src/.github/skills/squad/SKILL.md`, `squad-src/.github/instructions/squad/squad-federation.instructions.md`).
  - Watch Mode gains a federation-routing clause: a repository event is routed to a sub-squad via `meta-routing.md`, then that sub-squad's autopilot runs unchanged and produces a pull request (`squad-src/.github/instructions/squad/squad-watch-mode.instructions.md`).
  - Documented federation-wide autopilot on the usage page (`docs/usage.html`).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.10.2"
```

[0.10.2]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.10.2

## [0.10.1] - 2026-07-17

### Changed

- Updated hve-core dependency pin to `5c15a03` (5c15a03c78da2408527693e0fc3b3e387bf99cb2).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.10.1"
```

[0.10.1]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.10.1

## [0.10.0] - 2026-07-16

### Added

- **Squad federation (in-repo sub-squads)** — one repository can now host several named sub-squads side by side (for example, a `product` sub-squad for the business team and an `azure` sub-squad for the architects), each an ordinary squad rooted at `.copilot-tracking/squad/members/<name>/`. Federation is opt-in and additive: a repository that never opts in behaves exactly as before.
  - New `Squad Federation Coordinator` agent and `/squad-federation` prompt: builds a federation (propose → confirm → create), then routes each request to one or more sub-squads (or an explicit `squad=<name>` target) and runs each scoped to its own root (`squad-src/.github/agents/squad/squad-federation-coordinator.agent.md`, `squad-src/.github/prompts/squad/squad-federation.prompt.md`).
  - New `squad-federation.instructions.md` conventions: the parameterized squad root (`squadRoot`), the federation state layout, detection precedence (`federation.md` → federation, else top-level `team.md` → plain squad, else Init), the `federation.md` registry and `meta-routing.md` schemas, required-unique sub-squad naming, and the two-level single-writer rule (`squad-src/.github/instructions/squad/squad-federation.instructions.md`).
  - The Squad Coordinator gained an optional `squadRoot` input and a federation-aware Step 1, and its Init Mode now opens with a single-squad-or-federation choice on a fresh project; the Squad Scribe writes scoped to the resolved root and to the federation root; the squad skill documents the federation layer and ships federation seed templates (`squad-src/.github/agents/squad/squad-coordinator.agent.md`, `squad-src/.github/agents/squad/squad-scribe.agent.md`, `squad-src/.github/skills/squad/SKILL.md`, `squad-src/.github/prompts/squad/squad.prompt.md`).
- Documentation: a Federation section in the Usage guide and a Federation feature card on the site home page (`docs/usage.html`, `docs/index.html`).

### Notes

- Multi-repo federation (a hub coordinating one squad per repository) and federation-level autopilot (a coordinated pipeline across sub-squads) are researched and planned but not shipped in this release; single-sub-squad autonomy modes work today via forwarding.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.10.0"
```

[0.10.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.10.0

## [0.9.5] - 2026-07-15

### Changed

- Updated hve-core dependency pin to `05cd2e1` (05cd2e14884b1a25f7b8dc571ee6ade2a1368300).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.9.5"
```

[0.9.5]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.9.5

## [0.9.4] - 2026-07-14

### Changed

- Updated hve-core dependency pin to `766a4dc` (766a4dcc7a5f1905f15ed021189ad88b567f6da2).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.9.4"
```

[0.9.4]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.9.4

## [0.9.3] - 2026-07-12

### Changed

- Updated hve-core dependency pin to `d293ea3` (d293ea35de7732357d0ef3b16edf56ac6358372b).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.9.3"
```

[0.9.3]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.9.3

## [0.9.2] - 2026-07-11

### Changed

- Updated hve-core dependency pin to `25308f0` (25308f09fd4ae82defdf06324dcd9b6f9604e3c4).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.9.2"
```

[0.9.2]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.9.2

## [0.9.1] - 2026-07-10

### Changed

- Updated hve-core dependency pin to `677fd2e` (677fd2e5f4230a4db9d97872506fb595e66ba598).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.9.1"
```

[0.9.1]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.9.1

## [0.9.0] - 2026-07-08

### Added

- **Watch Mode (DR-01)** — the event-driven "continuous AI" trigger contract that turns a new issue (or PR, comment, schedule, or manual dispatch) into a headless squad run that opens a draft pull request. New `.github/instructions/squad/squad-watch-mode.instructions.md` defines the opt-in gates, the event-to-intent map, injection-safe payload handling (issue text is data, never instructions), profile inference (falls back to `default` when the issue is ambiguous), the draft-PR deliverable, idempotency and resume, and escalation.
- Shipped the documentation-only reference workflow `.github/skills/squad/squad-watch.workflow.yml` that runs the squad headlessly via the GitHub Copilot CLI (`copilot -p`). It wires the full event-to-intent map in one file — labeled issues, `squad/review` pull requests, `/squad` comment commands, a scheduled maintenance sweep, `workflow_dispatch`, and branch-filtered pushes — each authorized to write collaborators, fork-safe (never `pull_request_target`), with the event payload passed as data. Copy it to `.github/workflows/squad-watch.yml` to activate.
- Documented Watch Mode setup and its end-to-end flow (with a Mermaid diagram) on the Usage page.

### Changed

- Bumped `state.json` `schemaVersion` to `1.2` with an optional, backward-compatible `trigger` object recording event provenance (`source`, `ref`, `eventId`, `actor`, `receivedAt`, `runId`). Existing state stays valid; runs that were not event-triggered omit it.
- Wired the Watch Mode contract into the squad `SKILL.md` overview and the Squad Coordinator's governing conventions; the previously deferred DR-01 note in `squad-state.instructions.md` is now the active Watch Mode contract.
- Updated hve-core dependency pin to `21148ef` (21148ef1b62010e17a3d57f62f554cad340bda99).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.9.0"
```

[0.9.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.9.0

## [0.8.23] - 2026-07-08

### Changed

- Updated hve-core dependency pin to `aa49aed` (aa49aedd9e577f6808895f8f976a7eb35ea2db46).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.23"
```

[0.8.23]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.23

## [0.8.22] - 2026-07-07

### Changed

- Rewrote the `sql-migration-advisor` skill to align with the upstream interview-first playbook: source-of-truth fetch posture, core principles, ~11-question guided interview with answer lists, deterministic Step A–D scoring, clean-Markdown recommendation card, and guardrails (adapted from `fredgis/sql-migration-advisor`, MIT, with attribution retained).
- Updated `Squad SQL Migration Advisor` to load the skill and enforce a strict one-question-at-a-time interview using the skill's answer lists, withholding the recommendation card until the interview completes and tying scoring to the skill's Step A–D decision rules.

### Added

- Bundled `reference/decision-rules.md` as an offline fallback for the `sql-migration-advisor` skill so deterministic scoring works without network access.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.22"
```

[0.8.22]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.22

## [0.8.21] - 2026-07-07

### Added

- Added `Squad SQL Migration Advisor` as a dedicated advisory subagent for SQL Server-to-Azure migration planning, including schema/data migration path selection and downtime-aware cutover guidance.
- Added the `sql-migration-advisor` skill and wired SQL migration cues so modernization requests can deterministically route to the SQL advisory path.

### Changed

- Extended the `modernizer` role mapping with `Squad SQL Migration Advisor` as an alternate, and added `modernizer` to the `azure` profile roster.
- Updated squad coordinator dispatch allowlist and routing rules to recognize SQL migration keywords and send those requests through `modernizer` in confirm-mode.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.21"
```

[0.8.21]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.21

## [0.8.20] - 2026-07-07

### Changed

- Updated hve-core dependency pin to `918b0c6` (918b0c675053de622c2de4449b651f77c9bc4bd6).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.20"
```

[0.8.20]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.20

## [0.8.19] - 2026-07-07

### Added

- **Decision Ref** deep links on council and autopilot gates. Every Council Verdict entry in `decisions.md` is now addressable by a stable Markdown-heading anchor (for example `.copilot-tracking/squad/decisions.md#council-verdict-<timestamp>-<topic-id>`), and the coordinator surfaces that reference whenever it reports a verdict or opens a gate. The Scribe returns the anchor in its verdict-write confirmation, and the notification payload carries a `Decision Ref` line so a human can jump straight to the exact section of the append-only file instead of scanning for it. See `squad-council.instructions.md`, `squad-notifications.instructions.md`, `squad-autopilot.instructions.md`, `squad-scribe.agent.md`, and `squad-coordinator.agent.md`.
- Consumer docs: a "Finding the details behind a gate" section in `docs/usage.html` with a rendered Mermaid diagram showing where each gate records its details (`decisions.md`, `state.json`/history, `notifications.md`).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.19"
```

[0.8.19]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.19

## [0.8.18] - 2026-07-06

### Added

- Companion **hve-squad-mcp** server repository — a deployable Model Context Protocol (MCP) server that publishes the squad as model-invocable tools (`squad_research`, `squad_plan`, `squad_review`, `squad_architect`, `squad_run`) plus a deterministic `squad_render_pptx` file-output tool, over Streamable HTTP with Entra auth for hosts such as Copilot Studio. See [github.com/Peter-N91/hve-squad-mcp](https://github.com/Peter-N91/hve-squad-mcp).

### Changed

- Coordinating version bump that establishes the link between this package version and the companion `hve-squad-mcp` release: the MCP server pins its bundled squad cast to `hve-squad@0.8.18` (`host/cast/package-pin.json`). The hve-core dependency pin is unchanged (`c5de202`).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.18"
```

[0.8.18]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.18

## [0.8.17] - 2026-07-04

### Changed

- Updated hve-core dependency pin to `c5de202` (c5de2020ca4a28a992913d73dca2aff7a2a310bb).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.17"
```

[0.8.17]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.17

## [0.8.16] - 2026-07-03

### Changed

- Updated hve-core dependency pin to `142e528` (142e528eb0a6a59938d8e68f030fa4c8496a97a4).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.16"
```

[0.8.16]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.16

## [0.8.15] - 2026-07-02

### Changed

- Updated hve-core dependency pin to `b70237d` (b70237d08d5caf6918b9de9952a243a8588b92dc).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.15"
```

[0.8.15]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.15

## [0.8.14] - 2026-06-30

### Changed

- Updated hve-core dependency pin to `b6bb6ba` (b6bb6ba96b2a929c7e76951bd74965ff2c95b8ca).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.14"
```

[0.8.14]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.14

## [0.8.13] - 2026-06-29

### Changed

- Squad consumption ledger is now always populated. Bound the per-dispatch consumption block to the Proof-of-Dispatch gate, made the Squad Scribe self-derive a tier-default estimate when no consumption payload is supplied, hardened coordinator dispatch discipline to always pass an attribution, and added seed reconciliation so a disrupted run backfills `consumption.md` on the next turn.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.13"
```

[0.8.13]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.13

## [0.8.12] - 2026-06-28

### Changed

- Updated hve-core dependency pin to `88dc7f2` (88dc7f2922bbe1fb11b775b2d4a2c82b56ad40d3).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.12"
```

[0.8.12]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.12

## [0.8.11] - 2026-06-27

### Changed

- Updated hve-core dependency pin to `3d4dbad` (3d4dbadfd17c10e5476dfe29bb9556616de0a5e3).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.11"
```

[0.8.11]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.11

## [0.8.10] - 2026-06-26

### Changed

- Updated hve-core dependency pin to `44b42d4` (44b42d40e7bcf10ac1604c33bc9a5de4f2cc30ed).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.10"
```

[0.8.10]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.10

## [0.8.9] - 2026-06-26

Makes squad setup self-service when no built-in profile fits. At first run the coordinator now asks you to proceed with the proposed profile or choose differently; decline and you can pick another profile or build a custom roster from a described menu of every available role — so you always pick from real, deployed agents and never invent one. This release also fans out the autopilot Implement stage across owning specialists for multi-deliverable (`product`) profiles.

### Added

- **Custom roster selection at first run** — a new "Building a Custom Roster" role menu (`squad-src/.github/instructions/squad/squad-roster.instructions.md`) lists every selectable role with a plain-language description and the deployed agent that fills it, and the Squad Coordinator's Init Mode offers it whenever you decline the proposed profile (`squad-src/.github/agents/squad/squad-coordinator.agent.md`, mirrored in `squad-src/.github/skills/squad/SKILL.md`). A custom roster always keeps `scribe`, recommends the methodology spine, flags any role whose agent is not installed, and never invents a role or agent outside the cast catalog.
- **Autopilot deliverable fan-out** (#33) — for profiles that carry two or more deliverable-producing roles (the `product` profile), the autopilot Implement stage now enumerates the requested deliverables and dispatches each owning specialist instead of a single `developer`; spine-shaped profiles keep the unchanged single-developer build (`squad-src/.github/instructions/squad/squad-autopilot.instructions.md`, `squad-src/.github/instructions/squad/squad-roster.instructions.md`, `squad-src/.github/agents/squad/squad-coordinator.agent.md`, `squad-src/.github/skills/squad/SKILL.md`).

### Changed

- Init Mode's "propose" step is now an explicit **proceed-or-decline** decision: proceeding keeps the existing flow, while declining leads to either a different profile (each shown with its one-line description) or a custom roster. Adjusting a profile is recorded as a custom roster derived from it, since any change to a profile's exact member set makes it custom (`squad-src/.github/agents/squad/squad-coordinator.agent.md`, `squad-src/.github/instructions/squad/squad-roster.instructions.md`).
- Documented the first-run custom-roster option on the Usage page (`docs/usage.html`).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.9"
```

[0.8.9]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.9


## [0.8.8] - 2026-06-25

Adds automatic PowerPoint branding so generated decks follow your own template without any manual setup. A new shipped instruction makes the PowerPoint Builder use your branded `.pptx` for every deck, and when no template is present it asks for one and offers to save it — so a non-technical user never copies a file, edits a config, or restates the template on each request.

### Added

- Brand-template instruction (`squad-src/.github/instructions/squad/pptx-brand-template.instructions.md`), shipped as package content that auto-applies on install: the PowerPoint Builder uses the project's branded template at `.github/brand/pptx-brand-template.pptx` as `--template` for full rebuilds and `--source` for partial rebuilds, and when the template is missing it asks the user and offers to save the one they provide rather than producing a plain deck.
- "Bring your own PowerPoint template" docs page (`docs/ppt-templates.html`), wired into the docs navigation across the site, covering template preparation, the storage convention, the automatic behavior, and the validation loop.

### Changed

- Registered the brand-template instruction in `apm.yml` so it deploys to every consumer on install.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.8"
```

[0.8.8]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.8


## [0.8.7] - 2026-06-23

Adds cross-consumer self-learning: a durable learning discovered in one consumer can be sanitized, reviewed, and shipped as versioned package content that every consumer receives on the next sync, with a parallel tenant-internal path for learnings that must stay inside one organization. A new `/squad-learn` command drafts a sanitized candidate from local squad memory and opens the promotion pull request.

### Added

- `/squad-learn` command (`squad-src/.github/prompts/squad/squad-learn.prompt.md`): discovers candidate learnings from consumer-local memory, sanitizes them, lets you choose the `upstream` (cross-consumer) or `tenant` (organization-internal) target, and opens the promotion pull request behind an explicit impactful-action gate.
- Curated shared-learnings playbook (`squad-src/.github/skills/squad/learnings/shared-learnings.md`), shipped as versioned package content that the coordinator reads as read-only, authoritative context after consumer-local memory.
- Contribution governance: `CONTRIBUTING.md` with the learnings-promotion process and sanitization checklist, plus the sanitization checklist added to `.github/pull_request_template.md`.
- Tenant-internal C1 scaffold (`docs/templates/tenant-squad-learnings/`): a copyable private-repository template using a separate `squad-learnings-tenant` skill folder that deploys to a non-colliding path, with the `docs/templates/shared-learnings.md` reference describing both promotion options.
- Contributing site page (`docs/contributing.html`) wired into the docs navigation across the site.

### Changed

- The squad operating procedure now consults the shipped shared-learnings playbook and the optional tenant playbook as read-only context (`squad-src/.github/skills/squad/SKILL.md`, `squad-src/.github/instructions/squad/squad-state.instructions.md`).
- The Squad Scribe may surface a sanitized promotion candidate and point to the `/squad-learn` command and the `CONTRIBUTING.md` promotion paths, while still never writing outside consumer-local memory (`squad-src/.github/agents/squad/squad-scribe.agent.md`).
- Documented the `/squad-learn` command on the Usage page (`docs/usage.html`).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.7"
```

[0.8.7]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.7


## [0.8.6] - 2026-06-22

Adds a `product` squad profile and a non-technical Product Squad demo, so the squad can run business discovery and delivery — requirements, design thinking, roadmap, validation, and stakeholder deliverables — through the same Research → Plan → Implement → Review methodology, not just technical work.

### Added

- `product` squad profile (`squad-src/.github/instructions/squad/squad-roster.instructions.md`, mirrored in `squad-src/.github/skills/squad/SKILL.md` and `docs/usage.html`): seeds the methodology spine plus `analyst`, `designer`, `product-owner`, `presenter`, `technical-writer`, and `experimenter`, with a Profile Selection discovery signal for requirements/roadmap/discovery repositories.
- Business routing rows (`squad-src/.github/instructions/squad/squad-routing.instructions.md`) mapping requirements/BRD/PRD, journey-map/design-thinking, roadmap/backlog, experiment/MVE, presentation/deck, and document intents to the PRD Builder, DT Coach, Agile Coach, Experiment Designer, PowerPoint Builder, and Doc Ops agents.
- Demo 2 — Product Squad (`docs/demo-2.html`): a non-technical, no-cloud/no-spend walkthrough (discovery → BRD → roadmap and backlog → validation experiment → readiness review → executive deck) plus a say-it-once `mode=autopilot` version, wired into the demo chevron selector.

### Changed

- The Squad Coordinator dispatch allowlist now includes the product-profile business agents (PRD Builder, BRD Builder, Meeting Analyst, Product Manager Advisor, DT Coach, Agile Coach, GitHub Backlog Manager, Experiment Designer, PowerPoint Builder, PowerPoint Subagent, Doc Ops), and `product` is added to the `profile=` enumerations (`squad-src/.github/agents/squad/squad-coordinator.agent.md`, `squad-src/.github/prompts/squad/squad.prompt.md`).
- The home page demo card now points to both the Azure and the Product squad walkthroughs (`docs/index.html`).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.6"
```

[0.8.6]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.6


## [0.8.5] - 2026-06-22

Adds per-run consumption tracking so a squad run estimates its model cost and AI-credit usage, and hardens the Azure-icon diagram path with copy-don't-reauthor and verified-node-class guardrails.

### Added

- Consumption tracking across the squad. The Squad Scribe gains a Write Consumption step that records a per-dispatch consumption block in `history/<agent>.md` (append-only), rewrites the aggregated `consumption.md` member/model/credit ledger with a manual-baseline cost-comparison line, and updates the new `state.json` `currentRun` totals (`squad-src/.github/agents/squad/squad-scribe.agent.md`, `squad-src/.github/instructions/squad/squad-state.instructions.md`, `squad-src/.github/skills/squad/SKILL.md`).
- `consumption-rates.md`, a single maintainable per-model token-rate table (USD per 1M tokens) plus the comparison methodology, seeded from a template on first run and isolating volatile pricing from agent logic (`squad-src/.github/skills/squad/SKILL.md`).
- Azure-icon diagram render troubleshooting on the docs site (`docs/troubleshooting.html`): the Microsoft Store `python` stub, Graphviz off PATH, the `uv run --with diagrams` path, and the `verify_installation.py` check.

### Changed

- Updated hve-core dependency pin to `b69e34a` (b69e34ac38b39bd3b20bf80fa142c8ca3a3b29ed).
- The Squad Coordinator now records the dispatched model (or its tier when unknown) and an estimated-token consumption payload through the Scribe, keeping cost-first model selection visible in the ledger (`squad-src/.github/agents/squad/squad-coordinator.agent.md`).
- The roster clarifies that `Model Tier` records a preference, not the model that actually ran; the concrete model is captured per dispatch in the consumption block (`squad-src/.github/instructions/squad/squad-roster.instructions.md`).
- The Squad Azure Architect and the `python-diagrams` skill now require copying the bundled `diagram_io.py` and a `templates/` generator verbatim, verifying every `diagrams.azure.*` node class exists before use, and modeling external actors as real nodes rather than bare strings (`squad-src/.github/agents/squad/squad-azure-architect.agent.md`, `squad-src/.github/skills/python-diagrams/SKILL.md`).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.5"
```

[0.8.5]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.5


## [0.8.4] - 2026-06-19

Adds a Python `diagrams` skill for committed Azure-icon architecture diagrams and a docs Demo page, and removes third-party accelerator references.

### Added

- `python-diagrams` skill (`squad-src/.github/skills/python-diagrams/`): renders committed Azure-icon HLD/LLD diagrams with the Python `diagrams` library on a Graphviz backend, emitting paired PNG + SVG via a shared `diagram_io` output helper. Ships an `azure-webapp-lld` template, a `requirements.txt`, and a `verify_installation.py` check, and is registered in `apm.yml` dependencies.
- Docs Demo page (`docs/demo.html`) with a multi-demo chevron selector and a `Demo` entry added to the navigation across the docs site. Includes an Optional Azure-icon architecture diagrams section documenting the `uv` + Graphviz prerequisite and the one-clause `/squad` trigger.

### Changed

- Squad Azure Architect (`squad-src/.github/agents/squad/squad-azure-architect.agent.md`): the diagram-rendering step now follows a three-tier ladder — draw.io MCP when configured, the `python-diagrams` skill for a committed icon image, then Mermaid as the always-available fallback.
- Demo doc `/squad` requests updated to the real tested workload (frontend + backend web apps, VNet/subnets, private endpoints, under $60, containerization left to the squad) for the autopilot one-request version and the Beat 1 (cost) and Beat 2 (architecture) examples.

### Removed

- All references to the third-party APEX accelerator across the changelog, the MCP reference template (`mcp.template.json`), the capability map (`squad-mcp-capability.instructions.md`), and the `azure-scaffold` skill.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.4"
```

[0.8.4]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.4


## [0.8.3] - 2026-06-19

### Changed

- Updated hve-core dependency pin to `b98f527` (b98f527e7b3565c1a9f1d50eba899b1588c41bcc).

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.3"
```

[0.8.3]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.3


## [0.8.2] - 2026-06-18

Fork-specific release. No functional changes to squad content relative to upstream `Peter-N91/hve-squad@v0.8.1`.

### Changed

- Automated sync workflow (`sync-hve-core.yml`): all `microsoft/hve-core` content is now referenced directly from `microsoft/hve-core` at a pinned commit SHA. On each run the workflow fetches the latest `microsoft/hve-core` commit, regenerates `apm.yml` deps, bumps the patch version, updates this changelog, commits, and dispatches `release.yml`.
- Sync and release responsibilities split: `sync-hve-core.yml` owns the apm.yml bump and commit; `release.yml` only tags the version currently on `main` and publishes the GitHub Release (with an optional `version` input for manual bumps). Squad self-references stay pinned to upstream `Peter-N91/hve-squad` (the script default) so a fork's automation never rewrites them to its own slug.

### Consumer install

```powershell
apm install "Peter-N91/hve-squad#v0.8.2"

```

[0.8.2]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.2

## [0.8.1] - 2026-06-17

Guarantees the HVE Core delivery methodology — Research → Plan → Implement → Review — runs in every squad profile, not just the general-purpose ones. Adds a universal methodology spine to all profiles and a post-implementation review step, and lets the Squad Coordinator dispatch the three Azure-track roles that `0.8.0` shipped but left out of the coordinator's dispatch allowlist.

### Fixed

- The Squad Coordinator can now dispatch `Squad As-Built Author`, `Squad Azure Diagnose`, and `Squad Modernization Planner` (`squad-src/.github/agents/squad/squad-coordinator.agent.md`). `0.8.0` deployed these agent files and registered them in the roster, but the coordinator's `agents:` allowlist omitted them, so the as-built, diagnose, and modernization beats could not run.
- Specialized profiles no longer skip legs of the methodology. The `security`, `design`, `architecture`, and `azure` profiles previously omitted one or more of `researcher`, `lead`, `developer`, and `tester`, so the routing Implementation Gate escalated (a required role was absent from the roster) instead of running Research → Plan → Implement. Every profile now carries the full spine (`squad-src/.github/instructions/squad/squad-roster.instructions.md`, mirrored in `squad-src/.github/skills/squad/SKILL.md`).

### Added

- Methodology spine in the roster and skill: `researcher`, `lead`, `developer`, and `tester` are now always-included members of every profile (alongside `scribe`), documented as the four roles that run Research → Plan → Implement → Review (`squad-src/.github/instructions/squad/squad-roster.instructions.md`, `squad-src/.github/skills/squad/SKILL.md`).
- A `Review Follow-Through` rule in the routing conventions (`squad-src/.github/instructions/squad/squad-routing.instructions.md`): after any implementation-tier role lands a change, the coordinator dispatches `tester` (review) as the closing stage in every mode, making the gate symmetric — research and plan precede implementation, review follows it.

### Changed

- `docs/usage.html` Profiles table updated so every profile lists its methodology-spine members, with a note that every profile runs Research → Plan → Implement → Review.
- `apm.yml` package version bumped to `0.8.1`. The dependency entries are unchanged from `0.8.0` (the edited squad files keep the same paths), so the pinned hve-core commit from `0.7.0`/`0.8.0` is preserved.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.1"
```

[0.8.1]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.1

## [0.8.0] - 2026-06-17

Adds live Azure governance discovery, post-deployment as-built documentation, and resource-level triage and diagnosis to the Azure squad: all delivered as two new read-only squad roles backed by the official `@azure/mcp` server, with named non-MCP fallbacks so a missing server never blocks the squad.

### Added

- `Squad As-Built Author` agent (`squad-src/.github/agents/squad/squad-asbuilt-author.agent.md`): a read-only post-deploy role that inventories deployed Azure resources via the `azure-resource` capability (`@azure/mcp` Resource Graph KQL preferred, `az` CLI / Resource Manager REST fallback), builds a compliance matrix from Azure Policy state, and drafts an operations runbook and backup/DR plan for Doc Ops to publish. Never deploys, mutates resources, or authors IaC.
- `Squad Azure Diagnose` agent (`squad-src/.github/agents/squad/squad-azure-diagnose.agent.md`): a strictly read-only Azure troubleshooting role that queries Resource Health, Azure Monitor/Log Analytics KQL, and Resource Graph to correlate ranked hypotheses and recommend (never apply) remediations. Defers every change to the gated Squad Deployer or Squad IaC Author.
- `azure-resource` MCP capability row in the capability map (`squad-src/.github/instructions/squad/squad-mcp-capability.instructions.md`): maps the new `azure-resource` capability to `@azure/mcp` with a named `az` CLI / Resource Graph REST fallback, following the existing graceful-degradation contract.
- Official `@azure/mcp` server wired into the MCP reference template (`squad-src/.github/skills/squad/mcp.template.json`): stdio entry invoking `@azure/mcp@latest server start`, authenticated via `DefaultAzureCredential` / `az login` with no stored secrets. A community Azure pricing MCP recommendation replaces the prior placeholder (primary: `msftnadavbh/AzurePricingMCP`), with a labeled WI-02 placeholder for the unverified exact stdio invocation.
- Read-only Azure Policy precheck on the Squad Deployer (`squad-src/.github/agents/squad/squad-deployer.agent.md`): a new step between the what-if/plan dry-run and the Impactful-Action Gate that queries effective Azure Policy assignments and compliance for the target scope, surfacing predicted denials before approval. The gate semantics, `confirm` tier, and Mandatory Escalation Triggers are unchanged.
- `.vscode/mcp.json` entry in the azure-scaffold bundled templates and opt-in scaffolding flow (`squad-src/.github/skills/azure-scaffold/SKILL.md`): consumers can merge the squad MCP template into their workspace on request; the turnkey-via-scaffolding posture is documented in the skill overview. The APM package itself never writes consumer `.vscode/` or `.devcontainer/` trees.
- Roster, routing, and profile wiring for both new roles (`squad-src/.github/instructions/squad/squad-roster.instructions.md`, `squad-routing.instructions.md`, `squad-src/.github/skills/squad/SKILL.md`): `asbuilt-author` at `confirm` tier (non-parallel), `azure-diagnose` at `auto` tier (parallel-eligible); both registered in the `azure` and `full` squad profiles. Pre-existing SKILL-vs-roster profile mirror drift for `iac-author`, `deployer`, and `modernizer` reconciled in the same edit.

### Changed

- `apm.yml` dependency list updated: two new squad agent files added (`squad-asbuilt-author.agent.md`, `squad-azure-diagnose.agent.md`) and the package version bumped to `0.8.0`.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.8.0"
```

[0.8.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.8.0

## [0.7.0] - 2026-06-16

Makes installs reproducible by pinning every dependency to an immutable ref, so a published version keeps resolving the same files even after `microsoft/hve-core` changes its default branch. This fixes transitive installs of `0.6.0`, which broke when hve-core consolidated several instruction files on `main`.

### Fixed

- Transitive installs no longer break on hve-core drift. Previously the `dependencies.apm` entries for `microsoft/hve-core` were unpinned (bare paths), so any consumer re-resolved them against hve-core's moving `main`; once hve-core consolidated 13 instruction files, those paths 404'd and the install failed. Every hve-core entry is now pinned to a commit SHA, and the squad self-references are pinned to the release tag.

### Changed

- `scripts/Update-ApmDependencies.ps1` now pins generated dependencies: each `microsoft/hve-core` entry is suffixed with `#<commit-sha>` (the `-Ref` value resolved to a concrete commit), and a new optional `-SquadRef` parameter pins the `Peter-N91/hve-squad` self-references with `#<ref>` (use the release tag you are cutting). Repository discovery switched from `git clone --branch` to `git init` + `git fetch` so `-Ref` can be a branch, tag, or commit SHA.
- `apm.yml` dependency list regenerated against hve-core `main` (commit `a847cfa3b82d7c09d707d5e3d978780ad1d599d3`), with squad self-references pinned to `v0.7.0`, and the package version bumped to `0.7.0`.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.7.0"
```

[0.7.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.7.0

## [0.6.0] - 2026-06-15

Adds a modernization capability to the squad: a single `modernizer` role, reachable from the one `/squad` entry point, that plans same-stack framework and dependency upgrades and cross-stack re-platforms (for example, Node.js to .NET or React to Angular), then routes execution to the squad developer role or Microsoft's official App Modernization tooling.

### Added

- Squad Modernization Planner agent (`squad-src/.github/agents/squad/squad-modernization-planner.agent.md`): a markdown-only planning charter that classifies the modernization request, delegates current-state code scans to the Researcher Subagent, defines a target state and a phased plan, and recommends the execution engine — the `developer` role for scoped edits or the official GitHub Copilot App Modernization extension and CLI for large batch upgrades. It plans only; it never edits source and never deploys.
- Cross-stack re-platform mode in the same charter: a self-contained mode for rewrites across languages or frameworks that captures a behavior contract for the current system, sequences an incremental (strangler-fig) rewrite, routes execution to the `developer` and `architect` roles under mandatory council review, and never recommends the official upgrade tooling (which upgrades within a stack and cannot perform a cross-stack rewrite). The same-stack modes are unchanged.
- `modernizer` role in the roster cast catalog and the `full` profile (`squad-src/.github/instructions/squad/squad-roster.instructions.md`, mirrored in `squad-src/.github/skills/squad/SKILL.md`), plus same-stack and re-platform routing rows (`squad-src/.github/instructions/squad/squad-routing.instructions.md`).
- Documentation: a Modernization card on the home page and a Modernization section in Usage (`docs/index.html`, `docs/usage.html`).

### Changed

- Squad Coordinator dependency registration: `apm.yml` registers the new Squad Modernization Planner agent, and `apm.lock.yaml` was refreshed.
- README and home-page install pins bumped from `v0.5.0` to `v0.6.0` (`README.md`, `docs/index.html`), and the package version in `apm.yml` bumped to `0.6.0`.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.6.0"
```

[0.6.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.6.0

## [0.5.0] - 2026-06-15

Adds an Azure execution layer so any repo that installs hve-squad can author IaC, deploy to Azure, and govern infrastructure the package way — through documentation-only reference templates plus two new squad agents — and hardens the squad methodology so the coordinator always dispatches the mapped HVE Core agents and builds the squad before doing work.

### Added

- `azure-scaffold` skill (`squad-src/.github/skills/azure-scaffold/`): documentation-only reference templates a consumer-facing agent scaffolds into a consumer repo — a dev container (Azure CLI + Bicep, Terraform + TFLint, `gh`, Node, Python), `azure/login@v2` OIDC deploy workflows for Bicep and Terraform, a `Setup-AzureOidc.ps1` wizard (Entra app registration, OIDC federated credentials, RBAC, GitHub secrets), a read-only `Get-PolicyBaseline.ps1` plus a scheduled governance-baseline workflow, and the `infra/bicep/{project}` / `infra/terraform/{project}` convention. Nothing runs from the package; activation is an explicit copy-and-commit, and authentication is OIDC (no stored secrets).
- Squad IaC Author agent (`squad-src/.github/agents/squad/squad-iac-author.agent.md`): converts the Squad Azure Architect's LLD table into Bicep or Terraform under `infra/{track}/{project}` with AVM modules, scaffolds the `azure-scaffold` templates, validates statically, and hands off to cost and deploy — never deploys.
- Squad Deployer agent (`squad-src/.github/agents/squad/squad-deployer.agent.md`): runs Azure deployments in the consumer's environment, defaulting to a read-only `what-if`/`plan` and gating every `create`/`apply` behind the Impactful-Action Gate.
- Optional `azure-pricing` MCP entry in `squad-src/.github/skills/squad/mcp.template.json`, with the anonymous Azure Retail Prices REST fallback documented for the Squad Cost Manager.
- `azure` squad profile and the `iac-author` and `deployer` roles in the roster cast catalog (`squad-src/.github/instructions/squad/squad-roster.instructions.md`), plus IaC-authoring and deployment routing rows (`squad-src/.github/instructions/squad/squad-routing.instructions.md`).
- Documentation: an Azure execution layer card on the home page and an Azure execution layer / scaffolding-flow section in Usage and Getting Started (`docs/index.html`, `docs/usage.html`, `docs/getting-started.html`).

### Changed

- Methodology enforcement (the coordinator must use the mapped HVE Core agents): added a non-negotiable Dispatch Discipline section to the Squad Coordinator (`squad-src/.github/agents/squad/squad-coordinator.agent.md`) forbidding inline work, artifact-gate preconditions to the routing Implementation Gate (`squad-src/.github/instructions/squad/squad-routing.instructions.md`) and the autopilot pipeline (`squad-src/.github/instructions/squad/squad-autopilot.instructions.md`), a hard council-quorum stop (`squad-src/.github/instructions/squad/squad-council.instructions.md`), a no-self-fill rule for absent roles (`squad-src/.github/instructions/squad/squad-roster.instructions.md`), and a proof-of-dispatch rule keyed to `history/<agent>.md` (`squad-src/.github/instructions/squad/squad-state.instructions.md`).
- Autopilot now treats Init Mode (building and confirming the squad) as a precondition it never skips, in both the Squad Coordinator and the autopilot Pipeline Contract.
- Squad Coordinator `agents:` frontmatter registers the new Squad IaC Author and Squad Deployer agents, and `apm.yml` registers both agents and the `azure-scaffold` skill.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.5.0"
```

[0.5.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.5.0

## [0.4.1] - 2026-06-12

Adds a GitHub Pages documentation site so consumers and maintainers get a navigable how-to reference instead of one large README, and trims the README to a short landing page that links to it.

### Added

- Documentation site under `docs/`: a custom static site (landing page plus Getting Started, Usage, Maintaining, and Troubleshooting pages) with a shared dark theme in `docs/assets/style.css` and a `docs/.nojekyll` marker.
- GitHub Pages deploy workflow (`.github/workflows/docs.yml`): publishes `docs/` via GitHub Actions on every push to `main` that touches `docs/`, with SHA-pinned actions, least-privilege permissions, and `persist-credentials: false`.

### Changed

- README trimmed to a short landing page that links to the documentation site and retains quick start, repository structure, and versioning.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.4.1"
```

[0.4.1]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.4.1

## [0.4.0] - 2026-06-12

Adds two new autonomy modes — a full `mode=autopilot` pipeline and a remote, phone-approvable notification channel — so the squad can run unattended (for example, a multi-hour job on a VM) and stop for a human only at impactful actions and final-outcome validation.

### Added

- Autopilot mode instructions (`squad-src/.github/instructions/squad/squad-autopilot.instructions.md`): opt-in `mode=autopilot` that sequences research → plan → council → implement → review → final-outcome validation end-to-end, with two narrow Human Gates (Impactful-Action and Risk) and a no-auto-release rule.
- Notification + remote-approval instructions (`squad-src/.github/instructions/squad/squad-notifications.instructions.md`): build-time approval-channel capture, three adapters (`github-issue`, `webhook`, `in-chat`), the GitHub-issue approval protocol (`/approve`, `/approve-all`, `/changes:`, `/stop`), authorization and prompt-injection guards, and the append-only `notifications.md` log.
- GitHub approval-watcher reference workflow (`squad-src/.github/skills/squad/github-approval-watcher.workflow.yml`): documentation-only `issue_comment`/label watcher that relays an authorized human decision so an unattended run resumes; performs no impactful action itself.
- `github-issue` row in the MCP capability map (`squad-src/.github/instructions/squad/squad-mcp-capability.instructions.md`) with the `github` MCP → `gh` CLI → in-chat fallback chain, and an optional `github` server entry in `squad-src/.github/skills/squad/mcp.template.json`.
- README: Autonomy modes table, remote approval (unattended/VM) guidance, and a one-time remote-approval setup section.

### Changed

- Squad Coordinator (`squad-src/.github/agents/squad/squad-coordinator.agent.md`): Init Mode now captures an optional approval channel (defaulting to `in-chat` so local, at-the-PC runs are unaffected) and the agent gained Autopilot Mode orchestration plus the new `mode` input.
- Squad prompt (`squad-src/.github/prompts/squad/squad.prompt.md`): `mode` input accepts `autonomous|autopilot` and routes to the matching contract.
- Squad state conventions and `state.json` seed (`squad-src/.github/instructions/squad/squad-state.instructions.md`, `squad-src/.github/skills/squad/SKILL.md`): added the `notify` object (`approvalChannel`, `enabled`, `email`, `github`), the `mode` field, the `notifications.md` and `autopilot-run-<id>.md` files, and the `squad_notify` verb.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.4.0"
```

[0.4.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.4.0

## [0.3.0] - 2026-06-11

Adds capability-aware MCP routing for dispatched squad roles, a reference Azure DevOps MCP template, two new specialist agents, a model-pin convention for mechanical roles, and the DD-07 source-tree recovery that lets `apm install` resolve the squad package end-to-end.

### Added

- Squad MCP capability instructions (`squad-src/.github/instructions/squad/squad-mcp-capability.instructions.md`): Capability Map, Capability Hint Contract, Graceful Degradation, Out-of-Band Fallbacks, and Consumer Override sections so dispatched roles can prefer an MCP when present and fall back to a named non-MCP default without blocking.
- Reference Azure DevOps MCP template (`squad-src/.github/skills/squad/mcp.template.json`): documentation-only JSONC sample for the official `@azure-devops/mcp` server with managed Entra OAuth via VS Code `inputs`. The package never writes the consumer's `.vscode/mcp.json`.
- Squad Azure Architect agent (`squad-src/.github/agents/squad/squad-azure-architect.agent.md`): dispatched role for Azure architecture questions with the `architecture-docs` capability hint and a `learn.microsoft.com` fallback.
- Squad Cost Manager agent (`squad-src/.github/agents/squad/squad-cost-manager.agent.md`): dispatched role for Azure pricing questions with the `Azure-pricing` capability hint and an Azure Retail Prices REST fallback.

### Changed

- Pinned the mechanical-tier squad agents (`squad-src/.github/agents/squad/squad-scribe.agent.md`, `squad-src/.github/agents/squad/squad-cost-manager.agent.md`) to the Tier 1 model list (`Claude Haiku 4.5 (copilot)`, `GPT-5.4 mini (copilot)`) so routine state writes and lookups run on the cheapest capable models.
- Relocated the MCP reference template from `squad-src/.vscode/mcp.template.json` to `squad-src/.github/skills/squad/mcp.template.json`. The APM virtual-path validator rejects any path whose final segment begins with a dot, which blocked the previous `.vscode/` shipping location; the new path ships under the existing squad skill APM directory package.
- Reverted the now-unused `SquadDirectoryRoots` scaffold from `scripts/Update-ApmDependencies.ps1` and removed the corresponding `.vscode` virtual-path entry from `apm.yml`.
- Refreshed `apm.lock.yaml` against the latest `main` commit so the squad-src entries resolve to the merged squad capability upgrade.
- README install pins bumped from `v0.2.0` to `v0.3.0`.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.3.0"
```

[0.3.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.3.0

## [0.2.0] - 2026-06-10

Adds a locally authored "squad" alongside the bundled HVE Core content.

### Added

- Squad Coordinator agent (`squad-src/.github/agents/squad/squad-coordinator.agent.md`): a user-invocable orchestrator that classifies a request, routes it to a cast of deployed HVE Core agents in parallel, and synthesizes the response.
- Squad Scribe agent (`squad-src/.github/agents/squad/squad-scribe.agent.md`): the single writer of squad state, ensuring parallel dispatch cannot race on shared files.
- `/squad` prompt (`squad-src/.github/prompts/squad/squad.prompt.md`) to hand a request to the Squad Coordinator with optional `profile` and `tier` hints.
- `squad` skill (`squad-src/.github/skills/squad/`) packaging the coordinator's operating procedure and seed templates.
- Three squad instruction files (`squad-roster`, `squad-routing`, `squad-state`) that auto-apply when squad state under `.copilot-tracking/squad/**` is touched.
- Squad profiles (`default`, `full`, `security`, `design`, `architecture`) so consumers can seed the cast that fits their project on first run.
- `scripts/Update-ApmDependencies.ps1` now enumerates the local squad source and emits squad entries as remote virtual paths, with `-SquadSourceRoot` and `-SquadRepoSlug` parameters.
- Squad virtual-path entries appended to `dependencies.apm` in `apm.yml`.
- README guidance for consumers on installing the package, running the squad, and building it.

### Changed

- `apm.lock.yaml` regenerated to reflect the current dependency set.
- `.gitignore` updated to keep the authored `squad-src/` tree tracked while ignoring deployed assets.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.2.0"
```

[0.2.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.2.0

## [0.1.0] - 2026-06-10

Initial release of the `hve-squad` APM package.

### Added

- Curated APM package that bundles HVE Core agents, prompts, instructions, and skills for Copilot target environments.
- Auto-generated `dependencies.apm` list in `apm.yml` covering supported markdown artifacts from selected `microsoft/hve-core` folders (`.github/agents`, `.github/instructions`, `.github/prompts`, `.github/skills`).
- `scripts/Update-ApmDependencies.ps1` dependency generator.
- `sync-deps` and `install-sync` APM scripts for the maintainer workflow.
- `apm.lock.yaml` resolved dependency lock file for reproducible installs.
- README documenting maintainer and consumer workflows, including direct install from the public repository.

### Consumer install

Pin to this version:

```powershell
apm install "Peter-N91/hve-squad#v0.1.0"
```

[0.1.0]: https://github.com/Peter-N91/hve-squad/releases/tag/v0.1.0
