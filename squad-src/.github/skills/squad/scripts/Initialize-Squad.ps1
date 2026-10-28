#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
    Publishes a fresh squad tree from confirmed JSON, only after validation.
.DESCRIPTION
    AI cost: none; publishes confirmed payload data without dispatching the Scribe.
    Roots containing files or links are refused, including partial initialization.
    Additive catalog-role/pack expansion has a separate sealed transaction;
    non-additive refresh stays on the cold Scribe path. Payload strings are data,
    never commands.
.PARAMETER PayloadPath
    JSON input described in references/scribe-init.md.
.PARAMETER RepoRoot
    Consumer repository boundary; defaults to the current directory.
.PARAMETER AgentRepoRoot
    Repository whose installed agents are validated for `-Direct`. Defaults to
    RepoRoot. Federation Init supplies the consumer repository while staging member
    state in an isolated repository-shaped directory.
.PARAMETER Direct
    Confirmed coordinator execution. Records coordinator usage only; it is not a
    Scribe dispatch. The legacy Scribe invocation remains the default.
.EXAMPLE
    ./Initialize-Squad.ps1 -PayloadPath /tmp/init.json -RepoRoot .
.NOTES
    Serial execution is required with every other squad-state writer.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PayloadPath,
    [string]$RepoRoot = (Get-Location).ProviderPath,
    [string]$AgentRepoRoot = $RepoRoot,
    [switch]$Direct
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-ObjectKey {
    param($Object, [string[]]$Required, [string[]]$Optional = @())
    if ($Object -isnot [System.Collections.IDictionary]) { throw 'Expected a JSON object.' }
    foreach ($Key in $Required) {
        if (-not $Object.Contains($Key)) { throw "Missing field: $Key" }
    }
    foreach ($Key in $Object.Keys) {
        if ($Key -notin ($Required + $Optional)) { throw "Unsupported field: $Key" }
    }
}

function Assert-Text {
    param($Value, [switch]$AllowEmpty)
    if ($Value -isnot [string] -or $Value -match '[\r\n|\x00-\x1f]' -or (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value))) {
        throw "Expected a single-line string without table delimiters or control characters: $($MyInvocation.Line.Trim())"
    }
}

function Assert-UnlinkedPath {
    param([string]$Path)
    $Cursor = [System.IO.Path]::GetFullPath($Path)
    while ($Cursor) {
        $Item = Get-Item -LiteralPath $Cursor -Force -ErrorAction SilentlyContinue
        if ($Item -and ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { throw "Linked path refused: $Cursor" }
        $Cursor = Split-Path -Path $Cursor -Parent
    }
}

function Get-EmptyDirectoryTree {
    param([string]$Path)
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "Linked path refused: $Path" }
    if (-not $Item.PSIsContainer) { throw 'Squad root already exists; retry writes nothing. Use roster expansion for additive roles/packs or the cold path for other refreshes.' }
    $Directories = [System.Collections.Generic.List[string]]::new()
    $Directories.Add($Item.FullName)
    foreach ($Child in @(Get-ChildItem -LiteralPath $Path -Force)) {
        if ($Child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "Linked path refused: $($Child.FullName)" }
        if (-not $Child.PSIsContainer) { throw 'Squad root already exists; retry writes nothing. Use roster expansion for additive roles/packs or the cold path for other refreshes.' }
        foreach ($Nested in (Get-EmptyDirectoryTree $Child.FullName)) { $Directories.Add($Nested) }
    }
    return $Directories
}

function Get-Seed {
    param([string]$Name, [string]$Heading, [string]$Language = 'markdown')
    $Text = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "../references/$Name")) -replace '\r\n', "`n"
    $Section = $Text.Substring($Text.IndexOf("## $Heading`n", [System.StringComparison]::Ordinal))
    $Match = [regex]::Matches($Section, '(?ms)^(?<fence>`{3,4})' + $Language + '\n(?<body>.*?)\n\k<fence>[ \t]*$') | Where-Object { $Language -eq 'json' -or $_.Groups['body'].Value.StartsWith('---') } | Select-Object -First 1
    if (-not $Match) { throw "Missing shipped seed: $Name / $Heading" }
    return $Match.Groups['body'].Value + "`n"
}

