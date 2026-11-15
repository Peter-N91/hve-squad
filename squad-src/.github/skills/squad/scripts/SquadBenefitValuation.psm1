# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Deterministic FinOps benefit and delivery valuation engine for HVE Squad.
.DESCRIPTION
    Pure, read-only valuation math over supplied 9-category benefit claims, cost evidence,
    and HVE Squad consumption ledgers. Never invokes a model, never mutates squad state,
    never invents unit rates or Finance approvals, and never merges modeled counterfactuals
    or foreign currencies into evidenced stated monetary totals.
#>

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'SquadGovernanceReport.Markdown.ps1')
. (Join-Path $PSScriptRoot 'SquadGovernanceReport.State.ps1')
. (Join-Path $PSScriptRoot 'SquadGovernanceReport.Ledger.ps1')
. (Join-Path $PSScriptRoot 'SquadGovernanceReport.Economics.ps1')

$script:CanonicalCategories = [ordered]@{
    'revenue enablement'  = 'revenue enablement'
    'revenue_enablement'  = 'revenue enablement'
    'revenue-enablement'  = 'revenue enablement'
    'cost avoidance'      = 'cost avoidance'
    'cost_avoidance'      = 'cost avoidance'
    'cost-avoidance'      = 'cost avoidance'
    'capacity gained'     = 'capacity gained'
    'capacity_gained'     = 'capacity gained'
    'capacity-gained'     = 'capacity gained'
    'labour augmentation' = 'labour augmentation'
    'labor augmentation'  = 'labour augmentation'
    'labour_augmentation' = 'labour augmentation'
    'labor_augmentation'  = 'labour augmentation'
    'labour-augmentation' = 'labour augmentation'
    'labor-augmentation'  = 'labour augmentation'
    'quality'             = 'quality'
    'speed'               = 'speed'
    'risk reduction'      = 'risk reduction'
    'risk_reduction'      = 'risk reduction'
    'risk-reduction'      = 'risk reduction'
    'new capacity'        = 'new capacity'
    'new_capacity'        = 'new capacity'
    'new-capacity'        = 'new capacity'
    'engagement'          = 'engagement'
}

$script:DefaultDecreaseCategories = @(
    'cost avoidance'
    'quality'
    'speed'
    'risk reduction'
)

function Get-SquadBenefitValuationStop {
    <#
    .SYNOPSIS
        Constructs a documented stop exception for Measure-SquadBenefitValue.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )
    $err = [InvalidOperationException]::new("Measure-SquadBenefitValue: $Message")
    $err.Data['SquadBenefitValuationStop'] = $true
    return $err
}

function Assert-BvSafeReadPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = $full
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.LinkTarget)) {
            throw (Get-SquadBenefitValuationStop "Linked path refused: '$Path'.")
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) {
            break
        }
        $cursor = $parent
    }
    return $full
}

function Resolve-BvCanonicalCategory {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Category
    )
    if ([string]::IsNullOrWhiteSpace($Category)) {
        return $null
    }
    $key = ($Category.Trim().ToLowerInvariant() -replace '\s+', ' ')
    if ($script:CanonicalCategories.Contains($key)) {
        return [string]$script:CanonicalCategories[$key]
    }
    throw (Get-SquadBenefitValuationStop "Unsupported benefit category '$Category'. Expected one of the nine FinOps categories in business-value-measurement.md.")
}

function ConvertTo-BvDecimal {
    param(
        [AllowNull()]
        $Value,

        [Parameter(Mandatory)]
        [string]$FieldName
    )
    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
        return $null
    }
    if ($Value -is [bool]) {
        throw (Get-SquadBenefitValuationStop "Field '$FieldName' must be numeric, not boolean.")
    }
    $parsed = [decimal]0
    $text = [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture).Trim()
    if (-not [decimal]::TryParse($text, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        throw (Get-SquadBenefitValuationStop "Field '$FieldName' ('$Value') is not a finite decimal number.")
    }
    return $parsed
}

function Get-BvProp {
    param(
        [AllowNull()]
        $Object,

        [Parameter(Mandatory)]
        [string]$Name
    )
    if ($null -eq $Object) {
        return $null
    }
    if ($Object -is [Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key, $Name, [StringComparison]::OrdinalIgnoreCase)) {
                return $Object[$key]
            }
        }
        return $null
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop) {
        return $prop.Value
    }
    return $null
}

function ConvertTo-BvCurrencyAmount {
    param(
        [Parameter(Mandatory)]
        [decimal]$Amount,

        [Parameter(Mandatory)]
        [string]$SourceCurrency,

        [Parameter(Mandatory)]
        [string]$TargetCurrency,

        [AllowNull()]
        $FxRates
    )
    $src = $SourceCurrency.Trim().ToUpperInvariant()
    $dst = $TargetCurrency.Trim().ToUpperInvariant()
    if ($src -ceq $dst) {
        return [pscustomobject]@{
            Converted = $true
            Amount    = $Amount
            Rate      = [decimal]1
            Note      = $null
        }
    }
    $rateObj = Get-BvProp -Object $FxRates -Name $src
    if ($null -eq $rateObj) {
        $pairRate = Get-BvProp -Object $FxRates -Name "$src->$dst"
        if ($null -ne $pairRate) {
            $rateObj = $pairRate
        }
    }
    if ($null -eq $rateObj) {
        return [pscustomobject]@{
            Converted = $false
            Amount    = $null
            Rate      = $null
            Note      = "Currency '$src' differs from report currency '$dst' and no fxRates['$src'] conversion factor was supplied."
        }
    }
    $rate = ConvertTo-BvDecimal -Value $rateObj -FieldName "fxRates.$src"
    if ($null -eq $rate -or $rate -le 0) {
        throw (Get-SquadBenefitValuationStop "FX rate for '$src' must be a positive number.")
    }
    return [pscustomobject]@{
        Converted = $true
        Amount    = ($Amount * $rate)
        Rate      = $rate
        Note      = "Converted from $src to $dst at supplied FX rate $rate."
    }
}

function Get-BvDecisionClaimsFromMarkdown {
    <#
    .SYNOPSIS
        Extracts structured `Claim ID: ...` lines preserved in decisions.md via PR #170 rationale transport.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DecisionsPath
    )
    if (-not (Test-Path -LiteralPath $DecisionsPath -PathType Leaf)) {
        return @()
    }
    $null = Assert-BvSafeReadPath -Path $DecisionsPath
    $content = [IO.File]::ReadAllText($DecisionsPath) -replace "`r`n", "`n"
    $extracted = [Collections.Generic.List[object]]::new()
    $seenIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($line in ($content -split "`n")) {
        if ($line -notmatch '(?i)\bClaim ID:\s*(?<id>[A-Za-z0-9_.:-]+)') {
            continue
        }
        $claimId = $Matches['id'].Trim().TrimEnd(';', '.', ',')
        if (-not $seenIds.Add($claimId)) {
            continue
        }
        $fields = @{}
        foreach ($segment in ($line -split ';')) {
            $kv = $segment.Trim()
            if ($kv -match '^(?<k>[A-Za-z][A-Za-z0-9 _/-]*):\s*(?<v>.+)$') {
                $k = ($Matches['k'].Trim().ToLowerInvariant() -replace '\s+', ' ')
                $fields[$k] = $Matches['v'].Trim().TrimEnd('.')
            }
        }
        $rawCat = if ($fields.ContainsKey('category')) { $fields['category'] } else { $null }
        $cat = $null
        if ($rawCat) {
            $normKey = ($rawCat.ToLowerInvariant() -replace '\s+', ' ')
            if ($script:CanonicalCategories.Contains($normKey)) {
                $cat = [string]$script:CanonicalCategories[$normKey]
            }
        }
        $status = if ($fields.ContainsKey('status') -and $fields['status'].ToLowerInvariant() -in @('supported', 'gap', 'pending')) {
            $fields['status'].ToLowerInvariant()
        }
        else {
            'pending'
        }
        $extracted.Add([pscustomobject]@{
                claim_id          = $claimId
                category          = $cat
                hypothesis        = $(if ($fields.ContainsKey('hypothesis')) { $fields['hypothesis'] } else { $null })
                beneficiary       = $(if ($fields.ContainsKey('beneficiary')) { $fields['beneficiary'] } else { $null })
                status            = $status
                measurement_owner = $(if ($fields.ContainsKey('measurement owner')) { $fields['measurement owner'] } else { $null })
                decision_owner    = $(if ($fields.ContainsKey('business decision owner')) { $fields['business decision owner'] } else { $null })
                decision_ref      = $(if ($fields.ContainsKey('decision ref')) { $fields['decision ref'] } else { $null })
                evidence_links    = $(if ($fields.ContainsKey('source evidence')) { @($fields['source evidence']) } else { @() })
                baseline_text     = $(if ($fields.ContainsKey('baseline')) { $fields['baseline'] } else { $null })
                target_text       = $(if ($fields.ContainsKey('target')) { $fields['target'] } else { $null })
                source_origin     = 'decisions.md'
            })
    }
    return $extracted.ToArray()
}

