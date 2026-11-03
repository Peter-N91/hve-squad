# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

# Dot-sourced by SquadGovernanceReport.psm1. Read-only readers for squad state: they
# open files for reading only, never follow linked paths out of a squad root, and
# record every file they used so the report can name its grounding.

Set-StrictMode -Version Latest

$script:SqMaxFileBytes = 8MB

function New-SqContext {
    param([Parameter(Mandatory)][string]$BaseRoot)
    [pscustomobject]@{
        Base    = $BaseRoot
        Sources = [Collections.Generic.List[object]]::new()
        Skipped = [Collections.Generic.List[string]]::new()
    }
}

function Get-SqRelativePath {
    param([Parameter(Mandatory)][string]$Base, [Parameter(Mandatory)][string]$Path)
    $relative = [IO.Path]::GetRelativePath($Base, $Path)
    $relative.Replace('\', '/')
}

function Read-SqFile {
    <#
    .SYNOPSIS
        Reads a state file as LF-normalized UTF-8 text, or $null when it is absent, linked, or oversized.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $item = Get-Item -LiteralPath $Path -Force
    $display = Get-SqRelativePath -Base $Context.Base -Path $item.FullName
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $Context.Skipped.Add("$display (linked path; not followed)")
        return $null
    }
    if ($item.Length -gt $script:SqMaxFileBytes) {
        $Context.Skipped.Add("$display (larger than $($script:SqMaxFileBytes / 1MB) MB)")
        return $null
    }
    $text = ([IO.File]::ReadAllText($item.FullName, [Text.UTF8Encoding]::new($false)) -replace "`r`n?", "`n").TrimStart([char]0xFEFF)
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
    $Context.Sources.Add([pscustomobject]@{ Path = $display; Sha256 = $hash; Bytes = $item.Length })
    $text
}

function Get-SqTimestamp {
    <#
    .SYNOPSIS
        Parses an ISO-8601 date or date-time to a UTC DateTimeOffset, or $null.
    #>
    [OutputType([System.Nullable[datetimeoffset]])]
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $value = [datetimeoffset]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetimeoffset]::TryParse($Text.Trim(), [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$value)) { return $value }
    $null
}

function ConvertTo-SqInt {
    <#
    .SYNOPSIS
        A digit string as an Int32, or $null when it is not a number or does not fit.
    #>
    [OutputType([System.Nullable[int]])]
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $value = 0
    if ([int]::TryParse($Text, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) { return $value }
    $null
}

function New-SqFixedError {
    <#
    .SYNOPSIS
        A FormatException carrying fixed English text this module wrote, the only kind of message the report may show.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an exception object in memory only.')]
    [OutputType([System.Exception])]
    param([Parameter(Mandatory)][string]$Message)
    $failure = [FormatException]::new($Message)
    $failure.Data['SquadGovernanceFixedMessage'] = $true
    $failure
}

function Get-SqErrorText {
    <#
    .SYNOPSIS
        The text of an error for display: its message when this module wrote it, and a fixed phrase for anything else.
    .DESCRIPTION
        The message of a runtime or PowerShell error follows the UI culture and the runtime version, so it never reaches the report.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Exception]$Exception)
    if ($Exception.Data.Contains('SquadGovernanceFixedMessage')) { return $Exception.Message }
    'unexpected read error'
}

function ConvertFrom-SqJsonElement {
    <#
    .SYNOPSIS
        Converts a parsed JSON element to ordered dictionaries, object arrays, strings, numbers, and booleans.
    .DESCRIPTION
        Strings stay strings: no date-like text is reinterpreted, so the result never depends on the
        PowerShell version, the culture, or the time zone.
    #>
    param([Parameter(Mandatory)][Text.Json.JsonElement]$Element)
    switch ($Element.ValueKind) {
        ([Text.Json.JsonValueKind]::Object) {
            $table = [ordered]@{}
            foreach ($property in $Element.EnumerateObject()) { $table[$property.Name] = ConvertFrom-SqJsonElement -Element $property.Value }
            return $table
        }
        ([Text.Json.JsonValueKind]::Array) {
            $items = [Collections.Generic.List[object]]::new()
            foreach ($child in $Element.EnumerateArray()) { $items.Add((ConvertFrom-SqJsonElement -Element $child)) }
            return , $items.ToArray()
        }
        ([Text.Json.JsonValueKind]::String) { return $Element.GetString() }
        ([Text.Json.JsonValueKind]::Number) {
            $whole = [long]0
            if ($Element.TryGetInt64([ref]$whole)) { return $whole }
            $fraction = [decimal]0
            if ($Element.TryGetDecimal([ref]$fraction)) { return $fraction }
            return $Element.GetRawText()
        }
        ([Text.Json.JsonValueKind]::True) { return $true }
        ([Text.Json.JsonValueKind]::False) { return $false }
        default { return $null }
    }
}

