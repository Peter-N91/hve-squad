#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1') -Force
    function Get-FakeEfficiencyAcpText {
        @'
$ErrorActionPreference='Stop'
$Mode=$env:HVE_FAKE_ACP_MODE
while($null -ne ($Line=[Console]::In.ReadLine())) {
    Add-Content -LiteralPath $env:HVE_FAKE_ACP_TRACE -Value $Line
    $Request=$Line|ConvertFrom-Json -AsHashtable
    $Result=@{}
    switch($Request.method) {
        'initialize' { $Result=@{protocolVersion=1;agentCapabilities=@{loadSession=($Mode -ne 'unsupported-load');sessionCapabilities=@{close=@{}}}} }
        'session/load' {
            $Session=$Request.params.sessionId
            @{jsonrpc='2.0';method='session/update';params=@{sessionId=$Session;update=@{sessionUpdate='available_commands_update';availableCommands=@(if($Mode -ne 'unsupported-command'){@{name='compact'}})}}}|ConvertTo-Json -Depth 12 -Compress
        }
        'session/prompt' {
            if($Mode -eq 'timeout'){while($true){}}
            if($Mode -eq 'permission'){@{jsonrpc='2.0';id=99;method='session/request_permission';params=@{sessionId=$Session}}|ConvertTo-Json -Compress;continue}
            if($Mode -eq 'rpc-failure'){@{jsonrpc='2.0';id=$Request.id;error=@{code=-32603;message='PRIVATE PROTOCOL DIAGNOSTIC'}}|ConvertTo-Json -Compress;continue}
            @{jsonrpc='2.0';method='session/update';params=@{sessionId=$Session;update=@{sessionUpdate='compaction_update';compactionId='old-replayed';status='completed';summary=@(@{type='text';text='PRIVATE REPLAY'})}}}|ConvertTo-Json -Depth 12 -Compress
            if($Mode -ne 'no-proof') {@{id=[guid]::NewGuid().ToString();type='session.compaction_complete';data=@{}}|ConvertTo-Json -Compress|Add-Content -LiteralPath $env:HVE_FAKE_ACP_EVENTS}
            if($Mode -ne 'unmetered') {@{id=[guid]::NewGuid().ToString();type='session.usage_record';data=@{usage=@{inputTokens=20;outputTokens=3;aiCreditsStatus='complete';copilotUsage=@{totalNanoAiu=$(if($Mode -eq 'credit-limit'){2000000000}else{1000000})};accounting=@{sourceSessionId=$Session;usageId='compact-usage'}}}}|ConvertTo-Json -Depth 10 -Compress|Add-Content -LiteralPath $env:HVE_FAKE_ACP_EVENTS}
            $Result=@{stopReason='end_turn'}
        }
        'session/close' { }
        default {continue}
    }
    @{jsonrpc='2.0';id=$Request.id;result=$Result}|ConvertTo-Json -Depth 12 -Compress
}
'@
    }
    function New-TestEvent {
        param([string]$Type, [hashtable]$Data, [int]$Second = 0, [string]$Id = ([guid]::NewGuid().ToString()))
        @{ id = $Id; type = $Type; timestamp = "2026-10-18T00:00:$($Second.ToString('00'))Z"; data = $Data } | ConvertTo-Json -Depth 15 -Compress
    }
    function New-TestUsage {
        param([string]$Id = 'usage-1')
        New-TestEvent 'session.usage_record' @{ usage = @{ inputTokens = 100; outputTokens = 10; toolTokenCount = 20; availableToolCount = 3; requestBodyBytes = 400; aiCreditsStatus = 'complete'; copilotUsage = @{ totalNanoAiu = 1000000 }; accounting = @{ sourceSessionId = 'child'; usageId = $Id } } }
    }
    function New-TestRuns {
        foreach ($Arm in @('baseline', 'candidate')) {
            foreach ($Pair in 1..3) {
                $Scores = @{ businessClarity = 20; scopeFidelity = 20; acceptanceCriteria = 20; traceability = 20; risksAndDecisions = 20 }
                $Evidence = @{}; foreach ($Name in $Scores.Keys) { $Evidence[$Name] = 'Specific evidence in frozen document.' }
                $Hashes = @{ brd = 'brd-hash'; prd = 'prd-hash' }
                @{
                    schemaVersion = 'squad-efficiency-v1'
                    metadata = @{ runId = "$Arm-$Pair"; pair = $Pair; arm = $Arm; revision = "$Arm-revision"; sourceHash = "$Arm-tree"; compatibility = @{ fixture = 'frozen'; model = 'same'; cli = 'same' } }
                    completed = $true; acceptance = @{ passed = $true }; workflow = @{ passed = $true }
                    stages = @(@{ name = 'init'; passed = $true; process = @{} }, @{ name = 'requirements'; passed = $true; process = @{} }, @{ name = 'build'; passed = $true; process = @{} })
                    metrics = @{ complete = $true; modelRequests = $(if ($Arm -eq 'baseline') { 100 } else { 80 }); toolCalls = $(if ($Arm -eq 'baseline') { 100 } else { 80 }); totals = @{ inputTokens = $(if ($Arm -eq 'baseline') { 10000 } else { 8000 }); outputTokens = 1000 }; counts = @{ failures = 0 } }
                    judge = @{ valid = $true; documentHashes = $Hashes; response = @{ scores = $Scores; evidence = $Evidence; documentHashes = $Hashes; criticalHighFindings = 0 }; metrics = @{ complete = $true; modelRequests = 5; toolCalls = 0; totals = @{ inputTokens = 100; outputTokens = 100 }; counts = @{ failures = 0 } } }
                }
            }
        }
    }
}

Describe 'Efficiency event analysis' -Tag 'Unit' {
    It 'deduplicates accounting records without double-counting child usage' {
        $Path = Join-Path $TestDrive 'usage.jsonl'
        @(New-TestUsage; New-TestUsage) | Set-Content $Path
        $Result = Measure-EfficiencyEvents $Path
        $Result.modelRequests | Should -Be 1
        $Result.totals.inputTokens | Should -Be 100
        $Result.counts.duplicateUsage | Should -Be 1
        $Result.sources.child.records | Should -Be 1
        $Result.totals.cacheReadTokens | Should -BeNullOrEmpty
    }
    It 'merges overlapping and nested hook intervals rather than summing them as blocking' {
        $Path = Join-Path $TestDrive 'hooks.jsonl'
        @(
            New-TestEvent 'hook.start' @{ hookInvocationId = 'one'; hookType = 'postToolUse' } 0
            New-TestEvent 'hook.start' @{ hookInvocationId = 'two'; hookType = 'postToolUse' } 2
            New-TestEvent 'hook.end' @{ hookInvocationId = 'one'; success = $true } 5
            New-TestEvent 'hook.end' @{ hookInvocationId = 'two'; success = $true } 7
        ) | Set-Content $Path
        $Result = Measure-EfficiencyEvents $Path
        $Result.hooks.sumMs | Should -Be 10000
        $Result.hooks.unionMs | Should -Be 7000
        $Result.hooks.overlapMs | Should -Be 3000
        $Result.hooks.blockingMs | Should -BeNullOrEmpty
        $Result.hooks.criticalPathMs | Should -BeNullOrEmpty
    }
    It 'does not count re-emitted hook or tool identifiers twice' {
        $Path = Join-Path $TestDrive 'duplicates.jsonl'
        @(
            New-TestEvent 'tool.execution_start' @{ toolCallId = 'one'; toolName = 'view' }
            New-TestEvent 'tool.execution_start' @{ toolCallId = 'one'; toolName = 'view' }
            New-TestEvent 'tool.execution_complete' @{ toolCallId = 'one'; success = $false }
            New-TestEvent 'tool.execution_complete' @{ toolCallId = 'one'; success = $false }
        ) | Set-Content $Path
        $Result = Measure-EfficiencyEvents $Path
        $Result.toolCalls | Should -Be 1
        $Result.counts.failures | Should -Be 1
        $Result.repairs | Should -BeNullOrEmpty
    }
    It 'marks malformed and unmatched evidence incomplete' {
        $Path = Join-Path $TestDrive 'incomplete.jsonl'
        @((New-TestEvent 'tool.execution_start' @{ toolCallId = 'one'; toolName = 'view' }); '{"partial":') | Set-Content $Path
        $Result = Measure-EfficiencyEvents $Path
        $Result.complete | Should -BeFalse
        $Result.completeness.malformed | Should -Be 1
        $Result.completeness.unmatchedTools | Should -Be 1
        $Result.modelRequests | Should -BeNullOrEmpty
    }
    It 'does not serialize prompt or tool arguments into metrics' {
        $Path = Join-Path $TestDrive 'privacy.jsonl'
        New-TestEvent 'tool.execution_start' @{ toolCallId = 'one'; toolName = 'view'; arguments = @{ path = 'SECRET-PATH' } } | Set-Content $Path
        Measure-EfficiencyEvents $Path | ConvertTo-Json -Depth 30 | Should -Not -Match 'SECRET-PATH'
    }
    It 'preserves missing field coverage rather than treating it as zero' {
        $Path = Join-Path $TestDrive 'coverage.jsonl'
        @((New-TestUsage); (New-TestEvent 'session.usage_record' @{ usage = @{ outputTokens = 5; accounting = @{ sourceSessionId = 'child'; usageId = 'two' } } })) | Set-Content $Path
        $Result = Measure-EfficiencyEvents $Path
        $Result.modelRequests | Should -Be 2
        $Result.totals.inputTokens | Should -BeNullOrEmpty
        $Result.coverage.inputTokens | Should -Be 1
        $Result.totals.outputTokens | Should -Be 15
    }
    It 'creates an immutable snapshot and refuses an existing destination' {
        $Source = Join-Path $TestDrive 'source.jsonl'; $Destination = Join-Path $TestDrive 'snapshot.jsonl'
        New-TestUsage | Set-Content $Source
        $Evidence = Copy-EfficiencySnapshot $Source $Destination
        Add-Content $Source 'later'
        (Get-FileHash $Destination).Hash.ToLowerInvariant() | Should -Be $Evidence.sha256
        { Copy-EfficiencySnapshot $Source $Destination } | Should -Throw
    }
}

