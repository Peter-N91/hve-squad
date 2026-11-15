#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Deterministically computes stated monetary value, net value, BCR, and ROI from FinOps benefit and HVE Squad delivery evidence.
.DESCRIPTION
    AI cost: none; runs deterministic decimal math in PowerShell 7.4+ with no model invocation.

    Interprets structured 9-category FinOps benefit claims (business-value-measurement.md),
    cost evidence, and optional HVE Squad consumption ledgers (-SquadRoot) to produce stated
    monetary representations separated strictly by basis:
      - finance-approved (booked value with approved business decision reference)
      - stated-indicative (supported observed outcome + explicit conversion formula)
      - modeled-counterfactual (excluded from stated evidenced totals)
      - unmonetized-native-only (native unit retained when conversion inputs or guardrails are unmet)

    Reads squad state strictly read-only and refuses linked paths or output paths inside `.copilot-tracking/squad/`.
.PARAMETER ClaimsPath
    Path to a JSON file containing report metadata, benefit_claims/claims, cost_evidence/costEvidence,
    optional fx_rates/fxRates, and optional delivery_valuation/deliveryValuation.
.PARAMETER ClaimsJson
    Inline JSON string equivalent to -ClaimsPath. Mutually exclusive with -ClaimsPath.
.PARAMETER SquadRoot
    Optional HVE Squad root (single squad, federation root, or member root) read strictly read-only
    for AI spend, accepted-deliverable unit economics, counterfactual savings, and decisions.md claims.
.PARAMETER OutputPath
    Optional local path to write the rendered report (.md or .json). Never inside `.copilot-tracking/squad/`.
.PARAMETER Format
    Output format written to stdout: json (default) or markdown.
.PARAMETER AsOf
    Optional YYYY-MM-DD override for reproducible output.
.EXAMPLE
    ./Measure-SquadBenefitValue.ps1 -ClaimsPath ./claims.json -SquadRoot .copilot-tracking/squad -OutputPath .copilot-tracking/finops/stated-value.md
#>
[CmdletBinding()]
param(
    [string]$ClaimsPath,
    [string]$ClaimsJson,
    [string]$SquadRoot,
    [string]$OutputPath,
    [ValidateSet('json', 'markdown')]
    [string]$Format = 'json',
    [string]$AsOf
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'SquadBenefitValuation.psm1') -Force

function Resolve-BvRealPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    $full = [IO.Path]::GetFullPath($Path)
    $current = [IO.Path]::GetPathRoot($full)
    $separators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    foreach ($part in $full.Substring($current.Length).Split($separators, [StringSplitOptions]::RemoveEmptyEntries)) {
        $next = [IO.Path]::Combine($current, $part)
        $item = Get-Item -LiteralPath $next -Force -ErrorAction SilentlyContinue
        if ($item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.LinkTarget)) {
            throw (Get-SquadBenefitValuationStop "Path '$Path' crosses a symbolic link or reparse point.")
        }
        $current = $next
    }
    return $current
}

function Resolve-BvSafeOutputPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$ProtectedSquadRoot
    )
    if ($Path -match '^[A-Za-z][A-Za-z0-9+.-]+://' -or $Path -match '^(?:\\\\|//)') {
        throw (Get-SquadBenefitValuationStop "OutputPath '$Path' must be a local filesystem path.")
    }
    if ($Path -match '[\\/]$') {
        throw (Get-SquadBenefitValuationStop "OutputPath '$Path' names a directory; supply a file path.")
    }
    $full = Resolve-BvRealPath -Path $Path
    if (Test-Path -LiteralPath $full -PathType Container) {
        throw (Get-SquadBenefitValuationStop "OutputPath '$full' is an existing directory.")
    }
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $protectedCandidates = [Collections.Generic.List[string]]::new()
    $defaultState = [IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath '.copilot-tracking/squad'))
    $protectedCandidates.Add($defaultState)
    if (-not [string]::IsNullOrWhiteSpace($ProtectedSquadRoot)) {
        $protectedCandidates.Add([IO.Path]::GetFullPath($ProtectedSquadRoot))
    }
    foreach ($prot in $protectedCandidates) {
        $guard = $prot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if ($full.Equals($prot.TrimEnd('\', '/'), $comparison) -or $full.StartsWith($guard, $comparison)) {
            throw (Get-SquadBenefitValuationStop "OutputPath '$full' is inside the protected squad state tree; write valuation artifacts to the Deliverable Root (for example .copilot-tracking/finops/ or docs/finops/).")
        }
    }
    return $full
}

try {
    if (-not [string]::IsNullOrWhiteSpace($ClaimsPath) -and -not [string]::IsNullOrWhiteSpace($ClaimsJson)) {
        throw (Get-SquadBenefitValuationStop 'Specify either -ClaimsPath or -ClaimsJson, not both.')
    }
    if ([string]::IsNullOrWhiteSpace($ClaimsPath) -and [string]::IsNullOrWhiteSpace($ClaimsJson) -and [string]::IsNullOrWhiteSpace($SquadRoot)) {
        throw (Get-SquadBenefitValuationStop 'Supply at least one input source (-ClaimsPath, -ClaimsJson, or -SquadRoot).')
    }

    $inputDoc = $null
    if (-not [string]::IsNullOrWhiteSpace($ClaimsPath)) {
        $safeClaims = Resolve-BvRealPath -Path $ClaimsPath
        if (-not (Test-Path -LiteralPath $safeClaims -PathType Leaf)) {
            throw (Get-SquadBenefitValuationStop "ClaimsPath '$ClaimsPath' was not found.")
        }
        $rawJson = [IO.File]::ReadAllText($safeClaims)
        try {
            $inputDoc = $rawJson | ConvertFrom-Json -Depth 32
        }
        catch {
            throw (Get-SquadBenefitValuationStop "ClaimsPath '$ClaimsPath' is not valid JSON: $($_.Exception.Message)")
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ClaimsJson)) {
        try {
            $inputDoc = $ClaimsJson | ConvertFrom-Json -Depth 32
        }
        catch {
            throw (Get-SquadBenefitValuationStop "ClaimsJson is not valid JSON: $($_.Exception.Message)")
        }
    }

    $model = Get-SquadBenefitValuation -InputDocument $inputDoc -SquadRoot $SquadRoot -AsOf $AsOf

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $safeOut = Resolve-BvSafeOutputPath -Path $OutputPath -ProtectedSquadRoot $SquadRoot
        $parent = Split-Path -Parent $safeOut
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $fileBody = if ($safeOut.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)) {
            ($model | ConvertTo-Json -Depth 20) + "`n"
        }
        else {
            ConvertTo-SquadBenefitValuationMarkdown -Model $model
        }
        [IO.File]::WriteAllText($safeOut, $fileBody, [Text.UTF8Encoding]::new($false))
        $model['artifactPath'] = $safeOut
    }

    if ($Format -eq 'markdown') {
        [Console]::Out.Write((ConvertTo-SquadBenefitValuationMarkdown -Model $model))
    }
    else {
        [Console]::Out.WriteLine(($model | ConvertTo-Json -Depth 20))
    }
    exit 0
}
catch {
    if ($_.Exception.Data.Contains('SquadBenefitValuationStop')) {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
    [Console]::Error.WriteLine("Measure-SquadBenefitValue (unexpected failure): $($_.Exception.Message)")
    exit 2
}
