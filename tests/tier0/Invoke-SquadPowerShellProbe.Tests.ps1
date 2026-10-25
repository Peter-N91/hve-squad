#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# AI cost: none; executes isolated local PowerShell fixtures.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll.')]
param([Parameter(Mandatory)][string]$PackageRoot)

BeforeAll {
    $script:Probe = Join-Path $PackageRoot '.agents/skills/squad/scripts/Invoke-SquadPowerShellProbe.ps1'

    function New-ProbeFixture {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Creates only owned TestDrive fixtures; prompting would invalidate test setup.')]
        [CmdletBinding()]
        param([string]$Body = 'param([string]$Marker) [IO.File]::WriteAllText($Marker, "executed")')
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($root)
        $fixture = @{
            ScriptPath = Join-Path $root "probe [literal] 'script'.ps1"
            ParametersPath = Join-Path $root "input [literal] 'args'.json"
            Marker = Join-Path $root 'unexpected.txt'
        }
        [IO.File]::WriteAllText($fixture.ScriptPath, $Body)
        [IO.File]::WriteAllText($fixture.ParametersPath, (ConvertTo-Json @{ Marker = $fixture.Marker }))
        $fixture
    }

    function Invoke-ProbeFixture {
        param([string]$ScriptPath, [string]$ParametersPath, [int]$TimeoutSeconds = 10)
        $start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $script:Probe, '-ScriptPath', $ScriptPath, '-ParametersPath', $ParametersPath, '-TimeoutSeconds', "$TimeoutSeconds")) {
            $start.ArgumentList.Add($argument)
        }
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [Text.Encoding]::UTF8
        $start.StandardErrorEncoding = [Text.Encoding]::UTF8
        $process = [Diagnostics.Process]::Start($start)
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(30000)) { $process.Kill($true); $process.WaitForExit(); throw 'Probe test watchdog expired.' }
            @{
                ExitCode = $process.ExitCode
                Result = ($stdout.GetAwaiter().GetResult() | ConvertFrom-Json -AsHashtable)
                ErrorText = $stderr.GetAwaiter().GetResult()
            }
        }
        finally { $process.Dispose() }
    }
}

Describe 'PowerShell runtime probes (PRB-01)' {
    It 'rejects relative, missing and wrong-extension paths before launching the target' {
        $fixture = New-ProbeFixture
        $wrong = Join-Path (Split-Path $fixture.ScriptPath) 'wrong.txt'
        [IO.File]::WriteAllText($wrong, 'unused')
        foreach ($paths in @(
                @('relative.ps1', $fixture.ParametersPath),
                @((Join-Path $TestDrive 'missing.ps1'), $fixture.ParametersPath),
                @($wrong, $fixture.ParametersPath),
                @($fixture.ScriptPath, 'relative.json'),
                @($fixture.ScriptPath, (Join-Path $TestDrive 'missing.json')),
                @($fixture.ScriptPath, $wrong)
            )) {
            $result = Invoke-ProbeFixture -ScriptPath $paths[0] -ParametersPath $paths[1]
            $result.ExitCode | Should -Be 1
            $result.Result.status | Should -Be 'invalid-input'
            Test-Path -LiteralPath $fixture.Marker | Should -BeFalse
        }
    }

    It 'rejects malformed and non-object JSON without executing the target' {
        $fixture = New-ProbeFixture
        foreach ($json in @('{invalid', 'null', '[]', '42', '"text"')) {
            [IO.File]::WriteAllText($fixture.ParametersPath, $json)
            $result = Invoke-ProbeFixture -ScriptPath $fixture.ScriptPath -ParametersPath $fixture.ParametersPath
            $result.ExitCode | Should -Be 1
            $result.Result.status | Should -Be 'invalid-input'
            Test-Path -LiteralPath $fixture.Marker | Should -BeFalse
        }
    }

    It 'round-trips literal paths and inert structured parameters in an isolated child with closed stdin' {
        $fixture = New-ProbeFixture -Body @'
param([string]$Text, [object]$Nested)
$global:SquadProbeChildOnly = 'child'
@{ pid = $PID; input = [Console]::In.ReadToEnd(); text = $Text; nested = $Nested } | ConvertTo-Json -Depth 10 -Compress
'@
        $text = '$([IO.File]::WriteAllText("' + $fixture.Marker + '","unexpected")); quotes '' " [brackets]'
        $parameters = @{ Text = $text; Nested = @{ list = @(1, 2); flag = $true } }
        [IO.File]::WriteAllText($fixture.ParametersPath, (ConvertTo-Json $parameters -Depth 10))
        $result = Invoke-ProbeFixture -ScriptPath $fixture.ScriptPath -ParametersPath $fixture.ParametersPath
        $result.ExitCode | Should -Be 0 -Because $result.ErrorText
        $result.Result.status | Should -Be 'completed'
        $value = $result.Result.stdout | ConvertFrom-Json -AsHashtable
        $value.pid | Should -Not -Be $PID
        $value.input | Should -BeExactly ''
        $value.text | Should -BeExactly $text
        $value.nested.list | Should -Be @(1, 2)
        $value.nested.flag | Should -BeTrue
        Get-Variable SquadProbeChildOnly -Scope Global -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Test-Path -LiteralPath $fixture.Marker | Should -BeFalse
    }

    It 'preserves separate UTF-8 streams and actual exit7 as a helper failure' {
        $fixture = New-ProbeFixture -Body '[Console]::Out.Write("caf" + [char]0xE9); [Console]::Error.Write("err" + [char]0xE9); exit 7'
        [IO.File]::WriteAllText($fixture.ParametersPath, '{}')
        $result = Invoke-ProbeFixture -ScriptPath $fixture.ScriptPath -ParametersPath $fixture.ParametersPath
        $result.ExitCode | Should -Be 7
        $result.Result.status | Should -Be 'failed'
        $result.Result.exitCode | Should -Be 7
        $result.Result.stdout | Should -BeExactly ('caf' + [char]0xE9)
        $result.Result.stderr | Should -BeExactly ('err' + [char]0xE9)
    }

    It 'keeps binding and runtime exceptions nonzero instead of approving an unexecuted probe' {
        foreach ($body in @('param([ValidateSet("ok")][string]$Action) "unexpected"', 'param([string]$Action) throw "expected runtime failure"')) {
            $fixture = New-ProbeFixture -Body $body
            [IO.File]::WriteAllText($fixture.ParametersPath, '{"Action":"invalid"}')
            $result = Invoke-ProbeFixture -ScriptPath $fixture.ScriptPath -ParametersPath $fixture.ParametersPath
            $result.ExitCode | Should -Be 1
            $result.Result.status | Should -Be 'failed'
            $result.Result.stdout | Should -BeExactly ''
            $result.Result.stderr | Should -Not -BeNullOrEmpty
        }
    }

    It 'terminates an over-time child and reports a nonzero timeout' {
        $fixture = New-ProbeFixture -Body 'while ($true) { Start-Sleep -Milliseconds 100 }'
        [IO.File]::WriteAllText($fixture.ParametersPath, '{}')
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-ProbeFixture -ScriptPath $fixture.ScriptPath -ParametersPath $fixture.ParametersPath -TimeoutSeconds 1
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 15
        $result.ExitCode | Should -Be 124
        $result.Result.status | Should -Be 'timeout'
    }
}
