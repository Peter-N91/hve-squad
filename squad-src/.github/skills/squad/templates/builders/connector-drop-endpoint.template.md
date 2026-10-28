# `{{CONNECTOR_ID}}` mailbox

The manifest at `{{MANIFEST_PATH}}` points here. The removable example runner
polls only `*.request.json`, ignores `*.snapshot.json` and
`.squad-connector/`, writes task artifacts under request-declared output roots,
then atomically publishes one matching `*.result.json`.

Start it from the repository root:

```powershell
pwsh -File "{{RUNNER_PATH}}"
```

Use `-Once` for one non-blocking poll. Replace or remove the runner when your
real agent host or orchestrator handles this mailbox.