Describe 'Efficiency bounded recovery policy' -Tag 'Unit' {
    BeforeEach {
        $script:RecoveryLog = Join-Path $TestDrive 'recovery.jsonl'
        New-TestEvent 'session.error' @{ message = "Request exceeds the model's prompt budget after reserving output (127666 tokens; limit 100000)." } | Set-Content $script:RecoveryLog
        $script:RecoveryInput = @{
            Path = $script:RecoveryLog
            Metrics = @{ complete = $true; modelRequests = 2; counts = @{ questions = 0 } }
            Process = @{ exitCode = 0; stopCause = 'none' }
            Readiness = @{ passed = $false; checks = @{ stateVerifier = $true } }
            RemainingRequests = 10; RemainingSeconds = 60; AcpSupported = $true; RecoveryUsed = $false
        }
    }
    It 'reserves the full workflow allowance from the outset without borrowing judge credits' {
        $Policy = Get-EfficiencyRecoveryPolicy -MaxCredits 1000
        ($Policy.workflowCredits + $Policy.judgeCredits) | Should -Be 1000
        $Policy.workflowCredits | Should -Be 750
        $Policy.maxCyclesPerStage | Should -Be 1
    }
    It 'permits one healthy structured context-budget recovery' {
        (Get-EfficiencyRecoveryDecision @script:RecoveryInput).allowed | Should -BeTrue
        $script:RecoveryInput.AcpSupported = $false
        (Get-EfficiencyRecoveryDecision @script:RecoveryInput).allowed | Should -BeFalse
    }
    It 'does not infer a context error from ordinary assistant text' {
        New-TestEvent 'assistant.message' @{ message = "Request exceeds the model's prompt budget" } | Set-Content $script:RecoveryLog
        (Get-EfficiencyRecoveryDecision @script:RecoveryInput).allowed | Should -BeFalse
        Add-Content $script:RecoveryLog (New-TestEvent 'session.error' @{ message = "Request exceeds the model's prompt budget" })
        Add-Content $script:RecoveryLog (New-TestEvent 'session.error' @{ message = 'Authentication failed.' })
        (Get-EfficiencyRecoveryDecision @script:RecoveryInput).allowed | Should -BeFalse
    }
    It 'rejects <Failure> instead of retrying' -ForEach @(
        @{ Failure = 'repeated attempt' }
        @{ Failure = 'request exhaustion' }
        @{ Failure = 'unmetered evidence' }
        @{ Failure = 'state integrity' }
        @{ Failure = 'safety stop' }
    ) {
        switch ($Failure) {
            'repeated attempt' { $script:RecoveryInput.RecoveryUsed = $true }
            'request exhaustion' {
                $script:RecoveryInput.RemainingRequests = 1
                (Get-EfficiencyRecoveryDecision @script:RecoveryInput).allowed | Should -BeFalse
                $script:RecoveryInput.RemainingRequests = 10; $script:RecoveryInput.RemainingSeconds = 0
            }
            'unmetered evidence' { $script:RecoveryInput.Metrics.complete = $false }
            'state integrity' { $script:RecoveryInput.Readiness.checks.stateVerifier = $false }
            'safety stop' { Add-Content $script:RecoveryLog (New-TestEvent 'session.error' @{ message = 'Permission denied by policy.' }) }
        }
        (Get-EfficiencyRecoveryDecision @script:RecoveryInput).allowed | Should -BeFalse
    }
}

