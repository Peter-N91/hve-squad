# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Watch Mode delivery contracts loaded by SquadWatch.psm1. Mechanics stay here so
# hot instruction files do not grow. The module exports the public functions.

Set-StrictMode -Version Latest

$script:SquadWatchSpine = @('researcher', 'lead', 'developer', 'tester', 'scribe')
$script:SquadWatchCatalogPath = Join-Path $PSScriptRoot '../references/profiles-and-packs.md'
$script:SquadWatchKnownProfiles = @(
    'default', 'full', 'security', 'design', 'accessibility', 'architecture',
    'azure', 'modernization', 'compliance', 'operations', 'product'
)
$script:SquadWatchQuestionsStart = '<!-- squad-watch-open-questions:start -->'
$script:SquadWatchQuestionsEnd = '<!-- squad-watch-open-questions:end -->'
$script:SquadWatchGenericValidationFailure = 'Watch Mode validation failed. The run log has the details. No untrusted cells were published.'
$script:SquadWatchDataFields = @(
    'Kind', 'Number', 'Ref', 'SubSquad', 'Title', 'Body', 'Base', 'Head',
    'Thread', 'IsPullRequest', 'Command', 'Request', 'Task', 'Branch', 'Before', 'After'
)
$script:SquadWatchLifecycleStages = @(
    'Intake', 'Research', 'Plan', 'Council', 'Implement', 'Review', 'Risk', 'Impactful-Action'
)

function Get-SquadWatchDataFieldName {
    <#
    .SYNOPSIS
        Returns every untrusted DATA field used by the live and template Watch workflows.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $script:SquadWatchDataFields
}

function ConvertTo-SquadWatchJsonString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return 'null'
    }

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    foreach ($char in ([string]$Value).ToCharArray()) {
        $code = [int]$char
        if ($char -eq '"') {
            [void]$builder.Append('\"')
        }
        elseif ($char -eq '\') {
            [void]$builder.Append('\\')
        }
        elseif ($char -eq "`b") {
            [void]$builder.Append('\b')
        }
        elseif ($char -eq "`f") {
            [void]$builder.Append('\f')
        }
        elseif ($char -eq "`n") {
            [void]$builder.Append('\n')
        }
        elseif ($char -eq "`r") {
            [void]$builder.Append('\r')
        }
        elseif ($char -eq "`t") {
            [void]$builder.Append('\t')
        }
        elseif ($char -eq '<' -or $char -eq '>' -or $code -eq 0x2028 -or $code -eq 0x2029 -or $code -lt 0x20) {
            [void]$builder.AppendFormat('\u{0:x4}', $code)
        }
        else {
            [void]$builder.Append($char)
        }
    }
    [void]$builder.Append('"')
    $builder.ToString()
}

function ConvertTo-SquadWatchDataBlock {
    <#
    .SYNOPSIS
        Frames untrusted event fields as JSON strings so a value cannot emit a raw DATA terminator.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Fields
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<<<DATA')
    foreach ($key in @($Fields.Keys)) {
        $encoded = ConvertTo-SquadWatchJsonString -Value $Fields[$key]
        if ($encoded.Contains('>') -or $encoded.Contains([string][char]0x2028) -or $encoded.Contains([string][char]0x2029)) {
            throw "DATA framing left a raw delimiter character in field '$key'."
        }
        $lines.Add(('{0}: {1}' -f $key, $encoded))
    }
    $lines.Add('DATA>>>')
    ($lines -join "`n")
}

function ConvertFrom-SquadWatchDataBlock {
    <#
    .SYNOPSIS
        Decodes a Watch DATA frame and fails if a raw closing delimiter appears inside it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string]$Frame
    )

    $lines = @($Frame -split "`r?`n")
    if ($lines.Count -lt 2 -or $lines[0] -ne '<<<DATA' -or $lines[-1] -ne 'DATA>>>') {
        throw 'DATA frame markers are missing or misplaced.'
    }

    $interior = $lines[1..($lines.Count - 2)] -join "`n"
    if ($interior.Contains('DATA>>>') -or $interior.Contains('>')) {
        throw 'DATA frame interior contains a raw closing delimiter.'
    }

    $decoded = [ordered]@{}
    foreach ($line in @($lines | Select-Object -Skip 1 | Select-Object -SkipLast 1)) {
        $split = $line.IndexOf(': ')
        if ($split -lt 1) {
            throw 'DATA frame line is not a JSON field.'
        }
        $key = $line.Substring(0, $split)
        $json = $line.Substring($split + 2)
        $decoded[$key] = ConvertFrom-Json -InputObject $json
    }
    $decoded
}

function ConvertTo-SquadWatchInertCell {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    $zwsp = [char]0x200B
    $lineBreaks = "[\r\n$([char]0x2028)$([char]0x2029)]+"
    $text = $Value -replace $lineBreaks, ' ' -replace '\|', ' '
    $text = [regex]::Replace($text, '&(?!(?:amp|lt|gt|quot|#\d+|#x[0-9A-Fa-f]+);)', '&amp;')
    $text = $text.Replace('<', '&lt;').Replace('>', '&gt;')
    $text = [regex]::Replace($text, '@(?!\u200B)', "@$zwsp")
    $text = [regex]::Replace($text, '`(?!\u200B)', "``$zwsp")
    $text = [regex]::Replace($text, '~(?!\u200B)', "~$zwsp")
    $text = [regex]::Replace($text, '\[(?!\u200B)', "[$zwsp")
    $text = [regex]::Replace($text, '\](?!\u200B)', "]$zwsp")
    $text = [regex]::Replace($text, '\((?!\u200B)', "($zwsp")
    $text = [regex]::Replace($text, '\)(?!\u200B)', ")$zwsp")
    $text = [regex]::Replace(
        $text,
        '(?i)\b(?<kw>Closes|Fixes|Resolves)\b(?<ws>\s*)(?<repo>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?(?<hash>#)',
        {
            param($match)
            if ($match.Value.Contains([char]0x200B)) {
                return $match.Value
            }
            return $match.Groups['kw'].Value + $match.Groups['ws'].Value + $match.Groups['repo'].Value + [char]0x200B + '#'
        }
    )
    $text = [regex]::Replace($text, '(?i)https?(?!\u200B)://', { param($match) $match.Value.Insert(4, [char]0x200B) })
    $text = [regex]::Replace($text, '(?i)(?<![/\w])www(?!\u200B)\.', "www$zwsp.")
    $protected = [System.Collections.Generic.List[string]]::new()
    $text = [regex]::Replace(
        $text,
        'OQ-WATCH-\d{3}|decisions\.md#[A-Za-z0-9-]+|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#\d+',
        {
            param($match)
            $protected.Add($match.Value) | Out-Null
            return ('__SWP{0}__' -f ($protected.Count - 1))
        }
    )
    $text = [regex]::Replace(
        $text,
        '(?<![/\w])(?<user>[A-Za-z0-9._%+-]+)@(?<host>[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)',
        {
            param($match)
            if ($match.Value.Contains([char]0x200B)) { return $match.Value }
            $hostName = $match.Groups['host'].Value
            $lastDot = $hostName.LastIndexOf('.')
            $finalLabel = $hostName.Substring($lastDot + 1)
            if ($lastDot -lt 1 -or $finalLabel -notmatch '^[A-Za-z]{2,}$') { return $match.Value }
            $brokenHost = $hostName.Substring(0, $lastDot) + [char]0x200B + $hostName.Substring($lastDot)
            return $match.Groups['user'].Value + [char]0x200B + '@' + $brokenHost
        }
    )
    $text = [regex]::Replace(
        $text,
        '(?<![/@\w])(?<host>[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)\b',
        {
            param($match)
            if ($match.Value.Contains([char]0x200B)) { return $match.Value }
            $hostName = $match.Value
            $lastDot = $hostName.LastIndexOf('.')
            $finalLabel = $hostName.Substring($lastDot + 1)
            if ($finalLabel -notmatch '^[A-Za-z]{2,}$') { return $match.Value }
            return $hostName.Substring(0, $lastDot) + [char]0x200B + $hostName.Substring($lastDot)
        }
    )
    for ($index = 0; $index -lt $protected.Count; $index++) {
        $text = $text.Replace(('__SWP{0}__' -f $index), $protected[$index])
    }
    $text
}

function ConvertTo-SquadWatchInertReview {
    <#
    .SYNOPSIS
        Encodes model review text before a write-capable comment, preserving line breaks.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [string]$Text,

        [int]$MaxLength = 16000
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }
    $lines = foreach ($line in ($Text -split "`r?`n")) {
        ConvertTo-SquadWatchInertCell -Value $line
    }
    $encoded = $lines -join "`n"
    if ($encoded.Length -gt $MaxLength) {
        $encoded = $encoded.Substring(0, $MaxLength).TrimEnd() + "`n`n[truncated]"
    }
    $encoded
}

function Test-SquadWatchSourceToken {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [string]$Source,

        [string]$CurrentThread
    )

    if ([string]::IsNullOrWhiteSpace($Source)) {
        return $false
    }
    if ($Source -match '^OQ-WATCH-[0-9]{3}$') {
        return $true
    }
    if ($Source -match '^decisions\.md#[a-z0-9]+(?:-[a-z0-9]+)*$') {
        return $true
    }
    if ($CurrentThread -and $Source -ceq $CurrentThread -and $CurrentThread -match '^[^/\s]+/[^#\s]+#[0-9]+$') {
        return $true
    }
    $false
}

function Test-SquadWatchOpenQuestions {
    <#
    .SYNOPSIS
        Validates complete current-run Open Questions coverage and allowlisted inert cells.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The approved plan exports this plural contract name.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [string]$CurrentThread,

        [string[]]$RequiredIds
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.List[string]]::new()
    $limits = @{
        ID       = 32
        Source   = 256
        Question = 1000
        Impact   = 1000
        Status   = 256
    }

    foreach ($row in $Rows) {
        $cells = @{}
        foreach ($column in @('ID', 'Source', 'Question', 'Impact', 'Status')) {
            $raw = if ($row -is [System.Collections.IDictionary]) { $row[$column] } else { $row.$column }
            $cells[$column] = ConvertTo-SquadWatchInertCell -Value ([string]$raw)
            if ([string]::IsNullOrWhiteSpace($cells[$column])) {
                $failures.Add("Open Questions $column is empty")
            }
            elseif ($cells[$column].Length -gt $limits[$column]) {
                $failures.Add("Open Questions $column exceeds $($limits[$column]) characters")
            }
        }
        $id = [string]$cells['ID']
        if ($id -and $seen.Contains($id)) {
            $failures.Add("Open Questions ID '$id' is duplicated")
        }
        elseif ($id) {
            $seen.Add($id)
        }
        if (-not (Test-SquadWatchSourceToken -Source $cells['Source'] -CurrentThread $CurrentThread)) {
            $failures.Add('Open Questions Source is not allowlisted')
        }
    }

    foreach ($required in @($RequiredIds | Where-Object { $_ })) {
        if (-not $seen.Contains([string]$required)) {
            $failures.Add("Open Questions coverage is missing '$required'")
        }
    }

    [pscustomobject]@{
        Valid    = ($failures.Count -eq 0)
        Failures = @($failures)
        Message  = $(if ($failures.Count -eq 0) { 'none' } else { $script:SquadWatchGenericValidationFailure })
    }
}

