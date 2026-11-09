---
name: squad-document
description: "Searches squad state and artifacts to answer a question or produce a focused document (md/html/pdf/docx) without the user reading decision logs or routing tables directly. Use when the user asks the squad to summarize, document, or answer a question from its own history."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
---

# Squad Document

## Inputs

* **request** (required): What to find or document — a question, a topic to summarize, or a document to generate. Inferred from the caller's prompt or the conversation when not explicitly provided.
* **format** (optional, defaults to `md`): Output format — `md`, `html`, `pdf`, or `docx`.
* **outputPath** (optional): Local filesystem path for the document. When omitted, write to `docs/squad-document-<YYYY-MM-DD>.<ext>`.
* **squad** (optional): In a federation, the registered sub-squad name to scope the search to. Ignored when the project uses a single squad.

## Flow

1. Hand **request** to the Squad Document agent and let its required steps resolve the squad scope, search the artifacts, synthesize the answer, and write the file.
2. Pass **format**, **outputPath**, and **squad** through as-is. The agent owns format fallback, the default output path, and federation scoping.
3. Let the agent own its guardrails: squad state is read-only, every statement is grounded in an artifact, and the output path resolves to the local filesystem.

## Invocation

Dispatch this request to the `Squad Document` agent. This skill does not perform the search or synthesis itself — it only resolves which parameters to pass.