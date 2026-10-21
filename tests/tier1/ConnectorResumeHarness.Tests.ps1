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
        $resumeTurn[0].prompt | Should -Not -Match 'Squad Connector|Scribe|Invoke-Squad|taskId|validation inline'
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

    It 'rejects script calls and other-agent prompts that merely mention the Connector' {
        $transcript = Join-Path $script:Scratch 'inline-events.jsonl'
        @(
            '{"type":"tool.execution_start","tool":"powershell","arguments":{"command":"Invoke-SquadConnectorDispatch.ps1 # Squad Connector task-original"}}'
            '{"type":"tool.execution_start","tool":"task","arguments":{"agent":"Squad Scribe","prompt":"Record the Squad Connector task-original result."}}'
            '{"type":"tool.execution_complete","tool":"task","result":{"agent":"Squad Connector","taskId":"task-original"}}'
        ) | Set-Content -LiteralPath $transcript
        @(Get-SquadDispatchEvidence -TranscriptPath $transcript -AgentName 'Squad Connector').Count | Should -Be 0
    }

    It 'binds resume evidence to the exact native agent and original task id' {
        $transcript = Join-Path $script:Scratch 'bound-events.jsonl'
        @(
            '{"type":"tool.execution_start","data":{"toolName":"task","arguments":{"agent_type":"hve-squad:squad-connector","prompt":"Resume task-original with unchanged inputs."}}}'
            '{"type":"subagent.started","data":{"agentName":"Squad Connector","prompt":"Resume task-original"}}'
        ) | Set-Content -LiteralPath $transcript
        @(Get-SquadDispatchEvidence -TranscriptPath $transcript -AgentName 'Squad Connector' -TaskId 'task-original').Count | Should -Be 2
        @(Get-SquadDispatchEvidence -TranscriptPath $transcript -AgentName 'Squad Connector' -TaskId 'task-other').Count | Should -Be 0
    }

    It 'CONN-35 counts every wrapper attempt inside its actual native child, not eventual success alone' {
        $transcript = Join-Path $script:Scratch 'attempt-events.jsonl'
        @(
            '{"type":"subagent.started","agentId":"connector-child","data":{"agentName":"Squad Connector","toolCallId":"dispatch-1","model":"claude-sonnet-5.5","taskModelSource":"custom_agent_definition","modelSelectionSource":"agent_definition_default"}}'
            '{"type":"tool.execution_start","agentId":"connector-child","data":{"toolName":"powershell","toolCallId":"attempt-1","arguments":{"command":"& scripts\\Invoke-SquadConnectorDispatch.ps1 -InputJson $j"}}}'
            '{"type":"tool.execution_start","agentId":"connector-child","data":{"toolName":"powershell","toolCallId":"attempt-2","arguments":{"command":"& scripts\\Invoke-SquadConnectorDispatch.ps1 -InputJson $j"}}}'
            '{"type":"tool.execution_start","agentId":"connector-child","data":{"toolName":"powershell","toolCallId":"attempt-3","arguments":{"command":"& scripts\\Invoke-SquadConnectorDispatch.ps1 -InputJson $j"}}}'
            '{"type":"tool.execution_start","agentId":"connector-child","data":{"toolName":"powershell","toolCallId":"attempt-4","arguments":{"command":"& scripts\\Invoke-SquadConnectorDispatch.ps1 -InputPath dispatch.json"}}}'
            '{"type":"tool.execution_complete","agentId":"connector-child","data":{"toolName":"powershell","toolCallId":"attempt-4","result":{"status":"completed"}}}'
        ) | Set-Content -LiteralPath $transcript
        $evidence = @(Get-SquadConnectorExecutionEvidence -TranscriptPath $transcript)
        $evidence.Count | Should -Be 1
        $evidence[0].WrapperCallCount | Should -Be 4
        $evidence[0].Model | Should -Be 'claude-sonnet-5.5'
        $evidence[0].ModelSelectionSource | Should -Be 'agent_definition_default'
    }

    It 'CONN-35 deduplicates copied event logs and excludes other agents, inline calls, and script reads' {
        $directory = Join-Path $script:Scratch 'copied-events'
        [void][System.IO.Directory]::CreateDirectory($directory)
        $transcript = Join-Path $directory 'events.jsonl'
        @(
            '{"type":"subagent.started","agentId":"connector-child","data":{"agentName":"Squad Connector","toolCallId":"dispatch-1"}}'
            '{"type":"tool.execution_start","agentId":"connector-child","data":{"toolName":"powershell","toolCallId":"read-1","arguments":{"command":"Get-Content scripts\\Invoke-SquadConnectorDispatch.ps1"}}}'
            '{"type":"tool.execution_start","agentId":"other-child","data":{"toolName":"powershell","toolCallId":"other-1","arguments":{"command":"& scripts\\Invoke-SquadConnectorDispatch.ps1 -InputJson $j"}}}'
            '{"type":"tool.execution_start","data":{"toolName":"powershell","toolCallId":"inline-1","arguments":{"command":"& scripts\\Invoke-SquadConnectorDispatch.ps1 -InputJson $j"}}}'
            '{"type":"tool.execution_start","data":{"toolName":"powershell","toolCallId":"attempt-1","parentToolCallId":"dispatch-1","arguments":{"command":"pwsh -File \"scripts\\Invoke-SquadConnectorDispatch.ps1\" -InputPath dispatch.json"}}}'
        ) | Set-Content -LiteralPath $transcript
        Copy-Item -LiteralPath $transcript -Destination (Join-Path $directory 'copy.jsonl')
        $evidence = @(Get-SquadConnectorExecutionEvidence -TranscriptPath $transcript -LogDir $directory)
        $evidence.Count | Should -Be 1
        $evidence[0].WrapperCallCount | Should -Be 1
    }

    It 'CONN-35 counts multiple invocations even when one shell call contains them' {
        $transcript = Join-Path $script:Scratch 'combined-attempts.jsonl'
        @(
            '{"type":"subagent.started","agentId":"connector-child","data":{"agentName":"Squad Connector","toolCallId":"dispatch-1"}}'
            '{"type":"tool.execution_start","agentId":"connector-child","data":{"toolName":"powershell","toolCallId":"combined","arguments":{"command":"& scripts\\Invoke-SquadConnectorDispatch.ps1 -InputJson $first; & scripts\\Invoke-SquadConnectorDispatch.ps1 -InputJson $second"}}}'
        ) | Set-Content -LiteralPath $transcript
        $evidence = @(Get-SquadConnectorExecutionEvidence -TranscriptPath $transcript)
        $evidence.Count | Should -Be 1
        $evidence[0].WrapperCallCount | Should -Be 2
    }
}