Describe 'Efficiency resolved discovery evidence' -Tag 'Unit' {
    BeforeAll {
        function Add-DiscoveryOperation {
            param([string]$Path,[string]$Tool,[hashtable]$Arguments,[bool]$Success,[string]$Actor='scribe-a',[string]$Content='reference text',[string]$Detailed='', [string]$ErrorMessage='Permission denied because no interactive user response was available. Retry in an interactive session.')
            $CallId=[guid]::NewGuid().ToString()
            foreach($Record in @(
                @{type='tool.execution_start';data=@{toolCallId=$CallId;toolName=$Tool;arguments=$Arguments}},
                @{type='tool.execution_complete';data=@{toolCallId=$CallId;success=$Success;result=@{content=$Content;detailedContent=$Detailed};error=if($Success){$null}else{@{message=$ErrorMessage}}}}
            )) {
                $Event=New-TestEvent $Record.type $Record.data|ConvertFrom-Json -AsHashtable
                $Event['agentId']=$Actor
                $Event|ConvertTo-Json -Depth 20 -Compress|Add-Content -LiteralPath $Path
            }
        }
    }
    BeforeEach {
        $script:DiscoveryWorkspace=Join-Path $TestDrive 'discovery-workspace'
        New-Item -ItemType Directory -Path $script:DiscoveryWorkspace -Force|Out-Null
        $script:DiscoveryLog=Join-Path $TestDrive 'discovery.jsonl'
        New-TestEvent 'session.error' @{message="Request exceeds the model's prompt budget (127366 tokens; limit 100000)."}|Set-Content $script:DiscoveryLog
        $script:DiscoveryInput=@{Path=$script:DiscoveryLog;Workspace=$script:DiscoveryWorkspace;Metrics=@{complete=$true;modelRequests=5;counts=@{questions=0}};Process=@{exitCode=0;stopCause='none'};Readiness=@{passed=$false;checks=@{stateVerifier=$true}};RemainingRequests=20;RemainingSeconds=60;AcpSupported=$true;RecoveryUsed=$false}
        $script:DeniedReference='/home/azureuser/.agents/skills/squad/references/entry-schemas.md'
        $script:SafeReference=Join-Path $script:DiscoveryWorkspace '.agents/skills/squad/references/entry-schemas.md'
    }
    It 'resolves a later same-actor local read, deduplicates and preserves evidence' {
        Add-DiscoveryOperation $script:DiscoveryLog view @{path=$script:DeniedReference} $false
        $DeniedCompletion=Get-Content $script:DiscoveryLog -Tail 1
        Add-DiscoveryOperation $script:DiscoveryLog view @{path=$script:SafeReference} $true
        Add-Content $script:DiscoveryLog $DeniedCompletion
        $Before=(Get-FileHash $script:DiscoveryLog).Hash
        $Decision=Get-EfficiencyRecoveryDecision @script:DiscoveryInput
        $Decision.allowed|Should -BeTrue
        $Decision.resolvedDiscoveryDenials|Should -Be 1
        ($Decision|ConvertTo-Json)|Should -Not -Match 'azureuser|discovery-workspace'
        (Get-FileHash $script:DiscoveryLog).Hash|Should -Be $Before
        $script:DiscoveryInput.Workspace=''
        (Get-EfficiencyRecoveryDecision @script:DiscoveryInput).allowed|Should -BeFalse
    }
    It 'resolves known glob discovery only with all core text and anchored grep proof' {
        Add-DiscoveryOperation $script:DiscoveryLog glob @{pattern='**/squad/references/*.md';paths=@('.agents/skills','/home/azureuser/.copilot')} $false
        $IndexPath=(Join-Path $script:DiscoveryWorkspace '.agents/skills/squad/references/00-index.md').Replace('\','/')
        Add-DiscoveryOperation $script:DiscoveryLog view @{path='.agents/skills/squad/references/00-index.md'} $true -Detailed "`ndiff --git a$IndexPath b$IndexPath`n"
        foreach($Reference in @('entry-schemas.md','scribe-payload-template.md')){Add-DiscoveryOperation $script:DiscoveryLog view @{path=(Join-Path $script:DiscoveryWorkspace ".agents/skills/squad/references/$Reference")} $true}
        Add-DiscoveryOperation $script:DiscoveryLog grep @{paths=@('.agents/skills/squad/references/scribe-procedure.md');output_mode='content';pattern='Consumption'} $true -Content '[grep content: 14 matches across 1 file(s)] procedure text'
        $Decision=Get-EfficiencyRecoveryDecision @script:DiscoveryInput
        $Decision.allowed|Should -BeTrue
        $Decision.resolvedDiscoveryDenials|Should -Be 1
        Set-Content $script:DiscoveryLog ((Get-Content $script:DiscoveryLog -Raw).Replace('14 matches','0 matches'))
        (Get-EfficiencyRecoveryDecision @script:DiscoveryInput).allowed|Should -BeFalse
    }
    It 'keeps <Boundary> blocking despite a budget error' -ForEach @(
        @{Boundary='unresolved'},@{Boundary='wrong actor'},@{Boundary='prior success'},@{Boundary='outside root'},@{Boundary='size notice'},
        @{Boundary='unknown target'},@{Boundary='write denial'},@{Boundary='shell denial'},@{Boundary='explicit policy'},@{Boundary='missing root proof'}
    ) {
        $Tool='view';$Target=$script:DeniedReference
        if($Boundary -eq 'unknown target'){$Target='/home/azureuser/private.md'}
        if($Boundary -eq 'write denial'){$Tool='edit'}
        if($Boundary -eq 'shell denial'){$Tool='bash'}
        if($Boundary -eq 'prior success'){Add-DiscoveryOperation $script:DiscoveryLog view @{path=$script:SafeReference} $true}
        if($Boundary -eq 'explicit policy'){Add-DiscoveryOperation $script:DiscoveryLog view @{path=$Target} $false -ErrorMessage 'Permission denied by policy.'}
        else{Add-DiscoveryOperation $script:DiscoveryLog $Tool @{path=$Target} $false}
        if($Boundary -notin @('unresolved','prior success')){
            $Actor=if($Boundary -eq 'wrong actor'){'scribe-b'}else{'scribe-a'}
            $Path=if($Boundary -eq 'outside root'){Join-Path ($script:DiscoveryWorkspace+'-other') '.agents/skills/squad/references/entry-schemas.md'}elseif($Boundary -eq 'missing root proof'){'.agents/skills/squad/references/entry-schemas.md'}else{$script:SafeReference}
            $Text=if($Boundary -eq 'size notice'){'File too large to read at once. Use view_range.'}else{'reference text'}
            Add-DiscoveryOperation $script:DiscoveryLog view @{path=$Path} $true -Actor $Actor -Content $Text
        }
        (Get-EfficiencyRecoveryDecision @script:DiscoveryInput).allowed|Should -BeFalse
        if($Boundary -eq 'outside root'){
            Add-DiscoveryOperation $script:DiscoveryLog view @{path=(Join-Path $script:DiscoveryWorkspace 'outside/../.agents/skills/squad/references/entry-schemas.md')} $true
            (Get-EfficiencyRecoveryDecision @script:DiscoveryInput).allowed|Should -BeFalse
        }
    }
}

Describe 'Efficiency native compaction boundary' -Tag 'Unit' {
    BeforeAll {
        $script:FakeAcpText = Get-FakeEfficiencyAcpText
    }
    It 'enforces native compaction outcome <Mode>' -ForEach @(
        @{ Mode = 'success'; Expected = 'none' }
        @{ Mode = 'unsupported-load'; Expected = 'unsupported-load' }
        @{ Mode = 'unsupported-command'; Expected = 'unsupported-command' }
        @{ Mode = 'no-proof'; Expected = 'unverified-compaction' }
        @{ Mode = 'unmetered'; Expected = 'unverified-compaction' }
        @{ Mode = 'permission'; Expected = 'client-request' }
        @{ Mode = 'rpc-failure'; Expected = 'protocol-error' }
        @{ Mode = 'timeout'; Expected = 'timeout' }
        @{ Mode = 'credit-limit'; Expected = 'credit-limit' }
    ) {
        $Cli = Join-Path $TestDrive "$Mode-cli.ps1"
        $Events = Join-Path $TestDrive "$Mode-events.jsonl"
        $Trace = Join-Path $TestDrive "$Mode-trace.jsonl"
        $Output = Join-Path $TestDrive "$Mode-output.jsonl"
        Set-Content -LiteralPath $Cli -Value $script:FakeAcpText -Encoding utf8NoBOM
        @(New-TestUsage; New-TestEvent 'session.compaction_complete' @{}) | Set-Content $Events
        $Session = [guid]::NewGuid().ToString()
        $Result = Invoke-EfficiencyCompaction -CliPath $Cli -SessionId $Session -Workspace $TestDrive -EventsPath $Events -OutputPath $Output -UsagePath (Join-Path $TestDrive "$Mode-usage.json") -MaxCredits $(if($Mode -eq 'credit-limit'){1}else{10}) -Model fake -TimeoutSeconds $(if($Mode -eq 'timeout'){1}else{10}) -MaxRequests $(if($Mode -eq 'success'){990}else{10}) -EnvironmentVariables @{HVE_FAKE_ACP_MODE=$Mode;HVE_FAKE_ACP_EVENTS=$Events;HVE_FAKE_ACP_TRACE=$Trace}
        $Result.stopCause | Should -Be $Expected
        $Result.succeeded | Should -Be ($Mode -eq 'success')
        ($Result | ConvertTo-Json -Depth 10) | Should -Not -Match 'PRIVATE REPLAY|PRIVATE PROTOCOL DIAGNOSTIC'
        if ($Mode -eq 'success') {
            $Result.freshCompactions | Should -Be 1
            $Result.freshUsage | Should -Be 1
            $Requests = @(Get-Content $Trace | ForEach-Object { $_ | ConvertFrom-Json })
            ($Requests | Where-Object method -EQ 'session/load').params.sessionId | Should -Be $Session
            ($Requests | Where-Object method -EQ 'session/prompt').params.prompt[0].text | Should -Match '^/compact '
            $Requests.method | Should -Not -Contain 'session/new'
        }
    }
}

Describe 'Efficiency recovery end to end' -Tag 'Unit' {
    It 'preserves same-run evidence and stops correctly for <Outcome>' -ForEach @(
        @{ Outcome = 'recovered' }
        @{ Outcome = 'still-fails' }
        @{ Outcome = 'credit-limit' }
    ) {
        $Install = Join-Path $TestDrive "$Outcome-install"; $Trial = Join-Path $TestDrive "$Outcome-run"
        New-Item -ItemType Directory -Path (Join-Path $Install '.github/agents') -Force | Out-Null
        foreach ($Name in @('squad-coordinator.agent.md','brd-builder.agent.md','prd-builder.agent.md')) { Set-Content (Join-Path $Install ".github/agents/$Name") 'offline fixture' }
        $Source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
        $Fixture = (Join-Path $Source 'tests/fixtures/scribe-benchmark/applied').Replace("'", "''")
        $Cli = Join-Path $TestDrive "$Outcome-cli.ps1"
        $Acp = (Get-FakeEfficiencyAcpText).Replace('$Session=$Request.params.sessionId', '$Session=$Request.params.sessionId; $env:HVE_FAKE_ACP_EVENTS=Join-Path $HOME ".copilot/session-state/$Session/events.jsonl"')
        $Fake = @'
if ($args -contains 'mcp') { '{"mcpServers":{}}'; exit 0 }
if ($args -contains '--version') { 'offline-recovery-cli'; exit 0 }
if ($args -contains '--help') { '--acp --session-id --max-ai-credits --no-ask-user --max-autopilot-continues --usage-output-file --no-remote --no-remote-export --add-dir'; exit 0 }
if ($args -contains '--acp') {
    $env:HVE_FAKE_ACP_MODE='success'
    $env:HVE_FAKE_ACP_TRACE=Join-Path $PWD 'acp-trace.jsonl'
__ACP__
    exit 0
}
$ErrorActionPreference='Stop'
$Session=$args[[array]::IndexOf($args,'--session-id')+1]
$Prompt=$args[[array]::IndexOf($args,'-p')+1]
$Kind=if($Prompt -match 'Initialization only;'){'init'}elseif($Prompt -match 'Implement docs/requirements/prd.md'){'build'}elseif($Prompt -match 'This is a continuation of this same stage'){'continuation'}else{'requirements'}
$Ceiling=[double]$args[[array]::IndexOf($args,'--max-ai-credits')+1]
if(-not (Test-Path 'initial-credit-limit.txt')){Set-Content 'initial-credit-limit.txt' $Ceiling}
$EffectiveCeiling=[double](Get-Content 'initial-credit-limit.txt')
@{kind=$Kind;session=$Session;ceiling=$Ceiling;effectiveCeiling=$EffectiveCeiling;resumeOnly=$Prompt.Contains('Resume only the interrupted Scribe handoff first')}|ConvertTo-Json -Compress|Add-Content 'stage-calls.jsonl'
if($EffectiveCeiling -lt 750){exit 38}
$SessionRoot=Join-Path $HOME ".copilot/session-state/$Session"
New-Item -ItemType Directory -Path $SessionRoot -Force|Out-Null
$Events=Join-Path $SessionRoot 'events.jsonl'
function Write-FakeEvent([string]$Type,[hashtable]$Data) {
    $Line=@{id=[guid]::NewGuid().ToString();type=$Type;data=$Data}|ConvertTo-Json -Depth 20 -Compress
    Add-Content -LiteralPath $Events -Value $Line
    Write-Output $Line
}
Write-FakeEvent 'session.usage_record' @{usage=@{inputTokens=10;outputTokens=1;aiCreditsStatus='complete';copilotUsage=@{totalNanoAiu=$(if($Kind -eq 'requirements' -and '__OUTCOME__' -eq 'credit-limit'){751000000000}else{1000000})};accounting=@{sourceSessionId=$Session;usageId="$Kind-usage"}}}
if($Kind -eq 'init') {
    New-Item -ItemType Directory -Path '.copilot-tracking' -Force|Out-Null
    foreach($Item in Get-ChildItem -LiteralPath '__FIXTURE__' -Force) { Copy-Item -LiteralPath $Item.FullName -Destination '.copilot-tracking/squad' -Recurse -Force }
    Write-FakeEvent 'subagent.started' @{agentName='Squad Scribe'}
} elseif($Kind -eq 'requirements' -or ($Kind -eq 'continuation' -and '__OUTCOME__' -eq 'still-fails')) {
    Write-FakeEvent 'session.error' @{message="Request exceeds the model's prompt budget after reserving output (127666 tokens; limit 100000)."}
} elseif($Kind -eq 'continuation') {
    New-Item -ItemType Directory -Path 'docs/requirements/reviews' -Force|Out-Null
    foreach($Name in @('brd.md','prd.md')){Set-Content "docs/requirements/$Name" 'synthetic published requirement'}
    Add-Content -LiteralPath '.copilot-tracking/squad/team.md' -Value '| tester | Reviewer | Squad Reviewer | — | — | runSubagent / task | default | reviews/ |'
    foreach($Agent in @('BRD Builder','PRD Builder','BRD Quality Reviewer','PRD Quality Reviewer','Squad Reviewer')) {
        $Relative="docs/requirements/reviews/$Agent.md"
        Set-Content -LiteralPath $Relative -Value $(if($Agent -eq 'Squad Reviewer'){'Outcome: Pass'}else{'synthetic reviewer or author artifact'})
        $Block=[ordered]@{model='Claude Haiku 4.5';model_source='agent-pinned';priced_as='Claude Haiku 4.5';model_tier='fast';internal_turns=0;input_tokens=0;cached_tokens=0;cache_write_tokens=0;output_tokens=0;basis='estimated'}|ConvertTo-Json
        Set-Content -LiteralPath ".copilot-tracking/squad/history/$Agent.md" -Value ("# History: $Agent`n`n### $([datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')) Synthetic test dispatch`n* Deliverable: $Relative`n`n#### Consumption`n"+'```json'+"`n$Block`n"+'```')
        Write-FakeEvent 'subagent.started' @{agentName=$Agent}
    }
} elseif($Kind -eq 'build') { exit 37 }
exit 0
'@
        Set-Content -LiteralPath $Cli -Value ($Fake.Replace('__ACP__',$Acp).Replace('__FIXTURE__',$Fixture).Replace('__OUTCOME__',$Outcome)) -Encoding utf8NoBOM
        $Execution = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'),'-Mode','Run','-SourceRoot',$Source,'-InstallRoot',$Install,'-CliPath',$Cli,'-TrialRoot',$Trial,'-MaxCredits','1000','-Live','-IsolatedEnvironment') -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive "$Outcome-launch.txt") -TimeoutSeconds 90 -InputText ''
        $Run = Get-Content (Join-Path $Trial 'out/run.json') -Raw | ConvertFrom-Json
        try {
            $Execution.exitCode | Should -Be 2
            $Run.stages[0].passed | Should -BeTrue
            $Stage = $Run.stages[1]
            $Stage.name | Should -Be requirements
            if ($Outcome -eq 'credit-limit') {
                $Stage.process.stopCause | Should -Be 'credit-limit'
                $Stage.attempts[0].process.creditsUsed | Should -Be 751.001
                $Stage.recovery.count | Should -Be 0
                @($Run.stages).Count | Should -Be 2
                $Run.judge | Should -BeNullOrEmpty
                @(Get-Content (Join-Path $Trial 'workspace/stage-calls.jsonl')).Count | Should -Be 2
                return
            }
            $Stage.attempts.kind -join ',' | Should -Be 'stage,compaction,continuation'
            $Stage.recovery.count | Should -Be 1
            $Stage.passed | Should -Be ($Outcome -eq 'recovered')
            $Stage.recovery.status | Should -Be $(if($Outcome -eq 'recovered'){'recovered'}else{'failed'})
            $Stage.stageTokenDelta.inputTokens | Should -Be 40
            $Stage.metrics.modelRequests | Should -Be 4
            foreach($Prefix in @('requirements','requirements-compaction','requirements-continuation')) { Test-Path (Join-Path $Trial "out/$Prefix-events.jsonl") | Should -BeTrue }
            Get-Content (Join-Path $Trial 'out/requirements-stdout.jsonl') -Raw | Should -Match '127666'
            $Calls = @(Get-Content (Join-Path $Trial 'workspace/stage-calls.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
            @($Calls.session | Sort-Object -Unique).Count | Should -Be 1
            ($Calls | Where-Object kind -EQ continuation).resumeOnly | Should -BeTrue
            @($Calls.ceiling | Sort-Object -Unique) | Should -Be @(750)
            @($Calls.effectiveCeiling | Sort-Object -Unique) | Should -Be @(750)
            $Stage.attempts.sessionCreditCeiling | Should -Be @(750,750,750)
            $Stage.attempts[1].process.creditCeiling | Should -Be 750
            $Stage.metrics.credits.complete | Should -BeTrue
            $Stage.metrics.credits.used | Should -Be 0.004
            $AcpCalls = @(Get-Content (Join-Path $Trial 'workspace/acp-trace.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
            @($AcpCalls | Where-Object method -EQ 'session/prompt').Count | Should -Be 1
            ($AcpCalls | Where-Object method -EQ 'session/load').params.sessionId | Should -Be $Run.metadata.sessionId
            @($Run.stages).Count | Should -Be $(if($Outcome -eq 'recovered'){3}else{2})
            $Run.completed | Should -BeFalse
            $Run.judge | Should -BeNullOrEmpty
        }
        finally { Remove-Item (Join-Path $HOME ".copilot/session-state/$($Run.metadata.sessionId)") -Recurse -Force }
    }
}

Describe 'Efficiency process boundary' -Tag 'Unit' {
    It 'guards cumulative credits for <Case>' -ForEach @(
        @{ Case = 'reset-counter'; Amount = 1200000000; Delay = 3000; Expected = 'credit-limit'; Prior = $true }
        @{ Case = 'fast-exit'; Amount = 1200000000; Delay = 0; Expected = 'credit-limit'; Prior = $true }
        @{ Case = 'replay'; Amount = 500000000; Delay = 0; Expected = 'none'; Prior = $true }
        @{ Case = 'negative'; Amount = -1; Delay = 0; Expected = 'incomplete-credit-metering'; Prior = $false }
        @{ Case = 'invalid'; Amount = 'unknown'; Delay = 0; Expected = 'incomplete-credit-metering'; Prior = $false }
        @{ Case = 'missing'; Amount = $null; Delay = 0; Expected = 'incomplete-credit-metering'; Prior = $false }
        @{ Case = 'no-records'; Amount = 0; Delay = 0; Expected = 'incomplete-credit-metering'; Prior = $false }
        @{ Case = 'no-fresh-records'; Amount = 0; Delay = 0; Expected = 'incomplete-credit-metering'; Prior = $true }
        @{ Case = 'native-compaction'; Amount = 1200000000; Delay = 0; Expected = 'credit-limit'; Prior = $true }
    ) {
        $Events = Join-Path $TestDrive "$Case-events.jsonl"
        $Cli = Join-Path $TestDrive "$Case-credit-cli.ps1"
        $PriorLine = New-TestEvent 'session.usage_record' @{usage=@{aiCreditsStatus='complete';copilotUsage=@{totalNanoAiu=1000000000};accounting=@{sourceSessionId='workflow';usageId='initial'}}}
        if ($Prior) { Set-Content -LiteralPath $Events -Value $PriorLine }
        $Data = @{aiCreditsStatus='complete';copilotUsage=@{totalNanoAiu=$Amount};accounting=@{sourceSessionId='descendant';usageId='next'}}
        $Line = if ($Case -eq 'native-compaction') {
            New-TestEvent 'session.compaction_complete' @{compactionAttemptId='compact-one';compactionTokensUsed=$Data}
        } else { New-TestEvent 'session.usage_record' @{usage=$Data} }
        $Encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Line))
        @'
param($Events,$Encoded,$Delay,$Case)
Set-Content -LiteralPath ($Events+'.started') -Value 'started'
if($Case -eq 'replay'){$Replay=@(Get-Content -LiteralPath $Events);$Replay|Add-Content -LiteralPath $Events}
if($Case -notin @('no-records','no-fresh-records')){Add-Content -LiteralPath $Events -Value ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Encoded)))}
Start-Sleep -Milliseconds ([int]$Delay)
'@ | Set-Content -LiteralPath $Cli
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile','-File',$Cli,$Events,$Encoded,[string]$Delay,$Case) -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive "$Case-credit-output.txt") -EventsPath $Events -StartLine $(if($Prior){1}else{0}) -MaxCredits 2 -TimeoutSeconds 10
        $Result.stopCause | Should -Be $Expected
        if ($Expected -eq 'credit-limit') {
            $Result.creditsUsed | Should -Be 2.2
            $Marker = $Events + '.started'
            Remove-Item -LiteralPath $Marker
            $Blocked = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile','-File',$Cli,$Events,$Encoded,'0',$Case) -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive "$Case-blocked.txt") -EventsPath $Events -StartLine 100 -MaxCredits 2
            $Blocked.stopCause | Should -Be 'credit-limit'
            Test-Path -LiteralPath $Marker | Should -BeFalse
        }
        if ($Case -eq 'replay') {
            $Result.creditsUsed | Should -Be 1.5
            (Measure-EfficiencyEvents $Events).credits.used | Should -Be 1.5
        }
        if ($Delay -gt 0) { $Result.seconds | Should -BeLessThan 3 }
    }
    It 'keeps judge credit accounting separate from the workflow' {
        $Workspace = Join-Path $TestDrive 'judge-workspace'; $Out = Join-Path $TestDrive 'judge-out'
        New-Item -ItemType Directory -Path (Join-Path $Workspace 'docs/requirements'),$Out -Force | Out-Null
        foreach ($Name in @('brd','prd','review')) { Set-Content -LiteralPath (Join-Path $Workspace "docs/requirements/$Name.md") -Value 'synthetic document' }
        $Cli = Join-Path $TestDrive 'judge-credit-cli.ps1'
        @'
$Payload=[Console]::In.ReadToEnd()|ConvertFrom-Json -AsHashtable
$Session=$args[[array]::IndexOf($args,'--session-id')+1]
$Ceiling=[double]$args[[array]::IndexOf($args,'--max-ai-credits')+1]
$SessionRoot=Join-Path $HOME ".copilot/session-state/$Session"
New-Item -ItemType Directory -Path $SessionRoot -Force|Out-Null
$Events=Join-Path $SessionRoot 'events.jsonl'
@{type='session.usage_record';data=@{usage=@{inputTokens=10;outputTokens=1;aiCreditsStatus='complete';copilotUsage=@{totalNanoAiu=1000000000};accounting=@{sourceSessionId=$Session;usageId='judge'}}}}|ConvertTo-Json -Depth 10 -Compress|Set-Content $Events
$Scores=@{};$Evidence=@{}
foreach($Name in @('businessClarity','scopeFidelity','acceptanceCriteria','traceability','risksAndDecisions')){$Scores[$Name]=20;$Evidence[$Name]='specific synthetic document evidence'}
$Response=@{scores=$Scores;evidence=$Evidence;criticalHighFindings=0;documentHashes=$Payload.documentHashes}|ConvertTo-Json -Compress
@{type='assistant.message';data=@{content=$Response}}|ConvertTo-Json -Compress|Add-Content $Events
@{session=$Session;ceiling=$Ceiling}|ConvertTo-Json -Compress|Set-Content 'judge-call.json'
'@ | Set-Content -LiteralPath $Cli
        $Policy = Get-EfficiencyRecoveryPolicy -MaxCredits 1000
        $Judge = Invoke-EfficiencyJudge -Workspace $Workspace -Out $Out -CliPath $Cli -Model fake -MaxCredits $Policy.judgeCredits -ReviewPath 'docs/requirements/review.md'
        $Call = Get-Content (Join-Path $Out 'judge-call.json') -Raw | ConvertFrom-Json
        try {
            $Judge.valid | Should -BeTrue
            $Call.ceiling | Should -Be 250
            $Judge.process.creditCeiling | Should -Be 250
            $Judge.metrics.credits.used | Should -Be 1
        }
        finally { Remove-Item -LiteralPath (Join-Path $HOME ".copilot/session-state/$($Call.session)") -Recurse -Force }
    }
    It 'sets repository-hook opt-in only for the child process' {
        $Previous = [Environment]::GetEnvironmentVariable('GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS', 'Process')
        $Output = Join-Path $TestDrive 'child-environment.txt'
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', '[Console]::Write($env:GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS)') -WorkingDirectory $TestDrive -OutputPath $Output -TimeoutSeconds 10 -EnvironmentVariables @{ GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS = 'true' }
        $Result.exitCode | Should -Be 0
        Get-Content $Output -Raw | Should -Be 'true'
        [Environment]::GetEnvironmentVariable('GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS', 'Process') | Should -Be $Previous
    }
    It 'preserves named readiness failures when a stage exits zero' {
        $Trial = {
            param($Arm, $Pair, $Credits)
            $Run = @(New-TestRuns)[0]; $Run.completed = $false; $Run.judge = $null
            $Run.stages = @(@{ name = 'requirements'; passed = $false; process = @{ exitCode = 0; stopCause = 'none' }; readiness = @{ passed = $false; checks = @{ 'PRD Quality Reviewer' = $false; 'brd.md' = $true } } })
            $Run
        }
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial $Trial -PerRunCredits 10 -SeriesCredits 30
        $Result.report.slots[0].failedStages[0].failedChecks | Should -Contain 'PRD Quality Reviewer'
        $Result.report.slots[0].failedStages[0].failedChecks | Should -Not -Contain 'brd.md'
        $Result.report.trials[0].stages[0].readiness.passed | Should -BeFalse
        @($Result.report.slots | Where-Object status -EQ 'not-run').Count | Should -Be 2
    }
    It 'transfers large input through stdin instead of the Windows command line' {
        $Output = Join-Path $TestDrive 'stdin.txt'
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', '$value=[Console]::In.ReadToEnd(); [Console]::Write($value.Length)') -WorkingDirectory $TestDrive -OutputPath $Output -TimeoutSeconds 10 -InputText ('x' * 40000)
        $Result.exitCode | Should -Be 0
        Get-Content $Output -Raw | Should -Be '40000'
    }
    It 'preserves quoted arguments and captures streams without invoking a model' {
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', 'Write-Output "a b"') -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'stdout.txt') -TimeoutSeconds 10
        $Result.exitCode | Should -Be 0
        $Result.stopCause | Should -Be 'none'
        (Get-Content (Join-Path $TestDrive 'stdout.txt') -Raw).Trim() | Should -Be 'a b'
    }
    It 'times out a runaway subprocess' {
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', 'while ($true) {}') -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'timeout.txt') -TimeoutSeconds 1
        $Result.stopCause | Should -Be 'timeout'
    }
    It 'returns a failed independent grade when the implementation is missing' {
        $Output = & (Join-Path $PSScriptRoot 'Test-EfficiencyTask.ps1') -Workspace $TestDrive | ConvertFrom-Json
        $Output.passed | Should -BeFalse
    }
}

