#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Returns an exact native-credit snapshot for the Copilot session serving a repository.
.DESCRIPTION
    Resolves an explicit events.jsonl path, `auto`, or a CLI usage-output JSON and
    delegates accounting to SquadUsage.psm1. Complete records are deduplicated by
    host identity; checkpoints remain diagnostics. This script writes nothing.
.PARAMETER RepoRoot
    Repository whose newest matching Copilot session is selected for `-SessionLog auto`.
.PARAMETER SessionLog
    events.jsonl, its directory, or `auto`. Mutually exclusive with -UsagePath.
.PARAMETER UsagePath
    CLI --usage-output-file JSON. Mutually exclusive with -SessionLog.
.PARAMETER BaselineNanoAiu
    Cumulative native total captured at the run boundary. The result reports only
    consumption above this value.
.PARAMETER IncludeAgentRuns
    Include exact top-level agent runs with nested descendants rolled into their
    owning agent. Each run carries uncached input, cache read, cache write, output,
    native nano-AIU, credits, and lightweight request records.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).ProviderPath,
    [string]$SessionLog = 'auto',
    [string]$UsagePath,
    [decimal]$BaselineNanoAiu = 0,
    [switch]$IncludeAgentRuns
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadUsage.psm1') -Force

try {
    if ($PSBoundParameters.ContainsKey('UsagePath') -and $PSBoundParameters.ContainsKey('SessionLog')) {
        throw 'Supply only one of -SessionLog or -UsagePath.'
    }
    $snapshot = if ($PSBoundParameters.ContainsKey('UsagePath')) {
        Get-SquadUsageSnapshot -UsagePath $UsagePath -BaselineNanoAiu $BaselineNanoAiu -IncludeAgentRuns:$IncludeAgentRuns
    }
    else {
        $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
        $events = Resolve-SquadSessionLogPath -SessionLog $SessionLog -RepoRoot $RepoRoot
        if (-not $events) { throw 'No Copilot session log matches this repository.' }
        Get-SquadUsageSnapshot -EventsPath $events -BaselineNanoAiu $BaselineNanoAiu -IncludeAgentRuns:$IncludeAgentRuns
    }
    $snapshot | ConvertTo-Json -Depth 12 -Compress
}
catch {
    [Console]::Error.WriteLine("Get-SquadUsage: $($_.Exception.Message)")
    exit 1
}