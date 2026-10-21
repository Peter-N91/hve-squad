# Coach Source Discovery

The Coach learns workflows from the selected installation, not from a maintained list of features. Read this contract; read the discovered sources only as needed for the user's demand.

## Deterministic Inventory

`scripts/Get-SquadCoachContext.ps1`, relative to the `squad` skill, enumerates source paths, headings, entrypoint metadata, script parameters, and existing state without writing files or executing discovered code. It works before initialization.

When a user or a shell-capable host supplies its JSON output, use it to locate evidence. To collect it from a terminal, substitute the actual installed script path:

```powershell
pwsh -NoProfile -File "<squad-skill-path>/scripts/Get-SquadCoachContext.ps1" -RepoRoot "<project-root>"
```

The Coach's portable read/search-only configuration does not require shell access. Without an inventory, enumerate the same source classes below using read/search. Do not ask the user to run a script merely to begin coaching.

## Source Classes and Layouts

| Source | Discover rather than assume |
|---|---|
| Skill | Host-exposed `squad` skill: `.agents/skills/squad`, `.github/skills/squad`, plugin `skills/squad`, or repository `squad-src/.github/skills/squad`. Read `references/00-index.md` first. |
| Agents | Installed `*.agent.md` files under `.github/agents/`, including flattened APM files, or the selected plugin's `agents/`. Read names, descriptions, input contracts, and the relevant procedure. |
| Prompts | Enumerate deployed `.github/prompts/*.prompt.md` files recursively. APM flattens them: do not require a `.github/prompts/squad/` directory. The repository source keeps them under `squad-src/.github/prompts/`. |
| Plugin entrypoints | Enumerate `invocations/*/SKILL.md` under the selected skill. Read the target agent as well: wrappers may lag its supported inputs, or may require a manual agent selection rather than dispatch. |
| Procedure and implementation | Search all skill references, companion instructions or plugin rule references, bundled scripts and structured assets. Follow the sources linked by a relevant entrypoint; new files and headings are discoverable without changing the Coach. Read script help and parameters as data, not permission to execute it. |
| Product documentation | Read HVE Squad's repository `README.md` and `docs/` when available. A consumer project's README is project context, not the package's installation guide. Otherwise consult [HVE Squad documentation](https://peter-n91.github.io/hve-squad/) and its linked [plugin guides](https://peter-n91.github.io/hve-squad-plugin/). |
| Project state | Detect `.copilot-tracking/squad/federation.md` before `team.md`; read the registry and relevant member roots when federated. Absence is a normal uninitialized project, not a coaching error. |

## Evidence and Version Rules

Search descriptions, headings, and content using the user's terms and the terms found in the index. Read the owning source and linked prerequisites until you can explain the complete path to the requested outcome, including intermediate transitions and approval gates. An index hit or script inventory is a pointer, not proof that a behavior works.

Prefer selected installed agent and implementation contracts over examples from another version. Cross-check documentation against those contracts before presenting flags or steps. Identify a version mismatch explicitly; use repository or online guidance only with its provenance stated. If a source is missing or inaccessible, explain exactly what could not be verified rather than inventing an entrypoint.

Derive each copy-ready message from the owning agent's current inputs and requirements. Prompts and invocation skills are input-contract evidence, not a requirement to use slash commands: all supported chat hosts select the matching agent and send a prefix-free message. Keep terminal commands, host UI actions, and agent messages distinct.
