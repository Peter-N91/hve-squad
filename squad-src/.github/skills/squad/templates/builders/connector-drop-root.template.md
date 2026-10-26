# Squad Connector mailboxes

Each child directory is a file-drop mailbox for one connector. HVE Squad owns
`*.snapshot.json`, `*.request.json`, and `.squad-connector/`. The external
runner owns `*.result.json` and task artifacts only.

Run only trusted, consumer-owned adapters. Never place credentials here, never
edit snapshots or private state, and never use this directory as the final
report location. Copy example envelopes from `connectors/examples/`; do not put
them into a live mailbox.
