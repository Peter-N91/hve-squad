# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

#Requires -Version 7.4

Set-StrictMode -Version Latest

# This module ships with the squad skill so copied Watch Mode workflows and the
# source repository execute the same handoff enforcement.

$script:RuntimeOverlayPaths = @(
    '.github/agents'
    '.github/prompts'
    '.github/instructions'
    '.agents'
)

function ConvertTo-SquadWatchTimestamp {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($Value -is [datetimeoffset]) {
        return $Value.ToUniversalTime()
    }
    if ($Value -is [datetime]) {
        return [datetimeoffset]::new($Value.ToUniversalTime())
    }

    $parsed = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse(
            [string]$Value,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$parsed
        )) {
        return $parsed.ToUniversalTime()
    }

    $null
}

function Get-SquadWatchWorkspaceRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $prefix = $workspace + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path '$fullPath' is outside the Squad Watch workspace '$workspace'."
    }

    [System.IO.Path]::GetRelativePath($workspace, $fullPath) -replace '\\', '/'
}

function New-SquadWatchBaseline {
    <#
    .SYNOPSIS
        Captures the trusted event identity and pre-run repository file hashes used
        to distinguish current Watch Mode evidence from committed or stale evidence.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string]$MemberRoot,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('issue', 'pull_request', 'issue_comment', 'schedule', 'workflow_dispatch', 'push')]
        [string]$Source,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EventRef,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EventId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Actor,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ReceivedAt
    )

    $workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
    $member = [System.IO.Path]::GetFullPath($MemberRoot)
    $memberRelative = Get-SquadWatchWorkspaceRelativePath -WorkspaceRoot $workspace -Path $member
    if ($memberRelative -notmatch '^\.copilot-tracking/squad/members/[a-z0-9][a-z0-9-]*$') {
        throw "Squad Watch member root '$memberRelative' is not an event-scoped federation member path."
    }

    $received = ConvertTo-SquadWatchTimestamp -Value $ReceivedAt
    if (-not $received) {
        throw "Squad Watch receivedAt '$ReceivedAt' is not a valid timestamp."
    }

    $baselinePath = [System.IO.Path]::GetFullPath($Path)
    $workspacePrefix = $workspace.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if ($baselinePath.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The Squad Watch baseline must be stored outside the untrusted workspace.'
    }

    $files = [System.Collections.Generic.List[object]]::new()
    $repositoryFiles = @(
        Invoke-SquadWatchGit -WorkspaceRoot $workspace -Arguments @(
            'ls-files', '--cached', '--others', '--exclude-standard'
        ) | Where-Object { $_ } | Sort-Object -Unique
    )
    foreach ($relativePath in $repositoryFiles) {
        $normalized = $relativePath -replace '\\', '/'
        $fullPath = Join-Path $workspace $normalized
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            continue
        }

        $files.Add([ordered]@{
                path   = $normalized
                sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            })
    }

    $resume = $null
    $statePath = Join-Path $member 'state.json'
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
            $trigger = $state['trigger']
            $runId = if ($trigger -is [System.Collections.IDictionary]) { [string]$trigger['runId'] } else { '' }
            $triggerReceivedAt = ConvertTo-SquadWatchTimestamp -Value $trigger['receivedAt']
            $sameTrigger = $trigger -is [System.Collections.IDictionary] -and
            [string]$trigger['source'] -ceq $Source -and
            [string]$trigger['ref'] -ceq $EventRef -and
            [string]$trigger['eventId'] -ceq $EventId -and
            [string]$trigger['actor'] -ceq $Actor -and
            $triggerReceivedAt -and
            $triggerReceivedAt -eq $received

            if ($sameTrigger -and $runId -match '^autopilot-run-[A-Za-z0-9._-]+(?:\.md)?$') {
                $summaryName = if ($runId.EndsWith('.md', [StringComparison]::OrdinalIgnoreCase)) {
                    $runId
                }
                else {
                    "$runId.md"
                }
                $summaryPath = Join-Path $member (Join-Path 'history' $summaryName)
                if (Test-Path -LiteralPath $summaryPath -PathType Leaf) {
                    $summaryText = Get-Content -LiteralPath $summaryPath -Raw
                    $resume = [ordered]@{
                        runId       = $runId
                        summaryPath = "history/$summaryName"
                        stages      = @(
                            Get-SquadWatchStageRow -Summary $summaryText | ForEach-Object {
                                [ordered]@{
                                    stage          = [string]$_.Stage
                                    roles          = [string]$_.Roles
                                    dispatchRecord = [string]$_.DispatchRecord
                                    result         = [string]$_.Result
                                    gate           = [string]$_.Gate
                                }
                            }
                        )
                    }
                }
            }
        }
        catch {
            Write-Warning "Existing Watch Mode member state could not be captured as resume evidence: $($_.Exception.Message)"
            $resume = $null
        }
    }

    $capturedAt = [datetimeoffset]::UtcNow.ToString('o')
    $baseline = [ordered]@{
        version      = 1
        capturedAt   = $capturedAt
        memberRoot   = $memberRelative
        trigger      = [ordered]@{
            source     = $Source
            ref        = $EventRef
            eventId    = $EventId
            actor      = $Actor
            receivedAt = $received.ToUniversalTime().ToString('o')
        }
        files        = @($files)
        resume       = $resume
    }

    if (-not $PSCmdlet.ShouldProcess($baselinePath, 'Write Squad Watch trusted startup baseline')) {
        return
    }

    $parent = Split-Path -Parent $baselinePath
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $baseline | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $baselinePath -Encoding utf8NoBOM

    [pscustomobject]@{
        Path       = $baselinePath
        Hash       = (Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash.ToLowerInvariant()
        CapturedAt = $capturedAt
        MemberRoot = $memberRelative
    }
}

function Get-SquadWatchBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string]$MemberRoot,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ExpectedHash
    )

    $baselinePath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
        throw "Squad Watch lifecycle handoff blocked: trusted startup baseline '$baselinePath' is missing."
    }

    $actualHash = (Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $ExpectedHash.ToLowerInvariant()) {
        throw 'Squad Watch lifecycle handoff blocked: trusted startup baseline changed after capture.'
    }

    try {
        $baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "Squad Watch lifecycle handoff blocked: trusted startup baseline is invalid JSON: $($_.Exception.Message)"
    }

    if ($baseline['version'] -ne 1 -or
        $baseline['trigger'] -isnot [System.Collections.IDictionary] -or
        $baseline['files'] -isnot [System.Collections.IEnumerable]) {
        throw 'Squad Watch lifecycle handoff blocked: trusted startup baseline has an unsupported shape.'
    }

    $workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
    $member = [System.IO.Path]::GetFullPath($MemberRoot)
    $memberRelative = Get-SquadWatchWorkspaceRelativePath -WorkspaceRoot $workspace -Path $member
    if ([string]$baseline['memberRoot'] -cne $memberRelative) {
        throw "Squad Watch lifecycle handoff blocked: baseline member '$($baseline['memberRoot'])' does not match '$memberRelative'."
    }

    $capturedAt = ConvertTo-SquadWatchTimestamp -Value $baseline['capturedAt']
    if (-not $capturedAt) {
        throw 'Squad Watch lifecycle handoff blocked: baseline capturedAt is invalid.'
    }

    $fileHashes = @{}
    foreach ($file in @($baseline['files'])) {
        if ($file -isnot [System.Collections.IDictionary]) {
            throw 'Squad Watch lifecycle handoff blocked: baseline file inventory is invalid.'
        }
        $relativePath = ([string]$file['path']) -replace '\\', '/'
        $sha256 = ([string]$file['sha256']).ToLowerInvariant()
        if (-not $relativePath -or
            $relativePath -match '(^|/)\.\.(/|$)' -or
            $sha256 -notmatch '^[a-f0-9]{64}$' -or
            $fileHashes.ContainsKey($relativePath)) {
            throw "Squad Watch lifecycle handoff blocked: baseline file entry '$relativePath' is invalid."
        }
        $fileHashes[$relativePath] = $sha256
    }

    [pscustomobject]@{
        Path       = $baselinePath
        Hash       = $actualHash
        CapturedAt = $capturedAt
        MemberRoot = $memberRelative
        Trigger    = $baseline['trigger']
        FileHashes = $fileHashes
        Resume      = $baseline['resume']
    }
}

function Test-SquadWatchFileChanged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [object]$Baseline
    )

    $relativePath = Get-SquadWatchWorkspaceRelativePath -WorkspaceRoot $WorkspaceRoot -Path $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    -not $Baseline.FileHashes.ContainsKey($relativePath) -or
    $Baseline.FileHashes[$relativePath] -ne $actualHash
}

function Copy-SquadWatchDirectoryContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }

    New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null

    foreach ($directory in Get-ChildItem -LiteralPath $Source -Directory -Recurse -Force) {
        $relative = [System.IO.Path]::GetRelativePath($Source, $directory.FullName)
        New-Item -ItemType Directory -Path (Join-Path $Destination $relative) -Force -ErrorAction Stop | Out-Null
    }

    foreach ($file in Get-ChildItem -LiteralPath $Source -File -Recurse -Force) {
        $relative = [System.IO.Path]::GetRelativePath($Source, $file.FullName)
        $target = Join-Path $Destination $relative
        $parent = Split-Path -Parent $target
        if ($parent) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force -ErrorAction Stop
    }
}

