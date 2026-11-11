#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

# preToolUse (matcher: bash|powershell) — Impactful-Action Gate backstop.
# Source: squad-autopilot.instructions.md (Impactful-Action Gate), squad-watch-mode.instructions.md
# (the absolute unattended variant).
#
# Decision is 'ask', not 'deny': the gate is documented as stop -> human approval -> proceed, and
# only 'ask' can complete that third step. Interactive CLI prompts the human; cloud agent and other
# non-interactive surfaces convert 'ask' to 'deny' automatically.
$ErrorActionPreference = 'SilentlyContinue'

$input_raw = [Console]::In.ReadToEnd()
$pattern = 'git\s+push|terraform\s+apply|az\s+[a-zA-Z-]+\s+(create|delete)|az\s+keyvault\s+secret|gh\s+pr\s+merge|kubectl\s+(apply|delete)|npm\s+publish|helm\s+(install|upgrade|uninstall)|rm\s+-rf|Remove-Item.*-Recurse.*-Force|DROP\s+TABLE|DROP\s+DATABASE'

if ($input_raw -match $pattern) {
    $reason = 'Impactful-Action Gate (squad-autopilot.instructions.md): this command matches a deploy, force-push/push, PR merge, schema migration, secret rotation, or destructive infrastructure/data operation. Confirm it is the action you intend, then approve to let it run. On a non-interactive surface this prompt is converted to a denial, which is the Watch Mode absolute variant — there, re-run the command yourself outside the session.'
    $out = @{ permissionDecision = 'ask'; permissionDecisionReason = $reason } | ConvertTo-Json -Compress
    Write-Output $out
} else {
    Write-Output '{"permissionDecision":"allow"}'
}
