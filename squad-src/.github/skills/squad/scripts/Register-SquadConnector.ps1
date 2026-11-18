#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Registers one new connector binding with a deterministic squad-state transaction.
.DESCRIPTION
    AI cost: none. Validates a 1.1 manifest and one replace/add registration, then
    previews or writes team.md, routing.md, and an append-only decisions.md entry.
    Exact reruns are no-ops. Existing binding IDs may not be changed or removed;
    those identity changes retain the cold Scribe retirement-evidence path.

    The transaction preserves state, history, notifications, and accounting
    byte-for-byte, serializes with the ordinary squad writer lock, verifies every
    owned output, checks the ledger read-only, and restores owned files on failure.
.PARAMETER InputPath
    Optional closed-shape JSON input. Inline parameters are the alternative.
.PARAMETER Confirmed
    Applies the validated registration. Without it, the script only returns a
    validated preview and writes no squad state.
.PARAMETER ManifestPath
    Repository-contained connector manifest path.
.PARAMETER RoleMode
    `replace` overlays an existing internal role row. `add` creates a distinct
    Squad Connector member and one routing row.
.EXAMPLE
    pwsh -File ./Register-SquadConnector.ps1 -RepoRoot . `
        -ManifestPath connectors/org-research.json -BindingId research-org `
        -RoleMode replace -TargetRole researcher -MemberName "Org Researcher" `
        -DefaultExecution connector
.EXAMPLE
    pwsh -File ./Register-SquadConnector.ps1 -RepoRoot . `
        -ManifestPath connectors/org-research.json -BindingId research-org `
        -RoleMode replace -TargetRole researcher -MemberName "Org Researcher" `
        -DefaultExecution connector -Confirmed
#>

[CmdletBinding(DefaultParameterSetName = 'Inline')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Input')]
    [string]$InputPath,

    [string]$RepoRoot = (Get-Location).ProviderPath,
    [string]$SquadRoot = '.copilot-tracking/squad',

    [Parameter(Mandatory, ParameterSetName = 'Inline')]
    [string]$ManifestPath,

    [Parameter(Mandatory, ParameterSetName = 'Inline')]
    [string]$BindingId,

    [Parameter(Mandatory, ParameterSetName = 'Inline')]
    [ValidateSet('replace', 'add')]
    [string]$RoleMode,

    [Parameter(Mandatory, ParameterSetName = 'Inline')]
    [string]$TargetRole,

    [Parameter(ParameterSetName = 'Inline')]
    [string]$TargetMember,

    [Parameter(Mandatory, ParameterSetName = 'Inline')]
    [string]$MemberName,

    [Parameter(Mandatory, ParameterSetName = 'Inline')]
    [ValidateSet('original', 'connector', 'ask', 'both')]
    [string]$DefaultExecution,

    [Parameter(ParameterSetName = 'Inline')]
    [string]$AlignedRole,

    [Parameter(ParameterSetName = 'Inline')]
    [string]$SelectionCue,

    [Parameter(ParameterSetName = 'Inline')]
    [ValidateSet('fast', 'default', 'extended')]
    [string]$ModelTier = 'default',

    [Parameter(ParameterSetName = 'Inline')]
    [string]$Model,

    [Parameter(ParameterSetName = 'Inline')]
    [string]$DeliverableRoot,

    [Parameter(ParameterSetName = 'Inline')]
    [string]$AlternateAgents,

    [Parameter(ParameterSetName = 'Inline')]
    [string]$Invocation = 'runSubagent / task',

    [Parameter(ParameterSetName = 'Inline')]
    [string]$RoutePattern,

    [Parameter(ParameterSetName = 'Inline')]
    [ValidateSet('auto', 'confirm', 'escalate')]
    [string]$AutonomyTier = 'confirm',

    [Parameter(ParameterSetName = 'Inline')]
    [switch]$ParallelEligible,

    [Parameter(ParameterSetName = 'Inline')]
    [string]$RunId = 'connector-registration',

    [Parameter(ParameterSetName = 'Inline')]
    [string]$ConfirmationRef,

    [Parameter(ParameterSetName = 'Inline')]
    [string]$Rationale,

    [switch]$Confirmed,

    [ValidateRange(1, 3600)]
    [int]$LockTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:registrationBoundParameters = $PSBoundParameters
$script:registrationParameterSet = $PSCmdlet.ParameterSetName
$script:registrationInputPath = $InputPath

Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SquadPromotion.psm1') -Force
. (Join-Path $PSScriptRoot 'Resolve-SquadConnectorDispatch.ps1')

$script:locks = [Collections.Generic.List[IO.FileStream]]::new()
$script:root = $null
$script:originals = [ordered]@{}
$script:planned = [ordered]@{}
$script:wrote = $false

function Assert-RegistrationFieldSet {
    param($Object, [string[]]$Required, [string[]]$Optional = @())
    if ($Object -isnot [Collections.IDictionary]) { throw 'Registration input must be a JSON object.' }
    foreach ($key in $Required) {
        if (-not $Object.Contains($key)) { throw "Registration input is missing '$key'." }
    }
    foreach ($key in $Object.Keys) {
        if ($key -notin ($Required + $Optional)) { throw "Unsupported registration input field: $key" }
    }
}

function Assert-RegistrationLine {
    param([AllowNull()]$Value, [string]$Name, [switch]$AllowEmpty)
    if ($null -eq $Value -or $Value -isnot [string] -or
        $Value -match '[\r\n|\x00-\x1f]' -or
        (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value))) {
        throw "Registration field '$Name' must be one nonempty line without table delimiters or control characters."
    }
}

