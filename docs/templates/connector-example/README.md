---
title: Squad Connector examples
description: Consumer agent and orchestrator starters, replacement and additive roster examples, versioned envelopes, and a compatibility checklist.
---

# Squad Connector Example

This directory contains worked examples of the Squad Connector contract
defined in
[`connector-contract.md`](../../../squad-src/.github/skills/squad/references/connector-contract.md).
Every file name, field name, and field value here matches that contract
exactly — copy a file, rename the connector, and adapt rather than
re-deriving the shapes from prose.

A consumer wiring up their own coordinator reads `connector-contract.md`
first. This directory retains the legacy `acme-coordinator-v2` 1.0 round trip
and adds an `acme-delivery-orchestrator-v3` 1.1 role-mode round trip.

## Start with your agents and extra members

Start with the [consumer walkthrough in the documentation](../../connector.html#consumer-walkthrough).
It shows the repository tree, researcher-agent/developer-workflow setup,
registration decisions, autopilot, and extra .NET/GCP members. Its
[inline templates](../../connector.html#copy-the-templates) have copy buttons
and download links. A [Markdown companion](./CONSUMER-GUIDE.md) is also available.

| Example | What you can adapt |
|---|---|
| [Consumer team](./consumer-team.1.1.md) | Automatic research/implementation defaults, an optional workflow, and GCP, .NET practices, and data-quality members |
| [Research agent](./agents/consumer-research.agent.md) and [manifest](./manifest.research-agent.1.1.json) | Your researcher and its own skills |
| [Implementation agent](./agents/consumer-implementation.agent.md) and [manifest](./manifest.implementation-agent.1.1.json) | Your implementor and engineering practices |
| [Implementation orchestrator](./agents/consumer-implementation-orchestrator.agent.md) | Your research, implementation, and validation workflow behind the developer seat |
| [Developer workflow manifest](./manifest.delivery-workflow.1.1.json) | Developer-only manifest used by the consumer walkthrough |
| [Capability assessor](./agents/consumer-capability-assessor.agent.md) and [manifest](./manifest.capability-assessor.1.1.json) | Multiple additive roles, not only GCP |
| [Agent request](./delegation-request.agent.1.1.sample.json) and [agent result](./result-envelope.agent.1.1.sample.json) | A 1.1 single-agent exchange without optional `outputs` |

These charters are source-only starters. Replace their example organization skill
names and configure your own runner; HVE does not install or execute them. The
user-invocable builders can scaffold a removable runner and runbook when present.

## Legacy 1.0 worked example (filled in)

| File | What it is |
|---|---|
| [`manifest.json`](./manifest.json) | The consumer-authored capability manifest: `transport: file`, the `developer` role, and a `dropPath`. |
| [`delegation-request.sample.json`](./delegation-request.sample.json) | What the Squad Connector shim writes to `dropPath` in Step 2 of its dispatch. |
| [`result-envelope.sample.json`](./result-envelope.sample.json) | What the consumer's coordinator writes back in the legacy 1.0 single-role flow. |
| [`sample-consumer-coordinator.md`](./sample-consumer-coordinator.md) | A prose-and-pseudo-code sketch of the external coordinator process itself. **Illustrative only — never executed, imported, or shelled out to by anything in this repository.** |

The retained 1.0 result narrative predates the trusted-provenance
clarification and repeats an accounting marker as text. It remains untrusted
narrative and is preserved only as compatibility evidence.

For both contract versions, the shim also writes a closed
`<taskId>.snapshot.json` collision baseline before publishing
`<taskId>.request.json`. That sidecar is shim-owned runtime evidence, not a
consumer template: watchers ignore it and never edit it, while later resumes
reuse it unchanged.

## Role-mode 1.1 worked example

| File | What it is |
|---|---|
| [`manifest.1.1.json`](./manifest.1.1.json) | A file-transport orchestrator manifest with bounded developer, tester, and GCP capabilities. |
| [`delegation-request.1.1.sample.json`](./delegation-request.1.1.sample.json) | A binding-aware request with a named role target and two closed `allowedOutputs`. |
| [`result-envelope.1.1.sample.json`](./result-envelope.1.1.sample.json) | A bound multi-output result whose narrative contains no authoritative accounting or verification markers. |
| [`role-mode-bindings.1.1.md`](./role-mode-bindings.1.1.md) | Copyable work-role replacement/addition fragments, persisted defaults, optional overrides, and trusted Scribe rendering. |

## Legacy 1.0 blank templates

| File | Replaces |
|---|---|
| [`manifest.template.json`](./manifest.template.json) | `manifest.json`, with every value blanked except `transport: "file"` and `schemaVersion: "1.0"`. |
| [`delegation-request.template.json`](./delegation-request.template.json) | `delegation-request.sample.json`, with every value blanked. Written by the shim, not hand-authored — shown here only so the shape is easy to recognize. |
| [`result-envelope.template.json`](./result-envelope.template.json) | `result-envelope.sample.json`, with every value blanked. Written by a consumer's own coordinator. |

## Contract versions, role modes, and authority boundaries

* The unsuffixed JSON samples and blank templates remain the **legacy 1.0**
  compatibility fixtures (single role, single deliverable root, manual flow).
* Files carrying `.1.1` are the role-mode examples.
* **Role modes are 1.1 features** and are roster-owned in `team.md`
  `Connector Bindings` (replace vs add, endpoint kind, target kind, and
  default execution choice).
* Registration/build/refresh is where consumers choose whether a connector
  **replaces** an existing execution surface or **adds** a new
  connector-backed member.
* Autopilot resolves saved defaults for every work-role dispatch; no execution
  flag is required. `original`, `connector:<binding-id>`, and safe `both` remain
  optional request-time overrides.
* HVE coordinators and Scribe cannot be connected. The only target kind is
  `role`, for ordinary work roles; council governance stays internal too.
* Additive alignment is compatibility only. Example: a `gcp` assessor aligned
  to `azure-architect` inherits routing/deliverable semantics, but gains no
  Azure capability by implication and no council lens membership.

## Example history-entry narrative

The Accounting Convention in `connector-contract.md` requires the dispatching
role's `history/<agent>.md` entry to carry the exact marker phrase
`External-unmetered: connector=<id>` in its trusted Scribe-rendered bullets.
That marker is derived from validated registration/binding provenance, not from
external narrative text. For this example connector, trusted history bullets include:

```text
* Outcome: external, unverified
* Verification: external, unverified
* External-unmetered: connector=acme-coordinator-v2
```

This is a worked example of squad state the Scribe writes — it is not itself
a squad-state file and this directory does not create one.

## Rollback and unrouting (1.1 back to 1.0/internal)

If you need to roll back from role modes:

1. Run a confirmed roster refresh to remove the 1.1 binding and remove or rebind
   any affected additive members/routes.
2. Keep using the retained internal original member (`execution=original`) or
   return to the legacy 1.0 manual connector flow.
3. Do not widen authority: council, governance gates, approvals, and Scribe
   ownership remain internal throughout rollback.

## Compatibility checklist

[`COMPATIBILITY-CHECKLIST.md`](./COMPATIBILITY-CHECKLIST.md) restates the
contract's own Compatibility Checklist as a standalone, checkable file a
consumer can copy alongside their coordinator's own documentation.

## What this example is not

* It is not a reference implementation of a coordinator — no code here runs.
* It is not shipped inside the installed APM package; it lives only in this
  source repository as documentation for consumers authoring their own
  connector.
* It does not define `transport: mcp` or any other transport — the contract
  reserves that value and this example does not build it.
