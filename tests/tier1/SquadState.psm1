# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Reads a squad state tree into the model the Tier 1 contract asserts on, and can
# generate a schema-correct fixture.
#
# The fixture exists to prove the assertions fire, not to prove the squad works: a
# fixture the author wrote to satisfy their own assertions is circular evidence. Its
# real job is to be MUTATED - each mutation in Assertions.Tests.ps1 breaks one rule and
# the contract must catch it. An assertion that never fails on a broken tree is worse
# than no assertion, because it reports success.

#Requires -Version 7.4

Set-StrictMode -Version Latest

# Field order is contractual: the ledger rewrite reparses these blocks. Rates and money
# are deliberately absent - a block records consumption, the ledger prices it.
$script:ConsumptionFields = @(
    'model', 'model_source', 'priced_as', 'model_tier', 'internal_turns'
    'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens'
    'basis'
)

$script:ModelSources = @('dispatch-reported', 'agent-pinned', 'operator-declared', 'session-inherited', 'cli-pinned', 'unresolved')
$script:Bases = @('estimated', 'tier-default')
$script:Modes = @('interactive', 'autonomous', 'autopilot')
$script:ApprovalChannels = @('in-chat', 'github-issue', 'webhook')

# Files Init seeds eagerly. history/<agent>.md is deliberately absent: it is created on
# first dispatch, and its presence is the proof that a dispatch happened.
$script:EagerStateFiles = @(
    'team.md', 'routing.md', 'decisions.md', 'state.json'
    'notifications.md', 'consumption.md', 'consumption-rates.md'
)

function Get-ConsumptionBlock {
    <#
    .SYNOPSIS
        Extracts every per-dispatch consumption block from a history file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw

    foreach ($match in [regex]::Matches($raw, '(?ms)^####\s+Consumption(?<orchestration>\s+[-\u2014]\s+Orchestration)?\s*$\r?\n+```json\r?\n(?<json>.*?)\r?\n```')) {
        $json = $match.Groups['json'].Value
        $parsed = $null
        $parseError = $null
        try { $parsed = $json | ConvertFrom-Json -AsHashtable }
        catch { $parseError = $_.Exception.Message }

        # Order is read from the raw text, because ConvertFrom-Json does not preserve it.
        $order = @([regex]::Matches($json, '(?m)^\s*"([a-z_]+)"\s*:') | ForEach-Object { $_.Groups[1].Value })

        # A bare number is the contract. '~8,400 (estimated)' parses as a string and drops
        # the dispatch out of every later aggregate, so the shape is checked, not just the value.
        $nonNumeric = @(
            if ($parsed) {
                foreach ($field in $order) {
                    if ($field -in 'model', 'model_source', 'priced_as', 'model_tier', 'basis') { continue }
                    if ($parsed[$field] -isnot [int] -and $parsed[$field] -isnot [long] -and $parsed[$field] -isnot [double] -and $parsed[$field] -isnot [decimal]) {
                        $field
                    }
                }
            }
        )

        [pscustomobject]@{
            Source          = Split-Path $Path -Leaf
            IsOrchestration = [bool]$match.Groups['orchestration'].Success
            Fields          = $parsed
            Order           = $order
            NonNumeric      = $nonNumeric
            ParseError      = $parseError
        }
    }
}

function Get-HistoryEntry {
    <#
    .SYNOPSIS
        Splits a history file into its dispatch entries.
    .DESCRIPTION
        Entries are the level-2 and level-3 headings; the consumption block's own heading
        is level four and is deliberately not one. An entry that names no artifact is the
        gap this exists to expose: 'Deliverable: N/A - inline verdict' produces no path
        for the existence check to reject, so the stage reports complete having written
        nothing at all.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw
    $headings = @([regex]::Matches($raw, '(?m)^#{2,3}[ \t]+(?<title>.+)$'))

    for ($index = 0; $index -lt $headings.Count; $index++) {
        $start = $headings[$index].Index
        $end = if ($index + 1 -lt $headings.Count) { $headings[$index + 1].Index } else { $raw.Length }
        $body = $raw.Substring($start, $end - $start)
        $declared = @(
            foreach ($line in [regex]::Matches($body, '(?m)^\s*\*\s*Deliverable:\s*(?<value>.+)$')) {
                Get-DeliverablePathToken $line.Groups['value'].Value
            }
        )

        [pscustomobject]@{
            Source        = Split-Path $Path -Leaf
            Agent         = [System.IO.Path]::GetFileNameWithoutExtension($Path)
            Title         = $headings[$index].Groups['title'].Value.Trim()
            NamesArtifact = $declared.Count -gt 0
        }
    }
}