function Get-BvSquadLedgerSummary {
    <#
    .SYNOPSIS
        Reads single-squad or federation consumption ledgers read-only using SquadGovernanceReport helpers when available,
        with direct consumption.md parsing for standalone squad roots.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SquadRoot
    )
    $resolvedRoot = Assert-BvSafeReadPath -Path $SquadRoot
    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        throw (Get-SquadBenefitValuationStop "SquadRoot '$SquadRoot' does not exist or is not a directory.")
    }

    $unitRoots = [Collections.Generic.List[object]]::new()
    $federationFile = Join-Path $resolvedRoot 'federation.md'
    $membersDir = Join-Path $resolvedRoot 'members'
    if ((Test-Path -LiteralPath $federationFile -PathType Leaf) -and (Test-Path -LiteralPath $membersDir -PathType Container)) {
        foreach ($dir in (Get-ChildItem -LiteralPath $membersDir -Directory -Force | Sort-Object Name)) {
            $null = Assert-BvSafeReadPath -Path $dir.FullName
            $ledgerPath = Join-Path $dir.FullName 'consumption.md'
            $ledgerText = ''
            if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) {
                $null = Assert-BvSafeReadPath -Path $ledgerPath
                $ledgerText = [IO.File]::ReadAllText($ledgerPath)
            }
            $ledgerView = Get-SqLedgerView -Text $ledgerText
            $unitRoots.Add([pscustomobject]@{
                    Name          = $dir.Name
                    RootPath      = $dir.FullName
                    DecisionsPath = (Join-Path $dir.FullName 'decisions.md')
                    Ledger        = $ledgerView
                    Journal       = $null
                })
        }
    }
    else {
        $ledgerPath = Join-Path $resolvedRoot 'consumption.md'
        $ledgerText = ''
        if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) {
            $null = Assert-BvSafeReadPath -Path $ledgerPath
            $ledgerText = [IO.File]::ReadAllText($ledgerPath)
        }
        $ledgerView = Get-SqLedgerView -Text $ledgerText
        $unitRoots.Add([pscustomobject]@{
                Name          = (Split-Path -Leaf $resolvedRoot)
                RootPath      = $resolvedRoot
                DecisionsPath = (Join-Path $resolvedRoot 'decisions.md')
                Ledger        = $ledgerView
                Journal       = $null
            })
    }

    $economics = Get-SqEconomics -Units $unitRoots.ToArray()
    $decisionClaims = [Collections.Generic.List[object]]::new()
    foreach ($unit in $unitRoots) {
        foreach ($dc in (Get-BvDecisionClaimsFromMarkdown -DecisionsPath $unit.DecisionsPath)) {
            $decisionClaims.Add($dc)
        }
    }

    return [pscustomobject]@{
        SquadRoot      = $resolvedRoot
        UnitCount      = $unitRoots.Count
        Economics      = $economics
        DecisionClaims = $decisionClaims.ToArray()
    }
}

