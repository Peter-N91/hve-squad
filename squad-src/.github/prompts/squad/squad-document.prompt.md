---
description: "Searches squad state and artifacts to answer a user's question or produce a focused document, then writes the result to a local file in the requested format without the user needing to read decision logs, history files, or routing tables directly"
agent: Squad Document
argument-hint: "request=... [format={md|html|pdf|docx}] [outputPath=<path>] [squad=<name>]"
---

# Squad Document

## Inputs

* ${input:request}: (Required) What the user wants to find or document — a question, a topic to summarize, or a document to generate. Inferred from the user prompt or conversation when not explicitly provided.
* ${input:format:md}: (Optional, defaults to `md`) Output format: `md`, `html`, `pdf`, or `docx`.
* ${input:outputPath}: (Optional) Local filesystem path for the document. When omitted, the agent writes to `docs/squad-document-<YYYY-MM-DD>.<ext>`.
* ${input:squad}: (Optional) In a federation, the registered sub-squad name to scope the search to. Ignored when the project uses a single squad.

## Requirements

1. Hand `${input:request}` to the Squad Document agent and let its required steps resolve the squad scope, search the artifacts, synthesize the answer, and write the file.
2. Pass `${input:format}`, `${input:outputPath}`, and `${input:squad}` through as-is. The agent owns format fallback, the default output path, and federation scoping.
3. Let the agent own its guardrails: squad state is read-only, every statement is grounded in an artifact, and the output path resolves to the local filesystem.
