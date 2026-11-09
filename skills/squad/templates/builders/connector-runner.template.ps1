#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the removable file-drop example for connector {{CONNECTOR_ID}}.
.DESCRIPTION
    Polls only request envelopes, writes a clearly labelled demonstration
    artifact under each request-declared output root, and atomically publishes
    a matching result envelope. Replace Invoke-ExampleEndpoint with the trusted
    invocation for your agent host or orchestrator.
#>

[CmdletBinding()]
param(
    [string]$WorkspaceRoot = '.',
    [string]$ManifestPath = '{{MANIFEST_PATH}}',
    [ValidateRange(1, 3600)]
    [int]$PollSeconds = 3,
    [switch]$Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RequiredValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        throw "Missing required request field '$Name'."
    }
    $property.Value
}

function Assert-SafeIdentifier {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        throw "Request field '$Name' is not a safe identifier."
    }
}

function Resolve-SafeChildPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath -match '^[A-Za-z]:' -or
        $RelativePath -match ':') {
        throw "Expected a repository-relative path, received '$RelativePath'."
    }

    $segments = @($RelativePath.Replace('\', '/').Split('/', [StringSplitOptions]::RemoveEmptyEntries))
    if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -in '.', '..' }).Count -gt 0) {
        throw "Path '$RelativePath' contains an unsafe segment."
    }

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $candidate = [IO.Path]::GetFullPath((Join-Path $rootFull ($segments -join [IO.Path]::DirectorySeparatorChar)))
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if (-not $candidate.StartsWith("$rootFull$([IO.Path]::DirectorySeparatorChar)", $comparison)) {
        throw "Path '$RelativePath' escapes the workspace."
    }

    $cursor = $rootFull
    foreach ($segment in $segments) {
        $cursor = Join-Path $cursor $segment
        if (-not (Test-Path -LiteralPath $cursor)) { continue }
        $item = Get-Item -LiteralPath $cursor -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Path '$RelativePath' crosses a symbolic link or reparse point."
        }
    }
    $candidate
}

function Write-AtomicNewFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    if (Test-Path -LiteralPath $Path) {
        throw "Refusing to overwrite '$Path'."
    }
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $parent ".$([IO.Path]::GetFileName($Path)).$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, $Content, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $Path)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Invoke-ExampleEndpoint {
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$Workspace
    )

    $taskId = [string](Get-RequiredValue -Object $Request -Name 'taskId')
    $role = [string](Get-RequiredValue -Object $Request -Name 'role')
    Assert-SafeIdentifier -Value $taskId -Name 'taskId'
    Assert-SafeIdentifier -Value $role -Name 'role'

    $slots = if ($Manifest.endpointKind -eq 'orchestrator') {
        $allowed = @(Get-RequiredValue -Object $Request -Name 'allowedOutputs')
        if ($allowed.Count -eq 0) { throw 'An orchestrator request needs at least one allowed output.' }
        $allowed
    }
    else {
        @([pscustomobject]@{
                outputId       = 'agent-result'
                deliverableRoot = [string](Get-RequiredValue -Object $Request -Name 'deliverableRoot')
            })
    }

    $planned = [Collections.Generic.List[object]]::new()
    $seenOutputIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($slot in $slots) {
        $outputId = [string](Get-RequiredValue -Object $slot -Name 'outputId')
        Assert-SafeIdentifier -Value $outputId -Name 'outputId'
        if (-not $seenOutputIds.Add($outputId)) { throw "Duplicate outputId '$outputId'." }

        $rootRelative = [string](Get-RequiredValue -Object $slot -Name 'deliverableRoot')
        $rootPath = Resolve-SafeChildPath -Root $Workspace -RelativePath $rootRelative
        $artifactName = "connector-example-$taskId-$outputId.md"
        $artifactPath = Join-Path $rootPath $artifactName
        if (Test-Path -LiteralPath $artifactPath) {
            throw "Refusing to overwrite task artifact '$artifactPath'."
        }

        $requestReference = ".connector-drops/$($Manifest.connectorId)/$taskId.request.json"
        $content = @"
# Connector transport example

This removable example runner processed a bounded file-drop request.

* Connector: ``$($Manifest.connectorId)``
* Task: ``$taskId``
* Role: ``$role``
* Output slot: ``$outputId``
* Request envelope: ``$requestReference``

This receipt demonstrates transport compatibility only. Replace
``Invoke-ExampleEndpoint`` with your trusted external agent or orchestrator and
return source-grounded work before using this connector for production.
"@
        $planned.Add([pscustomobject]@{
                OutputId = $outputId
                FullPath = $artifactPath
                Content  = "$content`n"
                Artifact = [ordered]@{ path = $artifactName; type = 'md' }
            })
    }

    foreach ($item in $planned) {
        Write-AtomicNewFile -Path $item.FullPath -Content $item.Content
    }
    $planned.ToArray()
}

