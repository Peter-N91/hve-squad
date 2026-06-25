---
description: "Make the PowerPoint Builder always brand generated decks with the project's own .pptx template, and guide non-technical users to provide one — without any manual setup."
applyTo: "**/.copilot-tracking/ppt/**"
---

# Brand Template for PowerPoint Builds

Apply these rules whenever the PowerPoint Builder or PowerPoint Subagent creates or rebuilds a slide deck in this project. They make every generated deck inherit the organization's branding instead of the plain default look. This instruction ships with the squad and is active automatically — no one needs to copy or edit it.

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