function Open-SqJsonDocument {
    <#
    .SYNOPSIS
        Parses JSON text to a System.Text.Json.JsonDocument (the caller disposes it), with an error message that does not depend on the UI culture.
    .DESCRIPTION
        Throws System.FormatException ("Invalid JSON at line N, position M.") on malformed input.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [int]$MaxDepth = 32)
    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth = $MaxDepth
    $options.AllowTrailingCommas = $true
    $options.CommentHandling = [Text.Json.JsonCommentHandling]::Skip
    try { [Text.Json.JsonDocument]::Parse($Text, $options) }
    catch {
        # PowerShell wraps the .NET error in a message that follows the UI culture; report only where the JSON is invalid.
        $inner = $_.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException }
        $place = ''
        if ($inner -is [Text.Json.JsonException] -and $null -ne $inner.LineNumber -and $null -ne $inner.BytePositionInLine) {
            $place = " at line $([long]$inner.LineNumber + 1), position $([long]$inner.BytePositionInLine + 1)"
        }
        throw (New-SqFixedError "Invalid JSON$place.")
    }
}

function ConvertFrom-SqJson {
    <#
    .SYNOPSIS
        Parses JSON text without ConvertFrom-Json, so it behaves identically on every PowerShell 7 version.
    .DESCRIPTION
        Throws System.FormatException with fixed English text on malformed input or an unreadable string; callers decide how to degrade.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [int]$MaxDepth = 32)
    $document = Open-SqJsonDocument -Text $Text -MaxDepth $MaxDepth
    try { ConvertFrom-SqJsonElement -Element $document.RootElement }
    catch { throw (New-SqFixedError 'Invalid JSON value.') }
    finally { $document.Dispose() }
}

function Get-SqFencedLineMask {
    <#
    .SYNOPSIS
        Marks which lines sit inside (or open/close) a fenced code block so headings in code are never structure.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $mask = [bool[]]::new($Lines.Count)
    $open = $null
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s{0,3}(?<f>`{3,}|~{3,})') {
            $fence = $Matches.f
            if ($null -eq $open) { $open = $fence; $mask[$i] = $true; continue }
            if ($fence[0] -eq $open[0] -and $fence.Length -ge $open.Length -and $Lines[$i] -match '^\s{0,3}(`{3,}|~{3,})\s*$') {
                $open = $null
                $mask[$i] = $true
                continue
            }
        }
        if ($null -ne $open) { $mask[$i] = $true }
    }
    , $mask
}

function Split-SqByHeading {
    <#
    .SYNOPSIS
        Splits text into the chunks that start at each heading of the given level (fence-aware).
    .OUTPUTS
        Objects with Heading (text after the hashes), Lines (the chunk's lines after the heading line).
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][int]$Level)
    $lines = @($Text -split "`n")
    $mask = Get-SqFencedLineMask -Lines $lines
    $marker = '^' + ('#' * $Level) + '\s+(?!#)(?<t>\S.*?)\s*$'
    $starts = [Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not $mask[$i] -and $lines[$i] -match $marker) { $starts.Add($i) }
    }
    for ($n = 0; $n -lt $starts.Count; $n++) {
        $first = $starts[$n]
        $last = if ($n + 1 -lt $starts.Count) { $starts[$n + 1] - 1 } else { $lines.Count - 1 }
        $null = $lines[$first] -match $marker
        $body = if ($last -gt $first) { @($lines[($first + 1)..$last]) } else { @() }
        [pscustomobject]@{ Heading = $Matches.t; Lines = $body }
    }
}

function Get-SqBulletFields {
    <#
    .SYNOPSIS
        Reads top-level "* Key: value" bullets (with indented continuation lines) into an ordered map.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $fields = [ordered]@{}
    $mask = Get-SqFencedLineMask -Lines $Lines
    $current = $null
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($mask[$i]) { continue }
        $line = $Lines[$i]
        if ($line -match '^[*-]\s+(?<k>[A-Z][A-Za-z0-9 /&()-]{0,60}?):\s*(?<v>.*)$') {
            $current = $Matches.k.Trim()
            if (-not $fields.Contains($current)) { $fields[$current] = $Matches.v.Trim() }
            else { $current = $null }
            continue
        }
        if ($line -match '^#{1,6}\s' -or $line -match '^[*-]\s') { $current = $null; continue }
        if ($null -ne $current -and $line.Trim() -ne '') {
            $fields[$current] = ($fields[$current] + "`n" + $line.Trim()).Trim()
        }
    }
    $fields
}

