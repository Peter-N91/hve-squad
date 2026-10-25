# Adapt `{{EXISTING_PATH}}` for HVE Squad

The existing implementation remains consumer-owned and was not modified.
Integration artifacts were generated for connector `{{CONNECTOR_ID}}`:

* Manifest: `{{MANIFEST_PATH}}`
* Removable transport runner: `{{RUNNER_PATH}}`
* Connector runbook: `{{CONNECTOR_RUNBOOK_PATH}}`

## Adaptation steps

1. Map the request's bounded task, deadline, role, and declared output slots to
   the existing `{{ENDPOINT_KIND}}` without widening its authority.
2. Replace `Invoke-ExampleEndpoint` in the removable runner with the trusted
   invocation of `{{EXISTING_PATH}}`, or implement an equivalent adapter.
3. Map existing outputs back to relative `md`, `json`, or `txt` artifact paths.
   For an orchestrator, return only declared `outputId` values.
4. Keep credentials in the existing host's secret store. Never put commands,
   URLs, tokens, agent paths, or credentials in the closed connector manifest.
5. Validate with `Test-SquadConnectorManifest.ps1`, test one sample request in a
   disposable worktree, then register the connector with HVE Squad.

If the implementation lacks a required skill, add it in its native host or run
the builder again in create mode to generate editable skill guidance. Do not
replace working consumer code merely to match these examples.
