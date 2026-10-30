#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Deny-Dispatch {
    param([string]$Reason)
    @{ permissionDecision = 'deny'; permissionDecisionReason = $Reason } | ConvertTo-Json -Compress
    exit 0
}

try {
    $inputText = [Console]::In.ReadToEnd()
    $hook = $inputText | ConvertFrom-Json -AsHashtable
    if ($hook -isnot [Collections.IDictionary]) { throw 'Expected a hook input object.' }
    $repo = if ($hook['cwd']) { (Resolve-Path -LiteralPath $hook['cwd']).ProviderPath } else { (Get-Location).ProviderPath }
    $calls = if ($hook.ContainsKey('toolCalls')) { @($hook.toolCalls | Where-Object name -eq 'task') }
    else {
        $arguments = if ($hook.ContainsKey('toolArgs')) { $hook.toolArgs } else { $hook['tool_input'] }
        @(@{ args = $arguments })
    }
    $module = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'skills', 'squad', 'scripts', 'SquadCoordinator.psm1'
    if (-not (Test-Path -LiteralPath $module)) { $module = Join-Path -Path $PSScriptRoot -ChildPath 'runtime' -AdditionalChildPath 'SquadCoordinator.psm1' }
    Import-Module $module -Force
    $agents = Get-SquadAgentIndex $repo

    foreach ($call in $calls) {
        $dispatch = $call.args
        if ($dispatch -is [string]) { $dispatch = $dispatch | ConvertFrom-Json -AsHashtable }
        if ($dispatch -isnot [Collections.IDictionary]) { throw 'Expected task arguments as an object.' }
        $agentType = if ($dispatch['agent_type']) { [string]$dispatch['agent_type'] } else { [string]$dispatch['agentName'] }
        $agentName = $agentType
        if (-not $agents.ContainsKey($agentName) -and $agentType.Contains(':')) {
            $stem = ($agentType -split ':')[-1]
            $nativeMatches = @($agents.Values | Where-Object { ([IO.Path]::GetFileName($_.path) -replace '\.agent\.md$', '') -ceq $stem })
            if ($nativeMatches.Count -gt 1) { Deny-Dispatch "Ambiguous native agent '$agentType'; resolve its installed definition before dispatch." }
            if ($nativeMatches.Count -eq 1) { $agentName = $nativeMatches[0].name }
        }
        $raw = $dispatch | ConvertTo-Json -Depth 20 -Compress
        $root = Join-Path -Path $repo -ChildPath '.copilot-tracking' -AdditionalChildPath 'squad'
        $member = [regex]::Match($raw, 'members[\\/]+([A-Za-z0-9_-]+)')
        if ($member.Success) {
            $name = $member.Groups[1].Value
            if ($name -cnotmatch '^[a-z0-9][a-z0-9-]*$') { Deny-Dispatch "Federation member '$name' must be lower-kebab-case." }
            $memberRoot = Join-Path -Path $root -ChildPath 'members' -AdditionalChildPath $name
            if (Test-Path -LiteralPath (Join-Path $memberRoot 'team.md') -PathType Leaf) { $root = $memberRoot }
        }

        $decisionsPath = Join-Path $root 'decisions.md'
        if ((Test-Path -LiteralPath $decisionsPath) -and $raw -match '(?i)plan|implement|developer|lead') {
            $decisions = [IO.File]::ReadAllText($decisionsPath)
            $verdicts = [regex]::Matches($decisions, '(?ms)^## Intake Readiness Verdict\b.*?(?=^## |\z)')
            if ($verdicts.Count -and $verdicts[-1].Value -match '(?im)^\*\s*Verdict:\s*Not-Ready\b') {
                Deny-Dispatch 'Intake Gate: the latest Intake Readiness Verdict is Not-Ready. Resolve it before planning or implementation.'
            }
        }

        $tracker = '(work items?|jira( (issues?|tickets?))?|github issues?|azure devops|ado|issue tracker|backlog handoff)'
        $verb = '(create|push|apply|sync)'
        $writes = @([regex]::Matches($raw, "(?i)[^.;]{0,40}\b$verb\b[^.;]{0,40}\b$tracker\b|[^.;]{0,40}\b$tracker\b[^.;]{0,15}\b$verb\b") |
                Where-Object { $_.Value -notmatch "(?i)(\bnot|\bnever|\bwithout|n't)\s+(\w+\s+){0,2}$verb\b" })
        if ($writes.Count -and $agentName -notin @('Squad Scribe', 'Squad Backlog Executor')) {
            Deny-Dispatch 'Tracker-Write Gate: only Squad Backlog Executor may perform a tracker write, with recorded approval.'
        }

        $teamPath = Join-Path $root 'team.md'
        if ($agentName -eq 'Squad Scribe' -or -not (Test-Path -LiteralPath $teamPath -PathType Leaf)) { continue }
        $team = [IO.File]::ReadAllText($teamPath)
        if ($team -notmatch '(?m)^Model routing:\s*`?(ranked|economy|manual)`?\s*$') { continue }
        $rows = @(Get-SquadRoster $root | Where-Object {
                $_['Agent Name (Primary)'] -ceq $agentName -or $agentName -cin @($_['Alternate Agents'] -split ',\s*')
            })
        if (-not $rows.Count) { continue }
        $allowed = @($rows | ForEach-Object {
                if ($_.ContainsKey('Model')) { [string]$_.Model }
            } | Where-Object { $_ -and $_ -notin @('-', [string][char]0x2014) } | Select-Object -Unique)
        if (-not $allowed.Count) {
            Deny-Dispatch "Routed-model guard: $agentName has no resolved Model cell in $teamPath. Run New-SquadDispatchPlan.ps1 -ApplyModelRouting before dispatch."
        }
        if ([string]$dispatch['model'] -cnotin $allowed) {
            Deny-Dispatch "Routed-model guard: $teamPath routes $agentName to $($allowed -join ' or '). Copy the planned endpoint.model into the native model argument."
        }
    }
    Write-Output '{"permissionDecision":"allow"}'
}
catch {
    [Console]::Error.WriteLine("dispatch-guards: $($_.Exception.Message)")
    exit 1
}
