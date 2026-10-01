#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# P04-T01 (routing-performance plan, Amendment 3 §5, Unit U5): integrity assertions for
# the 'autopilot-pipelining' Tier 1 scenario. These hold whether or not the coordinator
# actually overlapped any hand-off with the next stage's dispatch -- this file proves
# pipelining, when it happens, never corrupts state; it does not itself prove that
# overlap occurred (that is the paired benchmark driver's job, using independent
# transcript/tool-call timestamps, per Amendment 2 §11).
#
# Every stage artifact's own write is gated on the PRECEDING stage's artifact already
# being on disk -- pipelining only ever overlaps stage N's Scribe hand-off with stage
# N+1's ROLE dispatch, never stage N's own artifact write with stage N+1's (see
# 'Scribe Hand-off Pipelining (Autopilot)' in references/operating-procedure.md: "once
# stage N's own artifact is confirmed on disk, the coordinator may..."). That is what
# makes artifact mtimes a sound, pipelining-agnostic proxy for stage order here.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'WorkspaceRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as unrelated scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SquadRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as unrelated scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Stages',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as unrelated scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'BarrierAfterStage',
    Justification = 'Read inside a Describe/It scriptblock, which PSScriptAnalyzer treats as unrelated scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ScribeAgentFile',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as unrelated scope.')]
param(
    # Provisioned workspace root (a scenario's install.Root), so stage artifact paths
    # (recorded project-root-relative in the scenario JSON) resolve against the same
    # root a live run wrote them under.
    [Parameter(Mandatory)]
    [string]$WorkspaceRoot,

    # The squad root the scenario's turns seeded (one entry of $squadRoots in
    # Invoke-Tier1LiveRun.ps1), so history/*.md is read from the same tree the state
    # contract already asserts on.
    [Parameter(Mandatory)]
    [string]$SquadRoot,

    # Ordered array of { id, artifact } from the scenario JSON's own
    # 'pipeliningIntegrity.stages' block -- the scenario is the one place that knows
    # which stage wrote which fixed path, so this file reads it rather than
    # rediscovering stage identity from prose.
    [Parameter(Mandatory)]
    [object[]]$Stages,

    # Stage id after which a barrier applies (a council verdict consumed by Implement,
    # per the barrier list in references/gates-and-modes.md). Empty means the scenario
    # asserts no barrier.
    [string]$BarrierAfterStage = '',

    # The Scribe's own history file name. 'Squad Scribe.md' matches the roster
    # convention every fixture and shipped template uses; overridable in case a live
    # roster names its Scribe agent differently.
    [string]$ScribeAgentFile = 'Squad Scribe.md'
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadState.psm1') -Force

    $historyDirectory = Join-Path $SquadRoot 'history'
    $script:HistoryFiles = @(
        if (Test-Path -LiteralPath $historyDirectory) {
            Get-ChildItem -LiteralPath $historyDirectory -Filter '*.md' -File
        }
    )

    # Every '* Deliverable:' path any agent's history declares, tail-normalized so a
    # federation rebase (not expected in this scenario, but cheap to tolerate) does not
    # break the match. See Get-DeliverableTail's own remarks.
    $script:DeliverableEntries = @(
        foreach ($file in $script:HistoryFiles) { Get-DeliverableEntry -Path $file.FullName }
    )

    $script:StageInfo = @(
        foreach ($stage in $Stages) {
            $fullPath = Join-Path $WorkspaceRoot $stage.artifact
            $tail = Get-DeliverableTail $stage.artifact
            $matchingEntries = @($script:DeliverableEntries | Where-Object { (Get-DeliverableTail $_.Path) -eq $tail })
            $exists = Test-Path -LiteralPath $fullPath

            [pscustomobject]@{
                Id             = $stage.id
                Artifact       = $stage.artifact
                FullPath       = $fullPath
                Exists         = $exists
                MtimeUtc       = if ($exists) { (Get-Item -LiteralPath $fullPath).LastWriteTimeUtc } else { $null }
                HistoryMatches = $matchingEntries
            }
        }
    )

    $scribeFile = @($script:HistoryFiles | Where-Object { $_.Name -eq $ScribeAgentFile })
    $script:ScribeEntries = if ($scribeFile.Count -gt 0) { @(Get-HistoryEntry -Path $scribeFile[0].FullName) } else { @() }
    $script:ScribeFileCount = $scribeFile.Count
}

Describe 'Every stage artifact has a matching history entry' {
    It 'wrote every declared stage artifact to disk' {
        $missing = @($script:StageInfo | Where-Object { -not $_.Exists } | ForEach-Object { $_.Artifact })
        $missing | Should -BeNullOrEmpty -Because 'a stage that reports complete without its artifact on disk is the exact gap the Per-Stage Advance Checklist exists to catch'
    }

    It 'has at least one agent history entry declaring each stage artifact as a Deliverable' {
        $undeclared = @($script:StageInfo | Where-Object { $_.HistoryMatches.Count -eq 0 } | ForEach-Object { $_.Artifact })
        $undeclared | Should -BeNullOrEmpty -Because 'an artifact on disk with no matching history entry means the stage''s Scribe hand-off was never verified (see the Resume rule)'
    }
}