Describe 'Efficiency stage readiness' -Tag 'Unit' {
    BeforeEach {
        $script:StageWorkspace = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:StageSquad = Join-Path $script:StageWorkspace '.copilot-tracking/squad'
        New-Item -ItemType Directory -Path (Join-Path $script:StageSquad 'history'), (Join-Path $script:StageWorkspace 'docs/requirements/reviews') -Force | Out-Null
        foreach ($Name in @('team.md', 'routing.md', 'state.json', 'decisions.md', 'consumption.md', 'consumption-rates.md')) {
            Set-Content (Join-Path $script:StageSquad $Name) 'synthetic fixture; external state verification is mocked'
        }
        Set-Content (Join-Path $script:StageSquad 'history/Squad Scribe.md') '# History: Squad Scribe'
        Set-Content (Join-Path $script:StageSquad 'team.md') '| tester | Closing reviewer | Squad Reviewer | n/a |'
        Set-Content (Join-Path $script:StageWorkspace 'docs/requirements/reviews/closing.md') 'Outcome: Pass'
        Set-Content (Join-Path $script:StageSquad 'history/Squad Reviewer.md') "# History: Squad Reviewer`n* Deliverable: docs/requirements/reviews/closing.md"
        $script:StageMetrics = @{ dispatches = @{ 'Squad Scribe' = 1; 'Squad Reviewer' = 1 } }
        foreach ($Agent in @('BRD Builder', 'PRD Builder', 'BRD Quality Reviewer', 'PRD Quality Reviewer')) {
            $script:StageMetrics.dispatches[$Agent] = 1
            $Relative = "docs/requirements/reviews/$Agent.md"
            Set-Content (Join-Path $script:StageWorkspace $Relative) 'synthetic authored artifact'
            Set-Content (Join-Path $script:StageSquad "history/$Agent.md") "# History: $Agent`n* Deliverable: $Relative"
        }
        foreach ($Name in @('brd.md', 'prd.md')) { Set-Content (Join-Path $script:StageWorkspace "docs/requirements/$Name") 'synthetic published requirements' }
        Mock Invoke-EfficiencyProcess -ModuleName EfficiencyBenchmark { [pscustomobject]@{ exitCode = 0; stopCause = 'none' } }
    }
    It 'accepts initialized state without demanding implementation roles' {
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage init).passed | Should -BeTrue
    }
    It 'accepts requirements with both author and reviewer evidence' {
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeTrue
        foreach ($Agent in @('BRD Builder', 'PRD Builder', 'BRD Quality Reviewer', 'PRD Quality Reviewer')) {
            Set-Content (Join-Path $script:StageSquad "history/$Agent.md") "# History: $Agent`n* Deliverable: ``docs/requirements/reviews/$Agent.md`` (25 bytes); publication copy ``docs/requirements/prd.md``"
        }
        Set-Content (Join-Path $script:StageWorkspace 'docs/requirements/reviews/closing.md') "## Verdict`n`n**Pass** (gate met)."
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeTrue
        foreach ($Agent in @('BRD Builder', 'PRD Builder', 'BRD Quality Reviewer', 'PRD Quality Reviewer')) {
            Set-Content (Join-Path $script:StageSquad "history/$Agent.md") "# History: $Agent`n* Deliverable: docs/requirements/reviews/$Agent.md (25 bytes)"
        }
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeTrue
    }
    It 'rejects a failed or conditional closing review despite complete intake artifacts' {
        foreach ($Verdict in @('Fail', 'Pass-With-Conditions')) {
            Set-Content (Join-Path $script:StageWorkspace 'docs/requirements/reviews/closing.md') "## Verdict`n`n**$Verdict** (gate not met)."
            $Result = Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements
            foreach ($Agent in @('BRD Builder', 'PRD Builder', 'BRD Quality Reviewer', 'PRD Quality Reviewer')) {
                $Result.checks[$Agent] | Should -BeTrue
            }
            $Result.checks['tester'] | Should -BeTrue
            $Result.checks['reviewOutcome'] | Should -BeFalse
            $Result.passed | Should -BeFalse
        }
        Remove-Item (Join-Path $script:StageWorkspace 'docs/requirements/reviews/closing.md')
        $Result = Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements
        $Result.checks['tester'] | Should -BeFalse
        $Result.passed | Should -BeFalse
    }
    It 'rejects a missing reviewer artifact despite existing dispatch and history' {
        Remove-Item (Join-Path $script:StageWorkspace 'docs/requirements/reviews/PRD Quality Reviewer.md')
        Set-Content (Join-Path $script:StageSquad 'history/PRD Quality Reviewer.md') "# History: PRD Quality Reviewer`n* Deliverable: ``docs/requirements/reviews/PRD Quality Reviewer.md`` (25 bytes)"
        $Result = Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements
        $Result.passed | Should -BeFalse
        $Result.checks['PRD Quality Reviewer'] | Should -BeFalse
        Set-Content (Join-Path $script:StageWorkspace 'docs/requirements/reviews/PRD Quality Reviewer.md') 'synthetic authored artifact'
        Set-Content (Join-Path $script:StageSquad 'history/PRD Quality Reviewer.md') "# History: PRD Quality Reviewer`n* Deliverable: ``docs/requirements/reviews/PRD Quality Reviewer.md (25 bytes)``"
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeFalse
    }
    It 'rejects reviewer artifacts with no dispatch history' {
        Remove-Item (Join-Path $script:StageSquad 'history/BRD Quality Reviewer.md')
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeFalse
    }
    It 'requires published <Document> before advancing requirements' -ForEach @(@{ Document = 'brd.md' }, @{ Document = 'prd.md' }) {
        Remove-Item (Join-Path $script:StageWorkspace "docs/requirements/$Document")
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeFalse
    }
    It 'does not accept a history deliverable outside the workspace' {
        Set-Content (Join-Path $TestDrive 'outside.md') 'outside evidence'
        Set-Content (Join-Path $script:StageSquad 'history/BRD Quality Reviewer.md') "# History: BRD Quality Reviewer`n* Deliverable: ../outside.md"
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeFalse
        Set-Content (Join-Path $script:StageSquad 'history/BRD Quality Reviewer.md') "# History: BRD Quality Reviewer`n* Deliverable: ``../outside.md`` (16 bytes)"
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeFalse
        Set-Content (Join-Path $script:StageSquad 'history/BRD Quality Reviewer.md') "# History: BRD Quality Reviewer`n* Deliverable: ../outside.md (16 bytes)"
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeFalse
    }
    It 'rejects empty initialization state even if the external verifier passes' {
        Set-Content (Join-Path $script:StageSquad 'team.md') '' -NoNewline
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage init).passed | Should -BeFalse
    }
    It 'requires observed reviewer dispatches rather than only files' {
        $script:StageMetrics.dispatches.Remove('PRD Quality Reviewer')
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics -Stage requirements).passed | Should -BeFalse
    }
    It 'retains build as the default and requires implementation evidence' {
        (Test-EfficiencyWorkflow -Workspace $script:StageWorkspace -Metrics $script:StageMetrics).passed | Should -BeFalse
    }
}

