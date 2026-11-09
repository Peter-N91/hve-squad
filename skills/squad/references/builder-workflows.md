---
name: squad-builder-workflows
description: "Progressively loaded decisions and scripted workflows for connector and external endpoint builders."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-10-24"
---

# Builder Workflows

The two builders own conversation and decisions. These scripts own repeatable
filesystem work:

| Script | Deterministic responsibility |
|---|---|
| `scripts/New-SquadConnector.ps1` | Render a 1.1 manifest, mailbox guidance, examples, removable runner, and connector runbook |
| `scripts/New-SquadExternalEndpoint.ps1` | Create endpoint/worker charters and a skill, or preserve an existing implementation and add only integration artifacts |
| `scripts/Test-SquadConnectorManifest.ps1` | Reuse the connector validator and reject placeholders or inconsistent builder values |

Resolve scripts relative to the installed `squad` skill. Typical roots are
`.agents/skills/squad/` for APM and `skills/squad/` for a plugin. Do not copy
their implementation into the agent response.

## Connector builder

### Decision order

1. **Mode** — configured interactive scaffold or editable template.
2. **Destination** — an existing trusted repository root.
3. **Identity** — a stable lower-kebab-case connector id.
4. **Endpoint kind** — `agent` for one endpoint result or `orchestrator` for
   output-slot fan-out.
5. **Capabilities and roles** — factual capabilities and ordinary work-role
   allowlist. HVE coordinators, Scribe, and council cannot be connected.
6. **Operations** — non-secret contact, endpoint version, positive deadline,
   and non-negative retry cap.

Never collect a token, password, connection string, private key, or executable
command. The contract's closed manifest has no place for them.

### Configured invocation

After preview and confirmation, pass arrays as arrays rather than comma-joined
text:

```powershell
pwsh -File "<skill-root>/scripts/New-SquadConnector.ps1" `
  -WorkspaceRoot "<repository-root>" `
  -ConnectorId "org-research" `
  -EndpointKind agent `
  -Capabilities @("Researches approved repository sources") `
  -Roles @("researcher") `
  -Contact "integrations@example.invalid"
```

Then validate:

```powershell
pwsh -File "<skill-root>/scripts/Test-SquadConnectorManifest.ps1" `
  -ManifestPath "<repository-root>/connectors/org-research.json"
```

### Editable-template invocation

```powershell
pwsh -File "<skill-root>/scripts/New-SquadConnector.ps1" `
  -WorkspaceRoot "<repository-root>" `
  -EditableTemplate
```

Report all four placeholders:

* `REPLACE_CONNECTOR_ID`
* `REPLACE_CAPABILITY`
* `REPLACE_ROLE`
* `REPLACE_CONTACT`

Validation must remain red until they are resolved.

### Output and runner

A configured run creates:

* `connectors/<id>.json`;
* `.connector-drops/README.md` and an endpoint mailbox;
* request/result examples under `connectors/examples/`;
* `scripts/Run-<id>-Connector.ps1`;
* `docs/<id>-connector-runbook.md`.

The runner is executable with PowerShell 7.4 and needs no credential. It polls
only requests, ignores snapshots/private state, writes new example artifacts
under request-declared roots, and atomically publishes a result. It deliberately
produces a transport receipt rather than pretending to perform domain work.
Users replace `Invoke-ExampleEndpoint`, replace the whole runner, or remove it.

## External agent/orchestrator builder

### Decision order

1. **Action** — create or adapt. Adaptation never modifies the existing path.
2. **Endpoint kind** — standalone `agent` or multi-agent `orchestrator`.
3. **Execution environment** — the consumer's actual host, SDK, CLI, worktree,
   and secret store. These inform the runbook, never the manifest.
4. **Responsibilities** — bounded, non-overlapping duties. Each responsibility
   becomes a worker in orchestrator create mode.
5. **Skills** — inspect installed HVE Core and consumer skills by exact name.
   Reuse a matching skill. Supply only missing practice requirements to the
   generated editable skill.
6. **Connector values** — capabilities, roles, contact, version, deadline, and
   retry cap as above.

### Create invocation

```powershell
pwsh -File "<skill-root>/scripts/New-SquadExternalEndpoint.ps1" `
  -WorkspaceRoot "<repository-root>" `
  -Mode Create `
  -ConnectorId "org-delivery" `
  -EndpointKind orchestrator `
  -Capabilities @("Implements bounded changes", "Validates changes") `
  -Roles @("developer") `
  -Responsibilities @("Implement the approved change", "Validate the resulting diff") `
  -SkillRequirements @("Follow repository conventions", "Run existing tests") `
  -Contact "integrations@example.invalid"
```

Create mode adds a user-invocable endpoint, non-user-invocable workers when
needed, an editable consumer skill, connector artifacts, and separate endpoint
and connector runbooks. Missing skill requirements remain an explicit `TODO`;
the builder must name it.

### Adapt invocation

```powershell
pwsh -File "<skill-root>/scripts/New-SquadExternalEndpoint.ps1" `
  -WorkspaceRoot "<repository-root>" `
  -Mode Adapt `
  -ConnectorId "org-existing-research" `
  -EndpointKind agent `
  -Capabilities @("Researches approved sources") `
  -Roles @("researcher") `
  -Responsibilities @("Return a cited research note") `
  -ExistingPath "tools/existing-research-agent" `
  -Contact "integrations@example.invalid"
```

Adapt mode checks that the path exists, never edits it, and creates the
connector artifacts plus `docs/<id>-adaptation-runbook.md`. That runbook maps
request fields and output envelopes to the existing implementation and explains
where missing native-host skills must be installed.

## Safe reruns and completion

Every script preflights its complete write plan. Existing byte-identical files
are reported `unchanged`; any differing file aborts the entire write before a
new file is created. There is no force switch. To adopt new generated content,
the consumer compares and edits it deliberately.

Before completion:

1. Parse the script's JSON result.
2. Require manifest validation `status: ok` for configured output.
3. Name generated paths, unchanged paths, conflicts, and placeholders.
4. Give the exact `-Once` runner command and prerequisites.
5. Explain direct endpoint testing, trusted adapter mapping, connector
   registration, first dispatch (`awaiting`), same-task resume, and human review
   of external results.
6. Remind the user that no credential was generated or requested.