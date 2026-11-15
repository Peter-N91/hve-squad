#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

# AI cost: none; exercises deterministic FinOps benefit valuation math and specialist contracts locally.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Creates only owned Pester TestDrive fixtures.', Scope = 'Function', Target = 'Write-BvFixtureFile')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Creates only owned Pester TestDrive fixtures.', Scope = 'Function', Target = 'New-BvSquadFixture')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    $script:ScriptsRoot = Join-Path $PackageRoot '.agents/skills/squad/scripts'
    $script:ReferencesRoot = Join-Path $PackageRoot '.agents/skills/squad/references'
    $script:CliPath = Join-Path $script:ScriptsRoot 'Measure-SquadBenefitValue.ps1'
    $script:ModulePath = Join-Path $script:ScriptsRoot 'SquadBenefitValuation.psm1'
    $script:AgentPath = @(
        Get-ChildItem -LiteralPath (Join-Path $PackageRoot '.github/agents') -Recurse -Filter 'squad-value-economist.agent.md' |
            Select-Object -First 1 -ExpandProperty FullName
    )[0]
    Import-Module $script:ModulePath -Force

    function Write-BvFixtureFile {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Text
        )
        $parent = Split-Path -Parent $Path
        if ($parent) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
    }

    function New-BvSquadFixture {
        param(
            [string]$RunId = 'val-run-01',
            [string]$SquadUsd = '0.5000',
            [string]$SquadUnits = '50.00',
            [string]$BaselineUsd = '2.00',
            [int]$Produced = 3,
            [int]$Accepted = 2,
            [string]$Basis = 'exact-native',
            [string[]]$DecisionClaims = @()
        )
        $dir = Join-Path $TestDrive ("bv-squad-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $ledger = @(
            '---'
            'description: "Squad consumption ledger"'
            '---'
            ''
            "# Squad Consumption Ledger (Run: $RunId)"
            ''
            '## Attribution'
            ''
            '| Role | Member | Agent | Model | Model Source | Priced As | Tier |'
            '| --- | --- | --- | --- | --- | --- | --- |'
            '| developer | Alpha | Squad Implementor | claude-sonnet-5.5 | host-reported | native credits | default |'
            '| orchestration | | Squad Coordinator + Squad Scribe | claude-haiku-5.5 | host-reported | native credits | mixed |'
            ''
            '## Usage & Cost'
            ''
            '| Role | Requests | In Tokens | Cached | Cache Wr | Out Tokens | Exact Cost (USD) | Exact Credits | Basis |'
            '| --- | --- | --- | --- | --- | --- | --- | --- | --- |'
            "| developer | 2 | 10,000 | 20,000 | 0 | 2,000 | 0.4000 | 40.00 | $Basis |"
            "| orchestration | 1 | 5,000 | 5,000 | 0 | 500 | 0.1000 | 10.00 | $Basis |"
            "| **Total** | **3** | **15,000** | **25,000** | **0** | **2,500** | **$SquadUsd** | **$SquadUnits** | **$Basis** |"
            ''
            '## Unit Economics (value)'
            ''
            '| Measure | Value | Label |'
            '| --- | --- | --- |'
            "| Deliverables produced | $Produced | derived |"
            "| Accepted by an independent review | $Accepted | derived |"
            '| Rejected | 0 | derived |'
            "| Unreviewed | $($Produced - $Accepted) | derived |"
            '| Dispatches (excluding Scribe) | 2 | derived |'
            '| Rework dispatches | 0 | derived |'
            '| First-pass yield | 100.0% | derived |'
            '| Exact credits per accepted deliverable | 25.00 | measured |'
            '| Orchestration share of exact credits | 20.0% | measured |'
            ''
            '## Cost Comparison'
            ''
            "This run consumed **`$$SquadUsd (~$SquadUnits AI credits)**. Pricing the same non-orchestration traffic on claude-opus-4.6 is a calculated counterfactual of **`$$BaselineUsd** — a saving of **75.0%**."
            ''
        ) -join "`n"
        Write-BvFixtureFile -Path (Join-Path $dir 'consumption.md') -Text $ledger
        if ($DecisionClaims.Count -gt 0) {
            $decText = @('# Decisions', '', '## Decision 2026-11-15T10:00:00Z', '') + $DecisionClaims
            Write-BvFixtureFile -Path (Join-Path $dir 'decisions.md') -Text ($decText -join "`n")
        }
        return $dir
    }

    function Invoke-BvCli {
        param(
            [Parameter(Mandatory)]
            [string[]]$Arguments
        )
        $start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        foreach ($arg in @('-NoProfile', '-NonInteractive', '-File', $script:CliPath) + $Arguments) {
            $start.ArgumentList.Add($arg)
        }
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.UseShellExecute = $false
        $proc = [Diagnostics.Process]::Start($start)
        try {
            $stdout = $proc.StandardOutput.ReadToEndAsync()
            $stderr = $proc.StandardError.ReadToEndAsync()
            $proc.WaitForExit()
            return [pscustomobject]@{
                ExitCode = $proc.ExitCode
                Stdout   = $stdout.GetAwaiter().GetResult()
                Stderr   = $stderr.GetAwaiter().GetResult()
            }
        }
        finally {
            $proc.Dispose()
        }
    }
}

