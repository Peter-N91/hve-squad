#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the Tier 1 live behavioral scenarios against a provisioned squad package.
.DESCRIPTION
    Each scenario provisions a scratch repository, installs the package into it,
    copies a fixture on top, and drives one or more headless Copilot CLI turns. What
    the run leaves on disk is then asserted by the Tier 1 state contract and reduced
    to an observation for Tier 2.

    This is the only tier that spends Copilot requests, so it is gated on a secret and
    a pinned model, its fixtures are deliberately tiny, and every turn carries a
    timeout. A failed scenario is retried once before it is called a failure, because a
    single nondeterministic run cannot distinguish a flake from a regression; both
    attempts are kept.

    The assertions never read the run's prose. They read files. See
    tests/squad-behavior-contract.md.
.PARAMETER Ref
    Published ref to install and exercise, for example 'v0.16.0'.
.PARAMETER SourceRoot
    Repository root to install from and overlay, for testing a branch.
.PARAMETER Scenario
    Scenario ids to run. Defaults to every scenario in scenarios/.
.PARAMETER Model
    Model to pin. Results across runs are not comparable without this.
.PARAMETER ResultRoot
    Directory to write transcripts, observations, and the summary into.
.PARAMETER WorkspaceRoot
    Directory to provision scratch repositories under. Defaults to the temp directory.
.PARAMETER Retries
    Extra attempts per scenario after the first failure.
.PARAMETER TimeoutMinutes
    Per-turn timeout. A hung turn must not stall a release.
.PARAMETER ProvisionOnly
    Build each scenario's workspace and stop before the first turn. Spends no Copilot
    requests and needs no token; proves the install, overlay, fixture, and git baseline
    work before a live run pays to discover otherwise.
.EXAMPLE
    ./Invoke-Tier1LiveRun.ps1 -SourceRoot . -ProvisionOnly
.EXAMPLE
    ./Invoke-Tier1LiveRun.ps1 -SourceRoot . -Scenario single-init
.EXAMPLE
    ./Invoke-Tier1LiveRun.ps1 -Ref v0.16.0
#>
[CmdletBinding(DefaultParameterSetName = 'Ref')]
param(
    [Parameter(ParameterSetName = 'Ref')]
    [string]$Ref = 'main',

    [Parameter(Mandatory, ParameterSetName = 'Source')]
    [string]$SourceRoot,

    [string[]]$Scenario,

    [string]$Model = 'claude-sonnet-5',

    [string]$ResultRoot,

    [string]$WorkspaceRoot,

    [int]$Retries = 1,

    [int]$TimeoutMinutes = 20,

    [switch]$ProvisionOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'SquadRun.psm1') -Force

# Everything except the turns themselves is free, and a first live run that dies on a
# provisioning bug after paying for three turns is the waste worth avoiding.
if (-not $ProvisionOnly) {
    if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
        throw "The 'copilot' CLI was not found on PATH. Install @github/copilot at a pinned version first."
    }

    # Fail on the missing secret rather than on the CLI's generic authentication error,
    # which reads like an expired token and sends you looking at the wrong credential.
    if (-not $env:COPILOT_GITHUB_TOKEN) {
        throw 'COPILOT_GITHUB_TOKEN is not set. Tier 1 needs a token carrying the Copilot Requests permission.'
    }
}

if (-not $ResultRoot) { $ResultRoot = Join-Path $PSScriptRoot 'results' }
if (-not $WorkspaceRoot) {
    $WorkspaceRoot = Join-Path ([System.IO.Path]::GetTempPath()) "hve-squad-tier1-live-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
}

New-Item -ItemType Directory -Path $ResultRoot -Force | Out-Null
New-Item -ItemType Directory -Path $WorkspaceRoot -Force | Out-Null
$ResultRoot = (Resolve-Path -LiteralPath $ResultRoot).Path

$scenarioFiles = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'scenarios') -Filter '*.json' -File | Sort-Object Name)
if ($Scenario) {
    $scenarioFiles = @($scenarioFiles | Where-Object { $_.BaseName -in $Scenario })
}
if ($scenarioFiles.Count -eq 0) {
    throw "No scenarios matched. Available: $((Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'scenarios') -Filter '*.json').BaseName -join ', ')"
}

$fixtureRoot = Join-Path $PSScriptRoot '..' 'fixtures'
$contractRunner = Join-Path $PSScriptRoot 'Invoke-Tier1Tests.ps1'
$summary = @()

