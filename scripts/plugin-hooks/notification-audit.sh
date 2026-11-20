#!/usr/bin/env bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
set -uo pipefail
if ! command -v pwsh >/dev/null 2>&1; then
  printf '{}\n'
  exit 0
fi
exec pwsh -NoProfile -File "$(dirname "${BASH_SOURCE[0]}")/notification-audit.ps1"
