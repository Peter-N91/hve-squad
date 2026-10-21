---
title: Bring your researcher and implementation workflow
description: Consumer onboarding for connector folders, replacing work roles, registration choices, autopilot, and extra .NET or GCP specialists.
ms.topic: how-to
ms.date: 2026-10-15
---

## Example: your researcher and implementation coordinator

Your squad is already initialized. You want your research agent, with its
organizational skills, to perform `researcher` work. You also have an
implementation coordinator that runs your own coding and validation agents.
It will perform `developer` work.

The published [Squad Connector guide](../../connector.html) contains this
walkthrough with inline templates, file download links, and copy buttons.
This Markdown companion uses the same configuration and template files.

HVE's Coordinator, Federation Coordinator, Scribe, and council stay internal
and unchanged. Your implementation coordinator is an external workflow behind
the developer role, not a replacement for HVE's Coordinator.

Use a Squad package that supports contract 1.1. You also need your existing agent
host/adapter: it reads file-drop requests, runs the configured endpoint with its
own skills, and returns a result. Copying a manifest or an agent file does not
start that process.

## Step 1: Create the connector folders

Create `connectors` and the two mailbox directories in your project:

```powershell
New-Item -ItemType Directory -Force -Path `
    '.\connectors', `
    '.\.connector-drops\acme-research-agent', `
    '.\.connector-drops\acme-delivery-orchestrator-v3' | Out-Null
```

Use this layout. Agent starters are optional if you already have your own
agents; they belong in the host that runs your endpoints.

```text
your-repository\
+-- connectors\                         You create these manifests
|   +-- research-agent.json
|   +-- delivery-workflow.json
|   +-- specialists.json                Optional, Step 5
+-- .connector-drops\                   Mailboxes, not final reports
|   +-- acme-research-agent\
|   +-- acme-delivery-orchestrator-v3\
|   +-- acme-capability-assessor\        Optional, Step 5
+-- .github\
|   +-- agents\                         Optional consumer-owned starters
|       +-- consumer-research.agent.md
|       +-- consumer-implementation-orchestrator.agent.md
|       +-- consumer-implementation.agent.md
|       +-- consumer-validation.agent.md
|       +-- consumer-capability-assessor.agent.md
+-- .copilot-tracking\
    +-- squad\                          HVE/Scribe-managed squad state
        +-- team.md                     Members and Connector Bindings
        +-- routing.md
        +-- decisions.md
        +-- state.json
        +-- history\
