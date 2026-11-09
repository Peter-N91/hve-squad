#!/usr/bin/env bash
set -euo pipefail
exec pwsh -NoProfile -File "$(dirname "${BASH_SOURCE[0]}")/dispatch-guards.ps1"