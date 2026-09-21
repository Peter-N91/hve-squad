#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$SourceRoot
)

BeforeAll {
    $script:BuildScript = Join-Path $SourceRoot 'scripts/Build-SquadPlugin.ps1'
    $script:OutputRoot = Join-Path $TestDrive 'plugin-output'
    $script:HookScriptNames = @(
        'autonomous-escalation-check'
        'dispatch-guards'
        'impactful-action-gate'
        'notification-audit'
        'prompt-injection-note'
        'session-start-check'
        'state-write-guard'
    )

    $hookScriptRoot = Join-Path $script:OutputRoot 'hooks/scripts'
    New-Item -ItemType Directory -Path $hookScriptRoot -Force | Out-Null
    foreach ($name in $script:HookScriptNames) {
        foreach ($extension in @('ps1', 'sh')) {
            $content = if ($name -eq 'session-start-check' -and $extension -eq 'ps1') {
                'Set-Content -LiteralPath $env:HOOK_SENTINEL -Value powershell -Encoding UTF8'
            }
            elseif ($name -eq 'session-start-check' -and $extension -eq 'sh') {
                '#!/usr/bin/env bash' + "`n" + 'printf bash > "$HOOK_SENTINEL"'
            }
            else {
                ''
            }
            Set-Content -LiteralPath (Join-Path $hookScriptRoot "$name.$extension") -Value $content -Encoding utf8NoBOM
        }
    }

    $pwsh = (Get-Process -Id $PID).Path
    $script:BuildOutput = @(
        & $pwsh -NoProfile -File $script:BuildScript `
            -SourceRoot $SourceRoot `
            -OutputRoot $script:OutputRoot `
            -McpVersion '0.0.0-test' 2>&1
    )
    $script:BuildExitCode = $LASTEXITCODE

    $script:RootManifestPath = Join-Path $script:OutputRoot 'plugin.json'
    $script:NestedManifestPath = Join-Path $script:OutputRoot '.github/plugin/plugin.json'
    $script:HookManifestPath = Join-Path $script:OutputRoot 'hooks.json'
    . $script:BuildScript
}

Describe 'PKG-14 Plugin host discovery and hook commands' -Tag 'Unit' {
    It 'builds the plugin distribution successfully' {
        $script:BuildExitCode | Should -Be 0 -Because ($script:BuildOutput -join "`n")
    }

    It 'emits byte-identical root and GitHub plugin manifests' {
        Test-Path -LiteralPath $script:RootManifestPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:NestedManifestPath -PathType Leaf | Should -BeTrue
        Get-Content -LiteralPath $script:RootManifestPath -Raw |
            Should -BeExactly (Get-Content -LiteralPath $script:NestedManifestPath -Raw)
    }

    It 'qualifies every hook command with the installed plugin root' {
        $manifest = Get-Content -LiteralPath $script:HookManifestPath -Raw | ConvertFrom-Json
        $entries = @(
            foreach ($eventProperty in $manifest.hooks.PSObject.Properties) {
                $eventProperty.Value
            }
        )

        $entries | Should -HaveCount $script:HookScriptNames.Count
        foreach ($entry in $entries) {
            $entry.bash | Should -Match '^bash "\$\{CLAUDE_PLUGIN_ROOT\}/hooks/scripts/[a-z-]+\.sh"$'
            $entry.powershell | Should -Match '^powershell\.exe -NoProfile -ExecutionPolicy Bypass -File "\$env:CLAUDE_PLUGIN_ROOT/hooks/scripts/[a-z-]+\.ps1"$'
        }
    }

    It 'resolves a SourceRoot build without a git repository or tags' {
        $taglessSource = Join-Path $TestDrive 'tagless-source'
        New-Item -ItemType Directory -Path (Join-Path $taglessSource 'squad-src/.github') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $taglessSource 'apm.yml') -Value "name: fixture`nversion: 9.8.7`n" -Encoding utf8NoBOM

        $source = Resolve-BuildSource -RepoRoot $taglessSource `
            -RefSpecified $false -Ref $null `
            -SourceRootSpecified $true -SourceRoot $taglessSource

        $source.PluginVersion | Should -BeExactly '9.8.7+local'
    }

    It 'executes a generated Bash hook from outside the plugin directory' -Skip:($IsWindows -or -not (Get-Command bash -ErrorAction SilentlyContinue)) {
        $manifest = Get-Content -LiteralPath $script:HookManifestPath -Raw | ConvertFrom-Json
        $foreignWorkingDirectory = Join-Path $TestDrive 'consumer-repository'
        $sentinelPath = Join-Path $TestDrive 'bash-hook-ran'
        New-Item -ItemType Directory -Path $foreignWorkingDirectory -Force | Out-Null
        $previousPluginRoot = $env:CLAUDE_PLUGIN_ROOT
        $previousSentinel = $env:HOOK_SENTINEL

        try {
            $env:CLAUDE_PLUGIN_ROOT = $script:OutputRoot
            $env:HOOK_SENTINEL = $sentinelPath
            Push-Location $foreignWorkingDirectory
            & bash -c $manifest.hooks.sessionStart[0].bash
            $LASTEXITCODE | Should -Be 0
            Get-Content -LiteralPath $sentinelPath -Raw | Should -BeExactly 'bash'
        }
        finally {
            Pop-Location
            $env:CLAUDE_PLUGIN_ROOT = $previousPluginRoot
            $env:HOOK_SENTINEL = $previousSentinel
        }
    }

    It 'executes a PowerShell hook from outside the plugin directory' -Skip:(-not $IsWindows) {
        $manifest = Get-Content -LiteralPath $script:HookManifestPath -Raw | ConvertFrom-Json
        $foreignWorkingDirectory = Join-Path $TestDrive 'consumer-repository'
        $sentinelPath = Join-Path $TestDrive 'powershell-hook-ran'
        New-Item -ItemType Directory -Path $foreignWorkingDirectory -Force | Out-Null
        $previousPluginRoot = $env:CLAUDE_PLUGIN_ROOT
        $previousSentinel = $env:HOOK_SENTINEL

        try {
            $env:CLAUDE_PLUGIN_ROOT = $script:OutputRoot
            $env:HOOK_SENTINEL = $sentinelPath
            Push-Location $foreignWorkingDirectory
            & ([scriptblock]::Create($manifest.hooks.sessionStart[0].powershell))
            $LASTEXITCODE | Should -Be 0
            (Get-Content -LiteralPath $sentinelPath -Raw).Trim() | Should -BeExactly 'powershell'
        }
        finally {
            Pop-Location
            $env:CLAUDE_PLUGIN_ROOT = $previousPluginRoot
            $env:HOOK_SENTINEL = $previousSentinel
        }
    }

    It 'fails before publishing when a referenced hook script is absent' {
        Remove-Item -LiteralPath (Join-Path $script:OutputRoot 'hooks/scripts/session-start-check.ps1')

        { Write-PluginHookManifest -OutputRoot $script:OutputRoot } |
            Should -Throw '*Plugin hook scripts are missing from OutputRoot*session-start-check.ps1*'
    }

    It 'supports a dry run against an empty output root' {
        $dryRunRoot = Join-Path $TestDrive 'empty-dry-run-output'
        New-Item -ItemType Directory -Path $dryRunRoot -Force | Out-Null
        $script:OutputRootResolved = $dryRunRoot
        $script:GeneratedPaths = [System.Collections.Generic.List[string]]::new()

        { Write-PluginHookManifest -OutputRoot $dryRunRoot -DryRun } | Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $dryRunRoot 'hooks.json') | Should -BeFalse
    }
}