function ConvertTo-SquadWatchOpenQuestionsMarkdown {
    <#
    .SYNOPSIS
        Renders a deterministic inert Open Questions table, or a generic failure when validation fails.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [string]$CurrentThread,

        [string[]]$RequiredIds
    )

    $validation = Test-SquadWatchOpenQuestions -Rows $Rows -CurrentThread $CurrentThread -RequiredIds $RequiredIds
    if (-not $validation.Valid) {
        return $script:SquadWatchGenericValidationFailure
    }

    $rendered = foreach ($row in $Rows) {
        $cells = foreach ($column in @('ID', 'Source', 'Question', 'Impact', 'Status')) {
            $raw = if ($row -is [System.Collections.IDictionary]) { $row[$column] } else { $row.$column }
            ConvertTo-SquadWatchInertCell -Value ([string]$raw)
        }
        '| ' + ($cells -join ' | ') + ' |'
    }

    @(
        '## Open Questions'
        ''
        '| ID | Source | Question | Impact | Status |'
        '| --- | --- | --- | --- | --- |'
        @($rendered)
    ) -join "`n"
}

function ConvertTo-SquadWatchHeadingMask {
    <#
    .SYNOPSIS
        Blanks completed fences and DATA frames so quoted headings are not run boundaries.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }
    $builder = [System.Text.StringBuilder]::new($Text)
    $spans = [System.Collections.Generic.List[object]]::new()
    $fenceStart = -1
    $fenceChar = ''
    $fenceSize = 0
    $dataStart = -1
    foreach ($line in [regex]::Matches($Text, '(?m)^[^\r\n]*')) {
        $value = $line.Value
        $trim = $value.Trim()
        if ($dataStart -ge 0) {
            if ($trim -eq 'DATA>>>') {
                $spans.Add([pscustomobject]@{ Start = $dataStart; End = $line.Index }) | Out-Null
                $dataStart = -1
            }
            continue
        }
        if ($fenceStart -ge 0) {
            $close = '^[ ]{0,3}' + [regex]::Escape($fenceChar) + '{' + $fenceSize + ',}[ ]*$'
            if ($value -match $close) {
                $spans.Add([pscustomobject]@{ Start = $fenceStart; End = $line.Index }) | Out-Null
                $fenceStart = -1
            }
            continue
        }
        if ($trim -eq '<<<DATA') {
            $dataStart = $line.Index + $line.Length
            continue
        }
        $tick = [char]96
        $opened = [regex]::Match($value, ('^[ ]{0,3}(?<mark>(' + [regex]::Escape([string]$tick) + '{3,}|~{3,}))'))
        if ($opened.Success) {
            $fenceChar = $opened.Groups['mark'].Value.Substring(0, 1)
            $fenceSize = $opened.Groups['mark'].Value.Length
            $fenceStart = $line.Index + $line.Length
        }
    }
    foreach ($span in $spans) {
        for ($index = $span.Start; $index -lt $span.End -and $index -lt $builder.Length; $index++) {
            $char = $builder[$index]
            if ($char -ne "`n" -and $char -ne "`r") {
                $builder[$index] = ' '
            }
        }
    }
    $builder.ToString()
}

function Get-SquadWatchCurrentRunBoundary {
    <#
    .SYNOPSIS
        Authenticates the current-run slice against the trusted resolver run id.
    .DESCRIPTION
        The slice starts at the single selection heading whose run id equals the trusted
        run id. A second heading for that run, or any later selection heading, fails
        closed. Quoted headings inside a completed fence or DATA frame are not boundaries.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [string]$Markdown,

        [AllowNull()]
        [string]$CurrentRunId
    )

    $text = [string]$Markdown
    if ([string]::IsNullOrWhiteSpace($CurrentRunId)) {
        return [pscustomobject]@{ Ok = $false; Reason = 'run-id-missing'; Markdown = ''; Start = -1 }
    }
    $masked = ConvertTo-SquadWatchHeadingMask -Text $text
    $selections = [regex]::Matches($masked, '(?m)^## Watch Profile Selection \S+ (?<runId>\S+)\s*$')
    $current = @($selections | Where-Object { $_.Groups['runId'].Value -ceq $CurrentRunId })
    if ($current.Count -eq 0) {
        return [pscustomobject]@{ Ok = $true; Reason = 'no-current-selection'; Markdown = ''; Start = -1 }
    }
    if ($current.Count -gt 1) {
        return [pscustomobject]@{ Ok = $false; Reason = 'duplicate-current-run-selection'; Markdown = ''; Start = -1 }
    }
    $start = $current[0].Index
    foreach ($selection in $selections) {
        if ($selection.Index -gt $start) {
            return [pscustomobject]@{ Ok = $false; Reason = 'unauthenticated-later-selection'; Markdown = ''; Start = $start }
        }
    }
    [pscustomobject]@{
        Ok       = $true
        Reason   = 'current-run'
        Markdown = $text.Substring($start)
        Start    = $start
    }
}

function Get-SquadWatchCouncilQuestionId {
    <#
    .SYNOPSIS
        Builds a question id that is unique per council verdict and finding and fits in 32 characters.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Topic,

        [Parameter(Mandatory)]
        [int]$Ordinal,

        [Parameter(Mandatory)]
        [string]$Role,

        [Parameter(Mandatory)]
        [string]$Suffix
    )

    $roleToken = [regex]::Replace($Role.ToUpperInvariant(), '[^A-Z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($roleToken)) {
        $roleToken = 'ROLE'
    }
    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Topic) -and $Topic -notmatch '^\d+$') {
        $topicToken = [regex]::Replace($Topic.ToUpperInvariant(), '[^A-Z0-9]', '')
        if ($topicToken -and -not $candidates.Contains("COUNCIL-$topicToken-$roleToken-$Suffix")) {
            $candidates.Add("COUNCIL-$topicToken-$roleToken-$Suffix")
        }
    }
    $candidates.Add("COUNCIL-$Ordinal-$roleToken-$Suffix")
    $shortRole = if ($roleToken.Length -gt 8) { $roleToken.Substring(0, 8) } else { $roleToken }
    $candidates.Add("C$Ordinal-$shortRole-$Suffix")
    foreach ($candidate in $candidates) {
        if ($candidate.Length -le 32 -and $candidate -match '^[A-Z0-9-]+$') {
            return $candidate
        }
    }
    $fallback = "C$Ordinal-$Suffix"
    if ($fallback.Length -gt 32) {
        return $fallback.Substring(0, 32)
    }
    $fallback
}

function Get-SquadWatchCouncilFindingPart {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([AllowNull()][string]$Cell)

    $parts = [System.Collections.Generic.List[string]]::new()
    $text = [string]$Cell
    if (-not [string]::IsNullOrWhiteSpace($text) -and $text.Trim() -notmatch '^(?i)(none|n/a|-|<risk>|<list>|<list-or-none>)$') {
        foreach ($part in ($text -split '\s*;\s*')) {
            $trim = $part.Trim()
            if ($trim -and $trim -notmatch '^(?i)(none|n/a|-|<risk>|<list>|<list-or-none>)$') {
                $parts.Add($trim)
            }
        }
    }
    return $parts.ToArray()
}

function Get-SquadWatchSelectionBlock {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Markdown
    )

    $blocks = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrEmpty($Markdown)) {
        return @()
    }

    $masked = ConvertTo-SquadWatchHeadingMask -Text $Markdown
    $selectionMatches = [regex]::Matches($masked, '(?m)^## Watch Profile Selection (?<timestamp>\S+) (?<runId>\S+)\s*$')
    for ($index = 0; $index -lt $selectionMatches.Count; $index++) {
        $start = $selectionMatches[$index].Index
        $end = if ($index + 1 -lt $selectionMatches.Count) { $selectionMatches[$index + 1].Index } else { $masked.Length }
        $body = $masked.Substring($start, $end - $start)
        $fields = @{}
        foreach ($field in @('Selected Profile', 'Selected Packs', 'Dropped Packs', 'Reason', 'Source', 'Demand Ref', 'Notification')) {
            $found = [regex]::Match($body, "(?m)^\*\s*$([regex]::Escape($field)):\s*(?<value>.*)$")
            $fields[$field] = if ($found.Success) { $found.Groups['value'].Value.Trim() } else { '' }
        }
        $blocks.Add([pscustomobject]@{
                Timestamp = $selectionMatches[$index].Groups['timestamp'].Value
                RunId     = $selectionMatches[$index].Groups['runId'].Value
                Fields    = $fields
            })
    }
    @($blocks)
}

