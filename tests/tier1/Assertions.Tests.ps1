#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Mutation controls: each case breaks exactly one rule and requires the contract to
# catch it. This is the evidence that the contract is worth running - a suite that
# cannot fail reports success on a broken tree, which is worse than no suite.
#
# Each mutation runs the contract in a child process, because Pester does not nest.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadFixture.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'SquadState.psm1') -Force

    $script:Runner = Join-Path $PSScriptRoot 'Invoke-Tier1Tests.ps1'
    $script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) "hve-squad-tier1-$([guid]::NewGuid().ToString('N').Substring(0, 8))"

    function New-Fixture {
        param([string]$Name)

        $path = Join-Path $script:Scratch $Name
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        New-SquadStateFixture -Path $path
    }

    function Test-Contract {
        param([string]$Root, [switch]$InitOnly)

        $arguments = @('-NoProfile', '-File', $script:Runner, '-SquadRoot', $Root, '-Output', 'None', '-Strict')
        if ($InitOnly) { $arguments += '-InitOnly' }
        & pwsh @arguments *>$null
        [pscustomobject]@{ Passed = $LASTEXITCODE -eq 0 }
    }

    function Edit-Fixture {
        param([string]$Path, [string]$Pattern, [string]$Replacement)

        $content = Get-Content -LiteralPath $Path -Raw
        $updated = $content -replace $Pattern, $Replacement
        if ($updated -eq $content) { throw "Mutation did not change $Path - the pattern '$Pattern' no longer matches the fixture." }
        Set-Content -LiteralPath $Path -Value $updated -Encoding utf8NoBOM -NoNewline

        # A plain function collects surplus positional arguments into $args rather than
        # failing, so an unparenthesised '-Replacement a + b' silently binds only 'a'.
        if ($args.Count -gt 0) { throw "Edit-Fixture received $($args.Count) unbound argument(s); parenthesise the concatenated replacement." }
    }

    function Set-PreflightDisposition {
        param(
            [string]$Root,
            [ValidateSet('over-ceiling', 'cannot-confirm')]
            [string]$Decision
        )

        $statePath = Join-Path $Root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['activeRoles'] = @()
        $preflight = $state['currentRun']['costPreflight']
        $preflight['decision'] = $Decision

        $decisionsPath = Join-Path $Root 'decisions.md'
        $decisions = Get-Content -LiteralPath $decisionsPath -Raw
        $decisions = $decisions.Replace('* Decision: within-ceiling', "* Decision: $Decision")
        $decisions = $decisions.Replace('* Permitted Next Dispatch Set: researcher-1, scribe-1', '* Permitted Next Dispatch Set: none')

        if ($Decision -eq 'over-ceiling') {
            $preflight['ceilingUsd'] = 3.0
            $preflight['remainingUsd'] = 3.0
            $preflight['reason'] = 'Conservative admission cost exceeds the remaining ceiling.'
            $decisions = $decisions.Replace('* Ceiling USD: 10.0000', '* Ceiling USD: 3.0000')
            $decisions = $decisions.Replace('* Remaining USD: 10.0000', '* Remaining USD: 3.0000')
        }
        else {
            $preflight['confidence'] = 'low'
            $preflight['basis'] = 'estimated'
            $preflight['reason'] = 'Calibration is not eligible for admission.'
            $decisions = $decisions.Replace('* Confidence: medium', '* Confidence: low')
            $decisions = $decisions.Replace('* Basis: calibrated', '* Basis: estimated')
            $ratesPath = Join-Path $Root 'consumption-rates.md'
            $rates = Get-Content -LiteralPath $ratesPath -Raw
            $rates.Replace('observations: 1', 'observations: 0') |
                Set-Content -LiteralPath $ratesPath -Encoding utf8NoBOM -NoNewline
        }

        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
        Set-Content -LiteralPath $decisionsPath -Value $decisions -Encoding utf8NoBOM -NoNewline
        Get-ChildItem -LiteralPath (Join-Path $Root 'history') -File -Filter '*.md' | Remove-Item -Force
    }

    function Add-RollingPreflightRound {
        param([string]$Root)

        Add-Content -LiteralPath (Join-Path $Root 'decisions.md') -Encoding utf8NoBOM -Value @'

## Cost Preflight 2026-08-19T10:01:00Z fixture-001 round-002

* Ceiling USD: 20.0000
* Estimated Spend So Far USD: 0.0923
* Remaining USD: 19.9077
* Projected Cost USD: 2.1176
* Reserve Multiplier: 3.0
* Admission Cost USD: 6.3527
* Confidence: medium
* Basis: calibrated
* Decision: within-ceiling
* Reason: The remaining review slot fits the conservative reserve.
* Evaluated Dispatch Set: tester-2
* Permitted Next Dispatch Set: tester-2
* Estimate Notice: Forecast only; not billed cost.

### Planned Demand

| Slot | Stage | Role | Count | Dispatch Class | Pricing Basis | Internal Turns | Base Context | Growth/Turn | Output/Turn | Projected Cost |
|------|-------|------|------:|----------------|---------------|---------------:|-------------:|------------:|------------:|---------------:|
| tester-2 | review | tester | 1 | Review / verification | Claude Sonnet 4.6 | 18 | 50000 | 4000 | 1500 | 2.117580 |
'@

        $statePath = Join-Path $Root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['currentRun']['costPreflight'] = [ordered]@{
            runId = 'fixture-001'; roundId = 'round-002'; ceilingUsd = 20.0
            evaluatedSpendUsd = 0.0923; remainingUsd = 19.9077; plannedDispatches = 1
            projectedCostUsd = 2.1176; reserveMultiplier = 3.0; admissionCostUsd = 6.3527
            confidence = 'medium'; basis = 'calibrated'; decision = 'within-ceiling'
            reason = 'The remaining review slot fits the conservative reserve.'
        }
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
    }

    function Add-ApprovedOverCeilingRound {
        param([string]$Root)

        $decisionsPath = Join-Path $Root 'decisions.md'
        $decisions = Get-Content -LiteralPath $decisionsPath -Raw
        $decisions = $decisions.Replace('* Ceiling USD: 10.0000', '* Ceiling USD: 0.0900')
        $decisions = $decisions.Replace('* Remaining USD: 10.0000', '* Remaining USD: 0.0900')
        $decisions = $decisions.Replace('* Decision: within-ceiling', '* Decision: over-ceiling')
        $decisions = $decisions.Replace('* Reason: Complete fixed-model manifest with eligible calibration fits the remaining ceiling.', '* Reason: Conservative admission cost exceeds the remaining ceiling.')
        $decisions = $decisions.Replace('* Permitted Next Dispatch Set: researcher-1, scribe-1', '* Permitted Next Dispatch Set: none')
        Set-Content -LiteralPath $decisionsPath -Value $decisions -Encoding utf8NoBOM -NoNewline

        Add-Content -LiteralPath $decisionsPath -Encoding utf8NoBOM -Value @'

## Cost Preflight 2026-08-19T10:00:00Z fixture-001 round-002

* Ceiling USD: 0.0900
* Estimated Spend So Far USD: 0.0000
* Remaining USD: 0.0900
* Projected Cost USD: 1.4243
* Reserve Multiplier: 3.0
* Admission Cost USD: 4.2728
* Confidence: medium
* Basis: calibrated
* Decision: approved-over-ceiling
* Approved From: `decisions.md#cost-preflight-2026-08-19t095959z-fixture-001-round-001`
* Approval Ref: `notifications.md#approval-received-2026-08-19t100000z`
* Reason: The user approved bounded execution under the unchanged ceiling.
* Evaluated Dispatch Set: coordinator-1, researcher-1, scribe-1
* Permitted Next Dispatch Set: researcher-1, scribe-1
* Estimate Notice: Forecast only; not billed cost.

### Planned Demand

| Slot | Stage | Role | Count | Dispatch Class | Pricing Basis | Internal Turns | Base Context | Growth/Turn | Output/Turn | Projected Cost |
|------|-------|------|------:|----------------|---------------|---------------:|-------------:|------------:|------------:|---------------:|
| coordinator-1 | orchestration | coordinator | 1 | Lookup / single-file read | Claude Sonnet 4.6 | 3 | 20000 | 3000 | 800 | 0.191460 |
| researcher-1 | research | researcher | 1 | Research / file survey | Claude Sonnet 4.6 | 12 | 40000 | 4000 | 1250 | 1.164960 |
| scribe-1 | orchestration | scribe | 1 | Scribe state write | Claude Haiku 4.5 | 4 | 15000 | 3000 | 800 | 0.067840 |
'@

        Add-Content -LiteralPath (Join-Path $Root 'notifications.md') -Encoding utf8NoBOM -Value @'

## Approval received 2026-08-19T10:00:00Z

* Decision: proceed under the configured ceiling
'@

        foreach ($historyPath in (Get-ChildItem -LiteralPath (Join-Path $Root 'history') -File -Filter '*.md')) {
            $history = Get-Content -LiteralPath $historyPath.FullName -Raw
            $history.Replace('fixture-001-round-001', 'fixture-001-round-002') |
                Set-Content -LiteralPath $historyPath.FullName -Encoding utf8NoBOM -NoNewline
        }

        $statePath = Join-Path $Root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['currentRun']['costPreflight'] = [ordered]@{
            runId = 'fixture-001'; roundId = 'round-002'; ceilingUsd = 0.09
            evaluatedSpendUsd = 0.0; remainingUsd = 0.09; plannedDispatches = 3
            projectedCostUsd = 1.4243; reserveMultiplier = 3.0; admissionCostUsd = 4.2728
            confidence = 'medium'; basis = 'calibrated'; decision = 'approved-over-ceiling'
            reason = 'The user approved bounded execution under the unchanged ceiling.'
        }
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
    }

    function Add-CeilingReachedRound {
        param([string]$Root)

        Add-Content -LiteralPath (Join-Path $Root 'decisions.md') -Encoding utf8NoBOM -Value @'

## Cost Preflight 2026-08-19T10:00:06Z fixture-001 round-003

* Ceiling USD: 0.0900
* Estimated Spend So Far USD: 0.0923
* Remaining USD: 0.0000
* Projected Cost USD: 2.1176
* Reserve Multiplier: 3.0
* Admission Cost USD: 6.3527
* Confidence: medium
* Basis: calibrated
* Decision: over-ceiling
* Reason: Accumulated estimated spend has reached the configured ceiling.
* Evaluated Dispatch Set: tester-1
* Permitted Next Dispatch Set: none
* Estimate Notice: Forecast only; not billed cost.

### Planned Demand

| Slot | Stage | Role | Count | Dispatch Class | Pricing Basis | Internal Turns | Base Context | Growth/Turn | Output/Turn | Projected Cost |
|------|-------|------|------:|----------------|---------------|---------------:|-------------:|------------:|------------:|---------------:|
| tester-1 | review | tester | 1 | Review / verification | Claude Sonnet 4.6 | 18 | 50000 | 4000 | 1500 | 2.117580 |
'@

        $statePath = Join-Path $Root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['currentRun']['costPreflight'] = [ordered]@{
            runId = 'fixture-001'; roundId = 'round-003'; ceilingUsd = 0.09
            evaluatedSpendUsd = 0.0923; remainingUsd = 0.0; plannedDispatches = 1
            projectedCostUsd = 2.1176; reserveMultiplier = 3.0; admissionCostUsd = 6.3527
            confidence = 'medium'; basis = 'calibrated'; decision = 'over-ceiling'
            reason = 'Accumulated estimated spend has reached the configured ceiling.'
        }
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
    }

    function Use-NoCeilingState {
        [CmdletBinding(SupportsShouldProcess)]
        param([string]$Root)

        if (-not $PSCmdlet.ShouldProcess($Root, 'Configure a no-ceiling state fixture')) { return }

        $statePath = Join-Path $Root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['activeRoles'] = @()
        $state['currentRun']['costPreflight'] = [ordered]@{
            runId = ''; roundId = ''; ceilingUsd = $null; evaluatedSpendUsd = 0
            remainingUsd = $null; plannedDispatches = 0; projectedCostUsd = 0
            reserveMultiplier = 3.0; admissionCostUsd = 0; confidence = 'not-applicable'
            basis = 'not-requested'; decision = 'not-requested'; reason = 'No cost ceiling configured.'
        }
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
        Get-ChildItem -LiteralPath (Join-Path $Root 'history') -File -Filter '*.md' | Remove-Item -Force
    }

    function Move-FixtureToMemberRoot {
        param([string]$Root, [string]$Name)

        $trackingRoot = Split-Path $Root -Parent
        $temporary = Join-Path $trackingRoot "$Name-state"
        Move-Item -LiteralPath $Root -Destination $temporary
        $members = Join-Path $trackingRoot 'squad/members'
        New-Item -ItemType Directory -Path $members -Force | Out-Null
        $destination = Join-Path $members $Name
        Move-Item -LiteralPath $temporary -Destination $destination
        $destination
    }

    function New-FederationPreflightFixture {
        param([string]$Name)

        $root = Join-Path $script:Scratch "$Name/.copilot-tracking/squad"
        New-Item -ItemType Directory -Path (Join-Path $root 'history') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'federation.md') -Encoding utf8NoBOM -Value "# Squad Federation`n"
        Set-Content -LiteralPath (Join-Path $root 'decisions.md') -Encoding utf8NoBOM -Value @'
