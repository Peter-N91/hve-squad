#!/usr/bin/env bash
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#
# Starts Invoke-Benchmark.ps1 from bash once PowerShell 7.4 or newer (pwsh) is confirmed.
# Arguments go to the PowerShell script unchanged, for example:
#   bash tests/tier2/live-benchmark/invoke-benchmark.sh -Runs 1
#   bash tests/tier2/live-benchmark/invoke-benchmark.sh -WhatIf
# Exit status: 127 when pwsh is missing, 2 when it is older than 7.4 or cannot run,
# 1 when Invoke-Benchmark.ps1 is missing; otherwise the status of Invoke-Benchmark.ps1.

set -euo pipefail

powershell_install_help() {
  # shellcheck disable=SC2016
  printf '%s\n' \
    'The benchmark needs PowerShell 7.4 or newer (pwsh). Nothing has been installed.' \
    '' \
    'On a supported Ubuntu release, review and run these commands yourself:' \
    '  sudo apt-get update' \
    '  sudo apt-get install -y wget apt-transport-https software-properties-common' \
    '  . /etc/os-release' \
    '  wget -q "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb"' \
    '  sudo dpkg -i packages-microsoft-prod.deb' \
    '  sudo apt-get update' \
    '  sudo apt-get install -y powershell' \
    '' \
    'This registers the Microsoft package repository on your machine. For other systems' \
    'or Ubuntu releases and architectures, follow the official guidance:' \
    'https://learn.microsoft.com/powershell/scripting/install/installing-powershell' \
    '' \
    'Then run this launcher again. An existing older PowerShell may need an upgrade.'
}

main() {
  if ! command -v pwsh >/dev/null 2>&1; then
    printf '%s\n' 'PowerShell (pwsh) was not found on PATH.' >&2
    powershell_install_help >&2
    return 127
  fi

  # shellcheck disable=SC2016
  if ! pwsh -NoLogo -NoProfile -NonInteractive -Command \
    'if ($PSVersionTable.PSEdition -ne "Core" -or $PSVersionTable.PSVersion -lt [version]"7.4") { exit 1 }; exit 0' \
    >/dev/null 2>&1; then
    printf '%s\n' 'The installed pwsh is older than 7.4 or could not run.' >&2
    powershell_install_help >&2
    return 2
  fi

  local script_dir runner
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  runner="${script_dir}/Invoke-Benchmark.ps1"
  if [[ ! -f "${runner}" ]]; then
    printf '%s\n' "Benchmark script not found: ${runner}" >&2
    return 1
  fi

  exec pwsh -NoLogo -NoProfile -File "${runner}" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
