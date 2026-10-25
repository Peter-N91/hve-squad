#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Initializes or expands a federation from one confirmed payload without model dispatch.
.DESCRIPTION
    AI cost: none. The payload comes from `Get-SquadFederationInitPlan.ps1`.
    Every new member is initialized in parallel through the existing direct
    `Initialize-Squad.ps1` transaction inside an isolated repository-shaped stage.
    After every member passes its ledger check, this helper deterministically seeds a
    fresh federation or additively registers the members into an existing federation
    under the ordinary squad writer lock.

    Fresh Init publishes one complete staged tree. Expansion stages only the new member
    roots and a validated projection of root metadata; it never replaces or rewrites
    an existing member. Stale payloads, changed preconditions, member failures, lock
    timeouts, collisions, or validation failures publish nothing. Owned root files and
    member moves are rolled back when safe.

    Exit 0 returns one verified JSON receipt. Exit 1 rejects input or a stale
    precondition; 3 reports a publish/cleanup failure; 5 is a member collision;
    8 is a writer-lock timeout.
.PARAMETER ExpectedPayloadSha256
    Exact digest returned by `Get-SquadFederationInitPlan.ps1`.
.PARAMETER Confirmed
    Required after the user approves the complete proposed federation. Authorized
    unattended bootstrap passes it only after its trigger gates.
.EXAMPLE
    ./Initialize-SquadFederation.ps1 -RepoRoot . -PayloadPath $payload `
      -ExpectedPayloadSha256 $sha -Confirmed
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PayloadPath,
    [Parameter(Mandatory)][string]$ExpectedPayloadSha256,
    [string]$RepoRoot = (Get-Location).ProviderPath,
    [switch]$Confirmed,
    [ValidateRange(1, 3600)][int]$LockTimeoutSeconds = 120,
    [ValidateRange(10, 1800)][int]$MemberTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SquadCoordinator.psm1') -Force

$lock = $null
$operation = $null
$stageContainer = $null
$stageRepo = $null
$stageSquad = $null
$backupRoot = $null
$published = $false
$committed = $false
$trackingCreated = $false
$finalSnapshot = $null
$exitCode = 1
$preserveTransaction = $false
$running = [Collections.Generic.List[object]]::new()
$originalFiles = [ordered]@{}
$ownedFiles = @{}
$movedMembers = [Collections.Generic.List[object]]::new()
$stopwatch = [Diagnostics.Stopwatch]::StartNew()

function Assert-FieldSet {
    param($Object, [string[]]$Required, [string[]]$Optional = @())
    if ($Object -isnot [Collections.IDictionary]) { throw 'Expected a JSON object.' }
    foreach ($field in $Required) {
        if (-not $Object.Contains($field)) { throw "Missing field: $field" }
    }
    foreach ($field in $Object.Keys) {
        if ($field -notin ($Required + $Optional)) { throw "Unsupported field: $field" }
    }
}

function Assert-Line {
    param($Value, [switch]$AllowEmpty)
    if ($Value -isnot [string] -or $Value -match '[\r\n|\x00-\x1f]' -or
        (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value))) {
        throw 'Expected a single-line value without table delimiters or control characters.'
    }
}

function Get-Hash {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Get-TreeSnapshot {
    param([Parameter(Mandatory)][string]$Root)
    $lines = [Collections.Generic.List[string]]::new()
    $paths = [string[]]@(Get-ChildItem -LiteralPath $Root -Recurse -Force | ForEach-Object FullName)
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    foreach ($path in $paths) {
        $item = Get-Item -LiteralPath $path -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked staged path refused: $path" }
        $relative = [IO.Path]::GetRelativePath($Root, $path) -replace '\\', '/'
        if ($relative -match '[\r\n\t\x00]') { throw 'Staged path contains a control character.' }
        if ($item.PSIsContainer) { $lines.Add("D`t$relative") }
        else { $lines.Add("F`t$relative`t$($item.Length)`t$((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash)") }
    }
    Get-Hash ([Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n")))
}

function Get-MemberDirectoryName {
    param([Parameter(Mandatory)][string]$Root)
    $members = Join-Path $Root 'members'
    if (-not (Test-Path -LiteralPath $members -PathType Container)) { return @() }
    @(
        Get-ChildItem -LiteralPath $members -Directory -Force | Sort-Object Name | ForEach-Object {
            if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Linked federation member directory refused: $($_.FullName)"
            }
            $_.Name
        }
    )
}

function Assert-FederationBaseline {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Repository
    )
    Assert-FieldSet $Expected @('kind', 'snapshot', 'memberDirectories')
    if ($Expected.kind -cne 'federation' -or $Expected.snapshot -isnot [Collections.IDictionary] -or
        $Expected.memberDirectories -isnot [array]) {
        throw 'Unsupported federation expansion baseline.'
    }
    $actual = Get-SquadFederationSnapshot -SquadRoot $Path -RepoRoot $Repository
    if (($Expected.snapshot | ConvertTo-Json -Depth 20 -Compress) -cne
        ($actual | ConvertTo-Json -Depth 20 -Compress)) {
        throw 'Federation changed after confirmation.'
    }
    $directories = @(Get-MemberDirectoryName -Root $Path)
    if (($Expected.memberDirectories -join "`n") -cne ($directories -join "`n")) {
        throw 'Federation member directories changed after confirmation.'
    }
}

