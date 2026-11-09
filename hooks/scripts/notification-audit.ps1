#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# postToolUse (matcher: bash|powershell) — notification-send audit backstop.
# Source: squad-notifications.instructions.md. Log-only: postToolUse runs after the call
# already completed, so this can never block. Real enforcement is the approval watcher.
$ErrorActionPreference = 'SilentlyContinue'

$input_raw = [Console]::In.ReadToEnd()
$logDir = '.copilot-tracking/squad'
$logFile = Join-Path $logDir 'hooks-audit.log'

if ($input_raw -match '(?i)gh\s+issue|Invoke-RestMethod|curl\s+.*(webhook|hooks\.)') {
    if (Test-Path -LiteralPath $logDir -PathType Container) {
        $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        Add-Content -LiteralPath $logFile -Value "$ts notification-shaped command observed (postToolUse backstop, not the enforcement path)"
    }
}

Write-Output '{}'