function Invoke-PendingRequest {
    param(
        [Parameter(Mandatory)][IO.FileInfo]$RequestFile,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$Workspace,
        [Parameter(Mandatory)][string]$DropDirectory
    )

    $request = Get-Content -LiteralPath $RequestFile.FullName -Raw | ConvertFrom-Json -Depth 32
    $taskId = [string](Get-RequiredValue -Object $request -Name 'taskId')
    $connectorId = [string](Get-RequiredValue -Object $request -Name 'connectorId')
    $bindingId = [string](Get-RequiredValue -Object $request -Name 'bindingId')
    $role = [string](Get-RequiredValue -Object $request -Name 'role')
    Assert-SafeIdentifier -Value $taskId -Name 'taskId'
    Assert-SafeIdentifier -Value $bindingId -Name 'bindingId'

    if ($connectorId -cne $Manifest.connectorId) {
        throw "Request connectorId '$connectorId' does not match '$($Manifest.connectorId)'."
    }
    if ($RequestFile.Name -cne "$taskId.request.json") {
        throw "Request filename does not match taskId '$taskId'."
    }

    $resultPath = Join-Path $DropDirectory "$taskId.result.json"
    if (Test-Path -LiteralPath $resultPath) { return }

    $planned = @(Invoke-ExampleEndpoint -Request $request -Manifest $Manifest -Workspace $Workspace)
    $result = [ordered]@{
        taskId     = $taskId
        connectorId = $connectorId
        bindingId  = $bindingId
        role       = $role
        status     = 'completed'
        artifacts  = @()
    }
    if ($Manifest.endpointKind -eq 'orchestrator') {
        $result.outputs = @($planned | ForEach-Object {
                [ordered]@{ outputId = $_.OutputId; artifacts = @($_.Artifact) }
            })
    }
    else {
        $result.artifacts = @($planned[0].Artifact)
    }
    $result.narrative = 'The removable example runner completed a transport demonstration; replace it with source-grounded endpoint work.'
    $result.createdAt = [DateTimeOffset]::UtcNow.ToString('o')

    Write-AtomicNewFile -Path $resultPath -Content (($result | ConvertTo-Json -Depth 16) + "`n")
    Write-Host "Published $resultPath" -ForegroundColor Green
}

$workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$manifestFullPath = Resolve-SafeChildPath -Root $workspace -RelativePath $ManifestPath
$manifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json -Depth 16
if ($manifest.schemaVersion -cne '1.1' -or $manifest.transport -cne 'file') {
    throw 'The example runner supports only connector contract 1.1 file transport.'
}
if ($manifest.connectorId -cne '{{CONNECTOR_ID}}') {
    throw "Manifest connectorId '$($manifest.connectorId)' does not match this runner."
}
if ($manifest.endpointKind -cnotin @('agent', 'orchestrator')) {
    throw "Unsupported endpointKind '$($manifest.endpointKind)'."
}

$dropDirectory = Resolve-SafeChildPath -Root $workspace -RelativePath ([string]$manifest.dropPath)
New-Item -ItemType Directory -Path $dropDirectory -Force | Out-Null

do {
    foreach ($requestFile in @(Get-ChildItem -LiteralPath $dropDirectory -File -Filter '*.request.json' | Sort-Object Name)) {
        try {
            Invoke-PendingRequest -RequestFile $requestFile -Manifest $manifest -Workspace $workspace -DropDirectory $dropDirectory
        }
        catch {
            Write-Warning "Skipped '$($requestFile.Name)': $($_.Exception.Message)"
        }
    }
    if (-not $Once) { Start-Sleep -Seconds $PollSeconds }
} while (-not $Once)