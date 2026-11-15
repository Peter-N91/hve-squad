#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Renders the squad governance dashboard as one self-contained, deterministic HTML file.
.DESCRIPTION
    AI cost: none; reads local squad state and writes one HTML file, without a model call.

    Reads `.copilot-tracking/squad/` (state.json, decisions.md, history/, consumption.md and its
    siblings, notifications.md) strictly read-only and renders the seven-section dashboard plus the
    full consumption ledger, observed usage, the without-HVE-Squad comparison, ROI, and the evidence
    for why HVE Squad paid off. The consumption ledger is displayed as a document, section by
    section, so a section or column added to the ledger later appears with no change to this script.

    The same state files and the same -AsOf always produce byte-identical output. Nothing is
    estimated or repaired: a figure a ledger does not state is shown as unavailable.

    Prints one JSON receipt on stdout (path, period, one-line summary, grounding, gaps, data-quality
    notes). Exits 1 with a message on stderr when no squad state exists, a sub-squad is unknown, or
    the output path is unsafe; the receipt is then not printed.
.PARAMETER ProjectRoot
    Repository holding `.copilot-tracking/squad/`. Defaults to the current directory.
.PARAMETER SquadRoot
    Explicit squad state root (a plain squad, a federation root, or one member root). Overrides the
    `.copilot-tracking/squad/` default.
.PARAMETER OutputPath
    Local file to write. Defaults to `docs/squad-governance-report-<YYYY-MM-DD>.html` under -ProjectRoot.
    URLs and network shares are refused, and so is any path inside the squad state tree.
.PARAMETER Squad
    In a federation, report only this sub-squad (members/<name>/). Omit to aggregate every sub-squad.
.PARAMETER Period
    all, 30d, or 7d. Filters dated entries; ledger totals are cumulative and labeled as such.
.PARAMETER AsOf
    Date (yyyy-MM-dd) anchoring the period window, the default file name, and the footer. Defaults to
    today (UTC). Pass it to reproduce a report exactly.
.PARAMETER ProjectName
    Name shown in the title. Defaults to the project folder name.
.EXAMPLE
    ./New-SquadGovernanceReport.ps1 -ProjectRoot . -Period 30d
.EXAMPLE
    ./New-SquadGovernanceReport.ps1 -ProjectRoot . -Squad azure -OutputPath docs/azure-governance.html
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).ProviderPath,
    [string]$SquadRoot,
    [string]$OutputPath,
    [string]$Squad,
    [ValidateSet('all', '30d', '7d')][string]$Period = 'all',
    [string]$AsOf,
    [string]$ProjectName
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { Import-Module (Join-Path $PSScriptRoot 'SquadGovernanceReport.psm1') -Force }
catch {
    [Console]::Error.WriteLine("New-SquadGovernanceReport (unexpected failure; follow the manual steps): the renderer module could not be loaded. $($_.Exception.Message)")
    exit 2
}

function Resolve-RealPath {
    <#
    .SYNOPSIS
        The path with every link among its existing ancestors resolved, so a link cannot hide the squad state tree behind a lexical path.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $current = [IO.Path]::GetPathRoot($full)
    $separators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    foreach ($part in $full.Substring($current.Length).Split($separators, [StringSplitOptions]::RemoveEmptyEntries)) {
        $next = [IO.Path]::Combine($current, $part)
        $item = Get-Item -LiteralPath $next -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkTarget) {
            try { $resolved = $item.ResolveLinkTarget($true) }
            catch { throw (New-SquadGovernanceStop "Output path '$Path' crosses a link that cannot be resolved ($($_.Exception.Message)).") }
            if ($resolved) { $next = $resolved.FullName }
        }
        $current = $next
    }
    $current
}

