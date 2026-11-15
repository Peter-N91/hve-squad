#!/usr/bin/env bash
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
set -uo pipefail

input="$(cat)"
pattern='git[[:space:]]+push|terraform[[:space:]]+apply|az[[:space:]]+[a-zA-Z-]+[[:space:]]+(create|delete)|az[[:space:]]+keyvault[[:space:]]+secret|gh[[:space:]]+pr[[:space:]]+merge|kubectl[[:space:]]+(apply|delete)|npm[[:space:]]+publish|helm[[:space:]]+(install|upgrade|uninstall)|rm[[:space:]]+-rf|Remove-Item.*-Recurse.*-Force|DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE'

if printf '%s' "$input" | grep -Eiq "$pattern"; then
  printf '%s\n' '{"permissionDecision":"ask","permissionDecisionReason":"Impactful-Action Gate (squad-autopilot.instructions.md): this command matches a deploy, force-push/push, PR merge, schema migration, secret rotation, or destructive infrastructure/data operation. Confirm it is the action you intend, then approve to let it run. On a non-interactive surface this prompt is converted to a denial, which is the Watch Mode absolute variant — there, re-run the command yourself outside the session."}'
else
  printf '%s\n' '{"permissionDecision":"allow"}'
fi
