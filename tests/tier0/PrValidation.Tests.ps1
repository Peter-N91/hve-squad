#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Checks PR/release workflow safeguards and change-fragment policy.
# AI cost: none; validates source files without starting CI or a benchmark campaign.

param(
    [Parameter(Mandatory)]
    [string]$SourceRoot
)

BeforeAll {
    $workflow = Get-Content -LiteralPath (Join-Path $SourceRoot '.github/workflows/pr-validation.yml') -Raw
    function Get-WorkflowStepScript([string]$Name) {
        $step = [regex]::Match($workflow, "(?ms)^      - name: $([regex]::Escape($Name))\r?`n.*?(?=^      - name:|\z)").Value
        $body = [regex]::Match($step, '(?ms)^        run: \|\r?\n(?<body>.*?)(?=^ {0,9}\S|\z)').Groups['body'].Value
        if (-not $body) { throw "Missing workflow script: $Name" }
        $body -replace '(?m)^ {10}', ''
    }
    $compute = (Get-WorkflowStepScript 'Compute diff against base').Replace('/tmp/changed.txt', 'changed.txt')
    $guard = Get-WorkflowStepScript 'Reject an unreviewed hve-core pin move'
    function Invoke-FixtureGit {
        & git @args 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Fixture git failed: $args" }
    }
}

Describe 'CI-01 Release-state checks compare the tested merge parent' {
    It '<Case>' -Skip:($IsWindows -or -not (Get-Command bash -ErrorAction SilentlyContinue)) -ForEach @(
        @{ Case = 'accepts an upstream-only pin update despite a stale event base'; ChangePin = $false; ExpectedExit = 0 }
        @{ Case = 'still rejects a real PR pin update'; ChangePin = $true; ExpectedExit = 1 }
    ) {
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $repo | Out-Null
        Push-Location $repo
        $oldBase = $env:BASE_SHA
        $oldOutput = $env:GITHUB_OUTPUT
        try {
            Invoke-FixtureGit init --quiet --initial-branch=main
            Invoke-FixtureGit config user.email fixture@example.invalid
            Invoke-FixtureGit config user.name Fixture
            Set-Content apm.yml 'microsoft/hve-core/path#aaaaaaaa'
            Invoke-FixtureGit add apm.yml
            Invoke-FixtureGit commit --quiet -m initial
            $env:BASE_SHA = (& git rev-parse HEAD).Trim()
            Invoke-FixtureGit switch --quiet -c candidate
            Set-Content candidate.txt candidate
            Invoke-FixtureGit add candidate.txt
            Invoke-FixtureGit commit --quiet -m candidate
            Invoke-FixtureGit switch --quiet main
            Set-Content apm.yml 'microsoft/hve-core/path#bbbbbbbb'
            Invoke-FixtureGit add apm.yml
            Invoke-FixtureGit commit --quiet -m upstream
            $upstream = (& git rev-parse HEAD).Trim()
            Invoke-FixtureGit merge --quiet --no-ff --no-edit candidate
            if ($ChangePin) {
                Set-Content apm.yml 'microsoft/hve-core/path#cccccccc'
                Invoke-FixtureGit add apm.yml
                Invoke-FixtureGit -c core.editor=true commit --quiet --amend --no-edit
            }
            $env:GITHUB_OUTPUT = Join-Path $repo 'output.txt'
            $script = Join-Path $repo 'check.sh'
            [IO.File]::WriteAllText($script, "set -eu`n$compute`n$guard", [Text.UTF8Encoding]::new($false))
            $output = & bash $script 2>&1 | Out-String
            $LASTEXITCODE | Should -Be $ExpectedExit -Because $output
            Get-Content $env:GITHUB_OUTPUT | Should -Contain "base_sha=$upstream"
            $changed = Get-Content changed.txt
            $changed | Should -Contain 'candidate.txt'
            if ($ChangePin) {
                $changed | Should -Contain 'apm.yml'
                $output | Should -Match 'Only the Sync and Adapt workflow'
            }
            else {
                $changed | Should -Not -Contain 'apm.yml'
            }
        }
        finally {
            $env:BASE_SHA = $oldBase
            $env:GITHUB_OUTPUT = $oldOutput
            Pop-Location
        }
    }
}