function Test-SquadWatchProfileSelection {
    <#
    .SYNOPSIS
        Validates one current-run profile selection, additive packs, and an independent required-role set.
    .DESCRIPTION
        Canonical comparison proves the resulting roster only. It does not record how the roster was constructed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Markdown,

        [Parameter(Mandatory)]
        [string]$CurrentRunId,

        [string]$SelectedProfile,

        [string[]]$SelectedPacks = @(),

        [string[]]$DroppedPacks = @(),

        [string[]]$Roster = @(),

        [string[]]$KnownProfiles,

        [string[]]$InstalledPacks = @(),

        [hashtable]$PackRoleDependencies,

        [string[]]$InstalledExternalRoles = @(),

        [string[]]$RequiredRoles = @(),

        [string[]]$CanonicalProfileRoles,

        [hashtable]$CanonicalPackRoles,

        [string]$DemandText = '',

        [switch]$SensitiveTask,

        [string[]]$LifecycleStages
    )

    if (-not $KnownProfiles) {
        $KnownProfiles = $script:SquadWatchKnownProfiles
    }
    if (-not $CanonicalProfileRoles) {
        $CanonicalProfileRoles = $script:SquadWatchSpine
    }
    if (-not $LifecycleStages) {
        $LifecycleStages = $script:SquadWatchLifecycleStages
    }
    if (-not $PackRoleDependencies) {
        $PackRoleDependencies = @{}
    }
    if (-not $CanonicalPackRoles) {
        $CanonicalPackRoles = @{}
    }

    $failures = [System.Collections.Generic.List[string]]::new()
    $boundary = Get-SquadWatchCurrentRunBoundary -Markdown $Markdown -CurrentRunId $CurrentRunId
    if (-not $boundary.Ok) {
        $failures.Add($boundary.Reason)
    }
    $blocks = @(Get-SquadWatchSelectionBlock -Markdown $Markdown)
    $current = @($blocks | Where-Object { $_.RunId -ceq $CurrentRunId })
    if ($Markdown -and $current.Count -ne 1) {
        $failures.Add('current-run selection block count must be exactly one')
    }
    if ($current.Count -eq 1) {
        $fields = $current[0].Fields
        foreach ($required in @('Selected Profile', 'Selected Packs', 'Dropped Packs', 'Reason', 'Source', 'Demand Ref', 'Notification')) {
            if ([string]::IsNullOrWhiteSpace([string]$fields[$required]) -and $required -ne 'Dropped Packs' -and $required -ne 'Selected Packs') {
                $failures.Add("selection is missing $required")
            }
        }
        if ($fields['Source'] -cne 'watch-demand') {
            $failures.Add('selection Source must be watch-demand')
        }
        if ($fields['Notification'] -cne 'none') {
            $failures.Add('successful selection notification must be none')
        }
        if (-not $SelectedProfile) {
            $SelectedProfile = [string]$fields['Selected Profile']
        }
    }

    if ($SelectedProfile -notin $KnownProfiles -or $SelectedProfile -eq 'custom') {
        $failures.Add('selection must be exactly one known non-custom profile')
    }

    $computedDropped = [System.Collections.Generic.List[string]]::new()
    $retained = [System.Collections.Generic.List[string]]::new()
    foreach ($pack in @($SelectedPacks + @($current | ForEach-Object { $_.Fields['Selected Packs'] -split ',' }))) {
        $name = $pack.Trim()
        if (-not $name -or $name -eq 'none') {
            continue
        }
        $dependency = @()
        if ($PackRoleDependencies.ContainsKey($name)) {
            $dependency = @($PackRoleDependencies[$name])
        }
        $missing = @($dependency | Where-Object { $_ -and $_ -notin $InstalledExternalRoles })
        if ($name -notin $InstalledPacks -or $missing.Count -gt 0) {
            $computedDropped.Add($name)
        }
        elseif ($name -notin $retained) {
            $retained.Add($name)
        }
    }
    foreach ($dropped in @($DroppedPacks)) {
        if ($dropped -and $dropped -ne 'none' -and $dropped -notin $computedDropped) {
            $computedDropped.Add($dropped)
        }
    }

    $expected = [System.Collections.Generic.List[string]]::new()
    foreach ($role in @($CanonicalProfileRoles)) {
        if ($role -and $role -notin $expected) {
            $expected.Add($role)
        }
    }
    foreach ($pack in @($retained)) {
        $packRoles = @()
        if ($CanonicalPackRoles.ContainsKey($pack)) {
            $packRoles = @($CanonicalPackRoles[$pack])
        }
        foreach ($role in $packRoles) {
            if ($role -and $role -notin $expected) {
                $expected.Add($role)
            }
        }
    }
    foreach ($requiredRole in @($RequiredRoles)) {
        if ($requiredRole -and $requiredRole -notin $expected) {
            $expected.Add($requiredRole)
        }
    }
    foreach ($spineRole in $script:SquadWatchSpine) {
        if ($spineRole -notin $expected) {
            $failures.Add("profile spine lost $spineRole")
        }
        if ($Roster.Count -gt 0 -and $spineRole -notin $Roster) {
            $failures.Add("resulting roster pruned $spineRole")
        }
    }
    if ($Roster.Count -gt 0) {
        $rosterSet = @($Roster | Select-Object -Unique)
        $expectedSet = @($expected | Select-Object -Unique)
        $missing = @($expectedSet | Where-Object { $_ -notin $rosterSet })
        $extra = @($rosterSet | Where-Object { $_ -notin $expectedSet })
        if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
            $failures.Add('resulting roster does not equal canonical profile plus retained pack rows')
        }
    }

    $blocked = $false
    foreach ($requiredRole in @($RequiredRoles)) {
        if ($requiredRole -and $requiredRole -notin $Roster) {
            $blocked = $true
            $failures.Add("required role $requiredRole is unavailable")
        }
    }

    $downgraded = $false
    if ($DemandText -match '(?i)\b(?:use|select)\s+default\b' -and $SensitiveTask -and $SelectedProfile -eq 'default') {
        $downgraded = $true
        $failures.Add('demand text downgraded a sensitive task to default')
    }
    foreach ($stage in $script:SquadWatchLifecycleStages) {
        if ($DemandText -match "(?i)\bskip\s+$stage\b" -and $stage -notin $LifecycleStages) {
            $downgraded = $true
            $failures.Add("demand text skipped $stage")
        }
    }

    $valid = $failures.Count -eq 0 -and -not $blocked
    [pscustomobject]@{
        Valid              = $valid
        Blocked            = $blocked
        Downgraded         = $downgraded
        Failures           = @($failures)
        SelectedProfile    = $SelectedProfile
        SelectedPacks      = @($retained)
        DroppedPacks       = @($computedDropped)
        Notification       = $(if ($valid) { 'none' } else { 'escalate' })
        Assurance          = 'resulting-roster-only'
        HistoricalRetained = @($blocks | Where-Object { $_.RunId -cne $CurrentRunId }).Count
    }
}

function Test-SquadWatchActorAuthorized {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('live', 'template')]
        [string]$Workflow,

        [Parameter(Mandatory)]
        [string]$EventName,

        [string]$Permission = 'none',

        [switch]$LabelGate,

        [switch]$SameRepository,

        [switch]$Fork,

        [switch]$RegisteredApprover
    )

    if ($RegisteredApprover -and $Permission -notin @('write', 'maintain', 'admin')) {
        return $false
    }
    if ($Fork) {
        return $false
    }

    $collaborator = $Permission -in @('write', 'maintain', 'admin')
    if ($EventName -in @('issues', 'issue_comment', 'workflow_dispatch')) {
        return $collaborator
    }
    if ($EventName -eq 'pull_request' -and $LabelGate -and $SameRepository) {
        return $true
    }
    if ($Workflow -eq 'template' -and $EventName -eq 'schedule') {
        return $true
    }
    if ($Workflow -eq 'template' -and $EventName -eq 'push') {
        return $collaborator
    }
    $false
}

