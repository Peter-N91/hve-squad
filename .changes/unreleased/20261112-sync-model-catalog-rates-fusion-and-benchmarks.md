---
bump: patch
type: Fixed
---

- **Automated Copilot model catalog, rates, and Copilot Fusion sync (`scripts/Sync-ModelCatalog.ps1`, `.github/workflows/sync-model-benchmarks.yml`).** Refreshes `model-catalog.md` and `consumption-rates-template.md` from official GitHub Copilot docs alongside `model-benchmarks.md`, adding newly released models (`claude-fable-5.2`, `gemini-4-argon`, `gemini-4-carbon`, `gpt-6.1-terra`), pruning retired models (`gpt-5-mini`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.5`, `claude-opus-4.7`, `gemini-3.5-flash`, `gemini-3.6-flash`, `gemini-3.7-flash`, `kimi-k2.7-code`), and separating all three Copilot Fusion effort levels (`fusion-standard`, `hydrafusion` / High, `hydrafusion-max` / Max) across routing and consumption estimation.
- **Fixed daily `Sync-ModelBenchmarks.ps1` failures.** Added standalone Epoch AI CSV fallbacks (`deepswe_external.csv`, `hle_external.csv`, `swe_bench_verified.csv`, `terminalbench_external.csv`), scoped coverage-continuity checks to active catalog models, dynamically derived benchmark model specs from `model-catalog.md`, and updated Artificial Analysis `SciCode` verification for the v5.0 `<h3 id="scicode">` Legacy Evaluations section.
