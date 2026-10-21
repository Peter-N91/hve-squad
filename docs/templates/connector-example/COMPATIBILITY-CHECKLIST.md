---
title: Squad Connector compatibility checklist
description: Standalone, copyable restatement of connector-contract.md's Compatibility Checklist for Consumers section.
---

# Squad Connector Compatibility Checklist

Copy this file alongside a new connector's own documentation and check off
each item before registering the connector against a role. Every item below
restates a requirement from
[`connector-contract.md`](../../../squad-src/.github/skills/squad/references/connector-contract.md)'s
own *Compatibility Checklist for Consumers* section; that file is normative
and this one is a convenience copy.

* [ ] Authors one manifest per connector, validating clean against the closed
      Manifest Schema (no extra fields, `transport: "file"`, no secret-shaped
      content).
* [ ] Treats requests as bounded, idempotent work units. A duplicate
      `taskId` is replay and is rejected rather than re-executed.
* [ ] Watches or polls the manifest's `dropPath` for `*.request.json`, by
      whatever means it chooses, and ignores the shim-owned `*.snapshot.json`
      collision baseline and private `.squad-connector` lifecycle state.
* [ ] Writes back exactly one result envelope per `taskId`, never reusing a
      `taskId` and never writing to a `dropPath` it was not given.
* [ ] In 1.1 mode, echoes and binds trusted identity fields correctly:
      `connectorId`, `bindingId`, `taskId`, and only declared `outputId`
      values from `allowedOutputs`.
* [ ] Writes each task-owned artifact directly under the `deliverableRoot` (or
      declared `allowedOutputs[].deliverableRoot` slot) named in the matching
      delegation-request before publishing `<taskId>.result.json`, as one of
      `md`, `json`, or `txt`, within the numeric caps in *Envelope Artifact-Path
      Validation Rules*, without overwriting any pre-existing file.
* [ ] Honors `deadline` and `retryCap`; a coordinator with a failure result
      writes `status: "failed"`, while an unanswered request reaches
      `unreachable` when its deadline or retry cap is exhausted rather than
      fabricating completion. A present terminal result is still validated;
      lateness alone does not make a correctly bound result unsolicited.
* [ ] Never embeds credentials, tokens, or other secret-shaped content in the
      manifest, request, or result.
* [ ] Never emits action fields (`command`, `exec`, `script`, `url`, `fetch`)
      or any undeclared schema fields in manifest/request/result payloads.
* [ ] Never writes squad state and never claims role authority, council
      membership, gate outcomes, or approval authority.
* [ ] Treats its own `narrative` as a summary a human and an automated
      validator both read as data — never as a vehicle for steering what the
      squad does next.
* [ ] If the endpoint is an orchestrator, discloses internal fan-out while
      returning one bounded result envelope that maps all artifacts to declared
      outputs only.
* [ ] Loads the consumer's required skills explicitly and reports a missing
      skill, worker, or tool as failure rather than substituting another method.
* [ ] Uses top-level `artifacts` for a single agent; an orchestrator instead uses
      empty top-level `artifacts` and declared `outputs[]`.
* [ ] Publishes complete results atomically and durably tracks claimed/consumed
      task ids so restarts cannot execute or accept the same task twice.
      Preserves the shim's `.squad-connector` state without editing it; producer
      execution deduplication and the shim's result-consumption record are separate.
* [ ] Gives every additive capability a validated manifest role, unique member,
      binding, route, resolved alignment, and explicit deliverable root.
* [ ] Keeps worktree source changes separate from transported report artifacts;
      parallel writers have independent approved scopes, not merely separate reports.
* [ ] Tests the real consumer-host round trip and checks Scribe history and
      member/binding attribution under the owning squad, including federation use.
