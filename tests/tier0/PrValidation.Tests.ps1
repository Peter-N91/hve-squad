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
    $script:SyncWorkflow = Get-Content -LiteralPath (Join-Path $SourceRoot '.github/workflows/sync-hve-core.yml') -Raw
    $script:Tier0Workflow = Get-Content -LiteralPath (Join-Path $SourceRoot '.github/workflows/tier0-conformance.yml') -Raw
    $script:ReleaseWorkflow = Get-Content -LiteralPath (Join-Path $SourceRoot '.github/workflows/release.yml') -Raw
    $script:ReleasePrepWorkflow = Get-Content -LiteralPath (Join-Path $SourceRoot '.github/workflows/release-prep.yml') -Raw
    function Get-WorkflowStepScript([string]$Name) {
        $step = [regex]::Match($workflow, "(?ms)^      - name: $([regex]::Escape($Name))\r?`n.*?(?=^      - name:|\z)").Value
        $body = [regex]::Match($step, '(?ms)^        run: \|\r?\n(?<body>.*?)(?=^ {0,9}\S|\z)').Groups['body'].Value
        if (-not $body) { throw "Missing workflow script: $Name" }
        $body -replace '(?m)^ {10}', ''
    }
    function Get-WorkflowStepBlock([string]$Body, [string]$Name) {
        $step = [regex]::Match($Body, "(?ms)^      - name: $([regex]::Escape($Name))\r?`n.*?(?=^      - name:|\z)").Value
        if (-not $step) { throw "Missing workflow step: $Name" }
        $step
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

Describe 'CI-02 hve-core sync validates before publication' {
    It 'runs candidate Tier 0 after regeneration and before fragment creation or push' {
        $names = @(
            'Regenerate apm.yml dependencies'
            'Install the APM CLI for candidate conformance'
            'Install Pester for candidate conformance'
            'Validate candidate package before push'
            'Record the pin move'
            'Commit and push'
        )
        $positions = @($names | ForEach-Object { $script:SyncWorkflow.IndexOf("- name: $_") })
        $positions | ForEach-Object { $_ | Should -BeGreaterOrEqual 0 }
        for ($i = 1; $i -lt $positions.Count; $i++) {
            $positions[$i] | Should -BeGreaterThan $positions[$i - 1]
        }

        $validation = Get-WorkflowStepBlock -Body $script:SyncWorkflow -Name 'Validate candidate package before push'
        $validation | Should -Match 'Invoke-Tier0Tests\.ps1 -SourceRoot \. -Output Detailed'
        $validation | Should -Match "steps\.castguard\.outputs\.is_breaking == 'false'"
        $validation | Should -Match "inputs\.dry_run != 'true'"
    }

    It 'keeps dependency pushes on rolling preview and releases only by explicit dispatch' {
        $script:ReleaseWorkflow | Should -Match '(?m)^  workflow_dispatch:\s*$'
        $script:ReleaseWorkflow | Should -Not -Match '(?m)^  push:\s*$'
        $script:ReleasePrepWorkflow | Should -Match 'gh workflow run release\.yml --ref main'
        $script:SyncWorkflow | Should -Match 'refresh the rolling preview'
    }

    It 'retries the exact Pester install used by PR, sync, and release conformance' {
        foreach ($entry in @(
                @{ Body = $script:Tier0Workflow; Name = 'Install Pester' }
                @{ Body = $script:SyncWorkflow; Name = 'Install Pester for candidate conformance' }
                @{ Body = $script:ReleaseWorkflow; Name = 'Install Pester' }
            )) {
            $step = Get-WorkflowStepBlock -Body $entry.Body -Name $entry.Name
            $step | Should -Match ([regex]::Escape('for ($attempt = 1; $attempt -le 3; $attempt++)'))
            $step | Should -Match 'Install-Module Pester -RequiredVersion 5\.7\.1.+-ErrorAction Stop'
            $step | Should -Match ([regex]::Escape('Start-Sleep -Seconds (5 * $attempt)'))
        }
    }
}
