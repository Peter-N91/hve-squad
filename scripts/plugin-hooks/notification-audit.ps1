#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

# Post-action observation only, never consent enforcement or send prevention.
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'hook-input.ps1')
    $hook = Read-SquadHookInput -InputText ([Console]::In.ReadToEnd())
    $root = Get-SquadHookWorkspace -Hook $hook
    $calls = @(Get-SquadHookToolCall -Hook $hook -DefaultTool 'shell')
    $commands = @(
        foreach ($call in $calls) {
            if ($call.Name -in @('bash', 'powershell', 'shell')) { Get-SquadHookCommand -Call $call }
        }
    )
    if (@($commands | Where-Object { $_ -match 'gh\s+issue|Invoke-RestMethod|curl\s+.*(webhook|hooks\.)' }).Count -gt 0) {
        $logDir = Resolve-SquadHookPath -Workspace $root -Path '.copilot-tracking/squad'
        $logFile = Join-Path $logDir 'hooks-audit.log'
        Assert-SquadHookAuditPath -Path $logFile
        if (Test-Path -LiteralPath $logDir -PathType Container) {
            $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            Add-Content -LiteralPath $logFile -Value "$ts notification-shaped command observed (postToolUse backstop, not consent enforcement)"
        }
    }
}
catch {
    # Missing/unsafe consumer context must not fall back to the plugin or expose input.
    Write-Output '{}'
    exit 0
}
Write-Output '{}'
