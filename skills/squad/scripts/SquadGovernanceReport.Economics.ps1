# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

# Dot-sourced by SquadGovernanceReport.psm1. Turns the ledgers of the units in scope into the
# run economics the report headlines: spend by basis, the without-HVE-Squad comparison, ROI,
# value delivered, and the host-reported whole-session totals. Every figure is arithmetic over
# values the ledgers state; a figure a ledger does not state stays $null and is shown as unavailable.

Set-StrictMode -Version Latest

function Get-SqUnitSpend {
    <#
    .SYNOPSIS
        The stated (or row-summed) cost, credits, tokens, and basis of one unit's ledger, or $null.
    #>
    param([Parameter(Mandatory)]$Unit)
    $view = $Unit.Ledger
    if (-not $view.Present -or $null -eq $view.Usage) { return $null }
    $row = if ($view.Usage.HasTotalRow) { $view.Usage.Total } else { $view.Usage.ComputedTotal }
    [pscustomobject]@{
        Unit    = $Unit.Name
        Usd     = $row.Usd
        Credits = $row.Credits
        Turns   = $row.Turns
        In      = $row.In
        Cached  = $row.Cached
        CacheWr = $row.CacheWr
        Out     = $row.Out
        Tokens  = (Get-SqRowTokens $row)
        Basis   = $view.Usage.Basis
        AsOf    = $(if ($view.Snapshot) { $view.Snapshot.Through } else { '' })
    }
}

function Measure-SqField {
    param([AllowEmptyCollection()][object[]]$Items, [Parameter(Mandatory)][string]$Field)
    Measure-SqSum @($Items | ForEach-Object { $_.$Field })
}

function Get-SqUnitEconomicsMeasures {
    <#
    .SYNOPSIS
        Reads Unit Economics (value) measures by the words in their names; a measure the ledger does not state is $null.
    #>
    param([Parameter(Mandatory)]$Unit)
    $view = $Unit.Ledger
    if (-not $view.Present -or $null -eq $view.UnitEconomics) { return $null }
    $find = {
        param($pattern)
        foreach ($name in $view.UnitEconomics.Measures.Keys) {
            if ($name -match $pattern) { return $view.UnitEconomics.Measures[$name] }
        }
        $null
    }
    $number = { param($m) if ($null -eq $m) { $null } else { ConvertTo-SqDecimal $m.Value } }
    $perAccepted = & $find 'per accepted deliverable'
    [pscustomobject]@{
        Unit               = $Unit.Name
        Produced           = (& $number (& $find '^Deliverables produced'))
        Accepted           = (& $number (& $find '^Accepted by'))
        Rejected           = (& $number (& $find '^Rejected'))
        Unreviewed         = (& $number (& $find '^Unreviewed'))
        FirstPassYieldPct  = (& $number (& $find '^First-pass yield'))
        CreditsPerAccepted = (& $number $perAccepted)
        PerAcceptedLabel   = $(if ($perAccepted) { [string]$perAccepted.Label } else { '' })
    }
}

function Get-SqSavings {
    <#
    .SYNOPSIS
        Saving, ROI, and cost multiple from one with/without pair; each is $null when its denominator is not positive.
    #>
    param([Parameter(Mandatory)][decimal]$SquadUsd, [Parameter(Mandatory)][decimal]$BaselineUsd)
    $saving = $BaselineUsd - $SquadUsd
    [pscustomobject]@{
        SavingsUsd = $saving
        SavingsPct = $(if ($BaselineUsd -gt 0) { $saving / $BaselineUsd * 100 } else { $null })
        RoiPct     = $(if ($SquadUsd -gt 0) { $saving / $SquadUsd * 100 } else { $null })
        Multiple   = $(if ($SquadUsd -gt 0) { $BaselineUsd / $SquadUsd } else { $null })
    }
}