function Resolve-SquadWatchDelivery {
    <#
    .SYNOPSIS
        Resolves Watch identity, authorization, immutable source SHA, and publication flags.
    .DESCRIPTION
        trustedBaseSha is an input from the post-lock base query and is never copied from sourceSha.
        Reconciliation flags are returned even when interpretation or staging is skipped.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Context
    )

    $workflow = if ($Context.Contains('Workflow')) { [string]$Context['Workflow'] } else { 'live' }
    $eventName = [string]$Context['EventName']
    $owner = [string]$Context['Owner']
    $repo = [string]$Context['Repo']
    $permission = if ($Context.Contains('ActorPermission')) { [string]$Context['ActorPermission'] } else { 'none' }
    $registered = $Context.Contains('RegisteredApprover') -and [bool]$Context['RegisteredApprover']
    $fork = $Context.Contains('Fork') -and [bool]$Context['Fork']
    $labelGate = $Context.Contains('LabelGate') -and [bool]$Context['LabelGate']
    $sameRepo = -not $Context.Contains('SameRepository') -or [bool]$Context['SameRepository']
    $trustedBaseSha = [string]$Context['TrustedBaseSha']
    $defaultSha = if ($Context.Contains('DefaultBranchSha')) { [string]$Context['DefaultBranchSha'] } else { $trustedBaseSha }
    $staleHead = if ($Context.Contains('StaleHeadSha')) { [string]$Context['StaleHeadSha'] } else { '' }
    $baseAllows = -not $Context.Contains('BaseConfigurationAllowsMapping') -or [bool]$Context['BaseConfigurationAllowsMapping']
    $actor = [string]$Context['Actor']
    $runId = [string]$Context['RunId']
    $receivedAt = [string]$Context['ReceivedAt']

    $issueNumber = 0
    if ($Context.Contains('IssueNumber')) {
        $issueNumber = [int]$Context['IssueNumber']
    }
    $prNumber = 0
    if ($Context.Contains('PullRequestNumber')) {
        $prNumber = [int]$Context['PullRequestNumber']
    }

    $authorized = Test-SquadWatchActorAuthorized -Workflow $workflow -EventName $eventName -Permission $permission -LabelGate:$labelGate -SameRepository:$sameRepo -Fork:$fork -RegisteredApprover:$registered
    $notify = -not $authorized -and -not $fork -and $eventName -in @('issues', 'issue_comment', 'workflow_dispatch')

    $candidate = $null
    if ($Context.Contains('CandidatePullRequest') -and $Context['CandidatePullRequest']) {
        $candidate = $Context['CandidatePullRequest']
    }

    $mapped = $false
    $mappedIssue = 0
    $mappingFailures = [System.Collections.Generic.List[string]]::new()
    if ($candidate) {
        $headRef = [string]$candidate['HeadRef']
        $headMatch = [regex]::Match($headRef, '^squad/issue-([0-9]+)$')
        $open = [string]$candidate['State'] -eq 'open'
        $same = [string]$candidate['HeadRepo'] -ceq [string]$candidate['BaseRepo'] -and [string]$candidate['HeadRepo']
        $bot = [string]$candidate['AuthorLogin'] -ceq 'github-actions[bot]'
        $actorOnIssue = Test-SquadWatchActorAuthorized -Workflow $workflow -EventName 'issues' -Permission $permission -RegisteredApprover:$registered
        if (-not $open) { $mappingFailures.Add('pr-not-open') }
        if (-not $same) { $mappingFailures.Add('fork') }
        if (-not $headMatch.Success) { $mappingFailures.Add('head-shape') }
        if (-not $bot) { $mappingFailures.Add('publisher-identity') }
        if (-not $baseAllows) { $mappingFailures.Add('base-configuration') }
        if (-not $actorOnIssue) { $mappingFailures.Add('actor') }
        if ($mappingFailures.Count -eq 0) {
            $mapped = $true
            $mappedIssue = [int]$headMatch.Groups[1].Value
        }
    }

    $member = ''
    $stableRef = ''
    $sourceThreadNumber = ''
    $publicationBranch = ''
    $existingPr = ''
    $kind = $eventName
    $fallback = ''

    if ($mapped) {
        $member = "issue-$mappedIssue"
        $stableRef = "$owner/$repo#$mappedIssue"
        $sourceThreadNumber = [string]$candidate['Number']
        $publicationBranch = "squad/issue-$mappedIssue"
        $existingPr = [string]$candidate['Number']
        $kind = if ($eventName -eq 'pull_request') { 'pull_request' } else { 'issue' }
    }
    elseif ($prNumber -gt 0 -or ($candidate -and ($eventName -eq 'pull_request'))) {
        $number = if ($prNumber -gt 0) { $prNumber } elseif ($candidate) { [int]$candidate['Number'] } else { 0 }
        $member = "pr-$number"
        $stableRef = "$owner/$repo#$number"
        $sourceThreadNumber = [string]$number
        $fallback = 'pr-N'
        $kind = if ($eventName -eq 'pull_request') { 'pull_request' } else { 'comment' }
        if ($fork) {
            $authorized = $false
            $notify = $false
        }
    }
    elseif ($issueNumber -gt 0) {
        $member = "issue-$issueNumber"
        $stableRef = "$owner/$repo#$issueNumber"
        $sourceThreadNumber = [string]$issueNumber
        $publicationBranch = "squad/issue-$issueNumber"
        $kind = if ($eventName -eq 'workflow_dispatch') { 'dispatch' } elseif ($eventName -eq 'issue_comment') { 'comment' } else { 'issue' }
        if ($Context.Contains('ExistingPullRequestNumber') -and $Context['ExistingPullRequestNumber']) {
            $existingPr = [string]$Context['ExistingPullRequestNumber']
            $sourceThreadNumber = $existingPr
        }
    }
    elseif ($eventName -eq 'workflow_dispatch') {
        $member = "dispatch-$runId"
        $stableRef = "$owner/$repo@dispatch-$runId"
        $sourceThreadNumber = ''
        $kind = 'dispatch'
    }

    $branchExists = $Context.Contains('PublicationBranchExists') -and [bool]$Context['PublicationBranchExists']
    $branchTip = if ($Context.Contains('PublicationBranchTip')) { [string]$Context['PublicationBranchTip'] } else { '' }
    $prHead = if ($candidate -and $candidate.Contains('HeadSha')) { [string]$candidate['HeadSha'] } elseif ($Context.Contains('PullRequestHeadSha')) { [string]$Context['PullRequestHeadSha'] } else { '' }

    $sourceSha = $defaultSha
    if ($mapped -or ($branchExists -and $publicationBranch)) {
        $sourceSha = $branchTip
    }
    elseif ($kind -eq 'pull_request' -or ($fallback -eq 'pr-N' -and $prHead)) {
        $sourceSha = $prHead
    }
    if ($sourceSha -and $staleHead -and $sourceSha -ceq $staleHead -and $branchTip -and $branchTip -cne $staleHead) {
        $sourceSha = $branchTip
    }
    if (-not $sourceSha) {
        $sourceSha = $defaultSha
    }

    $persisted = $null
    if ($Context.Contains('PersistedTrigger')) {
        $persisted = $Context['PersistedTrigger']
    }
    $checkpointLost = $Context.Contains('EphemeralCheckpointLost') -and [bool]$Context['EphemeralCheckpointLost']
    $eventId = [string]$Context['TriggerEventId']
    $resumeKind = 'fresh'
    $suppress = $false
    $triggerReceivedAt = $receivedAt
    $triggerRunId = $runId
    if ($checkpointLost -or -not $persisted) {
        $resumeKind = 'fresh'
    }
    elseif ([string]$persisted['eventId'] -ceq $eventId) {
        $triggerReceivedAt = [string]$persisted['receivedAt']
        $triggerRunId = [string]$persisted['runId']
        if ($persisted.Contains('completed') -and [bool]$persisted['completed']) {
            $resumeKind = 'duplicate'
            $suppress = $true
        }
        else {
            $resumeKind = 'interrupted'
        }
    }
    else {
        $resumeKind = 'follow-up'
    }

    $hasExistingPublication = [bool]($existingPr -or ($branchExists -and $publicationBranch))
    $reconcile = $authorized -and $kind -ne 'pull_request' -and $hasExistingPublication
    $publishComment = $authorized -and $kind -ne 'pull_request' -and -not $hasExistingPublication
    if (-not $authorized) {
        $reconcile = $false
        $publishComment = $false
    }

    [pscustomobject]@{
        Authorized            = $authorized
        Notify                = $notify
        Kind                  = $kind
        Member                = $member
        StableRef             = $stableRef
        SourceThread          = $(if ($sourceThreadNumber) { "$owner/$repo#$sourceThreadNumber" } else { '' })
        SourceThreadNumber    = $sourceThreadNumber
        PublicationBranch     = $publicationBranch
        ExistingPr            = $existingPr
        SourceSha             = $sourceSha
        TrustedBaseSha        = $trustedBaseSha
        TriggerSource         = $eventName
        TriggerEventId        = $eventId
        TriggerActor          = $actor
        TriggerReceivedAt     = $triggerReceivedAt
        TriggerRunId          = $triggerRunId
        SuppressInterpret     = $suppress
        ResumeKind            = $resumeKind
        ReconcilePublication  = $reconcile
        PublishSourceComment  = $publishComment
        Mapped                = $mapped
        Fallback              = $fallback
        MappingFailures       = @($mappingFailures)
        StaleHeadDiscarded    = [bool]($staleHead -and $sourceSha -cne $staleHead)
        InterpretationSha     = $sourceSha
        BaselineSha           = $sourceSha
        PatchGenerationSha    = $sourceSha
        ApplySha              = $sourceSha
        RegisteredApproverUsed = $false
    }
}

function Update-SquadWatchMarkedBody {
    <#
    .SYNOPSIS
        Replaces only the marker-delimited Open Questions block, or inserts one pair.
    .DESCRIPTION
        Ambiguous or duplicated markers fail closed and return the original body unchanged.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [string]$Body,

        [Parameter(Mandatory)]
        [string]$Interior,

        [string]$InsertBeforeHeading = '## Notes'
    )

    if (-not $PSCmdlet.ShouldProcess('Open Questions body', 'Replace the marker interior')) {
        return
    }

    $bodyText = [string]$Body
    $startCount = [regex]::Matches($bodyText, [regex]::Escape($script:SquadWatchQuestionsStart)).Count
    $endCount = [regex]::Matches($bodyText, [regex]::Escape($script:SquadWatchQuestionsEnd)).Count
    if ($startCount -eq 0 -and $endCount -eq 0) {
        $block = @(
            $script:SquadWatchQuestionsStart
            $Interior.Trim()
            $script:SquadWatchQuestionsEnd
        ) -join "`n"
        $heading = $bodyText.IndexOf($InsertBeforeHeading)
        $updated = if ($heading -ge 0) {
            $bodyText.Insert($heading, $block + "`n`n")
        }
        else {
            ($bodyText.TrimEnd() + "`n`n" + $block + "`n")
        }
        return [pscustomobject]@{
            Updated   = $true
            Ambiguous = $false
            Body      = $updated
        }
    }

    $start = $bodyText.IndexOf($script:SquadWatchQuestionsStart)
    $end = $bodyText.IndexOf($script:SquadWatchQuestionsEnd)
    $ambiguous = $startCount -ne 1 -or $endCount -ne 1 -or $start -lt 0 -or $end -lt $start
    if ($ambiguous) {
        return [pscustomobject]@{
            Updated   = $false
            Ambiguous = $true
            Body      = $bodyText
        }
    }

    $prefix = $bodyText.Substring(0, $start + $script:SquadWatchQuestionsStart.Length)
    $suffix = $bodyText.Substring($end)
    [pscustomobject]@{
        Updated   = $true
        Ambiguous = $false
        Body      = $prefix + "`n" + $Interior.Trim() + "`n" + $suffix
    }
}

function Invoke-SquadWatchPublicationGit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [System.Collections.Generic.List[string]]$CommandLog,

        [switch]$AllowFailure
    )

    if ($Arguments -contains '--force' -or $Arguments -contains '--force-with-lease') {
        throw 'Squad Watch publication refuses force push.'
    }
    if ($CommandLog) {
        $CommandLog.Add(('git ' + ($Arguments -join ' ')))
    }
    $output = @(& git -C $Repository @Arguments 2>&1)
    if (-not $AllowFailure -and $LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join "`n")"
    }
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = @($output)
    }
}

