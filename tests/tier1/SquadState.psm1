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

$script:ConnectorBindingColumns = @(
    'Binding ID', 'Connector ID', 'Manifest', 'Endpoint Kind', 'Role Mode',
    'Target Kind', 'Target', 'Member Name', 'Added Role', 'Aligned Role',
    'Default Execution'
)
$connectorDispatchHelper = Join-Path $PSScriptRoot '..' '..' 'squad-src' '.github' 'skills' 'squad' 'scripts' 'Resolve-SquadConnectorHistory.ps1'
if (-not (Test-Path -LiteralPath $connectorDispatchHelper -PathType Leaf)) {
    throw "The connector dispatch helper was not found at '$connectorDispatchHelper'."
}
. $connectorDispatchHelper

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
$script:PreflightFields = @(
    'runId', 'roundId', 'ceilingUsd', 'evaluatedSpendUsd', 'remainingUsd'
    'plannedDispatches', 'projectedCostUsd', 'reserveMultiplier'
    'admissionCostUsd', 'confidence', 'basis', 'decision', 'reason'
)
$script:PreflightConfidences = @('not-applicable', 'low', 'medium')
$script:PreflightBases = @('not-requested', 'estimated', 'calibrated')
$script:PreflightDecisions = @('not-requested', 'within-ceiling', 'over-ceiling', 'approved-over-ceiling', 'cannot-confirm')

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

