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

    It 'treats an unterminated last usage line from a host that is still appending as not yet written, not as damage' {
        $whole = New-UsageLine -Id one -NanoAiu 2000000000
        $cut = '{"type":"session.usage_record","timestamp":"2026-10-24T10:00:01.000Z","data":{"usage":{"model":"gpt-5.6-sol","inputTok'
        $path = Write-UsageEvents @($whole, $cut)

        foreach ($withRuns in @($false, $true)) {
            $snapshot = Get-SquadUsageSnapshot -EventsPath $path -IncludeAgentRuns:$withRuns
            $snapshot.status | Should -Be 'complete' -Because ($snapshot.problems -join '; ')
            $snapshot.records | Should -Be 1
            $snapshot.totalNanoAiu | Should -Be 2000000000
        }
    }

    It 'still reports a damaged usage line that later lines follow' {
        $cut = '{"type":"session.usage_record","timestamp":"2026-10-24T10:00:01.000Z","data":{"usage":{"model":"gpt-5.6-sol","inputTok'
        $snapshot = Get-SquadUsageSnapshot -EventsPath (Write-UsageEvents @($cut, (New-UsageLine -Id two -NanoAiu 2000000000)))
        $snapshot.status | Should -Be 'incomplete'
        @($snapshot.problems) | Should -Contain 'Malformed session.usage_record event.'
    }

    It 'ignores a line that merely quotes an event type inside another event' {
        $quoting = @{
            type = 'tool.execution_complete'
            timestamp = '2026-10-24T10:00:00.000Z'
            data = @{ result = @{ note = '"type":"session.usage_record"'; extra = @{ type = 'session.usage_record'; data = 'x' } } }
        } | ConvertTo-Json -Depth 8 -Compress
        $raw = '{"type":"tool.execution_complete","data":{"payload":{"type":"session.usage_record","data":{"usage":"not a record"}}},"timestamp":"2026-10-24T10:00:01.000Z"}'
        $snapshot = Get-SquadUsageSnapshot -EventsPath (Write-UsageEvents @((New-UsageLine -NanoAiu 1000000000), $quoting, $raw)) -IncludeAgentRuns
        $snapshot.status | Should -Be 'complete' -Because ($snapshot.problems -join '; ')
        $snapshot.records | Should -Be 1
    }

    It 'keeps timestamps as the log text and reads usage records the same way on a PowerShell without -DateKind' {
        $record = New-UsageLine -Id one -NanoAiu 2500000000
        $path = Write-UsageEvents @(
            (@{ type = 'session.start'; timestamp = '2026-10-24T09:59:59.000Z'; data = @{ sessionId = 'main-session' } } | ConvertTo-Json -Compress)
            $record
        )
        $native = Get-SquadUsageSnapshot -EventsPath $path -IncludeAgentRuns
        InModuleScope SquadUsage {
            $script:JsonDateKindSupported = $false
        }
        try {
            $portable = Get-SquadUsageSnapshot -EventsPath $path -IncludeAgentRuns
        }
        finally {
            InModuleScope SquadUsage {
                $script:JsonDateKindSupported = (Get-Command -Name ConvertFrom-Json -CommandType Cmdlet).Parameters.ContainsKey('DateKind')
            }
        }
        $portable.status | Should -Be 'complete' -Because ($portable.problems -join '; ')
        $portable.last | Should -Be '2026-10-24T10:00:00.000Z'
        $portable.totalNanoAiu | Should -Be $native.totalNanoAiu
        $portable.identityDigest | Should -Be $native.identityDigest
        $portable.lastUsageTimestamp | Should -Be $native.lastUsageTimestamp
    }
}