Describe 'VAL-01 Nine-category deterministic FinOps monetary valuation and basis separation' {
    It 'computes exact stated monetary values across all nine FinOps categories and separates finance-approved from stated-indicative' {
        $doc = @{
            report_id = 'val-nine-categories'
            as_of     = '2026-11-15'
            currency  = 'USD'
            benefit_claims = @(
                @{
                    claim_id          = 'c-rev'
                    category          = 'revenue enablement'
                    hypothesis        = 'Improve checkout conversion'
                    beneficiary       = 'Commerce BU'
                    measurement_owner = 'Growth Lead'
                    status            = 'supported'
                    baseline          = @{ value = 100; unit = 'orders' }
                    target            = @{ value = 150; unit = 'orders' }
                    observation       = @{ value = 140; unit = 'orders' }
                    evidence_links    = @('docs/orders.csv')
                    business_decision = @{ status = 'approved'; owner = 'CFO'; reference = 'FIN-01' }
                    valuation         = @{ unitValue = 50; attributionShare = 0.8; financeApproved = $true }
                }
                @{
                    claim_id          = 'c-avoid'
                    category          = 'cost avoidance'
                    hypothesis        = 'Prevent burst GPU over-provisioning'
                    beneficiary       = 'AI Platform'
                    measurement_owner = 'FinOps Lead'
                    status            = 'supported'
                    evidence_links    = @('docs/acm.csv')
                    business_decision = @{ status = 'pending'; owner = 'VP Eng'; reference = '' }
                    valuation         = @{ counterfactualCost = 5000; observedCost = 3200; attributionShare = 1.0 }
                }
                @{
                    claim_id          = 'c-cap'
                    category          = 'capacity gained'
                    hypothesis        = 'Release L2 triage hours'
                    beneficiary       = 'Support Ops'
                    measurement_owner = 'Support Mgr'
                    status            = 'supported'
                    baseline          = @{ value = 0.50; unit = 'hours' }
                    target            = @{ value = 0.25; unit = 'hours' }
                    observation       = @{ value = 0.30; unit = 'hours' }
                    evidence_links    = @('docs/tickets.csv')
                    valuation         = @{ direction = 'decrease'; volume = 1000; hourlyRate = 60; redeployedShare = 0.75; attributionShare = 1.0 }
                }
                @{
                    claim_id          = 'c-lab'
                    category          = 'labour augmentation'
                    hypothesis        = 'Reduce analyst hours per dossier at constant quality'
                    beneficiary       = 'Risk Analysts'
                    measurement_owner = 'Risk Ops'
                    status            = 'supported'
                    baseline          = @{ value = 4.0; unit = 'hours' }
                    target            = @{ value = 2.0; unit = 'hours' }
                    observation       = @{ value = 2.5; unit = 'hours' }
                    evidence_links    = @('docs/dossiers.csv')
                    valuation         = @{ direction = 'decrease'; volume = 100; hourlyRate = 80; redeployedShare = 0.50; attributionShare = 1.0; qualityFloorMet = $true }
                }
                @{
                    claim_id          = 'c-qual'
                    category          = 'quality'
                    hypothesis        = 'Cut escaped billing defects'
                    beneficiary       = 'Billing Ops'
                    measurement_owner = 'QA Lead'
                    status            = 'supported'
                    baseline          = @{ value = 20; unit = 'defects' }
                    target            = @{ value = 5; unit = 'defects' }
                    observation       = @{ value = 8; unit = 'defects' }
                    evidence_links    = @('docs/defects.csv')
                    valuation         = @{ direction = 'decrease'; costPerDefect = 200; attributionShare = 1.0 }
                }
                @{
                    claim_id          = 'c-speed'
                    category          = 'speed'
                    hypothesis        = 'Avoid SLA breach penalties via faster onboarding'
                    beneficiary       = 'Enterprise Onboarding'
                    measurement_owner = 'Delivery Lead'
                    status            = 'supported'
                    baseline          = @{ value = 10; unit = 'days' }
                    target            = @{ value = 6; unit = 'days' }
                    observation       = @{ value = 7; unit = 'days' }
                    evidence_links    = @('docs/onboarding.csv')
                    valuation         = @{ direction = 'decrease'; volume = 10; valuePerTimeUnit = 100; attributionShare = 1.0 }
                }
                @{
                    claim_id          = 'c-risk'
                    category          = 'risk reduction'
                    hypothesis        = 'Lower probability of Sev1 token-leak incident'
                    beneficiary       = 'Security'
                    measurement_owner = 'CISO Office'
                    status            = 'supported'
                    evidence_links    = @('docs/risk-model.md')
                    valuation         = @{ baselineLikelihood = 0.20; observedLikelihood = 0.05; impactAmount = 40000; attributionShare = 0.50 }
                }
                @{
                    claim_id          = 'c-newcap'
                    category          = 'new capacity'
                    hypothesis        = 'Serve multilingual compliance reviews previously declined'
                    beneficiary       = 'EMEA Legal'
                    measurement_owner = 'Legal Ops'
                    status            = 'supported'
                    baseline          = @{ value = 0; unit = 'reviews' }
                    target            = @{ value = 50; unit = 'reviews' }
                    observation       = @{ value = 40; unit = 'reviews' }
                    evidence_links    = @('docs/legal-reviews.csv')
                    valuation         = @{ unitValue = 120; attributionShare = 1.0; demandVerified = $true }
                }
                @{
                    claim_id          = 'c-eng'
                    category          = 'engagement'
                    hypothesis        = 'Active self-service portal adoption driving verified renewals'
                    beneficiary       = 'Customer Success'
                    measurement_owner = 'CS Ops'
                    status            = 'supported'
                    baseline          = @{ value = 200; unit = 'active_users' }
                    target            = @{ value = 500; unit = 'active_users' }
                    observation       = @{ value = 400; unit = 'active_users' }
                    evidence_links    = @('docs/adoption.csv')
                    valuation         = @{ downstreamConversionRate = 0.10; downstreamUnitValue = 150; attributionShare = 1.0 }
                }
            )
            cost_evidence = @(
                @{
                    scope         = 'platform-and-rollout'
                    amount        = 10000
                    currency      = 'USD'
                    period        = '2026-Q4'
                    source        = 'Azure Cost Management'
                    evidence_link = 'docs/cost-q4.csv'
                }
            )
        }

        # Expected math:
        # c-rev (finance-approved): (140 - 100) * 50 * 0.8 = 1,600
        # c-avoid (stated-indicative): (5000 - 3200) * 1.0 = 1,800
        # c-cap (stated-indicative): (0.50 - 0.30) * 1000 * 0.75 * 60 = 9,000
        # c-lab (stated-indicative): (4.0 - 2.5) * 100 * 0.50 * 80 = 6,000
        # c-qual (stated-indicative): (20 - 8) * 200 = 2,400
        # c-speed (stated-indicative): (10 - 7) * 10 * 100 = 3,000
        # c-risk (stated-indicative): (0.20 - 0.05) * 40000 * 0.50 = 3,000
        # c-newcap (stated-indicative): (40 - 0) * 120 = 4,800
        # c-eng (stated-indicative): (400 - 200) * 0.10 * 150 = 3,000
        # financeApprovedValue = 1,600.00
        # statedIndicativeValue = 1,800 + 9,000 + 6,000 + 2,400 + 3,000 + 3,000 + 4,800 + 3,000 = 33,000.00
        # totalStatedEvidencedValue = 34,600.00
        # netStatedValue = 34,600 - 10,000 = 24,600.00; BCR = 3.46; ROI = 246.0%
        $result = Get-SquadBenefitValuation -InputDocument $doc
        $result.summary.financeApprovedValue | Should -Be 1600.00
        $result.summary.statedIndicativeValue | Should -Be 33000.00
        $result.summary.totalStatedEvidencedValue | Should -Be 34600.00
        $result.summary.totalEvidencedCost | Should -Be 10000.00
        $result.summary.netStatedValue | Should -Be 24600.00
        $result.summary.benefitCostRatio | Should -Be 3.46
        $result.summary.statedRoiPct | Should -Be 246.0
        $result.summary.claimsMonetizedEvidenced | Should -Be 9
    }
}

