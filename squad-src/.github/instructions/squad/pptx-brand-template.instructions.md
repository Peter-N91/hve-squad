---
description: "Reference only: brand-template guidance for slide decks. The powerpoint skill and PowerPoint agents were removed upstream at hve-core f425e94, so the squad ships no deck pipeline."
applyTo: "**/.copilot-tracking/ppt*/**, **/.copilot-tracking/squad/**/ppt*/**"
---

# Brand Template for Slide Decks (reference only)

The `powerpoint` skill (`build_deck.py`, `Invoke-PptxPipeline.ps1`) and the `PowerPoint Builder` and `PowerPoint Subagent` agents were removed upstream at hve-core f425e94. The squad no longer has a `presenter` role or a deck pipeline, and this capability is no longer available from the squad. The guidance below is retained only for consumers who supply their own pptx tooling; it does not name a replacement skill.

**Never author a substitute deck builder on the squad's behalf.** A one-off script against `pptxgenjs`, `python-pptx`, or another library silently drops the brand template, theme colors, and layout conventions. When a deck is requested, say plainly that the squad has no deck pipeline and return the request to the user.

## Brand template location

The project's branded PowerPoint template lives at:

```text
.github/brand/pptx-brand-template.pptx
```

Treat that path as the single source of branding.

## When the template exists

* **Full rebuild / new deck**: pass the brand template to `build_deck.py` as `--template` (PowerShell `-TemplatePath`). This inherits the template's slide masters, layouts, and theme (colors and fonts) while discarding the template's own example slides. Only the slides defined under `content/` are added.
* **Partial rebuild** (updating specific slides in an existing deck): use `--source` pointing at the existing deck plus `--slides`. Do **not** pass `--template` for partial rebuilds — it would discard every slide not listed in `--slides`.
* **Never combine** `--template` and `--source` in the same command.

## When the template is missing

Do not silently produce a plain, unbranded deck. Many users are non-technical and will not know to add a template. Instead:

1. Tell the user, in plain language, that no branded template was found and that adding one makes every deck look on-brand.
2. Offer to use a template they provide. If they share a `.pptx` (a path, an attached file, or a file already in the workspace), copy it to `.github/brand/pptx-brand-template.pptx` for them — create the `.github/brand/` folder if needed — and then build with it. The user never has to navigate folders or edit files.
3. If the user confirms they have no template, build with the skill defaults this once, and remind them they can drop a branded `.pptx` in at any time and ask the squad to save it.

## Content rules

* In `content/global/style.yaml`, set `template.path` to the brand template and map content layout names to the template's named layouts under `layouts` (for example `title`, `content`, `section`).
* In each slide's `content.yaml`, reference colors with `@theme_name` rather than hardcoded hex values so slides adapt to the brand theme.
* Always run the Validate pipeline after building and resolve its findings before finalizing the deck.
