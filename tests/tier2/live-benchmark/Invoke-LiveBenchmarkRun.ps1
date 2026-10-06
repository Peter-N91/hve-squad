#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs ONE live squad session for one (level, arm) on a freshly materialised fixture. Spends credits.
.DESCRIPTION
    Materialises the inventory fixture as a new git repository with no remote, overlays the
    arm's squad source the same way the Tier 1 harness does, then runs the Copilot CLI
    non-interactively with the squad coordinator. Evidence lands under -TrialRoot:
    workspace/ (the repository the squad changed) and out/ (metadata.json, result.json,
    usage.json, events.jsonl, stderr.txt, logs/). Score it with Measure-LiveBenchmarkRun.ps1.

    Hygiene: no remote, delete/network/push shell verbs denied, token variables declared
    secret so the CLI strips them from shell environments and redacts them from output.
    Nothing here writes a credential anywhere.
.PARAMETER Src
    The arm's squad-src directory.
.PARAMETER Level
    easy, medium, or hard.
.PARAMETER Arm
    B (baseline routing), R (routing=ranked), or E (routing=economy). Only the routing
    token in the prompt depends on it; the source comes from -Src.
.PARAMETER TrialRoot
    New directory for this run's evidence. Must not exist.
.PARAMETER Model
    Coordinator session model. Defaults to claude-sonnet-5.
.EXAMPLE
    ./Invoke-LiveBenchmarkRun.ps1 -Src ../../../squad-src -Level easy -Arm B -TrialRoot $env:TEMP/lb/easy-B-r1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Src,
    [Parameter(Mandatory)][ValidateSet('easy', 'medium', 'hard')][string]$Level,
    [Parameter(Mandatory)][ValidateSet('A', 'B', 'C', 'D', 'E')][string]$Arm,
    [Parameter(Mandatory)][string]$TrialRoot,
    [string]$RunId = "$Level-$Arm",
    [int]$Repeat = 1,
    [int]$Position = 1,
    [string]$Model = 'claude-sonnet-5',
    [string]$CliPath = (Join-Path $env:APPDATA 'npm/copilot.ps1'),
    [AllowEmptyString()][string]$DisabledMcpServers = '',
    [AllowEmptyString()][string]$InstallRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
Import-Module (Join-Path $PSScriptRoot 'LiveBenchmark.psm1') -Force
Import-Module (Join-Path $repoRoot 'tests/lib/SquadInstall.psm1') -Force

if (Test-Path -LiteralPath $TrialRoot) { throw "Trial root already exists: $TrialRoot" }
if (-not (Test-Path -LiteralPath (Join-Path $Src '.github/agents'))) { throw "Not a squad-src directory: $Src" }
if (-not (Test-Path -LiteralPath $CliPath)) { throw "Copilot CLI not found: $CliPath" }
if ([string]::IsNullOrWhiteSpace($DisabledMcpServers)) {
    $disabledServers = @(Get-ConfiguredMcpServerNames -CliPath $CliPath)
}
else {
    $disabledServers = @(ConvertFrom-McpServerArgument -Names $DisabledMcpServers)
}
$Src = (Resolve-Path -LiteralPath $Src).Path

$workspace = Join-Path $TrialRoot 'workspace'
$out = Join-Path $TrialRoot 'out'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$fixture = New-InventoryFixture -Destination $workspace
if ($InstallRoot) {
    foreach ($dir in '.github', '.agents') { Copy-Item -LiteralPath (Join-Path $InstallRoot $dir) -Destination $workspace -Recurse -Force }
}
else { Copy-SquadSource -From $Src -To $workspace }

$prompt = Get-ArmPrompt -Level $Level -Arm $Arm
$deny = @('shell(git push)', 'shell(git remote)', 'shell(git clean)', 'shell(git reset)', 'shell(gh)',
    'shell(rm)', 'shell(rmdir)', 'shell(rd)', 'shell(del)', 'shell(erase)', 'shell(Remove-Item)',
    'shell(curl)', 'shell(wget)', 'shell(Invoke-WebRequest)', 'shell(Invoke-RestMethod)', 'shell(Start-Process)')
$cliArgs = @('-p', $prompt, '--model', $Model, '--agent', 'squad-coordinator',
    '--allow-all-tools', '--no-ask-user', '--disable-builtin-mcps',
    '--output-format', 'json', '--usage-output-file', (Join-Path $out 'usage.json'), '--log-dir', (Join-Path $out 'logs'),
    '--secret-env-vars', 'GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'COPILOT_GITHUB_TOKEN')
foreach ($tool in $deny) { $cliArgs += @('--deny-tool', $tool) }
foreach ($server in $disabledServers) { $cliArgs += @('--disable-mcp-server', $server) }

# Variables an outer agent session sets would make the child think it is nested.
Remove-Item Env:COPILOT_AGENT, Env:COPILOT_DEBUG_NONCE, Env:COPILOT_ENTRA_AUTH_AUD -ErrorAction SilentlyContinue
$env:GIT_TERMINAL_PROMPT = '0'

$srcCommit = (& git -C $Src rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0) { $srcCommit = '' }
$srcDirty = [bool](& git -C $Src status --porcelain -- . 2>$null)
[ordered]@{
    runId           = $RunId
    level           = $Level
    arm             = $Arm
    repeat          = $Repeat
    position        = $Position
    routing         = (Get-ArmRouting -Arm $Arm)
    prompt          = $prompt
    requestedModel  = $Model
    cliVersion      = (@(& $CliPath --version) | Where-Object { $_ } | Select-Object -First 1).Trim()
    src             = $Src
    srcCommit       = "$srcCommit".Trim()
    srcDirty        = $srcDirty
    srcTreeHash     = Get-SourceTreeHash -Path $Src
    baselineCommit  = $fixture.Commit
    deniedTools     = $deny
    disabledMcpServers = $disabledServers
    installed       = [bool]$InstallRoot
    caveats         = @('Source overlay, not a full APM install; no hve-core.', 'Runtime credits are not reconciled billing.')
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'metadata.json') -Encoding utf8NoBOM

$started = Get-Date
Push-Location $workspace
try {
    & $CliPath @cliArgs 1> (Join-Path $out 'events.jsonl') 2> (Join-Path $out 'stderr.txt')
    $cliExit = $LASTEXITCODE
}
finally { Pop-Location }
$finished = Get-Date

$result = [ordered]@{
    runId    = $RunId
    exitCode = $cliExit
    seconds  = [int]($finished - $started).TotalSeconds
    started  = $started.ToUniversalTime().ToString('o')
    finished = $finished.ToUniversalTime().ToString('o')
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'result.json') -Encoding utf8NoBOM
[pscustomobject]$result