function Get-RoutingIdentityBullets {
    <#
    .SYNOPSIS
        Extracts the optional routing-identity bullets beneath each Consumption block
        in a history file, per model-routing.md's Identity Bullets contract.
    .DESCRIPTION
        The four bullets - Requested model, Effective model, Observed model, Route
        rationale - are additive narrative content, never a JSON key. A no-policy
        dispatch omits all four, so absence is a valid, expected result rather than a
        parse failure: callers assert on HasBullets, not on this returning nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw

    foreach ($match in [regex]::Matches($raw, '(?ms)^####\s+Consumption(?:\s+[-\u2014]\s+Orchestration)?\s*$\r?\n+```json\r?\n.*?\r?\n```(?<bullets>(?:\r?\n[ \t]*\*[ \t]*\*\*[^\r\n]+)*)')) {
        $bulletBlock = $match.Groups['bullets'].Value
        $labels = @(
            [regex]::Matches($bulletBlock, '(?m)^[ \t]*\*[ \t]*\*\*(?<label>[^*]+)\*\*[ \t]*(?:\u2014|-)[ \t]*(?<value>.+)$') |
            ForEach-Object { [pscustomobject]@{ Label = $_.Groups['label'].Value.Trim(); Value = $_.Groups['value'].Value.Trim() } }
        )

        [pscustomobject]@{
            Source     = Split-Path $Path -Leaf
            HasBullets = $labels.Count -gt 0
            Labels     = @($labels | ForEach-Object { $_.Label })
            Values     = $labels
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

        $preflightRef = [regex]::Match($body, '(?m)^\s*\*\s*Cost Preflight Ref:\s*`(?<value>[^`]+)`\s*$')
        $preflightSlot = [regex]::Match($body, '(?m)^\s*\*\s*Cost Preflight Slot:\s*(?<value>\S+)\s*$')
        $memberName = [regex]::Match($body, '(?m)^\s*\*\s*Member Name:\s*(?<value>.+?)\s*$')
        $provenanceLine = [regex]::Match($body, '(?m)^\s*\*\s*External provenance:\s*(?<value>.+?)\s*$')
        $provenance = if ($provenanceLine.Success) {
            [regex]::Match(
                $provenanceLine.Groups['value'].Value,
                '^connector=(?<connector>[^;]+);\s*binding=(?<binding>[^;]+);\s*endpoint=(?<endpoint>[^;]+);\s*mode=(?<mode>[^;]+);\s*target=(?<target>.+)$')
        }
        else { $null }
        $verification = [regex]::Match($body, '(?m)^\s*\*\s*Verification:\s*(?<value>.+?)\s*$')
        $unmetered = [regex]::Match($body, '(?m)^\s*\*\s*External-unmetered:\s*connector=(?<value>.+?)\s*$')

        [pscustomobject]@{
            Source                    = Split-Path $Path -Leaf
            Agent                     = [System.IO.Path]::GetFileNameWithoutExtension($Path)
            Title                     = $headings[$index].Groups['title'].Value.Trim()
            DeliverablePaths          = $declared
            NamesArtifact             = $declared.Count -gt 0
            PreflightRef              = if ($preflightRef.Success) { $preflightRef.Groups['value'].Value } else { $null }
            PreflightSlot             = if ($preflightSlot.Success) { $preflightSlot.Groups['value'].Value } else { $null }
            MemberName                = if ($memberName.Success) { $memberName.Groups['value'].Value.Trim() } else { '' }
            HasExternalProvenance      = $provenanceLine.Success
            ExternalProvenanceValid    = $null -ne $provenance -and $provenance.Success
            ExternalConnectorId        = if ($null -ne $provenance -and $provenance.Success) { $provenance.Groups['connector'].Value.Trim() } else { '' }
            ExternalBindingId          = if ($null -ne $provenance -and $provenance.Success) { $provenance.Groups['binding'].Value.Trim() } else { '' }
            ExternalEndpointKind       = if ($null -ne $provenance -and $provenance.Success) { $provenance.Groups['endpoint'].Value.Trim().ToLowerInvariant() } else { '' }
            ExternalRoleMode           = if ($null -ne $provenance -and $provenance.Success) { $provenance.Groups['mode'].Value.Trim().ToLowerInvariant() } else { '' }
            ExternalTarget             = if ($null -ne $provenance -and $provenance.Success) { $provenance.Groups['target'].Value.Trim() } else { '' }
            Verification               = if ($verification.Success) { $verification.Groups['value'].Value.Trim() } else { '' }
            ExternalUnmeteredConnector = if ($unmetered.Success) { $unmetered.Groups['value'].Value.Trim() } else { '' }
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

    foreach ($entry in (Get-HistoryEntry -Path $Path)) {
        foreach ($candidate in $entry.DeliverablePaths) {
            [pscustomobject]@{
                Source = $entry.Source
                Agent  = $entry.Agent
                Title  = $entry.Title
                MemberName = $entry.MemberName
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

function Resolve-ConnectorManifestPath {
    param(
        [AllowEmptyString()][string]$ManifestPath,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$TeamPath
    )

    $manifest = ([string]$ManifestPath).Trim()
    if (-not $manifest) { return $null }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ([System.IO.Path]::IsPathRooted($manifest)) {
        $candidates.Add($manifest)
    }
    else {
        $candidates.Add((Join-Path $ProjectRoot $manifest))
        $candidates.Add((Join-Path (Split-Path -Parent $TeamPath) $manifest))
        $candidates.Add($manifest)
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    $null
}

function Get-ConnectorRosterRows {
    param([AllowNull()][string]$TeamContent)

    foreach ($table in (Get-MarkdownTable -Content $TeamContent)) {
        if ('Agent Name (Primary)' -notin $table.Header -or 'Role' -notin $table.Header) { continue }
        foreach ($row in $table.Rows) {
            if (-not $row['Role'] -or -not $row['Agent Name (Primary)']) { continue }
            [pscustomobject]@{
                Role       = ([string]$row['Role']).Trim().ToLowerInvariant()
                MemberName = if ('Member Name' -in $table.Header) { ([string]$row['Member Name']).Trim() } else { '' }
                Agent      = ([string]$row['Agent Name (Primary)']).Trim()
                Tier       = ([string]$row['Model Tier']).Trim()
                DeliverableRoot = ([string]$row['Deliverable Root']).Trim()
            }
        }
    }
}

function Get-ConnectorBindingModel {
    param(
        [AllowNull()][string]$TeamContent,
        [Parameter(Mandatory)][string]$TeamPath,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$RosterRows,
        [System.Collections.IDictionary]$ManifestSnapshots
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $bindings = [System.Collections.Generic.List[object]]::new()
    $tables = @(Get-MarkdownTable -Content $TeamContent)
    $candidateTables = @(
        $tables | Where-Object {
            'Binding ID' -in $_.Header -or 'Connector ID' -in $_.Header -or 'Role Mode' -in $_.Header
        }
    )
    $bindingTables = @(
        $candidateTables | Where-Object {
            $table = $_
            @($script:ConnectorBindingColumns | Where-Object { $_ -notin $table.Header }).Count -eq 0
        }
    )

    if ($candidateTables.Count -gt 0 -and $bindingTables.Count -eq 0) {
        $issues.Add('Connector Bindings table does not carry the complete contractual column set.')
    }
    if ($bindingTables.Count -gt 1) {
        $issues.Add("Connector Bindings is declared in $($bindingTables.Count) tables; one roster owns one binding table.")
    }

    $rowIndex = 0
    foreach ($table in $bindingTables) {
        foreach ($row in $table.Rows) {
            $rowIndex++
            $binding = [pscustomobject]@{
                RowIndex         = $rowIndex
                BindingId        = ([string]$row['Binding ID']).Trim()
                ConnectorId      = ([string]$row['Connector ID']).Trim()
                ManifestPath     = ([string]$row['Manifest']).Trim()
                ResolvedManifest = ''
                EndpointKind     = ([string]$row['Endpoint Kind']).Trim().ToLowerInvariant()
                RoleMode         = ([string]$row['Role Mode']).Trim().ToLowerInvariant()
                TargetKind       = ([string]$row['Target Kind']).Trim().ToLowerInvariant()
                Target           = ([string]$row['Target']).Trim()
                MemberName       = ([string]$row['Member Name']).Trim()
                AddedRole        = ([string]$row['Added Role']).Trim().ToLowerInvariant()
                AlignedRole      = ([string]$row['Aligned Role']).Trim().ToLowerInvariant()
                DefaultExecution = ([string]$row['Default Execution']).Trim().ToLowerInvariant()
                Role             = ''
                TargetMemberName = ''
                Tier             = ''
                DeliverableRoot  = ''
                Issues           = [System.Collections.Generic.List[string]]::new()
            }
            $bindings.Add($binding)

            if (-not $binding.BindingId) { $binding.Issues.Add('missing:bindingId') }
            elseif ($binding.BindingId -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { $binding.Issues.Add('invalid:bindingId') }
            if (-not $binding.ConnectorId) { $binding.Issues.Add('missing:connectorId') }
            if ($binding.EndpointKind -notin @('agent', 'orchestrator')) { $binding.Issues.Add('invalid:endpointKind') }
            if ($binding.RoleMode -notin @('replace', 'add')) { $binding.Issues.Add('invalid:roleMode') }
            if ($binding.TargetKind -ne 'role') { $binding.Issues.Add('invalid:targetKind') }
            if ($binding.DefaultExecution -notin @('original', 'connector', 'ask', 'both')) { $binding.Issues.Add('invalid:defaultExecution') }

            $target = Get-ConnectorTargetRoleLocal -Target $binding.Target
            if ($target.Kind -ne 'role') {
                $binding.Issues.Add('invalid:target')
            }
            else {
                $binding.Role = $target.Role
                $binding.TargetMemberName = $target.MemberName
                if (Test-ConnectorGovernanceRoleLocal -Role $target.Role) { $binding.Issues.Add('invalid:reserved-role-target') }
            }

            if ($binding.RoleMode -eq 'replace') {
                if (-not $binding.MemberName) { $binding.Issues.Add('missing:memberName') }
                if ($target.Kind -eq 'role') {
                    $targetRows = @(
                        $RosterRows | Where-Object {
                            $_.Agent -cne 'Squad Connector' -and $_.Role -eq $target.Role
                        }
                    )
                    if ($target.MemberName) {
                        $targetRows = @($targetRows | Where-Object { $_.MemberName -ceq $target.MemberName })
                    }
                    if ($targetRows.Count -eq 0) {
                        $binding.Issues.Add($(if ($target.MemberName) { 'target-member-not-found' } else { 'target-role-not-found' }))
                    }
                    elseif (-not $target.MemberName -and $targetRows.Count -gt 1) {
                        $binding.Issues.Add('ambiguous:replace-target-member-required')
                    }
                    if ($targetRows.Count -eq 1) {
                        $binding.Tier = $targetRows[0].Tier
                        $binding.DeliverableRoot = $targetRows[0].DeliverableRoot
                    }
                    if ($binding.MemberName -and @($targetRows | Where-Object { $_.MemberName -and $_.MemberName -ceq $binding.MemberName }).Count -gt 0) {
                        $binding.Issues.Add('invalid:memberName-collides-with-target')
                    }
                }
            }
            elseif ($binding.RoleMode -eq 'add') {
                if (-not $binding.MemberName) { $binding.Issues.Add('missing:memberName') }
                if (-not $binding.AddedRole) { $binding.Issues.Add('missing:addedRole') }
                elseif ($binding.AddedRole -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { $binding.Issues.Add('invalid:addedRole') }
                if (-not $binding.AlignedRole) { $binding.Issues.Add('missing:alignedRole') }
                if (Test-ConnectorGovernanceRoleLocal -Role $binding.AddedRole) { $binding.Issues.Add('invalid:reserved-added-role') }
                if (Test-ConnectorGovernanceRoleLocal -Role $binding.AlignedRole) { $binding.Issues.Add('invalid:reserved-aligned-role') }
                if ($binding.DefaultExecution -in @('original', 'both')) { $binding.Issues.Add('invalid:defaultExecution-for-add') }
                if ($target.Kind -eq 'role') {
                    if ($target.Role -ne $binding.AddedRole) { $binding.Issues.Add('invalid:add-target-role-mismatch') }
                    if (-not $target.MemberName -or $target.MemberName -cne $binding.MemberName) { $binding.Issues.Add('invalid:add-target-member-mismatch') }
                }
                $memberRows = @(
                    $RosterRows | Where-Object {
                        $_.Role -eq $binding.AddedRole -and
                        $_.MemberName -ceq $binding.MemberName -and
                        $_.Agent -ceq 'Squad Connector'
                    }
                )
                if ($memberRows.Count -ne 1) { $binding.Issues.Add('add-member-row-missing-or-ambiguous') }
                else {
                    $binding.Tier = $memberRows[0].Tier
                    $binding.DeliverableRoot = $memberRows[0].DeliverableRoot
                }
                if ($binding.AddedRole) { $binding.Role = $binding.AddedRole }
            }

            $manifest = $null
            if (-not $binding.ManifestPath) {
                $binding.Issues.Add('missing:manifestPath')
            }
            elseif ($PSBoundParameters.ContainsKey('ManifestSnapshots')) {
                if ($null -eq $ManifestSnapshots -or -not $ManifestSnapshots.Contains($binding.ManifestPath)) {
                    $binding.Issues.Add('snapshot-manifest-missing')
                }
                else { $manifest = $ManifestSnapshots[$binding.ManifestPath] }
            }
            else {
                $resolvedManifest = Resolve-ConnectorManifestPath -ManifestPath $binding.ManifestPath -ProjectRoot $ProjectRoot -TeamPath $TeamPath
                if (-not $resolvedManifest) { $binding.Issues.Add('manifest-not-found') }
                else {
                    $binding.ResolvedManifest = $resolvedManifest
                    try { $manifest = Get-Content -LiteralPath $resolvedManifest -Raw | ConvertFrom-Json -AsHashtable -Depth 64 }
                    catch { $binding.Issues.Add('manifest-parse-failed') }
                }
            }
            if ($manifest -is [System.Collections.IDictionary]) {
                $shape = Test-SquadConnectorManifestShape -Manifest $manifest
                foreach ($shapeIssue in @($shape.Issues)) { $binding.Issues.Add("manifest-shape:$shapeIssue") }
                if ([string]$manifest['schemaVersion'] -ne '1.1') { $binding.Issues.Add('manifest-version-not-1.1') }
                if ([string]$manifest['connectorId'] -cne $binding.ConnectorId) { $binding.Issues.Add('manifest-connectorId-mismatch') }
                if (([string]$manifest['endpointKind']).Trim().ToLowerInvariant() -ne $binding.EndpointKind) { $binding.Issues.Add('manifest-endpointKind-mismatch') }
                $manifestRoles = @($manifest['roles'] | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
                if ($binding.Role -and $manifestRoles -notcontains $binding.Role) { $binding.Issues.Add("manifest-role-missing:$($binding.Role)") }
            }
            else { $binding.Issues.Add('manifest-unreadable') }
        }
    }

    foreach ($group in @($bindings | Where-Object BindingId | Group-Object { $_.BindingId.ToLowerInvariant() })) {
        if ($group.Count -le 1) { continue }
        foreach ($binding in $group.Group) { $binding.Issues.Add('duplicate:bindingId') }
    }
    foreach ($group in @($bindings | Where-Object MemberName | Group-Object MemberName)) {
        if ($group.Count -le 1) { continue }
        foreach ($binding in $group.Group) { $binding.Issues.Add('duplicate:memberName') }
    }

    foreach ($binding in $bindings) {
        $label = if ($binding.BindingId) { $binding.BindingId } else { "<row-$($binding.RowIndex)-blank-binding-id>" }
        foreach ($issue in @($binding.Issues)) { $issues.Add("${label}:$issue") }
    }

    [pscustomobject]@{
        HasBindings  = $candidateTables.Count -gt 0
        Bindings     = $bindings.ToArray()
        ValidBindings = @($bindings | Where-Object { $_.Issues.Count -eq 0 })
        Issues       = $issues.ToArray()
    }
}

function Get-ConnectorRetirementModel {
    param(
        [AllowNull()][string]$Content,
        [Parameter(Mandatory)][string]$TeamPath,
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    Get-SquadConnectorRetirementModel -Content $Content -TeamPath $TeamPath -ProjectRoot $ProjectRoot
}

function Get-ConnectorHistoryModel {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Bindings,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ValidBindings,
        [AllowEmptyCollection()][object[]]$RetiredBindings = @(),
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$RosterRows
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $identities = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Entries) {
        if ($entry.Agent -cne 'Squad Connector') {
            if ($entry.HasExternalProvenance) { $issues.Add("$($entry.Source): non-connector history carries external provenance") }
            continue
        }

        $entryIssueCount = $issues.Count
        if (-not $entry.MemberName) { $issues.Add("$($entry.Source): connector history is missing Member Name") }
        if (-not $entry.HasExternalProvenance) {
            $issues.Add("$($entry.Source): connector history is missing external provenance")
            continue
        }
        if (-not $entry.ExternalProvenanceValid) {
            $issues.Add("$($entry.Source): connector history external provenance is malformed")
            continue
        }
        if ($entry.Verification -cne 'external, unverified') { $issues.Add("$($entry.Source): connector history verification marker is invalid") }
        if ($entry.ExternalUnmeteredConnector -cne $entry.ExternalConnectorId) { $issues.Add("$($entry.Source): connector history unmetered marker does not match provenance") }

        $role = ''
        $deliverableRoot = ''
        if ($entry.ExternalBindingId -in @('legacy-1.0', 'none (legacy-1.0)')) {
            if ($entry.ExternalEndpointKind -ne 'agent') { $issues.Add("$($entry.Source): legacy connector endpoint must be agent") }
            if ($entry.ExternalRoleMode -ne 'replace') { $issues.Add("$($entry.Source): legacy connector mode must be replace") }
            $target = Get-ConnectorTargetRoleLocal -Target $entry.ExternalTarget
            if ($target.Kind -ne 'role' -or (Test-ConnectorGovernanceRoleLocal -Role $target.Role)) {
                $issues.Add("$($entry.Source): legacy connector target is not an ordinary work role")
            }
            else {
                $role = $target.Role
                $targetRows = @($RosterRows | Where-Object { $_.Role -eq $target.Role -and $_.Agent -cne 'Squad Connector' })
                if ($target.MemberName) { $targetRows = @($targetRows | Where-Object { $_.MemberName -ceq $target.MemberName }) }
                if ($targetRows.Count -eq 0) { $issues.Add("$($entry.Source): legacy connector target has no matching internal member") }
                elseif ($targetRows.Count -eq 1) { $deliverableRoot = $targetRows[0].DeliverableRoot }
                $roleBindings = @(
                    $Bindings | Where-Object {
                        $_.Role -eq $target.Role -and
                        (-not $target.MemberName -or -not $_.TargetMemberName -or $_.TargetMemberName -ceq $target.MemberName)
                    }
                )
                if ($roleBindings.Count -gt 0) { $issues.Add("$($entry.Source): legacy connector provenance bypasses a Connector Bindings row") }
            }
        }
        else {
            $bindingMatches = @($ValidBindings | Where-Object { $_.BindingId -ceq $entry.ExternalBindingId })
            $exactCurrent = @($bindingMatches | Where-Object {
                    $_.ConnectorId -ceq $entry.ExternalConnectorId -and
                    $_.EndpointKind -ceq $entry.ExternalEndpointKind -and
                    $_.RoleMode -ceq $entry.ExternalRoleMode -and
                    $_.Target -ceq $entry.ExternalTarget -and
                    $_.MemberName -ceq $entry.MemberName
                })
            if ($exactCurrent.Count -eq 0) {
                # Retirement evidence admits only the completed entries named before a
                # confirmed change; it never becomes a current dispatch registration.
                $retired = @($RetiredBindings | Where-Object {
                        $_.BindingId -ceq $entry.ExternalBindingId -and $_.HistoryEntries -ccontains $entry.Title
                    })
                if ($retired.Count -gt 0) { $bindingMatches = $retired }
            }
            if ($bindingMatches.Count -ne 1) {
                $issues.Add("$($entry.Source): connector history binding '$($entry.ExternalBindingId)' does not resolve to one valid binding")
            }
            else {
                $binding = $bindingMatches[0]
                $role = $binding.Role
                $deliverableRoot = $binding.DeliverableRoot
                foreach ($comparison in @(
                        @{ Name = 'connector'; Actual = $entry.ExternalConnectorId; Expected = $binding.ConnectorId }
                        @{ Name = 'endpoint'; Actual = $entry.ExternalEndpointKind; Expected = $binding.EndpointKind }
                        @{ Name = 'mode'; Actual = $entry.ExternalRoleMode; Expected = $binding.RoleMode }
                        @{ Name = 'target'; Actual = $entry.ExternalTarget; Expected = $binding.Target }
                        @{ Name = 'member'; Actual = $entry.MemberName; Expected = $binding.MemberName }
                    )) {
                    if ([string]$comparison.Actual -cne [string]$comparison.Expected) {
                        $issues.Add("$($entry.Source): connector history $($comparison.Name) '$($comparison.Actual)' does not match binding '$($comparison.Expected)'")
                    }
                }
            }
        }

        if ($issues.Count -eq $entryIssueCount -and $role) {
            $identities.Add([pscustomobject]@{
                    Role        = $role
                    MemberName  = $entry.MemberName
                    Agent       = 'Squad Connector'
                    BindingId   = $entry.ExternalBindingId
                    ConnectorId = $entry.ExternalConnectorId
                    Source      = $entry.Source
                    Title       = $entry.Title
                    DeliverableRoot = $deliverableRoot
                })
        }
    }

    [pscustomobject]@{
        Identities = $identities.ToArray()
        Issues     = $issues.ToArray()
    }
}

function Get-ConnectorLedgerIssues {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Attribution,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$HistoryIdentities
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $connectorRows = @(
        foreach ($row in $Attribution) {
            if ($row.Count -ge 3 -and ([string]$row[2]).Trim() -ceq 'Squad Connector') {
                [pscustomobject]@{
                    Role       = (Get-LedgerRoleKey ([string]$row[0])).ToLowerInvariant()
                    MemberName = ([string]$row[1]).Trim()
                    Agent      = ([string]$row[2]).Trim()
                }
            }
        }
    )

    foreach ($row in $connectorRows) {
        $matches = @($HistoryIdentities | Where-Object { $_.Role -eq $row.Role -and $_.MemberName -ceq $row.MemberName })
        if ($matches.Count -eq 0) {
            $issues.Add("Attribution row '$($row.Role)' / '$($row.MemberName)' has no exact connector history identity")
        }
    }
    foreach ($identity in $HistoryIdentities) {
        $matches = @($connectorRows | Where-Object { $_.Role -eq $identity.Role -and $_.MemberName -ceq $identity.MemberName })
        if ($matches.Count -eq 0) {
            $issues.Add("Connector history '$($identity.Source)' / '$($identity.MemberName)' has no exact Attribution row")
        }
    }
    $issues.ToArray()
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

function Get-DispatchClassTable {
    <#
    .SYNOPSIS
        Reads the canonical dispatch-size estimator table.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Content = ''
    )

    $classes = @{}
    foreach ($table in (Get-MarkdownTable -Content $Content)) {
        $required = @('Dispatch class', 'Internal turns', 'Base context', 'Growth/turn', 'Output/turn')
        if (@($required | Where-Object { $_ -notin $table.Header }).Count -gt 0) { continue }

        foreach ($row in $table.Rows) {
            $name = $row['Dispatch class']
            $numbers = @($required[1..4] | ForEach-Object { ConvertTo-LedgerNumber $row[$_] })
            if (-not $name -or $numbers -contains $null) { continue }
            $classes[$name] = @{
                internal_turns = $numbers[0]
                base_context   = $numbers[1]
                growth         = $numbers[2]
                output         = $numbers[3]
            }
        }
    }

    $classes
}

function Get-CostPreflightRecord {
    <#
    .SYNOPSIS
        Reads every append-only Cost Preflight decision and its demand table.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Content = ''
    )

    foreach ($match in [regex]::Matches($Content, '(?ms)^## Cost Preflight (?<timestamp>\S+) (?<run>\S+) (?<round>\S+)\r?\n(?<body>.*?)(?=^## |\z)')) {
        $body = $match.Groups['body'].Value
        $fields = [ordered]@{}
        foreach ($field in [regex]::Matches($body, '(?m)^\* (?<key>[^:]+):\s*(?<value>.*)\r?$')) {
            $fields[$field.Groups['key'].Value] = $field.Groups['value'].Value.Trim()
        }

        $demand = @(Get-MarkdownTable -Content $body | Where-Object {
                'Slot' -in $_.Header -and 'Projected Cost' -in $_.Header
            } | Select-Object -First 1)
        $permitted = @(
            if ($fields['Permitted Next Dispatch Set'] -and $fields['Permitted Next Dispatch Set'] -ne 'none') {
                $fields['Permitted Next Dispatch Set'] -split ',' | ForEach-Object { $_.Trim() }
            }
        )

        [pscustomobject]@{
            Timestamp      = $match.Groups['timestamp'].Value
            RunId          = $match.Groups['run'].Value
            RoundId        = $match.Groups['round'].Value
            Fields         = $fields
            PermittedSlots = $permitted
            DemandRows     = @(if ($demand) { $demand[0].Rows })
        }
    }
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

    $projectRoot = $SquadRoot
    if (($SquadRoot -replace '\\', '/') -match '^(?<base>.*?)/?\.copilot-tracking(/|$)') {
        $projectRoot = if ($Matches['base']) { $Matches['base'] } else { '.' }
    }

    # The ledger rewrite matches a history file back to its roster row by file name, so
    # the roster is what makes a basename legal. Alternates count: a dispatch can be
    # routed to one and it writes its own history file. A connector replacement retains
    # the internal Members row, so its binding must separately admit Squad Connector as
    # the history agent for the target role.
    $roleAgents = @{}
    $rosterAgentCandidates = [System.Collections.Generic.List[string]]::new()
    $rosterRows = @(Get-ConnectorRosterRows -TeamContent $teamContent)
    $teamTables = @(Get-MarkdownTable -Content $teamContent)
    foreach ($table in $teamTables) {
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
            if ('Role' -in $table.Header -and $row['Role']) {
                $role = ([string]$row['Role']).Trim().ToLowerInvariant()
                $combined = @($roleAgents[$role]) + $names
                $roleAgents[$role] = @($combined | Where-Object { $_ } | Sort-Object -Unique)
            }
            foreach ($name in $names) { [void]$rosterAgentCandidates.Add([string]$name) }
        }
    }

    $teamPath = Join-Path $SquadRoot 'team.md'
    $connectorBindingModel = Get-ConnectorBindingModel -TeamContent $teamContent -TeamPath $teamPath -ProjectRoot $projectRoot -RosterRows $rosterRows
    foreach ($binding in $connectorBindingModel.ValidBindings) {
        $combined = @($roleAgents[$binding.Role]) + @('Squad Connector')
        $roleAgents[$binding.Role] = @($combined | Where-Object { $_ } | Sort-Object -Unique)
        [void]$rosterAgentCandidates.Add('Squad Connector')
    }
    $rosterAgents = @($rosterAgentCandidates | Sort-Object -Unique)

    # Only this file holds token rates, so every block's rates are checked against it.
    $rates = Get-RateTable -Content $ratesContent
    $decisionsContent = Read-Text 'decisions.md'

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
    $connectorRetirementModel = Get-ConnectorRetirementModel -Content $decisionsContent -TeamPath $teamPath -ProjectRoot $projectRoot
    $connectorHistoryModel = Get-ConnectorHistoryModel -Entries $entries -Bindings $connectorBindingModel.Bindings `
        -ValidBindings $connectorBindingModel.ValidBindings -RetiredBindings $connectorRetirementModel.Retirements -RosterRows $rosterRows
    foreach ($identity in $connectorHistoryModel.Identities) {
        $combined = @($roleAgents[$identity.Role]) + @('Squad Connector')
        $roleAgents[$identity.Role] = @($combined | Where-Object { $_ } | Sort-Object -Unique)
        if ('Squad Connector' -notin $rosterAgents) { $rosterAgents += 'Squad Connector' }
    }
    $preflightEntries = @(
        foreach ($file in ($historyFiles | Where-Object { $_.BaseName -notmatch '^(autonomous-loop|autopilot-run)-' })) {
            Get-HistoryEntry -Path $file.FullName
        }
    )
    $preflightRecords = @(Get-CostPreflightRecord -Content $decisionsContent)

    $artifactlessEntries = @(
        foreach ($entry in $entries) {
            if (-not $entry.NamesArtifact) { "$($entry.Source): $($entry.Title)" }
        }
    )

    $deliverables = @(
        foreach ($entry in $declared) {
            $resolved = Resolve-Deliverable $entry.Path
            $root = if ($agentRoots.ContainsKey($entry.Agent)) { $agentRoots[$entry.Agent] } else { $null }
            if ($entry.Agent -ceq 'Squad Connector') {
                $identity = @($connectorHistoryModel.Identities | Where-Object {
                        $_.Source -ceq $entry.Source -and $_.Title -ceq $entry.Title -and $_.MemberName -ceq $entry.MemberName
                    })
                $root = if ($identity.Count -eq 1) { $identity[0].DeliverableRoot } else { $null }
            }

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
                UnderRoot  = if (-not $root) { $entry.Agent -cne 'Squad Connector' }
                    elseif ($entry.Agent -ceq 'Squad Connector') { $declaredPath.StartsWith("$prefix/", [StringComparison]::OrdinalIgnoreCase) }
                    else { $declaredPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }
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
    $lastReconciled = 'never'
    $estimatorRevision = 0
    $calibrationBasis = ''
    $ratesObservedOn = ''
    if ($ratesContent) {
        $factor = [regex]::Match($ratesContent, '(?im)^\s*[*-]?\s*`?calibration_factor`?\s*[:=]\s*([0-9.]+)')
        if ($factor.Success) { $calibration = [double]$factor.Groups[1].Value }
        $seen = [regex]::Match($ratesContent, '(?im)^\s*[*-]?\s*`?observations`?\s*[:=]\s*([0-9]+)')
        if ($seen.Success) { $observations = [int]$seen.Groups[1].Value }
        $last = [regex]::Match($ratesContent, '(?im)^\s*[*-]?\s*`?last_reconciled`?\s*[:=]\s*([^\r\n]+)')
        if ($last.Success) { $lastReconciled = $last.Groups[1].Value.Trim().Trim('"') }
        $revision = [regex]::Match($ratesContent, '(?im)^\s*[*-]?\s*`?estimator_revision`?\s*[:=]\s*([0-9]+)')
        if ($revision.Success) { $estimatorRevision = [int]$revision.Groups[1].Value }
        $basis = [regex]::Match($ratesContent, '(?im)^\s*[*-]?\s*`?calibration_basis`?\s*[:=]\s*([^\r\n]+)')
        if ($basis.Success) { $calibrationBasis = $basis.Groups[1].Value.Trim().Trim('"') }
        $observedOn = [regex]::Match($ratesContent, '(?im)^\s*[*-]\s*Observed-on:\s*([^\.\r\n]+)')
        if ($observedOn.Success) { $ratesObservedOn = $observedOn.Groups[1].Value.Trim() }
    }

    $attribution = @(if ($ledgerContent) { Get-LedgerTable -Content $ledgerContent -Heading 'Attribution' })
    $usageAndCost = @(if ($ledgerContent) { Get-LedgerTable -Content $ledgerContent -Heading 'Usage & Cost' })
    $connectorLedgerIssues = Get-ConnectorLedgerIssues -Attribution $attribution -HistoryIdentities $connectorHistoryModel.Identities

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
        ConnectorBindings = @($connectorBindingModel.Bindings)
        ConnectorBindingIssues = @($connectorBindingModel.Issues)
        ConnectorRetirements = @($connectorRetirementModel.Retirements)
        ConnectorRetirementIssues = @($connectorRetirementModel.Issues)
        ConnectorHistoryIdentities = @($connectorHistoryModel.Identities)
        ConnectorHistoryIssues = @($connectorHistoryModel.Issues)
        ConnectorLedgerIssues = @($connectorLedgerIssues)
        AgentRoots       = $agentRoots
        RoleRoots        = $roleRoots
        Deliverables     = @($deliverables)
        Entries          = @($entries)
        PreflightEntries = @($preflightEntries)
        PreflightRecords = @($preflightRecords)
        ArtifactlessEntries = @($artifactlessEntries)
        OrphanArtifacts  = @($orphanArtifacts)
        NestedTracking   = @($nestedTracking)
        Routing          = Read-Text 'routing.md'
        Decisions        = $decisionsContent
        Notifications    = Read-Text 'notifications.md'
        Ledger           = $ledgerContent
        RatesContent     = $ratesContent
        Rates            = $rates
        DispatchClasses  = Get-DispatchClassTable -Content $ratesContent
        Calibration      = $calibration
        Observations     = $observations
        LastReconciled   = $lastReconciled
        EstimatorRevision = $estimatorRevision
        CalibrationBasis = $calibrationBasis
        RatesObservedOn  = $ratesObservedOn
        Blocks           = $blocks
        DispatchBlocks   = @($blocks | Where-Object { -not $_.IsOrchestration })
        OrchestrationBlocks = @($blocks | Where-Object { $_.IsOrchestration })
        Attribution      = $attribution
        UsageAndCost     = $usageAndCost
        ConsumptionFields = $script:ConsumptionFields
        ModelSources     = $script:ModelSources
        Bases            = $script:Bases
        Modes            = $script:Modes
        ApprovalChannels = $script:ApprovalChannels
        PreflightFields  = $script:PreflightFields
        PreflightConfidences = $script:PreflightConfidences
        PreflightBases   = $script:PreflightBases
        PreflightDecisions = $script:PreflightDecisions
    }
}

Export-ModuleMember -Function Get-SquadStateModel, Get-ConsumptionBlock, Get-RoutingIdentityBullets, Get-DeliverableEntry, Get-DeliverableTail, Get-HistoryEntry, Get-LedgerTable, Get-LedgerRoleKey, Get-MarkdownTable, Get-RateTable, Get-DispatchClassTable, Get-CostPreflightRecord, ConvertTo-LedgerNumber, Get-LedgerDecimal
