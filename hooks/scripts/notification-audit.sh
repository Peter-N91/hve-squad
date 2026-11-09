#!/usr/bin/env bash
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# postToolUse (matcher: bash|powershell) — notification-send audit backstop.
# Source: squad-notifications.instructions.md. Log-only: postToolUse runs after the call
# already completed, so this can never block. Real enforcement is the approval watcher.
set -uo pipefail

input="$(cat)"
log_dir=".copilot-tracking/squad"
log_file="$log_dir/hooks-audit.log"

if printf '%s' "$input" | grep -Eiq 'gh[[:space:]]+issue|Invoke-RestMethod|curl[[:space:]].*(webhook|hooks\.)'; then
  if [ -d "$log_dir" ]; then
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    printf '%s notification-shaped command observed (postToolUse backstop, not the enforcement path)\n' "$ts" >> "$log_file" 2>/dev/null || true
  fi
fi

printf '{}\n'