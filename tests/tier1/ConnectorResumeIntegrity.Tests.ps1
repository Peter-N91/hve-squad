#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

param(
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [Parameter(Mandatory)][string]$SquadRoot,
    [Parameter(Mandatory)][string]$RequestTranscript,
    [Parameter(Mandatory)][string]$RequestLogDir,
    [Parameter(Mandatory)][string]$ResumeTranscript,
    [Parameter(Mandatory)][string]$ResumeLogDir,
    [Parameter(Mandatory)][string]$RequestPath,
    [Parameter(Mandatory)][string]$RequestHash,
    [Parameter(Mandatory)][string]$SnapshotPath,
    [Parameter(Mandatory)][string]$SnapshotHash,
    [Parameter(Mandatory)][string]$ResultPath,
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$Artifact,
    [Parameter(Mandatory)][string]$ConnectorAgent,
    [Parameter(Mandatory)][string]$ScribeAgent
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadRun.psm1') -Force
}

Describe 'CONN-28 ordinary connector resume preserves dispatch and collision evidence' {
    It 'keeps the original request and collision snapshot byte-identical across resume' {
        (Get-FileHash -LiteralPath $RequestPath -Algorithm SHA256).Hash | Should -Be $RequestHash
        (Get-FileHash -LiteralPath $SnapshotPath -Algorithm SHA256).Hash | Should -Be $SnapshotHash
    }

    It 'keeps a closed snapshot bound to the same task and deliverable root' {
        $request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
        $snapshot = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
        @($snapshot.PSObject.Properties.Name) | Should -Be @('taskId', 'deliverableRoot', 'preExistingPaths', 'createdAt')
        $snapshot.taskId | Should -Be $TaskId
        $snapshot.taskId | Should -Be $request.taskId
        $snapshot.deliverableRoot | Should -Be $request.deliverableRoot

        $artifactPath = (Join-Path $WorkspaceRoot $Artifact)
        $artifactKey = [System.IO.Path]::GetFullPath($artifactPath).Replace('\', '/').ToLowerInvariant()
        $preExisting = @(
            $snapshot.preExistingPaths | ForEach-Object {
                $candidate = if ([System.IO.Path]::IsPathRooted([string]$_)) { [string]$_ } else { Join-Path $WorkspaceRoot ([string]$_) }
                [System.IO.Path]::GetFullPath($candidate).Replace('\', '/').ToLowerInvariant()
            }
        )
        $preExisting | Should -Not -Contain $artifactKey -Because 'the delivered artifact did not exist when the request was published'
    }

    It 'publishes the deterministic consumer result and task-owned artifact' {
        Test-Path -LiteralPath $ResultPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $WorkspaceRoot $Artifact) -PathType Leaf | Should -BeTrue
    }

    It 'records an actual Squad Connector dispatch for the first request' {
        $evidence = @(Get-SquadDispatchEvidence -TranscriptPath $RequestTranscript -LogDir $RequestLogDir -AgentName $ConnectorAgent)
        $evidence.Count | Should -BeGreaterThan 0 -Because 'an awaiting request must come from a real connector dispatch, not an inline coordinator write'
    }

    It 'records actual Squad Connector and Squad Scribe dispatches for resume' {
        $connectorEvidence = @(Get-SquadDispatchEvidence -TranscriptPath $ResumeTranscript -LogDir $ResumeLogDir -AgentName $ConnectorAgent)
        $scribeEvidence = @(Get-SquadDispatchEvidence -TranscriptPath $ResumeTranscript -LogDir $ResumeLogDir -AgentName $ScribeAgent)
        $connectorEvidence.Count | Should -BeGreaterThan 0 -Because 'the result must be validated by the roster-resolved shim'
        $scribeEvidence.Count | Should -BeGreaterThan 0 -Because 'completed connector work must be persisted by the internal Scribe'
    }

    It 'leaves connector provenance in history after the dispatched Scribe handoff' {
        $historyPath = Join-Path $SquadRoot 'history' "$ConnectorAgent.md"
        Test-Path -LiteralPath $historyPath -PathType Leaf | Should -BeTrue
        $history = Get-Content -LiteralPath $historyPath -Raw
        $history | Should -Match ([regex]::Escape('* Member Name: Tier1 Research Partner'))
        $history | Should -Match ([regex]::Escape('binding=tier1-research'))
        $history | Should -Match ([regex]::Escape('* Verification: external, unverified'))
    }
}
