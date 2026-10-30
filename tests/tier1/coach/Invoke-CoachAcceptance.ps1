#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Captures native, read-only Coach regressions for semantic review.
.DESCRIPTION
    Overlays working-copy Squad sources into isolated consumers, without network-backed
    APM provisioning. This tests the selected installed Coach, not dependency installation.
    Live execution spends Copilot requests and uses the CLI's existing authentication.
    Mechanical checks cover file preservation, discovery-only tool calls, and host syntax.
    Semantic criteria remain NotReviewed until a reviewer assesses the saved responses;
    keyword presence is never a semantic pass.
.PARAMETER Model
    Explicitly pinned Copilot model. Required even for provision-only fixture checks.
.PARAMETER ResultRoot
    Parent for a new, uniquely named run directory. Existing results are never replaced.
.PARAMETER Repetitions
    Independent conversations per case, all retained rather than replacing a failed attempt.
.PARAMETER ProvisionOnly
    Prepare fixtures and review manifests without invoking a model.
.EXAMPLE
    ./tests/tier1/coach/Invoke-CoachAcceptance.ps1 -SourceRoot . -ResultRoot <evidence-root> -Model <model> -Repetitions 2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$ResultRoot,
    [Parameter(Mandatory)][string]$Model,
    [ValidateSet('first-capped-run', 'legacy-artifacts')]
    [string[]]$Case = @('first-capped-run', 'legacy-artifacts'),
    [ValidateRange(1, 10)][int]$Repetitions = 1,
    [ValidateRange(1, 60)][int]$TimeoutMinutes = 10,
    [switch]$ProvisionOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$resolvedSource = (Resolve-Path -LiteralPath $SourceRoot).Path
Import-Module (Join-Path $resolvedSource 'tests/lib/SquadInstall.psm1') -Force
$definitions = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cases.json') -Raw | ConvertFrom-Json
$cases = @($definitions.cases | Where-Object id -In $Case)
if ($cases.Count -ne @($Case | Select-Object -Unique).Count) { throw 'A requested Coach case is missing.' }
$cli = if (-not $ProvisionOnly) { (Get-Command copilot -CommandType Application -ErrorAction Stop).Source }
$cliVersion = if ($ProvisionOnly) { 'NotRun' } else {
    $version = & $cli --no-auto-update --version
    if ($LASTEXITCODE -ne 0) { throw 'Could not identify the native Copilot CLI version.' }
    $version -join "`n"
}
$runRoot = Join-Path $ResultRoot ("coach-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$runRoot = (Resolve-Path -LiteralPath $runRoot).Path

function Get-CoachSnapshot {
    param([string]$Root)
    @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
            [ordered]@{
                path = [IO.Path]::GetRelativePath($Root, $_.FullName)
                kind = if ($_.PSIsContainer) { 'directory' } else { 'file' }
                hash = if ($_.PSIsContainer) { '' } else { (Get-FileHash -LiteralPath $_.FullName).Hash }
                modified = if ($_.PSIsContainer) { '' } else { $_.LastWriteTimeUtc.ToString('O') }
            }
        })
}

