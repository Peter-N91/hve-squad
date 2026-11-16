---
name: squad-fabric-blueprint
description: "Opt-in Fabric and Power BI official pack: data-scientist ownership, pinned skills, installation readiness, complete support roots, parity supersession, and boundaries."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-11-15"
---
<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

# Fabric and Power BI Official Pack

Read this reference for a `fabric` proposal's resource preflight, or when the resolved root's `team.md` `Packs:` line includes `fabric`. A proposal permits explanation, not skill selection or installation. A present `data-scientist` role does not activate the pack. Removing the pack stops this guidance and stops squad selection of the skills below. It does not uninstall or hide a host-installed skill.

Host visibility is not selection. A declined resource stays unavailable to the squad even if the host exposes it.

The pack adds no new catalog role and no external agent Primary or Alternate. `data-scientist` (`Squad Data Scientist`) is the only owner. `full +fabric` and `product +fabric` add no roles; a profile that lacks `data-scientist`, such as `default` or `azure`, adds `data-scientist` and no other role. An unpacked squad keeps `data-scientist`'s HVE Core skills (`data-catalog`, `analysis-authoring`, `dataops`, `feasibility`, `ml-experimentation`, `evaluation-design`) unchanged.

## Admitted skills

Select one admitted skill only for its cue while `fabric` is active and its disposition is not `declined`.

| Skill | Select when | Do not select when |
|---|---|---|
| `semantic-model-authoring` | Power BI semantic model design or review, star schema, relationships, Import/DirectQuery/Direct Lake storage modes, TMDL/PBIP model authoring, field parameters, DAX measures/UDFs, DAX performance optimization (`DAX001`–`DAX021`), Copilot/Data Agent AI readiness, refresh, or connection binding | Report page visual layout or PBIR editing (`powerbi-report-cli`), or Warehouse/SQL endpoint T-SQL (`sqldw-cli`) |
| `powerbi-report-cli` | Power BI report requirements/planning (`_brief/report-spec.md`), visual design and archetypes (`Design Brief:`), visual-budget and accessibility review, local PBIR/PBIP authoring and validation, or explicit user-requested report transport | Semantic model, relationship, or DAX authoring (`semantic-model-authoring`) |
| `e2e-medallion-architecture` | Fabric Lakehouse fundamentals (Files vs Delta Tables, schemas, shortcuts, OneLake security, V-Order, `OPTIMIZE`/`ZORDER`/`VACUUM`), Bronze/Silver/Gold medallion design, Materialized Lake View vs Spark notebook layer selection, and Gold-to-Direct Lake handoff | Single-notebook Spark triage (`spark-cli`) or Warehouse `COPY INTO` (`sqldw-cli`) |
| `sqldw-cli` | Fabric Warehouse, Lakehouse SQL analytics endpoint, or Mirrored Database T-SQL, `COPY INTO`, Query Insights, or Capacity Metrics app CU-spike correlation | A Fabric SQL database OLTP item (`sqldb-cli`) or semantic-model DAX (`semantic-model-authoring`) |
| `sqldb-cli` | A Fabric SQL database OLTP item, including T-SQL, Query Store, blocked-session or regressed-plan triage, and temporal or vector queries | Warehouse, Lakehouse SQL endpoint, or Mirrored Database work (`sqldw-cli`) |
| `eventhouse-cli` | Eventhouse or KQL database work, including tables, functions, policies, KQL materialized views, and read-only KQL | Eventstream topology (`eventstream-cli`), Activator alerts (`activator-cli`), or Spark Materialized Lake Views (`spark-cli`) |
| `eventstream-cli` | A Fabric Eventstream item: sources, operators, destinations, routing, throughput, or retention | KQL database work (`eventhouse-cli`) or Activator alert rules (`activator-cli`) |
| `activator-cli` | Fabric Activator (Reflex) alert inspection and local `ReflexEntities.json` rule, condition, and Teams/email action design | Streaming pipeline routing (`eventstream-cli`) or KQL storage (`eventhouse-cli`) |
| `spark-cli` | A Fabric Spark notebook (`%%configure`, `%%sql`, PySpark, `notebookutils`), Livy session, failed or OOM Spark run triage, or Materialized Lake View (`CREATE MATERIALIZED LAKE VIEW`) lifecycle | Databricks, Synapse, or HDInsight source-code migration (`databricks-migration`, `synapse-migration`, `hdinsight-migration`) |
| `dataflows-cli` | A Dataflow Gen2 item, Power Query M definition inspection/editing, or Gen1-to-Gen2 `saveAsNativeArtifact` readiness assessment | Semantic models/DAX (`semantic-model-authoring`), reports (`powerbi-report-cli`), or pipeline JSON (`pipeline-migration`) |
| `onelake-catalog-cli` | OneLake catalog item metadata curation (descriptions, tags, table/column descriptions) and read-only `dataowner-audit` or `admin-audit` governance posture checks | Fabric PolicySet rules or repository data-dictionary authoring without Fabric (`data-catalog`) |
| `databricks-migration` | Existing Databricks notebooks, `dbutils`, DBFS, Unity Catalog, Jobs, or DLT workloads ported to Fabric | Native Fabric Spark (`spark-cli`), Synapse (`synapse-migration`), HDInsight (`hdinsight-migration`), or SQL Server-to-Azure path selection (`modernizer`) |
| `synapse-migration` | Existing Azure Synapse Spark notebooks, Lake Databases, Linked Services, or Dedicated SQL Pool schemas/stored procedures ported to Fabric Lakehouse or Warehouse | Standalone ADF/Synapse pipeline JSON (`pipeline-migration`) or SQL Server-to-Azure path selection (`modernizer`) |
| `hdinsight-migration` | Existing Azure HDInsight `HiveContext`/`SparkContext`, `wasb://`/`abfs://` paths, Hive DDL, or Oozie coordinators ported to Fabric Lakehouse, shortcuts, and pipelines | Databricks (`databricks-migration`) or Synapse (`synapse-migration`) workloads |
| `pipeline-migration` | Synapse or Azure Data Factory pipeline JSON mapped to Fabric Data Factory (connections, inlined datasets, Variable Library parameters, `TridentNotebook`) | Synapse Spark/SQL pool code (`synapse-migration`) or Dataflow Gen2 M definitions (`dataflows-cli`) |

