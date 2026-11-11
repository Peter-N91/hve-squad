#!/usr/bin/env bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

# sessionStart — informational squad-state resolution check.
# Source: squad-floor.instructions.md ("must hold before squad state even exists").
# Cannot block; sessionStart only supports additionalContext injection.
set -uo pipefail

input="$(cat)"
cwd="$(printf '%s' "$input" | grep -Eo '"cwd"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*:"([^"]+)"$/\1/')"
cwd="${cwd:-.}"

if [ -f "$cwd/.copilot-tracking/squad/federation.md" ]; then
  context="Squad state detected: federation (federation.md present). Sub-squad roots resolve under .copilot-tracking/squad/members/<name>/."
elif [ -f "$cwd/.copilot-tracking/squad/team.md" ]; then
  context="Squad state detected: single squad (team.md present, no federation.md)."
  if [ -f "$cwd/.copilot-tracking/squad/state.json" ]; then
    if command -v node >/dev/null 2>&1 && ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$cwd/.copilot-tracking/squad/state.json" >/dev/null 2>&1; then
      context="$context WARNING: state.json exists but does not parse as valid JSON."
    fi
  else
    context="$context WARNING: team.md exists but state.json is missing."
  fi
else
  context="No squad state detected at this cwd (neither team.md nor federation.md). Init Mode would run on the first squad dispatch."
fi

if command -v node >/dev/null 2>&1; then
  node -e '
    const ctx = process.argv[1];
    process.stdout.write(JSON.stringify({ additionalContext: ctx }));
  ' "$context"
  printf '\n'
else
  printf '{}\n'
fi