Describe 'Efficiency quality and comparison gates' -Tag 'Unit' {
    It 'uses CLI-compatible restrictions that leave the independent judge without tools' {
        $Workspace = Join-Path $TestDrive 'judge-workspace'
        $Output = Join-Path $TestDrive 'judge-output'
        New-Item -ItemType Directory -Path (Join-Path $Workspace 'docs/requirements/reviews'), $Output -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $Workspace 'docs/requirements/brd.md') -Value 'Synthetic BRD.'
        Set-Content -LiteralPath (Join-Path $Workspace 'docs/requirements/prd.md') -Value 'Synthetic PRD.'
        Set-Content -LiteralPath (Join-Path $Workspace 'docs/requirements/reviews/closing.md') -Value 'Synthetic closing review.'
        $Cli = Join-Path $TestDrive 'fake-judge-cli.ps1'
        @'
$ErrorActionPreference = 'Stop'
$null = [Console]::In.ReadToEnd()
@{ arguments = @($args) } | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath (Join-Path $PWD 'judge-argv.json') -Encoding utf8NoBOM
exit 37
'@ | Set-Content -LiteralPath $Cli -Encoding utf8NoBOM

        $Result = Invoke-EfficiencyJudge -Workspace $Workspace -Out $Output -CliPath $Cli -Model 'fake-model' -MaxCredits 1 -ReviewPath 'docs/requirements/reviews/closing.md'

        $Result.valid | Should -BeFalse
        $Result.process.exitCode | Should -Be 37
        $Arguments = (Get-Content -LiteralPath (Join-Path $Output 'judge-argv.json') -Raw | ConvertFrom-Json -AsHashtable).arguments
        $AllowedIndex = [array]::IndexOf($Arguments, '--available-tools')
        $DeniedIndex = [array]::IndexOf($Arguments, '--deny-tool')
        $AllowedIndex | Should -BeGreaterThan 0
        $Arguments[$AllowedIndex + 1] | Should -Be 'view'
        $DeniedIndex | Should -BeGreaterThan 0
        $Arguments[$DeniedIndex + 1] | Should -Be 'view'
        foreach ($BroadPermission in @('--allow-all', '--yolo', '--allow-all-tools', '--allow-all-paths', '--allow-all-urls')) {
            $Arguments | Should -Not -Contain $BroadPermission
        }
        foreach ($PreservedOption in @('--no-custom-instructions', '--disable-builtin-mcps', '--no-remote', '--no-remote-export')) {
            $Arguments | Should -Contain $PreservedOption
        }
    }

    It 'requires three pairs and includes independently metered judge work' {
        $Report = Compare-EfficiencyRuns @(New-TestRuns)
        $Report.eligible | Should -BeTrue
        $Report.metrics.modelRequests.baseline | Should -Be 105
        $Report.metrics.modelRequests.candidate | Should -Be 85
        $Report.pairs.Count | Should -Be 3
    }
    It 'rejects missing observations rather than interpreting them as zero' {
        $Runs = @(New-TestRuns); $Runs[3].metrics.totals.inputTokens = $null
        { Compare-EfficiencyRuns $Runs } | Should -Throw
    }
    It 'rejects incompatible runs and duplicate pair identities' {
        $Runs = @(New-TestRuns); $Runs[3].metadata.compatibility.cli = 'different'
        { Compare-EfficiencyRuns $Runs } | Should -Throw '*Incompatible*'
        foreach ($Key in @('hostProfile', 'preparationHash', 'exerciseHash')) {
            $Runs = @(New-TestRuns)
            foreach ($Run in $Runs) { $Run.metadata.compatibility[$Key] = 'same' }
            $Runs[3].metadata.compatibility[$Key] = 'different'
            { Compare-EfficiencyRuns $Runs } | Should -Throw '*Incompatible*'
        }
        $Runs = @(New-TestRuns); $Runs[3].metadata.pair = 2
        { Compare-EfficiencyRuns $Runs } | Should -Throw '*Duplicate*'
    }
    It 'does not trust a saved completed flag when independent checks fail' {
        $Runs = @(New-TestRuns); $Runs[3].workflow.passed = $false
        (Compare-EfficiencyRuns $Runs).eligible | Should -BeFalse
        $Run = @(New-TestRuns)[0]
        $Limit = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'efficiency-scenario.json') -Raw | ConvertFrom-Json).maxModelRequests
        $Run.judge.metrics.modelRequests = 10
        $Run.metrics.modelRequests = $Limit - 10
        Test-EfficiencyRun $Run | Should -BeTrue
        $Run.metrics.modelRequests++
        Test-EfficiencyRun $Run | Should -BeFalse
    }
    It 'refuses offline promotion when a required stage is missing despite a saved success flag' {
        $Runs = @(New-TestRuns); $Runs[3].stages[2].passed = $false
        (Compare-EfficiencyRuns $Runs).eligible | Should -BeFalse
        { Save-EfficiencyBaseline -Runs $Runs -Path (Join-Path $TestDrive 'missing-stage.json') } | Should -Throw '*not eligible*'
    }
    It 'rejects a faster candidate whose quality declines' {
        $Runs = @(New-TestRuns)
        foreach ($Run in $Runs | Where-Object { $_.metadata.arm -eq 'candidate' }) { $Run.judge.response.scores.businessClarity = 19 }
        $Report = Compare-EfficiencyRuns $Runs
        $Report.eligible | Should -BeFalse
        $Report.reasons -join ',' | Should -Match 'Quality'
    }
    It 'rejects excessive secondary metric regression' {
        $Runs = @(New-TestRuns)
        foreach ($Run in $Runs | Where-Object { $_.metadata.arm -eq 'candidate' }) { $Run.metrics.totals.outputTokens = 2000 }
        (Compare-EfficiencyRuns $Runs).eligible | Should -BeFalse
    }
    It 'requires matching judge document hashes and evidence for every dimension' {
        $Run = @(New-TestRuns)[0]
        $Run.judge.response.documentHashes = @{ brd = 'wrong'; prd = 'wrong' }
        Test-EfficiencyJudge $Run.judge.response $Run.judge.documentHashes | Should -BeFalse
        { Compare-EfficiencyRuns @(New-TestRuns | ForEach-Object { $_.judge.response.evidence.businessClarity = ''; $_ }) } | Should -Throw
    }
    It 'rejects extra score fields rather than inflating the frozen quality total' {
        $Run = @(New-TestRuns)[0]
        $Run.judge.response.scores['bonus'] = 1000
        Test-EfficiencyJudge $Run.judge.response $Run.judge.documentHashes | Should -BeFalse
    }
    It 'preserves the initial report and refuses failed promotion' {
        $Path = Join-Path $TestDrive 'accepted.json'
        Save-EfficiencyBaseline -Runs @(New-TestRuns) -Path $Path | Out-Null
        $Initial = (Get-FileHash ($Path + '.initial.json')).Hash
        Save-EfficiencyBaseline -Runs @(New-TestRuns) -Path $Path | Out-Null
        (Get-FileHash ($Path + '.initial.json')).Hash | Should -Be $Initial
        $Before = (Get-FileHash $Path).Hash
        $Runs = @(New-TestRuns); $Runs[3].acceptance.passed = $false
        { Save-EfficiencyBaseline $Runs $Path } | Should -Throw
        (Get-FileHash $Path).Hash | Should -Be $Before
    }
    It 'refuses a live launch without explicit opt-in and isolation' {
        $Output = Join-Path $TestDrive 'blocked-launch.txt'
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'), '-Mode', 'Run') -WorkingDirectory $TestDrive -OutputPath $Output -TimeoutSeconds 10
        $Result.exitCode | Should -Be 1
        Get-Content ($Output + '.stderr') -Raw | Should -Match 'requires -Live'
    }
    It 'returns exit two and preserves reports for an incomplete Analyze command' {
        $Events = Join-Path $TestDrive 'analyze-events.jsonl'
        New-TestEvent 'tool.execution_start' @{ toolCallId = 'unfinished'; toolName = 'view' } | Set-Content $Events
        $Destination = Join-Path $TestDrive 'analysis'
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'), '-Mode', 'Analyze', '-EventsPath', $Events, '-OutputPath', $Destination) -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'analysis-stdout.txt') -TimeoutSeconds 10
        $Result.exitCode | Should -Be 2
        (Get-Content (Join-Path $Destination 'metrics.json') -Raw | ConvertFrom-Json).complete | Should -BeFalse
        Test-Path (Join-Path $Destination 'events.jsonl') | Should -BeTrue
    }
    It 'actually launches an Establish child and retains its failed preflight stderr' {
        $Source = Join-Path $TestDrive 'launch-source'
        $Install = Join-Path $TestDrive 'launch-install'
        $Trial = Join-Path $TestDrive 'launch-series'
        New-Item -ItemType Directory -Path (Join-Path $Source 'squad-src/.github/agents'), (Join-Path $Install '.github/agents') -Force | Out-Null
        foreach ($Name in @('squad-coordinator.agent.md', 'brd-builder.agent.md', 'prd-builder.agent.md')) { Set-Content -LiteralPath (Join-Path $Install ".github/agents/$Name") -Value 'offline fixture' }
        $Cli = Join-Path $TestDrive 'no-model-cli.ps1'
        @'
if ($args -contains 'mcp') { '{"mcpServers":{}}' }
elseif ($args -contains '--help') { 'OFFLINE PREFLIGHT SENTINEL: no live invocation is supported' }
elseif ($args -contains '--version') { 'offline-cli-1.0' }
else { throw 'A model-backed invocation is forbidden in this test.' }
exit 0
'@ | Set-Content -LiteralPath $Cli -Encoding utf8NoBOM
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'), '-Mode', 'Establish', '-SourceRoot', $Source, '-InstallRoot', $Install, '-CliPath', $Cli, '-TrialRoot', $Trial, '-MaxCredits', '1', '-MaxSeriesCredits', '3', '-Live', '-IsolatedEnvironment') -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'establish-command.txt') -TimeoutSeconds 30 -InputText ''
        $Result.exitCode | Should -Be 2
        $LaunchError = Join-Path $Trial 'out/baseline-1-launch.jsonl.stderr'
        Test-Path -LiteralPath $LaunchError | Should -BeTrue
        Get-Content -LiteralPath $LaunchError -Raw | Should -Match 'does not support --session-id'
        $Report = Get-Content -LiteralPath (Join-Path $Trial 'out/report.json') -Raw | ConvertFrom-Json
        $Report.outcome | Should -Be incomplete
        $Report.slots[0].status | Should -Be failed
        $Report.slots[0].reason | Should -Be 'child-exited-without-run-evidence'
        $Report.slots[0].childExitCode | Should -Be 1
        $Report.slots[0].evidence | Should -Contain 'out/baseline-1-launch.jsonl.stderr'
        Get-Content -LiteralPath (Join-Path $Trial 'out/report.md') -Raw | Should -Match 'Failure Diagnostics'
        Get-Content -LiteralPath (Join-Path $Trial 'out/report.json') -Raw | Should -Not -Match 'OFFLINE PREFLIGHT SENTINEL|does not support --session-id'
        $Report.slots[1].status | Should -Be 'not-run'
    }
    It 'stops after zero-exit initialization with missing readiness evidence' {
        $Install = Join-Path $TestDrive 'incomplete-install'; $Trial = Join-Path $TestDrive 'incomplete-run'
        New-Item -ItemType Directory -Path (Join-Path $Install '.github/agents') -Force | Out-Null
        foreach ($Name in @('squad-coordinator.agent.md', 'brd-builder.agent.md', 'prd-builder.agent.md')) { Set-Content (Join-Path $Install ".github/agents/$Name") 'offline fixture' }
        $Cli = Join-Path $TestDrive 'incomplete-cli.ps1'
        @'
if ($args -contains 'mcp') { '{"mcpServers":{}}'; exit 0 }
if ($args -contains '--version') { 'offline-incomplete-cli'; exit 0 }
if ($args -contains '--help') { '--session-id --max-ai-credits --no-ask-user --max-autopilot-continues --usage-output-file --no-remote --no-remote-export --add-dir'; exit 0 }
Add-Content 'stage-launches.txt' 'one invocation'
$Session = $args[[array]::IndexOf($args, '--session-id') + 1]
$SessionRoot = Join-Path $HOME ".copilot/session-state/$Session"
New-Item -ItemType Directory -Path $SessionRoot -Force | Out-Null
1..100 | ForEach-Object { @{ type = 'session.usage_record'; data = @{ usage = @{ inputTokens = 10; outputTokens = 1; aiCreditsStatus = 'complete'; copilotUsage = @{ totalNanoAiu = 1000000 }; accounting = @{ sourceSessionId = $Session; usageId = "fake-usage-$_" } } } } | ConvertTo-Json -Depth 8 -Compress } | Set-Content (Join-Path $SessionRoot 'events.jsonl')
exit 0
'@ | Set-Content $Cli -Encoding utf8NoBOM
        $Source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'), '-Mode', 'Run', '-SourceRoot', $Source, '-InstallRoot', $Install, '-CliPath', $Cli, '-TrialRoot', $Trial, '-MaxCredits', '1', '-Live', '-IsolatedEnvironment') -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'incomplete-command.txt') -TimeoutSeconds 60 -InputText ''
        $Run = Get-Content (Join-Path $Trial 'out/run.json') -Raw | ConvertFrom-Json
        try {
            $Result.exitCode | Should -Be 2
            @($Run.stages).Count | Should -Be 1
            $Run.stages[0].process.exitCode | Should -Be 0
            $Run.stages[0].process.stopCause | Should -Be 'none'
            $Run.stages[0].process.observedRequests | Should -Be 100
            $Run.stages[0].readiness.passed | Should -BeFalse
            $Run.stages[0].passed | Should -BeFalse
            @(Get-Content (Join-Path $Trial 'workspace/stage-launches.txt')).Count | Should -Be 1
            $Run.judge | Should -BeNullOrEmpty
        }
        finally { Remove-Item (Join-Path $HOME ".copilot/session-state/$($Run.metadata.sessionId)") -Recurse -Force }
    }
    It 'passes the full init prompt and options as valid argv elements to the CLI process' {
        $Install = Join-Path $TestDrive 'argv-install'; $Trial = Join-Path $TestDrive 'argv-run'
        New-Item -ItemType Directory -Path (Join-Path $Install '.github/agents'), (Join-Path $Install '.github/instructions') -Force | Out-Null
        foreach ($Name in @('squad-coordinator.agent.md', 'brd-builder.agent.md', 'prd-builder.agent.md')) { Set-Content -LiteralPath (Join-Path $Install ".github/agents/$Name") -Value 'offline fixture' }
        Set-Content -LiteralPath (Join-Path $Install '.github/instructions/retained.instructions.md') -Value 'retained dependency rule'
        $Cli = Join-Path $TestDrive 'argv-only-cli.ps1'
        @'
if ($args -contains 'mcp') { '{"mcpServers":{}}'; exit 0 }
if ($args -contains '--version') { 'offline-argv-cli'; exit 0 }
if ($args -contains '--help') { '--session-id --max-ai-credits --no-ask-user --max-autopilot-continues --usage-output-file --no-remote --no-remote-export --add-dir'; exit 0 }
@{ arguments = @($args); repoHooks = $env:GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS; stateParentsReady = (Test-Path -LiteralPath '.copilot-tracking/squad/history' -PathType Container); stateFiles = if(Test-Path -LiteralPath '.copilot-tracking/squad'){@(Get-ChildItem -LiteralPath '.copilot-tracking/squad' -Recurse -File).Count}else{-1} } | ConvertTo-Json -Depth 6 -Compress
exit 37
'@ | Set-Content -LiteralPath $Cli -Encoding utf8NoBOM
        $Source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'), '-Mode', 'Run', '-SourceRoot', $Source, '-InstallRoot', $Install, '-CliPath', $Cli, '-TrialRoot', $Trial, '-MaxCredits', '1', '-Live', '-IsolatedEnvironment') -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'argv-command.txt') -TimeoutSeconds 60 -InputText ''
        $Result.exitCode | Should -Be 2
        $Captured = Get-Content -LiteralPath (Join-Path $Trial 'out/init-stdout.jsonl') -Raw | ConvertFrom-Json
        $Captured.arguments[0] | Should -Be '-p'
        $Captured.arguments[1] | Should -Match '^This is a synthetic, preauthorized exercise.*Initialization only; no substantive business deliverables yet\.$'
        $Captured.arguments[2] | Should -Be '--agent'
        $Captured.arguments | Should -Contain '--secret-env-vars=GH_TOKEN,GITHUB_TOKEN,COPILOT_GITHUB_TOKEN'
        $Captured.arguments | Should -Not -Contain 'GITHUB_TOKEN'
        $Captured.arguments | Should -Not -Contain '--trust-folder'
        $Captured.arguments | Should -Contain '--session-id'
        $Captured.arguments | Should -Contain '--allow-all-tools'
        $DirectoryIndex = [array]::IndexOf($Captured.arguments, '--add-dir')
        $DirectoryIndex | Should -BeGreaterThan 0
        $Captured.arguments[$DirectoryIndex + 1] | Should -Be (Join-Path $Trial 'workspace')
        $Captured.arguments | Should -Not -Contain '--allow-all-paths'
        $Captured.arguments | Should -Not -Contain '--allow-all-urls'
        $Captured.arguments | Should -Contain 'shell(git push)'
        $Captured.arguments[1] | Should -Match 'split large reference reads into explicit ranges'
        $Captured.arguments[1] | Should -Match 'one complete Scribe handoff per completed dispatch'
        $Captured.arguments[1] | Should -Match 'every dispatched role and Scribe prompt, outside any schema payload'
        $Captured.arguments[1] | Should -Match ([regex]::Escape("absolute workspace '$(Join-Path $Trial 'workspace')'; absolute skill root '$(Join-Path $Trial 'workspace')/.agents/skills'"))
        $Captured.repoHooks | Should -Be 'true'
        $Captured.stateParentsReady | Should -BeTrue
        $Captured.stateFiles | Should -Be 0
        $Run = Get-Content -LiteralPath (Join-Path $Trial 'out/run.json') -Raw | ConvertFrom-Json
        $Run.stages[0].process.exitCode | Should -Be 37
        $Run.completed | Should -BeFalse
        $Run.metadata.hostProfile | Should -Be 'native-cli-references'
        $Run.metadata.compatibility.hostProfile | Should -Be $Run.metadata.hostProfile
        $Run.metadata.compatibility.preparationHash | Should -Be (Get-FileHash -LiteralPath (Join-Path $Source 'tests/lib/SquadInstall.psm1')).Hash
        $Run.metadata.compatibility.exerciseHash | Should -Be (Get-FileHash -LiteralPath (Join-Path $Source 'tests/tier2/live-benchmark/Invoke-EfficiencyExercise.ps1')).Hash
        $Workspace = Join-Path $Trial 'workspace'
        Get-Content -LiteralPath (Join-Path $Workspace '.github/instructions/retained.instructions.md') -Raw |
            Should -Match 'retained dependency rule'
        foreach ($Rule in Get-ChildItem -LiteralPath (Join-Path $Source 'squad-src/.github/instructions/squad') -File -Filter '*.instructions.md') {
            $Name = $Rule.Name -replace '\.instructions\.md$', ''
            $Ported = Join-Path $Workspace ".agents/skills/squad/references/rules/$Name.md"
            Test-Path -LiteralPath $Ported -PathType Leaf | Should -BeTrue
            $Body = (Get-Content -LiteralPath $Rule.FullName -Raw) -replace '(?s)^\uFEFF?---\r?\n.*?\r?\n---\r?\n', ''
            $Heading = [regex]::Match($Body, '(?m)^# .+$').Value
            Get-Content -LiteralPath $Ported -Raw | Should -Match ([regex]::Escape($Heading))
            Test-Path -LiteralPath (Join-Path $Workspace ".github/instructions/$($Rule.Name)") |
                Should -Be ($Rule.Name -eq 'squad-floor.instructions.md')
        }
        $Coordinator = Get-Content -LiteralPath (Join-Path $Workspace '.github/agents/squad-coordinator.agent.md') -Raw
        $Coordinator | Should -Match '\.agents/skills/squad/references/rules/squad-roster\.md'
        $Coordinator | Should -Match 'unconditional floor still auto-applies'
        $Coordinator | Should -Not -Match '\.agents/\.agents/'
    }
}