function Sync-SquadWatchPublication {
    <#
    .SYNOPSIS
        Reconciles an existing publication branch without another model run.
    .DESCRIPTION
        Order is fast-forward push, then one draft PR create-or-reuse, then marker body update.
        An existing remote tip that is not sourceSha fails closed and never force-pushes.
        Committed member evidence is the recovery input; runner artifacts are not read.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [string]$RemoteRepository,

        [Parameter(Mandatory)]
        [string]$PublicationBranch,

        [Parameter(Mandatory)]
        [string]$SourceSha,

        [string]$ExistingPr,

        [string[]]$OpenPullRequestNumbers = @(),

        [string]$Member,

        [string]$CurrentBody = '',

        [string]$OpenQuestionsMarkdown,

        [string]$RemoteName = 'origin',

        [string]$CatalogMarkdown,

        [switch]$ExpectedExisting
    )

    if ($OpenQuestionsMarkdown) {
        Write-Verbose 'Caller-supplied Open Questions markdown is ignored. Committed rows are rendered by the trusted module.'
    }
    $commands = [System.Collections.Generic.List[string]]::new()
    if (-not $PSCmdlet.ShouldProcess($PublicationBranch, 'Reconcile Watch publication')) {
        return
    }

    $remoteTip = ''
    $branchExists = $false
    if ($RemoteRepository) {
        Invoke-SquadWatchPublicationGit -Repository $Repository -Arguments @('fetch', '--quiet', $RemoteName, $PublicationBranch) -CommandLog $commands -AllowFailure | Out-Null
        $tip = Invoke-SquadWatchPublicationGit -Repository $Repository -Arguments @('rev-parse', "$RemoteName/$PublicationBranch") -CommandLog $commands -AllowFailure
        if ($tip.ExitCode -eq 0) {
            $branchExists = $true
            $remoteTip = ([string]$tip.Output[-1]).Trim()
        }
    }
    else {
        $tip = Invoke-SquadWatchPublicationGit -Repository $Repository -Arguments @('rev-parse', '--verify', $PublicationBranch) -CommandLog $commands -AllowFailure
        if ($tip.ExitCode -eq 0) {
            $branchExists = $true
            $remoteTip = ([string]$tip.Output[-1]).Trim()
        }
    }

    $branchDecision = Test-SquadWatchExpectedBranch -ExpectedExisting ([bool]$ExpectedExisting) -Fetched $branchExists
    if (-not $branchDecision.Ok) {
        return [pscustomobject]@{
            Ok                  = $false
            Reason              = 'branch-disappeared'
            ForcePushAttempted  = $false
            Commands            = @($commands)
            CreateDraft         = $false
            ReusedPullRequest   = ''
            Body                = $CurrentBody
            DuplicateCommit     = $false
        }
    }

    if ($branchExists -and $remoteTip -cne $SourceSha) {
        return [pscustomobject]@{
            Ok                  = $false
            Reason              = 'branch-movement'
            ForcePushAttempted  = $false
            Commands            = @($commands)
            CreateDraft         = $false
            ReusedPullRequest   = ''
            Body                = $CurrentBody
            DuplicateCommit     = $false
        }
    }

    $duplicateCommit = $false
    if ($branchExists -and $remoteTip -ceq $SourceSha) {
        $duplicateCommit = $true
    }
    elseif (-not $branchExists) {
        Invoke-SquadWatchPublicationGit -Repository $Repository -Arguments @('branch', $PublicationBranch, $SourceSha) -CommandLog $commands | Out-Null
        if ($RemoteRepository) {
            Invoke-SquadWatchPublicationGit -Repository $Repository -Arguments @('push', $RemoteName, "${PublicationBranch}:${PublicationBranch}") -CommandLog $commands | Out-Null
        }
    }

    $prMatches = @($OpenPullRequestNumbers | Where-Object { $_ })
    if ($ExistingPr) {
        $prMatches = @($ExistingPr)
    }
    if ($prMatches.Count -gt 1) {
        return [pscustomobject]@{
            Ok                 = $false
            Reason             = 'multiple-pull-requests'
            ForcePushAttempted = $false
            Commands           = @($commands)
            CreateDraft        = $false
            ReusedPullRequest  = ''
            Body               = $CurrentBody
            DuplicateCommit    = $duplicateCommit
        }
    }

    $createDraft = $prMatches.Count -eq 0
    $reused = if ($prMatches.Count -eq 1) { [string]$prMatches[0] } else { '' }
    if ($createDraft) {
        $commands.Add('gh pr create --draft')
    }

    $evidence = Get-SquadWatchCommittedQuestionsMarkdown -Repository $Repository -Member $Member -CatalogMarkdown $CatalogMarkdown
    $marked = Update-SquadWatchMarkedBody -Body $CurrentBody -Interior $evidence

    [pscustomobject]@{
        Ok                 = -not $marked.Ambiguous
        Reason             = $(if ($marked.Ambiguous) { 'ambiguous-markers' } else { 'reconciled' })
        ForcePushAttempted = $false
        Commands           = @($commands)
        CreateDraft        = $createDraft
        ReusedPullRequest  = $reused
        Body               = $marked.Body
        Ambiguous          = $marked.Ambiguous
        DuplicateCommit    = $duplicateCommit
        RunnerArtifactsRead = $false
    }
}

function Assert-SquadWatchTrustedHelper {
    <#
    .SYNOPSIS
        Accepts a helper only when it and every transitive import resolve under the trusted root.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$TrustedRoot,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $root = [System.IO.Path]::GetFullPath($TrustedRoot).TrimEnd('\', '/')
    $resolved = [System.IO.Path]::GetFullPath($Path)
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and $resolved -ne $root) {
        throw "Helper '$resolved' is outside trusted root '$root'."
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Trusted helper '$resolved' does not exist."
    }

    $accepted = [System.Collections.Generic.List[string]]::new()
    $pending = [System.Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($resolved)
    while ($pending.Count -gt 0) {
        $current = $pending.Dequeue()
        if ($current -in $accepted) {
            continue
        }
        $accepted.Add($current)
        $text = Get-Content -LiteralPath $current -Raw
        $imports = [regex]::Matches($text, '(?m)^\s*\.\s+(?<path>\S+)')
        foreach ($import in $imports) {
            $raw = $import.Groups['path'].Value
            if ($raw -match '^(Join-Path|\$)') {
                continue
            }
            $candidate = if ([System.IO.Path]::IsPathRooted($raw)) { $raw } else { Join-Path (Split-Path -Parent $current) $raw }
            $full = [System.IO.Path]::GetFullPath($candidate)
            if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Transitive import '$full' is outside trusted root '$root'."
            }
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                $pending.Enqueue($full)
            }
        }
    }
    @($accepted)
}

function Get-SquadWatchPublicationDecision {
    <#
    .SYNOPSIS
        Decides patch upload and publication without redefining HasChanges.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [bool]$HasChanges,

        [Parameter(Mandatory)]
        [bool]$HasMaterialChanges,

        [string]$ExistingPr,

        [string]$SourceThreadNumber,

        [switch]$BranchExists
    )

    $existing = [bool]($ExistingPr -or $BranchExists)
    [pscustomobject]@{
        HasChanges           = $HasChanges
        HasMaterialChanges  = $HasMaterialChanges
        UploadPatch          = $HasChanges -and ($HasMaterialChanges -or $existing)
        CreateBranch         = $HasMaterialChanges -and -not $existing
        CreatePullRequest    = $HasMaterialChanges -and -not $ExistingPr
        ReconcilePublication = $existing -or $HasMaterialChanges
        PublishSourceComment = -not $HasMaterialChanges -and -not $existing -and ($SourceThreadNumber -match '^[0-9]+$')
        IssueLessSummary     = -not $HasMaterialChanges -and -not $existing -and ($SourceThreadNumber -notmatch '^[0-9]+$')
    }
}

function Assert-SquadWatchTrustedCheckout {
    <#
    .SYNOPSIS
        Verifies the pinned checkout before any trusted helper is imported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TrustedRoot,

        [Parameter(Mandatory)]
        [string]$ExpectedSha,

        [string[]]$RelativePaths
    )

    $scriptPath = Join-Path $PSScriptRoot 'Assert-SquadWatchTrustedCheckout.ps1'
    & $scriptPath -TrustedRoot $TrustedRoot -ExpectedSha $ExpectedSha -RelativePaths $RelativePaths
}

function Add-SquadWatchTrustedExclude {
    <#
    .SYNOPSIS
        Excludes the trusted checkout from staging via .git/info/exclude.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository
    )

    $gitDir = Join-Path $Repository '.git'
    if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) {
        return
    }
    $info = Join-Path $gitDir 'info'
    New-Item -ItemType Directory -Path $info -Force | Out-Null
    $exclude = Join-Path $info 'exclude'
    $existing = if (Test-Path -LiteralPath $exclude) { Get-Content -LiteralPath $exclude -Raw } else { '' }
    if ($existing -notmatch '(?m)^\.squad-trusted/\s*$') {
        Add-Content -LiteralPath $exclude -Value '.squad-trusted/' -Encoding ascii
    }
}

function Get-SquadWatchProfileCatalog {
    <#
    .SYNOPSIS
        Parses canonical profile and pack role rows from the pinned catalog.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [string]$Markdown
    )

    $profiles = @{}
    $packs = @{}
    $section = ''
    foreach ($line in ([string]$Markdown -split "`r?`n")) {
        if ($line -match '^## Squad Profiles') { $section = 'profile'; continue }
        if ($line -match '^## Squad Packs') { $section = 'pack'; continue }
        if ($line -match '^## ') { $section = ''; continue }
        if ($section -and $line -match '^\|\s*`(?<name>[a-z0-9-]+)`\s*\|\s*(?<members>[^|]+)\|') {
            $catalogName = $Matches['name']
            $memberCell = $Matches['members']
            $roles = @(
                $memberCell.Split(',') |
                    ForEach-Object { $_.Trim().ToLowerInvariant() } |
                    Where-Object { $_ -match '^[a-z0-9-]+$' }
            )
            if ($section -eq 'profile') { $profiles[$catalogName] = @($roles) }
            else { $packs[$catalogName] = @($roles) }
        }
    }
    [pscustomobject]@{ Profiles = $profiles; Packs = $packs }
}

function Resolve-SquadWatchCanonicalRoster {
    <#
    .SYNOPSIS
        Returns the selected profile roles plus roles of installed selected packs.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Catalog,

        [AllowEmptyString()]
        [string]$ProfileName = '',

        [string[]]$SelectedPacks = @(),

        [string[]]$InstalledPacks = @()
    )

    $name = ([string]$ProfileName).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($name) -or -not $Catalog -or -not $Catalog.Profiles -or -not $Catalog.Profiles.ContainsKey($name)) {
        return [pscustomobject]@{ Ok = $false; Roles = @(); Reason = 'profile-not-in-catalog' }
    }
    $roles = [System.Collections.Generic.List[string]]::new()
    foreach ($role in @($Catalog.Profiles[$name])) {
        if ($role -and -not $roles.Contains($role)) { $roles.Add($role) }
    }
    $installed = @(
        @($InstalledPacks) | Where-Object { $_ } | ForEach-Object { $_.ToString().Trim().ToLowerInvariant() } | Where-Object { $_ }
    )
    foreach ($pack in @($SelectedPacks)) {
        if (-not $pack) { continue }
        $packName = $pack.ToString().Trim().ToLowerInvariant()
        if (-not $packName -or $packName -eq 'none') { continue }
        if (-not $Catalog.Packs.ContainsKey($packName) -or $packName -notin $installed) {
            return [pscustomobject]@{ Ok = $false; Roles = @(); Reason = "pack-not-installed:$packName" }
        }
        foreach ($role in @($Catalog.Packs[$packName])) {
            if ($role -and -not $roles.Contains($role)) { $roles.Add($role) }
        }
    }
    [pscustomobject]@{ Ok = $true; Roles = @($roles); Reason = 'none' }
}

function Get-SquadWatchCurrentRunMarkdown {
    <#
    .SYNOPSIS
        Returns only the decision text for the trusted current run.
    .DESCRIPTION
        The trusted run id comes from the resolver, not from the model text. The slice
        starts at the single matching selection heading and continues to the end. A
        duplicate or later selection heading returns empty; callers fail closed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [string]$Markdown,

        [AllowNull()]
        [string]$CurrentRunId
    )

    $boundary = Get-SquadWatchCurrentRunBoundary -Markdown $Markdown -CurrentRunId $CurrentRunId
    if (-not $boundary.Ok) {
        return ''
    }
    ConvertTo-SquadWatchHeadingMask -Text $boundary.Markdown
}

