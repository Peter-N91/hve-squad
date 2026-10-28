# `{{CONNECTOR_ID}}` connector runbook

## Generated files

* Manifest: `{{MANIFEST_PATH}}`
* Mailbox: `.connector-drops/{{CONNECTOR_ID}}/`
* Removable runner: `{{RUNNER_PATH}}`
* Request/result examples: `{{REQUEST_EXAMPLE_PATH}}` and
  `{{RESULT_EXAMPLE_PATH}}`

The manifest uses connector contract 1.1, endpoint kind `{{ENDPOINT_KIND}}`,
and file transport. It contains no command, agent path, or credentials.

## Prerequisites

1. Install PowerShell 7.4 or newer.
2. Install an HVE Squad version that supports connector contract 1.1.
3. Review the manifest's roles, capabilities, contact, deadline, and retry cap.
4. Keep the repository and every output root on a trusted local filesystem.

## Validate

From an APM installation:

```powershell
pwsh -File ".agents/skills/squad/scripts/Test-SquadConnectorManifest.ps1" -ManifestPath "{{MANIFEST_PATH}}"
```

From the plugin layout, use
`skills/squad/scripts/Test-SquadConnectorManifest.ps1` instead. A valid run
returns JSON with `status: "ok"`. Resolve every reported issue before
registration.

## Exercise the removable runner

Poll once without waiting:

```powershell
pwsh -File "{{RUNNER_PATH}}" -Once
```

Run continuously (Ctrl+C stops it):

```powershell
pwsh -File "{{RUNNER_PATH}}"
```

The default runner is a transport demonstration. It writes a clearly labelled
Markdown receipt rather than invoking an AI service, so it needs no credential.
Replace `Invoke-ExampleEndpoint` with your trusted host/SDK call, or delete the
script and implement the same request/result contract yourself. Do not add an
execution field to the closed manifest schema.

## Register and run

1. Start the real adapter or the removable runner.
2. Ask the Squad Coordinator to register `{{MANIFEST_PATH}}` for one of these
   allowed roles: {{ROLES}}.
3. Confirm `replace` or `add`, the target member, deliverable root, and default
   execution. HVE coordinators, Scribe, and council remain internal.
4. Run a bounded Squad request. The first dispatch publishes a request and
   returns `awaiting`; resume the same task id after the adapter publishes its
   result.
5. Review every external result as `external, unverified`.

## Customize and rerun safely

Edit the manifest, generated agent files, skills, and runner in your repository.
Re-running the builder is a no-op only when every generated file is
byte-identical. If any file was customized, the builder stops before writing
anything and lists the conflicts; it never silently overwrites user work.
