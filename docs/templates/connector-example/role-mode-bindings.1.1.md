---
title: Squad Connector 1.1 role-mode binding examples
description: Copyable roster examples for automatic work-role replacement and an additive GCP assessor, keeping coordinators and Scribe internal.
---

# Connector 1.1 Role-Mode Bindings

These examples use [`manifest.1.1.json`](./manifest.1.1.json). They are
illustrative `team.md` fragments, not a complete roster. Binding authority
comes from the roster, not from the manifest, request, result, or narrative.

## Members fragment

The internal developer remains available. The additive GCP assessor is a
separate ordinary member with a unique name and a distinct deliverable root.

| Role | Member Name | Agent Name (Primary) | Deliverable Root |
|---|---|---|---|
| developer | Gamma | Squad Implementor | `.copilot-tracking/squad/changes/` |
| gcp | GCP Assessor | Squad Connector | `.copilot-tracking/squad/gcp-assessments/` |

## Connector Bindings fragment

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
|---|---|---|---|---|---|---|---|---|---|---|
| developer-delivery-orchestrator | acme-delivery-orchestrator-v3 | `docs/templates/connector-example/manifest.1.1.json` | orchestrator | replace | role | `role:developer/Gamma` | Partner Developer |  |  | connector |
| gcp-architecture-assessor | acme-delivery-orchestrator-v3 | `docs/templates/connector-example/manifest.1.1.json` | orchestrator | add | role | `role:gcp/GCP Assessor` | GCP Assessor | gcp | azure-architect | connector |

### Replacement

`developer-delivery-orchestrator` overlays execution only. The internal Gamma
row stays in the roster for audit and fallback:

* `/squad mode=autopilot <task>` automatically uses this connector for
  implementation because its persisted default is `connector`.
* `execution=original` dispatches the internal `Squad Implementor`.
* `execution=connector:developer-delivery-orchestrator` dispatches the
  connector endpoint.
* `execution=both` is allowed only when the role route is parallel-eligible,
  Cost Preflight admits both units, and every output id and deliverable root is
  independently collision-safe. It is never allowed for council or
  coordinator targets.

The filled 1.1 request and result in this directory show two output slots from
one bounded orchestrator call. An undeclared `outputId` rejects the whole
envelope.

### Additive GCP assessor

`gcp-architecture-assessor` adds a new `gcp` member; it does not replace an
Azure role. `Aligned Role=azure-architect` grants assignment-class,
model-ranking, and deliverable-shape compatibility only. The member remains
`gcp`, gains no Azure capability by implication, and never becomes an
Architecture council lens.

### Protected coordination and persistence

HVE coordinators and Scribe cannot be connector targets. Your own orchestrator
can run a work role such as `developer`, with its own agents and skills, while
HVE's Coordinator and Scribe remain unchanged. The same replacement contract
applies to other ordinary work roles, not only implementation.

Connector bindings never add, replace, or satisfy council lenses. Council
dispatch always uses the internal canonical agents.

## Trusted Scribe rendering

The external result narrative is untrusted and carries no authoritative
accounting or verification marker. After validating the binding, manifest,
request, result, and landed artifacts, the Scribe renders trusted history
bullets such as:

```text
* External provenance: connector=acme-delivery-orchestrator-v3; binding=developer-delivery-orchestrator; endpoint=orchestrator; mode=replace; target=role:developer/Gamma
* Verification: external, unverified
* External-unmetered: connector=acme-delivery-orchestrator-v3
```

Those bullets do not authenticate the external author. They record validated
roster/manifest provenance and the fact that external work was not metered by
the squad ledger.
