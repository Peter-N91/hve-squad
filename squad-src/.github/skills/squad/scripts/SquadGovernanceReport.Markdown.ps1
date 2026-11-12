# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

# Dot-sourced by SquadGovernanceReport.psm1. A schema-free Markdown reader and an
# HTML-escaping inline renderer. The governance report renders squad ledgers through
# this layer so a section, table, or column the ledger gains later is displayed with no
# change here: the parser knows Markdown constructs, never ledger field names.

Set-StrictMode -Version Latest

function ConvertTo-SqEscaped {
    <#
    .SYNOPSIS
        HTML-escapes text for element content or a double-quoted attribute value.
    #>
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $clean = [regex]::Replace($Text, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
    $clean.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#39;')
}

$script:SqInlinePattern = [regex]::new(
    '(?<code>(?<tick>`+)(?<c>.+?)\k<tick>)' +
    '|(?<strong>\*\*(?<s>.+?)\*\*)' +
    '|(?<em>(?<![\w*])\*(?<e>[^\s*][^*]*?)\*(?![\w*]))' +
    '|(?<link>\[(?<lt>[^\]]+)\]\((?<lu>[^)\s]+)\))' +
    '|(?<auto><(?<au>https?://[^>\s]+)>)',
    [Text.RegularExpressions.RegexOptions]::Compiled)

function ConvertTo-SqInlineHtml {
    <#
    .SYNOPSIS
        Renders the inline Markdown a ledger uses (code, bold, emphasis) as escaped HTML.
    .DESCRIPTION
        Every character of the source reaches the output through HTML escaping, so
        state content can never inject markup. Links and autolinks are shown as text,
        never as anchors: the report is self-contained and makes no external reference.
    #>
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $builder = [Text.StringBuilder]::new()
    $position = 0
    foreach ($match in $script:SqInlinePattern.Matches($Text)) {
        if ($match.Index -gt $position) {
            [void]$builder.Append((ConvertTo-SqEscaped $Text.Substring($position, $match.Index - $position)))
        }
        if ($match.Groups['code'].Success) {
            [void]$builder.Append('<code>').Append((ConvertTo-SqEscaped $match.Groups['c'].Value.Trim())).Append('</code>')
        }
        elseif ($match.Groups['strong'].Success) {
            [void]$builder.Append('<strong>').Append((ConvertTo-SqInlineHtml $match.Groups['s'].Value)).Append('</strong>')
        }
        elseif ($match.Groups['em'].Success) {
            [void]$builder.Append('<em>').Append((ConvertTo-SqInlineHtml $match.Groups['e'].Value)).Append('</em>')
        }
        elseif ($match.Groups['link'].Success) {
            [void]$builder.Append((ConvertTo-SqEscaped ('{0} ({1})' -f $match.Groups['lt'].Value, $match.Groups['lu'].Value)))
        }
        else {
            [void]$builder.Append((ConvertTo-SqEscaped $match.Groups['au'].Value))
        }
        $position = $match.Index + $match.Length
    }
    if ($position -lt $Text.Length) { [void]$builder.Append((ConvertTo-SqEscaped $Text.Substring($position))) }
    $builder.ToString()
}

function ConvertTo-SqPlainText {
    <#
    .SYNOPSIS
        Strips inline Markdown to the text a reader sees (bold, code and link syntax removed).
    #>
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $plain = [regex]::Replace($Text, '`+(?<c>.+?)`+', '${c}')
    $plain = [regex]::Replace($plain, '\*\*(?<s>.+?)\*\*', '${s}')
    $plain = [regex]::Replace($plain, '(?<![\w*])\*(?<e>[^\s*][^*]*?)\*(?![\w*])', '${e}')
    $plain = [regex]::Replace($plain, '\[(?<t>[^\]]+)\]\([^)\s]+\)', '${t}')
    $plain.Trim()
}

function ConvertTo-SqDecimal {
    <#
    .SYNOPSIS
        Parses a figure as the ledger prints it ("1,234.50", "**0.5255**", "$2.05", "64%", "~74") to a decimal, or $null.
    #>
    [OutputType([System.Nullable[decimal]])]
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $clean = (ConvertTo-SqPlainText $Text).Replace(',', '').Replace('$', '').Replace('~', '').Replace('%', '').Trim()
    if ($clean -eq '' -or $clean -match '^(?i:n/?a|none|unknown|unavailable)$' -or $clean -match '^[—–-]+$') { return $null }
    $value = [decimal]0
    if ([decimal]::TryParse($clean, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
        return $value
    }
    $null
}

function Test-SqTableSeparator {
    param([AllowNull()][string]$Line)
    if ([string]::IsNullOrEmpty($Line) -or $Line -notmatch '-') { return $false }
    $Line -match '^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$' -and $Line -match '\|'
}

function Split-SqTableRow {
    param([Parameter(Mandatory)][string]$Line)
    $text = $Line.Trim()
    if ($text.StartsWith('|')) { $text = $text.Substring(1) }
    if ($text.EndsWith('|') -and -not $text.EndsWith('\|')) { $text = $text.Substring(0, $text.Length - 1) }
    $cells = [regex]::Split($text, '(?<!\\)\|')
    , @($cells | ForEach-Object { $_.Trim().Replace('\|', '|') })
}

function Resize-SqCells {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Cells, [Parameter(Mandatory)][int]$Width)
    $resized = [Collections.Generic.List[string]]::new()
    foreach ($cell in $Cells) { $resized.Add([string]$cell) }
    while ($resized.Count -lt $Width) { $resized.Add('') }
    , $resized.ToArray()
}

function ConvertFrom-SqMarkdown {
    <#
    .SYNOPSIS
        Parses Markdown into an ordered list of blocks without interpreting any field names.
    .DESCRIPTION
        Block types: heading, paragraph, table, code, quote, list. HTML comments, rules,
        and blank lines carry no content and are skipped. Table rows keep every cell
        (a row wider than its header widens the table instead of dropping cells).
    .OUTPUTS
        An object with Frontmatter (ordered key/value map) and Blocks.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Text)

    $lines = @(([string]$Text -replace "`r`n?", "`n").TrimStart([char]0xFEFF) -split "`n")
    $blocks = [Collections.Generic.List[object]]::new()
    $front = [ordered]@{}
    $i = 0
    if ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---') {
        $end = -1
        for ($j = 1; $j -lt $lines.Count; $j++) {
            if ($lines[$j].Trim() -eq '---') { $end = $j; break }
        }
        if ($end -gt 0) {
            for ($j = 1; $j -lt $end; $j++) {
                if ($lines[$j] -match '^(?<k>[A-Za-z0-9_.-]+):\s*(?<v>.*)$') { $front[$Matches.k] = $Matches.v.Trim().Trim('"', "'") }
            }
            $i = $end + 1
        }
    }

    $startsBlock = {
        param([string]$Line, [string]$Next)
        $Line -match '^\s{0,3}(`{3,}|~{3,})' -or $Line -match '^\s{0,3}#{1,6}\s' -or $Line -match '^\s{0,3}>' -or
        $Line -match '^\s*([*+-]|\d+[.)])\s+\S' -or $Line -match '^\s*<!--' -or
        ($Line -match '\|' -and (Test-SqTableSeparator $Next))
    }

    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ($line.Trim() -eq '') { $i++; continue }

        if ($line -match '^\s{0,3}(?<f>`{3,}|~{3,})\s*(?<lang>[^`\s]*)\s*$') {
            $fence = $Matches.f
            $lang = $Matches.lang
            $buffer = [Collections.Generic.List[string]]::new()
            $i++
            while ($i -lt $lines.Count) {
                if ($lines[$i] -match '^\s{0,3}(?<c>`{3,}|~{3,})\s*$' -and $Matches.c[0] -eq $fence[0] -and $Matches.c.Length -ge $fence.Length) { break }
                $buffer.Add($lines[$i])
                $i++
            }
            $i++
            $blocks.Add([pscustomobject]@{ Type = 'code'; Lang = $lang; Text = ($buffer -join "`n") })
            continue
        }

        if ($line -match '^\s*<!--') {
            while ($i -lt $lines.Count -and $lines[$i] -notmatch '-->') { $i++ }
            $i++
            continue
        }

        if ($line -match '^(?<h>#{1,6})\s+(?<t>.+?)\s*#*\s*$') {
            $blocks.Add([pscustomobject]@{ Type = 'heading'; Level = $Matches.h.Length; Text = $Matches.t.Trim() })
            $i++
            continue
        }

        if ($line -match '^\s{0,3}([-*_])(\s*\1){2,}\s*$') { $i++; continue }

        $next = if ($i + 1 -lt $lines.Count) { $lines[$i + 1] } else { $null }
        if ($line -match '\|' -and (Test-SqTableSeparator $next)) {
            $headers = (Split-SqTableRow $line)
            $separator = (Split-SqTableRow $next)
            if ($headers.Count -eq $separator.Count) {
                $align = @(foreach ($cell in $separator) {
                        if ($cell -match '^:-*:$' -and $cell.Length -gt 1) { 'center' }
                        elseif ($cell -match ':$') { 'right' }
                        elseif ($cell -match '^:') { 'left' }
                        else { '' }
                    })
                $rows = [Collections.Generic.List[object]]::new()
                $i += 2
                while ($i -lt $lines.Count -and $lines[$i].Trim() -ne '' -and $lines[$i] -match '\|' -and $lines[$i] -notmatch '^\s{0,3}(`{3,}|~{3,}|#{1,6}\s|>)') {
                    $rows.Add((Split-SqTableRow $lines[$i]))
                    $i++
                }
                $width = $headers.Count
                foreach ($row in $rows) { if ($row.Count -gt $width) { $width = $row.Count } }
                $blocks.Add([pscustomobject]@{
                        Type    = 'table'
                        Headers = (Resize-SqCells $headers $width)
                        Align   = (Resize-SqCells $align $width)
                        Rows    = @(foreach ($row in $rows) { , (Resize-SqCells $row $width) })
                    })
                continue
            }
        }

        if ($line -match '^\s{0,3}>') {
            $quote = [Collections.Generic.List[string]]::new()
            while ($i -lt $lines.Count -and $lines[$i] -match '^\s{0,3}>') {
                $quote.Add(($lines[$i] -replace '^\s{0,3}>\s?', ''))
                $i++
            }
            $paragraphs = [Collections.Generic.List[string]]::new()
            $current = [Collections.Generic.List[string]]::new()
            foreach ($quoted in $quote) {
                if ($quoted.Trim() -eq '') {
                    if ($current.Count -gt 0) { $paragraphs.Add(($current -join ' ')); $current.Clear() }
                }
                else { $current.Add($quoted.Trim()) }
            }
            if ($current.Count -gt 0) { $paragraphs.Add(($current -join ' ')) }
            $blocks.Add([pscustomobject]@{ Type = 'quote'; Paragraphs = $paragraphs.ToArray() })
            continue
        }

        if ($line -match '^(?<ind>\s*)(?<m>[*+-]|\d+[.)])\s+(?<t>\S.*)$') {
            $items = [Collections.Generic.List[object]]::new()
            while ($i -lt $lines.Count) {
                $candidate = $lines[$i]
                if ($candidate -match '^(?<ind>\s*)(?<m>[*+-]|\d+[.)])\s+(?<t>\S.*)$') {
                    $indent = $Matches.ind.Length
                    $marker = $Matches.m
                    $itemText = $Matches.t.Trim()
                    $items.Add([pscustomobject]@{
                            Level   = [int][Math]::Floor($indent / 2)
                            Ordered = ($marker -match '^\d')
                            Text    = $itemText
                        })
                    $i++
                }
                elseif ($candidate -match '^\s{2,}\S' -and $items.Count -gt 0 -and -not (& $startsBlock $candidate $null)) {
                    $items[$items.Count - 1].Text += ' ' + $candidate.Trim()
                    $i++
                }
                else { break }
            }
            $blocks.Add([pscustomobject]@{ Type = 'list'; Items = $items.ToArray() })
            continue
        }

        $paragraph = [Collections.Generic.List[string]]::new()
        while ($i -lt $lines.Count -and $lines[$i].Trim() -ne '') {
            $following = if ($i + 1 -lt $lines.Count) { $lines[$i + 1] } else { $null }
            if ($paragraph.Count -gt 0 -and (& $startsBlock $lines[$i] $following)) { break }
            $paragraph.Add($lines[$i].Trim())
            $i++
        }
        if ($paragraph.Count -gt 0) {
            $blocks.Add([pscustomobject]@{ Type = 'paragraph'; Text = ($paragraph -join ' ') })
        }
    }

    [pscustomobject]@{ Frontmatter = $front; Blocks = $blocks.ToArray() }
}

