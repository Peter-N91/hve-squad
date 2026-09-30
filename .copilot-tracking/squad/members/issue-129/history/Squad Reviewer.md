---
description: "Append-only dispatch history for a single squad agent"
---

# History: Squad Reviewer

### 2026-09-30T12:25:00Z Verifying the cast repoint against a live hve-core clone, the delta script, docs, and the manifest suite

* Turn: 1
* Request: Confirm every roster Primary and Alternate resolves to an installed, dispatchable hve-core agent at `5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb`, that none sets `disable-model-invocation: true`, that no docs reference the removed `graph-research` prompt, and that the delta script reports a non-breaking verdict.
* Deliverable:
  * Verification notes folded into `.copilot-tracking/squad/members/issue-129/decisions.md` under *Root Cause*, *Fix Approach*, *Risk Gate*, and *Acceptance Criteria Status*.
* Outcome:
  * Ran `pwsh scripts/Get-HveCoreCastDelta.ps1 -ToRef 5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb` before editing: confirmed the verdict matched the issue's attached report exactly — `graph-research` (prompt), removed, one reference, in `squad-src/.github/instructions/squad/squad-roster.instructions.md`.
  * Cloned `microsoft/hve-core` directly at `5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb` and parsed every `.github/agents/**/*.agent.md`'s `name:` and `disable-model-invocation:` frontmatter; cross-checked all 71 entries in both `squad-coordinator.agent.md` and `squad-federation-coordinator.agent.md`'s `agents:` lists. Every hve-core-sourced name resolves and none sets `disable-model-invocation: true`; the remaining names (`Power Platform Expert`, `Power Platform MCP Integration Expert`, `Declarative Agents Architect`, `MCP M365 Agent Expert`, `QA`, `GitHub Actions Expert`, three `aws-*` agents) are Registered External Cast entries outside `microsoft/hve-core` and outside this delta's scope.
  * Re-ran `pwsh scripts/Get-HveCoreCastDelta.ps1 -ToRef 5c7f9a7d2c0da3d8bbd3562cb89b7a7811acd2eb` after the roster edit and the `apm.yml` regeneration: verdict `no surface change` (`FromRef` now equals `ToRef` since the pin moved), `isBreaking: False`, `squadAtRisk: {}`.
  * Diffed the pre- and post-regeneration `apm.yml` dependency lists directly (not just grepped for the SHA) to confirm no hve-core path silently dropped beyond the three the delta and repository comparison both explain (`graph-research.prompt.md`, `graphify.instructions.md`, `hve-core-location.instructions.md` — the last two removed/renamed by hve-core independent of this issue and referenced nowhere in `squad-src/`).
  * Swept `README.md`, `CONTRIBUTING.md`, and `docs/` for `graph-research`; zero hits.
  * Confirmed `apm.yml`'s `version:` line is unchanged (`0.17.0`) and `CHANGELOG.md` has no diff.
  * Confirmed `.changes/unreleased/20260930-adapt-squad-cast-to-hve-core-5c7f9a7.md` carries `bump: minor`.
  * Ran `tests/tier0/Manifest.Tests.ps1` directly against Pester (the full `Invoke-Tier0Tests.ps1` install harness needs the `apm` CLI, which is not installed in this sandbox and is a different tool from the unrelated npm package of the same command name): PKG-11 passed all 52 assertions, confirming every squad-owned artifact under `squad-src/.github/{agents,prompts,instructions,skills}` is still declared in the regenerated `apm.yml`.

#### Consumption

```json
{
  "model": "claude-sonnet-5",
  "model_source": "session-inherited",
  "priced_as": "Claude Haiku 4.5",
  "model_tier": "fast",
  "internal_turns": 9,
  "input_tokens": 46000,
  "cached_tokens": 158000,
  "cache_write_tokens": 24000,
  "output_tokens": 4100,
  "basis": "estimated"
}
```
