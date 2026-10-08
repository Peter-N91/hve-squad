#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Hot-file byte diff against v0.18.1. Every default (off, ranked, manual) run reads
# these files, so economy procedure must live in the cold references/economy-mode.md
# and each hot file may grow by at most a one-line pointer. Sizes are LF-normalized
# UTF-8 bytes, so a CRLF checkout measures the same as the committed blob. A change
# that applies in every routing mode (never an economy-only one) may carry an
# approved everyMode allowance with its reason in the baseline.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Read inside Pester BeforeDiscovery and BeforeAll blocks, which PSScriptAnalyzer treats as scopes unrelated to the param block.')]
param(
    [Parameter(Mandatory)]
    [string]$SourceRoot
)

BeforeDiscovery {
    $baseline = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'baselines/hot-file-v0.18.1.json') -Raw | ConvertFrom-Json
    $script:HotFiles = @($baseline.files.PSObject.Properties | ForEach-Object { @{ Path = $_.Name; Baseline = [int]$_.Value } })
}

BeforeAll {
    $script:Root = (Resolve-Path -LiteralPath $SourceRoot).Path
    $script:Budget = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'baselines/hot-file-v0.18.1.json') -Raw | ConvertFrom-Json

    function Get-NormalizedByteCount {
        param([Parameter(Mandatory)][string]$Path)
        $text = [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
        return [System.Text.Encoding]::UTF8.GetByteCount($text)
    }

    function Get-EveryModeAllowance {
        param([Parameter(Mandatory)][string]$Path)
        if (-not $script:Budget.PSObject.Properties['everyMode']) { return 0 }
        $entry = $script:Budget.everyMode.PSObject.Properties[$Path]
        if (-not $entry) { return 0 }
        return [int]$entry.Value.bytes
    }
}

Describe 'Hot files stay within a one-line pointer of v0.18.1' {
    It '<Path> grows by at most the per-file threshold' -ForEach $script:HotFiles {
        $size = Get-NormalizedByteCount -Path (Join-Path $script:Root $Path)
        $limit = $script:Budget.perFileThreshold + (Get-EveryModeAllowance -Path $Path)
        ($size - $Baseline) | Should -BeLessOrEqual $limit -Because "$Path is read on every default run: $size bytes against $Baseline at $($script:Budget.ref); move economy text to references/economy-mode.md"
    }

    It 'the hot set grows by at most the total threshold, every-mode allowances aside' {
        $delta = 0
        foreach ($property in $script:Budget.files.PSObject.Properties) {
            $grown = (Get-NormalizedByteCount -Path (Join-Path $script:Root $property.Name)) - [int]$property.Value
            $covered = [Math]::Min((Get-EveryModeAllowance -Path $property.Name), [Math]::Max($grown, 0))
            $delta += $grown - $covered
        }
        $delta | Should -BeLessOrEqual $script:Budget.totalThreshold -Because "the hot set grew $delta bytes against $($script:Budget.ref)"
    }

    It 'measures every listed file, including every file a ranked or manual run reads' {
        @($script:Budget.files.PSObject.Properties).Count | Should -BeGreaterOrEqual 22
        foreach ($required in @(
                'squad-src/.github/skills/squad/references/model-routing.md'
                'squad-src/.github/instructions/squad/squad-roster.instructions.md'
                'squad-src/.github/skills/squad/SKILL.md'
                'squad-src/.github/prompts/squad/squad.prompt.md'
                'squad-src/.github/agents/squad/squad-federation-coordinator.agent.md'
                'squad-src/.github/prompts/squad/squad-federation.prompt.md'
                'squad-src/.github/instructions/squad/squad-intake-gate.instructions.md'
                'squad-src/.github/instructions/squad/squad-autopilot.instructions.md'
                'squad-src/.github/instructions/squad/squad-watch-mode.instructions.md'
                'squad-src/.github/skills/squad/references/consumption.md'
                'squad-src/.github/skills/squad/references/seed-templates.md'
                'squad-src/.github/skills/squad/references/consumption-rates-template.md'
            )) {
            $script:Budget.files.PSObject.Properties.Name | Should -Contain $required
        }
        foreach ($property in $script:Budget.files.PSObject.Properties) {
            Test-Path -LiteralPath (Join-Path $script:Root $property.Name) -PathType Leaf | Should -BeTrue -Because "$($property.Name) is in the hot-file baseline"
        }
    }

    It 'keeps the total threshold at or below 2048 bytes and names a reason for every every-mode allowance' {
        $script:Budget.totalThreshold | Should -BeLessOrEqual 2048
        if ($script:Budget.PSObject.Properties['everyMode']) {
            foreach ($entry in $script:Budget.everyMode.PSObject.Properties) {
                $script:Budget.files.PSObject.Properties.Name | Should -Contain $entry.Name
                $entry.Value.reason | Should -Not -BeNullOrEmpty
                $entry.Value.reason | Should -Not -Match '(?i)economy-only'
            }
        }
    }
}
