#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Legacy file byte diff against v0.18.1, plus the measured universal ordinary path.
# Full legacy Scribe procedure is now cold, not a required default-mode read. The aggregate
# ceiling remains fixed while documented per-file overrides permit concentrated
# growth within it. Pull requests inherit existing base debt but may not increase
# it. Sizes are LF-normalized UTF-8 bytes, so checkout line endings do not matter.

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
    $script:Tier0Workflow = Get-Content -LiteralPath (Join-Path $script:Root '.github/workflows/tier0-conformance.yml') -Raw

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

    function Get-PerFileThreshold {
        param([Parameter(Mandatory)][string]$Path)
        # Redistribute existing aggregate headroom for universal contract pointers;
        # this does not increase the aggregate ceiling or exclude their bytes.
        if ($Path -in @(
                'squad-src/.github/agents/squad/squad-coordinator.agent.md'
                'squad-src/.github/agents/squad/squad-federation-coordinator.agent.md'
                'squad-src/.github/instructions/squad/squad-state.instructions.md'
                'squad-src/.github/skills/squad/SKILL.md'
                'squad-src/.github/skills/squad/references/operating-procedure.md'
                'squad-src/.github/skills/squad/references/gates-and-modes.md'
            )) { return 1024 }
        if ($script:Budget.PSObject.Properties['perFileThresholdOverrides']) {
            $entry = $script:Budget.perFileThresholdOverrides.PSObject.Properties[$Path]
            if ($entry) { return [int]$entry.Value.bytes }
        }
        return [int]$script:Budget.perFileThreshold
    }

    function Get-GitBlobNormalizedByteCount {
        param(
            [Parameter(Mandatory)][string]$Ref,
            [Parameter(Mandatory)][string]$Path
        )

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'git'
        $startInfo.WorkingDirectory = $script:Root
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.ArgumentList.Add('show')
        $startInfo.ArgumentList.Add("${Ref}:$Path")

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            $null = $process.Start()
            $text = $process.StandardOutput.ReadToEnd()
            $errorText = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) {
                throw "Cannot read $Path at base $Ref`: $errorText"
            }
            $text = $text -replace "`r`n", "`n"
            return [System.Text.Encoding]::UTF8.GetByteCount($text)
        }
        finally {
            $process.Dispose()
        }
    }

    function Get-EffectivePerFileThreshold {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][int]$Baseline
        )

        $limit = Get-PerFileThreshold -Path $Path
        if ($env:TIER0_BASE_SHA) {
            $baseDelta = (Get-GitBlobNormalizedByteCount -Ref $env:TIER0_BASE_SHA -Path $Path) - $Baseline
            $limit = [Math]::Max($limit, $baseDelta)
        }
        return $limit
    }
}

