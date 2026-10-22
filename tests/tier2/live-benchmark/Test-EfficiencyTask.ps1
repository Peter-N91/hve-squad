#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Independently probes the generated task CLI in separate bounded processes.
.PARAMETER Workspace
    Workspace containing src/task.ps1. Test stores are created outside it.
.EXAMPLE
    ./Test-EfficiencyTask.ps1 -Workspace ./trial/workspace
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Workspace)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1') -Force

if ($MyInvocation.InvocationName -ne '.') {
    $Root = Join-Path ([IO.Path]::GetTempPath()) ('efficiency-grade-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $Root | Out-Null
    $Checks = [Collections.Generic.List[object]]::new()
    try {
        $Script = Join-Path (Resolve-Path -LiteralPath $Workspace) 'src/task.ps1'
        if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) { throw 'Missing src/task.ps1' }
        $Store = Join-Path $Root 'tasks.json'
        $Invoke = {
            param([string[]]$Options)
            $Output = Join-Path $Root ("probe-$([guid]::NewGuid()).json")
            $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments (@('-NoProfile', '-File', $Script, '-Store', $Store) + $Options) -WorkingDirectory $Root -OutputPath $Output -TimeoutSeconds 10
            $Value = $null
            if ($Result.exitCode -eq 0 -and $Result.stopCause -eq 'none') { $Value = Get-Content -LiteralPath $Output -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate }
            @{ ok = ($Result.exitCode -eq 0 -and $Result.stopCause -eq 'none'); rejected = ($null -ne $Result.exitCode -and $Result.exitCode -ne 0 -and $Result.stopCause -eq 'none'); value = $Value; exitCode = $Result.exitCode; stopCause = $Result.stopCause }
        }
        $Record = { param([string]$Name, [bool]$Passed) $Checks.Add([pscustomobject]@{ name = $Name; passed = $Passed }) }
        $Empty = & $Invoke -Options @('-Action', 'list')
        & $Record 'empty-list' ($Empty.ok -and $Empty.value -is [array] -and $Empty.value.Count -eq 0)
        $Title = 'Follow up ' + [char]0x00E9
        $First = & $Invoke -Options @('-Action', 'add', '-Title', $Title)
        & $Record 'add-unicode' ($First.ok -and $First.value['title'] -ceq $Title -and $First.value['status'] -eq 'open' -and $First.value['id'] -gt 0)
        $Second = & $Invoke -Options @('-Action', 'add', '-Title', 'Second task')
        & $Record 'unique-increasing-id' ($Second.ok -and $Second.value['id'] -gt $First.value['id'])
        $List = & $Invoke -Options @('-Action', 'list')
        & $Record 'persistent-ordered-list' ($List.ok -and $List.value -is [array] -and $List.value.Count -eq 2 -and $List.value[0]['id'] -eq $First.value['id'] -and $List.value[1]['id'] -eq $Second.value['id'])
        $Done = & $Invoke -Options @('-Action', 'done', '-Id', [string]$First.value['id'])
        $Again = & $Invoke -Options @('-Action', 'done', '-Id', [string]$First.value['id'])
        & $Record 'done-idempotent' ($Done.ok -and $Again.ok -and $Again.value['status'] -eq 'done' -and $Again.value['title'] -ceq $Title)
        $Open = & $Invoke -Options @('-Action', 'list', '-Status', 'open')
        $Closed = & $Invoke -Options @('-Action', 'list', '-Status', 'done')
        & $Record 'status-filter' ($Open.ok -and $Closed.ok -and $Open.value.Count -eq 1 -and $Closed.value.Count -eq 1 -and $Open.value[0]['id'] -eq $Second.value['id'] -and $Closed.value[0]['id'] -eq $First.value['id'])
        foreach ($Case in @(
            @{ name = 'missing-title'; args = @('-Action', 'add') },
            @{ name = 'blank-title'; args = @('-Action', 'add', '-Title', '   ') },
            @{ name = 'unknown-id'; args = @('-Action', 'done', '-Id', '999999') },
            @{ name = 'invalid-action'; args = @('-Action', 'erase') },
            @{ name = 'invalid-filter'; args = @('-Action', 'list', '-Status', 'invalid') }
        )) {
            $Before = (Get-FileHash -LiteralPath $Store).Hash
            $Bad = & $Invoke -Options $Case.args
            & $Record $Case.name ($Bad.rejected -and (Get-FileHash -LiteralPath $Store).Hash -eq $Before)
        }
        Set-Content -LiteralPath $Store -Value '{invalid-json' -NoNewline
        $Before = (Get-FileHash -LiteralPath $Store).Hash
        $Bad = & $Invoke -Options @('-Action', 'list')
        & $Record 'corrupt-store-preserved' ($Bad.rejected -and (Get-FileHash -LiteralPath $Store).Hash -eq $Before)
        $BoundaryPassed = $true
        foreach ($Maximum in @([long][int]::MaxValue, [long]::MaxValue)) {
            $Seed = @(@{ id = $Maximum; title = 'Boundary task'; status = 'open' })
            ConvertTo-Json -InputObject $Seed -Compress | Set-Content -LiteralPath $Store -NoNewline -Encoding utf8NoBOM
            $Before = (Get-FileHash -LiteralPath $Store).Hash
            $Boundary = & $Invoke -Options @('-Action', 'add', '-Title', 'After boundary')
            $Preserved = $false
            if ($Maximum -lt [long]::MaxValue -and $Boundary.ok -and $Boundary.value -is [Collections.IDictionary] -and ($Boundary.value['id'] -is [int] -or $Boundary.value['id'] -is [long]) -and $Boundary.value['id'] -gt $Maximum) {
                $List = & $Invoke -Options @('-Action', 'list')
                $Done = & $Invoke -Options @('-Action', 'done', '-Id', [string]$Boundary.value['id'])
                $Preserved = ($List.ok -and $List.value -is [array] -and $List.value.Count -eq 2 -and $List.value[0]['id'] -eq $Maximum -and $List.value[0]['title'] -ceq 'Boundary task' -and $List.value[0]['status'] -eq 'open' -and $List.value[1]['id'] -eq $Boundary.value['id'] -and $Done.ok -and $Done.value['id'] -eq $Boundary.value['id'] -and $Done.value['title'] -ceq 'After boundary' -and $Done.value['status'] -eq 'done')
            } elseif ($Boundary.rejected) {
                $Preserved = (Test-Path -LiteralPath $Store -PathType Leaf) -and (Get-FileHash -LiteralPath $Store).Hash -eq $Before
            }
            $BoundaryPassed = $BoundaryPassed -and $Preserved
        }
        & $Record 'id-boundary-preserves-store' $BoundaryPassed
    }
    catch { $Checks.Add([pscustomobject]@{ name = 'grader-completed'; passed = $false }) }
    finally { Remove-Item -LiteralPath $Root -Recurse -Force }
    [pscustomobject]@{ passed = ($Checks.Count -eq 13 -and @($Checks | Where-Object { -not $_.passed }).Count -eq 0); checks = @($Checks) } | ConvertTo-Json -Depth 5
}