function Measure-BvSingleClaim {
    <#
    .SYNOPSIS
        Evaluates one FinOps benefit claim into native outcome delta, monetary basis, gross value, and missing-input diagnostics.
    #>
    param(
        [Parameter(Mandatory)]
        $Claim,

        [Parameter(Mandatory)]
        [string]$ReportCurrency,

        [AllowNull()]
        $FxRates
    )
    $claimId = [string](Get-BvProp -Object $Claim -Name 'claim_id')
    if ([string]::IsNullOrWhiteSpace($claimId)) {
        $claimId = [string](Get-BvProp -Object $Claim -Name 'claimId')
    }
    if ([string]::IsNullOrWhiteSpace($claimId)) {
        throw (Get-SquadBenefitValuationStop 'Every claim in claims[] must declare a non-empty claim_id.')
    }

    $rawCategory = [string](Get-BvProp -Object $Claim -Name 'category')
    $category = Resolve-BvCanonicalCategory -Category $rawCategory
    $hypothesis = [string](Get-BvProp -Object $Claim -Name 'hypothesis')
    $beneficiary = [string](Get-BvProp -Object $Claim -Name 'beneficiary')
    $measurementOwner = [string](Get-BvProp -Object $Claim -Name 'measurement_owner')
    if ([string]::IsNullOrWhiteSpace($measurementOwner)) {
        $measurementOwner = [string](Get-BvProp -Object $Claim -Name 'measurementOwner')
    }

    $businessDecision = Get-BvProp -Object $Claim -Name 'business_decision'
    if ($null -eq $businessDecision) {
        $businessDecision = Get-BvProp -Object $Claim -Name 'businessDecision'
    }
    $decisionOwner = [string](Get-BvProp -Object $businessDecision -Name 'owner')
    if ([string]::IsNullOrWhiteSpace($decisionOwner)) {
        $decisionOwner = [string](Get-BvProp -Object $Claim -Name 'decision_owner')
    }
    $decisionStatus = [string](Get-BvProp -Object $businessDecision -Name 'status')
    if ([string]::IsNullOrWhiteSpace($decisionStatus)) {
        $decisionStatus = 'unapproved'
    }
    $decisionRef = [string](Get-BvProp -Object $businessDecision -Name 'reference')
    if ([string]::IsNullOrWhiteSpace($decisionRef)) {
        $decisionRef = [string](Get-BvProp -Object $Claim -Name 'decision_ref')
    }

    $rawStatus = [string](Get-BvProp -Object $Claim -Name 'status')
    if ([string]::IsNullOrWhiteSpace($rawStatus)) {
        $rawStatus = [string](Get-BvProp -Object $Claim -Name 'evidence_status')
    }
    $evidenceStatus = if ([string]::IsNullOrWhiteSpace($rawStatus)) { 'pending' } else { $rawStatus.Trim().ToLowerInvariant() }
    if ($evidenceStatus -notin @('supported', 'gap', 'pending')) {
        throw (Get-SquadBenefitValuationStop "Claim '$claimId' has invalid status '$evidenceStatus'. Expected supported, gap, or pending.")
    }

    $baseline = Get-BvProp -Object $Claim -Name 'baseline'
    $target = Get-BvProp -Object $Claim -Name 'target'
    $observation = Get-BvProp -Object $Claim -Name 'observation'
    $valuation = Get-BvProp -Object $Claim -Name 'valuation'

    $evidenceLinksRaw = Get-BvProp -Object $Claim -Name 'evidence_links'
    if ($null -eq $evidenceLinksRaw) {
        $evidenceLinksRaw = Get-BvProp -Object $Claim -Name 'evidenceLinks'
    }
    $evidenceLinks = @(
        if ($null -ne $evidenceLinksRaw) {
            foreach ($lnk in @($evidenceLinksRaw)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$lnk)) {
                    ([string]$lnk).Trim()
                }
            }
        }
    )

    $gaps = [Collections.Generic.List[string]]::new()
    $missingInputs = [Collections.Generic.List[string]]::new()
    $notes = [Collections.Generic.List[string]]::new()

    if (-not $category) {
        $gaps.Add('Missing primary FinOps value category.')
    }
    if ([string]::IsNullOrWhiteSpace($hypothesis)) {
        $gaps.Add('Missing explicit benefit hypothesis.')
    }
    if ([string]::IsNullOrWhiteSpace($beneficiary)) {
        $gaps.Add('Missing beneficiary/scope.')
    }
    if ([string]::IsNullOrWhiteSpace($measurementOwner)) {
        $gaps.Add('Missing measurement owner.')
    }
    if ($evidenceStatus -eq 'supported' -and $evidenceLinks.Count -eq 0) {
        $gaps.Add('Claim is marked supported but carries no evidence_links.')
    }

    $baseVal = ConvertTo-BvDecimal -Value (Get-BvProp -Object $baseline -Name 'value') -FieldName "$claimId.baseline.value"
    $baseUnit = [string](Get-BvProp -Object $baseline -Name 'unit')
    $targVal = ConvertTo-BvDecimal -Value (Get-BvProp -Object $target -Name 'value') -FieldName "$claimId.target.value"
    $obsVal = ConvertTo-BvDecimal -Value (Get-BvProp -Object $observation -Name 'value') -FieldName "$claimId.observation.value"
    $obsUnit = [string](Get-BvProp -Object $observation -Name 'unit')

    $unitMismatch = $false
    if (-not [string]::IsNullOrWhiteSpace($baseUnit) -and -not [string]::IsNullOrWhiteSpace($obsUnit) -and
        -not [string]::Equals($baseUnit.Trim(), $obsUnit.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
        $unitMismatch = $true
        $gaps.Add("Unit mismatch between baseline ('$baseUnit') and observation ('$obsUnit').")
    }

    $directionRaw = [string](Get-BvProp -Object $valuation -Name 'direction')
    $isDecrease = if (-not [string]::IsNullOrWhiteSpace($directionRaw)) {
        $directionRaw.Trim().ToLowerInvariant() -eq 'decrease'
    }
    elseif ($null -ne $baseVal -and $null -ne $targVal -and $targVal -ne $baseVal) {
        $targVal -lt $baseVal
    }
    else {
        $category -in $script:DefaultDecreaseCategories
    }

    $nativeDelta = $null
    $targetNativeDelta = $null
    if (-not $unitMismatch -and $null -ne $baseVal -and $null -ne $obsVal) {
        $nativeDelta = if ($isDecrease) { $baseVal - $obsVal } else { $obsVal - $baseVal }
    }
    if ($null -ne $baseVal -and $null -ne $targVal) {
        $targetNativeDelta = if ($isDecrease) { $baseVal - $targVal } else { $targVal - $baseVal }
    }

    $overlapGroup = [string](Get-BvProp -Object $Claim -Name 'overlap_group')
    if ([string]::IsNullOrWhiteSpace($overlapGroup)) {
        $overlapGroup = [string](Get-BvProp -Object $Claim -Name 'overlapGroup')
    }
    if ([string]::IsNullOrWhiteSpace($overlapGroup)) {
        $overlapGroup = [string](Get-BvProp -Object $valuation -Name 'overlapGroup')
    }
    $primaryInGroup = [bool](Get-BvProp -Object $valuation -Name 'primaryInGroup')
    $overlapShare = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'overlapShare') -FieldName "$claimId.valuation.overlapShare"
    if ($null -eq $overlapShare) {
        $overlapShare = [decimal]1
    }
    if ($overlapShare -lt 0 -or $overlapShare -gt 1) {
        throw (Get-SquadBenefitValuationStop "Claim '$claimId' overlapShare must be between 0 and 1.")
    }

    $valCurrency = [string](Get-BvProp -Object $valuation -Name 'currency')
    if ([string]::IsNullOrWhiteSpace($valCurrency)) {
        $valCurrency = $ReportCurrency
    }
    $attributionShare = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'attributionShare') -FieldName "$claimId.valuation.attributionShare"
    if ($null -eq $attributionShare) {
        $attributionShare = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'attribution_share') -FieldName "$claimId.valuation.attribution_share"
    }
    $periodFactor = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'periodFactor') -FieldName "$claimId.valuation.periodFactor"
    if ($null -eq $periodFactor) {
        $periodFactor = [decimal]1
    }
    if ($periodFactor -le 0) {
        throw (Get-SquadBenefitValuationStop "Claim '$claimId' periodFactor must be positive.")
    }

    $uncertaintyPct = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'uncertaintyPct') -FieldName "$claimId.valuation.uncertaintyPct"
    if ($null -ne $uncertaintyPct -and ($uncertaintyPct -lt 0 -or $uncertaintyPct -gt 100)) {
        throw (Get-SquadBenefitValuationStop "Claim '$claimId' uncertaintyPct must be between 0 and 100.")
    }

    $financeApprovedFlag = (Get-BvProp -Object $valuation -Name 'financeApproved') -eq $true -or
    (Get-BvProp -Object $valuation -Name 'finance_approved') -eq $true

    # Evaluate monetary conversion only when category + valuation inputs exist and guardrails pass.
    $useForecast = ($evidenceStatus -eq 'pending' -and $null -eq $nativeDelta -and $null -ne $targetNativeDelta)
    $workingDelta = if ($useForecast) { $targetNativeDelta } else { $nativeDelta }

    $grossRaw = $null
    $formulaText = $null
    $monetizable = $true

    if ($evidenceStatus -eq 'gap' -or $unitMismatch -or -not $category) {
        $monetizable = $false
    }
    elseif ($evidenceStatus -eq 'supported' -and $evidenceLinks.Count -eq 0) {
        $monetizable = $false
        $missingInputs.Add('evidence_links')
    }
    elseif ($null -eq $valuation) {
        $monetizable = $false
        $missingInputs.Add('valuation')
    }

    if ($monetizable) {
        if ($null -eq $attributionShare) {
            $monetizable = $false
            $missingInputs.Add('valuation.attributionShare')
        }
        elseif ($attributionShare -le 0 -or $attributionShare -gt 1) {
            throw (Get-SquadBenefitValuationStop "Claim '$claimId' attributionShare must be in (0, 1].")
        }
    }

    if ($monetizable) {
        $volume = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'volume') -FieldName "$claimId.valuation.volume"
        if ($null -eq $volume) {
            $volume = [decimal]1
        }
        if ($volume -lt 0) {
            throw (Get-SquadBenefitValuationStop "Claim '$claimId' volume cannot be negative.")
        }

        switch ($category) {
            'revenue enablement' {
                $pipelineOnly = (Get-BvProp -Object $valuation -Name 'pipelineOnly') -eq $true
                $convRate = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'conversionToRecognizedRate') -FieldName "$claimId.valuation.conversionToRecognizedRate"
                $unitValue = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'unitValue') -FieldName "$claimId.valuation.unitValue"
                if ($null -eq $unitValue) {
                    $unitValue = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'unitMargin') -FieldName "$claimId.valuation.unitMargin"
                }
                if ($pipelineOnly -and $null -eq $convRate) {
                    $monetizable = $false
                    $missingInputs.Add('valuation.conversionToRecognizedRate')
                    $notes.Add('Influenced pipeline is separated from incremental recognized revenue; supply conversionToRecognizedRate to monetize.')
                }
                elseif ($null -eq $workingDelta -or $workingDelta -le 0) {
                    $monetizable = $false
                    if ($null -eq $workingDelta) { $missingInputs.Add('observation.value') }
                }
                elseif ($null -eq $unitValue -or $unitValue -le 0) {
                    $monetizable = $false
                    $missingInputs.Add('valuation.unitValue')
                }
                else {
                    $effConv = if ($null -ne $convRate) { $convRate } else { [decimal]1 }
                    if ($effConv -le 0 -or $effConv -gt 1) {
                        throw (Get-SquadBenefitValuationStop "Claim '$claimId' conversionToRecognizedRate must be in (0, 1].")
                    }
                    $grossRaw = $workingDelta * $volume * $effConv * $unitValue * $attributionShare * $periodFactor
                    $formulaText = "$workingDelta * volume($volume) * conv($effConv) * unitValue($unitValue) * attr($attributionShare) * period($periodFactor)"
                }
            }
            'cost avoidance' {
                $cfCost = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'counterfactualCost') -FieldName "$claimId.valuation.counterfactualCost"
                $obsCost = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'observedCost') -FieldName "$claimId.valuation.observedCost"
                $unitCost = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'unitCost') -FieldName "$claimId.valuation.unitCost"
                if ($null -ne $cfCost -and $null -ne $obsCost) {
                    $diff = $cfCost - $obsCost
                    if ($diff -le 0) {
                        $monetizable = $false
                        $notes.Add('Observed cost exceeded or equaled counterfactual cost; no positive cost avoidance.')
                    }
                    else {
                        $grossRaw = $diff * $attributionShare * $periodFactor
                        $formulaText = "(counterfactualCost($cfCost) - observedCost($obsCost)) * attr($attributionShare) * period($periodFactor)"
                    }
                }
                elseif ($null -ne $workingDelta -and $workingDelta -gt 0 -and $null -ne $unitCost -and $unitCost -gt 0) {
                    $grossRaw = $workingDelta * $volume * $unitCost * $attributionShare * $periodFactor
                    $formulaText = "$workingDelta * volume($volume) * unitCost($unitCost) * attr($attributionShare) * period($periodFactor)"
                }
                else {
                    $monetizable = $false
                    if ($null -eq $unitCost -and $null -eq $cfCost) { $missingInputs.Add('valuation.unitCost or counterfactualCost/observedCost') }
                    if ($null -eq $workingDelta -and $null -eq $cfCost) { $missingInputs.Add('observation.value') }
                }
            }
            'capacity gained' {
                $hourlyRate = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'hourlyRate') -FieldName "$claimId.valuation.hourlyRate"
                $redeployedShare = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'redeployedShare') -FieldName "$claimId.valuation.redeployedShare"
                $avoidedExpense = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'avoidedExpenseAmount') -FieldName "$claimId.valuation.avoidedExpenseAmount"
                if ($null -ne $avoidedExpense -and $avoidedExpense -gt 0 -and ($evidenceStatus -eq 'supported' -or $useForecast)) {
                    $grossRaw = $avoidedExpense * $attributionShare * $periodFactor
                    $formulaText = "avoidedExpenseAmount($avoidedExpense) * attr($attributionShare) * period($periodFactor)"
                }
                elseif ($null -eq $workingDelta -or $workingDelta -le 0) {
                    $monetizable = $false
                    if ($null -eq $workingDelta) { $missingInputs.Add('observation.value') }
                }
                elseif ($null -eq $hourlyRate -or $hourlyRate -le 0 -or $null -eq $redeployedShare -or $redeployedShare -le 0) {
                    $monetizable = $false
                    if ($null -eq $hourlyRate -or $hourlyRate -le 0) { $missingInputs.Add('valuation.hourlyRate') }
                    if ($null -eq $redeployedShare -or $redeployedShare -le 0) { $missingInputs.Add('valuation.redeployedShare') }
                    $notes.Add('Released capacity remains in native hours unless evidenced redeployment share and hourlyRate (or avoidedExpenseAmount) are supplied.')
                }
                else {
                    if ($redeployedShare -gt 1) {
                        throw (Get-SquadBenefitValuationStop "Claim '$claimId' redeployedShare must be in (0, 1].")
                    }
                    $grossRaw = $workingDelta * $volume * $redeployedShare * $hourlyRate * $attributionShare * $periodFactor
                    $formulaText = "$workingDelta * volume($volume) * redeployed($redeployedShare) * hourlyRate($hourlyRate) * attr($attributionShare) * period($periodFactor)"
                }
            }
            'labour augmentation' {
                $qualityFloorMet = Get-BvProp -Object $valuation -Name 'qualityFloorMet'
                $hourlyRate = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'hourlyRate') -FieldName "$claimId.valuation.hourlyRate"
                $redeployedShare = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'redeployedShare') -FieldName "$claimId.valuation.redeployedShare"
                if ($qualityFloorMet -eq $false) {
                    $monetizable = $false
                    $gaps.Add('Quality floor was violated (qualityFloorMet=false); labour augmentation cannot be monetized when quality degrades.')
                }
                elseif ($null -eq $workingDelta -or $workingDelta -le 0) {
                    $monetizable = $false
                    if ($null -eq $workingDelta) { $missingInputs.Add('observation.value') }
                }
                elseif ($null -eq $hourlyRate -or $hourlyRate -le 0 -or $null -eq $redeployedShare -or $redeployedShare -le 0) {
                    $monetizable = $false
                    if ($null -eq $hourlyRate -or $hourlyRate -le 0) { $missingInputs.Add('valuation.hourlyRate') }
                    if ($null -eq $redeployedShare -or $redeployedShare -le 0) { $missingInputs.Add('valuation.redeployedShare') }
                    $notes.Add('Productivity gains alone do not remove labor cost; supply hourlyRate and evidenced redeployedShare.')
                }
                else {
                    if ($redeployedShare -gt 1) {
                        throw (Get-SquadBenefitValuationStop "Claim '$claimId' redeployedShare must be in (0, 1].")
                    }
                    $grossRaw = $workingDelta * $volume * $redeployedShare * $hourlyRate * $attributionShare * $periodFactor
                    $formulaText = "$workingDelta * volume($volume) * redeployed($redeployedShare) * hourlyRate($hourlyRate) * attr($attributionShare) * period($periodFactor)"
                }
            }
            'quality' {
                $costPerDefect = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'costPerDefect') -FieldName "$claimId.valuation.costPerDefect"
                if ($null -eq $costPerDefect) {
                    $costPerDefect = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'unitCost') -FieldName "$claimId.valuation.unitCost"
                }
                if ($null -eq $workingDelta -or $workingDelta -le 0) {
                    $monetizable = $false
                    if ($null -eq $workingDelta) { $missingInputs.Add('observation.value') }
                }
                elseif ($null -eq $costPerDefect -or $costPerDefect -le 0) {
                    $monetizable = $false
                    $missingInputs.Add('valuation.costPerDefect')
                }
                else {
                    $grossRaw = $workingDelta * $volume * $costPerDefect * $attributionShare * $periodFactor
                    $formulaText = "$workingDelta * volume($volume) * costPerDefect($costPerDefect) * attr($attributionShare) * period($periodFactor)"
                }
            }
            'speed' {
                $valuePerTimeUnit = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'valuePerTimeUnit') -FieldName "$claimId.valuation.valuePerTimeUnit"
                if ($null -eq $workingDelta -or $workingDelta -le 0) {
                    $monetizable = $false
                    if ($null -eq $workingDelta) { $missingInputs.Add('observation.value') }
                }
                elseif ($null -eq $valuePerTimeUnit -or $valuePerTimeUnit -le 0) {
                    $monetizable = $false
                    $missingInputs.Add('valuation.valuePerTimeUnit')
                    $notes.Add('Cycle-time reduction remains an operational metric unless linked to a verified economic rate (valuePerTimeUnit).')
                }
                else {
                    $grossRaw = $workingDelta * $volume * $valuePerTimeUnit * $attributionShare * $periodFactor
                    $formulaText = "$workingDelta * volume($volume) * valuePerTimeUnit($valuePerTimeUnit) * attr($attributionShare) * period($periodFactor)"
                }
            }
            'risk reduction' {
                $baseL = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'baselineLikelihood') -FieldName "$claimId.valuation.baselineLikelihood"
                $obsL = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'observedLikelihood') -FieldName "$claimId.valuation.observedLikelihood"
                $impactAmount = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'impactAmount') -FieldName "$claimId.valuation.impactAmount"
                $costPerIncident = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'costPerIncident') -FieldName "$claimId.valuation.costPerIncident"
                if ($null -ne $baseL -and $null -ne $obsL -and $null -ne $impactAmount -and $impactAmount -gt 0) {
                    if ($baseL -lt 0 -or $baseL -gt 1 -or $obsL -lt 0 -or $obsL -gt 1) {
                        throw (Get-SquadBenefitValuationStop "Claim '$claimId' likelihood values must be in [0, 1].")
                    }
                    $probDelta = $baseL - $obsL
                    if ($probDelta -le 0) {
                        $monetizable = $false
                    }
                    else {
                        $grossRaw = $probDelta * $impactAmount * $attributionShare * $periodFactor
                        $formulaText = "(baselineLikelihood($baseL) - observedLikelihood($obsL)) * impactAmount($impactAmount) * attr($attributionShare) * period($periodFactor)"
                    }
                }
                elseif ($null -ne $workingDelta -and $workingDelta -gt 0 -and $null -ne $costPerIncident -and $costPerIncident -gt 0) {
                    $grossRaw = $workingDelta * $volume * $costPerIncident * $attributionShare * $periodFactor
                    $formulaText = "$workingDelta * volume($volume) * costPerIncident($costPerIncident) * attr($attributionShare) * period($periodFactor)"
                }
                else {
                    $monetizable = $false
                    $missingInputs.Add('valuation.baselineLikelihood/observedLikelihood/impactAmount or valuation.costPerIncident')
                }
            }
            'new capacity' {
                $demandVerified = Get-BvProp -Object $valuation -Name 'demandVerified'
                $unitValue = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'unitValue') -FieldName "$claimId.valuation.unitValue"
                if ($demandVerified -eq $false) {
                    $monetizable = $false
                    $gaps.Add('New capacity is not verified against real demand (demandVerified=false).')
                }
                elseif ($null -eq $workingDelta -or $workingDelta -le 0) {
                    $monetizable = $false
                    if ($null -eq $workingDelta) { $missingInputs.Add('observation.value') }
                }
                elseif ($null -eq $unitValue -or $unitValue -le 0) {
                    $monetizable = $false
                    $missingInputs.Add('valuation.unitValue')
                }
                else {
                    $grossRaw = $workingDelta * $volume * $unitValue * $attributionShare * $periodFactor
                    $formulaText = "$workingDelta * volume($volume) * unitValue($unitValue) * attr($attributionShare) * period($periodFactor)"
                }
            }
            'engagement' {
                $downRate = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'downstreamConversionRate') -FieldName "$claimId.valuation.downstreamConversionRate"
                $downValue = ConvertTo-BvDecimal -Value (Get-BvProp -Object $valuation -Name 'downstreamUnitValue') -FieldName "$claimId.valuation.downstreamUnitValue"
                if ($null -eq $workingDelta -or $workingDelta -le 0) {
                    $monetizable = $false
                    if ($null -eq $workingDelta) { $missingInputs.Add('observation.value') }
                }
                elseif ($null -eq $downRate -or $downRate -le 0 -or $null -eq $downValue -or $downValue -le 0) {
                    $monetizable = $false
                    $missingInputs.Add('valuation.downstreamConversionRate and valuation.downstreamUnitValue')
                    $notes.Add('Engagement is a leading indicator; financial value requires a tested link (downstreamConversionRate and downstreamUnitValue).')
                }
                else {
                    if ($downRate -gt 1) {
                        throw (Get-SquadBenefitValuationStop "Claim '$claimId' downstreamConversionRate must be in (0, 1].")
                    }
                    $grossRaw = $workingDelta * $volume * $downRate * $downValue * $attributionShare * $periodFactor
                    $formulaText = "$workingDelta * volume($volume) * downstreamConv($downRate) * downstreamUnitValue($downValue) * attr($attributionShare) * period($periodFactor)"
                }
            }
        }
    }

    $grossConverted = $null
    $fxNote = $null
    if ($monetizable -and $null -ne $grossRaw) {
        $fx = ConvertTo-BvCurrencyAmount -Amount $grossRaw -SourceCurrency $valCurrency -TargetCurrency $ReportCurrency -FxRates $FxRates
        if (-not $fx.Converted) {
            $monetizable = $false
            $gaps.Add($fx.Note)
            $missingInputs.Add("fxRates.$($valCurrency.Trim().ToUpperInvariant())")
        }
        else {
            $grossConverted = $fx.Amount
            if ($fx.Note) {
                $fxNote = $fx.Note
                $notes.Add($fx.Note)
            }
        }
    }

    $monetaryBasis = if (-not $monetizable -or $null -eq $grossConverted) {
        'unmonetized-native-only'
    }
    elseif ($useForecast -or $evidenceStatus -eq 'pending') {
        'modeled-counterfactual'
    }
    elseif ($financeApprovedFlag -and $decisionStatus.ToLowerInvariant() -eq 'approved' -and -not [string]::IsNullOrWhiteSpace($decisionRef)) {
        'finance-approved'
    }
    else {
        'stated-indicative'
    }

    $effectiveUncertainty = if ($null -ne $uncertaintyPct) {
        $uncertaintyPct
    }
    elseif ($monetaryBasis -eq 'finance-approved') {
        [decimal]10
    }
    elseif ($monetaryBasis -eq 'stated-indicative') {
        [decimal]25
    }
    elseif ($monetaryBasis -eq 'modeled-counterfactual') {
        [decimal]35
    }
    else {
        $null
    }

    return [pscustomobject]@{
        claimId                = $claimId
        category               = $category
        hypothesis             = $hypothesis
        beneficiary            = $beneficiary
        measurementOwner       = $measurementOwner
        decisionOwner          = $decisionOwner
        decisionStatus         = $decisionStatus
        decisionReference      = $decisionRef
        evidenceStatus         = $evidenceStatus
        evidenceLinks          = $evidenceLinks
        nativeUnit             = $(if (-not [string]::IsNullOrWhiteSpace($obsUnit)) { $obsUnit.Trim() } elseif (-not [string]::IsNullOrWhiteSpace($baseUnit)) { $baseUnit.Trim() } else { $null })
        baselineValue          = $(if ($null -ne $baseVal) { [double][Math]::Round($baseVal, 4) } else { $null })
        targetValue            = $(if ($null -ne $targVal) { [double][Math]::Round($targVal, 4) } else { $null })
        observedValue          = $(if ($null -ne $obsVal) { [double][Math]::Round($obsVal, 4) } else { $null })
        nativeDelta            = $(if ($null -ne $nativeDelta) { [double][Math]::Round($nativeDelta, 4) } else { $null })
        monetaryBasis          = $monetaryBasis
        currency               = $ReportCurrency
        Formula                = $formulaText
        GrossDecimal           = $grossConverted
        OverlapGroup           = $(if ([string]::IsNullOrWhiteSpace($overlapGroup)) { $null } else { $overlapGroup.Trim() })
        PrimaryInGroup         = $primaryInGroup
        OverlapShare           = $overlapShare
        UncertaintyPct         = $effectiveUncertainty
        FxNote                 = $fxNote
        MissingValuationInputs = @($missingInputs | Select-Object -Unique)
        Gaps                   = @($gaps | Select-Object -Unique)
        Notes                  = @($notes | Select-Object -Unique)
    }
}