```

Keep your skills in their existing supported location. The starters use
`org-research`, `org-dotnet`, and `org-validation` as example names; replace
them with your real skills. The optional assessor also needs a configured
domain skill, such as `org-gcp`.

## Step 2: Configure the researcher and implementation workflow

Copy the [research manifest](./manifest.research-agent.1.1.json) into
`connectors/research-agent.json` and the
[delivery workflow manifest](./manifest.delivery-workflow.1.1.json) into
`connectors/delivery-workflow.json`. Their full contents are available in
the published guide's template section.

| Project file | Connector ID | Endpoint Kind | Work role |
|---|---|---|---|
| `connectors/research-agent.json` | `acme-research-agent` | agent | researcher |
| `connectors/delivery-workflow.json` | `acme-delivery-orchestrator-v3` | orchestrator | developer |

The manifest declares capability and transport, not which role it replaces.
The roster binding created in Step 3 makes that choice.

Configure your adapter's trusted endpoint mapping:

| Connector ID | Endpoint in your host | Skills/workflow |
|---|---|---|
| `acme-research-agent` | Your researcher, or Consumer Research Agent | Your research skills |
| `acme-delivery-orchestrator-v3` | Your implementation coordinator, or Consumer Implementation Orchestrator | Your implementation and validation agents, with their skills |

### How `.agent.md` files, manifests, and your adapter link together

1. **Manifests (`connectors/*.json`) declare capability and mailbox paths only.**
   The `roles` array in a manifest is an **allowlist** of squad roles that connector is permitted to serve—it does **not** automatically replace every listed role. For security, manifests never contain shell commands, scripts, or `.agent.md` file paths.
2. **`team.md` (`## Connector Bindings`) chooses the actual role binding.**
   During `init` or roster refresh, each binding row links one squad role (for example `researcher`) to one `connectorId` and `Manifest`, and sets `Default Execution=connector`.
3. **Your consumer `.agent.md` files and skills can live anywhere.**
   They can stay in `.github/agents/` inside the repository or in a separate central folder or repository on your machine—HVE Squad never dispatches consumer `.agent.md` files directly because `Squad Coordinator` only dispatches its built-in `Squad Connector` shim.
4. **Your adapter script bridges `.connector-drops/<connectorId>/` to your `.agent.md` or workflow.**
   When a bound role runs, `Squad Connector` first writes its internal `<taskId>.snapshot.json` collision baseline, then publishes `<taskId>.request.json` into the manifest's `dropPath` and pauses (`awaiting`). A lightweight PowerShell watcher (or your own agent host) polls only `*.request.json`, ignores and never edits `*.snapshot.json`, maps `connectorId` to your `.agent.md` or orchestrator, runs it against the real source files named in `request.task`, writes the source-grounded `.md` deliverable(s), and writes `<taskId>.result.json`.

Below is a reference PowerShell watcher loop you can adapt for your own host (save it outside the package or in your own tooling folder and replace the inner agent call with your CLI or SDK runner):

```powershell
#Consumer-owned watcher sketch: maps connectorId -> your external .agent.md or CLI runner
$EndpointMap = @{
    'acme-research-agent'           = 'C:\OrgAgents\consumer-research.agent.md'
    'acme-delivery-orchestrator-v3' = 'C:\OrgAgents\consumer-implementation-orchestrator.agent.md'
}

Get-ChildItem -Path '.\connectors\*.json' | ForEach-Object {
    $manifest = Get-Content $_.FullName -Raw | ConvertFrom-Json
    $dropDir  = Join-Path (Get-Location) $manifest.dropPath
    Get-ChildItem -Path $dropDir -Filter '*.request.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $req        = Get-Content $_.FullName -Raw | ConvertFrom-Json
        $resultPath = Join-Path $dropDir "$($req.taskId).result.json"
        if (-not (Test-Path $resultPath)) {
            $agentFile = $EndpointMap[$req.connectorId]
            # 1. Invoke your agent/CLI ($agentFile) with $req.task and the read-only sources it names.
            #    The generated Markdown must cite the actual project sources (generic placeholders are rejected).
            # 2. Save the new task-owned Markdown report(s) under $req.deliverableRoot (or declared allowedOutputs[].deliverableRoot) without overwriting pre-existing files, then write $resultPath in $dropDir matching the 1.1 Result Envelope schema.
        }
    }
}
```

The adapter's mapping format depends on your host. HVE does not read an
invented adapter configuration file, execute a manifest command, or discover an
endpoint from its filename. Do not add unsupported fields to the manifest.
Change the sample contact address, ids, and paths if necessary, keeping the
mapping, registration, and mailbox paths consistent.

## Step 3: Register and choose which roles to replace

Send this to the Squad Coordinator:

```text
I added two connector manifests to this repository:
connectors/research-agent.json
connectors/delivery-workflow.json

Help me connect them to this initialized squad.
I want my research agent to perform researcher work, and my implementation
coordinator to perform developer work. Keep HVE coordination, Scribe, and council unchanged.
Show the proposed configuration and wait for my confirmation.
```

The coordinator asks for missing decisions one at a time. Exact wording varies;
already supplied values do not need to be asked again. For this example choose:

| Decision | Research connector | Delivery connector |
|---|---|---|
| Replace an existing role or add a member? | replace | replace |
| Which role/member? | Existing researcher member | Existing developer member |
| Single agent or workflow? | agent, from manifest | orchestrator, from manifest |
| Automatic default or alternative? | connector | connector |
| Connector member label for history? | Org Researcher | Org Delivery |
| Where should reports land? | Existing researcher root | Existing developer root, with declared workflow output slots |

If you want a request-time alternative instead, choose `ask`; unattended
autopilot cannot guess that choice. Use `connector` for the automatic behavior
in this example. For a role with several members, confirm which member is
targeted. Keep only one applicable non-`ask` default.

Confirm the proposal. The Scribe persists the bindings in the owning squad's
`team.md`; it preserves the original internal Members rows and their roots.
The existing research/developer routes do not need to be replaced.

| Binding ID | Role Mode | Target | Default Execution |
|---|---|---|---|
| research-org | replace | researcher member | connector |
| developer-delivery-orchestrator | replace | developer member | connector |

Do not overwrite `team.md` with a sample roster or manually change the Primary
agent to your endpoint's name. Connector execution uses the Squad Connector shim.

## Step 4: Run the squad

Submit your normal bounded task:

```text
/squad mode=autopilot Implement the approved validation change and its regression tests. Do not deploy or push.
```

No `execution=` argument is needed. Research automatically uses your researcher.
Planning stays with the existing lead. Implementation uses your coordinator's
workflow. HVE's closing review and applicable council/risk gates remain in place.
Other ordinary work roles support the same binding mechanism.

Your running adapter handles the request and writes the reports directly under
the declared root before returning the result. Your endpoint is responsible for
grounding those reports in the repository sources and citations requested by
`request.task`; HVE's ordinary review assesses their domain quality. The
scripted shim validates identity, paths, files, caps, and secret-shaped content,
not whether the report's claims are correct. A result that
is not ready leaves the current stage `awaiting`; it does not trigger a fallback
to the internal worker. Consumer automation can resume the run when the result
arrives. If your workflow uses manual file handoff, resume the same task:

```text
/squad mode=autopilot Continue the current run. Check the pending connector result using its existing taskId and binding; do not create a new task.
```

The connector does not provide an external runner or automatic wake-up service.
That transport limitation is separate from automatic role selection.

The thin `Squad Connector` agent runs `Invoke-SquadConnectorDispatch.ps1` once
and returns its JSON; the existing resolver stays side-effect free. The wrapper
keeps request/snapshot hashes, unanswered retry counts, and consumed ids in
`dropPath/.squad-connector/<taskId>.state.json` under an exclusive task lock.
Preserve that private state and never let your watcher edit it. Replay rejection
survives a new process and removal of public exchange files, but not deletion or
tampering with trusted private state. Pending exchanges without that state fail
closed instead of being re-snapshotted. Only validated paths and provenance
return to the coordinator, never raw `narrative` or artifact contents. Routing,
admission, escalation, and Scribe persistence remain internal to HVE.

## Step 5: Add a .NET or GCP specialist

An extra specialist uses `add`, not `replace`. For a .NET practices assessor:

1. Copy the [specialist manifest](./manifest.capability-assessor.1.1.json) into
   `connectors/specialists.json`.
2. Create `.connector-drops/acme-capability-assessor/`.
3. Configure that endpoint in your adapter with your real assessor and domain
   skills. The example Consumer Capability Assessor maps the requested role
   to an explicitly configured skill.
4. Send this to the Squad Coordinator and confirm its proposal:

```text
Add an extra specialist from connectors/specialists.json without replacing anyone.
Use binding dotnet-assessor, member Dotnet Assessor, and added role dotnet-practices.
Align it to tester for classification only.
Use .copilot-tracking/squad/dotnet-practices/ for its reports.
Route "assess dotnet practices" to it and set Default Execution=connector.
Keep the existing tester, Coordinator, Scribe, and council unchanged.
Show the proposed member, binding, route, and root before writing.
```

The coordinator confirms the additive member, alignment, root, route, and
default. The Scribe creates a separate member with `Primary=Squad Connector`,
not a replacement for `tester`.

For GCP, use the same manifest and configured assessor, or your own separate
manifest/endpoint. Choose:

| Field | .NET example | GCP example |
|---|---|---|
| Binding ID | dotnet-assessor | gcp-assessor |
| Added Role | dotnet-practices | gcp |
| Member Name | Dotnet Assessor | GCP Assessor |
| Aligned Role | tester | azure-architect |
| Deliverable Root | `.copilot-tracking/squad/dotnet-practices/` | `.copilot-tracking/squad/gcp-assessments/` |
| Route | assess dotnet practices | assess GCP architecture |
| Default Execution | connector | connector |

Alignment grants classification/output compatibility, not domain skills or
council membership. In a federation, use roots resolved for the owning member.
Add as many distinct connector-backed members as needed, with unique names and
bindings.

```text
/squad Assess dotnet practices in the implemented change.
/squad Assess GCP architecture for the proposed design.
```

To include the specialist in autopilot, request its assessment as a deliverable
so the plan names the owning role. Adding a member alone does not run it on
every request.

## Step 6: Know where outputs and ownership live

| Output | Owner and location |
|---|---|
| Requests/results | Shim/adapter in each manifest's mailbox |
| Research report | At the researcher's active `Deliverable Root` |
| Implementation/validation reports | At the workflow request's declared output-slot roots |
| .NET/GCP assessments | At the additive member's confirmed root |
| Source code/tests | In the authorized shared or synchronized worktree |
| History, provenance, decisions, state, ledger | Internal Scribe under the owning `squadRoot` |

Only Markdown, JSON, and text reports travel in the envelope. Your agents must
honor the passed roots instead of their own defaults. All connector dispatches
append to `history/Squad Connector.md`; when multiple roles are connected, each
binding's unique `Member Name` disambiguates the entries and gives each
connected role its own row in `consumption.md`, marking external work
`external, unverified`.
The ledger measures the shim, not your external workflow's spend.

On a confirmed unbind or identity-changing rebind, the internal Scribe appends a
`Connector Binding Retirement` decision to the owning squad's `decisions.md`
before changing the active rows. It records the prior validated identity, the
operator confirmation, and the exact completed history headings being retained.
Completed history and its Attribution rows stay intact; this evidence cannot
authorize a new dispatch or an unlisted entry. A default-only refresh does not
retire an unchanged identity.

Bindings belong to this squad. Federation promotion carries them with its roster,
not to federation-global authority. Tracking roots are rebased; mailbox/manifest
paths remain transport configuration. Complete or abandon pending exchanges
before promotion, then create fresh requests with the new roots.

## Copy the templates

The published [inline template section](../../connector.html#copy-the-templates)
has a copy button and a download link for each file:

| Save in your project | Source template |
|---|---|
| `connectors/research-agent.json` | [Research manifest](./manifest.research-agent.1.1.json) |
| `connectors/delivery-workflow.json` | [Developer workflow manifest](./manifest.delivery-workflow.1.1.json) |
| `connectors/specialists.json` | [Optional specialist manifest](./manifest.capability-assessor.1.1.json) |
| `.github/agents/consumer-research.agent.md` | [Research agent starter](./agents/consumer-research.agent.md) |
| `.github/agents/consumer-implementation-orchestrator.agent.md` | [Implementation coordinator starter](./agents/consumer-implementation-orchestrator.agent.md) |
| `.github/agents/consumer-implementation.agent.md` | [Implementation worker](./agents/consumer-implementation.agent.md) |
| `.github/agents/consumer-validation.agent.md` | [Validation worker](./agents/consumer-validation.agent.md) |
| `.github/agents/consumer-capability-assessor.agent.md` | [Optional specialist](./agents/consumer-capability-assessor.agent.md) |

Reuse your existing agents instead of copying starters when they already meet
the [compatibility checklist](./COMPATIBILITY-CHECKLIST.md). The
[single-agent envelopes](./delegation-request.agent.1.1.sample.json) and
[workflow envelopes](./delegation-request.1.1.sample.json) are protocol examples
for adapter authors, not files you copy into the mailbox to register a connector.
