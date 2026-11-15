#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

# userPromptSubmitted — log-only injection-safety note.
# Source: squad-watch-mode.instructions.md (untrusted trigger payload rule).
# A command-type userPromptSubmitted hook cannot block or rewrite the prompt.
$ErrorActionPreference = 'SilentlyContinue'

$input_raw = [Console]::In.ReadToEnd()
$logDir = '.copilot-tracking/squad'
$logFile = Join-Path $logDir 'hooks-audit.log'

if ($input_raw -match '(?i)ignore (all )?(previous|prior) instructions|skip the (gate|approval)|disregard the (gate|rule)') {
    if (Test-Path -LiteralPath $logDir -PathType Container) {
        $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        Add-Content -LiteralPath $logFile -Value "$ts prompt contained instruction-override-shaped language (log-only; this event cannot block or rewrite for command hooks)"
    }
}

Write-Output '{}'
