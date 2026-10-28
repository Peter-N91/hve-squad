# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# One small benchmark score: build it from run results, write it, compare two.
#
# Invoke-Benchmark.ps1 writes the score into benchmarks/efficiency/ and
# Compare-Benchmark.ps1 compares two scores for a pull request. A score file that
# arrives from a pull request is untrusted: Read-BenchmarkScore keeps only validated
# numbers and short sanitised strings, so nothing in the file can turn into markup in
# a comment or into a workflow command.

#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:Schema = 'benchmark-score-v1'
$script:Culture = [Globalization.CultureInfo]::InvariantCulture
$script:Stages = @('init', 'requirements', 'build')
$script:Dimensions = [ordered]@{
    businessClarity = 'Business clarity'
    scopeFidelity = 'Scope fidelity'
    acceptanceCriteria = 'Acceptance criteria'
    traceability = 'Traceability'
    risksAndDecisions = 'Risks and decisions'
}
$script:Marker = '<!-- squad-benchmark-score -->'
$script:RefreshCommand = 'pwsh -NoProfile -File ./tests/tier2/live-benchmark/Invoke-Benchmark.ps1'
$script:ActivityLabels = [ordered]@{
    scribeDispatches = 'Scribe dispatches'
    scribeModelRequests = 'Scribe model requests'
    scribeSeconds = 'Time inside Scribe dispatches'
    scribeCredits = 'Scribe credits'
    coordinatorModelRequests = 'Coordinator model requests'
    authorModelRequests = 'BRD/PRD author model requests'
}

# --- Small helpers -----------------------------------------------------------

function Test-Number {
    param($Value)
    $Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or ($Value -is [double] -and [double]::IsFinite($Value))
}

function Get-ScoreField {
    param($Object, [string[]]$Path)
    foreach ($name in $Path) {
        if ($Object -isnot [Collections.IDictionary] -or -not $Object.Contains($name)) { return $null }
        $Object = $Object[$name]
    }
    $Object
}

function Get-ScoreList {
    param($Object, [string[]]$Path)
    $value = Get-ScoreField $Object $Path
    if ($value -is [array]) { @($value | Where-Object { $_ -is [Collections.IDictionary] }) }
}

function Get-ScoreMedian {
    param([double[]]$Value)
    $sorted = @($Value | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2) { $sorted[$middle] } else { ($sorted[$middle - 1] + $sorted[$middle]) / 2 }
}

function Format-SafeText {
    param($Value, [int]$MaxLength = 64)
    $text = [regex]::Replace([string]$Value, '[^A-Za-z0-9 ._+/,;()=-]', '').Trim()
    if ($text.Length -gt $MaxLength) { $text = $text.Substring(0, $MaxLength) }
    if ($text) { $text } else { 'unknown' }
}

function Format-ScoreNumber {
    param([double]$Value)
    ([Math]::Round($Value, 2) + 0.0).ToString('0.##', $script:Culture)
}

function Format-ScoreDuration {
    param([double]$Seconds)
    $total = [Math]::Round($Seconds, 1)
    $minutes = [Math]::Floor($total / 60)
    "$($minutes.ToString('N0', $script:Culture)) min $(Format-ScoreNumber ($total - $minutes * 60)) s"
}

function ConvertTo-ScoreTime {
    # ConvertFrom-Json turns ISO timestamps into [datetime], so accept both forms.
    param($Value)
    $parsed = [datetime]::MinValue
    if ($Value -is [datetime]) { $parsed = $Value.ToUniversalTime() }
    elseif (-not ($Value -is [string] -and [datetime]::TryParse($Value, $script:Culture, 'AssumeUniversal,AdjustToUniversal', [ref]$parsed))) { return $null }
    $parsed.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $script:Culture)
}

# --- Build a score from run results -------------------------------------------

function ConvertTo-BenchmarkRunSummary {
    <# .SYNOPSIS
    Reduces one run's result file (or the lack of one) to the figures the score uses.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Run,
        [AllowNull()][Collections.IDictionary]$Result,
        [string]$Note = ''
    )
    $trial = [ordered]@{
        run = $Run; scored = $false; quality = $null; dimensions = $null
        functional = $false; workflow = $false; criticalHighFindings = $null
        seconds = $null; credits = $null; failedChecks = @()
        note = if ($Note) { Format-SafeText $Note 120 } else { '' }
        activity = $null
    }
    if ($null -eq $Result) { return $trial }
    $trial['activity'] = Read-ScoreActivity (Get-ScoreField $Result 'metrics', 'activity')

    $stages = @(Get-ScoreList $Result 'stages')
    $stagesPassed = $true
    foreach ($name in $script:Stages) {
        $stage = $stages | Where-Object { $_['name'] -eq $name } | Select-Object -First 1
        if ($null -eq $stage -or $stage['passed'] -ne $true) { $stagesPassed = $false }
    }
    $trial['functional'] = (Get-ScoreField $Result 'acceptance', 'passed') -eq $true
    $trial['workflow'] = $stagesPassed -and (Get-ScoreField $Result 'workflow', 'passed') -eq $true

    $seconds = @($stages | ForEach-Object { Get-ScoreField $_ 'process', 'seconds' }) + (Get-ScoreField $Result 'judge', 'process', 'seconds') |
        Where-Object { Test-Number $_ }
    if (@($seconds).Count) { $trial['seconds'] = [double](@($seconds) | Measure-Object -Sum).Sum }

    $workflowCredits = Get-ScoreCredit (Get-ScoreField $Result 'metrics', 'credits')
    $judgeCredits = if ($null -ne (Get-ScoreField $Result 'judge')) { Get-ScoreCredit (Get-ScoreField $Result 'judge', 'metrics', 'credits') } else { 0.0 }
    if ($null -ne $workflowCredits -and $null -ne $judgeCredits) { $trial['credits'] = $workflowCredits + $judgeCredits }

    $scores = Get-ScoreField $Result 'judge', 'response', 'scores'
    $findings = Get-ScoreField $Result 'judge', 'response', 'criticalHighFindings'
    $valid = (Get-ScoreField $Result 'judge', 'valid') -eq $true -and $scores -is [Collections.IDictionary] -and (Test-Number $findings) -and $findings -ge 0
    $dimensions = [ordered]@{}
    $total = 0.0
    foreach ($name in $script:Dimensions.Keys) {
        $value = if ($valid) { $scores[$name] }
        if ($valid -and ((Test-Number $value) -and $value -ge 0 -and $value -le 20)) { $dimensions[$name] = [double]$value; $total += $value }
        else { $valid = $false }
    }
    if ($valid) {
        $trial['scored'] = $true; $trial['quality'] = $total; $trial['dimensions'] = $dimensions
        $trial['criticalHighFindings'] = [int]$findings
    }
    elseif (-not $trial['note']) { $trial['note'] = 'the judge result is missing or invalid' }

    $failed = [Collections.Generic.List[string]]::new()
    foreach ($check in @(Get-ScoreList $Result 'acceptance', 'checks')) {
        if ($check['passed'] -ne $true) { $failed.Add("functional/$($check['name'])") }
    }
    foreach ($stage in $stages) {
        $checks = Get-ScoreField $stage 'readiness', 'checks'
        if ($checks -isnot [Collections.IDictionary]) { continue }
        foreach ($key in $checks.Keys) { if ($checks[$key] -ne $true) { $failed.Add("$($stage['name'])/$key") } }
    }
    $trial['failedChecks'] = @($failed | ForEach-Object { Format-SafeText $_ 60 } | Select-Object -Unique -First 12)
    $trial
}

function Get-ScoreCredit {
    param($Metric)
    $used = Get-ScoreField $Metric 'used'
    if ((Get-ScoreField $Metric 'complete') -eq $true -and (Test-Number $used)) { [double]$used }
}

function Get-BenchmarkRunIdentity {
    <# .SYNOPSIS
    Reads the model, CLI and source identity a run recorded about itself.
    #>
    [CmdletBinding()]
    param([AllowNull()][Collections.IDictionary]$Result)
    [ordered]@{
        model = Get-ScoreField $Result 'metadata', 'compatibility', 'model'
        cli = Get-ScoreField $Result 'metadata', 'compatibility', 'cli'
        powershell = Get-ScoreField $Result 'metadata', 'compatibility', 'powershell'
        squadSourceHash = Get-ScoreField $Result 'metadata', 'sourceHash'
    }
}

function ConvertTo-BenchmarkScore {
    <# .SYNOPSIS
    Combines the per-run summaries into one score. Runs without a valid judged result count as failed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Trial,
        [Parameter(Mandatory)][ValidateRange(1, 3)][int]$Requested,
        [Parameter(Mandatory)][string]$Commit,
        [bool]$UncommittedChanges,
        [Collections.IDictionary]$Identity = @{},
        [string]$Scenario = 'task-cli-cold-start',
        [datetime]$MeasuredAt = [datetime]::UtcNow
    )
    if ($Trial.Count -ne $Requested) { throw 'One summary per requested run is required.' }
    $scored = @($Trial | Where-Object { $_['scored'] })
    $summary = [ordered]@{
        quality = $null; dimensions = $null
        functional = @($Trial | Where-Object { $_['functional'] }).Count
        workflow = @($Trial | Where-Object { $_['workflow'] }).Count
        criticalHighFindings = $null; averageSeconds = $null; averageCredits = $null
        activity = $null
    }
    if ($scored.Count) {
        $summary['activity'] = [ordered]@{}
        foreach ($key in $script:ActivityLabels.Keys) {
            $values = @($scored | ForEach-Object { Get-ScoreField $_ 'activity', $key } | Where-Object { $null -ne $_ })
            $summary['activity'][$key] = if ($values.Count -eq $scored.Count) { [double]($values | Measure-Object -Average).Average } else { $null }
        }
        $summary['quality'] = Get-ScoreMedian @($scored | ForEach-Object { $_['quality'] })
        $summary['dimensions'] = [ordered]@{}
        foreach ($name in $script:Dimensions.Keys) {
            $summary['dimensions'][$name] = Get-ScoreMedian @($scored | ForEach-Object { $_['dimensions'][$name] })
        }
        $summary['criticalHighFindings'] = [int](@($scored | ForEach-Object { $_['criticalHighFindings'] }) | Measure-Object -Sum).Sum
        foreach ($pair in @(@('averageSeconds', 'seconds'), @('averageCredits', 'credits'))) {
            $values = @($scored | Where-Object { $null -ne $_[$pair[1]] } | ForEach-Object { $_[$pair[1]] })
            if ($values.Count -eq $scored.Count) { $summary[$pair[0]] = ($values | Measure-Object -Average).Average }
        }
    }
    [ordered]@{
        schema = $script:Schema
        scenario = $Scenario
        measuredAt = $MeasuredAt.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $script:Culture)
        source = [ordered]@{ commit = $Commit; squadSourceHash = $Identity['squadSourceHash']; uncommittedChanges = $UncommittedChanges }
        environment = [ordered]@{ model = $Identity['model']; cli = $Identity['cli']; powershell = $Identity['powershell'] }
        runs = [ordered]@{ requested = $Requested; scored = $scored.Count; failed = $Requested - $scored.Count }
        summary = $summary
        trials = @($Trial)
    }
}

# --- Badge, report and files ---------------------------------------------------

function Get-BenchmarkBadgeText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Score)
    $runs = $Score['runs']; $summary = $Score['summary']
    if ($runs['scored'] -lt 1) { return 'benchmark unavailable' }
    $requested = $runs['requested']
    $time = if ($null -ne $summary['averageSeconds']) { Format-ScoreDuration $summary['averageSeconds'] } else { 'unavailable' }
    "doc quality $(Format-ScoreNumber $summary['quality'])/100 | functional $($summary['functional'])/$requested | workflow $($summary['workflow'])/$requested | avg benchmark time $time"
}

function Get-BenchmarkBadgeSvg {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Score)
    $runs = $Score['runs']; $summary = $Score['summary']
    $text = [Security.SecurityElement]::Escape((Get-BenchmarkBadgeText $Score))
    $allPassed = $runs['scored'] -eq $runs['requested'] -and $summary['functional'] -eq $runs['requested'] -and $summary['workflow'] -eq $runs['requested']
    $fill = if ($runs['scored'] -lt 1) { '#6b7280' } elseif ($allPassed) { '#16723b' } else { '#b45309' }
    $width = [Math]::Max(720, 24 + 7 * $text.Length)
    '<svg xmlns="http://www.w3.org/2000/svg" width="{0}" height="28" viewBox="0 0 {0} 28" role="img" aria-label="{1}"><title>{1}</title><rect width="{0}" height="28" rx="4" fill="{2}"/><text x="{3}" y="18" text-anchor="middle" fill="#fff" font-family="Verdana,Arial,sans-serif" font-size="12">{1}</text></svg>' -f $width, $text, $fill, ($width / 2).ToString($script:Culture)
}

function Get-ScoreProvenance {
    param([Parameter(Mandatory)][Collections.IDictionary]$Score)
    $commit = Get-ScoreField $Score 'source', 'commit'
    $commit = if ($commit -is [string] -and $commit -cmatch '^[0-9a-f]{7,40}$') { $commit.Substring(0, 7) } else { 'unknown' }
    $when = ConvertTo-ScoreTime (Get-ScoreField $Score 'measuredAt')
    $when = if ($when) { $when.Substring(0, 16).Replace('T', ' ') + ' UTC' } else { 'unknown date' }
    $model = Format-SafeText (Get-ScoreField $Score 'environment', 'model')
    $cli = Format-SafeText (Get-ScoreField $Score 'environment', 'cli')
    $count = $Score['runs']['requested']
    "$when, commit ``$commit``, model ``$model``, Copilot CLI ``$cli``, $count run$(if ($count -ne 1) { 's' })"
}

function Get-ScoreRow {
    # The display text and the number compared for each measure of a score.
    param([Parameter(Mandatory)][Collections.IDictionary]$Score)
    $requested = $Score['runs']['requested']; $scored = $Score['runs']['scored']
    $summary = $Score['summary']
    $has = $scored -gt 0
    $findings = $summary['criticalHighFindings']
    $perRun = if ($has -and $null -ne $findings) { $findings / $scored }
    [ordered]@{
        quality = @{
            Label = 'Document quality (median, out of 100)'
            Text = if ($has) { Format-ScoreNumber $summary['quality'] } else { 'n/a' }
            Number = if ($has) { $summary['quality'] }
        }
        functional = @{ Label = 'Functional (runs passing)'; Text = "$($summary['functional'])/$requested"; Number = $summary['functional'] / $requested }
        workflow = @{ Label = 'Workflow (runs passing)'; Text = "$($summary['workflow'])/$requested"; Number = $summary['workflow'] / $requested }
        findings = @{
            Label = 'Critical/high findings'
            Text = if ($null -ne $perRun) { "$findings ($(Format-ScoreNumber $perRun) per run)" } else { 'n/a' }
            Number = $perRun
        }
        seconds = @{
            Label = 'Average time per run'
            Text = if ($null -ne $summary['averageSeconds']) { Format-ScoreDuration $summary['averageSeconds'] } else { 'n/a' }
            Number = $summary['averageSeconds']
        }
        credits = @{
            Label = 'Average credits per run'
            Text = if ($null -ne $summary['averageCredits']) { Format-ScoreNumber $summary['averageCredits'] } else { 'n/a' }
            Number = $summary['averageCredits']
        }
        scored = @{ Label = 'Runs that produced a score'; Text = "$scored/$requested"; Number = $scored / $requested }
    }
}

function Get-ActivityReportMarkdown {
    param([AllowNull()][Collections.IDictionary]$Earlier, [AllowNull()][Collections.IDictionary]$Latest)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]@('## Observed activity', '', '| Observed activity | Earlier run | Latest run |', '| --- | --- | --- |'))
    foreach ($key in $script:ActivityLabels.Keys) {
        $cells = foreach ($score in @($Earlier, $Latest)) {
            $value = Get-ScoreField $score 'summary', 'activity', $key
            if ($null -eq $value) { 'unavailable' }
            elseif ($key -eq 'scribeSeconds') { Format-ScoreDuration $value }
            else { Format-ScoreNumber $value }
        }
        $lines.Add("| $($script:ActivityLabels[$key]) | $($cells -join ' | ') |")
    }
    $lines.Add('')
    $lines.Add('Activity is averaged per scored run; a metric is unavailable if any scored run lacks it. Dispatch time is summed per Scribe dispatch, not elapsed benchmark time. Requests count unique usage records; credits cover those records, excluding separate compaction charges and the judge.')
    $lines.Add('')
    $lines -join "`n"
}

function Get-BenchmarkReportMarkdown {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Score, [AllowNull()][Collections.IDictionary]$EarlierScore)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]@('# Benchmark score', '', "Measured: $(Get-ScoreProvenance $Score)."))
    if ($Score['source']['uncommittedChanges']) { $lines.Add('The squad source had uncommitted changes when this was measured.') }
    $lines.AddRange([string[]]@('', '| Measure | Result |', '| --- | --- |'))
    $rows = Get-ScoreRow $Score
    foreach ($row in $rows.Values) { $lines.Add("| $($row.Label) | $($row.Text) |") }
    $lines.Add('')
    $lines.Add((Get-ActivityReportMarkdown -Earlier $EarlierScore -Latest $Score))
    if ($null -ne $EarlierScore) { $lines.Add("Earlier run: $(Get-ScoreProvenance $EarlierScore).") }
    else { $lines.Add('Earlier run: no previous local score was available.') }
    if ($Score['runs']['scored'] -gt 0) {
        $lines.AddRange([string[]]@('', '## Document quality by dimension (median, out of 20)', '', '| Dimension | Score |', '| --- | --- |'))
        foreach ($name in $script:Dimensions.Keys) { $lines.Add("| $($script:Dimensions[$name]) | $(Format-ScoreNumber $Score['summary']['dimensions'][$name]) |") }
    }
    $lines.AddRange([string[]]@('', '## Runs', '', '| Run | Scored | Quality | Functional | Workflow | Critical/high | Time | Credits |', '| --- | --- | --- | --- | --- | --- | --- | --- |'))
    $yes = { param($value) if ($value) { 'yes' } else { 'no' } }
    foreach ($trial in $Score['trials']) {
        $quality = if ($trial['scored']) { Format-ScoreNumber $trial['quality'] } else { 'n/a' }
        $findings = if ($trial['scored']) { $trial['criticalHighFindings'] } else { 'n/a' }
        $time = if ($null -ne $trial['seconds']) { Format-ScoreDuration $trial['seconds'] } else { 'n/a' }
        $credits = if ($null -ne $trial['credits']) { Format-ScoreNumber $trial['credits'] } else { 'n/a' }
        $lines.Add("| $($trial['run']) | $(& $yes $trial['scored']) | $quality | $(& $yes $trial['functional']) | $(& $yes $trial['workflow']) | $findings | $time | $credits |")
    }
    $details = @($Score['trials'] | Where-Object { $_['note'] -or @($_['failedChecks']).Count })
    if ($details.Count) {
        $lines.AddRange([string[]]@('', '## What did not pass', ''))
        foreach ($trial in $details) {
            $parts = @($trial['note']) + @($trial['failedChecks'] | ForEach-Object { "``$_``" })
            $lines.Add("- Run $($trial['run']): $(($parts | Where-Object { $_ }) -join ', ')")
        }
    }
    $lines.AddRange([string[]]@('', 'How to read and refresh this score: [README](README.md).', ''))
    $lines -join "`n"
}

function Write-BenchmarkScore {
    <# .SYNOPSIS
    Writes score.json, badge.svg and report.md into the directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Score,
        [Parameter(Mandatory)][string]$Directory,
        [AllowNull()][Collections.IDictionary]$EarlierScore
    )
    [void][IO.Directory]::CreateDirectory($Directory)
    $files = [ordered]@{
        'score.json' = ($Score | ConvertTo-Json -Depth 8) + "`n"
        'badge.svg' = (Get-BenchmarkBadgeSvg $Score) + "`n"
        'report.md' = Get-BenchmarkReportMarkdown -Score $Score -EarlierScore $EarlierScore
    }
    foreach ($name in $files.Keys) {
        $path = Join-Path $Directory $name
        [IO.File]::WriteAllText($path, $files[$name].Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
        $path
    }
}

# --- Read an untrusted score ---------------------------------------------------

function ConvertTo-ScoreInteger {
    param($Value, [int]$Min, [int]$Max)
    if (-not (Test-Number $Value) -or $Value -ne [Math]::Floor($Value) -or $Value -lt $Min -or $Value -gt $Max) { throw 'Invalid score value.' }
    [int]$Value
}

function ConvertTo-ScoreDouble {
    param($Value, [double]$Min, [double]$Max)
    if ($null -eq $Value) { return $null }
    if (-not (Test-Number $Value) -or $Value -lt $Min -or $Value -gt $Max) { throw 'Invalid score value.' }
    [double]$Value
}

function Read-ScoreActivity {
    param($Activity)
    if ($null -eq $Activity) { return $null }
    if ($Activity -isnot [Collections.IDictionary]) { throw 'Invalid activity metrics.' }
    $result = [ordered]@{}
    foreach ($key in $script:ActivityLabels.Keys) {
        $result[$key] = ConvertTo-ScoreDouble (Get-ScoreField $Activity $key) 0 10000000
    }
    $result
}

function Read-BenchmarkScore {
    <# .SYNOPSIS
    Reads a score.json and returns only validated numbers and sanitised strings. Throws when it is not a valid score.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if ((Get-Item -LiteralPath $Path).Length -gt 1MB) { throw 'The score file is too large.' }
    $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if ((Get-ScoreField $raw 'schema') -cne $script:Schema) { throw 'Unsupported score schema.' }

    $requested = ConvertTo-ScoreInteger (Get-ScoreField $raw 'runs', 'requested') 1 3
    $scored = ConvertTo-ScoreInteger (Get-ScoreField $raw 'runs', 'scored') 0 $requested
    $summary = [ordered]@{
        quality = ConvertTo-ScoreDouble (Get-ScoreField $raw 'summary', 'quality') 0 100
        dimensions = $null
        functional = ConvertTo-ScoreInteger (Get-ScoreField $raw 'summary', 'functional') 0 $requested
        workflow = ConvertTo-ScoreInteger (Get-ScoreField $raw 'summary', 'workflow') 0 $requested
        criticalHighFindings = ConvertTo-ScoreDouble (Get-ScoreField $raw 'summary', 'criticalHighFindings') 0 1000000
        averageSeconds = ConvertTo-ScoreDouble (Get-ScoreField $raw 'summary', 'averageSeconds') 0 10000000
        averageCredits = ConvertTo-ScoreDouble (Get-ScoreField $raw 'summary', 'averageCredits') 0 10000000
        activity = Read-ScoreActivity (Get-ScoreField $raw 'summary', 'activity')
    }
    if ($scored -gt 0) {
        if ($null -eq $summary['quality'] -or $null -eq $summary['criticalHighFindings']) { throw 'A scored run needs quality and findings.' }
        $dimensions = Get-ScoreField $raw 'summary', 'dimensions'
        if ($dimensions -isnot [Collections.IDictionary]) { throw 'A scored run needs quality dimensions.' }
        $summary['dimensions'] = [ordered]@{}
        foreach ($name in $script:Dimensions.Keys) {
            $summary['dimensions'][$name] = ConvertTo-ScoreDouble $dimensions[$name] 0 20
            if ($null -eq $summary['dimensions'][$name]) { throw 'A quality dimension is missing.' }
        }
    }
    $commit = Get-ScoreField $raw 'source', 'commit'
    [ordered]@{
        schema = $script:Schema
        measuredAt = ConvertTo-ScoreTime (Get-ScoreField $raw 'measuredAt')
        source = [ordered]@{
            commit = if ($commit -is [string] -and $commit -cmatch '^[0-9a-f]{7,40}$') { $commit } else { 'unknown' }
            uncommittedChanges = (Get-ScoreField $raw 'source', 'uncommittedChanges') -eq $true
        }
        environment = [ordered]@{
            model = Format-SafeText (Get-ScoreField $raw 'environment', 'model')
            cli = Format-SafeText (Get-ScoreField $raw 'environment', 'cli')
        }
        runs = [ordered]@{ requested = $requested; scored = $scored; failed = $requested - $scored }
        summary = $summary
    }
}

# --- Compare two scores --------------------------------------------------------

function Get-ScoreChange {
    param([string]$Key, $BaseRow, $HeadRow)
    $base = $BaseRow.Number; $head = $HeadRow.Number
    if ($null -eq $base -or $null -eq $head) { return '' }
    $delta = $head - $base
    if ([Math]::Abs($delta) -lt 1e-9) { return '0' }
    $sign = if ($delta -gt 0) { '+' } else { '-' }
    $size = [Math]::Abs($delta)
    $percent = if ($base -gt 0) { " ($sign$(Format-ScoreNumber ($size / $base * 100))%)" } else { '' }
    switch ($Key) {
        { $_ -in 'functional', 'workflow', 'scored' } { "$sign$(Format-ScoreNumber ($size * 100)) pts" }
        'seconds' { "$sign$(if ($size -lt 60) { "$(Format-ScoreNumber $size) s" } else { Format-ScoreDuration $size })$percent" }
        'credits' { "$sign$(Format-ScoreNumber $size)$percent" }
        'findings' { "$sign$(Format-ScoreNumber $size) per run" }
        default { "$sign$(Format-ScoreNumber $size)" }
    }
}

function Compare-BenchmarkScore {
    <# .SYNOPSIS
    Describes how a pull request's score differs from its base. Warns about lower scores and failed runs; never fails.
    .DESCRIPTION
    Scores that differ in run count, model or CLI are still compared on a best-effort basis
    (pass rates and per-run averages), with a note. A missing or unreadable score only
    changes what is shown. Returns Warnings, Notes and the Markdown comment.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][Collections.IDictionary]$Base,
        [AllowNull()][Collections.IDictionary]$Head,
        [string]$BaseProblem = '',
        [string]$HeadProblem = '',
        [switch]$Unchanged,
        [switch]$SquadSourceChanged
    )
    $warnings = [Collections.Generic.List[string]]::new()
    $notes = [Collections.Generic.List[string]]::new()
    $baseRows = if ($null -ne $Base) { Get-ScoreRow $Base }
    $headRows = if ($null -ne $Head) { Get-ScoreRow $Head }
    $mode = if ($null -ne $Base -and $null -ne $Head -and -not $Unchanged) { 'compare' } elseif ($null -ne $Head) { 'head' } elseif ($null -ne $Base) { 'base' } else { 'none' }

    if ($mode -eq 'compare') {
        $b = $Base['summary']; $h = $Head['summary']
        if ($Base['runs']['scored'] -eq 0) { $notes.Add('The base score has no scored runs, so only this pull request''s figures are meaningful.') }
        elseif ($Head['runs']['scored'] -gt 0) {
            if ($h['quality'] -lt $b['quality'] - 1e-9) { $warnings.Add("Document quality is lower than on the base branch: $(Format-ScoreNumber $h['quality']) vs $(Format-ScoreNumber $b['quality']).") }
            $lower = @($script:Dimensions.Keys | Where-Object { $h['dimensions'][$_] -lt $b['dimensions'][$_] - 1e-9 })
            if ($lower.Count) { $warnings.Add('Lower quality dimension medians than on the base branch: ' + (($lower | ForEach-Object { "$($script:Dimensions[$_]) $(Format-ScoreNumber $h['dimensions'][$_]) vs $(Format-ScoreNumber $b['dimensions'][$_])" }) -join ', ') + '.') }
            if ($headRows.findings.Number -gt $baseRows.findings.Number + 1e-9) { $warnings.Add("More critical/high findings per run than on the base branch: $(Format-ScoreNumber $headRows.findings.Number) vs $(Format-ScoreNumber $baseRows.findings.Number).") }
        }
        foreach ($key in 'functional', 'workflow') {
            if ($headRows[$key].Number -lt $baseRows[$key].Number - 1e-9) { $warnings.Add("The $key pass rate is lower than on the base branch: $($headRows[$key].Text) vs $($baseRows[$key].Text).") }
        }
        if ($Base['runs']['requested'] -ne $Head['runs']['requested']) { $notes.Add("The base score used $($Base['runs']['requested']) run(s) and this pull request $($Head['runs']['requested']); pass rates and per-run averages are compared, so treat the comparison as indicative.") }
        if ($Base['environment']['model'] -cne $Head['environment']['model']) { $notes.Add("The model differs (base ``$($Base['environment']['model'])``, this pull request ``$($Head['environment']['model'])``), so the scores may not be comparable.") }
        if ($Base['environment']['cli'] -cne $Head['environment']['cli']) { $notes.Add("The Copilot CLI version differs (base ``$($Base['environment']['cli'])``, this pull request ``$($Head['environment']['cli'])``).") }
    }
    if ($mode -in 'compare', 'head' -and -not $Unchanged) {
        if ($Head['runs']['scored'] -eq 0) { $warnings.Add('None of the benchmark runs produced a score.') }
        elseif ($Head['runs']['failed'] -gt 0) { $warnings.Add("$($Head['runs']['failed']) of $($Head['runs']['requested']) benchmark runs did not produce a score.") }
    }
    if ($null -eq $Head -and $null -ne $Base) { $warnings.Add("This pull request has no readable benchmark score ($HeadProblem), but the base branch has one.") }
    if ($null -eq $Base) {
        $notes.Add($(if ($BaseProblem -eq 'unreadable') { 'The base branch''s score could not be read, so there is nothing to compare with.' } elseif ($null -ne $Head) { 'The base branch has no benchmark score yet, so there is nothing to compare with.' } else { 'No benchmark score has been recorded yet.' }))
    }
    if ($Unchanged -and $null -ne $Head) { $notes.Add('This pull request does not change the benchmark score.') }
    if ($null -ne $Head -and $Head['source']['uncommittedChanges']) { $notes.Add('The pull request''s score was measured with uncommitted changes in `squad-src/`, so its commit may not match this code.') }
    if ($SquadSourceChanged -and ($Unchanged -or $null -eq $Head)) { $notes.Add("``squad-src/`` changed but the score was not refreshed. Optionally run ``$script:RefreshCommand`` and commit ``benchmarks/efficiency/``.") }

    $lines = [Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]@($script:Marker, '### Benchmark score', ''))
    if ($mode -ne 'none') {
        $header = switch ($mode) {
            'compare' { @('Measure', 'Base branch', 'This pull request', 'Change') }
            'head' { @('Measure', 'Score') }
            'base' { @('Measure', 'Base branch') }
        }
        $table = {
            param($Keys, $Labels, $BaseSet, $HeadSet)
            $lines.Add('| ' + ($header -join ' | ') + ' |')
            $lines.Add('| ' + (($header | ForEach-Object { '---' }) -join ' | ') + ' |')
            foreach ($key in $Keys) {
                $label = $Labels[$key]
                $cells = switch ($mode) {
                    'compare' { @($label, $BaseSet[$key].Text, $HeadSet[$key].Text, (Get-ScoreChange $key $BaseSet[$key] $HeadSet[$key])) }
                    'head' { @($label, $HeadSet[$key].Text) }
                    'base' { @($label, $BaseSet[$key].Text) }
                }
                $lines.Add('| ' + ($cells -join ' | ') + ' |')
            }
        }
        $labels = @{}
        $source = if ($null -ne $headRows) { $headRows } else { $baseRows }
        foreach ($key in $source.Keys) { $labels[$key] = $source[$key].Label }
        & $table @($source.Keys) $labels $baseRows $headRows
        $lines.Add('')
        $lines.Add((Get-ActivityReportMarkdown -Earlier $Base -Latest $Head))
        $shown = if ($null -ne $Head) { $Head } else { $Base }
        if ($shown['runs']['scored'] -gt 0 -and ($mode -ne 'compare' -or ($Base['runs']['scored'] -gt 0 -and $Head['runs']['scored'] -gt 0))) {
            $dimension = {
                param($Score)
                $rows = [ordered]@{}
                foreach ($name in $script:Dimensions.Keys) { $text = Format-ScoreNumber $Score['summary']['dimensions'][$name]; $rows[$name] = @{ Text = $text; Number = $Score['summary']['dimensions'][$name] } }
                $rows
            }
            $dimensionLabels = @{}
            foreach ($name in $script:Dimensions.Keys) { $dimensionLabels[$name] = $script:Dimensions[$name] }
            $lines.AddRange([string[]]@('', '<details><summary>Document quality by dimension (median, out of 20)</summary>', ''))
            & $table @($script:Dimensions.Keys) $dimensionLabels $(if ($null -ne $Base) { & $dimension $Base }) $(if ($null -ne $Head) { & $dimension $Head })
            $lines.AddRange([string[]]@('', '</details>'))
        }
        $lines.Add('')
        if ($null -ne $Base) { $lines.Add("Base branch: $(Get-ScoreProvenance $Base)."); $lines.Add('') }
        if ($null -ne $Head) { $lines.Add("This pull request: $(Get-ScoreProvenance $Head)."); $lines.Add('') }
    }
    if ($warnings.Count) { $lines.Add('**Warnings**'); $lines.Add(''); foreach ($w in $warnings) { $lines.Add("- :warning: $w") }; $lines.Add('') }
    if ($notes.Count) { $lines.Add('**Notes**'); $lines.Add(''); foreach ($n in $notes) { $lines.Add("- $n") }; $lines.Add('') }
    $lines.Add("<sub>Informational only: this check never fails a pull request. Scores are measured locally with ``$script:RefreshCommand`` and saved in ``benchmarks/efficiency/`` (see its README).</sub>")
    [pscustomobject]@{ Warnings = @($warnings); Notes = @($notes); Markdown = ($lines -join "`n") + "`n" }
}

Export-ModuleMember -Function ConvertTo-BenchmarkRunSummary, Get-BenchmarkRunIdentity, ConvertTo-BenchmarkScore, Get-BenchmarkBadgeText, Get-BenchmarkBadgeSvg, Get-BenchmarkReportMarkdown, Write-BenchmarkScore, Read-BenchmarkScore, Compare-BenchmarkScore