function Get-SqEconomics {
    <#
    .SYNOPSIS
        Aggregates the ledgers of every unit in scope into spend, comparison/ROI, value, role/model/tier breakdowns, and host-reported totals.
    .DESCRIPTION
        Figures on different bases (exact-native, estimated, modeled, host-billed) are kept in
        separate buckets. A total over buckets is flagged mixed and never replaces them.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Units)

    $spends = @(foreach ($unit in $Units) { $s = Get-SqUnitSpend -Unit $unit; if ($s) { $s } })
    $withUsd = @($spends | Where-Object { $null -ne $_.Usd })
    $bases = @($withUsd | ForEach-Object { $_.Basis } | Select-Object -Unique)
    $basisLabel = if ($withUsd.Count -eq 0) { 'unavailable' } elseif ($bases.Count -eq 1) { [string]$bases[0] } else { 'mixed' }
    $byBasis = @(foreach ($basis in ($bases | Sort-Object)) {
            $group = @($withUsd | Where-Object Basis -eq $basis)
            [pscustomobject]@{ Basis = $basis; Usd = (Measure-SqField $group 'Usd'); Credits = (Measure-SqField $group 'Credits'); Units = $group.Count }
        })
    $spend = [pscustomobject]@{
        Usd = (Measure-SqField $withUsd 'Usd'); Credits = (Measure-SqField $withUsd 'Credits'); Basis = $basisLabel; ByBasis = $byBasis
        Covered = $withUsd.Count; Units = @($Units).Count; Turns = (Measure-SqField $spends 'Turns')
    }
    $tokenBases = @($spends | Where-Object { $null -ne $_.Tokens } | ForEach-Object { $_.Basis } | Select-Object -Unique)
    $tokens = [pscustomobject]@{
        In = (Measure-SqField $spends 'In'); Cached = (Measure-SqField $spends 'Cached'); CacheWr = (Measure-SqField $spends 'CacheWr'); Out = (Measure-SqField $spends 'Out')
        Total = (Measure-SqField $spends 'Tokens'); Basis = $(if ($tokenBases.Count -eq 0) { 'unavailable' } elseif ($tokenBases.Count -eq 1) { [string]$tokenBases[0] } else { 'mixed' })
    }

    $roleMap = [ordered]@{}
    $modelMap = [ordered]@{}
    $tierMap = [ordered]@{}
    $orchestrationUsd = $null
    $inputSide = [decimal]0
    $cachedSide = [decimal]0
    foreach ($unit in $Units) {
        $view = $unit.Ledger
        if (-not $view.Present -or $null -eq $view.Usage) { continue }
        foreach ($pair in (Join-SqAttributionToUsage -View $view)) {
            $row = $pair.Usage
            $roleKey = $row.Role
            if (-not $roleMap.Contains($roleKey)) { $roleMap[$roleKey] = [pscustomobject]@{ Role = $roleKey; Usd = $null; Credits = $null; Tokens = $null; Bases = [Collections.Generic.List[string]]::new(); Units = [Collections.Generic.List[string]]::new() } }
            $entry = $roleMap[$roleKey]
            if ($null -ne $row.Usd) { $entry.Usd = [decimal]($(if ($null -ne $entry.Usd) { $entry.Usd } else { 0 }) + $row.Usd) }
            if ($null -ne $row.Credits) { $entry.Credits = [decimal]($(if ($null -ne $entry.Credits) { $entry.Credits } else { 0 }) + $row.Credits) }
            $rowTokens = Get-SqRowTokens $row
            if ($null -ne $rowTokens) { $entry.Tokens = [decimal]($(if ($null -ne $entry.Tokens) { $entry.Tokens } else { 0 }) + $rowTokens) }
            if ($row.Basis -and -not $entry.Bases.Contains($row.Basis)) { $entry.Bases.Add($row.Basis) }
            if (-not $entry.Units.Contains($unit.Name)) { $entry.Units.Add($unit.Name) }
            if ($row.Role -match '^(?i)orchestration$' -and $null -ne $row.Usd) { $orchestrationUsd = [decimal]($(if ($null -ne $orchestrationUsd) { $orchestrationUsd } else { 0 }) + $row.Usd) }
            if ($null -ne $row.In) { $inputSide += $row.In }
            if ($null -ne $row.CacheWr) { $inputSide += $row.CacheWr }
            if ($null -ne $row.Cached) { $inputSide += $row.Cached; $cachedSide += $row.Cached }
            $attribution = $pair.Attribution
            $modelKey = if ($attribution -and $attribution.Model) { $attribution.Model } else { 'not recorded' }
            $tierKey = if ($attribution -and $attribution.Tier) { $attribution.Tier } else { 'not recorded' }
            foreach ($map in @(@($modelMap, $modelKey), @($tierMap, $tierKey))) {
                $target = $map[0]; $key = $map[1]
                if (-not $target.Contains($key)) { $target[$key] = [pscustomobject]@{ Key = $key; Usd = $null; Tokens = $null; Roles = [Collections.Generic.List[string]]::new(); PricedAs = [Collections.Generic.List[string]]::new() } }
                $slot = $target[$key]
                if ($null -ne $row.Usd) { $slot.Usd = [decimal]($(if ($null -ne $slot.Usd) { $slot.Usd } else { 0 }) + $row.Usd) }
                if ($null -ne $rowTokens) { $slot.Tokens = [decimal]($(if ($null -ne $slot.Tokens) { $slot.Tokens } else { 0 }) + $rowTokens) }
                if ($row.Role -and -not $slot.Roles.Contains($row.Role)) { $slot.Roles.Add($row.Role) }
                if ($attribution -and $attribution.PricedAs -and -not $slot.PricedAs.Contains($attribution.PricedAs)) { $slot.PricedAs.Add($attribution.PricedAs) }
            }
        }
    }

    $comparisons = [Collections.Generic.List[object]]::new()
    foreach ($unit in $Units) {
        $view = $unit.Ledger
        if (-not $view.Present) { continue }
        $candidates = @()
        if ($view.Comparison) { $candidates += $view.Comparison }
        if ($view.Observed -and $view.Observed.Comparison) { $candidates += $view.Observed.Comparison }
        foreach ($candidate in $candidates) {
            $math = $null
            if ($candidate.Complete) { $math = Get-SqSavings -SquadUsd $candidate.SquadUsd -BaselineUsd $candidate.BaselineUsd }
            $comparisons.Add([pscustomobject]@{ Unit = $unit.Name; Comparison = $candidate; Math = $math })
        }
    }
    $primary = [Collections.Generic.List[object]]::new()
    foreach ($unit in $Units) {
        $mine = @($comparisons | Where-Object { $_.Unit -eq $unit.Name -and $null -ne $_.Math })
        if ($mine.Count -gt 0) { $primary.Add($mine[0]) }
    }
    $rollup = $null
    if ($primary.Count -gt 0) {
        $squadUsd = Measure-SqSum @($primary | ForEach-Object { $_.Comparison.SquadUsd })
        $baselineUsd = Measure-SqSum @($primary | ForEach-Object { $_.Comparison.BaselineUsd })
        $kinds = @($primary | ForEach-Object { $_.Comparison.Kind } | Select-Object -Unique)
        $models = @($primary | ForEach-Object { $_.Comparison.BaselineModel } | Where-Object { $_ } | Select-Object -Unique)
        $math = Get-SqSavings -SquadUsd $squadUsd -BaselineUsd $baselineUsd
        $rollup = [pscustomobject]@{
            SquadUsd = $squadUsd; BaselineUsd = $baselineUsd; SavingsUsd = $math.SavingsUsd; SavingsPct = $math.SavingsPct; RoiPct = $math.RoiPct; Multiple = $math.Multiple
            Kind = $(if ($kinds.Count -eq 1) { [string]$kinds[0] } else { 'mixed' }); Models = $models; Covered = $primary.Count; Units = @($Units).Count
        }
    }

    $measures = @(foreach ($unit in $Units) { $m = Get-SqUnitEconomicsMeasures -Unit $unit; if ($m) { $m } })
    $value = $null
    if ($measures.Count -gt 0) {
        $accepted = Measure-SqField $measures 'Accepted'
        $weighted = @($measures | Where-Object { $null -ne $_.FirstPassYieldPct -and $null -ne $_.Accepted -and $_.Accepted -gt 0 })
        $firstPass = $null
        if ($weighted.Count -gt 0) {
            $weight = Measure-SqSum @($weighted | ForEach-Object { $_.Accepted })
            $firstPass = (Measure-SqSum @($weighted | ForEach-Object { $_.FirstPassYieldPct * $_.Accepted })) / $weight
        }
        $perAcceptedUsd = $null
        $perAcceptedLabel = ''
        $stated = @($measures | Where-Object { $null -ne $_.CreditsPerAccepted })
        if ($stated.Count -eq $measures.Count -and $stated.Count -eq 1) {
            $perAcceptedUsd = $stated[0].CreditsPerAccepted * $script:SqUsdPerCredit
            $perAcceptedLabel = $stated[0].PerAcceptedLabel
        }
        elseif ($null -ne $accepted -and $accepted -gt 0 -and $null -ne $spend.Usd) {
            $perAcceptedUsd = $spend.Usd / $accepted
            $perAcceptedLabel = 'derived'
        }
        $value = [pscustomobject]@{
            Produced = (Measure-SqField $measures 'Produced'); Accepted = $accepted; Rejected = (Measure-SqField $measures 'Rejected'); Unreviewed = (Measure-SqField $measures 'Unreviewed')
            FirstPassYieldPct = $firstPass; CostPerAcceptedUsd = $perAcceptedUsd; CostPerAcceptedLabel = $perAcceptedLabel; Covered = $measures.Count; Units = @($Units).Count
        }
    }

    $sessions = [Collections.Generic.List[object]]::new()
    $duplicates = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($unit in $Units) {
        $observed = $unit.Ledger.Observed
        if (-not $unit.Ledger.Present -or $null -eq $observed -or $null -eq $observed.SessionCredits) { continue }
        $item = [pscustomobject]@{ Unit = $unit.Name; SessionId = $observed.SessionId; Credits = $observed.SessionCredits; Usd = $observed.SessionUsd; Records = $observed.SessionRecords; Scope = $observed.Scope }
        if ($observed.SessionId -and -not $seen.Add($observed.SessionId)) { $duplicates.Add($item) } else { $sessions.Add($item) }
    }
    $hostBilled = [pscustomobject]@{
        Sessions = $sessions.ToArray(); Duplicates = $duplicates.ToArray()
        Credits = (Measure-SqField $sessions.ToArray() 'Credits'); Usd = (Measure-SqField $sessions.ToArray() 'Usd')
        Unscoped = @($sessions | Where-Object { -not $_.SessionId }).Count
    }

    $overlap = [Collections.Generic.List[string]]::new()
    $owners = @{}
    foreach ($unit in $Units) {
        if ($null -eq $unit.Journal -or -not $unit.Journal.Valid) { continue }
        foreach ($hash in @($unit.Journal.RequestHashes | Select-Object -Unique)) {
            if ($owners.ContainsKey($hash) -and $owners[$hash] -ne $unit.Name) { $overlap.Add($hash) } else { $owners[$hash] = $unit.Name }
        }
    }

    [pscustomobject]@{
        Spend = $spend; Tokens = $tokens; Spends = $spends
        ByRole = @($roleMap.Values); ByModel = @($modelMap.Values); ByTier = @($tierMap.Values)
        OrchestrationUsd = $orchestrationUsd
        OrchestrationSharePct = $(if ($null -ne $orchestrationUsd -and $null -ne $spend.Usd -and $spend.Usd -gt 0) { $orchestrationUsd / $spend.Usd * 100 } else { $null })
        CacheReadSharePct = $(if ($inputSide -gt 0) { $cachedSide / $inputSide * 100 } else { $null })
        Comparisons = $comparisons.ToArray(); Rollup = $rollup; Value = $value; HostBilled = $hostBilled
        NativeOverlap = @($overlap | Select-Object -Unique)
    }
}