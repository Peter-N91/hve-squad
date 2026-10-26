# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SquadSessionLogPath {
    <#
    .SYNOPSIS
        Resolves an explicit events.jsonl path or the newest Copilot session for a repository.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionLog,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    if ($SessionLog -ne 'auto') {
        $candidate = if (Test-Path -LiteralPath $SessionLog -PathType Container) {
            Join-Path $SessionLog 'events.jsonl'
        }
        else {
            $SessionLog
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Session log '$SessionLog' does not resolve to an events.jsonl file."
        }
        return (Resolve-Path -LiteralPath $candidate).ProviderPath
    }

    $repository = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' }
    $stateRoot = Join-Path $copilotHome 'session-state'
    if (-not (Test-Path -LiteralPath $stateRoot -PathType Container)) { return $null }

    $candidates = [Collections.Generic.List[IO.FileInfo]]::new()
    foreach ($directory in [IO.Directory]::EnumerateDirectories($stateRoot)) {
        $events = [IO.FileInfo]::new([IO.Path]::Combine($directory, 'events.jsonl'))
        if ($events.Exists) { $candidates.Add($events) }
    }
    $candidates.Sort([Comparison[IO.FileInfo]] {
            param($left, $right)
            $right.LastWriteTimeUtc.CompareTo($left.LastWriteTimeUtc)
        })

    foreach ($events in $candidates) {
        $workspace = Join-Path $events.DirectoryName 'workspace.yaml'
        if (-not (Test-Path -LiteralPath $workspace -PathType Leaf)) { continue }
        $match = [regex]::Match([IO.File]::ReadAllText($workspace), '(?m)^cwd:\s*(?<cwd>.+?)\s*$')
        if (-not $match.Success) { continue }
        try {
            $cwd = [IO.Path]::GetFullPath($match.Groups['cwd'].Value.Trim('"', "'")).TrimEnd('\', '/')
        }
        catch {
            continue
        }
        if ([string]::Equals($cwd, $repository, [StringComparison]::OrdinalIgnoreCase)) {
            return $events.FullName
        }
    }
    return $null
}

function Add-SquadNativeUsageRecord {
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Usage,
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$Seen,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Problems,
        [Parameter(Mandatory)][hashtable]$Totals
    )

    if (-not $Seen.Add($Identity)) {
        $Totals.duplicates++
        return
    }

    $native = $Usage['copilotUsage']
    if ($Usage['aiCreditsStatus'] -ne 'complete') {
        $Problems.Add("$Identity has aiCreditsStatus '$($Usage['aiCreditsStatus'])', not complete.")
        return
    }
    if ($native -isnot [Collections.IDictionary]) {
        $Problems.Add("$Identity has no copilotUsage object.")
        return
    }
    $value = $native['totalNanoAiu']
    if ($null -eq $value -or $value -isnot [ValueType] -or $value -is [bool]) {
        $Problems.Add("$Identity has no numeric totalNanoAiu.")
        return
    }
    $number = [decimal]0
    try { $number = [decimal]$value }
    catch {
        $Problems.Add("$Identity has an invalid totalNanoAiu.")
        return
    }
    if ($number -lt 0) {
        $Problems.Add("$Identity has a negative totalNanoAiu.")
        return
    }
    $Totals.nanoAiu += $number
    $Totals.records++
    $breakdown = ConvertTo-SquadNativeTokenBreakdown -Usage $Usage -Identity $Identity -Problems $Problems
    if ($null -eq $breakdown) { return }
    $Totals.inputTokens += [long]$breakdown.inputTokens
    $Totals.outputTokens += [long]$breakdown.outputTokens
    $Totals.cacheReadTokens += [long]$breakdown.cacheReadTokens
    $Totals.cacheWriteTokens += [long]$breakdown.cacheWriteTokens
    $model = [string]$Usage['model']
    if ($model) {
        if (-not $Totals.models.Contains($model)) {
            $Totals.models[$model] = [ordered]@{ records = 0; nanoAiu = [decimal]0 }
        }
        $Totals.models[$model].records++
        $Totals.models[$model].nanoAiu += $number
    }
}