function Enable-SquadWatchRuntimeOverlay {
    <#
    .SYNOPSIS
        Merges the installed Squad runtime into a workspace while backing up any
        pre-existing runtime paths for exact restoration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageRoot,

        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string]$BackupRoot
    )

    $package = (Resolve-Path -LiteralPath $PackageRoot).Path
    $workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
    $backup = [System.IO.Path]::GetFullPath($BackupRoot)

    if (Test-Path -LiteralPath $backup) {
        Remove-Item -LiteralPath $backup -Recurse -Force
    }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($relativePath in $script:RuntimeOverlayPaths) {
        $source = Join-Path $package $relativePath
        if (-not (Test-Path -LiteralPath $source -PathType Container)) {
            continue
        }

        $destination = Join-Path $workspace $relativePath
        if ((Test-Path -LiteralPath $destination) -and
            -not (Test-Path -LiteralPath $destination -PathType Container)) {
            throw "Squad Watch runtime destination '$relativePath' exists but is not a directory."
        }

        $existed = Test-Path -LiteralPath $destination -PathType Container
        $originalFiles = @()
        $originalDirectories = @()
        if ($existed) {
            $original = Join-Path $backup (Join-Path 'original' $relativePath)
            Copy-SquadWatchDirectoryContent -Source $destination -Destination $original
            $originalFiles = @(
                Get-ChildItem -LiteralPath $original -File -Recurse -Force |
                    Sort-Object FullName |
                    ForEach-Object {
                        [pscustomobject]@{
                            Path   = ([System.IO.Path]::GetRelativePath($original, $_.FullName) -replace '\\', '/')
                            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                        }
                    }
            )
            $originalDirectories = @(
                Get-ChildItem -LiteralPath $original -Directory -Recurse -Force |
                    ForEach-Object {
                        [System.IO.Path]::GetRelativePath($original, $_.FullName) -replace '\\', '/'
                    } |
                    Sort-Object
            )
        }

        $entries.Add([pscustomobject]@{
                Path                = ($relativePath -replace '\\', '/')
                Existed             = $existed
                OriginalFiles       = $originalFiles
                OriginalDirectories = $originalDirectories
            })
    }

    $manifestPath = Join-Path $backup 'manifest.json'
    [ordered]@{
        version = 1
        entries = @($entries)
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()

    try {
        foreach ($entry in $entries) {
            $source = Join-Path $package $entry.Path
            $destination = Join-Path $workspace $entry.Path
            Copy-SquadWatchDirectoryContent -Source $source -Destination $destination
        }
    }
    catch {
        $provisionError = $_.Exception
        try {
            Restore-SquadWatchRuntimeOverlay `
                -WorkspaceRoot $workspace `
                -BackupRoot $backup `
                -ExpectedManifestHash $manifestHash
        }
        catch {
            throw "Squad Watch runtime provisioning failed and rollback also failed. Provisioning: $($provisionError.Message) Rollback: $($_.Exception.Message)"
        }
        throw $provisionError
    }

    [pscustomobject]@{
        BackupRoot   = $backup
        Entries      = @($entries)
        ManifestHash = $manifestHash
    }
}

function Restore-SquadWatchRuntimeOverlay {
    <#
    .SYNOPSIS
        Removes only the runtime paths owned by the overlay and restores their exact
        pre-run contents.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string]$BackupRoot,

        [string]$ExpectedManifestHash
    )

    $workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
    $backup = [System.IO.Path]::GetFullPath($BackupRoot)
    $manifestPath = Join-Path $backup 'manifest.json'

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return
    }

    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ExpectedManifestHash -and $manifestHash -ne $ExpectedManifestHash.ToLowerInvariant()) {
        throw 'Squad Watch runtime backup manifest changed after provisioning; refusing cleanup.'
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $validationFailures = [System.Collections.Generic.List[string]]::new()
    $manifestPaths = @($manifest.entries | ForEach-Object { ([string]$_.Path) -replace '\\', '/' })
    foreach ($relativePath in $manifestPaths) {
        if ($relativePath -notin $script:RuntimeOverlayPaths) {
            $validationFailures.Add("unexpected runtime path '$relativePath'")
        }
    }
    foreach ($duplicate in @($manifestPaths | Group-Object | Where-Object Count -gt 1)) {
        $validationFailures.Add("duplicate runtime path '$($duplicate.Name)'")
    }

    foreach ($entry in @($manifest.entries)) {
        $relativePath = ([string]$entry.Path) -replace '\\', '/'
        if ($relativePath -notin $script:RuntimeOverlayPaths) {
            continue
        }

        $original = Join-Path $backup (Join-Path 'original' $relativePath)
        if ([bool]$entry.Existed) {
            if (-not (Test-Path -LiteralPath $original -PathType Container)) {
                $validationFailures.Add("missing backup for pre-existing runtime path '$relativePath'")
                continue
            }

            $expectedFiles = @{}
            foreach ($file in @($entry.OriginalFiles)) {
                $path = ([string]$file.Path) -replace '\\', '/'
                $expectedFiles[$path] = ([string]$file.Sha256).ToLowerInvariant()
            }
            $actualFiles = @(
                Get-ChildItem -LiteralPath $original -File -Recurse -Force |
                    ForEach-Object {
                        [pscustomobject]@{
                            Path   = ([System.IO.Path]::GetRelativePath($original, $_.FullName) -replace '\\', '/')
                            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                        }
                    }
            )
            if ($actualFiles.Count -ne $expectedFiles.Count) {
                $validationFailures.Add("backup file inventory changed for '$relativePath'")
            }
            foreach ($file in $actualFiles) {
                if (-not $expectedFiles.ContainsKey($file.Path) -or $expectedFiles[$file.Path] -ne $file.Sha256) {
                    $validationFailures.Add("backup file changed for '$relativePath/$($file.Path)'")
                }
            }

            $expectedDirectories = @($entry.OriginalDirectories | ForEach-Object { ([string]$_) -replace '\\', '/' } | Sort-Object)
            $actualDirectories = @(
                Get-ChildItem -LiteralPath $original -Directory -Recurse -Force |
                    ForEach-Object {
                        [System.IO.Path]::GetRelativePath($original, $_.FullName) -replace '\\', '/'
                    } |
                    Sort-Object
            )
            if (($expectedDirectories -join "`n") -ne ($actualDirectories -join "`n")) {
                $validationFailures.Add("backup directory inventory changed for '$relativePath'")
            }
        }
        elseif (Test-Path -LiteralPath $original) {
            $validationFailures.Add("unexpected backup content for new runtime path '$relativePath'")
        }
    }

    if ($validationFailures.Count -gt 0) {
        throw "Squad Watch runtime backup validation failed:`n- $($validationFailures -join "`n- ")"
    }

    foreach ($entry in @($manifest.entries)) {
        $relativePath = ([string]$entry.Path) -replace '\\', '/'
        $destination = Join-Path $workspace $relativePath
        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Recurse -Force
        }

        if ([bool]$entry.Existed) {
            $original = Join-Path $backup (Join-Path 'original' $relativePath)
            Copy-SquadWatchDirectoryContent -Source $original -Destination $destination
        }
    }

    Remove-Item -LiteralPath $backup -Recurse -Force
}

function ConvertFrom-SquadWatchTableLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Line
    )

    @(($Line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim() })
}

function Get-SquadWatchMarkdownTable {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Content
    )

    if (-not $Content) {
        return @()
    }

    $lines = @($Content -split '\r?\n')
    $tables = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt ($lines.Count - 1); $index++) {
        if ($lines[$index] -notmatch '^\s*\|' -or
            $lines[$index + 1] -notmatch '^\s*\|(?:\s*:?-+:?\s*\|)+\s*$') {
            continue
        }

        $header = @(ConvertFrom-SquadWatchTableLine -Line $lines[$index])
        $rows = [System.Collections.Generic.List[object]]::new()
        $cursor = $index + 2
        while ($cursor -lt $lines.Count -and $lines[$cursor] -match '^\s*\|') {
            $cells = @(ConvertFrom-SquadWatchTableLine -Line $lines[$cursor])
            if ($cells.Count -eq $header.Count) {
                $row = @{}
                for ($cell = 0; $cell -lt $header.Count; $cell++) {
                    $row[$header[$cell]] = $cells[$cell]
                }
                $rows.Add($row)
            }
            $cursor++
        }

        $tables.Add([pscustomobject]@{
                Header = $header
                Rows   = @($rows)
            })
        $index = $cursor - 1
    }

    @($tables)
}

