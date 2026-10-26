#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs an authorized local PowerShell probe in a bounded, isolated child.
.DESCRIPTION
    AI cost: none. Preloads standard modules and catches runtime/binding errors
    without expensive native error formatting. Parameters remain JSON data.
    Emits one JSON receipt containing status, actual child exitCode, stdout,
    stderr and elapsedSeconds. Child failures remain nonzero; timeout exits 124.
    The helper writes no files. The target can write: this is not a sandbox,
    permission grant, or alternative to retry after a denied command.
.PARAMETER ScriptPath
    Existing literal absolute .ps1 path. Child working directory is its parent.
.PARAMETER ParametersPath
    Existing literal absolute .json path containing one parameter object.
.PARAMETER TimeoutSeconds
    Child execution and stream-drain deadline, from 1 to 300 seconds; default 10.
.EXAMPLE
    ./Invoke-SquadPowerShellProbe.ps1 -ScriptPath /workspace/probes/check.ps1 -ParametersPath /workspace/probes/input.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [Parameter(Mandatory)][string]$ParametersPath,
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 10
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-ProbeInputFailure {
    param([string]$Message)
    [Console]::Error.WriteLine("Invoke-SquadPowerShellProbe: $Message")
    @{ status = 'invalid-input'; exitCode = 1; stdout = ''; stderr = $Message } | ConvertTo-Json -Compress
    exit 1
}

foreach ($inputPath in @(
        @{ path = $ScriptPath; extension = '.ps1' },
        @{ path = $ParametersPath; extension = '.json' }
    )) {
    if (-not [IO.Path]::IsPathFullyQualified($inputPath.path) -or
        [IO.Path]::GetExtension($inputPath.path) -ine $inputPath.extension -or
        -not (Test-Path -LiteralPath $inputPath.path -PathType Leaf)) {
        Write-ProbeInputFailure "Expected an existing absolute $($inputPath.extension) file: $($inputPath.path)"
    }
}
try { $parametersText = [IO.File]::ReadAllText($ParametersPath) }
catch [IO.IOException], [UnauthorizedAccessException] { Write-ProbeInputFailure $_.Exception.Message }
try { $parameters = ConvertFrom-Json -InputObject $parametersText -AsHashtable -Depth 100 }
catch [ArgumentException] { Write-ProbeInputFailure $_.Exception.Message }
if ($parameters -isnot [Collections.IDictionary]) { Write-ProbeInputFailure 'Parameters must be one JSON object.' }

$command = @'
try {
    Import-Module Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility -ErrorAction Stop
    function ConvertFrom-ProbeJsonToken {
        param([Newtonsoft.Json.Linq.JToken]$Token)
        if ($Token -is [Newtonsoft.Json.Linq.JObject]) {
            $Object = [Management.Automation.OrderedHashtable]::new()
            foreach ($Property in $Token.Properties()) {
                $Object.Add($Property.Name, (ConvertFrom-ProbeJsonToken -Token $Property.Value))
            }
            return $Object
        }
        if ($Token -is [Newtonsoft.Json.Linq.JArray]) {
            $Array = [Collections.Generic.List[object]]::new()
            foreach ($Item in $Token) { $Array.Add((ConvertFrom-ProbeJsonToken -Token $Item)) }
            return ,$Array.ToArray()
        }
        return $Token.Value
    }
    $Settings = [Newtonsoft.Json.JsonSerializerSettings]::new()
    $Settings.DateParseHandling = [Newtonsoft.Json.DateParseHandling]::None
    $Settings.MaxDepth = 100
    $Root = [Newtonsoft.Json.JsonConvert]::DeserializeObject(
        [IO.File]::ReadAllText($env:HVE_SQUAD_PROBE_PARAMETERS), [Newtonsoft.Json.Linq.JObject], $Settings)
    $Parameters = ConvertFrom-ProbeJsonToken -Token $Root
    if ($Parameters -isnot [Collections.IDictionary]) { throw 'Parameters must be one JSON object.' }
    $global:LASTEXITCODE = 0
    & $env:HVE_SQUAD_PROBE_SCRIPT @Parameters
    if (-not $?) {
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        exit 1
    }
}
catch [System.Management.Automation.RuntimeException] {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
'@
$start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', $command)) { $start.ArgumentList.Add($argument) }
$start.WorkingDirectory = [IO.Path]::GetDirectoryName($ScriptPath)
$start.UseShellExecute = $false
$start.RedirectStandardInput = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.StandardOutputEncoding = [Text.Encoding]::UTF8
$start.StandardErrorEncoding = [Text.Encoding]::UTF8
$start.Environment['HVE_SQUAD_PROBE_SCRIPT'] = $ScriptPath
$start.Environment['HVE_SQUAD_PROBE_PARAMETERS'] = $ParametersPath
$process = [Diagnostics.Process]::new()
$process.StartInfo = $start
$watch = [Diagnostics.Stopwatch]::StartNew()
try {
    if (-not $process.Start()) { throw 'Probe child did not start.' }
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $timedOut) {
        $remaining = [Math]::Max(0, [int]($TimeoutSeconds * 1000 - $watch.ElapsedMilliseconds))
        $timedOut = -not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), $remaining)
    }
    if ($timedOut -and -not $process.HasExited) {
        $process.Kill($true)
        if (-not $process.WaitForExit(5000)) { throw 'Timed-out probe child did not terminate.' }
    }
    $watch.Stop()
    $result = @{
        status = $(if ($timedOut) { 'timeout' } elseif ($process.ExitCode -ne 0) { 'failed' } else { 'completed' })
        exitCode = $process.ExitCode
        stdout = $(if ($stdout.IsCompletedSuccessfully) { $stdout.GetAwaiter().GetResult() } else { $null })
        stderr = $(if ($stderr.IsCompletedSuccessfully) { $stderr.GetAwaiter().GetResult() } else { $null })
        elapsedSeconds = $watch.Elapsed.TotalSeconds
    }
    $result | ConvertTo-Json -Compress
    if ($timedOut) { exit 124 }
    exit $process.ExitCode
}
finally { $process.Dispose() }