function Copy-ExpansionProjection {
    param(
        [Parameter(Mandatory)][string]$LiveRoot,
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)]$Baseline
    )
    foreach ($file in Get-ChildItem -LiteralPath $LiveRoot -File -Force) {
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked federation root file refused: $($file.FullName)" }
        [IO.File]::Copy($file.FullName, (Join-Path $StageRoot $file.Name), $true)
    }
    $liveHistory = Join-Path $LiveRoot 'history'
    $stageHistory = Join-Path $StageRoot 'history'
    $null = [IO.Directory]::CreateDirectory($stageHistory)
    foreach ($file in Get-ChildItem -LiteralPath $liveHistory -File -Force) {
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked federation history file refused: $($file.FullName)" }
        [IO.File]::Copy($file.FullName, (Join-Path $stageHistory $file.Name), $true)
    }
    foreach ($name in $Baseline.snapshot.members.Keys) {
        $member = Join-Path $StageRoot 'members' $name
        $null = [IO.Directory]::CreateDirectory($member)
        [IO.File]::Copy((Join-Path $LiveRoot 'members' $name 'state.json'), (Join-Path $member 'state.json'), $true)
    }
}

function Add-EntryContent {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Header,
        [Parameter(Mandatory)][string]$Entry
    )
    $before = if (Test-Path -LiteralPath $Path) { ,([IO.File]::ReadAllBytes($Path)) } else { ,([byte[]]::new(0)) }
    $newline = if ([Text.Encoding]::UTF8.GetString($before).Contains("`r`n")) { "`r`n" } else { "`n" }
    $tail = if ($before.Length) {
        $(if ($before[-1] -ne 10) { $newline }) + $newline + ($Entry -replace "`r?`n", $newline) + $newline
    }
    else {
        ($Header + "`n`n" + $Entry + "`n") -replace "`r?`n", $newline
    }
    $stream = [IO.MemoryStream]::new()
    try {
        $stream.Write($before)
        $stream.Write([Text.UTF8Encoding]::new($false).GetBytes($tail))
        ,$stream.ToArray()
    }
    finally { $stream.Dispose() }
}

function Add-TableRow {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Rows)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $match = [regex]::Match($text, '(?s)\A(?<body>.*\|[ \t]*)(?<tail>\r?\n(?:[ \t]*\r?\n)*[ \t]*)?\z')
    if (-not $match.Success) { throw "Federation table must end with its final row: $Path" }
    $lastLine = ($match.Groups['body'].Value -split '\r?\n')[-1]
    if ($lastLine -notmatch '^\s*\|.*\|\s*$') { throw "Federation table has an invalid final row: $Path" }
    $tail = if ($match.Groups['tail'].Success) { $match.Groups['tail'].Value } else { $newline }
    $updated = $match.Groups['body'].Value + $newline + (($Rows -join $newline) -replace "`r?`n", $newline) + $tail
    [IO.File]::WriteAllText($Path, $updated, [Text.UTF8Encoding]::new($false))
}

function Write-Atomic {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$Bytes)
    if (-not $script:originalFiles.Contains($Path)) {
        if (Test-Path -LiteralPath $Path) { $script:originalFiles.Add($Path, [IO.File]::ReadAllBytes($Path)) }
        else { $script:originalFiles.Add($Path, $null) }
    }
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        [IO.File]::Move($temporary, $Path, $true)
        $script:ownedFiles[$Path] = Get-Hash $Bytes
        if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $script:ownedFiles[$Path]) {
            throw 'Write read-back mismatch.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) }
    }
}

function Restore-Expansion {
    $failures = [Collections.Generic.List[string]]::new()
    $paths = @($script:originalFiles.Keys)
    [Array]::Reverse($paths)
    foreach ($path in $paths) {
        try {
            if (-not $script:ownedFiles.ContainsKey($path)) {
                if ($null -eq $script:originalFiles[$path] -and -not (Test-Path -LiteralPath $path)) { continue }
                if ($null -ne $script:originalFiles[$path] -and (Test-Path -LiteralPath $path) -and
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ceq (Get-Hash $script:originalFiles[$path])) {
                    continue
                }
                $failures.Add("root file: $path")
                continue
            }
            if (-not (Test-Path -LiteralPath $path) -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $script:ownedFiles[$path]) {
                $failures.Add("root file: $path")
                continue
            }
            if ($null -eq $script:originalFiles[$path]) { [IO.File]::Delete($path) }
            else { [IO.File]::WriteAllBytes($path, $script:originalFiles[$path]) }
        }
        catch { $failures.Add("root file '$path': $($_.Exception.Message)") }
    }
    if (-not $failures.Count) {
        $moves = @($script:movedMembers)
        [Array]::Reverse($moves)
        foreach ($move in $moves) {
            try {
                if (-not (Test-Path -LiteralPath $move.live) -or (Get-TreeSnapshot $move.live) -cne $move.digest -or
                    (Test-Path -LiteralPath $move.stage)) {
                    $failures.Add("member: $($move.name)")
                    continue
                }
                [IO.Directory]::Move($move.live, $move.stage)
            }
            catch { $failures.Add("member '$($move.name)': $($_.Exception.Message)") }
        }
    }
    $failures.ToArray()
}

function Get-RootBaseline {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [ordered]@{ kind = 'absent'; directories = @() } }
    $root = Get-Item -LiteralPath $Path -Force
    if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Fresh federation root must be absent or an unlinked empty directory tree.'
    }
    $directories = [Collections.Generic.List[string]]::new()
    foreach ($item in Get-ChildItem -LiteralPath $Path -Recurse -Force | Sort-Object FullName) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked empty-root path refused: $($item.FullName)" }
        if (-not $item.PSIsContainer) { throw 'Fresh federation root is no longer empty.' }
        $directories.Add(([IO.Path]::GetRelativePath($Path, $item.FullName) -replace '\\', '/'))
    }
    [ordered]@{ kind = 'empty'; directories = $directories.ToArray() }
}

