---
name: squad-delegated-worker-routing
description: "Cold-loaded selected-delegate admission: explicit ownership, roster routes, worker pins, undiscounted ranked models, lazy eligibility, and existing history attribution."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-10"
---

# Selected Delegates

Read only when a dispatched parent can delegate, through an explicit `agents:` list, a skill, or a generic `agent`/`task` call. This uses the existing [model resolver](../scripts/Resolve-SquadModelRoute.ps1), not another dispatcher. The coordinator still resolves roles, the parent still constructs worker inputs, and the host still dispatches.

## Ownership and Admission

1. Propagate the parent's explicit owning (`Role`, `Member Name`) row and `squadRoot` in its brief. Nested workers retain that row until a genuine roster-role dispatch establishes its own ownership. Do not infer ownership from similar agent names or the parent session's model.
2. Discovery is not admission. An `agents:` list advertises reachability; a generic agent call selects a target. Resolve model eligibility only for that selected target. An unused delegate with no eligible model must not stop unrelated parent work.
3. Match the selected target against the running roster's Primary and Alternate cells. A genuine roster match retains its own assignment class, floor, and policy (including its own discounted pick when applicable), not the caller's. Disambiguate shared agents by `-Role`; an ambiguous or mismatched roster identity is an explicit refusal, never an unrostered worker.
4. With no roster match, the target is a worker, not a new role. Preserve its required input contract and the parent's artifact ownership. Read the worker's own model pin first; a pin governs that worker and is never silently replaced to make lookup succeed. If unpinned, request the owner's **ranked model at its real floor**, not its discounted `suggested`/`resolved` pick, manual cell, or inherited session model. The same full-floor rule applies when the parent used the bounded lane. Ordinary no-policy role dispatch remains unchanged.
5. Admit only this selected dispatch. Validate availability and the applicable floor for the selected pin or request. An unavailable, uncatalogued, or below-floor worker pin is a refusal, not permission to override it. No eligible ranked worker model means explicitly refuse that dispatch, naming owner and floor; never silently downgrade or omit `model` to gamble on a host fallback. Record the refusal in the parent's outcome/decision, not as consumption for a worker that never ran.
6. Keep consent, approval, artifact and cost gates. A roster-backed target still copies its own Model cell, with a Scribe refresh before dispatch when its computed pick changed. Unpriced explicit manual roster picks keep the existing unevaluated exception; automatic worker picks and pins must have a verifiable capability class. The helper reports missing economy consent as before; the coordinator records acceptance before proceeding.

## Helper and Host Precedence

Run `Resolve-SquadModelRoute.ps1 -SquadRoot <root> -DispatchAgent '<exact name>' -OwningRole <role>` with this host's `-AvailableModels` or `-SessionModel`. Add `-OwningMemberName` for duplicate owner rows and `-Role` for an ambiguous roster-backed delegate.

Without `-DispatchAgent`, reports and ordinary routing are unchanged. With it, the helper adds `dispatch` or throws `Delegate dispatch refused`. It writes nothing, admits no other delegate and authorizes no worker inputs. It retains repository-first and installed-plugin agent lookup.

`selectedModel` is a prediction of the admitted model, never a host observation. `routingIdentity.requestedModel` is the value to pass, or `none (parameter omitted)` for a governing pin. Omission preserves that target's frontmatter pin. Role requests under ranked/manual routing intentionally replace a pin through the existing dispatch parameter; worker owner requests do not replace worker pins. An explicit dispatch request is distinct from session `--model`, which does not override pins.

`attributionSource` and `routingIdentity.effectiveModel` predict attribution only until the host reports. Re-run the same selected resolution with `-ObservedModel <host report>` when one is available: that report wins attribution without replacing the requested value. The helper cannot dispatch a model, compel the host to honor a pin, or assert that a request actually ran. Under `SessionModel: auto` without a host report, attribution is `unresolved`, Effective model is `unknown`, and Observed model is `unreported`; neither the pin nor the request proves what ran.

The host's model report is stronger than the helper's prediction. A differing concrete report produces the existing `identity-mismatch` token. The dispatch report's `observedFloor` is `admitted`, `below-floor`, `unverified`, or `unreported`; escalate a below-floor or unverifiable host substitution through the existing floor/Risk Gate procedure, never record it as successful admission. Retain the actual consumption even when escalation is required. Host rejection may re-rank only at the same floor; it never permits a weaker worker.

## History and Consumption

Give every delegating parent this procedure and require it to return each actual worker's exact agent name, request, artifact/outcome, passed model, host model report, routing identity, and consumption estimate. Do not count that worker's loop again in the parent's estimate.

Use the existing [history schema](entry-schemas.md) and [Scribe payload](scribe-payload-template.md):

* Keep the ten consumption fields closed and in order. `model` is the Effective model, and `model_source` records the attribution rung, never a fabricated host observation. Host reports use `dispatch-reported`; an honored pin prediction under fixed selection uses `agent-pinned`; an explicit request without a contrary report uses `cli-pinned`; auto without a report uses `unresolved`.
* Keep the four D9 identity bullets: Requested model, Effective model, Observed model, Route rationale. Include owning role/member, routing role, assignment class, floor, pin/ranked source and refusals/substitutions in Route rationale. Under economy, retain the `Route: economy` prefix; a bounded dispatch substitutes the existing `Route: bounded` prefix.
* Requested and reported models remain distinct. Price the Effective/Observed model, not the request, and surface every `identity-mismatch` in the run summary.
* Unrostered worker records go to the **Squad Scribe**: the ordinary hand-off script's existing exit 2 delegates non-roster history to it. The ledger already retains unmapped agent history under the exact agent name. Do not cast workers or expand the hand-off/consumption schema to avoid that fallback.
* A never-started worker has no consumption block.

## Compatibility Evidence

This is an audit prompted by a confirmed failure in the separate MCP adapter, not proof of an upstream runtime bug. Current upstream includes `routing=economy`; its role resolver reports an exhausted unused row without throwing for other rows. Dispatch remains coordinator/parent `runSubagent`/`task`, and plugin dispatch guards are maintained outside this checkout.

At the HVE Core `727e262d7fa7f59c6568fe85a441958301a41589` pin in `apm.yml`, Functional Planner is unpinned, has no explicit delegate list, and hands execution to Backlog Manager. ADO Backlog Executor is an unpinned worker requiring a confirmed destination, sanitized operations, autonomy tier, tracking directory, and optional preview flag. Its presence must not make Functional Planner a tracker writer: the opt-in backlog-executor charter and Impactful-Action Gate still govern execution. An adapter-style synthetic planner delegate list tests compatibility, not this pinned planner's runtime delegation.
