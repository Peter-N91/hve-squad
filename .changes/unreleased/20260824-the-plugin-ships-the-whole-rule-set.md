---
bump: patch
type: Fixed
---

- **The plugin distribution shipped a partial rule set, and the squad dispatched an off-roster
  role because of it.** The generator distilled fifteen instruction files into ten reference files
  by hand. Five had no destination at all — `squad-routing`, the discovery and intake gates,
  notifications, and watch mode — so `squad-routing`'s **Tracker-Write Gate** ("when the active
  roster does not carry `backlog-executor`, propose adding it") and the roster's **"never
  self-fill an absent role"** reached no plugin file. A federation sub-squad asked to write its
  backlog to Azure DevOps dispatched `Squad Backlog Executor` and wrote its history without ever
  adding the role to `team.md`, because in the plugin no rule said otherwise.

  Three further reference files (`floor.md`, `mcp-capability.md`, `notifications-and-watch.md`)
  existed only as hand-written files inside `hve-squad-plugin`, with no source of truth here and
  no generator step authoring them — one of them the target of a citation the generator emitted
  on every build.

  `Build-SquadPlugin.ps1` now ports every instruction file verbatim into
  `skills/squad/references/rules/`, builds the citation index from what it ported rather than
  from a hand-maintained map, and rewrites the directory-level prose that told the coordinator
  its rules live under `.github/instructions/squad/` in a distribution that ships no such
  directory. A new instruction file now reaches the plugin without anyone remembering to map it.

  A build-time conformance check fails the build — rather than warning — when a generated file
  cites an instruction path the plugin does not ship, cites a `skills/` target no step authored,
  or when anything under `agents/` or `skills/` was not authored by the run. Every defect it
  catches is invisible at run time: a dangling citation reads as a working reference, and a
  hand-written orphan is indistinguishable from generated content while it drifts.

- **`squad-researcher.agent.md` cited an hve-core instruction under the squad namespace.**
  `untrusted-content-boundary.instructions.md` deploys to `.github/instructions/`, not
  `.github/instructions/squad/`, so the citation resolved to nothing in the package as well as in
  the plugin.