function Get-SqOutcomeClass {
    <#
    .SYNOPSIS
        Classifies a recorded outcome as success, failure, escalation, or unrecorded from its own wording.
    #>
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Outcome)
    $text = ConvertTo-SqPlainText $Outcome
    if ($text -eq '') { return 'unrecorded' }
    if ($text -match '(?i)^\s*escalat') { return 'escalation' }
    if ($text -match '(?i)^\s*(fail(ed|ure|s)?|error(ed)?|blocked|rejected|aborted|timed out|could not|unable to)\b') { return 'failure' }
    'success'
}

function Test-SqPathLike {
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Token)
    $Token -match '^[\w@./\\-]+$' -and ($Token -match '[/\\]' -or $Token -match '\.[A-Za-z0-9]{1,8}$') -and $Token -notmatch '^[\d.]+$' -and $Token -notmatch '^\.\.\.'
}

function Get-SqDeliverablePaths {
    <#
    .SYNOPSIS
        File paths named in a Deliverable field: every path-like code span on a single line, or the first one on each line of a multi-line list.
    .DESCRIPTION
        Deliverable bullets often carry prose after the path, so on a multi-line field only the
        leading code span of each line is a deliverable; spans later in the prose (commands,
        repositories, versions) are not.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $lines = @($Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $multiLine = $lines.Count -gt 1
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $clean = $line -replace '^(?:[*+-]\s+)+', ''
        $tokens = @([regex]::Matches($clean, '`(?<p>[^`\n]+)`') | ForEach-Object { $_.Groups['p'].Value.Trim() })
        if ($multiLine) { $tokens = @($tokens | Select-Object -First 1) }
        foreach ($token in $tokens) { if (Test-SqPathLike $token) { $paths.Add($token) } }
    }
    @($paths | Select-Object -Unique)
}

function Read-SqHistoryEntries {
    <#
    .SYNOPSIS
        Parses a history/<agent>.md file into dispatch entries with their fields and Consumption block.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][string]$Agent)
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($chunk in (Split-SqByHeading -Text $Text -Level 3)) {
        $heading = [string]$chunk.Heading
        $timestamp = $null
        $title = $heading
        if ($heading -match '^(?<ts>\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?)?)\s*(?<t>.*)$') {
            $timestamp = Get-SqTimestamp $Matches.ts
            $title = $Matches.t.Trim()
        }
        $lines = @($chunk.Lines)
        $mask = Get-SqFencedLineMask -Lines $lines
        $fields = [ordered]@{}
        $identity = [ordered]@{}
        $consumption = $null
        $consumptionError = $null
        $isOrchestration = $false
        $current = $null
        $sawConsumption = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($mask[$i]) {
                if ($sawConsumption -and $null -eq $consumption -and $null -eq $consumptionError -and $line -match '^\s{0,3}(`{3,}|~{3,})\s*(json)?\s*$') {
                    $buffer = [Collections.Generic.List[string]]::new()
                    $j = $i + 1
                    while ($j -lt $lines.Count -and $mask[$j] -and $lines[$j] -notmatch '^\s{0,3}(`{3,}|~{3,})\s*$') { $buffer.Add($lines[$j]); $j++ }
                    try { $consumption = ConvertFrom-SqJson -Text ($buffer -join "`n") -MaxDepth 10 }
                    catch { $consumptionError = Get-SqErrorText $_.Exception }
                }
                continue
            }
            if ($line -match '^####\s+Consumption\b(?<rest>.*)$') {
                $sawConsumption = $true
                $isOrchestration = ($Matches.rest -match 'Orchestration')
                $current = $null
                continue
            }
            if ($line -match '^#{1,6}\s') { $current = $null; continue }
            if ($line -match '^[*-]\s+\*\*(?<k>Requested model|Effective model|Observed model|Route rationale)\*\*\s+[—–-]\s+(?<v>.*)$') {
                $identity[$Matches.k] = (ConvertTo-SqPlainText $Matches.v)
                $current = $null
                continue
            }
            if ($line -match '^[*-]\s+(?<k>[A-Z][A-Za-z0-9 /&()-]{0,60}?):\s*(?<v>.*)$') {
                $current = $Matches.k.Trim()
                if (-not $fields.Contains($current)) { $fields[$current] = $Matches.v.Trim() } else { $current = $null }
                continue
            }
            if ($line -match '^[*-]\s') { $current = $null; continue }
            if ($null -ne $current -and $line.Trim() -ne '') {
                $fields[$current] = ($fields[$current] + "`n" + $line.Trim()).Trim()
            }
        }

        $turn = $null
        if ($fields.Contains('Turn') -and $fields['Turn'] -match '^\s*(?<n>\d+)') { $turn = ConvertTo-SqInt $Matches.n }
        $outcome = if ($fields.Contains('Outcome')) { [string]$fields['Outcome'] } else { '' }
        $deliverable = if ($fields.Contains('Deliverable')) { [string]$fields['Deliverable'] } else { '' }
        $model = $null
        if ($consumption -is [System.Collections.IDictionary] -and $consumption.Contains('model')) { $model = [string]$consumption['model'] }
        $entries.Add([pscustomobject]@{
                Agent            = $Agent
                Timestamp        = $timestamp
                Title            = (ConvertTo-SqPlainText $title)
                Turn             = $turn
                Request          = $(if ($fields.Contains('Request')) { [string]$fields['Request'] } else { '' })
                Deliverable      = $deliverable
                Deliverables     = @(Get-SqDeliverablePaths $deliverable)
                Outcome          = $outcome
                OutcomeClass     = (Get-SqOutcomeClass $outcome)
                Fields           = $fields
                Identity         = $identity
                Consumption      = $consumption
                ConsumptionError = $consumptionError
                IsOrchestration  = $isOrchestration
                Model            = $model
            })
    }
    , $entries.ToArray()
}