function Assert-RootBaseline {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)][string]$Path
    )
    Assert-FieldSet $Expected @('kind', 'directories')
    if ($Expected.kind -notin @('absent', 'empty') -or $Expected.directories -isnot [array]) {
        throw 'Unsupported federation root baseline.'
    }
    try { $actual = Get-RootBaseline $Path }
    catch { throw 'Federation root changed after confirmation.' }
    if ($Expected.kind -cne $actual.kind -or
        (@($Expected.directories) -join "`n") -cne (@($actual.directories) -join "`n")) {
        throw 'Federation root changed after confirmation.'
    }
}

function Write-Text {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-DecisionRef {
    param(
        [Parameter(Mandatory)][string]$StageRepository,
        [Parameter(Mandatory)][string]$MemberRoot
    )
    $path = Join-Path $MemberRoot 'decisions.md'
    $headingMatches = [regex]::Matches([IO.File]::ReadAllText($path), '(?m)^## (?<title>[^\r\n]+)$')
    if (-not $headingMatches.Count) { throw "Member decisions have no heading: $path" }
    $title = $headingMatches[-1].Groups['title'].Value
    $anchor = ($title.ToLowerInvariant() -replace '[^\p{L}\p{Nd}_ -]', '') -replace ' ', '-'
    ([IO.Path]::GetRelativePath($StageRepository, $path) -replace '\\', '/') + '#' + $anchor
}

function Get-MemberInitProcess {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$PayloadFile,
        [Parameter(Mandatory)][string]$StageRepository,
        [Parameter(Mandatory)][string]$AgentRepository
    )
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $PSHOME 'pwsh'
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @(
            '-NoProfile', '-File', (Join-Path $PSScriptRoot 'Initialize-Squad.ps1'),
            '-RepoRoot', $StageRepository,
            '-AgentRepoRoot', $AgentRepository,
            '-PayloadPath', $PayloadFile,
            '-Direct'
        )) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $null = $process.Start()
    [pscustomobject]@{
        name = $Name
        process = $process
        startedAt = $process.StartTime.ToUniversalTime()
        stdout = $process.StandardOutput.ReadToEndAsync()
        stderr = $process.StandardError.ReadToEndAsync()
    }
}

function Get-OrchestrationPrice {
    param(
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)][string]$FirstMemberRoot,
        [Parameter(Mandatory)][string]$Entry,
        [Parameter(Mandatory)]$Block,
        [Parameter(Mandatory)][string]$ScratchRoot
    )
    $null = [IO.Directory]::CreateDirectory((Join-Path $ScratchRoot 'history'))
    Write-Text (Join-Path $ScratchRoot 'history' 'Squad Scribe.md') "# History: Squad Scribe`n`n$Entry`n"
    [IO.File]::Copy((Join-Path $FirstMemberRoot 'team.md'), (Join-Path $ScratchRoot 'team.md'))
    [IO.File]::Copy((Join-Path $StageRoot 'consumption-rates.md'), (Join-Path $ScratchRoot 'consumption-rates.md'))
    [IO.File]::Copy((Join-Path $FirstMemberRoot 'state.json'), (Join-Path $ScratchRoot 'state.json'))
    $price = Invoke-SquadLocalScript -Name 'Measure-SquadLedger.ps1' -Arguments @('-SquadRoot', $ScratchRoot, '-Format', 'json')
    if ($price.exitCode -ne 0) { throw "Federation Init orchestration pricing failed: $($price.stderr.Trim())" }
    $result = $price.stdout | ConvertFrom-Json -AsHashtable
    if ($result.total.turns -ne $Block.internal_turns -or @($result.attribution).Count -ne 1 -or
        $result.attribution[0].role -ne 'orchestration') {
        throw 'Federation Init orchestration accounting did not reconcile.'
    }
    $result
}

function Restore-Root {
    param(
        [Parameter(Mandatory)][string]$LiveRoot,
        [Parameter(Mandatory)][string]$StageRoot
    )
    $failures = [Collections.Generic.List[string]]::new()
    try {
        if ($script:published -and (Test-Path -LiteralPath $LiveRoot) -and $script:finalSnapshot) {
            if ((Get-TreeSnapshot $LiveRoot) -cne $script:finalSnapshot) {
                $failures.Add('published federation changed before rollback')
            }
            elseif (Test-Path -LiteralPath $StageRoot) {
                $failures.Add('stage collision during rollback')
            }
            else {
                [IO.Directory]::Move($LiveRoot, $StageRoot)
                $script:published = $false
            }
        }
    }
    catch { $failures.Add("published root: $($_.Exception.Message)") }
    try {
        if ($script:backupRoot -and (Test-Path -LiteralPath $script:backupRoot) -and -not (Test-Path -LiteralPath $LiveRoot)) {
            [IO.Directory]::Move($script:backupRoot, $LiveRoot)
            $script:backupRoot = $null
        }
    }
    catch { $failures.Add("empty scaffold: $($_.Exception.Message)") }
    $failures.ToArray()
}

