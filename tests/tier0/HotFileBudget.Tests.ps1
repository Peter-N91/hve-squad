#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Hot-file byte diff against v0.18.0. Every default (off, ranked, manual) run reads
# these files, so economy procedure must live in the cold references/economy-mode.md
# and each hot file may grow by at most a one-line pointer. Sizes are LF-normalized
# UTF-8 bytes, so a CRLF checkout measures the same as the committed blob.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Read inside Pester BeforeDiscovery and BeforeAll blocks, which PSScriptAnalyzer treats as scopes unrelated to the param block.')]
param(
    [Parameter(Mandatory)]
    [string]$SourceRoot
)

BeforeDiscovery {
    $baseline = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'baselines/hot-file-v0.18.0.json') -Raw | ConvertFrom-Json
    $script:HotFiles = @($baseline.files.PSObject.Properties | ForEach-Object { @{ Path = $_.Name; Baseline = [int]$_.Value } })
}

BeforeAll {
    $script:Root = (Resolve-Path -LiteralPath $SourceRoot).Path
    $script:Budget = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'baselines/hot-file-v0.18.0.json') -Raw | ConvertFrom-Json

    function Get-NormalizedByteCount {
        param([Parameter(Mandatory)][string]$Path)
        $text = [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
        return [System.Text.Encoding]::UTF8.GetByteCount($text)
    }
}

Describe 'Hot files stay within a one-line pointer of v0.18.0' {
    It '<Path> grows by at most the per-file threshold' -ForEach $script:HotFiles {
        $size = Get-NormalizedByteCount -Path (Join-Path $script:Root $Path)
        ($size - $Baseline) | Should -BeLessOrEqual $script:Budget.perFileThreshold -Because "$Path is read on every default run: $size bytes against $Baseline at $($script:Budget.ref); move economy text to references/economy-mode.md"
    }

    It 'the hot set grows by at most the total threshold' {
        $delta = 0
        foreach ($property in $script:Budget.files.PSObject.Properties) {
            $delta += (Get-NormalizedByteCount -Path (Join-Path $script:Root $property.Name)) - [int]$property.Value
        }
        $delta | Should -BeLessOrEqual $script:Budget.totalThreshold -Because "the hot set grew $delta bytes against $($script:Budget.ref)"
    }

    It 'measures every listed file' {
        @($script:Budget.files.PSObject.Properties).Count | Should -BeGreaterOrEqual 10
        foreach ($property in $script:Budget.files.PSObject.Properties) {
            Test-Path -LiteralPath (Join-Path $script:Root $property.Name) -PathType Leaf | Should -BeTrue -Because "$($property.Name) is in the hot-file baseline"
        }
    }
}
