#!/usr/bin/env bash
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# userPromptSubmitted — log-only injection-safety note.
# Source: squad-watch-mode.instructions.md (untrusted trigger payload rule).
# A command-type userPromptSubmitted hook cannot block or rewrite the prompt.
set -uo pipefail

input="$(cat)"
log_dir=".copilot-tracking/squad"
log_file="$log_dir/hooks-audit.log"

if printf '%s' "$input" | grep -Eiq 'ignore (all )?(previous|prior) instructions|skip the (gate|approval)|disregard the (gate|rule)'; then
  if [ -d "$log_dir" ]; then
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    printf '%s prompt contained instruction-override-shaped language (log-only; this event cannot block or rewrite for command hooks)\n' "$ts" >> "$log_file" 2>/dev/null || true
  fi
fi

printf '{}\n'