# Squad Federation Decisions

## Cost Preflight 2026-08-19T09:50:00Z prior-run meta-009

* Realized Inner Cost USD: 0.5000

### Federation Terms

| Round | Inner Admission USD | Federation Meta Admission USD | Total Admission USD |
|-------|--------------------:|------------------------------:|--------------------:|
| meta-009 | 1.0000 | 0.9000 | 1.9000 |

### Meta Demand

| Slot | Projected Cost |
|------|---------------:|
| federation-coordinator-1 | 0.9000 |

## Cost Preflight 2026-08-19T09:59:59Z federation-001 meta-001

* Realized Inner Cost USD: 2.0000

### Federation Terms

| Round | Inner Admission USD | Federation Meta Admission USD | Total Admission USD |
|-------|--------------------:|------------------------------:|--------------------:|
| meta-001 | 5.1000 | 0.9000 | 6.0000 |

### Meta Demand

| Slot | Projected Cost |
|------|---------------:|
| federation-coordinator-1 | 0.2000 |
| federation-future-1 | 0.6000 |

## Cost Preflight 2026-08-19T10:00:04Z federation-001 meta-002

* Realized Inner Cost USD: 2.0000

### Federation Terms

| Round | Inner Admission USD | Federation Meta Admission USD | Total Admission USD |
|-------|--------------------:|------------------------------:|--------------------:|
| meta-002 | 2.1000 | 0.3000 | 2.4000 |

### Meta Demand

| Slot | Projected Cost |
|------|---------------:|
| federation-coordinator-1 | 0.1500 |
| federation-root-writer-1 | 0.1000 |
| federation-future-2 | 0.0500 |
'@
        Set-Content -LiteralPath (Join-Path $root 'history/product.md') -Encoding utf8NoBOM -Value @'
# History: product

## Completed prior-run coordinator transition

* Cost Preflight Ref: `decisions.md#cost-preflight-2026-08-19t095000z-prior-run-meta-009`
* Cost Preflight Slot: federation-coordinator-1

## Completed federation coordinator transition

* Cost Preflight Ref: `decisions.md#cost-preflight-2026-08-19t095959z-federation-001-meta-001`
* Cost Preflight Slot: federation-coordinator-1

## Re-read federation coordinator transition

* Cost Preflight Ref: `decisions.md#cost-preflight-2026-08-19t095959z-federation-001-meta-001`
* Cost Preflight Slot: federation-coordinator-1

## Completed federation root writer transition

* Cost Preflight Ref: `decisions.md#cost-preflight-2026-08-19t100004z-federation-001-meta-002`
* Cost Preflight Slot: federation-root-writer-1

## Completed second-round coordinator transition