Describe 'SquadUsage session selection for -SessionLog auto' {
    BeforeAll {
        function New-FakeSession {
            param([string]$CopilotHome, [string]$Id, [string]$Cwd, [datetime]$Written)
            $directory = Join-Path $CopilotHome "session-state/$Id"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'workspace.yaml') -Value "id: $Id`ncwd: $Cwd`n"
            $events = Join-Path $directory 'events.jsonl'
            Set-Content -LiteralPath $events -Value ('{"type":"session.start","data":{"sessionId":"' + $Id + '"}}')
            (Get-Item -LiteralPath $events).LastWriteTimeUtc = $Written
            [IO.Path]::GetFullPath($events)
        }
        function Get-SessionIds {
            param([string]$Repo)
            @(Resolve-SquadSessionLogPaths -SessionLog auto -RepoRoot $Repo | ForEach-Object { Split-Path -Leaf (Split-Path -Parent $_) })
        }
    }

    BeforeEach {
        $script:SavedHome = $env:COPILOT_HOME
        $script:SavedSessionId = $env:COPILOT_AGENT_SESSION_ID
        $script:StateHome = Join-Path $TestDrive "home-$([guid]::NewGuid().ToString('N'))"
        $script:Repo = Join-Path $TestDrive "repo-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -ItemType Directory -Path $script:Repo -Force | Out-Null
        $env:COPILOT_HOME = $script:StateHome
        Remove-Item Env:COPILOT_AGENT_SESSION_ID -ErrorAction SilentlyContinue
    }

    AfterEach {
        if ($null -eq $script:SavedHome) { Remove-Item Env:COPILOT_HOME -ErrorAction SilentlyContinue } else { $env:COPILOT_HOME = $script:SavedHome }
        if ($null -eq $script:SavedSessionId) { Remove-Item Env:COPILOT_AGENT_SESSION_ID -ErrorAction SilentlyContinue } else { $env:COPILOT_AGENT_SESSION_ID = $script:SavedSessionId }
    }

    It 'returns repository sessions newest first when the host names no running session' {
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'older' -Cwd $script:Repo -Written ([datetime]'2026-10-01T10:00:00Z')
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'newer' -Cwd $script:Repo -Written ([datetime]'2026-10-02T10:00:00Z')
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'elsewhere' -Cwd (Join-Path $TestDrive 'other') -Written ([datetime]'2026-10-03T10:00:00Z')
        Get-SessionIds -Repo $script:Repo | Should -Be @('newer', 'older')
    }

    It 'puts the session that is running this process first even when another window wrote later' {
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'running' -Cwd $script:Repo -Written ([datetime]'2026-10-01T10:00:00Z')
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'second-window' -Cwd $script:Repo -Written ([datetime]'2026-10-02T10:00:00Z')
        $env:COPILOT_AGENT_SESSION_ID = 'running'
        Get-SessionIds -Repo $script:Repo | Should -Be @('running', 'second-window')
        (Resolve-SquadSessionLogPath -SessionLog auto -RepoRoot $script:Repo) | Should -Match 'running'
    }

    It 'admits the running session when it was opened one folder above or below the repository' {
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'sibling-window' -Cwd $script:Repo -Written ([datetime]'2026-10-02T10:00:00Z')
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'parent-folder' -Cwd (Split-Path -Parent $script:Repo) -Written ([datetime]'2026-10-01T10:00:00Z')
        $env:COPILOT_AGENT_SESSION_ID = 'parent-folder'
        Get-SessionIds -Repo $script:Repo | Should -Be @('parent-folder', 'sibling-window')

        $env:COPILOT_AGENT_SESSION_ID = 'sibling-window'
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'subfolder' -Cwd (Join-Path $script:Repo 'src') -Written ([datetime]'2026-10-03T10:00:00Z')
        $env:COPILOT_AGENT_SESSION_ID = 'subfolder'
        Get-SessionIds -Repo $script:Repo | Should -Be @('subfolder', 'sibling-window')
    }

    It 'never adopts a running session that belongs to an unrelated folder or names a path' {
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'repo-session' -Cwd $script:Repo -Written ([datetime]'2026-10-01T10:00:00Z')
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'unrelated' -Cwd (Join-Path $TestDrive 'another-project') -Written ([datetime]'2026-10-02T10:00:00Z')
        foreach ($id in @('unrelated', 'missing-session', '..', '../repo-session', 'a/b')) {
            $env:COPILOT_AGENT_SESSION_ID = $id
            Get-SessionIds -Repo $script:Repo | Should -Be @('repo-session') -Because "COPILOT_AGENT_SESSION_ID='$id' must not widen the match"
        }
    }

    It 'does not repeat the running session when its cwd already matches' {
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'only' -Cwd $script:Repo -Written ([datetime]'2026-10-01T10:00:00Z')
        $env:COPILOT_AGENT_SESSION_ID = 'only'
        Get-SessionIds -Repo $script:Repo | Should -Be @('only')
    }

    It 'finds an accepted session by id when its folder is the repository or one folder above or below it' {
        $inside = New-FakeSession -CopilotHome $script:StateHome -Id 'inside' -Cwd $script:Repo -Written ([datetime]'2026-10-01T10:00:00Z')
        $below = New-FakeSession -CopilotHome $script:StateHome -Id 'below' -Cwd (Join-Path $script:Repo 'src') -Written ([datetime]'2026-10-01T10:00:00Z')
        $above = New-FakeSession -CopilotHome $script:StateHome -Id 'above' -Cwd (Split-Path -Parent $script:Repo) -Written ([datetime]'2026-10-01T10:00:00Z')
        Resolve-SquadSessionLogPathById -SessionId 'inside' -RepoRoot $script:Repo | Should -Be $inside
        Resolve-SquadSessionLogPathById -SessionId 'below' -RepoRoot $script:Repo | Should -Be $below
        Resolve-SquadSessionLogPathById -SessionId 'above' -RepoRoot $script:Repo | Should -Be $above
        # Only the cwd match is listed for auto, which is why an accepted session needs this lookup.
        Get-SessionIds -Repo $script:Repo | Should -Be @('inside')
    }

    It 'never resolves a session by id when its folder is unrelated, it does not exist, or the id is a path' {
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'unrelated' -Cwd (Join-Path $TestDrive 'another-project') -Written ([datetime]'2026-10-01T10:00:00Z')
        $null = New-FakeSession -CopilotHome $script:StateHome -Id 'repo-session' -Cwd $script:Repo -Written ([datetime]'2026-10-01T10:00:00Z')
        foreach ($id in @('unrelated', 'missing-session', '..', '.', '.hidden', '../repo-session', '..\repo-session', 'a/b', 'a\b', 'C:repo-session', "repo-session`n", 'repo-session ')) {
            Resolve-SquadSessionLogPathById -SessionId $id -RepoRoot $script:Repo | Should -BeNullOrEmpty -Because "session id '$id' must not resolve"
        }
        Resolve-SquadSessionLogPathById -SessionId 'repo-session' -RepoRoot $script:Repo | Should -Not -BeNullOrEmpty
    }
}