Describe 'VAL-02 FinOps monetization guardrails prevent fabricated dollar conversions' {
    It 'keeps claims in native units when redeployment, quality floor, pipeline conversion, demand verification, or unit consistency is unmet' {
        $doc = @{
            report_id = 'val-guardrails'
            as_of     = '2026-11-15'
            benefit_claims = @(
                @{
                    claim_id          = 'raw-hours-no-redeploy'
                    category          = 'capacity gained'
                    hypothesis        = 'Save hours without redeployment evidence'
                    beneficiary       = 'Team A'
                    measurement_owner = 'Owner A'
                    status            = 'supported'
                    baseline          = @{ value = 10; unit = 'hours' }
                    observation       = @{ value = 4; unit = 'hours' }
                    evidence_links    = @('docs/a.csv')
                    valuation         = @{ direction = 'decrease'; hourlyRate = 100; attributionShare = 1.0 }
                }
                @{
                    claim_id          = 'degraded-quality-labour'
                    category          = 'labour augmentation'
                    hypothesis        = 'Faster completions that broke quality floor'
                    beneficiary       = 'Team B'
                    measurement_owner = 'Owner B'
                    status            = 'supported'
                    baseline          = @{ value = 5; unit = 'hours' }
                    observation       = @{ value = 2; unit = 'hours' }
                    evidence_links    = @('docs/b.csv')
                    valuation         = @{ direction = 'decrease'; hourlyRate = 100; redeployedShare = 0.8; attributionShare = 1.0; qualityFloorMet = $false }
                }
                @{
                    claim_id          = 'pipeline-only-rev'
                    category          = 'revenue enablement'
                    hypothesis        = 'Influenced pipeline without conversion rate'
                    beneficiary       = 'Sales'
                    measurement_owner = 'RevOps'
                    status            = 'supported'
                    baseline          = @{ value = 10; unit = 'deals' }
                    observation       = @{ value = 25; unit = 'deals' }
                    evidence_links    = @('docs/c.csv')
                    valuation         = @{ pipelineOnly = $true; unitValue = 1000; attributionShare = 0.5 }
                }
                @{
                    claim_id          = 'leading-engagement'
                    category          = 'engagement'
                    hypothesis        = 'Higher DAU without downstream conversion link'
                    beneficiary       = 'Portal'
                    measurement_owner = 'PM'
                    status            = 'supported'
                    baseline          = @{ value = 100; unit = 'users' }
                    observation       = @{ value = 300; unit = 'users' }
                    evidence_links    = @('docs/d.csv')
                    valuation         = @{ attributionShare = 1.0 }
                }
                @{
                    claim_id          = 'unit-mismatch'
                    category          = 'speed'
                    hypothesis        = 'Mismatched baseline and observation units'
                    beneficiary       = 'Ops'
                    measurement_owner = 'Lead'
                    status            = 'supported'
                    baseline          = @{ value = 2; unit = 'hours' }
                    observation       = @{ value = 45; unit = 'minutes' }
                    evidence_links    = @('docs/e.csv')
                    valuation         = @{ direction = 'decrease'; valuePerTimeUnit = 50; attributionShare = 1.0 }
                }
            )
        }

        $result = Get-SquadBenefitValuation -InputDocument $doc
        $result.summary.overallBasis | Should -Be 'unmonetized-native-only'
        $result.summary.totalStatedEvidencedValue | Should -BeNullOrEmpty
        $result.summary.claimsUnmonetizedNativeOnly | Should -Be 5
        foreach ($claim in $result.claims) {
            $claim.monetaryBasis | Should -Be 'unmonetized-native-only'
            $claim.statedMonetaryValue | Should -BeNullOrEmpty
        }
        ($result.claims | Where-Object claimId -EQ 'raw-hours-no-redeploy').nativeDelta | Should -Be 6
        ($result.claims | Where-Object claimId -EQ 'degraded-quality-labour').gaps -join ' ' | Should -Match 'Quality floor'
        ($result.claims | Where-Object claimId -EQ 'unit-mismatch').gaps -join ' ' | Should -Match 'Unit mismatch'
    }
}

