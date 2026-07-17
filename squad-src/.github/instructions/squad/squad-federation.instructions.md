---
description: "Squad federation layout: opt-in sub-squads under one repo, the parameterized squad root, the federation registry and meta-routing schemas, detection precedence, and two-level single-writer state"
applyTo: '**/.copilot-tracking/squad/**'
---

# Squad Federation Conventions

These conventions define **federation**: running several named sub-squads under one hub so a single repository can host more than one squad — for example, a business team's `product` sub-squad and an architecture team's `azure` sub-squad, side by side. Federation is **opt-in and additive**. A repository that never opts in keeps exactly today's single-squad behavior.

Federation reuses every existing squad mechanism unchanged. Each sub-squad is an ordinary squad — same roster, routing, decisions, history, consumption, and single-writer Scribe discipline — only rooted at a named path instead of the top-level `.copilot-tracking/squad/`. The only new pieces are a **parameterized state root** and a thin **meta layer** (a registry, a meta-routing table, and the Squad Federation Coordinator) that classifies a request to one or more sub-squads and runs each scoped to its own root.

Routing across sub-squads is decided here and in `meta-routing.md`; routing *within* a sub-squad is unchanged (`squad-routing.instructions.md`). Roster and persistence rules are unchanged (`squad-roster.instructions.md`, `squad-state.instructions.md`).

## Squad Root (`squadRoot`)

A squad's state lives under a **squad root**. The root is parameterized:

* The default squad root is `.copilot-tracking/squad/`. Every state path in `squad-state.instructions.md` (`team.md`, `routing.md`, `decisions.md`, `history/<agent>.md`, `state.json`, `consumption.md`, and the rest) is `<squadRoot>/...`, and the default keeps today's literal paths.
* In a federation, each sub-squad roots at `.copilot-tracking/squad/members/<name>/`, where `<name>` is the sub-squad's registered name (lower-kebab-case). That directory holds the sub-squad's full standard state tree.
* The Squad Coordinator and the Squad Scribe accept an optional `squadRoot`; when omitted, the default preserves single-squad behavior. The Squad Federation Coordinator sets `squadRoot=.copilot-tracking/squad/members/<name>/` when it drives a sub-squad.

Because every squad instruction file's `applyTo` is `**/.copilot-tracking/squad/**`, all conventions auto-apply at any depth, so a sub-squad tree under `members/<name>/` inherits the roster, routing, and state rules without any `applyTo` change.

## Federation State Layout

A federation adds a small meta layer at the federation root (`.copilot-tracking/squad/`) and nests each sub-squad under `members/<name>/`:

