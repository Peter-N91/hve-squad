# Coach Source Discovery

The Coach learns workflows from the selected installation, not from a maintained list of features. Read this contract; read the discovered sources only as needed for the user's demand.

## Deterministic Inventory

`scripts/Get-SquadCoachContext.ps1`, relative to the `squad` skill, enumerates source paths, headings, entrypoint metadata, script parameters, and existing state without writing files or executing discovered code. It works before initialization.

Its `tracking` object lists directories and file paths throughout the project's `.copilot-tracking/`, including unrecorded artifacts outside `squad/`. These are pointers, not artifact ownership or evidence that other source-defined locations have been inspected.

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

## Retrieval Completeness

Search matches locate evidence; they do not establish a complete workflow contract. Read the complete owning section or function, including every admission-list item, table row, and conditional branch. A size warning or truncated return is incomplete evidence even when the tool reports success. Locate the relevant heading or function and recover size-limited text with bounded line ranges before claiming readiness. Keyword-only excerpts can omit a prerequisite that does not contain the search terms. An access or policy refusal instead makes the source unavailable: report that gap and do not try alternate routes to read it.

## Prerequisite Closure

Before recommending a transition, trace its admission conditions through the owning implementation, linked prerequisites, seed defaults, and current state. Follow dependencies until each applicable condition has evidence or an explicit gap; do not mistake successful initialization, a file's existence, or a template placeholder for eligible evidence.

Read linked seed/default files themselves when available, not only documentation summarizing them. For each gating condition, state its initial or effective value and the evidence required to become ready. A correct-looking example is not a substitute for checking the installed values.

Bind prerequisite evidence to the producer identity, scope, revision, and observation window its consumer requires. Measurements and comparison artifacts must cover the same operation; exclude preceding setup or unrelated work from the measurement window unless the comparison includes it. Collect and verify evidence at that point in the runbook.

Show a readiness evidence table before runnable transitions:

| Transition | Admission condition | Initial/effective value | Required evidence and source | Preparation / status |
|---|---|---|---|---|

Carry every condition from an owning admission checklist into this table, including conditions defined by linked files. Use one row per predicate; do not collapse a multi-condition gate into one row that hides unread children. Do not report only familiar inputs or file-shape checks. Follow each definition to its actual default or current value; an undefined predicate or unread value is unverified, never ready. Keep dependent work conditional until every applicable row is satisfied, while distinguishing setup that is allowed before the work gate.

Classify conditions as met, unmet or unverified. Put each required preparation step before its dependent transition, naming its owner, real inputs, expected evidence, and verification. Explain the actual blocker and whether approval can resolve it. When preparation itself needs a different safeguard or execution mode, obtain explicit approval for that change rather than silently removing the user's requested protection. If the sources provide no safe preparation path, keep the dependent action blocked and name the missing evidence.

Check every copy-ready block against the current input contract and its prerequisite chain. An unmet or unverified prerequisite must be explained before the block, which stays explicitly conditional until verification. Never fabricate observations, approvals, or state to make a gate pass. Omit unused optional fields instead of inventing negative values. Cite the owning source beside each step, including corrected follow-up steps, and re-read affected sources and state on resumption when their inputs have changed.

## Artifact Scope

Read the workflow's artifact-scope rules and current roster paths, then enumerate the required disk locations, not just state or history. A wider workflow-defined enumeration takes precedence over a cast's current root table; old or unrecorded directories may still contain deliverables. Inspect relevant files before characterizing them. Report an uninspected or inaccessible location as unverified, not absent, and state the scope of any verified absence. A partial inventory is not proof that no artifacts exist.

Resolve expected output paths from the current roster or source-defined defaults before presenting them; do not assume that every deliverable shares the state directory.

The Coach does not install or update releases. Advice adapts after the selected installation changes and affected sources are re-read; it does not promise automatic upgrades or compatibility with every future undocumented change.