Describe 'Independent functional acceptance contract' -Tag 'Unit' {
    It 'passes all probes on a conformant reference CLI' {
        $Workspace = Join-Path $TestDrive 'reference'; New-Item -ItemType Directory -Path (Join-Path $Workspace 'src') -Force | Out-Null
        @'
param([ValidateSet('add','list','done')][string]$Action,[string]$Store,[string]$Title,[int]$Id,[ValidateSet('all','open','done')][string]$Status='all')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
try {
    $Tasks=@()
    if (Test-Path -LiteralPath $Store) { $Tasks=@(Get-Content -LiteralPath $Store -Raw | ConvertFrom-Json -AsHashtable) }
    if ($Action -eq 'add') {
        if ([string]::IsNullOrWhiteSpace($Title)) {throw 'title'}
        $Maximum=0; foreach ($Task in $Tasks) {if ($Task.id -gt $Maximum) {$Maximum=$Task.id}}
        $Result=@{id=$Maximum+1;title=$Title;status='open'}; $Tasks+=,$Result
    } elseif ($Action -eq 'done') {
        $Found=@($Tasks | Where-Object id -EQ $Id); if ($Found.Count -ne 1) {throw 'id'}
        $Found[0].status='done'; $Result=$Found[0]
    } elseif ($Action -eq 'list') {
        $Selected=@($Tasks | Where-Object {$Status -eq 'all' -or $_.status -eq $Status} | Sort-Object id)
        ConvertTo-Json -InputObject $Selected -Depth 8 -Compress; exit 0
    } else {throw 'action'}
    ConvertTo-Json -InputObject $Tasks -Depth 8 | Set-Content -LiteralPath $Store -Encoding utf8NoBOM
    $Result | ConvertTo-Json -Compress
} catch {exit 1}
'@ | Set-Content -LiteralPath (Join-Path $Workspace 'src/task.ps1') -Encoding utf8NoBOM
        $Result = & (Join-Path $PSScriptRoot 'Test-EfficiencyTask.ps1') -Workspace $Workspace | ConvertFrom-Json
        $Result.checks.Count | Should -Be 12
        $Result.passed | Should -BeTrue -Because (@($Result.checks | Where-Object { -not $_.passed } | ForEach-Object name) -join ', ')
    }
}

