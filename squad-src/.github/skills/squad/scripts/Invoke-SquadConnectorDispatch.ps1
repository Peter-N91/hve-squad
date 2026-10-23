# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Publishes or resumes one bounded connector file exchange.
.DESCRIPTION
    Side-effecting lifecycle wrapper around Resolve-SquadConnectorDispatch.ps1.
    Publishes a snapshot before a request, checks a result once without polling,
    and persists request/snapshot hashes, retry attempts, and consumed task ids.
    Returns only validated metadata, never external narrative or artifact content.
.PARAMETER InputPath
    JSON dispatch input. Required fields: workspaceRoot, manifestPath,
    connectorId, role, deliverableRoot. A first dispatch also requires task.
    Contract 1.1 requires bindingId and allowedOutputs; teamPath defaults to
    <squadRoot>/team.md, with squadRoot defaulting to .copilot-tracking/squad.
    Optional: owner, memberName (legacy), executionChoice, deadline, retryCap.
    Supply taskId only to resume an existing exchange.
.PARAMETER InputJson
    Alternative to InputPath. Never supply both.
#>
[CmdletBinding(DefaultParameterSetName = 'Library')]
param(
    [Parameter(ParameterSetName = 'Run')][string]$InputPath,
    [Parameter(ParameterSetName = 'Run')][string]$InputJson
)

$runCli = $MyInvocation.InvocationName -ne '.'
$dispatchInputPath = $InputPath
$dispatchInputJson = $InputJson
. (Join-Path $PSScriptRoot 'Resolve-SquadConnectorDispatch.ps1')

function Stop-ConnectorDispatchLocal {
    param([Parameter(Mandatory)][string]$Code)
    throw [System.IO.InvalidDataException]::new($Code)
}

function Get-ConnectorDispatchHashLocal {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Text)))
}

function Get-ConnectorDispatchFileHashLocal {
    param([Parameter(Mandatory)][string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    try { [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($stream)) }
    finally { $stream.Dispose() }
}

function ConvertFrom-ConnectorDispatchJsonLocal {
    param([Parameter(Mandatory)][string]$Json)
    $options = @{ AsHashtable = $true; Depth = 64 }
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $options.DateKind = 'String' }
    try { $value = ConvertFrom-Json -InputObject $Json @options }
    catch [System.ArgumentException] { Stop-ConnectorDispatchLocal 'malformed-json' }
    if ($value -isnot [System.Collections.IDictionary]) { Stop-ConnectorDispatchLocal 'json-object-required' }
    return ,$value
}

function Get-ConnectorDispatchPathLocal {
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowAbsolute,
        [switch]$Directory
    )
    if ($Directory) { $Path = $Path.TrimEnd([char[]]'\/') }
    if (-not $AllowAbsolute -and ($Path -match '^[\\/]' -or $Path -match '^[A-Za-z]:')) {
        Stop-ConnectorDispatchLocal 'repository-relative-path-required'
    }
    $declared = if ([System.IO.Path]::IsPathRooted($Path)) { [System.IO.Path]::GetRelativePath($WorkspaceRoot, $Path) } else { $Path }
    foreach ($segment in ($declared -split '[\\/]')) {
        if (-not $segment -or $segment -in @('.', '..') -or $segment -match '[. ]$|[<>:"|?*\x00-\x1f]' -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            Stop-ConnectorDispatchLocal 'unsafe-repository-path'
        }
    }
    $full = if ([System.IO.Path]::IsPathRooted($Path)) { [System.IO.Path]::GetFullPath($Path) } else { [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRoot $Path)) }
    $prefix = $WorkspaceRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { Stop-ConnectorDispatchLocal 'path-outside-workspace' }
    if (Test-ConnectorReparsePointInChainLocal -RootPath $WorkspaceRoot -TargetPath $full) { Stop-ConnectorDispatchLocal 'reparse-point-path' }
    $full
}

function Read-ConnectorDispatchJsonLocal {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-ConnectorDispatchLocal 'missing-exchange-file' }
    if ((Get-Item -LiteralPath $Path -Force).Length -gt 5242880) { Stop-ConnectorDispatchLocal 'oversize-json-file' }
    ConvertFrom-ConnectorDispatchJsonLocal -Json ([System.IO.File]::ReadAllText($Path))
}