function Get-SquadWatchRequiredQuestionCoverage {
    <#
    .SYNOPSIS
        Derives required question ids from every current-run risk, council, and assumption record.
    .DESCRIPTION
        A finding with no derivable id is a coverage failure. An unparseable evidence
        source is not treated as an empty required set.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [string]$Markdown,

        [string]$CurrentRunId
    )

    $ids = [System.Collections.Generic.List[string]]::new()
    $reasons = [System.Collections.Generic.List[string]]::new()
    $boundary = Get-SquadWatchCurrentRunBoundary -Markdown $Markdown -CurrentRunId $CurrentRunId
    if (-not $boundary.Ok) {
        return [pscustomobject]@{ Ids = @(); Malformed = $true; Reasons = @($boundary.Reason) }
    }
    $text = ConvertTo-SquadWatchHeadingMask -Text $boundary.Markdown
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [pscustomobject]@{ Ids = @(); Malformed = $false; Reasons = @() }
    }

    $riskSections = [regex]::Matches($text, '(?ms)^#{2,3} [^\r\n]*Risk Gate[^\r\n]*\r?\n(?<body>.*?)(?=^#{2,3} |\z)')
    foreach ($section in $riskSections) {
        $body = $section.Groups['body'].Value
        $findingLines = [System.Collections.Generic.List[string]]::new()
        foreach ($line in ($body -split "`r?`n")) {
            $trim = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trim)) { continue }
            if ($trim -match '^(?i)(none|n/a|-)$') { continue }
            $tick = [char]96
            if ($trim -match ('^(' + [regex]::Escape([string]$tick) + '{3,}|~{3,}|<<<DATA|DATA>>>)$')) { continue }
            if ($trim -match '^\|') {
                $cells = @($trim.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
                if ($cells.Count -lt 2 -or $cells[0] -match '^(?i)(id|role|finding|-+)$') { continue }
                $findingLines.Add($trim) | Out-Null
                continue
            }
            if ($trim -match '^[-*]\s+\S' -or $trim -match '^[A-Za-z0-9]') {
                $findingLines.Add($trim) | Out-Null
            }
        }
        if ($findingLines.Count -eq 0 -and $body.Trim() -and $body -notmatch '(?i)\b(none|n/a)\b' -and $body -notmatch '\b[A-Z][A-Z0-9]*-\d+\b') {
            $reasons.Add('Risk Gate section has no derivable finding id') | Out-Null
        }
        foreach ($line in $findingLines) {
            $tokens = [regex]::Matches($line, '\b[A-Z][A-Z0-9]*-\d+\b')
            if ($tokens.Count -eq 0) {
                $reasons.Add('Risk Gate finding has no derivable id') | Out-Null
                continue
            }
            foreach ($token in $tokens) {
                if (-not $ids.Contains($token.Value)) { $ids.Add($token.Value) }
            }
        }
    }

    $findings = [regex]::Matches($text, '(?ms)^### Findings by Role\s*\r?\n(?<body>.*?)(?=^#{2,3} |\z)')
    $verdictOrdinal = 0
    foreach ($section in $findings) {
        $verdictOrdinal++
        $topic = ''
        $riskCounts = @{}
        $conditionCounts = @{}
        foreach ($line in ($section.Groups['body'].Value -split "`r?`n")) {
            if ($line -notmatch '^\|') { continue }
            $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
            if ($cells.Count -lt 5 -or $cells[0] -match '^(?i)(Role|-+)$') { continue }
            $role = $cells[0]
            if ([string]::IsNullOrWhiteSpace($role)) {
                $reasons.Add('Council finding has no derivable id') | Out-Null
                continue
            }
            $risks = @(Get-SquadWatchCouncilFindingPart -Cell $cells[2])
            $conditions = @(Get-SquadWatchCouncilFindingPart -Cell $cells[4])
            $riskCounts[$role] = [int]$riskCounts[$role]
            foreach ($risk in $risks) {
                $riskCounts[$role] = [int]$riskCounts[$role] + 1
                $suffix = if ([int]$riskCounts[$role] -eq 1) { 'RISK' } else { ('RISK-' + $riskCounts[$role]) }
                $id = Get-SquadWatchCouncilQuestionId -Topic $topic -Ordinal $verdictOrdinal -Role $role -Suffix $suffix
                if ($id.Length -gt 32) {
                    $reasons.Add('Council finding id exceeds 32 characters') | Out-Null
                    continue
                }
                if (-not $ids.Contains($id)) { $ids.Add($id) }
            }
            $conditionCounts[$role] = [int]$conditionCounts[$role]
            foreach ($condition in $conditions) {
                $conditionCounts[$role] = [int]$conditionCounts[$role] + 1
                $id = Get-SquadWatchCouncilQuestionId -Topic $topic -Ordinal $verdictOrdinal -Role $role -Suffix ('COND-' + $conditionCounts[$role])
                if ($id.Length -gt 32) {
                    $reasons.Add('Council finding id exceeds 32 characters') | Out-Null
                    continue
                }
                if (-not $ids.Contains($id)) { $ids.Add($id) }
            }
            if ($risks.Count -eq 0 -and $conditions.Count -eq 0 -and $cells[3] -and $cells[3] -notmatch '^(?i)(none|n/a|-|<list>|<list-or-none>)$') {
                $reasons.Add('Council finding has no derivable id') | Out-Null
            }
        }
    }

    $assumptions = [regex]::Matches($text, '(?ms)^### Recorded Assumptions\s*\r?\n(?<body>.*?)(?=^#{2,3} |\z)')
    $index = 0
    foreach ($section in $assumptions) {
        foreach ($line in ($section.Groups['body'].Value -split "`r?`n")) {
            if ($line -notmatch '^\*\s+(?<text>\S.*)$') { continue }
            $assumption = $Matches['text'].Trim()
            if ($assumption -match '^(?i)(<|empty when none|none)$') { continue }
            $index++
            $id = "ASM-$index"
            if (-not $ids.Contains($id)) { $ids.Add($id) }
        }
    }

    [pscustomobject]@{
        Ids       = @($ids)
        Malformed = ($reasons.Count -gt 0)
        Reasons   = @($reasons)
    }
}

function Get-SquadWatchClosingLabel {
    <#
    .SYNOPSIS
        Returns Closes #N only for a numeric issue reference.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][string]$StableRef)

    if ($StableRef -match '#(?<number>[0-9]+)$' -and $StableRef -notmatch '@') {
        return "Closes #$($Matches['number'])"
    }
    return ''
}

function Test-SquadWatchExpectedBranch {
    <#
    .SYNOPSIS
        Fails closed when an expected publication branch disappeared after resolution.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [bool]$ExpectedExisting,

        [Parameter(Mandatory)]
        [bool]$Fetched
    )

    if ($ExpectedExisting -and -not $Fetched) {
        return [pscustomobject]@{ Ok = $false; Reason = 'branch-disappeared' }
    }
    [pscustomobject]@{ Ok = $true; Reason = 'continue' }
}

function ConvertTo-SquadWatchPublicationRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Row
    )

    $converted = [ordered]@{}
    foreach ($column in @('ID', 'Source', 'Question', 'Impact', 'Status')) {
        $raw = if ($Row -is [System.Collections.IDictionary]) { $Row[$column] } else { $Row.$column }
        $converted[$column] = [string]$raw
    }
    [pscustomobject]$converted
}