$results = @(
    foreach ($definition in $cases) {
        foreach ($attempt in 1..$Repetitions) {
            $attemptRoot = Join-Path $runRoot "$($definition.id)-$attempt"
            $workspace = Join-Path $attemptRoot 'consumer'
            New-Item -ItemType Directory -Path $workspace -Force | Out-Null
            Copy-SquadSource -From (Join-Path $resolvedSource 'squad-src') -To $workspace -NativeCli
            if ($definition.includeProductDocumentation) {
                $product = Join-Path $workspace 'package-docs'
                New-Item -ItemType Directory -Path $product | Out-Null
                foreach ($path in @('README.md', 'apm.yml', 'docs')) {
                    Copy-Item -LiteralPath (Join-Path $resolvedSource $path) -Destination $product -Recurse
                }
            }
            foreach ($file in $definition.files) {
                if ([IO.Path]::IsPathRooted($file.path) -or '..' -in ($file.path -split '[\\/]')) {
                    throw "Fixture path must stay inside its consumer: $($file.path)"
                }
                $target = Join-Path $workspace $file.path
                New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
                Set-Content -LiteralPath $target -Value $file.content -Encoding utf8NoBOM -NoNewline
            }
            & git -C $workspace init --quiet
            if ($LASTEXITCODE -ne 0) { throw "Could not initialize fixture: $workspace" }
            $definition.prompt | Set-Content -LiteralPath (Join-Path $attemptRoot 'prompt.txt') -Encoding utf8NoBOM
            $record = [ordered]@{
                case = $definition.id
                attempt = $attempt
                workspace = $workspace
                model = $Model
                productDocumentation = $definition.includeProductDocumentation
                cliVersion = $cliVersion
                coachSha256 = (Get-FileHash -LiteralPath (Join-Path $workspace '.github/agents/squad-coach.agent.md')).Hash
                discoverySha256 = (Get-FileHash -LiteralPath (Join-Path $workspace '.agents/skills/squad/references/coach-discovery.md')).Hash
                execution = 'Provisioned'
                mechanical = 'NotRun'
                semantic = 'NotReviewed'
                criteria = @($definition.criteria | ForEach-Object {
                        [ordered]@{ id = $_.id; requirement = $_.requirement; sources = $_.sources; verdict = 'NotReviewed'; evidence = '' }
                    })
            }
            $failures = @()
            if (-not $ProvisionOnly) {
                $before = ConvertTo-Json -InputObject @(Get-CoachSnapshot $workspace) -Depth 4 -Compress
                $start = [Diagnostics.ProcessStartInfo]::new()
                $start.FileName = $cli
                $start.WorkingDirectory = $workspace
                $start.UseShellExecute = $false
                $start.RedirectStandardOutput = $true
                $start.RedirectStandardError = $true
                foreach ($argument in @(
                        '--agent', 'squad-coach', '--model', $Model, '--trust-folder',
                        '--allow-all-tools', '--disable-builtin-mcps', '--disable-mcp-server', 'hve-squad',
                        '--no-ask-user', '--no-color', '--no-auto-update', '--output-format', 'json',
                        '--log-dir', (Join-Path $attemptRoot 'logs'),
                        '--usage-output-file', (Join-Path $attemptRoot 'usage.json'), '-p', $definition.prompt
                    )) { $start.ArgumentList.Add($argument) }
                $process = [Diagnostics.Process]::new()
                $process.StartInfo = $start
                $timedOut = $false
                try {
                    if (-not $process.Start()) { throw 'Could not start the native Coach process.' }
                    $stdout = $process.StandardOutput.ReadToEndAsync()
                    $stderr = $process.StandardError.ReadToEndAsync()
                    if (-not $process.WaitForExit($TimeoutMinutes * 60000)) {
                        $timedOut = $true
                        Stop-Process -Id $process.Id -Force
                        $process.WaitForExit()
                        $failures += "Native Coach exceeded $TimeoutMinutes minutes."
                    }
                    $exitCode = $process.ExitCode
                    if ($process.ExitCode -ne 0) { $failures += "Native Coach exited $($process.ExitCode)." }
                    $stdout.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $attemptRoot 'events.jsonl') -Encoding utf8NoBOM -NoNewline
                    $stderr.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $attemptRoot 'stderr.txt') -Encoding utf8NoBOM -NoNewline
                }
                finally { $process.Dispose() }
                $after = ConvertTo-Json -InputObject @(Get-CoachSnapshot $workspace) -Depth 4 -Compress
                $before | Set-Content -LiteralPath (Join-Path $attemptRoot 'before.json') -Encoding utf8NoBOM
                $after | Set-Content -LiteralPath (Join-Path $attemptRoot 'after.json') -Encoding utf8NoBOM
                if ($before -cne $after) { $failures += 'Consumer files or directories changed.' }
                $events = @(Get-Content -LiteralPath (Join-Path $attemptRoot 'events.jsonl') |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
                $messages = @($events | Where-Object type -EQ 'assistant.message' | ForEach-Object { $_.data.content } | Where-Object { $_ })
                $answer = $messages -join "`n`n"
                $answer | Set-Content -LiteralPath (Join-Path $attemptRoot 'response.txt') -Encoding utf8NoBOM
                $tools = @($events | Where-Object type -EQ 'tool.execution_start' | ForEach-Object { $_.data.toolName })
                if (@($tools | Where-Object { $_ -notin 'view', 'rg', 'glob', 'skill' }).Count -gt 0) {
                    $failures += "Unexpected non-discovery tool: $($tools -join ', ')."
                }
                if ($tools.Count -eq 0) { $failures += 'No native source-discovery tool call was recorded.' }
                if (-not $answer.Trim()) { $failures += 'No native assistant response was recorded.' }
                if ($answer -match '(?m)^[ \t]*/squad(?:[- ]|$)') { $failures += 'An actionable Squad slash invocation was returned.' }
                $record.execution = if ($timedOut) { 'TimedOut' } elseif ($exitCode -ne 0) { 'Failed' } else { 'Completed' }
                $record.mechanical = if ($failures.Count) { 'Fail' } else { 'Pass' }
                $record['failures'] = $failures
                $record['tools'] = $tools
            }
            $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $attemptRoot 'review.json') -Encoding utf8NoBOM
            Write-Host "$($definition.id) attempt ${attempt}: $($record.mechanical); semantic review required at $attemptRoot"
            [pscustomobject]$record
        }
    }
)
ConvertTo-Json -InputObject $results -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'results.json') -Encoding utf8NoBOM
if (@($results | Where-Object mechanical -EQ 'Fail').Count) {
    throw "Coach mechanical acceptance failed. Inspect $runRoot."
}
[pscustomobject]@{ Root = $runRoot; Results = $results }