function Read-SqRoster {
    <#
    .SYNOPSIS
        Reads team.md's member table (role, member, primary and alternate agents, tier) by header text.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $members = [Collections.Generic.List[object]]::new()
    $packs = ''
    if ([string]::IsNullOrEmpty($Text)) { return [pscustomobject]@{ Members = @(); Packs = $packs } }
    $document = ConvertFrom-SqMarkdown $Text
    foreach ($block in $document.Blocks) {
        if ($block.Type -eq 'paragraph' -and $block.Text -match '^Packs:\s*(?<p>.+)$') { $packs = $Matches.p.Trim() }
        if ($block.Type -ne 'table') { continue }
        $roleIndex = Find-SqColumn $block.Headers '^Role$'
        $primaryIndex = Find-SqColumn $block.Headers 'Agent Name'
        if ($roleIndex -lt 0 -or $primaryIndex -lt 0) { continue }
        $alternateIndex = Find-SqColumn $block.Headers 'Alternate'
        $memberIndex = Find-SqColumn $block.Headers 'Member'
        $tierIndex = Find-SqColumn $block.Headers 'Tier'
        foreach ($row in $block.Rows) {
            $alternates = @()
            if ($alternateIndex -ge 0) {
                $alternates = @((ConvertTo-SqPlainText $row[$alternateIndex]) -split '\s*,\s*' | Where-Object { $_ -and $_ -notmatch '^[—–-]+$' })
            }
            $members.Add([pscustomobject]@{
                    Role       = (ConvertTo-SqPlainText $row[$roleIndex])
                    Member     = $(if ($memberIndex -ge 0) { ConvertTo-SqPlainText $row[$memberIndex] } else { '' })
                    Primary    = (ConvertTo-SqPlainText $row[$primaryIndex])
                    Alternates = $alternates
                    Tier       = $(if ($tierIndex -ge 0) { ConvertTo-SqPlainText $row[$tierIndex] } else { '' })
                })
        }
    }
    [pscustomobject]@{ Members = $members.ToArray(); Packs = $packs }
}

function Read-SqRoutingTiers {
    <#
    .SYNOPSIS
        Maps each role in routing.md to the autonomy tier of the first rule that names it.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $tiers = @{}
    if ([string]::IsNullOrEmpty($Text)) { return $tiers }
    foreach ($block in (ConvertFrom-SqMarkdown $Text).Blocks) {
        if ($block.Type -ne 'table') { continue }
        $roleIndex = Find-SqColumn $block.Headers '^Role'
        $tierIndex = Find-SqColumn $block.Headers 'Autonomy'
        if ($roleIndex -lt 0 -or $tierIndex -lt 0) { continue }
        foreach ($row in $block.Rows) {
            $tier = (ConvertTo-SqPlainText $row[$tierIndex]).ToLowerInvariant()
            foreach ($role in ((ConvertTo-SqPlainText $row[$roleIndex]) -split '\s*,\s*')) {
                $key = ($role -replace '\(.*?\)', '').Trim().ToLowerInvariant()
                if ($key -and -not $tiers.ContainsKey($key)) { $tiers[$key] = $tier }
            }
        }
    }
    $tiers
}

