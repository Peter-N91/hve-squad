#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

function Read-SquadHookInput {
    param([string]$InputText)
    if ([string]::IsNullOrWhiteSpace($InputText) -or -not $InputText.TrimStart().StartsWith('{')) {
        throw 'Expected a hook input object.'
    }
    $hook = $InputText | ConvertFrom-Json -ErrorAction Stop
    if ($hook -isnot [pscustomobject]) { throw 'Expected a hook input object.' }
    return $hook
}

function Get-SquadHookToolCall {
    param($Hook, [string]$DefaultTool)
    if ($Hook.PSObject.Properties['toolCalls']) {
        if ($Hook.toolCalls -isnot [array] -or $Hook.toolCalls.Count -eq 0) {
            throw 'Expected a non-empty toolCalls array.'
        }
        foreach ($call in $Hook.toolCalls) {
            if ($call -isnot [pscustomobject] -or $call.name -isnot [string] -or
                [string]::IsNullOrWhiteSpace($call.name)) { throw 'Expected a named tool call.' }
            [pscustomobject]@{ Name = $call.name.ToLowerInvariant(); Arguments = $call.args }
        }
        return
    }
    $names = @('toolName', 'tool_name' | Where-Object { $Hook.PSObject.Properties[$_] })
    $arguments = @('toolArgs', 'tool_input' | Where-Object { $Hook.PSObject.Properties[$_] })
    if ($names.Count -gt 1 -or $arguments.Count -ne 1) { throw 'Ambiguous or missing tool input.' }
    $name = $DefaultTool
    if ($names.Count -eq 1) { $name = $Hook.($names[0]) }
    if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name)) { throw 'Expected a tool name.' }
    [pscustomobject]@{ Name = $name.ToLowerInvariant(); Arguments = $Hook.($arguments[0]) }
}

function Get-SquadHookArgument {
    param($Call)
    $arguments = $Call.Arguments
    if ($arguments -is [string]) {
        if (-not $arguments.TrimStart().StartsWith('{')) { throw 'Expected a tool arguments object.' }
        $arguments = $arguments | ConvertFrom-Json -ErrorAction Stop
    }
    if ($arguments -isnot [pscustomobject]) { throw 'Expected a tool arguments object.' }
    return $arguments
}

function Get-SquadHookCommand {
    param($Call)
    $arguments = Get-SquadHookArgument -Call $Call
    if ($arguments.command -isnot [string] -or [string]::IsNullOrWhiteSpace($arguments.command)) {
        throw 'Expected a non-empty command string.'
    }
    return $arguments.command
}

function Get-SquadHookWorkspace {
    param($Hook)
    if ($Hook.cwd -isnot [string] -or [string]::IsNullOrWhiteSpace($Hook.cwd) -or
        -not [IO.Path]::IsPathRooted($Hook.cwd) -or $Hook.cwd -match '^[\\/]{2}' -or
        [IO.Path]::GetPathRoot($Hook.cwd) -notmatch '[\\/]$') { throw 'Expected an absolute workspace cwd.' }
    $root = [IO.Path]::GetFullPath($Hook.cwd)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Workspace cwd does not exist.' }
    return $root
}

function Resolve-SquadHookPath {
    param([string]$Workspace, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Expected a file path.' }
    $normalized = $Path.Replace('\', [IO.Path]::DirectorySeparatorChar).Replace('/', [IO.Path]::DirectorySeparatorChar)
    if ([IO.Path]::IsPathRooted($normalized)) {
        if ([IO.Path]::GetPathRoot($normalized) -notmatch '[\\/]$') { throw 'Expected an unambiguous file path.' }
        $full = [IO.Path]::GetFullPath($normalized)
    }
    else { $full = [IO.Path]::GetFullPath((Join-Path $Workspace $normalized)) }
    $prefix = $Workspace.TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
    $comparison = if ([IO.Path]::DirectorySeparatorChar -eq '\') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if (-not $full.StartsWith($prefix, $comparison)) { throw 'File path is outside the workspace.' }
    return $full
}

function Assert-SquadHookAuditPath {
    param([string]$Path)
    $current = $Path
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Audit path contains a link.'
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
}
