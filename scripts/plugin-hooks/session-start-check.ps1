#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# sessionStart — informational squad-state resolution check.
# Source: squad-floor.instructions.md ("must hold before squad state even exists").
# Cannot block; sessionStart only supports additionalContext injection.
$ErrorActionPreference = 'SilentlyContinue'

$input_raw = [Console]::In.ReadToEnd()
$cwdMatch = [regex]::Match($input_raw, '"cwd"\s*:\s*"([^"]+)"')
$cwd = if ($cwdMatch.Success) { $cwdMatch.Groups[1].Value } else { '.' }

$context = ''

if (Test-Path -LiteralPath (Join-Path $cwd '.copilot-tracking/squad/federation.md') -PathType Leaf) {
    $context = 'Squad state detected: federation (federation.md present). Sub-squad roots resolve under .copilot-tracking/squad/members/<name>/.'
} elseif (Test-Path -LiteralPath (Join-Path $cwd '.copilot-tracking/squad/team.md') -PathType Leaf) {
    $context = 'Squad state detected: single squad (team.md present, no federation.md).'
    $statePath = Join-Path $cwd '.copilot-tracking/squad/state.json'
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        try {
            Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json | Out-Null
        } catch {
            $context = "$context WARNING: state.json exists but does not parse as valid JSON."
        }
    } else {
        $context = "$context WARNING: team.md exists but state.json is missing."
    }
} else {
    $context = 'No squad state detected at this cwd (neither team.md nor federation.md). Init Mode would run on the first squad dispatch.'
}

$out = @{ additionalContext = $context } | ConvertTo-Json -Compress
Write-Output $out