function ConvertTo-SquadNativeTokenBreakdown {
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Usage,
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Problems
    )

    $native = $Usage['copilotUsage']
    if ($native -isnot [Collections.IDictionary]) {
        $Problems.Add("$Identity has no copilotUsage object.")
        return $null
    }

    $nativeNanoAiu = [decimal]0
    try { $nativeNanoAiu = [decimal]$native['totalNanoAiu'] }
    catch {
        $Problems.Add("$Identity has an invalid totalNanoAiu.")
        return $null
    }

    $tokens = [ordered]@{
        inputTokens = 0L
        cacheReadTokens = 0L
        cacheWriteTokens = 0L
        outputTokens = 0L
    }
    $rawDetails = $native['tokenDetails']
    [object[]]$details = @()
    if ($null -ne $rawDetails) { $details = @($rawDetails) }
    if ($details.Count -gt 0) {
        $calculatedNanoAiu = [decimal]0
        $fieldByType = @{
            input = 'inputTokens'
            cache_read = 'cacheReadTokens'
            cache_write = 'cacheWriteTokens'
            output = 'outputTokens'
        }
        foreach ($detail in $details) {
            if ($detail -isnot [Collections.IDictionary]) {
                $Problems.Add("$Identity has a malformed tokenDetails entry.")
                return $null
            }
            $tokenType = [string]$detail['tokenType']
            if (-not $fieldByType.ContainsKey($tokenType)) {
                $Problems.Add("$Identity has unsupported billed token type '$tokenType'.")
                return $null
            }
            $tokenCount = 0L
            if (-not [long]::TryParse([string]$detail['tokenCount'], [ref]$tokenCount) -or $tokenCount -lt 0) {
                $Problems.Add("$Identity has invalid tokenDetails tokenCount.")
                return $null
            }
            $batchSize = [decimal]0
            $costPerBatch = [decimal]0
            try {
                $batchSize = [decimal]$detail['batchSize']
                $costPerBatch = [decimal]$detail['costPerBatch']
            }
            catch {
                $Problems.Add("$Identity has invalid tokenDetails pricing.")
                return $null
            }
            if ($batchSize -le 0 -or $costPerBatch -lt 0) {
                $Problems.Add("$Identity has non-positive tokenDetails batchSize or negative pricing.")
                return $null
            }
            $tokens[$fieldByType[$tokenType]] += $tokenCount
            $calculatedNanoAiu += [decimal]$tokenCount * $costPerBatch / $batchSize
        }
        if ([decimal]::Abs($calculatedNanoAiu - $nativeNanoAiu) -gt [decimal]0.5) {
            $Problems.Add("$Identity tokenDetails price to $calculatedNanoAiu nano-AIU, not $nativeNanoAiu.")
            return $null
        }
        return [pscustomobject]$tokens
    }

    $inclusiveInput = 0L
    foreach ($pair in @(
            @{ key = 'inputTokens'; variable = 'inclusiveInput' }
            @{ key = 'cacheReadTokens'; variable = 'cacheReadTokens' }
            @{ key = 'cacheWriteTokens'; variable = 'cacheWriteTokens' }
            @{ key = 'outputTokens'; variable = 'outputTokens' }
        )) {
        $value = 0L
        if (-not [long]::TryParse([string]$Usage[$pair.key], [ref]$value) -or $value -lt 0) {
            $Problems.Add("$Identity has invalid $($pair.key).")
            return $null
        }
        if ($pair.variable -eq 'inclusiveInput') { $inclusiveInput = $value }
        else { $tokens[$pair.variable] = $value }
    }
    $tokens.inputTokens = $inclusiveInput - $tokens.cacheReadTokens - $tokens.cacheWriteTokens
    if ($tokens.inputTokens -lt 0) {
        $Problems.Add("$Identity inputTokens is smaller than cacheReadTokens plus cacheWriteTokens.")
        return $null
    }
    [pscustomobject]$tokens
}