* Cost Preflight Ref: `decisions.md#cost-preflight-2026-08-19t100004z-federation-001-meta-002`
* Cost Preflight Slot: federation-coordinator-1
'@
        Set-Content -LiteralPath (Join-Path $root 'state.json') -Encoding utf8NoBOM -Value @'
{
  "schemaVersion": "1.3",
  "updated": "2026-08-19T10:00:05Z",
  "turn": 1,
  "mode": "autopilot",
  "subSquads": [ "product" ],
  "activeSubSquads": [ "product" ],
  "openEscalations": [],
  "currentRun": {
    "sessionModel": "Claude Sonnet 4.6",
    "modelOverrides": {},
    "estCostUsd": 2.45,
    "estCreditsTotal": 245.0,
    "costPreflight": {
      "runId": "federation-001",
    "roundId": "meta-002",
      "ceilingUsd": 10.0,
      "evaluatedSpendUsd": 0.0,
      "remainingUsd": 10.0,
    "plannedDispatches": 2,
    "projectedCostUsd": 0.8,
      "reserveMultiplier": 3.0,
    "admissionCostUsd": 2.4,
      "confidence": "medium",
      "basis": "calibrated",
      "decision": "within-ceiling",
      "reason": "Aggregate inner and meta reservations fit."
    }
  },
  "notify": {
    "approvalChannel": "github-issue",
    "enabled": true,
    "email": "",
    "github": { "handle": "operator", "repo": "owner/repo" }
  }
}
'@
    $rateTemplate = Get-ShippedRateTemplate
    $observedOnPattern = 'Observed-on: (<YYYY-MM-DD>|\d{4}-\d{2}-\d{2})'
    if ($rateTemplate -notmatch $observedOnPattern) { throw "The shipped rate template has no 'Observed-on:' line matching $observedOnPattern." }
    $rateTemplate = $rateTemplate -replace $observedOnPattern, 'Observed-on: 2026-08-19'
    $rateTemplate = $rateTemplate.Replace('last_reconciled: never', 'last_reconciled: 2026-08-19')
    $rateTemplate = $rateTemplate.Replace('observations: 0', 'observations: 1')
    $rateTemplate = $rateTemplate.Replace('calibration_basis: "<observed-on>|2"', 'calibration_basis: "2026-08-19|2"')
    Set-Content -LiteralPath (Join-Path $root 'consumption-rates.md') -Encoding utf8NoBOM -Value $rateTemplate
        $root
    }

    function Copy-ConnectorManifestFixture {
        param(
            [string]$Root,
            [string]$Name
        )

        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $source = Join-Path $repoRoot 'docs' 'templates' 'connector-example' $Name
        $projectRoot = Split-Path (Split-Path $Root -Parent) -Parent
        $destinationDirectory = Join-Path $projectRoot 'connectors'
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination (Join-Path $destinationDirectory $Name)
        "connectors/$Name"
    }

    function Set-ConnectorHistoryFixture {
        param(
            [string]$Root,
            [string]$MemberName,
            [string]$ConnectorId,
            [string]$BindingId,
            [string]$EndpointKind,
            [string]$RoleMode,
            [string]$Target
        )

        $internalHistory = Join-Path $Root 'history/Squad Researcher.md'
        $connectorHistory = Join-Path $Root 'history/Squad Connector.md'
        Move-Item -LiteralPath $internalHistory -Destination $connectorHistory
        $history = Get-Content -LiteralPath $connectorHistory -Raw
        $history = $history.Replace('# History: Squad Researcher', '# History: Squad Connector')
        $history = $history -replace '(?m)^\* Outcome: .+$', ("* Outcome: external, unverified`n" +
            "* Member Name: $MemberName`n" +
            "* External provenance: connector=$ConnectorId; binding=$BindingId; endpoint=$EndpointKind; mode=$RoleMode; target=$Target`n" +
            "* Verification: external, unverified`n" +
            "* External-unmetered: connector=$ConnectorId")
        Set-Content -LiteralPath $connectorHistory -Value $history -Encoding utf8NoBOM -NoNewline
    }

    function Set-ConnectorLedgerFixture {
        param(
            [string]$Root,
            [string]$Role,
            [string]$MemberName
        )

        $ledgerPath = Join-Path $Root 'consumption.md'
        $ledger = Get-Content -LiteralPath $ledgerPath -Raw
        $updated = $ledger.Replace(
            '| researcher    |        | Squad Researcher               |',
            ("| {0,-13} | {1} | Squad Connector                |" -f $Role, $MemberName))
        if ($updated -eq $ledger) { throw 'The connector fixture could not update the researcher attribution row.' }
        if ($Role -ne 'researcher') {
            $updated = $updated.Replace('| researcher    | 1     |', ("| {0,-13} | 1     |" -f $Role))
            $updated = $updated.Replace('researcher     turns 1', ("{0,-14} turns 1" -f $Role))
        }
        Set-Content -LiteralPath $ledgerPath -Value $updated -Encoding utf8NoBOM -NoNewline
    }

    function Use-ConnectorReplacementState {
        param([string]$Root)

        $manifest = Copy-ConnectorManifestFixture -Root $Root -Name 'manifest.research-agent.1.1.json'
        $bindings = @'

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
|------------|--------------|----------|---------------|-----------|-------------|--------|-------------|------------|--------------|-------------------|
| research-org | acme-research-agent | __MANIFEST__ | agent | replace | role | role:researcher | Org Researcher | | researcher | connector |
'@.Replace('__MANIFEST__', $manifest)
        Add-Content -LiteralPath (Join-Path $Root 'team.md') -Encoding utf8NoBOM -Value $bindings

        Set-ConnectorHistoryFixture -Root $Root -MemberName 'Org Researcher' -ConnectorId 'acme-research-agent' `
            -BindingId 'research-org' -EndpointKind 'agent' -RoleMode 'replace' -Target 'role:researcher'
        Set-ConnectorLedgerFixture -Root $Root -Role 'researcher' -MemberName 'Org Researcher'
    }

    function Use-ConnectorAdditiveState {
        param([string]$Root)

        $manifest = Copy-ConnectorManifestFixture -Root $Root -Name 'manifest.capability-assessor.1.1.json'
        $teamPath = Join-Path $Root 'team.md'
        $team = Get-Content -LiteralPath $teamPath -Raw
        $memberRow = '| gcp         | GCP Assessor | Squad Connector      |                  | —                                                   | runSubagent | fast       | `.copilot-tracking/research/` |'
        $updated = [regex]::Replace($team, '(?m)^(\| scribe[^\r\n]+\|\r?\n)', ('$1' + $memberRow + "`n"), 1)
        if ($updated -eq $team) { throw 'The additive fixture could not add the connector Members row.' }
        Set-Content -LiteralPath $teamPath -Value $updated -Encoding utf8NoBOM -NoNewline

        $bindings = @'

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
|------------|--------------|----------|---------------|-----------|-------------|--------|-------------|------------|--------------|-------------------|
| gcp-assessor | acme-capability-assessor | __MANIFEST__ | agent | add | role | role:gcp/GCP Assessor | GCP Assessor | gcp | researcher | connector |
'@.Replace('__MANIFEST__', $manifest)
        Add-Content -LiteralPath $teamPath -Encoding utf8NoBOM -Value $bindings

        Set-ConnectorHistoryFixture -Root $Root -MemberName 'GCP Assessor' -ConnectorId 'acme-capability-assessor' `
            -BindingId 'gcp-assessor' -EndpointKind 'agent' -RoleMode 'add' -Target 'role:gcp/GCP Assessor'
        Set-ConnectorLedgerFixture -Root $Root -Role 'gcp' -MemberName 'GCP Assessor'

        $statePath = Join-Path $Root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['activeRoles'] = @('gcp')
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
    }

    function Use-LegacyConnectorState {
        param([string]$Root)

        Set-ConnectorHistoryFixture -Root $Root -MemberName 'Org Researcher' -ConnectorId 'acme-research-legacy' `
            -BindingId 'legacy-1.0' -EndpointKind 'agent' -RoleMode 'replace' -Target 'role:researcher'
        Set-ConnectorLedgerFixture -Root $Root -Role 'researcher' -MemberName 'Org Researcher'
    }

    function Save-ConnectorRetirementFixture {
        param([string]$Root)

        $model = Get-SquadStateModel -SquadRoot $Root
        if ($model.ConnectorBindingIssues.Count -gt 0 -or $model.ConnectorHistoryIssues.Count -gt 0) {
            throw 'Only a valid completed connector fixture can be retired.'
        }
        $binding = $model.ConnectorBindings[0]
        $manifests = [ordered]@{}
        foreach ($priorBinding in $model.ConnectorBindings) {
            $manifests[$priorBinding.ManifestPath] = Get-Content -LiteralPath $priorBinding.ResolvedManifest -Raw | ConvertFrom-Json -AsHashtable
        }
        $record = [ordered]@{
            team            = $model.Team
            manifests       = $manifests
            confirmed       = $true
            confirmationRef = 'in-chat:fixture-confirmed-refresh'
            historyEntries  = @(
                $model.Entries | Where-Object { $_.Agent -ceq 'Squad Connector' -and $_.ExternalBindingId -ceq $binding.BindingId } |
                    ForEach-Object Title
            )
        }
        $json = $record | ConvertTo-Json -Depth 10
        $entry = "`n## Connector Binding Retirement 2026-08-20T10:00:00Z $($binding.BindingId)`n`n" +
            '```json' + "`n$json`n" + '```'
        Add-Content -LiteralPath (Join-Path $Root 'decisions.md') -Value $entry -Encoding utf8NoBOM
    }

    function Use-MultipleConnectorRoots {
        param([string]$Root, [switch]$Shared)
        Use-ConnectorReplacementState -Root $Root
        $model = Get-SquadStateModel -SquadRoot $Root
        $first = $model.Deliverables | Where-Object Agent -CEQ 'Squad Connector' | Select-Object -First 1
        $secondRoot = if ($Shared) { $model.RoleRoots['researcher'] } else { '.copilot-tracking/reviews/external/' }
        $manifest = Copy-ConnectorManifestFixture -Root $Root -Name 'manifest.capability-assessor.1.1.json'
        $teamPath = Join-Path $Root 'team.md'
        $team = [System.IO.File]::ReadAllText($teamPath)
        $member = "| gcp | GCP Assessor | Squad Connector | | - | task | fast | $secondRoot |"
        $team = [regex]::Replace($team, '(?m)^(\| scribe[^\r\n]+\|\r?\n)', ('$1' + $member + "`n"), 1)
        $team = $team.TrimEnd() + "`n| gcp-assessor | acme-capability-assessor | $manifest | agent | add | role | role:gcp/GCP Assessor | GCP Assessor | gcp | researcher | connector |`n"
        Set-Content -LiteralPath $teamPath -Value $team -Encoding utf8NoBOM
        $secondPath = $secondRoot.TrimEnd('/') + '/second-connector.md'
        $projectRoot = Split-Path (Split-Path $Root -Parent) -Parent
        $diskPath = Join-Path $projectRoot $secondPath
        [void][System.IO.Directory]::CreateDirectory((Split-Path $diskPath -Parent))
        Copy-Item -LiteralPath $first.Resolved -Destination $diskPath
        $historyPath = Join-Path $Root 'history/Squad Connector.md'
        $body = [regex]::Match([System.IO.File]::ReadAllText($historyPath), '(?ms)^#{2,3}[ \t]+[^\r\n]+\r?\n(?<body>.*)').Groups['body'].Value
        $body = $body.Replace('Org Researcher', 'GCP Assessor').Replace('acme-research-agent', 'acme-capability-assessor').
            Replace('binding=research-org', 'binding=gcp-assessor').Replace('mode=replace', 'mode=add').
            Replace('target=role:researcher', 'target=role:gcp/GCP Assessor')
        $body = $body -replace '(?m)^\* Deliverable:[^\r\n]+', ('* Deliverable: `' + $secondPath + '`')
        Add-Content -LiteralPath $historyPath -Value ("`n## 2026-08-19T10:30:00Z Second connector report`n" + $body) -Encoding utf8NoBOM
        [pscustomobject]@{ FirstPath = $first.Path; SecondPath = $secondPath; SecondRoot = $secondRoot; HistoryPath = $historyPath }
    }

    function Remove-ConnectorBindingFixture {
        param([string]$Root)

        Edit-Fixture -Path (Join-Path $Root 'team.md') -Pattern '(?ms)\r?\n## Connector Bindings\r?\n.*\z' -Replacement ''
    }

    function Test-FederationPreflightFixture {
        param([string]$Root)

        try {
            $state = Get-Content -LiteralPath (Join-Path $Root 'state.json') -Raw | ConvertFrom-Json -AsHashtable
            if ($state['schemaVersion'] -ne '1.3' -or -not $state['notify'] -or -not $state['currentRun']['costPreflight']) { return $false }
            $ratesPath = Join-Path $Root 'consumption-rates.md'
            if (-not (Test-Path -LiteralPath $ratesPath)) { return $false }
            $rates = Get-Content -LiteralPath $ratesPath -Raw
            if ($rates -notmatch '(?m)^observations:\s+[1-9][0-9]*\r?$' -or $rates -notmatch '(?m)^calibration_basis:\s+"2026-08-19\|2"\r?$') { return $false }
            $decisions = Get-Content -LiteralPath (Join-Path $Root 'decisions.md') -Raw
            $tables = @(Get-MarkdownTable -Content $decisions)
            foreach ($terms in @($tables | Where-Object { 'Inner Admission USD' -in $_.Header } | ForEach-Object Rows)) {
                if ([double]$terms['Total Admission USD'] -ne ([double]$terms['Inner Admission USD'] + [double]$terms['Federation Meta Admission USD'])) { return $false }
            }

            $metaCosts = @{}
            $currentBody = $null
            foreach ($record in [regex]::Matches($decisions, '(?ms)^## Cost Preflight (?<timestamp>\S+) (?<run>\S+) (?<round>\S+)\r?\n(?<body>.*?)(?=^## |\z)')) {
                if ($record.Groups['run'].Value -ne $state['currentRun']['costPreflight']['runId']) { continue }
                $timestamp = $record.Groups['timestamp'].Value.ToLowerInvariant().Replace(':', '')
                $reference = 'decisions.md#cost-preflight-' + $timestamp + '-' + $record.Groups['run'].Value + '-' + $record.Groups['round'].Value
                foreach ($table in @(Get-MarkdownTable -Content $record.Groups['body'].Value | Where-Object { 'Slot' -in $_.Header -and 'Projected Cost' -in $_.Header })) {
                    foreach ($row in $table.Rows) { $metaCosts["$reference|$($row['Slot'])"] = [double]$row['Projected Cost'] }
                }
                if ($record.Groups['round'].Value -eq $state['currentRun']['costPreflight']['roundId']) { $currentBody = $record.Groups['body'].Value }
            }
            $history = Get-Content -LiteralPath (Join-Path $Root 'history/product.md') -Raw
            $completed = @(
                foreach ($entry in [regex]::Matches($history, '(?ms)^## .*?\r?\n(?<body>.*?)(?=^## |\z)')) {
                    $reference = [regex]::Match($entry.Groups['body'].Value, '(?m)^\* Cost Preflight Ref:\s*`(?<value>[^`]+)`').Groups['value'].Value
                    $slot = [regex]::Match($entry.Groups['body'].Value, '(?m)^\* Cost Preflight Slot:\s*(?<value>\S+)').Groups['value'].Value
                    $key = "$reference|$slot"
                    if ($metaCosts.ContainsKey($key)) { $key }
                }
            ) | Sort-Object -Unique
            $metaRealized = ($completed | ForEach-Object { $metaCosts[$_] } | Measure-Object -Sum).Sum
            $inner = [double]([regex]::Match($currentBody, '(?m)^\* Realized Inner Cost USD:\s*([0-9.]+)').Groups[1].Value)
            $expected = [math]::Round($inner + $metaRealized, 4)
            return [math]::Round([double]$state['currentRun']['estCostUsd'], 4) -eq $expected -and
                [math]::Round([double]$state['currentRun']['estCreditsTotal'], 2) -eq [math]::Round($expected / 0.01, 2)
        }
        catch { return $false }
    }
}