function Resolve-SqAgentRole {
    <#
    .SYNOPSIS
        Resolves a history file's agent name to its roster role; the Scribe is the "scribe" role and an unlisted agent keeps its own name.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Agent, [AllowEmptyCollection()][object[]]$Roster = @())
    $key = Get-SqKey $Agent
    foreach ($member in $Roster) {
        if ((Get-SqKey $member.Primary) -eq $key) { return [string]$member.Role }
    }
    foreach ($member in $Roster) {
        foreach ($alternate in @($member.Alternates)) {
            if ((Get-SqKey $alternate) -eq $key) { return [string]$member.Role }
        }
    }
    if ($key -eq 'squadscribe') { return 'scribe' }
    $Agent
}

function Read-SqDecisions {
    <#
    .SYNOPSIS
        Reads Council, Discovery, Intake Readiness, Waiver, and Cost Preflight entries from decisions.md.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $result = [pscustomobject]@{
        Council    = [Collections.Generic.List[object]]::new()
        Discovery  = [Collections.Generic.List[object]]::new()
        Intake     = [Collections.Generic.List[object]]::new()
        Waivers    = [Collections.Generic.List[object]]::new()
        Preflights = [Collections.Generic.List[object]]::new()
    }
    if ([string]::IsNullOrEmpty($Text)) { return $result }
    foreach ($chunk in (Split-SqByHeading -Text $Text -Level 2)) {
        $heading = [string]$chunk.Heading
        $fields = Get-SqBulletFields -Lines @($chunk.Lines)
        $body = (@($chunk.Lines) -join "`n")
        $tables = @((ConvertFrom-SqMarkdown $body).Blocks | Where-Object Type -eq 'table')
        $get = { param($name) if ($fields.Contains($name)) { ConvertTo-SqPlainText ([string]$fields[$name]) } else { '' } }
        if ($heading -match '^Council Verdict\s+(?<ts>\S+)\s+(?<topic>\S+)') {
            $stamp = $Matches.ts
            $topic = $Matches.topic
            $findings = @()
            foreach ($table in $tables) {
                $roleIndex = Find-SqColumn $table.Headers '^Role$'
                $verdictIndex = Find-SqColumn $table.Headers '^Verdict$'
                if ($roleIndex -lt 0 -or $verdictIndex -lt 0) { continue }
                $riskIndex = Find-SqColumn $table.Headers '^Risk'
                $findings = @(foreach ($row in $table.Rows) {
                        [pscustomobject]@{
                            Role    = (ConvertTo-SqPlainText $row[$roleIndex])
                            Verdict = (ConvertTo-SqPlainText $row[$verdictIndex])
                            Risk    = $(if ($riskIndex -ge 0) { ConvertTo-SqPlainText $row[$riskIndex] } else { '' })
                        }
                    })
                break
            }
            $outstanding = 0
            if ((& $get 'Conditions Outstanding') -match '^\s*(?<n>\d+)') { $parsed = ConvertTo-SqInt $Matches.n; if ($null -ne $parsed) { $outstanding = $parsed } }
            $verdict = (& $get 'Verdict')
            $label = if ($verdict -match '^(?i)(go-with-conditions|go|stop)\b') { $Matches[1] } else { $verdict }
            $result.Council.Add([pscustomobject]@{
                    Timestamp = (Get-SqTimestamp $stamp); Stamp = $stamp; Topic = $topic; Summary = (& $get 'Topic')
                    Verdict = $label; Permits = (& $get 'Permits Implementation Dispatch'); Outstanding = $outstanding
                    Dispatched = (& $get 'Council Members Dispatched'); Findings = $findings
                })
        }
        elseif ($heading -match '^Discovery Verdict\s+(?<ts>\S+)\s+(?<topic>\S+)') {
            $stamp = $Matches.ts
            $topic = $Matches.topic
            $discarded = 0
            foreach ($table in $tables) {
                $outcomeIndex = Find-SqColumn $table.Headers '^Outcome$'
                if ($outcomeIndex -lt 0) { continue }
                foreach ($row in $table.Rows) { if ((ConvertTo-SqPlainText $row[$outcomeIndex]) -match '(?i)^discard') { $discarded++ } }
            }
            $result.Discovery.Add([pscustomobject]@{
                    Timestamp = (Get-SqTimestamp $stamp); Stamp = $stamp; Topic = $topic; OptIn = (& $get 'Opt-In')
                    Depth = ((& $get 'Depth').ToLowerInvariant()); Roles = (& $get 'Roles Dispatched'); Brief = (& $get 'Brief'); Discarded = $discarded
                })
        }
        elseif ($heading -match '^Intake Readiness Verdict\s+(?<ts>\S+)\s+(?<topic>\S+)') {
            $stamp = $Matches.ts
            $topic = $Matches.topic
            $cycles = 0
            if ((& $get 'Remediation Cycles') -match '^\s*(?<n>\d+)') { $parsed = ConvertTo-SqInt $Matches.n; if ($null -ne $parsed) { $cycles = $parsed } }
            $result.Intake.Add([pscustomobject]@{
                    Timestamp = (Get-SqTimestamp $stamp); Stamp = $stamp; Topic = $topic; Verdict = (& $get 'Verdict'); Cycles = $cycles
                })
        }
        elseif ($heading -match '^Council Waiver\s+(?<ts>\S+)\s+(?<topic>\S+)') {
            $stamp = $Matches.ts
            $topic = $Matches.topic
            $result.Waivers.Add([pscustomobject]@{ Timestamp = (Get-SqTimestamp $stamp); Topic = $topic })
        }
        elseif ($heading -match '^Cost Preflight\s+(?<ts>\S+)\s+(?<run>\S+)\s+(?<round>\S+)') {
            $stamp = $Matches.ts
            $runId = $Matches.run
            $roundId = $Matches.round
            $result.Preflights.Add([pscustomobject]@{
                    Timestamp = (Get-SqTimestamp $stamp); RunId = $runId; RoundId = $roundId
                    Ceiling = (ConvertTo-SqDecimal (& $get 'Ceiling USD')); Decision = (& $get 'Decision'); Confidence = (& $get 'Confidence')
                })
        }
    }
    $result
}