function Get-SquadAgentUsageAttribution {
    param(
        [Parameter(Mandatory)][string]$EventsPath,
        [Parameter(Mandatory)][decimal]$ExpectedNanoAiu
    )

    $agents = @{}
    $problems = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $records = [Collections.Generic.List[object]]::new()
    $identityMaterial = [Collections.Generic.List[string]]::new()
    $rootSessionId = ''

    $stream = [IO.FileStream]::new($EventsPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = [IO.StreamReader]::new($stream)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            $type = [regex]::Match($line, '"type"\s*:\s*"(?<type>session\.start|subagent\.started|subagent\.completed|session\.usage_record|session\.compaction_complete)"')
            if (-not $type.Success) { continue }
            try { $logEvent = $line | ConvertFrom-Json -AsHashtable -Depth 100 -DateKind String }
            catch {
                $problems.Add("Malformed $($type.Groups['type'].Value) event.")
                continue
            }
            $data = $logEvent['data']
            if ($data -isnot [Collections.IDictionary]) {
                $problems.Add("$($type.Groups['type'].Value) has no data object.")
                continue
            }
            switch ($type.Groups['type'].Value) {
                'session.start' {
                    $rootSessionId = [string]$data['sessionId']
                }
                'subagent.started' {
                    $agentId = [string]$logEvent['agentId']
                    if (-not $agentId) {
                        $problems.Add('subagent.started is missing agentId.')
                        continue
                    }
                    if (-not $data['agentName']) {
                        $problems.Add("subagent.started '$agentId' is missing agentName.")
                        continue
                    }
                    $agents[$agentId] = [ordered]@{
                        agentId = $agentId
                        agentName = [string]$data['agentName']
                        displayName = [string]$data['agentDisplayName']
                        parentAgentId = [string]$data['parentId']
                        toolCallId = [string]$data['toolCallId']
                        started = [string]$logEvent['timestamp']
                        completed = ''
                        durationMs = [long]0
                    }
                }
                'subagent.completed' {
                    $agentId = [string]$logEvent['agentId']
                    if (-not $agentId) { continue }
                    if (-not $agents.ContainsKey($agentId)) {
                        $agents[$agentId] = [ordered]@{
                            agentId = $agentId
                            agentName = [string]$data['agentName']
                            displayName = [string]$data['agentDisplayName']
                            parentAgentId = ''
                            toolCallId = [string]$data['toolCallId']
                            started = ''
                            completed = ''
                            durationMs = [long]0
                        }
                    }
                    $agents[$agentId].completed = [string]$logEvent['timestamp']
                    $duration = 0L
                    if ([long]::TryParse([string]$data['durationMs'], [ref]$duration) -and $duration -ge 0) {
                        $agents[$agentId].durationMs = $duration
                    }
                }
                'session.usage_record' {
                    $usage = $data['usage']
                    $accounting = if ($usage -is [Collections.IDictionary]) { $usage['accounting'] } else { $null }
                    if ($accounting -isnot [Collections.IDictionary] -or -not $accounting['sourceSessionId'] -or -not $accounting['usageId']) {
                        $problems.Add('session.usage_record is missing sourceSessionId or usageId.')
                        continue
                    }
                    $identity = 'usage:' + [string]$accounting['sourceSessionId'] + ':' + [string]$accounting['usageId']
                    if (-not $seen.Add($identity)) { continue }
                    if ($usage['aiCreditsStatus'] -ne 'complete') {
                        $problems.Add("$identity has aiCreditsStatus '$($usage['aiCreditsStatus'])', not complete.")
                        continue
                    }
                    $breakdown = ConvertTo-SquadNativeTokenBreakdown -Usage $usage -Identity $identity -Problems $problems
                    if ($null -eq $breakdown) { continue }
                    $nanoAiu = [decimal]$usage['copilotUsage']['totalNanoAiu']
                    $record = [pscustomobject][ordered]@{
                        identity = $identity
                        timestamp = [string]$logEvent['timestamp']
                        agentId = [string]$logEvent['agentId']
                        sourceSessionId = [string]$accounting['sourceSessionId']
                        model = [string]$usage['model']
                        inputTokens = $breakdown.inputTokens
                        cacheReadTokens = $breakdown.cacheReadTokens
                        cacheWriteTokens = $breakdown.cacheWriteTokens
                        outputTokens = $breakdown.outputTokens
                        nanoAiu = $nanoAiu
                    }
                    $records.Add($record)
                    $identityMaterial.Add("$identity|$($record.agentId)|$($record.model)|$($record.inputTokens)|$($record.cacheReadTokens)|$($record.cacheWriteTokens)|$($record.outputTokens)|$nanoAiu")
                }
                'session.compaction_complete' {
                    $usage = $data['compactionTokensUsed']
                    if ($usage -isnot [Collections.IDictionary]) { continue }
                    if (-not $data['compactionAttemptId']) {
                        $problems.Add('session.compaction_complete is missing compactionAttemptId.')
                        continue
                    }
                    $identity = 'compaction:' + [string]$data['compactionAttemptId']
                    if (-not $seen.Add($identity)) { continue }
                    if ($usage['aiCreditsStatus'] -ne 'complete') {
                        $problems.Add("$identity has aiCreditsStatus '$($usage['aiCreditsStatus'])', not complete.")
                        continue
                    }
                    $breakdown = ConvertTo-SquadNativeTokenBreakdown -Usage $usage -Identity $identity -Problems $problems
                    if ($null -eq $breakdown) { continue }
                    $nanoAiu = [decimal]$usage['copilotUsage']['totalNanoAiu']
                    $record = [pscustomobject][ordered]@{
                        identity = $identity
                        timestamp = [string]$logEvent['timestamp']
                        agentId = [string]$logEvent['agentId']
                        sourceSessionId = if ($usage['accounting'] -is [Collections.IDictionary]) { [string]$usage['accounting']['sourceSessionId'] } else { '' }
                        model = [string]$usage['model']
                        inputTokens = $breakdown.inputTokens
                        cacheReadTokens = $breakdown.cacheReadTokens
                        cacheWriteTokens = $breakdown.cacheWriteTokens
                        outputTokens = $breakdown.outputTokens
                        nanoAiu = $nanoAiu
                    }
                    $records.Add($record)
                    $identityMaterial.Add("$identity|$($record.agentId)|$($record.model)|$($record.inputTokens)|$($record.cacheReadTokens)|$($record.cacheWriteTokens)|$($record.outputTokens)|$nanoAiu")
                }
            }
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }

    $groups = @{}
    foreach ($record in $records) {
        $rootAgentId = [string]$record.agentId
        if (-not $rootAgentId -and (-not $rootSessionId -or $record.sourceSessionId -cne $rootSessionId)) {
            $problems.Add("$($record.identity) has no event agentId and cannot be proven to belong to the coordinator session.")
            continue
        }
        if ($rootAgentId) {
            if (-not $agents.ContainsKey($rootAgentId)) {
                $problems.Add("$($record.identity) names unknown agentId '$rootAgentId'.")
                continue
            }
            $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            while ($agents[$rootAgentId].parentAgentId) {
                if (-not $visited.Add($rootAgentId)) {
                    $problems.Add("Agent parent cycle contains '$rootAgentId'.")
                    $rootAgentId = ''
                    break
                }
                $parent = [string]$agents[$rootAgentId].parentAgentId
                if (-not $agents.ContainsKey($parent)) {
                    $problems.Add("Agent '$rootAgentId' names unknown parentAgentId '$parent'.")
                    $rootAgentId = ''
                    break
                }
                $rootAgentId = $parent
            }
            if (-not $rootAgentId) { continue }
        }
        $key = if ($rootAgentId) { $rootAgentId } else { 'main' }
        if (-not $groups.ContainsKey($key)) {
            $root = if ($rootAgentId) { $agents[$rootAgentId] } else { $null }
            $groups[$key] = @{
                agentId = $rootAgentId
                agentName = if ($root) { [string]$root.agentName } else { 'coordinator' }
                displayName = if ($root) { [string]$root.displayName } else { 'coordinator' }
                toolCallId = if ($root) { [string]$root.toolCallId } else { '' }
                started = if ($root) { [string]$root.started } else { '' }
                completed = if ($root) { [string]$root.completed } else { '' }
                durationMs = if ($root) { [long]$root.durationMs } else { [long]0 }
                records = 0
                nanoAiu = [decimal]0
                inputTokens = 0L
                cacheReadTokens = 0L
                cacheWriteTokens = 0L
                outputTokens = 0L
                models = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                descendants = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                requests = [Collections.Generic.List[object]]::new()
            }
        }
        $group = $groups[$key]
        $group.records++
        $group.nanoAiu += [decimal]$record.nanoAiu
        $group.inputTokens += [long]$record.inputTokens
        $group.cacheReadTokens += [long]$record.cacheReadTokens
        $group.cacheWriteTokens += [long]$record.cacheWriteTokens
        $group.outputTokens += [long]$record.outputTokens
        if ($record.model) { $null = $group.models.Add([string]$record.model) }
        if ($record.agentId -and $record.agentId -cne $rootAgentId -and $agents.ContainsKey([string]$record.agentId)) {
            $null = $group.descendants.Add([string]$agents[[string]$record.agentId].agentName)
        }
        $group.requests.Add($record)
    }

    $attributedNanoAiu = [decimal]0
    $runs = @(
        foreach ($key in @($groups.Keys | Sort-Object { if ($_ -eq 'main') { '' } else { $_ } })) {
            $group = $groups[$key]
            $attributedNanoAiu += $group.nanoAiu
            [pscustomobject][ordered]@{
                agentId = $group.agentId
                agentName = $group.agentName
                displayName = $group.displayName
                toolCallId = $group.toolCallId
                started = $group.started
                completed = $group.completed
                durationMs = $group.durationMs
                records = $group.records
                models = @($group.models | Sort-Object)
                descendantAgents = @($group.descendants | Sort-Object)
                inputTokens = $group.inputTokens
                cacheReadTokens = $group.cacheReadTokens
                cacheWriteTokens = $group.cacheWriteTokens
                outputTokens = $group.outputTokens
                totalNanoAiu = $group.nanoAiu
                credits = $group.nanoAiu / [decimal]1e9
                usd = $group.nanoAiu / [decimal]1e11
                requests = $group.requests.ToArray()
            }
        }
    )
    if ($attributedNanoAiu -ne $ExpectedNanoAiu) {
        $problems.Add("Attributed total $attributedNanoAiu nano-AIU does not equal exact session total $ExpectedNanoAiu.")
    }
    $digestBytes = [Text.Encoding]::UTF8.GetBytes($identityMaterial -join "`n")
    $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($digestBytes))
    [pscustomobject][ordered]@{
        status = if ($problems.Count -eq 0) { 'complete' } else { 'incomplete' }
        sessionId = $rootSessionId
        records = $records.Count
        identityDigest = $digest
        lastTimestamp = if ($records.Count -gt 0) { [string]$records[$records.Count - 1].timestamp } else { '' }
        attributedNanoAiu = $attributedNanoAiu
        agentRuns = $runs
        problems = $problems.ToArray()
    }
}