function Split-SqSections {
    <#
    .SYNOPSIS
        Groups a parsed document's blocks under the heading that precedes them.
    .DESCRIPTION
        Returns one entry per heading, in document order, with its level, title, and the
        blocks up to the next heading. Blocks before the first heading form a level-0 entry.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Document)
    $sections = [Collections.Generic.List[object]]::new()
    $current = [pscustomobject]@{ Level = 0; Title = ''; Blocks = [Collections.Generic.List[object]]::new() }
    foreach ($block in $Document.Blocks) {
        if ($block.Type -eq 'heading') {
            if ($current.Level -gt 0 -or $current.Blocks.Count -gt 0) { $sections.Add($current) }
            $current = [pscustomobject]@{ Level = $block.Level; Title = $block.Text; Blocks = [Collections.Generic.List[object]]::new() }
        }
        else { $current.Blocks.Add($block) }
    }
    if ($current.Level -gt 0 -or $current.Blocks.Count -gt 0) { $sections.Add($current) }
    , $sections.ToArray()
}

function Find-SqColumn {
    <#
    .SYNOPSIS
        Index of the first table header whose plain text matches the pattern, or -1.
    #>
    [OutputType([int])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Headers, [Parameter(Mandatory)][string]$Pattern)
    for ($i = 0; $i -lt $Headers.Count; $i++) {
        if ((ConvertTo-SqPlainText ([string]$Headers[$i])) -match $Pattern) { return $i }
    }
    -1
}