## Installation and readiness

Use the shared **Pack Resource Preflight** in `profiles-and-packs.md` at Init, pack addition, and a missing-resource escalation. `Registered Pack Skills` maps all fifteen `fabric` skills to exact pinned directory entries in `microsoft/skills-for-fabric@e31422e7d1045ef3a0906df9ff5991f2338af010` (MIT).

1. Explain the missing resources in plain language. Offer all fifteen official `fabric` skills (Power BI semantic models/DAX, Power BI reports, Medallion Lakehouse, Warehouse/SQL endpoint, Fabric SQL DB, Eventhouse, Eventstream, Activator, Spark/MLV, Dataflow Gen2, OneLake catalog, and Databricks/Synapse/HDInsight/pipeline migrations), a selected subset, or continuing without them. Say which requested job each choice enables. Keep `spark-cli` selected alongside `e2e-medallion-architecture` when medallion notebook/MLV patterns are needed.
2. **Disclose skill-manifest MCP entries before installation approval.** At `e31422e7d1045ef3a0906df9ff5991f2338af010`, four skill directories carry `apm.yml` `dependencies.mcp` blocks that APM writes into `.github/mcp.json`: `semantic-model-authoring` and `powerbi-report-cli` configure `powerbi-modeling-mcp` (`npx -y @microsoft/powerbi-modeling-mcp@latest --start` over stdio), while `sqldw-cli` and `synapse-migration` configure `fabric-sqlendpoint` (`https://api.fabric.microsoft.com/v1/mcp/dataPlane/sqlEndpoint`). The other eleven skills add no MCP server, and no skill installs hooks. Disclose this `.github/mcp.json` change up front: installation approval does not approve starting `@microsoft/powerbi-modeling-mcp@latest`, installing `powerbi-report-author`, or authenticating to a Fabric tenant, and local TMDL/PBIP/PBIR design and review work without starting an MCP server. Whole-plugin forms (`fabric-skills@fabric-collection` and `powerbi-authoring`) remain unregistered because they bundle external agents and broader `.mcp.json` configurations.
3. After the user's resource choices, run `Install-SquadPackResources.ps1` with `-Pack fabric`, the approved `-Resource` names, a new receipt path, and `-Confirmed`. The helper installs skill payloads only — never `az`, `sqlcmd`, `fab`, `powerbi-report-author`, or tenant credentials. Preserve native confirmation prompts; a failed or cancelled command remains missing.
4. Require a `PASS` receipt, then stop for a host reload. `PLANNED` is not installation, and an on-disk skill is not yet host-visible. After reload, rerun preflight with the actual native host inventory and record every listed skill as `available` or explicitly `declined`.
5. Check the packaged files and shared `common/` support root below before claiming the requested job is ready. Report installed payloads, host visibility, missing support files, and live-tenant/CLI prerequisites separately. Resume a failed setup at the failed step, without inventing availability or overwriting existing files.