function Get-SquadWatchRosterModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MemberRoot
    )

    $teamPath = Join-Path $MemberRoot 'team.md'
    $team = if (Test-Path -LiteralPath $teamPath -PathType Leaf) {
        Get-Content -LiteralPath $teamPath -Raw
    }
    else {
        ''
    }

    $roleAgents = @{}
    $agentRoots = @{}
    $rosterAgents = [System.Collections.Generic.List[string]]::new()
    foreach ($table in Get-SquadWatchMarkdownTable -Content $team) {
        if ('Role' -notin $table.Header -or
            'Agent Name (Primary)' -notin $table.Header) {
            continue
        }

        foreach ($row in $table.Rows) {
            $role = ([string]$row['Role']).Trim().ToLowerInvariant()
            $agents = [System.Collections.Generic.List[string]]::new()
            foreach ($value in @(
                    [string]$row['Agent Name (Primary)']
                    if ('Alternate Agents' -in $table.Header) {
                        @(([string]$row['Alternate Agents']) -split ',')
                    }
                )) {
                $agent = ([string]$value).Trim()
                if ($agent -and $agent -notmatch '^[-\u2014]$') {
                    $agents.Add($agent)
                    if ($agent -notin $rosterAgents) {
                        $rosterAgents.Add($agent)
                    }
                }
            }

            if ($role) {
                $roleAgents[$role] = @($agents)
            }

            if ('Deliverable Root' -in $table.Header) {
                $root = (([string]$row['Deliverable Root']) -replace '`', '').Trim() -replace '\\', '/'
                if ($root -match '/') {
                    foreach ($agent in $agents) {
                        $agentRoots[$agent] = $root
                    }
                }
            }
        }
    }

    [pscustomobject]@{
        Team         = $team
        RoleAgents   = $roleAgents
        AgentRoots   = $agentRoots
        RosterAgents = @($rosterAgents)
    }
}

function Get-SquadWatchDeliverableToken {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    $tokens = @([regex]::Matches($Value, '`(?<path>[^`]+)`') | ForEach-Object {
            $_.Groups['path'].Value
        })
    if ($tokens.Count -eq 0) {
        $bare = ($Value -split '\s\(')[0].Trim().TrimEnd(',', ';', '.')
        if ($bare -match '[/\\]' -and $bare -match '\.[A-Za-z0-9]{1,8}$') {
            $tokens = @($bare)
        }
    }

    @(
        $tokens |
            ForEach-Object { $_.Trim().TrimEnd(',', ';', '.') -replace '\\', '/' } |
            Where-Object { $_ -and $_ -notmatch '[*?{}]' }
    )
}

function Get-SquadWatchLatestHistoryEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw
    $headings = @([regex]::Matches($raw, '(?m)^###(?!#)[ \t]+(?<title>.+)$'))
    if ($headings.Count -eq 0) {
        return $null
    }

    $body = $raw.Substring($headings[-1].Index)
    $fields = @{}
    foreach ($match in [regex]::Matches($body, '(?m)^\s*\*\s*(?<key>Turn|Request|Deliverable|Outcome):\s*(?<value>.+)$')) {
        $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value.Trim()
    }

    $consumptionMatch = [regex]::Match(
        $body,
        '(?ms)^####\s+Consumption(?<orchestration>\s+[-\u2014]\s+Orchestration)?\s*$\r?\n+```json\r?\n(?<json>.*?)\r?\n```'
    )
    $consumption = $null
    if ($consumptionMatch.Success) {
        try {
            $consumption = $consumptionMatch.Groups['json'].Value | ConvertFrom-Json -AsHashtable
        }
        catch {
            $consumption = $null
        }
    }

    [pscustomobject]@{
        Title           = $headings[-1].Groups['title'].Value.Trim()
        Body            = $body
        Turn            = [string]$fields['Turn']
        Request         = [string]$fields['Request']
        DeliverableText = [string]$fields['Deliverable']
        Deliverables    = @(Get-SquadWatchDeliverableToken -Value ([string]$fields['Deliverable']))
        Outcome         = [string]$fields['Outcome']
        IsOrchestration = $consumptionMatch.Success -and [bool]$consumptionMatch.Groups['orchestration'].Success
        Consumption     = $consumption
    }
}

function Test-SquadWatchOutcomeComplete {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    $outcome = $Value -replace '(?i)(?<![\w.+-])(?<!\d,)(?:0+(?:[.,]0+)?|zero|no)\s+(?:fail(?:ed|ures?|ing)?|errors?)\b', ''
    $outcome = $outcome -replace '(?i)\b(?:fail(?:ed|ures?|ing)?|errors?)\s*[:=]\s*0+(?:[.,]0+)?\b(?![.,]\d)', ''
    [bool]($Value -and $outcome -notmatch '(?ix)\b(
        fail(?:ed|ures?|ing)? | errors? | incomplete | pending | running |
        blocked | escalated | stopped | cancelled | canceled |
        not[\s-]+(?:yet[\s-]+)?(?:started|run|complet(?:e|ed)|finished|done|successful) |
        never[\s-]+started | in[\s-]+progress
    )\b')
}

function Test-SquadWatchStructuredFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    if ((Get-Item -LiteralPath $Path).Length -eq 0) {
        return $false
    }
    $extension = [System.IO.Path]::GetExtension($Path)
    if ($extension -notin @('.md', '.markdown', '.txt')) {
        return $true
    }

    $content = Get-Content -LiteralPath $Path -Raw
    $hasHeading = $content -match '(?m)^#{1,6}\s+\S'
    $hasBody = @(
        $content -split '\r?\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object {
                $_ -and
                $_ -notmatch '^---$' -and
                $_ -notmatch '^#{1,6}\s+' -and
                $_ -notmatch '^```' -and
                $_ -notmatch '^\|?[\s:|-]+\|?$'
            }
    ).Count -gt 0

    $hasBody -and ($hasHeading -or $extension -eq '.txt')
}

function Test-SquadWatchEmptyCouncilItem {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    $Value.Trim() -match '^(?i:none|n/?a|not applicable|not required|[-\u2014])?\.?$'
}

function Get-SquadWatchLatestCouncilVerdict {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Content,

        [string]$TopicId
    )

    $verdictMatches = @([regex]::Matches(
            $Content,
            '(?ms)^## Council Verdict\s+(?<timestamp>\S+)\s+(?<topic>[^\r\n]+)\r?\n(?<body>.*?)(?=^## |\z)'
        ) | Where-Object {
            -not $TopicId -or $_.Groups['topic'].Value.Trim() -ceq $TopicId
        })
    if ($verdictMatches.Count -eq 0) {
        return $null
    }

    $section = $verdictMatches[-1].Value
    $body = $verdictMatches[-1].Groups['body'].Value
    $fields = @{}
    foreach ($match in [regex]::Matches(
            $body,
            '(?m)^\s*\*\s*(?<key>Topic|Proposal Ref|Council Members Dispatched|Council Members Not Proposed|Verdict|Blocking Issues|Conditions|Conditions Outstanding|Conditions Satisfied|Conditions Accepted):[ \t]*(?<value>[^\r\n]*)\r?$'
        )) {
        $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value.Trim()
    }

    $findings = @()
    foreach ($table in Get-SquadWatchMarkdownTable -Content $body) {
        if ('Role' -in $table.Header -and 'Verdict' -in $table.Header -and 'Risk' -in $table.Header) {
            $findings = @($table.Rows)
            break
        }
    }

    [pscustomobject]@{
        Section           = $section
        Timestamp         = $verdictMatches[-1].Groups['timestamp'].Value.Trim()
        TopicId           = $verdictMatches[-1].Groups['topic'].Value.Trim()
        Topic             = [string]$fields['Topic']
        ProposalRef       = [string]$fields['Proposal Ref']
        MembersDispatched = @(
            ([string]$fields['Council Members Dispatched']) -split ',' |
                ForEach-Object { $_.Trim().ToLowerInvariant() } |
                Where-Object { $_ }
        )
        Verdict           = [string]$fields['Verdict']
        Findings          = $findings
        BlockingIssues    = [string]$fields['Blocking Issues']
        Conditions        = [string]$fields['Conditions']
        ConditionsOutstanding = [string]$fields['Conditions Outstanding']
        ConditionsSatisfied = [string]$fields['Conditions Satisfied']
        ConditionsAccepted = [string]$fields['Conditions Accepted']
        PermitsImplement  = $body -match '(?im)^\s*\*\s*Permits Implementation Dispatch:\s*yes\b'
        HasSynthesis      = $body -match '(?m)^### Synthesis\s*$' -and
        $body -match '(?m)^\s*\*\s*(Blocking Issues|Conditions|Suggested Follow-ups):\s*\S'
    }
}

function Get-SquadWatchStageRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Summary
    )

    $sections = @([regex]::Matches(
            $Summary,
            '(?ms)^## Stages\s*\r?\n(?<body>.*?)(?=^## |\z)'
        ))
    if ($sections.Count -eq 0) {
        return @()
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($sections[-1].Groups['body'].Value -split '\r?\n')) {
        if ($line -notmatch '^\s*\|') {
            continue
        }
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') {
            continue
        }

        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 5 -or $cells[0] -eq 'Stage') {
            continue
        }

        $rows.Add([pscustomobject]@{
                Stage          = $cells[0]
                Roles          = $cells[1]
                DispatchRecord = $cells[2]
                Result         = $cells[3]
                Gate           = $cells[4]
            })
    }

    @($rows)
}

