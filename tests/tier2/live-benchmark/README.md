# Live benchmark harness

Offline self-tests do not call models. Live benchmark and judge scripts spend credits.

## Prerequisites

- PowerShell 7.4 or later
- Python 3 with pytest: `python -m pip install pytest`, or use a venv
- APM 0.29.0
- GitHub Copilot CLI
- `COPILOT_GITHUB_TOKEN` for live runs

## Arms and defaults

- A: baseline source, routing off
- B: candidate source, routing off
- C: baseline source, `routing=ranked`
- D: candidate source, `routing=ranked`
- E: candidate source, `routing=economy`
- F: optional candidate source, `routing=economy delivery=background`

Default live matrix: arms A to E (F runs every selected level; the easy task has three independent items, so pair F with `-Levels easy` when only background delivery is under test), 8 repeats per cell, model `claude-sonnet-5.5`, blind judge on. Use `-SkipJudge` to report unjudged results. Use `-Arms A,B,C,D,E,F` to include F.

## stopCause values

`stopCause` is classified in this order: `intake-escalation`, `handoff-failure` (with exit code when present), `ledger-crash`, `rate-limit`, `cli-error`, `none`, `unknown`.

## Run offline self-tests

```powershell
python -m venv $env:TEMP\bench-venv
& "$env:TEMP\bench-venv\Scripts\python.exe" -m pip install pytest
$env:PATH = "$env:TEMP\bench-venv\Scripts" + [IO.Path]::PathSeparator + $env:PATH
pwsh -NoProfile -File tests\tier2\live-benchmark\Invoke-LiveBenchmarkTests.ps1 -Output Normal
```
