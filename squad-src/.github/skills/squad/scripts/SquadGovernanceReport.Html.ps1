# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

# Dot-sourced by SquadGovernanceReport.psm1. Renders the report model as one self-contained HTML
# file: inline CSS, no JavaScript, no external reference. Every state-derived string passes
# through HTML escaping, and ledger content is rendered from the parsed document verbatim.

Set-StrictMode -Version Latest

$script:SqCss = @'
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background:#f8f9fb;color:#1e293b;line-height:1.6;-webkit-font-smoothing:antialiased}
header{background:linear-gradient(135deg,#1e2a4a,#2d3a6a,#3a4a8a);padding:2.5rem 2rem 2rem}
header .header-inner{max-width:1200px;margin:0 auto}
header h1{font-size:1.75rem;font-weight:700;color:#fff;letter-spacing:-.025em}
header .subtitle{font-size:.9rem;color:rgba(255,255,255,.8);margin-top:.35rem}
header .stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:.75rem;margin-top:1.5rem}
header .stat{text-align:center;padding:.75rem .5rem;background:rgba(255,255,255,.06);border-radius:8px}
header .stat .value{font-size:1.5rem;font-weight:700;color:#fff;line-height:1.2;overflow-wrap:anywhere}
header .stat .label{font-size:.68rem;font-weight:500;color:rgba(255,255,255,.6);text-transform:uppercase;letter-spacing:.05em;margin-top:.2rem}
header .stat .sub{font-size:.66rem;color:rgba(255,255,255,.75);margin-top:.15rem}
header .roi-strip{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:.75rem;margin-top:1rem}
header .roi-chip{padding:.7rem .85rem;background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.18);border-radius:8px}
header .roi-chip .rc-label{font-size:.66rem;text-transform:uppercase;letter-spacing:.05em;color:rgba(255,255,255,.65)}
header .roi-chip .rc-value{font-size:1.25rem;font-weight:700;color:#fff;overflow-wrap:anywhere}
header .roi-chip .rc-sub{font-size:.68rem;color:rgba(255,255,255,.75)}
header .roi-chip.rc-good .rc-value{color:#86efac}
header .roi-chip.rc-bad .rc-value{color:#fca5a5}
header .roi-chip.rc-na .rc-value{color:rgba(255,255,255,.55);font-size:1rem}
.container{max-width:1200px;margin:0 auto;padding:1.5rem 1.25rem 3rem}
.card{background:#fff;border:1px solid #e9edf3;border-radius:12px;padding:1.5rem 1.75rem;margin-bottom:1.25rem;box-shadow:0 1px 3px rgba(0,0,0,.04),0 1px 2px rgba(0,0,0,.02)}
.section-header{font-size:1.1rem;font-weight:700;color:#1e293b;margin-bottom:1.25rem;padding-bottom:.5rem;border-bottom:3px solid transparent;border-image:linear-gradient(90deg,#3b82f6,#8b5cf6) 1}
.section-label{font-size:.7rem;font-weight:600;letter-spacing:.08em;text-transform:uppercase;color:#94a3b8;margin-bottom:.75rem;margin-top:1.5rem}
.section-label:first-child{margin-top:0}
.grid-2{display:grid;gap:1.25rem}
@media (min-width:768px){.grid-2{grid-template-columns:1fr 1fr}}
.grid-4{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:.75rem}
.summary-card{background:#f8fafc;border:1px solid #eef1f6;border-radius:10px;padding:1rem 1.1rem;text-align:center}
.summary-card .value{font-size:1.5rem;font-weight:700;line-height:1.2;color:#334155}
.summary-card .label{font-size:.72rem;font-weight:500;color:#64748b;margin-top:.25rem}
.badge-status{display:inline-block;font-size:.68rem;font-weight:600;padding:.2rem .6rem;border-radius:999px;margin-top:.35rem}
.badge-green{background:#dcfce7;color:#166534}.badge-amber{background:#fef3c7;color:#92400e}.badge-red{background:#fee2e2;color:#991b1b}.badge-gray{background:#f1f5f9;color:#64748b}.badge-blue{background:#dbeafe;color:#1e40af}
.empty-state{text-align:center;font-style:italic;color:#64748b;padding:1rem}
.gate-notes{font-size:.78rem;color:#64748b;margin-top:.9rem}
.donut-container{display:flex;align-items:center;gap:2rem;flex-wrap:wrap;margin-bottom:1.5rem}
.donut{width:140px;height:140px;border-radius:50%;position:relative;flex-shrink:0}
.donut::after{content:'';position:absolute;top:28px;left:28px;width:84px;height:84px;border-radius:50%;background:#fff}
.donut-center{position:absolute;top:0;left:0;width:100%;height:100%;display:flex;align-items:center;justify-content:center;z-index:1;font-size:1.3rem;font-weight:700;color:#334155}
.legend{display:flex;flex-direction:column;gap:.6rem}
.legend-item{display:flex;align-items:center;gap:.6rem;font-size:.85rem;color:#475569}
.legend-dot{width:12px;height:12px;border-radius:4px;flex-shrink:0}
.legend-dot.go{background:#86efac}.legend-dot.cond{background:#fde68a}.legend-dot.stop{background:#fca5a5}
.legend-value{font-weight:600;color:#1e293b;margin-left:auto;padding-left:1rem}
.conditions-counter{display:inline-flex;align-items:center;gap:.5rem;background:#fffbeb;border:1px solid #fde68a;border-radius:8px;padding:.6rem 1rem;font-size:.85rem;color:#92400e;margin-top:1rem}
.table-wrap{overflow-x:auto}
table{width:100%;border-collapse:separate;border-spacing:0;font-size:.82rem}
thead th{background:#f8fafc;font-weight:600;color:#475569;text-align:left;padding:.65rem .75rem;border-bottom:2px solid #e9edf3;font-size:.75rem;text-transform:uppercase;letter-spacing:.04em;white-space:nowrap}
tbody td{padding:.6rem .75rem;border-bottom:1px solid #f1f5f9;color:#334155;vertical-align:top;overflow-wrap:break-word}
tbody tr:hover td{background:#f8fafc}
tbody tr:last-child td{border-bottom:none}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.row-total td{font-weight:700;background:#f0f4ff;border-top:2px solid #e2e8f0;color:#1e293b}
.cost-note,.note{font-size:.75rem;color:#64748b;margin-top:.75rem}
.chip{display:inline-block;font-size:.72rem;font-weight:600;padding:.1rem .5rem;border-radius:999px;white-space:nowrap}
.chip-good{background:#dcfce7;color:#166534}.chip-warn{background:#fef3c7;color:#92400e}.chip-bad{background:#fee2e2;color:#991b1b}.chip-info{background:#dbeafe;color:#1e40af}.chip-muted{background:#f1f5f9;color:#64748b}
.role-badge{display:inline-block;font-size:.72rem;font-weight:600;padding:.2rem .6rem;border-radius:999px;white-space:nowrap}
.tier-auto{background:#dcfce7;color:#166534}.tier-confirm{background:#fef3c7;color:#92400e}.tier-gated{background:#fee2e2;color:#991b1b}.tier-unrecorded{background:#f1f5f9;color:#64748b}
.cost-bars{display:flex;flex-direction:column;gap:.6rem;margin-bottom:1.25rem}
.cost-bar-row{display:flex;align-items:center;gap:.75rem}
.cost-bar-label{font-size:.78rem;color:#475569;width:130px;flex-shrink:0;text-align:right;font-weight:500;overflow-wrap:anywhere}
.cost-bar-track{flex:1;height:24px;background:#f1f5f9;border-radius:6px;overflow:hidden}
.cost-bar-fill{height:100%;border-radius:6px}
.cost-bar-amount{font-size:.78rem;font-weight:600;color:#334155;width:80px}
.dispatch-summary,.outcome-badges{display:flex;flex-wrap:wrap;gap:.75rem;margin-top:1.25rem}
.outcome-badges{margin-top:0;margin-bottom:1.25rem}
.dispatch-badge{display:inline-flex;align-items:center;gap:.4rem;background:#f8fafc;border:1px solid #e9edf3;border-radius:8px;padding:.5rem .85rem;font-size:.8rem;color:#334155}
.dispatch-badge .db-value,.outcome-badge .ob-value{font-weight:700;font-size:.95rem}
.outcome-badge{display:inline-flex;align-items:center;gap:.4rem;padding:.5rem .85rem;border-radius:8px;font-size:.8rem;font-weight:500}
.compliance-list{display:flex;flex-direction:column;gap:.5rem}
.compliance-item{display:flex;align-items:center;justify-content:space-between;gap:1rem;padding:.6rem .85rem;background:#f8fafc;border-radius:8px;border:1px solid #eef1f6;font-size:.82rem}
.compliance-item .status{font-weight:600;font-size:.78rem;white-space:nowrap}
.status-pass{color:#166534}.status-na{color:#64748b}.status-fail{color:#991b1b}
.timeline{position:relative;padding-left:1.75rem}
.timeline::before{content:'';position:absolute;left:7px;top:4px;bottom:4px;width:2px;background:#e2e8f0;border-radius:1px}
.tl-entry{position:relative;padding:.65rem 0 .65rem 1.25rem;margin-left:-1.75rem;padding-left:2.75rem}
.tl-entry::before{content:'';position:absolute;left:1.53rem;top:1rem;width:10px;height:10px;border-radius:50%;background:#60a5fa;border:2px solid #fff;z-index:1}
.tl-time{font-size:.72rem;color:#94a3b8;font-weight:500}
.tl-title{font-size:.85rem;font-weight:600;color:#1e293b;margin-top:.1rem}
.tl-detail{font-size:.78rem;color:#64748b;margin-top:.15rem}
.legend-box{background:#f8fafc;border:1px solid #eef1f6;border-radius:8px;padding:.7rem .9rem;font-size:.76rem;color:#475569;margin-bottom:1rem}
.legend-box ul{list-style:none;display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:.35rem .9rem}
.evidence{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:.75rem;margin-top:.5rem}
.evidence-item{border:1px solid #e9edf3;border-left:4px solid #94a3b8;border-radius:8px;padding:.7rem .9rem;background:#fff}
.evidence-item.ev-shown{border-left-color:#22c55e;background:#f7fef9}.evidence-item.ev-not-shown{border-left-color:#f59e0b;background:#fffdf5}
.evidence-item .ev-title{font-size:.82rem;font-weight:700;color:#1e293b}
.evidence-item .ev-detail{font-size:.78rem;color:#475569;margin-top:.2rem}
.evidence-item .ev-basis{font-size:.68rem;color:#94a3b8;margin-top:.25rem}
details.ledger,details.ledger-sub{border:1px solid #e9edf3;border-radius:10px;margin:.75rem 0;background:#fff}
details.ledger>summary,details.ledger-sub>summary{cursor:pointer;padding:.6rem .9rem;font-weight:600;font-size:.85rem;color:#334155;background:#f8fafc;border-radius:10px}
details.ledger[open]>summary,details.ledger-sub[open]>summary{border-bottom:1px solid #e9edf3;border-radius:10px 10px 0 0}
details.ledger>.ledger-body,details.ledger-sub>.ledger-body{padding:.8rem .9rem}
.ledger-body p{font-size:.82rem;color:#334155;margin:.5rem 0}
.ledger-body ul{margin:.5rem 0 .5rem 1.2rem;font-size:.82rem}
.ledger-body h5{font-size:.8rem;margin:.9rem 0 .3rem;color:#475569}
pre.ledger-code{background:#0f172a;color:#e2e8f0;border-radius:8px;padding:.8rem 1rem;font-size:.74rem;overflow-x:auto;margin:.6rem 0;line-height:1.5}
.ledger-note{border-left:3px solid #cbd5e1;background:#f8fafc;padding:.5rem .8rem;margin:.6rem 0;font-size:.78rem;color:#475569}
.ledger-note p{margin:.25rem 0;font-size:.78rem}
.ledger-body code,td code{background:#f1f5f9;border-radius:4px;padding:0 .25rem;font-size:.92em}
.dq-list{list-style:none;display:flex;flex-direction:column;gap:.4rem}
.dq-list li{font-size:.8rem;padding:.5rem .75rem;border-radius:8px;border:1px solid #eef1f6;background:#f8fafc;color:#334155}
.dq-list li.dq-warn{background:#fffbeb;border-color:#fde68a;color:#92400e}
.dq-list li.dq-info{background:#f8fafc}
.dq-list .dq-tag{font-weight:700;margin-right:.4rem;font-size:.7rem;text-transform:uppercase}
footer{max-width:1200px;margin:0 auto;padding:1.5rem 1.25rem 2rem;font-size:.75rem;color:#94a3b8;border-top:1px solid #e9edf3;overflow-wrap:anywhere}
footer strong{color:#64748b}
'@

$script:SqPalette = @(
    @('#60a5fa', '#3b82f6'), @('#fb923c', '#f97316'), @('#4ade80', '#22c55e'), @('#f87171', '#ef4444'), @('#a78bfa', '#8b5cf6'),
    @('#fbbf24', '#f59e0b'), @('#38bdf8', '#0ea5e9'), @('#f472b6', '#ec4899'), @('#2dd4bf', '#14b8a6'), @('#94a3b8', '#64748b')
)

function Get-SqHashIndex {
    [OutputType([int])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][int]$Modulo)
    [long]$hash = 2166136261
    foreach ($byte in [Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant())) {
        $hash = (($hash -bxor [long]$byte) * 16777619) -band [long]4294967295
    }
    [int]($hash % $Modulo)
}

function Get-SqRoleBadge {
    param([Parameter(Mandatory)][string]$Role)
    $known = @{
        'researcher' = @('#dbeafe', '#1e40af'); 'analyst' = @('#ede9fe', '#5b21b6'); 'lead' = @('#dcfce7', '#166534'); 'coordinator' = @('#dcfce7', '#166534')
        'developer' = @('#ffedd5', '#9a3412'); 'designer' = @('#fce7f3', '#9d174d'); 'scribe' = @('#f1f5f9', '#475569'); 'orchestration' = @('#f1f5f9', '#475569')
    }
    $key = $Role.ToLowerInvariant()
    if ($known.ContainsKey($key)) { $colors = $known[$key] }
    else {
        $hue = (Get-SqHashIndex $key 360)
        $colors = @(('hsl({0},70%,92%)' -f $hue), ('hsl({0},60%,28%)' -f $hue))
    }
    '<span class="role-badge" style="background:{0};color:{1}">{2}</span>' -f $colors[0], $colors[1], (ConvertTo-SqEscaped (Get-SqRoleDisplay $Role))
}

function New-SqBadge {
    param([Parameter(Mandatory)][string]$Text, [ValidateSet('green', 'amber', 'red', 'gray', 'blue')][string]$Kind = 'gray')
    '<span class="badge-status badge-{0}">{1}</span>' -f $Kind, (ConvertTo-SqEscaped $Text)
}

function Get-SqCellChip {
    <#
    .SYNOPSIS
        A chip class for the few cell values whose meaning is a basis or match state; $null for every other cell.
    #>
    param([AllowNull()][string]$Header, [AllowNull()][string]$Plain)
    $value = ([string]$Plain).Trim().ToLowerInvariant()
    if ($value -in 'exact-native', 'host-reported', 'native credits', 'measured') { return 'chip-good' }
    if ($value -in 'estimated', 'tier-default') { return 'chip-warn' }
    if ($value -in 'unresolved', 'unknown', 'unreported', 'unverified') { return 'chip-bad' }
    if ($Header -match '(?i)^match$') {
        if ($value -match '^(yes|match(ed)?|ok|✓|same)') { return 'chip-good' }
        if ($value -match '^(n/a|—|–|-)$') { return 'chip-muted' }
        if ($value) { return 'chip-bad' }
    }
    $null
}

function ConvertTo-SqTableHtml {
    <#
    .SYNOPSIS
        Renders a parsed table verbatim: every header and cell, in order, with numeric columns right-aligned.
    #>
    param([Parameter(Mandatory)]$Table)
    $builder = [Text.StringBuilder]::new()
    $columnCount = @($Table.Headers).Count
    $numeric = [bool[]]::new($columnCount)
    for ($c = 0; $c -lt $columnCount; $c++) {
        $cells = @($Table.Rows | ForEach-Object { (ConvertTo-SqPlainText $_[$c]) } | Where-Object { $_ -ne '' })
        $isNumber = $cells.Count -gt 0
        foreach ($cell in $cells) { if ($cell -notmatch '^[-+~$]?\d[\d,]*(\.\d+)?%?$') { $isNumber = $false; break } }
        $numeric[$c] = ($isNumber -or $Table.Align[$c] -eq 'right')
    }
    [void]$builder.Append('<div class="table-wrap"><table class="ledger-table"><thead><tr>')
    for ($c = 0; $c -lt $columnCount; $c++) {
        [void]$builder.Append($(if ($numeric[$c]) { '<th class="num">' } else { '<th>' })).Append((ConvertTo-SqInlineHtml $Table.Headers[$c])).Append('</th>')
    }
    [void]$builder.Append('</tr></thead><tbody>')
    foreach ($row in $Table.Rows) {
        $isTotal = ((ConvertTo-SqPlainText $row[0]) -match '^(?i)(total|subagents total)$')
        [void]$builder.Append($(if ($isTotal) { '<tr class="row-total">' } else { '<tr>' }))
        for ($c = 0; $c -lt $columnCount; $c++) {
            $plain = ConvertTo-SqPlainText $row[$c]
            $html = ConvertTo-SqInlineHtml $row[$c]
            $chip = Get-SqCellChip -Header (ConvertTo-SqPlainText $Table.Headers[$c]) -Plain $plain
            if ($chip) { $html = '<span class="chip {0}">{1}</span>' -f $chip, $html }
            [void]$builder.Append($(if ($numeric[$c]) { '<td class="num">' } else { '<td>' })).Append($html).Append('</td>')
        }
        [void]$builder.Append('</tr>')
    }
    [void]$builder.Append('</tbody></table></div>')
    $builder.ToString()
}

function ConvertTo-SqBlockHtml {
    param([Parameter(Mandatory)]$Block)
    switch ($Block.Type) {
        'table' { ConvertTo-SqTableHtml $Block }
        'code' { '<pre class="ledger-code"><code>{0}</code></pre>' -f (ConvertTo-SqEscaped $Block.Text) }
        'quote' { '<div class="ledger-note">{0}</div>' -f (($Block.Paragraphs | ForEach-Object { '<p>{0}</p>' -f (ConvertTo-SqInlineHtml $_) }) -join '') }
        'list' { '<ul>{0}</ul>' -f (($Block.Items | ForEach-Object { '<li style="margin-left:{0}rem">{1}</li>' -f ($_.Level * 1.2), (ConvertTo-SqInlineHtml $_.Text) }) -join '') }
        'paragraph' { '<p>{0}</p>' -f (ConvertTo-SqInlineHtml $Block.Text) }
        default { '' }
    }
}

function ConvertTo-SqLedgerHtml {
    <#
    .SYNOPSIS
        Renders every section of a ledger document, in order, with every table, paragraph, list, code block, and note.
    .DESCRIPTION
        Structure comes from the ledger's own headings. A subsection that holds a code block (the
        Derivation) is grouped into a collapsed details element; nothing is omitted from the file.
    #>
    param([Parameter(Mandatory)]$View)
    $builder = [Text.StringBuilder]::new()
    $openMain = $false
    $openSub = $false
    foreach ($section in $View.Sections) {
        if ($section.Level -le 1) {
            if ($openSub) { [void]$builder.Append('</div></details>'); $openSub = $false }
            if ($openMain) { [void]$builder.Append('</div></details>'); $openMain = $false }
            if ($section.Level -eq 1) { [void]$builder.Append('<div class="note ledger-title"><strong>').Append((ConvertTo-SqInlineHtml $section.Title)).Append('</strong></div>') }
            foreach ($block in $section.Blocks) { [void]$builder.Append((ConvertTo-SqBlockHtml $block)) }
            continue
        }
        if ($section.Level -eq 2) {
            if ($openSub) { [void]$builder.Append('</div></details>'); $openSub = $false }
            if ($openMain) { [void]$builder.Append('</div></details>'); $openMain = $false }
            [void]$builder.Append('<details class="ledger" open><summary>').Append((ConvertTo-SqInlineHtml $section.Title)).Append('</summary><div class="ledger-body">')
            $openMain = $true
            foreach ($block in $section.Blocks) { [void]$builder.Append((ConvertTo-SqBlockHtml $block)) }
            continue
        }
        if ($openSub) { [void]$builder.Append('</div></details>'); $openSub = $false }
        if (-not $openMain) {
            [void]$builder.Append('<details class="ledger" open><summary>Ledger</summary><div class="ledger-body">')
            $openMain = $true
        }
        $hasCode = @($section.Blocks | Where-Object Type -eq 'code').Count -gt 0
        [void]$builder.Append($(if ($hasCode) { '<details class="ledger-sub"><summary>' } else { '<details class="ledger-sub" open><summary>' })).Append((ConvertTo-SqInlineHtml $section.Title)).Append('</summary><div class="ledger-body">')
        $openSub = $true
        foreach ($block in $section.Blocks) { [void]$builder.Append((ConvertTo-SqBlockHtml $block)) }
    }
    if ($openSub) { [void]$builder.Append('</div></details>') }
    if ($openMain) { [void]$builder.Append('</div></details>') }
    $builder.ToString()
}

function New-SqSimpleTable {
    <#
    .SYNOPSIS
        A table from pre-rendered HTML cells (callers escape; this only lays out).
    #>
    param([Parameter(Mandatory)][string[]]$Headers, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows, [int[]]$NumericColumns = @(), [int[]]$TotalRows = @())
    $builder = [Text.StringBuilder]::new()
    [void]$builder.Append('<div class="table-wrap"><table><thead><tr>')
    for ($c = 0; $c -lt $Headers.Count; $c++) { [void]$builder.Append($(if ($c -in $NumericColumns) { '<th class="num">' } else { '<th>' })).Append((ConvertTo-SqEscaped $Headers[$c])).Append('</th>') }
    [void]$builder.Append('</tr></thead><tbody>')
    for ($r = 0; $r -lt $Rows.Count; $r++) {
        [void]$builder.Append($(if ($r -in $TotalRows) { '<tr class="row-total">' } else { '<tr>' }))
        for ($c = 0; $c -lt $Headers.Count; $c++) {
            $cell = if ($c -lt $Rows[$r].Count) { [string]$Rows[$r][$c] } else { '' }
            [void]$builder.Append($(if ($c -in $NumericColumns) { '<td class="num">' } else { '<td>' })).Append($cell).Append('</td>')
        }
        [void]$builder.Append('</tr>')
    }
    [void]$builder.Append('</tbody></table></div>')
    $builder.ToString()
}

function Format-SqBasisChip {
    param([AllowNull()][string]$Basis)
    $text = if ($Basis) { $Basis } else { 'unavailable' }
    $class = switch -Regex ($text) {
        '^exact-native$|^host-reported$|^host-billed$' { 'chip-good' }
        '^estimated|^tier-default$|^mixed$' { 'chip-warn' }
        '^unavailable$|^not recorded$' { 'chip-muted' }
        default { 'chip-info' }
    }
    '<span class="chip {0}">{1}</span>' -f $class, (ConvertTo-SqEscaped $text)
}

function ConvertTo-SquadGovernanceHtml {
    <#
    .SYNOPSIS
        Renders the governance report model as a single self-contained HTML document.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model, [string]$Command = '/squad-governance-report')

    $previousCulture = [Globalization.CultureInfo]::CurrentCulture
    [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
    try {
        $e = $Model.Economics
        $g = $Model.Governance
        $meta = $Model.Meta
        $h = $Model.Header
        $sb = [Text.StringBuilder]::new(65536)
        $esc = { param($t) ConvertTo-SqEscaped ([string]$t) }
        $date = { param($d) if ($null -eq $d) { 'n/a' } else { $d.UtcDateTime.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } }
        $scopeLabel = if ($meta.Mode -eq 'federation') { 'Federation' } else { 'Single squad' }
        $spanDays = if ($meta.Period.Days -gt 0) { $meta.Period.Days } elseif ($meta.SpanStart -and $meta.SpanEnd) { [int][Math]::Round(($meta.SpanEnd.UtcDateTime.Date - $meta.SpanStart.UtcDateTime.Date).TotalDays) + 1 } else { 0 }
        $periodText = if ($meta.Period.Name -eq 'all') {
            if ($meta.SpanStart) { "all time: $(& $date $meta.SpanStart) to $(& $date $meta.SpanEnd) ($spanDays day$(if ($spanDays -ne 1) { 's' }))" } else { 'all time (no dated entries)' }
        }
        else { "$(& $date $meta.SpanStart) to $(& $date $meta.SpanEnd) ($($meta.Period.Days) days)" }
        $subtitle = "$scopeLabel · Period: $periodText"
        if ($meta.Squad) { $subtitle += " · Sub-squad: $($meta.Squad)" } elseif ($meta.Multi) { $subtitle += " · Sub-squads: $($meta.Units.Count)" }

        [void]$sb.Append("<!DOCTYPE html>`n<html lang=`"en`">`n<head>`n<meta charset=`"UTF-8`">`n<meta name=`"viewport`" content=`"width=device-width, initial-scale=1.0`">`n")
        [void]$sb.Append("<title>Squad Governance Report — $(& $esc $meta.ProjectName) — $(& $esc $meta.AsOf)</title>`n<style>`n$($script:SqCss)</style>`n</head>`n<body>`n")

        # Header.
        $costValue = if ($null -ne $e.Spend.Usd) { Format-SqUsd $e.Spend.Usd } else { 'No data' }
        $costSub = ''
        if ($e.Spend.Basis -eq 'mixed') { $costSub = (@($e.Spend.ByBasis | ForEach-Object { '{0} {1}' -f $_.Basis, (Format-SqUsd $_.Usd) }) -join ' · ') }
        elseif ($meta.Period.Name -ne 'all' -and $null -ne $e.Spend.Usd) { $costSub = 'cumulative ledger' }
        $tokenPrefix = if ($e.Tokens.Basis -in 'estimated', 'mixed') { '~' } else { '' }
        $tokenValue = if ($null -ne $e.Tokens.Total) { $tokenPrefix + (Format-SqNumber $e.Tokens.Total 0 -Grouped) } else { 'No data' }
        $turnsValue = if ($null -ne $h.Turns) { [string]$h.Turns } else { 'No data' }
        $stat = { param($value, $label, $sub) '<div class="stat"><div class="value">{0}</div><div class="label">{1}</div>{2}</div>' -f (& $esc $value), (& $esc $label), $(if ($sub) { '<div class="sub">' + (& $esc $sub) + '</div>' } else { '' }) }
        [void]$sb.Append('<header><div class="header-inner"><h1>Squad Governance Report</h1><div class="subtitle">').Append((& $esc $subtitle)).Append('</div><div class="stats-grid">')
        [void]$sb.Append((& $stat $turnsValue 'Coordination Turns' '')).Append((& $stat ([string]$h.Dispatches) 'Role Dispatches' ''))
        [void]$sb.Append((& $stat $costValue $h.CostLabel $costSub)).Append((& $stat $tokenValue $h.TokensLabel $(if ($meta.Period.Name -ne 'all' -and $null -ne $e.Tokens.Total) { 'cumulative ledger' } else { '' })))
        [void]$sb.Append((& $stat ([string]$h.Gates) 'Human Gates Fired' '')).Append((& $stat ([string]$h.Escalations) 'Escalations' ''))
        [void]$sb.Append('</div>')

        $roiChip = { param($class, $label, $value, $sub) '<div class="roi-chip {0}"><div class="rc-label">{1}</div><div class="rc-value">{2}</div><div class="rc-sub">{3}</div></div>' -f $class, (& $esc $label), (& $esc $value), (& $esc $sub) }
        [void]$sb.Append('<div class="roi-strip">')
        $spendSub = if ($e.Spend.Basis -eq 'exact-native') { 'exact-native · coordinator and Scribe included' } elseif ($e.Spend.Basis -eq 'unavailable') { 'no recognizable ledger' } else { "$($e.Spend.Basis) · approximate" }
        [void]$sb.Append((& $roiChip $(if ($null -ne $e.Spend.Usd) { '' } else { 'rc-na' }) 'Run spend' $costValue $spendSub))
        if ($e.Rollup) {
            $r = $e.Rollup
            $modelText = if (@($r.Models).Count -gt 0) { "single model: $(@($r.Models) -join ', ')" } else { 'single-model baseline' }
            $good = if ($r.SavingsUsd -gt 0) { 'rc-good' } elseif ($r.SavingsUsd -lt 0) { 'rc-bad' } else { '' }
            [void]$sb.Append((& $roiChip '' 'Without HVE Squad' (Format-SqUsd $r.BaselineUsd) "modeled · $modelText"))
            $direction = if ($r.SavingsUsd -gt 0) { 'lower with HVE Squad' } elseif ($r.SavingsUsd -lt 0) { 'higher with HVE Squad' } else { 'same as the baseline' }
            $differencePct = if ($null -ne $r.SavingsPct) { Format-SqPct ([Math]::Abs([decimal]$r.SavingsPct)) } else { 'n/a' }
            [void]$sb.Append((& $roiChip $good 'Difference' ('{0} ({1})' -f (Format-SqUsd ([Math]::Abs($r.SavingsUsd))), $differencePct) $direction))
            $roiText = Format-SqRoi $r.RoiPct
            $multipleText = if ($null -ne $r.Multiple) { (Format-SqNumber $r.Multiple 2) + '×' } else { 'n/a' }
            [void]$sb.Append((& $roiChip $good 'Run ROI' $roiText ('return on spend · {0} · {1}' -f $multipleText, $r.Kind)))
        }
        else {
            [void]$sb.Append((& $roiChip 'rc-na' 'Without HVE Squad' 'Not recorded' 'the ledger states no comparison'))
            [void]$sb.Append((& $roiChip 'rc-na' 'Run ROI' 'Not derivable' 'needs a with and a without figure'))
        }
        if ($e.Value -and $null -ne $e.Value.CostPerAcceptedUsd) {
            [void]$sb.Append((& $roiChip '' 'Per accepted deliverable' (Format-SqUsd $e.Value.CostPerAcceptedUsd) ("{0} · {1} accepted" -f $e.Value.CostPerAcceptedLabel, (Format-SqNumber $e.Value.Accepted 0))))
        }
        else { [void]$sb.Append((& $roiChip 'rc-na' 'Per accepted deliverable' 'Not recorded' 'no accepted-value measure in the ledger')) }
        [void]$sb.Append('</div></div></header>')
        [void]$sb.Append('<div class="container">')

        # Scope and provenance.
        [void]$sb.Append('<div class="card"><p class="section-label">Scope and provenance</p>')
        $scopeRows = [Collections.Generic.List[object]]::new()
        foreach ($unit in $Model.Units) {
            $spend = $e.Spends | Where-Object Unit -eq $unit.Name | Select-Object -First 1
            $trigger = if ($unit.Trigger) { ('{0} {1}{2}' -f $unit.Trigger['source'], $unit.Trigger['ref'], $(if ($unit.Trigger['actor']) { " by $($unit.Trigger['actor'])" } else { '' })).Trim() } else { '—' }
            $scopeRows.Add(@(
                    (& $esc $unit.Name), (& $esc $trigger),
                    $(if ($unit.Ledger.Present) { & $esc $unit.Ledger.RunId } else { '<span class="chip chip-muted">no ledger</span>' }),
                    $(if ($spend) { Format-SqBasisChip $spend.Basis } else { Format-SqBasisChip 'unavailable' }),
                    $(if ($spend -and $null -ne $spend.Usd) { & $esc (Format-SqUsd $spend.Usd) } else { 'n/a' }),
                    $(if ($spend -and $null -ne $spend.Tokens) { & $esc (Format-SqNumber $spend.Tokens 0 -Grouped) } else { 'n/a' }),
                    $(if ($spend -and $spend.AsOf) { & $esc $spend.AsOf } else { '—' })
                ))
        }
        [void]$sb.Append((New-SqSimpleTable -Headers @('Squad', 'Trigger', 'Ledger run', 'Basis', 'Cost (USD)', 'Tokens', 'Ledger as of') -Rows $scopeRows.ToArray() -NumericColumns @(4, 5)))
        if ($Model.RootUnit) { [void]$sb.Append('<p class="note">Federation root state (decisions, meta-run summaries) is included for verdicts and gates. The federation root has no consumption ledger of its own; coordinator overhead appears only in each sub-squad ledger.</p>') }
        if ($meta.Period.Name -ne 'all') { [void]$sb.Append('<p class="note">Period filter applies to dated entries (dispatches, verdicts, gates, timeline). Ledger totals are cumulative for the whole run and are labeled as such.</p>') }
        [void]$sb.Append('</div>')

        # Section 1.
        [void]$sb.Append('<div class="card" id="s1"><div class="section-header">1. Governance Gates</div><div class="grid-4">')
        $gateCard = { param($value, $label, $badge) '<div class="summary-card"><div class="value">{0}</div><div class="label">{1}</div>{2}</div>' -f (& $esc $value), (& $esc $label), $badge }
        [void]$sb.Append((& $gateCard $g.CouncilCount 'Council Verdicts' $(if ($g.CouncilCount -eq 0) { New-SqBadge 'Not activated' 'gray' } else { '' })))
        [void]$sb.Append((& $gateCard $g.IntakeCount 'Intake Readiness Checks' $(if ($g.IntakeCount -eq 0) { New-SqBadge 'Not activated' 'gray' } else { '' })))
        $gateBadge = if ($g.GateLog.Count -eq 0) { New-SqBadge 'Not activated' 'gray' } elseif ($g.GatesBlocked -gt 0) { New-SqBadge "$($g.GatesBlocked) blocked" 'red' } elseif ($g.GatesPending -gt 0) { New-SqBadge "$($g.GatesPending) pending" 'amber' } else { New-SqBadge 'All passed' 'green' }
        [void]$sb.Append((& $gateCard "$($g.GatesPassed) / $($g.GateLog.Count)" 'Human Gates Passed' $gateBadge))
        [void]$sb.Append((& $gateCard $h.Escalations 'Escalations' $(if ($h.Escalations -eq 0) { New-SqBadge 'None' 'green' } else { New-SqBadge "$($h.Escalations) recorded" 'amber' })))
        [void]$sb.Append('</div>')
        $noteParts = @("Discovery sessions: $($g.DiscoveryCount)$(if ($g.DiscoveryCount -eq 0) { ' (Not activated)' })", "Discovery offers declined: $($g.DiscoveryDeclined)", "Council waivers: $($g.Waivers)")
        if (@($g.Preflights).Count -gt 0) { $noteParts += "Cost preflight rounds: $(@($g.Preflights).Count)" }
        [void]$sb.Append('<p class="gate-notes">').Append((& $esc ($noteParts -join ' · '))).Append('</p>')
        if ($g.GateLog.Count -gt 0) {
            [void]$sb.Append('<p class="section-label">Human Gate Log</p>')
            $gateRows = @(foreach ($gate in $g.GateLog) {
                    $statusHtml = switch ($gate.Status) { 'passed' { '<span style="color:#166534;font-weight:600">✓ PASSED</span>' } 'blocked' { '<span style="color:#991b1b;font-weight:600">✗ BLOCKED</span>' } default { '<span style="color:#92400e;font-weight:600">… PENDING</span>' } }
                    , @($(if ($null -ne $gate.Turn) { [string]$gate.Turn } else { '—' }), $(if ($gate.Timestamp) { & $date $gate.Timestamp } else { '—' }), (& $esc $gate.Type), (& $esc $gate.Action), $statusHtml)
                })
            [void]$sb.Append((New-SqSimpleTable -Headers @('Turn', 'Date', 'Gate Type', 'Action', 'Status') -Rows $gateRows))
        }
        [void]$sb.Append('</div>')

        # Section 2.
        [void]$sb.Append('<div class="card" id="s2"><div class="section-header">2. Council Verdicts</div>')
        if ($g.CouncilCount -gt 0) {
            $total = $g.CouncilCount
            $vc = $g.VerdictCounts
            $goDeg = [Math]::Round(360.0 * $vc['Go'] / $total, 2); $condDeg = [Math]::Round(360.0 * $vc['Go-With-Conditions'] / $total, 2)
            $inv = [Globalization.CultureInfo]::InvariantCulture
            $gradient = 'conic-gradient(#86efac 0deg {0}deg, #fde68a {0}deg {1}deg, #fca5a5 {1}deg 360deg)' -f $goDeg.ToString($inv), ($goDeg + $condDeg).ToString($inv)
            [void]$sb.Append('<div class="donut-container"><div class="donut" style="background:').Append($gradient).Append('"><div class="donut-center">').Append($total).Append('</div></div><div class="legend">')
            foreach ($pair in @(@('go', 'Go', 'Go'), @('cond', 'Go-With-Conditions', 'Go-With-Conditions'), @('stop', 'Stop', 'Stop'))) {
                $count = $vc[$pair[2]]
                $pct = [Math]::Round([decimal](100.0 * $count / $total), 0, [MidpointRounding]::AwayFromZero)
                [void]$sb.Append('<div class="legend-item"><span class="legend-dot ').Append($pair[0]).Append('"></span>').Append((& $esc $pair[1])).Append('<span class="legend-value">').Append("$count ($($pct.ToString($inv))%)").Append('</span></div>')
            }
            [void]$sb.Append('</div></div>')
            if (@($g.Findings).Count -gt 0) {
                [void]$sb.Append('<p class="section-label">Findings by Role</p>')
                $findingRows = @(foreach ($f in ($g.Findings | Sort-Object Role)) { , @((& $esc $f.Role), [string]$f.Approve, [string]$f.Conditional, [string]$f.Concern, [string]$f.Block, [string]$f.High) })
                [void]$sb.Append((New-SqSimpleTable -Headers @('Role', 'Approve', 'Conditional', 'Concern', 'Block', 'Risk: High') -Rows $findingRows -NumericColumns @(1, 2, 3, 4, 5)))
            }
            [void]$sb.Append('<div class="conditions-counter"><strong>').Append($g.Outstanding).Append('</strong> conditions outstanding (latest verdict per topic)</div>')
        }
        else {
            [void]$sb.Append('<p class="empty-state">No council reviews were triggered during this period. The squad operated in interactive mode with direct user approval gates.</p>')
        }
        [void]$sb.Append('</div>')

        # Section 3.
        [void]$sb.Append('<div class="card" id="s3"><div class="section-header">3. Cost Breakdown</div>')
        [void]$sb.Append('<div class="legend-box"><strong>How to read these figures.</strong> Each figure carries its basis and bases are never added silently.<ul>')
        [void]$sb.Append('<li><span class="chip chip-good">exact-native</span> host-reported native usage records, priced by the host (1 AI credit = $0.01).</li>')
        [void]$sb.Append('<li><span class="chip chip-warn">estimated</span> dispatch-size estimator × per-model rates × calibration; approximate.</li>')
        [void]$sb.Append('<li><span class="chip chip-info">modeled</span> a counterfactual or blended-price figure computed from token counts; not a bill.</li>')
        [void]$sb.Append('<li><span class="chip chip-good">host-billed</span> whole-session AI units the host reported, coordinator included.</li></ul></div>')

        [void]$sb.Append('<p class="section-label">Run economics and ROI</p>')
        $roiRows = [Collections.Generic.List[object]]::new()
        $na = '<span class="chip chip-muted">not recorded</span>'
        $roiRows.Add(@('HVE Squad spend', $(if ($null -ne $e.Spend.Usd) { (& $esc (Format-SqUsd $e.Spend.Usd)) + $(if ($null -ne $e.Spend.Credits) { ' <span class="note">(' + (& $esc (Format-SqNumber $e.Spend.Credits 2 -Grouped)) + ' AI credits)</span>' } else { '' }) } else { $na }), (Format-SqBasisChip $e.Spend.Basis), 'Ledger Usage &amp; Cost total (all roles plus coordinator and Scribe overhead)'))
        if ($e.Spend.Basis -eq 'mixed') {
            foreach ($b in $e.Spend.ByBasis) { $roiRows.Add(@(('&nbsp;&nbsp;of which ' + (& $esc $b.Basis)), (& $esc (Format-SqUsd $b.Usd)), (Format-SqBasisChip $b.Basis), ("$($b.Units) ledger(s)"))) }
        }
        if ($e.Rollup) {
            $r = $e.Rollup
            $roiRows.Add(@('Without HVE Squad', (& $esc (Format-SqUsd $r.BaselineUsd)), (Format-SqBasisChip "modeled ($($r.Kind))"), $(if (@($r.Models).Count -gt 0) { 'Same work on one model: ' + (& $esc (@($r.Models) -join ', ')) } else { 'Manual single-model baseline stated by the ledger' })))
            $roiRows.Add(@('Avoided cost', (& $esc (Format-SqUsd $r.SavingsUsd)), (Format-SqBasisChip 'derived'), 'Without HVE Squad − HVE Squad spend'))
            $roiRows.Add(@('Cost reduction', (& $esc (Format-SqPct $r.SavingsPct)), (Format-SqBasisChip 'derived'), 'Avoided cost ÷ Without HVE Squad'))
            $roiRows.Add(@('Run ROI', (& $esc (Format-SqPct $r.RoiPct)), (Format-SqBasisChip 'derived'), 'Avoided cost ÷ HVE Squad spend (return per dollar spent)'))
            $roiRows.Add(@('Cost multiple', (& $esc $(if ($null -ne $r.Multiple) { (Format-SqNumber $r.Multiple 2) + '×' } else { 'n/a' })), (Format-SqBasisChip 'derived'), 'Without HVE Squad ÷ HVE Squad spend'))
            if ($r.Covered -lt $r.Units) { $roiRows.Add(@('Comparison coverage', "$($r.Covered) of $($r.Units) ledgers", (Format-SqBasisChip 'derived'), 'Only ledgers that state both a with and a without figure are included in the comparison totals')) }
        }
        else { $roiRows.Add(@('Without HVE Squad and ROI', $na, (Format-SqBasisChip 'unavailable'), 'No ledger states both a with and a without HVE Squad figure; nothing is estimated in its place')) }
        if ($e.Value) {
            $v = $e.Value
            $roiRows.Add(@('Accepted / produced deliverables', (& $esc ("$(Format-SqNumber $v.Accepted 0) / $(Format-SqNumber $v.Produced 0)")), (Format-SqBasisChip 'derived'), 'Unit Economics (value): accepted only after an independent review'))
            $roiRows.Add(@('First-pass yield', $(if ($null -ne $v.FirstPassYieldPct) { & $esc (Format-SqPct $v.FirstPassYieldPct) } else { $na }), (Format-SqBasisChip 'derived'), 'Share of accepted deliverables with no rework'))
            $roiRows.Add(@('Cost per accepted deliverable', $(if ($null -ne $v.CostPerAcceptedUsd) { & $esc (Format-SqUsd $v.CostPerAcceptedUsd) } else { $na }), (Format-SqBasisChip $(if ($v.CostPerAcceptedLabel) { $v.CostPerAcceptedLabel } else { 'unavailable' })), 'Spend ÷ accepted deliverables'))
        }
        else { $roiRows.Add(@('Unit Economics (value)', $na, (Format-SqBasisChip 'unavailable'), 'The ledger has no Unit Economics section; no value measure is shown')) }
        $roiRows.Add(@('Orchestration share of spend', $(if ($null -ne $e.OrchestrationSharePct) { & $esc (Format-SqPct $e.OrchestrationSharePct) } else { $na }), (Format-SqBasisChip 'derived'), 'Coordinator and Scribe row ÷ total'))
        $roiRows.Add(@('Prompt-cache share of input-side tokens', $(if ($null -ne $e.CacheReadSharePct) { & $esc (Format-SqPct $e.CacheReadSharePct) } else { $na }), (Format-SqBasisChip 'derived'), 'Cached ÷ (input + cached + cache write)'))
        [void]$sb.Append((New-SqSimpleTable -Headers @('Measure', 'Value', 'Basis', 'Derivation') -Rows $roiRows.ToArray()))
        [void]$sb.Append('<p class="note">ROI = (Without HVE Squad − HVE Squad) ÷ HVE Squad. The without-HVE-Squad figure is a modeled counterfactual that holds the work constant on one model; it is not an observed alternate run and a negative value is shown as negative.</p>')

        # Figures by basis.
        $basisRows = [Collections.Generic.List[object]]::new()
        foreach ($b in $e.Spend.ByBasis) { $basisRows.Add(@('Ledger total', (& $esc (Format-SqUsd $b.Usd)), (Format-SqBasisChip $b.Basis), "$($b.Units) ledger(s); includes orchestration; cumulative")) }
        if ($e.HostBilled.Sessions.Count -gt 0) {
            $hb = $e.HostBilled
            if ($hb.Unscoped -gt 1) { foreach ($s in $hb.Sessions) { $basisRows.Add(@("Host-reported whole-session billed ($(& $esc $s.Unit))", (& $esc ((Format-SqNumber $s.Credits 2 -Grouped) + ' AI credits')), (Format-SqBasisChip 'host-billed'), 'Whole session, coordinator included; no session id, so not combined')) } }
            else { $basisRows.Add(@('Host-reported whole-session billed', (& $esc ((Format-SqNumber $hb.Credits 2 -Grouped) + ' AI credits' + $(if ($null -ne $hb.Usd) { " ($(Format-SqUsd $hb.Usd 2))" } else { '' }))), (Format-SqBasisChip 'host-billed'), "Whole session, coordinator included; $($hb.Sessions.Count) distinct session(s), each counted once")) }
        }
        foreach ($unit in $Model.Units) {
            $o = $unit.Ledger.Observed
            if ($unit.Ledger.Present -and $o -and $null -ne $o.SubagentTokens) {
                $basisRows.Add(@("Observed subagent tokens ($(& $esc $unit.Name))", (& $esc ((Format-SqNumber $o.SubagentTokens 0 -Grouped) + ' tokens')), (Format-SqBasisChip 'host-reported'), "Subagents only, coordinator excluded; estimated tokens $(& $esc (Format-SqNumber $o.EstimatedTokens 0 -Grouped)); blended USD $(& $esc (Format-SqUsd $o.BlendedUsd)) is modeled, not billed"))
            }
        }
        if ($basisRows.Count -gt 0) {
            [void]$sb.Append('<p class="section-label">Figures by basis (not added together)</p>')
            [void]$sb.Append((New-SqSimpleTable -Headers @('Figure', 'Value', 'Basis', 'Scope') -Rows $basisRows.ToArray()))
        }
        if ($e.Comparisons.Count -gt 0) {
            [void]$sb.Append('<p class="section-label">Comparisons stated by the ledgers</p>')
            $cmpRows = @(foreach ($c in $e.Comparisons) {
                    $cmp = $c.Comparison
                    $math = $c.Math
                    , @((& $esc $c.Unit), (Format-SqBasisChip $cmp.Kind), $(if ($null -ne $cmp.SquadUsd) { & $esc (Format-SqUsd $cmp.SquadUsd) } else { 'n/a' }), $(if ($null -ne $cmp.BaselineUsd) { & $esc (Format-SqUsd $cmp.BaselineUsd) } else { 'n/a' }),
                        (& $esc $(if ($cmp.BaselineModel) { $cmp.BaselineModel } else { '—' })), $(if ($math) { & $esc (Format-SqUsd $math.SavingsUsd) } else { 'n/a' }),
                        $(if ($math) { & $esc (Format-SqPct $math.SavingsPct) } else { 'n/a' }), $(if ($null -ne $cmp.StatedPct) { & $esc ("$(Format-SqPct $cmp.StatedPct) $($cmp.StatedDirection)") } else { '—' }),
                        $(if ($math -and $null -ne $math.RoiPct) { & $esc (Format-SqPct $math.RoiPct 0) } else { 'n/a' }))
                })
            [void]$sb.Append((New-SqSimpleTable -Headers @('Squad', 'Kind', 'With HVE Squad', 'Without', 'Baseline model', 'Saving', 'Saving %', 'Ledger states', 'ROI') -Rows $cmpRows -NumericColumns @(2, 3, 5, 6, 8)))
        }

        # Why HVE Squad: cost evidence.
        $renderEvidence = {
            param($items)
            $out = [Text.StringBuilder]::new()
            [void]$out.Append('<div class="evidence">')
            foreach ($item in $items) {
                $mark = switch ($item.State) { 'shown' { '✓ ' } 'not-shown' { '△ ' } default { '– ' } }
                [void]$out.Append('<div class="evidence-item ev-').Append($item.State).Append('"><div class="ev-title">').Append($mark).Append((& $esc $item.Title)).Append('</div><div class="ev-detail">').Append((& $esc $item.Detail)).Append('</div><div class="ev-basis">basis: ').Append((& $esc $item.Basis)).Append('</div></div>')
            }
            [void]$out.Append('</div>')
            $out.ToString()
        }
        [void]$sb.Append('<p class="section-label">Why HVE Squad: what this run spent</p>')
        [void]$sb.Append((& $renderEvidence $Model.Justifications.Cost))

        # Cost by role.
        $roleBasis = switch ($e.Spend.Basis) { 'exact-native' { 'exact-native' } 'estimated' { 'estimated' } 'mixed' { 'mixed basis' } default { 'no data' } }
        [void]$sb.Append("<p class=`"section-label`">Cost by Role ($(& $esc $roleBasis))</p>")
        $roleCosts = @($e.ByRole | Where-Object { $null -ne $_.Usd } | Sort-Object @{ Expression = { $_.Usd }; Descending = $true }, @{ Expression = { $_.Role } })
        if ($roleCosts.Count -gt 0) {
            $max = [decimal]($roleCosts | ForEach-Object { $_.Usd } | Measure-Object -Maximum).Maximum
            [void]$sb.Append('<div class="cost-bars">')
            foreach ($role in $roleCosts) {
                $width = if ($max -gt 0) { [Math]::Round([decimal](100 * $role.Usd / $max), 1) } else { 0 }
                $pair = $script:SqPalette[(Get-SqHashIndex $role.Role $script:SqPalette.Count)]
                [void]$sb.Append('<div class="cost-bar-row"><span class="cost-bar-label">').Append((& $esc (Get-SqRoleDisplay $role.Role))).Append('</span><div class="cost-bar-track"><div class="cost-bar-fill" style="width:').Append($width.ToString([Globalization.CultureInfo]::InvariantCulture)).Append("%;background:linear-gradient(90deg,$($pair[0]),$($pair[1]))`"></div></div><span class=`"cost-bar-amount`">").Append((& $esc (Format-SqUsd $role.Usd))).Append('</span></div>')
            }
            [void]$sb.Append('</div>')
        }
        else { [void]$sb.Append('<p class="empty-state">No cost data: the ledger states no per-role cost.</p>') }

        # Cost by model and tier.
        if ($e.ByModel.Count -gt 0) {
            [void]$sb.Append('<p class="section-label">Cost by Model Tier</p>')
            $modelRows = @(foreach ($m in ($e.ByModel | Sort-Object @{ Expression = { if ($null -ne $_.Tokens) { $_.Tokens } else { 0 } }; Descending = $true }, @{ Expression = { $_.Key } })) {
                    , @((& $esc $m.Key), (& $esc (@($m.Roles) -join ', ')), (& $esc (@($m.PricedAs) -join ', ')), $(if ($null -ne $m.Usd) { & $esc (Format-SqUsd $m.Usd) } else { 'n/a' }), $(if ($null -ne $m.Tokens -and $null -ne $e.Tokens.Total) { & $esc (Format-SqPct (Get-SqPercent $m.Tokens $e.Tokens.Total)) } else { 'n/a' }))
                })
            [void]$sb.Append((New-SqSimpleTable -Headers @('Model', 'Role Usage', 'Priced as', 'Cost (USD)', 'Token Share') -Rows $modelRows -NumericColumns @(3, 4)))
            if ($e.ByTier.Count -gt 0) {
                $tierRows = @(foreach ($t in ($e.ByTier | Sort-Object { $_.Key })) {
                        , @((& $esc $t.Key), (& $esc (@($t.Roles) -join ', ')), $(if ($null -ne $t.Usd) { & $esc (Format-SqUsd $t.Usd) } else { 'n/a' }), $(if ($null -ne $t.Tokens -and $null -ne $e.Tokens.Total) { & $esc (Format-SqPct (Get-SqPercent $t.Tokens $e.Tokens.Total)) } else { 'n/a' }))
                    })
                [void]$sb.Append('<p class="section-label">Cost by tier</p>')
                [void]$sb.Append((New-SqSimpleTable -Headers @('Tier', 'Role Usage', 'Cost (USD)', 'Token Share') -Rows $tierRows -NumericColumns @(2, 3)))
            }
        }
        [void]$sb.Append('<p class="section-label">Per-Turn Cost Trend</p><p class="note">Omitted: no ledger records cost per turn, and a per-turn figure the ledger cannot reproduce is never shown. Totals above are cumulative for the run.</p>')

        # Consumption ledger detail.
        [void]$sb.Append('<p class="section-label">Consumption ledger: complete detail</p>')
        foreach ($unit in $Model.Units) {
            $label = if ($Model.Units.Count -gt 1 -or $meta.Squad) { "Ledger: $($unit.Name)" } else { 'Ledger' }
            if (-not $unit.Ledger.Present) {
                [void]$sb.Append('<details class="ledger" open><summary>').Append((& $esc $label)).Append('</summary><div class="ledger-body"><p>No <code>consumption.md</code> was found for this squad. Cost, token, observed-usage and ROI figures are unavailable; nothing is estimated in their place.</p></div></details>')
                continue
            }
            if ($Model.Units.Count -gt 1 -or $meta.Squad) { [void]$sb.Append('<details class="ledger" open><summary>').Append((& $esc $label)).Append(' — ').Append((Format-SqBasisChip $(if ($unit.Ledger.Usage) { $unit.Ledger.Usage.Basis } else { 'unavailable' }))).Append('</summary><div class="ledger-body">') }
            [void]$sb.Append((ConvertTo-SqLedgerHtml -View $unit.Ledger))
            $o = $unit.Ledger.Observed
            if (-not $o) {
                [void]$sb.Append('<div class="ledger-note"><p><strong>Observed Usage (host-reported):</strong> not recorded in this ledger. ')
                [void]$sb.Append($(if ($unit.Ledger.Usage -and $unit.Ledger.Usage.Basis -eq 'exact-native') { 'An exact-native ledger folds host-reported usage into its main tables, so there is no separate section. ' } else { 'This ledger is estimate-only, so no host telemetry, token split, billing value or model identity is shown. ' }))
                [void]$sb.Append('Nothing is substituted.</p></div>')
            }
            if ($unit.Journal -and $unit.Journal.Valid -and @($unit.Journal.Sessions).Count -gt 0) {
                $sessionRows = @(foreach ($s in $unit.Journal.Sessions) {
                        $credits = $s.NanoAiu / [decimal]1e9
                        , @((& $esc $s.SessionId), (& $esc $s.First), (& $esc $s.Through), (& $esc ([string]$s.Records)), (& $esc ([string]$s.Roles)), (& $esc ([string]$s.Requests)), (& $esc (Format-SqNumber $credits 2 -Grouped)), (& $esc $s.Digest.Substring(0, [Math]::Min(12, $s.Digest.Length))))
                    })
                [void]$sb.Append('<details class="ledger-sub"><summary>Native sessions behind this ledger (consumption-sessions.json)</summary><div class="ledger-body">')
                [void]$sb.Append((New-SqSimpleTable -Headers @('Session', 'First record', 'Through', 'Records', 'Roles', 'Requests', 'Credits', 'Digest') -Rows $sessionRows -NumericColumns @(3, 4, 5, 6)))
                [void]$sb.Append('</div></details>')
            }
            elseif ($unit.Journal -and -not $unit.Journal.Valid) {
                [void]$sb.Append('<div class="ledger-note"><p>consumption-sessions.json could not be read (').Append((& $esc $unit.Journal.Error)).Append('); native session provenance is unavailable.</p></div>')
            }
            if ($unit.Rates) {
                $rates = $unit.Rates
                [void]$sb.Append('<details class="ledger-sub"><summary>Methodology: rates, observation date, calibration</summary><div class="ledger-body">')
                $calibration = $rates.Calibration
                $factor = if ($calibration.Contains('calibration_factor')) { $calibration['calibration_factor'] } else { 'not recorded' }
                $observedRuns = if ($calibration.Contains('observations')) { $calibration['observations'] } else { 'not recorded' }
                $reconciled = if ($calibration.Contains('last_reconciled')) { $calibration['last_reconciled'] } else { 'not recorded' }
                $methodRows = @(
                    , @('Rates observed on', $(if ($rates.ObservedOn) { & $esc $rates.ObservedOn } else { '<span class="chip chip-muted">not recorded (placeholder)</span>' }))
                    , @('Billing model', $(if ($rates.Billing) { & $esc $rates.Billing } else { 'not recorded' }))
                    , @('Credit conversion', $(if ($rates.CreditConversion) { & $esc $rates.CreditConversion } else { 'not recorded' }))
                    , @('Calibration factor', (& $esc ([string]$factor)))
                    , @('Reconciled runs (observations)', (& $esc ([string]$observedRuns)))
                    , @('Last reconciled', (& $esc ([string]$reconciled)))
                )
                [void]$sb.Append((New-SqSimpleTable -Headers @('Setting', 'Value') -Rows $methodRows))
                if ($rates.RateTable) {
                    $wanted = [Collections.Generic.HashSet[string]]::new()
                    foreach ($pair in (Join-SqAttributionToUsage -View $unit.Ledger)) {
                        if ($null -eq $pair.Attribution) { continue }
                        foreach ($name in @(@($pair.Attribution.Model, $pair.Attribution.PricedAs) | Where-Object { $_ } | ForEach-Object { $_ -split '\s*,\s*' })) { [void]$wanted.Add((Get-SqKey $name)) }
                    }
                    $subset = @($rates.RateTable.Rows | Where-Object { $wanted.Contains((Get-SqKey $_[0])) -or ($rates.RateTable.Headers.Count -gt 1 -and $wanted.Contains((Get-SqKey $_[1]))) })
                    if ($subset.Count -gt 0) {
                        [void]$sb.Append('<p class="note">Per-model token rates in USD per 1M tokens, for the models this ledger used:</p>')
                        [void]$sb.Append((ConvertTo-SqTableHtml ([pscustomobject]@{ Headers = $rates.RateTable.Headers; Align = $rates.RateTable.Align; Rows = $subset })))
                    }
                }
                [void]$sb.Append('</div></details>')
            }
            if ($Model.Units.Count -gt 1 -or $meta.Squad) { [void]$sb.Append('</div></details>') }
        }

        # Data quality.
        [void]$sb.Append('<p class="section-label">Data quality and reading notes</p>')
        if ($Model.Quality.Count -eq 0) { [void]$sb.Append('<p class="note">No inconsistency, unresolved identity, or fallback pricing was detected in the ledgers read.</p>') }
        else {
            [void]$sb.Append('<ul class="dq-list">')
            foreach ($q in ($Model.Quality | Sort-Object @{ Expression = { if ($_.Severity -eq 'warn') { 0 } else { 1 } } }, @{ Expression = { $_.Unit } }, @{ Expression = { $_.Code } }, @{ Expression = { $_.Message } })) {
                $prefix = if ($q.Unit) { "[$($q.Unit)] " } else { '' }
                [void]$sb.Append('<li class="dq-').Append($q.Severity).Append('"><span class="dq-tag">').Append($(if ($q.Severity -eq 'warn') { 'warning' } else { 'note' })).Append('</span>').Append((& $esc ($prefix + $q.Message))).Append('</li>')
            }
            [void]$sb.Append('</ul>')
        }
        [void]$sb.Append('</div>')

        # Section 4.
        $d = $Model.Dispatch
        [void]$sb.Append('<div class="card" id="s4"><div class="section-header">4. Role Dispatch Activity</div>')
        if ($d.Rows.Count -gt 0) {
            $dispatchRows = @(foreach ($row in $d.Rows) {
                    $modelHtml = (& $esc $(if ($row.Models.Count -gt 0) { $row.Models -join ', ' } else { '—' }))
                    if ($row.ModelFlags.Count -gt 0) { $modelHtml += ' <span class="chip chip-bad">' + (& $esc ($row.ModelFlags -join '; ')) + '</span>' }
                    , @((Get-SqRoleBadge $row.Role), (& $esc $row.Agent), [string]$row.Dispatches, $modelHtml, (& $esc $row.Activities))
                })
            [void]$sb.Append((New-SqSimpleTable -Headers @('Role', 'Agent', 'Dispatches', 'Model', 'Key Activities') -Rows $dispatchRows -NumericColumns @(2)))
        }
        else { [void]$sb.Append('<p class="empty-state">No dispatch entries were recorded in this period.</p>') }
        $rateText = if ($null -ne $d.SuccessRate) { Format-SqPct $d.SuccessRate 0 } else { 'n/a' }
        $rateStyle = if ($null -ne $d.SuccessRate -and $d.SuccessRate -eq 100) { ' style="border-color:#dcfce7"' } else { '' }
        [void]$sb.Append("<div class=`"dispatch-summary`"><div class=`"dispatch-badge`"><span class=`"db-value`">$($d.DistinctRoles)</span> Distinct Roles Used</div><div class=`"dispatch-badge`"><span class=`"db-value`">$($d.Total)</span> Total Dispatches</div>")
        [void]$sb.Append("<div class=`"dispatch-badge`"$rateStyle><span class=`"db-value`">$(& $esc $rateText)</span> Dispatch Success Rate</div><div class=`"dispatch-badge`"><span class=`"db-value`"$(if ($d.Failed -eq 0) { ' style="color:#166534"' })>$($d.Failed)</span> Failed Dispatches</div></div>")
        if ($d.Unrecorded -gt 0) { [void]$sb.Append("<p class=`"note`">$($d.Unrecorded) dispatch(es) recorded no outcome and are excluded from the success rate; an outcome starting with fail, error, blocked or rejected counts as failed.</p>") }
        [void]$sb.Append('</div>')

        # Section 5.
        [void]$sb.Append('<div class="card" id="s5"><div class="section-header">5. Risk &amp; Compliance</div><div class="grid-2"><div><p class="section-label">Autonomy Tier Distribution</p>')
        if ($d.Tiers.Count -gt 0) {
            $tierRows = @(foreach ($t in $d.Tiers) { , @(('<span class="role-badge tier-{0}">{0}</span>' -f (& $esc $t.Tier)), [string]$t.Dispatches, (& $esc $t.Outcome)) })
            [void]$sb.Append((New-SqSimpleTable -Headers @('Tier', 'Dispatches', 'Outcome') -Rows $tierRows -NumericColumns @(1)))
            [void]$sb.Append('<p class="note">Tier is the routing.md autonomy tier of the dispatched role (escalate is shown as gated); unrecorded means the role has no routing rule.</p>')
        }
        else { [void]$sb.Append('<p class="empty-state">No dispatches in this period.</p>') }
        [void]$sb.Append('</div><div><p class="section-label">Compliance Indicators</p><div class="compliance-list">')
        $c = $Model.Compliance
        $indicator = { param($name, $ok, $total, $pass, $naText)
            $status = if ($total -eq 0) { '<span class="status status-na">' + (& $esc $naText) + '</span>' } elseif ($pass) { "<span class=`"status status-pass`">✓ $ok/$total</span>" } else { "<span class=`"status status-fail`">✗ $ok/$total</span>" }
            '<div class="compliance-item"><span>{0}</span>{1}</div>' -f (& $esc $name), $status
        }
        [void]$sb.Append((& $indicator 'Artifact evidence for all dispatches' $c.ArtifactEvidence[0] $c.ArtifactEvidence[1] ($c.ArtifactEvidence[0] -eq $c.ArtifactEvidence[1]) 'None required'))
        [void]$sb.Append((& $indicator 'Test verification on code changes' $c.TestVerified $c.CodeChanges ($c.TestVerified -eq $c.CodeChanges) 'None required'))
        [void]$sb.Append((& $indicator 'Cost logged for metered dispatches' $c.CostLogged[0] $c.CostLogged[1] ($c.CostLogged[0] -eq $c.CostLogged[1]) 'None required'))
        [void]$sb.Append((& $indicator 'Impactful actions gated' $c.ImpactfulPassed $c.ImpactfulFired ($c.ImpactfulPassed -eq $c.ImpactfulFired) 'None required'))
        [void]$sb.Append((& $indicator 'Notifications sent' $c.NotificationsResolved $c.Notifications ($c.NotificationsResolved -eq $c.Notifications) 'None required'))
        [void]$sb.Append('<div class="compliance-item"><span>Open escalations</span>').Append($(if ($c.OpenEscalations -eq 0) { '<span class="status status-pass">✓ 0 open</span>' } else { "<span class=`"status status-fail`">✗ $($c.OpenEscalations) open</span>" })).Append('</div>')
        if (@($g.Preflights).Count -gt 0) {
            $within = @($g.Preflights | Where-Object { $_.Decision -match '^(within-ceiling|approved-over-ceiling)$' }).Count
            [void]$sb.Append((& $indicator 'Cost ceiling preflight admitted' $within @($g.Preflights).Count ($within -eq @($g.Preflights).Count) 'None required'))
        }
        [void]$sb.Append('</div></div></div></div>')

        # Section 6.
        [void]$sb.Append('<div class="card" id="s6"><div class="section-header">6. Activity Timeline</div>')
        if ($Model.Timeline.Count -gt 0) {
            [void]$sb.Append('<div class="timeline">')
            foreach ($ev in $Model.Timeline) {
                $when = if ($ev.Timestamp) { & $date $ev.Timestamp } else { 'undated' }
                if ($null -ne $ev.Turn) { $when += " · Turn $($ev.Turn)" }
                if ($Model.Units.Count -gt 1 -and $ev.Unit) { $when += " · $($ev.Unit)" }
                [void]$sb.Append('<div class="tl-entry"><span class="tl-time">').Append((& $esc $when)).Append('</span><div class="tl-title">').Append((& $esc $ev.Title)).Append('</div><div class="tl-detail">').Append((& $esc $ev.Detail)).Append('</div></div>')
            }
            [void]$sb.Append('</div>')
        }
        else { [void]$sb.Append('<p class="empty-state">No dated activity was recorded in this period.</p>') }
        [void]$sb.Append('</div>')

        # Section 7.
        $o = $Model.Outcomes
        [void]$sb.Append('<div class="card" id="s7"><div class="section-header">7. Key Outcomes This Period</div><div class="outcome-badges">')
        $outBadge = { param($value, $label, $class) '<div class="outcome-badge badge-{0}"><span class="ob-value">{1}</span> {2}</div>' -f $class, (& $esc $value), (& $esc $label) }
        [void]$sb.Append((& $outBadge $o.Deployments 'Azure Deployments' 'green')).Append((& $outBadge $o.Issues 'GitHub Issues Created' 'blue'))
        [void]$sb.Append((& $outBadge (Format-SqNumber $o.Tests 0) "Tests (from $($o.TestSources) source$(if ($o.TestSources -ne 1) { 's' }))" 'blue')).Append((& $outBadge $o.Files 'Files Created/Modified' 'blue')).Append('</div>')
        [void]$sb.Append('<p class="section-label">Delivered Capabilities</p>')
        if ($o.Capabilities.Count -gt 0) {
            $capRows = @(foreach ($cap in ($o.Capabilities | Select-Object -First 25)) {
                    $badge = switch ($cap.Status) { 'Complete' { 'green' } 'Blocked' { 'red' } 'Escalated' { 'amber' } default { 'blue' } }
                    , @(('<code>{0}</code>' -f (& $esc $cap.Capability)), (& $esc $cap.Type), ('<span class="role-badge badge-{0}">{1}</span>' -f $badge, (& $esc $cap.Status)))
                })
            [void]$sb.Append((New-SqSimpleTable -Headers @('Capability', 'Type', 'Status') -Rows $capRows))
            if ($o.Capabilities.Count -gt 25) { [void]$sb.Append("<p class=`"note`">$($o.Capabilities.Count - 25) more deliverable(s) are recorded in the dispatch history.</p>") }
        }
        else { [void]$sb.Append('<p class="empty-state">No deliverable paths were recorded in this period.</p>') }
        [void]$sb.Append('<p class="section-label">Why HVE Squad: what this run produced</p>')
        [void]$sb.Append((& $renderEvidence $Model.Justifications.Output))
        [void]$sb.Append('</div></div>')

        # Footer.
        [void]$sb.Append('<footer>')
        [void]$sb.Append('<strong>Grounding sources:</strong> ').Append((& $esc (@($Model.Sources | ForEach-Object { $_.Path }) -join ', '))).Append('<br>')
        if ($Model.Skipped.Count -gt 0) { [void]$sb.Append('<strong>Not read:</strong> ').Append((& $esc ($Model.Skipped -join ', '))).Append('<br>') }
        $scopeFooter = if ($meta.Squad) { "sub-squad $($meta.Squad) (federation member)" } elseif ($meta.Multi) { "federation, $($meta.Units.Count) sub-squads" } else { 'single squad' }
        [void]$sb.Append('<strong>Scope:</strong> ').Append((& $esc $scopeFooter)).Append(' · <strong>Period:</strong> ').Append((& $esc $periodText)).Append('<br>')
        $arguments = "period=$($meta.Period.Name)"
        if ($meta.Squad) { $arguments = "squad=$($meta.Squad) $arguments" }
        [void]$sb.Append('<strong>Report generated by:</strong> ').Append((& $esc "$Command $arguments")).Append(' — deterministic renderer (New-SquadGovernanceReport.ps1); read-only, CSS-only, no JavaScript, self-contained. Generated for ').Append((& $esc $meta.AsOf)).Append('.<br>')
        [void]$sb.Append('<strong>Input digest:</strong> sha256:').Append((& $esc $Model.Digest)).Append(' (same state and arguments always produce the same report).<br>')
        $calibrationNotes = @($Model.Units | Where-Object { $_.Ledger.Present -and $_.Ledger.Calibration } | ForEach-Object { '{0}: factor {1}, {2} reconciled run(s){3}' -f $_.Name, (Format-SqNumber $_.Ledger.Calibration.Factor 2), $_.Ledger.Calibration.ReconciledRuns, $(if ($_.Ledger.Calibration.Status) { " ($($_.Ledger.Calibration.Status))" } else { '' }) })
        if ($calibrationNotes.Count -gt 0) { [void]$sb.Append('<strong>Calibration:</strong> ').Append((& $esc ($calibrationNotes -join '; '))).Append('<br>') }
        [void]$sb.Append('<strong>Badge thresholds</strong> are guidance: green marks success, amber in-progress or conditional, red blocked or failed, gray not activated.')
        [void]$sb.Append('</footer></body></html>')
        $sb.ToString().Replace("`r`n", "`n")
    }
    finally {
        [Globalization.CultureInfo]::CurrentCulture = $previousCulture
    }
}