function Get-SquadUsageSnapshot {
    <#
    .SYNOPSIS
        Sums complete native AI-credit records once per host accounting identity.
    .DESCRIPTION
        session.usage_record is keyed by sourceSessionId plus usageId. Native
        compaction usage is keyed by compactionAttemptId. Incomplete identities,
        partial records, non-complete credit status, malformed relevant lines, or a
        baseline above the observed total make the snapshot incomplete. A lagging
        session.usage_checkpoint is retained only as diagnostics and never replaces
        the complete-record sum.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Events')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Events')][string]$EventsPath,
        [Parameter(Mandatory, ParameterSetName = 'Usage')][string]$UsagePath,
        [decimal]$BaselineNanoAiu = 0,
        [switch]$IncludeAgentRuns
    )

    if ($BaselineNanoAiu -lt 0) { throw 'BaselineNanoAiu must be nonnegative.' }
    $problems = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $totals = @{
        nanoAiu = [decimal]0
        records = 0
        duplicates = 0
        inputTokens = 0L
        outputTokens = 0L
        cacheReadTokens = 0L
        cacheWriteTokens = 0L
        models = [ordered]@{}
    }
    $checkpointNanoAiu = $null
    $sessionId = ''
    $source = ''
    $first = ''
    $last = ''
    $attribution = $null

    if ($PSCmdlet.ParameterSetName -eq 'Usage') {
        if (-not (Test-Path -LiteralPath $UsagePath -PathType Leaf)) {
            throw "Usage output '$UsagePath' does not exist."
        }
        $source = (Resolve-Path -LiteralPath $UsagePath).ProviderPath
        try { $usage = [IO.File]::ReadAllText($source) | ConvertFrom-Json -AsHashtable -Depth 100 }
        catch { throw "Usage output is not valid JSON: $($_.Exception.Message)" }
        if ($usage -isnot [Collections.IDictionary] -or $null -eq $usage['totalNanoAiu']) {
            throw 'Usage output has no totalNanoAiu.'
        }
        $total = [decimal]0
        try { $total = [decimal]$usage['totalNanoAiu'] }
        catch { throw 'Usage output totalNanoAiu is invalid.' }
        if ($total -lt 0) { throw 'Usage output totalNanoAiu is negative.' }
        $totals.nanoAiu = $total
        $totals.records = 1
        if ($usage['modelMetrics'] -is [Collections.IDictionary]) {
            foreach ($modelName in @($usage['modelMetrics'].Keys)) {
                $metric = $usage['modelMetrics'][$modelName]
                $metricNano = if ($metric -is [Collections.IDictionary] -and $null -ne $metric['totalNanoAiu']) { [decimal]$metric['totalNanoAiu'] } else { [decimal]0 }
                $totals.models[$modelName] = [ordered]@{ records = 1; nanoAiu = $metricNano }
            }
        }
    }
    else {
        if (-not (Test-Path -LiteralPath $EventsPath -PathType Leaf)) {
            throw "Events log '$EventsPath' does not exist."
        }
        $source = (Resolve-Path -LiteralPath $EventsPath).ProviderPath
        $sessionId = Split-Path -Leaf (Split-Path -Parent $source)
        $stream = [IO.FileStream]::new($source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $reader = [IO.StreamReader]::new($stream)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                $type = [regex]::Match($line, '"type"\s*:\s*"(?<type>session\.usage_record|session\.compaction_complete|session\.usage_checkpoint)"')
                if (-not $type.Success) { continue }
                try { $logEvent = $line | ConvertFrom-Json -AsHashtable -Depth 100 -DateKind String }
                catch {
                    $problems.Add("Malformed $($type.Groups['type'].Value) event.")
                    continue
                }
                $timestamp = [string]$logEvent['timestamp']
                if ($timestamp) {
                    if (-not $first) { $first = $timestamp }
                    $last = $timestamp
                }
                $data = $logEvent['data']
                if ($data -isnot [Collections.IDictionary]) {
                    $problems.Add("$($type.Groups['type'].Value) has no data object.")
                    continue
                }
                switch ($type.Groups['type'].Value) {
                    'session.usage_checkpoint' {
                        if ($null -ne $data['totalNanoAiu']) {
                            try { $checkpointNanoAiu = [decimal]$data['totalNanoAiu'] }
                            catch { $problems.Add('session.usage_checkpoint has an invalid totalNanoAiu.') }
                        }
                    }
                    'session.usage_record' {
                        $usage = $data['usage']
                        $accounting = if ($usage -is [Collections.IDictionary]) { $usage['accounting'] } else { $null }
                        if ($accounting -isnot [Collections.IDictionary] -or -not $accounting['sourceSessionId'] -or -not $accounting['usageId']) {
                            $problems.Add('session.usage_record is missing sourceSessionId or usageId.')
                            continue
                        }
                        $identity = 'usage:' + [string]$accounting['sourceSessionId'] + ':' + [string]$accounting['usageId']
                        Add-SquadNativeUsageRecord -Usage $usage -Identity $identity -Seen $seen -Problems $problems -Totals $totals
                    }
                    'session.compaction_complete' {
                        $usage = $data['compactionTokensUsed']
                        if ($usage -isnot [Collections.IDictionary]) { continue }
                        if (-not $data['compactionAttemptId']) {
                            $problems.Add('session.compaction_complete is missing compactionAttemptId.')
                            continue
                        }
                        $identity = 'compaction:' + [string]$data['compactionAttemptId']
                        Add-SquadNativeUsageRecord -Usage $usage -Identity $identity -Seen $seen -Problems $problems -Totals $totals
                    }
                }
            }
        }
        finally {
            $reader.Dispose()
            $stream.Dispose()
        }
        if ($IncludeAgentRuns) {
            $attribution = Get-SquadAgentUsageAttribution -EventsPath $source -ExpectedNanoAiu $totals.nanoAiu
            if ($attribution.sessionId) { $sessionId = [string]$attribution.sessionId }
        }
    }

    if ($BaselineNanoAiu -gt $totals.nanoAiu) {
        $problems.Add("BaselineNanoAiu $BaselineNanoAiu exceeds observed total $($totals.nanoAiu).")
    }
    if ($PSCmdlet.ParameterSetName -eq 'Events' -and $null -ne $checkpointNanoAiu -and $totals.records -eq 0) {
        $problems.Add('A usage checkpoint exists but no complete identity-bearing usage records were found.')
    }
    $consumed = if ($totals.nanoAiu -gt $BaselineNanoAiu) { $totals.nanoAiu - $BaselineNanoAiu } else { [decimal]0 }
    $status = if ($problems.Count -eq 0) { 'complete' } else { 'incomplete' }
    $models = [ordered]@{}
    foreach ($model in $totals.models.Keys) {
        $models[$model] = [ordered]@{
            records = $totals.models[$model].records
            nanoAiu = $totals.models[$model].nanoAiu
            credits = $totals.models[$model].nanoAiu / [decimal]1e9
        }
    }

    [pscustomobject][ordered]@{
        status = $status
        source = $source
        sessionId = $sessionId
        first = $first
        last = $last
        records = $totals.records
        duplicates = $totals.duplicates
        totalNanoAiu = $totals.nanoAiu
        baselineNanoAiu = $BaselineNanoAiu
        consumedNanoAiu = $consumed
        credits = $consumed / [decimal]1e9
        usd = $consumed / [decimal]1e11
        inputTokens = $totals.inputTokens
        outputTokens = $totals.outputTokens
        cacheReadTokens = $totals.cacheReadTokens
        cacheWriteTokens = $totals.cacheWriteTokens
        checkpointNanoAiu = $checkpointNanoAiu
        models = $models
        attributionStatus = if ($IncludeAgentRuns) { if ($attribution) { $attribution.status } else { 'unavailable' } } else { 'not-requested' }
        attributionProblems = if ($attribution) { @($attribution.problems) } else { @() }
        identityDigest = if ($attribution) { $attribution.identityDigest } else { '' }
        lastUsageTimestamp = if ($attribution) { $attribution.lastTimestamp } else { '' }
        agentRuns = if ($attribution) { @($attribution.agentRuns) } else { @() }
        problems = $problems.ToArray()
    }
}

Export-ModuleMember -Function Resolve-SquadSessionLogPath, Get-SquadUsageSnapshot
