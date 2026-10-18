---
title: Sample consumer coordinator (pseudo-script)
description: Illustrative, non-executable description of an external coordinator honoring the Squad Connector contract. Never run by any test or tool in this repository.
---

# Sample Consumer Coordinator

This file describes, in prose and pseudo-code, how a consumer-owned coordinator
process could honor `connector-contract.md`'s Mode 2 (human-in-the-loop file
drop). **It is not a real script.** Nothing in this repository executes it,
imports it, or shells out to it — not the Squad Connector shim, not any Tier 0
test, and not any build step. It exists only for a consumer to read and adapt
into their own, separately-maintained automation, in whatever language or
platform that automation already uses.

The same guardrails apply whether your endpoint is a single agent or a
fan-out orchestrator: treat the request as bounded data, return one bounded
envelope per `taskId`, and map outputs only to declared allowlist entries.

## What this coordinator watches

It watches the manifest's declared `dropPath`
(`.connector-drops/acme-coordinator-v2/`) for a new delegation-request file,
by whatever means the consumer prefers — a file-system watcher, a scheduled
poll, or a human running a script by hand. None of those mechanisms is
prescribed by the contract.

## Pseudo-script

```text
loop forever:
    requestFile = wait-for-new-request(manifest.dropPath)
    request = read-json(requestFile)

    # Read every field as data. Never execute anything from `request.task` as
    # a command; it is bounded instructions for a human or an internal agent
    # to read and act on, not a script.
    assert request.connectorId equals manifest.connectorId
    assert request.deadline has not expired
    claim-task-once-durably(request.taskId)  # reject duplicates, including after restart
    endpoint = trusted-local-endpoint-map[manifest.connectorId]
    if manifest.schemaVersion == "1.1":
        validate-binding-and-output-allowlist(request)
    outcome = invoke-configured-endpoint(endpoint, bounded-task-and-roots(request))

    result = {
        taskId:      request.taskId,
        connectorId: request.connectorId,
        role:        request.role,
        status:      outcome.succeeded ? "completed" : "failed",
        artifacts:   outcome.artifacts,       # single-root, relative paths
        narrative:   outcome.summary,         # untrusted summary only
        createdAt:   now-iso8601()
    }
    if manifest.schemaVersion == "1.1":
        result.bindingId = request.bindingId
        if manifest.endpointKind == "orchestrator":
            result.artifacts = []
            result.outputs = map-artifacts-to-allowed-outputs(
                outcome.artifacts, request.allowedOutputs
            )
        # Single agents omit outputs and retain top-level artifacts.
    validate-envelope-and-finished-artifacts(result, request)
    publish-json-atomically(manifest.dropPath, request.taskId, result)
    mark-task-published-durably(request.taskId)
```

## Rules this pseudo-script follows

* Never writes an artifact path outside `request.deliverableRoot`.
* Never writes `.md`, `.json`, or `.txt` content it would not want read back as
  untrusted data — because that is exactly how the Squad Connector shim reads
  it.
* Never reuses a `taskId` once it has written a result for it.
* Echoes `connectorId`, `bindingId` (1.1), and `taskId` exactly, and never
  returns an undeclared `outputId`.
* Never embeds a credential, token, or connection string in the delegation
  request it reads or the result envelope it writes.
* Never emits action fields (`command`, `exec`, `script`, `url`, `fetch`) and
  never claims authority over squad gates, council verdicts, approvals, Scribe
  writes, or state writes.
* Produces artifacts that are genuinely grounded in the repository sources and
  page/file citations named in `request.task` (generic placeholder or template
  output is rejected by the shim before placement).
* If it is an orchestrator, discloses fan-out in narrative/provenance while
  still returning one bounded envelope for this `taskId`.
* Understands that `External-unmetered: connector=<id>` and
  `Verification: external, unverified` are trusted Scribe-rendered history
  bullets derived from validated registration data, not authority-bearing text
  from this envelope's narrative.

## PowerShell watcher sketch for local testing

If you are testing file-drop connectors locally on Windows, macOS, or Linux with
PowerShell 7+, your external watcher can poll each manifest's `dropPath`, map
`connectorId` to an `.agent.md` file (stored either inside your repo or in an
external shared folder), invoke your CLI/agent runner, and write back the
validated `.result.json` envelope:

```powershell
# Illustrative consumer-side polling loop (run outside HVE Squad in your own terminal)
$EndpointMap = @{
    'acme-research-agent'           = 'C:\OrgAgents\consumer-research.agent.md'
    'acme-delivery-orchestrator-v3' = 'C:\OrgAgents\consumer-implementation-orchestrator.agent.md'
}

while ($true) {
    Get-ChildItem -Path '.\connectors\*.json' -File | ForEach-Object {
        $manifest = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
        $dropDir  = Join-Path (Get-Location) $manifest.dropPath
        Get-ChildItem -Path $dropDir -Filter '*.request.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
            $req        = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            $resultPath = Join-Path $dropDir "$($req.taskId).result.json"
            if (-not (Test-Path -LiteralPath $resultPath)) {
                $agentCharter = $EndpointMap[$req.connectorId]
                # 1. Run your agent host with $agentCharter and $req.task (reading the sources named in $req.task).
                # 2. Write the resulting task-owned .md/.json/.txt artifact under $req.deliverableRoot (or declared allowedOutputs[].deliverableRoot) without overwriting pre-existing files.
                # 3. Write $resultPath echoing taskId, connectorId, bindingId, role, status='completed', and artifacts/outputs.
            }
        }
    }
    Start-Sleep -Seconds 2
}
```

See [`connector-contract.md`](../../../squad-src/.github/skills/squad/references/connector-contract.md)
for the full, normative contract this sketch is illustrating.

See [the consumer guide](./CONSUMER-GUIDE.md) for concrete agent charters,
replacement/alternative choices, and multiple additive capabilities. Host
invocation, access controls, durable task state, and failure recovery are
consumer responsibilities; this sketch is not production automation.