foreach ($file in $scenarioFiles) {
    $definition = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    $scenarioResult = $null

    foreach ($attempt in 1..($Retries + 1)) {
        Write-Host "[$($definition.id)] attempt $attempt of $($Retries + 1)" -ForegroundColor Cyan

        $attemptRoot = Join-Path $ResultRoot $definition.id "attempt-$attempt"
        New-Item -ItemType Directory -Path $attemptRoot -Force | Out-Null

        $workspace = Join-Path $WorkspaceRoot "$($definition.id)-$attempt"
        $fixture = Join-Path $fixtureRoot $definition.fixture

        $failures = @()
        $turnLog = @()
        $answer = ''

        try {
            $install = if ($PSCmdlet.ParameterSetName -eq 'Source') {
                New-SquadWorkspace -Destination $workspace -FixturePath $fixture -SourceRoot $SourceRoot
            }
            else {
                New-SquadWorkspace -Destination $workspace -FixturePath $fixture -Ref $Ref
            }

            if ($ProvisionOnly) {
                foreach ($expected in @('.github/agents/squad-coordinator.agent.md', '.agents/skills/squad/SKILL.md', 'README.md')) {
                    if (-not (Test-Path -LiteralPath (Join-Path $install.Root $expected))) {
                        $failures += "provisioned workspace is missing '$expected'"
                    }
                }

                Push-Location $install.Root
                try {
                    $dirty = @(& git status --porcelain)
                    if ($dirty.Count -gt 0) {
                        $failures += "workspace is not clean before the first turn, so deliverable detection would report $($dirty.Count) pre-existing change(s)"
                    }
                }
                finally {
                    Pop-Location
                }

                Write-Host "  provisioned $($install.Root)" -ForegroundColor DarkGray
            }
            else {
                foreach ($turn in $definition.turns) {
                    $transcript = Join-Path $attemptRoot "turn-$($turn.id).log"
                    $result = Invoke-SquadTurn -Workspace $install.Root -Prompt $turn.prompt -Model $Model `
                        -TranscriptPath $transcript -TimeoutMinutes $TimeoutMinutes

                    $turnLog += [pscustomobject]@{
                        id       = $turn.id
                        exitCode = $result.ExitCode
                        timedOut = $result.TimedOut
                        seconds  = $result.Seconds
                    }
                    $answer = $result.Answer

                    Write-Host "  turn '$($turn.id)': exit $($result.ExitCode) in $($result.Seconds)s" -ForegroundColor DarkGray

                    if ($result.TimedOut) { $failures += "turn '$($turn.id)' exceeded $TimeoutMinutes minutes" }
                    elseif ($result.ExitCode -ne 0) { $failures += "turn '$($turn.id)' exited $($result.ExitCode): $($result.ErrorLog)" }

                    # A turn that never ran cannot leave the state the next turn assumes.
                    if ($failures) { break }
                }

                $squadRoots = @(Get-Item -Path (Join-Path $install.Root $definition.squadRootGlob) -ErrorAction SilentlyContinue |
                        Where-Object { $_.PSIsContainer } | ForEach-Object { $_.FullName })

                if ($squadRoots.Count -eq 0) {
                    $failures += "No squad root matched '$($definition.squadRootGlob)'. The run did not initialize, or it wrote state somewhere else."
                }

                $observation = Get-RunObservation -Workspace $install.Root -ScenarioId $definition.id `
                    -SquadRoot $squadRoots -Answer $answer -Metadata @{
                    model   = $Model
                    mode    = $install.Mode
                    ref     = $install.Ref
                    attempt = $attempt
                    turns   = @($definition.turns | ForEach-Object { $_.id })
                }

                $observation | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $attemptRoot 'observation.json') -Encoding utf8NoBOM

                # The state contract is the gate; the observation above only feeds Tier 2.
                $contractArgs = @('-NoProfile', '-File', $contractRunner, '-Output', 'Detailed')
                if (-not $definition.expectDispatches) { $contractArgs += '-InitOnly' }

                foreach ($root in $squadRoots) {
                    $name = Split-Path $root -Leaf
                    & pwsh @contractArgs -SquadRoot $root 2>&1 |
                        Tee-Object -FilePath (Join-Path $attemptRoot "contract-$name.log")

                    if ($LASTEXITCODE -ne 0) { $failures += "state contract failed for '$name'" }

                    $produced = Join-Path $PSScriptRoot 'tier1-results.xml'
                    if (Test-Path -LiteralPath $produced) {
                        Move-Item -LiteralPath $produced -Destination (Join-Path $attemptRoot "contract-$name.xml") -Force
                    }
                }

                # The state tree is the evidence for any failure, so keep it with the attempt.
                foreach ($root in $squadRoots) {
                    $name = Split-Path $root -Leaf
                    Copy-Item -LiteralPath $root -Destination (Join-Path $attemptRoot "state-$name") -Recurse -Force
                }

                # Deliverables land beside the squad root, not inside it, so capturing only
                # the squad root leaves every artifact the contract reconciles against
                # unavailable to anyone reading the uploaded results.
                $tracking = Join-Path $install.Root '.copilot-tracking'
                if (Test-Path -LiteralPath $tracking) {
                    Copy-Item -LiteralPath $tracking -Destination (Join-Path $attemptRoot 'tracking') -Recurse -Force
                }
            }
        }
        catch {
            $failures += "harness error: $($_.Exception.Message)"
        }

        $scenarioResult = [pscustomobject]@{
            scenario = $definition.id
            attempt  = $attempt
            passed   = @($failures).Count -eq 0
            failures = @($failures)
            turns    = @($turnLog)
        }

        $scenarioResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $attemptRoot 'result.json') -Encoding utf8NoBOM

        if ($scenarioResult.passed) { break }
        Write-Host "  failed: $($failures -join '; ')" -ForegroundColor Yellow
    }

    $summary += $scenarioResult
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ResultRoot 'tier1-summary.json') -Encoding utf8NoBOM

$failed = @($summary | Where-Object { -not $_.passed })
Write-Host ''
Write-Host "Tier 1 live: $(@($summary).Count - $failed.Count) passed, $($failed.Count) failed" -ForegroundColor ($failed ? 'Red' : 'Green')
foreach ($item in $failed) {
    Write-Host "  $($item.scenario): $($item.failures -join '; ')" -ForegroundColor Red
}

if ($failed) { exit 1 }
