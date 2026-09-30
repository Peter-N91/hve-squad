---
bump: minor
type: Changed
---

- **Ranked routing picked models by price and spelling, not by fit.** Ranking went capability class, then cheapest input rate, then alphabetical Catalog ID. So every lightweight role landed on `gemini-3.6-flash`, and every frontier role landed on `claude-opus-5.5`. The catalog now scores every model 0–3 for each assignment class (*Catalog: Assignment Fit*). Ranking goes by fit, then a blended per-dispatch rate, then the newer generation within a family, and never by name (`squad-src/.github/skills/squad/references/model-catalog.md`, `squad-src/.github/skills/squad/references/model-routing.md`).
- **Per-role models now live in `team.md`.** `routing=off|ranked|manual` is persisted as a `Model routing:` line in `team.md`, and a `Model` column shows each role's model: the ranked pick, or the user's own pick. `routing=manual` asks before any dispatch: accept all suggestions, pick per assignment class, then per-role exceptions. It offers only models the host can run: the `task` enum on the Copilot CLI and the GitHub Copilot app, or models priced at or below the session model on VS Code. The comma-separated `models=` input is retired (`squad-src/.github/agents/squad/squad-coordinator.agent.md`, `squad-src/.github/prompts/squad/squad.prompt.md`).
- **`consumption-rates.md` gains a `Model ID` column** holding the exact dispatch id for every priced model, so a `Model` cell maps straight to its rate row (`squad-src/.github/skills/squad/references/consumption-rates-template.md`).
- **`intake-validator` now seeds at the `default` floor instead of `fast`.** Its readiness verdict gates every later stage, so it no longer runs on lightweight models (`squad-src/.github/skills/squad/references/seed-templates.md`).
- **New read-only helper `Resolve-SquadModelRoute.ps1`** (PowerShell 7+). It computes each role's ranked pick, candidate list, and `Model` cell status deterministically (`squad-src/.github/skills/squad/scripts/Resolve-SquadModelRoute.ps1`).
- **Catalog re-verified 2026-09-30**, adding GA models Claude Sonnet 5.5 and GPT-6.1 Sol.