function Get-DeliverablePathToken {
    <#
    .SYNOPSIS
        Reads the paths one `* Deliverable:` value names.
    .DESCRIPTION
        Backticked tokens are read first, because an entry writes its path in backticks
        and its size in plain prose and reading unquoted words would register
        '(~5,000 words)' as a file. When nothing was backticked, one bare path is
        accepted: a live run wrote its artifact to the right root and named it correctly
        without the backticks, and rejecting that reports a missing deliverable for a
        file sitting on disk. The bare form must still look like a path, so
        'N/A - inline verdict, no artifact written' stays rejected.
    #>
    param([string]$Value)

    $tokens = @([regex]::Matches($Value, '`(?<path>[^`]+)`') | ForEach-Object { $_.Groups['path'].Value })

    if (-not $tokens) {
        $bare = ($Value -split '\s\(')[0].Trim().TrimEnd(',', ';', '.')
        if ($bare -match '/' -and $bare -match '\.[A-Za-z0-9]{1,5}$') { $tokens = @($bare) }
    }

    # Never split on whitespace: an agent's name carries spaces, so
    # 'history/Squad Researcher.md' would truncate to 'history/Squad'. A fan-out
    # summarized as 'history/*.md' or 'root/{a.md,b.md}' names a set, not an artifact.
    @($tokens |
        ForEach-Object { $_.Trim().TrimEnd(',', ';', '.') } |
        Where-Object { $_ -and $_ -notmatch '[*?{}]' })
}

function Get-DeliverableEntry {
    <#
    .SYNOPSIS
        Extracts the `* Deliverable:` paths every history entry declares.
    .DESCRIPTION
        A single entry may legitimately name several paths. See Get-DeliverablePathToken
        for what counts as a path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw
    foreach ($line in [regex]::Matches($raw, '(?m)^\s*\*\s*Deliverable:\s*(?<value>.+)$')) {
        foreach ($candidate in (Get-DeliverablePathToken $line.Groups['value'].Value)) {
            [pscustomobject]@{
                Source = Split-Path $Path -Leaf
                Agent  = [System.IO.Path]::GetFileNameWithoutExtension($Path)
                Path   = $candidate -replace '\\', '/'
            }
        }
    }
}

function Get-DeliverableTail {
    <#
    .SYNOPSIS
        Strips the tracking prefix and any sub-squad root from a deliverable path.
    .DESCRIPTION
        History is append-only, so a promotion cannot rewrite the paths already recorded
        in it. An entry written before a promotion still reads
        '.copilot-tracking/research/x.md' while the file now sits under
        'members/<name>/researches/'. Comparing tails makes both forms equal, so the
        contract reports a role that wrote to the wrong folder without also reporting
        every entry a promotion left behind.
    #>
    param([string]$Path)

    ($Path -replace '^\./', '') -replace '^\.copilot-tracking/(squad/members/[^/]+/)?', ''
}

function Get-LedgerTable {
    <#
    .SYNOPSIS
        Parses one markdown table out of consumption.md by its heading.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$Heading
    )

    # Built by concatenation: in a double-quoted string the anchor '$' followed by '('
    # is parsed as a subexpression and the pattern is silently destroyed.
    $pattern = '(?ms)^##\s+' + [regex]::Escape($Heading) + '\s*$(?<body>.*?)(?=^##\s|\z)'
    $section = [regex]::Match($Content, $pattern)
    if (-not $section.Success) { return @() }

    $rows = @()
    foreach ($line in ($section.Groups['body'].Value -split '\r?\n')) {
        if ($line -notmatch '^\s*\|') { continue }
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') { continue }

        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim() })
        if ($cells[0] -match '^(Role|-+)$') { continue }
        $rows += , $cells
    }

    $rows
}

