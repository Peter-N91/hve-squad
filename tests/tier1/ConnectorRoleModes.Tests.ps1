#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Deterministic integration semantics for connector role-mode execution choice.
# This is intentionally offline: it exercises contract-level routing logic with
# fixture objects, no model dispatch or network calls.

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:DispatchHelper = Join-Path $repoRoot 'squad-src/.github/skills/squad/scripts/Resolve-SquadConnectorDispatch.ps1'
    . $script:DispatchHelper
    $script:RoleModes = Get-Content -LiteralPath (Join-Path $repoRoot 'squad-src/.github/skills/squad/references/connector-role-modes.md') -Raw
    # NR-004: an applicable binding admitted as `ok` must now resolve to a real, readable,
    # schema-valid manifest. Fixtures use the real shipped manifest (which authorizes
    # developer/tester/gcp) instead of a nonexistent `docs/connectors/*.md`
    # path, so these fixtures exercise genuine manifest admission rather than bypassing it.
    $script:ManifestPath = Join-Path $repoRoot 'docs/templates/connector-example/manifest.1.1.json'

    function New-MemberRow {
        param(
            [string]$Role = 'developer',
            [string]$Agent = 'Squad Implementor',
            [string]$MemberName = 'Gamma'
        )
        [pscustomobject]@{
            Role       = $Role
            Agent      = $Agent
            MemberName = $MemberName
        }
    }

    function New-Binding {
        param(
            [string]$BindingId,
            [string]$ConnectorId = 'acme-delivery-orchestrator-v3',
            [string]$ManifestPath = $script:ManifestPath,
            [string]$MemberName = 'Partner Developer',
            [string]$DefaultExecution = 'ask',
            [string]$TargetKind = 'role',
            [string]$EndpointKind = 'orchestrator',
            [string]$RoleMode = 'replace',
            [string]$AddedRole = '',
            [string]$AlignedRole = 'developer',
            [string]$Target = 'role:developer/Gamma'
        )
        [pscustomobject]@{
            BindingId        = $BindingId
            ConnectorId      = $ConnectorId
            ManifestPath     = $ManifestPath
            MemberName       = $MemberName
            DefaultExecution = $DefaultExecution
            TargetKind       = $TargetKind
            EndpointKind     = $EndpointKind
            RoleMode         = $RoleMode
            AddedRole        = $AddedRole
            AlignedRole      = $AlignedRole
            Target           = $Target
        }
    }

    function Invoke-ResolveExecutionFixture {
        param(
            [AllowNull()][string]$ExecutionChoice,
            [Parameter(Mandatory)][string]$Role,
            [AllowEmptyString()][string]$Owner = '',
            [AllowEmptyString()][string]$MemberName = '',
            [AllowEmptyCollection()][object[]]$Members = @(),
            [AllowEmptyCollection()][object[]]$Bindings = @(),
            [switch]$Unattended,
            [switch]$ParallelEligible,
            [switch]$CouncilDispatch,
            [switch]$AdmissionApproved,
            [AllowEmptyCollection()][object[]]$AllowedOutputs = @()
        )
        if (-not $Members -or $Members.Count -eq 0) {
            $Members = @(
                New-MemberRow -Role 'developer' -Agent 'Squad Implementor' -MemberName 'Gamma'
            )
        }
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('| Role | Agent Name (Primary) | Member Name |')
        $lines.Add('| --- | --- | --- |')
        foreach ($memberRow in $Members) {
            $lines.Add("| $([string]$memberRow.Role) | $([string]$memberRow.Agent) | $([string]$memberRow.MemberName) |")
        }
        if ($Bindings.Count -gt 0) {
            $lines.Add('')
            $lines.Add('| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |')
            $lines.Add('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |')
            foreach ($binding in $Bindings) {
                $manifestColumn = if ([string]$binding.ManifestPath) { [string]$binding.ManifestPath } else { $script:ManifestPath }
                $lines.Add("| $([string]$binding.BindingId) | $([string]$binding.ConnectorId) | $manifestColumn | $([string]$binding.EndpointKind) | $([string]$binding.RoleMode) | $([string]$binding.TargetKind) | $([string]$binding.Target) | $([string]$binding.MemberName) | $([string]$binding.AddedRole) | $([string]$binding.AlignedRole) | $([string]$binding.DefaultExecution) |")
            }
        }
        $teamPath = Join-Path ([System.IO.Path]::GetTempPath()) ("connector-role-modes-{0}.md" -f [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllLines($teamPath, $lines)
        try {
            Resolve-SquadConnectorExecution -TeamPath $teamPath -Role $Role -Owner $Owner -MemberName $MemberName -Execution $ExecutionChoice -AllowedOutputs @($AllowedOutputs) -Unattended:$Unattended -ParallelEligible:$ParallelEligible -CouncilDispatch:$CouncilDispatch -AdmissionApproved:$AdmissionApproved
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }
}

Describe 'connector autopilot defaults apply to ordinary work roles' -Tag 'Unit' {
    It 'automatically selects agent and orchestrator endpoints for <Role> without an execution flag' -ForEach @(
        @{ Role = 'researcher'; Primary = 'Squad Researcher' },
        @{ Role = 'lead'; Primary = 'Squad Lead' },
        @{ Role = 'developer'; Primary = 'Squad Implementor' },
        @{ Role = 'tester'; Primary = 'Squad Reviewer' },
        @{ Role = 'architect'; Primary = 'System Architecture Reviewer' },
        @{ Role = 'azure-architect'; Primary = 'Squad Azure Architect' },
        @{ Role = 'technical-writer'; Primary = 'Squad Technical Writer' }
    ) {
        foreach ($kind in @('agent', 'orchestrator')) {
            $manifest = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json
            $manifest.endpointKind = $kind
            $manifest.roles = @($Role)
            $manifestPath = Join-Path $TestDrive "$Role-$kind.json"
            $manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
            $binding = New-Binding -BindingId "$Role-org" -ManifestPath $manifestPath -EndpointKind $kind -Target "role:$Role/Original" -DefaultExecution 'connector' -MemberName "Org $Role"
            $members = @(New-MemberRow -Role $Role -Agent $Primary -MemberName 'Original')
            $resolved = Invoke-ResolveExecutionFixture -Role $Role -Members $members -Bindings @($binding) -Unattended
            $resolved.Status | Should -Be 'ok' -Because ($resolved | ConvertTo-Json -Depth 10)
            $resolved.Choice | Should -Be "connector:$Role-org"
            $resolved.Agent | Should -Be 'Squad Connector'
            $resolved.MemberName | Should -Be "Org $Role"
            $resolved.EndpointKind | Should -Be $kind
        }
    }
}

Describe 'connector execution choice precedence and fail-closed ambiguity' {
    It 'retains the original endpoint: explicit original wins over a connector default' {
        $binding = New-Binding -BindingId 'developer-delivery-orchestrator' -DefaultExecution 'connector'
        $resolved = Invoke-ResolveExecutionFixture -ExecutionChoice 'original' -Bindings @($binding) -Role 'developer' -MemberName 'Gamma'
        $resolved.Status | Should -Be 'ok'
        $resolved.Choice | Should -Be 'original'
    }

    It 'selects a named connector binding when explicitly requested (NR-001 identity exposure)' {
        $binding = New-Binding -BindingId 'developer-delivery-orchestrator' -DefaultExecution 'ask'
        $resolved = Invoke-ResolveExecutionFixture -ExecutionChoice 'connector:developer-delivery-orchestrator' -Bindings @($binding) -Role 'developer' -MemberName 'Gamma'
        $resolved.Status | Should -Be 'ok'
        $resolved.Choice | Should -Be 'connector:developer-delivery-orchestrator'
        $resolved.BindingId | Should -Be 'developer-delivery-orchestrator'
        $resolved.Agent | Should -Be 'Squad Connector'
        $resolved.MemberName | Should -Be 'Partner Developer'
        $resolved.MemberName | Should -Not -Be 'Gamma'
    }

    It 'fails closed on explicit connector binding-id that is not applicable' {
        $binding = New-Binding -BindingId 'developer-delivery-orchestrator' -DefaultExecution 'ask'
        $resolved = Invoke-ResolveExecutionFixture -ExecutionChoice 'connector:other-binding' -Bindings @($binding) -Role 'developer' -MemberName 'Gamma'
        $resolved.Status | Should -Be 'error'
        $resolved.Reason | Should -Be 'unknown-connector-binding'
    }

    It 'fails closed on explicit connector and both when no binding exists' {
        $connector = Invoke-ResolveExecutionFixture -ExecutionChoice 'connector:developer-delivery-orchestrator' -Role 'developer' -MemberName 'Gamma'
        $connector.Status | Should -Be 'error'
        $connector.Reason | Should -Be 'unknown-connector-binding'

        $both = Invoke-ResolveExecutionFixture -ExecutionChoice 'both' -Role 'developer' -MemberName 'Gamma' -ParallelEligible -AdmissionApproved -AllowedOutputs @(
            @{ outputId = 'implementation-note'; deliverableRoot = 'changes/impl' },
            @{ outputId = 'validation-note'; deliverableRoot = 'changes/validation' }
        )
        $both.Status | Should -Be 'error'
        $both.Reason | Should -Be 'both-missing-connector-binding'
    }

    It 'applies exactly one non-ask default when execution is omitted' {
        $binding = New-Binding -BindingId 'developer-delivery-orchestrator' -DefaultExecution 'connector'
        $resolved = Invoke-ResolveExecutionFixture -Bindings @($binding) -Role 'developer' -MemberName 'Gamma'
        $resolved.Status | Should -Be 'ok'
        $resolved.Choice | Should -Be 'connector:developer-delivery-orchestrator'
        $resolved.BindingId | Should -Be 'developer-delivery-orchestrator'
    }

    It 'fails closed when original or both target an additive-only connector member without an internal original' {
        $members = @(
            New-MemberRow -Role 'gcp' -Agent 'Squad Connector' -MemberName 'GCP Assessor'
        )
        $binding = New-Binding -BindingId 'gcp-architecture-assessor' -ConnectorId 'acme-delivery-orchestrator-v3' -RoleMode 'add' -AddedRole 'gcp' -AlignedRole 'azure-architect' -Target 'role:gcp/GCP Assessor' -MemberName 'GCP Assessor' -DefaultExecution 'connector'

        $original = Invoke-ResolveExecutionFixture -ExecutionChoice 'original' -Members $members -Bindings @($binding) -Role 'gcp' -MemberName 'GCP Assessor'
        $original.Status | Should -Be 'error'
        $original.Reason | Should -Be 'original-missing-internal-member'

        $both = Invoke-ResolveExecutionFixture -ExecutionChoice 'both' -Members $members -Bindings @($binding) -Role 'gcp' -MemberName 'GCP Assessor' -ParallelEligible -AdmissionApproved -AllowedOutputs @(
            @{ outputId = 'a'; deliverableRoot = 'gcp/assessments' },
            @{ outputId = 'b'; deliverableRoot = 'gcp/reviews' }
        )
        $both.Status | Should -Be 'error'
        $both.Reason | Should -Be 'both-missing-internal-original'
    }

    It 'stops unattended runs on ask/ambiguous defaults instead of guessing' {
        $members = @(
            New-MemberRow -Role 'developer' -Agent 'Squad Connector' -MemberName 'Gamma'
            New-MemberRow -Role 'developer' -Agent 'Squad Connector' -MemberName 'Delta'
        )
        $bindings = @(
            New-Binding -BindingId 'connector-a' -MemberName 'Gamma' -DefaultExecution 'connector' -Target 'role:developer/Gamma'
            New-Binding -BindingId 'connector-b' -MemberName 'Delta' -DefaultExecution 'connector' -Target 'role:developer/Delta'
        )
        $resolved = Invoke-ResolveExecutionFixture -Members $members -Bindings $bindings -Role 'developer' -Unattended
        $resolved.Status | Should -Be 'error'
        $resolved.Reason | Should -Be 'unattended-member-ambiguity'
    }

    It 'returns interactive clarification when multiple connector-backed members match and run is attended' {
        $members = @(
            New-MemberRow -Role 'developer' -Agent 'Squad Connector' -MemberName 'Gamma'
            New-MemberRow -Role 'developer' -Agent 'Squad Connector' -MemberName 'Delta'
        )
        $bindings = @(
            New-Binding -BindingId 'connector-a' -MemberName 'Gamma' -DefaultExecution 'connector' -Target 'role:developer/Gamma'
            New-Binding -BindingId 'connector-b' -MemberName 'Delta' -DefaultExecution 'connector' -Target 'role:developer/Delta'
        )
        $resolved = Invoke-ResolveExecutionFixture -Members $members -Bindings $bindings -Role 'developer'
        $resolved.Status | Should -Be 'clarify'
        $resolved.Reason | Should -Be 'interactive-member-ambiguity'
    }
}

Describe '`both` constraints and coordinator/council refusal semantics' {
    It 'allows both only with parallel eligibility and independent outputs/roots' {
        $binding = New-Binding -BindingId 'developer-dual' -DefaultExecution 'both'
        $outputs = @(
            @{ outputId = 'implementation-note'; deliverableRoot = 'changes/impl' },
            @{ outputId = 'validation-note'; deliverableRoot = 'changes/validation' }
        )
        $resolved = Invoke-ResolveExecutionFixture -ExecutionChoice 'both' -Bindings @($binding) -Role 'developer' -MemberName 'Gamma' -ParallelEligible -AdmissionApproved -AllowedOutputs $outputs
        $resolved.Status | Should -Be 'ok'
        $resolved.Choice | Should -Be 'both'
    }

    It 'refuses both for council/coordinator dispatch and output collisions' {
        $binding = New-Binding -BindingId 'developer-dual' -DefaultExecution 'both'
        $independentOutputs = @(
            @{ outputId = 'a'; deliverableRoot = 'r1' },
            @{ outputId = 'b'; deliverableRoot = 'r2' }
        )
        $council = Invoke-ResolveExecutionFixture -ExecutionChoice 'both' -Bindings @($binding) -Role 'developer' -MemberName 'Gamma' -ParallelEligible -AdmissionApproved -CouncilDispatch -AllowedOutputs $independentOutputs
        $council.Status | Should -Be 'error'
        $council.Reason | Should -Be 'both-refused-council'

        $coordinatorBinding = New-Binding -BindingId 'coord-dual' -RoleMode 'replace' -TargetKind 'coordinator' -AddedRole '' -AlignedRole '' -Target 'coordinator:Squad Coordinator' -DefaultExecution 'ask' -MemberName 'Coordinator Relay'
        $coordinatorMembers = @(
            New-MemberRow -Role 'coordinator' -Agent 'Squad Coordinator' -MemberName 'Lead'
        )
        $coordinator = Invoke-ResolveExecutionFixture -ExecutionChoice 'both' -Members $coordinatorMembers -Bindings @($coordinatorBinding) -Role 'coordinator' -MemberName 'Lead' -ParallelEligible -AdmissionApproved -AllowedOutputs $independentOutputs
        $coordinator.Status | Should -Be 'error'
        $coordinator.Reason | Should -Be 'connector-protected-role'

        $collision = Invoke-ResolveExecutionFixture -ExecutionChoice 'both' -Bindings @($binding) -Role 'developer' -MemberName 'Gamma' -ParallelEligible -AdmissionApproved -AllowedOutputs @(
            @{ outputId = 'a'; deliverableRoot = 'r1' },
            @{ outputId = 'a'; deliverableRoot = 'r2' }
        )
        $collision.Status | Should -Be 'error'
        $collision.Reason | Should -Be 'both-output-id-collision'

        $rootCollision = Invoke-ResolveExecutionFixture -ExecutionChoice 'both' -Bindings @($binding) -Role 'developer' -MemberName 'Gamma' -ParallelEligible -AdmissionApproved -AllowedOutputs @(
            @{ outputId = 'a'; deliverableRoot = 'changes/shared' },
            @{ outputId = 'b'; deliverableRoot = 'changes/shared/sub' }
        )
        $rootCollision.Status | Should -Be 'error'
        $rootCollision.Reason | Should -Be 'both-output-root-collision'

        $equalRootCollision = Invoke-ResolveExecutionFixture -ExecutionChoice 'both' -Bindings @($binding) -Role 'developer' -MemberName 'Gamma' -ParallelEligible -AdmissionApproved -AllowedOutputs @(
            @{ outputId = 'a'; deliverableRoot = 'changes/same' },
            @{ outputId = 'b'; deliverableRoot = 'changes/same' }
        )
        $equalRootCollision.Status | Should -Be 'error'
        $equalRootCollision.Reason | Should -Be 'both-output-root-collision'
    }

    It 'refuses an explicit connector choice on council routes but routes a connector default to the canonical internal original (NR-003)' {
        $binding = New-Binding -BindingId 'developer-delivery-orchestrator' -DefaultExecution 'connector'

        $explicit = Invoke-ResolveExecutionFixture -ExecutionChoice 'connector:developer-delivery-orchestrator' -Bindings @($binding) -Role 'developer' -MemberName 'Gamma' -CouncilDispatch
        $explicit.Status | Should -Be 'error'
        $explicit.Reason | Should -Be 'connector-refused-council'

        # NR-003: normal council routing always selects the validated canonical internal
        # original and ignores a connector `default`/`ask` overlay; it never refuses council
        # dispatch outright just because the role route happens to carry a connector default.
        $defaulted = Invoke-ResolveExecutionFixture -Bindings @($binding) -Role 'developer' -MemberName 'Gamma' -CouncilDispatch
        $defaulted.Status | Should -Be 'ok'
        $defaulted.Reason | Should -Be 'council-canonical-original'
        $defaulted.Choice | Should -Be 'original'
        $defaulted.MemberName | Should -Be 'Gamma'
        $defaulted.Agent | Should -Be 'Squad Implementor'
    }

    It 'pins coordinator-target and canonical-council exclusions in the normative role-mode contract' {
        $script:RoleModes | Should -Match ([regex]::Escape('`both` is refused for council dispatch and for coordinator targets.'))
        $script:RoleModes | Should -Match ([regex]::Escape('Connector bindings never add, replace, or expand council membership.'))
        $script:RoleModes | Should -Match ([regex]::Escape('Council dispatch always uses internal canonical agents from roster resolution without connector overlays.'))
    }

    It 'returns connector identity and binding identity separately for both execution (NR-001)' {
        $binding = New-Binding -BindingId 'developer-dual' -ConnectorId 'acme-delivery-orchestrator-v3' -DefaultExecution 'both'
        $resolved = Invoke-ResolveExecutionFixture -ExecutionChoice 'both' -Bindings @($binding) -Role 'developer' -MemberName 'Gamma' -ParallelEligible -AdmissionApproved -AllowedOutputs @(
            @{ outputId = 'implementation-note'; deliverableRoot = 'changes/impl' },
            @{ outputId = 'validation-note'; deliverableRoot = 'changes/validation' }
        )
        $resolved.Status | Should -Be 'ok'
        $resolved.BindingId | Should -Be 'developer-dual'
        $resolved.ConnectorId | Should -Be 'acme-delivery-orchestrator-v3'
        $resolved.Agent | Should -Be 'Squad Implementor'
        $resolved.MemberName | Should -Be 'Gamma'
        $resolved.ConnectorAgent | Should -Be 'Squad Connector'
        $resolved.ConnectorMemberName | Should -Be 'Partner Developer'
        $resolved.ConnectorMemberName | Should -Not -Be $resolved.MemberName
    }
}
