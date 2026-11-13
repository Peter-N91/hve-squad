#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

# Lexical backstop only: host permissions remain the independent action boundary.
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'hook-input.ps1')
    $hook = Read-SquadHookInput -InputText ([Console]::In.ReadToEnd())
    $calls = @(Get-SquadHookToolCall -Hook $hook -DefaultTool 'shell')
    $commands = @(
        foreach ($call in $calls) {
            if ($call.Name -in @('bash', 'powershell', 'shell')) { Get-SquadHookCommand -Call $call }
        }
    )
    if ($commands.Count -eq 0) { throw 'No supported shell tool call.' }
    $pattern = 'git\s+push|terraform\s+apply|az\s+[a-zA-Z-]+\s+(create|delete)|az\s+keyvault\s+secret|gh\s+pr\s+merge|kubectl\s+(apply|delete)|npm\s+publish|helm\s+(install|upgrade|uninstall)|rm\s+-rf|Remove-Item.*-Recurse.*-Force|DROP\s+TABLE|DROP\s+DATABASE'
    $matchesAction = @($commands | Where-Object { $_ -match $pattern }).Count -gt 0
    if ($matchesAction) {
        @{ permissionDecision = 'ask'; permissionDecisionReason = 'Impactful-Action Gate: this command matches an impactful operation. Confirm this specific action before proceeding. This lexical backstop is not independent enforcement; non-interactive approval behavior requires native host validation.' } | ConvertTo-Json -Compress
    }
    else { Write-Output '{"permissionDecision":"allow"}' }
}
catch {
    Write-Output '{"permissionDecision":"deny","permissionDecisionReason":"Impactful-Action Gate: invalid or unsupported hook input, or required parser unavailable. No action approval was established."}'
}