function Get-SqKey {
    <#
    .SYNOPSIS
        Spelling-tolerant key for model and agent names (case, spaces, hyphens and dots ignored).
    #>
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    ([regex]::Replace((ConvertTo-SqPlainText $Text).ToLowerInvariant(), '[^a-z0-9]', ''))
}

function Measure-SqSum {
    <#
    .SYNOPSIS
        Exact decimal sum of the non-null values, or $null when there are none (Measure-Object would widen to double).
    #>
    [OutputType([System.Nullable[decimal]])]
    param([AllowEmptyCollection()][AllowNull()][object[]]$Values)
    $sum = [decimal]0
    $count = 0
    foreach ($value in $Values) {
        if ($null -eq $value) { continue }
        $sum += [decimal]$value
        $count++
    }
    if ($count -eq 0) { return $null }
    $sum
}

function Format-SqNumber {
    <#
    .SYNOPSIS
        Culture-independent number formatting for derived figures.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowNull()]$Value,
        [int]$Decimals = 0,
        [switch]$Grouped
    )
    if ($null -eq $Value) { return 'n/a' }
    $format = if ($Grouped) { "N$Decimals" } else { "F$Decimals" }
    ([decimal]$Value).ToString($format, [Globalization.CultureInfo]::InvariantCulture)
}
