---
name: squad-dotnet-platform-options
description: "Opt-in .NET official skill ownership, prerequisites, packaged support files, preview boundaries, and non-admitted candidates."
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-11-12"
---
<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

# .NET Platform Options

Read this reference for a `dotnet` proposal's resource preflight, or when the resolved root's `team.md` `Packs:` line includes `dotnet`. A proposal permits explanation, not skill selection or installation. Removing the pack stops squad selection and workload guidance. It does not uninstall or hide a host-installed skill.

Host visibility is not selection. A declined resource stays unavailable to the squad even if the host exposes it. The preview jobs below also require explicit preview approval; accepting the pack alone is not that approval.

The pack adds no new catalog role and no external agent Primary or Alternate. It reuses `modernizer`, `tester`, `performance`, and `developer` through their existing local charters. `full +dotnet` adds no roles; `default +dotnet` adds `modernizer` and `performance`; `azure +dotnet` and `modernization +dotnet` add `performance`; `operations +dotnet` adds `modernizer`.

## Paths

| Request | Agent | Skill |
|---|---|---|
| .NET 8 to .NET 9 upgrade plan | `Squad Modernization Planner` | `migrate-dotnet8-to-dotnet9` |
| .NET 9 to .NET 10 upgrade plan | `Squad Modernization Planner` | `migrate-dotnet9-to-dotnet10` |
| .NET 10 to .NET 11 upgrade plan (preview) | `Squad Modernization Planner` | `migrate-dotnet10-to-dotnet11` |
| C# nullable reference types readiness and migration plan | `Squad Modernization Planner` | `migrate-nullable-references` |
| Native AOT and IL trimming compatibility plan | `Squad Modernization Planner` | `dotnet-aot-compat` |
| Legacy MSBuild / `packages.config` to SDK-style migration plan | `Squad Modernization Planner` | `msbuild-modernization` |
| NuGet Central Package Management (`Directory.Packages.props`) plan | `Squad Modernization Planner` | `convert-to-cpm` |
| VSTest to `Microsoft.Testing.Platform` runner migration plan | `Squad Modernization Planner` | `migrate-vstest-to-mtp` |
| Changed-behavior and regression-test review on a diff, PR, or commit | `Squad Reviewer` | `test-value-evidence` |
| Supplied `.NET` Cobertura / coverage report and CRAP hotspot analysis | `Squad Reviewer` | `coverage-analysis` |
| Public API, `ApiCompat`, multi-targeting, `InternalsVisibleTo`, or generated-partial compatibility review | `Squad Reviewer` | `dotnet-breaking-changes` |
| `.NET` mock-setup control-flow audit across Moq, NSubstitute, or FakeItEasy (preview) | `Squad Reviewer` | `exp-mock-usage-analysis` |
| C#/.NET hot-path performance anti-pattern scan | `Squad Performance Planner` | `analyzing-dotnet-performance` |
| BenchmarkDotNet suite, comparison-axis, and job-preset matrix planning | `Squad Performance Planner` | `microbenchmarking` |
| Production `.NET` diagnostic tool selection and trace-collection planning | `Squad Performance Planner` | `dotnet-trace-collect` |
| ASP.NET Core Web API endpoints, DTOs, OpenAPI, and error handling | `Squad Implementor` | `dotnet-webapi` |
| Blazor `.razor` component authoring, parameters, async lifecycle, and disposal | `Squad Implementor` | `author-component` |
| Entity Framework Core query review and optimization | `Squad Implementor` | `optimizing-ef-core-queries` |
| Behavior-preserving C#/.NET structural refactoring | `Squad Implementor` | `csharp-refactoring` |
| MSBuild `.csproj`/`.props`/`.targets`, custom targets, and incremental-build repairs | `Squad Implementor` | `msbuild` |
| SQL Server-to-Azure path selection or migration prerequisite planning | `Squad SQL Migration Advisor` | existing `modernizer` Alternate; not these `.NET` pack skills |
| Authoring and executing new test suites | `QA` (`qa-engineer`) | optional external role; `tester` reviews only and never writes or runs tests |

When `Squad Implementor` executes an approved modernization plan phase, it may also read the non-declined `modernizer` upgrade skill that governed that plan, and `dotnet-breaking-changes` before editing public library surfaces, while preserving its `.copilot-tracking/changes/` deliverable contract and never running `git commit`.

## Installation and readiness

