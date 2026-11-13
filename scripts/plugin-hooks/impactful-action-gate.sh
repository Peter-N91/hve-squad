#!/usr/bin/env bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
set -uo pipefail
if ! command -v pwsh >/dev/null 2>&1; then
  printf '%s\n' '{"permissionDecision":"deny","permissionDecisionReason":"Squad hook requires PowerShell; no action approval was established."}'
  exit 0
fi
exec pwsh -NoProfile -File "$(dirname "${BASH_SOURCE[0]}")/impactful-action-gate.ps1"
