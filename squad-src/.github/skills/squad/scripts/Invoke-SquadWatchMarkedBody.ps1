# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

<#
.SYNOPSIS
    Renders validated Watch Open Questions into a pull request body, source-thread comment, or run summary.
.DESCRIPTION
    Imports the trusted module before any helper call. Question text comes from committed
    watch-publication.json, or from a downloaded copy of that same file for a no-commit comment.
    The script never interpolates question text into a shell command.
#>
#Requires -Version 7.4
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$trustedRoot = [System.IO.Path]::GetFullPath($env:SQUAD_WATCH_TRUSTED_ROOT)
$pinnedSha = [string]$env:SQUAD_WATCH_TRUSTED_SHA
if (-not [string]::IsNullOrWhiteSpace($pinnedSha)) {
    $assertScript = Join-Path $trustedRoot 'squad-src/.github/skills/squad/scripts/Assert-SquadWatchTrustedCheckout.ps1'
    & $assertScript -TrustedRoot $trustedRoot -ExpectedSha $pinnedSha
}
$modulePath = Join-Path $trustedRoot 'squad-src/.github/skills/squad/scripts/SquadWatch.psm1'
Import-Module $modulePath -Force
Assert-SquadWatchTrustedHelper -TrustedRoot $trustedRoot -Path $modulePath | Out-Null

$mode = if ($env:SQUAD_WATCH_MODE) { $env:SQUAD_WATCH_MODE } else { 'pr' }
if ($mode -eq 'review') {
    $reviewPath = [string]$env:SQUAD_WATCH_REVIEW
    $raw = if ($reviewPath -and (Test-Path -LiteralPath $reviewPath)) { Get-Content -LiteralPath $reviewPath -Raw } else { '' }
    $encoded = ConvertTo-SquadWatchInertReview -Text $raw
    $out = if ($env:SQUAD_WATCH_BODY_OUT) { $env:SQUAD_WATCH_BODY_OUT } else { Join-Path $env:RUNNER_TEMP 'squad-review-encoded.md' }
    Set-Content -LiteralPath $out -Value ($encoded + "`n") -Encoding utf8NoBOM
    return
}
$member = [string]$env:SQUAD_WATCH_MEMBER
$workspace = if ($env:SQUAD_WATCH_WORKSPACE) { $env:SQUAD_WATCH_WORKSPACE } else { (Get-Location).Path }
$rendered = $null

if ($mode -eq 'pr') {
    $catalog = ''
    if (-not [string]::IsNullOrWhiteSpace($pinnedSha)) {
        $catalogLines = @(& git -C $trustedRoot show "${pinnedSha}:squad-src/.github/skills/squad/references/profiles-and-packs.md" 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw 'Pinned profile catalog is missing. Publication evidence cannot be recomputed.'
        }
        $catalog = $catalogLines -join "`n"
    }
    $rendered = Get-SquadWatchCommittedQuestionsMarkdown -Repository $workspace -Member $member -CatalogMarkdown $catalog -ExpectedRunId $env:SQUAD_WATCH_RUN_ID -ExpectedThread $env:SQUAD_WATCH_THREAD -ExpectedStableRef $env:SQUAD_WATCH_STABLE_REF -ExpectedTrustedBaseSha $pinnedSha
}
else {
    $evidence = [string]$env:SQUAD_WATCH_EVIDENCE
    $catalog = ''
    if (-not [string]::IsNullOrWhiteSpace($pinnedSha)) {
        $catalogLines = @(& git -C $trustedRoot show "${pinnedSha}:squad-src/.github/skills/squad/references/profiles-and-packs.md" 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw 'Pinned profile catalog is missing. Publication evidence cannot be recomputed.'
        }
        $catalog = $catalogLines -join "`n"
    }
    $decisionsPath = Join-Path $workspace ".copilot-tracking/squad/members/$member/decisions.md"
    $teamPath = Join-Path $workspace ".copilot-tracking/squad/members/$member/team.md"
    $hasCommitted = (Test-Path -LiteralPath $decisionsPath) -and (Test-Path -LiteralPath $teamPath)
    if ($mode -eq 'comment' -or -not $hasCommitted) {
        if (-not $evidence -or -not (Test-Path -LiteralPath $evidence -PathType Leaf)) {
            $rendered = 'Watch Mode validation failed. The run log has the details. No untrusted cells were published.'
        }
        else {
            $rendered = Get-SquadWatchStagedQuestionsMarkdown -EvidencePath $evidence -CatalogMarkdown $catalog -ExpectedMember $member -ExpectedRunId $env:SQUAD_WATCH_RUN_ID -ExpectedThread $env:SQUAD_WATCH_THREAD -ExpectedStableRef $env:SQUAD_WATCH_STABLE_REF -ExpectedTrustedBaseSha $pinnedSha
        }
    }
    else {
        $committedDecisions = Get-Content -LiteralPath $decisionsPath -Raw
        $committedTeam = Get-Content -LiteralPath $teamPath -Raw
        $rendered = Get-SquadWatchEvidenceQuestionsMarkdown -EvidencePath $evidence -CatalogMarkdown $catalog -ExpectedMember $member -ExpectedRunId $env:SQUAD_WATCH_RUN_ID -ExpectedThread $env:SQUAD_WATCH_THREAD -ExpectedStableRef $env:SQUAD_WATCH_STABLE_REF -ExpectedTrustedBaseSha $pinnedSha -CommittedDecisions $committedDecisions -CommittedTeam $committedTeam
    }
}

if ($mode -eq 'summary') {
    $summary = @(
        '### Watch Mode'
        ''
        'Watch Mode recorded no material publication. This free-form workflow_dispatch has no numeric source thread, so no issue comment was attempted.'
        ''
        $rendered
        ''
        "Run log: $($env:SQUAD_WATCH_RUN_URL)"
    ) -join "`n"
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary -Encoding utf8
    return
}

$prefix = if ($mode -eq 'comment') {
    "Watch Mode recorded no material publication.`n`n"
}
else {
    ''
}
$interior = ($prefix + $rendered).Trim()

if ($mode -eq 'comment' -and -not $env:SQUAD_WATCH_BODY_IN) {
    $commentPath = if ($env:SQUAD_WATCH_BODY_OUT) { $env:SQUAD_WATCH_BODY_OUT } else { Join-Path $env:RUNNER_TEMP 'squad-watch-comment.md' }
    Set-Content -LiteralPath $commentPath -Value ($interior + "`n") -Encoding utf8NoBOM
    return
}

$before = ''
if ($env:SQUAD_WATCH_BODY_IN -and (Test-Path -LiteralPath $env:SQUAD_WATCH_BODY_IN)) {
    $before = Get-Content -LiteralPath $env:SQUAD_WATCH_BODY_IN -Raw
}
$marked = Update-SquadWatchMarkedBody -Body $before -Interior $interior
if ($marked.Ambiguous) {
    throw 'Ambiguous Open Questions markers; body left unchanged.'
}
# Marker contract: <!-- squad-watch-open-questions:start --> ... <!-- squad-watch-open-questions:end -->
Set-Content -LiteralPath $env:SQUAD_WATCH_BODY_OUT -Value $marked.Body -Encoding utf8NoBOM