Describe 'Stage order preserved' {
    It 'wrote every stage''s artifact no earlier than the artifact before it' {
        # Pipelining only ever overlaps a Scribe hand-off with the NEXT stage's role
        # dispatch, never a stage's own artifact write with the one after it, so this
        # inequality holds whether or not the coordinator actually pipelined anything.
        $present = @($script:StageInfo | Where-Object { $_.Exists })
        $outOfOrder = for ($i = 1; $i -lt $present.Count; $i++) {
            if ($present[$i].MtimeUtc -lt $present[$i - 1].MtimeUtc) {
                "$($present[$i - 1].Id) -> $($present[$i].Id)"
            }
        }
        @($outOfOrder) | Should -BeNullOrEmpty -Because 'a stage''s own artifact write is gated on the preceding stage''s artifact already being on disk'
    }
}

Describe 'At most one Scribe hand-off per stage (no merged payloads)' {
    It 'recorded a Scribe history file' {
        $script:ScribeFileCount | Should -BeGreaterThan 0 -Because "no '$ScribeAgentFile' means no stage's hand-off was ever verified"
    }

    It 'recorded at least one Scribe entry per requested stage (a merged hand-off would under-count)' {
        # 'Each stage still gets exactly one Scribe subagent invocation... never merge
        # two stages' Scribe payloads into one hand-off' (operating-procedure.md). A
        # run that merged stages would leave fewer Scribe entries than stages; a run
        # that pipelined correctly still dispatches one hand-off per stage, it just
        # overlaps some of them with the next stage's role dispatch, so the entry
        # count is unaffected by pipelining either way.
        $script:ScribeEntries.Count | Should -BeGreaterOrEqual $Stages.Count
    }
}

Describe 'Pre-barrier writes land before the barrier''s output' {
    It 'lands the barrier stage''s artifact and history entry before any stage after it' {
        if (-not $BarrierAfterStage) {
            Set-ItResult -Skipped -Because 'this scenario declares no barrier'
            return
        }

        $barrierIndex = @(0..($Stages.Count - 1) | Where-Object { $Stages[$_].id -eq $BarrierAfterStage })
        $barrierIndex.Count | Should -BeGreaterThan 0 -Because "BarrierAfterStage '$BarrierAfterStage' must name one of the declared stages"

        $barrierStage = $script:StageInfo[$barrierIndex[0]]
        $barrierStage.Exists | Should -BeTrue -Because 'the barrier stage must itself have landed before anything gated on it can be checked'
        $barrierStage.HistoryMatches.Count | Should -BeGreaterThan 0 -Because 'the barrier is a council verdict CONSUMED by the next stage, which requires the verdict''s own hand-off already verified'

        for ($i = $barrierIndex[0] + 1; $i -lt $script:StageInfo.Count; $i++) {
            $after = $script:StageInfo[$i]
            if (-not $after.Exists) { continue }
            $after.MtimeUtc | Should -BeGreaterOrEqual $barrierStage.MtimeUtc `
                -Because "stage '$($after.Id)' consumes the '$BarrierAfterStage' verdict and must not have started before it landed"
        }
    }
}

Describe 'Measure-SquadLedger -Check -ExpectedHistoryCounts passes on the resulting root' {
    It 'exits 0 for the observed per-agent history entry counts' {
        $ledgerScript = Join-Path $PSScriptRoot '..' '..' 'squad-src' '.github' 'skills' 'squad' 'scripts' 'Measure-SquadLedger.ps1'
        $ledgerScript = (Resolve-Path -LiteralPath $ledgerScript).Path

        # Keyed by agent name (the file's basename, no extension) -- that is what
        # Measure-SquadLedger.ps1 itself keys -ExpectedHistoryCounts by, matching
        # Get-HistoryEntry's own 'Agent' property.
        $expectedCounts = @{}
        foreach ($file in $script:HistoryFiles) {
            $expectedCounts[[System.IO.Path]::GetFileNameWithoutExtension($file.Name)] = @(Get-HistoryEntry -Path $file.FullName).Count
        }

        # The script calls exit 0/1 itself, which would tear down THIS Pester process
        # if invoked in-proc; and pwsh -File stringifies every argument, so a
        # hashtable arrives as the literal text 'System.Collections.Hashtable' and
        # -ExpectedHistoryCounts's argument transform throws before -Check even runs.
        # A -Command string that spells the hashtable out as PowerShell source, parsed
        # fresh in the child process, is what -File cannot do and dot-sourcing here
        # cannot survive.
        $pairs = foreach ($key in $expectedCounts.Keys) {
            "'$($key.Replace("'", "''"))' = $($expectedCounts[$key])"
        }
        $hashLiteral = '@{' + ($pairs -join '; ') + '}'
        $escapedScript = $ledgerScript.Replace("'", "''")
        $escapedRoot = $SquadRoot.Replace("'", "''")
        $command = "& '$escapedScript' -SquadRoot '$escapedRoot' -Check -ExpectedHistoryCounts $hashLiteral"

        & pwsh -NoProfile -Command $command 2>&1 | Out-String | Write-Verbose -Verbose:$false
        $LASTEXITCODE | Should -Be 0 -Because 'a nonzero exit means the ledger''s own bookkeeping disagrees with the on-disk history it just read'
    }
}