function Read-SqNotifications {
    <#
    .SYNOPSIS
        Reads notifications.md entries (### <timestamp> <trigger> with Mode/Channel/Approval Ref/Topic/Awaiting/Resolved).
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return , @() }
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($chunk in (Split-SqByHeading -Text $Text -Level 3)) {
        $fields = Get-SqBulletFields -Lines @($chunk.Lines)
        $heading = [string]$chunk.Heading
        $stamp = $null
        $trigger = $heading
        if ($heading -match '^(?<ts>\d{4}-\d{2}-\d{2}(?:[T ]\S+)?)\s*(?<t>.*)$') { $stamp = Get-SqTimestamp $Matches.ts; $trigger = $Matches.t.Trim() }
        $get = { param($name) if ($fields.Contains($name)) { ConvertTo-SqPlainText ([string]$fields[$name]) } else { '' } }
        $entries.Add([pscustomobject]@{
                Timestamp = $stamp; Trigger = (ConvertTo-SqPlainText $trigger); Mode = (& $get 'Mode'); Channel = (& $get 'Channel')
                ApprovalRef = (& $get 'Approval Ref'); Topic = (& $get 'Topic'); Awaiting = (& $get 'Awaiting'); Resolved = (& $get 'Resolved')
            })
    }
    , $entries.ToArray()
}