function Get-LedgerRoleKey {
    <#
    .SYNOPSIS
        Strips a trailing annotation so a Usage & Cost row joins its Attribution row.
    #>
    param([string]$Label)

    # A run labelled a row 'orchestration (Turns 1-3)'. The annotation is against the
    # writing rule, but a reader that cannot join the two tables loses the whole ledger.
    ($Label -replace '\s*\(.*$', '').Trim()
}

function ConvertTo-LedgerNumber {
    <#
    .SYNOPSIS
        Strips the bold and currency markup a ledger total carries.
    #>
    param([string]$Value)

    # One character class rather than chained -replace: the comma in `-replace a, b`
    # binds tighter than the operator, so chaining without parentheses silently builds
    # an array instead of applying three replacements.
    $clean = ($Value -replace '[*$,]', '').Trim()
    if ($clean -match '^-?\d+(\.\d+)?$') { return [double]$clean }
    return $null
}

function Get-LedgerDecimal {
    <#
    .SYNOPSIS
        Counts the decimals a ledger cell displays.
    .DESCRIPTION
        The ledger prints role rows at four decimals and the run total at two, so a sum
        compared at full precision fails on display rounding alone. Reading the printed
        precision back keeps the comparison exact at whatever the ledger chose, instead
        of widening a tolerance until real drift fits inside it. Two decimals is the
        floor, so a total printed as a whole dollar cannot pass on rounding slack.
    #>
    param([string]$Value)

    $clean = ($Value -replace '[*$,]', '').Trim()
    if ($clean -match '^-?\d+\.(\d+)$') { return [math]::Max(2, $Matches[1].Length) }
    return 2
}

function Get-MarkdownTable {
    <#
    .SYNOPSIS
        Reads every markdown table in a document as rows keyed by their column headers.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Content = ''
    )

    $tables = @()
    $header = $null
    $rows = $null

    foreach ($line in ($Content -split '\r?\n')) {
        if ($line -notmatch '^\s*\|') {
            if ($header) { $tables += , [pscustomobject]@{ Header = $header; Rows = $rows } }
            $header = $null
            $rows = $null
            continue
        }

        # The delimiter row separates header from body and carries no data of its own.
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') { continue }

        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim().Trim('`').Trim() })

        if (-not $header) {
            $header = $cells
            $rows = @()
            continue
        }

        $row = [ordered]@{}
        for ($i = 0; $i -lt $header.Count; $i++) {
            $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' }
        }
        $rows += , $row
    }

    if ($header) { $tables += , [pscustomobject]@{ Header = $header; Rows = $rows } }
    $tables
}

function Get-RateTable {
    <#
    .SYNOPSIS
        Reads the per-model and tier-fallback rate tables out of consumption-rates.md.
    .DESCRIPTION
        Tables are selected by column header and cells are read by header name, never by
        position. The shipped table carries Tier and Notes columns around the four rate
        columns, so a positional read lands on the wrong cells, and a model name like
        'Claude Sonnet 4.6' does not survive a key pattern that forbids spaces. Selecting
        on the four rate headers also keeps the dispatch-size estimator's class rows out:
        they are five numeric-looking columns that a looser match would happily register
        as a price.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Content = ''
    )

    $rates = @{}
    if (-not $Content) { return $rates }

    $rateColumns = @('Input', 'Cached', 'Cache write', 'Output')

    foreach ($table in (Get-MarkdownTable -Content $Content)) {
        if (@($rateColumns | Where-Object { $_ -notin $table.Header }).Count -gt 0) { continue }

        # 'Priced as' names the rate row on the tier-fallback table, whose first column is
        # the tier. Everywhere else the first column is the model itself.
        $keyColumn = if ('Priced as' -in $table.Header) { 'Priced as' } else { $table.Header[0] }

        foreach ($row in $table.Rows) {
            $key = $row[$keyColumn]

            # The per-model table is read first, so it stays authoritative over the
            # tier-fallback duplicates of the same model.
            if (-not $key -or $rates.ContainsKey($key)) { continue }

            $numbers = @($rateColumns | ForEach-Object { ConvertTo-LedgerNumber $row[$_] })
            if ($numbers -contains $null) { continue }

            $rates[$key] = @{
                input       = $numbers[0]
                cached      = $numbers[1]
                cache_write = $numbers[2]
                output      = $numbers[3]
                tier        = if ('Tier' -in $table.Header) { $row['Tier'] } else { $null }
            }
        }
    }

    $rates
}

