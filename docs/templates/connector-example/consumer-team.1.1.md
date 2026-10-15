---
title: Consumer connector roster and routing example
description: Automatic research and implementation connector defaults for autopilot, an optional implementation workflow, and extra GCP, .NET practices, and data-quality members.
---

# Consumer Connector Team

Merge these example rows into your existing squad through a confirmed refresh.
Do not overwrite its other members, edited roots, model choices, or routes.
For a federation member, rebase tracking roots to that member's `squadRoot`.
The manifests here are repository-relative; update their paths when copying.

## Members

| Role | Member Name | Agent Name (Primary) | Alternate Agents | Selection Cue | Invocation | Model Tier | Deliverable Root |
|---|---|---|---|---|---|---|---|
| researcher | Alpha | Squad Researcher | | - | runSubagent / task | default | .copilot-tracking/research/consumer/ |
| lead | Beta | Squad Lead | | - | runSubagent / task | default | .copilot-tracking/plans/ |
| developer | Gamma | Squad Implementor | | - | runSubagent / task | default | .copilot-tracking/changes/consumer/ |
| tester | Delta | Squad Reviewer | | - | runSubagent / task | fast | .copilot-tracking/reviews/ |
| azure-architect | Eta | Squad Azure Architect | | - | runSubagent / task | default | docs/architecture/ |
| scribe | Scribe | Squad Scribe | | - | runSubagent / task | fast | .copilot-tracking/squad/ |
| gcp | GCP Assessor | Squad Connector | | - | runSubagent / task | default | .copilot-tracking/squad/gcp-assessments/ |
| dotnet-practices | Dotnet Assessor | Squad Connector | | - | runSubagent / task | fast | .copilot-tracking/squad/dotnet-practices/ |
| data-quality | Data Assessor | Squad Connector | | - | runSubagent / task | fast | .copilot-tracking/squad/data-quality/ |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
|---|---|---|---|---|---|---|---|---|---|---|
| research-org | acme-research-agent | docs/templates/connector-example/manifest.research-agent.1.1.json | agent | replace | role | role:researcher/Alpha | Org Researcher | | | connector |
| implementation-org | acme-implementation-agent | docs/templates/connector-example/manifest.implementation-agent.1.1.json | agent | replace | role | role:developer/Gamma | Org Implementor | | | connector |
| developer-delivery-orchestrator | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Gamma | Partner Developer | | | ask |
| gcp-assessor | acme-capability-assessor | docs/templates/connector-example/manifest.capability-assessor.1.1.json | agent | add | role | role:gcp/GCP Assessor | GCP Assessor | gcp | azure-architect | connector |
| dotnet-assessor | acme-capability-assessor | docs/templates/connector-example/manifest.capability-assessor.1.1.json | agent | add | role | role:dotnet-practices/Dotnet Assessor | Dotnet Assessor | dotnet-practices | tester | connector |
| data-quality-assessor | acme-capability-assessor | docs/templates/connector-example/manifest.capability-assessor.1.1.json | agent | add | role | role:data-quality/Data Assessor | Data Assessor | data-quality | tester | connector |

## Routing fragment

Copy these rows to `routing.md`, keeping its other confirmed routes.
The generic assessment request must resolve to the specific capability route,
not to the council. `confirm` means the normal confirmation gate applies.

| Pattern / Keyword | Role(s) | Autonomy Tier | Parallel-Eligible |
|---|---|---|---|
| research, investigate | researcher | auto | yes |
| implement, build, code, fix | developer | confirm | no |
| assess GCP architecture, review GCP design | gcp | confirm | yes |
| assess dotnet practices, check .NET organization conventions | dotnet-practices | confirm | yes |
| assess dataset quality, validate data quality | data-quality | confirm | yes |

## Autopilot with saved defaults

```text
/squad mode=autopilot Implement the approved validation change and its regression tests. Do not deploy or push.
/squad Assess GCP architecture
/squad Assess dotnet practices
/squad Assess dataset quality
```

Research automatically uses `research-org`; implementation automatically uses
`implementation-org`. Plan and review stay internal until you register defaults
for those work roles too. Coordinator, Scribe, and council remain internal.

To use your full implementation workflow instead, confirm a refresh setting
`implementation-org` to `ask` and `developer-delivery-orchestrator` to
`connector`. The next autopilot invocation is unchanged: no per-stage
`execution=` flag is needed. See [the step-by-step guide](./CONSUMER-GUIDE.md#step-by-step-autopilot-test).

An optional `execution=` argument can override a matching work-role request
for comparison/debugging. It is not the normal autopilot path.
`Default Execution=original` keeps the internal endpoint as default when it is
the only non-`ask` default.

Multiple non-`ask` defaults are ambiguous, even if they appear to agree.
The coordinator asks interactively or stops and escalates unattended.

The three additive members share one example endpoint, but retain separate
roles, binding ids, member identities, and output roots. You can instead give
each its own manifest, mailbox, agent, or orchestrator. Alignment only selects
compatible assignment/model/output conventions; it creates no domain skills
and no council membership.