Describe 'VAL-03 Double-count deduplication and VAL-04 counterfactual isolation' {
    It 'deducts overlapping claim pools within an overlap_group and keeps pending/counterfactual figures out of stated totals' {
        $squadDir = New-BvSquadFixture -SquadUsd '0.5000' -SquadUnits '50.00' -BaselineUsd '2.50' -Accepted 2
        $doc = @{
            report_id = 'val-overlap-and-cf'
            as_of     = '2026-11-15'
            benefit_claims = @(
                @{
                    claim_id          = 'cap-primary'
                    category          = 'capacity gained'
                    hypothesis        = 'Ticket triage capacity freed'
                    beneficiary       = 'Desk'
                    measurement_owner = 'Ops'
                    status            = 'supported'
                    overlap_group     = 'triage-pool'
                    baseline          = @{ value = 1.0; unit = 'hours' }
                    observation       = @{ value = 0.5; unit = 'hours' }
                    evidence_links    = @('docs/triage.csv')
                    valuation         = @{ direction = 'decrease'; volume = 200; hourlyRate = 50; redeployedShare = 0.8; attributionShare = 1.0; primaryInGroup = $true }
                }
                @{
                    claim_id          = 'speed-overlapping'
                    category          = 'speed'
                    hypothesis        = 'Same triage hours expressed as cycle-time speed'
                    beneficiary       = 'Desk'
                    measurement_owner = 'Ops'
                    status            = 'supported'
                    overlap_group     = 'triage-pool'
                    baseline          = @{ value = 1.0; unit = 'hours' }
                    observation       = @{ value = 0.5; unit = 'hours' }
                    evidence_links    = @('docs/triage.csv')
                    valuation         = @{ direction = 'decrease'; volume = 200; valuePerTimeUnit = 30; attributionShare = 1.0; overlapShare = 1.0 }
                }
                @{
                    claim_id          = 'pending-forecast'
                    category          = 'cost avoidance'
                    hypothesis        = 'Next-quarter storage tiering forecast'
                    beneficiary       = 'Infra'
                    measurement_owner = 'FinOps'
                    status            = 'pending'
                    baseline          = @{ value = 1000; unit = 'gb' }
                    target            = @{ value = 400; unit = 'gb' }
                    valuation         = @{ direction = 'decrease'; unitCost = 2.0; attributionShare = 1.0 }
                }
            )
        }

        # cap-primary = 0.5 * 200 * 0.8 * 50 = 4,000.00
        # speed-overlapping gross = 0.5 * 200 * 30 = 3,000.00 -> overlap deducted 3,000.00 -> net 0.00
        # pending-forecast = (1000 - 400) * 2.0 = 1,200.00 (modeled-counterfactual)
        # squad counterfactual AI savings = 2.50 - 0.50 = 2.00 (modeled-counterfactual)
        # total modeledCounterfactualValue = 1,202.00; totalStatedEvidencedValue = 4,000.00
        $result = Get-SquadBenefitValuation -InputDocument $doc -SquadRoot $squadDir
        $result.summary.totalStatedEvidencedValue | Should -Be 4000.00
        $result.summary.overlapDeductionsTotal | Should -Be 3000.00
        $result.overlapAdjustments.Count | Should -Be 1
        $result.overlapAdjustments[0].adjustedClaimId | Should -Be 'speed-overlapping'
        $result.summary.modeledCounterfactualValue | Should -Be 1202.00
        $result.summary.totalEvidencedCost | Should -Be 0.5
        $result.summary.netStatedValue | Should -Be 3999.50
    }
}

