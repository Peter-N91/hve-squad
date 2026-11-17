#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$SourceRoot
)

BeforeAll {
    $script:SourceRootResolved = (Resolve-Path -LiteralPath $SourceRoot).Path
    $script:StudioRoot = Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/extensions/hve-squad-studio'
    $script:InstallerScript = Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/scripts/Install-SquadStudioExtension.ps1'
    $script:NodeTestPath = Join-Path $PSScriptRoot 'squad-studio/studio.test.mjs'
    $script:PwshExe = (Get-Process -Id $PID).Path
}

Describe 'STUDIO-01 HVE Squad Studio canvas package, branding, and bootstrap' {
    It 'ships required canvas files and manifest under the squad skill' {
        foreach ($rel in @(
                'copilot-extension.json'
                'extension.mjs'
                'README.md'
                'lib/catalog.mjs'
                'lib/scenarios.mjs'
                'lib/server.mjs'
                'lib/session-bridge.mjs'
                'lib/squad-initializer.mjs'
                'lib/state-reader.mjs'
                'lib/store.mjs'
                'ui/index.html'
                'ui/styles.css'
                'ui/app.mjs'
            )) {
            Test-Path -LiteralPath (Join-Path $script:StudioRoot $rel) -PathType Leaf |
                Should -BeTrue -Because "missing HVE Squad Studio file: $rel"
        }

        $extManifest = Get-Content -LiteralPath (Join-Path $script:StudioRoot 'copilot-extension.json') -Raw | ConvertFrom-Json
        $extManifest.name | Should -BeExactly 'hve-squad-studio'
        $extManifest.version | Should -Be 1
    }

    It 'uses HVE Squad product branding across UI chrome and avoids bare Squad Studio naming' {
        $html = Get-Content -LiteralPath (Join-Path $script:StudioRoot 'ui/index.html') -Raw
        $entry = Get-Content -LiteralPath (Join-Path $script:StudioRoot 'extension.mjs') -Raw
        $html | Should -Match 'HVE Squad Studio'
        $html | Should -Match 'Start with HVE Squad'
        $html | Should -Match 'Your Chosen Squad'
        $entry | Should -Match "displayName:\s*'HVE Squad Studio'"
        $html | Should -Not -Match '(?<!HVE )Squad Studio'
    }

    It 'materializes repository and user extension copies and detects drift with -Check' {
        $consumerRepo = Join-Path $TestDrive 'consumer-repo'
        $userHome = Join-Path $TestDrive 'copilot-home'
        New-Item -ItemType Directory -Path $consumerRepo, $userHome -Force | Out-Null

        $repoInstallRaw = & $script:PwshExe -NoProfile -File $script:InstallerScript -Scope repository -RepoRoot $consumerRepo 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $repoInstallRaw
        $repoInstall = $repoInstallRaw | ConvertFrom-Json
        $repoInstall.status | Should -BeExactly 'installed'
        Test-Path -LiteralPath (Join-Path $consumerRepo '.github/extensions/hve-squad-studio/extension.mjs') -PathType Leaf |
            Should -BeTrue

        $checkCleanRaw = & $script:PwshExe -NoProfile -File $script:InstallerScript -Scope repository -RepoRoot $consumerRepo -Check 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $checkCleanRaw
        ($checkCleanRaw | ConvertFrom-Json).status | Should -BeExactly 'up-to-date'

        Add-Content -LiteralPath (Join-Path $consumerRepo '.github/extensions/hve-squad-studio/README.md') -Value "`ndrift"
        $checkDriftRaw = & $script:PwshExe -NoProfile -File $script:InstallerScript -Scope repository -RepoRoot $consumerRepo -Check 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 2 -Because $checkDriftRaw
        ($checkDriftRaw | ConvertFrom-Json).status | Should -BeExactly 'drift-detected'

        $userInstallRaw = & $script:PwshExe -NoProfile -File $script:InstallerScript -Scope user -CopilotHome $userHome 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $userInstallRaw
        Test-Path -LiteralPath (Join-Path $userHome 'extensions/hve-squad-studio/extension.mjs') -PathType Leaf |
            Should -BeTrue
    }

    It 'passes the Node unit and loopback server test suite' {
        $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
        if (-not $nodeCmd) {
            Set-ItResult -Skipped -Because 'Node.js is not installed on this runner'
            return
        }
        $out = & $nodeCmd.Source --test $script:NodeTestPath 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $out
    }
}