Describe 'Legacy surface budgets and universal ordinary hot-path envelope' {
    It 'measures the ordinary agent plus its sole mandatory reference in every routing mode' {
        $agent = 'squad-src/.github/agents/squad/squad-scribe.agent.md'
        $reference = 'squad-src/.github/skills/squad/references/economy-scribe.md'
        $agentBytes = Get-NormalizedByteCount -Path (Join-Path $script:Root $agent)
        $contractBytes = Get-NormalizedByteCount -Path (Join-Path $script:Root $reference)
        $agentBytes | Should -BeLessThan 3000
        $contractBytes | Should -BeLessOrEqual 3072
        ($agentBytes + $contractBytes) | Should -BeLessOrEqual 6144
        $body = Get-Content -LiteralPath (Join-Path $script:Root $agent) -Raw
        $ordinary = [regex]::Match($body, '(?s)## Ordinary handoff.*?(?=## Cold operations)').Value
        $ordinary | Should -Match 'Read only `references/economy-scribe\.md`'
        $ordinary | Should -Not -Match 'Read.*references/(scribe-procedure|entry-schemas|scribe-payload-template|00-index)\.md'
    }

    It '<Path> grows by at most the per-file threshold' -ForEach $script:HotFiles {
        $size = Get-NormalizedByteCount -Path (Join-Path $script:Root $Path)
        $limit = (Get-EffectivePerFileThreshold -Path $Path -Baseline $Baseline) + (Get-EveryModeAllowance -Path $Path)
        ($size - $Baseline) | Should -BeLessOrEqual $limit -Because "$Path remains in the legacy surface budget: $size bytes against $Baseline at $($script:Budget.ref); keep ordinary writes in the measured small contract and cold details conditional"
    }

    It 'the hot set grows by at most the total threshold, every-mode allowances aside' {
        $delta = 0
        $baseDelta = 0
        foreach ($property in $script:Budget.files.PSObject.Properties) {
            $grown = (Get-NormalizedByteCount -Path (Join-Path $script:Root $property.Name)) - [int]$property.Value
            $covered = [Math]::Min((Get-EveryModeAllowance -Path $property.Name), [Math]::Max($grown, 0))
            $delta += $grown - $covered
            if ($env:TIER0_BASE_SHA) {
                $baseGrown = (Get-GitBlobNormalizedByteCount -Ref $env:TIER0_BASE_SHA -Path $property.Name) - [int]$property.Value
                $baseCovered = [Math]::Min((Get-EveryModeAllowance -Path $property.Name), [Math]::Max($baseGrown, 0))
                $baseDelta += $baseGrown - $baseCovered
            }
        }
        $limit = [Math]::Max([int]$script:Budget.totalThreshold, $baseDelta)
        $delta | Should -BeLessOrEqual $limit -Because "the hot set grew $delta bytes against $($script:Budget.ref); the absolute ceiling is $($script:Budget.totalThreshold) and the pull request base uses $baseDelta bytes"
    }

    It 'measures the common-path progress contract instead of hiding it in an unmeasured reference' {
        $path = 'squad-src/.github/skills/squad/references/operating-procedure.md'
        $script:Budget.files.PSObject.Properties.Name | Should -Contain $path
        $procedure = Get-Content -LiteralPath (Join-Path $script:Root $path) -Raw
        $procedure | Should -Match '(?m)^### Progress Presentation\r?$'
        $procedure | Should -Not -Match 'references/progress\.md|\[progress\.md\]'
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
        if ($script:Budget.PSObject.Properties['perFileThresholdOverrides']) {
            foreach ($entry in $script:Budget.perFileThresholdOverrides.PSObject.Properties) {
                $script:Budget.files.PSObject.Properties.Name | Should -Contain $entry.Name
                $entry.Value.bytes | Should -BeGreaterOrEqual $script:Budget.perFileThreshold
                $entry.Value.bytes | Should -BeLessOrEqual $script:Budget.totalThreshold
                $entry.Value.reason | Should -Not -BeNullOrEmpty
            }
        }
        if ($script:Budget.PSObject.Properties['everyMode']) {
            foreach ($entry in $script:Budget.everyMode.PSObject.Properties) {
                $script:Budget.files.PSObject.Properties.Name | Should -Contain $entry.Name
                $entry.Value.reason | Should -Not -BeNullOrEmpty
                $entry.Value.reason | Should -Not -Match '(?i)economy-only'
            }
        }
    }

    It 'keeps the pull request merge parent available to the budget ratchet' {
        $fetchDepth = [regex]::Match($script:Tier0Workflow, '(?m)^\s+fetch-depth:\s*(\d+)\s*$')
        $fetchDepth.Success | Should -BeTrue
        ([int]$fetchDepth.Groups[1].Value -eq 0 -or [int]$fetchDepth.Groups[1].Value -ge 2) | Should -BeTrue -Because 'HEAD^1 must exist in the checkout'
    }

    It 'ratchets against the checked-out merge parent instead of a stale event base' {
        $expectedBase = "TIER0_BASE_SHA: `${{ github.event_name == 'pull_request' && 'HEAD^1' || '' }}"
        $script:Tier0Workflow | Should -Match ([regex]::Escape($expectedBase))
        $script:Tier0Workflow | Should -Not -Match 'github\.event\.pull_request\.base\.sha'
    }
}