function Get-SquadWatchHistoryReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    @(
        foreach ($row in $Rows) {
            foreach ($match in [regex]::Matches(
                    [string]$row.DispatchRecord,
                    '`(?<path>history[/\\][^`]+\.md)`'
                )) {
                $match.Groups['path'].Value -replace '\\', '/'
            }
        }
    ) | Sort-Object -Unique
}

function Get-SquadWatchStageKey {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Stage
    )

    $Stage.Split(':')[0].Trim().ToLowerInvariant()
}

function Get-SquadWatchLatestBullet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$Label
    )

    $bulletMatches = @([regex]::Matches(
            $Content,
            '(?m)^\s*\*\s*' + [regex]::Escape($Label) + ':\s*(?<value>.+)$'
        ))
    if ($bulletMatches.Count -eq 0) {
        return $null
    }

    $bulletMatches[-1].Groups['value'].Value.Trim()
}

function Get-SquadWatchCurrentSummaryPreamble {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $stageSections = @([regex]::Matches($Content, '(?m)^## Stages\s*$'))
    if ($stageSections.Count -eq 0) {
        return ''
    }

    $beforeStages = $Content.Substring(0, $stageSections[-1].Index)
    $outcomes = @([regex]::Matches($beforeStages, '(?m)^\*\s*Outcome:\s*.+$'))
    if ($outcomes.Count -eq 0) {
        return ''
    }

    $beforeStages.Substring($outcomes[-1].Index)
}

function Get-SquadWatchRowRole {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Roles
    )

    @(
        ($Roles -replace '`', '') -split '(?:,|;|/|\+|\band\b)' |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { $_ -and $_ -notmatch '^(none|n/?a|not applicable|not required|[-\u2014])$' }
    )
}

function Test-SquadWatchBaselineStageReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Baseline,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [string]$Stage,

        [Parameter(Mandatory)]
        [string]$HistoryReference
    )

    if ($Baseline.Resume -isnot [System.Collections.IDictionary] -or
        [string]$Baseline.Resume['runId'] -cne $RunId) {
        return $false
    }

    foreach ($row in @($Baseline.Resume['stages'])) {
        if ($row -isnot [System.Collections.IDictionary] -or
            (Get-SquadWatchStageKey -Stage ([string]$row['stage'])) -ne $Stage -or
            -not (Test-SquadWatchOutcomeComplete -Value ([string]$row['result']))) {
            continue
        }

        $references = @(Get-SquadWatchHistoryReference -Rows @([pscustomobject]@{
                    DispatchRecord = [string]$row['dispatchRecord']
                }))
        if ($HistoryReference -in $references) {
            return $true
        }
    }

    $false
}