function Invoke-Helper {
    param([string]$Name, [string[]]$Arguments)
    $Output = & (Join-Path $PSHOME 'pwsh') -NoProfile -File (Join-Path $PSScriptRoot $Name) @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "$Name failed: $($Output -join "`n")" }
    return (($Output -join "`n") -replace '\x1b\[[0-9;]*[A-Za-z]', '')
}

function Resolve-InitDeliverable {
    param([string]$Value, [string]$Relative, [string]$Repository)
    if ($Value -ceq '(squad state)' -or $Value -ceq [string][char]0x2014) { return $Value }
    $Resolved = foreach ($Alternative in ($Value -split '\s+or\s+')) {
        $Label = [regex]::Match($Alternative, ' \((?:ADO|Jira)\)$').Value
        $Path = $Alternative.Substring(0, $Alternative.Length - $Label.Length).Trim().Trim('`') -replace '\\', '/'
        if ($Path -match '(^|/)\.\.(/|$)|^[~/]|:' ) { throw 'Unsafe Deliverable Root.' }
        $Canonical = ([System.IO.Path]::GetRelativePath($Repository, [System.IO.Path]::GetFullPath($Path, $Repository)) -replace '\\', '/').TrimEnd('/')
        if ($Canonical -eq '.' -or $Canonical -match '^\.\.(?:/|$)') { throw 'Unsafe Deliverable Root.' }
        if ($Relative -ne '.copilot-tracking/squad' -and $Canonical -notmatch '^(?:docs|outputs)(?:/|$)') {
            if ($Canonical -match '^\.copilot-tracking/squad/members(?:/|$)') {
                if ($Canonical -cne $Relative -and -not $Canonical.StartsWith($Relative + '/', [System.StringComparison]::Ordinal)) { throw 'Deliverable Root must stay under the selected member.' }
            }
            else {
                if ($Canonical.StartsWith('.copilot-tracking/', [System.StringComparison]::Ordinal)) { $Canonical = $Canonical.Substring('.copilot-tracking/'.Length) }
                $Canonical = $Relative + '/' + $Canonical
            }
        }
        $Canonical + $(if ($Path.EndsWith('/')) { '/' }) + $Label
    }
    return $Resolved -join ' or '
}

function Assert-InitPricing {
    param($Usage, [string]$RateContent)
    . (Join-Path $PSScriptRoot 'Initialize-SquadConsumptionRates.ps1') -SquadRoot '.'
    $Tables = @(Get-MarkdownTableLocal -Content $RateContent)
    $ModelRows = @($Tables | Where-Object { 'Model (as routed)' -in $_.Header } | ForEach-Object { $_.Rows })
    $FallbackRows = @($Tables | Where-Object { 'Priced as' -in $_.Header } | ForEach-Object { $_.Rows })
    foreach ($Entry in $Usage) {
        $Block = $Entry.consumption
        $ModelKey = ($Block.model.Trim() -replace '\s*\((?:copilot|github|anthropic|openai)\)\s*$', '' -replace '[\s_]+', '-').ToLowerInvariant()
        if ($ModelKey -in @('auto', 'fast', 'default', 'extended') -or $Block.model -ne $Block.model.Trim()) { throw 'Consumption requires an actual model or unknown/unresolved, not a tier or auto.' }
        $ExpectedBasis = if ($Block.model -eq 'unknown') { 'tier-default' } else { 'estimated' }
        if ($Block.basis -ne $ExpectedBasis) { throw "Consumption basis must be $ExpectedBasis for the supplied model attribution." }
        $OwnRow = @($ModelRows | Where-Object {
            $NameKey = ($_['Model (as routed)'] -replace '\s+', '-').ToLowerInvariant()
            $IdKey = $_['Model ID'].Trim('`').ToLowerInvariant()
            $ModelKey -in @($NameKey, $IdKey)
        }) | Select-Object -First 1
        if ($OwnRow) {
            if ($Block.priced_as -notin @($OwnRow['Model (as routed)'], $OwnRow['Model ID'].Trim('`'))) { throw "Consumption priced_as must name the model's own rate row." }
        }
        else {
            $Fallback = @($FallbackRows | Where-Object { $_.Tier -eq $Block.model_tier }) | Select-Object -First 1
            if (-not $Fallback -or $Block.priced_as -notin @($Fallback['Priced as'], $Block.model_tier)) { throw 'Consumption priced_as must name the matching tier fallback for an unknown or unlisted model.' }
        }
    }
}

