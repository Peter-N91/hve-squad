---
name: squad-doctor
description: "Checks that the HVE Core cast bundled inside the hve-squad plugin is visible and dispatchable. Use at squad Init, on request ('run squad-doctor', 'check for missing roles', 'what's not installed'), or any time a mapped Primary agent cannot be found."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Doctor

## Why This Exists

The published `hve-squad` plugin bundles the exact HVE Core commit recorded in
its `.github/plugin/hve-core-source.json`. Every supported host should therefore
see the Squad and HVE Core cast from one plugin root. A missing domain indicates
an incomplete or stale update, a disabled plugin, a host inventory problem, or
a corrupt installation rather than an optional companion that still needs to
be installed. This check exposes that condition before dispatch.

## Inputs

None required. Optionally accepts **scope** (`all` default, or a single domain name) to narrow the report to one domain.

## Flow

1. **Enumerate dispatchable agents actually available in this session** — the set the coordinator could hand to `runSubagent`/`task` right now, by whatever discovery mechanism the host exposes (installed plugin agent listings, `apm install`-deployed `.github/agents/**`, or both).
2. **Check each of the seven domains below against its representative Primary agent name(s).** A domain is reported **present** only when at least one of its named Primaries actually resolves; **absent** otherwise. Do not guess from a partial match — an agent whose name merely sounds similar does not count.

   | Domain | Representative Primary agent name(s) to check for |
   |---|---|
   | `security` | `Security Planner`, `SSSC Planner`, `Skill Assessor`, `Supply Chain Skill Assessor`, `Finding Deep Verifier`, `Report Generator`, `CVE Analyzer` |
   | `rai` | `RAI Planner`, `RAI Skill Assessor` |
   | `privacy` | `Privacy Planner` |
   | `accessibility` | `Accessibility Framework Assessor`, `Accessibility Surface Inventory` |
   | `project-planning` | `PRD Builder`, `BRD Builder`, `Functional Planner`, `System Architecture Reviewer`, `ADR Creator`, `Meeting Analyst`, `UX UI Designer` |
   | `design-thinking` | `DT Coach`, `DT Learning Tutor` |
   | `coding-standards` | `Code Review Functional`, `Code Review Standards`, `Code Review Security`, `Code Review Accessibility` |

3. **Report per-domain, not just an aggregate.** For each domain: `present` (name the resolved agent) or `absent`. Never report a domain `present` on the strength of the squad's own `squad-*` glue agents (`Squad Reviewer`, `Squad Lead`, etc.) — those dispatch *to* the domain's agents and are not a substitute for them being present.
4. **Name the fix for every absent domain.** For a plugin consumer, update or reinstall the single `hve-squad` plugin from the same marketplace channel and start a fresh session. For an APM fallback consumer, rerun the pinned `apm install` command. Never tell a plugin consumer to install a second HVE Core plugin.
5. **Cross-check the mapping's currency.** This table mirrors the cast catalog canonical in `skills/squad/references/roster-catalog.md` as of this plugin's build. If the roster changes which Primary a role resolves to, this table drifts — note that possibility in the report rather than presenting the table as infallible.

## Output

A short per-domain table (`present`/`absent` + resolved agent name or the fix) plus a one-line summary count (`N of 7 domains present`). Never silently drop a domain from the report.

## Invocation

This is a mechanical inspection, not a role dispatch — perform it directly rather than routing to a specialist agent. It complements, and does not replace, `hooks/scripts/session-start-check.sh` (which only checks squad-state file resolution, not cast availability).