AfterAll {
    if ($script:Scratch -and (Test-Path -LiteralPath $script:Scratch)) {
        Remove-Item -LiteralPath $script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'The contract passes on a schema-correct tree' {
    It 'passes unmutated' {
        $root = New-Fixture 'baseline'
        (Test-Contract $root).Passed | Should -BeTrue -Because 'a contract that cannot pass on a correct tree only reports noise'
    }

    It 'passes an initialized tree that has not dispatched yet' {
        $root = New-Fixture 'init-only'
        Get-ChildItem -LiteralPath (Join-Path $root 'history') -Filter '*.md' -File | Remove-Item -Force
        (Test-Contract -Root $root -InitOnly).Passed | Should -BeTrue -Because 'Init seeds the history directory and nothing inside it'
    }

    It 'accepts legacy schema 1.3 without a cost preflight object' {
        $root = New-Fixture 'legacy-no-ceiling'
        $statePath = Join-Path $root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['schemaVersion'] = '1.3'
        $state['currentRun'].Remove('costPreflight')
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
        (Test-Contract $root).Passed | Should -BeTrue -Because 'an existing no-ceiling squad upgrades on its next write rather than failing on read'
    }

    It 'accepts a completed connector replacement while retaining the internal Members row' {
        $root = New-Fixture 'connector-replacement'
        Use-ConnectorReplacementState -Root $root

        $model = Get-SquadStateModel -SquadRoot $root
        $model.RosterAgents | Should -Contain 'Squad Connector'
        $model.RoleAgents['researcher'] | Should -Contain 'Squad Researcher'
        $model.RoleAgents['researcher'] | Should -Contain 'Squad Connector'

        $memberRows = @(
            foreach ($table in (Get-MarkdownTable -Content $model.Team)) {
                if ('Agent Name (Primary)' -in $table.Header) { $table.Rows }
            }
        )
        @($memberRows | Where-Object { $_['Role'] -eq 'researcher' }).Count | Should -Be 1
        @($memberRows | Where-Object { $_['Member Name'] -eq 'Org Researcher' }).Count | Should -Be 0
        (Test-Contract $root).Passed | Should -BeTrue -Because 'a replacement binding adds a connector history identity without rewriting Members'
    }

    It 'accepts a completed additive connector with its exact Members row' {
        $root = New-Fixture 'connector-additive'
        Use-ConnectorAdditiveState -Root $root

        $model = Get-SquadStateModel -SquadRoot $root
        $model.RoleAgents['gcp'] | Should -Contain 'Squad Connector'
        $model.ConnectorHistoryIdentities[0].MemberName | Should -Be 'GCP Assessor'
        (Test-Contract $root).Passed | Should -BeTrue -Because 'an additive binding is valid only with its exact connector member row'
    }

    It 'accepts a binding-free legacy 1.0 connector identity' {
        $root = New-Fixture 'connector-legacy'
        Use-LegacyConnectorState -Root $root

        $model = Get-SquadStateModel -SquadRoot $root
        $model.ConnectorBindings.Count | Should -Be 0
        $model.RoleAgents['researcher'] | Should -Contain 'Squad Connector'
        $model.ConnectorHistoryIdentities[0].BindingId | Should -Be 'legacy-1.0'
        (Test-Contract $root).Passed | Should -BeTrue -Because 'legacy provenance derives role identity without inventing a 1.1 binding'
    }

    It 'preserves completed connector history after a confirmed unbind' {
        $root = New-Fixture 'connector-confirmed-unbind'
        Use-ConnectorReplacementState -Root $root
        $historyPath = Join-Path $root 'history/Squad Connector.md'
        $historyHash = (Get-FileHash -LiteralPath $historyPath).Hash
        Save-ConnectorRetirementFixture -Root $root
        Remove-ConnectorBindingFixture -Root $root

        (Test-Contract $root).Passed | Should -BeTrue -Because 'confirmed removal changes future execution, not completed history'
        (Get-FileHash -LiteralPath $historyPath).Hash | Should -Be $historyHash
        (Get-SquadStateModel -SquadRoot $root).ConnectorBindings.Count | Should -Be 0
    }

    It 'preserves the former identity when the same binding id is rebound to a different connector and member' {
        $root = New-Fixture 'connector-confirmed-rebind'
        Use-ConnectorReplacementState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'team.md') -Pattern 'Org Researcher' -Replacement 'New Org Researcher'
        Edit-Fixture -Path (Join-Path $root 'team.md') -Pattern 'acme-research-agent' -Replacement 'new-research-agent'
        $projectRoot = Split-Path (Split-Path $root -Parent) -Parent
        Edit-Fixture -Path (Join-Path $projectRoot 'connectors/manifest.research-agent.1.1.json') `
            -Pattern 'acme-research-agent' -Replacement 'new-research-agent'

        (Test-Contract $root).Passed | Should -BeTrue -Because 'retained provenance must not be reinterpreted through the new registration'
        $model = Get-SquadStateModel -SquadRoot $root
        $model.ConnectorBindings[0].MemberName | Should -Be 'New Org Researcher'
        $model.ConnectorHistoryIdentities[0].MemberName | Should -Be 'Org Researcher'
    }

    It 'preserves completed additive history after its confirmed binding and member removal' {
        $root = New-Fixture 'connector-confirmed-additive-unbind'
        Use-ConnectorAdditiveState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Remove-ConnectorBindingFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'team.md') -Pattern '(?m)^\| gcp[ \t]+\| GCP Assessor[^\r\n]*\r?\n' -Replacement ''
        $statePath = Join-Path $root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['activeRoles'] = @()
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM

        (Test-Contract $root).Passed | Should -BeTrue -Because 'an additive member is removed without erasing its completed dispatches'
    }

    It 'keeps a default-only refresh compatible with completed connector history' {
        $root = New-Fixture 'connector-default-only-refresh'
        Use-ConnectorReplacementState -Root $root
        Edit-Fixture -Path (Join-Path $root 'team.md') -Pattern '\| connector \|' -Replacement '| ask |'

        (Test-Contract $root).Passed | Should -BeTrue
    }

    It 'CONN-33 resolves each completed connector root when Shared=<Shared>' -ForEach @(
        @{ Shared = $true }, @{ Shared = $false }
    ) {
        $root = New-Fixture "connector-multiple-roots-$Shared"
        $paths = Use-MultipleConnectorRoots -Root $root -Shared:$Shared
        $model = Get-SquadStateModel -SquadRoot $root
        $model.ConnectorHistoryIssues | Should -BeNullOrEmpty
        $reports = @($model.Deliverables | Where-Object Agent -CEQ 'Squad Connector')
        $reports.Count | Should -Be 2
        @($reports | Where-Object { -not $_.UnderRoot -or -not $_.Resolved }).Count | Should -Be 0
        ($reports | Where-Object Path -EQ $paths.FirstPath).Root | Should -Be $model.RoleRoots['researcher']
        ($reports | Where-Object Path -EQ $paths.SecondPath).Root | Should -Be $paths.SecondRoot
    }

    It 'CONN-33 does not admit a report merely because another connector owns its root' {
        $root = New-Fixture 'connector-wrong-sibling-root'
        $paths = Use-MultipleConnectorRoots -Root $root
        $history = [System.IO.File]::ReadAllText($paths.HistoryPath).Replace($paths.FirstPath, $paths.SecondPath)
        Set-Content -LiteralPath $paths.HistoryPath -Value $history -Encoding utf8NoBOM
        $model = Get-SquadStateModel -SquadRoot $root
        $model.ConnectorHistoryIssues | Should -BeNullOrEmpty
        @($model.Deliverables | Where-Object { $_.Agent -ceq 'Squad Connector' -and -not $_.UnderRoot }).Count | Should -Be 1
    }

    It 'CONN-33 rejects a directory whose name only starts with the authorized root' {
        $root = New-Fixture 'connector-root-prefix-collision'
        $paths = Use-MultipleConnectorRoots -Root $root
        $wrongPath = $paths.SecondRoot.TrimEnd('/') + '-sibling/report.md'
        Set-Content -LiteralPath $paths.HistoryPath -Value ([System.IO.File]::ReadAllText($paths.HistoryPath).Replace($paths.SecondPath, $wrongPath))
        $model = Get-SquadStateModel -SquadRoot $root
        ($model.Deliverables | Where-Object Path -EQ $wrongPath).UnderRoot | Should -BeFalse
    }

    It 'preserves legacy state while upgrading the preflight schema' {
        $root = New-Fixture 'legacy-upgrade'
        $statePath = Join-Path $root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $preflight = $state['currentRun']['costPreflight']
        $state['schemaVersion'] = '1.3'
        $state['trigger'] = @{ source = 'issue'; ref = 'owner/repo#42'; eventId = 'issue:42'; actor = 'operator'; receivedAt = '2026-08-19T09:00:00Z'; runId = 'fixture-001' }
        $state['notify']['github']['handle'] = 'operator'
        $state['currentRun'].Remove('costPreflight')
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM

        $legacy = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $legacy['schemaVersion'] = '1.4'
        $legacy['currentRun']['costPreflight'] = $preflight
        $legacy | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
        $upgraded = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable

        $upgraded['trigger']['eventId'] | Should -Be 'issue:42'
        $upgraded['notify']['github']['handle'] | Should -Be 'operator'
        $upgraded['currentRun']['estCostUsd'] | Should -Be 0.09225
        (Test-Contract $root).Passed | Should -BeTrue
    }

    It 'passes an over-ceiling round with no child dispatch' {
        $root = New-Fixture 'denied-round'
        Set-PreflightDisposition -Root $root -Decision 'over-ceiling'
        (Test-Contract -Root $root -InitOnly).Passed | Should -BeTrue
    }

    It 'passes a cannot-confirm round with no child dispatch' {
        $root = New-Fixture 'uncertain-round'
        Set-PreflightDisposition -Root $root -Decision 'cannot-confirm'
        (Test-Contract -Root $root -InitOnly).Passed | Should -BeTrue
    }

    It 'does not resume denied work from an approval note alone' {
        $root = New-Fixture 'approval-note-only'
        Set-PreflightDisposition -Root $root -Decision 'over-ceiling'
        Add-Content -LiteralPath (Join-Path $root 'notifications.md') -Value "`n## Approval received`n`n* Approval Ref: unchanged-ceiling`n"
        (Test-Contract -Root $root -InitOnly).Passed | Should -BeTrue
    }

    It 'passes an explicit approved over-ceiling round and its bounded dispatch unit' {
        $root = New-Fixture 'approved-over-ceiling'
        Add-ApprovedOverCeilingRound -Root $root
        (Test-Contract $root).Passed | Should -BeTrue
    }

    It 'passes a terminal ceiling-reached round after the approved dispatch unit' {
        $root = New-Fixture 'ceiling-reached'
        Add-ApprovedOverCeilingRound -Root $root
        Add-CeilingReachedRound -Root $root
        (Test-Contract $root).Passed | Should -BeTrue
    }

    It 'passes a current-schema new run with no ceiling' {
        $root = New-Fixture 'new-run-no-ceiling'
        Use-NoCeilingState -Root $root
        (Test-Contract -Root $root -InitOnly).Passed | Should -BeTrue
    }

    It 'passes an explicitly unset ceiling while preserving accumulated totals' {
        $root = New-Fixture 'explicitly-unset-ceiling'
        Use-NoCeilingState -Root $root
        Add-Content -LiteralPath (Join-Path $root 'notifications.md') -Encoding utf8NoBOM -Value "`n## Cost ceiling removed`n`n* Input: cost-ceiling=unset`n"
        $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json -AsHashtable
        $state['currentRun']['estCostUsd'] | Should -Be 0.09225
        $state['currentRun']['estCreditsTotal'] | Should -Be 9.225
        (Test-Contract -Root $root -InitOnly).Passed | Should -BeTrue
    }

    It 'keeps Watch Mode at schema 1.4 and stops before child dispatch' {
        $root = New-Fixture 'watch-denied'
        Set-PreflightDisposition -Root $root -Decision 'over-ceiling'
        $statePath = Join-Path $root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['mode'] = 'autopilot'
        $state['trigger'] = @{ source = 'issue'; ref = 'owner/repo#9'; eventId = 'issue:9'; actor = 'operator'; receivedAt = '2026-08-19T09:00:00Z'; runId = 'fixture-001' }
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
        (Test-Contract -Root $root -InitOnly).Passed | Should -BeTrue
    }

    It 'passes a targeted federation run at the member root' {
        $root = New-Fixture 'targeted-federation'
        $memberRoot = Move-FixtureToMemberRoot -Root $root -Name 'product'
        (Test-Contract $memberRoot).Passed | Should -BeTrue
    }

    It 'passes a rolling round while prior dispatches retain their original authorization' {
        $root = New-Fixture 'rolling-round'
        Add-RollingPreflightRound -Root $root
        (Test-Contract $root).Passed | Should -BeTrue
    }

    It 'passes aggregate federation accounting with duplicate transition references counted once' {
        $root = New-FederationPreflightFixture 'federation-aggregate'
        Test-FederationPreflightFixture $root | Should -BeTrue
    }

    It 'passes ordinary federation root state after a prior aggregate run' {
        $root = New-FederationPreflightFixture 'federation-ordinary-root'
        $statePath = Join-Path $root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['mode'] = 'interactive'
        $state['currentRun']['costPreflight'] = [ordered]@{
            runId = ''; roundId = ''; ceilingUsd = $null; evaluatedSpendUsd = 0; remainingUsd = $null
            plannedDispatches = 0; projectedCostUsd = 0; reserveMultiplier = 3.0; admissionCostUsd = 0
            confidence = 'not-applicable'; basis = 'not-requested'; decision = 'not-requested'; reason = 'No cost ceiling configured.'
        }
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
        $state['currentRun']['estCostUsd'] | Should -Be 2.45
        $state['currentRun']['costPreflight']['decision'] | Should -Be 'not-requested'
        $state['currentRun']['costPreflight']['ceilingUsd'] | Should -BeNullOrEmpty
    }
}

Describe 'The contract rejects invalid connector binding and provenance state' {
    It 'rejects a removed binding without confirmed historical evidence' {
        $root = New-Fixture 'connector-unconfirmed-unbind'
        Use-ConnectorReplacementState -Root $root
        Remove-ConnectorBindingFixture -Root $root
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects an unconfirmed historical retirement' {
        $root = New-Fixture 'connector-retirement-unconfirmed'
        Use-ConnectorReplacementState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Remove-ConnectorBindingFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'decisions.md') -Pattern '"confirmed": true' -Replacement '"confirmed": false'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects historical evidence without an operator confirmation reference' {
        $root = New-Fixture 'connector-retirement-no-confirmation-ref'
        Use-ConnectorReplacementState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Remove-ConnectorBindingFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'decisions.md') -Pattern '"confirmationRef": "in-chat:fixture-confirmed-refresh"' -Replacement '"confirmationRef": ""'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a retained member identity that differs from the confirmed retirement' {
        $root = New-Fixture 'connector-retirement-wrong-member'
        Use-ConnectorReplacementState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Remove-ConnectorBindingFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'history/Squad Connector.md') -Pattern '\* Member Name: Org Researcher' -Replacement '* Member Name: Wrong Researcher'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects retired target/member provenance that was not valid in the saved roster' {
        $root = New-Fixture 'connector-retirement-invalid-prior-target'
        Use-ConnectorReplacementState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Remove-ConnectorBindingFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'decisions.md') -Pattern 'role:researcher' -Replacement 'role:researcher/Missing Researcher'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Connector.md') -Pattern 'role:researcher' -Replacement 'role:researcher/Missing Researcher'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a retired binding without its saved manifest' {
        $root = New-Fixture 'connector-retirement-missing-prior-manifest'
        Use-ConnectorReplacementState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Remove-ConnectorBindingFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'decisions.md') `
            -Pattern '"connectors/manifest\.research-agent\.1\.1\.json":' -Replacement '"connectors/missing.json":'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a retired connector id that differs from the saved manifest' {
        $root = New-Fixture 'connector-retirement-prior-id-mismatch'
        Use-ConnectorReplacementState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Remove-ConnectorBindingFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'decisions.md') `
            -Pattern '"connectorId": "acme-research-agent"' -Replacement '"connectorId": "wrong-research-agent"'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a retired additive binding whose member was absent from the saved roster' {
        $root = New-Fixture 'connector-retirement-prior-orphan-additive'
        Use-ConnectorAdditiveState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Remove-ConnectorBindingFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'decisions.md') -Pattern '\| gcp[ \t]+\| GCP Assessor' -Replacement '| gcp | Wrong Assessor'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a retirement record with an undeclared field' {
        $root = New-Fixture 'connector-retirement-open-schema'
        Use-ConnectorReplacementState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Remove-ConnectorBindingFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'decisions.md') -Pattern '"confirmed": true' -Replacement '"unexpected": true, "confirmed": true'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects an entry heading not covered by the confirmed retirement' {
        $root = New-Fixture 'connector-retirement-unlisted-entry'
        Use-ConnectorReplacementState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Remove-ConnectorBindingFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'history/Squad Connector.md') -Pattern '(?m)^## .+' -Replacement '## 2026-08-21T10:00:00Z Unregistered later dispatch'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a retired connector ledger member that differs from retained history' {
        $root = New-Fixture 'connector-retirement-wrong-ledger-member'
        Use-ConnectorReplacementState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Remove-ConnectorBindingFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'consumption.md') -Pattern '\| researcher\s+\| Org Researcher \| Squad Connector' -Replacement '| researcher    | Wrong Researcher | Squad Connector'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'does not let historical evidence hide an invalid current binding' {
        $root = New-Fixture 'connector-retirement-invalid-active-binding'
        Use-ConnectorReplacementState -Root $root
        Save-ConnectorRetirementFixture -Root $root
        Edit-Fixture -Path (Join-Path $root 'team.md') -Pattern 'role:researcher' -Replacement 'role:researcher/Missing Researcher'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a replacement target naming a missing internal member' {
        $root = New-Fixture 'connector-wrong-target-member'
        Use-ConnectorReplacementState -Root $root
        Edit-Fixture -Path (Join-Path $root 'team.md') -Pattern 'role:researcher' -Replacement 'role:researcher/Missing Researcher'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Connector.md') -Pattern 'role:researcher' -Replacement 'role:researcher/Missing Researcher'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a malformed connector role target' {
        $root = New-Fixture 'connector-malformed-target'
        Use-ConnectorReplacementState -Root $root
        Edit-Fixture -Path (Join-Path $root 'team.md') -Pattern 'role:researcher' -Replacement 'researcher'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Connector.md') -Pattern 'role:researcher' -Replacement 'researcher'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a connector binding whose manifest is missing' {
        $root = New-Fixture 'connector-missing-manifest'
        Use-ConnectorReplacementState -Root $root
        Edit-Fixture -Path (Join-Path $root 'team.md') -Pattern 'connectors/manifest\.research-agent\.1\.1\.json' -Replacement 'connectors/missing.json'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a connector id that does not match the manifest' {
        $root = New-Fixture 'connector-mismatched-id'
        Use-ConnectorReplacementState -Root $root
        Edit-Fixture -Path (Join-Path $root 'team.md') -Pattern 'acme-research-agent' -Replacement 'wrong-research-agent'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Connector.md') -Pattern 'acme-research-agent' -Replacement 'wrong-research-agent'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a blank connector binding id' {
        $root = New-Fixture 'connector-blank-binding'
        Use-ConnectorReplacementState -Root $root
        Edit-Fixture -Path (Join-Path $root 'team.md') -Pattern '\| research-org \|' -Replacement '|  |'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects conflicting duplicate connector bindings' {
        $root = New-Fixture 'connector-duplicate-binding'
        Use-ConnectorReplacementState -Root $root
        Add-Content -LiteralPath (Join-Path $root 'team.md') -Encoding utf8NoBOM -Value '| research-org | acme-research-agent | connectors/manifest.research-agent.1.1.json | agent | replace | role | role:researcher | Other Researcher | | researcher | ask |'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a connector history member that does not match its binding' {
        $root = New-Fixture 'connector-wrong-history-member'
        Use-ConnectorReplacementState -Root $root
        Edit-Fixture -Path (Join-Path $root 'history/Squad Connector.md') -Pattern '\* Member Name: Org Researcher' -Replacement '* Member Name: Wrong Researcher'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a connector history binding id that does not resolve exactly' {
        $root = New-Fixture 'connector-wrong-history-binding'
        Use-ConnectorReplacementState -Root $root
        Edit-Fixture -Path (Join-Path $root 'history/Squad Connector.md') -Pattern 'binding=research-org' -Replacement 'binding=other-binding'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects a connector ledger member that differs from history' {
        $root = New-Fixture 'connector-wrong-ledger-member'
        Use-ConnectorReplacementState -Root $root
        Edit-Fixture -Path (Join-Path $root 'consumption.md') -Pattern '\| researcher\s+\| Org Researcher \| Squad Connector' -Replacement '| researcher    | Wrong Researcher | Squad Connector'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'rejects an additive binding whose connector Members row is missing' {
        $root = New-Fixture 'connector-orphan-additive'
        Use-ConnectorAdditiveState -Root $root
        Edit-Fixture -Path (Join-Path $root 'team.md') -Pattern '(?m)^\| gcp[ \t]+\| GCP Assessor[^\r\n]*\r?\n' -Replacement ''
        (Test-Contract $root).Passed | Should -BeFalse
    }
}

Describe 'The contract catches a broken tree' {
    It 'catches an undocumented preflight decision' {
        $root = New-Fixture 'bad-preflight-decision'
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"decision": "within-ceiling"' -Replacement '"decision": "probably"'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches low confidence that still admits dispatch' {
        $root = New-Fixture 'low-confidence-admission'
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"confidence": "medium"' -Replacement '"confidence": "low"'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'low confidence fails closed as cannot-confirm'
    }

    It 'catches an admission cost below the factor-of-three reserve' {
        $root = New-Fixture 'under-reserved-preflight'
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"admissionCostUsd": 4\.2728' -Replacement '"admissionCostUsd": 1.4243'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'the point estimate is not the admission reserve'
    }

    It 'catches remaining budget that ignores evaluated spend' {
        $root = New-Fixture 'bad-preflight-remaining'
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"evaluatedSpendUsd": 0\.0' -Replacement '"evaluatedSpendUsd": 2.0'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches a missing readable preflight decision' {
        $root = New-Fixture 'missing-preflight-record'
        Edit-Fixture -Path (Join-Path $root 'decisions.md') `
            -Pattern '## Cost Preflight 2026-08-19T09:59:59Z fixture-001 round-001' `
            -Replacement '## Cost Forecast Without Binding Identity'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'machine state must resolve to the readable demand record'
    }

    It 'catches a child dispatched outside the permitted set' {
        $root = New-Fixture 'forbidden-preflight-slot'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Researcher.md') `
            -Pattern 'Cost Preflight Slot: researcher-1' -Replacement 'Cost Preflight Slot: developer-1'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches a dispatch recorded after an over-ceiling decision' {
        $root = New-Fixture 'dispatch-after-denial'
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"decision": "within-ceiling"' -Replacement '"decision": "over-ceiling"'
        Edit-Fixture -Path (Join-Path $root 'decisions.md') `
            -Pattern '\* Decision: within-ceiling' -Replacement '* Decision: over-ceiling'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a non-admitting round permits no later child dispatch'
    }

    It 'catches an approved round without its prior over-ceiling decision' {
        $root = New-Fixture 'approval-without-denial'
        Add-ApprovedOverCeilingRound -Root $root
        Edit-Fixture -Path (Join-Path $root 'decisions.md') `
            -Pattern '\* Decision: over-ceiling' -Replacement '* Decision: within-ceiling'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'bounded consent must reference an immutable over-ceiling decision'
    }

    It 'catches an approved round created at the ceiling boundary' {
        $root = New-Fixture 'approval-at-boundary'
        Add-ApprovedOverCeilingRound -Root $root
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"evaluatedSpendUsd": 0\.0' -Replacement '"evaluatedSpendUsd": 0.09'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'approval never starts another dispatch at or above the ceiling'
    }

    It 'catches low confidence disguised as an approved over-ceiling round' {
        $root = New-Fixture 'low-confidence-approval'
        Add-ApprovedOverCeilingRound -Root $root
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"confidence": "medium"' -Replacement '"confidence": "low"'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'cannot-confirm is never approvable'
    }

    It 'catches approved demand that drifted from the denied manifest' {
        $root = New-Fixture 'approval-demand-drift'
        Add-ApprovedOverCeilingRound -Root $root
        Edit-Fixture -Path (Join-Path $root 'decisions.md') `
            -Pattern '(?s)(\* Decision: approved-over-ceiling.*?\* Evaluated Dispatch Set:) coordinator-1, researcher-1, scribe-1' `
            -Replacement '$1 coordinator-1, researcher-1, developer-1, scribe-1'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'approval binds to the exact denied demand inputs'
    }

    It 'catches a child dispatch timestamped after the ceiling-reached round' {
        $root = New-Fixture 'dispatch-after-ceiling'
        Add-ApprovedOverCeilingRound -Root $root
        Add-CeilingReachedRound -Root $root
        Edit-Fixture -Path (Join-Path $root 'history/Squad Researcher.md') `
            -Pattern '2026-08-19T10:00:03Z' -Replacement '2026-08-19T10:00:07Z'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'no substantive child starts after accumulated estimated spend reaches the ceiling'
    }

    It 'catches a not-requested state that retains a ceiling' {
        $root = New-Fixture 'unset-retains-ceiling'
        Use-NoCeilingState -Root $root
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"ceilingUsd": null' -Replacement '"ceilingUsd": 10.0'
        (Test-Contract -Root $root -InitOnly).Passed | Should -BeFalse -Because 'unset removes the compact ceiling instead of leaving an ambiguous guard'
    }

    It 'catches a preflight slot consumed twice' {
        $root = New-Fixture 'replayed-preflight-slot'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Scribe.md') `
            -Pattern 'Cost Preflight Slot: scribe-1' -Replacement 'Cost Preflight Slot: researcher-1'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'one reservation slot authorizes one dispatch'
    }

    It 'catches aggregate federation spend that drops completed meta slots' {
        $root = New-FederationPreflightFixture 'federation-dropped-meta'
        Edit-Fixture -Path (Join-Path $root 'state.json') -Pattern '"estCostUsd": 2\.45' -Replacement '"estCostUsd": 2.0'
        Test-FederationPreflightFixture $root | Should -BeFalse
    }

    It 'catches federation spend reconstructed from only the latest preflight round' {
        $root = New-FederationPreflightFixture 'federation-latest-round-only'
        Edit-Fixture -Path (Join-Path $root 'state.json') -Pattern '"estCostUsd": 2\.45' -Replacement '"estCostUsd": 2.25'
        Test-FederationPreflightFixture $root | Should -BeFalse -Because 'completed meta slots remain cumulative when later manifests shrink'
    }

    It 'catches aggregate federation admission without its root rate table' {
        $root = New-FederationPreflightFixture 'federation-no-rates'
        Remove-Item -LiteralPath (Join-Path $root 'consumption-rates.md') -Force
        Test-FederationPreflightFixture $root | Should -BeFalse
    }

    It 'catches federation state that drops its approval channel' {
        $root = New-FederationPreflightFixture 'federation-no-notify'
        $statePath = Join-Path $root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state.Remove('notify')
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
        Test-FederationPreflightFixture $root | Should -BeFalse
    }

    It 'catches automatic model routing in an admitted manifest' {
        $root = New-Fixture 'auto-preflight-model'
        Edit-Fixture -Path (Join-Path $root 'decisions.md') `
            -Pattern 'Claude Sonnet 4\.6 \| 3 \| 20000' -Replacement 'auto | 3 | 20000'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'auto cannot support medium-confidence pre-dispatch pricing'
    }

    It 'catches a model with no rate row in an admitted manifest' {
        $root = New-Fixture 'unrated-preflight-model'
        Edit-Fixture -Path (Join-Path $root 'decisions.md') `
            -Pattern 'Claude Sonnet 4\.6 \| 3 \| 20000' -Replacement 'Future Model | 3 | 20000'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches an incomplete dispatch class in an admitted manifest' {
        $root = New-Fixture 'incomplete-preflight-class'
        Edit-Fixture -Path (Join-Path $root 'decisions.md') `
            -Pattern 'Lookup / single-file read' -Replacement 'Unmapped work'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches zero calibration observations on an admitted manifest' {
        $root = New-Fixture 'uncalibrated-preflight'
        Edit-Fixture -Path (Join-Path $root 'consumption-rates.md') `
            -Pattern 'observations: 1' -Replacement 'observations: 0'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches calibration from a different rate or estimator basis' {
        $root = New-Fixture 'stale-preflight-calibration'
        Edit-Fixture -Path (Join-Path $root 'consumption-rates.md') `
            -Pattern 'calibration_basis: "2026-08-19\|2"' -Replacement 'calibration_basis: "2026-07-01|1"'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'stale calibration cannot support medium-confidence admission'
    }

    It 'catches a missing eager state file' {
        $root = New-Fixture 'missing-ledger'
        Remove-Item -LiteralPath (Join-Path $root 'consumption.md') -Force
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches a deliverable that was never written' {
        $root = New-Fixture 'phantom-deliverable'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Researcher.md') `
            -Pattern '2026-08-19-login-validation\.md` \(410 words\)' -Replacement '2026-08-19-login-never-written.md` (410 words)'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a Deliverable path is verified by listing it, never asserted'
    }

    It 'catches an entry that declares no artifact at all' {
        $root = New-Fixture 'inline-verdict'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Researcher.md') `
            -Pattern '(?m)^\* Deliverable: .+$' -Replacement '* Deliverable: N/A - inline findings, no artifact written'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a stage that wrote no file did not run'
    }

    It 'catches a role that wrote outside its Deliverable Root' {
        $root = New-Fixture 'strayed-deliverable'
        $stray = Join-Path (Split-Path (Split-Path $root -Parent) -Parent) '.copilot-tracking/details'
        New-Item -ItemType Directory -Path $stray -Force | Out-Null
        Move-Item -LiteralPath (Join-Path (Split-Path $root -Parent) 'research/2026-08-19-login-validation.md') `
            -Destination (Join-Path $stray '2026-08-19-login-validation.md') -Force
        Edit-Fixture -Path (Join-Path $root 'history/Squad Researcher.md') `
            -Pattern '`\.copilot-tracking/research/2026-08-19-login-validation\.md` \(410 words\)' `
            -Replacement '`.copilot-tracking/details/2026-08-19-login-validation.md` (410 words)'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'the roster root overrides the path convention in the agent own definition'
    }

    # The stage ran and left its artifact, but the coordinator never handed the dispatch
    # over, so state and ledger agree with each other and with nothing that happened.
    It 'catches an artifact no history entry claims' {
        $root = New-Fixture 'orphan-artifact'
        Set-Content -Encoding utf8NoBOM -Value "# Plan`n" `
            -LiteralPath (New-Item -ItemType File -Force -Path (Join-Path (Split-Path $root -Parent) 'plans/2026-08-19-login-plan.md')).FullName
        (Test-Contract $root).Passed | Should -BeFalse -Because 'an unclaimed artifact is a dispatch nobody recorded'
    }

    It 'catches a model_tier that does not match the priced_as row' {
        $root = New-Fixture 'tier-mismatch'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Researcher.md') `
            -Pattern '"model_tier": "default"' -Replacement '"model_tier": "fast"'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a fast tier beside a default rate row prices one model and reports another'
    }

    It 'catches a dispatch sized from another dispatch numbers' {
        $root = New-Fixture 'copied-sizing'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Scribe.md') `
            -Pattern '(?s)"internal_turns": 1,\s*\r?\n\s*"input_tokens": 4000,\s*\r?\n\s*"cached_tokens": 0,\s*\r?\n\s*"cache_write_tokens": 0,\s*\r?\n\s*"output_tokens": 1000,' `
            -Replacement ('"internal_turns": 1,' + "`n  " + '"input_tokens": 10000,' + "`n  " + '"cached_tokens": 5000,' + "`n  " + '"cache_write_tokens": 1000,' + "`n  " + '"output_tokens": 2000,')
        (Test-Contract $root).Passed | Should -BeFalse -Because 'identical token counts describe one dispatch recorded twice'
    }

    It 'catches a token column total out by an order of magnitude' {
        $root = New-Fixture 'dropped-column'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '\*\*14000\*\*' -Replacement '**1400**'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'the total row is computed, never carried'
    }

    It 'catches a history entry with no consumption block' {
        $root = New-Fixture 'no-block'
        $path = Join-Path $root 'history/Squad Researcher.md'
        Set-Content -LiteralPath $path -Encoding utf8NoBOM -Value "# History: Squad Researcher`n`n## 2026-08-19T10:00:03Z Investigate`n`n* Turn: 1`n"
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a history append and its block are inseparable'
    }

    It 'catches a reordered consumption block' {
        $root = New-Fixture 'reordered'
        $path = Join-Path $root 'history/Squad Researcher.md'
        Edit-Fixture -Path $path `
            -Pattern '(?s)"model_source": "dispatch-reported",\s*\r?\n\s*"priced_as": "Claude Sonnet 4.6",' `
            -Replacement ('"priced_as": "Claude Sonnet 4.6",' + "`n  " + '"model_source": "dispatch-reported",')
        (Test-Contract $root).Passed | Should -BeFalse -Because 'the ledger rewrite reads these blocks positionally'
    }

    It 'catches a token count that is not a bare number' {
        $root = New-Fixture 'not-bare'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Researcher.md') `
            -Pattern '"input_tokens": 10000' -Replacement '"input_tokens": "~10,000 (estimated)"'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'an unparseable field drops that dispatch out of every later aggregate'
    }

    It 'catches a ledger cost that does not follow from its tokens and rates' {
        $root = New-Fixture 'bad-arithmetic'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '0\.0653' -Replacement '0.5000'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches a priced_as that names no rate row' {
        $root = New-Fixture 'rate-drift'
        Edit-Fixture -Path (Join-Path $root 'history/Squad Researcher.md') `
            -Pattern '"priced_as": "Claude Sonnet 4.6"' -Replacement '"priced_as": "claude-sonnet-4-6"'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'only consumption-rates.md holds token rates and a slug matches no row'
    }

    It 'catches a rate row swapped under a ledger row' {
        $root = New-Fixture 'ledger-rate-swap'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern 'dispatch-reported \| Claude Sonnet 4\.6 \| default' `
            -Replacement 'dispatch-reported | Claude Haiku 4.5  | fast   '
        (Test-Contract $root).Passed | Should -BeFalse -Because 'the row is priced from the model its Attribution row names'
    }

    It 'catches missing orchestration overhead' {
        $root = New-Fixture 'no-orchestration'
        Remove-Item -LiteralPath (Join-Path $root 'history/Squad Scribe.md') -Force
        (Test-Contract $root).Passed | Should -BeFalse -Because 'without it the ledger omits the cost of running the squad itself'
    }

    It 'catches a run total that dropped an earlier role' {
        $root = New-Fixture 'dropped-role'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '\*\*0\.0923\*\*' -Replacement '**0.0270**'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'this is exactly the payload-only rewrite the Scribe procedure warns about'
    }

    It 'catches an orchestration row that skipped a recorded block' {
        $root = New-Fixture 'partial-orchestration'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '\| 0\.0270 +\| 2\.70' -Replacement '| 0.0010          | 0.10'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'the row is the sum of every orchestration block, not the latest one'
    }

    It 'catches a history file named by role id instead of agent name' {
        $root = New-Fixture 'slugified-history'
        Move-Item -LiteralPath (Join-Path $root 'history/Squad Researcher.md') `
            -Destination (Join-Path $root 'history/researcher.md')
        (Test-Contract $root).Passed | Should -BeFalse -Because 'the filename is how a later turn matches an entry back to its roster row'
    }

    It 'catches a rate table the contract cannot read' {
        $root = New-Fixture 'unreadable-rates'
        Edit-Fixture -Path (Join-Path $root 'consumption-rates.md') `
            -Pattern '\| Cache write \|' -Replacement '| Cache-write |'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a table that does not parse makes every rate assertion vacuous'
    }

    It 'catches history files seeded before the first dispatch' {
        $root = New-Fixture 'init-with-history'
        (Test-Contract -Root $root -InitOnly).Passed | Should -BeFalse -Because 'a history file that predates its dispatch is indistinguishable from one that recorded it'
    }

    It 'catches a roster that lists alternates without their cue' {
        $root = New-Fixture 'no-selection-cue'
        Edit-Fixture -Path (Join-Path $root 'team.md') `
            -Pattern '\| Selection Cue\s+' -Replacement '| Alternate Cue '
        (Test-Contract $root).Passed | Should -BeFalse -Because 'knowing an alternate exists is not knowing when it applies'
    }

    It 'catches a ledger row for a role that was never dispatched' {
        $root = New-Fixture 'idle-role-row'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '(?m)^\| orchestration \| 1 ' `
            -Replacement "| lead          | 0     | 0         | 0      | 0        | 0          | 0.0000          | 0.00         | estimated |`n| orchestration | 1 "
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a zero row makes a stale ledger look populated'
    }

    It 'catches a priced ledger row whose agent left no history file' {
        $root = New-Fixture 'invented-role-row'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '(?m)^\| orchestration \| 1 ' `
            -Replacement "| lead          | 4     | 20000     | 10000  | 0        | 4000       | 0.1230          | 12.30        | estimated |`n| orchestration | 1 "
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a plausible cost is what makes an invented row invisible to the zero-row check'
    }

    It 'catches per-turn figures parked in state.json' {
        $root = New-Fixture 'state-scratchpad'
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"estCreditsTotal": 9.225' `
            -Replacement ('"estCreditsTotal": 9.225,' + "`n    " + '"turn1_consumption": { "tokens": "moderate" }')
        (Test-Contract $root).Passed | Should -BeFalse -Because 'currentRun is a running total, not a scratchpad'
    }

    It 'catches a file written with a read tool line-number gutter' {
        $root = New-Fixture 'numbered-lines'
        $path = Join-Path $root 'history/Squad Researcher.md'
        $lines = @(Get-Content -LiteralPath $path)
        $numbered = @(for ($n = 1; $n -le $lines.Count; $n++) { "$n. $($lines[$n - 1])" })
        Set-Content -LiteralPath $path -Value $numbered -Encoding utf8NoBOM
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a gutter that reads as content leaves the file parseable to nobody'
    }

    It 'catches an undocumented autonomy mode' {
        $root = New-Fixture 'bad-mode'
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"mode": "interactive"' -Replacement '"mode": "turbo"'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches state.json totals that disagree with the ledger' {
        $root = New-Fixture 'state-drift'
        Edit-Fixture -Path (Join-Path $root 'state.json') `
            -Pattern '"estCostUsd": 0.09225' -Replacement '"estCostUsd": 0'
        (Test-Contract $root).Passed | Should -BeFalse
    }

    It 'catches a priced row whose arithmetic the ledger never shows' {
        $root = New-Fixture 'unshown-derivation'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '(?m)^orchestration\s+turns .*$' -Replacement ''
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a cost written without its products is indistinguishable from a guess'
    }

    It 'catches a comparison that reports spend without the saving' {
        $root = New-Fixture 'no-saving'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '\u2014 a saving of about \*\*62%\*\*' -Replacement '.'
        (Test-Contract $root).Passed | Should -BeFalse -Because 'the saving is the number the operator actually reads'
    }

    It 'tolerates a ledger figure that is merely imprecise' {
        $root = New-Fixture 'imprecise-cost'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '\| 0\.0653 ' -Replacement '| 0.0700 '
        (Test-Contract $root).Passed | Should -BeTrue -Because 'every figure is an estimate and only an order-of-magnitude slip corrupts a decision'
    }

    It 'catches a ledger figure out by an order of magnitude' {
        $root = New-Fixture 'tenfold-cost'
        Edit-Fixture -Path (Join-Path $root 'consumption.md') `
            -Pattern '\| 0\.0653 ' -Replacement '| 0.6530 '
        (Test-Contract $root).Passed | Should -BeFalse -Because 'dividing by 1e6 twice is the documented corruption'
    }

    It 'catches a tracking directory nested inside the tracking directory' {
        $root = New-Fixture 'nested-tracking'
        New-Item -ItemType Directory -Force -Path (Join-Path (Split-Path $root -Parent) '.copilot-tracking/squad/members/product/plans') | Out-Null
        (Test-Contract $root).Passed | Should -BeFalse -Because 'a state path is written from the project root and can never contain .copilot-tracking twice'
    }
}