function Resolve-SquadWatchDeliverable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string]$MemberRoot,

        [Parameter(Mandatory)]
        [string]$MemberName,

        [Parameter(Mandatory)]
        [string]$Deliverable,

        [string]$DeclaredRoot
    )

    $normalized = $Deliverable.Trim().Trim('`').TrimEnd(',', ';', '.') -replace '\\', '/'
    if (-not $normalized -or
        [System.IO.Path]::IsPathRooted($normalized) -or
        $normalized -match '(^|/)\.\.(/|$)') {
        return [pscustomobject]@{
            Path           = $null
            Normalized     = $normalized
            MemberMismatch = $false
            UnderRoot      = $false
        }
    }

    $memberMatch = [regex]::Match(
        $normalized,
        '^\.copilot-tracking/squad/members/(?<member>[^/]+)(?:/|$)'
    )
    if ($memberMatch.Success -and $memberMatch.Groups['member'].Value -cne $MemberName) {
        return [pscustomobject]@{
            Path           = $null
            Normalized     = $normalized
            MemberMismatch = $true
            UnderRoot      = $false
        }
    }

    $workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
    $member = (Resolve-Path -LiteralPath $MemberRoot).Path
    $memberRelative = Get-SquadWatchWorkspaceRelativePath -WorkspaceRoot $workspace -Path $member
    $memberLocal = $normalized -match '^(research|plans|changes|reviews|history)(/|$)'
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($normalized.StartsWith("$memberRelative/", [StringComparison]::OrdinalIgnoreCase) -or
        $normalized -match '^\.copilot-tracking/') {
        $candidates.Add((Join-Path $workspace $normalized))
    }
    elseif ($memberLocal) {
        $candidates.Add((Join-Path $member $normalized))
    }
    else {
        $candidates.Add((Join-Path $workspace $normalized))
        $candidates.Add((Join-Path $member $normalized))
    }

    $resolved = @(
        $candidates |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            ForEach-Object { (Get-Item -LiteralPath $_).FullName } |
            Select-Object -Unique
        ) | Select-Object -First 1
        if (-not $resolved) {
            return [pscustomobject]@{
                Path           = $null
                Normalized     = $normalized
                MemberMismatch = $false
                UnderRoot      = $false
            }
        }

        $underRoot = $true
        if ($DeclaredRoot) {
            $root = (($DeclaredRoot -replace '`', '') -split '<')[0].Trim().TrimEnd('/') -replace '\\', '/'
            $rootMemberMatch = [regex]::Match(
                $root,
                '^\.copilot-tracking/squad/members/(?<member>[^/]+)(?:/|$)'
            )
            if ($rootMemberMatch.Success -and $rootMemberMatch.Groups['member'].Value -cne $MemberName) {
                $underRoot = $false
            }
            elseif ($root) {
                $rootMemberLocal = $root -match '^(research|plans|changes|reviews|history)(/|$)'
                $rootPath = if ($root.StartsWith("$memberRelative/", [StringComparison]::OrdinalIgnoreCase) -or
                    $root -match '^\.copilot-tracking/') {
                    Join-Path $workspace $root
                }
                elseif ($rootMemberLocal) {
                    Join-Path $member $root
                }
                else {
                    Join-Path $workspace $root
                }
                $rootFull = [System.IO.Path]::GetFullPath($rootPath).TrimEnd('\', '/')
                $resolvedFull = [System.IO.Path]::GetFullPath($resolved)
                $underRoot = $resolvedFull.StartsWith(
                    $rootFull + [System.IO.Path]::DirectorySeparatorChar,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
        }

        [pscustomobject]@{
            Path           = $resolved
            Normalized     = $normalized
            MemberMismatch = $false
            UnderRoot      = $underRoot
        }
    }

    function Test-SquadWatchHistoryEvidence {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$WorkspaceRoot,

            [Parameter(Mandatory)]
            [string]$MemberRoot,

            [Parameter(Mandatory)]
            [string]$MemberName,

            [Parameter(Mandatory)]
            [string]$RelativePath,

            [Parameter(Mandatory)]
            [string]$Stage,

            [Parameter(Mandatory)]
            [bool]$RequireCurrent,

            [Parameter(Mandatory)]
            [object]$Baseline,

            [Parameter(Mandatory)]
            [string]$RunId,

            [Parameter(Mandatory)]
            [object]$Roster
        )

        $failures = [System.Collections.Generic.List[string]]::new()
        $historyPath = Join-Path $MemberRoot $RelativePath
        $agent = [System.IO.Path]::GetFileNameWithoutExtension($historyPath)
        if (-not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
            $failures.Add("autopilot summary references missing '$RelativePath'")
            return [pscustomobject]@{
                Agent    = $agent
                Changed  = $false
                Failures = @($failures)
            }
        }

        $changed = Test-SquadWatchFileChanged `
            -WorkspaceRoot $WorkspaceRoot `
            -Path $historyPath `
            -Baseline $Baseline
        $baselineStage = Test-SquadWatchBaselineStageReference `
            -Baseline $Baseline `
            -RunId $RunId `
            -Stage $Stage `
            -HistoryReference $RelativePath
        if (-not $changed -and ($RequireCurrent -or -not $baselineStage)) {
            $failures.Add("dispatch history '$RelativePath' is not current-run evidence for '$Stage'")
        }

        $entry = Get-SquadWatchLatestHistoryEntry -Path $historyPath
        if (-not $entry) {
            $failures.Add("dispatch history '$RelativePath' has no structured entry")
            return [pscustomobject]@{
                Agent    = $agent
                Changed  = $changed
                Failures = @($failures)
            }
        }

        foreach ($field in @('Turn', 'Request', 'DeliverableText', 'Outcome')) {
            if (-not [string]$entry.$field) {
                $failures.Add("dispatch history '$RelativePath' latest entry is missing '$field'")
            }
        }
        if (-not (Test-SquadWatchOutcomeComplete -Value $entry.Outcome)) {
            $failures.Add("dispatch history '$RelativePath' latest outcome is not complete: '$($entry.Outcome)'")
        }
        if ($entry.IsOrchestration) {
            $failures.Add("dispatch history '$RelativePath' uses an orchestration block for a dispatched stage")
        }

        $requiredConsumption = @(
            'model', 'model_source', 'priced_as', 'model_tier', 'internal_turns',
            'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens', 'basis'
        )
        if ($entry.Consumption -isnot [System.Collections.IDictionary]) {
            $failures.Add("dispatch history '$RelativePath' latest entry has no valid Consumption block")
        }
        else {
            foreach ($key in $requiredConsumption) {
                if (-not $entry.Consumption.Contains($key)) {
                    $failures.Add("dispatch history '$RelativePath' Consumption block is missing '$key'")
                }
            }
            foreach ($extra in @($entry.Consumption.Keys | Where-Object { $_ -notin $requiredConsumption })) {
                $failures.Add("dispatch history '$RelativePath' Consumption block contains unsupported key '$extra'")
            }
        }

        if ($entry.Deliverables.Count -eq 0) {
            $failures.Add("dispatch history '$RelativePath' names no deliverable in its latest entry")
        }
        $declaredRoot = if ($Roster.AgentRoots.ContainsKey($agent)) {
            [string]$Roster.AgentRoots[$agent]
        }
        else {
            ''
        }
        $changedDeliverables = 0
        foreach ($deliverable in $entry.Deliverables) {
            $resolved = Resolve-SquadWatchDeliverable `
                -WorkspaceRoot $WorkspaceRoot `
                -MemberRoot $MemberRoot `
                -MemberName $MemberName `
                -Deliverable $deliverable `
                -DeclaredRoot $declaredRoot
            if ($resolved.MemberMismatch) {
                $failures.Add("$RelativePath deliverable '$deliverable' belongs to another federation member")
                continue
            }
            if (-not $resolved.Path) {
                $failures.Add("$RelativePath references missing deliverable '$deliverable'")
                continue
            }
            if (-not $resolved.UnderRoot) {
                $failures.Add("$RelativePath deliverable '$deliverable' is outside '$declaredRoot'")
            }
            if (-not (Test-SquadWatchStructuredFile -Path $resolved.Path)) {
                $failures.Add("$RelativePath deliverable '$deliverable' has no structured evidence")
            }
            if (Test-SquadWatchFileChanged -WorkspaceRoot $WorkspaceRoot -Path $resolved.Path -Baseline $Baseline) {
                $changedDeliverables++
            }
        }
        if ($changed -and $entry.Deliverables.Count -gt 0 -and $changedDeliverables -eq 0) {
            $failures.Add("dispatch history '$RelativePath' names no deliverable changed by the authorized run")
        }

        [pscustomobject]@{
            Agent    = $agent
            Changed  = $changed
            Entry    = $entry
            Failures = @($failures)
        }
    }

    function Test-SquadWatchLifecycle {
        <#
    .SYNOPSIS
        Verifies that material changes are backed by complete lifecycle evidence
        tied to the trusted event identity and startup baseline for this run.
    #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$MemberRoot,

            [Parameter(Mandatory)]
            [string]$WorkspaceRoot,

            [Parameter(Mandatory)]
            [string]$BaselinePath,

            [Parameter(Mandatory)]
            [string]$ExpectedBaselineHash
        )

        $failures = [System.Collections.Generic.List[string]]::new()
        if (-not (Test-Path -LiteralPath $MemberRoot -PathType Container)) {
            throw "Squad Watch lifecycle handoff blocked: member root '$MemberRoot' does not exist."
        }

        $member = (Resolve-Path -LiteralPath $MemberRoot).Path
        $workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
        $baseline = Get-SquadWatchBaseline `
            -WorkspaceRoot $workspace `
            -MemberRoot $member `
            -Path $BaselinePath `
            -ExpectedHash $ExpectedBaselineHash
        $memberName = Split-Path -Leaf $member

        foreach ($file in @(
                'team.md'
                'routing.md'
                'decisions.md'
                'state.json'
                'notifications.md'
                'consumption.md'
                'consumption-rates.md'
            )) {
            if (-not (Test-Path -LiteralPath (Join-Path $member $file) -PathType Leaf)) {
                $failures.Add("missing required state file '$file'")
            }
        }

        $roster = Get-SquadWatchRosterModel -MemberRoot $member
        foreach ($role in @('researcher', 'lead', 'developer', 'tester', 'scribe')) {
            if (-not $roster.RoleAgents.ContainsKey($role) -or @($roster.RoleAgents[$role]).Count -eq 0) {
                $failures.Add("team.md is missing the required '$role' role")
            }
        }

        $statePath = Join-Path $member 'state.json'
        $state = $null
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            try {
                $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
            }
            catch {
                $failures.Add("state.json is invalid JSON: $($_.Exception.Message)")
            }
        }

        if ($state -isnot [System.Collections.IDictionary]) {
            $failures.Add('state.json is missing or invalid')
        }
        else {
            $expectedStateKeys = @(
                'schemaVersion', 'updated', 'turn', 'mode', 'activeRoles',
                'openEscalations', 'currentRun', 'notify', 'trigger'
            )
            foreach ($key in $expectedStateKeys) {
                if (-not $state.Contains($key)) {
                    $failures.Add("state.json is missing '$key'")
                }
            }
            foreach ($extra in @($state.Keys | Where-Object { $_ -notin $expectedStateKeys })) {
                $failures.Add("state.json contains unsupported key '$extra'")
            }

            if ([string]$state['schemaVersion'] -cne '1.4') {
                $failures.Add("state.json schemaVersion must be '1.4'")
            }
            if ([string]$state['mode'] -cne 'autopilot') {
                $failures.Add("state.json mode must be 'autopilot'")
            }
            if (@($state['activeRoles']).Count -gt 0) {
                $failures.Add('state.json still reports active roles')
            }

            $turn = 0
            if (-not [int]::TryParse([string]$state['turn'], [ref]$turn) -or $turn -lt 1) {
                $failures.Add('state.json turn must be a positive integer')
            }

            $updated = ConvertTo-SquadWatchTimestamp -Value $state['updated']
            if (-not $updated) {
                $failures.Add('state.json updated is not a valid timestamp')
            }
            elseif ($updated -lt $baseline.CapturedAt) {
                $failures.Add('state.json was not updated during the authorized run')
            }

            $currentRun = $state['currentRun']
            $expectedCurrentRunKeys = @(
                'sessionModel', 'modelOverrides', 'estCostUsd', 'estCreditsTotal', 'costPreflight'
            )
            if ($currentRun -isnot [System.Collections.IDictionary]) {
                $failures.Add('state.json currentRun is not an object')
            }
            else {
                foreach ($key in $expectedCurrentRunKeys) {
                    if (-not $currentRun.Contains($key)) {
                        $failures.Add("state.json currentRun is missing '$key'")
                    }
                }
                foreach ($extra in @($currentRun.Keys | Where-Object { $_ -notin $expectedCurrentRunKeys })) {
                    $failures.Add("state.json currentRun contains unsupported key '$extra'")
                }
                if ($currentRun['modelOverrides'] -isnot [System.Collections.IDictionary]) {
                    $failures.Add('state.json currentRun.modelOverrides is not an object')
                }

                $costPreflight = $currentRun['costPreflight']
                $expectedPreflightKeys = @(
                    'runId', 'roundId', 'ceilingUsd', 'evaluatedSpendUsd', 'remainingUsd',
                    'plannedDispatches', 'projectedCostUsd', 'reserveMultiplier',
                    'admissionCostUsd', 'confidence', 'basis', 'decision', 'reason'
                )
                if ($costPreflight -isnot [System.Collections.IDictionary]) {
                    $failures.Add('state.json currentRun.costPreflight is not an object')
                }
                else {
                    foreach ($key in $expectedPreflightKeys) {
                        if (-not $costPreflight.Contains($key)) {
                            $failures.Add("state.json currentRun.costPreflight is missing '$key'")
                        }
                    }
                    foreach ($extra in @($costPreflight.Keys | Where-Object { $_ -notin $expectedPreflightKeys })) {
                        $failures.Add("state.json currentRun.costPreflight contains unsupported key '$extra'")
                    }
                    if ([string]$costPreflight['confidence'] -notin @('not-applicable', 'low', 'medium')) {
                        $failures.Add('state.json currentRun.costPreflight confidence is invalid')
                    }
                    if ([string]$costPreflight['basis'] -notin @('not-requested', 'estimated', 'calibrated')) {
                        $failures.Add('state.json currentRun.costPreflight basis is invalid')
                    }
                    if ([string]$costPreflight['decision'] -notin @(
                            'not-requested', 'within-ceiling', 'over-ceiling',
                            'approved-over-ceiling', 'cannot-confirm'
                        )) {
                        $failures.Add('state.json currentRun.costPreflight decision is invalid')
                    }
                }
            }

            $notify = $state['notify']
            $expectedNotifyKeys = @('approvalChannel', 'enabled', 'email', 'github')
            if ($notify -isnot [System.Collections.IDictionary]) {
                $failures.Add('state.json notify is not an object')
            }
            else {
                foreach ($key in $expectedNotifyKeys) {
                    if (-not $notify.Contains($key)) {
                        $failures.Add("state.json notify is missing '$key'")
                    }
                }
                if ([string]$notify['approvalChannel'] -notin @('in-chat', 'github-issue', 'webhook')) {
                    $failures.Add('state.json notify.approvalChannel is invalid')
                }
                $githubNotify = $notify['github']
                if ($githubNotify -isnot [System.Collections.IDictionary] -or
                    -not $githubNotify.Contains('handle') -or
                    -not $githubNotify.Contains('repo')) {
                    $failures.Add('state.json notify.github is invalid')
                }
            }

            $trigger = $state['trigger']
            $expectedTriggerKeys = @('source', 'ref', 'eventId', 'actor', 'receivedAt', 'runId')
            if ($trigger -isnot [System.Collections.IDictionary]) {
                $failures.Add('state.json trigger is missing or invalid')
            }
            else {
                foreach ($key in $expectedTriggerKeys) {
                    if (-not $trigger.Contains($key) -or -not [string]$trigger[$key]) {
                        $failures.Add("state.json trigger is missing '$key'")
                    }
                }
                foreach ($extra in @($trigger.Keys | Where-Object { $_ -notin $expectedTriggerKeys })) {
                    $failures.Add("state.json trigger contains unsupported key '$extra'")
                }
                foreach ($key in @('source', 'ref', 'eventId', 'actor')) {
                    if ([string]$trigger[$key] -cne [string]$baseline.Trigger[$key]) {
                        $failures.Add("state.json trigger.$key does not match the authorized event")
                    }
                }

                $triggerReceivedAt = ConvertTo-SquadWatchTimestamp -Value $trigger['receivedAt']
                $expectedReceivedAt = ConvertTo-SquadWatchTimestamp -Value $baseline.Trigger['receivedAt']
                if (-not $triggerReceivedAt -or
                    -not $expectedReceivedAt -or
                    $triggerReceivedAt -ne $expectedReceivedAt) {
                    $failures.Add('state.json trigger.receivedAt does not match the authorized event')
                }
            }
        }

        if ($state -and -not (Test-SquadWatchFileChanged -WorkspaceRoot $workspace -Path $statePath -Baseline $baseline)) {
            $failures.Add('state.json was not changed during the authorized run')
        }

        $runId = if ($state -and $state['trigger'] -is [System.Collections.IDictionary]) {
            [string]$state['trigger']['runId']
        }
        else {
            ''
        }
        $summaryPath = $null
        $summaryText = ''
        if ($runId -notmatch '^autopilot-run-[A-Za-z0-9._-]+(?:\.md)?$') {
            $failures.Add("state.json trigger.runId '$runId' is not a valid autopilot run id")
        }
        else {
            $summaryName = if ($runId.EndsWith('.md', [StringComparison]::OrdinalIgnoreCase)) {
                $runId
            }
            else {
                "$runId.md"
            }
            $summaryPath = Join-Path $member (Join-Path 'history' $summaryName)
            if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
                $failures.Add("state.json trigger.runId references missing 'history/$summaryName'")
            }
            else {
                $summaryText = Get-Content -LiteralPath $summaryPath -Raw
                if (-not (Test-SquadWatchFileChanged -WorkspaceRoot $workspace -Path $summaryPath -Baseline $baseline)) {
                    $failures.Add("autopilot summary 'history/$summaryName' was not changed during the authorized run")
                }
            }
        }

        $currentSummaryPreamble = if ($summaryText) {
            Get-SquadWatchCurrentSummaryPreamble -Content $summaryText
        }
        else {
            ''
        }
        if ($summaryText -and -not $currentSummaryPreamble) {
            $failures.Add('current autopilot summary has no outcome immediately preceding its latest Stages table')
        }
        if ($currentSummaryPreamble) {
            $provenance = [ordered]@{
                'Trigger Source'      = 'source'
                'Trigger Ref'         = 'ref'
                'Trigger Event ID'    = 'eventId'
                'Trigger Actor'       = 'actor'
                'Trigger Received At' = 'receivedAt'
            }
            foreach ($label in $provenance.Keys) {
                $actual = Get-SquadWatchLatestBullet -Content $currentSummaryPreamble -Label $label
                $expected = $baseline.Trigger[$provenance[$label]]
                if ($label -eq 'Trigger Received At') {
                    $actualTime = ConvertTo-SquadWatchTimestamp -Value $actual
                    $expectedTime = ConvertTo-SquadWatchTimestamp -Value $expected
                    if (-not $actualTime -or
                        -not $expectedTime -or
                        $actualTime -ne $expectedTime) {
                        $failures.Add("autopilot summary '$label' does not match the authorized event")
                    }
                }
                elseif ($actual -cne $expected) {
                    $failures.Add("autopilot summary '$label' does not match the authorized event")
                }
            }
        }

        $historyRoot = Join-Path $member 'history'
        $stageRows = @()
        $historyReferences = @()
        if ($summaryText) {
            $outcomes = @([regex]::Matches($currentSummaryPreamble, '(?m)^\*\s*Outcome:\s*(?<value>.+)$'))
            if ($outcomes.Count -eq 0 -or
                $outcomes[-1].Groups['value'].Value -notmatch '^completed\b' -or
                -not (Test-SquadWatchOutcomeComplete -Value $outcomes[-1].Groups['value'].Value)) {
                $failures.Add('current autopilot summary does not report a completed outcome')
            }

            $stageRows = @(Get-SquadWatchStageRow -Summary $summaryText)
            foreach ($stage in @('research', 'plan', 'council', 'implement', 'review')) {
                $stageMatches = @($stageRows | Where-Object {
                        (Get-SquadWatchStageKey -Stage ([string]$_.Stage)) -eq $stage
                    })
                if ($stageMatches.Count -eq 0) {
                    $failures.Add("current autopilot summary is missing the '$stage' stage row")
                }
                elseif ($stage -ne 'implement' -and $stageMatches.Count -ne 1) {
                    $failures.Add("current autopilot summary must contain exactly one '$stage' stage row")
                }
                foreach ($row in $stageMatches) {
                    $isCouncilSkip = $stage -eq 'council' -and
                    [string]$row.Result -match '(?i)\b(skipped|not required|not applicable)\b'
                    if (-not $isCouncilSkip -and
                        -not (Test-SquadWatchOutcomeComplete -Value ([string]$row.Result))) {
                        $failures.Add("'$stage' stage result is not complete: '$($row.Result)'")
                    }
                }
            }

            $historyReferences = @(Get-SquadWatchHistoryReference -Rows $stageRows)
            foreach ($relativePath in $historyReferences) {
                if ($relativePath -notmatch '^history/[^/]+\.md$' -or
                    $relativePath -match '(^|/)\.\.(/|$)') {
                    $failures.Add("autopilot summary contains unsafe history path '$relativePath'")
                }
            }

            foreach ($stage in @('research', 'plan', 'review')) {
                $row = @($stageRows | Where-Object {
                        (Get-SquadWatchStageKey -Stage ([string]$_.Stage)) -eq $stage
                    } | Select-Object -First 1)
            if ($row.Count -eq 0) {
                continue
            }

            $role = if ($stage -eq 'plan') {
                'lead'
            }
            elseif ($stage -eq 'review') {
                'tester'
            }
            else {
                'researcher'
            }
            $references = @(Get-SquadWatchHistoryReference -Rows $row)
            $agents = @(
                foreach ($reference in $references) {
                    $evidence = Test-SquadWatchHistoryEvidence `
                        -WorkspaceRoot $workspace `
                        -MemberRoot $member `
                        -MemberName $memberName `
                        -RelativePath $reference `
                        -Stage $stage `
                        -RequireCurrent:($stage -eq 'review') `
                        -Baseline $baseline `
                        -RunId $runId `
                        -Roster $roster
                    foreach ($failure in $evidence.Failures) {
                        $failures.Add($failure)
                    }
                    $evidence.Agent
                }
            )
            if ($agents.Count -eq 0 -or
                @($agents | Where-Object { $_ -in @($roster.RoleAgents[$role]) }).Count -eq 0) {
                $failures.Add("'$stage' has no dispatch history for the roster's '$role' agent")
            }
        }

        $implementRows = @($stageRows | Where-Object {
                (Get-SquadWatchStageKey -Stage ([string]$_.Stage)) -eq 'implement'
            })
        foreach ($row in $implementRows) {
            $roles = @(Get-SquadWatchRowRole -Roles ([string]$row.Roles))
            $references = @(Get-SquadWatchHistoryReference -Rows @($row))
            $agents = @(
                foreach ($reference in $references) {
                    $evidence = Test-SquadWatchHistoryEvidence `
                        -WorkspaceRoot $workspace `
                        -MemberRoot $member `
                        -MemberName $memberName `
                        -RelativePath $reference `
                        -Stage 'implement' `
                        -RequireCurrent:$true `
                        -Baseline $baseline `
                        -RunId $runId `
                        -Roster $roster
                    foreach ($failure in $evidence.Failures) {
                        $failures.Add($failure)
                    }
                    $evidence.Agent
                }
            )
            if ($roles.Count -eq 0) {
                $failures.Add('implement stage row names no roster role')
                continue
            }
            foreach ($role in $roles) {
                if (-not $roster.RoleAgents.ContainsKey($role)) {
                    $failures.Add("implement stage selects role '$role' that is not on the roster")
                    continue
                }
                if (@($agents | Where-Object { $_ -in @($roster.RoleAgents[$role]) }).Count -eq 0) {
                    $failures.Add("implement stage has no dispatch history for selected role '$role'")
                }
            }
        }

        $councilRows = @($stageRows | Where-Object {
                (Get-SquadWatchStageKey -Stage ([string]$_.Stage)) -eq 'council'
            })
        if ($councilRows.Count -gt 0) {
            $decisionsPath = Join-Path $member 'decisions.md'
            $decisions = if (Test-Path -LiteralPath $decisionsPath -PathType Leaf) {
                Get-Content -LiteralPath $decisionsPath -Raw
            }
            else {
                ''
            }
            $expectedTopicId = ($runId -replace '^autopilot-run-', '') -replace '\.md$', ''
            $verdict = Get-SquadWatchLatestCouncilVerdict -Content $decisions -TopicId $expectedTopicId
            $councilSkipped = @($councilRows | Where-Object {
                    $_.Result -match '(?i)\b(skipped|not required|not applicable)\b'
                }).Count -eq $councilRows.Count

            if ($councilSkipped) {
                if ($verdict) {
                    $failures.Add('skipped council row contradicts the recorded Council Verdict for this run')
                }
                foreach ($row in $councilRows) {
                    if (@(Get-SquadWatchRowRole -Roles ([string]$row.Roles)).Count -gt 0) {
                        $failures.Add('skipped council row must not name selected roles')
                    }
                    if ($row.DispatchRecord -notmatch '^(?i:n/?a|not applicable|not required|skipped|[-\u2014])$') {
                        $failures.Add('skipped council row must use an explicit non-dispatch marker')
                    }
                }
            }
            else {
                $councilRoles = @(
                    $councilRows |
                        ForEach-Object { Get-SquadWatchRowRole -Roles ([string]$_.Roles) } |
                        Sort-Object -Unique
                )
                $councilReferences = @(Get-SquadWatchHistoryReference -Rows $councilRows)
                $councilEvidenceChanged = $false
                $councilAgents = @(
                    foreach ($reference in $councilReferences) {
                        $evidence = Test-SquadWatchHistoryEvidence `
                            -WorkspaceRoot $workspace `
                            -MemberRoot $member `
                            -MemberName $memberName `
                            -RelativePath $reference `
                            -Stage 'council' `
                            -RequireCurrent:$false `
                            -Baseline $baseline `
                            -RunId $runId `
                            -Roster $roster
                        foreach ($failure in $evidence.Failures) {
                            $failures.Add($failure)
                        }
                        if ($evidence.Changed) {
                            $councilEvidenceChanged = $true
                        }
                        $evidence.Agent
                    }
                )

                if ($councilRoles.Count -eq 0) {
                    $failures.Add('council stage names no selected council role')
                }
                foreach ($role in $councilRoles) {
                    if ($role -notin @('architect', 'security', 'cost-manager', 'product-owner', 'rai')) {
                        $failures.Add("council stage names unsupported role '$role'")
                        continue
                    }
                    if (-not $roster.RoleAgents.ContainsKey($role)) {
                        $failures.Add("council stage selects role '$role' that is not on the roster")
                        continue
                    }
                    if (@($councilAgents | Where-Object { $_ -in @($roster.RoleAgents[$role]) }).Count -eq 0) {
                        $failures.Add("council has no dispatch history for selected role '$role'")
                    }
                }

                if (-not $verdict) {
                    $failures.Add("council ran without a structured '## Council Verdict' decision")
                }
                else {
                    if ($councilEvidenceChanged -and
                        -not (Test-SquadWatchFileChanged -WorkspaceRoot $workspace -Path $decisionsPath -Baseline $baseline)) {
                        $failures.Add('current council dispatches have no current Council Verdict write')
                    }

                    $verdictTimestamp = ConvertTo-SquadWatchTimestamp -Value $verdict.Timestamp
                    if ($councilEvidenceChanged -and
                        (-not $verdictTimestamp -or $verdictTimestamp -lt $baseline.CapturedAt)) {
                        $failures.Add('current council dispatches resolve only to a stale Council Verdict')
                    }

                    if ($verdict.Verdict -notin @('Go', 'Go-With-Conditions')) {
                        $failures.Add("council verdict '$($verdict.Verdict)' does not permit handoff")
                    }
                    if (-not $verdict.PermitsImplement) {
                        $failures.Add('council verdict does not permit implementation dispatch')
                    }
                    if (-not $verdict.Topic -or -not $verdict.ProposalRef -or -not $verdict.HasSynthesis) {
                        $failures.Add('council verdict is missing structured topic, proposal, or synthesis evidence')
                    }
                    $proposalTokens = @(Get-SquadWatchDeliverableToken -Value $verdict.ProposalRef)
                    if ($proposalTokens.Count -ne 1) {
                        $failures.Add('council verdict Proposal Ref does not name exactly one artifact')
                    }
                    else {
                        $proposal = Resolve-SquadWatchDeliverable `
                            -WorkspaceRoot $workspace `
                            -MemberRoot $member `
                            -MemberName $memberName `
                            -Deliverable $proposalTokens[0]
                        if ($proposal.MemberMismatch -or -not $proposal.Path -or
                            -not (Test-SquadWatchStructuredFile -Path $proposal.Path)) {
                            $failures.Add("council verdict Proposal Ref '$($proposalTokens[0])' is not valid structured member evidence")
                        }
                    }

                    $actualCouncilRoles = (@($verdict.MembersDispatched) | Sort-Object) -join ','
                    $expectedCouncilRoles = ($councilRoles | Sort-Object) -join ','
                    if ($actualCouncilRoles -cne $expectedCouncilRoles) {
                        $failures.Add('council verdict membership does not match the selected council roles')
                    }
                    $findingRoles = @($verdict.Findings | ForEach-Object {
                            ([string]$_['Role']).Trim().ToLowerInvariant()
                        } | Sort-Object)
                    if (($findingRoles -join ',') -cne $expectedCouncilRoles) {
                        $failures.Add('council findings do not match the selected council roles')
                    }

                    $requiresConditions = -not (Test-SquadWatchEmptyCouncilItem -Value $verdict.Conditions)
                    if (-not (Test-SquadWatchEmptyCouncilItem -Value $verdict.BlockingIssues)) {
                        $failures.Add('council findings still have synthesized blocking issues')
                    }
                    $conditions = [System.Collections.Generic.List[object]]::new()
                    foreach ($role in $councilRoles) {
                        $finding = @($verdict.Findings | Where-Object {
                                ([string]$_['Role']).Trim().ToLowerInvariant() -eq $role
                            })
                        if ($finding.Count -ne 1 -or
                            [string]$finding[0]['Verdict'] -notin @('Approve', 'Conditional', 'Concern', 'Block') -or
                            [string]$finding[0]['Risk'] -notmatch '^Risk:\s*(Low|Medium|High)$' -or
                            -not $finding[0].Contains('Blocking Issues') -or
                            -not $finding[0].Contains('Conditions')) {
                            $failures.Add("council finding for selected role '$role' is missing or invalid")
                            continue
                        }
                        $roleFinding = $finding[0]
                        if ($roleFinding['Verdict'] -eq 'Block' -or
                            $roleFinding['Risk'] -match '^Risk:\s*High$' -or
                            -not (Test-SquadWatchEmptyCouncilItem -Value $roleFinding['Blocking Issues'])) {
                            $failures.Add("council finding for '$role' blocks implementation under most-restrictive-wins synthesis")
                        }
                        if ($roleFinding['Verdict'] -eq 'Conditional' -or
                            -not (Test-SquadWatchEmptyCouncilItem -Value $roleFinding['Conditions'])) {
                            $requiresConditions = $true
                        }
                        if (-not (Test-SquadWatchEmptyCouncilItem -Value $roleFinding['Conditions'])) {
                            $conditions.Add([pscustomobject]@{
                                    Role = $role
                                    Text = [string]$roleFinding['Conditions']
                                })
                        }
                    }
                    $expectedVerdict = if ($requiresConditions) { 'Go-With-Conditions' } else { 'Go' }
                    if ($verdict.Verdict -cne $expectedVerdict) {
                        $failures.Add("council findings require '$expectedVerdict', not '$($verdict.Verdict)'")
                    }
                    if ($requiresConditions -and
                        (Test-SquadWatchEmptyCouncilItem -Value $verdict.Conditions)) {
                        $failures.Add('council findings have conditions without consolidated synthesis evidence')
                    }
                    $outstanding = -1
                    if (-not [int]::TryParse($verdict.ConditionsOutstanding, [ref]$outstanding) -or
                        $outstanding -lt 0) {
                        $failures.Add('council Conditions Outstanding must be a nonnegative integer')
                    }
                    elseif ($outstanding -gt 0) {
                        $unresolved = @(
                            foreach ($condition in $conditions) {
                                $attributed = "($($condition.Role)) $($condition.Text)"
                                if ($verdict.ConditionsSatisfied.IndexOf($attributed, [StringComparison]::OrdinalIgnoreCase) -lt 0 -and
                                    $verdict.ConditionsAccepted.IndexOf($attributed, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                                    $attributed
                                }
                            }
                        )
                        if ($conditions.Count -eq 0 -or $unresolved.Count -gt 0) {
                            $failures.Add('council conditions remain unresolved or unaccepted at handoff')
                        }
                    }
                }
            }
        }

        if ($roster.RoleAgents.ContainsKey('scribe')) {
            $scribeEvidence = 0
            foreach ($scribe in @($roster.RoleAgents['scribe'])) {
                $scribePath = Join-Path $historyRoot "$scribe.md"
                if (-not (Test-Path -LiteralPath $scribePath -PathType Leaf)) {
                    continue
                }
                $entry = Get-SquadWatchLatestHistoryEntry -Path $scribePath
                if (-not $entry -or
                    -not $entry.IsOrchestration -or
                    -not $entry.Turn -or
                    -not $entry.Request -or
                    -not $entry.DeliverableText -or
                    -not (Test-SquadWatchOutcomeComplete -Value $entry.Outcome) -or
                    $entry.Consumption -isnot [System.Collections.IDictionary]) {
                    $failures.Add("scribe history '$scribe.md' latest entry is not structured orchestration evidence")
                    continue
                }
                $requiredConsumption = @(
                    'model', 'model_source', 'priced_as', 'model_tier', 'internal_turns',
                    'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens', 'basis'
                )
                if (@($requiredConsumption | Where-Object { -not $entry.Consumption.Contains($_) }).Count -gt 0 -or
                    @($entry.Consumption.Keys | Where-Object { $_ -notin $requiredConsumption }).Count -gt 0) {
                    $failures.Add("scribe history '$scribe.md' latest Consumption block is incomplete")
                    continue
                }
                if (-not (Test-SquadWatchFileChanged -WorkspaceRoot $workspace -Path $scribePath -Baseline $baseline)) {
                    $failures.Add("scribe history '$scribe.md' was not changed during the authorized run")
                    continue
                }
                $scribeEvidence++
            }
            if ($scribeEvidence -eq 0) {
                $failures.Add("history is missing current structured evidence for the selected 'scribe' agent")
            }
        }
    }

    if ($failures.Count -gt 0) {
        throw "Squad Watch lifecycle handoff blocked:`n- $($failures -join "`n- ")"
    }

    [pscustomobject]@{
        MemberRoot        = $member
        Summary           = $summaryPath
        RunId             = $runId
        Stages            = @($stageRows | ForEach-Object { $_.Stage })
        HistoryReferences = $historyReferences
    }
}

function Invoke-SquadWatchGit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = @(& git -C $WorkspaceRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join "`n")"
    }

    @($output)
}

function New-SquadWatchHandoff {
    <#
    .SYNOPSIS
        Stages a Watch Mode run, treats an unchanged workspace as a legitimate
        no-change outcome, validates lifecycle evidence for material changes, and
        writes the binary patch consumed by the write-capable job.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string]$MemberRoot,

        [Parameter(Mandatory)]
        [string]$PatchPath,

        [string]$BaselinePath,

        [string]$ExpectedBaselineHash
    )

    $workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
    $patch = [System.IO.Path]::GetFullPath($PatchPath)

    if (-not $PSCmdlet.ShouldProcess($workspace, 'Stage Watch Mode changes and create the handoff patch')) {
        return
    }

    Add-SquadWatchTrustedExclude -Repository $workspace
    Invoke-SquadWatchGit -WorkspaceRoot $workspace -Arguments @('add', '-A') | Out-Null
    $trustedStaged = @(
        Invoke-SquadWatchGit -WorkspaceRoot $workspace -Arguments @('diff', '--cached', '--name-only') |
            Where-Object { ($_ -replace '\\', '/') -match '(?i)^\.squad-trusted(?:/|$)' }
    )
    if ($trustedStaged.Count -gt 0) {
        Invoke-SquadWatchGit -WorkspaceRoot $workspace -Arguments (@('reset', '-q', '--') + $trustedStaged) | Out-Null
        throw 'Refusing to stage .squad-trusted. The trusted checkout is excluded from publication.'
    }
    $auditExtra = @(
        Invoke-SquadWatchGit -WorkspaceRoot $workspace -Arguments @('diff', '--cached', '--name-only') |
            Where-Object {
                $normalized = $_ -replace '\\', '/'
                $normalized -match '^\.copilot-tracking/squad/watch-audit/.+' -and
                $normalized -notmatch '/watch-publication\.json$' -and
                $normalized -notmatch '/AUDIT\.md$'
            }
    )
    if ($auditExtra.Count -gt 0) {
        Invoke-SquadWatchGit -WorkspaceRoot $workspace -Arguments (@('reset', '-q', '--') + $auditExtra) | Out-Null
    }
    $stagedPaths = @(
        Invoke-SquadWatchGit -WorkspaceRoot $workspace -Arguments @(
            'diff', '--cached', '--name-only', '--diff-filter=ACDMRTUXB'
        ) | Where-Object { $_ }
    )

    if ($stagedPaths.Count -eq 0) {
        if (Test-Path -LiteralPath $patch) {
            Remove-Item -LiteralPath $patch -Force
        }
        return [pscustomobject]@{
            HasChanges          = $false
            HasMaterialChanges = $false
            StagedPaths         = @()
            MaterialChanges     = @()
            PatchPath           = $null
        }
    }

    $materialChanges = @($stagedPaths | Where-Object {
            $normalized = $_ -replace '\\', '/'
            $normalized -notmatch '^\.copilot-tracking/squad(?:/|$)' -and
            $normalized -notmatch '^\.changes/unreleased(?:/|$)'
        })

    if ($materialChanges.Count -gt 0) {
        if (-not $BaselinePath -or -not $ExpectedBaselineHash) {
            throw 'Squad Watch lifecycle handoff blocked: material changes require the trusted startup baseline.'
        }
        Test-SquadWatchLifecycle `
            -MemberRoot $MemberRoot `
            -WorkspaceRoot $workspace `
            -BaselinePath $BaselinePath `
            -ExpectedBaselineHash $ExpectedBaselineHash | Out-Null
    }

    $parent = Split-Path -Parent $patch
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Invoke-SquadWatchGit -WorkspaceRoot $workspace -Arguments @(
        'diff', '--cached', '--binary', "--output=$patch"
    ) | Out-Null

    [pscustomobject]@{
        HasChanges          = $true
        HasMaterialChanges = ($materialChanges.Count -gt 0)
        StagedPaths         = $stagedPaths
        MaterialChanges     = $materialChanges
        PatchPath           = $patch
    }
}