Describe 'VAL-05 Read-only HVE Squad ledger, federation aggregation, and decisions.md claim extraction' {
    It 'evaluates delivery labor value, extracts decisions.md claims, aggregates federation members, and leaves squad state untouched' {
        $fedRoot = Join-Path $TestDrive ("bv-fed-" + [guid]::NewGuid().ToString('N'))
        Write-BvFixtureFile -Path (Join-Path $fedRoot 'federation.md') -Text "# Federation`n"
        $m1 = New-BvSquadFixture -RunId 'm1' -SquadUsd '0.4000' -SquadUnits '40.00' -BaselineUsd '1.40' -Produced 2 -Accepted 2 -DecisionClaims @(
            'Claim ID: benefit-speed-01; category: speed; hypothesis: faster triage; beneficiary: Support; source evidence: docs/ev.csv; baseline: 12 minutes; target: 8 minutes; measurement owner: Ops; business decision owner: VP; status: pending; decision ref: dec-01.'
        )
        $m2 = New-BvSquadFixture -RunId 'm2' -SquadUsd '0.6000' -SquadUnits '60.00' -BaselineUsd '2.60' -Produced 1 -Accepted 1
        Copy-Item -LiteralPath $m1 -Destination (Join-Path $fedRoot 'members/alpha') -Recurse
        Copy-Item -LiteralPath $m2 -Destination (Join-Path $fedRoot 'members/beta') -Recurse

        $beforeHashes = @(
            Get-ChildItem -LiteralPath $fedRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
                "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)"
            }
        ) -join '|'

        $claimsFile = Join-Path $TestDrive 'fed-delivery-input.json'
        $outMd = Join-Path $TestDrive 'finops-out/fed-stated-value.md'
        $payload = @{
            report_id          = 'fed-portfolio-01'
            as_of              = '2026-11-15'
            delivery_valuation = @{
                baselineHoursPerDeliverable = 5.0
                observedHoursPerDeliverable = 1.0
                hourlyRate                  = 100.0
                redeployedShare             = 0.75
                attributionShare            = 1.0
            }
        }
        Write-BvFixtureFile -Path $claimsFile -Text ($payload | ConvertTo-Json -Depth 10)

        $cli = Invoke-BvCli -Arguments @('-ClaimsPath', $claimsFile, '-SquadRoot', $fedRoot, '-OutputPath', $outMd, '-Format', 'json')
        $cli.ExitCode | Should -Be 0 -Because $cli.Stderr
        Test-Path -LiteralPath $outMd -PathType Leaf | Should -BeTrue

        $parsed = $cli.Stdout | ConvertFrom-Json
        # 3 accepted deliverables across alpha (2) + beta (1); (5 - 1) * 0.75 * 100 * 3 = 900.00
        $parsed.squadDelivery.unitsCovered | Should -Be 2
        $parsed.squadDelivery.acceptedDeliverables | Should -Be 3
        $parsed.squadDelivery.aiSpend | Should -Be 1.0
        $parsed.squadDelivery.statedDeliveryLaborValue | Should -Be 900.00
        $parsed.summary.totalStatedEvidencedValue | Should -Be 900.00
        $parsed.summary.netStatedValue | Should -Be 899.00
        $parsed.summary.modeledCounterfactualValue | Should -Be 3.00
        @($parsed.claims | Where-Object claimId -EQ 'benefit-speed-01').Count | Should -Be 1
        ($parsed.claims | Where-Object claimId -EQ 'benefit-speed-01').monetaryBasis | Should -Be 'unmonetized-native-only'

        $mdText = Get-Content -LiteralPath $outMd -Raw
        $mdText | Should -Match '# Stated Monetary Value Report: fed-portfolio-01'
        $mdText | Should -Match 'USD 900\.00'
        $mdText | Should -Match '`benefit-speed-01`'

        $afterHashes = @(
            Get-ChildItem -LiteralPath $fedRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
                "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)"
            }
        ) -join '|'
        $afterHashes | Should -BeExactly $beforeHashes
    }
}