function Write-ConnectorDispatchFileLocal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text,
        [switch]$Replace
    )
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($temporary, $Text, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Move($temporary, $Path, $Replace.IsPresent)
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Invoke-SquadConnectorDispatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InputObject)

    $response = [ordered]@{
        status = 'failed'; connectorId = ''; bindingId = ''; targetKind = 'role'
        executionChoice = ''; taskId = ''; artifacts = @(); outputs = @(); reasons = @()
    }
    $phase = 'input'
    $lock = $null
    try {
        $required = @('workspaceRoot', 'manifestPath', 'connectorId', 'role', 'deliverableRoot')
        $optional = @('teamPath', 'squadRoot', 'owner', 'memberName', 'bindingId', 'targetKind',
            'executionChoice', 'allowedOutputs', 'task', 'taskId', 'deadline', 'retryCap')
        if (@(Get-ClosedSchemaIssuesLocal -Object $InputObject -Required $required -Optional $optional).Count -gt 0) {
            Stop-ConnectorDispatchLocal 'invalid-dispatch-input'
        }
        foreach ($field in $required) {
            $value = Get-ConnectorInputValueLocal -Object $InputObject -Name $field
            if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) { Stop-ConnectorDispatchLocal 'invalid-dispatch-input' }
        }
        if (-not (Test-Path -LiteralPath $InputObject.workspaceRoot -PathType Container)) { Stop-ConnectorDispatchLocal 'invalid-workspace-root' }
        $workspace = (Resolve-Path -LiteralPath $InputObject.workspaceRoot).Path
        $manifestPath = Get-ConnectorDispatchPathLocal -WorkspaceRoot $workspace -Path $InputObject.manifestPath -AllowAbsolute
        $root = Get-ConnectorDispatchPathLocal -WorkspaceRoot $workspace -Path $InputObject.deliverableRoot -Directory
        $phase = 'manifest'
        $manifest = Read-ConnectorDispatchJsonLocal -Path $manifestPath
        $check = Test-SquadConnectorManifestShape -Manifest $manifest
        if ($check.Status -ne 'ok') {
            $limitIssues = @('invalid:deadlineMinutesDefault', 'invalid:retryCapDefault')
            if (@($check.Issues | Where-Object { $_ -notin $limitIssues }).Count -eq 0) {
                Stop-ConnectorDispatchLocal 'invalid-manifest-limit'
            }
            Stop-ConnectorDispatchLocal 'invalid-manifest'
        }
        if ($manifest.connectorId -cne $InputObject.connectorId -or $manifest.roles -cnotcontains $InputObject.role) {
            Stop-ConnectorDispatchLocal 'manifest-identity-mismatch'
        }
        $drop = Get-ConnectorDispatchPathLocal -WorkspaceRoot $workspace -Path $manifest.dropPath -Directory
        if (Test-ConnectorRootsCollideLocal -Left $InputObject.deliverableRoot -Right $manifest.dropPath) {
            Stop-ConnectorDispatchLocal 'mailbox-overlaps-deliverable-root'
        }
        $response.connectorId = [string]$manifest.connectorId
        $phase = 'request'
        $version = $manifest.schemaVersion
        $provenance = [ordered]@{
            connectorId = $response.connectorId; bindingId = 'legacy-1.0'; endpointKind = 'agent'
            roleMode = 'replace'; targetKind = 'role'; target = "role:$($InputObject.role)"
            verification = 'external-unverified'; metering = 'external-unmetered'
        }
        $member = [string](Get-ConnectorInputValueLocal -Object $InputObject -Name 'memberName' -Default '')
        if ($version -eq '1.0') {
            foreach ($field in @('bindingId', 'targetKind', 'executionChoice', 'allowedOutputs')) {
                if ($null -ne (Get-ConnectorInputValueLocal -Object $InputObject -Name $field)) { Stop-ConnectorDispatchLocal 'v11-input-under-v10' }
            }
            $squad = [string](Get-ConnectorInputValueLocal -Object $InputObject -Name 'squadRoot' -Default '.copilot-tracking/squad')
            $teamValue = [string](Get-ConnectorInputValueLocal -Object $InputObject -Name 'teamPath' -Default (Join-Path $squad 'team.md'))
            $teamPath = Get-ConnectorDispatchPathLocal -WorkspaceRoot $workspace -Path $teamValue -AllowAbsolute
            if (Test-Path -LiteralPath $teamPath -PathType Leaf) {
                $roster = Get-SquadConnectorRosterState -TeamPath $teamPath
                foreach ($row in @($roster.Members | Where-Object Role -EQ $InputObject.role)) {
                    if (@(Get-ApplicableBindingsForMemberRowLocal -Row $row -Bindings $roster.Bindings).Count -gt 0) {
                        Stop-ConnectorDispatchLocal 'legacy-conflicts-with-active-binding'
                    }
                }
            }
            if ($member) { $provenance.target += "/$member" }
        }
        else {
            $bindingId = [string](Get-ConnectorInputValueLocal -Object $InputObject -Name 'bindingId' -Default '')
            $teamValue = [string](Get-ConnectorInputValueLocal -Object $InputObject -Name 'teamPath' -Default '')
            if (-not $teamValue) {
                $squad = [string](Get-ConnectorInputValueLocal -Object $InputObject -Name 'squadRoot' -Default '.copilot-tracking/squad')
                $teamValue = Join-Path $squad 'team.md'
            }
            $teamPath = Get-ConnectorDispatchPathLocal -WorkspaceRoot $workspace -Path $teamValue -AllowAbsolute
            $roster = Get-SquadConnectorRosterState -TeamPath $teamPath
            $bindings = @($roster.Bindings | Where-Object BindingId -CEQ $bindingId)
            if ($bindings.Count -ne 1) { Stop-ConnectorDispatchLocal 'unknown-connector-binding' }
            $registeredPath = $bindings[0].ManifestPath
            if (-not [System.IO.Path]::IsPathRooted($registeredPath)) {
                $candidate = Join-Path $workspace $registeredPath
                $registeredPath = if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidate } else { Join-Path (Split-Path $teamPath -Parent) $registeredPath }
            }
            $registeredPath = Get-ConnectorDispatchPathLocal -WorkspaceRoot $workspace -Path $registeredPath -AllowAbsolute
            if (-not $registeredPath.Equals($manifestPath, [StringComparison]::OrdinalIgnoreCase)) { Stop-ConnectorDispatchLocal 'binding-manifest-mismatch' }
            Push-Location -LiteralPath $workspace
            try {
                $selection = Resolve-SquadConnectorExecution -TeamPath $teamPath -Role $InputObject.role `
                    -Execution "connector:$bindingId" -Owner ([string](Get-ConnectorInputValueLocal -Object $InputObject -Name 'owner' -Default '')) -Unattended $true
            }
            finally { Pop-Location }
            if ($selection.Status -ne 'ok' -or $selection.ConnectorId -cne $manifest.connectorId) {
                Stop-ConnectorDispatchLocal 'invalid-connector-binding'
            }
            $provenance.bindingId = $selection.BindingId
            $provenance.endpointKind = $selection.EndpointKind
            $provenance.roleMode = $selection.RoleMode
            $provenance.target = $selection.BindingTarget
            $member = $selection.MemberName
            $response.executionChoice = [string](Get-ConnectorInputValueLocal -Object $InputObject -Name 'executionChoice' -Default "connector:$bindingId")
            if ($response.executionChoice -cnotin @("connector:$bindingId", 'both')) { Stop-ConnectorDispatchLocal 'invalid-execution-choice' }
            if ((Get-ConnectorInputValueLocal -Object $InputObject -Name 'targetKind' -Default 'role') -cne 'role') {
                Stop-ConnectorDispatchLocal 'invalid-target-kind'
            }
        }
        $response.bindingId = $provenance.bindingId
        $taskId = [string](Get-ConnectorInputValueLocal -Object $InputObject -Name 'taskId' -Default '')
        $resume = -not [string]::IsNullOrEmpty($taskId)
        if (-not $resume) { $taskId = "task-$([guid]::NewGuid().ToString('N'))" }
        if ($taskId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') { Stop-ConnectorDispatchLocal 'invalid-task-id' }
        $response.taskId = $taskId
        $privateRoot = Join-Path $drop '.squad-connector'
        if ($resume -and -not (Test-Path -LiteralPath $privateRoot -PathType Container)) { Stop-ConnectorDispatchLocal 'missing-dispatch-state' }
        [void][System.IO.Directory]::CreateDirectory($privateRoot)
        $paths = @{}
        foreach ($kind in @('request', 'snapshot', 'result')) {
            $paths[$kind] = Get-ConnectorDispatchPathLocal -WorkspaceRoot $workspace -Path (Join-Path $drop "$taskId.$kind.json") -AllowAbsolute
        }
        $statePath = Get-ConnectorDispatchPathLocal -WorkspaceRoot $workspace -Path (Join-Path $privateRoot "$taskId.state.json") -AllowAbsolute
        $lockPath = Get-ConnectorDispatchPathLocal -WorkspaceRoot $workspace -Path (Join-Path $privateRoot "$taskId.lock") -AllowAbsolute
        try { $lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) }
        catch [System.IO.IOException] { Stop-ConnectorDispatchLocal 'dispatch-locked' }
        $manifestHash = Get-ConnectorDispatchFileHashLocal -Path $manifestPath
        $identity = [ordered]@{
            provenance = $provenance
            memberName = $member
            teamPath = ConvertTo-ConnectorPathKeyLocal -Path ([System.IO.Path]::GetRelativePath($workspace, $teamPath))
        }
        $identityHash = Get-ConnectorDispatchHashLocal -Text ($identity | ConvertTo-Json -Depth 8 -Compress)
        if (-not $resume) {
            $task = Get-ConnectorInputValueLocal -Object $InputObject -Name 'task'
            if ($task -isnot [string] -or [string]::IsNullOrWhiteSpace($task)) { Stop-ConnectorDispatchLocal 'missing-task' }
            $now = [DateTimeOffset]::UtcNow
            $deadline = Get-ConnectorInputValueLocal -Object $InputObject -Name 'deadline' -Default ($now.AddMinutes($manifest.deadlineMinutesDefault).ToString('o'))
            $retryCap = Get-ConnectorInputValueLocal -Object $InputObject -Name 'retryCap' -Default $manifest.retryCapDefault
            if (($retryCap -isnot [int] -and $retryCap -isnot [long]) -or $retryCap -lt 0 -or $retryCap -gt [int]::MaxValue) {
                Stop-ConnectorDispatchLocal 'invalid-retry-cap'
            }
            $request = [ordered]@{
                taskId = $taskId; connectorId = $manifest.connectorId; role = $InputObject.role
                deliverableRoot = $InputObject.deliverableRoot; task = $task; deadline = $deadline
                retryCap = $retryCap; createdAt = $now.ToString('o')
            }
            if ($version -eq '1.1') {
                $request.bindingId = $provenance.bindingId
                $request.targetKind = 'role'
                $request.executionChoice = $response.executionChoice
                $request.allowedOutputs = Get-ConnectorInputValueLocal -Object $InputObject -Name 'allowedOutputs'
            }
            $check = Test-SquadConnectorRequestShape -Request $request -SchemaVersion $version
            if ($check.Status -ne 'ok') { Stop-ConnectorDispatchLocal 'invalid-request' }
            try { [void][DateTimeOffset]::Parse([string]$request.deadline, [Globalization.CultureInfo]::InvariantCulture) }
            catch [FormatException] { Stop-ConnectorDispatchLocal 'invalid-deadline' }
            if ($version -eq '1.1') {
                $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($output in $request.allowedOutputs) {
                    if ($output.outputId -isnot [string] -or [string]::IsNullOrWhiteSpace($output.outputId) -or -not $seen.Add($output.outputId)) {
                        Stop-ConnectorDispatchLocal 'invalid-output-id'
                    }
                    if (-not (Test-ConnectorRootContainedLocal -ParentRoot $request.deliverableRoot -ChildRoot $output.deliverableRoot)) {
                        Stop-ConnectorDispatchLocal 'output-root-outside-deliverable-root'
                    }
                    [void](Get-ConnectorDispatchPathLocal -WorkspaceRoot $workspace -Path $output.deliverableRoot -Directory)
                }
            }
            $existing = @(
                if (Test-Path -LiteralPath $root -PathType Container) {
                    foreach ($item in (Get-ChildItem -LiteralPath $root -Recurse -Force)) {
                        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { Stop-ConnectorDispatchLocal 'reparse-point-baseline' }
                        if (-not $item.PSIsContainer) { [System.IO.Path]::GetRelativePath($workspace, $item.FullName).Replace('\', '/') }
                    }
                }
            )
            $snapshot = [ordered]@{
                taskId = $taskId; deliverableRoot = $request.deliverableRoot
                preExistingPaths = @($existing | Sort-Object); createdAt = $request.createdAt
            }
            if ((Test-SquadConnectorSnapshot -Snapshot $snapshot -Request $request).Status -ne 'ok') { Stop-ConnectorDispatchLocal 'invalid-snapshot' }
            $requestText = $request | ConvertTo-Json -Depth 32
            $snapshotText = $snapshot | ConvertTo-Json -Depth 32
            if ([System.Text.Encoding]::UTF8.GetByteCount($requestText) -gt 5242880) { Stop-ConnectorDispatchLocal 'oversize-request-json' }
            $state = [ordered]@{
                taskId = $taskId; connectorId = $manifest.connectorId
                requestHash = Get-ConnectorDispatchHashLocal -Text $requestText
                snapshotHash = Get-ConnectorDispatchHashLocal -Text $snapshotText
                manifestHash = $manifestHash; identityHash = $identityHash; attempts = 0; consumed = $false
            }
            if (Test-Path -LiteralPath $paths.result) { Stop-ConnectorDispatchLocal 'unsolicited-result' }
            Write-ConnectorDispatchFileLocal -Path $paths.snapshot -Text $snapshotText
            Write-ConnectorDispatchFileLocal -Path $statePath -Text ($state | ConvertTo-Json)
            Write-ConnectorDispatchFileLocal -Path $paths.request -Text $requestText
            $response.status = 'awaiting'
            return [pscustomobject]$response
        }
        $phase = 'resume'
        $state = Read-ConnectorDispatchJsonLocal -Path $statePath
        $stateFields = @('taskId', 'connectorId', 'requestHash', 'snapshotHash', 'manifestHash', 'identityHash', 'attempts', 'consumed')
        if (@(Get-ClosedSchemaIssuesLocal -Object $state -Required $stateFields).Count -gt 0 -or
            $state.taskId -cne $taskId -or $state.connectorId -cne $manifest.connectorId -or $state.consumed -isnot [bool] -or
            ($state.attempts -isnot [int] -and $state.attempts -isnot [long]) -or $state.attempts -lt 0) {
            Stop-ConnectorDispatchLocal 'invalid-dispatch-state'
        }
        if ($state.consumed) { Stop-ConnectorDispatchLocal 'replayed-task-id' }
        if ($state.manifestHash -cne $manifestHash -or $state.identityHash -cne $identityHash) { Stop-ConnectorDispatchLocal 'changed-dispatch-identity' }
        foreach ($kind in @('request', 'snapshot')) {
            $hash = Get-ConnectorDispatchFileHashLocal -Path $paths[$kind]
            if ($hash -cne $state["${kind}Hash"]) { Stop-ConnectorDispatchLocal "changed-$kind" }
        }
        $request = ConvertFrom-ConnectorDispatchJsonLocal -Json ([System.IO.File]::ReadAllText($paths.request))
        $snapshot = ConvertFrom-ConnectorDispatchJsonLocal -Json ([System.IO.File]::ReadAllText($paths.snapshot))
        if ((Test-SquadConnectorRequestShape -Request $request -SchemaVersion $version).Status -ne 'ok' -or
            $request.taskId -cne $taskId -or $request.connectorId -cne $manifest.connectorId -or
            $request.role -cne $InputObject.role -or $request.deliverableRoot -cne $InputObject.deliverableRoot) {
            Stop-ConnectorDispatchLocal 'request-identity-mismatch'
        }
        if ($version -eq '1.1' -and ($request.bindingId -cne $provenance.bindingId -or $request.executionChoice -cne $response.executionChoice)) {
            Stop-ConnectorDispatchLocal 'request-binding-mismatch'
        }
        foreach ($field in @('task', 'deadline', 'retryCap', 'allowedOutputs')) {
            $value = Get-ConnectorInputValueLocal -Object $InputObject -Name $field
            if ($null -ne $value -and ($value | ConvertTo-Json -Depth 32 -Compress) -cne ($request[$field] | ConvertTo-Json -Depth 32 -Compress)) {
                Stop-ConnectorDispatchLocal 'changed-resume-input'
            }
        }
        $snapshotCheck = Test-SquadConnectorSnapshot -Snapshot $snapshot -Request $request
        if ($snapshotCheck.Status -ne 'ok') { Stop-ConnectorDispatchLocal 'invalid-snapshot' }
        $result = $null
        if (Test-Path -LiteralPath $paths.result) {
            $result = Read-ConnectorDispatchJsonLocal -Path $paths.result
            $check = Test-SquadConnectorResultShape -Result $result -SchemaVersion $version -EndpointKind $provenance.endpointKind
            if ($check.Status -ne 'ok') { Stop-ConnectorDispatchLocal 'invalid-result' }
            $check = Test-SquadConnectorExchange -Manifest $manifest -Request $request -Result $result `
                -WorkspaceRoot $workspace -PreExistingPaths $snapshotCheck.PreExistingPaths
            if ($check.Status -ne 'ok') {
                $response.reasons = @('invalid-result') + @($check.Issues | ForEach-Object { ($_ -split ':')[0] } | Sort-Object -Unique)
                return [pscustomobject]$response
            }
        }
        if ($null -eq $result -or $result.status -eq 'awaiting') {
            $state.attempts++
            Write-ConnectorDispatchFileLocal -Path $statePath -Text ($state | ConvertTo-Json) -Replace
            if ([DateTimeOffset]::UtcNow -ge [DateTimeOffset]::Parse([string]$request.deadline, [Globalization.CultureInfo]::InvariantCulture)) {
                $response.status = 'unreachable'; $response.reasons = @('deadline-exhausted')
            }
            elseif ($state.attempts -ge $request.retryCap) {
                $response.status = 'unreachable'; $response.reasons = @('retry-cap-exhausted')
            }
            else { $response.status = 'awaiting' }
            return [pscustomobject]$response
        }
        foreach ($kind in @('request', 'snapshot')) {
            if ((Get-ConnectorDispatchFileHashLocal -Path $paths[$kind]) -cne $state["${kind}Hash"]) {
                Stop-ConnectorDispatchLocal "changed-$kind"
            }
        }
        $terminal = [ordered]@{}
        foreach ($key in $response.Keys) { $terminal[$key] = $response[$key] }
        $terminal.status = $result.status
        if ($terminal.status -eq 'completed') {
            $terminal.memberName = $member
            $terminal.verification = 'external, unverified'
            $terminal.trustedProvenance = $provenance
            $terminal.accountingNote = "External-unmetered: connector=$($manifest.connectorId)"
            $terminal.artifacts = @($result.artifacts | ForEach-Object { (Join-Path $request.deliverableRoot $_.path).Replace('\', '/') })
            $terminal.outputs = @(
                foreach ($output in @((Get-ConnectorInputValueLocal -Object $result -Name 'outputs' -Default @()))) {
                    $slot = @($request.allowedOutputs | Where-Object outputId -EQ $output.outputId)
                    [ordered]@{
                        outputId = $slot[0].outputId
                        artifacts = @($output.artifacts | ForEach-Object { (Join-Path $slot[0].deliverableRoot $_.path).Replace('\', '/') })
                    }
                }
            )
        }
        else { $terminal.reasons = @('external-terminal-status') }
        $state.consumed = $true
        Write-ConnectorDispatchFileLocal -Path $statePath -Text ($state | ConvertTo-Json) -Replace
        return [pscustomobject]$terminal
    }
    catch [System.IO.InvalidDataException] {
        $response.status = if ($phase -eq 'manifest') { 'unreachable' } else { 'failed' }
        $response.reasons = @($_.Exception.Message)
        return [pscustomobject]$response
    }
    catch [System.IO.IOException] {
        $response.status = if ($phase -eq 'manifest') { 'unreachable' } else { 'failed' }
        $response.reasons = @('dispatch-file-io-failed')
        return [pscustomobject]$response
    }
    catch [System.UnauthorizedAccessException] {
        $response.status = if ($phase -eq 'manifest') { 'unreachable' } else { 'failed' }
        $response.reasons = @('dispatch-file-access-denied')
        return [pscustomobject]$response
    }
    finally {
        if ($null -ne $lock) { $lock.Dispose() }
    }
}

if ($runCli) {
    try {
        if ((-not $dispatchInputPath -and -not $dispatchInputJson) -or ($dispatchInputPath -and $dispatchInputJson)) { Stop-ConnectorDispatchLocal 'provide-one-dispatch-input' }
        $payload = if ($dispatchInputPath) { Read-ConnectorDispatchJsonLocal -Path $dispatchInputPath } else { ConvertFrom-ConnectorDispatchJsonLocal -Json $dispatchInputJson }
        Invoke-SquadConnectorDispatch -InputObject $payload | ConvertTo-Json -Depth 32
    }
    catch [System.IO.InvalidDataException] {
        [ordered]@{ status = 'failed'; artifacts = @(); outputs = @(); reasons = @($_.Exception.Message) } | ConvertTo-Json
    }
}