function Read-SqRunFile {
    <#
    .SYNOPSIS
        Reads an autopilot-run or autonomous-loop summary: header bullets, stage rows, and gate rows.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][string]$Name)
    $kind = if ($Name -like 'autonomous-loop-*') { 'autonomous' } else { 'autopilot' }
    $document = ConvertFrom-SqMarkdown $Text
    $fields = [ordered]@{}
    foreach ($block in $document.Blocks) {
        if ($block.Type -ne 'list') { continue }
        foreach ($item in $block.Items) {
            if ($item.Text -match '^(?<k>[A-Z][A-Za-z0-9 /&()-]{0,60}?):\s*(?<v>.*)$' -and -not $fields.Contains($Matches.k)) { $fields[$Matches.k] = ConvertTo-SqPlainText $Matches.v }
        }
    }
    $stageGates = [Collections.Generic.List[object]]::new()
    $meta = [Collections.Generic.List[object]]::new()
    $currentHeading = ''
    foreach ($block in $document.Blocks) {
        if ($block.Type -eq 'heading') { $currentHeading = $block.Text; continue }
        if ($block.Type -ne 'table') { continue }
        $headers = $block.Headers
        $gateIndex = Find-SqColumn $headers '^gate fired'
        $stageIndex = Find-SqColumn $headers '^(stage|sub-squad)$'
        $resultIndex = Find-SqColumn $headers '^result$'
        if ($gateIndex -ge 0) {
            foreach ($row in $block.Rows) {
                $gate = ConvertTo-SqPlainText $row[$gateIndex]
                if ($gate -eq '' -or $gate -match '^(none|n/a|—|–|-)$') { continue }
                $date = [regex]::Match($currentHeading, '\d{4}-\d{2}-\d{2}').Value
                $stageGates.Add([pscustomobject]@{
                        Stage  = $(if ($stageIndex -ge 0) { ConvertTo-SqPlainText $row[$stageIndex] } else { '' })
                        Gate   = $gate
                        Result = $(if ($resultIndex -ge 0) { ConvertTo-SqPlainText $row[$resultIndex] } else { '' })
                        Date   = $date
                    })
            }
        }
        $timestampIndex = Find-SqColumn $headers '^timestamp$'
        $gateNameIndex = Find-SqColumn $headers '^gate$'
        if ($timestampIndex -ge 0 -and $gateNameIndex -ge 0) {
            $raisedIndex = Find-SqColumn $headers '^raised by'
            $awaitIndex = Find-SqColumn $headers '^awaiting'
            $notesIndex = Find-SqColumn $headers '^notes$'
            foreach ($row in $block.Rows) {
                $meta.Add([pscustomobject]@{
                        Timestamp = (Get-SqTimestamp (ConvertTo-SqPlainText $row[$timestampIndex]))
                        Gate      = (ConvertTo-SqPlainText $row[$gateNameIndex])
                        RaisedBy  = $(if ($raisedIndex -ge 0) { ConvertTo-SqPlainText $row[$raisedIndex] } else { '' })
                        Resolved  = $(if ($awaitIndex -ge 0) { ConvertTo-SqPlainText $row[$awaitIndex] } else { '' })
                        Notes     = $(if ($notesIndex -ge 0) { ConvertTo-SqPlainText $row[$notesIndex] } else { '' })
                    })
            }
        }
    }
    $title = ($document.Blocks | Where-Object { $_.Type -eq 'heading' -and $_.Level -eq 1 } | Select-Object -First 1)
    [pscustomobject]@{
        Kind       = $kind
        Name       = $Name
        Title      = $(if ($title) { [string]$title.Text } else { $Name })
        Topic      = $(if ($fields.Contains('Topic')) { [string]$fields['Topic'] } else { '' })
        Outcome    = $(if ($fields.Contains('Outcome')) { [string]$fields['Outcome'] } else { '' })
        Ceiling    = $(if ($fields.Contains('Cost Ceiling')) { [string]$fields['Cost Ceiling'] } else { '' })
        StageGates = $stageGates.ToArray()
        MetaGates  = $meta.ToArray()
    }
}