function Get-RegistrationHash {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Get-RegistrationFileSnapshot {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Linked squad-state file refused: $Path"
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    [ordered]@{ bytes = $bytes.Length; sha256 = Get-RegistrationHash $bytes }
}

function Get-RegistrationDocument {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf
    $body = if ($hasBom -and $bytes.Length -gt 3) { $bytes[3..($bytes.Length - 1)] }
    elseif ($hasBom) { [byte[]]::new(0) }
    else { $bytes }
    $text = [Text.UTF8Encoding]::new($false).GetString($body)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $trailing = $text.EndsWith("`n")
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in ($text -split '\r?\n')) { $null = $lines.Add($line) }
    if ($trailing -and $lines.Count -and $lines[-1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    [pscustomobject]@{
        bytes   = $bytes
        hasBom  = $hasBom
        newline = $newline
        trailing = $trailing
        lines   = $lines
    }
}

function ConvertTo-RegistrationDocumentByteArray {
    param([Parameter(Mandatory)]$Document)
    $text = ($Document.lines -join $Document.newline) + $(if ($Document.trailing) { $Document.newline })
    $body = [Text.UTF8Encoding]::new($false).GetBytes($text)
    if (-not $Document.hasBom) { return ,$body }
    $result = [byte[]]::new($body.Length + 3)
    $result[0] = 0xef
    $result[1] = 0xbb
    $result[2] = 0xbf
    [Array]::Copy($body, 0, $result, 3, $body.Length)
    ,$result
}

function ConvertFrom-RegistrationTableLine {
    param([Parameter(Mandatory)][string]$Line)
    @($Line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
}

function Get-RegistrationTable {
    param(
        [AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string[]]$RequiredHeaders,
        [switch]$Required
    )
    $tables = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -notmatch '^\s*\|') { continue }
        $header = @(ConvertFrom-RegistrationTableLine $Lines[$index] | ForEach-Object { $_.Trim('`') })
        if (@($RequiredHeaders | Where-Object { $_ -notin $header }).Count) { continue }
        if ($index + 1 -ge $Lines.Count -or $Lines[$index + 1] -notmatch '^\s*\|') {
            throw 'Markdown table is missing its separator row.'
        }
        $end = $index + 2
        while ($end -lt $Lines.Count -and $Lines[$end] -match '^\s*\|') { $end++ }
        $null = $tables.Add([pscustomobject]@{
                start = $index
                end = $end
                header = $header
            })
    }
    if ($tables.Count -gt 1) { throw "Expected at most one table with headers: $($RequiredHeaders -join ', ')." }
    if ($tables.Count -eq 0) {
        if ($Required) { throw "Missing table with headers: $($RequiredHeaders -join ', ')." }
        return $null
    }
    $tables[0]
}

function Get-RegistrationInput {
    $registration = if ($script:registrationParameterSet -eq 'Input') {
        $path = (Resolve-Path -LiteralPath $script:registrationInputPath).ProviderPath
        $item = Get-Item -LiteralPath $path -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Linked registration input refused.'
        }
        $cursor = Split-Path -Parent $path
        while ($cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Linked registration input directory refused: $cursor"
            }
            $cursor = Split-Path -Parent $cursor
        }
        $stateRoot = [IO.Path]::GetFullPath((Join-Path -Path $RepoRoot -ChildPath '.copilot-tracking' -AdditionalChildPath 'squad'))
        $relative = [IO.Path]::GetRelativePath($stateRoot, $path)
        if ($relative -ne '..' -and $relative -notmatch '^\.\.[\\/]' -and
            -not [IO.Path]::IsPathRooted($relative)) {
            throw 'Registration input must be outside squad state.'
        }
        Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 32
    }
    else {
        $value = [ordered]@{
            manifestPath = $ManifestPath
            bindingId = $BindingId
            roleMode = $RoleMode
            targetRole = $TargetRole
            memberName = $MemberName
            defaultExecution = $DefaultExecution
            runId = $RunId
        }
        if ($script:registrationBoundParameters.ContainsKey('TargetMember')) { $value.targetMember = $TargetMember }
        if ($script:registrationBoundParameters.ContainsKey('AlignedRole')) { $value.alignedRole = $AlignedRole }
        if ($script:registrationBoundParameters.ContainsKey('SelectionCue')) { $value.selectionCue = $SelectionCue }
        if ($script:registrationBoundParameters.ContainsKey('ModelTier')) { $value.modelTier = $ModelTier }
        if ($script:registrationBoundParameters.ContainsKey('Model')) { $value.model = $Model }
        if ($script:registrationBoundParameters.ContainsKey('DeliverableRoot')) { $value.deliverableRoot = $DeliverableRoot }
        if ($script:registrationBoundParameters.ContainsKey('AlternateAgents')) { $value.alternateAgents = $AlternateAgents }
        if ($script:registrationBoundParameters.ContainsKey('Invocation')) { $value.invocation = $Invocation }
        if ($script:registrationBoundParameters.ContainsKey('ConfirmationRef')) { $value.confirmationRef = $ConfirmationRef }
        if ($script:registrationBoundParameters.ContainsKey('Rationale')) { $value.rationale = $Rationale }
        if ($script:registrationBoundParameters.ContainsKey('RoutePattern')) {
            $value.route = [ordered]@{
                pattern = $RoutePattern
                autonomyTier = $AutonomyTier
                parallelEligible = [bool]$ParallelEligible
            }
        }
        elseif ($script:registrationBoundParameters.ContainsKey('AutonomyTier') -or
            $script:registrationBoundParameters.ContainsKey('ParallelEligible')) {
            throw 'RoutePattern is required when AutonomyTier or ParallelEligible is supplied.'
        }
        $value
    }

    Assert-RegistrationFieldSet -Object $registration -Required @(
        'manifestPath', 'bindingId', 'roleMode', 'targetRole', 'memberName',
        'defaultExecution', 'runId'
    ) -Optional @(
        'squadRoot', 'targetMember', 'alignedRole', 'selectionCue', 'modelTier',
        'model', 'deliverableRoot', 'alternateAgents', 'invocation', 'route',
        'confirmationRef', 'rationale', 'confirmed'
    )
    foreach ($name in @('manifestPath', 'bindingId', 'roleMode', 'targetRole', 'memberName', 'defaultExecution', 'runId')) {
        Assert-RegistrationLine -Value $registration[$name] -Name $name
    }
    foreach ($name in @('squadRoot', 'targetMember', 'alignedRole', 'selectionCue', 'modelTier', 'model', 'deliverableRoot', 'alternateAgents', 'invocation', 'confirmationRef', 'rationale')) {
        if ($registration.Contains($name)) {
            Assert-RegistrationLine -Value $registration[$name] -Name $name `
                -AllowEmpty:($name -in @(
                    'targetMember', 'alignedRole', 'selectionCue', 'model',
                    'deliverableRoot', 'alternateAgents', 'confirmationRef', 'rationale'
                ))
        }
    }
    if ($registration.Contains('confirmed') -and $registration.confirmed -isnot [bool]) {
        throw "Registration field 'confirmed' must be boolean."
    }
    if ($Confirmed -and $registration.Contains('confirmed') -and -not $registration.confirmed) {
        throw 'The registration input does not carry confirmed=true.'
    }
    foreach ($name in @($registration.Keys)) {
        if ($name -ne 'route' -and $registration[$name] -is [string]) {
            $registration[$name] = $registration[$name].Trim()
        }
    }
    if ($registration.roleMode -notin @('replace', 'add')) { throw "Invalid roleMode '$($registration.roleMode)'." }
    if ($registration.defaultExecution -notin @('original', 'connector', 'ask', 'both')) {
        throw "Invalid defaultExecution '$($registration.defaultExecution)'."
    }
    if ($registration.roleMode -eq 'replace') {
        $addOnly = @(
            'selectionCue', 'modelTier', 'model', 'deliverableRoot',
            'alternateAgents', 'invocation', 'route'
        )
        $unexpected = @($addOnly | Where-Object { $registration.Contains($_) })
        if ($unexpected.Count) {
            throw "Replace registration does not accept add-only fields: $($unexpected -join ', ')"
        }
    }
    elseif ($registration.Contains('targetMember')) {
        throw 'Additive registration derives its target member from memberName; targetMember is not accepted.'
    }
    if ($registration.bindingId -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw 'bindingId must be lower-kebab-case.'
    }
    if ($registration.memberName -in @('-', [string][char]0x2014)) {
        throw 'memberName must identify the connector-backed member, not a placeholder.'
    }
    if ($registration.targetRole -cnotmatch '^[a-z][a-z0-9-]*$') {
        throw 'targetRole must be a lower-kebab-case role id.'
    }
    if ($registration.targetRole -in @('scribe', 'coordinator', 'federation-coordinator', 'council')) {
        throw "Role '$($registration.targetRole)' is reserved for HVE governance."
    }
    if ($registration.Contains('modelTier') -and $registration.modelTier -notin @('fast', 'default', 'extended')) {
        throw "Invalid modelTier '$($registration.modelTier)'."
    }
    if ($registration.Contains('model') -and $registration.model -and $registration.model -cnotmatch '^[a-z0-9][a-z0-9.-]*$') {
        throw "Invalid model id '$($registration.model)'."
    }
    if (@(Get-ConnectorDocumentIssuesLocal -Object $registration).Count -gt 0) {
        throw 'Registration input contains an oversized or secret-bearing value.'
    }

    if ($registration.Contains('route')) {
        Assert-RegistrationFieldSet -Object $registration.route `
            -Required @('pattern', 'autonomyTier', 'parallelEligible')
        Assert-RegistrationLine -Value $registration.route.pattern -Name 'route.pattern'
        $registration.route.pattern = $registration.route.pattern.Trim()
        $registration.route.autonomyTier = ([string]$registration.route.autonomyTier).Trim()
        if ($registration.route.autonomyTier -notin @('auto', 'confirm', 'escalate')) {
            throw "Invalid route.autonomyTier '$($registration.route.autonomyTier)'."
        }
        if ($registration.route.parallelEligible -isnot [bool]) {
            throw "route.parallelEligible must be boolean."
        }
    }
    $registration
}

