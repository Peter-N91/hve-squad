#!/usr/bin/env bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
set -uo pipefail

input="$(cat)"

# Scanned fields: response (camelCase) or last_assistant_message (VS Code compatible format) -
# both are plain text inside the JSON payload, so a raw pattern match over the whole payload
# covers either without needing to extract the field first.
pattern='Verdict:[[:space:]]*Stop|Risk:[[:space:]]*High|compliance violation|irreversible'

if printf '%s' "$input" | grep -Eiq "$pattern"; then
  printf '%s\n' '{"decision":"block","reason":"Autonomous-loop mandatory escalation (squad-autonomous.instructions.md): this dispatch'\''s response contains a Stop verdict, a Risk: High finding, a compliance violation, or an irreversible-write statement. Do not continue the loop silently - stop and escalate to the user through the coordinator instead of proceeding to the next cycle."}'
else
  printf '%s\n' '{"decision":"allow"}'
fi
