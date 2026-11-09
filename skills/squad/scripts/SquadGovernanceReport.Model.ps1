# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

# Dot-sourced by SquadGovernanceReport.psm1. Scope resolution and the report model: every
# number the HTML layer prints is computed here, from parsed state, with its basis attached.

Set-StrictMode -Version Latest

function New-SquadGovernanceStop {
    <#
    .SYNOPSIS
        A documented stop: a condition the caller relays to the user (no squad state, unknown sub-squad, unsafe output path) rather than a defect.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an exception object in memory only.')]
    [OutputType([System.Exception])]
    param([Parameter(Mandatory)][string]$Message)
    $exception = [InvalidOperationException]::new($Message)
    $exception.Data['SquadGovernanceStop'] = $true
    $exception
}

function Get-SquadGovernanceExitCode {
    <#
    .SYNOPSIS
        1 for a documented stop or an unreadable or unwritable path, 2 for any other failure (the caller then falls back to the manual steps).
    .DESCRIPTION
        A .NET call that fails surfaces in PowerShell wrapped in a MethodInvocationException, so every exception in the chain decides.
    #>
    [OutputType([int])]
    param([Parameter(Mandatory)][System.Exception]$Exception)
    for ($current = $Exception; $null -ne $current; $current = $current.InnerException) {
        if ($current.Data.Contains('SquadGovernanceStop') -or $current -is [IO.IOException] -or $current -is [UnauthorizedAccessException] -or $current -is [System.Management.Automation.ItemNotFoundException]) { return 1 }
    }
    2
}

function Limit-SqText {
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Text, [int]$Max = 160)
    $plain = ((ConvertTo-SqPlainText $Text) -replace '\s+', ' ').Trim()
    if ($plain.Length -le $Max) { return $plain }
    $plain.Substring(0, $Max - 1).TrimEnd() + '…'
}

function Get-SqFirstSentence {
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Text, [int]$Max = 200)
    $plain = ((ConvertTo-SqPlainText $Text) -replace '\s+', ' ').Trim() -replace '^(?:[*+-]\s+)+', ''
    if ($plain -match '^(?<s>.+?[.!?])(\s|$)') { $plain = $Matches.s }
    Limit-SqText $plain $Max
}

function Format-SqCount {
    <#
    .SYNOPSIS
        "1 dispatch", "4 dispatches": a count with its noun in the right number.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)]$Count, [Parameter(Mandatory)][string]$Singular, [string]$Plural)
    if (-not $Plural) { $Plural = if ($Singular -match '(s|x|ch|sh)$') { $Singular + 'es' } else { $Singular + 's' } }
    '{0} {1}' -f $Count, $(if ([decimal]$Count -eq 1) { $Singular } else { $Plural })
}

function Get-SqRoleDisplay {
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Role)
    $words = @($Role -split '[-_\s]+' | Where-Object { $_ } | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) })
    if ($words.Count -eq 0) { return $Role }
    $words -join ' '
}

function Get-SqPercent {
    [OutputType([System.Nullable[decimal]])]
    param([AllowNull()]$Part, [AllowNull()]$Whole)
    if ($null -eq $Part -or $null -eq $Whole -or [decimal]$Whole -le 0) { return $null }
    [decimal]$Part / [decimal]$Whole * 100
}

function Format-SqUsd {
    [OutputType([string])]
    param([AllowNull()]$Value, [int]$Decimals = 4)
    if ($null -eq $Value) { return 'n/a' }
    $number = [decimal]$Value
    $sign = if ($number -lt 0) { '-' } else { '' }
    $sign + '$' + (Format-SqNumber ([Math]::Abs($number)) $Decimals -Grouped)
}

function Format-SqPct {
    [OutputType([string])]
    param([AllowNull()]$Value, [int]$Decimals = 1)
    if ($null -eq $Value) { return 'n/a' }
    (Format-SqNumber $Value $Decimals) + '%'
}

function Format-SqRoi {
    <#
    .SYNOPSIS
        A signed return-on-spend percentage ("+150%", "-20%") shared by the header chip and the receipt.
    #>
    [OutputType([string])]
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return 'n/a' }
    $number = [decimal]$Value
    $(if ($number -gt 0) { '+' } else { '' }) + (Format-SqPct $number 0)
}

function Resolve-SqPeriod {
    param([Parameter(Mandatory)][string]$Period, [Parameter(Mandatory)][datetimeoffset]$AsOf)
    $days = switch ($Period) { '30d' { 30 } '7d' { 7 } default { 0 } }
    if ($days -eq 0) { return [pscustomobject]@{ Name = 'all'; Days = 0; Start = $null; EndExclusive = $null } }
    $asOfDate = [datetimeoffset]::new($AsOf.UtcDateTime.Date, [TimeSpan]::Zero)
    [pscustomobject]@{ Name = $Period; Days = $days; Start = $asOfDate.AddDays(1 - $days); EndExclusive = $asOfDate.AddDays(1) }
}

function Test-SqInPeriod {
    [OutputType([bool])]
    param([Parameter(Mandatory)]$Window, [AllowNull()]$Timestamp)
    if ($Window.Name -eq 'all') { return $true }
    if ($null -eq $Timestamp) { return $false }
    $Timestamp -ge $Window.Start -and $Timestamp -lt $Window.EndExclusive
}

function Read-SqUnit {
    <#
    .SYNOPSIS
        Reads every squad-state file one root carries. Nothing is written; a missing file leaves its slot empty.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Name)

    $stateText = Read-SqFile -Context $Context -Path (Join-Path $Root 'state.json')
    $state = $null
    $stateError = ''
    if ($stateText) {
        try { $state = ConvertFrom-SqJson -Text $stateText -MaxDepth 32 }
        catch { $stateError = Get-SqErrorText $_.Exception }
    }
    $roster = Read-SqRoster (Read-SqFile -Context $Context -Path (Join-Path $Root 'team.md'))
    $tiers = Read-SqRoutingTiers (Read-SqFile -Context $Context -Path (Join-Path $Root 'routing.md'))
    $decisions = Read-SqDecisions (Read-SqFile -Context $Context -Path (Join-Path $Root 'decisions.md'))
    $notifications = Read-SqNotifications (Read-SqFile -Context $Context -Path (Join-Path $Root 'notifications.md'))

    $histories = [Collections.Generic.List[object]]::new()
    $runs = [Collections.Generic.List[object]]::new()
    $historyDirectory = Join-Path $Root 'history'
    if (Test-Path -LiteralPath $historyDirectory -PathType Container) {
        $files = @()
        if ((Get-Item -LiteralPath $historyDirectory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $Context.Skipped.Add("$(Get-SqRelativePath -Base $Context.Base -Path $historyDirectory) (linked path; not followed)")
        }
        else { $files = [IO.Directory]::GetFiles($historyDirectory, '*.md') }
        [Array]::Sort($files, [StringComparer]::Ordinal)
        foreach ($file in $files) {
            $leaf = [IO.Path]::GetFileNameWithoutExtension($file)
            $text = Read-SqFile -Context $Context -Path $file
            if ($null -eq $text) { continue }
            if ($leaf -like 'autopilot-run-*' -or $leaf -like 'autonomous-loop-*') {
                $runs.Add((Read-SqRunFile -Text $text -Name $leaf))
                continue
            }
            $parsedEntries = Read-SqHistoryEntries -Text $text -Agent $leaf
            $histories.Add([pscustomobject]@{
                    Agent   = $leaf
                    Role    = (Resolve-SqAgentRole -Agent $leaf -Roster $roster.Members)
                    Entries = @($parsedEntries)
                })
        }
    }

    $ledgerText = Read-SqFile -Context $Context -Path (Join-Path $Root 'consumption.md')
    $rates = Read-SqRates (Read-SqFile -Context $Context -Path (Join-Path $Root 'consumption-rates.md'))
    $journal = Read-SqJournal (Read-SqFile -Context $Context -Path (Join-Path $Root 'consumption-sessions.json'))
    $ledger = Get-SqLedgerView -Text $ledgerText
    $trigger = $null
    if ($state -is [System.Collections.IDictionary] -and $state.Contains('trigger') -and $state['trigger'] -is [System.Collections.IDictionary]) { $trigger = $state['trigger'] }

    [pscustomobject]@{
        Name = $Name; Root = $Root; State = $state; StateError = $stateError; Roster = $roster; Tiers = $tiers; Decisions = $decisions
        Notifications = @($notifications); Histories = $histories.ToArray(); Runs = $runs.ToArray()
        Ledger = $ledger; Rates = $rates; Journal = $journal; Trigger = $trigger
        Quality = @(Get-SqLedgerQuality -View $ledger -State $state -Rates $rates)
    }
}