function Get-RegistrationBaseline {
    param([string]$Root, [string]$Repository, [string]$RelativeRoot)
    $files = [ordered]@{}
    foreach ($name in @(
            'team.md', 'routing.md', 'decisions.md', 'notifications.md',
            'state.json', 'consumption.md', 'consumption-rates.md'
        )) {
        $path = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing required squad state: $name"
        }
        $files[$name] = Get-RegistrationFileSnapshot $path
    }
    $sessionCache = Join-Path $Root 'consumption-sessions.json'
    if (Test-Path -LiteralPath $sessionCache -PathType Leaf) {
        $files['consumption-sessions.json'] = Get-RegistrationFileSnapshot $sessionCache
    }
    $history = Join-Path $Root 'history'
    if (-not (Test-Path -LiteralPath $history -PathType Container)) {
        throw 'Missing required squad state: history'
    }
    $baseline = [ordered]@{
        files = $files
        history = Get-SquadPromotionTreeSnapshot $history
    }
    if ($RelativeRoot -match '^\.copilot-tracking/squad/members/(?<name>[a-z0-9][a-z0-9-]*)$') {
        $member = $Matches.name
        $registryPath = Join-Path $Repository '.copilot-tracking/squad/federation.md'
        if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
            throw "Federation registry is missing for member '$member'."
        }
        $registries = @(Read-SquadTables $registryPath |
                Where-Object { 'Sub-squad' -in $_.Header -and 'Location' -in $_.Header })
        if ($registries.Count -ne 1) { throw 'Federation registry is missing or ambiguous.' }
        $rows = @($registries[0].Rows | Where-Object {
                $_['Sub-squad'] -ceq $member -and
                (($_.Location -replace '\\', '/').TrimEnd('/')) -ceq "members/$member"
            })
        if ($rows.Count -ne 1) { throw "Member '$member' is not registered at its selected root." }
        $baseline.federation = [ordered]@{
            member = $member
            registry = Get-RegistrationFileSnapshot $registryPath
        }
    }
    $baseline
}

function Assert-RegistrationBaseline {
    param(
        [Parameter(Mandatory)]$Expected,
        [string]$Root,
        [string]$Repository,
        [string]$RelativeRoot,
        [string[]]$IgnoreFiles = @()
    )
    $actual = Get-RegistrationBaseline -Root $Root -Repository $Repository -RelativeRoot $RelativeRoot
    foreach ($name in $Expected.files.Keys) {
        if ($name -in $IgnoreFiles) { continue }
        foreach ($field in @('bytes', 'sha256')) {
            if ($Expected.files[$name][$field] -cne $actual.files[$name][$field]) {
                throw "Connector registration collision: $name changed during the transaction."
            }
        }
    }
    foreach ($field in @('digest', 'files', 'directories', 'bytes')) {
        if ($Expected.history[$field] -cne $actual.history[$field]) {
            throw 'Connector registration collision: history changed during the transaction.'
        }
    }
    if ($Expected.Contains('federation')) {
        foreach ($field in @('bytes', 'sha256')) {
            if ($Expected.federation.registry[$field] -cne $actual.federation.registry[$field]) {
                throw 'Connector registration collision: federation registry changed during the transaction.'
            }
        }
    }
}

function Enter-RegistrationWriterLock {
    param([string]$Path, [DateTime]$Deadline)
    $key = (Get-RegistrationHash ([Text.UTF8Encoding]::new($false).GetBytes($Path.ToLowerInvariant()))).Substring(0, 16)
    $lockPath = Join-Path ([IO.Path]::GetTempPath()) "hve-squad-handoff-$key.lock"
    while ($true) {
        try {
            return [IO.FileStream]::new(
                $lockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        }
        catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $Deadline) {
                throw 'Connector registration writer lock timed out; nothing was written.'
            }
            Start-Sleep -Milliseconds 200
        }
    }
}

