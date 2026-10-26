#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll.') ]
param([Parameter(Mandatory)][string]$PackageRoot)

BeforeAll {
    $script:Module = Join-Path $PackageRoot '.agents/skills/squad/scripts/SquadUsage.psm1'
    $script:Script = Join-Path $PackageRoot '.agents/skills/squad/scripts/Get-SquadUsage.ps1'
    Import-Module $script:Module -Force

    function Write-UsageEvents {
        param([Parameter(Mandatory)][string[]]$Lines)
        $path = Join-Path $TestDrive ("events-$([guid]::NewGuid().ToString('N')).jsonl")
        [IO.File]::WriteAllText($path, ($Lines -join "`n"), [Text.UTF8Encoding]::new($false))
        $path
    }

    function New-UsageLine {
        param(
            [string]$Source = 'session',
            [string]$Id = 'one',
            [decimal]$NanoAiu = 1000000000,
            [string]$Status = 'complete',
            [switch]$MissingIdentity
        )
        $accounting = if ($MissingIdentity) { @{} } else { @{ sourceSessionId = $Source; usageId = $Id } }
        @{
            type = 'session.usage_record'
            timestamp = '2026-10-24T10:00:00.000Z'
            data = @{
                usage = @{
                    model = 'gpt-5.6-sol'
                    inputTokens = 100
                    outputTokens = 10
                    cacheReadTokens = 80
                    cacheWriteTokens = 0
                    accounting = $accounting
                    aiCreditsStatus = $Status
                    copilotUsage = @{ totalNanoAiu = $NanoAiu }
                }
            }
        } | ConvertTo-Json -Depth 10 -Compress
    }
}

