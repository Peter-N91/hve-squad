#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Deny-Dispatch {
    param([string]$Reason)
    @{ permissionDecision = 'deny'; permissionDecisionReason = $Reason } | ConvertTo-Json -Compress
    exit 0
}

function Get-SquadIntakeHold {
    param([string]$SquadRoot)
    $path = Join-Path $SquadRoot 'decisions.md'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $verdicts = [regex]::Matches([IO.File]::ReadAllText($path),
        '(?ms)^## Intake Readiness Verdict\b(?<heading>[^\r\n]*)\r?\n(?<body>.*?)(?=^## |\z)')
    if (-not $verdicts.Count) { return }
    $latest = $verdicts[-1]
    $body = $latest.Groups['body'].Value
    if ($body -notmatch '(?im)^\*[ \t]*Verdict:[ \t]*Not-Ready[ \t]*\r?$') { return }
    $topic = [regex]::Match($latest.Groups['heading'].Value, '^[ \t]+\S+[ \t]+(?<id>[a-z0-9]+(?:-[a-z0-9]+)*)[ \t]*$')
    [pscustomobject]@{
        TopicId = $topic.Groups['id'].Value
        CanRemediate = ($body -match '(?m)^\*[ \t]*Remediation Cycles:[ \t]*[01][ \t]*\r?$')
    }
}

function Get-DispatchRosterRow {
    param([object[]]$Roster, [string]$AgentName)
    $Roster | Where-Object {
        $_['Agent Name (Primary)'] -ceq $AgentName -or $AgentName -cin @($_['Alternate Agents'] -split ',\s*')
    }
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
        $squadBase = Join-Path -Path $repo -ChildPath '.copilot-tracking' -AdditionalChildPath 'squad'
        $root = $squadBase
        # A mention in task content cannot choose a different squad's intake verdict.
        $intakeRoot = $squadBase
        $federationPath = Join-Path $squadBase 'federation.md'
        if (Test-Path -LiteralPath $federationPath -PathType Leaf) {
            $scope = [regex]::Match([string]$dispatch['prompt'],
                '\ASquad root: \.copilot-tracking[\\/]squad[\\/]members[\\/](?<member>[a-z0-9]+(?:-[a-z0-9]+)*)(?:\r?\n|\z)')
            $members = @(Read-SquadTables $federationPath | Where-Object {
                    'Sub-squad' -in $_.Header -and 'Location' -in $_.Header -and 'Kind' -in $_.Header
                } | ForEach-Object Rows | Where-Object {
                    $_.Kind -ceq 'in-repo' -and $_['Sub-squad'] -cmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -and
                    ($_['Location'] -replace '\\', '/').TrimEnd('/') -ceq "members/$($_['Sub-squad'])"
                })
            if ($scope.Success) {
                $selectedMember = @($members | Where-Object { $_['Sub-squad'] -ceq $scope.Groups['member'].Value })
                if ($selectedMember.Count -ne 1) { Deny-Dispatch 'Intake Gate: Squad root must identify exactly one registered federation member.' }
                $intakeRoot = Resolve-SquadRepositoryPath -RepoRoot $repo -Path (Join-Path $squadBase $selectedMember[0].Location)
                $root = $intakeRoot
            }
            else {
                foreach ($entry in $members) {
                    $candidate = Join-Path $squadBase $entry.Location
                    if (Get-SquadIntakeHold -SquadRoot $candidate) {
                        Deny-Dispatch 'Intake Gate: a federation member is Not-Ready. Specify its dispatch scope in the Squad root field before starting a worker.'
                    }
                }
            }
        }

        $roster = $null
        $intakeHold = Get-SquadIntakeHold -SquadRoot $intakeRoot
        if ($intakeHold) {
            $root = $intakeRoot
            $roles = @()
            if ($agents.ContainsKey($agentName) -and $agents[$agentName].dispatchable -and
                (Test-Path -LiteralPath (Join-Path $root 'team.md') -PathType Leaf)) {
                $roster = @(Get-SquadRoster $root)
                $rows = @(Get-DispatchRosterRow -Roster $roster -AgentName $agentName)
                $roles = @($rows | ForEach-Object Role | Sort-Object -Unique -CaseSensitive)
            }
            $taskName = if ($dispatch['name']) { [string]$dispatch['name'] } else { [string]$dispatch['description'] }
            $topic = $intakeHold.TopicId
            $role = if ($roles.Count -eq 1) { $roles[0] } else { '' }
            $validation = $role -ceq 'intake-validator'
            $canRemediate = $intakeHold.CanRemediate -and $role -cin @('analyst', 'product-owner')
            $remediation = $topic -and $canRemediate -and $taskName -ceq "intake-remediation-$topic"
            $isScribe = $role -ceq 'scribe' -and $agentName -ceq 'Squad Scribe'
            $handoff = $topic -and $isScribe -and $taskName -ceq "intake-handoff-$topic"
            if (-not ($validation -or $remediation -or $handoff)) {
                Deny-Dispatch 'Intake Gate: the latest Intake Readiness Verdict is Not-Ready. Only the roster intake validator, scoped intake remediation, and intake bookkeeping can run until a new verdict clears the gate.'
            }
        }
        elseif ($root -eq $squadBase) {
            # Keep legacy member model routing for older prompts when no intake hold applies.
            $member = [regex]::Match($raw, 'members[\\/]+([A-Za-z0-9_-]+)')
            if ($member.Success) {
                $name = $member.Groups[1].Value
                if ($name -cnotmatch '^[a-z0-9][a-z0-9-]*$') { Deny-Dispatch "Federation member '$name' must be lower-kebab-case." }
                $memberRoot = Join-Path -Path $squadBase -ChildPath 'members' -AdditionalChildPath $name
                if (Test-Path -LiteralPath (Join-Path $memberRoot 'team.md') -PathType Leaf) { $root = $memberRoot }
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
        if ($null -eq $roster) {
            $roster = @(Get-SquadRoster $root)
            $rows = @(Get-DispatchRosterRow -Roster $roster -AgentName $agentName)
        }
        if ($agentName -ceq 'Squad Connector') {
            # The native hook has an agent type, not a binding ID. Compare against
            # its possible roster targets; the planner still validates the selected binding.
            foreach ($target in @(Get-SquadConnectorReplacementTarget -TeamPath $teamPath)) {
                $rows += @($roster | Where-Object {
                        $_.Role -ceq $target.Role -and [string]$_['Member Name'] -ceq $target.MemberName -and
                        $_['Agent Name (Primary)'] -ceq $target.Agent
                    })
            }
        }
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