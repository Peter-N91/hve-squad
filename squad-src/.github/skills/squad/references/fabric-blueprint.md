---
name: squad-fabric-blueprint
description: "Opt-in Fabric supplement: existing data-scientist owner, admitted skills, prerequisites, and the jobs this pack does not take."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-11-04"
---

# Fabric Supplement

Use this reference only when the resolved root's `team.md` `Packs:` line includes `fabric`. A present `data-scientist` role does not activate the pack. Host visibility is not selection. Removing the pack stops this guidance and stops squad selection of the skills below. It does not uninstall or hide a host-installed skill.

The pack adds no role and no external agent Primary. `data-scientist` is the only owner. `full +fabric` adds no roles. A profile that lacks `data-scientist`, such as `azure`, adds that existing role and no other.

## Admitted skills

Select one admitted skill only for its cue. Do not use an admitted skill to answer a Lakehouse primer, Power BI model, DAX, or report question. Those jobs stay on the unchanged community rows.

| Skill | Select when | Do not select when |
|---|---|---|
| `sqldw-cli` | Fabric Warehouse, mirrored database, `COPY INTO`, Query Insights, or a capacity CU spike | Lakehouse primer, shortcuts, V-Order overview, or a Fabric SQL database item |
| `sqldb-cli` | A Fabric SQL database item, including its T-SQL, Query Store, or temporal or vector query | Warehouse, Lakehouse SQL endpoint, or mirrored database work |
| `eventhouse-cli` | Eventhouse or KQL database work, including tables, functions, policies, or KQL | Eventstream topology, or T-SQL |
| `eventstream-cli` | An Eventstream item: sources, operators, destinations, routing, or retention | KQL database work, or Activator alerts |
| `spark-cli` | A Fabric Spark notebook, Livy session, failed or OOM Spark run, or Materialized Lake View authoring | The Lakehouse primer, or a Databricks migration |
| `dataflows-cli` | A Dataflow Gen2 item or a Power Query M definition | A semantic model, DAX, a report, or pipeline JSON |
| `databricks-migration` | Existing Databricks notebooks or jobs must be ported to Fabric | Native Fabric Spark that is not a migration, or SQL Server-to-Azure path selection |
| `pipeline-migration` | Synapse or ADF pipeline JSON must be mapped to Fabric Data Factory | Dataflow Gen2 item management, or the Lakehouse primer |

## Prerequisites and boundaries

Every admitted skill was gated at `microsoft/skills-for-fabric@4c3986d2e5b498ce2d6e6025533b94b5e5bb2ccd`. The repository licence is MIT. Each skill's frontmatter `name` matches its directory. Install only the granular command in *Registered External Cast*: `apm install microsoft/skills-for-fabric/skills/<name> --target copilot`. The whole-plugin `fabric-skills@fabric-collection` form was rejected: that bundle includes colliding semantic-model and medallion skills, external agents, and tenant-authenticated MCP servers.

Runtime prerequisites are explicit in the skill and in `common/COMMON-CLI.md`: `az login` to the Fabric tenant, workspace resolution, and capacity where the skill creates or runs an item. `sqldw-cli` also needs the `fabric-sqlendpoint` MCP `execute_query` tool for T-SQL. The shared Pack Resource Preflight may install these skills after explicit approval; it never installs a CLI, MCP server or prerequisite. Do not request tenant consent. Item creation, dacpac deployment, and data-plane writes are impactful; report them and stop for approval. Do not execute them from this guidance.

## Not admitted

These candidates were gated individually and were not registered. None was blocklisted, and no existing Power BI or `fabric-lakehouse` row changed.

* `onelake-catalog-govern-cli` has no path at the pin. `onelake-catalog-cli` was not inferred in its place.
* `deployment-pipelines-authoring-cli`, `git-integration-operations-cli`, and `variable-library-cli` have no evidence-backed owner. `developer` owns implementation, not Fabric ALM.
* `activator-cli`, `synapse-migration`, and `hdinsight-migration` passed the technical gate and were left out so this pack stays a small supplement.
* `semantic-model-authoring`, `powerbi-report-cli`, and `e2e-medallion-architecture` collide with the community Power BI and `fabric-lakehouse` rows. Do not select them.