Describe 'Unattended series lifecycle' -Tag 'Unit' {
    BeforeEach {
        $script:SeriesCalls = [Collections.Generic.List[string]]::new()
        $script:Trial = {
            param($Arm, $Pair, $Credits)
            $script:SeriesCalls.Add("$Arm-$Pair")
            @(New-TestRuns | Where-Object { $_.metadata.arm -eq $Arm -and $_.metadata.pair -eq $Pair })[0]
        }
    }
    It 'establishes exactly three controls with no invented improvement or prior score' {
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial $script:Trial -PerRunCredits 10 -SeriesCredits 30
        $Result.exitCode | Should -Be 0
        $Result.report.message | Should -Be 'baseline established; no previous comparison available'
        $Result.report.previousComparisonAvailable | Should -BeFalse
        $Result.report.efficiency | Should -BeNullOrEmpty
        $Result.controls.runs.Count | Should -Be 3
        $script:SeriesCalls.Count | Should -Be 3
    }
    It 'executes all six paired slots and automatically compares without promotion' {
        $Result = Invoke-EfficiencySeries -Kind Series -RunTrial $script:Trial -PerRunCredits 10 -SeriesCredits 60
        $Result.exitCode | Should -Be 0
        $script:SeriesCalls -join ',' | Should -Be 'baseline-1,candidate-1,candidate-2,baseline-2,baseline-3,candidate-3'
        $Result.report.outcome | Should -Be 'passed'
        $Result.report.acceptedBaselineChanged | Should -BeFalse
        $Result.report.pairwiseDeltas.Count | Should -Be 3
    }
    It 'reuses exactly three compatible saved controls' {
        $Controls = @{ schemaVersion = 'efficiency-control-v1'; runs = @(New-TestRuns | Where-Object { $_.metadata.arm -eq 'baseline' }) }
        $Result = Invoke-EfficiencySeries -Kind Series -RunTrial $script:Trial -PerRunCredits 10 -SeriesCredits 30 -BaselineEvidence $Controls -ExpectedCompatibility $Controls.runs[0].metadata.compatibility
        $Result.exitCode | Should -Be 0
        $script:SeriesCalls -join ',' | Should -Be 'candidate-1,candidate-2,candidate-3'
        $Result.report.reusedControlRuns | Should -Be 3
    }
    It 'rejects incompatible saved controls before launching anything' {
        $Controls = @{ schemaVersion = 'efficiency-control-v1'; runs = @(New-TestRuns | Where-Object { $_.metadata.arm -eq 'baseline' }) }
        { Invoke-EfficiencySeries -Kind Series -RunTrial $script:Trial -PerRunCredits 10 -SeriesCredits 30 -BaselineEvidence $Controls -ExpectedCompatibility @{ cli = 'different' } } | Should -Throw '*compatibility*'
        $script:SeriesCalls.Count | Should -Be 0
    }
    It 'rejects incorrectly paired saved controls before launching anything' {
        $Controls = @{ schemaVersion = 'efficiency-control-v1'; runs = @(New-TestRuns | Where-Object { $_.metadata.arm -eq 'baseline' }) }
        $Controls.runs[2].metadata.pair = 1
        { Invoke-EfficiencySeries -Kind Series -RunTrial $script:Trial -PerRunCredits 10 -SeriesCredits 30 -BaselineEvidence $Controls -ExpectedCompatibility $Controls.runs[0].metadata.compatibility } | Should -Throw '*paired*'
        $script:SeriesCalls.Count | Should -Be 0
    }
    It 'does not establish a control series whose source changes between trials' {
        $Trial = { param($Arm, $Pair, $Credits) $Run = @(New-TestRuns | Where-Object { $_.metadata.arm -eq $Arm -and $_.metadata.pair -eq $Pair })[0]; $Run.metadata.sourceHash = "changed-$Pair"; $Run }
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial $Trial -PerRunCredits 10 -SeriesCredits 30
        $Result.exitCode | Should -Be 2
        $Result.controls | Should -BeNullOrEmpty
    }
    It 'rejects insufficient series spending bounds before launching anything' {
        { Invoke-EfficiencySeries -Kind Series -RunTrial $script:Trial -PerRunCredits 10 -SeriesCredits 59 } | Should -Throw '*ceiling*'
        $script:SeriesCalls.Count | Should -Be 0
    }
    It 'preserves a failed trial and all unstarted slots without retries' {
        $Trial = { param($Arm, $Pair, $Credits) $script:SeriesCalls.Add("$Arm-$Pair"); $Run = @(New-TestRuns)[0]; $Run.acceptance.passed = $false; $Run }
        $Result = Invoke-EfficiencySeries -Kind Series -RunTrial $Trial -PerRunCredits 10 -SeriesCredits 60
        $Result.exitCode | Should -Be 2
        $Result.report.slots.Count | Should -Be 6
        @($Result.report.slots | Where-Object status -EQ 'not-run').Count | Should -Be 5
        $Result.report.trials.Count | Should -Be 1
        $script:SeriesCalls.Count | Should -Be 1
    }
    It 'reports missing trial evidence as incomplete rather than passing an empty series' {
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial { throw 'missing' } -PerRunCredits 10 -SeriesCredits 30
        $Result.exitCode | Should -Be 2
        $Result.report.outcome | Should -Be 'incomplete'
        $Result.controls | Should -BeNullOrEmpty
    }
    It 'reports missing judge or telemetry as failed checks without losing the failure category' {
        $Trial = { param($Arm, $Pair, $Credits) $Run = @(New-TestRuns)[0]; $Run.completed = $false; $Run.judge = $null; $Run.metrics = $null; $Run }
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial $Trial -PerRunCredits 10 -SeriesCredits 30
        $Result.report.slots[0].reason | Should -Be 'run-failed-independent-checks'
        $Result.report.slots[0].checks.judge | Should -BeFalse
        $Result.report.slots[0].checks.telemetry | Should -BeFalse
        $Result.exitCode | Should -Be 2
    }
    It 'reports an immediate init process failure without calling it a document-quality failure' {
        $Trial = { param($Arm, $Pair, $Credits) $Run = @(New-TestRuns)[0]; $Run.completed = $false; $Run.stages = @(@{ name = 'init'; passed = $false; process = @{ exitCode = 1; stopCause = 'none' } }); $Run.judge = $null; $Run.metrics = $null; $Run }
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial $Trial -PerRunCredits 10 -SeriesCredits 30
        $Result.report.slots[0].failedStages[0].name | Should -Be init
        $Result.report.slots[0].failedStages[0].exitCode | Should -Be 1
        $Result.report.slots[0].failedStages[0].stopCause | Should -Be none
        $Result.report.quality.scores.Count | Should -Be 0
        $Result.exitCode | Should -Be 2
    }
    It 'does not leak arbitrary callback exception text into portable reports' {
        $Result = Invoke-EfficiencySeries -Kind Establish -RunTrial { throw 'PRIVATE-TOKEN-OR-PROMPT-CONTENT' } -PerRunCredits 10 -SeriesCredits 30
        $Result.report | ConvertTo-Json -Depth 30 | Should -Not -Match 'PRIVATE-TOKEN-OR-PROMPT-CONTENT'
        $Result.report.slots[0].reason | Should -Be 'trial-error-or-missing-evidence'
    }
}

