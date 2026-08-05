---
description: "Searches squad state and artifacts to answer a user's question or produce a focused document, then writes the result to a local file in the requested format without the user needing to read decision logs, history files, or routing tables directly"
argument-hint: "request=... [format={md|html|pdf|docx}] [outputPath=<path>] [squad=<name>]"
---

# Squad Document

Search squad state — decisions, history, routing, roster, and any documentation under `docs/` — to answer a question or produce a focused document. The user supplies a request in natural language; this command finds the relevant artifacts, synthesizes a grounded answer, and writes it to a local file in the requested format.

## Inputs

* ${input:request}: (Required) What the user wants to find or document — a question, a topic to summarize, or a document to generate. Inferred from the user prompt or conversation when not explicitly provided.
* ${input:format:md}: (Optional, defaults to `md`) Output format. Accepted values: `md` (Markdown), `html` (self-contained HTML page), `pdf` (PDF via available tooling), `docx` (Word document via the `md-to-docx` skill). When a value is not recognized, fall back to `md` and inform the user.
* ${input:outputPath}: (Optional) Absolute or relative local filesystem path where the document should be saved. When omitted, write to `docs/squad-document-<YYYY-MM-DD>.<ext>` in the working directory.
* ${input:squad}: (Optional) In a federation, the registered sub-squad name to scope the search to (for example, `squad=product`). When omitted in a federation, search across all sub-squads. Ignored when the project uses a single squad.

## Workflow

### Step 1: Detect squad mode and resolve scope

Check `.copilot-tracking/squad/` for the presence of state files:

1. **`federation.md` present** — federation mode. When `${input:squad}` is provided, scope all reads to `.copilot-tracking/squad/members/<squad>/`. When omitted, search across all sub-squads listed in `federation.md`.
2. **No `federation.md`, but `team.md` present** — single-squad mode. Scope reads to `.copilot-tracking/squad/`.
3. **Neither present** — no squad initialized. Stop and inform the user: "No squad state found. Run `/squad` to initialize a squad first."

### Step 2: Search squad artifacts

Read the scoped squad state files and collect content relevant to `${input:request}`:

* `decisions.md` — squad decisions with timestamps and rationale.
* `history/<agent>.md` — per-agent dispatch history and outcomes.
* `team.md` — roster, roles, and member capabilities.
* `routing.md` — request-to-role routing patterns.
* `state.json` — current squad status and configuration.
* `consumption.md` — usage and cost tracking.
* Files under `docs/` — existing project documentation.

Filter and rank by relevance to the request. When in federation mode without a `${input:squad}` scope, prefix findings with the sub-squad name they came from.

### Step 3: Synthesize

Produce a focused, well-structured document that answers `${input:request}`:

* Ground every statement in a squad artifact. Cite the source file for key facts.
* When information is missing from the artifacts, mark the gap as an explicit **Open Question** rather than inventing content.
* Use headings, lists, and tables to organize the answer clearly.
* Follow the repository's markdown and writing-style instruction files.

### Step 4: Format and write

Render the synthesized content in `${input:format}`:

* **`md`** — write the Markdown content directly.
* **`html`** — convert Markdown to a self-contained HTML page using the `markdown-to-html` skill. Include a clean stylesheet, a `<title>` derived from the request, and a `<main>` element containing the rendered content.
* **`pdf`** — attempt generation via an available PDF skill or tool. When PDF tooling is unavailable, fall back to `md`, write the Markdown file, and inform the user: "PDF generation is not available in this environment. The document was written as Markdown instead."
* **`docx`** — convert the synthesized Markdown to a professionally formatted Word document using the `md-to-docx` skill. Write the Markdown to a temporary `.md` file, run the bundled conversion script (`node skills/md-to-docx/scripts/md-to-docx.mjs <input.md> <output.docx>`), and remove the temporary file after conversion succeeds. When Node.js or the `md-to-docx` skill is unavailable, fall back to `md` and inform the user.

Write to `${input:outputPath}` when provided. Otherwise, derive the filename as `docs/squad-document-<YYYY-MM-DD>.<ext>` (for example, `docs/squad-document-2026-08-01.md`). Create the target directory if it does not exist.

### Step 5: Confirm

Report to the user:

* **Path** — the file written.
* **Format** — the format used (and whether a fallback occurred).
* **Grounding** — the squad artifacts that sourced the content.
* **Open Questions** — gaps the artifacts did not answer, or `none`.

## Guardrails

* Squad state is **read-only** input to this command. Never modify, delete, or append to any squad state file.
* Ground every statement in squad artifacts. Never invent or hallucinate content that is not evidenced by the files read.
* When the requested format is unavailable (missing skill, runtime, or tooling), fall back to Markdown and inform the user rather than failing.
* Respect federation boundaries: when `${input:squad}` scopes to a sub-squad, do not read other sub-squads' state.
* Output path must resolve to the **local filesystem**. Never write to remote locations, URLs, or shared drives.
* This command does not persist squad state, dispatch history, or consumption tracking. It is a search-and-export tool, not a squad deliverable.