Use the shared **Pack Resource Preflight** in `profiles-and-packs.md` at Init, pack addition, and a missing-resource escalation. `Registered Pack Skills` maps all twenty `.NET` skills to their exact opt-in entries: eighteen core official `dotnet/skills` entries and two separately approved preview entries (`migrate-dotnet10-to-dotnet11` and `exp-mock-usage-analysis`).

1. Explain the missing resources in plain language. Offer the eighteen core official `.NET` skills (upgrade, test review, diagnostics/performance, EF Core data, ASP.NET Core/Blazor, C# refactoring, and MSBuild), the two separately approved preview skills, a selected subset, or continuing without them. Preview is not the default; a generic install-all answer without preview disclosure is not preview approval. Say which requested job each choice enables.
2. Before preview approval, disclose the preview posture and excluded execution steps for both preview entries:
   * `migrate-dotnet10-to-dotnet11` targets `.NET 11` while `.NET 11` is in preview (covering breaking changes documented through Preview 3). `Squad Modernization Planner` plans the upgrade read-only from its packaged reference files, and `Squad Implementor` edits target frameworks only under an approved plan; neither runs `dotnet-install` or `setup-local-sdk` to install a preview SDK.
   * `exp-mock-usage-analysis` ships in `dotnet/skills`'s `dotnet-experimental` plugin (`Experimental skills under active evaluation that may change or graduate to stable plugins`). `Squad Reviewer` uses it strictly for read-only mock-setup control-flow review and never edits test or production files.
   * All twenty entries install as self-contained pinned skill directories with no hooks, no LSP configuration, and no `.mcp.json` or `mcpServers` entries.
3. After the user's resource choices, run `Install-SquadPackResources.ps1` with `-Pack dotnet`, the approved `-Resource` names, a new receipt path, and `-Confirmed`. The helper installs skill payloads only — never `.NET SDK`s, workloads, `dotnet tool` packages, or MCP servers. Preserve native confirmation prompts; a failed or cancelled command remains missing.
4. Require a `PASS` receipt, then stop for a host reload. `PLANNED` is not installation, and an on-disk skill is not yet host-visible. After reload, rerun preflight with the actual native host inventory and record every listed skill as `available` or explicitly `declined`. Pass the preview approval's decision reference or current explicit request with its dispatch; an `available` flag alone is not preview permission. Declining preview skills does not prevent applying the pack or using the other approved resources.
5. Check the packaged support files below before claiming the requested job is ready. Report installed payloads, host visibility, missing packaged support files, and `.NET SDK` or tool prerequisites separately. Resume a failed setup at the failed step, without inventing availability or overwriting existing files.

The shared installer runs the exact pinned APM entries without a `.NET`-specific installer. APM takes **skill directories**, not `SKILL.md` file paths. Give the user the published [English setup guide](https://peter-n91.github.io/hve-squad/usage.html#dotnet-setup) or [French setup guide](https://peter-n91.github.io/hve-squad/fr/usage.html#dotnet-setup) for detailed commands and troubleshooting; the consumer repository need not contain this project's documentation.

### Packaged support files and optional reference snapshot

Each pinned `.NET` directory install carries its own `references/` and `scripts/` inside `.agents/skills/<skill>/` (and `apm_modules/`) with no parent-plugin `${PLUGIN_ROOT}` dependency, hooks, LSP server, or MCP configuration. Verify the required files below under the installed skill root before use; if they are missing, stop and give the setup remedy instead of answering from memory. Skills not listed in this table (`msbuild-modernization`, `migrate-vstest-to-mtp`, `test-value-evidence`, `exp-mock-usage-analysis`, `dotnet-webapi`, `optimizing-ef-core-queries`) are self-contained in `SKILL.md`.

| Skills | Verified source | Required packaged support files |
|---|---|---|
| `migrate-dotnet8-to-dotnet9` | `dotnet/skills@2877c712edc20643b72f64e2983b168e6661d607` | `references/aspnet-core-dotnet8to9.md`, `references/core-libraries-dotnet8to9.md`, `references/csharp-compiler-dotnet8to9.md`, `references/efcore-dotnet8to9.md`, and `references/sdk-msbuild-dotnet8to9.md` |
| `migrate-dotnet9-to-dotnet10` | same pin | `references/aspnet-core-dotnet9to10.md`, `references/core-libraries-dotnet9to10.md`, `references/csharp-compiler-dotnet9to10.md`, `references/efcore-dotnet9to10.md`, and `references/sdk-msbuild-dotnet9to10.md` |
| `migrate-dotnet10-to-dotnet11` (preview) | same pin | `references/aspnetcore-dotnet10to11.md`, `references/core-libraries-dotnet10to11.md`, `references/csharp-compiler-dotnet10to11.md`, `references/efcore-dotnet10to11.md`, and `references/sdk-msbuild-dotnet10to11.md` |
| `migrate-nullable-references` | same pin | `references/aspnet-core.md`, `references/breaking-changes.md`, `references/ef-core.md`, `references/nullable-attributes.md`, and `scripts/Get-NullableReadiness.ps1` |
| `dotnet-aot-compat` | same pin | `references/polyfills.md` |
| `convert-to-cpm` | same pin | `references/audit-complexities.md`, `references/baseline-comparison.md`, `references/directory-packages-props.md`, `references/msbuild-property-handling.md`, `references/report-template.md`, and `references/validation-and-errors.md` |
| `coverage-analysis` | same pin | `references/guidelines.md`, `references/output-format.md`, `references/report-generation.md`, `references/setup-discovery.md`, `scripts/Compute-CrapScores.ps1`, `scripts/CoverageData.ps1`, and `scripts/Extract-MethodCoverage.ps1` |
| `dotnet-breaking-changes` | same pin | `references/public-api.md`, `references/multi-targeting.md`, `references/internals-visible-to.md`, and `references/source-generation.md` |
| `analyzing-dotnet-performance` | same pin | `references/critical-patterns.md`, `references/async-patterns.md`, `references/collections-and-linq.md`, `references/io-and-serialization.md`, `references/memory-and-strings.md`, `references/regex-patterns.md`, and `references/structural-patterns.md` |
| `microbenchmarking` | same pin | `references/comparison-strategies.md`, `references/writing-benchmarks.md`, `references/diagnosers-and-exporters.md`, `references/project-setup-and-running.md`, and `references/bdn-internals-and-tuning.md` |
| `dotnet-trace-collect` | same pin | `references/dotnet-trace-collect.md`, `references/dotnet-trace-collect-linux.md`, `references/dotnet-monitor.md`, `references/perfview.md`, and `references/perfcollect.md` |
| `author-component` | same pin | `references/async-programming-rules.md`, `references/breaking-down-components.md`, and `references/component-disposal.md` |
| `csharp-refactoring` | same pin | `references/operation-catalog.md` |
| `msbuild` | same pin | `references/binlog-failure-analysis.md`, `references/binlog-generation.md`, `references/build-perf-baseline.md`, `references/build-perf-diagnostics.md`, `references/copy-to-output-directory.md`, `references/eval-performance.md`, `references/extension-points.md`, `references/incremental-build.md`, and `references/msbuild-antipatterns.md` |

When offline access to additional `dotnet/skills` plugin documentation is wanted, ask before fetching a read-only source snapshot into `apm_modules/.squad-pack-support/dotnet-skills-2877c71` with repository-local `core.longpaths=true`. Verify its detached `HEAD` matches `2877c712edc20643b72f64e2983b168e6661d607` and do not register that checkout as a plugin or working project. An installed skill or snapshot at a different ref requires re-verification before use.

### Preview selection and exclusions

`migrate-dotnet10-to-dotnet11` covers `.NET 10` to `.NET 11` migration while `.NET 11` is in preview (through Preview 3). `Squad Modernization Planner` plans target-framework, C# 15, ASP.NET Core 11, EF Core 11, and container/hardware readiness read-only; `Squad Implementor` applies edits only from an approved plan. Do not run `dotnet-install` or `setup-local-sdk` to install a preview `.NET 11` SDK, and do not run `git commit` from either charter.

`exp-mock-usage-analysis` audits `.NET` test mock setups (`Moq`, `NSubstitute`, `FakeItEasy`) against production control flow to report dead, unreachable, redundant, or over-mocked setups. `Squad Reviewer` runs it read-only under `.copilot-tracking/reviews/` and never modifies test or production source.

Other upstream `dotnet/skills` candidates were gated at `2877c712edc20643b72f64e2983b168e6661d607` and remain **not registered squad capabilities**:

* All sixteen `.agent.md` files fail role/worker gating and are recorded in *External Cast Blocklist*: the nine `dotnet-test` internal specialists (`code-testing-researcher`, `code-testing-planner`, `code-testing-implementer`, `code-testing-builder`, `code-testing-tester`, `code-testing-fixer`, `code-testing-linter`, `test-quality-auditor`, `testability-migration`) are delegated workers under `test-engineer`; `test-engineer`, `test-migration`, `msbuild`, `build-perf`, `msbuild-code-review`, `template-engine`, and `optimizing-dotnet-performance` either mutate source/tests against read-only `modernizer`/`tester`/`performance` Deliverable Roots, duplicate the Squad Coordinator's RPI loop, invoke `ask_user` from a worker, or assume the prerelease `binlog` MCP server.
* `setup-local-sdk` and `system-text-json-net11` (`dotnet-install` script execution) install `.NET SDK` toolchains; `csharp-expert` routes users to `/plugin install ...@dotnet-agent-skills` instead of Squad's consent-bound resource preflight.
* `dotnet-msbuild`'s binlog MCP skills (`binlog-failure-analysis`, `build-perf-diagnostics`, `check-bin-obj-clash`, `eval-performance`, `find-repeated-work-within-one-build`, `incremental-build`, `resolve-project-references`, `troubleshoot-binlog-mcp`) prefer the plugin-bundled prerelease `dotnet dnx Microsoft.AITools.BinlogMcp` MCP server; the standalone `plugins/dotnet/skills/msbuild` skill covers MSBuild authoring, replay, and incremental repairs without that MCP server.
* `dotnet-test`'s mutating or test-running skills (`code-testing`, `writing-mstest-tests`, `scaffold-dotnet-test-project`, `generate-testability-wrappers`, `migrate-static-to-wrapper`, `testability-obstacle`, `mtp-hot-reload`, `run-tests`, `test-tagging`), its four `disable-model-invocation: true` reference catalogs (`code-testing-agent`, `code-testing-extensions`, `filter-syntax`, `test-analysis-extensions`), and analysis skills expecting `test-analysis-extensions` (`assertion-quality`, `test-anti-patterns`, `test-gap-analysis`, `test-smell-detection`) remain unregistered so `tester` stays strictly read-only and self-contained.
* `dump-collect`, `android-tombstone-symbolication`, `apple-crash-symbolication`, `clr-activation-debugging`, `dotnet-maui`, `dotnet-winforms`, `dotnet-template-engine`, `dotnet-advanced`, `process-api-net11`, `exp-test-maintainability`, `create-datadriven-aspnetcore`, `convert-blazor-server-to-webapp`, `thread-abort-migration`, `technology-selection`, and secondary `dotnet-blazor` / `dotnet-test-migration` skills stay unregistered and unblocked to keep the pack focused; `microsoft-agent-framework` and `semantic-kernel` remain the bundled cross-language AI build skills on `developer`.

## Boundaries

* The `.NET SDK` (`dotnet` CLI) and `.NET` diagnostic tools (`dotnet-trace`, `PerfView`, `perfcollect`, `dotnet-monitor`, `BenchmarkDotNet`) count as runtime CLI/toolchain prerequisites under *Tier Qualification* test 3, and `.NET` is an optional technology vertical under test 4, so every row is `opt-in` and none is `bundled` in `apm.yml`.
* Whole-plugin install forms (`dotnet@dotnet-agent-skills`, `dotnet-msbuild@dotnet-agent-skills`, `dotnet-test@dotnet-agent-skills`, `dotnet-test-migration@dotnet-agent-skills`, `dotnet-diag@dotnet-agent-skills`, `dotnet-upgrade@dotnet-agent-skills`, `dotnet-experimental@dotnet-agent-skills`, `dotnet11@dotnet-agent-skills`) remain unregistered so `lsp.json`, prerelease `dnx` MCP servers, `disable-model-invocation: true` catalogs, and mutating/worker agents are never pulled in silently.
* `Squad Modernization Planner` (`modernizer`), `Squad Reviewer` (`tester`), and `Squad Performance Planner` (`performance`) remain strictly read-only on source and tests: `modernizer` plans upgrades without editing files or running `git commit`; `tester` reviews diffs and supplied coverage reports without chaining into `run-tests` or writing tests; `performance` plans hot-path remediations, BenchmarkDotNet matrices, and trace-collection commands without running benchmarks or attaching live profilers.
* `Squad Implementor` (`developer`) edits source and project files only for an approved plan phase, writes its change record under `.copilot-tracking/changes/`, and never runs `git commit`, `dotnet workload install`, `dotnet tool install`, `dotnet-install`, or schema/database migrations without human approval.
* Existing bundled and community rows (`microsoft-agent-framework`, `semantic-kernel`, `recommend-migration-path`, `generate-migration-prerequisite-plan`, `qa-subagent`) remain distinct and are neither superseded nor blocklisted.