| Path                                   | Purpose                                                                     | Write Semantics    |
|----------------------------------------|-----------------------------------------------------------------------------|--------------------|
| `federation.md`                        | Registry of sub-squads (name, profile, kind, location, owner, description)   | Replace via scribe |
| `meta-routing.md`                      | Request pattern / domain → sub-squad routing table                          | Replace via scribe |
| `decisions.md`                         | Federation-level cross-squad routing decisions and rationale                | Append-only        |
| `history/<sub-squad>.md`               | Per-sub-squad federation dispatch history (which sub-squad ran, for what)   | Append-only        |
| `history/autopilot-run-<id>.md`        | Federation autopilot meta-run summary linking each sub-squad's inner run     | Append-only        |
| `state.json`                           | Federation status: active sub-squads, mode, current-run cost, open escalations | Replace via scribe |
| `members/<name>/`                      | A full ordinary squad state tree (the sub-squad's `squadRoot`)              | Per squad-state    |

Each `members/<name>/` directory is an unmodified squad: `team.md`, `routing.md`, `decisions.md`, `notifications.md`, `history/<agent>.md`, `state.json`, `consumption.md`, and `consumption-rates.md`, all governed by `squad-state.instructions.md` rooted at `members/<name>/`.

The federation root's `decisions.md` and `history/<sub-squad>.md` are **append-only**; `federation.md`, `meta-routing.md`, and the federation `state.json` use **replace** semantics — mirroring the per-squad rules one level up. The federation `history/autopilot-run-<id>.md` is **append-only by topic-id** and is written only for a federation-level autopilot meta-run; see `.github/instructions/squad/squad-federation-autopilot.instructions.md`. The federation `state.json` carries additive `mode` and `currentRun` fields for that meta-run (the autonomy mode in effect and the cost aggregated across every sub-squad inner run); both are backward-compatible, so a federation that never runs autopilot omits or zeroes them and existing state stays valid.

## Detection Precedence

The Squad Coordinator resolves what kind of squad a project has at the start of a turn, checking `.copilot-tracking/squad/` in this order:

1. **`federation.md` present** → **federation mode**. The Squad Federation Coordinator owns the turn: it reads the registry and meta-routing, selects the target sub-squad(s), and runs each scoped to `members/<name>/`. When the Squad Coordinator itself is invoked with an explicit `squadRoot`, it operates directly against that sub-squad root.
2. **No `federation.md`, but `team.md` present** → **plain single-squad mode**. Behavior is exactly today's: the Squad Coordinator runs the six-step protocol against `.copilot-tracking/squad/`.
3. **Neither present** → **Init Mode**. The user is offered a plain squad (the default) or a federation of named sub-squads.

`federation.md` at the top level versus `team.md` at the top level is the single discriminator between a federation and a plain squad. The two are mutually exclusive at the federation root: a federation keeps `team.md` only inside each `members/<name>/`, never at the top.

## Registry Schema (`federation.md`)

The registry is the durable list of sub-squads the Federation Coordinator can route to. It begins with YAML frontmatter and a single H1, then a `## Sub-Squads` table:

| Column      | Meaning                                                                                              |
|-------------|------------------------------------------------------------------------------------------------------|
| Sub-squad   | Unique name, lower-kebab-case (for example, `product`, `azure`); also the `members/<name>/` directory |
| Profile     | The profile the sub-squad was seeded from (`default`, `full`, `security`, `design`, `architecture`, `azure`, `product`) or `custom` |
| Kind        | `in-repo` (state under `members/<name>/`) — `repo` is reserved for the deferred multi-repo federation |
| Location    | `members/<name>/` for an `in-repo` sub-squad                                                          |
| Owner       | Optional human or team label (for example, `business-team`, `architects`)                            |
| Description | One-line purpose the meta-routing table uses to choose this sub-squad                                 |

`Kind=repo` and external `Location` values are defined by the deferred multi-repo plan and are not seeded by the in-repo flow.

### Registry Example

```markdown
## Sub-Squads

| Sub-squad | Profile | Kind    | Location          | Owner         | Description                                              |
|-----------|---------|---------|-------------------|---------------|---------------------------------------------------------|
| product   | product | in-repo | members/product/  | business-team | Requirements, roadmap, and stakeholder deliverables     |
| azure     | azure   | in-repo | members/azure/    | architects    | Azure build: Bicep, landing-zone, cost, and deployment  |
```

### Sub-Squad Naming and Uniqueness

Every sub-squad has a **required, unique name** because the name is simultaneously the registry key, the `members/<name>/` state directory, and the `squad=<name>` selector the user types to target it. A collision would make two sub-squads share one folder and one selector, so names are validated before any folder is created.

* **Required.** No sub-squad may be nameless — including a custom sub-squad the user builds from a role menu. When the user proposes a custom sub-squad without naming it, the coordinator asks for a name before creating it.
* **Format.** Lower-kebab-case, matching `^[a-z0-9][a-z0-9-]*$` (letters, digits, and internal hyphens; no spaces, slashes, dots, uppercase, or leading hyphen) so the name is a safe directory segment and an unambiguous selector. The coordinator suggests a normalized form when the user offers a name that does not fit (for example, `Data Platform` → `data-platform`).
* **Unique within the federation.** No two sub-squads may share a name, compared case-insensitively after normalization. Before creating sub-squads, the coordinator checks the proposed set against itself and against any name already in `federation.md`; on a duplicate it stops and asks the user to rename one before proceeding — it never auto-suffixes silently or reuses an existing `members/<name>/` directory.
* **Stable.** The name is the durable handle used across turns. Renaming a sub-squad later means renaming its `members/<name>/` directory and its `federation.md` row together (a Scribe-performed change), so the coordinator treats a rename as an explicit operation, not a routine edit.

These rules are the sub-squad-level analogue of the per-member `Member Name` uniqueness in `squad-roster.instructions.md`: there, names disambiguate two rows of the same role; here, names disambiguate two sub-squads so each maps to exactly one folder and one selector.

## Meta-Routing Schema (`meta-routing.md`)

Meta-routing decides *which sub-squad* handles a request, the layer above the per-squad routing that decides *which role* acts. It begins with YAML frontmatter and a single H1, then a routing table:

| Column            | Meaning                                                                                     |
|-------------------|---------------------------------------------------------------------------------------------|
| Pattern / Domain  | The request trigger the Federation Coordinator matches (keywords, domain, or phrasing)       |
| Sub-squad         | The registered sub-squad the pattern routes to (must exist in `federation.md`)              |
| Parallel-Eligible | `yes` when the sub-squad can run concurrently with other sub-squads for one request; else `no` |

### Meta-Routing Example

```markdown
| Pattern / Domain                                                | Sub-squad | Parallel-Eligible |
|-----------------------------------------------------------------|-----------|-------------------|
| requirements, PRD, BRD, roadmap, backlog, stakeholder, discovery | product   | yes               |
| Azure, Bicep, landing zone, deploy, IaC, cost, infrastructure    | azure     | yes               |
```

### Meta-Routing Rules

* Match the most specific pattern first; when several match, prefer the sub-squad that most directly owns the requested outcome.
* An explicit `squad=<name>` target from the user overrides meta-routing for the turn.
* Dispatch parallel-eligible sub-squads concurrently; run non-parallel sub-squads sequentially. Each sub-squad's own routing then governs role dispatch inside it.
* Escalate to the user — rather than guessing — when no pattern matches with reasonable confidence, when a matched sub-squad is not in the registry, or when two patterns conflict with no clearly more specific match. State the ambiguity, list the candidate sub-squads, and ask the user to choose.

## Two-Level State and the Single Writer

Federation keeps the single-writer rule at both levels: only the Squad Scribe writes squad state, and it writes at whichever root the coordinator hands it.

* **Sub-squad level.** When the Federation Coordinator drives a sub-squad, the Scribe writes that sub-squad's `decisions.md`, `history/<agent>.md`, `consumption.md`, and the rest under `members/<name>/`, exactly as for a plain squad. Proof-of-dispatch is unchanged: a sub-squad stage is proven by a `members/<name>/history/<agent>.md` entry plus its consumption block.
* **Federation level.** The Federation Coordinator hands the Scribe a federation-level decision and a per-sub-squad history entry recording which sub-squad was routed to and why. These land at the federation root's `decisions.md` and `history/<sub-squad>.md` and reference the sub-squad's own decision entries so the two levels stay linked.

Neither the Federation Coordinator nor the Squad Coordinator writes state directly; both hand every mutation to the Scribe so parallel sub-squad dispatch cannot race on shared files. Each sub-squad's writes stay inside its own root, so two sub-squads running in parallel never touch the same files.

## Relationship to Multi-Repo Federation (deferred)

This file specifies the **in-repo** federation. The **multi-repo** federation — a hub that coordinates one squad per repository — reuses everything here and only changes a sub-squad's `Kind` to `repo` and its `Location` to an external repository, plus a cross-repo execution driver. Its research and plan live in `.copilot-tracking/plans/2026-07-16/squad-federation-multi-repo-plan.instructions.md`. The `repo` kind is reserved but not seeded by the in-repo flow.