function Write-RegistrationAtomicFile {
    param([string]$Path, [byte[]]$Bytes)
    if (Test-Path -LiteralPath $Path) {
        $probe = $null
        try {
            $probe = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        finally {
            if ($probe) { $probe.Dispose() }
        }
    }
    $temporary = Join-Path (Split-Path -Parent $Path) (".$([IO.Path]::GetFileName($Path)).$([guid]::NewGuid().ToString('N')).tmp")
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        [IO.File]::Move($temporary, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Add-RegistrationDecision {
    param([byte[]]$Before, [string]$Entry)
    $hasBom = $Before.Length -ge 3 -and $Before[0] -eq 0xef -and $Before[1] -eq 0xbb -and $Before[2] -eq 0xbf
    $body = if ($hasBom -and $Before.Length -gt 3) { $Before[3..($Before.Length - 1)] }
    elseif ($hasBom) { [byte[]]::new(0) }
    else { $Before }
    $text = [Text.UTF8Encoding]::new($false).GetString($body)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $prefix = if (-not $Before.Length) { '' } elseif ($text.EndsWith("`n")) { $newline } else { "$newline$newline" }
    $tail = $prefix + ($Entry -replace '\r?\n', $newline) + $newline
    $tailBytes = [Text.UTF8Encoding]::new($false).GetBytes($tail)
    $result = [byte[]]::new($Before.Length + $tailBytes.Length)
    [Array]::Copy($Before, 0, $result, 0, $Before.Length)
    [Array]::Copy($tailBytes, 0, $result, $Before.Length, $tailBytes.Length)
    ,$result
}

function Resolve-RegistrationDeliverable {
    param([string]$Value, [string]$RelativeRoot, [string]$Repository)
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'Additive connector registration requires deliverableRoot.' }
    if ($Value -eq '(squad state)' -or $Value -eq [string][char]0x2014) {
        throw 'Additive connector output requires an explicit deliverable directory, not squad state.'
    }
    $path = $Value.Trim().Trim('`') -replace '\\', '/'
    if ($path -match '(^|/)\.\.(/|$)|^[~/]|:|\s+or\s+') { throw 'Unsafe connector deliverableRoot.' }
    $canonical = ([IO.Path]::GetRelativePath(
            $Repository,
            [IO.Path]::GetFullPath($path, $Repository)
        ) -replace '\\', '/').TrimEnd('/')
    if ($canonical -eq '.' -or $canonical -match '^\.\.(?:/|$)') {
        throw 'Unsafe connector deliverableRoot.'
    }
    if ($RelativeRoot -ne '.copilot-tracking/squad' -and $canonical -notmatch '^(?:docs|outputs)(?:/|$)') {
        if ($canonical -match '^\.copilot-tracking/squad/members(?:/|$)') {
            if ($canonical -cne $RelativeRoot -and
                -not $canonical.StartsWith($RelativeRoot + '/', [StringComparison]::Ordinal)) {
                throw 'Connector deliverableRoot must stay under the selected federation member.'
            }
        }
        else {
            if ($canonical.StartsWith('.copilot-tracking/', [StringComparison]::Ordinal)) {
                $canonical = $canonical.Substring('.copilot-tracking/'.Length)
            }
            $canonical = $RelativeRoot + '/' + $canonical
        }
    }
    $canonical + $(if ($path.EndsWith('/')) { '/' })
}

function Resolve-RegistrationAlignedClass {
    param(
        [string]$Role,
        [AllowEmptyCollection()][object[]]$Bindings,
        [hashtable]$ClassMap,
        [AllowEmptyCollection()][Collections.Generic.HashSet[string]]$Seen
    )
    if ($ClassMap.ContainsKey($Role)) { return $ClassMap[$Role] }
    if (-not $Seen.Add($Role)) { throw "Connector alignment cycle includes role '$Role'." }
    try {
        $alignments = @($Bindings | Where-Object {
                $_.RoleMode -eq 'add' -and $_.AddedRole -ceq $Role
            })
        if ($alignments.Count -ne 1) {
            throw "Aligned role '$Role' has no unambiguous assignment-class mapping."
        }
        $next = ([string]$alignments[0].AlignedRole).Trim().ToLowerInvariant()
        Resolve-RegistrationAlignedClass -Role $next -Bindings $Bindings -ClassMap $ClassMap -Seen $Seen
    }
    finally {
        $null = $Seen.Remove($Role)
    }
}

function Get-RegistrationProjection {
    param(
        [Collections.IDictionary]$Registration,
        [string]$Repository,
        [string]$Root,
        [string]$RelativeRoot
    )

    $manifestPath = Resolve-SquadRepositoryPath -RepoRoot $Repository -Path ([string]$Registration.manifestPath)
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Manifest file not found: $($Registration.manifestPath)"
    }
    $manifestBytes = [IO.File]::ReadAllBytes($manifestPath)
    $manifest = [Text.UTF8Encoding]::new($false).GetString($manifestBytes).TrimStart([char]0xfeff) |
        ConvertFrom-Json -AsHashtable -Depth 40
    $manifestShape = Test-SquadConnectorManifestShape -Manifest $manifest
    if ($manifestShape.Status -ne 'ok') {
        throw "Manifest validation failed: $($manifestShape.Issues -join ', ')"
    }
    if ($manifest.schemaVersion -ne '1.1') {
        throw 'Registration supports only connector manifest schema 1.1.'
    }
    if ([string]$manifest.connectorId -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw 'Manifest connectorId must be lower-kebab-case.'
    }
    $manifestRelative = ([IO.Path]::GetRelativePath($Repository, $manifestPath) -replace '\\', '/')

    $agentIndex = Get-SquadAgentIndex $Repository
    if (-not $agentIndex.ContainsKey('Squad Connector') -or
        -not $agentIndex['Squad Connector'].dispatchable) {
        throw "The registered 'Squad Connector' agent is not installed and dispatchable."
    }

    $teamPath = Join-Path $Root 'team.md'
    $routingPath = Join-Path $Root 'routing.md'
    $team = Get-RegistrationDocument $teamPath
    $routing = Get-RegistrationDocument $routingPath
    $memberHeaders = @(
        'Role', 'Member Name', 'Agent Name (Primary)', 'Alternate Agents',
        'Selection Cue', 'Invocation', 'Model Tier'
    )
    $memberTable = Get-RegistrationTable -Lines $team.lines -RequiredHeaders $memberHeaders -Required
    $recordedModes = @([regex]::Matches(
            ($team.lines -join "`n"),
            '(?m)^Model routing:\s*`?(?<mode>off|ranked|economy|manual)`?\s*$'
        ))
    if ($recordedModes.Count -gt 1) { throw 'team.md has more than one Model routing line.' }
    $routingMode = if ($recordedModes.Count) { $recordedModes[0].Groups['mode'].Value } else { 'off' }
    $hasModel = 'Model' -in $memberTable.header
    $expectedMemberHeaders = @($memberHeaders)
    if ($routingMode -ne 'off') { $expectedMemberHeaders += 'Model' }
    $expectedMemberHeaders += 'Deliverable Root'
    if (($memberTable.header -join "`n") -cne ($expectedMemberHeaders -join "`n")) {
        throw 'Connector registration requires the current canonical Members columns.'
    }
    if (($routingMode -ne 'off') -ne $hasModel) {
        throw 'team.md Model routing and Model column disagree.'
    }
    if ($Registration.Contains('model') -and $Registration.model -and $routingMode -eq 'off') {
        throw 'A connector Model cell requires active model routing.'
    }

    $bindingHeaders = @(
        'Binding ID', 'Connector ID', 'Manifest', 'Endpoint Kind', 'Role Mode',
        'Target Kind', 'Target', 'Member Name', 'Added Role', 'Aligned Role',
        'Default Execution'
    )
    $bindingHeadings = @(0..($team.lines.Count - 1) | Where-Object {
            $team.lines[$_] -match '^##\s+Connector Bindings\s*$'
        })
    if ($bindingHeadings.Count -gt 1) { throw 'team.md has more than one Connector Bindings heading.' }
    $bindingTable = Get-RegistrationTable -Lines $team.lines -RequiredHeaders $bindingHeaders
    if ($bindingHeadings.Count -eq 0 -and $null -ne $bindingTable) {
        throw 'Connector Bindings table is missing its required heading.'
    }
    if ($bindingHeadings.Count -eq 1 -and $null -eq $bindingTable) {
        throw 'Connector Bindings heading is missing the canonical table.'
    }
    if ($null -ne $bindingTable -and ($bindingTable.header -join "`n") -cne ($bindingHeaders -join "`n")) {
        throw 'Connector Bindings columns do not match the canonical header.'
    }

    $teamText = $team.lines -join "`n"
    $currentRoster = Get-SquadConnectorRosterState -TeamPath $teamPath -TeamContent $teamText
    $targetRole = ([string]$Registration.targetRole).ToLowerInvariant()
    $targetMember = if ($Registration.Contains('targetMember')) { [string]$Registration.targetMember } else { '' }
    $memberName = [string]$Registration.memberName
    $alignedRole = if ($Registration.Contains('alignedRole')) { ([string]$Registration.alignedRole).Trim().ToLowerInvariant() } else { '' }
    $existingBinding = @($currentRoster.Bindings | Where-Object {
            $_.BindingId -ceq [string]$Registration.bindingId
        })
    if ($existingBinding.Count -gt 1) { throw "Binding ID '$($Registration.bindingId)' is duplicated." }

    if ($Registration.roleMode -eq 'add' -and $Registration.defaultExecution -in @('original', 'both')) {
        throw "Additive connector registration cannot default to '$($Registration.defaultExecution)'."
    }
    if ($Registration.roleMode -eq 'replace') {
        $targets = @($currentRoster.Members | Where-Object {
                $_.Role -eq $targetRole -and $_.Agent -cne 'Squad Connector'
            })
        if ($targetMember) { $targets = @($targets | Where-Object { $_.MemberName -ceq $targetMember }) }
        if ($targets.Count -eq 0) { throw "No internal role row matches targetRole '$targetRole'." }
        if (-not $targetMember -and $targets.Count -gt 1) {
            throw "TargetRole '$targetRole' is ambiguous; provide targetMember."
        }
        if ($targets.Count -ne 1) { throw "Target member '$targetMember' is ambiguous for role '$targetRole'." }
        $memberCollisions = @($currentRoster.Bindings | Where-Object {
                $_.MemberName -ceq $memberName -and $_.BindingId -cne [string]$Registration.bindingId
            })
        if ($memberCollisions.Count -gt 0) {
            throw "Connector Member Name '$memberName' is already registered."
        }
        if ($memberName -ceq $targets[0].MemberName) {
            throw 'Connector Member Name must differ from the targeted internal member.'
        }
        $bindingTarget = "role:$targetRole" + $(if ($targetMember) { "/$targetMember" })
        $newAddedRole = ''
    }
    else {
        if (-not $alignedRole) { throw 'Additive registration requires alignedRole.' }
        $existingAddMembers = @($currentRoster.Members | Where-Object { $_.Role -eq $targetRole })
        if ($existingAddMembers.Count -gt 0 -and $existingBinding.Count -eq 0) {
            throw "Additive targetRole '$targetRole' already exists in the Members table."
        }
        $additiveCollisions = @($currentRoster.Bindings | Where-Object {
                $_.BindingId -cne [string]$Registration.bindingId -and
                ($_.AddedRole -eq $targetRole -or $_.MemberName -ceq $memberName)
            })
        if ($additiveCollisions.Count -gt 0) {
            throw 'Additive connector role or Member Name is already registered.'
        }
        if (-not $Registration.Contains('deliverableRoot') -or
            -not $Registration.Contains('route')) {
            throw 'Additive registration requires deliverableRoot and route.'
        }
        $bindingTarget = "role:$targetRole/$memberName"
        $newAddedRole = $targetRole
    }

    $bindingRow = [ordered]@{
        'Binding ID' = [string]$Registration.bindingId
        'Connector ID' = [string]$manifest.connectorId
        'Manifest' = $manifestRelative
        'Endpoint Kind' = ([string]$manifest.endpointKind).ToLowerInvariant()
        'Role Mode' = [string]$Registration.roleMode
        'Target Kind' = 'role'
        'Target' = $bindingTarget
        'Member Name' = $memberName
        'Added Role' = $newAddedRole
        'Aligned Role' = $alignedRole
        'Default Execution' = [string]$Registration.defaultExecution
    }
    $expectedBindingMatches = $false
    if ($existingBinding.Count -eq 1) {
        $expected = @($bindingHeaders | ForEach-Object {
                $name = $_
                $property = switch ($name) {
                    'Binding ID' { 'BindingId' }
                    'Connector ID' { 'ConnectorId' }
                    'Manifest' { 'ManifestPath' }
                    'Endpoint Kind' { 'EndpointKind' }
                    'Role Mode' { 'RoleMode' }
                    'Target Kind' { 'TargetKind' }
                    'Target' { 'Target' }
                    'Member Name' { 'MemberName' }
                    'Added Role' { 'AddedRole' }
                    'Aligned Role' { 'AlignedRole' }
                    'Default Execution' { 'DefaultExecution' }
                }
                [string]$existingBinding[0].$property -ceq [string]$bindingRow[$name]
            })
        $expectedBindingMatches = @($expected | Where-Object { -not $_ }).Count -eq 0
        if (-not $expectedBindingMatches) {
            throw "Binding ID '$($Registration.bindingId)' already exists with different data; use the audited binding refresh path."
        }
    }

    $newBinding = [pscustomobject]@{
        BindingId = $bindingRow['Binding ID']
        ConnectorId = $bindingRow['Connector ID']
        ManifestPath = $bindingRow.Manifest
        EndpointKind = $bindingRow['Endpoint Kind']
        RoleMode = $bindingRow['Role Mode']
        TargetKind = $bindingRow['Target Kind']
        Target = $bindingRow.Target
        MemberName = $bindingRow['Member Name']
        AddedRole = $bindingRow['Added Role']
        AlignedRole = $bindingRow['Aligned Role']
        DefaultExecution = $bindingRow['Default Execution']
    }
    $finalBindings = [Collections.Generic.List[object]]::new()
    foreach ($binding in $currentRoster.Bindings) { $finalBindings.Add($binding) }
    if (-not $expectedBindingMatches) { $finalBindings.Add($newBinding) }

    $memberRow = $null
    $memberIdentityExists = $false
    $routeRow = $null
    $routeIdentityExists = $false
    if ($Registration.roleMode -eq 'add') {
        $selectionCue = if ($Registration.Contains('selectionCue') -and $Registration.selectionCue) {
            [string]$Registration.selectionCue
        }
        else { [string][char]0x2014 }
        $alternateAgents = if ($Registration.Contains('alternateAgents') -and $Registration.alternateAgents) {
            [string]$Registration.alternateAgents
        }
        else { [string][char]0x2014 }
        $invocation = if ($Registration.Contains('invocation') -and $Registration.invocation) {
            [string]$Registration.invocation
        }
        else { 'runSubagent / task' }
        $tier = if ($Registration.Contains('modelTier') -and $Registration.modelTier) {
            [string]$Registration.modelTier
        }
        else { 'default' }
        $connectorDeliverableRoot = Resolve-RegistrationDeliverable -Value ([string]$Registration.deliverableRoot) `
            -RelativeRoot $RelativeRoot -Repository $Repository
        $memberValues = [ordered]@{
            Role = $targetRole
            'Member Name' = $memberName
            'Agent Name (Primary)' = 'Squad Connector'
            'Alternate Agents' = $alternateAgents
            'Selection Cue' = $selectionCue
            Invocation = $invocation
            'Model Tier' = $tier
        }
        if ($routingMode -ne 'off') {
            $memberValues.Model = if ($Registration.Contains('model')) { [string]$Registration.model } else { '' }
        }
        $memberValues['Deliverable Root'] = $connectorDeliverableRoot
        $memberLine = '| ' + (($memberTable.header | ForEach-Object { $memberValues[$_] }) -join ' | ') + ' |'
        $sameMemberRows = [Collections.Generic.List[bool]]::new()
        for ($index = $memberTable.start + 2; $index -lt $memberTable.end; $index++) {
            $cells = @(ConvertFrom-RegistrationTableLine $team.lines[$index])
            if ($cells.Count -ne $memberTable.header.Count) {
                throw 'team.md contains a Members row with the wrong width.'
            }
            if ($cells[[array]::IndexOf($memberTable.header, 'Role')] -cne $targetRole -or
                $cells[[array]::IndexOf($memberTable.header, 'Member Name')] -cne $memberName) {
                continue
            }
            $exact = $true
            for ($column = 0; $column -lt $memberTable.header.Count; $column++) {
                if ($cells[$column] -cne [string]$memberValues[$memberTable.header[$column]]) {
                    $exact = $false
                }
            }
            $sameMemberRows.Add($exact)
        }
        if ($sameMemberRows.Count -gt 1) {
            throw "Connector member '$memberName' is duplicated for role '$targetRole'."
        }
        if ($sameMemberRows.Count -eq 1) {
            if (-not $sameMemberRows[0]) {
                throw "Connector member '$memberName' already exists with different confirmed values."
            }
            $memberIdentityExists = $true
        }
        $memberRow = $memberLine

        $routingHeaders = @('Pattern / Keyword', 'Role(s)', 'Autonomy Tier', 'Parallel-Eligible')
        $routingTable = Get-RegistrationTable -Lines $routing.lines -RequiredHeaders $routingHeaders -Required
        if (($routingTable.header -join "`n") -cne ($routingHeaders -join "`n")) {
            throw 'Connector registration requires canonical routing.md columns.'
        }
        $routeCells = @(
            [string]$Registration.route.pattern,
            $targetRole,
            [string]$Registration.route.autonomyTier,
            $(if ($Registration.route.parallelEligible) { 'yes' } else { 'no' })
        )
        $routeRow = '| ' + ($routeCells -join ' | ') + ' |'
        for ($index = $routingTable.start + 2; $index -lt $routingTable.end; $index++) {
            $cells = @(ConvertFrom-RegistrationTableLine $routing.lines[$index])
            if ($cells.Count -ne $routingHeaders.Count) {
                throw 'routing.md contains a row with the wrong width.'
            }
            if ($cells[0] -ceq $routeCells[0] -and $cells[1] -ceq $routeCells[1]) {
                $exact = $true
                for ($column = 2; $column -lt $routeCells.Count; $column++) {
                    if ($cells[$column] -cne $routeCells[$column]) { $exact = $false }
                }
                if (-not $exact) {
                    throw 'The additive connector route already exists with different confirmed values.'
                }
                $routeIdentityExists = $true
                break
            }
        }
    }

    if ($expectedBindingMatches) {
        if ($Registration.roleMode -eq 'add' -and
            (-not $memberIdentityExists -or -not $routeIdentityExists)) {
            throw "Binding '$($Registration.bindingId)' exists but its additive member or route is incomplete; use the audited refresh path."
        }
        $alreadyRegistered = [ordered]@{
            status = 'unchanged'
            bindingId = $Registration.bindingId
            connectorId = $manifest.connectorId
            roleMode = $Registration.roleMode
            stateWritten = $false
            aiCost = 'none'
        }
        return $alreadyRegistered
    }
    if ($Registration.roleMode -eq 'add' -and $memberIdentityExists) {
        throw "Connector member '$memberName' already exists without a matching binding."
    }

    $finalMemberRows = [Collections.Generic.List[object]]::new()
    foreach ($member in $currentRoster.Members) { $finalMemberRows.Add($member) }
    if ($Registration.roleMode -eq 'add') {
        $finalMemberRows.Add([pscustomobject]@{
                Role = $targetRole
                MemberName = $memberName
                Agent = 'Squad Connector'
                Tier = $(if ($memberValues.Contains('Model Tier')) { $memberValues['Model Tier'] } else { 'default' })
                DeliverableRoot = $memberValues['Deliverable Root']
            })
    }

    $validationMembers = @($finalMemberRows)
    $validationBindings = @(
        foreach ($binding in $finalBindings) {
            $copy = [ordered]@{}
            foreach ($property in $binding.PSObject.Properties) { $copy[$property.Name] = $property.Value }
            $path = [string]$copy.ManifestPath
            if ($path -and -not [IO.Path]::IsPathRooted($path)) {
                $copy.ManifestPath = [IO.Path]::GetFullPath(
                    (Resolve-SquadRepositoryPath -RepoRoot $Repository -Path $path -AllowMissing),
                    $Repository
                )
            }
            [pscustomobject]$copy
        }
    )
    $bindingValidation = Test-ApplicableBindingsLocal -Bindings $validationBindings `
        -Members $validationMembers -TeamPath $teamPath
    if ($bindingValidation.Status -ne 'ok') {
        throw "Binding validation failed: $($bindingValidation.Issues -join ', ')"
    }

    $seenBindingIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $seenConnectorMembers = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($binding in $finalBindings) {
        if ($binding.BindingId -and -not $seenBindingIds.Add([string]$binding.BindingId)) {
            throw "Connector Binding ID '$($binding.BindingId)' is duplicated."
        }
        if ($binding.MemberName -and -not $seenConnectorMembers.Add([string]$binding.MemberName)) {
            throw "Connector Member Name '$($binding.MemberName)' is reused by multiple bindings."
        }
    }
    if ($alignedRole) {
        $classMap = Get-SquadRoleClassMap
        $classSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $null = Resolve-RegistrationAlignedClass -Role $alignedRole -Bindings @($finalBindings) `
            -ClassMap $classMap -Seen $classSeen
    }

    $roleMemberRows = @($validationMembers | Where-Object { $_.Role -eq $targetRole })
    $defaultCounts = @(
        foreach ($member in $roleMemberRows) {
            $applicable = @(Get-ApplicableBindingsForMemberRowLocal -Row $member -Bindings @($finalBindings))
            [pscustomobject]@{
                MemberName = $member.MemberName
                Defaults = @($applicable | Where-Object {
                        $_.DefaultExecution -and $_.DefaultExecution -ne 'ask'
                    })
            }
        }
    )
    foreach ($selection in $defaultCounts) {
        if (@($selection.Defaults).Count -gt 1) {
            throw "Connector defaults are ambiguous for '$targetRole/$($selection.MemberName)'; use ask for alternatives or refresh the existing default."
        }
    }

    $teamOutput = Get-RegistrationDocument $teamPath
    $routingOutput = Get-RegistrationDocument $routingPath
    $outputMemberTable = Get-RegistrationTable -Lines $teamOutput.lines -RequiredHeaders $memberHeaders -Required
    if ($Registration.roleMode -eq 'add') {
        $teamOutput.lines.Insert($outputMemberTable.end, $memberRow)
    }
    $outputBindingTable = Get-RegistrationTable -Lines $teamOutput.lines -RequiredHeaders $bindingHeaders
    if ($null -eq $outputBindingTable) {
        if ($teamOutput.lines.Count -and $teamOutput.lines[-1] -ne '') { $teamOutput.lines.Add('') }
        $teamOutput.lines.Add('## Connector Bindings')
        $teamOutput.lines.Add('')
        $teamOutput.lines.Add('| ' + ($bindingHeaders -join ' | ') + ' |')
        $teamOutput.lines.Add('| ' + (($bindingHeaders | ForEach-Object { '---' }) -join ' | ') + ' |')
    }
    $outputBindingTable = Get-RegistrationTable -Lines $teamOutput.lines -RequiredHeaders $bindingHeaders -Required
    $bindingLine = '| ' + (($bindingHeaders | ForEach-Object { $bindingRow[$_] }) -join ' | ') + ' |'
    $teamOutput.lines.Insert($outputBindingTable.end, $bindingLine)
    if ($Registration.roleMode -eq 'add' -and -not $routeIdentityExists) {
        $outputRoutingTable = Get-RegistrationTable -Lines $routingOutput.lines -RequiredHeaders @(
            'Pattern / Keyword', 'Role(s)', 'Autonomy Tier', 'Parallel-Eligible'
        ) -Required
        $routingOutput.lines.Insert($outputRoutingTable.end, $routeRow)
    }

    $teamBytes = [byte[]](ConvertTo-RegistrationDocumentByteArray $teamOutput)
    $routingBytes = [byte[]](ConvertTo-RegistrationDocumentByteArray $routingOutput)
    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    $confirmation = if ($Registration.Contains('confirmationRef') -and $Registration.confirmationRef) {
        [string]$Registration.confirmationRef
    }
    elseif ($Confirmed) { "cli:$($Registration.runId)" }
    else { '(supplied at -Confirmed apply)' }
    $decision = [Collections.Generic.List[string]]::new()
    $decision.Add("## Connector Registration $timestamp $($Registration.bindingId)")
    $decision.Add('')
    $decision.Add("* Run ID: $($Registration.runId)")
    $decision.Add("* Binding ID: $($Registration.bindingId)")
    $decision.Add("* Connector ID: $($manifest.connectorId)")
    $decision.Add("* Manifest: $manifestRelative")
    $decision.Add("* Role mode: $($Registration.roleMode)")
    $decision.Add("* Target: $bindingTarget")
    $decision.Add("* Member Name: $memberName")
    $decision.Add("* Default execution: $($Registration.defaultExecution)")
    $decision.Add("* Confirmation: $confirmation")
    $decision.Add('* Source: Register-SquadConnector.ps1; deterministic local registration; AI cost none')
    if ($Registration.Contains('rationale') -and $Registration.rationale) {
        $decision.Add("* Rationale: $($Registration.rationale)")
    }
    $decisionsBytes = [byte[]](Add-RegistrationDecision `
            -Before ([IO.File]::ReadAllBytes((Join-Path $Root 'decisions.md'))) `
            -Entry ($decision -join "`n"))

    [ordered]@{
        status = 'planned'
        bindingId = $Registration.bindingId
        connectorId = $manifest.connectorId
        roleMode = $Registration.roleMode
        target = $bindingTarget
        memberName = $memberName
        defaultExecution = $Registration.defaultExecution
        manifestPath = $manifestRelative
        endpointKind = $manifest.endpointKind
        addedRole = $newAddedRole
        alignedRole = $alignedRole
        deliverableRoot = if ($Registration.roleMode -eq 'add') {
            $memberValues['Deliverable Root']
        }
        else { $targets[0].DeliverableRoot }
        memberAdded = ($Registration.roleMode -eq 'add')
        routeAdded = ($Registration.roleMode -eq 'add' -and -not $routeIdentityExists)
        binding = $bindingRow
        member = if ($Registration.roleMode -eq 'add') { $memberValues } else { $null }
        route = if ($Registration.roleMode -eq 'add') {
            [ordered]@{
                pattern = $Registration.route.pattern
                role = $targetRole
                autonomyTier = $Registration.route.autonomyTier
                parallelEligible = [bool]$Registration.route.parallelEligible
            }
        }
        else { $null }
        manifestFullPath = $manifestPath
        manifestSha256 = Get-RegistrationHash $manifestBytes
        team = $teamBytes
        routing = $routingBytes
        decisions = $decisionsBytes
        aiCost = 'none'
        stateWritten = $false
    }
}

function Restore-RegistrationOutput {
    $failures = [Collections.Generic.List[string]]::new()
    foreach ($name in @('routing.md', 'team.md', 'decisions.md')) {
        if (-not $script:originals.Contains($name)) { continue }
        $path = Join-Path $script:root $name
        try {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $current = [IO.File]::ReadAllBytes($path)
                if ((Get-RegistrationHash $current) -ceq (Get-RegistrationHash $script:originals[$name])) {
                    continue
                }
                if (-not $script:planned.Contains($name) -or
                    (Get-RegistrationHash $current) -cne (Get-RegistrationHash $script:planned[$name])) {
                    $failures.Add("$name changed after this transaction wrote it")
                    continue
                }
            }
            Write-RegistrationAtomicFile -Path $path -Bytes $script:originals[$name]
        }
        catch {
            $failures.Add("${name}: $($_.Exception.Message)")
        }
    }
    if ($failures.Count) { throw "Connector registration rollback incomplete: $($failures -join '; ')" }
}

try {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $registration = Get-RegistrationInput
    $selectedSquadRoot = if ($registration.Contains('squadRoot') -and $registration.squadRoot) {
        if ($script:registrationBoundParameters.ContainsKey('SquadRoot') -and
            $registration.squadRoot -cne $SquadRoot) {
            throw 'SquadRoot disagrees with squadRoot in registration input.'
        }
        [string]$registration.squadRoot
    }
    else { $SquadRoot }
    $script:root = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $selectedSquadRoot
    $relativeRoot = [IO.Path]::GetRelativePath($RepoRoot, $script:root) -replace '\\', '/'
    if ($relativeRoot -notmatch '^\.copilot-tracking/squad(?:/members/[a-z0-9][a-z0-9-]*)?$') {
        throw 'SquadRoot must be one plain squad root or one federation member root.'
    }
    if (Test-Path -LiteralPath (Join-Path $script:root 'federation.md') -PathType Leaf) {
        throw 'Connector bindings register on a plain squad or federation member, not a federation root.'
    }

    if (-not $Confirmed) {
        $baseline = Get-RegistrationBaseline -Root $script:root -Repository $RepoRoot -RelativeRoot $relativeRoot
        $projection = Get-RegistrationProjection -Registration $registration -Repository $RepoRoot `
            -Root $script:root -RelativeRoot $relativeRoot
        if ($projection.status -eq 'unchanged') {
            $projection | ConvertTo-Json -Depth 10 -Compress
            exit 0
        }
        $ledger = Invoke-SquadLocalScript -Name 'Measure-SquadLedger.ps1' `
            -Arguments @('-SquadRoot', $script:root, '-Check')
        $ledgerText = ((@($ledger.stdout, $ledger.stderr) | Where-Object { $_ }) -join "`n").Trim()
        if ($ledger.exitCode -ne 0 -or $ledgerText -notmatch 'Measure-SquadLedger -Check: PASS') {
            throw "Read-only ledger check failed before preview: $ledgerText"
        }
        Assert-RegistrationBaseline -Expected $baseline -Root $script:root `
            -Repository $RepoRoot -RelativeRoot $relativeRoot
        [ordered]@{
            status = 'planned'
            bindingId = $projection.bindingId
            connectorId = $projection.connectorId
            endpointKind = $projection.endpointKind
            roleMode = $projection.roleMode
            target = $projection.target
            memberName = $projection.memberName
            defaultExecution = $projection.defaultExecution
            manifestPath = $projection.manifestPath
            addedRole = $projection.addedRole
            alignedRole = $projection.alignedRole
            deliverableRoot = $projection.deliverableRoot
            memberAdded = $projection.memberAdded
            routeAdded = $projection.routeAdded
            binding = $projection.binding
            member = $projection.member
            route = $projection.route
            teamSha256 = Get-RegistrationHash $projection.team
            routingSha256 = Get-RegistrationHash $projection.routing
            decisionsSha256 = Get-RegistrationHash $projection.decisions
            aiCost = 'none'
            confirmationRequired = $true
            stateWritten = $false
        } | ConvertTo-Json -Depth 10 -Compress
        exit 0
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($LockTimeoutSeconds)
    $lockRoots = [Collections.Generic.List[string]]::new()
    if ($relativeRoot -match '^\.copilot-tracking/squad/members/') {
        $lockRoots.Add((Join-Path -Path $RepoRoot -ChildPath '.copilot-tracking' -AdditionalChildPath 'squad'))
    }
    $lockRoots.Add($script:root)
    foreach ($lockRoot in $lockRoots) {
        $script:locks.Add((Enter-RegistrationWriterLock -Path $lockRoot -Deadline $deadline))
    }

    $baseline = Get-RegistrationBaseline -Root $script:root -Repository $RepoRoot -RelativeRoot $relativeRoot
    $projection = Get-RegistrationProjection -Registration $registration -Repository $RepoRoot `
        -Root $script:root -RelativeRoot $relativeRoot
    if ($projection.status -eq 'unchanged') {
        $projection | ConvertTo-Json -Depth 10 -Compress
        exit 0
    }
    $ledger = Invoke-SquadLocalScript -Name 'Measure-SquadLedger.ps1' `
        -Arguments @('-SquadRoot', $script:root, '-Check')
    $ledgerText = ((@($ledger.stdout, $ledger.stderr) | Where-Object { $_ }) -join "`n").Trim()
    if ($ledger.exitCode -ne 0 -or $ledgerText -notmatch 'Measure-SquadLedger -Check: PASS') {
        throw "Read-only ledger check failed before registration: $ledgerText"
    }
    $manifestHash = (Get-FileHash -LiteralPath $projection.manifestFullPath -Algorithm SHA256).Hash
    if ($manifestHash -cne $projection.manifestSha256) {
        throw 'Connector manifest changed while registration was being prepared.'
    }
    Assert-RegistrationBaseline -Expected $baseline -Root $script:root `
        -Repository $RepoRoot -RelativeRoot $relativeRoot

    foreach ($name in @('team.md', 'routing.md', 'decisions.md')) {
        $script:originals[$name] = [IO.File]::ReadAllBytes((Join-Path $script:root $name))
    }
    $script:planned['team.md'] = $projection.team
    $script:planned['routing.md'] = $projection.routing
    $script:planned['decisions.md'] = $projection.decisions
    try {
        Write-RegistrationAtomicFile -Path (Join-Path $script:root 'decisions.md') `
            -Bytes $projection.decisions
        $script:wrote = $true
        Write-RegistrationAtomicFile -Path (Join-Path $script:root 'team.md') `
            -Bytes $projection.team
        Write-RegistrationAtomicFile -Path (Join-Path $script:root 'routing.md') `
            -Bytes $projection.routing
        foreach ($name in @('team.md', 'routing.md', 'decisions.md')) {
            $actual = [IO.File]::ReadAllBytes((Join-Path $script:root $name))
            if ((Get-RegistrationHash $actual) -cne (Get-RegistrationHash $script:planned[$name])) {
                throw "Connector registration read-back failed for $name."
            }
        }
        Assert-RegistrationBaseline -Expected $baseline -Root $script:root `
            -Repository $RepoRoot -RelativeRoot $relativeRoot `
            -IgnoreFiles @('team.md', 'routing.md', 'decisions.md')
        $finalHash = (Get-FileHash -LiteralPath $projection.manifestFullPath -Algorithm SHA256).Hash
        if ($finalHash -cne $projection.manifestSha256) {
            throw 'Connector manifest changed after registration validation.'
        }
        $after = Invoke-SquadLocalScript -Name 'Measure-SquadLedger.ps1' `
            -Arguments @('-SquadRoot', $script:root, '-Check')
        $afterText = ((@($after.stdout, $after.stderr) | Where-Object { $_ }) -join "`n").Trim()
        if ($after.exitCode -ne 0 -or $afterText -notmatch 'Measure-SquadLedger -Check: PASS') {
            throw "Read-only ledger check failed after registration: $afterText"
        }
        $roster = Get-SquadConnectorRosterState -TeamPath (Join-Path $script:root 'team.md')
        $match = @($roster.Bindings | Where-Object { $_.BindingId -ceq $projection.bindingId })
        if ($match.Count -ne 1) { throw 'Registered binding read-back failed.' }
    }
    catch {
        $detail = $_.Exception.Message
        if ($script:wrote) {
            try {
                Restore-RegistrationOutput
                $detail += ' Original squad files restored.'
            }
            catch {
                $detail += " Rollback failed: $($_.Exception.Message)"
            }
        }
        throw $detail
    }

    [ordered]@{
        status = 'written'
        bindingId = $projection.bindingId
        connectorId = $projection.connectorId
        endpointKind = $projection.endpointKind
        roleMode = $projection.roleMode
        target = $projection.target
        memberName = $projection.memberName
        defaultExecution = $projection.defaultExecution
        manifestPath = $projection.manifestPath
        addedRole = $projection.addedRole
        alignedRole = $projection.alignedRole
        deliverableRoot = $projection.deliverableRoot
        memberAdded = $projection.memberAdded
        routeAdded = $projection.routeAdded
        binding = $projection.binding
        member = $projection.member
        route = $projection.route
        accountingPreserved = $true
        historyPreserved = $true
        aiCost = 'none'
        stateWritten = $true
    } | ConvertTo-Json -Depth 10 -Compress
    exit 0
}
catch {
    [Console]::Error.WriteLine("Register-SquadConnector: $($_.Exception.Message)")
    exit 1
}
finally {
    foreach ($lock in $script:locks) {
        if ($null -ne $lock) { $lock.Dispose() }
    }
}
