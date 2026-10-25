# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

<#
.SYNOPSIS
Compares a pull request's benchmark score with its base branch's score. Never fails.

.DESCRIPTION
Reads the two score.json files (either may be missing or unreadable), writes the pull
request comment to -CommentPath, appends it to the job summary, and prints a warning
annotation for each lower score or failed run. The script always exits 0: a problem
with the comparison becomes a "comparison unavailable" comment, not a failed check.
It has no #Requires line on purpose, so nothing can fail before it starts.
#>

[CmdletBinding()]
param(
    [string]$BasePath,
    [string]$HeadPath,
    [string]$CommentPath = (Join-Path (Get-Location) 'benchmark-comment.md'),
    [switch]$SquadSourceChanged
)

$ErrorActionPreference = 'Stop'

function Read-OptionalScore {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @{ Score = $null; Problem = 'missing' } }
    try { @{ Score = Read-BenchmarkScore -Path $Path; Problem = '' } }
    catch { @{ Score = $null; Problem = 'unreadable' } }
}

function Write-Annotation {
    param([string]$Message)
    $escaped = $Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    Write-Host "::warning title=Benchmark score::$escaped"
}

$comment = $null
try {
    Import-Module (Join-Path $PSScriptRoot 'BenchmarkScore.psm1') -Force
    $base = Read-OptionalScore $BasePath
    $head = Read-OptionalScore $HeadPath
    $unchanged = $null -ne $base.Score -and $null -ne $head.Score -and (Get-FileHash -LiteralPath $BasePath).Hash -eq (Get-FileHash -LiteralPath $HeadPath).Hash
    $result = Compare-BenchmarkScore -Base $base.Score -Head $head.Score -BaseProblem $base.Problem -HeadProblem $head.Problem -Unchanged:$unchanged -SquadSourceChanged:$SquadSourceChanged
    $comment = $result.Markdown
    foreach ($warning in $result.Warnings) { Write-Annotation $warning }
}
catch {
    $comment = "<!-- squad-benchmark-score -->`n### Benchmark score`n`nThe benchmark comparison is unavailable for this pull request. This never fails the pull request.`n"
    Write-Annotation 'The benchmark comparison is unavailable.'
}

try {
    [IO.File]::WriteAllText($CommentPath, $comment, [Text.UTF8Encoding]::new($false))
    if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $comment }
}
catch {
    Write-Annotation 'The benchmark comment could not be written.'
}
exit 0
