#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadRun.psm1') -Force
    $script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) "hve-squad-connector-resume-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:Scratch -Force | Out-Null
}

AfterAll {
    if ($script:Scratch -and (Test-Path -LiteralPath $script:Scratch)) {
        Remove-Item -LiteralPath $script:Scratch -Recurse -Force
    }
}

Describe 'CONN-28 connector resume live harness' {
    It 'ships a scenario that captures both connector dispatch turns and attaches a deterministic consumer' {
        $scenario = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'scenarios/connector-resume.json') -Raw | ConvertFrom-Json
        $scenario.connectorResumeIntegrity | Should -Not -BeNullOrEmpty
        $requestTurn = @($scenario.turns | Where-Object id -eq $scenario.connectorResumeIntegrity.requestTurn)
        $resumeTurn = @($scenario.turns | Where-Object id -eq $scenario.connectorResumeIntegrity.resumeTurn)
        $requestTurn.Count | Should -Be 1
        $resumeTurn.Count | Should -Be 1
        $requestTurn[0].captureDispatchEvents | Should -BeTrue
        $resumeTurn[0].captureDispatchEvents | Should -BeTrue
        $requestTurn[0].connectorConsumer.connectorId | Should -Be 'tier1-research-agent'
    }

    It 'publishes a result without rewriting the request or snapshot' {
        $workspace = Join-Path $script:Scratch 'publish'
        $dropPath = Join-Path $workspace '.connector-drops/tier1-research-agent'
        New-Item -ItemType Directory -Path $dropPath -Force | Out-Null
        $request = [ordered]@{
            taskId          = 'task-resume-001'
            connectorId     = 'tier1-research-agent'
            role            = 'researcher'
            deliverableRoot = '.copilot-tracking/research'
            bindingId       = 'tier1-research'
            targetKind      = 'role'
            executionChoice = 'connector:tier1-research'
            allowedOutputs  = @(
                [ordered]@{
                    outputId       = 'research-note'
                    role           = 'researcher'
                    memberName     = 'Tier1 Research Partner'
                    deliverableRoot = '.copilot-tracking/research'
                }
            )
            task             = 'Write one bounded research note.'
            deadline         = '2026-10-19T12:00:00Z'
            retryCap         = 2
            createdAt        = '2026-10-19T11:00:00Z'
        }
        $requestPath = Join-Path $dropPath 'task-resume-001.request.json'
        $snapshotPath = Join-Path $dropPath 'task-resume-001.snapshot.json'
        $request | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $requestPath -Encoding utf8NoBOM
        [ordered]@{
            taskId          = $request.taskId
            deliverableRoot = $request.deliverableRoot
            preExistingPaths = @()
            createdAt       = $request.createdAt
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $snapshotPath -Encoding utf8NoBOM
        $requestHash = (Get-FileHash -LiteralPath $requestPath -Algorithm SHA256).Hash
        $snapshotHash = (Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash

        $record = Publish-ConnectorConsumerResult -Workspace $workspace -ConnectorId 'tier1-research-agent' `
            -ArtifactPath 'connector-resume.md' -ArtifactContent '# Result' -Narrative 'Completed.'

        $record.RequestHash | Should -Be $requestHash
        $record.SnapshotHash | Should -Be $snapshotHash
        (Get-FileHash -LiteralPath $requestPath -Algorithm SHA256).Hash | Should -Be $requestHash
        (Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash | Should -Be $snapshotHash
        Test-Path -LiteralPath $record.ResultPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $record.ArtifactPath -PathType Leaf | Should -BeTrue
    }

    It 'counts machine dispatch events and ignores matching model prose' {
        $transcript = Join-Path $script:Scratch 'events.jsonl'
        @(
            'I dispatched Squad Connector and Squad Scribe.'
            '{"type":"tool.execution_start","tool":"task","arguments":{"agent":"Squad Connector"}}'
            '{"type":"tool.execution_complete","tool":"task","result":{"agent":"Squad Connector"}}'
        ) | Set-Content -LiteralPath $transcript -Encoding utf8NoBOM

        $connector = @(Get-SquadDispatchEvidence -TranscriptPath $transcript -AgentName 'Squad Connector')
        $scribe = @(Get-SquadDispatchEvidence -TranscriptPath $transcript -AgentName 'Squad Scribe')
        $connector.Count | Should -Be 1
        $scribe.Count | Should -Be 0
    }
}
