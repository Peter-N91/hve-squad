#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# subagentStop — autonomous-loop mandatory escalation trigger detection.
# Source: squad-autonomous.instructions.md. This is the one Section 4a condition that
# genuinely needs a subagent's own response text, which preToolUse cannot see — subagentStop
# is the correct event.
$ErrorActionPreference = 'SilentlyContinue'

$input_raw = [Console]::In.ReadToEnd()
$pattern = 'Verdict:\s*Stop|Risk:\s*High|compliance violation|irreversible'

if ($input_raw -match "(?i)$pattern") {
    $reason = "Autonomous-loop mandatory escalation (squad-autonomous.instructions.md): this dispatch's response contains a Stop verdict, a Risk: High finding, a compliance violation, or an irreversible-write statement. Do not continue the loop silently - stop and escalate to the user through the coordinator instead of proceeding to the next cycle."
    $out = @{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress
    Write-Output $out
} else {
    Write-Output '{"decision":"allow"}'
}