function Write-Seed {
    param([string]$Name, [string]$Text)
    [System.IO.File]::WriteAllText((Join-Path $Stage $Name), $Text, [System.Text.UTF8Encoding]::new($false))
}

function Get-InitUsage {
    param([string]$SessionModel, [string]$ScribeTier, [string[]]$Actors = @('coordinator', 'scribe'))
    . (Join-Path $PSScriptRoot 'Initialize-SquadConsumptionRates.ps1') -SquadRoot '.'
    $Tables = @(Get-MarkdownTableLocal -Content (Get-TemplateSeedBlock -Path (Join-Path $PSScriptRoot '../references/consumption-rates-template.md')))
    $Floors = @($Tables | Where-Object { 'Dispatch class' -in $_.Header } | ForEach-Object { $_.Rows } | Where-Object { $_['Dispatch class'] -eq 'Scribe state write' })
    if ($Floors.Count -ne 1) { throw 'Missing shipped setup orchestration estimator floor.' }
    $Sizes = @('Internal turns', 'Base context', 'Growth/turn', 'Output/turn' | ForEach-Object {
        $Number = 0L
        if (-not [long]::TryParse(($Floors[0][$_] -replace ',', ''), [ref]$Number) -or $Number -le 0) { throw "Invalid setup estimator floor: $_" }
        $Number
    })
    $Turns, $Base, $Growth, $Output = $Sizes
    $Gross = $Turns * ($Base + $Growth * ($Turns - 1) / 2.0)
    $ModelRows = @($Tables | Where-Object { 'Model (as routed)' -in $_.Header } | ForEach-Object { $_.Rows })
    $FallbackRows = @($Tables | Where-Object { 'Priced as' -in $_.Header } | ForEach-Object { $_.Rows })
    foreach ($Actor in $Actors) {
        $ConcreteSession = $Actor -eq 'coordinator' -and $SessionModel.Trim() -notin @('', 'auto', 'fast', 'default', 'extended', 'unknown')
        $Model = if ($ConcreteSession) { $SessionModel } else { 'unknown' }
        $ModelKey = ($Model.Trim() -replace '\s*\((?:copilot|github|anthropic|openai)\)\s*$', '' -replace '[\s_]+', '-').ToLowerInvariant()
        $Own = @($ModelRows | Where-Object {
            $NameKey = ($_['Model (as routed)'] -replace '\s+', '-').ToLowerInvariant()
            $IdKey = $_['Model ID'].Trim('`').ToLowerInvariant()
            $ModelKey -in @($NameKey, $IdKey)
        }) | Select-Object -First 1
        $Tier = if ($Own) { $Own.Tier } elseif ($Actor -eq 'scribe') { $ScribeTier } else { 'default' }
        $Fallback = @($FallbackRows | Where-Object { $_.Tier -eq $Tier }) | Select-Object -First 1
        if (-not $Own -and -not $Fallback) { throw "Missing setup pricing for $Tier." }
        $Price = if ($Own) { $Own['Model (as routed)'] } else { $Fallback['Priced as'] }
        $PriceRow = @($ModelRows | Where-Object { $_['Model (as routed)'] -eq $Price }) | Select-Object -First 1
        if (-not $PriceRow) { throw 'Missing setup pricing row.' }
        @{ actor = $Actor; consumption = [ordered]@{
            model = $Model; model_source = $(if ($ConcreteSession) { 'session-inherited' } else { 'unresolved' })
            priced_as = $Price; model_tier = $Tier; internal_turns = [long]$Turns
            input_tokens = [long][Math]::Round($Gross * 0.20); cached_tokens = [long][Math]::Round($Gross * 0.80)
            cache_write_tokens = $(if ([double]$PriceRow['Cache write'] -gt 0) { [long]($Base + $Growth * ($Turns - 1)) } else { 0L })
            output_tokens = [long]($Turns * $Output); basis = $(if ($ConcreteSession) { 'estimated' } else { 'tier-default' })
        } }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $Stage = $null
    try {
        $Payload = Get-Content -LiteralPath $PayloadPath -Raw | ConvertFrom-Json -AsHashtable
        Assert-ObjectKey $Payload @('squadRoot', 'runId', 'roster', 'provenance') @('timestamp', 'usage', 'payloadType', 'turn', 'mode', 'modelRouting', 'sessionModel', 'modelOverrides', 'notify', 'stateAdvance', 'ledgerCommand')
        $Now = [DateTimeOffset]::UtcNow
        if (-not $Payload.Contains('timestamp')) { $Payload.timestamp = $Now.ToString('o') }
        if ($Payload.timestamp -is [DateTime]) { $Payload.timestamp = $Payload.timestamp.ToString('o') }
        if ($Payload.Contains('payloadType') -and $Payload.payloadType -ne 'initialization') { throw 'Only fresh initialization is supported.' }
        if ($Payload.Contains('turn') -and $Payload.turn -ne 1) { throw 'Init turn must be 1.' }
        foreach ($Key in @('squadRoot', 'runId', 'timestamp', 'provenance')) { Assert-Text $Payload[$Key] }
        $Timestamp = [DateTimeOffset]::Parse($Payload.timestamp, [cultureinfo]::InvariantCulture)
        if ($Timestamp -gt $Now) { throw 'Future Init timestamp refused; omit timestamp to use the helper UTC clock.' }
        $Repository = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
        Assert-UnlinkedPath $Repository
        if ($Payload.squadRoot -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Path traversal refused.' }
        $Root = [System.IO.Path]::GetFullPath($Payload.squadRoot, $Repository).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
        $Relative = [System.IO.Path]::GetRelativePath($Repository, $Root) -replace '\\', '/'
        if ($Relative -notmatch '^\.copilot-tracking/squad(?:/members/[A-Za-z0-9][A-Za-z0-9_-]*)?$') { throw 'squadRoot must be the single-squad root or one member root inside RepoRoot.' }
        Assert-UnlinkedPath $Root
        $EmptyRoot = $false
        if (Get-Item -LiteralPath $Root -Force -ErrorAction SilentlyContinue) {
            $null = Get-EmptyDirectoryTree $Root
            $EmptyRoot = $true
        }
        $Mode = if ($Payload.Contains('mode')) { $Payload.mode } else { 'interactive' }
        if ($Mode -notin @('interactive', 'autonomous', 'autopilot')) { throw 'Invalid mode.' }
        $Routing = if ($Payload.Contains('modelRouting')) { $Payload.modelRouting } else { 'off' }
        if ($Routing -notin @('off', 'ranked', 'economy', 'manual')) { throw 'Invalid modelRouting.' }
        $State = Get-Seed 'entry-schemas.md' 'state.json' 'json' | ConvertFrom-Json -AsHashtable
        $State.updated = $Timestamp.ToString('o')
        $State.turn = 1
        $State.mode = $Mode
        if ($Payload.Contains('stateAdvance')) {
            Assert-ObjectKey $Payload.stateAdvance @('activeRoles') @('mode', 'sessionModel', 'modelOverrides', 'openEscalationsRaised', 'openEscalationsResolved')
            foreach ($Key in @('sessionModel', 'modelOverrides')) {
                if ($Payload.stateAdvance.Contains($Key)) {
                    if ($Payload.Contains($Key)) { throw "Supply $Key only once." }
                    $Payload[$Key] = $Payload.stateAdvance[$Key]
                }
            }
            if ($Payload.stateAdvance.Contains('mode')) {
                if ($Payload.Contains('mode') -and $Mode -ne $Payload.stateAdvance.mode) { throw 'Conflicting mode.' }
                $State.mode = $Payload.stateAdvance.mode
                if ($State.mode -notin @('interactive', 'autonomous', 'autopilot')) { throw 'Invalid stateAdvance.mode.' }
            }
            if (@($Payload.stateAdvance.activeRoles).Count -ne 0) { throw 'Fresh Init cannot record work roles.' }
            foreach ($Key in @('openEscalationsRaised', 'openEscalationsResolved')) {
                if ($Payload.stateAdvance.Contains($Key) -and @($Payload.stateAdvance[$Key]).Count -gt 0) { throw 'Fresh Init cannot record escalations.' }
            }
        }
        foreach ($Key in @('sessionModel', 'modelOverrides')) {
            if ($Payload.Contains($Key)) { $State.currentRun[$Key] = $Payload[$Key] }
        }
        Assert-Text $State.currentRun.sessionModel -AllowEmpty
        Assert-ObjectKey $State.currentRun.modelOverrides @() @($State.currentRun.modelOverrides.Keys)
        foreach ($Value in $State.currentRun.modelOverrides.Values) { Assert-Text $Value }
        $NotifyDefaulted = -not $Payload.Contains('notify')
        if (-not $NotifyDefaulted) {
            Assert-ObjectKey $Payload.notify @('approvalChannel', 'enabled') @('email', 'github')
            if ($Payload.notify.enabled -isnot [bool] -or $Payload.notify.approvalChannel -notin @('in-chat', 'github-issue', 'webhook')) { throw 'Invalid notify configuration.' }
            foreach ($Key in $Payload.notify.Keys) { $State.notify[$Key] = $Payload.notify[$Key] }
            Assert-Text $State.notify.email -AllowEmpty
            Assert-ObjectKey $State.notify.github @('handle', 'repo')
            foreach ($Value in $State.notify.github.Values) { Assert-Text $Value -AllowEmpty }
            if ($State.notify.enabled -and $State.notify.approvalChannel -eq 'github-issue') {
                Assert-Text $State.notify.github.handle
                Assert-Text $State.notify.github.repo
            }
        }
        $Columns = @('Role', 'Member Name', 'Agent Name (Primary)', 'Alternate Agents', 'Selection Cue', 'Invocation', 'Model Tier')
        if ($Routing -ne 'off') { $Columns += 'Model' }
        $Columns += 'Deliverable Root'
        if ($Payload.roster -isnot [array] -or $Payload.roster.Count -eq 0) { throw 'Missing confirmed roster rows.' }
        $Identities = @{}
        $Roles = @()
        $Rows = foreach ($Row in $Payload.roster) {
            Assert-ObjectKey $Row ($Columns | Where-Object { $_ -ne 'Member Name' }) @('Member Name')
            if (-not $Row.Contains('Member Name')) { $Row['Member Name'] = '' }
            foreach ($Column in $Columns) { Assert-Text $Row[$Column] -AllowEmpty:($Column -in @('Member Name', 'Alternate Agents', 'Model')) }
            if ($Row.Role -notmatch '^[a-z][a-z0-9-]*$' -or $Row['Agent Name (Primary)'] -match '[/\\<>:]' -or $Row['Agent Name (Primary)'] -eq [string][char]0x2014) { throw 'Invalid role or Agent Name (Primary).' }
            if ($Row['Model Tier'] -notin @('fast', 'default', 'extended')) { throw 'Invalid Model Tier.' }
            $Identity = $Row.Role + ':' + $Row['Member Name']
            if ($Identities.ContainsKey($Identity) -or ($Row.Role -in $Roles -and (-not $Row['Member Name'] -or $Identities.ContainsKey($Row.Role + ':')))) { throw 'Duplicate roles require unique supplied Member Names.' }
            $Identities[$Identity] = $true
            $Roles += $Row.Role
            $Row['Deliverable Root'] = Resolve-InitDeliverable $Row['Deliverable Root'] $Relative $Repository
            if ($Row.Role -eq 'intake-validator') {
                $CaptureRoot = $Row['Deliverable Root'].TrimEnd('/')
                if ($CaptureRoot -in @('-', [string][char]0x2014, '(squad state)') -or
                    $CaptureRoot -match '\s+or\s+|[<>]' -or
                    $CaptureRoot -match '^\.copilot-tracking/squad(?:/members/[^/]+)?(?:$|/(?:team\.md|routing\.md|decisions\.md|notifications\.md|state\.json|consumption(?:-rates)?\.md|history|memory)(?:/|$))') {
                    throw 'intake-validator requires an explicit non-state capture directory; no fallback root is allowed.'
                }
                Assert-UnlinkedPath ([System.IO.Path]::GetFullPath($CaptureRoot, $Repository))
            }
            '| ' + (($Columns | ForEach-Object { $Row[$_] }) -join ' | ') + ' |'
        }
        if ('scribe' -notin $Roles -or @($Payload.roster | Where-Object { $_.Role -eq 'scribe' -and $_['Agent Name (Primary)'] -eq 'Squad Scribe' }).Count -ne 1) { throw 'Confirmed Squad Scribe roster row required.' }
        if ($Direct) {
            Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force
            $AgentRepository = (Resolve-Path -LiteralPath $AgentRepoRoot).ProviderPath
            Assert-UnlinkedPath $AgentRepository
            if ($AgentRepository -ine $Repository) {
                $StageRelative = [IO.Path]::GetRelativePath($AgentRepository, $Repository) -replace '\\', '/'
                if ($StageRelative -cnotmatch '^\.copilot-tracking/\.squad-federation-init-[a-f0-9]+/repository$') {
                    throw 'AgentRepoRoot may differ only for the owned federation Init staging repository.'
                }
            }
            $AgentIndex = Get-SquadAgentIndex $AgentRepository
            foreach ($Row in $Payload.roster) {
                $Primary = $Row['Agent Name (Primary)']
                if (-not $AgentIndex.ContainsKey($Primary) -or -not $AgentIndex[$Primary].dispatchable) {
                    throw "Confirmed Primary '$Primary' is not installed and dispatchable."
                }
            }
        }
        if ($Payload.Contains('usage') -and ($Payload.usage -isnot [array] -or $Payload.usage.Count -eq 0)) { throw 'Supplied usage must be a nonempty array.' }
        $SuppliedActors = @(if ($Payload.Contains('usage')) { $Payload.usage | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { $_['actor'] } })
        $RequiredActors = @(if ($Direct) { 'coordinator' } else { 'coordinator'; 'scribe' })
        if (@($SuppliedActors | Where-Object { $_ -notin $RequiredActors }).Count) { throw 'Direct initialization cannot record a Scribe actor.' }
        $EstimatedActors = @($RequiredActors | Where-Object { $_ -notin $SuppliedActors })
        $UsageEstimated = $EstimatedActors.Count -gt 0
        if ($UsageEstimated) {
            $ScribeRow = @($Payload.roster | Where-Object { $_.Role -eq 'scribe' })[0]
            $Derived = @(Get-InitUsage -SessionModel $State.currentRun.sessionModel -ScribeTier $ScribeRow['Model Tier'] -Actors $RequiredActors | Where-Object { $_.actor -in $EstimatedActors })
            $Payload.usage = @(@(if ($Payload.Contains('usage')) { $Payload.usage }) + $Derived)
        }
        $ConsumptionKeys = @('model', 'model_source', 'priced_as', 'model_tier', 'internal_turns', 'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens', 'basis')
        $History = (Get-Seed 'entry-schemas.md' 'history/<agent>.md').Replace('<agent>', 'Squad Scribe')
        $Actors = @()
        foreach ($Usage in $Payload.usage) {
            Assert-ObjectKey $Usage @('actor', 'consumption')
            if ($Usage.actor -notin $RequiredActors -or $Usage.actor -in $Actors) { throw 'Usage must identify an actual setup actor, once each.' }
            $Actors += $Usage.actor
            Assert-ObjectKey $Usage.consumption $ConsumptionKeys
            $Block = [ordered]@{}
            foreach ($Key in $ConsumptionKeys) {
                $Value = $Usage.consumption[$Key]
                if ($Key -in @('internal_turns', 'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens')) {
                    if ($Value -isnot [long] -and $Value -isnot [int] -or $Value -lt 0) { throw "Invalid consumption.$Key" }
                }
                else { Assert-Text $Value }
                $Block[$Key] = $Value
            }
            if ($Block.model_source -notin @('dispatch-reported', 'agent-pinned', 'operator-declared', 'session-inherited', 'cli-pinned', 'unresolved') -or $Block.model_tier -notin @('fast', 'default', 'extended') -or $Block.basis -notin @('estimated', 'tier-default')) { throw 'Invalid consumption attribution, tier, or basis.' }
            if ($Block.model -eq 'auto' -or (($Block.model_source -eq 'unresolved') -ne ($Block.model -eq 'unknown'))) { throw 'auto is not an actual model; use unknown/unresolved when unreported.' }
            if ($Block.model_source -eq 'session-inherited' -and ($State.currentRun.sessionModel -in @('', 'auto') -or $Block.model -ne $State.currentRun.sessionModel)) { throw 'session-inherited requires the supplied concrete sessionModel.' }
            if ($Block.model_source -eq 'agent-pinned') { throw 'Supply actual dispatch-reported usage rather than inferring a pin.' }
            $Fence = '```'
            $Heading = '#### Consumption ' + [char]0x2014 + ' Orchestration'
            $Outcome = if ($Usage.actor -in $EstimatedActors) { "Estimator-derived setup usage for $($Usage.actor); documented orchestration floor, not measured tokens or billed telemetry." } else { "Setup usage recorded for $($Usage.actor)." }
            $History += "`n### $($State.updated) Initialization $($Usage.actor)`n`n* Turn: 1`n* Request: Confirmed initialization`n* Deliverable: squad state`n* Outcome: $Outcome`n`n$Heading`n`n${Fence}json`n$($Block | ConvertTo-Json)`n$Fence`n"
        }
        $Team = Get-Seed 'seed-templates.md' 'team.md'
        $Team = $Team.Substring(0, $Team.IndexOf('| Role'))
        if ($Routing -ne 'off') { $Team = $Team.Replace('# Squad Roster', "# Squad Roster`nModel routing: $Routing") }
        $Team += '| ' + ($Columns -join ' | ') + " |`n| " + (($Columns | ForEach-Object { '---' }) -join ' | ') + " |`n" + ($Rows -join "`n") + "`n"
        $Routes = (Get-Seed 'seed-templates.md' 'routing.md') -split "`n" | Where-Object {
            if ($_ -notmatch '^\| ' -or $_ -match '^\| Pattern|^\|\s*-') { return $true }
            $Cells = $_.Trim('|').Split('|')
            $RouteRoles = @($Cells[1].Trim() -split ',\s*' | ForEach-Object { $_ -replace ' \(optional\)$', '' })
            return ($Cells[0] -match 'council' -or @($RouteRoles | Where-Object { $_ -notin $Roles }).Count -eq 0)
        }
        $Parent = Split-Path -Path $Root -Parent
        [System.IO.Directory]::CreateDirectory($Parent) | Out-Null
        Assert-UnlinkedPath $Parent
        $Stage = Join-Path $Parent ('.squad-init-' + [guid]::NewGuid().ToString('N'))
        [System.IO.Directory]::CreateDirectory((Join-Path $Stage 'history')) | Out-Null
        Write-Seed 'team.md' $Team
        Write-Seed 'routing.md' ($Routes -join "`n")
        Write-Seed 'state.json' ($State | ConvertTo-Json -Depth 20)
        Write-Seed 'decisions.md' ((Get-Seed 'entry-schemas.md' 'decisions.md') + "`n## Initialization $($State.updated)`n`n* Turn: 1`n* Provenance: $($Payload.provenance)`n* Model routing: $Routing`n")
        Write-Seed 'notifications.md' "---`ndescription: Append-only squad notifications`n---`n`n# Squad Notifications`n"
        Write-Seed 'history/Squad Scribe.md' $History
        Write-Seed 'consumption.md' ((Get-Seed 'consumption.md' 'consumption.md').Replace('<run-id>', $Payload.runId))
        $SeedStatus = Invoke-Helper 'Initialize-SquadConsumptionRates.ps1' @('-SquadRoot', $Stage)
        Assert-InitPricing -Usage $Payload.usage -RateContent ([System.IO.File]::ReadAllText((Join-Path $Stage 'consumption-rates.md')))
        $LedgerStatus = Invoke-Helper 'Measure-SquadLedger.ps1' @('-SquadRoot', $Stage, '-Write')
        $Check = Invoke-Helper 'Measure-SquadLedger.ps1' @('-SquadRoot', $Stage, '-Check', '-ExpectedHistoryCounts', "Squad Scribe=$($Payload.usage.Count)")
        if ($Check -notmatch 'Measure-SquadLedger -Check: PASS') { throw 'Ledger returned no PASS.' }
        $Warnings = @(("$SeedStatus`n$LedgerStatus`n$Check" -split "`n") | Where-Object { $_ -match '^WARN(?:ING)?[: ]' } | Select-Object -Unique)
        if ($NotifyDefaulted) { $Warnings += 'Notifications defaulted to disabled in-chat.' }
        if ($UsageEstimated) { $Warnings += "Estimator-derived setup usage for $($EstimatedActors -join ' and '): shipped Scribe state write orchestration floor; estimates are not measured tokens or billed telemetry." }
        $WrittenTeam = [System.IO.File]::ReadAllText((Join-Path $Stage 'team.md'))
        if ($WrittenTeam -ne $Team -or @((Get-ChildItem -LiteralPath (Join-Path $Stage 'history') -File)).Count -ne 1) { throw 'Roster/history verification failed.' }
        Assert-UnlinkedPath $Root
        if ($EmptyRoot) {
            # Nonrecursive deletes make any file that arrives after validation block publication.
            $Empty = @(Get-EmptyDirectoryTree $Root)
            [array]::Reverse($Empty)
            foreach ($Directory in $Empty) { [System.IO.Directory]::Delete($Directory, $false) }
        }
        [System.IO.Directory]::Move($Stage, $Root)
        $Stage = $null
        [ordered]@{ status = 'PASS'; verified = $true; turn = 1; squadRoot = $Root; rosterCheck = 'PASS'; ledgerCheck = 'PASS'; historyEntries = $Payload.usage.Count; actors = $RequiredActors; notificationsDefaulted = $NotifyDefaulted; warnings = $Warnings } | ConvertTo-Json -Compress
        exit 0
    }
    catch {
        [Console]::Error.WriteLine("Initialize-Squad: $($_.Exception.Message)")
        exit 1
    }
    finally {
        if ($Stage -and (Test-Path -LiteralPath $Stage)) { Remove-Item -LiteralPath $Stage -Recurse -Force }
    }
}
