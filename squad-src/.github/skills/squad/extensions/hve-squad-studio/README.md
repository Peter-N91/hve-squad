<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

# HVE Squad Studio

**HVE Squad Studio** (`hve-squad-studio`) is an opt-in, beginner-friendly visual canvas for **HVE Squad**. It lets non-technical users, first-time AI users, and computer beginners build websites, plans, presentations, and documents through plain-language cards and simple choices instead of typing structured chat commands.

## Where It Runs & How to Install It

**HVE Squad Studio** runs as an interactive side-panel canvas in the **GitHub Copilot app** (and any Copilot host that renders SDK extension canvases).

- **Plugin installation (`hve-squad`) — ready automatically:**
  Add `Peter-N91/hve-squad#plugin` under **Customize → Plugins** in the GitHub Copilot app and install `hve-squad`, then start a new project session. `plugin.json` registers `skills/squad/extensions`, so **HVE Squad Studio** is available right away with no extra setup.
- **APM repository fallback (`apm install`) — one-time helper step:**
  Because APM `0.29.0` deploys skill directories under `.agents/skills/squad/` rather than `.github/extensions/`, materialize the extension once into your repository (`.github/extensions/hve-squad-studio/`) or user profile (`~/.copilot/extensions/hve-squad-studio/`):

```powershell
pwsh -File .agents/skills/squad/scripts/Install-SquadStudioExtension.ps1 -Scope repository
```

  Use `-Scope user` to make **HVE Squad Studio** available across all repositories on your machine, then start a new session (or reload extensions).

## How to Start HVE Squad Studio

You **do not** need to select an agent first or run `init` in chat. In a project session inside the GitHub Copilot app, start **HVE Squad Studio** in either of two ways:

1. **Click in the UI:** Open the **Canvas** panel in the session header and choose **HVE Squad Studio**.
2. **Ask in plain language in chat:** Send `Open HVE Squad Studio` in the chat box (with or without an agent selected) and Copilot opens the **HVE Squad Studio** side panel for you.

## Step-by-Step Workflow

1. **Step 1 — Choose What to Build**
   - Pick a starter card (*Website or Landing Page*, *Project or Business Plan*, *Presentation Deck*, *Polished Document or Report*, or *Fix or Improve Existing Files*), or click **Not sure where to start?** for a 3-question guided helper.
   - Optionally drag-and-drop or upload existing notes or documents (`.docx`, `.pdf`, `.pptx`, `.xlsx`, `.md`, `.txt`, `.csv`, `.json`) to run HVE Squad's **Intake Gate** checkup automatically before building.
   - Review any auto-detected **Specialist Add-Ons** (`m365-copilot`, `power-platform`, `dotnet`, `azure-functions`, `aks`, `azure-cloud`, `foundry`, `fabric`, `aws`)—experimental preview helpers stay off by default unless you opt in—and toggle optional **Safety, Budget & Design Checkups** (councils).
   - Choose how HVE Squad works (*Do most of the work for me* vs. *Check with me step by step*), pace/budget (*Best quality*, *Save budget*, *Quick first draft*), and an optional USD spending limit.
   - Click **Start Building with HVE Squad**. Behind the scenes, **HVE Squad Studio** automatically selects `Squad Coordinator` if needed and pre-initializes a **single chosen squad** under `.copilot-tracking/squad/` (`layout: single`, auto-matched `profile`, `naming: skip`, `notify: { approvalChannel: "in-chat", enabled: false }`) via `Get-SquadInitContext.ps1` and `Initialize-Squad.ps1 -Direct`—no `init` questions interrupt you.
2. **Step 2 — Watch Progress & Decide**
   - Watch plain-English progress for your chosen squad, inspect **Document Checkup** (`## Intake Readiness Verdict`) and **Safety, Budget & Design Checkup** (`## Council Verdict`) cards, answer one-question decision cards with a single click (or click **Skip extra checkup** on optional checkups), and follow clear **Allow** cues when the host app asks for a security confirmation.
3. **Step 3 — Your Finished Work**
   - Open finished files directly in your editor, read plain-English summaries, or click one-button adjustments (*Change how it looks*, *Add a feature*, *Fix something*).

## 100% Coexistence with Technical Chat Users

- **Completely opt-in:** Technical users in VS Code, Copilot CLI, and the GitHub Copilot app can continue using chat and slash commands without ever opening **HVE Squad Studio**.
- **Manual-only preference:** Toggle **Keep HVE Squad Studio manual-only (never auto-open)** inside **Settings** (`$COPILOT_HOME/extensions/hve-squad-studio/artifacts/preferences.json`).
- **Zero prompt-budget overhead:** All studio UI and logic live in the extension process, adding 0 bytes to HVE Squad's hot-file and agent prompt budgets.