function Read-SqJournal {
    <#
    .SYNOPSIS
        Reads the optional exact-session journal (consumption-sessions.json) for provenance and request-identity overlap.
    .DESCRIPTION
        Reads the camelCase keys the journal writer emits. A shape the writer never produces is ignored rather than guessed, a request
        without a string or number identity records none, and an unreadable value marks the whole journal unreadable with a fixed message.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try { $document = Open-SqJsonDocument -Text $Text -MaxDepth 32 }
    catch { return [pscustomobject]@{ Valid = $false; Error = (Get-SqErrorText $_.Exception); Sessions = @(); RequestHashes = @() } }
    $sessions = [Collections.Generic.List[object]]::new()
    $hashes = [Collections.Generic.List[string]]::new()
    try {
        # Only the few fields the report needs are read, straight from the parsed document: a journal can hold thousands of request identities.
        $field = {
            param($element, $name)
            $value = [Text.Json.JsonElement]::new()
            if (-not $element.TryGetProperty($name, [ref]$value)) { return '' }
            switch ($value.ValueKind) {
                ([Text.Json.JsonValueKind]::String) { $value.GetString() }
                ([Text.Json.JsonValueKind]::Number) { $value.GetRawText() }
                ([Text.Json.JsonValueKind]::True) { 'True' }
                ([Text.Json.JsonValueKind]::False) { 'False' }
                default { '' }
            }
        }
        $root = $document.RootElement
        $sessionsElement = [Text.Json.JsonElement]::new()
        if ($root.ValueKind -eq [Text.Json.JsonValueKind]::Object -and $root.TryGetProperty('sessions', [ref]$sessionsElement) -and $sessionsElement.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
            foreach ($session in $sessionsElement.EnumerateArray()) {
                if ($session.ValueKind -ne [Text.Json.JsonValueKind]::Object) { continue }
                $nano = [decimal]0
                $requests = [decimal]0
                $roles = 0
                $rowsElement = [Text.Json.JsonElement]::new()
                if ($session.TryGetProperty('rows', [ref]$rowsElement) -and $rowsElement.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
                    foreach ($row in $rowsElement.EnumerateArray()) {
                        if ($row.ValueKind -ne [Text.Json.JsonValueKind]::Object) { continue }
                        $roles++
                        $number = ConvertTo-SqDecimal (& $field $row 'nanoAiu')
                        if ($null -ne $number) { $nano += $number }
                        $number = ConvertTo-SqDecimal (& $field $row 'requests')
                        if ($null -ne $number) { $requests += $number }
                        $detailsElement = [Text.Json.JsonElement]::new()
                        if ($row.TryGetProperty('requestDetails', [ref]$detailsElement) -and $detailsElement.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
                            foreach ($request in $detailsElement.EnumerateArray()) {
                                if ($request.ValueKind -ne [Text.Json.JsonValueKind]::Object) { continue }
                                $identity = [Text.Json.JsonElement]::new()
                                if (-not $request.TryGetProperty('identityHash', [ref]$identity)) { continue }
                                $hash = switch ($identity.ValueKind) {
                                    ([Text.Json.JsonValueKind]::String) { $identity.GetString() }
                                    ([Text.Json.JsonValueKind]::Number) { $identity.GetRawText() }
                                    default { '' }
                                }
                                if ($hash) { $hashes.Add($hash) }
                            }
                        }
                    }
                }
                $records = ConvertTo-SqDecimal (& $field $session 'records')
                $sessions.Add([pscustomobject]@{
                        SessionId = (& $field $session 'sessionId'); Source = (& $field $session 'source'); First = (& $field $session 'first'); Last = (& $field $session 'last')
                        Through = (& $field $session 'through'); Records = $(if ($null -ne $records) { $records } else { [decimal]0 })
                        Digest = (& $field $session 'identityDigest'); Roles = $roles; Requests = $requests; NanoAiu = $nano
                    })
            }
        }
    }
    catch {
        # An unpaired surrogate or an out-of-range number cannot be read; the journal is then shown as unreadable instead of aborting the report.
        return [pscustomobject]@{ Valid = $false; Error = 'a value is invalid or out of range'; Sessions = @(); RequestHashes = @() }
    }
    finally { $document.Dispose() }
    [pscustomobject]@{ Valid = $true; Error = ''; Sessions = $sessions.ToArray(); RequestHashes = $hashes.ToArray() }
}

function Read-SqRates {
    <#
    .SYNOPSIS
        Reads consumption-rates.md: observation date, billing/credit lines, calibration, and the per-model rate table.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    $document = ConvertFrom-SqMarkdown $Text
    $observed = ''
    $billing = ''
    $credit = ''
    foreach ($block in $document.Blocks) {
        if ($block.Type -ne 'list') { continue }
        foreach ($item in $block.Items) {
            $plain = ConvertTo-SqPlainText $item.Text
            if ($plain -match '^Observed-on:\s*(?<d>\d{4}-\d{2}-\d{2})' -and -not $observed) { $observed = $Matches.d }
            elseif ($plain -match '^Billing model:\s*(?<b>.+)$' -and -not $billing) { $billing = $Matches.b.Trim() }
            elseif ($plain -match '^Credit conversion:\s*(?<c>.+)$' -and -not $credit) { $credit = $Matches.c.Trim() }
        }
    }
    $calibration = [ordered]@{}
    foreach ($block in $document.Blocks) {
        if ($block.Type -eq 'code' -and $block.Text -match 'calibration_factor') {
            foreach ($line in ($block.Text -split "`n")) {
                if ($line -match '^\s*(?<k>[a-z_]+):\s*(?<v>.+?)\s*$') { $calibration[$Matches.k] = $Matches.v.Trim('"', "'") }
            }
        }
    }
    $rates = $null
    foreach ($block in $document.Blocks) {
        if ($block.Type -ne 'table') { continue }
        $joined = ($block.Headers -join '|')
        if ($joined -match '(?i)Input' -and $joined -match '(?i)Cached' -and $joined -match '(?i)Cache write' -and $joined -match '(?i)Output' -and $joined -match '(?i)Model' -and $null -eq $rates) { $rates = $block }
    }
    [pscustomobject]@{ ObservedOn = $observed; Billing = $billing; CreditConversion = $credit; Calibration = $calibration; RateTable = $rates }
}