function Get-SqStateNumber {
    param([AllowNull()]$State, [Parameter(Mandatory)][string]$Key)
    if ($State -is [System.Collections.IDictionary] -and $State.Contains($Key) -and $null -ne $State[$Key]) {
        $value = [decimal]0
        if ([decimal]::TryParse([string]$State[$Key], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) { return $value }
    }
    $null
}

function Get-SqCapabilityType {
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    $lower = $Path.ToLowerInvariant()
    if ($lower -match '(^|/)(tests?|spec|__tests__)(/|$)|\.(tests?|spec)\.[a-z]+$') { return 'Test' }
    if ($lower -match '\.(bicep|tf|tfvars)$') { return 'Infrastructure' }
    if ($lower -match '\.(ps1|psm1|py|js|mjs|ts|tsx|cs|go|java|sh|rb|rs)$') { return 'Code' }
    if ($lower -match '\.(ya?ml)$|workflow') { return 'Pipeline / config' }
    if ($lower -match '(^|/)plans?(/|$)') { return 'Plan' }
    if ($lower -match '(^|/)research(/|$)') { return 'Research' }
    if ($lower -match '(^|/)reviews?(/|$)') { return 'Review' }
    if ($lower -match '\.(md|txt|docx|pdf|html)$') { return 'Documentation' }
    'Artifact'
}

function Test-SqCodeDeliverable {
    param([Parameter(Mandatory)][string]$Path)
    $Path -match '(?i)\.(ps1|psm1|py|js|mjs|ts|tsx|cs|go|java|sh|rb|rs|bicep|tf|ya?ml)$'
}

function Get-SqIsStatePath {
    param([Parameter(Mandatory)][string]$Path)
    $normalized = $Path.Replace('\', '/')
    $normalized -match '(^|/)\.copilot-tracking/squad(/|$)' -or $normalized -match '^(state\.json|consumption(-rates|-sessions)?\.(md|json)|decisions\.md|notifications\.md|team\.md|routing\.md|history/.*)$'
}

function New-SqNote {
    param([string]$Severity, [string]$Code, [string]$Message, [string]$Unit = '')
    [pscustomobject]@{ Severity = $Severity; Code = $Code; Message = $Message; Unit = $Unit }
}

function Get-SqGateType {
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($Text -match '(?i)impactful') { return 'Impactful-Action Gate' }
    'Human Gate'
}

function Get-SquadGovernanceModel {
    <#
    .SYNOPSIS
        Builds the complete, deterministic governance report model from squad state.
    .DESCRIPTION
        Throws InvalidOperationException when no squad state exists or a requested sub-squad is unknown.
        Reads files only; never writes. Output depends only on the state files, the parameters,
        and -AsOf, so the same inputs always produce the same model.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$SquadRoot,
        [string]$Squad,
        [ValidateSet('all', '30d', '7d')][string]$Period = 'all',
        [datetimeoffset]$AsOf = [datetimeoffset]::UtcNow,
        [string]$ProjectName
    )

    $previousCulture = [Globalization.CultureInfo]::CurrentCulture
    [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
    try {
        $projectRoot = (Resolve-Path -LiteralPath $ProjectRoot).ProviderPath
        $stateRoot = if ($SquadRoot) { (Resolve-Path -LiteralPath $SquadRoot).ProviderPath } else { [IO.Path]::GetFullPath((Join-Path $projectRoot '.copilot-tracking/squad')) }
        if (-not $ProjectName) { $ProjectName = Split-Path -Leaf $projectRoot }
        $context = New-SqContext -BaseRoot $projectRoot
        $window = Resolve-SqPeriod -Period $Period -AsOf $AsOf
        $gaps = [Collections.Generic.List[string]]::new()
        $notes = [Collections.Generic.List[object]]::new()

        $mode = $null
        if (Test-Path -LiteralPath (Join-Path $stateRoot 'federation.md') -PathType Leaf) { $mode = 'federation' }
        elseif (Test-Path -LiteralPath (Join-Path $stateRoot 'team.md') -PathType Leaf) { $mode = 'single' }
        if (-not $mode) { throw (New-SquadGovernanceStop 'No squad state found. Run `/squad` to initialize a squad first.') }

        $units = [Collections.Generic.List[object]]::new()
        $rootUnit = $null
        $selected = ''
        if ($mode -eq 'single') {
            if ($Squad) { $gaps.Add("squad=$Squad was ignored: this is a single squad, not a federation.") }
            $units.Add((Read-SqUnit -Context $context -Root $stateRoot -Name (Split-Path -Leaf $stateRoot)))
        }
        else {
            $membersRoot = Join-Path $stateRoot 'members'
            $names = @()
            if (Test-Path -LiteralPath $membersRoot -PathType Container) {
                if ((Get-Item -LiteralPath $membersRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    $context.Skipped.Add("$(Get-SqRelativePath -Base $projectRoot -Path $membersRoot) (linked path; not followed)")
                }
                else {
                    $names = @([IO.Directory]::GetDirectories($membersRoot) | ForEach-Object {
                            $item = Get-Item -LiteralPath $_ -Force
                            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { $context.Skipped.Add("$(Get-SqRelativePath -Base $projectRoot -Path $item.FullName) (linked path; not followed)") }
                            else { $item.Name }
                        })
                    [Array]::Sort($names, [StringComparer]::Ordinal)
                }
            }
            if ($Squad) {
                if ($Squad -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw (New-SquadGovernanceStop "Sub-squad name '$Squad' is not valid.") }
                $match = @($names | Where-Object { $_ -ceq $Squad })
                if ($match.Count -ne 1) {
                    throw (New-SquadGovernanceStop "Sub-squad '$Squad' was not found under members/. Available: $(if ($names.Count) { $names -join ', ' } else { 'none' }).")
                }
                $selected = $Squad
                $names = @($Squad)
            }
            foreach ($name in $names) { $units.Add((Read-SqUnit -Context $context -Root (Join-Path $membersRoot $name) -Name $name)) }
            if (-not $selected) {
                $rootUnit = Read-SqUnit -Context $context -Root $stateRoot -Name '(federation root)'
                if ($units.Count -eq 0) { $gaps.Add('The federation has no sub-squads under members/.') }
            }
        }
        $allUnits = @($units.ToArray())
        $multi = $allUnits.Count -gt 1
        $metaUnits = @($allUnits)
        if ($rootUnit) { $metaUnits += $rootUnit }

        # Dispatch entries (agent history only; run summaries and federation routing records are not dispatches).
        $entries = [Collections.Generic.List[object]]::new()
        $undated = 0
        foreach ($unit in $allUnits) {
            foreach ($history in $unit.Histories) {
                foreach ($entry in $history.Entries) {
                    $inWindow = Test-SqInPeriod -Window $window -Timestamp $entry.Timestamp
                    if (-not $inWindow -and $null -eq $entry.Timestamp -and $window.Name -ne 'all') { $undated++ }
                    $entries.Add([pscustomobject]@{
                            Unit = $unit.Name; Role = $history.Role; Agent = $history.Agent; Entry = $entry; InPeriod = $inWindow
                            Tier = $(if ($unit.Tiers.ContainsKey($history.Role.ToLowerInvariant())) { [string]$unit.Tiers[$history.Role.ToLowerInvariant()] } else { '' })
                        })
                }
            }
        }
        $inPeriodEntries = @($entries | Where-Object InPeriod)
        if ($undated -gt 0) { $gaps.Add("$undated history entr$(if ($undated -eq 1) { 'y has' } else { 'ies have' }) no timestamp and $(if ($undated -eq 1) { 'is' } else { 'are' }) excluded from the $($window.Name) period.") }

        # Verdicts.
        $council = @(foreach ($unit in $metaUnits) { foreach ($v in $unit.Decisions.Council) { $v | Add-Member -NotePropertyName Unit -NotePropertyValue $unit.Name -PassThru -Force } })
        $intake = @(foreach ($unit in $metaUnits) { foreach ($v in $unit.Decisions.Intake) { $v | Add-Member -NotePropertyName Unit -NotePropertyValue $unit.Name -PassThru -Force } })
        $discovery = @(foreach ($unit in $metaUnits) { foreach ($v in $unit.Decisions.Discovery) { $v | Add-Member -NotePropertyName Unit -NotePropertyValue $unit.Name -PassThru -Force } })
        $waivers = @(foreach ($unit in $metaUnits) { foreach ($v in $unit.Decisions.Waivers) { $v | Add-Member -NotePropertyName Unit -NotePropertyValue $unit.Name -PassThru -Force } })
        $preflights = @(foreach ($unit in $metaUnits) { foreach ($v in $unit.Decisions.Preflights) { $v | Add-Member -NotePropertyName Unit -NotePropertyValue $unit.Name -PassThru -Force } })
        $councilIn = @($council | Where-Object { Test-SqInPeriod -Window $window -Timestamp $_.Timestamp })
        $intakeIn = @($intake | Where-Object { Test-SqInPeriod -Window $window -Timestamp $_.Timestamp })
        $discoveryIn = @($discovery | Where-Object { Test-SqInPeriod -Window $window -Timestamp $_.Timestamp })
        $waiversIn = @($waivers | Where-Object { Test-SqInPeriod -Window $window -Timestamp $_.Timestamp })
        $preflightsIn = @($preflights | Where-Object { Test-SqInPeriod -Window $window -Timestamp $_.Timestamp })

        $verdictCounts = [ordered]@{ 'Go' = 0; 'Go-With-Conditions' = 0; 'Stop' = 0 }
        foreach ($v in $councilIn) { if ($verdictCounts.Contains($v.Verdict)) { $verdictCounts[$v.Verdict]++ } }
        $findingRoles = [ordered]@{}
        foreach ($v in $councilIn) {
            foreach ($f in $v.Findings) {
                $key = $f.Role.ToLowerInvariant()
                if (-not $findingRoles.Contains($key)) { $findingRoles[$key] = [pscustomobject]@{ Role = $f.Role; Approve = 0; Conditional = 0; Concern = 0; Block = 0; High = 0 } }
                $row = $findingRoles[$key]
                switch -Regex ($f.Verdict) { '^(?i)approve' { $row.Approve++ } '^(?i)conditional' { $row.Conditional++ } '^(?i)concern' { $row.Concern++ } '^(?i)block' { $row.Block++ } }
                if ($f.Risk -match '(?i)high') { $row.High++ }
            }
        }
        $latestByTopic = @{}
        foreach ($v in ($councilIn | Sort-Object { $_.Timestamp }, { $_.Topic })) { $latestByTopic["$($v.Unit)|$($v.Topic)"] = $v }
        $outstanding = 0
        foreach ($v in $latestByTopic.Values) { $outstanding += $v.Outstanding }

        # Human gates: run summaries first; notifications only when the root records no run summary.
        $gates = [Collections.Generic.List[object]]::new()
        $undatedGates = 0
        $memberNames = @($allUnits | ForEach-Object { $_.Name })
        $turnIndex = @{}
        foreach ($group in @($entries | Where-Object { $null -ne $_.Entry.Timestamp -and $null -ne $_.Entry.Turn } | Group-Object -Property Unit)) {
            $ordered = @($group.Group | Sort-Object { $_.Entry.Timestamp })
            $times = [datetimeoffset[]]::new($ordered.Count)
            $highestTurns = [int[]]::new($ordered.Count)
            $highest = [int]::MinValue
            for ($i = 0; $i -lt $ordered.Count; $i++) {
                $times[$i] = $ordered[$i].Entry.Timestamp
                $highest = [Math]::Max($highest, [int]$ordered[$i].Entry.Turn)
                $highestTurns[$i] = $highest
            }
            $turnIndex[[string]$group.Name] = [pscustomobject]@{ Times = $times; HighestTurns = $highestTurns }
        }
        $turnFor = {
            param($unitName, $timestamp)
            if ($null -eq $timestamp -or -not $turnIndex.ContainsKey([string]$unitName)) { return $null }
            $index = $turnIndex[[string]$unitName]
            $best = $null
            for ($i = 0; $i -lt $index.Times.Length; $i++) {
                if ($index.Times[$i] -gt $timestamp) { break }
                $best = $index.HighestTurns[$i]
            }
            $best
        }
        foreach ($unit in $metaUnits) {
            foreach ($run in $unit.Runs) {
                $outcomeBlocked = ($run.Outcome -match '(?i)^(stopped|escalated)')
                $lastIndex = @($run.StageGates).Count - 1
                $index = 0
                foreach ($g in $run.StageGates) {
                    $stamp = if ($g.Date) { Get-SqTimestamp $g.Date } else { $null }
                    $status = if ($g.Result -match '(?i)\b(blocked|stopp|escalat|denied|declin|rejected)') { 'blocked' } elseif ($outcomeBlocked -and $index -eq $lastIndex) { 'blocked' } else { 'passed' }
                    $index++
                    if (-not (Test-SqInPeriod -Window $window -Timestamp $stamp)) { if ($null -eq $stamp -and $window.Name -ne 'all') { $undatedGates++ }; continue }
                    $gates.Add([pscustomobject]@{ Unit = $unit.Name; Timestamp = $stamp; Turn = (& $turnFor $unit.Name $stamp); Type = (Get-SqGateType $g.Gate); Action = (Limit-SqText ("$($g.Stage): $($g.Gate)") 140); Status = $status })
                }
                foreach ($g in $run.MetaGates) {
                    if ($memberNames -contains $g.RaisedBy) { continue }
                    if (-not (Test-SqInPeriod -Window $window -Timestamp $g.Timestamp)) { continue }
                    $status = if ($g.Resolved -match '(?i)\b(pending)\b') { 'pending' } elseif ($g.Resolved -match '(?i)\b(stopped|denied|declin|rejected|blocked|changes)') { 'blocked' } else { 'passed' }
                    $gates.Add([pscustomobject]@{ Unit = $unit.Name; Timestamp = $g.Timestamp; Turn = $null; Type = (Get-SqGateType $g.Gate); Action = (Limit-SqText "$($g.Gate) — $($g.Notes)" 140); Status = $status })
                }
            }
            if (@($unit.Runs).Count -eq 0) {
                foreach ($n in @($unit.Notifications)) {
                    if ($n.Trigger -match '(?i)^final-outcome' -or -not (Test-SqInPeriod -Window $window -Timestamp $n.Timestamp)) { continue }
                    $status = if ($n.Resolved -match '(?i)^(approved|approve-all)') { 'passed' } elseif ($n.Resolved -match '(?i)^(stopped|changes-requested)') { 'blocked' } else { 'pending' }
                    $gates.Add([pscustomobject]@{ Unit = $unit.Name; Timestamp = $n.Timestamp; Turn = (& $turnFor $unit.Name $n.Timestamp); Type = (Get-SqGateType $n.Trigger); Action = (Limit-SqText $(if ($n.Topic) { $n.Topic } else { $n.Awaiting }) 140); Status = $status })
                }
            }
        }
        if ($undatedGates -gt 0) { $gaps.Add("$undatedGates gate row(s) carry no date and are excluded from the $($window.Name) period.") }
        $gateLog = @($gates | Sort-Object { $_.Timestamp }, { $_.Unit }, { $_.Action })
        $gatesPassed = @($gateLog | Where-Object Status -eq 'passed').Count
        $gatesBlocked = @($gateLog | Where-Object Status -eq 'blocked').Count
        $gatesPending = @($gateLog | Where-Object Status -eq 'pending').Count

        $escalationEvents = 0
        foreach ($unit in $metaUnits) { foreach ($run in $unit.Runs) { if ($run.Outcome -match '(?i)^escalated') { $escalationEvents++ } } }
        $escalationEvents += @($inPeriodEntries | Where-Object { $_.Entry.OutcomeClass -eq 'escalation' }).Count
        $openEscalations = 0
        foreach ($unit in $metaUnits) {
            if ($unit.State -is [System.Collections.IDictionary] -and $unit.State.Contains('openEscalations') -and $null -ne $unit.State['openEscalations']) { $openEscalations += @($unit.State['openEscalations']).Count }
        }

        # Turns.
        $turns = $null
        if ($window.Name -eq 'all') {
            $stateTurns = @($allUnits | ForEach-Object { Get-SqStateNumber $_.State 'turn' } | Where-Object { $null -ne $_ })
            if ($stateTurns.Count -gt 0) { $turns = [int](Measure-SqSum $stateTurns) }
        }
        if ($null -eq $turns) {
            $distinct = @($inPeriodEntries | Where-Object { $null -ne $_.Entry.Turn } | ForEach-Object { "$($_.Unit)|$($_.Entry.Turn)" } | Select-Object -Unique)
            if ($distinct.Count -gt 0) { $turns = $distinct.Count }
        }

        # Economics.
        $economics = Get-SqEconomics -Units $allUnits
        foreach ($unit in $allUnits) { foreach ($q in $unit.Quality) { $notes.Add((New-SqNote $q.Severity $q.Code $q.Message $(if ($multi -or $selected) { $unit.Name } else { '' }))) } }
        if ($rootUnit -and $rootUnit.Ledger.Present) { $gaps.Add('The federation root carries a consumption.md; it is shown separately and not added to the sub-squad totals.') }
        if ($economics.NativeOverlap.Count -gt 0) {
            $notes.Add((New-SqNote 'warn' 'native-overlap' ("{0} native request identit{1} appear in more than one sub-squad journal, so aggregate spend may count the same host usage twice. Per-sub-squad figures are exact for each ledger; do not add them." -f $economics.NativeOverlap.Count, $(if ($economics.NativeOverlap.Count -eq 1) { 'y' } else { 'ies' }))))
        }
        if ($economics.HostBilled.Duplicates.Count -gt 0) {
            $notes.Add((New-SqNote 'info' 'shared-session' ("{0} sub-squad ledger(s) repeat a whole-session host-billed total already counted for the same session; it is counted once." -f $economics.HostBilled.Duplicates.Count)))
        }
        if ($economics.HostBilled.Unscoped -gt 1) {
            $notes.Add((New-SqNote 'warn' 'unscoped-host-total' 'More than one ledger reports a whole-session host-billed total without a session id; they cannot be proven distinct, so no combined host-billed total is shown.'))
        }
        if ($window.Name -ne 'all') {
            $notes.Add((New-SqNote 'info' 'period-cumulative' ("Ledger figures (cost, tokens, ROI, unit economics) are cumulative for the whole run and are not filtered to the {0} period; the ledger records no per-period breakdown. Dispatches, verdicts, gates, and timeline are period-filtered." -f $window.Name)))
        }
        if ($economics.Spend.Basis -eq 'mixed') {
            $notes.Add((New-SqNote 'warn' 'mixed-scope-basis' 'Ledgers in scope use different bases (exact-native and estimated). The total is shown with its per-basis subtotals; it is not a single measured figure.'))
        }
        $rateIssue = @($allUnits | Where-Object { $_.Rates -and -not $_.Rates.ObservedOn })
        if ($rateIssue.Count -gt 0) { $notes.Add((New-SqNote 'info' 'rates-undated' 'consumption-rates.md does not record an observation date (Observed-on is a placeholder), so the age of the token rates is unknown.')) }
        foreach ($unit in $allUnits) {
            if ($unit.StateError) { $notes.Add((New-SqNote 'warn' 'state-unreadable' ("state.json could not be parsed: $($unit.StateError)") $unit.Name)) }
            elseif ($null -eq $unit.State) { $notes.Add((New-SqNote 'info' 'state-missing' 'No state.json was found; turn count and open escalations fall back to history.' $unit.Name)) }
        }

        # Header figures.
        $dispatchCount = $inPeriodEntries.Count
        $costLabel = switch ($economics.Spend.Basis) { 'exact-native' { 'Exact Cost (exact-native)' } 'estimated' { 'Est. Cost (estimated)' } 'mixed' { 'Cost (mixed basis)' } default { 'Cost (unavailable)' } }
        $tokensLabel = switch ($economics.Tokens.Basis) { 'exact-native' { 'Total Tokens (exact billed categories)' } 'estimated' { 'Total Tokens (estimated ~)' } 'mixed' { 'Total Tokens (mixed basis)' } default { 'Total Tokens (unavailable)' } }

        # Dispatch activity.
        $dispatchRows = [Collections.Generic.List[object]]::new()
        foreach ($group in ($inPeriodEntries | Group-Object { "$($_.Role)|$($_.Agent)" })) {
            $first = $group.Group[0]
            $sorted = @($group.Group | Sort-Object { $_.Entry.Timestamp }, { $_.Entry.Title })
            $models = @($group.Group | ForEach-Object { $_.Entry.Model } | Where-Object { $_ } | Select-Object -Unique | Sort-Object)
            $flags = @($group.Group | Where-Object { $_.Entry.Identity.Contains('Observed model') -and $_.Entry.Identity['Observed model'] -and $_.Entry.Identity['Observed model'] -notmatch '(?i)^(unreported|unverified)' -and $_.Entry.Model -and (Get-SqKey $_.Entry.Identity['Observed model']) -ne (Get-SqKey $_.Entry.Model) } |
                    ForEach-Object { "observed $($_.Entry.Identity['Observed model']) vs recorded $($_.Entry.Model)" } | Select-Object -Unique)
            $titles = @($sorted | ForEach-Object { Limit-SqText $_.Entry.Title 70 } | Select-Object -Unique)
            $activities = Limit-SqText (($titles | Select-Object -First 3) -join '; ') 200
            if ($titles.Count -gt 3) { $activities += " (+$($titles.Count - 3) more)" }
            $dispatchRows.Add([pscustomobject]@{
                    Role = $first.Role; Agent = $first.Agent; Dispatches = $group.Count; Models = $models; ModelFlags = $flags; Activities = $activities
                    Units = @($group.Group | ForEach-Object { $_.Unit } | Select-Object -Unique)
                })
        }
        $dispatchRowsSorted = @($dispatchRows | Sort-Object @{ Expression = { $_.Dispatches }; Descending = $true }, @{ Expression = { $_.Role } }, @{ Expression = { $_.Agent } })
        $recorded = @($inPeriodEntries | Where-Object { $_.Entry.OutcomeClass -ne 'unrecorded' })
        $successes = @($recorded | Where-Object { $_.Entry.OutcomeClass -eq 'success' }).Count
        $failures = @($inPeriodEntries | Where-Object { $_.Entry.OutcomeClass -eq 'failure' }).Count
        $distinctRoles = @($inPeriodEntries | ForEach-Object { $_.Role } | Select-Object -Unique).Count

        # Autonomy tiers.
        $tierRows = [Collections.Generic.List[object]]::new()
        foreach ($tier in 'auto', 'confirm', 'gated', 'unrecorded') {
            $members = @($inPeriodEntries | Where-Object {
                    $mapped = if ($_.Tier -eq 'escalate') { 'gated' } elseif ($_.Tier -in 'auto', 'confirm') { $_.Tier } else { 'unrecorded' }
                    $mapped -eq $tier
                })
            if ($members.Count -eq 0) { continue }
            $classes = @($members | Group-Object { $_.Entry.OutcomeClass } | Sort-Object Name | ForEach-Object { "$($_.Count) $($_.Name)" })
            $tierRows.Add([pscustomobject]@{ Tier = $tier; Dispatches = $members.Count; Outcome = ($classes -join ', ') })
        }

        # Compliance and outcomes (dispatch evidence).
        $nonState = @($inPeriodEntries)
        $withDeliverable = @($nonState | Where-Object { $_.Entry.Deliverable -or $_.Entry.Deliverables.Count -gt 0 }).Count
        $metered = @($nonState | Where-Object { $null -ne $_.Entry.Consumption }).Count
        $codeChanges = @($nonState | Where-Object { -not $_.Entry.IsOrchestration -and @($_.Entry.Deliverables | Where-Object { (Test-SqCodeDeliverable $_) -and -not (Get-SqIsStatePath $_) }).Count -gt 0 })
        $verified = 0
        $verifiersByTurn = @{}
        foreach ($d in $nonState) {
            if ($null -eq $d.Entry.Turn -or $d.Entry.OutcomeClass -ne 'success' -or $d.Entry.Outcome -notmatch '(?i)\b(tests?|pass(ed)?|verified|validated|review)\b') { continue }
            $bucketKey = "$($d.Unit)|$($d.Entry.Turn)"
            if (-not $verifiersByTurn.ContainsKey($bucketKey)) { $verifiersByTurn[$bucketKey] = [Collections.Generic.List[string]]::new() }
            $verifiersByTurn[$bucketKey].Add([string]$d.Role)
        }
        foreach ($c in $codeChanges) {
            $verifiedSameTurn = $false
            if ($null -ne $c.Entry.Turn -and $verifiersByTurn.ContainsKey("$($c.Unit)|$($c.Entry.Turn)")) {
                foreach ($verifierRole in $verifiersByTurn["$($c.Unit)|$($c.Entry.Turn)"]) { if ($verifierRole -ne [string]$c.Role) { $verifiedSameTurn = $true; break } }
            }
            if ($c.Entry.Outcome -match '(?i)\b\d+\s+(tests?|pass(ed|ing)?)\b' -or $verifiedSameTurn) { $verified++ }
        }
        $files = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($d in $nonState) { foreach ($path in $d.Entry.Deliverables) { if (-not $path.EndsWith('/') -and -not (Get-SqIsStatePath $path)) { [void]$files.Add($path.Replace('\', '/')) } } }
        $testTotal = [decimal]0
        $testSources = 0
        foreach ($d in $nonState) {
            $best = $null
            foreach ($m in [regex]::Matches($d.Entry.Outcome, '(?i)\b(?<n>\d+)\s+(?:tests?|specs?|assertions?|cases?|pass(?:ed|ing)?)\b')) {
                $n = [decimal]$m.Groups['n'].Value
                if ($null -eq $best -or $n -gt $best) { $best = $n }
            }
            if ($null -ne $best) { $testTotal += $best; $testSources++ }
        }
        $deployments = @($nonState | Where-Object { $_.Role -match '(?i)^deployer$' -and $_.Entry.OutcomeClass -eq 'success' }).Count
        $issueRefs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $notificationsAll = @(foreach ($unit in $metaUnits) { foreach ($n in @($unit.Notifications)) { if (Test-SqInPeriod -Window $window -Timestamp $n.Timestamp) { $n } } })
        foreach ($n in $notificationsAll) { if ($n.Channel -match '(?i)github-issue' -and $n.ApprovalRef -match '#\d+') { [void]$issueRefs.Add($n.ApprovalRef) } }
        $notificationsResolved = @($notificationsAll | Where-Object { $_.Resolved -and $_.Resolved -notmatch '(?i)^pending' }).Count
        $impactful = @($gateLog | Where-Object Type -eq 'Impactful-Action Gate')
        $impactfulPassed = @($impactful | Where-Object Status -eq 'passed').Count

        $capabilityRows = [Collections.Generic.List[object]]::new()
        $seenCapabilities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($d in ($nonState | Sort-Object { $_.Entry.Timestamp }, { $_.Agent })) {
            if ($d.Entry.IsOrchestration) { continue }
            foreach ($path in $d.Entry.Deliverables) {
                $normal = $path.Replace('\', '/')
                if ($normal.EndsWith('/') -or (Get-SqIsStatePath $normal) -or -not $seenCapabilities.Add($normal)) { continue }
                $status = switch ($d.Entry.OutcomeClass) { 'success' { 'Complete' } 'failure' { 'Blocked' } 'escalation' { 'Escalated' } default { 'Recorded' } }
                $capabilityRows.Add([pscustomobject]@{ Capability = $normal; Type = (Get-SqCapabilityType $normal); Status = $status; Role = $d.Role })
            }
        }

        # Timeline.
        $events = [Collections.Generic.List[object]]::new()
        foreach ($d in $nonState) {
            $e = $d.Entry
            $detail = if ($e.Outcome) { Get-SqFirstSentence $e.Outcome 220 } else { 'outcome not recorded' }
            $events.Add([pscustomobject]@{ Timestamp = $e.Timestamp; Turn = $e.Turn; Title = (Limit-SqText $e.Title 120); Detail = ("{0} → {1}" -f (Get-SqRoleDisplay $d.Role), $detail); Kind = 1; Unit = $d.Unit })
        }
        foreach ($v in $councilIn) {
            $roles = @($v.Findings | ForEach-Object { "$($_.Role): $($_.Verdict)" }) -join ', '
            $events.Add([pscustomobject]@{ Timestamp = $v.Timestamp; Turn = $null; Title = "Council Verdict — $($v.Topic) ($($v.Verdict))"; Detail = (Limit-SqText "$roles. $($v.Outstanding) condition(s) outstanding." 220); Kind = 0; Unit = $v.Unit })
        }
        foreach ($v in $intakeIn) { $events.Add([pscustomobject]@{ Timestamp = $v.Timestamp; Turn = $null; Title = "Intake Readiness — $($v.Topic) ($($v.Verdict))"; Detail = "Remediation cycles: $($v.Cycles)."; Kind = 0; Unit = $v.Unit }) }
        foreach ($v in $discoveryIn) { $events.Add([pscustomobject]@{ Timestamp = $v.Timestamp; Turn = $null; Title = "Discovery — $($v.Topic) ($($v.Depth), $($v.OptIn))"; Detail = "Options discarded: $($v.Discarded)."; Kind = 0; Unit = $v.Unit }) }
        foreach ($g in $gateLog) { $events.Add([pscustomobject]@{ Timestamp = $g.Timestamp; Turn = $g.Turn; Title = "$($g.Type) — $($g.Status)"; Detail = $g.Action; Kind = 0; Unit = $g.Unit }) }
        $timeline = @($events | Sort-Object @{ Expression = { if ($null -eq $_.Timestamp) { [datetimeoffset]::MinValue } else { $_.Timestamp } }; Descending = $true }, @{ Expression = { $_.Kind } }, @{ Expression = { $_.Title } } | Select-Object -First 30)

        # Spans.
        $stamps = @(@($inPeriodEntries | ForEach-Object { $_.Entry.Timestamp }) + @($councilIn | ForEach-Object { $_.Timestamp }) | Where-Object { $null -ne $_ } | Sort-Object)
        $spanStart = if ($window.Name -ne 'all') { $window.Start } elseif ($stamps.Count -gt 0) { $stamps[0] } else { $null }
        $spanEnd = if ($window.Name -ne 'all') { $window.EndExclusive.AddDays(-1) } elseif ($stamps.Count -gt 0) { $stamps[$stamps.Count - 1] } else { $null }

        $model = [pscustomobject]@{
            Meta = [pscustomobject]@{
                ProjectName = $ProjectName; Mode = $mode; Squad = $selected; Units = @($allUnits | ForEach-Object { $_.Name }); Multi = $multi
                Period = $window; AsOf = $AsOf.UtcDateTime.Date.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                SpanStart = $spanStart; SpanEnd = $spanEnd
                Triggers = @($allUnits | Where-Object { $_.Trigger } | ForEach-Object { [pscustomobject]@{ Unit = $_.Name; Source = [string]$_.Trigger['source']; Ref = [string]$_.Trigger['ref']; Actor = [string]$_.Trigger['actor'] } })
            }
            Header = [pscustomobject]@{
                Turns = $turns; Dispatches = $dispatchCount; CostLabel = $costLabel; TokensLabel = $tokensLabel
                Gates = $gateLog.Count; Escalations = $escalationEvents
            }
            Economics = $economics
            Governance = [pscustomobject]@{
                CouncilCount = $councilIn.Count; IntakeCount = $intakeIn.Count
                DiscoveryCount = @($discoveryIn | Where-Object { $_.Depth -ne 'skip' }).Count; DiscoveryDeclined = @($discoveryIn | Where-Object { $_.Depth -eq 'skip' -or $_.OptIn -eq 'offer-declined' }).Count
                Waivers = $waiversIn.Count; Preflights = @($preflightsIn)
                VerdictCounts = $verdictCounts; Findings = @($findingRoles.Values); Outstanding = $outstanding; Council = $councilIn
                GateLog = $gateLog; GatesPassed = $gatesPassed; GatesBlocked = $gatesBlocked; GatesPending = $gatesPending
                OpenEscalations = $openEscalations
            }
            Dispatch = [pscustomobject]@{
                Rows = $dispatchRowsSorted; DistinctRoles = $distinctRoles; Total = $dispatchCount
                SuccessRate = (Get-SqPercent $successes $recorded.Count); Failed = $failures; Unrecorded = ($dispatchCount - $recorded.Count)
                Tiers = $tierRows.ToArray()
            }
            Compliance = [pscustomobject]@{
                ArtifactEvidence = @($withDeliverable, $dispatchCount); CostLogged = @($metered, $dispatchCount)
                CodeChanges = $codeChanges.Count; TestVerified = $verified
                ImpactfulFired = $impactful.Count; ImpactfulPassed = $impactfulPassed
                Notifications = $notificationsAll.Count; NotificationsResolved = $notificationsResolved
                OpenEscalations = $openEscalations
            }
            Outcomes = [pscustomobject]@{
                Deployments = $deployments; Issues = $issueRefs.Count; Tests = $testTotal; TestSources = $testSources; Files = $files.Count
                Capabilities = $capabilityRows.ToArray()
            }
            Timeline = $timeline
            Units = $allUnits
            RootUnit = $rootUnit
            Quality = $notes.ToArray()
            Gaps = $gaps.ToArray()
        }

        $model | Add-Member -NotePropertyName Justifications -NotePropertyValue (Get-SqJustifications -Model $model) -Force
        $sources = @($context.Sources | Sort-Object { $_.Path } -CaseSensitive)
        $digestInput = (($sources | ForEach-Object { "$($_.Path)=$($_.Sha256)" }) -join "`n") + "`n" + "period=$($window.Name);asof=$($model.Meta.AsOf);squad=$selected"
        $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($digestInput))).ToLowerInvariant()
        $model | Add-Member -NotePropertyName Sources -NotePropertyValue $sources -Force
        $model | Add-Member -NotePropertyName Skipped -NotePropertyValue @($context.Skipped | Sort-Object -CaseSensitive) -Force
        $model | Add-Member -NotePropertyName Digest -NotePropertyValue $digest -Force
        $model
    }
    finally {
        [Globalization.CultureInfo]::CurrentCulture = $previousCulture
    }
}

function Get-SqJustifications {
    <#
    .SYNOPSIS
        Evidence-backed reasons HVE Squad paid off in this run, in two groups: what it cost and what it produced.
    .DESCRIPTION
        Each item states a fact computed from the run's own records, or says plainly that the run
        does not demonstrate it. Nothing here is a claim the data does not support.
    #>
    param([Parameter(Mandatory)]$Model)
    $e = $Model.Economics
    $g = $Model.Governance
    $cost = [Collections.Generic.List[object]]::new()
    $output = [Collections.Generic.List[object]]::new()
    $item = { param($state, $title, $detail, $basis) [pscustomobject]@{ State = $state; Title = $title; Detail = $detail; Basis = $basis } }

    if ($e.Rollup) {
        $r = $e.Rollup
        $modelNote = if (@($r.Models).Count -gt 0) { " (single model: $(@($r.Models) -join ', '))" } else { '' }
        if ($r.SavingsUsd -gt 0) {
            $returnText = if ($null -ne $r.RoiPct -and $null -ne $r.Multiple) { " Return on spend $(Format-SqPct $r.RoiPct 0); the single-model approach would have cost $(Format-SqNumber $r.Multiple 2)× as much." } else { '' }
            $detail = "HVE Squad spent {0} against {1} for the same work without HVE Squad{2}: {3} ({4}) lower.{5} This is a modeled counterfactual, not an observed alternate run." -f
            (Format-SqUsd $r.SquadUsd), (Format-SqUsd $r.BaselineUsd), $modelNote, (Format-SqUsd $r.SavingsUsd), (Format-SqPct $r.SavingsPct), $returnText
            $cost.Add((& $item 'shown' 'Lower spend for the same work' $detail $r.Kind))
        }
        elseif ($r.SavingsUsd -eq 0) {
            $detail = "In this run HVE Squad's spend equals the modeled single-model baseline ({0}){1}: no cost advantage is demonstrated here." -f (Format-SqUsd $r.SquadUsd), $modelNote
            $cost.Add((& $item 'not-shown' 'Lower spend for the same work' $detail $r.Kind))
        }
        else {
            $higherPct = if ($null -ne $r.SavingsPct) { Format-SqPct ([Math]::Abs([decimal]$r.SavingsPct)) } else { 'n/a' }
            $detail = "In this run HVE Squad's spend was {0} ({1}) higher than the modeled single-model baseline{2}. Orchestration overhead is counted on the HVE Squad side only; the cost advantage is not demonstrated here." -f (Format-SqUsd ([Math]::Abs($r.SavingsUsd))), $higherPct, $modelNote
            $cost.Add((& $item 'not-shown' 'Lower spend for the same work' $detail $r.Kind))
        }
    }
    else {
        $cost.Add((& $item 'unavailable' 'Lower spend for the same work' 'The ledger records no complete without-HVE-Squad comparison, so no cost advantage is claimed for this run.' 'unavailable'))
    }
    $modelsKnown = @($e.ByModel | Where-Object { $_.Key -ne 'not recorded' -and $_.Key -notmatch '(?i)\b(unknown|unresolved)\b' -and $null -ne $_.Tokens })
    if ($modelsKnown.Count -ge 2 -and $null -ne $e.Tokens.Total -and $e.Tokens.Total -gt 0) {
        $shares = @($modelsKnown | Sort-Object @{ Expression = { $_.Tokens }; Descending = $true }, @{ Expression = { $_.Key } } | ForEach-Object { "{0} {1}" -f $_.Key, (Format-SqPct (Get-SqPercent $_.Tokens $e.Tokens.Total) 0) })
        $cost.Add((& $item 'shown' 'Right-sized models per role' ("{0} distinct models served the roles (share of billed tokens: {1}): each role ran on the model recorded for it instead of one session model for everything." -f $modelsKnown.Count, ($shares -join ', ')) $e.Tokens.Basis))
    }
    elseif ($modelsKnown.Count -eq 1) {
        $cost.Add((& $item 'unavailable' 'Right-sized models per role' ("Every role ran on one model ({0}), so per-role model routing is not demonstrated in this run." -f $modelsKnown[0].Key) 'unavailable'))
    }
    else {
        $cost.Add((& $item 'unavailable' 'Right-sized models per role' 'The ledger records no model identity per role, so model right-sizing is not demonstrated here.' 'unavailable'))
    }
    $snapshot = @($Model.Units | Where-Object { $_.Ledger.Present -and $_.Ledger.Snapshot } | ForEach-Object { $_.Ledger.Snapshot })
    if ($e.Spend.Basis -eq 'exact-native') {
        $detail = if ($snapshot.Count -ge 1) { "Every figure is host-reported native usage: {0} complete accounting record(s) through {1}, reconciled to the native session total (digest {2}…). Spend is audited, not estimated." -f (Measure-SqSum @($snapshot | ForEach-Object { $_.Records })), $snapshot[0].Through, $snapshot[0].Digest.Substring(0, 12) }
        else { 'Every ledger row is labeled exact-native: spend comes from host-reported native usage records, not from an estimator.' }
        $cost.Add((& $item 'shown' 'Spend is measured, not guessed' $detail 'exact-native'))
    }
    elseif ($e.Spend.Basis -eq 'mixed') {
        $cost.Add((& $item 'not-shown' 'Spend is measured, not guessed' 'Only part of the scope is exact-native; the rest is estimated and labeled as such. Per-basis subtotals are shown.' 'mixed'))
    }
    elseif ($e.Spend.Basis -eq 'estimated') {
        $cost.Add((& $item 'not-shown' 'Spend is measured, not guessed' 'Figures are estimates from the dispatch-size estimator; exact host-reported reconciliation was not available for this run, so they are labeled approximate.' 'estimated'))
    }
    else {
        $cost.Add((& $item 'unavailable' 'Spend is measured, not guessed' 'No recognizable consumption ledger was available.' 'unavailable'))
    }
    $ceilings = @($g.Preflights | Where-Object { $null -ne $_.Ceiling })
    if ($ceilings.Count -gt 0) {
        $decisions = @($ceilings | Group-Object Decision | Sort-Object Name | ForEach-Object { "$($_.Count) $($_.Name)" })
        $cost.Add((& $item 'shown' 'Spend guarded by a ceiling' ("Cost ceiling {0}: {1} preflight round(s) recorded before dispatch ({2})." -f (Format-SqUsd $ceilings[0].Ceiling 2), $ceilings.Count, ($decisions -join ', ')) 'recorded'))
    }

    $v = $e.Value
    if ($v -and $null -ne $v.Accepted -and $v.Accepted -gt 0) {
        $detail = "{0} of {1} deliverable(s) accepted by an independent review ({2} rejected, {3} unreviewed)" -f (Format-SqNumber $v.Accepted 0), (Format-SqNumber $v.Produced 0), (Format-SqNumber $(if ($null -ne $v.Rejected) { $v.Rejected } else { 0 }) 0), (Format-SqNumber $(if ($null -ne $v.Unreviewed) { $v.Unreviewed } else { 0 }) 0)
        if ($null -ne $v.FirstPassYieldPct) { $detail += "; first-pass yield $(Format-SqPct $v.FirstPassYieldPct)" }
        if ($null -ne $v.CostPerAcceptedUsd) { $detail += "; $(Format-SqUsd $v.CostPerAcceptedUsd) per accepted deliverable ($($v.CostPerAcceptedLabel))" }
        $output.Add((& $item 'shown' 'Independent review before acceptance' ($detail + '. Value is counted only for reviewed, accepted work.') 'ledger'))
    }
    elseif ($v) {
        $output.Add((& $item 'not-shown' 'Independent review before acceptance' 'No deliverable has an accepting independent review yet, so no accepted value is claimed.' 'ledger'))
    }
    else {
        $output.Add((& $item 'unavailable' 'Independent review before acceptance' 'The ledger records no Unit Economics (value) section, so acceptance and first-pass yield are not measured here.' 'unavailable'))
    }
    if ($g.CouncilCount -gt 0 -or $g.IntakeCount -gt 0) {
        $vc = $g.VerdictCounts
        $output.Add((& $item 'shown' 'Risk surfaced before implementation' ("{0} council verdict(s) ({1} Go, {2} Go-With-Conditions, {3} Stop) with {4} condition(s) outstanding, and {5} intake readiness check(s): concerns were raised and recorded before code was written." -f $g.CouncilCount, $vc['Go'], $vc['Go-With-Conditions'], $vc['Stop'], $g.Outstanding, $g.IntakeCount) 'decisions'))
    }
    else {
        $output.Add((& $item 'unavailable' 'Risk surfaced before implementation' 'No council or intake gate was recorded in this period (interactive runs approve each step directly).' 'unavailable'))
    }
    if ($g.GateLog.Count -gt 0) {
        $output.Add((& $item 'shown' 'Humans stay in control' ("{0} human gate(s) fired: {1} passed, {2} blocked, {3} pending; {4} escalation event(s) recorded. Impactful actions wait for approval." -f $g.GateLog.Count, $g.GatesPassed, $g.GatesBlocked, $g.GatesPending, $Model.Header.Escalations) 'runs'))
    }
    else {
        $output.Add((& $item 'unavailable' 'Humans stay in control' 'No human gate was recorded in this period.' 'unavailable'))
    }
    $d = $Model.Dispatch
    if ($d.Total -gt 0) {
        $percent = Get-SqPercent $Model.Compliance.ArtifactEvidence[0] $Model.Compliance.ArtifactEvidence[1]
        $output.Add((& $item 'shown' 'Every dispatch leaves proof' ("{0} dispatch(es) across {1} role(s), each recorded in append-only history with its request, deliverable, outcome, and consumption block; {2} carry deliverable evidence." -f $d.Total, $d.DistinctRoles, (Format-SqPct $percent 0)) 'history'))
    }
    else {
        $output.Add((& $item 'unavailable' 'Every dispatch leaves proof' 'No dispatch entry was recorded in this period.' 'unavailable'))
    }
    $o = $Model.Outcomes
    if ($o.Files -gt 0 -or $o.Tests -gt 0) {
        $output.Add((& $item 'shown' 'Deliverables with evidence' ("{0} file(s) delivered and {1} test result(s) reported across {2} source(s), taken from dispatch outcomes." -f $o.Files, (Format-SqNumber $o.Tests 0), $o.TestSources) 'history'))
    }
    else {
        $output.Add((& $item 'unavailable' 'Deliverables with evidence' 'No deliverable paths or test results were recorded in this period.' 'unavailable'))
    }
    [pscustomobject]@{ Cost = $cost.ToArray(); Output = $output.ToArray() }
}

function Get-SquadGovernanceReceipt {
    <#
    .SYNOPSIS
        The one-line summary, grounding, and gaps the caller reports after a report is written.
    #>
    param([Parameter(Mandatory)]$Model)
    $h = $Model.Header
    $cost = if ($null -ne $Model.Economics.Spend.Usd) { '{0} {1} cost' -f (Format-SqUsd $Model.Economics.Spend.Usd), $Model.Economics.Spend.Basis } else { 'no cost data' }
    $parts = @(
        $(if ($null -ne $h.Turns) { Format-SqCount $h.Turns 'coordination turn' } else { 'coordination turns unavailable' }),
        (Format-SqCount $h.Dispatches 'dispatch'), $cost,
        (Format-SqCount $h.Gates 'human gate'), (Format-SqCount $h.Escalations 'escalation')
    )
    if ($Model.Economics.Rollup) {
        $r = $Model.Economics.Rollup
        $parts += ('ROI {0} vs without HVE Squad ({1})' -f (Format-SqRoi $r.RoiPct), $r.Kind)
    }
    $gaps = [Collections.Generic.List[string]]::new()
    foreach ($gap in $Model.Gaps) { $gaps.Add($gap) }
    if ($Model.Governance.CouncilCount -eq 0) { $gaps.Add('Council Verdicts: Not activated') }
    if ($Model.Governance.IntakeCount -eq 0) { $gaps.Add('Intake Readiness Checks: Not activated') }
    if ($Model.Governance.GateLog.Count -eq 0) { $gaps.Add('Human Gate Log: No data') }
    if (-not $Model.Economics.Rollup) { $gaps.Add('Without-HVE-Squad comparison and ROI: not recorded in the ledger') }
    if (-not $Model.Economics.Value) { $gaps.Add('Unit Economics (value): not recorded in the ledger') }
    [pscustomobject]@{
        Summary = ($parts -join ', ')
        Period = $Model.Meta.Period.Name
        Mode = $Model.Meta.Mode
        Scope = $(if ($Model.Meta.Squad) { $Model.Meta.Squad } elseif ($Model.Meta.Multi) { 'all sub-squads' } else { 'squad' })
        Basis = $Model.Economics.Spend.Basis
        Grounding = @($Model.Sources | ForEach-Object { $_.Path })
        Gaps = $gaps.ToArray()
        DataQuality = @($Model.Quality | ForEach-Object { [pscustomobject]@{ severity = $_.Severity; code = $_.Code; unit = $_.Unit; message = $_.Message } })
        Digest = $Model.Digest
    }
}