Describe 'VAL-06 Currency isolation and protected squad-state output path refusal' {
    It 'refuses unconvertible foreign currency additions and blocks writing inside .copilot-tracking/squad' {
        $squadDir = Join-Path $TestDrive '.copilot-tracking/squad'
        $fixture = New-BvSquadFixture
        Copy-Item -LiteralPath $fixture -Destination $squadDir -Recurse

        $unsafeOut = Join-Path $squadDir 'illegal-report.md'
        $refused = Invoke-BvCli -Arguments @('-SquadRoot', $squadDir, '-OutputPath', $unsafeOut)
        $refused.ExitCode | Should -Be 1
        $refused.Stderr | Should -Match 'protected squad state tree'
        Test-Path -LiteralPath $unsafeOut | Should -BeFalse

        $fxJson = @{
            report_id = 'fx-isolation'
            currency  = 'USD'
            benefit_claims = @(
                @{
                    claim_id          = 'eur-unconverted'
                    category          = 'cost avoidance'
                    hypothesis        = 'EUR cloud savings without FX rate'
                    beneficiary       = 'EU BU'
                    measurement_owner = 'EU FinOps'
                    status            = 'supported'
                    evidence_links    = @('docs/eu.csv')
                    valuation         = @{ currency = 'EUR'; counterfactualCost = 1000; observedCost = 600; attributionShare = 1.0 }
                }
            )
        } | ConvertTo-Json -Depth 10
        $fxRes = Invoke-BvCli -Arguments @('-ClaimsJson', $fxJson)
        $fxRes.ExitCode | Should -Be 0 -Because $fxRes.Stderr
        $fxModel = $fxRes.Stdout | ConvertFrom-Json
        $fxModel.summary.totalStatedEvidencedValue | Should -BeNullOrEmpty
        $fxModel.gaps -join ' ' | Should -Match 'EUR'
    }
}

Describe 'VAL-07 Squad Value Economist charter and FinOps reference integration' {
    It 'delivers Squad Value Economist wired to deterministic valuation and FinOps references' {
        $script:AgentPath | Should -Not -BeNullOrEmpty
        $raw = (Get-Content -LiteralPath $script:AgentPath -Raw) -replace "`r`n", "`n"
        $raw | Should -Match '(?m)^name:\s*Squad Value Economist$'
        $raw | Should -Match '(?m)^user-invocable:\s*false$'
        $raw | Should -Match '(?m)^disable-model-invocation:\s*false$'
        $raw | Should -Match 'Measure-SquadBenefitValue\.ps1'
        $raw | Should -Match 'business-value-measurement\.md'
        $raw | Should -Match 'value-valuation\.md'
        $raw | Should -Match '`finance-approved`'
        $raw | Should -Match '`stated-indicative`'
        $raw | Should -Match '`modeled-counterfactual`'
        $raw | Should -Match '`unmonetized-native-only`'
        $raw | Should -Match '`confirm`'
        Test-Path -LiteralPath (Join-Path $script:ReferencesRoot 'business-value-measurement.md') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:ReferencesRoot 'value-valuation.md') -PathType Leaf | Should -BeTrue
    }
}
