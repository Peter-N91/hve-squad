#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

# Create-overwrite backstop only; this does not authenticate the writer.
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'hook-input.ps1')
    $hook = Read-SquadHookInput -InputText ([Console]::In.ReadToEnd())
    $calls = @(Get-SquadHookToolCall -Hook $hook)
    foreach ($call in $calls) {
        $arguments = Get-SquadHookArgument -Call $call
        if ($call.Name -eq 'edit') { continue }
        if ($call.Name -ne 'create') { throw 'Unsupported state-write tool.' }
        $paths = @('path', 'file_path' | Where-Object { $arguments.PSObject.Properties[$_] })
        if ($paths.Count -ne 1 -or $arguments.($paths[0]) -isnot [string]) { throw 'Expected one file path.' }
        $root = Get-SquadHookWorkspace -Hook $hook
        $path = Resolve-SquadHookPath -Workspace $root -Path $arguments.($paths[0])
        $relative = $path.Substring($root.TrimEnd([char[]]'\/').Length + 1).Replace('\', '/')
        if ($relative -match '^\.copilot-tracking/squad/(?:[^/]+/)*(?:decisions\.md|notifications\.md|federation\.md|history/(?:[^/]+/)*[^/]+\.md)$' -and
            (Test-Path -LiteralPath $path -PathType Leaf)) {
            Write-Output '{"permissionDecision":"deny","permissionDecisionReason":"squad-state append-only guard: this existing squad record cannot be overwritten with create; append instead. This backstop cannot verify caller identity."}'
            exit 0
        }
    }
    Write-Output '{"permissionDecision":"allow"}'
}
catch {
    Write-Output '{"permissionDecision":"deny","permissionDecisionReason":"squad-state append-only guard: invalid or unsupported hook input, workspace or file path; required parser must be available."}'
}
