# `{{ENDPOINT_NAME}}` external endpoint runbook

This consumer-owned `{{ENDPOINT_KIND}}` was scaffolded for connector
`{{CONNECTOR_ID}}`.

## Endpoint artifacts

{{ENDPOINT_ARTIFACTS}}

The generated skill captures the supplied capability and practice requirements.
Replace every `TODO` before production. Reuse an installed HVE Core or
organization skill when it already owns a requirement; remove duplicated
generated guidance rather than forking it.

## Connect it

1. Review the generated charters and skill.
2. Complete any `TODO`, then test the endpoint directly in its host.
3. Follow `{{CONNECTOR_RUNBOOK_PATH}}` to validate the manifest and exercise the
   removable file-drop runner.
4. Replace `Invoke-ExampleEndpoint` in `{{RUNNER_PATH}}` with the trusted host or
   SDK invocation. Keep credentials in that host's secret store.
5. Configure the adapter's trusted mapping from `{{CONNECTOR_ID}}` to
   `{{ENDPOINT_PATH}}`; the manifest must not contain that path or a command.
6. Register the connector with HVE Squad and run one bounded request end to end.

The generated endpoint does not replace HVE's Coordinator, Scribe, council, or
admission gates. Its output remains external and unverified until reviewed.