. (Join-Path $PSScriptRoot 'SquadWatch.Delivery.ps1')

Export-ModuleMember -Function @(
    'New-SquadWatchBaseline'
    'Enable-SquadWatchRuntimeOverlay'
    'Restore-SquadWatchRuntimeOverlay'
    'Test-SquadWatchLifecycle'
    'New-SquadWatchHandoff'
    'Get-SquadWatchDataFieldName'
    'ConvertTo-SquadWatchDataBlock'
    'ConvertFrom-SquadWatchDataBlock'
    'Test-SquadWatchOpenQuestions'
    'ConvertTo-SquadWatchOpenQuestionsMarkdown'
    'Test-SquadWatchProfileSelection'
    'Test-SquadWatchActorAuthorized'
    'Resolve-SquadWatchDelivery'
    'Update-SquadWatchMarkedBody'
    'Sync-SquadWatchPublication'
    'Assert-SquadWatchTrustedHelper'
    'Get-SquadWatchPublicationDecision'
    'Save-SquadWatchPublicationEvidence'
    'Get-SquadWatchCommittedQuestionsMarkdown'
    'Get-SquadWatchRequiredQuestionId'
    'Get-SquadWatchTeamRoster'
    'Get-SquadWatchRequiredRole'
    'ConvertTo-SquadWatchInertReview'
    'Add-SquadWatchForcedPublicationEvidence'
    'Assert-SquadWatchTrustedCheckout'
    'Add-SquadWatchTrustedExclude'
    'Get-SquadWatchProfileCatalog'
    'Resolve-SquadWatchCanonicalRoster'
    'Get-SquadWatchRequiredQuestionCoverage'
    'Get-SquadWatchClosingLabel'
    'Test-SquadWatchExpectedBranch'
    'Get-SquadWatchEvidenceQuestionsMarkdown'
    'Get-SquadWatchQuestionRecompute'
    'Get-SquadWatchCurrentRunMarkdown'
    'Get-SquadWatchCurrentRunBoundary'
    'Get-SquadWatchStagedQuestionsMarkdown'
    'Test-SquadWatchAppliedPublication'
    'Export-SquadWatchDispatchAudit'
)
