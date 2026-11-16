---
bump: patch
type: Changed
---

- Re-verified all 29 External Cast rows at or past the 90-day backstop (`github/awesome-copilot@dc0083dbe22133bfa7ce3500dee85e187e0cd47a`), migrated SQL Server migration advisory skills from community `fredgis/sql-migration-advisor` (now blocklisted) to official `microsoft/microsoft-sql@eeb1c6867c2d128763516a1aad41671c593cc189` alongside fifteen additional official Azure SQL migration, diagnostics, schema/T-SQL, security, and CI skills (`get-migration-assessment`, `analyze-readiness-at-scale`, `diagnose-slow-query`, `diagnose-blocking-and-deadlocks`, `diagnose-resource-pressure`, `diagnose-connection-errors`, `read-execution-plan`, `design-azure-sql-schema`, `schema-migrations-safely`, `sql-database-projects`, `t-sql-correctness`, `entra-id-auth`, `prevent-sql-injection`, `rls-multi-tenant`, `github-actions-for-sql`), pinned every External Cast `apm install` entry, and added `scripts/Sync-ExternalCast.ps1` plus `.github/workflows/sync-external-cast.yml` for split-mode zero-diff renewals and `squad/auto` drift escalation (#241).