The shared installer runs the exact pinned APM entries without a Fabric-specific installer. APM takes **skill directories**, not `SKILL.md` file paths. Give the user the published [English setup guide](https://peter-n91.github.io/hve-squad/usage.html#fabric-setup) or [French setup guide](https://peter-n91.github.io/hve-squad/fr/usage.html#fabric-setup) for detailed commands and troubleshooting; the consumer repository need not contain this project's documentation.

### Complete support roots and packaged references

`powerbi-report-cli` is self-contained inside `.agents/skills/powerbi-report-cli/references/` (87 files across `planning`, `design`, `authoring`, and `management`). The other fourteen skills carry their own `references/` or `resources/` directories under `.agents/skills/<skill>/` and also reference shared repository-level files under `common/` (`COMMON-CLI.md`, `COMMON-CORE.md`, `ITEM-DEFINITIONS-CORE.md`, and workload `*-CORE.md` files), which APM fetches under `apm_modules/microsoft/skills-for-fabric/` (or an optional user-approved read-only source snapshot at `apm_modules/.squad-pack-support/skills-for-fabric-e31422e` with repository-local `core.longpaths=true`). Verify both the skill's packaged files and the `common/` support root at `e31422e7d1045ef3a0906df9ff5991f2338af010` before live REST/CLI payload construction; if missing, stop and give the setup remedy instead of inventing API envelopes.

| Skills | Verified source | Required packaged files and shared support root |
|---|---|---|
| `semantic-model-authoring` | `microsoft/skills-for-fabric@e31422e7d1045ef3a0906df9ff5991f2338af010` | `references/modeling-guidelines.md`, `references/direct-lake-guidelines.md`, `references/tmdl-guidelines.md`, `references/pbip.md`, `references/dax-guidelines.md`, `references/dax-perf-decision-guide.md`, `references/dax-perf-patterns.md`, `references/semantic-model-ai-readiness.md`, plus `common/COMMON-CLI.md`, `common/COMMON-CORE.md`, and `common/ITEM-DEFINITIONS-CORE.md` |
| `powerbi-report-cli` | same pin | `references/planning.md`, `references/planning-part-02.md`, `references/design.md`, `references/design/chart-selection.md`, `references/design/accessibility.md`, `references/design/anti-patterns.md`, `references/design/design-brief.md`, and `references/authoring.md` |
| `e2e-medallion-architecture`, `spark-cli` | same pin | `spark-cli/references/authoring.md`, `spark-cli/references/mlv.md`, `spark-cli/references/operations.md`, `spark-cli/references/authoring/resources/infrastructure-orchestration.md`, `spark-cli/references/authoring/resources/data-engineering-patterns.md`, plus `common/COMMON-CLI.md`, `common/COMMON-CORE.md`, and `common/SPARK-AUTHORING-CORE.md` |
| `sqldw-cli`, `sqldb-cli`, `eventhouse-cli`, `eventstream-cli`, `activator-cli`, `dataflows-cli`, `onelake-catalog-cli` | same pin | Each skill's `references/` directory under `.agents/skills/<skill>/`, plus `common/COMMON-CLI.md`, `common/COMMON-CORE.md`, and `common/ITEM-DEFINITIONS-CORE.md` |
| `databricks-migration`, `synapse-migration`, `hdinsight-migration`, `pipeline-migration` | same pin | Each skill's `resources/` and `references/` directory under `.agents/skills/<skill>/`, plus `common/COMMON-CLI.md`, `common/COMMON-CORE.md`, and `common/SPARK-AUTHORING-CORE.md` |

## Parity supersession and excluded candidates

All six legacy community Power BI and Lakehouse skills (`github/awesome-copilot@9db369d00f121542e1c99fd9b6cd6f707bade765`) were audited for content parity against `microsoft/skills-for-fabric@e31422e7d1045ef3a0906df9ff5991f2338af010` and moved to *External Cast Blocklist*:

* `powerbi-modeling`, `power-bi-model-design-review`, and `power-bi-dax-optimization` are superseded by `semantic-model-authoring` (Tier 1 MCP and Tier 2 offline TMDL/PBIP editing, star-schema/Direct Lake/AI-readiness design review, and FE/SE trace or offline DAX-shape optimization `DAX001`–`DAX021`, `QRY001`–`QRY004`, `MDL001`–`MDL009`, `DL001`–`DL002`).
* `power-bi-report-design-consultation` is superseded by `powerbi-report-cli` (`planning`, `design`, `authoring`, and `management` modes covering chart selection, five page archetypes, semantic color/WCAG 4.5:1 accessibility, anti-patterns, `Design Brief:`, and PBIR/PBIP files).
* `power-bi-performance-troubleshooting` is superseded jointly by `semantic-model-authoring` (model compression, Direct Lake, and DAX Studio / MCP / TOM / Workspace Monitoring trace diagnostics), `powerbi-report-cli` (`references/design/anti-patterns.md` visual and slicer budgets), and `sqldw-cli` (Capacity Metrics CU-spike correlation).
* `fabric-lakehouse` is superseded jointly by `e2e-medallion-architecture`, `spark-cli`, and `sqldw-cli` (Files vs Delta Tables, schema-enabled Lakehouses, shortcuts, OneLake Spark Catalog & RLS/CLS, Materialized Lake Views, V-Order, `OPTIMIZE`/`ZORDER`/`VACUUM`, PySpark ingestion, and SQL analytics endpoint queries).

The five upstream Fabric agents (`FabricAdmin`, `FabricAppDev`, `FabricDataEngineer`, `FabricIQ`, `FabricMigrationEngineer`) and four gate-failing skills (`fabriciq`, `ontology-cli`, `project-osmos`, `e2e-fabric-cost-estimation`) are recorded in *External Cast Blocklist*. Eight remaining upstream skills stay unregistered and unblocked: `deployment-pipelines-authoring-cli`, `git-integration-operations-cli` (`experimental`), and `variable-library-cli` have no evidence-backed Fabric ALM owner; `fabric-policies-cli` and `eventschemaset-cli` target preview/beta tenant or delegated-only registries; `databasehub-cli` and `azmon-mirroredcatalogs-operations-cli` require live estate/AzMon onboarding across diagnostic and observability boundaries; and `search-consumption-cli` is a cross-workspace locator helper omitting Dataflows.

## Boundaries

* `az login`, Fabric capacity/workspace permissions, `sqlcmd`, `powerbi-report-author`, `powerbi-modeling-mcp`, and `fabric-sqlendpoint` count as runtime prerequisites under *Tier Qualification* test 3, and Power BI / Microsoft Fabric is an optional data/BI platform vertical under test 4, so every row is `opt-in` behind `fabric` and none is `bundled` in `apm.yml`.
* `Squad Data Scientist` (`data-scientist`) writes analysis, design briefs, TMDL/PBIP/PBIR plans, and migration deliverables under `outputs/` (or local PBIP/TMDL files only when explicitly requested in an approved plan). When no live trace client or MCP server is connected, `semantic-model-authoring` reviews `.tmdl` files or applies DAX-shape hypotheses from `dax-perf-decision-guide.md` without fabricating measured FE/SE timings, and `powerbi-report-cli` stops at the Greenfield Approval Barrier (`_brief/report-spec.md` / `Design Brief:`) before PBIR edits.
* Never request tenant consent, start unapproved `@latest` MCP servers, or run workspace/item creation, `updateDefinition`, semantic-model deployment/refresh, report publishing/rebinding, `dacpac` deployment, Activator writes, OneLake catalog remediation, or migration cutovers from `Squad Data Scientist`; report any live Fabric control-plane or data-plane write as an impactful action requiring explicit human approval.