Describe 'SquadUsage exact native accounting' {
    It 'ships a script entry point for coordinators' {
        Test-Path -LiteralPath $script:Script -PathType Leaf | Should -BeTrue
    }

    It 'deduplicates complete usage identities and ignores a lagging checkpoint as authority' {
        $record = New-UsageLine -NanoAiu 2500000000
        $path = Write-UsageEvents @(
            $record
            $record
            (New-UsageLine -Source child -Id two -NanoAiu 500000000)
            (@{ type = 'session.usage_checkpoint'; timestamp = '2026-10-24T10:01:00.000Z'; data = @{ totalNanoAiu = 1000000000 } } | ConvertTo-Json -Compress)
        )

        $snapshot = Get-SquadUsageSnapshot -EventsPath $path
        $snapshot.status | Should -Be 'complete'
        $snapshot.records | Should -Be 2
        $snapshot.duplicates | Should -Be 1
        $snapshot.totalNanoAiu | Should -Be 3000000000
        $snapshot.credits | Should -Be 3
        $snapshot.usd | Should -Be 0.03
        $snapshot.checkpointNanoAiu | Should -Be 1000000000
    }

    It 'subtracts a run baseline in native units without rounding the consumed amount' {
        $path = Write-UsageEvents @(
            (New-UsageLine -NanoAiu 2500000000)
            (New-UsageLine -Source child -Id two -NanoAiu 500000000)
        )
        $snapshot = Get-SquadUsageSnapshot -EventsPath $path -BaselineNanoAiu 1250000000
        $snapshot.consumedNanoAiu | Should -Be 1750000000
        $snapshot.credits | Should -Be 1.75
        $snapshot.usd | Should -Be 0.0175
    }

    It 'fails metering closed for incomplete credit status or missing accounting identity' {
        $path = Write-UsageEvents @(
            (New-UsageLine -Status pending)
            (New-UsageLine -Id two -MissingIdentity)
        )
        $snapshot = Get-SquadUsageSnapshot -EventsPath $path
        $snapshot.status | Should -Be 'incomplete'
        @($snapshot.problems).Count | Should -Be 2
        $snapshot.records | Should -Be 0
    }

    It 'does not treat a checkpoint-only host as exact metering' {
        $path = Write-UsageEvents @(
            (@{ type = 'session.usage_checkpoint'; timestamp = '2026-10-24T10:01:00.000Z'; data = @{ totalNanoAiu = 1000000000 } } | ConvertTo-Json -Compress)
        )
        $snapshot = Get-SquadUsageSnapshot -EventsPath $path
        $snapshot.status | Should -Be 'incomplete'
        $snapshot.checkpointNanoAiu | Should -Be 1000000000
        $snapshot.totalNanoAiu | Should -Be 0
    }

    It 'returns the same snapshot through the script entry point' {
        $path = Write-UsageEvents @((New-UsageLine -NanoAiu 2500000000))
        $output = & pwsh -NoProfile -File $script:Script -SessionLog $path -BaselineNanoAiu 500000000 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $snapshot = $output | ConvertFrom-Json
        $snapshot.totalNanoAiu | Should -Be 2500000000
        $snapshot.consumedNanoAiu | Should -Be 2000000000
    }

    It 'attributes exact billed token categories and nested workers to the owning top-level agent' {
        $usage = {
            param($Source, $Id, $AgentId, $NanoAiu, $FreshInput, $Cached, $CacheWrite, $Output)
            @{
                type = 'session.usage_record'
                timestamp = "2026-10-24T10:00:0$Id.000Z"
                agentId = $AgentId
                data = @{
                    usage = @{
                        model = 'gpt-5.6-sol'
                        inputTokens = $FreshInput + $Cached + $CacheWrite
                        outputTokens = $Output
                        cacheReadTokens = $Cached
                        cacheWriteTokens = $CacheWrite
                        accounting = @{ sourceSessionId = $Source; usageId = $Id }
                        aiCreditsStatus = 'complete'
                        copilotUsage = @{
                            totalNanoAiu = $NanoAiu
                            tokenDetails = @(
                                @{ tokenType = 'input'; tokenCount = $FreshInput; batchSize = 1; costPerBatch = 100000000 }
                                @{ tokenType = 'cache_read'; tokenCount = $Cached; batchSize = 1; costPerBatch = 10000000 }
                                @{ tokenType = 'cache_write'; tokenCount = $CacheWrite; batchSize = 1; costPerBatch = 20000000 }
                                @{ tokenType = 'output'; tokenCount = $Output; batchSize = 1; costPerBatch = 100000000 }
                            )
                        }
                    }
                }
            } | ConvertTo-Json -Depth 12 -Compress
        }
        $path = Write-UsageEvents @(
            (@{ type = 'session.start'; timestamp = '2026-10-24T09:59:59.000Z'; data = @{ sessionId = 'main-session' } } | ConvertTo-Json -Compress)
            (@{ type = 'subagent.started'; agentId = 'owner'; timestamp = '2026-10-24T10:00:00.000Z'; data = @{ toolCallId = 't1'; agentName = 'Squad Researcher'; agentDisplayName = 'researcher' } } | ConvertTo-Json -Depth 6 -Compress)
            (& $usage 'owner-session' '1' 'owner' 1500000000 10 20 5 2)
            (@{ type = 'subagent.started'; agentId = 'worker'; timestamp = '2026-10-24T10:00:02.000Z'; data = @{ toolCallId = 't2'; agentName = 'RPI Researcher'; agentDisplayName = 'lane'; parentId = 'owner' } } | ConvertTo-Json -Depth 6 -Compress)
            (& $usage 'worker-session' '2' 'worker' 700000000 5 10 0 1)
            (& $usage 'main-session' '3' '' 300000000 2 0 0 1)
        )

        $snapshot = Get-SquadUsageSnapshot -EventsPath $path -IncludeAgentRuns
        $snapshot.status | Should -Be 'complete'
        $snapshot.attributionStatus | Should -Be 'complete'
        $snapshot.sessionId | Should -Be 'main-session'
        $snapshot.totalNanoAiu | Should -Be 2500000000
        $snapshot.identityDigest | Should -Match '^[A-F0-9]{64}$'
        @($snapshot.agentRuns).Count | Should -Be 2

        $owner = $snapshot.agentRuns | Where-Object agentName -eq 'Squad Researcher'
        $owner.records | Should -Be 2
        $owner.totalNanoAiu | Should -Be 2200000000
        $owner.inputTokens | Should -Be 15
        $owner.cacheReadTokens | Should -Be 30
        $owner.cacheWriteTokens | Should -Be 5
        $owner.outputTokens | Should -Be 3
        $owner.descendantAgents | Should -Contain 'RPI Researcher'

        $main = $snapshot.agentRuns | Where-Object agentName -eq 'coordinator'
        $main.totalNanoAiu | Should -Be 300000000
    }

    It 'keeps aggregate credits exact but refuses exact role attribution when tokenDetails do not reconcile' {
        $line = @{
            type = 'session.usage_record'
            timestamp = '2026-10-24T10:00:00.000Z'
            data = @{
                usage = @{
                    model = 'gpt-5.6-sol'
                    inputTokens = 1
                    outputTokens = 0
                    cacheReadTokens = 0
                    cacheWriteTokens = 0
                    accounting = @{ sourceSessionId = 'main'; usageId = 'bad-details' }
                    aiCreditsStatus = 'complete'
                    copilotUsage = @{
                        totalNanoAiu = 1000000000
                        tokenDetails = @(
                            @{ tokenType = 'input'; tokenCount = 1; batchSize = 1; costPerBatch = 1 }
                        )
                    }
                }
            }
        } | ConvertTo-Json -Depth 12 -Compress
        $snapshot = Get-SquadUsageSnapshot -EventsPath (Write-UsageEvents @($line)) -IncludeAgentRuns
        $snapshot.status | Should -Be 'incomplete'
        $snapshot.totalNanoAiu | Should -Be 1000000000
        $snapshot.attributionStatus | Should -Be 'incomplete'
        @($snapshot.attributionProblems).Count | Should -BeGreaterThan 0
    }
}