Describe 'Runtime limits and closing review evidence' -Tag 'Unit' {
    It 'stops a subprocess when the observed request budget is exhausted' {
        $Events = Join-Path $TestDrive 'budget-events.jsonl'
        $Encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(((New-TestUsage) + "`n")))
        $Command = "[IO.File]::WriteAllText('$Events',[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$Encoded'))); while (`$true) {}"
        $Result = Invoke-EfficiencyProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', $Command) -WorkingDirectory $TestDrive -OutputPath (Join-Path $TestDrive 'budget-stdout.txt') -EventsPath $Events -MaxRequests 1 -TimeoutSeconds 10
        $Result.stopCause | Should -Be 'request-limit'
    }
    It 'requires a passing outcome in the actual closing review artifact' {
        Mock Invoke-EfficiencyProcess -ModuleName EfficiencyBenchmark { @{ exitCode = 0; stopCause = 'none' } }
        $Root = Join-Path $TestDrive 'workflow'; $Squad = Join-Path $Root '.copilot-tracking/squad'
        New-Item -ItemType Directory -Path (Join-Path $Squad 'history'), (Join-Path $Root 'artifacts') -Force | Out-Null
        foreach ($Name in @('routing.md', 'state.json', 'decisions.md', 'consumption.md', 'consumption-rates.md')) { Set-Content (Join-Path $Squad $Name) 'fixture' }
        $Rows = @(); $Dispatches = @{}
        foreach ($Role in @('researcher', 'lead', 'developer', 'tester')) {
            $Agent = "Test $Role"; $Dispatches[$Agent] = 1
            $Rows += "| $Role | member | $Agent | none |"
            Set-Content (Join-Path $Root "artifacts/$Role.md") 'Verdict: Pass'
            Set-Content (Join-Path $Squad "history/$Agent.md") "# History: $Agent`n* Deliverable: artifacts/$Role.md"
        }
        Set-Content (Join-Path $Squad 'team.md') $Rows
        (Test-EfficiencyWorkflow $Root @{ dispatches = $Dispatches }).passed | Should -BeTrue
        Set-Content (Join-Path $Root 'artifacts/tester.md') 'Verdict: Fail'
        (Test-EfficiencyWorkflow $Root @{ dispatches = $Dispatches }).passed | Should -BeFalse
    }
}