function Get-SquadBenefitValuation {
    <#
    .SYNOPSIS
        Computes the deterministic FinOps stated monetary valuation model across benefit claims, cost evidence, and HVE Squad ledgers.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputDocument,

        [string]$SquadRoot,

        [string]$AsOf
    )
    $asOfText = if (-not [string]::IsNullOrWhiteSpace($AsOf)) {
        $AsOf.Trim()
    }
    elseif ($null -ne (Get-BvProp -Object $InputDocument -Name 'as_of')) {
        [string](Get-BvProp -Object $InputDocument -Name 'as_of')
    }
    elseif ($null -ne (Get-BvProp -Object $InputDocument -Name 'asOf')) {
        [string](Get-BvProp -Object $InputDocument -Name 'asOf')
    }
    else {
        [DateTimeOffset]::UtcNow.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    }

    $reportId = [string](Get-BvProp -Object $InputDocument -Name 'report_id')
    if ([string]::IsNullOrWhiteSpace($reportId)) {
        $reportId = [string](Get-BvProp -Object $InputDocument -Name 'reportId')
    }
    if ([string]::IsNullOrWhiteSpace($reportId)) {
        $reportId = "finops-valuation-$asOfText"
    }

    $currencyRaw = [string](Get-BvProp -Object $InputDocument -Name 'currency')
    $currency = if ([string]::IsNullOrWhiteSpace($currencyRaw)) { 'USD' } else { $currencyRaw.Trim().ToUpperInvariant() }
    if ($currency -notmatch '^[A-Z]{3}$') {
        throw (Get-SquadBenefitValuationStop "Currency '$currency' must be a 3-letter ISO currency code (for example, USD or EUR).")
    }
    $fxRates = Get-BvProp -Object $InputDocument -Name 'fx_rates'
    if ($null -eq $fxRates) {
        $fxRates = Get-BvProp -Object $InputDocument -Name 'fxRates'
    }

    $ledgerData = $null
    if (-not [string]::IsNullOrWhiteSpace($SquadRoot)) {
        $ledgerData = Get-BvSquadLedgerSummary -SquadRoot $SquadRoot
    }

    $rawClaimsList = [Collections.Generic.List[object]]::new()
    $suppliedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $docClaims = Get-BvProp -Object $InputDocument -Name 'benefit_claims'
    if ($null -eq $docClaims) {
        $docClaims = Get-BvProp -Object $InputDocument -Name 'claims'
    }
    if ($null -ne $docClaims) {
        foreach ($c in @($docClaims)) {
            if ($null -eq $c) { continue }
            $cid = [string](Get-BvProp -Object $c -Name 'claim_id')
            if ([string]::IsNullOrWhiteSpace($cid)) {
                $cid = [string](Get-BvProp -Object $c -Name 'claimId')
            }
            if (-not [string]::IsNullOrWhiteSpace($cid) -and -not $suppliedIds.Add($cid)) {
                throw (Get-SquadBenefitValuationStop "Duplicate claim_id '$cid' in input claims.")
            }
            $rawClaimsList.Add($c)
        }
    }

    if ($null -ne $ledgerData) {
        foreach ($dc in $ledgerData.DecisionClaims) {
            if ($suppliedIds.Add($dc.claim_id)) {
                $rawClaimsList.Add($dc)
            }
        }
    }

    $evaluatedClaims = @(
        foreach ($c in $rawClaimsList) {
            Measure-BvSingleClaim -Claim $c -ReportCurrency $currency -FxRates $fxRates
        }
    )

    # Deduplicate overlapping evidenced claims within the same overlapGroup.
    $overlapAdjustments = [Collections.Generic.List[object]]::new()
    $deductionByClaim = @{}
    foreach ($ec in $evaluatedClaims) {
        $deductionByClaim[$ec.claimId] = [decimal]0
    }

    $evidencedGroups = @(
        $evaluatedClaims |
            Where-Object { $null -ne $_.OverlapGroup -and $_.monetaryBasis -in @('finance-approved', 'stated-indicative') -and $null -ne $_.GrossDecimal } |
            Group-Object -Property OverlapGroup
    )
    foreach ($grp in $evidencedGroups) {
        if ($grp.Count -le 1) {
            continue
        }
        $ordered = @(
            $grp.Group | Sort-Object -Property @(
                @{ Expression = { if ($_.PrimaryInGroup) { 0 } else { 1 } }; Ascending = $true }
                @{ Expression = { if ($_.monetaryBasis -eq 'finance-approved') { 0 } else { 1 } }; Ascending = $true }
                @{ Expression = { $_.GrossDecimal }; Descending = $true }
                @{ Expression = { $_.claimId }; Ascending = $true }
            )
        )
        $primary = $ordered[0]
        for ($idx = 1; $idx -lt $ordered.Count; $idx++) {
            $secondary = $ordered[$idx]
            $deduction = $secondary.GrossDecimal * $secondary.OverlapShare
            $deductionByClaim[$secondary.claimId] = $deduction
            $overlapAdjustments.Add([ordered]@{
                    overlapGroup     = $grp.Name
                    retainedClaimId  = $primary.claimId
                    adjustedClaimId  = $secondary.claimId
                    overlapShare     = [double][Math]::Round($secondary.OverlapShare, 4)
                    deductedAmount   = [double][Math]::Round($deduction, 2)
                    currency         = $currency
                    reason           = "Deducted overlapping pool '$($grp.Name)' already counted in primary claim '$($primary.claimId)'."
                })
        }
    }

    # Evaluate HVE Squad delivery economics and optional engineering-labor valuation.
    $squadDelivery = $null
    $squadLaborFinanceApproved = [decimal]0
    $squadLaborIndicative = [decimal]0
    $squadCounterfactualSavings = [decimal]0
    $hasSquadCounterfactual = $false
    $squadAiSpendInReportCurrency = $null
    $crossCuttingGaps = [Collections.Generic.List[string]]::new()
    $missingGlobalInputs = [Collections.Generic.List[string]]::new()

    if ($null -ne $ledgerData) {
        $econ = $ledgerData.Economics
        $aiUsd = if ($null -ne $econ.Spend -and $null -ne $econ.Spend.Usd) { [decimal]$econ.Spend.Usd } else { $null }
        $aiCredits = if ($null -ne $econ.Spend -and $null -ne $econ.Spend.Credits) { [decimal]$econ.Spend.Credits } else { $null }
        $aiBasis = if ($null -ne $econ.Spend) { [string]$econ.Spend.Basis } else { 'unavailable' }

        if ($null -ne $aiUsd) {
            $aiFx = ConvertTo-BvCurrencyAmount -Amount $aiUsd -SourceCurrency 'USD' -TargetCurrency $currency -FxRates $fxRates
            if ($aiFx.Converted) {
                $squadAiSpendInReportCurrency = $aiFx.Amount
            }
            else {
                $crossCuttingGaps.Add($aiFx.Note)
                $missingGlobalInputs.Add('fxRates.USD')
            }
        }

        $cfSavingsReport = $null
        $cfBaselineReport = $null
        if ($null -ne $econ.Rollup -and $null -ne $econ.Rollup.SavingsUsd) {
            $cfFx = ConvertTo-BvCurrencyAmount -Amount ([decimal]$econ.Rollup.SavingsUsd) -SourceCurrency 'USD' -TargetCurrency $currency -FxRates $fxRates
            $baseFx = ConvertTo-BvCurrencyAmount -Amount ([decimal]$econ.Rollup.BaselineUsd) -SourceCurrency 'USD' -TargetCurrency $currency -FxRates $fxRates
            if ($cfFx.Converted -and $baseFx.Converted) {
                $cfSavingsReport = $cfFx.Amount
                $cfBaselineReport = $baseFx.Amount
                $squadCounterfactualSavings = $cfFx.Amount
                $hasSquadCounterfactual = $true
            }
        }

        $acceptedCount = if ($null -ne $econ.Value -and $null -ne $econ.Value.Accepted) { [decimal]$econ.Value.Accepted } else { $null }
        $producedCount = if ($null -ne $econ.Value -and $null -ne $econ.Value.Produced) { [decimal]$econ.Value.Produced } else { $null }
        $fpyPct = if ($null -ne $econ.Value -and $null -ne $econ.Value.FirstPassYieldPct) { [decimal]$econ.Value.FirstPassYieldPct } else { $null }
        $costPerAcceptedReport = $null
        if ($null -ne $econ.Value -and $null -ne $econ.Value.CostPerAcceptedUsd) {
            $cpaFx = ConvertTo-BvCurrencyAmount -Amount ([decimal]$econ.Value.CostPerAcceptedUsd) -SourceCurrency 'USD' -TargetCurrency $currency -FxRates $fxRates
            if ($cpaFx.Converted) {
                $costPerAcceptedReport = $cpaFx.Amount
            }
        }

        $delivVal = Get-BvProp -Object $InputDocument -Name 'delivery_valuation'
        if ($null -eq $delivVal) {
            $delivVal = Get-BvProp -Object $InputDocument -Name 'deliveryValuation'
        }
        $laborValueDecimal = $null
        $laborBasis = 'unmonetized-native-only'
        $laborFormula = $null
        $laborMissing = [Collections.Generic.List[string]]::new()

        if ($null -ne $delivVal) {
            $dHourly = ConvertTo-BvDecimal -Value (Get-BvProp -Object $delivVal -Name 'hourlyRate') -FieldName 'deliveryValuation.hourlyRate'
            $dRedeployed = ConvertTo-BvDecimal -Value (Get-BvProp -Object $delivVal -Name 'redeployedShare') -FieldName 'deliveryValuation.redeployedShare'
            $dHoursSaved = ConvertTo-BvDecimal -Value (Get-BvProp -Object $delivVal -Name 'hoursSavedPerAcceptedDeliverable') -FieldName 'deliveryValuation.hoursSavedPerAcceptedDeliverable'
            if ($null -eq $dHoursSaved) {
                $dBaseHrs = ConvertTo-BvDecimal -Value (Get-BvProp -Object $delivVal -Name 'baselineHoursPerDeliverable') -FieldName 'deliveryValuation.baselineHoursPerDeliverable'
                $dObsHrs = ConvertTo-BvDecimal -Value (Get-BvProp -Object $delivVal -Name 'observedHoursPerDeliverable') -FieldName 'deliveryValuation.observedHoursPerDeliverable'
                if ($null -ne $dBaseHrs -and $null -ne $dObsHrs) {
                    $dHoursSaved = $dBaseHrs - $dObsHrs
                }
            }
            $dAttr = ConvertTo-BvDecimal -Value (Get-BvProp -Object $delivVal -Name 'attributionShare') -FieldName 'deliveryValuation.attributionShare'
            if ($null -eq $dAttr) {
                $dAttr = [decimal]1
            }
            $dCurr = [string](Get-BvProp -Object $delivVal -Name 'currency')
            if ([string]::IsNullOrWhiteSpace($dCurr)) {
                $dCurr = $currency
            }
            $dFinApproved = (Get-BvProp -Object $delivVal -Name 'financeApproved') -eq $true
            $dDecisionRef = [string](Get-BvProp -Object $delivVal -Name 'decisionReference')

            if ($null -eq $acceptedCount -or $acceptedCount -le 0) {
                $laborMissing.Add('acceptedDeliverables > 0 (independent review acceptance required)')
            }
            if ($null -eq $dHoursSaved -or $dHoursSaved -le 0) {
                $laborMissing.Add('deliveryValuation.hoursSavedPerAcceptedDeliverable (or baselineHoursPerDeliverable > observedHoursPerDeliverable)')
            }
            if ($null -eq $dHourly -or $dHourly -le 0) {
                $laborMissing.Add('deliveryValuation.hourlyRate')
            }
            if ($null -eq $dRedeployed -or $dRedeployed -le 0) {
                $laborMissing.Add('deliveryValuation.redeployedShare')
            }
            elseif ($dRedeployed -gt 1) {
                throw (Get-SquadBenefitValuationStop 'deliveryValuation.redeployedShare must be in (0, 1].')
            }
            if ($dAttr -le 0 -or $dAttr -gt 1) {
                throw (Get-SquadBenefitValuationStop 'deliveryValuation.attributionShare must be in (0, 1].')
            }

            if ($laborMissing.Count -eq 0) {
                $rawLabor = $acceptedCount * $dHoursSaved * $dRedeployed * $dHourly * $dAttr
                $lFx = ConvertTo-BvCurrencyAmount -Amount $rawLabor -SourceCurrency $dCurr -TargetCurrency $currency -FxRates $fxRates
                if ($lFx.Converted) {
                    $laborValueDecimal = $lFx.Amount
                    $laborBasis = if ($dFinApproved -and -not [string]::IsNullOrWhiteSpace($dDecisionRef)) { 'finance-approved' } else { 'stated-indicative' }
                    $laborFormula = "accepted($acceptedCount) * hoursSaved($dHoursSaved) * redeployed($dRedeployed) * hourlyRate($dHourly) * attr($dAttr)"
                    if ($laborBasis -eq 'finance-approved') {
                        $squadLaborFinanceApproved = $laborValueDecimal
                    }
                    else {
                        $squadLaborIndicative = $laborValueDecimal
                    }
                }
                else {
                    $crossCuttingGaps.Add($lFx.Note)
                    $laborMissing.Add("fxRates.$($dCurr.Trim().ToUpperInvariant())")
                }
            }
        }
        else {
            $laborMissing.Add('deliveryValuation (optional: supply hourlyRate, hoursSavedPerAcceptedDeliverable, and redeployedShare to monetize engineering time)')
        }

        $squadDelivery = [ordered]@{
            squadRoot                     = $ledgerData.SquadRoot
            unitsCovered                  = $ledgerData.UnitCount
            currency                      = $currency
            aiSpend                       = $(if ($null -ne $squadAiSpendInReportCurrency) { [double][Math]::Round($squadAiSpendInReportCurrency, 4) } else { $null })
            aiSpendUsd                    = $(if ($null -ne $aiUsd) { [double][Math]::Round($aiUsd, 4) } else { $null })
            aiSpendCredits                = $(if ($null -ne $aiCredits) { [double][Math]::Round($aiCredits, 2) } else { $null })
            aiSpendBasis                  = $aiBasis
            deliverablesProduced          = $(if ($null -ne $producedCount) { [int]$producedCount } else { $null })
            acceptedDeliverables          = $(if ($null -ne $acceptedCount) { [int]$acceptedCount } else { $null })
            firstPassYieldPct             = $(if ($null -ne $fpyPct) { [double][Math]::Round($fpyPct, 1) } else { $null })
            costPerAcceptedDeliverable    = $(if ($null -ne $costPerAcceptedReport) { [double][Math]::Round($costPerAcceptedReport, 4) } else { $null })
            counterfactualBaselineCost    = $(if ($null -ne $cfBaselineReport) { [double][Math]::Round($cfBaselineReport, 4) } else { $null })
            counterfactualAiSavings       = $(if ($null -ne $cfSavingsReport) { [double][Math]::Round($cfSavingsReport, 4) } else { $null })
            counterfactualBasis           = $(if ($null -ne $cfSavingsReport) { 'modeled-counterfactual' } else { 'unavailable' })
            statedDeliveryLaborValue      = $(if ($null -ne $laborValueDecimal) { [double][Math]::Round($laborValueDecimal, 2) } else { $null })
            statedDeliveryLaborBasis      = $laborBasis
            statedDeliveryLaborFormula    = $laborFormula
            missingLaborValuationInputs   = @($laborMissing)
        }
    }

    # Build final claim rows and sum separated basis buckets.
    $financeApprovedSum = $squadLaborFinanceApproved
    $statedIndicativeSum = $squadLaborIndicative
    $modeledCounterfactualSum = if ($hasSquadCounterfactual) { $squadCounterfactualSavings } else { [decimal]0 }
    $hasAnyCounterfactual = $hasSquadCounterfactual
    $lowBandSum = ($squadLaborFinanceApproved * [decimal]0.90) + ($squadLaborIndicative * [decimal]0.75)
    $highBandSum = ($squadLaborFinanceApproved * [decimal]1.10) + ($squadLaborIndicative * [decimal]1.25)

    $claimOutputs = [Collections.Generic.List[object]]::new()
    foreach ($ec in $evaluatedClaims) {
        $deduct = [decimal]$deductionByClaim[$ec.claimId]
        $netDec = if ($null -ne $ec.GrossDecimal) { [Math]::Max([decimal]0, ($ec.GrossDecimal - $deduct)) } else { $null }

        if ($ec.monetaryBasis -eq 'finance-approved' -and $null -ne $netDec) {
            $financeApprovedSum += $netDec
            $bandFrac = ($ec.UncertaintyPct / [decimal]100)
            $lowBandSum += $netDec * ([decimal]1 - $bandFrac)
            $highBandSum += $netDec * ([decimal]1 + $bandFrac)
        }
        elseif ($ec.monetaryBasis -eq 'stated-indicative' -and $null -ne $netDec) {
            $statedIndicativeSum += $netDec
            $bandFrac = ($ec.UncertaintyPct / [decimal]100)
            $lowBandSum += $netDec * ([decimal]1 - $bandFrac)
            $highBandSum += $netDec * ([decimal]1 + $bandFrac)
        }
        elseif ($ec.monetaryBasis -eq 'modeled-counterfactual' -and $null -ne $netDec) {
            $modeledCounterfactualSum += $netDec
            $hasAnyCounterfactual = $true
        }

        foreach ($m in $ec.MissingValuationInputs) {
            $missingGlobalInputs.Add("$($ec.claimId): $m")
        }
        foreach ($g in $ec.Gaps) {
            $crossCuttingGaps.Add("$($ec.claimId): $g")
        }

        $claimOutputs.Add([ordered]@{
                claimId                = $ec.claimId
                category               = $ec.category
                hypothesis             = $ec.hypothesis
                beneficiary            = $ec.beneficiary
                measurementOwner       = $ec.measurementOwner
                decisionOwner          = $ec.decisionOwner
                decisionStatus         = $ec.decisionStatus
                decisionReference      = $ec.decisionReference
                evidenceStatus         = $ec.evidenceStatus
                evidenceLinks          = $ec.evidenceLinks
                nativeUnit             = $ec.nativeUnit
                baselineValue          = $ec.baselineValue
                targetValue            = $ec.targetValue
                observedValue          = $ec.observedValue
                nativeDelta            = $ec.nativeDelta
                monetaryBasis          = $ec.monetaryBasis
                currency               = $ec.currency
                formula                = $ec.Formula
                grossMonetaryValue     = $(if ($null -ne $ec.GrossDecimal) { [double][Math]::Round($ec.GrossDecimal, 2) } else { $null })
                overlapDeduction       = $(if ($deduct -gt 0) { [double][Math]::Round($deduct, 2) } else { 0.0 })
                statedMonetaryValue    = $(if ($null -ne $netDec -and $ec.monetaryBasis -in @('finance-approved', 'stated-indicative')) { [double][Math]::Round($netDec, 2) } else { $null })
                modeledMonetaryValue   = $(if ($null -ne $netDec -and $ec.monetaryBasis -eq 'modeled-counterfactual') { [double][Math]::Round($netDec, 2) } else { $null })
                uncertaintyPct         = $(if ($null -ne $ec.UncertaintyPct) { [double][Math]::Round($ec.UncertaintyPct, 1) } else { $null })
                overlapGroup           = $ec.OverlapGroup
                missingValuationInputs = $ec.MissingValuationInputs
                gaps                   = $ec.Gaps
                notes                  = $ec.Notes
            })
    }

    # Evaluate Cost Evidence and reconcile with Squad AI spend.
    $rawCosts = Get-BvProp -Object $InputDocument -Name 'cost_evidence'
    if ($null -eq $rawCosts) {
        $rawCosts = Get-BvProp -Object $InputDocument -Name 'costEvidence'
    }
    $costOutputs = [Collections.Generic.List[object]]::new()
    $costSum = [decimal]0
    $hasAnyCost = $false
    $explicitSquadSpendIncluded = $false

    if ($null -ne $rawCosts) {
        foreach ($ce in @($rawCosts)) {
            if ($null -eq $ce) { continue }
            $scope = [string](Get-BvProp -Object $ce -Name 'scope')
            $amt = ConvertTo-BvDecimal -Value (Get-BvProp -Object $ce -Name 'amount') -FieldName "costEvidence($scope).amount"
            $cCurr = [string](Get-BvProp -Object $ce -Name 'currency')
            if ([string]::IsNullOrWhiteSpace($cCurr)) {
                $cCurr = $currency
            }
            $period = [string](Get-BvProp -Object $ce -Name 'period')
            $source = [string](Get-BvProp -Object $ce -Name 'source')
            $link = [string](Get-BvProp -Object $ce -Name 'evidence_link')
            if ([string]::IsNullOrWhiteSpace($link)) {
                $link = [string](Get-BvProp -Object $ce -Name 'evidenceLink')
            }

            $cGaps = [Collections.Generic.List[string]]::new()
            if ([string]::IsNullOrWhiteSpace($scope)) { $cGaps.Add('Missing cost scope.') }
            if ($null -eq $amt -or $amt -lt 0) { $cGaps.Add('Missing or negative cost amount.') }
            if ([string]::IsNullOrWhiteSpace($period)) { $cGaps.Add('Missing cost period.') }
            if ([string]::IsNullOrWhiteSpace($source)) { $cGaps.Add('Missing cost source.') }
            if ([string]::IsNullOrWhiteSpace($link)) { $cGaps.Add('Missing cost evidence_link.') }

            $convertedAmt = $null
            if ($null -ne $amt -and $amt -ge 0) {
                $cFx = ConvertTo-BvCurrencyAmount -Amount $amt -SourceCurrency $cCurr -TargetCurrency $currency -FxRates $fxRates
                if ($cFx.Converted) {
                    $convertedAmt = $cFx.Amount
                    $costSum += $convertedAmt
                    $hasAnyCost = $true
                }
                else {
                    $cGaps.Add($cFx.Note)
                }
            }
            if ($scope -match '(?i)hve-squad-ai-spend|squad-ai-spend') {
                $explicitSquadSpendIncluded = $true
            }
            foreach ($cg in $cGaps) {
                $crossCuttingGaps.Add("cost($scope): $cg")
            }
            $costOutputs.Add([ordered]@{
                    scope           = $scope
                    originalAmount  = $(if ($null -ne $amt) { [double][Math]::Round($amt, 4) } else { $null })
                    originalCurrency = $cCurr.Trim().ToUpperInvariant()
                    convertedAmount = $(if ($null -ne $convertedAmt) { [double][Math]::Round($convertedAmt, 4) } else { $null })
                    currency        = $currency
                    period          = $period
                    source          = $source
                    evidenceLink    = $link
                    gaps            = @($cGaps)
                })
        }
    }

    $includeSquadCostProp = Get-BvProp -Object $InputDocument -Name 'includeSquadAiSpendInCost'
    $includeSquadCost = if ($null -ne $includeSquadCostProp) { [bool]$includeSquadCostProp } else { $true }
    if ($includeSquadCost -and -not $explicitSquadSpendIncluded -and $null -ne $squadAiSpendInReportCurrency) {
        $costSum += $squadAiSpendInReportCurrency
        $hasAnyCost = $true
        $costOutputs.Add([ordered]@{
                scope            = 'hve-squad-ai-spend'
                originalAmount   = [double][Math]::Round([decimal]$ledgerData.Economics.Spend.Usd, 4)
                originalCurrency = 'USD'
                convertedAmount  = [double][Math]::Round($squadAiSpendInReportCurrency, 4)
                currency         = $currency
                period           = 'cumulative-run'
                source           = "consumption.md ($($squadDelivery.aiSpendBasis))"
                evidenceLink     = 'consumption.md'
                gaps             = @()
            })
    }

    $evidencedMonetizedCount = @(
        $evaluatedClaims | Where-Object { $_.monetaryBasis -in @('finance-approved', 'stated-indicative') }
    ).Count
    $hasEvidencedLabor = ($squadLaborFinanceApproved -gt 0 -or $squadLaborIndicative -gt 0)
    $hasEvidencedValue = ($evidencedMonetizedCount -gt 0 -or $hasEvidencedLabor)

    $totalEvidenced = if ($hasEvidencedValue) { $financeApprovedSum + $statedIndicativeSum } else { $null }
    $netStated = if ($null -ne $totalEvidenced -and $hasAnyCost) { $totalEvidenced - $costSum } else { $null }
    $roiPct = if ($null -ne $netStated -and $costSum -gt 0) { ($netStated / $costSum) * [decimal]100 } else { $null }
    $bcr = if ($null -ne $totalEvidenced -and $costSum -gt 0) { $totalEvidenced / $costSum } else { $null }

    $overallBasis = if (-not $hasEvidencedValue) {
        'unmonetized-native-only'
    }
    elseif ($statedIndicativeSum -eq 0 -and $financeApprovedSum -gt 0) {
        'finance-approved'
    }
    elseif ($financeApprovedSum -eq 0) {
        'stated-indicative'
    }
    else {
        'mixed-evidenced (finance-approved + stated-indicative)'
    }

    $summary = [ordered]@{
        currency                       = $currency
        overallBasis                   = $overallBasis
        financeApprovedValue           = $(if ($hasEvidencedValue) { [double][Math]::Round($financeApprovedSum, 2) } else { $null })
        statedIndicativeValue          = $(if ($hasEvidencedValue) { [double][Math]::Round($statedIndicativeSum, 2) } else { $null })
        totalStatedEvidencedValue      = $(if ($null -ne $totalEvidenced) { [double][Math]::Round($totalEvidenced, 2) } else { $null })
        sensitivityRange               = $(if ($null -ne $totalEvidenced) {
                [ordered]@{
                    low    = [double][Math]::Round($lowBandSum, 2)
                    stated = [double][Math]::Round($totalEvidenced, 2)
                    high   = [double][Math]::Round($highBandSum, 2)
                }
            }
            else {
                $null
            })
        totalEvidencedCost             = $(if ($hasAnyCost) { [double][Math]::Round($costSum, 4) } else { $null })
        netStatedValue                 = $(if ($null -ne $netStated) { [double][Math]::Round($netStated, 2) } else { $null })
        benefitCostRatio               = $(if ($null -ne $bcr) { [double][Math]::Round($bcr, 2) } else { $null })
        statedRoiPct                   = $(if ($null -ne $roiPct) { [double][Math]::Round($roiPct, 1) } else { $null })
        modeledCounterfactualValue     = $(if ($hasAnyCounterfactual) { [double][Math]::Round($modeledCounterfactualSum, 2) } else { $null })
        claimsTotal                    = $evaluatedClaims.Count
        claimsMonetizedEvidenced       = $evidencedMonetizedCount
        claimsModeledCounterfactual    = @($evaluatedClaims | Where-Object { $_.monetaryBasis -eq 'modeled-counterfactual' }).Count
        claimsUnmonetizedNativeOnly    = @($evaluatedClaims | Where-Object { $_.monetaryBasis -eq 'unmonetized-native-only' }).Count
        overlapDeductionsTotal         = [double][Math]::Round((($deductionByClaim.Values | Measure-Object -Sum).Sum), 2)
    }

    return [ordered]@{
        schemaVersion          = '1.0'
        reportId               = $reportId
        asOf                   = $asOfText
        currency               = $currency
        autonomyTierForBooking = 'confirm'
        governanceNotice       = 'Stated indicative values reflect supplied evidence and explicit valuation assumptions; Finance-approved booked value requires explicit Finance/business approval and never waives execution, review, or release gates.'
        summary                = $summary
        squadDelivery          = $squadDelivery
        claims                 = $claimOutputs.ToArray()
        costEvidence           = $costOutputs.ToArray()
        overlapAdjustments     = $overlapAdjustments.ToArray()
        missingValuationInputs = @($missingGlobalInputs | Select-Object -Unique)
        gaps                   = @($crossCuttingGaps | Select-Object -Unique)
    }
}

