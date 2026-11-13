#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
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
    $script:LintWorkflow = Get-Content -LiteralPath (Join-Path $SourceRoot '.github/workflows/lint-powershell.yml') -Raw
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
    It 'runs candidate Tier 0 after regeneration and before fragment creation or PR proposal' {
        $names = @(
            'Regenerate apm.yml dependencies'
            'Install the APM CLI for candidate conformance'
            'Install Pester for candidate conformance'
            'Validate candidate package before push'
            'Record the pin move'
            'Propose sync pull request'
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
        $script:SyncWorkflow | Should -Not -Match 'git push origin main'
    }

    It 'keeps dependency pushes on rolling preview and releases only by explicit dispatch' {
        $script:ReleaseWorkflow | Should -Match '(?m)^  workflow_dispatch:\s*$'
        $script:ReleaseWorkflow | Should -Not -Match '(?m)^  push:\s*$'
        $script:ReleasePrepWorkflow | Should -Match 'gh workflow run release\.yml --ref main'
        $script:SyncWorkflow | Should -Match 'refresh the rolling preview'
    }

    It 'retries the exact Pester install shared by PR, sync, and reusable release conformance' {
        foreach ($entry in @(
                @{ Body = $script:Tier0Workflow; Name = 'Install Pester' }
                @{ Body = $script:SyncWorkflow; Name = 'Install Pester for candidate conformance' }
            )) {
            $step = Get-WorkflowStepBlock -Body $entry.Body -Name $entry.Name
            $step | Should -Match ([regex]::Escape('for ($attempt = 1; $attempt -le 3; $attempt++)'))
            $step | Should -Match 'Install-Module Pester -RequiredVersion 5\.7\.1.+-ErrorAction Stop'
            $step | Should -Match ([regex]::Escape('Start-Sleep -Seconds (5 * $attempt)'))
        }
    }

    Describe 'CI-03 Isolated CI shards retain a fail-closed required check' {
        It 'freezes the planned checkout and preserves the aggregate check name' {
            $script:Tier0Workflow | Should -Match 'ref: \$\{\{ needs\.plan\.outputs\.sha \}\}'
            $script:Tier0Workflow | Should -Match 'shard: \$\{\{ fromJSON\(needs\.plan\.outputs\.shards\) \}\}'
            $script:Tier0Workflow | Should -Match 'fail-fast: true'
            $script:Tier0Workflow | Should -Match '(?s)required:\s+name: Package conformance\s+if: always\(\)\s+needs: \[plan, conformance\]'
            $script:Tier0Workflow | Should -Match '\$PLAN_RESULT" != success \|\| "\$SHARD_RESULT" != success'
            $script:Tier0Workflow | Should -Match 'name: tier0-\$\{\{ inputs.scope \|\| ''All'' \}\}-\$\{\{ matrix.shard \}\}'
            $script:Tier0Workflow | Should -Match 'path: tests/tier0/tier0-results\.xml'
        }

        It 'covers shared installer, canonical hooks, and release workflow changes' {
            foreach ($path in @('tests/lib/**', 'scripts/plugin-hooks/**', '.github/workflows/release.yml')) {
                @([regex]::Matches($script:Tier0Workflow, [regex]::Escape("'$path'"))).Count | Should -Be 2
            }
            $script:Tier0Workflow | Should -Match 'group: \$\{\{ github.workflow \}\}-tier0-'
        }

        It 'keeps legacy hotfix runners unsharded and passes selectors only to capable runners' {
            $script:Tier0Workflow | Should -Match 'Parameters\.ContainsKey\(''Scope''\).*Parameters\.ContainsKey\(''Shard''\)'
            $script:Tier0Workflow | Should -Match ([regex]::Escape('$shards = @(''All'')'))
            $script:Tier0Workflow | Should -Match '(?s)if \(\$env:MODERN_RUNNER -eq ''true''\).*?\$testArgs\.Scope.*?\$testArgs\.Shard'
        }
    }

    Describe 'CI-04 Complementary release validation gates publication' {
        It 'checks repository contracts at the frozen candidate before creating a tag' {
            $script:ReleaseWorkflow | Should -Match '(?s)source_conformance:.*?source-ref: \$\{\{ needs.candidate.outputs.sha \}\}\s+scope: Repository'
            $script:ReleaseWorkflow | Should -Match 'needs: \[candidate, source_conformance\]'
            $script:ReleaseWorkflow | Should -Match 'needs.source_conformance.result == ''success'''
        }

        It 'runs all installed-package cases at the tagged identity before publishing' {
            $script:ReleaseWorkflow | Should -Match '(?s)published_conformance:.*?ref: \$\{\{ needs.tag.outputs.tag \}\}\s+source-ref: \$\{\{ needs.tag.outputs.sha \}\}\s+scope: Package'
            $script:ReleaseWorkflow | Should -Match 'needs: \[candidate, tag, published_conformance\]'
            $script:ReleaseWorkflow | Should -Match 'needs.published_conformance.result == ''success'''
            $script:ReleaseWorkflow | Should -Match '(?s)Checkout verified tag.*?ref: \$\{\{ needs.tag.outputs.sha \}\}'
            @([regex]::Matches($script:ReleaseWorkflow, 'uses: \./\.github/workflows/tier0-conformance\.yml')).Count | Should -Be 2
            $script:ReleaseWorkflow | Should -Not -Match 'run: \./tests/tier0/Invoke-Tier0Tests\.ps1'
        }
    }

    Describe 'CI-05 PowerShell lint installation is reproducible and resilient' {
        It 'uses the checksummed pinned GitHub release instead of the transient gallery index' {
            $script:LintWorkflow | Should -Match 'PSSCRIPTANALYZER_VERSION: ''1\.25\.0'''
            $script:LintWorkflow | Should -Match "PSSCRIPTANALYZER_SHA256: '[A-F0-9]{64}'"
            $script:LintWorkflow | Should -Match 'github\.com/PowerShell/PSScriptAnalyzer/releases/download/\$version/PSScriptAnalyzer\.\$version\.nupkg'
            $script:LintWorkflow | Should -Match 'Get-FileHash -LiteralPath \$package -Algorithm SHA256'
            $script:LintWorkflow | Should -Match 'Import-Module PSScriptAnalyzer -RequiredVersion \$version'
            $script:LintWorkflow | Should -Not -Match 'Install-Module PSScriptAnalyzer'
        }

        It 'uploads SARIF only when the analyzer actually produced it' {
            @([regex]::Matches($script:LintWorkflow, "hashFiles\('results\.sarif'\) != ''")).Count | Should -Be 2
        }
    }

    Describe 'CI-08 Organization token, environment, and PR governance' {
        BeforeAll {
            $script:SourceRootCi08 = (Resolve-Path -LiteralPath $SourceRoot).Path
            $script:PrValidationRaw = Get-Content -LiteralPath (Join-Path $script:SourceRootCi08 '.github/workflows/pr-validation.yml') -Raw
        }

        It 'scopes GitHub App key and Copilot headless tokens to dedicated non-deployment environments without PR key exposure' {
            $python = Get-Command python -ErrorAction Stop
            $inspector = @'
import json, sys, yaml
from pathlib import Path

root = Path(sys.argv[1]) / ".github" / "workflows"
app_jobs = []
app_pr_triggers = []
copilot_jobs = []
for p in sorted(root.glob("*.yml")):
    raw = p.read_text(encoding="utf-8")
    doc = yaml.safe_load(raw)
    on_block = doc.get("on") or doc.get(True) or {}
    on_keys = list(on_block.keys()) if isinstance(on_block, dict) else []
    if "secrets.AUTOMATION_APP_PRIVATE_KEY" in raw:
        if "pull_request" in on_keys or "pull_request_target" in on_keys or "github.event.pull_request" in raw:
            app_pr_triggers.append(p.name)
    for job_name, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict) or "uses" in job:
            continue
        job_json = json.dumps(job)
        env_cfg = job.get("environment") or {}
        if "secrets.AUTOMATION_APP_PRIVATE_KEY" in job_json:
            token_steps = [
                s for s in (job.get("steps") or [])
                if isinstance(s, dict) and str(s.get("uses") or "").startswith("actions/create-github-app-token@")
            ]
            perms = []
            uses_vals = []
            for ts in token_steps:
                uses_vals.append(str(ts.get("uses") or ""))
                w = ts.get("with") or {}
                perms.append(sorted([k for k in w.keys() if str(k).startswith("permission-")]))
            app_jobs.append({
                "workflow": p.name,
                "job": job_name,
                "envName": env_cfg.get("name") if isinstance(env_cfg, dict) else env_cfg,
                "deployment": env_cfg.get("deployment") if isinstance(env_cfg, dict) else None,
                "uses": uses_vals,
                "permKeys": perms,
            })
        if "COPILOT_GITHUB_TOKEN" in job_json or "secrets.copilot-token" in job_json:
            copilot_jobs.append({
                "workflow": p.name,
                "job": job_name,
                "envName": env_cfg.get("name") if isinstance(env_cfg, dict) else env_cfg,
                "deployment": env_cfg.get("deployment") if isinstance(env_cfg, dict) else None,
                "ifExpr": str(job.get("if") or ""),
            })

print(json.dumps({
    "appJobs": app_jobs,
    "appPrTriggers": app_pr_triggers,
    "copilotJobs": copilot_jobs,
}))
'@
            $json = & $python.Source -c $inspector $script:SourceRootCi08
            $LASTEXITCODE | Should -Be 0 -Because ($json -join "`n")
            $data = $json | ConvertFrom-Json

            @($data.appPrTriggers) | Should -BeNullOrEmpty -Because 'no workflow reading AUTOMATION_APP_PRIVATE_KEY may trigger on pull_request or pull_request_target'
            @($data.appJobs).Count | Should -Be 6 -Because 'sync-hve-core, sync-model-benchmarks, release-prep (prepare + dispatch-release), and release (tag + release) must mint scoped GitHub App tokens'
            foreach ($job in @($data.appJobs)) {
                $job.envName | Should -BeExactly 'automation-governance' -Because "$($job.workflow)/$($job.job) must bind to automation-governance"
                $job.deployment | Should -BeFalse -Because "$($job.workflow)/$($job.job) must set deployment: false"
                foreach ($u in @($job.uses)) {
                    $u | Should -BeExactly 'actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510'
                }
                foreach ($pk in @($job.permKeys)) {
                    @($pk).Count | Should -BeGreaterOrEqual 1 -Because "$($job.workflow)/$($job.job) must request explicit permission-* inputs"
                }
            }

            $copilotTargets = @($data.copilotJobs | ForEach-Object { "$($_.workflow):$($_.job)" } | Sort-Object)
            $copilotTargets | Should -Be @('squad-watch.yml:interpret', 'tier1-behavior.yml:live', 'tier2-semantic.yml:compare')
            foreach ($cjob in @($data.copilotJobs)) {
                $cjob.envName | Should -BeExactly 'copilot-headless' -Because "$($cjob.workflow)/$($cjob.job) must bind to copilot-headless"
                $cjob.deployment | Should -BeFalse -Because "$($cjob.workflow)/$($cjob.job) must set deployment: false"
            }
            $watchJob = @($data.copilotJobs | Where-Object { $_.workflow -eq 'squad-watch.yml' })[0]
            $watchJob.ifExpr | Should -Match "vars\.SQUAD_WATCH_ENABLED == 'true'"
            $watchJob.ifExpr | Should -Match "github\.event\.pull_request\.head\.repo\.full_name == github\.repository"
        }

        It 'eliminates direct-to-main automation pushes and enforces same-repo PR scope guards in pr-validation.yml' {
            $script:SyncWorkflow | Should -Match 'chore/sync-hve-core'
            $script:SyncWorkflow | Should -Match 'gh pr create'
            $script:SyncWorkflow | Should -Not -Match 'git push origin main'

            $script:ReleasePrepWorkflow | Should -Match 'chore/release-prep'
            $script:ReleasePrepWorkflow | Should -Match 'gh pr create'
            $script:ReleasePrepWorkflow | Should -Not -Match 'git push origin "HEAD:\$\{REF\}"'
            $script:ReleaseWorkflow | Should -Match 'Run Release Prep first so the version bump lands on main through a reviewed pull request'

            $script:PrValidationRaw | Should -Match '- name: Validate Release Prep pull request scope'
            $script:PrValidationRaw | Should -Match '- name: Validate Sync and Adapt pull request scope'
            $pinStep = Get-WorkflowStepBlock -Body $script:PrValidationRaw -Name 'Reject an unreviewed hve-core pin move'
            $pinStep | Should -Match 'github\.event\.pull_request\.head\.repo\.full_name == github\.repository'
            $pinStep | Should -Match "github\.head_ref == 'chore/sync-hve-core'"
        }

        It 'apm.yml sets Microsoft package authorship' {
            $apm = Get-Content -LiteralPath (Join-Path $script:SourceRootCi08 'apm.yml') -Raw
            $apm | Should -Match '(?m)^author:\s*Microsoft\s*$'
        }
    }
}