function Get-SquadStateModel {
    <#
    .SYNOPSIS
        Reads a squad root into the collections the Tier 1 contract asserts on.
    .PARAMETER SquadRoot
        A squad root: .copilot-tracking/squad/ or .copilot-tracking/squad/members/<name>/.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SquadRoot
    )

    function Read-Text {
        param([string]$Name)
        $path = Join-Path $SquadRoot $Name
        if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw } else { $null }
    }

    $stateJson = $null
    $statePath = Join-Path $SquadRoot 'state.json'
    if (Test-Path -LiteralPath $statePath) {
        try { $stateJson = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable } catch { $stateJson = $null }
    }

    $historyDirectory = Join-Path $SquadRoot 'history'
    $historyFiles = @(
        if (Test-Path -LiteralPath $historyDirectory) {
            Get-ChildItem -LiteralPath $historyDirectory -Filter '*.md' -File
        }
    )

    $blocks = @(foreach ($file in $historyFiles) { Get-ConsumptionBlock -Path $file.FullName })

    # A template copied out of a line-numbered read view keeps the viewer's gutter, which
    # leaves the file well formed to the eye and unparseable to everything downstream.
    # Scoped to state files: a deliverable may legitimately open with a numbered list.
    $numberedFiles = @(
        foreach ($file in (@(Get-ChildItem -LiteralPath $SquadRoot -Filter '*.md' -File -ErrorAction SilentlyContinue) + $historyFiles)) {
            $lines = @(Get-Content -LiteralPath $file.FullName -TotalCount 12 -ErrorAction SilentlyContinue)
            $gutter = @($lines | Where-Object { $_ -match '^\s*\d+[.:]\s' })
            if ($gutter.Count -ge 3) { $file.Name }
        }
    )

    $ledgerContent = Read-Text 'consumption.md'
    $ratesContent = Read-Text 'consumption-rates.md'
    $teamContent = Read-Text 'team.md'

    # The ledger rewrite matches a history file back to its roster row by file name, so
    # the roster is what makes a basename legal. Alternates count: a dispatch can be
    # routed to one and it writes its own history file.
    $roleAgents = @{}
    $rosterAgents = @(
        foreach ($table in (Get-MarkdownTable -Content $teamContent)) {
            if ('Agent Name (Primary)' -notin $table.Header) { continue }
            foreach ($row in $table.Rows) {
                $names = @(
                    if ($row['Agent Name (Primary)']) { $row['Agent Name (Primary)'] }
                    if ('Alternate Agents' -in $table.Header) {
                        foreach ($alternate in ($row['Alternate Agents'] -split ',')) {
                            $trimmed = $alternate.Trim()
                            if ($trimmed -and $trimmed -notmatch '^[-\u2014]$') { $trimmed }
                        }
                    }
                )
                if ('Role' -in $table.Header -and $row['Role']) { $roleAgents[$row['Role']] = $names }
                $names
            }
        }
    ) | Sort-Object -Unique

    # Only this file holds token rates, so every block's rates are checked against it.
    $rates = Get-RateTable -Content $ratesContent

    # The Deliverable Root cell is an operator declaration, not a default: a role writes
    # there or it escalates. Roots are resolved against the project root first and the
    # squad root second, because a federation sub-squad's roots are rebased under its own.
    $projectRoot = $SquadRoot
    if (($SquadRoot -replace '\\', '/') -match '^(?<base>.*?)/?\.copilot-tracking(/|$)') {
        $projectRoot = if ($Matches['base']) { $Matches['base'] } else { '.' }
    }

    # A move that joined a project-root-relative destination onto the tracking directory
    # instead of the project root leaves an empty .copilot-tracking inside .copilot-tracking.
    $trackingRoot = Join-Path $projectRoot '.copilot-tracking'
    $nestedTracking = @(
        if (Test-Path -LiteralPath $trackingRoot) {
            Get-ChildItem -LiteralPath $trackingRoot -Recurse -Directory -Force -Filter '.copilot-tracking' -ErrorAction SilentlyContinue |
                ForEach-Object { $_.FullName }
        }
    )

    $agentRoots = @{}
    $roleRoots = @{}
    foreach ($table in (Get-MarkdownTable -Content $teamContent)) {
        if ('Deliverable Root' -notin $table.Header -or 'Agent Name (Primary)' -notin $table.Header) { continue }
        foreach ($row in $table.Rows) {
            # '—' and '(squad state)' are declarations that the role owns no artifact root.
            $root = ($row['Deliverable Root'] -replace '`', '').Trim() -replace '\\', '/'
            if ($root -notmatch '/') { continue }

            if ('Role' -in $table.Header -and $row['Role']) { $roleRoots[$row['Role']] = $root }
            foreach ($agent in @($row['Agent Name (Primary)']) + @(
                    if ('Alternate Agents' -in $table.Header) { $row['Alternate Agents'] -split ',' }
                )) {
                $name = "$agent".Trim()
                if ($name -and $name -notmatch '^[-\u2014]$') { $agentRoots[$name] = $root }
            }
        }
    }

    function Resolve-Deliverable {
        param([string]$Relative)
        # The tail attempt resolves a path recorded before a promotion moved the file.
        foreach ($candidate in @(
                (Join-Path $projectRoot $Relative)
                (Join-Path $SquadRoot $Relative)
                (Join-Path $SquadRoot (Get-DeliverableTail $Relative))
            )) {
            # Get-Item, not Resolve-Path: only FileInfo.FullName expands an 8.3 short path,
            # and the orphan scan compares against FileInfo.FullName.
            if (Test-Path -LiteralPath $candidate) { return (Get-Item -LiteralPath $candidate).FullName }
        }
        return $null
    }

    # The Scribe's own entries name the state files a turn wrote, not a deliverable, and
    # they cite them across roots - a sub-squad turn names federation-root files and vice
    # versa. It is not a dispatched stage, so proof of dispatch does not apply to it.
    # Loop and run summaries are per-run rollups rather than dispatch records.
    #
    # A federation root's history/ names sub-squads rather than agents: those entries
    # record which sub-squad a turn routed to and carry a Reference, not a Deliverable.
    # The dispatch records for that turn live under the sub-squad's own root.
    $isFederationRoot = Test-Path -LiteralPath (Join-Path $SquadRoot 'federation.md')

    $dispatchHistory = @(
        if (-not $isFederationRoot) {
            $historyFiles | Where-Object {
                $_.BaseName -ne 'Squad Scribe' -and $_.BaseName -notmatch '^(autonomous-loop|autopilot-run)-'
            }
        }
    )

    $declared = @(foreach ($file in $dispatchHistory) { Get-DeliverableEntry -Path $file.FullName })
    $entries = @(foreach ($file in $dispatchHistory) { Get-HistoryEntry -Path $file.FullName })

    $artifactlessEntries = @(
        foreach ($entry in $entries) {
            if (-not $entry.NamesArtifact) { "$($entry.Source): $($entry.Title)" }
        }
    )

    $deliverables = @(
        foreach ($entry in $declared) {
            $resolved = Resolve-Deliverable $entry.Path
            $root = if ($agentRoots.ContainsKey($entry.Agent)) { $agentRoots[$entry.Agent] } else { $null }

            # Compared as tails, not as written: a promotion rebases the roster's roots
            # but cannot edit the append-only entries that predate it.
            $declaredPath = Get-DeliverableTail $entry.Path
            $prefix = (Get-DeliverableTail (($root -split '<')[0])).TrimEnd('/')

            [pscustomobject]@{
                Source     = $entry.Source
                Agent      = $entry.Agent
                Path       = $entry.Path
                Resolved   = $resolved
                Root       = $root
                UnderRoot  = -not $root -or $declaredPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
            }
        }
    )

    # An artifact under a role's root that no entry claims is a dispatch nobody recorded.
    # Scoped to markdown at most one directory below the root's literal prefix: deeper
    # trees are working directories whose scratch files are legitimately unclaimed.
    $claimed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in ($deliverables | Where-Object { $_.Resolved })) { [void]$claimed.Add($item.Resolved) }

    $stateRoot = if (Test-Path -LiteralPath $SquadRoot) { (Get-Item -LiteralPath $SquadRoot).FullName } else { $SquadRoot }

    $orphanArtifacts = @(
        foreach ($root in (@($roleRoots.Values) | Sort-Object -Unique)) {
            if ($root -notmatch '\.copilot-tracking/') { continue }
            $literal = (($root -split '<')[0]).TrimEnd('/')

            foreach ($base in (@($projectRoot, $SquadRoot) | Sort-Object -Unique)) {
                $directory = Join-Path $base $literal
                if (-not (Test-Path -LiteralPath $directory)) { continue }

                # The scribe's root is the squad root itself. Squad state is written by the
                # Scribe rather than claimed by a history entry, so scanning it would report
                # every state file as an orphan. Enumeration runs from the normalized path so
                # both sides of the claimed-set comparison survive an 8.3 short path.
                $resolved = (Get-Item -LiteralPath $directory).FullName
                if ($resolved -eq $stateRoot -or $resolved.StartsWith($stateRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { continue }

                $scan = @(Get-ChildItem -LiteralPath $resolved -Filter '*.md' -File -ErrorAction SilentlyContinue)
                foreach ($child in @(Get-ChildItem -LiteralPath $resolved -Directory -ErrorAction SilentlyContinue)) {
                    $scan += @(Get-ChildItem -LiteralPath $child.FullName -Filter '*.md' -File -ErrorAction SilentlyContinue)
                }

                foreach ($file in $scan) {
                    if (-not $claimed.Contains($file.FullName)) { $file.FullName }
                }
            }
        }
    ) | Sort-Object -Unique

    $calibration = 1.0
    $observations = 0
    if ($ratesContent) {
        $factor = [regex]::Match($ratesContent, '(?im)^\s*[*-]?\s*`?calibration_factor`?\s*[:=]\s*([0-9.]+)')
        if ($factor.Success) { $calibration = [double]$factor.Groups[1].Value }
        $seen = [regex]::Match($ratesContent, '(?im)^\s*[*-]?\s*`?observations`?\s*[:=]\s*([0-9]+)')
        if ($seen.Success) { $observations = [int]$seen.Groups[1].Value }
    }

    @{
        SquadRoot        = $SquadRoot
        Exists           = Test-Path -LiteralPath $SquadRoot
        EagerFiles       = @($script:EagerStateFiles | ForEach-Object {
                @{ Name = $_; Present = Test-Path -LiteralPath (Join-Path $SquadRoot $_) }
            })
        HasHistoryDir    = Test-Path -LiteralPath $historyDirectory
        HistoryFiles     = $historyFiles
        HistoryNames     = @($historyFiles | ForEach-Object { $_.BaseName })
        NumberedFiles    = @($numberedFiles)
        State            = $stateJson
        Team             = $teamContent
        RosterAgents     = @($rosterAgents)
        RoleAgents       = $roleAgents
        AgentRoots       = $agentRoots
        RoleRoots        = $roleRoots
        Deliverables     = @($deliverables)
        ArtifactlessEntries = @($artifactlessEntries)
        OrphanArtifacts  = @($orphanArtifacts)
        NestedTracking   = @($nestedTracking)
        Routing          = Read-Text 'routing.md'
        Decisions        = Read-Text 'decisions.md'
        Notifications    = Read-Text 'notifications.md'
        Ledger           = $ledgerContent
        RatesContent     = $ratesContent
        Rates            = $rates
        Calibration      = $calibration
        Observations     = $observations
        Blocks           = $blocks
        DispatchBlocks   = @($blocks | Where-Object { -not $_.IsOrchestration })
        OrchestrationBlocks = @($blocks | Where-Object { $_.IsOrchestration })
        Attribution      = @(if ($ledgerContent) { Get-LedgerTable -Content $ledgerContent -Heading 'Attribution' })
        UsageAndCost     = @(if ($ledgerContent) { Get-LedgerTable -Content $ledgerContent -Heading 'Usage & Cost' })
        ConsumptionFields = $script:ConsumptionFields
        ModelSources     = $script:ModelSources
        Bases            = $script:Bases
        Modes            = $script:Modes
        ApprovalChannels = $script:ApprovalChannels
    }
}

Export-ModuleMember -Function Get-SquadStateModel, Get-ConsumptionBlock, Get-DeliverableEntry, Get-DeliverableTail, Get-HistoryEntry, Get-LedgerTable, Get-LedgerRoleKey, Get-MarkdownTable, Get-RateTable, ConvertTo-LedgerNumber, Get-LedgerDecimal