try {
    if (-not $Confirmed) { throw 'Federation Init requires explicit confirmation.' }
    if ($ExpectedPayloadSha256 -cnotmatch '^[A-Fa-f0-9]{64}$') { throw 'ExpectedPayloadSha256 must be a SHA-256 digest.' }
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $payloadFile = (Resolve-Path -LiteralPath $PayloadPath).ProviderPath
    if ([IO.Path]::GetExtension($payloadFile) -cne '.json' -or
        (Get-FileHash -LiteralPath $payloadFile -Algorithm SHA256).Hash -cne $ExpectedPayloadSha256.ToUpperInvariant()) {
        throw 'Federation Init payload hash mismatch.'
    }
    $payload = Get-Content -LiteralPath $payloadFile -Raw | ConvertFrom-Json -AsHashtable
    Assert-FieldSet $payload @(
        'schemaVersion', 'operation', 'runId', 'rootBaseline', 'notify', 'sessionModel',
        'modelOverrides', 'members', 'generatedAt'
    ) @('orchestration')
    if ($payload.schemaVersion -ne 2 -or $payload.operation -notin @('fresh', 'expand') -or
        $payload.members -isnot [array] -or
        $payload.members.Count -lt 1 -or $payload.members.Count -gt 16) {
        throw 'Unsupported federation Init payload.'
    }
    $operation = $payload.operation
    Assert-Line $payload.runId
    Assert-Line ([string]$payload.sessionModel) -AllowEmpty
    if ($payload.modelOverrides -isnot [Collections.IDictionary]) { throw 'modelOverrides must be an object.' }
    foreach ($value in $payload.modelOverrides.Values) { Assert-Line $value }
    if ($payload.generatedAt -is [DateTime]) { $payload.generatedAt = $payload.generatedAt.ToString('o') }
    Assert-Line $payload.generatedAt
    Assert-FieldSet $payload.notify @('approvalChannel', 'enabled') @('email', 'github')
    if ($payload.notify.enabled -isnot [bool] -or $payload.notify.approvalChannel -notin @('in-chat', 'github-issue', 'webhook')) {
        throw 'Invalid federation notification configuration.'
    }
    if ($payload.notify.Contains('email')) { Assert-Line $payload.notify.email -AllowEmpty }
    if ($payload.notify.Contains('github')) {
        Assert-FieldSet $payload.notify.github @('handle', 'repo')
        foreach ($value in $payload.notify.github.Values) { Assert-Line $value -AllowEmpty }
    }
    if ($payload.notify.enabled -and $payload.notify.approvalChannel -eq 'github-issue' -and
        (-not $payload.notify.Contains('github') -or -not $payload.notify.github.handle -or -not $payload.notify.github.repo)) {
        throw 'Enabled github-issue notifications require handle and repo.'
    }

    $root = [IO.Path]::GetFullPath((Join-Path $RepoRoot '.copilot-tracking' 'squad'))
    $trackingRoot = Split-Path -Parent $root
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $routeSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($operation -eq 'fresh') {
        Assert-RootBaseline -Expected $payload.rootBaseline -Path $root
    }
    else {
        if (-not (Test-Path -LiteralPath (Join-Path $root 'history') -PathType Container)) {
            throw 'Existing federation is missing its root history directory.'
        }
        Assert-FederationBaseline -Expected $payload.rootBaseline -Path $root -Repository $RepoRoot
        foreach ($name in $payload.rootBaseline.snapshot.members.Keys) { $null = $seen.Add($name) }
        $routingTables = @(Read-SquadTables (Join-Path $root 'meta-routing.md') |
                Where-Object { 'Pattern / Domain' -in $_.Header -and 'Sub-squad' -in $_.Header -and 'Parallel-Eligible' -in $_.Header })
        if ($routingTables.Count -ne 1) { throw 'Existing federation has no unique meta-routing table.' }
        foreach ($route in $routingTables[0].Rows) {
            if (-not $routeSeen.Add($route['Pattern / Domain'])) { throw 'Existing federation contains duplicate meta-routes.' }
        }
    }
    foreach ($member in $payload.members) {
        Assert-FieldSet $member @('name', 'profile', 'owner', 'description', 'routes', 'initPayload')
        Assert-Line $member.name
        Assert-Line $member.profile
        Assert-Line $member.owner -AllowEmpty
        Assert-Line $member.description
        if ($member.name -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or -not $seen.Add($member.name) -or
            $member.routes -isnot [array] -or -not $member.routes.Count) {
            throw 'Invalid or duplicate federation member.'
        }
        foreach ($route in $member.routes) {
            Assert-FieldSet $route @('pattern', 'parallelEligible')
            Assert-Line $route.pattern
            if ($route.parallelEligible -isnot [bool] -or -not $routeSeen.Add($route.pattern)) {
                throw 'parallelEligible must be boolean and every meta-route must be unique.'
            }
        }
        if ($member.initPayload -isnot [Collections.IDictionary] -or
            $member.initPayload.squadRoot -cne ".copilot-tracking/squad/members/$($member.name)") {
            throw 'Member Init payload is not bound to its federation root.'
        }
        if ($operation -eq 'expand' -and (Test-Path -LiteralPath (Join-Path $root 'members' $member.name))) {
            $exitCode = 5
            throw "Federation member '$($member.name)' already exists."
        }
        if ($operation -eq 'expand' -and
            (Test-Path -LiteralPath (Join-Path $root 'history' "$($member.name).md"))) {
            $exitCode = 5
            throw "Federation history for '$($member.name)' already exists."
        }
    }

    $trackingExisted = Test-Path -LiteralPath $trackingRoot -PathType Container
    if (-not $trackingExisted) {
        $null = [IO.Directory]::CreateDirectory($trackingRoot)
        $trackingCreated = $true
    }
    $transactionId = [guid]::NewGuid().ToString('N')
    $stageContainer = Join-Path $trackingRoot ".squad-federation-init-$transactionId"
    $stageRepo = Join-Path $stageContainer 'repository'
    $stageSquad = Join-Path $stageRepo '.copilot-tracking' 'squad'
    $null = [IO.Directory]::CreateDirectory($stageRepo)

    foreach ($member in $payload.members) {
        $memberPayload = Join-Path $stageRepo "member-$($member.name).json"
        Write-Text $memberPayload ($member.initPayload | ConvertTo-Json -Depth 30)
        $running.Add((Get-MemberInitProcess -Name $member.name -PayloadFile $memberPayload -StageRepository $stageRepo -AgentRepository $RepoRoot))
    }
    $receipts = [ordered]@{}
    $memberErrors = [Collections.Generic.List[string]]::new()
    foreach ($run in $running) {
        if (-not $run.process.WaitForExit($MemberTimeoutSeconds * 1000)) {
            $run.process.Kill($true)
            $run.process.WaitForExit()
            $memberErrors.Add("$($run.name): exceeded $MemberTimeoutSeconds seconds")
        }
        $stdout = $run.stdout.GetAwaiter().GetResult()
        $stderr = $run.stderr.GetAwaiter().GetResult()
        $memberExitCode = $run.process.ExitCode
        if ($memberExitCode -ne 0) {
            $memberErrors.Add("$($run.name): $($stderr.Trim()) $($stdout.Trim())")
            continue
        }
        try {
            $receipt = ($stdout.Trim().Split("`n") | Where-Object { $_ -match '^\{' } | Select-Object -Last 1) | ConvertFrom-Json -AsHashtable
            if ($receipt.status -ne 'PASS' -or $receipt.verified -ne $true -or $receipt.ledgerCheck -ne 'PASS') {
                throw 'member receipt is not verified'
            }
            $receipts[$run.name] = [ordered]@{ receipt = $receipt; warnings = @($stderr.Trim() | Where-Object { $_ }) }
        }
        catch { $memberErrors.Add("$($run.name): invalid member receipt") }
    }
    if ($memberErrors.Count) { throw "Federation member initialization failed: $($memberErrors -join '; ')" }

    if ($operation -eq 'expand') {
        Copy-ExpansionProjection -LiveRoot $root -StageRoot $stageSquad -Baseline $payload.rootBaseline
    }
    if (-not (Test-Path -LiteralPath (Join-Path $stageSquad 'consumption-rates.md') -PathType Leaf)) {
        $rates = Invoke-SquadLocalScript -Name 'Initialize-SquadConsumptionRates.ps1' -Arguments @('-SquadRoot', $stageSquad)
        if ($rates.exitCode -ne 0) { throw "Federation root rate seeding failed: $($rates.stderr.Trim())" }
    }
    $block = if ($payload.Contains('orchestration')) { $payload.orchestration }
    else { New-SquadOrchestrationConsumption -RatesPath (Join-Path $stageSquad 'consumption-rates.md') -SessionModel ([string]$payload.sessionModel) }
    $keys = @('model', 'model_source', 'priced_as', 'model_tier', 'internal_turns', 'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens', 'basis')
    Assert-FieldSet $block $keys
    foreach ($field in $keys) {
        if ($field -in @('internal_turns', 'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens')) {
            if ($block[$field] -isnot [int] -and $block[$field] -isnot [long] -or $block[$field] -lt 0) {
                throw 'Invalid federation orchestration token count.'
            }
        }
        else { Assert-Line $block[$field] }
    }
    if ($block.model_source -notin @('dispatch-reported', 'session-inherited', 'operator-declared', 'cli-pinned', 'unresolved') -or
        $block.model_tier -notin @('fast', 'default', 'extended') -or
        $block.model -in @('auto', 'fast', 'default', 'extended') -or
        (($block.model -eq 'unknown') -ne ($block.model_source -eq 'unresolved')) -or
        $block.basis -ne $(if ($block.model -eq 'unknown') { 'tier-default' } else { 'estimated' }) -or
        ($block.model_source -eq 'session-inherited' -and $block.model -cne $payload.sessionModel)) {
        throw 'Invalid federation coordinator orchestration attribution.'
    }
    $expected = New-SquadOrchestrationConsumption -RatesPath (Join-Path $stageSquad 'consumption-rates.md') -SessionModel $block.model -FallbackTier $block.model_tier
    if ($block.priced_as -cne $expected.priced_as -or $block.model_tier -cne $expected.model_tier) {
        throw 'Federation coordinator orchestration does not match canonical pricing.'
    }

    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    $rootTurn = if ($operation -eq 'fresh') {
        1
    }
    else {
        $existingState = Get-Content -LiteralPath (Join-Path $stageSquad 'state.json') -Raw | ConvertFrom-Json -AsHashtable
        if ($existingState.schemaVersion -notin @('1.2', '1.3') -or
            $existingState.turn -isnot [ValueType] -or $existingState.turn -is [bool] -or
            $existingState.currentRun.estCostUsd -isnot [ValueType] -or
            $existingState.currentRun.estCreditsTotal -isnot [ValueType]) {
            throw 'Unsupported federation state for deterministic expansion.'
        }
        if ($existingState.updated -and
            [DateTimeOffset]::Parse([string]$existingState.updated, [Globalization.CultureInfo]::InvariantCulture) -ge
            [DateTimeOffset]::Parse($timestamp, [Globalization.CultureInfo]::InvariantCulture)) {
            throw 'Federation timestamp must advance.'
        }
        [int]$existingState.turn + 1
    }
    $orderedBlock = [ordered]@{}
    foreach ($field in $keys) { $orderedBlock[$field] = $block[$field] }
    $fence = '```'
    $activity = if ($operation -eq 'fresh') { 'initialization' } else { 'expansion' }
    $entry = "### $timestamp Federation $activity`n`n* Turn: $rootTurn`n* Request: Confirmed federation $activity`n* Deliverable: federation state`n* Outcome: Coordinator-only deterministic $activity; no Scribe dispatch.`n`n#### Consumption $([char]0x2014) Orchestration`n`n${fence}json`n$($orderedBlock | ConvertTo-Json)`n$fence"
    $firstMemberRoot = Join-Path $stageSquad 'members' $payload.members[0].name
    $priced = Get-OrchestrationPrice -StageRoot $stageSquad -FirstMemberRoot $firstMemberRoot -Entry $entry -Block $block -ScratchRoot (Join-Path $stageContainer 'price')

    $registryRows = [Collections.Generic.List[string]]::new()
    $routeRows = [Collections.Generic.List[string]]::new()
    $decisionLines = [Collections.Generic.List[string]]::new()
    $memberCost = 0.0
    $memberCredits = 0.0
    foreach ($member in $payload.members) {
        $memberRoot = Join-Path $stageSquad 'members' $member.name
        $state = Get-Content -LiteralPath (Join-Path $memberRoot 'state.json') -Raw | ConvertFrom-Json -AsHashtable
        $memberCost += [double]$state.currentRun.estCostUsd
        $memberCredits += [double]$state.currentRun.estCreditsTotal
        $decisionRef = Get-DecisionRef -StageRepository $stageRepo -MemberRoot $memberRoot
        $registryRows.Add("| $($member.name) | $($member.profile) | in-repo | members/$($member.name)/ | $($member.owner) | $($member.description) |")
        foreach ($route in $member.routes) {
            $routeRows.Add("| $($route.pattern) | $($member.name) | $(if ($route.parallelEligible) { 'yes' } else { 'no' }) |")
        }
        $decisionLines.Add(
            "* Sub-squad: $($member.name); Profile: $($member.profile); Owner: $($member.owner); " +
            "Description: $($member.description); Routes: $(@($member.routes | ForEach-Object pattern) -join ', '); Decision Ref: $decisionRef"
        )
        $history = @"
---
description: "Append-only federation sub-squad history"
---

# History: $($member.name)

### $timestamp Initialization

* Turn: $rootTurn
* Request: Initialize federation member $($member.name).
* Outcome: Member initialized and verified through the standard direct Init transaction.
* Decision Refs: $decisionRef
"@
        Write-Text (Join-Path $stageSquad 'history' "$($member.name).md") ($history.TrimStart() + "`n")
    }

    if ($operation -eq 'fresh') {
        $federation = @"
---
description: "Squad federation registry: the named sub-squads in this repository and the profile each was seeded from"
---

# Squad Federation

## Sub-Squads

| Sub-squad | Profile | Kind | Location | Owner | Description |
|-----------|---------|------|----------|-------|-------------|
$($registryRows -join "`n")
"@
        Write-Text (Join-Path $stageSquad 'federation.md') ($federation.TrimStart() + "`n")
        $routing = @"
---
description: "Squad federation meta-routing: request patterns mapped to the sub-squad that handles them"
---

# Squad Federation Meta-Routing

| Pattern / Domain | Sub-squad | Parallel-Eligible |
|------------------|-----------|-------------------|
$($routeRows -join "`n")
"@
        Write-Text (Join-Path $stageSquad 'meta-routing.md') ($routing.TrimStart() + "`n")
        $decisions = @"
---
description: "Append-only log of squad federation routing decisions and their rationale"
---

# Squad Federation Decisions

Entries are appended below in chronological order.

## $timestamp Initialize federation

* Turn: 1
* Run: $($payload.runId)
* Rationale: Publish the complete confirmed federation through one validated transaction.
$($decisionLines -join "`n")
"@
        Write-Text (Join-Path $stageSquad 'decisions.md') ($decisions.TrimStart() + "`n")
        Write-Text (Join-Path $stageSquad 'history' 'Squad Scribe.md') "---`ndescription: Append-only orchestration history`n---`n`n# History: Squad Scribe`n`n$entry`n"

        $stateSection = Get-SquadReferenceSection -Path (Join-Path $PSScriptRoot '..' 'references' 'federation-templates.md') -Heading '### state.json (federation root)'
        $stateMatch = [regex]::Match($stateSection, '(?s)```json\s*\n(?<json>.*?)\n```')
        if (-not $stateMatch.Success) { throw 'Missing canonical federation state seed.' }
        $rootState = $stateMatch.Groups['json'].Value | ConvertFrom-Json -AsHashtable
        $rootState.updated = $timestamp
        $rootState.turn = 1
        $rootState.mode = 'interactive'
        $rootState.subSquads = @($payload.members | ForEach-Object name)
        $rootState.activeSubSquads = @()
        $rootState.currentRun.sessionModel = $payload.sessionModel
        $rootState.currentRun.modelOverrides = $payload.modelOverrides
        $rootState.currentRun.estCostUsd = [Math]::Round($memberCost + [double]$priced.total.estCostUsd, 4)
        $rootState.currentRun.estCreditsTotal = [Math]::Round($memberCredits + [double]$priced.total.estCredits, 2)
        foreach ($field in $payload.notify.Keys) { $rootState.notify[$field] = $payload.notify[$field] }
        Write-Text (Join-Path $stageSquad 'state.json') (($rootState | ConvertTo-Json -Depth 30) + "`n")
        $receiptCost = [double]$rootState.currentRun.estCostUsd
        $receiptCredits = [double]$rootState.currentRun.estCreditsTotal
        $totalMemberCount = $payload.members.Count
    }
    else {
        Add-TableRow -Path (Join-Path $stageSquad 'federation.md') -Rows $registryRows.ToArray()
        Add-TableRow -Path (Join-Path $stageSquad 'meta-routing.md') -Rows $routeRows.ToArray()
        $decisionEntry = "## $timestamp Expand federation`n`n* Turn: $rootTurn`n* Run: $($payload.runId)`n* Rationale: Add the confirmed sub-squad members through the deterministic Federation Init transaction.`n$($decisionLines -join "`n")"
        [IO.File]::WriteAllBytes(
            (Join-Path $stageSquad 'decisions.md'),
            (Add-EntryContent -Path (Join-Path $stageSquad 'decisions.md') -Header '' -Entry $decisionEntry)
        )
        $orchestrationPath = Join-Path $stageSquad 'history' 'Squad Scribe.md'
        [IO.File]::WriteAllBytes(
            $orchestrationPath,
            (Add-EntryContent -Path $orchestrationPath -Header "---`ndescription: Append-only orchestration history`n---`n`n# History: Squad Scribe" -Entry $entry)
        )

        $existingNames = @($existingState.subSquads)
        $existingCost = [double](@($payload.rootBaseline.snapshot.members.Values | ForEach-Object costUsd) | Measure-Object -Sum).Sum
        $existingCredits = [double](@($payload.rootBaseline.snapshot.members.Values | ForEach-Object credits) | Measure-Object -Sum).Sum
        $priorCost = [double]$existingState.currentRun.estCostUsd
        $priorCredits = [double]$existingState.currentRun.estCreditsTotal
        $overheadCost = $priorCost - $existingCost
        $overheadCredits = $priorCredits - $existingCredits
        if (-not [double]::IsFinite($overheadCost) -or -not [double]::IsFinite($overheadCredits) -or
            $overheadCost -lt -0.00005 -or $overheadCredits -lt -0.005) {
            throw 'Prior federation totals do not cover the existing member totals.'
        }
        $stateText = [IO.File]::ReadAllText((Join-Path $stageSquad 'state.json'))
        $next = [Text.Json.Nodes.JsonNode]::Parse($stateText).DeepClone()
        $next['schemaVersion'] = '1.3'
        $next['updated'] = $timestamp
        $next['turn'] = $rootTurn
        $next['subSquads'] = [Text.Json.Nodes.JsonNode]::Parse((ConvertTo-Json -InputObject @($existingNames + @($payload.members | ForEach-Object name)) -Compress))
        $next['activeSubSquads'] = [Text.Json.Nodes.JsonNode]::Parse('[]')
        $next['currentRun']['sessionModel'] = [string]$payload.sessionModel
        $next['currentRun']['modelOverrides'] = [Text.Json.Nodes.JsonNode]::Parse(($payload.modelOverrides | ConvertTo-Json -Compress))
        $next['currentRun']['estCostUsd'] = [Math]::Round($existingCost + $memberCost + [Math]::Max(0.0, $overheadCost) + [double]$priced.total.estCostUsd, 4)
        $next['currentRun']['estCreditsTotal'] = [Math]::Round($existingCredits + $memberCredits + [Math]::Max(0.0, $overheadCredits) + [double]$priced.total.estCredits, 2)
        $next['notify'] = [Text.Json.Nodes.JsonNode]::Parse(($payload.notify | ConvertTo-Json -Depth 10 -Compress))
        $stateSection = Get-SquadReferenceSection -Path (Join-Path $PSScriptRoot '..' 'references' 'federation-templates.md') -Heading '### state.json (federation root)'
        $stateMatch = [regex]::Match($stateSection, '(?s)```json\s*\n(?<json>.*?)\n```')
        if (-not $stateMatch.Success) { throw 'Missing canonical federation state seed.' }
        $seed = [Text.Json.Nodes.JsonNode]::Parse($stateMatch.Groups['json'].Value)
        $next['currentRun']['costPreflight'] = $seed['currentRun']['costPreflight'].DeepClone()
        Write-Text (Join-Path $stageSquad 'state.json') ($next.ToJsonString([Text.Json.JsonSerializerOptions]@{ WriteIndented = $true }) + "`n")
        $receiptCost = [double]$next['currentRun']['estCostUsd'].ToString()
        $receiptCredits = [double]$next['currentRun']['estCreditsTotal'].ToString()
        $totalMemberCount = $existingNames.Count + $payload.members.Count
    }

    $snapshot = Get-SquadFederationSnapshot -SquadRoot $stageSquad -RepoRoot $stageRepo
    if ($snapshot.members.Count -ne $totalMemberCount) { throw 'Staged federation member count mismatch.' }
    if ($operation -eq 'fresh') { $finalSnapshot = Get-TreeSnapshot $stageSquad }

    $key = (Get-Hash ([Text.UTF8Encoding]::new($false).GetBytes($root.ToLowerInvariant()))).Substring(0, 16)
    $lockPath = Join-Path ([IO.Path]::GetTempPath()) "hve-squad-handoff-$key.lock"
    $deadline = [DateTime]::UtcNow.AddSeconds($LockTimeoutSeconds)
    while (-not $lock) {
        try { $lock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) { $exitCode = 8; throw 'Federation Init writer lock timed out; nothing was published.' }
            Start-Sleep -Milliseconds 200
        }
    }
    if ($operation -eq 'fresh') {
        Assert-RootBaseline -Expected $payload.rootBaseline -Path $root
    }
    else {
        Assert-FederationBaseline -Expected $payload.rootBaseline -Path $root -Repository $RepoRoot
    }
    $exitCode = 3
    if ($operation -eq 'fresh') {
        if (Test-Path -LiteralPath $root) {
            $backupRoot = Join-Path $stageContainer 'empty-root-backup'
            [IO.Directory]::Move($root, $backupRoot)
        }
        [IO.Directory]::Move($stageSquad, $root)
        $published = $true
        if ((Get-TreeSnapshot $root) -cne $finalSnapshot) { throw 'Published federation verification failed.' }
    }
    else {
        foreach ($member in $payload.members) {
            $stageMember = Join-Path $stageSquad 'members' $member.name
            $liveMember = Join-Path $root 'members' $member.name
            if (Test-Path -LiteralPath $liveMember) {
                $exitCode = 5
                throw "Federation member '$($member.name)' already exists."
            }
            $digest = Get-TreeSnapshot $stageMember
            [IO.Directory]::Move($stageMember, $liveMember)
            $movedMembers.Add([pscustomobject]@{ name = $member.name; stage = $stageMember; live = $liveMember; digest = $digest })
        }
        $publishFiles = [Collections.Generic.List[string]]::new()
        foreach ($member in $payload.members) { $publishFiles.Add("history/$($member.name).md") }
        foreach ($relative in @('history/Squad Scribe.md', 'decisions.md', 'federation.md', 'meta-routing.md')) {
            $publishFiles.Add($relative)
        }
        if (-not (Test-Path -LiteralPath (Join-Path $root 'consumption-rates.md') -PathType Leaf)) {
            $publishFiles.Add('consumption-rates.md')
        }
        $publishFiles.Add('state.json')
        foreach ($relative in $publishFiles) {
            Write-Atomic -Path (Join-Path $root $relative) -Bytes ([IO.File]::ReadAllBytes((Join-Path $stageSquad $relative)))
        }
    }
    $publishedSnapshot = Get-SquadFederationSnapshot -SquadRoot $root -RepoRoot $RepoRoot
    if ($publishedSnapshot.members.Count -ne $totalMemberCount) { throw 'Published federation member verification failed.' }
    if ($operation -eq 'expand' -and
        (($snapshot.files | ConvertTo-Json -Depth 10 -Compress) -cne
            ($publishedSnapshot.files | ConvertTo-Json -Depth 10 -Compress) -or
         ($snapshot.members | ConvertTo-Json -Depth 10 -Compress) -cne
            ($publishedSnapshot.members | ConvertTo-Json -Depth 10 -Compress))) {
        throw 'Published federation does not match the validated expansion projection.'
    }
    $committed = $true

    $cleanupWarnings = [Collections.Generic.List[string]]::new()
    foreach ($path in @($backupRoot, $stageContainer)) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        try {
            [IO.Directory]::Delete($path, $true)
            if ($path -ceq $backupRoot) { $backupRoot = $null }
            if ($path -ceq $stageContainer) { $stageContainer = $null }
        }
        catch { $cleanupWarnings.Add("Transaction cleanup required at '$path': $($_.Exception.Message)") }
    }
    $stopwatch.Stop()
    $warnings = [Collections.Generic.List[string]]::new()
    if (-not $payload.Contains('orchestration')) {
        $warnings.Add('Federation coordinator usage uses the documented orchestration estimator floor, not measured or billed telemetry.')
    }
    foreach ($member in $receipts.Values) {
        foreach ($warning in $member.warnings) { if ($warning) { $warnings.Add($warning) } }
        foreach ($warning in $member.receipt.warnings) { if ($warning) { $warnings.Add($warning) } }
    }
    foreach ($warning in $cleanupWarnings) { $warnings.Add($warning) }
    $memberStartTimes = @($running | ForEach-Object startedAt | Sort-Object)
    $memberStartSkewMs = if ($memberStartTimes.Count -gt 1) {
        [Math]::Round(($memberStartTimes[-1] - $memberStartTimes[0]).TotalMilliseconds)
    }
    else { 0 }
    $statusBase = if ($operation -eq 'fresh') { 'initialized' } else { 'expanded' }
    [ordered]@{
        status = $(if ($cleanupWarnings.Count) { "$statusBase-cleanup-required" } else { $statusBase })
        verified = $cleanupWarnings.Count -eq 0
        operation = $operation
        squadRoot = '.copilot-tracking/squad'
        members = @($payload.members | ForEach-Object name)
        memberCount = $payload.members.Count
        totalMemberCount = $totalMemberCount
        turn = $rootTurn
        costUsd = $receiptCost
        credits = $receiptCredits
        elapsedMs = $stopwatch.ElapsedMilliseconds
        parallelMemberInitialization = $true
        memberStartSkewMs = $memberStartSkewMs
        warnings = $warnings.ToArray()
        cleanupRequired = $cleanupWarnings.Count -gt 0
    } | ConvertTo-Json -Depth 10 -Compress
    $exitCode = $(if ($cleanupWarnings.Count) { 3 } else { 0 })
}
catch {
    $restoreFailures = @()
    if (-not $committed -and $operation -eq 'expand' -and
        ($originalFiles.Count -or $movedMembers.Count)) {
        $restoreFailures = @(Restore-Expansion)
    }
    elseif (-not $committed -and ($published -or $backupRoot)) {
        $restoreFailures = @(Restore-Root -LiveRoot $root -StageRoot $stageSquad)
    }
    [Console]::Error.WriteLine("Initialize-SquadFederation: $($_.Exception.Message)")
    if ($restoreFailures.Count) {
        [Console]::Error.WriteLine("RESTORE FAILED; inspect transaction paths: $($restoreFailures -join '; ')")
        $exitCode = 3
        $preserveTransaction = $true
    }
}
finally {
    if ($lock) { $lock.Dispose() }
    foreach ($run in $running) {
        try {
            if (-not $run.process.HasExited) {
                $run.process.Kill($true)
                $run.process.WaitForExit()
            }
        }
        catch { [Console]::Error.WriteLine("Member process cleanup failed for '$($run.name)': $($_.Exception.Message)") }
        finally { $run.process.Dispose() }
    }
    if (-not $committed) {
        foreach ($path in @($stageContainer)) {
            if (-not $preserveTransaction -and $path -and (Test-Path -LiteralPath $path)) {
                try { [IO.Directory]::Delete($path, $true) } catch { [Console]::Error.WriteLine("Federation Init cleanup failed for '$path': $($_.Exception.Message)") }
            }
        }
        if ($trackingCreated -and (Test-Path -LiteralPath $trackingRoot)) {
            try {
                if (@(Get-ChildItem -LiteralPath $trackingRoot -Force).Count -eq 0) { [IO.Directory]::Delete($trackingRoot, $false) }
            }
            catch { [Console]::Error.WriteLine("Tracking-root cleanup failed: $($_.Exception.Message)") }
        }
    }
    $stopwatch.Stop()
}
exit $exitCode