function ConvertTo-SquadWatchNameList {
    param($Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        return @($Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    @($Value | ForEach-Object { [string]$_ } | Where-Object { $_ })
}

function Get-SquadWatchCatalogMarkdown {
    param([AllowNull()][string]$CatalogMarkdown)

    if (-not [string]::IsNullOrWhiteSpace($CatalogMarkdown)) {
        return [string]$CatalogMarkdown
    }
    if ($script:SquadWatchCatalogPath -and (Test-Path -LiteralPath $script:SquadWatchCatalogPath)) {
        return Get-Content -LiteralPath $script:SquadWatchCatalogPath -Raw
    }
    return ''
}

function Get-SquadWatchQuestionRecompute {
    <#
    .SYNOPSIS
        Recomputes profile, coverage, and thread binding. Never trusts questionsValid.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        $Payload,

        [string]$CatalogMarkdown,

        [string]$ExpectedMember,

        [string]$ExpectedRunId,

        [string]$ExpectedThread,

        [string]$ExpectedStableRef,

        [string]$ExpectedTrustedBaseSha,

        [AllowNull()]
        [string]$CommittedDecisions,

        [AllowNull()]
        [string]$CommittedTeam
    )

    $generic = $script:SquadWatchGenericValidationFailure
    $names = @($Payload.PSObject.Properties.Name)
    $boundMember = if ($names -contains 'member') { [string]$Payload.member } else { '' }
    $boundRun = if ($names -contains 'runId') { [string]$Payload.runId } else { '' }
    $boundThread = if ($names -contains 'currentThread') { [string]$Payload.currentThread } else { '' }
    $boundStable = if ($names -contains 'stableRef') { [string]$Payload.stableRef } else { '' }
    $boundBase = if ($names -contains 'trustedBaseSha') { [string]$Payload.trustedBaseSha } else { '' }
    if ($ExpectedMember -and $boundMember -cne $ExpectedMember) {
        return [pscustomobject]@{ Ok = $false; Markdown = $generic; Reason = 'member-binding' }
    }
    if ($ExpectedRunId -and $boundRun -cne $ExpectedRunId) {
        return [pscustomobject]@{ Ok = $false; Markdown = $generic; Reason = 'run-binding' }
    }
    if ($ExpectedThread -and $boundThread -cne $ExpectedThread) {
        return [pscustomobject]@{ Ok = $false; Markdown = $generic; Reason = 'thread-binding' }
    }
    if ($ExpectedStableRef -and $boundStable -cne $ExpectedStableRef) {
        return [pscustomobject]@{ Ok = $false; Markdown = $generic; Reason = 'stable-ref-binding' }
    }
    if ($ExpectedTrustedBaseSha -and $boundBase -cne $ExpectedTrustedBaseSha) {
        return [pscustomobject]@{ Ok = $false; Markdown = $generic; Reason = 'base-binding' }
    }
    $normalize = {
        param([AllowNull()][string]$Value)
        (([string]$Value -replace "`r`n", "`n" -replace "`r", "`n").Trim())
    }
    if ([string]::IsNullOrWhiteSpace($CommittedDecisions) -or [string]::IsNullOrWhiteSpace($CommittedTeam)) {
        return [pscustomobject]@{ Ok = $false; Markdown = $generic; Reason = 'committed-evidence-missing' }
    }
    $snapshotDecisions = if ($names -contains 'decisionsMarkdown') { [string]$Payload.decisionsMarkdown } else { '' }
    $snapshotTeam = if ($names -contains 'teamMarkdown') { [string]$Payload.teamMarkdown } else { '' }
    if ((& $normalize $snapshotDecisions) -cne (& $normalize $CommittedDecisions) -or ((& $normalize $snapshotTeam) -cne (& $normalize $CommittedTeam))) {
        return [pscustomobject]@{ Ok = $false; Markdown = $generic; Reason = 'snapshot-mismatch' }
    }
    $catalogText = Get-SquadWatchCatalogMarkdown -CatalogMarkdown $CatalogMarkdown
    if ([string]::IsNullOrWhiteSpace($catalogText)) {
        return [pscustomobject]@{ Ok = $false; Markdown = $generic; Reason = 'catalog-missing' }
    }
    $catalog = Get-SquadWatchProfileCatalog -Markdown $catalogText
    $selectedPacks = if ($names -contains 'selectedPacks') { ConvertTo-SquadWatchNameList $Payload.selectedPacks } else { @() }
    $installedPacks = if ($names -contains 'installedPacks') { ConvertTo-SquadWatchNameList $Payload.installedPacks } else { @() }
    $profileName = if ($names -contains 'profileName') { [string]$Payload.profileName } else { '' }
    $resolved = Resolve-SquadWatchCanonicalRoster `
        -Catalog $catalog `
        -ProfileName $profileName `
        -SelectedPacks $selectedPacks `
        -InstalledPacks $installedPacks
    if (-not $resolved.Ok) {
        return [pscustomobject]@{ Ok = $false; Markdown = $generic; Reason = $resolved.Reason }
    }
    $decisions = [string]$CommittedDecisions
    $team = [string]$CommittedTeam
    $roster = @(Get-SquadWatchTeamRoster -Markdown $team)
    $requiredRoles = @(Get-SquadWatchRequiredRole -Markdown $decisions -CurrentRunId ([string]$Payload.runId))
    $profileCheck = Test-SquadWatchProfileSelection `
        -Markdown $decisions `
        -CurrentRunId $(if ($names -contains 'runId') { [string]$Payload.runId } else { '' }) `
        -Roster $roster `
        -RequiredRoles $requiredRoles `
        -CanonicalProfileRoles $resolved.Roles `
        -KnownProfiles @($catalog.Profiles.Keys)
    if (-not $profileCheck.Valid) {
        return [pscustomobject]@{ Ok = $false; Markdown = $generic; Reason = 'profile-recompute' }
    }
    $coverage = Get-SquadWatchRequiredQuestionCoverage -Markdown $decisions -CurrentRunId ([string]$Payload.runId)
    if ($coverage.Malformed) {
        return [pscustomobject]@{ Ok = $false; Markdown = $generic; Reason = 'malformed-coverage' }
    }
    $rows = @()
    if ($names -contains 'rows' -and $Payload.rows) {
        $rows = @($Payload.rows | Where-Object { $_ } | ForEach-Object { ConvertTo-SquadWatchPublicationRow -Row $_ })
    }
    $thread = if ($names -contains 'currentThread') { [string]$Payload.currentThread } else { '' }
    $questions = Test-SquadWatchOpenQuestions -Rows $rows -CurrentThread $thread -RequiredIds $coverage.Ids
    if (-not $questions.Valid) {
        return [pscustomobject]@{ Ok = $false; Markdown = $generic; Reason = 'coverage-recompute' }
    }
    [pscustomobject]@{
        Ok       = $true
        Markdown = (ConvertTo-SquadWatchOpenQuestionsMarkdown -Rows $rows -CurrentThread $thread -RequiredIds $coverage.Ids)
        Reason   = 'recomputed'
    }
}

function Get-SquadWatchEvidenceQuestionsMarkdown {
    <#
    .SYNOPSIS
        Renders questions from an evidence file only after recomputing coverage.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$EvidencePath,

        [string]$CatalogMarkdown,

        [string]$ExpectedMember,

        [string]$ExpectedRunId,

        [string]$ExpectedThread,

        [string]$ExpectedStableRef,

        [string]$ExpectedTrustedBaseSha,

        [AllowNull()]
        [string]$CommittedDecisions,

        [AllowNull()]
        [string]$CommittedTeam
    )

    if (-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)) {
        return $script:SquadWatchGenericValidationFailure
    }
    $payload = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json
    (Get-SquadWatchQuestionRecompute -Payload $payload -CatalogMarkdown $CatalogMarkdown -ExpectedMember $ExpectedMember -ExpectedRunId $ExpectedRunId -ExpectedThread $ExpectedThread -ExpectedStableRef $ExpectedStableRef -ExpectedTrustedBaseSha $ExpectedTrustedBaseSha -CommittedDecisions $CommittedDecisions -CommittedTeam $CommittedTeam).Markdown
}

function Get-SquadWatchStagedQuestionsMarkdown {
    <#
    .SYNOPSIS
        Renders questions from staging evidence after the resolver binding matches.
    .DESCRIPTION
        The comment job has no source checkout. It may render only the artifact the
        trusted staging step produced, and only when member, run, thread, stable ref,
        and trusted base match the resolver. A mismatch returns the generic failure.
        questionsValid in the artifact is ignored.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The comment contract renders the staged Open Questions block.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$EvidencePath,

        [string]$CatalogMarkdown,

        [string]$ExpectedMember,

        [string]$ExpectedRunId,

        [string]$ExpectedThread,

        [string]$ExpectedStableRef,

        [string]$ExpectedTrustedBaseSha
    )

    $generic = $script:SquadWatchGenericValidationFailure
    if ([string]::IsNullOrWhiteSpace($ExpectedMember) -or [string]::IsNullOrWhiteSpace($ExpectedRunId) -or [string]::IsNullOrWhiteSpace($ExpectedTrustedBaseSha)) {
        return $generic
    }
    if (-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)) {
        return $generic
    }
    $payload = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json
    $names = @($payload.PSObject.Properties.Name)
    $boundMember = if ($names -contains 'member') { [string]$payload.member } else { '' }
    $boundRun = if ($names -contains 'runId') { [string]$payload.runId } else { '' }
    $boundThread = if ($names -contains 'currentThread') { [string]$payload.currentThread } else { '' }
    $boundStable = if ($names -contains 'stableRef') { [string]$payload.stableRef } else { '' }
    $boundBase = if ($names -contains 'trustedBaseSha') { [string]$payload.trustedBaseSha } else { '' }
    if ($boundMember -cne $ExpectedMember -or $boundRun -cne $ExpectedRunId -or $boundBase -cne $ExpectedTrustedBaseSha) {
        return $generic
    }
    if ($ExpectedThread -and $boundThread -cne $ExpectedThread) {
        return $generic
    }
    if ($ExpectedStableRef -and $boundStable -cne $ExpectedStableRef) {
        return $generic
    }
    $decisions = if ($names -contains 'decisionsMarkdown') { [string]$payload.decisionsMarkdown } else { '' }
    $team = if ($names -contains 'teamMarkdown') { [string]$payload.teamMarkdown } else { '' }
    (Get-SquadWatchQuestionRecompute -Payload $payload -CatalogMarkdown $CatalogMarkdown -ExpectedMember $ExpectedMember -ExpectedRunId $ExpectedRunId -ExpectedThread $ExpectedThread -ExpectedStableRef $ExpectedStableRef -ExpectedTrustedBaseSha $ExpectedTrustedBaseSha -CommittedDecisions $decisions -CommittedTeam $team).Markdown
}

function Get-SquadWatchCommittedQuestionsMarkdown {
    <#
    .SYNOPSIS
        Renders Open Questions from committed evidence, never from runner artifacts.
    .DESCRIPTION
        Recomputes profile, required-id coverage, and member binding. A committed
        questionsValid boolean is ignored.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [string]$Member,

        [string]$CatalogMarkdown,

        [string]$ExpectedRunId,

        [string]$ExpectedThread,

        [string]$ExpectedStableRef,

        [string]$ExpectedTrustedBaseSha
    )

    if (-not $Member) {
        return $script:SquadWatchGenericValidationFailure
    }
    $memberRoot = Join-Path $Repository ".copilot-tracking/squad/members/$Member"
    $decisionsPath = Join-Path $memberRoot 'decisions.md'
    $teamPath = Join-Path $memberRoot 'team.md'
    $committedDecisions = if (Test-Path -LiteralPath $decisionsPath -PathType Leaf) { Get-Content -LiteralPath $decisionsPath -Raw } else { '' }
    $committedTeam = if (Test-Path -LiteralPath $teamPath -PathType Leaf) { Get-Content -LiteralPath $teamPath -Raw } else { '' }
    $audit = Join-Path $Repository ".copilot-tracking/squad/watch-audit/$Member/watch-publication.json"
    $memberFile = Join-Path $Repository ".copilot-tracking/squad/members/$Member/watch-publication.json"
    $committed = if (Test-Path -LiteralPath $audit -PathType Leaf) { $audit } else { $memberFile }
    Get-SquadWatchEvidenceQuestionsMarkdown -EvidencePath $committed -CatalogMarkdown $CatalogMarkdown -ExpectedMember $Member -ExpectedRunId $ExpectedRunId -ExpectedThread $ExpectedThread -ExpectedStableRef $ExpectedStableRef -ExpectedTrustedBaseSha $ExpectedTrustedBaseSha -CommittedDecisions $committedDecisions -CommittedTeam $committedTeam
}

function Test-SquadWatchAppliedPublication {
    <#
    .SYNOPSIS
        Revalidates an applied patch from the files it wrote, not from runner copies.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Member,

        [Parameter(Mandatory)]
        [string]$CurrentRunId,

        [string]$CurrentThread = '',

        [string]$CatalogMarkdown = '',

        [string[]]$InstalledPacks = @(),

        [string]$StableRef = '',

        [string]$TrustedBaseSha = ''
    )

    $memberRoot = Join-Path $Repository ".copilot-tracking/squad/members/$Member"
    $decisionsPath = Join-Path $memberRoot 'decisions.md'
    $questionsPath = Join-Path $memberRoot 'watch-questions.json'
    $profileMarkdown = if (Test-Path -LiteralPath $decisionsPath -PathType Leaf) { Get-Content -LiteralPath $decisionsPath -Raw } else { '' }
    $rows = @()
    if (Test-Path -LiteralPath $questionsPath -PathType Leaf) {
        $payload = Get-Content -LiteralPath $questionsPath -Raw | ConvertFrom-Json
        if ($payload.PSObject.Properties.Name -contains 'rows' -and $payload.rows) {
            $rows = @($payload.rows)
        }
    }
    Save-SquadWatchPublicationEvidence -Repository $Repository -Member $Member -CurrentRunId $CurrentRunId -ProfileMarkdown $profileMarkdown -Rows $rows -CurrentThread $CurrentThread -CatalogMarkdown $CatalogMarkdown -InstalledPacks $InstalledPacks -StableRef $StableRef -TrustedBaseSha $TrustedBaseSha
}

