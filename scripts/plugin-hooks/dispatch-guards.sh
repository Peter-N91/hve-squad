#!/usr/bin/env bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
set -euo pipefail
exec pwsh -NoProfile -File "$(dirname "${BASH_SOURCE[0]}")/dispatch-guards.ps1"