function ConvertTo-SquadBenefitValuationMarkdown {
    <#
    .SYNOPSIS
        Renders a deterministic Markdown Stated Monetary Value Report from Get-SquadBenefitValuation output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Collections.IDictionary]$Model
    )
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $curr = $Model.currency
    $fmtMoney = {
        param($val, [int]$digits = 2)
        if ($null -eq $val) {
            return 'unavailable (not monetized)'
        }
        return "$curr " + ([double]$val).ToString("N$digits", $inv)
    }
    $fmtPct = {
        param($val)
        if ($null -eq $val) {
            return 'unavailable'
        }
        return ([double]$val).ToString('N1', $inv) + '%'
    }

    $s = $Model.summary
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('---')
    $lines.Add("description: `"Stated monetary benefit valuation report ($($Model.reportId))`"")
    $lines.Add('---')
    $lines.Add('')
    $lines.Add("# Stated Monetary Value Report: $($Model.reportId)")
    $lines.Add('')
    $lines.Add("* **As of:** $($Model.asOf)")
    $lines.Add("* **Currency:** $curr")
    $lines.Add("* **Overall Valuation Basis:** ``$($s.overallBasis)``")
    $lines.Add("* **Governance Tier for Financial Commitment / Booking:** ``$($Model.autonomyTierForBooking)``")
    $lines.Add('')
    $lines.Add("## Executive Stated Value Summary")
    $lines.Add('')
    $lines.Add('| Metric | Amount / Value | Basis |')
    $lines.Add('| --- | ---: | --- |')
    $lines.Add("| Finance-Approved (Booked) Value | $(& $fmtMoney $s.financeApprovedValue 2) | ``finance-approved`` |")
    $lines.Add("| Stated Indicative (Evidenced) Value | $(& $fmtMoney $s.statedIndicativeValue 2) | ``stated-indicative`` |")
    $lines.Add("| **Total Stated Evidenced Value** | **$(& $fmtMoney $s.totalStatedEvidencedValue 2)** | ``$($s.overallBasis)`` |")
    if ($null -ne $s.sensitivityRange) {
        $rangeStr = "$(& $fmtMoney $s.sensitivityRange.low 2) to $(& $fmtMoney $s.sensitivityRange.high 2)"
        $lines.Add("| Sensitivity Band (Low to High) | $rangeStr | ``derived`` |")
    }
    $lines.Add("| Total Evidenced Cost | $(& $fmtMoney $s.totalEvidencedCost 4) | ``evidenced-cost`` |")
    $lines.Add("| **Net Stated Value** | **$(& $fmtMoney $s.netStatedValue 2)** | ``derived`` |")
    $bcrStr = if ($null -ne $s.benefitCostRatio) { ([double]$s.benefitCostRatio).ToString('N2', $inv) + 'x' } else { 'unavailable' }
    $lines.Add("| Benefit-Cost Ratio (BCR) | $bcrStr | ``derived`` |")
    $lines.Add("| Stated Return on Investment (ROI) | $(& $fmtPct $s.statedRoiPct) | ``derived`` |")
    $lines.Add("| Modeled Counterfactual / Forecast Value (Separate) | $(& $fmtMoney $s.modeledCounterfactualValue 2) | ``modeled-counterfactual`` (excluded from stated total) |")
    $lines.Add('')
    $lines.Add("> $($Model.governanceNotice)")
    $lines.Add('')

    if ($null -ne $Model.squadDelivery) {
        $sd = $Model.squadDelivery
        $lines.Add('## HVE Squad Delivery & AI Spend Economics')
        $lines.Add('')
        $lines.Add('| Measure | Value | Basis |')
        $lines.Add('| --- | ---: | --- |')
        $lines.Add("| Squad AI Spend | $(& $fmtMoney $sd.aiSpend 4) | ``$($sd.aiSpendBasis)`` |")
        $accStr = if ($null -ne $sd.acceptedDeliverables) { "$($sd.acceptedDeliverables) / $($sd.deliverablesProduced)" } else { 'unavailable' }
        $lines.Add("| Accepted / Produced Deliverables | $accStr | ``derived`` |")
        $lines.Add("| First-Pass Yield | $(& $fmtPct $sd.firstPassYieldPct) | ``derived`` |")
        $lines.Add("| AI Cost per Accepted Deliverable | $(& $fmtMoney $sd.costPerAcceptedDeliverable 4) | ``derived`` |")
        $lines.Add("| Counterfactual Model-Routing Savings | $(& $fmtMoney $sd.counterfactualAiSavings 4) | ``$($sd.counterfactualBasis)`` |")
        $lines.Add("| Stated Engineering Delivery Labor Value | $(& $fmtMoney $sd.statedDeliveryLaborValue 2) | ``$($sd.statedDeliveryLaborBasis)`` |")
        $lines.Add('')
    }

    $lines.Add('## Claim-by-Claim Monetary Valuation Schedule')
    $lines.Add('')
    if ($Model.claims.Count -eq 0) {
        $lines.Add('_No benefit claims were supplied._')
        $lines.Add('')
    }
    else {
        $lines.Add('| Claim ID | Category | Evidence Status | Native Delta | Monetary Basis | Gross | Overlap Ded. | Stated Value |')
        $lines.Add('| --- | --- | --- | --- | --- | ---: | ---: | ---: |')
        foreach ($c in $Model.claims) {
            $deltaStr = if ($null -ne $c.nativeDelta) {
                "$($c.nativeDelta) $($c.nativeUnit)".Trim()
            }
            else {
                'n/a'
            }
            $statedCell = if ($null -ne $c.statedMonetaryValue) {
                & $fmtMoney $c.statedMonetaryValue 2
            }
            elseif ($null -ne $c.modeledMonetaryValue) {
                "$(& $fmtMoney $c.modeledMonetaryValue 2) (modeled)"
            }
            else {
                'native-only'
            }
            $grossCell = if ($null -ne $c.grossMonetaryValue) { & $fmtMoney $c.grossMonetaryValue 2 } else { 'n/a' }
            $dedCell = if ($c.overlapDeduction -gt 0) { & $fmtMoney $c.overlapDeduction 2 } else { "$curr 0.00" }
            $catCell = if ($c.category) { $c.category } else { 'unspecified' }
            $lines.Add("| ``$($c.claimId)`` | $catCell | ``$($c.evidenceStatus)`` | $deltaStr | ``$($c.monetaryBasis)`` | $grossCell | $dedCell | $statedCell |")
        }
        $lines.Add('')
    }

    if ($Model.overlapAdjustments.Count -gt 0) {
        $lines.Add('## Double-Count Deductions')
        $lines.Add('')
        foreach ($adj in $Model.overlapAdjustments) {
            $lines.Add("* **Group ``$($adj.overlapGroup)``:** Deducted $(& $fmtMoney $adj.deductedAmount 2) from ``$($adj.adjustedClaimId)`` ($($adj.reason))")
        }
        $lines.Add('')
    }

    if ($Model.costEvidence.Count -gt 0) {
        $lines.Add('## Cost Evidence')
        $lines.Add('')
        $lines.Add('| Scope | Period | Amount | Source |')
        $lines.Add('| --- | --- | ---: | --- |')
        foreach ($ce in $Model.costEvidence) {
            $lines.Add("| $($ce.scope) | $($ce.period) | $(& $fmtMoney $ce.convertedAmount 4) | $($ce.source) |")
        }
        $lines.Add('')
    }

    if ($Model.missingValuationInputs.Count -gt 0 -or $Model.gaps.Count -gt 0) {
        $lines.Add('## Open Valuation Inputs & Evidence Gaps')
        $lines.Add('')
        foreach ($mi in $Model.missingValuationInputs) {
            $lines.Add("* **Missing valuation input:** $mi")
        }
        foreach ($gp in $Model.gaps) {
            $lines.Add("* **Evidence gap:** $gp")
        }
        $lines.Add('')
    }

    return ($lines -join "`n") + "`n"
}

Export-ModuleMember -Function Get-SquadBenefitValuation, ConvertTo-SquadBenefitValuationMarkdown, Get-SquadBenefitValuationStop
