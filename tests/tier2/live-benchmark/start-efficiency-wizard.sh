#!/usr/bin/env bash
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Starts the PowerShell wizard and forwards every argument, including -ParallelTrials.
# AI cost: Offline makes no model requests; authorized live modes collect 3 or 6 paid trials.

set -euo pipefail

ubuntu_install_help() {
  # shellcheck disable=SC2016
  printf '%s\n' \
    'The wizard requires stable PowerShell Core 7.4 or newer (pwsh).' \
    'No installation has been performed.' \
    '' \
    'For a supported Ubuntu release, review and run these commands yourself:' \
    '  sudo apt-get update' \
    '  sudo apt-get install -y wget apt-transport-https software-properties-common' \
    '  . /etc/os-release' \
    '  wget -q "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb"' \
    '  sudo dpkg -i packages-microsoft-prod.deb' \
    '  sudo apt-get update' \
    '  sudo apt-get install -y powershell' \
    '' \
    'This registers the Microsoft package repository. Review its .NET feed implications.' \
    'For unsupported Ubuntu releases or other architectures, use official guidance:' \
    'https://learn.microsoft.com/powershell/scripting/install/install-ubuntu' \
    '' \
    'Then rerun this launcher. Existing PowerShell installations may need an upgrade.'
}

main() {
  if ! command -v pwsh >/dev/null 2>&1; then
    printf '%s\n' 'PowerShell (pwsh) was not found on PATH.' >&2
    ubuntu_install_help >&2
    return 127
  fi

  # shellcheck disable=SC2016
  if ! pwsh -NoLogo -NoProfile -NonInteractive -Command \
    'if ($PSVersionTable.PSEdition -ne "Core" -or $PSVersionTable.PSVersion -lt [version]"7.4" -or $PSVersionTable.PSVersion.ToString().Contains("-")) { exit 1 }; exit 0' \
    >/dev/null 2>&1; then
    printf '%s\n' 'The installed pwsh is too old, a preview, or could not run.' >&2
    ubuntu_install_help >&2
    return 2
  fi

  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  local wizard_path="${script_dir}/Start-EfficiencyWizard.ps1"
  if [[ ! -f "${wizard_path}" ]]; then
    printf '%s\n' "Wizard script not found: ${wizard_path}" >&2
    return 1
  fi

  exec pwsh -NoLogo -NoProfile -File "${wizard_path}" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi