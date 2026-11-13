# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
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
$script:CompatibilityFields = @(
    'schema', 'rubric', 'hostProfile', 'scenarioHash', 'parserHash', 'exerciseHash',
    'preparationHash', 'graderHash', 'verifierHash', 'converterHash', 'installHash',
    'model', 'cli', 'powershell', 'roleModelPolicy', 'disabledMcpServers',
    'maxCredits', 'continuations', 'recoveryPolicy', 'evaluationPolicy'
)
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
    ,$Object
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

function Read-ScoreCompatibility {
    param($Compatibility)
    $result = [ordered]@{}
    foreach ($key in $script:CompatibilityFields) {
        $value = Get-ScoreField $Compatibility $key
        $result[$key] = if ($value -is [string] -and $value -cmatch '^[a-f0-9]{64}$') { $value } else { $null }
    }
    $result
}

function ConvertTo-ScoreReviewPath {
    param($Path)
    if ($Path -isnot [string] -or $Path.Length -gt 240) { return $null }
    $pathText = $Path.Replace('\', '/')
    if ($pathText -cnotmatch '^[A-Za-z0-9_. -]+(?:/[A-Za-z0-9_. -]+)*$' -or
        @($pathText.Split('/') | Where-Object { $_ -in '.', '..' -or $_ -cne $_.Trim() -or $_.EndsWith('.') }).Count) { return $null }
    $pathText
}

function Read-ScoreReview {
    param($Reviews)
    $result = [ordered]@{}
    foreach ($stage in 'requirements', 'build') {
        $review = Get-ScoreField $Reviews $stage
        $outcome = Get-ScoreField $review 'outcome'
        $path = ConvertTo-ScoreReviewPath (Get-ScoreField $review 'reviewPath')
        $result[$stage] = [ordered]@{
            outcome = if ($outcome -cin @('passed', 'failed')) { $outcome } else { 'unavailable' }
            reviewPath = $path
            criticalHighFindings = ConvertTo-ScoreDouble (Get-ScoreField $review 'criticalHighFindings') 0 1000000
        }
        $count = $result[$stage]['criticalHighFindings']
        if ($null -ne $count -and $count -ne [Math]::Floor($count)) { throw 'Invalid review finding count.' }
        if ($null -eq $path) { $result[$stage]['criticalHighFindings'] = $null }
    }
    $result
}

function Get-ScoreReviewMarkdown {
    param([Collections.IDictionary]$Score, [string]$Label)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]@("#### $Label stage reviews", '', '| Run | Review source | Outcome check | Review path (workspace-relative) | Critical/high (source only) |', '| --- | --- | --- | --- | --- |'))
    $trials = @(Get-ScoreList $Score 'trials')
    if (-not $trials.Count) { $lines.Add('| unavailable | requirements/build | unavailable | unavailable | unavailable |') }
    foreach ($trial in $trials) {
        $reviews = Read-ScoreReview (Get-ScoreField $trial 'sourceReviews')
        foreach ($stage in $reviews.Keys) {
            $review = $reviews[$stage]
            $count = if ($null -ne $review['criticalHighFindings']) { $review['criticalHighFindings'] } else { 'unavailable' }
            $path = if ($review['reviewPath']) { "``$($review['reviewPath'])``" } else { 'unavailable' }
            $lines.Add("| $($trial['run']) | $stage | $($review['outcome']) | $path | $count |")
        }
    }
    $lines -join "`n"
}

function Get-ScoreComparability {
    param($Base, $Head)
    $unknown = [Collections.Generic.List[string]]::new()
    $changed = [Collections.Generic.List[string]]::new()
    foreach ($key in @('scenario') + $script:CompatibilityFields) {
        $before = if ($key -eq 'scenario') { Get-ScoreField $Base 'scenario' } else { Get-ScoreField $Base 'compatibility', $key }
        $after = if ($key -eq 'scenario') { Get-ScoreField $Head 'scenario' } else { Get-ScoreField $Head 'compatibility', $key }
        if ($null -eq $before -or $null -eq $after) { $unknown.Add($key) }
        elseif ($before -cne $after) { $changed.Add($key) }
    }
    [pscustomobject]@{
        Status = if ($changed.Count) { 'incompatible' } elseif ($unknown.Count) { 'unknown' } else { 'compatible' }
        Unknown = @($unknown); Changed = @($changed)
    }
}

# --- Build a score from run results -------------------------------------------

function ConvertTo-BenchmarkRunSummary {
    <# .SYNOPSIS
    Reduces one run's result file (or the lack of one) to the figures the score uses.
    .DESCRIPTION
    sourceReviews preserves requirements/build readiness.checks.reviewOutcome and a safe
    workspace-relative readiness.reviewPath. Optional readiness.findingCounts must contain
    both critical and high as nonnegative integers (at most 500000 each); otherwise source
    severity is unavailable. Review files are not opened and overlapping sources are not summed.
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
        sourceReviews = Read-ScoreReview $null
    }
    if ($null -eq $Result) { return $trial }
    $trial['activity'] = Read-ScoreActivity (Get-ScoreField $Result 'metrics', 'activity')

    $stages = @(Get-ScoreList $Result 'stages')
    foreach ($name in 'requirements', 'build') {
        $stage = $stages | Where-Object { $_['name'] -eq $name } | Select-Object -First 1
        $outcome = Get-ScoreField $stage 'readiness', 'checks', 'reviewOutcome'
        $review = $trial['sourceReviews'][$name]
        $review['outcome'] = if ($outcome -is [bool]) { if ($outcome) { 'passed' } else { 'failed' } } else { 'unavailable' }
        $review['reviewPath'] = ConvertTo-ScoreReviewPath (Get-ScoreField $stage 'readiness', 'reviewPath')
        # Only typed, complete severity pairs count; never infer severity from a verdict or prose.
        $counts = Get-ScoreField $stage 'readiness', 'findingCounts'
        try {
            $critical = ConvertTo-ScoreInteger (Get-ScoreField $counts 'critical') 0 500000
            $high = ConvertTo-ScoreInteger (Get-ScoreField $counts 'high') 0 500000
            if ($review['reviewPath']) { $review['criticalHighFindings'] = $critical + $high }
        }
        catch { $review['criticalHighFindings'] = $null }
    }
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
    .DESCRIPTION
    compatibility contains SHA256 fingerprints of exact allowlisted metadata.compatibility
    values, not raw policy text or truncated display values. Missing, unsupported or oversized
    inputs (over 16384 characters) remain null. Fingerprints are comparison evidence, not attestation.
    #>
    [CmdletBinding()]
    param([AllowNull()][Collections.IDictionary]$Result)
    $compatibility = [ordered]@{}
    foreach ($key in $script:CompatibilityFields) {
        $value = Get-ScoreField $Result 'metadata', 'compatibility', $key
        # Fingerprint exact bounded inputs, not truncated display strings or arbitrary metadata.
        $text = if ($value -is [string]) { $value } elseif (Test-Number $value) { $value.ToString($script:Culture) } else { $null }
        $compatibility[$key] = if ($null -ne $text -and $text.Length -le 16384 -and
            ($text.Length -gt 0 -or $key -in 'roleModelPolicy', 'disabledMcpServers')) {
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
        } else { $null }
    }
    [ordered]@{
        model = Get-ScoreField $Result 'metadata', 'compatibility', 'model'
        cli = Get-ScoreField $Result 'metadata', 'compatibility', 'cli'
        powershell = Get-ScoreField $Result 'metadata', 'compatibility', 'powershell'
        squadSourceHash = Get-ScoreField $Result 'metadata', 'sourceHash'
        compatibility = $compatibility
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
        allRequested = [ordered]@{}
    }
    foreach ($pair in @(@('Seconds', 'seconds'), @('Credits', 'credits'))) {
        $values = @($Trial | ForEach-Object { Get-ScoreField $_ $pair[1] } | Where-Object { $null -ne $_ })
        $summary['allRequested']["$($pair[1])Covered"] = $values.Count
        $summary['allRequested']["total$($pair[0])"] = if ($values.Count) { [double]($values | Measure-Object -Sum).Sum } else { $null }
        $summary['allRequested']["average$($pair[0])"] = if ($values.Count) { [double]($values | Measure-Object -Average).Average } else { $null }
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
        compatibility = Read-ScoreCompatibility (Get-ScoreField $Identity 'compatibility')
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
    "doc quality $(Format-ScoreNumber $summary['quality'])/100 | functional $($summary['functional'])/$requested | workflow $($summary['workflow'])/$requested | avg scored-run time $time ($($runs['scored'])/$requested scored)"
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
    $hash = Get-ScoreField $Score 'source', 'squadSourceHash'
    $hash = if ($hash -is [string] -and $hash -cmatch '^[0-9a-fA-F]{7,64}$') { $hash } else { 'unavailable' }
    "$when, measured commit ``$commit``, measured squad source hash ``$hash``, model ``$model``, Copilot CLI ``$cli``, $count run$(if ($count -ne 1) { 's' }); not an identity of the current checkout"
}

function Get-ScoreRow {
    # The display text and the number compared for each measure of a score.
    param([Parameter(Mandatory)][Collections.IDictionary]$Score)
    $requested = $Score['runs']['requested']; $scored = $Score['runs']['scored']
    $summary = $Score['summary']
    $has = $scored -gt 0
    $findings = $summary['criticalHighFindings']
    $perRun = if ($has -and $null -ne $findings) { $findings / $scored }
    $rows = [ordered]@{
        quality = @{
            Label = 'Document quality (median, out of 100)'
            Text = if ($has) { Format-ScoreNumber $summary['quality'] } else { 'n/a' }
            Number = if ($has) { $summary['quality'] }
        }
        functional = @{ Label = 'Functional (runs passing)'; Text = "$($summary['functional'])/$requested"; Number = $summary['functional'] / $requested }
        workflow = @{ Label = 'Workflow (runs passing)'; Text = "$($summary['workflow'])/$requested"; Number = $summary['workflow'] / $requested }
        findings = @{
            Label = 'JUDGE-ONLY critical/high findings'
            Text = if ($null -ne $perRun) { "$findings ($(Format-ScoreNumber $perRun) per scored run)" } else { 'unavailable' }
            Number = $perRun
        }
        seconds = @{
            Label = 'Average time per scored run'
            Text = if ($null -ne $summary['averageSeconds']) { Format-ScoreDuration $summary['averageSeconds'] } else { 'n/a' }
            Number = $summary['averageSeconds']
        }
        credits = @{
            Label = 'Average credits per scored run'
            Text = if ($null -ne $summary['averageCredits']) { Format-ScoreNumber $summary['averageCredits'] } else { 'n/a' }
            Number = $summary['averageCredits']
        }
        scored = @{ Label = 'Runs that produced a score'; Text = "$scored/$requested"; Number = $scored / $requested }
    }
    foreach ($pair in @(@('Seconds', 'seconds', 'time'), @('Credits', 'credits', 'credits'))) {
        $all = Get-ScoreField $summary 'allRequested'
        $covered = Get-ScoreField $all "$($pair[1])Covered"
        $coverage = if ($null -ne $covered) { "$covered/$requested requested runs covered" } else { 'coverage unavailable' }
        foreach ($kind in 'total', 'average') {
            $value = Get-ScoreField $all "$kind$($pair[0])"
            $text = if ($null -eq $value) { 'unavailable' } elseif ($pair[1] -eq 'seconds') { Format-ScoreDuration $value } else { Format-ScoreNumber $value }
            $rows["all$kind$($pair[0])"] = @{
                Label = "All-requested $($pair[2]) ($kind observed)"
                Text = "$text; $coverage"
                Number = $null
            }
        }
    }
    $rows
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
    $Score = Read-ScoreData $Score
    if ($null -ne $EarlierScore) { $EarlierScore = Read-ScoreData $EarlierScore }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]@('# Benchmark score', '', "Measured: $(Get-ScoreProvenance $Score)."))
    if ($Score['source']['uncommittedChanges']) { $lines.Add('The squad source had uncommitted changes when this was measured.') }
    $lines.AddRange([string[]]@('', '| Measure | Result |', '| --- | --- |'))
    $rows = Get-ScoreRow $Score
    foreach ($row in $rows.Values) { $lines.Add("| $($row.Label) | $($row.Text) |") }
    $lines.Add('')
    $lines.Add("Scored-only averages use $($Score['runs']['scored']) scored run(s); all-requested totals/means use only the covered slots, including unscored trials, without imputing missing data.")
    $lines.Add('JUDGE-ONLY findings cover only the inputs supplied to the unchanged document judge, not whole-workflow risk coverage. Stage reviews are separate sources and are never added together; unavailable severity coverage is not zero.')
    $lines.Add((Get-ScoreReviewMarkdown -Score $Score -Label 'Latest'))
    if ($null -ne $EarlierScore) {
        $comparison = Get-ScoreComparability $EarlierScore $Score
        $lines.Add("Comparison identity: $($comparison.Status). Missing identities: $($comparison.Unknown -join ', '). Differing identities: $($comparison.Changed -join ', '). Figures are descriptive, not a controlled causal comparison.")
    }
    $lines.Add('')
    $lines.Add((Get-ActivityReportMarkdown -Earlier $EarlierScore -Latest $Score))
    if ($null -ne $EarlierScore) { $lines.Add("Earlier run: $(Get-ScoreProvenance $EarlierScore).") }
    else { $lines.Add('Earlier run: no previous local score was available.') }
    if ($Score['runs']['scored'] -gt 0) {
        $lines.AddRange([string[]]@('', '## Document quality by dimension (median, out of 20)', '', '| Dimension | Score |', '| --- | --- |'))
        foreach ($name in $script:Dimensions.Keys) { $lines.Add("| $($script:Dimensions[$name]) | $(Format-ScoreNumber $Score['summary']['dimensions'][$name]) |") }
    }
    $lines.AddRange([string[]]@('', '## Runs', '', '| Run | Scored | Quality | Functional | Workflow | JUDGE-ONLY critical/high | Time | Credits |', '| --- | --- | --- | --- | --- | --- | --- | --- |'))
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
    $Score = Read-ScoreData $Score
    if ($null -ne $EarlierScore) { $EarlierScore = Read-ScoreData $EarlierScore }
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
    Read-ScoreData $raw
}

function Read-ScoreData {
    param($Raw)
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
        allRequested = $null
    }
    $all = Get-ScoreField $raw 'summary', 'allRequested'
    if ($null -ne $all) {
        if ($all -isnot [Collections.IDictionary]) { throw 'Invalid all-requested metrics.' }
        $summary['allRequested'] = [ordered]@{}
        foreach ($pair in @(@('Seconds', 'seconds'), @('Credits', 'credits'))) {
            $covered = ConvertTo-ScoreInteger (Get-ScoreField $all "$($pair[1])Covered") 0 $requested
            $total = ConvertTo-ScoreDouble (Get-ScoreField $all "total$($pair[0])") 0 30000000
            $average = ConvertTo-ScoreDouble (Get-ScoreField $all "average$($pair[0])") 0 10000000
            if (($covered -eq 0 -and ($null -ne $total -or $null -ne $average)) -or
                ($covered -gt 0 -and ($null -eq $total -or $null -eq $average -or [Math]::Abs($total / $covered - $average) -gt 1e-6))) {
                throw 'Invalid all-requested coverage.'
            }
            $summary['allRequested']["$($pair[1])Covered"] = $covered
            $summary['allRequested']["total$($pair[0])"] = $total
            $summary['allRequested']["average$($pair[0])"] = $average
        }
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
    $hash = Get-ScoreField $raw 'source', 'squadSourceHash'
    $scenario = Get-ScoreField $raw 'scenario'
    $rawTrials = Get-ScoreField $raw 'trials'
    $trials = @()
    if ($null -ne $rawTrials) {
        if ($rawTrials -isnot [array] -or $rawTrials.Count -gt $requested) { throw 'Invalid trial list.' }
        $seen = [Collections.Generic.HashSet[int]]::new()
        $trials = @(
            foreach ($trial in $rawTrials) {
                $run = ConvertTo-ScoreInteger (Get-ScoreField $trial 'run') 1 $requested
                if (-not $seen.Add($run)) { throw 'Duplicate trial.' }
                $failedChecks = Get-ScoreField $trial 'failedChecks'
                if ($null -eq $failedChecks) { $failedChecks = @() }
                if ($failedChecks -isnot [array] -or @($failedChecks | Where-Object { $_ -isnot [string] }).Count) {
                    throw 'Invalid failed checks.'
                }
                $dimensions = $null
                if ((Get-ScoreField $trial 'scored') -eq $true) {
                    $dimensions = [ordered]@{}
                    foreach ($name in $script:Dimensions.Keys) {
                        $dimensions[$name] = ConvertTo-ScoreDouble (Get-ScoreField $trial 'dimensions', $name) 0 20
                        if ($null -eq $dimensions[$name]) { throw 'A trial dimension is missing.' }
                    }
                }
                [ordered]@{
                    run = $run; scored = (Get-ScoreField $trial 'scored') -eq $true
                    quality = ConvertTo-ScoreDouble (Get-ScoreField $trial 'quality') 0 100
                    dimensions = $dimensions
                    functional = (Get-ScoreField $trial 'functional') -eq $true
                    workflow = (Get-ScoreField $trial 'workflow') -eq $true
                    criticalHighFindings = ConvertTo-ScoreDouble (Get-ScoreField $trial 'criticalHighFindings') 0 1000000
                    seconds = ConvertTo-ScoreDouble (Get-ScoreField $trial 'seconds') 0 10000000
                    credits = ConvertTo-ScoreDouble (Get-ScoreField $trial 'credits') 0 10000000
                    failedChecks = @($failedChecks | Select-Object -First 12 | ForEach-Object { Format-SafeText $_ 60 })
                    note = if (Get-ScoreField $trial 'note') { Format-SafeText (Get-ScoreField $trial 'note') 120 } else { '' }
                    activity = Read-ScoreActivity (Get-ScoreField $trial 'activity')
                    sourceReviews = Read-ScoreReview (Get-ScoreField $trial 'sourceReviews')
                }
            }
        )
    }
    [ordered]@{
        schema = $script:Schema
        scenario = if ($scenario -is [string] -and $scenario -cmatch '^[A-Za-z0-9._-]{1,80}$') { $scenario } else { $null }
        measuredAt = ConvertTo-ScoreTime (Get-ScoreField $raw 'measuredAt')
        source = [ordered]@{
            commit = if ($commit -is [string] -and $commit -cmatch '^[0-9a-f]{7,40}$') { $commit } else { 'unknown' }
            squadSourceHash = if ($hash -is [string] -and $hash -cmatch '^[0-9a-fA-F]{7,64}$') { $hash } else { $null }
            uncommittedChanges = (Get-ScoreField $raw 'source', 'uncommittedChanges') -eq $true
        }
        environment = [ordered]@{
            model = Format-SafeText (Get-ScoreField $raw 'environment', 'model')
            cli = Format-SafeText (Get-ScoreField $raw 'environment', 'cli')
            powershell = if ((Get-ScoreField $raw 'environment', 'powershell') -cmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$') {
                Get-ScoreField $raw 'environment', 'powershell'
            } else { $null }
        }
        compatibility = Read-ScoreCompatibility (Get-ScoreField $raw 'compatibility')
        runs = [ordered]@{ requested = $requested; scored = $scored; failed = $requested - $scored }
        summary = $summary
        trials = $trials
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
        'findings' { "$sign$(Format-ScoreNumber $size) per scored run" }
        default { "$sign$(Format-ScoreNumber $size)" }
    }
}

function Compare-BenchmarkScore {
    <# .SYNOPSIS
    Describes how a pull request's score differs from its base. Warns about lower scores and failed runs; never fails.
    .DESCRIPTION
    Displays descriptive differences, explicitly flagging missing or incompatible executing identities.
    A missing or unreadable score only changes what is shown. Returns Warnings, Notes,
    Comparability and the Markdown comment, never authorization or a controlled causal claim.
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
    if ($null -ne $Base) { $Base = Read-ScoreData $Base }
    if ($null -ne $Head) { $Head = Read-ScoreData $Head }
    $warnings = [Collections.Generic.List[string]]::new()
    $notes = [Collections.Generic.List[string]]::new()
    $baseRows = if ($null -ne $Base) { Get-ScoreRow $Base }
    $headRows = if ($null -ne $Head) { Get-ScoreRow $Head }
    $mode = if ($null -ne $Base -and $null -ne $Head -and -not $Unchanged) { 'compare' } elseif ($null -ne $Head) { 'head' } elseif ($null -ne $Base) { 'base' } else { 'none' }
    $comparability = 'unavailable'
    if ($null -ne $Base -and $null -ne $Head) {
        $identity = Get-ScoreComparability $Base $Head
        $comparability = $identity.Status
        $notes.Add("Comparison identity: $comparability. Descriptive differences are not evidence of a controlled causal comparison.")
        if ($identity.Unknown.Count) { $notes.Add("Missing/invalid compatibility identities: $($identity.Unknown -join ', '). Legacy or incomplete evidence is unavailable, not a match.") }
        if ($identity.Changed.Count) { $notes.Add("Incompatible compatibility identities: $($identity.Changed -join ', ').") }
    }
    elseif ($mode -ne 'none') {
        $identity = Get-ScoreComparability $Base $Head
        $notes.Add('Comparison identity: unavailable (two scores are required).')
        $notes.Add("Missing/invalid compatibility identities on one or both sides: $($identity.Unknown -join ', ').")
    }

    if ($mode -eq 'compare') {
        $b = $Base['summary']; $h = $Head['summary']
        if ($Base['runs']['scored'] -eq 0) { $notes.Add('The base score has no scored runs, so only this pull request''s figures are meaningful.') }
        elseif ($Head['runs']['scored'] -gt 0) {
            if ($h['quality'] -lt $b['quality'] - 1e-9) { $warnings.Add("Document quality is lower than on the base branch: $(Format-ScoreNumber $h['quality']) vs $(Format-ScoreNumber $b['quality']).") }
            $lower = @($script:Dimensions.Keys | Where-Object { $h['dimensions'][$_] -lt $b['dimensions'][$_] - 1e-9 })
            if ($lower.Count) { $warnings.Add('Lower quality dimension medians than on the base branch: ' + (($lower | ForEach-Object { "$($script:Dimensions[$_]) $(Format-ScoreNumber $h['dimensions'][$_]) vs $(Format-ScoreNumber $b['dimensions'][$_])" }) -join ', ') + '.') }
            if ($headRows.findings.Number -gt $baseRows.findings.Number + 1e-9) { $warnings.Add("More JUDGE-ONLY critical/high findings per scored run than on the base branch: $(Format-ScoreNumber $headRows.findings.Number) vs $(Format-ScoreNumber $baseRows.findings.Number).") }
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
        $lines.Add('JUDGE-ONLY findings cover only the supplied document-judge inputs, not whole-workflow risk coverage. Requirements/build reviews are separate, potentially overlapping sources, never summed; unavailable severity coverage is not zero.')
        $lines.Add('Scored-only averages use each score''s scored-run count. All-requested totals/means include measured unscored trials and use the explicitly covered slots, not imputed missing data.')
        if ($null -ne $Base) { $lines.Add((Get-ScoreReviewMarkdown -Score $Base -Label 'Base branch')) }
        if ($null -ne $Head) { $lines.Add((Get-ScoreReviewMarkdown -Score $Head -Label 'This pull request')) }
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
    [pscustomobject]@{ Warnings = @($warnings); Notes = @($notes); Comparability = $comparability; Markdown = ($lines -join "`n") + "`n" }
}

Export-ModuleMember -Function ConvertTo-BenchmarkRunSummary, Get-BenchmarkRunIdentity, ConvertTo-BenchmarkScore, Get-BenchmarkBadgeText, Get-BenchmarkBadgeSvg, Get-BenchmarkReportMarkdown, Write-BenchmarkScore, Read-BenchmarkScore, Compare-BenchmarkScore