function Get-SquadWatchTeamRoster {
    <#
    .SYNOPSIS
        Reads role ids from a team.md table. This is the roster, not the selection block.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()]
        [string]$Markdown
    )

    $roles = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ([string]$Markdown -split "`r?`n")) {
        if ($line -notmatch '^\|\s*(?<role>[a-z0-9-]+)\s*\|') {
            continue
        }
        $role = $Matches['role']
        if ($role -eq 'role' -or $role -match '^-+$') {
            continue
        }
        if (-not $roles.Contains($role)) {
            $roles.Add($role)
        }
    }
    @($roles)
}

function Get-SquadWatchRequiredQuestionId {
    <#
    .SYNOPSIS
        Derives required Open Questions IDs from every current-run risk, council, and assumption record.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()]
        [string]$Markdown,

        [string]$CurrentRunId
    )

    @(Get-SquadWatchRequiredQuestionCoverage -Markdown $Markdown -CurrentRunId $CurrentRunId).Ids
}

function Get-SquadWatchRequiredRole {
    <#
    .SYNOPSIS
        Returns the spine plus council roles independently named as dispatched.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()]
        [string]$Markdown,

        [string]$CurrentRunId
    )

    $roles = [System.Collections.Generic.List[string]]::new()
    foreach ($role in $script:SquadWatchSpine) {
        $roles.Add($role)
    }
    $scoped = Get-SquadWatchCurrentRunMarkdown -Markdown $Markdown -CurrentRunId $CurrentRunId
    $dispatched = [regex]::Matches([string]$scoped, '(?m)^\* Council Members Dispatched:\s*(?<roles>.+)$')
    foreach ($match in $dispatched) {
        foreach ($role in ($match.Groups['roles'].Value -split ',')) {
            $name = $role.Trim().ToLowerInvariant()
            if ($name -match '^[a-z0-9-]+$' -and -not $roles.Contains($name)) {
                $roles.Add($name)
            }
        }
    }
    @($roles)
}

function Export-SquadWatchDispatchAudit {
    <#
    .SYNOPSIS
        Writes dispatch publication evidence to the tracked audit path.
    .DESCRIPTION
        Free-form dispatch member trees stay ignored. The trusted renderer writes only
        watch-publication.json and AUDIT.md under watch-audit, which git can track.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Member,

        [Parameter(Mandatory)]
        $Payload,

        [string]$RenderedMarkdown = ''
    )

    if ($Member -notmatch '^dispatch-[A-Za-z0-9._-]+$') {
        return $null
    }
    $relativeDir = ".copilot-tracking/squad/watch-audit/$Member"
    $dir = Join-Path $Repository ($relativeDir -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $jsonPath = Join-Path $dir 'watch-publication.json'
    $auditPath = Join-Path $dir 'AUDIT.md'
    $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM
    $summary = @(
        '# Watch dispatch audit'
        ''
        "- Member: $Member"
        "- Run: $($Payload.runId)"
        "- Thread: $($Payload.currentThread)"
        ''
        '## Open Questions'
        ''
        $RenderedMarkdown
    ) -join "`n"
    Set-Content -LiteralPath $auditPath -Value ($summary + "`n") -Encoding utf8NoBOM
    [pscustomobject]@{
        Json  = $jsonPath
        Audit = $auditPath
    }
}

function Add-SquadWatchForcedPublicationEvidence {
    <#
    .SYNOPSIS
        Copies dispatch evidence to the tracked audit path. Never force-adds ignored files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Member
    )

    if ($Member -notmatch '^dispatch-[A-Za-z0-9._-]+$') {
        return
    }
    $source = Join-Path $Repository ".copilot-tracking/squad/members/$Member/watch-publication.json"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        return
    }
    $payload = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
    Export-SquadWatchDispatchAudit -Repository $Repository -Member $Member -Payload $payload | Out-Null
}

function Save-SquadWatchPublicationEvidence {
    <#
    .SYNOPSIS
        Validates the current-run profile and question rows, then writes committed recovery evidence.
    .DESCRIPTION
        Invalid profile blocks publication. Invalid question coverage stores no partial cells and
        renders only the generic failure string. The written file is the orphan-recovery input.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Member,

        [Parameter(Mandatory)]
        [string]$CurrentRunId,

        [string]$ProfileMarkdown = '',

        [AllowEmptyCollection()]
        [object[]]$Rows = @(),

        [string]$CurrentThread = '',

        [string[]]$RequiredIds = @(),

        [string]$CatalogMarkdown = '',

        [string[]]$InstalledPacks = @(),

        [string]$StableRef = '',

        [string]$TrustedBaseSha = ''
    )

    if (-not $PSCmdlet.ShouldProcess($Member, 'Write Watch publication evidence')) {
        return
    }

    $memberRootForEvidence = Join-Path $Repository ".copilot-tracking/squad/members/$Member"
    $teamPath = Join-Path $memberRootForEvidence 'team.md'
    $teamMarkdown = if (Test-Path -LiteralPath $teamPath) { Get-Content -LiteralPath $teamPath -Raw } else { '' }
    $roster = @(Get-SquadWatchTeamRoster -Markdown $teamMarkdown)
    $requiredRoles = @(Get-SquadWatchRequiredRole -Markdown $ProfileMarkdown -CurrentRunId $CurrentRunId)
    $coverage = Get-SquadWatchRequiredQuestionCoverage -Markdown $ProfileMarkdown -CurrentRunId $CurrentRunId
    $derivedIds = @($coverage.Ids)
    $coverageIds = @(@($RequiredIds) + $derivedIds | Where-Object { $_ } | Select-Object -Unique)
    $catalogText = Get-SquadWatchCatalogMarkdown -CatalogMarkdown $CatalogMarkdown
    $catalog = Get-SquadWatchProfileCatalog -Markdown $catalogText
    $blocks = @(Get-SquadWatchSelectionBlock -Markdown $ProfileMarkdown)
    $current = @($blocks | Where-Object { $_.RunId -ceq $CurrentRunId })
    $profileName = if ($current.Count -eq 1) { [string]$current[0].Fields['Selected Profile'] } else { '' }
    $selectedPacks = if ($current.Count -eq 1) {
        @(ConvertTo-SquadWatchNameList $current[0].Fields['Selected Packs'] | Where-Object { $_ -and $_ -ne 'none' })
    }
    else {
        @()
    }
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        $resolved = [pscustomobject]@{ Ok = $false; Roles = @(); Reason = 'profile-not-in-catalog' }
    }
    else {
        $resolved = Resolve-SquadWatchCanonicalRoster -Catalog $catalog -ProfileName $profileName -SelectedPacks $selectedPacks -InstalledPacks $InstalledPacks
    }
    $canonicalRoles = if ($resolved.Ok) { @($resolved.Roles) } else { @() }
    $profileResult = Test-SquadWatchProfileSelection `
        -Markdown $ProfileMarkdown `
        -CurrentRunId $CurrentRunId `
        -Roster $roster `
        -RequiredRoles $requiredRoles `
        -InstalledPacks $InstalledPacks `
        -CanonicalProfileRoles $canonicalRoles `
        -KnownProfiles @($catalog.Profiles.Keys)
    $questionRows = @(
        @($Rows) | Where-Object { $_ } | ForEach-Object { ConvertTo-SquadWatchPublicationRow -Row $_ }
    )
    if ($null -eq $questionRows) { $questionRows = [object[]]::new(0) }
    $questions = Test-SquadWatchOpenQuestions -Rows ([object[]]$questionRows) -CurrentThread $CurrentThread -RequiredIds $coverageIds
    if ($coverage.Malformed -or -not $resolved.Ok) {
        $questions = [pscustomobject]@{ Valid = $false; Message = $script:SquadWatchGenericValidationFailure }
    }
    if (-not $resolved.Ok) {
        $profileResult = [pscustomobject]@{ Valid = $false }
    }
    $storedRows = [System.Collections.Generic.List[object]]::new()
    if ($questions.Valid) {
        foreach ($row in @($questionRows)) {
            if ($row) { $storedRows.Add($row) }
        }
    }
    $rendered = if ($questions.Valid) {
        ConvertTo-SquadWatchOpenQuestionsMarkdown -Rows $storedRows.ToArray() -CurrentThread $CurrentThread -RequiredIds $RequiredIds
    }
    else {
        $script:SquadWatchGenericValidationFailure
    }

    $memberRoot = Join-Path $Repository ".copilot-tracking/squad/members/$Member"
    New-Item -ItemType Directory -Path $memberRoot -Force | Out-Null
    $path = Join-Path $memberRoot 'watch-publication.json'
    $payload = [ordered]@{
        member            = $Member
        runId             = $CurrentRunId
        currentThread     = $CurrentThread
        stableRef         = $StableRef
        trustedBaseSha    = $TrustedBaseSha
        profileName       = $profileName
        selectedPacks     = @($selectedPacks)
        installedPacks    = @($InstalledPacks)
        decisionsMarkdown = $ProfileMarkdown
        teamMarkdown      = $teamMarkdown
        profileValid      = [bool]$profileResult.Valid
        questionsValid    = [bool]$questions.Valid
        requiredIds       = @($coverageIds)
        rows              = @($storedRows.ToArray())
    }
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    Export-SquadWatchDispatchAudit -Repository $Repository -Member $Member -Payload $payload -RenderedMarkdown $rendered | Out-Null

    [pscustomobject]@{
        Path             = $path
        ProfileValid     = [bool]$profileResult.Valid
        QuestionsValid   = [bool]$questions.Valid
        BlockPublication = (-not [bool]$profileResult.Valid) -or (-not [bool]$questions.Valid)
        RenderedMarkdown = $rendered
        GenericFailure   = $script:SquadWatchGenericValidationFailure
        ProfileMessage   = $(if ($profileResult.Valid) { 'none' } else { $script:SquadWatchGenericValidationFailure })
        QuestionsMessage = [string]$questions.Message
    }
}