function Resolve-ReportOutputPath {
    param([string]$Path, [string]$Root, [string]$StateRoot, [string]$DefaultName)
    if (-not $Path) { $Path = Join-Path 'docs' $DefaultName }
    if ($Path -match '^\\\\\?\\(?<local>[A-Za-z]:\\.*)$') { $Path = $Matches['local'] }
    if ($Path -match '^[A-Za-z][A-Za-z0-9+.-]+://' -or $Path -match '^(?:\\\\|//)') {
        throw (New-SquadGovernanceStop "Output path '$Path' is not a local filesystem path; the report is never written to a remote location.")
    }
    if ($IsWindows -and $Path -match '^[A-Za-z]:(?![\\/])') { throw (New-SquadGovernanceStop "Output path '$Path' is relative to a drive's current directory; give an absolute path or one relative to the project.") }
    if ($Path -match '[\\/]$') { throw (New-SquadGovernanceStop "Output path '$Path' names a directory; give a file path.") }
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $Root $Path)) }
    if (Test-Path -LiteralPath $full -PathType Container) { throw (New-SquadGovernanceStop "Output path '$full' is a directory.") }
    if ($IsWindows -and $full.Substring([IO.Path]::GetPathRoot($full).Length).Contains(':')) { throw (New-SquadGovernanceStop "Output path '$full' names an alternate data stream; give a plain file path.") }
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $protectedRoots = foreach ($candidate in @($StateRoot, (Join-Path $Root '.copilot-tracking/squad'))) {
        $lexical = [IO.Path]::GetFullPath($candidate)
        $lexical
        Resolve-RealPath -Path $lexical
    }
    foreach ($location in @($full, (Resolve-RealPath -Path $full))) {
        foreach ($protected in $protectedRoots) {
            $guard = $protected.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            if ($location.StartsWith($guard, $comparison)) { throw (New-SquadGovernanceStop "Output path '$full' is inside the squad state tree, which this report only reads.") }
        }
    }
    $full
}

try {
    $root = (Resolve-Path -LiteralPath $ProjectRoot).ProviderPath
    $asOfValue = [datetimeoffset]::UtcNow
    if ($AsOf) {
        $parsed = [datetimeoffset]::MinValue
        $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
        if (-not [datetimeoffset]::TryParse($AsOf, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) { throw (New-SquadGovernanceStop "-AsOf '$AsOf' is not a valid date (use yyyy-MM-dd).") }
        $asOfValue = $parsed
    }
    $stateRoot = if ($SquadRoot) { (Resolve-Path -LiteralPath $SquadRoot).ProviderPath } else { [IO.Path]::GetFullPath((Join-Path $root '.copilot-tracking/squad')) }

    $arguments = @{ ProjectRoot = $root; Period = $Period; AsOf = $asOfValue }
    if ($SquadRoot) { $arguments['SquadRoot'] = $SquadRoot }
    if ($Squad) { $arguments['Squad'] = $Squad }
    if ($ProjectName) { $arguments['ProjectName'] = $ProjectName }
    $model = Get-SquadGovernanceModel @arguments

    $defaultName = 'squad-governance-report-{0}.html' -f $asOfValue.UtcDateTime.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $target = Resolve-ReportOutputPath -Path $OutputPath -Root $root -StateRoot $stateRoot -DefaultName $defaultName
    $html = ConvertTo-SquadGovernanceHtml -Model $model

    $directory = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { $null = New-Item -ItemType Directory -Path $directory -Force }
    $temporary = Join-Path $directory ('.{0}.{1}.tmp' -f [IO.Path]::GetFileName($target), [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, $html, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $target, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }

    $receipt = Get-SquadGovernanceReceipt -Model $model
    $display = [IO.Path]::GetRelativePath($root, $target).Replace('\', '/')
    if ($display.StartsWith('..')) { $display = $target }
    $roi = $null
    if ($model.Economics.Rollup) {
        $r = $model.Economics.Rollup
        $round = { param($v) if ($null -eq $v) { $null } else { [Math]::Round([decimal]$v, 4) } }
        $roi = [ordered]@{
            kind = $r.Kind; squadUsd = (& $round $r.SquadUsd); withoutUsd = (& $round $r.BaselineUsd); savingsUsd = (& $round $r.SavingsUsd)
            savingsPct = (& $round $r.SavingsPct); roiPct = (& $round $r.RoiPct); multiple = (& $round $r.Multiple)
        }
    }
    [ordered]@{
        status      = 'ok'
        path        = $display
        bytes       = [IO.FileInfo]::new($target).Length
        sha256      = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($html))).ToLowerInvariant()
        period      = $receipt.Period
        mode        = $receipt.Mode
        scope       = $receipt.Scope
        summary     = $receipt.Summary
        ledgerBasis = $receipt.Basis
        roi         = $roi
        grounding   = $receipt.Grounding
        gaps        = $receipt.Gaps
        dataQuality = $receipt.DataQuality
    } | ConvertTo-Json -Depth 6 -Compress
}
catch {
    $code = Get-SquadGovernanceExitCode -Exception $_.Exception
    $prefix = if ($code -eq 1) { 'New-SquadGovernanceReport' } else { 'New-SquadGovernanceReport (unexpected failure; follow the manual steps)' }
    [Console]::Error.WriteLine("${prefix}: $($_.Exception.Message)")
    exit $code
}
